local TIF = TIF
TIF.Air = TIF.Air or {}
local Air = TIF.Air

Air.Types = Air.Types or {}

function Air.RegisterType(id, def)
	def.id = id
	Air.Types[id] = def
end

function Air.Type(id)
	return Air.Types[id or "blackhawk"]
end

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

	ropeHub = 920,
	maxRopeHub = 1050,
	rotorBone = "main_rotor_jnt",
	tailBone = "tail_rotor_jnt",
	tailAxis = "pitch",

	doors = { bones = { "side_door_l_jnt", "side_door_r_jnt" }, travel = Vector(-64, 0, 0), time = 1.6 },

	doorsOpenSets = { land = true },
	ropeTags = { "tag_fastrope_le", "tag_fastrope_ri" },
	sound = "npc/attack_helicopter/aheli_rotor_loop1.wav",
})

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

	ropeHub = 690,
	maxRopeHub = 800,
	rotorBone = "main_rotor_jnt",
	tailBone = "tail_rotor_jnt",
	tailAxis = "pitch",

	doors = { bones = { "side_door_l_jnt", "side_door_r_jnt" }, travel = Vector(-36, 0, 0), time = 1.4 },
	ropeTags = { "tag_fastrope_front_le", "tag_fastrope_front_ri", "tag_fastrope_back_le", "tag_fastrope_back_ri" },
	sound = "npc/attack_helicopter/aheli_rotor_loop1.wav",
})

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

	ropeHub = 760,
	maxRopeHub = 870,
	rotorBone = "bone_66ebfc78",
	tailBone = "tag_tail_rotor_rot",
	tailAxis = "pitch",
	ropeTags = { "bone_578d27c4", "bone_777e4f9a", "bone_352e9a26", "bone_54ee2530" },
	sound = "npc/attack_helicopter/aheli_rotor_loop1.wav",
})

function Air.AvailableTypes()
	local out = {}
	for id in pairs(Air.Types) do if Air.Available(id) then out[#out + 1] = id end end
	table.sort(out)
	return out
end
