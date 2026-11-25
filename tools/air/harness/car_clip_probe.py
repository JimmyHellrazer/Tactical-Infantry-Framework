"""Where the MWII pickup seat clips put a man on a RAM export, per seat tag: idle spot, entry start (should be on the
ground beside the door), exit end, notetracks. Checks which tag each clip is authored on.
usage: python -I car_clip_probe.py <car id> <clip prefix>"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep  # noqa: E402
import heli_build as hb  # noqa: E402
import car_build as cb  # noqa: E402
import heli_infil_data as hid  # noqa: E402

cid, pre = sys.argv[1], sys.argv[2]
cfg = cb.CARS_CFG[cid]
nodes, skel, _, _ = hb.read_smd_skeleton(cb.export_smd(cfg))
W = hb.world_matrices(nodes, skel)
tags = {n: (W[i][:3, 3].copy(), math.degrees(math.atan2(W[i][1, 0], W[i][0, 0]))) for i, (n, _) in nodes.items()}
gz = tags["tag_origin_static"][0][2]
print("ground z", round(gz, 1))


def place(tag, clip):
    tp, tyaw = tags[tag]
    a = prep.read_seanim(hid.find(clip))
    s0, y0 = hid.start_of(a)
    R = lambda d: np.array([[math.cos(math.radians(d)), -math.sin(math.radians(d)), 0],
                            [math.sin(math.radians(d)), math.cos(math.radians(d)), 0], [0, 0, 1]])
    start = tp + R(tyaw) @ s0
    tr = prep.root_track(a)
    end = start + R(tyaw + y0) @ np.array(tr[-1][:3])
    eyaw = tyaw + y0 + (tr[-1][3] if len(tr[-1]) > 3 else 0)
    notes = [(fr, n) for fr, n in a["notes"]]
    return start, tyaw + y0, end, eyaw, len(tr), notes


for n in range(7):
    tag = "tag_seat_%d" % n
    print("== seat %d  tag (%6.1f %6.1f %6.1f) yaw %.0f" % (n, *tags[tag][0], tags[tag][1]))
    names = sorted({f[:-7] for f in os.listdir(hid.SOURCES[1]) if f.startswith(pre + "seat_%d_" % n) and f.endswith(".seanim")})
    for c in names:
        try:
            s, sy, e, ey, nf, notes = place(tag, c)
        except Exception as ex:  # noqa: BLE001
            print("  %-60s %s" % (c[len(pre):], ex))
            continue
        print("  %-52s start (%6.1f %6.1f %5.1f) y%5.0f -> end (%6.1f %6.1f %5.1f) y%5.0f  %3df  %s" % (
            c[len(pre):], s[0], s[1], s[2] - gz, sy, e[0], e[1], e[2] - gz, ey, nf,
            " ".join("%s@%d" % (nm, fr) for fr, nm in notes)[:90]))
