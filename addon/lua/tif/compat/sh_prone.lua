-- wOS prone mod adapter. TIF reuses only its ValveBiped sequences and holdtype table;
-- the mod's player logic is not used for NPCs.

local TIF = TIF
TIF.Prone = TIF.Prone or {}
local A = TIF.Prone

-- Sequences the prone stance needs on the visual model.
A.SEQUENCES = { "pronedown_stand", "proneup_stand", "prone_ar2", "prone_walktwohand", "prone_smg1", "prone_passive" }

function A.Present()
	return istable(prone) and istable(prone.Animations)
end

-- Idle and moving prone sequence names for a weapon holdtype.
function A.SequencesFor(holdtype)
	local wa = A.Present() and prone.Animations.WeaponAnims
	if not wa then return "prone_ar2", "prone_walktwohand" end
	return wa.idle[holdtype] or wa.idle.ar2, wa.moving[holdtype] or wa.moving.ar2
end
