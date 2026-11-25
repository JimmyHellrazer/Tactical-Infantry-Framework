r"""Find / fix vertices weighted to root + Head1 (a helmet left half on the model origin) in a model's .vvd.
    python vvd_headfix.py <model.mdl> [--fix]
Only vertices whose bones are exactly {root, ValveBiped.Bip01_Head1} with root carrying weight are touched: their
Head1 slot gets 1.0, the root slot 0 (bone slots unchanged, so the VTX stays valid)."""
import struct, sys, os, shutil
sys.path.insert(0, r"K:\jimmyproject\codport\tools")
sys.path.insert(0, r"K:\jimmyproject\codport")
from mdl_decompile import Mdl
mdl_path = sys.argv[1]
fix = "--fix" in sys.argv
m = Mdl(mdl_path)
names = [b["name"] for b in m.bones]
try:
    root, head = names.index("root"), names.index("ValveBiped.Bip01_Head1")
except ValueError:
    print(os.path.basename(mdl_path), "no root / Head1 bone:", names[:3]); sys.exit()
vvd = mdl_path[:-4] + ".vvd"
b = bytearray(open(vvd, "rb").read())
assert b[:4] == b"IDSV"
nlods = struct.unpack_from("<i", b, 12)[0]
nverts = struct.unpack_from("<i", b, 16)[0]
vstart = struct.unpack_from("<i", b, 56)[0]
bad = 0
for k in range(nverts):
    o = vstart + k * 48
    w = list(struct.unpack_from("<3f", b, o))
    bones = list(b[o + 12:o + 15])
    nb = b[o + 15]
    used = {bones[j] for j in range(nb)}
    if used == {root, head} and any(bones[j] == root and w[j] > 0.01 for j in range(nb)):
        bad += 1
        if fix:
            for j in range(nb):
                w[j] = 1.0 if bones[j] == head else 0.0
            struct.pack_into("<3f", b, o, *w)
print(f"{os.path.basename(mdl_path):16} verts {nverts:6}  root+head (bad): {bad}")
if fix and bad:
    bak = vvd + ".bak_rootweights"
    if not os.path.exists(bak): shutil.copy2(vvd, bak)
    open(vvd, "wb").write(b)
    print("  fixed, backup:", bak)
