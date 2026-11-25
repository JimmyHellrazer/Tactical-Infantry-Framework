-- Voice test (from sh_voices.lua, 0.38.11).

local TIF = TIF
local V = TIF.Voice

concommand.Add("tif_voice_test", function(ply, _, args)
	if not TIF.CanUseDev(ply) or not IsValid(ply) then return end
	local packId, event = args[1] or "mercenary", args[2] or "contact"
	local snd = V.Play(ply, packId, event)
	TIF.Log(snd and ("Played " .. snd) or ("No line for " .. packId .. "/" .. event))
end, nil, "tif_voice_test <pack> <event>: play a voice line on yourself (packs: mercenary, bf3marine, securityforce, securityforcevip)")
