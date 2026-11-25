"""
TIF air: the fast-rope / rappel rope model (MWII misc_rapelling_rope_sim_fiber, the rope the CoD rope clips drive)
-> addons/tif_air/models/tif_air/rope.mdl.

The source: 200 joints j_rope_1..200 in a straight line along +x, 3 units apart (600 long), every one a direct child
of tag_origin, so the game can place each joint on its own (TIF entities/tif_heli.lua poses the rope: thrown out,
falling, hanging and swaying, stretched to the hover height). Vertices are bound to their strongest joint; the
"refobj_grey" placeholder pieces are dropped; each joint's piece is simplified (the fiber mesh is 39k triangles).
Colour: the export's colour map is flat grey (CoD tints it); tinted to a rope tan here.

Usage: rope_build.py   (Python with numpy, Pillow, meshoptimizer: same as heli_build.py)
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import heli_build as hb  # noqa: E402

SRC = r"K:\Rapelling Rope\Rapelling Rope mw2 apparentally\misc_rapelling_rope_sim_fiber"
SMD = os.path.join(SRC, "misc_rapelling_rope_sim_fiber_LOD0.smd")
IMG = os.path.join(SRC, "_images", "misc_rapelling_rope_01_fiber")
MODEL = "tif_air/rope"
MAT = "rope_fiber"
KEEP_RATIO, KEEP_ERR = 0.22, 0.02
TINT = (1.45, 1.28, 0.98)


def main():
    nodes, skel, mats, verts = hb.read_smd(SMD)
    by = {n: i for i, (n, _) in nodes.items()}
    W = hb.world_matrices(nodes, skel)
    joints = sorted([n for n in by if n.startswith("j_rope_")], key=lambda n: int(n.split("_")[-1]))
    # skeleton: root + the 200 joints, all children of the root (as in the source)
    bones = [("tag_origin", -1, W[by["tag_origin"]])]
    root_inv = np.linalg.inv(W[by["tag_origin"]])
    for n in joints:
        bones.append((n, 0, root_inv @ W[by[n]]))
    # triangles of the fiber material, per joint (strongest link), simplified
    keep_tris = [t for t, m in enumerate(mats) if m == "misc_rapelling_rope_01_fiber"]
    tv = verts.reshape(-1, 3, 9)[keep_tris]
    by_bone = {}
    for t in tv:
        by_bone.setdefault(int(t[0, 0]), []).append(t)
    out, n_in, n_out = [], 0, 0
    for b, ts in by_bone.items():
        arr = np.array(ts)
        n_in += len(arr)
        pos, attr, idx = hb.weld(arr.reshape(-1, 9))
        res = hb.simplify(pos, attr, idx, KEEP_RATIO, KEEP_ERR)
        piece = np.hstack([pos, attr])[res].reshape(-1, 3, 8)
        n_out += len(piece)
        name = nodes[b][0]
        if name not in joints and name != "tag_origin":
            name = "tag_origin"
        out.append((MAT, name, piece))
    print("rope: %d -> %d triangles, %d joints" % (n_in, n_out, len(joints)))
    os.makedirs(hb.BUILD, exist_ok=True)
    ref = os.path.join(hb.BUILD, "rope_ref.smd")
    hb.write_smd(ref, bones, out)
    # textures: tinted colour + normal
    mdir = os.path.join(hb.ADDON, "materials", "tif_air", "rope")
    c = hb.load(hb.one(IMG, "ximage_1314c36a93062d2c*"), mode="RGB")
    a = np.asarray(c, np.float32) * np.array(TINT, np.float32)
    hb.vtex(MAT, Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), mdir)
    hb.vtex(MAT + "_n", hb.load(hb.one(IMG, "ximage_3cb507572ff16601*"), mode="RGB"), mdir, normal=True)
    with open(os.path.join(mdir, MAT + ".vmt"), "w") as f:
        f.write('"VertexLitGeneric"\n{\n\t"$basetexture" "tif_air/rope/%s"\n\t"$bumpmap" "tif_air/rope/%s_n"\n'
                '\t"$surfaceprop" "rope"\n\t"$nocull" "1"\n}\n' % (MAT, MAT))
    qc = os.path.join(hb.BUILD, "rope.qc")
    with open(qc, "w") as f:
        f.write('$modelname "%s.mdl"\n$cdmaterials "tif_air/rope/"\n$surfaceprop "rope"\n' % MODEL)
        f.write('$body "rope" "rope_ref.smd"\n$sequence "idle" "rope_ref.smd" fps 30\n')
        # (no collision: purely visual; the bounds are set by the game each frame)
    cfg = {"model": MODEL}
    print("compiled:", hb.compile_model(cfg, qc))


if __name__ == "__main__":
    main()
