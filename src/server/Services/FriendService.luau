--[[
	FriendService.luau
	Freunde-Bonus: Spielen zwei Roblox-Freunde gleichzeitig im selben Server,
	bekommen BEIDE +Config.FriendBonusPercent aufs rohe Tresor-Einkommen.

	- Beim Join wird die Freundesliste einmal komplett über
	  Players:GetFriendsAsync geladen und als Set gecacht (Player:IsFriendsWith
	  ist deprecated). Fehlgeschlagene Ladeversuche holt eine Retry-Schleife nach.
	- Zustand fürs UI: Attribut "FriendsOnline" (Anzahl Freunde im Server,
	  repliziert automatisch). Übergang 0 <-> aktiv gibt einen Toast.
	- Auszahlung: eigener Einkommens-Tick (gleiches Muster wie die
	  CashMult-Pets im PetService) – BaseService bleibt unangetastet,
	  Tresor-Inhalt wird nur GELESEN.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FriendService = {}

local DataService, PlayerService -- in Init verdrahtet

local notifyRemote: RemoteEvent

-- Freundes-Set pro Spieler: { [FreundUserId] = true }. nil = Laden steht noch
-- aus/ist fehlgeschlagen (Retry-Schleife versucht es erneut).
local friendSets: { [Player]: { [number]: boolean } } = {}

-- Komplette Freundesliste laden (paged); gibt nil bei API-Fehler zurück
local function fetchFriendSet(userId: number): { [number]: boolean }?
	local set: { [number]: boolean } = {}
	local ok = pcall(function()
		local pages = Players:GetFriendsAsync(userId)
		while true do
			for _, item in pages:GetCurrentPage() do
				set[item.Id] = true
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		return nil
	end
	return set
end

-- Sind die beiden befreundet? (reicht, wenn EINE der beiden Listen es weiß)
local function areFriends(a: Player, b: Player): boolean
	local setA = friendSets[a]
	if setA and setA[b.UserId] then
		return true
	end
	local setB = friendSets[b]
	return setB ~= nil and setB[a.UserId] == true
end

-- Anzahl online befreundeter Mitspieler + Attribut/Toast aktualisieren
local function refreshPlayer(player: Player)
	if not player.Parent then
		return
	end
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and areFriends(player, other) then
			count += 1
		end
	end
	local before = player:GetAttribute("FriendsOnline")
	player:SetAttribute("FriendsOnline", count)
	if count > 0 and (typeof(before) ~= "number" or before == 0) then
		notifyRemote:FireClient(
			player,
			("👫 Freundes-Bonus aktiv: +%d%% Tresor-Einkommen!"):format(Config.FriendBonusPercent * 100)
		)
	elseif count == 0 and typeof(before) == "number" and before > 0 then
		notifyRemote:FireClient(player, "👋 Dein Freund ist weg – Freundes-Bonus pausiert.")
	end
end

local function refreshAll()
	for _, player in Players:GetPlayers() do
		refreshPlayer(player)
	end
end

-- Freundesliste eines Spielers laden (yieldet!) und alle Anzeigen aktualisieren
local function loadFriendsFor(player: Player)
	local set = fetchFriendSet(player.UserId)
	if set and player.Parent then
		friendSets[player] = set
		refreshAll()
	end
end

function FriendService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadFriendsFor, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadFriendsFor, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		friendSets[player] = nil
		task.defer(refreshAll) -- nach dem Entfernen aus Players neu zählen
	end)

	-- Retry-Schleife: fehlgeschlagene GetFriendsAsync-Ladevorgänge nachholen
	task.spawn(function()
		while true do
			task.wait(Config.FriendRecheckInterval)
			for _, player in Players:GetPlayers() do
				if not friendSets[player] then
					task.spawn(loadFriendsFor, player)
				end
			end
		end
	end)

	-- Bonus-Auszahlung: +X% aufs rohe Tresor-Einkommen (mit Rebirth-Multiplikator),
	-- solange mindestens ein Freund im Server ist
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTick)
			for _, player in Players:GetPlayers() do
				local friends = player:GetAttribute("FriendsOnline")
				if typeof(friends) ~= "number" or friends <= 0 then
					continue
				end
				local profile = DataService.Get(player)
				if not profile then
					continue
				end
				local vaultIncome = 0
				for _, snackName in profile.Vault do
					local def = SnackTypes.ByName[snackName]
					if def then
						vaultIncome += def.Income
					end
				end
				local bonus = vaultIncome * Config.FriendBonusPercent * DataService.GetMultiplier(player)
				if bonus > 0 then
					PlayerService.AddCash(player, bonus * Config.IncomeTick)
				end
			end
		end
	end)
end

return FriendService
