--[[
	ParkourMap.luau
	Baut die 8 Parkour-Arenen aus Code – jede als eigener Ordner, hoch über
	der Hauptmap (y=400) und 1000 Studs voneinander entfernt, damit sich
	nichts überschneidet und niemand von der Straße aus etwas sieht.

	Cursor-Prinzip: jeder Parcours wird als Segment-Kette gebaut. Ein Cursor
	(Position + Blickrichtung) wandert vorwärts, jedes Segment setzt eine
	Plattform/Falle und schiebt den Cursor weiter. So bleiben die Layouts
	lesbar und die Sprungweiten kontrollierbar (Gravity 140, JumpHeight 7.2:
	max. ~10 Studs Weite bei Basis-Tempo -> Lücken hier: 2-8 Studs).

	Gibt pro Parcours zurück, was der ParkourService verdrahten muss:
	SpawnCFrame, StartPart, FinishPart, Checkpoints, KillParts, Animated.
	Die Animationen (Spin/Move/Blink) fährt der ParkourService in EINEM
	Heartbeat-Loop – hier werden sie nur registriert (deterministisch über
	os.clock(), damit alle Spieler dasselbe sehen).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ParkourMap = {}

export type Animated = {
	Part: BasePart,
	Kind: "spin" | "move" | "blink",
	Base: CFrame,
	Speed: number, -- spin: rad/s, move: rad/s der Sinus-Phase, blink: unbenutzt
	Phase: number,
	Offset: Vector3?, -- move: Amplituden-Vektor (Welt)
	Period: number?, -- blink: Sekunden pro An/Aus-Zyklus
	Duty: number?, -- blink: Anteil "sichtbar" (0..1)
}

export type CourseBuild = {
	Folder: Folder,
	SpawnCFrame: CFrame,
	StartPart: BasePart,
	FinishPart: BasePart,
	Checkpoints: { { Part: BasePart, Spawn: CFrame } },
	KillParts: { BasePart },
	Animated: { Animated },
}

-- ══════════ Cursor-Kontext ══════════

type Ctx = {
	Folder: Folder,
	Pos: Vector3, -- Cursor = OBERKANTE der zuletzt gesetzten Plattform
	Dir: Vector3, -- horizontale Blickrichtung (Einheitsvektor)
	Def: any, -- Config-Eintrag des Parcours (für Farben)
	Build: CourseBuild,
}

local function newCtx(def, origin: Vector3, folder: Folder): Ctx
	return {
		Folder = folder,
		Pos = origin,
		Dir = Vector3.zAxis, -- Parcours laufen Richtung +Z
		Def = def,
		Build = {
			Folder = folder,
			SpawnCFrame = CFrame.new(origin),
			StartPart = nil :: any,
			FinishPart = nil :: any,
			Checkpoints = {},
			KillParts = {},
			Animated = {},
		},
	}
end

local function right(ctx: Ctx): Vector3
	return Vector3.new(ctx.Dir.Z, 0, -ctx.Dir.X)
end

-- Blickrichtung um 90° drehen (für Zickzack/Spiralen)
local function turn(ctx: Ctx, direction: number) -- +1 = rechts, -1 = links
	ctx.Dir = if direction > 0 then right(ctx) else -right(ctx)
end

local function makePart(ctx: Ctx, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = ctx.Folder
	return part
end

-- Größe so drehen, dass "depth" entlang der Laufrichtung liegt
local function orientedSize(ctx: Ctx, width: number, height: number, depth: number): Vector3
	if math.abs(ctx.Dir.X) > 0.5 then
		return Vector3.new(depth, height, width)
	end
	return Vector3.new(width, height, depth)
end

-- Kern-Segment: Cursor um `forward` (Laufrichtung) und `dy` (Höhe) schieben,
-- dann Plattform width×1×depth mit Oberkante am Cursor setzen.
local function pad(ctx: Ctx, forward: number, dy: number, width: number, depth: number, opts: { [string]: any }?): Part
	opts = opts or {}
	local shift = (opts :: any).Shift or 0 -- seitlicher Versatz
	ctx.Pos += ctx.Dir * forward + Vector3.new(0, dy, 0) + right(ctx) * shift
	local part = makePart(ctx, {
		Name = (opts :: any).Name or "Pad",
		Size = orientedSize(ctx, width, 1, depth),
		Position = ctx.Pos - Vector3.new(0, 0.5, 0),
		Color = (opts :: any).Color or ctx.Def.Color,
		Material = (opts :: any).Material or Enum.Material.SmoothPlastic,
	})
	return part
end

-- Todes-Fläche auf Laufhöhe (Schoko-Lava & Co.): Berühren = zurück zum Checkpoint
local function killPad(ctx: Ctx, forward: number, width: number, depth: number, color: Color3?): Part
	local part = pad(ctx, forward, 0, width, depth, {
		Name = "Kill",
		Color = color or Color3.fromRGB(255, 80, 30),
		Material = Enum.Material.Neon,
	})
	-- Optisch minimal absenken, damit die sicheren Kanten klar lesbar sind
	part.Position -= Vector3.new(0, 0.15, 0)
	table.insert(ctx.Build.KillParts, part)
	return part
end

-- Rotierender Zuckerstangen-Balken über der aktuellen Plattform (Kill bei Berührung)
local function spinner(ctx: Ctx, radius: number, speed: number, phase: number)
	local center = ctx.Pos + Vector3.new(0, 1.6, 0)
	local bar = makePart(ctx, {
		Name = "Spinner",
		Size = Vector3.new(radius * 2, 0.8, 0.8),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(255, 70, 70),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local hub = makePart(ctx, {
		Name = "SpinnerHub",
		Size = Vector3.new(1.6, 2.4, 1.6),
		Position = center,
		Color = Color3.fromRGB(250, 250, 250),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	hub.Shape = Enum.PartType.Cylinder
	hub.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	table.insert(ctx.Build.KillParts, bar)
	table.insert(ctx.Build.Animated, {
		Part = bar,
		Kind = "spin" :: "spin",
		Base = CFrame.new(center),
		Speed = speed,
		Phase = phase,
	})
end

-- Blink-Plattform: Period Sekunden pro Zyklus, Duty-Anteil davon begehbar
local function blinkPad(ctx: Ctx, forward: number, dy: number, width: number, depth: number, period: number, phase: number, duty: number?)
	local part = pad(ctx, forward, dy, width, depth, {
		Name = "Blink",
		Color = Color3.fromRGB(255, 235, 150),
		Material = Enum.Material.Neon,
	})
	table.insert(ctx.Build.Animated, {
		Part = part,
		Kind = "blink" :: "blink",
		Base = part.CFrame,
		Speed = 0,
		Phase = phase,
		Period = period,
		Duty = duty or 0.55,
	})
end

-- Fahrende Plattform: Pendel-Mitte liegt `forward/2` Studs voraus, pendelt
-- entlang der Laufrichtung (axis="forward") oder seitlich (axis="side") um
-- ±amp. WICHTIG: Der Cursor rückt nur bis zur Pendel-MITTE vor – so landet
-- das nächste normale pad() (11-13 Studs) direkt hinter dem Pendel-Endpunkt
-- und bleibt erreichbar.
local function mover(ctx: Ctx, forward: number, dy: number, width: number, depth: number, axis: string, amp: number, speed: number, phase: number)
	ctx.Pos += ctx.Dir * (forward / 2) + Vector3.new(0, dy, 0)
	local part = makePart(ctx, {
		Name = "Mover",
		Size = orientedSize(ctx, width, 1, depth),
		Position = ctx.Pos - Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(150, 220, 255),
		Material = Enum.Material.Neon,
	})
	local offset = if axis == "side" then right(ctx) * amp else ctx.Dir * amp
	table.insert(ctx.Build.Animated, {
		Part = part,
		Kind = "move" :: "move",
		Base = part.CFrame,
		Speed = speed,
		Phase = phase,
		Offset = offset,
	})
end

-- Checkpoint: grünes Neon-Pad, Respawn-Punkt bei Sturz/Lava (nur dieser Lauf)
local function checkpoint(ctx: Ctx, forward: number, dy: number)
	local part = pad(ctx, forward, dy, 10, 8, {
		Name = "Checkpoint",
		Color = Color3.fromRGB(90, 230, 120),
		Material = Enum.Material.Neon,
	})
	table.insert(ctx.Build.Checkpoints, {
		Part = part,
		Spawn = CFrame.lookAlong(ctx.Pos + Vector3.new(0, 3.5, 0), ctx.Dir),
	})
end

-- Neon-Torbogen quer zum Weg (Start-/Ziellinie): unsichtbare Touch-Wand + Optik
local function gate(ctx: Ctx, label: string, color: Color3): BasePart
	local width = 14
	local base = ctx.Pos
	for _, side in { -1, 1 } do
		makePart(ctx, {
			Name = "GatePillar",
			Size = Vector3.new(1.6, 10, 1.6),
			Position = base + right(ctx) * (side * width / 2) + Vector3.new(0, 5, 0),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end
	makePart(ctx, {
		Name = "GateTop",
		Size = orientedSize(ctx, width + 1.6, 1.4, 1.6),
		Position = base + Vector3.new(0, 10.2, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local line = makePart(ctx, {
		Name = label,
		Size = orientedSize(ctx, width, 9, 1),
		Position = base + Vector3.new(0, 5, 0),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 0.6,
		CanCollide = false,
	})
	return line
end

-- ══════════ Die 8 Layouts ══════════
-- Schwierigkeit steigt: erst nur Sprünge, dann Lava, Spinner, Blinker,
-- Mover – und die langen Parcours kombinieren alles (mit Checkpoints).

local function courseZuckerstange(ctx: Ctx) -- 1: nur Hüpfen, breite Pads
	for i = 1, 4 do
		pad(ctx, 12, 0, 10, 8, { Shift = if i % 2 == 0 then 3 else -3 })
	end
	pad(ctx, 12, 3, 10, 8)
	pad(ctx, 12, 3, 10, 8)
	for i = 1, 3 do
		pad(ctx, 13, 0, 9, 7, { Shift = if i % 2 == 0 then -4 else 4 })
	end
	pad(ctx, 13, -3, 10, 8)
	pad(ctx, 13, -3, 12, 10)
end

local function courseSchoko(ctx: Ctx) -- 2: Höhenstufen + Schoko-Lava
	local lava = Color3.fromRGB(140, 60, 20)
	pad(ctx, 12, 3, 9, 7)
	pad(ctx, 12, 3, 9, 7)
	pad(ctx, 12, 3, 8, 6)
	-- Lava-Teppich: sichere Streifen, dazwischen heiße Schokolade
	pad(ctx, 12, 0, 14, 5)
	for _ = 1, 3 do
		killPad(ctx, 4.5, 14, 4, lava)
		pad(ctx, 4.5, 0, 14, 4)
	end
	pad(ctx, 13, 2, 8, 6)
	pad(ctx, 13, 2, 7, 6)
	killPad(ctx, 5, 14, 5, lava)
	pad(ctx, 5.5, 0, 12, 6)
	pad(ctx, 13, -4, 10, 8)
	pad(ctx, 13, -4, 12, 10)
end

local function courseBonbon(ctx: Ctx) -- 3: Spinner + Zickzack-Stege
	pad(ctx, 12, 0, 10, 8)
	pad(ctx, 13, 1, 12, 12)
	spinner(ctx, 6.5, 2.4, 0)
	pad(ctx, 14, 1, 12, 12)
	spinner(ctx, 6.5, -3, 2)
	-- Zickzack-Stege
	pad(ctx, 12, 0, 4, 10)
	turn(ctx, 1)
	pad(ctx, 10, 0, 4, 10)
	turn(ctx, -1)
	pad(ctx, 10, 0, 4, 10)
	turn(ctx, -1)
	pad(ctx, 10, 0, 4, 10)
	turn(ctx, 1)
	pad(ctx, 12, 1, 12, 12)
	spinner(ctx, 7, 3.4, 4)
	pad(ctx, 14, -1, 12, 10)
end

local function courseWaffel(ctx: Ctx) -- 4: Blink-Platten in zwei Wellen
	pad(ctx, 12, 0, 10, 8)
	for i = 1, 4 do
		blinkPad(ctx, 11, 0, 7, 6, 3.2, (i % 2) * 0.5)
	end
	checkpoint(ctx, 12, 0)
	pad(ctx, 12, 2, 8, 6)
	for i = 1, 5 do
		blinkPad(ctx, 11, 1, 6, 5, 2.6, (i % 3) / 3, 0.5)
	end
	pad(ctx, 12, 0, 10, 8)
	spinner(ctx, 5.5, 2.8, 1)
	pad(ctx, 13, -2, 12, 10)
end

local function courseDonut(ctx: Ctx) -- 5: Mover + schmale Stege + alles zusammen
	pad(ctx, 12, 0, 10, 8)
	mover(ctx, 26, 0, 7, 7, "forward", 7, 1.6, 0)
	pad(ctx, 12, 0, 8, 6)
	-- Schmaler Zuckerguss-Steg mit Seiten-Movern als Zwischenstationen
	pad(ctx, 11, 0, 2.5, 14)
	mover(ctx, 24, 0, 6, 6, "side", 8, 1.9, 2)
	pad(ctx, 12, 0, 8, 6)
	checkpoint(ctx, 11, 0)
	pad(ctx, 12, 1, 12, 12)
	spinner(ctx, 6.5, 3.2, 0)
	for i = 1, 3 do
		blinkPad(ctx, 11, 1, 6, 5, 2.4, (i % 2) * 0.5, 0.5)
	end
	pad(ctx, 12, 0, 2.5, 12)
	pad(ctx, 13, -2, 12, 10)
end

local function courseKaramell(ctx: Ctx) -- 6 (LANG): der große Turm
	pad(ctx, 12, 0, 10, 8)
	for _ = 1, 4 do
		pad(ctx, 12, 3, 8, 6)
	end
	checkpoint(ctx, 12, 2)
	-- Spiral-Aufstieg: alle 2 Pads rechts abbiegen, stetig höher
	for round = 1, 4 do
		pad(ctx, 12, 3, 7, 6)
		pad(ctx, 12, 3, 6, 6)
		turn(ctx, 1)
		if round == 2 then
			checkpoint(ctx, 12, 3)
		end
	end
	checkpoint(ctx, 12, 3)
	-- Karamell-Lava-Ring
	pad(ctx, 12, 0, 14, 5)
	for _ = 1, 2 do
		killPad(ctx, 4.5, 14, 4, Color3.fromRGB(220, 140, 40))
		pad(ctx, 4.5, 0, 14, 4)
	end
	-- Blink-Brücke hoch zum Gipfel
	for i = 1, 4 do
		blinkPad(ctx, 11, 2, 6, 5, 3, (i % 2) * 0.5)
	end
	checkpoint(ctx, 12, 1)
	pad(ctx, 12, 2, 12, 12)
	spinner(ctx, 6.5, 3, 0)
	pad(ctx, 14, 2, 2.5, 14)
	pad(ctx, 11, 2, 2.5, 14)
	pad(ctx, 12, 0, 14, 12)
end

local function courseLakritz(ctx: Ctx) -- 7 (LANG): dunkles Steg-Labyrinth
	local black = Color3.fromRGB(45, 40, 50)
	pad(ctx, 12, 0, 10, 8)
	-- Zickzack aus schmalen Lakritz-Stegen
	for i = 1, 5 do
		pad(ctx, 11, 0, 3, 12, { Color = black })
		turn(ctx, if i % 2 == 0 then -1 else 1)
	end
	checkpoint(ctx, 11, 0)
	-- Spinner-Gauntlet: drei Wirbel hintereinander
	for i = 1, 3 do
		pad(ctx, 12, 1, 12, 12, { Color = black })
		spinner(ctx, 6.5, if i % 2 == 0 then -3.2 else 3.2, i * 1.5)
	end
	checkpoint(ctx, 13, 0)
	-- Blink-Korridor (schnell!)
	for i = 1, 6 do
		blinkPad(ctx, 11, 0, 6, 5, 2.6, (i % 3) / 3, 0.5)
	end
	checkpoint(ctx, 12, 0)
	-- Finale: Seiten-Mover + Mini-Stege
	mover(ctx, 24, 0, 6, 6, "side", 8, 2.2, 0)
	pad(ctx, 12, 0, 2.5, 12, { Color = black })
	mover(ctx, 24, 2, 6, 6, "forward", 7, 2, 3)
	pad(ctx, 12, 0, 2.5, 12, { Color = black })
	pad(ctx, 12, -2, 14, 12)
end

local function courseVulkan(ctx: Ctx) -- 8 (LANG): das Lava-Finale
	local lava = Color3.fromRGB(255, 90, 20)
	pad(ctx, 12, 0, 10, 8)
	-- Lava-See mit Mini-Inseln
	for i = 1, 5 do
		killPad(ctx, 5, 16, 5, lava)
		pad(ctx, 5.5, 0, 5, 5, { Shift = if i % 2 == 0 then 4 else -4 })
	end
	checkpoint(ctx, 12, 0)
	-- Mover-Kette über den Krater
	mover(ctx, 24, 2, 6, 6, "forward", 6, 2, 0)
	pad(ctx, 11, 0, 4, 5)
	mover(ctx, 24, 2, 6, 6, "side", 8, 2.3, 2)
	pad(ctx, 11, 0, 4, 5)
	mover(ctx, 24, 2, 5, 5, "forward", 7, 2.5, 4)
	checkpoint(ctx, 12, 0)
	-- Wirbel + Blinker gleichzeitig
	pad(ctx, 12, 1, 12, 12)
	spinner(ctx, 7, 3.6, 0)
	for i = 1, 4 do
		blinkPad(ctx, 11, 1, 6, 5, 2.2, (i % 2) * 0.5, 0.5)
	end
	pad(ctx, 12, 1, 12, 12)
	spinner(ctx, 7, -3.8, 1)
	checkpoint(ctx, 13, 0)
	-- Kraterrand: schmaler Aufstieg mit Lava-Streifen
	pad(ctx, 11, 2, 2.5, 12)
	pad(ctx, 11, 2, 2.5, 12)
	pad(ctx, 12, 0, 14, 5)
	for _ = 1, 2 do
		killPad(ctx, 4.5, 14, 4, lava)
		pad(ctx, 4.5, 0, 14, 4)
	end
	pad(ctx, 13, 3, 8, 6)
	pad(ctx, 13, 3, 14, 12)
end

local COURSE_BUILDERS: { [string]: (Ctx) -> () } = {
	Zuckerstange = courseZuckerstange,
	Schoko = courseSchoko,
	Bonbon = courseBonbon,
	Waffel = courseWaffel,
	Donut = courseDonut,
	Karamell = courseKaramell,
	Lakritz = courseLakritz,
	Vulkan = courseVulkan,
}

-- ══════════ Arena-Rahmen (Start, Ziel, Auffangnetz, Deko) ══════════

local function buildCourse(def, index: number, parent: Folder): CourseBuild
	local origin = Vector3.new(-3500 + (index - 1) * 1000, 400, 4000)

	local folder = Instance.new("Folder")
	folder.Name = "Arena_" .. def.Id
	folder.Parent = parent

	local ctx = newCtx(def, origin, folder)

	-- Start-Plattform + Spawn (Blick in Laufrichtung)
	local startPad = pad(ctx, 0, 0, 16, 16, { Name = "StartPad" })
	ctx.Build.SpawnCFrame = CFrame.lookAlong(ctx.Pos + Vector3.new(0, 3.5, 0), ctx.Dir)

	-- Namensschild schwebend über dem Start
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(340, 44)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.Name
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = def.Color
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = startPad

	-- Startlinie kurz vor der ersten Plattform
	ctx.Pos += ctx.Dir * 7
	ctx.Build.StartPart = gate(ctx, "StartLine", Color3.fromRGB(120, 255, 120))
	ctx.Pos -= ctx.Dir * 7 -- Cursor zurück: das erste Segment misst ab Pad-Mitte

	-- Hindernis-Strecke
	COURSE_BUILDERS[def.Id](ctx)

	-- Ziellinie + Zielplattform
	ctx.Pos += ctx.Dir * 2
	ctx.Build.FinishPart = gate(ctx, "FinishLine", Color3.fromRGB(255, 215, 0))
	pad(ctx, 10, 0, 16, 14, { Name = "FinishPad", Color = Color3.fromRGB(255, 215, 0) })

	-- Auffangnetz weit unter der Arena: Sturz = zurück zum Checkpoint.
	-- Großzügig dimensioniert, damit auch weite Abflüge sicher landen.
	local catcher = makePart(ctx, {
		Name = "FallCatcher",
		Size = Vector3.new(900, 4, 900),
		Position = origin + Vector3.new(0, -70, 250),
		Transparency = 1,
		CanCollide = false,
	})
	table.insert(ctx.Build.KillParts, catcher)

	return ctx.Build
end

-- Baut alle Arenen; Rückgabe indexiert wie Config.ParkourCourses
function ParkourMap.BuildAll(): { CourseBuild }
	local root = Instance.new("Folder")
	root.Name = "ParkourArenas"
	root.Parent = workspace

	local builds = {}
	for index, def in Config.ParkourCourses do
		builds[index] = buildCourse(def, index, root)
	end
	return builds
end

return ParkourMap
