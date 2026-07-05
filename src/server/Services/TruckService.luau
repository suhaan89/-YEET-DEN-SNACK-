--[[
	TruckService.luau
	Der SCHOKO-TRUCK: der zentrale Timer-Event des Spiels.
	Rast alle Config.TruckInterval Sekunden über die Straße, verliert Snacks
	(gewichteter Zufall) und schleudert jeden weg, der ihm im Weg steht.

	Kollisions-Erkennung läuft über räumliche Abfragen (GetPartBoundsInBox)
	statt .Touched – ein per CFrame bewegtes, verankertes Teil feuert
	Touched nämlich NICHT zuverlässig.

	Special: Jeder Config.RushHourEvery-te Truck ist eine RUSH HOUR –
	zwei Trucks aus beiden Richtungen gleichzeitig!
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TruckService = {}

local SnackService, Ragdoll -- in Init verdrahtet
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

local ROAD_END = 300 -- Start-/End-X der Fahrt
local truckCounter = 0

-- Baut das Platzhalter-Truck-Modell (später durch echtes Modell ersetzen)
local function buildTruck(): Model
	local model = Instance.new("Model")
	model.Name = "SchokoTruck"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(22, 9, 9)
	body.Color = Color3.fromRGB(92, 51, 23) -- Schokobraun
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false -- Kollision machen wir selbst (räumliche Abfrage)
	body.Parent = model

	local cab = Instance.new("Part")
	cab.Name = "Cab"
	cab.Size = Vector3.new(6, 6, 8)
	cab.Color = Color3.fromRGB(200, 30, 30)
	cab.Material = Enum.Material.SmoothPlastic
	cab.Anchored = true
	cab.CanCollide = false
	cab.Parent = model

	-- "SCHOKO EXPRESS"-Schriftzug auf beiden Seiten
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(800, 300)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "🍫 SCHOKO EXPRESS 🍫"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 215, 0)
		label.Parent = gui
		gui.Parent = body
	end

	-- Hup-Sound (SoundId in Studio eintragen – es gibt keinen Built-in-Huper)
	local horn = Instance.new("Sound")
	horn.Name = "Horn"
	horn.Volume = 1
	horn.RollOffMaxDistance = 300
	horn.Parent = body

	model.PrimaryPart = body
	return model
end

-- Eine komplette Truck-Fahrt. dir = 1 (von links) oder -1 (von rechts). Blockiert bis fertig.
local function runTruck(dir: number)
	local startX = -dir * ROAD_END

	local truck = buildTruck()
	local body = truck.PrimaryPart :: BasePart
	local cab = truck:FindFirstChild("Cab") :: BasePart

	-- Truck quer zur Fahrt ausrichten: lokale -Z zeigt in Fahrtrichtung
	local bodyCFrame = CFrame.new(startX, 4.7, 0) * CFrame.Angles(0, dir > 0 and -math.pi / 2 or math.pi / 2, 0)
	truck:PivotTo(bodyCFrame)
	cab.CFrame = body.CFrame * CFrame.new(0, -1, -13)

	truck.Parent = workspace

	local horn = body:FindFirstChild("Horn") :: Sound?
	if horn and horn.SoundId ~= "" then
		horn:Play()
	end

	-- Spieler-Rammen per räumlicher Abfrage
	local flingDebounce: { [Model]: boolean } = {}
	local function checkRunOver()
		local parts = workspace:GetPartBoundsInBox(body.CFrame, body.Size + Vector3.new(6, 6, 6))
		for _, part in parts do
			local character = part.Parent
			if typeof(character) ~= "Instance" or not character:IsA("Model") or flingDebounce[character :: Model] then
				continue
			end
			local model = character :: Model
			local player = Players:GetPlayerFromCharacter(model)
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not player or not root then
				continue
			end
			flingDebounce[model] = true
			task.delay(1.5, function()
				flingDebounce[model] = nil
			end)

			-- Seitlich von der Straße wegschleudern
			local away = (root.Position - body.Position) * Vector3.new(0, 0, 1)
			if away.Magnitude < 0.1 then
				away = Vector3.new(0, 0, math.random() > 0.5 and 1 or -1)
			end
			local velocity = away.Unit * Config.TruckFlingForce + Vector3.new(0, Config.TruckFlingUpForce, 0)
			Ragdoll.Fling(model, velocity, Config.RagdollTime)
			sfxRemote:FireAllClients("explosion", root.Position)
		end
	end

	local dropTimer = 0
	local finished = false
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		local pivot = truck:GetPivot()
		local newX = pivot.Position.X + dir * Config.TruckSpeed * dt
		truck:PivotTo(pivot + Vector3.new(dir * Config.TruckSpeed * dt, 0, 0))

		checkRunOver()

		-- Snacks hinter dem Truck rausfallen lassen
		dropTimer += dt
		if dropTimer >= Config.TruckDropInterval and math.abs(newX) < Config.TruckDropZone then
			dropTimer = 0
			local dropPos = Vector3.new(newX - dir * 14, 6, 0)
			-- Snacks seitlich von der Straße wegschleudern (in die Plaza)
			local sideVel = Vector3.new(
				math.random(-15, 15),
				math.random(25, 45),
				math.random(20, 40) * (math.random() > 0.5 and 1 or -1)
			)
			SnackService.SpawnRandom(dropPos, sideVel)
		end

		-- Ende der Straße erreicht -> Truck weg
		if math.abs(newX) > ROAD_END then
			finished = true
			connection:Disconnect()
			truck:Destroy()
		end
	end)

	-- Blockieren, bis die Fahrt vorbei ist (für die Event-Schleife)
	while not finished do
		task.wait(0.25)
	end
end

function TruckService.Init(services)
	SnackService = services.SnackService
	Ragdoll = services.Ragdoll
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	task.spawn(function()
		task.wait(Config.TruckFirstSpawnDelay)
		local dirFlip = false
		while true do
			truckCounter += 1
			local isRushHour = truckCounter % Config.RushHourEvery == 0

			if isRushHour then
				announceRemote:FireAllClients("🚨 RUSH HOUR!! GLEICH KOMMEN ZWEI TRUCKS!!", "Mythic")
			else
				announceRemote:FireAllClients(
					("🚚 Der Schoko-Truck kommt in %d Sekunden! Auf die Plätze..."):format(Config.TruckWarnTime),
					nil
				)
			end
			task.wait(Config.TruckWarnTime)

			dirFlip = not dirFlip
			local dir = dirFlip and 1 or -1
			if isRushHour then
				announceRemote:FireAllClients("🚚🚚 DOPPELTES SNACK-CHAOS!!!", "Legendary")
				task.spawn(runTruck, -dir) -- zweiter Truck aus der Gegenrichtung
				task.wait(1.5)
				runTruck(dir)
			else
				announceRemote:FireAllClients("🚚💨 DER SCHOKO-TRUCK IST DA! SNACKS!!!", "Legendary")
				runTruck(dir)
			end

			task.wait(Config.TruckInterval)
		end
	end)
end

return TruckService
