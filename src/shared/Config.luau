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

	-- ══ Goldener Snack (Zufalls-Minievent) ══
	-- Spawnt unabhängig vom Truck an einer zufälligen Stelle der begehbaren Map.
	-- Wer ihn ZUERST berührt/schnappt, kriegt den Cash-Bonus (Server vergibt genau 1x).
	GoldenSnackFirstDelay = 75, -- Sekunden nach Serverstart bis zum ersten Golden-Spawn
	GoldenSnackIntervalMin = 120, -- Abstand zwischen zwei Spawns wird zufällig ...
	GoldenSnackIntervalMax = 240, -- ... aus [Min, Max] gewürfelt (Sekunden)
	GoldenSnackLifetime = 25, -- Sekunden sichtbar, dann verschwindet er wieder
	GoldenSnackReward = 750, -- Basis-Cash-Bonus (skaliert mit dem Rebirth-Multiplikator)
	-- Spawn-Rechteck: deckt Plaza + Straße + Wiese ab, spart Basen (z=±120) und Shops (z=±80) aus
	GoldenSnackArea = { MinX = -200, MaxX = 200, MinZ = -60, MaxZ = 60 },

	-- ══ Freunde-Bonus ══
	-- Spielt ein Roblox-Freund gleichzeitig im selben Server, bekommen BEIDE
	-- einen passiven Einkommens-Boost aufs rohe Tresor-Einkommen (FriendService).
	FriendBonusPercent = 0.1, -- +10% solange mindestens ein Freund online ist
	FriendRecheckInterval = 60, -- Sekunden: fehlgeschlagene Freundes-Checks erneut versuchen

	-- ══ Basis-Deko (Housing) ══
	-- Rein kosmetische Deko-Objekte für die eigene Basis: kaufen (Cash),
	-- in feste Slots stellen, wird pro Spieler persistent gespeichert und
	-- beim nächsten Join automatisch wieder aufgebaut (HousingService).
	HousingDataStore = "YeetDenSnack_Housing_v1",
	-- Feste Deko-Slots als LOKALE Offsets relativ zum Basis-Slot
	-- (44x44-Platte; -Z = vorne Richtung Straße; Tresor/Bau-Pad/Hort hinten
	-- bei z>=10 werden ausgespart). Kein freies Bauen – nur diese Plätze.
	HousingSlotOffsets = {
		Vector3.new(-16, 0, -16), -- vorne links
		Vector3.new(16, 0, -16), -- vorne rechts
		Vector3.new(-16, 0, 2), -- Mitte links
		Vector3.new(16, 0, 2), -- Mitte rechts
		Vector3.new(0, 0, -19), -- Eingang (vorne Mitte)
		Vector3.new(7, 0, 19), -- hinten neben dem Tresor
	},
	HousingDecor = {
		{ Id = "Zuckerstange", Name = "🍬 Zuckerstange", Cost = 300, Color = Color3.fromRGB(255, 70, 70), Desc = "Rot-weiß gestreifter Klassiker." },
		{ Id = "Fahne", Name = "🚩 Snack-Fahne", Cost = 600, Color = Color3.fromRGB(255, 150, 200), Desc = "Zeig allen, wessen Basis das ist!" },
		{ Id = "Lolli", Name = "🍭 Riesen-Lolli", Cost = 1200, Color = Color3.fromRGB(255, 90, 220), Desc = "So groß, dass er als Baum durchgeht." },
		{ Id = "Lampe", Name = "🏮 Zuckerwatte-Lampe", Cost = 2000, Color = Color3.fromRGB(255, 170, 220), Desc = "Flauschig-rosa Licht für laue Yeet-Nächte." },
		{ Id = "Gummibaer", Name = "🐻 Gummibär-Statue", Cost = 4000, Color = Color3.fromRGB(255, 80, 80), Desc = "Ein Denkmal für alle gefallenen Gummibärchen." },
		{ Id = "Donut", Name = "🍩 Donut-Schild", Cost = 7000, Color = Color3.fromRGB(255, 150, 200), Desc = "Leucht-Donut mit Streuseln. Sehr seriös." },
		{ Id = "Brunnen", Name = "⛲ Schoko-Brunnen", Cost = 12000, Color = Color3.fromRGB(110, 65, 30), Desc = "Sprudelt echte* Schokolade. (*Platzhalter)" },
		{ Id = "Disco", Name = "🪩 Disco-Bonbon", Cost = 25000, Color = Color3.fromRGB(180, 120, 255), Desc = "Party-Beleuchtung für Protz-Basen." },
	},

	-- ══ Referral/Einladungen ══
	-- Jeder Spieler hat einen festen Code (Prefix + UserId). Löst ein NEUER
	-- Spieler (vor seinem ersten Rebirth) den Code ein, wird er dauerhaft mit
	-- dem Einlader verknüpft. Schafft der Eingeladene Rebirth 1, bekommt der
	-- EINLADER die Belohnung (auch wenn er gerade offline ist -> PendingRewards).
	ReferralDataStore = "YeetDenSnack_Referrals_v1",
	ReferralCodePrefix = "SNACK-", -- eigener Code = "SNACK-<UserId>"
	ReferralRewardCash = 10000, -- Cash für den Einlader pro geschafftem Meilenstein
	ReferralRewardEgg = "Golden", -- + ein Gratis-Ei (Id aus Config.Eggs)

	-- ══ Achievements/Badges ══
	-- Meilensteine, serverseitig getrackt (eigener DataStore, AchievementService).
	-- Stat = welcher Zähler, Goal = Ziel-Wert für die Freischaltung.
	--
	-- TODO (Creator Dashboard): Für jedes Achievement eine echte Roblox-Badge
	-- anlegen (creator.roblox.com -> Spiel -> Engagement -> Badges) und die
	-- Badge-Id hier bei BadgeId eintragen! Solange BadgeId = 0 ist, wird nur
	-- intern freigeschaltet (Popup + Speicherung), aber keine Badge vergeben.
	AchievementDataStore = "YeetDenSnack_Achievements_v1",
	Achievements = {
		{ Id = "FirstBank", Name = "🍪 Erster Streich", Desc = "Lagere deinen ersten Snack im Tresor ein.", Stat = "Banked", Goal = 1, BadgeId = 0 },
		{ Id = "Bank100", Name = "🏦 Snack-Horter", Desc = "Lagere insgesamt 100 Snacks ein.", Stat = "Banked", Goal = 100, BadgeId = 0 },
		{ Id = "Bank500", Name = "🏰 Zucker-Baron", Desc = "Lagere insgesamt 500 Snacks ein.", Stat = "Banked", Goal = 500, BadgeId = 0 },
		{ Id = "FirstRebirth", Name = "🌟 Sugar Rush!", Desc = "Schaffe deinen ersten Rebirth.", Stat = "Rebirths", Goal = 1, BadgeId = 0 },
		{ Id = "Rebirth5", Name = "🌈 Zucker-Junkie", Desc = "Erreiche Rebirth 5.", Stat = "Rebirths", Goal = 5, BadgeId = 0 },
		{ Id = "FirstCrack", Name = "😈 Tresor-Knacker", Desc = "Knacke zum ersten Mal einen fremden Tresor.", Stat = "Cracks", Goal = 1, BadgeId = 0 },
		{ Id = "FirstLegendaryPet", Name = "🐉 Legenden-Zieher", Desc = "Ziehe ein Legendary- oder Mythic-Pet aus einem Ei.", Stat = "LegendaryPets", Goal = 1, BadgeId = 0 },
		{ Id = "Eggs25", Name = "🥚 Eierkopf", Desc = "Öffne 25 Eier im Pet-Shop.", Stat = "EggsOpened", Goal = 25, BadgeId = 0 },
		{ Id = "PerfectYeet50", Name = "🎯 Yeet-Präzision", Desc = "Lande 50 PERFEKTE Yeets (goldene Zone!).", Stat = "PerfectYeets", Goal = 50, BadgeId = 0 },
		{ Id = "Slap100", Name = "👋 Slap-Maschine", Desc = "Slappe 100 Spieler weg.", Stat = "Slaps", Goal = 100, BadgeId = 0 },
		{ Id = "FirstMerge", Name = "🧪 Mutations-Meister", Desc = "Schaffe deinen ersten erfolgreichen Merge.", Stat = "Merges", Goal = 1, BadgeId = 0 },
		{ Id = "GoldenGrab", Name = "🌟 Goldjunge", Desc = "Schnapp dir einen goldenen Snack.", Stat = "GoldenSnacks", Goal = 1, BadgeId = 0 },
	},

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

	-- ══ Ei-Gacha (Pet-System 2.0) ══
	-- Pets gibt es NICHT mehr direkt zu kaufen, sondern nur noch aus Eiern!
	-- Die alte `Pets`-Liste oben bleibt für Alt-Daten stehen (Ids leben in
	-- EggPets weiter, damit gekaufte Pets aus alten Spielständen erhalten bleiben).
	PetMaxEquipped = 3, -- so viele Pets dürfen gleichzeitig ausgerüstet sein

	-- Ei-Typen: Chances = relative Gewichte pro Rarität (müssen NICHT 100 ergeben)
	Eggs = {
		{
			Id = "Basic",
			Name = "🥚 Snack-Ei",
			Cost = 750,
			Color = Color3.fromRGB(240, 230, 200),
			Desc = "Riecht nach Keks. Meistens auch nur Keks drin.",
			Chances = { Common = 64, Rare = 25, Epic = 9, Legendary = 1.9, Mythic = 0.1 },
		},
		{
			Id = "Golden",
			Name = "🌟 Gold-Ei",
			Cost = 8000,
			Color = Color3.fromRGB(255, 210, 60),
			Desc = "Glänzt verdächtig. Deutlich bessere Chancen!",
			Chances = { Common = 30, Rare = 40, Epic = 22, Legendary = 7, Mythic = 1 },
		},
		{
			Id = "Mutant",
			Name = "☢️ Mutanten-Ei",
			Cost = 60000,
			Color = Color3.fromRGB(110, 255, 40),
			Desc = "Wackelt von alleine. KEINE Commons – Ehrenwort!",
			Chances = { Rare = 30, Epic = 40, Legendary = 24, Mythic = 6 },
		},
	},

	-- Anzeige-Reihenfolge der Pet-Raritäten (Farben kommen aus SnackTypes.RarityColors)
	PetRarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" },

	-- Duplikat gezogen? Gibt's Trostpflaster-Cash nach Rarität.
	PetDuplicateRefund = { Common = 100, Rare = 500, Epic = 2500, Legendary = 12000, Mythic = 40000 },

	-- Der komplette Pet-Pool. Ability.Type:
	--   Income       = +Value Cash/s (flach, mit Rebirth-Multiplikator)
	--   CashMult     = +Value*100% aufs Tresor-Einkommen (zahlt der Pet-Tick oben drauf)
	--   Yeet         = +Value*100% Wurfkraft
	--   Speed        = +Value WalkSpeed
	--   SlapRange    = +Value Studs Slap-Reichweite
	--   SlapCooldown = -Value*100% Slap-Cooldown
	--   SweetSpot    = Sweet-Spot-Zone wird um Value (Anteil vom Balken) breiter
	-- Exclusive = true -> fällt NICHT aus Eiern (nur Season-Pass o.ä.)
	EggPets = {
		-- Common
		{ Id = "Hamster", Name = "🐹 Schoko-Hamster", Rarity = "Common", Ability = { Type = "Income", Value = 1 }, Color = Color3.fromRGB(160, 100, 50), Desc = "Knabbert Krümel zu Cash. +1💰/s" },
		{ Id = "Zuckermaus", Name = "🐭 Puderzucker-Maus", Rarity = "Common", Ability = { Type = "Yeet", Value = 0.05 }, Color = Color3.fromRGB(235, 235, 245), Desc = "Niest Puderzucker. +5% Wurfkraft" },
		{ Id = "Kekskueken", Name = "🐤 Keks-Küken", Rarity = "Common", Ability = { Type = "Speed", Value = 2 }, Color = Color3.fromRGB(255, 220, 90), Desc = "Piept motivierend. +2 Tempo" },
		{ Id = "Lakritzschnecke", Name = "🐌 Lakritz-Schnecke", Rarity = "Common", Ability = { Type = "CashMult", Value = 0.05 }, Color = Color3.fromRGB(40, 35, 40), Desc = "Langsam, aber geschäftstüchtig. +5% Tresor-Einkommen" },
		-- Rare
		{ Id = "Dackel", Name = "🌭 Donut-Dackel", Rarity = "Rare", Ability = { Type = "Income", Value = 5 }, Color = Color3.fromRGB(255, 150, 200), Desc = "Halb Hund, halb Donut. +5💰/s" },
		{ Id = "Brezelboxer", Name = "🥨 Brezel-Boxer", Rarity = "Rare", Ability = { Type = "SlapRange", Value = 2 }, Color = Color3.fromRGB(190, 130, 60), Desc = "Trainiert deine Schlaghand. +2 Studs Slap-Reichweite" },
		{ Id = "Waffelpinguin", Name = "🐧 Waffel-Pinguin", Rarity = "Rare", Ability = { Type = "SweetSpot", Value = 0.03 }, Color = Color3.fromRGB(80, 80, 100), Desc = "Watschelt im Takt. Sweet-Spot +3% breiter" },
		{ Id = "Brausefrosch", Name = "🐸 Brause-Frosch", Rarity = "Rare", Ability = { Type = "Speed", Value = 4 }, Color = Color3.fromRGB(120, 255, 120), Desc = "Prickelt beim Hüpfen. +4 Tempo" },
		-- Epic
		{ Id = "Einhorn", Name = "🦄 Zucker-Einhorn", Rarity = "Epic", Ability = { Type = "Income", Value = 20 }, Color = Color3.fromRGB(220, 160, 255), Desc = "Pupst Puderzucker. +20💰/s" },
		{ Id = "Toffeeschildi", Name = "🐢 Toffee-Turbo-Schildkröte", Rarity = "Epic", Ability = { Type = "Yeet", Value = 0.12 }, Color = Color3.fromRGB(120, 200, 90), Desc = "Klebriger Rückenwind. +12% Wurfkraft" },
		{ Id = "Marshmallowgeist", Name = "👻 Marshmallow-Geist", Rarity = "Epic", Ability = { Type = "SlapCooldown", Value = 0.2 }, Color = Color3.fromRGB(255, 250, 250), Desc = "Spukt in deiner Schlaghand. -20% Slap-Cooldown" },
		{ Id = "Bonbonfuchs", Name = "🦊 Bonbon-Fuchs", Rarity = "Epic", Ability = { Type = "CashMult", Value = 0.12 }, Color = Color3.fromRGB(255, 140, 60), Desc = "Schlau UND süß. +12% Tresor-Einkommen" },
		-- Legendary
		{ Id = "Drache", Name = "🐉 Kakao-Drache", Rarity = "Legendary", Ability = { Type = "Income", Value = 90 }, Color = Color3.fromRGB(120, 60, 200), Desc = "Speit heiße Schokolade. +90💰/s" },
		{ Id = "Gummigorilla", Name = "🦍 Gummi-Gorilla", Rarity = "Legendary", Ability = { Type = "SlapRange", Value = 4 }, Color = Color3.fromRGB(255, 80, 80), Desc = "Trommelt auf der Gummibrust. +4 Studs Slap-Reichweite" },
		{ Id = "Karamellfalke", Name = "🦅 Karamell-Falke", Rarity = "Legendary", Ability = { Type = "Yeet", Value = 0.2 }, Color = Color3.fromRGB(230, 170, 80), Desc = "Gibt Flugstunden. +20% Wurfkraft" },
		{ Id = "Sahnekuh", Name = "🐮 Sahne-Sturm-Kuh", Rarity = "Legendary", Ability = { Type = "CashMult", Value = 0.25 }, Color = Color3.fromRGB(250, 245, 235), Desc = "Muht Geld herbei. +25% Tresor-Einkommen" },
		-- Mythic
		{ Id = "Riegelbot", Name = "🤖 Riegel-Bot 9000", Rarity = "Mythic", Ability = { Type = "Income", Value = 400 }, Color = Color3.fromRGB(140, 150, 170), Desc = "Druckt Riegel. Legal? Egal! +400💰/s" },
		{ Id = "Galaxienglibber", Name = "🐙 Galaxien-Glibber", Rarity = "Mythic", Ability = { Type = "CashMult", Value = 0.5 }, Color = Color3.fromRGB(90, 40, 180), Desc = "Aus Dimension X importiert. +50% Tresor-Einkommen" },
		{ Id = "Vanillerex", Name = "🦖 Vulkan-Vanille-Rex", Rarity = "Mythic", Ability = { Type = "Yeet", Value = 0.35 }, Color = Color3.fromRGB(255, 100, 40), Desc = "RAWR = +35% Wurfkraft" },
		{ Id = "Phoenix", Name = "🔥 Zucker-Phönix", Rarity = "Mythic", Ability = { Type = "CashMult", Value = 0.75 }, Color = Color3.fromRGB(255, 60, 60), Desc = "Season-1-Exklusiv! +75% Tresor-Einkommen", Exclusive = true },
	},

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

	-- ══ Season-Pass ══
	-- Zeitlich begrenzter Fortschritt: XP durch normales Spielen, 35 Stufen,
	-- Free-Spur für alle + Premium-Spur per Robux-Gamepass.
	-- Neue Season = Id/Zeiten/Rewards hier anpassen (Fortschritt resettet
	-- automatisch, sobald die gespeicherte Id nicht mehr zur Config passt).
	SeasonPass = {
		Id = "S1",
		Name = "🎪 SEASON 1: ZUCKER-ZIRKUS",
		StartTime = 1783296000, -- 06.07.2026 00:00 UTC
		EndTime = 1788220799, -- 31.08.2026 23:59 UTC
		GamepassId = 0, -- TODO: Gamepass im Creator Dashboard anlegen und Id hier eintragen!
		LevelCount = 35,
		XpBase = 60, -- XP für Stufe 1
		XpFactor = 1.09, -- Bedarf wächst pro Stufe um 9% (Stufe 35 ≈ 1120 XP)

		-- XP pro Aktion (vergeben NUR server-seitig)
		Xp = {
			Bank = 10, -- Snack erfolgreich eingelagert
			BankRareBonus = 30, -- extra, wenn der Snack Announce-würdig war (Legendary+)
			PerfectYeet = 5, -- im Sweet Spot losgelassen
			MergeTry = 10, -- Merge-Versuch (auch bei Matsch)
			MergeSuccess = 30, -- Merge geglückt
			Rebirth = 400, -- Sugar Rush
			EggOpen = 15, -- Ei im Pet-Shop geöffnet
			GoldenSnack = 25, -- Goldenen Snack geschnappt (Zufalls-Minievent)
		},

		-- Belohnungen pro Stufe. Typen:
		--   { Type = "Cash", Amount = n }             direkt aufs Konto
		--   { Type = "Egg", Egg = "Basic|Golden|Mutant" }  Ei wird sofort geöffnet
		--   { Type = "Trail", Trail = "<SeasonTrail-Id>" } exklusiver Trail
		--   { Type = "Pet", Pet = "<EggPet-Id>" }          exklusives Pet
		Rewards = {
			{ Free = { Type = "Cash", Amount = 200 }, Premium = { Type = "Egg", Egg = "Golden" } },
			{ Free = { Type = "Cash", Amount = 300 }, Premium = { Type = "Cash", Amount = 800 } },
			{ Free = { Type = "Cash", Amount = 450 }, Premium = { Type = "Cash", Amount = 1200 } },
			{ Free = { Type = "Cash", Amount = 600 }, Premium = { Type = "Cash", Amount = 1600 } },
			{ Free = { Type = "Egg", Egg = "Basic" }, Premium = { Type = "Egg", Egg = "Golden" } },
			{ Free = { Type = "Cash", Amount = 900 }, Premium = { Type = "Cash", Amount = 2400 } },
			{ Free = { Type = "Cash", Amount = 1000 }, Premium = { Type = "Cash", Amount = 2800 } },
			{ Free = { Type = "Cash", Amount = 1200 }, Premium = { Type = "Cash", Amount = 3200 } },
			{ Free = { Type = "Cash", Amount = 1400 }, Premium = { Type = "Cash", Amount = 3600 } },
			{ Free = { Type = "Cash", Amount = 1500 }, Premium = { Type = "Trail", Trail = "Bonbon" } },
			{ Free = { Type = "Cash", Amount = 1700 }, Premium = { Type = "Cash", Amount = 4400 } },
			{ Free = { Type = "Cash", Amount = 1800 }, Premium = { Type = "Cash", Amount = 4800 } },
			{ Free = { Type = "Cash", Amount = 2000 }, Premium = { Type = "Cash", Amount = 5200 } },
			{ Free = { Type = "Cash", Amount = 2100 }, Premium = { Type = "Cash", Amount = 5600 } },
			{ Free = { Type = "Egg", Egg = "Basic" }, Premium = { Type = "Egg", Egg = "Golden" } },
			{ Free = { Type = "Cash", Amount = 2400 }, Premium = { Type = "Cash", Amount = 6400 } },
			{ Free = { Type = "Cash", Amount = 2600 }, Premium = { Type = "Cash", Amount = 6800 } },
			{ Free = { Type = "Cash", Amount = 2700 }, Premium = { Type = "Cash", Amount = 7200 } },
			{ Free = { Type = "Cash", Amount = 2900 }, Premium = { Type = "Cash", Amount = 7600 } },
			{ Free = { Type = "Trail", Trail = "Zuckerwatte" }, Premium = { Type = "Egg", Egg = "Mutant" } },
			{ Free = { Type = "Cash", Amount = 3200 }, Premium = { Type = "Cash", Amount = 8400 } },
			{ Free = { Type = "Cash", Amount = 3300 }, Premium = { Type = "Cash", Amount = 8800 } },
			{ Free = { Type = "Cash", Amount = 3500 }, Premium = { Type = "Cash", Amount = 9200 } },
			{ Free = { Type = "Cash", Amount = 3600 }, Premium = { Type = "Cash", Amount = 9600 } },
			{ Free = { Type = "Egg", Egg = "Golden" }, Premium = { Type = "Egg", Egg = "Mutant" } },
			{ Free = { Type = "Cash", Amount = 3900 }, Premium = { Type = "Cash", Amount = 10400 } },
			{ Free = { Type = "Cash", Amount = 4100 }, Premium = { Type = "Cash", Amount = 10800 } },
			{ Free = { Type = "Cash", Amount = 4200 }, Premium = { Type = "Cash", Amount = 11200 } },
			{ Free = { Type = "Cash", Amount = 4400 }, Premium = { Type = "Cash", Amount = 11600 } },
			{ Free = { Type = "Cash", Amount = 4500 }, Premium = { Type = "Egg", Egg = "Mutant" } },
			{ Free = { Type = "Cash", Amount = 4700 }, Premium = { Type = "Cash", Amount = 12400 } },
			{ Free = { Type = "Cash", Amount = 4800 }, Premium = { Type = "Cash", Amount = 12800 } },
			{ Free = { Type = "Cash", Amount = 5000 }, Premium = { Type = "Cash", Amount = 13200 } },
			{ Free = { Type = "Cash", Amount = 5100 }, Premium = { Type = "Cash", Amount = 13600 } },
			{ Free = { Type = "Egg", Egg = "Golden" }, Premium = { Type = "Pet", Pet = "Phoenix" } },
		},
	},

	-- Season-exklusive Trails: NICHT kaufbar (Seasonal = true), nur als
	-- Pass-Belohnung. StyleService kennt sie fürs Ausrüsten mit.
	SeasonTrails = {
		{ Id = "Zuckerwatte", Name = "🍭 Zuckerwatte-Wolke", Color = Color3.fromRGB(255, 170, 220), Seasonal = true, Desc = "Season-1-Belohnung: flauschig-rosa Spur!" },
		{ Id = "Bonbon", Name = "🍬 Bonbon-Blizzard", Color = Color3.fromRGB(120, 220, 255), Rainbow = true, Seasonal = true, Desc = "Season-1-PREMIUM: wirbelnder Bonbon-Sturm!" },
	},

	-- ══ Parkour-Minigame & Juwelen ══
	-- 8 Parcours in FESTER Reihenfolge (5 kurze, dann 3 lange), betreten über
	-- den Portal-Hub südlich des Spawns (ParkourService baut Hub + Arenen).
	-- Freischaltung: Parcours n+1 öffnet sich erst nach Abschluss von Parcours n.
	-- Tiers: aufsteigend nach Time sortiert – die erste Stufe, deren Time-Limit
	-- die gelaufene Zeit noch einhält, zählt. Sonst gibt's die Base-Belohnung.
	-- Cash skaliert mit dem Rebirth-Multiplikator, Juwelen NICHT (bleiben rar!).
	-- MasterTime: ALLE 8 darunter -> exklusiver "Juwelensturm"-Trail (einmalig).
	ParkourDataStore = "YeetDenSnack_Parkour_v1",
	ParkourReturnDelay = 3, -- Sekunden Ergebnis angucken, dann Rück-Teleport zum Hub
	ParkourReadyTimeout = 60, -- Sekunden von Teleport bis Startlinie, sonst automatisch zurück
	ParkourCourses = {
		-- ── Die 5 kurzen (ca. 15-25s bei gutem Können) ──
		{
			Id = "Zuckerstange",
			Name = "🍭 Zuckerstangen-Sprint",
			Short = true,
			Color = Color3.fromRGB(255, 90, 110),
			Desc = "Breite Plattformen, kleine Hüpfer – der Einstieg.",
			Cooldown = 60,
			MaxTime = 120,
			MasterTime = 18,
			BaseCash = 50,
			BaseGems = 1,
			Tiers = { { Time = 15, Cash = 120, Gems = 3 }, { Time = 25, Cash = 80, Gems = 2 } },
		},
		{
			Id = "Schoko",
			Name = "🍫 Schoko-Hüpfturm",
			Short = true,
			Color = Color3.fromRGB(120, 72, 30),
			Desc = "Höhenstufen und heiße Schoko-Lava – nicht reintreten!",
			Cooldown = 75,
			MaxTime = 120,
			MasterTime = 22,
			BaseCash = 70,
			BaseGems = 1,
			Tiers = { { Time = 18, Cash = 180, Gems = 4 }, { Time = 30, Cash = 120, Gems = 3 } },
		},
		{
			Id = "Bonbon",
			Name = "🍬 Bonbon-Wirbel",
			Short = true,
			Color = Color3.fromRGB(120, 220, 255),
			Desc = "Rotierende Zuckerstangen-Balken – Timing ist alles!",
			Cooldown = 90,
			MaxTime = 150,
			MasterTime = 25,
			BaseCash = 90,
			BaseGems = 2,
			Tiers = { { Time = 20, Cash = 260, Gems = 5 }, { Time = 35, Cash = 170, Gems = 3 } },
		},
		{
			Id = "Waffel",
			Name = "🧇 Waffel-Wackelweg",
			Short = true,
			Color = Color3.fromRGB(230, 180, 90),
			Desc = "Blinkende Waffel-Platten – weg, wenn du zu langsam bist!",
			Cooldown = 90,
			MaxTime = 150,
			MasterTime = 28,
			BaseCash = 120,
			BaseGems = 2,
			Tiers = { { Time = 22, Cash = 360, Gems = 7 }, { Time = 40, Cash = 240, Gems = 4 } },
		},
		{
			Id = "Donut",
			Name = "🍩 Donut-Dash",
			Short = true,
			Color = Color3.fromRGB(255, 150, 200),
			Desc = "Fahrende Donuts, schmale Stege UND Wirbel – alles auf einmal!",
			Cooldown = 120,
			MaxTime = 180,
			MasterTime = 32,
			BaseCash = 160,
			BaseGems = 3,
			Tiers = { { Time = 25, Cash = 500, Gems = 9 }, { Time = 45, Cash = 330, Gems = 6 } },
		},
		-- ── Die 3 langen (ca. 45-120s bei gutem Können, mit Checkpoints) ──
		{
			Id = "Karamell",
			Name = "🍮 Karamell-Kletterturm",
			Short = false,
			Color = Color3.fromRGB(230, 170, 80),
			Desc = "Der große Turm: klettern, springen, nicht runterschauen!",
			Cooldown = 180,
			MaxTime = 300,
			MasterTime = 75,
			BaseCash = 400,
			BaseGems = 6,
			Tiers = { { Time = 60, Cash = 1200, Gems = 16 }, { Time = 100, Cash = 800, Gems = 11 } },
		},
		{
			Id = "Lakritz",
			Name = "🌪️ Lakritz-Labyrinth",
			Short = false,
			Color = Color3.fromRGB(60, 55, 65),
			Desc = "Schmale Lakritz-Stege, Wirbel und Blink-Passagen im Dunkeln.",
			Cooldown = 240,
			MaxTime = 360,
			MasterTime = 90,
			BaseCash = 600,
			BaseGems = 8,
			Tiers = { { Time = 75, Cash = 1800, Gems = 22 }, { Time = 120, Cash = 1200, Gems = 15 } },
		},
		{
			Id = "Vulkan",
			Name = "🌋 Schoko-Vulkan",
			Short = false,
			Color = Color3.fromRGB(255, 100, 40),
			Desc = "Das Finale: Lava-Sprints, Wirbel-Gauntlet, Wackel-Wände. Viel Glück.",
			Cooldown = 300,
			MaxTime = 420,
			MasterTime = 110,
			BaseCash = 900,
			BaseGems = 12,
			Tiers = { { Time = 90, Cash = 2800, Gems = 32 }, { Time = 150, Cash = 1900, Gems = 21 } },
		},
	},

	-- ══ Juwelen-Shop (NUR mit 💎 kaufbar – Juwelen gibt's NUR im Parkour!) ══
	-- GemEggs: wie Config.Eggs, aber GemCost statt Cost (deutlich bessere Chancen).
	GemEggs = {
		{
			Id = "Juwel",
			Name = "💎 Juwelen-Ei",
			GemCost = 45,
			Color = Color3.fromRGB(120, 230, 255),
			Desc = "Funkelt wie verrückt. KEINE Commons, fette Legendary-Chance!",
			Chances = { Rare = 25, Epic = 40, Legendary = 27, Mythic = 8 },
		},
	},
	-- GemTrails/GemSkins: exklusive Cosmetics (RewardOnly = nicht kaufbar,
	-- gibt's nur für die Parkour-Meisterschaft – alle 8 unter MasterTime).
	GemTrails = {
		{ Id = "Saphir", Name = "💠 Saphir-Schimmer", GemCost = 30, Color = Color3.fromRGB(80, 150, 255), Desc = "Kühles Funkeln für flinke Füße." },
		{ Id = "Diamant", Name = "💎 Diamant-Staub", GemCost = 75, Color = Color3.fromRGB(200, 245, 255), Desc = "Du läufst, es glitzert. Purer Protz." },
		{ Id = "Juwelensturm", Name = "🌈💎 Juwelensturm", RewardOnly = true, Rainbow = true, Color = Color3.fromRGB(150, 220, 255), Desc = "Meister-Belohnung: alle 8 Parcours unter der Meister-Zeit!" },
	},
	GemSkins = {
		{ Id = "Kristall", Name = "💎 Kristall-Körper", GemCost = 120, Color = Color3.fromRGB(150, 225, 255), Material = Enum.Material.Glass, Transparency = 0.35, Desc = "Durchsichtig, glänzend, unbezahlbar (fast)." },
	},

	-- ══ Promo-Codes ══
	-- Codes für YouTuber/TikTok-Shoutouts & Updates: einfach hier neue Zeilen
	-- ergänzen (KEINE Code-Änderung nötig), alte per Active=false abschalten.
	-- Jeder Account kann jeden Code nur EINMAL einlösen (im Profil gespeichert).
	-- Reward-Typen: Cash {Amount}, Egg {Egg="Basic|Golden|Mutant|Juwel"},
	-- Gems {Amount}, Trail {Trail="<Trail-Id>"}.
	PromoCodes = {
		{ Code = "YEETDENSNACK", Active = true, Reward = { Type = "Cash", Amount = 2500 } },
		{ Code = "SCHOKOLADE", Active = true, Reward = { Type = "Egg", Egg = "Basic" } },
		{ Code = "RELEASE", Active = true, Reward = { Type = "Egg", Egg = "Golden" } },
	},

	-- ══ Monetarisierung (Robux) ══
	-- Developer Products (mehrfach kaufbar) + VIP-Gamepass. Alle Ids sind
	-- PLATZHALTER (0), bis sie im Creator Dashboard angelegt sind – solange
	-- eine Id 0 ist, zeigt der Kauf-Button nur einen Hinweis-Toast.
	-- Quittierte Käufe (PurchaseId) landen im Receipt-DataStore, damit
	-- ProcessReceipt garantiert nur EINMAL auszahlt.
	Monetization = {
		ReceiptDataStore = "YeetDenSnack_Receipts_v1",
		VipGamepassId = 0, -- TODO: VIP-Gamepass im Creator Dashboard anlegen!
		VipCashBonusPercent = 0.1, -- dauerhafter Bonus aufs rohe Tresor-Einkommen
		BoostBonusPercent = 1, -- "2x Cash" = +100% Tresor-Einkommen solange aktiv
		Products = {
			{
				Id = "Boost2x",
				Name = "⚡ 2x Tresor-Cash (30 Min)",
				Desc = "Doppeltes Tresor-Einkommen für 30 Minuten – übersteht sogar Rejoins!",
				ProductId = 0, -- TODO: Developer Product anlegen und Id eintragen!
				DurationSeconds = 1800,
			},
			{
				Id = "VaultSell",
				Name = "💸 Tresor-Sofortverkauf",
				Desc = "Verkauft ALLE Tresor-Snacks sofort (Wert: 120 Sekunden Einkommen pro Snack).",
				ProductId = 0,
				SellSecondsWorth = 120,
			},
			{
				Id = "VaultSlots",
				Name = "🧰 +10 Tresor-Plätze (für immer)",
				Desc = "Dauerhaft 10 zusätzliche Tresor-Plätze – überlebt sogar Rebirths!",
				ProductId = 0,
				Slots = 10,
			},
			{
				Id = "EggBundle",
				Name = "🥚 Gold-Ei-Bundle (3 Stück)",
				Desc = "Drei Gold-Eier, sofort geöffnet – drück die Daumen!",
				ProductId = 0,
				Egg = "Golden",
				Count = 3,
			},
		},
	},

	-- ══ Debug/Test-Menü ══
	-- Im Studio ist das Menü IMMER sichtbar. Für Team Test/Live-Server hier UserIds eintragen:
	DebugUserIds = {
		1165289346, -- Rojan
	} :: { number },
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

-- Maximale Tresor-Plätze bei `rebirths` Rebirths und Basis-Level `baseLevel`.
-- `extraSlots` = dauerhaft gekaufte Zusatz-Plätze (Robux-Shop, überlebt Rebirths).
function Config.VaultLimit(rebirths: number, baseLevel: number?, extraSlots: number?): number
	return Config.VaultLimitBase
		+ rebirths * Config.VaultLimitPerRebirth
		+ Config.BaseLevelDef(baseLevel or 1).BonusSlots
		+ (extraSlots or 0)
end

-- Produkt-Lookup nach interner Id bzw. nach Roblox-ProductId
Config.MonetizationProductsById = {} :: { [string]: any }
for _, def in Config.Monetization.Products do
	Config.MonetizationProductsById[def.Id] = def
end

-- Erfolgschance für einen Merge mit `count` gleichen Snacks (Client-Anzeige + Server-Wurf
-- nutzen dieselbe Formel, damit die Anzeige nie lügt)
function Config.MergeChance(count: number): number
	return math.min(
		Config.MergeMaxChance,
		Config.MergeBaseChance + (count - Config.MergeMinCount) * Config.MergeChancePerExtra
	)
end

-- XP-Bedarf, um Season-Pass-Stufe `level` abzuschließen
function Config.SeasonLevelXp(level: number): number
	return math.floor(Config.SeasonPass.XpBase * Config.SeasonPass.XpFactor ^ (level - 1))
end

-- Aus Gesamt-XP: (abgeschlossene Stufe, XP in der aktuellen Stufe, Bedarf zur nächsten).
-- Bedarf = 0 heißt: Maximal-Stufe erreicht. Server-Vergabe und Client-Anzeige
-- nutzen exakt diese Funktion, damit der Fortschrittsbalken nie lügt.
function Config.SeasonProgress(xp: number): (number, number, number)
	local level = 0
	local remaining = xp
	while level < Config.SeasonPass.LevelCount do
		local need = Config.SeasonLevelXp(level + 1)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return level, 0, 0
end

-- ══ Abgeleitete Lookups (Server & Client nutzen dieselben) ══

Config.EggsById = {} :: { [string]: any }
for _, def in Config.Eggs do
	Config.EggsById[def.Id] = def
end
-- Juwelen-Eier laufen über dieselbe Id-Map (GrantEgg/Chancen-UI funktionieren
-- damit ohne Sonderfälle) – bezahlt wird nur anders (GemCost statt Cost).
for _, def in Config.GemEggs do
	Config.EggsById[def.Id] = def
end

Config.ParkourCoursesById = {} :: { [string]: any }
Config.ParkourCourseIndex = {} :: { [string]: number } -- Id -> Position in der Kette
for index, def in Config.ParkourCourses do
	Config.ParkourCoursesById[def.Id] = def
	Config.ParkourCourseIndex[def.Id] = index
end

-- Belohnung für einen Parkour-Lauf: beste Tier-Stufe, deren Zeitlimit gehalten
-- wurde, sonst Base. Server-Vergabe und Client-Anzeige nutzen dieselbe Funktion.
function Config.ParkourReward(courseDef: any, time: number): (number, number)
	for _, tier in courseDef.Tiers do
		if time <= tier.Time then
			return tier.Cash, tier.Gems
		end
	end
	return courseDef.BaseCash, courseDef.BaseGems
end

Config.EggPetsById = {} :: { [string]: any }
for _, def in Config.EggPets do
	Config.EggPetsById[def.Id] = def
end

Config.HousingDecorById = {} :: { [string]: any }
for _, def in Config.HousingDecor do
	Config.HousingDecorById[def.Id] = def
end

-- Chancen eines Eis als normalisierte Prozente (fürs UI, immer synchron zum Server-Wurf)
function Config.EggChancePercents(eggId: string): { [string]: number }
	local def = Config.EggsById[eggId]
	local result = {}
	if not def then
		return result
	end
	local total = 0
	for _, weight in def.Chances do
		total += weight
	end
	for rarity, weight in def.Chances do
		result[rarity] = weight / total * 100
	end
	return result
end

return Config
