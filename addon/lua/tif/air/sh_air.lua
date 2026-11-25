-- Air vehicles (reinforcement helicopters): type definitions, shared by server and client.
-- Models come from the tif_air content addon (K:\jimmyproject\tif_air\heli_build.py). A type whose model isn't
-- installed is unavailable; nothing else breaks. Flight and routes: tif/air/sv_air.lua + entities/tif_heli.lua.

local TIF = TIF
TIF.Air = TIF.Air or {}
local Air = TIF.Air

Air.Types = Air.Types or {}

-- def fields (units: inches; the CoD model frame is kept, so the entity origin is the rotor hub, not the wheels):
--   model, wreck           models (wreck: lies on the ground, origin on the ground)
--   groundZ                hub height above the ground when landed (CoD tag_ground)
--   rotorRadius            main rotor disc radius (LZ clearance)
--   health                 damage it takes before going down
--   cruiseSpeed, approachSpeed, accel, climbRate, sinkRate (u/s, u/s^2)
--   cruiseClearance        height above the LZ it flies in at (capped by the sky)
--   ropeHub                hub height above the ground for a fast-rope hover; maxRopeHub: highest it may hover
--   rotorBone, tailBone    spun on the client; tailAxis: "pitch" or "roll" (the tail rotor's spin axis in its bone)
--   doors                  { bones = { ... }, travel = Vector (local slide when open), time = seconds }
--   sound                  rotor loop
function Air.RegisterType(id, def)
	def.id = id
	Air.Types[id] = def
end

function Air.Type(id)
	return Air.Types[id or "blackhawk"]
end

-- Is the type's model installed (tif_air)?
function Air.Available(id)
	local def = Air.Type(id)
	return def ~= nil and util.IsValidModel(def.model)
end

Air.RegisterType("blackhawk", {
	name = "UH-60 Black Hawk",
	model = "models/tif_air/blackhawk.mdl",
	wreck = "models/tif_air/blackhawk_dst.mdl",
	groundZ = 163.3,
	rotorRadius = 345,
	health = 3000,
	cruiseSpeed = 1300,
	approachSpeed = 700,
	accel = 380,
	climbRate = 320,
	sinkRate = 260,
	cruiseClearance = 1200,
	-- (the MW19 rappel clips are made for a hub 920 above the ground; higher hovers warp the drop)
	ropeHub = 920,
	maxRopeHub = 1050,
	rotorBone = "main_rotor_jnt",
	tailBone = "tail_rotor_jnt",
	tailAxis = "pitch",
	-- (MW19 est_blima_doors_open / door_open clips: the cabin doors slide 61-69 back, 1.6 s)
	doors = { bones = { "side_door_l_jnt", "side_door_r_jnt" }, travel = Vector(-64, 0, 0), time = 1.6 },
	-- Seat sets (TIF_AIR_INFIL) that fly the whole way with the doors open: the landed set sits in the doorways.
	doorsOpenSets = { land = true },
	ropeTags = { "tag_fastrope_le", "tag_fastrope_ri" },
	sound = "npc/attack_helicopter/aheli_rotor_loop1.wav",
})

-- MH-6 Little Bird: six on the outside benches; lands only (no ropes). Light, fast, fragile.
Air.RegisterType("littlebird", {
	name = "MH-6 Little Bird",
	model = "models/tif_air/littlebird.mdl",
	wreck = "models/tif_air/littlebird_dst.mdl",
	groundZ = 113.2,
	rotorRadius = 170,
	health = 1400,
	cruiseSpeed = 1500,
	approachSpeed = 800,
	accel = 480,
	climbRate = 380,
	sinkRate = 300,
	cruiseClearance = 1000,
	rotorBone = "bone_66ebfc78",
	tailBone = "tag_tail_rotor_rot",
	tailAxis = "pitch",
	sound = "npc/attack_helicopter/aheli_rotor_loop1.wav",
})

-- Mi-8 / Mi-17: twelve aboard (+ a juggernaut seat), out the front doors and the open back, or down four ropes.
-- Big and slow, takes a lot of damage.
Air.RegisterType("mi8", {
	name = "Mi-8",
	model = "models/tif_air/mi8.mdl",
	wreck = "models/tif_air/mi8_dst.mdl",
	groundZ = 165.2,
	rotorRadius = 415,
	health = 4500,
	cruiseSpeed = 1150,
	approachSpeed = 600,
	accel = 300,
	climbRate = 260,
	sinkRate = 220,
	cruiseClearance = 1300,
	-- (the MW19 fast-rope clips are made for a hub 690 above the ground)
	ropeHub = 690,
	maxRopeHub = 800,
	rotorBone = "main_rotor_jnt",
	tailBone = "tail_rotor_jnt",
	tailAxis = "pitch",
	-- (no door clip for the Mi-8 in the MW19 set: slide back about a door's width; check in game)
	doors = { bones = { "side_door_l_jnt", "side_door_r_jnt" }, travel = Vector(-36, 0, 0), time = 1.4 },
	ropeTags = { "tag_fastrope_front_le", "tag_fastrope_front_ri", "tag_fastrope_back_le", "tag_fastrope_back_ri" },
	sound = "npc/attack_helicopter/aheli_rotor_loop1.wav",
})

-- CH-53 heavy (MWII heli_palfa, ramp-down export; 0.29.0): twelve aboard, out the front doors and down the ramp, or
-- down four ropes (front side windows, back of the ramp). Borrows the Mi-8's passenger clips (heli_infil_data.py).
-- Biggest and slowest; needs a big clearing to land (else it ropes).
Air.RegisterType("heavy", {
	name = "CH-53 heavy",
	model = "models/tif_air/heavy.mdl",
	wreck = "models/tif_air/heavy_dst.mdl",
	groundZ = 249.4,
	rotorRadius = 470,
	health = 6000,
	cruiseSpeed = 1100,
	approachSpeed = 550,
	accel = 260,
	climbRate = 230,
	sinkRate = 200,
	cruiseClearance = 1400,
	-- (the borrowed Mi-8 rope clips, shifted onto its rope points, end ~760 under the hub)
	ropeHub = 760,
	maxRopeHub = 870,
	rotorBone = "bone_66ebfc78",
	tailBone = "tag_tail_rotor_rot",
	tailAxis = "pitch",
	ropeTags = { "bone_578d27c4", "bone_777e4f9a", "bone_352e9a26", "bone_54ee2530" },
	sound = "npc/attack_helicopter/aheli_rotor_loop1.wav",
})

-- Every type whose model is installed.
function Air.AvailableTypes()
	local out = {}
	for id in pairs(Air.Types) do if Air.Available(id) then out[#out + 1] = id end end
	table.sort(out)
	return out
end
