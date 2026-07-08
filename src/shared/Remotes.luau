--[[
	Remotes.luau
	Erstellt (Server) bzw. findet (Client) alle RemoteEvents/RemoteFunctions.
	Zugriff immer über Remotes.Get("Name") – nie Instanzen hart verdrahten.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"Slap", -- Client -> Server: Slap ausführen
	"ThrowRequest", -- Client -> Server: gehaltenen Snack yeeten (charge 0..1)
	"Announce", -- Server -> alle Clients: großes Banner (text, rarityColorName?)
	"Notify", -- Server -> ein Client: kleine Toast-Nachricht
	"Fling", -- Server -> ein Client: eigene Velocity setzen (Client besitzt die Charakter-Physik!)
	"Sfx", -- Server -> alle Clients: Sound abspielen (name, position?)
	"OpenShop", -- Server -> ein Client: Shop-UI öffnen (shopId: "Upgrade"|"Pets"|"Style"|"Merge")
	"AchievementUnlocked", -- Server -> ein Client: Achievement-Popup (name, desc)
	"ParkourResult", -- Server -> ein Client: Lauf-Ergebnis {Name, Time, Cash, Gems, ServerRecord, PersonalBest}
	"ParkourLeave", -- Client -> Server: Parcours freiwillig verlassen (zurück zum Hub, keine Belohnung)
}

local FUNCTIONS = {
	"BuyUpgrade", -- Client -> Server: Upgrade kaufen, gibt {ok, msg} zurück
	"DoRebirth", -- Client -> Server: Sugar-Rush-Rebirth
	"BuyPet", -- Client -> Server: (Legacy) Direktkauf – gibt nur noch einen Hinweis auf Eier zurück
	"EquipPet", -- Client -> Server: Pet-Slot togglen (petId) bzw. alle ablegen (""), gibt {ok, msg} zurück
	"BuyEgg", -- Client -> Server: Ei kaufen & öffnen (eggId), gibt {ok, msg, Pet?, Duplicate?, Refund?} zurück
	"BuyTrail", -- Client -> Server: Trail kaufen (trailId), gibt {ok, msg} zurück
	"EquipTrail", -- Client -> Server: Trail ausrüsten/ablegen (trailId oder ""), gibt {ok, msg} zurück
	"BuySkin", -- Client -> Server: Charakter-Skin kaufen (skinId), gibt {ok, msg} zurück
	"EquipSkin", -- Client -> Server: Skin anziehen/ablegen (skinId oder ""), gibt {ok, msg} zurück
	"GetCollections", -- Client -> Server: eigene Pets/Trails + Ausrüstung abfragen
	"GetVault", -- Client -> Server: eigenen Tresor-Inhalt abfragen (Liste von Snack-Namen)
	"DoMerge", -- Client -> Server: Merge versuchen (snackName, count), gibt {ok, success?, msg} zurück
	"GetAchievements", -- Client -> Server: eigene Achievement-Stats + Freischaltungen abfragen
	"GetReferralInfo", -- Client -> Server: eigenen Referral-Code + Einladungs-Statistik abfragen
	"RedeemReferral", -- Client -> Server: Referral-Code einlösen (code), gibt {ok, msg} zurück
	"RedeemPromoCode", -- Client -> Server: Promo-Code einlösen (code), gibt {ok, msg} zurück
	"GetLeaderboards", -- Client -> Server: gecachte globale Top-Listen abfragen (KEIN DataStore-Hit)
	"GetDailyInfo", -- Client -> Server: Login-Streak-Status abfragen {CanClaim, Streak, NextIndex}
	"ClaimDailyReward", -- Client -> Server: Tagesbelohnung abholen, gibt {ok, msg, Streak?} zurück
	"GetHousing", -- Client -> Server: eigene Deko (gekauft + platziert) abfragen
	"BuyDecor", -- Client -> Server: Deko-Objekt kaufen (decorId), gibt {ok, msg} zurück
	"PlaceDecor", -- Client -> Server: Deko aufstellen/entfernen (decorId, place), gibt {ok, msg} zurück
	"DebugCommand", -- Client -> Server: Debug-Menü ("list" oder Command-Id) – nur Whitelist/Studio!
}

local Remotes = {}
local folder: Folder

if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	for _, name in FUNCTIONS do
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.Get(name: string): Instance
	return folder:WaitForChild(name)
end

return Remotes
