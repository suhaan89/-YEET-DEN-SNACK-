--[[
	SnackTypes.luau
	Alle Snack-Definitionen mit Rarität, Drop-Gewicht, Einkommen und Optik.

	Weight   = relative Drop-Wahrscheinlichkeit (höher = häufiger)
	Income   = Cash pro Sekunde, wenn der Snack im Tresor liegt
	Slowdown = Multiplikator auf die Wurfkraft (schwere Snacks fliegen kürzer)
	Announce = true -> Server-weite Ankündigung, wenn jemand ihn aufhebt (Zielscheibe!)
]]

local SnackTypes = {}

SnackTypes.RarityColors = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(85, 200, 85),
	Rare = Color3.fromRGB(70, 130, 255),
	Epic = Color3.fromRGB(170, 80, 255),
	Legendary = Color3.fromRGB(255, 170, 30),
	Mythic = Color3.fromRGB(255, 60, 60),
	Secret = Color3.fromRGB(20, 20, 20),
}

SnackTypes.List = {
	{
		Name = "Keks-Krümel",
		Rarity = "Common",
		Weight = 38,
		Income = 1,
		Color = Color3.fromRGB(196, 164, 132),
		Size = Vector3.new(1.5, 1, 1.5),
		Slowdown = 1,
		Announce = false,
	},
	{
		Name = "Gummibär",
		Rarity = "Common",
		Weight = 28,
		Income = 2,
		Color = Color3.fromRGB(255, 100, 100),
		Size = Vector3.new(1.5, 2, 1),
		Slowdown = 1,
		Announce = false,
	},
	{
		Name = "Schoko-Taler",
		Rarity = "Uncommon",
		Weight = 16,
		Income = 5,
		Color = Color3.fromRGB(120, 72, 30),
		Size = Vector3.new(2, 0.5, 2),
		Slowdown = 0.95,
		Announce = false,
	},
	{
		Name = "KitKat Klassik",
		Rarity = "Rare",
		Weight = 9,
		Income = 12,
		Color = Color3.fromRGB(200, 30, 30),
		Size = Vector3.new(3, 1, 1.2),
		Slowdown = 0.9,
		Announce = false,
	},
	{
		Name = "Riesen-Donut",
		Rarity = "Epic",
		Weight = 5,
		Income = 30,
		Color = Color3.fromRGB(255, 150, 200),
		Size = Vector3.new(3.5, 1.2, 3.5),
		Slowdown = 0.75,
		Announce = false,
	},
	{
		Name = "Goldener KitKat",
		Rarity = "Legendary",
		Weight = 2.4,
		Income = 80,
		Color = Color3.fromRGB(255, 215, 0),
		Size = Vector3.new(3.5, 1.2, 1.4),
		Slowdown = 0.65,
		Announce = true,
	},
	{
		Name = "Der Verbotene Riegel",
		Rarity = "Mythic",
		Weight = 0.9,
		Income = 250,
		Color = Color3.fromRGB(90, 0, 120),
		Size = Vector3.new(4, 1.5, 1.6),
		Slowdown = 0.55,
		Announce = true,
	},
	{
		Name = "El Cacao Supremo",
		Rarity = "Secret",
		Weight = 0.2,
		Income = 1000,
		Color = Color3.fromRGB(15, 10, 5),
		Size = Vector3.new(5, 2, 2),
		Slowdown = 0.4,
		Announce = true,
	},
}

-- Schneller Zugriff über den Namen (fürs Laden aus dem DataStore)
SnackTypes.ByName = {}
for _, def in SnackTypes.List do
	SnackTypes.ByName[def.Name] = def
end

-- Gewichteter Zufalls-Drop
function SnackTypes.RollRandom()
	local totalWeight = 0
	for _, def in SnackTypes.List do
		totalWeight += def.Weight
	end
	local roll = math.random() * totalWeight
	for _, def in SnackTypes.List do
		roll -= def.Weight
		if roll <= 0 then
			return def
		end
	end
	return SnackTypes.List[1] -- Fallback (sollte nie passieren)
end

return SnackTypes
