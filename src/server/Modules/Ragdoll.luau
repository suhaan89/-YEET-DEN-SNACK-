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

return Ragdoll
