--[[
	Config.luau
	Zentrale Tuning-Werte für "YEET DEN SNACK!"
	Alles Balancing an EINEM Ort – hier drehen, nicht im Code verteilt.
]]

local Config = {
	-- ══ Schoko-Truck ══
	TruckFirstSpawnDelay = 15, -- Sekunden nach Serverstart bis zum ersten Truck
	TruckInterval = 180, -- Sekunden zwischen Truck-Events
	TruckWarnTime = 10, -- Vorwarnung "DER TRUCK KOMMT!" (Sekunden vorher)
	TruckSpeed = 55, -- Studs pro Sekunde
	TruckDropInterval = 0.6, -- Sekunden zwischen zwei Snack-Drops
	TruckDropZone = 170, -- Snacks fallen nur bei |x| < diesem Wert
	TruckFlingForce = 95, -- Wie hart der Truck Spieler wegschleudert
	TruckFlingUpForce = 55,

	-- ══ Snacks & YEETen ══
	Gravity = 140, -- leicht floaty (Standard 196.2) -> weitere Yeets, höhere Sprünge, mehr Comedy
	HoldDuration = 4, -- Sekunden, die man einen Snack halten darf, bevor er runterfällt
	ThrowBasePower = 100, -- Basis-Wurfkraft (voll aufgeladen ~60-70 Studs Weite)
	ThrowUpFactor = 0.5, -- Bogen nach oben (Anteil der Wurfkraft)
	ThrowChargeTime = 1.2, -- Sekunden bis volle Aufladung
	ThrowPowerPerLevel = 0.12, -- +12% Wurfkraft pro Upgrade-Level
	SnackDespawnTime = 120, -- Lose Snacks verschwinden nach dieser Zeit
	MaxLooseSnacks = 60, -- Obergrenze gegen Snack-Müllhalden

	-- ══ Slap ══
	SlapRange = 10, -- Reichweite in Studs
	SlapCooldown = 2, -- Sekunden zwischen Slaps
	SlapBaseForce = 55, -- Basis-Schleuderkraft
	SlapForcePerLevel = 6, -- + Kraft pro Slap-Power-Level
	SlapUpForce = 35, -- Aufwärts-Anteil (für den schönen Flug)
	RagdollTime = 2.5, -- Sekunden Ragdoll nach Slap/Truck
	SnackStunTime = 5, -- Sekunden "DU BIST JETZT DER SNACK"-Verwandlung

	-- ══ Basen & Tresor ══
	VaultCrackBaseTime = 6, -- Sekunden Tresor-Knacken (Basis)
	VaultCrackTimePerLock = 3, -- + Sekunden pro Schloss-Level des Besitzers
	VaultCrackCooldown = 30, -- Sekunden Cooldown pro Tresor nach einem Klau
	IncomeTick = 1, -- Einkommens-Intervall in Sekunden

	-- ══ Ökonomie ══
	StartCash = 25,
	Upgrades = {
		Wurfkraft = { BaseCost = 100, CostFactor = 1.6, MaxLevel = 25, Label = "💪 Wurfkraft", Desc = "YEETe Snacks weiter!" },
		SlapPower = { BaseCost = 150, CostFactor = 1.6, MaxLevel = 25, Label = "👋 Slap-Power", Desc = "Schleudere Gegner weiter weg!" },
		Tempo = { BaseCost = 120, CostFactor = 1.6, MaxLevel = 15, Label = "👟 Tempo", Desc = "+2 Laufgeschwindigkeit pro Level" },
		Schloss = { BaseCost = 200, CostFactor = 1.7, MaxLevel = 10, Label = "🔒 Tresor-Schloss", Desc = "Diebe brauchen länger zum Knacken" },
	},
	UpgradeOrder = { "Wurfkraft", "SlapPower", "Tempo", "Schloss" }, -- feste Reihenfolge fürs UI
	WalkSpeedBase = 16,
	WalkSpeedPerTempo = 2,

	RebirthBaseCost = 10000,
	RebirthCostFactor = 2.5,
	RebirthBonus = 0.5, -- +50% Einkommen pro Rebirth ("Sugar Rush")

	-- ══ Juice & Events ══
	SweetSpotStart = 0.85, -- Ladung ab hier = PERFEKTER YEET
	SweetSpotBonus = 1.25, -- Extra-Wurfkraft für perfektes Timing
	ComboWindow = 12, -- Sekunden zwischen zwei Einlagerungen für Combo
	ComboBonusFactor = 5, -- Bonus-Cash = Snack-Einkommen * Faktor * Combo-Stufe
	RushHourEvery = 4, -- jeder n-te Truck wird zur RUSH HOUR (zwei Trucks!)
	SfxMaxDistance = 150, -- Sounds weiter weg als das hört man nicht
	PlaytimeGiftInterval = 240, -- alle X Sekunden Spielzeit gibt's einen Geschenk-Snack
	SpawnProtection = 4, -- Sekunden ForceField nach dem Spawnen

	-- ══ Daten ══
	AutosaveInterval = 60, -- Sekunden
	DataStoreName = "YeetDenSnack_v1",
}

-- Kosten für das nächste Level eines Upgrades
function Config.UpgradeCost(upgradeName: string, currentLevel: number): number
	local def = Config.Upgrades[upgradeName]
	if not def then
		return math.huge
	end
	return math.floor(def.BaseCost * def.CostFactor ^ currentLevel)
end

-- Kosten für den nächsten Rebirth
function Config.RebirthCost(rebirths: number): number
	return math.floor(Config.RebirthBaseCost * Config.RebirthCostFactor ^ rebirths)
end

return Config
