-- Flashlights on dark maps: some soldiers carry a weapon light, on while patrolling, searching and fighting
-- (as in CoD). The server only decides who (NW2 bool "tif_light"); clients draw it (npc/cl_flashlight.lua:
-- projected lights for the nearest few, a glow for the rest).
--   tif_flashlights 0 off, 1 always, 2 auto (dark maps: map or sky name, or a mode's TIF.Flashlight.Set).
--   Who: the squad leader and about LIGHT_SHARE of the others (decided once per soldier). Not in vehicles,
--   downed or surrendered.

local TIF = TIF

TIF.Flashlight = TIF.Flashlight or {}
local FL = TIF.Flashlight

FL.LIGHT_SHARE = 0.6
FL.MAP_WORDS = { "night", "dark", "dusk", "nite", "evening", "midnight", "_n_" }
FL.SKY_WORDS = { "night", "dark", "dusk", "borealis", "black", "_09", "moon" }

local cv = CreateConVar("tif_flashlights", "2", FCVAR_ARCHIVE, "Soldier flashlights: 0 off, 1 always, 2 dark maps only")

-- A mode can say it's night (true), day (false) or leave it to the map (nil).
function FL.Set(state) FL.Override = state end

local function has_word(s, words)
	s = string.lower(s or "")
	for _, w in ipairs(words) do if string.find(s, w, 1, true) then return true end end
	return false
end

function FL.Dark()
	local mode = cv:GetInt()
	if mode == 0 then return false end
	if mode == 1 then return true end
	if FL.Override ~= nil then return FL.Override end
	if FL.mapDark == nil then
		local sky = GetConVar("sv_skyname")
		FL.mapDark = has_word(game.GetMap(), FL.MAP_WORDS) or has_word(sky and sky:GetString() or "", FL.SKY_WORDS)
	end
	return FL.mapDark
end

local function carries(npc)
	if npc.tifHasLight == nil then
		local sq = npc.tifSquad
		npc.tifHasLight = (sq and sq.leader == npc) or math.random() < FL.LIGHT_SHARE
	end
	return npc.tifHasLight
end

timer.Create("tif_flashlights", 1, 0, function()
	local dark = FL.Dark()
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) then
			local on = dark and not npc.tifDead and not npc.tifVeh and not npc.tifDowned and not npc.tifSurrendered
				and npc:GetTIFWeapon() ~= "" and carries(npc)
			if npc:GetNW2Bool("tif_light", false) ~= on then npc:SetNW2Bool("tif_light", on) end
		end
	end
end)
