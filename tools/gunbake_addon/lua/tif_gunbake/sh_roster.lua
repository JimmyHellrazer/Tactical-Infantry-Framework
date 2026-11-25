-- TIF gun bake roster: MW base presets to bake into single low-poly NPC guns.
-- Each entry: id, swep (MW base class), atts (attachment classes; slots left out stay default), kind (TIF weapon
-- kind: rifle / smg / lmg / shotgun / pistol / rpg), tiers (who carries it), suppressed (TIF def gets
-- MWA_Suppressed), tint (per part recolours applied offline: mag = "black"), note.
-- Lasers are cosmetic only (no beam). Rails, mounts and sight folding come from the MW base's own rules, since the
-- preset is applied through it before the export.
-- Keys marked "guess" were picked from names in the packs; the exporter reports any it couldn't apply.

TIF_GUNBAKE = TIF_GUNBAKE or {}

local R = {}
local function add(e) R[#R + 1] = e end

-- Assault rifles ---------------------------------------------------------------------------------------------
add{ id = "m4_sof_a", swep = "mg_mike4", kind = "rifle", tiers = { "infantry", "sof" },
	atts = { "att_vm_holo_west01", "attachment_vm_ar_mike4_laser01" },
	note = "SOF-lite: default furniture, holo, top-rail laser" }
add{ id = "m4_sof_b", swep = "mg_mike4", kind = "rifle", tiers = { "infantry", "sof" },
	atts = { "att_vm_reflex_west03", "attachment_vm_ar_mike4_laser02", "attachment_vm_ar_mike4_vertgrip01" },
	note = "SOF-lite with vertical foregrip (left-hand grip point)" }
add{ id = "m13_sof", swep = "mg_mcharlie", kind = "rifle", tiers = { "sof" }, suppressed = true,
	atts = { "att_vm_silencer04", "att_vm_reflex_west03" },
	note = "MCX: suppressed, Operator reflex, no foregrip" }
add{ id = "kilo_sof", swep = "mg_kilo433", kind = "rifle", tiers = { "sof" }, suppressed = true,
	atts = { "att_vm_silencer02", "att_vm_holo_west02", "attachment_vm_ar_kilo433_laser01" },
	note = "Kilo 141 SOF, made like the MCX" }
add{ id = "ak74u", swep = "mg_akilo47", kind = "rifle", tiers = { "rebel", "ru_infantry" },
	atts = { "attachment_vm_ar_akilo47_smgbarrel", "attachment_vm_ar_akilo47_smgstock_unfolded",
		"attachment_vm_ar_akilo47_smgmag" },
	note = "74U style: short barrel, skeleton stock, 5.45 mag" }
add{ id = "ak_ff", swep = "mg_akilo47", kind = "rifle", tiers = { "rebel" },
	atts = { "attachment_vm_ar_akilo47_receiver_v6", "attachment_vm_ar_akilo47_smgmag_v6" },
	note = "Freedom Fighter blueprint" }
add{ id = "akm", swep = "mg_akilo47", kind = "rifle", tiers = { "rebel", "ru_infantry" }, atts = {},
	note = "stock AKM" }
add{ id = "ak_warsaw_sup", swep = "mg_akilo47", kind = "rifle", tiers = { "ru_sof" }, suppressed = true,
	atts = { "attachment_vm_ar_akilo47_receiver_v12", "attachment_vm_ar_akilo47_barrel_v12",
		"attachment_vm_ar_akilo47_stock_v12", "attachment_vm_ar_akilo47_smgmag", "att_vm_silencer01",
		"att_vm_4x_east01_tall" },
	tint = { mag = "black" },
	note = "War Saw (Black Warsaw), Russian SOF: suppressed, VLK 3.0x, black 5.45 mag" }
add{ id = "ak_warsaw_grip", swep = "mg_akilo47", kind = "rifle", tiers = { "ru_sof" },
	atts = { "attachment_vm_ar_akilo47_receiver_v12", "attachment_vm_ar_akilo47_barrel_v12",
		"attachment_vm_ar_akilo47_stock_v12", "attachment_vm_ar_akilo47_smgmag", "attachment_vm_ar_akilo47_vertgrip01",
		"att_vm_reflex_east01" },
	tint = { mag = "black" },
	note = "War Saw, Russian SOF: foregrip, Viper reflex (MW19's Kobra), black 5.45 mag" }
add{ id = "fal", swep = "mg_falima", kind = "rifle", tiers = { "rebel", "infantry" }, atts = {}, note = "stock FAL" }
add{ id = "oden", swep = "mg_asierra12", kind = "rifle", tiers = { "ru_infantry" },
	atts = { "att_vm_4x_east01_tall" }, note = "Oden with VLK 3.0x" }
add{ id = "scar", swep = "mg_scharlie", kind = "rifle", tiers = { "infantry", "sof" },
	atts = { "attachment_vm_ar_scharlie_laser01", "att_vm_4x_west01_tall" },
	note = "SCAR: laser, Scout Combat Optic" }
add{ id = "an94", swep = "mg_anovember94", kind = "rifle", tiers = { "ru_sof" },
	atts = { "att_vm_holo_east01" }, note = "AN-94, APX5 holo" }
add{ id = "asval", swep = "mg_valpha", kind = "rifle", tiers = { "ru_sof" }, suppressed = true,
	atts = { "att_vm_reflex_east02_tall" }, note = "AS VAL (integral suppressor), Monocle reflex" }

-- Marksman ----------------------------------------------------------------------------------------------------
add{ id = "ebr", swep = "mg_mike14", kind = "rifle", tiers = { "infantry", "sof" },
	atts = { "att_vm_scope_mike14" }, note = "EBR, default chassis stock, full sniper scope" }
add{ id = "ebr_sup", swep = "mg_mike14", kind = "rifle", tiers = { "sof" }, suppressed = true,
	atts = { "att_vm_scope_mike14", "att_vm_silencer04" }, note = "EBR suppressed, sniper scope" }
add{ id = "sks", swep = "mg_sksierra", kind = "rifle", tiers = { "rebel" }, atts = {},
	note = "SKS, wooden (check the default stock is the wood one; else stockhvy2)" }
add{ id = "svd", swep = "mg_delta", kind = "rifle", tiers = { "rebel", "ru_infantry" },
	atts = { "attachment_vm_sn_delta_scope" }, note = "stock Dragunov with its PSO" }
add{ id = "svd_plague", swep = "mg_delta", kind = "rifle", tiers = { "ru_sof" },
	-- (the Plague Sore receiver puts its scope in the optic slot's 2nd place, the K498 holo's, when the gun is built)
	atts = { "attachment_vm_sn_delta_receiver_v2", "att_vm_2x_west02_holo" },
	swaps = { att_vm_2x_west02_holo = "attachment_vm_sn_delta_scope_v2" },
	note = "Plague Sore blueprint (grey)" }
add{ id = "m13_dmr", swep = "mg_mcharlie", kind = "rifle", tiers = { "sof" }, suppressed = true,
	atts = { "attachment_vm_ar_mcharlie_longbarrel", "att_vm_silencer01", "attachment_vm_ar_mcharlie_laser01",
		"att_vm_scope_vz" },
	note = "M13 long barrel DMR: suppressed, laser, variable zoom (no standalone bipod for the M13)" }

add{ id = "rytec", swep = "mg_xmike109", kind = "rifle", tiers = { "infantry", "sof" },
	atts = { "attachment_vm_sn_xmike109_scope" },
	note = "Rytec AMR (Barrett-style .50) with its own sniper scope" }

-- LMGs --------------------------------------------------------------------------------------------------------
add{ id = "pkm", swep = "mg_pkilo", kind = "lmg", tiers = { "rebel", "ru_infantry" }, atts = {}, note = "stock PKM" }
add{ id = "pkm_sof", swep = "mg_pkilo", kind = "lmg", tiers = { "ru_sof" },
	atts = { "att_vm_stock_heavy02", "attachment_vm_lm_pkilo_barrel_short", "att_vm_reflex_east01" },
	note = "least wood PKM: synthetic stock, short barrel, Viper reflex" }
add{ id = "m91", swep = "mg_kilo121", kind = "lmg", tiers = { "infantry" }, atts = {}, note = "stock M91" }
add{ id = "bruen", swep = "mg_mkilo3", kind = "lmg", tiers = { "infantry" }, atts = {}, note = "stock Bruen" }
add{ id = "bruen_sof", swep = "mg_mkilo3", kind = "lmg", tiers = { "sof" },
	atts = { "attachment_vm_lm_mkilo3_barhvy", "att_vm_4x_west01_tall" },
	note = "SOF Bruen: railed handguard (guess: XRK Horizon), Scout Combat Optic" }
add{ id = "mg34", swep = "mg_mgolf34", kind = "lmg", tiers = { "rebel" }, atts = {}, note = "stock MG34" }
add{ id = "finn", swep = "mg_sierrax", kind = "lmg", tiers = { "infantry", "sof" },
	atts = { "att_vm_holo_west02" }, note = "FiNN with a western holo" }

-- SMGs --------------------------------------------------------------------------------------------------------
add{ id = "mp7_sof", swep = "mg_mpapa7", kind = "smg", tiers = { "sof" }, suppressed = true,
	atts = { "attachment_vm_sm_mpapa7_vertgrip01", "att_vm_silencer04", "att_vm_reflex_west03" },
	note = "SOF CQB: foregrip, suppressor, reflex" }
add{ id = "mp5", swep = "mg_mpapa5", kind = "smg", tiers = { "infantry", "police" }, atts = {}, note = "stock MP5" }
add{ id = "uzi", swep = "mg_uzulu", kind = "smg", tiers = { "rebel" }, atts = {}, note = "stock Uzi" }
add{ id = "bizon", swep = "mg_beta", kind = "smg", tiers = { "ru_sof", "ru_infantry" },
	atts = { "att_vm_reflex_east01" }, note = "Bizon with Viper reflex" }

-- Shotguns ----------------------------------------------------------------------------------------------------
add{ id = "m680", swep = "mg_romeo870", kind = "shotgun", tiers = { "infantry", "police" }, atts = {},
	note = "full-size 680" }
add{ id = "m680_breach", swep = "mg_romeo870", kind = "shotgun", tiers = { "breacher" },
	atts = { "attachment_vm_sh_romeo870_barrel_sawn", "attachment_vm_sh_romeo870_stock_pistolgrip" },
	note = "shorty breacher (breachers switch to it)" }
add{ id = "m680_wood", swep = "mg_romeo870", kind = "shotgun", tiers = { "rebel" },
	atts = { "attachment_vm_sh_romeo870_pump_wood", "attachment_vm_sh_romeo870_stock_wood" },
	note = "insurgent 680, wood parts" }
add{ id = "db_short", swep = "mg_charlie725", kind = "shotgun", tiers = { "rebel" },
	atts = { "attachment_vm_sh_charlie725_barrel_sawnoff", "attachment_vm_sh_charlie725_stock_sawnoff" },
	note = "sawed-off 725, no stock" }
add{ id = "db_full", swep = "mg_charlie725", kind = "shotgun", tiers = { "rebel" }, atts = {}, note = "full 725" }

-- Pistols -----------------------------------------------------------------------------------------------------
add{ id = "x16", swep = "mg_glock", kind = "pistol", tiers = { "infantry", "police" }, atts = {}, note = "standard carry" }
add{ id = "x16_sof", swep = "mg_glock", kind = "pistol", tiers = { "sof" },
	atts = { "att_vm_pi_golf21_slide_long", "att_vm_compensator01_pstl", "att_vm_minireddot01" },
	note = "long slide, comp, red dot" }
add{ id = "m19", swep = "mg_p320", kind = "pistol", tiers = { "infantry", "sof" }, atts = {}, note = "stock M19" }
add{ id = "m1911_jav", swep = "mg_m1911", kind = "pistol", tiers = { "sof" },
	atts = { "attachment_vm_pi_mike1911_receiver_v5", "attachment_vm_pi_mike1911_slide_v5",
		"attachment_vm_pi_mike1911_mag_v5" },
	note = "Javelina blueprint (receiver, slide, mag)" }
add{ id = "m1911", swep = "mg_m1911", kind = "pistol", tiers = { "rebel" }, atts = {}, note = "stock 1911" }
add{ id = "sykov", swep = "mg_makarov", kind = "pistol", tiers = { "rebel", "ru_infantry", "ru_sof" }, atts = {},
	note = "Makarov" }

-- Launcher ----------------------------------------------------------------------------------------------------
add{ id = "rpg7", swep = "mg_rpapa7_mwii", kind = "rpg", tiers = { "rebel", "ru_infantry", "ru_sof", "infantry" },
	atts = {}, note = "RPG-7 (MWII)" }

TIF_GUNBAKE.Roster = R
TIF_GUNBAKE.ById = {}
for _, e in ipairs(R) do TIF_GUNBAKE.ById[e.id] = e end
