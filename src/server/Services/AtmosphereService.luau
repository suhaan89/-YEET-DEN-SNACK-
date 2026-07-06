--[[
	AtmosphereService.luau
	Der Grafik-Politur-Pass: macht aus der Platzhalter-Map einen Ort, der
	nach Süßigkeiten-Sommernachmittag AUSSIEHT statt nach Testlevel.

	- Post-Effects in Lighting: Atmosphere (leichter Sommerdunst), Bloom
	  (Neon-Deko und Trails glühen), SunRays, ColorCorrection (kräftigere,
	  wärmere Farben – Candy-Look!)
	- Wolken (Clouds am Terrain – rein visuell, keine Physik)
	- Map-Deko obendrauf: Candy-Straßenlaternen entlang der Truck-Route,
	  Riesen-Zuckerstangen an den Map-Rändern, Neon-Umrandung der Plaza,
	  Willkommens-Bogen am Spawn
	Alles landet in einem eigenen "Atmosphere"-Ordner bzw. Lighting –
	MapService & Co. bleiben unangetastet.
]]

local Lighting = game:GetService("Lighting")

local AtmosphereService = {}

local folder: Folder

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = folder
	return part
end

-- ══════════ Lighting & Post-Effects ══════════

local function setupLighting()
	-- Leichter, warmer Dunst: gibt der Map Tiefe, ohne die Sicht zu fressen
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(215, 200, 190)
	atmosphere.Decay = Color3.fromRGB(120, 100, 130)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	-- Neon-Teile (Schilder, Trails, Deko) bekommen ein sattes Glühen
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 28
	bloom.Threshold = 1.05
	bloom.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting

	-- Candy-Look: etwas mehr Sättigung + Kontrast, minimal warm getönt
	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.14
	color.Contrast = 0.06
	color.Brightness = 0.01
	color.TintColor = Color3.fromRGB(255, 250, 244)
	color.Parent = Lighting

	-- Ein paar gemütliche Wolken am Himmel
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.4
	clouds.Parent = workspace:WaitForChild("Terrain")
end

-- ══════════ Map-Deko ══════════

-- Candy-Straßenlaterne: gestreifter Mast + leuchtende Bonbon-Kugel
local function buildLamp(position: Vector3, color: Color3)
	for i = 0, 3 do
		makePart({
			Size = Vector3.new(0.8, 2, 0.8),
			Position = position + Vector3.new(0, 1 + i * 2, 0),
			Color = if i % 2 == 0 then color else Color3.fromRGB(250, 250, 250),
			Material = Enum.Material.SmoothPlastic,
		})
	end
	local bulb = makePart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.2, 2.2, 2.2),
		Position = position + Vector3.new(0, 9.4, 0),
		Color = color,
		Material = Enum.Material.Neon,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.6
	light.Range = 22
	light.Parent = bulb
end

-- Riesen-Zuckerstange: gebogener Kandiszucker als Blickfang am Map-Rand
local function buildCandyCane(position: Vector3, lean: number)
	for i = 0, 7 do
		makePart({
			Size = Vector3.new(2.2, 2.6, 2.2),
			CFrame = CFrame.new(position + Vector3.new(0, 1.3 + i * 2.5, 0)) * CFrame.Angles(0, 0, math.rad(lean * i)),
			Color = if i % 2 == 0 then Color3.fromRGB(230, 40, 50) else Color3.fromRGB(250, 250, 250),
			Material = Enum.Material.SmoothPlastic,
		})
	end
	-- Bogen oben (drei versetzte Segmente)
	for i = 1, 3 do
		makePart({
			Size = Vector3.new(2.2, 2.4, 2.2),
			CFrame = CFrame.new(position + Vector3.new(i * 1.6, 21 + math.sin(i * 0.9) * 1.4 - i * i * 0.35, 0))
				* CFrame.Angles(0, 0, math.rad(-25 * i)),
			Color = if i % 2 == 0 then Color3.fromRGB(250, 250, 250) else Color3.fromRGB(230, 40, 50),
			Material = Enum.Material.SmoothPlastic,
		})
	end
end

-- Willkommens-Bogen über dem Spawn
local function buildSpawnArch()
	local spawnPos = Vector3.new(0, 0, 75)
	for _, x in { -9, 9 } do
		makePart({
			Size = Vector3.new(1.6, 12, 1.6),
			Position = spawnPos + Vector3.new(x, 6, 0),
			Color = Color3.fromRGB(255, 130, 200),
			Material = Enum.Material.SmoothPlastic,
		})
	end
	local beam = makePart({
		Size = Vector3.new(21, 2.4, 1.8),
		Position = spawnPos + Vector3.new(0, 13, 0),
		Color = Color3.fromRGB(25, 25, 35),
		Material = Enum.Material.Neon,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(900, 110)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "🍫 YEET DEN SNACK! 🍫"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 215, 0)
		label.Parent = gui
		gui.Parent = beam
	end
end

local function buildMapPolish()
	-- Laternen im Wechsel-Farbschema entlang der Straße (beidseitig)
	local lampColors = {
		Color3.fromRGB(255, 120, 180),
		Color3.fromRGB(120, 200, 255),
		Color3.fromRGB(150, 255, 150),
		Color3.fromRGB(255, 200, 80),
	}
	local index = 0
	for x = -300, 300, 100 do
		for _, z in { -17, 17 } do
			index += 1
			buildLamp(Vector3.new(x, 0, z), lampColors[index % #lampColors + 1])
		end
	end

	-- Neon-Umrandung der Plaza (Chaos-Zone soll man von weitem SEHEN)
	local plazaW, plazaD = 200, 130
	for _, def in {
		{ Size = Vector3.new(plazaW + 2, 0.3, 1), Offset = Vector3.new(0, 0, plazaD / 2) },
		{ Size = Vector3.new(plazaW + 2, 0.3, 1), Offset = Vector3.new(0, 0, -plazaD / 2) },
		{ Size = Vector3.new(1, 0.3, plazaD + 2), Offset = Vector3.new(plazaW / 2, 0, 0) },
		{ Size = Vector3.new(1, 0.3, plazaD + 2), Offset = Vector3.new(-plazaW / 2, 0, 0) },
	} do
		makePart({
			Size = def.Size,
			Position = Vector3.new(0, 0.18, 0) + def.Offset,
			Color = Color3.fromRGB(255, 170, 220),
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		})
	end

	-- Riesen-Zuckerstangen an den vier Map-Ecken + Straßen-Enden
	for _, pos in {
		Vector3.new(-330, 0, -140),
		Vector3.new(330, 0, -140),
		Vector3.new(-330, 0, 140),
		Vector3.new(330, 0, 140),
		Vector3.new(-70, 0, -195),
		Vector3.new(70, 0, 195),
	} do
		buildCandyCane(pos, 0)
	end

	buildSpawnArch()
end

function AtmosphereService.Init(_services)
	folder = Instance.new("Folder")
	folder.Name = "Atmosphere"
	folder.Parent = workspace

	setupLighting()
	buildMapPolish()
end

return AtmosphereService
