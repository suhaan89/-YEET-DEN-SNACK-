--[[
	init.client.luau
	Client-Bootstrap für "YEET DEN SNACK!"
	- Baut das UI (Ui.luau)
	- Input: Linksklick/Touch-Button halten = YEET aufladen, loslassen = werfen
	         Q / Touch-Button = SLAP
	- Empfängt Ankündigungen & Benachrichtigungen vom Server
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local SnackTypes = require(shared:WaitForChild("SnackTypes"))
local Remotes = require(shared:WaitForChild("Remotes"))
local Ui = require(script:WaitForChild("Ui"))
local SoundFx = require(script:WaitForChild("SoundFx"))

local player = Players.LocalPlayer

Ui.Build()

-- ══════════ Kamera-Shake (kurz & knackig) ══════════

local function cameraShake(intensity: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local elapsed = 0
		while elapsed < 0.45 do
			local dt = task.wait()
			elapsed += dt
			local falloff = 1 - elapsed / 0.45
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * intensity * falloff,
				(math.random() - 0.5) * intensity * falloff,
				0
			)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

local slapRemote = Remotes.Get("Slap") :: RemoteEvent
local throwRemote = Remotes.Get("ThrowRequest") :: RemoteEvent;

-- ══════════ Server-Nachrichten ══════════

(Remotes.Get("Announce") :: RemoteEvent).OnClientEvent:Connect(function(text, rarity)
	Ui.Announce(text, rarity)
end);

(Remotes.Get("Notify") :: RemoteEvent).OnClientEvent:Connect(function(text)
	Ui.Toast(text)
end);

-- ══════════ Basis-Flash bei Treffer ══════════
-- Landet ein Snack in einer Basis-Zone, leuchtet die getroffene Basis kurz auf.
-- Getriggert über das "bank"-Sound-Event (kommt mit der Einschlag-Position).

local function flashBaseAt(position: Vector3)
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	for _, folder in map:GetChildren() do
		if not folder.Name:match("^Base_") then
			continue
		end
		local floor = folder:FindFirstChild("Floor")
		if not (floor and floor:IsA("BasePart")) then
			continue
		end
		local offset = position - floor.Position
		if math.abs(offset.X) > floor.Size.X / 2 + 2 or math.abs(offset.Z) > floor.Size.Z / 2 + 2 then
			continue
		end
		-- Treffer! Boden + Tresor golden aufblitzen lassen
		for _, partName in { "Floor", "Vault" } do
			local part = folder:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				local highlight = Instance.new("Highlight")
				highlight.FillColor = Color3.fromRGB(255, 220, 80)
				highlight.OutlineColor = Color3.fromRGB(255, 240, 160)
				highlight.FillTransparency = 0.15
				highlight.OutlineTransparency = 0
				highlight.Parent = part
				TweenService:Create(highlight, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					FillTransparency = 1,
					OutlineTransparency = 1,
				}):Play()
				task.delay(0.75, function()
					highlight:Destroy()
				end)
			end
		end
		return
	end
end

-- Sound-Effekte vom Server (mit Entfernungs-Check)
(Remotes.Get("Sfx") :: RemoteEvent).OnClientEvent:Connect(function(name, position)
	SoundFx.Play(name, position)
	if name == "bank" and typeof(position) == "Vector3" then
		flashBaseAt(position)
	end
end);

-- Shop-Gebäude betreten (ProximityPrompt) -> Server sagt uns, welches Fenster aufgeht
(Remotes.Get("OpenShop") :: RemoteEvent).OnClientEvent:Connect(function(shopId)
	if typeof(shopId) == "string" then
		Ui.OpenShop(shopId)
	end
end);

-- Fling: Server sagt "du fliegst" – wir wenden den Impuls lokal an,
-- weil der Client die Physik seines eigenen Charakters besitzt.
(Remotes.Get("Fling") :: RemoteEvent).OnClientEvent:Connect(function(velocity, spin)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and typeof(velocity) == "Vector3" then
		root.AssemblyLinearVelocity = velocity
		if typeof(spin) == "Vector3" then
			root.AssemblyAngularVelocity = spin
		end
	end
	cameraShake(1.6)
end)

-- ══════════ Heimweg-Beam (zeigt beim Tragen den Weg zur eigenen Basis) ══════════

local beamParts: { Instance } = {}

local function clearBeam()
	for _, inst in beamParts do
		inst:Destroy()
	end
	table.clear(beamParts)
end

local function showBeam()
	clearBeam()
	local vaultPos = player:GetAttribute("VaultPos")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if typeof(vaultPos) ~= "Vector3" or not root then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = vaultPos + Vector3.new(0, 6, 0)
	anchor.Parent = workspace

	local att0 = Instance.new("Attachment")
	att0.Parent = root
	local att1 = Instance.new("Attachment")
	att1.Parent = anchor

	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 220, 80))
	beam.Transparency = NumberSequence.new(0.4)
	beam.Width0 = 0.8
	beam.Width1 = 0.2
	beam.FaceCamera = true
	beam.Parent = root

	table.insert(beamParts, anchor)
	table.insert(beamParts, att0)
	table.insert(beamParts, beam)
end

-- ══════════ Flugbahn-Vorschau ══════════
-- Gepunktete Wurfkurve beim Aufladen – nutzt exakt dieselbe Formel wie der
-- Server (SnackService.onThrowRequest), damit die Vorhersage stimmt.

local DOT_COUNT = 14
local trajectoryDots: { BasePart } = {}

local function ensureDots()
	if #trajectoryDots > 0 then
		return
	end
	for i = 1, DOT_COUNT do
		local dot = Instance.new("Part")
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.one * 0.5
		dot.Material = Enum.Material.Neon
		dot.Color = Color3.fromRGB(255, 220, 80)
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.Transparency = 0.15 + (i / DOT_COUNT) * 0.55 -- hinten ausblenden
		table.insert(trajectoryDots, dot)
	end
end

-- Landing-Ring: leuchtender Kreis am voraussichtlichen Aufschlagpunkt
local landingRing: BasePart? = nil

local function ensureLandingRing(): BasePart
	if landingRing then
		return landingRing
	end
	local ring = Instance.new("Part")
	ring.Name = "LandingRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.25, 7, 7)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 220, 80)
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	landingRing = ring
	return ring
end

local function hideTrajectory()
	for _, dot in trajectoryDots do
		dot.Parent = nil
	end
	if landingRing then
		landingRing.Parent = nil
	end
end

-- Flugbahn weitersimulieren und per Raycast den Boden-Treffpunkt finden.
-- Gleiche Physik wie die Punkte-Vorschau, nur länger (bis ~3,5 Sek. Flugzeit).
local function updateLandingRing(origin: Vector3, velocity: Vector3, gravity: Vector3)
	local ring = ensureLandingRing()

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { ring }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local snacks = workspace:FindFirstChild("Snacks")
	if snacks then
		table.insert(exclude, snacks)
	end
	rayParams.FilterDescendantsInstances = exclude

	local step = 0.08
	local lastPos = origin
	for i = 1, 45 do
		local t = i * step
		local nextPos = origin + velocity * t + gravity * (0.5 * t * t)
		local result = workspace:Raycast(lastPos, nextPos - lastPos, rayParams)
		if result then
			-- Zylinder-Achse ist X -> X entlang der Oberflächen-Normale drehen
			local up = result.Normal
			ring.CFrame = CFrame.new(result.Position + up * 0.15, result.Position + up * 1.15)
				* CFrame.Angles(0, math.rad(90), 0)
			ring.Parent = workspace
			return
		end
		lastPos = nextPos
	end
	ring.Parent = nil -- kein Boden in Reichweite gefunden
end

local function updateTrajectory(charge: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		hideTrajectory()
		return
	end
	ensureDots()

	-- Wurfkraft exakt wie auf dem Server berechnen
	local def = SnackTypes.ByName[player:GetAttribute("HeldSnackName")]
	local level = player:GetAttribute("Wurfkraft") or 0
	local power = Config.ThrowBasePower
		* (0.35 + 0.65 * charge)
		* (1 + level * Config.ThrowPowerPerLevel)
		* (def and def.Slowdown or 1)
	if charge >= Config.SweetSpotStart then
		power *= Config.SweetSpotBonus
	end

	local velocity = root.CFrame.LookVector * power + Vector3.new(0, power * Config.ThrowUpFactor, 0)
	local origin = root.Position + Vector3.new(0, 3.5, 0)
	local gravity = Vector3.new(0, -workspace.Gravity, 0)

	for i, dot in trajectoryDots do
		local t = i * 0.08
		dot.Position = origin + velocity * t + gravity * (0.5 * t * t)
		dot.Parent = workspace
	end

	updateLandingRing(origin, velocity, gravity)
end

-- ══════════ YEET-Aufladung ══════════

local charging = false
local chargeStart = 0

local function cancelCharge()
	charging = false
	Ui.HideCharge()
	hideTrajectory()
end

local function beginCharge()
	if player:GetAttribute("HoldingSnack") == true then
		charging = true
		chargeStart = os.clock()
		Ui.ShowCharge()
	end
end

local function endCharge()
	if not charging then
		return
	end
	local fraction = math.clamp((os.clock() - chargeStart) / Config.ThrowChargeTime, 0, 1)
	cancelCharge()
	throwRemote:FireServer(fraction)
end

RunService.RenderStepped:Connect(function()
	if charging then
		local charge = math.clamp((os.clock() - chargeStart) / Config.ThrowChargeTime, 0, 1)
		Ui.SetCharge(charge)
		updateTrajectory(charge)
	end
end)

-- Hinweis + Abbruch, wenn der Snack wegfällt (Timer/Slap/geworfen)
player:GetAttributeChangedSignal("HoldingSnack"):Connect(function()
	local holding = player:GetAttribute("HoldingSnack") == true
	Ui.SetHoldHint(holding, player:GetAttribute("HeldSnackName"))
	if holding then
		showBeam()
	else
		clearBeam()
		cancelCharge()
	end
end)

-- ══════════ Eingaben ══════════

ContextActionService:BindAction("Yeet", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		beginCharge()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		endCharge()
	end
	return Enum.ContextActionResult.Pass -- Klicks nicht für Kamera etc. blockieren
end, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

ContextActionService:BindAction("Slap", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		SoundFx.Play("throw") -- sofortiges lokales Feedback (Whoosh)
		slapRemote:FireServer()
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)

-- ══════════ Tutorial für neue Spieler ══════════

local tutorialShown = false
local function runTutorial()
	if tutorialShown then
		return
	end
	tutorialShown = true
	local steps = {
		"👋 Willkommen bei YEET DEN SNACK!",
		"🏠 Such dir ZUERST eine FREIE BASIS und drück E am Tresor – die gehört dann dir!",
		"🚚 Gleich kommt der SCHOKO-TRUCK und verliert Snacks!",
		"✋ Drück E bei einem Snack zum Aufheben – aber nur 4 Sekunden halten!",
		"🖱️ Klick HALTEN & loslassen = YEET Richtung deiner Basis (folge dem gelben Strahl!)",
		"👋 Q = SLAP! Wer getroffen wird, lässt seinen Snack fallen...",
		"🏦 Snacks im Tresor = Cash pro Sekunde. Aber Achtung: die Plätze sind BEGRENZT!",
	}
	for i, text in steps do
		task.delay((i - 1) * 6, Ui.Toast, text)
	end
end

if player:GetAttribute("IsNewPlayer") then
	runTutorial()
else
	player:GetAttributeChangedSignal("IsNewPlayer"):Connect(function()
		if player:GetAttribute("IsNewPlayer") then
			runTutorial()
		end
	end)
end

-- Touch-Buttons beschriften/positionieren (nur auf Mobile sichtbar)
pcall(function()
	ContextActionService:SetTitle("Yeet", "YEET!")
	ContextActionService:SetPosition("Yeet", UDim2.new(1, -90, 0, -140))
	ContextActionService:SetTitle("Slap", "SLAP!")
	ContextActionService:SetPosition("Slap", UDim2.new(1, -160, 0, -70))
end)

print("🍫 [YEET DEN SNACK] Client bereit!")
