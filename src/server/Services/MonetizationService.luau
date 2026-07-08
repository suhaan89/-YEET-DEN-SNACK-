--[[
	MonetizationService.luau
	Robux-Monetarisierung: Developer Products + VIP-Gamepass.

	Developer Products (Config.Monetization.Products, ProductId 0 = Platzhalter):
	- Boost2x    -> +100% Tresor-Einkommen für 30 Min. Ablauf-Zeitpunkt liegt
	               als os.time() im Profil (BoostUntil) und übersteht Rejoins.
	- VaultSell  -> verkauft ALLE Tresor-Snacks sofort (Wert pro Snack =
	               Income * SellSecondsWorth * Rebirth-Multiplikator).
	- VaultSlots -> dauerhaft +N Tresor-Plätze (profile.ExtraVaultSlots,
	               fließt über Config.VaultLimit ein, überlebt Rebirths).
	- EggBundle  -> N Eier, sofort geöffnet (PetService.GrantEgg).

	ProcessReceipt ist IDEMPOTENT: Jede PurchaseId wird nach der Auszahlung im
	Receipt-DataStore quittiert. Kommt derselbe Receipt nochmal (Roblox wiederholt
	bei Timeouts!), wird nur noch PurchaseGranted zurückgegeben, ohne erneut
	auszuzahlen. Ohne DataStore-Zugriff (Studio ohne API) wird trotzdem
	ausgezahlt – Testkäufe kosten ja nichts.

	VIP-Gamepass: dauerhafter Einkommens-Bonus (Income-Tick nach dem
	FriendService-Muster – BaseService bleibt unangetastet), 👑-Nametag über
	dem Kopf und eine exklusive VIP-Lounge auf der Map (Nicht-VIPs werden
	freundlich rausteleportiert).

	Fürs UI replizieren zwei Player-Attribute: IsVip (bool), BoostUntil (number).
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MonetizationService = {}

local DataService, PlayerService, BaseService, PetService -- in Init verdrahtet

local notifyRemote: RemoteEvent
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

local receiptStore = nil

-- Rohes Tresor-Einkommen (gleiche Formel wie FriendService – nur LESEN!)
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

-- Fehlende Monetarisierungs-Felder lazy anlegen (DataService bleibt unberührt)
local function ensureFields(profile): ()
	if typeof(profile.BoostUntil) ~= "number" then
		profile.BoostUntil = 0
	end
	if typeof(profile.ExtraVaultSlots) ~= "number" then
		profile.ExtraVaultSlots = 0
	end
end

local function syncAttributes(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	ensureFields(profile)
	player:SetAttribute("BoostUntil", profile.BoostUntil)
end

-- ══════════ Produkt-Auszahlungen ══════════
-- Geben (ok, Toast-Text) zurück; bei ok=false wird der Kauf NICHT quittiert
-- (Roblox versucht es später erneut).

local grantHandlers: { [string]: (Player, any) -> (boolean, string) } = {}

grantHandlers.Boost2x = function(player, def)
	local profile = DataService.Get(player)
	if not profile then
		return false, ""
	end
	ensureFields(profile)
	-- Läuft schon ein Boost? Dann wird VERLÄNGERT, nichts verfällt.
	local base = math.max(os.time(), profile.BoostUntil)
	profile.BoostUntil = base + def.DurationSeconds
	syncAttributes(player)
	return true, ("⚡ 2x-Boost aktiv! Läuft noch %d Minuten."):format(math.ceil((profile.BoostUntil - os.time()) / 60))
end

grantHandlers.VaultSell = function(player, def)
	local profile = DataService.Get(player)
	if not profile then
		return false, ""
	end
	local total = 0
	local count = #profile.Vault
	local multiplier = DataService.GetMultiplier(player)
	for _, snackName in profile.Vault do
		local snackDef = SnackTypes.ByName[snackName]
		if snackDef then
			total += snackDef.Income * def.SellSecondsWorth * multiplier
		end
	end
	table.clear(profile.Vault)
	total = math.floor(total)
	PlayerService.AddCash(player, total)
	PlayerService.Sync(player)
	BaseService.RefreshDisplay(player)
	return true, ("💸 %d Snacks verkauft: +%d💰!"):format(count, total)
end

grantHandlers.VaultSlots = function(player, def)
	local profile = DataService.Get(player)
	if not profile then
		return false, ""
	end
	ensureFields(profile)
	profile.ExtraVaultSlots += def.Slots
	PlayerService.Sync(player) -- VaultLimit-Attribut aktualisieren
	BaseService.RefreshDisplay(player)
	return true, ("🧰 +%d Tresor-Plätze für IMMER! (jetzt %d extra)"):format(def.Slots, profile.ExtraVaultSlots)
end

grantHandlers.EggBundle = function(player, def)
	local profile = DataService.Get(player)
	if not profile then
		return false, ""
	end
	local lines = {}
	for _ = 1, def.Count do
		local result = PetService.GrantEgg(player, def.Egg)
		if result.ok then
			table.insert(lines, result.msg)
		end
	end
	if #lines == 0 then
		return false, ""
	end
	return true, ("🥚 Bundle geöffnet!\n%s"):format(table.concat(lines, "\n"))
end

-- ══════════ ProcessReceipt (idempotent!) ══════════

local function findProductByRobloxId(productId: number): any?
	for _, def in Config.Monetization.Products do
		if def.ProductId > 0 and def.ProductId == productId then
			return def
		end
	end
	return nil
end

local function receiptKey(receiptInfo): string
	return "Receipt_" .. tostring(receiptInfo.PurchaseId)
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Spieler weg: NICHT quittieren – Roblox liefert den Receipt beim
		-- nächsten Join erneut, dann wird ausgezahlt.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Schon quittiert? (Roblox wiederholt Receipts nach Timeouts)
	if receiptStore then
		local ok, done = pcall(function()
			return receiptStore:GetAsync(receiptKey(receiptInfo))
		end)
		if ok and done then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	local def = findProductByRobloxId(receiptInfo.ProductId)
	if not def then
		warn("[MonetizationService] Unbekannte ProductId im Receipt:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.WaitFor(player, 10)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = grantHandlers[def.Id]
	if not handler then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local granted, message = handler(player, def)
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Quittieren – erst NACH erfolgreicher Auszahlung. Schlägt das Schreiben
	-- fehl, wird schlimmstenfalls doppelt ausgezahlt (spielerfreundlich) statt
	-- Robux zu verschlucken.
	if receiptStore then
		pcall(function()
			receiptStore:SetAsync(receiptKey(receiptInfo), true)
		end)
	end

	notifyRemote:FireClient(player, message)
	sfxRemote:FireClient(player, "ding")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ══════════ VIP-Gamepass ══════════

local function applyVipTag(player: Player)
	if player:GetAttribute("IsVip") ~= true then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or head:FindFirstChild("VipTag") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VipTag"
	billboard.Size = UDim2.fromOffset(110, 24)
	-- Über den Rebirth-Sternen (die sitzen bei 2.2)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = "👑 VIP"
	label.TextColor3 = Color3.fromRGB(255, 215, 0)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = head
end

local function setVip(player: Player, isVip: boolean)
	player:SetAttribute("IsVip", isVip)
	if isVip then
		applyVipTag(player)
	end
end

-- ══════════ VIP-Lounge (exklusiver Map-Bereich) ══════════

local LOUNGE_CENTER = Vector3.new(-70, 0, 195) -- Wiese hinterm Spawn, westlich vom Parkour-Hub
local LOUNGE_SIZE = 26

local function buildVipLounge()
	local folder = Instance.new("Folder")
	folder.Name = "VipLounge"

	local function part(props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in props do
			(p :: any)[key] = value
		end
		p.Parent = folder
		return p
	end

	-- Goldener Boden + Neon-Rahmen
	part({
		Name = "Floor",
		Size = Vector3.new(LOUNGE_SIZE, 0.6, LOUNGE_SIZE),
		Position = LOUNGE_CENTER + Vector3.new(0, 0.3, 0),
		Color = Color3.fromRGB(255, 210, 60),
		Material = Enum.Material.Marble,
	})
	for _, offset in {
		Vector3.new(0, 0.7, -LOUNGE_SIZE / 2),
		Vector3.new(0, 0.7, LOUNGE_SIZE / 2),
	} do
		part({
			Size = Vector3.new(LOUNGE_SIZE + 1, 0.8, 1),
			Position = LOUNGE_CENTER + offset,
			Color = Color3.fromRGB(255, 230, 130),
			Material = Enum.Material.Neon,
		})
	end
	for _, offset in {
		Vector3.new(-LOUNGE_SIZE / 2, 0.7, 0),
		Vector3.new(LOUNGE_SIZE / 2, 0.7, 0),
	} do
		part({
			Size = Vector3.new(1, 0.8, LOUNGE_SIZE + 1),
			Position = LOUNGE_CENTER + offset,
			Color = Color3.fromRGB(255, 230, 130),
			Material = Enum.Material.Neon,
		})
	end

	-- Zwei Protz-Throne
	for _, x in { -5, 5 } do
		part({
			Size = Vector3.new(3.4, 1.2, 3.4),
			Position = LOUNGE_CENTER + Vector3.new(x, 1.2, 8),
			Color = Color3.fromRGB(180, 40, 60),
			Material = Enum.Material.Fabric,
		})
		part({
			Size = Vector3.new(3.4, 4.6, 0.8),
			Position = LOUNGE_CENTER + Vector3.new(x, 3.2, 9.4),
			Color = Color3.fromRGB(255, 210, 60),
			Material = Enum.Material.Metal,
		})
	end

	-- Funkel-Brunnen in der Mitte
	local fountain = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.5, 6, 6),
		CFrame = CFrame.new(LOUNGE_CENTER + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 230, 130),
		Material = Enum.Material.Neon,
	})
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 215, 0)
	sparkles.Parent = fountain

	-- Schild
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(14, 3, 0.6),
		Position = LOUNGE_CENTER + Vector3.new(0, 8, -LOUNGE_SIZE / 2),
		Color = Color3.fromRGB(25, 25, 35),
		Material = Enum.Material.Neon,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(900, 200)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "👑 VIP-LOUNGE 👑"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 215, 0)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = sign
	end

	folder.Parent = workspace:FindFirstChild("Map") or workspace

	-- Türsteher-Schleife: Nicht-VIPs werden freundlich vor die Tür gesetzt
	local warned: { [Player]: number } = {}
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("IsVip") == true then
					continue
				end
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root then
					continue
				end
				local offset = root.Position - LOUNGE_CENTER
				if math.abs(offset.X) > LOUNGE_SIZE / 2 or math.abs(offset.Z) > LOUNGE_SIZE / 2 or offset.Y > 20 then
					continue
				end
				-- Vor die Lounge teleportieren (Richtung Spawn)
				root.CFrame = CFrame.new(LOUNGE_CENTER + Vector3.new(0, 4, -LOUNGE_SIZE / 2 - 6))
				if os.clock() - (warned[player] or 0) > 5 then
					warned[player] = os.clock()
					notifyRemote:FireClient(player, "👑 Sorry, nur für VIPs! Den VIP-Pass gibt's im 🛍️ Robux-Shop.")
				end
			end
		end
	end)
end

-- ══════════ Init ══════════

function MonetizationService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	BaseService = services.BaseService
	PetService = services.PetService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Monetization.ReceiptDataStore)
	end)
	if ok then
		receiptStore = result
	else
		warn("[MonetizationService] Kein DataStore-Zugriff – Receipts werden NICHT quittiert (nur Studio-Test!).")
	end

	MarketplaceService.ProcessReceipt = processReceipt

	buildVipLounge()

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitFor(player)
			if not profile or not player.Parent then
				return
			end
			ensureFields(profile)
			syncAttributes(player)
			PlayerService.Sync(player) -- ExtraVaultSlots ins VaultLimit-Attribut

			-- VIP-Besitz prüfen (0 = Gamepass noch nicht angelegt)
			if Config.Monetization.VipGamepassId > 0 then
				local okVip, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.Monetization.VipGamepassId)
				end)
				if okVip and owns and player.Parent then
					setVip(player, true)
				end
			end
		end)
		player.CharacterAdded:Connect(function()
			task.wait(0.2) -- Head kurz Zeit geben
			applyVipTag(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- VIP-Kauf direkt im Spiel
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, purchased: boolean)
		if purchased and Config.Monetization.VipGamepassId > 0 and gamePassId == Config.Monetization.VipGamepassId then
			setVip(player, true)
			announceRemote:FireAllClients(("👑 %s ist jetzt VIP – Verbeugung bitte!"):format(player.Name), "Legendary")
		end
	end)

	-- Bonus-Auszahlung: VIP-Bonus + 2x-Boost aufs rohe Tresor-Einkommen
	-- (eigener Tick nach dem FriendService-Muster – BaseService bleibt unangetastet)
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTick)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if not profile then
					continue
				end
				local percent = 0
				if player:GetAttribute("IsVip") == true then
					percent += Config.Monetization.VipCashBonusPercent
				end
				if typeof(profile.BoostUntil) == "number" and profile.BoostUntil > now then
					percent += Config.Monetization.BoostBonusPercent
				end
				if percent <= 0 then
					continue
				end
				local bonus = getVaultIncome(player) * percent * DataService.GetMultiplier(player)
				if bonus > 0 then
					PlayerService.AddCash(player, bonus * Config.IncomeTick)
				end
			end
		end
	end)
end

return MonetizationService
