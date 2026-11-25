"""Which helicopter tag is each passenger clip authored on? For every clip and every candidate tag: where the man
starts (model frame) and the ground height his clip ends on. A right tag puts him inside the cabin / on the bench at
the start, and every man of a landed set ends on the model's own ground (tag_ground).
usage: python -I tag_fit.py <smd> <tag regex> <clip> [<clip> ...]"""
import math
import os
import re
import sys

import numpy as np

sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
sys.path.insert(0, r"K:\jimmyproject\tif_air")
import cod_anim_prep as prep  # noqa: E402
import heli_build as hb  # noqa: E402

SOURCES = [r"K:\duglastakedown", r"K:\mw22 anims 2\xanims"]
CM = 1 / 2.54

nodes, skel, _, _ = hb.read_smd_skeleton(sys.argv[1])
W = hb.world_matrices(nodes, skel)
rx = re.compile(sys.argv[2])
tags = {}
for i, (n, _) in nodes.items():
    if rx.search(n) or n == "tag_ground":
        M = W[i]
        tags[n] = (M[:3, 3], math.degrees(math.atan2(M[1, 0], M[0, 0])))
ground = tags.get("tag_ground", (np.zeros(3), 0))[0][2]
print("model ground z %.1f" % ground)

for clip in sys.argv[3:]:
    p = next((os.path.join(d, clip + ".seanim") for d in SOURCES if os.path.exists(os.path.join(d, clip + ".seanim"))), None)
    if not p:
        print(clip, "MISSING")
        continue
    a = prep.read_seanim(p)
    t = a["bones"].get("tag_origin", {})
    s = np.array([v * CM for v in prep.sample_keys(t["loc"], 0, prep.vlerp)]) if t.get("loc") else np.zeros(3)
    m = prep.quat_to_matrix(prep.sample_keys(t["rot"], 0, prep.slerp)) if t.get("rot") else [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    y0 = math.degrees(math.atan2(m[1][0], m[0][0]))
    tr = prep.root_track(a)
    end = np.array(tr[-1][:3])
    rows = []
    for n, (tp, ty) in tags.items():
        c, sn = math.cos(math.radians(ty)), math.sin(math.radians(ty))
        R = np.array([[c, -sn, 0], [sn, c, 0], [0, 0, 1]])
        st = tp + R @ s
        sy = ty + y0
        c2, s2 = math.cos(math.radians(sy)), math.sin(math.radians(sy))
        R2 = np.array([[c2, -s2, 0], [s2, c2, 0], [0, 0, 1]])
        en = st + R2 @ end
        rows.append((abs(en[2] - ground), n, st, sy, en))
    rows.sort(key=lambda r: r[0])
    print("%-44s %5.1fs off (%5.1f %5.1f %5.1f) yaw %6.1f drop %6.1f" % (clip, a["frames"] / 30, s[0], s[1], s[2], y0, end[2]))
    for d, n, st, sy, en in rows[:5]:
        print("     %-22s ground off %6.1f  start (%6.1f %6.1f %6.1f) yaw %6.1f  end (%6.1f %6.1f)" % (n, en[2] - ground, st[0], st[1], st[2], sy, en[0], en[1]))
