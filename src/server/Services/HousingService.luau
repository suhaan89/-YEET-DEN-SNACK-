--[[
	HousingService.luau
	Basis-Deko (Housing light): Spieler kaufen Deko-Objekte (Config.HousingDecor)
	und stellen sie in feste Slots rund um die eigene Basis
	(Config.HousingSlotOffsets) – kein freies Bausystem.

	- Eigener DataStore (Config.HousingDataStore): Owned-Set + Slot-Belegung
	  pro Spieler, wird beim nächsten Join automatisch wieder aufgebaut.
	- BaseService bleibt unangetastet: die Basis wird nur über
	  BaseService.GetBaseOf(player) GELESEN (Slot-CFrame). Neu-Beanspruchen
	  erkennt der Service am "VaultPos"-Attribut (setzt BaseService beim Claim).
	- Alle Deko-Parts sind anchored + CanCollide=false -> reine Optik,
	  blockiert nie YEETs oder Slaps.
	- Server validiert alles: Kosten, Besitz, Slot-Limit, eigene Basis.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HousingService = {}

local PlayerService, BaseService -- in Init verdrahtet

local notifyRemote: RemoteEvent
local sfxRemote: RemoteEvent

local store = nil
-- { Owned = {[decorId]=true}, Slots = {"", "", ...} } ("" = Slot leer)
local records: { [Player]: any } = {}
local decoFolders: { [Player]: Folder } = {}

local function defaultRecord()
	local slots = {}
	for _ = 1, #Config.HousingSlotOffsets do
		table.insert(slots, "")
	end
	return { Owned = {}, Slots = slots }
end

-- ══════════ Deko-Bauer (Platzhalter-Parts, wie der Rest der Map) ══════════

local function makeDecoPart(parent: Instance, props: { [string]: any }): Part
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

-- Ein Bau-Rezept pro Deko-Id; cf = Boden-CFrame des Slots
local BUILDERS: { [string]: (parent: Instance, cf: CFrame) -> () } = {
	Zuckerstange = function(parent, cf)
		makeDecoPart(parent, { Size = Vector3.new(0.8, 7, 0.8), CFrame = cf * CFrame.new(0, 3.5, 0), Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic })
		for i = 0, 2 do
			makeDecoPart(parent, { Size = Vector3.new(1, 0.7, 1), CFrame = cf * CFrame.new(0, 1.5 + i * 2, 0), Color = Color3.fromRGB(255, 70, 70), Material = Enum.Material.SmoothPlastic })
		end
		local top = makeDecoPart(parent, { Size = Vector3.new(1.6, 1.6, 1.6), CFrame = cf * CFrame.new(0, 7.5, 0), Color = Color3.fromRGB(255, 70, 70), Material = Enum.Material.SmoothPlastic })
		top.Shape = Enum.PartType.Ball
	end,
	Fahne = function(parent, cf)
		makeDecoPart(parent, { Size = Vector3.new(0.5, 9, 0.5), CFrame = cf * CFrame.new(0, 4.5, 0), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal })
		makeDecoPart(parent, { Size = Vector3.new(3.2, 2, 0.25), CFrame = cf * CFrame.new(1.8, 7.8, 0), Color = Color3.fromRGB(255, 150, 200), Material = Enum.Material.Neon })
	end,
	Lolli = function(parent, cf)
		makeDecoPart(parent, { Size = Vector3.new(0.7, 8, 0.7), CFrame = cf * CFrame.new(0, 4, 0), Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic })
		local head = makeDecoPart(parent, { Size = Vector3.new(4.5, 4.5, 4.5), CFrame = cf * CFrame.new(0, 9.5, 0), Color = Color3.fromRGB(255, 90, 220), Material = Enum.Material.Neon })
		head.Shape = Enum.PartType.Ball
	end,
	Lampe = function(parent, cf)
		makeDecoPart(parent, { Size = Vector3.new(0.6, 6, 0.6), CFrame = cf * CFrame.new(0, 3, 0), Color = Color3.fromRGB(60, 55, 70), Material = Enum.Material.Metal })
		local bulb = makeDecoPart(parent, { Size = Vector3.new(2.2, 2.2, 2.2), CFrame = cf * CFrame.new(0, 6.8, 0), Color = Color3.fromRGB(255, 170, 220), Material = Enum.Material.Neon })
		bulb.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 220)
		light.Brightness = 2
		light.Range = 18
		light.Parent = bulb
	end,
	Gummibaer = function(parent, cf)
		local color = Color3.fromRGB(255, 80, 80)
		local body = makeDecoPart(parent, { Size = Vector3.new(3.4, 3.4, 3.4), CFrame = cf * CFrame.new(0, 1.9, 0), Color = color, Material = Enum.Material.Neon, Transparency = 0.25 })
		body.Shape = Enum.PartType.Ball
		local head = makeDecoPart(parent, { Size = Vector3.new(2.4, 2.4, 2.4), CFrame = cf * CFrame.new(0, 4.6, 0), Color = color, Material = Enum.Material.Neon, Transparency = 0.25 })
		head.Shape = Enum.PartType.Ball
		for _, x in { -1, 1 } do
			local ear = makeDecoPart(parent, { Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(x, 5.9, 0), Color = color, Material = Enum.Material.Neon, Transparency = 0.25 })
			ear.Shape = Enum.PartType.Ball
		end
	end,
	Donut = function(parent, cf)
		makeDecoPart(parent, { Size = Vector3.new(0.6, 6, 0.6), CFrame = cf * CFrame.new(0, 3, 0), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal })
		local ring = makeDecoPart(parent, { Size = Vector3.new(1, 5.5, 5.5), CFrame = cf * CFrame.new(0, 8, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 150, 200), Material = Enum.Material.Neon })
		ring.Shape = Enum.PartType.Cylinder
		local sprinkles = Instance.new("Sparkles")
		sprinkles.SparkleColor = Color3.fromRGB(255, 255, 160)
		sprinkles.Parent = ring
	end,
	Brunnen = function(parent, cf)
		local basin = makeDecoPart(parent, { Size = Vector3.new(1, 6, 6), CFrame = cf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(110, 65, 30), Material = Enum.Material.SmoothPlastic })
		basin.Shape = Enum.PartType.Cylinder
		local column = makeDecoPart(parent, { Size = Vector3.new(1, 3, 1), CFrame = cf * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(90, 55, 25), Material = Enum.Material.SmoothPlastic })
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 1.6, 0)
		attachment.Parent = column
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(120, 72, 30))
		emitter.Speed = NumberRange.new(6, 10)
		emitter.Lifetime = NumberRange.new(0.6, 1)
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.Size = NumberSequence.new(0.45)
		emitter.Rate = 14
		emitter.Parent = attachment
	end,
	Disco = function(parent, cf)
		makeDecoPart(parent, { Size = Vector3.new(0.5, 8, 0.5), CFrame = cf * CFrame.new(0, 4, 0), Color = Color3.fromRGB(60, 55, 70), Material = Enum.Material.Metal })
		local ball = makeDecoPart(parent, { Size = Vector3.new(3, 3, 3), CFrame = cf * CFrame.new(0, 9, 0), Color = Color3.fromRGB(180, 120, 255), Material = Enum.Material.Glass, Reflectance = 0.6 })
		ball.Shape = Enum.PartType.Ball
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(180, 120, 255)
		sparkles.Parent = ball
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(180, 120, 255)
		light.Brightness = 3
		light.Range = 24
		light.Parent = ball
	end,
}

-- ══════════ Aufbau/Abriss ══════════

-- Baut die komplette Deko eines Spielers passend zur Slot-Belegung neu auf
local function rebuild(player: Player)
	local old = decoFolders[player]
	if old then
		old:Destroy()
		decoFolders[player] = nil
	end

	local record = records[player]
	local base = BaseService.GetBaseOf(player)
	if not record or not base then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "PlayerDeco_" .. player.UserId
	for slotIndex, decorId in record.Slots do
		local builder = BUILDERS[decorId]
		local offset = Config.HousingSlotOffsets[slotIndex]
		if decorId ~= "" and builder and offset then
			-- Slot-CFrame: auf der Bodenplatte (y=1) der Basis
			builder(folder, base.Slot * CFrame.new(offset.X, 1, offset.Z))
		end
	end
	folder.Parent = workspace:FindFirstChild("Map") or workspace
	decoFolders[player] = folder
end

-- ══════════ Laden/Speichern ══════════

local function load(player: Player)
	local record = defaultRecord()
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("House_" .. player.UserId)
		end)
		if ok and typeof(saved) == "table" then
			if typeof(saved.Owned) == "table" then
				record.Owned = saved.Owned
			end
			if typeof(saved.Slots) == "table" then
				for i = 1, #Config.HousingSlotOffsets do
					local decorId = saved.Slots[i]
					-- Gelöschte/umbenannte Config-Einträge leeren den Slot
					if typeof(decorId) == "string" and Config.HousingDecorById[decorId] then
						record.Slots[i] = decorId
					end
				end
			end
		elseif not ok then
			warn("[HousingService] Laden fehlgeschlagen für", player.Name, saved)
		end
	end
	records[player] = record
	rebuild(player)
end

local function save(player: Player)
	local record = records[player]
	if not record or not store then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("House_" .. player.UserId, record)
	end)
	if not ok then
		warn("[HousingService] Speichern fehlgeschlagen für", player.Name, err)
	end
end

-- ══════════ Remote-Handler (Server validiert alles) ══════════

local function getHousing(player: Player)
	local record = records[player]
	if not record then
		return nil
	end
	return {
		Owned = record.Owned,
		Slots = record.Slots,
		HasBase = BaseService.GetBaseOf(player) ~= nil,
		SlotCount = #Config.HousingSlotOffsets,
	}
end

local function buyDecor(player: Player, decorId: any)
	if typeof(decorId) ~= "string" or not Config.HousingDecorById[decorId] then
		return { ok = false, msg = "Unbekanntes Deko-Objekt." }
	end
	local record = records[player]
	if not record then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	local def = Config.HousingDecorById[decorId]
	if record.Owned[decorId] then
		return { ok = false, msg = ("%s gehört dir schon!"):format(def.Name) }
	end
	if not PlayerService.TrySpend(player, def.Cost) then
		return { ok = false, msg = ("Zu wenig Cash! (%d💰 nötig)"):format(def.Cost) }
	end
	record.Owned[decorId] = true
	task.spawn(save, player)
	sfxRemote:FireClient(player, "ding")
	return { ok = true, msg = ("%s gekauft – jetzt aufstellen!"):format(def.Name) }
end

local function placeDecor(player: Player, decorId: any, place: any)
	if typeof(decorId) ~= "string" or not Config.HousingDecorById[decorId] then
		return { ok = false, msg = "Unbekanntes Deko-Objekt." }
	end
	local record = records[player]
	if not record then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end
	local def = Config.HousingDecorById[decorId]

	if place == true then
		if not record.Owned[decorId] then
			return { ok = false, msg = "Das gehört dir (noch) nicht – erst kaufen!" }
		end
		if not BaseService.GetBaseOf(player) then
			return { ok = false, msg = "Erst eine Basis beanspruchen ([E] am freien Tresor)!" }
		end
		if table.find(record.Slots, decorId) then
			return { ok = false, msg = ("%s steht schon auf deiner Basis."):format(def.Name) }
		end
		local freeSlot = table.find(record.Slots, "")
		if not freeSlot then
			return { ok = false, msg = ("Alle %d Deko-Plätze belegt – erst was entfernen!"):format(#record.Slots) }
		end
		record.Slots[freeSlot] = decorId
		rebuild(player)
		task.spawn(save, player)
		sfxRemote:FireClient(player, "ding")
		return { ok = true, msg = ("%s aufgestellt! Sieht gut aus."):format(def.Name) }
	else
		local slotIndex = table.find(record.Slots, decorId)
		if not slotIndex then
			return { ok = false, msg = ("%s steht gar nicht auf deiner Basis."):format(def.Name) }
		end
		record.Slots[slotIndex] = ""
		rebuild(player)
		task.spawn(save, player)
		return { ok = true, msg = ("%s eingepackt."):format(def.Name) }
	end
end

-- ══════════ Init ══════════

function HousingService.Init(services)
	PlayerService = services.PlayerService
	BaseService = services.BaseService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	(Remotes.Get("GetHousing") :: RemoteFunction).OnServerInvoke = getHousing;
	(Remotes.Get("BuyDecor") :: RemoteFunction).OnServerInvoke = buyDecor;
	(Remotes.Get("PlaceDecor") :: RemoteFunction).OnServerInvoke = placeDecor

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.HousingDataStore)
	end)
	if ok then
		store = result
	else
		warn("[HousingService] Kein DataStore-Zugriff – Deko wird NICHT gespeichert.")
	end

	local function onPlayerAdded(player: Player)
		task.spawn(load, player)
		-- Basis frisch beansprucht? BaseService setzt dabei "VaultPos" ->
		-- gespeicherte Deko auf der neuen Basis aufbauen (lesend angedockt,
		-- kein Eingriff in BaseService nötig)
		player:GetAttributeChangedSignal("VaultPos"):Connect(function()
			rebuild(player)
			if records[player] then
				local placed = 0
				for _, decorId in records[player].Slots do
					if decorId ~= "" then
						placed += 1
					end
				end
				if placed > 0 then
					notifyRemote:FireClient(player, ("🏡 Deine %d Deko-Objekte wurden wieder aufgebaut!"):format(placed))
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		records[player] = nil
		local folder = decoFolders[player]
		if folder then
			folder:Destroy()
			decoFolders[player] = nil
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(1)
			return
		end
		for player in records do
			save(player)
		end
	end)
end

return HousingService
