-- Squad search after losing contact (Phase 4).
-- Instead of every member wandering to the same spots around the last known position (LKP),
-- the squad splits the work:
--   overwatch  one member (marksman / support / leader first) takes a spot with a view of the
--              LKP, 350-700 units out on the squad's side, and watches it
--   searchers  the rest get separate nav points around the LKP, favouring the direction the
--              enemy was heading; the first searcher also checks the LKP itself
-- Points are stored in each soldier's tifSearch; the brain's search behaviour walks them.

local TIF = TIF

TIF.Search = TIF.Search or {}
local S = TIF.Search

S.RADIUS = 900
S.POINTS_EACH = 3
local WATCH_PREF = { marksman = 1, support = 2, leader = 3 }

local function flat(v)
	local f = Vector(v.x, v.y, 0)
	f:Normalize()
	return f
end

local trace = { mask = MASK_SOLID_BRUSHONLY }
local function sees(a, b)
	trace.start, trace.endpos = a, b
	return not util.TraceLine(trace).Hit
end

-- A spot with a view of the LKP, on the squad's side of it.
local function watch_point(lkp, from)
	local back = flat(from - lkp)
	local best, bestD
	for _, a in ipairs(navmesh.Find(lkp, 750, 200, 200)) do
		local p = a:GetCenter()
		local d = p:Distance(lkp)
		if d > 350 and d < 750 and flat(p - lkp):Dot(back) > 0.2
			and sees(p + Vector(0, 0, 60), lkp + Vector(0, 0, 40)) then
			local score = from:DistToSqr(p)
			if not bestD or score < bestD then best, bestD = p, score end
		end
	end
	return best
end

-- searchers: soldiers to give search work to. lkp/dir: last known position and heading.
function S.Plan(sq, searchers, lkp, dir, now)
	if #searchers == 0 then return end
	-- The enemy was last seen inside a building: clear it room by room instead (squads of 3+).
	if #searchers >= 3 and TIF.Building and TIF.CQB and not sq.cqb and TIF.Building.Indoor(lkp) then
		if TIF.CQB.Start(sq, lkp, true) then
			for _, m in ipairs(searchers) do
				if m.tifSearch then m.tifSearch.assigned = true end
			end
			TIF.Squad.Log(sq, "search: enemy was indoors, clearing the building")
			return
		end
	end
	local centre = Vector()
	for _, m in ipairs(searchers) do centre:Add(m:GetPos()) end
	centre = centre / #searchers

	-- Overwatch from groups of 3+.
	local watcher, watchAt
	if #searchers >= 3 then
		local bestRank
		for _, m in ipairs(searchers) do
			local r = WATCH_PREF[m.tifArchId] or 9
			if not bestRank or r < bestRank then watcher, bestRank = m, r end
		end
		watchAt = watch_point(lkp, centre)
		if not watchAt then watcher = nil end
	end

	local movers = {}
	for _, m in ipairs(searchers) do if m ~= watcher then movers[#movers + 1] = m end end

	-- Candidate points round the LKP.
	local cands = {}
	for _, a in ipairs(navmesh.Find(lkp, S.RADIUS, 150, 150)) do
		local p = a:GetCenter()
		local d = p:Distance(lkp)
		if d > 160 then
			local score = math.random() * 0.6 + (d < 500 and 0.3 or 0)
			if dir then score = score + flat(p - lkp):Dot(dir) * 1.2 end
			cands[#cands + 1] = { p = p, score = score }
		end
	end
	table.sort(cands, function(a, b) return a.score > b.score end)

	-- Spread points so two searchers don't pick spots next to each other.
	local picked = {}
	for _, c in ipairs(cands) do
		if #picked >= #movers * S.POINTS_EACH then break end
		local ok = true
		for _, q in ipairs(picked) do
			if q:DistToSqr(c.p) < 220 * 220 then ok = false break end
		end
		if ok then picked[#picked + 1] = c.p end
	end

	local lists = {}
	for i, m in ipairs(movers) do lists[i] = (i == 1) and { Vector(lkp) } or {} end
	for i, p in ipairs(picked) do
		local list = lists[(i - 1) % #movers + 1]
		if list then list[#list + 1] = p end
	end
	for i, m in ipairs(movers) do
		-- Visit this soldier's points nearest-first.
		local mp = m:GetPos()
		local list = lists[i]
		table.sort(list, function(a, b) return a:DistToSqr(mp) < b:DistToSqr(mp) end)
		m.tifSearch = { start = (m.tifSearch and m.tifSearch.start) or now, pos = Vector(lkp), dir = dir,
			points = list, i = 1, assigned = true }
	end
	if watcher then
		watcher.tifSearch = { start = (watcher.tifSearch and watcher.tifSearch.start) or now, pos = Vector(lkp),
			dir = dir, points = {}, i = 1, assigned = true, watch = watchAt }
	end
	if TIF.Squad.Log then
		TIF.Squad.Log(sq, "search: ", #movers, " searching ", #picked + 1, " points",
			watcher and ", 1 on overwatch" or "", " round ", tostring(lkp))
	end
	TIF.Say(searchers[1], "moving", 0.4)
end
