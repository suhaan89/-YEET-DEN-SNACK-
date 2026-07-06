--[[
	HousingService.luau
	Basis-Deko (Housing): Deko-Objekte aus Config.Decorations mit Cash kaufen
	und in feste Slots (Config.DecoSlots) rund um die eigene Basis setzen.

	- Persistenz: profile.Housing = { Owned = {decoId=true}, Slots = {["1"]=decoId} }
	  (lazy angelegt – DataService bleibt unberührt; String-Keys, damit die
	  Slot-Tabelle sauber durch den DataStore-JSON-Encoder kommt)
	- BaseService bleibt unangetastet: wir LESEN nur GetBaseOf(player) und
	  bauen unsere Deko + das Deko-Pad in einen EIGENEN Workspace-Ordner.
	- Eine Watch-Schleife erkennt, wenn ein Spieler eine Basis beansprucht
	  (oder sie beim Verlassen freigegeben wird) und baut auf/ab.
	- Alle Käufe/Platzierungen validiert der Server (Besitz, Cash, Slot-Range).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HousingService = {}

local DataService, PlayerService, BaseService -- in Init verdrahtet

local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent
local openShopRemote: RemoteEvent

local housingFolder: Folder

-- Pro Spieler: { Base = Basis-Record, Folder = Deko-Ordner, Pad = Deko-Pad }
local state: { [Player]: any } = {}

local function ensureFields(profile)
	if typeof(profile.Housing) ~= "table" then
		profile.Housing = { Owned = {}, Slots = {} }
	end
	if typeof(profile.Housing.Owned) ~= "table" then
		profile.Housing.Owned = {}
	end
	if typeof(profile.Housing.Slots) ~= "table" then
		profile.Housing.Slots = {}
	end
	return profile.Housing
end

-- ══════════ Deko-Baukasten (alles Platzhalter-Parts, wie der Rest der Map) ══════════

local function decoPart(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

-- Jede Funktion baut EIN Deko-Objekt; cf = Boden-Mitte des Slots
local BUILDERS: { [string]: (Instance, CFrame) -> () } = {
	Zuckerstange = function(parent, cf)
		-- Rot-weiß gestreifter Mast mit Leuchtkugel obendrauf
		for i = 0, 4 do
			decoPart(parent, {
				Size = Vector3.new(0.9, 1.4, 0.9),
				CFrame = cf * CFrame.new(0, 0.7 + i * 1.4, 0),
				Color = if i % 2 == 0 then Color3.fromRGB(230, 40, 50) else Color3.fromRGB(250, 250, 250),
				Material = Enum.Material.SmoothPlastic,
			})
		end
		local lamp = decoPart(parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = cf * CFrame.new(0, 7.9, 0),
			Color = Color3.fromRGB(255, 235, 160),
			Material = Enum.Material.Neon,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 220, 140)
		light.Brightness = 2
		light.Range = 18
		light.Parent = lamp
	end,
	Lolli = function(parent, cf)
		decoPart(parent, {
			Size = Vector3.new(0.7, 7, 0.7),
			CFrame = cf * CFrame.new(0, 3.5, 0),
			Color = Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
		})
		local head = decoPart(parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 5, 5),
			CFrame = cf * CFrame.new(0, 8.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 90, 160),
			Material = Enum.Material.Neon,
		})
		decoPart(parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9, 2.4, 2.4),
			CFrame = head.CFrame,
			Color = Color3.fromRGB(150, 255, 220),
			Material = Enum.Material.Neon,
		})
	end,
	Gummibaer = function(parent, cf)
		local red = Color3.fromRGB(255, 70, 70)
		local body = decoPart(parent, {
			Size = Vector3.new(3, 3.6, 2),
			CFrame = cf * CFrame.new(0, 1.8, 0),
			Color = red,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
		})
		decoPart(parent, {
			Size = Vector3.new(2.2, 2, 1.8),
			CFrame = body.CFrame * CFrame.new(0, 2.8, 0),
			Color = red,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
		})
		for _, x in { -0.8, 0.8 } do
			decoPart(parent, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.9, 0.9, 0.9),
				CFrame = body.CFrame * CFrame.new(x, 4, 0),
				Color = red,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
			})
			decoPart(parent, {
				Size = Vector3.new(1, 2.2, 1.6),
				CFrame = body.CFrame * CFrame.new(x * 2.4, -0.7, 0),
				Color = red,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
			})
		end
	end,
	Donut = function(parent, cf)
		-- Stehender Riesen-Donut: rosa Glasur-Ring mit "Loch" (dunkler Kern)
		local ring = decoPart(parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 7, 7),
			CFrame = cf * CFrame.new(0, 4.2, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 120, 180),
			Material = Enum.Material.SmoothPlastic,
		})
		decoPart(parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.7, 2.4, 2.4),
			CFrame = ring.CFrame,
			Color = Color3.fromRGB(70, 45, 25),
			Material = Enum.Material.SmoothPlastic,
		})
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 200, 230)
		sparkles.Parent = ring
	end,
	Brunnen = function(parent, cf)
		local basin = decoPart(parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 6.5, 6.5),
			CFrame = cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(120, 75, 40),
			Material = Enum.Material.SmoothPlastic,
		})
		decoPart(parent, {
			Size = Vector3.new(1.2, 3.5, 1.2),
			CFrame = cf * CFrame.new(0, 2.5, 0),
			Color = Color3.fromRGB(90, 55, 25),
			Material = Enum.Material.SmoothPlastic,
		})
		-- Schoko-Fontäne
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 4.4, 0)
		attachment.Parent = basin
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(120, 72, 30))
		emitter.Speed = NumberRange.new(8, 12)
		emitter.Lifetime = NumberRange.new(0.7, 1.1)
		emitter.SpreadAngle = Vector2.new(14, 14)
		emitter.Acceleration = Vector3.new(0, -30, 0)
		emitter.Size = NumberSequence.new(0.45)
		emitter.Rate = 22
		emitter.Parent = attachment
	end,
	Eisturm = function(parent, cf)
		-- Waffel-Sockel + drei Kugeln + Sahnehaube
		decoPart(parent, {
			Size = Vector3.new(3, 2.5, 3),
			CFrame = cf * CFrame.new(0, 1.25, 0),
			Color = Color3.fromRGB(210, 160, 90),
			Material = Enum.Material.SmoothPlastic,
		})
		local scoops = {
			{ Y = 3.6, R = 3.4, Color = Color3.fromRGB(250, 230, 200) }, -- Vanille
			{ Y = 6.2, R = 2.8, Color = Color3.fromRGB(255, 150, 190) }, -- Erdbeere
			{ Y = 8.3, R = 2.2, Color = Color3.fromRGB(120, 200, 130) }, -- Pistazie
		}
		for _, s in scoops do
			decoPart(parent, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(s.R, s.R, s.R),
				CFrame = cf * CFrame.new(0, s.Y, 0),
				Color = s.Color,
				Material = Enum.Material.SmoothPlastic,
			})
		end
		decoPart(parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 1.1),
			CFrame = cf * CFrame.new(0, 9.7, 0),
			Color = Color3.fromRGB(255, 60, 60),
			Material = Enum.Material.Neon,
		})
	end,
	Disco = function(parent, cf)
		decoPart(parent, {
			Size = Vector3.new(0.5, 8, 0.5),
			CFrame = cf * CFrame.new(0, 4, 0),
			Color = Color3.fromRGB(60, 60, 70),
			Material = Enum.Material.Metal,
		})
		local ball = decoPart(parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.2, 3.2, 3.2),
			CFrame = cf * CFrame.new(0, 6.5, 0),
			Color = Color3.fromRGB(200, 220, 255),
			Material = Enum.Material.Glass,
			Reflectance = 0.6,
		})
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(180, 120, 255)
		sparkles.Parent = ball
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(200, 140, 255)
		light.Brightness = 3
		light.Range = 24
		light.Parent = ball
	end,
}

-- ══════════ Auf-/Abbau ══════════

-- Deko eines Spielers passend zum Profil neu aufbauen
local function rebuildDeco(player: Player)
	local entry = state[player]
	if not entry then
		return
	end
	entry.Folder:ClearAllChildren()
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local housing = ensureFields(profile)
	for slotIndex, offset in Config.DecoSlots do
		local decoId = housing.Slots[tostring(slotIndex)]
		local builder = decoId and BUILDERS[decoId]
		if builder then
			builder(entry.Folder, entry.Base.Slot * CFrame.new(offset.X, 1, offset.Z))
		end
	end
end

-- Deko-Pad neben dem Tresor: öffnet das Housing-UI (nur für den Besitzer)
local function buildPad(player: Player, base): Part
	local pad = Instance.new("Part")
	pad.Name = "DecoPad"
	pad.Anchored = true
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.5, 7, 7)
	-- Hinter dem Tresor, zwischen den Zaunpfosten (links wäre das Hort-Grid im Weg)
	pad.CFrame = base.Slot * CFrame.new(5, 1.25, 20) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = Color3.fromRGB(255, 130, 200)
	pad.Material = Enum.Material.Neon

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🏡 BASIS-DEKO"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 180, 225)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = pad

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Deko aussuchen!"
	prompt.ObjectText = "Basis-Deko"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(function(who)
		if who == player then
			openShopRemote:FireClient(who, "Housing")
		else
			notifyRemote:FireClient(who, "😅 Deko darf nur der Basis-Besitzer umstellen!")
		end
	end)

	pad.Parent = housingFolder
	return pad
end

local function teardown(player: Player)
	local entry = state[player]
	if entry then
		entry.Folder:Destroy()
		entry.Pad:Destroy()
		state[player] = nil
	end
end

-- ══════════ Remote-Handler (Server validiert alles) ══════════

local function buyDeco(player: Player, decoId: any)
	if typeof(decoId) ~= "string" or not Config.DecorationsById[decoId] then
		return { ok = false, msg = "Unbekanntes Deko-Objekt." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	local housing = ensureFields(profile)
	local def = Config.DecorationsById[decoId]
	if housing.Owned[decoId] then
		return { ok = false, msg = "Hast du schon – setz es in einen Slot!" }
	end
	if not PlayerService.TrySpend(player, def.Cost) then
		return { ok = false, msg = ("Zu wenig Cash! (%d💰 nötig)"):format(def.Cost) }
	end
	housing.Owned[decoId] = true
	sfxRemote:FireClient(player, "ding")
	return { ok = true, msg = ("%s gekauft! Jetzt in einen Slot setzen."):format(def.Name) }
end

local function placeDeco(player: Player, slotIndex: any, decoId: any)
	if typeof(slotIndex) ~= "number" or not Config.DecoSlots[slotIndex] then
		return { ok = false, msg = "Ungültiger Slot." }
	end
	if typeof(decoId) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	local housing = ensureFields(profile)

	if decoId ~= "" then
		if not Config.DecorationsById[decoId] then
			return { ok = false, msg = "Unbekanntes Deko-Objekt." }
		end
		if not housing.Owned[decoId] then
			return { ok = false, msg = "Das gehört dir (noch) nicht – erst kaufen!" }
		end
	end

	housing.Slots[tostring(slotIndex)] = if decoId == "" then nil else decoId
	rebuildDeco(player)

	if decoId == "" then
		return { ok = true, msg = ("Slot %d ist jetzt leer."):format(slotIndex) }
	end
	return { ok = true, msg = ("%s steht jetzt in Slot %d!"):format(Config.DecorationsById[decoId].Name, slotIndex) }
end

local function getHousing(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local housing = ensureFields(profile)
	return {
		Owned = housing.Owned,
		Slots = housing.Slots,
		SlotCount = #Config.DecoSlots,
		HasBase = BaseService.GetBaseOf(player) ~= nil,
	}
end

-- ══════════ Init ══════════

function HousingService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	BaseService = services.BaseService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent
	openShopRemote = Remotes.Get("OpenShop") :: RemoteEvent;

	(Remotes.Get("BuyDeco") :: RemoteFunction).OnServerInvoke = buyDeco;
	(Remotes.Get("PlaceDeco") :: RemoteFunction).OnServerInvoke = placeDeco;
	(Remotes.Get("GetHousing") :: RemoteFunction).OnServerInvoke = getHousing

	housingFolder = Instance.new("Folder")
	housingFolder.Name = "Housing"
	housingFolder.Parent = workspace

	Players.PlayerRemoving:Connect(teardown)

	-- Watch-Schleife: Basis beansprucht? -> Pad + gespeicherte Deko aufbauen.
	-- (BaseService hat kein "Claimed"-Event, und wir bauen ihn nicht um –
	-- ein 2-Sekunden-Poll ist für 8 Spieler völlig ausreichend.)
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				local base = BaseService.GetBaseOf(player)
				local entry = state[player]
				if base and not entry then
					local folder = Instance.new("Folder")
					folder.Name = "Deco_" .. player.Name
					folder.Parent = housingFolder
					state[player] = { Base = base, Folder = folder, Pad = buildPad(player, base) }
					-- Erst aufbauen, wenn die Daten wirklich da sind
					task.spawn(function()
						DataService.WaitFor(player)
						if state[player] then
							rebuildDeco(player)
						end
					end)
				elseif not base and entry then
					teardown(player)
				end
			end
		end
	end)
end

return HousingService
