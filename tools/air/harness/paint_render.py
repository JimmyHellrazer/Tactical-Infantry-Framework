"""Flat-shaded orthographic renders of a built chassis SMD: red = tinted paint material, blue = its untinted inside
copy (_in), grey = everything else. Views: left side, right side, top, front 3/4.
usage: python -I paint_render.py <built chassis smd> <paint material names comma-separated> <out.png>"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import heli_build as hb  # noqa: E402

smd, paint, out = sys.argv[1], set(sys.argv[2].split(",")), sys.argv[3]
nodes, skel, mats, verts = hb.read_smd(smd)
P = verts[:, 1:4].reshape(-1, 3, 3) @ np.array(hb.UNTURN)  # (built SMDs are stored turned for studiomdl)
cut = len(sys.argv) > 4 and sys.argv[4] == "cut"
col = []
for m in mats:
    if m in paint:
        col.append((210, 60, 50))
    elif m.endswith("_in") and m[:-3] in paint:
        col.append((60, 90, 220))
    else:
        col.append((150, 150, 150))
col = np.array(col, float)
S = 420


def view(R, title):
    Q = P @ R.T  # x right, y up, z toward the viewer
    n = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    shade = 0.35 + 0.65 * np.abs(n[:, 2])
    lo, hi = Q[..., :2].reshape(-1, 2).min(0), Q[..., :2].reshape(-1, 2).max(0)
    k = (S - 20) / max(hi - lo)
    img = Image.new("RGB", (S, S), (30, 30, 34))
    d = ImageDraw.Draw(img)
    order = np.argsort(Q[..., 2].mean(1))
    for t in order:
        pts = [(10 + (q[0] - lo[0]) * k, S - 10 - (q[1] - lo[1]) * k) for q in Q[t]]
        c = tuple(int(v) for v in col[t] * shade[t])
        d.polygon(pts, fill=c)
    d.text((6, 4), title, fill=(255, 255, 0))
    return img


def rot(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    Ry = np.array([[math.cos(y), -math.sin(y), 0], [math.sin(y), math.cos(y), 0], [0, 0, 1]])
    Rp = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    # camera: world x forward, y left, z up -> screen x right, y up, z toward viewer (looking from +y = left side)
    base = np.array([[1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
    return Rp @ base @ Ry


views = [view(rot(0, 0), "left"), view(rot(180, 0), "right"), view(rot(0, 90), "top"),
         view(rot(-40, 25), "front-left 3/4"), view(rot(140, 25), "rear-right 3/4")]
# cutaway: the left half removed, looking at the cab from the left
keep = P[..., 1].mean(1) < 8
P, col = P[keep], col[keep]
views.append(view(rot(0, 0), "cut at centre, from left"))
sheet = Image.new("RGB", (S * 3, S * 2), (20, 20, 20))
for i, v in enumerate(views):
    sheet.paste(v, ((i % 3) * S, (i // 3) * S))
sheet.save(out)
print(out)
