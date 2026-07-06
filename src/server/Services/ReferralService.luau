--[[
	ReferralService.luau
	Einladungssystem: "YEET-<UserId>"-Codes, dauerhafte Verknüpfung,
	Belohnung für den EINLADENDEN, sobald der Eingeladene Rebirth 1 schafft.

	Server-autoritativ:
	- Der Client kann nur einen Code-String schicken; validiert (existiert der
	  User? kein Selbst-Invite? Spieler wirklich neu?) und gespeichert wird
	  ausschließlich hier.
	- Verknüpfung liegt im Profil des EINGELADENEN (profile.Referral.ReferredBy)
	  – lazy angelegt, DataService bleibt unberührt.
	- Meilenstein-Gutschrift für Offline-Einlader läuft über einen eigenen
	  Pending-DataStore (Key "Pending_<UserId>", Wert = Anzahl unabgeholter
	  Erfolge, atomar via UpdateAsync). Beim Join wird abgeräumt.
	- Zusätzlich: Join über einen Einladungs-Link mit LaunchData "ref=<UserId>"
	  löst den Code automatisch ein.
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

local pendingStore = nil -- DataStore für Offline-Gutschriften (nil ohne API-Zugriff)

-- Fehlende Referral-Felder im Profil anlegen (Alt-Spielstände!)
local function ensureFields(profile)
	if typeof(profile.Referral) ~= "table" then
		profile.Referral = {
			ReferredBy = 0, -- UserId des Einladenden (0 = niemand)
			MilestoneReported = false, -- Gutschrift für meinen Einladenden schon raus?
			Invited = 0, -- so viele meiner Eingeladenen haben den Meilenstein geschafft
		}
	end
	return profile.Referral
end

function ReferralService.CodeFor(userId: number): string
	return ("YEET-%d"):format(userId)
end

-- "YEET-12345", "yeet-12345" oder nur "12345" -> UserId (oder nil)
local function parseCode(code: string): number?
	local cleaned = code:gsub("%s", ""):upper()
	local idText = cleaned:match("^YEET%-(%d+)$") or cleaned:match("^(%d+)$")
	return idText and tonumber(idText)
end

-- ══════════ Belohnung für den Einladenden ══════════

-- Zahlt `count` Erfolgs-Belohnungen an einen ONLINE-Einlader aus
local function grantInviterReward(inviter: Player, count: number)
	local profile = DataService.Get(inviter)
	if not profile or count <= 0 then
		return
	end
	local referral = ensureFields(profile)
	referral.Invited += count

	local cash = Config.Referral.RewardCash * count
	PlayerService.AddCash(inviter, cash)
	local eggDef = Config.EggsById[Config.Referral.RewardEgg]
	for _ = 1, count do
		local result = PetService.GrantEgg(inviter, Config.Referral.RewardEgg)
		if result.ok then
			notifyRemote:FireClient(inviter, ("🥚 Einladungs-Bonus-Ei (%s): %s"):format(eggDef and eggDef.Name or "?", result.msg))
		end
	end
	notifyRemote:FireClient(
		inviter,
		("🎁 EINLADUNG ERFOLGREICH! %d Freund(e) haben Rebirth %d erreicht: +%d💰!"):format(
			count,
			Config.Referral.MilestoneRebirths,
			cash
		)
	)
	sfxRemote:FireClient(inviter, "ding")
end

-- Erfolg für einen (evtl. offline) Einlader verbuchen
local function creditInviter(inviterUserId: number, invitedName: string)
	-- Online im selben Server? Direkt auszahlen, kein DataStore nötig.
	local inviter = Players:GetPlayerByUserId(inviterUserId)
	if inviter and DataService.Get(inviter) then
		grantInviterReward(inviter, 1)
		announceRemote:FireAllClients(
			("🎁 %s wurde von %s eingeladen und hat Rebirth geschafft – Einladungs-Bonus kassiert!"):format(
				invitedName,
				inviter.Name
			),
			"Legendary"
		)
		return
	end

	-- Sonst: Pending-Zähler im Referral-Store hochzählen (atomar)
	if not pendingStore then
		warn("[ReferralService] Kein DataStore-Zugriff – Offline-Gutschrift geht verloren!")
		return
	end
	local ok, err = pcall(function()
		pendingStore:UpdateAsync("Pending_" .. inviterUserId, function(current)
			return (tonumber(current) or 0) + 1
		end)
	end)
	if not ok then
		warn("[ReferralService] Pending-Gutschrift fehlgeschlagen für", inviterUserId, err)
	end
end

-- Beim Join: aufgelaufene Offline-Gutschriften abholen (lesen + auf 0 setzen)
local function claimPending(player: Player)
	if not pendingStore then
		return
	end
	local claimed = 0
	local ok, err = pcall(function()
		pendingStore:UpdateAsync("Pending_" .. player.UserId, function(current)
			claimed = tonumber(current) or 0
			return 0
		end)
	end)
	if not ok then
		warn("[ReferralService] Pending-Abholung fehlgeschlagen für", player.Name, err)
		return
	end
	if claimed > 0 and player.Parent then
		grantInviterReward(player, claimed)
	end
end

-- ══════════ Code einlösen ══════════

local function redeem(player: Player, rawCode: any)
	if typeof(rawCode) ~= "string" or #rawCode > 40 then
		return { ok = false, msg = "Das sieht nicht nach einem Code aus." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	local referral = ensureFields(profile)

	local inviterUserId = parseCode(rawCode)
	if not inviterUserId then
		return { ok = false, msg = "Ungültiger Code. Format: YEET-12345" }
	end
	if inviterUserId == player.UserId then
		return { ok = false, msg = "Netter Versuch – dich selbst einladen zählt nicht! 😄" }
	end
	if referral.ReferredBy ~= 0 then
		return { ok = false, msg = "Du wurdest schon von jemandem eingeladen!" }
	end
	-- Nur ECHTE Neulinge dürfen einlösen, sonst wäre der Meilenstein
	-- (Rebirth 1) für Bestands-Spieler sofort erfüllt -> Farm-Exploit.
	if profile.Rebirths > 0 then
		return { ok = false, msg = "Codes können nur NEUE Spieler (vor dem ersten Rebirth) einlösen." }
	end

	-- Existiert der Einladende überhaupt? (Web-Call, validiert die UserId)
	local ok, inviterName = pcall(function()
		return Players:GetNameFromUserIdAsync(inviterUserId)
	end)
	if not ok or typeof(inviterName) ~= "string" then
		return { ok = false, msg = "Diesen Spieler gibt es nicht – Code nochmal prüfen!" }
	end

	referral.ReferredBy = inviterUserId
	notifyRemote:FireClient(
		player,
		("🤝 Verknüpft! Schaffst du Rebirth %d, kassiert %s eine fette Belohnung."):format(
			Config.Referral.MilestoneRebirths,
			inviterName
		)
	)
	return { ok = true, msg = ("Code von %s eingelöst – viel Spaß beim YEETen!"):format(inviterName) }
end

-- ══════════ Info fürs UI ══════════

local function getInfo(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local referral = ensureFields(profile)
	return {
		Code = ReferralService.CodeFor(player.UserId),
		Invited = referral.Invited,
		ReferredBy = referral.ReferredBy,
		CanRedeem = referral.ReferredBy == 0 and profile.Rebirths == 0,
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

	(Remotes.Get("RedeemReferral") :: RemoteFunction).OnServerInvoke = redeem;
	(Remotes.Get("GetReferralInfo") :: RemoteFunction).OnServerInvoke = getInfo

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Referral.DataStoreName)
	end)
	if ok then
		pendingStore = result
	else
		warn("[ReferralService] Kein DataStore-Zugriff – Referral-Gutschriften nur bei Online-Einladern.")
	end

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitFor(player)
			if not profile then
				return
			end
			ensureFields(profile)

			-- Einladungs-Link? LaunchData "ref=<UserId>" löst automatisch ein.
			local joinData = player:GetJoinData()
			local launchData = joinData and joinData.LaunchData
			if typeof(launchData) == "string" then
				local refId = launchData:match("ref=(%d+)")
				if refId then
					redeem(player, refId)
				end
			end

			-- Aufgelaufene Offline-Gutschriften abholen
			claimPending(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Meilenstein-Wache: hat ein Eingeladener seinen Rebirth geschafft,
	-- wird der Einladende EINMALIG belohnt (MilestoneReported schützt
	-- gegen Doppel-Vergabe, übersteht auch Rejoins).
	task.spawn(function()
		while true do
			task.wait(Config.Referral.CheckInterval)
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if not profile then
					continue
				end
				local referral = ensureFields(profile)
				if
					referral.ReferredBy ~= 0
					and not referral.MilestoneReported
					and profile.Rebirths >= Config.Referral.MilestoneRebirths
				then
					referral.MilestoneReported = true
					notifyRemote:FireClient(player, "🎁 Rebirth geschafft – dein Einlader bekommt seine Belohnung!")
					task.spawn(creditInviter, referral.ReferredBy, player.Name)
				end
			end
		end
	end)
end

return ReferralService
