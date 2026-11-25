"""Generates tif_cqb.vmf: a room-clearing test map for TIF's CQB (sv_clear / sv_building), 2026-11-20.

User: "make a cqb test map, with like some hl2 doored entrances and some wihtout. just so i can see the full scope of
the system as our old tif range isnt the best for it".

Every kind of doorway the CQB code handles, with stacking room outside each (x east, y north, floor z 0):
  A  kill house    x -1800..-300, y -1400..-200   corridor + three rooms. Outside: an HL2 door and an open doorway
                                                  (south), a 96-wide garage opening (east), a back door (north).
                                                  Inside: door / open doorway / LOCKED door off the corridor, an
                                                  open doorway and a door between rooms.
  B  two-storey    x 400..1000, y -1400..-600     front HL2 door, open back doorway, stairs up the stair hall
                                                  (stair doorways), a door between the rooms on each floor.
  C  locked shed   x 1500..1820, y -1300..-1000   one room behind a LOCKED door (kick / sledgehammer).
  D  hotel strip   x -1800..1400, y 600..1400     a long corridor with six rooms off it, alternating door / open /
                                                  locked / open / door / wide; open west entrance, door east, an
                                                  open doorway between rooms 2 and 3. Multi-room clears.
  yard / staging   south of A-C: low walls and crates; player start at (0, -2200) facing north.

Doors are props_c17/door01_left (48 x 108, origin on the hinge, mid-height) in 50 x 110 openings; open doorways are
50-96 wide, 110 high (lintel under a 144 ceiling, as BLD's gap_at wants).

Run:  python make_tif_cqb.py  -> tif_cqb.vmf next to this file. Compile with build_tif_cqb.ps1, then in game run
nav_generate once (doors don't block it).
"""
import pathlib
from make_tif_range import Map, GRASS, ROAD, YARD, LOW, CRATE, CONC, BRICK, WOOD, METAL, STAIR, SKY, NODRAW

OUT = pathlib.Path(__file__).with_name("tif_cqb.vmf")
DOOR_MODEL = "models/props_c17/door01_left.mdl"
OW, OH = 50, 110          # door opening
H = 144                    # single-storey ceiling
LIGHT = dict(_light="255 232 205 130", _lightHDR="-1 -1 -1 1", _quadratic_attn="1")


def door(m, x, y, along, z=0, locked=False, name=""):
    """An HL2 door in an opening whose low end is at (x, y) on a wall running along `along` ('x' or 'y'); x / y is the
    wall's centre line on the other axis. The hinge sits at the low end and the door spans the opening."""
    # door01_left: hinge at the origin, the slab along local +y, mid-height origin (hull z -54.3..54.3)
    if along == "x":
        origin, yaw = (x + 1, y, z + 57), 270    # local +y -> world +x
    else:
        origin, yaw = (x, y + 1, z + 57), 0      # local +y -> world +y
    kv = dict(model=DOOR_MODEL, angles="0 %d 0" % yaw, spawnflags="2048" if locked else "0", hardware="1",
              distance="90", speed="100", returndelay="-1", opendir="0", skin="1" if locked else "0", health="0",
              forceclosed="0")
    if name:
        kv["targetname"] = name
    m.ent("prop_door_rotating", origin, **kv)


def light(m, x, y, z=120):
    m.ent("light", (x, y, z), **LIGHT)


def build():
    m = Map()
    X, Y, ZTOP = 2560, 2560, 1024

    # --- Shell ----------------------------------------------------------------------------
    m.box(-X, -Y, -64, X, Y, 0, NODRAW, top=GRASS)
    m.box(-X - 32, -Y, -64, -X, Y, ZTOP, SKY)
    m.box(X, -Y, -64, X + 32, Y, ZTOP, SKY)
    m.box(-X - 32, -Y - 32, -64, X + 32, -Y, ZTOP, SKY)
    m.box(-X - 32, Y, -64, X + 32, Y + 32, ZTOP, SKY)
    m.box(-X - 32, -Y - 32, ZTOP, X + 32, Y + 32, ZTOP + 32, SKY)
    # Roads: the staging strip and a street between the south buildings and the hotel strip
    m.box(-2400, -2400, 0, 2400, -2000, 2, ROAD, True)
    m.box(-2400, 0, 0, 2400, 400, 2, ROAD, True)
    m.box(-200, -2000, 0, 200, 0, 2, ROAD, True)

    # --- A: kill house --------------------------------------------------------------------
    ax0, ay0, ax1, ay1 = -1800, -1400, -300, -200
    m.building(ax0, ay0, ax1, ay1, H, CONC, {
        "s": [(150, OW, 0, OH), (1200, OW, 0, OH)],     # x -1650 door; x -600 open doorway
        "e": [(700, 96, 0, OH)],                         # y -700..-604 garage opening into room 3
        "n": [(200, OW, 0, OH)],                         # x -1600 back door
    }, floor=WOOD)
    door(m, -1650, -1392, "x", name="a_front")
    door(m, -1600, -208, "x", name="a_back")
    # corridor (south) / rooms (north): wall at y -1100..-1084, x -1784..-316
    m.wall(-1784, -1100, -316, -1084, 0, H, CONC, [(184, OW, 0, OH), (684, OW, 0, OH), (1184, OW, 0, OH)])
    door(m, -1600, -1092, "x", name="a_r1")
    door(m, -600, -1092, "x", locked=True, name="a_r3_locked")
    # room dividers: x -1300 (open doorway y -700) and x -800 (door y -500)
    m.wall(-1300, -1084, -1284, -216, 0, H, CONC, [(384, OW, 0, OH)])
    m.wall(-800, -1084, -784, -216, 0, H, CONC, [(584, OW, 0, OH)])
    door(m, -792, -500, "y", name="a_r23")
    for p in ((-1550, -1240), (-800, -1240), (-1540, -650), (-1040, -650), (-550, -650)):
        light(m, *p)

    # --- B: two-storey house --------------------------------------------------------------
    bx0, by0, bx1, by1, F2 = 400, -1400, 1000, -600, 152
    m.building(bx0, by0, bx1, by1, 296, BRICK, {
        "s": [(100, OW, 0, OH)],                        # x 500 front door (west room)
        "n": [(400, OW, 0, OH)],                        # x 800 open back doorway (stair hall)
    }, floor=WOOD)
    door(m, 500, -1392, "x", name="b_front")
    # ground floor: west room / east stair hall, door between at y -1100
    m.wall(700, by0 + 16, 716, by1 - 16, 0, 144, BRICK, [(284, OW, 0, OH)])
    door(m, 708, -1100, "y", name="b_ground")
    # stairs up toward the south: bottom at y -860, top step y -1100..-1076 at 152
    m.stairs(870, -1100, 104, 10, "y+", F2)
    # upper slab with the hole over the stairs (x 856..984, y -1100..-860)
    m.box(bx0 + 16, by0 + 16, 144, 856, by1 - 16, F2, WOOD)
    m.box(856, by0 + 16, 144, bx1 - 16, -1100, F2, WOOD)
    m.box(856, -860, 144, bx1 - 16, by1 - 16, F2, WOOD)
    m.box(848, -1076, F2, 856, -860, F2 + 40, METAL, True)     # rail on the hole's west side
    # upper floor: dividing wall at x 700 with a door at y -1300
    m.wall(700, by0 + 16, 716, by1 - 16, F2, 296, BRICK, [(84, OW, F2, F2 + OH)])
    door(m, 708, -1300, "y", z=F2, name="b_upper")
    for p in ((550, -1000, 120), (850, -1250, 120), (550, -1000, 270), (850, -1250, 270), (900, -700, 270)):
        light(m, *p)

    # --- C: locked shed -------------------------------------------------------------------
    m.building(1500, -1300, 1820, -1000, 128, WOOD, {"s": [(130, OW, 0, OH)]}, floor=WOOD)
    door(m, 1630, -1292, "x", locked=True, name="c_locked")
    light(m, 1660, -1150, 104)

    # --- D: hotel strip -------------------------------------------------------------------
    dx0, dy0, dx1, dy1 = -1800, 600, 1400, 1400
    m.building(dx0, dy0, dx1, dy1, H, BRICK, {
        "w": [(90, 64, 0, OH)],                         # y 690..754 open west entrance
        "e": [(90, OW, 0, OH)],                         # y 690 east door
    }, floor=WOOD)
    door(m, 1392, 690, "y", name="d_east")
    # corridor (y 616..816) / rooms (y 832..1384): wall at y 816..832, x -1784..1384
    L = [-1784, -1256, -728, -200, 328, 856]
    R = [-1272, -744, -216, 312, 840, 1384]
    kinds = ["door", "open", "locked", "open", "door", "wide"]
    ops = []
    for i, k in enumerate(kinds):
        x = L[i] + 200
        ops.append((x - (-1784), 96 if k == "wide" else OW, 0, OH))
        if k in ("door", "locked"):
            door(m, x, 824, "x", locked=k == "locked", name="d_r%d" % (i + 1))
    m.wall(-1784, 816, 1384, 832, 0, H, BRICK, ops)
    # dividers between rooms (x = R[i]..L[i+1]); rooms 2 and 3 joined by an open doorway at y 1100
    for i in range(5):
        m.wall(R[i], 832, L[i + 1], 1384, 0, H, BRICK, [(268, OW, 0, OH)] if i == 1 else [])
    for i in range(6):
        light(m, (L[i] + R[i]) / 2, 1110)
    for x in range(-1500, 1301, 700):
        light(m, x, 716)

    # --- Yard / staging cover ------------------------------------------------------------
    for x, y, rot in ((-1500, -1800, 0), (-700, -1700, 0), (300, -1800, 0), (1300, -1700, 0), (2000, -1400, 90),
                      (-2100, -800, 90), (-1100, 200, 0), (700, 250, 0)):
        m.low_wall(x, y, rot)
    m.crates(-1000, -1650, 2)
    m.crates(1200, -650, 2, stack=True)
    m.crates(-100, -1000, 1, stack=True)
    m.block(150, -400, 90)
    m.block(1700, -400, 0)
    m.prop("models/props_c17/concrete_barrier001a.mdl", -400, -1650, 0)
    m.prop("models/props_c17/oildrum001.mdl", 1350, -1200, 0)

    # --- Entities -------------------------------------------------------------------------
    m.ent("info_player_start", (0, -2200, 8), angles="0 90 0")
    m.ent("light_environment", (0, -2200, 700), angles="0 120 0", pitch="-50",
          _light="255 240 215 380", _lightHDR="-1 -1 -1 1", _lightscaleHDR="1",
          _ambient="150 170 200 80", _ambientHDR="-1 -1 -1 1", _AmbientScaleHDR="1", SunSpreadAngle="5")
    m.ent("shadow_control", (0, -2200, 740), angles="50 120 0", color="80 80 90", distance="150")
    for p in ((-1000, -800, 64), (700, -1000, 64), (0, 1000, 64), (0, -1500, 64)):
        m.ent("env_cubemap", p)
    m.write(OUT)
    print("wrote", OUT, "world brushes:", len(m.world), "detail brushes:", len(m.detail), "entities:", len(m.ents))


if __name__ == "__main__":
    build()
