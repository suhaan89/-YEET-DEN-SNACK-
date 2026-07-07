--[[
	GoldenSnackService.luau
	Zufalls-Minievent: Alle paar Minuten (unabhängig vom Truck-Timer!) spawnt
	irgendwo auf der begehbaren Map ein GOLDENER SNACK mit dicker Leuchtsäule.
	Wer ihn ZUERST berührt oder per [E] schnappt, bekommt einen Cash-Bonus
	(skaliert mit dem Rebirth-Multiplikator) + Season-Pass-XP.

	Server-autoritativ:
	- Vergabe passiert genau EINMAL (claimed-Flag, first come first serve –
	  Luau-Callbacks laufen kooperativ, das Flag reicht als Schutz).
	- Reward-Höhe kommt aus Config, der Client kriegt nur Announce/Notify.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GoldenSnackService = {}

local DataService, PlayerService, SeasonPassService -- in Init verdrahtet
local servicesRef -- für optionale Hooks (AchievementService)

local announceRemote: RemoteEvent
local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent

local GOLD = Color3.fromRGB(255, 215, 0)

-- Zufällige Spawn-Position im Config-Rechteck; per Raycast auf den Boden gesetzt
local function rollSpawnPosition(): Vector3
	local area = Config.GoldenSnackArea
	local x = math.random(area.MinX, area.MaxX)
	local z = math.random(area.MinZ, area.MaxZ)
	local result = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -100, 0))
	local y = result and result.Position.Y or 1
	return Vector3.new(x, y + 2, z)
end

-- Baut den goldenen Snack samt Leuchtsäule; gibt (part, aufräumen) zurück
local function buildGoldenSnack(position: Vector3): (BasePart, () -> ())
	local part = Instance.new("Part")
	part.Name = "GoldenSnack"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.5, 2.5, 2.5)
	part.Color = GOLD
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.Position = position

	-- Leuchtsäule: von überall auf der Map sichtbar (wie die Imperiums-Säule)
	local pillar = Instance.new("Part")
	pillar.Name = "GoldenSnackPillar"
	pillar.Size = Vector3.new(1.6, 80, 1.6)
	pillar.Color = GOLD
	pillar.Material = Enum.Material.Neon
	pillar.Transparency = 0.5
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.Position = position + Vector3.new(0, 40, 0)
	pillar.Parent = workspace

	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = GOLD
	sparkles.Parent = part

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 3
	light.Range = 30
	light.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(GOLD)
	emitter.Speed = NumberRange.new(3, 7)
	emitter.Lifetime = NumberRange.new(0.5, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.4)
	emitter.Rate = 25
	emitter.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 34)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🌟 GOLDENER SNACK 🌟"
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
	billboard.Parent = part

	part.Parent = workspace

	local function cleanup()
		part:Destroy()
		pillar:Destroy()
	end
	return part, cleanup
end

-- Ein kompletter Event-Durchlauf: spawnen, warten, vergeben ODER despawnen
local function runGoldenSnack()
	local position = rollSpawnPosition()
	local part, cleanup = buildGoldenSnack(position)

	announceRemote:FireAllClients("🌟 Ein GOLDENER SNACK ist aufgetaucht! Wer zuerst kommt, kassiert!", "Legendary")
	sfxRemote:FireAllClients("ding", position)

	-- Genau EINE Vergabe – das Flag schützt gegen gleichzeitigen Touch + Prompt
	local claimed = false
	local function tryClaim(player: Player)
		if claimed or not player.Parent then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		if player:GetAttribute("Snackified") then
			return -- verwandelte Snacks schnappen keine Snacks 💀
		end
		claimed = true

		local reward = math.floor(Config.GoldenSnackReward * DataService.GetMultiplier(player))
		PlayerService.AddCash(player, reward)
		SeasonPassService.AddXp(player, "GoldenSnack")

		-- Optionaler Achievement-Hook (Service existiert evtl. noch nicht)
		local achievements = servicesRef and servicesRef.AchievementService
		if achievements then
			achievements.Track(player, "GoldenSnacks", 1)
		end

		sfxRemote:FireAllClients("ding", part.Position)
		notifyRemote:FireClient(player, ("🌟 GOLDENER SNACK geschnappt: +%d💰!"):format(reward))
		announceRemote:FireAllClients(
			("🌟 %s hat sich den GOLDENEN SNACK geschnappt! (+%d💰)"):format(player.Name, reward),
			"Legendary"
		)
		cleanup()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Schnappen!"
	prompt.ObjectText = "Goldener Snack"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(tryClaim)

	part.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and game:GetService("Players"):GetPlayerFromCharacter(character)
		if player then
			tryClaim(player)
		end
	end)

	-- Berührung braucht CanTouch trotz CanCollide=false; langsames Drehen für den Bling-Faktor
	part.CanTouch = true
	task.spawn(function()
		while part.Parent do
			part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(4), 0)
			task.wait(0.05)
		end
	end)

	task.wait(Config.GoldenSnackLifetime)
	if not claimed then
		claimed = true -- Vergabe ab jetzt gesperrt (Race mit letztem Touch)
		cleanup()
		announceRemote:FireAllClients("💨 Der goldene Snack ist wieder verschwunden... zu langsam!", nil)
	end
end

-- Debug-Hook: goldenen Snack sofort spawnen (fürs Test-Menü; unabhängig vom Timer)
function GoldenSnackService.DebugSpawnNow()
	task.spawn(runGoldenSnack)
end

function GoldenSnackService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	SeasonPassService = services.SeasonPassService
	servicesRef = services

	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	task.spawn(function()
		task.wait(Config.GoldenSnackFirstDelay)
		while true do
			runGoldenSnack()
			task.wait(math.random(Config.GoldenSnackIntervalMin, Config.GoldenSnackIntervalMax))
		end
	end)
end

return GoldenSnackService
