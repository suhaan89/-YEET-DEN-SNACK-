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
	TruckDropZone = 210, -- Snacks fallen nur bei |x| < diesem Wert
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

	-- Kurve bewusst steil (25k/75k/225k/675k/2M/...): Rebirths sollen sich
	-- wie echte Meilensteine anfühlen, nicht wie ein Zwischensnack.
	RebirthBaseCost = 25000,
	RebirthCostFactor = 3,
	RebirthBonus = 0.5, -- +50% Einkommen pro Rebirth ("Sugar Rush")

	-- ══ Tresor-Kapazität ══
	-- Der Tresor hat begrenzte Plätze – mehr gibt's durch Rebirths und Basis-Ausbau.
	VaultLimitBase = 20, -- Snack-Plätze ohne Rebirth
	VaultLimitPerRebirth = 10, -- + Plätze pro Rebirth (macht den Sugar Rush bedeutsamer)
	VaultFullNotifyCooldown = 3, -- Sekunden zwischen zwei "Tresor voll!"-Meldungen

	-- ══ Basis-Ausbau (Tycoon) ══
	-- Jeder startet als Camp (Level 1). Ausbauen kostet Cash am grünen Bau-Pad
	-- der eigenen Basis und bringt Tresor-Plätze + Einkommens-Bonus.
	-- BonusSlots/IncomeBonus sind GESAMT-Werte des Levels (keine Inkremente).
	-- Beim Rebirth wird die Basis wieder zum Camp – echter Neuanfang!
	BaseLevels = {
		{ Cost = 0, Label = "🏕️ Snack-Camp", BonusSlots = 0, IncomeBonus = 0 },
		{ Cost = 4000, Label = "🏠 Snack-Hütte", BonusSlots = 5, IncomeBonus = 0.05 },
		{ Cost = 18000, Label = "🏪 Snack-Lager", BonusSlots = 15, IncomeBonus = 0.12 },
		{ Cost = 75000, Label = "🏭 Snack-Fabrik", BonusSlots = 30, IncomeBonus = 0.25 },
		{ Cost = 300000, Label = "🏰 Snack-Imperium", BonusSlots = 50, IncomeBonus = 0.5 },
	},

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

	-- ══ Pet-Shop ══
	-- Pets sind schwebende Begleiter, die passiv Cash generieren (skaliert mit Rebirth-Multiplikator).
	-- Nur EIN Pet gleichzeitig ausgerüstet.
	Pets = {
		{ Id = "Hamster", Name = "🐹 Schoko-Hamster", Cost = 400, Income = 1, Color = Color3.fromRGB(160, 100, 50), Desc = "Knabbert Krümel zu Cash. +1💰/s" },
		{ Id = "Dackel", Name = "🌭 Donut-Dackel", Cost = 2500, Income = 5, Color = Color3.fromRGB(255, 150, 200), Desc = "Halb Hund, halb Donut. +5💰/s" },
		{ Id = "Einhorn", Name = "🦄 Zucker-Einhorn", Cost = 12000, Income = 20, Color = Color3.fromRGB(220, 160, 255), Desc = "Pupst Puderzucker. +20💰/s" },
		{ Id = "Drache", Name = "🐉 Kakao-Drache", Cost = 60000, Income = 90, Color = Color3.fromRGB(120, 60, 200), Desc = "Speit heiße Schokolade. +90💰/s" },
	},
	PetIncomeTick = 1, -- Sekunden zwischen Pet-Einkommens-Ticks

	-- ══ Style-Shop (Skins) ══
	-- Ganzkörper-Skins: färben alle Körperteile um (Material/Transparenz inklusive).
	-- Nur EINER gleichzeitig aktiv, rein kosmetisch.
	Skins = {
		{ Id = "Schoko", Name = "🍫 Schoko-Überzug", Cost = 1500, Color = Color3.fromRGB(90, 55, 25), Material = Enum.Material.SmoothPlastic, Desc = "Von Kopf bis Fuß in Schokolade getunkt." },
		{ Id = "Gummi", Name = "🐻 Gummibärchen", Cost = 8000, Color = Color3.fromRGB(255, 80, 80), Material = Enum.Material.Neon, Transparency = 0.25, Desc = "Halb durchsichtig, voll lecker." },
		{ Id = "Gold", Name = "🏆 Vergoldet", Cost = 40000, Color = Color3.fromRGB(255, 210, 60), Material = Enum.Material.Metal, Desc = "Protz-Modus: 24 Karat Snack." },
		{ Id = "Toxic", Name = "☢️ Mutanten-Glibber", Cost = 150000, Color = Color3.fromRGB(110, 255, 40), Material = Enum.Material.Neon, Sparkles = true, Desc = "Direkt aus dem Mutanten-Express gefallen." },
	},

	-- ══ Style-Shop (Trails) ══
	-- Rein kosmetische Lauf-Trails hinter dem Charakter. Nur EINER gleichzeitig aktiv.
	Trails = {
		{ Id = "Schoko", Name = "🍫 Schoko-Spur", Cost = 300, Color = Color3.fromRGB(120, 72, 30), Desc = "Hinterlasse eine leckere Schokoladenspur!" },
		{ Id = "Gold", Name = "✨ Gold-Glitzer", Cost = 2000, Color = Color3.fromRGB(255, 215, 0), Desc = "Für Spieler mit Geschmack UND Geld." },
		{ Id = "Feuer", Name = "🔥 Feuer-Furz", Cost = 8000, Color = Color3.fromRGB(255, 90, 20), Desc = "Zu viele scharfe Gummibärchen gegessen..." },
		{ Id = "Regenbogen", Name = "🌈 Regenbogen-Turbo", Cost = 25000, Color = Color3.fromRGB(255, 255, 255), Rainbow = true, Desc = "Nyan-Modus aktiviert!" },
	},

	-- ══ Merge-Station ══
	-- 2+ gleiche Tresor-Snacks einsetzen -> Chance auf 1 Snack der NÄCHSTHÖHEREN Rarität.
	-- Bei Misserfolg (Standardfall!) sind ALLE eingesetzten Snacks weg.
	MergeMinCount = 2, -- Mindestanzahl gleicher Snacks pro Versuch
	MergeMaxCount = 10, -- Obergrenze pro Versuch (Server-Clamp)
	MergeBaseChance = 0.3, -- Erfolgschance bei MergeMinCount Snacks
	MergeChancePerExtra = 0.08, -- + Chance pro zusätzlichem Snack
	MergeMaxChance = 0.6, -- Chance-Deckel (Misserfolg bleibt wahrscheinlich!)
	MergeRange = 16, -- max. Abstand zur Merge-Station (Server-Check, Studs)

	-- ══ Supreme Snack Event ══
	-- Statt eines normalen Trucks kommt der MUTANTEN-EXPRESS und droppt mutierte Supreme-Snacks.
	SupremeTrucksMin = 80, -- Countdown wird zufällig zwischen Min und Max gewürfelt
	SupremeTrucksMax = 120, -- (im Schnitt ~100 Trucks bis zum Event)
	SupremeSnackCount = 2, -- ca. so viele Supreme-Snacks droppt der Event-Truck

	-- ══ Debug/Test-Menü ══
	-- Im Studio ist das Menü IMMER sichtbar. Für Live-Server hier UserIds eintragen:
	DebugUserIds = {} :: { number },
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

-- Definition eines Basis-Levels (auf den gültigen Bereich geklemmt)
function Config.BaseLevelDef(level: number)
	return Config.BaseLevels[math.clamp(level, 1, #Config.BaseLevels)]
end

-- Maximale Tresor-Plätze bei `rebirths` Rebirths und Basis-Level `baseLevel`
function Config.VaultLimit(rebirths: number, baseLevel: number?): number
	return Config.VaultLimitBase
		+ rebirths * Config.VaultLimitPerRebirth
		+ Config.BaseLevelDef(baseLevel or 1).BonusSlots
end

-- Erfolgschance für einen Merge mit `count` gleichen Snacks (Client-Anzeige + Server-Wurf
-- nutzen dieselbe Formel, damit die Anzeige nie lügt)
function Config.MergeChance(count: number): number
	return math.min(
		Config.MergeMaxChance,
		Config.MergeBaseChance + (count - Config.MergeMinCount) * Config.MergeChancePerExtra
	)
end

return Config
