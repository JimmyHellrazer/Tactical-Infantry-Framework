"""Bones of MDL files: name, parent, procedural type; compares two models (e.g. the pack original vs the LOD rebuild)
and lists which bones of a part the base model lacks.
usage: python -I bone_compare.py <a.mdl> <b.mdl> [<base.mdl>]"""
import struct
import sys

PROC = {0: "", 1: "axisinterp", 2: "quatinterp", 3: "aimatbone", 4: "aimatattach", 5: "jiggle"}


def bones(path):
    d = open(path, "rb").read()
    n, base = struct.unpack_from("<ii", d, 156)
    out = []
    for i in range(n):
        o = base + i * 216
        name_at, parent = struct.unpack_from("<ii", d, o)
        name = d[o + name_at:d.index(b"\0", o + name_at)].decode("latin1")
        flags, ptype, pidx = struct.unpack_from("<iii", d, o + 160)
        out.append((name, parent, PROC.get(ptype, str(ptype)) if pidx else ""))
    return out


a, b = bones(sys.argv[1]), bones(sys.argv[2])
print("%s: %d bones, %d procedural | %s: %d bones, %d procedural" % (
    sys.argv[1].split("\\")[-1], len(a), sum(1 for x in a if x[2]), sys.argv[2].split("\\")[-1], len(b), sum(1 for x in b if x[2])))
na, nb = {x[0]: x for x in a}, {x[0]: x for x in b}
for n in sorted(set(na) | set(nb)):
    if n not in na or n not in nb or na[n][2] != nb[n][2]:
        print("  diff %-40s a:%s b:%s" % (n, na.get(n, ("-", 0, "MISSING"))[2] or "plain", nb.get(n, ("-", 0, "MISSING"))[2] or "plain"))
print("  procedural in b:", ", ".join(x[0] for x in b if x[2]) or "none")
if len(sys.argv) > 3:
    base = {x[0] for x in bones(sys.argv[3])}
    miss = [x[0] for x in b if x[0] not in base]
    print("  bones of b the base lacks (%d): %s" % (len(miss), ", ".join(miss[:40])))
