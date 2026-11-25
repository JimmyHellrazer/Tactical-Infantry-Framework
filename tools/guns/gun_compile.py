"""
TIF gun bake, offline step 3: compile a baked gun into addons/tif_guns.

Inputs (from gun_decimate.py and gun_textures.py): build/<id>_lod{0,1,2}_t.smd, build/<id>_atlas.tga, and the
export's data/tif_gunbake/<id>.json (tag bones). Output: models/tif_guns/<id>.mdl (bones tif_gun / tif_mag,
3 LODs, attachments muzzle and grip_l, a rough collision hull) and materials/tif_guns/<id>.vmt/.vtf.

Usage: gun_compile.py <id> [--lod1 6 --lod2 18]
"""
import argparse
import json
import math
import re
import os
import shutil
import subprocess
import sys

GAME = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod"
BIN = r"K:\SteamLibrary\steamapps\common\GarrysMod\bin"
STUDIOMDL = os.path.join(BIN, "studiomdl.exe")
VTEX = os.path.join(BIN, "vtex.exe")
DATA = os.path.join(GAME, "data", "tif_gunbake")
BUILD = r"K:\jimmyproject\tif_guns\build"
ADDON = os.path.join(GAME, "addons", "tactical_infantry_framework")  # (TIF 0.37.0: guns ship in the base)

VMT = '''"VertexLitGeneric"
{
	"$basetexture" "tif_guns/%s"
	"$surfaceprop" "metal"
	"$phong" "1"
	"$phongboost" "0.4"
	"$phongexponent" "18"
	"$phongalbedotint" "1"
	"$phongfresnelranges" "[0.4 0.7 1]"
}
'''


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    bad = [l for l in (r.stdout + r.stderr).splitlines() if "ERROR" in l.upper() and "0 error" not in l.lower()]
    if r.returncode != 0 or bad:
        print((r.stdout + r.stderr)[-3000:])
        sys.exit("failed: " + " ".join(cmd[:1]))
    return r.stdout


def tags(meta):
    """All tag bones from the gun and its parts: {name: [(pos, ang), ...]}."""
    out = {}
    for p in meta["parts"]:
        for name, t in (p.get("bones") or {}).items():
            out.setdefault(name, []).append((t["pos"], t["ang"]))
        for name, t in (p.get("tags") or {}).items():
            out.setdefault(name, []).append((t["pos"], t["ang"]))
    return out


def far(entries):
    return max(entries, key=lambda e: math.sqrt(sum(c * c for c in e[0])))


def ang_vectors(a):
    """GMod Angle (pitch, yaw, roll) -> forward, up vectors."""
    p, y, r = (math.radians(x) for x in a)
    sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    fwd = (cp * cy, cp * sy, -sp)
    up = (cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp)
    return fwd, up


# Where the palm sits on the gun: the model's origin is the MW world model's right-hand bone (the wrist), and TIF
# puts the gun's grip GRIP_IN (3.2) along the hand from the wrist (cl_body place_gun_vb).
GRIP_IN = 3.2


def texture(gid):
    src_dir = os.path.join(GAME, "materialsrc", "tif_guns")
    os.makedirs(src_dir, exist_ok=True)
    tga = os.path.join(src_dir, gid + ".tga")
    shutil.copy(os.path.join(BUILD, gid + "_atlas.tga"), tga)
    with open(os.path.join(src_dir, gid + ".txt"), "w") as f:
        f.write('"nocompress" "0"\n')
    run([VTEX, "-game", GAME, "-nopause", "-mkdir", tga])
    out_dir = os.path.join(ADDON, "materials", "tif_guns")
    os.makedirs(out_dir, exist_ok=True)
    shutil.move(os.path.join(GAME, "materials", "tif_guns", gid + ".vtf"), os.path.join(out_dir, gid + ".vtf"))
    with open(os.path.join(out_dir, gid + ".vmt"), "w") as f:
        f.write(VMT % gid)


# Guns whose MW world model isn't rooted at the right hand like the rest: their mesh, mag bone and tags moved so the
# grip lands where the rifles' does (TIF puts the model origin at the wrist). rpg7 (2026-11-20, user clip: the launcher
# floated ahead of the hands): MW22's RPG is rooted between its grips, ~6 in ahead of the trigger grip; the shift puts
# the trigger grip at (3.37, -0.29, -0.13) in the RPG aim's hand frame against the AKM's (3.28, -0.50, 0.66)
# (scratchpad shift_sim2.py: grip centroids, cl_body's placement reproduced on the baked aim poses).
MESH_SHIFT = {"rpg7": (5.78, 0.18, 0.20)}


def shifted_smd(src, dst, s):
    """Copy an SMD with every vertex and the tif_mag bone moved by s (tif_gun stays at the origin)."""
    out, sect = [], None
    for line in open(src, encoding="utf-8", errors="replace").read().split("\n"):
        st = line.strip()
        if st in ("nodes", "skeleton", "triangles", "end"):
            sect = None if st == "end" else st
            out.append(line)
            continue
        f = st.split()
        if sect == "skeleton" and len(f) == 7 and f[0] == "1":
            f[1:4] = ["%.4f" % (float(f[1 + k]) + s[k]) for k in range(3)]
            line = " ".join(f)
        elif sect == "triangles" and len(f) >= 9:
            f[1:4] = ["%.4f" % (float(f[1 + k]) + s[k]) for k in range(3)]
            line = " ".join(f)
        out.append(line)
    with open(dst, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out))


def model(gid, meta, lod1, lod2):
    t = tags(meta)
    s = MESH_SHIFT.get(gid)
    if s:
        for L in ("lod0", "lod1", "lod2"):
            shifted_smd(os.path.join(BUILD, "%s_%s_t.smd" % (gid, L)), os.path.join(BUILD, "%s_%s_ts.smd" % (gid, L)), s)
        t = {n: [([p[k] + s[k] for k in range(3)], a) for p, a in lst] for n, lst in t.items()}
    sfx = "_ts" if s else "_t"
    lines = ['$modelname "tif_guns/%s.mdl"' % gid, '$cdmaterials "tif_guns/"', "$surfaceprop \"weapon\"",
             '$body body "%s_lod0%s.smd"' % (gid, sfx),
             '$lod %d\n{\n\treplacemodel "%s_lod0%s" "%s_lod1%s"\n}' % (lod1, gid, sfx, gid, sfx),
             '$lod %d\n{\n\treplacemodel "%s_lod0%s" "%s_lod2%s"\n}' % (lod2, gid, sfx, gid, sfx),
             '$sequence idle "%s_lod0%s" fps 1' % (gid, sfx)]
    notes = []
    lines.append('$attachment "grip_r" "tif_gun" %.3f 0 0 rotate 0 0 0' % GRIP_IN)
    # Muzzle tag: tag_flash, or on pistols / some LMGs and DMRs only tag_flash_attachment / tag_silencer.
    flash = next((n for n in ("tag_flash", "tag_flash_attachment", "tag_silencer") if n in t), None)
    if flash:
        pos, ang = far(t[flash])
        lines.append('$attachment "muzzle" "tif_gun" %.3f %.3f %.3f rotate 0 0 0' % tuple(pos))
        # The gun's own axes for TIF (cl_body gun_info): a point back along the bore and one above the muzzle,
        # from the muzzle tag (MW world models hang upside down in the hand bone's frame: up is often -z).
        fwd, up = ang_vectors(ang)
        if fwd[0] * pos[0] + fwd[1] * pos[1] + fwd[2] * pos[2] < 0:  # tag pointing back: flip
            fwd = tuple(-c for c in fwd)
        back = tuple(pos[i] - fwd[i] * 10 for i in range(3))
        above = tuple(pos[i] + up[i] * 5 for i in range(3))
        lines.append('$attachment "tif_axis_b" "tif_gun" %.3f %.3f %.3f rotate 0 0 0' % back)
        lines.append('$attachment "tif_axis_u" "tif_gun" %.3f %.3f %.3f rotate 0 0 0' % above)
    else:
        notes.append("no muzzle tag (muzzle, axes)")
    # Vertical / angled foregrip: the hand's spot is the middle of the grip, below its rail mount
    # (tag_folding_grip), along the gun's down (the muzzle tag's up is the gun's top).
    # (Only with a foregrip fitted: tag_folding_grip is the rail mount, on bare barrels too: the M680 had one.)
    asked = " ".join(meta.get("atts_asked") or [])
    if "tag_folding_grip" in t and flash and ("vertgrip" in asked or "angledgrip" in asked or gid in ("oden",)):
        _, up = ang_vectors(far(t[flash])[1])
        gp, _ = t["tag_folding_grip"][-1]
        gv = tuple(gp[i] - up[i] * 2.8 for i in range(3))
        lines.append('$attachment "grip_v" "tif_gun" %.3f %.3f %.3f rotate 0 0 0' % gv)
    for name in ("tag_ik_loc_le", "tag_ik_hand_le"):
        if name in t:
            pos, _ = t[name][-1]  # the last one: a foregrip part's own, if it has one
            lines.append('$attachment "grip_l" "tif_gun" %.3f %.3f %.3f rotate 0 0 0' % tuple(pos))
            break
    else:
        notes.append("no left-hand grip point")
    # One convex hull: enough for a dropped gun, and cheap.
    lines.append('$collisionmodel "%s_lod2%s.smd"\n{\n\t$mass 4\n}' % (gid, sfx))
    qc = os.path.join(BUILD, gid + ".qc")
    with open(qc, "w") as f:
        f.write("\n".join(lines) + "\n")
    run([STUDIOMDL, "-game", GAME, "-nop4", "-nox360", qc])
    src = os.path.join(GAME, "models", "tif_guns")
    dst = os.path.join(ADDON, "models", "tif_guns")
    os.makedirs(dst, exist_ok=True)
    for fn in os.listdir(src):
        if fn.startswith(gid + "."):
            shutil.move(os.path.join(src, fn), os.path.join(dst, fn))
    return notes


# TIF's weapon bases (lua/tif/gta/weapons/_tif_bases.lua, TIF 0.38.0: no GTA weapon definitions any more)
BASE = {"rifle": "rifle", "dmr": "marksman", "lmg": "lmg", "smg": "smg", "shotgun": "shotgun", "pistol": "pistol",
        "rpg": "launcher"}
DMR = ("ebr", "ebr_sup", "sks", "svd", "svd_plague", "m13_dmr", "rytec")

WEAPON_LUA = '''-- Generated by gun_compile.py: baked MW gun "{id}" ({note}).
-- Stats from TIF's weapon base "{base}" (_tif_bases.lua) until tuned; the model is ours (models/tif_guns/{id}.mdl).
local base = TIFG.WeaponBases and TIFG.WeaponBases["{base}"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_{id}"
SWEP.PrintName = "{name}"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/{id}.mdl"
SWEP.GTG.mag = nil -- the mag is the model's own tif_mag bone (TIF.GunMag)
SWEP.TIFBaked = {{ id = "{id}", swep = "{swep}", tiers = {{ {tiers} }} }}
{suppressed}{mw}{hold}TIFG.RegisterWeaponDef(SWEP)
'''


def lua(v):
    """Python value -> Lua literal (strings, numbers, lists, dicts)."""
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "/").replace('"', '\\"')
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return "%g" % v
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        def key(k):
            return k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else '["%s"]' % k
        return "{ " + ", ".join("%s = %s" % (key(k), lua(x)) for k, x in v.items() if x is not None) + " }"
    return "nil"


def holds(gid):
    """The gun's place on the MW body's j_gun and its left-hand finger pose (gun_holds.py), as SWEP.TIFBaked.hold."""
    p = os.path.join(BUILD, gid + "_hold.json")
    if not os.path.exists(p):
        return ""
    h = json.load(open(p))
    if not h:
        return ""
    return ("-- How it's held (TIF cl_body / cl_gunhold): place on the MW body's gun bone, left-hand finger pose\n"
            "SWEP.TIFBaked.hold = %s\n" % lua(h))


def mw_sounds(gid):
    """The MW sounds recorded by tif_gunbake_sounds (data/tif_gunbake/<id>_sounds.json), as SWEP.GTG.mw."""
    p = os.path.join(DATA, gid + "_sounds.json")
    if not os.path.exists(p):
        return ""
    s = json.load(open(p, encoding="utf-8-sig"))
    keep ={k: s.get(k) for k in ("fire", "tailOut", "tailIn", "reload", "reloadEmpty") if s.get(k)}
    # (util.TableToJSON writes the reload events as {time, sound} lists)
    for k in ("reload", "reloadEmpty"):
        if k in keep:
            keep[k] = [[float(e[0]), str(e[1])] for e in keep[k]]
    return "-- MW sounds (TIF sv_weapon: fire + outdoor / indoor tail, reload foley over the reload)\nSWEP.GTG.mw = %s\n" % lua(keep)


def weapon_lua(gid, meta):
    kind = "dmr" if gid in DMR else meta.get("kind", "rifle")
    out_dir = os.path.join(ADDON, "lua", "tif", "gta", "weapons")
    os.makedirs(out_dir, exist_ok=True)
    text = WEAPON_LUA.format(id=gid, note=(meta.get("note") or "").replace("\n", " "), base=BASE[kind],
                             name=gid.replace("_", " ").upper(), swep=meta.get("swep", ""),
                             tiers=", ".join('"%s"' % t for t in meta.get("tiers") or []),
                             suppressed="SWEP.MWA_Suppressed = true\n" if meta.get("suppressed") else "",
                             mw=mw_sounds(gid), hold=holds(gid))
    # (TIF 0.38.1) per-gun rate of fire / fire mode / magazine / reload time from gun_tune.py, after the model line
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gun_tune
    tune = gun_tune.lua_block(gid)
    if tune:
        text = re.sub(r'(SWEP\.WorldModel = "[^"]*"\n)', lambda m: m.group(1) + tune, text, count=1)
    with open(os.path.join(out_dir, "weapon_tifmw_%s.lua" % gid), "w") as f:
        f.write(text)
    return "weapon_tifmw_" + gid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("id")
    ap.add_argument("--lod1", type=int, default=6)
    ap.add_argument("--lod2", type=int, default=18)
    ap.add_argument("--lua-only", action="store_true", help="only rewrite the weapon definition (sounds, flags)")
    a = ap.parse_args()
    meta = json.load(open(os.path.join(DATA, a.id + ".json")))
    if a.lua_only:
        print(a.id, "| TIF class", weapon_lua(a.id, meta), "| sounds", "yes" if mw_sounds(a.id) else "none")
        return
    texture(a.id)
    notes = model(a.id, meta, a.lod1, a.lod2)
    cls = weapon_lua(a.id, meta)
    print(a.id, "| compiled to", os.path.join(ADDON, "models", "tif_guns", a.id + ".mdl"), "| TIF class", cls, "|",
          "; ".join(notes) or "ok")


if __name__ == "__main__":
    main()
