--[[
	Ragdoll.luau
	Comedy-Physik: Spieler per PlatformStand + Impuls durch die Gegend schleudern.

	WICHTIG: Der Client besitzt die Netzwerk-Physik seines eigenen Charakters.
	Deshalb setzt der Server die Velocity UND schickt sie zusätzlich per
	"Fling"-Remote an den betroffenen Client – der wendet sie lokal an.
	So fliegt es im Live-Spiel genauso schön wie im Studio-Test.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Ragdoll = {}

local activeFlings: { [Model]: boolean } = {}

-- Schleudert einen Charakter mit gegebener Velocity weg und lässt ihn danach aufstehen.
function Ragdoll.Fling(character: Model, velocity: Vector3, ragdollTime: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if activeFlings[character] then
		return -- fliegt schon, nicht stapeln
	end
	activeFlings[character] = true

	local spin = Vector3.new(math.random(-25, 25), math.random(-25, 25), math.random(-25, 25))

	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = spin

	-- Client anweisen, den Impuls lokal anzuwenden (er besitzt die Physik)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		(Remotes.Get("Fling") :: RemoteEvent):FireClient(player, velocity, spin)
	end

	task.delay(ragdollTime, function()
		activeFlings[character] = nil
		if character.Parent and humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

function Ragdoll.IsFlinging(character: Model): boolean
	return activeFlings[character] == true
end

-- Comic-Slap-"Animation": eine riesige Cartoon-Hand holt neben dem Slapper aus
-- und klatscht zum Ziel. Rein prozedural (Part + Tween) – braucht keine
-- hochgeladenen Animations-Assets und ist für ALLE Spieler sichtbar.
function Ragdoll.SlapEffect(slapper: Model, targetPosition: Vector3)
	local root = slapper:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local hand = Instance.new("Part")
	hand.Name = "ComicSlapHand"
	hand.Size = Vector3.new(4, 4, 0.8)
	hand.Color = Color3.fromRGB(255, 220, 170)
	hand.Material = Enum.Material.SmoothPlastic
	hand.Anchored = true
	hand.CanCollide = false
	hand.CanQuery = false
	hand.CanTouch = false

	-- ✋ auf Vorder- und Rückseite, damit die Hand aus jeder Richtung lustig aussieht
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(200, 200)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "✋"
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = hand
	end

	-- Ausholen: seitlich neben dem Slapper, leicht verdreht (Windup-Pose)
	hand.CFrame = root.CFrame * CFrame.new(-3.5, 2.5, 1) * CFrame.Angles(0, math.rad(-70), math.rad(15))
	hand.Parent = workspace

	-- Zuschlagen: mit Schmackes ans Ziel, Handfläche zeigt zum Slapper zurück
	local hitCFrame = CFrame.lookAt(targetPosition + Vector3.new(0, 2, 0), root.Position)
	local swing = TweenService:Create(
		hand,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = hitCFrame }
	)
	swing:Play()
	swing.Completed:Once(function()
		TweenService:Create(hand, TweenInfo.new(0.3), { Transparency = 1, Size = hand.Size * 1.6 }):Play()
	end)
	Debris:AddItem(hand, 0.6)
end

return Ragdoll
