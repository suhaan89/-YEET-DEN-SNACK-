--[[
	SoundFx.luau
	Sound-Effekte NUR mit eingebauten Roblox-Sounds (rbxasset://) –
	funktioniert also sofort ohne hochgeladene Assets.
	Positionale Sounds werden nur abgespielt, wenn sie nah genug
	an der Kamera passieren (Config.SfxMaxDistance).

	Später in Studio: Ids hier einfach gegen richtige Marketplace-Sounds
	tauschen (Kaching, Cartoon-Slap, Hupe, ...).
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SoundFx = {}

local SOUNDS: { [string]: { Id: string, Volume: number, Speed: number? } } = {
	slap = { Id = "rbxasset://sounds/ouch.ogg", Volume = 0.9 },
	oof = { Id = "rbxasset://sounds/oof.ogg", Volume = 1 }, -- der Klassiker 💀
	explosion = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.6 },
	grab = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.7 },
	throw = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.8 },
	bank = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 1, Speed = 1.5 },
	ding = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 1, Speed = 2 },
}

-- name: Schlüssel aus SOUNDS. position: optional, für Entfernungs-Check.
function SoundFx.Play(name: string, position: Vector3?)
	local def = SOUNDS[name]
	if not def then
		return
	end

	-- Zu weit weg? Dann interessiert's uns nicht.
	if position then
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude > Config.SfxMaxDistance then
			return
		end
	end

	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	-- Leichte Tonhöhen-Variation, damit es nie doppelt gleich klingt
	sound.PlaybackSpeed = (def.Speed or 1) * (0.92 + math.random() * 0.16)
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 5)
end

return SoundFx
