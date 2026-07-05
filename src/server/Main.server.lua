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
services.StyleService = require(servicesFolder.StyleService)
services.MergeService = require(servicesFolder.MergeService)

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
services.PetService.Init(services)
services.StyleService.Init(services)
services.MergeService.Init(services)

print("🍫 [YEET DEN SNACK] Server bereit – der Truck kommt gleich!")
