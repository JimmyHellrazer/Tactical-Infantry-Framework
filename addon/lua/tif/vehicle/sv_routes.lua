local TIF = TIF
local BLD = TIF.Building

TIF.Routes = TIF.Routes or {}
local R = TIF.Routes

R.ROAD_PATTERNS = { "road", "asphalt", "tarmac", "street", "highway", "pavement", "freeway" }

R.MAP_ROADS = {
	tif_range = { "concretefloor028a" },
	gm_fork = { "concretefloor037b" },
}
R.MIN_WIDTH = 90
R.OFFROAD_COST = 3
R.MAX_EXPAND = 8000

local surfaceCache = {}
local tr = { mask = MASK_SOLID_BRUSHONLY }

function R.Surface(area)
	local id = area:GetID()
	local s = surfaceCache[id]
	if s then return s end
	if BLD and BLD.AreaIndoor(area) then s = "no"
	else
		local c = area:GetCenter()
		tr.start, tr.endpos = c + Vector(0, 0, 20), c - Vector(0, 0, 60)
		local t = util.TraceLine(tr)
		local tex = string.lower(t.HitTexture or "")
		s = "ground"
		for _, p in ipairs(R.ROAD_PATTERNS) do if string.find(tex, p) then s = "road" break end end
		if s ~= "road" then
			for _, p in ipairs(R.MAP_ROADS[game.GetMap()] or {}) do if string.find(tex, p) then s = "road" break end end
		end
		if s == "ground" and math.min(area:GetSizeX(), area:GetSizeY()) < R.MIN_WIDTH then

			local h = util.TraceHull({ start = c + Vector(0, 0, 30), endpos = c + Vector(0, 0, 30),
				mins = Vector(-55, -55, 0), maxs = Vector(55, 55, 50), mask = MASK_SOLID_BRUSHONLY })
			if h.Hit then s = "no" end
		end
	end
	surfaceCache[id] = s
	return s
end

local function nav_route(from, to)
	local a0 = navmesh.GetNearestNavArea(from, false, 400, false, true)
	local a1 = navmesh.GetNearestNavArea(to, false, 400, false, true)
	if not (IsValid(a0) and IsValid(a1)) then return nil end
	local goal = a1:GetCenter()
	local open, came, g = { a0 }, {}, { [a0:GetID()] = 0 }
	local f = { [a0:GetID()] = a0:GetCenter():Distance(goal) }
	local inOpen = { [a0:GetID()] = true }
	local expanded = 0
	while #open > 0 and expanded < R.MAX_EXPAND do

		local bi, best = 1, open[1]
		for i = 2, #open do if f[open[i]:GetID()] < f[best:GetID()] then bi, best = i, open[i] end end
		table.remove(open, bi)
		local bid = best:GetID()
		inOpen[bid] = nil
		expanded = expanded + 1
		if best == a1 then
			local path, cur = {}, best
			while cur do
				table.insert(path, 1, cur)
				cur = came[cur:GetID()]
			end
			return path
		end
		local bc = best:GetCenter()
		for _, n in ipairs(best:GetAdjacentAreas()) do
			local surf = n == a1 and "road" or R.Surface(n)
			local nc = n:GetCenter()
			if surf ~= "no" and math.abs(nc.z - bc.z) < 40 then
				local nid = n:GetID()
				local cost = g[bid] + bc:Distance(nc) * (surf == "road" and 1 or R.OFFROAD_COST)
				if not g[nid] or cost < g[nid] then
					g[nid], came[nid] = cost, best
					f[nid] = cost + nc:Distance(goal)
					if not inOpen[nid] then open[#open + 1] = n inOpen[nid] = true end
				end
			end
		end
	end
	return nil
end

local hull = { mins = Vector(-50, -50, 20), maxs = Vector(50, 50, 70), mask = MASK_SOLID_BRUSHONLY }
local down = { mask = MASK_SOLID_BRUSHONLY }
local function grounded(a, b)
	local len = a:Distance(b)
	local steps = math.floor(len / 120)
	for k = 1, steps do
		local p = LerpVector(k / (steps + 1), a, b)
		down.start, down.endpos = p + Vector(0, 0, 60), p - Vector(0, 0, 160)
		local t = util.TraceLine(down)
		if not t.Hit or math.abs(t.HitPos.z - p.z) > 60 then return false end
	end
	return true
end
local function clear(a, b)
	hull.start, hull.endpos = a, b
	return not util.TraceHull(hull).Hit and grounded(a, b)
end
local function simplify(pts)
	local out = { pts[1] }
	local i = 1
	while i < #pts do
		local j = math.min(#pts, i + 10)
		while j > i + 1 and not clear(pts[i], pts[j]) do j = j - 1 end
		out[#out + 1] = pts[j]
		i = j
	end
	return out
end

function R.Build(from, to)
	local dv = TIF.DV.Route(from, to)
	if dv then
		if dv[#dv]:DistToSqr(to) > 200 * 200 then dv[#dv + 1] = to end
		return dv, "dv"
	end
	local areas = nav_route(from, to)
	if areas and #areas > 0 then
		local pts = { from }
		for _, a in ipairs(areas) do pts[#pts + 1] = a:GetCenter() end
		pts[#pts + 1] = to
		local s = simplify(pts)
		table.remove(s, 1)
		return s, "roads"
	end
	if from:DistToSqr(to) < 1500 * 1500 then return { to }, "direct" end
	return nil, "no route"
end

function R.Classify(pos, radius)
	local out = {}
	for _, a in ipairs(navmesh.Find(pos, radius or 3000, 100, 100)) do
		out[#out + 1] = { area = a, surface = R.Surface(a) }
	end
	return out
end
