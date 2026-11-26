local TIF = TIF
local Budget = TIF.Budget
local Prof = TIF.Prof

TIF.Move = TIF.Move or {}
local M = TIF.Move

local GOAL_TOLERANCE = 30
local SAME_GOAL = 48
local FAIL_MEMORY = 10
local FAIL_RADIUS = 96
local EXPOSURE_COST = 1.6

function M.Init(npc)
	local p = Path("Follow")
	p:SetMinLookAheadDistance(160)
	p:SetGoalTolerance(GOAL_TOLERANCE)
	npc.tifPath = p
	npc.tifMove = { failed = {}, result = nil }

	npc.tifSpeeds = TIF.Anim.Speeds(npc.tifHomeHost or TIF.Factions[npc:GetTIFFaction()].host)
end

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
	if #m.failed > 12 then
		table.remove(m.failed, 1)
	end
end

local LEASH_EXEMPT = { formation = true, hold = true, advance = true, post = true, patrol = true, cqb = true,
	flee = true, medic = true }

M.SPREAD_R = 72
M.SPREAD_EXEMPT = { formation = true, cqb = true, board = true, medic = true, cover = true, flee = true,
	crawl = true, post = true }
local SPREAD_UP = Vector(0, 0, 40)

local spreadOut = {}
local spreadTr = { mask = MASK_NPCSOLID_BRUSHONLY, output = spreadOut }

local function taken(npc, p)
	local r2 = M.SPREAD_R * M.SPREAD_R
	local soldiers = TIF.Soldiers
	if not soldiers then return false end
	for i = 1, #soldiers do
		local o = soldiers[i]
		if IsValid(o) and o ~= npc and not o.tifDead and not o.tifVeh then
			local g = o.tifMove and o.tifMove.goal
			if (g and g:DistToSqr(p) < r2) or (not g and o:GetPos():DistToSqr(p) < r2) then
				return true
			end
		end
	end

	return false
end
M.Taken = taken

local function spread(npc, pos)
	if not taken(npc, pos) then return pos end
	local me = npc:GetPos()
	if me:DistToSqr(pos) < 150 * 150 and not taken(npc, me) then return me end
	local away = me - pos
	away.z = 0
	local a0 = away:LengthSqr() > 1 and math.deg(math.atan2(away.y, away.x)) or math.random(0, 359)
	local pUp = pos + SPREAD_UP
	for ring = 1, 2 do
		local r = 80 * ring + math.random(0, 16)
		for i = 0, 7 do
			local a = math.rad(a0 + (i % 2 == 0 and 1 or -1) * math.ceil(i / 2) * 45)
			local s = M.Snap(pos + Vector(math.cos(a) * r, math.sin(a) * r, 0))
			if s and math.abs(s.z - pos.z) < 48 and not taken(npc, s) then
				spreadTr.start, spreadTr.endpos = pUp, s + SPREAD_UP
				if not util.TraceLine(spreadTr).Hit then return s end
			end
		end
	end

	return pos
end
M.Spread = spread

function M.SetGoal(npc, pos, speed, tag, faceYaw)
	local m = npc.tifMove
	local now = CurTime()
	m.faceYaw = faceYaw

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
	if not M.SPREAD_EXEMPT[tag or ""] then
		pos = spread(npc, pos)
	end

	local snapped = M.Snap(pos)
	if not snapped or recently_failed(m, snapped, now) then return false end

	if m.stopping then
		m.stopping = nil
		if npc.tifAct and npc.tifAct.trans then
			TIF.Action.Clear(npc)
		end
	end

	m.goal, m.speed, m.tag, m.needCompute, m.result, m.startedAt = snapped, speed, tag, true, nil, now
	m.want, m.fresh, m.detour, m.watch, m.stuckN, m.passN = want, true, nil, nil, 0, 0

	if (speed == "run" or speed == "sprint" or speed == "aimrun") and tag ~= "flee" and tag ~= "board"
		and TIF.Weapon.CoveringBurst then
		TIF.Weapon.CoveringBurst(npc, now)
	end

	return true
end

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

	if m.goal and not m.stopping and TIF.TransMW then
		TIF.TransMW.StopHere(npc, m)
	end
	m.goal, m.needCompute, m.tag, m.stopping, m.fresh = nil, false, nil, nil, nil
	m.want, m.detour, m.watch, m.sprintT = nil, nil, nil, nil
	if npc.tifPath:IsValid() then
		npc.tifPath:Invalidate()
	end
end

function M.Moving(npc)
	return npc.tifMove.goal ~= nil
end

function M.UpdateThreatAreas(npc)
	local areas = {}
	for _, c in pairs(npc.tifK.contacts) do
		if c.confirmed and #areas < 3 then
			local a = navmesh.GetNearestNavArea(c.pos, false, 200, false, true)
			if IsValid(a) then
				areas[#areas + 1] = a
			end
		end
	end

	npc.tifThreatAreas = areas

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

local function cost_fn(npc, now)
	local loco = npc.loco
	local step = loco:GetStepHeight() + 6
	local drop = -loco:GetDeathDropHeight()
	local threats = npc.tifThreatAreas or {}
	local lanes = npc.tifFireLanes or {}
	local nThreats, nLanes = #threats, #lanes
	local climb = TIF.TraverseMW and TIF.TraverseMW.Use(npc) and TIF.TraverseMW.MAX_UP or nil
	local av = npc.tifMove.avoid
	local avPos = (av and now < av.untilT) and av.pos or nil
	local avR2 = M.AVOID_R * M.AVOID_R
	return function(area, from, ladder, elevator, length)
		if not IsValid(from) then return 0 end

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
		if area:HasAttributes(NAV_MESH_AVOID) then
			cost = cost + dist * 4
		end
		if avPos and area:GetCenter():DistToSqr(avPos) < avR2 then
			cost = cost + dist * 6
		end
		if area:HasAttributes(NAV_MESH_CROUCH) then
			cost = cost + dist * 0.5
		end
		if nLanes > 0 and in_lane(lanes, area:GetCenter()) then
			cost = cost + dist * 3
		end
		for i = 1, nThreats do
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

M.SPRINT_RAMP = 1.5

local RG_DIRS = { { "f", 0 }, { "l", 90 }, { "r", -90 }, { "bl", 135 }, { "br", -135 } }
function M.RunGunDir(npc)
	local host = npc.tifHomeHost
	if not (host and TIF.GTG.IsVB(host) and TIF.GTG.Clip("mwrg_f", host)) then
		return ""
	end

	local cf = npc.tifCoverFire
	local v = npc.loco:GetVelocity()
	v.z = 0
	if not cf or v:LengthSqr() < 100 * 100 then return "" end
	local rel = math.AngleDifference((cf.aim - npc:GetPos()):Angle().y, v:Angle().y)
	local best, be = "", nil
	for _, d in ipairs(RG_DIRS) do
		local e = math.abs(math.AngleDifference(rel, d[2]))
		if TIF.GTG.Clip("mwrg_" .. d[1], host) and (not be or e < be) then
			best, be = d[1], e
		end
	end

	return best
end

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
			if to:Dot(fwd) > 0 and (not bd or to:LengthSqr() < bd) then
				best, bd = o, to:LengthSqr()
			end
		end
	end

	return best
end

M.PASS_T, M.PASS_MAX = 1.5, 2
M.BACKOFF = 60
M.AVOID_T, M.AVOID_R = 5, 70

local function tif_body(e)
	return IsValid(e) and (e.TIFSoldier or (e.GetClass and e:GetClass() == "tif_civilian")) and not e.tifDead
end

local unstickOut = {}
local unstickHull = { mins = SIDE_MIN, maxs = SIDE_MAX, mask = MASK_NPCSOLID, output = unstickOut }

local function unstick(npc, m, now)
	local me = npc:GetPos()
	local fwd = npc.loco:GetVelocity()
	fwd.z = 0
	if fwd:LengthSqr() < 1 then
		fwd = (m.goal or me) - me fwd.z = 0
	end

	if fwd:LengthSqr() < 1 then
		fwd = npc:GetForward()
	end
	fwd:Normalize()
	local right = Vector(fwd.y, -fwd.x, 0)
	local b = blocker(npc, fwd)
	local C = TIF.Crowd
	if tif_body(b) and C and C.GhostPair and (m.passN or 0) < M.PASS_MAX and C.GhostPair(npc, b, M.PASS_T, now) then
		m.passN = (m.passN or 0) + 1
		if C.MakeWay then
			C.MakeWay(b, npc, fwd, now)
		end
		m.stuckN = math.max(0, (m.stuckN or 1) - 1)
		m.watch = nil
		return
	end

	local s1
	if IsValid(b) then
		local lat = (b:GetPos() - me):Dot(right)
		s1 = lat > 0 and -1 or 1
	else
		s1 = math.random() < 0.5 and 1 or -1
	end

	local bestP, bestF
	unstickHull.start, unstickHull.filter = me, npc
	for k = 1, 2 do
		local sgn = k == 1 and s1 or -s1
		local to = me + right * (sgn * 44) + fwd * 12
		unstickHull.endpos = to
		local tr = util.TraceHull(unstickHull)
		if tr.Fraction > 0.9 then
			bestP = to
			break
		end
		if not bestF or tr.Fraction > bestF then
			bestP, bestF = me + (to - me) * tr.Fraction, tr.Fraction
		end
	end

	if bestF and bestF < 0.3 then
		bestP = me - fwd * M.BACKOFF
	end
	if not tif_body(b) then
		m.avoid = { pos = IsValid(b) and b:GetPos() or (me + fwd * 40), untilT = now + M.AVOID_T }
	end

	m.detour = { pos = bestP, untilT = now + (bestF and bestF < 0.3 and 1.3 or 0.9) }
end

function watch_stuck(npc, m, want, now)
	local me = npc:GetPos()
	local w = m.watch

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

M.WADE_CAP = { 60, 45 }
local base_speed
function speed_of(npc, mode)
	local v = base_speed(npc, mode)
	local w = npc.tifWade
	if w and w > 0 and mode ~= "crawl" then
		v = math.min(v, M.WADE_CAP[w] or v)
	end

	return v
end

function base_speed(npc, mode)
	local s = npc.tifSpeeds
	local mult = npc.tifArch.speeds
	if mode == "walk" then return s.walk * (mult.walk or 1) end
	if mode == "tactical" then return s.tactical * (mult.tactical or 1) end
	if mode == "alert" then
		return (s.alert or s.tactical) * (mult.tactical or 1)
	end

	if mode == "aimrun" then return s.aimrun end
	if mode == "sprint" then return s.sprint * M.SPRINT_SCALE end
	if mode == "crouch" then return s.crouch end
	if mode == "crawl" then return 32 end
	return s.run * (mult.run or 1)
end

function M.Step(npc)

	if npc.tifVeh then return end
	local m = npc.tifMove
	local now = CurTime()

	if npc.tifGlide and TIF.CQB and TIF.CQB.GlideStep and TIF.CQB.GlideStep(npc, now) then
		return
	end

	local pr = npc.tifProne
	if pr and m.goal and m.speed ~= "crawl" then
		local PB = TIF.ProneB
		if PB and PB.IN and pr.phase == PB.IN then
			PB.GetUp(npc)
		end
		return
	end

	if m.goal and m.needCompute then
		if Budget.Take("path", 1) then
			Prof.Begin("path")
			local ok = npc.tifPath:Compute(npc, m.goal, cost_fn(npc, now))
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

	if npc.tifBipod then
		if TIF.BipodMW then
			TIF.BipodMW.Leave(npc, now)
		end
		return
	end

	if m.stopping then
		local a = npc.tifAct
		if not (a and a.trans) or Act_Done(npc, now) then
			M.Stop(npc)
			m.result = "arrived"
		end
		return
	end

	local TR = TIF.TraverseMW
	if TR and TR.Busy(npc, now) then return end

	local ta = npc.tifAct
	if ta and ta.trans and ta.handU and (now - ta.t0) >= ta.dur * ta.handU then
		TIF.Action.Clear(npc)
		m.needCompute = true
	end

	if npc.tifAct and npc.tifAct.trans and not Act_Done(npc, now) then
		if not (m.fresh and string.sub(npc.tifAct.name, 1, 9) == "mwt_turn_") then
			return
		end
		TIF.Action.Clear(npc)
	end

	local ex = npc.tifStartExit
	if ex then
		npc.tifStartExit = nil
		if now >= ex.doneAt - 0.1 and now < ex.doneAt + 0.4 then
			npc.loco:SetVelocity(ex.vel)
		end
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

	if T and T.Reverse and T.Reverse(npc, m, now) then return end

	if TIF.DoorMW and TIF.DoorMW.Check(npc, m, now) then return end

	if TR and TR.Check(npc, m, now) then return end

	local sp = m.speed
	local rg = ""
	if (sp == "sprint" or sp == "run") and TIF.Weapon.CoverFiring and TIF.Weapon.CoverFiring(npc, now) then
		rg = M.RunGunDir(npc)
		if rg == "" then
			sp = "tactical"
		end
	end

	if npc:GetNW2String("tif_rungun", "") ~= rg then
		npc:SetNW2String("tif_rungun", rg)
	end
	npc.tifRunGun = rg ~= "" or nil
	npc.tifAimFree = npc.tifRunGun or (npc.tifAimFree and not npc.tifRunGunWas) or nil
	npc.tifRunGunWas = npc.tifRunGun
	local want = sprint_speed(npc, m, sp, now)

	local d = m.detour
	if d then
		if now > d.untilT or npc:GetPos():DistToSqr(d.pos) < 16 * 16 then
			m.detour, m.watch = nil, nil
			m.needCompute = true
			return
		end

		npc.loco:SetDesiredSpeed(math.max(want, 30))
		npc.loco:Approach(d.pos, 1)
		return
	end

	local a = npc.tifAct
	if a and not a.trans and not npc.tifDowned and not npc.tifProne and not a.keepMoving
		and npc:GetNW2String("tif_act_base", "") == ""
		and (Act_Done(npc, now) or (a.clip.speed or 0) < 1) then
		TIF.Action.Clear(npc)
	end

	local steer
	if TIF.Crowd and TIF.Crowd.Steer then
		local fwd = npc.loco:GetVelocity()
		fwd.z = 0
		if fwd:LengthSqr() < 100 then
			fwd = m.goal - npc:GetPos() fwd.z = 0
		end
		if fwd:LengthSqr() > 1 then
			fwd:Normalize()
			want, steer = TIF.Crowd.Steer(npc, fwd, want, m.goal, now)
		end
	end

	npc.loco:SetDesiredSpeed(want)
	path:Update(npc)
	if steer then
		npc.loco:Approach(steer, TIF.Crowd.WEIGHT)
	end

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

	if now - (m.startedAt or now) > 25 then
		mark_failed(m, m.goal, now)
		M.Stop(npc)
		m.result = "timeout"
	end
end

local FACE_ANG = Angle and Angle(0, 0, 0)

function M.Face(npc, dt)

	if npc.tifVeh or npc.tifLeaving then return end
	local loco = npc.loco

	if npc.tifMelee and npc.tifMelee.fight then
		loco:SetMaxYawRate(0)
		return
	end

	if npc.tifAct and npc.tifAct.trans then
		loco:SetMaxYawRate(0)
		return
	end

	local face = npc.tifFace

	local cf = npc.tifCoverFire

	if cf and CurTime() < cf.untilT and cf.shots > 0 and not npc.tifRunGun then
		face = cf.aim
	end

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
	if prone and prone.phase ~= 2 then return end

	if TIF.TransMW and not M.Moving(npc) and loco:GetVelocity():Length2DSqr() < 10 * 10
		and TIF.TransMW.Turn(npc, want) then return end
	local rate = prone and TIF.ProneB.TURN_RATE or npc.tifArch.turnRate
	local new = math.ApproachAngle(cur, want, rate * dt)
	if math.abs(math.AngleDifference(new, cur)) > 0.01 then
		FACE_ANG.y = new
		npc:SetAngles(FACE_ANG)
	end
end
