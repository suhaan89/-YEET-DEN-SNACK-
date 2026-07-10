--[[
	TruckService.luau
	Der SCHOKO-TRUCK: der zentrale Timer-Event des Spiels.
	Rast alle Config.TruckInterval Sekunden über die Straße, verliert Snacks
	(gewichteter Zufall) und schleudert jeden weg, der ihm im Weg steht.

	Kollisions-Erkennung läuft über räumliche Abfragen (GetPartBoundsInBox)
	statt .Touched – ein per CFrame bewegtes, verankertes Teil feuert
	Touched nämlich NICHT zuverlässig.

	Specials:
	- Jeder Config.RushHourEvery-te Truck ist eine RUSH HOUR –
	  zwei Trucks aus beiden Richtungen gleichzeitig!
	- Im Schnitt alle ~100 Trucks (Config.SupremeTrucksMin..Max) kommt statt
	  des normalen Trucks der MUTANTEN-EXPRESS und droppt Supreme-Snacks.
	  Countdown repliziert über Workspace-Attribute "SupremeTrucksLeft"/
	  "SupremeTrucksTarget" (die Ui zeigt daraus die Fortschrittsleiste).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MeshVisuals = require(ReplicatedStorage.Shared.MeshVisuals)

local TruckService = {}

local SnackService, Ragdoll -- in Init verdrahtet
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

local ROAD_END = 420 -- Start-/End-X der Fahrt (Straße geht bis ±380, Truck startet dahinter)
local truckCounter = 0

-- Supreme-Countdown: so viele Trucks noch bis zum Mutanten-Express
local supremeTarget = 0
local supremeLeft = 0

local function rollSupremeCountdown()
	supremeTarget = math.random(Config.SupremeTrucksMin, Config.SupremeTrucksMax)
	supremeLeft = supremeTarget
	workspace:SetAttribute("SupremeTrucksTarget", supremeTarget)
	workspace:SetAttribute("SupremeTrucksLeft", supremeLeft)
end

-- Baut das Platzhalter-Truck-Modell (später durch echtes Modell ersetzen).
-- isSupreme = giftgrüner MUTANTEN-EXPRESS statt Schoko-Optik.
local function buildTruck(isSupreme: boolean?): Model
	local model = Instance.new("Model")
	model.Name = if isSupreme then "MutantenExpress" else "SchokoTruck"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(22, 9, 9)
	body.Color = if isSupreme then Color3.fromRGB(60, 200, 40) else Color3.fromRGB(92, 51, 23)
	body.Material = if isSupreme then Enum.Material.Neon else Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false -- Kollision machen wir selbst (räumliche Abfrage)
	body.Parent = model

	-- ══ MESH-EINBAU: echte Truck-MeshId in src/shared/Config.luau eintragen ══
	-- (Config.Meshes.Truck bzw. Config.Meshes.TruckSupreme, oben in der Datei).
	-- Ist dort eine echte MeshId gesetzt, bekommt der Body das Mesh als Optik;
	-- Platzhalter-Kabine und Schriftzug entfallen dann, weil ein richtiges
	-- Truck-Mesh beides selbst mitbringt. Kollision/Fahrlogik bleiben gleich.
	local hasMesh = MeshVisuals.Apply(body, if isSupreme then Config.Meshes.TruckSupreme else Config.Meshes.Truck)

	local cab = Instance.new("Part")
	cab.Name = "Cab"
	cab.Size = Vector3.new(6, 6, 8)
	cab.Color = if isSupreme then Color3.fromRGB(20, 80, 20) else Color3.fromRGB(200, 30, 30)
	cab.Material = Enum.Material.SmoothPlastic
	cab.Anchored = true
	cab.CanCollide = false
	cab.Transparency = if hasMesh then 1 else 0 -- echtes Mesh hat die Kabine schon dran
	cab.Parent = model

	-- Schriftzug auf beiden Seiten (nur auf dem Platzhalter-Block sinnvoll)
	if not hasMesh then
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.CanvasSize = Vector2.new(800, 300)
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = if isSupreme then "☢️ MUTANTEN EXPRESS ☢️" else "🍫 SCHOKO EXPRESS 🍫"
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = if isSupreme then Color3.fromRGB(180, 255, 80) else Color3.fromRGB(255, 215, 0)
			label.Parent = gui
			gui.Parent = body
		end
	end

	if isSupreme then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(110, 255, 40)
		sparkles.Parent = body
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
-- isSupreme: Mutanten-Express – droppt ca. Config.SupremeSnackCount Supreme-Snacks statt normaler.
local function runTruck(dir: number, isSupreme: boolean?)
	local startX = -dir * ROAD_END

	local truck = buildTruck(isSupreme)
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

	-- Supreme-Trucks droppen nur wenige, dafür fette Snacks:
	-- Intervall so strecken, dass über die Drop-Zone ~SupremeSnackCount Stück fallen
	local dropInterval = Config.TruckDropInterval
	if isSupreme then
		local zoneTime = (2 * Config.TruckDropZone) / Config.TruckSpeed
		dropInterval = zoneTime / (Config.SupremeSnackCount + 0.5)
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
		if dropTimer >= dropInterval and math.abs(newX) < Config.TruckDropZone then
			dropTimer = 0
			local dropPos = Vector3.new(newX - dir * 14, 6, 0)
			-- Snacks seitlich von der Straße wegschleudern (in die Plaza)
			local sideVel = Vector3.new(
				math.random(-15, 15),
				math.random(25, 45),
				math.random(20, 40) * (math.random() > 0.5 and 1 or -1)
			)
			if isSupreme then
				SnackService.SpawnSnack(SnackTypes.RollSupreme(), dropPos, sideVel)
			else
				SnackService.SpawnRandom(dropPos, sideVel)
			end
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

-- Debug-Hook: Mutanten-Express SOFORT losschicken (fürs Test-Menü).
-- Läuft unabhängig von der normalen Event-Schleife, Countdown bleibt unberührt.
function TruckService.DebugSupremeNow()
	task.spawn(function()
		announceRemote:FireAllClients("☢️☢️ DER MUTANTEN-EXPRESS!! MUTIERTE SNACKS!!! ☢️☢️", "Supreme")
		runTruck(math.random() > 0.5 and 1 or -1, true)
	end)
end

-- Debug-Hook: normalen Truck sofort losschicken (fürs Test-Menü)
function TruckService.DebugTruckNow()
	task.spawn(function()
		announceRemote:FireAllClients("🚚💨 DER SCHOKO-TRUCK IST DA! SNACKS!!!", "Legendary")
		runTruck(math.random() > 0.5 and 1 or -1)
	end)
end

-- Debug-Hook: Rush Hour sofort (zwei Trucks aus beiden Richtungen)
function TruckService.DebugRushHourNow()
	task.spawn(function()
		announceRemote:FireAllClients("🚚🚚 DOPPELTES SNACK-CHAOS!!!", "Legendary")
		task.spawn(runTruck, -1)
		task.wait(1.5)
		runTruck(1)
	end)
end

-- Debug-Hook: Warte-Timer der Event-Schleife überspringen (nächster Truck kommt sofort)
local skipTimer = false
function TruckService.DebugSkipTimer()
	skipTimer = true
end

-- Debug-Hook: Supreme-Countdown auf 0 -> der NÄCHSTE reguläre Truck ist der Mutanten-Express
function TruckService.DebugSupremeNext()
	supremeLeft = 0
	workspace:SetAttribute("SupremeTrucksLeft", supremeLeft)
end

-- task.wait, das sich per DebugSkipTimer abkürzen lässt (nur für die Event-Schleife)
local function waitSkippable(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not skipTimer do
		task.wait(0.25)
	end
	skipTimer = false
end

function TruckService.Init(services)
	SnackService = services.SnackService
	Ragdoll = services.Ragdoll
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	rollSupremeCountdown()

	task.spawn(function()
		waitSkippable(Config.TruckFirstSpawnDelay)
		local dirFlip = false
		while true do
			truckCounter += 1
			-- Countdown abgelaufen? Dann kommt statt des normalen Trucks der Mutanten-Express!
			local isSupreme = supremeLeft <= 0
			local isRushHour = not isSupreme and truckCounter % Config.RushHourEvery == 0

			if isSupreme then
				announceRemote:FireAllClients("☢️ ACHTUNG!! DER MUTANTEN-EXPRESS NÄHERT SICH... ☢️", "Supreme")
			elseif isRushHour then
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
			if isSupreme then
				announceRemote:FireAllClients("☢️☢️ MUTIERTE SNACKS AUF DER STRASSE!!! ☢️☢️", "Supreme")
				runTruck(dir, true)
				rollSupremeCountdown() -- neuen Countdown würfeln
			elseif isRushHour then
				announceRemote:FireAllClients("🚚🚚 DOPPELTES SNACK-CHAOS!!!", "Legendary")
				task.spawn(runTruck, -dir) -- zweiter Truck aus der Gegenrichtung
				task.wait(1.5)
				runTruck(dir)
			else
				announceRemote:FireAllClients("🚚💨 DER SCHOKO-TRUCK IST DA! SNACKS!!!", "Legendary")
				runTruck(dir)
			end

			if not isSupreme then
				supremeLeft -= 1
				workspace:SetAttribute("SupremeTrucksLeft", supremeLeft)
			end

			waitSkippable(Config.TruckInterval)
		end
	end)
end

return TruckService
