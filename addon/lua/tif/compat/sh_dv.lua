local TIF = TIF
TIF.DV = TIF.DV or {}
local A = TIF.DV

local function DV()
	return DecentVehicleDestination
end

A.Table = DV

function A.Present()
	return istable(DV()) and istable(DV().Waypoints)
end

function A.WaypointCount()
	return A.Present() and #DV().Waypoints or 0
end

function A.HasRoutes()
	return SERVER and A.Present() and isfunction(DV().GetRouteVector) and A.WaypointCount() > 0
end

if SERVER then
	function A.Clear()
		if not A.Present() then return end

		table.Empty(DV().Waypoints)

		if player.GetCount() > 0 then
			net.Start("Decent Vehicle: Clear waypoints")
			net.Broadcast()
		end
	end

	function A.Add(pos, opts)
		if not (A.Present() and DV().AddWaypoint) then return nil end

		opts = opts or {}
		local w = DV().AddWaypoint(pos)
		w.SpeedLimit = (opts.speedKph or 50) * (DV().KphToHUps or 17.6)
		w.Group = opts.group or 0
		w.UseTurnLights = false
		w.WaitUntilNext = 0
		w.FuelStation = false
		return #DV().Waypoints
	end

	function A.Link(from, to)
		if A.Present() and DV().AddNeighbor then
			DV().AddNeighbor(from, to)
		end
	end

	function A.Save()
		if not (A.Present() and DV().GetSaveTable) then return false end

		file.CreateDir("decentvehicle")
		file.Write("decentvehicle/" .. game.GetMap() .. ".txt", util.Compress(util.TableToJSON(DV().GetSaveTable())))
		return true
	end
end

local function nearest_ids(pos, n, band)
	local list = {}
	for id, w in ipairs(DV().Waypoints) do
		local t = w.Target
		if t and #(w.Neighbors or {}) > 0 then
			local dz = (t.z - pos.z) * 2
			list[#list + 1] = { id = id, d = math.sqrt((t.x - pos.x) ^ 2 + (t.y - pos.y) ^ 2 + dz * dz) }
		end
	end

	table.sort(list, function(a, b) return a.d < b.d end)
	if not list[1] then return {} end

	local wps = DV().Waypoints
	local function heading(id)
		local w = wps[id]
		local nb = wps[w.Neighbors[1]]
		return nb and (nb.Target - w.Target):GetNormalized() or Vector(1, 0, 0)
	end

	local ref = heading(list[1].id)
	local same, other = {}, {}
	local limit = list[1].d + band

	for _, e in ipairs(list) do
		if e.d > limit then break end

		local bucket = heading(e.id):Dot(ref) >= 0 and same or other
		if #bucket < math.ceil(n / 2) then
			bucket[#bucket + 1] = e.id
		end
	end

	local out = {}
	for i = 1, math.max(#same, #other) do
		if same[i] then
			out[#out + 1] = same[i]
		end

		if other[i] then
			out[#out + 1] = other[i]
		end
	end

	return out
end

local function to_points(wps)
	local pts, last = {}, nil
	for i = #wps, 1, -1 do
		local p = wps[i].Target
		if p and (not last or last:DistToSqr(p) > 1) then
			pts[#pts + 1] = p
			last = p
		end
	end

	return pts
end

local function length(pts)
	local n = 0
	for i = 2, #pts do
		n = n + pts[i]:Distance(pts[i - 1])
	end

	return n
end

local graph
function A.Invalidate()
	graph = nil
end

local function build()
	local wps = DV().Waypoints
	local stamp = #wps .. ":" .. tostring(DV().TIFStamp or 0)
	if graph and graph.stamp == stamp then return graph end

	local adj = {}
	for id, w in ipairs(wps) do
		for _, n in ipairs(w.Neighbors or {}) do
			n = tonumber(n)

			if n and n ~= id and wps[n] then
				adj[id] = adj[id] or {}
				adj[n] = adj[n] or {}
				adj[id][n], adj[n][id] = true, true
			end
		end
	end

	graph = { stamp = stamp, adj = adj }
	return graph
end

local function near(G, pos, k, band)
	local list = {}
	for id, w in ipairs(DV().Waypoints) do
		if G.adj[id] and w.Target then
			local t = w.Target
			local dz = (t.z - pos.z) * 2
			list[#list + 1] = { id = id, d = math.sqrt((t.x - pos.x) ^ 2 + (t.y - pos.y) ^ 2 + dz * dz) }
		end
	end

	table.sort(list, function(a, b) return a.d < b.d end)
	local out = {}

	for i = 1, math.min(k, #list) do
		if list[i].d > list[1].d + band then break end

		out[#out + 1] = list[i].id
	end

	return out
end

local function push(h, f, id)
	h[#h + 1] = { f, id }
	local i = #h

	while i > 1 do
		local p = math.floor(i / 2)
		if h[p][1] <= h[i][1] then break end

		h[p], h[i] = h[i], h[p]
		i = p
	end
end

local function pop(h)
	local top = h[1]
	local last = table.remove(h)

	if #h > 0 then
		h[1] = last
		local i = 1

		while true do
			local l, r, s = i * 2, i * 2 + 1, i
			if h[l] and h[l][1] < h[s][1] then
				s = l
			end

			if h[r] and h[r][1] < h[s][1] then
				s = r
			end

			if s == i then break end

			h[s], h[i] = h[i], h[s]
			i = s
		end
	end

	return top
end

local function two_way(from, to)
	local G = build()
	local wps = DV().Waypoints
	local starts, endsList = near(G, from, 6, 600), near(G, to, 6, 600)
	if #starts == 0 or #endsList == 0 then return nil end

	local ends = {}
	for _, id in ipairs(endsList) do
		ends[id] = true
	end

	local g, came, closed, h = {}, {}, {}, {}
	for _, s in ipairs(starts) do
		local p = wps[s].Target
		g[s] = from:Distance(p)
		push(h, g[s] + p:Distance(to), s)
	end

	local expanded = 0
	while #h > 0 and expanded < 30000 do
		local u = pop(h)[2]
		if not closed[u] then
			closed[u] = true
			expanded = expanded + 1

			if ends[u] then
				local pts, cur = {}, u
				while cur do
					table.insert(pts, 1, wps[cur].Target)
					cur = came[cur]
				end

				return pts
			end

			local pu = wps[u].Target
			for v in pairs(G.adj[u]) do
				if not closed[v] then
					local pv = wps[v].Target
					local cost = g[u] + pu:Distance(pv)

					if not g[v] or cost < g[v] then
						g[v], came[v] = cost, u
						push(h, cost + pv:Distance(to), v)
					end
				end
			end
		end
	end

	return nil
end

function A.Route(from, to)
	if not A.HasRoutes() then return nil end

	local dv = DV()
	local ok, pts = pcall(two_way, from, to)
	if ok and pts and #pts > 0 then return pts end

	if not ok then
		TIF.Warn("DV two-way route failed: ", tostring(pts))
	end

	local best, bestLen
	if isfunction(dv.GetRoute) then
		local starts = nearest_ids(from, 8, 500)
		local ends = {}

		for _, id in ipairs(nearest_ids(to, 8, 500)) do
			ends[id] = true
		end

		if #starts > 0 and next(ends) then
			for _, sid in ipairs(starts) do
				local ok, wps = pcall(dv.GetRoute, sid, ends)
				if ok and istable(wps) and #wps > 0 then
					local pts = to_points(wps)

					local len = length(pts) + (pts[1] and from:Distance(pts[1]) or 0)
					if #pts > 0 and (not bestLen or len < bestLen) then
						best, bestLen = pts, len
					end
				end
			end
		end
	end

	if best then return best end

	local ok, wps = pcall(dv.GetRouteVector, from, to)
	if not ok or not istable(wps) or #wps == 0 then return nil end

	local pts = to_points(wps)
	return #pts > 0 and pts or nil
end
