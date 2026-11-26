if SERVER then
	AddCSLuaFile()
end

local P = "weapon_tifmw_"
local A = {
	assaultrifle = "akm", assaultrifle_mk2 = "ak_ff", compactrifle = "ak74u", advancedrifle = "an94",
	carbinerifle = "m4_sof_a", carbinerifle_mk2 = "m4_sof_b", specialcarbine = "scar", specialcarbine_mk2 = "m13_sof",
	tacticalrifle = "kilo_sof", bullpuprifle = "m13_sof", bullpuprifle_mk2 = "kilo_sof", militaryrifle = "fal",
	heavyrifle = "fal", battlerifle = "fal",

	marksmanrifle = "ebr", marksmanrifle_mk2 = "ebr_sup", sniperrifle = "svd", precisionrifle = "sks",
	heavysniper = "rytec", heavysniper_mk2 = "rytec",

	mg = "pkm", combatmg = "m91", combatmg_mk2 = "bruen_sof",

	smg = "mp5", smg_mk2 = "mp5", microsmg = "uzi", minismg = "uzi", machinepistol = "uzi", assaultsmg = "mp7_sof",
	combatpdw = "mp7_sof",

	pumpshotgun = "m680", pumpshotgun_mk2 = "m680", combatshotgun = "m680_breach", assaultshotgun = "m680",
	bullpupshotgun = "m680", heavyshotgun = "m680",

	rpg = "rpg7", grenadelauncher = "rpg7",

	pistol = "m1911", pistol_mk2 = "m19", combatpistol = "x16", appistol = "x16_sof", heavypistol = "m1911_jav",
	pistol50 = "m1911",
}

TIF_WEAPON_ALIAS = TIF_WEAPON_ALIAS or {}

for gta, mw in pairs(A) do
	TIF_WEAPON_ALIAS["weapon_gtg_" .. gta] = P .. mw
end
