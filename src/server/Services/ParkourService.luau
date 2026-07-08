--[[
	ParkourService.luau
	Das Parkour-Minigame: Portal-Hub auf der Hauptmap, 8 separate Arenen
	(ParkourMap-Modul), Zeitmessung, Freischaltungs-Kette und Belohnungen
	(Cash + Juwelen über den GemService).

	Server-Autorität komplett hier:
	- Portal-Touch prüft Freischaltung (GemService-Datensatz) + Cooldown
	- Zeitmessung über Start-/Ziellinien-Touch mit workspace:GetServerTimeNow()
	  (synchronisierte Uhr -> der Client zeigt exakt dieselbe Zeit an)
	- Belohnung nach Config.ParkourReward (Cash skaliert mit Rebirth-Multi,
	  Juwelen nicht), Rück-Teleport nach kurzer Ergebnis-Pause
	- Lava/Spinner/Sturz = zurück zum letzten Checkpoint (Timer läuft weiter!)
	- Server-Bestzeit pro Parcours am Portal (Session-Leaderboard)
	- Meister-Belohnung: alle 8 unter Config-MasterTime -> exklusiver
	  "Juwelensturm"-Trail (einmalig, landet in profile.Trails wie beim
	  Season-Pass – StyleService kennt den Trail über Config.GemTrails)

	Client-Anzeige läuft rein über replizierende Attribute am Player:
	ParkourCourse (Id des aktiven Laufs) + ParkourStart (Serverzeit, 0 = noch
	vor der Startlinie) + ParkourUnlocked (setzt der GemService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ParkourMap = require(script.Parent.Parent.Modules.ParkourMap)

local ParkourService = {}

local DataService, PlayerService, GemService -- in Init verdrahtet

local notifyRemote: RemoteEvent
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent
local resultRemote: RemoteEvent

local builds: { ParkourMap.CourseBuild } = {}

-- Hub-Positionen (südlich hinter dem Spawn, weit weg von Straße & Basen)
local HUB_CENTER = Vector3.new(0, 0, 228)
local RETURN_CFRAME = CFrame.lookAlong(Vector3.new(0, 3.5, 214), -Vector3.zAxis)

type Run = {
	Index: number,
	Def: any,
	Phase: "ready" | "running" | "done",
	EnteredAt: number, -- os.clock beim Teleport
	StartAt: number, -- workspace:GetServerTimeNow() an der Startlinie
	Checkpoint: CFrame,
}

local runs: { [Player]: Run } = {}
local cooldownUntil: { [Player]: { [string]: number } } = {} -- os.clock-Zeitpunkte
local touchDebounce: { [Player]: number } = {}
local serverBest: { [string]: { Name: string, Time: number } } = {}
local bestLabels: { [string]: TextLabel } = {} -- Leaderboard-Zeile pro Portal

-- ══════════ Helfer ══════════

local function playerFromHit(hit: BasePart): Player?
	local character = hit.Parent
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function formatTime(seconds: number): string
	return string.format("%.2fs", seconds)
end

local function refreshBoard(courseId: string)
	local label = bestLabels[courseId]
	if not label then
		return
	end
	local best = serverBest[courseId]
	label.Text = if best
		then ("🏆 %s – %s"):format(best.Name, formatTime(best.Time))
		else "🏆 Bestzeit: noch keine!"
end

-- ══════════ Lauf-Lebenszyklus ══════════

local function setRunAttributes(player: Player, courseId: string?, startAt: number?)
	player:SetAttribute("ParkourCourse", courseId)
	player:SetAttribute("ParkourStart", startAt)
end

local function teleportToHub(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		character:PivotTo(RETURN_CFRAME)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

-- Lauf beenden (ohne Belohnung). teleport=false z.B. nach Tod/Respawn.
local function cancelRun(player: Player, message: string?, teleport: boolean?)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil
	setRunAttributes(player, nil, nil)
	if message then
		notifyRemote:FireClient(player, message)
	end
	if teleport ~= false then
		teleportToHub(player)
	end
end

local function startCourse(player: Player, index: number)
	local def = Config.ParkourCourses[index]
	local build = builds[index]
	if not def or not build then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	runs[player] = {
		Index = index,
		Def = def,
		Phase = "ready",
		EnteredAt = os.clock(),
		StartAt = 0,
		Checkpoint = build.SpawnCFrame,
	}
	character:PivotTo(build.SpawnCFrame)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	setRunAttributes(player, def.Id, 0)
	notifyRemote:FireClient(player, "🏁 Lauf durch das GRÜNE Tor – dann läuft die Zeit!")
	sfxRemote:FireClient(player, "grab")
end

-- Portal berührt: alle Checks, dann ab in die Arena
local function tryEnter(player: Player, index: number)
	local now = os.clock()
	if now - (touchDebounce[player] or 0) < 1 then
		return
	end
	touchDebounce[player] = now

	if runs[player] then
		return -- schon in einem Lauf
	end
	if player:GetAttribute("Snackified") then
		notifyRemote:FireClient(player, "🍫 Als SNACK wird nicht geklettert!")
		return
	end
	if player:GetAttribute("HoldingSnack") then
		notifyRemote:FireClient(player, "✋ Erst den Snack loswerden, dann Parkour!")
		return
	end

	local record = GemService.Get(player)
	if not record then
		notifyRemote:FireClient(player, "⏳ Daten laden noch – gleich nochmal probieren!")
		return
	end
	if index > record.Unlocked then
		local needed = Config.ParkourCourses[record.Unlocked]
		notifyRemote:FireClient(
			player,
			("🔒 Noch gesperrt! Schaffe zuerst %s."):format(needed and needed.Name or "den vorherigen Parcours")
		)
		return
	end

	local def = Config.ParkourCourses[index]
	local cds = cooldownUntil[player]
	local readyAt = cds and cds[def.Id] or 0
	if now < readyAt then
		notifyRemote:FireClient(player, ("⏱️ Kurz verschnaufen! %s in %ds wieder offen."):format(def.Name, math.ceil(readyAt - now)))
		return
	end

	startCourse(player, index)
end

-- Ziellinie: Zeit stoppen, Belohnung, Bestzeiten, Rück-Teleport
local function finishRun(player: Player, run: Run)
	run.Phase = "done"
	local elapsed = math.max(0.01, workspace:GetServerTimeNow() - run.StartAt)
	local def = run.Def

	-- Cooldown ab jetzt (gilt für Erfolg UND späteres Abbrechen gleichermaßen)
	local cds = cooldownUntil[player]
	if not cds then
		cds = {}
		cooldownUntil[player] = cds
	end
	cds[def.Id] = os.clock() + def.Cooldown

	-- Belohnung: Cash mit Rebirth-Multiplikator, Juwelen pur
	local cash, gems = Config.ParkourReward(def, elapsed)
	cash = math.floor(cash * DataService.GetMultiplier(player))
	PlayerService.AddCash(player, cash)
	GemService.AddGems(player, gems)

	local record = GemService.Get(player)
	local personalBest = false
	local unlockedNext = false
	if record then
		-- Nächsten Parcours freischalten (nur beim ERSTEN Abschluss des höchsten)
		if run.Index == record.Unlocked and record.Unlocked < #Config.ParkourCourses then
			record.Unlocked += 1
			unlockedNext = true
			GemService.MarkDirty(player)
			GemService.Sync(player)
		end
		-- Persönliche Bestzeit
		local oldBest = record.BestTimes[def.Id]
		if not oldBest or elapsed < oldBest then
			record.BestTimes[def.Id] = elapsed
			personalBest = true
			GemService.MarkDirty(player)
		end
		-- Meister-Check: alle 8 unter der MasterTime -> Juwelensturm-Trail
		if not record.MasterGranted then
			local master = true
			for _, courseDef in Config.ParkourCourses do
				local best = record.BestTimes[courseDef.Id]
				if not best or best > courseDef.MasterTime then
					master = false
					break
				end
			end
			if master then
				record.MasterGranted = true
				GemService.MarkDirty(player)
				local profile = DataService.Get(player)
				if profile then
					profile.Trails["Juwelensturm"] = true
				end
				announceRemote:FireAllClients(
					("👑 %s hat ALLE 8 Parcours unter der Meister-Zeit geschafft – JUWELENSTURM freigeschaltet!"):format(player.Name),
					"Mythic"
				)
			end
		end
	end

	-- Server-Bestzeit (Session-Leaderboard am Portal)
	local best = serverBest[def.Id]
	local serverRecord = not best or elapsed < best.Time
	if serverRecord then
		serverBest[def.Id] = { Name = player.Name, Time = elapsed }
		refreshBoard(def.Id)
		announceRemote:FireAllClients(
			("🏁 SERVER-REKORD! %s rennt %s in %s!"):format(player.Name, def.Name, formatTime(elapsed)),
			"Legendary"
		)
	end

	sfxRemote:FireClient(player, "bank")
	resultRemote:FireClient(player, {
		Name = def.Name,
		Time = elapsed,
		Cash = cash,
		Gems = gems,
		ServerRecord = serverRecord,
		PersonalBest = personalBest,
		UnlockedNext = unlockedNext,
	})
	if unlockedNext then
		local nextDef = Config.ParkourCourses[run.Index + 1]
		notifyRemote:FireClient(player, ("🔓 NEU: %s ist jetzt offen!"):format(nextDef.Name))
	end

	-- Kurz das Ergebnis feiern lassen, dann zurück zum Hub
	task.delay(Config.ParkourReturnDelay, function()
		if runs[player] == run then
			runs[player] = nil
			setRunAttributes(player, nil, nil)
			teleportToHub(player)
		end
	end)
end

-- ══════════ Arena-Verdrahtung (Touch-Events) ══════════

local killDebounce: { [Player]: number } = {}

local function wireCourse(index: number, build: ParkourMap.CourseBuild)
	local def = Config.ParkourCourses[index]

	build.StartPart.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local run = player and runs[player :: Player]
		if not player or not run or run.Index ~= index or run.Phase ~= "ready" then
			return
		end
		run.Phase = "running"
		run.StartAt = workspace:GetServerTimeNow()
		setRunAttributes(player, def.Id, run.StartAt)
		sfxRemote:FireClient(player, "ding")
	end)

	build.FinishPart.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local run = player and runs[player :: Player]
		if not player or not run or run.Index ~= index or run.Phase ~= "running" then
			return
		end
		finishRun(player, run :: Run)
	end)

	for _, cp in build.Checkpoints do
		cp.Part.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			local run = player and runs[player :: Player]
			if player and run and run.Index == index then
				(run :: Run).Checkpoint = cp.Spawn
			end
		end)
	end

	for _, killPart in build.KillParts do
		killPart.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if not player then
				return
			end
			local run = runs[player]
			if not run or run.Index ~= index or run.Phase == "done" then
				return
			end
			local now = os.clock()
			if now - (killDebounce[player] or 0) < 0.5 then
				return
			end
			killDebounce[player] = now
			local character = player.Character
			if character then
				character:PivotTo(run.Checkpoint)
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
			sfxRemote:FireClient(player, "oof")
		end)
	end
end

-- ══════════ Hindernis-Animationen (ein Loop für alles) ══════════

local function startAnimationLoop()
	local animated: { ParkourMap.Animated } = {}
	for _, build in builds do
		for _, item in build.Animated do
			table.insert(animated, item)
		end
	end

	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, item in animated do
			if item.Kind == "spin" then
				item.Part.CFrame = item.Base * CFrame.Angles(0, t * item.Speed + item.Phase, 0)
			elseif item.Kind == "move" and item.Offset then
				item.Part.CFrame = item.Base + item.Offset * math.sin(t * item.Speed + item.Phase)
			elseif item.Kind == "blink" then
				local period = item.Period or 3
				local duty = item.Duty or 0.55
				local cycle = (t / period + item.Phase) % 1
				local visible = cycle < duty
				item.Part.CanCollide = visible
				if visible then
					-- Kurz vorm Verschwinden halbtransparent = faire Vorwarnung
					item.Part.Transparency = if cycle > duty * 0.65 then 0.45 else 0
				else
					item.Part.Transparency = 0.9
				end
			end
		end
	end)
end

-- ══════════ Portal-Hub auf der Hauptmap ══════════

local function makeHubPart(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function buildPortal(parent: Folder, index: number, position: Vector3)
	local def = Config.ParkourCourses[index]
	local folder = Instance.new("Folder")
	folder.Name = "Portal_" .. def.Id
	folder.Parent = parent

	-- Sockel
	makeHubPart(folder, {
		Name = "Base",
		Size = Vector3.new(12, 1, 8),
		Position = position + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(240, 240, 245),
		Material = Enum.Material.SmoothPlastic,
	})
	-- Rahmen: lange Parcours kriegen den dickeren, höheren Bogen
	local tall = if def.Short then 9 else 11
	for _, side in { -1, 1 } do
		makeHubPart(folder, {
			Name = "Pillar",
			Size = Vector3.new(1.6, tall, 1.6),
			Position = position + Vector3.new(side * 4, tall / 2 + 1, 0),
			Color = def.Color,
			Material = Enum.Material.SmoothPlastic,
		})
	end
	makeHubPart(folder, {
		Name = "Arch",
		Size = Vector3.new(9.6, 1.6, 1.6),
		Position = position + Vector3.new(0, tall + 1.3, 0),
		Color = def.Color,
		Material = Enum.Material.SmoothPlastic,
	})
	-- Die eigentliche Portal-Fläche (Touch = Betreten). Der Client dunkelt
	-- sie lokal ab, solange der Parcours für IHN noch gesperrt ist.
	local fill = makeHubPart(folder, {
		Name = "Fill",
		Size = Vector3.new(6.4, tall - 0.5, 0.8),
		Position = position + Vector3.new(0, (tall - 0.5) / 2 + 1, 0),
		Color = def.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	})

	-- Schild: Name + Kurz/Lang + Server-Bestzeit
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(250, 76)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.MaxDistance = 140
	billboard.Parent = fill

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = ("%d. %s"):format(index, def.Name)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextColor3 = def.Color
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Parent = billboard

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, 0, 0, 20)
	infoLabel.Position = UDim2.fromOffset(0, 30)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = if def.Short then "⚡ KURZ" else "🔥 LANG & FETT BELOHNT"
	infoLabel.TextScaled = true
	infoLabel.Font = Enum.Font.FredokaOne
	infoLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
	infoLabel.TextStrokeTransparency = 0.3
	infoLabel.Parent = billboard

	local bestLabel = Instance.new("TextLabel")
	bestLabel.Size = UDim2.new(1, 0, 0, 20)
	bestLabel.Position = UDim2.fromOffset(0, 52)
	bestLabel.BackgroundTransparency = 1
	bestLabel.Text = "🏆 Bestzeit: noch keine!"
	bestLabel.TextScaled = true
	bestLabel.Font = Enum.Font.FredokaOne
	bestLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	bestLabel.TextStrokeTransparency = 0.3
	bestLabel.Parent = billboard
	bestLabels[def.Id] = bestLabel

	fill.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			tryEnter(player, index)
		end
	end)
end

local function buildHub()
	local folder = Instance.new("Folder")
	folder.Name = "ParkourHub"
	folder.Parent = workspace

	-- Plaza-Boden
	makeHubPart(folder, {
		Name = "Plaza",
		Size = Vector3.new(180, 0.4, 38),
		Position = HUB_CENTER + Vector3.new(0, 0.2, 0),
		Color = Color3.fromRGB(170, 140, 220),
		Material = Enum.Material.SmoothPlastic,
	})
	-- Großes Hub-Schild in der Mitte
	local sign = makeHubPart(folder, {
		Name = "HubSign",
		Size = Vector3.new(26, 4, 1),
		Position = HUB_CENTER + Vector3.new(0, 17, 17),
		Color = Color3.fromRGB(25, 25, 35),
		Material = Enum.Material.Neon,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(1000, 160)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "🌀 PARKOUR-PORTALE 🌀"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(170, 140, 255)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = sign
	end
	-- Rückkehr-Pad (hier landet man nach jedem Lauf)
	makeHubPart(folder, {
		Name = "ReturnPad",
		Size = Vector3.new(10, 0.5, 10),
		Position = Vector3.new(0, 0.45, 214),
		Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})

	-- 8 Portale in einer Reihe, Blick Richtung Spawn (Norden)
	for index = 1, #Config.ParkourCourses do
		local x = -105 + (index - 1) * 30
		buildPortal(folder, index, Vector3.new(x, 0, HUB_CENTER.Z + 12))
	end
end

-- ══════════ Debug-Hooks (fürs Test-Menü) ══════════

function ParkourService.DebugUnlockAll(player: Player): string
	local record = GemService.Get(player)
	if not record then
		return "Parkour-Daten noch nicht geladen..."
	end
	record.Unlocked = #Config.ParkourCourses
	GemService.MarkDirty(player)
	GemService.Sync(player)
	return ("Alle %d Parcours für %s freigeschaltet."):format(#Config.ParkourCourses, player.Name)
end

function ParkourService.DebugResetCooldowns(player: Player)
	cooldownUntil[player] = nil
end

-- ══════════ Init ══════════

function ParkourService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	GemService = services.GemService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent
	resultRemote = Remotes.Get("ParkourResult") :: RemoteEvent;

	-- Freiwillig aufgeben: zurück zum Hub, keine Belohnung, Cooldown läuft
	(Remotes.Get("ParkourLeave") :: RemoteEvent).OnServerEvent:Connect(function(player)
		local run = runs[player]
		if not run or run.Phase == "done" then
			return
		end
		local cds = cooldownUntil[player]
		if not cds then
			cds = {}
			cooldownUntil[player] = cds
		end
		cds[run.Def.Id] = os.clock() + run.Def.Cooldown
		cancelRun(player, "🏳️ Lauf abgebrochen – der Hub hat dich wieder.")
	end)

	builds = ParkourMap.BuildAll()
	for index, build in builds do
		wireCourse(index, build)
	end
	buildHub()
	startAnimationLoop()

	-- Wachhund: Trödler vor der Startlinie + Zeitüberschreitung
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			local serverNow = workspace:GetServerTimeNow()
			for player, run in runs do
				if run.Phase == "ready" and now - run.EnteredAt > Config.ParkourReadyTimeout then
					cancelRun(player, "💤 Zu lange getrödelt – zurück zum Hub!")
				elseif run.Phase == "running" and serverNow - run.StartAt > run.Def.MaxTime then
					local cds = cooldownUntil[player]
					if not cds then
						cds = {}
						cooldownUntil[player] = cds
					end
					cds[run.Def.Id] = now + run.Def.Cooldown
					cancelRun(player, "⏰ Zeit abgelaufen! Beim nächsten Mal klappt's.")
				end
			end
		end
	end)

	-- Tod/Respawn während eines Laufs = Abbruch (Spawn ist eh auf der Hauptmap)
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			if runs[player] then
				cancelRun(player, "💀 Autsch! Lauf abgebrochen.", false)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		cooldownUntil[player] = nil
		touchDebounce[player] = nil
		killDebounce[player] = nil
	end)
end

return ParkourService
