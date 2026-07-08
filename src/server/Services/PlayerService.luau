--[[
	PlayerService.luau
	Spieler-Lifecycle: Leaderstats, Attribut-Sync (fürs Client-UI),
	WalkSpeed aus Tempo-Upgrade, Cash-Helfer für alle anderen Services.

	Attribute am Player (replizieren automatisch zum Client):
	- Wurfkraft/SlapPower/Tempo/Schloss = Upgrade-Level
	- Multiplier = Einkommens-Multiplikator durch Rebirths
	- HoldingSnack = hält gerade einen Snack (setzt SnackService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlayerService = {}

local DataService -- wird in Init verdrahtet

-- Leaderstats + Attribute aus dem Profil aktualisieren
function PlayerService.Sync(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats:FindFirstChild("Cash") :: IntValue).Value = math.floor(profile.Cash);
		(stats:FindFirstChild("Rebirths") :: IntValue).Value = profile.Rebirths
	end

	for name, level in profile.Upgrades do
		player:SetAttribute(name, level)
	end
	player:SetAttribute("Multiplier", DataService.GetMultiplier(player))
	player:SetAttribute("VaultLimit", Config.VaultLimit(profile.Rebirths, profile.BaseLevel, profile.ExtraVaultSlots))
	PlayerService.UpdateOverhead(player)
end

-- Rebirth-Sterne über dem Kopf (sozialer Flex – jeder sieht deinen Fortschritt)
function PlayerService.UpdateOverhead(player: Player)
	local profile = DataService.Get(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not profile or not head then
		return
	end
	local existing = head:FindFirstChild("RebirthStars")
	if profile.Rebirths <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end
	local billboard = existing :: BillboardGui?
	local label: TextLabel
	if billboard then
		label = billboard:FindFirstChildOfClass("TextLabel") :: TextLabel
	else
		billboard = Instance.new("BillboardGui")
		billboard.Name = "RebirthStars"
		billboard.Size = UDim2.fromOffset(120, 28)
		billboard.StudsOffset = Vector3.new(0, 2.2, 0)
		billboard.MaxDistance = 120
		label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 215, 0)
		label.TextStrokeTransparency = 0.2
		label.Parent = billboard
		billboard.Parent = head
	end
	label.Text = ("🌟x%d"):format(profile.Rebirths)
end

-- WalkSpeed aus dem Tempo-Upgrade anwenden
function PlayerService.ApplySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local profile = DataService.Get(player)
	local tempo = profile and profile.Upgrades.Tempo or 0
	humanoid.WalkSpeed = Config.WalkSpeedBase + tempo * Config.WalkSpeedPerTempo
end

function PlayerService.AddCash(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.Cash += amount
	local stats = player:FindFirstChild("leaderstats")
	local cashValue = stats and stats:FindFirstChild("Cash") :: IntValue?
	if cashValue then
		cashValue.Value = math.floor(profile.Cash)
	end
end

-- Gibt true zurück, wenn bezahlt werden konnte
function PlayerService.TrySpend(player: Player, amount: number): boolean
	local profile = DataService.Get(player)
	if not profile or profile.Cash < amount then
		return false
	end
	PlayerService.AddCash(player, -amount)
	return true
end

local function onPlayerAdded(player: Player)
	-- Leaderstats (Roblox-Standard-Leaderboard rechts oben)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = stats
	stats.Parent = player

	player.CharacterAdded:Connect(function()
		task.wait(0.1) -- Humanoid kurz Zeit geben
		PlayerService.ApplySpeed(player)
		PlayerService.UpdateOverhead(player)
	end)

	-- Warten bis DataService geladen hat, dann syncen
	task.spawn(function()
		local profile = DataService.WaitFor(player)
		PlayerService.Sync(player)
		PlayerService.ApplySpeed(player)
		-- Neue Spieler bekommen auf dem Client das Tutorial
		if profile and profile.TotalYeets == 0 and profile.Rebirths == 0 and #profile.Vault == 0 then
			player:SetAttribute("IsNewPlayer", true)
		end
	end)
end

function PlayerService.Init(services)
	DataService = services.DataService

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerService
