-- Buildings (Phase 5): doorways, rooms, stack slots and entry points, all found from the navmesh
-- and a few traces. Results are cached (the map doesn't change; door entities are re-checked).
--
--   indoor area   a nav area with a ceiling above it (trace up hits something that isn't sky)
--   doorway       a door entity, or a nav connection that passes through a gap 24-100 units wide
--                 with walls on both sides and a lintel above, with at least one indoor side.
--                 Stores centre (floor level), normal (pointing into side B), width, and the
--                 nav areas on each side.
--   room          indoor nav areas connected without passing through a doorway (flood fill,
--                 max 60 areas). Outdoors has no room (nil).

local TIF = TIF
local Move = TIF.Move

TIF.Building = TIF.Building or {}
local BLD = TIF.Building

BLD.MAX_ROOM_AREAS = 60
BLD.DOOR_CLASSES = { prop_door_rotating = true, func_door_rotating = true, func_door = true }

local tr = { mask = MASK_SOLID_BRUSHONLY }
local function line(a, b)
	tr.start, tr.endpos = a, b
	return util.TraceLine(tr)
end

local function flat(v)
	local f = Vector(v.x, v.y, 0)
	f:Normalize()
	return f
end

-- Indoor test per area, cached by area id.
BLD.IndoorCache = {}
function BLD.AreaIndoor(area)
	local id = area:GetID()
	local v = BLD.IndoorCache[id]
	if v == nil then
		local c = area:GetCenter()
		local t = line(c + Vector(0, 0, 40), c + Vector(0, 0, 420))
		v = t.Hit and not t.HitSky
		BLD.IndoorCache[id] = v
	end
	return v
end

function BLD.Indoor(pos)
	local a = navmesh.GetNearestNavArea(pos, false, 200, false, true)
	return IsValid(a) and BLD.AreaIndoor(a), a
end

-- Doorways ---------------------------------------------------------------------------

BLD.Doors = {}         -- list of doorway tables
BLD.PairsDone = {} -- "idA:idB" -> doorway or false
BLD.Crossing = {}   -- "idA:idB" -> doorway (nav connections that pass through one)

local function pair_key(a, b)
	local x, y = a:GetID(), b:GetID()
	if x > y then x, y = y, x end
	return x .. ":" .. y
end

local function find_existing(center)
	for _, d in ipairs(BLD.Doors) do
		if d.center:DistToSqr(center) < 48 * 48 then return d end
	end
	return nil
end

-- Try to find a doorway gap near p, with the passage running along dir.
local function gap_at(p, dir)
	local side = Vector(-dir.y, dir.x, 0)
	local base = p + Vector(0, 0, 48)
	local l = line(base, base + side * 72)
	local r = line(base, base - side * 72)
	if not (l.Hit and r.Hit) then return nil end
	local dl, dr = l.Fraction * 72, r.Fraction * 72
	local width = dl + dr
	if width < 24 or width > 100 then return nil end
	local center = p + side * ((dl - dr) / 2)
	local cz = center + Vector(0, 0, 48)
	-- A lintel above (doorways have tops; gaps between free-standing walls don't).
	local up = line(cz, cz + Vector(0, 0, 150))
	if not up.Hit or up.HitSky then return nil end
	-- The passage itself must be open.
	if line(cz - dir * 20, cz + dir * 20).Hit then return nil end
	-- A narrow corridor also has walls and a ceiling: a doorway's lintel is lower than the
	-- ceiling (or sky) on at least one side.
	local lintel = up.HitPos.z
	local higher = false
	for _, s in ipairs({ 1, -1 }) do
		local o = cz + dir * (s * 48)
		local c = line(o, o + Vector(0, 0, 400))
		if not c.Hit or c.HitSky or c.HitPos.z > lintel + 6 then higher = true break end
	end
	if not higher then return nil end
	return center, width
end

local function make_door(center, width, normal, areaA, areaB, ent)
	-- The sides are the areas clear of the doorway itself (the navmesh often has a small area
	-- inside the gap, which belongs to neither room).
	local sa = navmesh.GetNearestNavArea(center - normal * 72 + Vector(0, 0, 16), false, 80, false, true)
	local sb = navmesh.GetNearestNavArea(center + normal * 72 + Vector(0, 0, 16), false, 80, false, true)
	if IsValid(sa) then areaA = sa end
	if IsValid(sb) then areaB = sb end
	if areaA == areaB then return nil end
	local inA = IsValid(areaA) and BLD.AreaIndoor(areaA)
	local inB = IsValid(areaB) and BLD.AreaIndoor(areaB)
	if not inA and not inB then return nil end
	-- Normal points into side B; make B the indoor side for exterior doors.
	if inA and not inB then
		areaA, areaB = areaB, areaA
		normal = -normal
		inA, inB = inB, inA
	end
	local d = {
		id = #BLD.Doors + 1, center = center, normal = normal, width = width,
		areaA = areaA, areaB = areaB, exterior = not inA, ent = ent,
	}
	BLD.Doors[#BLD.Doors + 1] = d
	return d
end

local function extents(a)
	local c0, c2 = a:GetCorner(0), a:GetCorner(2)
	return math.min(c0.x, c2.x), math.min(c0.y, c2.y), math.max(c0.x, c2.x), math.max(c0.y, c2.y)
end

-- Points along the shared edge of two adjacent (axis-aligned) nav areas, with the crossing
-- direction. Big areas meet along long edges, and a doorway can be anywhere on them.
local function edge_samples(a, b)
	local ax0, ay0, ax1, ay1 = extents(a)
	local bx0, by0, bx1, by1 = extents(b)
	local z = (a:GetCenter().z + b:GetCenter().z) / 2
	local out = {}
	local function along_y(x, sx)
		local lo, hi = math.max(ay0, by0), math.min(ay1, by1)
		if hi < lo then return end
		local n = math.min(24, math.floor((hi - lo) / 20) + 1)
		for i = 0, n - 1 do
			local y = n == 1 and (lo + hi) / 2 or lo + (hi - lo) * i / (n - 1)
			out[#out + 1] = { p = Vector(x, y, z), dir = Vector(sx, 0, 0) }
		end
	end
	local function along_x(y, sy)
		local lo, hi = math.max(ax0, bx0), math.min(ax1, bx1)
		if hi < lo then return end
		local n = math.min(24, math.floor((hi - lo) / 20) + 1)
		for i = 0, n - 1 do
			local x = n == 1 and (lo + hi) / 2 or lo + (hi - lo) * i / (n - 1)
			out[#out + 1] = { p = Vector(x, y, z), dir = Vector(0, sy, 0) }
		end
	end
	local E = 4
	if math.abs(ax1 - bx0) < E then along_y((ax1 + bx0) / 2, 1)
	elseif math.abs(bx1 - ax0) < E then along_y((bx1 + ax0) / 2, -1)
	elseif math.abs(ay1 - by0) < E then along_x((ay1 + by0) / 2, 1)
	elseif math.abs(by1 - ay0) < E then along_x((by1 + ay0) / 2, -1) end
	if #out == 0 then
		-- Not edge to edge (overlapping or diagonal): fall back to the closest points.
		local ac, bc = a:GetCenter(), b:GetCenter()
		out[1] = { p = (a:GetClosestPointOnArea(bc) + b:GetClosestPointOnArea(ac)) / 2, dir = flat(bc - ac) }
	end
	return out
end

local function scan_pair(a, b)
	local key = pair_key(a, b)
	if BLD.PairsDone[key] ~= nil then return BLD.PairsDone[key] end
	BLD.PairsDone[key] = false
	if not (BLD.AreaIndoor(a) or BLD.AreaIndoor(b)) then return false end
	for _, smp in ipairs(edge_samples(a, b)) do
		local p, dir = smp.p, smp.dir
		local center, width
		for _, off in ipairs({ 0, 12, -12 }) do
			center, width = gap_at(p + dir * off, dir)
			if center then break end
		end
		if center then
			local g = line(center + Vector(0, 0, 20), center - Vector(0, 0, 60))
			if g.Hit then center = g.HitPos end
			local d = find_existing(center) or make_door(center, width, dir, a, b)
			BLD.PairsDone[key] = d or false
			if d then BLD.Crossing[key] = d end
			return d
		end
	end
	return false
end

local function scan_door_entity(ent)
	if ent.tifDoorway then return ent.tifDoorway end
	local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
	local size = maxs - mins
	-- The thin axis is the door's normal.
	local normal = size.x < size.y and ent:GetForward() or ent:GetRight()
	normal = flat(normal)
	local width = math.max(size.x, size.y)
	local c = ent:WorldSpaceCenter()
	local g = line(c, c - Vector(0, 0, 120))
	local center = g.Hit and g.HitPos or c
	local a = navmesh.GetNearestNavArea(center - normal * 48, false, 120, false, true)
	local b = navmesh.GetNearestNavArea(center + normal * 48, false, 120, false, true)
	local d = find_existing(center) or make_door(center, width, normal, a, b, ent)
	if d then
		d.ent = ent
		ent.tifDoorway = d
		if IsValid(a) and IsValid(b) then BLD.Crossing[pair_key(a, b)] = d end
	end
	return d
end

-- Scan for doorways within radius of pos. Each nav connection is traced once per map.
function BLD.Scan(pos, radius)
	radius = radius or 1000
	for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
		if BLD.DOOR_CLASSES[ent:GetClass()] then scan_door_entity(ent) end
	end
	for _, a in ipairs(navmesh.Find(pos, radius, 200, 200)) do
		for _, b in ipairs(a:GetAdjacentAreas()) do scan_pair(a, b) end
	end
	local out = {}
	local r2 = radius * radius
	for _, d in ipairs(BLD.Doors) do
		if d.center:DistToSqr(pos) < r2 then out[#out + 1] = d end
	end
	return out
end

-- Does a nav connection pass through a doorway?
function BLD.CrossesDoor(a, b)
	return BLD.Crossing[pair_key(a, b)]
end

-- Is the door entity closed? (open doorways are never closed)
function BLD.Closed(d)
	local e = d.ent
	if not IsValid(e) then return false end
	if e:GetClass() == "prop_door_rotating" then
		local ok, st = pcall(e.GetInternalVariable, e, "m_eDoorState")
		return ok and st == 0
	end
	local ok, st = pcall(e.GetInternalVariable, e, "m_toggle_state")
	return ok and st == 1
end

function BLD.Open(d, by)
	local e = d.ent
	if not IsValid(e) then return end
	if e:GetClass() == "prop_door_rotating" and IsValid(by) then
		e:Fire("OpenAwayFrom", "!activator", 0, by)
	else
		e:Fire("Open")
	end
end

-- Rooms ------------------------------------------------------------------------------

BLD.RoomOfArea = {}
local NextRoom = 1

-- Rooms stay on one floor: the flood only takes areas within FLOOR_BAND of the start height.
-- Where it meets areas climbing out of the band (stairs), it follows them to the top or bottom
-- and records a stair link, which works like a doorway between the two floors' rooms.
BLD.FLOOR_BAND = 40

-- Follow a staircase from area `a` (just outside the band) until it levels off.
local function stair_end(a, upward)
	local cur, prev, steps = a, a, 0
	while steps < 40 do
		steps = steps + 1
		local z = cur:GetCenter().z
		local nextA, nextZ
		for _, b in ipairs(cur:GetAdjacentAreas()) do
			local bz = b:GetCenter().z
			if BLD.AreaIndoor(b) and ((upward and bz > z + 2) or (not upward and bz < z - 2)) then
				if not nextA or (upward and bz > nextZ) or (not upward and bz < nextZ) then nextA, nextZ = b, bz end
			end
		end
		if not nextA then break end
		prev, cur = cur, nextA
	end
	return cur, prev
end

-- bottom/top: the foot of the stairs and the edge of the landing (not area centres, which can
-- be far away in a big hall).
local function add_stair(bottomArea, bottom, topArea, top)
	for _, d in ipairs(BLD.Doors) do
		if d.stair and d.top:DistToSqr(top) < 80 * 80 and d.center:DistToSqr(bottom) < 120 * 120 then return d end
	end
	local d = {
		id = #BLD.Doors + 1, stair = true, center = bottom, top = top, normal = flat(top - bottom),
		width = 80, areaA = bottomArea, areaB = topArea, exterior = false,
	}
	BLD.Doors[#BLD.Doors + 1] = d
	return d
end

function BLD.RoomOf(area)
	if not IsValid(area) or not BLD.AreaIndoor(area) then return nil end
	local cached = BLD.RoomOfArea[area:GetID()]
	if cached then return cached end
	local room = { id = NextRoom, areas = {}, set = {} }
	NextRoom = NextRoom + 1
	local z0 = area:GetCenter().z
	local queue, head = { area }, 1
	local climbs = {}
	room.set[area:GetID()] = true
	while queue[head] and #room.areas < BLD.MAX_ROOM_AREAS do
		local a = queue[head]
		head = head + 1
		room.areas[#room.areas + 1] = a
		for _, b in ipairs(a:GetAdjacentAreas()) do
			local id = b:GetID()
			if not room.set[id] and BLD.AreaIndoor(b) and scan_pair(a, b) == false then
				local dz = b:GetCenter().z - z0
				if math.abs(dz) <= BLD.FLOOR_BAND then
					room.set[id] = true
					queue[#queue + 1] = b
				else
					climbs[#climbs + 1] = { from = a, to = b, up = dz > 0 }
				end
			end
		end
	end
	local c = Vector()
	for _, a in ipairs(room.areas) do c:Add(a:GetCenter()) BLD.RoomOfArea[a:GetID()] = room end
	room.center = c / math.max(1, #room.areas)
	-- Stairs out of this room, as links to the other floor.
	for _, cl in ipairs(climbs) do
		local far, last = stair_end(cl.to, cl.up)
		if math.abs(far:GetCenter().z - z0) > BLD.FLOOR_BAND * 1.5 then
			local nearPos = cl.from:GetClosestPointOnArea(cl.to:GetCenter())
			local farPos = far:GetClosestPointOnArea(last:GetCenter())
			if cl.up then add_stair(cl.from, nearPos, far, farPos)
			else add_stair(far, farPos, cl.from, nearPos) end
		end
	end
	return room
end

function BLD.RoomAt(pos)
	local a = navmesh.GetNearestNavArea(pos, false, 200, false, true)
	return BLD.RoomOf(a)
end

-- Doorways leading out of a room, with the side the room is on.
function BLD.DoorsOf(room)
	local out = {}
	for _, d in ipairs(BLD.Doors) do
		local ra, rb = BLD.RoomOf(d.areaA), BLD.RoomOf(d.areaB)
		if ra == room or rb == room then out[#out + 1] = d end
	end
	return out
end

-- The room on the far side of a doorway, coming from `room` (nil = outdoors).
function BLD.OtherSide(d, room)
	local ra, rb = BLD.RoomOf(d.areaA), BLD.RoomOf(d.areaB)
	if ra == room then return rb, 1 end
	return ra, -1
end

-- Stack slots and entry points --------------------------------------------------------------

local hull = { mask = MASK_SOLID_BRUSHONLY, mins = Vector(-13, -13, 4), maxs = Vector(13, 13, 64) }
local function free_spot(p)
	local s = Move.Snap(p)
	if not s or s:DistToSqr(p) > 40 * 40 then return nil end
	hull.start, hull.endpos = s, s
	if util.TraceHull(hull).Hit then return nil end
	return s
end

-- Slots on the approach side of a doorway: inward = direction of entry (into the target room).
-- Alternates sides (A1, B1, A2, B2...). Returns a list of { pos, side } (side +1 / -1).
function BLD.StackSlots(d, inward, n)
	local out = {}
	local side = Vector(-inward.y, inward.x, 0)
	local half = d.width / 2
	local ok = { [1] = true, [-1] = true }
	for k = 1, n do
		for _, s in ipairs({ 1, -1 }) do
			if #out < n and ok[s] then
				local p = d.center - inward * 30 + side * s * (half + 24 + (k - 1) * 34)
				local f = free_spot(p)
				if f then out[#out + 1] = { pos = f, side = s } else ok[s] = false end
			end
		end
	end
	return out
end

-- Stairs: stack at the departure end, then go up (or down) and spread through the room at the
-- other end. Returns slots, points.
function BLD.StairPlan(d, goingUp, room, n)
	local dep, arr = goingUp and d.center or d.top, goingUp and d.top or d.center
	local dir = flat(arr - dep)
	local side = Vector(-dir.y, dir.x, 0)
	local slots = {}
	for k = 1, n * 2 do
		if #slots >= n then break end
		local s = (k % 2 == 1) and 1 or -1
		local back = math.ceil(k / 2)
		local f = free_spot(dep - dir * (30 + 30 * back) + side * s * 34)
		if f then slots[#slots + 1] = { pos = f, side = s } end
	end
	for k = #slots + 1, n do
		local f = free_spot(dep - dir * (40 + 45 * k)) or Move.Snap(dep) or dep
		slots[k] = { pos = f, side = 1 }
	end
	-- Arrival point, then spread through the room's areas (at least 140 apart).
	local points = { Move.Snap(arr) or arr }
	if room then
		local list = {}
		for _, a in ipairs(room.areas) do list[#list + 1] = a:GetCenter() end
		table.sort(list, function(a, b) return a:DistToSqr(arr) < b:DistToSqr(arr) end)
		for _, p in ipairs(list) do
			if #points >= 4 then break end
			local ok = p:DistToSqr(arr) > 120 * 120
			for _, q in ipairs(points) do if q:DistToSqr(p) < 140 * 140 then ok = false break end end
			if ok then points[#points + 1] = p end
		end
	end
	while #points < 4 do points[#points + 1] = points[#points] end
	return slots, points
end

-- Points inside the room past a doorway: the two corners beside the door (crossing and
-- buttonhook), then two deeper points. inward points into the room.
function BLD.EntryPoints(d, inward, room)
	local side = Vector(-inward.y, inward.x, 0)
	local z = Vector(0, 0, 48)
	local start = d.center + inward * 40
	local depthT = line(start + z, start + z + inward * 700)
	local depth = math.max(80, depthT.Fraction * 700)
	local fwd = math.min(80, depth * 0.5)
	local function reach(s)
		local o = start + inward * (fwd - 40) + z
		local t = line(o, o + side * s * 500)
		return math.max(30, t.Fraction * 500 - 32)
	end
	local rl, rr = reach(1), reach(-1)
	local raw = {
		start + inward * (fwd - 40) + side * rl,                       -- corner, side +1
		start + inward * (fwd - 40) - side * rr,                       -- corner, side -1
		start + inward * math.min(depth * 0.6, 260) + side * rl * 0.4, -- deep, side +1
		start + inward * math.min(depth * 0.6, 260) - side * rr * 0.4, -- deep, side -1
	}
	local out = {}
	for i, p in ipairs(raw) do
		local s = Move.Snap(p)
		if s and room then
			local a = navmesh.GetNearestNavArea(s, false, 60, false, true)
			if not (IsValid(a) and room.set[a:GetID()]) then s = nil end
		end
		out[i] = s or Move.Snap(start + inward * 40) or start
	end
	return out
end
