--[[
	Ui.luau
	Komplettes Prototyp-UI, per Code gebaut (später in Studio hübsch machen):
	- Cash-Anzeige (oben links) mit Rebirth-Multiplikator
	- Ankündigungs-Banner (oben mitte, mit Raritäts-Farbe)
	- Toast-Nachrichten (unten mitte)
	- Shop-Fenster (Upgrade/Pets/Style/Merge) – öffnen NUR über die
	  Shop-Gebäude in der Map (Server feuert "OpenShop"), kein Button mehr!
	- YEET-Ladebalken + Halte-Hinweis
	- Supreme-Truck-Fortschrittsanzeige
	- Debug-Menü (nur für Entwickler sichtbar)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local SnackTypes = require(shared:WaitForChild("SnackTypes"))
local Remotes = require(shared:WaitForChild("Remotes"))

local Ui = {}

local player = Players.LocalPlayer

local FONT = Enum.Font.FredokaOne

-- Handles, die Build() befüllt
local gui: ScreenGui
local cashLabel: TextLabel
local announceLabel: TextLabel
local toastContainer: Frame
local shopFrame: Frame
local chargeBarBg: Frame
local chargeBarFill: Frame
local holdHint: TextLabel
local upgradeRows: { [string]: { Level: TextLabel, Button: TextButton } } = {}
local rebirthButton: TextButton

-- Shop-Fenster-Registry: shopId -> Frame (öffnen über Ui.OpenShop)
local shopWindows: { [string]: Frame } = {}

-- Pet-/Style-Shop: Buttons pro Item + Cache des Server-Stands
local petRows: { [string]: TextButton } = {}
local trailRows: { [string]: TextButton } = {}
local collectionsCache: any = { Pets = {}, EquippedPet = "", Trails = {}, EquippedTrail = "" }

-- Merge-Station
local mergeList: ScrollingFrame

-- ══════════ Kleine Helfer ══════════

local function formatNumber(n: number): string
	n = math.floor(n)
	if n >= 1_000_000 then
		return string.format("%.1fM", n / 1_000_000)
	elseif n >= 10_000 then
		return string.format("%.1fk", n / 1_000)
	end
	return tostring(n)
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function roundify(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- Rotes ✕ oben rechts – seit die Shops Orte sind, braucht jedes Fenster einen Schließer
local function addCloseButton(frame: Frame)
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 8)
	close.Size = UDim2.fromOffset(30, 30)
	close.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	close.Font = FONT
	close.TextScaled = true
	close.Text = "✕"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.ZIndex = 5
	roundify(close, 8)
	close.Parent = frame
	close.Activated:Connect(function()
		frame.Visible = false
	end)
end

-- Zentriertes Fenster mit Titel + Schließen-Button (Grundgerüst aller Shop-UIs)
local function makeWindow(title: string, size: Vector2, titleColor: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
	frame.BackgroundTransparency = 0.05
	frame.Visible = false
	roundify(frame, 16)
	makeLabel(frame, {
		Size = UDim2.new(1, -80, 0, 40),
		Position = UDim2.fromOffset(40, 0),
		Text = title,
		TextColor3 = titleColor,
	})
	addCloseButton(frame)
	frame.Parent = gui
	return frame
end

-- ══════════ Cash-Anzeige ══════════

local function buildCashDisplay()
	local frame = Instance.new("Frame")
	frame.Name = "CashDisplay"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.new(0, 12, 0, 12)
	frame.Size = UDim2.fromOffset(190, 44)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BackgroundTransparency = 0.25
	roundify(frame, 12)
	cashLabel = makeLabel(frame, {
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = "💰 0",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	frame.Parent = gui

	-- Cash live aus den Leaderstats spiegeln
	local function refresh()
		local stats = player:FindFirstChild("leaderstats")
		local cash = stats and stats:FindFirstChild("Cash") :: IntValue?
		local mult = player:GetAttribute("Multiplier") or 1
		local multText = mult > 1 and ("  (x%.1f)"):format(mult) or ""
		cashLabel.Text = "💰 " .. formatNumber(cash and cash.Value or 0) .. multText
	end
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats", 20)
		if not stats then
			return
		end
		local cash = stats:WaitForChild("Cash", 20) :: IntValue?
		if cash then
			cash.Changed:Connect(refresh)
		end
		player:GetAttributeChangedSignal("Multiplier"):Connect(refresh)
		refresh()
	end)
end

-- ══════════ Ankündigungs-Banner ══════════

local announceQueue: { { Text: string, Color: Color3 } } = {}
local announcing = false

local function processAnnounceQueue()
	if announcing then
		return
	end
	announcing = true
	task.spawn(function()
		while #announceQueue > 0 do
			local item = table.remove(announceQueue, 1)
			announceLabel.Text = item.Text
			announceLabel.TextColor3 = item.Color
			announceLabel.Visible = true
			announceLabel.Position = UDim2.new(0.5, 0, 0, -60)
			TweenService:Create(announceLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
				Position = UDim2.new(0.5, 0, 0, 20),
			}):Play()
			task.wait(3.2)
			TweenService:Create(announceLabel, TweenInfo.new(0.3), {
				Position = UDim2.new(0.5, 0, 0, -60),
			}):Play()
			task.wait(0.35)
			announceLabel.Visible = false
		end
		announcing = false
	end)
end

function Ui.Announce(text: string, rarity: string?)
	table.insert(announceQueue, {
		Text = text,
		Color = rarity and SnackTypes.RarityColors[rarity] or Color3.new(1, 1, 1),
	})
	-- Queue nicht endlos wachsen lassen
	if #announceQueue > 4 then
		table.remove(announceQueue, 1)
	end
	processAnnounceQueue()
end

-- ══════════ Toasts ══════════

local toastCounter = 0

function Ui.Toast(text: string)
	local label = makeLabel(toastContainer, {
		Size = UDim2.new(1, 0, 0, 26),
		Text = text,
		TextTransparency = 0,
	})
	toastCounter += 1
	label.LayoutOrder = -toastCounter -- Neueste oben
	task.delay(3, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.5)
		label:Destroy()
	end)
end

-- ══════════ Shop ══════════

local function refreshShop()
	local stats = player:FindFirstChild("leaderstats")
	local rebirths = stats and (stats:FindFirstChild("Rebirths") :: IntValue?) and (stats:FindFirstChild("Rebirths") :: IntValue).Value or 0

	for name, row in upgradeRows do
		local def = Config.Upgrades[name]
		local level = player:GetAttribute(name) or 0
		row.Level.Text = ("%s  [Lv. %d/%d]"):format(def.Label, level, def.MaxLevel)
		if level >= def.MaxLevel then
			row.Button.Text = "MAX"
			row.Button.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
		else
			row.Button.Text = formatNumber(Config.UpgradeCost(name, level)) .. "💰"
			row.Button.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
		end
	end
	rebirthButton.Text = ("🌟 SUGAR RUSH! (%s💰)  – Reset für +%d%% Einkommen"):format(
		formatNumber(Config.RebirthCost(rebirths)),
		Config.RebirthBonus * 100
	)
end

local function buildShop()
	-- Kein Toggle-Button mehr: der Upgrade-Shop ist jetzt ein ORT auf der Map!
	shopFrame = makeWindow("🛒 UPGRADE-SHOP", Vector2.new(420, 360), Color3.fromRGB(255, 200, 80))
	shopWindows.Upgrade = shopFrame

	local list = Instance.new("Frame")
	list.Position = UDim2.new(0, 12, 0, 48)
	list.Size = UDim2.new(1, -24, 1, -120)
	list.BackgroundTransparency = 1
	list.Parent = shopFrame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local buyRemote = Remotes.Get("BuyUpgrade") :: RemoteFunction

	for _, name in Config.UpgradeOrder do
		local def = Config.Upgrades[name]
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		roundify(row, 10)
		row.Parent = list

		local levelLabel = makeLabel(row, {
			Position = UDim2.fromOffset(10, 2),
			Size = UDim2.new(1, -130, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Label,
		})
		makeLabel(row, {
			Position = UDim2.fromOffset(10, 26),
			Size = UDim2.new(1, -130, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Desc,
			TextColor3 = Color3.fromRGB(190, 190, 200),
		})

		local buyButton = Instance.new("TextButton")
		buyButton.AnchorPoint = Vector2.new(1, 0.5)
		buyButton.Position = UDim2.new(1, -8, 0.5, 0)
		buyButton.Size = UDim2.fromOffset(105, 36)
		buyButton.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
		buyButton.Font = FONT
		buyButton.TextScaled = true
		buyButton.TextColor3 = Color3.new(1, 1, 1)
		buyButton.Text = "..."
		roundify(buyButton, 10)
		buyButton.Parent = row

		buyButton.Activated:Connect(function()
			task.spawn(function()
				local ok, result = pcall(function()
					return buyRemote:InvokeServer(name)
				end)
				if ok and result then
					Ui.Toast((result.ok and "✅ " or "❌ ") .. result.msg)
				end
				refreshShop()
			end)
		end)

		upgradeRows[name] = { Level = levelLabel, Button = buyButton }
	end

	-- Rebirth-Button
	rebirthButton = Instance.new("TextButton")
	rebirthButton.AnchorPoint = Vector2.new(0.5, 1)
	rebirthButton.Position = UDim2.new(0.5, 0, 1, -12)
	rebirthButton.Size = UDim2.new(1, -24, 0, 48)
	rebirthButton.BackgroundColor3 = Color3.fromRGB(200, 70, 200)
	rebirthButton.Font = FONT
	rebirthButton.TextScaled = true
	rebirthButton.TextColor3 = Color3.new(1, 1, 1)
	rebirthButton.Text = "🌟 SUGAR RUSH!"
	roundify(rebirthButton, 12)
	rebirthButton.Parent = shopFrame

	local rebirthRemote = Remotes.Get("DoRebirth") :: RemoteFunction
	rebirthButton.Activated:Connect(function()
		task.spawn(function()
			local ok, result = pcall(function()
				return rebirthRemote:InvokeServer()
			end)
			if ok and result then
				Ui.Toast((result.ok and "🌟 " or "❌ ") .. result.msg)
			end
			refreshShop()
		end)
	end)

	-- Bei Level-/Rebirth-Änderungen aktualisieren
	player.AttributeChanged:Connect(function()
		if shopFrame.Visible then
			refreshShop()
		end
	end)
end

-- ══════════ Pet-Shop & Style-Shop ══════════
-- Beide zeigen Items aus Config (Pets/Trails) mit Kaufen/Ausrüsten-Buttons.
-- Besitz & Ausrüstung kommen per GetCollections vom Server (collectionsCache).

local function refreshCollectionShops()
	task.spawn(function()
		local ok, data = pcall(function()
			return (Remotes.Get("GetCollections") :: RemoteFunction):InvokeServer()
		end)
		if not ok or typeof(data) ~= "table" then
			return
		end
		collectionsCache = data

		for _, def in Config.Pets do
			local button = petRows[def.Id]
			if button then
				if data.EquippedPet == def.Id then
					button.Text = "✓ AKTIV"
					button.BackgroundColor3 = Color3.fromRGB(90, 120, 220)
				elseif data.Pets and data.Pets[def.Id] then
					button.Text = "AUSRÜSTEN"
					button.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
				else
					button.Text = formatNumber(def.Cost) .. "💰"
					button.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
				end
			end
		end
		for _, def in Config.Trails do
			local button = trailRows[def.Id]
			if button then
				if data.EquippedTrail == def.Id then
					button.Text = "✓ AKTIV"
					button.BackgroundColor3 = Color3.fromRGB(90, 120, 220)
				elseif data.Trails and data.Trails[def.Id] then
					button.Text = "AUSRÜSTEN"
					button.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
				else
					button.Text = formatNumber(def.Cost) .. "💰"
					button.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
				end
			end
		end
	end)
end

-- Generischer Item-Shop (Pets ODER Trails – gleiche Mechanik, andere Remotes)
local function buildCollectionShop(
	shopId: string,
	title: string,
	titleColor: Color3,
	items: { any },
	rows: { [string]: TextButton },
	buyRemoteName: string,
	equipRemoteName: string,
	ownedKey: string,
	equippedKey: string
)
	local frame = makeWindow(title, Vector2.new(440, 90 + #items * 62), titleColor)
	shopWindows[shopId] = frame

	local list = Instance.new("Frame")
	list.Position = UDim2.new(0, 12, 0, 48)
	list.Size = UDim2.new(1, -24, 1, -60)
	list.BackgroundTransparency = 1
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	for _, def in items do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 54)
		row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		roundify(row, 10)
		row.Parent = list

		makeLabel(row, {
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -140, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Name,
			TextColor3 = def.Color or Color3.new(1, 1, 1),
		})
		makeLabel(row, {
			Position = UDim2.fromOffset(10, 32),
			Size = UDim2.new(1, -140, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Desc or "",
			TextColor3 = Color3.fromRGB(190, 190, 200),
		})

		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.fromOffset(115, 38)
		button.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
		button.Font = FONT
		button.TextScaled = true
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = formatNumber(def.Cost) .. "💰"
		roundify(button, 10)
		button.Parent = row
		rows[def.Id] = button

		button.Activated:Connect(function()
			task.spawn(function()
				-- Aktion aus dem Cache ableiten: besitzen? ausgerüstet? sonst kaufen.
				local owned = collectionsCache[ownedKey] and collectionsCache[ownedKey][def.Id]
				local remoteName, arg
				if owned and collectionsCache[equippedKey] == def.Id then
					remoteName, arg = equipRemoteName, "" -- ablegen
				elseif owned then
					remoteName, arg = equipRemoteName, def.Id
				else
					remoteName, arg = buyRemoteName, def.Id
				end
				local ok, result = pcall(function()
					return (Remotes.Get(remoteName) :: RemoteFunction):InvokeServer(arg)
				end)
				if ok and result then
					Ui.Toast((result.ok and "✅ " or "❌ ") .. result.msg)
				end
				refreshCollectionShops()
			end)
		end)
	end
end

-- ══════════ Merge-Station ══════════
-- Zeigt den eigenen Tresor-Inhalt gruppiert; pro Snack-Sorte Buttons für
-- x2/x3/x5-Merges inkl. Erfolgschance. Validierung passiert auf dem Server!

local MERGE_COUNTS = { 2, 3, 5 }

local function refreshMerge()
	task.spawn(function()
		local ok, vault = pcall(function()
			return (Remotes.Get("GetVault") :: RemoteFunction):InvokeServer()
		end)
		if not ok or typeof(vault) ~= "table" then
			return
		end

		-- Nach Snack-Name gruppieren
		local counts: { [string]: number } = {}
		for _, name in vault do
			if typeof(name) == "string" then
				counts[name] = (counts[name] or 0) + 1
			end
		end
		local names = {}
		for name in counts do
			table.insert(names, name)
		end
		table.sort(names, function(a, b)
			local defA, defB = SnackTypes.ByName[a], SnackTypes.ByName[b]
			return (defA and defA.Income or 0) < (defB and defB.Income or 0)
		end)

		-- Liste neu aufbauen
		for _, child in mergeList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		if #names == 0 then
			local empty = Instance.new("Frame")
			empty.Size = UDim2.new(1, 0, 0, 40)
			empty.BackgroundTransparency = 1
			empty.Parent = mergeList
			makeLabel(empty, {
				Size = UDim2.fromScale(1, 1),
				Text = "🕸️ Dein Tresor ist leer – erst Snacks einlagern!",
				TextColor3 = Color3.fromRGB(190, 190, 200),
			})
			return
		end

		for _, name in names do
			local def = SnackTypes.ByName[name]
			local count = counts[name]
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 46)
			row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
			roundify(row, 10)
			row.Parent = mergeList

			makeLabel(row, {
				Position = UDim2.fromOffset(10, 2),
				Size = UDim2.new(0.45, -10, 1, -4),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = ("%s  x%d"):format(name, count),
				TextColor3 = (def and SnackTypes.RarityColors[def.Rarity]) or Color3.new(1, 1, 1),
			})

			local mergeable = def and SnackTypes.NextRarity(def.Rarity) ~= nil
			if not mergeable then
				makeLabel(row, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.new(0.5, 0, 0, 22),
					TextXAlignment = Enum.TextXAlignment.Right,
					Text = "MAX-Rarität 👑",
					TextColor3 = Color3.fromRGB(255, 215, 0),
				})
			else
				for slot, n in MERGE_COUNTS do
					if count >= n and n <= Config.MergeMaxCount then
						local button = Instance.new("TextButton")
						button.AnchorPoint = Vector2.new(1, 0.5)
						button.Position = UDim2.new(1, -8 - (#MERGE_COUNTS - slot) * 92, 0.5, 0)
						button.Size = UDim2.fromOffset(86, 34)
						button.BackgroundColor3 = Color3.fromRGB(150, 70, 220)
						button.Font = FONT
						button.TextScaled = true
						button.TextColor3 = Color3.new(1, 1, 1)
						button.Text = ("x%d · %d%%"):format(n, Config.MergeChance(n) * 100)
						roundify(button, 8)
						button.Parent = row

						button.Activated:Connect(function()
							task.spawn(function()
								local callOk, result = pcall(function()
									return (Remotes.Get("DoMerge") :: RemoteFunction):InvokeServer(name, n)
								end)
								if callOk and result then
									Ui.Toast((result.ok and (result.success and "🧪✨ " or "🧪💥 ") or "❌ ") .. result.msg)
								end
								refreshMerge()
							end)
						end)
					end
				end
			end
		end
	end)
end

local function buildMergeUi()
	local frame = makeWindow("🧪 MERGE-MASCHINE 3000", Vector2.new(480, 420), Color3.fromRGB(180, 120, 255))
	shopWindows.Merge = frame

	makeLabel(frame, {
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32, 0, 34),
		Text = "Gleiche Snacks mergen = Chance auf SELTENER!\n💥 Bei Misserfolg sind ALLE eingesetzten Snacks WEG!",
		TextColor3 = Color3.fromRGB(255, 160, 160),
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
	})

	mergeList = Instance.new("ScrollingFrame")
	mergeList.Position = UDim2.new(0, 12, 0, 84)
	mergeList.Size = UDim2.new(1, -24, 1, -96)
	mergeList.BackgroundTransparency = 1
	mergeList.BorderSizePixel = 0
	mergeList.ScrollBarThickness = 6
	mergeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mergeList.CanvasSize = UDim2.new()
	mergeList.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = mergeList
end

-- ══════════ Fenster öffnen (vom OpenShop-Remote getriggert) ══════════

function Ui.OpenShop(shopId: string)
	local frame = shopWindows[shopId]
	if not frame then
		return
	end
	for _, other in shopWindows do
		other.Visible = false -- immer nur ein Fenster offen
	end
	frame.Visible = true
	if shopId == "Upgrade" then
		refreshShop()
	elseif shopId == "Pets" or shopId == "Style" then
		refreshCollectionShops()
	elseif shopId == "Merge" then
		refreshMerge()
	end
end

-- ══════════ YEET-Ladebalken & Halte-Hinweis ══════════

local function buildChargeBar()
	chargeBarBg = Instance.new("Frame")
	chargeBarBg.AnchorPoint = Vector2.new(0.5, 1)
	chargeBarBg.Position = UDim2.new(0.5, 0, 1, -90)
	chargeBarBg.Size = UDim2.fromOffset(260, 22)
	chargeBarBg.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	chargeBarBg.Visible = false
	roundify(chargeBarBg, 10)
	chargeBarBg.Parent = gui

	-- Goldene Sweet-Spot-Zone: hier loslassen = PERFEKTER YEET
	local sweetZone = Instance.new("Frame")
	sweetZone.Position = UDim2.fromScale(Config.SweetSpotStart, 0)
	sweetZone.Size = UDim2.fromScale(1 - Config.SweetSpotStart, 1)
	sweetZone.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	sweetZone.BackgroundTransparency = 0.45
	sweetZone.ZIndex = 2
	roundify(sweetZone, 10)
	sweetZone.Parent = chargeBarBg

	chargeBarFill = Instance.new("Frame")
	chargeBarFill.Size = UDim2.fromScale(0, 1)
	chargeBarFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	chargeBarFill.ZIndex = 3
	roundify(chargeBarFill, 10)
	chargeBarFill.Parent = chargeBarBg

	holdHint = makeLabel(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -118),
		Size = UDim2.fromOffset(460, 28),
		Text = "",
		Visible = false,
		TextColor3 = Color3.fromRGB(255, 230, 130),
	})
end

function Ui.SetHoldHint(visible: boolean, snackName: string?)
	holdHint.Visible = visible
	if visible then
		holdHint.Text = ("🍫 %s – Klick HALTEN & loslassen zum YEETEN! (%ds Zeit!)"):format(
			snackName or "Snack",
			Config.HoldDuration
		)
	end
end

function Ui.ShowCharge()
	chargeBarBg.Visible = true
	chargeBarFill.Size = UDim2.fromScale(0, 1)
end

function Ui.HideCharge()
	chargeBarBg.Visible = false
end

function Ui.SetCharge(fraction: number)
	chargeBarFill.Size = UDim2.fromScale(fraction, 1)
	if fraction >= Config.SweetSpotStart then
		-- Im Sweet Spot: GOLD! Jetzt loslassen!
		chargeBarFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	else
		chargeBarFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60):Lerp(Color3.fromRGB(255, 70, 40), fraction)
	end
end

-- ══════════ Supreme-Truck-Fortschritt ══════════
-- Zeigt, wie viele Trucks es noch bis zum Mutanten-Express sind.
-- Datenquelle: Workspace-Attribute (setzt der TruckService, replizieren automatisch).

local function buildSupremeBar()
	local frame = Instance.new("Frame")
	frame.Name = "SupremeProgress"
	frame.Position = UDim2.new(0, 12, 0, 66) -- sitzt da, wo früher der Shop-Button war
	frame.Size = UDim2.fromOffset(190, 48)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BackgroundTransparency = 0.25
	roundify(frame, 12)
	frame.Parent = gui

	local label = makeLabel(frame, {
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 20),
		Text = "☢️ Supreme-Truck: ???",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 255, 90),
	})

	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0, 8, 0, 30)
	barBg.Size = UDim2.new(1, -16, 0, 10)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	roundify(barBg, 5)
	barBg.Parent = frame

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 255, 40)
	roundify(fill, 5)
	fill.Parent = barBg

	local function refresh()
		local left = workspace:GetAttribute("SupremeTrucksLeft")
		local target = workspace:GetAttribute("SupremeTrucksTarget")
		if typeof(left) ~= "number" or typeof(target) ~= "number" or target <= 0 then
			return
		end
		if left <= 0 then
			label.Text = "☢️ MUTANTEN-EXPRESS KOMMT!"
		else
			label.Text = ("☢️ Supreme-Truck: noch %d"):format(left)
		end
		fill.Size = UDim2.fromScale(math.clamp(1 - left / target, 0, 1), 1)
	end

	workspace:GetAttributeChangedSignal("SupremeTrucksLeft"):Connect(refresh)
	workspace:GetAttributeChangedSignal("SupremeTrucksTarget"):Connect(refresh)
	refresh()
end

-- ══════════ Hilfe-Panel ══════════

local function buildHelp()
	local toggle = Instance.new("TextButton")
	toggle.Name = "HelpToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 12)
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle.BackgroundColor3 = Color3.fromRGB(80, 120, 220)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "❓"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "HelpPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 330)
	panel.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
	panel.Visible = false
	roundify(panel, 16)
	panel.Parent = gui

	makeLabel(panel, {
		Size = UDim2.new(1, 0, 0, 40),
		Text = "❓ SO GEHT'S",
		TextColor3 = Color3.fromRGB(150, 200, 255),
	})

	local helpText = table.concat({
		"🚚 Der SCHOKO-TRUCK verliert alle 3 Min Snacks",
		"✋ [E] Snack aufheben – nur 4 Sek. haltbar!",
		"🖱️ Klick HALTEN & loslassen = YEET zur Basis",
		"🌟 Im GOLDENEN Bereich loslassen = Extra-Power!",
		"👋 [Q] SLAP! Träger verlieren ihren Snack...",
		"🏦 Tresor-Snacks = Cash/Sekunde",
		"🏪 Shops & Merge-Maschine sind ORTE am Plaza-Rand!",
		"🧪 Merge: 2+ gleiche Snacks = Chance auf seltener (RISIKO!)",
		"😈 Fremde Tresore kann man KNACKEN [E halten]",
		"🔥 Schnell nacheinander einlagern = COMBO-Bonus",
		"🌟 SUGAR RUSH (Rebirth) = +50% Einkommen für immer",
	}, "\n")

	local body = Instance.new("TextLabel")
	body.Position = UDim2.new(0, 16, 0, 48)
	body.Size = UDim2.new(1, -32, 1, -64)
	body.BackgroundTransparency = 1
	body.Font = FONT
	body.Text = helpText
	body.TextColor3 = Color3.new(1, 1, 1)
	body.TextSize = 19
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = panel

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

-- ══════════ Build ══════════

function Ui.Build()
	gui = Instance.new("ScreenGui")
	gui.Name = "YeetUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Banner
	announceLabel = makeLabel(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Size = UDim2.new(0.92, 0, 0, 44), -- skaliert auch auf Handys sauber
		Text = "",
		Visible = false,
	})

	-- Toast-Container
	toastContainer = Instance.new("Frame")
	toastContainer.AnchorPoint = Vector2.new(0.5, 1)
	toastContainer.Position = UDim2.new(0.5, 0, 1, -150)
	toastContainer.Size = UDim2.fromOffset(520, 120)
	toastContainer.BackgroundTransparency = 1
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Padding = UDim.new(0, 2)
	toastLayout.Parent = toastContainer
	toastContainer.Parent = gui

	buildCashDisplay()
	buildShop()
	buildCollectionShop(
		"Pets",
		"🐹 PET-SHOP",
		Color3.fromRGB(140, 230, 160),
		Config.Pets,
		petRows,
		"BuyPet",
		"EquipPet",
		"Pets",
		"EquippedPet"
	)
	buildCollectionShop(
		"Style",
		"✨ STYLE-SHOP",
		Color3.fromRGB(240, 140, 240),
		Config.Trails,
		trailRows,
		"BuyTrail",
		"EquipTrail",
		"Trails",
		"EquippedTrail"
	)
	buildMergeUi()
	buildSupremeBar()
	buildChargeBar()
	buildHelp()
end

return Ui
