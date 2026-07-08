--[[
	Main.server.lua
	Bootstrap für "YEET DEN SNACK!" – verdrahtet alle Services in der
	richtigen Reihenfolge. Services kommunizieren über die geteilte
	`services`-Tabelle (einfaches Dependency-Wiring ohne Framework).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes-Ordner anlegen (muss VOR allen Services passieren)
require(ReplicatedStorage.Shared.Remotes)

local servicesFolder = script.Parent.Services
local modulesFolder = script.Parent.Modules

local services = {}
services.Ragdoll = require(modulesFolder.Ragdoll)
services.DataService = require(servicesFolder.DataService)
services.PlayerService = require(servicesFolder.PlayerService)
services.MapService = require(servicesFolder.MapService)
services.BaseService = require(servicesFolder.BaseService)
services.SnackService = require(servicesFolder.SnackService)
services.SlapService = require(servicesFolder.SlapService)
services.TruckService = require(servicesFolder.TruckService)
services.ShopService = require(servicesFolder.ShopService)
services.RewardService = require(servicesFolder.RewardService)
services.PetService = require(servicesFolder.PetService)
services.SeasonPassService = require(servicesFolder.SeasonPassService)
services.StyleService = require(servicesFolder.StyleService)
services.MergeService = require(servicesFolder.MergeService)
services.GoldenSnackService = require(servicesFolder.GoldenSnackService)
services.AchievementService = require(servicesFolder.AchievementService)
services.FriendService = require(servicesFolder.FriendService)
services.ReferralService = require(servicesFolder.ReferralService)
services.HousingService = require(servicesFolder.HousingService)
services.MonetizationService = require(servicesFolder.MonetizationService)
services.PromoCodeService = require(servicesFolder.PromoCodeService)
services.GemService = require(servicesFolder.GemService)
services.ParkourService = require(servicesFolder.ParkourService)
services.AtmosphereService = require(servicesFolder.AtmosphereService)
services.DebugService = require(servicesFolder.DebugService)

-- Reihenfolge ist wichtig: Daten -> Spieler -> Map -> Gameplay
services.DataService.Init()
services.PlayerService.Init(services)
services.MapSlots = services.MapService.Build()
services.BaseService.Init(services)
services.SnackService.Init(services)
services.SlapService.Init(services)
services.TruckService.Init(services)
services.ShopService.Init(services)
services.RewardService.Init(services)
services.GemService.Init(services) -- vor Pet/Style (die verkaufen gegen Juwelen)
services.PetService.Init(services)
services.SeasonPassService.Init(services) -- nach PetService (zahlt Eier als Belohnung aus)
services.StyleService.Init(services)
services.MergeService.Init(services)
services.GoldenSnackService.Init(services) -- nach SeasonPassService (vergibt XP)
services.AchievementService.Init(services) -- nach BaseService (umhüllt TryCrack)
services.FriendService.Init(services)
services.ReferralService.Init(services) -- nach PetService (zahlt Eier als Prämie aus)
services.HousingService.Init(services) -- nach BaseService (liest GetBaseOf)
services.MonetizationService.Init(services) -- nach Pet/BaseService (zahlt Eier aus, liest Tresor)
services.PromoCodeService.Init(services) -- nach Pet/GemService (zahlt Eier/Juwelen aus)
services.ParkourService.Init(services) -- nach GemService (Juwelen/Freischaltung)
services.AtmosphereService.Init(services) -- Grafik-Politur: Lighting, Wolken, Map-Deko
services.DebugService.Init(services) -- als Letztes: greift auf alle anderen Services zu

print("🍫 [YEET DEN SNACK] Server bereit – der Truck kommt gleich!")
