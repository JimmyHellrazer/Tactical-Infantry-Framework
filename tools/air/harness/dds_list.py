"""List the DDS images of an export per material folder: size, format, channel means (to tell colour / normal / mask).
usage: python -I dds_list.py <_images folder>"""
import glob
import os
import struct
import sys

import numpy as np
from PIL import Image

root = sys.argv[1]
for p in sorted(glob.glob(os.path.join(root, "*", "*.dds"))):
    b = open(p, "rb").read(160)
    h, w = struct.unpack_from("<II", b, 12)
    fcc = b[84:88].decode(errors="replace")
    if w < 8:
        continue
    try:
        im = Image.open(p)
        a = np.asarray(im.convert("RGBA").reduce(max(1, w // 128))).reshape(-1, 4).astype(float)
        stats = "mean %s std %s" % (a.mean(0).round(0).astype(int).tolist(), a.std(0).round(0).astype(int).tolist())
        mode = im.mode
    except Exception as e:  # noqa: BLE001
        stats, mode = "ERR %s" % e, "?"
    print("%5dx%-5d %-5s %-5s %-60s %s" % (w, h, fcc, mode, os.path.relpath(p, root)[:60], stats))
