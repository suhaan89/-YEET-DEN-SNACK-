--[[
	PetService.luau
	Pets aus dem Pet-Shop: schwebende Begleiter, die passiv Cash generieren.
	- Kauf/Ausrüsten server-validiert (Kosten aus Config.Pets)
	- Nur EIN Pet gleichzeitig ausgerüstet (profile.EquippedPet)
	- Pet folgt dem Spieler als angeankertes Neon-Teil (Heartbeat-Lerp + Bobbing)
	- Einkommen skaliert mit dem Rebirth-Multiplikator

	Beherbergt außerdem das "GetCollections"-Remote (Pets + Trails in einem
	Aufruf), damit Pet- und Style-Shop-UI mit einem Roundtrip auskommen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PetService = {}

local DataService, PlayerService -- in Init verdrahtet

local petDefsById: { [string]: any } = {}
for _, def in Config.Pets do
	petDefsById[def.Id] = def
end

local petFolder: Folder
local petParts: { [Player]: BasePart } = {}

local function destroyPet(player: Player)
	local part = petParts[player]
	if part then
		part:Destroy()
		petParts[player] = nil
	end
end

local function spawnPet(player: Player, def)
	destroyPet(player)

	local part = Instance.new("Part")
	part.Name = "Pet_" .. def.Id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.Color = def.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(130, 24)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.Name
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = def.Color
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = part

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	part.CFrame = if root then root.CFrame * CFrame.new(3, 2.5, 3) else CFrame.new(0, 5, 50)
	part.Parent = petFolder
	petParts[player] = part
end

-- ══════════ Remote-Handler ══════════

local function buyPet(player: Player, petId: any)
	if typeof(petId) ~= "string" or not petDefsById[petId] then
		return { ok = false, msg = "Unbekanntes Pet." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	if profile.Pets[petId] then
		return { ok = false, msg = "Das Pet gehört dir schon!" }
	end
	local def = petDefsById[petId]
	if not PlayerService.TrySpend(player, def.Cost) then
		return { ok = false, msg = ("Zu wenig Cash! (%d💰 nötig)"):format(def.Cost) }
	end
	profile.Pets[petId] = true
	return { ok = true, msg = ("%s gehört jetzt dir! Gleich ausrüsten?"):format(def.Name) }
end

local function equipPet(player: Player, petId: any)
	if typeof(petId) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	if petId == "" then
		profile.EquippedPet = ""
		destroyPet(player)
		return { ok = true, msg = "Pet in die Tasche gesteckt." }
	end
	local def = petDefsById[petId]
	if not def or not profile.Pets[petId] then
		return { ok = false, msg = "Das Pet gehört dir (noch) nicht!" }
	end
	profile.EquippedPet = petId
	spawnPet(player, def)
	return { ok = true, msg = ("%s trottet jetzt hinter dir her!"):format(def.Name) }
end

-- Pets + Trails in einem Rutsch (fürs Shop-UI)
local function getCollections(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	return {
		Pets = profile.Pets,
		EquippedPet = profile.EquippedPet,
		Trails = profile.Trails,
		EquippedTrail = profile.EquippedTrail,
	}
end

-- ══════════ Init ══════════

function PetService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService;

	(Remotes.Get("BuyPet") :: RemoteFunction).OnServerInvoke = buyPet;
	(Remotes.Get("EquipPet") :: RemoteFunction).OnServerInvoke = equipPet;
	(Remotes.Get("GetCollections") :: RemoteFunction).OnServerInvoke = getCollections

	petFolder = Instance.new("Folder")
	petFolder.Name = "Pets"
	petFolder.Parent = workspace

	-- Beim Join: gespeichertes Pet wieder herbeirufen
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitFor(player)
			if profile and profile.EquippedPet ~= "" and petDefsById[profile.EquippedPet] then
				spawnPet(player, petDefsById[profile.EquippedPet])
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(destroyPet)

	-- Folge-Schleife: Pet schwebt schräg hinter dem Spieler + fröhliches Bobbing
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, part in petParts do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local bob = math.sin(now * 4 + part.Position.X) * 0.5
				local target = root.CFrame * CFrame.new(3, 2.5 + bob, 3)
				part.CFrame = part.CFrame:Lerp(target, math.min(dt * 6, 1))
			end
		end
	end)

	-- Einkommens-Schleife: ausgerüstetes Pet generiert Cash (mit Rebirth-Multiplikator)
	task.spawn(function()
		while true do
			task.wait(Config.PetIncomeTick)
			for player, _ in petParts do
				local profile = DataService.Get(player)
				local def = profile and petDefsById[profile.EquippedPet]
				if def then
					PlayerService.AddCash(player, def.Income * DataService.GetMultiplier(player) * Config.PetIncomeTick)
				end
			end
		end
	end)
end

return PetService
