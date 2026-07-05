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

local function isDev(player: Player): boolean
	return RunService:IsStudio() or table.find(Config.DebugUserIds, player.UserId) ~= nil
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
		Id = "FillVault",
		Label = "🏦 Tresor +20 Snacks",
		Handler = function(player, services)
			for _ = 1, 20 do
				services.BaseService.AddToVault(player, SnackTypes.RollRandom().Name)
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
end

return DebugService
