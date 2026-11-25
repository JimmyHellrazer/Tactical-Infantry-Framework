-- Movement: navmesh path following with a tactical cost (areas visible to known threats cost
-- more), path budgets, failed-goal memory, and body facing (strafing while aiming).

local TIF = TIF
local Budget = TIF.Budget
local Prof = TIF.Prof

TIF.Move = TIF.Move or {}
local M = TIF.Move

local GOAL_TOLERANCE = 30
local SAME_GOAL = 48
local FAIL_MEMORY = 10      -- seconds a failed goal is not retried
local FAIL_RADIUS = 96
local EXPOSURE_COST = 1.6   -- extra cost multiplier for an area a known threat can see

function M.Init(npc)
	local p = Path("Follow")
	p:SetMinLookAheadDistance(160)
	p:SetGoalTolerance(GOAL_TOLERANCE)
	npc.tifPath = p
	npc.tifMove = { failed = {}, result = nil }
	-- Speeds of the home body's clips, so feet match the ground (MW19 walk/jog differ from GTA's).
	npc.tifSpeeds = TIF.Anim.Speeds(npc.tifHomeHost or TIF.Factions[npc:GetTIFFaction()].host)
end

-- Nearest point on the navmesh, or nil.
function M.Snap(pos)
	local area = navmesh.GetNearestNavArea(pos, false, 250, false, true)
	if not IsValid(area) then return nil, nil end
	return area:GetClosestPointOnArea(pos), area
end

local function recently_failed(m, pos, now)
	for i = #m.failed, 1, -1 do
		local f = m.failed[i]
		if now - f.time > FAIL_MEMORY then
			table.remove(m.failed, i)
		elseif f.pos:DistToSqr(pos) < FAIL_RADIUS * FAIL_RADIUS then
			return true
		end
	end
	return false
end

local function mark_failed(m, pos, now)
	m.failed[#m.failed + 1] = { pos = pos, time = now }
	if #m.failed > 12 then table.remove(m.failed, 1) end
end

-- Request movement. speed: "walk" | "tactical" | "alert" (MW19 alert walk) | "run" | "aimrun" | "sprint" | "crouch".
-- Returns false if the goal is off the navmesh or failed recently.
-- Moves that come from the squad order itself are never clamped to the leash.
local LEASH_EXEMPT = { formation = true, hold = true, advance = true, post = true, patrol = true, cqb = true,
	flee = true, medic = true }

-- Goal spreading: soldiers sent to the same spot (a sound to investigate, the last contact after a fight) each
-- took the exact same coordinate and walked into one another. A goal another soldier is already heading to or
-- standing on moves to a free, reachable spot around it, on this soldier's side; one already near it and not
-- crowding anyone stays where he is. Moves that are meant to be shared or are placed already are left alone.
M.SPREAD_R = 56
M.SPREAD_EXEMPT = { formation = true, cqb = true, board = true, medic = true, cover = true, flee = true,
	crawl = true, post = true }
local SPREAD_UP = Vector(0, 0, 40)

local function taken(npc, p)
	local r2 = M.SPREAD_R * M.SPREAD_R
	for _, o in ipairs(TIF.Soldiers or {}) do
		if IsValid(o) and o ~= npc and not o.tifDead and not o.tifVeh then
			local g = o.tifMove and o.tifMove.goal
			if (g and g:DistToSqr(p) < r2) or (not g and o:GetPos():DistToSqr(p) < r2) then return true end
		end
	end
	return false
end
M.Taken = taken

local function spread(npc, pos)
	if not taken(npc, pos) then return pos end
	local me = npc:GetPos()
	-- Already close and with room: stay.
	if me:DistToSqr(pos) < 150 * 150 and not taken(npc, me) then return me end
	local away = me - pos
	away.z = 0
	local a0 = away:LengthSqr() > 1 and math.deg(math.atan2(away.y, away.x)) or math.random(0, 359)
	for ring = 1, 2 do
		local r = 64 * ring + math.random(0, 16)
		for i = 0, 7 do
			local a = math.rad(a0 + (i % 2 == 0 and 1 or -1) * math.ceil(i / 2) * 45)
			local s = M.Snap(pos + Vector(math.cos(a) * r, math.sin(a) * r, 0))
			if s and math.abs(s.z - pos.z) < 48 and not taken(npc, s) then
				local tr = util.TraceLine({ start = pos + SPREAD_UP, endpos = s + SPREAD_UP, mask = MASK_NPCSOLID_BRUSHONLY })
				if not tr.Hit then return s end
			end
		end
	end
	return pos
end
M.Spread = spread

-- faceYaw (optional): the facing wanted on arrival (a post's), used by MW19 stop clips.
function M.SetGoal(npc, pos, speed, tag, faceYaw)
	local m = npc.tifMove
	local now = CurTime()
	m.faceYaw = faceYaw
	-- Squad leash: holding or following soldiers don't chase beyond it.
	if not LEASH_EXEMPT[tag] and TIF.Squad then
		local center, radius = TIF.Squad.Leash(npc)
		if center and pos:DistToSqr(center) > radius * radius then
			local dir = pos - center
			dir.z = 0
			dir:Normalize()
			pos = center + dir * radius * 0.9
		end
	end
	if m.goal and (m.goal:DistToSqr(pos) < SAME_GOAL * SAME_GOAL
		or (m.want and m.want:DistToSqr(pos) < SAME_GOAL * SAME_GOAL)) then
		m.speed, m.tag = speed, tag
		return true
	end
	local want = pos
	if not M.SPREAD_EXEMPT[tag or ""] then pos = spread(npc, pos) end
	local snapped = M.Snap(pos)
	if not snapped or recently_failed(m, snapped, now) then return false end
	-- A new goal mid stop clip: drop the stop and go.
	if m.stopping then
		m.stopping = nil
		if npc.tifAct and npc.tifAct.trans then TIF.Action.Clear(npc) end
	end
	m.goal, m.speed, m.tag, m.needCompute, m.result, m.startedAt = snapped, speed, tag, true, nil, now
	m.want, m.fresh, m.detour, m.watch, m.stuckN, m.passN = want, true, nil, nil, 0, 0
	-- A dash in a fight (to cover, a flank, closing in): sometimes a few covering rounds as it starts.
	if (speed == "run" or speed == "sprint" or speed == "aimrun") and tag ~= "flee" and tag ~= "board"
		and TIF.Weapon.CoveringBurst then
		TIF.Weapon.CoveringBurst(npc, now)
	end
	return true
end

-- Gaits in a fight: the MW19 aimed walk (~100 u/s, can shoot) for short moves, a sprint (gun down, no shooting)
-- for anything longer. No aimed jog: soldiers don't cover ground fast while aiming. Kept for the whole move once
-- picked (same goal), so a sprint doesn't drop to a walk as he gets close.
M.SPRINT_DIST = 300
function M.CombatGait(npc, goal)
	local m = npc.tifMove
	if m.goal and goal and m.goal:DistToSqr(goal) < SAME_GOAL * SAME_GOAL
		and (m.speed == "sprint" or m.speed == "tactical") then
		return m.speed
	end
	local d = (goal or npc:GetPos()) - npc:GetPos()
	d.z = 0
	return d:LengthSqr() > M.SPRINT_DIST * M.SPRINT_DIST and "sprint" or "tactical"
end

function M.Stop(npc)
	local m = npc.tifMove
	-- Halting mid-walk (MW19 body): a stop clip carries him to a standstill instead of freezing.
	if m.goal and not m.stopping and TIF.TransMW then TIF.TransMW.StopHere(npc, m) end
	m.goal, m.needCompute, m.tag, m.stopping, m.fresh = nil, false, nil, nil, nil
	m.want, m.detour, m.watch, m.sprintT = nil, nil, nil, nil
	if npc.tifPath:IsValid() then npc.tifPath:Invalidate() end
end

function M.Moving(npc)
	return npc.tifMove.goal ~= nil
end

-- Collect nav areas of confirmed threats once per think, for the path cost.
function M.UpdateThreatAreas(npc)
	local areas = {}
	for _, c in pairs(npc.tifK.contacts) do
		if c.confirmed and #areas < 3 then
			local a = navmesh.GetNearestNavArea(c.pos, false, 200, false, true)
			if IsValid(a) then areas[#areas + 1] = a end
		end
	end
	npc.tifThreatAreas = areas
	-- Firing lanes of squadmates who are shooting: paths avoid crossing in front of them.
	local lanes = {}
	local sq = npc.tifSquad
	if sq then
		local me = npc:GetPos()
		for _, m in ipairs(sq.members) do
			local f = IsValid(m) and m ~= npc and not m.tifDead and m.tifFire
			if f and f.want and f.aimPos and m:GetPos():DistToSqr(me) < 2000 * 2000 then
				local src = m:GetPos()
				local dir = f.aimPos - src
				dir.z = 0
				local len = dir:Length()
				if len > 50 then
					dir:Mul(1 / len)
					lanes[#lanes + 1] = { src = src, dir = dir, len = len }
					if #lanes >= 4 then break end
				end
			end
		end
	end
	npc.tifFireLanes = lanes
end

-- Is a point inside a squadmate's firing lane (a 10-degree wedge plus a body width)?
local LANE_TAN = math.tan(math.rad(10))
local function in_lane(lanes, p)
	for i = 1, #lanes do
		local l = lanes[i]
		local rx, ry = p.x - l.src.x, p.y - l.src.y
		local along = rx * l.dir.x + ry * l.dir.y
		if along > 40 and along < l.len then
			local lat = math.abs(rx * l.dir.y - ry * l.dir.x)
			if lat < 40 + along * LANE_TAN then return true end
		end
	end
	return false
end

local function cost_fn(npc)
	local loco = npc.loco
	local step = loco:GetStepHeight() + 6
	local drop = -loco:GetDeathDropHeight()
	local threats = npc.tifThreatAreas or {}
	local lanes = npc.tifFireLanes or {}
	-- MW19 body: can mantle up ledges (TIF.TraverseMW), so climbs up to its limit are allowed (at a cost).
	local climb = TIF.TraverseMW and TIF.TraverseMW.Use(npc) and TIF.TraverseMW.MAX_UP or nil
	return function(area, from, ladder, elevator, length)
		if not IsValid(from) then return 0 end
		-- GMod passes NULL objects for "no ladder" / "no elevator", and NULL is truthy in Lua:
		-- IsValid is required, or every connection between areas counts as a ladder.
		if IsValid(ladder) or IsValid(elevator) then return -1 end
		if not loco:IsAreaTraversable(area) then return -1 end
		local dist = length > 0 and length or from:GetCenter():Distance(area:GetCenter())
		local dz = from:ComputeAdjacentConnectionHeightChange(area)
		local cost = dist
		if dz > step then
			if not climb or dz > climb then return -1 end
			cost = cost + 150 + dz * 2
		elseif dz < drop then
			return -1
		end
		if area:HasAttributes(NAV_MESH_AVOID) then cost = cost + dist * 4 end
		-- (0.38.26) where he just got stuck on a player / prop / corner: steered round for a few seconds
		local av = npc.tifMove.avoid
		if av and CurTime() < av.untilT and area:GetCenter():DistToSqr(av.pos) < M.AVOID_R * M.AVOID_R then
			cost = cost + dist * 6
		end
		if area:HasAttributes(NAV_MESH_CROUCH) then cost = cost + dist * 0.5 end
		if #lanes > 0 and in_lane(lanes, area:GetCenter()) then cost = cost + dist * 3 end
		for i = 1, #threats do
			if threats[i]:IsPotentiallyVisible(area) then
				cost = cost + dist * EXPOSURE_COST
				break
			end
		end
		return from:GetCostSoFar() + cost
	end
end

local function Act_Done(npc, now) return TIF.Action.Done(npc, now) end

local speed_of, sprint_speed, watch_stuck

-- Sprint builds up: from his current pace (at least the aimed walk) to full over SPRINT_RAMP seconds (user: a
-- soldier went from standing to a full sprint at once, very quick on real maps).
M.SPRINT_RAMP = 1.5
-- Run and gun (covering burst on a dash): which mwrg_ clip, from the aim's angle off the run. "" = none / no clips.
local RG_DIRS = { { "f", 0 }, { "l", 90 }, { "r", -90 }, { "bl", 135 }, { "br", -135 } }
function M.RunGunDir(npc)
	local host = npc.tifHomeHost
	if not (host and TIF.GTG.IsVB(host) and TIF.GTG.Clip("mwrg_f", host)) then return "" end
	local cf = npc.tifCoverFire
	local v = npc.loco:GetVelocity()
	v.z = 0
	if not cf or v:LengthSqr() < 100 * 100 then return "" end
	local rel = math.AngleDifference((cf.aim - npc:GetPos()):Angle().y, v:Angle().y)
	local best, be = "", nil
	for _, d in ipairs(RG_DIRS) do
		local e = math.abs(math.AngleDifference(rel, d[2]))
		if TIF.GTG.Clip("mwrg_" .. d[1], host) and (not be or e < be) then best, be = d[1], e end
	end
	return best
end
-- Full sprint pace, as a share of the sprint clip's own speed. The clip is MW19's (sdr_mp_strafe_sprint_ar_8, 247 u/s
-- = MW19's AI sprint loop, 251); CoD soldiers mostly cover ground at their run pace (sdr_com_run_loop01, 217 u/s), and
-- 247 read too quick on Source maps (user, 2026-11-17). 0.88 = 217: the legs blend the jog and the sprint there.
-- (Since 0.31.1 the sprint clip IS the AI run loop, sdr_com_run_loop01 at 217: full speed.)
M.SPRINT_SCALE = 1.0
function sprint_speed(npc, m, sp, now)
	local full = speed_of(npc, sp)
	if sp ~= "sprint" then
		m.sprintT = nil
		return full
	end
	if not m.sprintT then
		m.sprintT = now
		m.sprintFrom = math.min(full, math.max(npc.loco:GetVelocity():Length2D(), speed_of(npc, "tactical")))
	end
	local k = math.Clamp((now - m.sprintT) / M.SPRINT_RAMP, 0, 1)
	k = k * k * (3 - 2 * k)
	return Lerp(k, m.sprintFrom, full)
end

-- Caught on something (a squadmate, a prop, a corner the path cuts): his speed is ~0 though he's trying to move,
-- so he stood in the calm idle. Every STUCK_T seconds of path following, too little progress for the pace he wants
-- = stuck: a sidestep away from the blocker (another soldier, or the side the hull traces find open), then a fresh
-- path. Three in a row: the goal is given up (as the engine's own stuck check does).
M.STUCK_T = 0.6
M.STUCK_MAX = 3
local SIDE_MIN, SIDE_MAX = Vector(-13, -13, 6), Vector(13, 13, 60)

local function blocker(npc, fwd)
	local me = npc:GetPos()
	local best, bd
	for _, o in ipairs(ents.FindInSphere(me, 56)) do
		if o ~= npc and (o:IsNPC() or o:IsPlayer() or o:IsNextBot()) then
			local to = o:GetPos() - me
			to.z = 0
			if to:Dot(fwd) > 0 and (not bd or to:LengthSqr() < bd) then best, bd = o, to:LengthSqr() end
		end
	end
	return best
end

-- (0.38.26, user: "a step back into a step forward, i see it alot when their stuck on someone but its usually not
-- enough to unstick them because of the step forward again") Hemmed in, unstick backed him off 30 in and then
-- re-pathed the same line into the same person. Now, by what he's stuck on:
--   another TIF soldier / civilian   the two pass through each other for M.PASS_T (TIF.Crowd.GhostPair: the same
--                                    no-collide group as the overlap rule, which never fires for two hulls pressed
--                                    together), and a standing, idle soldier steps aside (TIF.Crowd.MakeWay). Not a
--                                    strike toward giving the goal up; at most M.PASS_MAX times per goal.
--   a player, a prop, the world      backs off M.BACKOFF (60) when both sides are blocked, and his next paths steer
--                                    round that spot for M.AVOID_T s (cost_fn, M.AVOID_R).
M.PASS_T, M.PASS_MAX = 1.5, 2
M.BACKOFF = 60
M.AVOID_T, M.AVOID_R = 5, 70

local function tif_body(e)
	return IsValid(e) and (e.TIFSoldier or (e.GetClass and e:GetClass() == "tif_civilian")) and not e.tifDead
end

local function unstick(npc, m, now)
	local me = npc:GetPos()
	local fwd = npc.loco:GetVelocity()
	fwd.z = 0
	if fwd:LengthSqr() < 1 then fwd = (m.goal or me) - me fwd.z = 0 end
	if fwd:LengthSqr() < 1 then fwd = npc:GetForward() end
	fwd:Normalize()
	local right = Vector(fwd.y, -fwd.x, 0)
	local b = blocker(npc, fwd)
	local C = TIF.Crowd
	if tif_body(b) and C and C.GhostPair and (m.passN or 0) < M.PASS_MAX and C.GhostPair(npc, b, M.PASS_T, now) then
		m.passN = (m.passN or 0) + 1
		if C.MakeWay then C.MakeWay(b, npc, fwd, now) end
		m.stuckN = math.max(0, (m.stuckN or 1) - 1)
		m.watch = nil
		return
	end
	local sides
	if IsValid(b) then
		-- Step around him, on the side away from where he stands.
		local lat = (b:GetPos() - me):Dot(right)
		sides = lat > 0 and { -1, 1 } or { 1, -1 }
	else
		sides = math.random() < 0.5 and { 1, -1 } or { -1, 1 }
	end
	local bestP, bestF
	for _, sgn in ipairs(sides) do
		local to = me + right * (sgn * 44) + fwd * 12
		local tr = util.TraceHull({ start = me, endpos = to, mins = SIDE_MIN, maxs = SIDE_MAX, filter = npc,
			mask = MASK_NPCSOLID })
		if tr.Fraction > 0.9 then bestP = to break end
		if not bestF or tr.Fraction > bestF then bestP, bestF = me + (to - me) * tr.Fraction, tr.Fraction end
	end
	-- Hemmed in on both sides: back off instead (far enough that the next path can bend round it).
	if bestF and bestF < 0.3 then bestP = me - fwd * M.BACKOFF end
	-- (not on a TIF body: his next paths steer round where this happened for a while)
	if not tif_body(b) then
		m.avoid = { pos = IsValid(b) and b:GetPos() or (me + fwd * 40), untilT = now + M.AVOID_T }
	end
	m.detour = { pos = bestP, untilT = now + (bestF and bestF < 0.3 and 1.3 or 0.9) }
end

function watch_stuck(npc, m, want, now)
	local me = npc:GetPos()
	local w = m.watch
	-- (Only over steady path following: clips, traversals and waits in between start a fresh window.)
	if not w or now - w.last > 0.35 then
		m.watch = { t = now, last = now, pos = me }
		return false
	end
	w.last = now
	if now - w.t < M.STUCK_T then return false end
	local moved = (me - w.pos):Length2D()
	local expect = want * (now - w.t)
	m.watch = { t = now, last = now, pos = me }
	if want < 30 or moved >= math.max(6, expect * 0.25) then
		m.stuckN = 0
		return false
	end
	m.stuckN = (m.stuckN or 0) + 1
	if m.stuckN >= M.STUCK_MAX then
		mark_failed(m, m.goal, now)
		M.Stop(npc)
		m.result = "stuck"
		return true
	end
	unstick(npc, m, now)
	return true
end

-- Wading (NW2 tif_wade, sv_brain): knee-deep water caps the pace, chest-deep more (MW22's wading clips).
M.WADE_CAP = { 60, 45 }   -- (the clips: wade ~30-47 u/s, hurried wade ~50)
local base_speed
function speed_of(npc, mode)
	local v = base_speed(npc, mode)
	local w = npc.tifWade
	if w and w > 0 and mode ~= "crawl" then v = math.min(v, M.WADE_CAP[w] or v) end
	return v
end
function base_speed(npc, mode)
	local s = npc.tifSpeeds
	local mult = npc.tifArch.speeds
	if mode == "walk" then return s.walk * (mult.walk or 1) end
	if mode == "tactical" then return s.tactical * (mult.tactical or 1) end
	if mode == "alert" then return (s.alert or s.tactical) * (mult.tactical or 1) end
	if mode == "aimrun" then return s.aimrun end
	if mode == "sprint" then return s.sprint * M.SPRINT_SCALE end
	if mode == "crouch" then return s.crouch end
	if mode == "crawl" then return 32 end -- MW19 last-stand crawl (clips ~28-40)
	return s.run * (mult.run or 1)
end

-- Runs every behaviour update (from the NextBot coroutine).
function M.Step(npc)
	-- Seated in a vehicle: the vehicle carries the soldier.
	if npc.tifVeh then return end
	local m = npc.tifMove
	local now = CurTime()
	-- A room clear's glide onto a spot / through a doorway (TIF.CQB.GlideStep): every tick, no path meanwhile.
	if npc.tifGlide and TIF.CQB and TIF.CQB.GlideStep and TIF.CQB.GlideStep(npc, now) then return end
	if m.goal and m.needCompute then
		if Budget.Take("path", 1) then
			Prof.Begin("path")
			local ok = npc.tifPath:Compute(npc, m.goal, cost_fn(npc))
			Prof.End()
			m.needCompute = false
			if not ok or not npc.tifPath:IsValid() then
				mark_failed(m, m.goal, now)
				m.goal, m.result = nil, "fail"
			end
		end
		return
	end
	if not m.goal then return end
	local path = npc.tifPath
	-- MW19 LMG on its bipod: packed up first (TIF.BipodMW), then off he goes.
	if npc.tifBipod then
		if TIF.BipodMW then TIF.BipodMW.Leave(npc, now) end
		return
	end
	-- MW19 stop clip carrying the soldier onto the goal: arrived when it ends.
	if m.stopping then
		local a = npc.tifAct
		if not (a and a.trans) or Act_Done(npc, now) then
			M.Stop(npc)
			m.result = "arrived"
		end
		return
	end
	-- MW19 traversal (mantle, vault, drop) carrying him: the path waits until its hand-back point.
	local TR = TIF.TraverseMW
	if TR and TR.Busy(npc, now) then return end
	-- MW19 start / turn clip playing: the path waits (the clip moves the body). A turn on the spot is dropped
	-- for a new move (calm turns take 3 s).
	-- A strafe reversal hands back to the path at its code_move note (the rest of the clip is the new strafe).
	local ta = npc.tifAct
	if ta and ta.trans and ta.handU and (now - ta.t0) >= ta.dur * ta.handU then
		TIF.Action.Clear(npc)
		m.needCompute = true
	end
	if npc.tifAct and npc.tifAct.trans and not Act_Done(npc, now) then
		if not (m.fresh and string.sub(npc.tifAct.name, 1, 9) == "mwt_turn_") then return end
		TIF.Action.Clear(npc)
	end
	if not path:IsValid() then
		m.goal, m.result = nil, "arrived"
		return
	end
	local T = TIF.TransMW
	if m.fresh then
		m.fresh = nil
		if T and T.Start(npc, m) then return end
	end
	if T and T.Stop(npc, m) then
		m.stopping = true
		return
	end
	-- Strafing the other way now: the AI reversal clip (plant and push off) instead of the legs flipping.
	if T and T.Reverse and T.Reverse(npc, m, now) then return end
	-- A closed door right ahead: MW19's door interaction (push / shoulder / kick), the door opening on its contact.
	if TIF.DoorMW and TIF.DoorMW.Check(npc, m, now) then return end
	-- A ledge, an obstacle or a drop right ahead on the path: MW19's traversal clip.
	if TR and TR.Check(npc, m, now) then return end
	-- Covering burst on a dash: MW19 body with the run-and-gun clips: keeps running, the few rounds go out to the side
	-- of the run (NW2 tif_rungun = which way the gun points, cl_body plays mwrg_<v>; tifAimFree lets it shoot off
	-- the body's facing). Otherwise the aimed walk (gun up) for its few rounds, then the sprint.
	local sp = m.speed
	local rg = ""
	if (sp == "sprint" or sp == "run") and TIF.Weapon.CoverFiring and TIF.Weapon.CoverFiring(npc, now) then
		rg = M.RunGunDir(npc)
		if rg == "" then sp = "tactical" end
	end
	if npc:GetNW2String("tif_rungun", "") ~= rg then npc:SetNW2String("tif_rungun", rg) end
	npc.tifRunGun = rg ~= "" or nil
	npc.tifAimFree = npc.tifRunGun or (npc.tifAimFree and not npc.tifRunGunWas) or nil
	npc.tifRunGunWas = npc.tifRunGun
	local want = sprint_speed(npc, m, sp, now)
	-- Sidestepping something he got caught on (unstick): straight to the side spot, then a fresh path.
	local d = m.detour
	if d then
		if now > d.untilT or npc:GetPos():DistToSqr(d.pos) < 16 * 16 then
			m.detour, m.watch = nil, nil
			m.needCompute = true
			return
		end
		-- At his own pace (0.19.7 forced 80: a calm walk at 40 played its legs double speed, user: "sped up").
		npc.loco:SetDesiredSpeed(math.max(want, 30))
		npc.loco:Approach(d.pos, 1)
		return
	end
	-- Walking off: a full-body clip that doesn't move him (a finished one-shot holding its last frame, a standing
	-- loop: an idle activity, a CQB wait pose) ends here, or he slid along the path in that pose (user, 2026-11-17).
	local a = npc.tifAct
	if a and not a.trans and not npc.tifDowned and not npc.tifProne and not a.keepMoving
		and npc:GetNW2String("tif_act_base", "") == ""
		and (Act_Done(npc, now) or (a.loop and (a.clip.speed or 0) < 1)) then
		TIF.Action.Clear(npc)
	end
	-- (0.38.18) Someone in the way ahead: behind him at his pace, or eased past (TIF.Crowd, sv_crowd.lua).
	local steer
	if TIF.Crowd and TIF.Crowd.Steer then
		local fwd = npc.loco:GetVelocity()
		fwd.z = 0
		if fwd:LengthSqr() < 100 then fwd = m.goal - npc:GetPos() fwd.z = 0 end
		if fwd:LengthSqr() > 1 then
			fwd:Normalize()
			want, steer = TIF.Crowd.Steer(npc, fwd, want, m.goal, now)
		end
	end
	npc.loco:SetDesiredSpeed(want)
	path:Update(npc)
	if steer then npc.loco:Approach(steer, TIF.Crowd.WEIGHT) end
	if npc:GetPos():DistToSqr(m.goal) < GOAL_TOLERANCE * GOAL_TOLERANCE * 1.5 then
		M.Stop(npc)
		m.result = "arrived"
		return
	end
	if watch_stuck(npc, m, want, now) then return end
	if npc.loco:IsStuck() then
		npc.loco:ClearStuck()
		mark_failed(m, m.goal, now)
		M.Stop(npc)
		m.result = "stuck"
		return
	end
	-- Paths that drag on for too long are given up (blocked doors, props).
	if now - (m.startedAt or now) > 25 then
		mark_failed(m, m.goal, now)
		M.Stop(npc)
		m.result = "timeout"
	end
end

-- Facing, every tick. npc.tifFace = position to keep the body pointed at (aiming / looking),
-- or nil to let the path turn the body toward travel.
function M.Face(npc, dt)
	-- Seated (angles are local to the vehicle) or mid get-out clip (the clip turns the body).
	if npc.tifVeh or npc.tifLeaving then return end
	local loco = npc.loco
	-- (a paired melee fight: the clip turns him, both men placed for it; no facing of ours on top)
	if npc.tifMelee and npc.tifMelee.fight then
		loco:SetMaxYawRate(0)
		return
	end
	-- An MW19 turn / start / stop clip turns the body itself.
	if npc.tifAct and npc.tifAct.trans then
		loco:SetMaxYawRate(0)
		return
	end
	local face = npc.tifFace
	-- Covering burst: the body swings toward the enemy for those rounds (strafing on the dash).
	local cf = npc.tifCoverFire
	-- (not when running and gunning: the body keeps to the run, the clip points the gun)
	if cf and CurTime() < cf.untilT and cf.shots > 0 and not npc.tifRunGun then face = cf.aim end
	-- Calm (weapon lowered) soldiers only have a forward walk: while walking they face where they go (the path
	-- turns them) and look around once they stop. Otherwise they slid sideways playing the forward walk.
	-- (Not a downed soldier crawling: he drags himself away still facing the enemy.)
	if face and npc.tifMode == TIF.Anim.MODE_RELAXED and not npc.tifAct and not npc.tifDowned
		and loco:GetVelocity():Length2DSqr() > 30 * 30 then
		face = nil
	end
	if not face then
		loco:SetMaxYawRate(npc.tifArch.turnRate)
		return
	end
	loco:SetMaxYawRate(0)
	local to = face - npc:GetPos()
	if to:Length2DSqr() < 1 then return end
	local want = to:Angle().y
	local cur = npc:GetAngles().y
	local prone = npc.tifProne
	if prone and prone.phase ~= 2 then return end -- no turning while getting down or up
	-- Standing still and facing far off: an MW19 turn-in-place clip instead of spinning on the spot.
	if not prone and TIF.TransMW and not M.Moving(npc) and loco:GetVelocity():Length2DSqr() < 10 * 10
		and TIF.TransMW.Turn(npc, want) then return end
	local rate = prone and TIF.ProneB.TURN_RATE or npc.tifArch.turnRate
	local new = math.ApproachAngle(cur, want, rate * dt)
	if math.abs(math.AngleDifference(new, cur)) > 0.01 then npc:SetAngles(Angle(0, new, 0)) end
end
