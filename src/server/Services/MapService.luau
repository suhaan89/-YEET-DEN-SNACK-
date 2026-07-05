--[[
	MapService.luau
	Baut die komplette Platzhalter-Map aus Code:
	- Straße entlang der X-Achse (Truck-Route)
	- Zentraler Plaza-Bereich (Drop-Zone = Chaos-Zone)
	- 8 Basen-Slots in zwei Reihen nördlich/südlich der Straße
	- SpawnLocation

	Alle Teile sind bewusst simple Parts -> werden später in Studio
	durch richtige Modelle ersetzt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapService = {}

local mapFolder: Folder

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

	return slots
end

function MapService.GetFolder(): Folder
	return mapFolder
end

return MapService
