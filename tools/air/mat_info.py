"""MWII-style exports (hashed xmaterial / ximage names): each material's <mat>_images.txt says which image fills which
semantic slot. Slot 0x0 = colour (albedo, alpha sometimes a mask), 0x4 = normal (RGB) + gloss (A). Images shared by
every material are engine placeholders (flat normal, black, white) and are ignored.
Used by car_build.py to write texture recipes automatically; run alone to print a model's materials.
usage: python -I mat_info.py <export folder (has *_images.txt and _images/)>"""
import glob
import os
import sys

import numpy as np
from PIL import Image

PLACEHOLDERS = {"ximage_3c29eeff15212c37", "ximage_4a882744bc523875", "ximage_5c2d1c3e952cb190"}


def slots(folder, mat):
    p = os.path.join(folder, mat + "_images.txt")
    out = {}
    if not os.path.exists(p):
        return out
    for line in open(p, encoding="utf-8", errors="replace").read().splitlines()[1:]:
        if "," not in line:
            continue
        sem, img = line.split(",", 1)
        img = img.split("~")[0] if img.startswith("ximage") else img
        out[sem.replace("unk_semantic_", "")] = img
    return out


def image_path(folder, mat, name):
    if not name or name in PLACEHOLDERS:
        return None
    hits = glob.glob(os.path.join(folder, "_images", mat, name + "*.dds"))
    return hits[0] if hits else None


def stats(path):
    im = Image.open(path).convert("RGBA")
    w = im.size[0]
    a = np.asarray(im.reduce(max(1, w // 128))).reshape(-1, 4).astype(float)
    rgb = a[:, :3]
    sat = (rgb.max(1) - rgb.min(1)).mean()
    return {"mean": a.mean(0).round(0).tolist(), "std": a.std(0).round(0).tolist(), "sat": round(float(sat), 1),
            "size": im.size}


def recipe(folder, mat):
    """{base, normal, kind_hint, colour stats} for one material."""
    s = slots(folder, mat)
    base = image_path(folder, mat, s.get("0x0"))
    normal = image_path(folder, mat, s.get("0x4"))
    packed = False
    if not normal and s.get("0x9"):
        # MW2019: slot 0x9 = normal / occlusion / gloss packed: normal X in alpha, Y in green
        normal = image_path(folder, mat, s.get("0x9"))
        packed = normal is not None
    st = stats(base) if base else None
    glass = "glass" in mat.lower()
    # MW2019: slot 0x44 = an alpha mask (grilles, nets, canvas cut-outs); on glass it's the glass's own
    alpha = None if glass else image_path(folder, mat, s.get("0x44"))
    return {"base": base, "normal": normal, "packed": packed, "stats": st, "glass": glass, "alpha": alpha}


def unpack_normal(img):
    """MW2019 packed normal (X = alpha, Y = green) -> a plain RGB normal map."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 127.5 - 1
    x, y = a[..., 3], a[..., 1]
    z = np.sqrt(np.clip(1 - x * x - y * y, 0, 1))
    rgb = np.stack([x, y, z], -1)
    return Image.fromarray(((rgb + 1) * 127.5).clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")


if __name__ == "__main__":
    folder = sys.argv[1]
    for f in sorted(glob.glob(os.path.join(folder, "*_images.txt"))):
        mat = os.path.basename(f)[:-len("_images.txt")]
        r = recipe(folder, mat)
        st = r["stats"]
        print("%-28s base %-28s normal %-28s %s" % (
            mat, os.path.basename(r["base"] or "-")[:28], os.path.basename(r["normal"] or "-")[:28],
            ("mean %s std %s sat %.0f %s" % (st["mean"], st["std"], st["sat"], st["size"])) if st else ""))
