--[[
	PetService.luau
	Pet-System 2.0: Eier statt Direktkauf (Gacha)!
	- Eier kaufen (Config.Eggs) -> Server würfelt Rarität + Pet (Config.EggPets)
	- Duplikate werden in Trost-Cash umgewandelt (Config.PetDuplicateRefund)
	- Bis zu Config.PetMaxEquipped Pets gleichzeitig aktiv (profile.EquippedPets)
	- Jedes Pet gibt EINEN Boost (Ability), aggregiert als Player-Attribute:
	    PetIncomeBonus / PetCashMult / PetYeetBonus / PetSpeedBonus /
	    PetSlapRangeBonus / PetSlapCooldownFactor / PetSweetSpotBonus
	  SnackService/SlapService/Client lesen NUR diese Attribute (Server setzt sie).
	- Pets folgen dem Spieler als schwebende Neon-Kugeln (Heartbeat-Lerp + Bobbing)
	- Alt-Daten-Migration: profile.EquippedPet (alter Einzel-Slot) -> EquippedPets

	Beherbergt außerdem das "GetCollections"-Remote (Pets + Trails + Skins in
	einem Aufruf), damit die Shop-UIs mit einem Roundtrip auskommen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PetService = {}

local DataService, PlayerService -- in Init verdrahtet
local servicesRef -- komplette Services-Tabelle (für optionale Hooks wie Season-XP)

local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

local petFolder: Folder
local petParts: { [Player]: { BasePart } } = {}

-- Schwebe-Positionen relativ zum Spieler (Slot 1/2/3)
local PET_OFFSETS = {
	Vector3.new(3, 2.5, 3),
	Vector3.new(-3, 2.5, 3),
	Vector3.new(0, 3.2, 4.5),
}

-- ══════════ Begleiter-Optik ══════════

local function destroyPets(player: Player)
	local parts = petParts[player]
	if parts then
		for _, part in parts do
			part:Destroy()
		end
		petParts[player] = nil
	end
end

local function makePetPart(def, offset: Vector3, rootCFrame: CFrame?): BasePart
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
	billboard.Size = UDim2.fromOffset(140, 24)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.Name
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = SnackTypes.RarityColors[def.Rarity] or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = part

	-- Seltene Pets glitzern (soll man von Weitem neidisch werden!)
	if def.Rarity == "Legendary" or def.Rarity == "Mythic" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = def.Color
		sparkles.Parent = part
	end

	part.CFrame = if rootCFrame then rootCFrame * CFrame.new(offset) else CFrame.new(0, 5, 50)
	part.Parent = petFolder
	return part
end

-- Baut die Begleiter eines Spielers passend zu profile.EquippedPets neu auf
local function spawnPets(player: Player)
	destroyPets(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local parts = {}
	for slot, petId in profile.EquippedPets do
		local def = Config.EggPetsById[petId]
		local offset = PET_OFFSETS[slot]
		if def and offset then
			table.insert(parts, makePetPart(def, offset, root and root.CFrame))
		end
	end
	petParts[player] = parts
end

-- ══════════ Boost-Aggregation ══════════

-- Summiert die Abilities aller ausgerüsteten Pets und spiegelt sie als
-- Attribute (replizieren automatisch -> UI zeigt sie, Services lesen sie).
local function refreshBoosts(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local sums = { Income = 0, CashMult = 0, Yeet = 0, Speed = 0, SlapRange = 0, SlapCooldown = 0, SweetSpot = 0 }
	for _, petId in profile.EquippedPets do
		local def = Config.EggPetsById[petId]
		if def and sums[def.Ability.Type] then
			sums[def.Ability.Type] += def.Ability.Value
		end
	end
	player:SetAttribute("PetIncomeBonus", sums.Income)
	player:SetAttribute("PetCashMult", sums.CashMult)
	player:SetAttribute("PetYeetBonus", sums.Yeet)
	player:SetAttribute("PetSpeedBonus", sums.Speed)
	-- Cooldown nie unter 20% drücken, Sweet-Spot nie breiter als +10% (Server-Clamp)
	player:SetAttribute("PetSlapCooldownFactor", math.max(0.2, 1 - sums.SlapCooldown))
	player:SetAttribute("PetSweetSpotBonus", math.min(sums.SweetSpot, 0.1))
	PlayerService.ApplySpeed(player) -- Speed-Bonus sofort anwenden (siehe Wrapper in Init)
	spawnPets(player)
end

-- ══════════ Ei-Würfe (Server-Autorität!) ══════════

-- Erst Rarität (gewichtete Chances des Eis), dann gleichverteiltes Pet der Stufe.
-- Exklusive Pets (Season-Pass) fallen NIE aus Eiern.
local function rollPet(eggDef)
	local total = 0
	for _, weight in eggDef.Chances do
		total += weight
	end
	local roll = math.random() * total
	local rarity = "Common"
	for r, weight in eggDef.Chances do
		roll -= weight
		if roll <= 0 then
			rarity = r
			break
		end
	end
	local pool = {}
	for _, def in Config.EggPets do
		if def.Rarity == rarity and not def.Exclusive then
			table.insert(pool, def)
		end
	end
	return pool[math.random(1, #pool)]
end

-- Öffnet ein Ei OHNE Bezahlung (nutzt auch der Season-Pass für Gratis-Eier).
-- Gibt das volle Ergebnis-Paket fürs Client-Reveal zurück.
function PetService.GrantEgg(player: Player, eggId: string)
	local eggDef = Config.EggsById[eggId]
	local profile = DataService.Get(player)
	if not eggDef or not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end

	local def = rollPet(eggDef)
	local duplicate = profile.Pets[def.Id] == true
	local refund = 0
	local msg
	if duplicate then
		refund = Config.PetDuplicateRefund[def.Rarity] or 0
		PlayerService.AddCash(player, refund)
		msg = ("%s war DOPPELT – dafür gibt's %d💰 Trostpflaster!"):format(def.Name, refund)
	else
		profile.Pets[def.Id] = true
		msg = ("NEU: %s (%s)! %s"):format(def.Name, def.Rarity, def.Desc)
	end

	if def.Rarity == "Legendary" or def.Rarity == "Mythic" then
		announceRemote:FireAllClients(
			("🥚 JACKPOT! %s hat '%s' aus einem %s gezogen!"):format(player.Name, def.Name, eggDef.Name),
			def.Rarity
		)
	end

	-- Achievement-Fortschritt (lose verdrahtet, wie der Season-Pass-Hook unten)
	local achievements = servicesRef and servicesRef.AchievementService
	if achievements then
		achievements.Track(player, "EggsOpened", 1)
		if def.Rarity == "Legendary" or def.Rarity == "Mythic" then
			achievements.Track(player, "LegendaryPets", 1)
		end
	end

	return {
		ok = true,
		msg = msg,
		Pet = { Id = def.Id, Name = def.Name, Rarity = def.Rarity, Desc = def.Desc },
		Duplicate = duplicate,
		Refund = refund,
	}
end

-- ══════════ Remote-Handler ══════════

local function buyEgg(player: Player, eggId: any)
	if typeof(eggId) ~= "string" or not Config.EggsById[eggId] then
		return { ok = false, msg = "Unbekanntes Ei." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	local eggDef = Config.EggsById[eggId]
	if not PlayerService.TrySpend(player, eggDef.Cost) then
		return { ok = false, msg = ("Zu wenig Cash! (%d💰 nötig)"):format(eggDef.Cost) }
	end

	local result = PetService.GrantEgg(player, eggId)
	if result.ok then
		sfxRemote:FireClient(player, "ding")
		-- Season-Pass-XP fürs Ei-Öffnen (Service existiert erst nach Teil 2 – defensiv)
		local seasonPass = servicesRef and servicesRef.SeasonPassService
		if seasonPass then
			seasonPass.AddXp(player, "EggOpen")
		end
	end
	return result
end

-- Legacy: Direktkauf gibt es nicht mehr – alte Clients kriegen einen Hinweis
local function buyPet(_player: Player, _petId: any)
	return { ok = false, msg = "Pets schlüpfen jetzt aus EIERN – schnapp dir eins im Pet-Shop!" }
end

-- Toggle: petId ausrüsten/ablegen, "" = alle ablegen
local function equipPet(player: Player, petId: any)
	if typeof(petId) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	if petId == "" then
		table.clear(profile.EquippedPets)
		refreshBoosts(player)
		return { ok = true, msg = "Alle Pets in die Tasche gesteckt." }
	end

	local def = Config.EggPetsById[petId]
	if not def or not profile.Pets[petId] then
		return { ok = false, msg = "Das Pet gehört dir (noch) nicht!" }
	end

	local index = table.find(profile.EquippedPets, petId)
	if index then
		table.remove(profile.EquippedPets, index)
		refreshBoosts(player)
		return { ok = true, msg = ("%s macht Pause."):format(def.Name) }
	end
	if #profile.EquippedPets >= Config.PetMaxEquipped then
		return { ok = false, msg = ("Alle %d Pet-Slots voll – erst eins ablegen!"):format(Config.PetMaxEquipped) }
	end
	table.insert(profile.EquippedPets, petId)
	refreshBoosts(player)
	return { ok = true, msg = ("%s trottet jetzt hinter dir her!"):format(def.Name) }
end

-- Pets + Trails + Skins in einem Rutsch (fürs Shop-UI)
local function getCollections(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	return {
		Pets = profile.Pets,
		EquippedPets = profile.EquippedPets,
		EquippedPet = profile.EquippedPet, -- Legacy-Feld (nach Migration immer "")
		Trails = profile.Trails,
		EquippedTrail = profile.EquippedTrail,
		Skins = profile.Skins,
		EquippedSkin = profile.EquippedSkin,
	}
end

-- ══════════ Init ══════════

function PetService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	servicesRef = services

	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	(Remotes.Get("BuyEgg") :: RemoteFunction).OnServerInvoke = buyEgg;
	(Remotes.Get("BuyPet") :: RemoteFunction).OnServerInvoke = buyPet;
	(Remotes.Get("EquipPet") :: RemoteFunction).OnServerInvoke = equipPet;
	(Remotes.Get("GetCollections") :: RemoteFunction).OnServerInvoke = getCollections

	petFolder = Instance.new("Folder")
	petFolder.Name = "Pets"
	petFolder.Parent = workspace

	-- Speed-Pets: PlayerService.ApplySpeed wird UMHÜLLT statt geändert
	-- (PlayerService gehört dem Kollegen – wir hängen uns nur von außen dran).
	-- Alle Aufrufer schlagen das Feld zur Laufzeit nach, der Wrapper greift also überall.
	local baseApplySpeed = PlayerService.ApplySpeed
	PlayerService.ApplySpeed = function(target: Player)
		baseApplySpeed(target)
		local bonus = target:GetAttribute("PetSpeedBonus")
		if typeof(bonus) == "number" and bonus > 0 then
			local character = target.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			-- WalkSpeed 0 = gestunnt/verwandelt -> kein Pet-Turbo für Snacks 💀
			if humanoid and humanoid.WalkSpeed > 0 then
				humanoid.WalkSpeed += bonus
			end
		end
	end

	-- Beim Join: Alt-Daten migrieren (Einzel-Slot -> Liste) und Pets herbeirufen
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitFor(player)
			if not profile then
				return
			end
			if profile.EquippedPet ~= "" then
				if profile.Pets[profile.EquippedPet] and not table.find(profile.EquippedPets, profile.EquippedPet) then
					table.insert(profile.EquippedPets, profile.EquippedPet)
				end
				profile.EquippedPet = ""
			end
			-- Gelöschte/umbenannte Config-Einträge aus der Equip-Liste werfen
			for i = #profile.EquippedPets, 1, -1 do
				if not Config.EggPetsById[profile.EquippedPets[i]] then
					table.remove(profile.EquippedPets, i)
				end
			end
			refreshBoosts(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(destroyPets)

	-- Folge-Schleife: Pets schweben um den Spieler + fröhliches Bobbing
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, parts in petParts do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				for slot, part in parts do
					local offset = PET_OFFSETS[slot] or PET_OFFSETS[1]
					local bob = math.sin(now * 4 + slot * 2) * 0.5
					local target = root.CFrame * CFrame.new(offset + Vector3.new(0, bob, 0))
					part.CFrame = part.CFrame:Lerp(target, math.min(dt * 6, 1))
				end
			end
		end
	end)

	-- Einkommens-Schleife: Income-Pets zahlen flach, CashMult-Pets legen
	-- einen Anteil des ROHEN Tresor-Einkommens oben drauf (beides mit
	-- Rebirth-Multiplikator; der Tycoon-Bonus läuft separat im BaseService).
	task.spawn(function()
		while true do
			task.wait(Config.PetIncomeTick)
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if not profile then
					continue
				end
				local flat, cashMult = 0, 0
				for _, petId in profile.EquippedPets do
					local def = Config.EggPetsById[petId]
					if def then
						if def.Ability.Type == "Income" then
							flat += def.Ability.Value
						elseif def.Ability.Type == "CashMult" then
							cashMult += def.Ability.Value
						end
					end
				end
				local total = flat
				if cashMult > 0 then
					local vaultIncome = 0
					for _, snackName in profile.Vault do
						local snackDef = SnackTypes.ByName[snackName]
						if snackDef then
							vaultIncome += snackDef.Income
						end
					end
					total += vaultIncome * cashMult
				end
				if total > 0 then
					PlayerService.AddCash(player, total * DataService.GetMultiplier(player) * Config.PetIncomeTick)
				end
			end
		end
	end)
end

return PetService
