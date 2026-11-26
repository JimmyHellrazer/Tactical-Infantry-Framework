local TIF = TIF
local Air = TIF.Air

CreateConVar("tif_heli_health_scale", "1", FCVAR_ARCHIVE, "Helicopter health multiplier")

Air.Active = Air.Active or {}

function Air.Forget(heli)
	for i = #Air.Active, 1, -1 do
		if Air.Active[i] == heli or not IsValid(Air.Active[i]) then
			table.remove(Air.Active, i)
		end
	end
end

function Air.List()
	Air.Forget(NULL)
	return Air.Active
end

local function trace(start, endpos, mask, filter)
	return util.TraceLine({ start = start, endpos = endpos, mask = mask or MASK_SOLID, filter = filter })
end

local function hull(start, endpos, half, zlo, zhi, mask)
	return util.TraceHull({ start = start, endpos = endpos, mins = Vector(-half, -half, zlo), maxs = Vector(half, half, zhi),
		mask = mask or MASK_SOLID })
end

local function ceiling(pos)
	local tr = trace(pos + Vector(0, 0, 32), pos + Vector(0, 0, 30000), MASK_SOLID_BRUSHONLY)
	return tr.HitPos.z
end

function Air.CheckLZ(pos, typeId, want, ropeHub)
	local def = Air.Type(typeId)
	if not def then return nil, "unknown helicopter type" end

	want = want or "auto"
	local g = trace(pos + Vector(0, 0, 64), pos - Vector(0, 0, 4000))
	if not g.Hit then return nil, "no ground" end
	if g.HitSky then return nil, "sky" end

	local ground = g.HitPos
	local ceil = ceiling(ground)
	local R = def.rotorRadius

	local function can_land()
		if g.HitNormal.z < 0.93 then return false, "slope" end

		for _, o in ipairs({ Vector(170, 0, 0), Vector(-170, 0, 0), Vector(0, 110, 0), Vector(0, -110, 0),
			Vector(240, 90, 0), Vector(-240, -90, 0), Vector(240, -90, 0), Vector(-240, 90, 0) }) do
			local t = trace(ground + o + Vector(0, 0, 60), ground + o - Vector(0, 0, 80))
			if not t.Hit or math.abs(t.HitPos.z - ground.z) > 24 then
				return false, "uneven ground"
			end
		end

		if ceil < ground.z + def.groundZ + 400 then
			return false, "no room above"
		end

		local top = math.min(ceil - 20, ground.z + def.groundZ + 500)
		local body = hull(Vector(ground.x, ground.y, top), ground + Vector(0, 0, 30), 260, 0, 8)
		if body.Hit then return false, "something in the way" end

		local disc = hull(Vector(ground.x, ground.y, top), Vector(ground.x, ground.y, ground.z + def.groundZ - 40), R, 0, 8)
		if disc.Hit then return false, "no room for the rotor" end

		return true
	end

	local landWhy
	if want ~= "rope" then
		local ok, why = can_land()
		if ok then
			return { mode = "land", ground = ground, hubZ = ground.z + def.groundZ, normal = g.HitNormal }
		end

		if want == "land" then return nil, why end

		landWhy = why
	end

	if not def.ropeHub then
		return nil, (landWhy and (landWhy .. "; ") or "") .. "the " .. def.name .. " can't rope down"
	end

	local rh = ropeHub or def.ropeHub
	local maxRh = rh + ((def.maxRopeHub or def.ropeHub) - def.ropeHub)

	local top = ceil - 60
	if top < ground.z + rh then return nil, "no room above for a hover" end

	local col = hull(Vector(ground.x, ground.y, top), ground + Vector(0, 0, 8), R, 0, 8)
	local obstacle = col.Hit and col.HitPos.z or ground.z
	local hubZ = math.max(ground.z + rh, obstacle + 130)
	if hubZ - ground.z > maxRh then return nil, "too cluttered for a fast-rope" end
	if hubZ > top then return nil, "no room above for a hover" end

	return { mode = "rope", ground = ground, hubZ = hubZ, normal = g.HitNormal }
end

local DIRS = 16
local MAX_DIST = 12000
local EXIT_DIST = 40000
local MIN_DIST = 1800

local function clear_run(from, yaw, def, maxDist)
	maxDist = maxDist or MAX_DIST
	local dir = Angle(0, yaw, 0):Forward()
	local R = def.rotorRadius + 30
	local tr = hull(from, from + dir * maxDist, R, -def.groundZ - 20, 90, MASK_NPCSOLID_BRUSHONLY)
	if tr.StartSolid then return 0 end

	return tr.Fraction * maxDist
end

local GLIDE_ANGLES = { 12, 20, 35 }
Air.SETTLE = { land = 70, rope = 40 }

local function glide(lz, def, inDir, cruiseZ, settle)
	local H = cruiseZ - (lz.hubZ + settle)
	if H <= 60 then return nil end

	local R = def.rotorRadius
	for _, ang in ipairs(GLIDE_ANGLES) do
		local D = H / math.tan(math.rad(ang))
		local ok = true
		local prev = Vector(lz.ground.x, lz.ground.y, lz.hubZ + settle)

		for k = 1, 8 do
			local d = D * k / 8
			local p = Vector(lz.ground.x, lz.ground.y, lz.hubZ + settle) + inDir * d
			p.z = lz.hubZ + settle + H * (d / D)
			local tr = hull(prev, p, R * 0.9, -def.groundZ + 30, 60, MASK_SOLID)

			if tr.Hit then
				ok = false
				break
			end

			prev = p
		end

		if ok then return D, ang end
	end

	return nil
end

function Air.PlanRoute(lz, def, opts)
	opts = opts or {}
	local ceilZ = ceiling(lz.ground)
	local cruiseZ = math.min(lz.ground.z + def.cruiseClearance, ceilZ - 160)
	if cruiseZ < lz.hubZ + 150 then return nil, "no room to fly in" end

	local top = Vector(lz.ground.x, lz.ground.y, cruiseZ)

	if hull(top, Vector(lz.ground.x, lz.ground.y, lz.hubZ + 10), def.rotorRadius, -20, 20, MASK_SOLID).Hit then
		return nil, "the way down is blocked"
	end

	local runs = {}
	local base = opts.fromYaw or math.Rand(0, 360)

	for k = 0, DIRS - 1 do
		local yaw = base + k * 360 / DIRS
		runs[#runs + 1] = { yaw = yaw, dist = clear_run(top, yaw, def), k = k }
	end

	local best
	for _, r in ipairs(runs) do
		if r.dist >= MIN_DIST and (not best or (opts.fromYaw and r.k == 0) or r.dist > best.dist + 500) then
			best = r
			if opts.fromYaw and r.k == 0 then break end
		end
	end

	if not best then return nil, "no clear way in" end

	local inDir = Angle(0, best.yaw, 0):Forward()
	local entry = top + inDir * math.max(MIN_DIST - 300, best.dist - 400)
	local heading = (-inDir):Angle().y

	local out, outD
	for _, r in ipairs(runs) do
		local d = clear_run(top, r.yaw, def, EXIT_DIST)
		r.exitDist = d
		local ahead = math.abs(math.AngleDifference(r.yaw, best.yaw + 180)) < 50
		local score = d * (ahead and 1.1 or 1)

		if d >= MIN_DIST and (not out or score > outD) then
			out, outD = r, score
		end
	end

	out = out or best
	local exit = top + Angle(0, out.yaw, 0):Forward() * math.max(MIN_DIST - 300, (out.exitDist or out.dist) - 400)
	local settle = Air.SETTLE[lz.mode] or 0
	local glideD, glideAng

	if lz.mode ~= "flyby" then
		glideD, glideAng = glide(lz, def, inDir, cruiseZ, settle)
	end

	return {
		glideD = glideD, glideAng = glideAng, settle = settle,
		entry = entry,
		app = top,
		hub = Vector(lz.ground.x, lz.ground.y, lz.hubZ),
		ground = lz.ground,
		exit = exit,
		heading = heading,
		cruiseZ = cruiseZ,
		ceilZ = ceilZ,
		mode = lz.mode,
	}
end

function Air.Call(opts)
	local typeId = opts.type or "blackhawk"
	local def = Air.Type(typeId)
	if not def then return nil, "unknown helicopter type" end

	if not Air.Available(typeId) then
		return nil, "model not installed (tif_air addon)"
	end

	local mode = opts.mode or "auto"
	local P = opts.passengers

	local ropeSet, ropeId
	if P and mode ~= "flyby" and TIF.AirRide then
		ropeSet, ropeId = TIF.AirRide.SetFor(typeId, "rope", P.set)
		local hasLand = TIF.AirRide.SetFor(typeId, "land", P.set) ~= nil

		if mode == "auto" and not hasLand and ropeSet then
			mode = "rope"
		end

		if mode == "auto" and not ropeSet and hasLand then
			mode = "land"
		end
	end

	local lz, why
	if mode == "flyby" then
		local g = trace(opts.pos + Vector(0, 0, 64), opts.pos - Vector(0, 0, 4000))
		if not g.Hit then return nil, "no ground" end

		lz = { mode = "flyby", ground = g.HitPos, hubZ = g.HitPos.z + def.cruiseClearance * 0.6 }
	else
		lz, why = Air.CheckLZ(opts.pos, typeId, mode, ropeSet and ropeSet.hub)
		if not lz then return nil, why end
	end

	local route
	route, why = Air.PlanRoute(lz, def, opts)
	if not route then return nil, why end

	local set, setId
	if P and lz.mode ~= "flyby" then
		if lz.mode == "rope" and ropeSet then
			set, setId = ropeSet, ropeId
		else
			set, setId = TIF.AirRide.SetFor(typeId, lz.mode, P.set)
		end

		if not set then
			return nil, "no passenger seats for a " .. lz.mode .. " drop on this helicopter"
		end
	end

	route.hold = opts.hold

	if route.hold == nil and not opts.holdUntilRelease and not set then
		route.hold = lz.mode == "land" and 8 or 10
	end

	route.onArrive, route.onDestroyed, route.onEmpty = opts.onArrive, opts.onDestroyed, opts.onEmpty

	route.doorsOpen = (setId and def.doorsOpenSets and def.doorsOpenSets[setId]) or nil
	route.setId = setId

	if lz.mode == "flyby" then
		route.app = route.hub
	end

	local heli = ents.Create("tif_heli")
	if not IsValid(heli) then return nil, "couldn't create the entity" end

	heli:SetHeliType(typeId)
	heli:SetPos(route.entry)
	heli:SetAngles(Angle(0, (route.app - route.entry):Angle().y, 0))
	heli:Spawn()
	heli:Activate()
	if not IsValid(heli) then return nil, "spawn failed" end

	heli:SetRoute(route)

	heli.v = (route.app - route.entry):GetNormalized() * def.cruiseSpeed * 0.8
	heli.v.z = 0
	heli.tifFaction = opts.faction or (P and P.faction)

	heli:SetNW2String("tif_crew_set", setId or "")
	heli:SetNW2String("tif_crew_fac", heli.tifFaction or "usmc")
	table.insert(Air.Active, heli)

	if set then
		local riders, sq = P.soldiers, nil
		if not riders then
			local n = math.min(P.count or math.min(#set.men, 12), #set.men)
			local arch = P.archetypes or {}

			if #arch == 0 then
				for i = 1, n do
					arch[i] = TIF.SquadMix[i] or "rifleman"
				end
			end

			local pts = {}
			for i = 1, #arch do
				pts[i] = heli:GetPos()
			end

			sq, riders = TIF.API.SpawnSquad(P.faction or "usmc", heli:GetPos(), arch, { tight = true, points = pts })
		else
			sq = riders[1] and riders[1].tifSquad
		end

		local boarded = TIF.AirRide.Board(heli, riders, set, setId, P.style)

		for i = boarded + 1, #riders do
			if IsValid(riders[i]) and not riders[i].tifHeli and not P.soldiers then
				riders[i]:Remove()
			end
		end

		heli.tifSquad = sq
		heli.tifAutoLeave = not opts.holdUntilRelease
		heli.tifOrder = P.order
	end

	return heli, lz.mode
end

hook.Add("TIF_HeliEmpty", "tif_air_squad_order", function(heli)
	local sq = heli.tifSquad
	if not sq or not TIF.Squad.Members or #TIF.Squad.Members(sq) == 0 then
		return
	end

	local o = heli.tifOrder
	if o then
		TIF.Squad.SetOrder(sq, o.kind or "advance", o.pos, o.yaw, o.opts)
	else
		local r = heli.route
		TIF.Squad.SetOrder(sq, "hold", r and r.ground or heli:GetPos(), r and r.heading or nil)
	end
end)

TIF.API = TIF.API or {}
local API = TIF.API

function API.CallHeli(opts)
	return Air.Call(opts or {})
end

function API.HeliRelease(heli)
	if IsValid(heli) and heli.Release then
		heli:Release()
	end
end

function API.CheckLZ(pos, typeId, want)
	return Air.CheckLZ(pos, typeId, want)
end

function API.Helis()
	return Air.List()
end
