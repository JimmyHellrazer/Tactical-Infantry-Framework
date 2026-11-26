r"""US Marines in MARPAT woodland (Workshop 3466197531, an Insurgency retexture of the INS2 security characters) as a
separate TIF faction (2026-11-25, user).

    python make_marpat.py

The pack's models are byte for byte the INS2 security_light / standard / heavy that make_ins2.py already rebuilt on
TIF's skeleton (with LODs and the ragdoll), and only four textures differ (uniform top, helmet cover, both trousers;
one VMT is a little brighter). So:
  1. materials\models\tif\ins2\usmc_wood\: every Marine VMT, pointing at the four woodland textures copied here and at
     the base Marines' textures (models\tif\ins2\usmc) for everything else
  2. the base Marines' finished LOD QCs (codport work\ins2_security_*\qc\*_lods.qc) recompiled as
     tif_factions\ins2\marpat_<light|standard|heavy>.mdl with the woodland folder first in $cdmaterials; the ragdoll
     .phy copied from the base model with the new checksum
"""
import hashlib, os, re, shutil, struct, sys

sys.path.insert(0, r"K:\jimmyproject\codport")
sys.path.insert(0, r"K:\jimmyproject\codport\tools")
import lod_pack

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addon")
PACK = r"D:\steamcmd\steamapps\workshop\content\222880\3466197531"
INS2 = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\ins2 mod retarget these pls"
WORK = r"K:\jimmyproject\work"
BASE = "models/tif/ins2/usmc"
WOOD = "models/tif/ins2/usmc_wood"
MODELS = ("security_light", "security_standard", "security_heavy")


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


def materials():
    src = os.path.join(PACK, "materials", "models", "player", "usmc")
    ref = os.path.join(INS2, "materials", "models", "player", "usmc")
    dst = os.path.join(ADDON, "materials", *WOOD.split("/"))
    changed = set()
    for root, dirs, files in os.walk(src):
        if os.path.basename(root).lower() == "vm":
            continue
        for f in files:
            if f.lower().endswith(".vtf"):
                rel = os.path.relpath(os.path.join(root, f), src)
                other = os.path.join(ref, rel)
                if not os.path.isfile(other) or md5(other) != md5(os.path.join(root, f)):
                    changed.add(os.path.splitext(rel.replace("\\", "/").lower())[0])
                    out = os.path.join(dst, rel.lower())
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    shutil.copy2(os.path.join(root, f), out)

    def repath(m):
        name = m.group(2).replace("\\", "/").lower()
        return m.group(1) + (WOOD if name in changed else BASE) + "/" + name

    n = 0
    for root, dirs, files in os.walk(src):
        if os.path.basename(root).lower() == "vm":
            continue
        for f in files:
            if f.lower().endswith(".vmt"):
                rel = os.path.relpath(os.path.join(root, f), src)
                t = open(os.path.join(root, f), encoding="latin1").read()
                t = re.sub(r'("?)models[\\/]+player[\\/]+usmc[\\/]+([^"\s]+)', repath, t, flags=re.I)
                out = os.path.join(dst, rel.lower())
                os.makedirs(os.path.dirname(out), exist_ok=True)
                open(out, "w", encoding="latin1", newline="").write(t)
                n += 1
    print(f"materials: {n} VMTs, {len(changed)} woodland textures ({', '.join(sorted(changed))})")


def models():
    dst = os.path.join(ADDON, "models", "tif_factions", "ins2")
    for m in MODELS:
        qcdir = os.path.join(WORK, f"ins2_{m}", "qc")
        src = os.path.join(qcdir, f"{m}_lods.qc")
        name = "marpat_" + m.split("_", 1)[1]
        t = open(src, encoding="latin1").read()
        t = re.sub(r'\$modelname "[^"]*"', f'$modelname "tif_factions/ins2/{name}.mdl"', t)
        t = t.replace(f'$cdmaterials "{BASE}/face/"', f'$cdmaterials "{WOOD}/face/"\n$cdmaterials "{BASE}/face/"')
        t = t.replace(f'$cdmaterials "{BASE}/"', f'$cdmaterials "{WOOD}/"\n$cdmaterials "{BASE}/"', 1)
        qc = os.path.join(qcdir, f"{name}_lods.qc")
        open(qc, "w", encoding="latin1", newline="\n").write(t)
        game = lod_pack.compile_qc(qc)
        base = os.path.join(game, "models", "tif_factions", "ins2", name)
        for e in (".mdl", ".vvd", ".dx90.vtx", ".dx80.vtx", ".sw.vtx"):
            if os.path.isfile(base + e):
                shutil.move(base + e, os.path.join(dst, name + e))
        phy = bytearray(open(os.path.join(dst, m + ".phy"), "rb").read())
        phy[12:16] = open(os.path.join(dst, name + ".mdl"), "rb").read()[8:12]
        open(os.path.join(dst, name + ".phy"), "wb").write(phy)
        print(name, "->", dst)


if __name__ == "__main__":
    materials()
    models()
