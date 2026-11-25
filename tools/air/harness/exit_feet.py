"""For each built passenger exit clip: when do his feet really touch the ground (root height curve + the pose's feet),
when does the root curve itself land, and how high is his pelvis when TIF takes him back (crouched?).
usage: python -I exit_feet.py <role glob, e.g. mwlb_*>"""
import fnmatch
import glob
import math
import os
import sys

sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep  # noqa: E402
import cod_to_breen as c2b  # noqa: E402

MANIFEST = r"K:\jimmyproject\tif_mw\manifest.py"
BUILD = r"K:\jimmyproject\tif_mw\build\heli"
DATA = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\tif_air\lua\autorun\tif_air_infil.lua"
SOURCES = [r"K:\duglastakedown", r"K:\mw22 anims 2\xanims"]

import runpy  # noqa: E402
fam = runpy.run_path(MANIFEST)["FAMILIES"]["heli"]
rx = sys.argv[1] if len(sys.argv) > 1 else "*"

# release points from the generated data: role_suffix -> release u
import re  # noqa: E402
rel = {}
txt = open(DATA, encoding="utf-8").read()
for m in re.finditer(r'role = "(\w+)".*?exits = \{(.*?)\} \}', txt):
    for s, u in re.findall(r'(\w+) = \{ off = .*?release = ([\d.]+)', m.group(2)):
        rel[m.group(1) + "_" + s] = float(u)

for role, clip, opts in fam:
    if not fnmatch.fnmatch(role, rx) or role.endswith("_idle") or "pilot" in role or "chief" in role:
        continue
    smd_path = os.path.join(BUILD, clip + ".smd")
    if not os.path.exists(smd_path):
        print(role, "no SMD")
        continue
    src = next(os.path.join(d, clip + ".seanim") for d in SOURCES if os.path.exists(os.path.join(d, clip + ".seanim")))
    track = prep.root_track(prep.read_seanim(src))
    smd = prep.read_smd(smd_path)
    prep.fill_frames(smd)
    names = [n for n, _ in smd.nodes]
    lf, rf = names.index("ValveBiped.Bip01_L_Foot"), names.index("ValveBiped.Bip01_R_Foot")
    pel = names.index("ValveBiped.Bip01_Pelvis")
    n = len(smd.frames)
    zend = track[-1][2]
    feet, pelv = [], []
    for f, (_, bones) in enumerate(smd.frames):
        w = c2b.world_pose(smd.nodes, {i: prep.to_rt(v) for i, v in bones.items()})
        rz = track[min(f, len(track) - 1)][2]
        feet.append(rz + min(w[lf][1][2], w[rf][1][2]) - zend)
        pelv.append(w[pel][1][2])
    # first frame the feet are within 4 of where they end, and stay there
    touch = next((f for f in range(n) if all(abs(feet[g] - feet[-1]) < 4 for g in range(f, n))), n - 1)
    rootland = next((f for f in range(n) if all(abs(track[min(g, len(track) - 1)][2] - zend) < 2 for g in range(f, n))), n - 1)
    r = rel.get(role)
    rf_ = int(round(r * (n - 1))) if r is not None else n - 1
    print("%-24s %4d fr | feet down %3d (%.2fs) | root lands %3d (%.2fs) | gap %+5.2fs | release %3d, pelvis %5.1f %s" % (
        role, n, touch, touch / 30, rootland, rootland / 30, (touch - rootland) / 30, rf_, pelv[rf_],
        "CROUCHED" if pelv[rf_] < 30 else ""))
