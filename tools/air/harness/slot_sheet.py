"""Contact sheet of a material's texture slots (RGB and alpha side by side), to tell masks apart.
usage: python -I slot_sheet.py <export folder> <material> <out.png>"""
import glob
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import mat_info as mi  # noqa: E402

folder, mat, out = sys.argv[1], sys.argv[2], sys.argv[3]
S = 256
tiles = []
for sem, name in mi.slots(folder, mat).items():
    p = mi.image_path(folder, mat, name)
    if not p:
        continue
    im = Image.open(p).convert("RGBA").resize((S, S))
    tiles.append((sem + " rgb", im.convert("RGB")))
    tiles.append((sem + " a", im.getchannel("A").convert("RGB")))
cols = 4
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * S, rows * (S + 16)), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, (label, im) in enumerate(tiles):
    x, y = (i % cols) * S, (i // cols) * (S + 16)
    sheet.paste(im, (x, y + 16))
    d.text((x + 4, y + 2), label, fill=(255, 255, 0))
sheet.save(out)
print(out, len(tiles), "tiles")
