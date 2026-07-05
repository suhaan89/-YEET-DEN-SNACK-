--[[
	RewardService.luau
	Spielzeit-Geschenke: Alle Config.PlaytimeGiftInterval Sekunden bekommt
	jeder Spieler einen zufälligen Snack direkt in den Tresor.

	Zweck: Anti-Frust-Mechanik. Auch wer im PvP alles verliert oder (noch)
	nicht gut yeetet, baut langsam Einkommen auf und bleibt im Spiel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SnackTypes = require(ReplicatedStorage.Shared.SnackTypes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RewardService = {}

local BaseService, DataService -- in Init verdrahtet

local notifyRemote: RemoteEvent
local announceRemote: RemoteEvent
local sfxRemote: RemoteEvent

local lastGift: { [Player]: number } = {}

local function giveGift(player: Player)
	local def = SnackTypes.RollRandom()
	BaseService.AddToVault(player, def.Name)
	notifyRemote:FireClient(player, ("🎁 Spielzeit-Geschenk: %s! (+%d💰/s)"):format(def.Name, def.Income))
	sfxRemote:FireClient(player, "ding")
	if def.Announce then
		announceRemote:FireAllClients(
			("🎁 %s hat '%s' als Spielzeit-Geschenk gezogen! Glückspilz!"):format(player.Name, def.Name),
			def.Rarity
		)
	end
end

function RewardService.Init(services)
	BaseService = services.BaseService
	DataService = services.DataService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	Players.PlayerAdded:Connect(function(player)
		lastGift[player] = os.clock()
	end)
	for _, player in Players:GetPlayers() do
		lastGift[player] = os.clock()
	end
	Players.PlayerRemoving:Connect(function(player)
		lastGift[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.clock()
			for player, last in lastGift do
				-- Nur beschenken, wenn Daten geladen sind und eine Basis existiert
				if now - last >= Config.PlaytimeGiftInterval
					and DataService.Get(player)
					and BaseService.GetBaseOf(player)
				then
					lastGift[player] = now
					giveGift(player)
				end
			end
		end
	end)
end

return RewardService
