"""How much the host's (TIF mw_male) forearm and upper arm ROLL about their own bone axis in built clips, relative to
the rest pose (reference.smd), vs the hand's roll about the forearm. CoD-rigged parts (codport) expect the forearm
not to roll (their Wrist twist helper carries the hand's twist); a rolling host forearm twists their forearm skin.
usage: python -I arm_roll.py <clip.smd> [...]"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep  # noqa: E402

REF = r"K:\jimmyproject\tif_mw\build\reference.smd"


def local_rots(smd, frame):
    prep.fill_frames(smd)
    bones = smd.frames[min(frame, len(smd.frames) - 1)][1]
    names = [n for n, _ in smd.nodes]
    out = {}
    for i, v in bones.items():
        r, t = prep.to_rt(v)
        out[names[i]] = (np.array(r), np.array(t))
    return out


def roll(r_rest, r_now, axis):
    """Twist angle (deg) of r_rest^-1 r_now about axis (bone-local)."""
    d = r_rest.T @ r_now
    w = math.sqrt(max(0.0, 1 + d[0, 0] + d[1, 1] + d[2, 2])) / 2
    if w < 1e-6:
        return 180.0
    v = np.array([d[2, 1] - d[1, 2], d[0, 2] - d[2, 0], d[1, 0] - d[0, 1]]) / (4 * w)
    p = float(np.dot(v, axis))
    return math.degrees(2 * math.atan2(p, w))


ref = local_rots(prep.read_smd(REF), 0)
for path in sys.argv[1:]:
    smd = prep.read_smd(path)
    n = len(smd.frames)
    for side in ("L", "R"):
        rows = []
        for f in (0, n // 2, n - 1):
            cur = local_rots(smd, f)
            vals = []
            for b, child in (("UpperArm", "Forearm"), ("Forearm", "Hand"), ("Hand", None)):
                name = "ValveBiped.Bip01_%s_%s" % (side, b)
                if name not in cur or name not in ref:
                    continue
                # bone axis: toward its child's rest position (bone-local), else x
                cname = "ValveBiped.Bip01_%s_%s" % (side, child) if child else None
                ax = ref[cname][1] if cname and cname in ref else np.array([1.0, 0, 0])
                ax = ax / max(np.linalg.norm(ax), 1e-9)
                vals.append("%s %+6.1f" % (b, roll(ref[name][0], cur[name][0], ax)))
            rows.append("f%-4d %s" % (f, "  ".join(vals)))
        print("%-46s %s  %s" % (os.path.basename(path)[:46], side, " | ".join(rows)))
