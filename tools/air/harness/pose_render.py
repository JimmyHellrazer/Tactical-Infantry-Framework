"""Offline look at a retargeted codport part in a host pose: one frame of a TIF mw_male clip -> GTG's own map + solve
(tif/gta/playermodel, run under lupa) -> TIF.Modular.ArmTwist (sh_modular.lua) -> linear-blend skinning of the part's
mesh -> flat-shaded renders (front / left / right / top). Shows what the retarget does to arms without the game.
usage: python -I pose_render.py <part id (work dir)> <part model (models/...mdl)> <clip.smd> <frame> <out.png> [twist 0/1]"""
import math
import os
import struct
import sys

import numpy as np
from lupa import LuaRuntime
from PIL import Image, ImageDraw

sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep  # noqa: E402
import cod_to_breen as c2b  # noqa: E402

A = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
HOST = "models/tif_mw/mw_male.mdl"
cid, model, clip, frame, out = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
twist_on = len(sys.argv) < 7 or sys.argv[6] != "0"
shares = [float(x) for x in sys.argv[7].split(",")] if len(sys.argv) > 7 else None  # forearm,wrist,shoulder
rest_pose = frame < 0  # (-1: the part's own rest pose, no solve)


def game_path(p):
    for r in [os.path.join(A, d) for d in os.listdir(A)]:
        q = os.path.join(r, p.replace("/", os.sep))
        if os.path.isfile(q):
            return q
    return None


def mdl_bones(path):
    d = open(path, "rb").read()
    n, base = struct.unpack_from("<ii", d, 156)
    out = []
    for i in range(n):
        o = base + i * 216
        name_at, parent = struct.unpack_from("<ii", d, o)
        name = d[o + name_at:d.index(b"\0", o + name_at)].decode("latin1")
        p = struct.unpack_from("<12f", d, o + 96)
        P = np.array(p).reshape(3, 4)
        R = P[:, :3].T
        out.append((name, parent, R, -R @ P[:, 3]))
    return out


# ---- host pose: world matrices of the clip frame (clip SMD space = host model space)
smd = prep.read_smd(clip)
prep.fill_frames(smd)
bones = smd.frames[min(frame, len(smd.frames) - 1)][1]
wp = c2b.world_pose(smd.nodes, {i: prep.to_rt(v) for i, v in bones.items()})
host_world = {smd.nodes[i][0].lower(): (np.array(R), np.array(t)) for i, (R, t) in wp.items()}

# ---- follower: rest from its MDL; engine-side matrices = host's for same names, else rest-relative to parent
fb = mdl_bones(game_path(model))
E = {}
for i, (n, p, R, t) in enumerate(fb):
    h = host_world.get(n.lower())
    if h is not None:
        E[i] = h
    elif p >= 0:
        Rp0, tp0 = fb[p][2], fb[p][3]
        Rl, tl = Rp0.T @ R, Rp0.T @ (t - tp0)
        Rp, tp = E[p]
        E[i] = (Rp @ Rl, Rp @ tl + tp)
    else:
        E[i] = (R, t)

lua = LuaRuntime(unpack_returned_tuples=True)


class Fh:
    def __init__(self, data): self.d, self.p = data, 0
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
    q = game_path(path)
    if not q:
        return None
    f = Fh(open(q, "rb").read()); t = lua.table()
    for k in ("Seek", "Read", "ReadLong", "ReadFloat", "Size", "Close"):
        t[k] = getattr(f, k)
    return t


lua.globals().py_open = open_game
lua.execute(r"""
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH, HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG = 0,1,2,3,4,5,6,7
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end }
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
math.Clamp = function(v, a, b) return v < a and a or (v > b and b or v) end
math_sqrt = math.sqrt
FCVAR_ARCHIVE, FCVAR_REPLICATED = 0, 0
function CreateConVar() return { GetFloat = function() return 1 end } end
function CurTime() return 0 end
function istable(t) return type(t) == "table" end
function isstring(s) return type(s) == "string" end
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
file = { Open = function(p) return py_open(p) end, Read = function() return nil end }
local Vm = {} Vm.__index = Vm
Vm.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
Vm.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vm) end
function Angle(...) return { ... } end
local Mm = {} Mm.__index = Mm
function Matrix(t) return setmetatable({ t = t or { {1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1} } }, Mm) end
function Mm:ToTable() return self.t end
function Mm:Unpack() local t = self.t return t[1][1], t[1][2], t[1][3], t[1][4], t[2][1], t[2][2], t[2][3], t[2][4], t[3][1], t[3][2], t[3][3], t[3][4] end
function Mm:SetUnpacked(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
  self.t = { { a1, a2, a3, a4 }, { a5, a6, a7, a8 }, { a9, a10, a11, a12 }, { 0, 0, 0, 1 } } end
local Ent = {}
Ent.__index = Ent
function Ent:GetBoneMatrix(i) local m = self.mats[i] if not m then return nil end return Matrix(m.t) end
function Ent:SetBoneMatrix(i, m) self.mats[i] = Matrix(m.t) end
function Ent:GetModel() return self.model end
function FindMetaTable(n) if n == "Entity" then return Ent end return Mm end
function NewEnt(model) return setmetatable({ model = model, mats = {} }, Ent) end
hook = { Add = function() end }
function CreateClientConVar() return { GetBool = function() return true end, GetFloat = function() return 1 end } end
concommand = { Add = function() end }
cvars = { AddChangeCallback = function() end }
TIFG = { PMS = {} }
function TIFG.QuatFromRows(m00, m01, m02, m10, m11, m12, m20, m21, m22)
  local tr = m00 + m11 + m22
  if tr > 0 then local s = math.sqrt(tr + 1) * 2 return (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s end
  if m00 > m11 and m00 > m22 then local s = math.sqrt(1 + m00 - m11 - m22) * 2 return 0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s end
  if m11 > m22 then local s = math.sqrt(1 + m11 - m00 - m22) * 2 return (m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s end
  local s = math.sqrt(1 + m22 - m00 - m11) * 2 return (m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s
end
SERVER, CLIENT = false, true
TIF = { GTG = {} }
""")
pm = os.path.join(A, "tactical_infantry_framework", "lua", "tif", "gta", "playermodel")
for f in ("sh_skeleton.lua", "sh_map.lua", "sh_pose.lua", "cl_bones.lua"):
    src = open(os.path.join(pm, f), encoding="utf-8").read()
    lua.execute(src)
lua.execute(open(os.path.join(A, "tactical_infantry_framework", "lua", "tif", "config", "sh_modular.lua"), encoding="utf-8").read())
lua.execute('TIF.GTG.MapFor = function(a, b) return TIFG.PMS.MapFor(a, b) end')
if os.environ.get("FOREARM_PALM") == "1":
    lua.execute("TIF.Modular.ForearmPalm = true")  # (old behaviour, for comparison)
lua.eval('function(m) TIF.Modular.Retarget[string.lower(m)] = true end')(model)
if shares:
    lua.eval('function(a, b, c) TIF.Modular.TwistShares = { forearm = a, wrist = b, shoulder = c } end')(*shares)

ent = lua.eval("NewEnt")(model)
mk = lua.eval("function(t) return Matrix(t) end")
lua.execute("_NOW, _FRAME = 0, 0; function RealTime() return _NOW end; function FrameNumber() return _FRAME end")


def load_E(E_, shift):
    for i, (R, t) in E_.items():
        rows = lua.table_from([lua.table_from([R[r, 0], R[r, 1], R[r, 2], t[r] + shift[r]]) for r in range(3)] + [lua.table_from([0, 0, 0, 1])])
        ent.mats[i] = mk(rows)


solve = lua.eval(r"""function(ent, host, model, twist, sway)
  local map = TIFG.PMS.MapFor(host, model)
  if not map then return "no map" end
  TIFG.PMS.Solve(ent, map, nil, nil)
  if twist then TIF.Modular.ArmTwist(ent) end
  local dev = ""
  if sway then
    local chains = TIF.Modular.SwayChains(model) or {}
    local before = {}
    for k, c in ipairs(chains) do before[k] = ent:GetBoneMatrix(c.b):ToTable() end
    TIF.Modular.Sway(ent)
    for k, c in ipairs(chains) do
      local a, b = before[k], ent:GetBoneMatrix(c.b):ToTable()
      local tr = 0
      for r = 1, 3 do for q = 1, 3 do tr = tr + a[q][r] * b[q][r] end end
      local ang = math.deg(math.acos(math.max(-1, math.min(1, (tr - 1) / 2))))
      if ang ~= ang then ang = -999 end
      dev = dev .. string.format("%5.1f ", ang)
    end
  end
  return "ok " .. map.n .. (sway and (" sway dev " .. dev) or "")
end""")
sway_env = os.environ.get("SWAY")  # "frames,speed": walk the body along +x at speed (u/s), stop at half, loop the clip
if sway_env:
    nfr, speed = int(sway_env.split(",")[0]), float(sway_env.split(",")[1])
    print("chains:", lua.eval("function(m) local o = {} for _, c in ipairs(TIF.Modular.SwayChains(m) or {}) do o[#o+1] = TIF.Modular.__n(m, c.b) end return table.concat(o, ' ') end")(model) if False else "")
    clip_smd = prep.read_smd(clip); prep.fill_frames(clip_smd)
    x = 0.0
    for f in range(nfr):
        fb_ = clip_smd.frames[f % len(clip_smd.frames)][1]
        wp_ = c2b.world_pose(clip_smd.nodes, {i: prep.to_rt(v) for i, v in fb_.items()})
        hw = {clip_smd.nodes[i][0].lower(): (np.array(R), np.array(t)) for i, (R, t) in wp_.items()}
        E2 = {}
        for i, (n, p, R, t) in enumerate(fb):
            hh = hw.get(n.lower())
            if hh is not None: E2[i] = hh
            elif p >= 0:
                Rp0, tp0 = fb[p][2], fb[p][3]; Rl, tl = Rp0.T @ R, Rp0.T @ (t - tp0); Rp, tp = E2[p]; E2[i] = (Rp @ Rl, Rp @ tl + tp)
            else: E2[i] = (R, t)
        if f < nfr // 2: x += speed / 30.0
        load_E(E2, np.array([x, 0, 0]))
        lua.execute("_NOW = %f; _FRAME = %d" % (f / 30.0, f))
        r = solve(ent, HOST, model, twist_on, True)
        if f % 6 == 0 or f == nfr // 2 + 3: print("  f%3d x %6.1f %s" % (f, x, r))
    host_world = {k: (R, t + np.array([x, 0, 0])) for k, (R, t) in host_world.items()}
    res = "sway run done"
else:
    load_E(E, np.zeros(3))
    res = solve(ent, HOST, model, twist_on, False)
print("solve:", res)
W = {}
if rest_pose:
    for i, (n, p, R, t) in enumerate(fb):
        ent.mats[i] = mk(lua.table_from([lua.table_from([R[r, 0], R[r, 1], R[r, 2], t[r]]) for r in range(3)] + [lua.table_from([0, 0, 0, 1])]))
for i in range(len(fb)):
    m = ent.mats[i]
    if m is None:
        continue
    t = m.t
    W[i] = (np.array([[t[r + 1][c + 1] for c in range(3)] for r in range(3)]), np.array([t[r + 1][4] for r in range(3)]))

name_ix_pre = {n.lower(): i for i, (n, _, _, _) in enumerate(fb)}
_hb = mdl_bones(game_path(HOST)); _hi = {n.lower(): i for i, (n, _, _, _) in enumerate(_hb)}
host_rest_local = {s: _hb[_hi["valvebiped.bip01_%s_upperarm" % s]][2].T @ _hb[_hi["valvebiped.bip01_%s_forearm" % s]][2] for s in ("l", "r")}
# ---- JOINT_CHECK: solved joints vs the host's (same names)
for nm in ("pelvis", "spine4", "l_clavicle", "l_upperarm", "l_forearm", "l_hand", "r_clavicle", "r_upperarm", "r_forearm", "r_hand", "head1"):
    full = "valvebiped.bip01_" + nm
    i = next((k for k, (n, _, _, _) in enumerate(fb) if n.lower() == full), None)
    if i is not None and i in W and full in host_world:
        print("  %-12s solved %s  host %s  off %.2f" % (nm, np.round(W[i][1], 1), np.round(host_world[full][1], 1), float(np.linalg.norm(W[i][1] - host_world[full][1]))))

# ---- HINGE_CHECK: elbow delta rotation (forearm in upper arm, vs rest) as axis-angle in the upper arm's frame
def _aa(R):
    a = math.degrees(math.acos(max(-1, min(1, (np.trace(R) - 1) / 2))))
    ax = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]])
    return round(a, 1), np.round(ax / (np.linalg.norm(ax) + 1e-9), 2)
for s in ("l", "r"):
    u = name_ix_pre["valvebiped.bip01_%s_upperarm" % s]; f = name_ix_pre["valvebiped.bip01_%s_forearm" % s]
    L0 = fb[u][2].T @ fb[f][2]; L1 = W[u][0].T @ W[f][0]
    print("  HINGE %s ours" % s, _aa(L1 @ L0.T))
    hu, hf = host_world["valvebiped.bip01_%s_upperarm" % s], host_world["valvebiped.bip01_%s_forearm" % s]
    print("  HINGE %s host" % s, _aa((hu[0].T @ hf[0]) @ np.linalg.inv(host_rest_local[s])))

# ---- AXIS_CHECK: does each arm bone point at its child joint (deg off)?
for s in ("l", "r"):
    for a_, b_ in (("clavicle", "upperarm"), ("upperarm", "forearm"), ("forearm", "hand"), ("thigh", "calf"), ("calf", "foot"), ("foot", "toe0")):
        if "valvebiped.bip01_%s_%s" % (s, b_) not in name_ix_pre: continue
        ia, ib = name_ix_pre["valvebiped.bip01_%s_%s" % (s, a_)], name_ix_pre["valvebiped.bip01_%s_%s" % (s, b_)]
        rl = fb[ia][2].T @ (fb[ib][3] - fb[ia][3]); rl /= np.linalg.norm(rl)
        want = W[ib][1] - W[ia][1]; want /= np.linalg.norm(want)
        got = W[ia][0] @ rl
        print("  AXIS %s %-8s off %.1f deg" % (s, a_, math.degrees(math.acos(max(-1, min(1, float(got @ want)))))))

# ---- EYE_CHECK: head-forward (the model's rest +x in the head frame) in the solved pose
if "valvebiped.bip01_head1" in name_ix_pre:
    ih = name_ix_pre["valvebiped.bip01_head1"]
    fl = fb[ih][2].T @ np.array([1.0, 0, 0])
    print("  EYE fwd", np.round(W[ih][0] @ fl, 2))

# ---- skin the part's meshes (every SMD its QC builds, LOD0)
work = os.path.join(r"K:\jimmyproject\work", cid)
import re as _re  # noqa: E402
qc = [q for q in os.listdir(os.path.join(work, "qc")) if q.endswith(".qc") and not q.endswith("_lods.qc")][0]
text = open(os.path.join(work, "qc", qc), encoding="latin1").read()
meshes = [os.path.normpath(os.path.join(work, "qc", m)) for m in _re.findall(r'^\s*(?:studio|\$model\s+"[^"]+")\s+"([^"]+\.smd)"', text, _re.M)
          if "placeholder" not in m.lower()]
name_ix = {n: i for i, (n, _, _, _) in enumerate(fb)}
tris, cols = [], []
for path in meshes:
    sm = open(path, encoding="latin1").read()
    nodes = {}
    for line in sm.split("nodes\n")[1].split("end")[0].strip().splitlines():
        p = line.split('"')
        nodes[int(p[0])] = p[1]
    lines = sm.split("\ntriangles\n")[1].splitlines()
    k = 0
    while k + 3 < len(lines):
        if lines[k].strip() in ("end", ""):
            k += 1
            continue
        mat = lines[k].strip().lower()
        tri = []
        for l in lines[k + 1:k + 4]:
            p = l.split()
            v = np.array([float(x) for x in p[1:4]])
            links = [(int(p[0]), 1.0)]
            if len(p) > 9:
                nl = int(p[9])
                links = [(int(p[10 + 2 * j]), float(p[11 + 2 * j])) for j in range(nl)]
            acc = np.zeros(3)
            tw = 0
            for b, w in links:
                bi = name_ix.get(nodes.get(b, ""))
                if bi is None or bi not in W:
                    continue
                R0, t0 = fb[bi][2], fb[bi][3]
                R1, t1 = W[bi]
                acc += w * (R1 @ (R0.T @ (v - t0)) + t1)
                tw += w
            tri.append(acc / tw if tw > 0 else v)
        tris.append(tri)
        cols.append((200, 120, 100) if ("skin" in mat or "arm" in mat) else (150, 150, 140))
        k += 4
P = np.array(tris)
col = np.array(cols, float)
pel = W[name_ix["ValveBiped.Bip01_Pelvis"]][1]
P = P - pel
keep = P[..., 2].mean(1) > 8  # torso and arms only
P, col = P[keep], col[keep]
S = 520


def view(R, title):
    Q = P @ R.T
    n = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    sh = 0.35 + 0.65 * np.abs(n[:, 2])
    # fixed framing (same scale for every render): 64 units wide, pelvis-centred
    lo, hi = np.array([-32.0, 5.0]), np.array([32.0, 69.0])
    k = (S - 20) / 64.0
    img = Image.new("RGB", (S, S), (30, 30, 34))
    d = ImageDraw.Draw(img)
    for t in np.argsort(Q[..., 2].mean(1)):
        d.polygon([(10 + (q[0] - lo[0]) * k, S - 10 - (q[1] - lo[1]) * k) for q in Q[t]], fill=tuple(int(c) for c in col[t] * sh[t]))
    d.text((6, 4), title, fill=(255, 255, 0))
    return img


def rot(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    Ry = np.array([[math.cos(y), -math.sin(y), 0], [math.sin(y), math.cos(y), 0], [0, 0, 1]])
    Rp = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    base = np.array([[0, -1, 0], [0, 0, 1], [-1, 0, 0]], float)  # look from +x (front): screen x = -y, up = z
    return Rp @ base @ Ry


tag = ("palm " if os.environ.get("FOREARM_PALM") == "1" else "") + ("rest pose" if rest_pose else ("twist %s" % (",".join("%g" % s for s in shares) if shares else "on") if twist_on else "twist off"))
views = [view(rot(0, 0), tag + " a"), view(rot(90, 0), tag + " b"), view(rot(-90, 0), tag + " c"), view(rot(30, -20), tag + " d")]
sheet = Image.new("RGB", (S * 4, S), (20, 20, 20))
for i, v in enumerate(views):
    sheet.paste(v, (i * S, 0))
sheet.save(out)
print(out)
