"""Per-gun handling for TIF's baked MW guns (TIF 0.38.1, user: "tune the guns everywhere except for damage").

Damage, range and falloff stay the weapon base's (_tif_bases.lua). Per gun here:
  rpm      rounds per minute inside a burst (TIF sv_weapon cadence: rate = 60 / rpm; pistols use their own jittered
           group timing, W.PISTOL, so their rpm only caps a semi-auto rhythm)
  auto     full auto (False: semi-auto: TIF fires 1-2 round groups, no bursts)
  mag      magazine / belt / tube
  dmg      (optional) damage per round instead of the base's (FAL only, user: between rifles and DMRs)
  semi     (optional) the semi-auto fire pattern by range, TIF sv_weapon W.SEMI: "dmr" (strings up close, spaced far
           out: marksman rifles, FAL), "heavy" (single spaced shots: Rytec). Overrides the carrier's burst habits.
  reload   seconds out of the fight reloading (the MW reload clip is stretched to it: rifle clip 3.3 s, SMG 3.3 s,
           LMG 2.9 s, shotgun 3.2 s, pistol 1.5 s, RPG 2.7 s)
Values follow the real guns / their MW19 / MWII versions, rounded. gun_compile.py writes them into each gun's Lua
(lua_block); apply_tune.py (scratchpad) applied them to the built guns.
"""

TUNE = {
    # rifles
    "akm":            dict(rpm=600, auto=True,  mag=30,  reload=2.4),
    "ak_ff":          dict(rpm=600, auto=True,  mag=30,  reload=2.4),
    "ak_warsaw_grip": dict(rpm=650, auto=True,  mag=30,  reload=2.4),
    "ak_warsaw_sup":  dict(rpm=650, auto=True,  mag=30,  reload=2.4),
    "ak74u":          dict(rpm=700, auto=True,  mag=30,  reload=2.3),
    "an94":           dict(rpm=650, auto=True,  mag=30,  reload=2.4),
    "asval":          dict(rpm=900, auto=True,  mag=20,  reload=2.3),
    "fal":            dict(rpm=650, auto=False, mag=20,  reload=2.3, semi="dmr", dmg=33),
    "kilo_sof":       dict(rpm=750, auto=True,  mag=30,  reload=2.4),
    "m13_sof":        dict(rpm=800, auto=True,  mag=30,  reload=2.3),
    "m4_sof_a":       dict(rpm=800, auto=True,  mag=30,  reload=2.3),
    "m4_sof_b":       dict(rpm=800, auto=True,  mag=30,  reload=2.3),
    "oden":           dict(rpm=520, auto=True,  mag=20,  reload=2.1),
    "scar":           dict(rpm=650, auto=True,  mag=20,  reload=2.1),
    # SMGs
    "bizon":          dict(rpm=680, auto=True,  mag=64,  reload=2.6),
    "mp5":            dict(rpm=800, auto=True,  mag=30,  reload=2.3),
    "mp7_sof":        dict(rpm=950, auto=True,  mag=40,  reload=2.3),
    "uzi":            dict(rpm=600, auto=True,  mag=32,  reload=2.3),
    # LMGs
    "bruen":          dict(rpm=750, auto=True,  mag=100, reload=4.2),
    "bruen_sof":      dict(rpm=750, auto=True,  mag=100, reload=4.2),
    "finn":           dict(rpm=750, auto=True,  mag=75,  reload=3.8),
    "m91":            dict(rpm=700, auto=True,  mag=100, reload=4.2),
    "mg34":           dict(rpm=900, auto=True,  mag=50,  reload=3.6),
    "pkm":            dict(rpm=650, auto=True,  mag=100, reload=4.2),
    "pkm_sof":        dict(rpm=650, auto=True,  mag=100, reload=4.2),
    # marksman (semi-auto) / anti-materiel
    "ebr":            dict(rpm=240, auto=False, mag=10,  reload=2.5, semi="dmr"),
    "ebr_sup":        dict(rpm=240, auto=False, mag=10,  reload=2.5, semi="dmr"),
    "m13_dmr":        dict(rpm=300, auto=False, mag=20,  reload=2.4, semi="dmr"),
    "sks":            dict(rpm=240, auto=False, mag=10,  reload=2.5, semi="dmr"),
    "svd":            dict(rpm=200, auto=False, mag=10,  reload=2.5, semi="dmr"),
    "svd_plague":     dict(rpm=200, auto=False, mag=10,  reload=2.5, semi="dmr"),
    "rytec":          dict(rpm=65,  auto=False, mag=5,   reload=2.2, semi="heavy"),
    # pistols
    "m19":            dict(rpm=400, auto=False, mag=17,  reload=1.6),
    "m1911":          dict(rpm=360, auto=False, mag=8,   reload=1.5),
    "m1911_jav":      dict(rpm=360, auto=False, mag=8,   reload=1.5),
    "sykov":          dict(rpm=400, auto=False, mag=12,  reload=1.6),
    "x16":            dict(rpm=400, auto=False, mag=15,  reload=1.6),
    "x16_sof":        dict(rpm=400, auto=False, mag=15,  reload=1.6),
    # shotguns
    "db_full":        dict(rpm=240, auto=False, mag=2,   reload=1.6),
    "db_short":       dict(rpm=240, auto=False, mag=2,   reload=1.6),
    "m680":           dict(rpm=75,  auto=False, mag=7,   reload=2.4),
    "m680_breach":    dict(rpm=75,  auto=False, mag=7,   reload=2.4),
    "m680_wood":      dict(rpm=75,  auto=False, mag=7,   reload=2.4),
    # launcher
    "rpg7":           dict(rpm=75,  auto=False, mag=1,   reload=2.7),
}


def lua_block(gid):
    """The gun's tuning as Lua lines (after SWEP = table.Copy(base)), or "" if it isn't in TUNE."""
    t = TUNE.get(gid)
    if not t:
        return ""
    auto = "true" if t["auto"] else "false"
    dmgNote = ("damage %d, range the base's" % t["dmg"]) if t.get("dmg") else "damage / range stay the base's"
    return ("-- Handling (gun_tune.py: rpm %d, %s, %d rounds, %.1f s reload; " + dmgNote + ")\n"
            "SWEP.Primary = { ClipSize = %d, DefaultClip = %d, Automatic = %s, Ammo = SWEP.Primary and SWEP.Primary.Ammo }\n"
            "SWEP.GTG.rate = %.4f\nSWEP.GTG.auto = %s\nSWEP.GTG.reload_time = %.2f\n") % (
        t["rpm"], "full auto" if t["auto"] else "semi-auto", t["mag"], t["reload"],
        t["mag"], t["mag"], auto, 60.0 / t["rpm"], auto, t["reload"]) + (
        # (0.38.2) the semi-auto fire pattern, by range (TIF sv_weapon W.SEMI): "dmr" or "heavy"
        'SWEP.GTG.semi = "%s"\n' % t["semi"] if t.get("semi") else "") + (
        # (0.38.3) a damage override, only where the user asked (FAL: between the rifles' 22 and the DMRs' 44)
        'SWEP.GTG.damage = %d\n' % t["dmg"] if t.get("dmg") else "")
