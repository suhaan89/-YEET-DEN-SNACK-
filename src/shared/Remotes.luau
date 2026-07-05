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
}

local FUNCTIONS = {
	"BuyUpgrade", -- Client -> Server: Upgrade kaufen, gibt {ok, msg} zurück
	"DoRebirth", -- Client -> Server: Sugar-Rush-Rebirth
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
