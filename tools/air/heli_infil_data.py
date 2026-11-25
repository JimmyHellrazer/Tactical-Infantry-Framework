"""
TIF air: passenger clip data for a helicopter, from the CoD clips and the model's own tags.

Per seat set (land / rappel / rope) and man: which tag he rides on, where the clip puts him relative to it (CoD
clips are authored on the tag: tag_origin at frame 0 = his place), where he ends (feet on the ground: that gives the
hover height the set needs), and when TIF takes him back (release: code_move / finish notetrack, or computed from
root motion), with the speed he's moving at then (so locomotion carries on without a stop).

Writes addons/tif_air/lua/autorun/server/tif_air_infil.lua (TIF_AIR_INFIL[type][set]) and prints a check table.
The clips themselves are built into tif_mw_anims by the MW manifest (family "heli", roles mwhb_*).

Usage: heli_infil_data.py   (run with a Python that has numpy)
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import heli_build as hb  # noqa: E402

SOURCES = [r"K:\duglastakedown", r"K:\mw22 anims 2\xanims"]
# Shared (the client places the crew dummies from it).
OUT = os.path.join(hb.ADDON, "lua", "autorun", "tif_air_infil.lua")
OLD_OUT = os.path.join(hb.ADDON, "lua", "autorun", "server", "tif_air_infil.lua")
FPS = 30
CM = 1 / 2.54

# Seat sets for the Black Hawk. role: TIF clip role prefix (tif_mw manifest, family "heli").
#   land:   landed, out through both cabin doors (MW19 AI ground exits; 3 a side)
#   rappel: high hover (~20 m), 8 men on two ropes (MW19 campaign rappel; vh_blima_rappel_soldierN on tag_guyN)
# Each set: kind ("land" = on the ground, "rope" = from a hover), men = [(role, tag, idle clip, {exit suffix: clip})].
# Several exits = styles the game picks from (Little Bird bench: run / ready / patrol). Seat order = fill order.
# Tags: found with harness/tag_fit.py (every man of a landed set ends on the model's ground; rope sets agree on one
# hover height). The Mi-8's rope clips and its juggernaut are authored on the body tag, not a seat.
def _mi8_land():
    tags = {"fl1": 7, "fl2": 8, "fl3": 9, "fr1": 0, "fr2": 1, "fr3": 2, "rl1": 12, "rl2": 11, "rl3": 10,
            "rr1": 6, "rr2": 5, "rr3": 4}
    order = ["fl1", "fr1", "fl2", "fr2", "rl1", "rr1", "fl3", "fr3", "rl2", "rr2", "rl3", "rr3"]
    men = [("mwmi_land_" + s, "tag_guy%d" % tags[s], "sdr_mp_veh_mindia8_ground_%s_idle" % s,
            {"exit": "sdr_mp_veh_mindia8_ground_%s_exit" % s}) for s in order]
    # (jug on tag_ground, not the body tag: both put his feet on the ground, but on the body tag he ends at x -164,
    # under the cabin floor; on tag_ground at -202, out the back with the other rear men)
    men.append(("mwmi_land_jug", "tag_ground", "sdr_mp_veh_mindia8_ground_jug_idle",
                {"exit": "sdr_mp_veh_mindia8_ground_jug_exit"}))
    return men


def _mi8_rope():
    side = {"fl": "front_l", "fr": "front_r", "rl": "rear_l", "rr": "rear_r"}
    order = ["fl1", "fr1", "rl1", "rr1", "fl2", "fr2", "rl2", "rr2", "fl3", "fr3", "rl3", "rr3"]
    return [("mwmi_rope_" + s, "body_animate_jnt", "vh_mindia8_%s_%s_idle" % (side[s[:2]], s[2]),
             {"exit": "vh_mindia8_%s_%s_exit" % (side[s[:2]], s[2])}) for s in order]


# CH-53 heavy (MWII palfa): its own infil clips carry no root motion (the slide down isn't in the export), so it
# borrows the Mi-8's: each man keeps his Mi-8 clip (same roles, no new seat clips), moved from his Mi-8 tag onto the
# heavy's matching spot by a shift in the hub frame. Landed: the front-door men onto its front doors (j_door_le/ri
# 187, +-57), the open-back men moved back 130 so they leave down the ramp; heights: its cabin floor sits ~31 over its
# ground, the Mi-8's ~38. Rope: each Mi-8 rope man onto the heavy's rope point (the MWII infil's rope clips hang from
# bone_578d27c4 / 777e4f9a at the front side windows and bone_352e9a26 / 54ee2530 at the back of the ramp).
# A man with a borrow entry rides on "tag_body" (the hub, yaw 0) with his start given in the hub frame.
_GROUND = {"mi8": -165.2, "heavy": -249.4}
_DZ = _GROUND["heavy"] - _GROUND["mi8"] - 7


def _heavy_land():
    out = []
    for role, tag, idle, exits in _mi8_land()[:12]:
        side = role[-3:-1]
        if side in ("fl", "fr"):
            sh = (187.3 - 116.0, (56.9 - 48.5) * (1 if side == "fl" else -1), _DZ)
        else:
            sh = (-130.0, 0.0, _DZ)
        out.append((role, tag, idle, exits, {"from": "mi8", "shift": sh}))
    return out


def _heavy_rope():
    pts = {"fl": ((124.3, 66.2, -76.0), (164.7, 86.3, -118.4)), "fr": ((124.3, -66.2, -76.0), (164.7, -86.3, -118.4)),
           "rl": ((-120.0, 67.0, -76.0), (-354.0, 63.4, -170.4)), "rr": ((-120.0, -67.0, -76.0), (-354.0, -63.4, -170.4))}
    out = []
    for role, tag, idle, exits in _mi8_rope():
        src, dst = pts[role[-3:-1]]
        out.append((role, tag, idle, exits, {"from": "mi8", "shift": tuple(d - s for d, s in zip(dst, src))}))
    return out


# Crew (client-side dummies, never get out): pilots always; crew chiefs only in a drop whose men leave their spot
# free (a chief standing within CHIEF_CLEAR of any seat or exit start would stand inside a man).
# (role, tag, idle clip). Pilot clips sit on tag_pilot1 / 2 (Mi-8: on the body tag, landing on its pilot seats).
CREW = {
    "blackhawk": {
        "pilots": [("mwhb_pilot", "tag_pilot1", "vh_blima_rappel_pilot"), ("mwhb_copilot", "tag_pilot2", "vh_blima_rappel_copilot")],
        # standing at the front of the cabin, facing aft (on tag_guy9, the floor-level centre spot)
        "chiefs": [("mwhb_chief", "tag_guy9", "reb_com_vh_blima_chief_idle"), ("mwhb_chief2", "tag_guy9", "reb_com_vh_blima_chief2_idle")],
    },
    "littlebird": {
        "pilots": [("mwlb_pilot", "tag_pilot1", "reb_vh_lbravo_pilot_idle_search01"),
                   ("mwlb_copilot", "tag_pilot2", "reb_vh_lbravo_copilot_idle_search01")],
        "chiefs": [],
    },
    "mi8": {
        "pilots": [("mwmi_pilot", "body_animate_jnt", "vh_mindia8_pilot_idle"), ("mwmi_copilot", "body_animate_jnt", "vh_mindia8_copilot_idle")],
        "chiefs": [],
    },
    "heavy": {
        "pilots": [("mwhv_pilot", "tag_driver", "reb_vh_palfa_driver_idle_search01"), ("mwhv_copilot", "tag_passenger", "reb_vh_palfa_pass_idle_search01")],
        "chiefs": [],
    },
}
CHIEF_CLEAR = 26

SETS = {
    "blackhawk": {
        "land": ("land", [
            ("mwhb_land_l1", "tag_guy7", "sdr_mp_veh_blima_ground_l1_idle", {"exit": "sdr_mp_veh_blima_ground_l1_exit"}),
            ("mwhb_land_r1", "tag_guy5", "sdr_mp_veh_blima_ground_r1_idle", {"exit": "sdr_mp_veh_blima_ground_r1_exit"}),
            ("mwhb_land_l2", "tag_guy8", "sdr_mp_veh_blima_ground_l2_idle", {"exit": "sdr_mp_veh_blima_ground_l2_exit"}),
            ("mwhb_land_r2", "tag_guy6", "sdr_mp_veh_blima_ground_r2_idle", {"exit": "sdr_mp_veh_blima_ground_r2_exit"}),
            ("mwhb_land_l3", "tag_guy1", "sdr_mp_veh_blima_ground_l3_idle", {"exit": "sdr_mp_veh_blima_ground_l3_exit"}),
            ("mwhb_land_r3", "tag_guy0", "sdr_mp_veh_blima_ground_r3_idle", {"exit": "sdr_mp_veh_blima_ground_r3_exit"}),
        ]),
        "rappel": ("rope", [("mwhb_rap_%d" % n, "tag_guy%d" % n, "vh_blima_rappel_soldier%d_idle" % n,
                             {"drop": "vh_blima_rappel_soldier%d_drop" % n}) for n in (0, 1, 2, 3, 4, 6, 8, 9)]),
        # campaign fast-rope (MW19 reb_com_vh_blima_guy0..05, ~575 hover, two ropes): seated on tag_guy0-5. Which man
        # sits on which tag isn't in the names: matched by where each one's slide runs down a rope (1.5-19 off,
        # harness: session scan 2026-11-14). Crew chiefs stand clear of this set.
        # MP intro fast-rope (MW19 mp_infil_blima_[r_]guy01-03): two mirrored 3-man teams, one per rope (together they
        # walk through each other in the cabin), authored in the helicopter's own frame (tag_body = the hub, yaw 0);
        # the 5-6 s cabin lead-in is cut (manifest trim), the gun-raise tail by TIF's hand-back on landing.
        "mpleft": ("rope", [("mwhb_mpl_%d" % n, "tag_body", ("mp_infil_blima_guy0%d" % n, 180),
                             {"exit": ("mp_infil_blima_guy0%d" % n, 180)}) for n in (1, 2, 3)]),
        "mpright": ("rope", [("mwhb_mpr_%d" % n, "tag_body", ("mp_infil_blima_r_guy0%d" % n, 150),
                              {"exit": ("mp_infil_blima_r_guy0%d" % n, 150)}) for n in (1, 2, 3)]),
        "fastrope": ("rope", [("mwhb_fr_%s" % g, "tag_guy%d" % t, "reb_com_vh_blima_guy%s_idle" % g,
                               {"exit": "reb_com_vh_blima_guy%s_exit" % g})
                              for g, t in (("0", 0), ("03", 1), ("01", 2), ("04", 3), ("02", 4), ("05", 5))]),
    },
    "littlebird": {
        # MP AI ground exits off the benches
        "land": ("land", [("mwlb_land_%s%d" % (s, n), "tag_passenger%d" % (n + (0 if s == "l" else 3)),
                           "sdr_mp_veh_lbravo_ground_%s%d_idle" % (s, n), {"exit": "sdr_mp_veh_lbravo_ground_%s%d_exit" % (s, n)})
                          for n in (1, 2, 3) for s in ("l", "r")]),
        # campaign AI bench hop-offs: run (straight into a run), ready (gun up, stops), patrol (walks off)
        "bench": ("land", [("mwlb_bench_%d" % g, "tag_passenger%d" % g, "reb_vh_lbravo_guy%d_idle_search01" % g,
                            {"run": "reb_vh_lbravo_guy%d_exit_combat_run" % g, "ready": "reb_vh_lbravo_guy%d_exit_combat_idle" % g,
                             "patrol": "reb_vh_lbravo_guy%d_exit_patrol" % g})
                           for g in (1, 4, 2, 5, 3, 6)]),
    },
    "mi8": {
        "land": ("land", _mi8_land()),
        "rope": ("rope", _mi8_rope()),
    },
    "heavy": {
        "land": ("land", _heavy_land()),
        "rope": ("rope", _heavy_rope()),
    },
}


def _trim(anim, fr):
    """Same cut as tif_mw_build.py trim_start: the clip from frame fr on."""
    lerp = {"loc": prep.vlerp, "rot": prep.slerp, "scale": prep.vlerp}
    out = dict(anim)
    out["bones"] = {n: {k: [(0, prep.sample_keys(keys, fr, lerp.get(k, prep.vlerp)))] + [(f - fr, v) for f, v in keys if f > fr]
                        for k, keys in b.items() if keys} for n, b in anim["bones"].items()}
    out["frames"] = max(2, anim["frames"] - fr)
    out["notes"] = [(f - fr, nm) for f, nm in anim.get("notes", []) if f >= fr]
    return out


def load(spec):
    """A clip: "name", or ("name", frames cut from its start) as the manifest's trim builds it."""
    if isinstance(spec, tuple):
        return _trim(prep.read_seanim(find(spec[0])), spec[1])
    return prep.read_seanim(find(spec))


def built_name(spec):
    return "%s_t%d" % spec if isinstance(spec, tuple) else spec


def find(name):
    for d in SOURCES:
        p = os.path.join(d, name + ".seanim")
        if os.path.exists(p):
            return p
    raise FileNotFoundError(name)


def tag_frames(vid):
    cfg = hb.VEHICLES[vid]
    nodes, skel, _, _ = hb.read_smd_skeleton(cfg["smd"])
    W = hb.world_matrices(nodes, skel)
    out = {}
    for i, (n, _) in nodes.items():
        M = W[i]
        out[n] = (M[:3, 3].copy(), math.degrees(math.atan2(M[1, 0], M[0, 0])))
    return out


def start_of(anim):
    """tag_origin at frame 0 relative to the clip's frame (the tag): (x, y, z) inches, yaw degrees."""
    tag = anim["bones"].get("tag_origin", {})
    loc = tag.get("loc")
    rot = tag.get("rot")
    p = [v * CM for v in prep.sample_keys(loc, 0, prep.vlerp)] if loc else [0.0, 0.0, 0.0]
    if rot:
        m = prep.quat_to_matrix(prep.sample_keys(rot, 0, prep.slerp))
        yaw = math.degrees(math.atan2(m[1][0], m[0][0]))
    else:
        yaw = 0.0
    return np.array(p), yaw


def release(anim, track):
    """Frame TIF takes the man back, and his speed then (frame-0 space, inches / s, x fwd y left)."""
    n = len(track)
    # code_move = CoD lets the AI move on from here. "finish" is NOT used: the AI exits reach it after stopping to aim
    # (Mi-8 ropes: ~3 s standing at the bottom), the wait the user doesn't want.
    notes = {name.lower().strip(): fr for fr, name in anim["notes"]}
    fr = notes.get("code_move")
    pos = np.array([t[:3] for t in track])
    vel = np.zeros_like(pos)
    vel[1:] = (pos[1:] - pos[:-1]) * FPS
    hs = np.hypot(vel[:, 0], vel[:, 1])
    zend = pos[-1, 2]
    how = "code_move"
    if fr is None:
        # Feet down (within 3 of the final height) and still moving well (>= 45% of the peak ground speed after
        # touchdown): hand over then; else 0.35 s after touchdown.
        down = next((f for f in range(n) if abs(pos[f, 2] - zend) < 3 and all(abs(pos[g, 2] - zend) < 3 for g in range(f, n))), n - 1)
        peak = hs[down:].max() if down < n else 0
        if peak > 30:
            after = int(np.argmax(hs[down:])) + down
            fr = next((f for f in range(after, n) if hs[f] < 0.45 * peak), n - 1)
            how = "speed"
        else:
            fr = min(n - 1, down + int(0.35 * FPS))
            how = "touchdown"
    fr = max(1, min(n - 1, fr))
    w = max(1, int(0.15 * FPS))
    v = (pos[fr] - pos[max(0, fr - w)]) * FPS / (fr - max(0, fr - w))
    return fr, v, how


MW_BUILD = r"K:\jimmyproject\tif_mw\build\heli"
CROUCH_PELVIS = 30  # pelvis lower than this over his feet = crouched (standing ~34-38)


def crouched_at(clip, frame):
    """Is he crouched at this frame of the built (ValveBiped) clip? None if the clip isn't built yet."""
    p = os.path.join(MW_BUILD, clip + ".smd")
    if not os.path.exists(p):
        return None
    import cod_to_breen as c2b
    smd = prep.read_smd(p)
    prep.fill_frames(smd)
    names = [n for n, _ in smd.nodes]
    pel = names.index("ValveBiped.Bip01_Pelvis")
    bones = smd.frames[min(frame, len(smd.frames) - 1)][1]
    w = c2b.world_pose(smd.nodes, {i: prep.to_rt(v) for i, v in bones.items()})
    # (over the ground: the clip's root is on the ground at the hand-back; measured over the lowest foot, a running
    # stride with one foot up read as crouched)
    return w[pel][1][2] < CROUCH_PELVIS


def lua(v):
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join("%s = %s" % (k, lua(x)) for k, x in v.items()) + " }"
    if isinstance(v, bool):
        return "true" if v else "false"
    return ("%.2f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def main():
    lines = ["-- Generated by K:/jimmyproject/tif_air/heli_infil_data.py: passenger seats and dismount data per",
             "-- helicopter (TIF tif/air/sv_air_ride.lua; crew dummies: entities/tif_heli.lua). Do not edit by hand.",
             "if SERVER then AddCSLuaFile() end",
             "TIF_AIR_INFIL = TIF_AIR_INFIL or {}"]
    for vid, sets in SETS.items():
        tags = tag_frames(vid)
        lines.append('TIF_AIR_INFIL["%s"] = {' % vid)
        # Crew dummies: where each sits / stands (tag + the idle's own start offset).
        crew = CREW.get(vid, {"pilots": [], "chiefs": []})
        crew_rows, chief_pos = {"pilots": [], "chiefs": []}, []
        for group in ("pilots", "chiefs"):
            for role, tag, clip in crew[group]:
                tp, tyaw = tags[tag]
                s0, y0 = start_of(prep.read_seanim(find(clip)))
                c, s = math.cos(math.radians(tyaw)), math.sin(math.radians(tyaw))
                pos = tp + np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]]) @ s0
                print("  crew %-12s %-16s at (%6.1f %6.1f %6.1f) yaw %6.1f" % (role, tag, pos[0], pos[1], pos[2], tyaw + y0))
                crew_rows[group].append({"role": role, "tag": tag, "off": [round(float(x), 2) for x in s0], "yaw": round(y0, 2)})
                if group == "chiefs":
                    chief_pos.append(pos)
        for sid, (kind, men) in sets.items():
            rows, hubs, pts = [], [], []
            print("== %s %s (%s)" % (vid, sid, kind))
            src_tags = {}
            for man in men:
                role, tag, idle, exits = man[:4]
                borrow = man[4] if len(man) > 4 else None
                if borrow:
                    st = src_tags.get(borrow["from"]) or tag_frames(borrow["from"])
                    src_tags[borrow["from"]] = st
                    tp, tyaw = st[tag]
                    tp = tp + np.array(borrow["shift"])
                else:
                    tp, tyaw = tags[tag]
                a_idle = load(idle)
                s_idle, y_idle = start_of(a_idle)
                c, s = math.cos(math.radians(tyaw)), math.sin(math.radians(tyaw))
                R = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
                row = {"role": role, "tag": "tag_body" if borrow else tag, "exits": {}}
                for suffix, exitc in exits.items():
                    a_exit = load(exitc)
                    s0, y0 = start_of(a_exit)
                    track = prep.root_track(a_exit)
                    fr, v, how = release(a_exit, track)
                    n = len(track)
                    start = tp + R @ s0
                    syaw = tyaw + y0
                    c2, s2 = math.cos(math.radians(syaw)), math.sin(math.radians(syaw))
                    R2 = np.array([[c2, -s2, 0], [s2, c2, 0], [0, 0, 1]])
                    end = start + R2 @ np.array(track[-1][:3])
                    rel = start + R2 @ np.array(track[fr][:3])
                    pts.append(start)
                    pts.append(tp + R @ s_idle)
                    hub = -end[2]  # his feet end on the ground: hub height above ground
                    hubs.append(hub)
                    print("  %-16s %-5s %-16s start (%6.1f %6.1f %6.1f) yaw %6.1f | idle gap %4.1f | end (%6.1f %6.1f) "
                          "hub %6.1f | release %3d/%3d (%s) at (%6.1f %6.1f) %5.0f u/s" % (
                              role, suffix, tag, start[0], start[1], start[2], syaw, float(np.linalg.norm(s_idle - s0)),
                              end[0], end[1], hub, fr, n - 1, how, rel[0], rel[1], float(np.hypot(*v[:2]))))
                    # The seat itself is where the idle sits (the exits start there too: idle gap ~0). Borrowed men:
                    # their whole start in the hub frame (they ride on tag_body, yaw 0).
                    if borrow:
                        si = tp + R @ s_idle
                        row["off"], row["yaw"] = [round(float(x), 2) for x in si], round(tyaw + y_idle, 2)
                        eo, ey = start, syaw
                    else:
                        row["off"], row["yaw"] = [round(float(x), 2) for x in s_idle], round(y_idle, 2)
                        eo, ey = s0, y0
                    row["exits"][suffix] = {"off": [round(float(x), 2) for x in eo], "yaw": round(ey, 2),
                                            "release": round(fr / max(1, n - 1), 3),
                                            "vel": [round(float(v[0]), 1), round(float(v[1]), 1)]}
                    # Lands crouched: TIF keeps him down, gun up, until the helicopter has gone (user, 0.25.0).
                    if crouched_at(built_name(exitc), fr):
                        row["exits"][suffix]["crouch"] = True
                rows.append(row)
            spread = max(hubs) - min(hubs)
            print("  hub height %.1f (spread %.1f)" % (sum(hubs) / len(hubs), spread))
            lines.append("\t%s = {" % sid)
            lines.append('\t\tkind = "%s",' % kind)
            lines.append("\t\thub = %s, -- hub height above the ground the clips are made for" % lua(round(sum(hubs) / len(hubs), 1)))
            # Crew chiefs that stand clear of every man of this set (seats and exit starts).
            ok = [i + 1 for i, cp in enumerate(chief_pos)
                  if min(float(np.linalg.norm((cp - p)[:2])) for p in pts) > CHIEF_CLEAR]
            print("  chiefs clear in this set: %s" % (ok or "none"))
            lines.append("\t\tchiefs = %s, -- crew chiefs (crew.chiefs) that stand clear of these men" % lua(ok))
            lines.append("\t\tmen = {")
            for r in rows:
                lines.append("\t\t\t%s," % lua(r))
            lines.append("\t\t},")
            lines.append("\t},")
        lines.append("\tcrew = %s," % lua(crew_rows))
        lines.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    if os.path.exists(OLD_OUT):  # (server-only before 0.24.0)
        os.remove(OLD_OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
