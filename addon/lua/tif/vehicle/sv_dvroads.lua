-- Decent Vehicle waypoints from a road layout (Phase 6+).
--
-- A layout is a list of road centrelines. Each road becomes two lanes (right-hand traffic,
-- `lane` units either side of the centreline) with a waypoint about every `spacing` units, linked
-- one way along the lane. Loops close on themselves. Where a road's end is near another road, its
-- lanes are linked into that road's lanes both ways round (turn left or right), and roads leaving
-- another road are linked out of it the same way. A road marked `deadEnd` gets a U-turn at its end.
--
-- On a map with a layout and no DV waypoints yet, the waypoints are built and saved to
-- data/decentvehicle/<map>.txt shortly after the map loads, so DV loads them by itself from then on.
-- `tif_dv_build` rebuilds them (`tif_dv_build nosave` to try without saving).

local TIF = TIF
local DV = TIF.DV

TIF.DVRoads = TIF.DVRoads or {}
local DR = TIF.DVRoads

DR.LANE = 80
DR.SPACING = 300
DR.JOIN = 450

-- Road layouts per map. tif_range: see mapsrc/make_tif_range.py (roads are 320 wide).
DR.Layouts = DR.Layouts or {}
DR.Layouts.tif_range = {
	-- The ring road round the whole map.
	{ name = "ring", loop = true, speedKph = 60, pts = {
		Vector(-4190, -3190, 0), Vector(4190, -3190, 0), Vector(4190, 3190, 0), Vector(-4190, 3190, 0),
	} },
	-- The middle road, west ring road to east ring road.
	{ name = "middle", speedKph = 45, pts = { Vector(-3960, 860, 0), Vector(3960, 860, 0) } },
	-- The road down to the compound gate (dead end at the gate).
	{ name = "gate", speedKph = 25, deadEnd = true, pts = { Vector(2200, 780, 0), Vector(2200, 390, 0) } },
}

local function flat(v)
	local f = Vector(v.x, v.y, 0)
	f:Normalize()
	return f
end

local tr = { mask = MASK_SOLID_BRUSHONLY }
local function ground(p)
	tr.start, tr.endpos = p + Vector(0, 0, 100), p - Vector(0, 0, 200)
	local t = util.TraceLine(tr)
	return t.Hit and (t.HitPos + Vector(0, 0, 4)) or p
end

-- Points along a polyline at most `step` apart, corners kept.
local function resample(pts, loop, step)
	local out = {}
	local n = #pts
	local last = loop and n or n - 1
	for i = 1, last do
		local a, b = pts[i], pts[i % n + 1]
		local len = a:Distance(b)
		local k = math.max(1, math.ceil(len / step))
		for j = 0, k - 1 do out[#out + 1] = LerpVector(j / k, a, b) end
	end
	if not loop then out[#out + 1] = pts[n] end
	return out
end

-- One lane: the centreline points offset to the right of travel.
local function lane(center, loop)
	local n = #center
	local out = {}
	for i = 1, n do
		local prev = center[i - 1] or (loop and center[n]) or nil
		local nxt = center[i + 1] or (loop and center[1]) or nil
		local d = flat((nxt or center[i]) - (prev or center[i]))
		local right = Vector(d.y, -d.x, 0)
		out[i] = ground(center[i] + right * DR.LANE)
	end
	return out
end

local function reversed(t)
	local r = {}
	for i = #t, 1, -1 do r[#r + 1] = t[i] end
	return r
end

-- Build the layout into DV. Returns waypoint count, link count.
function DR.Build(layout)
	DV.Clear()
	local lanes = {}
	local links = 0
	for _, road in ipairs(layout) do
		local center = resample(road.pts, road.loop, DR.SPACING)
		for side = 1, 2 do
			local pts = lane(side == 1 and center or reversed(center), road.loop)
			local ids = {}
			for i, p in ipairs(pts) do ids[i] = DV.Add(p, { speedKph = road.speedKph }) end
			for i = 1, #ids - 1 do DV.Link(ids[i], ids[i + 1]) links = links + 1 end
			if road.loop then DV.Link(ids[#ids], ids[1]) links = links + 1 end
			lanes[#lanes + 1] = { road = road, side = side, pts = pts, ids = ids }
		end
	end
	-- Dead ends: U-turn from the end of the outbound lane into the start of the return lane.
	for _, l in ipairs(lanes) do
		if l.road.deadEnd and l.side == 1 then
			for _, m in ipairs(lanes) do
				if m.road == l.road and m.side == 2 then DV.Link(l.ids[#l.ids], m.ids[1]) links = links + 1 end
			end
		end
	end
	-- Junctions: lane ends into other roads' lanes, other roads' lanes into lane starts.
	local function nearest(m, p)
		local best, bestD
		for i, q in ipairs(m.pts) do
			local d = q:DistToSqr(p)
			if not bestD or d < bestD then best, bestD = i, d end
		end
		return best, bestD
	end
	for _, l in ipairs(lanes) do
		if not l.road.loop then
			for _, m in ipairs(lanes) do
				if m.road ~= l.road then
					-- Leaving l's end into m (not at l's dead end).
					local deadEndOut = l.road.deadEnd and l.side == 1
					if not deadEndOut then
						local i, d = nearest(m, l.pts[#l.pts])
						if i and d < DR.JOIN ^ 2 then DV.Link(l.ids[#l.ids], m.ids[i]) links = links + 1 end
					end
					-- Turning from m into l's start (not into the return lane of a dead end).
					local deadEndIn = l.road.deadEnd and l.side == 2
					if not deadEndIn then
						local j, d2 = nearest(m, l.pts[1])
						if j and d2 < DR.JOIN ^ 2 then DV.Link(m.ids[j], l.ids[1]) links = links + 1 end
					end
				end
			end
		end
	end
	return DV.WaypointCount(), links
end

concommand.Add("tif_dv_build", function(ply, cmd, args)
	if not TIF.CanUseDev(ply) then return end
	local function say(...)
		local msg = table.concat({ ... }, "")
		TIF.Log(msg)
		if IsValid(ply) then ply:ChatPrint("[TIF] " .. msg) end
	end
	if not DV.Present() then say("Decent Vehicle isn't installed") return end
	local layout = DR.Layouts[game.GetMap()]
	if not layout then say("No TIF road layout for ", game.GetMap()) return end
	local n, links = DR.Build(layout)
	local saved = args[1] ~= "nosave" and DV.Save()
	say("Decent Vehicle waypoints for ", game.GetMap(), ": ", n, " waypoints, ", links, " links",
		saved and (", saved to data/decentvehicle/" .. game.GetMap() .. ".txt") or " (not saved)")
end, nil, "tif_dv_build [nosave]: build Decent Vehicle waypoints from this map's TIF road layout")

-- First load of a map with a layout and no waypoints: build and save them.
hook.Add("InitPostEntity", "tif_dv_roads", function()
	timer.Simple(3, function()
		local layout = DR.Layouts[game.GetMap()]
		if not layout or not DV.Present() or DV.WaypointCount() > 0 then return end
		local n, links = DR.Build(layout)
		DV.Save()
		TIF.Log("Built Decent Vehicle waypoints for ", game.GetMap(), ": ", n, " waypoints, ", links, " links (saved)")
	end)
end)
