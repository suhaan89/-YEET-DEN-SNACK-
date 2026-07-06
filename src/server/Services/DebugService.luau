--[[
	DebugService.luau
	Test-Menü NUR für Entwickler:
	- Im Studio immer aktiv
	- Auf Live-Servern nur für UserIds in Config.DebugUserIds
	- Server prüft die Berechtigung bei JEDEM Aufruf (das Client-UI ist nur Deko)

	══════════════════════════════════════════════════════════════════
	NEUEN COMMAND HINZUFÜGEN (z.B. für Tresor-/Rebirth-Features):
	Einfach einen Eintrag an die COMMANDS-Liste unten anhängen:

		{
			Id = "MeinCommand",         -- eindeutige Id (kommt vom Client zurück)
			Label = "🔧 Mein Command",  -- Button-Beschriftung im UI
			Handler = function(player, services)
				-- `services` = die Services-Tabelle aus Main.server.lua,
				-- also z.B. services.BaseService, services.DataService, ...
				return "Toast-Text für den Entwickler"
			end,
		}

	Das Client-UI (Ui.luau -> buildDebugMenu) holt sich die Liste per
	DebugCommand("list") und generiert die Buttons automatisch –
	KEINE UI-Änderung nötig!
	══════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DebugService = {}

local servicesRef -- die komplette Services-Tabelle (in Init verdrahtet)

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

local COMMANDS = {
	{
		Id = "AddCash",
		Label = "💰 +10.000 Cash",
		Handler = function(player, services)
			services.PlayerService.AddCash(player, 10000)
			return "+10.000💰 aufs Konto!"
		end,
	},
	{
		Id = "AddCash1M",
		Label = "🤑 +1 Mio Cash",
		Handler = function(player, services)
			services.PlayerService.AddCash(player, 1_000_000)
			return "+1.000.000💰 – Geld spielt keine Rolle!"
		end,
	},
	{
		Id = "BaseLevelUp",
		Label = "⬆️ Basis-Level +1 (gratis)",
		Handler = function(player, services)
			local profile = services.DataService.Get(player)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			if not services.BaseService.GetBaseOf(player) then
				return "Erst eine Basis beanspruchen!"
			end
			if profile.BaseLevel >= #Config.BaseLevels then
				return "Basis ist schon MAX ausgebaut."
			end
			profile.BaseLevel += 1
			services.BaseService.RefreshBuildout(player)
			services.PlayerService.Sync(player)
			return ("Basis-Level %d: %s"):format(profile.BaseLevel, Config.BaseLevelDef(profile.BaseLevel).Label)
		end,
	},
	{
		Id = "ClearSnacks",
		Label = "🧹 Lose Snacks aufräumen",
		Handler = function(_player, services)
			local count = services.SnackService.ClearLoose()
			return ("%d lose Snacks entsorgt."):format(count)
		end,
	},
	{
		Id = "UnlockStyle",
		Label = "🎨 Alle Skins & Trails freischalten",
		Handler = function(player, services)
			local profile = services.DataService.Get(player)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			for _, def in Config.Skins do
				profile.Skins[def.Id] = true
			end
			for _, def in Config.Trails do
				profile.Trails[def.Id] = true
			end
			return "Alle Skins & Trails gehören dir – Fashion-Show!"
		end,
	},
	{
		Id = "ForceRebirth",
		Label = "🌟 Rebirth erzwingen",
		Handler = function(player, services)
			local profile = services.DataService.Get(player)
			if not profile then
				return "Profil noch nicht geladen..."
			end
			-- Fehlendes Cash auffüllen, dann den GANZ NORMALEN Rebirth-Pfad nehmen
			-- (Kostenlogik bleibt unangetastet – wichtig für Kollegen-Features!)
			local cost = Config.RebirthCost(profile.Rebirths)
			if profile.Cash < cost then
				services.PlayerService.AddCash(player, cost - profile.Cash)
			end
			local result = services.ShopService.DebugDoRebirth(player)
			return result and result.msg or "Rebirth ausgeführt."
		end,
	},
	{
		Id = "SupremeNow",
		Label = "☢️ Supreme-Event JETZT",
		Handler = function(_player, services)
			services.TruckService.DebugSupremeNow()
			return "Mutanten-Express ist unterwegs!"
		end,
	},
	{
		Id = "TruckNow",
		Label = "🚚 Normaler Truck JETZT",
		Handler = function(_player, services)
			services.TruckService.DebugTruckNow()
			return "Schoko-Truck ist unterwegs!"
		end,
	},
	{
		Id = "SeasonXp",
		Label = "🎫 +500 Season-XP",
		Handler = function(player, services)
			services.SeasonPassService.DebugAddXp(player, 500)
			return "+500 Season-XP – Stufen prasseln!"
		end,
	},
	{
		Id = "SeasonPremium",
		Label = "👑 Premium-Pass togglen",
		Handler = function(player, services)
			local nowPremium = services.SeasonPassService.DebugTogglePremium(player)
			return nowPremium and "Premium-Pass AN (Test) – Belohnungen kommen rückwirkend!" or "Premium-Pass AUS (Test)."
		end,
	},
	{
		Id = "FreeEgg",
		Label = "🥚 Gratis Gold-Ei",
		Handler = function(player, services)
			local result = services.PetService.GrantEgg(player, "Golden")
			return result.msg or "Ei geöffnet!"
		end,
	},
	{
		Id = "GoldenNow",
		Label = "🌟 Goldener Snack JETZT",
		Handler = function(_player, services)
			services.GoldenSnackService.DebugSpawnNow()
			return "Goldener Snack ist gespawnt – lauf!"
		end,
	},
	{
		Id = "FillVault",
		Label = "🏦 Tresor +20 Snacks",
		Handler = function(player, services)
			local added = 0
			for _ = 1, 20 do
				if services.BaseService.AddToVault(player, SnackTypes.RollRandom().Name) then
					added += 1
				end
			end
			if added < 20 then
				return ("+%d Snacks – dann war der Tresor VOLL (Limit-Test geglückt!)"):format(added)
			end
			return "+20 zufällige Snacks im Tresor!"
		end,
	},
}

local function onDebugCommand(player: Player, commandId: any)
	if not isDev(player) then
		return nil -- für Nicht-Entwickler existiert das Menü schlicht nicht
	end
	if commandId == "list" then
		local list = {}
		for _, cmd in COMMANDS do
			table.insert(list, { Id = cmd.Id, Label = cmd.Label })
		end
		return list
	end
	if typeof(commandId) ~= "string" then
		return { ok = false, msg = "Ungültiger Command." }
	end
	for _, cmd in COMMANDS do
		if cmd.Id == commandId then
			local msg = cmd.Handler(player, servicesRef)
			return { ok = true, msg = msg or cmd.Label }
		end
	end
	return { ok = false, msg = "Unbekannter Command: " .. commandId }
end

function DebugService.Init(services)
	servicesRef = services;

	(Remotes.Get("DebugCommand") :: RemoteFunction).OnServerInvoke = onDebugCommand

	-- Flag fürs Client-UI ("darf ich den Debug-Button zeigen?").
	-- Sicherheit hängt NICHT hieran – jeder Aufruf wird oben erneut geprüft.
	local function mark(player: Player)
		if isDev(player) then
			player:SetAttribute("IsDev", true)
		end
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		groupRankCache[player] = nil
	end)
end

return DebugService
