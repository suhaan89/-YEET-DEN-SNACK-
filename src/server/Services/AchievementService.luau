--[[
	AchievementService.luau
	Meilenstein-Belohnungen (Config.Achievements) mit optionalen echten
	Roblox-Badges (BadgeService:AwardBadge, sobald BadgeIds eingetragen sind).

	- Serverseitiges Tracking im Profil: profile.Achievements = { [id] = true }
	  (einmalige Vergabe, übersteht Rejoins) + profile.AchStats für kumulative
	  Zähler (Banked/Cracks/Golden), die nirgendwo sonst gezählt werden.
	- Beide Felder werden hier LAZY angelegt – DataService bleibt unberührt,
	  der Save schreibt sie automatisch mit (gleiche Profil-Tabelle).
	- Stats aus dem Profil (Rebirths, TotalYeets, BaseLevel, Pets) werden
	  per Poll-Schleife geprüft; Zähler-Stats feuern sofort über AddStat.
	- BaseService gehört dem Kollegen: statt ihn umzubauen, werden
	  AddToVault/TryCrack von außen UMHÜLLT (gleiches Muster wie der
	  ApplySpeed-Wrapper im PetService).
]]

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AchievementService = {}

local DataService -- in Init verdrahtet

local unlockedRemote: RemoteEvent
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

-- Fehlende Achievement-Felder im Profil anlegen (Alt-Spielstände!)
local function ensureFields(profile)
	if typeof(profile.Achievements) ~= "table" then
		profile.Achievements = {}
	end
	if typeof(profile.AchStats) ~= "table" then
		profile.AchStats = { Banked = 0, Cracks = 0, Golden = 0 }
	end
	return profile
end

-- Aktuellen Wert eines Achievement-Stats ermitteln
local function getStat(profile, stat: string): number
	if stat == "Rebirths" then
		return profile.Rebirths or 0
	elseif stat == "TotalYeets" then
		return profile.TotalYeets or 0
	elseif stat == "BaseLevel" then
		return profile.BaseLevel or 1
	elseif stat == "LegendaryPet" then
		for petId in profile.Pets do
			local def = Config.EggPetsById[petId]
			if def and (def.Rarity == "Legendary" or def.Rarity == "Mythic") then
				return 1
			end
		end
		return 0
	end
	return profile.AchStats[stat] or 0
end

local function award(player: Player, profile, def)
	profile.Achievements[def.Id] = true

	-- Popup nur an den Spieler; große Meilensteine zusätzlich server-weit
	unlockedRemote:FireClient(player, def.Name, def.Desc)
	sfxRemote:FireClient(player, "ding")
	if def.Announce then
		announceRemote:FireAllClients(
			("🏆 %s hat das Achievement '%s' freigeschaltet!"):format(player.Name, def.Name),
			"Legendary"
		)
	end

	-- Echtes Roblox-Badge vergeben, sobald eine Id eingetragen ist.
	-- 0 = Platzhalter (siehe Config.Achievements) -> nur In-Game-Popup.
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

-- Alle noch offenen Achievements gegen den aktuellen Stand prüfen
function AchievementService.Check(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	ensureFields(profile)
	for _, def in Config.Achievements do
		if not profile.Achievements[def.Id] and getStat(profile, def.Stat) >= def.Value then
			award(player, profile, def)
		end
	end
end

-- Kumulativen Zähler erhöhen (rufen Wrapper + andere Services auf)
function AchievementService.AddStat(player: Player, stat: string, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	ensureFields(profile)
	profile.AchStats[stat] = (profile.AchStats[stat] or 0) + amount
	AchievementService.Check(player)
end

function AchievementService.Init(services)
	DataService = services.DataService

	unlockedRemote = Remotes.Get("AchievementUnlocked") :: RemoteEvent
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	-- Fürs Trophäen-Fenster: freigeschaltete Ids abfragen
	(Remotes.Get("GetAchievements") :: RemoteFunction).OnServerInvoke = function(player: Player)
		local profile = DataService.Get(player)
		if not profile then
			return {}
		end
		return ensureFields(profile).Achievements
	end

	-- ── Wrapper: Einlagerungen zählen (BaseService bleibt unangetastet) ──
	-- Alle Aufrufer (SnackService/RewardService/Debug) schlagen das Feld zur
	-- Laufzeit auf derselben Tabelle nach, der Wrapper greift also überall.
	local baseAddToVault = services.BaseService.AddToVault
	services.BaseService.AddToVault = function(owner: Player, snackName: string): boolean
		local ok = baseAddToVault(owner, snackName)
		if ok then
			AchievementService.AddStat(owner, "Banked", 1)
		end
		return ok
	end

	-- ── Wrapper: erfolgreiche Tresor-Knacks zählen ──
	-- TryCrack gibt nichts zurück; Erfolg erkennen wir daran, dass der
	-- Tresor des Besitzers danach WENIGER Snacks enthält (rein lesend).
	local baseTryCrack = services.BaseService.TryCrack
	services.BaseService.TryCrack = function(thief: Player, base)
		local ownerProfile = base.Owner and DataService.Get(base.Owner)
		local before = ownerProfile and #ownerProfile.Vault or 0
		baseTryCrack(thief, base)
		if ownerProfile and #ownerProfile.Vault < before then
			AchievementService.AddStat(thief, "Cracks", 1)
		end
	end

	-- Beim Join: Felder anlegen + Altbestände sofort prüfen (wer schon
	-- 3 Rebirths hat, kriegt seine Popups einmalig nachgereicht)
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitFor(player)
			if profile then
				ensureFields(profile)
				AchievementService.Check(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Poll-Schleife für Profil-Stats (Rebirths/Yeets/BaseLevel/Pets):
	-- billig genug, um nicht jeden Service einzeln anzapfen zu müssen
	task.spawn(function()
		while true do
			task.wait(Config.AchievementCheckInterval)
			for _, player in Players:GetPlayers() do
				AchievementService.Check(player)
			end
		end
	end)
end

return AchievementService
