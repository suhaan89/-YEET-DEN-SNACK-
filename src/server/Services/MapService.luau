--[[
	MapService.luau
	Baut die komplette Platzhalter-Map aus Code:
	- Straße entlang der X-Achse (Truck-Route)
	- Zentraler Plaza-Bereich (Drop-Zone = Chaos-Zone)
	- 8 Basen-Slots in zwei Reihen nördlich/südlich der Straße
	- SpawnLocation
	- 3 Shop-Gebäude (Upgrade/Pets/Style) + Merge-Station als begehbare Orte:
	  ProximityPrompt am Tresen feuert das "OpenShop"-Remote -> Client öffnet das UI

	Alle Teile sind bewusst simple Parts -> werden später in Studio
	durch richtige Modelle ersetzt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MapService = {}

local mapFolder: Folder

-- Welt-Position pro Shop-Id ("Upgrade"/"Pets"/"Style"/"Merge") –
-- für Server-Distanzchecks (z.B. MergeService validiert Config.MergeRange)
local shopPositions: { [string]: Vector3 } = {}

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = mapFolder
	return part
end

-- ══════════ Shop-Gebäude ══════════

-- Neon-Schild mit Text auf Vorder- und Rückseite
local function addSign(part: BasePart, text: string, textColor: Color3)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(900, 200)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = textColor
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = part
	end
end

-- Baut einen Kiosk-Stand. cf = Stand-CFrame, lokale -Z-Richtung = "vorne" (zur Plaza).
-- Der ProximityPrompt am Tresen feuert "OpenShop" mit der shopId an den Spieler.
local function buildShopStand(shopId: string, title: string, promptText: string, color: Color3, cf: CFrame)
	local openShopRemote = Remotes.Get("OpenShop") :: RemoteEvent

	local folder = Instance.new("Folder")
	folder.Name = "Shop_" .. shopId
	folder.Parent = mapFolder

	local function standPart(props: { [string]: any }): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in props do
			(part :: any)[key] = value
		end
		part.Parent = folder
		return part
	end

	-- Boden-Pad
	standPart({
		Name = "Pad",
		Size = Vector3.new(18, 0.6, 14),
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	})
	-- Verkaufshäuschen hinten
	standPart({
		Name = "Booth",
		Size = Vector3.new(14, 7, 6),
		CFrame = cf * CFrame.new(0, 4.1, 3),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	})
	-- Dach
	standPart({
		Name = "Roof",
		Size = Vector3.new(16, 1, 10),
		CFrame = cf * CFrame.new(0, 8.1, 1),
		Color = Color3.fromRGB(250, 250, 250),
		Material = Enum.Material.SmoothPlastic,
	})
	-- Leucht-Schild überm Dach
	local sign = standPart({
		Name = "Sign",
		Size = Vector3.new(16, 2.6, 0.6),
		CFrame = cf * CFrame.new(0, 10.1, 1),
		Color = Color3.fromRGB(25, 25, 35),
		Material = Enum.Material.Neon,
	})
	addSign(sign, title, color)

	-- Tresen vorne – hier hängt der Prompt dran
	local counter = standPart({
		Name = "Counter",
		Size = Vector3.new(10, 3.2, 2.5),
		CFrame = cf * CFrame.new(0, 1.9, -3.5),
		Color = Color3.fromRGB(240, 240, 240),
		Material = Enum.Material.SmoothPlastic,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = promptText
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function(player)
		openShopRemote:FireClient(player, shopId)
	end)

	shopPositions[shopId] = counter.Position
	return folder
end

-- Die Merge-Station: brodelnde Mutations-Maschine statt Kiosk
local function buildMergeStation(cf: CFrame)
	local folder = buildShopStand("Merge", "🧪 MERGE-MASCHINE 3000", "Mergen!", Color3.fromRGB(150, 70, 220), cf)

	-- Brodelnder Kessel auf dem Tresen-Vorplatz
	local cauldron = Instance.new("Part")
	cauldron.Name = "Cauldron"
	cauldron.Shape = Enum.PartType.Cylinder
	cauldron.Anchored = true
	cauldron.Size = Vector3.new(3.5, 6, 6)
	cauldron.CFrame = cf * CFrame.new(6.5, 2.1, -3.5) * CFrame.Angles(0, 0, math.rad(90))
	cauldron.Color = Color3.fromRGB(110, 255, 40)
	cauldron.Material = Enum.Material.Neon
	cauldron.Parent = folder

	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(110, 255, 40)
	sparkles.Parent = cauldron
end

-- Baut die Map und gibt die 8 Basis-Slot-CFrames zurück
function MapService.Build(): { CFrame }
	workspace.Gravity = Config.Gravity -- floaty Comedy-Physik

	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	-- Straße: verläuft von x=-260 bis x=260 bei z=0
	makePart({
		Name = "Road",
		Size = Vector3.new(520, 0.2, 26),
		Position = Vector3.new(0, 0.1, 0),
		Color = Color3.fromRGB(60, 60, 60),
		Material = Enum.Material.Asphalt,
	})
	-- Mittelstreifen
	makePart({
		Name = "RoadLine",
		Size = Vector3.new(520, 0.22, 0.8),
		Position = Vector3.new(0, 0.11, 0),
		Color = Color3.fromRGB(255, 220, 60),
		Material = Enum.Material.Neon,
	})

	-- Plaza: die zentrale Chaos-Zone, in der die Snacks landen
	makePart({
		Name = "Plaza",
		Size = Vector3.new(140, 0.15, 90),
		Position = Vector3.new(0, 0.08, 0),
		Color = Color3.fromRGB(230, 190, 140),
		Material = Enum.Material.WoodPlanks,
	})

	-- SpawnLocation abseits der Straße
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Size = Vector3.new(14, 1, 14)
	spawnLoc.Position = Vector3.new(0, 0.5, 58)
	spawnLoc.Color = Color3.fromRGB(120, 200, 255)
	spawnLoc.Anchored = true
	spawnLoc.Neutral = true
	spawnLoc.Duration = Config.SpawnProtection -- kurzer Spawn-Schutz gegen Spawn-Slapping
	spawnLoc.Parent = mapFolder

	-- 8 Basis-Slots: 4 nördlich (z = -95), 4 südlich (z = +95)
	-- CFrames schauen jeweils Richtung Straße (damit "vorne" zur Action zeigt)
	-- (CFrame-Blickrichtung ist -Z: Nordreihe muss um 180° gedreht werden)
	local slots: { CFrame } = {}
	local xPositions = { -165, -55, 55, 165 }
	for _, x in xPositions do
		-- Nordreihe (z=-95) schaut nach Süden Richtung Straße
		table.insert(slots, CFrame.new(x, 0, -95) * CFrame.Angles(0, math.pi, 0))
	end
	for _, x in xPositions do
		-- Südreihe (z=+95) schaut nach Norden Richtung Straße
		table.insert(slots, CFrame.new(x, 0, 95))
	end

	-- Shops in den Lücken zwischen den Basen (Front jeweils Richtung Plaza):
	-- Südseite (z=62, Blick nach Norden = Standard -Z), Nordseite (z=-62, um 180° gedreht)
	buildShopStand("Upgrade", "🛒 UPGRADE-SHOP", "Shoppen!", Color3.fromRGB(240, 160, 40), CFrame.new(-110, 0, 62))
	buildShopStand("Pets", "🐹 PET-SHOP", "Pets angucken!", Color3.fromRGB(90, 200, 120), CFrame.new(110, 0, 62))
	buildShopStand(
		"Style",
		"✨ STYLE-SHOP",
		"Stylen!",
		Color3.fromRGB(220, 100, 220),
		CFrame.new(-110, 0, -62) * CFrame.Angles(0, math.pi, 0)
	)
	buildMergeStation(CFrame.new(110, 0, -62) * CFrame.Angles(0, math.pi, 0))

	return slots
end

-- Welt-Position eines Shops (z.B. für Server-Distanzchecks der Merge-Station)
function MapService.GetShopPosition(shopId: string): Vector3?
	return shopPositions[shopId]
end

function MapService.GetFolder(): Folder
	return mapFolder
end

return MapService
