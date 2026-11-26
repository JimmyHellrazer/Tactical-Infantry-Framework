-- Cover finding.
-- Candidates come from navmesh areas around a centre. Each is tested against the threat with
-- traces: is there a wall between it and the threat at waist height, is it high or low, is there
-- room to stand, is there an edge to lean around, is the soldier hidden from the threat, and can
-- it shoot from the pop-out position. Results are cached per grid cell and threat direction so
-- soldiers share the work. Points are reserved so two soldiers never take the same spot.

local TIF = TIF
local Budget = TIF.Budget
local Prof = TIF.Prof

TIF.Cover = TIF.Cover or {}
local C = TIF.Cover

C.HUG = 20             -- distance from wall to the soldier's origin
C.WAIST = 30
C.CHEST = 44           -- second detection height, for obstacles that are open underneath
C.HEAD = 60
C.EDGE_STEP = 36       -- how far along the wall an edge is looked for
C.EXCLUSION = 56       -- min distance between two soldiers' cover points
C.CACHE_TIME = 20
C.MAX_TRACES = 110     -- per search: ~40 to find obstacles, the rest to judge them
C.MAX_CANDIDATES = 16

-- World and props block; players and NPCs don't count as cover.
C.MASK = bit.bor(CONTENTS_SOLID, CONTENTS_MOVEABLE, CONTENTS_WINDOW, CONTENTS_GRATE)

C.Cache = C.Cache or {}
C.Reserved = C.Reserved or {}   -- key -> { npc, pos }
C.Recent = C.Recent or {}       -- evaluated points, for the debug overlay
C.RecentRays = C.RecentRays or {} -- obstacle-finding rays: kind 1 counts, 2 faces the threat, 0 missed

local tr, hullOut = {}, {}
local trace = { output = tr, mask = C.MASK }
local hull = { output = hullOut, mask = C.MASK, mins = Vector(-13, -13, 4), maxs = Vector(13, 13, 46) }

local VEC_WAIST = Vector(0, 0, C.WAIST)
local VEC_CHEST = Vector(0, 0, C.CHEST)
local VEC_HEAD = Vector(0, 0, C.HEAD)
local VEC_24, VEC_34, VEC_40, VEC_56, VEC_60, VEC_62, VEC_64, VEC_120 =
	Vector(0, 0, 24), Vector(0, 0, 34), Vector(0, 0, 40), Vector(0, 0, 56),
	Vector(0, 0, 60), Vector(0, 0, 62), Vector(0, 0, 64), Vector(0, 0, 120)

local math_floor, math_abs, math_max, math_min = math.floor, math.abs, math.max, math.min

local function line(a, b)
	trace.start, trace.endpos = a, b
	util.TraceLine(trace)
	return tr
end

local function blocked_before(a, b, margin)
	local t = line(a, b)
	return t.Hit and (1 - t.Fraction) * a:Distance(b) > margin
end
local function reaches(a, b, margin)
	local t = line(a, b)
	return not t.Hit or (1 - t.Fraction) * a:Distance(b) < margin
end

local function flat(v)
	local f = Vector(v.x, v.y, 0)
	f:Normalize()
	return f
end

local function yaw_dir(yaw)
	local r = math.rad(yaw)
	return Vector(math.cos(r), math.sin(r), 0)
end

local function cell_key(p, threat)
	local yaw = (threat - p):Angle().y
	local d2 = p:DistToSqr(threat)
	local band = d2 < 360000 and 0 or (d2 < 2250000 and 1 or 2)
	return math_floor(p.x / 40) .. ":" .. math_floor(p.y / 40) .. ":" .. math_floor(p.z / 64) .. ":"
		.. math_floor(((yaw + 360) % 360) / 22.5) .. ":" .. band
end

local function record(pt)
	if not TIF.Dev then return end
	local r = C.Recent
	r[#r + 1] = pt
	if #r > 160 then table.remove(r, 1) end
end

local function spend(traces, n)
	traces.n = traces.n + n
	return Budget.Take("cover_trace", n)
end

local function evaluate(p, threat, threatEye, traces)
	local pt = { probe = p, time = CurTime() }
	local dir = flat(threat - p)

	if not spend(traces, 1) then pt.reject = "budget" return pt end
	local pWaist = p + VEC_WAIST
	local w = line(pWaist, pWaist + dir * 90)
	local wallOk = w.Hit and not w.HitSky and math_abs(w.HitNormal.z) <= 0.55
	if not wallOk then
		if not spend(traces, 1) then pt.reject = "budget" return pt end
		local pChest = p + VEC_CHEST
		w = line(pChest, pChest + dir * 90)
		wallOk = w.Hit and not w.HitSky and math_abs(w.HitNormal.z) <= 0.55
	end
	if not wallOk then pt.reject = "no wall" return pt end
	local n = flat(w.HitNormal)
	if n:Dot(-dir) < 0.35 then pt.reject = "wall angled away" return pt end
	pt.normal = n
	pt.ny = n:Angle().y
	pt.material = IsValid(w.Entity) and (w.Entity.IsGlideVehicle and "vehicle" or "prop") or "world"
	pt.ent = IsValid(w.Entity) and w.Entity or nil

	local origin = w.HitPos + n * C.HUG
	if not spend(traces, 1) then pt.reject = "budget" return pt end
	local g = line(origin + VEC_24, origin - VEC_64)
	if not g.Hit then pt.reject = "no ground" return pt end
	origin = Vector(g.HitPos)
	pt.pos = origin
	if not IsValid(navmesh.GetNearestNavArea(origin, false, 72, false, true)) then pt.reject = "off navmesh" return pt end

	if not spend(traces, 1) then pt.reject = "budget" return pt end
	hull.start, hull.endpos = origin, origin
	local h = util.TraceHull(hull)
	if h.Hit or h.StartSolid then pt.reject = "no room" return pt end

	if not spend(traces, 1) then pt.reject = "budget" return pt end
	local oHead = origin + VEC_HEAD
	local wallBack = n * (C.HUG + 24)
	local head = line(oHead, oHead - wallBack)
	pt.high = head.Hit
	if not pt.high then
		if not spend(traces, 1) then pt.reject = "budget" return pt end
		local oChest = origin + VEC_CHEST
		pt.mid = line(oChest, oChest - wallBack).Hit
	end

	local tL, tR = yaw_dir(pt.ny - 90), yaw_dir(pt.ny + 90)
	local probeZ = pt.high and VEC_HEAD or VEC_WAIST
	if not spend(traces, 2) then pt.reject = "budget" return pt end
	local sL = origin + tL * C.EDGE_STEP + probeZ
	pt.edgeL = not line(sL, sL - wallBack).Hit
	local sR = origin + tR * C.EDGE_STEP + probeZ
	pt.edgeR = not line(sR, sR - wallBack).Hit

	if not spend(traces, 1) then pt.reject = "budget" return pt end
	pt.protected = blocked_before(threatEye, origin + (pt.high and VEC_56 or VEC_34), 6)
	if not pt.protected then pt.reject = "exposed" return pt end

	if not spend(traces, 1) then pt.reject = "budget" return pt end
	local target = threat + VEC_40
	if not pt.high then
		pt.canShoot = reaches(origin + VEC_62, target, 40)
		pt.shootFrom = "over"
	else
		local side = tL:Dot(dir) >= tR:Dot(dir) and "l" or "r"
		local edge = side == "l" and pt.edgeL or pt.edgeR
		if not edge then
			side = side == "l" and "r" or "l"
			edge = side == "l" and pt.edgeL or pt.edgeR
		end
		if edge then
			local t = side == "l" and tL or tR
			pt.canShoot = reaches(origin + t * 40 + VEC_60, target, 40)
			pt.shootFrom = side
		else
			pt.canShoot = false
		end
	end
	return pt
end

local COVER_CLASSES = { prop_physics = true, prop_physics_multiplayer = true, prop_dynamic = true, prop_dynamic_override = true }

-- Could this entity shield a soldier? Props between knee and above-head height, wide enough, and vehicles.
function C.IsCoverEntity(ent)
	if not IsValid(ent) then return false end
	if ent.IsGlideVehicle or ent.tifCover then return true end
	if not COVER_CLASSES[ent:GetClass()] then return false end
	local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
	local h = maxs.z - mins.z
	local w = math.max(maxs.x - mins.x, maxs.y - mins.y)
	return h >= 28 and w >= 20
end

local function too_close_to_reserved(pos, npc)
	for _, r in pairs(C.Reserved) do
		if r.npc ~= npc and IsValid(r.npc) and r.pos:DistToSqr(pos) < C.EXCLUSION * C.EXCLUSION then return true end
	end
	return false
end

local function score(pt, npc, threat)
	local arch = npc.tifArch
	local s, why = 0, {}
	if pt.canShoot then s = s + 3 why[#why + 1] = "can shoot" else s = s + 0.3 why[#why + 1] = "hide only" end
	local d = pt.pos:Distance(threat)
	local lo, hi = arch.prefRange[1], arch.prefRange[2]
	local off = d < lo and lo - d or (d > hi and d - hi or 0)
	s = s - off / 400
	if off > 0 then why[#why + 1] = string.format("%d off range", off) end
	local travel = npc:GetPos():Distance(pt.pos)
	s = s - travel / 350
	why[#why + 1] = string.format("%du away", travel)
	if pt.high and pt.canShoot then s = s + 0.4 end
	if pt.material == "vehicle" then s = s - 0.3 why[#why + 1] = "vehicle" end
	-- Placed fortifications (sandbags, HESCO; TIF.API.MarkCover) are built for this: taken first.
	if pt.ent and pt.ent.tifCover then s = s + 1.5 why[#why + 1] = "fortification" end
	-- Moving toward the threat to reach it is riskier for cautious soldiers.
	local to = flat(pt.pos - npc:GetPos())
	if travel > 120 and to:Dot(flat(threat - npc:GetPos())) > 0.6 then
		s = s - (1 - arch.aggression) * 1.2
		why[#why + 1] = "toward enemy"
	end
	for _, other in ipairs(TIF.Soldiers) do
		if other ~= npc and IsValid(other) and other:GetPos():DistToSqr(pt.pos) < 80 * 80 then
			s = s - 2
			why[#why + 1] = "crowded"
			break
		end
	end
	return s, table.concat(why, ", ")
end

-- Best cover against threat near center. Returns the point or nil.
-- opts: center, radius, maxTravel
function C.Find(npc, threat, opts)
	opts = opts or {}
	Prof.Begin("cover")
	local now = CurTime()
	local center = opts.center or npc:GetPos()
	local radius = opts.radius or 700
	local threatEye = threat + Vector(0, 0, 60)
	local traces = { n = 0 }
	local stats = {}

	-- Candidates: cast waist-height rays toward the threat side and keep whatever they hit
	-- (walls, low walls, crates, vehicles). Each spot is placed BEHIND the obstacle as seen from
	-- the threat, so the obstacle is between them. (Placing it in front of the face the ray hit
	-- only works for long walls; a narrow crate hit at an angle would miss the line to the threat.)
	local probes = {}
	local seen = {}
	local function add_probe(p, z)
		p.z = z
		local k = math.floor(p.x / 32) .. ":" .. math.floor(p.y / 32)
		if not seen[k] then
			seen[k] = true
			probes[#probes + 1] = p
		end
	end
	local function fan(origin, yawCenter, spread, count, len)
		local low, high = origin + Vector(0, 0, C.WAIST), origin + Vector(0, 0, C.CHEST)
		-- Never look past the threat: walls behind it can't shield us from it.
		len = math.min(len, math.max(80, origin:Distance(threat) - 40))
		for i = 0, count - 1 do
			if traces.n >= C.MAX_TRACES * 0.45 then return end
			local yaw = yawCenter + (count == 1 and 0 or (i / (count - 1) - 0.5) * spread)
			local dir = Vector(math.cos(math.rad(yaw)), math.sin(math.rad(yaw)), 0)
			-- Alternate heights so both solid low walls and raised desks/tables are found.
			local start = (i % 2 == 0) and low or high
			traces.n = traces.n + 1
			if not Budget.Take("cover_trace", 1) then return end
			local h = line(start, start + dir * len)
			local hit = Vector(h.HitPos)
			local face = flat(h.HitNormal)
			local toThreatHere = flat(threat - hit)
			local solid = h.Hit and not h.StartSolid and not h.HitSky and math_abs(h.HitNormal.z) < 0.55 and h.Fraction > 0.02
			local ok = solid and face:Dot(toThreatHere) <= 0.1
			if TIF.Dev then
				local rays = C.RecentRays
				rays[#rays + 1] = { a = Vector(start), b = hit, kind = ok and 1 or (solid and 2 or 0), time = now }
				if #rays > 300 then table.remove(rays, 1) end
			end
			if ok then
				add_probe(hit - toThreatHere * (C.HUG - 4), origin.z)
			end
		end
	end
	local toThreat = (threat - center):Angle().y
	-- Wide fan from the soldier, then narrower fans from points to each side and halfway forward,
	-- to find cover the soldier itself can't "see" from where it stands.
	fan(center, toThreat, 200, 18, radius)
	local fwd, side = yaw_dir(toThreat), yaw_dir(toThreat + 90)
	for _, off in ipairs({ side * radius * 0.45, -side * radius * 0.45, fwd * radius * 0.35 }) do
		local o = center + off
		local g = line(o + Vector(0, 0, 40), o - Vector(0, 0, 120))
		if g.Hit and not g.StartSolid then fan(Vector(g.HitPos), toThreat, 110, 6, radius * 0.6) end
	end
	-- Props and vehicles nearby are looked up directly (no traces), so a narrow crate between
	-- two rays isn't missed: one probe behind each, as seen from the threat.
	-- Nearest first.
	table.sort(probes, function(a, b) return a:DistToSqr(center) < b:DistToSqr(center) end)

	-- Props and vehicles nearby are looked up directly (no traces), so a narrow crate between
	-- two rays isn't missed: one probe behind each, as seen from the threat. They go first in the
	-- list so the candidate limit can't crowd them out.
	local toT = flat(threat - center)
	local propProbes = {}
	for _, ent in ipairs(ents.FindInSphere(center, radius)) do
		if C.IsCoverEntity(ent) then
			local c = ent:WorldSpaceCenter()
			-- Skip what's behind the soldier or right next to the threat.
			if flat(c - center):Dot(toT) > -0.3 and c:DistToSqr(threat) > 120 * 120 then
				local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
				local half = math.max(maxs.x - mins.x, maxs.y - mins.y) * 0.5
				local p = c - flat(threat - c) * math.min(half + C.HUG - 4, 120)
				p.z = center.z
				local k = math.floor(p.x / 32) .. ":" .. math.floor(p.y / 32)
				if not seen[k] then
					seen[k] = true
					propProbes[#propProbes + 1] = p
				end
			end
		end
	end
	table.sort(propProbes, function(a, b) return a:DistToSqr(center) < b:DistToSqr(center) end)
	stats.props = #propProbes
	for _, p in ipairs(probes) do propProbes[#propProbes + 1] = p end
	probes = propProbes

	local best, bestScore
	local tested = 0
	for _, p in ipairs(probes) do
		if tested >= C.MAX_CANDIDATES or traces.n >= C.MAX_TRACES then break end
		tested = tested + 1
		local key = cell_key(p, threat)
		local cached = C.Cache[key]
		local pt
		-- The key only holds the rough direction to the threat; far away one slice is ~1000 units
		-- wide. Reuse a judged spot only if the threat is still near where it was judged from.
		local fresh = cached and now - cached.time < C.CACHE_TIME and cached.threat
			and cached.threat:DistToSqr(threat) < math.max(100, 0.04 * p:Distance(threat)) ^ 2
		if fresh then
			pt = cached
			Prof.Count("cover_cache_hits", 1)
		else
			pt = evaluate(p, threat, threatEye, traces)
			pt.key = key
			pt.threat = Vector(threat)
			if pt.reject ~= "budget" then C.Cache[key] = pt end
			record(pt)
		end
		local why = pt.reject or "usable"
		stats[why] = (stats[why] or 0) + 1
		if not pt.reject then
			local unreachable = false
			for _, a in ipairs(opts.avoid or {}) do
				if a:DistToSqr(pt.pos) < 64 * 64 then unreachable = true break end
			end
			if unreachable then
				pt.lastReject = "unreachable"
				stats.unreachable = (stats.unreachable or 0) + 1
			elseif too_close_to_reserved(pt.pos, npc) then
				pt.lastReject = "taken"
			elseif opts.maxTravel and npc:GetPos():DistToSqr(pt.pos) > opts.maxTravel * opts.maxTravel then
				pt.lastReject = "too far"
			else
				local s, sw = score(pt, npc, threat)
				pt.score, pt.why = s, sw
				if not bestScore or s > bestScore then best, bestScore = pt, s end
			end
		end
	end
	Prof.Count("cover_searches", 1)
	Prof.Count("cover_traces", traces.n)
	Prof.End()
	if best then best.chosenBy, best.chosenAt = npc, now end
	stats.obstacles, stats.tested, stats.traces = #probes, tested, traces.n
	C.LastStats = stats
	return best, stats
end

-- Re-check one point against a (moved) threat. Cheap: 1-2 traces.
function C.StillGood(pt, threat)
	if not Budget.Take("trace", 1) then return true end
	if not blocked_before(threat + VEC_60, pt.pos + (pt.high and VEC_56 or VEC_34), 6) then
		return false, "exposed"
	end
	local dir = flat(threat - pt.pos)
	if pt.normal:Dot(-dir) < 0.25 then return false, "flanked" end
	return true
end

function C.Reserve(pt, npc)
	C.Release(npc)
	C.Reserved[pt.key] = { npc = npc, pos = pt.pos }
	npc.tifCoverKey = pt.key
end

function C.Release(npc)
	local k = npc.tifCoverKey
	if k and C.Reserved[k] and C.Reserved[k].npc == npc then C.Reserved[k] = nil end
	npc.tifCoverKey = nil
end

-- Drop stale cache entries and dead reservations.
timer.Create("tif_cover_gc", 5, 0, function()
	local now = CurTime()
	for k, pt in pairs(C.Cache) do
		if now - pt.time > C.CACHE_TIME * 2 then C.Cache[k] = nil end
	end
	for k, r in pairs(C.Reserved) do
		if not IsValid(r.npc) or r.npc.tifDead then C.Reserved[k] = nil end
	end
end)
