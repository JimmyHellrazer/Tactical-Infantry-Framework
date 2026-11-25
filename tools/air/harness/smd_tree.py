"""Bone tree of an SMD (rest positions, yaw), with triangle counts and materials per bone.
usage: python -I smd_tree.py <smd> [name filter regex]"""
import math
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, r"K:\jimmyproject\tif_air")
import heli_build as hb  # noqa: E402

path = sys.argv[1]
rx = re.compile(sys.argv[2]) if len(sys.argv) > 2 else None
nodes, skel, mats, verts = hb.read_smd(path)
W = hb.world_matrices(nodes, skel)
tri = Counter()
mat = defaultdict(Counter)
for t, m in enumerate(mats):
    b = int(verts[t * 3, 0])
    tri[b] += 1
    mat[b][m] += 1


def depth(i):
    d = 0
    while nodes[i][1] >= 0:
        i = nodes[i][1]
        d += 1
    return d


for i in sorted(nodes):
    n, p = nodes[i]
    if rx and not rx.search(n) and not tri[i]:
        continue
    M = W[i]
    yaw = math.degrees(math.atan2(M[1, 0], M[0, 0]))
    ms = ", ".join("%s:%d" % (k, v) for k, v in mat[i].most_common(3))
    print("%s%-32s <- %-26s (%7.1f %7.1f %7.1f) yaw %6.1f  tris %6d  %s" % (
        "  " * min(depth(i), 4), n, nodes[p][0] if p >= 0 else "-", M[0, 3], M[1, 3], M[2, 3], yaw, tri[i], ms))
