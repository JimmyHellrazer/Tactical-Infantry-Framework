-- Squad tactics: once a second per squad in a fight, the squad picks a plan and gives each
-- member a role.
--   base      stays in cover and fires at the enemy, including suppressive fire at the last
--             known position when it can't be seen
--   maneuver  moves: leapfrogs to cover closer to the enemy, or swings round a flank
-- Plans:
--   bound     two groups take turns: one moves cover-to-cover toward the enemy, the other covers
--   flank     the enemy has sat still for a while: the maneuver group goes round one side
--   hold      no maneuvering (hold orders, squads led by a player, small or beaten squads)

local TIF = TIF
local AW = TIF.AWARE
local SQ = TIF.Squad
local Move = TIF.Move

TIF.SquadTactics = TIF.SquadTactics or {}
local ST = TIF.SquadTactics

ST.BOUND_STEP = 450        -- how far one bound goes toward the enemy
ST.BOUND_TIMEOUT = 14
ST.BOUND_MIN = 3           -- a bound lasts at least this long
ST.ARRIVE = 130            -- movers this close to the goal count as arrived
ST.FLANK_DIST = 650
ST.FLANK_STILL = 8         -- seconds the enemy must hold one spot before a flank
ST.FLANK_COOLDOWN = 25
-- Pushing (a squad with an advance order in contact): bounds aim at the objective unless the enemy is roughly on
-- the way (cos of the angle between them above PUSH_ON_WAY); a close fight is only sat out while the enemy is
-- being seen (PUSH_QUIET s without a sighting: the push resumes); the objective reached = fight there.
ST.PUSH_ON_WAY = 0.35
ST.PUSH_QUIET = 5
ST.PUSH_ARRIVED = 350

local ALWAYS_BASE = { support = true, marksman = true, leader = true }
local ALWAYS_MANEUVER = { assault = true, breacher = true }

local function flat(v)
	local f = Vector(v.x, v.y, 0)
	f:Normalize()
	return f
end

-- The enemy the squad is dealing with. Sticks with the current one until it's gone or hasn't
-- been seen for a while, so the plan doesn't flip between enemies every second.
local THREAT_STICK = 6
local function squad_threat(sq, now)
	local cur = sq.threatEnt and sq.knowledge[sq.threatEnt]
	if cur and TIF.IsLiveCombatant(sq.threatEnt) and now - cur.time < THREAT_STICK then return cur end
	local best, bestT, bestEnt
	for ent, k in pairs(sq.knowledge) do
		if TIF.IsLiveCombatant(ent) and (not bestT or k.time > bestT) then best, bestT, bestEnt = k, k.time, ent end
	end
	sq.threatEnt = bestEnt
	return best
end

local function engaged_count(members)
	local n = 0
	for _, m in ipairs(members) do
		if m.tifAware == AW.ENGAGED or m.tifAware == AW.ALERTED then n = n + 1 end
	end
	return n
end

local function centroid(members)
	local c = Vector()
	for _, m in ipairs(members) do c:Add(m:GetPos()) end
	return c / math.max(1, #members)
end

local function set_role(m, role, goal)
	m.tifRole = role
	m.tifCoverCenter = goal
	if m:GetNW2String("tif_role", "") ~= (role or "") then m:SetNW2String("tif_role", role or "") end
	m:SetNW2Vector("tif_mgoal", goal or vector_origin)
end

-- Split members: base keeps firing, maneuver moves. groups A/B alternate for bounding.
local function assign_groups(sq, members)
	local a, b = {}, {}
	local flip = false
	for _, m in ipairs(members) do
		local arch = m.tifArchId
		if ALWAYS_BASE[arch] then a[#a + 1] = m
		elseif ALWAYS_MANEUVER[arch] then b[#b + 1] = m
		else
			if flip then a[#a + 1] = m else b[#b + 1] = m end
			flip = not flip
		end
	end
	-- Everyone the same kind (e.g. all support): split them evenly instead.
	if (#a == 0 or #b == 0) and #members >= 2 then
		a, b = {}, {}
		for i, m in ipairs(members) do
			if i % 2 == 0 then a[#a + 1] = m else b[#b + 1] = m end
		end
	end
	sq.groupA, sq.groupB = a, b
end

local function clear_roles(sq, members)
	for _, m in ipairs(members) do set_role(m, nil, nil) end
	sq.tactic = nil
end

local function snap(p)
	return Move.Snap(p)
end

-- A point to one side of the enemy, as seen from the squad. Picks the side that's on the navmesh.
local function flank_point(sq, from, threat)
	local dir = flat(threat - from)
	local perp = Vector(-dir.y, dir.x, 0)
	local sides = { 1, -1 }
	if math.random() < 0.5 then sides = { -1, 1 } end
	for _, s in ipairs(sides) do
		local p = snap(threat - dir * ST.FLANK_DIST * 0.4 + perp * s * ST.FLANK_DIST)
		if p and p:DistToSqr(threat) > 300 * 300 then return p, s end
	end
	return nil
end

local function start_bound(sq, members, threat, now)
	assign_groups(sq, members)
	if #sq.groupA == 0 or #sq.groupB == 0 then return false end
	sq.tactic = { kind = "bound", moving = "B", started = now }
	return true
end

-- The next bound. Pushing on an objective (advance order, obj): toward the enemy if he's on the way there,
-- else toward the objective while the other group keeps him busy. Otherwise toward the enemy.
local function advance_goal(group, threat, obj)
	local c = centroid(group)
	if obj then
		local dT, dO = flat(threat - c), flat(obj - c)
		if dT:Dot(dO) < ST.PUSH_ON_WAY then
			local step = math.min(ST.BOUND_STEP, c:Distance(obj) * 0.5)
			return snap(c + dO * step) or c
		end
	end
	local d = c:Distance(threat)
	local step = math.min(ST.BOUND_STEP, d * 0.45)
	return snap(c + flat(threat - c) * step) or c
end

local function prune(list)
	if not list then return {} end
	local out = {}
	for _, m in ipairs(list) do if IsValid(m) and not m.tifDead and m.tifSquad then out[#out + 1] = m end end
	return out
end

local function plan(sq, now)
	-- The hold after a withdraw is temporary: restore the previous order (unless someone
	-- gave a new one since).
	if sq.withdrawHoldUntil and now > sq.withdrawHoldUntil then
		local prev = sq.preWithdrawOrder
		sq.withdrawHoldUntil, sq.preWithdrawOrder = nil, nil
		if sq.order.kind == "hold" and sq.order.time and sq.order.time < now - 29 then
			if prev then
				-- The whole order table, so a patrol keeps its route.
				sq.order = prev
				prev.time, prev.i = now, nil
				SQ.Publish(sq)
			else
				SQ.SetOrder(sq, "free")
			end
			SQ.Log(sq, "hold after withdraw over: back to ", prev and prev.kind or "free")
		end
	end
	sq.groupA, sq.groupB = prune(sq.groupA), prune(sq.groupB)
	local members = SQ.Members(sq)

	-- Lost contact: split the search between the members that are searching.
	local searching, fresh = {}, nil
	for _, m in ipairs(members) do
		if m.tifAware == AW.SEARCHING and m.tifSearch then
			searching[#searching + 1] = m
			if not m.tifSearch.assigned then fresh = m.tifSearch end
		end
	end
	if fresh and TIF.Search then TIF.Search.Plan(sq, searching, fresh.pos, fresh.dir, now) end
	-- Clearing a building, or riding / getting out of a vehicle: that plan is in charge.
	if sq.cqb then return end
	if TIF.Mounted and TIF.Mounted.Busy(sq) then return end

	if #members < 2 or engaged_count(members) == 0 then
		if sq.tactic then clear_roles(sq, members) end
		return
	end
	sq.lastContact = now
	local k = squad_threat(sq, now)
	if not k then
		if sq.tactic then clear_roles(sq, members) end
		return
	end
	local threat = k.pos
	local o = sq.order.kind
	local playerLed = IsValid(sq.leader) and sq.leader:IsPlayer()

	-- Track whether the enemy has been holding one spot.
	if not sq.threatAnchor or sq.threatAnchor:DistToSqr(threat) > 150 * 150 then
		sq.threatAnchor, sq.threatStill = Vector(threat), now
	end

	-- Static squads (base guards on posts, a reserve not yet sent out) fight where they stand.
	if sq.static then
		sq.tactic = { kind = "hold" }
		for _, m in ipairs(members) do set_role(m, "base", nil) end
		return
	end

	-- Losing: half the squad gone and outnumbered, or pinned down hard. Fall back together,
	-- then hold the new position. Player-led squads only do what the player says.
	sq.peakSize = math.max(sq.peakSize or 0, #members)
	local t0 = sq.tactic
	if not playerLed and (not t0 or t0.kind ~= "withdraw") and now > (sq.nextWithdraw or 0) then
		local enemies = 0
		for ent, kk in pairs(sq.knowledge) do
			if TIF.IsLiveCombatant(ent) and now - kk.time < 10 then enemies = enemies + 1 end
		end
		local supp = 0
		for _, m in ipairs(members) do supp = supp + (m.tifSupp or 0) end
		supp = supp / #members
		-- Half gone and outnumbered, or two thirds gone whatever the odds (one good shooter
		-- can never "outnumber" a squad).
		local lost = sq.peakSize >= 3 and #members <= sq.peakSize * 0.5
		local beaten = lost and (enemies >= #members or #members <= sq.peakSize / 3)
		-- Suppression alone only drives back a squad that has already taken losses or is outnumbered.
		local pinned = supp > 0.8 and (#members < sq.peakSize or enemies > #members)
		-- Or the squad's nerve is gone.
		local spent = TIF.Morale and TIF.Morale.Enabled() and TIF.Morale.SquadAverage(sq) < 0.3
		if beaten or pinned or spent then
			local from0 = centroid(members)
			local away = flat(from0 - threat)
			local goal = snap(from0 + away * 700) or snap(from0 + away * 400)
			if goal then
				sq.tactic = { kind = "withdraw", goal = goal, started = now }
				sq.nextWithdraw = now + 60
				SQ.Log(sq, "withdrawing: ", #members, "/", sq.peakSize, " left, ", enemies, " enemies, suppression ", string.format("%.2f", supp))
				TIF.Say(members[1], "retreat", 1)
			end
		end
	end
	if sq.tactic and sq.tactic.kind == "withdraw" then
		local w = sq.tactic
		local arrived = 0
		for _, m in ipairs(members) do
			if m:GetPos():DistToSqr(w.goal) < 220 * 220 then arrived = arrived + 1 end
		end
		if arrived >= math.ceil(#members * 0.6) or now - w.started > 18 then
			-- Regrouped: defend from here for a while, then go back to the old order.
			sq.preWithdrawOrder = sq.preWithdrawOrder or sq.order
			sq.withdrawHoldUntil = now + 30
			SQ.SetOrder(sq, "hold", w.goal, (threat - w.goal):Angle().y)
			sq.tactic = { kind = "hold" }
			for _, m in ipairs(members) do set_role(m, "base", nil) end
		else
			-- Everyone falls back; the nearest to the enemy keep shooting as they go.
			for _, m in ipairs(members) do set_role(m, "maneuver", w.goal) end
		end
		return
	end

	-- No maneuvering under a hold order or when a player leads: everyone is base of fire. (A pair pushing on an
	-- objective still bounds: one covers, one moves.)
	if o == "hold" or playerLed or (#members < 3 and o ~= "advance") then
		sq.tactic = { kind = "hold" }
		for _, m in ipairs(members) do set_role(m, "base", nil) end
		return
	end

	local from = centroid(members)
	local dist = from:Distance(threat)
	local minRange = 350
	if IsValid(sq.leader) and sq.leader.tifArch then minRange = sq.leader.tifArch.prefRange[1] + 100 end

	local t = sq.tactic
	-- Start a flank when the enemy has been static and the squad is big enough.
	if (not t or t.kind ~= "flank") and #members >= 4 and now - (sq.threatStill or now) > ST.FLANK_STILL
		and now > (sq.nextFlank or 0) and dist > 500 then
		assign_groups(sq, members)
		local p, side = flank_point(sq, from, threat)
		if p and #sq.groupB > 0 then
			sq.tactic = { kind = "flank", goal = p, side = side, started = now }
			sq.nextFlank = now + ST.FLANK_COOLDOWN
			local speaker = sq.groupB[1]
			TIF.Say(speaker, "moving", 0.9)
			t = sq.tactic
		end
	end

	if t and t.kind == "flank" then
		local arrived = 0
		for _, m in ipairs(sq.groupB) do
			if IsValid(m) and m:GetPos():DistToSqr(t.goal) < 250 * 250 then arrived = arrived + 1 end
		end
		if arrived >= math.ceil(#sq.groupB / 2) or now - t.started > ST.BOUND_TIMEOUT * 1.5 then
			-- Flank done: everyone fights from where they are for a while.
			sq.tactic = { kind = "engage", started = now }
			for _, m in ipairs(members) do set_role(m, "base", nil) end
			return
		end
		for _, m in ipairs(sq.groupA) do set_role(m, "base", nil) end
		for _, m in ipairs(sq.groupB) do set_role(m, "maneuver", t.goal) end
		return
	end

	-- Pushing on an objective: the objective unless it's been reached.
	local obj = o == "advance" and sq.order.pos or nil
	if obj and from:DistToSqr(obj) < ST.PUSH_ARRIVED * ST.PUSH_ARRIVED then obj = nil end
	-- While pushing, a close fight is only sat out while the enemy is actually being seen (or he's on the way
	-- to the objective anyway); gone quiet, the push carries on past him.
	local quiet = now - (k.time or now) > ST.PUSH_QUIET
	local holdClose = not obj or (not quiet and flat(threat - from):Dot(flat(obj - from)) >= ST.PUSH_ON_WAY)

	if t and t.kind == "engage" and now - t.started < 10 and holdClose then return end

	-- Close enough: stop bounding, fight.
	if dist < minRange and holdClose then
		sq.tactic = { kind = "engage", started = now }
		for _, m in ipairs(members) do set_role(m, "base", nil) end
		return
	end

	if not t or t.kind ~= "bound" then
		if not start_bound(sq, members, threat, now) then return end
		t = sq.tactic
		t.goal = advance_goal(sq.groupB, threat, obj)
		TIF.Say(sq.groupB[1], obj and "advance" or "moving", 0.6)
	end

	-- Deaths emptied one group (or new members joined): split again so someone always covers.
	local listed = #sq.groupA + #sq.groupB
	if #sq.groupA == 0 or #sq.groupB == 0 or listed ~= #members then
		assign_groups(sq, members)
	end
	local moving = t.moving == "B" and sq.groupB or sq.groupA
	local covering = t.moving == "B" and sq.groupA or sq.groupB
	-- A bound is done when most movers reached the goal (at least 3 s in), or it timed out.
	local arrived = 0
	for _, m in ipairs(moving) do
		if IsValid(m) then
			local cov = m.tifCov
			local inCoverNear = cov and cov.phase ~= "move" and cov.origin:DistToSqr(t.goal) < 420 * 420
			if inCoverNear or m:GetPos():DistToSqr(t.goal) < ST.ARRIVE * ST.ARRIVE then arrived = arrived + 1 end
		end
	end
	local done = (arrived >= math.ceil(#moving * 0.6) and now - t.started > ST.BOUND_MIN) or now - t.started > ST.BOUND_TIMEOUT
	if done then
		-- Swap: the group that covered now moves past the other.
		t.moving = t.moving == "B" and "A" or "B"
		t.started = now
		moving, covering = covering, moving
		t.goal = advance_goal(moving, threat, obj)
		SQ.Log(sq, "bound: group ", t.moving, " moves (", #moving, "), ", #covering, " cover; ", math.floor(dist), "u from enemy")
		if moving[1] then TIF.Say(moving[1], (moving[1].tifSupp or 0) > 0.3 and "cover_me" or (obj and "advance" or "moving"), 0.6) end
		if covering[1] then TIF.Say(covering[1], "suppressing", 0.5) end
	end
	for _, m in ipairs(covering) do set_role(m, "base", nil) end
	for _, m in ipairs(moving) do set_role(m, "maneuver", t.goal) end
end

timer.Create("tif_squad_tactics", 1, 0, function()
	if TIF.AIDisabled() then return end
	local now = CurTime()
	for _, sq in pairs(SQ.List) do
		local ok, err = pcall(plan, sq, now)
		if not ok then TIF.Error("Squad tactics error: ", tostring(err)) end
		if TIF.Chatter then
			local ok2, err2 = pcall(TIF.Chatter.Tick, sq, now)
			if not ok2 then TIF.Error("Squad chatter error: ", tostring(err2)) end
		end
		local kind = sq.tactic and sq.tactic.kind or ""
		if kind ~= sq.lastTacticShown then
			sq.lastTacticShown = kind
			for _, m in ipairs(SQ.Members(sq)) do m:SetNW2String("tif_tactic", kind) end
			if SQ.Log then SQ.Log(sq, "tactic: ", kind == "" and "none" or kind) end
		end
	end
end)
