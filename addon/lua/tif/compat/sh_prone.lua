local TIF = TIF
TIF.Prone = TIF.Prone or {}
local A = TIF.Prone

A.SEQUENCES = { "pronedown_stand", "proneup_stand", "prone_ar2", "prone_walktwohand", "prone_smg1", "prone_passive" }

function A.Present()
	return istable(prone) and istable(prone.Animations)
end

function A.SequencesFor(holdtype)
	local wa = A.Present() and prone.Animations.WeaponAnims
	if not wa then return "prone_ar2", "prone_walktwohand" end
	return wa.idle[holdtype] or wa.idle.ar2, wa.moving[holdtype] or wa.moving.ar2
end
