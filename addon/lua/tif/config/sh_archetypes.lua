-- Archetypes: one soldier implementation, different tuning.
-- In Phase 1 every archetype uses the same behaviour; the numbers below already change how
-- they detect, shoot and hold distance. Role-specific behaviour (flanking, suppression,
-- overwatch, breaching) arrives with Phases 2-5.

local TIF = TIF

TIF.AWARE = { UNAWARE = 0, SUSPICIOUS = 1, ALERTED = 2, ENGAGED = 3, SEARCHING = 4 }
TIF.AWARE_NAMES = { [0] = "unaware", "suspicious", "alerted", "engaged", "searching" }

TIF.Archetypes = TIF.Archetypes or {}

local BASE = {
	label = "Rifleman",
	health = 100,
	fov = 120,             -- degrees, when alerted or fighting
	fovUnaware = 95,       -- degrees, while on routine duty
	viewDist = 4500,       -- units
	detectTime = 1.4,      -- seconds to fully spot a standing, still target at 1000 units
	hearing = 1.0,         -- multiplier on every sound radius
	reaction = { 0.35, 0.7 }, -- seconds between spotting and the first shot
	spread = 2.2,          -- degrees of aim error at rest
	spreadMoving = 1.6,    -- multiplier while the shooter moves
	firstShots = 1.8,      -- multiplier right after acquiring a target, fades over 1.5 s
	burst = { 3, 7 },      -- rounds per burst
	burstPause = { 0.3, 0.8 },
	coverFire = 0.35,      -- chance of a few covering rounds as a dash to cover / a flank starts
	prefRange = { 350, 1800 }, -- keeps this distance from the target
	crouchChance = 0.45,   -- chance to crouch when holding still in a fight
	aggression = 0.5,      -- 0 holds back .. 1 pushes in
	loseContact = 6,       -- seconds without sight before switching to searching
	searchTime = 40,       -- seconds spent searching before returning to duty
	turnRate = 320,        -- degrees per second
	headshotChance = 0.08,
	speeds = { walk = 1, tactical = 1, run = 1 }, -- multipliers on clip speeds
	-- Phase 2
	coverUse = 0.85,       -- chance to take cover when a fight starts (re-rolled every few seconds)
	coverPause = { 0.8, 2.2 }, -- seconds hidden between pop-outs
	coverBurst = { 1.4, 3.2 }, -- seconds exposed per pop-out
	suppressResist = 0.3,  -- 0 panics easily .. 1 ignores incoming fire
	proneChance = 0.25,    -- chance to go prone when pinned with no cover nearby
	longRangeProne = false, -- lies down to fight at long range
	-- Secondary weapon: switch to it when the enemy is closer than this (nil = only when the
	-- primary runs dry up close). Long guns (marksman rifles, launchers) set it.
	secondaryBelow = nil,
}
TIF.Archetypes.base = BASE

function TIF.RegisterArchetype(id, def)
	def.id = id
	setmetatable(def, { __index = BASE })
	TIF.Archetypes[id] = def
	return def
end

TIF.RegisterArchetype("rifleman", {})

TIF.RegisterArchetype("assault", {
	label = "Assault", aggression = 0.8, prefRange = { 200, 1000 }, crouchChance = 0.25, burst = { 4, 9 }, coverFire = 0.6,
	coverUse = 0.6, coverPause = { 0.5, 1.4 }, suppressResist = 0.45,
})

TIF.RegisterArchetype("support", {
	label = "Support Gunner", burst = { 8, 16 }, burstPause = { 0.4, 0.9 }, spread = 2.8,
	prefRange = { 600, 2200 }, crouchChance = 0.7, aggression = 0.3, health = 110,
	coverBurst = { 2.5, 5 }, suppressResist = 0.65, coverFire = 0.3, proneChance = 0.6, longRangeProne = true,
})

TIF.RegisterArchetype("marksman", {
	label = "Marksman", burst = { 1, 1 }, burstPause = { 0.9, 1.7 }, spread = 0.6, firstShots = 1.3,
	prefRange = { 1200, 4000 }, viewDist = 7000, fov = 100, crouchChance = 0.6, aggression = 0.25,
	headshotChance = 0.25, coverFire = 0, coverPause = { 1.5, 3 }, suppressResist = 0.4, proneChance = 0.7, longRangeProne = true,
	secondaryBelow = 450,
})

TIF.RegisterArchetype("rpg", {
	label = "AT Gunner", prefRange = { 450, 2200 }, aggression = 0.35, crouchChance = 0.5, coverUse = 0.8,
	coverPause = { 1.2, 2.8 }, suppressResist = 0.45, coverFire = 0.3,
})

TIF.RegisterArchetype("leader", {
	label = "Squad Leader", aggression = 0.55, health = 110, suppressResist = 0.5, coverFire = 0.45,
})

TIF.RegisterArchetype("guard", {
	label = "Security", detectTime = 2.0, reaction = { 0.6, 1.1 }, spread = 2.9, aggression = 0.4,
	fovUnaware = 80, loseContact = 8, suppressResist = 0.05, coverPause = { 1.2, 3 }, coverFire = 0.2,
})

TIF.RegisterArchetype("breacher", {
	label = "Breacher", prefRange = { 100, 700 }, aggression = 0.75, burst = { 3, 8 }, crouchChance = 0.2,
	coverUse = 0.5, suppressResist = 0.5, coverFire = 0.5,
})

function TIF.Archetype(id)
	return TIF.Archetypes[id or "rifleman"] or TIF.Archetypes.rifleman
end
