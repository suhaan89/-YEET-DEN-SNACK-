--[[
	DailyRewardService.luau
	Täglicher Login-Streak – GETRENNT vom RewardService (der belohnt
	Spielzeit in der Session, hier zählt der Kalendertag).

	- Kalendertag = os.time() // 86400 (UTC – für alle Server identisch,
	  kein Zeitzonen-Chaos).
	- Streak: Login an aufeinanderfolgenden Tagen -> Streak steigt; ein
	  verpasster Tag -> zurück auf 1. Belohnung = Config.DailyRewards-Eintrag
	  ((streak-1) % 7 + 1) – nach Tag 7 beginnt der Zyklus von vorn, der
	  Streak-Zähler selbst läuft zum Angeben weiter.
	- Abgeholt wird AKTIV per Button (ClaimDailyReward) – ein Popup beim Join
	  ist besser als stilles Auto-Gutschreiben, weil der Spieler die Belohnung
	  dann auch WAHRNIMMT (Retention!).
	- Zustand liegt im normalen Profil (profile.Daily, lazy angelegt) und
	  wird vom DataService-Autosave mitgespeichert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DailyRewardService = {}

local DataService, PlayerService, PetService, GemService -- in Init verdrahtet

local sfxRemote: RemoteEvent

local DAY = 86400

local function today(): number
	return os.time() // DAY
end

local function ensureDaily(profile)
	if typeof(profile.Daily) ~= "table" then
		profile.Daily = { LastDay = 0, Streak = 0 }
	end
	return profile.Daily
end

-- Index in Config.DailyRewards für den NÄCHSTEN Claim bei Streak `streak`
local function rewardIndex(streak: number): number
	return (streak - 1) % #Config.DailyRewards + 1
end

local function getDailyInfo(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local daily = ensureDaily(profile)
	local now = today()
	local canClaim = daily.LastDay < now
	-- Welcher Streak-Wert würde beim nächsten Claim gelten?
	local nextStreak = if daily.LastDay == now - 1 then daily.Streak + 1 elseif canClaim then 1 else daily.Streak
	return {
		CanClaim = canClaim,
		Streak = daily.Streak,
		NextStreak = nextStreak,
		NextIndex = rewardIndex(math.max(nextStreak, 1)),
	}
end

local function claimDailyReward(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return { ok = false, msg = "Daten noch nicht geladen – versuch's gleich nochmal." }
	end
	local daily = ensureDaily(profile)
	local now = today()
	if daily.LastDay >= now then
		return { ok = false, msg = "Heute schon abgeholt – komm morgen wieder! ⏰" }
	end

	-- Streak fortsetzen oder neu starten
	if daily.LastDay == now - 1 then
		daily.Streak += 1
	else
		daily.Streak = 1
	end
	daily.LastDay = now

	local def = Config.DailyRewards[rewardIndex(daily.Streak)]
	local text = "???"
	if def.Type == "Cash" then
		PlayerService.AddCash(player, def.Amount)
		text = ("+%d💰"):format(def.Amount)
	elseif def.Type == "Egg" then
		local result = PetService.GrantEgg(player, def.Egg)
		text = if result.ok then result.msg else "Ei (Fehler beim Öffnen?)"
	elseif def.Type == "Gems" then
		GemService.AddGems(player, def.Amount)
		text = ("+%d💎"):format(def.Amount)
	end

	sfxRemote:FireClient(player, "ding")
	return {
		ok = true,
		msg = ("Tag %d abgeholt: %s"):format(daily.Streak, text),
		Streak = daily.Streak,
	}
end

function DailyRewardService.Init(services)
	DataService = services.DataService
	PlayerService = services.PlayerService
	PetService = services.PetService
	GemService = services.GemService

	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent;

	(Remotes.Get("GetDailyInfo") :: RemoteFunction).OnServerInvoke = getDailyInfo;
	(Remotes.Get("ClaimDailyReward") :: RemoteFunction).OnServerInvoke = claimDailyReward
end

return DailyRewardService
