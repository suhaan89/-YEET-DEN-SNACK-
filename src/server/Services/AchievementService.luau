--[[
	AchievementService.luau
	Meilenstein-Achievements mit optionalen Roblox-Badges.

	- Eigener DataStore (Config.AchievementDataStore) mit Stats + Unlocked pro
	  Spieler -> nichts wird doppelt vergeben, auch nicht über Sessions hinweg.
	- Andere Services melden Fortschritt über AchievementService.Track(player,
	  stat, amount) bzw. TrackMax(player, stat, value). Vor dem Daten-Load
	  gemeldete Events werden gepuffert und nachgezogen.
	- Rebirths kommen NICHT über einen Hook in der Rebirth-Logik (die gehört
	  dem Kollegen), sondern über den leaderstats-Wert (repliziert von
	  PlayerService.Sync) – TrackMax zieht auch Alt-Spieler rückwirkend nach.
	- Tresor-Knacken: BaseService bleibt unangetastet – stattdessen wird
	  BaseService.TryCrack UMHÜLLT (gleiches Pattern wie der ApplySpeed-Wrapper
	  im PetService). Erfolg = Tresor des Besitzers ist danach kleiner.
	- Badge-Vergabe über BadgeService:AwardBadge, sobald echte BadgeIds in
	  Config.Achievements eingetragen sind (BadgeId = 0 -> nur intern).
]]

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AchievementService = {}

local DataService, BaseService -- in Init verdrahtet

local announceRemote: RemoteEvent
local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent

local store = nil
local records: { [Player]: any } = {} -- { Stats = {[stat]=n}, Unlocked = {[id]=true} }
local dirty: { [Player]: boolean } = {} -- nur geänderte Datensätze speichern
-- Events, die VOR dem Daten-Load reinkamen (z.B. Join-Rennen)
local pending: { [Player]: { { Stat: string, Amount: number, IsMax: boolean } } } = {}

local function defaultRecord()
	return { Stats = {}, Unlocked = {} }
end

-- ══════════ Freischalten ══════════

local function unlock(player: Player, def)
	local record = records[player]
	if not record or record.Unlocked[def.Id] then
		return
	end
	record.Unlocked[def.Id] = true
	dirty[player] = true

	notifyRemote:FireClient(player, ("🏅 ACHIEVEMENT: %s – %s"):format(def.Name, def.Desc))
	announceRemote:FireAllClients(("🏅 %s hat das Achievement '%s' freigeschaltet!"):format(player.Name, def.Name), "Legendary")
	sfxRemote:FireClient(player, "ding")

	-- Echte Roblox-Badge vergeben (nur wenn im Creator Dashboard angelegt + Id eingetragen)
	if def.BadgeId and def.BadgeId > 0 then
		task.spawn(function()
			local ok, err = pcall(function()
				BadgeService:AwardBadge(player.UserId, def.BadgeId)
			end)
			if not ok then
				warn("[AchievementService] Badge-Vergabe fehlgeschlagen:", def.Id, err)
			end
		end)
	end
end

local function checkUnlocks(player: Player)
	local record = records[player]
	if not record then
		return
	end
	for _, def in Config.Achievements do
		if not record.Unlocked[def.Id] and (record.Stats[def.Stat] or 0) >= def.Goal then
			unlock(player, def)
		end
	end
end

-- ══════════ Öffentliche API (rufen andere Services auf) ══════════

-- Zähler um `amount` erhöhen (z.B. "Banked" +1 pro Einlagerung)
function AchievementService.Track(player: Player, stat: string, amount: number)
	local record = records[player]
	if not record then
		local queue = pending[player]
		if not queue then
			queue = {}
			pending[player] = queue
		end
		table.insert(queue, { Stat = stat, Amount = amount, IsMax = false })
		return
	end
	record.Stats[stat] = (record.Stats[stat] or 0) + amount
	dirty[player] = true
	checkUnlocks(player)
end

-- Zähler auf mindestens `value` heben (für absolute Werte wie Rebirths)
function AchievementService.TrackMax(player: Player, stat: string, value: number)
	local record = records[player]
	if not record then
		local queue = pending[player]
		if not queue then
			queue = {}
			pending[player] = queue
		end
		table.insert(queue, { Stat = stat, Amount = value, IsMax = true })
		return
	end
	if value > (record.Stats[stat] or 0) then
		record.Stats[stat] = value
		dirty[player] = true
		checkUnlocks(player)
	end
end

-- ══════════ Laden/Speichern ══════════

local function load(player: Player)
	local record = defaultRecord()
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("Ach_" .. player.UserId)
		end)
		if ok and typeof(saved) == "table" then
			record.Stats = typeof(saved.Stats) == "table" and saved.Stats or {}
			record.Unlocked = typeof(saved.Unlocked) == "table" and saved.Unlocked or {}
		elseif not ok then
			warn("[AchievementService] Laden fehlgeschlagen für", player.Name, saved)
		end
	end
	records[player] = record

	-- Gepufferte Events nachziehen
	local queue = pending[player]
	pending[player] = nil
	if queue then
		for _, item in queue do
			if item.IsMax then
				AchievementService.TrackMax(player, item.Stat, item.Amount)
			else
				AchievementService.Track(player, item.Stat, item.Amount)
			end
		end
	end
	checkUnlocks(player)
end

local function save(player: Player)
	local record = records[player]
	if not record or not store or not dirty[player] then
		return
	end
	dirty[player] = nil
	local ok, err = pcall(function()
		store:SetAsync("Ach_" .. player.UserId, record)
	end)
	if not ok then
		warn("[AchievementService] Speichern fehlgeschlagen für", player.Name, err)
	end
end

-- ══════════ Init ══════════

function AchievementService.Init(services)
	DataService = services.DataService
	BaseService = services.BaseService

	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	-- Fürs UI: eigene Stats + Freischaltungen
	(Remotes.Get("GetAchievements") :: RemoteFunction).OnServerInvoke = function(player: Player)
		local record = records[player]
		if not record then
			return nil
		end
		return { Stats = record.Stats, Unlocked = record.Unlocked }
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.AchievementDataStore)
	end)
	if ok then
		store = result
	else
		warn("[AchievementService] Kein DataStore-Zugriff – Achievements werden NICHT gespeichert.")
	end

	-- Tresor-Knacken zählen, OHNE BaseService anzufassen: TryCrack umhüllen.
	-- Erfolgskriterium: der Tresor des Besitzers ist nach dem Aufruf kleiner
	-- (alle Fehlschläge – Cooldown, leer, eigener Tresor – ändern nichts).
	local baseTryCrack = BaseService.TryCrack
	BaseService.TryCrack = function(thief: Player, base)
		local owner = base.Owner
		local profile = owner and DataService.Get(owner)
		local before = profile and #profile.Vault or 0
		baseTryCrack(thief, base)
		if profile and #profile.Vault < before then
			AchievementService.Track(thief, "Cracks", 1)
		end
	end

	local function onPlayerAdded(player: Player)
		task.spawn(load, player)

		-- Rebirth-Meilensteine über den replizierten leaderstats-Wert
		-- (kein Eingriff in die Rebirth-Logik nötig; zieht Alt-Spieler nach)
		task.spawn(function()
			local stats = player:WaitForChild("leaderstats", 20)
			local rebirths = stats and stats:WaitForChild("Rebirths", 20) :: IntValue?
			if not rebirths then
				return
			end
			rebirths.Changed:Connect(function(value)
				AchievementService.TrackMax(player, "Rebirths", value)
			end)
			if rebirths.Value > 0 then
				AchievementService.TrackMax(player, "Rebirths", rebirths.Value)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		records[player] = nil
		dirty[player] = nil
		pending[player] = nil
	end)

	-- Autosave (gleiche Kadenz wie der DataService)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in records do
				task.spawn(save, player)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(1)
			return
		end
		for player in records do
			save(player)
		end
	end)
end

return AchievementService
