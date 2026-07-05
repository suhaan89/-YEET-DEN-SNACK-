--[[
	BaseService.luau
	Spieler-Basen: Zuweisung, Tresor (Vault), Einkommens-Schleife
	und die Tresor-Knack-Mechanik (Klauen bei anderen Spielern).

	Jede Basis:
	- Floor      = farbige Bodenplatte
	- Vault      = Tresor-Block mit BillboardGui (Name, Snacks, Einkommen)
	- VaultZone  = unsichtbare Zone: landet hier ein loser Snack, wird er
	               dem Basis-Besitzer gutgeschrieben (auch bei Fehlwürfen!)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local BaseService = {}

local DataService, PlayerService, SnackService -- in Init verdrahtet

local bases = {} -- Liste aller Basis-Records
local zoneToBase: { [BasePart]: any } = {}
local playerToBase: { [Player]: any } = {}

local announceRemote: RemoteEvent
local notifyRemote: RemoteEvent

local BASE_COLORS = {
	Color3.fromRGB(255, 130, 130),
	Color3.fromRGB(130, 200, 255),
	Color3.fromRGB(150, 255, 150),
	Color3.fromRGB(255, 220, 120),
	Color3.fromRGB(220, 150, 255),
	Color3.fromRGB(130, 255, 230),
	Color3.fromRGB(255, 170, 90),
	Color3.fromRGB(200, 200, 255),
}
local FREE_COLOR = Color3.fromRGB(120, 120, 120)

local function getVaultIncome(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local income = 0
	for _, snackName in profile.Vault do
		local def = SnackTypes.ByName[snackName]
		if def then
			income += def.Income
		end
	end
	return income
end

-- Eingelagerte Snacks als Mini-Modelle auf der Basis anzeigen (max. 24):
-- Spieler sehen ihren Hort wachsen, Diebe sehen, wo es sich lohnt.
local MAX_HOARD_SHOWN = 24

local function updateHoard(base)
	base.HoardFolder:ClearAllChildren()
	local owner = base.Owner
	if not owner then
		return
	end
	local profile = DataService.Get(owner)
	if not profile then
		return
	end
	local count = math.min(#profile.Vault, MAX_HOARD_SHOWN)
	for i = 1, count do
		local def = SnackTypes.ByName[profile.Vault[i]]
		if not def then
			continue
		end
		local col = (i - 1) % 6
		local row = (i - 1) // 6
		local mini = Instance.new("Part")
		mini.Size = def.Size * 0.6
		mini.Color = def.Color
		mini.Material = if def.Announce then Enum.Material.Neon else Enum.Material.SmoothPlastic
		mini.Anchored = true
		mini.CanCollide = false
		mini.CanQuery = false
		-- Grid links neben dem Tresor (lokale Koordinaten der Basis)
		mini.CFrame = base.Slot * CFrame.new(-19 + col * 3, 1 + mini.Size.Y / 2, 10 + row * 3)
		mini.Parent = base.HoardFolder
	end
end

local function updateDisplay(base)
	updateHoard(base)
	local owner = base.Owner
	if owner then
		local profile = DataService.Get(owner)
		local count = profile and #profile.Vault or 0
		local income = math.floor(getVaultIncome(owner) * DataService.GetMultiplier(owner))
		base.NameLabel.Text = "🏠 " .. owner.Name
		base.InfoLabel.Text = ("🍫 %d Snacks  |  %d💰/s"):format(count, income)
	else
		base.NameLabel.Text = "FREIE BASIS"
		base.InfoLabel.Text = "—"
	end
end

-- ══════════ Bau der Basen ══════════

local function buildBase(index: number, slot: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Base_" .. index

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(44, 1, 44)
	floor.CFrame = slot * CFrame.new(0, 0.5, 0)
	floor.Color = FREE_COLOR
	floor.Material = Enum.Material.SmoothPlastic
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.Parent = folder

	-- Tresor hinten auf der Basis (lokales +Z = von der Straße weg)
	local vault = Instance.new("Part")
	vault.Name = "Vault"
	vault.Anchored = true
	vault.Size = Vector3.new(7, 7, 7)
	vault.CFrame = slot * CFrame.new(0, 4.5, 14)
	vault.Color = Color3.fromRGB(80, 80, 90)
	vault.Material = Enum.Material.DiamondPlate
	vault.Parent = folder

	-- Unsichtbare Fang-Zone über der ganzen Basis
	local zone = Instance.new("Part")
	zone.Name = "VaultZone"
	zone.Anchored = true
	zone.Size = Vector3.new(42, 12, 42)
	zone.CFrame = slot * CFrame.new(0, 7, 0)
	zone.Transparency = 0.94
	zone.Color = FREE_COLOR
	zone.CanCollide = false
	zone.CanQuery = false
	zone.Parent = folder

	-- Anzeige über dem Tresor
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 70)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.MaxDistance = 220
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.55)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Parent = billboard
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Position = UDim2.fromScale(0, 0.55)
	infoLabel.Size = UDim2.fromScale(1, 0.45)
	infoLabel.BackgroundTransparency = 1
	infoLabel.TextScaled = true
	infoLabel.Font = Enum.Font.FredokaOne
	infoLabel.TextColor3 = Color3.fromRGB(255, 230, 150)
	infoLabel.TextStrokeTransparency = 0.2
	infoLabel.Parent = billboard
	billboard.Parent = vault

	-- Knack-Prompt für Diebe
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Tresor knacken!"
	prompt.ObjectText = "Tresor"
	prompt.HoldDuration = Config.VaultCrackBaseTime
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = vault

	-- Ordner für die Mini-Snack-Anzeige (der sichtbare Hort)
	local hoardFolder = Instance.new("Folder")
	hoardFolder.Name = "Hoard"
	hoardFolder.Parent = folder

	folder.Parent = workspace:FindFirstChild("Map") or workspace

	local base = {
		Index = index,
		Slot = slot,
		Owner = nil :: Player?,
		Floor = floor,
		Vault = vault,
		Zone = zone,
		Prompt = prompt,
		NameLabel = nameLabel,
		InfoLabel = infoLabel,
		HoardFolder = hoardFolder,
		LastCrack = 0,
	}
	zoneToBase[zone] = base

	-- Warnung an den Besitzer, sobald jemand zu knacken beginnt (Drama!)
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if base.Owner and player ~= base.Owner then
			notifyRemote:FireClient(base.Owner, ("🚨 %s knackt deinen TRESOR! SLAP IHN WEG!"):format(player.Name))
		end
	end)

	prompt.Triggered:Connect(function(player)
		BaseService.TryCrack(player, base)
	end)

	updateDisplay(base)
	return base
end

-- ══════════ Tresor knacken ══════════

function BaseService.TryCrack(thief: Player, base)
	local owner = base.Owner
	if not owner then
		return
	end
	if thief == owner then
		notifyRemote:FireClient(thief, "😅 Das ist dein eigener Tresor...")
		return
	end
	local profile = DataService.Get(owner)
	if not profile or #profile.Vault == 0 then
		notifyRemote:FireClient(thief, "🕸️ Dieser Tresor ist leer.")
		return
	end
	if os.clock() - base.LastCrack < Config.VaultCrackCooldown then
		local rest = math.ceil(Config.VaultCrackCooldown - (os.clock() - base.LastCrack))
		notifyRemote:FireClient(thief, ("🔒 Tresor ist noch gesichert! (%d Sek.)"):format(rest))
		return
	end

	-- Zufälligen Snack aus dem Tresor werfen
	local idx = math.random(1, #profile.Vault)
	local snackName = table.remove(profile.Vault, idx)
	local def = SnackTypes.ByName[snackName]
	base.LastCrack = os.clock()
	updateDisplay(base)

	if def then
		-- Snack ploppt vor dem Tresor raus – der Dieb muss ihn erst heimYEETen!
		local spawnCFrame = base.Vault.CFrame * CFrame.new(0, 2, -8)
		SnackService.SpawnSnack(def, spawnCFrame.Position, Vector3.new(0, 20, 0))
	end

	notifyRemote:FireClient(owner, ("😱 %s hat '%s' aus deinem Tresor geklaut!"):format(thief.Name, snackName))
	announceRemote:FireAllClients(
		("😈 %s hat '%s' aus %ss Tresor befreit! Noch liegt er rum..."):format(thief.Name, snackName, owner.Name),
		def and def.Rarity or nil
	)
end

-- ══════════ Öffentliche API ══════════

function BaseService.GetZoneOwner(zone: BasePart): Player?
	local base = zoneToBase[zone]
	return base and base.Owner
end

function BaseService.AddToVault(owner: Player, snackName: string)
	local profile = DataService.Get(owner)
	if not profile then
		return
	end
	table.insert(profile.Vault, snackName)
	local base = playerToBase[owner]
	if base then
		updateDisplay(base)
	end
end

-- Schloss-Upgrade anwenden: Diebe brauchen länger
function BaseService.RefreshLock(player: Player)
	local base = playerToBase[player]
	local profile = DataService.Get(player)
	if base and profile then
		base.Prompt.HoldDuration = Config.VaultCrackBaseTime
			+ profile.Upgrades.Schloss * Config.VaultCrackTimePerLock
	end
end

function BaseService.GetBaseOf(player: Player)
	return playerToBase[player]
end

-- Anzeige neu zeichnen (z.B. nach Rebirth, wenn sich der Multiplikator ändert)
function BaseService.RefreshDisplay(player: Player)
	local base = playerToBase[player]
	if base then
		updateDisplay(base)
	end
end

-- ══════════ Zuweisung ══════════

local function assign(player: Player)
	for _, base in bases do
		if not base.Owner then
			base.Owner = player
			playerToBase[player] = base
			local color = BASE_COLORS[base.Index] or FREE_COLOR
			base.Floor.Color = color
			base.Zone.Color = color
			base.Prompt.Enabled = true
			-- Für den Heimweg-Pfeil auf dem Client
			player:SetAttribute("VaultPos", base.Vault.Position)
			-- Anzeige erst aktualisieren, wenn die Daten geladen sind
			task.spawn(function()
				DataService.WaitFor(player)
				if base.Owner == player then
					updateDisplay(base)
					BaseService.RefreshLock(player)
				end
			end)
			return
		end
	end
	notifyRemote:FireClient(player, "⚠️ Alle Basen belegt! (Server voll)")
end

local function releaseBase(player: Player)
	local base = playerToBase[player]
	if base then
		base.Owner = nil
		base.Floor.Color = FREE_COLOR
		base.Zone.Color = FREE_COLOR
		base.Prompt.Enabled = false
		playerToBase[player] = nil
		updateDisplay(base)
	end
end

-- ══════════ Init ══════════

function BaseService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	SnackService = services.SnackService

	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	notifyRemote = Remotes.Get("Notify") :: RemoteEvent

	for index, slot in services.MapSlots do
		table.insert(bases, buildBase(index, slot))
	end

	Players.PlayerAdded:Connect(assign)
	for _, player in Players:GetPlayers() do
		if not playerToBase[player] then
			assign(player)
		end
	end
	Players.PlayerRemoving:Connect(releaseBase)

	-- Einkommens-Schleife: Tresor-Snacks generieren Cash
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTick)
			for player, base in playerToBase do
				local income = getVaultIncome(player) * DataService.GetMultiplier(player)
				if income > 0 then
					PlayerService.AddCash(player, income * Config.IncomeTick)
				end
			end
		end
	end)
end

return BaseService
