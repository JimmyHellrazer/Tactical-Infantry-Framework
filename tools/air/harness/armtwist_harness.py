"""Offline check of TIF.Modular.ArmTwist (tif/config/sh_modular.lua) on a real codport skeleton: the model in its rest
pose, then the hand rolled about the forearm; prints what the pass does to the forearm, Wrist and Shoulder helpers
(positions must stay put, rolls should be the configured shares).
usage: python -I armtwist_harness.py"""
import math
import os
import struct

import numpy as np
from lupa import LuaRuntime

A = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
MODEL = "models/tif_cod_factions/usmc_body_basic_ar_1.mdl"
lua = LuaRuntime(unpack_returned_tuples=True)


class F:
    def __init__(self, data):
        self.d, self.p = data, 0
    def Seek(self, _s, p): self.p = int(p)
    def Read(self, _s, n):
        b = self.d[self.p:self.p + int(n)]; self.p += int(n); return b.decode("latin1")
    def ReadLong(self, _s):
        v = struct.unpack_from("<i", self.d, self.p)[0]; self.p += 4; return v
    def ReadFloat(self, _s):
        v = struct.unpack_from("<f", self.d, self.p)[0]; self.p += 4; return v
    def Size(self, _s): return len(self.d)
    def Close(self, _s): pass


def open_game(path, *_):
    for r in [os.path.join(A, d) for d in os.listdir(A)]:
        p = os.path.join(r, path.replace("/", os.sep))
        if os.path.isfile(p):
            f = F(open(p, "rb").read()); t = lua.table()
            for k in ("Seek", "Read", "ReadLong", "ReadFloat", "Size", "Close"):
                t[k] = getattr(f, k)
            return t
    return None


lua.globals().py_open = open_game
lua.execute(r"""
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH, HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG = 0,1,2,3,4,5,6,7
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end }
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
math.Clamp = function(v, a, b) return v < a and a or (v > b and b or v) end
FCVAR_ARCHIVE, FCVAR_REPLICATED = 0, 0
function CreateConVar() return { GetFloat = function() return 1 end } end
function CurTime() return 0 end
function istable(t) return type(t) == "table" end
function isstring(s) return type(s) == "string" end
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
file = { Open = function(p) return py_open(p) end, Read = function() return nil end }
local Vm = {}
Vm.__index = Vm
Vm.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
Vm.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vm) end
function Angle(...) return { ... } end
local Mm = {}
Mm.__index = Mm
function Matrix(t) return setmetatable({ t = t }, Mm) end
function Mm:ToTable() return self.t end
hook = { Add = function() end }
TIFG = { PMS = {} }
SERVER, CLIENT = false, true
TIF = { GTG = {} }
""")
pm = os.path.join(A, "tactical_infantry_framework", "lua", "tif", "gta", "playermodel")
lua.execute(open(os.path.join(pm, "sh_skeleton.lua"), encoding="utf-8").read())
lua.execute(open(os.path.join(pm, "sh_map.lua"), encoding="utf-8").read())
lua.execute(open(os.path.join(A, "tactical_infantry_framework", "lua", "tif", "config", "sh_modular.lua"), encoding="utf-8").read())

# rest world matrices of the model from the skeleton GTG reads (entity space)
run = lua.eval(r"""function(model, side, roll_deg, uroll_deg)
  local sk = TIFG.PMS.Skeleton(model)
  local W = {}
  for i = 0, sk.n - 1 do
    local R, t = sk.R[i], sk.t[i]
    W[i] = { R = { R[1], R[2], R[3], R[4], R[5], R[6], R[7], R[8], R[9] }, t = { t[1], t[2], t[3] } }
  end
  local function ix(n) return sk.index["valvebiped.bip01_" .. side .. "_" .. n] end
  local f, h, w, s, u = ix("forearm"), ix("hand"), ix("wrist"), ix("shoulder"), ix("upperarm")
  -- roll the hand about the forearm axis (forearm frame) and the upper arm about its own axis
  local function mul(a, b)
    return { a[1]*b[1]+a[2]*b[4]+a[3]*b[7], a[1]*b[2]+a[2]*b[5]+a[3]*b[8], a[1]*b[3]+a[2]*b[6]+a[3]*b[9],
      a[4]*b[1]+a[5]*b[4]+a[6]*b[7], a[4]*b[2]+a[5]*b[5]+a[6]*b[8], a[4]*b[3]+a[5]*b[6]+a[6]*b[9],
      a[7]*b[1]+a[8]*b[4]+a[9]*b[7], a[7]*b[2]+a[8]*b[5]+a[9]*b[8], a[7]*b[3]+a[8]*b[6]+a[9]*b[9] }
  end
  local function tr(a) return { a[1], a[4], a[7], a[2], a[5], a[8], a[3], a[6], a[9] } end
  local function rot(ax, ang)
    local c, s_, k = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
    local x, y, z = ax[1], ax[2], ax[3]
    return { c+x*x*k, x*y*k-z*s_, x*z*k+y*s_, y*x*k+z*s_, c+y*y*k, y*z*k-x*s_, z*x*k-y*s_, z*y*k+x*s_, c+z*z*k }
  end
  local function axis_of(a, b)
    local d = { W[b].t[1]-W[a].t[1], W[b].t[2]-W[a].t[2], W[b].t[3]-W[a].t[3] }
    local R = tr(W[a].R)
    local v = { R[1]*d[1]+R[2]*d[2]+R[3]*d[3], R[4]*d[1]+R[5]*d[2]+R[6]*d[3], R[7]*d[1]+R[8]*d[2]+R[9]*d[3] }
    local l = math.sqrt(v[1]^2+v[2]^2+v[3]^2)
    return { v[1]/l, v[2]/l, v[3]/l }
  end
  local fa = axis_of(f, h)
  -- hand: W_h = W_f * rot(fa, roll) * (W_f^T W_h)   (roll in the forearm frame)
  local Lh = mul(tr(W[f].R), W[h].R)
  W[h] = { R = mul(W[f].R, mul(rot(fa, math.rad(roll_deg)), Lh)), t = W[h].t }
  local ua = axis_of(u, f)
  local Ru = W[u].R
  W[u] = { R = mul(Ru, rot(ua, math.rad(uroll_deg))), t = W[u].t }
  local before = { w = W[w] and { t = W[w].t }, s = W[s] and { t = W[s].t } }
  local set = {}
  local ent = { GetModel = function() return model end }
  function ent:GetBoneMatrix(i)
    local m = W[i]
    if not m then return nil end
    return Matrix({ { m.R[1], m.R[2], m.R[3], m.t[1] }, { m.R[4], m.R[5], m.R[6], m.t[2] }, { m.R[7], m.R[8], m.R[9], m.t[3] }, { 0, 0, 0, 1 } })
  end
  function ent:SetBoneMatrix(i, m)
    local t = m:ToTable()
    set[i] = { R = { t[1][1], t[1][2], t[1][3], t[2][1], t[2][2], t[2][3], t[3][1], t[3][2], t[3][3] }, t = { t[1][4], t[2][4], t[3][4] } }
  end
  TIF.Modular.ArmTwist(ent)
  local function twist_of(Rn, Rold, ax)
    local d = mul(tr(Rold), Rn)  -- in the old frame
    local wq = math.sqrt(math.max(0, 1 + d[1] + d[5] + d[9])) / 2
    local vx, vy, vz = (d[8]-d[6])/(4*wq), (d[3]-d[7])/(4*wq), (d[4]-d[2])/(4*wq)
    return math.deg(2 * math.atan2(vx*ax[1]+vy*ax[2]+vz*ax[3], wq))
  end
  local out = {}
  out.forearm = set[f] and twist_of(set[f].R, W[f].R, fa) or "unset"
  if w and set[w] then
    out.wrist = twist_of(set[w].R, W[w].R, fa)
    out.wrist_moved = math.sqrt((set[w].t[1]-before.w.t[1])^2 + (set[w].t[2]-before.w.t[2])^2 + (set[w].t[3]-before.w.t[3])^2)
  end
  if s and set[s] then
    out.shoulder = twist_of(set[s].R, W[s].R, ua)
    out.shoulder_moved = math.sqrt((set[s].t[1]-before.s.t[1])^2 + (set[s].t[2]-before.s.t[2])^2 + (set[s].t[3]-before.s.t[3])^2)
  end
  return out
end""")
for side in ("l", "r"):
    for roll, uroll in ((90, 0), (-130, 0), (0, 40)):
        o = run(MODEL, side, roll, uroll)
        print("%s hand roll %+4d upper roll %+3d -> forearm %s  wrist %s (moved %s)  shoulder %s (moved %s)" % (
            side, roll, uroll, *[("%+.1f" % o[k]) if isinstance(o[k], float) else o[k] for k in ("forearm", "wrist", "wrist_moved", "shoulder", "shoulder_moved")]))
