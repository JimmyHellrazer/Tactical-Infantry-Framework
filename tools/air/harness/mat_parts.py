"""Per material of a car export: triangle count, bones it's on, bbox, and how much of its UV area the paint mask
covers. Finds what each painted material really is (body / interior / armour).
usage: python -I mat_parts.py <car id>"""
import collections
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import heli_build as hb  # noqa: E402
import car_build as cb  # noqa: E402

cfg = cb.CARS_CFG[sys.argv[1]]
nodes, skel, mats, verts = hb.read_smd(cb.export_smd(cfg))
names = {i: n for i, (n, _) in nodes.items()}
by = collections.defaultdict(list)
for t, m in enumerate(mats):
    by[m].append(t)
for m, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
    mp = cb.paint_mask(cfg["export"], m)
    if not mp:
        continue
    mask = np.asarray(Image.open(mp).convert("L").resize((512, 512))) / 255.0
    bones = collections.Counter(names[int(verts[t * 3, 0])] for t in ts)
    # per bone: tris and painted fraction (UV centroid sampled on the mask)
    print("== %s  %d tris" % (m, len(ts)))
    per = collections.defaultdict(lambda: [0, 0.0, []])
    for t in ts:
        v = verts[t * 3:t * 3 + 3]
        b = names[int(v[0, 0])]
        u, w = v[:, 7].mean(), v[:, 8].mean()
        x = int((u % 1) * 511)
        y = int((1 - (w % 1)) * 511)
        per[b][0] += 1
        per[b][1] += mask[y, x]
        per[b][2].append(v[:, 1:4].mean(0))
    for b, (n, p, c) in sorted(per.items(), key=lambda kv: -kv[1][0])[:25]:
        c = np.array(c)
        print("   %-34s %5d tris painted %3.0f%%  x %5.0f..%5.0f y %5.0f..%5.0f z %5.0f..%5.0f" % (
            b, n, 100 * p / n, c[:, 0].min(), c[:, 0].max(), c[:, 1].min(), c[:, 1].max(), c[:, 2].min(), c[:, 2].max()))
