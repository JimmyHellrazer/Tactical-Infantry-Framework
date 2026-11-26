r"""BF4 Russian Ground Forces (MadIvan18's pack, Workshop 1444174239) -> TIF's third default faction "russians", rebuilt
on TIF's own ValveBiped host skeleton like the INS2 starter factions (make_ins2.py: same body / qc / compile / package
flow, same host rig, horde zombies' infected male ragdoll).

    python tools\sets\make_bf4ru.py [model ...] [--stages body,qc,compile,package] [--no-materials]

Choices (2026-11-25, user):
  - no blue: the Siberian "sib" camo models (ru_soldierD_*, ru_reconC_*) are not built
  - the recon-set extras appended to the end of every soldier model's HeadWear list (beanie, beanie + headset, cap,
    gas mask, gas mask + headset) render scrambled in game: dropped from the soldier models (the recon models keep
    their own); the soldier models keep the helmets only
  - never bare-headed: HeadWear / Mask lose their blank option
  - every model is decompiled once (tools\mdl_decompile.py) into WORK and rebuilt from those SMDs, so nothing of the
    original compile survives
  - head flexes are dropped (the head keeps its eyeballs and the 5 face skins)
Materials: the pack's materials\models\madivan18 tree copied (lower case, sib textures skipped) to
materials\models\tif\bf4ru\, VMT paths rewritten.
"""
import json, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CODPORT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, CODPORT)
sys.path.insert(0, HERE)
from stages import smd as smdlib
import make_ins2 as ins2

SRC = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\comradivan18_s_bf4_russian_ground_forces_1444174239"
ADDON = r"K:\jimmyproject\Tactical Infantry Framework\Tactical Infantry Framework\addon"
WORK = r"K:\jimmyproject\bf4ru_src"
MAT_ROOT = "models/tif/bf4ru"
OUT_DIR = "tif_factions\\bf4ru"

MODELS = {
    "ru_recona_karl_valvebiped": "recon_a",
    "ru_reconb_karl_valvebiped": "recon_b",
    "ru_reconb_karlbalac2_valvebiped": "recon_b_balaclava",
    "ru_soldiera_karl_valvebiped": "soldier_a",
    "ru_soldiera_karlbalac2_valvebiped": "soldier_a_balaclava",
    "ru_soldiera_baku_karl_valvebiped": "soldier_baku",
    "ru_soldiera_baku_karlbalac3_valvebiped": "soldier_baku_balaclava",
    "ru_soldierb_karl_valvebiped": "soldier_b",
    "ru_soldierb_karlbalac3_valvebiped": "soldier_b_balaclava",
    "ru_soldierc_karl_valvebiped": "soldier_c",
    "ru_soldierc_karlbalac_valvebiped": "soldier_c_balaclava",
    "ru_soldieraftermath_karl_valvebiped": "soldier_aftermath",
    "ru_soldieraftermath_karlbalac_valvebiped": "soldier_aftermath_balaclava",
    "ru_soldieremr_karl_valvebiped": "soldier_emr",
    "ru_soldieremr_karlbalac3_valvebiped": "soldier_emr_balaclava",
}
NO_BLANK = ("headwear", "mask")
SOLDIER_DROP = re.compile(r"(beanie|_cap\.smd|gasmask|headset2)", re.I)


def copy_materials():
    src = os.path.join(SRC, "materials", "models", "madivan18")
    dst = os.path.join(ADDON, "materials", *MAT_ROOT.split("/"))
    n = 0
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src).lower()
        out = os.path.join(dst, "" if rel == "." else rel)
        os.makedirs(out, exist_ok=True)
        for f in files:
            if re.search(r"_sib(_v2)?_[a-z]+\.vt[fm]$", f.lower()):
                continue
            p, q = os.path.join(root, f), os.path.join(out, f.lower())
            if f.lower().endswith(".vmt"):
                t = open(p, encoding="latin1").read()
                t = re.sub(r'(models[\\/]+madivan18[\\/]+)([^"\s]*)',
                           lambda m: f"{MAT_ROOT}/" + m.group(2).replace("\\", "/").lower(), t, flags=re.I)
                open(q, "w", encoding="latin1", newline="").write(t)
            else:
                shutil.copy2(p, q)
            n += 1
    print(f"materials: {n} files -> {dst}")


def source_qc(model):
    return os.path.join(WORK, model, model + ".qc")


def cdmaterials(model):
    out = []
    for m in re.finditer(r'\$cdmaterials "([^"]*)"', open(source_qc(model), encoding="latin1").read()):
        p = m.group(1).replace("\\", "/").lower()
        if p.startswith("models/madivan18/"):
            out.append(MAT_ROOT + "/" + p[len("models/madivan18/"):])
        elif p == "models/madivan18/":
            out.append(MAT_ROOT + "/")
    return [p for p in out if os.path.isdir(os.path.join(ADDON, "materials", *p.strip("/").split("/")))]


def skins(model):
    m = re.search(r'\$texturegroup "skinfamilies"\s*\{(.*?)\n\}', open(source_qc(model), encoding="latin1").read(), re.S)
    return [r.lower() for r in re.findall(r'\{\s*"([^"]+)"\s*\}', m.group(1))] if m else []


def trim(model, parts):
    soldier = "_soldier" in model
    for p in parts:
        key = p["name"].lower()
        if key in NO_BLANK:
            p["blank"] = False
            if soldier:
                p["studios"] = [s for s in p["studios"] if not SOLDIER_DROP.search(s)]
    return parts


def write_character(model, parts, combined_path, combined):
    short = MODELS[model]
    cid = f"bf4ru_{short}"
    mats = {}
    for m, _ in combined.triangles:
        mats.setdefault(m.split("__")[0], []).append(m)
    for k in mats:
        mats[k] = sorted(set(mats[k]))
    used, groups, meta = set(), [], []
    if mats.get("eyes"):
        used.add("eyes")
        groups.append(f'[[body.bodygroups]]\nname = "eyes"\nmaterials = {json.dumps(mats["eyes"])}\n')
        meta.append({"name": "eyes", "eyes": True})
    for bi, p in enumerate(parts):
        name = ins2.group_name(p, used)
        opts = [(oi, mats.get(f"b{bi}o{oi}", [])) for oi in range(len(p["studios"]))]
        opts = [(oi, m) for oi, m in opts if m]
        if not opts:
            meta.append({"name": name, "empty": True, "blank": p["blank"]})
            continue
        if len(opts) == 1 and not p["blank"]:
            groups.append(f'[[body.bodygroups]]\nname = "{name}"\nmaterials = {json.dumps(opts[0][1])}\n')
        else:
            g = f'[[body.bodygroups]]\nname = "{name}"\n'
            for oi, m in opts:
                g += f'[[body.bodygroups.options]]\nname = "o{oi + 1}"\nmaterials = {json.dumps(m)}\n'
            groups.append(g)
        meta.append({"name": name, "blank": p["blank"], "options": len(opts)})
    toml = f"""# Generated by tools\\sets\\make_bf4ru.py - edit the generator, not this file.
[character]
id       = "{cid}"
body_smd = '{combined_path}'

[model]
modelname = '{OUT_DIR}\\{short}.mdl'
body      = "{cid}"
head      = ""
ragdoll   = true

[paths]
output_addon = '{ADDON}'
rig = '{ins2.RIG_QCI}'
reference_anim = '{ins2.RIG_REF}'
twist_vrd = ''

[package]
ragdoll_phy = '{ins2.VB_PHY}'

[qc]
cdmaterials = {json.dumps(cdmaterials(model))}

[body]
smd_prefix = "{cid}_"
rotate_z_deg = 0
rebind = true
rebind_joint_frames = true
rebind_scale_to = "ValveBiped.Bip01_Head1"
keep_bones = []

[[body.merge_bones]]
match = "ValveBiped.Bip01"
to = "ValveBiped.Bip01_Pelvis"

[[body.merge_bones]]
match = "ValveBiped.forward"
to = "ValveBiped.Bip01_Pelvis"

""" + "\n".join(groups)
    path = os.path.join(CODPORT, "characters", cid + ".toml")
    open(path, "w", encoding="utf-8", newline="\n").write(toml)
    json.dump({"parts": parts, "groups": meta}, open(os.path.join(WORK, model, "bf4ru_meta.json"), "w"), indent=1)
    return cid, meta


def add_skins(cid, model):
    fam = skins(model)
    if len(fam) < 2:
        return
    qcdir = os.path.join(r"K:\jimmyproject\work", cid, "qc")
    p = os.path.join(qcdir, [f for f in os.listdir(qcdir) if f.endswith(".qc")][0])
    t = open(p, encoding="utf-8").read()
    t = re.sub(r'\$texturegroup "skinfamilies"\s*\{.*?\n\}\n?', "", t, flags=re.S)
    block = '$texturegroup "skinfamilies"\n{\n' + "".join(f'\t{{ "{f}" }}\n' for f in fam) + "}\n"
    t = t.replace("$cdmaterials", block + "$cdmaterials", 1)
    open(p, "w", encoding="utf-8", newline="\n").write(t)


def main(argv):
    want = [a for a in argv if not a.startswith("--")] or list(MODELS)
    stages = ["body", "qc", "compile", "package"]
    for a in argv:
        if a.startswith("--stages="):
            stages = a.split("=", 1)[1].split(",")
    if "--no-materials" not in argv:
        copy_materials()
    ins2.make_host_rig()
    for model in want:
        if not os.path.isfile(source_qc(model)):
            subprocess.run([sys.executable, os.path.join(CODPORT, "tools", "mdl_decompile.py"),
                            os.path.join(SRC, "models", "madivan18", "bf4", "ru", model + ".mdl"), WORK], check=True)
        ins2.WORK = WORK
        parts = trim(model, ins2.parse_qc(source_qc(model)))
        out = os.path.join(WORK, model)
        combined = None
        for bi, p in enumerate(parts):
            for oi, studio in enumerate(p["studios"]):
                s = smdlib.read(os.path.join(out, studio))
                if combined is None:
                    combined = smdlib.read(os.path.join(out, studio))
                    combined.triangles = []
                assert [n for n, _ in s.nodes] == [n for n, _ in combined.nodes], f"{studio}: other skeleton"
                for mat, vs in s.triangles:
                    eye = mat.lower().startswith("eyeball")
                    combined.triangles.append((f"{'eyes' if eye else f'b{bi}o{oi}'}__{mat}", vs))
        path = os.path.join(out, model + "_combined.smd")
        smdlib.write(combined, path, combined.triangles)
        cid, meta = write_character(model, parts, path, combined)
        if "body" in stages:
            ins2.codport(cid, ["body"])
        eye_smd = ins2.untag_body(cid)
        if "qc" in stages:
            ins2.codport(cid, ["qc"])
            ins2.fix_qc(cid, meta, eye_smd)
            add_skins(cid, model)
        rest = [s for s in stages if s in ("compile", "package")]
        log = ins2.codport(cid, rest) if rest else ""
        res = [l for l in log.splitlines() if "materials resolve" in l or "WARNING" in l or "ragdoll" in l]
        print(f"{MODELS[model]:28} {cid:36} " + " | ".join(r.strip() for r in res))


if __name__ == "__main__":
    main(sys.argv[1:])
