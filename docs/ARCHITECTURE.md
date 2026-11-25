# Tactical Infantry Framework (TIF): Resource Inspection and Architecture Proposal

Status: **proposal only. No framework code exists yet.** Written 2026-11-06 after inspecting the five addons in this folder.

Lua namespace: `TIF`. Console prefix: `tif_`. Addon folder: `addons/tactical_infantry_framework`.

---

## 1. Summary

- **Animation:** Grand Theft GMod (GTG 0.98.1) is a full GTA V animation library: 6,576 male clips (same again for female), each with root-motion curves, foot-plant frames and GTA event tags. It includes the full GTA cover system, rifle aim/fire/reload sets, crouch-aim strafing, vehicle enter/exit/seat sets for every seat, and directional get-ups. The clips only play on GTG's GTA-skeleton ped (`mp_m_freemode_01`). GTG already has a retargeter that lets a normal ValveBiped model "wear" those animations. NPCs can use this approach too.
- **Prone:** the wOS prone mod is a ValveBiped animation pack (`male_postures.mdl`) that lives on a **different skeleton** from GTG. Prone therefore needs special handling (§4.3).
- **Vehicles:** Glide is the vehicle base. An NPC can drive a Glide car without modifying Glide: car controls are read from seat 1's input table whether or not a player sits there. Seats are `prop_vehicle_prisoner_pod`s, which only players can occupy, so NPC passengers are parented to seat positions instead.
- **GTG Glide cars** include per-seat entry data (stand point, door bone and hinge, GTA anim dictionary), so NPCs can board and dismount with real GTA door animations.
- **Decent Vehicle (DV)** provides a per-map road waypoint graph and A* routing. It cannot drive Glide cars (it supports Simfphys, LVS, SCAR and Source vehicles). TIF uses DV only for roads and routes, with its own Glide driver. If a map has no DV waypoints, TIF falls back to detecting roads from ground textures (§4.8).
- **Gaps in the resources:** no on-foot hit reactions, no on-foot deaths, no hand signals or squad gestures, no wounded-drag animations, no prone firing animations, no voice lines, and no military NPC models installed. Each gap has a fallback below. None blocks Phase 1.

---

## 2. Resource inventory

### 2.1 Grand Theft GMod (`grandtheftgmod_0_98_1_3824259874`)

**How it is built**
- Characters: `models/grandtheftgmod/peds/mp_m_freemode_01.mdl` (81 bones, GTA skeleton) and `mp_f_freemode_01`. The ped `$includemodel`s `anims/male_move.mdl`, which includes `male_guns`, `male_heavy`, `male_vehicle`, `male_phone`, `male_para`, `male_items`, `male_drunk` and `male_crouch`. One ped model therefore reaches about 6,500 sequences.
- Clip metadata lives in Lua (`lua/grandtheftgmod/clips/lib_male_*.lua`) through `GTG.RegisterClips(pack, clips, meta)`. Each clip has `seq` (sequence name), `from` (GTA dictionary), `dur`, `frames`, `loop`, `move` (total root displacement x, y, yaw), `curve` (root motion per sample), `speed`, `tags` (Foot, MoveEvent, etc.) and `lplant`/`rplant` (foot-plant frames).
- Lookup API: `GTG.Characters[id]`, `GTG.Clips[char.clips][clipName]`, `GTG.ClipCurve`, `GTG.ClipPhase`, `GTG.ClipFrameForPhase`, `GTG.ClipTagPhase` and `GTG.ClipInTag`.
- Playback (players only): `sh_loco.lua` composes a weighted list of clips each frame and pushes it into the engine through `AddVCDSequenceToGestureSlot` and `AnimSetGestureWeight`. These are **Player-only** calls. The movement controller (`sh_motion.lua`, `sh_cover.lua`) is built on `SetupMove`, so it is player-only too.
- Retargeting (`playermodel/*`): `PMS.MapFor(leaderModel, followerModel)` builds a bone map from a GTA ped to any ValveBiped model, and `PMS.Solve(ent, map, ik, origin)` poses the follower each frame inside a `BuildBonePositions` callback. This code is **model-based, not player-based**, so NPCs can reuse it. The player wrapper (`cl_main.lua`) is not reusable as is. TIF needs its own small NPC wrapper.
- Weapons: every GTG gun (and its M9K shims) has a `SWEP.GTG` table with aim clips (low/med/high plus pitch range), intro/settle, fire clips, reload clip and time, cover set prefix (`cw2_`), damage, rate, range, falloff, spread, head/limb multipliers and sound. **TIF reads this table as its weapon data** and fires bullets itself, so the SWEP code doesn't need to run on NPCs.
- Units: `GTG.Data.U = 39.3701` (1 GTA metre in Hammer units).

**Clips relevant to this project (male; female mirrors them)**

| Need | Available | Examples |
|---|---|---|
| Cover enter/exit | Yes, high and low, left and right, by approach angle | `cov2_enter_high_l_0-5m_00`, `cov2_enter_low_r_faceleft`, `cov2_exit_*` |
| Cover idle/peek | Yes | `cov2_high_idle_l`, `cov2_low_idle_r_peek` |
| Cover shuffle and turn | Yes | `cov2_high_walk_l`, `cov2_*_step`, `cov2_*_settle`, `cov2_high_turn_l_*`, `cov2_*_cturn_*_90` |
| Corner pop-out aim | Yes (short and long lean) | `cw2_intro_hi_l_corner_long`, `cwc_hi_l_corner_covertoshort`, `cw2_outro_*` |
| Over-the-top aim (low cover) | Yes | `cw2_intro_low_l_centre_long`, `cw2_intro_low_r_direct_100` |
| Blindfire | Yes, high and low, with edge variants | `cw2_blindfire_low_l_aim_med_edge` |
| Switch sides / cover-to-cover | Yes | `cov2_high_l_to_high_r`, `cov2_low_l_to_high_r`, `cov2_break_high_l` |
| Cover reload, grenade | Yes | `cw2_high_reload`, `cw2_low_reload`, `cwgr_hi_l_throw_long` |
| Rifle stand aim/fire/reload | Yes, several hold sets | `wcr_*`, `war_*`, `wsm_*` |
| Crouch aim strafe | Yes, 8 directions | `crouch_mstg_walk_fwd_45_loop` |
| Walk/run/sprint, idle turns, starts/stops | Yes | `move_m@generic`, `move_strafe@generic`, `move_action@generic@core` |
| Stealth/tactical walk | Yes | `move_stealth@generic@core`, `gtg_stealth_*` |
| Idle fidgets / look around | Yes | `idlev_p0_fidget_look_around`, `idlev_mp_idle_a` |
| Vehicle enter/exit (driver and passengers) | Yes, including combat variants | `veh_std_ps_enter_exit_get_in_combat`, `*_jump_out`, `*_get_out_to_run`, `*_dead_fall_out` |
| Vehicle seated idle/lean/die | Yes | `veh_std_rps_sit`, `veh_std_ps_lean_left_idle`, `veh_std_ps_die` |
| Get-up from ground | Yes, directional, normal and injured | `getup_ts_front`, `getup_tki_back` |
| Climb/vault | Yes | `move_climb` |
| **On-foot hit reactions / stagger** | **No** | Fallback: additive procedural flinch, see §4.2 |
| **On-foot deaths** | **No** | GTG uses ragdolls. TIF does the same (blend into ragdoll) |
| **Hand signals / squad gestures** | **No** (only melee taunts) | Fallback: look-at + head turn + short idle. Add a gesture pack later |
| **Drag wounded** | **No** | Defer. "Protect casualty" behaviour still works without it |
| **Prone** | **No** in GTG (get-up only) | Use wOS prone, §4.3 |

The full male clip list is cataloged (6,576 rows) and will be regenerated by a TIF dev command rather than kept by hand.

### 2.2 Prone Mod (`the_prone_mod_1100368137`)

> Update 2026-11-06: the wOS version below turned out to need the separate wOS animation extension (its model files only include `models/player/wiltos/anim_extension_prone.mdl`). It was replaced by the standalone Prone Mod, which ships that file plus replacement `m_anm.mdl`/`f_anm.mdl`/`z_anm.mdl`, so any model that includes the standard player animations gets prone. Same Lua and sequence names. It also has a 9-way prone aim set (`prone_down_left` … `prone_up_right`) and `prone_base_layer`/`prone_pelvis_layer`, so §4.3's prone aiming can use real aim poses instead of a recoil kick only. Notes from the original inspection:

- Animations: `models/humans/male_postures.mdl` (97 seq) and `female_postures.mdl`, both ValveBiped. `police_ss.mdl` too.
- Sequences used: `pronedown_stand`, `proneup_stand`, `pronedown_crouch`, `proneup_crouch`, and idle/move by holdtype (`prone_ar2`, `prone_walktwohand`, `prone_smg1`, …).
- Logic is entirely player-based (`SetupMove`, `CalcMainActivity`, NW2 vars on the player). TIF reuses **only the sequences and the holdtype table** (`prone.Animations.WeaponAnims`).
- No prone firing animations ("there are no moving and shooting animations while prone"). The idle holdtype pose is used for prone aiming, with a muzzle-flash/recoil kick only.

### 2.3 Glide (`glide_styled_s_vehicle_base_3389728250`)

- Bases: `base_glide`, `_car`, `_tank`, `_motorcycle`, `_boat`, `_heli`, `_plane`, `_aircraft`. Military-relevant stock vehicles: `gtav_insurgent` (with turret), `gtav_rhino`, `gtav_speedo`, `gtav_police_cruiser`, `gtav_blazer`, `gtav_hauler`.
- **Driving:** `ENT:SetInputFloat(1, "accelerate"|"brake"|"steer", v)` and `ENT:SetInputBool(1, "handbrake", b)`. `sv_engine.lua` and `base_glide_car/init.lua` read seat 1 inputs with no driver check. Engine: `ENT:TurnOn()` / `TurnOff()`. Auto-on only happens in `OnDriverEnter` (players), so TIF calls `TurnOn()` itself.
- **Seats:** `ENT.seats[i]` are pods (`CreateSeat(offset, angle, exitPos)`), with `seat.GlideExitPos`. `GetFreeSeat()` and `GetClosestAvailableSeat()` only know about players. TIF keeps its own NPC occupancy table and blocks players from entering an NPC-occupied seat with the `Glide_CanEnterVehicle` hook.
- **Health and destruction:** network vars `ChassisHealth`, `EngineHealth`, `IsEngineOnFire`. `ENT:Explode()` sets `hasExploded` and damages players only, so TIF kills or ejects its own occupants. Vehicle usability = `not hasExploded and ChassisHealth > 0 and EngineHealth > 0` plus a water check (`GetWaterState`).
- Hooks TIF uses: `Glide_CanEnterVehicle`, `Glide_OnEnterVehicle`, `Glide_OnExitVehicle`, `Glide_CanSwitchSeat`, and `EntityRemoved` for cleanup.
- Turrets (`glide_vehicle_turret`, Insurgent gunner) are player-input driven. NPC gunners are Phase 6+ and need a closer read of the turret input path before committing.

### 2.4 GTG Glide cars (`grandtheftgmod_glide_cars_3825412299`)

- Eight GTA cars on `base_glide_car` (`baller2`, `kuruma`, `rebel2`, …). `ENT.GTGData.seats` has pod position, exit, `gta_seat` and pelvis offset. `ENT.GTGData.entries` has seat, `stand` point, `face`, `side`, door bone, hinge axis and limits, handle, and `enter`/`exit`/`common` GTA dictionaries.
- GTG's `GTG.VehicleEntry` (`VE.Entries`, `VE.Sets`, `VE.Plan`, `VE.Pose`, `VE.Door`) already turns this into a timed enter/exit plan with door animation. It is player-driven, but the planning functions take plain data and can be called for NPCs.
- Cars without `GTGData` (stock Glide) get a generic fallback: seat 1 = `veh@std@ds`, seat 2 = `ps`, seat 3 = `rds`, seat 4 = `rps`, stand point = `seat.GlideExitPos`, no door animation.

### 2.5 Decent Vehicle (`dv_decent_vehicle_basic_ai_1587455087`)

- Global `dvd`. `dvd.Waypoints[i] = { Target = Vector, Neighbors = {ids}, SpeedLimit, TrafficLight, Group, WaitUntilNext, UseTurnLights, FuelStation }`.
- `dvd.GetRoute(startId, {[endId]=true}, group)` is A* with a turn-angle cost. `dvd.GetRouteVector(startPos, endPos|{...}, group)` is the convenience wrapper. `dvd.GetNearestWaypoint(pos)` is a **linear scan**, so TIF builds its own spatial grid over `dvd.Waypoints` for nearest-lookups.
- Saved per map in `data/decentvehicle/<map>.txt` (compressed JSON), authored with the `dv_route` tool. Its "generate" button builds waypoints from the map's **AI nodegraph** ground nodes, not from roads, so generated waypoints are not lanes.
- Hook: `Decent Vehicle: OnLoadWaypoints`. TIF rebuilds its grid there.
- Driving: DV's own `npc_decentvehicle` doesn't support Glide. **TIF does not spawn DV drivers.** It reads DV's graph only. DV is an optional dependency.

### 2.6 NPC models and weapons

- No military NPC or player models are installed. The retargeter needs a **ValveBiped** skeleton, and wOS prone needs the model to reach `humans/male_postures.mdl` through its include chain. Both must be checked per model; TIF will include a model checker command.
- Weapons: GTG guns (`weapon_gtg_*`) and GTG's M9K shims (`weapon_gtg_m9k_*`). Other weapon bases (ARC9, TFA, M9K proper) can be used through a small mapping table to a GTG hold set (`2h`, `1h`, `mini`, …) plus stats.
- Sounds: GTG ships weapon and effect audio only. **There are no voice lines.** The communications system is built with an event → voice-set table so you can drop in a voice pack later.

---

## 3. Engine limitations and risks

These are checked first, in Phase 0, because several decisions depend on them.

| # | Risk | Why it matters | How it will be verified | Fallback |
|---|---|---|---|---|
| R1 | **Overlay-layer sequence index bits.** Source networks layer sequence numbers with a limited bit count (12 bits / 4,095 in stock Source 2013; GMod's value unverified). The ped reaches ~6,500 sequences. | If the server sets layers with indexes above the limit, clients play the wrong animation. | Spawn a test NextBot, put sequence #6000 on a server layer, and compare client `GetLayerSequence`. | **Preferred design anyway:** the server sends a compact *animation intent* and each client composes the blend itself, as GTG does for players. The server runs a reduced pose for hitboxes. |
| R2 | **Overlay layer count.** NextBots have about 15 layers. GTG blends up to 8 + 2 upper-body slots. | Budget. | Count in the spike. | Cap per-NPC blends at 6 layers; drop the lowest weights. |
| R3 | **Client cost of retargeting.** `PMS.Solve` runs per follower per frame. 50 NPCs = 50 solves. | Client FPS. | Profile 10/25/50 followers. | Distance LOD: solve at 30/15/5 Hz by distance, skip when not drawn, and use the bare GTA ped (no follower) beyond a cutoff. |
| R4 | **Two skeletons for prone.** | Prone animations can't play on the GTA ped. | Spike in Phase 2. | §4.3 |
| R5 | **Glide engine with no driver.** Inputs are read without a driver check, but some engine/transmission paths may still assume a player (lights, auto-off). | NPC driving. | Phase 0 spike: spawn `gtav_insurgent`, call `TurnOn()`, set throttle and steer from a timer. | Wrap any player-only call. Glide itself is never edited. |
| R6 | **Navmesh dependency.** NextBot pathing needs a navmesh (`nav_generate`). Many workshop maps ship without one. | Movement. | Detect at load and warn on screen. | Generate in-game. Debug menu has a one-click "generate nav" with a warning. |
| R7 | **Lua trace and path budget.** `util.TraceLine` is cheap; `TraceHull` and `PathFollower:Compute` are not. 50 NPCs each tracing every tick is not viable. | Server tick. | Built-in profiler (§4.12). | Central scheduler with per-tick budgets (§4.11). |
| R8 | **GTG version coupling.** TIF calls GTG internals (`GTG.Clips`, `PMS.*`, `VE.*`). GTG updates could rename them. | Breakage on update. | Startup self-test checks every GTG symbol TIF uses. | All GTG access goes through one adapter file (`tif/compat/gtg.lua`), so a GTG update is fixed in one place. |

Other Source limits taken into account: no reliable "door open" state across door classes (handled per class); `prop_door_rotating` blocks nav until opened; bullets don't report near misses (TIF does its own near-miss check from `EntityFireBullets`); NPCs can't be in pods (handled by parenting).

---

## 4. Architecture

```
tif/
  sh_init.lua          load order, config, version, self-test
  compat/              gtg.lua, prone.lua, glide.lua, dv.lua  (only place 3rd-party symbols are used)
  core/                scheduler, profiler, events (bus), factions, util (spatial grid, budgets)
  npc/                 entity (base_nextbot), body (anim intent), locomotion, weapon, health/ragdoll
  perception/          sight, hearing, knowledge (contacts)
  brain/               utility actions, archetypes, awareness state
  tactics/             cover, suppression, flanking, search/containment
  squad/               squad, orders, formations, roles, comms
  building/            doorways, stacks, room clearing
  vehicle/             adapter, occupancy, driver, routes (dv / roads / authored), dismount
  encounter/           areas (bases, patrols, guard posts), reinforcements
  debug/               cl overlays, dev menu, test spawners, benchmarks
  config/              factions/*.lua, archetypes/*.lua, voices/*.lua, models/*.lua
```

### 4.1 The NPC entity

- `tif_soldier` is a **NextBot** (`base_nextbot`). NextBots give direct control over locomotion, pathing (`PathFollower`), a coroutine behaviour loop, and full animation-layer control. Scripted `ai`-type NPCs are tied to the HL2 schedule system and default activities, which is what this project is replacing.
- Server-side model = GTG ped (`mp_m_freemode_01` or the female). Hitboxes follow the GTA skeleton, which is accurate because the animations are authored for it.
- Visual model = any ValveBiped military model, drawn client-side through the PMS retargeter (§4.2). With no model configured, the GTA ped itself is drawn (a useful debug view).
- Weapon: the world model is attached to the GTA right-hand bone using the weapon's `GTG.hand` offset. Firing uses `self:FireBullets` with stats from `SWEP.GTG`.
- Health: per-hitgroup multipliers (`head`, `limb` from the weapon). Death → ragdoll of the *visual* model posed from the last frame (GTG's `R.PosedCopy` approach), velocity from the hit.

### 4.2 Animation system

> Phase 0 outcome (2026-11-06, see STATUS.md "Phase 0 decisions"): the client composes animation by writing the main sequence and 8 server-created layer slots on the NextBot every frame. Every sequence index networks fine as the main sequence. Server-set layers are not relied on, because some entities received no layer data. The design below stands; the "server plays a reduced version" part means main sequence only.

**Split.** The server decides *what* the soldier is doing. The client decides *how it looks*.

- Server → client: a compact **intent** per NPC, sent as network vars only when it changes: `stance` (stand/crouch/prone/cover/seat), `clip` (an id from a TIF clip table, ≤ 2,048 entries, so no raw sequence indexes are sent; this avoids R1), `t0` (start time), `aim` yaw/pitch, `cover` (side, height, edge), and flags (firing, reloading, suppressed).
- Client: composes the blend from the intent, the same way GTG does for players: locomotion blend by speed and direction, upper-body aim pitch blend (low/med/high from the weapon table), fire and reload overlays, transitions crossfaded using clip durations. It then runs the retarget onto the visual model.
- Server: plays a **reduced** version (main sequence + aim layer) so hitboxes roughly match. Layers use server-only sequence indexes that are never networked, so R1 doesn't apply.

**Clip registry (`TIF.Anim`).** Built at load from `GTG.Clips`. It maps TIF actions to concrete clips per weapon hold, e.g. `cover.enter{height, side, approachAngle}` picks the best `cov2_enter_*` the same way GTG's `cover_find` does (smallest turn error after scaling). Each entry stores root motion, duration and foot plants. Missing clips fall back down a chain (rifle → generic → core), and the fallback is logged once.

**Root motion.** Transitions with displacement (cover enter/exit, cover-to-cover, turn-in-place, vehicle get-out) **drive the NPC's position from the clip curve** instead of letting locomotion slide the body. This stops foot sliding and is the main reason the GTA anims will look right.

**Avoiding restarts.** An intent change that maps to the same clip keeps its phase. Looping clips resume on the matching foot-plant phase (`GTG.ClipPhase`) when switching between walk, run and strafe.

**Fallbacks for missing categories.**
- Hit reaction: an additive procedural flinch on spine/head bones scaled by damage direction, applied in the client bone callback. Heavy hits (explosives, vehicle) → short ragdoll → directional `getup_*` clip, which GTG already supports.
- Hand signals: turn head and torso to the teammate, hold 0.6 s, and play a voice line if one is configured. A `gesture` slot is reserved for a future pack.

### 4.3 Prone

The prone animations are ValveBiped; the server ped is GTA. Plan:

1. **Client:** when `stance == prone`, the visual model stops following the GTA ped and plays the wOS sequence directly on itself (`pronedown_stand` → `prone_ar2`/`prone_walktwohand` → `proneup_stand`), parented at the NPC origin with the NPC's yaw. This works because the visual model is ValveBiped and (if its include chain reaches `male_postures.mdl`) has those sequences.
2. **Server:** the GTA ped holds the first frame of `getup_tk_front` (a face-down pose) so hitboxes are low and roughly correct. The hull shrinks to wOS's `HullHeight` (24).
3. **Aiming while prone:** the idle holdtype pose plus body pitch; yaw limited to ±40° (larger turns are a short shuffle), recoil kick only. No moving fire, matching the wOS limitation.
4. Models whose include chain doesn't reach `male_postures` fall back to "crouch behind low cover" and the model checker reports it.

This is the riskiest animation item and gets its own spike at the start of Phase 2. If the visual hand-off looks bad, the alternative is to retarget prone ValveBiped → GTA (the reverse of PMS), which is more work.

### 4.4 Movement

- NavMesh path via `PathFollower`, with a **custom cost function** that adds exposure cost for areas visible to known contacts (from a cached per-area visibility sample, not live traces).
- Speeds come from the character definition (`walk 68.5`, `run 185.9`, `sprint 277.9`) and are matched to clip ground speed so feet don't slide.
- Path requests go through the scheduler (§4.11): a path is recomputed only when the goal moves more than a threshold, a blocked check fails, or an order changes. Failed goals are remembered for 10 s so NPCs don't keep retrying impossible routes.
- Local avoidance: simple separation between soldiers in the same squad, plus 2 forward hull probes per second.

### 4.5 Perception and knowledge

- **Sight:** FOV cone (configurable per archetype), distance bands, a stance/movement/lighting factor (the server can't read light levels cheaply, so darkness comes from per-area "dark" flags set in config or the debug menu, plus the target's flashlight state), and 2 rays (head and chest). Detection builds over time in a meter instead of being instant. Sight checks are budgeted, and each soldier checks at most one candidate per think.
- **Hearing:** `EntityFireBullets` (gunfire, suppressed weapons quieter), `EntityEmitSound` (footsteps by speed, explosions, doors), and a TIF event bus for custom sounds. Each event has a loudness radius; soldiers in range get a *stimulus* (position + uncertainty), not the source entity.
- **Knowledge (`Contact`):** `{ ent, pos, vel, seenAt, heardAt, confidence, source (self/squad/radio), lastDir }`. Positions are only updated by an actual sighting or sound. When sight is lost, `pos` is frozen and `lastDir` is kept, and uncertainty grows with time × the target's last speed. Soldiers never read the true position of a contact they can't perceive. This is what makes breaking contact possible.
- **Sharing:** soldiers report contacts to their squad (instantly, if in voice range or with a radio flag); squads report to the area (a base or encounter) with a delay. Shared reports carry their own uncertainty.

### 4.6 Decision making

Two layers, so each soldier acts on its own but within a coordinated plan.

1. **Squad brain** (≈ 2 Hz while engaged, 0.2 Hz while idle): a state machine over orders: `patrol`, `guard`, `hold`, `defend`, `advance` (bounding overwatch), `suppress`, `flank`, `regroup`, `retreat`, `search`, `contain`, `stack`, `clear`, `mount`, `dismount`. Each order assigns roles to members (e.g. flank = 2 movers + rest base-of-fire).
2. **Soldier utility AI** (staggered, 1 to 10 Hz by tier): scores a small set of actions inside the current order: *take cover, shoot from cover, reposition, reload, move to order point, investigate stimulus, throw grenade, go prone, return to duty*. Scores use the soldier's knowledge, suppression, health, ammo, archetype weights and the squad order. **Hysteresis and minimum commit times** stop flip-flopping between actions.

Archetypes (rifleman, assault, support, marksman, leader, guard, breacher) are **config tables of weights and parameters** on the same code, not separate classes.

### 4.7 Cover

**Finding cover points (on demand, cached).** Cover points aren't hand-placed and there is no whole-map precompute. When a soldier needs cover:

1. Gather nav areas within radius R of the desired region (squad order point, or the soldier itself).
2. Sample candidate points along area edges that border obstacles (nav "blocked" sides) and around props/vehicles found with `ents.FindInBox`, filtered by class: `prop_physics` above a size threshold, Glide vehicles, `func_brush` walls.
3. Classify each candidate with GTG's probe logic: waist trace into the obstacle (`cover_probe`), head trace → **high** or **low**, sideways edge traces → **left/right edge** (corner). This gives the cover *kind* that selects the animation set: high wall, low wall, high corner L/R, low edge L/R.
4. Tag the **material**: world brush, prop, or vehicle (`IsGlideVehicle`). Vehicles use the same GTA cover clips (GTA uses them on cars too), but the height comes from the vehicle's bounds and the point is dropped if the vehicle moves or explodes.
5. Cache points per nav area for 60 s (world) or until the prop moves.

**Scoring** (weights per archetype): protection from known threat directions (dot of cover normal vs. threat), whether the soldier can fire from it (edge or low = yes), distance from its order point, exposure on the path there, distance from friendly soldiers (spacing), preferred engagement range, and "was compromised recently" (flanked or fired on from an unprotected side).

**Reservations.** `TIF.Cover.Reserve(point, npc, ttl)`: one soldier per point, plus a 40-unit exclusion radius. Released on death, removal, order change or timeout. The debug overlay shows free/reserved/occupied.

**Cover behaviour loop** (the GTA cover state machine, run by the soldier): approach → `enter` clip chosen by approach angle → idle (high/low, side) → peek → pop-out aim (`intro … corner_long/short` or `low_centre`) → fire bursts → `outro` → idle. Side change uses `*_l_to_*_r`. Reload uses the cover reload clip. Blindfire is for suppressed and low-morale soldiers. Breaking cover uses `break_*` / `exit_*`.

### 4.8 Vehicles

**Adapter interface** (`TIF.Vehicle.Adapter`), so other bases can be added later without touching the AI:

```
adapter:IsUsable(veh)               -- not exploded, health > 0, upright, not deep water
adapter:Seats(veh)                  -- { index, role = driver|passenger|gunner, standPos, face, dict, door }
adapter:Occupy(veh, seat, npc) / Vacate(...)
adapter:Drive(veh, throttle, steer, brake, handbrake)
adapter:StartEngine(veh)
adapter:Speed(veh), Forward(veh)
```

The Glide adapter implements this with `SetInputFloat(1, …)`, `TurnOn`, `seats[i]`, `GTGData.entries` (or the generic fallback) and the hooks in §2.3.

**Occupants.** An NPC in a vehicle is parented to the seat pod position, plays the seat clip (`veh_std_ps_sit`, lean and brake reactions from vehicle acceleration), stays non-solid, and has its hitboxes kept. A player trying to enter an NPC-held seat is refused. On vehicle explosion, occupants die (or the dead fall-out clip plays). On heavy damage they bail with `jump_out`.

**Boarding and dismount.** Uses the GTA enter/exit plans (`VE.Plan`) when `GTGData` exists. Otherwise: walk to `GlideExitPos`, play `get_in`/`get_out`, snap to the seat.

**Combat dismount (the MW-style pickup scene).**
1. The squad leader gets a `dismount_at` point (authored, or "near the contact").
2. The driver slows on approach (speed is a function of distance), brakes, and angles the vehicle so its side faces the threat when the road allows. The vehicle then counts as cover.
3. Passengers are released in a stagger (0.2–0.5 s each) using `get_out_to_run` / combat variants on the side *away* from the threat when possible.
4. Each passenger already holds a cover reservation chosen before the vehicle stopped (the cover search runs during the last ~5 s of approach), so they spread out instead of following each other.
5. Roles on landing: support → base of fire; assault → flank; others → nearest good cover. The driver follows the archetype config: stay and reposition, or dismount.

**Driving and routes (the driver controller).**
- Steering: pure-pursuit on a path polyline, speed from curvature and speed limit, with an obstacle hull probe ahead of the vehicle (brake or steer around). Stuck detection triggers reverse-and-retry.
- **Route source tiers** (first one available wins):
  1. **Authored routes:** placed with the TIF route tool (patrol loops, approach routes, dismount points). Most reliable; recommended for encounters.
  2. **Decent Vehicle graph:** if `dvd.Waypoints` has entries for this map, routes come from `dvd.GetRoute`. TIF keeps its own spatial grid for nearest-waypoint lookups and respects `SpeedLimit` and directed `Neighbors` (lanes).
  3. **Road detection from ground textures:** for maps with neither. See below.
  4. **Direct:** straight-line drive with obstacle avoidance, short hops only (< 1,500 units), e.g. the final approach to a dismount point off-road.

**Road detection (tier 3).** Run once per map on demand (`tif_roads_build`), cached in `data/tif/roads/<map>.json`, spread across ticks.
1. Walk the navmesh (it exists anyway for infantry). For each area, trace down at its centre and corners and read `tr.HitTexture` and `tr.MatType`.
2. Classify as road when the texture name matches configurable patterns (`road`, `asphalt`, `tarmac`, `street`, `highway`, `pavement`, `dirtroad`, `concrete/.*road`, …) or the map's own texture list in `config/roads/<map>.lua`. Concrete and dirt count as "drivable but not road" (higher cost). Displacements report their blend material and are handled the same way.
3. Merge connected road areas into a graph. Edges are kept only where a vehicle-width hull trace passes (so sidewalks and narrow alleys that share road textures are dropped). Nodes are thinned to about one per 300 units along each road strip.
4. Route with A* using cost = length × surface factor (road 1, drivable 2.5, other: not allowed).
5. The debug overlay draws the classified areas so you can see what was detected and fix patterns per map.

This won't be perfect on every map (texture names are up to the mapper), which is why it is tier 3, why patterns are per-map overridable, and why authored routes win.

### 4.9 Squads, factions, communication

- **Factions:** `config/factions/*.lua`. A relation matrix (`ally`/`neutral`/`hostile`) that also covers players (by team, by a per-player override, or a "player faction" setting). Default GMod NPCs are mapped via `AddEntityRelationship` so HL2 NPCs react sensibly, but TIF never relies on dispositions internally.
- **Squads:** a leader, members with roles, shared knowledge, current order and formation (column, wedge, line, file for interiors). If the leader dies, a successor is chosen by role priority, morale takes a hit, and orders pause briefly.
- **Friendly AI with the player:** a "follow player" order in which the player acts as the squad's reference point. The squad keeps the formation offset, takes cover when the player does, and engages on its own. Simple commands come from a key menu (hold, follow, advance, suppress-at-crosshair, stack-on-door, regroup).
- **Communication:** an event → voice-set table (`contact`, `reloading`, `taking_fire`, `man_down`, `moving`, `grenade`, `flanking`, `clear`, `lost_contact`, …) with cooldowns per squad, so lines don't spam. Silent until voices are configured.

### 4.10 Buildings and door stacking

- **Doorway detection:** `prop_door_rotating` / `func_door_rotating` / `func_door` entities, plus open doorways found as nav connections that pass through a gap narrower than ~64 units with walls on both sides (two side traces). Each doorway stores its centre, normal (inside/outside, from which side has more indoor nav area or a ceiling trace), width and blocked flag.
- **Stack slots:** generated per doorway along the wall on each side (hinge side preferred), 32-unit spacing, validated by hull traces. Slots that are exposed to known threats or that are blocked are dropped. The doorway is marked unsuitable when fewer slots remain than the entry team needs.
- **Entry:** the leader assigns order (point, second, …). Members move to slots and hold weapon-ready poses (crouch-aim idle or `wcr_idle` with aim toward the door). When ready or forced (contact, timeout), the door is opened (`Fire("Open")` or `Use`), and members enter one at a time with a 0.4–0.7 s gap. Each takes an alternating corner sector (left/right buttonhook) using nav areas inside the room. Members already inside hold their sector while the rest flow in.
- **Adapting:** contact through the doorway → stack members engage from slots, entry pauses. A stack member down → order re-assigned. Door blocked or locked → fall back to another doorway or "contain".
- **Room clearing:** rooms = connected indoor nav areas between doorways (flood fill, stops at doorways). Clearing = every area seen by a squad member within the last N s. Then move on to the next doorway.

### 4.11 Performance

- **One scheduler** drives all TIF thinking from a single `Tick` hook. No per-NPC timers.
- **Tiers** (per soldier, recomputed every 1 s):

| Tier | Who | Brain rate | Sight checks | Path recompute |
|---|---|---|---|---|
| 0 Combat-near | engaged, < 2,500 u from a player | 10 Hz | every think | on demand |
| 1 Combat-far / alerted | engaged far, alerted, searching | 4 Hz | every 2nd think | ≥ 1 s apart |
| 2 Routine-near | patrol/guard within PVS of a player | 1 Hz | 1 Hz | ≥ 3 s apart |
| 3 Dormant | far from all players, unaware | 0.2 Hz, simplified (patrol by teleport-along-route when not in PVS) | none, hearing only | none |

- **Budgets per tick** (convars): max sight traces, max hull traces, max path computes, max cover searches. Work that exceeds the budget is queued for the next tick (round-robin, priority by tier).
- **Events over polling:** gunfire, damage, death, sound, squad reports and vehicle destroyed push work. Routine checks are cheap timers.
- **Shared work:** the squad does one cover search for all members. Contacts are shared, not re-detected. Nav visibility samples are cached per area.
- **Cleanup:** `OnRemove` / `EntityRemoved` / death release reservations, seats, stack slots and squad membership, and clear any references. Weak-keyed tables everywhere an entity is a key.

### 4.12 Debug and test tools (built alongside Phase 1, not at the end)

- `tif_debug <0|1>` plus per-channel convars (`tif_debug_state`, `_cover`, `_paths`, `_sight`, `_squad`, `_doors`, `_vehicles`, `_roads`, `_perf`). Overlay data is only networked to admins and only while a channel is on. Zero cost when off: no net messages and no hooks beyond one convar check.
- **Overlays:** state, order, target, awareness, suppression bars; last-known-position markers with uncertainty circles; paths; cover points coloured by kind/score/reservation, with the selection reason on hover; sight cones; hearing stimuli; patrol routes; stack slots with entry order; road classification.
- **Dev menu** (`tif_menu`, Q-menu tab): spawn one soldier / squad by role list / faction; place doorway → stack → enter; spawn Glide vehicle with N passengers → patrol route → combat dismount at crosshair; fake a contact at crosshair; force lose-contact; force search; force go-prone; set tier; freeze AI.
- **Profiler:** `TIF.Prof.Begin/End` around every system. `tif_perf` shows ms/tick per system, traces/paths per second, tier counts, NPC and squad counts, and the slowest calls of the last 10 s.
- **Benchmarks:** `tif_bench 10|25|50 [mix]` spawns a standard scene on the current map, records 60 s, and writes `data/tif/bench/<map>_<n>_<time>.txt`.

### 4.13 Configuration

Plain Lua tables in `lua/tif/config/` (shipped defaults) with overrides from `data/tif/config/*.json` (editable from the dev menu, persisted). Covers every item in spec §13: archetype, faction, aggression, accuracy, detection range, hearing, suppression resistance, speed, engagement range, patrol behaviour, squad membership, vehicle compatibility, voices, animation preferences, morale, reinforcement rules. A content API lets other addons register factions, archetypes, models and weapons: `TIF.RegisterFaction`, `TIF.RegisterArchetype`, `TIF.RegisterModel`, `TIF.RegisterWeapon`.

---

## 5. Development phases (revised)

Each phase ends with its test commands working and a benchmark run. Anything incomplete is listed in `STATUS.md`, never presented as done.

**Phase 0: Spikes (short, before any real systems).**
- R1/R2: layer sequence networking and count on a NextBot.
- R3: client retarget cost with 10/25/50 followers.
- R5: drive a Glide car from Lua with no player.
- The GTG adapter file plus a startup self-test of every GTG symbol used.
- Output: a short spike report with the decisions they force.

**Phase 1: Core.** NextBot soldier on the GTG ped, intent → client blend (locomotion + aim + fire + reload), retargeted visual model, weapon data from `SWEP.GTG`, navmesh movement with tactical cost, sight/hearing/knowledge, factions, basic engage-from-standing, death ragdoll, scheduler + profiler + debug overlays (state, sight, paths, perf), spawn tools.

**Phase 2: Tactical infantry.** Cover finder + classification + reservation + full GTA cover state machine; prone spike, then prone; suppression (near-miss detection, per-archetype response); repositioning; cover debug overlay.

**Phase 3: Squads.** Squad brain and orders, roles/archetypes, formations, shared knowledge, bounding overwatch, flanking, friendly squad following the player, player command menu.

**Phase 4: Bases and encounters.** Area definitions (bases, posts, patrol routes, towers), guard rotations, alert levels, reinforcement requests, search/containment/lose-contact/return-to-duty, encounter presets (compound defence, hospital-style defence).

**Phase 5: Buildings.** Doorway detection, stack slots, entry, room clearing, indoor formations.

**Phase 6: Vehicles.** Glide adapter, occupancy, boarding/dismount with GTA anims, driver controller, route tiers (authored → DV → roads → direct), vehicle patrols, combat dismount, vehicles as cover, bailing out.

**Phase 7: Advanced.** Morale, casualties (incapacitated state, protect casualty), communications/voices, dynamic reinforcements by vehicle, environmental extras.

---

## 6. Decisions needed from you

Answered 2026-11-06: enemy = DPR militia model with mercenary voices, ally = HECU PMC with BF3 Marine voices (see STATUS.md). Items 2 and 4 are still open.

1. **Military models.** Which NPC models should Phase 1 target? They need a ValveBiped skeleton. For prone, they also need `male_postures.mdl` reachable through their includes (the checker will tell us).
2. **Hard dependencies.** Proposed: GTG and Glide required; wOS prone and Decent Vehicle optional (features turn off with a notice).
3. **Voices.** Is there a voice pack you want to use? Otherwise communications ships silent with the table ready.
4. **Test map.** Which map should benchmarks and encounter presets be built on? It needs a navmesh, and ideally roads for the vehicle work.
