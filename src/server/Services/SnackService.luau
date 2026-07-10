--[[
	SnackService.luau
	Das Herzstück: Snacks spawnen, aufheben, YEETen, fallen lassen,
	in Tresore einlagern – und die "DU BIST JETZT DER SNACK"-Verwandlung.

	Snack-Lebenszyklus:
	  Loose  -> liegt rum, jeder kann ihn per ProximityPrompt aufheben
	  Held   -> schwebt über dem Kopf des Trägers (max. Config.HoldDuration Sek.!)
	  Banked -> im Tresor gelandet, Part wird zerstört, Name wandert ins Profil
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MeshVisuals = require(ReplicatedStorage.Shared.MeshVisuals)

local SnackService = {}

local BaseService, PlayerService, DataService, SeasonPassService, AchievementService -- in Init verdrahtet

local snackFolder: Folder
local entries: { [BasePart]: any } = {} -- alle aktiven Snack-Parts
local held: { [Player]: any } = {} -- wer hält gerade was

local announceRemote: RemoteEvent
local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent

-- Combo-Tracking: schnelles Einlagern hintereinander gibt Bonus-Cash
local combos: { [Player]: { Count: number, Last: number } } = {}

-- "Tresor voll!"-Meldungen drosseln (Touched feuert sonst im Sekundentakt)
local vaultFullNotify: { [Player]: number } = {}

local function announce(text: string, rarity: string?)
	announceRemote:FireAllClients(text, rarity)
end

local function notify(player: Player, text: string)
	notifyRemote:FireClient(player, text)
end

local function countLoose(): number
	local n = 0
	for _, entry in entries do
		if entry.State == "Loose" then
			n += 1
		end
	end
	return n
end

local function destroyOldestLoose()
	local oldest, oldestTime = nil, math.huge
	for _, entry in entries do
		if entry.State == "Loose" and entry.SpawnedAt < oldestTime then
			oldest, oldestTime = entry, entry.SpawnedAt
		end
	end
	if oldest then
		entries[oldest.Part] = nil
		oldest.Part:Destroy()
	end
end

-- ══════════ Trage-Pose (prozedural, ohne Animations-Assets) ══════════
-- Beide Arme nach oben strecken, solange der Snack überm Kopf schwebt.
-- Funktioniert für R6 (Schulter-Motoren im Torso) und R15 (in den UpperArms).

local function findShoulders(character: Model): { Motor6D }
	local motors: { Motor6D } = {}
	local torso = character:FindFirstChild("Torso")
	if torso then -- R6
		for _, name in { "Left Shoulder", "Right Shoulder" } do
			local motor = torso:FindFirstChild(name)
			if motor and motor:IsA("Motor6D") then
				table.insert(motors, motor)
			end
		end
	else -- R15
		for _, pair in { { "LeftUpperArm", "LeftShoulder" }, { "RightUpperArm", "RightShoulder" } } do
			local arm = character:FindFirstChild(pair[1])
			local motor = arm and arm:FindFirstChild(pair[2])
			if motor and motor:IsA("Motor6D") then
				table.insert(motors, motor :: Motor6D)
			end
		end
	end
	return motors
end

-- Original-C0s merken, damit die Arme nach dem Wurf wieder runterkommen
local function applyCarryPose(entry, character: Model)
	local pose: { [Motor6D]: CFrame } = {}
	local isR6 = character:FindFirstChild("Torso") ~= nil
	for _, motor in findShoulders(character) do
		pose[motor] = motor.C0
		if isR6 then
			motor.C0 = motor.C0 * CFrame.Angles(0, 0, math.pi) -- R6: um Z hochklappen
		else
			motor.C0 = motor.C0 * CFrame.Angles(math.rad(170), 0, 0) -- R15: um X hochklappen
		end
	end
	entry.CarryPose = pose
end

local function clearCarryPose(entry)
	local pose = entry.CarryPose
	entry.CarryPose = nil
	if not pose then
		return
	end
	for motor, c0 in pose do
		if motor.Parent then
			motor.C0 = c0
		end
	end
end

-- Snack wieder "loose" machen (nach Wurf, Drop, Tod, Slap)
local function release(entry, velocity: Vector3?)
	local player = entry.Holder
	entry.State = "Loose"
	entry.Holder = nil
	entry.SpawnedAt = os.clock() -- Despawn-Timer neu starten
	clearCarryPose(entry) -- Arme wieder runter

	if entry.Weld then
		entry.Weld:Destroy()
		entry.Weld = nil
	end
	if entry.Highlight then
		entry.Highlight:Destroy()
		entry.Highlight = nil
	end
	local part = entry.Part :: BasePart
	part.CanCollide = true
	part.Massless = false
	if velocity then
		part.AssemblyLinearVelocity = velocity
	end
	pcall(function()
		part:SetNetworkOwner(nil) -- Server behält die Physik-Hoheit
	end)
	task.delay(0.3, function()
		if entry.State == "Loose" and entry.Prompt.Parent then
			entry.Prompt.Enabled = true
		end
	end)

	if player then
		held[player] = nil
		player:SetAttribute("HoldingSnack", false)
		player:SetAttribute("HeldSnackName", nil)
		PlayerService.ApplySpeed(player) -- Slowdown aufheben
	end
end

-- Snack im Tresor eines Spielers einlagern
local function bank(entry, owner: Player)
	if entry.State ~= "Loose" then
		return
	end
	-- Frisch aus einem Tresor geworfen/geklaut? Dann nicht sofort wieder einlagern.
	if entry.NoBankUntil and os.clock() < entry.NoBankUntil then
		return
	end

	local def = entry.Def
	if not BaseService.AddToVault(owner, def.Name) then
		-- Tresor voll (oder Daten noch nicht geladen): Snack bleibt liegen
		local now = os.clock()
		if now - (vaultFullNotify[owner] or 0) >= Config.VaultFullNotifyCooldown then
			vaultFullNotify[owner] = now
			notify(owner, "🏦 TRESOR VOLL! [R] am Tresor wirft Snacks raus – oder merge/rebirthe für Platz!")
		end
		return
	end

	entry.State = "Banked"
	entries[entry.Part] = nil
	notify(owner, ("🍫 %s eingelagert! (+%d💰/s)"):format(def.Name, def.Income))
	sfxRemote:FireAllClients("bank", entry.Part.Position)

	-- Season-Pass-XP fürs Einlagern (seltene Snacks geben extra)
	SeasonPassService.AddXp(owner, "Bank")
	if def.Announce then
		SeasonPassService.AddXp(owner, "BankRareBonus")
	end
	AchievementService.Track(owner, "Banked", 1)

	-- Combo: mehrere Snacks kurz nacheinander einlagern = Bonus-Cash
	local now = os.clock()
	local combo = combos[owner]
	if combo and now - combo.Last <= Config.ComboWindow then
		combo.Count += 1
	else
		combo = { Count = 1, Last = now }
		combos[owner] = combo
	end
	combo.Last = now
	if combo.Count >= 2 then
		local bonus = math.max(1, def.Income * Config.ComboBonusFactor * combo.Count)
		PlayerService.AddCash(owner, bonus)
		notify(owner, ("🔥 COMBO x%d! Bonus: +%d💰"):format(combo.Count, bonus))
		if combo.Count == 3 or combo.Count == 5 or combo.Count == 10 then
			announce(("🔥 %s ist ON FIRE! Einlager-Combo x%d!"):format(owner.Name, combo.Count), "Legendary")
		end
	end

	if def.Announce then
		local thrower = entry.LastThrower
		if thrower and thrower ~= owner and thrower.Parent then
			-- Der legendäre Fehlwurf – Comedy-Gold für Clips
			announce(
				("😂 FEHLWURF! %s hat '%s' direkt in %ss Tresor geyeetet!"):format(thrower.Name, def.Name, owner.Name),
				def.Rarity
			)
		else
			announce(("🏦 %s hat '%s' sicher eingelagert!"):format(owner.Name, def.Name), def.Rarity)
		end
	end

	entry.Part:Destroy()
end

local function onTouched(entry, hit: BasePart)
	if entry.State ~= "Loose" then
		return
	end
	if hit.Name == "VaultZone" then
		local owner = BaseService.GetZoneOwner(hit)
		if owner then
			bank(entry, owner)
		end
	end
end

-- ══════════ Spawnen ══════════

-- noBankSeconds: so lange kann der Snack NICHT eingelagert werden – für Snacks,
-- die gerade erst aus einem Tresor geflogen sind (Klau/Rauswurf), sonst saugt
-- die VaultZone sie sofort wieder ein.
function SnackService.SpawnSnack(def, position: Vector3, velocity: Vector3?, noBankSeconds: number?): BasePart
	if countLoose() >= Config.MaxLooseSnacks then
		destroyOldestLoose()
	end

	local part = Instance.new("Part")
	part.Name = "Snack_" .. def.Name
	part.Size = def.Size
	part.Color = def.Color
	part.Material = if def.Rarity == "Legendary" or def.Rarity == "Mythic" or def.Rarity == "Secret"
		then Enum.Material.Neon
		else Enum.Material.SmoothPlastic
	part.Position = position
	part.CanCollide = true
	part:SetAttribute("SnackName", def.Name)
	part:SetAttribute("Rarity", def.Rarity)

	-- ══ MESH-EINBAU: echte Snack-MeshIds in src/shared/SnackTypes.luau eintragen ══
	-- (SnackTypes.Meshes, oben in der Datei – ein Slot pro Snack-Name).
	-- Ist dort eine echte MeshId gesetzt, überlagert sie den simplen Block;
	-- Größe/Kollision/Welds laufen weiter über def.Size, nichts ändert sich an der Logik.
	MeshVisuals.Apply(part, SnackTypes.Meshes[def.Name])

	-- Schwebender Name über dem Snack
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(140, 30)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, def.Size.Y / 2 + 1.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.Name
	label.TextColor3 = SnackTypes.RarityColors[def.Rarity] or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard
	billboard.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Aufheben"
	prompt.ObjectText = def.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	-- Flug-Trail in Raritäts-Farbe (sieht man beim YEETen quer über die Map)
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, def.Size.Y / 2, 0)
	att0.Parent = part
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, -def.Size.Y / 2, 0)
	att1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new(SnackTypes.RarityColors[def.Rarity] or Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.4
	trail.Parent = part

	-- Seltene Snacks glitzern
	if def.Announce then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = SnackTypes.RarityColors[def.Rarity] or Color3.new(1, 1, 1)
		sparkles.Parent = part
	end

	local entry = {
		Part = part,
		Def = def,
		State = "Loose",
		Holder = nil :: Player?,
		Prompt = prompt,
		Weld = nil,
		SpawnedAt = os.clock(),
		LastThrower = nil :: Player?,
		NoBankUntil = if noBankSeconds then os.clock() + noBankSeconds else nil,
	}
	entries[part] = entry

	prompt.Triggered:Connect(function(player)
		SnackService.TryGrab(player, entry)
	end)
	part.Touched:Connect(function(hit)
		onTouched(entry, hit)
	end)
	-- Falls die Engine das Part zerstört (z.B. unter FallenPartsDestroyHeight):
	-- Eintrag aufräumen, sonst leakt die entries-Tabelle und das Snack-Limit stimmt nicht mehr
	part.Destroying:Connect(function()
		entries[part] = nil
		clearCarryPose(entry)
		local holder = entry.Holder
		if holder and held[holder] == entry then
			held[holder] = nil
			holder:SetAttribute("HoldingSnack", false)
			holder:SetAttribute("HeldSnackName", nil)
			PlayerService.ApplySpeed(holder)
		end
	end)

	part.Parent = snackFolder
	if velocity then
		part.AssemblyLinearVelocity = velocity
	end
	-- Lustiges Trudeln beim Spawnen (fliegende Snacks rotieren komisch)
	part.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	return part
end

-- Debug/Admin: alle losen Snacks despawnen, gibt die Anzahl zurück
function SnackService.ClearLoose(): number
	local count = 0
	for part, entry in entries do
		if entry.State == "Loose" then
			entries[part] = nil
			part:Destroy()
			count += 1
		end
	end
	return count
end

function SnackService.SpawnRandom(position: Vector3, velocity: Vector3?): BasePart
	return SnackService.SpawnSnack(SnackTypes.RollRandom(), position, velocity)
end

-- ══════════ Aufheben ══════════

function SnackService.TryGrab(player: Player, entry)
	if entry.State ~= "Loose" or held[player] then
		return
	end
	if player:GetAttribute("Snackified") then
		return -- verwandelte Snacks heben nichts auf 💀
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	local def = entry.Def
	entry.State = "Held"
	entry.Holder = player
	held[player] = entry
	entry.Prompt.Enabled = false

	-- Snack über den Kopf schweben lassen und festschweißen
	local part = entry.Part :: BasePart
	part.CanCollide = false
	part.Massless = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.CFrame = root.CFrame * CFrame.new(0, 3 + def.Size.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = root
	weld.Parent = part
	entry.Weld = weld

	player:SetAttribute("HoldingSnack", true)
	player:SetAttribute("HeldSnackName", def.Name)

	-- Arme hoch – man sieht jedem SOFORT an, dass er Beute trägt
	applyCarryPose(entry, character :: Model)

	-- Schwere Snacks machen langsam
	PlayerService.ApplySpeed(player)
	humanoid.WalkSpeed = humanoid.WalkSpeed * def.Slowdown

	sfxRemote:FireAllClients("grab", part.Position)

	-- Zielscheibe auf dem Rücken: seltene Funde werden ausgerufen
	-- und der Träger leuchtet für ALLE sichtbar durch Wände!
	if def.Announce then
		announce(("⚠️ %s hält: %s! SCHNAPPT IHN EUCH!"):format(player.Name, def.Name), def.Rarity)
		local highlight = Instance.new("Highlight")
		highlight.FillColor = SnackTypes.RarityColors[def.Rarity] or Color3.new(1, 1, 1)
		highlight.FillTransparency = 0.6
		highlight.OutlineColor = SnackTypes.RarityColors[def.Rarity] or Color3.new(1, 1, 1)
		highlight.Parent = character
		entry.Highlight = highlight
	end

	-- Halte-Timer: wer zu lange wartet, lässt den Snack fallen
	local myHoldId = {}
	entry.HoldId = myHoldId
	task.delay(Config.HoldDuration, function()
		if held[player] == entry and entry.HoldId == myHoldId then
			release(entry, Vector3.new(math.random(-6, 6), 4, math.random(-6, 6)))
			notify(player, "😵 Zu schwer! Der Snack ist dir aus den Händen gefallen!")
		end
	end)
end

-- ══════════ YEETen ══════════

local function onThrowRequest(player: Player, charge: any)
	local entry = held[player]
	if not entry then
		return
	end
	if typeof(charge) ~= "number" then
		charge = 1
	end
	charge = math.clamp(charge, 0, 1)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local profile = DataService.Get(player)
	local level = profile and profile.Upgrades.Wurfkraft or 0
	local def = entry.Def

	local power = Config.ThrowBasePower
		* (0.35 + 0.65 * charge) -- Aufladung
		* (1 + level * Config.ThrowPowerPerLevel) -- Wurfkraft-Upgrade
		* def.Slowdown -- schwere Snacks fliegen kürzer

	-- Pet-Boost: Yeet-Pets geben extra Wurfkraft (Attribut setzt NUR der PetService)
	local petYeet = player:GetAttribute("PetYeetBonus")
	if typeof(petYeet) == "number" then
		power *= 1 + petYeet
	end

	-- Sweet Spot: im goldenen Bereich losgelassen = PERFEKTER YEET!
	-- (SweetSpot-Pets machen die goldene Zone breiter)
	local sweetStart = Config.SweetSpotStart
	local petSweet = player:GetAttribute("PetSweetSpotBonus")
	if typeof(petSweet) == "number" then
		sweetStart -= petSweet
	end
	if charge >= sweetStart then
		power *= Config.SweetSpotBonus
		notify(player, "🎯 PERFEKTER YEET!")
		sfxRemote:FireClient(player, "ding")
		SeasonPassService.AddXp(player, "PerfectYeet")
		AchievementService.Track(player, "PerfectYeets", 1)
	end
	sfxRemote:FireAllClients("throw", root.Position)

	local direction = root.CFrame.LookVector
	local velocity = direction * power + Vector3.new(0, power * Config.ThrowUpFactor, 0)

	entry.LastThrower = player
	if profile then
		profile.TotalYeets += 1
	end
	release(entry, velocity)
end

-- ══════════ Fallenlassen & Verwandlung ══════════

-- Verwandelt einen Spieler für kurze Zeit selbst in einen Snack (Comedy-Stun)
local function snackify(player: Player, def)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	player:SetAttribute("Snackified", true)
	-- Beide Sprung-Systeme abdecken (JumpHeight UND JumpPower)
	local prevJumpHeight = humanoid.JumpHeight
	local prevJumpPower = humanoid.JumpPower
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0

	-- Riesiger Snack-Körper um den Spieler (Mindestgröße, sonst ist ein
	-- Keks-Krümel-Kostüm kleiner als der Spieler und der Witz geht verloren)
	local shellSize = def.Size * 2.2
	shellSize = Vector3.new(math.max(shellSize.X, 4.5), math.max(shellSize.Y, 5), math.max(shellSize.Z, 4.5))
	local shell = Instance.new("Part")
	shell.Name = "SnackShell"
	shell.Size = shellSize
	shell.Color = def.Color
	shell.Material = Enum.Material.Neon
	shell.CanCollide = false
	shell.Massless = true
	shell.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = shell
	weld.Part1 = root
	weld.Parent = shell
	shell.Parent = character

	announce(("💀 %s wurde zum Snack verwandelt!"):format(player.Name), def.Rarity)
	notify(player, "💀 DU BIST JETZT DER SNACK! (" .. Config.SnackStunTime .. " Sek.)")
	sfxRemote:FireAllClients("oof", root.Position)

	task.delay(Config.SnackStunTime, function()
		if shell.Parent then
			shell:Destroy()
		end
		if player.Parent then
			player:SetAttribute("Snackified", nil)
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.JumpHeight = prevJumpHeight
				hum.JumpPower = prevJumpPower
			end
			PlayerService.ApplySpeed(player)
		end
	end)
end

-- Snack zwangsweise fallen lassen; transform=true -> Träger wird selbst zum Snack
function SnackService.ForceDrop(player: Player, transform: boolean)
	local entry = held[player]
	if not entry then
		return
	end
	local def = entry.Def
	entry.LastThrower = nil
	release(entry, Vector3.new(math.random(-10, 10), 15, math.random(-10, 10)))
	if transform then
		snackify(player, def)
	end
end

function SnackService.IsHolding(player: Player): boolean
	return held[player] ~= nil
end

-- ══════════ Init ══════════

function SnackService.Init(services)
	BaseService = services.BaseService
	PlayerService = services.PlayerService
	DataService = services.DataService
	SeasonPassService = services.SeasonPassService
	AchievementService = services.AchievementService

	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	snackFolder = Instance.new("Folder")
	snackFolder.Name = "Snacks"
	snackFolder.Parent = workspace

	local throwRemote = Remotes.Get("ThrowRequest") :: RemoteEvent
	throwRemote.OnServerEvent:Connect(onThrowRequest)

	-- Tod & Verlassen: gehaltenen Snack freigeben
	local function hookCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			(humanoid :: Humanoid).Died:Connect(function()
				SnackService.ForceDrop(player, false)
			end)
		end
	end
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			hookCharacter(player, char)
		end)
		-- Charakter verschwindet (Respawn/Reset), ohne dass Died feuert:
		-- gehaltenen Snack freigeben, sonst hängt er als Zombie in der Luft
		player.CharacterRemoving:Connect(function()
			if held[player] then
				SnackService.ForceDrop(player, false)
			end
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entry = held[player]
		if entry then
			release(entry)
		end
		combos[player] = nil
		vaultFullNotify[player] = nil
	end)

	-- Aufräum-Schleife: alte lose Snacks despawnen,
	-- aus der Map gefallene Snacks zurück auf die Plaza retten
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for part, entry in entries do
				if entry.State ~= "Loose" then
					continue
				end
				if now - entry.SpawnedAt > Config.SnackDespawnTime then
					entries[part] = nil
					part:Destroy()
				elseif part.Position.Y < -30 then
					-- Runtergefallen? Zurück in die Chaos-Zone! (Bereich = Plaza-Größe)
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
					part.CFrame = CFrame.new(math.random(-90, 90), 10, math.random(-55, 55))
				end
			end
		end
	end)
end

return SnackService
