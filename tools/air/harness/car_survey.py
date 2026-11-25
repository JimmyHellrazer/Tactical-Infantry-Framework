"""Survey CoD vehicle exports for car_build: tris, materials, seat / wheel / door / turret tags.
usage: python -I car_survey.py <export folder> [...]"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import heli_build as hb  # noqa: E402

for folder in sys.argv[1:]:
    smd = os.path.join(folder, os.path.basename(folder) + "_LOD0.smd")
    if not os.path.exists(smd):
        print("== %s: no LOD0" % folder)
        continue
    nodes, skel, mats, verts = hb.read_smd(smd)
    W = hb.world_matrices(nodes, skel)
    names = [n for _, (n, _) in nodes.items()]
    pos = {n: W[i][:3, 3] for i, (n, _) in nodes.items()}
    print("== %s  tris %d  bones %d  mats %d" % (os.path.basename(folder), len(mats), len(names), len(set(mats))))
    for pat in (r"seat|passenger|guy|driver", r"wheel", r"door", r"turret|gun|barrel|mg", r"hood|trunk|tailgate|steer",
                r"origin_static|ground"):
        hits = [n for n in names if re.search(pat, n) and not re.search(r"_dmg|_flat|_hsk|_web|_dst", n)]
        if hits:
            print("  %-26s %s" % (pat[:26], ", ".join("%s(%.0f %.0f %.0f)" % (h, *pos[h]) for h in hits[:14])
                                   + (" +%d" % (len(hits) - 14) if len(hits) > 14 else "")))
