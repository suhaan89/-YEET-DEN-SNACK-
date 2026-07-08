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
local RunService = game:GetService("RunService")
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

-- ══════════ Juwelen-Anzeige (💎 gibt's NUR im Parkour) ══════════

local function buildGemDisplay()
	local frame = Instance.new("Frame")
	frame.Name = "GemDisplay"
	frame.Position = UDim2.new(0, 12, 0, 62)
	frame.Size = UDim2.fromOffset(190, 36)
	frame.BackgroundColor3 = Color3.fromRGB(20, 40, 55)
	frame.BackgroundTransparency = 0.25
	roundify(frame, 12)
	local label = makeLabel(frame, {
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = "💎 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 230, 255),
	})
	frame.Parent = gui

	-- Juwelen live aus den Leaderstats spiegeln (Zeile hängt der GemService an)
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats", 20)
		local gems = stats and stats:WaitForChild("Juwelen", 30) :: IntValue?
		if not gems then
			return
		end
		local function refresh()
			label.Text = "💎 " .. formatNumber(gems.Value)
		end
		gems.Changed:Connect(refresh)
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
			elseif def.RewardOnly then
				-- Parkour-Meister-Belohnung: nicht kaufbar
				button.Text = "🏅 MEISTER"
				button.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
			elseif def.GemCost then
				button.Text = formatNumber(def.GemCost) .. "💎"
				button.BackgroundColor3 = Color3.fromRGB(60, 170, 200)
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
		refreshRows(Config.GemTrails, trailRows, data.Trails, data.EquippedTrail)
		refreshRows(Config.Skins, skinRows, data.Skins, data.EquippedSkin)
		refreshRows(Config.GemSkins, skinRows, data.Skins, data.EquippedSkin)
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
			-- Season-/Meister-Items haben keinen Preis, Gem-Items kosten 💎
			button.Text = if def.Seasonal
				then "🎫 PASS"
				elseif def.RewardOnly then "🏅 MEISTER"
				elseif def.GemCost then formatNumber(def.GemCost) .. "💎"
				else formatNumber(def.Cost) .. "💰"
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
	-- Eine Ei-Zeile (Cash-Eier UND Juwelen-Eier – Unterschied ist nur der Preis-Knopf)
	local function makeEggRow(eggDef: any, order: number)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 66)
		row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		row.LayoutOrder = order
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
		button.BackgroundColor3 = if eggDef.GemCost then Color3.fromRGB(60, 170, 200) else Color3.fromRGB(240, 160, 40)
		button.Font = FONT
		button.TextScaled = true
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = if eggDef.GemCost then formatNumber(eggDef.GemCost) .. "💎" else formatNumber(eggDef.Cost) .. "💰"
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

	for i, eggDef in Config.Eggs do
		makeEggRow(eggDef, 1 + i)
	end
	-- Juwelen-Eier direkt darunter (💎 verdient man NUR im Parkour!)
	for i, eggDef in Config.GemEggs do
		makeEggRow(eggDef, 1 + #Config.Eggs + i)
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

-- ══════════ Parkour: Lauf-HUD + Ergebnis-Anzeige ══════════
-- Datenquelle: Attribute ParkourCourse/ParkourStart (setzt NUR der Server).
-- Die Uhr ist workspace:GetServerTimeNow() – exakt dieselbe, mit der der
-- Server misst, also lügt der Timer nie.

local function buildParkourHud()
	local frame = Instance.new("Frame")
	frame.Name = "ParkourHud"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 72)
	frame.Size = UDim2.fromOffset(340, 64)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BackgroundTransparency = 0.25
	frame.Visible = false
	roundify(frame, 12)
	frame.Parent = gui

	local nameLabel = makeLabel(frame, {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -115, 0, 22),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local timeLabel = makeLabel(frame, {
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -115, 0, 30),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 80),
	})

	local leave = Instance.new("TextButton")
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.Position = UDim2.new(1, -8, 0.5, 0)
	leave.Size = UDim2.fromOffset(95, 46)
	leave.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	leave.Font = FONT
	leave.TextScaled = true
	leave.Text = "🏳️ RAUS"
	leave.TextColor3 = Color3.new(1, 1, 1)
	roundify(leave, 10)
	leave.Parent = frame
	leave.Activated:Connect(function()
		(Remotes.Get("ParkourLeave") :: RemoteEvent):FireServer()
	end)

	local function refreshVisibility()
		local courseId = player:GetAttribute("ParkourCourse")
		local def = if typeof(courseId) == "string" then Config.ParkourCoursesById[courseId] else nil
		frame.Visible = def ~= nil
		if def then
			nameLabel.Text = def.Name
			nameLabel.TextColor3 = def.Color
		end
	end
	player:GetAttributeChangedSignal("ParkourCourse"):Connect(refreshVisibility)
	refreshVisibility()

	RunService.RenderStepped:Connect(function()
		if not frame.Visible then
			return
		end
		local startAt = player:GetAttribute("ParkourStart")
		if typeof(startAt) ~= "number" or startAt <= 0 then
			timeLabel.Text = "🏁 Lauf durchs GRÜNE Tor!"
		else
			timeLabel.Text = ("⏱️ %.2fs"):format(math.max(0, workspace:GetServerTimeNow() - startAt))
		end
	end)
end

-- Ergebnis-Panel nach einem geschafften Lauf (verschwindet mit dem Rück-Teleport)
function Ui.ParkourResult(data: any)
	local frame = Instance.new("Frame")
	frame.Name = "ParkourResult"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.38)
	frame.Size = UDim2.fromOffset(400, 200)
	frame.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
	frame.BackgroundTransparency = 0.06
	frame.ZIndex = 15
	roundify(frame, 16)
	frame.Parent = gui

	makeLabel(frame, {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 34),
		Text = "🏁 GESCHAFFT: " .. tostring(data.Name),
		TextColor3 = Color3.fromRGB(140, 255, 160),
		ZIndex = 16,
	})
	makeLabel(frame, {
		Position = UDim2.fromOffset(10, 48),
		Size = UDim2.new(1, -20, 0, 52),
		Text = ("⏱️ %.2fs"):format(tonumber(data.Time) or 0),
		TextColor3 = Color3.fromRGB(255, 220, 80),
		ZIndex = 16,
	})
	makeLabel(frame, {
		Position = UDim2.fromOffset(10, 108),
		Size = UDim2.new(1, -20, 0, 34),
		Text = ("+%d💰   +%d💎"):format(tonumber(data.Cash) or 0, tonumber(data.Gems) or 0),
		ZIndex = 16,
	})

	local extras = {}
	if data.ServerRecord then
		table.insert(extras, "🏆 SERVER-REKORD!")
	end
	if data.PersonalBest then
		table.insert(extras, "✨ Neue Bestzeit!")
	end
	if data.UnlockedNext then
		table.insert(extras, "🔓 Nächster Parcours offen!")
	end
	if #extras > 0 then
		makeLabel(frame, {
			Position = UDim2.fromOffset(10, 150),
			Size = UDim2.new(1, -20, 0, 30),
			Text = table.concat(extras, "  "),
			TextColor3 = Color3.fromRGB(255, 180, 255),
			ZIndex = 16,
		})
	end

	task.delay(Config.ParkourReturnDelay + 0.5, function()
		frame:Destroy()
	end)
end

-- ══════════ Supreme-Truck-Fortschritt ══════════
-- Zeigt, wie viele Trucks es noch bis zum Mutanten-Express sind.
-- Datenquelle: Workspace-Attribute (setzt der TruckService, replizieren automatisch).

local function buildSupremeBar()
	local frame = Instance.new("Frame")
	frame.Name = "SupremeProgress"
	frame.Position = UDim2.new(0, 12, 0, 104) -- unter der Juwelen-Anzeige (y=62, Höhe 36)
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
-- Kleines Badge unter der Supreme-Anzeige, solange der Server-Bonus aktiv ist
-- (Datenquelle: "FriendsOnline"-Attribut, setzt der FriendService).

local function buildFriendBonus()
	local frame = Instance.new("Frame")
	frame.Name = "FriendBonus"
	frame.Position = UDim2.new(0, 12, 0, 158) -- unter SupremeProgress (y=104, Höhe 48)
	frame.Size = UDim2.fromOffset(190, 30)
	frame.BackgroundColor3 = Color3.fromRGB(30, 55, 40)
	frame.BackgroundTransparency = 0.25
	frame.Visible = false
	roundify(frame, 10)
	frame.Parent = gui

	local label = makeLabel(frame, {
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(140, 230, 160),
	})

	local function refresh()
		local friends = player:GetAttribute("FriendsOnline")
		local active = typeof(friends) == "number" and friends > 0
		frame.Visible = active
		if active then
			label.Text = ("👫 Freundes-Bonus: +%d%%"):format(Config.FriendBonusPercent * 100)
		end
	end
	player:GetAttributeChangedSignal("FriendsOnline"):Connect(refresh)
	refresh()
end

-- ══════════ Debug-Menü (nur Entwickler) ══════════
-- Erscheint nur, wenn der Server das "IsDev"-Attribut setzt (Studio/Whitelist).
-- Tabs (Spieler/Events/Diagnose/Server), Suchfeld, Ziel-Auswahl und F4-Toggle.
-- Die Command-Buttons kommen komplett vom Server (DebugCommand "list") – neue
-- Commands im DebugService tauchen automatisch im passenden Tab auf, ohne
-- UI-Änderung. Die Diagnose-Tools (Zonen-Anzeige, State-Inspector, Log-Panel,
-- Performance-HUD) laufen client-lokal und LESEN den Spielzustand nur aus.

local debugBuilt = false

local function buildDebugMenu()
	if debugBuilt then
		return
	end
	debugBuilt = true

	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local debugRemote = Remotes.Get("DebugCommand") :: RemoteFunction

	-- Sichere Invoke-Hülle (Server prüft die Whitelist bei jedem Aufruf selbst)
	local function invoke(action: string, payload: any?): any
		local ok, result = pcall(function()
			return debugRemote:InvokeServer(action, payload)
		end)
		return if ok then result else nil
	end

	-- ── Ziel-Auswahl: nil = ich selbst ──
	local targetUserId: number? = nil

	local function targetPayload(extra: any?): any
		local payload = extra or {}
		payload.Target = targetUserId
		return payload
	end

	-- ── Hauptfenster ──
	local panel = makeWindow("🐞 DEBUG-MENÜ", Vector2.new(620, 540), Color3.fromRGB(255, 120, 120))

	local searchBox = Instance.new("TextBox")
	searchBox.Position = UDim2.fromOffset(16, 44)
	searchBox.Size = UDim2.new(0.5, -24, 0, 32)
	searchBox.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	searchBox.Font = FONT
	searchBox.TextSize = 16
	searchBox.TextColor3 = Color3.new(1, 1, 1)
	searchBox.PlaceholderText = "🔍 Aktion suchen..."
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	roundify(searchBox, 8)
	searchBox.Parent = panel

	local targetButton = Instance.new("TextButton")
	targetButton.AnchorPoint = Vector2.new(1, 0)
	targetButton.Position = UDim2.new(1, -16, 0, 44)
	targetButton.Size = UDim2.new(0.5, -24, 0, 32)
	targetButton.BackgroundColor3 = Color3.fromRGB(70, 60, 90)
	targetButton.Font = FONT
	targetButton.TextScaled = true
	targetButton.TextColor3 = Color3.fromRGB(255, 220, 120)
	targetButton.Text = "🎯 Ziel: DU"
	roundify(targetButton, 8)
	targetButton.Parent = panel

	local function refreshTargetButton()
		local target = targetUserId and Players:GetPlayerByUserId(targetUserId)
		if targetUserId and not target then
			targetUserId = nil -- Ziel hat den Server verlassen
		end
		targetButton.Text = if target then ("🎯 Ziel: %s"):format(target.Name) else "🎯 Ziel: DU (klick = wechseln)"
	end

	-- Klick = zum nächsten Spieler im Server durchschalten (Kategorie 4.1)
	targetButton.Activated:Connect(function()
		local players = Players:GetPlayers()
		local currentId = targetUserId or player.UserId
		local index = 1
		for i, p in players do
			if p.UserId == currentId then
				index = i
				break
			end
		end
		local nextPlayer = players[(index % #players) + 1]
		targetUserId = if nextPlayer == player then nil else nextPlayer.UserId
		refreshTargetButton()
	end)

	-- ── Tabs ──
	local TABS = { "Spieler", "Events", "Diagnose", "Server" }
	local activeTab = "Spieler"
	local tabButtons: { [string]: TextButton } = {}
	local rebuildRows: () -> () = function() end

	local tabRow = Instance.new("Frame")
	tabRow.Position = UDim2.fromOffset(16, 84)
	tabRow.Size = UDim2.new(1, -32, 0, 34)
	tabRow.BackgroundTransparency = 1
	tabRow.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabRow

	for _, name in TABS do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0.25, -6, 1, 0)
		button.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		button.Font = FONT
		button.TextScaled = true
		button.Text = name
		button.TextColor3 = Color3.new(1, 1, 1)
		roundify(button, 8)
		button.Parent = tabRow
		tabButtons[name] = button
		button.Activated:Connect(function()
			activeTab = name
			rebuildRows()
		end)
	end

	-- ── Command-Liste ──
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 126)
	list.Size = UDim2.new(1, -24, 1, -138)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local commandsCache: { any } = {}

	-- ── Bestätigungs-Dialog für Danger-Commands ──
	local function confirmThen(question: string, callback: () -> ())
		local overlay = Instance.new("TextButton")
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0.5
		overlay.Text = ""
		overlay.AutoButtonColor = false
		overlay.ZIndex = 30
		overlay.Parent = gui

		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromOffset(400, 160)
		box.BackgroundColor3 = Color3.fromRGB(70, 38, 44)
		box.ZIndex = 31
		roundify(box, 14)
		box.Parent = overlay
		makeLabel(box, {
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -28, 0, 84),
			Text = ("⚠️ Wirklich ausführen?\n%s\nDas kann Fortschritt zerstören!"):format(question),
			TextWrapped = true,
			TextScaled = false,
			TextSize = 16,
			ZIndex = 32,
		})
		local function makeChoice(text: string, color: Color3, x: number, onClick: () -> ())
			local button = Instance.new("TextButton")
			button.Position = UDim2.new(x, 14, 1, -54)
			button.Size = UDim2.new(0.5, -28, 0, 42)
			button.BackgroundColor3 = color
			button.Font = FONT
			button.TextScaled = true
			button.Text = text
			button.TextColor3 = Color3.new(1, 1, 1)
			button.ZIndex = 32
			roundify(button, 10)
			button.Parent = box
			button.Activated:Connect(onClick)
		end
		makeChoice("✅ JA, ausführen", Color3.fromRGB(180, 60, 60), 0, function()
			overlay:Destroy()
			callback()
		end)
		makeChoice("ABBRECHEN", Color3.fromRGB(70, 70, 90), 0.5, function()
			overlay:Destroy()
		end)
		overlay.Activated:Connect(function()
			overlay:Destroy()
		end)
	end

	-- ── Diagnose-Tool 1: State-Inspector (links, live-aktualisiert) ──
	local inspectorFrame = makeWindow("📋 STATE-INSPECTOR", Vector2.new(380, 470), Color3.fromRGB(150, 220, 255))
	inspectorFrame.AnchorPoint = Vector2.new(0, 0.5)
	inspectorFrame.Position = UDim2.new(0, 12, 0.5, 0)
	local inspectorScroll = Instance.new("ScrollingFrame")
	inspectorScroll.Position = UDim2.new(0, 12, 0, 48)
	inspectorScroll.Size = UDim2.new(1, -24, 1, -60)
	inspectorScroll.BackgroundTransparency = 1
	inspectorScroll.BorderSizePixel = 0
	inspectorScroll.ScrollBarThickness = 6
	inspectorScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	inspectorScroll.CanvasSize = UDim2.new()
	inspectorScroll.Parent = inspectorFrame
	local inspectorText = Instance.new("TextLabel")
	inspectorText.Size = UDim2.new(1, -8, 0, 0)
	inspectorText.AutomaticSize = Enum.AutomaticSize.Y
	inspectorText.BackgroundTransparency = 1
	inspectorText.Font = Enum.Font.Code
	inspectorText.TextSize = 14
	inspectorText.TextColor3 = Color3.fromRGB(200, 230, 255)
	inspectorText.TextXAlignment = Enum.TextXAlignment.Left
	inspectorText.TextYAlignment = Enum.TextYAlignment.Top
	inspectorText.TextWrapped = true
	inspectorText.Text = ""
	inspectorText.Parent = inspectorScroll

	task.spawn(function()
		while true do
			task.wait(0.7)
			if inspectorFrame.Visible then
				local result = invoke("inspect", targetPayload())
				if typeof(result) == "table" and typeof(result.Lines) == "table" then
					inspectorText.Text = table.concat(result.Lines, "\n")
				end
			end
		end
	end)

	-- ── Diagnose-Tool 2: Zonen-Visualisierung (client-lokal, rein lesend) ──
	local zoneFolder: Folder? = nil

	local function addOverlayBox(folder: Folder, cf: CFrame, size: Vector3, color: Color3, labelText: string?): Part
		local box = Instance.new("Part")
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box.CanTouch = false
		box.Transparency = 0.72
		box.Color = color
		box.Material = Enum.Material.SmoothPlastic
		box.Size = size
		box.CFrame = cf
		if labelText then
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(180, 22)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1, 0)
			billboard.AlwaysOnTop = true
			billboard.MaxDistance = 200
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = labelText
			label.TextScaled = true
			label.Font = FONT
			label.TextColor3 = color
			label.TextStrokeTransparency = 0.2
			label.Parent = billboard
			billboard.Parent = box
		end
		box.Parent = folder
		return box
	end

	local function toggleZoneOverlay()
		if zoneFolder then
			zoneFolder:Destroy()
			zoneFolder = nil
			Ui.Toast("🗺️ Zonen-Anzeige AUS.")
			return
		end
		local folder = Instance.new("Folder")
		folder.Name = "DebugZoneOverlay"
		zoneFolder = folder

		-- Basis-Fangzonen (grün)
		local map = workspace:FindFirstChild("Map")
		if map then
			for _, inst in map:GetDescendants() do
				if inst.Name == "VaultZone" and inst:IsA("BasePart") then
					local parentName = inst.Parent and inst.Parent.Name or "?"
					addOverlayBox(folder, inst.CFrame, inst.Size, Color3.fromRGB(80, 220, 120), "VaultZone " .. parentName)
				end
			end
		end

		-- Alle ProximityPrompts: Part orange umranden + Reichweite als Kugel
		-- (Snacks/Pets ausgenommen – die bewegen sich; das hier ist ein Snapshot)
		local snacksFolder = workspace:FindFirstChild("Snacks")
		local petsFolder = workspace:FindFirstChild("Pets")
		for _, inst in workspace:GetDescendants() do
			if not inst:IsA("ProximityPrompt") then
				continue
			end
			local parent = inst.Parent
			if not (parent and parent:IsA("BasePart")) then
				continue
			end
			if snacksFolder and parent:IsDescendantOf(snacksFolder) then
				continue
			end
			if petsFolder and parent:IsDescendantOf(petsFolder) then
				continue
			end
			if parent:IsDescendantOf(folder) then
				continue
			end
			local title = if inst.ObjectText ~= "" then inst.ObjectText else parent.Name
			addOverlayBox(folder, parent.CFrame, parent.Size + Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 170, 60), "📍 " .. title)
			local range = addOverlayBox(folder, parent.CFrame, Vector3.one * inst.MaxActivationDistance * 2, Color3.fromRGB(255, 170, 60))
			range.Transparency = 0.93
			range.Shape = Enum.PartType.Ball
		end
		folder.Parent = workspace
		Ui.Toast("🗺️ Zonen-Anzeige AN (Snapshot – nach Map-Änderungen neu togglen).")
	end

	-- ── Diagnose-Tool 3: Log- & Remote-Panel (rechts) ──
	local logFrame = makeWindow("🧾 LOGS & REMOTES", Vector2.new(470, 430), Color3.fromRGB(255, 180, 120))
	logFrame.AnchorPoint = Vector2.new(1, 0.5)
	logFrame.Position = UDim2.new(1, -12, 0.5, 0)
	local logScroll = Instance.new("ScrollingFrame")
	logScroll.Position = UDim2.new(0, 12, 0, 48)
	logScroll.Size = UDim2.new(1, -24, 1, -60)
	logScroll.BackgroundTransparency = 1
	logScroll.BorderSizePixel = 0
	logScroll.ScrollBarThickness = 6
	logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logScroll.CanvasSize = UDim2.new()
	logScroll.Parent = logFrame
	local logText = Instance.new("TextLabel")
	logText.Size = UDim2.new(1, -8, 0, 0)
	logText.AutomaticSize = Enum.AutomaticSize.Y
	logText.BackgroundTransparency = 1
	logText.Font = Enum.Font.Code
	logText.TextSize = 13
	logText.TextColor3 = Color3.fromRGB(255, 220, 190)
	logText.TextXAlignment = Enum.TextXAlignment.Left
	logText.TextYAlignment = Enum.TextYAlignment.Top
	logText.TextWrapped = true
	logText.Text = ""
	logText.Parent = logScroll

	-- Server->Client-Events lokal mitschreiben (Sfx ausgenommen – zu laut)
	local clientRemoteLog: { string } = {}
	for _, remote in ReplicatedStorage:WaitForChild("Remotes"):GetChildren() do
		if remote:IsA("RemoteEvent") and remote.Name ~= "Sfx" then
			remote.OnClientEvent:Connect(function(...)
				local args = table.pack(...)
				local parts = {}
				for i = 1, math.min(args.n, 3) do
					table.insert(parts, tostring(args[i]))
				end
				table.insert(clientRemoteLog, ("[%s] %s: %s"):format(os.date("%H:%M:%S"), remote.Name, table.concat(parts, ", ")))
				if #clientRemoteLog > 10 then
					table.remove(clientRemoteLog, 1)
				end
			end)
		end
	end

	task.spawn(function()
		while true do
			task.wait(2)
			if not logFrame.Visible then
				continue
			end
			local data = invoke("logs")
			if typeof(data) ~= "table" then
				continue
			end
			local lines = { "── SERVER-WARNUNGEN/-FEHLER (letzte 20) ──" }
			if typeof(data.Logs) == "table" then
				if #data.Logs == 0 then
					table.insert(lines, "(keine – gut so!)")
				end
				for _, entry in data.Logs do
					table.insert(lines, ("[%s %s] %s"):format(entry.Time, entry.Type, entry.Text))
				end
			end
			table.insert(lines, "")
			table.insert(lines, "── REMOTES Client→Server (letzte 15) ──")
			if typeof(data.Remotes) == "table" then
				for _, entry in data.Remotes do
					table.insert(lines, ("[%s] %s ← %s (%s)"):format(entry.Time, entry.Name, entry.From, entry.Args))
				end
			end
			table.insert(lines, "")
			table.insert(lines, "── REMOTES Server→Client (lokal, ohne Sfx) ──")
			for _, line in clientRemoteLog do
				table.insert(lines, line)
			end
			logText.Text = table.concat(lines, "\n")
		end
	end)

	-- ── Diagnose-Tool 4: Performance-HUD (FPS/Ping/Server-RAM) ──
	local perfFrame = Instance.new("Frame")
	perfFrame.Name = "PerfHud"
	perfFrame.AnchorPoint = Vector2.new(1, 1)
	perfFrame.Position = UDim2.new(1, -12, 1, -66)
	perfFrame.Size = UDim2.fromOffset(190, 74)
	perfFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	perfFrame.BackgroundTransparency = 0.25
	perfFrame.Visible = false
	roundify(perfFrame, 10)
	perfFrame.Parent = gui
	local perfLabel = makeLabel(perfFrame, {
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 1, -8),
		Text = "📈 ...",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextSize = 14,
	})

	local serverMemoryMb = 0
	task.spawn(function()
		while true do
			task.wait(3)
			if perfFrame.Visible then
				local data = invoke("logs")
				if typeof(data) == "table" and typeof(data.MemoryMb) == "number" then
					serverMemoryMb = data.MemoryMb
				end
			end
		end
	end)
	local frameCount = 0
	local fpsWindowStart = os.clock()
	RunService.RenderStepped:Connect(function()
		if not perfFrame.Visible then
			return
		end
		frameCount += 1
		local now = os.clock()
		if now - fpsWindowStart >= 1 then
			local fps = frameCount / (now - fpsWindowStart)
			frameCount = 0
			fpsWindowStart = now
			local ping = math.floor(player:GetNetworkPing() * 1000)
			perfLabel.Text = ("📈 FPS: %d\n📡 Ping: %d ms\n💾 Server-RAM: %d MB"):format(fps, ping, serverMemoryMb)
		end
	end)

	-- Lokale Diagnose-Zeilen (erscheinen NUR im Diagnose-Tab)
	local localTools = {
		{ Label = "📋 State-Inspector ein/aus (zeigt das ZIEL)", Action = function()
			inspectorFrame.Visible = not inspectorFrame.Visible
		end },
		{ Label = "🗺️ Trigger-Zonen einblenden/ausblenden", Action = toggleZoneOverlay },
		{ Label = "🧾 Log- & Remote-Panel ein/aus", Action = function()
			logFrame.Visible = not logFrame.Visible
		end },
		{ Label = "📈 Performance-HUD ein/aus (FPS/Ping/RAM)", Action = function()
			perfFrame.Visible = not perfFrame.Visible
		end },
	}

	-- ── Zeilen im aktiven Tab (nach Suchtext gefiltert) ──
	local function makeRow(order: number, labelText: string, danger: boolean, argDefault: number?, onRun: (value: number?) -> ())
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 40)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Parent = list

		local argBox: TextBox? = nil
		if argDefault ~= nil then
			local box = Instance.new("TextBox")
			box.AnchorPoint = Vector2.new(1, 0.5)
			box.Position = UDim2.new(1, 0, 0.5, 0)
			box.Size = UDim2.fromOffset(96, 36)
			box.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
			box.Font = FONT
			box.TextSize = 16
			box.TextColor3 = Color3.new(1, 1, 1)
			box.Text = tostring(argDefault)
			box.ClearTextOnFocus = false
			roundify(box, 8)
			box.Parent = row
			argBox = box
		end

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, if argBox then -104 else 0, 1, 0)
		button.BackgroundColor3 = if danger then Color3.fromRGB(150, 55, 60) else Color3.fromRGB(70, 60, 90)
		button.Font = FONT
		button.TextScaled = true
		button.Text = (if danger then "⚠️ " else "") .. labelText
		button.TextColor3 = Color3.new(1, 1, 1)
		roundify(button, 8)
		button.Parent = row
		button.Activated:Connect(function()
			onRun(if argBox then tonumber(argBox.Text) else nil)
		end)
	end

	rebuildRows = function()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == activeTab then Color3.fromRGB(180, 60, 65) else Color3.fromRGB(55, 48, 70)
		end

		local filter = searchBox.Text:lower()
		local function matches(label: string): boolean
			return filter == "" or label:lower():find(filter, 1, true) ~= nil
		end

		local order = 0
		if activeTab == "Diagnose" then
			for _, tool in localTools do
				if matches(tool.Label) then
					order += 1
					makeRow(order, tool.Label, false, nil, tool.Action)
				end
			end
		end
		for _, cmd in commandsCache do
			if cmd.Category == activeTab and matches(cmd.Label) then
				order += 1
				makeRow(order, cmd.Label, cmd.Danger == true, cmd.Arg and cmd.Arg.Default, function(value)
					local function run()
						task.spawn(function()
							local result = invoke(cmd.Id, targetPayload({ Value = value }))
							if typeof(result) == "table" and result.msg then
								Ui.Toast((result.ok and "🐞 " or "❌ ") .. result.msg)
							end
						end)
					end
					if cmd.Danger then
						confirmThen(cmd.Label, run)
					else
						run()
					end
				end)
			end
		end
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(rebuildRows)

	-- Command-Liste (neu) vom Server holen – bei jedem Öffnen, damit die
	-- dynamischen Teleport-Ziele (Basis-Besitzer!) aktuell sind
	local function refreshCommands()
		task.spawn(function()
			local result = invoke("list")
			if typeof(result) == "table" and typeof(result.Commands) == "table" then
				commandsCache = result.Commands
			end
			rebuildRows()
		end)
	end

	-- ── Toggle-Button + F4 ──
	local toggle = Instance.new("TextButton")
	toggle.Name = "DebugToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 12, 1, -12)
	toggle.Size = UDim2.fromOffset(130, 40)
	toggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "🐞 DEBUG [F4]"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local function togglePanel()
		panel.Visible = not panel.Visible
		if panel.Visible then
			refreshTargetButton()
			refreshCommands()
		end
	end
	toggle.Activated:Connect(togglePanel)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F4 then
			togglePanel()
		end
	end)

	refreshCommands()
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
-- Fenster mit Stats & Freischaltungen vom Server (GetAchievements).

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
	local toggle = Instance.new("TextButton")
	toggle.Name = "AchievementToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 116) -- unter Hilfe (12) und Pass (64)
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle.BackgroundColor3 = Color3.fromRGB(200, 170, 60)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "🏅"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local frame = makeWindow("🏅 ACHIEVEMENTS", Vector2.new(460, 520), Color3.fromRGB(255, 215, 0))

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

	-- Eine Zeile pro Achievement, Fortschritt/Häkchen füllt refresh()
	local rows: { [string]: { Row: Frame, Name: TextLabel, Progress: TextLabel } } = {}
	for i, def in Config.Achievements do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 52)
		row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		row.LayoutOrder = i
		roundify(row, 10)
		row.Parent = list

		local nameLabel = makeLabel(row, {
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -110, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Name,
		})
		makeLabel(row, {
			Position = UDim2.fromOffset(10, 30),
			Size = UDim2.new(1, -110, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Desc,
			TextColor3 = Color3.fromRGB(190, 190, 200),
			TextScaled = false,
			TextSize = 13,
		})
		local progress = makeLabel(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(90, 30),
			Text = "…",
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(190, 190, 200),
		})
		rows[def.Id] = { Row = row, Name = nameLabel, Progress = progress }
	end

	local function refresh()
		task.spawn(function()
			local ok, data = pcall(function()
				return (Remotes.Get("GetAchievements") :: RemoteFunction):InvokeServer()
			end)
			if not ok or typeof(data) ~= "table" then
				return
			end
			for _, def in Config.Achievements do
				local refs = rows[def.Id]
				if not refs then
					continue
				end
				local unlocked = data.Unlocked and data.Unlocked[def.Id] == true
				local value = math.min(data.Stats and data.Stats[def.Stat] or 0, def.Goal)
				refs.Row.BackgroundColor3 = if unlocked then Color3.fromRGB(45, 70, 50) else Color3.fromRGB(55, 48, 70)
				refs.Progress.Text = if unlocked then "✅" else ("%d/%d"):format(value, def.Goal)
				refs.Progress.TextColor3 = if unlocked
					then Color3.fromRGB(140, 230, 160)
					else Color3.fromRGB(190, 190, 200)
			end
		end)
	end

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		if frame.Visible then
			refresh()
		end
	end)
end

-- ══════════ Referral/Einladungen ══════════
-- Zeigt den eigenen Code + Erfolgs-Zähler und lässt NEUE Spieler einen
-- fremden Code einlösen. Alles Weitere validiert der ReferralService.

local function buildReferral()
	local toggle = Instance.new("TextButton")
	toggle.Name = "ReferralToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 168) -- unter Hilfe/Pass/Achievements
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle.BackgroundColor3 = Color3.fromRGB(80, 180, 200)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "👥"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local frame = makeWindow("👥 FREUNDE EINLADEN", Vector2.new(440, 330), Color3.fromRGB(120, 220, 240))

	makeLabel(frame, {
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -32, 0, 40),
		Text = ("Lade Freunde ein! Schafft dein Freund Rebirth 1,\nkriegst DU %s💰 + ein Gratis-Gold-Ei!"):format(
			formatNumber(Config.ReferralRewardCash)
		),
		TextColor3 = Color3.fromRGB(190, 190, 200),
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
	})

	-- Eigener Code (groß, zum Abtippen/Weitersagen)
	local codeBox = Instance.new("TextBox")
	codeBox.Position = UDim2.new(0, 16, 0, 94)
	codeBox.Size = UDim2.new(1, -32, 0, 44)
	codeBox.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	codeBox.Font = FONT
	codeBox.TextScaled = true
	codeBox.TextColor3 = Color3.fromRGB(255, 215, 0)
	codeBox.Text = "…"
	codeBox.TextEditable = false -- nur zum Markieren/Kopieren, nicht editierbar
	codeBox.ClearTextOnFocus = false
	roundify(codeBox, 10)
	codeBox.Parent = frame

	local statsLabel = makeLabel(frame, {
		Position = UDim2.fromOffset(16, 144),
		Size = UDim2.new(1, -32, 0, 24),
		Text = "",
		TextColor3 = Color3.fromRGB(140, 230, 160),
	})

	-- Einlöse-Bereich (nur sichtbar, solange man selbst noch einlösen darf)
	local redeemBox = Instance.new("TextBox")
	redeemBox.Position = UDim2.new(0, 16, 0, 186)
	redeemBox.Size = UDim2.new(1, -152, 0, 40)
	redeemBox.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	redeemBox.Font = FONT
	redeemBox.TextSize = 18
	redeemBox.TextColor3 = Color3.new(1, 1, 1)
	redeemBox.PlaceholderText = "Code vom Freund, z.B. " .. Config.ReferralCodePrefix .. "12345"
	redeemBox.Text = ""
	redeemBox.ClearTextOnFocus = false
	roundify(redeemBox, 10)
	redeemBox.Parent = frame

	local redeemButton = Instance.new("TextButton")
	redeemButton.AnchorPoint = Vector2.new(1, 0)
	redeemButton.Position = UDim2.new(1, -16, 0, 186)
	redeemButton.Size = UDim2.fromOffset(112, 40)
	redeemButton.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
	redeemButton.Font = FONT
	redeemButton.TextScaled = true
	redeemButton.Text = "EINLÖSEN"
	redeemButton.TextColor3 = Color3.new(1, 1, 1)
	roundify(redeemButton, 10)
	redeemButton.Parent = frame

	local redeemHint = makeLabel(frame, {
		Position = UDim2.fromOffset(16, 232),
		Size = UDim2.new(1, -32, 0, 60),
		Text = "",
		TextColor3 = Color3.fromRGB(190, 190, 200),
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
	})

	local function refresh()
		task.spawn(function()
			local ok, info = pcall(function()
				return (Remotes.Get("GetReferralInfo") :: RemoteFunction):InvokeServer()
			end)
			if not ok or typeof(info) ~= "table" then
				return
			end
			codeBox.Text = info.Code or "?"
			statsLabel.Text = ("🤝 Erfolgreich eingeladen: %d"):format(info.SuccessCount or 0)
			local canRedeem = info.CanRedeem == true
			redeemBox.Visible = canRedeem
			redeemButton.Visible = canRedeem
			if canRedeem then
				redeemHint.Text = "Hat DICH jemand eingeladen? Löse seinen Code ein (geht nur vor deinem ersten Rebirth)!"
			elseif (info.InvitedBy or 0) > 0 then
				redeemHint.Text = "✅ Du bist schon mit deinem Einlader verknüpft – schaff Rebirth 1 für seine Prämie!"
			else
				redeemHint.Text = "Einlösen geht nur für neue Spieler (vor dem ersten Rebirth)."
			end
		end)
	end

	redeemButton.Activated:Connect(function()
		local code = redeemBox.Text
		if code:gsub("%s", "") == "" then
			Ui.Toast("❌ Erst einen Code eintippen!")
			return
		end
		task.spawn(function()
			local ok, result = pcall(function()
				return (Remotes.Get("RedeemReferral") :: RemoteFunction):InvokeServer(code)
			end)
			if ok and typeof(result) == "table" then
				Ui.Toast((result.ok and "🤝 " or "❌ ") .. result.msg)
			end
			refresh()
		end)
	end)

	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
		if frame.Visible then
			refresh()
		end
	end)
end

-- ══════════ Basis-Deko (Housing) ══════════
-- Kaufen + Aufstellen/Entfernen von Deko-Objekten für die eigene Basis.
-- Besitz/Slots kommen per GetHousing vom Server; validiert wird dort.

local function buildHousing()
	local toggle = Instance.new("TextButton")
	toggle.Name = "HousingToggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -12, 0, 220) -- unter Hilfe/Pass/Achievements/Referral
	toggle.Size = UDim2.fromOffset(44, 44)
	toggle.BackgroundColor3 = Color3.fromRGB(120, 200, 120)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "🏡"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	local frame = makeWindow("🏡 BASIS-DEKO", Vector2.new(460, 520), Color3.fromRGB(150, 230, 150))

	local slotLabel = makeLabel(frame, {
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32, 0, 22),
		Text = "",
		TextColor3 = Color3.fromRGB(190, 190, 200),
		TextScaled = false,
		TextSize = 15,
	})

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 70)
	list.Size = UDim2.new(1, -24, 1, -82)
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

	local housingCache: any = { Owned = {}, Slots = {}, HasBase = false, SlotCount = #Config.HousingSlotOffsets }
	local decorRows: { [string]: TextButton } = {}
	local refresh: () -> ()

	for i, def in Config.HousingDecor do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 54)
		row.BackgroundColor3 = Color3.fromRGB(55, 48, 70)
		row.LayoutOrder = i
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
			Size = UDim2.new(1, -140, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = def.Desc or "",
			TextColor3 = Color3.fromRGB(190, 190, 200),
			TextScaled = false,
			TextSize = 13,
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
		decorRows[def.Id] = button

		button.Activated:Connect(function()
			task.spawn(function()
				-- Aktion aus dem Cache ableiten: kaufen -> aufstellen -> entfernen
				local owned = housingCache.Owned and housingCache.Owned[def.Id] == true
				local placed = housingCache.Slots and table.find(housingCache.Slots, def.Id) ~= nil
				local ok, result
				if not owned then
					ok, result = pcall(function()
						return (Remotes.Get("BuyDecor") :: RemoteFunction):InvokeServer(def.Id)
					end)
				else
					ok, result = pcall(function()
						return (Remotes.Get("PlaceDecor") :: RemoteFunction):InvokeServer(def.Id, not placed)
					end)
				end
				if ok and typeof(result) == "table" then
					Ui.Toast((result.ok and "🏡 " or "❌ ") .. result.msg)
				end
				refresh()
			end)
		end)
	end

	refresh = function()
		task.spawn(function()
			local ok, data = pcall(function()
				return (Remotes.Get("GetHousing") :: RemoteFunction):InvokeServer()
			end)
			if not ok or typeof(data) ~= "table" then
				return
			end
			housingCache = data

			local placedCount = 0
			for _, decorId in data.Slots or {} do
				if decorId ~= "" then
					placedCount += 1
				end
			end
			slotLabel.Text = if data.HasBase
				then ("Deko-Plätze an deiner Basis: %d/%d belegt"):format(placedCount, data.SlotCount or 0)
				else "⚠️ Erst eine Basis beanspruchen – dann wird hier dekoriert!"

			for _, def in Config.HousingDecor do
				local button = decorRows[def.Id]
				if not button then
					continue
				end
				local owned = data.Owned and data.Owned[def.Id] == true
				local placed = data.Slots and table.find(data.Slots, def.Id) ~= nil
				if placed then
					button.Text = "ENTFERNEN"
					button.BackgroundColor3 = Color3.fromRGB(90, 120, 220)
				elseif owned then
					button.Text = "AUFSTELLEN"
					button.BackgroundColor3 = Color3.fromRGB(70, 170, 90)
				else
					button.Text = formatNumber(def.Cost) .. "💰"
					button.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
				end
			end
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
	panel.Size = UDim2.fromOffset(460, 490)
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
		"🌟 GOLDENER SNACK: taucht zufällig auf – wer ZUERST hinrennt, kassiert!",
		"🏆 ACHIEVEMENTS (Pokal-Button): Meilensteine sammeln!",
		"🤝 Mit Roblox-FREUNDEN im Server spielen = +10% Einkommen!",
		"👥 FREUNDE EINLADEN (Button rechts): Code teilen = fette Belohnung!",
		"🏡 BASIS-DEKO (Button rechts): Deko kaufen & aufstellen!",
	}, "\n")

	local body = Instance.new("TextLabel")
	body.Position = UDim2.new(0, 16, 0, 48)
	body.Size = UDim2.new(1, -32, 1, -64)
	body.BackgroundTransparency = 1
	body.Font = FONT
	body.Text = helpText
	body.TextColor3 = Color3.new(1, 1, 1)
	body.TextSize = 16
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
	buildGemDisplay()
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
			Header = "💎 JUWELEN-TRAILS (nur mit Parkour-Juwelen!)",
			Items = Config.GemTrails,
			Rows = trailRows, -- Ids sind eindeutig, gleiche Map wie normale Trails
			BuyRemote = "BuyTrail",
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
		{
			Header = "💎 JUWELEN-SKINS",
			Items = Config.GemSkins,
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
	buildParkourHud()
	buildSeasonPass()
	buildAchievements()
	buildReferral()
	buildHousing()
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
