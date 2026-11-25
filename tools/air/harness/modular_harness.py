"""Offline check of TIF's modular faction picker (tif/config/sh_modular.lua) with the TIF CoD Factions definitions:
5000 Al Qatala and USMC soldiers, every pick checked against the user's pairing rules, coverage of all pairs.
usage: python -I modular_harness.py"""
import re
import sys

from lupa import LuaRuntime

A = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
SERVER, CLIENT = true, false
function istable(t) return type(t) == "table" end
function isstring(s) return type(s) == "string" end
function isnumber(s) return type(s) == "number" end
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
util = { PrecacheModel = function() end }
function AddCSLuaFile() end
function MsgN(...) print(...) end
file = { Exists = function() return true end }
math.randomseed(7)
TIF = { Factions = {} }
function TIF.RegisterFaction(id, def) TIF.Factions[id] = def end
""")
lua.execute(open(A + r"\tactical_infantry_framework\lua\tif\config\sh_modular.lua", encoding="utf-8").read())
lua.execute("TIF.RegisterContent = function(name, f) f() end")
lua.execute(open(A + r"\tif_cod_factions\lua\autorun\tif_cod_factions.lua", encoding="utf-8").read())
pick = lua.eval("function(id, arch) return TIF.Modular.Pick(TIF.Factions[id], arch) end")
fails = 0


def num(m):
    return int(re.search(r"_(\d+)\.mdl", m).group(1))


ok_pairs, seen = set(), set()
for h in (2, 4, 6, 9):
    for b in (1, 2, 3, 4, 6, 7, 8, 9):
        ok_pairs.add((h, b))
for h in (1, 3, 7, 8):
    for b in (1, 3, 7, 8):
        ok_pairs.add((h, b))
ok_pairs.add((5, 5))
for _ in range(5000):
    head, parts = pick("al_qatala_desert")
    bodies = [p for p in parts.split(";") if p]
    if len(bodies) != 1 or "head" not in head:
        fails += 1
        continue
    pair = (num(head), num(bodies[0].split("#")[0]))
    seen.add(pair)
    if pair not in ok_pairs:
        fails += 1
        print("FAIL bad pair head %d body %d" % pair)
print(("ok  " if not fails else "FAIL") + " Al Qatala: 5000 soldiers, every head/body pair allowed; %d of %d allowed pairs seen"
      % (len(seen), len(ok_pairs)))
if seen != ok_pairs:
    fails += 1
us = set()
for _ in range(5000):
    head, parts = pick("usmc_basic")
    ps = [p.split("#")[0] for p in parts.split(";") if p]
    body = [p for p in ps if "body" in p]
    helm = [p for p in ps if "helmet" in p]
    if len(body) != 1 or len(helm) != 1 or "sc_m_" not in head:
        fails += 1
    us.add((head, body[0] if body else None, helm[0] if helm else None))
print(("ok  " if len(us) == 100 else "FAIL") + " USMC: always body + head + helmet; %d of 100 combinations seen" % len(us))
fails += len(us) != 100
# --- 2026-11-14 factions ---------------------------------------------------------------------------------------
import collections


def parts_of(id_, arch=None):
    head, parts = pick(id_, arch)
    ps = [p for p in parts.split(";") if p]
    return head, [p.split("#")[0] for p in ps], [p.split("#")[1] for p in ps]


def chk(cond, msg):
    global fails
    print(("ok  " if cond else "FAIL") + " " + msg)
    fails += not cond


# Russian Ground Forces: hooded bodies never with a helmet, others always; no gas masks; bodies roughly even
bodyc, bad, helm_seen, combos = collections.Counter(), 0, set(), set()
for _ in range(6000):
    head, ps, _s = parts_of("rus_ground_forces")
    body = [p for p in ps if "_body_" in p][0]
    helm = [p for p in ps if "helmet" in p]
    hooded = body.endswith("ar_3_3.mdl") or body.endswith("ar_3_4.mdl")
    if (hooded and helm) or (not hooded and len(helm) != 1) or "gasmask" in head + "".join(ps):
        bad += 1
    bodyc[body] += 1
    helm_seen.update(helm)
    combos.add((head, body))
chk(bad == 0, "RGF: hooded bodies never helmeted, the rest always; no gas masks (6000)")
chk(len(bodyc) == 13 and min(bodyc.values()) > 300, "RGF: all 13 bodies used, evenly (min %d, max %d)" % (min(bodyc.values()), max(bodyc.values())))
chk(len(helm_seen) == 7 and len(combos) == 65, "RGF: all 7 helmets, all 65 head x body pairs seen")
# Spetsnaz by archetype
want = {"assault": ("head_cqc", {"body_cqc"}), "support": ("head_lmg", {"body_lmg"}), "marksman": ("head_dmr", {"body_dmr"}),
        "rifleman": ("head_ar", {"body_ar.", "body_ar_2_1", "body_ar_3_1"}), "leader": ("head_ar", {"body_ar.", "body_ar_2_1", "body_ar_3_1"}),
        "rpg": ("head_ar", {"body_ar.", "body_ar_2_1", "body_ar_3_1"})}
for arch, (hw, bw) in want.items():
    bad, helms, seen_b = 0, 0, set()
    for _ in range(800):
        head, ps, _s = parts_of("rus_spetsnaz", arch)
        body = [p for p in ps if "_body_" in p]
        helm = [p for p in ps if "helmet" in p]
        if hw not in head or len(body) != 1 or not any(b in body[0] for b in bw):
            bad += 1
        if helm and arch != "assault":
            bad += 1
        helms += bool(helm)
        seen_b.update(body)
    extra = " (NVG helmet on %d%%)" % (helms * 100 // 800) if arch == "assault" else ""
    chk(bad == 0 and len(seen_b) == len(bw), "Spetsnaz %-8s -> %s + %s%s" % (arch, hw, "/".join(sorted(bw)), extra))
# Smugglers: no skins, beanie only on Orlovszki
bad, heads = 0, set()
for _ in range(3000):
    head, ps, seeds = parts_of("rus_smugglers")
    hats = [p for p in ps if "beanie" in p]
    if ("orlovszki" in head) != bool(hats) or any(s != "0" for s in seeds) or "gasmask" in head:
        bad += 1
    heads.add(head)
chk(bad == 0 and len(heads) == 5, "Smugglers: beanie exactly on Orlovszki, every part skin 0, all 5 heads")
# Mex SF: head N with body N, skin 0
bad, pairs = 0, set()
for _ in range(2000):
    head, ps, seeds = parts_of("mex_sf_tier1")
    n = re.search(r"head_(\d)_1", head).group(1)
    if len(ps) != 1 or ("body_%s_1" % n) not in ps[0] or any(s != "0" for s in seeds):
        bad += 1
    pairs.add(n)
chk(bad == 0 and len(pairs) == 4, "Mex SF: head N always with body N, skin 0, all 4 pairs")
chk(lua.eval("TIF.Factions.rus_spetsnaz.modular.skins") is None and lua.eval("TIF.Factions.mex_sf_tier1.modular.skins") is False,
    "skins flag: off only where asked")
print("ok   Al Qatala models list (TIF's faction models) = %d heads" % len(lua.eval("TIF.Factions.al_qatala_desert.models")))
print("failed:", fails)
sys.exit(1 if fails else 0)
