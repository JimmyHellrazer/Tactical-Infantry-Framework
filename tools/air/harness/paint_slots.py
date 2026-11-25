"""Which materials of an export carry a paint mask (slot 0x1E), how much of each it covers, and the colour under it.
usage: python -I paint_slots.py <export folder>"""
import glob
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import mat_info as mi  # noqa: E402

folder = sys.argv[1]
for f in sorted(glob.glob(os.path.join(folder, "*_images.txt"))):
    mat = os.path.basename(f)[:-len("_images.txt")]
    s = mi.slots(folder, mat)
    mp = mi.image_path(folder, mat, s.get("0x1E"))
    bp = mi.image_path(folder, mat, s.get("0x0"))
    if not mp:
        continue
    m = np.asarray(Image.open(mp).convert("L").resize((256, 256))).astype(float) / 255
    line = "%-28s mask cover %.2f" % (mat, m.mean())
    if bp:
        b = np.asarray(Image.open(bp).convert("RGB").resize((256, 256))).astype(float)
        w = m[..., None]
        if m.sum() > 1:
            line += "  colour under mask %s" % ((b * w).sum((0, 1)) / w.sum()).round(0).tolist()
        line += "  base %s" % Image.open(bp).size.__repr__()
    print(line)
