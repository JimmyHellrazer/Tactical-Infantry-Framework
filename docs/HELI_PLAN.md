# TIF: infils and reinforcement vehicles (plan + change log)

Status: **Stage 1 (Black Hawk model + flight) checked in game (0.21.1). Stages 2-3 (Black Hawk passengers: landed
drop + rappel) built in TIF 0.22.0, NOT yet run in game.** Started 2026-11-13.

Goal (user): reinforcement helicopters (and ground vehicles) inside TIF, callable by any gamemode
(DTW, GOPS, SWAT, later ones). Lots of variety. **No awkward waits after a man gets out** (the MP infil
"stand there until the round starts" tail): every dismount runs straight into movement.

Rules for this work: changes to the TIF base are made with caution. New code goes in its own module and
API calls; any edit to an existing TIF file is named here (file + reason) before it is made, and logged in
the change log at the bottom.

Sources:
- MW19 clips: `K:\duglastakedown` (40,855 SEAnims)
- MW22 clips: `K:\mw22 anims 2\xanims` (50,517 SEAnims; this export carries few notetracks)
- Vehicle models: `K:\cod choppers`
- Anim conversion: `K:\jimmyproject\tif_mw` (manifest.py) + `K:\mods map pics\smh_cod_anim_baker\tools`
  (cod_anim_prep.py, cod_to_breen.py, tif_mw_build.py)
- Survey script: session scratchpad `infil_scan.py` (length, root travel / drop, end speed, release notetracks)

---

## 1. Models on hand (`K:\cod choppers`)

| Model | Folder | Useful bones |
|---|---|---|
| UH-60 Black Hawk (`blima`) | `veh8_mil_air_blima` (+ `_cp`, door, landing gear) | `tag_seat_0..5`, `tag_seat_exit_0..5`, `tag_guy0..9`, `tag_fastrope_le/ri`, fastrope hooks/clasps, `side_door_l/r_jnt`, `main_rotor_jnt`, `tail_rotor_jnt`, blade + blur tags, `tag_doorgun`, `tag_gun_l/r`, wheels |
| Black Hawk crashed / destroyed | `debris_mil_air_blima_dst_lm`, `veh8_mil_air_blima_dst` | wreck for shoot-downs |
| MH-6 Little Bird (`lbravo`) | `veh8_mil_air_lbravo_mp` (bench version) + parts (miniguns, platforms, blades, dst) | `tag_seat_0..5`, `tag_passenger1..6`, `tag_personnel_platform`, `tag_turret_left/right`, rotor tags |
| Mi-17 / Mi-8 (`mindia8`) | `_open_back`, `_interior_static`, `_turret`, `_spotlight`, `_static_dst(_tail)` | `tag_guy0..13`, `tag_fastrope_front/back_le/ri`, `j_backdoor_le/ri`, `side_door_l/r_jnt`, `tag_missile_*`, `tag_spotlight`, `tag_turret` |

The CoD passenger clips are authored against these tags, so seat and rope positions come straight from the
model; no hand placement.

---

## 2. Infil catalogue

Times are clip length. "Drop" = how far the man descends (inches); "release" = the notetrack where CoD hands
the AI back to code (`code_move` / `finish`), i.e. where TIF takes over.

### Air, model on hand

| # | Infil | Clips | Seats | Notes |
|---|---|---|---|---|
| A1 | **Black Hawk, landed, side doors** | MW19 `sdr_mp_veh_blima_ground_{l,r}{1,2,3}_idle/_exit` | 6 | 3.2-5.0 s, 33 drop. No release notes: release point from root motion (see §3) |
| A2 | **Black Hawk, fast-rope (AI)** | MW22 `iw9_ai_infil_blima_seat_0..5_idle/_getout`, `_rope_l/r_idle/_drop`, `_crew_1/2`, `_heli` | 6 + 2 crew | ~17 s getout incl. ride, 404 drop. Rope model anims included |
| A3 | **Black Hawk, rappel from high hover** | MW19 `vh_blima_rappel_soldier{0,1,2,3,4,6,8,9}_idle/_drop`, pilot / copilot | 8 | 6.4-10.3 s, ~790 drop (20 m). Ends crouched; `motion_warp_end` ~7.7 s |
| A4 | Black Hawk, rebel / campaign fast-rope | MW19 `reb_com_vh_blima_guy0..5_idle/_exit`, `chief(2)` | 6-8 | 15 s, 440 drop, release `finish` 13.4 s |
| A5 | Black Hawk, MP cutscene infil | MW19 `mp_infil_blima_guy01..03/chief` (+ `_r_` side), MW22 `iw9_mp_infil_blima_seat_0..5/rope/crew` | 4-6 | Long player-style intros; usable late-started for variety only |
| A6 | **Little Bird bench, landed** | MW19 `sdr_mp_veh_lbravo_ground_{l,r}{1,2,3}_idle/_exit` | 6 | 5-5.6 s, `motion_warp_end` 2.8 s |
| A7 | **Little Bird bench, hop-off into action** | MW19 `reb_vh_lbravo_guy1..6_idle` + `_exit_combat_run / _combat_idle / _patrol` (+ deaths); same set in MW22 as `iw9_veh_heli_medium_seat_2..7_*` | 6 | **Best "no wait" set**: combat_run 2.7-3.8 s, `code_move` at 1.7 s, ends running (70-133 u/s) |
| A8 | Little Bird MP infil | MW19 `mp_infil_lbravo_{a,b}_guy1..6(_loop)(_exit)_wm`, pilot / copilot | 6 | 6 s exits, `ws_raise` 0.5 s |
| A9 | **Mi-8, landed, doors + ramp** | MW19 `sdr_mp_veh_mindia8_ground_{fl,fr,rl,rr}{1,2,3}_idle/_exit`, `_jug_` | 12 + juggernaut | 4.1-7.7 s, `finish` 0.3-0.5 s before the end |
| A10 | **Mi-8, fast-rope** | MW19 `vh_mindia8_{front,rear}_{l,r}_{1,2,3}_idle/_exit`, `_rope_exit/_rope_fall`, `vh_mindia8_fastrope_death`, heli `_arrival_2/_exit_2..8/_idle` | 12 | 9.8-13.2 s, ~565 drop, `finish` ~9.7 s. Rope falls away after. A man can be shot off the rope |
| A11 | Mi-8 MP infil | MW19 `mp_infil_mi8_guyl/guyr_01..06`, heli | 12 | 10 s, `ws_raise` 5.5 s |
| A12 | Mi-8 escape / jump | MW19 `mp_infil_escape4_mindia8_01..07`, `wz_infil_mindia8_*` (jump out, squad / solo) | 4-7 | Leads into parachute (needs a chute model) |

### Air, model missing

| # | Infil | Clips | Missing |
|---|---|---|---|
| M1 | Parachute / HALO drop | MW19 `sdr_mp_parachute_*` (41), `sdr_com_parachute_*` (19), `sdr_mp_infil_ac130_jump*`, `wz_infil_skilo_*`; MW22 same + `wz_infil_cargoplane` | parachute model; optional AC-130 / cargo plane (`skilo`) |
| M2 | MW22 4-rope transport (`palfa`) | `iw9_mp_infil_palfa_seat_*` (40), `_rope_fl/fr/bl/br`, `_crew_1..3`, `_vehicle` | model (big 4-rope heli; exact type to confirm) |
| M3 | MW22 `mbravo` heli | `iw9_mp_infil_mbravo_seat_*` (12), `_alt/_luxury/_swapmeet` (map variants), pilot | model (unknown type) |
| M4 | Hind (`hindia`) | MW19 `sdr_mp_hindia_seat00..05_getin`, deaths, gunner scrub | model; gunship, not a troop drop |

### Ground, all models missing

| # | Infil | Clips | Seats | Notes |
|---|---|---|---|---|
| G1 | **Military cargo truck, bed** | MW22 `iw9_veh_mil_cargo_truck_seat_2..7_exit_combat_run / _combat_idle / _gate_combat_idle / _idle`, `_entry` | 6 | combat_run 4.2 s, ends running ~100 u/s |
| G2 | **Pickup / technical** | MW22 `iw9_veh_pickup_fullsize_2014_*` and `_techoarmor_*` (exit run / combat idle / idle, with / without doors, from crouches in the bed); MW19 `sdr_com_veh8_techo_bed_1..4`, `_back_1..2` in/out | 4-8 | exit_run 2.2 s ending at ~190 u/s. Biggest ground set |
| G3 | Rebel truck (`decho`) | MW19 `reb_com_veh8_decho_back_1..4_in/out/idle/pain`, driver, passenger, turret | 4 + crew | out 1.5 s, already moving |
| G4 | **APC rear / side doors** | MW22 `vh_apc_org_unload_door_back_guy5..8`, `_left_guy1..2`, `_right_guy3..4`, door anims | 8 | 2.2-3 s, `code_move` at the end |
| G5 | SUV / sedan (cartel, PMC, civilian) | MW22 `iw9_veh_suv_*`, `iw9_veh_sedan_*` exit combat_run / combat_idle / idle | 4 | combat_run 2.2 s, ~190 u/s |
| G6 | JLTV | MW22 `iw9_veh_jltv_seat_0..3_getin(_nodoor)`, turret in / out, two exits | 4 + gunner | thin exit set |
| G7 | 12-man vehicle (`mkilo23`) | MW19 `sdr_mp_veh_mkilo23_01..12_exit` | 12 | 3.4-4.3 s, `finish` ~3 s. Vehicle type unknown (APC / truck) |
| G8 | Opforce van, sliding door | MW19 `infil_opforce_van_1..6/driver/chief/van`; MW22 `iw9_mp_infil_van_seat_*`, `_van_fort_*` | 6 | 15 s cutscene style |
| G9 | Tailgate truck (`umike`) | MW19 `mp_infil_umike_guy0..5(_exit)_wm`, driver, tailgate | 6 | 6 s exits |
| G10 | Tank ride (`tango72`) | MW19 `mp_infil_tango72_{a,b}_guy1..6_exit_wm`, turret, car crush | 6 | riders jump off a T-72 |

### No vehicle needed

| # | Infil | Clips | Notes |
|---|---|---|---|
| N1 | Rappel down a building | MW22 `twr_global_rappel_td/tu_*` (walk / shuffle / jump / idle, 8-way) | roof-to-ground entries, uses a rope only |

---

## 3. "Straight into movement" (no MP wait)

What the survey shows:
- The **MP infil clips** (`mp_infil_*`, `iw9_mp_infil_*`) are player intros: 10-15 s, end standing still,
  hand-over notes (`ws_raise`, `free_look`) well before the end. That tail is the wait the user dislikes.
- The **AI clips** (`sdr_mp_veh_*`, `reb_*`, `vh_*`, `iw9_veh_*`, `iw9_ai_*`) carry release notetracks:
  `motion_warp_end` (feet down), `code_move` (AI may start moving), `finish` (clip done for gameplay).
  `reb_vh_lbravo_guy1_exit_combat_run`: `code_move` 1.7 s of 3.8 s, already running.

How TIF will do it:
1. Prefer exits that end moving (`exit_combat_run`, `exit_run`); pick idle / patrol exits only for calm drops.
2. Hand the soldier back at `code_move` / `finish`, not at the clip's end. Clips without notes (MW22 export,
   MW19 `blima_ground`) get a release frame computed by the builder from root motion (feet planted and root
   speed rising), stored in the clip data.
3. Carry the clip's exit velocity into TIF's move system so the legs blend into the jog / sprint at that
   speed (no stop-then-start), and give the squad its first goal before touchdown so the order is ready.
4. Rappel / fast-rope landings end crouched: release into the crouched move or straight to cover.

---

## 4. Stages

1. Black Hawk model compiled for GMod (rotors spinning, doors, tags as attachments), flying on a scripted
   path: approach, flare, land or hover, leave. Shoot-down to the destroyed model.
2. Anim build: the A1 / A2 / A3 / A7 / A9 / A10 sets through the existing MW pipeline into a new clip
   family, with release frames.
3. Ride + dismount on the TIF side: seats from the tags, the release hand-off of §3.
4. API: `TIF.API.Reinforce(...)`-style call (faction, squad size, landing zone, infil type or "any"),
   hooks for gamemodes; encounter reinforcements may use it.
5. Little Bird and Mi-8, then ground vehicles as models arrive.

TIF files that will need touching (to confirm per stage): `autorun/tif_init.lua` (load the new module; done in
0.21.0), possibly `npc/sv_move.lua` (start a move at a given speed, Stage 3). The API calls live in the air module
itself (`TIF.API.CallHeli` etc.), so `api/sv_api.lua` stays untouched.

---

## 5. Stage 1 as built (0.21.0)

### Where things are

| What | Where |
|---|---|
| Model build script | `K:\jimmyproject\tif_air\heli_build.py <blackhawk / blackhawk_dst>` (build files in `build\`) |
| Offline harness + survey scripts | `K:\jimmyproject\tif_air\harness\` (`heli_harness.py <TIF folder> heli_harness.lua`, needs lupa) |
| Content addon (new) | `addons/tif_air`: `models/tif_air/blackhawk(_dst).mdl`, `materials/tif_air/blackhawk(_dst)/` |
| Types (shared) | TIF `lua/tif/air/sh_air.lua` (`TIF.Air.RegisterType`, `TIF.Air.Available`) |
| LZ checks, routes, API, commands | TIF `lua/tif/air/sv_air.lua` |
| Helicopter entity | TIF `lua/entities/tif_heli.lua` |

### Model (`heli_build.py`)
- Source: `veh8_mil_air_blima_LOD0.smd` (146,650 tris, 187 bones, inches). The CoD frame is kept: the entity origin
  is the rotor hub, the wheels are 163.3 below it (`tag_ground`), so CoD passenger clips line up with the tags.
- Bones kept: body, main rotor, tail rotor, both cabin doors, and 37 tags as bones + attachments of the same name
  (`tag_seat_0..5`, `tag_seat_exit_0..5`, `tag_guy0..9`, `tag_fastrope_le/ri`, `tag_ground`, `tag_engine_left/right`,
  `tag_deathfx`, `tag_doorgun`, `tag_gun_l/r`, `tag_pilot1/2`, `tag_turret_npc`, `tag_light_belly`, rotor tags).
  Everything else (cables, seat belts, sticks, wheels) is merged into the body.
- Bodyparts: body, interior (gone at the far LOD), rotor (0 = blades, 1 = blurred blades).
- Triangles: 47.2k (body 24.6k, interior 21.8k, blades 0.4k). **No visible LODs** (user, 0.21.1: one big,
  short-lived object; the popping was too aggressive); the shadow uses the 16.2k mid version. Collision: 3 convex
  boxes (cabin, boom, fin), rotor not solid.
- studiomdl turns every model 90 deg left as it compiles; the build writes the SMDs turned the other way
  (`UNTURN`), so the compiled model is in the CoD frame (checked from the compiled hull: x -493 tail .. +358).
- Textures (DDS BC7 / BC4 via Pillow -> vtex): hull 2048 with normal map (alpha = gloss -> phong mask), interior
  1024 with the occlusion channel baked into the colour, rotors 512, blurred blades translucent, glass dark
  translucent, decals alpha-tested.
- Wreck: `veh8_mil_air_blima_dst` (40.5k -> 16.6k / 3.7k / 1.0k), 1024 textures.

### Flight (`tif_heli`)
- Kinematic: a physics shadow follows the flight model, so it collides, pushes players and takes bullets.
- Route (`TIF.Air.PlanRoute`): 16 hull traces at cruise height out from the LZ (rotor-disc wide); it comes in along
  the longest clear run (or `fromYaw` when clear) and leaves roughly straight on.
- Phases: inbound (cruise 1300 u/s, terrain following, under the sky) -> approach (slows to stop over the LZ, turns
  to the landing heading) -> descend (doors open in the last 500) -> hold (landed, or hovering with a slight drift)
  -> climb (doors shut) -> depart -> removed at the exit point. Flyby: inbound -> depart.
- Attitude from acceleration: nose down to speed up, up to flare, banks into turns (max 16 / 22 deg).
- LZ (`TIF.Air.CheckLZ`): land needs flat ground (8 samples within 24), fuselage footprint and rotor disc clear, and
  room above; else a fast-rope hover over whatever is under the disc (hub 560 to 950 above the ground); else refused.
- Shot down (health 3000 x `tif_heli_health_scale`, blasts x1.5): becomes a real physics object, spins up, engines
  smoke, explodes on impact (or after 14 s), leaves a burning wreck (`tif_heli_wreck_time`, 120 s).
- Client: rotor and tail rotor spun with bone manipulation, blurred blades above 55% rotor speed, doors slide 64
  back in 1.6 s, rotor wash dust on the ground below, rotor loop sound.

### API (game modes)
```lua
local heli, modeOrWhy = TIF.API.CallHeli({ pos = Vector, mode = "auto" | "land" | "rope" | "flyby",
    type = "blackhawk", fromYaw = 90, hold = 8, holdUntilRelease = true,
    onArrive = function(heli) end, onDestroyed = function(heli, attacker) end })
TIF.API.HeliRelease(heli)       -- leave now
TIF.API.CheckLZ(pos, type, want) -- { mode, ground, hubZ } or nil, why
TIF.API.Helis()                 -- active helicopters
-- hooks: TIF_HeliArrived(heli), TIF_HeliLeaving(heli), TIF_HeliDestroyed(heli, attacker)
```

### Test commands
`tif_heli [auto|land|rope|flyby] [from yaw]` (to your crosshair), `tif_heli_lz` (check the crosshair spot),
`tif_heli_release`, `tif_heli_kill` (crash test), `tif_heli_clear`.

### Offline checks (harness, flat stub world): 20 / 20
Open field: lands, phases in order, hub at 163.3 on the LZ, never below landing height, pitch <= 16 / roll <= 22,
hooks fire, gone after 38 s (approach 6.7 s, descend 11.1 s, hold 17.9-25.9 s). A 300-high block on the LZ: hover
at hub 560, holds within 4. Low sky: landing refused. Flyby. Corridor: comes in along the only open way. Held until
`Release()`. Crash: explodes even without a collision.

### Not known until it runs in game (check these first)
1. Rotor spin: main rotor spun as yaw in its bone, tail rotor as pitch (`tailAxis` in sh_air.lua flips it to roll).
2. Doors slide the right way (`doors.travel` = -64 on the bone's x).
3. Pitch / roll signs look right (nose down when speeding up, bank into turns).
4. Textures: normal map green channel, glass, decals.
5. Sound is an HL2 stand-in (`npc/attack_helicopter/aheli_rotor_loop1.wav`); swap `sound` in sh_air.lua for a real one.
6. LOD switch points (`lods` in heli_build.py) and the shadow pushing players near the skids.

---

## 6. Stages 2-3 as built (0.22.0): Black Hawk passengers

### Two drops
| Drop | Clips (tif_mw_anims family `heli`) | Seats | Hover | Out in |
|---|---|---|---|---|
| landed (`land`) | MW19 `sdr_mp_veh_blima_ground_{l,r}{1,2,3}_idle/_exit` -> `mwhb_land_<l|r><n>_idle/_exit` | 6 (tag_guy7, 8, 1 left; 5, 6, 0 right) | on the ground | 3.0-4.5 s after touchdown (harness) |
| rappel (`rope`) | MW19 `vh_blima_rappel_soldier<n>_idle/_drop` -> `mwhb_rap_<n>_idle/_drop` | 8 (tag_guy0-4, 6, 8, 9) | hub 920 above the ground (~23 m) | 10.3 s for all 8 |

### How the clips are placed (`K:\jimmyproject\tif_air\heli_infil_data.py`)
- CoD passenger clips are authored on a vehicle tag: the clip's tag_origin at frame 0 is the man's place relative to
  that tag. The script reads the tags from the Black Hawk model and each clip's start offset, end point and
  notetracks, and writes `addons/tif_air/lua/autorun/server/tif_air_infil.lua` (`TIF_AIR_INFIL`).
- Check of the mapping: every rappel man lands at the same height when placed on `tag_guy<n>` (hub 920.4, spread 2.1).
  Landed: 4 of 6 agree with the real landing height (164.4 vs tag_ground 163.3); l2 / r2 sit on the door sill with
  their legs hanging out and would end 18 below the ground: their drop is warped onto the real ground (TIF.Action
  root + to warp), invisible over a 4 s clip.
- Release (hand-back to TIF): the clip's `code_move` / `finish` notetrack if it has one, else computed from root
  motion (feet down, then where his ground speed drops under 45% of its peak after that), with his velocity then.

### Runtime (`tif/air/sv_air_ride.lua`, `TIF.AirRide`)
- Boarding: soldiers are parented to the helicopter at seat = tag + start offset, ghosted, `MOVETYPE_NONE`, playing
  the seat idle. `npc.tifHeli` holds the state; `npc.tifVeh` = the helicopter too, so every TIF system that leaves
  vehicle riders alone (movement, facing, cover, weapon choice, reactions, pains) leaves them alone.
- Dismount: once it has landed / is hovering with the doors open, each man (0-0.35 s apart) is unparented onto his
  seat and plays the exit / drop clip with root motion (`TIF.Action`), warped so his feet end on the real ground.
- **No wait:** at the release point he's handed back: moving and colliding normally, loco velocity = the clip's
  velocity there, and a first `run` goal 320-460 on along his exit (start-from-standing clip skipped). The squad gets
  its order once everyone is out (game mode's, else hold the LZ).
- The helicopter leaves by itself 1.2 s after the last man is out (never waits more than 45 s). Shot down with men
  aboard: they die with it. Ropes (rappel): drawn from `tag_fastrope_le / _ri` to the ground while men are on them.

### API
```lua
TIF.API.CallHeli({ pos = lz, mode = "auto" | "land" | "rope",
    passengers = { faction = "pmc", count = 6, archetypes = { ... } }   -- a new squad aboard
              -- or { soldiers = { npc, ... } }                          -- existing soldiers
    -- passengers.order = { kind = "advance", pos = target, opts = { pace = "rush" } }  once everyone's out
    holdUntilRelease = true, -- optional: keep the helicopter there
    onEmpty = function(heli) end })
-- hooks: TIF_HeliRiderOut(npc, heli), TIF_HeliEmpty(heli)
```
Test: `tif_heli_drop [auto|land|rope] [faction] [count]`.

### Offline (`harness\heli_ride_harness.py`, real sv_action.lua + real built clip data + real model tags): 21 / 21
Landed: 6 aboard, no drift on the seats in flight, all 6 handed back on the ground (|z| <= 2), clear of the fuselage
(closest 66 from the centre line, beside the nose), still moving (34-49 u/s), each with a run goal, all out within
4.5 s of touchdown, collisions restored, squad told to hold, helicopter gone at 36 s. Rappel: 8 aboard, hover at 920,
all 8 on the ground, ropes out then gone, all down within 10.3 s, helicopter leaves. Shot down: the 6 aboard die.
Flight harness still 20 / 20.

### Not known until it runs in game
1. Seat poses vs the cabin (the tag mapping for the landed set is from heights and exit directions, not seen).
2. Needs `tif_mw_anims 1` (the mwhb_* clips are on the MW19 body); without it men are put on the ground beside the
   door (no clip).
3. The gun in these clips is held from the hand (gun_holds.py not re-run for the new clips).
4. The squad is created at the LZ and put aboard in the same tick (should never be seen there).

### Changed in this stage
- New: `tif/air/sv_air_ride.lua`; `addons/tif_air/lua/autorun/server/tif_air_infil.lua` (generated);
  `K:\jimmyproject\tif_air\heli_infil_data.py`, `harness\heli_ride_harness.*`, `harness\clip_origin.py`.
- Existing TIF files changed:
  - `npc/sv_brain.lua`: one branch before the vehicle branch: `if npc.tifHeli and TIF.AirRide and
    TIF.AirRide.Think(npc, now) then` (riders also carry tifVeh, so the Glide seat code mustn't see them).
  - `autorun/tif_init.lua`: loads `air/sv_air_ride.lua`; version 0.22.0.
  - `tif/air/*`, `entities/tif_heli.lua` (ours): passengers in `Air.Call`, `tif_heli_drop`, ropes, still hover while
    men are on the ropes, rope hover hub 920 (was 560), route keeps the LZ ground.
- `K:\jimmyproject\tif_mw\manifest.py`: new family `heli` (`heli_family()`); tif_mw_anims rebuilt (all families
  compiled OK, 1484 roles).

---

## 7. Little Bird and Mi-8 (0.23.0)

### Drops now built
| Helicopter | Set (`passengers.set`) | Kind | Seats | Clips (tif_mw_anims family `heli`) | Out in (harness) |
|---|---|---|---|---|---|
| Black Hawk | `land` | land | 6 | `mwhb_land_*` | 4.5 s |
| Black Hawk | `rappel` | rope, hub 920 | 8 | `mwhb_rap_*` | 10.3 s |
| Little Bird | `land` | land | 6 | `mwlb_land_<l|r><1-3>` (MP AI ground exits) | 5.7 s |
| Little Bird | `bench` | land | 6 | `mwlb_bench_<1-6>_run / _ready / _patrol` (campaign AI hop-offs) | 2.3-3.7 s |
| Mi-8 | `land` | land | 12 (+ juggernaut as 13th) | `mwmi_land_<fl|fr|rl|rr><1-3>`, `mwmi_land_jug` | 6.8 s (7.4 with 13) |
| Mi-8 | `rope` | rope, hub 690, 4 ropes | 12 | `mwmi_rope_<fl|fr|rl|rr><1-3>` | 17.4 s (three men queue per rope) |

- A landed / rope drop picks one set of that kind at random (the Little Bird has two landed sets) unless
  `passengers.set` names one. The Little Bird can't rope (`tif_heli_drop littlebird rope` is refused).
- Bench exit styles: `passengers.style` = `run` | `ready` | `patrol` for the whole drop, else per man by the
  situation: in a fight 70% run / 30% ready (stops, gun up); calm 60% patrol / 40% run.

### Tags (found with `harness\tag_fit.py`: landed men must end on the model's ground; a rope set agrees on one hover)
- Little Bird: `tag_passenger1-3` left bench, `4-6` right, for both sets (ground spread 0.0 / 4.5).
- Mi-8 landed: front-left `tag_guy7-9` (out the left door), front-right `guy0-2` (right door), rear-left `guy10-12`,
  rear-right `guy4-6` (out the open back); juggernaut on `tag_ground` (on the body tag he'd end under the cabin
  floor). Ground spread 0.6.
- Mi-8 rope: all 12 authored on `body_animate_jnt` (not a seat): hub 690.2 above the ground, spread 0.2.

### Release rule (changed for all sets)
`code_move` notetrack if the clip has one; else the moment he's on the ground and still moving (>= 45% of his peak
speed after touchdown); else 0.35 s after touchdown. The `finish` note is no longer used: the AI exits reach it after
stopping to aim (Mi-8 ropes: ~3 s standing at the bottom), the wait the user doesn't want. All hand-backs now happen
moving (23-95 u/s), except two Little Bird bench `run` men whose `code_move` comes as they start off (4 and 13 u/s).

### Models (`heli_build.py littlebird | littlebird_dst | mi8 | mi8_dst`)
- Little Bird: 18.0k body (with the benches, `veh8_mil_air_lbravo_personnel_platform`, merged onto
  `tag_personnel_platform`), 2.0k blades, 3.6k blurred; 22 attachments. The export names its textures by hash; the
  recipes (which image is colour / normal / mask) are in `_lb_mats()` (found with `harness\dds_list.py`).
- Mi-8: open-back version (no clamshell doors) + `veh8_mil_air_mindia8_interior_static` merged; 15.5k body, 5.7k
  interior, 2.1k blades, 3.2k blurred; 27 attachments; front sliding doors.
- Wrecks: Little Bird 25.5k, Mi-8 12.5k.
- Build script additions: `extras` (merge part exports onto a tag), `blur` (explicit blurred-blade bones), per-material
  `base` / `normal` / `alpha` / `alpha_ch` / `base_alpha` / `images` recipes.

### Types (sh_air.lua)
| | Little Bird | Mi-8 |
|---|---|---|
| health | 1400 | 4500 |
| cruise / approach | 1500 / 800 | 1150 / 600 |
| rotor radius (LZ) | 170 | 415 |
| hover for rope | - (lands only) | hub 690 (max 800) |

### Test command
`tif_heli_drop [blackhawk|littlebird|mi8] [auto|land|rope] [set] [run|ready|patrol] [faction] [count]`, arguments in
any order; no type = a random installed one. `tif_heli` takes the type too.

### Not known until it runs in game
1. Little Bird: the tail rotor bone (`tag_tail_rotor_rot`) spin axis; materials from hashed images (colour vs mask
   guessed from channel stats); 2% of its triangles disagreed with their normals (left unflipped).
2. Mi-8: door slide (-36 on x, no MW19 door clip to read it from); the cabin collision box is wide (gear, pylons).
3. Seat poses vs the cabins / benches (only heights and exit paths checked).

### Changed in 0.23.0
- TIF: `tif/air/sh_air.lua` (Little Bird, Mi-8, `doorsOpenSets`, `ropeTags`, `Air.AvailableTypes`),
  `tif/air/sv_air.lua` (`set` / `style`, rope refusal for land-only types, doors per type, 12 by default, test
  command parsing), `tif/air/sv_air_ride.lua` (set kinds, per-exit start offsets, exit styles),
  `entities/tif_heli.lua` (rope points per type), `autorun/tif_init.lua` (version). No other TIF file touched.
- `addons/tif_air`: 4 new models + materials; `tif_air_infil.lua` regenerated (new schema: `kind`, `exits`).
- `K:\jimmyproject\tif_mw\manifest.py`: `heli_family()` gains the Little Bird and Mi-8 roles; tif_mw_anims rebuilt
  (1570 roles, all families compiled OK).
- Harness: drops 108 / 108 (every type, set and style; the Little Bird rope refusal; calm bench drops mix styles),
  flight 20 / 20.

---

## 8. Crew dummies, gradual approach, leaving to the map edge (0.24.0)

### Crew (pilots, crew chiefs): client-side dummies (user: no AI needed)
- Per helicopter: an invisible MW19 host body (`models/tif_mw/mw_male.mdl`, alpha 0 so its bones are still built)
  parented at the crew tag, cycling its seat loop, with a faction model bone-merged on it (`ENT:TIFMakeCrew` in
  `entities/tif_heli.lua`). No server entities; gone with the helicopter.
- Faction: the passengers' (NW2 `tif_crew_fac`), else `opts.faction`, else pmc. Model picked from the faction's
  `models` by the helicopter's index.
- Seats (`heli_infil_data.py` CREW -> `TIF_AIR_INFIL[type].crew`, now a shared file
  `addons/tif_air/lua/autorun/tif_air_infil.lua`):

| Helicopter | Pilot / copilot clips | Tag |
|---|---|---|
| Black Hawk | `vh_blima_rappel_pilot / _copilot` -> `mwhb_pilot / _copilot` | tag_pilot1 / 2 |
| Little Bird | `reb_vh_lbravo_pilot / copilot_idle_search01` -> `mwlb_*` | tag_pilot1 / 2 |
| Mi-8 | `vh_mindia8_pilot_idle / copilot_idle` -> `mwmi_*` | body_animate_jnt (lands on its pilot seats) |

- Crew chiefs: Black Hawk only (`reb_com_vh_blima_chief_idle / chief2_idle` -> `mwhb_chief / _chief2`, standing at the
  front of the cabin facing aft, on tag_guy9). A set gets a chief only if he stands >26 from every man's seat and exit
  start (`set.chiefs`): none of the current sets leave room, so no chief shows yet. They belong to the campaign
  fast-rope set (`reb_com_vh_blima_guy0-5` + both chiefs), to add in the Black Hawk round.

### Gradual approach (user: "fly over the LZ then land vertically isn't elegant... bring it in gradually")
- Route: an approach slope along the way in, from cruise height to just over the spot (`Air.SETTLE`: 70 over a
  landing, 40 over a rope hover). The shallowest of 12 / 20 / 35 deg whose path is clear (rotor-wide hull traces in 8
  steps); none clear = the old way (over the spot, straight down). `route.glideD`, `route.glideAng`.
- Flight: from the slope's start it slows evenly from cruise speed to a stop over the spot while coming down an
  eased S-curve (pushes over gently, steepest midway, levels out low), sink fed forward from the slope's gradient x
  ground speed; doors open in the last 1500. Then only the settle (~2 s).
- Harness: 12 deg in the open, within 65 of the curve, arrives 70 above the landed height; a block under the 12 deg
  slope gives 20 deg. (First tries: a straight slope + correction-only sink trailed by 170-220.)

### Leaving (user: "the longest available direction towards the skybox")
- Out along the longest clear run measured to 40,000 (to the edge of the map), straight on winning a near tie (10%);
  removed at its end. (Was: straight on preferred, capped at 12,000.) Spawning in is unchanged (longest run, or
  `fromYaw`, from up to 12,000 out). Harness: walls 6000 out on three sides -> leaves through the open side to 39,600.

### Changed in 0.24.0
- TIF: `entities/tif_heli.lua` (crew dummies, slope approach), `tif/air/sv_air.lua` (glide planning, exit rule,
  crew NW2 values), `tif/air/sv_air_ride.lua` (exit-style "in a fight" check fixed: with no awareness table loaded,
  nil == nil counted as a fight), `autorun/tif_init.lua` (version).
- `tif_air`: `tif_air_infil.lua` moved to shared autorun (crew + `chiefs` per set); the server-only copy removed.
- `manifest.py`: crew roles; tif_mw_anims rebuilt (1578 roles).
- Harness: flight 25 / 25, drops 108 / 108. The crew dummies are client-side: not covered offline.

---

## 9. Fixes from the first in-game look at the drops (0.25.0)

| User report | Cause | Fix |
|---|---|---|
| Huge character shadows during infils | Riders (20 m up on ropes, or inside a cabin) and crew dummies cast shadows; Source stretches them into huge blobs | No shadows while aboard / getting out: NW2 `tif_noshadow` on the rider; new client file `tif/air/cl_air.lua` turns off the shadows of cl_body's faction model and gun (through `TIF.Body.States`, no cl_body edit); crew dummies never cast one |
| Some infils spawn men in late | Riders were only networked to a client once near it on their own: the helicopter came into view before its men | `SetTransmitWithParent(true)` while aboard (off again once off) |
| A Little Bird exit: the landing (legs opening) plays after they've landed | Measured every built exit (`harness\exit_feet.py`): the clips' feet and root curves agree (within 0.13 s). Most likely the clip's name reached the client after his new position: he was shown seated while already moving down, then the clip jumped in at its landing frames | Exit clips now start 0.4 s after they're announced (`tif_act_t` in the future); their first frame is the seat pose, so the lead-in doesn't show. **Check in game: this is the probable cause, not a proven one** |
| Men that land crouched should stay crouched while the helicopter dusts off | - | Exits ending crouched (pelvis < 30 over the ground at the hand-back, from the built clip: `crouch = true` in the seat data; 41 of 63 exits, every Little Bird bench exit stands) hold there: crouched, aiming, facing away from the helicopter, until it is 1.5 s into its climb (or gone), an enemy shows, or 10 s; then on as before. The helicopter counts them as out |

- Changed: `tif/air/sv_air_ride.lua`, new `tif/air/cl_air.lua`, `entities/tif_heli.lua` (crew shadows),
  `autorun/tif_init.lua` (loads cl_air; version 0.25.0); `heli_infil_data.py` (crouch flag, reads the built clips).
- Harness: drops 129 / 129 (new: holders crouched / aiming / facing out and released once the helicopter lifts away,
  shadows and networking restored), flight 25 / 25.

---

## 10. Black Hawk campaign fast-rope, CH-53 heavy, rope model, per-set hover (0.29.0)

### New drops
| Helicopter | Set | Kind | Seats | Clips | Hover | Out in (harness) |
|---|---|---|---|---|---|---|
| Black Hawk | `fastrope` | rope, 2 ropes | 6 (tag_guy0-5) + crew chief | MW19 `reb_com_vh_blima_guy0..05_idle/_exit` -> `mwhb_fr_*` | 575.6 | 15.5 s (walk to the door, hook up, 440 slide) |
| Black Hawk | `mpleft` / `mpright` | rope, 1 rope each | 3 (two mirrored teams; together they'd walk through each other) + both crew chiefs | MW19 MP intro `mp_infil_blima_[r_]guy01-03` -> `mwhb_mpl_* / mwhb_mpr_*`, cabin lead-in cut (6 / 5 s, builder `trim`); idle = held frame there | 571.8 | 9.3 / 10.2 s |
| CH-53 heavy | `land` | land | 12 (6 front doors, 6 down the ramp) | the Mi-8's `mwmi_land_*`, borrowed | on the ground | 7.4 s |
| CH-53 heavy | `rope` | rope, 4 ropes | 12 | the Mi-8's `mwmi_rope_*`, borrowed | 758.6 | 17.9 s |

- Fast-rope tags: the names don't say which man sits where; each man's slide was matched to a rope (seat on tag_guyN
  that puts his descent 1.5-19 off a rope): guy0 -> 0, 03 -> 1, 01 -> 2, 04 -> 3, 02 -> 4, 05 -> 5. Crew chief 1 now
  stands in this set (clear of everyone).
- Left out: MWII `iw9_ai_infil_blima_*` (A2): seats 4-5 and the crew files are broken in the export ("not an
  SEAnim file"), the other four fit the ropes 11-36 off at hovers ~40 apart. A5 (MP cutscene intros), user: 'could it not just end earlier?': yes. The MW19 ones (authored in the helicopter's own frame, ride on `tag_body`) are the two 3-man sets above: the 5-8 s of cabin cutscene before anyone moves is cut (`tif_mw_build.py` new option `trim`, `heli_infil_data.py` cuts the same), the 2-5 s gun-raise tail is cut by TIF's hand-back on landing. The MWII `iw9_mp_infil_blima_seat_*` have no root motion: still out.
- CH-53: model = the MWII `veh9_mil_air_heli_palfa_doors_open_vehphys_mp` export (ramp down; stays down), wreck =
  `veh9_mil_air_heli_palfa_dst`. Its own MWII infil (`iw9_mp_infil_palfa_seat_0-19`, 20 men, 4 ropes) carries no
  root motion in this export (the slide isn't in the data), so it borrows the Mi-8's clips: each man keeps his Mi-8
  clip, moved from his Mi-8 tag onto the CH-53 by a hub-frame shift (heli_infil_data.py `_heavy_land / _heavy_rope`;
  borrowed men ride on `tag_body`). Rope points from the MWII rope clips (front side windows bone_578d27c4 / 777e4f9a,
  back of the ramp bone_352e9a26 / 54ee2530: within 3 of the model's bones). Pilots: MW19 `reb_vh_palfa_driver/pass_idle`
  -> `mwhv_pilot / _copilot` on tag_driver / tag_passenger.
- Type `heavy` (sh_air.lua): groundZ 249.4, rotor radius 470, health 6000, cruise 1100 / approach 550, rope hover 760
  (max 870). Build: `heli_build.py heavy | heavy_dst` (`_mw2_mats`: recipes from each material's `_images.txt`;
  `lod_scale` 0.5: the body otherwise has 94.6k vertices, over Source's 65,536; textures rounded to powers of two).

### Hover per seat set (TIF base: `tif/air/sv_air.lua`)
`Air.CheckLZ(pos, type, want, ropeHub)`: the hover comes from the drop's rope set (`set.hub`), not one height per
type (the Black Hawk now has rope sets at 920 and 575). `Air.Call` picks the rope set before checking the LZ, and a
type with seats of only one kind does only that kind.

### Ropes (TIF: `entities/tif_heli.lua`, client)
The MWII fast-rope rope (`misc_rapelling_rope_sim_fiber`, the rope the CoD rope clips drive: 200 joints, 3 apart, all
children of the root) built by `K:\jimmyproject\tif_air\rope_build.py` -> `models/tif_air/rope.mdl` (39k -> 8.5k
triangles; colour tinted tan, the export's is flat grey). One per rope tag, posed every frame: thrown out with the
end falling (gravity), hanging and swaying, the rest laid on the ground away from the helicopter, joints scaled
when the drop is longer than the rope (Black Hawk rappel ~830). Cut: the top falls, the rope lies there 8 s. No model: no ropes (user: every rope must be the model; the drawn HL2 lines were removed, 2026-11-14) and a console note; a model added while the game runs is only mounted after a restart. The CoD rope clips themselves aren't used (each is made for one hover height).

### Checks
Drop harness 197 / 197 (MP intro sets added) (new: Black Hawk fast-rope, CH-53 landed + rope; rappel now asked by name), flight 25 / 25.
Not checked in game: the CH-53 model (materials from hashed recipes, tail rotor axis, ramp/door positions vs the
borrowed clips' paths, its seat heights), the rope posing, fast-rope seat poses vs the cabin.

---

## Change log

- 2026-11-13: survey of clips and models (this document). No code changes.
- 2026-11-13, TIF 0.21.0 (Stage 1, NOT yet run in game):
  - New addon `tif_air` (Black Hawk + wreck models, materials).
  - New TIF files: `lua/tif/air/sh_air.lua`, `lua/tif/air/sv_air.lua`, `lua/entities/tif_heli.lua`.
  - Existing TIF file changed: `lua/autorun/tif_init.lua` (two manifest lines after `api/sv_api.lua` to load the
    air module; version 0.20.2 -> 0.21.0). Nothing else in TIF touched.
  - Tools: `K:\jimmyproject\tif_air\heli_build.py`, `harness\`.
- 2026-11-13, TIF 0.21.1 (fixes from the first in-game look):
  - Client error `tif_heli.lua:60 attempt to index local 'B'` every frame, rotors not turning: the client method was
    named `SetupBones`, an engine Entity method that is found before the entity's own, so it never ran. Renamed
    `TIFInitBones` (bones in `self.tifBones`). The harness only covers the server side, which is why it passed.
  - Whole helicopter facing 90 deg left: studiomdl's compile turn. `heli_build.py` un-turns (root bone + vertices +
    collision); heli and wreck recompiled.
  - LODs removed (`"lods": []`); shadow LOD kept at the mid version.
  - Changed: `entities/tif_heli.lua`, `autorun/tif_init.lua` (version only), `tif_air` models.
- 2026-11-13: user checked 0.21.1 in game: "looks all good" (rotors, doors, attitude, facing).
- 2026-11-13, TIF 0.22.0 (Stages 2-3, NOT yet run in game): Black Hawk passengers, landed drop + rappel, release
  into movement. Details and the exact list of changed files: section 6.
- 2026-11-13: user checked 0.22.0 in game: "solid".
- 2026-11-13, TIF 0.22.1: landed drop keeps the cabin doors open the whole flight, in and out (user: the men sit in
  the doorways). `route.doorsOpen` (sv_air.lua, set for the "land" seat set), honoured in `tif_heli.lua` SetRoute /
  climb. Rappel unchanged (doors open from the descent, shut on the climb). Harness: drops 22/22, flight 20/20.
- 2026-11-13, TIF 0.23.0 (NOT yet run in game): Little Bird (landed, bench with 3 exit styles) and Mi-8 (landed 12+1,
  fast-rope 12), new release rule for every set. Section 7.
- 2026-11-13, TIF 0.24.0 (NOT yet run in game): crew dummies (pilots; Black Hawk chiefs wired, none placed yet),
  gradual slope approach, leaving along the longest way to the map edge. Section 8.
- 2026-11-13, TIF 0.25.0 (NOT yet run in game): no rider / crew shadows, riders sent with the helicopter, 0.4 s exit
  lead-in, crouched landers cover the LZ until the helicopter lifts away. Section 9.
- 2026-11-14, TIF 0.29.0 (NOT yet run in game): Black Hawk campaign fast-rope (+ crew chief), CH-53 heavy (borrowed Mi-8 sets), rope model, hover per rope set. Section 10. Changed: `tif/air/sv_air.lua`, `tif/air/sh_air.lua`, `entities/tif_heli.lua`, `autorun/tif_init.lua` (version); tif_air models + `tif_air_infil.lua`; manifest roles mwhb_fr_*, mwhv_*.
