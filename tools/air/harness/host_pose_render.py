"""The host body itself (breen_reference.smd, TIF's mw_male mesh) skinned into one frame of a host clip, same views as
pose_render.py (torso + arms): a reference for how the pose deforms a plain ValveBiped body.
usage: python -I host_pose_render.py <clip.smd> <frame> <out.png>"""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep  # noqa: E402
import cod_to_breen as c2b  # noqa: E402

REF = r"K:\jimmyproject\tif_mw\build\breen_reference.smd"
clip, frame, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]


def world_of(smd, fr):
    prep.fill_frames(smd)
    b = smd.frames[min(fr, len(smd.frames) - 1)][1]
    w = c2b.world_pose(smd.nodes, {i: prep.to_rt(v) for i, v in b.items()})
    return {smd.nodes[i][0].lower(): (np.array(R), np.array(t)) for i, (R, t) in w.items()}


ref = prep.read_smd(REF)
rest = world_of(ref, 0)
pose = world_of(prep.read_smd(clip), frame)
names = [n.lower() for n, _ in ref.nodes]
text = open(REF, encoding="latin1").read().split("\ntriangles\n")[1].splitlines()
tris = []
k = 0
while k + 3 < len(text):
    if text[k].strip() in ("end", ""):
        k += 1
        continue
    tri = []
    for l in text[k + 1:k + 4]:
        p = l.split()
        v = np.array([float(x) for x in p[1:4]])
        links = [(int(p[0]), 1.0)]
        if len(p) > 9:
            links = [(int(p[10 + 2 * j]), float(p[11 + 2 * j])) for j in range(int(p[9]))]
        acc, tw = np.zeros(3), 0
        for b, w in links:
            n = names[b]
            if n in rest and n in pose:
                R0, t0 = rest[n]
                R1, t1 = pose[n]
                acc += w * (R1 @ (R0.T @ (v - t0)) + t1)
                tw += w
        tri.append(acc / tw if tw else v)
    tris.append(tri)
    k += 4
P = np.array(tris) - pose["valvebiped.bip01_pelvis"][1]
P = P[P[..., 2].mean(1) > 8]
S = 520


def view(R, title):
    Q = P @ R.T
    n = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    sh = 0.35 + 0.65 * np.abs(n[:, 2])
    # fixed framing (same scale for every render): 64 units wide, pelvis-centred
    lo, hi = np.array([-32.0, 5.0]), np.array([32.0, 69.0])
    k = (S - 20) / 64.0
    img = Image.new("RGB", (S, S), (30, 30, 34))
    d = ImageDraw.Draw(img)
    for t in np.argsort(Q[..., 2].mean(1)):
        g = int(170 * sh[t])
        d.polygon([(10 + (q[0] - lo[0]) * k, S - 10 - (q[1] - lo[1]) * k) for q in Q[t]], fill=(g, g, int(g * 0.9)))
    d.text((6, 4), title, fill=(255, 255, 0))
    return img


def rot(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    Ry = np.array([[math.cos(y), -math.sin(y), 0], [math.sin(y), math.cos(y), 0], [0, 0, 1]])
    Rp = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    base = np.array([[0, -1, 0], [0, 0, 1], [-1, 0, 0]], float)
    return Rp @ base @ Ry


views = [view(rot(0, 0), "host a"), view(rot(90, 0), "host b"), view(rot(-90, 0), "host c"), view(rot(30, -20), "host d")]
sheet = Image.new("RGB", (S * 4, S), (20, 20, 20))
for i, v in enumerate(views):
    sheet.paste(v, (i * S, 0))
sheet.save(out)
print(out)
