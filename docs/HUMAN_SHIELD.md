# Human shield: what's built, and what could be built for semi-scripted scenes

User, 2026-11-20: "build it and also like note it as something which could be created incase i wanna have it be in
a semi scripted situation".

## Built: the dynamic version (TIF 0.38.20, two variants since 0.38.28)

`tactics/sv_shield.lua` (TIF.Shield), placements per frame in `tactics/sv_shield_data.lua` (generated:
`K:\jimmyproject\tif_mw\shield_frames.py`; rerun after rebaking `mwsh_*` / `mwsc_*`).

- **mw19** (a player can see it start): MW19's AI hostage taker (Spec Ops `cp_hostagetaker_*`, roles
  `mwsh_<grab|idle|death|rescue>_<att|vic>`). He grabs a civilian from his right; raw, she ends kneeling at his side
  (MW19's pose: they don't touch once held), so TIF slides her to a kneel right in front of him over the grab's second
  half (0.38.28). Outcomes: hit on him -> he drops, she runs; an enemy within 110 in or 30-55 s held -> he shoves her
  down and fights; she's shot -> she dies outright, he fights on.
- **ch** (no player sees it start): Clean House's shield (`thd_2f_020_hostage_*`, roles `mwsc_*`), held standing in
  front of him, his gun over her shoulder. No grab clip, so it starts held (aim lead-in, then the aim hold); the
  nearest civilian within 160 in is put in his grip. Outcomes: hit on him -> his neck-shot death (cut at f90) with her
  "live" clip (cut at f78, before she grabs his gun at f84); she's shot -> her death (or the headshot one, picked by
  the hit's height) with his reaction, then he fights on. Held until settled (or 120 s).
- Trigger (SH.Try, from engage): a soldier hostile to the players, an enemy in sight 100-1000 in away; 50% per try, a
  try every 2 s, 40 s cooldown each, 2 scenes at most (0.38.28: was 30% / 3 s / 150 in). mw19 needs a civilian near
  the grab's start (~82 in out) for a facing within 50 deg of the enemy. `tif_shield 0` off.
- TIF soldiers hold fire while she's between them and their target (sv_weapon `ally_in_line`).
- Test: `tif_shield_test [held]` (dev addon) with a soldier and a civilian about.
## Semi-scripted: how to set one up today

The same scene, started by a script instead of the AI, through the API:

```lua
-- captor: a TIF soldier (MW19 body), civ: a tif_civilian
local sc = TIF.API.HumanShield(captor, civ, {
    variant = "ch",       -- Clean House's held-in-front shield (always held); default "mw19"
    held = true,          -- already holding when the player gets there (no grab clip)
    hold = 999,           -- or { min, max } seconds before he gives up on his own
    noRescue = true,      -- he never shoves her away himself: only a shot ends it
    pos = Vector(...),    -- his spot (default: where he stands)
    yaw = 90,             -- the scene's facing (default: turned so the civilian is where the clip starts)
})
hook.Add("TIF_ShieldEnd", "my_mission", function(sc, outcome)
    -- outcome: "shot" | "rescue" | "hostage_killed" | "captor_killed" | "removed"
end)
```

A mission / map trigger would spawn both (`TIF.API` spawn calls, `ents.Create("tif_civilian")`), start it held, and
react to `TIF_ShieldEnd` (hostage saved / lost). `TIF_ShieldStart(sc)` fires when any scene starts, dynamic or not.

## Could be created: the other shield sets in the rips (not built)

These are more cinematic, one-off scene clips; each would be a scripted variant of TIF.Shield (same placement method:
fit the raw scene onto the baked clips per frame, `shield_frames.py` with another clip list).

| Set | Clips (frames) | What it adds |
|---|---|---|
| **Clean House shield** (`K:\duglastakedown\thd_2f_020_hostage_*`) (built in 0.38.28 as the `ch` variant; the aim poses below still aren't used) | captor `aim_start` (21), `aim` (326), `aim_2/4/6/8` (1-frame aim poses), `idle` (335), `live` (82), `death` (947, notes `neck_fx`, `dropgun`, `allowdeath`, `kill_me`); hostage `aim_start`, `aim`, `idle`, `live` (122, `grab_gun`, `use_death`, `allow_long_death`), `death` (82), `death_headshot` (110, `start_ragdoll`), `death_long` (450) | The real "gun to her head, standing behind her" shield. The four aim poses can be blended (2 / 4 / 6 / 8 = down / left / right / up) so he tracks the player while holding her; the long neck-shot death; the hostage grabbing the gun when he's hit. Best for a hand-placed set piece. |
| **Embassy pistol grab** (`emb_oc_010_hostage_*`) | captor `enter` (126, `pistol_pickup`, `gun_2_chest`), `idle` (60), `exita` (67, `fire`), `exitb` (104); civilian `enter`, `idle`, `exita` (112), `exitb` (118) | Grabs a civilian and draws a pistol; one ending where he fires (execution / at the player), one where he lets go. |
| **Bomb-strapped hostage** (`hostage_bomb_idle_1/2`, ~22 s each) | idle loops | A hostage wearing a bomb (a defuse / rescue objective); pairs with the suicide-bomber standoff below. |
| **Bomber standoff** (`thd_atc_010_bomber_*`) | `enter` (366, `player_can_shoot`, `price_shoot`), `start_idle` (81), `end` (181: he sets it off), `death` (111), `death_headshot` (140), `death_longdeath` (667), `death_longdeath_shot` (59) | A dead-man's-switch standoff: shoot him in the window or it goes off. |
| **Wolf's room grab** (`mar_hos_wolfroom_pre_breach_grab_hostage_*`) | grab + two idles | Wolf holding a hostage before the breach (scene-specific). |

Semi-scripted pieces these would need that the dynamic version doesn't: aim blending from the 1-frame poses (cl_body
already blends aim sets), a "shoot the hostage" ending on a timer (Embassy `exita`), and notetrack-driven outcomes
(`player_can_shoot` windows, `grab_gun`).
