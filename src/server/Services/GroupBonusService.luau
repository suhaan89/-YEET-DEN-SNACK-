--[[
	GroupBonusService.luau
	Gruppen-Bonus: Mitglieder der Spiel-Gruppe (Config.GroupId) bekommen
	dauerhaft +Config.GroupBonusPercent aufs rohe Tresor-Einkommen –
	gleiches Auszahlungs-Muster wie der FriendService (eigener Income-Tick,
	BaseService bleibt unangetastet).

	- Solange Config.GroupId = 0 ist (Platzhalter), schläft das Feature komplett.
	- Mitgliedschaft wird über GroupService:GetGroupsAsync geprüft (ohne den
	  Session-Cache von Player:IsInGroup, der ist außerdem deprecated).
	  Ergebnis liegt als replizierendes Attribut "InGroup" fürs UI. Eine
	  Recheck-Schleife prüft Nicht-Mitglieder regelmäßig neu – wer der Gruppe
	  WÄHREND des Spielens beitritt, kriegt den Bonus noch in derselben Session.
	- Nicht-Mitglieder bekommen einmalig einen Beitritts-Hinweis-Toast.
]]

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GroupBonusService = {}

local DataService, PlayerService -- in Init verdrahtet

local notifyRemote: RemoteEvent

-- Rohes Tresor-Einkommen (nur LESEN, gleiche Formel wie FriendService)
local function getVaultIncome(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local income = 0
	for _, snackName in profile.Vault do
		local def = SnackTypes.ByName[snackName]
		if def then
			income += def.Income
		end
	end
	return income
end

local function setMember(player: Player, isMember: boolean, announce: boolean)
	local before = player:GetAttribute("InGroup")
	player:SetAttribute("InGroup", isMember)
	if isMember and before ~= true and announce then
		notifyRemote:FireClient(
			player,
			("🏷️ Gruppen-Bonus aktiv: +%d%% Tresor-Einkommen – danke fürs Dabeisein!"):format(
				Config.GroupBonusPercent * 100
			)
		)
	end
end

-- Frische Prüfung OHNE Session-Cache (für Beitritte während des Spielens)
local function isInGroupFresh(userId: number): boolean?
	local result: boolean? = nil
	local ok = pcall(function()
		local groups = GroupService:GetGroupsAsync(userId)
		result = false
		for _, info in groups do
			if info.Id == Config.GroupId then
				result = true
				break
			end
		end
	end)
	if not ok then
		return nil
	end
	return result
end

local function checkOnJoin(player: Player)
	local isMember = isInGroupFresh(player.UserId)
	if isMember == nil then
		return -- API-Fehler: Recheck-Schleife versucht es erneut
	end
	if not player.Parent then
		return
	end
	setMember(player, isMember, true)
	if not isMember then
		task.delay(30, function()
			if player.Parent and player:GetAttribute("InGroup") ~= true then
				notifyRemote:FireClient(
					player,
					("🏷️ Tritt unserer Roblox-Gruppe bei und kassiere +%d%% Einkommen! (Gruppe auf der Spielseite verlinkt)"):format(
						Config.GroupBonusPercent * 100
					)
				)
			end
		end)
	end
end

function GroupBonusService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent

	if Config.GroupId <= 0 then
		return -- noch keine Gruppe angelegt: Feature schläft
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkOnJoin, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(checkOnJoin, player)
	end

	-- Recheck: Nicht-Mitglieder (oder fehlgeschlagene Checks) frisch prüfen
	task.spawn(function()
		while true do
			task.wait(Config.GroupRecheckInterval)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("InGroup") == true then
					continue
				end
				task.spawn(function()
					local fresh = isInGroupFresh(player.UserId)
					if fresh ~= nil and player.Parent then
						setMember(player, fresh, true)
					end
				end)
			end
		end
	end)

	-- Bonus-Auszahlung (FriendService-Muster)
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTick)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("InGroup") ~= true then
					continue
				end
				local bonus = getVaultIncome(player) * Config.GroupBonusPercent * DataService.GetMultiplier(player)
				if bonus > 0 then
					PlayerService.AddCash(player, bonus * Config.IncomeTick)
				end
			end
		end
	end)
end

return GroupBonusService
