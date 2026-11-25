# TIF MW cars: CoD ground vehicles for TIF / DTW (plan + change log)

Status: **2026-11-13: RAM 1500 (unarmored + armoured) built as Glide cars, with soldier seat clips (stages 1-3 for
the RAMs). Driven once by the user; the AI seat clips are NOT yet run in game.**

Goal (user): replace DTW's GTA cars (`tif_gta_glide_cars_*`) with MW2019 / MWII vehicles whose soldiers get in, ride
and get out with the CoD clips. White-bodied cars take a random tint at spawn. "Make it cool."

Rules: same as the helicopters (`HELI_PLAN.md`): TIF base changes named here before they're made, logged below.

Sources: models `K:\cod cars` (from the MEGA vehicle repository, see the recommendation in this conversation),
clips `K:\duglastakedown` (MW19) and `K:\mw22 anims 2\xanims` (MWII).

---

## 1. What's in K:\cod cars (2026-11-13)

| Folder | Use |
|---|---|
| Pick-Up - RAM 1500 - AQ | `_tech` / `_tech_aq` = the **unarmored** pickup (same body, white vs AQ tan camo paint); `_tech_armor` = the **armoured** one (bigger, plated). Built: `ram1500`, `ram1500_armor` |
| Armored Truck - Standard | the armoured RAM's separate doors / hood (already in `_tech_armor`) |
| Pick-Up - RAM 1500 - Mexican Police | police rack + lights (later: a police variant) |
| Truck - KamAZ 43101 - Base / Cargo / Destroyed | troop truck (MWII cargo_truck clips), cargo layouts, wreck |
| Cargo Truck - Skin 07 Woodland Convoy | KamAZ in woodland camo |
| Truck - Oshkosh MTVR - Payload / Rebel | 12-man truck (drop-off clips only) |
| SUV - 2016 Land-Rover Defender (+ Rebel, Rebel MG) | MW19 decho: many paints, rebel bench, MG version |
| Toyota Hilux - civ_lnd_hindia / mil_lnd_pindia | civilian / military Hilux |
| Toyota Tundra - civ_lnd_techo_rebel | technical with armour pieces |
| SUV - Standard | Jeep Cherokee (MWII suv_1996) |
| Chop Top - Standard | Defender "overland_2016_cage" (MWII) |
| Heavy Chopper - Standard / Destroyed | MH-53E (palfa): MW19 veh8_mil_air_palfa + MWII heli_palfa (for HELI_PLAN) |

## 2. Pipeline (Stage 1)

`K:\jimmyproject\tif_air\car_build.py <id>` (config `CARS_CFG`) -> `addons/tif_mw_cars`:
- chassis model: body + doors / hood / tailgate / steering wheel as bones, CoD tags as attachments (seats
  `tag_seat_0..6`, seat windows, lights, exhaust, engine, ground), wheels removed; 3 collision boxes;
- wheel model: one (left) wheel around its hub, axle along y; Glide sizes it from the model (`useModelSize`) and turns
  it round for the right side;
- dropped: flat tyres (`*_flat`), cracked glass (`*_web` bones + overlay materials), damaged / husk / destroyed parts;
- textures from each material's `_images.txt` (`mat_info.py`: slot 0x0 colour, 0x4 normal; 1x1 black = glass /
  lights -> dark translucent);
- **paint**: `"paint": "auto"` = every material with CoD's own paint mask (slot `0x1E`, black / white: painted panels
  only; glass, trim, rubber, armour plates are black). The mask goes into the colour texture's alpha
  (`$blendtintbybasealpha`) and a `PlayerColor` proxy -> `$color2`; the car's `GetPlayerColor` returns its NW
  `PaintColor`. RAM: body (58% of its texture) + bed / back panels (34%); armoured RAM: the body under the plates;
- data: `lua/tif_mw_cars/data/<id>.lua` (`TIF_MW_CARS[id]`: wheel hubs / radius, seats, lights, exhaust, engine, ground,
  doors, paint) from the model's own tags.

Glide side (`addons/tif_mw_cars/lua`): `base_tif_mw_car` (base_glide_car) builds wheels, seats, lights, exhaust and
engine smoke from the data, applies pickup handling (overridable per car), and picks a random paint from
`TIF_MW_CARS_PAINTS` (12 colours, slightly varied) for white-bodied cars unless the spawner set one
(`car:SetPaintColor(Vector(r, g, b))`). Cars: `tif_mw_ram1500`, `tif_mw_ram1500_armor`. Spawning: Vehicles tab ->
"TIF MW Cars" (own node) or Glide -> TIF MW; console `tif_mw_car <id>` (e.g. `tif_mw_car ram1500_armor`, admin) or
TIF's `tif_vehicle tif_mw_ram1500`.

| Car | Chassis | Wheel | Mass | Paint |
|---|---|---|---|---|
| ram1500 | 35.5k tris, 4 doors + hood + tailgate + steering | 1.7k, r 16.5 | 2200 | random tint |
| ram1500_armor | 44.4k tris | 3.1k, r 19.5 | 3200 | its own (plates) |

## 3. Stages

1. **Models + Glide cars** (in progress): RAM 1500 x2 done; next KamAZ, Defender (+ rebel, + MG), Tundra
   technical, Hilux x2, Cherokee, Chop Top; MTVR as a drop-off truck.
2. **Seat clips**: per car, fit the CoD enter / exit / seat idles to its tags (same method as `heli_infil_data.py`:
   clips are authored on a tag; landed men end on the model's ground), build them into tif_mw_anims.
3. **TIF integration** (base change, to be named before it's made): `vehicle/sv_vehicle.lua` reads seat poses and door
   animations from the GTA car data; it needs a path for MW cars (seat = tag + clip offset, enter / exit = the MW
   clip with the door bone opened by the clip's timing, release into movement like the helicopters).
4. **DTW**: swap `C.Vehicles` / `Trucks` / `Escorts` to the MW classes per side; side paints through
   `SetPaintColor`.

### Stage 2 + 3 as built (2026-11-13)

Clips (stage 2): `K:\jimmyproject\tif_air\car_seat_data.py` fits each seat's MWII clips to the car's seat tags (they
are authored on `tag_seat_N`: idles on the tag, entries from the ground beside the door to the tag, exits from the tag
to the ground) and samples each door's swing from the matching `<clip>_geo_door` clip. Writes
`tif_mw_cars/lua/tif_mw_cars/data/<car>_seats.lua`. Manifest family `car` builds the same roles into tif_mw_anims:
`mwrp_*` (RAM 1500), `mwra_*` (armoured), per seat `_idle`, `_entry`, `_exit_<run|idle|combat>[_<l|r>]`. Bed seats
(4-6) have no idle clip in the game: their idle holds the entry's last frame (new build option `hold`).

| Seats (Glide n = tag_seat_n-1) | In | Out |
|---|---|---|
| 1-4 cab | through its own door (door swings with the clip) | run / calm / gun-up exits, door shuts behind |
| 5 bed, kneeling behind the cab | over the right side | over either side |
| 6-7 bed, tailgate | over the side | over the same side |

**TIF base change (stage 3), named before it was made:**
- `vehicle/sv_vehicle.lua`: a vehicle may answer for its own seats. If it has `ENT:TIFSeatPose(n, npc)` /
  `ENT:TIFSeatEntry(n, npc)`, those are used instead of the GTA seat data (`TIF.GTG.SeatPose / SeatEntry`).
  - pose `{ lp, yaw, clip, exact = true }`: `exact` skips the GTA seat-fit cvars (drop / forward).
  - entry adds `rootz = true` (the clip carries its own height: entries are warped to end on the seat, exits on the
    ground), `combatOut` (exit clip for combat dismounts), `release[clip]` (0..1: hand back before the clip ends, so
    he moves straight on) and `from[clip]` (an exit that starts off the seat).
  - after starting an entry / exit clip: `hook.Run("TIF_SeatClip", npc, veh, n, "in" | "out", clip)` (the MW cars
    swing their doors from it).
- Nothing changes for GTA cars (no such methods: the old path, line for line).

### All cars (2026-11-13, TIF 0.27.0)

| Class | Car (source) | Seats: clips | Paint |
|---|---|---|---|
| tif_mw_ram1500 | RAM 1500 (MWII) | 4 cab + 3 bed gunners, all native | random civilian |
| tif_mw_ram1500_armor | RAM 1500 armoured (MWII techoarmor) | same; doors swing with the plain RAM's curves | own finish |
| tif_mw_cherokee | Jeep Cherokee (MWII suv_1996) | 4 cab (front passenger borrowed from the RAM) | random civilian |
| tif_mw_choptop | Defender Chop Top (MWII overland_2016_cage) | 4 cab | random civilian |
| tif_mw_kamaz | KamAZ 43101 covered cargo (MWII cargo_truck) | 2 cab native; 4 in the back: pose only (put in / out at the door) | random military |
| tif_mw_hilux | Toyota Hilux military (MW19 pindia) | 2 cab (own get-ins) + 4 bed gunners (climb in borrowed from the RAM) | none (MW19 skins) |
| tif_mw_tundra | Toyota Tundra technical (MW19 techo) | driver, passenger, 2 rear cab, 3 bed gunners; entries borrowed from the RAM | none |
| tif_mw_defender | Land Rover Defender 110 (MW19 decho) | 2 front + 2 rear (entries borrowed) + 2 in the boot (out the back) | none |
| tif_mw_mtvr | Oshkosh MTVR troop truck (MW19 mkilo23) | 2 cab (own get-ins) + 8 bench seats: pose only | random military |

Method (all in `car_seat_data.py`): a seat sits on its tag (or a point no tag marks) by its idle; MW19 clips are on the
tag named like their role (`tag_driver`, `tag_bed_guy1`, `tag_cab1`...); a missing entry / exit is borrowed from a
similar RAM seat ("~" clips) and placed from the seat, TIF's warp landing it. Doors: the game's `_geo_door` swing
where there is one, else a plain 62 deg swing about the hinge timed to the clip. `car_build.py` cars are now mostly
`auto` (doors, hood, wheels incl. 6-wheelers, lights, ground read from the skeleton); MW19 materials (packed normal
in slot 0x9, alpha cut-outs in 0x44) are read too.

**Bed gunners**: seats flagged `gunner` (pickup / technical beds). While riding with an enemy in sight (3000 u),
the man turns on the spot to face it (220 deg/s) in his gun-up loop and fires once facing it; back to his seat pose
without one. Cvar `tif_mw_car_gunners 1/0`.

**TIF base change (0.27.0)**, named before made: `vehicle/sv_vehicle.lua` RideThink asks the vehicle first:
`ENT:TIFRideThink(npc, n, now)` returning true = it handles him this tick (the bed gunners). GTA cars have no such
method: unchanged.

**DTW (dtw_campaign, not TIF)**: `C.Reinforce.Vehicles` = MW cars per side (enemy: Cherokee, Chop Top, Hilux, Tundra,
RAM; friendly: Defender, armoured RAM, MTVR), `VehiclesFallback` = the old GTA cars; supply trucks KamAZ / MTVR,
escorts Tundra / armoured RAM, backup Defender (each a list: first installed). `sv_adapter.lua`: seat counts from the
MW car data, side colours through the car's body paint (`SetPaintColor`) instead of a whole-entity colour.

## 4. Not known until it runs in game

New cars (2026-11-13), worth a look first:
- borrowed RAM entries on other cars (Tundra, Defender, Hilux bed, Cherokee front passenger): the man ends in the
  RAM's seat pose, then snaps to the car's own idle; the warp spreads height / turn differences over the clip;
- plain door swings (cars without the game's door clip): direction and hinge (computed, never seen);
- KamAZ back, MTVR benches, Defender boot: pose only, put in / out at the Glide seat's door (no clips exist);
  MTVR bench pose is the RAM back-seat idle on the bench tag (height unchecked);
- MTVR / KamAZ get-ins are long (MTVR driver walks up from ~250 u, KamAZ ~12 s): the game's own;
- bed gunners: pose faces his target by turning the whole man; no pitch (fine for ground targets);
- truck handling (KamAZ 6500 kg, MTVR 9000 kg: torque scaled by hand).

Earlier:
1. Player seat height (pods put 18 over the low CoD seat tags in the cab, 2 over the bed tags): only for players;
   soldiers will use the CoD clips (Stage 2).
2. Handling (pickup defaults from Glide's Insurgent), wheel / suspension fit, collision boxes.
3. Steering wheel doesn't turn yet; doors don't open for players (Stage 3 opens them for soldiers).

---

## Change log
- 2026-11-14 (user: tinting causes texture issues, disable on all): the 8 paint materials no longer tint (no `` / PlayerColor proxy); `TIF_MW_CARS_TINT = false` skips the random paint and makes `GetPlayerColor` white (DTW side paints do nothing on MW cars); `car_build.py` `TINT = False`. Cars show CoD's own finish.
- 2026-11-13 (TIF 0.27.0): user: armoured RAM's doors "kinda strange" -> the plain RAM's door curves; the big truck's
  armour and the plain RAM's interior tinted -> the armoured RAM keeps its own finish, and paint triangles that face
  inside the car (voxel flood fill from outside; inner door skins, jambs, hood underside) use an untinted copy.
  Seven more cars (table above), bed gunners, the RideThink hook, DTW switched to MW cars. Collision boxes: whole
  units and meeting at their slab boundaries (studiomdl split some cars' boxes into flat pieces otherwise).
  231 seat clips built (manifest family "car"); `harness/car_seat_harness.py` checks every car's seats against them
  plus the gunner turn / fire / settle: all pass. Not run in game.
- 2026-11-13 (TIF 0.26.0): AI seat clips for both RAMs (user: "both lack enter and exit anims for ai ... the biggest
  issue"): `car_seat_data.py`, manifest family `car` (102 roles, built), `hold` build option, base change as named in
  "Stage 2 + 3 as built", doors swung client-side from the `_geo_door` curves. Offline check
  `harness/car_seat_harness.py` 77/77.
- 2026-11-13: tint (user: hit the up-armour's windows, missed the back of the regular RAM): the brightness mask is
  replaced by CoD's own paint mask (slot 0x1E); the bed / back material is now painted too; the armoured RAM tints its
  body and keeps its plates and glass. Both RAMs rebuilt.
- 2026-11-13: still missing from the spawn menu (user). Glide's code lists "TIF MW" correctly as far as can be read
  offline, so the addon now also adds its own "TIF MW Cars" node to the Vehicles tab and a `tif_mw_car` command; car
  classes are `Spawnable` server-side only (Glide's own convention). Not yet confirmed in game.
- 2026-11-13: cars missing from the spawn menu (user): Glide lists only categories registered in
  `list.Set("GlideCategories", id, { name, icon })` (glide/client/spawn_tab.lua); "TIF MW" registered in the
  autorun. Spawn tab: Vehicles -> Glide -> TIF MW.
- 2026-11-13: Stage 1 started: `car_build.py`, `mat_info.py` (in `K:\jimmyproject\tif_air`); new addon `tif_mw_cars`
  (RAM 1500, RAM 1500 armoured). No TIF or DTW file touched.
