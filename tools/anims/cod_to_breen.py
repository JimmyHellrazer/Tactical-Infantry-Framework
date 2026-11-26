"""
Retarget animations from the ValveBiped-renamed CoD rig (cod_anim_prep.py output) onto the real ValveBiped
(Breen) skeleton, so they play on normal GMod playermodels.

The renamed rig keeps CoD's bone axes, rest pose and proportions; renaming alone isn't a retarget. The target's
rest pose is first lined up with the source's (top-down, each limb/finger bone swung to point where the source
bone points; torso and head keep their own rest), then every shared bone copies the source's world rotation:
    W_t(b) = W_s(b) * inv(Rest_s(b)) * AlignedRest_t(b)        (rotations, model space)
Bone lengths come from the target's rest pose. The pelvis moves by the source's travel (cod_anim_prep.py now
converts MW19's cm to inches; use --root-unit 2.54 for SMDs made before that). Breen's Spine (not on the CoD rig) takes half of Spine1's bend. Other target bones the source doesn't
have follow their parent rigidly. Checked against the Oct 2026 Breen death set: within 0.1 deg except the spine.

j_gun (the weapon bone) is re-parented to the right hand and keeps the same grip relative to it.

Usage:
  python cod_to_breen.py <smd_folder> --source K:/head2/PlaceHolder_Body.smd --target K:/duglastakedown_smd/reference.smd --out <folder>
  python cod_to_breen.py ... --compare old.smd new.smd     (per-bone angle difference report, for checking)
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from cod_anim_prep import (read_smd, write_smd, fill_frames, to_rt, from_rt, mat_mul, mat_vec, Smd,  # noqa: E402
                           quat_to_matrix, slerp)


def transpose(m):
    return [[m[j][i] for j in range(3)] for i in range(3)]


def inv_rt(rt):
    r, t = rt
    ri = transpose(r)
    ti = mat_vec(ri, t)
    return ri, [-ti[0], -ti[1], -ti[2]]


def mul_rt(a, b):
    ar, at = a
    br, bt = b
    t = mat_vec(ar, bt)
    return mat_mul(ar, br), [t[0] + at[0], t[1] + at[1], t[2] + at[2]]


def world_pose(nodes, local):
    """local: {i: (R, t)} -> world {i: (R, t)}; nodes are parent-before-child in SMDs."""
    out = {}
    for i, (_, parent) in enumerate(nodes):
        out[i] = local[i] if parent == -1 else mul_rt(out[parent], local[i])
    return out


def rest_of(smd):
    fill_frames(smd)
    local = {i: to_rt(v) for i, v in smd.frames[0][1].items()}
    return local, world_pose(smd.nodes, local)


def arc(u, v):
    """Shortest rotation taking unit vector u onto v (3x3)."""
    c = sum(a * b for a, b in zip(u, v))
    ax = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    s = math.sqrt(sum(a * a for a in ax))
    if s < 1e-9:
        if c > 0:
            return [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        # opposite: 180 degrees about any perpendicular axis
        p = [1, 0, 0] if abs(u[0]) < 0.9 else [0, 1, 0]
        ax = [u[1] * p[2] - u[2] * p[1], u[2] * p[0] - u[0] * p[2], u[0] * p[1] - u[1] * p[0]]
        s = math.sqrt(sum(a * a for a in ax))
        c = -1.0
    x, y, z = (a / s for a in ax)
    ang = math.atan2(s, c)
    ca, sa = math.cos(ang), math.sin(ang)
    t = 1 - ca
    return [[t * x * x + ca, t * x * y - sa * z, t * x * z + sa * y],
            [t * x * y + sa * z, t * y * y + ca, t * y * z - sa * x],
            [t * x * z - sa * y, t * y * z + sa * x, t * z * z + ca]]


def unit(a, b):
    d = [b[k] - a[k] for k in range(3)]
    l = math.sqrt(sum(x * x for x in d))
    return [x / l for x in d] if l > 1e-6 else None


# Which child a bone points at, when it has several (the hand points down the middle finger).
BETWEEN = {"ValveBiped.Bip01_Spine": "ValveBiped.Bip01_Spine1"}

# Clavicles: Breen's start ~2.4 in higher on the chest than the CoD rig's, so copying the clavicle direction puts
# the shoulders up at the neck when a clip shrugs. Instead the shoulder (UpperArm joint) moves relative to Spine4
# by as much as the source's does from its rest, starting from Breen's rest shoulder; the clavicle aims there.
SHOULDER_FIT = {
    "ValveBiped.Bip01_L_Clavicle": ("ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_L_UpperArm"),
    "ValveBiped.Bip01_R_Clavicle": ("ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_R_UpperArm"),
}


def fit_shoulder(rot, i, parent, fit, a_w, a_index, src_rest, t_w, t_index, tgt_rest_local, tgt_rest_w):
    chest, arm = fit
    ac, aa = a_index.get(chest), a_index.get(arm)
    tc, ta = t_index.get(chest), t_index.get(arm)
    if None in (ac, aa, tc, ta) or chest not in src_rest or arm not in src_rest or tc not in t_w:
        return rot
    now = mul_rt(inv_rt(a_w[ac]), a_w[aa])[1]
    rest = mul_rt(inv_rt(src_rest[chest]), src_rest[arm])[1]
    shrug = mat_vec(a_w[ac][0], [now[k] - rest[k] for k in range(3)])
    rest_t = mul_rt(inv_rt(tgt_rest_w[tc]), tgt_rest_w[ta])[1]
    want = mul_rt(t_w[tc], ([[1, 0, 0], [0, 1, 0], [0, 0, 1]], rest_t))[1]
    want = [want[k] + shrug[k] for k in range(3)]
    start = mul_rt(t_w[parent], tgt_rest_local[i])[1]
    have = mat_vec(rot, tgt_rest_local[ta][1])
    d_have, d_want = unit([0, 0, 0], have), unit(start, want)
    if not d_have or not d_want:
        return rot
    return mat_mul(arc(d_have, d_want), rot)


def mat_to_quat(m):
    """3x3 -> (x, y, z, w), same convention as cod_anim_prep.quat_to_matrix."""
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


TORSO = ("Pelvis", "Spine", "Neck", "Head", "forward")
PREFER_CHILD = ("ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_R_Finger2", "ValveBiped.Bip01_L_Finger2")


def rest_offsets(src_nodes, src_rest_w, tgt_nodes, tgt_rest_w):
    """
    Per shared bone, the rotation C with W_t = W_s * C. The target's rest pose is first turned so each bone points
    where the source bone points at rest (the rigs' rest poses differ: arm angle, hand and finger bend), so the
    retargeted bones point the same way as the source's during the animation. The root keeps its own rest.
    """
    s_index = {n: i for i, (n, _) in enumerate(src_nodes)}
    shared = {n for n, _ in tgt_nodes if n in s_index}
    children = {}
    for i, (n, p) in enumerate(tgt_nodes):
        if p != -1 and n in shared:
            children.setdefault(p, []).append(i)
    # Aligned target rest, built top-down: each bone starts from its parent's aligned frame plus its own rest
    # rotation, then swings (shortest turn) to the source's direction. Going top-down keeps each bone's roll
    # relative to its parent, so fingers don't twist about their own length.
    C, aligned = {}, {}
    for i, (name, parent) in enumerate(tgt_nodes):
        local = mat_mul(transpose(tgt_rest_w[parent][0]), tgt_rest_w[i][0]) if parent != -1 else None
        cand = mat_mul(aligned[parent], local) if parent != -1 else tgt_rest_w[i][0]
        kids = children.get(i, [])
        if name in shared and parent != -1 and kids and not any(k in name for k in TORSO):
            pick = next((k for k in kids if tgt_nodes[k][0] in PREFER_CHILD), None)
            if pick is None:
                pick = max(kids, key=lambda k: math.dist(tgt_rest_w[i][1], tgt_rest_w[k][1]))
            dt = unit(tgt_rest_w[i][1], tgt_rest_w[pick][1])
            ds = unit(src_rest_w[s_index[name]][1], src_rest_w[s_index[tgt_nodes[pick][0]]][1])
            if dt and ds:
                d_now = mat_vec(mat_mul(cand, transpose(tgt_rest_w[i][0])), dt)
                cand = mat_mul(arc(d_now, ds), cand)
        aligned[i] = cand
        if name in shared:
            C[name] = mat_mul(transpose(src_rest_w[s_index[name]][0]), cand)
    return C


def retarget(anim, src_rest_w, tgt, tgt_rest_local, tgt_rest_w, unit_scale, offsets):
    fill_frames(anim)
    a_index = {n: i for i, (n, _) in enumerate(anim.nodes)}
    t_nodes = list(tgt.nodes)
    t_index = {n: i for i, (n, _) in enumerate(t_nodes)}
    src_rest_by_name = {n: src_rest_w[i] for n, i in src_rest_w["_index"].items()}

    hand = t_index.get("ValveBiped.Bip01_R_Hand")
    gun_src = a_index.get("j_gun")

    out = Smd()
    out.header = ["version 1"]
    out.nodes = list(t_nodes)
    gun_out = None
    if gun_src is not None and hand is not None:
        gun_out = len(out.nodes)
        out.nodes.append(("j_gun", hand))

    for time, bones in anim.frames:
        a_local = {i: to_rt(v) for i, v in bones.items()}
        a_w = world_pose(anim.nodes, a_local)
        t_w = {}
        for i, (name, parent) in enumerate(t_nodes):
            ai = a_index.get(name)
            rest_s = src_rest_by_name.get(name) if src_rest_by_name else None
            if ai is not None and name in offsets:
                rot = mat_mul(a_w[ai][0], offsets[name])
                fit = SHOULDER_FIT.get(name)
                if fit and parent != -1:
                    rot = fit_shoulder(rot, i, parent, fit, a_w, a_index, src_rest_by_name, t_w, t_index,
                                       tgt_rest_local, tgt_rest_w)
            elif name in BETWEEN and parent != -1:
                # A target bone the source lacks, between two it has (Breen's Spine under Spine1): takes half the bend
                child = BETWEEN[name]
                ci, cai = t_index.get(child), a_index.get(child)
                rigid = mat_mul(t_w[parent][0], tgt_rest_local[i][0])
                if ci is not None and cai is not None and child in offsets:
                    child_w = mat_mul(a_w[cai][0], offsets[child])
                    full = mat_mul(child_w, transpose(tgt_rest_local[ci][0]))
                    rot = quat_to_matrix(slerp(mat_to_quat(rigid), mat_to_quat(full), 0.5))
                else:
                    rot = rigid
            elif parent != -1:
                rot = mat_mul(t_w[parent][0], tgt_rest_local[i][0])
            else:
                rot = tgt_rest_w[i][0]
            if parent == -1:
                if ai is not None and rest_s is not None:
                    # MW19 root offsets are centimetres: move from the target's rest by the source's travel / 2.54
                    p, r0, t0 = a_w[ai][1], rest_s[1], tgt_rest_w[i][1]
                    pos = [t0[k] + (p[k] - r0[k]) * unit_scale for k in range(3)]
                else:
                    pos = tgt_rest_w[i][1]
            else:
                pos = mul_rt(t_w[parent], tgt_rest_local[i])[1]
            t_w[i] = (rot, pos)
        frame = {}
        for i, (_, parent) in enumerate(t_nodes):
            loc = t_w[i] if parent == -1 else mul_rt(inv_rt(t_w[parent]), t_w[i])
            frame[i] = from_rt(loc)
        if gun_out is not None:
            ah = a_index.get("ValveBiped.Bip01_R_Hand")
            # grip: gun relative to the source hand, re-applied in the target hand's source-aligned frame
            grip = mul_rt(inv_rt(a_w[ah]), a_w[gun_src])
            aligned_hand = (a_w[ah][0], t_w[hand][1])
            gun_w = mul_rt(aligned_hand, grip)
            frame[gun_out] = from_rt(mul_rt(inv_rt(t_w[hand]), gun_w))
        out.frames.append((time, frame))
    return out


def angle_between(r1, r2):
    m = mat_mul(transpose(r1), r2)
    c = (m[0][0] + m[1][1] + m[2][2] - 1) / 2
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


def compare(old_path, new_path):
    a, b = read_smd(old_path), read_smd(new_path)
    fill_frames(a)
    fill_frames(b)
    bi = {n: i for i, (n, _) in enumerate(b.nodes)}
    worst = {}
    n = min(len(a.frames), len(b.frames))
    for f in range(n):
        wa = world_pose(a.nodes, {i: to_rt(v) for i, v in a.frames[f][1].items()})
        wb = world_pose(b.nodes, {i: to_rt(v) for i, v in b.frames[f][1].items()})
        for i, (name, _) in enumerate(a.nodes):
            j = bi.get(name)
            if j is None:
                continue
            d = angle_between(wa[i][0], wb[j][0])
            pd = math.dist(wa[i][1], wb[j][1])
            w = worst.setdefault(name, [0, 0, 0, 0])
            w[0] = max(w[0], d)
            w[1] += d / n
            w[2] = max(w[2], pd)
            w[3] += pd / n
    print(f"frames compared: {n} (old {len(a.frames)}, new {len(b.frames)})")
    print(f"{'bone':40s} {'max deg':>8s} {'avg deg':>8s} {'max dist':>9s} {'avg dist':>9s}")
    for name, (mx, av, pmx, pav) in sorted(worst.items(), key=lambda kv: -kv[1][1]):
        print(f"{name:40s} {mx:8.1f} {av:8.1f} {pmx:9.2f} {pav:9.2f}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", nargs="?", help="folder of renamed-rig SMDs (cod_anim_prep.py output)")
    ap.add_argument("--source", default="K:/head2/PlaceHolder_Body.smd", help="renamed CoD rig body SMD")
    ap.add_argument("--target", default="K:/duglastakedown_smd/reference.smd", help="ValveBiped (Breen) skeleton SMD")
    ap.add_argument("--out", help="output folder (default <folder>_breen)")
    ap.add_argument("--root-unit", type=float, default=1.0,
                    help="divide the pelvis travel by this (2.54 for SMDs made before cod_anim_prep converted cm)")
    ap.add_argument("--compare", nargs=2, metavar=("OLD", "NEW"), help="compare two SMDs on the same skeleton")
    args = ap.parse_args()

    if args.compare:
        compare(*args.compare)
        return

    src = read_smd(args.source)
    _, src_rest_w = rest_of(src)
    src_rest_w["_index"] = {n: i for i, (n, _) in enumerate(src.nodes)}
    tgt = read_smd(args.target)
    tgt_rest_local, tgt_rest_w = rest_of(tgt)

    offsets = rest_offsets(src.nodes, src_rest_w, tgt.nodes, tgt_rest_w)
    unit_scale = 1.0 / args.root_unit

    shared = sorted(set(n for n, _ in src.nodes) & set(n for n, _ in tgt.nodes))
    print(f"shared bones: {len(shared)} of {len(tgt.nodes)} target bones")

    folder = os.path.abspath(args.folder)
    out_root = os.path.abspath(args.out or folder.rstrip("\\/") + "_breen")
    n = 0
    for fn in sorted(os.listdir(folder)):
        if not fn.lower().endswith(".smd") or fn == os.path.basename(args.source):
            continue
        anim = read_smd(os.path.join(folder, fn))
        if anim.has_mesh:
            continue
        res = retarget(anim, src_rest_w, tgt, tgt_rest_local, tgt_rest_w, unit_scale, offsets)
        write_smd(os.path.join(out_root, fn), res)
        n += 1
    print(f"{n} animations -> {out_root}")


if __name__ == "__main__":
    main()
