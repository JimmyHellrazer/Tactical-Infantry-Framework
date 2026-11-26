"""
TIF gun bake, offline step 2: one texture per gun. Packs every material's base texture into an atlas (power-of-two
tiles sized by how much surface each material covers), remaps the UVs of the gun's LOD SMDs to it and writes a
single material, so a gun is one draw call.

- MW materials use base alpha as a metal mask ($color2 [0 0 0] + $blendtintbybasealpha, lit by albedo-tinted
  phong): metal there stores the bright metal colour, so it becomes dark steel (METAL_DIFFUSE of it), since our
  material has no phong / envmap.
- tint (roster): {"mag": "black"} darkens the mag bone's tile (Russian SOF 5.45 mags).
- UVs outside 0..1 (tiling) are wrapped per triangle; a triangle spanning more than one tile is clamped (counted).

Usage: gun_textures.py <id> [--size 1024]
Reads build/<id>_lod{0,1,2}.smd, writes build/<id>_lod{n}_t.smd, build/<id>_atlas.png and build/<id>_atlas.tga.
"""
import argparse
import glob
import json
import math
import os
import re
import numpy as np
from PIL import Image
try:
    from srctools.vtf import VTF
except ImportError:
    VTF = None
import subprocess
import tempfile
VTFCMD = r"K:\MWBTOOL\vtfcmd\VTFCmd.exe"


def vtf_image(p):
    if VTF is not None:
        with open(p, "rb") as f:
            vtf = VTF.read(f)
            vtf.load()
            return vtf.get().to_PIL().convert("RGBA")
    out = tempfile.mkdtemp(prefix="tifvtf_")
    subprocess.run([VTFCMD, "-file", os.path.normpath(p), "-output", os.path.normpath(out), "-exportformat", "png", "-silent"], check=True)
    tga = os.path.join(out, os.path.splitext(os.path.basename(p))[0] + ".png")
    img = Image.open(tga).convert("RGBA")
    img.load()
    return img

ADDONS = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
GAME = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod"
DATA = os.path.join(GAME, "data", "tif_gunbake")
BUILD = r"K:\jimmyproject\tif_guns\build"
SMALL_KINDS = ("pistol", "smg")
PAD = 4
METAL_DIFFUSE = 0.3

_roots = None


def roots():
    global _roots
    if _roots is None:
        _roots = [d for d in glob.glob(os.path.join(ADDONS, "*")) if os.path.isdir(os.path.join(d, "materials"))]
        _roots.append(GAME)
    return _roots


def find(rel):
    rel = rel.replace("\\", "/").lstrip("/")
    for r in roots():
        p = os.path.join(r, "materials", rel)
        if os.path.exists(p):
            return p
    return None


def read_vmt(mat):
    p = find(mat + ".vmt")
    if not p:
        return None
    t = open(p, encoding="utf-8", errors="ignore").read()
    t = re.sub(r"//[^\n]*", "", t)

    def val(k):
        m = re.search(r'"?\$' + k + r'"?\s+"?([^"\n]+?)"?\s*(\n|$)', t, re.I)
        return m.group(1).strip() if m else None
    inc = val("include") if re.search(r'^\s*"?patch"?', t, re.I | re.M) else None
    base = val("basetexture")
    if inc and not base:
        sub = read_vmt(re.sub(r"^materials/", "", inc.replace("\\", "/"))[:-4])
        return sub
    return {"path": p, "base": base, "color2": val("color2"), "blendtint": val("blendtintbybasealpha"),
            "translucent": val("translucent"), "alphatest": val("alphatest")}


def load_texture(name, size):
    p = find(name + ".vtf") if name else None
    if not p:
        return None
    img = vtf_image(p)
    if img.size == (size, size):
        return img
    # Colour and alpha resized apart: Pillow resizes RGBA premultiplied, and un-premultiplying where alpha is near
    # zero blew tiny values up into yellow / red specks.
    rgb = img.convert("RGB").resize((size, size), Image.LANCZOS)
    a = img.getchannel("A").resize((size, size), Image.LANCZOS)
    rgb.putalpha(a)
    return rgb


def parse_color(s):
    if not s:
        return None
    nums = [float(x) for x in re.findall(r"[-\d.]+", s)]
    if len(nums) < 3:
        return None
    if "{" in s:
        nums = [x / 255 for x in nums]
    return np.array(nums[:3], np.float32)


def read_smd(path):
    lines = open(path).read().split("\n")
    head_end = lines.index("triangles") + 1
    head = lines[:head_end]
    tris = []
    k = head_end
    while k + 3 < len(lines) and lines[k] != "end":
        tris.append((lines[k].strip(), [lines[k + j].split() for j in (1, 2, 3)]))
        k += 4
    return head, tris


def tri_area(v):
    p = [np.array([float(x) for x in c[1:4]]) for c in v]
    return 0.5 * float(np.linalg.norm(np.cross(p[1] - p[0], p[2] - p[0])))


def pack(sizes, atlas):
    """Quadtree packing of power-of-two squares, biggest first. Returns {key: (x, y)} or None if it doesn't fit."""
    free = [(0, 0, atlas)]
    out = {}
    for key, s in sorted(sizes.items(), key=lambda kv: -kv[1]):
        free.sort(key=lambda f: (f[2], f[1], f[0]))
        slot = next((f for f in free if f[2] >= s), None)
        if not slot:
            return None
        free.remove(slot)
        x, y, fs = slot
        while fs > s:  # split down to size
            fs //= 2
            free += [(x + fs, y, fs), (x, y + fs, fs), (x + fs, y + fs, fs)]
        out[key] = (x, y)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("id")
    ap.add_argument("--size", type=int, default=0)
    a = ap.parse_args()
    meta = json.load(open(os.path.join(DATA, a.id + ".json")))
    atlas = a.size or (512 if meta.get("kind") in SMALL_KINDS else 1024)
    tint = meta.get("tint") or {}
    head, tris0 = read_smd(os.path.join(BUILD, a.id + "_lod0.smd"))
    # Surface per material (lod0) decides its tile size; the mag bone's materials are tracked for the tint.
    area, magmat = {}, set()
    for m, v in tris0:
        area[m] = area.get(m, 0) + tri_area(v)
        if v[0][0] == "1":
            magmat.add(m)
    total = sum(area.values())
    # Tile sizes: share of the atlas by surface, power of two, at least 32; shrink until they fit.
    scale = 1.0
    while True:
        sizes = {}
        for m, ar in area.items():
            side = atlas * math.sqrt(ar / total) * scale
            sizes[m] = max(32, 2 ** int(round(math.log2(max(side, 1)))))
            sizes[m] = min(sizes[m], atlas)
        places = pack(sizes, atlas)
        if places:
            break
        scale *= 0.9
    img = Image.new("RGBA", (atlas, atlas), (90, 90, 90, 255))
    report = []
    for m, s in sizes.items():
        vmt = read_vmt(m)
        tex = load_texture(vmt and vmt["base"], s - 2 * PAD) if vmt else None
        if tex is None:
            report.append("missing texture: " + m)
            tex = Image.new("RGBA", (s - 2 * PAD, s - 2 * PAD), (70, 70, 70, 255))
        arr = np.asarray(tex).astype(np.float32) / 255
        rgb, al = arr[..., :3], arr[..., 3:4]
        c2 = parse_color(vmt and vmt["color2"])
        if vmt and vmt["blendtint"] == "1" and c2 is not None and c2.max() < 0.05:
            # MW base metalness setup: alpha = metal mask; there the RGB is the (bright) metal colour that tints
            # the phong (boost 30) over a black diffuse. Without phong / envmap: dark steel, a share of that colour.
            # Grey, not tinted: the metal colour is near-grey with small saturated specks (yellow / red) that
            # only ever showed as a faint tint in the specular, but read as coloured noise in a diffuse.
            lum = (rgb * np.array([0.3, 0.59, 0.11], np.float32)).sum(axis=2, keepdims=True)
            rgb = rgb * (1 - al) + lum * METAL_DIFFUSE * al
        elif vmt and vmt["blendtint"] == "1" and c2 is not None:
            rgb = rgb * (1 - al + al * c2)
        if m in magmat and tint.get("mag") == "black":
            lum = rgb.mean(axis=2, keepdims=True)
            rgb = np.clip(lum * 0.35, 0, 1).repeat(3, axis=2)
        out = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
        # Gutter: the tile's edge pixels repeated into the padding (no colour bleed at a distance).
        tile = Image.new("RGB", (s, s))
        tile.paste(out.resize((s, s), Image.NEAREST), (0, 0))
        tile.paste(out, (PAD, PAD))
        x, y = places[m]
        img.paste(tile, (x, y))
    img = img.convert("RGB")
    img.save(os.path.join(BUILD, a.id + "_atlas.png"))
    img.save(os.path.join(BUILD, a.id + "_atlas.tga"))
    # Remap every LOD's UVs into the tiles.
    clamped = 0
    for lod in (0, 1, 2):
        src = os.path.join(BUILD, "%s_lod%d.smd" % (a.id, lod))
        if not os.path.exists(src):
            continue
        h, tris = read_smd(src)
        with open(os.path.join(BUILD, "%s_lod%d_t.smd" % (a.id, lod)), "w") as f:
            f.write("\n".join(h) + "\n")
            for m, v in tris:
                if m not in places:
                    continue
                s = sizes[m]
                x, y = places[m]
                uv = np.array([[float(c[7]), float(c[8])] for c in v])
                uv -= np.floor(uv.min(axis=0))  # wrap tiled UVs into one tile
                if uv.max() > 1.001:
                    clamped += 1
                uv = np.clip(uv, 0, 1)
                f.write(a.id + "\n")
                for c, (u, vv) in zip(v, uv):
                    # SMD v runs bottom-up; atlas pixels top-down.
                    px = x + PAD + u * (s - 2 * PAD)
                    py = y + PAD + (1 - vv) * (s - 2 * PAD)
                    c[7] = "%.5f" % (px / atlas)
                    c[8] = "%.5f" % (1 - py / atlas)
                    f.write(" ".join(c) + "\n")
            f.write("end\n")
    print(a.id, "| atlas", atlas, "| tiles", len(sizes), "| sizes", sorted(sizes.values(), reverse=True),
          "| clamped tris", clamped, "|", "; ".join(report) or "all textures found")


if __name__ == "__main__":
    main()
