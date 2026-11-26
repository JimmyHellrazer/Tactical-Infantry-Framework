r"""The disposable AT4 for TIF (USMC AT gunners), from SandSWEP Launchers' AT4 (2026-11-25, user).

    python at4_build.py

Source: sandswep_launchers models\weapons\sandswep\mags\at4_tube.mdl (the whole AT4 laid along +Y, muzzle at -Y, sights
+Z, the vertical front grip hanging -Z near the muzzle; 24k triangles), decompiled with codport into SRC.
Built into TIF's baked-gun frame (the RPG-7's: the right wrist at the origin, barrel +X, up -Z, the right side +Y,
root bone tif_gun) so it plays MW19's RPG set with the RPG-7's hold: the tube on the RPG-7's axis, the front grip 8.5
ahead of the wrist under the right hand (SandSWEP's own world model has it 8.8 ahead of the hand bone, the RPG-7's
trigger grip is 8 ahead), the left wrist where the RPG-7's is, so the left palm lands on the tube ahead of the grip.
  at4.mdl        the launcher in hand / on the back (about 3k triangles)
  at4_spent.mdl  the spent tube dropped after the shot: same mesh, physics (a 12-sided hull), no attachments
Textures halved to 1024x512 (the normal map DXT5 instead of 8 MB uncompressed) into materials\tif_guns\at4\.
"""
import os, re, shutil, subprocess, sys
import numpy as np

CODPORT = r"K:\jimmyproject\codport"
sys.path.insert(0, CODPORT)
sys.path.insert(0, os.path.join(CODPORT, "tools"))
from stages import smd as smdlib
import lod_pack

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(REPO, "addon")
SAND = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\sandswep_launchers"
SRC = r"K:\jimmyproject\at4_src"
WORK = os.path.join(SRC, "build")
VTFCMD = r"K:\MWBTOOL\vtfcmd\VTFCmd.exe"

M = np.array([[0, -1, 0], [-1, 0, 0], [0, 0, -1]], float)
T = np.array([8.45, -0.62, -4.61])
RATIO = 0.11
AXIS_Y, AXIS_Z = -0.82, -4.05
MUZZLE_X = 13.69
GRIP_R = (3.2, 0.0, 0.0)


def decompile():
    if not os.path.isfile(os.path.join(SRC, "at4_tube", "at4_tube.smd")):
        subprocess.run([sys.executable, os.path.join(CODPORT, "tools", "mdl_decompile.py"),
                        os.path.join(SAND, "models", "weapons", "sandswep", "mags", "at4_tube.mdl"), SRC], check=True)


def to_tif():
    s = smdlib.read(os.path.join(SRC, "at4_tube", "at4_tube.smd"))
    s.nodes = [("tif_gun", -1)]
    s.skeleton = [(0, [(0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))])]
    tris = []
    for _, vs in s.triangles:
        nv = []
        for v in vs:
            p = M @ np.array(v.pos) + T
            n = M @ np.array(v.nrm)
            nv.append(smdlib.Vertex(0, tuple(p), tuple(n), v.uv, [(0, 1.0)]))
        tris.append(("at4", nv))
    s.triangles = tris
    full = os.path.join(WORK, "at4_full.smd")
    smdlib.write(s, full, s.triangles)
    lo = os.path.join(WORK, "at4.smd")
    lod_pack.write_lod(full, lo, RATIO, (0.02, 0.08))
    print("triangles", len(tris), "->", len(smdlib.read(lo).triangles))
    return lo, s


def hull_smd(path):
    s = smdlib.Smd()
    s.nodes = [("tif_gun", -1)]
    s.skeleton = [(0, [(0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))])]
    x0, x1, r, k = -23.4, 7.3, 2.3, 12
    ring = [(np.cos(2 * np.pi * i / k) * r, np.sin(2 * np.pi * i / k) * r) for i in range(k)]
    V = lambda x, a: smdlib.Vertex(0, (x, AXIS_Y + a[0], AXIS_Z + a[1]), (0.0, 0.0, 1.0), (0.0, 0.0), [(0, 1.0)])
    tris = []
    for i in range(k):
        a, b = ring[i], ring[(i + 1) % k]
        tris.append(("phy", [V(x0, a), V(x1, a), V(x1, b)]))
        tris.append(("phy", [V(x0, a), V(x1, b), V(x0, b)]))
        tris.append(("phy", [V(x1, (0, 0)), V(x1, b), V(x1, a)]))
        tris.append(("phy", [V(x0, (0, 0)), V(x0, a), V(x0, b)]))
    s.triangles = tris
    smdlib.write(s, path, tris)


def qc_text(name, body, spent):
    q = [f'$modelname "tif_guns/{name}.mdl"', f'$body "body" "{body}"', '$cdmaterials "tif_guns\\"',
         '$definebone "tif_gun" "" 0 0 0 0 0 0 0 0 0 0 0 0', '$surfaceprop "weapon"']
    if not spent:
        mx, by, bz = MUZZLE_X, AXIS_Y, AXIS_Z
        q += [f'$attachment "grip_r" "tif_gun" {GRIP_R[0]:.4f} {GRIP_R[1]:.4f} {GRIP_R[2]:.4f} rotate 0 0 0',
              f'$attachment "muzzle" "tif_gun" {mx:.4f} {by:.4f} {bz:.4f} rotate 0 0 0',
              f'$attachment "tif_axis_b" "tif_gun" {mx - 10:.4f} {by:.4f} {bz:.4f} rotate 0 0 0',
              f'$attachment "tif_axis_u" "tif_gun" {mx:.4f} {by:.4f} {bz - 5:.4f} rotate 0 0 0']
    q.append(f'$sequence "idle" "{body}" fps 30')
    if spent:
        q += ['$collisionmodel "at4_hull.smd"', "{", "\t$mass 7", "}"]
    return "\n".join(q) + "\n"


def textures():
    src = os.path.join(SAND, "materials", "models", "sandswep", "at4")
    dst = os.path.join(ADDON, "materials", "tif_guns", "at4")
    tmp = os.path.join(WORK, "tex")
    os.makedirs(dst, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    from PIL import Image
    for name, fmt in (("MI_1P_AT4_rgb", "DXT5"), ("MI_1P_AT4_e", "DXT5"), ("MI_1P_AT4_n", "DXT5")):
        subprocess.run([VTFCMD, "-file", os.path.join(src, name + ".vtf"), "-output", tmp, "-exportformat", "png",
                        "-silent"], check=True)
        png = os.path.join(tmp, name + ".png")
        im = Image.open(png)
        im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
        out = os.path.join(tmp, name.lower().replace("mi_1p_", "") + ".png")
        im.save(out)
        args = [VTFCMD, "-file", out, "-output", dst, "-format", fmt, "-alphaformat", fmt, "-silent"]
        if name.endswith("_n"):
            args += ["-flag", "NORMAL"]
        subprocess.run(args, check=True)
    t = open(os.path.join(src, "MI_1P_AT4.vmt"), encoding="latin1").read()
    t = re.sub(r"//[^\n]*", "", t)
    t = re.sub(r'models\\sandswep\\at4\\MI_1P_AT4_(rgb|n|e)', lambda m: "tif_guns/at4/at4_" + m.group(1), t)
    t = re.sub(r"\n\s*\n+", "\n", t)
    open(os.path.join(ADDON, "materials", "tif_guns", "at4.vmt"), "w", encoding="latin1", newline="\n").write(t)


def build():
    os.makedirs(WORK, exist_ok=True)
    decompile()
    body, s = to_tif()
    hull_smd(os.path.join(WORK, "at4_hull.smd"))
    textures()
    dst = os.path.join(ADDON, "models", "tif_guns")
    for name, spent in (("at4", False), ("at4_spent", True)):
        qc = os.path.join(WORK, name + ".qc")
        open(qc, "w", encoding="latin1", newline="\n").write(qc_text(name, "at4.smd", spent))
        game = lod_pack.compile_qc(qc)
        base = os.path.join(game, "models", "tif_guns", name)
        for e in (".mdl", ".vvd", ".dx90.vtx", ".dx80.vtx", ".sw.vtx", ".phy"):
            if os.path.isfile(base + e):
                shutil.move(base + e, os.path.join(dst, name + e))
        print(name, "->", dst)


if __name__ == "__main__":
    build()
