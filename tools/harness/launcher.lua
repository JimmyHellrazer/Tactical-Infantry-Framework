local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function IsValid(e) return e ~= nil and e ~= false and (type(e) ~= "table" or not e.removed) end
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
math.Rand = function(a, b) return (a + b) / 2 end
local VM = {}
VM.__index = VM
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VM) end
function VM.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VM.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function VM:DistToSqr(o) local d = self - o return d.x * d.x + d.y * d.y + d.z * d.z end
function VM:Distance(o) return math.sqrt(self:DistToSqr(o)) end
local cvars = {}
function CreateConVar(n, d) local c = { v = d } c.GetInt = function() return tonumber(c.v) end c.GetFloat = function() return tonumber(c.v) end cvars[n] = c return c end
FCVAR_ARCHIVE = 1
MASK_SOLID_BRUSHONLY, MASK_SHOT = 1, 2
local sky = true
local traceHitPos
util = { TraceLine = function(t)
	if t.mask == MASK_SOLID_BRUSHONLY then return { Hit = not sky, HitSky = false } end
	return { Entity = nil, HitPos = traceHitPos or t.endpos }
end }
timer = { Simple = function(_, f) f() end }
player = { GetAll = function() return {} end }
local said = {}
local events = {}

local DEFS = {
	weapon_tifmw_rpg7 = { projectile = {}, hold = "rpg" },
	weapon_tifmw_at4 = { projectile = {}, hold = "rpg", disposable = true },
	weapon_tifmw_akm = { hold = "rifle" },
	weapon_tifmw_m4_sof_a = { hold = "rifle" },
	weapon_tifmw_m1911 = { hold = "pistol" },
}
TIF = {
	Factions = {},
	GTG = { DEFAULT_HOST = "mw_male", WeaponDef = function(c) return DEFS[c] end,
		WeaponKind = function(c) local d = DEFS[c] return d and d.hold == "pistol" and "pistol" or "rifle" end },
	REL_HOSTILE = 2, REL_ALLY = 0,
	Soldiers = {},
	Say = function(npc, ev) said[#said + 1] = { npc, ev } end,
	Event = function(...) events[#events + 1] = { ... } end,
	Anim = { MODE_AIM = 1 },
	Move = { Stop = function() end },
	ProneB = { Is = function() return false end },
	Morale = { Shaken = function() return false end },
	CoverBehave = { In = function() return false end, Leave = function() end },
}
function TIF.Relation(a, b) return (a.side == b.side) and 0 or 2 end
assert(loadfile(ROOT .. "tif/config/sh_content.lua"))()

local p, s, l = TIF.Loadout({ loadouts = { default = { primary = { "weapon_tifmw_akm" } }, rpg = { primary = { "weapon_tifmw_rpg7" }, secondary = { "weapon_tifmw_m1911" } } } }, "rpg")
check(p == "weapon_tifmw_akm", "old rpg-primary loadout: rifle from the default primaries")
check(l == "weapon_tifmw_rpg7", "old rpg-primary loadout: the rpg moves to the launcher slot")
check(s == "weapon_tifmw_m1911", "secondary kept")
p, s, l = TIF.Loadout(TIF.Factions.usmc, "rpg")
check(not TIF.IsLauncherClass(p), "usmc AT gunner carries a rifle")
check(l == "weapon_tifmw_at4", "usmc AT gunner: AT4")
p, s, l = TIF.Loadout(TIF.Factions.insurgents, "rpg")
check(l == "weapon_tifmw_rpg7" and not TIF.IsLauncherClass(p), "insurgent AT gunner: rifle + RPG-7")
p, s, l = TIF.Loadout(TIF.Factions.russians, "rpg")
check(l == "weapon_tifmw_rpg7" and not TIF.IsLauncherClass(p), "russian AT gunner: rifle + RPG-7")
p, s, l = TIF.Loadout(TIF.Factions.insurgents, "rifleman")
check(l == nil, "riflemen carry no launcher")
p, s, l = TIF.Loadout("usmc", "rpg")
check(l == "weapon_tifmw_at4", "Loadout takes a faction id")

local switched = {}
local W = {
	Switch = function(npc, slot, now, opts)
		if npc.tifSwitch or not npc.tifArms[slot] then return false end
		switched[#switched + 1] = { slot = slot, opts = opts }
		npc.tifSwitch = { to = slot }
		return true
	end,
}
TIF.Weapon = W
assert(loadfile(ROOT .. "tif/tactics/sv_launcher.lua"))()
local L = TIF.Launcher
check(L.Rockets(DEFS.weapon_tifmw_rpg7) == 2, "reusable: tif_rpg_rockets (2)")
check(L.Rockets(DEFS.weapon_tifmw_at4) == 1, "disposable: 1")

local function soldier(side, pos, launcher)
	local n = { side = side, tifArch = {}, tifStance = 0, tifSquad = nil, pos = pos }
	n.GetPos = function() return n.pos end
	n.Health = function() return 100 end
	n.Visible = function() return true end
	n.tifFire = {}
	n.tifSlot = "primary"
	n.tifArms = { primary = { class = "weapon_tifmw_akm", ammo = 30 }, secondary = { class = "weapon_tifmw_m1911", ammo = 7 } }
	if launcher then
		n.tifArms.launcher = { class = launcher, def = DEFS[launcher], ammo = 1, rockets = L.Rockets(DEFS[launcher]) }
	end
	return n
end
local function target(side, pos)
	local e = soldier(side, pos)
	e.IsVehicle = function() return false end
	e.IsPlayer = function() return false end
	e.GetClass = function() return "tif_soldier" end
	e.WorldSpaceCenter = function() return e.pos + Vector(0, 0, 40) end
	return e
end

local now = 100
local gunner = soldier("a", Vector(0, 0, 0), "weapon_tifmw_at4")
local foe = target("b", Vector(1200, 0, 0))
TIF.Soldiers = { gunner, foe }
local c = { ent = foe, pos = foe.pos, visible = true }
check(not L.Consider(gunner, c, now), "first look only arms the first-contact delay")
check(gunner.tifLaunchNext and gunner.tifLaunchNext > now, "first-contact delay set")
now = now + 20
cvars.tif_rpg_lone_chance.v = "0"
gunner.tifLaunchCheck = 0
check(not L.Consider(gunner, c, now), "lone soldier, lone chance 0: keeps the rifle")
local f2 = target("b", Vector(1250, 60, 0))
local f3 = target("b", Vector(1180, -80, 0))
TIF.Soldiers = { gunner, foe, f2, f3 }
gunner.tifLaunchCheck = 0
check(L.Worth(gunner, c, now) == "cluster", "3 enemies inside 250: a cluster")
local ally = target("a", Vector(1210, 20, 0))
TIF.Soldiers = { gunner, foe, f2, f3, ally }
check(not L.Consider(gunner, c, now), "friendly near the impact point: no rocket")
TIF.Soldiers = { gunner, foe, f2, f3 }
gunner.tifLaunchCheck = 0
sky = false
check(not L.Consider(gunner, c, now), "indoors: no rocket")
sky = true
gunner.tifLaunchCheck = 0
gunner.tifCQB = {}
check(not L.Consider(gunner, c, now), "room clearing: no rocket")
gunner.tifCQB = nil
gunner.tifLaunchCheck = 0
local near = { ent = foe, pos = Vector(300, 0, 0), visible = true }
check(not L.Consider(gunner, near, now), "too close (< 500): no rocket")
gunner.tifLaunchCheck = 0
said = {}
check(L.Consider(gunner, c, now), "cluster in range, clear, outdoors: draws the launcher")
check(switched[#switched].slot == "launcher", "switch to the launcher slot")
check(gunner.tifLaunch and gunner.tifLaunch.kind == "cluster", "launch state kept with its reason")
local warned = false
for _, s2 in ipairs(said) do if s2[2] == "contact_rpg" and s2[1].side == "b" then warned = true end end
check(warned, "an enemy who sees him shouts RPG")

gunner.tifSwitch = nil
gunner.tifSlot = "launcher"
check(L.Think(gunner, c, now), "launcher in hand: Think owns the tick")
check(gunner.tifFire.want == false, "settling: no fire yet")
check(not L.Ready(gunner, now), "not ready during the settle")
now = now + 1.2
L.Think(gunner, c, now)
check(L.Ready(gunner, now) and gunner.tifFire.want, "settled: fires")
gunner.tifArms.launcher.rockets = 0
L.Fired(gunner, now)
check(gunner.tifLaunchNext >= now + L.GAP[1], "per-soldier gap after a shot")
check(foe.tifRocketedAt == now, "target marked")
L.Think(gunner, c, now + 0.1)
check(gunner.tifFire.want == false, "after the shot: holds")
L.Think(gunner, c, now + L.HOLD_AFTER + 0.01)
local sw = switched[#switched]
check(sw.slot == "primary" and sw.opts and sw.opts.drop and sw.opts.clip == "at4_drop", "spent AT4: drop clip, back to the rifle, tube dropped")

local rpg = soldier("a", Vector(0, 0, 0), "weapon_tifmw_rpg7")
local sq = {}
rpg.tifSquad = sq
rpg.tifLaunchNext = 0
rpg.tifLaunch = { target = foe, kind = "lone", started = now, seenAt = now }
rpg.tifSlot = "launcher"
L.Think(rpg, c, now)
now = now + 1.3
L.Think(rpg, c, now)
rpg.tifArms.launcher.rockets = 1
L.Fired(rpg, now)
check(sq.tifLaunchNext == now + L.SQUAD_GAP, "squad gap set")
L.Think(rpg, c, now + L.HOLD_AFTER + 0.01)
sw = switched[#switched]
check(sw.slot == "primary" and not (sw.opts and sw.opts.drop), "RPG-7 with rockets left: stowed on the back")

local mate = soldier("a", Vector(50, 0, 0), "weapon_tifmw_rpg7")
mate.tifSquad = sq
mate.tifLaunchNext = 0
check(L.Blocked(mate, c, now + 1) == "squad cooldown", "squadmate waits for the squad gap")
local other = soldier("a", Vector(0, 400, 0), "weapon_tifmw_rpg7")
other.tifLaunchNext, other.tifLaunchCheck = 0, 0
cvars.tif_rpg_lone_chance.v = "1"
TIF.Soldiers = { other, foe }
check(not L.Consider(other, c, now + 5), "same target inside the target gap: no second rocket")
local veh = target("b", Vector(1500, 0, 0))
veh.IsVehicle = function() return true end
veh.tifRocketedAt = now
other.tifLaunchCheck = 0
check(L.Consider(other, { ent = veh, pos = veh.pos, visible = true }, now + 5), "vehicles ignore the target gap")

local ADDON = ROOT:gsub("lua/$", "")
local function exists(path) local fh = io.open(path, "rb") if fh then fh:close() return true end return false end
local src = io.open(ROOT .. "tif/gta/weapons/weapon_tifmw_at4.lua"):read("*a")
check(src:find('WorldModel = "models/tif_guns/at4.mdl"', 1, true) ~= nil, "AT4 uses its own model")
check(src:find("disposable = true", 1, true) ~= nil, "AT4 is disposable")
check(src:find('spentModel = "models/tif_guns/at4_spent.mdl"', 1, true) ~= nil, "AT4 names its spent tube")
for _, f in ipairs({ "models/tif_guns/at4.mdl", "models/tif_guns/at4.vvd", "models/tif_guns/at4.dx90.vtx",
	"models/tif_guns/at4_spent.mdl", "models/tif_guns/at4_spent.phy", "materials/tif_guns/at4.vmt",
	"materials/tif_guns/at4/at4_rgb.vtf", "materials/tif_guns/at4/at4_n.vtf", "materials/tif_guns/at4/at4_e.vtf",
	"sound/tif/at4/shot_04.ogg", "sound/tif/at4/tail_03.ogg", "sound/tif/at4/tail_in_03.ogg" }) do
	check(exists(ADDON .. f), f .. " on disk")
end

local stuck = soldier("a", Vector(0, 0, 0), "weapon_tifmw_rpg7")
stuck.tifLaunch = { target = foe, kind = "lone", started = now, seenAt = now }
stuck.tifSlot = "launcher"
L.Think(stuck, c, now)
L.Think(stuck, { ent = foe, pos = foe.pos, visible = false }, now + L.LOST + 0.5)
sw = switched[#switched]
check(sw.slot == "primary", "target lost: puts the launcher away without firing")
do
	local vmt = io.open(ROOT .. "../materials/tif_guns/at4.vmt"):read("*a")
	check(not vmt:find("$color2", 1, true) and not vmt:find("$blendtintbybasealpha", 1, true), "AT4 material: no tint (DXT1 texture, no alpha: the black $color2 covered the whole tube)")
	local gh = io.open(ROOT .. "tif/npc/cl_gunhold.lua"):read("*a")
	check(gh:find("M.DISPOSABLE_LIFT = 5", 1, true) and gh:find("local grip = c - fwd * M.BACK_DIST - up * (8 - lift)", 1, true), "the AT4 rides higher on the back than the RPG-7")
	check(gh:find("M.BACK_DIST = 6.5", 1, true) ~= nil, "launchers slung closer to the back (6.5 behind the chest, was 9)")
	local jg = io.open(ROOT .. "tif/gta/clips/zz_jgun.lua"):read("*a")
	check(jg:find('["sdr_com_exp_stand_rpg_drop_to_exp_stand"] = true', 1, true) and jg:find('["sdr_com_exp_crouch_rpg_drop_to_exp_stand"] = true', 1, true)
		and jg:find('["sdr_com_exp_stand_rpg_drop_to_exp_stand_pstl"] = true', 1, true), "AT4 drops: the drawn weapon stays in the hand (the gun bone carries the dropped tube away)")
	local ghp = io.open(ROOT .. "../../tools/guns/gun_holds.py")
	if ghp then check(ghp:read("*a"):find("|_rpg_drop_to_exp_stand(_pstl)?$", 1, true) ~= nil, "and gun_holds.py keeps them that way") end
end
local bodySrc = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
check(bodySrc:find("\telse\n\t\tent:SetupBones()\n\tend\n\n\tif TIF.GunHold then\n\t\tTIF.GunHold.Post(ent, st)\n\tend", 1, true) ~= nil, "slung launcher / rifle follow the body with no gun in hand (downed, surrendered)")
print(string.format("passed %d, failed %d", pass, fail))
