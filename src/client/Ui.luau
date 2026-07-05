--[[
	Ui.luau
	Komplettes Prototyp-UI, per Code gebaut (später in Studio hübsch machen):
	- Cash-Anzeige (oben links) mit Rebirth-Multiplikator
	- Ankündigungs-Banner (oben mitte, mit Raritäts-Farbe)
	- Toast-Nachrichten (unten mitte)
	- Shop (Upgrades + Sugar-Rush-Rebirth)
	- YEET-Ladebalken + Halte-Hinweis
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
	-- Toggle-Button
	local toggle = Instance.new("TextButton")
	toggle.Name = "ShopToggle"
	toggle.Position = UDim2.new(0, 12, 0, 66)
	toggle.Size = UDim2.fromOffset(120, 40)
	toggle.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
	toggle.Font = FONT
	toggle.TextScaled = true
	toggle.Text = "🛒 SHOP"
	toggle.TextColor3 = Color3.new(1, 1, 1)
	roundify(toggle, 12)
	toggle.Parent = gui

	-- Shop-Fenster
	shopFrame = Instance.new("Frame")
	shopFrame.Name = "Shop"
	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopFrame.Position = UDim2.fromScale(0.5, 0.5)
	shopFrame.Size = UDim2.fromOffset(420, 360)
	shopFrame.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
	shopFrame.BackgroundTransparency = 0.05
	shopFrame.Visible = false
	roundify(shopFrame, 16)
	shopFrame.Parent = gui

	makeLabel(shopFrame, {
		Size = UDim2.new(1, 0, 0, 40),
		Text = "🍫 SNACK-SHOP",
		TextColor3 = Color3.fromRGB(255, 200, 80),
	})

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

	toggle.Activated:Connect(function()
		shopFrame.Visible = not shopFrame.Visible
		if shopFrame.Visible then
			refreshShop()
		end
	end)

	-- Bei Level-/Rebirth-Änderungen aktualisieren
	player.AttributeChanged:Connect(function()
		if shopFrame.Visible then
			refreshShop()
		end
	end)
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
	buildChargeBar()
	buildHelp()
end

return Ui
