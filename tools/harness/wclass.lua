-- Offline: TIF.Anim.Legs weapon-class sets (sh_anim.lua) and TIF.GTG.WeaponKind (sh_gtg.lua) on real clip data.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
for _, c in pairs(clips) do if c.move then c.travel = math.deg(math.atan2(c.move[2], c.move[1])) end end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
SERVER, CLIENT = true, false
local defs = { weapon_gtg_pumpshotgun = { hold = "pump" }, weapon_gtg_combatshotgun = { hold = "combat_shotgun" },
	weapon_gtg_mg = { hold = "mg" }, weapon_gtg_combatmg = { hold = "combat_mg" }, weapon_gtg_rpg = { hold = "rpg" },
	weapon_gtg_pistol = { hold = "pistol" }, weapon_gtg_carbinerifle = { hold = "carbine" }, weapon_gtg_microsmg = { hold = "micro_smg" } }
-- sh_gtg's WeaponKind only needs WeaponDef: pull the KIND block out of the real file.
local src = io.open(ROOT .. "tif/compat/sh_gtg.lua"):read("*a")
local block = src:match("(local KIND = %b{}.-function A%.WeaponKind%(class%).-\nend)")
assert(block, "WeaponKind block not found")
local A = { WeaponDef = function(c) return defs[c] end }
assert(load("local A = ...\n" .. block))(A)
for c, want in pairs({ weapon_gtg_pumpshotgun = "shotgun", weapon_gtg_combatshotgun = "shotgun", weapon_gtg_mg = "lmg",
	weapon_gtg_combatmg = "lmg", weapon_gtg_rpg = "rpg", weapon_gtg_pistol = "pistol", weapon_gtg_carbinerifle = "rifle",
	weapon_gtg_microsmg = "smg" }) do
	check(A.WeaponKind(c) == want, c .. " -> " .. want .. " (got " .. tostring(A.WeaponKind(c)) .. ")")
end
-- every kind but rifle has its reloads, crouched reloads and cover reloads
for _, k in ipairs({ "pistol", "shotgun", "rpg", "lmg" }) do
	check(clips["mw_reload_" .. k] and clips["mw_reload_" .. k].ub, k .. ": standing reload, upper body")
	check(clips["mw_reload_" .. k .. "_cr"] ~= nil, k .. ": crouched reload")
	for _, t in ipairs({ "ls", "rs", "cr" }) do check(clips["mwc_" .. t .. "_reload_" .. k] ~= nil, k .. ": cover reload " .. t) end
end
check(clips.mw_reload_cr ~= nil, "rifle: crouched reload")
check(clips.mw_fire_shotgun_1 == nil and clips.mw_fire_rpg_1 == nil, "additive fire gestures not built (arms thrown up)")
check(clips.lmg_alert_idle == nil, "feet-together LMG idle not built")

-- Legs
TIF = { GTG = { Clips = function(id) return id == "mw_male" and clips or nil end, Clip = function(n) return clips[n] end },
	Error = print }
local fn = assert(loadfile(ROOT .. "tif/npc/sh_anim.lua"))
local ok, err = pcall(fn)
if not ok then print("sh_anim load: " .. tostring(err)) end
local L = TIF.Anim and TIF.Anim.Legs("mw_male")
check(L ~= nil, "legs built")
if L then
	check(L.lmg and L.lmg.aim.idle == clips.lmg_idle and L.lmg.aim.walk == L.aim.walk and L.lmg.aim.walkSpeed == L.aim.walkSpeed,
		"LMG: own aimed idle, rifle strafes and speeds")
	check(L.lmg.alert == L.alert, "LMG: the rifle's alert posture")
	check(L.rpg and L.rpg.aim.idle == clips.rpg_idle and L.rpg.crouch.idle == clips.rpg_crouch_idle and L.crouch.idle ~= clips.rpg_crouch_idle,
		"RPG: shoulder idles standing and crouched, rifle's untouched")
	check(L.shotgun == nil and L.rifle == nil, "shotgun and rifle use the rifle set")
	check(L.smg and L.smg.relaxed.sprint == clips.smg_sprint and L.relaxed.sprint ~= clips.smg_sprint and L.smg.aim == L.aim, "SMG: own sprint, rifle's untouched")
	check(L.prone.reload == clips.mwp_reload and L.prone.reloadPistol == clips.mwp_reload_pistol, "prone reloads")
	check(L.prone.bipod and L.prone.bipod.aim.aim9 and L.prone.bipod.aim.aim9.yaw > 60, "prone bipod with its aim blend")
	-- 0.38.12: the RPG's own sets everywhere (not the rifle's with the launcher in rifle hands)
	local R = L.rpg
	local function all_named(set, prefix)
		if not set or #set < 8 then return false end
		for _, e in ipairs(set) do if not string.find(e.name, "^" .. prefix) then return false end end
		return true
	end
	check(R and all_named(R.aim.walk, "rpg_mstg_walk_") and all_named(R.aim.run, "rpg_mstg_run_"), "RPG: own 8-way aimed strafes")
	check(R and all_named(R.crouch.walk, "rpg_crouch_walk_") and all_named(R.crouch.run, "rpg_crouch_run_"), "RPG: own crouched strafes")
	check(all_named(L.aim.walk, "mstg_walk_") and all_named(L.crouch.walk, "crouch_mstg_walk_"), "rifle strafes untouched")
	check(R and R.relaxed.idle == clips.rpg_calm_idle and R.relaxed.walk == clips.rpg_calm_walk and R.relaxed.run == clips.rpg_calm_run
		and R.relaxed.sprint == clips.rpg_calm_sprint and R.relaxed.variants == nil and R.relaxed.walkVariants == nil, "RPG: calm set, launcher lowered")
	check(L.relaxed.idle ~= clips.rpg_calm_idle and L.relaxed.walk == clips.walk, "rifle calm set untouched")
	check(R and R.alert and R.alert.idle == clips.rpg_alert_idle and R.alert.walk == clips.rpg_alert_walk and L.alert.idle ~= clips.rpg_alert_idle,
		"RPG: alert set, launcher half up; rifle's untouched")
	check(R and R.aim.walkSpeed and R.aim.walkSpeed > 60 and R.relaxed.walkSpeed > 20 and R.alert.walkSpeed > 20, "RPG speeds from its clips")
	check(clips.rpg_idle and clips.rpg_idle.frames > 10 and clips.rpg_crouch_idle.frames > 10, "RPG idles animate (not the 2-frame aim pose)")
end
print(string.format("passed %d, failed %d", pass, fail))
