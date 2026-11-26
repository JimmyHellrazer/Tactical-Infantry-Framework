

local TIF = TIF

TIF.AWARE = { UNAWARE = 0, SUSPICIOUS = 1, ALERTED = 2, ENGAGED = 3, SEARCHING = 4 }
TIF.AWARE_NAMES = { [0] = "unaware", "suspicious", "alerted", "engaged", "searching" }

TIF.Archetypes = TIF.Archetypes or {}

local BASE = {
	label = "Rifleman",
	health = 100,
	fov = 120,
	fovUnaware = 95,
	viewDist = 4500,
	detectTime = 1.4,
	hearing = 1.0,
	reaction = { 0.35, 0.7 },
	spread = 2.2,
	spreadMoving = 1.6,
	firstShots = 1.8,
	burst = { 3, 7 },
	burstPause = { 0.3, 0.8 },
	coverFire = 0.35,
	prefRange = { 350, 1800 },
	crouchChance = 0.45,
	aggression = 0.5,
	loseContact = 6,
	searchTime = 40,
	turnRate = 320,
	headshotChance = 0.08,
	speeds = { walk = 1, tactical = 1, run = 1 },

	coverUse = 0.85,
	coverPause = { 0.8, 2.2 },
	coverBurst = { 1.4, 3.2 },
	suppressResist = 0.3,
	proneChance = 0.25,
	longRangeProne = false,

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
