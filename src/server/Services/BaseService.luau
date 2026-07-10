--[[
	BaseService.luau
	Spieler-Basen: Beanspruchen, Tresor (Vault), Einkommens-Schleife
	und die Tresor-Knack-Mechanik (Klauen bei anderen Spielern).

	Basen werden NICHT automatisch zugewiesen: Neue Spieler laufen zu einer
	freien Basis und beanspruchen sie per ProximityPrompt am Tresor.

	Der Tresor hat begrenzte Plätze (Config.VaultLimit, steigt mit Rebirths
	und Basis-Ausbau). Ist er voll, wird nichts mehr eingelagert – der Besitzer
	kann am eigenen Tresor per [R] den billigsten Snack rauswerfen.

	Tycoon-Ausbau: Am grünen Bau-Pad neben dem Tresor kauft der Besitzer
	Ausbaustufen (Config.BaseLevels) – mehr Tresor-Plätze, Einkommens-Bonus
	und sichtbare Deko (Zaun, Fahnen, Gold-Tresor, Imperiums-Leuchtsäule).
	Beim Rebirth fällt die Basis zurück auf Level 1.

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
local MeshVisuals = require(ReplicatedStorage.Shared.MeshVisuals)

local BaseService = {}

local DataService, PlayerService, SnackService -- in Init verdrahtet

local bases = {} -- Liste aller Basis-Records
local zoneToBase: { [BasePart]: any } = {}
local playerToBase: { [Player]: any } = {}

local announceRemote: RemoteEvent
local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent

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

-- Gesamteinkommen/s aus dem Tresor: Snacks × Rebirth-Multiplikator × Ausbau-Bonus
local function getTotalIncome(player: Player): number
	local profile = DataService.Get(player)
	local bonus = Config.BaseLevelDef(profile and profile.BaseLevel or 1).IncomeBonus
	return getVaultIncome(player) * DataService.GetMultiplier(player) * (1 + bonus)
end

-- Kurzer Konfetti-Burst (Beanspruchen, Ausbau, Tresor-Explosion)
local function confettiBurst(part: BasePart, color: Color3, amount: number)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, part.Size.Y / 2 + 1, 0)
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Speed = NumberRange.new(15, 32)
	emitter.Lifetime = NumberRange.new(0.6, 1.3)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Size = NumberSequence.new(0.7)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(amount)
	task.delay(2, function()
		attachment:Destroy()
	end)
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
		local level = profile and profile.BaseLevel or 1
		local levelDef = Config.BaseLevelDef(level)
		local count = profile and #profile.Vault or 0
		local limit = Config.VaultLimit(profile and profile.Rebirths or 0, level)
		local income = math.floor(getTotalIncome(owner))
		base.NameLabel.Text = ("%s  %s"):format(levelDef.Label, owner.Name)
		base.InfoLabel.Text = ("🍫 %d/%d Snacks  |  %d💰/s"):format(count, limit, income)

		-- Bau-Pad-Anzeige: nächste Ausbaustufe oder MAX
		local nextDef = Config.BaseLevels[level + 1]
		if nextDef then
			base.BuildLabel.Text = ("⬆️ %s – %d💰\n+%d Plätze, +%d%% Einkommen"):format(
				nextDef.Label,
				nextDef.Cost,
				nextDef.BonusSlots - levelDef.BonusSlots,
				(nextDef.IncomeBonus - levelDef.IncomeBonus) * 100
			)
		else
			base.BuildLabel.Text = "👑 MAX AUSGEBAUT!"
		end
	else
		base.NameLabel.Text = "FREIE BASIS"
		base.InfoLabel.Text = "Hinlaufen & [E] drücken!"
		base.BuildLabel.Text = ""
	end
end

-- ══════════ Tycoon-Buildout (sichtbare Deko pro Ausbaustufe) ══════════

local function updateBuildout(base)
	base.DecoFolder:ClearAllChildren()

	local owner = base.Owner
	local profile = owner and DataService.Get(owner)
	local level = profile and profile.BaseLevel or 1

	-- Tresor-Optik: ab Level 4 wird er GOLDEN
	if owner and level >= 4 then
		base.Vault.Color = Color3.fromRGB(255, 210, 60)
		base.Vault.Material = Enum.Material.Metal
	else
		base.Vault.Color = Color3.fromRGB(80, 80, 90)
		base.Vault.Material = Enum.Material.DiamondPlate
	end

	if not owner or level < 2 then
		return
	end
	local color = BASE_COLORS[base.Index] or FREE_COLOR

	local function deco(props: { [string]: any }): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		for key, value in props do
			(part :: any)[key] = value
		end
		part.Parent = base.DecoFolder
		return part
	end

	-- Level 2: Zaun-Pfosten an drei Seiten (vorne bleibt offen für YEETs)
	local postPositions = {}
	for _, x in { -20, -10, 0, 10, 20 } do
		table.insert(postPositions, Vector3.new(x, 0, 20)) -- hinten
	end
	for _, z in { -12, -4, 4, 12 } do
		table.insert(postPositions, Vector3.new(-20, 0, z)) -- links
		table.insert(postPositions, Vector3.new(20, 0, z)) -- rechts
	end
	for _, pos in postPositions do
		deco({
			Size = Vector3.new(1, 4.5, 1),
			CFrame = base.Slot * CFrame.new(pos.X, 3.25, pos.Z),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		})
	end

	-- Level 3: Neon-Fahnenmasten an den vorderen Ecken
	if level >= 3 then
		for _, x in { -20, 20 } do
			deco({
				Size = Vector3.new(0.6, 12, 0.6),
				CFrame = base.Slot * CFrame.new(x, 7, -20),
				Color = Color3.fromRGB(200, 200, 210),
				Material = Enum.Material.Metal,
			})
			deco({
				Size = Vector3.new(4, 2.5, 0.3),
				CFrame = base.Slot * CFrame.new(x + (x < 0 and 2.2 or -2.2), 11.5, -20),
				Color = color,
				Material = Enum.Material.Neon,
			})
		end
	end

	-- Level 4: "Roter Teppich" (Neon-Landebahn) von vorne bis zum Gold-Tresor
	if level >= 4 then
		deco({
			Size = Vector3.new(5, 0.12, 32),
			CFrame = base.Slot * CFrame.new(0, 1.08, -3),
			Color = Color3.fromRGB(255, 210, 60),
			Material = Enum.Material.Neon,
		})
	end

	-- Level 5: Imperiums-Leuchtsäule + Sparkles überm Tresor (sieht JEDER auf der Map)
	if level >= 5 then
		local pillar = deco({
			Size = Vector3.new(2.5, 60, 2.5),
			CFrame = base.Slot * CFrame.new(0, 38, 14),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
		})
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 210, 60)
		sparkles.Parent = pillar
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
	-- ══ MESH-EINBAU: echte Tresor-MeshId in src/shared/Config.luau eintragen ══
	-- (Config.Meshes.Vault, oben in der Datei). Rein kosmetisch: Name, Größe,
	-- Position und die komplette Tresor-Logik (Prompts, Zone, Knacken) bleiben
	-- unverändert – nur die Optik des 7x7x7-Blocks wird ersetzt.
	MeshVisuals.Apply(vault, Config.Meshes.Vault)
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

	-- Beanspruchen-Prompt: freie Basis per Hinlaufen + [E] übernehmen
	local claimPrompt = Instance.new("ProximityPrompt")
	claimPrompt.ActionText = "Basis beanspruchen!"
	claimPrompt.ObjectText = "Freie Basis"
	claimPrompt.HoldDuration = 0.3
	claimPrompt.MaxActivationDistance = 14
	claimPrompt.RequiresLineOfSight = false
	claimPrompt.Enabled = true
	claimPrompt.Parent = vault

	-- Rauswerfen-Prompt: nur für den Besitzer (Platz schaffen, wenn der Tresor voll ist)
	local dropPrompt = Instance.new("ProximityPrompt")
	dropPrompt.ActionText = "Snack rauswerfen (Besitzer)"
	dropPrompt.ObjectText = "Tresor"
	dropPrompt.KeyboardKeyCode = Enum.KeyCode.R
	dropPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY -- ButtonX ist schon der Slap!
	dropPrompt.HoldDuration = 0
	dropPrompt.MaxActivationDistance = 10
	dropPrompt.RequiresLineOfSight = false
	dropPrompt.Enabled = false
	dropPrompt.Parent = vault

	-- Grünes Bau-Pad neben dem Tresor: hier kauft der Besitzer den Tycoon-Ausbau
	local buildPad = Instance.new("Part")
	buildPad.Name = "BuildPad"
	buildPad.Anchored = true
	buildPad.Shape = Enum.PartType.Cylinder
	buildPad.Size = Vector3.new(0.5, 7, 7)
	buildPad.CFrame = slot * CFrame.new(11, 1.25, 14) * CFrame.Angles(0, 0, math.rad(90))
	buildPad.Color = Color3.fromRGB(80, 210, 120)
	buildPad.Material = Enum.Material.Neon
	buildPad.Parent = folder

	local buildBillboard = Instance.new("BillboardGui")
	buildBillboard.Size = UDim2.fromOffset(230, 54)
	buildBillboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	buildBillboard.MaxDistance = 90
	local buildLabel = Instance.new("TextLabel")
	buildLabel.Size = UDim2.fromScale(1, 1)
	buildLabel.BackgroundTransparency = 1
	buildLabel.Text = ""
	buildLabel.TextScaled = true
	buildLabel.Font = Enum.Font.FredokaOne
	buildLabel.TextColor3 = Color3.fromRGB(160, 255, 190)
	buildLabel.TextStrokeTransparency = 0.2
	buildLabel.Parent = buildBillboard
	buildBillboard.Parent = buildPad

	local buildPrompt = Instance.new("ProximityPrompt")
	buildPrompt.ActionText = "Basis ausbauen!"
	buildPrompt.ObjectText = "Ausbau"
	buildPrompt.HoldDuration = 0.3
	buildPrompt.MaxActivationDistance = 9
	buildPrompt.RequiresLineOfSight = false
	buildPrompt.Enabled = false
	buildPrompt.Parent = buildPad

	-- Ordner für die Mini-Snack-Anzeige (der sichtbare Hort)
	local hoardFolder = Instance.new("Folder")
	hoardFolder.Name = "Hoard"
	hoardFolder.Parent = folder

	-- Ordner für die Tycoon-Ausbau-Deko (Zaun, Fahnen, ...)
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "Deco"
	decoFolder.Parent = folder

	folder.Parent = workspace:FindFirstChild("Map") or workspace

	local base = {
		Index = index,
		Slot = slot,
		Owner = nil :: Player?,
		Floor = floor,
		Vault = vault,
		Zone = zone,
		Prompt = prompt,
		ClaimPrompt = claimPrompt,
		DropPrompt = dropPrompt,
		BuildPrompt = buildPrompt,
		BuildLabel = buildLabel,
		NameLabel = nameLabel,
		InfoLabel = infoLabel,
		HoardFolder = hoardFolder,
		DecoFolder = decoFolder,
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

	claimPrompt.Triggered:Connect(function(player)
		BaseService.TryClaim(player, base)
	end)

	dropPrompt.Triggered:Connect(function(player)
		BaseService.TryDropSnack(player, base)
	end)

	buildPrompt.Triggered:Connect(function(player)
		BaseService.TryUpgradeBase(player, base)
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
		-- Snack ploppt vor dem Tresor raus und fliegt Richtung Straße –
		-- der Dieb muss ihn erst heimYEETen! Kurze Bank-Immunität, sonst
		-- landet er in der VaultZone und wird sofort wieder eingelagert.
		local spawnCFrame = base.Vault.CFrame * CFrame.new(0, 2, -8)
		local outward = base.Slot.LookVector -- lokales -Z = Richtung Straße
		SnackService.SpawnSnack(def, spawnCFrame.Position, outward * 55 + Vector3.new(0, 30, 0), 3)
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

-- Snack einlagern. Gibt false zurück, wenn der Tresor voll ist
-- (Limit = Config.VaultLimit, steigt mit Rebirths) – Aufrufer entscheidet,
-- was dann mit dem Snack passiert (liegen lassen, Geschenk verschieben, ...).
function BaseService.AddToVault(owner: Player, snackName: string): boolean
	local profile = DataService.Get(owner)
	if not profile then
		return false
	end
	if #profile.Vault >= Config.VaultLimit(profile.Rebirths, profile.BaseLevel) then
		return false
	end
	table.insert(profile.Vault, snackName)
	local base = playerToBase[owner]
	if base then
		updateDisplay(base)
	end
	return true
end

-- Billigsten Snack aus dem EIGENEN Tresor werfen (Platz schaffen!).
-- Der Snack landet als loses Part vor dem Tresor – wer ihn will, muss ihn neu einlagern.
function BaseService.TryDropSnack(player: Player, base)
	if player ~= base.Owner then
		notifyRemote:FireClient(player, "😅 Rauswerfen darf nur der Besitzer – knack den Tresor doch einfach!")
		return
	end
	local profile = DataService.Get(player)
	if not profile or #profile.Vault == 0 then
		notifyRemote:FireClient(player, "🕸️ Dein Tresor ist leer – nichts zum Rauswerfen.")
		return
	end

	-- Den WERTLOSESTEN Snack opfern (schützt die seltenen Schätze vor Fett-Fingern)
	local cheapestIndex, cheapestIncome = 1, math.huge
	for i, name in profile.Vault do
		local def = SnackTypes.ByName[name]
		local income = def and def.Income or 0
		if income < cheapestIncome then
			cheapestIndex, cheapestIncome = i, income
		end
	end
	local snackName = table.remove(profile.Vault, cheapestIndex)
	updateDisplay(base)

	local def = SnackTypes.ByName[snackName]
	if def then
		-- Richtung Straße yeeten + Bank-Immunität, sonst lagert er sich sofort wieder selbst ein
		local spawnCFrame = base.Vault.CFrame * CFrame.new(0, 2, -8)
		local outward = base.Slot.LookVector
		SnackService.SpawnSnack(
			def,
			spawnCFrame.Position,
			outward * 55 + Vector3.new(math.random(-8, 8), 28, 0),
			3
		)
	end
	notifyRemote:FireClient(
		player,
		("🗑️ '%s' rausgeworfen! (%d/%d Plätze belegt)"):format(
			snackName,
			#profile.Vault,
			Config.VaultLimit(profile.Rebirths, profile.BaseLevel)
		)
	)
end

-- Beim Rebirth: ALLE Tresor-Snacks freilassen! Sie fliegen aus der Basis raus
-- Richtung Plaza (mit Bank-Immunität, sonst saugt die eigene VaultZone sie
-- sofort wieder ein) – wer sie will (auch der Ex-Besitzer!), muss sie neu erobern.
-- Gibt die Anzahl der befreiten Snacks zurück.
function BaseService.ReleaseVaultSnacks(player: Player): number
	local profile = DataService.Get(player)
	if not profile or #profile.Vault == 0 then
		return 0
	end
	local released = table.clone(profile.Vault)
	table.clear(profile.Vault)

	local base = playerToBase[player]
	if base then
		updateDisplay(base)
		-- Explosions-Effekt: der Tresor "platzt" sichtbar auf
		confettiBurst(base.Vault, Color3.fromRGB(255, 220, 80), 80)
		sfxRemote:FireAllClients("explosion", base.Vault.Position)
		local outward = base.Slot.LookVector -- lokales -Z = Richtung Straße
		for i, snackName in released do
			local def = SnackTypes.ByName[snackName]
			if def then
				-- Gestaffelt rauswerfen – sieht aus wie eine Tresor-Explosion!
				task.delay((i - 1) * 0.08, function()
					local spawnCFrame = base.Vault.CFrame * CFrame.new(math.random(-3, 3), 2, -6)
					SnackService.SpawnSnack(
						def,
						spawnCFrame.Position,
						outward * math.random(40, 70) + Vector3.new(math.random(-18, 18), math.random(25, 45), math.random(-18, 18)),
						5
					)
				end)
			end
		end
	else
		-- Kein eigenes Zuhause (sollte selten sein): Snacks um den Spieler verteilen
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local origin = root and root.Position or Vector3.new(0, 10, 0)
		for i, snackName in released do
			local def = SnackTypes.ByName[snackName]
			if def then
				task.delay((i - 1) * 0.08, function()
					SnackService.SpawnSnack(
						def,
						origin + Vector3.new(0, 4, 0),
						Vector3.new(math.random(-40, 40), math.random(25, 45), math.random(-40, 40)),
						5
					)
				end)
			end
		end
	end
	return #released
end

-- Tycoon-Ausbau kaufen (am Bau-Pad der eigenen Basis)
function BaseService.TryUpgradeBase(player: Player, base)
	if player ~= base.Owner then
		notifyRemote:FireClient(player, "😅 Das ist nicht deine Basis – bau deine eigene aus!")
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local level = profile.BaseLevel or 1
	local nextDef = Config.BaseLevels[level + 1]
	if not nextDef then
		notifyRemote:FireClient(player, "👑 Deine Basis ist schon MAXIMAL ausgebaut!")
		return
	end
	if not PlayerService.TrySpend(player, nextDef.Cost) then
		notifyRemote:FireClient(player, ("Zu wenig Cash! Der Ausbau kostet %d💰."):format(nextDef.Cost))
		return
	end

	profile.BaseLevel = level + 1
	updateBuildout(base)
	updateDisplay(base)
	PlayerService.Sync(player) -- VaultLimit-Attribut aktualisieren
	confettiBurst(base.Vault, BASE_COLORS[base.Index] or FREE_COLOR, 60)
	sfxRemote:FireAllClients("ding", base.Vault.Position)
	notifyRemote:FireClient(
		player,
		("⬆️ Ausbau fertig: %s! (+%d Tresor-Plätze, +%d%% Einkommen)"):format(
			nextDef.Label,
			nextDef.BonusSlots - Config.BaseLevelDef(level).BonusSlots,
			(nextDef.IncomeBonus - Config.BaseLevelDef(level).IncomeBonus) * 100
		)
	)
	if profile.BaseLevel >= #Config.BaseLevels then
		announceRemote:FireAllClients(
			("🏰 %s hat das SNACK-IMPERIUM errichtet! Verneigt euch!!"):format(player.Name),
			"Mythic"
		)
	end
end

-- Buildout + Anzeige neu aufbauen (z.B. nach Rebirth-Reset des Basis-Levels)
function BaseService.RefreshBuildout(player: Player)
	local base = playerToBase[player]
	if base then
		updateBuildout(base)
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

-- ══════════ Beanspruchen ══════════

-- Freie Basis übernehmen (per ProximityPrompt am Tresor)
function BaseService.TryClaim(player: Player, base)
	if base.Owner then
		notifyRemote:FireClient(player, "😅 Diese Basis gehört schon jemandem!")
		return
	end
	if playerToBase[player] then
		notifyRemote:FireClient(player, "😅 Du hast schon eine Basis!")
		return
	end

	base.Owner = player
	playerToBase[player] = base
	local color = BASE_COLORS[base.Index] or FREE_COLOR
	base.Floor.Color = color
	base.Zone.Color = color
	base.Prompt.Enabled = true
	base.DropPrompt.Enabled = true
	base.BuildPrompt.Enabled = true
	base.ClaimPrompt.Enabled = false
	-- Für den Heimweg-Pfeil auf dem Client
	player:SetAttribute("VaultPos", base.Vault.Position)
	notifyRemote:FireClient(player, "🏠 Das ist jetzt DEINE Basis! YEETe Snacks in die Zone!")
	confettiBurst(base.Vault, color, 40)
	sfxRemote:FireAllClients("ding", base.Vault.Position)
	-- Anzeige/Ausbau erst aktualisieren, wenn die Daten geladen sind
	task.spawn(function()
		DataService.WaitFor(player)
		if base.Owner == player then
			updateDisplay(base)
			updateBuildout(base)
			BaseService.RefreshLock(player)
		end
	end)
end

local function releaseBase(player: Player)
	local base = playerToBase[player]
	if base then
		base.Owner = nil
		base.Floor.Color = FREE_COLOR
		base.Zone.Color = FREE_COLOR
		base.Prompt.Enabled = false
		base.DropPrompt.Enabled = false
		base.BuildPrompt.Enabled = false
		base.ClaimPrompt.Enabled = true
		playerToBase[player] = nil
		updateDisplay(base)
		updateBuildout(base) -- Deko + Gold-Tresor zurücksetzen
	end
end

-- ══════════ Init ══════════

function BaseService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	SnackService = services.SnackService

	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	for index, slot in services.MapSlots do
		table.insert(bases, buildBase(index, slot))
	end

	-- Keine Auto-Zuweisung mehr: Spieler suchen sich ihre Basis selbst aus.
	-- Kleiner Anstupser für alle, die nach ein paar Sekunden noch keine haben.
	local function greet(player: Player)
		task.delay(4, function()
			if player.Parent and not playerToBase[player] then
				notifyRemote:FireClient(player, "🏠 Such dir eine FREIE BASIS aus und drück [E] am Tresor!")
			end
		end)
	end
	Players.PlayerAdded:Connect(greet)
	for _, player in Players:GetPlayers() do
		greet(player)
	end
	Players.PlayerRemoving:Connect(releaseBase)

	-- Einkommens-Schleife: Tresor-Snacks generieren Cash
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTick)
			for player, base in playerToBase do
				local income = getTotalIncome(player)
				if income > 0 then
					PlayerService.AddCash(player, income * Config.IncomeTick)
				end
			end
		end
	end)
end

return BaseService
