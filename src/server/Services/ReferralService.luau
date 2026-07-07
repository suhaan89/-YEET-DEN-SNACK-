--[[
	ReferralService.luau
	Einladungs-System: Jeder Spieler hat einen festen Code ("SNACK-<UserId>").

	Ablauf:
	1. Neuer Spieler (vor Rebirth 1) löst den Code eines Freundes ein ->
	   dauerhafte Verknüpfung (InvitedBy) im eigenen DataStore.
	2. Schafft der Eingeladene Rebirth 1 (Meilenstein, erkannt über den
	   replizierten leaderstats-Wert – KEIN Eingriff in die Rebirth-Logik),
	   bekommt der EINLADER Cash + ein Gratis-Ei.
	3. Ist der Einlader gerade offline/in einem anderen Server, wird die
	   Belohnung als PendingRewards vermerkt und beim nächsten Join ausgezahlt.

	Server-autoritativ: Der Client schickt nur den Code-String; Verknüpfung,
	Meilenstein-Erkennung und Auszahlung passieren ausschließlich hier.
	ALLE DataStore-Schreibzugriffe laufen über UpdateAsync (merge-sicher,
	weil fremde Server denselben Einlader-Datensatz anfassen können).

	Datensatz pro Spieler ("Ref_<UserId>"):
	  InvitedBy      = UserId des Einladers (0 = niemand)
	  Completed      = eigener Meilenstein wurde schon verrechnet
	  SuccessCount   = wie viele Eingeladene den Meilenstein geschafft haben
	  PendingRewards = noch nicht ausgezahlte Belohnungen (Einlader offline)
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ReferralService = {}

local DataService, PlayerService, PetService -- in Init verdrahtet

local notifyRemote: RemoteEvent
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

local store = nil
local records: { [Player]: any } = {} -- gecachter eigener Datensatz

local function defaultRecord()
	return { InvitedBy = 0, Completed = false, SuccessCount = 0, PendingRewards = 0 }
end

local function keyFor(userId: number): string
	return "Ref_" .. userId
end

local function codeFor(userId: number): string
	return Config.ReferralCodePrefix .. userId
end

-- Merge-sicherer Schreibzugriff; gibt (ok, neuer Datensatz) zurück
local function updateRecord(userId: number, transform: (any) -> any): (boolean, any)
	if not store then
		return false, nil
	end
	local result = nil
	local ok, err = pcall(function()
		result = store:UpdateAsync(keyFor(userId), function(old)
			local record = if typeof(old) == "table" then old else defaultRecord()
			for field, value in defaultRecord() do
				if record[field] == nil then
					record[field] = value
				end
			end
			return transform(record)
		end)
	end)
	if not ok then
		warn("[ReferralService] UpdateAsync fehlgeschlagen für", userId, err)
		return false, nil
	end
	return true, result
end

-- "SNACK-12345", "snack-12345" oder "12345" -> 12345 (oder nil)
local function parseCode(code: string): number?
	local cleaned = code:gsub("%s", ""):upper()
	local prefix = Config.ReferralCodePrefix:upper()
	if cleaned:sub(1, #prefix) == prefix then
		cleaned = cleaned:sub(#prefix + 1)
	end
	local userId = tonumber(cleaned)
	if userId and userId == math.floor(userId) and userId > 0 then
		return userId
	end
	return nil
end

-- ══════════ Belohnung an den Einlader ══════════

-- Zahlt `count` Belohnungen an einen ONLINE-Spieler aus (Cash + Gratis-Ei)
local function payoutOnline(inviter: Player, count: number)
	for _ = 1, count do
		PlayerService.AddCash(inviter, Config.ReferralRewardCash)
		local result = PetService.GrantEgg(inviter, Config.ReferralRewardEgg)
		notifyRemote:FireClient(
			inviter,
			("🎉 EINLADUNGS-BONUS: +%d💰 und ein Gratis-Ei! %s"):format(
				Config.ReferralRewardCash,
				result.ok and result.msg or ""
			)
		)
	end
	sfxRemote:FireClient(inviter, "ding")
end

-- Meilenstein des Eingeladenen verrechnen (genau einmal)
local function completeReferral(player: Player)
	local record = records[player]
	if not record or record.Completed or record.InvitedBy <= 0 then
		return
	end
	-- Eigenen Datensatz zuerst dauerhaft als "verrechnet" markieren
	-- (UpdateAsync prüft nochmal, falls zwei Server gleichzeitig rennen)
	local alreadyDone = false
	local ok, saved = updateRecord(player.UserId, function(data)
		if data.Completed then
			alreadyDone = true
		end
		data.Completed = true
		return data
	end)
	if not ok then
		return -- DataStore down: beim nächsten Rebirth-Event erneut versuchen
	end
	records[player] = saved or record
	records[player].Completed = true
	if alreadyDone then
		return
	end

	local inviterId = record.InvitedBy

	-- Einlader gutschreiben: Zähler hoch; offline zusätzlich als Pending vormerken
	local inviter: Player? = Players:GetPlayerByUserId(inviterId)
	local inviterOnline = inviter ~= nil and inviter.Parent ~= nil
	local okInviter, inviterRecord = updateRecord(inviterId, function(data)
		data.SuccessCount += 1
		if not inviterOnline then
			data.PendingRewards += 1
		end
		return data
	end)
	if okInviter and inviter and inviterRecord and records[inviter] then
		records[inviter] = inviterRecord -- Cache frisch halten (fürs UI)
	end

	if inviter and inviterOnline then
		payoutOnline(inviter, 1)
		announceRemote:FireAllClients(
			("🤝 %s hat Rebirth 1 geschafft – Einlader %s kassiert die Prämie!"):format(player.Name, inviter.Name),
			"Legendary"
		)
	end
	notifyRemote:FireClient(player, "🤝 Dein Einlader hat gerade seine Einladungs-Prämie bekommen – danke dir!")
end

-- ══════════ Remote-Handler ══════════

local function getReferralInfo(player: Player)
	local record = records[player]
	if not record then
		return nil
	end
	local profile = DataService.Get(player)
	return {
		Code = codeFor(player.UserId),
		SuccessCount = record.SuccessCount,
		InvitedBy = record.InvitedBy,
		-- Einlösen geht nur für "frische" Spieler: noch nicht verknüpft + vor Rebirth 1
		CanRedeem = record.InvitedBy == 0 and (profile == nil or profile.Rebirths == 0),
	}
end

local function redeemReferral(player: Player, code: any)
	if typeof(code) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	local record = records[player]
	if not record then
		return { ok = false, msg = "Daten noch nicht geladen – versuch's gleich nochmal." }
	end
	if not store then
		return { ok = false, msg = "Speicher gerade nicht erreichbar – später nochmal versuchen." }
	end
	if record.InvitedBy > 0 then
		return { ok = false, msg = "Du hast schon einen Einladungs-Code eingelöst!" }
	end

	local profile = DataService.Get(player)
	if profile and profile.Rebirths > 0 then
		return { ok = false, msg = "Einladungs-Codes sind nur für NEUE Spieler (vor dem ersten Rebirth)." }
	end

	local inviterId = parseCode(code)
	if not inviterId then
		return { ok = false, msg = ("Das sieht nicht nach einem Code aus (Format: %s12345)."):format(Config.ReferralCodePrefix) }
	end
	if inviterId == player.UserId then
		return { ok = false, msg = "Netter Versuch – dich selbst einladen zählt nicht! 😄" }
	end

	-- Gibt es den Einlader überhaupt? (validiert die UserId)
	local okName, inviterName = pcall(function()
		return Players:GetNameFromUserIdAsync(inviterId)
	end)
	if not okName then
		return { ok = false, msg = "Diesen Code kennt hier niemand – Tippfehler?" }
	end

	-- Dauerhaft verknüpfen (merge-sicher; falls parallel schon verknüpft: abbrechen)
	local alreadyLinked = false
	local ok, saved = updateRecord(player.UserId, function(data)
		if data.InvitedBy > 0 then
			alreadyLinked = true
		else
			data.InvitedBy = inviterId
		end
		return data
	end)
	if not ok then
		return { ok = false, msg = "Speichern fehlgeschlagen – später nochmal versuchen." }
	end
	if alreadyLinked then
		return { ok = false, msg = "Du hast schon einen Einladungs-Code eingelöst!" }
	end
	records[player] = saved or record
	records[player].InvitedBy = inviterId

	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter then
		notifyRemote:FireClient(inviter, ("🤝 %s ist über deinen Code beigetreten! Prämie gibt's bei Rebirth 1."):format(player.Name))
	end
	return {
		ok = true,
		msg = ("Verknüpft mit %s! Schaffst du Rebirth 1, bekommt dein Einlader die Prämie."):format(inviterName),
	}
end

-- ══════════ Init ══════════

function ReferralService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	PetService = services.PetService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	(Remotes.Get("GetReferralInfo") :: RemoteFunction).OnServerInvoke = getReferralInfo;
	(Remotes.Get("RedeemReferral") :: RemoteFunction).OnServerInvoke = redeemReferral

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.ReferralDataStore)
	end)
	if ok then
		store = result
	else
		warn("[ReferralService] Kein DataStore-Zugriff – Referrals werden NICHT gespeichert.")
	end

	local function onPlayerAdded(player: Player)
		-- Eigenen Datensatz laden + offene Belohnungen abholen (merge-sicher:
		-- UpdateAsync nullt Pending und liefert den alten Stand zurück)
		task.spawn(function()
			local pendingToPay = 0
			local okLoad, saved = updateRecord(player.UserId, function(data)
				pendingToPay = data.PendingRewards
				data.PendingRewards = 0
				return data
			end)
			if not okLoad then
				records[player] = records[player] or defaultRecord() -- offline-Fallback (Studio ohne API)
				return
			end
			if not player.Parent then
				return
			end
			records[player] = saved or defaultRecord()
			if pendingToPay > 0 then
				DataService.WaitFor(player) -- Cash/Eier brauchen das Profil
				if player.Parent then
					payoutOnline(player, pendingToPay)
				end
			end
		end)

		-- Meilenstein "Rebirth 1" über den replizierten leaderstats-Wert erkennen
		task.spawn(function()
			local stats = player:WaitForChild("leaderstats", 20)
			local rebirths = stats and stats:WaitForChild("Rebirths", 20) :: IntValue?
			if not rebirths then
				return
			end
			rebirths.Changed:Connect(function(value)
				if value >= 1 then
					task.spawn(completeReferral, player)
				end
			end)
			-- Alt-Fall: Spieler war beim Einlösen verknüpft, hat aber in einer
			-- anderen Session gerebirtht, bevor der Server es mitbekam
			if rebirths.Value >= 1 then
				task.spawn(completeReferral, player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
end

return ReferralService
