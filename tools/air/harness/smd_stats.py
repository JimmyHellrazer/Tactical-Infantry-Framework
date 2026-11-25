"""Stats for a big SMD: tris per material, per bone (first link), bounds, link counts.
usage: python -I smd_stats.py <smd>"""
import sys
from collections import Counter, defaultdict

path = sys.argv[1]
nodes = {}
mode = None
mat_tris = Counter()
bone_tris = Counter()
links = Counter()
lo = [1e9] * 3
hi = [-1e9] * 3
bone_box = defaultdict(lambda: [[1e9] * 3, [-1e9] * 3])
skel_first = {}
cur_mat = None
k = 0
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        s = line.strip()
        if mode is None:
            if s == "nodes":
                mode = "nodes"
            continue
        if s == "end":
            mode = "between"
            continue
        if mode == "nodes":
            parts = s.split('"')
            nodes[int(parts[0])] = (parts[1], int(parts[2]))
        elif mode == "between":
            if s == "skeleton":
                mode = "skeleton"
            elif s == "triangles":
                mode = "tris"
        elif mode == "skeleton":
            if s.startswith("time"):
                continue
            p = s.split()
            skel_first[int(p[0])] = [float(x) for x in p[1:7]]
        elif mode == "tris":
            if k == 0:
                cur_mat = s
                mat_tris[s] += 1
                k = 1
                continue
            p = s.split()
            b = int(p[0])
            v = [float(x) for x in p[1:4]]
            for i in range(3):
                lo[i] = min(lo[i], v[i])
                hi[i] = max(hi[i], v[i])
            nl = int(p[9]) if len(p) > 9 else 0
            links[nl] += 1
            wb = int(p[10]) if nl else b
            bb = bone_box[wb]
            for i in range(3):
                bb[0][i] = min(bb[0][i], v[i])
                bb[1][i] = max(bb[1][i], v[i])
            if k == 1:
                bone_tris[wb] += 1
            k = k + 1 if k < 3 else 0

print("bones", len(nodes), "| tris", sum(mat_tris.values()))
print("bounds", [round(x, 1) for x in lo], [round(x, 1) for x in hi], "size", [round(hi[i] - lo[i], 1) for i in range(3)])
print("links per vertex", dict(links))
print("== materials")
for m, c in mat_tris.most_common():
    print(f"{c:8d} {m}")
print("== tris by (first) weighted bone")
for b, c in bone_tris.most_common():
    bb = bone_box[b]
    print(f"{c:8d} {nodes[b][0]:34s} box {[round(x) for x in bb[0]]} .. {[round(x) for x in bb[1]]}")
