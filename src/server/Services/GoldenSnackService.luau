--[[
	GoldenSnackService.luau
	Zufalls-Minievent: Der GOLDENE SNACK!
	- Spawnt alle Config.GoldenSnack.IntervalMin..Max Sekunden an einer
	  zufälligen Stelle der begehbaren Map (unabhängig vom Truck-Timer)
	- Leuchtet weithin sichtbar (Neon + Lichtsäule + Sparkles + Licht)
	- Wer ihn ZUERST berührt, bekommt Cash (mal Rebirth-Multiplikator) + Season-XP
	- Claim ist server-autoritativ: ein `claimed`-Flag verhindert Doppel-Vergabe,
	  auch wenn zwei Spieler im selben Frame reinlaufen (Touched feuert seriell,
	  das Flag kippt beim ersten gültigen Treffer)
	- Nach Config.GoldenSnack.Lifetime Sekunden verschwindet er unberührt
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GoldenSnackService = {}

local DataService, PlayerService, SeasonPassService -- in Init verdrahtet
local servicesRef -- für optionale Hooks (z.B. AchievementService)

local announceRemote: RemoteEvent
local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent

local GOLD = Color3.fromRGB(255, 215, 0)

-- Grobe Himmelsrichtung für die Ankündigung ("wo ungefähr suchen?")
local function directionHint(position: Vector3): string
	local hints = {}
	if position.Z < -60 then
		table.insert(hints, "im NORDEN")
	elseif position.Z > 60 then
		table.insert(hints, "im SÜDEN")
	end
	if position.X < -100 then
		table.insert(hints, "im WESTEN")
	elseif position.X > 100 then
		table.insert(hints, "im OSTEN")
	end
	if #hints == 0 then
		return "bei der PLAZA"
	end
	return table.concat(hints, " ")
end

-- Zufällige Boden-Position im Spawn-Bereich (Raycast von oben, damit der
-- Snack auch auf Basen/Plaza/Straße sauber aufliegt)
local function rollSpawnPosition(): Vector3
	local cfg = Config.GoldenSnack
	local x = math.random(-cfg.SpawnAreaX, cfg.SpawnAreaX)
	local z = math.random(-cfg.SpawnAreaZ, cfg.SpawnAreaZ)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	local snacks = workspace:FindFirstChild("Snacks")
	if snacks then
		table.insert(exclude, snacks)
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -100, 0), params)
	local groundY = result and result.Position.Y or 0.5
	return Vector3.new(x, groundY + 2.5, z)
end

-- Baut das leuchtende Gold-Objekt samt Lichtsäule
local function buildGoldenSnack(position: Vector3): (Part, Part)
	local part = Instance.new("Part")
	part.Name = "GoldenSnack"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(3, 3, 3)
	part.Color = GOLD
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false -- Spieler laufen durch -> Touched feuert trotzdem
	part.Position = position

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 4
	light.Range = 30
	light.Parent = part

	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = GOLD
	sparkles.Parent = part

	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(GOLD)
	emitter.LightEmission = 1
	emitter.Speed = NumberRange.new(3, 7)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Rate = 25
	emitter.Parent = attachment

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(240, 34)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🌟 GOLDENER SNACK 🌟"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.1
	label.Parent = billboard
	billboard.Parent = part

	-- Lichtsäule: von JEDEM Punkt der Map sichtbar
	local beacon = Instance.new("Part")
	beacon.Name = "GoldenBeacon"
	beacon.Size = Vector3.new(2, 120, 2)
	beacon.Color = GOLD
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.55
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.Position = position + Vector3.new(0, 60, 0)

	part.Parent = workspace
	beacon.Parent = workspace
	return part, beacon
end

-- Ein kompletter Spawn-Zyklus: aufbauen, auf Berührung warten, abräumen
local function runGoldenSnack()
	local position = rollSpawnPosition()
	local part, beacon = buildGoldenSnack(position)

	announceRemote:FireAllClients(
		("🌟 Ein GOLDENER SNACK ist aufgetaucht – %s! Wer zuerst kommt, kassiert!"):format(directionHint(position)),
		"Legendary"
	)
	sfxRemote:FireAllClients("ding", position)

	local claimed = false
	local expired = false

	part.Touched:Connect(function(hit)
		if claimed or expired then
			return
		end
		local character = hit.Parent
		if not character or not character:IsA("Model") then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		if not DataService.Get(player) then
			return -- Daten noch nicht geladen: kein Claim möglich
		end
		claimed = true -- ab hier gehen alle weiteren Touches leer aus

		local amount = math.floor(Config.GoldenSnack.CashBase * DataService.GetMultiplier(player))
		PlayerService.AddCash(player, amount)
		SeasonPassService.AddXp(player, "GoldenSnack")

		-- Optionaler Achievement-Hook (Service kommt aus Teil 2 – defensiv)
		local achievements = servicesRef and servicesRef.AchievementService
		if achievements then
			achievements.AddStat(player, "Golden", 1)
		end

		notifyRemote:FireClient(player, ("🌟 GOLDENER SNACK geschnappt: +%d💰!"):format(amount))
		announceRemote:FireAllClients(
			("🌟 %s hat den GOLDENEN SNACK geschnappt! (+%d💰)"):format(player.Name, amount),
			"Legendary"
		)
		sfxRemote:FireAllClients("ding", part.Position)

		-- Abschieds-Konfetti, dann weg damit
		local burst = part:FindFirstChildOfClass("Attachment")
		local burstEmitter = burst and burst:FindFirstChildOfClass("ParticleEmitter")
		if burstEmitter then
			burstEmitter:Emit(60)
		end
		part.Transparency = 1
		local bb = part:FindFirstChildOfClass("BillboardGui")
		if bb then
			bb.Enabled = false
		end
		beacon:Destroy()
		task.delay(1.5, function()
			part:Destroy()
		end)
	end)

	-- Schwebe-Animation (dreht sich + hüpft leicht), bis geclaimt/abgelaufen
	local spin: RBXScriptConnection
	local baseY = position.Y
	spin = RunService.Heartbeat:Connect(function()
		if claimed or expired or not part.Parent then
			spin:Disconnect()
			return
		end
		local t = os.clock()
		part.CFrame = CFrame.new(position.X, baseY + math.sin(t * 2.5) * 0.6, position.Z) * CFrame.Angles(0, t * 2, 0)
	end)

	-- Lebenszeit abwarten; wenn niemand ihn geholt hat: leise verschwinden
	task.wait(Config.GoldenSnack.Lifetime)
	if not claimed then
		expired = true
		announceRemote:FireAllClients("💨 Der goldene Snack ist wieder verschwunden... Pech gehabt!", nil)
		part:Destroy()
		beacon:Destroy()
	end
end

-- Debug-Hook: goldenen Snack SOFORT spawnen (fürs Test-Menü)
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
		while true do
			task.wait(math.random(Config.GoldenSnack.IntervalMin, Config.GoldenSnack.IntervalMax))
			-- Ohne Spieler kein Event (leerer Server soll nicht vor sich hin spawnen)
			if #Players:GetPlayers() > 0 then
				runGoldenSnack()
			end
		end
	end)
end

return GoldenSnackService
