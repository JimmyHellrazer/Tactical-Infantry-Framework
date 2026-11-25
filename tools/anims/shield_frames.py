"""
TIF human shield (0.38.20): entity placement per frame for the MW19 hostage-taker pair (manifest shield_family,
mwsh_<clip>_<att|vic>), written to tactical_infantry_framework/lua/tif/tactics/sv_shield_data.lua.

The scene is anchored on the captor's raw tag_origin at frame 0 of each clip (it never moves: x ahead, y left). For
every frame of each baked clip, a rigid fit of the raw CoD joints onto the baked SMD's ValveBiped joints (Kabsch, ~5
in residual from the retarget) gives S(f): raw scene -> SMD space. The entity that plays that clip must stand at
E(f) = inv(S(f)) * C in scene space (C: an entity's +x ahead is the SMD's -y: studiomdl turns models +90 deg), so its
baked body lands where the raw scene had it. TIF plays these clips without root motion and sets both entities'
positions / yaws from this table (the bake's own root curve is in another frame and isn't used).

Usage: python shield_frames.py   (after baking mwsh_*; rerun if they're rebaked)
"""
import glob
import os
import sys
import numpy as np

sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep
import cod_to_breen as c2b

SRC = "K:/duglastakedown"
BUILD = r"K:\jimmyproject\tif_mw\build"
OUT = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons\tactical_infantry_framework\lua\tif\tactics\sv_shield_data.lua"
BODY = prep.read_smd(r"K:\jimmyproject\Alex Desert\body_hero_alex_desert\body_hero_alex_desert_LOD0.smd")
PAIRS = [("j_mainroot", "ValveBiped.Bip01_Pelvis"), ("j_spine4", "ValveBiped.Bip01_Spine4"), ("j_wrist_ri", "ValveBiped.Bip01_R_Hand"),
         ("j_wrist_le", "ValveBiped.Bip01_L_Hand"), ("j_elbow_ri", "ValveBiped.Bip01_R_Forearm"), ("j_elbow_le", "ValveBiped.Bip01_L_Forearm"),
         ("j_knee_le", "ValveBiped.Bip01_L_Calf"), ("j_knee_ri", "ValveBiped.Bip01_R_Calf"), ("j_head", "ValveBiped.Bip01_Head1"),
         ("j_ankle_le", "ValveBiped.Bip01_L_Foot"), ("j_ankle_ri", "ValveBiped.Bip01_R_Foot")]
C = np.eye(4)
C[:3, :3] = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], float).T   # entity frame -> SMD frame (+x ahead -> SMD -y, the bakes face -Y; checked: the captor comes out at yaw ~0)
STEP = 2


def poses(smd):
    idx = {n: i for i, (n, _) in enumerate(smd.nodes)}
    out = []
    for fr in range(len(smd.frames)):
        w = c2b.world_pose(smd.nodes, {i: prep.to_rt(v) for i, v in smd.frames[fr][1].items()})
        out.append({n: (np.array(w[i][0]), np.array(w[i][1])) for n, i in idx.items()})
    return out


def fit(A, B):
    ca, cb = A.mean(0), B.mean(0)
    U, _, Vt = np.linalg.svd((A - ca).T @ (B - cb))
    D = np.diag([1, 1, np.sign(np.linalg.det(Vt.T @ U.T))])
    R = Vt.T @ D @ U.T
    S = np.eye(4); S[:3, :3] = R; S[:3, 3] = cb - R @ ca
    return S, float(np.linalg.norm(A @ R.T + S[:3, 3] - B, axis=1).max())


def placements(src, anchor_src, smd_name=None):
    """src: the raw clip this entity plays; anchor_src: the captor clip of the pair (its tag_origin, frame 0, is the
    scene); smd_name: the baked SMD (a trimmed bake is <src>_e<N>)."""
    a = prep.read_seanim("%s/%s.seanim" % (SRC, src))
    cod, _ = prep.seanim_to_smd(a, BODY, {}, False, prep.CM_TO_INCH, inplace=False)
    prep.fill_frames(cod)
    # the scene anchor: the captor's tag_origin, frame 0 of this clip
    att = prep.read_seanim("%s/%s.seanim" % (SRC, anchor_src))
    acod, _ = prep.seanim_to_smd(att, BODY, {}, False, prep.CM_TO_INCH, inplace=False)
    prep.fill_frames(acod)
    anchor = poses(acod)[0]["tag_origin"]
    Ai = np.eye(4); Ai[:3, :3] = anchor[0]; Ai[:3, 3] = anchor[1]
    Ai = np.linalg.inv(Ai)
    smd = prep.read_smd(glob.glob(os.path.join(BUILD, "*", (smd_name or src) + ".smd"))[0]); prep.fill_frames(smd)
    rp, bp = poses(cod), poses(smd)
    out, worst = [], 0
    for fr in range(0, len(bp), STEP):
        A = np.array([(Ai @ np.append(rp[fr][c][1], 1))[:3] for c, v in PAIRS])
        B = np.array([bp[fr][v][1] for c, v in PAIRS])
        S, res = fit(A, B)
        worst = max(worst, res)
        E = np.linalg.inv(S) @ C
        out.append((E[0, 3], E[1, 3], E[2, 3], np.degrees(np.arctan2(E[1, 0], E[0, 0]))))
    if (len(bp) - 1) % STEP:
        fr = len(bp) - 1
        A = np.array([(Ai @ np.append(rp[fr][c][1], 1))[:3] for c, v in PAIRS])
        B = np.array([bp[fr][v][1] for c, v in PAIRS])
        S, res = fit(A, B)
        E = np.linalg.inv(S) @ C
        out.append((E[0, 3], E[1, 3], E[2, 3], np.degrees(np.arctan2(E[1, 0], E[0, 0]))))
    return out, worst, len(bp)


# (role, raw clip, the pair's captor clip = scene anchor, baked SMD name or None)
CP, CH = "cp_hostagetaker_", "thd_2f_020_hostage_"
ROLES = []
for _c in ("grab", "idle", "death", "rescue"):
    ROLES.append(("mwsh_%s_att" % _c, CP + _c + "_attacker", CP + _c + "_attacker", None))
    ROLES.append(("mwsh_%s_vic" % _c, CP + _c + "_victim", CP + _c + "_attacker", None))
# (0.38.28) Clean House: hold pairs, and the outcome pairs (captor shot: his death with her "live"; hostage shot: his
# "live" with her death / headshot death), each anchored on the captor clip it plays with
for _c in ("aim_start", "aim", "idle"):
    ROLES.append(("mwsc_%s_att" % _c, CH + "alqatala_" + _c, CH + "alqatala_" + _c, None))
    ROLES.append(("mwsc_%s_vic" % _c, CH + "civ_" + _c, CH + "alqatala_" + _c, None))
ROLES += [
    ("mwsc_death_att", CH + "alqatala_death", CH + "alqatala_death", CH + "alqatala_death_e90"),
    ("mwsc_live_vic", CH + "civ_live", CH + "alqatala_death", CH + "civ_live_e78"),
    ("mwsc_live_att", CH + "alqatala_live", CH + "alqatala_live", None),
    ("mwsc_death_vic", CH + "civ_death", CH + "alqatala_live", None),
    ("mwsc_death_hs_vic", CH + "civ_death_headshot", CH + "alqatala_live", CH + "civ_death_headshot_e63"),
]

# Clips whose raw scene origin isn't the pair's (checked: the headshot death started 75 in behind him, turned 98 deg):
# moved rigidly so their first frame is the given role's first frame.
ALIGN = {"mwsc_death_hs_vic": "mwsc_aim_vic"}


def main():
    lines = ["-- GENERATED by K:/jimmyproject/tif_mw/shield_frames.py (TIF 0.38.20, Clean House 0.38.28): human shield placements.",
             "-- TIF.ShieldData[clip] = { frames = n, step = s, p = { x, y, z, yaw, ... } }: where the entity playing that clip",
             "-- stands, every s-th frame (and the last), in the scene's frame (the captor's spot at the clip's start: x ahead,",
             "-- y left, z up, degrees). Played without root motion; positions set from this.",
             "TIF = TIF or {}", "TIF.ShieldData = {"]
    done = {}
    for role, src, anchor, smd_name in ROLES:
        p, worst, n = placements(src, anchor, smd_name)
        # (a clip authored at another scene origin: moved rigidly so its first frame starts where ALIGN says)
        if role in ALIGN:
            tx, ty, tz, tyaw = done[ALIGN[role]][0]
            x0, y0, z0, yaw0 = p[0]
            dy = np.radians(tyaw - yaw0)
            c, s = np.cos(dy), np.sin(dy)
            p = [(tx + (x - x0) * c - (y - y0) * s, ty + (x - x0) * s + (y - y0) * c, z, yaw + (tyaw - yaw0)) for x, y, z, yaw in p]
        done[role] = p
        print("%-20s %d fr  fit max %.1f  start (%.1f %.1f %.1f yaw %.1f)  end (%.1f %.1f %.1f yaw %.1f)" % (
            role, n, worst, *p[0], *p[-1]))
        flat = ", ".join("%.1f, %.1f, %.1f, %.1f" % e for e in p)
        lines.append('\t%s = { frames = %d, step = %d, p = { %s } },' % (role, n, STEP, flat))
    lines += ["}", ""]
    open(OUT, "w", newline="\n").write("\n".join(lines))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
