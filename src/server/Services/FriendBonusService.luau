--[[
	FriendBonusService.luau
	Freunde-Bonus: Spielt ein Roblox-Freund gleichzeitig im selben Server,
	bekommen BEIDE +Config.FriendBonusPercent aufs rohe Tresor-Einkommen.

	- Freundschafts-Check beim Join via Players:GetFriendsAsync (einmalig die
	  Freundesliste laden, danach nur noch Set-Lookups – erwischt so auch
	  Freunde, die SPÄTER joinen, ohne weitere Web-Calls)
	- Der Bonus wird in einem EIGENEN Einkommens-Tick ausgezahlt (gleiches
	  Muster wie die CashMult-Pets im PetService) – BaseService und dessen
	  Einkommens-Schleife bleiben unangetastet, wir lesen das Profil nur.
	- Fürs UI repliziert das Attribut "FriendBonusCount" (Anzahl Freunde
	  gerade online); > 0 heißt Bonus aktiv.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FriendBonusService = {}

local DataService, PlayerService -- in Init verdrahtet

local notifyRemote: RemoteEvent

-- Bestätigte Freundes-Paare in DIESEM Server: friends[a][b] = true (symmetrisch)
local friends: { [Player]: { [Player]: boolean } } = {}

-- Freundeslisten-Cache pro Spieler: { [friendUserId] = true }
local friendIds: { [Player]: { [number]: boolean } } = {}

-- Komplette Freundesliste eines Spielers laden (FriendPages durchblättern)
local function fetchFriendIds(player: Player): { [number]: boolean }
	local ids: { [number]: boolean } = {}
	local ok, err = pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		-- Sicherheits-Deckel: 40 Seiten à 50 Einträge = 2000 Freunde reichen
		for _ = 1, 40 do
			for _, item in pages:GetCurrentPage() do
				ids[item.Id] = true
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn("[FriendBonusService] Freundesliste konnte nicht geladen werden für", player.Name, err)
	end
	return ids
end

local function countOnlineFriends(player: Player): number
	local map = friends[player]
	if not map then
		return 0
	end
	local n = 0
	for other in map do
		if other.Parent then
			n += 1
		end
	end
	return n
end

local function syncAttribute(player: Player)
	player:SetAttribute("FriendBonusCount", countOnlineFriends(player))
end

-- Beim Join: eigene Freundesliste laden und gegen alle anwesenden Spieler
-- matchen. Freundschaft gilt, wenn EINE der beiden Listen den anderen kennt
-- (deckt auch den Fall ab, dass eine Liste nicht geladen werden konnte).
local function checkNewPlayer(newPlayer: Player)
	local ids = fetchFriendIds(newPlayer)
	if not newPlayer.Parent then
		return -- während des Web-Calls schon wieder weg
	end
	friendIds[newPlayer] = ids
	friends[newPlayer] = friends[newPlayer] or {}

	for _, other in Players:GetPlayers() do
		if other == newPlayer or not other.Parent or friends[newPlayer][other] then
			continue
		end
		local otherIds = friendIds[other]
		local isFriend = ids[other.UserId] == true or (otherIds and otherIds[newPlayer.UserId] == true)
		if isFriend then
			friends[newPlayer][other] = true
			friends[other] = friends[other] or {}
			friends[other][newPlayer] = true

			-- Beide informieren – der Bonus ist ein Feature, kein Geheimnis!
			local percent = Config.FriendBonusPercent * 100
			notifyRemote:FireClient(
				newPlayer,
				("🤝 Dein Freund %s ist im Server – Freundes-Bonus aktiv: +%d%% Einkommen!"):format(other.Name, percent)
			)
			notifyRemote:FireClient(
				other,
				("🤝 Dein Freund %s ist gejoint – Freundes-Bonus aktiv: +%d%% Einkommen!"):format(newPlayer.Name, percent)
			)
			syncAttribute(other)
		end
	end
	syncAttribute(newPlayer)
end

function FriendBonusService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent

	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkNewPlayer, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(checkNewPlayer, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local map = friends[player]
		friends[player] = nil
		friendIds[player] = nil
		if map then
			for other in map do
				local otherMap = friends[other]
				if otherMap then
					otherMap[player] = nil
				end
				if other.Parent then
					syncAttribute(other)
					if countOnlineFriends(other) == 0 then
						notifyRemote:FireClient(other, ("👋 %s ist weg – Freundes-Bonus pausiert."):format(player.Name))
					end
				end
			end
		end
	end)

	-- Eigener Zahl-Tick: rohes Tresor-Einkommen * Bonus * Rebirth-Multiplikator
	-- (gleiche Formel-Basis wie die CashMult-Pets, damit sich nichts doppelt
	-- verrechnet – der Tycoon-Ausbau-Bonus läuft weiterhin nur im BaseService)
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTick)
			for _, player in Players:GetPlayers() do
				if countOnlineFriends(player) == 0 then
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
				if vaultIncome > 0 then
					local bonus = vaultIncome
						* Config.FriendBonusPercent
						* DataService.GetMultiplier(player)
						* Config.IncomeTick
					PlayerService.AddCash(player, bonus)
				end
			end
		end
	end)
end

return FriendBonusService
