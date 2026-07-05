--[[
	StyleService.luau
	Style-Shop: rein kosmetische Lauf-Trails hinter dem Charakter.
	- Kauf/Ausrüsten server-validiert (Kosten aus Config.Trails)
	- Nur EIN Trail gleichzeitig aktiv (profile.EquippedTrail)
	- Trail wird bei Equip und nach jedem Respawn neu an den Charakter gehängt
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local StyleService = {}

local DataService, PlayerService -- in Init verdrahtet

local trailDefsById: { [string]: any } = {}
for _, def in Config.Trails do
	trailDefsById[def.Id] = def
end

local TRAIL_NAME = "StyleTrail"

-- Regenbogen-Farbverlauf für den Nyan-Modus
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 60)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 220, 80)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 130, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 80, 255)),
})

local function removeTrail(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local old = root:FindFirstChild(TRAIL_NAME)
		if old then
			old:Destroy()
		end
	end
end

-- Hängt den ausgerüsteten Trail an den (aktuellen) Charakter
local function applyTrail(player: Player)
	local profile = DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not profile or not character or not root then
		return
	end
	removeTrail(character :: Model)

	local def = trailDefsById[profile.EquippedTrail]
	if not def then
		return
	end

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 2, 0)
	att0.Parent = root
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, -2, 0)
	att1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = if def.Rainbow then RAINBOW else ColorSequence.new(def.Color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.8
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.Parent = root
end

-- ══════════ Remote-Handler ══════════

local function buyTrail(player: Player, trailId: any)
	if typeof(trailId) ~= "string" or not trailDefsById[trailId] then
		return { ok = false, msg = "Unbekannter Trail." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	if profile.Trails[trailId] then
		return { ok = false, msg = "Den Trail hast du schon!" }
	end
	local def = trailDefsById[trailId]
	if not PlayerService.TrySpend(player, def.Cost) then
		return { ok = false, msg = ("Zu wenig Cash! (%d💰 nötig)"):format(def.Cost) }
	end
	profile.Trails[trailId] = true
	return { ok = true, msg = ("%s gekauft! Zieh ihn gleich an!"):format(def.Name) }
end

local function equipTrail(player: Player, trailId: any)
	if typeof(trailId) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	if trailId == "" then
		profile.EquippedTrail = ""
		if player.Character then
			removeTrail(player.Character)
		end
		return { ok = true, msg = "Trail abgelegt – ganz unauffällig jetzt." }
	end
	local def = trailDefsById[trailId]
	if not def or not profile.Trails[trailId] then
		return { ok = false, msg = "Der Trail gehört dir (noch) nicht!" }
	end
	profile.EquippedTrail = trailId
	applyTrail(player)
	return { ok = true, msg = ("%s aktiviert – zieh eine Show ab!"):format(def.Name) }
end

-- ══════════ Init ══════════

function StyleService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService;

	(Remotes.Get("BuyTrail") :: RemoteFunction).OnServerInvoke = buyTrail;
	(Remotes.Get("EquipTrail") :: RemoteFunction).OnServerInvoke = equipTrail

	-- Nach jedem (Re-)Spawn den gespeicherten Trail wieder anhängen
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			task.spawn(function()
				DataService.WaitFor(player)
				task.wait(0.2) -- HumanoidRootPart kurz Zeit geben
				applyTrail(player)
			end)
		end)
		if player.Character then
			task.spawn(function()
				DataService.WaitFor(player)
				applyTrail(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return StyleService
