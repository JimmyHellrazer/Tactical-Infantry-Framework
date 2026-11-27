# TIF status

Last updated: 2026-11-06. See ARCHITECTURE.md for the design.

## Phase 0: engine checks (written, not yet run in game)

Nothing here is a soldier yet. Phase 0 answers the questions that decide how Phase 1 is built.

| Command | Checks | Report file (`garrysmod/data/tif/reports/`) |
|---|---|---|
| `tif_selftest` | Dependencies, GTG symbols, the ~60 GTA clips Phase 1-2 need and their sequence indexes, every GTG weapon's clips, faction models (ValveBiped skeleton, retarget map, prone sequences, skins, bodygroups), voice packs, navmesh | `selftest.txt` |
| `tif_spike_layers` | R1: do sequence indexes above 4095 reach the client (main sequence and overlay layers)? R2: how many layers a NextBot holds. Which layer functions exist client-side | `spike_layers.txt` |
| `tif_spike_retarget 10` then `25`, `50` | R3: client frame cost of retargeting faction models onto GTA animations, cost per solve, pose match. Leaves the soldiers standing for a visual check | `cl_spike_retarget.txt` (overwritten each run) |
| `tif_spike_glide` | R5: start and drive a Glide Insurgent with nobody in it: straight, turn, brake | `spike_glide.txt` |
| `tif_voice_test mercenary contact` | Plays a voice line on you (`bf3marine` for the ally pack) | console only |

### How to run

1. Start a **singleplayer** game on a map with open flat ground and a navmesh (for example `gm_construct` or `gm_flatgrass` after `nav_generate`).
2. Open the console and run, in order:
   - `tif_selftest`
   - `tif_spike_layers`
   - `tif_spike_retarget 10`: look at the soldiers for ~10 s while it measures. Then `tif_spike_retarget_clear`, `tif_spike_retarget 25`, and so on. Copy the report file between runs if you want to keep each one (it is overwritten).
   - `tif_spike_glide`: needs ~25 m of clear ground in front of you. `tif_spike_glide gtg_grandtheftgmod_rebel2` tests a GTG car.
3. The reports land in `garrysmod/data/tif/reports/`, where they can be read directly.

Retarget test options: `tif_spike_retarget 10 militia`, `tif_spike_retarget 10 pmc`, or a model path.

### Results, run 1 (2026-11-06, gm_construct, singleplayer)

| Check | Result | What it means |
|---|---|---|
| Self-test | 0 fails. GTG 0.98.0, Glide, wOS prone script, navmesh (2,271 areas) present. Decent Vehicle not installed. All ~60 required GTA clips found. All 168 GTG weapons have their clips. Both voice packs load (mercenary 429 lines, marine 684) | Foundation is in place |
| Prone | Run 1: no model had prone sequences. The wOS version's files are stubs that need the wOS animation extension. **Fixed:** the standalone Prone Mod (`the_prone_mod_1100368137`) is now installed. It ships `anim_extension_prone.mdl` and replacement `m_anm`/`f_anm`/`z_anm`, so all three faction models should now have prone (re-run `tif_selftest` to confirm). It also adds a 9-way prone aim set (`prone_{down,mid,up}_{left,center,right}`) | Prone is unblocked. The old wOS version should be removed: same Lua and model paths |
| R1 main sequence | Every index up to 6,502 reaches the client | No 12-bit limit. The server can set any GTA clip as the main sequence |
| R1 layers | Indexes 2,048 to 6,502 arrived. 10, 1,000 and 2,047 arrived as 0 | Not a bit limit. Cause unknown; `tif_spike_layers2` investigates |
| R2 layer count | 15 layers per NextBot, all 15 valid on the client | Enough for the planned blend (≤ 6) |
| Client layer API | Client has Set/GetLayerSequence/Weight/Cycle (not AddLayeredSequence). Client `SetSequence` sticks | Client-side blending may be possible on server-made slots; `tif_spike_layers2` checks it actually changes the pose |
| R3 retarget | 10 soldiers: +0.89 ms/frame, 39 µs per solve, about 2 ms/frame for 50. Pose match within 0.5 units on all three models | Retarget is cheap. No LOD needed for 50 |
| R5 Glide | Engine starts with no driver, accelerates to 578 u/s, steers 101°. Brake slowed 507 → 50 u/s, then the car reversed | Driving works. Glide treats "brake" as reverse at low speed (like GTA). The driver must switch to handbrake to stop. Test updated |

### Results, run 2 (2026-11-06, gm_construct)

| Check | Result |
|---|---|
| Self-test | 0 fails. Prone sequences present on all three faction models. Old wOS prone mod removed. Remaining warnings: Decent Vehicle not installed; sequences above 4095 (no longer matters) |
| Layer anomaly | Not about sequence numbers. Run 1: the first 3 bots had no layers on the client. Run 2: indexes 10/1000/2047 were fine and the last 2 bots had none (client: layer invalid, weight 0). It is per entity: some NextBots get no layer data on the client at all. Cause still unknown |
| Client layer control | **Works.** Client set `crouch_idle` (#6408) on server-made slots (created at weight 0 or 0.01): head dropped 25.7 units. All 8 slots were valid on the client. When the client stops writing, values revert to the server's within 0.5 s, so the client must write every frame |
| Glide braking | **Passes.** Brake from 560 to under 80 u/s, then handbrake holds it at 2 u/s with no reverse |

### Phase 0 decisions

1. **Animation runs on the client.** Each soldier is a NextBot on the GTG ped. The server creates 8 empty layer slots at spawn and never touches them again. It networks a compact intent (stance, clip ids, start times, aim, cover side/height, flags). Every frame, before bones are built, the client sets the main sequence and the 8 layers from that intent, then retargets the faction model on top.
2. **Server pose for hitboxes** = main sequence only (any index works over the network), set from the same intent. No server layers.
3. **Missing-slot guard.** Because some NextBots got no layer data in both runs, the client checks its slots each second. If they are missing it falls back to main-sequence-only for that soldier and reports it on the debug HUD. The Phase 1 benchmark counts how often this happens; if it is frequent, the next step is re-creating slots on the server for that entity.
4. **Retarget:** no LOD needed up to 50 soldiers (about 2 ms/frame). A distance LOD is still added in Phase 1 as a setting, off by default.
5. **Glide driver:** throttle/steer through seat 1 inputs. To stop: brake above 80 u/s, then handbrake. Never hold "brake" at low speed unless reversing is intended.
6. **Prone** uses the standalone Prone Mod, including its 9-way aim set.

**Phase 0 is complete.** The spike commands stay in for now as regression checks.

## Phase 1: core soldier (written 2026-11-06, NOT yet run in game)

All Lua passes a syntax check. Nothing below has been seen working in game yet.

### What exists

| Area | Files | Notes |
|---|---|---|
| Soldier entity | `entities/tif_soldier*.lua` | NextBot on the GTG ped. Spawnmenu: NPCs → Tactical Infantry (militia = enemy, PMC = ally) |
| Client animation | `tif/npc/cl_body.lua`, `tif/npc/sh_anim.lua` | Every frame in `PreRender`: up to 3 leg clips (relaxed walk/run/sprint, or 8-way aim strafe, or crouch strafe, foot-phase synced) + up to 2 upper-body weapon clips (carry, aim, fire, settle, reload) into the 8 layer slots. Aim pitch via `gtg_aim_pitch`. Faction model retargeted on top, gun bone-merged to `PH_R_Hand`, muzzle flash, small hit flinch, faction model moved onto the GTA ragdoll on death |
| Weapon | `tif/npc/sv_weapon.lua` | Stats from `SWEP.GTG`: damage, rate, falloff, reload time, clip. Bursts and pauses per archetype, aim error (moving, first shots, moving target), friendly-fire check before each burst, reloads |
| Movement | `tif/npc/sv_move.lua` | Navmesh paths with extra cost for areas visible to known threats. Path budget, failed-goal memory, stuck and timeout handling, strafing while aiming |
| Perception | `tif/npc/sv_perception.lua` | Sight: view cone, distance, detection meter (stance, movement, peripheral vision, alertness), budgeted head/chest traces. Hearing: gunfire (suppressed weapons quieter), footsteps (crouch/walk quieter), explosions. Being shot. Contacts keep last known position + direction; uncertainty grows over time. Basic callout to allies within 1,300 units |
| Decisions | `tif/npc/sv_brain.lua` | Unaware (guard post, look around) → suspicious (look, then walk over) → alerted (close in or hold crouched) → engaged (shoot, keep preferred range, shift sideways, clear line of fire, covering fire, reacquire) → searching (last known position, then 3 points biased toward the enemy's last direction) → back to duty, on edge for 90 s |
| Factions | `tif/core/sh_factions.lua` | Own relation table. Players are `pmc` by default (`tif_player_faction`) |
| Voices | `tif/sh_voices.lua` | contact, reloading, moving, kill, pain, death, man down, clear. Per-soldier and per-faction cooldowns. `tif_voice 0` mutes |
| Archetypes | `tif/config/sh_archetypes.lua` | rifleman, assault, support, marksman, leader, guard, breacher: different detection, accuracy, bursts, range, aggression, crouching. **Same behaviour code**; role-specific tactics come later |
| Performance | `tif/core/sv_sched.lua`, `tif/core/sh_prof.lua` | One scheduler, 4 tiers (0.1 / 0.25 / 0.75 / 3 s between thinks), 3 ms per-tick think budget, 60 traces and 3 paths per tick. Profiler on every system |
| Debug | `tif/debug/*` | Overlay (`tif_debug 1`), dev commands, benchmark |

### Test checklist

Use `gm_construct` (it has a navmesh), singleplayer.

1. `tif_selftest`: should still be 0 fails.
2. `tif_debug 1`
3. **One soldier, animation:** `tif_spawn militia 1 rifleman away`. Check:
   - militia model (not the GTA ped), gun in hand
   - relaxed idle and look-around
   - Walk behind it: does it notice you (debug shows "detecting %", then SUSPICIOUS/ENGAGED)?
   - Does it raise the rifle, aim up/down at you, fire bursts, reload?
4. **Detection and hearing:** spawn one facing away. Crouch-walk close (should stay unaware longer), then sprint (footsteps). `tif_noise` at a spot: it should look, then walk over.
5. **Fight:** `tif_spawn pmc 3` next to you, `tif_spawn militia 3` 1,500 units away. Watch range keeping, crouching, sideways shifts, callouts, deaths and ragdolls.
6. **Breaking contact:** get spotted, break line of sight, move away. The debug overlay shows the last known position (orange) and a growing uncertainty ring; they should search there, then return to their posts. `tif_forget` forces this. `tif_reveal` makes all enemies spot you.
7. **Benchmark:** `tif_bench 10`, `tif_bench 25`, `tif_bench 50` (battle), plus `tif_bench 50 patrol` and `tif_bench 50 mixed`. Each writes `bench_<n>_<mode>.txt`.
8. Paste any Lua errors, or tell me what looks wrong (screenshots help).

The benchmark report also answers the Phase 0 open question: whether client layer writes survive until bone setup (the "overwritten %" line) and how often soldiers lose their layer slots.

### Fixes after first in-game test (0.1.1)

- Faction model and gun detached after the soldier left view and came back (noclip out of PVS). They are now re-attached whenever their parent is wrong, and fully rebuilt on the frame the soldier comes back into view.
- First test run produced no benchmark reports; the cause is unknown until the console output is available.

### Fixes after the first gameplay clip (0.1.2)

Seen in the clip and console log (2026-11-06):

| Problem | Cause | Fix |
|---|---|---|
| `tif_bench` never finished, then "already running" forever | `engine.ServerFrameTime` doesn't exist in this GMod build, so every sample errored | Own tick-time measurement; samples wrapped so an error stops the run cleanly; new `tif_bench_stop` |
| Some soldiers hold the rifle one-handed at their side ("pistol / no weapon"), even while firing | Their upper-body layer slots stopped working. The debug HUD showed hundreds of missing-slot frames per second with 4 soldiers. Most likely cause: the client wrote weight 0 to unused slots (and to every slot before the weapon data arrived), and the engine deactivates zero-weight layers, which the client can't undo | Unused slots now keep an invisible weight (0.002) on both server and client. The server re-checks its slots every 2 s. A client that finds a soldier's slots missing asks the server to rebuild and resend them |
| "overwritten 73%" on the HUD | The check ran in the faction model's bone setup, after the GTA ped's bones were already built, so it measured the wrong moment | The check now runs inside the GTA ped's own bone setup |
| Soldiers vanish in a burst of blood instead of leaving a body | The handover to the engine's client-side ragdoll didn't work | The server builds a real ragdoll posed like the soldier at death and tags it with the faction model; every client dresses it. Bodies and dropped guns stay for `tif_corpse_time` (60 s) |
| `killicon not found` warnings | No kill icons | Soldiers use the AR2 icon |

### Benchmark results, 0.1.2 (2026-11-06, gm_construct, singleplayer, battle mode)

| Soldiers | AI per server tick (avg) | Share of 15 ms tick | Sight traces/s | Paths/s | Notes |
|---|---|---|---|---|---|
| 10 | 0.08 ms | 0.5% | 11 | 0.3 | stopped early at 30 s |
| 25 | 0.54 ms | 3.6% | 244 | 3.5 | stopped early at 43 s |
| 50 | 1.41 ms | 9.4% | 651 | 12 | worst second ~4.5 ms/tick; client 23 fps avg (singleplayer: client and server share the machine), retarget 1,541 solves/s at 41.6 µs |

- Layer slots: **no soldier was missing slots at any point** in the 50-soldier run (server rebuilt 0, client requests 0). The one-handed-rifle problem is fixed.
- "Overwritten 12.5%": counted bone builds that happened earlier in the frame than the write, which are discarded anyway. The check now separates those (0.1.3).
- Biggest server cost at 50 is perception (0.53 ms/tick) and the per-tick soldier update (0.65 ms/tick). Both are well inside budget; they are the first places to optimise if needed.

### Fixes, 0.1.3

- **Dead soldiers left their live model standing:** `SetupBones` is client-only, so the corpse code crashed (76 times in the log) before the soldier was removed. Removed the call (the server builds bones on demand). Corpse and weapon drop are now wrapped so the soldier is always hidden and removed even if one of them fails.
- `tif_bench_stop` now still collects the client's numbers before writing the report (the 10 and 25 runs had none because they were stopped early).

### Benchmark results, 0.1.3 (2026-11-06) — Phase 1 closed

| Run | AI per tick | Tick share | Client fps | Overwritten | Missing slots |
|---|---|---|---|---|---|
| 10 battle | 0.07 ms | 0.5% | 153 | 0.1% | none |
| 25 battle | 0.39 ms | 2.6% | 76 | 0.4% | none |
| 50 battle | 0.44 ms | 2.9% | 63 | 2.0% | none |
| 10 patrol | 0.14 ms | 0.9% | 94 | 0.6% | none |

Deaths confirmed working in game. The overwrite threshold is now 5% (a few odd bone builds per second, not visible).

## Phase 2: tactical infantry (written 2026-11-06, NOT yet run in game)

| Area | Files | What it does |
|---|---|---|
| Actions | `tif/npc/sv_action.lua` | Plays one GTA clip as a full-body animation. The server moves the soldier along the clip's root motion (GTG's curves: x forward, y left, yaw CCW, same as Source), or blends it to a target spot. Clients play the same clip from the same start time (NW2 `tif_act`, `tif_act_t`) |
| Cover finding | `tif/tactics/sv_cover.lua` | Candidates from nav areas near the soldier. Traces per candidate: wall facing the threat at waist height, ground, room to stand, high or low (head trace), left/right edges, hidden from the threat, can shoot from the pop-out spot. Scored by: can shoot, preferred range, travel distance, moving toward the enemy (cautious soldiers dislike it), crowding, vehicle (slight penalty). Cached 20 s per grid cell + threat direction, shared by all soldiers. Reservations keep soldiers 56 units apart. Works on walls, props, crates and Glide vehicles (anything solid) |
| Cover fighting | `tif/tactics/sv_cover_behave.lua` | Run in (shooting on the way if aggressive) → GTA enter clip chosen by turn angle → idle / peek loop → pop out (corner lean for high cover, stand up over low cover) with root motion → aim and fire bursts → duck back. Also: cover reload, switch sides (when the threat moves), blindfire when pinned, leave when flanked or seen (re-checked every 1.5 s), then look for new cover |
| Suppression | `tif/tactics/sv_suppression.lua` | Every bullet passing within 90 units of a soldier's chest adds pressure (no traces, vector math). Hits and explosions add more. Effects: worse aim, longer hiding between pop-outs, shorter exposure, blindfire, more likely to take cover, prone when pinned without cover. Rounds snapping past also tell the soldier roughly where the shooter is. Archetype resistance (guard 0.05 .. support 0.65) |
| Prone | `tif/tactics/sv_prone.lua`, prone part of `tif/npc/cl_body.lua` | Get down / get up with the Prone Mod's own animations on the faction model; the gun follows its right hand. Low hull; server hitboxes use a face-down GTA pose. Used when pinned with no cover (by `proneChance`) and by marksmen / support gunners for long-range fights. Gets up when the fight ends, the target gets close, or pressure drops |
| Archetypes | `tif/config/sh_archetypes.lua` | New: `coverUse`, `coverPause`, `coverBurst`, `suppressResist`, `proneChance`, `longRangeProne` |
| Debug | `tif/debug/*` | Suppression bar above heads. `tif_debug_cover 1`: every evaluated cover point (green = can shoot, yellow = hide only, blue = reserved, grey = rejected with the reason; score and reasons up close; edge ticks on top). Cover, suppression and cover-search counts in the HUD and benchmark |

### Phase 2 test commands

| Command | Use |
|---|---|
| `tif_debug 1` + `tif_debug_cover 1` | See cover points, phases ("cover: idle", "cover: aim"...), suppression |
| `tif_cover_test [faction] [count] [archetype]` | Spawn soldiers at your crosshair who already know where you are. Watch cover choice, entering, popping out, ducking back |
| `tif_cover_scan [archetype] [radius]` | Evaluate cover around your crosshair with you as the threat; prints the best point |
| `tif_suppress [0-1]` | Suppress the soldiers you're looking at |
| `tif_prone` | Toggle prone on the soldier you're looking at |
| `tif_spawn militia 3 support` / `marksman` | Long-range prone users |

### Test checklist

1. Find a spot with walls, low walls and crates (gm_construct's building and the crate area work). `tif_debug 1`, `tif_debug_cover 1`.
2. `tif_cover_test militia 1`, ~800 units away, and hide behind something. Does it pick sensible cover, enter with the GTA animation, lean/pop out, fire, duck back?
3. Move around its cover: does it switch sides, and leave when flanked?
4. Shoot near it (or `tif_suppress`): suppression bar rises, it hides longer, blindfires.
5. Open ground, no cover nearby: suppress a `support` soldier until it goes prone. `tif_prone` on any soldier to inspect the prone animation and gun placement.
6. `tif_bench 50` again for the cost of cover.
7. Clips or screenshots of anything odd. Expect tuning: cover enter/exit positions, pop-out facing and the gun in prone are the likeliest to need adjusting.

### Fixes after first Phase 2 test (0.2.1)

| Problem | Cause | Fix |
|---|---|---|
| Soldiers never took cover | Benchmark: 1.9 searches/s but only ~3 traces per search, so nearly every candidate failed the first "wall in front?" trace. Candidates were nav-area centres; the navmesh stops ~16 units short of walls, so centres are usually far from any wall | Probe each area's edge on the threat side (plus both ends on big areas, and the centre of nearby areas for props placed after the navmesh). `tif_cover_scan` and `tif_info` now print why candidates were rejected |
| Prone gun rotated 90° | Grip offset was measured on the GTA ped's hand bone, but the faction model's ValveBiped hand bone is oriented differently | Offset now measured relative to the faction model's own right hand while standing |

### Fix 0.2.2: cover candidates from obstacle rays

0.2.1 still found no cover. `tif_cover_scan` showed why: each search found only 1-6 navmesh areas (gm_construct's areas are huge rectangles), so probing area edges gave a handful of points, mostly on open floor ("no wall" every time).

Candidates now come from the obstacles themselves: an 18-ray waist-height fan (200°) from the soldier toward the threat, plus three 6-ray fans from points to each side and ahead. Every wall, low wall, crate or vehicle a ray hits gives a candidate just in front of it, which the existing checks then judge. Spots off the navmesh are rejected. About 40 traces to find obstacles, up to 110 per search in total. `tif_cover_scan` now also steps back off the wall you aim at.

### 0.2.3

- 0.2.2 found usable cover (`tif_cover_scan`: "high, can shoot, score 2.8"), but one search ran out of trace budget part-way (`budget=6`): a search needs up to 110 traces and shared the 60-per-tick sight budget. Cover searches now have their own budget (`tif_cover_trace_budget` 150 per tick, `tif_cover_search_budget` 2 searches per tick; a soldier that misses out retries on its next think).
- With `tif_debug 1`, every soldier logs its cover roll, each search result (with rejection counts) and every cover phase change to the console, so `console.log` shows exactly where it stops.

### 0.2.4: pathing bug (affected Phase 1 movement too)

The 0.2.3 cover log showed the whole cover loop working (move → enter → idle → aim_in → aim → aim_out → blindfire → reload in cover → left when exposed), but most attempts ended with "can't reach" one think after starting.

Cause: the path cost function rejected ladders/elevators with `if ladder or elevator`. GMod passes NULL objects for "none", and NULL is truthy in Lua, so **every connection between nav areas was treated as a ladder and refused**. Soldiers could only path inside the nav area they stood in. This also limited Phase 1 movement (advancing, searching, returning to post) without any error. Fixed with `IsValid()`, plus the standard `loco:IsAreaTraversable` check.

Also: a cover spot that can't be reached is skipped by that soldier's searches for 30 s (it used to re-pick the same spot every few seconds), and the log says why movement failed.

### 0.2.5: low props rejected as "exposed"

Waist-high props you placed were never used. The "hidden from the threat?" check counted a spot as protected only if the line from the threat's eyes was blocked before 97% of its length. A low prop sits ~20 units in front of the soldier, so on any line longer than ~700 units the hit lands past 97% and the spot was rejected as "exposed". Walls had the same problem at long range. The protection and line-of-fire checks now use absolute distances (blocked at least 6 units before the soldier; line of fire reaches within 40 units of the target). Rounded props (sandbags, barriers) are also accepted at steeper face angles.

### 0.2.6: props as cover

0.2.5 test: soldiers far more mobile (pathing fix), cover used, but only walls. Log totals: 366 candidates, 252 rejected as "no wall", every chosen spot high cover. The candidate was placed in front of the face the ray hit, then tested toward the threat; long walls still block that line, narrow props hit at an angle don't. Candidates are now placed behind the obstacle on the line from the threat (plus one behind each prop's / vehicle's centre), and the "wall in front" check reaches 90 units.

### 0.2.7: rays no longer look past the threat

0.2.6 log: 383 of 404 candidates rejected as "wall angled away", 2 spots chosen. The obstacle rays were 650 units long, so with the player closer than that they passed the player and hit walls behind them. Those walls can't shield anyone from the player; 0.2.5 rejected them as "no wall", 0.2.6 placed the spot inside them. Rays now stop 40 units short of the threat, and a hit only counts if its face is turned away from the threat (the obstacle is between the soldier and the threat).

### 0.2.8: diagnosing

0.2.7 log: far fewer wasted candidates, but most searches found no obstacles at all (`obstacles=0` in ~120 of 155 searches); 9 high-cover spots chosen, 8 entered, 0 low. The arrangement of soldiers, props and player can't be seen from text, so `tif_debug_cover 1` now also draws every search ray (green = obstacle between soldier and threat, orange = obstacle facing the threat, grey = miss). Also fixed a debug overlay error when a dead soldier's entity number was reused by another entity.

### 0.2.9: raised obstacles

Screenshots (0.2.8): a soldier in GTA high cover at a building corner (working). The placed props were a desk and a shipping container, both much closer to the player than to the soldiers. The desk is a slab on legs, open underneath, so the 30-unit-high rays and wall test passed under it. Search rays now alternate between 30 and 44 units high, and the wall test tries 44 if 30 misses. Cover near the enemy is still deliberately scored down ("toward enemy"), most for cautious archetypes; aggressive ones (assault, breacher) accept it more.

### 0.2.10

- 0.2.9 log: 98 of 135 candidates usable (was 34 of 85), 23 cover picks, 12 entered, firing from cover. All picks high cover: in the screenshot the props stood on the raised platform next to the player, i.e. the player's cover.
- New `tif_cover_course [faction] [count] [distance]`: 4 frozen waist-high props (concrete barriers, crates) in a row 350 units in front of new soldiers who know where you are, so low cover can be tested on any map.
- GMod's AI switches now apply: `ai_disabled` (Disable Thinking) freezes soldiers like `tif_ai_disabled`; `ai_ignoreplayers` (Ignore Players) makes players invisible, inaudible and non-suppressing to soldiers, and drops existing knowledge of them without a "kill" callout.

### 0.2.10 results and 0.2.11

The 13 low-cover uses were at the construct building's half walls (map brushes); the course props were still not used. Two causes:
- `tif_cover_course` spawned soldiers anywhere within 350 units of their spawn point, and the props were only 350 units in front of it, so many soldiers stood beside or in front of the props.
- A prop only became a candidate if one of ~36 search rays happened to hit it; a narrow crate between two rays was missed.

0.2.11: the course spawns soldiers within 110 units, well behind the props. Cover searches now also look up nearby props and Glide vehicles directly (`ents.FindInSphere`, no traces; props at least 28 tall and 20 wide), put a candidate behind each as seen from the threat, and evaluate those first. The search log shows `props=N`.

Still to confirm visually: low-cover animation quality, prone gun position (0.2.1 fix), blindfire, suppression, and the AI toggles.

### 0.2.12: cover animation diagnosis

Clip review (6:14 pm clip): blindfire from low cover and the corner pop-out at a pillar look right. Soldiers labelled "cover: peek" at a low window wall stood upright facing the wall (low peek should be crouched side-on), and one in "cover: reload" was in a walking pose; i.e. in some phases the drawn pose isn't the GTA cover clip. The overlay now shows, per soldier, the server's cover clip and what the client actually has in slot 0 (sequence name, weight, stance, mode) to find where they diverge.

Phase 2 bench (0.2.0, 50 soldiers): AI 1.28 ms/tick (8.6%). Suppression 0.12 ms/tick. Client 2 fps in that run, most likely because the game window wasn't focused (only 34 retarget solves/s were drawn); needs a re-run.

### 0.3.0 cover fixes (from the 7:57 pm clip)

- The new overlay showed the client playing the right clips. Low-cover "peek" is GTA's look-over-the-top pose (`cov2_low_idle_l_peek`, upright), and the cover loop held it the whole time the target was lost, so soldiers stood exposed above low walls. Low cover now stays crouched and only peeks for ~1 s every 3-5 s.
- Leaving cover after a fight snapped straight to walking. Calm exits now play GTA's step-out clip (`cov2_exit_*`) first; urgent exits (flanked, exposed) still leave at once.

## Phase 3: squads (started 2026-11-06, NOT yet run in game)

### Done in 0.3.0

| Area | What |
|---|---|
| Squads (`tif/squad/sv_squad.lua`) | Leader (soldier or player), up to 12 members, standing order, formation. Leader killed: the "leader" archetype takes over, else the healthiest member; an advance becomes a hold. A player leader who dies hands over to a soldier, who holds position |
| Shared knowledge | Squad radio: what any member sees, hears or is hit by reaches the others ~0.3-0.9 s later as a last known position (source "squad"). Replaces the Phase 1 radius callout within the squad (the radius callout still reaches other squads) |
| Orders | free (Phase 1-2 behaviour), hold (line formation around a point, fights without chasing past 550 units), follow (formation on the leader, fights within 900 units of it), regroup (tight formation, then follow), advance (leader walks to the point, squad follows in formation, then holds there) |
| Formations | wedge, column, line, file (two files) |
| Leash | Any movement in a fight (advancing, searching, cover) is clamped to the hold point / leader distance; cover outside the leash is rejected |
| Spawning | Groups spawned together are one squad. Single spawn-menu soldiers join a nearby same-faction squad (within 700 units) or start their own |
| Debug | Line from each soldier to its leader (colour per squad), and "squad N, order, LEADER / follows <player>" in the label |

### Commands

| Command | Use |
|---|---|
| `tif_spawn_squad <faction> [size] [hold|follow|free] [me|away|random]` | Mixed squad: leader, rifleman, support, rifleman, assault, marksman, ... |
| `tif_follow [radius]` | Allied (PMC) soldiers near you join your squad and follow you |
| `tif_order <hold|follow|regroup|advance|free>` | Order your squad, or the squad of the soldier you look at. hold/advance use your crosshair |
| `tif_formation <wedge|column|line|file>` | Formation of your squad or the looked-at squad |
| `tif_dismiss` | Your squad stops following you and holds where it is |

Suggested binds: `bind f "tif_order hold"`, `bind g "tif_order follow"`, `bind h "tif_order regroup"`.

### Test checklist

1. `tif_spawn_squad pmc 5 free away` in front of you, then `tif_follow`. Walk, run, turn: do they keep formation behind you? Try `tif_formation column` and `line`.
2. `tif_order hold` at a spot, walk away: they stay. `tif_order follow`: they come back.
3. `tif_spawn_squad militia 6` far away (with `ai_ignoreplayers 0`): when one militia soldier sees your squad, do the others react together (squad radio)? Kill the militia leader: does another take over (label says LEADER)?
4. A firefight with your squad following: do they fight and use cover without running off past ~900 units?

0.3.0 test log: no errors; squads, `tif_follow`, hold/follow orders and enemy squad spawning all ran. Prop lookup works (`props=1` in searches).

### 0.3.1: squad tactics (`tif/squad/sv_squad_tactics.lua`)

Once a second per squad in a fight:

| Plan | When | What |
|---|---|---|
| hold | hold order, player-led squad, or fewer than 3 soldiers | Everyone is base of fire; no maneuvering |
| bound | default when the enemy is further than the leader's preferred minimum range | Two groups leapfrog: one moves ~450 units toward the enemy (cover-to-cover, cover searched around that goal), the other is base of fire. When half the movers arrive (or 14 s pass) they swap |
| flank | enemy held one spot for 8 s, squad of 4+, more than 500 units away (25 s cooldown) | The maneuver group goes to a point ~650 units to one side of the enemy while the rest pin it; then everyone fights from where they are |
| engage | close enough, or after a flank | Everyone fights from current positions for 10 s, then re-plans |

Roles: support, marksman and leader are always base of fire; assault and breacher always maneuver; riflemen are split. Base of fire pops out of cover more often and keeps firing at the enemy's last known position for up to 6 s after losing sight (suppressive fire, "suppressing" callout). Maneuvering soldiers break cover that's far from their goal and move, shooting on the way when they see the enemy ("moving" / "cover me").

Debug: label shows "plan: bound role: maneuver"; maneuver goals drawn as magenta lines and rings; with `tif_debug 1` the console logs each squad's plan changes and bound swaps.

Test: `tif_spawn_squad militia 6` ~1500 units away facing you, take cover and shoot back now and then (or set up a PMC squad on hold as their target). Watch the groups leapfrog, then stay in one spot for 8+ s and see if some go round the side.

### 0.3.2: bound fixes, withdraw, order menu

0.3.1 log: bounds swapped every second and the threat distance jumped between enemies. Fixes:
- The squad sticks with one enemy until it's dead or unseen for 6 s.
- A bound lasts at least 3 s; movers count as arrived within 130 units of the goal, or once settled in cover within 420 units of it; the swap needs 60% arrived.
- Maneuvering soldiers in the open stop moving 100 units from the goal (was 200).

Withdraw (AI-led squads only): when the squad is down to half its peak size (peak 3+) and outnumbered by enemies seen in the last 10 s, or its average suppression is above 0.7, everyone falls back ~700 units away from the enemy ("retreat" callout, mercenary pack only). When 60% get there (or after 18 s) the squad gets a hold order there, facing the enemy. At most once a minute. Logged with `tif_debug 1`.

Order menu (`tif/debug/cl_menu.lua`): `bind <key> +tif_menu` (hold the key, click) or `tif_menu` (stays open until a click). Follow / hold / advance / regroup / free, the four formations, take command of nearby allies, dismiss. Buttons run the console commands, so hold/advance use your crosshair.

### 0.3.3: fixes from the 0.3.2 test

0.3.2 log: no TIF errors. Bounds lasted several seconds each with no flip-flopping (6 swaps over the fight). Two problems:
- One soldier entered the same high cover three times and left each time as "exposed". The cover cache key only stores the rough direction to the threat (22.5° slices, which at 2500 units is ~1000 units wide), so after the player moved, a spot judged against the old position was reused. Cached spots are now reused only if the threat is within max(100, 4% of the distance) of where it was judged from, and a spot left as exposed or flanked is dropped from the cache.
- The squad went from 6 to 2 against a lone player without withdrawing, because a single enemy never outnumbers it. A squad down to a third of its peak now withdraws whatever the odds.

### 0.3.4: fixes from the 0.3.3 test

0.3.3 log: no TIF errors.
- gm_construct: withdraw worked. At 2/6 left the squad fell back, then held about 10 s later. Soldiers used high cover, including peek and aim.
- testroom2_extended has no navmesh ("Failed to load .nav file"). Every cover spot was rejected as off navmesh, and the withdraw found no navmesh point to fall back to. Spawn commands now warn in chat and console when the map has no navmesh.
- After deaths, one bound ran as "4 move, 0 cover". The groups are now re-split whenever one is empty or the squad size changed. A squad of all one kind (e.g. all support) is split evenly, so it can still bound.

### 0.3.5: fixes from the first tif_range fight

Log: no TIF errors. 6 squads; 43 cover entries with full peek/aim, reload and blindfire cycles; 128 searches saw props. Bounding, a flank and three withdrawals all ran.
- **Legs during cover reloads and peeks:** GTA's cover reloads (`cover@weapon@` clips) and peeks are upper-body-only, but they were played as full-body clips, so the legs showed the clip's default pose. These actions now name a base clip (the cover idle, NW2 `tif_act_base`): the client keeps the base on the legs and plays the action through the upper-body slots. Standing loops (cover idle, peek) run on one clock per soldier, so swapping between them doesn't restart the legs.
- **Lockstep slow aim-walk, no gun-down running:** every combat move used the aim mode, and advance/reacquire/close-in all used the slow aimed walk. Now each soldier picks its own gait for 3-7 s at a time:
  - advancing far (> 1500 units): mostly run;
  - advancing at mid range: mostly an aimed jog;
  - advancing close: aimed walk or jog;
  - reacquire: aimed walk or jog, by aggression;
  - maneuvers with nothing in sight: run or sprint.
  Any run or sprint without shooting switches to the relaxed carry (gun down, run legs). That covers runs to cover, maneuvers and long advances.
- **Withdraw:** suppression alone (now > 0.8) only triggers it for a squad that has lost someone or is outnumbered; it fired twice for a full PMC squad. The hold after a withdraw now lasts 30 s, then the previous order returns (unless a new order was given).

### Test map: tif_range

Generated from `mapsrc/make_tif_range.py` and built with `mapsrc/build_tif_range.ps1` (vbsp++/vvis++/vrad++; `-Fast` for a quick build) into `maps/tif_range.bsp`. It's plain blocks with dev and HL2 textures and builds in ~2 s. Compiles with no leaks and passes BSP validation; not yet loaded in game.
- **Field** (south-west): low walls, tall walls, angled walls, L-corners, crates and stacks, raised tables open underneath, a roofless house with door and window gaps, physics props (barriers, crates, drums, counter, table).
- **Lane** (north): ~7800 units long, walled, cover along both sides and the middle, three entries in its south wall.
- **Compound** (south-east): walled, gate on the north, side door on the west. Barracks with two rooms, HQ with a corridor and two rooms (doors, windows, interior lights). Guard tower with stairs, sandbags at the gate, crates and props in the yard.
- **Roads**: a loop round the map, a middle road and a road to the gate (`concretefloor028a`).
- **Spawn**: a raised platform with stairs between the field and the compound, facing the field.

First load: `map tif_range`, then `nav_generate` once (saves `maps/tif_range.nav`).

### Still to do in Phase 3

Leader voice orders, and tuning from tests.

### Known gaps in Phase 2

- No moving along cover (the `cov2_*_walk` clips) or cover-to-cover dashes as one motion; soldiers leave cover, run, and enter the next.
- Leaving cover has no exit clip yet (it crossfades into running).
- Grenades are not in yet (clips exist: `cwgr_*`).
- Prone soldiers can't aim beyond the Prone Mod's idle pose plus body pitch; the 9-way aim set isn't wired up yet.
- Suppression doesn't check walls: a bullet passing close on the other side of a wall still counts.

### Known gaps in Phase 1 (by design, later phases)

- No cover use yet (Phase 2): soldiers fight from where they stand, crouch and shift sideways.
- No suppression reactions, prone or grenades (Phase 2).
- No squads, formations or orders. Allies don't follow the player (Phase 3). Callouts are a simple radius.
- No patrol routes; "duty" means holding the spawn spot (Phase 4).
- Hit reactions are a small procedural flinch. No stagger animations exist in the GTA library.
- Server hitboxes use one pose per stance (standing idle, aim idle, crouch). Exact hit positions on moving soldiers are approximate.
- Bullets start from the shoulder position on the server. The muzzle flash and tracers are visual only.
- Darkness doesn't affect detection yet.

## Phase 4: bases and search (started 2026-11-07, 0.4.0, NOT yet run in game)

Phase 3 closed without leader voice orders: there's no good line set for them yet (only a few Insurgency lines).

### Bases (`tif/encounter/sv_base.lua`)

A base has a centre, a radius, a faction and a garrison. Each soldier has a job (`job:` line in the debug label):

| Job | What it does |
|---|---|
| post | A guard at a fixed spot and facing. All posts form one squad that shares what it sees but never maneuvers; each guard fights within 420 units of its post and walks back after. |
| reserve | A quick-reaction force waiting at its spots (barracks). It sits still until the alarm, then is sent out and bounds toward the enemy like any squad. After the all-clear it returns to its spots. |
| patrol | A squad per route, in file, walking the loop and pausing 2-5 s at each point. It fights whatever it meets, then picks the route up at the nearest point. |
| reinforcement | One squad, spawned during a big alarm at the base's reinforcement point. It's called when the garrison is down to 60% or the alarm has lasted 45 s, arrives 12-20 s later, and only spawns where no player is within 1500 units or has a view of the spot. |

Alert levels:

| Level | Entered when | Effect |
|---|---|---|
| calm | start; 90 s of quiet in alert | routine (relaxed carry) |
| alert | a soldier is suspicious or in any fight, or a soldier died | everyone rifles up; drops to calm after 90 s with nobody suspicious, alerted, fighting or searching |
| alarm | a soldier is fighting (after a 1.5-3 s radio delay; the reporter calls for backup) | every squad in the base gets the enemy's position over the base radio, the reserve goes out, reinforcements may be called; after 25 s with nobody fighting and nothing new: back to alert, and the reserve (or the reinforcements) sweeps the last known position |

### Squad search (`tif/tactics/sv_search.lua`)

When squad members lose contact, the squad splits the search instead of everyone walking to the same spots:
- **Overwatch** (squads of 3+): one member, a marksman, support or leader by preference, takes a spot 350-700 units out on the squad's side that can see the last known position. It crouches there and sweeps the area.
- **Searchers:** the rest get separate nav points round the last known position, at least 220 units apart and favouring the direction the enemy was heading. The first searcher also checks the position itself.

New information (a shot heard, a sighting) restarts the plan around the new position. Searchers move at their own pace (aimed walk or jog).

Also:
- Alerted soldiers now follow maneuver goals (e.g. a reserve sent toward a heard enemy) at a run, gun down.
- After a withdraw, a squad's previous order is restored whole (so patrols keep their route).

### tif_range preset: "compound"

| Group | Size | Where |
|---|---|---|
| Posts | 6 | tower (marksman), 2 at the gate behind the sandbags, west side door, HQ west door, yard |
| Reserve | 6 | barracks, both rooms |
| Patrols | 2 x 3 | one inside the walls round the yard, one outside along the roads |
| Reinforcements | 6 | south-east corner of the road loop |

18 soldiers to start.

### Commands

| Command | |
|---|---|
| `tif_base_garrison [name]` | spawn a base (no name: the map's first preset, `compound` on tif_range) |
| `tif_base_info` / `tif_base_clear` / `tif_base_list` | status, remove, list presets and saved bases |
| `tif_base_level <calm\|alert\|alarm>` | force a level (`alarm` points the base at you) |
| `tif_base_new <name> [faction] [radius]`, `tif_base_post [post\|reserve] [arch]`, `tif_base_route [size]`, `tif_base_point`, `tif_base_reinforce [size]`, `tif_base_undo`, `tif_base_save` | build a base on any map, standing where things go; saved to `data/tif/bases/<map>_<name>.json` |

Overlay (`tif_debug 1`): base ring coloured by level, with level, alive count and reinforcement state over the centre. Posts are drawn red, reserve spots orange, routes cyan, the reinforcement point purple, and the last known enemy position as a white cross. With `tif_debug 1` the console logs level changes, the reserve going out, reinforcements and search plans.

### Test checklist (tif_range)

1. `tif_base_garrison`, then walk around with `tif_debug 1`: guards on posts facing out, the reserve in the barracks, both patrols walking their loops.
2. Fire a shot near the compound without being seen: it should go to ALERT (rifles up), then back to CALM after ~90 s.
3. Get spotted by a gate guard: ALARM after a couple of seconds; the reserve leaves the barracks and moves on you; the outside patrol joins.
4. Kill several: reinforcements are called and arrive from the south-east corner (if you're not watching it).
5. Break contact (run and hide): the squads split their search (overwatch + searchers in the log); after ~25 s the base drops to ALERT and the reserve sweeps; later CALM and everyone goes back to their jobs.

Phase 4 test (0.4.0, tif_range): worked well. No TIF errors; ALERT → ALARM → reserve sent out ran as designed. One issue, present since Phase 1: soldiers walking into each other's lines of fire and shooting each other. Fixed in 0.5.0 (below).

## Phase 5: buildings and room clearing (started 2026-11-07, 0.5.0, NOT yet run in game)

### Friendly fire fix

- The check ran once per burst and was a single ray down the exact aim line, so allies walking in mid-burst, or standing beside the line in the spread, got hit. It now runs **before every shot**, as a cone matching the soldier's current spread (0.7 of the max angle) plus a body width, reaching 500 units past the aim point (misses carry on). It's pure geometry, with no traces. Blindfire's wide spread makes its cone wide too.
- A friendly in the cone: the shooter holds fire and drops to **low ready** (relaxed carry, gun down) for 0.8-1.4 s, then sidesteps away from that friendly (the sidestep used to pick a random side). Label: "[friendly in line]".
- Paths avoid crossing in front of squadmates who are shooting: nav areas inside their firing lanes (a 10° wedge plus 40 units) cost 3x.

### Buildings (`tif/building/sv_building.lua`)

| Thing | How it's found |
|---|---|
| indoor | a nav area with a ceiling (trace up 420 hits non-sky), cached per area |
| doorway | a door entity (`prop_door_rotating`, `func_door(_rotating)`), or a nav connection through a gap 24-100 units wide with walls on both sides at waist height and a lintel above, with at least one indoor side. Each connection is traced once per map. The sides are the nav areas 72 units either side (clear of the small area the navmesh puts in door gaps). |
| room | indoor nav areas joined without crossing a doorway (flood fill, up to 60 areas) |
| stack slots | outside the doorway on both sides along the wall, alternating, 34 apart; checked against the navmesh and a hull trace |
| entry points | the two corners beside the door inside (found by tracing along the wall) and two deeper points, kept inside the room |

### Room clearing (`tif/building/sv_clear.lua`)

- **Team:** up to 4 entry members (assault/breacher first, then riflemen, leader). Support, marksman and extras stay outside, crouched, covering the first doorway.
- **stack:** members take the slots, crouched, aiming at the door. Entry goes when all are in place (or after 10 s with someone there) and nobody sees an enemy. A closed door is opened first; if it won't open the clear is abandoned.
- **entry:** one member goes in every 0.6 s. The 1st crosses to the far corner, the 2nd hooks to the other corner, the 3rd and 4th go deeper.
- **hold:** members face into the room. After 1.5 s with no enemy seen, the room is clear ("clear" callout). If it was the target room, the clear is done. Otherwise the team goes to the next doorway out of this room toward the target, stacking from the inside.
- Enemies seen at any point are shot from where the soldier stands, with no cover search indoors. The clear ends if the team dies, on timeout (150 s), or on any new order. The previous order then comes back (a player's squad goes back to following).
- **Starts when:**
  - the player orders it: `tif_order clear` at the crosshair, or "Clear building at crosshair" in the order menu;
  - a squad of 3+ loses contact and the last known position is indoors (instead of the normal search).
- The squad tactics (bounding, flanking, withdraw) pause while a squad is clearing.

### tif_range: two-storey building

A new building at x 0..560, y -600..240, north of the spawn platform:
- **Ground floor:** two rooms on the west, a stair hall on the east, three outside doors and two interior doors.
- **Upper floor:** reached by stairs on the east side, through a hole in the floor. It has two rooms joined by a door, and windows all round.

The barracks and HQ in the compound work too.

### Commands and overlay

- `tif_doors [radius]`: finds doorways near the crosshair and draws them for 60 s. It reports exterior/interior counts, scan time and the crosshair's room.
- Overlay (`tif_debug 1`):
  - doorways: a bar across the opening plus an arrow pointing indoors, green for exterior, blue for interior;
  - stack slots (yellow), entry points (magenta), the room being cleared (orange outlines), the target and phase.
- The console logs `[cqb]` steps.

### Test checklist (tif_range, run nav_generate again: the map changed)

1. `tif_doors` while looking at the new building: about 3 exterior and 3-4 interior doorways, arrows pointing inside.
2. `tif_spawn militia 2` inside an upstairs room. Get a PMC squad (`tif_spawn_squad pmc 6 follow`, or `tif_follow` with allies), look at the building, `tif_order clear`: the team stacks, enters, clears room by room up the stairs, then follows you again.
3. Hide in the building from a militia squad: they lose you, then stack and clear instead of searching.
4. Friendly fire: a big fight (`tif_spawn_squad` both sides). Far fewer team kills; "[friendly in line]" labels appear while someone waits for a clear line.

### 0.5.1: fixes from the first clearing test

0.5.0 test: no TIF errors. The squad gathered, stacked, entered and spread through rooms, but it was a bit slow and never went upstairs. From the log:
- **Upstairs never reached:**
  - The stairs joined the stair hall to the upper floor with no doorway in between, so the room flood made them one "room". The team took its spots downstairs and called the whole thing clear.
  - The clear also stopped at the "target room" (the crosshair's room).

  Fixes: rooms now stay on one floor (within 40 units of the start height). Where the flood meets stairs, it follows them to the other floor and records a **stair link**, which works like a doorway. The team stacks at the foot of the stairs, goes up one at a time and spreads through the room at the top (the reverse when going down). A clear now covers the **whole building**, nearest the target first, going back through cleared rooms to any uncleared one, up to 10 rooms.
- **Slow:**
  - Entries started on the 10 s stack timeout with 1 of 4 in place, and soldiers walked to their slots at aim-walk speed.
  - Now: jog to far slots; a 6 s stack timeout; doorways inside the building go once half the team is stacked; 0.45 s between entries (was 0.6); a 5 s max wait at the points (was 8); 1 s of quiet to call a room clear (was 1.5).
- **"No way in found" on the north side:** doorway detection only tried one point per nav connection (between the closest points of the two areas), which misses doorways on long shared edges. It now samples along the whole shared edge (up to 24 points, each connection still traced once per map). To stop narrow corridors counting as doorways, the lintel must be lower than the ceiling (or sky) on at least one side.

0.5.1 test: a full building clear. All 5 rooms on both floors, upstairs via the stair link, then back down for the one missed room ("building clear"). No TIF errors. Phase 5 closed.

## Phase 6: vehicles (started 2026-11-07, 0.6.0, NOT yet run in game)

### Occupancy (`tif/vehicle/sv_vehicle.lua`)

- A soldier claims seat n, is **parented to the vehicle** at the GTA seat position (GTGData, via `TIF.GTG.SeatPose`) and loops GTG's seat clip (driver: `steer_no_lean`, passenger: `sit`). It's switched to MOVETYPE_NONE and COLLISION_GROUP_IN_VEHICLE. Vehicles without GTA seat data (e.g. the Glide base pack's `gtav_*`): the soldier sits on the Glide seat pod, with a guessed height.
- **Getting in:**
  1. Run or walk to the GTA stand point for the seat (or Glide's exit position).
  2. Play `get_in` while sliding into the seat.
  3. Sit.
  It gives up after 25 s, or if the vehicle moves.
- **Getting out:** `get_out` (or `jump_out` if the vehicle is still moving) from the seat to the stand point, ending facing away. It doesn't collide until the clip ends, so it can't get stuck in the bodywork. Combat dismounts play 1.35x faster.
- Players can't take a seat a soldier holds. If the vehicle **explodes**, everyone inside dies; if it's removed, they're dropped.
- Riding soldiers still see and hear (that's what triggers dismounts). No drive-by shooting yet.

### Driver (`tif/vehicle/sv_driver.lua`)

- **Steering:** pure pursuit on the route, with a look-ahead of 260-900 units growing with speed.
- **Speed:** cruise is 520 u/s, slowed for the turn ahead and near the end.
- **Obstacles:** a hull probe ahead brakes for anything in the way; a wall for 3 s makes it back off.
- **Stuck** (throttle on, not moving for 2.5 s): reverse with opposite lock for 1.5 s.
- **Arrival:** within 220 units, handbrake on.
- Inputs go through `TIF.Glide.Drive` (the Phase 0 test passed: throttle, steer, brake, handbrake).

### Routes (`tif/vehicle/sv_routes.lua`)

1. **Decent Vehicle** waypoints (`TIF.DV.Route`), when the map has them.
2. **roads:** A* over the navmesh for vehicles. Indoor areas and narrow areas a 110-wide box doesn't fit are left out, as are steps of 40+ units. Road surfaces (texture matching road/asphalt/tarmac/street/highway/pavement/freeway, plus per-map extras: tif_range's `concretefloor028a`) cost 1x; other ground 3x. The path is then smoothed with hull traces.
3. **direct:** a straight line, under 1500 units only.

### Mounted squads (`tif/vehicle/sv_mounted.lua`)

Phases: boarding, ready, driving, stopping, dismounting, dismounted.
- **Boarding:** the driver is a rifleman or assault soldier (never the leader); the leader takes seat 2.
- **Contact while driving or waiting:** a rider sees an enemy, or knows of one within 1500 units. The driver brakes; once slow (or after 4 s), passengers get out one every 0.35 s, then the driver.
- **On foot:** the squad's previous order comes back and normal tactics take over. Vehicles already count as cover.
- Squad tactics pause while a squad is riding.

### Bases

- Definitions can have `vpatrols` (a vehicle class, crew size and a loop of points). The vehicle spawns at the first point with its crew beside it; they mount and drive the loop.
- On the all-clear, a vehicle patrol that got out to fight climbs back in and carries on.
- tif_range "compound" now has an Insurgent with 4 militia on the outer road loop.
- Saved base files don't store vehicle patrols yet; only presets do.

### Commands and overlay

| Command | |
|---|---|
| `tif_vehicle [class]` | spawn a Glide vehicle at the crosshair (default `gtav_insurgent`; tells you whether it has GTA seat data) |
| `tif_mount` | the looked-at / led / nearest squad boards the looked-at or nearest vehicle |
| `tif_drive [stay]` | the mounted squad drives to the crosshair and gets out (or stays in) |
| `tif_vpatrol` | it drives back and forth between where it is and the crosshair |
| `tif_dismount` | everyone out |
| `tif_roads [radius]` | road (yellow) / drivable (grey) / not drivable (red) nav areas, drawn for 30 s |

Overlay: each vehicle's seats, route label and source, drive state and speed vs target; the route (cyan, done part dimmed) and the pursuit target (white line). The console logs `[vehicle]` steps with `tif_debug 1`.

### Unknowns to check first

- How a NextBot behaves parented to a moving Glide vehicle: it should be carried smoothly, without jitter or falling through.
- Seat position and pose on `gtav_insurgent` (no GTA seat data, sits on the pods) vs a GTG car like `gtg_grandtheftgmod_baller2` (GTA seat data and get-in/out clips).
- Whether bullets hit soldiers riding inside (COLLISION_GROUP_IN_VEHICLE).

### Test checklist (tif_range)

1. `tif_vehicle gtg_grandtheftgmod_baller2` and `tif_vehicle` (Insurgent). `tif_spawn_squad pmc 4` nearby, look at a vehicle, `tif_mount`: they walk to the doors, play get-in and sit.
2. `tif_roads` near the roads: the ring road yellow, grass grey, buildings red.
3. `tif_drive` with your crosshair down the road: they follow the road (cyan route), slow for corners and get out at the end.
4. `tif_base_garrison`: the Insurgent patrol drives the ring road. Get seen by it: it stops, everyone gets out and fights. After the all-clear (~2 min of quiet) they get back in and carry on.

### 0.6.1: boarding fixes and door entry (from the first vehicle test)

0.6.0 test: driving without Decent Vehicle worked in simple cases. Boarding problems:
- Soldiers sometimes didn't turn while walking to the vehicle. An old look target (e.g. from formation) was kept; boarding now clears it.
- They got stuck on each other or all went to one side, and 2 of 4 sat while the other 2 stood about (needed the physgun). In the log, a second `tif_mount` on the Baller gave "1 of 4": seats were matched to soldiers by list position, so soldiers already seated didn't count, and anyone whose matching seat was taken got none. That squad then drove off with one man in it.

Fixes:
- **Seat assignment:**
  - Soldiers already seated keep their seats; the driver's seat goes to the most driver-like non-leader.
  - Everyone else takes the free seat whose door is nearest to them.
  - Failed boardings are retried on another free seat (up to 3 times), and every failure is logged with its reason (`[vehicle] #N boarding seat S failed: ...`).
  - After 20 s, anyone within 260 units of the vehicle is put straight into a free seat.
- **No body-blocking:** soldiers boarding, seated or getting out use COLLISION_GROUP_DEBRIS. They don't block each other or the vehicle, and bullets still hit them (`MASK_SHOT` includes debris; this also replaces COLLISION_GROUP_IN_VEHICLE for riders).
- **One at a time per door:** anyone heading for a door that another soldier is opening or climbing through waits 90 units back.
- **GTG door entry,** for GTG cars with entry data:
  1. walk to the door's stand point, facing it;
  2. `d_open_out`: the car door swings open (GTG's networked door ratio, `gtg_vd`, written every tick in step with the clip's Door tags, so every client sees it);
  3. `get_in` on the clip's own root motion, lifted smoothly from the ground to seat height;
  4. sit, then `d_close_in` (door shuts), then the seat loop.
  Getting out: `get_out` (the door opens during it), then `d_close_out` (the door shuts behind). Combat dismounts are 1.35x faster, skip the close and leave the doors open; a vehicle still moving gets `jump_out`. GTG's own door record is kept in step, so a player using the door sees the same state. Doors that are broken off are skipped.

### 0.6.2: seat fit and doors (from the 0.6.1 screenshots)

0.6.1 test: boarding otherwise fine. Two visual problems:
- **Soldiers sit a little too high in every seat, and the driver a bit too far back.** The seat position is exactly the one GTG uses for players (GTA seat pos minus the 1 m root), so the difference comes from players vs our retargeted NextBots. GTG itself drops generic seats 6 units (`seat_drop`). New live-tunable cvars; seated soldiers re-fit within a second when they change:
  - `tif_seat_drop` (default 6): how much lower than the GTA seat position soldiers sit;
  - `tif_seat_forward` (default 0): shift every seat forward or back;
  - `tif_driver_forward` (default 6): extra forward shift for the driver.
- **Doors only went slightly ajar.** I was writing GTG's shared door value (`gtg_vd`). When no player is animating a door, GTG hands that value to its deformation "swing" system, which only nudges the door. Soldiers' doors now use their own value (NW2 float `tif_door<entry>`). Clients rotate the door bones exactly as GTG does for a player's door: the same bones and children, the door's axis and its full open angle. GTG's own door state is no longer touched.

### 0.6.3: gun sounds, secondary weapons, RPGs, drive-bys

**Gun sounds:** soldiers played each GTG weapon definition's `sound` field, which for GTG guns is `Weapon_AR2.Single` (and the RPG's `Weapon_RPG.Single`). GTG's real GTA gun audio goes through `GTG.Sound.Shot`, which needs a weapon and an owner, so each soldier now gets a small stand-in for both (`TIF.GTG.GunShot`). Soldiers get the same GTA samples, near/far bands and automatic-burst handling players get. The old sound is only used for guns with no GTA audio.

**Loadouts** (`config/sh_content.lua`, `TIF.Loadout`): per faction and archetype, a primary list and a secondary list; one of each is picked at spawn. Each weapon keeps its own magazine.

| Archetype | Militia | PMC |
|---|---|---|
| default | assault / compact rifle + pistol | carbine / special carbine + combat pistol |
| support | MG + pistol | combat MG + combat pistol |
| marksman | marksman rifle + pistol | marksman rifle (mk2) + combat pistol |
| **rpg** (new: AT Gunner) | RPG + Micro SMG | RPG + Micro SMG |
| breacher | pump shotgun + pistol | combat shotgun + combat pistol |

The squad mix now has an AT gunner (7th soldier), and so do reinforcements.

**Switching** (`TIF.Weapon.Choose` / `Switch`): a switch takes 0.65 s, the gun changes halfway, and a reload in progress is dropped. At most one switch every 3 s.
- Marksmen (`secondaryBelow` 450) and AT gunners (500) draw the sidearm when the enemy is closer than that, and when room clearing. They go back to the primary past 1.4x that distance.
- Anyone whose primary runs dry with an enemy within 600 draws the sidearm instead of reloading; a dry sidearm with a loaded primary means switching back. Everyone else returns to the primary past 700 units or after 3 s without firing.
- Out of a fight, everyone carries the primary.

**RPGs:** launchers fire GTG's own projectile (`GTG.SpawnProjectile`): the rocket model, trail, acceleration and the `ROCKET` explosion. Never at targets within 320 units.

**Drive-bys** (`tif_driveby 1`):
- **Who:** passengers in seats that have a GTG drive-by set for a right hand (the gun is held in the right hand). That's the front passenger and the rear driver's side on standard cars; the rear passenger's side and van passenger use the left hand, so they don't shoot yet. The target must be visible within 2200 units.
- **Gun:** they switch to the secondary if it's a GTA drive-by gun (pistols, Micro / Mini SMG...), else use the primary if it is.
- **Animation:** GTG's `sweep_low/med/high` clip for the seat, held at the frame for the aim direction in the vehicle's frame (GTG's own yaw table; new NW2 `tif_act_cycle`, smoothed on the client), with low/med/high by pitch.
- **Shots** come from the seat, pushed out past the bodywork toward the target. Spread is x1.8 when stopped, rising with speed up to x3.8.

**Vehicle contact rules:**
- Driving somewhere: push on, firing from the windows, and only stop and get out for enemies within 600.
- Patrolling or parked: stop and get out for enemies within 1200.
- Further away: drive-by only.

0.6.3 test: secondaries work well; a rocket kill in the log confirms GTG rockets. No TIF errors. GTA gun sounds and drive-bys not yet confirmed.

## Phase 7: morale, casualties, radio, settings (started 2026-11-07, 0.7.0, NOT yet run in game)

GTG has no hands-up, writhing or dragging clips (its library is locomotion, combat, vehicles and get-ups). Surrender and downed poses use its get-up clips; there's no dragging of casualties.

### Morale (`tif/tactics/sv_morale.lua`, `tif_morale 1`)

Each soldier has morale 0..1, starting from `0.65 + 0.4 x suppressResist` (guard 0.67 .. support 0.91).

| Down | Up |
|---|---|
| squadmate killed -0.18 (the leader: -0.38 to the squad); another ally within 1000 -0.10 | killing an enemy +0.08 (squad +0.03), players included |
| hurt: -damage/120 (max 0.25) | quiet (no suppression, not hit for 5 s): +0.02/s back to the start value, +0.035 with the leader within 600 |
| suppression over 0.4: -(supp - 0.4) x 0.06 x (1 - resist) per second | treated after going down +0.15 |
| squad outnumbered 1.5:1: -0.012/s | |

| State | When | Effect |
|---|---|---|
| steady | > 0.45 | normal |
| shaken | 0.2 .. 0.45 | spread x1.25, doesn't advance on the enemy |
| broken | < 0.2 (at least 12 s, recovers above 0.35) | sprints ~1200 units away from the enemy with the gun down, then crouches and hides there; "retreat" callout |
| surrendered | broken, enemy seen within 500, and nobody within 600 to help or below half health (65% chance, rolled once) | drops the gun, kneels (last frame of the injured get-up to the knees), leaves the squad, out of the fight for good. Enemies stop targeting him; players can still shoot him. |

A squad whose average morale is under 0.3 withdraws (added to the withdraw conditions). Debug label: "morale: SHAKEN / BROKEN / SURRENDERED".

### Casualties (`tif/tactics/sv_casualty.lua`, `tif_downed 1`)

- **Going down:** a hit that would kill has a `tif_downed_chance` (0.35) chance to leave the soldier at 10 health on the ground instead. Never for head shots, explosions or hits over 150.
- **Downed:** lying on the back (first frame of `getup_tki_back`), gun away, low hitboxes, out of the fight. Any further damage kills. Pain callouts. Dies after `tif_bleedout` (45) s.
- **Medic:** the nearest squadmate within 1500 (the leader only if nobody else) runs over ("cover me"), unless an enemy is in its sight within 800, in which case it fights first. It kneels beside the casualty for 5 s, and the casualty gets up (injured get-up to the knees, then from the knees to standing) with 40 health.
- "Man down" callout, and -0.08 morale to the squad.

### Radio (`tif/squad/sv_radio.lua`, `tif_radio_range 4000`)

- **Contact reports:** fresh sightings (last 5 s) reach friendly squads within range after 2-4 s.
- **Backup:** a squad in a fight that's losing (lost men, average morale under 0.5, or outnumbered) calls for backup ("backup") at most every 40 s. The nearest friendly squad in range answers ("affirmative"); it gets the enemy positions at once and moves in. A hold order is dropped to go. The answering squad must not be fighting, player-led, on posts, clearing a building or in a vehicle.

### Settings (`tif/debug/cl_config.lua`)

Spawn menu > Utilities > Tactical Infantry > Settings, or `tif_settings` for a window:
- **AI:** freeze, ignore players, players' side.
- **Combat:** damage, accuracy, headshot multiplier, drive-bys.
- **Morale and casualties:** on/off, downed chance, bleed-out time.
- **Radio:** range, voices.
- **Vehicle seat offsets.**
- **Body time.**
- **Debug toggles.**
- **Quick actions:** spawn squads, garrison the base, order menu, clear.

Server settings change from the listen-server host's panel; on a dedicated server use the console.

### Test checklist

1. **Morale:** pin a militia squad with heavy fire and kill a couple; survivors go SHAKEN, then BROKEN and run. Corner a broken one: he may drop his gun and kneel. Others stop shooting at him.
2. **Casualties:** shoot soldiers in the body; about a third go down instead of dying. A squadmate runs over, kneels, and they get back up. Leave one alone 45 s: he bleeds out.
3. **Radio:** two militia squads ~2000 apart; fight one. The other gets the sightings a few seconds later, and once the first is losing, it moves in ("backup" / "affirmative" in the console with `tif_debug 1`).
4. **Settings:** open the spawn menu tab; change damage and see it apply.

### 0.7.1: convoys (`tif/vehicle/sv_convoy.lua`)

Several mounted squads, one vehicle each, driving one route in a column.
- **Route:** planned once from the lead, and every vehicle drives the same points. A patrol convoy joins the legs between its points into one loop and starts again when the lead gets round.
- **Spacing:**
  - The lead holds the convoy pace (380 u/s). It slows to 150 if the column stretches past 2.2x the gap, and stops past 3.5x.
  - Each follower keeps the gap (420) to the vehicle ahead: it stops under 0.6x, matches the vehicle ahead's speed under 1x, and speeds up past 1.6x.
  - Followers count as arrived one gap further back per place in the column.
  - This works through a per-tick speed cap in the driver (`d.speedCap`).
- **Contact:** any squad in the convoy stopping to fight halts the whole convoy. Vehicles within 2000 units of the fight stop and their squads get out; further back they just stop and wait.
- **Arrival** (transit): everyone gets out (or waits, with `stay`).
- **Remount:** after 30 s with nobody fighting, alerted or searching (or a base's all-clear), the squads get back in and the convoy sets off again once every vehicle is ready.
- **Commands:**
  - `tif_convoy [count] [faction] [class]`: a column at the crosshair, facing your view. Default 3 x `gtg_grandtheftgmod_baller2`, each with a crew of 4 (rifleman, leader, rifleman, AT gunner) who board it.
  - `tif_convoy_drive [stay]`: the nearest convoy drives to the crosshair.
  - `tif_convoy_patrol`: it loops between where its lead is and the crosshair.
- **Bases:** a definition can have `convoys` (class, count, crew size, loop points). The column forms behind the first point. tif_range "compound" now has a two-Baller convoy on the ring road (8 more soldiers), going the same way round as the Insurgent patrol and starting mid-way along the south road.

### 0.7.2: Decent Vehicle waypoints for tif_range (`tif/vehicle/sv_dvroads.lua`)

- **Layout:** road centrelines per map (`TIF.DVRoads.Layouts`). tif_range has three roads:
  - the ring road, as a loop (60 km/h);
  - the middle road between the west and east ring roads (45);
  - the gate road down to the compound, a dead end (25).
- **Lanes:** each road becomes two right-hand lanes, 80 either side of the centreline, with a waypoint at most every 300 units, snapped to the ground and linked one way along the lane. Loops close on themselves.
- **Junctions:** within 450 units, a road's lane ends are linked into the other road's lanes both ways round, and the other road's lanes into its lane starts, so vehicles can turn either way. The gate road gets a U-turn at its dead end.
- **Writing:** through DV's own API (`dvd.AddWaypoint` / `AddNeighbor`, wrapped in `TIF.DV.Clear/Add/Link`). Saved with DV's own format (`util.Compress(util.TableToJSON(dvd.GetSaveTable()))`) to `data/decentvehicle/<map>.txt`, which DV loads when the map starts (with its auto-load setting on).
- **When:** a map with a layout and no DV waypoints builds and saves them 3 s after loading. `tif_dv_build` rebuilds them (`nosave` to only try).
- With waypoints present, TIF's vehicle routes come from DV first (tier 1), so drivers keep to their lane. DV's own NPC drivers can use the map too.

### Benchmark at 0.7.2 (tif_range, 50 soldiers, battle, debug off)

| | Phase 1 (0.1) | Phase 2 (0.2.0) | 0.7.2 |
|---|---|---|---|
| AI per tick (avg) | 0.44 ms (2.9%) | 1.28 ms (8.6%) | 1.98 ms (13.2% of a 15 ms tick) |
| AI, first 8 s (45-50 alive, all fighting) | | | 3.3-4.3 ms/tick (22-28%) |
| Client | 63 fps | (bad run) | 61 fps, composer 72 ms/s, 1686 retarget solves/s at 40 us |

Breakdown per tick:
- perception 0.91 ms, the largest (808 traces/s);
- soldier Think 0.61 ms (actions, facing, weapons, including the per-shot friendly-fire cone);
- brain 0.29 ms;
- suppression 0.06, events 0.05, cover 0.03, paths 0.02.

All soldiers were tier 0 (everyone fighting near the player), so the tier slow-down for distant soldiers didn't come into it. Tick interval steady at ~15 ms with occasional 25-60 ms spikes; the 7.5 s first sample is the 50-soldier spawn. No layer-slot or overwrite problems. Verdict: fine as is; perception is where to look if more headroom is needed.

### 0.7.3 / 0.7.4: TIF.API for the DTW campaign (`tif/api/sv_api.lua`)

- 0.7.3: `TIF.API` v1 (squads, garrisons, queries, vehicles) and the hooks `TIF_SoldierKilled`, `TIF_BaseLevel`.
- 0.7.4: API v2 for DTW's reinforcements:
  - `GarrisonAdopt(base, squad, job)` (`TIF.Base.Adopt`): an outside squad joins a base (members, radio net, removed with it);
  - `MountPhase(squad)`;
  - `VehicleRoute(from, to, dvOnly)`;
  - `Convoy(squads, pos, stay)`: mounted squads drive there as a `TIF.Convoy`;
  - `VehicleSeats(class)`: seat count from a GTG car's data, without spawning it.
- gm_fork road texture `concretefloor037b` added to `TIF.Routes.MAP_ROADS`.

### 0.7.4: boarding fixes (from the gm_fork convoy test)

- **Doors on the far side.** The navmesh doesn't know about the car, so soldiers walked into the bodywork and stalled; they had to be physgunned round.
  - They now go round the front or the back via corner points, picking the end nearer to them and the door.
  - A soldier not getting closer for 3 s steps past the obstacle when no player can see him. If one can, he skips that corner or plans the way round again.
- **Straight into the seat when nobody's watching** (`tif_board_unseen 1`, default on; also in the TIF settings menu).
  - A boarding soldier within 2000 of the car is seated at once when no player is within 1000 of him or the car, or can see either within 4000.
  - In view, boarding is unchanged: walk to the door, open it, get in.
- **Decent Vehicle was never found** (`compat/sh_dv.lua`). DV's global table is `DecentVehicleDestination`, not `dvd` (that's a local name in DV's files). So `TIF.DV.Present()` was always false: no DV routes, and `tif_dv_build` on tif_range couldn't write waypoints. Fixed; vehicle routes now use DV roads first, as designed.
- `MT.MountSeated` / `API.MountSeated(squad, vehicle)`: mount with everyone put straight into their seats (no walk to the doors); the squad is ready on the next tick. For groups appearing mid-journey.
- **Driver: ramps aren't walls.** The level obstacle probe ignores world hits on drivable ground (surface normal z > 0.64, about 50°), so cars no longer brake and reverse at the foot of an up-ramp.
- **Proper stop before getting out.** A routine dismount (arrival, ordered) waits until the vehicle is under 25 u/s, for up to 6 s (`MT.EXIT_SPEED`). Combat dismounts don't wait.
- `API.VehicleUsable(veh)` / `API.VehicleDestroyed(veh)` (exploded or chassis at 0; an engine-dead vehicle is disabled, not destroyed).
- **Soldiers teleported back down the road after getting out** (DTW counterattack test). Two causes:
  - The NextBot locomotion snaps a bot it thinks is stuck back to its "last valid position", which is updated only while it walks. Soldiers put straight into their seats (`MountSeated`, convoys appearing mid-journey) still had their spawn spot there.
  - The exit spot was chosen ignoring the vehicle, so a soldier could overlap the car's body and count as stuck.
  - Fix: the exit spot must be clear of the vehicle too, and the stuck state is cleared (`loco:ClearStuck`). For 3 s after getting out, any jump over 250 units in a tick is undone (`V.GuardExit`).
- `API.FormSquad(soldiers)` and `API.SetCaptive(soldier, on)`: a kneeling, unarmed captive (surrender state, untargetable), or freed (steady, re-armed with the archetype loadout). For DTW's rescue operations.
- **Long-range harassing fire** (`npc/sv_brain.lua`, the not-visible branch).
  - When the enemy was only located by being fired on or hit (not seen) within the last 25 s, and is over 1200 away, a soldier taps single aimed shots toward that spot every 1.2-3.5 s. It's a 0.1 s trigger pull, scattered by about 4% of the range.
  - Instead of walking out to reacquire, he stays put. Not with a launcher, not when shaken.
  - The action shows as "return fire (long range)".
- **Riders held in their seats**: every think a seated soldier who's been shoved more than 2 units off his seat position is put back (and kept at MOVETYPE_NONE).
- **No physgun / gravity gun** on soldiers in a vehicle, at the door getting in, or getting out (`PhysgunPickup`, `GravGunPickupAllowed`).
- **Two-way road routes** (`compat/sh_dv.lua`). DV lanes are one-way and gm_fork's double many trips, so `TIF.DV.Route` runs its own A* on the waypoints with every link usable both ways. It starts from the 6 nearest road points and takes any of the 6 nearest at the end. The graph is cached and rebuilt when the waypoint count or `DecentVehicleDestination.TIFStamp` changes. DV's own search (below) is the fallback.
- **DV routes take the shortest lane** (`TIF.DV.Route`). One-way lane graphs (gm_fork's) sent cars round long loops when the nearest waypoint was the lane going the other way. The 4 nearest linked waypoints at the start are each routed to the 4 nearest at the end (`dvd.GetRoute`), and the shortest route is kept. Boat lanes and dead ends are skipped.
- **No more soldiers inside each other.**
  - `TIF.Room(pos)` and `TIF.FreeSpot(pos)` check for room for a soldier: nobody, no prop, no car, no player there. Otherwise they find the nearest free spot in rings out to 160 units.
  - Used by `TIF.SpawnPoints` (every spawner), garrison posts (two soldiers given the same post), and soldiers getting out of a vehicle (two using the same door).
- **Fallen under the map** (`tif/npc/sv_rescue.lua`, `tif_rescue 1`).
  - Every 2 s, a soldier on foot counts as lost when he is fully under water, or has no navmesh under his feet with the nearest nav area well above him (under a displacement, not just off the mesh on a ledge).
  - After about 6 s lost he is put back on the nearest nav area above, clear of others. With none, or on the third time, he's removed.
  - `tif_rescue_all 1` also removes other addons' NPCs and nextbots that fell under the map; they're never moved. Both settings are in the TIF settings menu under Safety.
- **Navmesh road routes no longer cut down slopes.** When thinning a route, a straight stretch now also needs the ground to follow it: checked every 120 units, within 60 of the line. Before, only a hull trace for walls was checked, so a line through open air over a hairpin counted as clear, and on gm_fork cars drove off the mountain. This only matters without Decent Vehicle waypoints; DV routes are used as they are.

### 0.7.5: balance sliders, faction editor, passive riders (2026-11-08, NOT yet run in game)

- **Balance** (TIF settings menu > "Balance (1 = default)"): damage, accuracy, health (`tif_health_scale`), reaction time (`tif_reaction_scale`, lower is faster), view distance (`tif_view_scale`), headshot. Health applies to soldiers spawned after the change.
- **Faction editor** (`tif_factions`, or the button in the settings menu, or the spawn menu entry). It edits id, name, side, voice, models ("Add the model I'm wearing"), each role's primary and secondary weapons (GTG weapon list), Glide vehicles and allies.
  - Saved to `data/tif/factions/<id>.json` and loaded at start. Editing a built-in faction overrides it; deleting the override restores the built-in.
  - Host / superadmin only.
- **`TIF.API.MountPassive(sq, veh)`**: the squad rides in a vehicle someone else drives (a player). They don't stop it on contact or take the driver seat logic. Also `PlayerSquad`, `AddToSquad`, `SquadOrder` in the API.

### 0.7.6: TIF's own copy of the GTA content (2026-11-08, NOT yet run in game)

TIF no longer needs GrandTheftGMod, its Glide car pack or Squad Deployables installed, and a GTG update can't break it. `tools/build_gta_bundle.py` (not uploaded) makes the copy from the installed addons; run it again to rebuild.

- **`lua/tif/gta/`, global `TIFG`** (was `GTG`): only the parts TIF uses.
  - Kept: clip and character registry, the male clip data (7,168 clips), the retargeter (playermodel skeleton/map/pose/bone solver), vehicle entry plans and seat layouts, GTA gun sounds, explosions, rockets (`tif_gta_projectile`), gas clouds, weapon tints.
  - Left out: GTG's player systems (movement, camera, HUD, wardrobe, parachute, items, melee, cover, ladders, player weapons, player hooks), its replacement of GMod's flesh-hit sounds, and GTA's explosion particles (GMod's explosion is used).
  - Small stand-ins for the player tables the kept code still reads (`TIFG.Config`, `Motion`, `Ragdoll`).
- **45 weapons, data only** (`lua/tif/gta/weapons/`): the military set (rifles, SMGs, MGs, shotguns, pistols, snipers, RPG and grenade launchers, with Mk2s). Same class names as GTG's (`weapon_gtg_*`), but they're not SWEPs: soldiers use them, and players can't pick them up. With GTG installed, its other guns also work in the faction editor (`TIF.GTG.Stored` checks TIF's copy first, then registered SWEPs).
- **Assets renamed so nothing clashes with GTG when it's installed:** `models|materials|sound/.../grandtheftgmod/` -> `tif_gta_assets/`. Paths inside the model files are renamed in place (same length).
- **GTG Glide cars** (all 8): classes `tif_gta_glide_cars_<car>` (was `gtg_grandtheftgmod_<car>`); spawn menu category "GTA cars (TIF)". Saved factions naming the old classes are converted.
- **Still needed:** Glide (vehicle base), the faction playermodels (MW2 militia, HECU PMC) and voice packs (Insurgency mercenary, BF3 marine), the prone mod, and Decent Vehicle for road routes.
- **Size:** about 316 MB on disk, ~180 MB download. Animations ~76 MB, weapon models/textures ~50 MB, gun sounds ~58 MB, cars ~88 MB.
- **Checked offline:** both realms load in LuaJIT with a mock GMod. Every weapon's clips exist, sounds map, seats and explosions resolve. Every copied model's included models and materials resolve inside the copy.
- **Test:** turn off GrandTheftGMod, its car pack and Squad Deployables (unsubscribe, and move their `addons/` folders out), then `tif_selftest`, spawn soldiers, a convoy, an RPG soldier, and a DTW sector with fortifications.

### 0.7.7: fortification cover, vehicle paint (2026-11-08, NOT yet run in game)

- `TIF.API.MarkCover(ent)`: a placed prop counts as cover whatever its size, and the cover picker prefers it (+1.5, shown as "fortification" in the debug reasons).
- `TIF.API.PaintVehicle(veh, color, color2)`: GTG cars through their paint (livery off), others with SetColor.

### 0.7.8: muzzle flash, spawn stutter (2026-11-08, NOT yet run in game)

- **Muzzle flash at the feet:** `GetAttachment` on the bone-merged gun gave the muzzle as if the gun stood at the soldier's origin. The muzzle's offset from the gun's grip bone is now measured once per gun model (unmerged copy) and applied to the merged grip bone (`cl_body.lua`, `muzzle_world`). Bullets were not affected.
- **Stutter when a garrison appears:** `TIF.Base.Garrison` spawned the whole garrison in one tick. It now builds it 2 soldiers per tick (`B.SPAWN_PER_TICK`), one base at a time, from a coroutine. It still returns the base at once. `base.pending` counts the soldiers still to come, and reinforcement-by-losses counts them too. `B.Remove` stops a build in progress. New `TIF.API.GarrisonPending(base)`. Offline test (LuaJIT, stubbed): 12 soldiers over 6 ticks, all squads formed; removal mid-build stops it.
- **Model loading:** new `core/sv_precache.lua` precaches every faction model, host ped and bundled gun model at map start (`tif_precache 0` to turn off), so they aren't read from disk the first time a soldier comes into view.
- Not changed: soldiers' client animation still runs every frame at any distance (~2.3 ms per frame for 50 in the 0.7.2 bench). A distance LOD is the next step if the stutter isn't spawn-related.

### 0.7.9 / 0.7.10: two-player fixes (2026-11-08, NOT yet run)

From the first two-player test (a friend hosting, Jimmy joining a campaign in progress): soldiers sometimes showed as the bare GTA freemode ped with no gun, mostly for the joining player and occasionally for the host. Prisoners discovered later looked right.
- **Full updates:** in multiplayer a network hiccup makes the client run `OnRemove` on entities that stay, which threw away the soldier's body state, faction model and gun; `Initialize` isn't called again, so nothing rebuilt them. `Bd.DrawHost` now re-adds a soldier with no state (`cl_body.lua`, `tif_soldier.lua`).
- **No retry:** a faction model or gun that failed once (e.g. built while a joining player was still loading) was never tried again, and the skeleton reader and bone map remembered failures for good. Now: parts retried every 2 s, skeleton/map failures retried after 10 s. The same patches are in `tools/build_gta_bundle.py` so a rebuild keeps them.
- **Default-looking enemies:** skin and bodygroups were only set when the faction model was made, so a look that reached the client later (joining, hiccup) was never applied. Now re-applied whenever the networked look changes (`apply_look`).
- **0.7.11, guns hanging from one hand** (joining player's clip, ~100 ms ping): followers walked with the relaxed walk and no weapon overlay, the look of the missing-slot fallback (main sequence only). Layer slots reaching a client stays unreliable in GMod (Phase 0 spikes), so the fallback now plays the armed (aim) locomotion, which holds the gun itself. The server's refresh on a missing-slot report also re-sets each slot's sequence, not only its weight. Unconfirmed: check `tif_debug 1` "missing slots" when it happens.
- 0.7.9: custom factions sent when the client says it's loaded (`tif_ready`), not 3 s after `PlayerInitialSpawn` (lost while still loading). DTW 0.8.6 does the same for sectors, objectives and settings.

### 0.7.12: damage by side (2026-11-08)

- `tif_damage_friendly` and `tif_damage_enemy` (default 1, 0-3 in Settings > Balance): multiply the damage soldiers deal, on top of `tif_damage_scale`. Friendly = allied with `tif_player_faction` (`TIF.SideDamageScale`). Bullets are scaled at the shot; rocket and grenade blasts (which `tif_damage_scale` didn't reach before) in an `EntityTakeDamage` hook, by both the global and the side multiplier.

### 0.7.13: perception profiles (2026-11-08)

Squads in a street (Insurgency-style map, ~2000-3000 units apart) weren't engaging. View distance (4500, marksman 7000) wasn't the limit; spotting was: detection slows past 1000 units, calm soldiers spot at 0.8x and see 95 degrees.
- `TIF.Perception.Profiles`: `standard` (the original numbers) and `long` (view x1.6, spotting x1.5, full speed out to 1800 units, +25 degrees unaware FOV). Still target, calm, in view at 2500: about 5 s standard, about 2 s long.
- Chosen per soldier: `npc.tifPerception` (`TIF.API.SetPerception(soldier|squad, name)`), else hook `TIF_PerceptionProfile` (npc), else `tif_perception` (default `long`). DTW answers the hook with `standard` while a campaign runs, so its AI can still be surprised.
- `tif_detect_scale` (spotting speed, default 1). Settings > Balance has the profile choice and the slider.
- For the planned mission framework: it uses `long` by default, or its own profile added to `TIF.Perception.Profiles`.

### 0.7.14: several voice packs per faction (2026-11-08)

- A faction can list several voice packs (`voices = { ... }`; the old single `voice` still works). Each soldier gets one of them the first time he speaks and keeps it (`npc.tifVoice`). Faction editor: "Voice packs" is now a list with "+ add". Self-test checks every listed pack.
- New packs, optional: `securityforce` and `securityforcevip` (TFA VOX Insurgency Security Force Improved, Workshop 3144830145, already installed). Not added to the built-in factions (Jimmy had asked to leave that pack unused); pick them in the editor. Mapping: "subdown" = kill, "wounded" = pain/man down, "pl_deathshout" = death (the VIP set has no death shouts; it uses "wounded").
- No per-soldier pitch change (Jimmy's call).

### 0.7.15: arms dropping when leaving cover (2026-11-08)

- Clip (Insurgency-style map): popping up from cover and settling back, the soldier stood for a moment with the rifle hanging low. A full-body cover action owns the arms and switches the weapon overlay off; when it ends the action fades out in ~0.1 s but the overlay came back at `UB_RATE` (~0.25 s), leaving the arms unheld. For 0.4 s after a full-body action ends the overlay now blends at `LEG_RATE * 2.5` (~0.06 s). Not yet seen in game.

### 0.7.16: pop-out legs (2026-11-08)

- Popping out of cover set `tif_caim` together with the GTA intro clip, so the client put the standing aim overlay on the upper body while the intro's legs were still rising from the crouch (torso up over crouched legs). `tif_caim` now goes on when the intro ends (aim phase); the intro plays whole as a full-body action, and the 0.7.15 fast overlay blend brings the aim in after it. The outro and cover enter already played whole. All layer decisions are TIF's (`cl_body.lua`, `sv_cover_behave.lua`); GTG only supplies clips and data.

### 0.7.17: content packs, camo variants, bodygroup rules; TIF Faction Pack (2026-11-08, NOT yet run in game)

TIF side:
- `config/sh_packs.lua`: other addons add factions and voice packs with `TIF.RegisterContent(name, fn)`, or queue `{ name, fn }` in global `TIF_CONTENT` when they load first (autorun order is alphabetical). Pack factions get `def.pack`, count as built-in (editor override and reset work) and aren't precached unless in use (player faction, or hook `TIF_PrecacheFactions`; DTW names its two sides).
- Camo variants: `variants = { { id, name, models } }`, `variantMode` = `squad` (default: soldiers of a faction spawned within 4 s share a camo, so a squad or garrison matches), `mixed`, or a variant id. `TIF.PickVisual` in `tif_soldier`; the faction editor has a Camo dropdown.
- Bodygroup rules: `bodygroups = { name = { allowed values } }`, `bodyRules = { { group, needs } }` (group forced to 0 when `needs` is 0). Kept through editor saves.
- `TIF.Voice.RegisterPack(id, def)`, `TIF.Voice.SANDSTORM_EVENTS` (the mercenary event map; every Sandstorm pack uses the same line names).

Faction pack: `addons/tif_faction_pack` (own addon.json). 7 factions; models stay in their Workshop addons and a faction is skipped if they're missing:
- allied: `us_army` (US Army Multicam, 13 incl. 4 female; no NVGs, goggles only with a helmet), `usmc_bf3` (BF3 marines), `operators` (Alex Vestin, 13 camos x 5; `mw2_soldier_06` is the ghillie and is excluded), `contractors` (PMC playermodels, 6 camos x 14);
- hostile: `arab_militia` (BF3 PLR militia + FSA outfits, mixed; underwear legs excluded), `chechen`, `rus_rebels` (gear only with an armour vest).
- Voices: `tif_arab_rebel`, `tif_arab_operative` (copied from Jimmy's alq_insurgents, 64 MB), `specops` (TFA VOX Insurgency Sandstorm American addon). Camo names read off the uniform textures (guesses).
- Offline test (LuaJIT, real addon folders): all 7 register with the counts above, no ghillie models, squads share a camo, mixed and fixed modes work. The first run caught `sh_packs.lua` running the queue before its helpers were defined (fixed).

### 0.8.0: MW19 animation host, Stage 2 of the rework (2026-11-10, NOT yet run in game)

Plan and stages: `TIFDIDDY/MW19_ANIM_PLAN.md`. Backup of 0.7.24: `K:\backups\tif_pre_mw19_2026-11-10`.

How it's switched:
- `tif_mw_anims 1` (archived, replicated; default 0). Male factions' new soldiers spawn on the MW19 host
  (`mw_male`, from the `tif_mw_anims` addon) instead of the GTA ped.
- Female factions and factions with `mwAnims = false` keep their GTA host. Without the addon nothing changes.

What changed:
- `compat/sh_gtg.lua`: `A.HostFor(fac)`, `A.IsVB(id)` (character `skeleton = "valvebiped"`), `A.MW_HOST`.
- `entities/tif_soldier.lua`:
  - `tifHostId` / `tifHomeHost`, NW2 `tif_host`.
  - `ENT:TIFSetHost(id)` swaps the model, main sequences and layer slots.
  - Think switches back home 0.6 s after the last GTA-only action, never in or boarding a vehicle.
  - Corpses on a ValveBiped host are the faction model itself as a ragdoll, posed by bone name, with skin and
    bodygroups; no client dressing.
- `npc/sv_action.lua`:
  - `Act.Clip` falls back to the faction's GTA host.
  - `Act.Play` switches the soldier to the GTA body for a clip only that body has (cover, vehicles, casualty
    drag, morale...).
  - An upper-body base clip missing on the current body is dropped.
- `npc/sv_move.lua`: speeds come from the home host's clips (MW walk 103, jog 199, sprint 247).
- `npc/cl_body.lua`:
  - The body is found from the model (`TIFG.ByModel`). On a change it rebuilds the follower and gun and
    clears bone manipulations.
  - ValveBiped host: plain bone-merge follower; the gun is unmerged and placed from the hands every frame
    (`place_gun_vb`: grip in the right palm, barrel to the left hand or the right hand's barrel direction,
    upright).
  - MW reload clip (`mw_reload` / `_pistol` / `_lmg`, upper-body `_ub` sequences) stretched to the weapon's
    `reload_time`.
  - `vb_pose`: aim pitch, recoil kick and hit flinch as Spine2/Spine4 yaw bends.
- `config/sh_packs.lua`: any model is usable on a ValveBiped host. `core/sv_precache.lua` precaches the MW host.
- Offline: syntax OK; host choice and action fallback 13/13 (`mw_harness` in the session scratchpad).

Known limits:
- No relaxed (gun-lowered) carry: MW soldiers always hold the rifle up.
- `j_gun` from the clips isn't used (MP and campaign clips key it differently); slings wait on that.
- Prone still uses the Prone Mod sequences on the faction model, as before.

### 0.9.0: MW19 cover, prone and flashbang reactions (2026-11-10/11, NOT yet run in game)

All MW-body only (`tif_mw_anims 1`); GTA soldiers are unchanged.

- Gun roll fix: GTA guns are +X barrel, +Y up. `gun_info` now takes up from each model's bounds (body sits
  above the grip), so any gun pack works.
- `tactics/sv_cover_mw.lua` (new, loaded after `sv_cover_behave.lua`): MW19's AI cover.
  - Types: ls = cover_left_stand (high cover, left edge), rs = cover_right_stand, cr = cover_crouch (low wall,
    aim over the top).
  - Node: 16 from the wall. Corners put the edge 12 (ls) / 10 (rs) past the node, found by traces (MW.Prepare).
    These values come from the clips' measured geometry.
  - Arrival: picked from 36 directional arrivals per type (jog/run, lead foot, numpad direction) by matching
    each clip's measured start pose (from its root motion) to where the soldier actually is.
  - Hide with twitches; peek (look in / look / look out) while the enemy is unseen.
  - Lean in, then aim with a real 3x3 blend: pose params `mw_aim_yaw` (+ left) / `mw_aim_pitch` (+ down),
    NW2 `tif_aim_yaw`. The body is anchored: `tifAimFree` skips the 14-degree facing check, `tifMuzzle` sets
    the lean muzzle, `tifAimAt` drives aim pitch without turning. Then lean out.
  - Blindfire (fires only in the middle of the clip), cover reloads, corner switch on pillars (slides to the
    other node during the turn), directional exit away from the wall.
  - Flash reaction on a real stun (NW2 `tif_stun_until`, not perception blackouts) from any settled phase.
- MW19 aim spaces are additive: outer points are offsets on aim_5. `cod_anim_prep.compose_additive` (base x
  offset, verified symmetric) bakes them into absolute poses. Measured ranges: corners +-90 yaw / +-62 pitch,
  low wall +-60 / +-51.
- Prone on the MW body: `mwp_down` / `mwp_up` / `mwp_idle` / 8-way `mwp_crawl_*` play on the host through
  compose. No Prone Mod needed. `sv_prone.lua` takes durations from the clips, and `mwp_idle` is the prone
  hitbox pose. The loops' pelvis is lined up with where the get-down ends.
- `TIF.ReactMW` (brain branch after cover exit): flashbanged in the open, stop and play MW19's stand/crouch
  reaction, long or short by stun length.
- `sv_action.lua`: a clip only the home (MW) body has switches back to it from the GTA fallback body.
- Offline: syntax OK on every changed file; MW cover / reaction harness 33/33 (real generated clip data, mock
  wall + corner); host logic 13/13.

Known limits:
- Cover nodes come from TIF's spots (traced corners), not hand-placed. Odd geometry may need EDGE_OFF tweaks.
- Lean fire clips (`*_lean_fire_burst*`) aren't used; recoil is the spine kick.
- Prone aim and prone flash reactions aren't wired (mwp_flash is built).
- Arrivals use a linear blend to the node (Act `to`), not each clip's own curve.

### 0.38.59: a real fall into the downed state (2026-11-26, NOT yet seen in game)
User: "look for a downed transition because rn it just plays after a death which is wrong sometimes". Going down played
the first half of a random standing torso death (LS.FALL_CUT 0.5), then blended to lying wounded: a standing death for
crouched / running / prone soldiers, falling whichever way that death fell.
- Looked for one: MW19 MP's sdr_mp_laststand_torso_med / head_med (already built as mwls_fall_*, unused) start lying
  (pelvis 5.9): hit reactions while down, not falls. No AI "into last stand" exists. MW19 SP's long-death entries
  (mwld_<st|cr>_<kind>_enter, built for long deaths) fall a wounded man from standing / crouched to the ground;
  measured against the last-stand idle (pose relative to the pelvis): crawl_back_enter (head 1.3, hands 11 / 6) and
  crawl_l_enter (head 6) end nearly in it; the deaths and the other entries 100-200 off.
- sv_laststand_mw LS.FallClip / Down: standing -> mwld_st_back_enter, crouched -> mwld_cr_back_enter; hit from his right
  -> the _l (side) version; 25% the other one for variety. Root motion, played to 97%, then lying wounded. Downed while
  prone (sv_casualty records tifDowned.wasProne): straight to lying wounded, no fall.
- Harness stage78 39 (+3: standing fall, crouched fall, prone straight to lying; ProneB mock honours tifProne).


### 0.38.60: player faction fallback; BLUFOR / OPFOR / Independent player sides (2026-11-26, NOT yet seen in game)
User: "regular marines are shooting at me now too". tif_player_faction was "operators" (TIF Faction Pack), and the pack
(tif_faction_pack, tif_cod_factions) was moved out to K:\TIF TEMP: players were an unknown faction, hostile to all.
- core/sh_factions TIF.PlayerFaction(): the setting if it's an installed faction or a player side, else usmc (one
  console warning). Used by FactionOf (players, HL2 player-ally NPCs), SideDamageScale and the precache.
- User: "add generic blufor, opfor, and independent factions which are just player identifiers". TIF.PlayerSides
  (not in TIF.Factions: no soldiers, no spawn menu, untouched by the faction editor / packs). Relations: blufor allied
  with every faction of side "ally", opfor with every faction of side "enemy", independent with none; a faction's own
  allies / neutral lists naming a side win; the sides are hostile to each other. Settings "Players' side" lists them first.
- Harness playersides 25 (new), fire 20 (PlayerFaction mock).
- Bench (user: "make sure bench uses the current models"): tif_bench spawned "militia" vs "pmc", hidden load-time copies
  of insurgents / usmc (alive counts read 0/0). Now the live factions, tif_bench_a / tif_bench_b (insurgents / usmc);
  the report lists each side's spawned models, adds the move step (Prof "move" round Move.Step in RunBehaviour, never
  measured before), crowd and cover_mw buckets, the gun hold arm IK (cl_ik_us / cl_ik_n round cl_gunhold's bone
  callback), soldiers animated and composes/s; file bench_<count>_<mode>_<version>.txt (before / after kept). Harness
  gunhold 19 (SysTime mock).

### 0.38.61: client animation LOD; faction relation cache (2026-11-26, NOT yet seen in game)
Baseline bench (bench_50_battle_0_38_60.txt, gm_construct, 50 soldiers): client 34 fps (29.5 ms frames), cl_anim
338 ms/s (~11.4 ms a frame, ~32 soldiers updated every frame at ~355 us each), gun hold IK 70 ms/s (74 us a solve),
feet 11 ms/s; server 2.57 ms a tick (17%), perception the largest share (0.89 ms).
- Cause: cl_body update ends in ent:SetupBones() for every soldier every frame (to place the gun from the hand): an
  8-layer bone build plus the IK / feet callbacks, also for soldiers behind the camera the engine would never build.
- cl_body Bd.LOD (tif_anim_lod 1, tif_anim_lod_every 4): MW19 soldiers outside the view cone (EyePos / EyeAngles, the
  wider of the player's and the view setup's fov, 16:9 aware, +12 deg and the body's radius; always full within 160;
  flashlight carriers always full: their beam lights what's on screen) compose every 4th frame with the skipped time
  carried in (foot phase, footsteps: cl_foley takes the range crossed) and skip the bone build, gun / mag / sling /
  prop placement. Back in view: the whole update before that frame draws. Their muzzle isn't used (tracers start
  from the server's point, no flash sprite / light). Settings panel entries.
- Prof cl_compose / cl_bones split cl_anim; bench reports both and the LOD counts.
- core/sh_factions: FactionRelation cached per pair (cleared every second and by RegisterFaction). Suppression does
  the distance maths before the relation.
- Harness animlod 19 (new), playersides 29 (+4 cache), timer mocks in hl2npc / marpat.

### 0.38.62: no IK on bone builds nobody sees; finer client profile (2026-11-26, NOT yet seen in game)
Bench 0.38.61 (bench_50_battle_0_38_61.txt): cl_anim 338 -> 268 ms/s, composes 950 -> 647/s, but 28 fps (a different
fight: server cost +13%, singleplayer shares the frame). Split: compose 30, bone build + gun 131, ~107 ms/s elsewhere
in the update. Gun hold IK ran 735/s against 647 composes: out-of-view soldiers' bones still get built by someone
(their shadows, most likely; "earlier in the frame" builds 608 -> 5519), each with the full arm IK.
- cl_gunhold ik_solve and cl_feet's callback only on the bone build cl_body asked for this frame (st.writeFrame ==
  FrameNumber()): early builds are thrown away by its InvalidateBoneCache, out-of-view builds show no hands / feet.
- Finger poses within M.FINGER_RANGE (700) only.
- Prof cl_parts (ensure_parts), cl_foley, cl_pose (slot check, spine pose, prone tilt): the bench lists them.
- Harness gunhold 20 (+1: no IK on a build that isn't this frame's write; writeFrame in the mock).

### 0.38.63: LOD view fix, start / stop hand-offs, MW19 stops back, revive fixes, squad variety (2026-11-26, NOT yet seen in game)
User: "alot of newer bugs ... anims jitter/fail", starts "slide a bit", "some stops still dont carry the right gun
orientation", "make sure there isnt like a long pause after stops", revives "gun would either go everywhere or be stuck
to their hand", "revives break sometimes and show as prone", "force as much model and bodygroup variety as possible
among spawned fireteams/squads", idle activity slings "like the old chest weld" / following the right hand.
- LOD view: EyePos / EyeAngles in PreRender can be the last view rendered (water reflection, scope / RT cameras):
  soldiers in front flickered into the cheap update (every 4th frame, gun not placed). Now the main view from
  RenderScene (origin, angles, fov); none for 0.5 s (another addon overrides it): everyone full. Out of the cone for
  0.3 s before going cheap; back in it: full at once.
- Starts: root motion SetPos left the locomotion at 0, the path took over from standing (legs dipped to the idle).
  T.ExitVel (last root samples, turned by the start yaw) -> npc.tifStartExit -> loco:SetVelocity when it played through.
- Stops: MW19 sources again (manifest PREFER_SOURCE = {}; the 20 MW22 swaps had no usable gun bone; MW19's l / r stop
  files are identical, so the stop-foot swap changes nothing on those). Stop tails measured 0.4-1.7 s after the root
  settles (walk avg 0.93): T.SettleU (root within 2 units / 3 deg of its end), the landing warp ends there (warpU), the
  clip clears T.SETTLE_TAIL 0.2 s later (Act a.stopU): arrived, free for the next thing.
- Revives: CAS.Down never reset NW2 tif_prone (only deaths did): downed from prone, the client kept the prone set over
  the downed / revive clips. Reset there. MP last-stand clips (sdr_mp_laststand_*, the medic's mwls_help_*) had a
  "carried" gun bone (r 1 all through) that is junk: gun_holds.py MP_UNUSABLE -> undriven -> slung. MW22 buddy revives
  (mwbr_*, undriven) kept the gun in the hand: slung too (cl_body slingAct).
- Activities: Bd.CARRY_R 0.5 -> 0.35 (only the seated sleep loop, 0.43, changes: it now carries the gun like its
  sit-down / wake-up). MW22 activities (hum, radio, look, scratch, stretch) still hold the gun in the right hand: MW22
  splits the gun's motion over j_gun (position) and j_gun_adjust (rotation, not in TIF's CoD skeleton), not decoded yet.
- Variety: TIF.VarietyPick (sh_packs): per faction, soldiers spawned within 8 s share a bag; model (PickVisual, pack
  variants), skin, each bodygroup (random_look) and modular combos / parts (M.Pick) take the least-used option, random
  among ties.
- Anim rebuild (mwt_stop_run_*, jog / walk l/r 8 / 6) and gun_holds.py rerun. (A first gun_holds run hit a 590 s
  timeout and left zz_jgun.lua empty: restored from a backup, rerun without a limit.)
- Harness: animlod 23 (RenderScene view, hysteresis), trans 76 (+9 exit speed, settle), revive (new), variety 10 (new).

### 0.38.64: MW22 gun decoded, cover exits in combat, gun-down stops, pistol prone, cover weapon switches (2026-11-26, NOT yet seen in game)
- MW22 gun (user: activities "follow the right hand when they shouldnt"): MW22's AI clips and MW19's MP clips split the
  gun over j_gun (position, one rotation key) and j_gun_adjust (rotation). The MPM chain (j_clavicle_ri -> j_gun_adjust ->
  j_gun, MP_GUN_FIT 2026-11-24) with the gun rest moved by its own offset is MW19's AI gun bone: on the one clip both
  rips share unchanged (sdr_com_exposed_stand_idle01) 0.06 u / 0.1 deg; held MW22 / MP clips keep the wrist 1.1-2 u off
  MW19's grip spot. cod_anim_prep AI_CHAIN_GUN + is_chain_gun: the bake uses it for any clip with j_gun_adjust rotation
  and no j_gun rotation (MPM's MP_GUN still wins). gun_holds.py: src_file (same file order as the builder: xanims first),
  chain clips driven, cod_wrist_in_jgun on the decoded chain; imports the repo's tools/anims (was the SMH baker folder).
  Full anim rebuild (4316 clips, same roles) + gun_holds. Check: tools/harness/gun_chain_check.py (7).
- Cover exits (user: "wire them in and make sure they are used appropriately ... if any end with walking/running then
  make sure to preserve that ... flanked they can not do it but ... if they are crouched thats preserved"): MW.ExitTo
  (settled / looking / lean-aiming, goal over 120 away): the exit heading best toward the goal (lean exit when aiming,
  CQB fast / walk exits CQB-style, else jog), played out when within EXIT_COMMIT, else cut at EXIT_CUT; its speed at the
  hand-off (T.ExitVel at that u) -> loco:SetVelocity, stance standing (MW.FinishExit). Squad maneuvers and medic runs use
  it; the calm fight-over exits carry their speed too. Flanked / exposed: no clip; crouched stays crouched
  (tifKeepCrouchUntil, MW.KEEP_CROUCH 2 s, applied in the brain's stance step).
- Gun-down stops (user: "SOME stop anims will have the gun down shown but still let them shoot"): measured on every stop:
  sprint arrivals (run) and the pistol jog / run stops drop the barrel below -30 deg for ~the first 60%; calm / alert are
  gun-down carries (out of fights); walk / jog / crouch stops keep it up. T.FightStopSet: engaged rifle stops from a
  sprint use the jog stops. gun_holds.py gun_low() writes zz_gunlow.lua (TIFG_GUN_LOW[role] = { from, to }, start / stop
  clips); W.Think holds fire inside it (root-motion clips read 0 speed, so the moving-fire limit never applied).
- Russians (user): assault + AK-74u, riflemen (own rifleman entry) + Oden; other roles unchanged.
- Pistol prone (user: "pistol prones"): mwp_pstl_idle / _aim (blend9 from MW19's 5-point pistol prone aims) / _up /
  _crawl_8_loop; sh_anim L.prone.pistol; cl_body picks them with a pistol out (get-up stretched to the rifle's PR.up
  duration the server times; forward crawl within 35 deg, other ways the rifle crawls; get-down stays the rifle's).
- Cover weapon switches (user: "pistol switching in cover"): mwc_<ls|rs|cr|st|lc|rc>_to_<pistol|rifle> (MW22, crouch
  also MW19). MW.PlaySwitch from settled cover: the clip as the cover action (phase "switch", no firing, then hiding with
  the new weapon's set); W.Switch takes its swap / ready timing from that clip's notes.
- AT4 (user screenshot: "at4 is black and should be a little higher on the back, fire and toss is perfect"): the material
  kept SandSWEP's "$color2 [0 0 0]" + $blendtintbybasealpha, but our at4_rgb.vtf is DXT1 (no alpha = 1 everywhere): tinted
  black all over. Both keys dropped (at4.vmt, and at4_build.py strips them). Back pose: disposable launchers ride
  M.DISPOSABLE_LIFT (5) higher than the RPG-7 (cl_gunhold SlingPose).
- Harness: test 115 (+18: exits, flank crouch, switches), trans 79, fire 23, russians 115, pistolprone 11 (new), launcher 54.
- Results: gun_holds 4110 sources, 75 with an unusable gun bone (was 743: ~680 MW22 / MP clips now follow their decoded
  gun - patrol activities, buddy revives, MP strafes / prone, corner checks, recoveries...; the 12 new cover switches
  join under the weapon-switch rule; the 56 MP last-stand / revive clips stay, MP_UNUSABLE), 918 where the right hand lets
  go; zz_gunlow 166 start / stop clips (run, pstljog, pstlrun; calm / alert gun-down carries). Decoded examples: stretch
  lets go (r 1), scratch keeps it in hand, humming moves it a little (r 0.10); buddy revives let go (r 1: the medic's gun
  follows MW22's own motion). All 51 harness suites pass (revive 9: buddy revives now decoded), gun_chain_check 7.

### 0.38.65: shotgun pump keeps the gun straight (2026-11-26, NOT yet seen in game)
User: "the pump is kinda weird, they like pump it up and sideways weirdly". The pump is the shotgun recoil kick
(mwfk_shotgun_*: MW19's shotgun fire clip, shot + pump, as an additive delta of its first frame). Its j_gun delta (the
gun rocking through the pump) is added in j_gun's local frame onto whatever the base clip holds, whose gun orientation
differs from the fire clip's: the same delta turned the gun about other axes, up and sideways.
- tif_mw_build shot_slice(still=...): listed bones keep the shot frame's pose through the kick (no delta). Manifest:
  shotgun kicks still = ("j_gun",): the body's recoil and the arms' pump stay, the gun keeps the base clip's orientation.
  Rebuilt mwfk_shotgun_* (the first build still eased j_gun from the last shot frame back in the 5 ease-back frames:
  held bones stay put there too now; checked on a built kick: j_gun spread 0, left forearm 0.82).
- Arm-overlay clips (user screenshot, "alot of clips now have guns like that", gun hanging off to the side): 132 roles
  (aimed strafe loops mstg_walk / mstg_run, walk / jog starts and stops, crouch turns, stance changes) are MW22 AI legs
  with MW19's aimed-idle arms + j_gun laid over (AI_ARMS / AI_ARMS_CROUCH). The overlay brought MW19's j_gun (one key) but
  the MW22 base kept its j_gun_adjust track, so 0.38.64's bake read them as chain clips: MW19's shoulder-relative gun
  inside MW22's clavicle chain. tif_mw_build: with an overlay that supplies j_gun, the base's j_gun_adjust is dropped
  (the overlay's gun bakes as before). gun_chain_check 10 (+3: overlay clip off the chain, gun in the hand like the idle
  within 2 deg, builder line). Rebuilt the 132 roles.
- Hit reactions while moving (user: "prevent npcs from using idle hurt anims if their moving ... it can kill their
  momentum"): walking under H.RUN_SPEED counted as standing, so a hit played a standing pain and Move.Stop'd him; running
  fell through to that 30% of the time; MW22 pain shock could stun him mid-move. sv_hits_mw H.Pain: moving
  (> H.MOVE_PAIN_MIN 40, not prone): no pain shock, no standing pains; running always takes its running flinch (keeps
  running) or nothing; CQB walkers keep their moving pain sets; others just get the client's spine flinch. Unaware
  soldiers hit on patrol still turn toward it (React22). Harness hits 278 (+2).
- Idles over walks (user: "sometimes a idle will take precedence while a walk is happening, usually during like the
  search state"): lost contact plays MW19's look-around (mwe_look_*) and investigating plays standing idles, both
  one-shots; the search / investigate move then starts at once. Move.Step only cleared a standing clip that loops or
  has finished, so a playing one-shot rode along and he glided in the idle pose. Now any full-body clip that doesn't
  travel (clip.speed < 1) is cleared once he's being moved (transitions, prone, downed, upper-body acts excepted;
  travelling clips like the running flinches keep playing). Harness move 26 (+2).

### 0.38.66: footstep sounds culled and capped (2026-11-26, NOT yet seen in game)
Bench 0.38.65 (bench_50_battle_0_38_65.txt): 44 soldiers alive on average (30-31 in the 0.38.60 / .61 runs), so totals
aren't comparable straight: per alive soldier the server is flat (AI 5.7 -> 6.0 ms/s) and client animation is down
about a third (~10.6 -> ~7.0 ms/s, 0.38.61-62 LOD and IK work). Split: compose 41, bone build + gun 145, foley 88,
parts 11, slots + pose 12 ms/s; arm IK 53 us a solve (was 74-99).
- Foley was the standout (88 ms/s, ~94 us a soldier a frame): every step, the gear rustle before and after it and the
  odd rattle is an EmitSound, a few hundred a second with 44 soldiers, most out of earshot (gear plays 6-8 dB under the
  step). cl_foley play(): C.HearDist by sound level (75+ 2000, 70+ 1400, 66+ 1000, else 700, scaled by volume) from
  EyePos, at most C.MAX_PER_FRAME (10) a frame (C.Fire skips its surface trace once the frame's budget is used);
  C.RANGE 2500 -> 2000. Harness foley 20 (+3: cap, quiet far rustle dropped, loud far step kept).
- Launchers on the back (user: "on both it should be a little closer to the back when slung"): cl_gunhold M.BACK_DIST
  6.5 behind Spine4 (was 9) for the RPG-7 and the AT4.
- AT4 drop (user: "the at4's return to rifle anim ... the gun look kinda far forward compared to the hand"): the drop
  clips (sdr_com_exp_<stand|crouch>_rpg_drop_to_exp_stand[_pstl]) had a "gun leaves the hand" curve: after the
  dropgun note MW19's j_gun carries the dropped tube away, and the drawn rifle followed it. Now on the weapon-switch rule
  (gun_holds.py SWITCH): undriven, the weapon in hand all through; zz_jgun.lua patched with the same three entries.
  Harness launcher 57 (+3).
- Floating guns (user screenshot: "if an npc goes off my screen their gun can stay in place"): out-of-view soldiers (the
  0.38.61 LOD) skip placing their hand-placed models, which aren't parented: walking out of view, his gun hung where he
  left it, still on screen. cl_body hide_placed: gun, slung primary, launcher and the clip prop are hidden on the LOD's
  skipped frames and cheap composes; shown and placed again the frame he's back in view (0.3 s hysteresis on the way
  out, so he's well clear first). Harness animlod 26 (+3).
- Post-fight scrums (user screenshot: "sometimes after fights they still do this converge on a singlepoint ... its the
  last major bug"): after a fight several soldiers head for the same spot (each solo search starts at the exact last
  known position; investigating goes to the noise; squad bounds share a goal). Move.Spread spaced those goals only 56
  apart, under twice the arrival tolerance (30 x sqrt 1.5) plus a hull, so two could stop overlapping; sv_crowd then
  ghosts overlapping bodies (no collisions until apart) and nothing parted soldiers standing still: the overlap stayed
  for good and, ghosted, let more walk into the pile.
  - sv_crowd C.Unstack: two bodies overlapping a second (C.UNSTACK_AFTER) with an idle soldier (no goal, still, not in
    cover / prone / a clip / a vehicle / downed / surrendered / medic / bipod / room clearing): one of them (the higher
    index, or the idle one) walks to Move.Spread's free spot (tag "unstack"), his post going with him if he stood at it;
    never both of a pair, at most every C.UNSTACK_GAP (2 s).
  - Move.SPREAD_R 56 -> 72, spread rings 64 -> 80 per ring.
  Harness crowd 43 (+6).
- Oden with a foregrip (user: "the gun pose features a grip but the model doesn't, i simply wanna put one on the model"):
  tif_gunbake roster oden + attachment_vm_ar_asierra12_vertgrip01, re-exported in game, rebuilt (lod0 6582 -> 7072 tris,
  atlas 7 -> 8 tiles). gun_compile HAND_PIN keeps its hand points as they were (grip_v 11.365 -0.924 0.645, no grip_l
  from the grip part), gun_holds not rerun: same hold, same class weapon_tifmw_oden. Old Oden backed up in
  K:\jimmyproject\_addon_backups\2026-11-26_oden.
- Eyes (user: "how do we direct eyes rn" ... "ok do that"): only codport-retarget / modular faction models had eye code
  (sh_modular M.Eyes: 200 ahead of the head bone each frame); the four built-in factions (host-skeleton models) had none.
  Server: tif_soldier Think networks NW2Vector tif_look (shooting at, else tifAimAt, else tifFace; resent on a 32 u move,
  zero when there's nothing). Client npc/cl_eyes.lua TIF.Eyes.Update, from cl_body right after the bone build (on-screen
  soldiers only), within E.RANGE 900: the eyes frame = host head bone x a per-model offset to the faction model's "eyes"
  attachment (measured once, no extra bone build), target = the look point clamped to a 40 deg cone round the face's
  forward, else straight ahead; SetEyeTarget in the eyes attachment's space. M.Eyes steps aside for models it handles
  (tifEyesByBody). tif_eyes 0: off. Harness eyes 8 (new).
- Panic fire (user: "i love the retreating as it is right now ... however the no shooting makes it really awkward when
  forces then get close to each other for a push ... let broken people shoot panicked"): the retreat is unchanged (flee
  point, hiding, 12 s minimum, recovery in quiet, surrender off). sv_morale BrokenThink sets npc.tifPanic (cleared when
  the state leaves broken) and:
  - running, enemy seen within MO.PANIC_RUN (400): an over-the-shoulder burst every 1-2 s through the covering-burst
    path (tifCoverFire: the run-and-gun clips, back-left / back-right at 135 deg), still sprinting away;
  - hiding, enemy seen within MO.PANIC_HIDE (1000): aim mode, fires from the crouch (tifFire.want / aimPos).
  sv_weapon under tifPanic: spread x W.PANIC_SPREAD (3), bursts W.PANIC_BURST 6-12 (auto) / W.PANIC_SEMI 2-4, pauses x
  W.PANIC_PAUSE (0.45) on every gun kind, reloads x W.PANIC_RELOAD (1.5). No grenades / peeks / weapon switches (the
  brain's engage doesn't run). Harness morale 17 (+9).
- Upturned guns (user screenshot, EBR in an idle: "the guns kinda upturned ... mainly on some guns like the fal, but not
  the insurgent aks"): each baked gun's mesh is in its MW world model's right-hand frame, and MW's world models hold the
  hand at different angles per gun, in steps: barrel level for the AK family, pistols, LMGs, Uzi, RPG-7; 5 deg up for
  FAL, Oden, M4s, M13s, Kilo, SCAR; 10 deg up for EBR, AN-94, AS VAL, Bizon, Bruens, shotguns, SVD, SKS, Rytec; SVD /
  Rytec 5, SKS 3, MP5 4, MP7 10 deg sideways too (measured on the export tags and again on the compiled attachments).
  The baked-gun hold (gun bone x KR, calibrated on the AKM) showed each gun's offset as its tilt. cl_body: gun_pose wraps
  gun_pose_raw and turns baked guns by X = (AKM's barrel frame) x (this gun's)^-1 (gun_info frames from muzzle /
  tif_axis_b / tif_axis_u), about the wrist; cached per model, skipped under Bd.ALIGN_MIN (0.5 deg). Bd.GunPose is the
  corrected pose, so the left-hand IK follows; slings already used each gun's own frame. Harness gunhold 24 (+4).
- Group spawns (user: "do big formations spawn backwards" ... "make em a formation looking at me so fights are easy to
  setup"): spawn-menu Fireteam / Squad (tif_spawner) and tif_spawn_squad spawned facing "away", each turned radially from
  the player (backs to you, fanned out). Now TIF.FormationPoints (core/sv_spawn): the leader on the aimed spot, the rest
  in the squad's wedge slots (TIF.Squad.SlotOffset, TIF.FORMATION_SPACING 90) behind him on the far side, navmesh-snapped
  and room-checked, all facing the player with one shared yaw. tif_spawn_squad defaults to it (face "me"; "away" /
  "random" keep the old scatter) and its hold order faces the player too. Harness spawnform 9 (new).

### 0.38.67: soldier director and survival director (2026-11-26, NOT yet seen in game)
User: "copy its director and survival director for our mod, just a rlly simple like thing to dynamically spawn
soldiers ... replicate how left 4 deads zombies work but for soldiers (after fighting in an area the ... next area can be
chill) ... survival ones are self explanatory. but make sure they rlly come for ya". Ported from Horde Zombies'
hz_director / hz_survival onto TIF squads. New tif/director/sv_director.lua (TIF.Director) plus two admin spawnables
under Tactical Infantry, settings in the context-menu Edit Properties:
- Shared: spawns are navmesh area centres in a distance window from the nearest player, out of every player's sight
  (within ~0.6 x min distance counts as seen; otherwise a 0.25 view cone with a clear line), preferring the player's
  movement heading. Squads spawn in TIF.FormationPoints facing the player, role mix leader / rifleman / assault /
  support / marksman / rpg. Faction "auto" = the insurgents (else the first faction) hostile to the player's faction;
  "random" or any faction id works too.
- Intensity (L4D's stress): + damage soldiers do to players, + 8 per soldier a player kills, + 3 a second per engaged
  soldier within 700; x 0.93 - 1 each second.
- Hunting ("rlly come for ya"): every 3 s each hunting squad is given the nearest player as a confirmed contact on every
  member (like a callout, P.Contact + Stimulus) plus squad knowledge, and an advance order on him at the rush pace (run
  until ~700 out, then the aimed walk). Re-routed only when he has moved 250+ and the squad hasn't been in contact for 4 s,
  so fights aren't interrupted.
- Recycling: soldiers far past the spawn window (not engaged) and hunters with no progress for 25 s are removed when
  out of sight (in survival they go back into the wave).
- tif_director (Soldier Director): buildup keeps up to N ambient squads ahead of the players (60% get a patrol route) and
  sends 1..N assault squads that hunt every 60-120 s; intensity >= peak (120) -> peak, no spawns; below relax (25) ->
  relax for 40 s, no spawns; then buildup again but calm: the next ambient squads stand guard (no patrols) until the next
  assault. Max alive 24. Removing it or unticking Active removes its soldiers.
- tif_survival (Soldier Survival): 10 s lead-in, then waves of hunting squads: wave n = start size x (1 + growth%)^(n-1)
  (6, +25%), up to max alive at once, squads from different spots; a cleared wave starts the break (25 s). HUD top right:
  WAVE n, run clock, next-wave timer. All players dead for 6 s resets the run.
- Harness director 48 (new). The bladew0rks formatting pass had left 15 suites failing on exact-text checks (code
  split over lines, comments removed, Act -> Action): run.py now retries a failed plain find on source text with
  whitespace collapsed (_ws.lua; `--strict` skips it), and recoil / vehclass / trans / hl2npc / hips checks updated to the
  new code. All suites pass.

### 0.38.68: soldiers survive saves (2026-11-26, NOT yet seen in game)
User: "do they respond well to being saved ... any spawned soldiers". They didn't: GMod's save (gmsave -> duplicator)
merges a SENT's whole Lua table into the save (contacts, squad, action, cover, path) and JSONs it, then on load
spawns a fresh soldier (new look rolled) and pastes that stale table and the network vars (stance, awareness) back over
it: lost squads, dead references, odd states. Same path for the Duplicator tool / AdvDupe.
- New core/sv_save.lua (TIF.Save). tif_soldier:OnEntityCopyTableFinish -> S.Strip: drops the live table, DT,
  host bodygroups / skin / flex / bone manips; keeps position, class, physics; adds a plain record (TIFSave):
  faction, role, look (visual, parts, skin, bodygroups), health / max, primary / secondary / launcher + rockets left,
  post + yaw, squad id, leader flag, player-led flag, squad order (free / hold / follow / regroup / advance / patrol
  with pos, yaw, pace, route).
- Dead, dying, downed, surrendered / captive and seated (tifVeh) soldiers are saved as skip records and not pasted.
- duplicator.RegisterEntityClass for tif_soldier and every SENT based on it (at InitPostEntity / OnReloaded): S.Create
  spawns him clean with the saved role / guns, then puts the saved look back (only if the model is valid, usable on the
  host and still one of the faction's models; modular factions keep their assembled model), health, rockets, post.
  0.3 s after the paste, S.Rebuild re-forms squads by saved id with the same leader and order (patrols keep their
  route); squads that followed a player join the loading player's squad and follow him. Soldiers saved without a squad
  auto-join as usual. Faction pack gone: skipped with a warning.
- Saves made before this load as fresh soldiers of the same faction and role (the stale table is ignored).
- Not kept: the fight itself (contacts, awareness, cover, reloads, actions), which starts over.
- Harness savegame 53 (new). All suites pass.

### 0.38.69: Onslaught survival mode; survival soldiers harder to break, go for players (2026-11-26, NOT yet seen in game)
- User: "add horde zombies "hell" mode as "onslaught" and let it follow the same premise". tif_survival gets an
  Onslaught toggle (Edit Properties); toggling it mid-run restarts the run. Ported from hz_survival's hell mode onto
  squads (D.ONSLAUGHT): no waves, no breaks, a spawn bank instead. Starts with 2 in the bank and fills at
  0.15/s + 0.08/s per minute (max 1.2/s, banked up to 8). A squad (squad min-max, capped by room) spawns from it every 2 s
  once it can afford one. Max alive at once ramps 25% -> 100% of MaxAlive over 8 minutes, then +10%/min up to 2x.
  Heat level every 90 s (HUD: ONSLAUGHT n plus the run clock). Surges every 75 s (2 s sooner per minute, floor 40 s) add
  4 + 2 x heat to the bank. Soldiers spawn with +2% health per minute (cap +50%). Recycled soldiers go back into the bank.
  Same hunt as waves (confirmed contact on the player every 3 s, rush advance).
- User: "survival soldiers should get less morale factors. and prioritize engaging you". npc.tifMoraleScale scales
  morale LOSSES (MO.Add negatives: casualties, hurt; drift: suppression, outnumbered) - gains and recovery unchanged.
  npc.tifPreferPlayers adds to a player's score in P.Primary (visible +1000, age, distance, current +150). Survival /
  onslaught soldiers get D.SURV_MORALE 0.4 and D.SURV_PREFER_PLAYERS 800: a visible player always beats a visible NPC; a
  player only heard recently still loses to an NPC shooting at them in plain view. Director squads unchanged.
- Harness director 66 (+18). All suites pass.
- Round cue (user: "make this the round noise/onslaught noise (its a sound of like soldiers getting ready and yelling
  over each other the next block over)", "make sure its ogg"): sound/tif/director/walla_alert.ogg (TLOU
  cap_walla_russ_alert_01, 36 kHz -> 44.1 kHz stereo, Vorbis, 100 KB from a 1.28 MB wav; local-only game rip). D.Cue
  broadcasts tif_surv_cue; tif_survival clients play it 2D (surface.PlaySound) on each new wave, the onslaught start and
  every surge. Harness director 70 (+4).

### 0.38.70: MW clip table split so soldiers animate in multiplayer (2026-11-26, NOT yet seen in game)
- User: "soldier anims bugged in mp". On a friend's p2p server the client logged "datapack file entry has no data!
  (addons/addon/lua/tif/gta/clips/mw_male.lua)" and "Couldn't include file 'tif\gta\clips\mw_male.lua' - File not
  found or is empty" on every join: the 5.4 MB clip table is too big for GMod's server -> client Lua send, so clients
  had no MW clip data (singleplayer reads it from disk, so it only broke in MP). The next biggest TIF Lua file is 150 KB.
- tif_mw_build write_clip_parts: the table goes out as mw_male_p01..pNN.lua, each <= ~120 KB and <= 600 roles, each a
  RegisterClips part ({ part = i, parts = N }, merged by sh_core merge_parts as before); a rebuild deletes the old
  single file and stale parts. The current table was split with it: 46 files, 4332 clips, checked identical to the old
  table in LuaJIT. read_clip_lua / gun_holds read_clips / car_seat_harness read the parts; the harness runner joins them
  into _mw_male_all.lua (git-ignored) for CLIPS. SMH baker copy of tif_mw_build synced. Backup of the old file and the
  old SMH copy: K:\jimmyproject\_addon_backups6-11-26_mwmale_split.
- The server you join must run this version: its own copy is what clients download.
- Harness luasize 98 (new): no addon Lua file over 200 KB, parts numbered and complete, all 4332 clips. All suites pass.

### 0.38.71: clip parts merge once (2026-11-26, NOT yet seen in game)
- User: "do it and keep a backup". With 46 parts, every RegisterClips part re-merged all parts so far and rebuilt and
  sorted the clip list plus every clip set: 46 list builds of up to 4332 names at load. sh_core merge_parts now adds only
  the new part into TIFG.ClipMerged[pack]; the list and sets are built once, when the last part is in. A part that
  registers again (Lua refresh) re-merges from scratch, so clips it dropped go away. An incomplete pack keeps its clips
  but has no list yet and counts as missing (MissingPacks), as before.
- Offline (LuaJIT, all 46 parts, parse included): 276 ms -> 156 ms; same names, order, network indexes, clip data and sets
  as the old code. Backup of the old sh_core.lua: K:\jimmyproject\_addon_backups\2026-11-26_mwmale_split\sh_core.lua.
- Harness clipmerge 12 (new). All suites pass.

### 0.38.72: searching soldier lost his search after a squad order (2026-11-26, NOT yet seen in game)
- log_sv on def_rusalka: "sv_brain.lua:222: attempt to index field 'tifSearch' (a nil value)" every think. SQ.SetOrder
  clears every member's tifSearch, but a member already SEARCHING kept that state and read tifSearch.start next think.
  Seen with the HL2 AI Replacer addon, which gives squad orders often (assault routes, scripted schedules).
- sv_brain.lua: a searching soldier with no tifSearch starts a fresh search on his last contact (one condition changed).
  Nothing else touched.

### 0.38.73: bone reads back on GetBoneMatrix (2026-11-26, NOT yet seen in game)
- User: "transition to ragdoll is harsher now", "im also seeing jittery ingame movement", "i think the lua split might
  have been a issue". Bench 0.38.72 (bench_50_battle_0_38_72.txt) against 0.38.65: server AI 264 -> 166 ms/s, client
  animation 312 -> 220 ms/s, foley 88 -> 38 ms/s, but [FAIL] layer writes overwritten 46.5% (was 0.1%) and [WARN]
  soldiers missing layer slots, peak 20, 350 refresh requests (was none).
- The split is not it: the 46 parts merge to the same 4332 clips (checked in LuaJIT against the old file), load in the
  same order, nothing else registers mw_male, and the slot code (TIFRefreshSlots, check_slots, write_slot) is unchanged
  since the clean 0.38.65 bench. The 0.38.65 bench ran before the bladew0rks pull, so his 18 commits and 0.38.66-.72
  are the suspects for the layer slots: not found yet, bisect pending.
- bladew0rks' ccd64f2 / 377102a moved bone reads to the engine's Entity:CopyBoneMatrix (TIF.CopyBone, sh_pose read).
  GetBoneMatrix rebuilds stale bones before it reads; CopyBoneMatrix appears to copy the cache. The death path clears
  the cache (DyingThink InvalidateBoneCache) and then reads every bone for the corpse pose and velocities, and the
  modular retarget reads the host's bones every frame. TIF.FAST_BONE_COPY (false) now gates CopyBoneMatrix in
  TIF.CopyBone and sh_pose read: back on GetBoneMatrix everywhere. Backups: K:\jimmyproject\_addon_backups\2026-11-26_copybone.
- All suites pass. Needs a look in game (ragdoll handoff, moving soldiers) and a new bench.

### 0.38.74: calm-idle watch (2026-11-26, NOT yet seen in game)
- User: "sometimes soldiers will assume the straight up calm idle, in times its not appropriate either. add some sort of
  watch for that before i do another bench". The client's leg_targets falls through to the relaxed set's idle whenever
  the soldier isn't in aim mode, isn't crouched and has no action clip; awareness only changes stairs / slopes (and the
  alert set in aim mode), so an alerted or fighting soldier in relaxed mode stands in the calm idle.
- New npc/cl_calmwatch.lua (TIF.Body.Calm), run from compose on the chosen leg clips: an episode is the dominant leg
  clip (>= 50% of the leg weight) being a calm idle (relaxed / relaxedFlash / any weapon kind's relaxed set, variants
  included) for 0.4 s+, standing (< 40 u/s), no action clip, not prone / dying / seated, while alerted, engaged or
  searching, or fired in the last 4 s, or hit in the last 3 s, or broken. Each episode logs to data/tif/log_cl.txt
  ("[calm idle] #idx faction: reasons, mode, weapon, speed, morale, cqb, slots, clip"; 10 s per soldier, 30 a minute).
  tif_calm_watch 0 turns it off. Stats: calmFrames, calmEpisodes, calmNow, calmWhy.
- tif_devtools bench: client collects the episode / frame deltas, the peak at once and the reasons; the report adds
  [PASS] no calm idle while alerted, or [WARN] "Calm idle while alerted / fighting" with counts and the top reasons.
- Harness calmwatch 19 (new). All suites pass.

### 0.38.75: no calm idle while fighting (2026-11-26, NOT yet seen in game)
- Bench 0.38.74 (bench_50_battle_0_38_74.txt): layers clean (0.0%, no missing slots), [WARN] calm idle 29 episodes, peak
  7 at once; log_cl.txt: every one engaged, mode relaxed, standing (speed 0-14), the reb_stl_patrol_idle01-06 calm idles;
  18 steady (most just fired or hit), 11 broken.
- Causes: (1) sv_brain's gun-down run rule relaxes an engaged soldier with a run / sprint goal who isn't firing, without
  checking he moves: waiting on a path, blocked or in a crowd he stood relaxed; (2) sv_morale BrokenThink sets relaxed
  every think and stands him up while his flee goal is > 80 away, also when he isn't moving yet.
- B.NoCalmStand (after the mode rules, before low ready): engaged or alerted, relaxed, standing stance, no action, not in a
  vehicle / downed / surrendered, under 40 u/s for 0.3 s (B.CALM_STAND_AFTER; run starts keep their relaxed start): aim
  mode back, or for a broken soldier a crouch (cowering). Unaware, suspicious and searching soldiers keep the calm idle.
- Harness calmstand 18 (new). All suites pass.

### 0.38.76: broken soldiers cower at any awareness (2026-11-26, NOT yet seen in game)
- Bench 0.38.75 (bench_50_battle_0_38_75.txt): calm idle 29 -> 1 episode (peak 1, 2 soldier-frames), layers clean.
  Per alive soldier AI 6.42 ms/s (5.76-6.01 in the last runs), client animation 6.20 (6.21); frame time 36.7 ms with
  47.5 alive on average, more of them aiming.
- The one left: a broken soldier whose awareness had dropped to searching, standing relaxed. B.NoCalmStand now also
  takes any broken soldier (cowers in a crouch). Harness calmstand 19 (+1).

### 0.38.77: broken soldiers shoot back from farther (2026-11-26, NOT yet seen in game)
- User: "can we up the range of the broken shots, just so they arent like watching and still participate in the battle
  a bit". MO.PANIC_RUN 400 -> 1200 (over-the-shoulder bursts while fleeing), MO.PANIC_HIDE 1000 -> 2500 (panic fire
  from the crouch). Still needs the enemy in sight (or seen within 1 s); panic spread x3, short pauses, slow reloads
  unchanged, so at range it's mostly suppressing fire. Harness morale 19 (+2, ranges updated). All suites pass.

### 0.38.78: director radios, faction dropdown (2026-11-26, NOT yet seen in game)
- User: "make the director models a hl2 radio instead of info player start and make the faction select a little dropdown
  instead of whatever weird "auto" thing it is rn". tif_director / tif_survival use models/props_lab/citizenradio.mdl,
  always drawn (the director's status text still only with the physgun / toolgun out), placed on the surface facing
  you. Faction in Edit Properties is a Combo from TIF.FactionComboValues() (sh_factions): "Auto (hostile to you)",
  "Random hostile", then every faction with models / variants that isn't hidden, labelled "Name (id)" like the settings
  panel. Harness director 78 (+8). All suites pass.

### 0.38.79: GTA-era dead branches and subclass entities removed (2026-11-27, NOT yet seen in game)
- User: "just remove the dead branches, unused entities". Every soldier runs on the one ValveBiped host (mw_male:
  HostFor always returns it, it's the only registered character, no other addon registers one), so these never ran:
  - Host swapping: ENT:TIFSetHost, the Think block that swapped back after a GTA-only action, the Action.Play / Clip
    fallback to the home host, the prone and MW22-react host checks.
  - IsVB / tifHostId == tifHomeHost terms in 15 server checks (cover, hits, bipod, door, melee, passive, prone, search,
    shield, transitions, traversal, run-and-gun, weapon draw, squad hand signals, corpse ragdoll). The checks keep their
    clip-exists tests.
  - TIF.VisualUsable / UsableVisuals / VisualCheck (sh_packs: the GTA bone-map test, always true on the VB host) and the
    8 s map-load check; the faction model lists are used as they are. tif_devtools cl_visual_check / tif_visual_check
    removed with it. The client still swaps in another faction model when one fails to create.
  - cl_body: the st.vb flag and every non-VB path: GTA weapon sets (st.wset, A.WeaponSet, A.PitchPose, gtg_aim_pitch /
    gtg_hold_gait poses), ub_targets' GTA half, flinch(), the GTA prone path (prone_enter / prone_exit / prone_update,
    PRONE_SEQ), the bonemerged gun (make_gun's vb arg, measure_gun_offset, gunOff / gunGripInv), the host-change reset
    in ensure_parts. cl_feet drops state.vb.
- tif_soldier_militia / tif_soldier_pmc removed: "militia" / "pmc" are hidden aliases of insurgents / usmc and both
  spawn paths fall back to tif_soldier with the faction set. Old saves / dupes with those classes paste as tif_soldier
  (sv_save registers S.OLD_CLASSES and falls back when the class is gone).
- 28 files, -571 / +109 lines. Backup of the whole lua folder and the devtools files:
  K:\jimmyproject\_addon_backups\2026-11-27_deadcode. Harness animlod / trans checks for the removed paths updated;
  all suites pass, every changed file parses.

### 0.38.80: Russian voices for the Russian Ground Forces (2026-11-27, NOT yet heard in game)
- User: "ok i got some more voice variants for the rgf" (tfa_vox_spetsnaz_soldiers_bocw_2495443964: Black Ops Cold War
  Spetsnaz, 4 voices) + "make them ogg for file size". Converted to sound/vo/tif_rgf1..4 (one pack per voice, so a
  soldier keeps one voice), files renamed to <category><n>.ogg, 44.1 kHz mono Vorbis: 170 lines, 14.5 MB of wav -> 2.2 MB.
  Local-only content from another Workshop author, like the other voice packs.
- sh_voices V.RGF_EVENTS: contact = spot, reloading = reload, grenade_out / grenade_incoming = grenadeout / grenadein,
  man_down = casualty, kill / pain / death, moving = moving, advance = move + flank, attack / swear = taunt. Suppressing,
  cover me, backup, retreat, clear etc. use V.FALLBACK. Voice 4 has no kill lines (stays quiet on kills).
- Russians: voices = tif_rgf1-4 + mercenary (1 in 5 keeps the old voice).
- Harness rgfvoice 51 (new): each pack builds from the real files, every core event has lines, all ogg. All suites pass.

### 0.38.81: Marine breachers carry the full-size shotgun too (2026-11-27, NOT yet seen in game)
- User: "let marines also use the full size shotgun". USMC breacher primary: m680_breach + m680 (the full-size Model
  680, infantry tier, unused by any faction until now). USMC Woodland copies the USMC loadouts, so it gets it as well.
  Loadout suites (russians, guns, marpat, test, wclass) pass.

### Gun bake from the hand: tif_gunbake_held (2026-11-27, tif_gunbake dev addon + tools, NOT yet run in game)
- User: "can you add a command where i can tif_gunbake whatever im holding and then tell you where i want it used?"
- `tif_gunbake_held <id> [rifle|smg|lmg|shotgun|pistol|rpg|dmr] [force]` (single player / listen host): exports the MW
  base gun in your hands as it is (attachments you set in its customize menu), mesh then sounds, to
  data/tif_gunbake/<id>.json, <id>_smd.txt, <id>_sounds.json, the same files a roster bake writes. Kind left out:
  guessed from the gun's hold type / category (launcher, shotgun, handgun, LMG, SMG, marksman / sniper -> dmr, else
  rifle). Suppressed when an attachment class has silencer / suppress in it. Ids are lowercase [a-z0-9_]; a roster id
  needs force. Also writes data/tif_gunbake/<id>_roster.txt: the add{...} line for sh_roster.lua so the bake can be
  repeated.
- tools/guns/gun_holds.py <id> ...: only those guns' holds (j_gun place + left-hand fingers), clip tables untouched, a
  gun without IK tags gets the average of the stored long-gun holds. ~3 s instead of 25-35 min; checked on m680
  (identical to its stored hold). The copy in K:\jimmyproject\tif_guns is an older version: use the repo's tools/guns.
- After "use <id> for <faction> <role>": batch.py <id> (decimate, textures, compile), tools/guns/gun_holds.py <id>,
  batch.py --lua <id> (weapon def with holds and sounds), add it to the faction's loadout, roster line into
  sh_roster.lua, harness.
- Backups: K:\jimmyproject\_addon_backups\2026-11-27_gunbake_held. Repo copy tools/gunbake_addon updated.

### 0.38.82: fall damage, hard landings and stumbles (2026-11-27, NOT yet seen in game)
- User: "do the fall damage first" (proposal: landing / stumble by height, then ladders). Planned traversal drops
  (mwtr_drop_*, up to 210 u) were already animated; falls the soldier didn't choose did nothing.
- New anim family fall (manifest fall_family, 23 roles, built with tif_mw_build --only "mwfl_*" into
  models/tif_mw/mw_male_fall.mdl): mwfl_land (iw9_mp_stand_jump_land), mwfl_land_<1-9> (iw9_mp_strafe_jog_jump_land_<n>),
  mwfl_stumble<1|2>_<2|4|6|8> (intd_com_exposed_stumble0<i>_<d>), mwfl_stumble_<jog|run|sprint><1|2>
  (reb_com_stumble_<g>0<i>). Clip table 4332 -> 4355, every existing clip unchanged (compared in LuaJIT).
- New tactics/sv_fall_mw.lua (TIF.Fall), fed by ENT:OnLeaveGround / OnLandOnGround: drop = height left - height landed.
  Under 120 u nothing; 120-250 hard landing (stand / moving direction clip), no damage; 250-450 stumble, 10-40 fall
  damage, no fire ~1 s; 450-700 heavy, 40-90 damage (the casualty system can down him), stumble if he's still up;
  700+ dies (1000 DMG_FALL). Moving soldiers get the jog / run / sprint stumble and keep going; standing ones stumble
  toward the way they were falling. Skipped: traversal (tifTrav), helicopter riders, vehicles, blast knockdowns,
  downed, surrendered, prone, dying. tif_fall_damage 0/1, tif_fall_damage_mult. Falls over 250 u log a fall event.
- Not done yet: the new clips aren't in the gun-hold tables (zz_jgun*, gun_holds.py full run, ~30 min, rewrites files
  the game hot-reloads), so during a fall clip the gun follows the hand. Run it when out of the game.
- Harness fall 26 (new); luasize / clipmerge clip counts 4355. All suites pass. Backups:
  K:\jimmyproject\_addon_backups\2026-11-27_fall (clips, characters, models/tif_mw).

### Gun tables per clip: gun_holds.py --clips (2026-11-27, tools)
- User: "whys the entire gun hold thing have to rebuilt for only a couple animations?" It didn't need to: gun_holds.py
  always re-read every source (~2,600 seanims) and rewrote zz_jgun / zz_jgun_h* / zz_gunlow from scratch.
- `gun_holds.py --clips <role pattern>[,...]`: only those roles' sources, merged into the existing tables (their old
  entries replaced); the start / stop gun-low table is redone when a pattern covers mwt_stop_ / mwt_start_ roles.
- Every table write goes to <file>.tmp and is swapped in (os.replace): the game never hot-reloads a half-written or
  empty table, so it's safe to run while playing (full runs too).
- The hold entries depend on each weapon family's grip spot (median wrist spot over the family's steady clips), so a
  subset measured on its own drifted (4 crouch hand-signal entries). A full run now saves the spots to
  K:\jimmyproject\tif_guns\build\grip_spots.json and --clips uses them; without the file it asks for a full run.
- Seeded with one full run (4133 sources, 78 undriven, 915 hold, 166 gun-low; the 23 fall clips drive the gun bone
  normally). Check: --clips over 203 existing roles (jumps, running flinches, hand signals, stops, falls) reproduced
  all three tables exactly, in 39 s.

### 0.38.83: guerrilla style for the Insurgents (2026-11-27, NOT yet seen in game)
- User: "propose getting the rebel clips as an unexperienced guerilla styled option for only certain factions" ->
  "build it for insurgents ... mostly similar to how they are now, to keep fights fair, but i do like slightly more
  frequent blind fire. just to see the animations a little bit more".
- Faction style: insurgents style = "guerrilla", styleChance = 0.7 (the militia alias inherits it). tif_soldier rolls
  tifGuerrilla per soldier (NW2Bool tif_guerrilla); sv_save keeps it.
- New anim family guerrilla (manifest guerrilla_family, 44 roles, models/tif_mw/mw_male_guerrilla.mdl), all MW19
  reb_com: mwc_<ls|rs|cr|lc|rc|st>_gblind<n> = reb_com_cover_<type>_wild_fire<n> (5-7 per cover type),
  mwgr_aim = reb_com_exposed_aim_5 + mwgr_aim_tw1-4 (its twitches), mwgr_sprint1-3 = reb_com_sprint_loop01-03.
  Clip table 4355 -> 4399, existing clips unchanged; gun tables by --clips (5 of them let go of the gun).
- Cover (sv_cover_mw): MW.BlindRole gives guerrillas a random wild-fire clip for the cover type (trained / pistol /
  missing clips keep blind1 / blind2). Guerrillas blind-fire from suppression 0.4 (trained 0.55, aggression gate kept)
  and 1 in 5 of their pop-outs (MW.GUERRILLA_BLIND_POP 0.2) is a blind burst instead. Same blind-fire path (tifBlind),
  so accuracy and damage are unchanged.
- Client: sh_anim L.gaim (the aim set with mwgr_aim as idle and its twitches) and L.gsprint; cl_body uses them for
  guerrillas (standing aim on the base aim set; relaxed sprint, one loop per soldier by idleVar).
- Not changed (user: keep fights even): accuracy, bursts, morale, tactics, formations.
- Harness guerrilla 22 (new); luasize / clipmerge counts 4399. All suites pass. Backups:
  K:\jimmyproject\_addon_backups\2026-11-27_guerrilla (clips, characters, models/tif_mw).

### 0.38.84: survival stages, survival soldiers press in, downed soldiers' RPG stays on their back (2026-11-27, NOT yet seen in game)
- User: "does survival ramp up in progression? enemy type" -> stages (assault first: "assault soldiers usually carry
  smgs or carbines"), "build it without boss waves for now". Before: only numbers ramped; roles came in a fixed
  order, so survival's 3-man squads were always leader / rifleman / assault.
- sv_director D.STAGES (level = wave, or heat level in onslaught): 1-2 guards + assault; 3-4 + riflemen, support;
  5-6 + marksmen, AT (rpg), squads +1; 7+ + breachers, a leader in every squad, guerrillas thinned to ~35% (half of
  them fight trained), +15% health. Roles drawn from the stage's weighted pool (D.StageRoles), so squads vary;
  D.SpawnSquad takes a role list. tif_survival "Stages" toggle (on by default; off = the old fixed order).
- User: "they would still kinda take cover/almost hide from me in survival, make them at least try to get within
  engagement sight and range so its like black hawk down esque standoffs". Survival soldiers get npc.tifPress:
  CB.Seek turns down cover they can't shoot from; in cover, unseen for CB.PRESS_UNSEEN (6 s) they exit ("pressing")
  and don't take cover again for CB.PRESS_COOLDOWN (10 s); the brain's lost-contact time counts from the last
  sighting (the director re-hears the player every 3 s, which kept it under 3 s). Once they see you the normal
  preferred-range advance / back-off holds them at their range: they fight it out instead of sitting hidden.
- User: "fix at soldiers who go down having their rpg float in their last standing position". Going down (and
  surrendering) clears TIFWeapon; cl_body only ran TIF.GunHold.Post (slung launcher / back rifle placement) inside
  `if IsValid(st.gun)`, so the slung RPG stayed where he stood. Post now runs every composed frame (bones set up
  when there's no gun in hand).
- Harness director 96 (+18), launcher 58 (+1). All suites pass. Backups: K:\jimmyproject\_addon_backups\2026-11-27_stages.

### 0.38.58: tracers from the muzzle, guns in the new clips, cheaper feet, prone bipod clips (2026-11-26, NOT yet seen in game)
User: "hl2 default tracers not coming out of the gun", "our new clips [don't] carry gun bone points, the guns go 90
degrees during some of them", "i feel chuggier, how much does it affect performance?", "the bipod prone is like
actually a start prone animation ... let this anim play when they do it from standing. but if they need to bipod
while already prone, do like a shift to the bipod idle. dont let it affect how often they bipod".
- Tracers: FireBullets drew HL2's tracer from the server's shot origin (W.MuzzleSrc: a point estimated beside the body;
  the gun only exists on clients). Now Tracer = 0 and each bullet's callback sends effect tif_tracer (soldier, start,
  hit); lua/effects/tif_tracer.lua starts HL2's "Tracer" at the client's real muzzle (Bd.MuzzleWorld, the muzzle
  flash's lookup), the server point when the gun isn't there. Same effect count as before.
- Guns in new clips: zz_jgun.lua's TIFG_JGUN_UNDRIVEN (clips whose gun bone isn't usable: MP locomotion) is built by
  tools/guns/gun_holds.py classify() from the clip table; the new MP clips (crouch starts / stops, prone shimmy) weren't
  in it, so the gun followed their unkeyed gun bone (90 deg off). classify() re-run with the new clips.
- Prone bipod: measured: mwb_prone_in (sdr_com_prone_lmg_setup_in) goes from standing (pelvis 36) to the bipod
  (5.8), mwb_prone_out the reverse. Client: an LMG gunner getting down with his weapon up plays mwb_prone_in as the
  get-down (2.87 s vs mwp_down 2.93: the server's prone timing is unchanged) and lands on the bipod; getting up off a set
  bipod plays mwb_prone_out (stretched to the server's get-up). Already prone, set-up / pack-up are a cross-fade between
  the prone aim and the bipod aim (no clip; the old reversible in / out states are gone). When they bipod is unchanged
  (lying still and aiming, the 1.2 s hold). sv_bipod_mw B.PRONE_SET_AFTER 2.9 -> 0.4 (braced after the shift).
- Performance (cl_feet): the pelvis drop and the lean each walked the ~60 bones under the pelvis; now one pass with one
  combined matrix. The lean counts against the per-frame cap too (it had none), tif_foot_ik_max default 12 -> 8, the
  callback returns at once for soldiers not in the cap (st.feetOn). TIF.Prof counters cl_feet_us / cl_feet_n; tif_bench
  (dev tools) prints "Foot IK / turn lean" ms/s and us per soldier.
- Harness: fire 20 (+2: no engine tracer, tif_tracer per bullet), bipodseq 17 (new prone timing, stand-to-bipod get-down,
  bipod-to-stand get-up, shift while prone), feet 12 (cap 8). All suites pass.

### 0.38.57: downed soldiers die in their downed pose (2026-11-25, NOT yet seen in game)
User: "can you fix deaths during downed state putting them in the prone death pose". Killing a downed soldier skips
the death clip (sv_hits_mw Death: tifDowned), and the corpse is posed from the server's bones. While downed the
server held the prone idle (BodyUpdate: downed counted as prone for hitboxes), and TIFMakeCorpse's "pose the action
first" read the bones already built that tick (the melee A-pose cause, 0.38.35): so the ragdoll started from the
prone idle, not the last stand / downed clip the clients showed.
- entities/tif_soldier.lua BodyUpdate: downed with an action playing (last stand fall / lie / crawl, the help-up
  clips, the non-MW downed clip): the server plays that clip's sequence at the same cycle as clients (loop or one-shot;
  tif_act_cycle when fixed), so its bones are the downed pose when he dies. Hitboxes follow the downed pose too.

### 0.38.56: locomotion pass (MPM comparison), prone shimmy, pistol kick fix (2026-11-25, NOT yet seen in game)
User: "go ahead with the locomotion fixes, still with my emphasis on performance. one of the pistol fires recoils
forward and like downish so fix that. and add prone shimey from mp if there arent any sp ones, as the slow glide turn
is inelligent". Compared with MPM (K:\modern_player_motion): TIF already had root-motion starts / stops / turns,
reversals, stance clips, a shared speed-synced foot phase, stair / slope sets and prone tilt.
- Recoil kicks: measured every built kick (right hand motion at its peak); 28 of 227 pushed the gun forward / down
  (all four pistol bursts' first shot - the gun settling out of the raise - and burst ends of rifle / lean / one
  shotgun slice). manifest _KICK_SKIP drops them; 199 kicks remain (pistol 10, all back and up).
- Prone shimmy: no AI / SP prone turns exist; MW19 MP's sdr_mp_prone_turn_90_l / _r (what MPM uses) as mwp_turn_l / _r on
  the prone pelvis. sv_trans_mw T.ProneTurn: settled prone, 30+ deg off, not on the bipod: the turn clip warped onto
  the wanted yaw (one clip up to 135, the rest next time), combat rate 1.5. sv_move lets prone soldiers through to
  T.Turn; cl_body plays mwp_turn_* over the prone set. Below 30 deg the old slow rotation still does it.
- New transition sets (aimove family): rifle sprint = MW19 AI run starts / stops (sdr_com_exposed_run_exit_<n>,
  run_arrival_<l|r>_<n>: TIF's sprint loop is the AI run) as mwt_start_run / mwt_stop_run (turning stops like calm /
  alert); crouched walk / fast = MP crouch strafe starts / stops (TIF's crouch loops are those MP strafes) as
  mwt_start|stop_cwalk / cfast. move_set: crouched rifle -> cwalk / cfast, rifle sprint -> run.
- Combat moves get starts / stops: maneuver, move, close (and flee / formation stops; a breaking soldier still bolts
  with no start). Cover and CQB keep theirs.
- Stop foot: cl_body Bd.StopFoot swaps the stop clip for its other-foot variant when that's the foot the walk loop
  plants next (from st.phase; plant data, else the clip's _l / _r name). Start hand-off: Bd.FootHandoff sets the loop's
  foot phase from the start clip's last plant (was: the loop resumed wherever its phase was).
- tif_mw_build: one-shot starts / stops without footstep notes get detect_steps plants + Foot tags (were all 0,0;
  also gives the foley footsteps on them). --only takes comma-separated patterns. PREFER_SOURCE (manifest): a clip's
  source folder first. Found while checking the feet: many _l / _r stop pairs were byte-identical in the first source
  the builder found (MW19's run arrivals, MW22 export 2's jog and slow-walk stops), so "both feet" stops were one clip
  twice. The manifest's _foot_pairs() hashes each mwt_stop_ pair across the source folders and prefers the first where
  the two differ (10 pairs: run arrivals, jog stops, slow-walk stops). Pairs identical everywhere stay as they were
  (the stop-foot swap then keeps the clip it has).
- Foot IK (npc/cl_feet.lua, TIF.Feet): on the host in its bone build, reusing cl_gunhold's two-bone solve
  (GunHold.SolveTwoBone): ground under each foot (one trace each, every other frame, smoothed), pelvis dropped to the
  lower foot, legs solved. Only standing / walking (fades out 60-170 u/s), not prone, only with no action or a
  transition / cover / stance clip, within tif_foot_ik_range (1200), at most tif_foot_ik_max (12) soldiers a frame.
  tif_foot_ik toggles it.
- Lean into turns: running (> 120 u/s) soldiers roll into the turn from yaw rate x speed, max 9 deg, smoothed
  (tif_turn_lean). Same callback, a few multiplies.
- Harness: trans +13 (run / crouch starts and stops, combat tags, cover excluded, prone shimmy incl. bipod), feet 12
  (range, speed fade, prone / melee off, transitions on, per-frame cap, lean direction, toggle). All suites pass.
- To watch: the prone shimmy's pivot (centred on the prone pelvis like the crawls), crouch stops (MP, in place: the
  warp carries the last <= 45 units), foot IK on stairs (pelvis drop limit 16), the lean amount.

### 0.38.55: woodland Marines are the Marines for relations (2026-11-25, NOT yet seen in game)
User: "marpat woodland dudes shoot at me, they should be identical to normal us marines". The user's
tif_player_faction is `operators` (TIF Faction Pack), whose ally list (like the CoD factions') names usmc / pmc but
not the new usmc_woodland, and 0.38.54 only listed usmc in the woodland faction's own allies.
- core/sh_factions.lua: TIF.RelationId(id) - the alias's faction, then def.relationsAs if set. FactionRelation compares
  and looks up ally / neutral lists by it, so a faction with `relationsAs = "usmc"` is the Marines to everyone (allies,
  neutrals, enemies, the player's faction, other packs' lists) without anyone listing it.
- usmc_woodland: relationsAs = "usmc" (instead of allies = { usmc }).
- tactics/sv_cover_mw.lua: the "no frag near friendlies" check counts any non-hostile soldier (was same faction id
  only), so allied factions don't frag each other either.
- Harness marpat 33 (+7: woodland vs usmc / operators both ways / usmc's neutrals / enemies / the pmc alias). All pass.

### 0.38.54: US Marines in MARPAT woodland, a separate faction (2026-11-25, NOT yet seen in game)
User: "add these usmc marpat woodland as a seperate faction" (Workshop 3466197531, app 222880: an Insurgency retexture
of the security team).
- The pack's security_light / standard / heavy are byte for byte the INS2 models the starter Marines are built from
  (same VVD, textures, bodygroups); 4 of its textures differ (uniform top, helmet cover, both trousers) and one VMT
  (pants_02 $color2 0.85 vs 0.75). VPK = the loose files.
- tools/factions/make_marpat.py: materials/models/tif/ins2/usmc_wood/ (17 VMTs: the 4 woodland diffuse maps here,
  everything else pointing at the base Marines' textures; 8 MB) and the base Marines' finished LOD QCs recompiled as
  models/tif_factions/ins2/marpat_<light|standard|heavy>.mdl with the woodland folder first in $cdmaterials; ragdoll
  copied with the new checksum. Same TIF skeleton, LODs and infected-male ragdoll as the Marines.
- Faction `usmc_woodland` "US Marines (MARPAT Woodland)": side ally, allied with usmc (they don't fight each other;
  everyone else does), the Marines' voices and loadouts (AT4 included).
- Harness: marpat.lua 26. All suites pass.

### 0.38.53: soldiers talk more (2026-11-25, NOT yet seen in game)
User's friend: talking "doesnt feel like enough". Before: TIF.Say let one line through per faction every 0.9 s and per
soldier every 2.5 s, at level 80 (under gunfire's 95-150); lines only on moments (first contact, reload, kill, man
down, grenades, bounds); nothing mid-firefight; advance / contact_mg / contact_sniper / critical / friendly_fire /
spawn / no_ammo had lines but were never called; "attack" (melee) has no lines in any pack; bf3marine has no moving /
cover me / clear / advance / negative / retreat lines (half the Marines silent on those).
- sh_voices.lua: the group gate is per squad (soldiers outside a squad: per faction and entity-index block), 0.5 s;
  per soldier 1.8 s; level 90 (V.LEVEL / V.SOLDIER_GAP / V.GROUP_GAP). TIF.Say returns the line played.
  V.FALLBACK: a pack without lines for an event uses a near one (moving -> advance / affirmative, cover_me ->
  suppressing, clear -> affirmative, retreat -> moving / negative / backup, attack -> swear, no_ammo -> reloading,
  critical -> pain, contact_mg / sniper / rpg -> contact, friendly_fire -> swear, spawn -> affirmative / advance...).
- squad/sv_chatter.lua (TIF.Chatter, from the 1 s squad timer): an engaged squad has someone talk every 4-8 s (C.GAP),
  never within 2.5 s of another line from that squad; the line by state (C.WEIGHTS: contact by what he's fighting,
  suppressing, swears; pinned -> cover me / swear; moving -> moving / advance). A new squad sometimes calls in (spawn,
  50%, 1-3 s after forming, only out of a fight).
- Wired: first contact names the threat (C.ContactEvent: LMG -> contact_mg, marksman -> contact_sniper, launcher ->
  contact_rpg; players by weapon class); squad pushes on an objective and range-closing say "advance"; hurt below 30%
  health -> "critical" once; hit by an ally -> "friendly_fire"; reloading an empty gun -> "no_ammo" (BF3's own lines,
  else reloading).
- Harness voices 33 (+22: fallbacks for every bf3 gap, the squad gate, level, contact kinds, chatter cadence over 2
  minutes, no chatter out of a fight). All suites pass.
- To tune after a test: C.GAP (4-8 s), C.WEIGHTS, V.GROUP_GAP / V.SOLDIER_GAP, V.LEVEL.

### 0.38.52: RPG rework (launcher as a utility) + disposable AT4 for the Marines (2026-11-25, NOT yet seen in game)
User: friend found RPGs "a bit oppressive", "them keeping it as a primary that slings so often isnt the super best";
wanted the launcher "more as a utility ... can whip out the rpg when it counts and not too uncommonly but ... not enough
to lay constant hate"; then "a disposable at4 ... the usmc will use one", model from SandSWEP Launchers, "optimize it
... oriented correctly and handed off correctly ... properly spent when let go".
- Third weapon slot (npc/sv_weapon.lua): W.Init(npc, primary, secondary, launcher); loadouts take `launcher = {...}`.
  TIF.Loadout returns it; any loadout (faction packs, editor, API) that still lists a launcher as the primary moves it
  to the launcher slot and gets a rifle (the role's `rifle` list, else the faction's default primaries). The AT gunner
  fights with his rifle; the launcher rides on his back (NW2 tif_launcher, cl_gunhold back pose) until he draws it.
- tactics/sv_launcher.lua (TIF.Launcher): when it counts only. Checks every 1.5 s from engage, before cover:
  vehicle / helicopter; 3+ enemies within 250 of the target; a target he's shot at for 8 s without hurting it (dug in);
  a lone exposed soldier at tif_rpg_lone_chance (0.1) per 4 s. Needs 500-2600 range, outdoors (sky over him), a clear
  line, no friendly within 320 of the impact, not in CQB / prone / bipod / melee / shield / shaken.
  Limiters: 4-10 s after first contact; 25-40 s between his rockets; 15 s per squad; 20 s per target (not vehicles).
  Rockets: tif_rpg_rockets (2) for reusable launchers, 1 for disposables; out of rockets = rifleman.
  Flow: leaves cover, draws (switch clip), says "cover me", the nearest enemy who can see him shouts "RPG!" (every
  pack's alertrpg), settles 0.9-1.3 s, fires, holds 0.6 s, stows. Gives up without firing if the target is lost 2 s
  or after ~8 s. RPG-7: back onto his back (next draw reloads). AT4: MW19's rpg_drop clip (new manifest clips at4_drop
  / at4_drop_cr / at4_drop_pstl, the pistol one when the rifle is dry): the tube leaves the hand on the clip's dropgun
  notetrack, empty hands until pistol_pickup, rifle up at start_aim.
- Archetype "rpg" (AT Gunner) is a rifleman now: rifle bursts, range 450-2200, cover fire 0.3, no 500-unit sidearm swap.
- Loadouts: Insurgents AKM / AK-74u / worn AK + M1911 + RPG-7; Marines M4 SOF a / b + X16 + AT4; Russians War Saw grip /
  AN-94 + Sykov + RPG-7.
- tif_rocket_radius default 300 -> 250 (archived values stay). Settings > Combat: rockets, lone chance, blast radius.
- AT4 (weapon_tifmw_at4): SandSWEP Launchers' AT4 (at4_tube mesh) rebuilt by `tools/guns/at4_build.py` into TIF's
  baked-gun frame (right wrist at the origin, the RPG-7's axis): front grip 8.5 ahead of the wrist under the right hand
  (SandSWEP's world model holds it 8.8 ahead of the hand bone; the RPG-7's trigger grip is 8), the RPG-7's hold and
  left-wrist spot (palm on the tube ahead of the grip). 24,349 -> 3,034 triangles; textures 2048x1024 -> 1024x512 DXT5
  (13.5 MB -> 2.1 MB). at4_spent.mdl: the same mesh with a 12-sided physics hull, mass 7. Sounds: SandSWEP's AT4
  shots / tails (sound/tif/at4, TIF_AT4.Fire / TailOut / TailIn).
- Spent: TIFDropWeapon(which) drops def.spentModel for an empty disposable, tossed out to his right and down, debris
  collision, launcher drop foley, removed with the corpse timer; it leaves his back for good.
- tools/anims now carries cod_anim_prep.py, cod_to_breen.py, cod_bone_mapping.py (the builder's helpers, from
  K:\mods map pics\smh_cod_anim_baker\tools, where TIF's anim pipeline lives) so the repo copy builds on its own.
- Harness: launcher.lua 52 (loadout migration, rockets, every trigger and limiter, draw / settle / fire / stow, AT4
  drop clip, assets on disk); guns 236 (45 guns, sound.Add stub); russians 94 (launcher slot). All suites pass.
- To watch in game: the AT4's hold on the MW RPG set (grip under the right hand, left palm on the tube), the dropped
  tube's pose leaving the hand, the back carry for both launchers, whether 2 rockets / 25-40 s feels right.

### 0.38.51: third starter faction, Russian Ground Forces (2026-11-25, NOT yet seen in game)
User: "third faction, Russian ground forces ... optimize these other models, i dont want the blue variants ... scrambled
messy compile bugged headgear varaints near the end of their headgear options ... removed ... prevent them spawning
completly without a headgear", "russians will use russian sof weapon category".
- Source: MadIvan18's BF4 Russian Ground Forces (Workshop 1444174239, 20 models, already ValveBiped + quad / knee
  helpers). New generator codport `tools\sets\make_bf4ru.py` (repo `tools/factions/`): decompile, merge, rebuild on
  rig_tifhost like make_ins2 (exact host skeleton, horde zombies' infected male ragdoll, 5 face skins kept, head flexes
  dropped), then lod_pack (LOD1-3 + shadow LOD).
- Blue = the "sib" Siberian camo: Soldier D and Recon C not built. 15 models in `models/tif_factions/bf4ru/`: soldier
  a (flora), b (green), c (khaki), baku, aftermath, emr (+ balaclava each), recon a / b / b balaclava.
- Headgear: the decompiled headgear meshes are all clean (on Head1, no stretched triangles; the VTX bone tables match the
  VVD), so the scramble was in the original compile. The soldier models' trailing recon-set extras (beanie, beanie +
  headset, cap, gas mask, gas mask + headset; in Baku the only options past vertex 65536) are dropped; soldiers keep
  their helmets (6B47, Altyn, 6B27). Rebuilt from clean SMDs, nothing of the old compile is left.
- Never bare-headed: HeadWear / Mask groups compiled without a blank option (recon B's bandana keeps its blank).
- Materials `materials/models/tif/bf4ru/` (1024 px DXT, 119 MB); 35 unused files (sib VMTs, tanker kit, spare eye
  textures) moved to `K:\jimmyproject\bf4ru_src\_pruned_materials`.
- Faction `russians` "Russian Ground Forces" (config/sh_content.lua): side enemy, no allies (Insurgents, Marines and
  Russians all fight each other). Guns: the roster's ru_sof tier only: War Saw grip / sup, AN-94 (default), AS VAL /
  Bizon (assault, breacher), PKM SOF (support), Plague SVD (marksman), RPG-7, Sykov. Voices: mercenary (no Russian
  pack yet).
- Harness: new russians.lua (90: models + ragdolls on disk, no sib, every role's guns are ru_sof and exist, every ru_sof
  gun used). All suites pass (civ_anim / civ_body are old scripts for an earlier runner).
- Repo: build/bf4ru holds the QCs + character tomls (meshes are rebuilt from the Workshop pack, not stored).

### 0.38.50: morale back on, surrender off (2026-11-25, NOT yet seen in game)
User: "put it back but just disable surrenderring".
- tactics/sv_morale.lua: MO.OFF = false (shaken / broken, morale withdrawals and radio lines are back; tif_morale works
  again and its settings checkbox is restored). New MO.SURRENDER = false: BrokenThink skips the surrender roll, so a
  broken soldier only runs and hides. MO.SURRENDER = true brings it back. Mission captives (TIF.API kneel) unaffected.
- Harness: new morale.lua (7: broken, alone, hurt, enemy at 200 never surrenders across 50 rolls; holds fire; runs
  away; the flag restores surrender). run.py now points at the repo's addon/. All suites pass.

### Starter factions: horde zombies' infected male ragdoll (2026-11-25, NOT yet seen in game)
- All 8 INS2 models (`models/tif_factions/ins2/*.phy`) now use horde_zombies' `hordez/citizens/male_02.phy` (the body 7
  of the 10 infected males share; user: "a loose cod style phys i rlly like"). 19 solids, every bone present,
  checksums restamped. `make_ins2.py` VB_PHY points at it, so rebuilds keep it. Old phys (rus_rebel male_02) backed
  up in `K:\jimmyproject\_addon_backups\2026-11-25\ins2_phy_rusrebel`.

### 0.38.49: morale off for the release; prone soldiers no longer slide at walk / run speed (2026-11-25)

User: "remove like morale for now. it can come back later but i dont want it for release as its a little buggy,
sometimes theres a prone failure. where they can stay in prone at walk and run".
- Morale: tactics/sv_morale.lua MO.OFF = true -> MO.Enabled() false whatever the archived tif_morale says (no shaken /
  broken / surrender, no morale withdrawals or radio lines). Code kept; the settings checkbox is commented out
  (ui/cl_settings.lua). MO.OFF = false brings both back. Workshop text and README no longer mention morale.
- Prone slide: sv_move M.Step chose speed from the move kind and never looked at prone, and the brain's "lying down"
  branch is skipped while fighting, so a later branch (morale break, medic run) could set a goal and he slid along in
  the prone pose (the brain re-forces stance 2 after every branch). Now Move.Step: lying prone with a goal (anything
  but the last-stand "crawl") -> TIF.ProneB.GetUp and no movement until he's up. GoDown clears goals (dives too), and
  nothing moves soldiers prone on purpose (P.CRAWL_SPEED was unused).
- Harness move 24 (+4); all suites pass.

### 0.38.48: insurgents carry the rebel guns (2026-11-25)

User: "make the insurgents use the more rebel weapon set, currently they use the russian one". The guns' "rebel" tier
(TIFBaked.tiers) instead of the old militia's Russian SOF table: default AKM / AK-74u / worn AK (ak_ff) / FAL with
M1911 or Sykov; assault AK-74u / Uzi / sawn-off; guard AKM / Uzi / wooden pump; support PKM / MG34; marksman SVD /
SKS; RPG-7; breacher wooden pump / double barrel. The militia alias follows (copied from it).

### 0.38.47: INS2 vertex spike, bare arms' normal map, LODs; tif_cqb ships; repo folder (2026-11-25, NOT yet run in game)

User screenshots (insurgent corpses): a sheet of vertices stretched up from the hips; bare arms "lack a normal"; "is
this good for performance, do they have lods".
- Spike: 13-36 vertices per model (trousers at the crotch) were weighted to INS2's root Bip01, kept unanimated: left
  behind once ragdolled. make_ins2.py merges Bip01's weights onto the pelvis; Bip01 is gone from the models.
- Arms: INS2's ins_light_color.vmt (the hands mesh) names models/player/ins_light/ins_light_normal, which isn't in the
  pack (the original model had the same gap), and the path rewrite mangled it. Generated from the arm texture's own
  shading (codport fake_normal.py, strength 2, blur 1, 1024 px DXT1) -> materials/models/tif/ins2/ins/
  ins_light_normal.vtf (kept in K:\jimmyproject\ins2_src); INS2's ins_light / us_light / us_heavy paths now map to ins /
  usmc.
- LODs: none in INS2 either (~18-26k triangles a soldier at any distance). codport lod_pack.py: LOD1 / 2 / 3 at ~50 /
  25 / 12% (switch 15 / 35 / 70) + a shadow LOD, weights kept exact, eyes whole; ragdolls kept. Check: no vertex on a
  non-ValveBiped bone, every bone exactly on the host's.
- maps/tif_cqb.bsp now ships in the base (the CQB test map).
- Repo for testers: K:\jimmyproject\Tactical Infantry Framework\Tactical Infantry Framework (addon/, build/, docs/,
  media/, tools/, README.md, .gitignore, .gitattributes; tools\sync_addon.ps1 refreshes addon/ and docs/ from here).
  Not committed.

### 0.38.46: INS2 models rebuilt on TIF's own ValveBiped skeleton: plain bone-merge (2026-11-25, NOT yet run in game)

User: "you retargetted these the same way my cod factions were. those have a rlly fucked up arm issue that we had to
fix on top with lua ... fix the models themselves to be valvebiped as best as possible". Right: codport's shared rig
keeps CoD's bone axes under ValveBiped names (its pelvis x points up, z back; ValveBiped's x forward, z down), which
is why codport models need TIF's retarget map and the CoD factions' arm fixes. TIF's host (mw_male) is bone for bone a
stock ValveBiped skeleton (checked against a normal player model: same positions and axes).
- make_ins2.py now builds on the host: make_host_rig() writes codport\shared\rig_tifhost.qci + anims\reference_
  tifhost.smd from mw_male.mdl's bind pose (65 bones, no j_gun; IK chains), the characters use it as [paths] rig /
  reference_anim, twist_vrd off (codport's helpers are CoD-axis), INS2's ForeTwist1 / 2 -> the host's Ulna / Wrist
  twist bones. Ragdoll: a stock ValveBiped .phy (tif_faction_pack rus_rebel male_02.phy, 15 solids), checksum
  restamped. Check: all 65 shared bones rest on the host's (worst 0.0000 u, 0.054 deg); extras only the unweighted
  INS2 root Bip01. All 8 rebuilt, every material resolves.
- insurgents / usmc no longer set retarget = true (plain bone-merge like any ValveBiped player model; their own
  ragdolls as corpses). TIF.RegisterFaction's retarget option stays for codport-rig factions.

### 0.38.45: INS2 factions twisted (torso / pelvis turned round): retarget, not bone-merge (2026-11-25)

User screenshots: US Marine torso backwards, pelvis backwards and 90 deg sideways; insurgents' vests turned on the
torso. The compiled models were right (pelvis / spine / thighs rest exactly on the rig's), but codport's rig keeps
CoD's bone axes under ValveBiped names, so TIF draws codport models through the retarget map (TIF.Modular.Retarget),
never a plain bone-merge; only modular factions could flag that (modular.retarget). TIF.RegisterFaction now takes
def.retarget = true (flags def.models and variants' models); insurgents / usmc set it (the militia / pmc aliases copy
it). Not seen in game yet.

### 0.38.44: starter factions Insurgents and US Marines (INS2), more voices (2026-11-25, NOT yet run in game)

User: MadIvan18's Insurgency 2 characters ("ivan has given me permission to use these as the starter factions"),
"give them generic names like insurgents and usmc. if ours rn conflict change them", "make it jus random bodygroups",
"bring in another american voice and the 2 insurgent voices from tif factions".
- Models: K:\jimmyproject\codport\tools\sets\make_ins2.py (rerunnable). INS2 skeleton (3ds Max Biped: Bip01 / Pelvis /
  L UpperArm..., bones rolled differently from ValveBiped: spine / thigh z flipped, feet) -> codport's MW19 rig:
  decompile, all bodypart meshes in one SMD with materials tagged per option (INS2 options share materials),
  INS2 -> ValveBiped bone names (twist / jiggle / weapon bones not renamed: weights to the nearest rig bone; Bip01
  kept unweighted), rebind scaled to the rig's head height (INS2 ~10% taller), arms / hands / fingers by joint frames,
  codport body + qc, tags stripped, blank options only where INS2 had them, eyes back as a $model with eyeballs at the
  rebound eye meshes, compile + package with the shared male ragdoll. 8 models in models/tif_factions/ins2:
  insurgent_light / standard / heavy, security_light / standard / heavy, civilian_vip_insurgent / _security (built,
  not used by a faction yet). All materials resolve. Materials copied to materials/models/tif/ins2/<ins|usmc>/ (VMT
  paths rewritten) + an EyeRefract eye set (codport's iris / occlusion / cornea). INS2's chest and head sit ~3 units
  further back on their bones than MW19's (bending pivots a little differently): look in game.
- Factions (config/sh_content.lua): insurgents ("Insurgents", enemy, the 3 insurgent outfits, the old militia guns,
  voices mercenary / tif_arab_rebel / tif_arab_operative) and usmc ("US Marines", ally, the 3 security outfits, the
  old PMC guns, voices bf3marine / specops). Bodygroups random per soldier (TIF's own look roll).
  militia / pmc stay as hidden aliases (TIF.FactionAlias; copies of the new defs, def.hidden, not in the spawn menu):
  DTW / GOPS / SWAT / sandbox / content packs' ally lists name them. FactionRelation resolves aliases both ways
  (TIF.FactionCanon; an allies list naming an old id counts for the new one). Defaults switched: tif_player_faction
  "usmc", spawner / soldier / orders / bases / tif_range preset "insurgents", heli crew / riders "usmc".
- TIF Faction Pack's own "insurgents" -> insurgent_cell ("Insurgent Cell"); its HOSTILES and TIF CoD Factions' ally
  list name both.
- Voices: specops, tif_arab_rebel, tif_arab_operative copied from TIF Faction Pack (35 + 32 + 35 MB) and registered in
  the base (sh_voices). tif_arab_operative has no "cover me" lines (the pack's own gap). Base now 543 MB (INS2
  models 20 MB, materials 120 MB, voices 185 MB).
- Harness: voices 11 (5 packs), hl2npc 35 (+5 alias relations); all suites pass.

### TIF Faction Pack: masked Russian rebel's helmets on his head (2026-11-25, not seen in game)

User: "his steel ssh helmet bodygroup isnt properly weighted to his head". models/player/rus_rebel/male_mask.mdl (the
only rebel compile with a "root" bone): the hat bodygroup's rurebl_helmet3 / rurebl_helmet4 were weighted 50% root
(the model origin, at his feet) / 50% Head1, so they hung halfway down and stretched; the cap and helmet1 / 2 were
100% head. Fixed in the .vvd only: the 604 vertex entries on exactly {root, Head1} (= the 305 unique positions of
those two meshes, checked against the decompile, nothing else) get Head1 1.0, root 0, bone slots unchanged so the
VTX / MDL / checksum stay valid. Re-decompiled: both helmets Head1 100%. Original .vvd:
K:\jimmyproject\_addon_backups\2026-11-25\tif_faction_pack_rus_rebel\male_mask.vvd. Tool: K:\jimmyproject\codport\tools\vvd_headfix.py.
The other seven rebel models have no root bone (fine).

### 0.38.43: the default factions' voices ship in the base (2026-11-25)

User: "pack in faction voices?" (readiness blocker B1). The base's own factions use vo/mercenary (militia) and
vo/bf3marine (pmc); they came from the Workshop addons TFA-VOX Insurgency Sandstorm Mercenary Improved (3287967646)
and TFA-VOX Battlefield 3 U.S. Marine (3283709387), not shipped. Their sound/vo/<pack> folders are copied into the
base as they were (527 + 685 files, mp3 / wav, 85 MB; re-encoding mp3 would only cost quality); same paths, so the
original addons installed alongside change nothing. The other packs content factions use (securityforce,
securityforcevip, specops, tif_arab_*) already ship in TIF Faction Pack. Base now 304 MB.
Harness voices.lua (new): every event of both packs (24 / 18) finds lines in the base's own folder. The default
factions' models (mw2_soldier_16, pmc_hecu) are still external.

### 0.38.42: horde zombies (and any tagged addon NextBot) are combatants (2026-11-25, NOT yet run in game)

User: "make em acknowledge my horde zombies mod". horde_zombies' hz_zombie is a NextBot and already tags itself
(NW2 tif_faction = "hl2_monster", HZ.Register) and hunts NPCs / NextBots (hz_target_npcs, TIF soldiers included), but
TIF only tracked and gave factions to NPCs, so soldiers never saw them.
- core/sh_factions.lua TIF.TaggedBot: a NextBot with a tif_faction tag that isn't a TIF soldier / civilian gets that
  faction (TIF.FactionOf) and counts as a live combatant (alive, not hz_dead, not notarget). hl2_monster is hostile to
  every faction.
- compat/sv_hl2npc.lua tracks NextBots too (TIF.NPCs); NPC-only relationship calls skip them (sync, switching off).
- sv_perception candidates: distance first, then combatant / relation (a horde can be hundreds long).
- Harness hl2npc 30 (+8); mw22's vector mock copies vectors (0.38.41's centre_cross); all 39 suites pass.

### 0.38.41: CQB entry clips cross the doorway at its middle (2026-11-21, NOT yet run in game)

User: "door opener tends to have trouble with clearance, alot" (CQB). The go clips were aimed from the stack slot at
a point in the room; where their curved path crossed the doorway was chance: in the sim 19-21 in off centre for open /
grenade / kick (2nd man) / no-door, i.e. at the jamb of a 48 in doorway. breach_plan now slides each breacher's start
along the door (centre_cross, up to CROSS_SHIFT_MAX 40, re-aimed each step) until the clip crosses the door plane at
its middle; plan.from is his stack spot and the warp / path check use it. Harness cqbsim 60 (+4; with the shift off
they fail at 18.9-21.5 in).

### 0.38.40: CQB round 3, shield pistol + AI shot, doors, fight sounds (2026-11-21, NOT yet run in game)

User list: choppy glides; a team not entering and the rest giving up; kicks dead centre; doors off without collision
(mind area portals); the second man barging in; notice anims / shooting through the door from the stack; clean house
pistol-only; AI takes the shield shot after a while; NPCs breaking destructible doors by walking into them; melee pairs
silent. log_sv: squad 4 "going without the full stack after 19 s (1/4): 1 (583 u off) 3 (515 u off) 4 (409 u off)",
squads 6 / 7 / 10 / 16 sat in hold with men who never got in.
- Glides: TIF.CQB.Glide only asks; CQB.GlideStep slides every server tick from TIF.Move.Step (was the brain's think).
- Getting in: CQB.Through: a man whose goal is across the door being cleared walks to its front (THROUGH_BACK 40)
  and is slid through it (to THROUGH_IN 48 past, up to 170 u) instead of trusting the path round the frame.
  CQB.PathTrouble logs a man who can't path to his spot ("can't get to his spot N u away (fail)") and tries a spot
  36 u beside it for 3 s.
- Seeing an enemy no longer holds the commit or the entry releases; on the stack (not committed) no shooting at what's
  seen unless within 220 u or hit in the last 3 s (eyes stay on the door). sv_passive_mw: no awareness reactions
  (startle, new enemy close, point out, look around, pending ones) for anyone whose squad is clearing.
- Kicks: the kicker is placed so at the kick (doorU) he's square to the door, centred, KICK_BACK (34) back, and his
  clip is blended onto it (plan.stand / warpU, like the sledge man).
- Doors: tif_cqb_door_off (1): kicked / sledged doors come off as a debris prop knocked into the room (the door
  hidden, not solid); a door a func_areaportal targets stays (open, portal open) but COLLISION_GROUP_DEBRIS; doors
  opened by hand / cracked for a grenade go DEBRIS too.
- Breach / entry clips: a narrower body (ENT:TIFSetSlim, 7 in half-width) while they play.
- Shield: clean house forces a pistol (TIF.Weapon.ForcePistol: his sidearm, or W.SIDEARM weapon_tifmw_m19 given), no
  pistol -> no ch scene (MW19 grab instead). Held SH.AI_SHOT_AFTER (15 s): the nearest hostile soldier within 1500 u
  whose shot line meets the captor first (not the hostage) fires: SH.AI_SHOT_WIN 0.9 -> the captor's death (killer =
  him), else again in 4 s.
- Doors on the way (sv_door_mw): when the MW19 door clip can't play (crouched, mid clip, prone, at an angle) the door
  is opened as he reaches it (D.TOUCH 44). compat/sv_doors.lua: crush / physics / generic damage to a door from an
  NPC / NextBot is dropped and the door opened away from him (tif_door_bump_open); bullets, blasts, blows untouched.
- Fight foley: the fight clips' own beat cues (ps_hm_grnd_melee02_*) -> body impact + gear accent + cloth; dropgun ->
  weapon drop; melee_death -> body fall.
- Harness: cqbsim 56, shield 66, foley 17, doors 7 (new); all 39 suites pass.

### 0.38.39: CQB onto the marks: glide, wall slide, breach clips decided at the plan (2026-11-21, NOT yet run in game)

User: "maybe make sure they get on the door with entry clearance more properly, or do some trickery to rlly force them
to enter. they can still get caught alot on the cqb entry anims, and then either stay outside or be switched to the
generic entry's ... they still sometimes do that anim of taking a step back and then forward over and over".
- Step back / forward at the stack: sv_brain's cqb step calls a man "there" within 32 in, but Move stops within
  ~37: men who stopped in between got a new goal each time (start clip, stop clip, again). Now TIF.CQB.Glide: within
  GLIDE_R (64) of the spot with a clear hull line (brush-only), he's slid straight onto it at GLIDE_SPEED (110 u/s;
  the client legs walk from the position change), after any stop / turn clip that's playing. Breachers land on their
  exact marks, so their clips start where they were planned from.
- Caught on the clips: root motion that met a wall stopped dead (sv_action Act.Tick) while the clip played on; it
  now slides the rest of the step along the wall (every root clip).
- Switched to the generic entry: breach_plan checks each breacher's go clip from his stack spot (clip_path_clear from
  slot.pos) and takes the other side's version when it's blocked; with neither he has no breach clip (on foot) from
  the start, instead of waiting in the pose and being dropped at the go. (Not the sledge swing.)
- Harness cqbsim 46 (+3 glide), warp 6 (+2 slide; old code 28.8 in along the wall vs 39.9 now); all suites pass.

### 0.38.38: breaches that stalled after "opening door"; go clips into the wall (2026-11-21, NOT yet run in game)

User: "their still walking against the wall/failing breach's with lingering outside". log_sv: squad 2 "opening door 2
(kick, breach clips)" then nothing for 12 s until removed.
- Stall: everything after the go (the door's moment, the flash, the entry) ran inside the stack's "settled" check, and
  the breach clips carry both breachers off their spots, so it stopped being settled: no door, no entry, until the
  progress stall timer (~14 s in the sim). Now cq.committed: once the stack goes, it runs to the entry (reset per door).
- Wall: breachers may start their go clip up to BREACH_READY (45 in) off their stack spot and the clip's path came with
  them. Off by more than GO_WARP_MIN (6), the clip is now blended onto the path from the planned spot (plan[i].from,
  aimed b.yaw) by GO_WARP_AT (0.1) past its door / move moment, and its path check is made from that spot.
- Watchdog: a clear in "hold" over 30 s is logged too, with how many of the team see an enemy and whether all got in.
- Harness cqbsim 43 (+9; with the old gate the new checks fail at 14.25 s).

### 0.38.37: civilian foley (2026-11-21, NOT yet run in game)

User: "do civs make walks too" - they didn't (tif_civilian plays its clip on the server as the entity's sequence;
cl_foley only read cl_body's soldiers). cl_foley now has C.Track (a clip's sound points between two cycles) shared by
both; a client Think scans tif_civilian (every 0.5 s) and tracks each one's sequence -> clip (TIFG mw_male by seq name)
and GetCycle: footsteps by surface and gait, cloth gear, landings, no weapon rattle. Civilian corpses get the ragdoll
body-fall impacts (TIF.Foley.CorpseSounds). Harness foley.lua 14 (+3); civ suites pass.

### 0.38.36: soldier foley: footsteps, gear, landings, body falls, stance, drops (2026-11-20, NOT yet run in game)

A tester: "they dont really make much sound when running about / falling over etc". The user gave MW19's foley rip
(K:\SOUNDSmw19, 7,444 wavs). K:\jimmyproject\tif_mw\foley_pack.py packs the subset TIF uses as
mono .ogg into sound/tif/foley/<key>/<n>.ogg (2,626 files, 22.6 MB) and writes lua/tif/npc/sh_foley_data.lua.
- npc/sh_foley.lua: surface rows (footstep / body-fall / weapon-drop / prone sets) from the trace's surface property
  or MatType, water depth (puddle / ankle; wading knee / waist from tif_wade); server: corpse ragdoll impacts as body
  falls (first 5 s, by part mass and speed) and the dropped gun's first 3 hits as MW weapon drops by weapon kind.
- npc/cl_foley.lua: on each client, from the notetracks of the clip the legs play (cl_body st.legPlay[1] + cycle):
  Foot heel plants -> step by gait (creep / walk / run / sprint by clip speed and stance), mvmt_step_pre/post -> vest
  gear (vestlight / vestheavy / vestaq per faction, heavy for LMG / RPG) with sometimes weapon rattle, land ->
  landing, ps_bodyfall_* -> body falls in death clips. Moving clips without Foot / gear notes use their foot plants.
  Stance changes, going prone (and its ground hit 0.55 s in), getting up, mantles (mwtr_). Within 2500 u only.
  cvars tif_foley (1/0), tif_foley_volume (0-2).
- Harness foley.lua 11 (new: every surface's sets packed, walk / run loops sound per plant on the right surface,
  files on disk, death-clip falls, silent out of range, puddles).

### 0.38.35: clip-death corpses from the clip's pose, not the hidden stance pose (2026-11-20, NOT yet run in game)

User: "melee pair ragdolls seem to come from the idle they were doing hidden instead of the actual last pose they had
in the fight". The server only holds one stance pose per stance for hitboxes (BodyUpdate); TIFMakeCorpse switched it
to the clip (ResetSequence / SetCycle) and read the bones in the kill's own tick, which returned that tick's cached
bones: the hidden idle. Now ENT:OnKilled turns a clip death (tifNoDeathClip: a fight's loser, a shield's captor) into
a short tifDying of that same clip, from where it was (CLIP_DEATH_HOLD 0.2 s): BodyUpdate plays it on the server,
HitsMW.DyingThink samples bones from the next tick on and hands over with bone velocities, as death clips do. Other
clip-less deaths (mid throw / reload) still use the old posing. Harness clipdeath.lua 5 (new); hits / melee / shield pass.

### 0.38.34: paired-fight A-pose corpses (real cause); fight clips forced and locked (2026-11-20, NOT yet run in game)

User: "theres stilll a pose deaths in melee pairs" + "it should also force the anim as sometimes ill spawn them next ot
eachother and one will do the spot animation while the victim plays the right anim".
- log_sv: every paired-fight death was followed by "Corpse failed: tif_soldier.lua:587 SetupBones (a nil value)".
  Like InvalidateBoneCache (0.38.33), SetupBones is client-only: TIFMakeCorpse died after spawning the ragdoll, which
  then dropped from its reference pose (the A-pose). Every clip death without a death clip went the same way (fight
  losers, deaths mid-throw / reload / vault since 0.38.4). Guarded; server bone matrices come from the sequence.
- start_fight now drops whatever either man was doing (reaction hold, look, activity, facing; the act force-cleared)
  and plays both halves under npc.tifActLock = "melee" (lockOK): no reaction / turn / flinch replaces one half while
  the other plays. end_fight (played out, partner gone, an outsider's shot) unlocks. Move.Face leaves fighters
  alone (the clip turns them). The watchdog doesn't count a fight's lock as leaked.
- Harness melee 39 (+5; the mock Act honours locks now); shield / move / push / crowd / gait / trans pass.

### 0.38.33: CQB stack timeout from progress; corpse error; silent squad ends logged (2026-11-20, NOT yet run in game)

User: "i had some failed breach's can you look at the condebug log". console.log had no CQB Lua errors; log_sv.txt:
- Squad 23 "entry at door 1 (1/3 stacked)" 15.2 s after its start: STACK_TIMEOUT (15) ran from the order, so the walk
  to the door used it up and it went in with two men still on the way. Now it runs from the last time anyone got 16 u
  nearer his stack spot (cq.progressAt), capped by CQB.STACK_MAX 45; going short logs who was missing, how far off,
  and what clip he was in.
- Squads 18 and 20: "next door N" then nothing (no done line, no watchdog): a CQB only ends without a log line when
  its squad empties (all members removed / dead) and the squad goes. squad/sv_squad.lua drop_squad now logs "clear
  ended, squad empty" with the phase and door.
- "Corpse failed: tif_soldier.lua:585 InvalidateBoneCache (a nil value)" (4 times): client-only; the corpse after a
  death in the middle of a clip (no death clip) failed outright. Guarded.
- Harness cqbsim 34 (+2: slow walkers waited for; a stuck man left after the stall timeout).

### 0.38.32: fighting from beside cover, hand-plant back in (2026-11-20, NOT yet run in game)

User: "a soldier NEXT to cover, crouched, when done shooting he like palms the ground rq to boost him into cover, do
we have that" -> "could it be built as a sometimes thing, i want just some more variety".
- The clips were already there (mwc_<ls|rs|cr>_xin_<st|cr>_<k>, MW19 AI exposed -> cover) but only played when he
  took a cover within 75 u while nearly stopped. They start from the plain exposed crouch at the root (pelvis
  checked in the SMDs) and turn by their root yaw.
- Now (tactics/sv_cover_mw.lua, MW.SideOut): when he'd pop out at a visible enemy, 20% of the time (MW.SIDE_CHANCE,
  at most every 12 s per cover, not with a pistol / under heavy suppression) he crouch-walks 24 u past the corner
  (ls / rs) or the low wall's end (cr, an end within 72 u), fires from the exposed crouch for a burst x1.3, then
  turns to the clip's start facing if he's >25 deg off it (phase side_turn) and goes back in with the xin clip,
  warped onto the node. Spot checks: ground level with the node, room for a crouched hull, clear shot, not taken.
  Phases side_out / side / side_turn; hits_mw treats them as out of cover (crouch pains / deaths, not cover ones).
  lc / rc / st have no xin clips: unchanged.
- Harness test.lua 97 (+12 beside-cover; also fixed 4 stale steps: the first soldier threw a frag mid flash
  test); gait / hits / smart / trans / melee / shield / cqbsim pass.

### 0.38.31: close 1-on-1s become paired fights; A-pose clip deaths (2026-11-20, NOT yet run in game)

User: "can you almost enforce one on one melee pairs when they are that close, ive only seen one play once, and in
that animations the death of one had an a pose into a ragdoll".
- A-pose: the fight clips are in the server model (checked); the kill (TakeDamageInfo at melee_death) runs
  ENT:OnInjured before OnKilled, and OnInjured played a HitsMW pain stagger, replacing the fight clip just before the
  corpse was posed from it: the ragdoll started from the stagger's upright first frame. No pain on a killing hit or
  a clip death (tifNoDeathClip) now; the human shield's captor kill went the same way.
- Pairs: M.PairScan every 0.5 s (M.PAIR_EVERY): any two enemy MW-body soldiers 50-160 in apart, level, a clear line,
  one of them fighting the other (tifPrimary): a paired fight 90% of the time (M.PAIR_CHANCE). A start / stop / turn
  step or a looping idle doesn't stop it (cleared, the fight clip takes over); cover, a CQB breach clip, a shield's
  lock, vehicles, prone and the rest still do. M.Try from engage stays as it was (60%).
- Harness melee 34 (+5); full run: all 35 suites pass.

### 0.38.30: TIF log file, watchdog, tif_mark (2026-11-20, NOT yet run in game)

User: "are errors like that readable or only noticed when i report them" -> "Yes, add it" (a log file read after a
session).
- core/sh_log.lua (loaded right after sh_core): garrysmod/data/tif/log_sv.txt / log_cl.txt (the last session's kept
  as *_prev.txt; header with version, realm, date, map). Every TIF.Log / TIF.Warn / TIF.Error line (still printed as
  before) plus TIF.Event(tag, ...) file-only lines; buffered, flushed every 1 s and on shutdown; capped at 2 MB a
  session. tif_logfile / tif_logfile_cl 0: off.
- Events: every CQB step (sv_clear log(): always, not only with tif_debug), human shield starts / ends / a captor
  clip that had to be put back, paired melee fights.
- core/sv_watchdog.lua (every 2 s, each find once): a held civilian with no live scene / a civilian "held" with no
  scene / an animation lock left on a soldier with no scene: put right and logged; a CQB clear on its stack 45 s or
  in its entry 20 s with men unreleased: logged with every man's CQB label and clip, the door, opening / flash state.
- tif_mark [note] (anyone): the note, where you are and what every TIF soldier / civilian within 1000 u is doing
  (faction, action, clip, CQB label, shield, melee, moving) into the log, flushed at once.
- Uncaught Lua errors outside TIF's own error handling still only reach the console: -condebug writes it to
  garrysmod/console.log.
- Harness logfile 17 (new); full run: all 35 suites pass.

### 0.38.29: human shield interrupted / hostage clips stuck or looping (2026-11-20, NOT yet run in game)

User: "the animation of the human shield can be interrupted by them noticing u, and sometimes itll bug on the civ and
the looping anim wont play or the death/free will repeat forever".
- Captor: npc.tifActLock while in a scene: Act.Play refuses other clips (nil, as for a missing clip: reactions,
  flinches, turns) unless opts.lockOK, and Act.Clear needs force; the scene's own calls pass them. Unlocked on release
  or by a blast that kills him outright (his death clip). Anything that still replaced his clip is put back in step
  (t0 / tif_act_t kept).
- Hostage: her own behaviour kept running when she was grabbed (a GoTo / OneShot / Wait / Hide in progress): it moved
  her, swapped her clip and switched her state out of "held" (then she wasn't released properly). Now those loops stop
  on tifHeld, OneShot leaves civOneShot alone while held, and SetState can't leave "held" while tifHeld is set
  (TIF.Shield clears it before letting her go).
- Released: the clip she's left in (run / survive) used to loop (BodyUpdate loops non-loop clips unless a one-shot)
  until her behaviour played something; now it holds its last frame (civHoldLast) until then.
- Harness shield 60 (+11: lock, resync, held state, loops, real Act.Play / Act.Clear under the lock); civ, civ_anim,
  civ_body, crowd, melee, hits, cqbsim, trans, passive all pass.

### 0.38.28: shield in front + Clean House variant, more shields and paired fights (2026-11-20, NOT yet run in game)

User: "fix the one we have and then do the clean house one as a variant for when the player cant see it initiate,
then maybe increase hte likeliness slightly, as i had a russian rebel around a bunch of civs and he wouldnt seem to do
it, i also keep putting opposing factions in front of eachother 1 on 1 and they wont melee pair, so make that a bit more
likely too"; "in clean house the civ grabs a gun right after, so make sure to not feature that part".
- MW19 (tag_sync checked: = tag_origin in both clips, no other alignment): the raw pose really is her kneeling at his
  side, no contact once held, so she's slid to a kneel 32 in in front of him over the grab's second half and kept
  there (VARIANTS.mw19.shift).
- Clean House variant (manifest mwsc_*, thd_2f_020_hostage_*): aim_start / aim / idle pairs; his death cut f90 (down
  by f40) with her live clip cut f78 (she grabs his gun at f84); his live clip with her death (killed at kill_me
  42/82) or headshot death (cut at start_ragdoll f63). shield_frames.py generalised (ROLES list, each anchored on its
  pair's captor clip; ALIGN: the headshot death was authored at another origin, 75 in behind / 98 deg: moved rigidly
  onto the aim hold's start). Used when no player sees either of them as it starts (SH.Seen: in view and a clear line):
  starts held (no grab clip), nearest civilian within 160 put in his grip. Hostage shot: her death pair (the hit's
  height picks the headshot one), killed on it, then he fights on; no rescue clip, held until settled or 120 s.
- More shields: 50% per try (was 30), every 2 s (3), enemy from 100 in (150); MW19 civilian pick: his facing may swing
  50 deg off the enemy to fit a civilian near the grab's start (was one exact spot); no stance requirement.
- Paired fights: 60% (35), 50-160 in apart (80-125), the attacker moved up to 70 in onto his mark (40) with a room /
  line check, crouched soldiers too (butt hits still standing only).
- EntityRemoved: a body removed as it dies reports hostage_killed / captor_killed, not "removed".
- Harness shield 49 (+16), melee 29 (+1; mocks: TraceHull, level traces clear).

### 0.38.27: human shield facing, captor death A-pose (2026-11-20, NOT yet run in game)

User (screenshot): "human shield turnt around and not positioned right together"; "also the death animation on the
attackers side bugs, it plays and then does an a pose ragdoll".
- Placement itself checked (scratchpad shield_check.py): the two baked skeletons placed from sv_shield_data land
  within ~3 in of the raw MW19 scene. The scene: both face ~25 deg left of its x (hips); he aims ahead at chest
  height, she kneels ~33 in to his right front. 0.38.20's trigger turned the scene so the hostage pointed at the
  enemy, which put the enemy off his right side ("turned around"). Now the scene faces him at the enemy
  (SH.FACE 25) and the civilian taken is one near where the grab starts for that facing (SH.SNAP 60); the old
  "civilian toward the enemy" pick (SH.TOWARD) is gone. The pose is MW19's (a hostage at his side, not a body held
  in front): noted in HUMAN_SHIELD.md, Clean House's set is the held-in-front one.
- Death: at the death clip's end the scene was released (his clip cleared) before he was killed, and the corpse is
  posed from the clip he's in: none -> bind pose. Now killed first, and a dead captor's clip isn't cleared.
- Harness shield 33 (+2: facing, killed while still in the death clip).

### 0.38.26: stuck on someone: pass through / make way / path round (2026-11-20, NOT yet run in game)

User: "a step back into a step forward, i see it alot when their stuck on someone but its usually not enough to
unstick them because of the step forward again" -> "Yes, build it". That was sv_move unstick: both sides blocked ->
backed off 30 in, then re-pathed the same line into the same person.
- Stuck on a TIF soldier / civilian (sv_move blocker): the pair pass through each other for M.PASS_T 1.5 s
  (TIF.Crowd.GhostPair, NPC_SCRIPTED; the overlap rule never fires for two hulls pressed together), and a standing
  soldier with nothing on (no goal, act, cover, prone, vehicle, shield, melee, bipod, downed, CQB wait) side-steps
  C.WAY_DIST 40 in out of the mover's line at a walk (TIF.Crowd.MakeWay, driven every tick for up to 1.2 s; not
  again for 4 s). Not a strike toward giving the goal up; at most M.PASS_MAX 2 per goal.
- Stuck on a player / prop / the world: backs off M.BACKOFF 60 (was 30) when both sides are blocked, and his paths
  avoid that spot for M.AVOID_T 5 s (cost_fn: areas within M.AVOID_R 70 cost x6 more).
- Harness crowd 37 (+11); full harness run: all pass but civ's known flaky scatter check and the stale
  _stage78_body_run composition (its `soldier` helper missing; harness-only, untouched code). push.lua had been
  broken since 0.38.21 (sv_flashbangs needs CreateConVar at load): mock added.

### 0.38.25: teams idling at the door, room called clear before anyone's in (2026-11-20, NOT yet run in game)

User: three clips with tif_debug on (no text). The door label read "CLEAR: entry" / "hold" while men still stood on
the stack: the clear went on without them getting in, then called the room clear and moved on ("idle outside until
dissentrested").
- The second man's paired breach clip stands still for its first part (kick 2nd: f71-75 = 2.4-2.5 s; right-hand
  handle 2nd 1.5 s), made to start with the first man's clip; TIF started it 0.25 s after the door gave way, so he
  stood that out on top. Now it starts at doorAt + 0.25 - moveU * dur (moveU: where the clip's own root curve first
  takes him 6 in, CQB.MoveStartU; the grenade pair keeps its measured CQB.BREACH_U).
- The hold's HOLD_WAIT (5 s, then quiet -> "clear" -> next door / done) ran from the last release; with 3-7 s breach
  clips the room was called clear before anyone was in. Now it starts once the whole team is 16+ in past the doorway
  (cq.allInAt), or after CQB.HOLD_ENTER_MAX 15 s.
- cqbsim: the real root curves (an x / y / yaw triple every 3 frames), the kick 2nd-man timing, a team that never gets
  in waits the 15 s. 32 checks; mw22 75, flashwait 19.

### 0.38.24: breach clips dropped by 0.38.23's wall check (2026-11-20, NOT yet run in game)

User (clip): "the update broke something i think. they almost never commit to single doors now, they will just kinda
idle outside of it until they get dissentrested". In the clip the door opened on its timer with nobody playing an
opening clip, then no one went in.
- 0.38.23's go-clip check traced the clip's path in straight hull segments; the handle / kick clips start beside the
  door and cut past the jamb, so the segments hit the frame and nearly every breach clip was dropped (regression check
  in the new sim: the old check rejects >= 4 of 8 opening / kick clips from normal stack spots). Now the check is the
  clip's end: on the room side of the doorway (12+ in), room to stand there, clear lines him -> doorway -> end (chest
  height, brush-only). The sledge swing (stays outside) isn't checked.
- New harness cqbsim: the whole sv_clear.lua driven through a closed single door (stack -> door -> entry -> hold) for
  open / kick / hammer / grenade / random, against a wall with a 48-in opening, the go clips through the brain's
  yawFn / check: all play, none skipped, no errors, collision groups restored. 30 checks.
- Not found offline: why no one walked in after the door opened in that clip (the sim's entry and hold run fine). If
  it still happens with the clips back, a tif_debug 1 console log of the clear ("[cqb]" lines) would show where it
  stops.

### 0.38.23: sledge facing / angle, CQB entry clips, team bumping, no flash after a breach (2026-11-20, NOT yet run in game)

User (screenshot): "this guy wasnt fully facing the door and also the angle of the hammer is off by one of the
yaw/pitch ... also ppl in cqb still sometimes bump into eachother or will do their enter animation while not fully in
door clearance. making them walk at a wall. also the door kick animation features some moving in, so that shouldnt be
a scenario where they flash".
- Sledge prop: studiomdl turns every model +90 about Z; the prop's mesh too, so cl_props takes it back off (UNTURN,
  as the baked guns do). The pose data itself was right.
- Sledge facing: 0.38.19 read the bake's axes as his. Against his feet (the bakes face -Y; entity +x = SMD -y) the
  hammer lands 11 in ahead and 47 to his LEFT, swinging leftward: he now stands side-on, the door on his left
  (CQB.HAMMER_YAW -90, HAMMER_HIT {11, 47}), and his go clip blends him onto his exact spot over its first 30%
  (Act root + to, warpU 0.3; the hit is at 31%): men stop up to ~37 in short of a goal.
- Go clips (handle / kick / grenade / sledge / no-door, sv_clear go_item): aimed from where he stands when the clip
  starts (sv_brain queue yawFn), not his slot; skipped if its path (hull at 1/3, 2/3, end, brush-only: the door prop
  doesn't count) hits the world: he goes in on foot with the entry. The door still opens on its own timing.
- The entry team passes through itself while clearing (COLLISION_GROUP_NPC_SCRIPTED, restored on release; handed to
  the crowd module / a shield's record if they hold him too).
- No flashbang after a clip breach (cq.wentIn): the go clips carry them through the door. Open doorways, doors opened
  without clips and commanded onEntry flashes as before; the grenade breach is its own flash.
- Harness mw22 75 (+4), props 12 (+1), crowd 26, shield 31, flashwait 19, gait 1013.

### 0.38.22: bipod order (2026-11-20, NOT yet run in game)

User: "our order for bipod anims is strange, sometimes ill see them do it correctly but other times ill see it cut to
a firing bipod" / "i was more talking abt prone also".
- Prone (cl_body): the set-up / pack-up was decided per frame from the aim mode, which drops between bursts: each
  drop restarted the pack-up from its first frame (the set pose) mid set-up, then set up again. Now kept on the
  bipod Bd.BIPOD_HOLD 1.2 s after the aim drops (a reload or crawling off still packs at once), and a set-up turned
  round mid-way packs up from the matching point (pack-up = set-up reversed, x1.8), and vice versa.
- Prone (server): B.Set counted 2.9 s of lying still, aimed or not, so a gunner who lay unaimed was "set" the moment
  he aimed and fired through the client's set-up. Now the timer needs the aim too (with the same 1.2 s hold:
  B.PRONE_HOLD), and sv_weapon holds a prone LMG's fire until set (not with an enemy within W.BAND_CLOSE).
- Wall / ledge: a move order mid set-up started the pack-up at once from its first frame (the set pose): the half
  set-up snapped to firing, then packed. Now the set-up finishes (b.leave), then the pack-up follows from the set pose
  (checked in pack() too: B.Update only runs in a fight).
- Harness bipodseq 15 (new), bipod 6, fire 17, gait 1013.

### 0.38.21: friendly flashes much weaker (2026-11-20, NOT yet run in game)

User: "way lower the effect of friendly flashes, like range and duration ... have maybe a debug option for no effect".
- New cvar tif_flash_friendly (0.3; settings > Combat slider): a flash on the thrower's own side (him, his allies,
  allied players) reaches that share of its range (780 -> 234) and its stun / white-out lasts that share as long; the
  ringing only at 0.5+. 0: no effect on them at all. Enemies get the full flash; flashes with no known thrower (other
  addons') stay full. TIF.FlashScale(thrower, ent); TIF.FlashAt(pos, radius, inflictor, thrower) (thrower defaults
  to the inflictor's owner: GR.Throw sets it).
- Harness flashfriend 8 (new), flashwait 19.

### 0.38.20: human shield (2026-11-20, NOT yet run in game)

User: "what about human shielding, theres a segment for that" -> "build it and also like note it as something which
could be created incase i wanna have it be in a semi scripted situation". Notes for scripted scenes and the other
shield sets in the rips (Clean House, Embassy, bomb hostage, bomber standoff): TIFDIDDY/HUMAN_SHIELD.md.
- Clips: MW19's AI hostage taker (Spec Ops cp_hostagetaker, matched pairs), manifest shield_family:
  mwsh_<grab|idle|death|rescue>_<att|vic>, built uncentred. Captor static; hostage starts ~82 in off his right, kneels
  ~33 in to his right; death: he drops, she runs ~70 in; rescue: he shoves her down and comes up aiming.
- Placement: K:/jimmyproject/tif_mw/shield_frames.py fits the raw scene (anchored on the captor's tag_origin) onto
  each baked clip per frame (Kabsch, ~5 in) -> tif/tactics/sv_shield_data.lua; both entities are placed from it every
  tick, clips played without root motion (the bake's own root curve is in another frame). Entity +x = SMD -y.
- tactics/sv_shield.lua (TIF.Shield): trigger from engage (sv_brain, after melee): a soldier hostile to the players,
  enemy in sight 150-1000 in, a civilian 45-125 in within 70 deg of that enemy and near the grab's start spot (30%
  per try every 3 s, 40 s cooldown, 2 scenes max, tif_shield). Busy chain entry (no moving / firing). Outcomes: any
  hit on him -> death pair (damage blocked, killed at the clip's end with tifNoDeathClip; a blast that kills outright
  just kills), enemy within 110 in or held 30-55 s -> rescue pair, hostage killed / captor killed / removed ->
  released. Both NPC_SCRIPTED while in it.
- Civilians: state "held" (does nothing of its own), Scare() leaves a held hostage alone; released -> flee.
- sv_weapon ally_in_line: soldiers (but her captor) don't fire through a held hostage between them and the target.
- API: TIF.API.HumanShield(captor, civ, opts {held, hold, noRescue, yaw, pos}), API.HumanShieldOf(ent); hooks
  TIF_ShieldStart / TIF_ShieldEnd(scene, outcome). Dev: tif_shield_test [held].
- gun_holds.py: clips baked with end=N use their _e<N> bake and a curve cut at N; j_gun relative to tag_origin per
  frame (scripted-scene and travelling clips had the slung gun 200+ in off the body: sledge, hostage / pilot idles,
  vehicle get-ins; the two civ_pnc runs still read far but civilians carry no gun).
- Harness shield 31 (new); civ / civ_anim / civ_body (known flaky scatter), melee 28, hits 276, fire 17, move 20,
  crowd 26, mw22 71, props 11, hl2npc 22.

### 0.38.19: sledgehammer breach (2026-11-20, NOT yet run in game)

User gave the MW19 sledgehammer rip (K:/wpn_vm_p40_me_sledgehammer_v0_prop) for the hammer breach.
- Clip: MW19's Clean House infil swing, zd30c_000_infil_lbirds_sledge_ally13 -> mwq_br_sledge (mw22cqb family),
  cut at f90 (new build option end=N, tif_mw_build trim_end): f90-97 is a scripted 290-unit catch-up slide, and the
  gun is back in the right hand by f90. Notes kept: sledge_vs_door (u 0.311, the door gives), stow_sledge (0.967).
  91 frames, no turn, ~7 u travel: he swings in place.
- Prop: K:/jimmyproject/tif_props/sledge_build.py -> models/tif_mw/props/sledgehammer.mdl (LOD0/2/4, no collision,
  1024 albedo with MW's metal-mask alpha darkened like the guns). sledge_frames.py fits the raw clip (root motion
  kept) onto the baked one by its joints per frame and writes npc/cl_props_data.lua: the sledge (CoD
  tag_accessory_right) relative to R_Hand for f0-85 and Spine4 from f86 (it turns up to 49 deg in the hand during
  the swing, so per frame, not one offset).
- Client npc/cl_props.lua (TIF.Props, from cl_body's update after the bones): the clip's prop follows it frame by
  frame; NW2 bool tif_sledge (sv_clear: the hammer man while he has a hammer breach, cleared on release) shows it
  stowed on the chest; hand <-> chest blended over 0.25 s; hidden when dying.
- sv_clear: method "hammer" (CQB.BREACH_CLIPS.hammer, weight 2 of 12; a locked door 40% hammer / 60% kick; also a
  commanded opts.method). He waits square to the door at bp.stand so the swing's reach (CQB.HAMMER_HIT, 47 ahead /
  11 right of his feet, from the baked clip) lands HAMMER_EDGE 10 in from his side's door edge; no room there (hull
  check) or no clip: kicked instead. The door bursts open on sledge_vs_door (metal impact + the kick's opening); the
  second man goes in on the kick stack clip.
- Harness mw22 71 (11 new), props 11 (new), crowd 26, flashwait 19, gait 1013.
- Test map tif_cqb (TIFDIDDY/maps, local, not in the base): mapsrc/make_tif_cqb.py + build_tif_cqb.ps1. Kill house
  (door / open / locked off a corridor, garage opening), two-storey with stairs and doors on both floors, a locked
  shed, a six-room hotel strip (door / open / locked / open / door / wide). HL2 door01_left doors. Needs
  nav_generate once in game.
- Build note: sledge_build.py left an empty models/tif_mw/props in the game dir; tif_mw_build's final move
  os.remove()d it and failed (models were already moved). Fixed in sledge_build (removes the empty folder).

### 0.38.18: soldiers and civilians don't get stuck on each other (2026-11-20, NOT yet run in game)

User: "make sure they wont get stuck on eachother. its something i see alot both in and outdoors, and on
civillians". Soldiers only reacted after bumping (0.6 s without progress, sidestep, new path); civilians only had
the engine's slow stuck check; root-motion clips move the body with a world-only trace, so they push it into others.
New npc/sv_crowd.lua (TIF.Crowd, cvar tif_crowd 1, profiler key "crowd"); the "make way" part (standing soldiers
stepping aside) is left out on purpose until this is tested.
- Steer: each mover looks 80 u ahead in a 26 u half-lane every 0.2 s (soldiers, civilians, players, HL2 NPCs; a list
  shared for 0.1 s). Someone walking the same way: kept behind at his pace. Standing / crossing / head-on: eased past
  on the right (left if he's already right of the lane or the right is walled), an extra loco:Approach blended with
  the path's own, no new path. Nobody counted past where the mover stops.
- Ghost: two TIF bodies overlapping 0.5 s, or at once when one is in a root-motion clip: both
  COLLISION_GROUP_NPC_SCRIPTED (pass each other; bullets and players still hit) until 28 u apart and 0.6 s on, then
  back. Bodies in vehicles / other groups (debris, melee, deaths) untouched; a group changed meanwhile isn't
  overwritten. tif_crowd 0 restores all.
- Civilians (tif_civilian GoTo): the same steering, and the soldiers' quick stuck check (0.6 s, hull-traced sidestep
  for 0.8 s, fresh path; 3 in a row = stuck).
- Harness crowd 26 (new); move 20, push 11, gait 1013, mw22 60, civ_anim 52, civ_body 11, hits 276, melee 28,
  hl2npc 22; civ's known flaky scatter check.

### 0.38.17: CQB entry variety (2026-11-20, NOT yet run in game)

User: "add a bit more variety to the cqb entries. just so its not the same every time" (drop-ins first; the hammer
breach needs a sledge prop, later). Every room was: closed door opened by hand (or a commanded kick), open doorway
stack-and-cross.
- Manifest (mw22cqb): MW22's grenade stack mwq_br_<l|r>_gren_idle / _gren_1st / _gren_2nd and open-doorway stack
  mwq_br_<l|r>_nodoor_idle / _nodoor_1st / _nodoor_2nd (sdr_breach_*_grenade_*, sdr_breach_nodoor_*).
- sv_clear: a closed door with no commanded method gets one at random (pick_method, CQB.METHOD_WEIGHTS open 4 /
  kick 3 / grenade 3; a locked door is kicked; grenade only for men allowed to flash under tif_cqb_flash, TIF
  grenades). An open doorway gets the no-door stack CQB.NODOOR_CHANCE 0.5 of the time (both in on their clips, then
  to their corners). New cvar tif_cqb_variety (1; 0 = the old way).
- Grenade breach: the first man cracks the door (door sped to 300) and rolls a flash in on his clip (no notetracks:
  door / release / second-man set-off measured on the raw clips, CQB.BREACH_U); the entry waits for the bang
  (cq.flashWait); no second flash that room. The second man's clip starts so he sets off ~1.3 s after the throw.
- Fixes: CQB.Go with a method redoes the breach plan (it kept the stack's clips); the "door won't open" release
  counts from the clip's door moment, not the go (the r grenade clip's door moment is 3 s in: cut at 2 s before).
- Harness mw22 60 (19 new), flashwait 19, gait 1013.

### 0.38.16: shooting a long death ends it (2026-11-20, NOT yet run in game)

User: "let shooting a long death end it early". Long deaths (fall -> crawl / wounded idle 2.5-6 s -> death) ran to
the end whatever happened.
- sv_hits_mw: H.ShotEnd(npc, pos, force): the ragdoll takes over this tick (dy.untilT = now; the chain doesn't move
  to its next stage after a shot, so the hand-over can't be pushed back), with that hit's own push (hit.fresh: not
  damped x0.25 like a death clip's, tif_soldier TIFMakeCorpse) and a BloodImpact effect where it hit.
- Bullets: an EntityFireBullets hook checks each round against the dying body's pelvis / chest / head bones (within
  H.SHOT_RADIUS 9, nothing solid in between): a dying soldier is a debris-group entity, which bullet traces may pass.
  H.DyingLong lists the soldiers in a long death (TIF.Soldiers drops the dead). Any damage that does reach him
  (blasts, melee) ends it too (EntityTakeDamage). Short death clips aren't cut.
- Harness hits 276 (9 new); all suites pass but civ's known flaky one.

### 0.38.15: TIF soldiers and HL2 / addon NPCs see and fight each other (2026-11-20, NOT yet run in game)

User: "let them be able to acknowledge half life npcs, currently they ignore eachother". TIF.FactionOf gave NPCs no
faction (not combatants) and perception scanned players and soldiers only; HL2 NPCs ignore NextBots unless told.
- core/sh_factions.lua: NPCs get a side from Classify(): player allies (rebels, vortigaunts, conscripts, hacked
  rollermines) = the players' faction (follows tif_player_faction); Combine classes = "hl2_combine"; zombies /
  antlions / headcrabs / barnacles = "hl2_monster"; passive citizens, bullseyes, fauna, missiles = none (not
  combatants); an unknown class (addon SNPCs) by its disposition to the first player (hate / fear "hl2_hostile", like
  the players' faction). NW2 "tif_faction" on an NPC overrides. Unknown ids are hostile to everyone by the existing
  rule, so the Combine and monsters fight every TIF faction (and each other). IsLiveCombatant: sided, alive,
  not notarget.
- compat/sv_hl2npc.lua: TIF.NPCs registry (spawned NPCs, ones already on the map); once a second each NPC gets
  AddEntityRelationship to every soldier from TIF.Relation (D_HT / D_LI / D_NU), only when it changes. tif_hl2_npcs 0
  turns both ways off (NPCs neutral again).
- sv_perception candidates scan TIF.NPCs; sv_weapon's friendly-fire check also spares allied NPCs in the line.
  Melee, suppression, gunfire and hits already worked on any combatant.
- Harness hl2npc (new) 22/22; all suites pass but civ's known flaky one. Syntax clean.

### 0.38.14: close-range melee: butt hits and paired fights (2026-11-20, NOT yet run in game)

User: "add the close range melee fights and the gun butt hits"; "against players they can only do the gun butt hits";
"are you sure theres not an ai gun melee?" (there is: my first search missed it; MP's upper-body gun_butt_hit clips
were dropped for it).
- Clips (manifest melee_family, model mw_male_melee, 28 roles): MW19's AI melee mwm_melee_1-4
  (sdr_com_exposed_stand_melee0N, full body, root motion; "fire" notes are the impacts, melee01 strikes twice),
  step-ins mwm_to_melee_1-4 (10 fr, 15 in) / mwm_run_to_melee_1-4 (20 fr, 74 in), pistol versions mwm_p*; paired fight
  mwm_fight_<aw|dw>_<att|def> (hm_grnd_melee02, uncentred). 0 stick frames.
- tactics/sv_melee_mw.lua (TIF.MeleeMW), cvars tif_melee, tif_melee_fights:
  - M.Try from engage and cqb (enemy visible, < 200): within 62 strike; to 100 the step-in first; running and to 170
    the charge. Damage at each fire note if the enemy is within 78 in front: players 30 (DMG_CLUB, view punch, shove),
    others 45 (TIF soldiers' existing melee pains / deaths). Cooldown 2.5-4 s. Not with an RPG, not in cover / prone /
    crouched / a vehicle.
  - Paired fights: enemy TIF soldiers on the MW body only (players never), 80-125 in apart, both standing and free,
    35% chance, 20 s cooldown each. Placement from the raw clips' tag_origin first keys: the defender is the scene origin
    (turned to face the attacker), the attacker goes 109 / 96 in ahead of him facing back (aw / dw), only if he's
    already within 40 of that spot and the ground there is level. Outcome: attacker wins 65% x aggression x health
    ratio. The loser dies at the clip's melee_death note (tifNoDeathClip: corpse from the fight frame); the winner plays
    on and fires into him at the clip's fire note (sound + muzzle flash). Both debris-collision while locked. Anyone
    else's damage on either ends it for both.
  - B.Think busy chain: TIF.MeleeMW.Busy first (before flash reactions).
- Harness melee (new) 28/28. Syntax clean. Gun tables regenerated for the new clips.

### 0.38.13: gun LOD mag drag, RPG sitting ahead of the hands (2026-11-20, NOT yet run in game)

User (clip of an RPG soldier): "slightly buggy still"; and "most guns have this issue where part of the mag on lower
lods is like still in the gun so it has a noticeable weight paint drag". Backup first:
K:\jimmyproject\_addon_backups\2026-11-20\tif_guns_before_lodchain (models, materials, weapon lua, build SMDs / QCs).
- Mag drag: the LOD SMDs were clean (no triangle mixing tif_gun / tif_mag), but studiomdl stores every LOD's vertices
  as LOD0 vertices (the AKM's three LODs: 4796 vertices in the VVD, LOD0's count, no fixups): a lower-LOD vertex not
  in LOD0 takes the nearest LOD0 one, near the magwell often a tif_gun vertex, so mag triangles kept a corner on the
  gun and stretched as the mag came out. 40 of 44 guns, up to ~220 triangles per LOD (scratchpad lod_snap.py).
  gun_decimate.py chains the LODs now (lod1 from lod0, lod2 from lod1): every lower-LOD vertex is a LOD0 vertex with
  its own bone (lod_subset.py: 0 misses in all 44; lod_snap.py: none). Caps retuned for the chaining (lod1 0.035, lod2
  0.09): lod1 ~15% lighter than before, lod2 total within 3%. LOD0 byte-identical to before.
- The texture step (gun_textures.py) couldn't run: the old venv's numpy and srctools are partly deleted (temp cleanup)
  and the system Python has no srctools. LOD0 was unchanged and lines up with lod0_t line for line, so the lod1 / lod2
  atlas meshes take each vertex's lod0_t twin (scratchpad lod_t_from_lod0.py). Reinstall srctools before the next
  full texture build.
- RPG: the launcher sat ~6 in ahead of the hands (clip: arms right, launcher floating). The runtime puts every gun's
  origin at the right wrist (cl_body gun_pose); the rifles' meshes are rooted ~3 in behind their pistol grip, MW22's
  RPG between its two grips. gun_compile.py MESH_SHIFT rpg7 (5.78, 0.18, 0.20) moves its mesh, mag bone and tag
  attachments: trigger grip in the RPG aim's hand frame (-2.32, -1.3, -0.49) -> (3.37, -0.29, -0.12), the AKM's being
  (3.28, -0.50, 0.66) (scratchpad shift_sim2.py / rpg_after.py reproduce cl_body's placement on the baked poses).
  The muzzle-up tilt during the RPG reload is MW19's own (j_gun to +34 deg, right hand on the grip throughout).
- All 44 guns recompiled; the weapon definitions came out identical to before.

### 0.38.12: RPG soldiers get their own idles and locomotion (2026-11-19, NOT yet run in game)

User (screenshot, RPG soldier): "whatever we should have for rpg idles isnt working".
- rpg_idle / rpg_crouch_idle were sdr_com_exposed_<stand|crouch>_rpg_aim_5: the aim set's centre pose, 2 frames,
  frozen. MW19's AI RPG idles (sdr_com_exposed_*_rpg_idle01) are ADDITIVE (upper bones identity at frame 0): now
  played on the aim pose every frame (new builder option additive_on / tif_mw_build.additive_on). 90 / 36 frames.
- Everything else used the rifle's clips with the launcher in rifle hands (sh_anim: "moving reuses the rifle strafes",
  calm / alert = the rifle's). New manifest rpg_family (38 roles, model mw_male_rpg): MW19 has no RPG locomotion but
  has the RPG's upper-body poses (sdr_rpg_exposed_<stand|crouch>_<ready|gun_down>, 12 bones, no legs):
  - rpg_mstg_<walk|run>_<dir>_loop, rpg_crouch_<walk|run>_<dir>_loop: the rifle strafes' legs, the RPG aim pose's
    upper body (masked with the rifle ready pose, which keys j_spine4, so the chest is pinned).
  - rpg_calm_<idle|walk|run|sprint>: gun_down; rpg_alert_<idle|walk>: ready.
  The RPG poses don't key j_spine4: their arms rode each base clip's lean (launcher ~65 deg down on crouch strafes /
  jogs). New builder option overlay_chest (overlay_pose chest=): the chest from the RPG aim pose. Checked offline
  (scratchpad rpg_check.py): every aimed RPG clip barrel (0, -1, 0) level, lowered carry 42 deg down, alert 31 deg
  down; 0 stick frames.
- sh_anim: L.rpg gets the RPG strafes / crouch strafes / calm / alert sets and their speeds (the rifle's untouched).
  Gun tables regenerated (gun_holds.py).
- Not covered: cover (MW19 has RPG cover reloads only; cover aims stay the rifle's), prone (rifle prone set).
- Build 33/33 models. Harness wclass 47 (new RPG checks); all suites pass but civ's known flaky one. Syntax clean.

### 0.38.11: release audit; debug / test commands moved to a local dev addon (2026-11-19)

User: "is tif base like fully ready ... we have some debug commands still which id rather not ship with, but i still
wanna keep. and apparentally we have early phase commands which do nothing still". Backup first:
K:\jimmyproject\_addon_backups\2026-11-19\tif_lua_before_devsplit (all of lua/ + addon.json).
- New local addon addons/tif_devtools (addon.json title says local only; not for upload): lua/tif_dev/sh_init.lua
  loads, after all of TIF, when present (tif_init: TIF.Dev = file.Exists("tif_dev/sh_init.lua", "LUA")):
  the overlays (sv_debug / cl_debug / cl_cqb / cl_base / cl_vehicle; tif_debug, tif_debug_cover, tif_debug_paths),
  test commands (tif_give, tif_reveal, tif_forget, tif_noise, tif_doors, tif_cover_scan, tif_suppress, tif_prone,
  tif_cover_test, tif_cover_course, tif_info, tif_aimwhy), tif_stickwhy / tif_stickwatch, tif_bench, vehicle tests
  (tif_vehicle, tif_mount, tif_drive, tif_vpatrol, tif_dismount, tif_convoy*, tif_roads), heli tests (tif_heli*),
  death clip bans (tif_deaths_recent / tif_death_ban / tif_death_unban; TIF still reads a saved ban list,
  H.SaveBans exposed), tif_voice_test, tif_visual_check (TIF.VisualCheck exposed), the MW clip viewer (tif_mw_view*,
  entity tif_mw_viewer). tif_modular_debug stays in config/sh_modular.lua (private tables), registered only if TIF.Dev.
- Shipped (player / admin, listen host or superadmin as before): squad orders tif_follow / tif_dismiss / tif_order /
  tif_formation (squad/sv_orders.lua; the tif_menu buttons), tif_spawn / tif_spawn_squad / tif_clear (the settings
  panel's quick actions), all tif_base_* (encounter/sv_base_commands.lua), tif_menu + tif_settings (ui/), tif_factions,
  tif_selftest, tif_dv_build, tif_cl_reset_bodies. Spawn helpers TIF.Room / FreeSpot / SpawnPoints / SpawnSoldiers /
  SquadMix (used by the API, spawn menu and DTW) moved out of the debug file into core/sv_spawn.lua.
- Fixed while there: tif_order / tif_formation took a looked-at ENEMY soldier's squad: allies only now.
  Settings panel's Debug section only with the dev addon. Stale pre-MW bits: the base encounter vehicles and
  tif_range's vehicle patrol named gtav_insurgent (-> TIF.Mounted.DefaultCar, an MW car); tif_vehicle's default and
  its "GTA seat data" message; tif_prone's "Prone Mod missing"; seat-fit cvar help (tif_seat_drop / _forward /
  tif_driver_forward: now "vehicles without their own TIF seats", still used by the generic MW seat);
  tif_gta_pm_proportions help (still used by the retarget library); the faction-model check's "GTA body" wording.
- Checked, not dead: no call to an undefined TIF function anywhere (scratchpad dead_refs.py); core's tif_debug
  readers (sv_clear, sv_base, sv_squad, sv_cover_behave, sv_convoy) are nil-safe without the dev addon; no other addon
  uses a moved command; no TODO / FIXME; no stray prints outside dev-only code.
- Kept on purpose (user's call): maps/tif_range.bsp (4.4 MB) + its base preset and DV road layout (the only map with
  a base preset: the settings panel's "Garrison this map's base" works there out of the box); compat/sh_prone.lua
  (wOS prone fallback: unreachable with the MW body, harmless).
- Harness: all 31 suites, 2621 checks pass; stage78_probe's mantle fixture moved 40 -> 34 (the mantle md clip starts
  within its contact distance + 12 = 36.5 since the 2026-11-18 rebuild; not a code fault). Syntax: base 148 files,
  dev addon 17, clean.

### 0.38.10: MW Base gun sounds packed in (2026-11-19)

User: "pack in the mw base sounds from my addons folder. they allow use of their ports so its fine".
- scratchpad mw_sounds_pack.py: the 371 names TIF's weapon_tifmw_* ask for (SWEP.GTG.mw fire / tailOut / tailIn /
  reload / reloadEmpty), every sound.Add in the MW addons' Lua run in LuaJIT with stubs (MW Base channels from
  mw_loader.lua: CHAN_ATMO 137 ... CHAN_WPNFOLEY 143) -> 4609 definitions; 186 of TIF's names found, their 211 files
  (25.9 MB, sound/viper/...) copied in; lua/tif/config/sh_mwsounds.lua (generated, shared, in the manifest after
  sh_content) registers each one only if not already registered (MW Base's own win where installed).
- 185 names are defined nowhere (no sound.Add, no script file, no file of that name in any MW addon: ps_wfoly_*,
  MW19_<pistol>.*, the mike4-style notetrack names): silent with MW Base too. sv_weapon's reload foley now only plays
  registered names (no failed-sound lookups).
- Check (scratchpad mw_sounds_check.py): all 44 guns' fire + outdoor / indoor tails resolve, 211/211 files present.
  Reload foley resolves for the AKs, SVDs, RPG, Rytec, SCAR, Oden, Kilo, M13s, double barrels, FAL (17/18); 0 for
  the rest (as with MW Base). MW Base is no longer needed for anything.
- Base now 190 MB.

### 0.38.9: activity gun at its ends, takedown handoff, death handoff force (2026-11-19, NOT yet run in game)

- Wading idle "gun got totally offed" (screenshot after 0.38.8: arms aimed, gun hanging straight down from the right
  hand). The bake is right (j_gun barrel / grip identical to the wading walks, scratchpad gun_check.py), the compiled
  mw_male_wade.mdl has the sequence; arms up with the gun bone at rest = the idle's sequence missing on the client, i.e.
  the old model still loaded (GMod doesn't reload a changed .mdl while running; Lua refreshes). Needs a game restart
  after a model rebuild. Gun tables (zz_jgun, gun_holds.py) regenerated anyway for the new calm wading idles; overlay
  ("_x_") clips aren't in them at all (none ever were): they count as gun-bone driven with no let-go, like the walks.
- Idle activities (smoke / phone / water): the gun "phasing onto the defined chest area" at the start and end. carried
  was per frame (jgunW > 0.5): while the clip's hand still held the gun (first / last part) the code sling took it to
  the chest, until the clip let go. Now per clip (Bd.ClipCarriesGun: TIFG_JGUN_HOLD r > 0.5 anywhere): in the hand,
  then on the clip's own j_gun motion; the code sling only for clips that never let go.
- Takedowns (mw22_takedowns): since 0.38.4 TIFMakeCorpse spun every bone at random (+-160 deg/s) when no death clip
  motion came in; the takedown re-posed the corpse and set velocities but never the spin: pose, then a jerk. Now
  hit.posed (the takedown passes it) skips the jitter; the takedown also carries the animation's spin (angular
  velocity from its two pose samples, local, capped 720 deg/s; not for retargeted models) and calls TIF's settle.
- Death clip -> ragdoll ("you can see the jump", "too much force", Source glitch jumps):
  - bone velocities over ~H.VEL_WINDOW 0.1 s of ticks (the sample nearest that age) instead of one tick (~15 ms: a
    hitch on that tick doubled / tripled them); per-bone cap 800 -> 480.
  - settle_corpse (ENT.TIFSettleCorpse): bones whose centre is inside the world (PointContents solid, under a floor
    surface) lift the whole body clear (<= 24) instead of physics shoving them out; death-clip handoffs can't leave
    upward faster than 160; angular damping >= 6 for 0.45 s (joint-limit springing), then restored.
- Harness hits 267 (new: last-tick hitch), hips 18 (new: per-clip sling). Syntax 157 + mw22_takedowns clean.

### 0.38.8: wading idle legs, hip turn for forward-only walks (2026-11-19, NOT yet run in game)

User (screenshot, a wading soldier with one heel kicked up behind): "wading idle (i think) has twitchy leg movement";
and forward-only walks sliding diagonally / sideways.
- Wading idles, measured on the bakes (scratchpad wade_feet.py / wade_cand.py: foot height, per-frame foot jump, loop
  seam): mwwd_calm_knee_idle / _chest_idle (sdr_wtr_*_patrol_idle_01, the same data) hold the right foot 14 in up,
  kick it to 36 in three times and pop 23 in at the seam: the kick in the screenshot. mwwd_idle (sdr_wtr_exposed_neutral)
  was one frame with the right foot 8 in up. Now sdr_wtr_<knee|chest>_patrol_idle_02 and
  sdr_com_exposed_wtr_shift_idle01 (feet planted < 1.5 in, seamless, no stick frames).
- Library scan of all 515 loops TIF uses (scratchpad loop_pops.py, foot jump > 6 in / frame or seam > 6 in; runs and
  sprints sit at 6-8 naturally): dropped civ_pnc_walk_forward05 (11 in pop mid-stride; civ_pwalk_1-5 now). Left, to
  look at: mwhb_rap_2_idle (heli rappel idle, 28 in seam pop) and the pickup seat idles mwkz_s2-4_idle (an entry clip,
  12 in seam).
- Hip turn (cl_body hip_turn / vb_pose): forward-only walks (calm, flashlight, alert, calm wading, stairs / slopes)
  moving off-axis turn the pelvis toward the travel direction (pitch about its up axis, + = left) and Spine / Spine1
  back half each, up to Bd.HIP_MAX 70 deg, scaled by moveK, eased at 240 deg/s; zero on full-body actions / prone /
  aimed strafes. Checked offline on the baked alert, patrol and knee-wade walks with Source's AngleMatrix composition
  (scratchpad hip_check.py): +-45 turns the hip line and the stride axis +-45, 70 -> 70, shoulder line moves < 0.5 deg.
  Alert soldiers (who keep facing where they look, up to 70 deg off their path) were the main sideways sliders.
- Calm wading off-axis (> 75 deg, moving): the gun-up 8-way wades, like the dry calm walk (it slid at any angle).
- Calm turn rate not changed: already 320 deg/s.
- Build 32/32 models. Harness hips (new) 14/14, gait 1013, recoil 496, gunhold 19, toplists 4, stage78 36, passive 28.
  Syntax 157 files clean.

### 0.38.7: the rest of the civilian animations (2026-11-18, NOT yet run in game)

User: "survey and implement the remaining citizen animations." Survey: MW19 953 civ_ clips, MW22 2005 (scratchpad
civ_triage.py: type, leg tracks, additive look, root travel/turn). Built (manifest civ22_family, ~110 roles, model
mw_male_civ22; stick scan 0/180 civ clips):
- civ_react_<sm1|sm2|md1|md2|lg1>_<n>: threat at numpad n, flinch into a run away from it (100-330 in, turns 0-180).
- civ_startle_<1|2l|2r|3|4|6|7|8|9>: startled turn to face it.
- civ_panic_idle_1-12 (incl. MW19 frantic twitches), civ_scared_idle_1-7, civ_stand_1-7 (calm: weight shifts, arms
  folded, looking round).
- civ_tocower_n -> civ_cowering_n -> civ_uncower_n (1-3); civ_prone_1-6 (flat, hands over the head).
- civ_walk_1-4, civ_wwalk_1-4 (wary), civ_chat_1-6 (group talking loops, face forward within ~18 deg),
  civ_pevade_2/4/6/8, civ_duck_run.
Left out: door opens (no leg tracks, upper body only), female / phone / texting / tourist / selfie / seated scenes
(props or female rig), stairs (no stair detection), punched reactions (civilians die to any hit).
Wired (entities/tif_civilian.lua):
- First scare while standing about (ENT:React, start of flee / leave): the reaction for the threat's direction, size by
  fear (lg >= 0.85, md >= 0.5), shorter one or a startle where RoomFor (hull trace + ground) says no room; far
  (> 1200) and fear < 0.5: startle, then off.
- OneShot root motion now hull-traced and kept on the ground per tick: stops short (clip too) at walls / people /
  drops. Returns true when played through.
- Idle by fear: panicked >= 0.5, scared > 0.05, else the civilian's own calm idle; MW19 twitches play as fidgets
  (35% of wander stops). Fear resets after 45 s quiet in wander.
- Walks: own walk of five; wary walk while fear > 0.05. Flee: duck run for a third of civilians when fear > 0.85 and the
  danger within 700 (not for scattering).
- Talk: own chat loop, random start cycle.
- Hide in the open: MW22 cower chain joins the scared-pose pool (got down into, up out of when leaving / to point);
  fear >= 0.9, even var: prone (no pointing). Pose kept per hiding place. Pointing uses all 8 directions now.
- Wall hides beckon fleeing / scattering civilians 150-700 away (every 15 s; civ_beckon was built but unused).
- Wander / talk waits: someone (player, TIF soldier) walking into it (within 110, closing at > 40) makes it step aside
  away from their line (civ_evade, civ_pevade when scared; civ_evade was built but unused); 2 s cooldown after.
- Harness civ_anim (new) 52/52; civ_body 10/11 (the known flaky scatter-removal check). Syntax 157 files clean.
Known: a few panic / scared idles stand twisted 35-60 deg off forward (hips); fine for idles, not aimed at anything.

### 0.38.6: the "crumple" found: additive clips played as poses (2026-11-18, NOT yet run in game)

Two tif_stickwhy reports from the user both had mwz_whizby_<n> (the bullet-whizby flinch) right before. Measured per
frame on the baked SMDs (scratchpad stick_frames.py / stick_all.py: all four limbs straight, cos > 0.97, and along
the spine): every frame of every sdr_cqb_strafe_whizby_0N is a rigid stick figure (straightness 0.97-1.00, along spine
0.88-0.98) against -0.4 / 0.5-0.7 for healthy clips. They're ADDITIVE data baked as absolute poses (keys on every
bone, so the 0.31 / 0.38.4 checks missed them; zero_scan compared to the wrong rest). Played as a full-body action
whenever rounds snapped past -> ~1 s stick figure: the user's crumple. 0.38.4's ragdoll changes stay (real, separate).
Whole-library scan (3789 clips TIF uses): 27 with stick frames:
- mwz_whizby_1-7 -> rebuilt as delta layers mwzw_1-7 (manifest shot = (0, frames-1, 4), like the recoil kicks):
  peak local turns head 7-43, shoulders 11-42, spine2 5-10 deg, ending exactly at rest. sv_suppression S.Whizby sends
  NW2 tif_whizby_t / _n (no Act); cl_body recoil_kicks plays it on a kick slot at full weight (not tif_recoil_scale),
  not over full-body actions or prone. Now also while walking / crouched; tifReactUntil 0.3 s.
- mwp_twitch_1-9 (prone fidgets) and pstl_twitch_15-18 (sdr_com_exposed_pstl_twitch01-04): no longer built.
- mwc_<t>[p]_lean (cover lean idles): same defect but never played (cover uses the aim blend): left.
- Build: 31/31 models, 4077 roles. Harness recoil 496 (whizby cases), flashwait 19, hits 266, passive 28, gait 1013,
  stage78 36, cover 82, mw22 42, guns 231, semi 19, gunhold 19, toplists 4.

### 0.38.5: stick-pose catcher (2026-11-18)

User: not convinced the crumple is ragdoll related (seen "during regular anims"); wants a command to identify it.
The 0.38.4 ragdoll fix stays, but the cause isn't confirmed. debug/cl_stick.lua (client):
- tif_stickwatch 1: 4x a second, every soldier's host body and faction model, and ragdolls within 2500, tested for
  the stiff pose (all four limbs straight, elbows / knees under ~5 deg, and along the spine). First catch per entity
  -> snapshot appended to data/tif/reports/stick.txt + console line. Keeps a ~4 s history per soldier (act, top leg /
  upper-body clip, fullBody, prone, knocked, dying, animation errors).
- tif_stickwhy: the same snapshot for what you look at (soldier or ragdoll, stiff or not): NW act / host / knocked /
  dying / prone / vehicle / dormant / nodraw, main sequence + all 8 layers (sequence, weight, cycle, valid), host and
  faction-model pose test, follower parent / nodraw / retarget, client fullBody / slotsOk / clips, last animation
  error with traceback.
- cl_body: animation errors now xpcall with a traceback, kept per soldier (st.lastErr) for these.

### 0.38.4: stiff "crumpled" ragdolls, CQB flash chance / wait / in the room (2026-11-18, NOT yet run in game)

Crumple (user clip: a soldier mid grenade-throw ends up laid out straight, "arms and legs straight in the direction the
torso is facing", any faction). Cause: ragdolls made without a death clip (blast knockdowns, deaths that skip the
clip) take their pose from the server's bones, which hold only one pose per stance (the standing aim / relaxed / crouch
hitbox pose, not what the client shows); every bone got the same velocity and the whole blast went onto one bone, so
the body was thrown and landed as a rigid plank in the aim pose. Also: H.Knockdown cleared the action first.
Checked and ruled out offline: no baked clip (4345 SMDs, scratchpad zero_scan.py) has zero-pose frames.
- TIFMakeCorpse: no death clip -> the current action is posed on the server first (ResetSequence + cycle from
  tifAct, SetupBones); each bone gets a little random velocity / spin; the force goes half to the nearest bone, half
  spread over the body. H.Knockdown makes the ragdoll before Act.Clear.
- Also fixed on the way: a faction model without ragdoll physics (55 of 81 tif_cod_factions models have no .phy)
  used to get a ragdoll of mw_male.mdl, which has none either (a frozen zero-pose figure). Now a stock ValveBiped
  ragdoll (HL2 rebel) posed by bone names, dressed by clients with the faction model (NW2 tif_vb_dress: bone-merge,
  or the retarget map for codport ports); a one-time warning names the model.
CQB flashes (user: not always; when they do, wait for it to go off; force it into the building):
- tif_cqb_flash_chance (0.55): a roll per room (cq.flashWait reset per door).
- flash_in no longer returns a guessed delay: cq.flashWait waits for the grenade's detonation (tifDone / removed),
  then CQB.AFTER_BANG 0.25 s; FLASH_WAIT_MAX 5 s safety; no wait if the thrower died before release.
- GR.Throw opts.force -> tif_grenade.tifForce { pos, door, inward }: once inside it's noted; crossing back out through
  the doorway its velocity is turned back in; not in the room (24 u past the doorway) when the fuse ends -> it goes
  off at the target point instead.
- Harness flashwait.lua 19 new; mw22 42, test 82, hits 266, stage78 36, gait 1013, move 20, guns 231, semi 19,
  recoil 490; civ flaky.

### 0.38.3: FAL damage 33 (2026-11-18)

User: the semi FAL a middle ground between the rifles (22 per round) and the DMRs (44): 33. gun_tune.py dmg field
(the only per-gun damage override; lua_block writes SWEP.GTG.damage and notes it in the header). Range / falloff stay
the rifle base's. Roughly: up close ~49 dmg/s (DMR pattern, 0.68 s average gap) vs the AKM's ~74 sustained; far out
it out-trades the auto rifles' 1-2 round long-range bursts per shot. Harness guns 231, semi 19, fire 17.

### 0.38.2: semi-auto fire patterns by range (2026-11-18, NOT yet run in game)

User: DMRs slightly spammy up close, spaced out far away; the Rytec spaced out; the FAL the same as the DMRs.
Before: semi guns fired one round per the carrier's archetype pause (marksman 0.9-1.7 s x range factor), so a Rytec
fired as often as an SVD and DMRs never strung shots.
- sv_weapon W.SEMI patterns, chosen by the gun (def.semi), whoever carries it: burst_size / cadence / pause use them
  before the archetype's burst habits; never faster than the gun's rate; walking caps a string at 2.
  dmr:   close 2-3 rounds 0.3-0.4 s apart, then 0.9-1.4 s; mid 1-2, 1.0-1.4 s; long 1, 1.8-2.8 s.
  heavy: single shots, close 1.8-2.2 s, mid 2.2-2.7 s, long 2.7-3.3 s.
- gun_tune.py semi = "dmr": ebr, ebr_sup, sks, svd, svd_plague, m13_dmr, fal (FAL back to semi-auto); "heavy": rytec.
  lua_block writes SWEP.GTG.semi.
- Measured (harness semi.lua, sv_weapon's own functions, 60 s of fire): DMR / FAL average gap close 0.66-0.68 s
  (2.4-2.7 per string), mid 1.2 s, long 2.25 s; Rytec 2.0 / 2.45 / 3.0 s. Same for marksman and rifleman carriers.
- Effect at the same damage: DMRs (44 per round) about double their output up close, +60 % mid, same far out. The FAL
  keeps the rifle base's 22 per round, so as a semi it does well under half an AK's damage per second (needs a damage
  call from the user if that's too weak).
- Harness semi 19, guns 231, fire 17, wclass 39, bipod 6, gunhold 19, stage78 36.

### 0.38.1: per-gun handling (2026-11-18, NOT yet run in game)

User: tune the guns everywhere except damage; faster rates may make fights the same length or quicker. Before this
every gun used its class base's rate / magazine / mode (DMRs full auto, FAL 30 rounds, double-barrels 8 shells...).
- K:\jimmyproject\tif_guns\gun_tune.py: TUNE[id] = rpm, auto, mag, reload (real guns / MW19 / MWII, rounded).
  lua_block() -> each weapon_tifmw_*.lua after its model line (SWEP.Primary ClipSize / Automatic, GTG.rate = 60 / rpm,
  GTG.auto, GTG.reload_time); gun_compile.py writes it on rebuilds. Damage, range and falloff untouched (base's).
  What each does in TIF: rate = gap inside a burst (pistols use W.PISTOL timing); auto = false -> 1-2 round groups;
  mag -> reload frequency; reload_time -> time out + the MW reload clip stretched to it. (def.spread is unused:
  accuracy is the archetype's.)
- DMRs (ebr, sks, svd, m13_dmr, rytec) semi-auto now; LMG belts 75-100 (mg34 50); SMG mags 30-64; pistols 8-17;
  double-barrels 2; 680 pump 7; rifles 20-30.
- Fairness (scratchpad dps_model.py: sustained damage from sv_weapon's burst model, rifleman / support / marksman
  archetypes, close and mid range, hit chance aside). TIF bursts are mostly pauses, so rpm moves it little; mags and
  semi-auto do. After rebalancing the slow ones (FAL select-fire 650, Oden 520, SCAR 650, quicker reloads; 680 7 shells):
  rifles -3 / -2 %, SMGs +11 / +7 %, LMGs +12 / +9 %, DMRs 0 %, pistols +5 / +3 %, shotguns -12 / -14 % (close / mid).
  Slower individually by design (small real mags): FAL -9..-13, Oden -10..-15, SCAR -7..-10, Rytec -9..-11,
  double-barrels -21..-27 %. Faster: MP7 +21, Bizon +18, Bruen +16, M19 +15 % (close).
- Harness guns 231, fire 17, wclass 39, bipod 6, gunhold 19.

### 0.38.0: GTG / GTA content removed from the base (2026-11-18, NOT yet run in game)

User: "since we have our own vehicles now, you are free to completely remove gtg stuff from the main addon". Decisions
(asked): other Glide vehicles get a generic MW seat; window drive-bys dropped. Base 382 -> 159 MB (615 files).
- Moved (not deleted) to K:\jimmyproject\_addon_backups\2026-11-18\gtg_from_base (223 MB): lua/tif/gta sh_data,
  sh_vehicle, sh_driveby, sv_weapons, sh_fx, sh_sound, cl_tint, data/ (GTA sound table), clips/lib_*.lua (36) and
  mp_m_freemode_01 (clips + character), weapons/weapon_gtg_*.lua (45); entities/effects tif_gta_* (projectile, cloud,
  explosion); models/ materials/models/ materials/ sound/ tif_gta_assets; tif/spikes (Phase 0) + tif_spike_bot.
- Kept from the old bundle (no GTA assets): sh_core.lua (clip / character / weapon registry, now hand-maintained; a
  stub TIFG.Data), playermodel/* (TIFG.PMS retarget: codport modular factions need it). sh_init loads only those,
  clips (mw_male, zz_jgun*), characters (mw_male), weapons. build_gta_bundle.py retired (refuses without --force).
- One body: compat/sh_gtg.lua rewritten. DEFAULT_HOST = FEMALE_HOST = MW_HOST = "mw_male"; HostFor always it;
  tif_mw_anims convar gone. sv_action: no switch to a GTA body for clips the MW body lacks (the action just doesn't
  play, warning). tif_soldier prone hitbox pose mwp_idle.
- Guns: lua/tif/gta/weapons/_tif_bases.lua (TIFG.WeaponBases rifle / smg / lmg / shotgun / marksman / pistol /
  launcher), flattened from the 7 GTA defs (scratchpad make_bases.py) minus GTA anim names / models. The 44
  weapon_tifmw_* copy a base by key (gun_compile.py writes it so). Defaults weapon_gtg_carbinerifle ->
  weapon_tifmw_m4_sof_a (sh_content, sv_weapon); GTA gun names in old configs still resolve (tif_guns_alias).
- Gun sounds: MW sounds are MW Base's sound scripts (mw_base_* Workshop addon = a dependency for gun audio). sv_weapon
  checks sound.GetProperties: not registered -> the gun's own HL2 sound (def.sound). GTG GTA audio fallback gone.
- RPG: entities/tif_rocket.lua (HL2 missile model, accelerating 500 -> 4000 like the GTA rocket, smoke trail, glow;
  blast tif_rocket_damage 200 / tif_rocket_radius 300); TIF.GTG.Launch spawns it (projectile.entity).
- Surrender / captives: MW22 bdr_1100_stash_woman_surrender react_alt_enemy01 (down, turns ~118 deg, root motion)
  then react_idle_alt_enemy01 (kneeling loop): roles mwsu_down / mwsu_idle (manifest surrender family). TIF.Morale
  .Kneel(npc, quick) + KneelThink; API.SetCaptive uses it (quick). (Was GTA getup_tk* last frame.)
- Vehicles: TIF.GTG.SeatPose = generic MW seat for Glide vehicles without TIF seat data: Cherokee seat idles
  (mwck_s0 driver, s1 front, s2 / s3 rear) at the Glide pod, tif_mw_seat_drop (34) below it, exact; SeatEntry nil
  (walk to Glide's exit spot). Drive-bys removed (sv_vehicle driveby stub, tif_driveby convar gone). Q menu: recoil
  strength slider; tif_mw_seat_drop replaces the GTA seat-fit sliders.
- Self-test: MW body clip groups, MW Base sound check, gun models; no GTA symbols / libraries / wOS prone.
- Checks: all 156 Lua files parse; every TIFG symbol used is defined; manifest entries exist; no other addon uses
  removed APIs or GTA gun names. Harness: guns.lua 231 new (44 standalone guns, rocket); all suites pass (civ flaky).
- Untested in game: the generic seat height in non-TIF Glide cars (tif_mw_seat_drop), surrender turn / kneel,
  the rocket's flight and blast, guns without MW Base (HL2 sounds).

### 0.37.0: release packaging: MW anims + guns in the base, GTA cars out (2026-11-18, NOT yet run in game)

User: MW anims the default; pack them and the guns into the base for the Workshop release; vehicles are the TIF
vehicle addons now (tif_mw_cars, tif_air), so the GTA vehicle parts go.
- tif_mw_anims 1 by default (compat/sh_gtg.lua; FCVAR_ARCHIVE: a server that saved 0 keeps 0).
- tif_mw_anims (lua: clips mw_male*.lua + zz_jgun*.lua, characters/mw_male.lua, the tif_mw_view clip viewer;
  models/tif_mw) and tif_guns (lua: 45 weapon defs + alias autorun; materials; models/tif_guns) copied into the base:
  489 files, no path collisions, sizes verified. The two addons moved (not deleted) to
  K:\jimmyproject\_addon_backups\2026-11-18\. tif_gunbake (exporter tool, no addon.json) and tif_mw_anim_test stay out.
- Build tools now write into the base: manifest ADDON, gun_holds.py CLIPS_LUA / JGUN_LUA, gun_compile.py ADDON,
  tif_air harness car_seat_harness.py. (The builder only replaces its own files: models/tif_mw/*, mw_male*.lua,
  zz_jgun_h*.lua; the GTA clips beside them are untouched.)
- GTA car pack out of the base (87.8 MB): lua/tif_gta_glide_cars, models/, materials/models/, sound/
  tif_gta_glide_cars, lua/entities/tif_gta_glide_cars_*.lua (9) -> the same backup folder (gta_glide_cars_from_base).
  build_gta_bundle.py no longer runs build_cars(). The GTA bundle's own vehicle code (sh_vehicle / sh_driveby, GTA
  seat / drive-by anims for the GTA body) stays: female factions and soldiers with mwAnims = false still use it.
- sv_mounted: MT.CAR_FALLBACK / MT.DefaultCar() (first installed of cherokee, ram1500, hilux, tundra, defender,
  ram1500_armor, choptop); MT.VehicleClass maps gtg_grandtheftgmod_* / tif_gta_glide_cars_* to it. sv_base convoy
  default, tif_range preset convoy, tif_convoy command default, custom faction vehicle lists use it. Selftest checks
  base_tif_mw_car, the default car and the mw_male host instead of the GTA cars.
- Other addons switched to MW cars (user, same day): no GTA car class named anywhere now.
  - DTW sh_config: VehiclesFallback = the other side's MW cars (enemy kamaz / defender, friendly ram1500 / cherokee);
    Trucks enemy kamaz, hilux / friendly mtvr, kamaz; Escorts enemy tundra, hilux / friendly ram1500_armor, defender;
    BackupVehicle defender, ram1500_armor. sv_support backup falls back to TIF.Mounted.DefaultCar(). sv_reinforce:
    a faction list with nothing installed now tries C.Reinforce.Vehicles before the fallback; log strips tif_mw_.
  - GOPS sh_vehicles: transport red hilux / kamaz, blu defender / mtvr, any ram1500; technical red tundra / hilux;
    patrol cherokee, red choptop, blu ram1500; evacuation defender / ram1500; ifv blu ram1500_armor; target hilux /
    cherokee ("heavy" left empty: falls back to technical).
  - tif_faction_pack: ALLY_VEH defender, ram1500_armor, mtvr; ENEMY_VEH cherokee, hilux, tundra, choptop.
- Base addon now 382 MB / 7987 files. Harness: all suites pass (vehclass 9 new; civ passed this run too).

### 0.36.1: recoil wherever he shoots (2026-11-18, NOT yet run in game)

0.36.0 skipped every full-body action, and MW19 cover aiming is one: firing from cover (most fights) had no recoil;
prone had no pool. Now:
- Manifest recoil +139: mwfk_lean_<ls|rs|lc>_<i> (35 each: cover_<side>_<stand|crouch>_lean_fire + burst2-6 + semi2-5),
  mwfk_lean_rc_<i> (15: hm_grnd_org_cover_right_crouch_lean_fire[_semi2-5]_ar), mwfk_prone_pr_<i> (19:
  hm_grnd_red_prone_burst_03-06_ar, prone_fire01_ar). Lean kicks are gentler (gun 1-2 deg avg), prone 0.7 deg avg; all
  end on their first pose. 227 kicks in all; 30/30 models, 4087 roles.
- cl_body kick_pool(): lying still aiming (vbProne 2 + prone aim blend) or on the prone bipod -> prone pool (bipod
  at Bd.BIPOD_W 0.4); cover aim act mwc_<t>[p]_aim -> lean pool of that corner (ls / rs / lc / rc), cr -> crouched,
  st -> standing, pistol in cover -> pistol; mwb_<set>_aim (wall / ledge bipod) -> crouched / standing at BIPOD_W;
  other full-body actions (blindfire has its own firing, hiding, transitions) none; launchers none. A running kick is
  cut only by a non-shooting full-body action. compose stores st.actName.
- Last stand: never fires (gun gone while down), nothing to do.
- Harness recoil.lua 490/490 (pool choice for each situation).

### 0.36.0: recoil from MW19's own firing clips (2026-11-18, NOT yet run in game)

User picked option A of the survey below: per-shot clip kicks.
- Builder (tif_mw_build.py): opts {"shot": (note frame, frames, back)}: the clip baked as usual, then shot_slice() keeps
  frames note .. note + w and appends `back` frames slerping every bone back to the note pose; no root motion; entry
  kick = true. QC: `$animation a_<seq>_ref ... frames 0 0`, `$animation a_<seq> ... subtract a_<seq>_ref 0`,
  `$sequence <seq> a_<seq> delta weightlist "tif_upper"` (family_seqs tuples gained a delta flag).
- Manifest family recoil (88): mwfk_<rifle|pistol|shotgun>_<st|cr>_<i>, one per "fire" notetrack: rifle stand 34
  (exposed shoot_auto_01/02, burst_02-06), rifle crouch 34 (crouch_burst_03-06, crouch_shoot_auto_01/02), pistol 14
  (stand_pstl_burst_02-05), shotgun 3 + 3 (stand / crouch shotgun_fire01-03, note to clip end: includes the pump).
  w = to the next note, 3-6 frames; back 5. Checked on the baked SMDs (scratchpad kick_check.py): rifle gun up avg 2.1
  (max 5-6.5) deg, right hand 2-3 u; every kick ends exactly on its first pose.
- sh_anim L.kicks[kind][st]. cl_body recoil_kicks(): a new networked shot (GetTIFShotTime, within 0.5 s) -> a random
  kick from the weapon's pool (pistol / shotgun / rifle; crouched pool if any; launchers none) on the next of layer
  slots 5-7 (free until now), weight Bd.KICK_W x client convar tif_recoil_scale; played once, dropped at its end. Not
  during full-body actions or prone. vb_pose's spine kick only where the body has no kick clips.
- Harness recoil.lua 192/192.

### Recoil survey (2026-11-18, no code changed)

User finds the spine-bend kick weird. Current recoil = vb_pose spine2 / spine4 kick on each networked shot
(SetTIFShotTime -> st.flashAt); the per-weapon fire clip layer (ub_targets st.fireClip, mw_fire_<kind>_<n>) is wired
but no mw_fire_* clips are built, so it never plays.
Candidates (MW19 duglastakedown, all full-body, one "fire" notetrack per shot):
- sdr_com_exposed_burst_02..06, shoot_auto_01/02 (stand), crouch_burst_03..06, crouch_shoot_auto_01/02, riot_* twins,
  cover_left_stand / left_crouch / right_stand lean_fire_burst2..6 / semi2..5, exposed_stand_pstl_burst_02..05,
  exposed_stand / crouch shotgun_fire01..03 (fire + "rechamber" note).
- MW22 shoot_single / lmg / sg ones: no gun bone motion, no notes: useless. sdr_mp_empty_additive_fire: empty.
Measured on our body (scratchpad recoil_bake.py), rifle shots: gun up 2-5 deg peaking 2-6 frames after the note,
pulled back ~1.2 u, chest only 1-2 deg, yaw jitter 3-6 deg; gun back to its start pitch at the clip end. Pistol bursts
read odd on j_gun (pistol gun-bone convention: needs the hand instead). Shotgun clips include the pump (gun to -46 deg).
Options: (A) per-shot additive gesture cut from the fire notes (delta vs the note frame, upper body, random per shot,
any locomotion) - recommended; (B) whole burst clips on the upper body with server fire timed to their notes;
(C) keep code recoil but shaped like the measurements, mostly arms / shoulder.

### 0.35.5: last few degrees of aim (2026-11-18, NOT yet run in game)

User on 0.35.4: high aim "largely fixed, maybe 5 degrees too much"; slings now dangle instead of merging into the
chest (good: the let-go / sling path is finally live). Residual: MW19's AI aimed idle holds j_gun 1.1 deg up, and the
recoil kick (spine2 3.5 / spine4 2.1 deg back, linear over 0.14 s) never settled at automatic rates: ~3.6 deg held
while firing. vb_pose: aim pitch + Bd.AIM_TRIM (client convar tif_aim_trim, default 1.2 deg down; the two spine bends
carry 0.9 of it); kick 2.5 deg easing out (quadratic) over 0.09 s (~1.2 deg average while firing at 600-900 rpm).

### 0.35.4: guns held high: the real cause (2026-11-18, NOT yet run in game)

Third / fourth tif_aimwhy reports (AK-74U engaging, MP5 returning to post): client tables loaded (548 / 627), top leg
clip driven, yet jrotW still 0.00. Cause: cl_body top() filled and returned ONE shared table. compose took
legTop = top(st.legW), then ubTop = top(st.ubW) cleared and refilled the same table, so the gun code after it looped
the upper-body list (usually empty) as the legs: ld = 0 -> jrotW = 0 (and jgunW from the legs = 0). Every gun was held
in the right hand's frame, which on MW19's AI aims sits ~24 deg off the barrel (the wrist bend KR describes); the left
hand IK then pulled the left hand up onto it (hands line -27 against -4 in the clips). Probably since the jrot / jgun
code went in: so the gun-bone rotation (KR) and the clips' let-go positions (grenades, activities, from the legs) never
ran in game before. Watch for: gun rotation in campaign / activity clips, grenade and smoke / phone hand-offs.
- top(weights, n, buffer); LEG_BUF / UB_BUF. Harness toplists.lua 4/4; gunhold 19, stage78 36.
- (0.35.3's split of zz_jgun.lua stays: harmless, and the tables did load on the client.)

### 0.35.3: aim-high investigation (2026-11-18, closed in 0.35.4)

User screenshot (0.35.2): four soldiers stacked along a wall end, standing aimed, guns ~20-25 deg high, torsos leaning
back. Checked offline, not the cause:
- Every looping clip's gun direction on frame 0 (445 loops, j_gun barrel, tif_mw_build aim_dir): all aimed / CQB /
  strafe / wade / alert loops are within ~2 deg of level. Only seated, vehicle, cover-hide and shuffle loops point
  elsewhere (not aimed poses). lowready / lowready_cqb point down (31-42 deg).
- Face points: doorway centres are floor level (doorAim +50 is below the 62 eye), contacts are floor positions + 40.
So the lean comes from the runtime aim pitch (vb_pose spine bend, 0.45 x pitch on spine2 + spine4) or an action /
layer not identified yet. Added `tif_aimwhy` (look at the soldier): server face / aim targets and the pitch they give,
CQB / low ready / rungun / wade / act / cover state, then the client's top leg and upper-body clips and the spine
manipulation; appended to data/tif/reports/aimwhy.txt.
First report (AS VAL soldier backing off, firing): server pitch +5.9 (down), spine manip ~0-1 deg, legs = the backward
aimed walk overlay. Nothing high on the host. Further offline checks: every frame of every aimed walk / jog / CQB / wade
cycle has j_gun within ~3 deg of level; hands line -4 (idle) / -13 (CQB walk); spine bend sign right (spine2/4 local
Y points forward 0.83 / 0.74: + yaw bends forward); no duplicate sequence names over the 29 QCs (3957). The gun is
placed from the HOST's j_gun (driven clips) / right hand, so a high gun with hands on it points at the drawn faction
model differing from the host: suspect the retargeted (codport CoD-rest) modular models. tif_aimwhy_cl now also
prints host vs faction model hand line and chest pitch, gun pitch, jrotW / jgunW, and whether the model is retargeted.
Second report (M13 SOF soldier, strafing left, plain mw2_soldier_03, not retargeted): host and faction model agree
(hands line -28.4 up vs -4 in the baked clip), and jrotW 0.00: the gun turned from the right hand's frame, not j_gun,
though the overlay clip is driven (not in TIFG_JGUN_UNDRIVEN). driven() is 0 only when TIFG_JGUN_UNDRIVEN /
TIFG_JGUN_HOLD are nil: the client didn't have zz_jgun.lua's tables (0.9 MB; loads fine in LuaJIT 2.0 / 2.1 offline,
no other addon defines them). The left-hand IK then pulls the left hand onto the tilted gun (the -28 line).
- gun_holds.py now writes TIFG_JGUN_HOLD in parts (zz_jgun_h<NN>.lua, 60 entries each, after zz_jgun.lua which keeps
  TIFG_JGUN_UNDRIVEN and resets HOLD).
- cl_body warns once in the client console if the tables are missing; tif_aimwhy_cl prints whether they exist and how
  the top leg clip is classed.

### 0.35.2: CQB cover, door flash clip, wading, burning rework, committed cover exits (2026-11-18, NOT yet run in game)

- CQB cover (manifest cqb_cover, 564 roles): MW19's sdr_cqb_cover_* are arrivals / exits only (walk / fast, rifle +
  pistol, all six types); the hide / lean / aim clips stay the type's own. mwc_<t>[p]_arr_<cwalk|cfast>_<foot>_<n>,
  mwc_<t>[p]_<cexit|cfexit>_<n>. sv_cover_mw pick_arrival: CQB style (tifCQB / tif_cqb / cover node indoors,
  BLD.Indoor, cached cov.indoor) or arriving under MW.CQB_WALK_MAX (130) -> cwalk / cfast arrivals, else jog / run.
  pick_exit: CQB style -> cexit (cfexit under suppression > 0.5), else jog.
- Door flash: CQB flash_in plays mwdr_<l|r>_flash (in place, no notes). Measured on the baked SMDs (left hand):
  l releases frame 25/67 (u 0.373), hand (40, 3, 42), throw 15 deg left of facing; r frame 26/74 (u 0.351), hand
  (-2, -40, 43), throw -106 deg. CQB.DOOR_FLASH; door_flash() picks the one that turns him least, faces him so the
  throw heads at the target, releases from the hand. Falls back to mwg_throw_stand.
- Wading (manifest wade, MW22 sdr_wtr_*): mwwd_idle / walk / fast 8-way (AI_ARMS overlay like the dry MW22 strafes),
  mwwd_calm_<knee|chest>_idle / walk. sv_brain: NW2 tif_wade (water at +14 = 1, +34 = 2; every 0.4 s). sv_move
  speed_of caps the pace M.WADE_CAP {60, 45} (clips ~30-50 u/s). sh_anim L.wade; cl_body leg_targets standing, not
  pistols: aimed -> 8-way wade set, else calm set by depth.
- Burning (found while adding prone burns): every MW19 molotov reaction except the four *_sling ones ENDS LYING ON THE
  GROUND (j_mainroot z -10 -> -80): they're burn-to-death sequences. 0.34's mwz_fire_<1-8> / mwz_fire_cr_* (those
  clips) would have popped him back up. Now: mwz_fire_<1-4> = the sling reactions (patting an arm / leg, on his feet;
  crouched men stand for it), mwz_fire_pr_<1-4> = prone_reaction01-04 (rolling, prone-centred, cl_body proneAct).
  Deaths by DMG_BURN: situation burn (23 standing: reactions / frantic / long / crawl), burn_crouch (11), burn_prone (4,
  prone-centred, PRONE_CUT). Prone pains 01-04 (end standing) unused.
- Cover exits commit (user: wall exits "sprint off but don't commit"): MW.PickCalmExit. Next destination
  (MW.ExitGoal: squad leader > 220 away, else post > 150 away). A jog exit heading within MW.EXIT_COMMIT (45 deg) of it:
  played in full. Otherwise the CQB walk exit (cexit; ended at 0.8 when there's nowhere to go), else the jog exit
  ended at MW.EXIT_CUT (0.5) (Act.Clear, cov.exitCut). Lean exits: toward the destination, same commit / cut rule.
- Build: 29/29 models, 3860 roles. gun_holds re-run. Harness: hits 266 (burn deaths / reactions), mw22 42 (door
  flash), cover 82 (calm exit cases; mock got GetNW2Bool), gait 1013, trans 55, move 20, others pass; civ flaky.

### 0.35.1: CQB stack timing and low ready (2026-11-18, NOT yet run in game)

User: wait for the whole stack, go a second later; low ready on the stack except the point man; gun up while moving
unless someone crosses the muzzle.
- sv_clear.lua stack phase: needs `ready >= #team` everywhere (inside the building it used to go at half the team),
  then `CQB.STACK_SETTLE` (1.0 s) on the full stack (`cq.fullAt`, reset if someone drops off) before breach / open.
  `CQB.STACK_TIMEOUT` 6 → 15: goes with whoever made it if a man is stuck. A commanded go still goes at once.
- Stack members get `tifCQB.lowReady = (i ~= 1)` once on their slot; the back-stack men always.
- sv_brain.lua `low_ready`: `tifCQB.lowReady` → down at once (0.4 s enter). Any other CQB phase (entry, moving,
  hold) → no quiet rule; down only for a friendly in the line of fire or `mate_across` (a squadmate 8-170 u ahead
  within 26 u of the facing line), 0.15 s enter. Outside CQB unchanged (2.5 s quiet). `LR_QUIET_CQB` removed.
- Harness mw22: 38/38 (new stack / low-ready checks); gait, move, fire, stage78, push pass.

### 0.35.0: grenade rework, CQB flashbangs, tier 2 animations (2026-11-18, NOT yet run in game)

- Grenades: `entities/tif_grenade.lua` (kind frag | flash), the SandSWEP M67 / M84 models packed into TIF (models/weapons/
  sandswep/throwables/w_sand_m67|m84, materials/models/sandswep/m67|m84; textures shrunk 53 MB -> 2 MB with codport
  tex_shrink --cap 512). Frag: blast (tif_grenade_damage 150, tif_grenade_radius 320), explosion, scorch, shake. Flash:
  TIF.FlashAt on soldiers in sight, white-out + ringing on players in sight. `GR.Throw(npc, target, src, kind)` uses it
  unless the faction has `grenades = "hl2"` (npc_grenade_frag, no flash: for a Combine faction). The grenade dodge
  (sv_react_mw22) takes tif_grenade frags only (tifDodgeable).
- CQB: breachers flash each room before going in (`tif_cqb_flash`: 0 off, 1 squads allied to a player (default), 2 all):
  the stack's second man throws a flash CQB.FLASH_DEPTH into the room (MW19 stand throw, released on its note); the entry
  waits for it.
- Run and gun: the covering burst on a dash to cover keeps running with MW19's AI rungun clips (mwrg_<f|l|r|bl|br> by
  the aim's angle off the run, NW2 tif_rungun, tifAimFree); no other firing on the run (user rule). Else the aimed walk.
- Doors: `tactics/sv_door_mw.lua`: a closed, unlocked prop_door_rotating right ahead on a path (not in room clears):
  MW19's door interaction (tac push walking, shoulder / kick running), side by the clip's drift vs the hinge, started so
  its contact lands on the door; the door opens away from him at D.CONTACT (estimates: the clips have no door note).
  `tif_door_anims`.
- Point out / look around (sv_passive_mw OnAware): contact past P.POINT_R (900) while on edge, not under fire: one man
  per squad (25 s) points it out (mwe_point[2]_<n>, x1.4, "contact"); lost contact -> searching: mwe_look[2]_<n>.
- Reactions: whizby flinches (sv_suppression S.Whizby: a round within half the near-miss distance, 30%, 4 s), vehicle
  dodge (sv_react_mw22: a vehicle > 220 u/s heading at a soldier within 1.3 s / 70 lateral: mwz_vdodge[_short]_<n>),
  on fire (sv_hits_mw: DMG_BURN -> mwz_fire[_cr]_<i>, H.FIRE_COOLDOWN 9 s).
- Stairs / slopes: cl_body st.grade (vertical / horizontal speed, smoothed): > 0.45 stairs (mwst_<calm|calmf|alert|
  alertf|aim|fast|run>_<up|down>), > 0.22 slopes (mwsl_<slwalk|walk|jog|run|sprint>_<up|down>), moving about forward.
- Offline: move 20 (new: run-and-gun directions), gait 1013 (covering burst check updated), cover 80 (frag is a
  tif_grenade with its fuse), hits 252, trans 55, mw22 30, others unchanged; civ's flaky check. Models 27/27, 3244 roles.
- Not done (tier 2): CQB-style cover (sdr_cqb_cover_*, a second indoor cover type), wading (sdr_wtr_*), prone / crawl
  burning, the door flash clip (sdr_com_inter_*door_flash: no motion / notes to place it), vehicle dodge on prone men.

### 0.34.0: tier 1 animations + AI strafe gun fix (2026-11-18, NOT yet run in game)

- AI strafe gun aim (user screenshot: forward walk aimed ~20-36 deg up): MW22's AI strafes / their starts / stops and
  the MW22 crouch turns / turning crouch-downs have placeholder arms (CoD lays an aim layer over them) and a gun bone
  fixed to the shoulder; TIF held the gun from our retargeted hand. Builder `overlay` + `overlay_mask`: the AI aimed
  idle's first frame on the 13 ready-pose bones (sdr_com_exposed_<stand|crouch>_idle01 masked by *_ready), and the
  chest pinned per frame (j_spine4 solved so mainroot*spinelower*spineupper*spine4 = the idle's): the strafes' lower
  spine leans back up to ~21 deg. Measured gun pitch after: 1.1 everywhere (= the idle). Overlay clips get their own
  `from` (seq name), so the gun-hold tables treat them as driven: the gun follows the overlaid gun bone.
  (Checked every hand-held-gun clip in use: calm / alert / activity sets read -60..-75, their lowered carry; MW22 cover
  lean arrivals / exits -13..-36 left as they are: real arm motion.)
- Flashlight sets: `mwf_<calm|alert>_*` + `mwt_<turn|start|stop>_<calm|alert>f_*` while NW2 tif_light (sh_anim
  relaxedFlash / alertFlash, sv_trans_mw `lit`). Alert: a handheld torch in the left hand (cl_body st.handLight: no
  left-hand grip; cl_flashlight: torch model on the hand, beam from it).
- Knockdowns (`tif_knockdowns`): a non-lethal blast >= 18 (75%) throws him as his own ragdoll (TIFMakeCorpse) for
  1.4-2.6 s; hidden, non-solid soldier follows it; hits on it go to him; killed while down the ragdoll is the corpse
  (H.KnockDeath, OnKilled). Gets up with MW19's AI recovery clip for how he lies (H.LieOf: back / stomach / left /
  right), turned and placed from KNOCK_POSE (each clip's frame-0 pelvis and head yaw), the variant facing the threat.
- Prone dives: going prone at >= 110 u/s plays `mwp_dive_<jog|run>_<foot>_<n>` (the one ending facing the threat,
  room ahead checked), built with the new `pelvis_last` centring (last frame on the prone idle's pelvis); shown over
  the prone set (cl_body proneAct). Prone twitches `mwp_twitch_*` every 8-16 s lying still, weapon down.
- Pains: full MW19 AI sets (stand / crouch by body part and side), `<sit>big` long staggers for hits >= 35
  (H.BIG_PAIN), `pstl` with a pistol, `cqbwalk` / `cqbfast` moving in CQB; pain cap 10 -> 30.
- Pistol: 18 aim fidgets (`pstl_twitch_*`, standing aimed, not firing for 2 s) and AI starts / stops for pistol
  runs (`mwt_<start|stop>_<pstljog|pstlrun>_*`).
- Traversals at pace: `mwtr_<kind>_<size>_<walk|fast>` (MW19 AI walk / fast sets) under 120 / over 200 u/s, else jog.
- Offline: hits 252 (new: LieOf back / stomach / sides, all 32 recovery clips built), trans 55 (new: flashlight turn /
  start, pistol run start), others unchanged; civ's flaky check. Models 27/27.

### 0.33.1: stance-change clips (2026-11-18, NOT yet run in game)

- Manifest (aimove): `mwk_down_<8|2|4|6>` (MW19/MW22 AI stand -> crouch; 2/4/6 turn while crouching), `mwk_up_8`
  (crouch -> stand), `mwk_down_pstl`. `TIF.TransMW.Stance` plays one when a still, free soldier changes stand <-> crouch
  (turning variant by the turn to npc.tifFace); sv_brain holds a flip-back until a stance clip (`mwk_down_*` /
  `mwk_up_8` only: the `mwk_` prefix also holds body checks, knockdown falls and recoveries) ends.
- Note: the knockdown recovery clips (`mwk_up_<back|stomach|left|right>_<n>`, MW19 `sdr_com_recovery_*`) are already
  built (from the removed knockdown system), only not played.
- Offline: trans 51 (new: straight / turning / behind / up / moving refused / pistol), all other suites unchanged;
  civ's flaky check. Models 27/27 compiled.

### 0.33.0: stand cover, crouched corners, pistol cover (2026-11-18, NOT yet run in game)

- New MW cover types (manifest `cover2_family`, sv_cover_mw): `st` = MW19 stand cover (chest-high wall: hidden
  crouched, head 30; stands to fire over it, gun 50-55; hide_to_aim_high + aim_high blend; turns +90 like cr), `lc` /
  `rc` = crouched corners (lean round a tall wall's corner low; placed and faced like ls / rs). Tables LEFT / CORNER /
  CROUCHED / OVER replace the per-type checks (hide facing, edge placement, stance, muzzle, lean / pop rules, grenade
  forward, side switching).
- Detection: sv_cover.lua marks `pt.mid` (wall at chest height 44, none at head height 60) -> st; corners are taken
  crouched `MW.CROUCH_CORNER` (40%, +30% under suppression) of the time when the clips exist.
- Pistol cover: `mwc_<t>p_<role>` (hide, twitches, look, lean, aim blend, arrivals, exits) for all six types; `MW.Role`
  prefers it while a pistol is out (`cov.pstl`, refreshed every update), else the rifle clip. No blindfire with a
  pistol (MW19 has rifle blindfires only). Pains / grenades / shock use the rifle clips.
- Shuffle along the wall: st (either way), lc (right), rc (left) out of cover, and the shuffle's end into st / lc / rc
  (8 MW19 clips); `SHUF_TO` widened (PlanShuffle still requires all three clips).
- Deaths: `cover_st` (MW19 cover_stand deaths); lc / rc use cover_cr (those clips are MW19's crouched-corner deaths).
- Builder: the clip table is written in parts of 600 roles, each registered from its own function
  (`TIFG.RegisterClips(..., { part, parts })`, which merges). 2702 roles in one table passed LuaJIT's 65536 constants
  per function ("main function has more than 65536 constants"): the whole clip file would have failed to load in game.
- Offline: cover 80 (new: rc / st / cr typing and facing, st crouched while hidden, pistol roles, roles present, shuffle
  clips), hits 216, all other suites unchanged; civ's flaky check. Models 27/27 compiled, 2702 roles.

### 0.32.2: death variety: uncapped pools and situational deaths (2026-11-18, NOT yet run in game)

- Manifest `hits_family`: deaths no longer capped at 10 per situation / region (pains still are); left / center /
  right / "_prone" fall variants and `last_breath` join stand / crouch / prone. Death clips 146 -> 295 (stand 133,
  crouch 32, run 22, prone 15...).
- New pools: `cqbwalk` / `cqbfast` (MW19 AI CQB moving deaths), `explode_prone` / `explode_crouch`, `cover_crexp`
  (leaning out over low cover), `fireair_stand` / `fireair_crouch` (killed mid-burst), `melee` (DMG_CLUB / SLASH),
  `ledge_<rail|norail>_<st|cr>` (balcony deaths + `stand_death_fall`), `act_<smoke|phone|water>` (killed mid idle
  activity, MW19 `reb_stl_idle_stand_*_death`), `look_<under|under_low|over|high|down>` (mid search look,
  `reb_smtobj_look_*_death`). Activity / look deaths aren't centred (same root as their poses).
- sv_hits_mw: `situation()` returns the pools to try, most specific first; `H.Death` takes the first with clips,
  else stand. Order: blast (prone / crouch first), prone, seated, search look, activity, cover (low-cover lean-out
  first), melee, ledge (`H.Ledge`: waist-high rail with a drop behind it, else an open edge with a drop, in front),
  firing (35%, `H.FIREAIR_CHANCE`), crouched, CQB moving, run, stand. Pains keep the old single answer
  (`base_situation`).
- Not used: chair variants of the seated deaths, high-wall `cover_stand_death` (TIF has no straight high-wall cover
  type), pistol variants of the look deaths.
- Offline: hits 216 (12 new situation checks; the rail check caught open railings being read as open edges: the rail
  test runs first now). Other suites unchanged. Models recompiled (26 ok, 2130 roles).

### 0.32.1: prone deaths line up and end sooner (2026-11-18, NOT yet run in game)

- User: prone deaths still jumped forward and lasted too long. MW19's prone deaths / pains start with the pelvis 26.6
  units forward of the prone idle / aim / crawl; since 0.19.3 TIF teleported the body back as they started, which still
  showed (the fading prone idle drew at the moved spot; the hull trace cut the move short by walls). Now the manifest
  builds them centred on the prone pelvis (`center = ("pelvis", "sdr_com_exposed_stand_to_exposed_prone")`, as mwp_idle):
  frame 0 pelvis (1.7, 1.0) vs idle (1.4, 0.9). `prone_death_shift` only clears prone now.
- The ragdoll takes over 40-50% into a prone death (`H.PRONE_CUT`; was >= 75%): 0.8-1.7 s.
- Offline: hits 204/204 (prone checks updated: no move, 40-50% handoff). Models recompiled (26 ok).

### 0.32.0: AI movement set, reversals, low ready, cover entries, long deaths (2026-11-18, NOT yet run in game)

User: "solidly AI animations" (MW19 SP kept as variety, MP out of the main set). Manifest family `aimove`
(`ai_move_family`), builder `overlay` option.
- Locomotion: aimed strafes `mstg_walk_*` / `mstg_run_*` = MW22 AI `sdr_com_strafe_walk/jog_N` (90-104 / 150-178 u/s);
  aimed idles = MW19 AI `sdr_com_exposed_stand/crouch_idle01`; relaxed run = `sdr_com_jog_loop01` (172), sprint =
  `sdr_com_run_loop01` (217, `M.SPRINT_SCALE` back to 1.0). Strafe starts = AI `sdr_com_strafe_walk/jog_start_N`, stops =
  AI `sdr_com_strafe_slwalk_stop_*` / `sdr_com_strafe_jog_stop_*` (they drift 10-40 units at odd angles: picked by
  the numpad in the name). Crouched strafes stay MP (no AI 8-way crouch strafe exists).
- Reversals `mwt_rev_<walk|jog|cqbwalk|cqbfast>_<a>_<b>` from MW19's AI CQB strafe trans (the only AI reversal set):
  `TIF.TransMW.Reverse` when a strafing soldier (aiming, body keeps facing) moving >= 45 u/s gets a path >= 130 deg
  the other way; path following waits until the clip's `code_move` note (`a.handU`, sv_move). 1.5 s cooldown.
- Turns: MW22 AI crouched in-place turns (with diagonals) and alert idle turns join the crouch / alert sets (`*_<n>v`).
  The MP 0.6 s snap turns were tried and dropped (MP).
- Low ready redone: NW2 `tif_lowready`; cl_body lays `lowready` / `lowready_cqb` (MW19 AI `*_gun_down` 13-bone pose
  over the AI idle, built "ub") over whatever the legs play, and drops the spine aim bend. Server `low_ready`
  (sv_brain): weapon up but nothing to shoot (friendly in line, or nothing seen / fired at for 2.5 s, 5 s in CQB);
  down after 0.4 s, up at once when an enemy shows or he wants to fire, else after >= 0.8 s. The old version
  switched the whole soldier to the calm set for 0.8-1.4 s on a blocked shot only: legs flickered.
- Cover: from right beside the node (< 75 units, < 40 u/s) MW19 AI `trans_exposed_<stand|crouch>_to_cover_*`
  (`mwc_<t>_xin_<st|cr>_<k>`, `MW.PickXin` by the turn into the hide facing), warped onto the node.
- Long deaths (`mwld_*`, MW19 SP AI): body hits standing / crouched / running, 22% (`tif_long_deaths`): wounded fall,
  2.5-6 s crawl (back / belly / side) or sitting / kneeling, death clip, ragdoll at >= 85% of it. Death safety timer
  20 s for those. Shoot / mercy / martyr-grenade variants not used yet (the dying soldier's gun is hidden).
- Offline: trans 45 (new: reversal picks, cooldown, 90 deg / calm / slow refusals; MW22 turns accepted), hits 204 (new:
  long-death chains), move 14, mw22 30, gait 1013, others unchanged; civ passed this run.

### 0.31.0: animation fixes from user clips: walks, CQB entry, cover facing, bipod pitch (2026-11-17, NOT yet run in game)

- MW22 export 2 (`K:\mw22 anims 2\xanims`) has NO notetracks (not in the .cast files either). Every MW22 clip built
  from it lost footsteps, door, grenade-hand and end notes. `tif_mw_build.py borrow_notes` takes them from the same
  clip in export 1, rescaled when the two cuts are within 10% in length; moving loops still without footsteps get
  `detect_steps` (heel strike from the feet, +5 frames, checked against walk01's notes). Walk variants mwv_walk_2-4 /
  mwv_awalk_4-5 had `lplant = {0}`: foot sync broke (sped up, then a frozen slide). Breach clips now get their
  `door_open` note.
- cl_body: the foot phase follows ground speed down to 0 (it froze below 5 u/s and had a 0.5x floor); moving loops always
  use the foot phase; standing loops start at frame 0 when they come in (locomotion idles: `loopStart`; action loops:
  `actLoopT0`, kept continuous only between two standing loops such as cover idle <-> peek).
- sv_move: a full-body action that doesn't move him (a finished one-shot holding its last frame, a standing loop) is
  cleared once the path actually moves him (not downed / prone / upper-body / trans clips; `a.keepMoving` opts out).
  Sprint is `M.SPRINT_SCALE` (0.88) of the clip: 217 u/s, MW19's AI run pace (AI sprint loop 251, run 217, jog 172).
- CQB: `breach_plan` was a local declared after `setup_door` used it, so every closed door errored (since 0.20.0) and the
  breach clips never played; now forward-declared. The open-door wide slice (MW22 slice + quick enter warped 150+
  units, sliding / freezing) is gone: stack on both sides, standing, then cross. The second man goes as the point
  man reaches the doorway (or after 1.2 s), aimed walk (no aimed jog).
- Cover (MW): arrivals and the shuffle's step onto the node ignore the hull trace (`noTrace`), which stopped them short
  of the wall before snap_home teleported them in. No arrival clip: a 0.12-0.6 s glide instead of a snap.
- Low cover: MW19's `lvar` blindfire / frag clips are for cover on the soldier's right; ours is on his left (the hide /
  hide_to_aim set). They blindfired and threw into the room. Now `rvar_blindfire02/01`, `rvar_grenade_throw01`
  (measured: j_gun barrel +90 deg vs lvar -110).
- Aim blends: `aim_dir` measures from j_gun's barrel (X axis), not the hands. Bipods are authored +-90 deg pitch but had
  recorded 10 (left hand on the stock): ~9x pitch. Corner leans +-89 (was 62), low wall 62.5 (51), prone 45. (yaw: abs
  of the wrapped difference.) Models recompiled.
- Fights: advance / close-in / reacquire go to a point on their own line short of the enemy (`short_of`), not onto
  his position (two sides walked into each other). Perception: an allied player's gunfire / blasts / steps are ignored
  (friendlies investigated every shot he fired).
- Offline: harness move 14/14, mw22 30/30 (new: forward declaration, no slice, door note), gait 1013, hits 83,
  passive 28, test 45, trans 37, smart 32, stage78 36, gunhold 19, others unchanged; civ's known flaky check.
  Not yet done: direction-change clips (MW19 `sdr_mp_strafe_trans_*`, `sdr_cqb_strafe_trans_*`), see the report.

### 0.30.1: helicopter passengers spawn on board (2026-11-14, NOT yet run in game)

- User clip: a drop's squad showed up under the crosshair in seat poses, then slid off / vanished into the helicopter. `Air.Call` made them on the LZ ground (`TIF.API.SpawnSquad(lz.ground)`) and then parented them to the helicopter, which was still far out. That spawn also needed free room at the LZ (`TIF.SpawnPoints`), so a crowded LZ (the last wave holding it) gave fewer or no passengers.
- Fix: `air/sv_air.lua` spawns them at the helicopter; `debug/sv_commands.lua` `TIF.SpawnSoldiers` takes `opts.points` (exact spots, no spread / room check); `api/sv_api.lua` `SpawnSquad` passes it through. Ride harness 217/217 (new check: every set spawns at the helicopter).

### 0.30.0: modular parts by archetype (2026-11-14, NOT yet run in game)

- `config/sh_modular.lua`: `Pick(def, archId)`, combos with `arch` lists and 0 = slot not worn, `modular.skins = false`; `entities/tif_soldier.lua` passes the archetype and honours `skins`; `config/sh_factions_custom.lua` keeps both. First users: four new tif_cod_factions factions (Russian Ground Forces, Spetsnaz, Weapon Smugglers, Mexican SF Tier 1). `MODULAR.md`.

### 0.29.0: helicopters: Black Hawk fast-rope, CH-53 heavy, real ropes (2026-11-14, NOT yet run in game)

- `tif/air/sv_air.lua`: the hover height comes from the drop's rope set (`Air.CheckLZ(..., ropeHub)`); a type with
  seats of one kind only does that kind. `tif/air/sh_air.lua`: type `heavy` (CH-53). `entities/tif_heli.lua`: ropes
  are the MWII rope model posed on the client (thrown, fall, hang, sway, cut and drop). Details: `HELI_PLAN.md` §10.
- Content: tif_air `heavy(_dst).mdl`, `rope.mdl`, seat data; tif_mw_anims roles `mwhb_fr_*`, `mwhv_*`.
### 0.28.0: modular factions (2026-11-13, NOT yet run in game)

- New `config/sh_modular.lua`: factions with `def.modular` build each soldier from parts (body + head + headgear) by
  pairing rules; parts bone-merged on the faction model and its corpse (NW2 `tif_parts`), random skins, default
  bodygroups (stand-in bodies off). `tif_soldier.lua` picks them at spawn and passes them to the corpse; the faction
  editor keeps `modular`. First user: new addon `tif_cod_factions` (Al Qatala Desert, USMC Basic). Details:
  `MODULAR.md`.
- Same day: `modular.retarget` (models on another rig's axes are retargeted even on the MW19 host: cl_body
  `make_follower`; GTG's reader no longer requires Bip01_Spine; their corpse = dressed host ragdoll). Head = base part.
- 2026-11-14: arm retarget fixed (user: "works perfect": upper arm / forearm aimed at elbow / hand + elbow hinge pass);
  new client sway sim for hanging CoD gear (`TIF.Modular.Sway`, convars `tif_sway*`), not yet run in game. MODULAR.md.

### 0.27.0: vehicles can run their riders (bed gunners) (2026-11-13, NOT yet run in game)

- `vehicle/sv_vehicle.lua` RideThink: a vehicle with `ENT:TIFRideThink(npc, n, now)` handles its rider first when it
  returns true (MW pickups / technicals: bed men turn and fire from the bed). GTA cars unchanged. Details:
  `VEHICLE_PLAN.md` "All cars".

### 0.26.0: vehicles can supply their own seats and entry / exit clips (2026-11-13, run in game: works)

- `vehicle/sv_vehicle.lua`: a vehicle with `ENT:TIFSeatPose(n, npc)` / `ENT:TIFSeatEntry(n, npc)` answers for its
  own seats (the MW cars in tif_mw_cars: CoD seat idles, door-to-seat entries, run / calm / gun-up exits). Entries and
  exits flagged `rootz` follow the clip's own height and are warped onto the seat / the ground; exits hand back at
  their release point; `combatOut` for combat dismounts; hook `TIF_SeatClip` when an entry / exit starts. GTA cars
  unchanged. Details: `VEHICLE_PLAN.md` "Stage 2 + 3 as built".

### 0.25.0: infil fixes: shadows, late men, exit timing, crouched cover (2026-11-13, NOT yet run in game)

- No shadows from riders / crew; riders networked with their helicopter; exit clips get a 0.4 s lead-in; men who land
  crouched hold the LZ until the helicopter lifts away. New `tif/air/cl_air.lua`. Details: `HELI_PLAN.md` section 9.

### 0.24.0: helicopter crews, gradual approach, leaving to the map edge (2026-11-13, NOT yet run in game)

- Pilots on every helicopter (client-side dummies in the faction's looks, MW19 cockpit loops).
- Landings / rope hovers come in down an eased slope (12-35 deg, whichever is clear) instead of over-then-down.
- Helicopters leave along the longest clear way, all the way to the map edge. Details: `HELI_PLAN.md` section 8.

### 0.23.0: Little Bird and Mi-8 drops (2026-11-13, NOT yet run in game)

- Little Bird: landed off the benches (two sets; bench exits run / ready / patrol). Mi-8: 12 landed (+ juggernaut),
  12 down four ropes. Men handed back moving in every set (no `finish`-note waits). `tif_heli_drop mi8 rope`, etc.
- Harness: drops 108/108, flight 20/20. Details: `HELI_PLAN.md` section 7.

### 0.22.1: landed drop flies with the doors open (2026-11-13)

- Doors stay open the whole flight for a landed drop (user). Details: `HELI_PLAN.md` change log.

### 0.22.0: helicopter passengers: landed drop + rappel (2026-11-13; checked in game: "solid")

- `TIF.API.CallHeli({ ..., passengers = { faction, count } })`: a squad rides in on the Black Hawk's CoD tags and gets
  out with MW19's clips (6 landed through the doors, 8 down two ropes from 920 up), handed back to TIF already moving
  at the clip's release point; the helicopter leaves once they're out. `tif_heli_drop [auto|land|rope] [faction]`.
- New `tif/air/sv_air_ride.lua`; `npc/sv_brain.lua` gets one branch for riders (first, before the vehicle branch).
- tif_mw_anims: new family `heli` (28 clips). Harness: drops 21/21, flight 20/20. Details: `HELI_PLAN.md` section 6.

### 0.21.1: helicopter fixes (2026-11-13; checked in game: OK)

- Client bone setup never ran (method named like the engine's `SetupBones`): rotors still, error spam. Fixed.
- Model faced 90 deg left (studiomdl's compile turn): un-turned in `heli_build.py`, recompiled. LODs removed.
  Details: `HELI_PLAN.md` change log.

### 0.21.0: reinforcement helicopters, Stage 1: Black Hawk model and flight (2026-11-13, NOT yet run in game)

- Full plan, clip / model survey and change log: `HELI_PLAN.md` (this folder).
- New content addon `tif_air` (Black Hawk + wreck, built by `K:\jimmyproject\tif_air\heli_build.py`).
- New: `tif/air/sh_air.lua` (types), `tif/air/sv_air.lua` (LZ checks, routes, `TIF.API.CallHeli` / `HeliRelease` /
  `CheckLZ` / `Helis`, commands `tif_heli`, `tif_heli_lz`, `tif_heli_release`, `tif_heli_kill`, `tif_heli_clear`),
  `entities/tif_heli.lua` (flight, doors, rotors, wash, crash to wreck). Changed: `autorun/tif_init.lua` (loads air).
- No passengers yet (Stage 2-3). Offline harness 20/20.

### 0.20.2: frozen CQB clips, sped-up sidesteps (2026-11-12, NOT yet run in game)

- User: the wide slice froze and slid; patrol / alert walks sometimes slid or looked sped up.
- CQB queue clips (slice, quick entry, breach go) weren't cleared when their time ran out: the brain walked him on
  with the finished clip held on its last frame. Now cleared at the end (brain tifCQBActName; CQB release too).
- The stuck sidestep (0.19.7) forced 80 u/s: a calm walk (40) played its legs at double speed. Now his own pace
  (min 30). Walk variants checked: speeds within 15% of the base walks, the client scales leg speed to match.

### 0.20.1: MW22 clips from the clean export; grenade hand (2026-11-12, NOT yet run in game)

- User (0.20.0): hiccups in the MW22 calm idles, jumpy grenade dodges. Cause: export 1 (K:\mw22 anims) puts a
  bind-pose key at frame 0 on every bone with the real keys from frame ~3-7: the first frames slid from the bind
  pose and loops didn't close (seams 20-60 units, so every loop wrap popped; scratching loops are 1-2.5 s long).
- User's full dump K:\mw22 anims 2\xanims (50k SEAnims) is clean: loops close (seam 0), normal first frames.
  manifest EXTRA_SOURCES = [export 2, export 1]; export 1 only for names export 2 lacks or has empty (0-byte:
  humming / stretching idles), with its frame-0 key dropped (builder FIX_FIRST_KEY, is_seanim). Export 2 also has
  the kick breach per side: mwq_br_<l|r>_kick_idle / mwq_br_<l|r>_kick_2nd_go replace the single kick clips.
  The raised feet in some activities were the same junk: all activities back in the pool.
- Non-looping "loop" clips (activities) play once before their end clip; one-shot breach waits hold their last
  frame (only used if a clip is built as a one-shot).
- Cover grenades leave from the side of the hand holding them (grenade_left / grenade_right notetrack, GR.Hand).
- Checks: scratchpad mw22_seam.py / mw22_spike.py / mw22_feet.py; all suites pass (civ's flaky one).

### 0.20.0: MW22 (MWII) clips forked into the MW19 set; CQB rework (2026-11-12, NOT yet run in game)

- Source: K:\mw22 anims (6516 SEAnims). 4705 share MW19 names: same body motion (median 0 deg, same frames),
  re-rigged gun bone (j_gun static on the hand, motion in new j_gun_adjust bones) -> MW19 versions kept. 1811 new.
  Triage (scratchpad mw22_triage.py): full-body vs additive / upper-only; per-weapon weapon_offset clips are empty
  in this export; the recovery lying idles have no legs; slope / *_add / "fast" / strafe-lean / custom-pose clips
  are additive or upper-only: none of those built as poses.
- Pipeline: manifest EXTRA_SOURCES (MW19 first, MW22 for names MW19 lacks); builder src_path / fix_first_frame
  (MW22 frame 0 is a junk near-bind pose in 118 of 311 clips: frame 0 takes frame 1). 7 new families (344 roles):
  mw22cover, mw22cqb, mw22react, mw22down (built, unused), mw22buddy, mw22idle, mw22move. gun_holds.py marks every
  MW22-only clip undriven (gun in the hand frame: its gun bone isn't MW19's convention).
- Cover (sv_cover_mw): jog arrivals straight into the lean when the enemy is in sight at a corner (60%, warped onto
  where lean_in ends, straight to aiming); exits out of the lean (MW.Exit from aim); shuffling along the wall to a
  new spot 50-380 along the same wall (MW.PlanShuffle on CB.Seek after leaving a settled spot: in -> n shuffle
  cycles (Act once) -> into the new cover warped onto its node); pain shock on heavy hits (35%); radio calls /
  armour plate swaps among the hiding fidgets (35%).
- CQB rework (user: no crouched stacks, no aiming at the room's middle on the way to corners): standing stacks;
  closed door: the two men at it wait in MW22 breach poses, turned so their clip carries them into the room (side
  picked by the clip's turn); the first opens / kicks it in (door on the clip's door_open moment), the second goes
  in 0.25 s later; open doorway: the point man slices it wide, then quick-enters toward his corner. On the way to
  their points men look past the point into their own corner; at the point, the room. Brain: tifCQBQueue /
  tifCQBActUntil / tifCQBLoop (one-shots hold movement, a waiting loop holds until he leaves his spot or fights).
- Reactions (new tactics/sv_react_mw22.lua, TIF.React22): grenades (landed / slow, not the thrower's): a jump /
  dodge away picked by clip travel, a dive (turned away first) + getting up when very close; pain shock (35% of
  45+ hits in the open); hit while unaware: the assess clip turning toward the attacker; running flinches (jog /
  run / sprint, 70% of hits on the move). Knockdowns dropped: MW22's raginit clips are 7-frame ragdoll hand-offs and
  the get-ups start from ragdoll-blend poses (needs a living-ragdoll system).
- Passive (sv_passive_mw): idle activities hum / radio / distance look / scratch / stretch (grouped; MW22 keeps the
  gun in the right hand: cl_body slings only for smoke / phone / water); MW22 curious / threat reactions as 50%
  variants; "new enemy close" snap (alert soldier, enemy within 600); area checks and threat look-arounds in the
  investigation pool. Walk variants (calm 2-4, alert 2-5) per soldier (sh_anim walkVariants, cl_body).
- Buddy revive (sv_laststand_mw): MW22's paired last-stand revive as a 50% variant (both halves from the wounded's
  origin; ends standing: LS.GetUp skipped). Leader hand signals (SQ.Signal on SetOrder): "on me" toward his men,
  "hold". Prone crawl starts / stops (sv_trans_mw, client prone composition lets mwp_cstart / mwp_cstop through).
  Running drop off ledges 100-210 high (traverse SIZES xl1, probe depth T.MAX_DROP, needs 220 of path ahead).
- Harness: new mw22.lua (29: dodges per direction, dive, breach sides / travel into the room / door moment, slice
  and quick entry, corner look); passive tests updated for the new names; all suites pass (civ's flaky one).

### 0.19.7: unsticking, goal spreading, sprint build-up (2026-11-12, NOT yet run in game)

- User: soldiers caught on each other or the map stood in the calm idle (speed ~0 while trying to move); after
  fights / investigating a sound they all walked to the same coordinate; sprint reached full speed at once.
- Stuck watch (sv_move watch_stuck / unstick): every 0.6 s of steady path following, under 25% of the distance his
  wanted pace should cover = stuck: a 44-unit sidestep (away from a soldier / player / NPC in front, else the side
  the hull traces find open, else back off 30), straight there (loco:Approach, <= 0.9 s), then a fresh path.
  Three in a row: the goal is marked failed and dropped (as the engine's IsStuck already did).
- Goal spreading (M.Spread in SetGoal): a goal within 56 of another soldier's goal or standing spot moves to a
  free, reachable (trace) navmesh spot 64-144 around it, starting on his own side; already within 150 with room:
  he stays. The asked spot (m.want) is remembered so re-issuing the order each think doesn't re-spread. Exempt:
  formation, cqb, board, medic, cover, flee, crawl, post.
- Sprint: builds from his current pace (at least the aimed walk) to full over 1.5 s (smoothstep, M.SPRINT_RAMP).
- Harness: new move.lua (14: spreading, ramp, stuck / sidestep / give up / no false positives); all suites pass.

### 0.19.6: left hand turned onto the handguard, pistol fire (2026-11-12, NOT yet run in game)

- User (0.19.5): foregrips work; calm idles: right hand fine, left hand open below the handguard. Measured
  (scratchpad lhand_rot.py): the left hand's rotation in the gun's frame is steady in aims / CQB (12 deg spread) but
  30-50 deg off in patrol / alert carries and cover looks (the retarget's wrist bend). The left IK now also turns
  the hand to LH (that aim-calibrated rotation; game frames hand = gun * TURN * LH) on the handguard; foregrips keep
  their built hand; the RPG keeps the clip's. Uzi / MP7 hands sit ~7 ahead of the grip: MW19's own tag there.
- Pistols (user: fire faster, panicky, not rhythmic, not a mag dump): W.PISTOL timing of their own: 0.11-0.22 s
  between shots re-rolled every shot, 20% chance of a 0.1-0.3 s hitch, groups 2-5 up close / 2-3 mid / 1-2 long,
  0.3-0.75 s breaks (x1 / 1.4 / 2 by band); single-shot archetypes still fire groups with a pistol.

### 0.19.5: gun turned by j_gun, releases from the raw clips, foregrip hand, Oden / RPG, draws (2026-11-12, NOT yet run in game)

- User (0.19.4 in game): the two-hand tilt fought the calm fidgets and both hands still sat off the gun in calm
  idles (other states fine); foregrips off; Oden and RPG off; rifle / pistol draws threw guns around (video:
  rifle over the head, then floating at head height; the pistol floating beside him).
- Found on the raw MW19 clips (CoD skeleton, scratchpad codspace.py): the right wrist sits at one spot in j_gun's
  frame in every clip set (rifles -12.6/-0.5/-3.6, within ~1) and the left wrist on the handguard: j_gun is the gun.
  Our retarget keeps j_gun's offset from the shoulder, so in the built clips its POSITION is 12+ units off (why
  0.19.0's j_gun * X put the gun behind the body), while its ROTATION is right and the retargeted hand bends at
  the wrist against it (0-24 deg).
- Rule (cl_body gun_pose): rotation = j_gun * KR (KR: the hand frame in j_gun's frame over 125 aim / CQB frames,
  ~diag(1,-1,-1)), blended with the hand frame by how much of the pose is from clips that animate j_gun (st.jrotW;
  MP locomotion doesn't); position = the right wrist. The two-hand swing is gone. Offline (render_jrot.py): left
  wrist 3.4-3.9 from the AKM's grip in patrol / alert / CQB vs 4.6-7.7 for the hand frame.
- Releases (gun_holds.py hold_curves): measured on the raw clips, the wrist off its weapon family's grip spot
  (taken from the family's aims / idles), anchored at the clip's frame closest to it: 274 clips (was 875; half
  the patrol set "let go" because of the wrist bend). Where let go, the gun goes where the raw clip has it:
  zz_jgun `o` (its origin per 3rd frame, clip space; COD_TO_BUILT turns CoD axes onto ours) -> st.jgunO, placed
  with the entity's LocalToWorld. Renders (render_rel2.py): grenade throw slings it at the chest, phone loop at the
  side, RPG reload keeps it on the shoulder while the hands load.
- Draws: sdr_com_exp_(crouch_)ar_to_pistol / pistol_to_ar are undriven (j_gun carries the other gun for part of
  the clip): the gun in hand stays in the hand; the swap and the slung primary do the rest.
- Foregrips (cl_gunhold): a hand built from the gun's axes (ValveBiped L hand: +x wrist->knuckles, index +z, palm
  -y): knuckles forward and round to the right, index on top, palm on the grip's left; wrist 2 behind / 2 left of
  the grip's middle (grip_v + (2, -2.05, -0.8) model space). 0.19.4 turned the clip's hand, but MW19's handguard
  hand isn't palm-up: it ended above the grip, fingers down.
- Oden: has its foregrip built in (INTEGRATED_VERTGRIP): vertgrip finger pose, the foregrip hand. RPG: no IK tags;
  hold.gripL = (7.0, 7.7, 0.3) model space, where the raw RPG aim puts the left wrist (GRIP_L_FALLBACK).
- Harness: gunhold 19 (two-hand tests dropped), all suites pass (civ's known flaky one).

### 0.19.4: two-hand gun hold, foregrips, prone deaths, audit fixes (2026-11-12, NOT yet run in game)

- User (0.19.3 in game): guns-up poses good; calm idles often off (gun vertical, left hand open beside it),
  foregrips not gripped. Cause: the gun bone's angle in the right hand differs per MW19 clip set (aim/CQB 0,
  reload 14, alert/patrol 24.5 deg) because MW19 IKs both hands onto the gun at runtime: the hand frame is right
  only in aims. (0.19.2's "correct in every clip" render check was wrong for patrol: stock over the shoulder.)
- Two-hand hold (cl_body two_hand): the gun swings about the right wrist so TWO_Q, the left wrist in the right
  hand's frame on aim / CQB clips (11.65, -5.86, -1.81; 169 frames within 2 deg), points at the clip's own left
  wrist (st.lwRaw, recorded in the IK callback before any IK). Corrections: aim/CQB ~2 deg, alert ~8, patrol ~23,
  fidgets up to ~60 (gun across the chest). Off when the wrists aren't 13.2 +-3..6 apart, past 70-90 deg, when it
  would point the gun back (hand at the stock), or when the notetracks take the left hand off (reloads:
  st.twoNote, cl_gunhold Prepare). Overrides the gun-bone follow while on. Pistols / RPG: hand frame.
  Scratchpad renders: render_two.py, two_cal.py (Q), two_stats.py.
- Foregrips: the wrist goes to grip_l (MW19's tag_ik_loc_le, ~1.5 above where the wrist sits on a vertical grip)
  + 1.5 down, palm turned to face across the grip, index on top (0.19.3 aimed at the grip's middle with the palm
  facing back: a fist over the rail). IK fade widened 6-14 -> 8-16. gun_holds.py: MW19 finger pose names
  `_l_grip`, `_l_gripvert`, `_l_gripang` (the M4 borrowed the AK's) and the POSES glob took only `*_l` files.
  gun_compile.py: grip_v only with a foregrip fitted (tag_folding_grip is the rail mount: the M680 had one; not
  recompiled, the Lua ignores it without a grip finger pose).
- Prone deaths (user: sudden ragdoll with no anim; the death jumped forward): the client's prone composition
  outranks actions, so the death clip never showed; and MW19's prone deaths / pains lie 26.6 units further forward
  of their origin than its prone idle (pelvis y -25.7 vs +0.9). H.Death (prone): clears prone, steps the soldier
  back 26.6 (EF_NOINTERP, hull trace stops at walls), and plays to 75% before the ragdoll (the builder's mid-fall
  handoff was 15-18%). Prone pains are skipped (never shown, same offset).
- Audit: W.Init aliases every GTA gun to its MW one (API / overrides / debug kept GTA guns); captives, surrendered
  and downed soldiers no longer show the primary slung (M.Post wanted only "not the primary", "" included); medics
  use the fight gaits (sprint / aimed walk) instead of the jog. No calls to missing functions across TIF, DTW,
  GOPS, SWAT, the faction pack and tif_guns. Harness: gunhold 22, hits 83 (new prone / two-hand tests), all
  suites pass (civ's known flaky one).

### 0.19.3: studiomdl's compile turn, crouched-pistol error, CQB idle legs (2026-11-12, NOT yet run in game)

- User: every gun yawed 90 deg to the right. Cause: studiomdl turns every model +90 deg about Z (SMD -Y forward ->
  model +X); the bodies' bone frames and our gun mesh both got it, so placing the gun on a bone frame applied it
  twice. cl_body gun_pose now ends with UNTURN = Rz(-90) (hand hold and gun-bone follow); the foregrip code uses
  model-space axes (barrel +y, top -z: rear = entity Right); the server's dropped gun gets the same correction.
  (Lesson: offline checks in raw SMD space don't show this; renders need the compile turn on the gun.)
- Error `cl_body.lua:310 walkSpeed nil`: sh_anim built the pistol's crouch set before L.crouch.walkSpeed existed
  (crouched pistol soldiers); now reads the clip speeds.
- User: CQB moveset legs A-pose. sdr_cqb_exp_interior_ready (cqb_idle) has no leg tracks (upper body only); audit
  of every role: the only full-body clip without legs. L.cqb.idle = the aimed stand (could return as an overlay).

### 0.19.2: gun in the right hand's frame everywhere; gun-bone motion only where the clip moves it (2026-11-12)

- User: every anim had the gun tilted ~90 deg; calm idles had the gun floating at the chest, right hand at the hip.
- Offline renders (scratchpad render_hold.py / render_rel.py) of clip frames with the AKM: the gun in the right
  hand's frame (the MW world model's export frame) is correct in every clip tried (alert, patrol carry, MP aim,
  cover; both hands land on the gun). j_gun * calibrated X was only right in cover: its convention varies.
- Rule now: gun = right hand's frame; where a clip moves the gun relative to the hand (fidgets, grenade throws,
  charging handle, putting it away), gun = j_gun * A, A = the hand in j_gun's frame at the clip's own grip frame
  (first frame; last for _end / exit / _out / _to_; the _start clip's for the phone / smoking / water loops).
  gun_holds.py writes TIFG_JGUN_HOLD[clip] = { a, r } (r 0..1 every 3rd frame); cl_body blends r over the layers
  (st.jgunW) and takes A from the dominant clip (st.jgunA). No per-gun calibration involved.
- Right-hand IK off (st.rikW = 0: the hand holds the gun by construction); left-hand IK / foregrip / fingers kept.
- Renders of grenade mid-throw (gun hangs at the hip), reload (across the chest, left hand), phone loop (slung at
  the side), patrol fidget (both hands on it) all look right offline. NOT yet run in game.

### 0.19.1: guns ride in the right hand, both hands IK'd like MW19, foregrips (2026-11-12, superseded by 0.19.2)

- User: better in fights, but idles odd, foregrips unused, Oden (ASh-12) and RPG held wrong (hands swapped look).
- Found: MW19 clips' hands are only approximate to the gun bone (MW19 IKs both hands onto the gun at runtime;
  the right-hand ik_out / ik_in notetracks exist); j_gun's in-hand offset varies 60-95 deg / up to 10 u between
  clip sets, and MW19's patrol carry sits a rigid 13 u off.
- Gun: baked guns sit exactly in the right hand's frame (they were exported in the MW world model's right-hand
  frame; true for every gun, Oden / RPG / pistols included), blended toward the gun bone (j_gun * X) by st.jgunW.
- gun_holds.py now writes TIFG_JGUN_HOLD (zz_jgun.lua): per clip every 3rd frame, j (gun on the bone vs in the
  hand: 0 for rigid carries like patrol) and rik (right hand on the grip: 0 where it lets go - grenade throws,
  charging handle, lean idles, activities), from the clip hand's distance to the gun's grip (AKM reference).
  cl_body blends them over the layers into st.jgunW / st.rikW (MP locomotion: in the hand).
- cl_gunhold: right-hand IK onto the grip (position + the gun's rotation), weighted by rikW and right-hand
  notetracks, fading 12-20 u; left-hand IK onto grip_l or the foregrip's grip_v (new attachment: middle of the
  grip below tag_folding_grip), hand turned 90 deg to wrap a vertical grip, then the gun's finger pose.
- Rebuilt m4_sof_b, ak_warsaw_grip, mp7_sof (grip_v). Harness suites pass.

### 0.19.0: guns on the clips' own gun bone, MW19 finger poses, one dropped gun (2026-11-12, NOT yet run in game)

- User (in game): left hand rarely lines up, fingers never change, slings snap and don't follow the body
  putting the gun away, sometimes two guns drop.
- Found: in MW19 the gun is its own animated bone (j_gun / tag_weapon_right, under the right shoulder); campaign
  clips key it every frame (gun pose in the hand, put away for grenades / phone / water, re-gripped), and the
  builder already compiles it into mw_male (j_gun under R_Hand). MP locomotion (sdr_mp_*) keys only a fixed
  rotation + drifting position: unusable there.
- `K:\jimmyproject\tif_guns\gun_holds.py`: (1) tif_mw_anims/.../clips/zz_jgun.lua: TIFG_JGUN_UNDRIVEN (113 of
  1098 source clips, from their seanim j_gun keys); (2) per gun, its place on j_gun: origin = j_gun * [diag(1,-1,-1)
  | t], t least-squares so the gun's tag_ik_loc_ri / _le meet the clip hands (2-3.7 u residual; Oden / RPG use the
  long-gun mean; pistols keep the hand hold); (3) per gun, MW19's left finger pose (mp_fingers_<gun>[_vertgrip /
  gripvert / angledgrip]_l, AK's grip pose as fallback) retargeted to ValveBiped L finger local rotations.
  Written into the weapon defs as SWEP.TIFBaked.hold by `batch.py --lua`.
- cl_body: st.jgunW = share of the pose from clips that drive j_gun (upper-body overlay owns it while on);
  gun_pose blends the hand hold with j_gun * X. Fallback sling only when the clip doesn't carry the gun.
  Dying: no client drop (the server's TIFDropWeapon is the one gun).
- cl_gunhold: after the arm IK, the gun's finger pose (parents first, lengths kept) while the hand is on.
- Not done: no pump motion on shotgun fire (MW19 fire gestures were additive / broken; the baked 680 has no pump
  bone), no shell in hand (user: not needed).
- Harness gunhold.lua 18/18 (IK, notetracks, finger pose); suites pass.

### 0.18.1: every faction on the MW guns; DPR Militia = Russian SOF (2026-11-12, NOT yet run in game)

- Sounds wired: tif_gunbake_sounds run by the user (44 guns), `batch.py --lua` wrote SWEP.GTG.mw into every gun.
- Loadouts rewritten to baked MW guns: militia "DPR Militia" = Russian SOF table (War Saw AKs, AN-94, AS VAL /
  Bizon, PKM SOF, Plague Sore SVD, RPG-7, Sykov); pmc and usmc_bf3 = US infantry (M4s, SCAR, M91 / Bruen, EBR,
  X16 / M19, MP5, 680 shorty); operators = SOF (M13, Kilo, MP7, Bruen SOF / FiNN, M13 DMR / EBR sup / Rytec,
  X16 SOF / Javelina); contractors = in between; insurgents / arab_militia = rebel (AKs, FAL, Uzi, PKM / MG34,
  SVD / SKS, wood 680 / 725, 1911 / Sykov); chechen / rus_rebels = Soviet-only rebel table. Oden unused (no
  Russian infantry faction yet).
- Safety net: tif_guns/lua/autorun/tif_guns_alias.lua maps every GTA gun to its MW counterpart (TIF_WEAPON_ALIAS);
  TIF.Loadout and the weapon fallback apply it when the MW gun is installed.
- GTA body (vehicles, GTA-only actions) with a baked gun: never bone-merged (no GTA hand bone); placed each frame
  from the faction model's ValveBiped right hand with the same grip math (gun.tifFree).

### 0.18.0: left-hand IK, sling, slung primary, dropped guns, MW sounds (2026-11-11, NOT yet run in game)

- `npc/cl_gunhold.lua` (TIF.GunHold), MW19 body only:
  - Left-hand IK: inside the host's bone build, the left hand goes to the gun's `grip_l` (baked guns' handguard /
    foregrip, from tag_ik_loc_le) with a two-bone arm solve keeping the clip's hand rotation and elbow side;
    helper / finger bones follow. Weight from the playing clips' ik_out / ik_in notetracks (reload, draw, actions)
    and faded out when the clip's hand is > 6-14 u from the grip. Not on pistols (no grip_l). `tif_hand_ik 0`
    turns it off; only within 1600 u.
  - Sling: what used to hide the gun (mwx_ activities, grenades, mwg_, seated non-gun poses) and now medic revives
    (mwls_help_*) blend the gun (~0.3 s) onto a chest sling (long guns), across the back (RPG) or a right-thigh
    holster (pistols), placed from the torso bones. Poses are first guesses (SlingPose), to tune in game.
  - Slung primary: while the sidearm is out the primary hangs on the sling (server sends `tif_primary`).
  - Dying: the gun drops as a client physics prop (max 16, 30 s); GTA guns without a hull just hide.
- cl_body: `gun_pose` split out of place_gun_vb (Bd.GunPose / GunInfo / MakeGun / State for cl_gunhold);
  gun_info keeps grip_l, barrel / up, length.
- Sounds: sv_weapon plays `def.mw` (baked guns): MW fire sound + outdoor / indoor atmosphere tail once per burst
  (sky trace cached 3 s), and the gun's MW reload foley stretched over the NPC reload (empty variant when dry).
  `tif_gunbake_sounds` (tif_gunbake) records each built gun's fire / tails / reload events into
  data/tif_gunbake/<id>_sounds.json; `batch.py --lua` rewrites the weapon files with them.
- Rytec AMR added to the roster and built (weapon_tifmw_rytec); its mag didn't split (bone name unknown).
- Harness: gunhold.lua (IK solve, notetrack weights) 15/15; all suites pass.

### Baked MW guns: all 43 built (2026-11-11, AKM seen in game, rest NOT yet)

- From the user's first in-game look at the AKM: fixed reversed winding (GetModelMeshes order is the reverse of
  SMD's: the gun looked inside out), gentler LODs (lod0 err 0.015 / lod1 0.05 / lod2 0.11), coloured specks on metal
  (Pillow's premultiplied RGBA resize; metal also greyed), grip too far forward and canted (baked guns now carry
  `grip_r` = palm point and `tif_axis_b` / `tif_axis_u` from the muzzle tag; cl_body gun_info uses them).
- `K:\jimmyproject\tif_guns\batch.py [ids]` builds everything (about 10 s a gun); log in build/batch.log.
  Muzzle tag falls back to tag_flash_attachment / tag_silencer (pistols, M91, MG34, SVDs). stencil_outline and
  ___error materials dropped.
- Typical LOD0: pistols 2.5-4k, rifles 3.5-10k, LMGs 8-15k (Bruen SOF heaviest); LOD2 0.5-2k.
- Weapon classes: weapon_tifmw_<roster id> (stats/sounds still GTA placeholders; factions not switched yet).

### Baked MW guns: first one (AKM) built (2026-11-11)

- Pipeline (K:\jimmyproject\tif_guns): gun_decimate.py (3 LODs), gun_textures.py (one atlas / material per gun),
  gun_compile.py (vtex + studiomdl into addons/tif_guns, plus lua/tif/gta/weapons/weapon_tifmw_<id>.lua: a copy of
  a GTA weapon's data with our model, MWA_Suppressed and tiers from the roster).
- AKM: 2533 / 1378 / 477 tris, 1024 atlas, mag on tif_mag, muzzle + grip_l attachments, single-hull collision.
- `tif_give <class> [all]` (dev): the soldier under the crosshair (or all) takes that primary. Try
  `tif_give weapon_tifmw_akm all`.
- To check in game: grip position (the model's origin is the MW world model's right-hand bone; place_gun_vb adds
  GRIP_IN 3.2 for GTA guns), LOD switch points ($lod 6 / 18), mag motion on reload. Stats / sounds are the GTA
  assault rifle's for now.

### 0.17.0: combat gaits, aimed walk or sprint (2026-11-11, NOT yet run in game)

- User: soldiers covered ground fast while aiming (MW19's aimed strafe jog, ~199 u/s). In a fight there are now two
  gaits: the aimed walk (`tactical`, MW19 strafe walk ~103 u/s, can shoot) for moves up to `TIF.Move.SPRINT_DIST`
  (300 u), and a sprint (~247 u/s, gun down, never shoots) for anything longer. `TIF.Move.CombatGait(npc, goal)`
  picks it and keeps it for the whole move (same goal).
- Changed: brain gait picker (advance = stretch down to 85% of preferred range; maneuvers by goal distance;
  everything else aimed walk), maneuvers (shoot only on the aimed-walk stretch), moves to cover (sv_cover_mw and
  sv_cover_behave), CQB stack (sprint far / aimed walk near) and entry (aimed walk), covering burst (aimed walk for
  its rounds, then the sprint). A sprinting soldier's fire request is dropped (sv_brain, before the relaxed-carry rule).
- Out of contact unchanged: squad travel still jogs / sprints (SQ.AdvancePace, formation catch-up).
- Harness: gait.lua (new) passes; all other suites unchanged.

### 0.16.5: MW gun bake exporter + reload mag motion (2026-11-11, NOT yet run in game)

- New addon `tif_gunbake` (tool, not shipped with TIF): roster of 43 MW base presets
  (`lua/tif_gunbake/sh_roster.lua`: rebel / infantry / sof / ru_infantry / ru_sof tiers, kind, suppressed, tint).
  `tif_gunbake [id ...]` in single player gives each gun, applies the preset through the MW base
  (`mw_utils.LoadPreset`, so its rails / mounts / sight folding rules apply), then the client dumps the world model
  and every attachment's third-person model (coarsest LOD above a floor) in the frame of the world model's
  `ValveBiped.Bip01_R_Hand` (sling offset applied), so the baked gun's origin is the grip.
  Output `data/tif_gunbake/<id>_smd.txt` + `<id>.json` (parts, LOD, materials / submaterials, skins, tag bones,
  attachments that didn't apply). Keys checked offline against the packs: 0 bad. Plague Sore: its receiver swaps
  the Dragunov scope for its own (roster `swaps`). Javelina = 1911 receiver/slide/mag `_v5` (blueprint pack
  placeholder_2945973521).
- Mags: magazine attachments (based on `att_magazine`) and gun geometry on mag bones (`j_mag*`, `tag_clip`,
  `j_rocket`, belt / box) go on a second bone `tif_mag`.
- `npc/cl_gunmag.lua`: on guns with a `tif_mag` bone, reloads follow the MW19 notetracks the clips already carry:
  hidden after `drop_clip`, in the left palm from `attach_clip_left`, seated at `detach_clip_left`; LMG box swap on
  `ps_wfoly_lm_reload_npc_out/_in`; RPG warhead hidden until attach. One falling mag copy per reload
  (`tif_mag_drop`, max 8, 10 s, within 1500 u; a trace a frame while falling). GTA guns untouched. cl_body records
  the playing reload clip / cycle (layered, prone, cover / action reloads). Palm offset `TIF.GunMag.PALM`.
- Offline: gunmag_test.py 9/9 on the real clip tags; harness suites unchanged (civ.lua's "scattered civilian
  removed" check is flaky, random leave share; not from this change).
- Next: user runs `tif_gunbake`, then the offline pass (decimate to ~1-1.5k tris, mag bone at the mag centre,
  textures 512/1024, drop lens/reticle materials, black mag tint, muzzle + grip attachments, compile, TIF weapon defs).

### 0.16.4: the real prone bug (2026-11-11, NOT yet run in game)

- User's console: `cl_body.lua:571: attempt to index local 'PR' (a boolean value)`, every frame for prone
  soldiers. 0.15.0's prone-throw / prone-flash exception was written `st.vbProne and legs.prone and not (...)`,
  which is the boolean `true` when no such action plays: every MW19 prone soldier's composition errored (no
  get-down / get-up, the gun left floating where it was). Fixed (PR is the clip table or nil). 0.16.2's
  no-swap-while-prone guard stays.
- Banned by default (user): sdr_com_exp_stand_death02_gut_lg_2 (mwd_stand_torso_8: knees, clutching the gut,
  falls back), `H.DEFAULT_BANS`.
- Proposed rework, later (user): soldiers covering ground quickly at walking pace looks gamey.

### 0.16.3: animation fixes from the user's clips (2026-11-11, NOT yet run in game)

- Clips 1 / 4 (stiff A-pose legs, LMG soldiers) and 3 / 5 / 6 (arms thrown straight up: shotgun pump, the
  "overhead blindfire" standing and after mantling): two 0.13 clip choices were wrong. MW19's shotgun / RPG fire
  clips are additive recoil layers (read as poses: pelvis 34 back, feet in the air), so the per-shot gestures
  threw the arms up; the LMG "gun down" idle stands feet together with straight legs. Both no longer built
  (clips 5 / 6 assumed to be the same gesture: check).
- Gun held from the right hand only (user): barrel and the gun's up fixed in the hand's frame (measured: up ~
  the hand's down, -0.99, in every rifle / LMG / RPG / walk aim); no more pointing the barrel at the left hand
  or keeping it world-upright, so clips that take a hand off the gun don't twist it.
- Explosion deaths only for real blasts (blast damage that isn't bullet damage, 30+): some weapons flag rounds
  as both. `tif_blast_scale` (1.6): soldiers take more from explosions (user: too strong against them).
- Clip 2's death (drops to the knees, falls back) couldn't be told apart from video: `tif_deaths_recent` lists
  the last 10 MW19 deaths, `tif_death_ban <n | name>` takes one out (data/tif/death_bans.txt),
  `tif_death_unban`.
- Not done: the rare opposite-side cover pose (no repro yet).

### 0.16.2: prone with no get-down / get-up and a floating gun (2026-11-11, NOT yet run in game)

User screenshot: a prone MG gunner in the Prone Mod's pose (empty hands), the gun floating above him, no MW19
get-down / get-up. That's the GTA-body prone path: the soldier's body had been swapped to the GTA ped
(Act.Play falls back to the GTA body for clips the MW19 body lacks), so the client used the Prone Mod on the
faction model, unparented the gun and, with no measured grip for that gun, never moved it again.
- `Act.Play`: no body swap while prone (the clip just doesn't play).
- cl_body prone (Prone Mod path): a gun without a measured grip is placed from the faction model's hands
  (place_gun_vb) instead of left where it was.
- Still swapping MW19 soldiers to the GTA body outside vehicles (to replace before GTA anims are phased out,
  user's plan): surrender kneel (sv_morale KNEEL), API hostage kneel (sv_api KNEEL), the GTA cover set when the
  MW19 cover set doesn't apply, the GTA casualty clips if a soldier goes down while on the GTA body.

### 0.16.1: civilians scatter harder, one hit, own looks (2026-11-11, NOT yet run in game)

From the user's test (civilians stayed in firefights, wounded state unwanted):
- Scatter share 0.6 -> 0.8; decides at fear 0.2 (was 0.3); gunfire scares within 2400 of the shooter (was
  1600) and 1000 of where it lands (was 700); scattering civilians run 3200 off and go once out of view and
  1100 from everyone, or 3500+ from everyone even if seen. Hide spots 500-1200 away (was 250-700).
- Shooting within `TIF.Civ.TOO_CLOSE` (700) of a hidden civilian moves it on (every 8 s at most), each time more
  likely out of the area (50%, 100%...). Sheltering ones stay put.
- One hit kills (1 health); no wounded state. The kneeling hostage clips with hands in front / on the ground
  (civ_kneel_2 / 4 / 5) are now scared poses alongside the three cowers; the hands-behind-the-back ones
  (civ_kneel_1 / 3, measured) stay for hostages.
- Pointing: right when a player or soldier walks up (within 300, once per person, shooting heard in the last
  minute), not on a timer.
- Random skin and every bodygroup from one seed (NW2 `tif_civ_seed`): client model, fallback body, ragdoll.
- Spawn menu, NPCs tab, "TIF - Civilians": Civilian, Civilian (stays, hides) (`tif_civ_noleave`), Crowd (8)
  (`tif_civ_crowd`: 7 more within 350).
- Prone get-down / get-up not showing (user): clips and timing checked (2.9 / 2.3 s, server phases fine, client
  picks them by NW phase); cause not found from code, waiting on the user's screenshots.

### 0.16.0: shared civilians (2026-11-11, NOT yet run in game)

User's vision: an urban op opens with shots cracking past the team, civilians scattering; most run off (removed
for performance), some stay and remain a factor for the rest of the op.
- `entities/tif_civilian.lua` (NextBot, spawnable under Tactical Infantry): the MW19 host playing MW19's civilian
  clips (71 roles, manifest `civ_family`), a Czech civilian model (9 male, 6 female playermodels) bone-merged on
  clients; falls back to the model's own HL2 activities without the MW19 host.
  - Calm: each keeps one of 6 long MW19 idles; wanders near home, talks in pairs (GOPS pairs them).
  - Panic: each keeps one of ~24 panic walk / jog / run variants (no crowd in step); wounded run; ragdoll in
    its own model posed from the host.
  - First scare decides once: scatter (`TIF.Civ.LEAVE_SHARE` 0.6: run 2600 away from the danger, removed once
    1400+ from every player and out of view; "TIF_CivilianLeft") or stay: flee 250-700 to a hide spot (out of
    the danger's line of sight, indoors, beside a wall) and cower or press against the wall (side it's on),
    pointing toward the shooting for a soldier / player close by; calms down after 40 s quiet. Sheltering /
    noLeave civilians never scatter.
  - Hooks: TIF_CivilianUse / Hurt / Injured / Killed / Left. GOPS-compatible fields and states.
- `tactics/sv_civilian.lua` (TIF.Civ): models, spawn, fear (any gunfire: the shooter within 1600 and where the
  rounds land within 700; blasts within 2200; scaled by distance), hide / leave points, removal tick.
- API: `SpawnCivilian(pos, opts)`, `ScareCivilians(pos, radius, amount)`, `Civilians()`,
  `SetCivilianLeaveShare(k)`.
- GOPS (`sv_civilians.lua`): spawns `tif_civilian` when TIF has it (else `gops_civilian`); use / injured /
  killed through the hooks (same ROE stats, informants, treating the wounded); civilians who scattered count off
  the district so they aren't respawned.
- Harness: civ 10 (models, scatter / stay decision once, shelter, hide spot behind a wall, leave point, removal
  only out of view).
- Not yet: female body proportions (on the male MW19 skeleton), starts / stops / turns for civilians, hostages /
  hands-up (clips exist: civ_kneel_*), DTW / SWAT spawning them, civilians opening doors.

### 0.15.1: flashbangs from other addons, squads that push (2026-11-11, NOT yet run in game)

From the user's test (SandSWEP flashbangs did nothing; GOPS attackers didn't hurry, friendlies didn't push):
- **Flashbangs** (`compat/sv_flashbangs.lua`): SandSWEP's M84 only stunned `IsNPC()` entities; TIF soldiers are
  NextBots, so they never noticed. `TIF.FlashAt(pos, radius, inflictor)` stuns every TIF soldier in range with
  line of sight (2-7 s by distance and facing; 80% of max right next to it); SandSWEP's flashbang Detonate is
  wrapped at load (SandSWEP not edited). Other flashbang addons can call `TIF.FlashAt`.
  - The MW19 open-ground reaction no longer refuses while a low-priority clip plays (turn / start / stop, search
    look, smoke / phone / seat, alert reactions): those are dropped for it. Prone soldiers react too (`mwp_flash`,
    client plays it over the prone set).
- **Pushing** (TIF squad layer, so GOPS and DTW both get it):
  - Advance pace (`SQ.SetOrder(..., opts.pace)`, `API.SquadAdvance(sq, pos, opts)`): "rush" jogs until 700 from
    the objective, "move" (default) until 1600, "careful" walks; any contact in the last 25 s = tactical walk;
    once slowed it stays slowed for that order. Followers jog when the leader jogs.
  - In contact with an advance order, bounds aim at the objective unless the enemy is roughly on the way
    (then at him, as before); a close fight is only sat out while the enemy is actually seen (5 s quiet: the push
    resumes past him); pairs bound too; the objective reached = fight there.
  - Contact lost mid-advance: an 8 s look, not the 40 s search, then the push carries on.
- **GOPS** (`sv_orders.lua` `O.Pace`): enemy assaults / reinforcements / counterattacks rush, friendlies and
  support move. `AI.Advance(sq, pos, opts)`.
- Harness: push 11 (flash LoS / distance / facing, pace rules).

### 0.15.0: Stage 7 + 8: cover pains, last stand, traversal, flashlights, open grenades (2026-11-11, NOT yet run in game)

MW body unless noted. 205 new roles (`stage78` family). Riot shields held off (user).
- **Cover pains** (`CoverBehave.MW.Pain`, from `HitsMW.Pain`): hit while hidden = a flinch in place
  (`mwc_<t>_pain_<region>_<md|lg>_<dir>`); hit while leaning out / aiming = knocked back into hiding (`*_hide`
  clips, eased back onto the hide spot, no fire). Chance by damage (40-90%), heavy = 35+ damage, side the hit
  comes from. Not during reloads, throws, moves.
- **Last stand** (both bodies' rules, sv_casualty): `tif_downed_chance` default 0.35 -> 0.2 (existing saved
  values stay; set it in console). Never one of the last men standing (2+ able friendlies within 1500), one
  casualty per squad at a time, 40 s squad cooldown.
  - MW body (`tactics/sv_laststand_mw.lua`): crumples (first half of an MW19 death clip), lies wounded, one short
    crawl (220, 8-way crawl clips, dragging himself away still facing the enemy, toward friends). Revive: the
    medic kneels on the near side and runs MW19's paired revive (helper in / loop 3.5 s / out, the casualty's
    matching clips by side), then the casualty's get-up. Medic pulled into a fight: the casualty goes back to
    lying. Bleeding out: the pass-out clip, then dead (no death clip, straight to the ragdoll). Killed while
    down: straight to the ragdoll.
- **Traversal** (`tactics/sv_traverse_mw.lua`): checked ahead along the path while moving: mantle up a ledge
  (24-100), vault over an obstacle that the path goes past (sandbags, low walls, fences; step <= 22), drop
  down an edge (24-100). Clip warped (root + height, through the obstacle) so its contact notetrack lands on
  the edge and it ends on the landing at its code_move / finish notetrack, where locomotion takes over. Paths
  may now climb up to 100 for MW soldiers (cost +150 + 2/unit); before, climbs were refused outright.
  `Act.Play` gained `rootz` (follow zcurve) and `warpU` (warp lands at a point of the clip).
- **Flashlights** (`tactics/sv_flashlight.lua`, `npc/cl_flashlight.lua`; any body): `tif_flashlights` 0 off /
  1 always / 2 dark maps (map or sky name; `API.SetFlashlights(true/false/nil)` for modes). Squad leader +
  ~60% of the others; on while patrolling, searching and fighting. Client: real lights (no shadows) for the
  nearest `tif_flashlight_max` (4) within `tif_flashlight_dist` (3000), a lens glow for the rest; the beam
  follows facing, aim yaw / pitch, lowered with the weapon down. Weapon light, not MW19's handheld-torch clips
  (those need a torch model).
- **Open-ground grenades** (`GrenadeMW.OpenThrow` / `OpenThink`): out of cover, enemy known but hidden: the
  same decision as cover throws (cooldowns, one frag each), MW19's standing / crouched / prone throw, released
  on the clip's grenade_throw frame. Gun hidden during it.
- Harness: stage78 36 (rarity, last stand flow, revive, abort, bleed out, traversal probes / check), cover 45
  (+4 cover pains); the rest unchanged.
- To watch: revive pair placement is estimated (the clips are each in their own space: helper kneels 30 from
  the casualty's chest); pain directions assume MW19 names the side the hit comes from; traversal only where
  the path goes over / up / down, so obstacles the navmesh routes around are still walked around.

### 0.14.0: fire discipline, covering bursts, movement commitment, LMG bipods, prone reloads, SMG sprint (2026-11-11, NOT yet run in game)

User: not a fan of soldiers jogging while firing full auto, or quick movement changes; wants sporadic bursts,
with CoD-style covering rounds on a dash.
- **Fire discipline** (sv_weapon `W.PROFILES`): rounds per burst by range band (close < 400, mid < 1500,
  long) and weapon kind; scaled by the archetype's burst (rifleman = x1, capped x1.6; LMGs unscaled unless
  braced). Rifle: close 3-5, mid 2-3, long 1-2. SMG 4-6 / 2-4 / 1-2. LMG 4-7 / 3-5 / 2-4, braced: the
  archetype's 8-16. Shotgun one per pull, pistol 1-3 / 1-2 / 1, marksman / AT singles, semi-auto rifles a
  pair up close else singles.
  - Shots inside a burst at 1.15-1.45x the gun's interval (full rate only up close); pauses x1 / 1.25 / 1.8
    by band.
  - Drift: each round of a burst spreads 14% more (5% braced), capped x2.
  - Moving: walking (20-110 u/s) only short bursts (max 3 close, 2 mid), never long range, slower cadence and
    longer pauses; faster than 110: no fire.
- **Covering burst** (`W.CoveringBurst`): a new run / sprint / aimrun goal in a fight (contact seen in the
  last 2.5 s) may start 3-5 loose rounds (x2.2 spread) over 0.55-0.9 s: the body swings to the enemy, sprint
  drops to the aimed jog, mode stays aimed; then the gun goes down. Chance per archetype `coverFire`: rifleman
  0.35, assault 0.6, breacher 0.5, leader 0.45, support 0.3, guard 0.2, marksman / AT 0. Every 3 s at most.
- **Movement commitment** (sv_brain): a move keeps its gait to the end (no jog / walk re-rolls mid-move);
  range keeping has hysteresis (advance until 85% of prefRange max, back off until 120% of min) and a 2 s
  minimum.
- **LMG bipods** (`tactics/sv_bipod_mw.lua`, TIF.BipodMW): an LMG gunner holding still in a fight with a rest
  toward the target 12-40 ahead: low wall 28-40 (crouch set), wall top 40-50 (stand), window / high ledge
  50-60 (high), open beyond it. Set-up clip, 3x3 aim blend (+-77-88 degrees measured), pack-up before moving
  (Move.Step waits), when the target leaves +-70, after 5 s without contact, 30 s, out of the fight or
  heavily suppressed. Prone: on the client (an LMG lying still sets up, packs up x1.8 before crawling); the
  server counts it braced after 2.9 s.
- **Prone reloads** (rifle, pistol) on the client's prone branch. **SMG sprint**: new kind `smg` (micro SMG,
  SMG, assault SMG) with MW19's SMG sprint; otherwise the rifle sets.
- Harness: fire 17, bipod 6, wclass 39; the rest unchanged (cover 41, trans 37, passive 28, hits 74, smart 32,
  warp 4).
- To watch: rest heights for the bipod sets are from hand heights, not verified on real geometry; the
  maneuver's aimrun no longer fires except covering bursts (bounds feel more like dashes); walking fire is
  much rarer.
- Later (user): AT4-style disposable launchers (fire, drop, draw the sidearm; `rpg_drop_to_exp_stand_pstl`).

### 0.13.0: MW19 weapon classes: shotgun, RPG, LMG (2026-11-11, NOT yet run in game)

MW body only. 33 new clips (`wclass` family). Before this every gun but pistols used the rifle set.
- `TIF.GTG.WeaponKind(class)` (sh_gtg): GTG hold -> pistol | shotgun | rpg | lmg | rifle. Current pool:
  assault / compact / marksman / carbine / special carbine / micro SMG -> rifle; pump / combat shotgun ->
  shotgun; MG / combat MG -> lmg; RPG -> rpg; pistol / combat pistol -> pistol.
- Reloads (upper body, stretched to the server's reload time), standing and now crouched for every kind
  (rifle included): `mw_reload[_<kind>][_cr]`.
- Per-shot gestures on the upper body: shotgun pump (3 variants, standing / crouched), RPG kick.
- Idles: LMG aimed idle (MW19 `exposed_lmg_aim_5`) and lowered alert idle; RPG on the shoulder standing and
  crouched. Moving still uses the rifle strafes (MW19 has no LMG / RPG strafes).
- Cover reloads per kind (pistol, shotgun, LMG, RPG at ls / rs / cr): `mwc_<t>_reload_<kind>`, else the
  rifle's.
- Harness: wclass 36 (kinds, clips present, leg sets); cover 41 (+ shotgun cover reload).
- Not done: RPG drop-and-draw-pistol after firing (`rpg_drop_to_exp_stand_pstl` exists), LMG bipod setups,
  prone reloads, the micro SMG's SMG sprint.

### 0.12.0: turns, starts, stops, search looks, Stage 6 (2026-11-11, NOT yet run in game)

MW body only. 148 new clips (`trans` family: `mwt_*`, `mwl_*`). Two new modules.
- `tactics/sv_trans_mw.lua` (TIF.TransMW), called from TIF.Move:
  - Turn in place: standing still and 60+ degrees off -> a turn clip picked by its measured yaw (45 / 90 /
    135 / 180; calm, alert, stand, pistol, crouch sets), blended to end exactly on the wanted facing. x1.5
    while engaged. Dropped when a new move starts (calm turns take ~3 s).
  - Starts: a fresh path from a standstill -> the start clip toward the first leg (calm / alert turn into the
    path; weapon-up walk / jog strafe starts keep the facing). Skipped if a corner comes before the clip's own
    travel (strafe starts cover 115-235 units). Not for fleeing, boarding or cover moves.
  - Stops: on the last leg within 45 of the goal -> the stop clip warped onto the goal. Calm / alert stops
    turn to the post's facing (`Move.SetGoal(..., faceYaw)`, passed for posts).
  - Halting short: posts, holds and patrol points count as reached 80-90 out, so `Move.Stop` mid-walk plays
    the stop clip from where he is (eased to the post facing) instead of freezing.
  - While one plays the action is marked `trans`: path following waits, facing code leaves the body alone.
- `tactics/sv_search_mw.lua` (TIF.SearchMW): looks picked from the geometry around the soldier: under a
  table, under a car, over a low wall, down a drop, up at a tall building under open sky, else look around.
  Enter / loop 2.5-4.5 s / exit. Used at each search point, and (60%) once per noise when investigating.
  Runs from the brain's busy check; a fight drops it at once.
- Harness: trans 37 (real clip data, mock path, box world). The others unchanged.
- To watch: MP strafe stops have little measured travel (the warp slides the rest); no foot-phase matching
  (random foot); starts on slopes / stairs; looks play where he stands (no stand-off from the object); crouch
  moves have no starts / stops.

### 0.11.0: situational idles, Stage 5b (2026-11-11, NOT yet run in game)

MW body only. New `tactics/sv_smart_mw.lua` (TIF.SmartMW), used by PassiveMW as idle activities.
- Spots found around a settled soldier (within 45 of him and 70 of his post):
  - wall lean (left / right shoulder): a vertical face at shoulder height;
  - hand on a surface (table, counter, railing, sandbags) 26-42 high with open space above; 30 or 36 set;
  - sitting on any chair / bench / stool / couch / sofa / seat prop (spawn-menu props work), facing away
    from the backrest; gun maintenance, laptop, phone or asleep.
- With a spot nearby it's used 75% of the time over smoke / phone / water.
- Leans: enter clip follows its own path onto the spot, loop, calm exit; startled: the 4-way react toward the
  threat. Seats: MW19 has no usable sit-down, so soldiers spawned next to a seat start seated (70%); later
  re-seating plays the stand-up reversed and slowed. Startled seated soldiers jump up.
- While sat on, a chair is frozen and stops colliding with characters (restored when he gets up / dies / is
  removed).
- Shot while seated: MW19's chair deaths (`mwd_sit_any_*`).
- Gun hidden for laptop / phone / sleep seats (not gun maintenance or leans).
- Spot traces ignore soldiers and players (no leaning on a teammate).
- Harness: smart 32 (box world + real clip data); passive 28, cover 40, hits 74, warp 4 unchanged.
- Untested: real-map spot quality (thin walls, odd props), whether the lean / table clips keep a gun in hand
  looking right, the reversed sit-down slide.

### 0.10.1: sideways calm walking, pistols, desync (2026-11-11, NOT yet run in game)

From the user's 0.10.0 test:
- Calm soldiers slid sideways playing the forward walk (also on the GTA body: calm mode only has a forward
  walk).
  - `sv_move` M.Face: calm soldiers on the move face their path and look around once stopped.
  - cl_body safety net: a calm soldier moving more than 75 degrees off-axis uses the directional set while
    turning.
- Pistols on the MW body:
  - Own sets: aim idle, 8-way CQB pistol walk / fast, crouch idle, calm patrol idle / walk, alert idle,
    jog / sprint.
  - Grip measured from MW19's pistol aims (the barrel comes from the right hand; the left hand cups it).
- Pistol draw / back to rifle:
  - `W.Switch` times the switch from MW19's draw clips: the gun changes on `pistol_pickup` /
    `pistol_putaway`, shooting resumes at `start_aim` (~0.67 s to the pistol, ~1.3 s back to the rifle).
  - Clients play the clip on the upper body (NW2 `tif_switch_clip` / `tif_switch_t`); crouched versions too.
- Desync:
  - Reactions and calm-downs wait for each soldier's own small random delay (squads share knowledge so their
    awareness flips together); spotting an enemy stays immediate.
  - Activities start after 8-35 s still and only 65% of the time.
  - Each soldier keeps one of 6 calm / 5 alert MW19 idles, picked by entity index so all clients agree.
- Harnesses: passive 28, cover 40, hits 74, warp 4, host 13.
- Group spawns too far out (user). `TIF.SpawnPoints` took random points anywhere inside the navmesh areas that
  touched the circle, so big open-ground areas sent soldiers thousands of units off.
  - Points are now random inside the circle (denser near the middle), snapped to the navmesh, and rejected
    outside it or more than 160 units up / down.
  - Default spread grows with the group: 120 + 25 per soldier (fireteam ~220, squad ~320).
  - Only the spawn menu groups and tif_spawn commands use this tight spread. API.SpawnSquad (GOPS / DTW / SWAT)
    keeps the old loose spread on purpose (the user wants DTW FOBs spread far out); `opts.tight = true` asks
    for the compact one.

- Prone on slopes (user): cl_body `prone_tilt`.
  - Ground traces at the head / feet ends and both sides give pitch and roll; resampled every 0.15 s,
    eased, max 35 degrees.
  - Faded in and out with the get-down / get-up timing.
  - MW body: host render angles (bone-merged model and gun follow). GTA body: the Prone Mod model's local
    angles.
  - Visual only (hitboxes unchanged). Reset on a body switch.

### 0.10.0: calm posture, reactions, hit reactions, situational deaths, CQB movement, prone aim, grenades (2026-11-11, NOT yet run in game)

MW body only (`tif_mw_anims 1`). 548 MW19 clips, 10 MB.

- Stage 5 (`tactics/sv_passive_mw.lua`):
  - Calm walk/idle = MW19 stealth patrol, weapon lowered; TIF's calm walk speed is now 40.
  - Alert posture (half-raised) when suspicious / searching / on edge; the new `alert` gait matches its speed.
  - Idle activities at posts and squad hold spots: smoke / phone / water, start-loop-end. Put away before
    walking.
  - Caught off guard: awareness rising during an activity plays its end first (hurried in a fight) and delays
    the first shot.
  - Graded react clips when awareness rises, by stimulus (footstep small; gunfire / explosion / man_down
    medium; known enemy large), toward front/left/right/back, patrol or alert, standing or walking. Spotted
    while calm: a quick large one, and the first shot waits for it.
  - Investigation idles where something was heard; check-body on a downed ally, then the alarm to allies
    within 1500.
  - Alert-to-patrol clip when calming down.
- Arrivals into cover follow their own root path, warped to end exactly on the node (`Act.Play`
  `{ root, to }`).
- `Act.Play` `clear = true`: a one-shot clears itself when done. Without it a finished clip holds its last
  frame.
- Stage 7 (`tactics/sv_hits_mw.lua`):
  - Deaths: pool by situation (cover type, prone, explosion, crouch, running, standing), then hit region, then
    the clip whose measured fall direction best matches the bullet's push (random among the best 3).
  - The server plays the death clip too (BodyUpdate), so the ragdoll starts from the real mid-fall pose.
  - Ragdoll handoff at each clip's measured cut (pelvis 60% down, at least 0.4 s), every physics bone keeping
    its animated velocity. No still-on-the-ground tail.
  - Pains: short staggers by situation / region / push, cooldown 2.5 s; none in cover or other actions.
  - K:\mw19deathanimations (36 ValveBiped deaths from a friend): QA OK (start standing, end lying; the long
    1-2 s still tails are skipped by the handoff). No name overlap with the MW19 extract; added to the standing
    and running pools.
- Stage 8:
  - CQB movement (8-way walk/fast + interior ready stance) while clearing rooms (NW2 `tif_cqb`).
  - Prone aim blend (+-43 yaw, +-42 pitch).
  - Frag grenades from cover (`TIF.GrenadeMW`, convar `tif_grenades`): see the comment in
    `tactics/sv_cover_mw.lua`.
- Offline harnesses all pass: cover + grenades 40, passive 26, hits 74, warp 4, host logic 13.

Known limits:
- The gun is hidden during idle activities, grenade throws and dying: both hands leave it, and the sling
  (j_gun) isn't decoded yet.
- No pains in cover yet (MW has 249 cover pains to wire).
- Laststand / revive for the casualty system is still to do.
- Grenades are thrown from cover only.

## Content in use

| Side | Faction id | Visual models | Voice pack |
|---|---|---|---|
| Enemy | `militia` | `models/mw2/mw2_soldier_16.mdl` (pm_dpr_militia) | Insurgency: Sandstorm mercenary (`sound/vo/mercenary`) |
| Ally | `pmc` | `models/pmc/pmc_hecu/pmc_pm.mdl`, `models/pmc/pmc_hecu/male_04.mdl` | Battlefield 3 US Marine (`sound/vo/bf3marine`) |

- Both model packs are ValveBiped and retarget cleanly. None of them has prone sequences yet (see results above).
- Voice sets are built from the sound folders directly, so the TFA VOX base addon is not needed. The security-force pack is installed but unused, as requested.
- Default weapons are GTG rifles and MGs. They can be changed in `lua/tif/config/sh_content.lua`.

## Assumed (not yet confirmed)

- GTG and Glide are required; wOS prone and Decent Vehicle are optional.
- Test map not chosen yet.

## Not built yet

Phases 1-7. No soldier entity, AI, cover, squads, vehicles AI or debug overlays exist yet.

### 0.7.18: API v3 for Global Operations (2026-11-09, NOT yet run in game)

- `api/sv_api.lua`, `API.VERSION = 3`. New calls: `SquadClear`, `SquadClearing`, `SquadWithdraw`, `SquadState`, `SquadEnemies`, `GarrisonRelease`. They only wrap what TIF already does (room clearing, the squad withdraw tactic, squad knowledge, garrison leashes); no behaviour changed.
- These were Global Operations' stopgaps (`addons/global_operations`, `gops/sv_adapter.lua`); Global Operations uses TIF's versions now and keeps its own only for older TIF.

### 0.7.19: no empty bodygroup options (2026-11-09, NOT yet run in game)

- Factions can set `noBlank = true`: random looks never pick an empty bodygroup option (blank submodel: no helmet, no gear, no belt). Works per model, so models whose blank sits at a different index are still covered. `tif_soldier.lua` records blank options per model; the faction editor keeps the flag through saves.
- Checked offline against BF3 marine 3's real bodygroups: 0 of 3000 random looks had an empty helmet, gear or belt, and every other option still appeared. Without the flag, 64% had at least one.
- TIF Faction Pack: `usmc_bf3` uses it. New faction `insurgents` ("Insurgents", MW19-style cell):
  - Models: one pool from Insurgency Inspired Bad Guys, Insurgency: Modern Infantry Combat (Iraqi insurgent; the addon's marines aren't in this copy) and Middle Eastern Insurgent Ragdolls (long coat, shirt). All four have the full ValveBiped skeleton.
  - Voices: the two Arabic packs.
  - Loadouts: AKs with SMGs and machine pistols mixed in (Uzi, mini-Uzi, MP5-style, Skorpion-style), SMG-heavy assaulters, PKM, RPG, Dragunov/SKS, shotguns.
  - Allied with the other enemy factions; Global Operations doctrine: guerrilla.

### 0.7.20: every faction and role in the spawn menu (2026-11-09, NOT yet run in game)

- `config/sh_spawnlist.lua`: NPCs tab entries for every faction TIF knows (built-in, content packs, faction editor), one category each ("TIF - <name>"):
  - every role: Rifleman, Squad Leader, Assault, Support Gunner, Marksman, AT Gunner, Breacher, Security;
  - Fireteam (4) and Squad (8), spawned together as one squad with the usual mix.
- Soldiers are all `tif_soldier`: the spawn menu passes `tif_faction` / `tif_arch` key-values (new `ENT:KeyValue`). Groups use the new `tif_spawner` point entity, which spawns them through `TIF.SpawnSoldiers` (with an undo entry for the player) and removes itself. `TIF.SquadMix` is now public.
- Rebuilt when the faction list changes (content packs, editor save or delete, the client receiving factions). A client whose spawn menu is already built reloads it.
- The old single "PMC Rifleman" / "Militia Rifleman" entries are gone (their classes stay; TIF uses them internally).
- Offline: 10 factions x 10 entries = 100 entries, the right key-values; removing a faction removes its entries.

### 0.7.21: frayed faction models after prone (2026-11-09, NOT yet run in game)

- Rare frayed look (user screenshot: an insurgent with bent legs and an arm out while standing).
- **Cause:** on getting up from prone, `prone_exit` put the faction model back by asking for its "reference"
  sequence. Models without one kept their last prone frame underneath the retarget. The retarget only drives the
  main bones, so the others (clavicles, spine, fingers...) stayed in the prone pose. Those are ragdoll-only models,
  whose rest pose is "ragdoll" (all four Insurgents models have only that one sequence). `rest_pose` already had
  the "ragdoll" fallback; prone exit didn't use it.
- **Fix:**
  - prone exit uses `rest_pose` and resets the prone aim pose parameters;
  - `rest_pose` remembers the sequence (`f.tifRestSeq`);
  - twice a second a standing soldier's model is put back in its rest pose if anything changed it
    (`Bd.Stats.restFixed` counts them).

### 0.7.22: camo picked per mode (2026-11-09, NOT yet run in game)

- `TIF.SetVariantOverride(owner, faction, mode)` / `TIF.API.SetCamo(owner, faction, mode)`: a mode (GOPS, DTW) picks a variant faction's camo ("squad", "mixed" or a variant id) while it runs, over the faction's own `variantMode`. A spawner's `ent.tifVariant` still wins. Nil faction clears the owner.
- `TIF.CamoChoices(id)`: the { value, label } list for camo menus (empty for factions without variants).
- Offline: an override to one variant picked it 20/20 times; clearing removes it.

### 0.7.23: soldiers shown as the bare GTA ped (2026-11-09, NOT yet run in game)

- User screenshot: enemies drawn as the bald freemode ped. That's what the client draws when the faction model can't be put on the GTA body (its bone map doesn't build: unreadable skeleton or bones that don't match), retried forever.
- Server: `TIF.VisualUsable(host, model)` checks the map before a model is handed out; `PickVisual` only picks models that pass (all of them if none do). Each bad model is warned once, and 8 s after map load every faction is checked and the bad ones listed in the server console.
- Client: a soldier whose model still fails twice here gets another model of the same faction that works on this client (looks only; his corpse wears the same). `tif_visual_check` lists the models that fail on your client.
- Offline: with 2 of 4 models failing, 40 picks never chose a bad one; a faction with only bad models still gets one.

### Faction pack: content bundled, US Army removed (2026-11-09)

- tif_faction_pack now carries copies of its factions' models, the materials they use, and the specops / securityforce / securityforcevip voices (about 1.1 GB), so a friend only needs this one addon. Local testing only: the content belongs to its Workshop authors.
- `us_army` (US Army Multicam) removed at the user's request: faction, ally entry, GOPS doctrine entry, and its 265 copied files. The original addon (us_army_multicam_playermodel_20_bodygroups_2753765285) is untouched.

### 0.7.24: API v4 for SWAT Operations (2026-11-10, NOT yet run in game; offline-tested through SWAT's harness)

- **Engage filter** (`API.SetEngageFilter(owner, fn)`): fn(soldier, target) -> "fight" | "cover" | "ignore". Checked in perception `candidates()` ("ignore" = not a contact) and in `W.Think` before every shot ("cover" = aims, never fires). Opt-in: nothing changes until a mode sets one.
- **Commanded room entries** (`API.SquadClear(sq, pos, opts)`): a chosen door from the squad's side, hold on the stack until `API.SquadClearGo(sq, opts)`, methods open / kick / breach, `onEntry` callback after the door opens (flashbang, gas: the entry waits for it), `single` = clear that room only, `teamSize`. Hooks `TIF_CQBRoomClear`, `TIF_CQBDone`. A held stack doesn't time out. Locked doors end with reason "door locked".
- **Fixed:** in a multi-room clear, any closed door after the first ended the clear as "door won't open" at once (`cq.opening` was never reset between doors).
- **Tasks and helpers:** `SoldierTask` / `SoldierTaskDone` (go there, face that way, shoot what shows up), `DoorAt`, `DoorInfo`, `DoorRooms`, `RoomAt`, `RoomCenter`, `SquadClearDoor`, `SquadSetLeader`, `SquadFormation`, `Stun` (blind + no firing + morale hit), `Say`, `SoldierState`; `SquadState.clear`.
