--[[
	LeaderboardService.luau
	Globale, server-übergreifende Bestenlisten (OrderedDataStores):
	- Top 20 nach LIFETIME-Cash (alles jemals verdiente Cash – Ausgeben und
	  Rebirth-Reset zählen NICHT runter, sonst wäre Rebirthen doof fürs Ranking)
	- Top 20 nach Rebirths

	Lifetime-Cash-Tracking: PlayerService.AddCash wird hier UMHÜLLT (gleiches
	Wrapper-Muster wie AchievementService bei AddToVault) – jede POSITIVE
	Gutschrift zählt auf profile.LifetimeCash (lazy angelegt, Bestandsspieler
	starten mit ihrem aktuellen Kontostand als Startwert).

	DataStore-Budget: Scores werden nur alle Config.Leaderboard.WriteInterval
	Sekunden pro Spieler hochgeladen, die Top-Listen alle ReadInterval Sekunden
	geladen und GECACHT. Das UI fragt per GetLeaderboards nur den Cache ab
	(kein DataStore-Hit pro Klick), die Map-Displays lesen denselben Cache.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LeaderboardService = {}

local DataService, PlayerService -- in Init verdrahtet

local cashStore = nil
local rebirthStore = nil

-- Gecachte Top-Listen: { { UserId, Name, Value }, ... }
local topCash: { any } = {}
local topRebirths: { any } = {}

-- UserId -> Name (GetNameFromUserIdAsync ist teuer, Namen ändern sich selten)
local nameCache: { [number]: string } = {}

local boardLabels: { [string]: TextLabel } = {} -- "Cash"/"Rebirths" -> Map-Display

local function formatNumber(n: number): string
	n = math.floor(n)
	if n >= 1_000_000 then
		return string.format("%.1fM", n / 1_000_000)
	elseif n >= 10_000 then
		return string.format("%.1fk", n / 1_000)
	end
	return tostring(n)
end

local function resolveName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[userId] = online.Name
		return online.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = if ok then name else "???"
	return nameCache[userId]
end

-- ══════════ Scores hochladen ══════════

local function uploadScores(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if cashStore and typeof(profile.LifetimeCash) == "number" and profile.LifetimeCash > 0 then
		pcall(function()
			cashStore:SetAsync(tostring(player.UserId), math.floor(profile.LifetimeCash))
		end)
	end
	if rebirthStore and profile.Rebirths > 0 then
		pcall(function()
			rebirthStore:SetAsync(tostring(player.UserId), profile.Rebirths)
		end)
	end
end

-- ══════════ Top-Listen laden ══════════

local function fetchTop(store): { any }?
	if not store then
		return nil
	end
	local result = nil
	pcall(function()
		local pages = store:GetSortedAsync(false, Config.Leaderboard.TopCount)
		local list = {}
		for _, entry in pages:GetCurrentPage() do
			table.insert(list, {
				UserId = tonumber(entry.key) or 0,
				Name = resolveName(tonumber(entry.key) or 0),
				Value = entry.value,
			})
		end
		result = list
	end)
	return result
end

-- ══════════ Map-Displays (SurfaceGui-Tafeln am Spawn) ══════════

local function buildBoard(title: string, emoji: string, position: Vector3, color: Color3): TextLabel
	local part = Instance.new("Part")
	part.Name = "Leaderboard" .. title
	part.Anchored = true
	part.Size = Vector3.new(17, 19, 1)
	part.Position = position
	part.Color = Color3.fromRGB(28, 26, 38)
	part.Material = Enum.Material.SmoothPlastic

	-- Neon-Rahmen oben (Titelbalken)
	local header = Instance.new("Part")
	header.Anchored = true
	header.Size = Vector3.new(17.6, 1.4, 1.2)
	header.Position = position + Vector3.new(0, 10.2, 0)
	header.Color = color
	header.Material = Enum.Material.Neon
	header.Parent = workspace:FindFirstChild("Map") or workspace

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(680, 760)
	gui.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0, 70)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.Text = emoji .. " " .. title
	titleLabel.TextColor3 = color
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.Parent = gui

	local body = Instance.new("TextLabel")
	body.Position = UDim2.fromOffset(20, 80)
	body.Size = UDim2.new(1, -40, 1, -95)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.FredokaOne
	body.TextSize = 30
	body.TextColor3 = Color3.new(1, 1, 1)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Text = "Lade Bestenliste..."
	body.Parent = gui

	part.Parent = workspace:FindFirstChild("Map") or workspace
	return body
end

local function refreshBoardDisplay(key: string, list: { any }, valueSuffix: string)
	local label = boardLabels[key]
	if not label then
		return
	end
	if #list == 0 then
		label.Text = "Noch keine Einträge – sei der Erste!"
		return
	end
	local lines = {}
	for rank, entry in list do
		local medal = if rank == 1 then "🥇" elseif rank == 2 then "🥈" elseif rank == 3 then "🥉" else ("%2d."):format(rank)
		table.insert(lines, ("%s %s – %s%s"):format(medal, entry.Name, formatNumber(entry.Value), valueSuffix))
	end
	label.Text = table.concat(lines, "\n")
end

-- ══════════ Init ══════════

function LeaderboardService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService

	local okCash, resultCash = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Leaderboard.CashStore)
	end)
	local okRebirth, resultRebirth = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Leaderboard.RebirthStore)
	end)
	if okCash then
		cashStore = resultCash
	end
	if okRebirth then
		rebirthStore = resultRebirth
	end
	if not (cashStore and rebirthStore) then
		warn("[LeaderboardService] Kein DataStore-Zugriff – globale Bestenlisten bleiben leer.")
	end

	-- Lifetime-Cash-Tracking: AddCash umhüllen (nur positive Beträge zählen)
	local originalAddCash = PlayerService.AddCash
	PlayerService.AddCash = function(player: Player, amount: number)
		originalAddCash(player, amount)
		if amount > 0 then
			local profile = DataService.Get(player)
			if profile then
				if typeof(profile.LifetimeCash) ~= "number" then
					profile.LifetimeCash = profile.Cash
				end
				profile.LifetimeCash += amount
			end
		end
	end

	-- Bestandsspieler beim Join initialisieren (Startwert = aktueller Kontostand)
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitFor(player)
			if profile and typeof(profile.LifetimeCash) ~= "number" then
				profile.LifetimeCash = profile.Cash
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Beim Verlassen letzten Stand hochladen (sonst fehlen bis zu 2 Min)
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(uploadScores, player)
	end)

	-- Map-Displays hinter dem Spawn (Spawn liegt bei (0, 0, 75), Front zeigt zur Plaza)
	boardLabels.Cash = buildBoard("REICHSTE YEETER", "💰", Vector3.new(-16, 10, 92), Color3.fromRGB(255, 210, 60))
	boardLabels.Rebirths = buildBoard("SUGAR-RUSH-KÖNIGE", "🌟", Vector3.new(16, 10, 92), Color3.fromRGB(220, 120, 255))

	-- Cache fürs UI (kein DataStore-Hit pro Anfrage!)
	;(Remotes.Get("GetLeaderboards") :: RemoteFunction).OnServerInvoke = function(_player)
		return { Cash = topCash, Rebirths = topRebirths }
	end

	-- Upload-Schleife
	task.spawn(function()
		while true do
			task.wait(Config.Leaderboard.WriteInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(uploadScores, player)
			end
		end
	end)

	-- Download-/Anzeige-Schleife (erster Lauf nach kurzer Anlaufzeit)
	task.spawn(function()
		task.wait(5)
		while true do
			local cash = fetchTop(cashStore)
			if cash then
				topCash = cash
				refreshBoardDisplay("Cash", topCash, "💰")
			end
			local rebirths = fetchTop(rebirthStore)
			if rebirths then
				topRebirths = rebirths
				refreshBoardDisplay("Rebirths", topRebirths, "🌟")
			end
			task.wait(Config.Leaderboard.ReadInterval)
		end
	end)
end

return LeaderboardService
