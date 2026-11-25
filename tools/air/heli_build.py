"""
TIF air: build a CoD helicopter export (K:\\cod choppers, Greyhound-style SMD + DDS) into a GMod model in
addons/tif_air.

What it does, per vehicle config (VEHICLES below):
- Reads the LOD0 SMD (inches, CoD tag_origin frame; kept as is so CoD passenger clips line up with the tags).
- Rebinds every vertex to a few moving bones (body, main rotor, tail rotor, sliding doors); other bones are merged
  into the body. Tag bones listed in `tags` are kept (bone + attachment of the same name) for seats, ropes, guns...
- Splits the mesh into bodyparts: body, interior (dropped at the far LOD), rotor (bodygroup 0 = blades, 1 = blur).
- Decimates every (part, bone, material) piece with meshoptimizer, error-capped, into 3 LODs.
- Converts textures (BC7 / BC4 DDS via Pillow) to TGA and compiles them with vtex; writes the VMTs.
- Writes simple convex collision boxes (cabin / boom / fin) from the body's own bounds.
- Compiles with studiomdl and moves the result into the addon.

Usage: heli_build.py <vehicle> [--skip-tex] [--skip-compile]
Run with a Python that has numpy, Pillow (BC7 decode) and meshoptimizer.
"""
import argparse
import ctypes
import glob
import math
import os
import shutil
import subprocess
import sys
from collections import defaultdict

import numpy as np
import meshoptimizer as mo
from PIL import Image

GAME = r"K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod"
BIN = r"K:\SteamLibrary\steamapps\common\GarrysMod\bin"
STUDIOMDL = os.path.join(BIN, "studiomdl.exe")
VTEX = os.path.join(BIN, "vtex.exe")
ADDON = os.path.join(GAME, "addons", "tif_air")
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")

BH = r"K:\cod choppers\Helicopter - Sikorsky UH-60 Black Hawk\veh8_mil_air_blima"
BHD = r"K:\cod choppers\Helicopter - Sikorsky UH-60 Black Hawk Destroyed\veh8_mil_air_blima_dst"
LBR = r"K:\cod choppers\MH-6 Little Bird - Standard"
MI8 = r"K:\cod choppers\Helicopter - Mil Mi-17"


def _lb_mats(keep=None):
    """Little Bird materials: the export names them by hash; recipes from their images (heli_infil notes)."""
    def hull(base, normal, size):
        return {"kind": "hull", "base": base + "*", "normal": normal + "*", "size": size}
    m = {
        "ximage_6a0e90654ff3161a": hull("ximage_502ba65613cc742c", "ximage_6d2b4b542a6779f8", 2048),  # fuselage
        "ximage_2fe9092e08616e97": hull("ximage_1fb709e27eee19b2", "ximage_125bbd17629c4e40", 2048),  # frame, benches
        "ximage_6454cbe01255aaa7": hull("ximage_a5fc41f638b17f1", "ximage_6f8ae3717ad31526", 1024),
        "ximage_3c0876e23e106ad5": hull("ximage_d8beb01a26fa35e", "ximage_41f59d353f2ec221", 512),  # rotor hub
        "ximage_63d14b9063d3f99b": hull("ximage_d8beb01a26fa35e", "ximage_41f59d353f2ec221", 512),  # blades
        "ximage_49ae8341444f266b": {"kind": "alpha", "base": "ximage_192fac3b7241ebca*", "alpha": "ximage_710a7623b5cac581*",
                                    "translucent": True, "size": 512},  # blurred blades
        "ximage_503895764ead0381": {"kind": "alpha", "base": "ximage_7217bbbe784cc73*", "alpha": "ximage_6f41591d01c58ebb*",
                                    "alphatest": True, "size": 512},  # decals
        "ximage_307027d126f0399": {"kind": "glass", "alpha": "ximage_5231aa16009e5b66*", "alpha_ch": "A", "size": 512},
        "ximage_b36dd780f25ca2d": {"kind": "glass", "alpha": "ximage_5231aa16009e5b66*", "alpha_ch": "A", "size": 512},
    }
    for k, v in m.items():
        v["dir"] = k
    return {k: v for k, v in m.items() if keep is None or k in keep}


def _mi8_mats():
    p = "veh8_mil_air_mindia8_"
    m = {
        p + "body01": {"kind": "hull", "size": 2048},
        p + "body02": {"kind": "hull", "size": 2048},
        p + "decals": {"kind": "alpha", "base": "*_decals_c&*", "alpha": "*_decals_c~*", "alphatest": True, "size": 1024},
        p + "rotors": {"kind": "hull", "size": 1024},
        p + "rotors_blur": {"kind": "alpha", "base": "*_rotors_2_c&*", "base_alpha": True, "translucent": True, "size": 512},
        p + "blurred_rotors": {"kind": "alpha", "base": "*_c&*", "alpha": "*_a~*", "translucent": True, "size": 512},
        p + "glass": {"kind": "glass", "size": 256, "opacity": 110},
        p + "glass_in": {"kind": "glass", "size": 256, "opacity": 110},
        p + "glass_2": {"kind": "glass", "size": 256, "opacity": 110},
        p + "glass_3": {"kind": "glass", "size": 256, "opacity": 110},
    }
    for k, v in m.items():
        v["dir"] = k
    m[p + "interior_no_thermal"] = {"kind": "hull", "size": 1024, "dir": p + "interior_no_thermal",
                                    "images": os.path.join(MI8, p + "interior_static", "_images")}
    return m

HVY = r"K:\cod cars\Heavy Chopper - Standard\veh9_mil_air_heli_palfa_doors_open_vehphys_mp"
HVYD = r"K:\cod cars\Heavy Chopper - Destroyed\veh9_mil_air_heli_palfa_dst"


def _mw2_mats(folder, kinds, size=2048):
    """MWII exports (hashed / slot-numbered images): recipes from each material's _images.txt (mat_info.py: slot 0x0
    colour, 0x4 normal). kinds: material -> kind override ("hull" default, "glass", "plain", "decal" = alpha-tested
    cut-out from the colour's alpha, "blades" = the same at blade size, "blur" = translucent at a fixed opacity)."""
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import mat_info as mi
    out = {}
    for mtl in sorted(glob.glob(os.path.join(folder, "*_images.txt"))):
        mat = os.path.basename(mtl)[:-len("_images.txt")]
        s = mi.slots(folder, mat)
        base, nrm = s.get("0x0"), s.get("0x4")
        if base in mi.PLACEHOLDERS:
            base = None
        if nrm in mi.PLACEHOLDERS:
            nrm = None
        k = kinds.get(mat, "hull" if (base and nrm) else ("plain" if base else "glass"))
        r = {"dir": mat, "size": size}
        if base:
            r["base"] = base + "*"
        if nrm:
            r["normal"] = nrm + "*"
        if k == "glass":
            r.update({"kind": "glass", "size": 256, "opacity": 110})
        elif k == "decal":
            r.update({"kind": "alpha", "base_alpha": True, "alphatest": True})
        elif k == "blades":
            r.update({"kind": "alpha", "base_alpha": True, "alphatest": True})
        elif k == "blur":
            r.update({"kind": "alpha", "translucent": True, "opacity": 120, "size": 512})
        elif k == "plain":
            r.update({"kind": "plain", "size": 512})
        else:
            r["kind"] = "hull"
        out[mat] = r
    return out


VEHICLES = {
    "blackhawk": {
        "smd": os.path.join(BH, "veh8_mil_air_blima_LOD0.smd"),
        "images": os.path.join(BH, "_images"),
        "body": "body_animate_jnt",
        # Bones that keep their own geometry (everything under them is merged into them).
        "movers": ["main_rotor_jnt", "tail_rotor_jnt", "side_door_l_jnt", "side_door_r_jnt"],
        # Kept as bones + attachments (seats, rope points, guns, effects).
        "tags": ["tag_ground", "tag_deathfx", "tag_engine_left", "tag_engine_right", "tag_light_belly",
                 "tag_fastrope_le", "tag_fastrope_ri", "tag_doorgun", "tag_gun_l", "tag_gun_r",
                 "tag_pilot1", "tag_pilot2", "tag_turret_npc", "tag_main_rotor_static", "tag_tail_rotor_static", "tag_body"]
                + ["tag_seat_%d" % i for i in range(6)] + ["tag_seat_exit_%d" % i for i in range(6)]
                + ["tag_guy%d" % i for i in range(10)],
        "blades": ["tag_main_rotor_blade_0%d" % i for i in range(1, 5)] + ["tag_tail_rotor_blade_0%d" % i for i in range(1, 5)],
        "interior_bone": "tag_interior",
        "interior_mats": ("interior",),
        # Per-material texture recipes. kind: hull (base + bump, phong), interior (base x occlusion), plain,
        # alpha (base + separate alpha map), glass (constant colour + alpha map).
        "materials": {
            "veh8_mil_air_blima_body1": {"kind": "hull", "dir": "veh8_mil_air_blima_body1", "size": 2048},
            "veh8_mil_air_blima_body2": {"kind": "hull", "dir": "veh8_mil_air_blima_body2", "size": 2048},
            "veh8_mil_air_blima_interior_01": {"kind": "interior", "dir": "veh8_mil_air_blima_interior_01", "size": 1024},
            "veh8_mil_air_blima_interior_02": {"kind": "interior", "dir": "veh8_mil_air_blima_interior_02", "size": 1024},
            "veh8_mil_air_blima_interior_01_flag": {"alias": "veh8_mil_air_blima_interior_01", "nocull": True},
            "veh8_mil_air_blima_interior_02_flag": {"alias": "veh8_mil_air_blima_interior_02", "nocull": True},
            "veh8_mil_air_blima_top_rotor": {"kind": "plain", "dir": "veh8_mil_air_blima_top_rotor", "size": 512},
            "veh8_mil_air_blima_rear_rotor": {"kind": "plain", "dir": "veh8_mil_air_blima_rear_rotor", "size": 512},
            "veh8_mil_air_blima_blurred_rotors": {"kind": "alpha", "dir": "veh8_mil_air_blima_blurred_rotors",
                                                  "size": 512, "alpha": "*_a~*", "translucent": True},
            "veh8_mil_air_blima_glass": {"kind": "glass", "dir": "veh8_mil_air_blima_glass", "size": 512, "alpha": "*_a~*"},
            "veh8_mil_air_blima_glass_interior": {"kind": "glass", "dir": "veh8_mil_air_blima_glass_interior", "size": 512,
                                                  "alpha": "*_a~*"},
            "veh8_mil_air_blima_decals": {"kind": "alpha", "dir": "veh8_mil_air_blima_decals", "size": 1024,
                                          "base": "*_c&defaultspec*", "alpha": "*_decals_c~*", "alphatest": True},
            "veh8_mil_air_blima_screens": {"kind": "plain", "dir": "veh8_mil_air_blima_screens", "size": 256,
                                           "base": "*_c&defaultspec*"},
        },
        # Collision boxes along the fuselage (x ranges, CoD frame: +x forward); the rotor isn't solid.
        "hulls": [(-130, 200), (-395, -130), (-470, -395)],
        "mass": 6000,
        "model": "tif_air/blackhawk",
        "lods": [],
    },
    # The shot-down wreck (lies where the crash ends; one bone, origin on the ground).
    "blackhawk_dst": {
        "smd": os.path.join(BHD, "veh8_mil_air_blima_dst_LOD0.smd"),
        "images": os.path.join(BHD, "_images"),
        "body": "tag_origin",
        "movers": [], "tags": [], "blades": [], "interior_bone": None, "interior_mats": (),
        "materials": {
            "veh8_mil_air_blima_body1_dst_no_thermal": {"kind": "hull", "dir": "veh8_mil_air_blima_body1_dst_no_thermal", "size": 1024},
            "veh8_mil_air_blima_body2_dst_no_thermal": {"kind": "hull", "dir": "veh8_mil_air_blima_body2_dst_no_thermal", "size": 1024},
            "veh8_mil_air_blima_interior_rotor": {"kind": "hull", "dir": "veh8_mil_air_blima_interior_rotor", "size": 1024},
        },
        "hulls": [(-120, 210), (-380, -120), (-510, -380)],
        "mass": 8000,
        "model": "tif_air/blackhawk_dst",
        "lods": [],
    },
    # MH-6 Little Bird: the fuselage + the passenger benches (separate export) on tag_personnel_platform.
    "littlebird": {
        "smd": os.path.join(LBR, "veh8_mil_air_lbravo_mp", "veh8_mil_air_lbravo_mp_LOD0.smd"),
        "images": os.path.join(LBR, "veh8_mil_air_lbravo_mp", "_images"),
        "extras": [{"smd": os.path.join(LBR, "veh8_mil_air_lbravo_personnel_platform",
                                        "veh8_mil_air_lbravo_personnel_platform_LOD0.smd"), "at": "tag_personnel_platform"}],
        "body": "bone_8053da84",
        "movers": ["bone_66ebfc78", "tag_tail_rotor_rot"],  # main rotor hub, tail rotor
        "tags": ["tag_passenger%d" % i for i in range(1, 7)] + ["tag_seat_%d" % i for i in range(6)]
                + ["tag_pilot1", "tag_pilot2", "tag_exhaust", "tag_main_rotor_static", "tag_tail_rotor_static",
                   "tag_personnel_platform", "tag_turret_left", "tag_turret_right", "tag_light_1", "tag_detach"],
        "blades": ["tag_main_rotor_blade_0%d" % i for i in range(1, 6)] + ["tag_tail_rotor_blade_0%d" % i for i in (1, 2)],
        "interior_bone": None, "interior_mats": (),
        "materials": _lb_mats(),
        "hulls": [(-40, 100), (-215, -40)],
        "mass": 1500,
        "model": "tif_air/littlebird",
        "lods": [],
    },
    "littlebird_dst": {
        "smd": os.path.join(LBR, "veh8_mil_air_lbravo_dst", "veh8_mil_air_lbravo_dst_LOD0.smd"),
        "images": os.path.join(LBR, "veh8_mil_air_lbravo_dst", "_images"),
        "body": "tag_origin", "movers": [], "tags": [], "blades": [], "interior_bone": None, "interior_mats": (),
        "materials": _lb_mats(keep={"ximage_6a0e90654ff3161a", "ximage_2fe9092e08616e97", "ximage_6454cbe01255aaa7",
                                    "ximage_3c0876e23e106ad5", "ximage_63d14b9063d3f99b", "ximage_503895764ead0381",
                                    "ximage_b36dd780f25ca2d"}),
        "hulls": [(-40, 100), (-230, -40)],
        "mass": 2500,
        "model": "tif_air/littlebird_dst",
        "lods": [],
    },
    # Mi-8 / Mi-17: the open-back version (no clamshell doors: the rear exits go straight out) + its cabin interior.
    "mi8": {
        "smd": os.path.join(MI8, "veh8_mil_air_mindia8_open_back", "veh8_mil_air_mindia8_open_back_LOD0.smd"),
        "images": os.path.join(MI8, "veh8_mil_air_mindia8_open_back", "_images"),
        "extras": [{"smd": os.path.join(MI8, "veh8_mil_air_mindia8_interior_static",
                                        "veh8_mil_air_mindia8_interior_static_LOD0.smd"), "at": "tag_origin"}],
        "body": "body_animate_jnt",
        "movers": ["main_rotor_jnt", "tail_rotor_jnt", "side_door_l_jnt", "side_door_r_jnt"],
        "tags": ["tag_guy%d" % i for i in range(14)]
                + ["tag_fastrope_front_le", "tag_fastrope_front_ri", "tag_fastrope_back_le", "tag_fastrope_back_ri",
                   "tag_ground", "tag_engine_left", "tag_engine_right", "tag_pilot1", "tag_pilot2", "tag_spotlight",
                   "tag_turret", "tag_light_belly", "body_animate_jnt"],
        "blades": ["tag_main_rotor_static", "tag_tail_rotor_static"],
        "blur": ["tag_main_rotor_motion", "tag_tail_rotor_motion"],
        "interior_bone": None, "interior_mats": ("interior",),
        "materials": _mi8_mats(),
        "hulls": [(-175, 225), (-470, -175), (-575, -470)],
        "mass": 9000,
        "model": "tif_air/mi8",
        "lods": [],
    },
    # CH-53 heavy (MWII heli_palfa, the ramp-down export: troops leave by the ramp / ropes; the ramp stays open).
    # Rope points: the four the MWII infil's rope clips hang from (front side windows, back of the ramp).
    "heavy": {
        "smd": os.path.join(HVY, "veh9_mil_air_heli_palfa_doors_open_vehphys_mp_LOD0.smd"),
        "images": os.path.join(HVY, "_images"),
        "body": "bone_8053da84",
        "movers": ["bone_66ebfc78", "tag_tail_rotor_rot"],  # main rotor hub, tail rotor
        "tags": ["tag_ground", "tag_deathfx", "tag_engine_left", "tag_engine_right", "tag_light_belly", "tag_driver",
                 "tag_passenger", "tag_door_rear", "tag_main_rotor_static", "tag_tail_rotor_static",
                 "bone_578d27c4", "bone_777e4f9a", "bone_352e9a26", "bone_54ee2530", "tag_body"]
                + ["tag_seat_%d" % i for i in range(8)],
        "blades": ["tag_main_rotor_blade_0%d" % i for i in range(1, 6)] + ["tag_tail_rotor_blade_0%d" % i for i in range(1, 5)],
        "interior_bone": None, "interior_mats": (),
        "materials": _mw2_mats(HVY, {"xmaterial_5ba79fb2c48a1077": "blades", "xmaterial_7d27a356f5ba0be1": "blur",
                                     "xmaterial_22c6e78927ae33ce": "decal", "xmaterial_4952bd70129cb7bf": "decal",
                                     "xmaterial_22c6ec8927ae3c4d": "decal",
                                     "xmaterial_28f4b751410f3297": "glass", "xmaterial_6f89d77a26661ef7": "glass"}),
        "hulls": [(-250, 300), (-470, -250), (-720, -470)],
        "mass": 15000,
        "model": "tif_air/heavy",
        "lod_scale": 0.42,
        "lods": [],
    },
    "heavy_dst": {
        "smd": os.path.join(HVYD, "veh9_mil_air_heli_palfa_dst_LOD0.smd"),
        "images": os.path.join(HVYD, "_images"),
        "body": "tag_origin", "movers": [], "tags": [], "blades": [], "interior_bone": None, "interior_mats": (),
        "materials": _mw2_mats(HVYD, {"veh9_mil_air_heli_palfa_01": "decal", "veh9_mil_air_heli_palfa_04": "decal",
                                      "veh9_mil_air_heli_palfa_rotor": "blades"}, size=1024),
        "hulls": [(-250, 300), (-470, -250), (-720, -470)],
        "mass": 18000,
        "model": "tif_air/heavy_dst",
        "lod_scale": 0.45,
        "lods": [],
    },
    "mi8_dst": {
        "smd": os.path.join(MI8, "veh8_mil_air_mindia8_static_dst", "veh8_mil_air_mindia8_static_dst_LOD0.smd"),
        "images": os.path.join(MI8, "veh8_mil_air_mindia8_static_dst", "_images"),
        "body": "tag_origin", "movers": [], "tags": [], "blades": [], "interior_bone": None, "interior_mats": (),
        "materials": {
            "veh8_mil_air_mindia8_body01_dst_no_thermal": {"kind": "hull", "dir": "veh8_mil_air_mindia8_body01_dst_no_thermal", "size": 1024},
            "veh8_mil_air_mindia8_body02_dst_no_thermal": {"kind": "hull", "dir": "veh8_mil_air_mindia8_body02_dst_no_thermal", "size": 1024},
            "veh8_mil_air_mindia8_interior_dst_no_thermal": {"kind": "hull", "dir": "veh8_mil_air_mindia8_interior_dst_no_thermal", "size": 1024},
            "veh8_mil_air_mindia8_rotors_dst_no_thermal": {"kind": "hull", "dir": "veh8_mil_air_mindia8_rotors_dst_no_thermal", "size": 512},
            "veh8_mil_air_mindia8_decals_dst_no_thermal": {"kind": "alpha", "dir": "veh8_mil_air_mindia8_decals_dst_no_thermal",
                                                          "base": "*_decals_dst_c&*", "alpha": "*_decals_c~*", "alphatest": True, "size": 1024},
            "veh8_mil_air_mindia8_glass_in_no_thermal": {"kind": "glass", "dir": "veh8_mil_air_mindia8_glass_in_no_thermal", "size": 256, "opacity": 110},
        },
        "hulls": [(-270, -60), (-60, 150), (150, 370)],
        "mass": 12000,
        "model": "tif_air/mi8_dst",
        "lods": [],
    },
}

# LODs: share of the piece's triangles aimed for, and the error cap (relative to the piece) that stops it.
LODS = [
    # (interior_err: the cabin is mostly seen through the doors; it may lose more)
    {"name": "lod0", "ratio": 0.30, "err": 0.008, "interior_err": 2},
    {"name": "lod1", "ratio": 0.10, "err": 0.02, "prune": True, "sloppy": True},
    {"name": "lod2", "ratio": 0.03, "err": 0.06, "prune": True, "sloppy": True, "no_interior": True},
]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    out = r.stdout + r.stderr
    bad = [l for l in out.splitlines() if "ERROR" in l.upper() and "0 error" not in l.lower()]
    if r.returncode != 0 or bad:
        print(out[-4000:])
        sys.exit("failed: " + os.path.basename(cmd[0]))
    return out


# ---------------------------------------------------------------- SMD in

def euler_matrix(rx, ry, rz):
    """SMD rotation (radians, XYZ) -> 3x3: R = Rz * Ry * Rx."""
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def matrix_euler(R):
    """3x3 -> SMD XYZ euler (inverse of euler_matrix)."""
    sy = -R[2, 0]
    sy = max(-1.0, min(1.0, sy))
    ry = math.asin(sy)
    if abs(sy) < 0.99999:
        rx = math.atan2(R[2, 1], R[2, 2])
        rz = math.atan2(R[1, 0], R[0, 0])
    else:
        rx = math.atan2(-R[1, 2], R[1, 1])
        rz = 0.0
    return rx, ry, rz


def read_smd(path):
    nodes, skel = {}, {}
    mats, verts = [], []  # verts: (bone, px py pz nx ny nz u v)
    mode = None
    k = 0
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.strip()
            if mode is None:
                if s == "nodes":
                    mode = "nodes"
                continue
            if s == "end":
                mode = "between"
                continue
            if mode == "nodes":
                p = s.split('"')
                nodes[int(p[0])] = (p[1], int(p[2]))
            elif mode == "between":
                if s == "skeleton":
                    mode = "skel"
                elif s == "triangles":
                    mode = "tris"
            elif mode == "skel":
                if s.startswith("time"):
                    continue
                p = s.split()
                skel[int(p[0])] = [float(x) for x in p[1:7]]
            elif mode == "tris":
                if k == 0:
                    mats.append(s)
                    k = 1
                    continue
                p = s.split()
                b = int(p[0])
                if len(p) > 10 and int(p[9]) > 0:  # weighted: strongest link
                    links = [(float(p[11 + 2 * j]), int(p[10 + 2 * j])) for j in range(int(p[9]))]
                    b = max(links)[1]
                verts.append([b] + [float(x) for x in p[1:9]])
                k = k + 1 if k < 3 else 0
    return nodes, skel, mats, np.array(verts, np.float64)


def read_smd_skeleton(path):
    """Nodes and rest skeleton only (stops at the triangles). Returns nodes, skel, [], []."""
    nodes, skel, mode = {}, {}, None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.strip()
            if s == "nodes":
                mode = "nodes"
            elif s == "skeleton":
                mode = "skel"
            elif s == "triangles":
                break
            elif s == "end":
                mode = None
            elif mode == "nodes":
                p = s.split('"')
                nodes[int(p[0])] = (p[1], int(p[2]))
            elif mode == "skel" and not s.startswith("time"):
                p = s.split()
                skel[int(p[0])] = [float(x) for x in p[1:7]]
    return nodes, skel, [], []


def world_matrices(nodes, skel):
    W = {}

    def get(i):
        if i in W:
            return W[i]
        name, par = nodes[i]
        x, y, z, rx, ry, rz = skel[i]
        M = np.eye(4)
        M[:3, :3] = euler_matrix(rx, ry, rz)
        M[:3, 3] = (x, y, z)
        W[i] = M if par < 0 else get(par) @ M
        return W[i]
    for i in nodes:
        get(i)
    return W


# ---------------------------------------------------------------- mesh

def ancestors(nodes, i):
    out = []
    while i >= 0:
        out.append(i)
        i = nodes[i][1]
    return out


def classify(cfg, nodes, mats, verts):
    """Per triangle: part (body / interior / blades / blur) and target bone name; per vertex rebinding."""
    by_name = {n: i for i, (n, _) in nodes.items()}
    movers = {by_name[m] for m in cfg["movers"]}
    blade_ids = {by_name[b] for b in cfg["blades"] if b in by_name}
    # blurred blades: cfg["blur"] (bones), else every blade's "<blade>_blur" sibling
    blur_names = cfg.get("blur") or [b + "_blur" for b in cfg["blades"]]
    blur_ids = {by_name[b] for b in blur_names if b in by_name}
    interior = by_name.get(cfg.get("interior_bone"))
    target, kind = {}, {}
    for i in nodes:
        anc = ancestors(nodes, i)
        mv = next((a for a in anc if a in movers), None)
        target[i] = nodes[mv][0] if mv is not None else cfg["body"]
        if any(a in blur_ids for a in anc):
            kind[i] = "blur"
        elif any(a in blade_ids for a in anc):
            kind[i] = "blades"
        elif interior is not None and interior in anc:
            kind[i] = "interior"
        else:
            kind[i] = "body"
    tri_part, tri_bone = [], []
    for t, m in enumerate(mats):
        b = int(verts[t * 3, 0])
        part = kind[b]
        if part == "body" and any(x in m for x in cfg["interior_mats"]):
            part = "interior"
        tri_part.append(part)
        tri_bone.append(target[b])
    return tri_part, tri_bone


def merge_extras(cfg, nodes, skel, mats, verts):
    """Separate part exports (Little Bird benches, Mi-8 cabin interior) placed on a tag of the main model, rigid
    on that tag's bone. cfg["extras"] = [{"smd": path, "at": tag}]."""
    if not cfg.get("extras"):
        return mats, verts
    by_name = {n: i for i, (n, _) in nodes.items()}
    W = world_matrices(nodes, skel)
    mats, parts = list(mats), [verts]
    for ex in cfg["extras"]:
        _, _, m2, v2 = read_smd(ex["smd"])
        bi = by_name[ex["at"]]
        M = W[bi]
        v2 = v2.copy()
        v2[:, 0] = bi
        v2[:, 1:4] = (M[:3, :3] @ v2[:, 1:4].T).T + M[:3, 3]
        v2[:, 4:7] = (M[:3, :3] @ v2[:, 4:7].T).T
        mats += m2
        parts.append(v2)
        print("merged", os.path.basename(ex["smd"]), len(m2), "tris on", ex["at"])
    return mats, np.vstack(parts)


def fix_winding(verts):
    """Studiomdl wants the winding that agrees with the normals; flip every triangle if most disagree."""
    p = verts[:, 1:4].reshape(-1, 3, 3)
    n = verts[:, 4:7].reshape(-1, 3, 3).sum(axis=1)
    face = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    agree = (np.einsum("ij,ij->i", face, n) > 0).mean()
    if agree < 0.5:
        verts = verts.reshape(-1, 3, verts.shape[1])[:, ::-1, :].reshape(-1, verts.shape[1])
    return verts, agree


def weld(v):
    """Unique vertices of one piece -> pos, attr, idx."""
    key = np.round(v[:, 1:9], 4)
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    return uniq[:, 0:3].astype(np.float32), uniq[:, 3:8].astype(np.float32), inv.astype(np.uint32).ravel()


def simplify(pos, attr, idx, ratio, err, prune=False, sloppy=False):
    """Careful (attribute-aware) simplification capped by err; CoD meshes are many open panels whose borders lock
    it, so the far LODs fall back to clustering (sloppy) when the careful pass stays well above the target."""
    target = max(4, int(len(idx) // 3 * ratio))
    if len(idx) // 3 <= target:
        return idx
    dest = np.zeros(len(idx), np.uint32)
    w = np.array([0.2, 0.2, 0.2, 0.8, 0.8], np.float32)
    n = mo.simplify_with_attributes(dest, idx, pos, np.ascontiguousarray(attr), w,
                                    target_index_count=target * 3, target_error=ctypes.c_float(err),
                                    options=mo.SIMPLIFY_PRUNE if prune else 0)
    res = dest[:n].copy() if n >= 3 else idx
    if sloppy and len(res) // 3 > target * 1.5:
        n = mo.simplify_sloppy(dest, idx, pos, target_index_count=target * 3, target_error=max(err * 3, 0.05))
        if 4 <= n // 3 < len(res) // 3:
            res = dest[:n].copy()
    return res


def build_meshes(cfg, nodes, mats, verts):
    tri_part, tri_bone = classify(cfg, nodes, mats, verts)
    pieces = defaultdict(list)
    for t, (part, bone, m) in enumerate(zip(tri_part, tri_bone, mats)):
        pieces[(part, bone, m)].append(t)
    out = {}  # (part, lod) -> list of (material, bone, tri verts Nx3x8)
    stats = defaultdict(int)
    for (part, bone, m), ts in pieces.items():
        tv = verts[np.repeat(np.array(ts) * 3, 3) + np.tile([0, 1, 2], len(ts))]
        pos, attr, idx = weld(tv)
        for L in LODS:
            if part == "interior" and L.get("no_interior"):
                continue
            err = L["err"] * (L.get("interior_err", 1) if part == "interior" else 1)
            # (cfg "lod_scale": fewer triangles for a big model; Source caps a model at 65536 vertices)
            res = simplify(pos, attr, idx, L["ratio"] * cfg.get("lod_scale", 1), err * (1 / cfg.get("lod_scale", 1)),
                           prune=L.get("prune", False), sloppy=L.get("sloppy", False))
            arr = np.hstack([pos, attr])[res].reshape(-1, 3, 8)
            out.setdefault((part, L["name"]), []).append((m, bone, arr))
            stats[(part, L["name"])] += len(arr)
    return out, stats


# ---------------------------------------------------------------- SMD out

def skeleton(cfg, nodes, skel):
    """Kept bones: root, body, movers, tags (with their kept ancestors). Returns [(name, parent_index, local 4x4)]."""
    W = world_matrices(nodes, skel)
    by_name = {n: i for i, (n, _) in nodes.items()}
    keep = [cfg["body"]] + cfg["movers"] + [t for t in cfg["tags"] if t in by_name]
    missing = [t for t in cfg["tags"] if t not in by_name]
    keep_ids = set()
    for n in keep:
        keep_ids.update(ancestors(nodes, by_name[n]))
    order = sorted(keep_ids, key=lambda i: len(ancestors(nodes, i)))  # parents first
    index = {i: k for k, i in enumerate(order)}
    bones = []
    for i in order:
        par = nodes[i][1]
        while par >= 0 and par not in keep_ids:
            par = nodes[par][1]
        local = W[i] if par < 0 else np.linalg.inv(W[par]) @ W[i]
        bones.append((nodes[i][0], index[par] if par >= 0 else -1, local))
    return bones, missing


# studiomdl turns a model 90 deg left (+z) as it compiles (the gun bake undoes the same turn). Everything written out
# is turned the other way first, so the compiled model sits in the CoD frame: +x forward, tags where CoD has them.
UNTURN = np.array([[0.0, 1.0, 0.0], [-1.0, 0.0, 0.0], [0.0, 0.0, 1.0]])


def unturn(v):
    return (UNTURN @ np.asarray(v, np.float64).T).T


def write_smd(path, bones, tris_by_mat=None, boxes=None, box_bone=0):
    bidx = {b[0]: k for k, b in enumerate(bones)}
    with open(path, "w") as f:
        f.write("version 1\nnodes\n")
        for k, (n, par, _) in enumerate(bones):
            f.write('%d "%s" %d\n' % (k, n, par))
        f.write("end\nskeleton\ntime 0\n")
        for k, (_, par, M) in enumerate(bones):
            if par < 0:  # the root carries the un-turn; children stay relative to it
                T = np.eye(4)
                T[:3, :3] = UNTURN
                M = T @ M
            rx, ry, rz = matrix_euler(M[:3, :3])
            f.write("%d %.6f %.6f %.6f %.6f %.6f %.6f\n" % (k, M[0, 3], M[1, 3], M[2, 3], rx, ry, rz))
        f.write("end\ntriangles\n")
        for m, bone, arr in tris_by_mat or []:
            b = bidx[bone]
            flat = arr.reshape(-1, 8).astype(np.float64)
            flat[:, 0:3] = unturn(flat[:, 0:3])
            flat[:, 3:6] = unturn(flat[:, 3:6])
            for t in range(0, len(flat), 3):
                f.write(m + "\n")
                for v in flat[t:t + 3]:
                    f.write("%d %.4f %.4f %.4f %.4f %.4f %.4f %.5f %.5f\n" % ((b,) + tuple(v)))
        for lo, hi in boxes or []:
            c = unturn([lo, hi])
            lo, hi = tuple(c.min(axis=0)), tuple(c.max(axis=0))
            for tri in box_tris(lo, hi):
                f.write("phys\n")
                for p, n in tri:
                    f.write("%d %.3f %.3f %.3f %.3f %.3f %.3f 0 0\n" % ((box_bone,) + p + n))
        f.write("end\n")


def box_tris(lo, hi):
    c = [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    faces = [((0, 1, 3, 2), (-1, 0, 0)), ((4, 6, 7, 5), (1, 0, 0)), ((0, 4, 5, 1), (0, -1, 0)),
             ((2, 3, 7, 6), (0, 1, 0)), ((0, 2, 6, 4), (0, 0, -1)), ((1, 5, 7, 3), (0, 0, 1))]
    # One normal per corner (pointing out of the box), so the six faces share vertices and studiomdl sees one
    # closed convex piece instead of six flat ones.
    mid = [(lo[i] + hi[i]) / 2 for i in range(3)]

    def nrm(p):
        d = [p[i] - mid[i] for i in range(3)]
        l = math.sqrt(sum(x * x for x in d)) or 1
        return tuple(x / l for x in d)
    out = []
    for (a, b, cc, d), _ in faces:
        out.append([(c[a], nrm(c[a])), (c[b], nrm(c[b])), (c[cc], nrm(c[cc]))])
        out.append([(c[a], nrm(c[a])), (c[cc], nrm(c[cc])), (c[d], nrm(c[d]))])
    return out


def hull_boxes(cfg, tris):
    """Bounding box of the body's own (body bone) geometry in each x slab."""
    pts = np.concatenate([arr.reshape(-1, 8)[:, :3] for m, bone, arr in tris if bone == cfg["body"]])
    boxes = []
    for x0, x1 in cfg["hulls"]:
        sel = pts[(pts[:, 0] >= x0) & (pts[:, 0] <= x1)]
        if len(sel) < 8:
            continue
        lo, hi = np.percentile(sel, 3, axis=0), np.percentile(sel, 97, axis=0)
        boxes.append((tuple(lo), tuple(hi)))
    return boxes


# ---------------------------------------------------------------- textures

def one(folder, pattern):
    hits = sorted(glob.glob(os.path.join(folder, pattern)))
    hits = [h for h in hits if "thermal" not in os.path.basename(h) and "$" not in os.path.basename(h)]
    return hits[0] if hits else None


def load(path, size=None, mode="RGBA"):
    im = Image.open(path)
    im = im.convert(mode)
    if size and im.size != size:
        im = im.resize(size, Image.LANCZOS)
    return im


def vtex(name, img, out_dir, normal=False):
    src = os.path.join(GAME, "materialsrc", "tif_air_build")
    os.makedirs(src, exist_ok=True)
    tga = os.path.join(src, name + ".tga")
    img.save(tga)
    with open(os.path.join(src, name + ".txt"), "w") as f:
        f.write('"nocompress" "0"\n' + ('"normal" "1"\n' if normal else ""))
    run([VTEX, "-game", GAME, "-nopause", "-mkdir", tga])
    built = os.path.join(GAME, "materials", "tif_air_build", name + ".vtf")
    os.makedirs(out_dir, exist_ok=True)
    shutil.move(built, os.path.join(out_dir, name + ".vtf"))


def _p2(n):
    """Nearest power of two (vtex refuses other sizes)."""
    return 1 << max(2, round(math.log2(max(4, n))))


def textures(cfg):
    mdir = cfg["model"].split("/")[0] + "/" + cfg["model"].split("/")[1]
    out_dir = os.path.join(ADDON, "materials", *mdir.split("/"))
    vmts = {}
    for mat, r in cfg["materials"].items():
        if "alias" in r:
            continue
        folder = os.path.join(r.get("images", cfg["images"]), r["dir"])
        S = r["size"]
        kind = r["kind"]
        params = {"$surfaceprop": "metalvehicle"}

        def alpha_of(sz):
            """The material's opacity: an alpha map (r["alpha"] glob; r["alpha_ch"] "A" = its alpha channel, else
            its grey value), or the base texture's own alpha (r["base_alpha"])."""
            if r.get("base_alpha"):
                return load(one(folder, r.get("base", "*_c&*")), sz).getchannel("A")
            p = r.get("alpha") and one(folder, r["alpha"])
            if not p:
                return None
            return load(p, sz).getchannel("A") if r.get("alpha_ch") == "A" else load(p, sz, "L")

        if kind in ("hull", "interior", "plain"):
            base = one(folder, r.get("base", "*_c&*"))
            c = load(base)
            sz = (S, _p2(S * c.size[1] / c.size[0]))
            rgb = c.convert("RGB").resize(sz, Image.LANCZOS)
            n = one(folder, r.get("normal", "*_n&*"))
            if kind == "interior" and n and "_o&" in os.path.basename(n):
                # n&o&g: occlusion in blue, baked into the colour
                occ = load(n, sz).getchannel("B")
                a = np.asarray(rgb).astype(np.float32) * (0.35 + 0.65 * np.asarray(occ)[..., None] / 255)
                rgb = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
            alpha = alpha_of(sz) if (r.get("alphatest") or r.get("translucent")) else None
            if alpha is not None:
                rgb.putalpha(alpha)
            vtex(mat, rgb, out_dir)
            if kind == "hull" and n:
                nm = load(n, sz)  # RGB normal, A gloss -> phong mask
                vtex(mat + "_n", nm, out_dir, normal=True)
                params.update({"$bumpmap": "%s/%s_n" % (mdir, mat), "$phong": "1", "$phongboost": "0.6",
                               "$phongexponent": "20", "$phongfresnelranges": "[0.3 0.6 1]"})
        elif kind == "alpha":
            c = load(one(folder, r.get("base", "*_c&*")))
            sz = (S, _p2(S * c.size[1] / c.size[0]))
            rgb = c.convert("RGB").resize(sz, Image.LANCZOS)
            a = alpha_of(sz)
            if a is None and r.get("opacity"):
                a = Image.new("L", sz, r["opacity"])
            if a is not None:
                rgb.putalpha(a)
            vtex(mat, rgb, out_dir)
        elif kind == "glass":
            p = r.get("alpha") and one(folder, r["alpha"])
            if p:
                a = load(p, None).getchannel("A") if r.get("alpha_ch") == "A" else load(p, None, "L")
                sz = (S, _p2(S * a.size[1] / a.size[0]))
                a = a.resize(sz, Image.LANCZOS).point(lambda v: 70 + v * 0.6)
            else:
                sz = (S // 4, S // 4)
                a = Image.new("L", sz, r.get("opacity", 120))
            img = Image.new("RGB", sz, tuple(r.get("tint", (18, 22, 24))))
            img.putalpha(a)
            vtex(mat, img, out_dir)
            params.update({"$translucent": "1", "$surfaceprop": "glass", "$envmap": "env_cubemap",
                           "$envmaptint": "[0.25 0.25 0.25]"})
        if r.get("translucent"):
            params.update({"$translucent": "1", "$nocull": "1"})
        if r.get("alphatest"):
            params.update({"$alphatest": "1", "$alphatestreference": str(r.get("cut", 0.45))})
        vmts[mat] = params
    for mat, r in cfg["materials"].items():
        if "alias" in r:
            p = dict(vmts[r["alias"]])
            if r.get("nocull"):
                p["$nocull"] = "1"
            vmts[mat] = (r["alias"], p)
    os.makedirs(out_dir, exist_ok=True)
    for mat, v in vmts.items():
        tex, params = (v if isinstance(v, tuple) else (mat, v))
        with open(os.path.join(out_dir, mat + ".vmt"), "w") as f:
            f.write('"VertexLitGeneric"\n{\n\t"$basetexture" "%s/%s"\n' % (mdir, tex))
            for k, val in params.items():
                f.write('\t"%s" "%s"\n' % (k, val))
            f.write("}\n")
    shutil.rmtree(os.path.join(GAME, "materialsrc", "tif_air_build"), ignore_errors=True)
    shutil.rmtree(os.path.join(GAME, "materials", "tif_air_build"), ignore_errors=True)
    return len(vmts)


# ---------------------------------------------------------------- compile

def qc(cfg, vid, parts, boxes_file, bones):
    model = cfg["model"]
    lines = ['$modelname "%s.mdl"' % model, '$cdmaterials "%s/"' % model, '$surfaceprop "metalvehicle"']
    lines.append('$bodygroup "body"\n{\n\tstudio "%s_body_lod0.smd"\n}' % vid)
    if "interior" in parts:
        lines.append('$bodygroup "interior"\n{\n\tstudio "%s_interior_lod0.smd"\n}' % vid)
    if "blades" in parts:
        lines.append('$bodygroup "rotor"\n{\n\tstudio "%s_blades_lod0.smd"\n\tstudio "%s_blur_lod0.smd"\n}' % (vid, vid))
    # Visible LODs only if the vehicle asks for them (user, 2026-11-13: a helicopter is one big, short-lived object;
    # no LOD popping). The shadow always uses the mid version: same outline, a third of the triangles.
    for dist, lod in zip(cfg.get("lods") or [], ("lod1", "lod2")):
        rep = []
        for part in parts:
            src = "%s_%s_lod0" % (vid, part)
            dst = "%s_%s_%s" % (vid, part, lod)
            rep.append(('\treplacemodel "%s" "%s"' % (src, dst)) if os.path.exists(os.path.join(BUILD, dst + ".smd"))
                       else '\tremovemodel "%s"' % src)
        lines.append("$lod %d\n{\n%s\n}" % (dist, "\n".join(rep)))
    rep = []
    for part in parts:
        dst = "%s_%s_lod1" % (vid, part)
        rep.append(('\treplacemodel "%s_%s_lod0" "%s"' % (vid, part, dst)) if os.path.exists(os.path.join(BUILD, dst + ".smd"))
                   else '\tremovemodel "%s_%s_lod0"' % (vid, part))
    lines.append("$shadowlod\n{\n%s\n}" % "\n".join(rep))
    for name, _, _ in bones:
        if name in cfg["tags"]:
            lines.append('$attachment "%s" "%s" 0 0 0 rotate 0 0 0' % (name, name))
    lines.append('$sequence "idle" "%s_body_lod0.smd" fps 30' % vid)
    lines.append('$collisionmodel "%s"\n{\n\t$concave\n\t$mass %d\n\t$maxconvexpieces 8\n}' % (boxes_file, cfg["mass"]))
    path = os.path.join(BUILD, vid + ".qc")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return path


def compile_model(cfg, path):
    run([STUDIOMDL, "-game", GAME, "-nop4", "-nox360", path])
    sub = cfg["model"].split("/")
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
    ap.add_argument("vehicle", choices=sorted(VEHICLES))
    ap.add_argument("--skip-tex", action="store_true")
    ap.add_argument("--skip-compile", action="store_true")
    a = ap.parse_args()
    cfg = VEHICLES[a.vehicle]
    os.makedirs(BUILD, exist_ok=True)
    nodes, skel, mats, verts = read_smd(cfg["smd"])
    mats, verts = merge_extras(cfg, nodes, skel, mats, verts)
    verts, agree = fix_winding(verts)
    print("read", len(mats), "tris,", len(nodes), "bones | winding agreed with normals: %.0f%%" % (agree * 100))
    bones, missing = skeleton(cfg, nodes, skel)
    if missing:
        print("tags not in model:", ", ".join(missing))
    meshes, stats = build_meshes(cfg, nodes, mats, verts)
    parts = [p for p in ("body", "interior", "blades", "blur") if (p, "lod0") in meshes]
    for part in parts:
        for L in LODS:
            tris = meshes.get((part, L["name"]))
            if tris:
                write_smd(os.path.join(BUILD, "%s_%s_%s.smd" % (a.vehicle, part, L["name"])), bones, tris)
        print(part, " | ".join("%s %d" % (L["name"], stats.get((part, L["name"]), 0)) for L in LODS))
    boxes = hull_boxes(cfg, meshes[("body", "lod0")])
    phys = "%s_phys.smd" % a.vehicle
    write_smd(os.path.join(BUILD, phys), bones, boxes=boxes)
    print("collision boxes", [(tuple(round(x) for x in lo), tuple(round(x) for x in hi)) for lo, hi in boxes])
    print("bones", len(bones), "| attachments", sum(1 for b in bones if b[0] in cfg["tags"]))
    if not a.skip_tex:
        print("materials", textures(cfg))
    path = qc(cfg, a.vehicle, parts, phys, bones)
    if not a.skip_compile:
        print("compiled:", ", ".join(compile_model(cfg, path)))


if __name__ == "__main__":
    main()
