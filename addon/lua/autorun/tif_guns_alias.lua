-- TIF MW guns: each GTA gun's MW counterpart. TIF swaps them in when it picks a soldier's loadout (TIF.Loadout),
-- so anything that still names a GTA gun (custom factions, other addons, old saves) gets the baked MW gun.
-- Only applied when the MW gun is installed (TIF checks its definition). The smoke launcher stays (smoke).
if SERVER then AddCSLuaFile() end

local P = "weapon_tifmw_"
local A = {
	-- rifles
	assaultrifle = "akm", assaultrifle_mk2 = "ak_ff", compactrifle = "ak74u", advancedrifle = "an94",
	carbinerifle = "m4_sof_a", carbinerifle_mk2 = "m4_sof_b", specialcarbine = "scar", specialcarbine_mk2 = "m13_sof",
	tacticalrifle = "kilo_sof", bullpuprifle = "m13_sof", bullpuprifle_mk2 = "kilo_sof", militaryrifle = "fal",
	heavyrifle = "fal", battlerifle = "fal",
	-- marksman / sniper
	marksmanrifle = "ebr", marksmanrifle_mk2 = "ebr_sup", sniperrifle = "svd", precisionrifle = "sks",
	heavysniper = "rytec", heavysniper_mk2 = "rytec",
	-- machine guns
	mg = "pkm", combatmg = "m91", combatmg_mk2 = "bruen_sof",
	-- SMGs
	smg = "mp5", smg_mk2 = "mp5", microsmg = "uzi", minismg = "uzi", machinepistol = "uzi", assaultsmg = "mp7_sof",
	combatpdw = "mp7_sof",
	-- shotguns
	pumpshotgun = "m680", pumpshotgun_mk2 = "m680", combatshotgun = "m680_breach", assaultshotgun = "m680",
	bullpupshotgun = "m680", heavyshotgun = "m680",
	-- launchers
	rpg = "rpg7", grenadelauncher = "rpg7",
	-- pistols
	pistol = "m1911", pistol_mk2 = "m19", combatpistol = "x16", appistol = "x16_sof", heavypistol = "m1911_jav",
	pistol50 = "m1911",
}

TIF_WEAPON_ALIAS = TIF_WEAPON_ALIAS or {}
for gta, mw in pairs(A) do TIF_WEAPON_ALIAS["weapon_gtg_" .. gta] = P .. mw end
