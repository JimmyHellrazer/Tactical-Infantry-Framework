"""
TIF gun holds, offline. Three outputs:

1. Which MW19 clips drive the gun bone (j_gun): addons/tif_mw_anims/lua/tif/gta/clips/zz_jgun.lua
   (TIFG_JGUN_UNDRIVEN[source clip] = true). Campaign clips key j_gun fully (the gun's pose in the hand, slung for
   grenades / activities, re-gripped); MP locomotion keys only a fixed rotation and drifting position (unusable).
2. Each baked gun's place on j_gun: the model origin is at j_gun * [C | t], C fixed (the MW world models hang
   upside down in their hand frame), t least-squares so the gun's own tag_ik_loc_ri / _le land on the clip's hands
   over campaign frames where j_gun is the gun.
3. Each gun's MW19 left-hand finger pose (mp_fingers_<gun>[_grip variant]_l), retargeted onto the ValveBiped
   hand: local rotations of the L finger bones.
(2) and (3) go to build/<id>_hold.json, read by gun_compile.py (--lua-only) into SWEP.TIFBaked.

Usage: gun_holds.py   (all guns in data/tif_gunbake)
       gun_holds.py <id> ...   (only those guns' holds; the clip tables are left as they are)
       gun_holds.py --clips <role pattern>[,...]   (only those clips' gun tables, merged into the existing ones)
"""
import fnmatch
import glob
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "anims"))
import cod_anim_prep as prep  # noqa: E402
import cod_to_breen as c2b  # noqa: E402
import tif_mw_build as tb  # noqa: E402

ADDONS = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
DATA = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\tif_gunbake"
SRC = "K:/duglastakedown"
SRC22 = ("K:/mw22 anims 2/xanims", "K:/mw22 anims")
BUILD = r"K:\jimmyproject\tif_mw\build"
OUT = r"K:\jimmyproject\tif_guns\build"
# (TIF 0.37.0: the MW anims live in the base addon)
CLIPS_DIR = os.path.join(ADDONS, r"tactical_infantry_framework\lua\tif\gta\clips")
CLIPS_LUA = os.path.join(CLIPS_DIR, "mw_male.lua")


def read_clips():
    names = sorted(f for f in os.listdir(CLIPS_DIR) if f.startswith("mw_male_p") and f.endswith(".lua"))
    if not names:
        return open(CLIPS_LUA, encoding="utf-8").read()
    return "\n".join(open(os.path.join(CLIPS_DIR, n), encoding="utf-8").read() for n in names)


JGUN_LUA = os.path.join(ADDONS, r"tactical_infantry_framework\lua\tif\gta\clips\zz_jgun.lua")
C = np.array([[1, 0, 0], [0, -1, 0], [0, 0, -1]], float)
L_FINGERS = ["ValveBiped.Bip01_L_Finger0", "ValveBiped.Bip01_L_Finger01", "ValveBiped.Bip01_L_Finger02",
             "ValveBiped.Bip01_L_Finger1", "ValveBiped.Bip01_L_Finger11", "ValveBiped.Bip01_L_Finger12",
             "ValveBiped.Bip01_L_Finger2", "ValveBiped.Bip01_L_Finger21", "ValveBiped.Bip01_L_Finger22",
             "ValveBiped.Bip01_L_Finger3", "ValveBiped.Bip01_L_Finger31", "ValveBiped.Bip01_L_Finger32",
             "ValveBiped.Bip01_L_Finger4", "ValveBiped.Bip01_L_Finger41", "ValveBiped.Bip01_L_Finger42"]


def rt(rot, pos):
    m = np.eye(4)
    m[:3, :3] = rot
    m[:3, 3] = pos
    return m


# 1. j_gun driven or not, per source clip ------------------------------------------------------------------------
# Rifle <-> pistol switches (mw_draw_*): j_gun carries the other gun for part of the clip.
SWITCH = re.compile(r"_to_pistol$|pistol_to_ar$|_rpg_drop_to_exp_stand(_pstl)?$")
MP_UNUSABLE = re.compile(r"^sdr_mp_laststand_")


def src_file(name):
    p = os.path.join(SRC, name + ".seanim")
    if os.path.exists(p):
        return p
    for d in SRC22:
        q = os.path.join(d, name + ".seanim")
        if os.path.exists(q):
            with open(q, "rb") as f:
                if f.read(6) == b"SEAnim":
                    return q
    return None


def chain_gun_world(a, w, idx, fr):
    fit = prep.AI_CHAIN_GUN
    gb, ab = a["bones"]["j_gun"], a["bones"]["j_gun_adjust"]
    ra = np.array(prep.quat_to_matrix(prep.sample_keys(ab["rot"], fr, prep.slerp)))
    rg = np.array(prep.quat_to_matrix(prep.sample_keys(gb["rot"], fr, prep.slerp))) if gb.get("rot") else np.eye(3)
    off = prep.sample_keys(gb["loc"], fr, prep.vlerp) if gb.get("loc") else [0.0, 0.0, 0.0]
    P = rt(np.array(w[idx[fit["parent"]]][0]), np.array(w[idx[fit["parent"]]][1]))
    A = rt(ra, np.array(fit["rest_adjust"], float))
    G = rt(rg, np.array([fit["rest_gun"][k] + off[k] * prep.CM_TO_INCH for k in range(3)]))
    return P @ A @ G


ROW_RE = re.compile(r'\["([^"]+)"\] = \{ seq = "[^"]*", (?:ub = "[^"]*", )?from = "([^"]+)"')


def classify_names(froms, stored=None):
    undriven = []
    for name in froms:
        p = src_file(name)
        if not p:
            continue
        a = prep.read_seanim(p)
        chain = bool(prep.AI_CHAIN_GUN) and prep.is_chain_gun(a)
        g = a["bones"].get("j_gun", {})
        rot, loc = len(g.get("rot", [])), len(g.get("loc", []))
        if not g or (rot <= 1 and not chain and (loc > 1 or not p.startswith(SRC))) or SWITCH.search(name) or MP_UNUSABLE.search(name):
            undriven.append(name)
    hold = hold_curves([n for n in froms if n not in undriven], stored)
    return undriven, hold


def hold_line(n, e):
    return 'H["%s"] = { a = { %s }, r = { %s }, o = { %s } }\n' % (
        n, ", ".join("%.4f" % x for x in e["a"]), ", ".join("%.2f" % x for x in e["r"]),
        ", ".join("%.2f" % x for x in e.get("o", [])))


def write_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def write_tables(undriven, lines):
    head = ("-- Generated by tif_guns/gun_holds.py: MW19 clips whose gun bone (j_gun) isn't usable (MP locomotion:\n"
            "-- a fixed rotation and drifting position). TIF holds the gun from the hand on these (cl_body).\n"
            "TIFG_JGUN_UNDRIVEN = {\n")
    body = "".join('\t["%s"] = true,\n' % n for n in sorted(undriven))
    tail = ("}\n"
            "-- Where the clip moves the gun in / out of the right hand: r = 0..1 every 3rd frame, a = the hand in the\n"
            "-- gun bone's frame where it holds the gun (gun = j_gun * a there). Unlisted clips: gun in the hand.\n"
            "-- (In parts, zz_jgun_h<i>.lua, loaded after this file: one 0.9 MB table didn't reach clients, TIF 0.35.3.)\n"
            "TIFG_JGUN_HOLD = {}\n")
    folder = os.path.dirname(JGUN_LUA)
    names = sorted(lines)
    parts = []
    for p in range(0, len(names), HOLD_PART):
        text = ("-- Generated by tif_guns/gun_holds.py (TIFG_JGUN_HOLD, part).\n"
                "TIFG_JGUN_HOLD = TIFG_JGUN_HOLD or {}\n"
                "local H = TIFG_JGUN_HOLD\n") + "".join(lines[n] for n in names[p:p + HOLD_PART])
        parts.append(text)
    write_atomic(JGUN_LUA, head + body + tail)
    keep = set()
    for i, text in enumerate(parts, start=1):
        path = os.path.join(folder, "zz_jgun_h%02d.lua" % i)
        keep.add(os.path.normcase(path))
        write_atomic(path, text)
    for old in glob.glob(os.path.join(folder, "zz_jgun_h*.lua")):
        if os.path.normcase(old) not in keep:
            os.remove(old)


def read_tables():
    undriven = re.findall(r'^\t\["([^"]+)"\] = true,$', open(JGUN_LUA, encoding="utf-8").read(), re.M)
    lines = {}
    folder = os.path.dirname(JGUN_LUA)
    for path in sorted(glob.glob(os.path.join(folder, "zz_jgun_h*.lua"))):
        for line in open(path, encoding="utf-8").read().splitlines():
            m = re.match(r'^H\["([^"]+)"\] = ', line)
            if m:
                lines[m.group(1)] = line + "\n"
    return undriven, lines


def classify():
    text = read_clips()
    froms = sorted(set(re.findall(r'from = "([^"]+)"', text)))
    undriven, hold = classify_names(froms)
    write_tables(undriven, {n: hold_line(n, e) for n, e in hold.items()})
    return len(froms), len(undriven), len(hold)


def classify_clips(patterns):
    rows = ROW_RE.findall(read_clips())
    roles = [(r, src) for r, src in rows if any(fnmatch.fnmatch(r, p) for p in patterns)]
    srcs = sorted({src for _, src in roles})
    undriven, lines = read_tables()
    if not os.path.exists(SPOTS_JSON):
        print("no %s yet: run gun_holds.py once without arguments first" % SPOTS_JSON)
        return 0, 0, 0, 0, False
    new_und, hold = classify_names(srcs, json.load(open(SPOTS_JSON)))
    undriven = [n for n in undriven if n not in srcs] + new_und
    for n in srcs:
        lines.pop(n, None)
    for n, e in hold.items():
        lines[n] = hold_line(n, e)
    write_tables(undriven, lines)
    low = any(GUNLOW_ROLES.search(r) for r, _ in roles)
    return len(roles), len(srcs), len(new_und), len(hold), low


HOLD_PART = 60


CHAIN_R = ["ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2",
           "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_R_Clavicle", "ValveBiped.Bip01_R_UpperArm",
           "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand", "j_gun"]
CHAIN_L = ["ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm",
           "ValveBiped.Bip01_L_Hand"]
REF_GUN = "akm"


def chain_world(smd, idx, frame):
    """World matrices of the right-arm chain (+ j_gun) and the left arm, from a built clip's frame (local SMD)."""
    bones = smd.frames[frame][1]
    out = {}

    def local(n):
        r, t = prep.to_rt(bones[idx[n]])
        return rt(np.array(r), np.array(t))
    m = np.eye(4)
    for n in CHAIN_R:
        m = (m @ local(n)) if n != "j_gun" else (out["ValveBiped.Bip01_R_Hand"] @ local(n))
        out[n] = m
    m = out["ValveBiped.Bip01_Spine4"]
    for n in CHAIN_L:
        m = m @ local(n)
        out[n] = m
    return out


_codbody = None


def cod_wrist_in_jgun(name):
    """The right wrist's position in j_gun's frame, every frame, from the raw MW19 clip on the CoD skeleton (no
    retarget). MW19 keeps it fixed while the hand holds the gun (within ~1 unit in aim, CQB, alert and patrol clips,
    2026-11-12); it moves only where the hand really lets go. None if the clip or bones are missing."""
    global _codbody
    p = src_file(name)
    if not p:
        return None
    if _codbody is None:
        _codbody = prep.read_smd(COD_BODY)
    a = prep.read_seanim(p)
    if not a["bones"].get("j_gun", {}).get("rot"):
        return None
    cod, _ = prep.seanim_to_smd(a, _codbody, {}, False, prep.CM_TO_INCH, inplace=True)
    prep.fill_frames(cod)
    idx = {n: i for i, (n, _) in enumerate(cod.nodes)}
    if "j_gun" not in idx or "j_wrist_ri" not in idx:
        return None
    chain = bool(prep.AI_CHAIN_GUN) and prep.is_chain_gun(a) and prep.AI_CHAIN_GUN["parent"] in idx
    out, mats = [], []
    for fr, (_, bones) in enumerate(cod.frames):
        loc = {i: prep.to_rt(v) for i, v in bones.items()}
        w = c2b.world_pose(cod.nodes, loc)
        if chain:
            J = chain_gun_world(a, w, idx, fr)
        else:
            J = rt(np.array(w[idx["j_gun"]][0]), np.array(w[idx["j_gun"]][1]))
        out.append((np.linalg.inv(J) @ np.append(w[idx["j_wrist_ri"]][1], 1.0))[:3])
        mats.append(J)
    # (2026-11-20) a clip baked with end=N (seq "<source>_e<N>", tif_mw_build trim_end) plays only frames 0..N: the
    # curve must end there too, or its r timing stretches over frames the game never plays (MW19 sledge breach, f90/113)
    n_end = trim_ends().get(name)
    if n_end is not None:
        out, mats = out[:n_end + 1], mats[:n_end + 1]
    # (2026-11-20) clips from scripted scenes (zd30c sledge breach, hostage / pilot idles) stand far from the scene
    # origin, and clips that travel (vehicle get-ins, civilian panic runs) move away from it; our bakes are in place.
    # j_gun is taken relative to tag_origin on each frame (identity on the AI clips): the slung gun's spot ("o") sat
    # 200+ units off the body on those before. Checked (scratchpad root_pick.py): the raw wrist lands within 2-8
    # units of the built hand this way on the sledge, a get-in, a panic run, a hostage idle and an AI reload.
    if "tag_origin" in idx:
        ti = idx["tag_origin"]
        for k, (_, bones) in enumerate(cod.frames[:len(mats)]):
            w = c2b.world_pose(cod.nodes, {i: prep.to_rt(v) for i, v in bones.items()})
            mats[k] = np.linalg.inv(rt(np.array(w[ti][0]), np.array(w[ti][1]))) @ mats[k]
    _jmats[name] = mats
    return out


_trim_ends = None


def trim_ends():
    """source clip -> last frame, for clips baked with end=N (their clip-table seq ends in _e<N>)."""
    global _trim_ends
    if _trim_ends is None:
        text = read_clips()
        _trim_ends = {m.group(2): int(m.group(3)) for m in
                      re.finditer(r'seq = "((\w+?)_e(\d+))", from = "\2"', text)}
    return _trim_ends


_jmats = {}
# Raw CoD clip space -> our built clips' space (same origin, horizontal axes turned: wrists agree within ~1 unit).
COD_TO_BUILT = np.array([[0, 1, 0], [-1, 0, 0], [0, 0, 1]], float)


COD_BODY = r"K:\jimmyproject\Alex Desert\body_hero_alex_desert\body_hero_alex_desert_LOD0.smd"


SPOTS_JSON = os.path.join(OUT, "grip_spots.json")


def hold_curves(names, stored=None):
    """Per clip: where the right hand lets go of the gun (r 0..1 every 3rd frame) and a = the hand in j_gun's frame
    (built clip) at a frame where it holds. Measured on the raw MW19 clips (cod_wrist_in_jgun) against each weapon
    family's grip spot (the median wrist spot over the family's clips): a clip can start off the grip (the RPG
    reload begins with the right hand at the rocket), so its own first frame isn't the reference."""
    qs = {}
    for n in names:
        q = cod_wrist_in_jgun(n)
        if q:
            qs[n] = q
    spots = {k: np.array(v) for k, v in (stored or {}).items()}
    for fam in set(family(n) for n in qs) - set(spots):
        if stored is not None:
            print("no stored grip spot for family %s: measured on these clips only" % fam)
        # From the family's aims / idles / moves where it has any: the hand is on the grip there (the RPG's few clips
        # are mostly reloads, which start with the hand at the rocket).
        fam_n = [n for n in qs if family(n) == fam]
        steady = [n for n in fam_n if re.search(r"aim|idle|walk|run", n) and not re.search(r"reload|grenade", n)]
        firsts = np.array([qs[n][0] for n in (steady or fam_n)])
        spots[fam] = np.median(firsts, axis=0)
    print("grip spots (wrist in j_gun, raw MW19):", {k: np.round(v, 1).tolist() for k, v in spots.items()})
    if stored is None:
        os.makedirs(OUT, exist_ok=True)
        json.dump({k: [float(x) for x in v] for k, v in spots.items()}, open(SPOTS_JSON, "w"), indent=1)
    out = {}
    for n, q in qs.items():
        # Weapon switches: the hand holds one gun while j_gun carries the other (ar_to_pistol parks j_gun at the hip
        # with the pistol in hand). Classified undriven: the gun stays in the hand (classify()).
        if SWITCH.search(n):
            continue
        loc = jgun_locals(n)
        if not loc:
            continue
        spot = spots[family(n)]
        dev = [float(np.linalg.norm(x - spot)) for x in q]
        # Held frame: the closest to the grip spot (first one on ties).
        held = int(np.argmin(dev))
        frames = list(range(0, len(loc), 3))
        if (len(loc) - 1) % 3:
            frames.append(len(loc) - 1)
        r = [min(1.0, max(0.0, (dev[min(fr, len(q) - 1)] - 2.0) / 3.0)) for fr in frames]
        # Activity loops (phone, smoking, water) spend the whole clip with the gun put away: the grip is the one
        # their _start clip begins with, and the gun follows the gun bone throughout.
        if re.search(r"_idle_stand_(cellphone|smoking|waterbottle)$", n):
            start = jgun_locals(n + "_start")
            if start:
                loc, held = start, 0
                r = [1.0] * len(r)
        if max(r) < 0.05:
            continue
        ra, ta = loc[min(held, len(loc) - 1)]
        inv_r = ra.T
        inv_t = -inv_r @ ta
        # Where the gun is while let go: its origin (the wrist spot on j_gun) in the clip's own space, from the raw
        # clip (the built j_gun's position is off: our retarget keeps its offset from the shoulder).
        o = []
        J = _jmats.get(n) or []
        for fr in frames:
            if not J:
                break
            Jm = J[min(fr, len(J) - 1)]
            p = COD_TO_BUILT @ (Jm[:3, :3] @ spot + Jm[:3, 3])
            o.extend(round(float(x), 2) for x in p)
        out[n] = {"a": [float(x) for x in (inv_r[0, 0], inv_r[0, 1], inv_r[0, 2], inv_t[0], inv_r[1, 0], inv_r[1, 1],
                                           inv_r[1, 2], inv_t[1], inv_r[2, 0], inv_r[2, 1], inv_r[2, 2], inv_t[2])],
                  "r": r, "o": o}
    return out

def hold_curves_by_grip(names):
    """(Superseded 2026-11-12: relied on a calibrated gun-bone offset that only fits cover clips.)"""
    meta = json.load(open(os.path.join(DATA, REF_GUN + ".json")))
    hp = json.load(open(os.path.join(OUT, REF_GUN + "_hold.json"))).get("jgun", {}).get("t")
    if not hp:
        return {}
    X = rt(C, np.array(hp))
    b = meta["parts"][0]["bones"]
    ple = np.append(b["tag_ik_loc_le"]["pos"], 1.0)
    out = {}
    for n in names:
        hits = glob.glob(os.path.join(BUILD, "*", n + ".smd"))
        if not hits:
            continue
        smd = prep.read_smd(hits[0])
        prep.fill_frames(smd)
        idx = {nm: i for i, (nm, _) in enumerate(smd.nodes)}
        if "j_gun" not in idx or any(c not in idx for c in CHAIN_R[:-1] + CHAIN_L):
            continue
        frames = list(range(0, len(smd.frames), 3))
        if (len(smd.frames) - 1) % 3:
            frames.append(len(smd.frames) - 1)
        dR, dL, rel = [], [], []
        for fr in frames:
            w = chain_world(smd, idx, fr)
            g = w["j_gun"] @ X
            hand = w["ValveBiped.Bip01_R_Hand"]
            dR.append(float(np.linalg.norm(g[:3, 3] - hand[:3, 3])))
            dL.append(float(np.linalg.norm((g @ ple)[:3] - w["ValveBiped.Bip01_L_Hand"][:3, 3])))
            rel.append(np.linalg.inv(hand) @ g)  # the gun relative to the hand
        # A rigid carry: the gun doesn't move in the hand over the clip (patrol carry's 13-unit offset).
        rigid = max(np.linalg.norm(r[:3, 3] - rel[0][:3, 3]) for r in rel) < 3
        j, rik = [], []
        for d_r, d_l in zip(dR, dL):
            on_grip = min(1.0, max(0.0, (10 - d_r) / 4))        # <=6 on the grip, >=10 off
            left_on = min(1.0, max(0.0, (8 - d_l) / 3))          # left hand on the handguard
            carry = 1.0 if (rigid and d_r < 18 and on_grip == 0 and left_on == 0) else 0.0
            j.append(1.0 - carry)
            rik.append(on_grip)
        if min(j) > 0.99 and min(rik) > 0.99:
            continue
        out[n] = {"j": j, "rik": rik}
    return out


def family(name):
    """Clips that hold the gun the same way (j_gun's in-hand spot differs between these sets)."""
    if "rpg" in name:
        return "rpg"
    if "pistol" in name or "pstl" in name:
        return "pistol"
    if "lmg" in name:
        return "lmg"
    if "shotgun" in name:
        return "shotgun"
    if name.startswith("reb_"):
        return "reb"
    return "base"


def jgun_locals(name):
    """j_gun's local (rot 3x3, pos) relative to the right hand, every frame of a built clip, or None."""
    # (a clip baked with end=N is built as <name>_e<N>.smd; a stale untrimmed bake may sit beside it)
    n_end = trim_ends().get(name)
    hits = glob.glob(os.path.join(BUILD, "*", (name + "_e%d" % n_end if n_end is not None else name) + ".smd"))
    if not hits:
        return None
    smd = prep.read_smd(hits[0])
    prep.fill_frames(smd)
    idx = {n: i for i, (n, _) in enumerate(smd.nodes)}
    if "j_gun" not in idx:
        return None
    j = idx["j_gun"]
    out = []
    for _, bones in smd.frames:
        r, t = prep.to_rt(bones[j])
        out.append((np.array(r), np.array(t)))
    return out


def ang_between(a, b):
    c = (np.trace(a.T @ b) - 1) / 2
    return float(np.degrees(np.arccos(max(-1.0, min(1.0, c)))))


def release_curves(names):
    data = {}
    for n in names:
        loc = jgun_locals(n)
        if loc:
            data[n] = loc
    # In-hand spot per family: the median first-frame position (and that clip's rotation).
    anchors = {}
    for fam in set(family(n) for n in data):
        firsts = [(n, data[n][0]) for n in data if family(n) == fam]
        med = np.median([f[1][1] for f in firsts], axis=0)
        best = min(firsts, key=lambda f: np.linalg.norm(f[1][1] - med))
        anchors[fam] = best[1]

    def dev(x, a):
        return np.linalg.norm(x[1] - a[1]) + 0.12 * ang_between(x[0], a[0])

    out = {}
    for n, loc in data.items():
        fa = anchors[family(n)]
        # The clip's own in-hand spot: whichever end is closer to the family's (a fidget or a sub-set holding the
        # gun a little differently); the family's when both ends are off the hand (a clip spent slung).
        ends = [loc[0], loc[-1]]
        a = min(ends, key=lambda x: dev(x, fa))
        if dev(a, fa) > 10:
            a = fa
        r = [min(1.0, max(0.0, (dev(x, a) - 4) / 6)) for x in loc[::3]]
        if loc and (len(loc) - 1) % 3:
            r.append(min(1.0, max(0.0, (dev(loc[-1], a) - 4) / 6)))
        if max(r) < 0.05:
            continue
        inv_r = a[0].T
        inv_t = -inv_r @ a[1]
        out[n] = {"a": [inv_r[0, 0], inv_r[0, 1], inv_r[0, 2], inv_t[0], inv_r[1, 0], inv_r[1, 1], inv_r[1, 2], inv_t[1],
                        inv_r[2, 0], inv_r[2, 1], inv_r[2, 2], inv_t[2]], "r": r}
    return out


# 2. hands in j_gun's frame on campaign frames ---------------------------------------------------------------------
REF_R = np.array([1.32, -3.11, -9.58])


def hand_samples():
    files = (glob.glob(os.path.join(BUILD, "cover", "sdr_com_cover_*idle*.smd"))[:8] +
             glob.glob(os.path.join(BUILD, "cover", "sdr_com_cover_*aim_5.smd"))[:4] +
             glob.glob(os.path.join(BUILD, "passive", "reb_stl_alert_idle01.smd")) +
             glob.glob(os.path.join(BUILD, "weapon", "sdr_com_exposed_reload01.smd")))
    out = []
    for p in files:
        smd = prep.read_smd(p)
        prep.fill_frames(smd)
        idx = {n: i for i, (n, _) in enumerate(smd.nodes)}
        if "j_gun" not in idx:
            continue
        for fr in (0, len(smd.frames) // 3):
            loc = {i: prep.to_rt(v) for i, v in smd.frames[fr][1].items()}
            w = c2b.world_pose(smd.nodes, loc)
            Ji = np.linalg.inv(rt(np.array(w[idx["j_gun"]][0]), np.array(w[idx["j_gun"]][1])))
            qr = (Ji @ np.append(w[idx["ValveBiped.Bip01_R_Hand"]][1], 1))[:3]
            ql = (Ji @ np.append(w[idx["ValveBiped.Bip01_L_Hand"]][1], 1))[:3]
            if np.linalg.norm(qr - REF_R) < 4:  # j_gun is the gun on this frame
                out.append((qr, ql))
    return out


def place(meta, samples):
    b = meta["parts"][0].get("bones") or {}
    if "tag_ik_loc_ri" not in b:
        return None
    pri = np.array(b["tag_ik_loc_ri"]["pos"])
    ple = np.array(b["tag_ik_loc_le"]["pos"]) if "tag_ik_loc_le" in b else None
    diffs = [s[0] - C @ pri for s in samples]
    if ple is not None:
        diffs += [s[1] - C @ ple for s in samples]
    t = np.mean(diffs, axis=0)
    err = np.mean([np.linalg.norm(C @ pri + t - s[0]) for s in samples])
    return t, err


# 3. finger poses ------------------------------------------------------------------------------------------------
POSES = set(os.path.basename(f)[11:-7] for f in glob.glob(SRC + "/mp_fingers_*.seanim"))
# MW19 names them several ways: ar_akilo47_vertgrip_l, sm_mpapa7_gripvert_l, lm_pkilo_l_gripvert, ar_mike4_l_grip
# (the M4's vertical grip; until 2026-11-12 only the first two were tried, so the M4 borrowed the AK's).
GRIP_SUFFIX = {"vert": ["_vertgrip_l", "_gripvert_l", "_l_gripvert", "_l_grip"],
               "angled": ["_angledgrip_l", "_gripang_l", "_l_gripang"], "": ["_l"]}


INTEGRATED_VERTGRIP = ("oden",)


def finger_pose_name(meta):
    name = meta["swep"][3:]
    atts = " ".join(meta.get("atts_asked") or [])
    # (The Oden / ASh-12 has its vertical foregrip built in: no attachment, but the left hand goes on it.)
    grip = "vert" if ("vertgrip" in atts or meta["id"] in INTEGRATED_VERTGRIP) else ("angled" if "angledgrip" in atts else "")
    # (POSES names keep their "_l": ar_akilo47_l, ar_akilo47_vertgrip_l)
    # The gun's own pose for its grip, then the AK's pose for that grip (a foregrip needs a foregrip hand), then
    # the gun's plain handguard grip, then the AK's.
    order = [(n, s) for s in GRIP_SUFFIX[grip] for n in [name]] + [("akilo47", s) for s in GRIP_SUFFIX[grip]]
    order += [(name, "_l"), ("akilo47", "_l")]
    for n, suf in order:
        for prefix in ("ar_", "sm_", "lm_", "sn_", "sh_"):
            if prefix + n + suf in POSES:
                return prefix + n + suf
    return None


_ctx = None


def finger_rotations(pose):
    global _ctx
    _ctx = _ctx or tb.Ctx({"SOURCE": SRC})
    base = prep.read_seanim(SRC + "/sdr_com_exposed_reload01.seanim")
    fp = prep.read_seanim(SRC + "/mp_fingers_%s.seanim" % pose)
    anim = {"fps": base["fps"], "frames": 1, "looped": False, "type": base["type"], "notes": [], "bones": {}}
    for bn, b in base["bones"].items():
        anim["bones"][bn] = {k: [(0, prep.sample_keys(v, 0, prep.slerp if k == "rot" else prep.vlerp))]
                             for k, v in b.items() if v and k in ("rot", "loc")}
    for bn, b in fp["bones"].items():
        if bn.startswith(("j_index_le", "j_mid_le", "j_ring_le", "j_pinky_le", "j_thumb_le", "j_meta")) and b.get("rot"):
            anim["bones"][bn] = dict(anim["bones"].get(bn, {}), rot=[(0, b["rot"][0][1])])
    cod, _ = prep.seanim_to_smd(anim, _ctx.src_body, _ctx.mapping, True, prep.CM_TO_INCH, inplace=True)
    res = c2b.retarget(cod, _ctx.src_rest_w, _ctx.tgt, _ctx.tgt_rest_local, _ctx.tgt_rest_w, 1.0, _ctx.offsets)
    prep.fill_frames(res)
    idx = {n: i for i, (n, _) in enumerate(res.nodes)}
    out = {}
    for bn in L_FINGERS:
        if bn in idx:
            r, _ = prep.to_rt(res.frames[0][1][idx[bn]])
            out[bn] = [round(float(x), 5) for row in r for x in row]
    return out


# Left-hand spot for guns without MW19's tag_ik_loc_le (model space after studiomdl's turn: forward +y, left +x,
# up -z): where the raw MW19 clips put the left wrist relative to the right one, in the gun's frame (scratchpad
# rpgdir.py, 2026-11-12: RPG aim 7.7 ahead, 7.0 left; the AK's measured the same way lands within 2-3 of its tag).
GRIP_L_FALLBACK = {"rpg7": [7.0, 7.7, 0.3]}


GUNLOW_LUA = os.path.join(os.path.dirname(JGUN_LUA), "zz_gunlow.lua")
GUNLOW_PITCH = -30.0
GUNLOW_ROLES = re.compile(r"^mwt_(?:stop|start)_")


def gun_low():
    text = read_clips()
    rows = re.findall(r'\["([^"]+)"\] = \{ seq = "[^"]*", (?:ub = "[^"]*", )?from = "([^"]+)"', text)
    out = {}
    for role, src in rows:
        if not GUNLOW_ROLES.search(role):
            continue
        if src not in _jmats:
            cod_wrist_in_jgun(src)
        mats = _jmats.get(src)
        if not mats or len(mats) < 2:
            continue
        low = []
        for i, J in enumerate(mats):
            x = J[:3, 0] / max(1e-6, float(np.linalg.norm(J[:3, 0])))
            if np.degrees(np.arcsin(np.clip(x[2], -1, 1))) < GUNLOW_PITCH:
                low.append(i)
        if low:
            n = len(mats) - 1
            out[role] = (max(0.0, (low[0] - 1) / n), min(1.0, (low[-1] + 2) / n))
    text = "TIFG_GUN_LOW = {\n" + "".join('\t["%s"] = { %.3f, %.3f },\n' % (role, out[role][0], out[role][1])
                                        for role in sorted(out)) + "}\n"
    write_atomic(GUNLOW_LUA, text)
    return len(out)


def stored_long_t():
    ts = []
    for hf in glob.glob(os.path.join(OUT, "*_hold.json")):
        gid = os.path.basename(hf)[:-len("_hold.json")]
        mf = os.path.join(DATA, gid + ".json")
        if not os.path.exists(mf) or json.load(open(mf)).get("kind") == "pistol":
            continue
        t = json.load(open(hf)).get("jgun", {}).get("t")
        if t:
            ts.append(t)
    return np.mean(ts, axis=0) if ts else None


def main():
    if "--clips" in sys.argv:
        i = sys.argv.index("--clips")
        pats = sys.argv[i + 1].split(",") if i + 1 < len(sys.argv) else []
        if not pats:
            print("usage: gun_holds.py --clips <role pattern>[,<pattern>...]")
            return
        n, ns, u, h, low = classify_clips(pats)
        print("clips: %d roles from %d sources, %d with an unusable gun bone, %d where the hand lets go -> %s" % (n, ns, u, h, JGUN_LUA))
        if low:
            print("start / stop clips with the gun lowered: %d -> %s" % (gun_low(), GUNLOW_LUA))
        return
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not only:
        n, u, rl = classify()
        print("clips: %d sources, %d with an unusable gun bone, %d where the right hand lets go -> %s" % (n, u, rl, JGUN_LUA))
        print("start / stop clips with the gun lowered: %d -> %s" % (gun_low(), GUNLOW_LUA))
    samples = hand_samples()
    print("campaign frames for the grip:", len(samples))
    cache = {}
    metas = [json.load(open(jf)) for jf in sorted(glob.glob(os.path.join(DATA, "*.json"))) if not jf.endswith("_sounds.json")]
    if only:
        metas = [m for m in metas if m["id"] in only]
        missing = sorted(set(only) - {m["id"] for m in metas})
        if missing:
            print("no export for:", ", ".join(missing))
    placed = {m["id"]: place(m, samples) for m in metas}
    longs = [p[0] for m in metas if m.get("kind") != "pistol" for p in [placed[m["id"]]] if p]
    long_t = np.mean(longs, axis=0) if not only and longs else stored_long_t()
    for meta in metas:
        gid = meta["id"]
        hold = {}
        p = placed[gid]
        if not p and meta.get("kind") != "pistol":
            p = (long_t, -1.0)
        if p:
            hold["jgun"] = {"t": [round(float(x), 4) for x in p[0]]}
        pose = finger_pose_name(meta) if meta.get("kind") != "pistol" else None
        if pose:
            if pose not in cache:
                cache[pose] = finger_rotations(pose)
            hold["fingers"] = cache[pose]
            hold["fingerPose"] = pose
        if gid in GRIP_L_FALLBACK:
            hold["gripL"] = GRIP_L_FALLBACK[gid]
        json.dump(hold, open(os.path.join(OUT, gid + "_hold.json"), "w"))
        print("%-16s grip err %s  fingers %s" % (gid, "%.2f" % p[1] if p else "-", pose or "-"))


if __name__ == "__main__":
    main()
