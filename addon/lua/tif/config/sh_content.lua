local TIF = TIF
TIF.Factions = TIF.Factions or {}

function TIF.RegisterFaction(id, def)
	def.id = id
	def.host = def.host or TIF.GTG.DEFAULT_HOST
	if def.retarget then
		TIF.Modular = TIF.Modular or {}
		TIF.Modular.Retarget = TIF.Modular.Retarget or {}
		local function flag(list) for _, m in ipairs(list or {}) do if isstring(m) then TIF.Modular.Retarget[string.lower(m)] = true end end end
		flag(def.models)
		for _, v in ipairs(def.variants or {}) do flag(v.models) end
	end
	TIF.Factions[id] = def
	if TIF.ClearRelationCache then TIF.ClearRelationCache() end
	return def
end

local function pick(list)
	if not list or #list == 0 then return nil end
	return list[math.random(#list)]
end

function TIF.WeaponAlias(class)
	local a = class and TIF_WEAPON_ALIAS and TIF_WEAPON_ALIAS[class]
	if a and TIF.GTG.WeaponDef(a) then return a end
	return class
end

local function is_launcher(class)
	local def = class and TIF.GTG.WeaponDef(TIF.WeaponAlias(class))
	return def ~= nil and def.projectile ~= nil
end
TIF.IsLauncherClass = is_launcher

local function pick_gun(list)
	local out = {}
	for _, c in ipairs(list or {}) do if not is_launcher(c) then out[#out + 1] = c end end
	return pick(out)
end

function TIF.Loadout(fac, archId)
	if isstring(fac) then fac = TIF.Factions[fac] or {} end
	fac = fac or {}
	local L = fac.loadouts or {}
	local l = L[archId or ""] or L.default or {}
	local d = L.default or {}
	local primary = pick(l.primary) or pick(d.primary) or pick(fac.weapons) or "weapon_tifmw_m4_sof_a"
	local secondary = pick(l.secondary) or pick(d.secondary)
	local launcher = pick(l.launcher)
	if is_launcher(primary) then
		launcher = launcher or primary
		primary = pick_gun(l.rifle) or pick_gun(d.primary) or pick_gun(fac.weapons) or "weapon_tifmw_m4_sof_a"
	end
	return TIF.WeaponAlias(primary), TIF.WeaponAlias(secondary), launcher and TIF.WeaponAlias(launcher) or nil
end

local function mw(list)
	local out = {}
	for i, id in ipairs(list) do out[i] = "weapon_tifmw_" .. id end
	return out
end

local INS2 = "models/tif_factions/ins2/"

TIF.RegisterFaction("insurgents", {
	name = "Insurgents",
	side = "enemy",
	models = { INS2 .. "insurgent_light.mdl", INS2 .. "insurgent_standard.mdl", INS2 .. "insurgent_heavy.mdl" },
	voices = { "mercenary", "tif_arab_rebel", "tif_arab_operative" },
	weapons = mw({ "akm", "ak74u", "ak_ff" }),
	loadouts = {
		default = { primary = mw({ "akm", "akm", "ak74u", "ak_ff", "ak_ff", "fal" }), secondary = mw({ "m1911", "sykov" }) },
		assault = { primary = mw({ "ak74u", "uzi", "uzi", "db_short" }), secondary = mw({ "m1911" }) },
		guard = { primary = mw({ "akm", "uzi", "m680_wood" }), secondary = mw({ "m1911" }) },
		support = { primary = mw({ "pkm", "mg34" }), secondary = mw({ "uzi" }) },
		marksman = { primary = mw({ "svd", "sks" }), secondary = mw({ "m1911" }) },
		rpg = { primary = mw({ "akm", "ak74u", "ak_ff" }), secondary = mw({ "m1911" }), launcher = mw({ "rpg7" }) },
		breacher = { primary = mw({ "m680_wood", "db_full" }), secondary = mw({ "m1911" }) },
	},
})

TIF.RegisterFaction("usmc", {
	name = "US Marines",
	side = "ally",
	models = { INS2 .. "security_light.mdl", INS2 .. "security_standard.mdl", INS2 .. "security_heavy.mdl" },
	voices = { "bf3marine", "specops" },
	weapons = mw({ "m4_sof_a", "m4_sof_b", "scar" }),
	loadouts = {
		default = { primary = mw({ "m4_sof_a", "m4_sof_b", "scar" }), secondary = mw({ "x16" }) },
		assault = { primary = mw({ "mp5", "m4_sof_b" }), secondary = mw({ "x16" }) },
		support = { primary = mw({ "m91", "bruen" }), secondary = mw({ "x16" }) },
		marksman = { primary = mw({ "ebr", "ebr_sup" }), secondary = mw({ "x16" }) },
		rpg = { primary = mw({ "m4_sof_a", "m4_sof_b" }), secondary = mw({ "x16" }), launcher = mw({ "at4" }) },
		breacher = { primary = mw({ "m680_breach" }), secondary = mw({ "x16" }) },
	},
})

do
	local usmc = TIF.Factions.usmc
	TIF.RegisterFaction("usmc_woodland", {
		name = "US Marines (MARPAT Woodland)",
		side = "ally",
		models = { INS2 .. "marpat_light.mdl", INS2 .. "marpat_standard.mdl", INS2 .. "marpat_heavy.mdl" },
		voices = { "bf3marine", "specops" },
		relationsAs = "usmc",
		weapons = table.Copy(usmc.weapons),
		loadouts = table.Copy(usmc.loadouts),
	})
end

local BF4RU = "models/tif_factions/bf4ru/"
local function bf4ru(list)
	local out = {}
	for i, n in ipairs(list) do out[i] = BF4RU .. n .. ".mdl" end
	return out
end

TIF.RegisterFaction("russians", {
	name = "Russian Ground Forces",
	side = "enemy",
	models = bf4ru({ "soldier_a", "soldier_a_balaclava", "soldier_b", "soldier_b_balaclava", "soldier_c",
		"soldier_c_balaclava", "soldier_baku", "soldier_baku_balaclava", "soldier_aftermath", "soldier_aftermath_balaclava",
		"soldier_emr", "soldier_emr_balaclava", "recon_a", "recon_b", "recon_b_balaclava" }),
	voices = { "mercenary" },
	weapons = mw({ "ak_warsaw_grip", "ak_warsaw_sup", "an94" }),
	loadouts = {
		default = { primary = mw({ "ak_warsaw_grip", "ak_warsaw_grip", "ak_warsaw_sup", "an94", "an94" }), secondary = mw({ "sykov" }) },
		rifleman = { primary = mw({ "oden", "oden", "ak_warsaw_grip", "ak_warsaw_sup", "an94" }), secondary = mw({ "sykov" }) },
		assault = { primary = mw({ "ak74u", "ak74u", "asval", "bizon", "ak_warsaw_grip" }), secondary = mw({ "sykov" }) },
		guard = { primary = mw({ "ak_warsaw_sup", "bizon" }), secondary = mw({ "sykov" }) },
		support = { primary = mw({ "pkm_sof" }), secondary = mw({ "bizon" }) },
		marksman = { primary = mw({ "svd_plague" }), secondary = mw({ "sykov" }) },
		rpg = { primary = mw({ "ak_warsaw_grip", "an94" }), secondary = mw({ "sykov" }), launcher = mw({ "rpg7" }) },
		breacher = { primary = mw({ "asval", "bizon" }), secondary = mw({ "sykov" }) },
	},
})

TIF.FactionAlias = TIF.FactionAlias or {}
for old, new in pairs({ militia = "insurgents", pmc = "usmc" }) do
	TIF.FactionAlias[old] = new
	local def = table.Copy(TIF.Factions[new])
	def.hidden, def.alias = true, new
	TIF.RegisterFaction(old, def)
end
