# TIF: MW19 animation rework (plan)

Goal: replace TIF's GTA (GTG) animations with MW19 soldier animations, except vehicle seats / vehicle cover,
and probably the weapon pool too. Done in stages, each playable on its own, switchable per faction so the GTA
set keeps working until the MW19 one is better.

Backup before any of this: `K:\backups\tif_pre_mw19_2026-11-10` (TIF 0.7.24, SWAT, GOPS, DTW, TIFDIDDY).

## How TIF animates today
- Server: every soldier is the GTA ped (`mp_m_freemode_01`) as an invisible "host". It holds 8 animation layers
  and one main sequence per stance (for hitboxes).
- Client (`npc/cl_body.lua`): every frame, picks and blends GTA clips into those layers. Up to 3 legs clips: idle,
  walk/run, 8-way strafe sorted by real travel direction. Up to 2 upper-body clips: hold, aim, fire, settle,
  reload, with an aim-pitch pose parameter.
- Server actions (`npc/sv_action.lua`): one full-body clip by name (cover in/out, peeks, blindfire, casualty
  drag, morale, vehicle entry), moving the soldier along the clip's root curve.
- The faction playermodel is drawn on top through GTG's runtime retargeter (GTA bones -> ValveBiped), and the
  gun is bone-merged to the GTA hand.
- Clips are data: `TIFG.RegisterCharacter` + `TIFG.RegisterClips` tables (seq name, dur, frames, loop, speed,
  root `curve` x/y/yaw, `tags`, foot plants), loaded from `lua/tif/gta/clips`. Factions pick a host by id.

**Key point:** MW19 can come in as a second character ("mw_male") in that same data format. Most of TIF's
behaviour code asks for clips by role, not by file, so it keeps working once each role points at an MW19 clip.

## Target design
- **New host body:** a ValveBiped (Breen skeleton) host model built by us, with MW19 clips in included
  animation models. Its own `j_gun` bone carries the clips' weapon motion.
- **Playermodels bone-merge straight onto it** (same bone names). No runtime retarget solve for MW19 soldiers:
  faster, and hitboxes match what's drawn.
- **Engine blending:** clips still go through the same layer slots, so many soldiers stay cheap. The
  `tif_mw_anim_test` per-bone Lua playback was only a probe and doesn't scale.
- **Clip library generated offline** by the pipeline: `cod_anim_prep.py` -> `cod_to_breen.py` -> a new builder
  that, per clip:
  - makes it in-place (root motion stripped from the pelvis) and writes the root `curve` like GTG's;
  - computes speed and travel direction;
  - turns MW19 notetracks into `tags`: footsteps, `ik_in/out_left_hand`, `grenade_off`, `finish`, ...;
  - writes the QC(s) and the `RegisterClips` Lua.
- **Role aliases:** TIF's GTA clip names (idle, mstg_walk_*, cw2_intro_*, blind_in, ...) map to MW19 clips in
  one table, so behaviour code doesn't change until a stage wants MW19-only features (9-way cover arrivals).
- **Vehicles stay GTA:** when a soldier sits in a vehicle, the host switches to the GTA ped (SetModel) and back
  on exit. The GTA vehicle seat, drive-by and vehicle cover clips are kept as they are.

## Weapon and sling handling
What the MW19 clips carry:
- `j_gun` is keyed in nearly every soldier clip, so the gun's whole path is baked in: one-handed moments,
  hanging while the hands do something else, raising and lowering. Following `j_gun` gets whatever the animator
  did.
- `tag_sling` / `j_sling_*` / `j_slingmount` appear mostly in multiplayer reload/inspect clips. They're the
  weapon's strap and its attach point (cosmetic), not a "gun goes to the sling" switch.
- Notetracks mark hand usage: `ik_out_start_left_hand` / `ik_in_end_left_hand` (support hand leaves / returns to
  the gun), `grenade_off` (release frame), footsteps.

Plan:
1. The gun attaches to the host's `j_gun` bone, not the hand, so clips that move or drop the gun just work.
2. **Retarget anchor:** today `cod_to_breen.py` keeps `j_gun` relative to the right hand. When the gun hangs
   away from the hand (slung), keeping it relative to the chest is truer on other body sizes. Blend the anchor
   hand -> chest by how far the gun is from the hand.
3. **Sling fallback for clips with no `j_gun` keys** (civilian-style, scripted, later Ready or Not clips): TIF
   puts the gun on a chest sling point (fixed offset, a little sway), switched by a per-clip `hands` tag or the
   notetracks.
4. **Left-hand IK** follows the `ik_in/out` notetracks, so the support hand snaps to the gun only when the clip
   says it's on the gun.
5. **Weapon pool:** with MW19 guns, the weapon model's origin is `tag_weapon` = `j_gun`, so there's no per-gun
   grip fitting. The guns' own strap bones can follow `tag_sling` keys or simple jiggle. GTA guns would each need
   a fitted grip offset.

## Coverage (from the MW19 extract, `sdr_` soldier set, ~17k clips)
| TIF role | MW19 source | Notes |
|---|---|---|
| Idle, walk, run, sprint, 8-way strafe | `sdr_mp_strafe_*` (1,270: walk/jog/sprint/crouch, numpad dirs 1-9, starts/stops), `sdr_cqb_*` strafe, `sdr_com_run/jog` | Direction sets sort by root travel like GTG's |
| Aim up/down/left/right | `9pt_aim_1..9` poses (cover, crouch, prone), `sdr_mp_aims_*_circle_90` | Build as 3x3 blend sequences with aim yaw/pitch pose params |
| Fire, reload | `sdr_mp_stand/crouch/prone_custom_reload_*` (355, per weapon class), `com_*reload01`, additive fire | Weapon classes ar/sm/lm/sh/pi/sn |
| Cover | `sdr_com_cover_*` (1,900): hide/lean idles, lean aim 9pt, blindfire, reloads, arrivals/exits in 9 directions | Richer than GTA's; arrivals need directional picking |
| CQB / room clearing | `sdr_cqb_*` (2,400): cover, strafe, stairs, pistol and riot-shield sets | |
| Prone | `sdr_mp_prone_*` (472), `sdr_com_exposed_prone_*` (150) | |
| Pain / flinch | ~750 directional and hit-location pains | Replaces the spine-bone flinch hack |
| Death | ~370 death clips (cover, exposed, running, balcony), then ragdoll | |
| Downed / casualty | `sdr_mp_laststand_*` (crawl, revive), drag scenes | Drag is scene-specific; may need picking |
| Grenades | `sdr_com_cover_*_grenade_throw*`, `sdr_mp_*_throw_eq_offhand` (with `grenade_off` notetrack) | |
| Flashbang / stun | `*_flashbang_react_*` (cover/exposed/prone, short and long) | |
| Doors | `sdr_com_inter_*door_*` (open, pull, tactical, flash/smoke in) | MW19 "kicks" aren't real kicks: real kick/breach later from Ready or Not |
| Traversal | `sdr_com_traverse_*` (330), mantle, ladders, stairs | TIF has no vaulting yet |
| Melee | `sdr_com_*melee*`, `sdr_mp_me_*` | |
| Surrender / hands up | **Missing** as a generic set (only scripted hands-up scenes) | Cut from scenes, keep GTA, or Ready or Not later |
| Civilians | `civ_*` (950: casual, panic, cover, cower) | For GOPS/DTW/SWAT civilians |
| Vehicles | stays GTA | By design |

## Stages
Each stage ships behind a per-faction host switch (`host = "mw_male"`) plus a convar to force all factions back
to GTA, and is tested in game before the next.

**Stage 0: tooling (done 2026-11-10)**
- `cod_to_breen.py` retarget (matches the old Breen set); proc clavicle follow in `cod_anim_prep.py`.
- `tif_mw_anim_test` probe addon; TIF backup.

**Stage 1: clip pipeline + host model (built 2026-11-10, waiting on the in-game look)**
- Done:
  - `tif_mw_build.py` (smh_cod_anim_baker/tools) reads `K:\jimmyproject\tif_mw\manifest.py`.
  - Output addon `tif_mw_anims`: models `tif_mw/mw_male(+_move,_react).mdl` and
    `lua/tif/gta/{clips,characters}/mw_male.lua`. TIF's GTA layer loads those from any addon, so TIF itself
    wasn't edited.
  - 62 roles / 59 sequences: stand/crouch idle; walk, jog, sprint; 8-way walk, jog, crouch walk, crouch fast;
    plus the 24 door/flash clips.
  - Checker: `tif_mw_view list | <role|n|next> [still]`, `tif_mw_view_pm <playermodel>`, `tif_mw_view_clear`.
- Findings:
  - MW19 SEAnim translations are **cm**. `cod_anim_prep.py` now converts them (`--loc-scale`); every older
    conversion, zd30 included, had root travel 2.54x too long.
  - MP clips (`sdr_mp_*`) stand the body ~10 in behind / ~6 in beside tag_origin. The builder re-centres
    the feet under the origin (loops: average; one-shots: first frame).
  - Foot slide at plant frames: 10-25 u/s on most loops (swing 200-500). Outliers: `crouch_mstg_run_fwd_-90`,
    `mstg_run_bwd_-135` (~95).
  - Shoulders (user, first in-game look): Breen's clavicles start ~2.4 in higher than the CoD rig's, so
    copying clavicle direction pushed shrugged shoulders above the neck. `cod_to_breen.py` SHOULDER_FIT now
    moves the shoulder relative to Spine4 by the source's shrug from rest. Built shoulders are within ~0.6 in
    of the source.
  - Corpses: TIF ragdolls the host model, and mw_male has no physics yet. Plan for Stage 2: ragdoll the
    faction playermodel instead.
- Builder script: clip manifest (role -> MW19 clip) -> in-place Breen SMDs + root curves + notetrack tags +
  QC(s) + `RegisterClips` Lua.
- ValveBiped host model with `j_gun`; sequence count split across include models.
- Check: spawn the host, scrub clips, compare root curves against foot plants.

**Stage 2: locomotion + aiming + firing (built 2026-11-10 as TIF 0.8.0, not run in game; details in STATUS.md)**
- Built as planned except:
  - Aim, recoil and flinch are spine bends rather than 9-point aim blends: MW strafe clips already aim.
  - The GTA fallback covers every action the MW body lacks, not only vehicles (cover stays GTA until
    Stage 3).
  - The gun is held from the hands instead of `j_gun`. MW19 `j_gun` differs between MP clips (fixed offset +
    `j_gun_adjust` rotation) and AI/campaign clips (fully keyed); decoding it is follow-up work, needed for
    slings.
- Original scope:
- Register "mw_male"; alias idle/walk/run/sprint/strafe/crouch.
- Aim as 9-point blend (pose params instead of `gtg_aim_pitch`); fire/settle/reload per weapon class.
- Playermodel bone-merges straight on; gun on `j_gun`; left-hand IK from notetracks.
- Host swap to the GTA ped in vehicles.
- Check: walk/strafe foot sliding, aiming at all angles, hitboxes vs drawn body, frame time vs GTA host
  (`tif_bench`).

**Gun roll fix (2026-11-10, after the first Stage 2 test):** GTA gun models are +X barrel, **+Y up**, with the
grip bone (PH_R_Hand) at the origin. `place_gun_vb` assumed +Z up, which rolled them 90 degrees. `gun_info` now
takes the barrel from the longest bounding-box axis (toward the muzzle) and up from where the gun's body sits
relative to the grip. Not yet seen in game. GTA guns also carry a `Gun_GripL` attachment, usable later for
left-hand IK.

## Revised stages (user-approved 2026-11-11)
Done:
- 1 pipeline, 2 locomotion/aim/reload, 3 cover, prone, flashbang reactions (0.9.0).
- 0.10.0: all of Stage 5; the Stage 3 arrival-path fix; Stage 7 deaths + pains; Stage 8 CQB movement, prone
  aim and cover grenades.
- Left in those stages:
  - Stage 6 (searching smart objects, starts/stops/turns);
  - Stage 7 cover pains + laststand/revive;
  - Stage 8 vault/mantle, riot shield, flashlights, exposed grenade throws;
  - the j_gun / sling decode.
- **Stage 5: calm posture + graded reactions (next)**
  - Unaware soldiers patrol with weapons lowered (reb_stl patrol walk/idle) and do idle activities at posts
    (smoking, phone, water bottle) with start / loop / end.
  - Activities make them slower to react ("caught off guard": the end or react clip plays first).
  - Suspicious / searching use the alert set.
  - Perception events play small / medium / large react clips toward the stimulus; finding a body plays
    check-body, then the alarm.
- **Stage 5b: situational idles (built in 0.11.0, 2026-11-10, untested in game; see STATUS.md)**
  - MW19 smart objects, each enter / loop / exit plus 4-direction startle reactions:
    - wall lean (`boss_smtobj_lean_wall_l/r`);
    - table / railing lean with a hand (`boss_smtobj_lean_table_hand_l/c/r_30|36`, surface height 30 or 36);
    - sitting (`reb_stl_idle_sit_gunmaintenance / laptop / phone01 / sleeping`, with chair react versions).
  - A settled soldier scans his post with a few traces: a wall at shoulder height, a 30/36 surface, or a
    chair/bench prop. He walks the last bit to the spot and uses it; otherwise smoke / phone / water.
  - Startles go through the existing "caught off guard" system (lean react toward the noise, jump out of the
    chair), slower than a standing guard.
  - For DTW garrisons and checkpoints.
- **Stage 6: searching + starts/stops/turns (built in 0.12.0, 2026-11-11, untested in game)**
  - Search uses the smart-object looks (under / over / up / down / around) aimed at real geometry from
    TIF.Building.
  - Directional start, stop and turn-in-place clips for patrol, alert and combat movement, to cut foot
    sliding everywhere.
- **Stages 7 and 8: done in 0.15.0 (2026-11-11, untested in game) except riot shields (held off by the user).
  Next: civilian AI (shared, for GOPS first).**
- **Stage 7: hit reactions + deaths + downed**
  - Pain by hit location and direction; death clips into ragdoll.
  - MW last-stand crawl and revive clips for the casualty system.
  - Situational deaths: MW19's own (cover / crouch / prone / running / stairs / balcony, by hit location and
    direction).
  - Plus K:\mw19deathanimations: 36 ready-made ValveBiped deaths (`Death_*` standing, `DeathRunning_*`
    running, from a friend). Root motion is in the pelvis. No name overlap with the MW19 extract (checked
    2026-11-11), so they're extra variety for standing and running deaths.
- Stage 3 follow-up: arrivals follow each clip's own root path instead of a straight slide to the node.
- **Stage 8: abilities**
  - Vault/mantle (needs navmesh jump links).
  - Riot shield role (cqb_riot) for SWAT/police.
  - Grenade throws timed to the release notetrack.
  - Flashlight patrols on dark maps.
  - CQB strafe/stairs for room clearing; prone aim (requested 2026-11-11 with grenade throws).
- **Later (game-mode content):**
  - Civilians (civ_*) as one shared module for GOPS / DTW / SWAT.
  - SWAT hostage scenes; surrender / zip-tie.
  - Stealth takedowns (proposal 5) not chosen for now.

**Stage 3 cover + part of Stage 4 (prone, flashbang reactions): built as TIF 0.9.0, 2026-11-11, not run in
game. Details in STATUS.md 0.9.0. Next: CQB strafe set for room clearing, pain reactions, deaths, grenade
throws, prone aim.**

**Stage 3: cover and CQB (original notes)**
- Where to change: `tactics/sv_cover_behave.lua`. `names(npc, cov, kind)` maps roles to GTA clip names:
  idle, peek, intro (step out), outro, reload, switch, blind_in / blind / blind_out, plus enter variants and
  exit. The phase machine is move -> enter -> idle/peek -> aim_in -> aim -> aim_out, plus reload, switch,
  blind and exit. Side "l"/"r" faces along the wall (face_yaw); cover is high or low.
- Plan: give names() an MW branch when `npc.tifHomeHost` is ValveBiped and the clip exists. Add MW cover clips
  to the manifest as a "cover" family:
  - `sdr_com_cover_{left,right}_stand_*` (high: hide idle, lean idle, lean aim 9pt);
  - `sdr_com_cover_crouch_*` and `_{left,right}_crouch_*` (low);
  - arrivals `_arrival_{l,r}_1..9`, exits `_exit_*`, blindfire `_blindfire*`, reloads `_reload01`.
- MW-only improvement: pick the arrival clip from the soldier's approach direction (numpad 1-9 relative to
  the wall) instead of GTA's enter variants.
- Then: MW prone (`sdr_mp_prone_*`, crawl 8-way, down/up), pain/flashbang reactions (Stage 4).
- Original scope:
- Map `sv_cover_behave` roles (intro/outro, idle, peek/lean, aim in/out, blindfire) to MW19 cover.
- Then add directional arrivals/exits (9-way) and the CQB strafe set for room clearing.

**Stage 4: reactions**
- Pain by hit location and direction, death clips into ragdoll, flashbang/stun reactions (SWAT flash ties in),
  prone transitions, laststand/downed for casualty.

**Stage 5: actions**
- Grenade throws (spawn on `grenade_off`), door opens (and Ready or Not kicks/breaches when available), melee,
  traversal/mantle (new TIF ability), stairs.

**Stage 6: weapon pool (optional)**
- MW19 weapon models on `j_gun`, strap bones, sounds, per-class stats in TIF's weapon defs; GTA guns kept for
  GTA-host factions.

**Stage 7: cleanup**
- MW19 as the default host; GTA kept for vehicles (and as fallback). Drop unused GTA clip libraries if the
  addon size matters.

## Risks / open questions
- Sequence limits per model: split into several include models (by family: move, cover, cqb, reactions).
- Aim blending: MW19 aims are additive poses; Source 3x3 blend sequences should cover it, but test early in
  Stage 2.
- Proportions: MW19 clips on the Breen-proportioned host, then playermodels bone-merge. Hands on the gun may
  drift on very different bodies: left-hand IK covers that.
- Surrender has no clean MW19 source.
- Content ownership: MW19 (and Ready or Not) animations are ripped game content: fine locally and with a friend,
  not for Workshop upload (same rule as the faction pack).
