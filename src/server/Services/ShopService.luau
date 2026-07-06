--[[
	ShopService.luau
	Upgrades kaufen + Sugar-Rush-Rebirth.
	Alle Preise/Effekte kommen aus Config – der Client rechnet die Anzeige
	selbst aus, aber bezahlt und validiert wird IMMER hier auf dem Server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ShopService = {}

local DataService, PlayerService, BaseService, SeasonPassService -- in Init verdrahtet
local announceRemote: RemoteEvent

local function buyUpgrade(player: Player, upgradeName: any)
	if typeof(upgradeName) ~= "string" or not Config.Upgrades[upgradeName] then
		return { ok = false, msg = "Unbekanntes Upgrade." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end

	local def = Config.Upgrades[upgradeName]
	local level = profile.Upgrades[upgradeName] or 0
	if level >= def.MaxLevel then
		return { ok = false, msg = "Maximales Level erreicht!" }
	end

	local cost = Config.UpgradeCost(upgradeName, level)
	if not PlayerService.TrySpend(player, cost) then
		return { ok = false, msg = ("Zu wenig Cash! (%d💰 nötig)"):format(cost) }
	end

	profile.Upgrades[upgradeName] = level + 1
	PlayerService.Sync(player)

	-- Effekte sofort anwenden
	if upgradeName == "Tempo" then
		PlayerService.ApplySpeed(player)
	elseif upgradeName == "Schloss" then
		BaseService.RefreshLock(player)
	end

	return { ok = true, msg = ("%s ist jetzt Level %d!"):format(def.Label, level + 1) }
end

local function doRebirth(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end

	local cost = Config.RebirthCost(profile.Rebirths)
	if profile.Cash < cost then
		return { ok = false, msg = ("Du brauchst %d💰 für den Sugar Rush!"):format(cost) }
	end

	-- Reset: Cash + Upgrades weg – und der Tresor springt AUF!
	-- Die Snacks werden befreit und fliegen aus der Basis (Chaos-Moment:
	-- jeder darf sie sich schnappen, auch der frisch Rebirthte selbst).
	profile.Cash = Config.StartCash
	for name in profile.Upgrades do
		profile.Upgrades[name] = 0
	end
	profile.BaseLevel = 1 -- Tycoon-Ausbau ist auch weg – zurück ins Camp!
	profile.Rebirths += 1
	local freed = BaseService.ReleaseVaultSnacks(player)

	PlayerService.Sync(player)
	PlayerService.ApplySpeed(player)
	BaseService.RefreshLock(player)
	BaseService.RefreshBuildout(player) -- Deko abreißen + Anzeige neu (Multiplikator/Level)
	SeasonPassService.AddXp(player, "Rebirth") -- dicker Season-Pass-Schub für den Meilenstein

	announceRemote:FireAllClients(
		("🌟 SUGAR RUSH! %s hat Rebirth #%d erreicht! (+%d%% Einkommen)"):format(
			player.Name,
			profile.Rebirths,
			profile.Rebirths * Config.RebirthBonus * 100
		),
		"Mythic"
	)
	if freed > 0 then
		announceRemote:FireAllClients(
			("💥 %ss Tresor ist AUFGESPRUNGEN – %d Snacks liegen frei rum! SCHNAPPT SIE EUCH!"):format(player.Name, freed),
			"Legendary"
		)
	end
	return { ok = true, msg = ("Sugar Rush #%d! Einkommen x%.1f – dein Tresor wurde befreit!"):format(profile.Rebirths, 1 + profile.Rebirths * Config.RebirthBonus) }
end

-- Für das Debug-Menü exportiert: nimmt den GANZ NORMALEN Rebirth-Pfad
-- (DebugService füllt vorher nur das Cash auf – Kostenlogik bleibt unberührt)
ShopService.DebugDoRebirth = doRebirth

function ShopService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	BaseService = services.BaseService
	SeasonPassService = services.SeasonPassService
	announceRemote = Remotes.Get("Announce") :: RemoteEvent;

	(Remotes.Get("BuyUpgrade") :: RemoteFunction).OnServerInvoke = buyUpgrade;
	(Remotes.Get("DoRebirth") :: RemoteFunction).OnServerInvoke = doRebirth
end

return ShopService
