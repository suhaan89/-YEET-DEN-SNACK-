--[[
	GemService.luau
	Juwelen (💎) – die zweite Währung. Verdienbar AUSSCHLIESSLICH im Parkour!

	- Eigener DataStore (Config.ParkourDataStore) NEBEN dem Haupt-Profil,
	  gleiches Muster wie AchievementService/HousingService – das Cash-Profil
	  des Kollegen bleibt komplett unangetastet.
	- Ein Datensatz pro Spieler: Juwelen-Stand, Parkour-Freischaltung,
	  persönliche Bestzeiten, Meister-Belohnungs-Flag.
	- Anzeige: leaderstats-IntValue "Juwelen" (hängt sich an den vom
	  PlayerService erstellten Ordner dran) + Attribute Gems/ParkourUnlocked
	  (replizieren automatisch -> HUD & Portal-Sperr-Optik lesen nur die).
	- Ausgeben: TrySpendGems() nutzen StyleService (Trails/Skins) und
	  PetService (Juwelen-Ei).
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GemService = {}

local store = nil
local records: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

local function defaultRecord()
	return {
		Gems = 0,
		Unlocked = 1, -- höchster BETRETBARER Parcours-Index (1 = nur der erste)
		BestTimes = {}, -- { [courseId] = Sekunden }
		MasterGranted = false, -- Juwelensturm-Trail schon vergeben?
	}
end

-- ══════════ Anzeige-Sync ══════════

-- leaderstats/Attribute aus dem Datensatz aktualisieren
function GemService.Sync(player: Player)
	local record = records[player]
	if not record then
		return
	end
	player:SetAttribute("Gems", record.Gems)
	player:SetAttribute("ParkourUnlocked", record.Unlocked)

	local stats = player:FindFirstChild("leaderstats")
	local gemValue = stats and stats:FindFirstChild("Juwelen") :: IntValue?
	if gemValue then
		gemValue.Value = math.floor(record.Gems)
	end
end

-- ══════════ Öffentliche API ══════════

function GemService.Get(player: Player)
	return records[player]
end

-- Wartet, bis der Datensatz geladen ist (für Join-Rennen im ParkourService)
function GemService.WaitFor(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	while not records[player] and os.clock() < deadline and player.Parent do
		task.wait(0.1)
	end
	return records[player]
end

function GemService.GetGems(player: Player): number
	local record = records[player]
	return record and record.Gems or 0
end

function GemService.AddGems(player: Player, amount: number)
	local record = records[player]
	if not record then
		return
	end
	record.Gems = math.max(0, record.Gems + amount)
	dirty[player] = true
	GemService.Sync(player)
end

-- Gibt true zurück, wenn bezahlt werden konnte
function GemService.TrySpendGems(player: Player, amount: number): boolean
	local record = records[player]
	if not record or record.Gems < amount then
		return false
	end
	GemService.AddGems(player, -amount)
	return true
end

-- Für ParkourService: Datensatz wurde direkt geändert (Unlocked/BestTimes/...)
function GemService.MarkDirty(player: Player)
	if records[player] then
		dirty[player] = true
	end
end

-- ══════════ Laden/Speichern ══════════

local function load(player: Player)
	local record = defaultRecord()
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("Pk_" .. player.UserId)
		end)
		if ok and typeof(saved) == "table" then
			record.Gems = typeof(saved.Gems) == "number" and math.max(0, saved.Gems) or 0
			record.Unlocked = typeof(saved.Unlocked) == "number"
					and math.clamp(saved.Unlocked, 1, #Config.ParkourCourses)
				or 1
			record.BestTimes = typeof(saved.BestTimes) == "table" and saved.BestTimes or {}
			record.MasterGranted = saved.MasterGranted == true
		elseif not ok then
			warn("[GemService] Laden fehlgeschlagen für", player.Name, saved)
		end
	end
	records[player] = record
	GemService.Sync(player)
end

local function save(player: Player)
	local record = records[player]
	if not record or not store or not dirty[player] then
		return
	end
	dirty[player] = nil
	local ok, err = pcall(function()
		store:SetAsync("Pk_" .. player.UserId, record)
	end)
	if not ok then
		warn("[GemService] Speichern fehlgeschlagen für", player.Name, err)
	end
end

-- ══════════ Init ══════════

function GemService.Init(_services)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.ParkourDataStore)
	end)
	if ok then
		store = result
	else
		warn("[GemService] Kein DataStore-Zugriff – Juwelen/Parkour werden NICHT gespeichert.")
	end

	local function onPlayerAdded(player: Player)
		task.spawn(load, player)

		-- Juwelen-Zeile ins Roblox-Leaderboard hängen (Ordner baut der PlayerService)
		task.spawn(function()
			local stats = player:WaitForChild("leaderstats", 20)
			if not stats or stats:FindFirstChild("Juwelen") then
				return
			end
			local gems = Instance.new("IntValue")
			gems.Name = "Juwelen"
			gems.Parent = stats
			GemService.Sync(player)
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

return GemService
