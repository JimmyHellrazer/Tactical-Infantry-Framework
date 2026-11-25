"""Generates tif_range.vmf: a blocky test range for the Tactical Infantry Framework.

Areas (x east, y north, floor at z=0, 1 unit ~ 1 inch):
  field     x -3900..-200, y -2900..550   scattered cover: low/tall walls, angled walls, corners,
                                           crates, raised tables (open underneath), a roofless house,
                                           physics props
  lane      y 1500..2632, x -3900..3900    long walled lane with cover along it, entries in the south wall
  compound  x 700..3900,  y -2900..300     walled base: north gate, two buildings with doors/windows
                                           and interior rooms, a guard tower with stairs, sandbags
  roads     ring round the map, a middle road, and a road to the compound gate
  spawn     raised platform with stairs between field and compound, facing the field

Run:  python make_tif_range.py  -> writes tif_range.vmf next to this file.
Compile with build_tif_range.ps1 (vbsp++ / vvis++ / vrad++), then in game run nav_generate once.
"""
import math
import pathlib

OUT = pathlib.Path(__file__).with_name("tif_range.vmf")

# Materials
GRASS = "NATURE/GRASSFLOOR002A"
ROAD = "CONCRETE/CONCRETEFLOOR028A"
YARD = "CONCRETE/CONCRETEFLOOR033K"
GRAVEL = "NATURE/GRAVELFLOOR004A"
WALL = "DEV/DEV_MEASUREWALL01A"
LOW = "DEV/DEV_MEASUREGENERIC01B"
CRATE = "DEV/DEV_MEASURECRATE02"
CONC = "CONCRETE/CONCRETEWALL074A"
BRICK = "BRICK/BRICKWALL001A"
WOOD = "WOOD/WOODWALL009A"
METAL = "METAL/METALWALL001A"
STAIR = "DEV/DEV_MEASURESTAIRS01A"
SKY = "TOOLS/TOOLSSKYBOX"
NODRAW = "TOOLS/TOOLSNODRAW"


class Ids:
    n = 0

    @classmethod
    def next(cls):
        cls.n += 1
        return cls.n


def fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def pt(p):
    return "(%s %s %s)" % (fmt(p[0]), fmt(p[1]), fmt(p[2]))


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def uv(normal):
    nx, ny, nz = (abs(c) for c in normal)
    if nz >= nx and nz >= ny:
        return "[1 0 0 0] 0.25", "[0 -1 0 0] 0.25"
    if nx >= ny:
        return "[0 1 0 0] 0.25", "[0 0 -1 0] 0.25"
    return "[1 0 0 0] 0.25", "[0 0 -1 0] 0.25"


def side(corner, e1, e2, normal, mat):
    # VBSP plane: normal = cross(p0 - p1, p2 - p1), must point out of the brush.
    p1 = corner
    p0 = add(corner, e1)
    p2 = add(corner, e2)
    u, v = uv(normal)
    return (
        '\t\tside\n\t\t{\n'
        '\t\t\t"id" "%d"\n\t\t\t"plane" "%s %s %s"\n\t\t\t"material" "%s"\n'
        '\t\t\t"uaxis" "%s"\n\t\t\t"vaxis" "%s"\n\t\t\t"rotation" "0"\n'
        '\t\t\t"lightmapscale" "16"\n\t\t\t"smoothing_groups" "0"\n\t\t}\n'
    ) % (Ids.next(), pt(p0), pt(p1), pt(p2), mat, u, v)


def prism(poly, z0, z1, mat, top=None, bottom=None):
    """Convex brush: 2D polygon (counter-clockwise) extruded from z0 to z1."""
    s = '\tsolid\n\t{\n\t\t"id" "%d"\n' % Ids.next()
    a = poly[0]
    s += side((a[0], a[1], z1), (1, 0, 0), (0, 1, 0), (0, 0, 1), top or mat)
    s += side((a[0], a[1], z0), (0, 1, 0), (1, 0, 0), (0, 0, -1), bottom or mat)
    for i in range(len(poly)):
        A, B = poly[i], poly[(i + 1) % len(poly)]
        d = (B[0] - A[0], B[1] - A[1], 0)
        n = (d[1], -d[0], 0)
        s += side((A[0], A[1], z0), d, (0, 0, z1 - z0), n, mat)
    s += '\t\teditor\n\t\t{\n\t\t\t"color" "0 180 220"\n\t\t\t"visgroupshown" "1"\n\t\t\t"visgroupautoshown" "1"\n\t\t}\n'
    s += '\t}\n'
    return s


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def orect(cx, cy, length, thick, rot):
    """Rectangle centred on cx,cy, `length` along yaw `rot` degrees, counter-clockwise."""
    r = math.radians(rot)
    ux, uy = math.cos(r), math.sin(r)
    vx, vy = -uy, ux
    hl, ht = length / 2, thick / 2
    return [
        (cx - ux * hl - vx * ht, cy - uy * hl - vy * ht),
        (cx + ux * hl - vx * ht, cy + uy * hl - vy * ht),
        (cx + ux * hl + vx * ht, cy + uy * hl + vy * ht),
        (cx - ux * hl + vx * ht, cy - uy * hl + vy * ht),
    ]


class Map:
    def __init__(self):
        self.world = []      # world brushes (seal the map, cut visibility)
        self.detail = []     # func_detail brushes (cover pieces, furniture)
        self.ents = []

    def box(self, x0, y0, z0, x1, y1, z1, mat, detail=False, top=None):
        (self.detail if detail else self.world).append(prism(rect(x0, y0, x1, y1), z0, z1, mat, top=top))

    def poly(self, poly, z0, z1, mat, detail=True):
        (self.detail if detail else self.world).append(prism(poly, z0, z1, mat))

    def ent(self, cls, origin, **kv):
        self.ents.append((cls, origin, kv))

    # A wall from (x0,y0) to (x1,y1) along x or y, with openings: (offset, width, bottom, top),
    # offset measured from the wall's low end.
    def wall(self, x0, y0, x1, y1, z0, z1, mat, openings=(), detail=False):
        along_x = abs(x1 - x0) >= abs(y1 - y0)
        if along_x:
            a, b = min(x0, x1), max(x0, x1)
            lo, hi = min(y0, y1), max(y0, y1)
        else:
            a, b = min(y0, y1), max(y0, y1)
            lo, hi = min(x0, x1), max(x0, x1)

        def piece(s0, s1, za, zb):
            if s1 - s0 < 1 or zb - za < 1:
                return
            if along_x:
                self.box(s0, lo, za, s1, hi, zb, mat, detail)
            else:
                self.box(lo, s0, za, hi, s1, zb, mat, detail)

        cur = a
        for off, w, bot, top in sorted(openings):
            o0, o1 = a + off, a + off + w
            piece(cur, o0, z0, z1)
            piece(o0, o1, z0, bot)
            piece(o0, o1, top, z1)
            cur = o1
        piece(cur, b, z0, z1)

    def building(self, x0, y0, x1, y1, h, mat, doors, t=16, roof=True, floor=None):
        """doors: dict side -> list of (offset, width, bottom, top). Sides s, n, w, e."""
        self.wall(x0, y0, x1, y0 + t, 0, h, mat, doors.get("s", ()))
        self.wall(x0, y1 - t, x1, y1, 0, h, mat, doors.get("n", ()))
        # West/east walls run between the north and south walls; offsets still count from y0.
        shift = lambda ops: [(o - t, w, b, tp) for (o, w, b, tp) in ops]
        self.wall(x0, y0 + t, x0 + t, y1 - t, 0, h, mat, shift(doors.get("w", ())))
        self.wall(x1 - t, y0 + t, x1, y1 - t, 0, h, mat, shift(doors.get("e", ())))
        if roof:
            self.box(x0, y0, h, x1, y1, h + 8, CONC)
        if floor:
            self.box(x0 + t, y0 + t, 0, x1 - t, y1 - t, 2, floor)

    def stairs(self, x0, y0, width, steps, direction, top_z, mat=STAIR, step_d=24):
        """Solid stairs going DOWN from (x0,y0) in direction 'x-', 'x+', 'y-' or 'y+'.
        The first step is top_z high; each next one 16 lower."""
        for i in range(steps):
            z = top_z - i * 16
            if z <= 0:
                break
            if direction == "y-":
                self.box(x0, y0 - (i + 1) * step_d, 0, x0 + width, y0 - i * step_d, z, mat, True)
            elif direction == "y+":
                self.box(x0, y0 + i * step_d, 0, x0 + width, y0 + (i + 1) * step_d, z, mat, True)
            elif direction == "x-":
                self.box(x0 - (i + 1) * step_d, y0, 0, x0 - i * step_d, y0 + width, z, mat, True)
            else:
                self.box(x0 + i * step_d, y0, 0, x0 + (i + 1) * step_d, y0 + width, z, mat, True)

    # Cover pieces ------------------------------------------------------------------
    def low_wall(self, cx, cy, rot=0, length=160):
        self.poly(orect(cx, cy, length, 12, rot), 0, 40, LOW)

    def tall_wall(self, cx, cy, rot=0, length=192):
        self.poly(orect(cx, cy, length, 16, rot), 0, 128, WALL)

    def block(self, cx, cy, rot=0):
        self.poly(orect(cx, cy, 96, 24, rot), 0, 44, CONC)

    def crates(self, cx, cy, n=2, stack=False):
        for i in range(n):
            x = cx + i * 50
            self.box(x - 24, cy - 24, 0, x + 24, cy + 24, 48, CRATE, True)
        if stack:
            self.box(cx - 24, cy - 24, 48, cx + 24, cy + 24, 96, CRATE, True)

    def table(self, cx, cy):
        # Open underneath: tests the chest-height cover ray.
        self.box(cx - 48, cy - 24, 32, cx + 48, cy + 24, 36, WOOD, True)
        for dx in (-44, 40):
            for dy in (-20, 16):
                self.box(cx + dx, cy + dy, 0, cx + dx + 4, cy + dy + 4, 32, WOOD, True)

    def corner(self, cx, cy, flip=1):
        self.box(cx, cy, 0, cx + 192, cy + 16, 128, WALL, True)
        self.box(cx if flip > 0 else cx + 176, cy + 16, 0, (cx + 16) if flip > 0 else cx + 192, cy + 160, 128, WALL, True)

    def prop(self, model, x, y, yaw=0, z=4):
        # Spawned a little above the floor, awake, so they settle onto it.
        self.ent("prop_physics", (x, y, z), model=model, angles="0 %d 0" % yaw, spawnflags="0",
                 skin="0", fademindist="-1", fadescale="1", physdamagescale="0.1")

    # Output ------------------------------------------------------------------------
    def write(self, path):
        out = ['versioninfo\n{\n\t"editorversion" "400"\n\t"editorbuild" "8000"\n\t"mapversion" "1"\n'
               '\t"formatversion" "100"\n\t"prefab" "0"\n}\n',
               'visgroups\n{\n}\n',
               'viewsettings\n{\n\t"bSnapToGrid" "1"\n\t"bShowGrid" "1"\n\t"bShowLogicalGrid" "0"\n'
               '\t"nGridSpacing" "16"\n\t"bShow3DGrid" "0"\n}\n',
               'world\n{\n\t"id" "%d"\n\t"mapversion" "1"\n\t"classname" "worldspawn"\n'
               '\t"skyname" "sky_day01_01"\n\t"maxpropscreenwidth" "-1"\n'
               '\t"detailvbsp" "detail.vbsp"\n\t"detailmaterial" "detail/detailsprites"\n' % Ids.next()]
        out += self.world
        out.append('}\n')
        if self.detail:
            out.append('entity\n{\n\t"id" "%d"\n\t"classname" "func_detail"\n' % Ids.next())
            out += self.detail
            out.append('}\n')
        for cls, o, kv in self.ents:
            s = 'entity\n{\n\t"id" "%d"\n\t"classname" "%s"\n' % (Ids.next(), cls)
            for k, v in kv.items():
                s += '\t"%s" "%s"\n' % (k, v)
            s += '\t"origin" "%s %s %s"\n}\n' % (fmt(o[0]), fmt(o[1]), fmt(o[2]))
            out.append(s)
        out.append('cameras\n{\n\t"activecamera" "-1"\n}\ncordon\n{\n\t"mins" "(-1024 -1024 -1024)"\n'
                   '\t"maxs" "(1024 1024 1024)"\n\t"active" "0"\n}\n')
        path.write_text("".join(out), encoding="utf-8")


def build():
    m = Map()
    X, Y, ZTOP = 4608, 3584, 2560

    # --- Shell: ground slab, sky walls and ceiling --------------------------------------
    m.box(-X, -Y, -64, X, Y, 0, NODRAW, top=GRASS)
    m.box(-X - 32, -Y, -64, -X, Y, ZTOP, SKY)
    m.box(X, -Y, -64, X + 32, Y, ZTOP, SKY)
    m.box(-X - 32, -Y - 32, -64, X + 32, -Y, ZTOP, SKY)
    m.box(-X - 32, Y, -64, X + 32, Y + 32, ZTOP, SKY)
    m.box(-X - 32, -Y - 32, ZTOP, X + 32, Y + 32, ZTOP + 32, SKY)

    # --- Roads (2 units thick on the ground) ---------------------------------------------
    RO, RW = 4350, 320
    m.box(-RO, -3350, 0, RO, -3350 + RW, 2, ROAD, True)          # south
    m.box(-RO, 3350 - RW, 0, RO, 3350, 2, ROAD, True)            # north
    m.box(-RO, -3350 + RW, 0, -RO + RW, 3350 - RW, 2, ROAD, True)  # west
    m.box(RO - RW, -3350 + RW, 0, RO, 3350 - RW, 2, ROAD, True)    # east
    m.box(-RO + RW, 700, 0, RO - RW, 1020, 2, ROAD, True)          # middle
    m.box(2040, 300, 0, 2360, 700, 2, ROAD, True)                  # to the compound gate

    # --- Field ----------------------------------------------------------------------------
    for i, x in enumerate((-3600, -2900, -2200, -1500, -800)):
        m.low_wall(x, -2600, 0 if i % 2 == 0 else 30)
    for x in (-3300, -2500, -1700, -900):
        m.tall_wall(x, -2050, 0)
    m.crates(-2150, -1950, 2, stack=True)
    # Roofless house: corner and doorway cover.
    m.building(-2680, -1560, -2360, -1300, 112, BRICK,
               {"s": [(40, 64, 0, 100)], "n": [(200, 64, 0, 100)], "w": [(110, 64, 44, 88)], "e": [(130, 64, 44, 88)]},
               roof=False)
    m.table(-3500, -1400)
    m.table(-1200, -1450)
    m.corner(-1900, -1500, 1)
    for x in (-3600, -3100, -2100, -1600, -700):
        m.block(x, -850, 0)
    m.tall_wall(-3000, -800, 45)
    m.tall_wall(-1350, -780, -45)
    for x in (-3400, -2400, -1400):
        m.low_wall(x, -200, 0, 256)
    m.crates(-2900, -150, 3)
    m.crates(-1900, -250, 1, stack=True)
    m.tall_wall(-3200, 330, 60)
    m.tall_wall(-2200, 300, -30)
    m.corner(-1100, 250, -1)
    m.low_wall(-600, 300, 90)
    # Physics props (the prop cover path)
    m.prop("models/props_c17/concrete_barrier001a.mdl", -3250, -1700, 0)
    m.prop("models/props_c17/concrete_barrier001a.mdl", -1050, -1100, 90)
    m.prop("models/props_junk/wood_crate001a.mdl", -2750, -600, 15, 24)
    m.prop("models/props_junk/wood_crate001a.mdl", -500, -2200, 0, 24)
    m.prop("models/props_c17/oildrum001.mdl", -2450, -2350, 0)
    m.prop("models/props_c17/oildrum001.mdl", -2400, -2390, 0)
    m.prop("models/props_wasteland/kitchen_counter001b.mdl", -1700, -2400, 90)
    m.prop("models/props_c17/furnituretable001a.mdl", -3700, -300, 0, 18)

    # --- Long lane ------------------------------------------------------------------------
    # South wall with three entries (at x -2000, 0 and 2000).
    m.wall(-3900, 1500, 3900, 1532, 0, 192, CONC, [(1772, 256, 0, 192), (3772, 256, 0, 192), (5772, 256, 0, 192)])
    m.box(-3900, 2600, 0, 3900, 2632, 192, CONC)
    m.box(-3932, 1500, 0, -3900, 2632, 192, CONC)
    m.box(3900, 1500, 0, 3932, 2632, 192, CONC)
    kinds = ["low", "tall", "crates", "block", "table", "low", "corner", "crates_stack"]
    for i, x in enumerate(range(-3600, 3601, 450)):
        y = 1720 if i % 2 == 0 else 2400
        k = kinds[i % len(kinds)]
        if k == "low":
            m.low_wall(x, y)
        elif k == "tall":
            m.tall_wall(x, y)
        elif k == "crates":
            m.crates(x, y, 2)
        elif k == "crates_stack":
            m.crates(x, y, 2, stack=True)
        elif k == "block":
            m.block(x, y)
        elif k == "table":
            m.table(x, y)
        elif k == "corner":
            m.corner(x - 96, y - 80, 1)
        if i % 2 == 1:
            m.block(x + 200, 2060, 90)
    m.prop("models/props_c17/concrete_barrier001a.mdl", -1500, 2050, 0)
    m.prop("models/props_c17/concrete_barrier001a.mdl", 1700, 2100, 90)

    # --- Compound -------------------------------------------------------------------------
    CX0, CY0, CX1, CY1, CH = 700, -2900, 3900, 300, 160
    m.box(CX0 + 24, CY0 + 24, 0, CX1 - 24, CY1 - 24, 2, YARD, True)
    m.wall(CX0, CY1 - 24, CX1, CY1, 0, CH, CONC, [(2080 - CX0, 240, 0, CH)])        # north, gate
    m.wall(CX0, CY0, CX1, CY0 + 24, 0, CH, CONC)                                        # south
    m.wall(CX0, CY0 + 24, CX0 + 24, CY1 - 24, 0, CH, CONC, [(1400, 64, 0, 104)])        # west, side door
    m.wall(CX1 - 24, CY0 + 24, CX1, CY1 - 24, 0, CH, CONC)                              # east
    # Barracks: two rooms joined by a door.
    m.building(1000, -1100, 1800, -500, 144, BRICK,
               {"n": [(360, 64, 0, 104)], "s": [(100, 64, 0, 104)],
                "w": [(150, 64, 48, 96), (400, 64, 48, 96)], "e": [(250, 64, 48, 96)]}, floor=WOOD)
    m.wall(1392, -1084, 1408, -516, 0, 144, BRICK, [(250, 64, 0, 104)])
    m.ent("light", (1200, -800, 120), _light="255 230 200 140", _lightHDR="-1 -1 -1 1", _quadratic_attn="1")
    m.ent("light", (1600, -800, 120), _light="255 230 200 140", _lightHDR="-1 -1 -1 1", _quadratic_attn="1")
    # HQ: corridor along the south, two rooms north of it.
    m.building(2600, -2600, 3600, -1600, 144, CONC,
               {"w": [(200, 64, 0, 104)], "n": [(150, 64, 0, 104), (700, 64, 48, 96)],
                "e": [(600, 64, 48, 96)], "s": [(400, 64, 48, 96)]}, floor=WOOD)
    m.wall(2616, -2116, 3584, -2100, 0, 144, CONC, [(200, 64, 0, 104), (700, 64, 0, 104)])
    m.wall(3092, -2100, 3108, -1616, 0, 144, CONC, [(250, 64, 0, 104)])
    for p in ((2850, -1850), (3350, -1850), (3100, -2350)):
        m.ent("light", (p[0], p[1], 120), _light="255 230 200 140", _lightHDR="-1 -1 -1 1", _quadratic_attn="1")
    # Guard tower in the north-east corner, stairs down to the west.
    for lx, ly in ((3550, 30), (3734, 30), (3550, 214), (3734, 214)):
        m.box(lx, ly, 0, lx + 16, ly + 16, 256, WOOD, True)
    m.box(3550, 30, 256, 3750, 230, 264, WOOD, True)
    m.box(3550, 126, 264, 3558, 230, 304, WOOD, True)   # west parapet, gap for the stairs
    m.box(3742, 30, 264, 3750, 230, 304, WOOD, True)
    m.box(3558, 30, 264, 3742, 38, 304, WOOD, True)
    m.box(3558, 222, 264, 3742, 230, 304, WOOD, True)
    m.stairs(3550, 30, 96, 16, "x-", 256)
    # Yard cover
    m.low_wall(2000, 120, 0)
    m.low_wall(2400, 120, 0)
    m.crates(1950, -1400, 2, stack=True)
    m.crates(2300, -900, 3)
    m.block(2200, -2000, 90)
    m.prop("models/props_c17/oildrum001.mdl", 2500, -400, 0)
    m.prop("models/props_c17/oildrum001.mdl", 2540, -430, 0)
    m.prop("models/props_c17/concrete_barrier001a.mdl", 1500, 50, 0)
    m.prop("models/props_junk/wood_crate001a.mdl", 3300, -1000, 30, 24)

    # --- Two-storey building (room clearing) ------------------------------------------------
    # x 0..560, y -600..240. Ground: south-west room, north-west room, stair hall on the east
    # half. Upstairs: a south room and a north room. Floor slab at z 144..152, roof at 296.
    BX0, BY0, BX1, BY1, F2 = 0, -600, 560, 240, 152
    m.building(BX0, BY0, BX1, BY1, 296, BRICK, {
        "s": [(380, 64, 0, 104), (150, 64, 192, 240), (420, 64, 192, 240)],
        "n": [(120, 64, 0, 104), (200, 64, 192, 240)],
        "w": [(200, 64, 0, 104), (600, 64, 48, 96), (300, 64, 192, 240), (650, 64, 192, 240)],
        "e": [(300, 64, 48, 96), (500, 64, 192, 240)],
    }, floor=WOOD)
    # Ground floor walls (under the slab)
    m.wall(280, BY0 + 16, 296, BY1 - 16, 0, 144, BRICK, [(134, 64, 0, 104), (534, 64, 0, 104)])
    m.wall(BX0 + 16, -196, 280, -180, 0, 144, BRICK, [(100, 64, 0, 104)])
    # Stairs up the east side, top at the north end
    m.stairs(440, 200, 104, 10, "y-", F2)
    # Upper floor slab with a hole over the stairs
    m.box(BX0 + 16, BY0 + 16, 144, 440, BY1 - 16, F2, WOOD)
    m.box(440, BY0 + 16, 144, BX1 - 16, -40, F2, WOOD)
    m.box(440, 200, 144, BX1 - 16, BY1 - 16, F2, WOOD)
    m.box(424, -40, F2, 440, 120, F2 + 40, METAL, True)   # rail along the stair hole
    # Upper floor dividing wall
    m.wall(BX0 + 16, -196, BX1 - 16, -180, F2, 296, BRICK, [(120, 64, F2, F2 + 104)])
    for p in ((140, -400, 120), (140, 20, 120), (420, -300, 120), (280, -400, 270), (280, 20, 270)):
        m.ent("light", p, _light="255 230 200 120", _lightHDR="-1 -1 -1 1", _quadratic_attn="1")

    # --- Spawn platform -------------------------------------------------------------------
    PZ = 320
    m.box(100, -1300, 0, 500, -900, PZ, CONC)
    m.box(228, -1300, PZ, 500, -1292, PZ + 40, METAL, True)    # south rail, gap over the stairs
    m.box(100, -908, PZ, 500, -900, PZ + 40, METAL, True)
    m.box(100, -1292, PZ, 108, -908, PZ + 40, METAL, True)
    m.box(492, -1292, PZ, 500, -908, PZ + 40, METAL, True)
    m.stairs(100, -1300, 128, 20, "y-", PZ)

    # --- Entities -------------------------------------------------------------------------
    m.ent("info_player_start", (300, -1100, PZ + 4), angles="0 180 0")
    m.ent("light_environment", (300, -1100, 600), angles="0 135 0", pitch="-50",
          _light="255 240 215 400", _lightHDR="-1 -1 -1 1", _lightscaleHDR="1",
          _ambient="150 170 200 70", _ambientHDR="-1 -1 -1 1", _AmbientScaleHDR="1", SunSpreadAngle="5")
    m.ent("shadow_control", (300, -1100, 640), angles="50 135 0", color="80 80 90", distance="150")
    m.ent("env_cubemap", (-2000, -1200, 64))
    m.ent("env_cubemap", (0, 2050, 64))
    m.ent("env_cubemap", (2300, -800, 64))
    m.write(OUT)
    print("wrote", OUT, "world brushes:", len(m.world), "detail brushes:", len(m.detail), "entities:", len(m.ents))


if __name__ == "__main__":
    build()
