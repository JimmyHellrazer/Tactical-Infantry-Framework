"""Where a passenger clip puts the man at frame 0 and at the end: tag_origin (root) and j_mainroot (pelvis) in inches.
usage: python -I clip_origin.py <tools_dir> <anim_dir>[;<anim_dir>] <clip> [<clip> ...]"""
import os
import sys

sys.path.insert(0, sys.argv[1])
from cod_anim_prep import read_seanim

dirs = sys.argv[2].split(";")


def val(keys, f):
    if not keys:
        return None
    best = keys[0]
    for k in keys:
        if k[0] <= f:
            best = k
    return best[1]


for n in sys.argv[3:]:
    p = next((os.path.join(d, n + ".seanim") for d in dirs if os.path.exists(os.path.join(d, n + ".seanim"))), None)
    if not p:
        print(n, "MISSING")
        continue
    a = read_seanim(p)
    fr = a["frames"]
    out = [f"{n:48s} {fr / (a['fps'] or 30):5.1f}s type{a['type']}"]
    for b in ("tag_origin", "j_mainroot"):
        k = a["bones"].get(b, {}).get("loc")
        if k:
            s, e = val(k, 0), val(k, fr - 1)
            out.append(f"{b}: {[round(x / 2.54, 1) for x in s]} -> {[round(x / 2.54, 1) for x in e]}")
        r = a["bones"].get(b, {}).get("rot")
        if r and b == "tag_origin":
            import math
            q0, q1 = val(r, 0), val(r, fr - 1)
            yaw = lambda q: round(math.degrees(math.atan2(2 * (q[3] * q[2] + q[0] * q[1]), 1 - 2 * (q[1] ** 2 + q[2] ** 2))), 1)
            out.append(f"yaw {yaw(q0)} -> {yaw(q1)}")
    print("  ".join(out))
