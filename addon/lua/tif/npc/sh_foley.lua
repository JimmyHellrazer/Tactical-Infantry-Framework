-- Soldier foley (2026-11-20, a tester: "they dont really make much sound when running about / falling over"): MW19's
-- own movement sounds (K:\SOUNDSmw19, packed by foley_pack.py into sound/tif/foley/<key>/<n>.ogg, counts in
-- sh_foley_data.lua). Shared: the surface under a point and the sound picks. The client plays what the clips mark
-- (cl_foley.lua: footsteps, gear, landings, body falls, stance changes); the server plays the corpse's and the
-- dropped gun's impacts (below), since those are real physics on the server.

TIF.Foley = TIF.Foley or {}
local F = TIF.Foley

-- The surface sets per material: { footsteps, body falls, weapon drops, going prone }.
local ROW = {
	concrete = { "concrete", "concrete_dry", "concrete", "concrete" },
	gritty = { "concrete_gritty", "concrete_gritty", "concrete", "concrete" },
	wet = { "concrete_wet", "concrete_wet", "concrete", "concrete" },
	dirt = { "dirt", "dirt", "dirt", "dirt" },
	gravel = { "gravel", "gravel", "dirt", "gravel" },
	grass = { "grass_short", "dirt", "grass", "grass" },
	foliage = { "grass_tall", "dirt", "grass", "foliage" },
	sand = { "sand", "sand", "sand", "sand" },
	snow = { "snow", "dirt", "dirt", "snow" },
	mud = { "mud", "mud", "mud", "mud" },
	wood = { "wood_solid", "wood_solid", "wood_solid", "concrete" },
	woodfloor = { "wood_floor", "wood_floor", "wood_hollow", "concrete" },
	metal = { "metal_thick", "metal_thick", "metal", "metal" },
	metalthin = { "metal_thin", "metal_thin", "metal", "metal" },
	grate = { "metal_grate", "metal_grate", "metal", "metal" },
	car = { "metal_car", "metal_car", "metal", "metal" },
	tile = { "tile", "concrete_dry", "concrete", "concrete" },
	glass = { "glass_solid", "concrete_dry", "concrete", "concrete" },
	carpet = { "carpet_solid", "carpet_solid", "carpet", "carpet" },
	rubber = { "rubber", "concrete_dry", "concrete", "concrete" },
	puddle = { "water_puddle", "water", "water", "mud" },
	ankle = { "water_ankle", "water", "water", "mud" },
	knee = { "water_knee", "water", "water", "mud" },
	waist = { "water_waist", "water", "water", "mud" },
}
F.ROW = ROW
local BY_MAT = {
	[MAT_CONCRETE or 67] = "concrete", [MAT_DIRT or 68] = "dirt", [MAT_GRASS or 85] = "grass", [MAT_SAND or 78] = "sand",
	[MAT_SNOW or 74] = "snow", [MAT_WOOD or 87] = "wood", [MAT_METAL or 77] = "metal", [MAT_GRATE or 71] = "grate",
	[MAT_VENT or 86] = "metalthin", [MAT_TILE or 84] = "tile", [MAT_GLASS or 89] = "glass", [MAT_SLOSH or 83] = "mud",
	[MAT_FOLIAGE or 79] = "foliage", [MAT_PLASTIC or 76] = "rubber", [MAT_COMPUTER or 80] = "metalthin",
	[MAT_FLESH or 70] = "dirt", [MAT_ANTLION or 65] = "dirt", [MAT_ALIENFLESH or 72] = "dirt",
}
-- Finer by surface property name (first match wins).
local BY_PROP = {
	{ "gravel", "gravel" }, { "mud", "mud" }, { "carpet", "carpet" }, { "rubber", "rubber" }, { "tile", "tile" },
	{ "chainlink", "grate" }, { "metalgrate", "grate" }, { "metalvehicle", "car" }, { "metal_box", "metalthin" },
	{ "metalpanel", "metalthin" }, { "wood_box", "woodfloor" }, { "wood_crate", "woodfloor" },
	{ "wood_plank", "woodfloor" }, { "wood_panel", "woodfloor" }, { "wood_furniture", "woodfloor" },
	{ "rock", "gritty" }, { "boulder", "gritty" }, { "brick", "gritty" }, { "plaster", "gritty" }, { "asphalt", "concrete" },
	{ "ice", "wet" }, { "slime", "mud" }, { "quicksand", "sand" }, { "snow", "snow" }, { "grass", "grass" },
}
F.BY_MAT, F.BY_PROP = BY_MAT, BY_PROP

-- The surface row name for a trace result (and nil = nothing under him).
function F.SurfaceOf(tr)
	if not (tr and tr.Hit) then return nil end
	local name = tr.SurfaceProps and util.GetSurfacePropName(tr.SurfaceProps) or ""
	name = string.lower(name or "")
	if name ~= "" then
		for _, e in ipairs(BY_PROP) do
			if string.find(name, e[1], 1, true) then return e[2] end
		end
	end
	return BY_MAT[tr.MatType] or "concrete"
end

local down = { mask = MASK_PLAYERSOLID }
-- The surface under pos (ignore: filter). Water above the ground: puddle / ankle deep.
function F.SurfaceAt(pos, ignore)
	down.start, down.endpos, down.filter = pos + Vector(0, 0, 16), pos - Vector(0, 0, 28), ignore
	down.mask = MASK_PLAYERSOLID
	local tr = util.TraceLine(down)
	local s = F.SurfaceOf(tr)
	if tr.Hit then
		down.mask = MASK_WATER
		down.start, down.endpos = tr.HitPos + Vector(0, 0, 30), tr.HitPos
		local w = util.TraceLine(down)
		if w.Hit and not w.StartSolid then
			local depth = w.HitPos.z - tr.HitPos.z
			if depth > 2 then s = depth < 9 and "puddle" or "ankle" end
		end
	end
	return s
end

-- A random file of a set, or nil when it isn't packed.
function F.Pick(key)
	local n = TIF.FoleyData and TIF.FoleyData[key]
	if not n or n < 1 then return nil end
	return "tif/foley/" .. key .. "/" .. math.random(n) .. ".ogg"
end
-- The first of several keys that exists.
function F.PickAny(...)
	for i = 1, select("#", ...) do
		local p = F.Pick((select(i, ...)))
		if p then return p end
	end
	return nil
end

-- Server: the corpse's and the dropped gun's impacts ---------------------------------------------------------------
if SERVER then
	F.BODY_TIME = 5      -- s after the ragdoll appears: its hits on the ground make body-fall sounds
	F.BODY_MIN = 70      -- impact speed for a sound
	F.BODY_GAP = 0.12    -- s between two body sounds of one corpse
	local function surf_of_hit(data)
		local name = data.TheirSurfaceProps and util.GetSurfacePropName(data.TheirSurfaceProps) or ""
		name = string.lower(name or "")
		for _, e in ipairs(BY_PROP) do if string.find(name, e[1], 1, true) then return e[2] end end
		local mat = util.GetSurfaceData and data.TheirSurfaceProps and util.GetSurfaceData(data.TheirSurfaceProps)
		return mat and BY_MAT[mat.material] or "concrete"
	end

	function F.CorpseSounds(rag)
		if not IsValid(rag) then return end
		local born, last = CurTime(), 0
		rag:AddCallback("PhysicsCollide", function(ent, data)
			local now = CurTime()
			if now - born > F.BODY_TIME or now - last < F.BODY_GAP or data.Speed < F.BODY_MIN then return end
			if IsValid(data.HitEntity) and data.HitEntity == ent then return end
			last = now
			local row = ROW[surf_of_hit(data)] or ROW.concrete
			-- (the heavy parts land as the torso, a fast hit of anything else as a large limb)
			local mass = IsValid(data.PhysObject) and data.PhysObject:GetMass() or 5
			local part = (mass >= 9 and "torso") or (data.Speed > 260 and "limb_lrg") or "limb_sm"
			local snd = F.PickAny("fall/" .. row[2] .. "/" .. part, "fall/concrete_dry/" .. part)
			if snd then ent:EmitSound(snd, 72, math.random(95, 105), math.Clamp(data.Speed / 400, 0.35, 1)) end
		end)
	end

	-- kind: TIF.GTG.WeaponKind of the dropped gun
	local DROP = { pistol = "metal_pistol", smg = "metal_smg", lmg = "lmg", rpg = "launcher", sniper = "sn",
		marksman = "sn", shotgun = "metal_ar", rifle = "metal_ar" }
	function F.GunDropSounds(prop, kind)
		if not IsValid(prop) then return end
		local born, hits = CurTime(), 0
		local set = DROP[kind or "rifle"] or "metal_ar"
		prop:AddCallback("PhysicsCollide", function(ent, data)
			if hits >= 3 or CurTime() - born > 6 or data.Speed < 60 then return end
			hits = hits + 1
			local row = ROW[surf_of_hit(data)] or ROW.concrete
			local snd = F.PickAny("drop/" .. set .. "/" .. row[3], "drop/" .. set .. "/concrete", "drop/metal_ar/concrete")
			if snd then ent:EmitSound(snd, 70, math.random(96, 104), hits == 1 and 1 or 0.55) end
		end)
	end
end
