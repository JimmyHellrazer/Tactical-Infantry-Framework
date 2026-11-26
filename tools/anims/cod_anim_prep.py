"""
Batch-prepare Call of Duty animations for a ValveBiped-renamed CoD rig.

Point it at a folder of animations (.smd and/or .seanim) and a target body SMD. For every file it:
  * renames bones using the same bone_mapping dict as the Blender rename script
  * .seanim: converts straight to an SMD on the body's skeleton (hierarchy and rest pose come from the body,
    tag_origin root motion is folded into the pelvis); --seanim-mode rename only renames bones in place
  * .smd: drops bones the target body doesn't have, folding their motion into the children so nothing
    that is kept moves differently -- e.g. tag_origin root motion gets folded into the pelvis
  * reports which target bones the animation drives and which it leaves at rest pose
  * --qc writes a standalone QC (body as reference mesh + one $sequence per converted animation)

Usage:
  python cod_anim_prep.py <anim_folder> --target K:/head2/PlaceHolder_Body.smd
  python cod_anim_prep.py <anim_folder> --target body.smd --match "zd30*" --qc zd30.qc --modelname cod_anims/zd30.mdl
  python cod_anim_prep.py <anim_folder> --target body.smd --out <out_folder> --keep "j_gun*" --keep "tag_weapon*"
  python cod_anim_prep.py <anim_folder> --target body.smd --no-strip     (SMD rename only)

Output mirrors the input folder layout under <anim_folder>_valvebiped (or --out). A report.txt is written there too.
"""

import argparse
import ast
import fnmatch
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MAPPING = os.path.join(HERE, "cod_bone_mapping.py")

# Weapon bones aren't in the body but the SMH baker uses them to animate the gun prop
DEFAULT_KEEP = ["j_gun*", "tag_weapon*", "tag_ik*"]


# ---------------------------------------------------------------- mapping

def load_mapping(path):
    """Pull the bone_mapping dict out of the Blender script without running it (it imports bpy)."""
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "bone_mapping" for t in node.targets):
            return ast.literal_eval(node.value)
    raise ValueError(f"no bone_mapping dict found in {path}")


# ---------------------------------------------------------------- math (Source SMD euler: M = Rz * Ry * Rx)

def euler_to_matrix(x, y, z):
    cx, sx = math.cos(x), math.sin(x)
    cy, sy = math.cos(y), math.sin(y)
    cz, sz = math.cos(z), math.sin(z)
    return [
        [cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx],
        [sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx],
        [-sy, cy * sx, cy * cx],
    ]


def matrix_to_euler(m):
    sy = -m[2][0]
    sy = max(-1.0, min(1.0, sy))
    y = math.asin(sy)
    if abs(math.cos(y)) > 1e-6:
        x = math.atan2(m[2][1], m[2][2])
        z = math.atan2(m[1][0], m[0][0])
    else:  # gimbal lock: fold everything into x
        x = math.atan2(-m[1][2], m[1][1])
        z = 0.0
    return x, y, z


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(a, v):
    return [sum(a[i][k] * v[k] for k in range(3)) for i in range(3)]


def compose(parent, child):
    """(R, t) of child expressed in parent's parent space."""
    pr, pt = parent
    cr, ct = child
    t = mat_vec(pr, ct)
    return mat_mul(pr, cr), [t[0] + pt[0], t[1] + pt[1], t[2] + pt[2]]


def to_rt(vals):
    px, py, pz, rx, ry, rz = vals
    return euler_to_matrix(rx, ry, rz), [px, py, pz]


def from_rt(rt):
    r, t = rt
    x, y, z = matrix_to_euler(r)
    return [t[0], t[1], t[2], x, y, z]


def quat_to_matrix(q):
    x, y, z, w = q
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]


def slerp(a, b, t):
    dot = sum(i * j for i, j in zip(a, b))
    if dot < 0:
        b, dot = [-v for v in b], -dot
    if dot > 0.9995:
        q = [i + (j - i) * t for i, j in zip(a, b)]
    else:
        th = math.acos(dot)
        s = math.sin(th)
        wa, wb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
        q = [i * wa + j * wb for i, j in zip(a, b)]
    n = math.sqrt(sum(v * v for v in q)) or 1.0
    return [v / n for v in q]


def sample_keys(keys, frame, lerp):
    """keys: sorted [(frame, value)]; holds the first/last value outside the keyed range."""
    if frame <= keys[0][0]:
        return keys[0][1]
    if frame >= keys[-1][0]:
        return keys[-1][1]
    lo, hi = 0, len(keys) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if keys[mid][0] <= frame:
            lo = mid
        else:
            hi = mid
    (f0, v0), (f1, v1) = keys[lo], keys[hi]
    return lerp(v0, v1, (frame - f0) / (f1 - f0))


def vlerp(a, b, t):
    return [i + (j - i) * t for i, j in zip(a, b)]


# Weapon bones kept from MW19 3p animations: name -> (CoD parent bone, rest position in parent space).
# The rest isn't in the exported animations (translations are stored relative to it); it was solved by fitting
# the gun so the right hand holds it rigidly across ~110 zd30 animations (rotation tracks j_shoulder_ri to <1 deg).
WEAPON_BONES = {
    "j_gun": ("j_shoulder_ri", [-10.08, 11.23, -0.40]),
}

# MW19 / MWII MULTIPLAYER rig (opt-in: Modern Player Motion sets this; TIF's AI clips keep WEAPON_BONES above).
# The MP gun is a two-bone chain: j_clavicle_ri -> j_gun_adjust (rotation keys) -> j_gun (position keys + rotation).
# Rests fitted 2026-11-24 so the right hand holds the gun rigidly over 449 frames of MP idles / walks / jogs / crouch
# (max 0.08 u, rotation spread 4 deg; the AI-rig reading of the same clips was off by ~24 u and up to 100 deg).
MP_GUN = None
MP_GUN_FIT = {"parent": "j_clavicle_ri", "rest_adjust": [5.77, 0.11, -0.09], "rest_gun": [-20.84, -5.27, -9.46]}
# MWII (iw9_) MP clips: same chain and composition, same adjust rest, gun rest ~18 u elsewhere. Fitted 2026-11-24 over
# 34 MWII rifle / LMG reloads (stand + crouch, 17 guns) + the stand idle pose: gun rotation in the right hand within
# 0-4 deg (belt-fed / bullpup lifts aside), origin within ~0.2-2 u. A clip read with anim["rig"] = "iw9" uses it.
MP_GUN_RIGS = {"iw9": {"parent": "j_clavicle_ri", "rest_adjust": [5.16, 0.04, 0.39], "rest_gun": [-2.86, 1.01, 1.61]}}

# CoD procedural bones the animations have no tracks for (the game computes them at runtime). Each one moves with
# the named bone as if parented to it (weight 1 = fully), keeping its own pivot. Both must share a parent.
# The clavicle helpers sit under Spine4, so without this the shoulder skin stays put when the clavicle moves.
PROC_FOLLOW = {
    "j_proc_lift_clavicle_le": ("ValveBiped.Bip01_L_Clavicle", 1.0),
    "j_proc_lift_clavicle_ri": ("ValveBiped.Bip01_R_Clavicle", 1.0),
}


def mat_to_quat(m):
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        return [(m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s, 0.25 * s]
    if m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        return [0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s, (m[2][1] - m[1][2]) / s]
    if m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        return [(m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s, (m[0][2] - m[2][0]) / s]
    s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
    return [(m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s, (m[1][0] - m[0][1]) / s]


def apply_proc_follow(nodes, rest, bones, driven):
    """bones/rest: {index: [px,py,pz,rx,ry,rz]} local values; driven: indices the animation drives (left alone)."""
    index = {n: i for i, (n, _) in enumerate(nodes)}
    for proc, (lead, w) in PROC_FOLLOW.items():
        pi, ci = index.get(proc), index.get(lead)
        if pi is None or ci is None or pi in driven or nodes[pi][1] != nodes[ci][1]:
            continue
        rc, tc = to_rt(bones[ci])
        rc0, tc0 = to_rt(rest[ci])
        d = mat_mul(rc, [[rc0[j][i] for j in range(3)] for i in range(3)])  # clavicle's turn from rest
        if w < 1:
            d = quat_to_matrix(slerp([0, 0, 0, 1], mat_to_quat(d), w))
        rp0, tp0 = to_rt(rest[pi])
        off = mat_vec(d, [tp0[k] - tc0[k] for k in range(3)])
        t = [tc0[k] + (tc[k] - tc0[k]) * w + off[k] for k in range(3)]
        bones[pi] = from_rt((mat_mul(d, rp0), t))


# Source SMDs (as Crowbar decompiles them, and as studiomdl expects) sit rotated -90 degrees about Z relative
# to CoD model space; only matters for root bones.
COD_TO_SMD = euler_to_matrix(0, 0, -math.pi / 2)
SMD_TO_COD = euler_to_matrix(0, 0, math.pi / 2)


# ---------------------------------------------------------------- SMD

class Smd:
    def __init__(self):
        self.header = []      # lines before "nodes" (version, comments)
        self.nodes = []       # [(name, parent_index)]
        self.frames = []      # [(time, {bone_index: [px,py,pz,rx,ry,rz]})]
        self.tail = []        # raw lines after skeleton (triangles, vertexanimation, ...)

    @property
    def has_mesh(self):
        return any(l.strip() == "triangles" for l in self.tail)


def read_smd(path):
    smd = Smd()
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()

    i, n = 0, len(lines)
    section = None
    frame = None
    while i < n:
        line = lines[i]
        s = line.strip()
        i += 1
        if section is None:
            if s == "nodes":
                section = "nodes"
            elif s == "skeleton":
                section = "skeleton"
            elif s in ("triangles", "vertexanimation"):
                smd.tail = lines[i - 1:]
                break
            else:
                smd.header.append(line)
        elif s == "end":
            section = None
        elif section == "nodes":
            # 12 "bone name" 3
            q1 = s.index('"')
            q2 = s.index('"', q1 + 1)
            name = s[q1 + 1:q2]
            parent = int(s[q2 + 1:].split()[0])
            smd.nodes.append((name, parent))
        elif section == "skeleton":
            parts = s.split()
            if not parts:
                continue
            if parts[0] == "time":
                frame = (int(parts[1]), {})
                smd.frames.append(frame)
            else:
                frame[1][int(parts[0])] = [float(v) for v in parts[1:7]]
    return smd


def write_smd(path, smd):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for l in smd.header:
            f.write(l + "\n")
        f.write("nodes\n")
        for idx, (name, parent) in enumerate(smd.nodes):
            f.write(f'  {idx} "{name}" {parent}\n')
        f.write("end\nskeleton\n")
        for time, bones in smd.frames:
            f.write(f"  time {time}\n")
            for idx in sorted(bones):
                v = bones[idx]
                f.write(f"    {idx} {v[0]:.6f} {v[1]:.6f} {v[2]:.6f} {v[3]:.6f} {v[4]:.6f} {v[5]:.6f}\n")
        f.write("end\n")
        for l in smd.tail:
            f.write(l + "\n")


def fill_frames(smd):
    """SMD frames may omit unchanged bones; make every frame complete by carrying values forward."""
    last = {}
    for idx in range(len(smd.nodes)):
        for _, bones in smd.frames:
            if idx in bones:
                last[idx] = bones[idx]
                break
        else:
            last[idx] = [0.0] * 6
    for _, bones in smd.frames:
        for idx in range(len(smd.nodes)):
            if idx in bones:
                last[idx] = bones[idx]
            else:
                bones[idx] = list(last[idx])


def strip_bones(smd, keep):
    """Remove bones not in `keep`, folding each removed bone's transform into its kept descendants."""
    fill_frames(smd)

    old_nodes = smd.nodes
    new_index = {}
    new_nodes = []
    for idx, (name, _) in enumerate(old_nodes):
        if keep(name):
            new_index[idx] = len(new_nodes)
            new_nodes.append(None)

    # For each kept bone: the chain of removed ancestors between it and its nearest kept ancestor
    chains = {}
    for idx, (name, parent) in enumerate(old_nodes):
        if idx not in new_index:
            continue
        chain = []
        p = parent
        while p != -1 and p not in new_index:
            chain.append(p)
            p = old_nodes[p][1]
        chains[idx] = chain
        new_nodes[new_index[idx]] = (name, new_index[p] if p != -1 else -1)

    new_frames = []
    for time, bones in smd.frames:
        out = {}
        for idx, chain in chains.items():
            rt = to_rt(bones[idx])
            for anc in chain:  # nearest removed ancestor first
                rt = compose(to_rt(bones[anc]), rt)
            out[new_index[idx]] = from_rt(rt) if chain else bones[idx]
        new_frames.append((time, out))

    removed = [old_nodes[i][0] for i in range(len(old_nodes)) if i not in new_index]
    smd.nodes = new_nodes
    smd.frames = new_frames
    return removed


# ---------------------------------------------------------------- SEAnim

SEANIM_LOOPED = 1


def read_seanim(path):
    """Full SEAnim parse. Returns dict(fps, frames, looped, type, bones={name: {"loc": [(f, v)], "rot": [...], "scale": [...]}})."""
    with open(path, "rb") as f:
        d = f.read()
    if d[:6] != b"SEAnim":
        raise ValueError("not an SEAnim file")
    header_size = struct.unpack_from("<H", d, 8)[0]
    anim_type, anim_flags, presence, props = struct.unpack_from("<BBBB", d, 10)
    fps, frame_count, bone_count = struct.unpack_from("<fII", d, 16)
    mod_count = d[28]
    p = 8 + header_size

    names = []
    for _ in range(bone_count):
        e = d.index(b"\x00", p)
        names.append(d[p:e].decode("ascii", "replace"))
        p = e + 1

    bone_fmt = "<B" if bone_count <= 0xFF else "<H"
    frame_fmt = "<B" if frame_count <= 0xFF else ("<H" if frame_count <= 0xFFFF else "<I")
    fsize = struct.calcsize(frame_fmt)
    vfmt = "d" if props & 1 else "f"
    vsize = struct.calcsize(vfmt)

    p += mod_count * (struct.calcsize(bone_fmt) + 1)  # per-bone type overrides; unused by MW19 exports

    bones = {}
    for name in names:
        p += 1  # bone flags
        b = {}
        for flag, key, comps in ((1, "loc", 3), (2, "rot", 4), (4, "scale", 3)):
            if presence & flag:
                count = struct.unpack_from(frame_fmt, d, p)[0]
                p += fsize
                keys = []
                for _ in range(count):
                    fr = struct.unpack_from(frame_fmt, d, p)[0]
                    p += fsize
                    keys.append((fr, list(struct.unpack_from("<" + vfmt * comps, d, p))))
                    p += vsize * comps
                keys.sort(key=lambda k: k[0])
                b[key] = keys
        bones[name] = b

    # Notetracks (presence flag 0x40): frame + name, e.g. footstep_left_large, ik_out_start_left_hand, grenade_off
    notes = []
    if presence & 0x40:
        note_count = struct.unpack_from("<I", d, 32)[0]
        for _ in range(note_count):
            fr = struct.unpack_from(frame_fmt, d, p)[0]
            p += fsize
            e = d.index(b"\x00", p)
            notes.append((fr, d[p:e].decode("ascii", "replace")))
            p = e + 1
        notes.sort()

    return {"fps": fps, "frames": frame_count, "looped": bool(anim_flags & SEANIM_LOOPED), "type": anim_type,
            "bones": bones, "notes": notes}


CM_TO_INCH = 1 / 2.54


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz]


def compose_additive(base, delta, rest_quat, order="base_delta", frame=None):
    """
    A static pose: an additive clip's offsets (delta, e.g. MW19 aim_4) applied on a base pose (aim_5, frame 0).
    MW19 aim spaces store their outer points as offsets from the centre, ramping in over the clip; the last
    frame is the full offset (frame= picks another). rest_quat(bone) gives the rest rotation for bones the base
    doesn't key. order: "base_delta" = base * delta (offset in the bone's own space), "delta_base" = delta * base.
    """
    last = frame if frame is not None else max(
        (k[-1][0] for b in delta["bones"].values() for k in b.values() if k), default=0)
    bones = {}
    names = set(base["bones"]) | set(delta["bones"])
    for name in names:
        bb, db = base["bones"].get(name, {}), delta["bones"].get(name, {})
        out = {}
        if bb.get("rot") or db.get("rot"):
            q0 = sample_keys(bb["rot"], 0, slerp) if bb.get("rot") else rest_quat(name)
            if q0 is not None:
                if db.get("rot"):
                    qd = sample_keys(db["rot"], last, slerp)
                    q0 = qmul(q0, qd) if order == "base_delta" else qmul(qd, q0)
                out["rot"] = [(0, q0)]
        if bb.get("loc") or db.get("loc"):
            l0 = sample_keys(bb["loc"], 0, vlerp) if bb.get("loc") else [0.0, 0.0, 0.0]
            if db.get("loc"):
                ld = sample_keys(db["loc"], last, vlerp)
                l0 = [l0[k] + ld[k] for k in range(3)]
            out["loc"] = [(0, l0)]
        bones[name] = out
    return {"fps": base["fps"], "frames": 2, "looped": True, "type": base["type"], "bones": bones, "notes": []}

def root_track(anim, loc_scale=CM_TO_INCH):
    """
    tag_origin (the character's ground root) per frame, relative to frame 0, in frame 0's space:
    [(x forward, y left, z up, yaw degrees CCW)], CoD axes, inches. Empty tag = no root motion.
    """
    tag = anim["bones"].get("tag_origin", {})
    last_key = max((k[-1][0] for b in anim["bones"].values() for k in b.values() if k), default=0)
    n = max(anim["frames"], last_key + 1, 1)
    out = []
    r0 = t0 = None
    for fr in range(n):
        r = quat_to_matrix(sample_keys(tag["rot"], fr, slerp)) if tag.get("rot") else euler_to_matrix(0, 0, 0)
        t = sample_keys(tag["loc"], fr, vlerp) if tag.get("loc") else [0.0, 0.0, 0.0]
        t = [v * loc_scale for v in t]
        if r0 is None:
            r0, t0 = r, t
        r0t = [[r0[j][i] for j in range(3)] for i in range(3)]
        d = mat_vec(r0t, [t[k] - t0[k] for k in range(3)])
        rel = mat_mul(r0t, r)
        yaw = math.degrees(math.atan2(rel[1][0], rel[0][0]))
        out.append((d[0], d[1], d[2], yaw))
    # unwrap yaw so turns past 180 keep counting
    for i in range(1, len(out)):
        x, y, z, yaw = out[i]
        prev = out[i - 1][3]
        while yaw - prev > 180:
            yaw -= 360
        while yaw - prev < -180:
            yaw += 360
        out[i] = (x, y, z, yaw)
    return out


def seanim_to_smd(anim, target, mapping, proc_follow=True, loc_scale=CM_TO_INCH, inplace=False):
    """
    loc_scale: MW19 SEAnim translations are centimetres while the rig is in inches (walk 260 cm/s = 2.6 m/s).
    inplace: leave tag_origin (root motion) out, so the clip stays on the spot; get the motion from root_track().
    """
    """
    Bake an SEAnim onto the target body's skeleton.
    MW19 exports (types 2/3) store rotations as absolute local quaternions and translations as offsets from the
    rest position; bones without keys hold the rest pose. Body bones keep CoD's local axes, so non-root bones map
    directly; the root (j_mainroot under tag_origin) is converted between CoD and SMD space.
    """
    fill_frames(target)
    rest = target.frames[0][1]
    body_index = {n: i for i, (n, _) in enumerate(target.nodes)}

    by_body = {}
    for cod, b in anim["bones"].items():
        name = mapping.get(cod, cod)
        if name in body_index and (b.get("loc") or b.get("rot")):
            by_body[body_index[name]] = b
    tag = anim["bones"].get("tag_origin", {})

    last_key = 0
    for b in anim["bones"].values():
        for keys in b.values():
            if keys:
                last_key = max(last_key, keys[-1][0])
    nframes = max(anim["frames"], last_key + 1, 1)

    rest_rt = [to_rt(rest[i]) for i in range(len(target.nodes))]
    roots = [i for i, (_, parent) in enumerate(target.nodes) if parent == -1]
    for i in roots:  # rest of a root bone in CoD tag_origin space
        r, t = rest_rt[i]
        rest_rt[i] = (mat_mul(SMD_TO_COD, r), mat_vec(SMD_TO_COD, t))

    smd = Smd()
    smd.header = ["version 1"]
    smd.nodes = list(target.nodes)

    weapons = []  # (smd index, keys, rest position)
    mp_gun = None  # (smd index, j_gun keys, j_gun_adjust keys) for the MP chain
    adj = anim["bones"].get("j_gun_adjust", {})
    gun_fit = (MP_GUN_RIGS.get(anim.get("rig")) or MP_GUN) if MP_GUN else None
    if gun_fit and adj.get("rot") and "j_gun" in anim["bones"] and "j_gun" not in body_index:
        parent = body_index.get(mapping.get(gun_fit["parent"], gun_fit["parent"]))
        if parent is not None:
            mp_gun = (len(smd.nodes), anim["bones"]["j_gun"], adj)
            smd.nodes.append(("j_gun", parent))
    for wname, (cod_parent, wrest) in WEAPON_BONES.items():
        if mp_gun and wname == "j_gun":
            continue
        wb = anim["bones"].get(wname, {})
        parent = body_index.get(mapping.get(cod_parent, cod_parent))
        if wb.get("rot") and parent is not None and wname not in body_index:
            weapons.append((len(smd.nodes), wb, wrest))
            smd.nodes.append((wname, parent))

    for fr in range(nframes):
        bones = {}
        for i in range(len(target.nodes)):
            b = by_body.get(i)
            if not b and i not in roots:
                bones[i] = rest[i]
                continue
            r, t = rest_rt[i]
            if b:
                if b.get("rot"):
                    r = quat_to_matrix(sample_keys(b["rot"], fr, slerp))
                if b.get("loc"):
                    off = sample_keys(b["loc"], fr, vlerp)
                    t = [t[0] + off[0] * loc_scale, t[1] + off[1] * loc_scale, t[2] + off[2] * loc_scale]
            if i in roots:
                if inplace:
                    tr, tt = euler_to_matrix(0, 0, 0), [0.0, 0.0, 0.0]
                else:
                    tr = quat_to_matrix(sample_keys(tag["rot"], fr, slerp)) if tag.get("rot") else euler_to_matrix(0, 0, 0)
                    tt = sample_keys(tag["loc"], fr, vlerp) if tag.get("loc") else [0.0, 0.0, 0.0]
                    tt = [v * loc_scale for v in tt]
                r, t = compose((tr, tt), (r, t))
                r, t = mat_mul(COD_TO_SMD, r), mat_vec(COD_TO_SMD, t)
            bones[i] = from_rt((r, t))
        for i, wb, wrest in weapons:
            r = quat_to_matrix(sample_keys(wb["rot"], fr, slerp))
            off = sample_keys(wb["loc"], fr, vlerp) if wb.get("loc") else [0.0, 0.0, 0.0]
            bones[i] = from_rt((r, [wrest[k] + off[k] * loc_scale for k in range(3)]))
        if mp_gun:
            i, gb, ab = mp_gun
            ra = quat_to_matrix(sample_keys(ab["rot"], fr, slerp))
            rg = quat_to_matrix(sample_keys(gb["rot"], fr, slerp)) if gb.get("rot") else euler_to_matrix(0, 0, 0)
            off = sample_keys(gb["loc"], fr, vlerp) if gb.get("loc") else [0.0, 0.0, 0.0]
            ra_rest, rg_rest = gun_fit["rest_adjust"], gun_fit["rest_gun"]
            inner = [rg_rest[k] + off[k] * loc_scale for k in range(3)]
            t = mat_vec(ra, inner)
            bones[i] = from_rt((mat_mul(ra, rg), [ra_rest[k] + t[k] for k in range(3)]))
        if proc_follow:
            apply_proc_follow(target.nodes, rest, bones, by_body)
        smd.frames.append((fr, bones))
    return smd, sorted(target.nodes[i][0] for i in by_body)


def rename_seanim(src, dst, rename):
    with open(src, "rb") as f:
        data = f.read()
    if data[:6] != b"SEAnim":
        raise ValueError("not an SEAnim file")
    header_size = struct.unpack_from("<H", data, 8)[0]
    # header (starting at the header-size field): type, flags, presence, property, 2 reserved, fps, frames, bones, ...
    bone_count = struct.unpack_from("<I", data, 8 + 2 + 4 + 2 + 4 + 4)[0]
    pos = 8 + header_size

    names = []
    for _ in range(bone_count):
        end = data.index(b"\x00", pos)
        raw = data[pos:end]
        if not all(32 <= c < 127 for c in raw):
            raise ValueError("unexpected bone name bytes; file layout not recognised")
        names.append(raw.decode("ascii"))
        pos = end + 1

    new_names = rename(names)
    out = bytearray(data[:8 + header_size])
    for nm in new_names:
        out += nm.encode("ascii") + b"\x00"
    out += data[pos:]

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(out)
    return names, new_names


# ---------------------------------------------------------------- main

def make_renamer(mapping, log):
    def rename(names):
        result = [mapping.get(n, n) for n in names]
        renamed_targets = {mapping[n] for n in names if n in mapping}
        for i, n in enumerate(names):
            # an untouched bone that already has a name we just renamed something else to
            if n not in mapping and n in renamed_targets:
                result[i] = n + "_orig"
                log.append(f"    name clash: existing '{n}' renamed to '{n}_orig'")
        return result
    return rename


def scene_key(name):
    """zd30c_1f_040_breach_sceneb_price -> zd30c_1f_040; groups animations that play together."""
    return "_".join(name.split("_")[:3])


def write_qc(args, out_root, sequences):
    """
    Standalone QC(s): the body as reference mesh (copied next to the QC) plus one $sequence per animation.
    With --split, one QC/model per scene instead, keeping each .mdl small enough for the game to load.
    """
    import shutil

    ref = os.path.basename(args.target)
    shutil.copyfile(args.target, os.path.join(out_root, ref))

    base = os.path.splitext(os.path.basename(args.qc))[0]
    modelname = args.modelname or f"cod_anims/{base}.mdl"
    if not args.split:
        return [write_one_qc(args, out_root, args.qc, modelname, ref, sequences)]

    groups = {}
    for seq in sequences:
        groups.setdefault(scene_key(seq[0]), []).append(seq)
    folder = os.path.splitext(modelname)[0]
    return [write_one_qc(args, out_root, f"{key}.qc", f"{folder}/{key}.mdl", ref, seqs)
            for key, seqs in sorted(groups.items())]


def write_one_qc(args, out_root, qcname, modelname, ref, sequences):
    lines = [
        "// Generated by cod_anim_prep.py",
        f'$modelname "{modelname}"',
        f'$model "body" "{ref}"',
    ]
    for cd in args.cdmaterials or []:
        lines.append(f'$cdmaterials "{cd}"')
    lines.append('$surfaceprop "flesh"')

    # $definebone / $bonemerge from the character's own QC keep the bind pose identical and stop studiomdl
    # collapsing unweighted bones (gear bones, procedural bones) that the animations drive
    if args.base_qc:
        with open(args.base_qc, "r", encoding="utf-8", errors="replace") as f:
            kept = [l.strip() for l in f if l.strip().startswith(("$definebone", "$bonemerge"))]
        lines.append("")
        lines.extend(kept)

    # weapon bones aren't on the body mesh, so define them (and keep studiomdl from collapsing them)
    mapping = load_mapping(args.mapping)
    lines.append("")
    for wname, (cod_parent, (x, y, z)) in WEAPON_BONES.items():
        lines.append(f'$definebone "{wname}" "{mapping.get(cod_parent, cod_parent)}" {x:g} {y:g} {z:g} 0 0 0 0 0 0 0 0 0')
        lines.append(f'$bonemerge "{wname}"')

    lines += ["", f'$sequence "reference" "{ref}" fps 1', ""]
    for name, rel, fps, looped in sequences:
        rel = rel.replace("\\", "/")
        lines.append(f'$sequence "{name}" "{rel}" fps {fps:g}{" loop" if looped else ""}')

    path = os.path.join(out_root, qcname)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return path


def process(args):
    mapping = load_mapping(args.mapping)
    target = read_smd(args.target)
    target_names = [n for n, _ in target.nodes]
    target_set = set(target_names)
    target_parent = {n: (target.nodes[p][0] if p != -1 else None) for n, p in target.nodes}
    keep_patterns = DEFAULT_KEEP + (args.keep or [])

    def keep(name):
        return name in target_set or any(fnmatch.fnmatch(name, p) for p in keep_patterns)

    src_root = os.path.abspath(args.folder)
    out_root = os.path.abspath(args.out or (src_root.rstrip("\\/") + "_valvebiped"))

    report = [f"target: {args.target} ({len(target_names)} bones)", f"mapping: {args.mapping} ({len(mapping)} entries)", ""]
    totals = {"ok": 0, "failed": 0}

    files = []
    for dirpath, _, filenames in os.walk(src_root):
        if os.path.abspath(dirpath).startswith(out_root):
            continue
        for fn in filenames:
            if not fn.lower().endswith((".smd", ".seanim")):
                continue
            if args.match and not any(fnmatch.fnmatch(fn.lower(), m.lower()) for m in args.match):
                continue
            files.append(os.path.join(dirpath, fn))
        if not args.recursive:
            break

    sequences = []  # (name, smd path relative to out_root, fps, looped)
    root_name = next(n for n, p in target.nodes if p == -1)
    totals["skipped"] = 0

    for path in sorted(files):
        rel = os.path.relpath(path, src_root)
        dst = os.path.join(out_root, rel)
        log = [rel]
        rename = make_renamer(mapping, log)
        try:
            if path.lower().endswith(".seanim") and args.seanim_mode == "rename":
                old, new = rename_seanim(path, dst, rename)
                final = new
                log.append(f"  seanim: {sum(a != b for a, b in zip(old, new))} bones renamed (rename only)")
            elif path.lower().endswith(".seanim"):
                anim = read_seanim(path)
                smd, driven = seanim_to_smd(anim, target, mapping, not args.no_proc_follow, args.loc_scale, args.inplace)
                if root_name not in driven or len(driven) < args.min_bones:
                    log.append(f"  skipped: drives {len(driven)} body bones"
                               f"{'' if root_name in driven else ', not the root'} (prop, camera or viewmodel?)")
                    totals["skipped"] += 1
                    report.extend(log)
                    report.append("")
                    print("\n".join(log))
                    continue
                dst = os.path.splitext(dst)[0] + ".smd"
                write_smd(dst, smd)
                sequences.append((os.path.splitext(os.path.basename(path))[0], os.path.relpath(dst, out_root),
                                  anim["fps"] or 30, anim["looped"]))
                final = driven
                log.append(f"  seanim -> smd: {len(smd.frames)} frames @ {anim['fps']:g} fps"
                           f"{', looped' if anim['looped'] else ''}")
            else:
                smd = read_smd(path)
                old = [n for n, _ in smd.nodes]
                new = rename(old)
                smd.nodes = [(nm, p) for nm, (_, p) in zip(new, smd.nodes)]
                log.append(f"  smd: {len(smd.frames)} frames, {sum(a != b for a, b in zip(old, new))} bones renamed")

                if args.no_strip:
                    pass
                elif smd.has_mesh:
                    log.append("  has mesh data; skipped bone stripping (would break vertex weights)")
                else:
                    removed = strip_bones(smd, keep)
                    if removed:
                        shown = ", ".join(removed[:12]) + (" ..." if len(removed) > 12 else "")
                        log.append(f"  dropped {len(removed)} bones not on the body: {shown}")

                final = [n for n, _ in smd.nodes]
                parent_of = {n: (smd.nodes[p][0] if p != -1 else None) for n, p in smd.nodes}
                mismatched = [n for n in final if n in target_parent and parent_of[n] != target_parent[n]]
                if mismatched:
                    log.append("  WARNING parent differs from body for: " + ", ".join(
                        f"{n} ({parent_of[n]} vs {target_parent[n]})" for n in mismatched[:8]))
                write_smd(dst, smd)
                if not smd.has_mesh:
                    sequences.append((os.path.splitext(os.path.basename(path))[0], os.path.relpath(dst, out_root), 30, False))

            final_set = set(final)
            missing = [n for n in target_names if n not in final_set]
            log.append(f"  drives {len(target_names) - len(missing)}/{len(target_names)} body bones")
            if missing:
                log.append("  at rest pose: " + ", ".join(missing))
            totals["ok"] += 1
        except Exception as e:
            log.append(f"  FAILED: {e}")
            totals["failed"] += 1
        report.extend(log)
        report.append("")
        print("\n".join(log))

    report.append(f"{totals['ok']} converted, {totals['skipped']} skipped, {totals['failed']} failed -> {out_root}")
    print(report[-1])
    os.makedirs(out_root, exist_ok=True)
    if args.qc and sequences:
        qcs = write_qc(args, out_root, sequences)
        report.append(f"QC: {len(qcs)} file(s), {len(sequences)} sequences: " + ", ".join(os.path.basename(q) for q in qcs))
        print(report[-1])
    with open(os.path.join(out_root, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    return 1 if totals["failed"] else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", help="folder of .smd / .seanim animations")
    ap.add_argument("--target", required=True, help="body SMD whose skeleton is the goal")
    ap.add_argument("--mapping", default=DEFAULT_MAPPING, help="Blender rename script containing bone_mapping")
    ap.add_argument("--out", help="output folder (default: <folder>_valvebiped)")
    ap.add_argument("--keep", action="append", help="extra bone name pattern to keep even if not on the body")
    ap.add_argument("--no-strip", action="store_true", help="only rename, keep every bone")
    ap.add_argument("--loc-scale", type=float, default=CM_TO_INCH,
                    help="SEAnim translation scale (default 1/2.54: MW19 stores cm, the rig is inches; 1 = old behaviour)")
    ap.add_argument("--inplace", action="store_true", help="leave tag_origin root motion out (clip stays on the spot)")
    ap.add_argument("--no-proc-follow", action="store_true",
                    help="leave CoD procedural helpers (j_proc_lift_clavicle_*) at rest instead of following the clavicle")
    ap.add_argument("--recursive", "-r", action="store_true", help="include subfolders")
    ap.add_argument("--match", action="append", help='only files matching this pattern, e.g. "zd30*" (repeatable)')
    ap.add_argument("--seanim-mode", choices=["smd", "rename"], default="smd",
                    help="smd: convert .seanim to SMD on the body skeleton (default); rename: rename bones in place")
    ap.add_argument("--min-bones", type=int, default=20,
                    help="skip .seanim files that drive fewer body bones than this (props, cameras)")
    ap.add_argument("--qc", help="write a standalone QC with this file name into the output folder")
    ap.add_argument("--modelname", help='$modelname for the QC (default "cod_anims/<qc name>.mdl")')
    ap.add_argument("--split", action="store_true",
                    help="one QC/model per scene (<modelname without .mdl>/<scene>.mdl) instead of one big model")
    ap.add_argument("--base-qc", help="character QC to copy $definebone/$bonemerge lines from")
    ap.add_argument("--cdmaterials", action="append", help="$cdmaterials path for the QC (repeatable)")
    sys.exit(process(ap.parse_args()))


if __name__ == "__main__":
    main()
