--[[
	SlapService.luau
	Der SLAP: schleudert den nächsten Spieler in Reichweite per Ragdoll weg.
	Trifft es einen Snack-Träger, lässt der den Snack fallen und wird
	selbst für ein paar Sekunden zum Snack verwandelt (SnackService.ForceDrop).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SlapService = {}

local SnackService, DataService, Ragdoll -- in Init verdrahtet

local lastSlap: { [Player]: number } = {}
local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent

-- Kleiner "POW!"-Effekt am Getroffenen (reine Comedy)
local function powEffect(position: Vector3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 60)
	billboard.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "💥 POW!"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
	billboard.Parent = part

	part.Parent = workspace
	Debris:AddItem(part, 0.7)
end

local function onSlap(player: Player)
	-- Cooldown
	local now = os.clock()
	if now - (lastSlap[player] or 0) < Config.SlapCooldown then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if player:GetAttribute("Snackified") then
		return -- Snacks slappen nicht 💀
	end

	lastSlap[player] = now

	-- Nächstes Ziel in Reichweite suchen
	local closest: Player? = nil
	local closestDist = Config.SlapRange
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if otherRoot then
				local dist = (otherRoot.Position - root.Position).Magnitude
				if dist < closestDist then
					closest = other
					closestDist = dist
				end
			end
		end
	end
	if not closest then
		return
	end

	local targetChar = closest.Character :: Model
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart

	-- Schleuderkraft: Basis + Upgrade
	local profile = DataService.Get(player)
	local level = profile and profile.Upgrades.SlapPower or 0
	local force = Config.SlapBaseForce + level * Config.SlapForcePerLevel

	-- Verwandelte Snacks fliegen EXTRA weit ("Snack-Kick" – pure Comedy)
	if closest:GetAttribute("Snackified") then
		force *= 1.5
	end

	local horizontal = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	if horizontal.Magnitude < 0.1 then
		horizontal = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	local velocity = horizontal.Unit * force + Vector3.new(0, Config.SlapUpForce, 0)

	-- Trägt das Opfer einen Snack? -> fallen lassen + Verwandlung!
	local wasHolding = SnackService.IsHolding(closest)
	if wasHolding then
		SnackService.ForceDrop(closest, true)
	end

	Ragdoll.SlapEffect(character :: Model, targetRoot.Position) -- Comic-Hand schwingt (Anim ohne Assets)
	Ragdoll.Fling(targetChar, velocity, Config.RagdollTime)
	powEffect(targetRoot.Position + Vector3.new(0, 2, 0))
	sfxRemote:FireAllClients("slap", targetRoot.Position)
	notifyRemote:FireClient(closest, ("👋 Geslappt von %s!"):format(player.Name))
end

function SlapService.Init(services)
	SnackService = services.SnackService
	DataService = services.DataService
	Ragdoll = services.Ragdoll

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;
	(Remotes.Get("Slap") :: RemoteEvent).OnServerEvent:Connect(onSlap)

	Players.PlayerRemoving:Connect(function(player)
		lastSlap[player] = nil
	end)
end

return SlapService
