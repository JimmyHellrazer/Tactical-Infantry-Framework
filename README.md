# Tactical Infantry Framework (TIF)

Modern Warfare-style NextBot military AI for Garry's Mod. Drop `addon/` into `garrysmod/addons` (optionally rename it to `tactical_infantry_framework`).

## Features

- **Animation & Body:** 4,200+ MW19/MW22 animations (movement, starts/stops/turns, prone, wading, mantling/vaulting, foot IK, turn lean) with ValveBiped player model bone-merging, 45 baked MW weapons with sounds/recoil/dropped mags/bipods, directional hit reactions, and situational death clips into ragdolls.
- **Combat & AI:** High/low/corner cover, peeking, blindfire, suppression, grenades, flashbangs, morale (`tif_morale`), close-quarters melee, smart AT launchers (RPG/AT4), and graded awareness (unaware, suspicious, searching, engaged).
- **Squads & CQB:** Formations, bounding overwatch, flanking, medics/revives, faction radio chatter, and door-breaching room clears (open, kick, sledge, flashbang). Squad command (`tif_menu`) is currently slated for an overhaul.
- **World & Compat:** Civilians and human shields, Glide vehicles/convoys, Decent Vehicle road networks, saveable bases/garrisons, HL2/addon NPC faction relations, and door-opening compat.
- **Modding:** Built-in Insurgents, US Marines (Desert & MARPAT Woodland), and Russian Ground Forces factions; in-game faction editor (`tif_factions`), modular character parts, content pack hooks, and server API (`TIF.API`, see `docs/WORKSHOP.md`).

## Quick Start

1. Ensure the map has a navmesh (run `nav_generate` in singleplayer if soldiers don't move). Included test maps: `tif_cqb`, `tif_range`.
2. Spawn soldiers/squads via **Spawn Menu > NPCs > TIF - ...**.
3. Configure settings via **Spawn Menu > Options > Tactical Infantry** (`tif_settings`) or run `tif_selftest`.
4. Optional addons: **Glide** (vehicles), **Decent Vehicle** (road waypoints).

## Reporting Bugs

Run `tif_mark <description>` in console when an issue occurs and attach `garrysmod/data/tif/log_sv.txt`.

## Repository Layout

| Path | Contents |
|---|---|
| `addon/` | Shipped Garry's Mod addon. |
| `build/` | Source meshes, QCs, host rig, and test map VMFs. |
| `tools/` | Asset build scripts (`anims/`, `guns/`, `props/`, `air/`, `factions/`), offline LuaJIT test harness (`harness/`), and local dev addons (`devtools_addon/`, `gunbake_addon/`). |
| `docs/` | Architecture, status, and Workshop documentation. |
| `media/` | Screenshots and Workshop assets. |

## Credits

- **Animations & Sounds:** Call of Duty: Modern Warfare (2019 / 2022) — fan project, unaffiliated with Activision or Infinity Ward.
- **Starter Faction Models:** Insurgency 2 & Battlefield 4 Russian Ground Forces by MadIvan18 (used with permission); MARPAT Woodland textures from Workshop #3466197531.
- **Voices & Audio:** TFA-VOX Insurgency: Sandstorm / BF3 USMC, TIF Faction Pack, MW Base weapon sounds (used with permission), and SandSWEP Launchers (AT4).
