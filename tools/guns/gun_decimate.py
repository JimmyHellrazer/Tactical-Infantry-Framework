"""
TIF gun bake, offline step 1: decimate an exported gun (garrysmod/data/tif_gunbake/<id>_smd.txt) to an NPC budget.

- Vertices are welded by (position, normal, uv, bone, material); meshoptimizer's attribute-aware simplifier keeps
  UV seams and material borders while it collapses.
- The gun body (bone tif_gun) and the magazine (bone tif_mag) are simplified separately, so the mag stays its own
  piece for reloads.
- SIMPLIFY_PRUNE drops small disconnected pieces first (bullets inside mags, screws, rail bolts).
- Translucent optic glass / reticle / laser beam materials are removed (MATERIAL_DROP).

Usage: gun_decimate.py <id> [--gun 1300] [--mag 160] [--out DIR]
Writes <out>/<id>.smd (reference, bones tif_gun / tif_mag) and prints the triangle counts.
"""
import argparse
import ctypes
import os
import re
import numpy as np
import meshoptimizer as mo

DATA = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\tif_gunbake"
OUT = r"K:\jimmyproject\tif_guns\build"
# (stencil_outline: optic reticle outlines; ___error: a part with a missing material)
MATERIAL_DROP = re.compile(r"(lens|glass|reticle|_ret_|holo_dot|reddot|laser_beam|beam|flare|glow|scope_overlay|"
                           r"stencil|___error)", re.I)


def read_smd(path):
    with open(path) as f:
        lines = f.read().split("\n")
    k = lines.index("triangles") + 1
    mats, tris = [], []
    while k + 3 < len(lines) and lines[k] != "end":
        mats.append(lines[k].strip())
        tri = []
        for j in range(1, 4):
            p = lines[k + j].split()
            tri.append((int(p[0]),) + tuple(float(x) for x in p[1:9]))
        # util.GetModelMeshes gives Source's winding, the reverse of what studiomdl reads from an SMD: flipped,
        # or the compiled gun shows its inside faces.
        tri.reverse()
        tris.append(tri)
        k += 4
    return mats, tris


def weld(tris, mats):
    """Index buffer over unique vertices. Returns (pos Nx3, attr Nx5 [nx ny nz u v], bone N, mat N, idx M*3)."""
    key_of, pos, attr, bone, mat, idx = {}, [], [], [], [], []
    # MW mag models hold two overlapping copies (the mags a reload swaps); duplicates also lock the simplifier
    # (every edge non-manifold). A triangle is a duplicate when the same three positions were seen already.
    seen = set()
    for t, m in zip(tris, mats):
        tk = tuple(sorted((round(v[1], 2), round(v[2], 2), round(v[3], 2)) for v in t))
        if tk in seen:
            continue
        seen.add(tk)
        for v in t:
            key = (v[0], m, round(v[1], 3), round(v[2], 3), round(v[3], 3), round(v[4], 2), round(v[5], 2),
                   round(v[6], 2), round(v[7], 4), round(v[8], 4))
            i = key_of.get(key)
            if i is None:
                i = len(pos)
                key_of[key] = i
                pos.append(v[1:4])
                attr.append(v[4:9])
                bone.append(v[0])
                mat.append(m)
            idx.append(i)
    return (np.array(pos, np.float32), np.array(attr, np.float32), np.array(bone), mat, np.array(idx, np.uint32))


MAX_ERR = 0.03  # relative to the piece's size: past this, shapes break (grip collapsing into the receiver)


def simplify(pos, attr, idx, target_tris, keep_min=0, prune=True, max_err=MAX_ERR, sloppy=False):
    res = simplify_qem(pos, attr, idx, target_tris, keep_min, prune, max_err)
    # Far LODs: a part the careful pass can't get near its target (overlapping copies, tangled pieces) is clustered
    # instead. Rough, but it keeps the outline.
    if sloppy and len(res) // 3 > target_tris * 2 and target_tris >= 4:
        dest = np.zeros(len(idx), np.uint32)
        n = mo.simplify_sloppy(dest, idx, pos, target_index_count=target_tris * 3, target_error=max_err)
        if n // 3 >= max(keep_min, 4):
            res = dest[:n].copy()
    return res


def simplify_qem(pos, attr, idx, target_tris, keep_min=0, prune=True, max_err=MAX_ERR):
    """Simplify toward target_tris without exceeding max_err. keep_min: never return fewer triangles. prune: drop
    small loose pieces (off for the mag: pruning takes the whole mag at once)."""
    if len(idx) // 3 <= target_tris:
        return idx
    dest = np.zeros(len(idx), np.uint32)
    # Normals matter less than shape and UVs (the low-poly shading is smoothed anyway).
    weights = np.array([0.15, 0.15, 0.15, 0.6, 0.6], np.float32)
    best = idx
    steps = [e for e in (0.002, 0.004, 0.008, 0.012, 0.018, 0.024, 0.03, 0.045, 0.06, 0.08, 0.11, 0.15, 0.2, 0.25, 0.3)
             if e < max_err] + [max_err]
    for err in steps:
        n = mo.simplify_with_attributes(dest, idx, pos, np.ascontiguousarray(attr), weights,
                                        target_index_count=target_tris * 3, target_error=ctypes.c_float(err),
                                        options=mo.SIMPLIFY_PRUNE if prune else 0)
        if n // 3 < keep_min:
            break
        best = dest[:n].copy()
        if n // 3 <= target_tris * 1.05:
            break
    return best


MIN_PART_TRIS = 10     # a kept part never goes below this
TINY_PART = 0.02       # parts under 2% of the whole gun's size are dropped (screws, pins, little levers)


def simplify_parts(pos, attr, mat, idx, budget, keep_min=0, prune=True, max_err=MAX_ERR, tiny=TINY_PART,
                   sloppy=False, min_part=MIN_PART_TRIS):
    """
    Simplify each part (one material = one part, close enough: every attachment has its own materials) on its own:
    the error is measured against the part's own size, so a long thin barrel keeps its shape instead of being
    eaten as "small" next to the whole gun. The budget is shared by size and detail (diagonal x sqrt(tris)).
    """
    tri = idx.reshape(-1, 3)
    tmat = np.array([mat[t[0]] for t in tri])
    whole = float(np.linalg.norm(pos[idx].max(0) - pos[idx].min(0)))
    groups = []
    for m in np.unique(tmat):
        gi = tri[tmat == m].ravel()
        d = float(np.linalg.norm(pos[gi].max(0) - pos[gi].min(0)))
        if prune and d < tiny * whole:
            continue
        groups.append((m, gi, d))
    if not groups:
        return idx
    w = np.array([d * np.sqrt(len(gi) / 3) for _, gi, d in groups])
    share = w / w.sum()
    out = []
    for (m, gi, d), s in zip(groups, share):
        target = max(min_part, int(round(budget * s)))
        # Compact this part's vertices so the simplifier's scale is the part's.
        used, local = np.unique(gi, return_inverse=True)
        res = simplify(pos[used], attr[used], local.astype(np.uint32), target, keep_min=min(keep_min, len(gi) // 3),
                       prune=prune, max_err=max_err, sloppy=sloppy)
        out.append(used[res])
    return np.concatenate(out).astype(np.uint32)


def drop_small_pieces(pos, idx, share=0.12):
    """Remove loose pieces (connected by shared positions) whose bounding box is under `share` of the largest
    piece's diagonal: the cartridges modelled inside a magazine."""
    key = {}
    pid = np.array([key.setdefault(tuple(np.round(p, 3)), len(key)) for p in pos])
    parent = list(range(len(key)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    tri = idx.reshape(-1, 3)
    for a, b, c in pid[tri]:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    comp = np.array([find(pid[t[0]]) for t in tri])
    diag = {}
    for c in np.unique(comp):
        pts = pos[tri[comp == c].ravel()]
        diag[c] = float(np.linalg.norm(pts.max(0) - pts.min(0)))
    big = max(diag.values())
    keep = np.array([diag[c] >= share * big for c in comp])
    return tri[keep].ravel()


def write_smd(path, pos, attr, bone, mat, idx, mag_origin):
    with open(path, "w") as f:
        f.write("version 1\nnodes\n0 \"tif_gun\" -1\n1 \"tif_mag\" 0\nend\nskeleton\ntime 0\n")
        f.write("0 0 0 0 0 0 0\n1 %.4f %.4f %.4f 0 0 0\nend\ntriangles\n" % tuple(mag_origin))
        for t in range(0, len(idx), 3):
            tri = idx[t:t + 3]
            # A triangle takes the material most of its corners carry.
            ms = [mat[i] for i in tri]
            m = max(set(ms), key=ms.count)
            f.write(m + "\n")
            for i in tri:
                p, a = pos[i], attr[i]
                f.write("%d %.4f %.4f %.4f %.4f %.4f %.4f %.5f %.5f\n" % (bone[i], p[0], p[1], p[2], a[0], a[1], a[2], a[3], a[4]))
        f.write("end\n")


# Three LODs. Targets are deliberately tiny: the error cap is what stops each one.
#   lod0 (close): as low as possible before shapes break, part by part.
#   lod1 (mid):   keeps the silhouette; small parts gone, part by part.
#   lod2 (far):   the whole gun as one piece, crude; may drift.
#   gun / mag: budgets (lod0's are tiny so the error cap decides; the far ones are what clustering aims for).
LODS = [
    # (user, first in-game look: 0.03 / 0.09 / 0.15 was too harsh)
    {"name": "lod0", "err": 0.015, "tiny": 0.012, "gun": 200, "mag": 40, "mag_keep": 40, "sloppy": False, "min_part": 12},
    # (2026-11-20: LODs are chained now, each from the one before, so the error caps add up: lod1 0.035 on lod0's
    # 0.015 ~ the old 0.05 from the source, lod2 0.09 on top: the old 0.11's triangle counts.)
    {"name": "lod1", "err": 0.035, "tiny": 0.035, "gun": 1100, "mag": 90, "mag_keep": 16, "sloppy": True, "min_part": 10},
    # (err 0.3 flattened long thin parts: a barrel's error is measured against its length)
    {"name": "lod2", "err": 0.09, "tiny": 0.07, "gun": 450, "mag": 30, "mag_keep": 8, "sloppy": True, "min_part": 6},
]


def drop_tiny_parts(pos, mat, idx, tiny):
    """Whole-gun pass helper: remove parts (materials) smaller than `tiny` of the gun."""
    tri = idx.reshape(-1, 3)
    tmat = np.array([mat[t[0]] for t in tri])
    whole = float(np.linalg.norm(pos[idx].max(0) - pos[idx].min(0)))
    keep = np.ones(len(tri), bool)
    for m in np.unique(tmat):
        sel = tmat == m
        g = tri[sel].ravel()
        if float(np.linalg.norm(pos[g].max(0) - pos[g].min(0))) < tiny * whole:
            keep[sel] = False
    return tri[keep].ravel()


def build_lod(pos, attr, bone, mat, idx, L):
    out_idx, report = [], []
    for b in (0, 1):
        sel = np.array([t for t in range(0, len(idx), 3) if bone[idx[t]] == b], dtype=np.int64)
        if len(sel) == 0:
            continue
        sub = idx[(sel[:, None] + np.arange(3)).ravel()]
        if b == 1:
            sub = drop_small_pieces(pos, sub)
            res = simplify_parts(pos, attr, mat, sub, L["mag"], keep_min=L["mag_keep"], prune=False,
                                 max_err=L["err"], sloppy=L["sloppy"], min_part=4)
        else:
            # (prune inside a part only at lod0's small error: at the far LODs it would take whole parts)
            res = simplify_parts(pos, attr, mat, sub, L["gun"], prune=L["err"] <= 0.03, max_err=L["err"],
                                 tiny=L["tiny"], sloppy=L["sloppy"], min_part=L["min_part"])
            if L["err"] > 0.03:
                res = drop_tiny_parts(pos, mat, res, L["tiny"])
        out_idx.append(res.astype(np.uint32))
        report.append("%s %d" % ("gun" if b == 0 else "mag", len(res) // 3))
    return (np.concatenate(out_idx) if out_idx else idx), report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("id")
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    mats, tris = read_smd(os.path.join(DATA, a.id + "_smd.txt"))
    keep = [i for i, m in enumerate(mats) if not MATERIAL_DROP.search(m)]
    dropped = sorted({mats[i] for i in range(len(mats)) if MATERIAL_DROP.search(mats[i])})
    mats, tris = [mats[i] for i in keep], [tris[i] for i in keep]
    pos, attr, bone, mat, idx = weld(tris, mats)
    os.makedirs(a.out, exist_ok=True)
    # The mag bone sits at the centre of the source mag (same for every LOD).
    magv = np.unique(idx)[bone[np.unique(idx)] == 1]
    mag_origin = pos[magv].mean(axis=0) if len(magv) else np.zeros(3)
    line = [a.id, "src %d" % (len(idx) // 3)]
    # Each LOD is simplified from the one before (lod0 from the source), not from the source again (2026-11-20, user:
    # on lower LODs "part of the mag is still in the gun ... noticeable weight paint drag"). studiomdl stores every LOD's
    # vertices as LOD0 vertices (the AKM's three LODs: 4796 vertices in all, LOD0's count, no fixups): a lower-LOD vertex
    # that isn't in LOD0 takes the nearest LOD0 vertex, and near the magwell that was often a tif_gun one, so mag
    # triangles kept a corner on the gun and stretched as the mag came out (40 of 44 guns, up to ~220 triangles;
    # scratchpad lod_snap.py). Chained, every LOD vertex is a LOD0 vertex with its own bone.
    src_idx = idx
    for L in LODS:
        final, report = build_lod(pos, attr, bone, mat, src_idx, L)
        src_idx = final
        write_smd(os.path.join(a.out, "%s_%s.smd" % (a.id, L["name"])), pos, attr, bone, mat, final, mag_origin)
        line.append("%s %d (%s)" % (L["name"], len(final) // 3, ", ".join(report)))
    print(" | ".join(line), "| dropped mats", len(dropped))


if __name__ == "__main__":
    main()
