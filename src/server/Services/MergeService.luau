--[[
	MergeService.luau
	Die MERGE-MASCHINE 3000: 2+ gleiche Tresor-Snacks einwerfen ->
	Zufallschance auf EINEN Snack der nächsthöheren Rarität.
	Bei Misserfolg (Standardfall!) sind ALLE eingesetzten Snacks weg.

	Server validiert ALLES:
	- Spieler steht wirklich an der Merge-Station (Config.MergeRange)
	- Anzahl im erlaubten Rahmen (MergeMinCount..MergeMaxCount)
	- Spieler besitzt die Snacks tatsächlich im Tresor
	- Erfolgschance kommt aus Config.MergeChance (gleiche Formel wie die UI-Anzeige)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MergeService = {}

local DataService, BaseService, MapService, SeasonPassService -- in Init verdrahtet

local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

-- Eigenen Tresor-Inhalt abfragen (fürs Merge-UI)
local function getVault(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return {}
	end
	return table.clone(profile.Vault)
end

local function doMerge(player: Player, snackName: any, count: any)
	if typeof(snackName) ~= "string" or typeof(count) ~= "number" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	count = math.floor(count)
	if count < Config.MergeMinCount or count > Config.MergeMaxCount then
		return { ok = false, msg = ("Es gehen nur %d bis %d Snacks auf einmal!"):format(Config.MergeMinCount, Config.MergeMaxCount) }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen..." }
	end

	-- Steht der Spieler überhaupt an der Maschine?
	local stationPos = MapService.GetShopPosition("Merge")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not stationPos or not root or (root.Position - stationPos).Magnitude > Config.MergeRange then
		return { ok = false, msg = "Du musst an der MERGE-MASCHINE stehen!" }
	end

	local def = SnackTypes.ByName[snackName]
	if not def then
		return { ok = false, msg = "Unbekannter Snack." }
	end
	local nextRarity = SnackTypes.NextRarity(def.Rarity)
	if not nextRarity then
		return { ok = false, msg = ("%s ist schon Maximal-Rarität – nicht mergebar!"):format(snackName) }
	end

	-- Besitzt der Spieler genug davon?
	local owned = 0
	for _, name in profile.Vault do
		if name == snackName then
			owned += 1
		end
	end
	if owned < count then
		return { ok = false, msg = ("Du hast nur %d davon im Tresor."):format(owned) }
	end

	-- Einsatz aus dem Tresor entfernen (rückwärts, damit die Indizes stimmen)
	local toRemove = count
	for i = #profile.Vault, 1, -1 do
		if toRemove == 0 then
			break
		end
		if profile.Vault[i] == snackName then
			table.remove(profile.Vault, i)
			toRemove -= 1
		end
	end

	local chance = Config.MergeChance(count)
	local success = math.random() < chance

	-- Season-Pass-XP: Mut wird belohnt (Versuch), Erfolg extra
	SeasonPassService.AddXp(player, "MergeTry")
	if success then
		SeasonPassService.AddXp(player, "MergeSuccess")
	end

	if success then
		-- Zufälliger Snack aus der nächsthöheren Raritäts-Stufe
		local pool = SnackTypes.ByRarity[nextRarity]
		local result = pool[math.random(1, #pool)]
		table.insert(profile.Vault, result.Name)
		BaseService.RefreshDisplay(player)
		sfxRemote:FireClient(player, "ding")

		if result.Announce then
			announceRemote:FireAllClients(
				("🧪 MUTATION GEGLÜCKT! %s hat '%s' zusammengemergt!"):format(player.Name, result.Name),
				result.Rarity
			)
		end
		return {
			ok = true,
			success = true,
			msg = ("%dx %s -> '%s' (%s, +%d💰/s)!"):format(count, snackName, result.Name, result.Rarity, result.Income),
		}
	else
		BaseService.RefreshDisplay(player)
		sfxRemote:FireClient(player, "oof")
		return {
			ok = true,
			success = false,
			msg = ("Die Maschine hat %dx %s zu Matsch zermergt... alles weg!"):format(count, snackName),
		}
	end
end

function MergeService.Init(services)
	DataService = services.DataService
	BaseService = services.BaseService
	MapService = services.MapService
	SeasonPassService = services.SeasonPassService

	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	(Remotes.Get("GetVault") :: RemoteFunction).OnServerInvoke = getVault;
	(Remotes.Get("DoMerge") :: RemoteFunction).OnServerInvoke = doMerge
end

return MergeService
