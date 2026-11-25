"""
TIF MW cars: build a CoD (MWII / MW19) ground vehicle export (K:\\cod cars) into Glide-ready models in
addons/tif_mw_cars: a chassis (body with its opening doors, hood, tailgate and steering wheel as bones, CoD seat /
light / exhaust tags as attachments, wheels removed) and one wheel model (origin at the hub, axle along y).

- Damage / flat-tyre / cracked-glass / husk parts are dropped (cfg "drop": bone name pattern).
- Textures: read from the export's <material>_images.txt (slot 0x0 colour, 0x4 normal; mat_info.py); 1x1 black
  materials are glass / lights (dark translucent).
- Paint (cfg "paint": materials, or "auto"): tintable. CoD's own paint mask (slot 0x1E) goes into the colour
  texture's alpha ($blendtintbybasealpha) and $color2 comes from the entity (PlayerColor proxy ->
  ENT:GetPlayerColor), so each car spawns in its own colour while glass, trim, rubber and armour stay as they are.
- studiomdl's 90 deg compile turn is undone as in heli_build.py (CoD frame kept: +x forward).

Usage: car_build.py <car id> [--skip-tex]
"""
# Body tint (paint mask in the colour alpha + PlayerColor proxy). Off since 2026-11-14 (user: texture issues).
TINT = False

import argparse
import os
import re
import shutil
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import heli_build as hb  # noqa: E402
import mat_info as mi  # noqa: E402

GAME = hb.GAME
ADDON = os.path.join(GAME, "addons", "tif_mw_cars")
BUILD = os.path.join(HERE, "build_cars")
CARS = r"K:\cod cars"

# Parts never wanted on a running vehicle: flat tyres, cracked glass, damaged / husk / destroyed pieces.
DROP_DEFAULT = r"(_flat$|_web$|_hsk|_dst|broken|_damaged|_dmg)"

RAM = os.path.join(CARS, "Pick-Up - RAM 1500 - AQ")
RAM_DOORS = ["tag_door_front_left", "tag_door_front_right", "tag_door_back_left", "tag_door_back_right"]
RAM_TAGS = (["tag_seat_%d" % i for i in range(7)] + ["tag_seat_%d_window" % i for i in range(4)]
            + ["tag_exhaust", "tag_engine_fx", "tag_light_front_left", "tag_light_front_right",
               "tag_light_back_left", "tag_light_back_right", "tag_origin_static"])
WHEELS = ["tag_wheel_center_front_left", "tag_wheel_center_front_right",
          "tag_wheel_center_back_left", "tag_wheel_center_back_right"]

CARS_CFG = {
    # RAM 1500 pickup, unarmored (MWII "tech": the AQ technical's body without its armour; white paint, tintable)
    "ram1500": {
        "export": os.path.join(RAM, "veh9_civ_lnd_pickup_fullsized_2014_tech_vehphys_mp"),
        "body": "tag_body",
        "movers": RAM_DOORS + ["tag_hood", "tag_trunk", "tag_steering_jnt"],
        "tags": RAM_TAGS,
        "wheels": WHEELS,
        "wheel_model": "tag_wheel_center_front_left",
        "paint": "auto",  # body + bed (CoD paint mask)
        # cracked-glass overlays (the "web" windshield and the rear door windows' cracks)
        "drop_mats": ["xmaterial_57581c3a905357c3", "xmaterial_2be656833317ad30"],
        "hulls": [(-110, -30), (-30, 45), (45, 120)],
        "mass": 2200,
    },
    # RAM 1500 armoured technical (MWII "tech_armor": plated cab, heavier)
    "ram1500_armor": {
        "export": os.path.join(RAM, "veh9_civ_lnd_pickup_fullsized_2014_tech_armor_vehphys_mp"),
        "body": "tag_body",
        "movers": RAM_DOORS + ["tag_hood", "tag_trunk", "tag_steering_jnt"],
        "tags": RAM_TAGS,
        "wheels": WHEELS,
        "wheel_model": "tag_wheel_center_front_left",
        "paint": [],  # (user: its body counts as the armour: keeps its factory finish)
        "hulls": [(-137, -40), (-40, 50), (50, 153)],
        "mass": 3200,
    },
}

def car(folder, export, seats, mass, paint="auto", **kw):
    """A car read off its own skeleton ("auto"): doors / hood / trunk / steering as movers, wheel hubs, light / exhaust /
    engine / ground tags, three collision boxes along its length. seats: Glide seat order = TIF seat n (driver
    first), the tags car_seat_data.py places the soldiers' clips on."""
    cfg = {"export": os.path.join(CARS, folder, export), "body": kw.pop("body", "tag_body"), "auto": True,
           "seat_tags": seats, "mass": mass, "paint": paint}
    cfg.update(kw)
    return cfg


CARS_CFG.update({
    # Jeep Cherokee (MWII suv_1996)
    "cherokee": car("SUV - Standard", "veh9_civ_lnd_suv_1996_body_x_vehphys_mp",
                    ["tag_seat_0", "tag_seat_1", "tag_seat_2", "tag_seat_3"], 1800),
    # Land Rover Defender "Chop Top" (MWII suv_overland_2016_cage)
    "choptop": car("Chop Top - Standard", "veh9_civ_lnd_suv_overland_2016_cage_wz_body_vehphys_mp",
                   ["tag_seat_0", "tag_seat_1", "tag_seat_2", "tag_seat_3"], 2000),
    # KamAZ 43101 with the covered cargo bed (MWII cargo_truck): 2 in the cab, 4 in the back
    "kamaz": car("Truck - KamAZ 43101 - Cargo", "veh9_mil_lnd_cargo_truck_midcargo_vehphys_sp",
                 ["tag_seat_0", "tag_seat_1", "tag_seat_wm_2", "tag_seat_wm_3", "tag_seat_wm_4", "tag_seat_wm_5"],
                 6500, wheels_extra=["tag_wheel_middle_left", "tag_wheel_middle_right"]),
    # Toyota Hilux, military (MW19 pindia): cab + four in the bed
    "hilux": car("Toyota Hilux - mil_lnd_pindia", "veh8_mil_lnd_pindia",
                 ["tag_driver", "tag_passenger", "tag_bed_guy3", "tag_bed_guy2", "tag_bed_guy4", "tag_bed_guy1"], 1900),
    # Toyota Tundra technical (MW19 techo, rebel): cab + bed
    "tundra": car("Toyota Tundra - civ_lnd_techo_rebel", "veh8_civ_lnd_techo_rebel",
                  ["tag_driver", "tag_passenger", "tag_cab1", "tag_cab2", "tag_bed_center", "tag_bed1", "tag_bed2"], 2300),
    # Land Rover Defender 110 (MW19 decho)
    "defender": car("SUV - 2016 Land-Rover Defender", "veh8_civ_lnd_decho",
                    ["tag_driver", "tag_passenger", "tag_seat_3", "tag_seat_2", [-40.0, 12.0, 30.0], [-40.0, -12.0, 30.0]],
                    2100),
    # Oshkosh MTVR troop truck (MW19 mkilo23 payload): cab + 8 on the benches
    "mtvr": car("Truck - Oshkosh MTVR - Payload", "veh8_mil_lnd_mkilo23_payload",
                ["tag_driver", "tag_seat_1", "tag_seat_2", "tag_seat_6", "tag_seat_3", "tag_seat_7", "tag_seat_4",
                 "tag_seat_8", "tag_seat_5", "tag_seat_9"], 9000,
                wheels_extra=["tag_wheel_center_middle_left", "tag_wheel_center_middle_right"]),
})

AUTO_MOVERS = r"^tag_(door_(front|back)_(left|right)|hood|trunk|tailgate|steering_jnt)$"
AUTO_TAGS = {"exhaust": r"^tag_exhaust(_left|_1)?$", "engine": r"^tag_engine(_fx)?(_left)?$",
             "fl": r"^tag_(light_front_left|headlight_left|headlight_l|light_left_front)$",
             "fr": r"^tag_(light_front_right|headlight_right|headlight_r|light_right_front)$",
             "bl": r"^tag_(light_back_left|light_rear_left|brakelight_left|taillight_left|light_left_back)$",
             "br": r"^tag_(light_back_right|light_rear_right|brakelight_right|taillight_right|light_right_back)$",
             "ground": r"^tag_origin_static$"}


def resolve_auto(cfg, nodes, W):
    """Fill an "auto" car's movers, tags, wheels and hulls from its skeleton."""
    names = {n: i for i, (n, _) in nodes.items()}
    cfg["movers"] = [n for n in names if re.match(AUTO_MOVERS, n)]
    found = {}
    for key, rx in AUTO_TAGS.items():
        hit = sorted(n for n in names if re.match(rx, n))
        if hit:
            found[key] = hit[0]
    cfg["tag_of"] = found
    cfg["tags"] = list(dict.fromkeys([t for t in cfg["seat_tags"] if isinstance(t, str)] + list(found.values())))
    w = [n for n in ("tag_wheel_center_front_left", "tag_wheel_center_front_right",
                     "tag_wheel_center_back_left", "tag_wheel_center_back_right") if n in names]
    cfg["wheels"] = w + [n for n in cfg.get("wheels_extra", []) if n in names]
    cfg["wheel_model"] = "tag_wheel_center_front_left"
    # every wheel-ish bone's geometry is a wheel (some exports hang the tyre on the bottom tag, not the hub)
    cfg["wheel_geom"] = [n for n in names if re.search(r"wheel", n) and not re.search(r"roof|steer|spare|fx", n)]


DECIMATE = {"ratio": 0.35, "err": 0.006}


def export_smd(cfg):
    folder = cfg["export"]
    return os.path.join(folder, os.path.basename(folder) + "_LOD0.smd")


def select(cfg, nodes, mats, verts):
    """Triangle masks: dropped, wheel (which wheel bone), chassis; and each chassis triangle's target bone."""
    drop = re.compile(cfg.get("drop", DROP_DEFAULT))
    by_name = {n: i for i, (n, _) in nodes.items()}
    movers = {by_name[m] for m in cfg["movers"] if m in by_name}
    wheels = {by_name[w]: w for w in cfg["wheels"] + cfg.get("wheel_geom", []) if w in by_name}
    info = {}
    for i in nodes:
        anc = hb.ancestors(nodes, i)
        dropped = any(drop.search(nodes[a][0]) for a in anc)
        wheel = next((wheels[a] for a in anc if a in wheels), None)
        mv = next((a for a in anc if a in movers), None)
        info[i] = (dropped, wheel, nodes[mv][0] if mv is not None else cfg["body"])
    keep_chassis, wheel_of, bone_of = [], [], []
    drop_mats = set(cfg.get("drop_mats", []))
    for t in range(len(mats)):
        d, w, b = info[int(verts[t * 3, 0])]
        d = d or mats[t] in drop_mats
        keep_chassis.append(not d and w is None)
        wheel_of.append(None if d else w)
        bone_of.append(b)
    return keep_chassis, wheel_of, bone_of


def decimate(tris, mats, ratio, err):
    """tris: list of (material, bone, Nx3x8 array) pieces -> decimated pieces."""
    out = []
    for m, bone, arr in tris:
        flat = arr.reshape(-1, 8)
        pos, attr, idx = hb.weld(np.hstack([np.zeros((len(flat), 1)), flat]))  # (weld wants a bone column first)
        res = hb.simplify(pos, attr, idx, ratio, err)
        out.append((m, bone, np.hstack([pos, attr])[res].reshape(-1, 3, 8)))
    return out


def pieces(mats, verts, sel, bone_of):
    groups = {}
    for t, ok in enumerate(sel):
        if ok:
            groups.setdefault((mats[t], bone_of[t]), []).append(t)
    out = []
    for (m, b), ts in groups.items():
        idx = np.repeat(np.array(ts) * 3, 3) + np.tile([0, 1, 2], len(ts))
        out.append((m, b, verts[idx][:, 1:9].reshape(-1, 3, 8)))
    return out


PAINT_SLOT = "0x1E"  # CoD's own paint mask (white = body paint; glass, trim, rubber, armour plates black)


def paint_mask(folder, mat):
    return mi.image_path(folder, mat, mi.slots(folder, mat).get(PAINT_SLOT))


def paint_materials(cfg, used):
    """cfg "paint": a list of materials, or "auto" = every used material that has CoD's paint mask."""
    p = cfg.get("paint", [])
    if p == "auto":
        return {m for m in used if paint_mask(cfg["export"], m) and not mi.recipe(cfg["export"], m).get("glass")}
    return set(p)


INTERIOR = "_in"  # suffix of an untinted copy of a paint material (its triangles that face the cab / inside)


def exterior_flags(chassis, vs=2.5):
    """Per chassis triangle: does its front face look out at open air? The chassis (glass included) is voxelised,
    thickened by one voxel to close panel seams, and the empty space is flood-filled from the grid's edge; a triangle
    whose point a few voxels along its normal is in that outside space is exterior. Inner door panels, dash and cab
    trim (CoD maps some onto the body texture) are not."""
    allv = np.concatenate([arr.reshape(-1, 8)[:, :3] for _, _, arr in chassis])
    lo = allv.min(0) - 6 * vs
    dims = np.ceil((allv.max(0) + 6 * vs - lo) / vs).astype(int) + 1
    occ = np.zeros(dims, bool)
    for _, _, arr in chassis:
        p0, p1, p2 = arr[:, 0, :3], arr[:, 1, :3], arr[:, 2, :3]
        longest = np.max([np.linalg.norm(p1 - p0, axis=1), np.linalg.norm(p2 - p0, axis=1),
                          np.linalg.norm(p2 - p1, axis=1)], axis=0)
        steps = np.clip(np.ceil(longest / (vs * 0.5)).astype(int), 1, 64)
        for s in np.unique(steps):
            sel = steps == s
            a, b, c = p0[sel], p1[sel], p2[sel]
            for i in range(s + 1):
                for j in range(s + 1 - i):
                    u, v = i / s, j / s
                    pt = a + (b - a) * u + (c - a) * v
                    ix = ((pt - lo) / vs).astype(int)
                    occ[ix[:, 0], ix[:, 1], ix[:, 2]] = True

    def dilate(m):
        o = m.copy()
        o[1:] |= m[:-1]; o[:-1] |= m[1:]
        o[:, 1:] |= m[:, :-1]; o[:, :-1] |= m[:, 1:]
        o[:, :, 1:] |= m[:, :, :-1]; o[:, :, :-1] |= m[:, :, 1:]
        return o

    wall = dilate(occ)
    free = ~wall
    out = np.zeros(dims, bool)
    out[0, :, :] = out[-1, :, :] = out[:, 0, :] = out[:, -1, :] = out[:, :, 0] = out[:, :, -1] = True
    out &= free
    while True:
        nxt = dilate(out) & free
        if nxt.sum() == out.sum():
            break
        out = nxt
    flags = []
    for _, _, arr in chassis:
        cen = arr[:, :, :3].mean(1)
        n = arr[:, :, 3:6].mean(1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-6)
        # March out along the normal: open air reached before another wall = it faces outside (a bull bar or a
        # mirror in front of a panel doesn't stop the march short of the air; the cab's far side or glass does).
        hit = np.zeros(len(arr), bool)
        blocked = np.zeros(len(arr), bool)
        left_shell = np.zeros(len(arr), bool)
        for k in np.arange(1.0, 30.0, 0.5):
            ix = np.clip(((cen + n * k * vs - lo) / vs).astype(int), 0, dims - 1)
            w = wall[ix[:, 0], ix[:, 1], ix[:, 2]]
            o = out[ix[:, 0], ix[:, 1], ix[:, 2]]
            live = ~hit & ~blocked
            hit |= live & o
            blocked |= live & left_shell & w & ~o
            left_shell |= ~w
        # (never reached open air within ~75 units: facing into an enclosed space, e.g. across the cab = inside)
        flags.append(hit)
    return flags


def split_interior(chassis, paint):
    """Paint-material triangles that don't face outside move to an untinted copy (<mat>_in)."""
    if not paint:
        return chassis
    flags = exterior_flags(chassis)
    out = []
    for (m, b, arr), ext in zip(chassis, flags):
        if m in paint and not ext.all():
            if ext.any():
                out.append((m, b, arr[ext]))
            out.append((m + INTERIOR, b, arr[~ext]))
            print("  %s on %s: %d outside, %d inside (untinted)" % (m, b, int(ext.sum()), int((~ext).sum())))
        else:
            out.append((m, b, arr))
    return out


def paint_texture(img, mask_path):
    """Paint: alpha = CoD's paint mask, so only the painted panels take the car's colour."""
    out = img.convert("RGB")
    m = Image.open(mask_path).convert("L").resize(out.size, Image.LANCZOS)
    out.putalpha(m)
    return out


def textures(cfg, cid, used):
    folder = cfg["export"]
    mdir = "tif_mw_cars/" + cid
    out_dir = os.path.join(ADDON, "materials", *mdir.split("/"))
    os.makedirs(out_dir, exist_ok=True)
    report = []
    paint = paint_materials(cfg, used)
    for mat in sorted(used):
        if mat.endswith(INTERIOR) and mat[:-len(INTERIOR)] in used:
            # the untinted copy: same textures as its paint material
            src = mat[:-len(INTERIOR)]
            with open(os.path.join(out_dir, mat + ".vmt"), "w") as f:
                f.write('"VertexLitGeneric"\n{\n\t"$basetexture" "%s/%s"\n\t"$surfaceprop" "metalvehicle"\n' % (mdir, src))
                f.write('\t"$bumpmap" "%s/%s_n"\n\t"$phong" "1"\n\t"$phongboost" "0.5"\n\t"$phongexponent" "25"\n'
                        '\t"$phongfresnelranges" "[0.3 0.6 1]"\n}\n' % (mdir, src))
            report.append("%s interior (untinted %s)" % (mat, src))
            continue
        r = mi.recipe(folder, mat)
        params = {"$surfaceprop": "metalvehicle"}
        st = r["stats"]
        if not r["base"] or (st and st["size"] == (1, 1)) or r.get("glass"):
            # glass, lights: dark and see-through
            img = Image.new("RGBA", (64, 64), (16, 18, 20, 120))
            hb.vtex(mat, img, out_dir)
            params.update({"$translucent": "1", "$surfaceprop": "glass", "$envmap": "env_cubemap",
                           "$envmaptint": "[0.3 0.3 0.3]"})
            kind = "glass"
        else:
            c = Image.open(r["base"])
            size = max(256, min(2048, c.size[0]))
            sz = (size, round(size * c.size[1] / c.size[0]))
            c = c.convert("RGBA").resize(sz, Image.LANCZOS)
            if mat in paint and TINT:
                hb.vtex(mat, paint_texture(c, paint_mask(folder, mat)), out_dir)
                params.update({"$blendtintbybasealpha": "1", "$blendtintcoloroverbase": "0"})
                kind = "paint"
            elif mat in paint:
                hb.vtex(mat, c.convert("RGB"), out_dir)  # (tint off: plain colour texture)
                kind = "solid"
            elif r.get("alpha"):
                # cut-outs (grilles, nets): alpha-tested, both sides drawn
                a = Image.open(r["alpha"]).convert("L").resize(sz, Image.LANCZOS)
                out = c.convert("RGB")
                out.putalpha(a)
                hb.vtex(mat, out, out_dir)
                params.update({"$alphatest": "1", "$alphatestreference": "0.5", "$nocull": "1"})
                kind = "cut-out"
            else:
                hb.vtex(mat, c.convert("RGB"), out_dir)
                kind = "hull"
            if r["normal"]:
                n = Image.open(r["normal"])
                n = mi.unpack_normal(n) if r.get("packed") else n.convert("RGBA")
                hb.vtex(mat + "_n", n.resize(sz, Image.LANCZOS), out_dir, normal=True)
                params.update({"$bumpmap": "%s/%s_n" % (mdir, mat), "$phong": "1", "$phongboost": "0.5",
                               "$phongexponent": "25", "$phongfresnelranges": "[0.3 0.6 1]"})
        with open(os.path.join(out_dir, mat + ".vmt"), "w") as f:
            f.write('"VertexLitGeneric"\n{\n\t"$basetexture" "%s/%s"\n' % (mdir, mat))
            for k, v in params.items():
                f.write('\t"%s" "%s"\n' % (k, v))
            if kind == "paint":
                f.write('\t"Proxies"\n\t{\n\t\t"PlayerColor"\n\t\t{\n\t\t\t"resultVar" "$color2"\n'
                        '\t\t\t"default" "1 1 1"\n\t\t}\n\t}\n')
            f.write("}\n")
        report.append("%s %s" % (mat, kind))
    shutil.rmtree(os.path.join(GAME, "materialsrc", "tif_air_build"), ignore_errors=True)
    shutil.rmtree(os.path.join(GAME, "materials", "tif_air_build"), ignore_errors=True)
    return report


def compile_qc(lines, path, model_rel):
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    hb.run([hb.STUDIOMDL, "-game", GAME, "-nop4", "-nox360", path])
    sub = model_rel.split("/")
    src = os.path.join(GAME, "models", *sub[:-1])
    dst = os.path.join(ADDON, "models", *sub[:-1])
    os.makedirs(dst, exist_ok=True)
    moved = []
    for fn in os.listdir(src):
        if fn.startswith(sub[-1] + "."):
            shutil.move(os.path.join(src, fn), os.path.join(dst, fn))
            moved.append(fn)
    return moved


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("car", choices=sorted(CARS_CFG))
    ap.add_argument("--skip-tex", action="store_true")
    a = ap.parse_args()
    cfg = CARS_CFG[a.car]
    os.makedirs(BUILD, exist_ok=True)
    nodes, skel, mats, verts = hb.read_smd(export_smd(cfg))
    verts, agree = hb.fix_winding(verts)
    W = hb.world_matrices(nodes, skel)
    by_name = {n: i for i, (n, _) in nodes.items()}
    if cfg.get("auto"):
        resolve_auto(cfg, nodes, W)
        print("auto: movers %s | wheels %s | tags %s" % (cfg["movers"], cfg["wheels"], cfg["tag_of"]))
    keep, wheel_of, bone_of = select(cfg, nodes, mats, verts)
    print("read %d tris | chassis %d | wheels %d | dropped %d | winding %.0f%%" % (
        len(mats), sum(keep), sum(1 for w in wheel_of if w), len(mats) - sum(keep) - sum(1 for w in wheel_of if w),
        agree * 100))

    # Chassis: body + movers + tags (heli_build's skeleton() keeps body, movers and tags with their ancestors).
    hcfg = {"body": cfg["body"], "movers": [m for m in cfg["movers"] if m in by_name], "tags": cfg["tags"]}
    cfg["movers"] = hcfg["movers"]
    bones, missing = hb.skeleton(hcfg, nodes, skel)
    if missing:
        print("tags not in model:", ", ".join(missing))
    chassis = decimate(pieces(mats, verts, keep, bone_of), mats, DECIMATE["ratio"], DECIMATE["err"])
    chassis = split_interior(chassis, paint_materials(cfg, {m for m, _, _ in chassis}))
    hb.write_smd(os.path.join(BUILD, a.car + "_chassis.smd"), bones, chassis)
    pts = np.concatenate([arr.reshape(-1, 8)[:, :3] for m, b, arr in chassis if b == cfg["body"]])
    if "hulls" not in cfg:
        lo, hi = np.percentile(pts[:, 0], 1), np.percentile(pts[:, 0], 99)
        cfg["hulls"] = [(lo + (hi - lo) * k / 3, lo + (hi - lo) * (k + 1) / 3) for k in range(3)]
    boxes = []
    for x0, x1 in cfg["hulls"]:
        s = pts[(pts[:, 0] >= x0) & (pts[:, 0] <= x1)]
        if len(s) > 8:
            boxes.append((tuple(np.percentile(s, 2, axis=0)), tuple(np.percentile(s, 98, axis=0))))
    # (whole units: with some exact values, e.g. the Hilux's, studiomdl split the boxes into 14 flat pieces)
    boxes = [(tuple(np.floor(lo)), tuple(np.ceil(hi))) for lo, hi in boxes]
    # neighbouring boxes meet exactly at their slab boundary (small gaps between them made studiomdl fall back to
    # one convex hull on the Cherokee / Chop Top); the outer ends keep the body's own extent
    if cfg.get("auto") and len(boxes) == len(cfg["hulls"]):
        fixed = []
        for i, ((lo, hi), (x0, x1)) in enumerate(zip(boxes, cfg["hulls"])):
            lo, hi = list(lo), list(hi)
            if i > 0:
                lo[0] = round(x0)
            if i < len(boxes) - 1:
                hi[0] = round(x1)
            fixed.append((tuple(lo), tuple(hi)))
        boxes = fixed
    hb.write_smd(os.path.join(BUILD, a.car + "_phys.smd"), bones, boxes=boxes)
    print("chassis %d tris | bones %d | collision %s" % (sum(len(arr) for _, _, arr in chassis), len(bones),
                                                         [tuple(round(v) for v in lo + hi) for lo, hi in boxes]))

    # Wheel: one wheel's geometry around its hub (axle along y, outer face +y: a left wheel).
    wb = cfg["wheel_model"]
    hub = W[by_name[wb]][:3, 3]
    # the front-left wheel: geometry under any wheel bone at that hub
    near = {w for w in set(wheel_of) if w and np.hypot(*(W[by_name[w]][:2, 3] - hub[:2])) < 20}
    sel = [w in near for w in wheel_of]
    wheel = pieces(mats, verts, sel, ["tif_wheel"] * len(mats))
    wheel = [(m, b, np.concatenate([arr[..., :3] - hub, arr[..., 3:]], axis=-1)) for m, b, arr in wheel]
    wheel = decimate(wheel, mats, 0.5, 0.004)
    wpts = np.concatenate([arr.reshape(-1, 8)[:, :3] for _, _, arr in wheel])
    radius = float(np.max(np.hypot(wpts[:, 0], wpts[:, 2])))
    wbones = [("tif_wheel", -1, np.eye(4))]
    hb.write_smd(os.path.join(BUILD, a.car + "_wheel.smd"), wbones, wheel)
    whboxes = [(tuple(wpts.min(0)), tuple(wpts.max(0)))]
    hb.write_smd(os.path.join(BUILD, a.car + "_wheel_phys.smd"), wbones, boxes=whboxes)
    hubs = {w: [round(float(x), 2) for x in W[by_name[w]][:3, 3]] for w in cfg["wheels"] if w in by_name}
    # a wheel known only by its ground tag (KamAZ middle axle): lift it to hub height like the front wheel
    if "tag_wheel_front_left" in by_name:
        dz = W[by_name["tag_wheel_center_front_left"]][2, 3] - W[by_name["tag_wheel_front_left"]][2, 3]
        for w in hubs:
            if "center" not in w:
                hubs[w][2] = round(hubs[w][2] + float(dz), 2)
    print("wheel %d tris | radius %.1f | width %.1f | hubs %s" % (sum(len(arr) for _, _, arr in wheel), radius,
                                                                 float(wpts[:, 1].max() - wpts[:, 1].min()), hubs))

    used = {m for m, _, _ in chassis} | {m for m, _, _ in wheel}
    if not a.skip_tex:
        for line in textures(cfg, a.car, used):
            print("  material", line)

    model = "tif_mw_cars/" + a.car
    lines = ['$modelname "%s.mdl"' % model, '$cdmaterials "%s/"' % model, '$surfaceprop "metalvehicle"',
             '$body "body" "%s_chassis.smd"' % a.car]
    for name, _, _ in bones:
        if name in cfg["tags"]:
            lines.append('$attachment "%s" "%s" 0 0 0 rotate 0 0 0' % (name, name))
    lines += ['$sequence "idle" "%s_chassis.smd" fps 30' % a.car,
              '$collisionmodel "%s_phys.smd"\n{\n\t$concave\n\t$mass %d\n\t$maxconvexpieces 8\n}' % (a.car, cfg["mass"])]
    print("compiled:", ", ".join(compile_qc(lines, os.path.join(BUILD, a.car + ".qc"), model)))
    wlines = ['$modelname "%s_wheel.mdl"' % model, '$cdmaterials "%s/"' % model, '$surfaceprop "rubbertire"',
              '$body "body" "%s_wheel.smd"' % a.car, '$sequence "idle" "%s_wheel.smd" fps 30' % a.car,
              '$collisionmodel "%s_wheel_phys.smd"\n{\n\t$mass 30\n}' % a.car]
    print("compiled:", ", ".join(compile_qc(wlines, os.path.join(BUILD, a.car + "_wheel.qc"), model + "_wheel")))
    write_data(a.car, cfg, W, by_name, hubs, radius)


def write_data(cid, cfg, W, by_name, hubs, radius):
    """lua/tif_mw_cars/data/<id>.lua: what the Glide entity needs, read from the model's own tags (CoD frame)."""
    def at(tag):
        if isinstance(tag, (list, tuple)):  # a seat at a point no tag marks
            return [float(x) for x in tag]
        return [round(float(x), 2) for x in W[by_name[tag]][:3, 3]] if tag in by_name else None
    seats = []
    for t in cfg.get("seat_tags") or ["tag_seat_%d" % i for i in range(10)]:
        p = at(t)
        if p:
            seats.append({"tag": t if isinstance(t, str) else "point", "pos": p})
    tag_of = cfg.get("tag_of") or {"fl": "tag_light_front_left", "fr": "tag_light_front_right",
                                   "bl": "tag_light_back_left", "br": "tag_light_back_right",
                                   "exhaust": "tag_exhaust", "engine": "tag_engine_fx", "ground": "tag_origin_static"}
    lights = {k: at(tag_of[k]) for k in ("fl", "fr", "bl", "br") if k in tag_of}
    ground = at(tag_of["ground"]) if "ground" in tag_of else None
    if not ground:  # (MW19 exports: no origin_static; the wheels stand on it)
        ground = [0, 0, round(min(h[2] for h in hubs.values()) - radius, 2)]
    data = {"model": "models/tif_mw_cars/%s.mdl" % cid, "wheelModel": "models/tif_mw_cars/%s_wheel.mdl" % cid,
            "wheelRadius": round(radius, 2), "mass": cfg["mass"],
            "wheels": [{"pos": hubs[w], "left": "left" in w, "front": "front" in w} for w in cfg["wheels"] if w in hubs],
            "seats": seats, "lights": {k: v for k, v in lights.items() if v},
            "exhaust": at(tag_of.get("exhaust", "")), "engine": at(tag_of.get("engine", "")), "ground": ground,
            "doors": [m for m in cfg["movers"] if m.startswith("tag_door")], "paint": bool(cfg.get("paint"))}
    path = os.path.join(ADDON, "lua", "tif_mw_cars", "data", cid + ".lua")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by K:/jimmyproject/tif_air/car_build.py from the CoD export's tags. Do not edit by hand.\n")
        f.write("TIF_MW_CARS = TIF_MW_CARS or {}\nTIF_MW_CARS[\"%s\"] = %s\n" % (cid, hb_lua(data)))
    print("data:", path)


def hb_lua(v, ind=""):
    if isinstance(v, dict):
        inner = ind + "\t"
        return "{\n" + "".join("%s%s = %s,\n" % (inner, k if re.match(r"^[A-Za-z_]\w*$", k) else '["%s"]' % k,
                                                 hb_lua(x, inner)) for k, x in v.items() if x is not None) + ind + "}"
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float)) for x in v):
            return "{ " + ", ".join("%g" % x for x in v) + " }"
        return "{\n" + "".join("%s\t%s,\n" % (ind, hb_lua(x, ind + "\t")) for x in v) + ind + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return "%g" % v
    return '"%s"' % v


if __name__ == "__main__":
    main()
