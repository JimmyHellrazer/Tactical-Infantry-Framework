"""
Build MW19 animations into a TIF character ("mw_male"): compiled models + TIF/GTG clip data.

Per clip in the manifest:
  .seanim -> renamed CoD rig SMD, in place (cod_anim_prep.seanim_to_smd, cm -> inches, proc clavicles follow)
          -> ValveBiped / Breen skeleton (cod_to_breen.retarget), j_gun kept under the right hand
          -> root curve from tag_origin (x forward, y left, yaw CCW, every 3 frames, like GTG's clips)
          -> notetracks -> tags (footsteps become Foot/Heel tags so TIF finds foot plants)
Then per family one animation model (QC), a host model that includes them all, and the Lua that registers
the clips and the character with TIF (lua/tif/gta/clips + characters, which TIF loads from any addon).

Usage:
  python tif_mw_build.py <manifest.py> [--compile] [--only <role pattern>]
The manifest defines: SOURCE (seanim folder), BUILD (work folder), ADDON (output addon folder),
CHARACTER (id), MODEL_DIR (models/<dir>), FAMILIES = { family: [ (role, clip, opts), ... ] }.
opts: {"loop": bool} overrides the SEAnim's loop flag.
"""

import argparse
import numpy as np
import fnmatch
import math
import os
import runpy
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cod_anim_prep as prep  # noqa: E402
import cod_to_breen as c2b  # noqa: E402

FPS = 30
DEFAULT_SOURCE_BODY = "K:/head2/PlaceHolder_Body.smd"
DEFAULT_TARGET = "K:/duglastakedown_smd/reference.smd"
DEFAULT_MESH = "K:/duglastakedown_smd/breen_smd/breen_reference.smd"
STUDIOMDL = r"K:\SteamLibrary\steamapps\common\GarrysMod\bin\studiomdl.exe"
GAMEDIR = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod"


class Ctx:
    def __init__(self, m):
        self.m = m
        self.mapping = prep.load_mapping(prep.DEFAULT_MAPPING)
        self.src_body = prep.read_smd(m.get("SOURCE_BODY", DEFAULT_SOURCE_BODY))
        prep.fill_frames(self.src_body)
        _, self.src_rest_w = c2b.rest_of(self.src_body)
        self.src_rest_w["_index"] = {n: i for i, (n, _) in enumerate(self.src_body.nodes)}
        self.tgt = prep.read_smd(m.get("TARGET", DEFAULT_TARGET))
        self.tgt_rest_local, self.tgt_rest_w = c2b.rest_of(self.tgt)
        self.offsets = c2b.rest_offsets(self.src_body.nodes, self.src_rest_w, self.tgt.nodes, self.tgt_rest_w)
        self._bidx = {n: i for i, (n, _) in enumerate(self.src_body.nodes)}
        self._roots = {i for i, (_, p) in enumerate(self.src_body.nodes) if p == -1}

    def rest_quat(self, cod_name):
        """Rest local rotation (CoD axes) of a CoD bone on the source rig, for additive clips; None for roots."""
        i = self._bidx.get(self.mapping.get(cod_name, cod_name))
        if i is None or i in self._roots:
            return None
        return c2b.mat_to_quat(prep.to_rt(self.src_body.frames[0][1][i])[0])


def is_seanim(p):
    """A real SEAnim (some files in the MW22 dump aren't: the next source is tried)."""
    with open(p, "rb") as f:
        return f.read(6) == b"SEAnim"


def src_path(m, name):
    """A clip's SEAnim: SOURCE first (MW19), then EXTRA_SOURCES in order (MW22 adds clips MW19 lacks; shared names
    keep the MW19 version, which the TIF gun hold is calibrated on)."""
    for d in [m["SOURCE"]] + list(m.get("EXTRA_SOURCES", [])):
        p = os.path.join(d, name + ".seanim")
        if os.path.exists(p) and is_seanim(p):
            return p
    return os.path.join(m["SOURCE"], name + ".seanim")


def note_tags(notes, frames):
    """MW19 notetracks -> GTG-style tags: {kind, start, end, args} with start/end as 0..1 of the clip."""
    tags, lplant, rplant = [], [], []
    span = max(1, frames - 1)
    for fr, name in notes:
        u = round(min(1.0, fr / span), 3)
        low = name.lower().strip()
        if low.startswith("footstep_left") or low.startswith("footstep_right"):
            right = low.startswith("footstep_right")
            tags.append(("Foot", u, u, {"Heel": True, "Right": right}))
            (rplant if right else lplant).append(min(fr, span))
        else:
            ev = low.replace(" = ", ":").replace(" ", "_")
            tags.append(("MoveEvent", u, u, {"MoveEvent": ev}))
    return tags, sorted(set(lplant)), sorted(set(rplant))


def borrow_notes(m, clip, anim, frames):
    """MW22 export 2 (the clean one, 2026-11-12) has no notetracks at all: no footsteps (loops lost their foot sync:
    the patrol / alert walk variants played sped up, then froze sliding), no door / grenade / end notes. The same clip
    in another EXTRA_SOURCES export (export 1) has them: those are used, rescaled to this clip's frame count when the
    two cuts are within 10% of each other's length (a few differ completely, e.g. a kick breach 85 vs 125 frames)."""
    if anim.get("notes"):
        return anim["notes"]
    here = os.path.normcase(os.path.normpath(src_path(m, clip)))
    for d in m.get("EXTRA_SOURCES", []):
        p = os.path.join(d, clip + ".seanim")
        if os.path.normcase(os.path.normpath(p)) == here or not (os.path.exists(p) and is_seanim(p)):
            continue
        other = prep.read_seanim(p)
        notes = other.get("notes") or []
        if not notes:
            continue
        na = max(other["frames"], max(f for f, _ in notes) + 1)
        ratio = (frames - 1) / max(1, na - 1)
        if 0.9 <= ratio <= 1.1:
            return [(min(frames - 1, int(round(f * ratio))), n) for f, n in notes]
    return []


def detect_steps(res, frames):
    """Heel strikes of a moving loop from its feet, for loops without footstep notes: along the feet's main axis of
    motion a planted foot drifts back slowly (most of the cycle) and swings forward fast; the strike is the end of the
    swing (the foot's furthest point that way). Returns (left frames, right frames)."""
    names = [n for n, _ in res.nodes]
    try:
        fi = [names.index("ValveBiped.Bip01_L_Foot"), names.index("ValveBiped.Bip01_R_Foot")]
    except ValueError:
        return [], []
    prep.fill_frames(res)
    P = [[], []]
    for _, bones in res.frames[:frames]:
        w = c2b.world_pose(res.nodes, {i: prep.to_rt(v) for i, v in bones.items()})
        for j, i in enumerate(fi):
            P[j].append(w[i][1][:2])
    import numpy as np
    pts = np.array(P[0] + P[1], dtype=float)
    pts -= pts.mean(axis=0)
    axis = np.linalg.svd(pts, full_matrices=False)[2][0]
    out = []
    n = frames - 1  # a loop's last frame repeats its first
    for j in range(2):
        s = np.array(P[j][:n], dtype=float) @ axis
        v = np.roll(s, -1) - s
        sign = -1.0 if np.median(v) > 0 else 1.0  # the swing goes against the planted drift
        sw = s * sign
        lo, hi = sw.min(), sw.max()
        strikes = []
        for k in range(n):
            if sw[k] >= sw[k - 1] and sw[k] > sw[(k + 1) % n] and sw[k] > lo + 0.6 * (hi - lo):
                if not strikes or k - strikes[-1] >= 8:
                    strikes.append(k)
        # the furthest point comes ~5 frames before the heel lands (MW19 walks with footstep notes, 2026-11-17)
        out.append(sorted((k + 5) % n for k in strikes))
    return out[0], out[1]


def pelvis_xy(res, frame):
    prep.fill_frames(res)
    root = next(i for i, (_, p) in enumerate(res.nodes) if p == -1)
    v = res.frames[frame][1][root]
    return v[0], v[1]


def recenter(res, loop, mode=True, target=(0.0, 0.0)):
    """
    Shift the clip so the feet sit under the origin (TIF's hull and position). MW19 multiplayer clips stand the
    body ~10 in behind and ~6 in beside tag_origin. Loops use the average over the clip, one-shots their first
    frame (so they start where idle stands). Returns the (x, y) shift applied, SMD space.
    mode "last": feet at the last frame (a get-up clip ends where idle stands).
    mode "pelvis": the pelvis (average) goes to target (prone loops line up with the end of the get-down clip).
    """
    prep.fill_frames(res)
    idx = {n: i for i, (n, _) in enumerate(res.nodes)}
    lf, rf = idx.get("ValveBiped.Bip01_L_Foot"), idx.get("ValveBiped.Bip01_R_Foot")
    root = next(i for i, (_, p) in enumerate(res.nodes) if p == -1)
    if lf is None or rf is None:
        return 0.0, 0.0
    if mode in ("pelvis", "pelvis_last"):
        # pelvis_last: the LAST frame's pelvis goes to target (a dive into prone ends where the prone idle lies)
        frames = res.frames[-1:] if mode == "pelvis_last" else (res.frames if loop else res.frames[:1])
        dx = sum(b[root][0] for _, b in frames) / len(frames) - target[0]
        dy = sum(b[root][1] for _, b in frames) / len(frames) - target[1]
    else:
        frames = res.frames[-1:] if mode == "last" else (res.frames if loop else res.frames[:1])
        sx = sy = 0.0
        for _, bones in frames:
            w = c2b.world_pose(res.nodes, {i: prep.to_rt(v) for i, v in bones.items()})
            sx += (w[lf][1][0] + w[rf][1][0]) / 2
            sy += (w[lf][1][1] + w[rf][1][1]) / 2
        dx, dy = sx / len(frames), sy / len(frames)
    for _, bones in res.frames:
        v = bones[root]
        bones[root] = [v[0] - dx, v[1] - dy] + v[2:]
    return dx, dy


AIM_YAW, AIM_PITCH = "mw_aim_yaw", "mw_aim_pitch"
# Missing points of a 9-point aim set borrow the nearest one along yaw, then pitch (crouch cover has 5 points).
AIM_FILL = {1: (4, 2, 5), 3: (6, 2, 5), 7: (4, 8, 5), 9: (6, 8, 5), 2: (5,), 4: (5,), 6: (5,), 8: (5,)}


def aim_dir(res):
    """Gun direction on frame 0 as model-space yaw (+ left) and pitch (+ down), degrees: j_gun's barrel (its X axis),
    else right hand -> left hand.
    (The hands were used alone until 2026-11-17: on an LMG bipod the left hand is on the stock, so the bipod sets
    measured pitch <= 10 deg (the floor) against an authored +-90 deg space: TIF's aim pitch drove them ~9x too far,
    user: "bipod angles seem multiplied". The gun bone reads the authored spaces exactly: prone +-45, crouch cover
    +-60 / -60..+65, bipods +-90.)"""
    prep.fill_frames(res)
    idx = {n: i for i, (n, _) in enumerate(res.nodes)}
    w = c2b.world_pose(res.nodes, {i: prep.to_rt(v) for i, v in res.frames[0][1].items()})
    if "j_gun" in idx:
        v = [w[idx["j_gun"]][0][k][0] for k in range(3)]
    else:
        r, l = w[idx["ValveBiped.Bip01_R_Hand"]][1], w[idx["ValveBiped.Bip01_L_Hand"]][1]
        v = [l[k] - r[k] for k in range(3)]
    x, y, z = -v[1], v[0], v[2]  # SMD (forward -Y) -> model (x forward, y left)
    return math.degrees(math.atan2(y, x)), -math.degrees(math.atan2(z, math.hypot(x, y)))


def do_blend9(ctx, family, role, opts, do_clip, smd_of, blends, build):
    """
    A 3x3 aim blend from a numpad-numbered set (opts["blend9"] = name with {} for 1..9; missing points borrow a
    neighbour). The entry is the centre clip's, with seq = the blend and aim9 = {yaw, pitch} half-ranges measured
    from the clips' gun directions; TIF drives the pose parameters mw_aim_yaw / mw_aim_pitch.
    """
    fmt = opts["blend9"]
    additive = opts.get("additive", False)
    sub = {k: v for k, v in opts.items() if k not in ("blend9", "additive")}
    if not os.path.exists(src_path(ctx.m, fmt.format(5))):
        raise ValueError(f"{fmt}: no centre (5) clip")
    base = prep.read_seanim(src_path(ctx.m, fmt.format(5)))
    have = {}
    for n in range(1, 10):
        name = fmt.format(n)
        if not os.path.exists(src_path(ctx.m, name)):
            continue
        if additive and n != 5:
            # MW19 aim spaces: outer points are offsets on the centre pose (verified: base * offset gives a
            # symmetric spread, +-90 yaw for corner leans, +-60 over a low wall).
            anim = prep.compose_additive(base, prep.read_seanim(src_path(ctx.m, name)), ctx.rest_quat)
            do_clip(family, role, name, sub, anim, name + "_abs")
            have[n] = name + "_abs"
        else:
            do_clip(family, role, name, sub)
            have[n] = name
    for n in range(1, 10):
        if n not in have:
            have[n] = next(have[k] for k in AIM_FILL[n] if k in have)
    dirs = {n: aim_dir(prep.read_smd(smd_of[have[n]])) for n in (2, 4, 5, 6, 8)}
    # (abs: sets authored at exactly +-90 read 180.0001 apart, which remainder() wraps to -179.9999)
    yaw = max(10.0, abs(math.remainder(dirs[4][0] - dirs[6][0], 360)) / 2) if have[4] != have[5] else 30.0
    pitch = max(10.0, (dirs[2][1] - dirs[8][1]) / 2) if have[2] != have[5] else 30.0
    files = [os.path.relpath(smd_of[have[n]], build).replace("\\", "/") for n in (9, 8, 7, 6, 5, 4, 3, 2, 1)]
    seq = role
    blends.setdefault(family, []).append((seq, files, yaw, pitch, sub.get("loop", True)))
    e = dict(do_clip(family, role, have[5], sub))
    e["seq"], e["from"], e["aim9"] = seq, fmt, {"yaw": round(yaw, 1), "pitch": round(pitch, 1)}
    return e


def build_external(path, out_smd):
    """
    A ready-made ValveBiped SMD (e.g. the K:\\mw19deathanimations set): its travel is baked into the pelvis, so
    the pelvis' horizontal path becomes the TIF root curve and the clip is made in place (TIF moves the soldier
    along it and stops him at walls). Returns the same tuple as build_clip.
    """
    res = prep.read_smd(path)
    prep.fill_frames(res)
    root_i = next(i for i, (_, p) in enumerate(res.nodes) if p == -1)
    x0, y0 = res.frames[0][1][root_i][0], res.frames[0][1][root_i][1]
    root = []
    for _, bones in res.frames:
        v = bones[root_i]
        dx, dy = v[0] - x0, v[1] - y0
        root.append((-dy, dx, 0.0, 0.0))  # SMD (forward -Y) -> model (x forward, y left)
        bones[root_i] = [x0, y0] + v[2:]
    prep.write_smd(out_smd, res)
    anim = {"fps": FPS, "frames": len(res.frames), "looped": False, "notes": [], "bones": {}, "type": 2}
    return anim, res, root, len(res.frames), (0.0, 0.0)


def motion_info(res, root, kind):
    """
    Death: the ragdoll handoff (0..1: once the pelvis has dropped 60% of its fall, at least 0.4 s in, so the
    clip never plays its still-on-the-ground tail) and the fall direction (pelvis travel, model x fwd / y left).
    Pain: the push direction (largest pelvis displacement during the clip).
    """
    prep.fill_frames(res)
    root_i = next(i for i, (_, p) in enumerate(res.nodes) if p == -1)
    n = len(res.frames)
    pts = []
    for f, (_, bones) in enumerate(res.frames):
        v = bones[root_i]
        r = root[min(f, len(root) - 1)]
        pts.append((r[0] - v[1], r[1] + v[0], v[2]))  # root curve + pelvis offset, model space
    out = {}
    if kind == "death":
        z0 = pts[0][2]
        zmin = min(p[2] for p in pts)
        drop = max(1e-3, z0 - zmin)
        cut = next((f for f in range(n) if f >= 12 and z0 - pts[f][2] >= 0.6 * drop), n - 1)
        out["cut"] = round(cut / max(1, n - 1), 3)
        end = pts[cut]
        out["fall"] = [round(end[0] - pts[0][0], 1), round(end[1] - pts[0][1], 1)]
    else:
        best = max(pts, key=lambda p: (p[0] - pts[0][0]) ** 2 + (p[1] - pts[0][1]) ** 2)
        out["push"] = [round(best[0] - pts[0][0], 1), round(best[1] - pts[0][1], 1)]
    return out


def fix_first_frame(anim):
    """MW22 exports (EXTRA_SOURCES) put a bind-pose key at frame 0 on every bone, and the real keys start a few
    frames later: those frames came out interpolated from the bind pose (a hand or foot sliding 15-60 units over
    the first 1-6 frames, loops not closing). The frame-0 key is dropped, so each bone holds its first real key from
    the start (2026-11-12; copying frame 1 instead, the first try, kept the junk interpolated frames)."""
    for b in anim["bones"].values():
        for k in ("rot", "loc"):
            keys = b.get(k)
            if keys and len(keys) > 1 and keys[0][0] == 0 and keys[1][0] > 0:
                del keys[0]
    return anim


def is_extra(m, name):
    return not os.path.exists(os.path.join(m["SOURCE"], name + ".seanim"))


def hold_pose(anim, frame):
    """One frame of a SEAnim as a static, looped 2-frame clip (tag_origin included, so it stays where it was)."""
    last = max((k[-1][0] for b in anim["bones"].values() for k in b.values() if k), default=0)
    fr = last if frame == "last" else int(frame)
    lerp = {"loc": prep.vlerp, "rot": prep.slerp, "scale": prep.vlerp}
    bones = {name: {k: [(0, prep.sample_keys(keys, fr, lerp.get(k, prep.vlerp)))] for k, keys in b.items() if keys}
             for name, b in anim["bones"].items()}
    return {"fps": anim["fps"], "frames": 2, "looped": True, "type": anim["type"], "bones": bones, "notes": []}


def overlay_pose(base, pose, mask=None, chest=None):
    """The base clip with every bone the pose clip keys held at the pose's first key (2026-11-17: MW19's AI low ready,
    sdr_com_exposed_*_gun_down: a 13-bone pose for spine4, neck, head, arms and j_gun, laid by CoD over whatever
    the legs do). Both are absolute-local MW19 exports (type 2)."""
    # mask: only these bones (2026-11-18: MW22's AI strafes have placeholder arms - CoD lays its aim layer over them -
    # so they take the AI aimed idle's upper body, limited to the 13 bones of MW19's ready / gun_down poses).
    out = dict(base)
    bones = {k: dict(v) for k, v in base["bones"].items()}
    for name, b in pose["bones"].items():
        if mask is not None and name not in mask:
            continue
        nb = dict(bones.get(name, {}))
        for k, keys in b.items():
            if keys:
                nb[k] = [(0, keys[0][1])]
        bones[name] = nb
    # Pin the chest: j_spine4 per frame so its orientation under the root equals the pose's (the overlaid arms and gun
    # rode the base clip's lower spine: MW22's forward AI walk leans back, its gun came out 21 deg up; user, 2026-11-18).
    # chest: another clip whose chest orientation is the target (2026-11-19: MW19's RPG ready / gun_down poses don't key
    # j_spine4 - their arms rode each base clip's lean, the launcher pointing ~65 deg down on crouch strafes / jogs -
    # so the chest comes from the RPG aim pose, the stance those arms were authored on).
    src = chest if chest is not None else pose
    if mask is not None and "j_spine4" in mask and all(base["bones"].get(c, {}).get("rot") for c in SPINE_CHAIN) \
            and all(src["bones"].get(c, {}).get("rot") for c in SPINE_CHAIN + ("j_spine4",)):
        def m3(q):
            return np.array(prep.quat_to_matrix(q))
        def at(b, k, fr):
            return prep.sample_keys(b[k]["rot"], fr, prep.slerp)
        want = np.eye(3)
        for c in SPINE_CHAIN + ("j_spine4",):
            want = want @ m3(at(src["bones"], c, 0))
        last = max((k[-1][0] for bb in base["bones"].values() for k in bb.values() if k), default=0)
        keys = []
        for fr in range(int(last) + 1):
            par = np.eye(3)
            for c in SPINE_CHAIN:
                par = par @ m3(at(base["bones"], c, fr))
            keys.append((fr, prep.mat_to_quat((par.T @ want).tolist())))
        bones["j_spine4"] = dict(bones.get("j_spine4", {}), rot=keys)
    out["bones"] = bones
    return out


SPINE_CHAIN = ("j_mainroot", "j_spinelower", "j_spineupper")


def additive_on(base, delta, rest_quat):
    """An additive clip played on a base pose, every frame (2026-11-19: MW19's AI RPG idles, sdr_com_exposed_*_rpg_idle01,
    are additive breathing / shifting offsets for the RPG aim pose sdr_com_exposed_*_rpg_aim_5; read as poses they
    are a stick figure). base frame 0 * delta frame f (offsets in the bone's own space, like the aim sets)."""
    last = max((k[-1][0] for b in delta["bones"].values() for k in b.values() if k), default=0)
    bones = {}
    for name in set(base["bones"]) | set(delta["bones"]):
        bb, db = base["bones"].get(name, {}), delta["bones"].get(name, {})
        out = {}
        if bb.get("rot") or db.get("rot"):
            q0 = prep.sample_keys(bb["rot"], 0, prep.slerp) if bb.get("rot") else rest_quat(name)
            if q0 is not None:
                if db.get("rot"):
                    out["rot"] = [(f, prep.qmul(q0, prep.sample_keys(db["rot"], f, prep.slerp))) for f in range(int(last) + 1)]
                else:
                    out["rot"] = [(0, q0)]
        if bb.get("loc") or db.get("loc"):
            l0 = prep.sample_keys(bb["loc"], 0, prep.vlerp) if bb.get("loc") else [0.0, 0.0, 0.0]
            if db.get("loc"):
                out["loc"] = []
                for f in range(int(last) + 1):
                    ld = prep.sample_keys(db["loc"], f, prep.vlerp)
                    out["loc"].append((f, [l0[k] + ld[k] for k in range(3)]))
            else:
                out["loc"] = [(0, l0)]
        bones[name] = out
    return {"fps": delta.get("fps", base["fps"]), "frames": int(last) + 1, "looped": True, "type": base["type"],
            "bones": bones, "notes": []}


def shot_slice(res, n, w, back):
    """One shot of an AI firing clip as a recoil kick (TIF 0.36.0): frames n (the fire note) .. n + w, then `back`
    frames easing every bone back to frame n's pose, so the delta (QC: subtract frame 0) starts and ends at nothing.
    Works on the baked SMD frames (ValveBiped locals: position + euler)."""
    prep.fill_frames(res)
    fr = res.frames
    n = max(0, min(n, len(fr) - 1))
    end = max(n, min(len(fr) - 1, n + w))
    base, last = fr[n][1], fr[end][1]

    def mix(a, b, t):
        qa = prep.mat_to_quat(prep.euler_to_matrix(*a[3:6]))
        qb = prep.mat_to_quat(prep.euler_to_matrix(*b[3:6]))
        r = prep.matrix_to_euler(prep.quat_to_matrix(prep.slerp(qa, qb, t)))
        return [a[i] + (b[i] - a[i]) * t for i in range(3)] + list(r)

    out = [(i, {b: list(v) for b, v in fr[f][1].items()}) for i, f in enumerate(range(n, end + 1))]
    for j in range(1, back + 1):
        t = j / back
        t = t * t * (3 - 2 * t)
        out.append((len(out), {b: mix(last[b], base[b], t) for b in base}))
    res.frames = out
    return len(out)


def trim_start(anim, fr):
    """The clip from frame fr on (that frame becomes frame 0; notes shifted, the ones before dropped). For clips with
    a long lead-in, e.g. the MW19 MP Black Hawk intros: 5-8 s of cutscene in the cabin before anyone moves."""
    fr = int(fr)
    lerp = {"loc": prep.vlerp, "rot": prep.slerp, "scale": prep.vlerp}
    bones = {}
    for name, b in anim["bones"].items():
        nb = {}
        for k, keys in b.items():
            if not keys:
                continue
            nb[k] = [(0, prep.sample_keys(keys, fr, lerp.get(k, prep.vlerp)))] + [(f - fr, v) for f, v in keys if f > fr]
        bones[name] = nb
    out = dict(anim)
    out["bones"] = bones
    out["frames"] = max(2, anim["frames"] - fr)
    out["notes"] = [(f - fr, n) for f, n in anim.get("notes", []) if f >= fr]
    return out


def trim_end(anim, fr):
    """The clip up to frame fr (it becomes the last frame; later keys and notes dropped). For clips whose tail is
    scripted catch-up, e.g. MW19's sledge breach (zd30c ally13) warps 290 units across f90-97."""
    fr = int(fr)
    lerp = {"loc": prep.vlerp, "rot": prep.slerp, "scale": prep.vlerp}
    bones = {}
    for name, b in anim["bones"].items():
        nb = {}
        for k, keys in b.items():
            if not keys:
                continue
            nb[k] = [(f, v) for f, v in keys if f < fr] + [(fr, prep.sample_keys(keys, fr, lerp.get(k, prep.vlerp)))]
        bones[name] = nb
    out = dict(anim)
    out["bones"] = bones
    out["frames"] = min(anim["frames"], fr + 1)
    out["notes"] = [(f, n) for f, n in anim.get("notes", []) if f <= fr]
    return out


def build_clip(ctx, clip, out_smd, loop_override=None, center=True, anim=None):
    if anim is None:
        path = src_path(ctx.m, clip)
        anim = prep.read_seanim(path)
        fix_dirs = [os.path.normcase(os.path.normpath(d)) for d in ctx.m.get("FIX_FIRST_KEY", [])]
        if os.path.normcase(os.path.normpath(os.path.dirname(path))) in fix_dirs:
            anim = fix_first_frame(anim)
    if abs((anim["fps"] or FPS) - FPS) > 0.01:
        raise ValueError(f"{clip}: {anim['fps']} fps (only 30 supported)")
    cod, driven = prep.seanim_to_smd(anim, ctx.src_body, ctx.mapping, True, prep.CM_TO_INCH, inplace=True)
    res = c2b.retarget(cod, ctx.src_rest_w, ctx.tgt, ctx.tgt_rest_local, ctx.tgt_rest_w, 1.0, ctx.offsets)
    loop = anim["looped"] if loop_override is None else loop_override
    # Cover clips keep their exact place relative to the cover node (hide, lean, aim and arrivals must line up).
    # center = ("pelvis", ref): the pelvis lines up with where clip `ref` (built already) ends.
    if isinstance(center, (tuple, list)) and center[0] in ("pelvis", "pelvis_last"):
        import glob as _glob
        here = os.path.join(os.path.dirname(out_smd), center[1] + ".smd")
        found = [here] if os.path.exists(here) else _glob.glob(
            os.path.join(os.path.dirname(os.path.dirname(out_smd)), "*", center[1] + ".smd"))
        if not found:
            raise ValueError(f"centre reference {center[1]} not built yet")
        ref = prep.read_smd(found[0])
        shift = recenter(res, loop, center[0], pelvis_xy(ref, -1))
    elif center:
        shift = recenter(res, loop, center)
    else:
        shift = (0.0, 0.0)
    prep.write_smd(out_smd, res)
    root = prep.root_track(anim)
    frames = len(res.frames)
    root = (root + [root[-1]] * frames)[:frames]
    return anim, res, root, frames, shift


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        r = round(v, 3)
        return str(int(r)) if r == int(r) else f"{r:g}"
    if isinstance(v, str):
        return '"' + v.replace("\\", "/").replace('"', "'") + '"'
    if isinstance(v, dict):
        return "{ " + ", ".join(f'["{k}"] = {lua_val(x)}' for k, x in v.items()) + " }"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }"
    raise TypeError(type(v))


def clip_entry(seq, clip, frames, loop, root, tags, lplant, rplant):
    dur = (frames - 1) / FPS
    curve = []
    for f in range(0, frames, 3):
        x, y, _, yaw = root[f]
        curve += [round(x, 1), round(y, 1), round(yaw, 1)]
    x, y, z, yaw = root[-1]
    dist = math.hypot(x, y)
    e = {
        "seq": seq, "from": clip, "dur": round(dur, 3), "frames": frames, "loop": loop,
        "move": [round(x, 1), round(y, 1), round(yaw, 1)], "speed": round(dist / max(0.01, dur), 1),
        "curve": curve,
    }
    if any(abs(r[2]) > 0.5 for r in root):
        e["zcurve"] = [round(root[f][2], 1) for f in range(0, frames, 3)]
    if tags:
        e["tags"] = tags
    e["lplant"], e["rplant"] = lplant or [0], rplant or [0]
    return e


CLIP_PART = 600  # roles per part


def write_clip_lua(path, pack, entries):
    """The clip table in parts, each registered from its own function (2026-11-18: 2700 roles in one table passed
    LuaJIT's 65536-constants-per-function limit: "main function has more than 65536 constants", the whole file failed
    to load; GMod runs LuaJIT). TIFG.RegisterClips merges parts (meta part / parts)."""
    roles = sorted(entries)
    chunks = [roles[i:i + CLIP_PART] for i in range(0, len(roles), CLIP_PART)] or [[]]
    lines = ["-- Generated by tif_mw_build.py: MW19 clips retargeted to ValveBiped. Do not edit by hand."]
    for ci, chunk in enumerate(chunks, start=1):
        lines.append(f'(function() TIFG.RegisterClips("{pack}", {{')
        for role in chunk:
            e = entries[role]
            parts = []
            for k in ("seq", "ub", "aim9", "kick", "cut", "fall", "push", "from", "dur", "frames", "loop", "move", "speed", "curve",
                      "zcurve", "tags", "lplant", "rplant"):
                if k in e:
                    parts.append(f"{k} = {lua_val(e[k])}")
            lines.append(f'\t["{role}"] = {{ ' + ", ".join(parts) + " },")
        # (";": a line starting with "(" after a call is ambiguous to Lua 5.1 / LuaJIT)
        lines.append(f"}}, {{ part = {ci}, parts = {len(chunks)} }}) end)();")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def gun_rest(res):
    """j_gun's local transform under the right hand on frame 0 (for $definebone)."""
    names = [n for n, _ in res.nodes]
    if "j_gun" not in names:
        return None
    v = res.frames[0][1][names.index("j_gun")]
    return v[:3], [math.degrees(a) for a in v[3:6]]


def copy_with_gun(src, dst, gun):
    """Copy a body SMD, adding j_gun under the right hand at its rest (studiomdl's $definebone can't parent it)."""
    smd = prep.read_smd(src)
    names = [n for n, _ in smd.nodes]
    if gun and "j_gun" not in names and "ValveBiped.Bip01_R_Hand" in names:
        smd.nodes.append(("j_gun", names.index("ValveBiped.Bip01_R_Hand")))
        (px, py, pz), rot = gun
        smd.frames[0][1][len(smd.nodes) - 1] = [px, py, pz] + [math.radians(a) for a in rot]
    prep.write_smd(dst, smd)


# Upper-body mask for layered clips (reloads over walking legs). Every bone is listed so nothing depends on
# studiomdl's defaults: legs and pelvis 0, the spine fades in, everything from Spine4 up (arms, head, gun) 1.
UB_WEIGHTS = {"ValveBiped.Bip01_Spine": 0.0, "ValveBiped.Bip01_Spine1": 0.3, "ValveBiped.Bip01_Spine2": 0.7}
UB_ZERO = ("Pelvis", "Thigh", "Calf", "Foot", "Toe")


def weightlist(nodes):
    lines = ['$weightlist "tif_upper" {']
    for name, _ in nodes:
        if name in UB_WEIGHTS:
            w = UB_WEIGHTS[name]
        elif any(k in name for k in UB_ZERO):
            w = 0.0
        else:
            w = 1.0
        lines.append(f'\t"{name}" {w:g}')
    lines.append("}")
    return lines


def qc_header(modelname, body, mesh_cd, gun):
    lines = [f'$modelname "{modelname}"', f'$body "body" "{body}"']
    for cd in mesh_cd:
        lines.append(f'$cdmaterials "{cd}"')
    lines.append('$surfaceprop "flesh"')
    if gun:
        lines.append('$bonemerge "j_gun"')  # keeps the unweighted weapon bone from being collapsed
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest")
    ap.add_argument("--compile", action="store_true", help="run studiomdl and copy the models into the addon")
    ap.add_argument("--only", help="rebuild only roles matching this pattern (SMDs of others are reused)")
    args = ap.parse_args()

    m = runpy.run_path(args.manifest)
    ctx = Ctx(m)
    build, addon, char = m["BUILD"], m["ADDON"], m["CHARACTER"]
    mdir = m.get("MODEL_DIR", "tif_mw")
    os.makedirs(build, exist_ok=True)

    entries, report, family_seqs, gun = {}, [], {}, None
    blends = {}  # family -> [(seq name, [9 smd paths], yaw, pitch, loop)]
    seq_done, smd_of = {}, {}

    def do_clip(family, role, clip, opts, anim_override=None, seq_name=None):
        """Build (or reuse) one clip; returns its entry. Adds it to the family's sequences once.
        anim_override: a prepared SEAnim-like dict (additive aim points composed on their base); seq_name names it."""
        nonlocal gun
        if opts.get("overlay") and anim_override is None and not seq_name:
            seq_name = f"{clip}_x_{opts['overlay']}"  # its own sequence, not the base clip's
        key = seq_name or clip
        if key in seq_done:
            e = dict(seq_done[key])
            if "loop" in opts:
                e["loop"] = opts["loop"]
            return e
        if opts.get("hold") is not None and anim_override is None:
            # A held pose: one frame of the clip ("last" or a frame number) as a 2-frame loop, e.g. a seat pose where
            # the game has only the clip that ends in it (pickup bed seats: the entry ends crouched in the bed).
            key = seq_name = seq_name or f"{clip}_hold"
            anim_override = hold_pose(prep.read_seanim(src_path(m, clip)), opts["hold"])
        if opts.get("overlay") and anim_override is None:
            # the clip with opts["overlay"]'s keyed bones held over it (an upper-body pose, e.g. AI low ready)
            mask = None
            if opts.get("overlay_mask"):
                mask = set(prep.read_seanim(src_path(m, opts["overlay_mask"]))["bones"])
            chest = None
            if opts.get("overlay_chest"):
                chest = prep.read_seanim(src_path(m, opts["overlay_chest"]))
                mask = (mask or set()) | {"j_spine4"}
            anim_override = overlay_pose(prep.read_seanim(src_path(m, clip)), prep.read_seanim(src_path(m, opts["overlay"])), mask, chest)
        if opts.get("additive_on") and anim_override is None:
            # an additive clip (clip) played on a base pose (opts["additive_on"]), every frame: additive_on()
            key = seq_name = seq_name or f"{clip}_on_{opts['additive_on']}"
            anim_override = additive_on(prep.read_seanim(src_path(m, opts["additive_on"])), prep.read_seanim(src_path(m, clip)),
                                        ctx.rest_quat)
        if opts.get("trim") and anim_override is None:
            # the clip from frame opts["trim"] on (a long lead-in cut off)
            key = seq_name = seq_name or f"{clip}_t{int(opts['trim'])}"
            anim_override = trim_start(prep.read_seanim(src_path(m, clip)), opts["trim"])
        if opts.get("end") and anim_override is None:
            # the clip up to frame opts["end"] (a scripted tail cut off)
            key = seq_name = seq_name or f"{clip}_e{int(opts['end'])}"
            anim_override = trim_end(prep.read_seanim(src_path(m, clip)), opts["end"])
        if opts.get("shot") is not None and not seq_name:
            # one shot of a firing clip as an additive kick: its own sequence per fire note
            key = seq_name = f"{clip}_s{int(opts['shot'][0])}"
            if key in seq_done:
                return dict(seq_done[key])
        smd = os.path.join(build, family, key + ".smd")
        os.makedirs(os.path.dirname(smd), exist_ok=True)
        need = not args.only or fnmatch.fnmatch(role, args.only) or not os.path.exists(smd)
        shift = (0.0, 0.0)
        if opts.get("shot") is not None:
            # Recoil kick (TIF 0.36.0): the shot's frames off the baked clip, eased back to the note pose, no root
            # motion; the QC makes it a delta of its own first frame on the upper body.
            n, w, back = opts["shot"]
            if need:
                anim, res, root, frames, shift = build_clip(ctx, clip, smd, False, False)
                frames = shot_slice(res, n, w, back)
                prep.write_smd(smd, res)
            else:
                res = prep.read_smd(smd)
                anim = prep.read_seanim(src_path(m, clip))
                frames = len(res.frames)
            e = clip_entry(key, clip, frames, False, [(0.0, 0.0, 0.0, 0.0)] * frames, None, [], [])
            e["kick"] = True
            seq_done[key] = e
            smd_of[key] = smd
            family_seqs[family].append((key, os.path.relpath(smd, build).replace("\\", "/"), False, False, True))
            report.append(f"{role:34s} {clip:52s} {frames:4d} fr  kick from frame {n}")
            return e
        if opts.get("smd"):
            anim, res, root, frames, shift = build_external(opts["smd"], smd)
        elif need:
            anim, res, root, frames, shift = build_clip(ctx, clip, smd, opts.get("loop"), opts.get("center", True),
                                                        anim_override)
        else:
            res = prep.read_smd(smd)
            anim = anim_override or prep.read_seanim(src_path(m, clip))
            root = prep.root_track(anim)
            frames = len(res.frames)
            root = (root + [root[-1]] * frames)[:frames]
        loop = opts.get("loop", anim["looped"])
        notes = anim["notes"] if (anim_override is not None or opts.get("smd")) else borrow_notes(m, clip, anim, frames)
        tags, lp, rp = note_tags(notes, frames)
        e = clip_entry(key, clip, frames, loop, root, tags, lp, rp)
        if opts.get("overlay"):
            # Its own name as "from": the gun-hold tables (keyed by from) don't treat it as the base clip. MW22's AI
            # strafes are listed undriven (their gun bone hangs off the shoulder), which put the gun on our
            # retargeted hand: ~36 deg up walking forward. With the aimed idle's arms and gun bone laid over, the
            # gun bone is right, so the gun follows it (2026-11-18).
            e["from"] = key
        if loop and not lp and not rp and e["speed"] > 15:
            # a moving loop with no footstep notes: strikes from the feet (foot-synced blending needs them)
            lp, rp = detect_steps(res, frames)
            e["lplant"], e["rplant"] = lp or [0], rp or [0]
            e["tags"] = sorted((e.get("tags") or []) + [("Foot", round(f / max(1, frames - 1), 3), round(f / max(1, frames - 1), 3),
                               {"Heel": True, "Right": r}) for r, fl in ((False, lp), (True, rp)) for f in fl], key=lambda t: t[1])
        if opts.get("ub"):
            e["ub"] = key + "_ub"
        if opts.get("motion"):
            e.update(motion_info(res, root, opts["motion"]))
        seq_done[key] = e
        smd_of[key] = smd
        family_seqs[family].append((key, os.path.relpath(smd, build).replace("\\", "/"), loop, bool(opts.get("ub")), False))
        if gun is None:
            gun = gun_rest(res)
        report.append(f"{role:34s} {clip:52s} {frames:4d} fr  move {e['move'][0]:7.1f} {e['move'][1]:7.1f} "
                      f"{e['move'][2]:6.1f}  speed {e['speed']:6.1f}  plants L{len(lp)} R{len(rp)}  "
                      f"centred {shift[0]:5.1f} {shift[1]:5.1f}  {'loop' if loop else ''}")
        return e

    for family, items in m["FAMILIES"].items():
        family_seqs[family] = []
        for item in items:
            role, clip = item[0], item[1]
            opts = item[2] if len(item) > 2 else {}
            try:
                if opts.get("blend9"):
                    entries[role] = do_blend9(ctx, family, role, opts, do_clip, smd_of, blends, build)
                else:
                    entries[role] = do_clip(family, role, clip, opts)
            except Exception as ex:  # noqa: BLE001
                report.append(f"{role:34s} {clip or opts.get('blend9', ''):52s} FAILED: {ex}")
    print("\n".join(report))

    # QCs: one animation model per family, then the host including them all.
    body = os.path.basename(m.get("TARGET", DEFAULT_TARGET))
    mesh = m.get("MESH", DEFAULT_MESH)
    copy_with_gun(m.get("TARGET", DEFAULT_TARGET), os.path.join(build, body), gun)
    copy_with_gun(mesh, os.path.join(build, os.path.basename(mesh)), gun)
    qcs = []
    for family, seqs in family_seqs.items():
        if not seqs:
            continue
        lines = ["// Generated by tif_mw_build.py"] + qc_header(f"{mdir}/{char}_{family}.mdl", body, [], gun)
        if any(s[3] or s[4] for s in seqs):
            lines += [""] + weightlist(ctx.tgt.nodes + ([("j_gun", -1)] if gun else []))
        lines += ["", f'$poseparameter "{AIM_YAW}" -90 90', f'$poseparameter "{AIM_PITCH}" -90 90']
        lines += ["", f'$sequence "{char}_{family}_ref" "{body}" fps 1', ""]
        for name, rel, loop, ub, delta in seqs:
            if delta:
                # additive recoil kick: the clip minus its own first frame, upper body only
                lines.append(f'$animation "a_{name}_ref" "{rel}" fps {FPS} frames 0 0')
                lines.append(f'$animation "a_{name}" "{rel}" fps {FPS} subtract "a_{name}_ref" 0')
                lines.append(f'$sequence "{name}" "a_{name}" delta weightlist "tif_upper" fps {FPS}')
                continue
            lines.append(f'$sequence "{name}" "{rel}" fps {FPS}{" loop" if loop else ""}')
            if ub:
                lines.append(f'$sequence "{name}_ub" "{rel}" fps {FPS}{" loop" if loop else ""} weightlist "tif_upper"')
        for name, files, yaw, pitch, loop in blends.get(family, []):
            # 3x3 aim blend: columns go right -> left (yaw -Y..+Y), rows up -> down (pitch -P..+P, + = down)
            lines.append(f'$sequence "{name}" {{')
            for row in range(3):
                lines.append("\t" + " ".join(f'"{files[row * 3 + c]}"' for c in range(3)))
            lines.append(f'\tblendwidth 3\n\tblend "{AIM_YAW}" {-yaw:.1f} {yaw:.1f}\n\tblend "{AIM_PITCH}" {-pitch:.1f} {pitch:.1f}')
            lines.append(f"\tfps {FPS}{' loop' if loop else ''}\n}}")
        path = os.path.join(build, f"{char}_{family}.qc")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        qcs.append(path)
    host = ["// Generated by tif_mw_build.py: the TIF host body (ValveBiped). Breen's mesh gives it hitboxes and a",
            "// visible fallback when a soldier's faction model can't be drawn."]
    host += qc_header(f"{mdir}/{char}.mdl", os.path.basename(mesh), ["models/breen/", "models/humans/male/"], gun)
    host += ["", f'$poseparameter "{AIM_YAW}" -90 90', f'$poseparameter "{AIM_PITCH}" -90 90']
    host += ["", f'$sequence "reference" "{body}" fps 1 loop', ""]
    for family, seqs in family_seqs.items():
        if seqs:
            host.append(f'$includemodel "{mdir}/{char}_{family}.mdl"')
    host_qc = os.path.join(build, f"{char}.qc")
    with open(host_qc, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(host) + "\n")
    qcs.append(host_qc)

    # Lua: clips + character, in the paths TIF's GTA layer loads from any addon.
    write_clip_lua(os.path.join(addon, "lua", "tif", "gta", "clips", f"{char}.lua"), char, entries)
    speeds = {k: entries[r]["speed"] for k, r in (("walk", "walk"), ("run", "run"), ("sprint", "sprint")) if r in entries}
    seqs = {k: entries[k]["seq"] for k in ("idle", "walk", "run", "sprint") if k in entries}
    cpath = os.path.join(addon, "lua", "tif", "gta", "characters", f"{char}.lua")
    os.makedirs(os.path.dirname(cpath), exist_ok=True)
    with open(cpath, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tif_mw_build.py\n")
        f.write(f'TIFG.RegisterCharacter("{char}", {{\n\tname = "{m.get("NAME", char)}",\n'
                f'\tmodel = "models/{mdir}/{char}.mdl",\n\tclips = "{char}",\n\tlibraries = {{}},\n\tbody = "male",\n'
                f'\tskeleton = "valvebiped", -- TIF: playermodels bone-merge straight on, gun held from the hands\n'
                f"\tspeeds = {lua_val(speeds)},\n\tsequences = {lua_val(seqs)},\n\texporterVersion = 3,\n}})\n")
    with open(os.path.join(build, "report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")
    print(f"{len(entries)} roles, {sum(len(s) for s in family_seqs.values())} sequences, QCs: "
          + ", ".join(os.path.basename(q) for q in qcs))

    if args.compile:
        out_models = os.path.join(addon, "models", mdir)
        os.makedirs(out_models, exist_ok=True)
        for qc in qcs:  # families first, host last (it includes them)
            r = subprocess.run([STUDIOMDL, "-game", GAMEDIR, "-nop4", "-nox360", qc], capture_output=True, text=True,
                               errors="replace")
            bad = [l for l in r.stdout.splitlines() if "ERROR" in l or "WARNING" in l]
            ok = any(l.startswith("Completed") for l in r.stdout.splitlines())
            print(f"compile {os.path.basename(qc)}: {'ok' if ok else 'FAILED'}" + ("".join("\n   " + l for l in bad[:8])))
            if not ok:
                print(r.stdout[-2000:])
                sys.exit(1)
        src = os.path.join(GAMEDIR, "models", mdir)
        for fn in os.listdir(src):
            dst = os.path.join(out_models, fn)
            if os.path.exists(dst):
                os.remove(dst)
            shutil.move(os.path.join(src, fn), dst)
        os.rmdir(src)
        print(f"models -> {out_models}")


if __name__ == "__main__":
    main()
