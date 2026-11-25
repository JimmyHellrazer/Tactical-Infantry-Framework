"""Offline check: GTG's skeleton reader + retarget map builder (TIF's copy, tif/gta/playermodel/) on the real MDL
files: TIF's MW19 host (mw_male) -> the codport heads of tif_cod_factions (CODDIDDY-renamed CoD rig). Needs the
Spine requirement dropped (tif/config/sh_modular.lua does that at load); the test applies the same edit.
usage: python -I retarget_harness.py"""
import glob
import os
import struct
import sys

from lupa import LuaRuntime

A = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
ROOTS = [os.path.join(A, d) for d in os.listdir(A)]
lua = LuaRuntime(unpack_returned_tuples=True)


class F:
    def __init__(self, data):
        self.d, self.p = data, 0

    def Seek(self, _s, p):
        self.p = int(p)

    def Read(self, _s, n):
        b = self.d[self.p:self.p + int(n)]
        self.p += int(n)
        return b.decode("latin1")

    def ReadLong(self, _s):
        v = struct.unpack_from("<i", self.d, self.p)[0]
        self.p += 4
        return v

    def ReadFloat(self, _s):
        v = struct.unpack_from("<f", self.d, self.p)[0]
        self.p += 4
        return v

    def Size(self, _s):
        return len(self.d)

    def Close(self, _s):
        pass


def open_game(path, *_):
    for r in ROOTS:
        p = os.path.join(r, path.replace("/", os.sep))
        if os.path.isfile(p):
            f = F(open(p, "rb").read())
            t = lua.table()
            for k in ("Seek", "Read", "ReadLong", "ReadFloat", "Size", "Close"):
                t[k] = getattr(f, k)
            return t
    return None


lua.globals().py_open = open_game
lua.execute(r"""
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH, HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG = 0,1,2,3,4,5,6,7
bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end }
math.Clamp = function(v, a, b) return v < a and a or (v > b and b or v) end
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
FCVAR_ARCHIVE, FCVAR_REPLICATED = 0, 0
function CreateConVar() return { GetFloat = function() return 1 end } end
function CurTime() return 0 end
function Angle(...) return { ... } end
function Vector(...) return { ... } end
file = { Open = function(p) return py_open(p) end }
TIFG = { PMS = {} }
""")
pm = os.path.join(A, "tactical_infantry_framework", "lua", "tif", "gta", "playermodel")
lua.execute(open(os.path.join(pm, "sh_skeleton.lua"), encoding="utf-8").read())
lua.execute(open(os.path.join(pm, "sh_map.lua"), encoding="utf-8").read())
fails = 0
host = "models/tif_mw/mw_male.mdl"
head = "models/tif_cod_factions/al_qatala_desert_head_01.mdl"
before = lua.eval('function(m) return TIFG.PMS.ParseSkeleton(m) ~= nil end')(head)
print(("ok   " if not before else "note ") + "before the fix the head skeleton reads: %s (GTG wants Bip01_Spine)" % before)
lua.execute("""for i = #TIFG.PMS.Required, 1, -1 do
  if TIFG.PMS.Required[i] == "valvebiped.bip01_spine" then table.remove(TIFG.PMS.Required, i) end end""")
check = lua.eval(r"""function(leader, follower)
  local lsk, fsk = TIFG.PMS.Skeleton(leader), TIFG.PMS.Skeleton(follower)
  if not lsk then return "host skeleton unreadable" end
  if not fsk then return "part skeleton unreadable" end
  -- (sh_modular.lua: retargeted models drive every bone; twist helpers QUAT, the rest BIND)
  for i = 0, fsk.n - 1 do
    fsk.weighted[i] = true
    if fsk.proc[i] ~= TIFG.PMS.PROC_QUAT or not fsk.rule[i] then fsk.proc[i] = 99 end
  end
  local map = TIFG.PMS.MapFor(leader, follower)
  if not map then return "no map" end
  local merged = 0
  local need = { "valvebiped.bip01_pelvis", "valvebiped.bip01_spine4", "valvebiped.bip01_head1",
    "valvebiped.bip01_l_hand", "valvebiped.bip01_r_hand", "valvebiped.bip01_l_foot", "valvebiped.bip01_r_foot" }
  local have = {}
  for k = 1, map.n do
    if map.K[k] == TIFG.PMS.MERGE then merged = merged + 1 have[fsk.name[map.B[k]]] = true end
  end
  for _, n in ipairs(need) do if not have[n] then return "not merged: " .. n end end
  local inmap = {}
  for k = 1, map.n do
    inmap[map.B[k]] = true
    if map.K[k] ~= TIFG.PMS.MERGE and map.K[k] ~= TIFG.PMS.BIND and map.K[k] ~= TIFG.PMS.QUAT then return "not bound: " .. fsk.name[map.B[k]] end
  end
  for i = 0, fsk.n - 1 do
    if not inmap[i] and fsk.parent[i] >= 0 then return "not driven: " .. fsk.name[i] end
  end
  return string.format("ok: all %d bones but the root driven, %d merged from the host, oddness %.2f%s", map.n, merged, map.oddness,
    map.own_all and " (own proportions)" or "")
end""")
heads = sorted(glob.glob(os.path.join(A, "tif_cod_factions", "models", "tif_cod_factions", "*head*.mdl")))
heads += sorted(glob.glob(os.path.join(A, "tif_cod_factions", "models", "tif_cod_factions", "sc_m_*.mdl")))
heads += sorted(glob.glob(os.path.join(A, "tif_cod_factions", "models", "tif_cod_factions", "*body*.mdl")))
heads += sorted(glob.glob(os.path.join(A, "tif_cod_factions", "models", "tif_cod_factions", "mex_sf", "*.mdl")))  # (2026-11-14)
heads += sorted(glob.glob(os.path.join(A, "tif_cod_factions", "models", "tif_cod_factions", "*helmet*.mdl")) + glob.glob(os.path.join(A, "tif_cod_factions", "models", "tif_cod_factions", "*beanie*.mdl")))
for p in heads:
    m = "models/" + os.path.relpath(p, os.path.join(A, "tif_cod_factions", "models")).replace(os.sep, "/")
    r = check(host, m)
    ok = r.startswith("ok")
    fails += not ok
    print(("ok   " if ok else "FAIL ") + "%-44s %s" % (os.path.basename(p), r))
# corpses: a part's map on the head's own ragdoll (TIF.Modular.CorpseMap, the real sh_modular.lua)
def read_game(path, *_):
    for r in ROOTS:
        p = os.path.join(r, path.replace("/", os.sep))
        if os.path.isfile(p):
            return open(p, "rb").read().decode("latin1")
    return None
lua.globals().py_read = read_game
lua.execute("""file.Read = function(p) return py_read(p) end
function Matrix(t) return t end
function istable(t) return type(t) == "table" end
function isstring(s) return type(s) == "string" end
SERVER, CLIENT = false, false
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
TIF = { GTG = { MapFor = function(a, b) return TIFG.PMS.MapFor(a, b) end } }""")
lua.execute(open(os.path.join(A, "tactical_infantry_framework", "lua", "tif", "config", "sh_modular.lua"), encoding="utf-8").read())
corpse = lua.eval(r"""function(head, part)
  TIF.Modular.Retarget[string.lower(head)] = true
  TIF.Modular.Retarget[string.lower(part)] = true
  local map = TIF.Modular.CorpseMap(head, part)
  if not map then return "no corpse map" end
  local lsk = TIFG.PMS.Skeleton(head)
  local fsk = TIFG.PMS.Skeleton(part)
  local merged, quat = {}, 0
  for k = 1, map.n do
    if map.K[k] == TIFG.PMS.MERGE then merged[#merged + 1] = string.gsub(fsk.name[map.B[k]], "valvebiped.bip01_", "") end
    if map.K[k] == TIFG.PMS.QUAT then quat = quat + 1 end
  end
  table.sort(merged)
  return string.format("%d merged from the ragdoll (%s), %d twist helpers solved", #merged, table.concat(merged, " "), quat)
end""")
for head, part in (("al_qatala_desert_head_04", "al_qatala_desert_body_04"), ("sc_m_colvin", "usmc_body_basic_ar_1"), ("sc_m_colvin", "usmc_helmet_ar_1")):
    r = corpse("models/tif_cod_factions/%s.mdl" % head, "models/tif_cod_factions/%s.mdl" % part)
    ok = "merged" in r and not r.startswith("0 ")
    fails += not ok
    print(("ok   " if ok else "FAIL ") + "corpse %s on %s: %s" % (part, head, r))
print("failed:", fails)
sys.exit(1 if fails else 0)
