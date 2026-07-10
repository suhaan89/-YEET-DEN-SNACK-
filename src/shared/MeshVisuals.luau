--[[
	MeshVisuals.luau
	Kleiner Helfer, um Platzhalter-Parts (Truck, Snacks, Tresor) optisch durch
	echte Meshes zu ersetzen, sobald wir MeshIds aus der Toolbox haben.

	WARUM SpecialMesh statt MeshPart?
	- MeshPart.MeshId ist zur Laufzeit NICHT per Skript setzbar (nur über den
	  asynchronen Umweg AssetService:CreateMeshPartAsync, der das komplette
	  Part austauschen würde – inkl. Welds, Touched-Verbindungen, Kollision).
	- Eine SpecialMesh hängt dagegen einfach IM bestehenden Part: Die gesamte
	  Spiellogik (Größe, Kollision, Welds, Touched, Attribute) bleibt exakt
	  wie bisher, nur die Optik wird ersetzt. Perfekt für unseren Fall.

	WO die echten IDs eingetragen werden:
	- Truck + Tresor:  src/shared/Config.luau      → Config.Meshes
	- Snacks:          src/shared/SnackTypes.luau  → SnackTypes.Meshes

	Solange dort der Platzhalter "rbxassetid://0" steht, passiert hier NICHTS
	und die bisherige Block-/Kugel-Optik bleibt aktiv (Fallback).
]]

export type MeshConfig = {
	MeshId: string?, -- "rbxassetid://0" = Platzhalter -> Fallback auf simple Geometrie
	TextureId: string?, -- optional; leer lassen -> Mesh übernimmt die Part-Farbe
	MeshScale: Vector3?, -- Faktor auf die ORIGINAL-Größe des Meshes (nicht der Part-Größe!)
}

local MeshVisuals = {}

local PLACEHOLDER_ID = "rbxassetid://0"

-- Ist in dieser Config eine echte MeshId eingetragen?
function MeshVisuals.HasMesh(config: MeshConfig?): boolean
	if not config then
		return false
	end
	local id = config.MeshId
	return id ~= nil and id ~= "" and id ~= PLACEHOLDER_ID
end

--[[
	Hängt eine SpecialMesh an das bestehende Part, falls eine echte MeshId
	konfiguriert ist. Gibt true zurück, wenn ein Mesh angewendet wurde.

	Wichtig fürs Einstellen der Größe: SpecialMesh.Scale skaliert relativ zur
	Original-Größe des importierten Meshes – NICHT relativ zur Part.Size.
	Also nach dem Eintragen der MeshId im Spiel anschauen und MeshScale so
	lange anpassen, bis das Mesh optisch zur Kollisions-Box (Part.Size) passt.
]]
function MeshVisuals.Apply(part: BasePart, config: MeshConfig?): boolean
	if not MeshVisuals.HasMesh(config) then
		return false
	end
	local cfg = config :: MeshConfig

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "VisualMesh"
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = cfg.MeshId :: string
	if cfg.TextureId and cfg.TextureId ~= "" then
		mesh.TextureId = cfg.TextureId :: string
	end
	mesh.Scale = cfg.MeshScale or Vector3.one
	mesh.Parent = part

	return true
end

return MeshVisuals
