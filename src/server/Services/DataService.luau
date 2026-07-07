--[[
	DataService.luau
	Laden/Speichern der Spielerdaten über DataStore.
	- Profil pro Spieler (Cash, Rebirths, Upgrades, Tresor-Inhalt)
	- Autosave, Save beim Verlassen, BindToClose für Server-Shutdown
	- Alle DataStore-Aufrufe in pcall (Studio ohne API-Zugriff crasht sonst)
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local store = nil
local profiles: { [Player]: any } = {}

local function defaultProfile()
	return {
		Cash = Config.StartCash,
		Rebirths = 0,
		Upgrades = { Wurfkraft = 0, SlapPower = 0, Tempo = 0, Schloss = 0 },
		Vault = {}, -- Liste von Snack-Namen (Strings), Details stehen in SnackTypes
		TotalYeets = 0,
		Pets = {}, -- gesammelte Pets (aus Eiern): { [petId] = true }
		EquippedPet = "", -- LEGACY (Alt-Daten): einzelnes Pet – wird beim Join in EquippedPets migriert
		EquippedPets = {}, -- Liste aktiver Pet-Ids (max. Config.PetMaxEquipped)
		Trails = {}, -- gekaufte Trails: { [trailId] = true }
		EquippedTrail = "", -- Id des aktiven Trails ("" = keiner)
		Skins = {}, -- gekaufte Charakter-Skins: { [skinId] = true }
		EquippedSkin = "", -- Id des aktiven Skins ("" = keiner)
		BaseLevel = 1, -- Tycoon-Ausbaustufe der Basis (Index in Config.BaseLevels)
		-- Season-Pass-Fortschritt (resettet, wenn Id nicht mehr zu Config.SeasonPass.Id passt)
		SeasonPass = {
			Id = "", -- welche Season dieser Fortschritt gehört
			Xp = 0, -- Gesamt-XP dieser Season
			GrantedFree = 0, -- bis zu dieser Stufe wurden Free-Belohnungen ausgezahlt
			GrantedPremium = 0, -- dito Premium-Spur
			Premium = false, -- Premium-Pass freigeschaltet (Gamepass)
		},
	}
end

-- Fehlende Felder aus dem Default auffüllen (für spätere Daten-Migrationen)
local function reconcile(data: any, template: any)
	for key, value in template do
		if data[key] == nil then
			data[key] = value
		elseif typeof(value) == "table" and typeof(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
end

local function load(player: Player)
	local profile = defaultProfile()
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("Player_" .. player.UserId)
		end)
		if ok and typeof(saved) == "table" then
			reconcile(saved, profile)
			profile = saved
		elseif not ok then
			warn("[DataService] Laden fehlgeschlagen für", player.Name, saved)
		end
	end
	profiles[player] = profile
end

local function save(player: Player)
	local profile = profiles[player]
	if not profile or not store then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("Player_" .. player.UserId, profile)
	end)
	if not ok then
		warn("[DataService] Speichern fehlgeschlagen für", player.Name, err)
	end
end

function DataService.Get(player: Player)
	return profiles[player]
end

-- Wartet, bis das Profil geladen ist (für Services, die beim Join zugreifen)
function DataService.WaitFor(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	while not profiles[player] and os.clock() < deadline and player.Parent do
		task.wait(0.1)
	end
	return profiles[player]
end

-- Debug-Hook: Profil SOFORT speichern (fürs Test-Menü – prüft, ob Speichern
-- gerade funktioniert, ohne auf Autosave/Shutdown zu warten).
-- Gibt (ok, Fehlertext) zurück.
function DataService.ForceSave(player: Player): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "Kein Profil geladen."
	end
	if not store then
		return false, "Kein DataStore-Zugriff (Studio-API aktivieren!)."
	end
	local ok, err = pcall(function()
		store:SetAsync("Player_" .. player.UserId, profile)
	end)
	return ok, if ok then nil else tostring(err)
end

function DataService.GetMultiplier(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 1
	end
	return 1 + profile.Rebirths * Config.RebirthBonus
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] Kein DataStore-Zugriff (Studio-API aktivieren!) – Daten werden NICHT gespeichert.")
	end

	Players.PlayerAdded:Connect(load)
	-- Spieler, die schon da sind (Studio-Play-Solo-Race)
	for _, player in Players:GetPlayers() do
		if not profiles[player] then
			task.spawn(load, player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
	end)

	-- Autosave-Schleife
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(save, player)
			end
		end
	end)

	-- Beim Server-Shutdown alle speichern
	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(1) -- Studio: kurz Zeit lassen
			return
		end
		for player in profiles do
			save(player)
		end
	end)
end

return DataService
