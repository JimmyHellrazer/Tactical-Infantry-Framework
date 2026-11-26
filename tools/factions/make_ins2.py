r"""Insurgency 2 characters (MadIvan's INS2 pack, used with permission) -> TIF's starter factions, on TIF's own
ValveBiped skeleton (the mw_male host's bind pose = stock ValveBiped, so they plain bone-merge onto TIF's soldier: no
retarget map, no arm fixes; 2026-11-25, user: "fix the models themselves to be valvebiped as best as possible").
(First built on codport's shared MW19 rig, which keeps CoD's bone axes under ValveBiped names: it needs TIF's retarget
and twisted when bone-merged.)

    python tools\sets\make_ins2.py [model ...] [--stages body,qc,compile,package] [--no-materials]

Source: K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\ins2 mod retarget these pls (compiled INS2 MDLs,
3ds Max Biped skeleton "Bip01 / Pelvis / L UpperArm", their own finished VMT / VTF).
Per model:
  1. decompile (tools\mdl_decompile.py) into K:\jimmyproject\ins2_src\<model>\
  2. one combined SMD: every bodypart mesh, materials tagged b<part>o<option>__<material> so codport's body stage
     splits them back per option (INS2 options share materials); the eye meshes are their own group
  3. characters\ins2_<model>.toml: INS2 bone names -> ValveBiped ([body.bone_names]; the twist / jiggle / weapon
     bones aren't renamed, their weights go to the nearest rig bone), rebind onto the rig scaled to its head height,
     arms / hands / fingers by joint frames (INS2 bones roll differently from ValveBiped)
  4. codport body + qc, then: tags stripped (materials lower case), blank options only where INS2 had them, the eye
     group back as a $model with eyeballs (positions measured on the rebound eye meshes), cdmaterials -> the copy below
  5. codport compile + package into the TIF base (models\tif_factions\ins2\<model>.mdl) with a stock ValveBiped ragdoll
     (VB_PHY: the skeleton is bone for bone a stock ValveBiped one, so its .phy fits; checksum restamped)
Rig: shared\rig_tifhost.qci + shared\anims\reference_tifhost.smd, written from mw_male.mdl (make_host_rig): every host
bone's $definebone (no j_gun), IK chains; no CoD twist helpers ($proceduralbones off: the host's own twist bones
Ulna / Wrist take INS2's ForeTwist1 / 2 and are animated by the host).
Materials: copied once into the base under materials\models\tif\ins2\ (ins, usmc; VMT paths rewritten) plus an
EyeRefract eye set (codport's, from tif_cod_factions). Bodygroups: INS2's own; TIF picks them at random.
"""
import json, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CODPORT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, CODPORT)
from stages import smd as smdlib

SRC = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\ins2 mod retarget these pls"
ADDON = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\tactical_infantry_framework"
COD = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\tif_cod_factions"
WORK = r"K:\jimmyproject\ins2_src"
MODELS = ["insurgent_light", "insurgent_standard", "insurgent_heavy", "security_light", "security_standard",
          "security_heavy", "civilian_vip_insurgent", "civilian_vip_security"]
MAT_ROOT = "models/tif/ins2"
HOST = os.path.join(ADDON, "models", "tif_mw", "mw_male.mdl")
VB_PHY = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\horde_zombies\models\hordez\citizens\male_02.phy"
RIG_QCI = os.path.join(CODPORT, "shared", "rig_tifhost.qci")
RIG_REF = os.path.join(CODPORT, "shared", "anims", "reference_tifhost.smd")

VB = "ValveBiped.Bip01_"
BONES = {"Pelvis": "Pelvis", "Spine": "Spine", "Spine1": "Spine1", "Spine2": "Spine2", "Spine3": "Spine4",
         "Neck": "Neck1", "Head": "Head1"}
for s in ("L", "R"):
    for b in ("Clavicle", "UpperArm", "Forearm", "Hand", "Thigh", "Calf", "Foot", "Toe0"):
        BONES[f"{s} {b}"] = f"{s}_{b}"
    for f in range(5):
        for seg in ("", "1", "2"):
            BONES[f"{s} Finger{f}{seg}"] = f"{s}_Finger{f}{seg}"
    BONES[f"{s} ForeTwist1"] = f"{s}_Ulna"     # INS2 forearm twist chain -> the host's twist bones
    BONES[f"{s} ForeTwist2"] = f"{s}_Wrist"
BONES = {k: VB + v for k, v in BONES.items()}


def make_host_rig():
    """TIF's host skeleton (mw_male.mdl bind pose) as a codport rig: QCI ($definebone + IK chains) and reference SMD."""
    import math
    import numpy as np
    sys.path.insert(0, os.path.join(CODPORT, "tools"))
    from mdl_decompile import Mdl
    m = Mdl(HOST)
    bones = [b for b in m.bones if b["name"] != "j_gun"]
    order = [b["name"] for b in bones]
    byname = {b["name"]: b for b in m.bones}
    rows, qci = [], ["// TIF host skeleton (mw_male.mdl bind pose: stock ValveBiped). Written by make_ins2.py make_host_rig()."]
    out = smdlib.Smd()
    for i, b in enumerate(bones):
        par = m.bones[b["parent"]]["name"] if b["parent"] >= 0 else ""
        if par and par not in order:
            par = ""
        W = b["world"]
        L = W if not par else np.linalg.inv(byname[par]["world"]) @ W
        rx, ry, rz = smdlib.matrix_to_euler(L[:3, :3].tolist())
        pos = tuple(float(x) for x in L[:3, 3])
        out.nodes.append((b["name"], order.index(par) if par else -1))
        rows.append((i, pos, (rx, ry, rz)))
        qci.append(f'$definebone "{b["name"]}" "{par}" {pos[0]:.6f} {pos[1]:.6f} {pos[2]:.6f} '
                   f'{math.degrees(ry):.6f} {math.degrees(rz):.6f} {math.degrees(rx):.6f} 0 0 0 0 0 0')
    qci += ['$ikchain "rhand" "ValveBiped.Bip01_R_Hand" knee 0.707 0.707 0',
            '$ikchain "lhand" "ValveBiped.Bip01_L_Hand" knee 0.707 0.707 0',
            '$ikchain "rfoot" "ValveBiped.Bip01_R_Foot" knee 0.707 -0.707 0',
            '$ikchain "lfoot" "ValveBiped.Bip01_L_Foot" knee 0.707 -0.707 0']
    open(RIG_QCI, "w", encoding="utf-8", newline="\n").write("\n".join(qci) + "\n")
    out.skeleton = [(0, rows)]
    smdlib.write(out, RIG_REF, [])
    print(f"host rig: {len(bones)} bones -> {RIG_QCI}")


def side_of(model):
    return "usmc" if model.startswith("security") or model == "civilian_vip_security" else "ins"


# ---------------------------------------------------------------- materials

def copy_materials():
    r"""INS2 materials -> materials\models\tif\ins2\<ins|usmc>\..., texture paths in the VMTs rewritten; eyes."""
    src = os.path.join(SRC, "materials", "models", "player")
    dst = os.path.join(ADDON, "materials", *MAT_ROOT.split("/"))
    n = 0
    for side in ("ins", "usmc"):
        for root, dirs, files in os.walk(os.path.join(src, side)):
            if os.path.basename(root).lower() == "vm":
                continue                                   # viewmodel hands: not used
            rel = os.path.relpath(root, os.path.join(src, side)).lower()
            out = os.path.join(dst, side, "" if rel == "." else rel)
            os.makedirs(out, exist_ok=True)
            for f in files:
                p = os.path.join(root, f)
                q = os.path.join(out, f.lower())
                if f.lower().endswith(".vmt"):
                    t = open(p, encoding="latin1").read()
                    # (ins_light / us_light / us_heavy: INS2's shared folders; what's used of them lives in ins / usmc)
                    t = re.sub(r"models[\\/]+player[\\/]+(ins_light|ins|us_light|us_heavy|usmc)\b",
                               lambda m: f"{MAT_ROOT}/" + ("ins" if m.group(1).lower().startswith("ins") else "usmc"),
                               t, flags=re.I)
                    open(q, "w", encoding="latin1", newline="").write(t)
                else:
                    shutil.copy2(p, q)
                n += 1
    # the bare arms' normal map (ins_light_color.vmt names one the pack doesn't have): made from the arm texture's own
    # shading with tools\fake_normal.py (strength 2, blur 1, 1024 px), kept in WORK
    shutil.copy2(os.path.join(WORK, "ins_light_normal.vtf"), os.path.join(dst, "ins", "ins_light_normal.vtf"))
    # eyes: codport's EyeRefract set (iris, occlusion, cornea) from tif_cod_factions
    eyes = os.path.join(dst, "eyes")
    os.makedirs(eyes, exist_ok=True)
    cm = os.path.join(COD, "materials", "models")
    for a, b in ((r"jimmy\cod\al_qatala_head_01_eye_iris.vtf", "ins2_eye_iris_brown.vtf"),
                 (r"jimmy\cod\codport_eye_ao.vtf", "ins2_eye_ao.vtf"),
                 (r"wap\shared\eyes_cornea.vtf", "ins2_eyes_cornea.vtf")):
        shutil.copy2(os.path.join(cm, a), os.path.join(eyes, b))
    for side_lr in ("l", "r"):
        open(os.path.join(eyes, f"eyeball_{side_lr}.vmt"), "w", newline="").write(f""""EyeRefract"
{{
	"$Iris" 				"{MAT_ROOT}/eyes/ins2_eye_iris_brown"
	"$AmbientOcclTexture" 	"{MAT_ROOT}/eyes/ins2_eye_ao"
	"$Envmap" 				"Engine/eye-reflection-cubemap-"
	"$CorneaTexture" 		"{MAT_ROOT}/eyes/ins2_eyes_cornea"
	"$AmbientOcclColor" 	"[0.3 0.3 0.3]"
	"$Dilation" 			"0.5"
	"$Glossiness" 			"0.1"
	"$ParallaxStrength" 	"0.25"
	"$CorneaBumpStrength" 	"1"
	"$HalfLambert" 			"1"
	"$NoDecal" 				"1"
	"$EyeballRadius" 		"0.5"
	"$RaytraceSphere" 		"1"
	"$SphereTexkillCombo" 	"1"
}}
""")
    print(f"materials: {n} files -> {dst} (+ eyes)")


# ---------------------------------------------------------------- source

def parse_qc(path):
    """The decompiled QC's bodyparts in order: [{name, kind, studios, blank, eyeballs}]."""
    parts, cur = [], None
    for line in open(path, encoding="latin1"):
        t = line.strip()
        m = re.match(r'\$model "([^"]+)" "([^"]+)"', t)
        if m:
            cur = {"name": m.group(1), "kind": "model", "studios": [m.group(2)], "blank": False, "eyeballs": []}
            parts.append(cur)
            continue
        m = re.match(r'\$body "([^"]+)" "([^"]+)"', t)
        if m:
            parts.append({"name": m.group(1), "kind": "body", "studios": [m.group(2)], "blank": False})
            cur = None
            continue
        m = re.match(r'\$bodygroup "([^"]+)"', t)
        if m:
            cur = {"name": m.group(1), "kind": "group", "studios": [], "blank": False}
            parts.append(cur)
            continue
        if cur is not None:
            m = re.match(r'studio "([^"]+)"', t)
            if m:
                cur["studios"].append(m.group(1))
            elif t == "blank":
                cur["blank"] = True
            elif t.startswith("eyeball"):
                cur["eyeballs"].append(t)
            elif t == "}":
                cur = None
    return parts


def build_source(model):
    """Decompile, merge, tag. Returns the parts plus the combined SMD path."""
    out = os.path.join(WORK, model)
    if not os.path.isfile(os.path.join(out, model + ".qc")):
        subprocess.run([sys.executable, os.path.join(CODPORT, "tools", "mdl_decompile.py"),
                        os.path.join(SRC, "models", "characters", model + ".mdl"), WORK], check=True)
    parts = parse_qc(os.path.join(out, model + ".qc"))
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
    return parts, path, combined


def group_name(p, used):
    n = re.sub(r"[^a-z0-9_]", "_", p["name"].lower()) or "part"
    while n in used:
        n += "_"
    used.add(n)
    return n


def write_character(model, parts, combined_path, combined):
    cid = f"ins2_{model}"
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
        name = group_name(p, used)
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
    side = side_of(model)
    cd = [f"{MAT_ROOT}/{side}/face/", f"{MAT_ROOT}/{side}/", f"{MAT_ROOT}/eyes/"]
    bone_names = "\n".join(f'"{k}" = "{v}"' for k, v in BONES.items())
    toml = f"""# Generated by tools\\sets\\make_ins2.py - edit the generator, not this file.
[character]
id       = "{cid}"
body_smd = '{combined_path}'

[model]
modelname = 'tif_factions\\ins2\\{model}.mdl'
body      = "{cid}"
head      = ""
ragdoll   = true

[paths]
output_addon = '{ADDON}'
rig = '{RIG_QCI}'
reference_anim = '{RIG_REF}'
twist_vrd = ''

[package]
ragdoll_phy = '{VB_PHY}'

[qc]
cdmaterials = {json.dumps(cd)}

[body]
smd_prefix = "{cid}_"
rotate_z_deg = 0
rebind = true
rebind_joint_frames = true
rebind_scale_to = "ValveBiped.Bip01_Head1"
keep_bones = []

[[body.merge_bones]]
match = "Bip01"
to = "ValveBiped.Bip01_Pelvis"

[body.bone_names]
{bone_names}

""" + "\n".join(groups)
    path = os.path.join(CODPORT, "characters", cid + ".toml")
    open(path, "w", encoding="utf-8", newline="\n").write(toml)
    json.dump({"parts": parts, "groups": meta}, open(os.path.join(WORK, model, "ins2_meta.json"), "w"), indent=1)
    return cid, meta


def codport(cid, stages):
    r = subprocess.run([sys.executable, os.path.join(CODPORT, "codport.py"), cid, *stages], cwd=CODPORT,
                       capture_output=True, text=True)
    tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-12:])
    if r.returncode:
        raise SystemExit(f"codport {cid} {' '.join(stages)} failed:\n{tail}")
    return r.stdout


def untag_body(cid):
    """Tags off the body stage's SMDs and manifest (materials lower case). Returns the eye SMD path."""
    body = os.path.join(r"K:\jimmyproject\work", cid, "body")
    eye_smd = None
    for f in os.listdir(body):
        if f.endswith(".smd"):
            p = os.path.join(body, f)
            s = smdlib.read(p)
            s.triangles = [(m.split("__", 1)[-1].lower(), vs) for m, vs in s.triangles]
            smdlib.write(s, p, s.triangles)
            if any(m.startswith("eyeball") for m, _ in s.triangles):
                eye_smd = p
    mp = os.path.join(body, "body_manifest.json")
    man = json.load(open(mp))
    fix = lambda L: list(dict.fromkeys(m.split("__", 1)[-1].lower() for m in L))
    for g in man["groups"]:
        g["materials"] = fix(g.get("materials", []))
        for o in g.get("options", []):
            o["materials"] = fix(o.get("materials", []))
    json.dump(man, open(mp, "w"), indent=1)
    return eye_smd


def eye_centres(eye_smd):
    s = smdlib.read(eye_smd)
    acc = {}
    for m, vs in s.triangles:
        for v in vs:
            a = acc.setdefault(m, [0.0, 0.0, 0.0, 0, [1e9, -1e9]])
            a[0] += v.pos[0]; a[1] += v.pos[1]; a[2] += v.pos[2]; a[3] += 1
            a[4] = [min(a[4][0], v.pos[0]), max(a[4][1], v.pos[0])]
    out = {}
    for m, a in acc.items():
        out[m] = ((a[0] / a[3], a[1] / a[3], a[2] / a[3]), a[4][1] - a[4][0])
    return out


def fix_qc(cid, meta, eye_smd):
    qcdir = os.path.join(r"K:\jimmyproject\work", cid, "qc")
    qc = [f for f in os.listdir(qcdir) if f.endswith(".qc")][0]
    p = os.path.join(qcdir, qc)
    t = open(p, encoding="utf-8").read()
    # blank only where INS2 had one (codport adds one to every group)
    for g in meta:
        if g.get("eyes") or g.get("empty"):
            continue
        if not g.get("blank"):
            t = re.sub(r'(\$bodygroup "%s"\s*\{[^}]*?)\n\s*blank\s*\n' % re.escape(g["name"]), r"\1\n", t)
    # the eye group -> $model with eyeballs
    m = re.search(r'\$bodygroup "eyes"\s*\{\s*studio "([^"]+)"[^}]*\}', t)
    if m and eye_smd:
        c = eye_centres(eye_smd)
        lines = []
        for mat, label in (("eyeball_r", "eye_right"), ("eyeball_l", "eye_left")):
            if mat in c:
                (x, y, z), d = c[mat]
                lines.append(f'\teyeball "{label}" "ValveBiped.Bip01_Head1" {x:.4f} {y:.4f} {z:.4f} "{mat}" '
                             f'{max(0.6, d):.3f} {1 if mat == "eyeball_r" else -1} "iris_unused" 0.55')
        t = t[:m.start()] + f'$model "eyes" "{m.group(1)}" {{\n' + "\n".join(lines) + "\n}" + t[m.end():]
    open(p, "w", encoding="utf-8", newline="\n").write(t)


def main(argv):
    want = [a for a in argv if not a.startswith("--")] or MODELS
    stages = ["body", "qc", "compile", "package"]
    for a in argv:
        if a.startswith("--stages="):
            stages = a.split("=", 1)[1].split(",")
    if "--no-materials" not in argv:
        copy_materials()
    make_host_rig()
    for model in want:
        parts, path, combined = build_source(model)
        cid, meta = write_character(model, parts, path, combined)
        if "body" in stages:
            codport(cid, ["body"])
        eye_smd = untag_body(cid)
        if "qc" in stages:
            codport(cid, ["qc"])
            fix_qc(cid, meta, eye_smd)
        rest = [s for s in stages if s in ("compile", "package")]
        log = codport(cid, rest) if rest else ""
        res = [l for l in log.splitlines() if "materials resolve" in l or "WARNING" in l or "ragdoll" in l]
        print(f"{model:24} {cid:30} " + " | ".join(r.strip() for r in res))


if __name__ == "__main__":
    main(sys.argv[1:])
