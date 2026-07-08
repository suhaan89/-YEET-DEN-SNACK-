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

-- Gibt false zurück, wenn der Tresor voll war (Geschenk wird dann verschoben)
local function giveGift(player: Player): boolean
	local def = SnackTypes.RollRandom()
	if not BaseService.AddToVault(player, def.Name) then
		notifyRemote:FireClient(player, "🎁 Dein Spielzeit-Geschenk WARTET – erst Platz im Tresor schaffen! [R am Tresor]")
		return false
	end
	notifyRemote:FireClient(player, ("🎁 Spielzeit-Geschenk: %s! (+%d💰/s)"):format(def.Name, def.Income))
	sfxRemote:FireClient(player, "ding")
	if def.Announce then
		announceRemote:FireAllClients(
			("🎁 %s hat '%s' als Spielzeit-Geschenk gezogen! Glückspilz!"):format(player.Name, def.Name),
			def.Rarity
		)
	end
	return true
end

function RewardService.Init(services)
	BaseService = services.BaseService
	DataService = services.DataService

	notifyRemote = Remotes.Get("Notify") :: RemoteEvent
	announceRemote = Remotes.Get("Announce") :: RemoteEvent
	sfxRemote = Remotes.Get("Sfx") :: RemoteEvent

	-- Private-Server-Besitzer freundlich begrüßen (das Spiel läuft in
	-- Private Servers ohne Sonderfälle – Basen sind Claim-basiert, keine
	-- Logik hängt an "8 Spieler"; hier gibt's nur den Ehren-Gruß).
	local function greetPrivateOwner(player: Player)
		if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == player.UserId then
			task.delay(6, function()
				if player.Parent then
					notifyRemote:FireClient(
						player,
						"🔒 Willkommen auf DEINEM Privat-Server! Lad Freunde ein – der Freundes-Bonus gilt hier auch!"
					)
				end
			end)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		lastGift[player] = os.clock()
		greetPrivateOwner(player)
	end)
	for _, player in Players:GetPlayers() do
		lastGift[player] = os.clock()
		greetPrivateOwner(player)
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
					if giveGift(player) then
						lastGift[player] = now
					else
						-- Tresor voll: in ~60s nochmal probieren (statt alle 15s zu nerven)
						lastGift[player] = now - Config.PlaytimeGiftInterval + 60
					end
				end
			end
		end
	end)
end

return RewardService
