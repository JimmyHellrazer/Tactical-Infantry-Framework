# TIF Workshop readiness planner

As of TIF 0.38.44 (2026-11-25). "Played" = you've run it in game and fed back. "Built" = written and passing the
offline harness (39 suites), not yet seen in game. STATUS.md tags every entry "NOT yet run in game" when it's
written and never updates the tag, so this file is the real picture.

## Verdict

The base is feature-complete for a first release. What stands between it and the Workshop:

1. **One in-game pass over everything built since 0.38.32** (list below). Nothing from 0.38.32 onward has been seen
   in game: the CQB rework, foley, corpses, shields, doors, zombies.
2. **The default factions need content the base doesn't ship.** That's a decision for you (see Blockers).
3. **A content / permission call on the companion packs** before they go up.

## Blockers (decide or fix before upload)

| # | Issue | Why it matters | Options |
|---|---|---|---|
| B1 | **Done (0.38.44).** Starter factions Insurgents / US Marines use MadIvan18's INS2 characters (permission given), rebuilt on TIF's rig and shipped in the base, with five voice packs in the base. The old militia / pmc ids are hidden aliases. | - | Clean-install check in game (test plan step 8). |
| B2 | In-game pass of 0.38.32-0.38.42 not done. | These touched core paths: corpses, movement ticks, root motion, perception, CQB. | One session per the test plan below, with `tif_mark` on anything odd. |
| B3 | The base now carries other authors' voice packs (TFA-VOX mercenary and BF3 marine, plus the Faction Pack's specops / Arabic packs). INS2 characters: MadIvan18's permission given. Companion packs reupload third-party and ripped content: TIF Faction Pack (other Workshop authors' models and voices), TIF CoD Factions, TIF Air and TIF MW Cars (CoD rips). | Workshop takedowns and DMCA. The base itself carries MW animations and MW Base sounds (you have the MW Base authors' OK). | Get permission for the third-party models in the Faction Pack, or publish it as a collection of links (Required items) instead of a reupload. |
| B4 | Sizes: base 543 MB (INS2 materials 120 MB, voices 185 MB), CoD Factions 1.24 GB, Faction Pack 1.15 GB, MW Cars 297 MB, Air 227 MB. | Big downloads put people off; check Steam's current per-item limit before uploading the 1 GB+ packs. | Split the big packs (by faction, by vehicle), or trim LODs and textures. |

## What's implemented

### Soldier body and animation
| Feature | State |
|---|---|
| MW19 body, 4,229 baked MW19 / MW22 clips, locomotion with starts / stops / turns, strafes | Played |
| Stance changes, prone (dive, crawl, get up), wading | Played |
| Per-weapon reloads, recoil from MW firing clips, sidearm switching, magazine motion | Played |
| Hit reactions by region, situational deaths, long deaths, last stand | Played |
| Death clip -> ragdoll handoff with bone velocities | Played; corpse error fixes 0.38.33-35 built, need a look |
| Modular factions (body / head / headgear parts) | Played |

### Combat AI
| Feature | State |
|---|---|
| Perception, awareness, reactions (startle, point out, look around) | Played |
| Cover (corners standing / crouched, low and chest-high walls, arrivals, lean aim, blindfire, shuffles, switches) | Played |
| Fighting from beside cover, hand-plant back in (0.38.32) | Built |
| Suppression, morale, grenades from cover and in the open, flash reactions | Played |
| LMG bipods (prone and ledges) | Played (bipod order fix 0.38.22) |
| Butt strikes, paired melee fights | Played; locked clips, corpse pose and fight sounds (0.38.34-40) built |
| Human shield (MW19 grab, clean house variant) | Played; pistol-only clean house and AI shot (0.38.40) built |
| HL2 / addon NPCs as friends and foes | Built 0.38.15 (check it's been seen) |
| Horde zombies as enemies (0.38.42) | Built |

### Squads and orders
| Feature | State |
|---|---|
| Formations, bounding, base of fire, flanks, withdraw, radio, voices | Played |
| Player squad orders (`tif_menu`) | Played |
| Medics, casualties, revives | Played |

### Room clearing (CQB)
| Feature | State |
|---|---|
| Stack, breach methods (open / kick / sledge / grenade / no-door), flashbangs, entry, hold, next room | Played (many rounds of fixes) |
| 0.38.38-41: committed breaches, glides, wall slide, plan-time clip checks, forced doorway crossing, centred kicks and crossings, doors coming off, slim hulls, no stack firing / reactions | Built, the most important thing to test |

### World and support
| Feature | State |
|---|---|
| Civilians (wander, talk, panic, flee, hide, wave over, step aside) | Played |
| Doors on the way (MW door clips), open-instead-of-barge, destructible-door compat (0.38.40) | Built |
| Foley: footsteps by surface, gear, landings, body falls, stance, mantles, soldiers and civilians (0.38.36-37) | Built |
| Vehicles: Glide driving, convoys, mounted guns, DV roads | Played (with MW cars) |
| Bases, garrisons, base presets | Played |
| Faction editor, content packs, spawn menu entries, settings panel | Played |
| Log file, watchdog, `tif_mark` | Played (logs read in this session) |
| API for DTW / GOPS / SWAT / Stackline | Used by those addons |
| Navmesh missing warning, `tif_selftest` | Built |

## Not built / known gaps

| Gap | Size | Notes |
|---|---|---|
| Default factions work without other addons (B1) | - | Done 0.38.44 (INS2 factions + voices in the base) |
| Strafe direction-change clips (MW `*_strafe_trans_*`) | M | Noted in STATUS; strafes reverse without a transition |
| Female body | L | Female models ride the male MW19 skeleton |
| Vanguard (s4) animations | M per set | Surveyed: paired kills (87 + ~195), bayonet charge, turret set, low-cover arrivals and exits, per-weapon reloads, vignettes. Same rig, untested bake |
| Walking door clips steered onto the door centre | S | You said the clearance issue was CQB only; left alone |
| Soft soldier-to-soldier collision outside CQB | M | Crowd steering + ghosting cover most of it |
| Foley volumes / distances tuned in game | S | First guesses: `tif_foley_volume` |
| Horde perf with TIF | ? | Perception checks distance first now; watch frame time with a big horde + 30 soldiers |

## Companion addons

| Addon | Size | Upload? | Notes |
|---|---|---|---|
| tactical_infantry_framework (base) | 543 MB | Yes, first | `.md`, `tools/`, `mapsrc/` ignored by addon.json; ships `maps/tif_range.bsp` on purpose |
| tif_cod_factions | 1.24 GB | After B3 / B4 | Modular CoD factions |
| tif_faction_pack | 1.15 GB | After B3 | Third-party models / voices |
| tif_mw_cars | 297 MB | After B3 | Glide MW vehicles |
| tif_air | 227 MB | After B3 | Reinforcement helicopters |
| tif_sandbox | 1 MB | Yes | Spawners and attack points |
| tif_devtools | 1 MB | **Never** | Local only (debug overlays and test commands) |
| tif_gunbake, tif_mw_anim_test | tools | **Never** | Build tools |

## In-game test plan (one session, tif_cqb + an open map)

Run `tif_mark <note>` whenever something looks off; send `garrysmod/data/tif/log_sv.txt` after.

1. **CQB (tif_cqb):** several clears of each door type. Watch for: men stepping back and forth at the stack (should be
   gone), entry clips clipping the frame, anyone left outside, kicks landing centred, doors coming off (and areaportal
   doors staying put), a team firing through the door before going in.
2. **Melee pairs:** spawn opposing soldiers face to face. Watch: both play the fight, the loser's ragdoll starts from
   the fight pose, hits and the gun drop make sound.
3. **Human shield:** let one start where you can't see (clean house): the captor should have a pistol. Wait 15+ s
   with a friendly soldier in view: he should take the shot.
4. **Foley:** walk soldiers and civilians over concrete, grass, metal, wood, water; kill a few. Footsteps and body
   falls at sensible volume?
5. **Cover:** a firefight at mixed cover: beside-cover fights now and then, no regressions in leaning.
6. **Doors (open map with the destructible-door mod):** soldiers walking through closed doors open them, don't break
   them.
7. **Horde zombies:** a horde against a squad. Do they engage each other? Frame time OK?
8. **Clean install check:** with only the base enabled (other packs off), spawn the default factions. Confirms B1.

## Release checklist

- [ ] B1 decided and done
- [ ] Test plan run, fixes in
- [ ] B3 permissions sorted for any pack going up
- [ ] Workshop text (`TIFDIDDY/WORKSHOP.md`): add Required items and companion links
- [ ] Thumbnail / screenshots / a short clip
- [ ] `tif_devtools` disabled for the clean-install check; base packs without it
- [ ] Final harness run (all suites) and `tif_selftest` on a fresh map
- [ ] Backup of the release build (like `K:\jimmyproject\_addon_backups\`)
