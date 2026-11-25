"""
TIF MW cars: soldier seat data per car, from the CoD seat clips and the car's own tags (VEHICLE_PLAN.md stage 2).

CoD seat clips are authored on a vehicle tag (tag_origin at frame 0 = the man's place relative to it): MWII sets on
tag_seat_N (idles on the tag, entries from the ground beside the door to the tag, exits from the tag to the ground);
MW19 campaign sets ("reb_vh_<car>_<role>_*") on the tag named like the role (tag_driver, tag_bed_guy1, tag_cab1...)
or, for some cars, a point no tag marks (seat "at"). A seat is placed by its idle on its tag.

Missing clips are borrowed from a similar seat of another car (clip names starting "~"): those are placed from the
seat itself (an exit starts on the seat; an entry starts where its root motion, run backwards from the seat, puts
it), and TIF's warp lands them on the seat / the ground. The door swing for an entry / exit is the game's own
"<clip>_geo_door" clip when there is one; otherwise, for seats with a door, a plain swing about the hinge (DOOR_SWING
degrees, out and back, timed to the clip).

Per seat (Glide seat n, the car's seat_tags order in car_build.py):
  role  = clip role prefix in tif_mw_anims (manifest family "car": <role>_idle, _entry, _exit_<style>[_<side>])
  lp / lyaw   = where he sits (car-local, CoD frame = the model's frame)
  entry       = { role, lp, lyaw (start, on the ground), door }   (none: TIF puts him in from the door)
  exits       = { <style> = { { role, release (0..1), vel {x, y}, door, side, [lp, lyaw] }, ... } }
                styles run / idle / combat; lp / lyaw only when the clip starts off the seat
  door        = { bone, rate (keys / s), keys = { {p, y, r}, ... } }   (bone angles from closed, Source order)
  gunner      = role of a gun-up loop: he turns to his enemy and fires from the seat (bed men)

Writes addons/tif_mw_cars/lua/tif_mw_cars/data/<car>_seats.lua (TIF_MW_CAR_SEATS[car]). The clip roles are built
by the MW manifest (K:/jimmyproject/tif_mw/manifest.py, family "car"); car_seat_roles() there lists the same clips.

Usage: car_seat_data.py [car ...]   (default: all cars with SEATS)
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as prep  # noqa: E402
import heli_build as hb  # noqa: E402
import car_build as cb  # noqa: E402
import heli_infil_data as hid  # noqa: E402

DOOR_RATE = 15  # door keys per second
DOOR_SWING = 62  # degrees, for doors without the game's own swing clip

RAMC = "iw9_veh_pickup_fullsize_2014_"  # RAM clips, the usual lenders


def B(clip):
    """A borrowed clip (another car's): placed from the seat."""
    return "~" + clip


def clean(clip):
    return clip[1:] if clip and clip.startswith("~") else clip


def borrowed(clip):
    return bool(clip) and clip.startswith("~")


def pickup_seats(pre, rp, idle_of):
    """The MWII full-size pickup seat set (RAM 1500 and its techo-armour version).
    pre: clip prefix; rp: role prefix; idle_of(n): cab seat n's idle clip."""
    seats = []
    for n in range(4):  # cab: in and out through its own door
        s = "%sseat_%d_" % (pre, n)
        seats.append({"n": n, "role": "%s_s%d" % (rp, n), "idle": idle_of(n), "entry": s + "entry", "door": True,
                      "exits": {"run": [(s + "exit_run", None)], "idle": [(s + "exit_idle", None)],
                                "combat": [(s + "exit_combat_idle", None)]}})

    def bed(n, start, sides):
        s = "%sseat_%d_" % (pre, n)
        exits = {}
        for style, suf in (("run", "run"), ("idle", "idle"), ("combat", "combat_idle")):
            exits[style] = [(s + "%s_exit_%s_%s" % (start, d, suf), side) for d, side in sides]
        return exits

    # bed: the centre man kneels behind the cab (out over either side), two crouch at the tailgate; all three are
    # gunners (their seat pose is already gun-up)
    seats.append({"n": 4, "role": "%s_s4" % rp, "hold": pre + "seat_4_entry_combat_idle_8",
                  "entry": pre + "seat_4_entry_combat_idle_8", "door": False, "gunner": "idle",
                  "exits": bed(4, "combat_idle_8", (("4", "l"), ("6", "r")))})
    seats.append({"n": 5, "role": "%s_s5" % rp, "hold": pre + "seat_5_entry_highcrouch_8",
                  "entry": pre + "seat_5_entry_highcrouch_8", "door": False, "gunner": "idle",
                  "exits": bed(5, "highcrouch_8", (("4", "l"),))})
    seats.append({"n": 6, "role": "%s_s6" % rp, "hold": pre + "seat_6_entry_highcrouch_8",
                  "entry": pre + "seat_6_entry_highcrouch_8", "door": False, "gunner": "idle",
                  "exits": bed(6, "highcrouch_8", (("6", "r"),))})
    return seats


def mwii_cab(pre, rp, n, tag=None, run="exit_combat_run", calm="exit_idle", gun="exit_combat_idle", idle="idle",
             entry="entry"):
    """An MWII cab seat (tag_seat_N): idle, entry, three exits, door."""
    s = "%sseat_%d_" % (pre, n)
    return {"n": n, "tag": tag or "tag_seat_%d" % n, "role": "%s_s%d" % (rp, n), "idle": s + idle,
            "entry": s + entry, "door": True,
            "exits": {"run": [(s + run, None)], "idle": [(s + calm, None)], "combat": [(s + gun, None)]}}


def ram_cab(n, tag, rp, k):
    """A cab seat with no clips of its own: the RAM's seat n, borrowed whole."""
    s = "%sseat_%d_" % (RAMC, n)
    return {"n": k, "tag": tag, "role": "%s_s%d" % (rp, k), "idle": B(s + "idle"), "entry": B(s + "entry"),
            "door": True, "exits": {"run": [(B(s + "exit_run"), None)], "idle": [(B(s + "exit_idle"), None)],
                                    "combat": [(B(s + "exit_combat_idle"), None)]}}


def mw19(pre, who, rp, k, tag=None, at=None, entry=None, door=True, gunner=False, sides=None):
    """An MW19 campaign seat (reb_vh_<car>_<who>_*): idle_search01, exits combat_run / patrol / combat_idle, the
    car's own get_in if it has one, else `entry` (borrowed). sides: exit variants per side ("_l" / "_r")."""
    s = "%s%s_" % (pre, who)
    sfx = [("_" + d, d) for d in sides] if sides else [("", None)]
    seat = {"n": k, "tag": tag, "at": at, "role": "%s_s%d" % (rp, k), "idle": s + "idle_search01",
            "entry": entry if entry is not None else s + "get_in", "door": door,
            "exits": {"run": [(s + "exit_combat_run" + x, d) for x, d in sfx],
                      "idle": [(s + "exit_patrol" + x, d) for x, d in sfx],
                      "combat": [(s + "exit_combat_idle" + x, d) for x, d in sfx]}}
    if gunner:
        seat["gunner_clip"] = s + "idle_combat01"
    return seat


def rider(k, tag, rp, idle, at=None):
    """A seat with only a pose (no clips to get in / out: TIF puts him in and out from the Glide seat's door)."""
    seat = {"n": k, "tag": tag, "at": at, "role": "%s_s%d" % (rp, k), "entry": None, "door": False, "exits": {}}
    seat["hold" if idle[1] else "idle"] = idle[0]
    return seat


TD, HX, DF, MT = "reb_vh_techo_", "reb_vh_pindia_", "reb_vh_decho_", "reb_vh_mkilo_"
SUV, OVL, KZ = "iw9_veh_suv_1996_", "iw9_veh_suv_overland_2016_", "iw9_veh_cargo_truck_"
# Defender: its rear clips sit on the centre line at the driver tag's height (no tag there)
DF_C = (3.2, 0.0, 20.0, 0.0)
# bed entries borrowed from the RAM's tailgate crouchers: from the left / right side
BED_L, BED_R = B(RAMC + "seat_5_entry_highcrouch_8"), B(RAMC + "seat_6_entry_highcrouch_8")

SEATS = {
    "ram1500": pickup_seats(RAMC, "mwrp", lambda n: RAMC + "seat_%d_idle" % n),
    "ram1500_armor": pickup_seats("iw9_veh_pickup_fullsize_techoarmor_", "mwra",
                                  lambda n: "iw9_ai_veh_pickup_fullsize_techoarmor_seat_%d_idle" % n),
    "cherokee": [mwii_cab(SUV, "mwck", 0), ram_cab(1, "tag_seat_1", "mwck", 1), mwii_cab(SUV, "mwck", 2),
                 mwii_cab(SUV, "mwck", 3)],
    "choptop": [mwii_cab(OVL, "mwct", n) for n in range(4)],
    "kamaz": [mwii_cab(KZ, "mwkz", 0, calm="exit"), mwii_cab(KZ, "mwkz", 1, calm="exit")]
             + [rider(k, "tag_seat_wm_%d" % k, "mwkz", (RAMC + "seat_5_entry_highcrouch_8", True)) for k in (2, 3, 4, 5)],
    "hilux": [mw19(HX, "driver", "mwhx", 0, "tag_driver", door=False), mw19(HX, "pass", "mwhx", 1, "tag_passenger", door=False),
              mw19(HX, "bed_guy3", "mwhx", 2, "tag_bed_guy3", entry=BED_L, door=False, gunner=True),
              mw19(HX, "bed_guy2", "mwhx", 3, "tag_bed_guy2", entry=BED_R, door=False, gunner=True),
              mw19(HX, "bed_guy4", "mwhx", 4, "tag_bed_guy4", entry=BED_L, door=False, gunner=True),
              mw19(HX, "bed_guy1", "mwhx", 5, "tag_bed_guy1", entry=BED_R, door=False, gunner=True)],
    "tundra": [mw19(TD, "driver", "mwtd", 0, "tag_driver", entry=B(RAMC + "seat_0_entry")),
               mw19(TD, "pass", "mwtd", 1, "tag_passenger", entry=B(RAMC + "seat_1_entry")),
               mw19(TD, "cab1", "mwtd", 2, "tag_cab1", entry=B(RAMC + "seat_2_entry")),
               mw19(TD, "cab2", "mwtd", 3, "tag_cab2", entry=B(RAMC + "seat_3_entry")),
               mw19(TD, "guy5", "mwtd", 4, "tag_bed_center", entry=B(RAMC + "seat_4_entry_combat_idle_8"), door=False,
                    gunner=True, sides=("l", "r")),
               mw19(TD, "bed_guy1", "mwtd", 5, "tag_bed1", entry=BED_R, door=False, gunner=True),
               mw19(TD, "bed_guy2", "mwtd", 6, "tag_bed2", entry=BED_L, door=False, gunner=True)],
    "defender": [mw19(DF, "driver", "mwdf", 0, "tag_driver", entry=B(RAMC + "seat_0_entry")),
                 mw19(DF, "pass", "mwdf", 1, "tag_passenger", entry=B(RAMC + "seat_1_entry")),
                 mw19(DF, "cab1", "mwdf", 2, at=DF_C, entry=B(RAMC + "seat_3_entry")),
                 mw19(DF, "cab2", "mwdf", 3, at=DF_C, entry=B(RAMC + "seat_2_entry")),
                 mw19(DF, "cab3", "mwdf", 4, at=DF_C, entry=False, door=False),
                 mw19(DF, "cab4", "mwdf", 5, at=DF_C, entry=False, door=False)],
    "mtvr": [mw19(MT, "driver", "mwmt", 0, "tag_driver"),
             mw19(MT, "pass", "mwmt", 1, at=(60.9, -24.0, 75.2, 0.0))]
            + [rider(k, "tag_seat_%d" % t, "mwmt", (B(RAMC + "seat_3_idle"), False))
               for k, t in zip(range(2, 10), (2, 6, 3, 7, 4, 8, 5, 9))],
}


def exists(clip):
    try:
        hid.find(clean(clip))
        return True
    except FileNotFoundError:
        return False


def resolve_exits(seat):
    """Drop variants whose clip doesn't exist; a style with none borrows from another (pickup 2014 bed seat 4 has no
    run out of the kneel: it uses the combat exit)."""
    out = {}
    for style, vs in seat["exits"].items():
        ok = [v for v in vs if exists(v[0])]
        if ok:
            out[style] = ok
    for style, alt in (("run", "combat"), ("combat", "run"), ("idle", "combat"), ("idle", "run")):
        if style not in out and alt in out:
            out[style] = out[alt]
    return out


def entry_of(seat):
    e = seat.get("entry")
    return e if e and exists(e) else None


def idle_of(seat):
    """(clip, held?) of the seat's pose: its idle, or a held last frame."""
    if seat.get("hold"):
        return seat["hold"], True
    if exists(seat.get("idle")):
        return seat["idle"], False
    return None, False


def role_name(seat, kind, style=None, side=None):
    r = "%s_%s" % (seat["role"], kind)
    if style:
        r += "_" + style
    if side:
        r += "_" + side
    return r


def car_seat_roles(car):
    """(role, clip, opts) for the manifest, same names as the data uses."""
    out = []
    k = {"loop": False, "center": False}
    for seat in SEATS[car]:
        clip, held = idle_of(seat)
        if not clip:
            continue
        if held:
            out.append((role_name(seat, "idle"), clean(clip), dict(k, loop=True, hold="last")))
        else:
            out.append((role_name(seat, "idle"), clean(clip), dict(k, loop=True)))
        if entry_of(seat):
            out.append((role_name(seat, "entry"), clean(seat["entry"]), k))
        for style, vs in resolve_exits(seat).items():
            for c, side in vs:
                out.append((role_name(seat, "exit", style, side), clean(c), k))
        if seat.get("gunner_clip") and exists(seat["gunner_clip"]):
            out.append((role_name(seat, "aim"), clean(seat["gunner_clip"]), dict(k, loop=True)))
    return out


def euler(m):
    """Source Angle (pitch, yaw, roll) of a rotation matrix (rows = world axes, columns = rotated axes)."""
    yaw = math.degrees(math.atan2(m[1][0], m[0][0]))
    pitch = math.degrees(math.atan2(-m[2][0], math.hypot(m[0][0], m[1][0])))
    roll = math.degrees(math.atan2(m[2][1], m[2][2]))
    return [round(pitch, 1), round(yaw, 1), round(roll, 1)]


# Cars whose own door clips look wrong use another car's (user: the armoured RAM's door swings were strange; the
# plain RAM's are near identical in timing): clip prefix -> prefix to take the door clip from.
DOOR_FROM = {"iw9_veh_pickup_fullsize_techoarmor_": "iw9_veh_pickup_fullsize_2014_"}


def door_curve(clip):
    """The door's motion for a seat clip, from <clip>_geo_door: { bone, rate, keys }, or None."""
    if borrowed(clip):
        return None  # (another car's door)
    for a, b in DOOR_FROM.items():
        if clip.startswith(a):
            clip = b + clip[len(a):]
    name = clip + "_geo_door"
    if not exists(name):
        return None
    a = prep.read_seanim(hid.find(name))
    best, span = None, 0
    for bone, b in a["bones"].items():
        keys = b.get("rot")
        if not bone.startswith("tag_door") or not keys:
            continue
        q0 = keys[0][1]
        r0 = np.array(prep.quat_to_matrix(q0))
        ang = max(math.degrees(math.acos(max(-1, min(1, (np.trace(r0.T @ np.array(prep.quat_to_matrix(q))) - 1) / 2))))
                  for _, q in keys)
        if ang > span:
            best, span = bone, ang
    if not best or span < 2:
        return None
    keys = a["bones"][best]["rot"]
    r0 = np.array(prep.quat_to_matrix(prep.sample_keys(keys, 0, prep.slerp)))
    n = a["frames"]
    step = hid.FPS / DOOR_RATE
    out = []
    f = 0.0
    while f <= n - 1 + 1e-6:
        r = np.array(prep.quat_to_matrix(prep.sample_keys(keys, f, prep.slerp)))
        out.append(euler(r0.T @ r))
        f += step
    # trim the closed tail (all zeros)
    while len(out) > 2 and max(abs(v) for v in out[-1]) < 0.05 and max(abs(v) for v in out[-2]) < 0.05:
        out.pop()
    return {"bone": best, "rate": DOOR_RATE, "keys": out, "peak": round(span, 1)}


def smooth(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def swing_curve(door, Wd, dur, kind):
    """A plain door swing for a clip without the game's door clip: about the hinge (the door bone; vertical axis in
    the model), out DOOR_SWING degrees and back. entry: opens 5-25%, shuts 78-95%; exit: opens 0-18%, shuts 70-90%."""
    side = 1 if Wd[1, 3] > 0 else -1  # left doors swing to -yaw (their back edge out to +y), right doors to +yaw
    R = Wd[:3, :3]
    o0, o1, c0, c1 = (0.05, 0.25, 0.78, 0.95) if kind == "in" else (0.0, 0.18, 0.70, 0.90)
    n = max(2, int(dur * DOOR_RATE) + 1)
    keys = []
    for i in range(n):
        u = i / (n - 1)
        k = smooth((u - o0) / (o1 - o0)) * (1 - smooth((u - c0) / (c1 - c0)))
        a = math.radians(-side * DOOR_SWING * k)
        Rz = np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])
        keys.append(euler(R.T @ Rz @ R))
    return {"bone": door, "rate": DOOR_RATE, "keys": keys, "peak": DOOR_SWING, "plain": True}


def rot(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def r2(v):
    return [round(float(x), 2) for x in v]


def place(clip, tp, tyaw):
    """Where a clip authored on a tag at (tp, tyaw) starts: position, yaw; and its root track."""
    a = prep.read_seanim(hid.find(clean(clip)))
    s0, y0 = hid.start_of(a)
    return tp + rot(tyaw) @ s0, tyaw + y0, prep.root_track(a), a


def back_from(lp, lyaw, track):
    """Start of a clip whose root motion ends at (lp, lyaw): run the motion backwards."""
    x, y, z, yaw = track[-1][:4] if len(track[-1]) > 3 else (*track[-1][:3], 0.0)
    syaw = lyaw - yaw
    return lp - rot(syaw) @ np.array([x, y, z]), syaw


def build(car):
    cfg = cb.CARS_CFG[car]
    nodes, skel, _, _ = hb.read_smd_skeleton(cb.export_smd(cfg))
    W = hb.world_matrices(nodes, skel)
    by = {n: i for i, (n, _) in nodes.items()}
    tags = {n: (W[i][:3, 3].copy(), math.degrees(math.atan2(W[i][1, 0], W[i][0, 0]))) for i, (n, _) in nodes.items()}
    gz = tags["tag_origin_static"][0][2] if "tag_origin_static" in tags else 0.0
    doors = [n for n in by if n.startswith("tag_door_") and n.count("_") == 3]
    rows = []
    print("== %s (ground z %.1f)" % (car, gz))
    for k, seat in enumerate(SEATS[car]):
        if seat.get("at"):
            x, y, z, yw = seat["at"]
            tp, tyaw, tag = np.array([x, y, z], float), yw, None
        else:
            tag = seat.get("tag") or "tag_seat_%d" % seat["n"]
            tp, tyaw = tags[tag]
        clip, held = idle_of(seat)
        if not clip:
            print("  seat %d %s: no idle clip, left out" % (k, seat["role"]))
            continue
        if borrowed(clip):
            lp, lyaw = tp.copy(), tyaw
        else:
            st, sy, tr, _ = place(clip, tp, tyaw)
            if held:  # the held pose is the clip's last frame: where it ends
                lp, lyaw = st + rot(sy) @ np.array(tr[-1][:3]), sy + tr[-1][3]
            else:
                lp, lyaw = st, sy
        row = {"n": k + 1, "tag": tag, "role": seat["role"], "lp": r2(lp), "lyaw": round(lyaw, 1),
               "idle": role_name(seat, "idle")}
        # the door this seat uses (nearest on its side, hinge ahead of the seat)
        door = None
        if seat.get("door") and doors:
            side = [d for d in doors if (W[by[d]][1, 3] > 0) == (lp[1] > 0)]
            if side:
                door = min(side, key=lambda d: abs(W[by[d]][0, 3] - 20 - lp[0]))

        def door_for(c, kind, nframes):
            d = door_curve(c)
            if d or not door:
                return d
            return swing_curve(door, W[by[door]], nframes / hid.FPS, kind)

        msg = ""
        e_clip = entry_of(seat)
        if e_clip:
            # Placed backwards from the seat, where every entry ends (some MWII entries are authored from their
            # own start, not the seat tag: Chop Top / KamAZ front seats). A native entry ends in the seat's own
            # yaw; a borrowed RAM one in the car's forward (its RAM seat faced forward), TIF's warp turning him.
            st, sy, tr, a = place(e_clip, tp, tyaw)
            st, sy = back_from(lp, 0.0 if borrowed(e_clip) else lyaw, tr)
            entry = {"role": role_name(seat, "entry"), "lp": r2(st), "lyaw": round(sy, 1)}
            d = door_for(e_clip, "in", a["frames"]) if seat.get("door") else None
            if d:
                entry["door"] = d
            row["entry"] = entry
            msg = "in from (%6.1f %6.1f %5.1f) y%5.0f%s%s" % (st[0], st[1], st[2] - gz, sy, " borrowed" if borrowed(e_clip) else "",
                                                           (" door %s%s" % (d["bone"], " (plain)" if d.get("plain") else "")) if d else "")
        else:
            msg = "no entry (put in from the door)"
        print("  seat %d %-8s on %-16s sit (%6.1f %6.1f %5.1f) y%5.0f | %s" % (
            k, seat["role"], tag or "point", lp[0], lp[1], lp[2] - gz, lyaw, msg))
        exits = {}
        for style, vs in resolve_exits(seat).items():
            lst = []
            for c, side in vs:
                st, sy, tr, a = place(c, tp, tyaw)
                if borrowed(c):  # (from the seat, facing the car's forward like its RAM seat)
                    st, sy = lp.copy(), 0.0
                fr, v, how = hid.release(a, tr)
                en = st + rot(sy) @ np.array(tr[-1][:3])
                gap = float(np.linalg.norm(st - lp))
                e = {"role": role_name(seat, "exit", style, side), "release": round(fr / max(1, len(tr) - 1), 3),
                     "vel": [round(float(v[0]), 1), round(float(v[1]), 1)]}
                if gap > 1 or abs(((sy - lyaw) + 180) % 360 - 180) > 1:  # (starts off the seat's spot / yaw)
                    e["lp"], e["lyaw"] = r2(st), round(sy, 1)
                if side:
                    e["side"] = side
                d = door_for(c, "out", a["frames"]) if seat.get("door") else None
                if d:
                    e["door"] = d
                lst.append(e)
                print("    %-6s %-2s start gap %4.1f | end (%6.1f %6.1f %5.1f) | release %3d/%3d (%s) %4.0f u/s%s" % (
                    style, side or "", gap, en[0], en[1], en[2] - gz, fr, len(tr) - 1, how, float(np.hypot(*v[:2])),
                    " door" if d else ""))
            exits[style] = lst
        row["exits"] = exits
        # gunner: turns and fires from the seat in a gun-up loop (its own, or the seat pose when that is gun-up)
        if seat.get("gunner") == "idle":
            row["gunner"] = row["idle"]
        elif seat.get("gunner_clip") and exists(seat["gunner_clip"]):
            row["gunner"] = role_name(seat, "aim")
        rows.append(row)
    path = os.path.join(cb.ADDON, "lua", "tif_mw_cars", "data", car + "_seats.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by K:/jimmyproject/tif_air/car_seat_data.py from the CoD seat clips and the car's tags.\n"
                "-- Do not edit by hand. Soldiers' seats, entries, exits and door motion (VEHICLE_PLAN.md stage 2).\n")
        f.write("TIF_MW_CAR_SEATS = TIF_MW_CAR_SEATS or {}\nTIF_MW_CAR_SEATS[\"%s\"] = %s\n" % (car, cb.hb_lua(rows)))
    print("wrote", path)


if __name__ == "__main__":
    for c in (sys.argv[1:] or list(SEATS)):
        build(c)
