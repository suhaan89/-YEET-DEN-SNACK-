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
local MarketplaceService = game:GetService("MarketplaceService")
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
local trailRows: { [string]: TextButton } = {}
local skinRows: { [string]: TextButton } = {}
local collectionsCache: any =
	{ Pets = {}, EquippedPets = {}, Trails = {}, EquippedTrail = "", Skins = {}, EquippedSkin = "" }

-- Pet-Shop (Eier + Inventar): wird nach jedem GetCollections neu aufgebaut
local refreshPetInventory: () -> () = function() end

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
	rebirthButton.Text = ("🌟 SUGAR RUSH! (%s💰) – Tresor fliegt RAUS, dafür +%d%% Einkommen & mehr Plätze!"):format(
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
-- Zeigen Items aus Config (Pets/Trails/Skins) mit Kaufen/Ausrüsten-Buttons.
-- Besitz & Ausrüstung kommen per GetCollections vom Server (collectionsCache).

-- Buttons einer Item-Liste anhand des Server-Stands einfärben/beschriften
local function refreshRows(items: { any }, rows: { [string]: TextButton }, ownedMap: any, equippedId: any)
	for _, def in items do
		local button = rows[def.Id]
		if button then
			if equippedId == def.Id then
				button.Text = "✓ AKTIV"
				button.BackgroundColor3 = Color3.fromRGB(90, 120, 220)
			elseif ownedMap and ownedMap[def.Id] then
				button.Text = "AUSRÜSTEN"
				button.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
			elseif def.Seasonal then
				-- Season-Items kann man nicht kaufen – nur über den Pass verdienen
				button.Text = "🎫 PASS"
				button.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
			else
				button.Text = formatNumber(def.Cost) .. "💰"
				button.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
			end
		end
	end
end

local function refreshCollectionShops()
	task.spawn(function()
		local ok, data = pcall(function()
			return (Remotes.Get("GetCollections") :: RemoteFunction):InvokeServer()
		end)
		if not ok or typeof(data) ~= "table" then
			return
		end
		collectionsCache = data
		refreshRows(Config.Trails, trailRows, data.Trails, data.EquippedTrail)
		refreshRows(Config.SeasonTrails, trailRows, data.Trails, data.EquippedTrail)
		refreshRows(Config.Skins, skinRows, data.Skins, data.EquippedSkin)
		refreshPetInventory()
	end)
end

-- Eine Sektion des Collection-Shops (z.B. "Trails" oder "Skins"):
-- Items + zugehörige Remotes + Schlüssel im collectionsCache
type ShopSection = {
	Header: string?,
	Items: { any },
	Rows: { [string]: TextButton },
	BuyRemote: string,
	EquipRemote: string,
	OwnedKey: string,
	EquippedKey: string,
}

-- Generischer Item-Shop mit beliebig vielen Sektionen (scrollbar)
local function buildCollectionShop(shopId: string, title: string, titleColor: Color3, sections: { ShopSection })
	-- Fensterhöhe aus dem Inhalt ableiten, aber auf Bildschirm-tauglich deckeln
	local contentHeight = 0
	for _, section in sections do
		contentHeight += (section.Header and 34 or 0) + #section.Items * 62
	end
	local frame = makeWindow(title, Vector2.new(440, math.min(96 + contentHeight, 540)), titleColor)
	shopWindows[shopId] = frame

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 48)
	list.Size = UDim2.new(1, -24, 1, -60)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local order = 0
	for _, section in sections do
		if section.Header then
			order += 1
			local header = makeLabel(list, {
				Size = UDim2.new(1, -8, 0, 26),
				Text = section.Header,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = titleColor,
			})
			header.LayoutOrder = order
		end

		for _, def in section.Items do
			order += 1
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 54)
			row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
			row.LayoutOrder = order
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
			-- Season-Items haben keinen Preis (gibt's nur über den Pass)
			button.Text = if def.Seasonal then "🎫 PASS" else formatNumber(def.Cost) .. "💰"
			roundify(button, 10)
			button.Parent = row
			section.Rows[def.Id] = button

			button.Activated:Connect(function()
				task.spawn(function()
					-- Aktion aus dem Cache ableiten: besitzen? ausgerüstet? sonst kaufen.
					local owned = collectionsCache[section.OwnedKey] and collectionsCache[section.OwnedKey][def.Id]
					local remoteName, arg
					if owned and collectionsCache[section.EquippedKey] == def.Id then
						remoteName, arg = section.EquipRemote, "" -- ablegen
					elseif owned then
						remoteName, arg = section.EquipRemote, def.Id
					else
						remoteName, arg = section.BuyRemote, def.Id
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
end

-- ══════════ Pet-Shop: Eier kaufen + Pet-Inventar ══════════
-- Kein Direktkauf mehr! Eier öffnen -> Server würfelt -> Reveal-Animation.

local function rarityHex(rarity: string): string
	local c = SnackTypes.RarityColors[rarity] or Color3.new(1, 1, 1)
	-- %X verlangt Integer, Color3-Kanäle sind Floats -> runden!
	return string.format("#%02X%02X%02X", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

-- Drop-Chancen eines Eis als bunte RichText-Zeile (gleiche Formel wie der Server!)
local function eggChanceText(eggId: string): string
	local percents = Config.EggChancePercents(eggId)
	local parts = {}
	for _, rarity in Config.PetRarityOrder do
		local p = percents[rarity]
		if p and p > 0 then
			table.insert(parts, ('<font color="%s">%s %s%%</font>'):format(rarityHex(rarity), rarity, string.format("%.4g", p)))
		end
	end
	return table.concat(parts, "  ")
end

-- Ei-Reveal: Ei wackelt, platzt, Pet poppt in Raritäts-Farbe auf
local function playEggReveal(result: any)
	local overlay = Instance.new("TextButton") -- Button = wegklickbar
	overlay.Name = "EggReveal"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.ZIndex = 20
	overlay.Parent = gui

	local egg = makeLabel(overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(150, 150),
		Text = "🥚",
		ZIndex = 21,
	})

	local dismissed = false
	overlay.Activated:Connect(function()
		dismissed = true
		overlay:Destroy()
	end)

	task.spawn(function()
		-- Wackeln (immer hektischer)
		for i = 1, 7 do
			if not overlay.Parent then
				return
			end
			local tween = TweenService:Create(
				egg,
				TweenInfo.new(0.24 - i * 0.02, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Rotation = if i % 2 == 0 then 20 else -20 }
			)
			tween:Play()
			tween.Completed:Wait()
		end
		if dismissed or not overlay.Parent then
			return
		end

		-- PLATZ!
		egg.Rotation = 0
		egg.Text = "💥"
		task.wait(0.18)
		if dismissed or not overlay.Parent then
			return
		end
		egg.Visible = false

		local pet = result.Pet
		local color = SnackTypes.RarityColors[pet.Rarity] or Color3.new(1, 1, 1)

		local nameLabel = makeLabel(overlay, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(10, 10), -- startet winzig, poppt groß
			Text = pet.Name,
			TextColor3 = color,
			ZIndex = 21,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 2
		stroke.Transparency = 0.4
		stroke.Parent = nameLabel
		TweenService:Create(nameLabel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(520, 64),
		}):Play()

		makeLabel(overlay, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.53),
			Size = UDim2.fromOffset(420, 30),
			Text = ("⭐ %s ⭐"):format(pet.Rarity),
			TextColor3 = color,
			ZIndex = 21,
		})
		makeLabel(overlay, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.62),
			Size = UDim2.fromOffset(520, 26),
			Text = if result.Duplicate
				then ("😅 Schon im Team! Dafür: +%d💰"):format(result.Refund or 0)
				else pet.Desc or "",
			TextColor3 = Color3.fromRGB(230, 230, 240),
			ZIndex = 21,
		})

		task.wait(2.6)
		if overlay.Parent then
			overlay:Destroy()
		end
	end)
end

local function buildPetShop()
	local frame = makeWindow("🥚 PET-SHOP", Vector2.new(470, 540), Color3.fromRGB(140, 230, 160))
	shopWindows.Pets = frame

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 48)
	list.Size = UDim2.new(1, -24, 1, -60)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- ── Sektion 1: Eier ──
	local eggHeader = makeLabel(list, {
		Size = UDim2.new(1, -8, 0, 26),
		Text = "🥚 EIER ÖFFNEN",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 120),
	})
	eggHeader.LayoutOrder = 1

	local buying = false -- Doppelklick-Schutz (Server validiert eh, das hier ist nur UX)
	for i, eggDef in Config.Eggs do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 66)
		row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		row.LayoutOrder = 1 + i
		roundify(row, 10)
		row.Parent = list

		makeLabel(row, {
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -140, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = eggDef.Name,
			TextColor3 = eggDef.Color,
		})
		makeLabel(row, {
			Position = UDim2.fromOffset(10, 28),
			Size = UDim2.new(1, -140, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = eggDef.Desc,
			TextColor3 = Color3.fromRGB(190, 190, 200),
			TextScaled = false,
			TextSize = 13,
		})
		local chanceLabel = makeLabel(row, {
			Position = UDim2.fromOffset(10, 46),
			Size = UDim2.new(1, -140, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = eggChanceText(eggDef.Id),
			TextScaled = false,
			TextSize = 13,
		})
		chanceLabel.RichText = true

		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.fromOffset(115, 44)
		button.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
		button.Font = FONT
		button.TextScaled = true
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = formatNumber(eggDef.Cost) .. "💰"
		roundify(button, 10)
		button.Parent = row

		button.Activated:Connect(function()
			if buying then
				return
			end
			buying = true
			task.spawn(function()
				local ok, result = pcall(function()
					return (Remotes.Get("BuyEgg") :: RemoteFunction):InvokeServer(eggDef.Id)
				end)
				buying = false
				if not ok or typeof(result) ~= "table" then
					return
				end
				if result.ok and result.Pet then
					playEggReveal(result)
					Ui.Toast("🥚 " .. result.msg)
				else
					Ui.Toast("❌ " .. result.msg)
				end
				refreshCollectionShops()
			end)
		end)
	end

	-- ── Sektion 2: Pet-Inventar ──
	local invHeader = makeLabel(list, {
		Size = UDim2.new(1, -8, 0, 26),
		Text = "🎒 DEINE PETS",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(140, 230, 160),
	})
	invHeader.LayoutOrder = 100

	local invContainer = Instance.new("Frame")
	invContainer.Size = UDim2.new(1, -8, 0, 0)
	invContainer.AutomaticSize = Enum.AutomaticSize.Y
	invContainer.BackgroundTransparency = 1
	invContainer.LayoutOrder = 101
	invContainer.Parent = list
	local invLayout = Instance.new("UIListLayout")
	invLayout.Padding = UDim.new(0, 6)
	invLayout.SortOrder = Enum.SortOrder.LayoutOrder
	invLayout.Parent = invContainer

	-- Inventar aus dem collectionsCache neu aufbauen (nach jedem GetCollections)
	refreshPetInventory = function()
		local equipped: { string } = collectionsCache.EquippedPets or {}
		invHeader.Text = ("🎒 DEINE PETS (%d/%d ausgerüstet)"):format(#equipped, Config.PetMaxEquipped)

		for _, child in invContainer:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		-- Nach Rarität gruppiert (Config-Reihenfolge ist schon gruppiert)
		local order = 0
		for _, def in Config.EggPets do
			order += 1
			local owned = collectionsCache.Pets and collectionsCache.Pets[def.Id] == true
			local isEquipped = table.find(equipped, def.Id) ~= nil

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 54)
			row.BackgroundColor3 = if owned then Color3.fromRGB(55, 48, 70) else Color3.fromRGB(40, 36, 50)
			row.LayoutOrder = order
			roundify(row, 10)
			row.Parent = invContainer

			makeLabel(row, {
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -140, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = if owned then def.Name else "❓ ???",
				TextColor3 = SnackTypes.RarityColors[def.Rarity] or Color3.new(1, 1, 1),
				TextTransparency = if owned then 0 else 0.4,
			})
			makeLabel(row, {
				Position = UDim2.fromOffset(10, 32),
				Size = UDim2.new(1, -140, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = if owned
					then ("%s · %s"):format(def.Rarity, def.Desc)
					elseif def.Exclusive then "🎫 Exklusiv aus dem Season-Pass!"
					else ("%s · Noch nicht aus einem Ei geschlüpft..."):format(def.Rarity),
				TextColor3 = Color3.fromRGB(190, 190, 200),
				TextScaled = false,
				TextSize = 13,
			})

			if owned then
				local button = Instance.new("TextButton")
				button.AnchorPoint = Vector2.new(1, 0.5)
				button.Position = UDim2.new(1, -8, 0.5, 0)
				button.Size = UDim2.fromOffset(115, 38)
				button.Font = FONT
				button.TextScaled = true
				button.TextColor3 = Color3.new(1, 1, 1)
				if isEquipped then
					button.Text = "✓ AKTIV"
					button.BackgroundColor3 = Color3.fromRGB(90, 120, 220)
				else
					button.Text = "AUSRÜSTEN"
					button.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
				end
				roundify(button, 10)
				button.Parent = row

				button.Activated:Connect(function()
					task.spawn(function()
						local ok, result = pcall(function()
							return (Remotes.Get("EquipPet") :: RemoteFunction):InvokeServer(def.Id)
						end)
						if ok and result then
							Ui.Toast((result.ok and "🐾 " or "❌ ") .. result.msg)
						end
						refreshCollectionShops()
					end)
				end)
			end
		end
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

-- Sweet-Spot-Start inkl. Pet-Bonus (SweetSpot-Pets machen die Zone breiter;
-- das Attribut setzt der Server, wir zeigen es nur an)
local function effectiveSweetSpotStart(): number
	local start = Config.SweetSpotStart
	local petSweet = player:GetAttribute("PetSweetSpotBonus")
	if typeof(petSweet) == "number" then
		start -= petSweet
	end
	return start
end

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
	-- (wächst live mit, wenn ein SweetSpot-Pet ausgerüstet wird)
	local sweetZone = Instance.new("Frame")
	sweetZone.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	sweetZone.BackgroundTransparency = 0.45
	sweetZone.ZIndex = 2
	roundify(sweetZone, 10)
	sweetZone.Parent = chargeBarBg
	local function refreshSweetZone()
		local start = effectiveSweetSpotStart()
		sweetZone.Position = UDim2.fromScale(start, 0)
		sweetZone.Size = UDim2.fromScale(1 - start, 1)
	end
	player:GetAttributeChangedSignal("PetSweetSpotBonus"):Connect(refreshSweetZone)
	refreshSweetZone()

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
	if fraction >= effectiveSweetSpotStart() then
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

-- ══════════ Freundes-Bonus-Anzeige ══════════
-- Kleines Badge unter der Supreme-Leiste, sichtbar solange mind. ein
-- Roblox-Freund im Server ist (Attribut "FriendBonusCount" vom Server).

local function buildFriendBonus()
	local frame = Instance.new("Frame")
	frame.Name = "FriendBonus"
	frame.Position = UDim2.new(0, 12, 0, 120)
	frame.Size = UDim2.fromOffset(190, 34)
	frame.BackgroundColor3 = Color3.fromRGB(30, 45, 35)
	frame.BackgroundTransparency = 0.2
	frame.Visible = false
	roundify(frame, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 220, 130)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame
	frame.Parent = gui

	local label = makeLabel(frame, {
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		Text = "",
		TextColor3 = Color3.fromRGB(140, 240, 170),
	})

	local function refresh()
		local count = player:GetAttribute("FriendBonusCount")
		if typeof(count) == "number" and count > 0 then
			frame.Visible = true
			label.Text = ("🤝 Freundes-Bonus: +%d%%"):format(Config.FriendBonusPercent * 100)
		else
			frame.Visible = false
		end
	end
	player:GetAttributeChangedSignal("FriendBonusCount"):Connect(refresh)
	refresh()
end

-- ══════════ Debug-Menü (nur Entwickler) ══════════
-- Erscheint nur, wenn der Server das "IsDev"-Attribut setzt (Studio/Whitelist).
-- Die Buttons kommen komplett vom Server (DebugCommand "list") – neue Commands
-- im DebugService tauchen hier also automatisch auf, ohne UI-Änderung.

local debugBuilt = false

local function buildDebugMenu()
	if debugBuilt then
		return
	end
	debugBuilt = true

	local debugRemote = Remotes.Get("DebugCommand") :: RemoteFunction

	local toggle = Instance.new("TextButton")
	toggle.Name = "DebugToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 12, 1, -12)
	toggle.Size = UDim2.fromOffset(110, 40)
	toggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "🐞 DEBUG"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local panel = makeWindow("🐞 DEBUG-MENÜ", Vector2.new(320, 140), Color3.fromRGB(255, 120, 120))

	local list = Instance.new("Frame")
	list.Position = UDim2.new(0, 12, 0, 48)
	list.Size = UDim2.new(1, -24, 1, -60)
	list.BackgroundTransparency = 1
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	-- Buttons vom Server generieren lassen
	task.spawn(function()
		local ok, commands = pcall(function()
			return debugRemote:InvokeServer("list")
		end)
		if not ok or typeof(commands) ~= "table" then
			return
		end
		panel.Size = UDim2.fromOffset(320, 72 + #commands * 46)
		for _, cmd in commands do
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, 0, 0, 40)
			button.BackgroundColor3 = Color3.fromRGB(70, 60, 90)
			button.Font = FONT
			button.TextScaled = true
			button.Text = cmd.Label
			button.TextColor3 = Color3.new(1, 1, 1)
			roundify(button, 10)
			button.Parent = list

			button.Activated:Connect(function()
				task.spawn(function()
					local callOk, result = pcall(function()
						return debugRemote:InvokeServer(cmd.Id)
					end)
					if callOk and typeof(result) == "table" then
						Ui.Toast((result.ok and "🐞 " or "❌ ") .. result.msg)
					end
				end)
			end)
		end
	end)

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

-- ══════════ Season-Pass ══════════
-- Alles rein anzeigend: XP/Stufe/Premium kommen als Player-Attribute vom
-- Server (SeasonXp/SeasonLevel/SeasonPremium), Belohnungen stehen in Config.

local seasonTrailsById: { [string]: any } = {}
for _, def in Config.SeasonTrails do
	seasonTrailsById[def.Id] = def
end

-- Anzeigetext einer Pass-Belohnung
local function rewardText(reward: any): string
	if not reward then
		return "–"
	end
	if reward.Type == "Cash" then
		return "💰 " .. formatNumber(reward.Amount)
	elseif reward.Type == "Egg" then
		local def = Config.EggsById[reward.Egg]
		return def and def.Name or "🥚 Ei"
	elseif reward.Type == "Trail" then
		local def = seasonTrailsById[reward.Trail]
		return def and def.Name or "🌀 Trail"
	elseif reward.Type == "Pet" then
		local def = Config.EggPetsById[reward.Pet]
		return def and def.Name or "🐾 Pet"
	end
	return "???"
end

-- Kurzes Popup beim Stufenaufstieg
local function showPassLevelUp(level: number)
	local rewards = Config.SeasonPass.Rewards[level]
	local premium = player:GetAttribute("SeasonPremium") == true

	local popup = Instance.new("Frame")
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, -110)
	popup.Size = UDim2.fromOffset(380, 92)
	popup.BackgroundColor3 = Color3.fromRGB(60, 40, 90)
	popup.ZIndex = 15
	roundify(popup, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 0)
	stroke.Thickness = 2
	stroke.Parent = popup
	popup.Parent = gui

	makeLabel(popup, {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 34),
		Text = ("🎉 PASS-STUFE %d!"):format(level),
		TextColor3 = Color3.fromRGB(255, 215, 0),
		ZIndex = 16,
	})
	local lines = {}
	if rewards and rewards.Free then
		table.insert(lines, "🎁 " .. rewardText(rewards.Free))
	end
	if rewards and rewards.Premium then
		table.insert(lines, (premium and "👑 " or "🔒 ") .. rewardText(rewards.Premium))
	end
	makeLabel(popup, {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 36),
		Text = table.concat(lines, "   "),
		TextColor3 = Color3.fromRGB(230, 225, 245),
		ZIndex = 16,
	})

	TweenService:Create(popup, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0, 80),
	}):Play()
	task.delay(3.2, function()
		local out = TweenService:Create(popup, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -110) })
		out:Play()
		out.Completed:Wait()
		popup:Destroy()
	end)
end

local function buildSeasonPass()
	-- Button rechts oben, unter dem Hilfe-Knopf
	local toggle = Instance.new("TextButton")
	toggle.Name = "PassToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 64)
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle.BackgroundColor3 = Color3.fromRGB(200, 140, 40)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "🎫"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local frame = makeWindow(Config.SeasonPass.Name, Vector2.new(540, 560), Color3.fromRGB(255, 200, 80))

	-- Countdown + Stufen-Anzeige
	local countdownLabel = makeLabel(frame, {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 22),
		Text = "",
		TextColor3 = Color3.fromRGB(190, 190, 200),
		TextScaled = false,
		TextSize = 15,
	})
	local levelLabel = makeLabel(frame, {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(0.5, -16, 0, 26),
		Text = "Stufe 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 215, 0),
	})
	local xpLabel = makeLabel(frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 64),
		Size = UDim2.new(0.5, -16, 0, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(190, 190, 200),
	})

	-- XP-Fortschrittsbalken
	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0, 16, 0, 94)
	barBg.Size = UDim2.new(1, -32, 0, 14)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	roundify(barBg, 7)
	barBg.Parent = frame
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	roundify(barFill, 7)
	barFill.Parent = barBg

	-- Spalten-Überschriften
	makeLabel(frame, {
		Position = UDim2.new(0, 76, 0, 112),
		Size = UDim2.new(0.5, -84, 0, 20),
		Text = "🎁 FREE",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(140, 230, 160),
		TextScaled = false,
		TextSize = 15,
	})
	makeLabel(frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 112),
		Size = UDim2.new(0.5, -84, 0, 20),
		Text = "👑 PREMIUM",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 200, 80),
		TextScaled = false,
		TextSize = 15,
	})

	-- Stufen-Liste
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 134)
	list.Size = UDim2.new(1, -24, 1, -134 - 64)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Pro Stufe eine Zeile mit Free-/Premium-Belohnung nebeneinander
	local rows: { { Row: Frame, Level: TextLabel, Free: TextLabel, Premium: TextLabel } } = {}
	for level = 1, Config.SeasonPass.LevelCount do
		local rewards = Config.SeasonPass.Rewards[level]
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 40)
		row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		row.LayoutOrder = level
		roundify(row, 8)
		row.Parent = list

		local levelText = makeLabel(row, {
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.fromOffset(52, 32),
			Text = tostring(level),
			TextColor3 = Color3.fromRGB(190, 190, 200),
		})
		local freeText = makeLabel(row, {
			Position = UDim2.new(0, 64, 0, 4),
			Size = UDim2.new(0.5, -72, 1, -8),
			Text = rewardText(rewards and rewards.Free),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = false,
			TextSize = 15,
		})
		local premiumText = makeLabel(row, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			Size = UDim2.new(0.5, -72, 1, -8),
			Text = rewardText(rewards and rewards.Premium),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = false,
			TextSize = 15,
		})
		rows[level] = { Row = row, Level = levelText, Free = freeText, Premium = premiumText }
	end

	-- Premium-Kauf-Button
	local buyButton = Instance.new("TextButton")
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.Position = UDim2.new(0.5, 0, 1, -12)
	buyButton.Size = UDim2.new(1, -24, 0, 44)
	buyButton.BackgroundColor3 = Color3.fromRGB(200, 140, 40)
	buyButton.Font = FONT
	buyButton.TextScaled = true
	buyButton.TextColor3 = Color3.new(1, 1, 1)
	buyButton.Text = "👑 PREMIUM-PASS HOLEN (Robux) – bessere Belohnungen auf JEDER Stufe!"
	roundify(buyButton, 12)
	buyButton.Parent = frame

	buyButton.Activated:Connect(function()
		if Config.SeasonPass.GamepassId <= 0 then
			Ui.Toast("⚠️ Premium-Pass kommt bald! (Gamepass noch nicht eingerichtet)")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, Config.SeasonPass.GamepassId)
	end)

	local function refreshPass()
		local xp = player:GetAttribute("SeasonXp")
		local level, into, need = Config.SeasonProgress(if typeof(xp) == "number" then xp else 0)
		local premium = player:GetAttribute("SeasonPremium") == true

		levelLabel.Text = ("🎫 Stufe %d/%d"):format(level, Config.SeasonPass.LevelCount)
		if need > 0 then
			xpLabel.Text = ("%d / %d XP"):format(into, need)
			barFill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1)
		else
			xpLabel.Text = "MAX! 👑"
			barFill.Size = UDim2.fromScale(1, 1)
		end

		local now = os.time()
		if now < Config.SeasonPass.StartTime then
			countdownLabel.Text = "⏳ Die Season hat noch nicht angefangen!"
		elseif now > Config.SeasonPass.EndTime then
			countdownLabel.Text = "🏁 Season beendet – danke fürs Mitspielen!"
		else
			local left = Config.SeasonPass.EndTime - now
			countdownLabel.Text = ("⏳ Season endet in %d Tagen, %d Stunden – XP gibt's fürs Einlagern, Yeeten, Mergen & Co."):format(
				math.floor(left / 86400),
				math.floor(left % 86400 / 3600)
			)
		end

		for lvl, refs in rows do
			local freeDone = lvl <= level
			local premiumDone = freeDone and premium
			refs.Row.BackgroundColor3 = if freeDone then Color3.fromRGB(45, 70, 50) else Color3.fromRGB(55, 48, 70)
			refs.Level.TextColor3 = if freeDone then Color3.fromRGB(140, 230, 160) else Color3.fromRGB(190, 190, 200)
			refs.Free.Text = (if freeDone then "✅ " else "") .. rewardText(Config.SeasonPass.Rewards[lvl] and Config.SeasonPass.Rewards[lvl].Free)
			refs.Free.TextColor3 = if freeDone then Color3.fromRGB(160, 240, 180) else Color3.new(1, 1, 1)
			refs.Premium.Text = (if premiumDone then "✅ " elseif premium then "" else "🔒 ")
				.. rewardText(Config.SeasonPass.Rewards[lvl] and Config.SeasonPass.Rewards[lvl].Premium)
			refs.Premium.TextColor3 = if premiumDone
				then Color3.fromRGB(255, 220, 120)
				elseif premium then Color3.new(1, 1, 1)
				else Color3.fromRGB(150, 145, 165)
		end

		buyButton.Visible = not premium
	end

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		if frame.Visible then
			refreshPass()
		end
	end)

	-- Live nachziehen, wenn der Server XP/Stufe/Premium ändert
	local lastLevel: number? = nil
	local function onLevelChanged()
		local level = player:GetAttribute("SeasonLevel")
		if typeof(level) ~= "number" then
			return
		end
		if lastLevel ~= nil and level > lastLevel then
			showPassLevelUp(level)
		end
		lastLevel = level
	end
	player:GetAttributeChangedSignal("SeasonLevel"):Connect(function()
		onLevelChanged()
		if frame.Visible then
			refreshPass()
		end
	end)
	player:GetAttributeChangedSignal("SeasonXp"):Connect(function()
		if frame.Visible then
			refreshPass()
		end
	end)
	player:GetAttributeChangedSignal("SeasonPremium"):Connect(function()
		if frame.Visible then
			refreshPass()
		end
	end)
	-- Join-Stand übernehmen, OHNE dafür ein Popup zu feuern
	local joinLevel = player:GetAttribute("SeasonLevel")
	if typeof(joinLevel) == "number" then
		lastLevel = joinLevel
	end
	refreshPass()
end

-- ══════════ Achievements ══════════
-- Popup beim Freischalten (kommt vom AchievementUnlocked-Remote) + Trophäen-
-- Fenster mit allen Meilensteinen. Freigeschaltet-Status via GetAchievements.

local achievementQueue: { { Name: string, Desc: string } } = {}
local achievementShowing = false

local function processAchievementQueue()
	if achievementShowing then
		return
	end
	achievementShowing = true
	task.spawn(function()
		while #achievementQueue > 0 do
			local item = table.remove(achievementQueue, 1)

			local popup = Instance.new("Frame")
			popup.AnchorPoint = Vector2.new(0.5, 0)
			popup.Position = UDim2.new(0.5, 0, 0, -110)
			popup.Size = UDim2.fromOffset(400, 88)
			popup.BackgroundColor3 = Color3.fromRGB(45, 40, 25)
			popup.ZIndex = 15
			roundify(popup, 14)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 215, 0)
			stroke.Thickness = 2
			stroke.Parent = popup
			popup.Parent = gui

			makeLabel(popup, {
				Position = UDim2.fromOffset(0, 6),
				Size = UDim2.new(1, 0, 0, 24),
				Text = "🏆 ACHIEVEMENT FREIGESCHALTET!",
				TextColor3 = Color3.fromRGB(255, 215, 0),
				ZIndex = 16,
			})
			makeLabel(popup, {
				Position = UDim2.fromOffset(0, 32),
				Size = UDim2.new(1, 0, 0, 28),
				Text = item.Name,
				TextColor3 = Color3.new(1, 1, 1),
				ZIndex = 16,
			})
			makeLabel(popup, {
				Position = UDim2.fromOffset(0, 60),
				Size = UDim2.new(1, -16, 0, 22),
				Text = item.Desc,
				TextColor3 = Color3.fromRGB(210, 205, 190),
				TextScaled = false,
				TextSize = 14,
				ZIndex = 16,
			})

			-- Unterhalb des Announce-Banners einschweben, kurz zeigen, weg
			TweenService:Create(popup, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
				Position = UDim2.new(0.5, 0, 0, 176),
			}):Play()
			task.wait(3.4)
			local out = TweenService:Create(popup, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -110) })
			out:Play()
			out.Completed:Wait()
			popup:Destroy()
		end
		achievementShowing = false
	end)
end

function Ui.AchievementPopup(name: string, desc: string)
	table.insert(achievementQueue, { Name = name, Desc = desc })
	processAchievementQueue()
end

local function buildAchievements()
	-- Button rechts, unter dem Season-Pass-Knopf
	local toggle = Instance.new("TextButton")
	toggle.Name = "AchievementToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 116)
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle.BackgroundColor3 = Color3.fromRGB(180, 150, 40)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "🏆"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local frame = makeWindow("🏆 ACHIEVEMENTS", Vector2.new(470, 500), Color3.fromRGB(255, 215, 0))

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 48)
	list.Size = UDim2.new(1, -24, 1, -60)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Eine Zeile pro Meilenstein; refresh() färbt anhand des Server-Stands
	local rows: { [string]: { Row: Frame, Name: TextLabel, Desc: TextLabel } } = {}
	for i, def in Config.Achievements do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 52)
		row.BackgroundColor3 = Color3.fromRGB(40, 36, 50)
		row.LayoutOrder = i
		roundify(row, 10)
		row.Parent = list

		local nameLabel = makeLabel(row, {
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -20, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "🔒 " .. def.Name,
			TextColor3 = Color3.fromRGB(150, 145, 165),
		})
		local descLabel = makeLabel(row, {
			Position = UDim2.fromOffset(10, 32),
			Size = UDim2.new(1, -20, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Desc,
			TextColor3 = Color3.fromRGB(190, 190, 200),
			TextScaled = false,
			TextSize = 13,
		})
		rows[def.Id] = { Row = row, Name = nameLabel, Desc = descLabel }
	end

	local function refresh()
		task.spawn(function()
			local ok, unlocked = pcall(function()
				return (Remotes.Get("GetAchievements") :: RemoteFunction):InvokeServer()
			end)
			if not ok or typeof(unlocked) ~= "table" then
				return
			end
			local count = 0
			for _, def in Config.Achievements do
				local refs = rows[def.Id]
				if unlocked[def.Id] then
					count += 1
					refs.Row.BackgroundColor3 = Color3.fromRGB(55, 60, 40)
					refs.Name.Text = "✅ " .. def.Name
					refs.Name.TextColor3 = Color3.fromRGB(255, 215, 0)
				else
					refs.Row.BackgroundColor3 = Color3.fromRGB(40, 36, 50)
					refs.Name.Text = "🔒 " .. def.Name
					refs.Name.TextColor3 = Color3.fromRGB(150, 145, 165)
				end
			end
			toggle.Text = count >= #Config.Achievements and "👑" or "🏆"
		end)
	end

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		if frame.Visible then
			refresh()
		end
	end)
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
		"🏠 Zuerst: FREIE BASIS suchen & [E] am Tresor drücken!",
		"🚚 Der SCHOKO-TRUCK verliert alle 3 Min Snacks",
		"✋ [E] Snack aufheben – nur 4 Sek. haltbar!",
		"🖱️ Klick HALTEN & loslassen = YEET zur Basis",
		"🌟 Im GOLDENEN Bereich loslassen = Extra-Power!",
		"👋 [Q] SLAP! Träger verlieren ihren Snack...",
		"🏦 Tresor-Snacks = Cash/Sekunde – aber die PLÄTZE sind begrenzt!",
		"🗑️ [R] am eigenen Tresor = billigsten Snack rauswerfen",
		"⬆️ GRÜNES PAD an deiner Basis = Tycoon-AUSBAU (Plätze + Einkommen!)",
		"🧍 Skins & Trails gibt's im STYLE-SHOP",
		"🥚 PET-SHOP: Eier öffnen! Bis zu 3 Pets = Boosts (Cash, Yeet, Tempo...)",
		"🎫 SEASON-PASS (Button rechts): XP durchs Spielen = Belohnungen!",
		"🏪 Shops & Merge-Maschine sind ORTE am Plaza-Rand!",
		"🧪 Merge: 2+ gleiche Snacks = Chance auf seltener (RISIKO!)",
		"😈 Fremde Tresore kann man KNACKEN [E halten]",
		"🔥 Schnell nacheinander einlagern = COMBO-Bonus",
		"🌟 SUGAR RUSH: Tresor springt AUF (Snacks für alle!), dafür +50% Einkommen & mehr Plätze!",
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
	buildPetShop()
	buildCollectionShop("Style", "✨ STYLE-SHOP", Color3.fromRGB(240, 140, 240), {
		{
			Header = "🌀 TRAILS",
			Items = Config.Trails,
			Rows = trailRows,
			BuyRemote = "BuyTrail",
			EquipRemote = "EquipTrail",
			OwnedKey = "Trails",
			EquippedKey = "EquippedTrail",
		},
		{
			Header = "🎫 SEASON-TRAILS",
			Items = Config.SeasonTrails,
			Rows = trailRows, -- Ids sind eindeutig, gleiche Map wie normale Trails
			BuyRemote = "BuyTrail", -- Server lehnt Season-Käufe eh ab (Seasonal-Check)
			EquipRemote = "EquipTrail",
			OwnedKey = "Trails",
			EquippedKey = "EquippedTrail",
		},
		{
			Header = "🧍 SKINS",
			Items = Config.Skins,
			Rows = skinRows,
			BuyRemote = "BuySkin",
			EquipRemote = "EquipSkin",
			OwnedKey = "Skins",
			EquippedKey = "EquippedSkin",
		},
	})
	buildMergeUi()
	buildSupremeBar()
	buildFriendBonus()
	buildChargeBar()
	buildSeasonPass()
	buildAchievements()
	buildHelp()

	-- Debug-Menü nur zeigen, wenn der Server uns als Entwickler markiert
	if player:GetAttribute("IsDev") then
		buildDebugMenu()
	else
		player:GetAttributeChangedSignal("IsDev"):Connect(function()
			if player:GetAttribute("IsDev") then
				buildDebugMenu()
			end
		end)
	end
end

return Ui
