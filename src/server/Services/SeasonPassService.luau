--[[
	SeasonPassService.luau
	Season-/Battle-Pass: XP durch normales Spielen, 35 Stufen, Free- und
	Premium-Spur (Robux-Gamepass über MarketplaceService).

	- XP-Vergabe und Stufenaufstieg passieren AUSSCHLIESSLICH hier auf dem
	  Server. Andere Services rufen nur SeasonPassService.AddXp(player, key)
	  mit einem Key aus Config.SeasonPass.Xp auf.
	- Belohnungen werden beim Stufenaufstieg AUTOMATISCH ausgezahlt
	  (GrantedFree/GrantedPremium im Profil merken sich, was schon raus ist –
	  übersteht damit auch Rejoins mitten in einer Season).
	- Premium nachträglich gekauft? Alle Premium-Belohnungen bis zur
	  aktuellen Stufe werden rückwirkend ausgezahlt.
	- Fortschritt fürs UI läuft über replizierende Player-Attribute:
	  SeasonXp / SeasonLevel / SeasonPremium (Client zeigt nur an).
	- Season-Wechsel: neue Id in Config.SeasonPass -> Fortschritt resettet
	  beim nächsten Join automatisch.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SeasonPassService = {}

local DataService, PlayerService, PetService -- in Init verdrahtet

local notifyRemote: RemoteEvent
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

-- Namen der Season-Trails für hübsche Belohnungs-Texte
local seasonTrailsById: { [string]: any } = {}
for _, def in Config.SeasonTrails do
	seasonTrailsById[def.Id] = def
end

local function seasonActive(): boolean
	local now = os.time()
	return now >= Config.SeasonPass.StartTime and now <= Config.SeasonPass.EndTime
end

-- Fortschritt in die replizierenden Attribute spiegeln (Datenquelle fürs UI)
local function syncAttributes(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local sp = profile.SeasonPass
	local level = Config.SeasonProgress(sp.Xp)
	player:SetAttribute("SeasonXp", sp.Xp)
	player:SetAttribute("SeasonLevel", level)
	player:SetAttribute("SeasonPremium", sp.Premium == true)
end

-- Eine einzelne Belohnung auszahlen; gibt einen Anzeigetext zurück
local function grantReward(player: Player, profile, reward): string
	if reward.Type == "Cash" then
		PlayerService.AddCash(player, reward.Amount)
		return ("+%d💰"):format(reward.Amount)
	elseif reward.Type == "Egg" then
		local eggDef = Config.EggsById[reward.Egg]
		local result = PetService.GrantEgg(player, reward.Egg)
		if result.ok then
			return ("%s geöffnet: %s"):format(eggDef and eggDef.Name or "Ei", result.msg)
		end
		return "Ei (Fehler beim Öffnen?)"
	elseif reward.Type == "Trail" then
		profile.Trails[reward.Trail] = true
		local def = seasonTrailsById[reward.Trail]
		return ("%s (im Style-Shop anziehen!)"):format(def and def.Name or reward.Trail)
	elseif reward.Type == "Pet" then
		profile.Pets[reward.Pet] = true
		local def = Config.EggPetsById[reward.Pet]
		return ("%s (im Pet-Shop ausrüsten!)"):format(def and def.Name or reward.Pet)
	end
	return "???"
end

-- Alle noch offenen Belohnungen bis zur aktuellen Stufe auszahlen
local function grantPending(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local sp = profile.SeasonPass
	local level = Config.SeasonProgress(sp.Xp)

	while sp.GrantedFree < level do
		sp.GrantedFree += 1
		local rewards = Config.SeasonPass.Rewards[sp.GrantedFree]
		if rewards and rewards.Free then
			local text = grantReward(player, profile, rewards.Free)
			notifyRemote:FireClient(player, ("🎫 Pass-Stufe %d: %s"):format(sp.GrantedFree, text))
		end
	end

	if sp.Premium then
		while sp.GrantedPremium < level do
			sp.GrantedPremium += 1
			local rewards = Config.SeasonPass.Rewards[sp.GrantedPremium]
			if rewards and rewards.Premium then
				local text = grantReward(player, profile, rewards.Premium)
				notifyRemote:FireClient(player, ("👑 Premium-Stufe %d: %s"):format(sp.GrantedPremium, text))
			end
		end
	end
end

-- ══════════ Öffentliche API (rufen andere Services auf) ══════════

-- XP für eine Aktion vergeben. `key` MUSS in Config.SeasonPass.Xp stehen.
function SeasonPassService.AddXp(player: Player, key: string)
	if not seasonActive() then
		return -- Season vorbei/noch nicht gestartet: kein XP mehr
	end
	local amount = Config.SeasonPass.Xp[key]
	local profile = DataService.Get(player)
	if not amount or not profile then
		return
	end
	local sp = profile.SeasonPass
	local before = Config.SeasonProgress(sp.Xp)
	sp.Xp += amount
	local after = Config.SeasonProgress(sp.Xp)
	if after > before then
		sfxRemote:FireClient(player, "ding")
		grantPending(player)
	end
	syncAttributes(player)
end

-- Premium-Status setzen (Gamepass-Kauf/-Check); zahlt rückwirkend aus
function SeasonPassService.SetPremium(player: Player, premium: boolean)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.SeasonPass.Premium = premium == true
	if premium then
		grantPending(player)
	end
	syncAttributes(player)
end

-- ══════════ Debug-Helfer (fürs Test-Menü) ══════════

-- Roh-XP ohne Season-Zeitfenster-Check (nur übers Debug-Menü erreichbar)
function SeasonPassService.DebugAddXp(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.SeasonPass.Xp += amount
	grantPending(player)
	syncAttributes(player)
end

function SeasonPassService.DebugTogglePremium(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local newValue = not profile.SeasonPass.Premium
	SeasonPassService.SetPremium(player, newValue)
	return newValue
end

-- ══════════ Init ══════════

function SeasonPassService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	PetService = services.PetService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.WaitFor(player)
			if not profile then
				return
			end

			-- Neue Season? Fortschritt sauber auf null (Premium hängt am
			-- Gamepass und wird gleich darunter sowieso frisch geprüft).
			if profile.SeasonPass.Id ~= Config.SeasonPass.Id then
				profile.SeasonPass = {
					Id = Config.SeasonPass.Id,
					Xp = 0,
					GrantedFree = 0,
					GrantedPremium = 0,
					Premium = false,
				}
			end

			-- Gamepass-Besitz beim Join prüfen (0 = noch nicht angelegt)
			if Config.SeasonPass.GamepassId > 0 and not profile.SeasonPass.Premium then
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.SeasonPass.GamepassId)
				end)
				if ok and owns then
					SeasonPassService.SetPremium(player, true)
				end
			end

			-- Falls sich Rewards zwischen Sessions geändert haben o.ä.
			grantPending(player)
			syncAttributes(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Kauf-Callback: Premium-Pass direkt im Spiel gekauft
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, purchased: boolean)
		if purchased and Config.SeasonPass.GamepassId > 0 and gamePassId == Config.SeasonPass.GamepassId then
			SeasonPassService.SetPremium(player, true)
			announceRemote:FireAllClients(
				("👑 %s hat den PREMIUM-PASS geholt – Respekt!"):format(player.Name),
				"Legendary"
			)
		end
	end)
end

return SeasonPassService
