"""
TIF prop: MW19's sledgehammer (wpn_vm_p40_me_sledgehammer_v0_prop, Wraith rip at K:/wpn_vm_p40_me_sledgehammer_v0_prop)
for the CQB hammer breach (TIF 0.38.19, sv_clear "hammer" method, cl_props).

Mesh as ripped: one bone (tag_origin), CoD units = inches, the handle along x. LOD0 / LOD2 / LOD4 as three LODs, no
collision (it's only ever a clientside model on a hand / the chest). Texture: the albedo; its alpha is MW's metal
mask (metal stores the bright metal colour), darkened to steel like the guns (gun_textures METAL_DIFFUSE), 1024.

Usage: python sledge_build.py   -> addons/tactical_infantry_framework/models/tif_mw/props/sledgehammer.mdl,
                                   materials/tif_mw/props/sledgehammer.vmt / .vtf
"""
import os
import shutil
import subprocess
import numpy as np
from PIL import Image

RIP = r"K:\wpn_vm_p40_me_sledgehammer_v0_prop"
BASE = os.path.join(RIP, "_images", "wpn_p40_me_sledgehammer_v0", "ximage_468a204b3307537d.dds")
GAME = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod"
BIN = r"K:\SteamLibrary\steamapps\common\GarrysMod\bin"
ADDON = os.path.join(GAME, "addons", "tactical_infantry_framework")
BUILD = r"K:\jimmyproject\tif_props\build\sledgehammer"
NAME = "sledgehammer"
METAL = 0.55
LIFT = 1.15


def texture():
    im = np.array(Image.open(BASE).convert("RGBA")).astype(np.float32)
    rgb, a = im[..., :3], im[..., 3:4] / 255.0
    rgb = rgb * (1 - a) * LIFT + rgb * a * METAL
    out = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").resize((1024, 1024), Image.LANCZOS)
    tga = os.path.join(BUILD, NAME + ".tga")
    out.save(tga)
    return tga


def smd(lod):
    src = os.path.join(RIP, "wpn_vm_p40_me_sledgehammer_v0_prop_LOD%d.smd" % lod)
    t = open(src).read().replace("wpn_p40_me_sledgehammer_v0", NAME)
    dst = os.path.join(BUILD, "lod%d.smd" % lod)
    open(dst, "w").write(t)
    return dst


def main():
    os.makedirs(BUILD, exist_ok=True)
    tga = texture()
    for lod in (0, 2, 4):
        smd(lod)
    # material
    mdir = os.path.join(ADDON, "materials", "tif_mw", "props")
    os.makedirs(mdir, exist_ok=True)
    src_dir = os.path.join(GAME, "materialsrc", "tif_mw", "props")
    os.makedirs(src_dir, exist_ok=True)
    shutil.copy(tga, os.path.join(src_dir, NAME + ".tga"))
    subprocess.run([os.path.join(BIN, "vtex.exe"), "-game", GAME, "-nopause", "-mkdir", os.path.join(src_dir, NAME + ".tga")], check=True)
    shutil.move(os.path.join(GAME, "materials", "tif_mw", "props", NAME + ".vtf"), os.path.join(mdir, NAME + ".vtf"))
    open(os.path.join(mdir, NAME + ".vmt"), "w").write(
        '"VertexLitGeneric"\n{\n\t"$basetexture" "tif_mw/props/%s"\n\t"$surfaceprop" "metal"\n\t"$phong" "1"\n'
        '\t"$phongboost" "0.3"\n\t"$phongexponent" "16"\n\t"$phongalbedotint" "1"\n'
        '\t"$phongfresnelranges" "[0.4 0.7 1]"\n}\n' % NAME)
    # model
    qc = os.path.join(BUILD, NAME + ".qc")
    open(qc, "w").write("\n".join([
        '$modelname "tif_mw/props/%s.mdl"' % NAME, '$cdmaterials "tif_mw/props/"', '$surfaceprop "metal"',
        "$staticprop", '$body body "lod0.smd"', '$lod 12\n{\n\treplacemodel "lod0.smd" "lod2.smd"\n}',
        '$lod 30\n{\n\treplacemodel "lod0.smd" "lod4.smd"\n}', '$sequence idle "lod0" fps 1', ""]))
    subprocess.run([os.path.join(BIN, "studiomdl.exe"), "-game", GAME, "-nop4", "-nopause", qc], check=True)
    out = os.path.join(ADDON, "models", "tif_mw", "props")
    os.makedirs(out, exist_ok=True)
    gdir = os.path.join(GAME, "models", "tif_mw", "props")
    for ext in (".mdl", ".vvd", ".dx90.vtx", ".dx80.vtx", ".sw.vtx", ".phy"):
        p = os.path.join(gdir, NAME + ext)
        if os.path.exists(p):
            shutil.move(p, os.path.join(out, NAME + ext))
    # (an empty folder left in the game's models/tif_mw broke tif_mw_build's final move: it os.remove()s what it finds)
    if os.path.isdir(gdir) and not os.listdir(gdir):
        os.rmdir(gdir)
    print("ok ->", out)


if __name__ == "__main__":
    main()
