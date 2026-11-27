Title:
Tactical Infantry Framework (TIF) - MW-Style Military AI

Description (Steam BBCode, paste as-is):

[h1]Tactical Infantry Framework[/h1]
[b]Soldiers that move, fight and clear rooms like Modern Warfare's AI.[/b]

TIF is a NextBot military AI built around a single, fully animated soldier body running over 4,400 Modern Warfare (2019 / 2022) animations. They take cover, push as squads, breach and clear buildings, take hostages, wrestle at close range, react to grenades and flashbangs, break and run when a fight turns against them, and die the way you'd expect. Spawn them from the spawn menu, set factions against each other, command a squad yourself, or drop a director and let it run the fight for you.

[hr][/hr]
[h2]Combat[/h2]
[list]
[*][b]Real cover.[/b] Corner cover (standing and crouched), low walls and chest-high walls. They run into it with directional arrivals, peek, lean out and fire with a proper aim blend, blindfire under heavy suppression, reload behind it, shuffle along walls, switch corners, and step out of it straight into a run when they need to move.
[*][b]Suppression.[/b] Incoming fire pins them, rushes them into cover or flat on the ground.
[*][b]Morale.[/b] Losing friends, getting hit and being outnumbered wears them down: shaken soldiers shoot worse and stop pushing. Broken ones retreat and hide, but still fire back in a panic (wild, inaccurate bursts over the shoulder or from a crouch), so a push on a breaking line is never free.
[*][b]Grenades.[/b] Frags over cover at enemies they can't see, flashbangs into rooms, dodges and dives away from live grenades.
[*][b]Weapons.[/b] 45 baked MW guns with MW sounds (fire, indoor / outdoor tails, reload foley), per-weapon reload and recoil animations, sidearm switching (in cover and prone too), LMG bipods prone and on ledges, magazines that actually leave the gun.
[*][b]Launchers as a tool, not a habit.[/b] AT gunners fight with their rifles and only shoulder the launcher when it counts: vehicles, bunched-up groups, dug-in positions, now and then an exposed soldier. A couple of rockets each, with cooldowns per gunner, squad and target, and the other side shouts "RPG!" when one goes up. The Marines' AT4 is disposable: fire, drop the spent tube, back on the rifle.
[*][b]Close quarters.[/b] Rifle-butt strikes, and paired melee fights between soldiers who end up face to face.
[*][b]Prone, crouch and stance changes[/b], all animated, including diving to prone on the run.
[*][b]Falls hurt.[/b] Blown off a roof or knocked off a ledge, they land hard, stumble, get wounded or die, depending on the drop.
[/list]

[h2]Squads[/h2]
[list]
[*]Formations, bounding overwatch, base of fire and flanking manoeuvres, regrouping on a new leader.
[*]Squads spawn in formation, facing you, so setting up a fight takes seconds.
[*]Radio chatter and per-faction voice packs: contact calls, suppressing, reloading, man down, grenade out.
[*]Medics and casualties: wounded soldiers, revives, last stands and long, crawling deaths.
[*][b]Command your own squad[/b] with the order menu ([i]tif_menu[/i]): follow, hold, advance, take cover, clear a building.
[/list]

[h2]Directors: fights that run themselves[/h2]
Two admin entities (a field radio each) under [b]Spawn Menu > Entities > Tactical Infantry[/b]. Pick the enemy faction from the dropdown (or leave it on Auto) and tune everything in Edit Properties.
[list]
[*][b]Soldier Director.[/b] Paces a fight like Left 4 Dead: patrols and guard posts appear ahead of you, out of sight, and assault squads come hunting you on a timer. It watches how hard the fight is going (damage you take, enemies you kill, how close they get) and after a big fight it backs off and lets things calm down, so the next area is quiet before it builds again.
[*][b]Soldier Survival.[/b] Waves of squads that know where you are and come to you. Waves grow, and the enemy changes as you last: early waves are guards and SMG-carrying assault troops, then riflemen and machine gunners pinning you down, then marksmen and AT gunners, then breachers, leaders in every squad and tougher men. They take cover they can shoot from and push in to find you rather than hiding, so you get proper standoffs. Wave counter, clock and break timer on screen.
[*][b]Onslaught.[/b] Survival's endless mode: no breaks, a constant stream that speeds up, grows and gets tougher the longer you hold, with surges every minute or so.
[/list]

[h2]Room clearing (CQB)[/h2]
[list]
[*]Squads stack up on doors and breach them: opened by hand, kicked, sledgehammered, or cracked for a flashbang.
[*]Open doorways get two-man simultaneous entries; the point man crosses, the second hooks the other way.
[*]Flashbangs before entry, cleared room by room through the whole building.
[*]Breached doors can come off their hinges (area-portal safe).
[/list]

[h2]Human shields[/h2]
[list]
[*]Enemies cornered near civilians may grab one as a shield. Shoot the captor cleanly, or watch the hostage pay for a bad shot.
[*]Hold off too long and a friendly soldier lines up the shot himself.
[*]Usable as a scripted moment from other addons through the API.
[/list]

[h2]Living, breathing soldiers[/h2]
[list]
[*][b]Reactions:[/b] flinches and staggers by hit location, flashbang blindness, startles, pointing out contacts, looking around after losing you.
[*][b]Deaths:[/b] situational death animations (in cover, running, against walls, over ledges, burning) that hand over smoothly to ragdolls.
[*][b]Movement:[/b] start / stop / turn animations, strafing, mantling, vaulting and dropping off ledges, opening doors on the way, wading through water.
[*][b]Eyes:[/b] they look at what they're aiming at, and at you.
[*][b]Downtime:[/b] patrols, smoking, phone calls, leaning on walls, sitting.
[*][b]Foley:[/b] footsteps for every surface, gear and cloth rattle, landings, body falls.
[/list]

[h2]Civilians[/h2]
[list]
[*]Wander, talk in groups, panic, flee, hide against walls or on the ground, and wave others to safety.
[*]Never targeted by soldiers; soldiers hold fire when a civilian is in the line.
[/list]

[h2]Vehicles and bases[/h2]
[list]
[*]Soldiers drive Glide vehicles, run convoys and man mounted guns (Glide required for vehicles).
[*]Road networks from Decent Vehicle waypoints or the navmesh.
[*]Build, save and garrison bases.
[/list]

[h2]Factions and setup[/h2]
[list]
[*]Three starter factions out of the box, all fighting each other:
[list]
[*][b]Insurgents[/b]: most of them fight like the untrained guerrillas they are, spraying blind over cover, jittery when they aim, sprinting loose. A few veterans in each group fight like soldiers.
[*][b]US Marines[/b] in desert or MARPAT Woodland.
[*][b]Russian Ground Forces[/b] (MadIvan18's Battlefield 4 Russians: flora, khaki, EMR, Baku, Aftermath and recon kits) with Russian special forces guns and Russian voices.
[/list]
[*]Insurgents and Marines are Insurgency characters by MadIvan18 (used with permission), each with light / standard / heavy outfits, randomised gear and several voice packs. Squads mix models and gear so no two look alike.
[*]Pick your side: play as a faction, or as plain BLUFOR, OPFOR or Independent.
[*]Faction editor ([i]tif_factions[/i]): sides, models, voices, weapons by role.
[*]Modular factions: soldiers assembled from body, head and headgear parts.
[*]HL2 and other NPCs are recognised: rebels side with players, Combine and monsters don't.
[*]Save and load: soldiers come back from a save (or a dupe) with the same look, guns, health, squad and orders.
[*]Settings in [b]Spawn Menu > Options > Tactical Infantry[/b] (Server and Client pages).
[*]A public API for game modes and other addons (spawning, squads, orders, room clears, shields).
[/list]

[hr][/hr]
[h2]Requirements[/h2]
[list]
[*][b]A navmesh.[/b] NextBots can't move without one. Most maps don't ship with one: run [i]nav_generate[/i] once in singleplayer.
[*][b]Optional:[/b] Glide (vehicles), Decent Vehicle (road waypoints).
[*]Works in singleplayer and multiplayer; the host needs the addon like everyone else.
[/list]

[h2]Good to know[/h2]
[list]
[*]Soldiers' sounds and animations are played on each client: no extra network load for footsteps or foley. Soldiers off screen animate cheaply.
[*]Bugs? Run [i]tif_mark <what happened>[/i] in the console the moment you see it, then send [i]garrysmod/data/tif/log_sv.txt[/i]. It records what every nearby soldier was doing.
[/list]

[i]Animations and sounds are from Call of Duty: Modern Warfare (2019 / 2022). This addon is a fan project, not affiliated with Activision or Infinity Ward. Voices: Insurgency: Sandstorm and BF3 USMC (TFA-VOX), Black Ops Cold War Spetsnaz (TFA-VOX). Faction models by MadIvan18, used with permission.[/i]

---

For developers (Steam BBCode, paste under the main description or as a Workshop discussion / guide):

[h1]For developers[/h1]
TIF is built to be extended. You can add factions and voices from your own addon without touching TIF's files, and drive soldiers from your own gamemode through a stable API.

[h2]Content packs: your own factions and voices[/h2]
Put this in [i]lua/autorun/your_pack.lua[/i] (shared). It works whether your addon loads before or after TIF:
[code]
local function pack()
    -- A voice pack: a sound folder plus which file names mean what.
    -- File names minus their trailing number are the categories ("alert3.wav" -> "alert").
    -- Reusing an existing event map is easiest (Insurgency: Sandstorm naming):
    TIF.Voice.RegisterPack("my_voices", { folder = "vo/my_voices", events = TIF.Voice.SANDSTORM_EVENTS })

    TIF.RegisterFaction("my_faction", {
        name = "My Faction",
        side = "enemy",                              -- enemy / ally / neutral (menu label)
        models = { "models/my/soldier_01.mdl", "models/my/soldier_02.mdl" },
        voices = { "my_voices" },                    -- each soldier gets one for life
        allies = { insurgents = true },              -- faction ids; everyone else is hostile
        -- relationsAs = "usmc",                     -- or: count as another faction for every relation (a camo variant)
        loadouts = {                                 -- by archetype, "default" for the rest
            default = { primary = { "weapon_tifmw_akm" }, secondary = { "weapon_tifmw_m19" } },
            support = { primary = { "weapon_tifmw_pkm" } },
            marksman = { primary = { "weapon_tifmw_svd" } },
            rpg = { primary = { "weapon_tifmw_akm" }, launcher = { "weapon_tifmw_rpg7" } },  -- drawn when it counts
        },
    })
end

if TIF and TIF.RegisterContent then
    TIF.RegisterContent("My Pack", pack)
else
    TIF_CONTENT = TIF_CONTENT or {}
    table.insert(TIF_CONTENT, { "My Pack", pack })
end
[/code]
[list]
[*][b]Models[/b] must be ValveBiped player models. TIF puts them on its animated MW19 body by bone-merge, so no animations of your own are needed. A model with its own ragdoll gets its own corpse.
[*][b]Archetypes[/b]: rifleman, assault, support, marksman, rpg, leader, guard, breacher.
[*][b]Voice events[/b] TIF plays: contact, contact_sniper, contact_mg, contact_rpg, reloading, grenade_out, grenade_incoming, man_down, suppressing, moving, cover_me, advance, retreat, clear, backup, affirmative, negative, kill, pain, death, critical, friendly_fire, swear, spawn. To map your own files, pass [i]events = { contact = { "alert", "attack" }, ... }[/i] (event -> categories).
[*][b]Camo variants[/b]: [i]variants = { { id = "woodland", name = "Woodland", models = { ... } } }[/i] with [i]variantMode = "squad"[/i] (one per squad), "mixed", or a variant id.
[*][b]Modular factions[/b]: soldiers assembled from body / head / headgear parts on one skeleton. Set [i]modular = { main = "body", slots = { body = {...}, head = {...}, helmet = {...} }, chance = { helmet = 0.7 } }[/i]. Combos limit which parts go together and which archetypes wear them.
[*][b]noBlank = true[/b] stops random looks from picking empty bodygroup options.
[*]Pack factions show in the spawn menu and can be overridden in game by the faction editor ([i]tif_factions[/i]).
[*]Guns: use the 45 [i]weapon_tifmw_*[/i] classes. Custom guns are definitions registered with [i]TIFG.RegisterWeaponDef[/i]; copy one of the [i]weapon_tifmw_*[/i] files as a template.
[/list]

[h2]Gamemodes: the API[/h2]
Server-side, in [i]TIF.API[/i]. Check [i]TIF.API.VERSION[/i] (currently 4) before relying on newer calls.
[code]
hook.Add("InitPostEntity", "mymode_tif", function()
    local API = TIF and TIF.API
    if not API or (API.VERSION or 0) < 4 then return end

    local squad = API.SpawnSquad("insurgents", Vector(0, 0, 0), { "leader", "rifleman", "rifleman", "support" })
    API.SquadAdvance(squad, Vector(1500, 0, 0))
end)

hook.Add("TIF_SoldierKilled", "mymode_score", function(soldier, attacker)
    -- award points, track objectives...
end)
[/code]
[list]
[*][b]Squads[/b]: SpawnSquad, FormSquad, AddToSquad, SquadHold / SquadAdvance / SquadPatrol / SquadSearch / SquadWithdraw / SquadFree, SquadOrder, SquadFormation, SquadSetLeader, RemoveSquad, PlayerSquad.
[*][b]Knowledge[/b]: SquadState (alive, engaged, suppressed, pinned, tactic, enemies...), SquadEnemies, SquadKnowsEnemy, SoldierState, Fighters, FightersNear, IsFighting, FactionOf.
[*][b]Room clearing[/b]: SquadClear(squad, pos, opts), with commanded entries: hold on the stack, then SquadClearGo; method open / kick, an onEntry callback, single room. Also SquadClearing, SquadStopClear, DoorAt, DoorInfo, RoomAt, RoomCenter.
[*][b]Single soldiers[/b]: SoldierTask (go there, face this way, shoot from there), SoldierTaskDone, Stun, Say, SetCaptive.
[*][b]Who fights whom[/b]: SetEngageFilter(owner, fn): fn(soldier, target) returns "fight", "cover" (aim, never shoot) or "ignore". Good for SWAT-style rules of engagement. SetPerception changes view / detection profiles.
[*][b]Bases[/b]: Garrison, GarrisonAdopt, GarrisonRelease, GarrisonSoldiers, GarrisonLevel, RemoveGarrison.
[*][b]Civilians[/b]: SpawnCivilian, Civilians, ScareCivilians, SetCivilianLeaveShare. [b]Human shields[/b]: HumanShield(captor, civilian, opts), HumanShieldOf.
[*][b]Vehicles[/b] (Glide): SpawnVehicle, Mount, MountSeated, MountPassive, DriveTo, Dismount, Convoy, VehicleRoute.
[/list]

[h2]Directors from code[/h2]
The Soldier Director and Soldier Survival are plain entities ([i]tif_director[/i], [i]tif_survival[/i]) with their settings as network vars, so a gamemode can spawn one and set it up like any other entity. [i]TIF.Director[/i] holds the pieces they use: hidden spawn points ahead of the players (FindSpawn), hunting squads (Hunt), the intensity meter and the survival stages (STAGES).

[h2]Hooks TIF fires[/h2]
TIF_SoldierKilled (soldier, attacker), TIF_CQBRoomClear (squad, room, cq), TIF_CQBDone (squad, reason, cq), TIF_ShieldStart (scene), TIF_ShieldEnd (scene, outcome), TIF_CivilianUse / TIF_CivilianHurt / TIF_CivilianKilled / TIF_CivilianLeft, TIF_BaseLevel (base, level, why).

[h2]Your own NPCs and NextBots[/h2]
Set [i]ent:SetNW2String("tif_faction", "some_faction_id")[/i] on your NPC or NextBot and TIF soldiers treat it as a member of that faction: they see it, fight it or fight beside it. "hl2_monster" is hostile to everyone. HL2 NPCs get a side automatically (rebels with the players, Combine and monsters against).

[h2]Debugging[/h2]
[i]tif_selftest[/i] checks the map, navmesh, factions and content. [i]tif_mark <note>[/i] writes what every soldier near you is doing to [i]garrysmod/data/tif/log_sv.txt[/i], alongside TIF's errors and events.
