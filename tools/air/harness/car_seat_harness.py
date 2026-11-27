"""Offline check of tif_mw_cars' soldier seat code (base_tif_mw_car.lua TIFSeatPose / TIFSeatEntry / TIFRideThink /
door lookup) against every car's generated seat data and the clips built into tif_mw_anims, under LuaJIT (lupa)
with small GMod stubs.
usage: python -I car_seat_harness.py"""
import glob
import os
import re
import sys

from lupa import LuaRuntime

ADDON = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\tif_mw_cars\lua"
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
SERVER, CLIENT = true, false
Glide = {}
function AddCSLuaFile() end
function DEFINE_BASECLASS() end
BaseClass = {}
function isfunction(f) return type(f) == "function" end
function IsValid(e) return e ~= nil and e ~= false end
local V = {}
V.__index = V
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function V:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function CreateConVar(n, d) return { GetBool = function() return d ~= "0" end } end
FCVAR_ARCHIVE = 0
math.Rand = function(a, b) return (a + b) / 2 end
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end  -- (GMod's LuaJIT has it; this Lua doesn't)
math.Clamp = function(v, a, b) return v < a and a or (v > b and b or v) end
math.NormalizeAngle = function(a) a = a % 360 if a > 180 then a = a - 360 end return a end
math.AngleDifference = function(a, b) return math.NormalizeAngle(a - b) end
hooks = {}
hook = { Add = function(ev, id, f) hooks[ev] = hooks[ev] or {} hooks[ev][id] = f end }
CurTime = function() return 100 end
known = {}
looped = {}
TIF = { Action = {
  Clip = function(npc, name) return (npc.has == nil or npc.has[name] ~= false) and known[name] and {} or nil end,
  Loop = function(npc, name) looped[npc] = name end } }
""")
data = os.path.join(ADDON, "tif_mw_cars", "data")
for f in sorted(glob.glob(os.path.join(data, "*.lua"))):
    lua.execute(open(f, encoding="utf-8").read())
clip_dir = os.path.join(ADDON, "..", "..", "tactical_infantry_framework", "lua", "tif", "gta", "clips")
clips = "\n".join(open(f, encoding="utf-8").read() for f in sorted(glob.glob(os.path.join(clip_dir, "mw_male_p*.lua"))))
roles = set(re.findall(r'\["(mw[a-z]{2}_s\d_[a-z0-9_]+)"\]', clips))
for r in roles:
    lua.execute('known["%s"] = true' % r)
lua.execute("ENT = {}")
lua.execute(open(os.path.join(ADDON, "entities", "base_tif_mw_car.lua"), encoding="utf-8").read())
fails = 0


def check(ok, msg, quiet=False):
    global fails
    if not ok:
        fails += 1
    if not ok or not quiet:
        print(("ok   " if ok else "FAIL ") + msg)


run = lua.eval(r"""function(car, n, enemyY)
  local e = setmetatable({ MWCar = car }, { __index = ENT })
  function e:WorldToLocal(p) return p end
  local npc = { tifPrimaryC = enemyY and { pos = Vector(0, enemyY, 0) } or nil }
  return e:TIFSeatPose(n, npc), e:TIFSeatEntry(n, npc)
end""")
cars = lua.eval("TIF_MW_CAR_SEATS")
for car in sorted(cars.keys()):
    seats = cars[car]
    nseat = len(lua.eval('TIF_MW_CARS["%s"].seats' % car))
    rows = [seats[i] for i in range(1, len(seats) + 1)]
    check(all(r["n"] <= nseat for r in rows), "%s: %d soldier seats within its %d Glide seats" % (car, len(rows), nseat))
    for r in rows:
        n = r["n"]
        pose, e = run(car, n, None)
        check(pose is not None and pose["clip"] in roles, "%s seat %d pose %s built" % (car, n, r["idle"]), quiet=True)
        if r["entry"] is not None:
            check(e is not None and e["getIn"] in roles and e["rootz"], "%s seat %d entry built" % (car, n), quiet=True)
            for k in ("getOut", "combatOut", "jumpOut"):
                role = e[k]
                if role is not None:
                    check(role in roles and 0 < e["release"][role] <= 1, "%s seat %d %s %s" % (car, n, k, role), quiet=True)
            if r["entry"]["door"] is not None:
                d = r["entry"]["door"]
                check(len(d["keys"]) > 2, "%s seat %d entry door %s (%d keys)" % (car, n, d["bone"], len(d["keys"])), quiet=True)
        else:
            check(e is None, "%s seat %d: no entry -> TIF puts him in from the door" % (car, n), quiet=True)
        if r["gunner"] is not None:
            check(r["gunner"] in roles, "%s seat %d gunner loop %s built" % (car, n, r["gunner"]), quiet=True)
    print("ok   %s: %d seats checked (%d with entries, %d gunners)" % (
        car, len(rows), sum(1 for r in rows if r["entry"] is not None), sum(1 for r in rows if r["gunner"] is not None)))

# gunner: turns toward the enemy, fires once facing it, back to the seat pose when it's gone
gun = lua.eval(r"""function(car, n)
  local e = setmetatable({ MWCar = car }, { __index = ENT })
  function e:WorldToLocal(p) return p end
  local ang
  local npc = { tifFire = {}, tifSeatLYaw = 0, tifSeatClip = "seatpose",
    GetPos = function() return Vector(0, 0, 0) end, GetLocalPos = function() return Vector(0, 0, 0) end,
    SetLocalAngles = function(_, a) ang = a end }
  local ent = { WorldSpaceCenter = function() return Vector(0, 500, 0) end }
  npc.tifPrimaryC = { visible = true, ent = ent, pos = Vector(0, 500, 0) }
  local out = {}
  local busy = e:TIFRideThink(npc, n, 100)
  out.first = { busy = busy, fire = npc.tifFire.want, yaw = ang and ang.y, loop = looped[npc] }
  for i = 1, 8 do e:TIFRideThink(npc, n, 100 + i * 0.1) end
  out.later = { fire = npc.tifFire.want, yaw = ang and ang.y }
  npc.tifPrimaryC = nil
  local b2 = e:TIFRideThink(npc, n, 101)
  out.gone = { busy = b2, yaw = ang and ang.y, loop = looped[npc], fire = npc.tifFire.want }
  return out
end""")
o = gun("tundra", 6)
check(o["first"]["busy"] and not o["first"]["fire"] and o["first"]["loop"] == "mwtd_s5_aim",
      "tundra bed gunner: takes over, gun-up loop %s, holds fire while turning (yaw %.0f)" % (o["first"]["loop"], o["first"]["yaw"]))
check(o["later"]["fire"] and abs(o["later"]["yaw"] - 90) < 1, "  ...faces the enemy (yaw %.0f) and fires" % o["later"]["yaw"])
check(not o["gone"]["busy"] and o["gone"]["yaw"] == 0 and o["gone"]["loop"] == "seatpose" and not o["gone"]["fire"],
      "  ...enemy gone: back to the seat pose, facing the seat")
c = lua.eval(r"""function()
  local e = setmetatable({ MWCar = "tundra" }, { __index = ENT })
  return e:TIFRideThink({ tifFire = {} }, 1, 100)
end""")()
check(not c, "tundra driver: not a gunner (TIF's own riding)")
door = lua.eval(r"""function()
  local nw = {}
  local veh = { MWCar = "ram1500", SetNW2String = function(_, k, v) nw[k] = v end, SetNW2Float = function(_, k, v) nw[k] = v end }
  hooks.TIF_SeatClip.tif_mw_cars_doors({}, veh, 1, "in", "mwrp_s0_entry")
  return nw["mwd_tag_door_front_left"], nw["mwdt_tag_door_front_left"]
end""")
c, t = door()
check(c == "mwrp_s0_entry" and t == 100, "RAM seat 1 entry swings tag_door_front_left (%s @ %s)" % (c, t))
print("failed:", fails)
sys.exit(1 if fails else 0)
