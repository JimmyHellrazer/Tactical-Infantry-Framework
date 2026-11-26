# Tactical Infantry Framework (TIF)

MW-style military AI for Garry's Mod: NextBot soldiers on a fully animated Modern Warfare (2019 / 2022) body that take
cover, move as squads, breach and clear buildings, take hostages, fight hand to hand and react to everything around
them.

Put `addon/` in `garrysmod/addons` (rename it `tactical_infantry_framework` if you like). That's all you need to test.

## Features

**The soldier**
- One fully animated body running over 4,200 Modern Warfare (2019 / 2022) animations: walks, runs, strafes, starts,
  stops and turns, stance changes, prone (diving in, crawling), wading, mantling and vaulting, opening doors on the way.
- Any ValveBiped player model can be a faction's look: it's bone-merged onto that body, so it gets every animation.
- 45 baked MW guns with MW sounds (fire, indoor / outdoor tails, reload foley), per-weapon reloads and recoil, sidearm
  switching, magazines that leave the gun, LMG bipods prone and on ledges.
- Hit reactions by body part, situational death animations (in cover, running, against walls, over ledges, burning,
  long crawling deaths, last stands) that hand over smoothly to ragdolls.
- Movement sounds: footsteps for every surface and gait, gear and cloth rattle, landings, body falls, for soldiers and
  civilians.

**Combat**
- Cover: corners (standing and crouched), low and chest-high walls. Directional arrivals, peeking, leaning out with a
  proper aim blend, blindfire under suppression, reloads, shuffling along walls, switching corners, and sometimes
  fighting from beside cover before palming back in.
- Suppression (pinned down, pushed into cover or flat on the ground), grenades over cover and in the open, flashbang
  reactions, dodging live grenades.
- Morale: losses, wounds and being outnumbered wear soldiers down. Shaken ones shoot worse and stop pushing, broken
  ones run and hide, and a squad that loses heart withdraws (`tif_morale`).
- Close quarters: rifle-butt strikes and paired melee fights between soldiers who end up face to face.
- Awareness: unaware / suspicious / searching / engaged, with MW's own reactions (startles, pointing out contacts,
  looking around after losing you).

**Squads**
- Formations, bounding overwatch, base of fire, flanking, withdrawing, regrouping on a new leader.
- Radio chatter and voice packs per faction (contact, suppressing, reloading, man down, grenade out...).
- Medics, casualties and revives.
- Command your own squad (`tif_menu`): follow, hold, advance, take cover, clear a building.

**Room clearing (CQB)**
- Squads stack on doors and breach them: opened by hand, kicked, sledgehammered, or cracked for a flashbang. Open
  doorways get two-man simultaneous entries. Flashbangs first, then room by room through the whole building.
- Kicked doors come off their hinges (area-portal safe), breachers line up on the door's centre, and the team holds
  fire and stays focused while it stacks.

**Human shields**
- Cornered enemies near civilians can grab one as a shield (an MW19 grab, or a hidden "Clean House" take with a
  pistol). Shoot the captor cleanly or the hostage pays; hold off too long and a friendly soldier takes the shot.

**World**
- Civilians: wander, talk, panic, flee, hide, wave others to safety; never targeted, and soldiers hold fire when one
  is in the line.
- Vehicles (Glide): driving, convoys, mounted guns, road networks from Decent Vehicle or the navmesh.
- Bases and garrisons you can build, save and populate.
- HL2 NPCs and tagged addon NextBots (e.g. horde zombies) are friends or enemies by side.
- Doors: soldiers open them instead of barging through (also stops destructible-door mods breaking them on a bump).

**Factions and modding**
- Two starter factions: **Insurgents** and **US Marines** (Insurgency 2 characters by MadIvan18), light / standard /
  heavy outfits, randomised gear, several voice packs each.
- Faction editor (`tif_factions`), camo variants, modular factions built from body / head / headgear parts.
- Content packs register factions and voices from their own addon; a server API (`TIF.API`) drives squads, room
  clears, garrisons, civilians, vehicles and shields from game modes. See `docs/WORKSHOP.md` (developer section).

**Under the hood**
- A log file (`garrysmod/data/tif/log_sv.txt`) with errors, CQB / shield / melee events and a watchdog for stuck
  states; `tif_mark` notes for bug reports; `tif_selftest` for the map and content.
- Client-side animation and sound: nothing extra over the network for footsteps or foley; LODs on the starter models.

## Testing

**Setup**
- The map needs a navmesh. If soldiers stand still, run `nav_generate` in the console (singleplayer) and reload.
- Test maps ship with it: `tif_cqb` (room clearing: doors, open doorways, a sledge door) and `tif_range` (open
  ground, a compound, a two-storey building).
- Optional: Glide (vehicles), Decent Vehicle (road waypoints).

**Spawning**
- Spawn menu > NPCs > `TIF - Insurgents` / `TIF - US Marines`: single roles and whole squads.
- `tif_menu`: order your own squad (follow, hold, advance, clear a building).
- Spawn menu > Utilities > Tactical Infantry (`tif_settings`): settings and quick actions.

**What to look at**
1. Room clearing on `tif_cqb`: stacks, kicks / opens / sledge / grenade breaches, everyone getting in, nobody
   shuffling back and forth at the door.
2. Close fights: two enemies face to face start a paired melee fight; the loser's body falls from the fight pose.
3. Human shields near civilians.
4. Cover fights, grenades, flashbangs, prone, bipods.
5. Footsteps, gear and body-fall sounds on different surfaces.
6. The starter factions' look: outfits, gear, faces, arms; their ragdolls.

**Reporting a bug**
1. The moment it happens, open the console and type `tif_mark what you saw` (e.g. `tif_mark guy stuck at door`).
2. Send `garrysmod/data/tif/log_sv.txt` (and a screenshot or clip). The mark records what every soldier near you was
   doing.

## Repository layout

| Folder | What's in it |
|---|---|
| `addon/` | The addon, ready to drop into `garrysmod/addons`. |
| `build/` | Sources the tools build from: `ins2/` the starter factions' meshes + QCs (per model), `rig/` TIF's host skeleton as a rig (`rig_tifhost.qci`, reference pose), `maps/` the test maps' VMFs and build scripts. |
| `tools/` | Build scripts (see below), `harness/` the offline test suites, `gunbake_addon/` the gun exporter, `devtools_addon/` debug overlays and test commands (local only, never shipped). |
| `docs/` | Design and status notes: `STATUS.md` (every change), `READINESS.md` (Workshop planner), `ARCHITECTURE.md`, `WORKSHOP.md`, ... |
| `media/` | Screenshots and Workshop images. |

**Tools** (written for one machine: paths inside point at `K:\`; edit the constants at the top of each script)

| Script | Builds |
|---|---|
| `tools/anims/tif_mw_build.py` + `manifest.py` | The soldier body's MW19 / MW22 animations (`python tif_mw_build.py manifest.py --compile [--only <pattern>]`). `shield_frames.py`: human-shield scene placement. `foley_pack.py`: the movement sounds from an MW19 foley rip. |
| `tools/guns/` | The baked MW guns: `gun_compile.py`, `gun_holds.py` (hand holds / gun bone), `gun_tune.py`, `gun_textures.py`, `gun_decimate.py`, `batch.py`. |
| `tools/props/` | Hand props for animations (the breach sledgehammer). |
| `tools/air/` | Reinforcement helicopters and MW cars (companion addons). |
| `tools/factions/make_ins2.py` | The starter factions: Insurgency 2 characters rebuilt on TIF's own ValveBiped skeleton (needs codport). `vvd_headfix.py`: moves vertices left on a model's root bone onto the head. |
| `tools/harness/` | Offline Lua tests (LuaJIT via `lupa`): `python run.py <suite>.lua`. `run.py` points at the addon's `lua/` folder. |
| `tools/sync_addon.ps1` | Refreshes `docs/` from the design notes folder. (On the dev machine `garrysmod/addons/tactical_infantry_framework` is a junction to `addon/`, so the addon itself needs no syncing.) |

## Credits

- Animations and sounds: Call of Duty: Modern Warfare (2019 / 2022). Fan project, not affiliated with Activision or
  Infinity Ward.
- Starter faction characters: Insurgency 2 models by MadIvan18, used with permission.
- Voices: TFA-VOX Insurgency: Sandstorm Mercenary, TFA-VOX Battlefield 3 U.S. Marine, and the Sandstorm-style packs
  from TIF Faction Pack.
- MW Base weapon sounds, used with the authors' permission.
