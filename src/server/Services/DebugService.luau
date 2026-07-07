--[[
	DebugService.luau
	Test-/Debug-Menü NUR für Entwickler:
	- Im Studio immer aktiv
	- Auf Live-Servern nur für UserIds in Config.DebugUserIds (+ Spiel-Besitzer)
	- Der Server prüft die Berechtigung bei JEDEM Aufruf (das Client-UI ist nur Deko)

	Das Menü ist in KATEGORIEN gegliedert (Tabs im Client-UI):
	  "Spieler"  – wirkt auf ein wählbares ZIEL (Standard: man selbst)
	  "Events"   – Trucks/Golden Snack/Timer/Season
	  "Diagnose" – serverseitig nur Datenquellen (inspect/logs), die
	               Anzeige-Tools (Zonen, Panels, Perf-HUD) leben im Client
	  "Server"   – serverweite Aktionen (Danger-Commands mit Bestätigung)

	══════════════════════════════════════════════════════════════════
	NEUEN COMMAND HINZUFÜGEN (z.B. für Tresor-/Rebirth-Features):
	Einfach einen Eintrag an die COMMANDS-Liste unten anhängen:

		{
			Id = "MeinCommand",        -- eindeutige Id (kommt vom Client zurück)
			Label = "🔧 Mein Command", -- Button-Beschriftung im UI
			Category = "Spieler",      -- "Spieler" | "Events" | "Diagnose" | "Server"
			Danger = true,             -- optional: Client fragt "Wirklich?" nach
			Arg = { Default = 100 },   -- optional: Zahlen-Eingabefeld im UI
			Handler = function(caller, target, services, value)
				-- caller  = der Entwickler, der den Button gedrückt hat
				-- target  = das im UI gewählte Ziel (Standard: caller!)
				-- services = Services-Tabelle aus Main.server.lua
				-- value   = Zahl aus dem Eingabefeld (nur wenn Arg gesetzt)
				return "Toast-Text für den Entwickler"
			end,
		}

	Das Client-UI (Ui.luau -> buildDebugMenu) holt die Liste per
	DebugCommand("list") und generiert Tabs/Buttons/Eingaben automatisch –
	KEINE UI-Änderung nötig!
	══════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local Stats = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DebugService = {}

local servicesRef -- die komplette Services-Tabelle (in Init verdrahtet)

local CATEGORY_ORDER = { "Spieler", "Events", "Diagnose", "Server" }

-- God-Mode-Merkliste (überlebt Respawns, siehe CharacterAdded-Hook in Init)
local godMode: { [Player]: boolean } = {}

-- Ringpuffer für die Diagnose-Panels
local LOG_LIMIT = 20
local REMOTE_LOG_LIMIT = 15
local serverLogs: { { Time: string, Type: string, Text: string } } = {}
local remoteLogs: { { Time: string, Name: string, From: string, Args: string } } = {}

-- ══════════ Berechtigung ══════════

-- Gruppen-Rang-Checks sind Web-Calls -> Ergebnis pro Spieler cachen
local groupRankCache: { [Player]: boolean } = {}

local function isDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.DebugUserIds, player.UserId) then
		return true
	end
	-- Der SPIEL-BESITZER ist immer Admin – auch live, ohne Whitelist-Eintrag
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if game.CreatorType == Enum.CreatorType.Group then
		if groupRankCache[player] == nil then
			local isAdmin = false
			local ok, groups = pcall(function()
				local GroupService = game:GetService("GroupService")
				return GroupService:GetGroupsAsync(player.UserId)
			end)
			if ok and typeof(groups) == "table" then
				for _, group in groups do
					if group.Id == game.CreatorId and group.Rank >= 254 then
						isAdmin = true -- Besitzer/Admins der Gruppe
						break
					end
				end
			end
			groupRankCache[player] = isAdmin
		end
		return groupRankCache[player] == true
	end
	return false
end

-- ══════════ Kleine Helfer ══════════

local function applyGodMode(target: Player)
	local character = target.Character
	if not character then
		return
	end
	local existing = character:FindFirstChild("DebugGodMode")
	if godMode[target] then
		if not existing then
			local field = Instance.new("ForceField")
			field.Name = "DebugGodMode"
			field.Visible = true
			field.Parent = character
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	elseif existing then
		existing:Destroy()
	end
end

local function teleportTo(target: Player, position: Vector3): string
	local character = target.Character
	if not character then
		return "Ziel hat gerade keinen Charakter."
	end
	character:PivotTo(CFrame.new(position))
	return ("%s teleportiert."):format(target.Name)
end

-- ══════════ Die Command-Registry ══════════

local COMMANDS = {
	-- ═════════════ Kategorie: SPIELER (wirkt aufs gewählte Ziel) ═════════════
	{
		Id = "SetCash",
		Label = "💰 Cash SETZEN auf ...",
		Category = "Spieler",
		Arg = { Default = 100000 },
		Handler = function(_caller, target, services, value)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			profile.Cash = math.max(0, math.floor(value))
			services.PlayerService.Sync(target)
			return ("Cash von %s = %d💰"):format(target.Name, profile.Cash)
		end,
	},
	{
		Id = "AddCash",
		Label = "💰 Cash ADDIEREN ...",
		Category = "Spieler",
		Arg = { Default = 10000 },
		Handler = function(_caller, target, services, value)
			services.PlayerService.AddCash(target, math.floor(value))
			return ("%+d💰 für %s!"):format(value, target.Name)
		end,
	},
	{
		Id = "GodMode",
		Label = "🛡️ God Mode togglen",
		Category = "Spieler",
		Handler = function(_caller, target, _services)
			godMode[target] = not godMode[target]
			applyGodMode(target)
			return godMode[target] and ("%s ist jetzt UNVERWUNDBAR (ForceField)."):format(target.Name)
				or ("%s ist wieder sterblich."):format(target.Name)
		end,
	},
	{
		Id = "SpeedBoost",
		Label = "👟 Speed-Boost (3x) togglen",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local active = target:GetAttribute("DebugSpeedBoost") == true
			target:SetAttribute("DebugSpeedBoost", if active then nil else true)
			services.PlayerService.ApplySpeed(target) -- Wrapper unten rechnet den Boost drauf
			return active and ("Speed-Boost für %s AUS."):format(target.Name)
				or ("Speed-Boost für %s AN (3x)."):format(target.Name)
		end,
	},
	{
		Id = "VaultClear",
		Label = "🗑️ Tresor LEEREN",
		Category = "Spieler",
		Danger = true,
		Handler = function(_caller, target, services)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			local count = #profile.Vault
			table.clear(profile.Vault)
			services.BaseService.RefreshDisplay(target)
			return ("Tresor von %s geleert (%d Snacks weg)."):format(target.Name, count)
		end,
	},
	{
		Id = "VaultFillTypes",
		Label = "🍫 Tresor: jede Snack-Sorte 1x",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			-- Bewusst am Limit vorbei (UI-Test mit vollem/übervollem Tresor!)
			local added = 0
			for _, def in SnackTypes.List do
				table.insert(profile.Vault, def.Name)
				added += 1
			end
			for _, def in SnackTypes.SupremeList do
				table.insert(profile.Vault, def.Name)
				added += 1
			end
			services.BaseService.RefreshDisplay(target)
			return ("+%d Snacks (alle Sorten) in %ss Tresor – Limit bewusst ignoriert."):format(added, target.Name)
		end,
	},
	{
		Id = "FillVault",
		Label = "🏦 Tresor +20 zufällige Snacks",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local added = 0
			for _ = 1, 20 do
				if services.BaseService.AddToVault(target, SnackTypes.RollRandom().Name) then
					added += 1
				end
			end
			if added < 20 then
				return ("+%d Snacks – dann war der Tresor VOLL (Limit-Test geglückt!)"):format(added)
			end
			return ("+20 zufällige Snacks für %s!"):format(target.Name)
		end,
	},
	{
		Id = "SetRebirths",
		Label = "🌟 Rebirths SETZEN auf ...",
		Category = "Spieler",
		Arg = { Default = 1 },
		Handler = function(_caller, target, services, value)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			profile.Rebirths = math.max(0, math.floor(value))
			services.PlayerService.Sync(target)
			services.BaseService.RefreshDisplay(target)
			return ("%s hat jetzt Rebirth %d (x%.1f Einkommen)."):format(
				target.Name,
				profile.Rebirths,
				services.DataService.GetMultiplier(target)
			)
		end,
	},
	{
		Id = "ForceRebirth",
		Label = "🌟 Rebirth erzwingen (normaler Pfad)",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			-- Fehlendes Cash auffüllen, dann den GANZ NORMALEN Rebirth-Pfad nehmen
			-- (Kostenlogik bleibt unangetastet – wichtig für Kollegen-Features!)
			local cost = Config.RebirthCost(profile.Rebirths)
			if profile.Cash < cost then
				services.PlayerService.AddCash(target, cost - profile.Cash)
			end
			local result = services.ShopService.DebugDoRebirth(target)
			return result and result.msg or "Rebirth ausgeführt."
		end,
	},
	{
		Id = "GiveAllPets",
		Label = "🐾 ALLE Pets geben (je 1x)",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			local count = 0
			for _, def in Config.EggPets do
				if not profile.Pets[def.Id] then
					profile.Pets[def.Id] = true
					count += 1
				end
			end
			return ("%d neue Pets für %s – Gacha-RNG umgangen!"):format(count, target.Name)
		end,
	},
	{
		Id = "FreeEgg",
		Label = "🥚 Gratis Gold-Ei",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local result = services.PetService.GrantEgg(target, "Golden")
			return result.msg or "Ei geöffnet!"
		end,
	},
	{
		Id = "UnlockStyle",
		Label = "🎨 Alle Skins & Trails freischalten",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			for _, def in Config.Skins do
				profile.Skins[def.Id] = true
			end
			for _, def in Config.Trails do
				profile.Trails[def.Id] = true
			end
			return ("Alle Skins & Trails für %s – Fashion-Show!"):format(target.Name)
		end,
	},
	{
		Id = "BaseLevelUp",
		Label = "⬆️ Basis-Level +1 (gratis)",
		Category = "Spieler",
		Handler = function(_caller, target, services)
			local profile = services.DataService.Get(target)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			if not services.BaseService.GetBaseOf(target) then
				return "Ziel muss erst eine Basis beanspruchen!"
			end
			if profile.BaseLevel >= #Config.BaseLevels then
				return "Basis ist schon MAX ausgebaut."
			end
			profile.BaseLevel += 1
			services.BaseService.RefreshBuildout(target)
			services.PlayerService.Sync(target)
			return ("Basis-Level %d: %s"):format(profile.BaseLevel, Config.BaseLevelDef(profile.BaseLevel).Label)
		end,
	},

	-- ═════════════ Kategorie: EVENTS ═════════════
	{
		Id = "TruckNow",
		Label = "🚚 Normaler Truck JETZT",
		Category = "Events",
		Handler = function(_caller, _target, services)
			services.TruckService.DebugTruckNow()
			return "Schoko-Truck ist unterwegs!"
		end,
	},
	{
		Id = "RushHourNow",
		Label = "🚚🚚 Rush Hour JETZT",
		Category = "Events",
		Handler = function(_caller, _target, services)
			services.TruckService.DebugRushHourNow()
			return "RUSH HOUR – zwei Trucks im Anflug!"
		end,
	},
	{
		Id = "SupremeNow",
		Label = "☢️ Supreme-Event JETZT",
		Category = "Events",
		Handler = function(_caller, _target, services)
			services.TruckService.DebugSupremeNow()
			return "Mutanten-Express ist unterwegs!"
		end,
	},
	{
		Id = "GoldenNow",
		Label = "🌟 Goldener Snack JETZT",
		Category = "Events",
		Handler = function(_caller, _target, services)
			services.GoldenSnackService.DebugSpawnNow()
			return "Goldener Snack gespawnt – hinterher!"
		end,
	},
	{
		Id = "SkipTruckTimer",
		Label = "⏩ Truck-Timer überspringen",
		Category = "Events",
		Handler = function(_caller, _target, services)
			services.TruckService.DebugSkipTimer()
			return "Truck-Wartezeit übersprungen – Event-Schleife läuft weiter."
		end,
	},
	{
		Id = "SupremeNext",
		Label = "☢️ Supreme-Zähler auf 0",
		Category = "Events",
		Handler = function(_caller, _target, services)
			services.TruckService.DebugSupremeNext()
			return "Der NÄCHSTE reguläre Truck ist der Mutanten-Express!"
		end,
	},
	{
		Id = "ResetCooldowns",
		Label = "🔄 Cooldowns des Ziels resetten",
		Category = "Events",
		Handler = function(_caller, target, services)
			services.SlapService.DebugResetCooldown(target)
			return ("Slap-Cooldown von %s zurückgesetzt. (Yeet-Charge & Merge haben keine Cooldowns.)"):format(target.Name)
		end,
	},
	{
		Id = "SeasonXp",
		Label = "🎫 Season-XP geben ...",
		Category = "Events",
		Arg = { Default = 500 },
		Handler = function(_caller, target, services, value)
			services.SeasonPassService.DebugAddXp(target, math.floor(value))
			return ("%+d Season-XP für %s!"):format(value, target.Name)
		end,
	},
	{
		Id = "SeasonPremium",
		Label = "👑 Premium-Pass togglen",
		Category = "Events",
		Handler = function(_caller, target, services)
			local nowPremium = services.SeasonPassService.DebugTogglePremium(target)
			return nowPremium and "Premium-Pass AN (Test) – Belohnungen kommen rückwirkend!" or "Premium-Pass AUS (Test)."
		end,
	},
	{
		Id = "SeasonOverride",
		Label = "📅 Season-Zeitfenster durchschalten",
		Category = "Events",
		Handler = function(_caller, _target, services)
			return services.SeasonPassService.DebugCycleSeasonOverride()
		end,
	},

	-- ═════════════ Kategorie: SERVER ═════════════
	{
		Id = "ClearSnacks",
		Label = "🧹 Lose Snacks aufräumen",
		Category = "Server",
		Handler = function(_caller, _target, services)
			local count = services.SnackService.ClearLoose()
			return ("%d lose Snacks entsorgt."):format(count)
		end,
	},
	{
		Id = "ClearAllVaults",
		Label = "💣 ALLE Tresore leeren",
		Category = "Server",
		Danger = true,
		Handler = function(_caller, _target, services)
			local total = 0
			for _, player in Players:GetPlayers() do
				local profile = services.DataService.Get(player)
				if profile then
					total += #profile.Vault
					table.clear(profile.Vault)
					services.BaseService.RefreshDisplay(player)
				end
			end
			return ("Alle Tresore geleert – %d Snacks im Datennirvana."):format(total)
		end,
	},
	{
		Id = "ForceSave",
		Label = "💾 DataStore-Save fürs Ziel erzwingen",
		Category = "Server",
		Handler = function(_caller, target, services)
			local ok, err = services.DataService.ForceSave(target)
			if ok then
				return ("Profil von %s erfolgreich gespeichert ✅"):format(target.Name)
			end
			return ("Speichern FEHLGESCHLAGEN: %s"):format(err or "?")
		end,
	},
}

-- ══════════ Liste fürs Client-UI (inkl. dynamischer Teleport-Ziele) ══════════

-- Teleport-Ziele hängen vom Live-Zustand ab (Basis-Besitzer!) und werden
-- deshalb bei jedem "list"-Aufruf frisch generiert. Ids: Tp_Base_<n>,
-- Tp_Shop_<shopId>, Tp_Truck – aufgelöst in resolveTeleport().
local function buildTeleportCommands(): { any }
	local list = {}

	-- Basis-Besitzer einsammeln (nur LESEND über GetBaseOf)
	local owners: { [number]: string } = {}
	for _, player in Players:GetPlayers() do
		local base = servicesRef.BaseService.GetBaseOf(player)
		if base then
			owners[base.Index] = player.Name
		end
	end
	for index in servicesRef.MapSlots do
		table.insert(list, {
			Id = "Tp_Base_" .. index,
			Label = ("🏠 TP: Basis %d%s"):format(index, owners[index] and (" – " .. owners[index]) or " (frei)"),
			Category = "Spieler",
		})
	end
	for _, shopId in { "Upgrade", "Pets", "Style", "Merge" } do
		table.insert(list, {
			Id = "Tp_Shop_" .. shopId,
			Label = ("🏪 TP: %s-Shop"):format(shopId),
			Category = "Spieler",
		})
	end
	table.insert(list, { Id = "Tp_Truck", Label = "🚚 TP: Truck-Startpunkt (Straße West)", Category = "Spieler" })
	return list
end

local function resolveTeleport(id: string): Vector3?
	local baseIndex = id:match("^Tp_Base_(%d+)$")
	if baseIndex then
		local slot = servicesRef.MapSlots[tonumber(baseIndex) :: number]
		if slot then
			-- vor den Tresor, mittig auf die Platte
			return (slot * CFrame.new(0, 6, 0)).Position
		end
		return nil
	end
	local shopId = id:match("^Tp_Shop_(%w+)$")
	if shopId then
		local pos = servicesRef.MapService.GetShopPosition(shopId)
		return pos and pos + Vector3.new(0, 5, 0)
	end
	if id == "Tp_Truck" then
		return Vector3.new(-380, 6, 14) -- Straßenrand am West-Start des Trucks
	end
	return nil
end

-- ══════════ State-Inspector (Diagnose, rein lesend) ══════════

local function inspectPlayer(target: Player): { string }
	local lines = {}
	local function add(fmt: string, ...)
		table.insert(lines, fmt:format(...))
	end

	local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	add("═ %s (UserId %d) ═", target.Name, target.UserId)
	if root then
		add("Position: %.0f, %.0f, %.0f", root.Position.X, root.Position.Y, root.Position.Z)
	else
		add("Position: kein Charakter")
	end

	local profile = servicesRef.DataService.Get(target)
	if profile then
		add("── Profil ──")
		add("Cash: %.1f | Rebirths: %d | TotalYeets: %d", profile.Cash, profile.Rebirths, profile.TotalYeets)
		add("BaseLevel: %d (%s)", profile.BaseLevel, Config.BaseLevelDef(profile.BaseLevel).Label)
		add("Tresor: %d/%d Snacks", #profile.Vault, Config.VaultLimit(profile.Rebirths, profile.BaseLevel))
		local petCount = 0
		for _ in profile.Pets do
			petCount += 1
		end
		add("Pets: %d gesammelt | aktiv: %s", petCount, #profile.EquippedPets > 0 and table.concat(profile.EquippedPets, ", ") or "-")
		add("Season: %d XP | Premium: %s", profile.SeasonPass.Xp, tostring(profile.SeasonPass.Premium))
		add("Skin: %s | Trail: %s", profile.EquippedSkin ~= "" and profile.EquippedSkin or "-", profile.EquippedTrail ~= "" and profile.EquippedTrail or "-")
	else
		add("── Profil: NICHT GELADEN ──")
	end

	add("── Attribute ──")
	local names = {}
	local attributes = target:GetAttributes()
	for name in attributes do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		add("%s = %s", name, tostring(attributes[name]))
	end
	return lines
end

-- ══════════ Remote-Handler ══════════

-- Aufruf-Formen (alle nur für Devs):
--   ("list")                  -> { Categories, Commands }
--   ("inspect", {Target?})    -> { Lines }
--   ("logs")                  -> { Logs, Remotes, MemoryMb }
--   (commandId, {Target?, Value?}) -> { ok, msg }
local function onDebugCommand(player: Player, action: any, payload: any)
	if not isDev(player) then
		return nil -- für Nicht-Entwickler existiert das Menü schlicht nicht
	end
	if typeof(action) ~= "string" then
		return { ok = false, msg = "Ungültiger Command." }
	end
	if typeof(payload) ~= "table" then
		payload = {}
	end

	-- Ziel auflösen (Standard: der Aufrufer selbst)
	local target: Player = player
	if typeof(payload.Target) == "number" then
		local found = Players:GetPlayerByUserId(payload.Target)
		if not found then
			return { ok = false, msg = "Ziel-Spieler ist nicht (mehr) im Server." }
		end
		target = found
	end

	if action == "list" then
		local list = {}
		for _, cmd in COMMANDS do
			table.insert(list, {
				Id = cmd.Id,
				Label = cmd.Label,
				Category = cmd.Category,
				Danger = cmd.Danger == true,
				Arg = cmd.Arg and { Default = cmd.Arg.Default } or nil,
			})
		end
		for _, cmd in buildTeleportCommands() do
			table.insert(list, cmd)
		end
		return { Categories = CATEGORY_ORDER, Commands = list }
	end

	if action == "inspect" then
		return { Lines = inspectPlayer(target) }
	end

	if action == "logs" then
		return {
			Logs = serverLogs,
			Remotes = remoteLogs,
			MemoryMb = math.floor(Stats:GetTotalMemoryUsageMb()),
		}
	end

	-- Teleport-Commands (dynamische Ids)
	if action:sub(1, 3) == "Tp_" then
		local position = resolveTeleport(action)
		if not position then
			return { ok = false, msg = "Unbekanntes Teleport-Ziel: " .. action }
		end
		return { ok = true, msg = teleportTo(target, position) }
	end

	-- Normale Commands
	for _, cmd in COMMANDS do
		if cmd.Id == action then
			local value = nil
			if cmd.Arg then
				value = tonumber(payload.Value) or cmd.Arg.Default
			end
			local msg = cmd.Handler(player, target, servicesRef, value)
			return { ok = true, msg = msg or cmd.Label }
		end
	end
	return { ok = false, msg = "Unbekannter Command: " .. action }
end

-- ══════════ Init ══════════

function DebugService.Init(services)
	servicesRef = services;

	(Remotes.Get("DebugCommand") :: RemoteFunction).OnServerInvoke = onDebugCommand

	-- Speed-Boost: ApplySpeed UMHÜLLEN statt PlayerService zu ändern
	-- (gleiches Pattern wie der Pet-Speed-Wrapper im PetService; Wrapper-Kette ok)
	local baseApplySpeed = services.PlayerService.ApplySpeed
	services.PlayerService.ApplySpeed = function(target: Player)
		baseApplySpeed(target)
		if target:GetAttribute("DebugSpeedBoost") == true then
			local character = target.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.WalkSpeed > 0 then
				humanoid.WalkSpeed *= 3
			end
		end
	end

	-- Server-Logs (Warnings + Errors) für das Debug-Log-Panel abgreifen
	LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
		if messageType ~= Enum.MessageType.MessageWarning and messageType ~= Enum.MessageType.MessageError then
			return
		end
		table.insert(serverLogs, {
			Time = os.date("%H:%M:%S") :: string,
			Type = if messageType == Enum.MessageType.MessageError then "ERROR" else "WARN",
			Text = message:sub(1, 200),
		})
		if #serverLogs > LOG_LIMIT then
			table.remove(serverLogs, 1)
		end
	end)

	-- Remote-Call-Logger: eingehende Client->Server-Events mitschreiben
	-- (zusätzliche Connections stören die eigentlichen Handler nicht)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	for _, remote in remotesFolder:GetChildren() do
		if remote:IsA("RemoteEvent") then
			remote.OnServerEvent:Connect(function(fromPlayer, ...)
				local args = table.pack(...)
				local parts = {}
				for i = 1, math.min(args.n, 3) do
					table.insert(parts, tostring(args[i]))
				end
				table.insert(remoteLogs, {
					Time = os.date("%H:%M:%S") :: string,
					Name = remote.Name,
					From = fromPlayer.Name,
					Args = table.concat(parts, ", "),
				})
				if #remoteLogs > REMOTE_LOG_LIMIT then
					table.remove(remoteLogs, 1)
				end
			end)
		end
	end

	-- Flag fürs Client-UI ("darf ich den Debug-Button zeigen?").
	-- Sicherheit hängt NICHT hieran – jeder Aufruf wird oben erneut geprüft.
	local function mark(player: Player)
		if isDev(player) then
			player:SetAttribute("IsDev", true)
		end
		-- God Mode Respawns überleben lassen
		player.CharacterAdded:Connect(function()
			if godMode[player] then
				task.wait(0.2)
				applyGodMode(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		groupRankCache[player] = nil
		godMode[player] = nil
	end)
end

return DebugService
