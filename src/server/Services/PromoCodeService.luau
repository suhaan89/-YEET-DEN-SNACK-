--[[
	PromoCodeService.luau
	Promo-Codes für Marketing (YouTuber-/TikTok-Shoutouts, Update-Codes).

	GETRENNT vom Referral-System: Referral-Codes verknüpfen Spieler
	untereinander, Promo-Codes sind feste Gutscheine aus Config.PromoCodes.

	- Neue Codes = neue Zeile in Config.PromoCodes (kein Code-Deploy nötig,
	  nur Place neu publishen); abschalten per Active = false.
	- Jeder Account kann jeden Code genau EINMAL einlösen. Die eingelösten
	  Codes liegen als Set im normalen Spieler-Profil (profile.RedeemedCodes,
	  lazy angelegt – DataService bleibt unverändert) und werden mit dem
	  Autosave persistiert.
	- Alles serverseitig validiert; der Client schickt nur den String.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PromoCodeService = {}

local DataService, PlayerService, PetService, GemService -- in Init verdrahtet

local sfxRemote: RemoteEvent

-- Lookup: normalisierter Code -> Definition (Codes sind case-insensitiv)
local codesByKey: { [string]: any } = {}
for _, def in Config.PromoCodes do
	codesByKey[def.Code:upper()] = def
end

-- Belohnung auszahlen; gibt (ok, Anzeigetext) zurück
local function grantReward(player: Player, profile, reward): (boolean, string)
	if reward.Type == "Cash" then
		PlayerService.AddCash(player, reward.Amount)
		return true, ("+%d💰"):format(reward.Amount)
	elseif reward.Type == "Egg" then
		local result = PetService.GrantEgg(player, reward.Egg)
		if result.ok then
			return true, result.msg
		end
		return false, ""
	elseif reward.Type == "Gems" then
		GemService.AddGems(player, reward.Amount)
		return true, ("+%d💎"):format(reward.Amount)
	elseif reward.Type == "Trail" then
		if profile.Trails[reward.Trail] then
			-- Trail schon da: kleiner Trost-Cash statt Nullnummer
			PlayerService.AddCash(player, 500)
			return true, "Trail hattest du schon – dafür +500💰!"
		end
		profile.Trails[reward.Trail] = true
		return true, "Neuer Trail (im Style-Shop anziehen!)"
	end
	warn("[PromoCodeService] Unbekannter Reward-Typ:", reward.Type)
	return false, ""
end

local function redeemPromoCode(player: Player, code: any)
	if typeof(code) ~= "string" then
		return { ok = false, msg = "Ungültige Anfrage." }
	end
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen – versuch's gleich nochmal." }
	end

	local key = code:gsub("%s", ""):upper()
	if key == "" then
		return { ok = false, msg = "Erst einen Code eintippen!" }
	end

	local def = codesByKey[key]
	if not def or def.Active ~= true then
		return { ok = false, msg = "Diesen Code gibt's nicht (mehr) – Tippfehler?" }
	end

	-- Eingelöste Codes lazy im Profil anlegen
	if typeof(profile.RedeemedCodes) ~= "table" then
		profile.RedeemedCodes = {}
	end
	if profile.RedeemedCodes[key] then
		return { ok = false, msg = "Diesen Code hast du schon eingelöst!" }
	end

	local granted, text = grantReward(player, profile, def.Reward)
	if not granted then
		return { ok = false, msg = "Auszahlung fehlgeschlagen – versuch's gleich nochmal." }
	end
	profile.RedeemedCodes[key] = true

	sfxRemote:FireClient(player, "ding")
	return { ok = true, msg = ("Code '%s' eingelöst: %s"):format(key, text) }
end

function PromoCodeService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	PetService = services.PetService
	GemService = services.GemService

	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	(Remotes.Get("RedeemPromoCode") :: RemoteFunction).OnServerInvoke = redeemPromoCode
end

return PromoCodeService
