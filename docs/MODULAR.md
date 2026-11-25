# TIF modular factions (plan + change log)

Status: **2026-11-13: built (TIF 0.28.0 + new addon tif_cod_factions); first in-game test failed (no retarget), fixed, re-test pending.**

Goal (user): a small sub-framework for factions whose soldiers are put together from parts, the way CoD builds its
characters: a body, a head, sometimes a helmet, with CoD's pairing rules. Random skins on every part, bodygroups
left alone. First users: the codport CoD ports (Jimmy_COD pack, bones renamed to ValveBiped by `CODDIDDY.py`, so
they bone-merge straight onto TIF's MW19 host with no retarget).

## How it works

- `tif/config/sh_modular.lua` (new, shared): a faction sets `def.modular = { main, slots, combos, chance }` (format in
  the file's header). `TIF.Modular.Pick(def)` (server) picks one model per slot: a random allowed combination from
  `combos` (by index into the slot lists), the rest free, `chance` per optional slot.
- The `main` slot (body) is TIF's faction model as before (look, corpse, gun hand). The other parts go out as NW2
  string `tif_parts` = `model#seed;...` on the soldier and his corpse; every client bone-merges them onto the soldier's
  faction model (or onto the corpse's), skin = seed % skin count (same on every client). They follow it: rebuilt
  when it's rebuilt, hidden while it's hidden / dormant, re-attached after dormancy, shadows off with `tif_noshadow`,
  removed with it.
- Bodygroups: the main model gets all defaults (no random bodygroups for modular factions); parts get defaults
  except any group named `PlaceHolder_Body` (codport heads carry a stand-in body), which is set to its blank option.
  Head accessories (shemaghs, tassels, hair...) stay on.
- Faction editor: the `modular` table is sent with the faction list, kept when a faction is saved and cleaned on load
  (not editable there yet).

**TIF base changes (0.28.0)**: new file `config/sh_modular.lua` (+ manifest line in `autorun/tif_init.lua`);
`entities/tif_soldier.lua`: Initialize asks `TIF.Modular.Pick` for modular factions (main model, parts, default
bodygroups, sets `tif_parts`), the corpse copies `tif_parts`; `config/sh_factions_custom.lua`: `modular` passes
through. Non-modular factions: unchanged (`tif_parts` = "").

## tif_cod_factions (new addon)

| Faction | Side | Parts |
|---|---|---|
| `al_qatala_desert` Al Qatala (Desert) | hostile | 9 heads x 9 bodies: heads 2 4 6 9 with any body but 5; heads 1 3 7 8 only with bodies 1 3 7 8 (no neck shemagh); head 5 and body 5 only together (49 pairs) |
| `usmc_basic` USMC (Basic) | allied | heads Colvin / Ferragamo / Valladares / Vasquez x basic helmets ar_1-4 / lmg x basic bodies ar_1-4 / lmg (100) |

Models: `models/tif_cod_factions/*.mdl`, copies of the Jimmy_COD pack models (pack currently in `K:\mods map pics`)
made by `K:\jimmyproject\codport\tools\lod_pack.py`: LOD0 = the original meshes untouched; LOD1/2/3 at ~50 / 25 / 12%
of the triangles ($lod 15 / 35 / 70, $shadowlod = LOD3; vertices only dropped, so bone weights stay exact; eyes never
simplified); heads built with `--no-flex` (user: no face posing needed: no flex controllers, rules or eyelids; eyeballs
kept); heads keep their ragdoll .phy (restamped). Materials copied in from the pack, so the addon stands alone.
Body 09_rpg / head 09_rpg (different outfit) left out.

Offline check: `K:\jimmyproject\tif_air\harness\modular_harness.py` (5000 picks per faction: no forbidden pair, all
49 / 100 combinations reached).

## Not known until it runs in game
- part bone-merge on the GTA host (`tif_mw_anims 0`): parts merge onto the retargeted faction model (should follow);
- LOD switch distances (15 / 35 / 70) and how far LOD3 holds up;
- corpses: dressed a moment after they appear (same as the faction model).

## Change log
- 2026-11-13: built (above).
- 2026-11-13 (user, first in-game test: twisted bodies, no heads; "the models still need a retarget ... the smart thing
  would be to parent clothes and helmets to the head model"): the ports keep CoD's bone axes under CODDIDDY.py's
  ValveBiped names, so a plain bone-merge twists them. Now: `modular.retarget = true` -> the main model wears the
  host through GTG's retarget map on every host (cl_body `make_follower` without the ValveBiped shortcut for those
  models); GTG's skeleton reader no longer requires `Bip01_Spine` (CODDIDDY has none: CoD spinelower/upper/spine4 ->
  Spine1/2/4; the map merges by name and inherits through missing bones); main slot = the head (it has the ragdoll +
  stand-in body, switched off), body + helmet bone-merge onto it (same codport rig: exact); corpses of retargeted
  models = the host's ragdoll dressed by clients. Offline: `harness/retarget_harness.py` builds the host -> head map
  for all 13 heads with GTG's own reader (56 bones driven, oddness 1.07; before the fix the read failed).
- 2026-11-13 (user: heads only, bodies/helmets missing but their shadows there): parts were hidden because their owner,
  the client-side faction model, always reads IsDormant(); now NoDraw only (+ dormancy for networked owners).
- 2026-11-13 (user: head only, no body / helmet, head-sized shadow): tif_soldier.lua read Pick's two results through an
  `a and b and f()` chain, which keeps only the first -> parts were always empty (also why the first test had no heads).
  Now called on its own. (The offline picker test called Pick directly, so it couldn't catch this.)
- 2026-11-13 (user: bodies/helmets show, but some body verts streak off sideways): GTG's map only drove the head's own
  used bones (weighted / hitbox), ~17 per head stayed at rest (wrists, fingers, twist helpers, gear joints) and the
  bone-merged body copied them. sh_modular.lua wraps PMS.MapFor: retargeted models drive every bone (all but the root,
  verified on all 13 heads by retarget_harness.py).
- 2026-11-13 (user: streaks remain on arms / thighs; theory: procedural bones lost): the rebuilds keep all 4 twist
  helpers (L/R Wrist, L/R Shoulder, quatinterp; bone_compare.py vs the pack originals: identical). The fault was how
  GTG drives non-host bones: ENGINE kind keeps the base model's rest rotation, QUAT re-solves the helpers from their
  VRD triggers (garbage on these rigs). Retargeted models now BIND every bone the host lacks to its solved parent (the
  helpers' extra twist is lost). retarget_harness.py checks every bone is MERGE or BIND on all 13 heads.
- 2026-11-13 (user: streaks even on the corpse, which stood in an A-pose): (1) bone-merging the body onto the head was
  the fault: Source only sets up the bones a model uses, and the head's mesh uses head + neck; the merged body copied
  the rest unset. Now every part of a retargeted faction is its own GTG follower of the soldier (or corpse): own map,
  own solve (all 19 bodies / helmets map like the heads: same 56 host bones). (2) TIF's MW19 host has no .phy, so the
  host-ragdoll corpse was a frozen A-pose; corpses are the head's own ragdoll again, each physics bone posed as host
  rotation x the retarget's rest offset (TIF.Modular.RestOffsets), parts retargeted from the ragdoll.
- 2026-11-13 (user: living soldiers good but arms weird; corpses still streak): (1) candy-wrapper forearms = the twist
  helpers bound to their parents; the earlier 'QUAT garbage' was really the bonemerge fault, so the 4 quatinterp
  helpers keep GTG's QUAT solve again (only gear bones bind). (2) a corpse ragdoll leaves its non-physics bones unset
  too, so parts on a corpse use TIF.Modular.CorpseMap: merge only the ragdoll's physics bones (names from its .phy:
  20, incl. spine1/2/4 + clavicles) + head / neck, bind the rest. retarget_harness.py checks both.
- 2026-11-13 (user: forearms skinny, upper arms rolled inward): TIF's MW19 host never rolls its forearm (harness/arm_roll.py:
  within 0.4 deg; the hand carries up to ~140 deg, upper arms roll 30-50 deg), and GTG's QUAT solve didn't reproduce
  codport's helpers. Now all helpers BIND and TIF.Modular.ArmTwist runs after every solve of a retargeted model:
  forearm takes 50% of the hand's roll, Wrist helper 85%, Shoulder helper counter-rolls 70% of the upper arm's roll
  against the clavicle; hand keeps the host's rotation. Not checked in game.
- User asked for the Chechen fighters' ragdoll (.phy) instead of codport's: theirs is a stock 18-solid ValveBiped one
  whose hulls and joint limits are in Valve bone axes; the heads' bones are on CoD axes, so it needs converting per bone
  (not done yet).
- 2026-11-13 (user: 'take a phys from the czech rebel mod', the current ragdoll felt weird; done with the Chechen fighters'
  boevik_male_02_pm.phy): K:\jimmyproject\codport\tools\phy_convert.py reads its 18 hulls (IVP ledges, bone space) +
  keyvalues, swings each hull onto the codport bone (bone direction to child aligned; centres 0.2-2.7 in off the
  bone segment) and maps joint limits onto the target bone's axes; lod_pack.py --ragdoll compiles it into each head
  via $collisionjoints (no $rootbone: with it studiomdl filed the pelvis under tag_origin). All 13 heads rebuilt:
  18 solids, pelvis root, checksums match. Not checked in game.
- 2026-11-13 (user: glove cuffs torn up the forearm, elbows bulging): the twist math checks out offline
  (harness/armtwist_harness.py on the real rig), but the forearm's own gear / cuff bones (bound before the pass) didn't
  turn with it, and a 50% forearm share wrung the elbow. Now forearm 0.3 / Wrist 0.8 / Shoulder 0.78 (VRD ratio) and every
  forearm descendant except the hand subtree and the Wrist helper turns with the forearm. Also found: the MW19 host
  has its own Valve helpers (L/R Wrist, Shoulder, Ulna, Elbow, Bicep, Trapezius); GTG merged codport's Wrist /
  Shoulder from those by name (the twist pass now overrides them).
- 2026-11-13: offline posing renders (harness/pose_render.py: GTG's real solve + ArmTwist + skinning of a part in a host
  clip frame; host_pose_render.py: TIF's host body in the same frame). The retargeted USMC body follows the host's arm
  pose; the bunched upper arms come from the body's bulky sleeves / pads with the rig's few helper bones in a deep elbow
  bend (same with the shoulder counter-roll off). Twist shares are now live: TIF.Modular.TwistShares = { forearm,
  wrist, shoulder } (0.3 / 0.8 / 0.78).
- 2026-11-13 (user: renders still look off, upper arms tilted in, forearms skinny): found the real fault with a hinge
  check in pose_render.py (elbow rotation vs rest, as axis-angle in the upper arm's frame). The host's elbow is a clean
  hinge about its z; ours bent about (0.12, 0.69, -0.72) on the left: GTG's offsets keep each bone's direction but
  not its roll, and codport's rest elbow is bent 47 deg about the upper arm's -z where the host's is near straight, so
  the upper arm came out rolled up to ~45 deg (sleeve and biceps turned in, forearm seen edge-on). TIF.Modular.ArmTwist
  now first rolls the upper arm about its own direction until its rest hinge axis is the real bend axis (upper arm x
  forearm; fades out under ~16 deg of bend), carries its other bones (not forearm / Shoulder helper), and rolls the
  forearm onto the same hinge before the hand-twist share. Joint positions unchanged. Hinge check now matches the host
  within ~1 deg on 5 clips (both arms). Not checked in game.
- 2026-11-14 (user screenshots: forearms "unwilling to tilt toward the hand", wrist skin stretched from forearm to
  hand): the root fault. GTG aims a bone at its child only when it has exactly one child (or PMS.Aim names it);
  codport's upper arm (forearm + Shoulder helper + j_proc_shoulder) and forearm (hand + Wrist helper + j_elbowdq + gear)
  have several, so both took the clavicle's offset and pointed 21 deg / 61 deg off their elbow / hand (axis check added to
  pose_render.py; legs, clavicles 0). The PMS.MapFor wrapper now sets PMS.Aim upperarm -> forearm, forearm -> hand
  for retargeted models' maps (restored after). Now 0.0 deg on both arms, and the elbow is a clean hinge matching the
  host even before ArmTwist. Also fixes the corpse ragdoll's arm pose (RestOffsets reads the same map).
- 2026-11-14 (user: arms "work perfect"; asked for CoD's physically simulated accessories: ammo belt tails,
  chemlights on carabiners): `TIF.Modular.Sway` (client, sh_modular.lua), run after the solve + ArmTwist on every
  retargeted part (living and corpse). CoD's per-bone physics presets aren't in the rips, so chains are found from
  the skeleton: a `j_cosmetic` bone whose rest direction to its `j_cosmetic` child points down (z < -0.6 x length) and
  is 0.3-6 units long; longer ones (vest / back plates `j_cosmetic_1/2/4_alt`, AQ butt pack `26_alt`) and childless
  pouches stay rigid. Found: AQ bodies 01/02 ammo belt tail (33-36_alt), 03 vest strap tabs (6-15, 48), 04-09
  butt-pack straps (20-23, 27-30); USMC ar_1 / ar_3 / lmg carabiner + chemlights, ar_2 / lmg canteen on keyring,
  ar_4 belt loadout + buckle straps. Each is a damped spring pendulum in world space (pulled to the animated tip,
  gravity, momentum, damping relative to the attachment so a steady walk doesn't trail, bone length kept, within
  `limit` deg of the animated direction); the bone and everything below it turn onto it. Integrates once per frame
  (sub-steps at 90 Hz, max 4), resets after a gap / teleport, off beyond `dist`. Live client convars: tif_sway,
  tif_sway_gravity (386), _stiffness (120), _drag (6), _limit (70), _dist (800; was 1600, user asked for close range only); per model
  `TIF.Modular.SwayModels[model] = false | { overrides }`. Offline (pose_render.py with SWAY="frames,speed": walks the
  body then stops): stable on all tested bodies, no blow-ups; idle hangs 10-20 deg off the animated pose (gravity,
  hips tilt), a stop swings up to ~65 deg per bone and settles. Clipping into packs / legs not checked (no collision).
- 2026-11-14 (user: "is the same tech on the head shemaghs"): it wasn't: AQ heads 01 / 03 / 07 / 08 carry two 3-bone
  shemagh tails each and head 04 two 2-bone ones, resting back along the head (only one of 04's passed the
  "hangs down" rule). Chains whose first non-cosmetic ancestor is Head1 / Neck1 are now taken whatever their rest
  direction, at 4x stiffness and half the swing limit (full gravity would flop them into the neck). Offline walk + stop:
  8-20 deg while walking, up to ~55 deg at the tip on a stop, settles; bodies unchanged. Corpses: the head is the
  ragdoll itself, so it now gets its own sway callback (its tails were rigid on corpses).
- 2026-11-14 (user screenshot: on death a headless body in the reference pose can float over the fresh corpse): the
  soldier is hidden then removed a tick after his corpse spawns; the parts record was only dropped with its owner (the
  faction model), and while the owner outlived the soldier the upkeep "re-attached" the parts to the owner, where
  their retarget has no host pose (reference pose, origin off). Parts now drop when their leader (soldier / corpse) is
  gone, and hide as soon as the leader is NoDraw (the death hide) or dormant. Not checked in game.
- 2026-11-14 (user: after fights, dressed bodies left posing in the field, some off living soldiers, some off corpse
  heads; with tif_cl_retarget 0 every bare host was in place): a retargeted model reads its leader's bones through
  the engine's bone-merge, and when that silently stops (parent link unchanged, merge cache lost) it keeps drawing
  its last / own pose where it was; cl_body and the parts upkeep only re-attached when the parent link changed.
  Now every retargeted model checks after its solve that its pelvis sits on the leader's (within 48 units; the
  retarget moves no joints); 3 frames off -> re-attached (main model: same steps as cl_body's attach, not while
  prone), a part set still off after 3 re-attaches -> rebuilt. `tif_modular_debug` lists records and counts.
  Not checked in game (cause not seen directly; the check is the safety net either way).
- 2026-11-14 (user: eyes only look forward from spawn, don't turn with the head): Source keeps a client-side
  model's eye target where it was set. TIF.Modular.Eyes sets it each frame 200 units ahead of the head (model rest +x
  in the head frame; offline: ~+x in idle clips). Living main models; client convar tif_eyes (1).
- 2026-11-14 (user: leftover bodies survive a map cleanup): the parts table was weak-keyed, so a removed owner's
  record could be garbage-collected before the upkeep saw the owner gone, and its client-side parts were orphaned
  for good (a cleanup only removes server entities). Likely also the source of the frozen "posing" bodies. Now
  strong-keyed; every part is also kept in TIF.Modular.AllParts, a 2 s sweep removes any part no record owns
  (counted in tif_modular_debug), and PostCleanupMap removes them all. Orphans made before this change need a
  restart to go.
- 2026-11-14 (user: help the game run with many MW characters): textures shrunk with
  `K:\jimmyproject\codport\tools\tex_shrink.py` (in place; originals in `K:\backups\tif_cod_factions_materials_2026-11-14`):
  faces / heads / hair / beards / eyes capped at 2048, everything else at 1024; DXT1 where the alpha is unused, else
  DXT5; mipmaps on all (19 had none). 663 textures 1098 MB -> 387 MB (no uncompressed ones left, 17 at 2048). Source in
  GMod has no texture streaming, so that is video memory saved whenever these factions are on the map. Spot check vs the
  originals (downscaled): mean colour difference 0.4-4.5 / 255. Not looked at in game.
- 2026-11-14 (user: t-shirt texture glitch after the shrink; eyes still bugged): (1) the shrink had DXT-compressed the
  lightwarp ramps (codport_gear_wrp / skin_wrp, lightwarp_soft): banded, flat lighting on everything using them. Those
  and the eye shader's textures (irises, cornea, eye AO, eyelashes) were restored from the backup; tex_shrink.py now
  leaves lookup textures alone (lightwarps, eye textures, anything 16 px or thinner). (2) Eyes: SetEyeTarget takes the
  point relative to the model's "eyes" attachment (as the sandbox eye poser), not a world position; TIF.Modular.Eyes
  converts it now (all 13 heads have the attachment). Neither checked in game.
- 2026-11-14, TIF 0.30.0 (user: four more factions from the Jimmy_COD pack). TIF base (`config/sh_modular.lua`,
  `entities/tif_soldier.lua`, `config/sh_factions_custom.lua`): `TIF.Modular.Pick(def, archId)` gets the soldier's
  archetype; a combo may carry `arch = { ... }` (only for those archetypes; others take the combos without one); an
  index of 0 in a combo = that slot not worn; `modular.skins = false` = every part and the main model at skin 0. The
  faction editor keeps `arch` and `skins`.
  tif_cod_factions: 49 new parts by lod_pack.py (heads --no-flex + the Chechen ragdoll; Mex SF in
  models/tif_cod_factions/mex_sf/ (generic names)); factions:
  | Faction | Side | Rules |
  |---|---|---|
  | `rus_ground_forces` Russian Ground Forces | enemy | RGF heads (androsov, balaclava 1/2, orlovszki, sharipov) x 13 bodies x helmets 1-7; hooded bodies ar_3_3 / ar_3_4 (the `jacket_b` ones) never helmeted; full skins; DPR guns |
  | `rus_spetsnaz` Spetsnaz | enemy | assault: CQC head + body, NVG helmet half the time; support: LMG head + body; marksman: DMR head + ghillie body, no helmet; everyone else: AR head + AR / AR 2 / AR 3 body. AR / LMG heads wear their own helmet bodygroups (the separate spetsnaz_headgear_ar / _lmg are the same meshes: not used, no double helmet). DPR guns |
  | `rus_smugglers` Weapon Smugglers | enemy | RGF heads x smuggler bodies 1-4, skin 0; only Orlovszki wears a hat (his civilian beanie) |
  | `mex_sf_tier1` Mexican SF (Tier 1) | ally | head N + body N, skin 0; M4s / Kilo / M13 / SCAR, MP5 / MP7, Bruen / M91 / Finn, EBR / M13 DMR, M680, X16 / M19 / M1911 |
  Gas-mask heads / helmets / headgear left out. Offline: modular_harness.py (every rule over thousands of picks, all
  combinations reached), retarget_harness.py (all 49 parts map; 86 checks). Textures shrunk the same way (faces 2048,
  rest 1024, DXT + mips; backup `K:\backups\tif_cod_factions_materials_2026-11-14b`). Not run in game.
- 2026-11-14 (user: t-shirt still glitched, white blown-out patches; ragdoll too rigid, use "Better L4D2 Ragdoll
  Physics v2"): (1) tex_shrink.py had blackened normal maps whose alpha (a phong mask) is 0: Pillow pre-multiplies
  RGBA by alpha when resizing, and vtex turns 0/255-only alpha into 1-bit DXT1 (transparent = black). Fixed: colour
  and alpha resized apart, alpha kept in 1..254 (8-bit -> DXT5), and every rebuilt texture is now checked against its
  source before it replaces anything. All originals restored from both backups and shrunk again: 1424 textures,
  2231 -> 973 MB, 341 rebuilt, 0 failed; no normal map left black. 11 normal maps that were already black / dark in
  the pack itself (from the rip; e.g. al_qatala_desert_shirt_a_04_n) replaced with flat normals keeping their alpha.
  (2) All 26 heads rebuilt with that addon's male_shared.phy (19 solids, damping 0.01 / rotdamping 1.5, mass 30:
  loose) via phy_convert, paired with the Chechen model's ValveBiped skeleton (K:\jimmyproject\codport\ragdolls\
  l4d2_male.*). retarget_harness: 0 failures. Not checked in game.
