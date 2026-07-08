--[[
	StyleService.luau
	Style-Shop: rein kosmetische Lauf-Trails UND Ganzkörper-Skins.
	- Kauf/Ausrüsten server-validiert (Kosten aus Config.Trails/Config.Skins)
	- Nur EIN Trail + EIN Skin gleichzeitig aktiv (profile.EquippedTrail/-Skin)
	- Beides wird bei Equip und nach jedem Respawn neu angewendet
	- Skins färben alle Körperteile um (Farbe/Material/Transparenz); der
	  Original-Look wird gemerkt und beim Ablegen wiederhergestellt
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local StyleService = {}

local DataService, PlayerService, GemService -- in Init verdrahtet

local trailDefsById: { [string]: any } = {}
for _, def in Config.Trails do
	trailDefsById[def.Id] = def
end
-- Season-Pass-Trails: ausrüstbar wie normale Trails, aber NICHT kaufbar
-- (Seasonal = true -> buyTrail lehnt ab, verteilt werden sie vom SeasonPassService)
for _, def in Config.SeasonTrails do
	trailDefsById[def.Id] = def
end
-- Juwelen-Trails: kaufbar NUR mit 💎 (GemCost) bzw. als Parkour-Meister-
-- Belohnung (RewardOnly – vergibt der ParkourService direkt in profile.Trails)
for _, def in Config.GemTrails do
	trailDefsById[def.Id] = def
end

local skinDefsById: { [string]: any } = {}
for _, def in Config.Skins do
	skinDefsById[def.Id] = def
end
for _, def in Config.GemSkins do
	skinDefsById[def.Id] = def
end

local TRAIL_NAME = "StyleTrail"
local SKIN_SPARKLES = "SkinSparkles"

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

-- ══════════ Skins ══════════

-- Original-Look pro Charakter merken, damit "Skin ablegen" ihn wiederherstellt
local originalLooks: { [Model]: { [BasePart]: { Color: Color3, Material: Enum.Material, Transparency: number } } } =
	{}

local function clearSkin(character: Model)
	local originals = originalLooks[character]
	if originals then
		for part, look in originals do
			if part.Parent then
				part.Color = look.Color
				part.Material = look.Material
				part.Transparency = look.Transparency
			end
		end
	end
	originalLooks[character] = nil
	local sparkles = character:FindFirstChild(SKIN_SPARKLES, true)
	if sparkles then
		sparkles:Destroy()
	end
end

-- Färbt alle Körperteile des (aktuellen) Charakters im Skin-Look um
local function applySkin(player: Player)
	local profile = DataService.Get(player)
	local character = player.Character
	if not profile or not character then
		return
	end
	clearSkin(character)

	local def = skinDefsById[profile.EquippedSkin]
	if not def then
		return
	end

	local originals = {}
	for _, part in character:GetChildren() do
		-- Nur direkte Körperteile (Accessoires/Hüte bleiben, wie sie sind)
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			originals[part] = { Color = part.Color, Material = part.Material, Transparency = part.Transparency }
			part.Color = def.Color
			part.Material = def.Material
			part.Transparency = def.Transparency or 0
		end
	end
	originalLooks[character] = originals

	if def.Sparkles then
		local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
		if torso then
			local sparkles = Instance.new("Sparkles")
			sparkles.Name = SKIN_SPARKLES
			sparkles.SparkleColor = def.Color
			sparkles.Parent = torso
		end
	end
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
	if def.Seasonal then
		return { ok = false, msg = "Den gibt's nur als Season-Pass-Belohnung!" }
	end
	if def.RewardOnly then
		return { ok = false, msg = "Nur für Parkour-MEISTER: alle 8 Parcours unter der Meister-Zeit!" }
	end
	if def.GemCost then
		if not GemService.TrySpendGems(player, def.GemCost) then
			return { ok = false, msg = ("Zu wenig Juwelen! (%d💎 nötig – ab in den Parkour!)"):format(def.GemCost) }
		end
	elseif not PlayerService.TrySpend(player, def.Cost) then
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

local function buySkin(player: Player, skinId: any)
	if typeof(skinId) ~= "string" or not skinDefsById[skinId] then
		return { ok = false, msg = "Unbekannter Skin." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	if profile.Skins[skinId] then
		return { ok = false, msg = "Den Skin hast du schon!" }
	end
	local def = skinDefsById[skinId]
	if def.GemCost then
		if not GemService.TrySpendGems(player, def.GemCost) then
			return { ok = false, msg = ("Zu wenig Juwelen! (%d💎 nötig – ab in den Parkour!)"):format(def.GemCost) }
		end
	elseif not PlayerService.TrySpend(player, def.Cost) then
		return { ok = false, msg = ("Zu wenig Cash! (%d💰 nötig)"):format(def.Cost) }
	end
	profile.Skins[skinId] = true
	return { ok = true, msg = ("%s gekauft! Gleich anziehen?"):format(def.Name) }
end

local function equipSkin(player: Player, skinId: any)
	if typeof(skinId) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	if skinId == "" then
		profile.EquippedSkin = ""
		if player.Character then
			clearSkin(player.Character)
		end
		return { ok = true, msg = "Skin abgelegt – zurück zum Normalo-Look." }
	end
	local def = skinDefsById[skinId]
	if not def or not profile.Skins[skinId] then
		return { ok = false, msg = "Der Skin gehört dir (noch) nicht!" }
	end
	profile.EquippedSkin = skinId
	applySkin(player)
	return { ok = true, msg = ("%s angezogen – schick!"):format(def.Name) }
end

-- ══════════ Init ══════════

function StyleService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	GemService = services.GemService;

	(Remotes.Get("BuyTrail") :: RemoteFunction).OnServerInvoke = buyTrail;
	(Remotes.Get("EquipTrail") :: RemoteFunction).OnServerInvoke = equipTrail;
	(Remotes.Get("BuySkin") :: RemoteFunction).OnServerInvoke = buySkin;
	(Remotes.Get("EquipSkin") :: RemoteFunction).OnServerInvoke = equipSkin

	-- Nach jedem (Re-)Spawn gespeicherten Trail + Skin wieder anwenden
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			task.spawn(function()
				DataService.WaitFor(player)
				task.wait(0.2) -- HumanoidRootPart/Körperteile kurz Zeit geben
				applyTrail(player)
				applySkin(player)
			end)
		end)
		-- Aufräumen: Original-Look-Cache nicht auf tote Charaktere zeigen lassen
		player.CharacterRemoving:Connect(function(character)
			originalLooks[character] = nil
		end)
		if player.Character then
			task.spawn(function()
				DataService.WaitFor(player)
				applyTrail(player)
				applySkin(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return StyleService
