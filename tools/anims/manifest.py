# TIF MW19 character "mw_male": which MW19 clip plays each TIF role.
# Build: python "K:/mods map pics/smh_cod_anim_baker/tools/tif_mw_build.py" K:/jimmyproject/tif_mw/manifest.py --compile
#
# Role names follow TIF's GTA clip names where TIF asks for a role (idle, walk, run, sprint, mstg_*, crouch_mstg_*);
# direction sets only need the "<prefix>fwd_<deg>_loop" / "bwd_" pattern (TIF sorts them by real travel).
# MW19 strafe numbers are numpad directions: 8 forward, 2 back, 4 left, 6 right.

SOURCE = "K:/duglastakedown"
# MW22 (MWII) AI clips: only names MW19 lacks are taken from here (the builder looks in SOURCE first). MW22 re-rigged
# the gun bone (j_gun static, motion in j_gun_adjust), so TIF holds the gun from the hand on these (gun_holds.py).
# Export 2 (the full dump) first: its clips are clean. Export 1 has a bind-pose key at frame 0 on every bone (junk
# first frames, loops that don't close) and is only the fallback for the 7 names export 2 lacks; the builder drops
# that key on files from FIX_FIRST_KEY.
EXTRA_SOURCES = ["K:/mw22 anims 2/xanims", "K:/mw22 anims"]
FIX_FIRST_KEY = ["K:/mw22 anims"]
BUILD = "K:/jimmyproject/tif_mw/build"
# (TIF 0.37.0: built straight into the base addon; the separate tif_mw_anims addon was folded into it)
ADDON = "K:/SteamLibrary/steamapps/common/GarrysMod/garrysmod/addons/tactical_infantry_framework"
CHARACTER = "mw_male"
NAME = "MW19 Male (ValveBiped)"
MODEL_DIR = "tif_mw"

DIRS = {8: "fwd_0", 9: "fwd_-45", 6: "fwd_-90", 3: "bwd_-135", 2: "bwd_180", 1: "bwd_135", 4: "fwd_90", 7: "fwd_45"}
LOOP = {"loop": True}


# MW22's AI strafes (and their starts / stops) carry placeholder arms: CoD lays its aim layer over their upper body,
# and their gun bone hangs fixed off the shoulder (forward walk ~36 deg up, strafing left ~7 down; user screenshot,
# 2026-11-18). They take the AI aimed idle's upper body instead: its first frame on the 13 bones of MW19's ready pose
# (spine4, neck, head, arms, j_gun); legs and lower spine stay the strafe's.
AI_ARMS = {"overlay": "sdr_com_exposed_stand_idle01", "overlay_mask": "sdr_com_exposed_stand_ready"}
# The same for MW22's crouched aimed clips (in-place crouch turns, turning crouch-downs: gun ~30 deg low otherwise).
AI_ARMS_CROUCH = {"overlay": "sdr_com_exposed_crouch_idle01", "overlay_mask": "sdr_com_exposed_crouch_ready"}


def strafe(prefix, clip_fmt, alt3=False, ai_arms=False):
    out = []
    for n, d in DIRS.items():
        clip = clip_fmt.format(f"{n}_alt" if (alt3 and n == 3) else n)
        out.append((f"{prefix}{d}_loop", clip, dict(LOOP, **AI_ARMS) if ai_arms else LOOP))
    return out


FAMILIES = {
    # Stage 1: everyday locomotion (weapon up; relaxed carry comes with Stage 2's upper-body work)
    "move": [
        # Calm (TIF relaxed mode, unaware): MW19's stealth patrol idle and walk, weapon lowered (Stage 5).
        ("idle", "reb_stl_patrol_idle01", {"loop": True, "center": False}),
        ("walk", "reb_stl_patrol_walk01", {"loop": True, "center": False}),
        # AI loops (user, 2026-11-17: AI / SP animations, not MP): MW19's AI jog (172 u/s) and AI run (217, the
        # CoD AI pace; TIF's sprint). Were sdr_mp_strafe_jog_8 / sdr_mp_strafe_sprint_ar_8 (MP).
        ("run", "sdr_com_jog_loop01", LOOP),
        ("sprint", "sdr_com_run_loop01", LOOP),
        # Aimed idles: MW19's AI exposed idles (were MP sdr_mp_stand_idle02 / sdr_mp_crouch_idle).
        ("mstg_idle", "sdr_com_exposed_stand_idle01", LOOP),
        ("crouch_mstg_idle", "sdr_com_exposed_crouch_idle01", LOOP),
    ]
    # Aimed strafes: MW22's AI set (walk 90-104 u/s, jog 150-178), one stride per loop. Were MW19 MP
    # (sdr_mp_strafe_walk / jog). Crouched strafes stay MP: AI has no 8-way crouch strafe.
    + strafe("mstg_walk_", "sdr_com_strafe_walk_{}", ai_arms=True)
    + strafe("mstg_run_", "sdr_com_strafe_jog_{}", ai_arms=True)
    + strafe("crouch_mstg_walk_", "sdr_mp_strafe_crouch_walk_{}", alt3=True)
    + strafe("crouch_mstg_run_", "sdr_mp_strafe_crouch_fast_{}", alt3=True),

    # Stage 2: reloads, layered over the legs as upper-body clips ("ub" builds a masked <seq>_ub as well)
    "weapon": [
        ("mw_reload", "sdr_com_exposed_reload01", {"ub": True, "loop": False}),
        ("mw_reload_pistol", "sdr_com_exposed_reload01_pistol", {"ub": True, "loop": False}),
        ("mw_reload_lmg", "sdr_com_exposed_stand_lmg_reload01_fixed", {"ub": True, "loop": False}),
    ],

    # Stage 3: cover (built by cover_family() below)
    "cover": [],

    # Stage 5: calm posture + graded reactions (built by passive_family() below)
    "passive": [],

    # Stage 4: prone (TIF's prone state: down -> in (idle / 8-way crawl) -> up), on the host itself.
    # The get-down clip starts with the feet where idle stands, the get-up ends that way, and the prone loops
    # put their pelvis where the get-down ends, so the phases join without a jump.
    "prone": [
        ("mwp_down", "sdr_com_exposed_stand_to_exposed_prone", {"loop": False}),
        ("mwp_up", "sdr_com_exposed_prone_to_exposed_stand", {"loop": False, "center": "last"}),
        ("mwp_idle", "sdr_mp_prone_idle_1", {"loop": True, "center": ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")}),
        ("mwp_flash", "sdr_com_exposed_prone_flashbang_srt_react_01",
         {"loop": False, "center": ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")}),
    ] + [(f"mwp_crawl_{d}_loop", f"sdr_mp_prone_strafe_fast_{n}",
          {"loop": True, "center": ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")}) for n, d in DIRS.items()],

    # Doors and flashbang reactions (the first test set)
    "react": [(c, c) for c in (
        "sdr_com_inter_ldoor_kick_ex_cqb_a", "sdr_com_inter_ldoor_kick_ex_run_a", "sdr_com_inter_ldoor_shoulder_ex_run_a",
        "sdr_com_inter_ldoor_tac_ex_cqb_a", "sdr_com_inter_rdoor_tac_ex_cqb_a", "sdr_com_inter_ldoor_flash_a",
        "sdr_com_inter_rdoor_flash_a", "sdr_com_inter_ldoor_smoke_a", "sdr_com_inter_rdoor_smoke_a",
        "sdr_com_inter_dbldoor_kick_ex_cqb_a", "sdr_com_inter_ldoor_wall_kick_ex_cqb_a",
        "sdr_com_inter_rdoor_wall_kick_ex_cqb_a", "sdr_com_inter_ldoor_90_pull_ex_idle_a",
        "sdr_com_inter_rdoor_90_pull_ex_idle_a", "sdr_com_exposed_stand_flashbang_react_01",
        "sdr_com_exposed_stand_flashbang_react_02", "sdr_com_exposed_stand_flashbang_srt_react_01",
        "sdr_com_exposed_stand_flashbang_srt_react_02", "sdr_com_exposed_crouch_flashbang_react_01",
        "sdr_com_exposed_crouch_flashbang_srt_react_01", "sdr_com_cover_stand_flashbang_react_01",
        "sdr_com_cover_crouch_flashbang_react_01", "sdr_com_cover_left_flashbang_srt_react_01",
        "sdr_com_cover_right_flashbang_srt_react_01",
    )],
}

# Cover: MW19's AI cover nodes. TIF type ls = cover_left_stand (high cover, corner on the left), rs =
# cover_right_stand, cr = cover_crouch (low wall, aims over the top). Roles: mwc_<type>_<role>.
# Every cover clip keeps its place relative to the node (no foot centring): hide, lean, aim and the arrivals
# all line up on it. Arrival/exit numbers are directions; TIF picks them from their measured root motion.
import os as _os

_SRC = "K:/duglastakedown"
_COVER = {"center": False}


def _has(name):
    return _os.path.exists(f"{_SRC}/{name}.seanim")


def cover_family():
    out = []

    def add(role, clip, loop=False):
        if _has(clip):
            out.append((role, clip, dict(_COVER, loop=loop)))

    for t, p in (("ls", "sdr_com_cover_left_stand"), ("rs", "sdr_com_cover_right_stand")):
        add(f"mwc_{t}_hide", f"{p}_hide_idle", True)
        add(f"mwc_{t}_twitch1", f"{p}_hide_twitch02")
        add(f"mwc_{t}_twitch2", f"{p}_hide_twitch03")
        add(f"mwc_{t}_look_in", f"{p}_hide_to_look")
        add(f"mwc_{t}_look", f"{p}_look_idle", True)
        add(f"mwc_{t}_look_out", f"{p}_look_to_hide")
        add(f"mwc_{t}_lean_in", f"{p}_hide_to_lean")
        add(f"mwc_{t}_lean", f"{p}_lean_idle", True)
        out.append((f"mwc_{t}_aim", None, dict(_COVER, loop=True, blend9=f"{p}_lean_aim_{{}}", additive=True)))
        add(f"mwc_{t}_lean_out", f"{p}_lean_to_hide")
        add(f"mwc_{t}_blind1", f"{p}_blindfire01")
        add(f"mwc_{t}_blind2", f"{p}_blindfire02")
        add(f"mwc_{t}_reload", f"{p}_reload_01" if _has(f"{p}_reload_01") else f"{p}_reload01")
        add(f"mwc_{t}_flash", f"{p}_flash_react01")
        other = "right" if t == "ls" else "left"
        add(f"mwc_{t}_switch", f"{p}_to_cover_{other}_stand")
    p = "sdr_com_cover_crouch"
    add("mwc_cr_hide", f"{p}_hide_twitch03", True)
    add("mwc_cr_twitch1", f"{p}_hide_twitch07")
    add("mwc_cr_twitch2", f"{p}_hide_twitch08")
    add("mwc_cr_look_in", f"{p}_hide_to_look")
    add("mwc_cr_look", f"{p}_look_idle", True)
    add("mwc_cr_look_out", f"{p}_look_to_hide")
    add("mwc_cr_lean_in", f"{p}_hide_to_aim")
    out.append(("mwc_cr_aim", None, dict(_COVER, loop=True, blend9=f"{p}_aim_aim_{{}}", additive=True)))
    add("mwc_cr_lean_out", f"{p}_aim_to_hide")
    # (rvar only: TIF's low cover has the wall on the soldier's left, as the hide / hide_to_aim set is authored. The
    # lvar clips are for cover on his right: their gun comes up ~110 deg the other way, into the room (user clip,
    # 2026-11-17; measured on j_gun's barrel axis against crouch aim_5).)
    add("mwc_cr_blind1", f"{p}_rvar_blindfire02")
    add("mwc_cr_blind2", f"{p}_rvar_blindfire01")
    add("mwc_cr_reload", f"{p}_reload01")
    add("mwc_cr_flash", f"{p}_flash_react01")
    # Arrivals (jog/run, lead foot l/r, direction 1-9; crouch has 8l/8r) and exits (jog, direction 1-9)
    for t, p in (("ls", "sdr_com_cover_left_stand"), ("rs", "sdr_com_cover_right_stand"), ("cr", "sdr_com_cover_crouch")):
        for gait in ("jog", "run"):
            for foot in ("l", "r"):
                for n in ("1", "2", "3", "4", "6", "7", "8", "9", "8l", "8r"):
                    add(f"mwc_{t}_arr_{gait}_{foot}_{n}", f"{p}_{gait}_arrival_{foot}_{n}")
        for n in range(1, 10):
            add(f"mwc_{t}_exit_{n}", f"{p}_jog_exit_{n}")
    return out


FAMILIES["cover"] = cover_family()


# More cover (2026-11-18): stand cover over a chest-high wall, crouched corners, and pistol versions of every type.
#   st = sdr_com_cover_stand (hides crouched behind a chest-high wall, stands up to fire over it: hide_to_aim_high /
#        aim_high blend; turns +90 into the aim like cr). lc / rc = sdr_com_cover_left / right_crouch (crouched at a
#        tall wall's corner, leaning round it low; turns like ls / rs).
#   mwc_<t>p_<role>   the pistol set of type t (hide, twitches, look, lean, aim blend, arrivals, exits; blindfire, pains
#                     and grenades come from the rifle set). TIF's role() prefers it while a pistol is out.
def _glob_twitches(prefix):
    import glob as _g
    out = sorted(_os.path.basename(f)[:-7] for f in _g.glob(f"{_SRC}/{prefix}hide_twitch0[0-9].seanim"))
    return out[:2]


def cover2_family():
    out = []
    cov = dict(_COVER, loop=False)

    def add(role, clip, loop=False):
        if clip and _has(clip):
            out.append((role, clip, dict(_COVER, loop=loop)))

    def first(*names):
        for n in names:
            if _has(n):
                return n
        return None

    # (role suffix in the type's own naming) per type: lean_in, aim blend, lean_out, lean idle
    kinds = {
        "st": dict(p="sdr_com_cover_stand", lean_in="hide_to_aim_high", aim="aim_high_{}", lean_out="aim_high_to_hide", lean=None),
        "lc": dict(p="sdr_com_cover_left_crouch", lean_in="hide_to_lean", aim="lean_aim_{}", lean_out="lean_to_hide", lean="lean_idle"),
        "rc": dict(p="sdr_com_cover_right_crouch", lean_in="hide_to_lean", aim="lean_aim_{}", lean_out="lean_to_hide", lean="lean_idle"),
        # pistol-only sets for the existing types
        "ls": dict(p="sdr_com_cover_left_stand", lean_in="hide_to_lean", aim="lean_aim_{}", lean_out="lean_to_hide", lean="lean_idle"),
        "rs": dict(p="sdr_com_cover_right_stand", lean_in="hide_to_lean", aim="lean_aim_{}", lean_out="lean_to_hide", lean="lean_idle"),
        "cr": dict(p="sdr_com_cover_crouch", lean_in="hide_to_aim", aim="aim_aim_{}", lean_out="aim_to_hide", lean=None),
    }
    for t, k in kinds.items():
        new = t in ("st", "lc", "rc")
        for pistol in (False, True):
            if not new and not pistol:
                continue  # the rifle sets of ls / rs / cr are in cover_family
            p = k["p"] + ("_pstl" if pistol else "")
            r = f"mwc_{t}{'p' if pistol else ''}_"
            add(r + "hide", first(f"{p}_hide_idle"), True)
            tw = _glob_twitches(p + "_")
            for i, c in enumerate(tw, start=1):
                add(f"{r}twitch{i}", c)
            add(r + "look_in", first(f"{p}_hide_to_look"))
            add(r + "look", first(f"{p}_look_idle"), True)
            add(r + "look_out", first(f"{p}_look_to_hide"))
            add(r + "lean_in", first(f"{p}_{k['lean_in']}"))
            if k["lean"]:
                add(r + "lean", first(f"{p}_{k['lean']}"), True)
            if _has(f"{p}_{k['aim'].format(5)}"):
                out.append((r + "aim", None, dict(_COVER, loop=True, blend9=f"{p}_{k['aim']}", additive=True)))
            add(r + "lean_out", first(f"{p}_{k['lean_out']}"))
            for gait in ("jog", "run"):
                for foot in ("l", "r"):
                    for n in ("1", "2", "3", "4", "6", "7", "8", "9", "8l", "8r"):
                        add(f"{r}arr_{gait}_{foot}_{n}", first(f"{p}_{gait}_arrival_{foot}_{n}"))
            for n in range(1, 10):
                add(f"{r}exit_{n}", first(f"{p}_jog_exit_{n}"))
            if pistol:
                continue
            # rifle-only extras for the new types
            add(r + "reload", first(f"{p}_reload01", f"{p}_reload02"))
            add(r + "reload_pistol", first(f"{p}_reload01_pistol"))
            add(r + "flash", first(f"{p}_flash_react01"))
            add(r + "grenade", first(f"{p}_hide_grenade_frag01"))
            for region, srcs in (("head", ("head",)), ("torso", ("torso",)), ("legs", ("legs", "leg"))):
                for g in ("md", "lg"):
                    for d in ("f", "b", "l", "r"):
                        base = first(*[f"{p}_pain01_{s}_{g}_{d}" for s in srcs])
                        add(f"{r}pain_{region}_{g}_{d}", base)
                        add(f"{r}pain_{region}_{g}_{d}_hide", base and first(base + "_to_hide"))
            for g in ("md", "lg"):
                add(f"{r}pain_lean_{g}", first(f"{p}_pain01_lean_{g}_to_lean"))
    return out


FAMILIES["cover2"] = cover2_family()


# CQB cover (0.35.2): MW19's room-clearing arrivals into / exits out of every cover type from the gun-up CQB walk /
# fast (sdr_cqb_cover_*; the hide / lean / aim clips are the type's own). TIF uses them indoors and from the aimed
# walk (sv_cover_mw pick_arrival / pick_exit), rifle and pistol.
#   mwc_<t>[p]_arr_<cwalk|cfast>_<l|r>_<n>   arrival, lead foot, direction n (1-9, 8l / 8r)
#   mwc_<t>[p]_<cexit|cfexit>_<n>            exit into the CQB walk / fast, direction n
_CQB_COVER = {"ls": "left_stand", "rs": "right_stand", "cr": "crouch", "st": "stand", "lc": "left_crouch",
              "rc": "right_crouch"}


def cqb_cover_family():
    out = []
    for t, k in _CQB_COVER.items():
        for pistol in (False, True):
            p = f"sdr_cqb_cover_{k}" + ("_pstl" if pistol else "")
            r = f"mwc_{t}{'p' if pistol else ''}_"
            for gait, g in (("cwalk", "walk"), ("cfast", "fast")):
                for foot in ("l", "r"):
                    for n in ("1", "2", "3", "4", "6", "7", "8", "9", "8l", "8r"):
                        clip = f"{p}_{g}_arrival_{foot}_{n}"
                        if _has(clip):
                            out.append((f"{r}arr_{gait}_{foot}_{n}", clip, dict(_COVER)))
                for n in ("1", "2", "3", "4", "6", "7", "8", "9"):
                    clip = f"{p}_{g}_exit_{n}"
                    if _has(clip):
                        out.append((f"{r}{'cexit' if g == 'walk' else 'cfexit'}_{n}", clip, dict(_COVER)))
    return out


FAMILIES["cqb_cover"] = cqb_cover_family()


# Stage 5: MW19's stealth AI (reb_stl_*). These are AI-authored and already stand on their root, so they keep
# their own placement (start / loop / end of an activity join exactly).
#   mwa_idle / mwa_walk         alert posture (suspicious, searching): weapon half-raised
#   mwa_calm                    alert -> patrol (calming down)
#   mwr_<posture>_<move>_<grade>_<dir>   reactions: posture patrol|alert, move idle|walk,
#                                        grade sm|smed|lg|look (lookaround), dir 2 back 4 left 6 right 8 front
#   mwx_<activity>_<start|loop|end>      idle activities at a post: smoke, phone, water
#   mwi_<around|middle|radio|up>         investigation idles (looking around where something was heard)
#   mwk_body<1-4>                        checking a body
def passive_family():
    out = []
    keep = {"center": False}

    def add(role, clip, loop=False):
        if _has(clip):
            out.append((role, clip, dict(keep, loop=loop)))

    add("mwa_idle", "reb_stl_alert_idle01", True)
    add("mwa_walk", "reb_stl_alert_walk01", True)
    add("mwa_calm", "reb_stl_alert_to_patrol")
    for posture in ("patrol", "alert"):
        for move in ("idle", "walk"):
            for grade, src in (("sm", "sm"), ("smed", "smed"), ("lg", "lg"), ("look", "lookaround")):
                for d in (2, 4, 6, 8):
                    clip = f"reb_stl_{posture}_{move}_react_{src}_{d}"
                    if posture == "patrol" and move == "idle" and src == "smed" and not _has(clip):
                        clip = f"reb_stl_patrol_idle_react_md_{d}"
                    add(f"mwr_{posture}_{move}_{grade}_{d}", clip)
    for act, base in (("smoke", "reb_stl_idle_stand_smoking"), ("phone", "reb_stl_idle_stand_cellphone"),
                      ("water", "reb_stl_idle_stand_waterbottle")):
        add(f"mwx_{act}_start", f"{base}_start")
        add(f"mwx_{act}_loop", base, True)
        add(f"mwx_{act}_end", f"{base}_end")
    for k in ("around", "middle", "radio", "up"):
        add(f"mwi_{k}", f"reb_stl_alert_idle_investigation_{k}")
    for i in range(1, 5):
        add(f"mwk_body{i}", f"reb_stl_alert_walk_checkbody0{i}")
    return out


FAMILIES["passive"] = passive_family()


# Stage 7: hit reactions and situational deaths.
#   mwd_<situation>_<region>_<n>   deaths: situation stand | crouch | prone | run | explode | cover_ls | cover_rs |
#                                  cover_cr; region head | torso | legs (any = all regions)
#   mwh_<situation>_<region>_<n>   pains: stand | crouch | run | prone
# Each death carries cut (ragdoll handoff 0..1, mid-fall) and fall (direction the body goes); each pain push.
# TIF picks by situation, hit group and the direction the bullet pushes (tactics/sv_hits_mw.lua).
# K:\mw19deathanimations (a friend's ready-made ValveBiped deaths) join stand (Death_*) and run (DeathRunning_*).
import re as _re

_EXT = "K:/mw19deathanimations"
_REGION = {"head": "head", "midbody": "torso", "gut": "torso", "torso": "torso", "lowerbody": "legs",
           "lleg": "legs", "rleg": "legs", "legs": "legs", "larm": "torso", "rarm": "torso", "turn": "torso",
           "chest": "torso", "neck": "head"}
# (2026-11-18, user: variety. Deaths aren't capped any more (pains keep _CAP), the left / center / right fall and
# "_prone" (ends lying) variants join their pools, and the situational sets below were added. TIF picks them in
# sv_hits_mw.lua situation().)
_SIDE = r"(?:_(?:left|right|center|prone))?"
_DEATH = [
    ("stand", r"^sdr_com_(?:exposed|exp)_stand_death\d+_(head|midbody|lowerbody|gut|torso|lleg|rleg|chest|neck)_(?:sm|md|med|lg)_\d" + _SIDE + "$"),
    ("stand", r"^sdr_com_exposed_last_breath_r_death$"),
    ("crouch", r"^sdr_com_(?:exposed|exp)_crouch_death\d+_(head|midbody|lowerbody|gut|torso|lleg|rleg|chest)_(?:sm|md|med|lg)_\d" + _SIDE + "$"),
    ("prone", r"^sdr_com_exp_prone_death\d+_(head|torso)_med_\d" + _SIDE + "$"),
    # moving gun-up indoors (CQB walk / fast)
    ("cqbwalk", r"^sdr_cqb_walk_death\d+_(?:md|lg)_\d$"),
    ("cqbfast", r"^sdr_cqb_fast_death\d+_(?:md|lg)_\d$"),
    # blasts while lying / crouched
    ("explode_prone", r"^sdr_com_exposed_prone_death_explode_\d_\d+$"),
    ("explode_crouch", r"^sdr_com_exposed_crouch_death_explode_\d_\d+$"),
    # shot while leaning out over low cover
    ("cover_crexp", r"^sdr_com_cover_crouch_exp_death\d+_(head|torso|legs|midbody|lowerbody)_(?:md|lg)_\d$"),
    # killed mid-burst: the gun swings up firing
    ("fireair_stand", r"^sdr_com_exposed_stand_death\d+_firing_into_air$"),
    ("fireair_crouch", r"^sdr_com_exposed_crouch_death\d+_firing_into_air$"),
    # melee kills, falls
    ("melee", r"^sdr_com_exposed_stand_death\d+_melee_\d$"),
    ("ledge_norail_st", r"^sdr_com_(?:balcony_stand_norail_death\d+|exposed_stand_death\d+_fall)$"),
    ("ledge_norail_cr", r"^sdr_com_balcony_crouch_norail_death\d+$"),
    ("ledge_rail_st", r"^sdr_com_balcony_stand_rail_death\d+$"),
    ("ledge_rail_cr", r"^sdr_com_balcony_crouch_rail_death\d+$"),
    ("run", r"^sdr_com_run_death\d+_md_\d$"),
    ("explode", r"^sdr_com_exposed_stand_death_explode_\d_\d+$"),
    ("cover_ls", r"^sdr_com_cover_left_stand_death\d+_(head|torso|legs)_(?:md|lg)_\d$"),
    ("cover_rs", r"^sdr_com_cover_right_stand_death\d+_(head|torso|legs)_(?:md|lg)_\d$"),
    ("cover_cr", r"^sdr_com_cover_(?:left|right)_crouch_death\d+_(?:md|lg)_\d$"),
    # stand cover (chest-high wall; TIF type st)
    ("cover_st", r"^sdr_com_cover_stand_death\d+_(head|torso|legs)_(?:sm|md|lg)(?:_\d)?$"),
    # killed by fire (0.35.2): MW19's molotov reactions, staggering / crawling burning until he drops (3-10 s)
    ("burn", r"^sdr_com_molotov_reactions_(?:0\d|frantic_0\d[a-c]?|long_0\d[a-d]?|crawl_0[248]|crawl_fixed_06)$"),
    ("burn_crouch", r"^sdr_com_molotov_crouch_reaction\d+_\d$"),
    ("burn_prone", r"^sdr_com_molotov_prone_reaction\d+$"),
]
_PAIN = [
    ("stand", r"^sdr_com_exposed_stand_pain\d+_shrt_(torso|lleg|rleg)_(?:upper|lower)_md_\d$"),
    ("crouch", r"^sdr_com_exposed_crouch_pain\d+_shrt_(torso|lleg|rleg)_md_\d$"),
    ("run", r"^sdr_com_jog_pain_(?:md|shrt)_\d_\d+$"),
    ("prone", r"^sdr_com_exposed_prone_pain\d+$"),
    # (2026-11-18, tier 1: the full MW19 AI pain sets.) Stand / crouch by body part and side (f / b / l / r: where the
    # hit comes from); <sit>big = the long "fullpain" staggers (heavy hits); pstl with a pistol; CQB walk / fast while
    # moving gun-up indoors.
    ("stand", r"^sdr_com_exposed_stand_pain\d+_(head|torso|larm|rarm|lleg|rleg)_(?:md|lg)_[fblr]$"),
    ("crouch", r"^sdr_com_exposed_crouch_pain\d+_(head|torso|larm|rarm|lleg|rleg)_(?:md|lg)_[fblr]$"),
    ("standbig", r"^sdr_com_exposed_stand_fullpain\d+_(head|torso|larm|rarm|lleg|rleg|turn)_[a-z_]*[fblr]$"),
    ("crouchbig", r"^sdr_com_exposed_crouch_fullpain\d+_(head|torso|larm|rarm|lleg|rleg|turn)_[a-z_]*[fblr]$"),
    ("pstl", r"^sdr_com_exposed_stand_pstl_fullpain\d+_[a-z_]+$"),
    ("cqbwalk", r"^sdr_cqb_walk_pain_md_\d_\d+$"),
    ("cqbfast", r"^sdr_cqb_fast_pain_md_\d_\d+$"),
]
_CAP = 30  # pains per situation / region (deaths are uncapped); was 10


def hits_family():
    names = sorted(f[:-7] for f in _os.listdir(_SRC) if f.endswith(".seanim") and f.startswith(("sdr_com_", "sdr_cqb_")))
    out, counts = [], {}

    def add(prefix, sit, region, clip, opts, capped=True):
        k = (prefix, sit, region)
        counts[k] = counts.get(k, 0) + 1
        # (deaths uncapped since 2026-11-18: variety)
        if counts[k] <= _CAP or not capped or prefix == "mwd":
            out.append((f"{prefix}_{sit}_{region}_{counts[k]}", clip, opts))

    for prefix, table, kind in (("mwd", _DEATH, "death"), ("mwh", _PAIN, "pain")):
        for sit, rx in table:
            pat = _re.compile(rx)
            for n in names:
                mm = pat.match(n)
                if mm:
                    region = _REGION.get(mm.group(1), "any") if mm.groups() else "any"
                    opts = {"loop": False, "motion": kind}
                    # Prone: centred on the prone pelvis like mwp_idle (the clips start 26.6 units further forward;
                    # TIF used to teleport the body back as they started, which still showed as a jump. 2026-11-18)
                    if sit in ("prone", "burn_prone"):
                        opts["center"] = ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")
                    add(prefix, sit, region, n, opts)
    # Killed mid-activity (smoking / phone / water bottle) or mid-search-look (under / over / high / down): MW19 AI
    # deaths out of those exact poses, on the same root as the activity / look clips (no centring).
    acts = {"smoking": "smoke", "cellphone": "phone", "waterbottle": "water"}
    for f in sorted(_os.listdir(_SRC)):
        mm = _re.match(r"^reb_stl_idle_stand_(smoking|cellphone|waterbottle)_death\d+_\d+\.seanim$", f)
        if mm:
            add("mwd", "act_" + acts[mm.group(1)], "any", f[:-7], {"loop": False, "motion": "death", "center": False})
        mm = _re.match(r"^reb_smtobj_look_(under_low|under|over|high|down)_death\d+\.seanim$", f)
        if mm:
            add("mwd", "look_" + mm.group(1), "any", f[:-7], {"loop": False, "motion": "death", "center": False})
    for f in sorted(_os.listdir(_EXT)) if _os.path.isdir(_EXT) else []:
        if f.lower().endswith(".smd"):
            sit = "run" if f.lower().startswith("deathrunning") else "stand"
            region = "any" if sit == "run" else "torso"
            add("mwd", sit, region, "ext_" + f[:-4], {"loop": False, "motion": "death", "smd": f"{_EXT}/{f}"}, capped=False)
    return out


FAMILIES["hits"] = hits_family()


# Stage 8: CQB movement (room clearing), prone aim, cover grenade throws.
#   cqb_idle, cqb_walk_<dir>_loop, cqb_fast_<dir>_loop  compact gun-up room-clearing movement (8-way)
#   mwp_aim          prone aim, 3x3 blend from MW19's additive 5-point prone aim set
#   mwc_<t>_grenade  frag throw from cover (TIF.GrenadeMW)
def stage8_family():
    out = [("cqb_idle", "sdr_cqb_exp_interior_ready", {"loop": True})]
    out += strafe("cqb_walk_", "sdr_cqb_strafe_walk_{}")
    out += strafe("cqb_fast_", "sdr_cqb_strafe_fast_{}")
    out.append(("mwp_aim", None, {"loop": True, "blend9": "sdr_com_exposed_prone_aim_{}", "additive": True,
                                  "center": ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")}))
    for t, clip in (("ls", "sdr_com_cover_left_stand_hide_grenade_frag01"),
                    ("rs", "sdr_com_cover_right_stand_hide_grenade_frag"),
                    ("cr", "sdr_com_cover_crouch_rvar_grenade_throw01")):  # (rvar: see mwc_cr_blind1)
        if _has(clip):
            out.append((f"mwc_{t}_grenade", clip, {"loop": False, "center": False}))
    return out


FAMILIES["stage8"] = stage8_family()


# Pistols (MW19 body; TIF picks them when the soldier holds a pistol):
#   pstl_idle, pstl_walk_<dir>_loop, pstl_run_<dir>_loop   aimed, 8-way (CQB pistol strafes)
#   pstl_crouch_idle                                       crouched aim (crouch walking reuses the rifle set)
#   pstl_calm_idle / pstl_calm_walk / pstl_alert_idle      stealth patrol / alert with a pistol
#   pstl_jog / pstl_sprint                                 running with a pistol
#   mw_draw_pistol(_cr) / mw_draw_rifle(_cr)               rifle -> pistol and back, upper body (weapon switch)
def pistol_family():
    keep = {"center": False}
    out = [
        ("pstl_idle", "sdr_com_exposed_pstl_aim_5", {"loop": True}),
        ("pstl_crouch_idle", "sdr_com_exposed_crouch_pstl_aim_5", {"loop": True}),
        ("pstl_calm_idle", "reb_stl_patrol_pstl_idle01", dict(keep, loop=True)),
        ("pstl_calm_walk", "reb_stl_patrol_pstl_walk01", dict(keep, loop=True)),
        ("pstl_alert_idle", "reb_stl_alert_pstl_idle01", dict(keep, loop=True)),
        ("pstl_jog", "sdr_com_pstl_jog_loop01", {"loop": True}),
        ("pstl_sprint", "sdr_com_pstl_run_loop01", {"loop": True}),
        ("mw_draw_pistol", "sdr_com_exp_ar_to_pistol", {"loop": False, "ub": True}),
        ("mw_draw_rifle", "sdr_com_exp_pistol_to_ar", {"loop": False, "ub": True}),
        ("mw_draw_pistol_cr", "sdr_com_exp_crouch_ar_to_pistol", {"loop": False, "ub": True}),
        ("mw_draw_rifle_cr", "sdr_com_exp_crouch_pistol_to_ar", {"loop": False, "ub": True}),
    ]
    out += strafe("pstl_walk_", "sdr_cqb_pstl_strafe_walk_{}")
    out += strafe("pstl_run_", "sdr_cqb_pstl_strafe_fast_{}")
    return out


FAMILIES["pistol"] = pistol_family()


# Idle variants, so neighbours don't mirror each other: each soldier keeps one (TIF picks per soldier).
#   mwv_idle_<n>    calm patrol idles 2-6 (idle = 1)
#   mwv_alert_<n>   alert idles 2-5 (mwa_idle = 1)
def variant_family():
    keep = {"center": False, "loop": True}
    out = []
    for n in range(2, 7):
        if _has(f"reb_stl_patrol_idle0{n}"):
            out.append((f"mwv_idle_{n}", f"reb_stl_patrol_idle0{n}", dict(keep)))
    for n in range(2, 6):
        if _has(f"reb_stl_alert_idle0{n}"):
            out.append((f"mwv_alert_{n}", f"reb_stl_alert_idle0{n}", dict(keep)))
    return out


FAMILIES["variant"] = variant_family()


# Stage 5b: situational idles (MW19 smart objects). Each keeps its place relative to the object (no centring).
#   mws_wall_<l|r>_<enter|loop|exit|react_N>          shoulder against a wall (l: wall on the left)
#   mws_table_<l|c|r>_<30|36>_<enter|loop|exit|react_N> hand(s) on a surface 30 (table) / 36 (counter, railing) high
#   mws_sit_enter / mws_sit_exit                       sitting down / standing up (informant scene)
#   mws_sit_<gun|laptop|phone|sleep>_<loop|react>      seated activities; react = startled, stands up
#   mwd_sit_any_<n>                                    killed while seated (death pool "sit")
def smart_family():
    keep = {"center": False}
    out = []

    def add(role, clip, loop=False, extra=None):
        if _has(clip):
            o = dict(keep, loop=loop)
            o.update(extra or {})
            out.append((role, clip, o))

    for side in ("l", "r"):
        p = f"boss_smtobj_lean_wall_{side}"
        add(f"mws_wall_{side}_enter", f"{p}_enter")
        add(f"mws_wall_{side}_loop", f"{p}_loop", True)
        add(f"mws_wall_{side}_exit", f"{p}_exit")
        for d in (2, 4, 6, 8):
            add(f"mws_wall_{side}_react_{d}", f"{p}_react_{d}")
    for hand in ("l", "c", "r"):
        for h in (30, 36):
            p = f"boss_smtobj_lean_table_hand_{hand}_{h}"
            add(f"mws_table_{hand}_{h}_enter", f"{p}_enter")
            add(f"mws_table_{hand}_{h}_loop", f"{p}_loop", True)
            add(f"mws_table_{hand}_{h}_exit", f"{p}_exit")
            for d in (2, 4, 6, 8):
                add(f"mws_table_{hand}_{h}_react_{d}", f"{p}_react_{d}")
    add("mws_sit_enter", "cp_informant_checkin_stand_2_sit")
    add("mws_sit_exit", "cp_informant_checkin_sit_2_stand")
    for k, base in (("gun", "reb_stl_idle_sit_gunmaintenance"), ("laptop", "reb_stl_idle_sit_laptop"),
                    ("phone", "reb_stl_idle_sit_phone01"), ("sleep", "reb_stl_idle_sit_sleeping")):
        add(f"mws_sit_{k}_loop", base if _has(base) else f"{base}_idle", True)
        add(f"mws_sit_{k}_react", f"{base}_react")
    n = 0
    for f in sorted(_os.listdir(_SRC)):
        if f.startswith("reb_stl_idle_sit_") and "_death" in f and not f.endswith("_chair.seanim"):
            n += 1
            add(f"mwd_sit_any_{n}", f[:-7], False, {"motion": "death"})
    return out


FAMILIES["smart"] = smart_family()


# Stage 6: turns in place, starts, stops (cut foot sliding), and searching looks.
#   mwt_turn_<set>_<n>              turn in place; set calm | alert | stand | pstl | crouch. TIF picks by the
#                                   clip's measured yaw (numpad: 4/6 90, 7/9 45, 1/3 135, 2l/2r 180)
#   mwt_start_<set>_<n>             idle -> moving; set calm | alert (stealth walks, body turns to the path) or
#                                   walk | jog (strafe starts, body keeps facing); n = travel direction
#   mwt_stop_<set>_<foot>_<n>       moving -> idle, foot l/r planted; TIF picks by measured travel and yaw
#   mwl_<kind>_<enter|loop|exit>    search looks: under (table height), under_low (a car), over (a low wall),
#                                   high (up at a ledge / window), down (over a drop), around (no feature)
# Stealth (reb_stl_*) and smart-object clips stand on their own root (no centring); MP strafe starts / stops are
# centred like the strafe loops they join.
def trans_family():
    keep = {"center": False, "loop": False}
    mp = {"loop": False}
    out = []

    def add(role, clip, opts):
        if _has(clip):
            out.append((role, clip, dict(opts)))

    for st, p, nums in (("calm", "reb_stl_patrol_turn_", ("2l", "2r", "4", "6")),
                        ("alert", "reb_stl_alert_turn_", ("2l", "2r", "4", "6")),
                        ("stand", "sdr_com_exposed_stand_turn_", ("1", "2l", "2r", "3", "4", "6", "7", "9")),
                        ("pstl", "sdr_com_exposed_stand_pstl_turn_", ("1", "2l", "2r", "3", "4", "6", "7", "9")),
                        ("crouch", "sdr_com_exposed_crouch_turn_", ("2l", "2r", "4", "6"))):
        for n in nums:
            add(f"mwt_turn_{st}_{n}", p + n, keep)
    for n in (1, 2, 3, 4, 6, 7, 8, 9):
        add(f"mwt_start_calm_{n}", f"reb_stl_patrol_walk_exit_{n}", keep)
        add(f"mwt_start_alert_{n}", f"reb_stl_alert_walk_exit_{n}", keep)
        # (walk / jog strafe starts and stops: MW22 AI clips since 2026-11-17, in ai_move_family)
        for foot in ("l", "r"):
            add(f"mwt_stop_calm_{foot}_{n}", f"reb_stl_patrol_walk_arrival_{foot}_{n}", keep)
            add(f"mwt_stop_alert_{foot}_{n}", f"reb_stl_alert_walk_arrival_{foot}_{n}", keep)
    for kind, p in (("under", "reb_smtobj_look_under"), ("under_low", "reb_smtobj_look_under_low"),
                    ("over", "reb_smtobj_look_over"), ("high", "reb_smtobj_look_high"),
                    ("down", "reb_smtobj_look_down")):
        add(f"mwl_{kind}_enter", f"{p}_enter", keep)
        add(f"mwl_{kind}_loop", f"{p}_loop", dict(keep, loop=True))
        add(f"mwl_{kind}_exit", f"{p}_exit", keep)
    add("mwl_around_enter", "reb_smtobj_lookaround_enter", keep)
    add("mwl_around_loop", "reb_smtobj_lookaround01", dict(keep, loop=True))
    add("mwl_around_exit", "reb_smtobj_lookaround_exit", keep)
    return out


FAMILIES["trans"] = trans_family()


# Weapon classes (MW19 body). TIF sorts a gun by its GTG hold (TIF.GTG.WeaponKind): pistol | shotgun | rpg |
# lmg | rifle. Upper-body clips ("ub") layer over the legs; idles replace the rifle's aimed idle.
#   mw_reload_<kind>[_cr]         reloads, standing / crouched (mw_reload / mw_reload_cr: rifle)
#   <kind>_idle / <kind>_crouch_idle   aimed idles (LMG at the hip, RPG on the shoulder)
#   mwc_<t>_reload_<kind>         reloads in cover
def wclass_family():
    ub = {"loop": False, "ub": True}
    out = []

    def add(role, clip, opts):
        if _has(clip):
            out.append((role, clip, dict(opts)))

    add("mw_reload_cr", "sdr_com_exposed_crouch_reload01", ub)
    add("mw_reload_pistol_cr", "sdr_com_exp_crouch_reload01_pistol", ub)
    add("mw_reload_shotgun", "sdr_com_exp_reload01_shotgun", ub)
    add("mw_reload_shotgun_cr", "sdr_com_exp_crouch_reload01_shotgun", ub)
    add("mw_reload_rpg", "sdr_com_exposed_stand_rpg_reload", ub)
    add("mw_reload_rpg_cr", "sdr_com_exposed_crouch_rpg_reload", ub)
    add("mw_reload_lmg_cr", "sdr_com_exposed_crouch_lmg_reload01_fixed", ub)
    add("at4_drop", "sdr_com_exp_stand_rpg_drop_to_exp_stand", ub)
    add("at4_drop_cr", "sdr_com_exp_crouch_rpg_drop_to_exp_stand", ub)
    add("at4_drop_pstl", "sdr_com_exp_stand_rpg_drop_to_exp_stand_pstl", ub)
    # (Not built: MW19's shotgun / RPG fire clips are additive recoil layers (pelvis 34 back, feet in the air when
    # read as poses: arms thrown straight up in game), and the LMG "gun down" idle stands feet together with
    # straight legs. User clips 1, 3, 4, 5, 6, 2026-11-11.)
    add("lmg_idle", "sdr_com_exposed_lmg_aim_5", {"loop": True})
    # (2026-11-19, user: "whatever we should have for rpg idles isnt working": these were the aim set's centre pose,
    # 2 frames, frozen. Now MW19's AI RPG idles - additive breathing / shifting offsets - played on that pose.)
    add("rpg_idle", "sdr_com_exposed_stand_rpg_idle01", {"loop": True, "additive_on": "sdr_com_exposed_stand_rpg_aim_5"})
    add("rpg_crouch_idle", "sdr_com_exposed_crouch_rpg_idle01", {"loop": True, "additive_on": "sdr_com_exposed_crouch_rpg_aim_5"})
    cov = {"loop": False, "center": False}
    for t, p, pc in (("ls", "sdr_com_cover_left_stand", "sdr_com_cover_left"),
                     ("rs", "sdr_com_cover_right_stand", "sdr_com_cover_right_stand"),
                     ("cr", "sdr_com_cover_crouch", "sdr_com_cover_crouch")):
        add(f"mwc_{t}_reload_pistol", f"{pc}_reload01_pistol", cov)
        add(f"mwc_{t}_reload_shotgun", f"{pc}_reload01_shotgun", cov)
        add(f"mwc_{t}_reload_lmg", f"{p}_lmg_reload01", cov)
        add(f"mwc_{t}_reload_rpg", f"{p}_rpg_reload", cov)
    # SMG sprint (micro SMG and other SMGs), prone reloads (rifle, pistol), LMG bipods.
    #   smg_sprint                      SMG-held sprint
    #   mwp_reload / mwp_reload_pistol  reloading prone (full body, on the prone pelvis like the prone set)
    #   mwb_<set>_<in|aim|out>          LMG on its bipod: set stand (wall top), high (window / high ledge),
    #                                   crouch (low wall), prone; aim is a 3x3 blend from the 9-point aim set
    add("smg_sprint", "sdr_mp_strafe_sprint_smg_8", {"loop": True})
    prone = ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")
    add("mwp_reload", "sdr_com_exposed_prone_reload01", {"loop": False, "center": prone})
    add("mwp_reload_pistol", "sdr_com_exposed_prone_pstl_reload01", {"loop": False, "center": prone})
    for st, p in (("stand", "sdr_com_stand_lmg"), ("high", "sdr_com_stand_high_lmg"),
                  ("crouch", "sdr_com_crouch_lmg"), ("prone", "sdr_com_prone_lmg")):
        c = {"center": prone} if st == "prone" else {"center": False}
        add(f"mwb_{st}_in", f"{p}_setup_in", dict(c, loop=False))
        add(f"mwb_{st}_out", f"{p}_setup_out", dict(c, loop=False))
        if _has(f"{p}_aim_5"):
            out.append((f"mwb_{st}_aim", None, dict(c, loop=True, blend9=f"{p}_aim_{{}}", additive=True)))
    return out


FAMILIES["wclass"] = wclass_family()


# Stage 7 / 8 remainder: cover pains, last stand + revive, traversal, open-ground grenade throws.
#   mwc_<t>_pain_<region>_<md|lg>_<f|b|l|r>[_hide]   hit in cover: hidden (plain) / leaning out (_hide: flinch
#                                     back into hiding); region head | torso | legs; lean pains mwc_<t>_pain_lean_<md|lg>
#   mwls_fall_<torso|head>_<n>        shot into last stand (no gun)
#   mwls_idle, mwls_crawl_<dir>_loop  lying wounded, 8-way crawl;  mwls_turn_<l|r>
#   mwls_passout_<n>                  bleeding out (the end)
#   mwls_help_<in|loop|out>_<n>       reviving, kneeling on side n (numpad, around the wounded man)
#   mwls_hurt_<in|loop|out>_<n>       being revived from side n (the wounded's clips: 1/4/7 left, 3/6/9 right, 2, 8)
#   mwls_getup                        back on his feet (to crouch, gun up)
#   mwtr_<kind>                       traversal: mantle_<sm|md|lg> (up onto), drop_<sm|md|lg> (down off),
#                                     vault_<sm|md|lg> (over), step (over something low)
#   mwg_throw_<stand|crouch|prone>    frag throws in the open
def stage78_family():
    out = []

    def add(role, clip, opts):
        if _has(clip):
            out.append((role, clip, dict(opts)))

    cov = {"loop": False, "center": False}
    for t, p in (("ls", "sdr_com_cover_left_stand"), ("rs", "sdr_com_cover_right_stand"), ("cr", "sdr_com_cover_crouch")):
        for region, src in (("head", "head"), ("torso", "torso"), ("legs", "legs" if t == "cr" else "leg")):
            for g in ("md", "lg"):
                for d in ("f", "b", "l", "r"):
                    base = f"{p}_pain01_{src}_{g}_{d}"
                    if t != "cr" and region == "legs" and not _has(base):
                        base = f"{p}_pain01_legs_{g}_{d}"
                    add(f"mwc_{t}_pain_{region}_{g}_{d}", base, cov)
                    add(f"mwc_{t}_pain_{region}_{g}_{d}_hide", base + "_to_hide", cov)
        for g in ("md", "lg"):
            add(f"mwc_{t}_pain_lean_{g}", f"{p}_pain01_lean_{g}_to_lean", cov)
    keep = {"loop": False, "center": False}
    for i in range(1, 5):
        add(f"mwls_fall_torso_{i}", f"sdr_mp_laststand_torso_med_0{i}", keep)
    for i in range(1, 3):
        add(f"mwls_fall_head_{i}", f"sdr_mp_laststand_head_med_0{i}", keep)
        add(f"mwls_passout_{i}", f"sdr_mp_laststand_passout_0{i}", dict(keep, motion="death"))
    add("mwls_idle", "sdr_mp_laststand_gunless_idle01", dict(keep, loop=True))
    for n, d in DIRS.items():
        add(f"mwls_crawl_{d}_loop", f"sdr_mp_laststand_gunless_fast_{n}", {"loop": True})
    add("mwls_turn_l", "sdr_mp_laststand_gunless_turn_l", keep)
    add("mwls_turn_r", "sdr_mp_laststand_gunless_turn_r", keep)
    wounded = {1: "1_4_7", 4: "1_4_7", 7: "1_4_7", 3: "3_6_9", 6: "3_6_9", 9: "3_6_9", 2: "2", 8: "8"}
    for n in (1, 2, 3, 4, 6, 7, 8, 9):
        for ph in ("in", "loop", "out"):
            o = dict(keep, loop=(ph == "loop"))
            add(f"mwls_help_{ph}_{n}", f"sdr_mp_laststand_crouch_revive_{ph}_helper_{n}", o)
            add(f"mwls_hurt_{ph}_{n}", f"sdr_mp_laststand_crouch_revive_{ph}_wounded_{wounded[n]}", o)
    add("mwls_getup", "sdr_mp_laststand_revive_br_getup_crouch", keep)
    for g in ("sm", "md", "lg"):
        add(f"mwtr_mantle_{g}", f"bmr_com_traverse_jog_mantle_{g}", keep)
        add(f"mwtr_drop_{g}", f"bmr_com_traverse_jog_mantle_down_{g}", keep)
        add(f"mwtr_vault_{g}", f"bmr_com_traverse_jog_vault_over_{g}" + ("_fixed" if g == "sm" else ""), keep)
    add("mwtr_step", "bmr_com_traverse_jog_step_over", keep)
    add("mwg_throw_stand", "hm_grnd_red_exposed_grenade01_ar", keep)
    add("mwg_throw_crouch", "sdr_com_exposed_crouch_grenade_throw01", keep)
    add("mwg_throw_prone", "sdr_com_exposed_prone_grenade01",
        dict(keep, center=("pelvis", "sdr_com_exposed_stand_to_exposed_prone")))
    return out


FAMILIES["stage78"] = stage78_family()


# Civilians (TIF's shared tif_civilian on the MW19 host, Czech civilian models bonemerged):
#   civ_idle_<n>                calm idles (1 = plain, 2-6 = fidgets)
#   civ_walk / civ_jog / civ_run_<n>          calm locomotion
#   civ_pwalk_<n> / civ_pjog_<n> / civ_prun_<n>   panicked locomotion (each civilian keeps one variant)
#   civ_wounded_run             hurt, running
#   civ_cower_<n>               crouched, hiding in the open;  civ_wall_<l|r>_<n>  pressed against a wall
#   civ_kneel_<n>               hostage-style kneeling under fire (later: SWAT)
#   civ_beckon_<n> / civ_point_<n>   gestures (numpad: toward where)
#   civ_evade_<2|4|6|8>         stepping out of someone's way
def civ_family():
    out = []
    loop = {"loop": True}
    one = {"loop": False}

    def add(role, clip, opts):
        if _has(clip):
            out.append((role, clip, dict(opts)))

    add("civ_idle_1", "civ_casual_idle", loop)
    for i, k in enumerate("abcde", start=2):
        add(f"civ_idle_{i}", f"civ_casual_idle_twitch_{k}", one)
    add("civ_walk", "civ_casual_walk", loop)
    add("civ_jog", "civ_casual_jog", loop)
    add("civ_run_1", "civ_casual_run_a", loop)
    add("civ_run_2", "civ_casual_run_b", loop)
    n = 0
    for i in range(1, 7):
        # (05: an 11 in foot pop mid-stride, scratchpad loop_pops.py 2026-11-19)
        if i != 5 and _has(f"civ_pnc_walk_forward0{i}"):
            n += 1
            add(f"civ_pwalk_{n}", f"civ_pnc_walk_forward0{i}", loop)
    n = 0
    for i in range(1, 11):
        c = f"civ_pnc_jog_forward{i:02d}"
        if _has(c):
            n += 1
            add(f"civ_pjog_{n}", c, loop)
    n = 0
    for i in range(1, 12):
        c = f"civ_pnc_run_forward{i:02d}"
        if _has(c):
            n += 1
            add(f"civ_prun_{n}", c, loop)
    add("civ_wounded_run", "civ_run_upright_wounded", loop)
    keep = {"loop": True, "center": False}
    for i in range(1, 4):
        add(f"civ_cower_{i}", f"civ_stl_exposed_crouch_hide_idle0{i}", keep)
    for side, p in (("l", "civ_stl_cover_left_stand_hide_idle0"), ("r", "civ_stl_cover_right_stand_hide_idle0")):
        for i in range(1, 5):
            add(f"civ_wall_{side}_{i}", f"{p}{i}", keep)
    for i in range(0, 5):
        add(f"civ_kneel_{i + 1}", f"sa_vips_hostages_underfire_idle_hostage0{i}", keep)
    for d in (1, 2, 3, 4, 6, 7, 8, 9):
        add(f"civ_beckon_{d}", f"civ_ges_exposed_stand_beckon_{d}", one)
        add(f"civ_point_{d}", f"civ_ges_cover_left_stand_point_{d}", dict(one, center=False))
    for d in (2, 4, 6, 8):
        add(f"civ_evade_{d}", f"civ_casual_player_evasion_{d}", one)
    return out


FAMILIES["civ"] = civ_family()


# ---------------------------------------------------------------------------------------------------------------
# MW22 additions (2026-11-12). Clips MW19 doesn't have, from K:/mw22 anims (EXTRA_SOURCES). Only full-body clips
# with leg tracks are built as poses (scratchpad mw22_triage.py: the recovery lying idles / nulls have no legs, the
# slope / *_add / "fast" / strafe-lean / custom-pose clips are additive or upper-body only and are left out).
_SRC22 = ("K:/mw22 anims 2/xanims", "K:/mw22 anims")


def _has22(name):
    return _has(name) or any(_os.path.exists(f"{d}/{name}.seanim") for d in _SRC22)


def _adder(out):
    def add(role, clip, opts):
        if _has22(clip):
            out.append((role, clip, dict(opts)))
    return add


_N8 = ("1", "2", "3", "4", "6", "7", "8", "9")


# Cover (MW22): straight into the lean (gun up) from a jog, out of it, shuffling along the wall to the next node,
# pain shock (stunned by a heavy hit, then recovering), and busy idles (radio calls, swapping an armour plate).
#   mwc_<ls|rs>_arr_lean_<n> / mwc_<ls|rs>_exit_lean_<n>   jog arrival into / exit out of the lean, direction n
#   mwc_<t>_to_shuf_<l|r>, mwc_shuf_<l|r> (loop), mwc_shuf_<l|r>_to_<ls|rs|cr>   shuffle along the cover
#   mwc_<t>_shock / mwc_<t>_shock_rec                    pain shock and recovery
#   mwc_<t>_busy_<n>                                     radio / armour plate idles
def mw22_cover_family():
    out = []
    add = _adder(out)
    cov = {"loop": False, "center": False}
    for t, side in (("ls", "left"), ("rs", "right")):
        for n in _N8:
            add(f"mwc_{t}_arr_lean_{n}", f"sdr_cover_{side}_stand_lean_jog_arrival_r_{n}", cov)
            add(f"mwc_{t}_exit_lean_{n}", f"sdr_cover_{side}_stand_lean_jog_exit_{n}", cov)
    add("mwc_ls_to_shuf_r", "sdr_com_cover_left_stand_to_shuffle_right", cov)
    add("mwc_rs_to_shuf_l", "sdr_com_cover_right_stand_to_shuffle_left", cov)
    add("mwc_cr_to_shuf_l", "sdr_com_cover_crouch_to_shuffle_left", cov)
    add("mwc_cr_to_shuf_r", "sdr_com_cover_crouch_to_shuffle_right", cov)
    add("mwc_shuf_l", "sdr_com_cover_shuffle_left", dict(cov, loop=True))
    add("mwc_shuf_r", "sdr_com_cover_shuffle_right", dict(cov, loop=True))
    add("mwc_shuf_l_to_ls", "sdr_com_shuffle_left_to_cover_left_stand", cov)
    add("mwc_shuf_r_to_rs", "sdr_com_shuffle_right_to_cover_right_stand", cov)
    add("mwc_shuf_l_to_cr", "sdr_com_shuffle_left_to_cover_crouch", cov)
    add("mwc_shuf_r_to_cr", "sdr_com_shuffle_right_to_cover_crouch", cov)
    # (2026-11-18) stand cover and crouched corners join the shuffle: out of them, and into them at the end.
    add("mwc_st_to_shuf_l", "sdr_com_cover_stand_to_shuffle_left", cov)
    add("mwc_st_to_shuf_r", "sdr_com_cover_stand_to_shuffle_right", cov)
    add("mwc_lc_to_shuf_r", "sdr_com_cover_left_crouch_to_shuffle_right", cov)
    add("mwc_rc_to_shuf_l", "sdr_com_cover_right_crouch_to_shuffle_left", cov)
    add("mwc_shuf_l_to_st", "sdr_com_shuffle_left_to_cover_stand", cov)
    add("mwc_shuf_r_to_st", "sdr_com_shuffle_right_to_cover_stand", cov)
    add("mwc_shuf_l_to_lc", "sdr_com_shuffle_left_to_cover_left_crouch", cov)
    add("mwc_shuf_r_to_rc", "sdr_com_shuffle_right_to_cover_right_crouch", cov)
    for t, p in (("ls", "sdr_com_cover_left_stand"), ("rs", "sdr_com_cover_right_stand"), ("cr", "sdr_com_cover_crouch")):
        add(f"mwc_{t}_shock", f"{p}_pain_shock01", cov)
        add(f"mwc_{t}_shock_rec", f"{p}_pain_shock_recover", cov)
    busy = {"ls": ["sdr_com_cover_left_stand_communication01", "sdr_com_cover_left_stand_communication02",
                   "sdr_com_cover_left_equip_armor_plate01"],
            "rs": ["sdr_com_cover_right_stand_communication01", "sdr_com_cover_right_stand_communication02",
                   "sdr_com_cover_right_stand_communication03", "sdr_com_cover_right_stand_communication04",
                   "sdr_com_cover_right_equip_armor_plate01"],
            "cr": ["sdr_com_cover_crouch_left_communication01", "sdr_com_cover_crouch_left_communication02",
                   "sdr_com_cover_crouch_equip_armor_plate01"]}
    for t, lst in busy.items():
        for i, c in enumerate(lst, start=1):
            add(f"mwc_{t}_busy_{i}", c, cov)
    return out


# Room clearing (MW22): breaching a closed door, slicing an open doorway, entering.
#   mwq_br_<l|r>_1st_idle / _open / _kick    first man beside the door (l: door on his left): waiting, opening it
#                                            by the handle and going in, kicking it in
#   mwq_br_<l|r>_2nd_go                      second man going in after a handle opening
#   mwq_br_<l|r>_kick_idle / mwq_br_<l|r>_kick_2nd_go   kick stack: waiting beside the door, second man in
#   mwq_br_<l|r>_gren_idle / _gren_1st / _gren_2nd      grenade stack: waiting, first man throws in and enters, second in
#   mwq_br_<l|r>_nodoor_idle / _nodoor_1st / _nodoor_2nd  open doorway stack: waiting beside the frame, going in
#   mwq_cc_ready_<l|r>, mwq_cc_to_slice_<l|r>, mwq_cc_slice_<4|6>, mwq_cc_slice_fast_<4|6>,
#   mwq_cc_quick_<l|r>, mwq_cc_enter_<4|6>_<n>     corner check: ready, into the slice, slicing the doorway wide
#                                                  (4 left / 6 right), quick entry, walking in toward n
#   cqb_shuffle_<dir>_loop                          slow aimed shuffle (8-way) for working a room's corners
def mw22_cqb_family():
    out = []
    add = _adder(out)
    k = {"loop": False, "center": False}
    for s in ("l", "r"):
        add(f"mwq_br_{s}_1st_idle", f"sdr_breach_{s}_handle_1st_idle01", dict(k, loop=True))
        add(f"mwq_br_{s}_1st_open", f"sdr_breach_{s}_handle_1st_exit", k)
        add(f"mwq_br_{s}_1st_kick", f"sdr_breach_{s}_kick_1st_exit", k)
        add(f"mwq_br_{s}_2nd_go", f"sdr_breach_{s}_handle_2nd_exit", k)
        add(f"mwq_cc_ready_{s}", f"sdr_com_cornercheck_ready_{s}", k)
        add(f"mwq_cc_to_slice_{s}", f"sdr_com_cornercheck_ready_to_slice_{s}", k)
        add(f"mwq_cc_quick_{s}", f"sdr_com_cornercheck_slice_quick_enter_to_{s}", k)
        # (export 2 has the kick stack per side: waiting beside the door, second man in after the kick)
        add(f"mwq_br_{s}_kick_idle", f"sdr_breach_{s}_kick_idle01", dict(k, loop=True))
        add(f"mwq_br_{s}_kick_2nd_go", f"sdr_breach_{s}_kick_2nd_exit", k)
        # (0.38.17 variety) grenade stack: first man throws through the door, both go in after the bang; open
        # doorway stack (no door): both wait beside the frame and go in together
        add(f"mwq_br_{s}_gren_idle", f"sdr_breach_{s}_grenade_idle01", dict(k, loop=True))
        add(f"mwq_br_{s}_gren_1st", f"sdr_breach_{s}_grenade_1st_exit", k)
        add(f"mwq_br_{s}_gren_2nd", f"sdr_breach_{s}_grenade_2nd_exit", k)
        add(f"mwq_br_{s}_nodoor_idle", f"sdr_breach_nodoor_{s}_idle01", dict(k, loop=True))
        add(f"mwq_br_{s}_nodoor_1st", f"sdr_breach_nodoor_{s}_1st_exit", k)
        add(f"mwq_br_{s}_nodoor_2nd", f"sdr_breach_nodoor_{s}_2nd_exit", k)
    # (0.38.19) MW19's sledgehammer breach (Clean House infil): one swing at the door (sledge_vs_door), sledge stowed
    # (stow_sledge), hands back on the slung gun. The sledge is a prop on the right hand (tif_mw/props/sledgehammer,
    # cl_props); one version, the side picked by its turn like the others.
    # (cut at f90: the gun is back in the right hand there; f90-97 is a scripted 290-unit catch-up slide)
    add("mwq_br_sledge", "zd30c_000_infil_lbirds_sledge_ally13", dict(k, end=90))
    for d in ("4", "6"):
        add(f"mwq_cc_slice_{d}", f"sdr_com_cornercheck_slice_wide_{d}", k)
        add(f"mwq_cc_slice_fast_{d}", f"sdr_com_cornercheck_slice_wide_fast_{d}", k)
        for n in _N8:
            add(f"mwq_cc_enter_{d}_{n}", f"sdr_com_cornercheck_quick_enter_{d}_walk_exit_{n}", k)
    out += strafe("cqb_shuffle_", "sdr_cqb_strafe_shuffle_{}")
    return out


# Reactions (MW22): dodging a grenade, flinching while running, a new enemy close by, pain shock, hit unaware.
#   mwe_dive_8 / mwe_dive_up_8, mwe_jump_<2|4|6|8>, mwe_dodge_<4|6>   away from a grenade / something coming at him
#   mwh_flinch_<jog|run|sprint>_<1|2>                                  hit on the move, keeps going
#   mwe_newenemy_<n>      surprised by an enemy close by, direction n
#   mwe_shock_<stand|crouch> / mwe_shock_<..>_rec                        stunned by a heavy hit, recovering
#   mwe_assess_<2|4|6|8>  hit while unaware: looks toward where it came from
def mw22_react_family():
    out = []
    add = _adder(out)
    one = {"loop": False}
    add("mwe_dive_8", "sdr_com_exposed_avoid_dive_8", one)
    add("mwe_dive_up_8", "sdr_com_exposed_avoid_dive_to_exp_8", one)
    for d in ("2", "4", "6", "8"):
        add(f"mwe_jump_{d}", f"sdr_com_exposed_avoid_jump_{d}", one)
        add(f"mwe_assess_{d}", f"sdr_com_exposed_unaware_pain_assess01_{d}", one)
    for d in ("4", "6"):
        add(f"mwe_dodge_{d}", f"sdr_com_exposed_stand_dodge_{d}", one)
    for g in ("jog", "run", "sprint"):
        for i in (1, 2):
            add(f"mwh_flinch_{g}_{i}", f"sdr_com_{g}_flinch0{i}", one)
    for n in ("1", "2l", "2r", "3", "4", "6", "7", "8", "9"):
        add(f"mwe_newenemy_{n}", f"sdr_com_exp_stand_react_newenemy_close01_{n}", one)
    for st in ("stand", "crouch"):
        add(f"mwe_shock_{st}", f"sdr_com_exposed_{st}_pain_shock01", one)
        add(f"mwe_shock_{st}_rec", f"sdr_com_exposed_{st}_pain_shock_recover", one)
    return out


# Knockdowns (MW22): blown off his feet by a nearby blast, then getting up.
#   mwk_fall_<2|4|6|8>               knocked down (pushed toward n), ends lying
#   mwk_up_<back|stomach|left|right>_<n>   getting up from lying on his back / stomach / side, facing n
def mw22_down_family():
    out = []
    add = _adder(out)
    k = {"loop": False, "center": False}
    for d in ("2", "4", "6", "8"):
        add(f"mwk_fall_{d}", f"sdr_raginit_stand_hit_{d}_midbody_to_ragidle", k)
    for pose, src in (("back", "back"), ("stomach", "stomach"), ("left", "leftside"), ("right", "rightside")):
        for n in _N8:
            add(f"mwk_up_{pose}_{n}", f"sdr_com_recovery_{src}_{n}", k)
    return out


# Buddy revive (MW22): a paired revive by how the wounded man lies.
#   mwbr_<pose>_<hurt|help>_<in|mid|out>_<4|6>   pose back | stomach | right | laststand; 4 / 6: helper's side
def mw22_buddy_family():
    out = []
    add = _adder(out)
    k = {"loop": False, "center": False}
    for pose in ("back", "stomach", "right", "laststand"):
        for d in ("4", "6"):
            p = f"sdr_com_buddy_revive_{pose}_to_exposed"
            add(f"mwbr_{pose}_hurt_in_{d}", f"{p}_intro_{d}", k)
            add(f"mwbr_{pose}_hurt_mid_{d}", f"{p}_{d}", k)
            add(f"mwbr_{pose}_hurt_out_{d}", f"{p}_exit_{d}", k)
            add(f"mwbr_{pose}_help_in_{d}", f"{p}_helper_intro_{d}", k)
            add(f"mwbr_{pose}_help_mid_{d}", f"{p}_helper_{d}", k)
            add(f"mwbr_{pose}_help_out_{d}", f"{p}_helper_exit_{d}", k)
    return out


# Calm life (MW22): idle activities at a post, curious / threat reactions, investigation looks, walk variants,
# hand signals.
#   mwx_<activity>_<start|loop|end>   hum1-2, radio1-4, look1-3 (into the distance), scratch1-8, stretch1-4
#   mwr2_<patrol|alert>_<idle|walk>_<cur|threat>_<2l|2r|4|6|8>   curious (heard something) / threat (saw one)
#   mwi_area<1-4>, mwi_threat<1-3>    investigating: area checks, looking around for a threat
#   mwv_walk_<2-4>, mwv_awalk_<2-5>   calm / alert walk variants (each soldier keeps one)
#   mwgs_come_<stand|crouch>_<n>, mwgs_stop   "on me" / "hold" signals
def mw22_idle_family():
    out = []
    add = _adder(out)
    keep = {"center": False, "loop": False}
    acts = [("hum", "humming", 2), ("radio", "radio", 4), ("look", "distance_look", 3), ("scratch", "scratching", 8),
            ("stretch", "stretching", 4)]
    for key, src, count in acts:
        for i in range(1, count + 1):
            p = f"sdr_stl_patrol_stand_{src}0{i}"
            loop = f"{p}_ilde" if _has22(f"{p}_ilde") and not _has22(f"{p}_idle") else f"{p}_idle"
            add(f"mwx_{key}{i}_start", f"{p}_start", keep)
            add(f"mwx_{key}{i}_loop", loop, dict(keep, loop=True))
            add(f"mwx_{key}{i}_end", f"{p}_end", keep)
    for n in ("2l", "2r", "4", "6", "8"):
        add(f"mwr2_patrol_idle_cur_{n}", f"sdr_patrol_idle_react_curious01_{n}", keep)
        add(f"mwr2_alert_idle_cur_{n}", f"sdr_alert_idle_react_curious01_{n}", keep)
        add(f"mwr2_alert_walk_cur_{n}", f"sdr_alert_walk_react_curious01_{n}", keep)
        add(f"mwr2_patrol_idle_threat_{n}", f"sdr_stl_patrol_idle_react_threat01_{n}", keep)
        add(f"mwr2_patrol_walk_threat_{n}", f"sdr_stl_patrol_walk_react_threat01_{n}", keep)
    for i in range(1, 5):
        add(f"mwi_area{i}", f"sdr_react_curious_areacheck0{i}", keep)
    for i in range(1, 4):
        add(f"mwi_threat{i}", f"sdr_stl_react_threat_lookaround0{i}", keep)
    for i in (2, 3, 4):
        add(f"mwv_walk_{i}", f"reb_stl_patrol_walk0{i}", dict(keep, loop=True))
    for i in (2, 3, 4, 5):
        add(f"mwv_awalk_{i}", f"reb_stl_alert_walk0{i}", dict(keep, loop=True))
    for st in ("stand", "crouch"):
        for n in ("2l", "2r", "4", "6", "8"):
            add(f"mwgs_come_{st}_{n}", f"sdr_ges_exposed_{st}_come01_{n}", {"loop": False})
    add("mwgs_stop", "sdr_ges_exposed_idle_stop01", {"loop": False})
    return out


# Movement extras: prone crawl starts / stops (on the prone pelvis like the crawl loops), big drops.
#   mwp_cstart_<dir>, mwp_cstop_<l|r>   into / out of the prone crawl
#   mwtr_drop_xl<1-3>                    running drop off a high ledge
def mw22_move_family():
    out = []
    add = _adder(out)
    prone = ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")
    for n, d in DIRS.items():
        add(f"mwp_cstart_{d}", f"sdr_mp_prone_strafe_fast_start_{n}", {"loop": False, "center": prone})
    for s in ("l", "r"):
        add(f"mwp_cstop_{s}", f"sdr_mp_prone_strafe_stop_{s}", {"loop": False, "center": prone})
    for i in (1, 2, 3):
        add(f"mwtr_drop_xl{i}", f"sdr_com_traverse_run_mantle_down0{i}_xlg", {"loop": False, "center": False})
    return out


# Helicopter passengers (TIF air, HELI_PLAN.md). Placed on the helicopter's own tags, so nothing is centred.
#   mwhb_land_<l|r><1-3>_idle / _exit   Black Hawk, landed: riding, then out through the cabin door (MW19 AI)
#   mwhb_rap_<n>_idle / _drop           Black Hawk, ~20 m hover: riding on tag_guy<n>, then down the rope
# Seat tags, start offsets, hover heights and hand-back points: K:/jimmyproject/tif_air/heli_infil_data.py.
def heli_family():
    out = []
    add = _adder(out)
    k = {"loop": False, "center": False}
    for s in ("l", "r"):
        for n in (1, 2, 3):
            add(f"mwhb_land_{s}{n}_idle", f"sdr_mp_veh_blima_ground_{s}{n}_idle", dict(k, loop=True))
            add(f"mwhb_land_{s}{n}_exit", f"sdr_mp_veh_blima_ground_{s}{n}_exit", k)
    for n in (0, 1, 2, 3, 4, 6, 8, 9):
        add(f"mwhb_rap_{n}_idle", f"vh_blima_rappel_soldier{n}_idle", dict(k, loop=True))
        add(f"mwhb_rap_{n}_drop", f"vh_blima_rappel_soldier{n}_drop", k)
    # Black Hawk MP intro fast-rope (MW19 mp_infil_blima_[r_]guy01-03; two 3-man teams, left / right rope), the
    # cabin lead-in cut (left 6 s, right 5 s): seat = the held first frame after the cut, exit = the clip from there.
    #   mwhb_mpl_<1-3>_idle / _exit, mwhb_mpr_<1-3>_idle / _exit
    for team, pre, cut in (("mpl", "", 180), ("mpr", "r_", 150)):
        for n in (1, 2, 3):
            clip = f"mp_infil_blima_{pre}guy0{n}"
            add(f"mwhb_{team}_{n}_idle", clip, dict(k, loop=True, hold=cut))
            add(f"mwhb_{team}_{n}_exit", clip, dict(k, trim=cut))
    # Black Hawk campaign fast-rope (~575 hover): mwhb_fr_<0|01..05>_idle / _exit
    for g in ("0", "01", "02", "03", "04", "05"):
        add(f"mwhb_fr_{g}_idle", f"reb_com_vh_blima_guy{g}_idle", dict(k, loop=True))
        add(f"mwhb_fr_{g}_exit", f"reb_com_vh_blima_guy{g}_exit", k)
    # Little Bird: MP ground exits off the benches; campaign bench hop-offs in three styles
    #   mwlb_land_<l|r><1-3>_idle / _exit, mwlb_bench_<1-6>_idle / _run / _ready / _patrol
    for s in ("l", "r"):
        for n in (1, 2, 3):
            add(f"mwlb_land_{s}{n}_idle", f"sdr_mp_veh_lbravo_ground_{s}{n}_idle", dict(k, loop=True))
            add(f"mwlb_land_{s}{n}_exit", f"sdr_mp_veh_lbravo_ground_{s}{n}_exit", k)
    for g in range(1, 7):
        add(f"mwlb_bench_{g}_idle", f"reb_vh_lbravo_guy{g}_idle_search01", dict(k, loop=True))
        add(f"mwlb_bench_{g}_run", f"reb_vh_lbravo_guy{g}_exit_combat_run", k)
        add(f"mwlb_bench_{g}_ready", f"reb_vh_lbravo_guy{g}_exit_combat_idle", k)
        add(f"mwlb_bench_{g}_patrol", f"reb_vh_lbravo_guy{g}_exit_patrol", k)
    # Mi-8: landed (front doors / open back, + juggernaut), fast-rope from four ropes
    #   mwmi_land_<fl|fr|rl|rr><1-3>_idle / _exit, mwmi_land_jug_idle / _exit, mwmi_rope_<..><1-3>_idle / _exit
    side = {"fl": "front_l", "fr": "front_r", "rl": "rear_l", "rr": "rear_r"}
    for s in ("fl", "fr", "rl", "rr"):
        for n in (1, 2, 3):
            add(f"mwmi_land_{s}{n}_idle", f"sdr_mp_veh_mindia8_ground_{s}{n}_idle", dict(k, loop=True))
            add(f"mwmi_land_{s}{n}_exit", f"sdr_mp_veh_mindia8_ground_{s}{n}_exit", k)
            add(f"mwmi_rope_{s}{n}_idle", f"vh_mindia8_{side[s]}_{n}_idle", dict(k, loop=True))
            add(f"mwmi_rope_{s}{n}_exit", f"vh_mindia8_{side[s]}_{n}_exit", k)
    add("mwmi_land_jug_idle", "sdr_mp_veh_mindia8_ground_jug_idle", dict(k, loop=True))
    add("mwmi_land_jug_exit", "sdr_mp_veh_mindia8_ground_jug_exit", k)
    # Crew (client-side dummies on the helicopter: pilots, Black Hawk crew chiefs)
    loop = dict(k, loop=True)
    for role, clip in (("mwhb_pilot", "vh_blima_rappel_pilot"), ("mwhb_copilot", "vh_blima_rappel_copilot"),
                       ("mwhb_chief", "reb_com_vh_blima_chief_idle"), ("mwhb_chief2", "reb_com_vh_blima_chief2_idle"),
                       ("mwlb_pilot", "reb_vh_lbravo_pilot_idle_search01"), ("mwlb_copilot", "reb_vh_lbravo_copilot_idle_search01"),
                       ("mwmi_pilot", "vh_mindia8_pilot_idle"), ("mwmi_copilot", "vh_mindia8_copilot_idle"),
                       ("mwhv_pilot", "reb_vh_palfa_driver_idle_search01"), ("mwhv_copilot", "reb_vh_palfa_pass_idle_search01")):
        add(role, clip, loop)
    return out


FAMILIES["heli"] = heli_family()


# MW cars (tif_mw_cars, VEHICLE_PLAN.md stage 2). Seat idles, entries and exits on each car's seat tags, so nothing is
# centred; bed seats with no idle clip hold the entry's last frame. Roles and clips come from
# K:/jimmyproject/tif_air/car_seat_data.py (SEATS), which also writes the matching seat data for the cars:
#   mwrp_s<0-6>_idle / _entry / _exit_<run|idle|combat>[_<l|r>]   RAM 1500 (MWII pickup_fullsize_2014)
#   mwra_s<0-6>_...                                               RAM 1500 armoured (MWII techoarmor)
def car_family():
    import sys as _sys
    _sys.path.insert(0, "K:/jimmyproject/tif_air")
    import car_seat_data as _csd
    out = []
    for car in _csd.SEATS:
        out += _csd.car_seat_roles(car)
    return out


FAMILIES["car"] = car_family()
FAMILIES["mw22cover"] = mw22_cover_family()
FAMILIES["mw22cqb"] = mw22_cqb_family()
FAMILIES["mw22react"] = mw22_react_family()
FAMILIES["mw22down"] = mw22_down_family()
FAMILIES["mw22buddy"] = mw22_buddy_family()
FAMILIES["mw22idle"] = mw22_idle_family()
FAMILIES["mw22move"] = mw22_move_family()


# AI movement, turns, cover entries and long deaths (2026-11-17; user: "solidly AI animations", MW19 SP as
# variety; nothing MP here). TIF: sv_trans_mw (starts / stops / reversals / turns), sv_cover_mw (xin),
# sv_hits_mw (long deaths).
#   mwt_start_<walk|jog>_<n>          MW22 AI strafe starts (sdr_com_strafe_<walk|jog>_start_n)
#   mwt_stop_<walk|jog>_<l|r>_<n>     AI strafe stops: walk from the AI slow-walk stops (the walk has only
#                                     in-place "zero" stops), jog from the AI jog stops
#   mwt_rev_<set>_<a>_<b>             strafe reversal (AI CQB set, the only AI one): moving in numpad direction a with
#                                     the body keeping its facing, plant, off in b. set walk / cqbwalk (trans walk),
#                                     jog / cqbfast (trans fast). TIF hands back to the strafe at code_move.
#   mwt_turn_crouch_<n>v              MW22 AI crouched turns in place (diagonals too, 0.67-1.33 s)
#   mwt_turn_alert_<n>v               MW22 AI alert idle turns (variety beside MW19's alert set)
#   mwc_<cr|ls|rs>_xin_<st|cr>_<k>    into cover from standing / crouched right beside it (no travel: the clip turns
#                                     him into the hide pose; k numbers the variants, TIF picks by the turn)
#   mwld_<st|cr>_<kind>_<enter|loop|death>   long deaths (MW19 SP): falls wounded, crawls a while (kind back | belly
#                                     | l | r) or sits / kneels (b | l2 | r2 | knees, standing only), then dies.
def ai_move_family():
    out = []
    add = _adder(out)
    keep = {"center": False, "loop": False}
    mv = {"loop": False}
    mva = dict(mv, **AI_ARMS)  # (the strafes' starts / stops: same placeholder arms)
    for n in _N8:
        add(f"mwt_start_walk_{n}", f"sdr_com_strafe_walk_start_{n}", mva)
        add(f"mwt_start_jog_{n}", f"sdr_com_strafe_jog_start_{n}", mva)
        for foot in ("l", "r"):
            add(f"mwt_stop_walk_{foot}_{n}", f"sdr_com_strafe_slwalk_stop_{foot}_{n}", mva)
            add(f"mwt_stop_jog_{foot}_{n}", f"sdr_com_strafe_jog_stop_{foot}_{n}", mva)
    pairs = (("1", "9"), ("2", "8"), ("3", "7"), ("4", "6"), ("6", "4"), ("7", "3"), ("8", "2"), ("9", "1"))
    for a, b in pairs:
        for st, src in (("walk", "walk"), ("cqbwalk", "walk"), ("jog", "fast"), ("cqbfast", "fast")):
            add(f"mwt_rev_{st}_{a}_{b}", f"sdr_cqb_strafe_trans_{src}{a}_{src}{b}", mv)
    for n in ("1", "2l", "2r", "3", "4", "6", "7", "9"):
        add(f"mwt_turn_crouch_{n}v", f"sdr_com_exposed_crouch_inplace_turn01_{n}", dict(keep, **AI_ARMS_CROUCH))
    for n in ("2l", "2r", "4", "6"):
        add(f"mwt_turn_alert_{n}v", f"sdr_alert_idle_turn01_{n}", keep)
    # Flashlight sets (MW19 stealth AI with a light; TIF swaps them in while NW2 tif_light is on):
    #   mwf_calm_idle[_n] / mwf_calm_walk[_n]     calm patrol, the light on the gun (left hand on the gun)
    #   mwf_alert_idle[_n] / mwf_alert_walk[_n]   alert, a handheld light in the left hand (tag_accessory_left)
    #   mwt_turn_<calmf|alertf>_<n>, mwt_start_<calmf|alertf>_<n>, mwt_stop_<calmf|alertf>_<l|r>_<n>
    loopk = {"center": False, "loop": True}
    for st, p in (("calm", "reb_stl_patrol_flash"), ("alert", "reb_stl_alert_flash")):
        add(f"mwf_{st}_idle", f"{p}_idle01", loopk)
        for i in (2, 3, 4):
            add(f"mwf_{st}_idle_{i}", f"{p}_idle0{i}", loopk)
        add(f"mwf_{st}_walk", f"{p}_walk01", loopk)
        for i in (2, 3):
            add(f"mwf_{st}_walk_{i}", f"{p}_walk0{i}", loopk)
        for n in ("2l", "2r", "4", "6"):
            add(f"mwt_turn_{st}f_{n}", f"{p}_turn_{n}", keep)
        for n in ("1", "2", "3", "4", "6", "7", "8", "9"):
            add(f"mwt_start_{st}f_{n}", f"{p}_walk_exit_{n}", keep)
            for foot in ("l", "r"):
                add(f"mwt_stop_{st}f_{foot}_{n}", f"{p}_walk_arrival_{foot}_{n}", keep)
    # Stairs and slopes (MW19 AI; cl_body picks by how steeply he climbs / descends, moving forward):
    #   mwst_<calm|calmf|alert|alertf|aim|fast|run>_<up|down>   stairs (calm / alert stealth, f = flashlight, aim / fast
    #                                                            = CQB walk / fast, run)
    #   mwsl_<slwalk|walk|jog|run|sprint>_<up|down>             slopes (incline / decline)
    lp = {"loop": True}
    for st, p in (("calm", "reb_stl_patrol_stairs_forward"), ("calmf", "reb_stl_patrol_stairs_forward_flashlight"),
                  ("alert", "reb_stl_alert_stairs_forward"), ("alertf", "reb_stl_alert_stairs_forward_flashlight"),
                  ("aim", "sdr_cqb_stairs_walk_forward"), ("fast", "sdr_cqb_stairs_fast_forward"),
                  ("run", "sdr_com_stairs_run_forward")):
        for ud in ("up", "down"):
            add(f"mwst_{st}_{ud}", f"{p}_{ud}", lp)
    for g in ("slwalk", "walk", "jog", "run", "sprint"):
        add(f"mwsl_{g}_up", f"sdr_com_slope_{g}_incline_8", lp)
        add(f"mwsl_{g}_down", f"sdr_com_slope_{g}_decline_8", lp)
    # Reactions (MW19 AI): mwz_whizby_<i> rounds snapping past (in place, ~0.9 s); mwz_vdodge[_short]_<2|4|6|8> out of
    # a vehicle's way; mwz_fire_<i> / mwz_fire_cr_<i> on fire standing / crouched (incendiary, burning).
    # (0.38.6) The whizby clips are ADDITIVE data: baked as poses they drew the soldier as a rigid stick figure for ~1 s
    # (user's "crumple"). Now built as delta layers like the recoil kicks (mwzw_<i>: the whole flinch, eased back over
    # 4 frames; tif_mw_build shot_slice + QC delta), played on top of whatever he's doing (cl_body). mwz_whizby_* gone.
    import cod_anim_prep as _cap
    for i in range(1, 8):
        clip = f"sdr_cqb_strafe_whizby_0{i}"
        if _has(clip):
            fr = _cap.read_seanim(f"{_SRC}/{clip}.seanim")["frames"]
            add(f"mwzw_{i}", clip, {"shot": (0, fr - 1, 4), "loop": False})
    for n in ("2", "4", "6", "8"):
        add(f"mwz_vdodge_{n}", f"sdr_com_exposed_stand_vehicle_dodge01_{n}", keep)
        add(f"mwz_vdodge_short_{n}", f"sdr_com_exposed_stand_vehicle_dodge_short01_{n}", keep)
    # (0.35.2: every molotov reaction except the four "sling" ones ends lying on the ground: they're burn-to-death
    # sequences, now deaths (_DEATH burn / burn_crouch / burn_prone). The on-fire reaction a man survives is patting the
    # flames off an arm / leg (stays standing); lying down, rolling on the ground (prone reactions, stay prone).)
    fire = [f"sdr_com_molotov_reactions_{s}_sling" for s in ("left_arm", "right_arm", "left_leg", "right_leg")]
    for i, src in enumerate(fire, start=1):
        add(f"mwz_fire_{i}", src, keep)
    for i in range(1, 5):
        add(f"mwz_fire_pr_{i}", f"sdr_com_molotov_prone_reaction0{i}",
            {"loop": False, "center": ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")})
    # Pointing out a distant contact / looking around after losing it (MW19 AI; TIF sv_passive_mw OnAware):
    #   mwe_point[2]_<n>, mwe_look[2]_<n>   n = numpad direction the clip turns toward (behind = 2)
    for n in ("1", "2", "3", "4", "6", "7", "8", "9"):
        add(f"mwe_point_{n}", f"sdr_com_exposed_reaction_point01_{n}", keep)
        add(f"mwe_point2_{n}", f"sdr_com_exposed_reaction_point02_{n}", keep)
        add(f"mwe_look_{n}", f"sdr_com_exposed_reaction_lookaround01_{n}", keep)
        add(f"mwe_look2_{n}", f"sdr_com_exposed_reaction_lookaround02_{n}", keep)
    # Doors (MW19 AI door interactions; TIF sv_door_mw): mwdr_<l|r>_<tac|shoulder|kick>_<a|b|c> opening a closed door on
    # the way through (tac from a walk, shoulder / kick on the run), mwdr_<l|r>_flash a flashbang through the door.
    for s in ("l", "r"):
        for v in ("a", "b", "c"):
            add(f"mwdr_{s}_tac_{v}", f"sdr_com_inter_{s}door_tac_ex_cqb_{v}", keep)
            add(f"mwdr_{s}_shoulder_{v}", f"sdr_com_inter_{s}door_shoulder_ex_run_{v}", keep)
            add(f"mwdr_{s}_kick_{v}", f"sdr_com_inter_{s}door_kick_ex_run_{v}", keep)
        add(f"mwdr_{s}_flash", f"sdr_com_inter_{s}door_flash_a", keep)
    # Run and gun (MW19 AI): the covering burst on the dash to cover keeps running, gun out to the side of the run.
    #   mwrg_<f|l|r|bl|br>   aiming ahead / left / right / back-left / back-right of the run (gun bone animated)
    for v, suf in (("f", ""), ("l", "_l"), ("r", "_r"), ("bl", "_bl"), ("br", "_br")):
        add(f"mwrg_{v}", f"sdr_com_rungun_run_forward{suf}", {"loop": True})
    # Traversals at the soldier's pace (MW19 AI walk / fast sets beside the jog set mwtr_<kind>_<size>):
    #   mwtr_<mantle|drop|vault>_<sm|md|lg>_<walk|fast>, mwtr_step_<walk|fast>  (sv_traverse_mw picks by speed)
    for gait in ("walk", "fast"):
        p = f"sdr_com_traverse_{gait}"
        for g in ("sm", "md", "lg"):
            add(f"mwtr_mantle_{g}_{gait}", f"{p}_mantle_{g}", keep)
            add(f"mwtr_drop_{g}_{gait}", f"{p}_mantle_down_{g}", keep)
            v = f"{p}_vault_over_{g}_fixed" if _has22(f"{p}_vault_over_{g}_fixed") else f"{p}_vault_over_{g}"
            add(f"mwtr_vault_{g}_{gait}", v, keep)
        add(f"mwtr_step_{gait}", f"{p}_step_over", keep)
    # Pistol on open ground (MW19 AI exposed pistol): pstl_twitch_<i> fidgets in the aimed stance; starts / stops for
    # pistol runs: mwt_start_<pstljog|pstlrun>_<n> (exits from the aim stance), mwt_stop_<pstljog|pstlrun>_<f>_<n>.
    i = 0
    # (0.38.6: not sdr_com_exposed_pstl_twitch01-04: additive data, a rigid stick figure baked as poses)
    for src in [f"sdr_com_exposed_pstl_aim_5_twitch{k:02d}" for k in range(1, 15)]:
        if _has22(src):
            i += 1
            add(f"pstl_twitch_{i}", src, keep)
    for gait, g in (("jog", "pstljog"), ("run", "pstlrun")):
        for n in _N8:
            add(f"mwt_start_{g}_{n}", f"sdr_com_exposed_pstl_{gait}_exit_{n}", keep)
            for foot in ("l", "r"):
                add(f"mwt_stop_{g}_{foot}_{n}", f"sdr_com_exposed_pstl_{gait}_arrival_{foot}_{n}", keep)
    # Prone dives and twitches (MW19 AI): mwp_dive_<jog|run>_<l|r>_<n>  running and dropping prone (numpad n = the
    # turn it ends on, like cover arrivals), its last frame's pelvis on the prone idle's; mwp_twitch_<i>  fidgets lying
    # still (frame 0 on the prone pelvis).
    prone_end = {"loop": False, "center": ("pelvis_last", "sdr_com_exposed_stand_to_exposed_prone")}
    prone_start = {"loop": False, "center": ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")}
    for gait in ("jog", "run"):
        for foot in ("l", "r"):
            for n in _N8:
                add(f"mwp_dive_{gait}_{foot}_{n}", f"sdr_com_exposed_prone_{gait}_arrival_{foot}_{n}", prone_end)
    # (0.38.6: the prone twitches are additive data too, a rigid stick figure baked as poses: not built any more)
    # Stance changes in place (TIF.TransMW.Stance): mwk_down_<n> standing -> crouched (8 straight down; MW22's 2 / 4 / 6
    # crouch while turning to face behind / left / right), mwk_up_8 crouched -> standing, mwk_down_pstl with a pistol.
    for n in ("8", "2", "4", "6"):
        # (8 is MW19's, gun bone animated; MW22's turning 2 / 4 / 6 have the static one: crouched arms laid over)
        add(f"mwk_down_{n}", f"sdr_com_exposed_stand_to_exposed_crouch01_{n}", keep if n == "8" else dict(keep, **AI_ARMS_CROUCH))
    add("mwk_up_8", "sdr_com_exposed_crouch_to_exposed_stand01_8", keep)
    add("mwk_down_pstl", "sdr_com_exposed_pstl_to_crouch_idle", keep)
    # Low ready (MW19 AI gun_down pose over the AI aimed idle), built masked ("ub") so TIF lays it over any legs.
    #   lowready / lowready_cqb    open ground / CQB interior gun-down
    add("lowready", "sdr_com_exposed_stand_idle01", {"loop": True, "ub": True, "overlay": "sdr_com_exposed_stand_gun_down"})
    add("lowready_cqb", "sdr_com_exposed_stand_idle01", {"loop": True, "ub": True, "overlay": "sdr_cqb_exp_interior_gun_down"})
    # Into cover from right beside it.
    cov = {"center": False, "loop": False}
    xin = {
        "cr": {"st": ["sdr_com_trans_exposed_stand_to_cover_crouch_6"],
               "cr": [f"sdr_com_trans_exposed_crouch_to_cover_crouch_0{v}_{d}" for v in (1, 2) for d in (2, 4, 6)]},
        "ls": {"st": [f"sdr_com_trans_exposed_stand_to_cover_left_stand0{v}_8" for v in (1, 2, 3)],
               "cr": [f"sdr_com_trans_exposed_crouch_to_cover_left_stand0{v}_{d}" for v in (1, 2, 3) for d in (2, 4, 6, 8)]},
        "rs": {"st": [f"sdr_com_trans_exposed_stand_to_cover_right_stand0{v}_8" for v in (1, 2, 3)],
               "cr": [f"sdr_com_trans_exposed_crouch_to_cover_right_stand0{v}_{d}" for v in (1, 2, 3) for d in (2, 4, 6, 8)]},
    }
    for t, by in xin.items():
        for stance, clips in by.items():
            for k, clip in enumerate(clips, 1):
                add(f"mwc_{t}_xin_{stance}_{k}", clip, cov)
    # Long deaths.
    death = {"center": False, "loop": False, "motion": "death"}
    for st, p in (("st", "sdr_com_exposed_stand_long_death_crawl"), ("cr", "sdr_com_exposed_crouch_long_death_crawl")):
        for kind, loop in (("back", "back"), ("belly", "belly"), ("l", "l_side"), ("r", "r_side")):
            add(f"mwld_{st}_{kind}_enter", f"{p}_{kind}_enter", keep)
            add(f"mwld_{st}_{kind}_loop", f"{p}_{loop}", keep)
            add(f"mwld_{st}_{kind}_death", f"{p}_{kind}_death", death)
    p = "sdr_com_exposed_long_death"
    for kind, src in (("b", "b"), ("l2", "l"), ("r2", "r")):
        add(f"mwld_st_{kind}_enter", f"{p}_{src}_enter", keep)
        add(f"mwld_st_{kind}_loop", f"{p}_{src}_idle", keep)
        add(f"mwld_st_{kind}_death", f"{p}_{src}_death", death)
    add("mwld_st_knees_enter", f"{p}_f_knees_enter", keep)
    add("mwld_st_knees_loop", f"{p}_f_knees_loop", keep)
    add("mwld_st_knees_death", f"{p}_f_knees_death", death)
    return out


FAMILIES["aimove"] = ai_move_family()


# Wading (0.35.2, MW22 sdr_wtr_*): moving through knee- to chest-deep water (TIF NW2 tif_wade 1 knee / 2 deep).
#   mwwd_idle, mwwd_walk_<dir>_loop, mwwd_fast_<dir>_loop   gun up: stand, 8-way wade, 8-way hurried wade (MW22 AI
#                                                           strafes: the aimed idle's arms, like the dry ones)
#   mwwd_calm_<knee|chest>_idle / _walk                      weapon lowered, by depth
def wade_family():
    out = []
    add = _adder(out)
    aim = dict(LOOP, **AI_ARMS)
    # (2026-11-19, user: wading idle "has twitchy leg movement". Measured on the bakes (scratchpad wade_cand.py):
    # sdr_wtr_exposed_neutral is one frame with the right foot 8 in up; the *_patrol_idle_01 calm idles hold the right
    # foot 14 in up, kick it to 36 in three times and pop 23 in at the loop seam. Now: the weight-shift idle 01 and the
    # patrol idles 02 - feet planted (< 1.5 in), seamless.)
    add("mwwd_idle", "sdr_com_exposed_wtr_shift_idle01", aim)
    for n, d in DIRS.items():
        add(f"mwwd_walk_{d}_loop", f"sdr_wtr_walk_{n}", aim)
        add(f"mwwd_fast_{d}_loop", f"sdr_wtr_fast_{n}", aim)
    add("mwwd_calm_knee_idle", "sdr_wtr_knee_patrol_idle_02", LOOP)
    add("mwwd_calm_knee_walk", "sdr_wtr_walk_knee_8", LOOP)
    add("mwwd_calm_chest_idle", "sdr_wtr_chest_patrol_idle_02", LOOP)
    add("mwwd_calm_chest_walk", "sdr_wtr_chest_patrol_walk_8", LOOP)
    return out


FAMILIES["wade"] = wade_family()


# Recoil kicks (TIF 0.36.0, user: per-shot clip kick instead of the code spine bend). MW19's AI firing clips carry one
# "fire" notetrack per shot; each shot becomes an additive upper-body clip (tif_mw_build shot_slice: from the note to
# the next one, max 6 frames, then 5 frames easing back; QC delta of its own first frame). cl_body plays a random one
# per networked shot on its own layer, over any pose.
#   mwfk_<rifle|pistol|shotgun>_<st|cr>_<i>
import sys as _sys
_sys.path.insert(0, r"K:\mods map pics\smh_cod_anim_baker\tools")
import cod_anim_prep as _prep

_KICK = {
    ("rifle", "st"): ["sdr_com_exposed_shoot_auto_01", "sdr_com_exposed_shoot_auto_02"]
                     + [f"sdr_com_exposed_burst_0{i}" for i in range(2, 7)],
    ("rifle", "cr"): [f"sdr_com_exposed_crouch_burst_0{i}" for i in range(3, 7)]
                     + ["sdr_com_exposed_crouch_shoot_auto_01", "sdr_com_exposed_crouch_shoot_auto_02"],
    ("pistol", "st"): [f"sdr_com_exposed_stand_pstl_burst_0{i}" for i in range(2, 6)],
    ("shotgun", "st"): [f"sdr_com_exposed_stand_shotgun_fire0{i}" for i in range(1, 4)],
    ("shotgun", "cr"): [f"sdr_com_exposed_crouch_shotgun_fire0{i}" for i in range(1, 4)],
    # (0.36.1) firing from cover, leaning round a corner: per corner type (TIF ls / rs / lc / rc)
    ("lean", "ls"): ["sdr_com_cover_left_stand_lean_fire"] + [f"sdr_com_cover_left_stand_lean_fire_burst{i}" for i in range(2, 7)]
                    + [f"sdr_com_cover_left_stand_lean_fire_semi{i}" for i in range(2, 6)],
    ("lean", "rs"): ["sdr_com_cover_right_stand_lean_fire"] + [f"sdr_com_cover_right_stand_lean_fire_burst{i}" for i in range(2, 7)]
                    + [f"sdr_com_cover_right_stand_lean_fire_semi{i}" for i in range(2, 6)],
    ("lean", "lc"): ["sdr_com_cover_left_crouch_lean_fire"] + [f"sdr_com_cover_left_crouch_lean_fire_burst{i}" for i in range(2, 7)]
                    + [f"sdr_com_cover_left_crouch_lean_fire_semi{i}" for i in range(2, 6)],
    ("lean", "rc"): ["hm_grnd_org_cover_right_crouch_lean_fire_ar"]
                    + [f"hm_grnd_org_cover_right_crouch_lean_fire_semi{i}_ar" for i in range(2, 6)],
    # (0.36.1) lying down (also the LMG on its prone bipod, scaled down in cl_body)
    ("prone", "pr"): [f"hm_grnd_red_prone_burst_0{i}_ar" for i in range(3, 7)] + ["hm_grnd_red_prone_fire01_ar"],
}
KICK_MAX, KICK_BACK = 6, 5


def recoil_family():
    out = []
    for (kind, st), clips in _KICK.items():
        i = 0
        for clip in clips:
            if not _has(clip):
                continue
            a = _prep.read_seanim(f"{_SRC}/{clip}.seanim")
            fires = sorted(fr for fr, t in (a.get("notes") or []) if "fire" in t.lower())
            for k, n in enumerate(fires):
                if kind == "shotgun":
                    w = a["frames"] - 1 - n          # the shot and the pump
                else:
                    nxt = fires[k + 1] if k + 1 < len(fires) else n + KICK_MAX
                    w = max(3, min(KICK_MAX, nxt - n))
                i += 1
                out.append((f"mwfk_{kind}_{st}_{i}", clip, {"shot": (n, w, KICK_BACK), "loop": False}))
    return out


FAMILIES["recoil"] = recoil_family()


# Surrender / captives (TIF 0.38.0, replacing the GTA get-up-to-knees poses with the GTG removal): MW22's stash
# surrender: going down to the knees (hands up), then the kneeling idle (loop).
#   mwsu_down, mwsu_idle
def surrender_family():
    out = []
    add = _adder(out)
    add("mwsu_down", "bdr_1100_stash_woman_surrender_react_alt_enemy01", {"loop": False})
    add("mwsu_idle", "bdr_1100_stash_woman_surrender_react_idle_alt_enemy01", {"loop": True})
    return out


FAMILIES["surrender"] = surrender_family()


# RPG locomotion (2026-11-19, user: RPG soldiers looked wrong - only the aimed idles were the RPG's, everything else
# was the rifle's clips with the launcher in rifle hands). MW19 has no RPG locomotion, but it has the RPG's upper-body
# poses (sdr_rpg_exposed_<stand|crouch>_<ready|gun_down>: 13 bones, spine4 / neck / head / arms / j_gun, no legs; CoD
# lays them over whatever the legs do) and the full RPG aim pose. Same approach as AI_ARMS for the rifle strafes:
#   rpg_mstg_<walk|run>_<dir>_loop, rpg_crouch_<walk|run>_<dir>_loop   the strafes with the RPG on the shoulder (aim
#                                                                    pose's upper body on the ready pose's bones)
#   rpg_calm_<idle|walk|run|sprint>    calm sets with the launcher lowered (gun_down)
#   rpg_alert_<idle|walk>              alert sets with it half up (ready)
# (The RPG poses don't key j_spine4: masked with the rifle's ready pose, which does, the chest is pinned to the RPG aim
# pose's; gun_down / ready take their chest from the RPG aim pose too (overlay_chest). Without it the launcher rode
# each base clip's lean: ~65 deg down on crouch strafes and jogs. scratchpad rpg_check.py.)
RPG_ARMS = {"overlay": "sdr_com_exposed_stand_rpg_aim_5", "overlay_mask": "sdr_com_exposed_stand_ready"}
RPG_ARMS_CROUCH = {"overlay": "sdr_com_exposed_crouch_rpg_aim_5", "overlay_mask": "sdr_com_exposed_crouch_ready"}
RPG_DOWN = {"overlay": "sdr_rpg_exposed_stand_gun_down", "overlay_mask": "sdr_rpg_exposed_stand_gun_down",
            "overlay_chest": "sdr_com_exposed_stand_rpg_aim_5"}
RPG_READY = {"overlay": "sdr_rpg_exposed_stand_ready", "overlay_mask": "sdr_rpg_exposed_stand_ready",
             "overlay_chest": "sdr_com_exposed_stand_rpg_aim_5"}


def rpg_family():
    out = []
    add = _adder(out)
    for n, d in DIRS.items():
        add(f"rpg_mstg_walk_{d}_loop", f"sdr_com_strafe_walk_{n}", dict(LOOP, **RPG_ARMS))
        add(f"rpg_mstg_run_{d}_loop", f"sdr_com_strafe_jog_{n}", dict(LOOP, **RPG_ARMS))
        c = f"{n}_alt" if n == 3 else n
        add(f"rpg_crouch_walk_{d}_loop", f"sdr_mp_strafe_crouch_walk_{c}", dict(LOOP, **RPG_ARMS_CROUCH))
        add(f"rpg_crouch_run_{d}_loop", f"sdr_mp_strafe_crouch_fast_{c}", dict(LOOP, **RPG_ARMS_CROUCH))
    add("rpg_calm_idle", "reb_stl_patrol_idle01", dict(LOOP, center=False, **RPG_DOWN))
    add("rpg_calm_walk", "reb_stl_patrol_walk01", dict(LOOP, center=False, **RPG_DOWN))
    add("rpg_calm_run", "sdr_com_jog_loop01", dict(LOOP, **RPG_DOWN))
    add("rpg_calm_sprint", "sdr_com_run_loop01", dict(LOOP, **RPG_DOWN))
    add("rpg_alert_idle", "reb_stl_alert_idle01", dict(LOOP, center=False, **RPG_READY))
    add("rpg_alert_walk", "reb_stl_alert_walk01", dict(LOOP, center=False, **RPG_READY))
    return out


FAMILIES["rpg"] = rpg_family()


# Close-range melee (2026-11-20, user: "add the close range melee fights and the gun butt hits"; against players only
# the butt hits; "are you sure theres not an ai gun melee?" - there is: MW19's AI melee, used instead of MP's
# upper-body-only gun_butt_hit clips). All full body with their own root motion; "fire" notes are the impacts.
#   mwm_melee_<1-4>              rifle butt strokes (sdr_com_exposed_stand_melee0N; 01 strikes twice: fire 7 and 23)
#   mwm_to_melee_<1-4>           stepping into it from a stand (10 fr, 15 in);  mwm_run_to_melee_<1-4>  from a run (20 fr, 74 in)
#   mwm_pmelee_<1-4>, mwm_pto_melee_<1-4>, mwm_prun_to_melee_<1-4>   the pistol whip versions
#   mwm_fight_<aw|dw>_<att|def>  MW19's paired fight hm_grnd_melee02: attacker wins (defender dies at melee_death
#                                87/114) / defender wins (attacker at 67/105); one scene space: built uncentred, both
#                                entities start on the same origin and yaw.
def melee_family():
    out = []
    add = _adder(out)
    one = {"loop": False}
    for i in (1, 2, 3, 4):
        add(f"mwm_melee_{i}", f"sdr_com_exposed_stand_melee0{i}", one)
        add(f"mwm_to_melee_{i}", f"sdr_com_exposed_stand_to_melee0{i}", one)
        add(f"mwm_run_to_melee_{i}", f"sdr_com_exposed_stand_run_to_melee0{i}", one)
        add(f"mwm_pmelee_{i}", f"sdr_com_exposed_stand_pstl_melee0{i}", one)
        add(f"mwm_pto_melee_{i}", f"sdr_com_exposed_stand_pstl_to_melee0{i}", one)
        add(f"mwm_prun_to_melee_{i}", f"sdr_com_exposed_stand_pstl_run_to_melee0{i}", one)
    fight = {"loop": False, "center": False}
    add("mwm_fight_aw_att", "hm_grnd_melee02_attacker_wins_att", fight)
    add("mwm_fight_aw_def", "hm_grnd_melee02_attacker_wins_def", fight)
    add("mwm_fight_dw_att", "hm_grnd_melee02_defender_wins_att", fight)
    add("mwm_fight_dw_def", "hm_grnd_melee02_defender_wins_def", fight)
    return out


FAMILIES["melee"] = melee_family()


# Civilians, the rest (TIF 0.38.7, 2026-11-18). MW22's civilian set (scratchpad civ_triage.py: all full-body
# poses with leg tracks, none additive; the door-open clips have no legs and are left out, as are the female,
# phone / texting / tourist / selfie clips that need props, stairs and the seated scenes).
# Numpad n is relative to the civilian's facing (8 = ahead).
#   civ_react_<sm|md|lg><v>_<n>   gunfire with the threat at n: flinch and break into a run away from it (root
#                                 motion; ends running)
#   civ_startle_<n>               a fright at n: turn to face it (n = 1, 2l, 2r, 3, 4, 6, 7, 8, 9)
#   civ_panic_idle_<n>            standing, panicked;  civ_scared_idle_<n>  standing, scared
#   civ_tocower_<n> -> civ_cowering_<n> -> civ_uncower_<n>   panic idle down into a crouched cower, and back up
#   civ_prone_<n>                 flat on the ground, hands over the head
#   civ_stand_<n>                 calm standing idles (shifting weight, arms folded, looking round)
#   civ_walk_<n> / civ_wwalk_<n>  calm / wary walks (each civilian keeps one)
#   civ_chat_<n>                  talking in a group
#   civ_pevade_<2|4|6|8>          panicked step out of the way (step toward n)
#   civ_duck_run                  running doubled over (gunfire very close)
def civ22_family():
    out = []
    add = _adder(out)
    loop = {"loop": True}
    one = {"loop": False}
    keep = {"loop": True, "center": False}
    for size, v in (("sm", 1), ("sm", 2), ("md", 1), ("md", 2), ("lg", 1)):
        for n in _N8:
            add(f"civ_react_{size}{v}_{n}", f"civ_pnc_exposed_stand_{size}_reaction0{v}_{n}", one)
    for n in ("1", "2l", "2r", "3", "4", "6", "7", "8", "9"):
        add(f"civ_startle_{n}", f"civ_cap_relaxed_react_scared01_{n}", one)
    k = 0
    for c in [f"civ_cap_panic0{i}_stand_exposed_idle" for i in range(1, 7)] + [f"civ_cap_panic_idle0{i}" for i in (1, 2, 3)] \
            + [f"civ_casual_frantic_exposed_idle_twitch_{x}" for x in "abc"]:
        if _has22(c):
            k += 1
            add(f"civ_panic_idle_{k}", c, loop)
    k = 0
    for c in ("civ_cap_scared01_stand_exposed_idle", "civ_cap_scared01_stand_exposed_idle02", "civ_cap_scared02_stand_exposed_idle",
              "civ_cap_scared03_stand_exposed_idle", "civ_cap_scared_idle01", "civ_cap_scared_idle02", "civ_cap_scared_idle03"):
        if _has22(c):
            k += 1
            add(f"civ_scared_idle_{k}", c, loop)
    for i in (1, 2, 3):
        add(f"civ_tocower_{i}", f"civ_cap_panic01_idle_to_cower0{i}", one)
        add(f"civ_cowering_{i}", f"civ_cap_cower0{i}_idle", keep)
        add(f"civ_uncower_{i}", f"civ_cap_cower0{i}_idle_to_panic01", one)
    for i in range(1, 7):
        add(f"civ_prone_{i}", f"civ_cap_cower0{i}_prone_exposed_idle", keep)
    k = 0
    for c in ("civ_cas_stand_idle01_male01", "civ_cas_stand_idle02_male01", "civ_cas_stand_idle03_male01",
              "civ_cap_relax01_stand_exposed_idle", "civ_cap_relax_arm_fold01_stand_exposed_idle",
              "civ_cap_relax_look01_stand_exposed_idle", "civ_cap_relax_look_r01_stand_exposed_idle"):
        if _has22(c):
            k += 1
            add(f"civ_stand_{k}", c, loop)
    for i in range(1, 5):
        add(f"civ_walk_{i}", f"civ_cas_walk0{i}_8_male01", loop)
        add(f"civ_wwalk_{i}", f"civ_suspicious_walk0{i}_man01", loop)
    k = 0
    for g in ("3a", "3b"):
        for i in (1, 2, 3):
            c = f"civ_scn_gen_grp{g}_man0{i}_idle"
            if _has22(c):
                k += 1
                add(f"civ_chat_{k}", c, loop)
    for n in (2, 4, 6, 8):
        add(f"civ_pevade_{n}", f"civ_pnc_player_evasion_{n}", one)
    add("civ_duck_run", "civ_pnc_strafe_jogduck_8", loop)
    return out


FAMILIES["civ22"] = civ22_family()

# Human shield (2026-11-20, user: "what about human shielding" -> "build it"): MW19's AI hostage taker (Spec Ops
# cp_hostagetaker, matched attacker / victim pairs, one scene). The captor never moves (his tag_origin stays put); the
# hostage starts 82 in to his right (raw tag_origin: x -3.6, y -81.9), is pulled in and kneels at (8.2, -32.9) beside
# him, slightly ahead. Built uncentred: each body sits on its own tag_origin, TIF places the hostage from those keys.
#   mwsh_<grab|idle|death|rescue>_<att|vic>   grab (51 fr), hold (286, loop), captor shot: he drops, she runs ~70 in
#                                             clear (65), rescue: he shoves her to the floor and comes up aiming (59)
# Not built (noted for semi-scripted scenes, TIFDIDDY/HUMAN_SHIELD.md): Clean House's shield (thd_2f_020_hostage_*,
# aim_2/4/6/8 poses), the Embassy pistol grab (emb_oc_010_hostage_*), the bomb-strapped hostage (hostage_bomb_idle_*).
def shield_family():
    out = []
    add = _adder(out)
    one = {"loop": False, "center": False}
    for c in ("grab", "idle", "death", "rescue"):
        o = dict(one, loop=True) if c == "idle" else one
        add(f"mwsh_{c}_att", f"cp_hostagetaker_{c}_attacker", o)
        add(f"mwsh_{c}_vic", f"cp_hostagetaker_{c}_victim", o)
    # (0.38.28) Clean House's held-in-front shield (thd_2f_020_hostage_*), the variant for when no player sees it start
    # (no grab clip: it starts held). mwsc_<aim_start|aim|idle>_<att|vic> hold; captor shot: mwsc_death_att (his neck
    # shot, down by f40; cut at f90 of 947) with mwsc_live_vic (she drops and starts up; cut at f78: she grabs his gun at
    # f84, user: "make sure to not feature that part"); hostage shot: mwsc_live_att (his reaction) with mwsc_death_vic
    # (kill_me f42) or mwsc_death_hs_vic (headshot, start_ragdoll f63: cut there).
    ch = "thd_2f_020_hostage_"
    for c in ("aim_start", "aim", "idle"):
        o = dict(one, loop=True) if c != "aim_start" else one
        add(f"mwsc_{c}_att", f"{ch}alqatala_{c}", o)
        add(f"mwsc_{c}_vic", f"{ch}civ_{c}", o)
    add("mwsc_death_att", f"{ch}alqatala_death", dict(one, end=90))
    add("mwsc_live_vic", f"{ch}civ_live", dict(one, end=78))
    add("mwsc_live_att", f"{ch}alqatala_live", one)
    add("mwsc_death_vic", f"{ch}civ_death", one)
    add("mwsc_death_hs_vic", f"{ch}civ_death_headshot", dict(one, end=63))
    return out


FAMILIES["shield"] = shield_family()