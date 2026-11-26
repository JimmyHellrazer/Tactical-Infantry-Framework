local TIF = TIF
TIF.Crowd = TIF.Crowd or {}
local Crowd = TIF.Crowd
local Prof = TIF.Prof

local cvCrowd = CreateConVar("tif_crowd", "1", FCVAR_ARCHIVE,
	"Soldiers and civilians steer round each other and come apart when they overlap (0: off)")

function Crowd.On() return cvCrowd:GetBool() end

Crowd.LOOK = 80
Crowd.LANE = 26
Crowd.SCAN_T = 0.2
Crowd.SIDE = 36
Crowd.WEIGHT = 1.5
Crowd.FOLLOW = 25
Crowd.OVERLAP = 22
Crowd.APART = 28
Crowd.GHOST_AFTER = 0.5
Crowd.GHOST_MIN = 0.6
Crowd.GHOST_GROUP = COLLISION_GROUP_NPC_SCRIPTED
Crowd.UNSTACK_AFTER = 1.0
Crowd.UNSTACK_GAP = 2.0

local function prof_begin(name) if Prof then Prof.Begin(name) end end

local function prof_end() if Prof then Prof.End() end end

local bodyList, bodyPool, lastScanTime = {}, {}, -1
function Crowd.Bodies(now)
	if now - lastScanTime < 0.1 then return bodyList end
	lastScanTime = now
	local count = 0
	local function add_body(ent, isTif)
		count = count + 1
		local body = bodyPool[count]
		if not body then
			body = { vel = Vector() } bodyPool[count] = body
		end
		local vel = (ent.loco and ent.loco:GetVelocity()) or ent:GetVelocity()
		body.e = ent
		body.pos = ent:GetPos()
		body.vel.x, body.vel.y, body.vel.z = vel.x, vel.y, 0
		body.tif = isTif
		bodyList[count] = body
	end

	local soldiers = TIF.Soldiers
	if soldiers then
		for i = 1, #soldiers do
			local soldier = soldiers[i]
			if IsValid(soldier) and not soldier.tifDead and not soldier.tifVeh then
				add_body(soldier, true)
			end
		end
	end

	if TIF.Civ and TIF.Civ.List then
		local civs = TIF.Civ.List()
		for i = 1, #civs do
			local civ = civs[i]
			if not civ.gone and not civ.dead then
				add_body(civ, true)
			end
		end
	end

	local players = player.GetAll()
	for i = 1, #players do
		local ply = players[i]
		if ply:Alive() and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
			add_body(ply, false)
		end
	end

	local npcs = TIF.NPCs
	if npcs then
		for i = 1, #npcs do
			local npc = npcs[i]
			if IsValid(npc) and npc:Health() > 0 then
				add_body(npc, false)
			end
		end
	end

	for i = #bodyList, count + 1, -1 do
		bodyList[i] = nil
	end
	return bodyList
end

function Crowd.Invalidate() lastScanTime = -1 end

local SIDE_MIN, SIDE_MAX = Vector(-12, -12, 8), Vector(12, 12, 56)
local sideOut = {}
local sideHull = { mins = SIDE_MIN, maxs = SIDE_MAX, mask = MASK_NPCSOLID, output = sideOut }
local function side_clear_frac(ent, from, to)
	sideHull.start, sideHull.endpos, sideHull.filter = from, to, ent
	return util.TraceHull(sideHull).Fraction
end

function Crowd.SidePoint(ent, forward, dist, preferredSign)
	local origin = ent:GetPos()
	local right = Vector(forward.y, -forward.x, 0)
	local firstSign = preferredSign or (math.random() < 0.5 and 1 or -1)
	local bestPos, bestFrac
	for attempt = 1, 2 do
		local sign = attempt == 1 and firstSign or -firstSign
		local target = origin + right * (sign * dist) + forward * 10
		local frac = side_clear_frac(ent, origin, target)
		if frac > 0.9 then return target end
		if not bestFrac or frac > bestFrac then
			bestPos, bestFrac = origin + (target - origin) * frac, frac
		end
	end

	return (bestFrac and bestFrac > 0.4) and bestPos or nil
end

function Crowd.Steer(ent, forward, wantSpeed, goal, now)
	if not cvCrowd:GetBool() or not forward then return wantSpeed, nil end
	local state = ent.tifCrowd
	if not state then
		state = {} ent.tifCrowd = state
	end

	if now >= (state.nextT or 0) then
		state.nextT = now + Crowd.SCAN_T
		prof_begin("crowd")
		state.cap, state.sgn = nil, nil
		local origin = ent:GetPos()
		local rightX, rightY = forward.y, -forward.x
		local goalDist = math.huge
		if goal then
			local gx, gy = goal.x - origin.x, goal.y - origin.y
			goalDist = math.sqrt(gx * gx + gy * gy)
		end
		local blocker, blockerAhead, blockerLat
		local scanRadius = Crowd.LOOK + 30
		local scanRadiusSqr = scanRadius * scanRadius
		local bodies = Crowd.Bodies(now)
		for i = 1, #bodies do
			local body = bodies[i]
			if body.e ~= ent then
				local dx, dy = body.pos.x - origin.x, body.pos.y - origin.y
				if dx * dx + dy * dy < scanRadiusSqr and math.abs(body.pos.z - origin.z) < 60 then
					local ahead = dx * forward.x + dy * forward.y
					local lateral = dx * rightX + dy * rightY
					if ahead > 4 and ahead < Crowd.LOOK and math.abs(lateral) < Crowd.LANE and ahead < goalDist + 10
						and (not blockerAhead or ahead < blockerAhead) then
						blocker, blockerAhead, blockerLat = body, ahead, lateral
					end
				end
			end
		end
		if blocker then
			local alongSpeed = blocker.vel.x * forward.x + blocker.vel.y * forward.y
			if alongSpeed > Crowd.FOLLOW then
				if blockerAhead < 60 and alongSpeed < wantSpeed then
					state.cap = math.max(alongSpeed, 30)
				end
			else
				local sign = blockerLat > 6 and -1 or 1
				local sideSpot = Crowd.SidePoint(ent, forward, Crowd.SIDE, sign)
				if sideSpot then
					state.sgn = ((sideSpot.x - origin.x) * rightX + (sideSpot.y - origin.y) * rightY) >= 0 and 1 or -1
					state.fwd = Vector(forward)
				elseif blockerAhead < 40 then
					state.cap = math.min(wantSpeed, 30)
				end
				if alongSpeed < -Crowd.FOLLOW and blockerAhead < 40 then
					state.cap = math.min(state.cap or wantSpeed, wantSpeed * 0.6)
				end
			end
		end
		prof_end()
	end

	local speed = state.cap and math.min(wantSpeed, state.cap) or wantSpeed
	if state.sgn then
		local dir = state.fwd or forward
		local steerTarget = ent:GetPos() + dir * 40 + Vector(dir.y, -dir.x, 0) * (state.sgn * Crowd.SIDE)
		return speed, steerTarget
	end

	return speed, nil
end

local function in_root_clip(ent)
	local act = ent.tifAct
	return act and (act.root or act.to) and not act.finished
end

local function can_ghost(ent)
	if ent.tifVeh or ent.tifBoarding or ent.tifLeaving or ent.tifDead then
		return false
	end
	local group = ent:GetCollisionGroup()
	return group == COLLISION_GROUP_NPC or group == COLLISION_GROUP_NONE or group == Crowd.GHOST_GROUP
end

local function enable_ghost(ent, now)
	if ent.tifCrowdGhost then
		ent.tifCrowdGhost.t = now
		return
	end

	if not can_ghost(ent) then return end
	ent.tifCrowdGhost = { old = ent:GetCollisionGroup(), t = now }
	if ent.tifCrowdGhost.old ~= Crowd.GHOST_GROUP then
		ent:SetCollisionGroup(Crowd.GHOST_GROUP)
	end
end

local function disable_ghost(ent)
	local ghostData = ent.tifCrowdGhost
	ent.tifCrowdGhost = nil
	if ghostData and IsValid(ent) and ent:GetCollisionGroup() == Crowd.GHOST_GROUP and ghostData.old ~= Crowd.GHOST_GROUP then
		ent:SetCollisionGroup(ghostData.old)
	end
end
Crowd.Unghost = disable_ghost

function Crowd.GhostPair(entA, entB, secs, now)
	if not cvCrowd:GetBool() or not (IsValid(entA) and IsValid(entB)) then
		return false
	end
	if not (can_ghost(entA) and can_ghost(entB)) then return false end
	enable_ghost(entA, now)
	enable_ghost(entB, now)
	local holdUntil = now + secs - Crowd.GHOST_MIN
	if entA.tifCrowdGhost then
		entA.tifCrowdGhost.t = math.max(entA.tifCrowdGhost.t, holdUntil)
	end

	if entB.tifCrowdGhost then
		entB.tifCrowdGhost.t = math.max(entB.tifCrowdGhost.t, holdUntil)
	end
	return entA.tifCrowdGhost ~= nil and entB.tifCrowdGhost ~= nil
end

Crowd.WAY_DIST, Crowd.WAY_T, Crowd.WAY_SPEED, Crowd.WAY_AGAIN = 40, 1.2, 70, 4
Crowd.Way = Crowd.Way or {}

function Crowd.MakeWay(blocker, mover, forward, now)
	if not cvCrowd:GetBool() or not (IsValid(blocker) and blocker.TIFSoldier and blocker.tifMove and blocker.loco and IsValid(mover)) then
		return false
	end
	if blocker.tifMove.goal or blocker.tifAct or blocker.tifCov or blocker.tifProne or blocker.tifVeh or blocker.tifShield
		or blocker.tifMelee or blocker.tifBipod or blocker.tifDowned or blocker.tifDead or (blocker.tifCQB and blocker.tifCQB.wait) then return false end
	if now < (blocker.tifWayNext or 0) then return false end
	local right = Vector(forward.y, -forward.x, 0)
	local lateral = (blocker:GetPos() - mover:GetPos()):Dot(right)
	local sidePos = Crowd.SidePoint(blocker, forward, Crowd.WAY_DIST, lateral >= 0 and 1 or -1)
	if not sidePos then return false end
	blocker.tifWayNext = now + Crowd.WAY_AGAIN
	Crowd.Way[blocker] = { pos = sidePos, untilT = now + Crowd.WAY_T }
	return true
end

hook.Add("Tick", "tif_crowd_way", function()
	if next(Crowd.Way) == nil then return end
	local now = CurTime()
	for soldier, way in pairs(Crowd.Way) do
		if not IsValid(soldier) or soldier.tifDead or soldier.tifMove.goal or soldier.tifAct
			or now > way.untilT or soldier:GetPos():DistToSqr(way.pos) < 100 then
			Crowd.Way[soldier] = nil
		else
			soldier.loco:SetDesiredSpeed(Crowd.WAY_SPEED)
			soldier.loco:Approach(way.pos, 1)
		end
	end
end)

local function is_idle_soldier(ent)
	if not (ent.TIFSoldier and not ent.tifDead) then return false end
	if ent.tifCov or ent.tifProne or ent.tifVeh or ent.tifDowned or ent.tifSurrendered or ent.tifAct or ent.tifMedic or ent.tifBipod
		or ent.tifCQB or ent.tifBoarding or ent.tifLeaving then return false end
	if ent.tifMove and ent.tifMove.goal then return false end
	return ent.loco and ent.loco:GetVelocity():Length2DSqr() < 225
end
Crowd.IdleSoldier = is_idle_soldier

local function is_unstacking(ent) return ent.tifMove and ent.tifMove.goal and ent.tifMove.tag == "unstack" end

function Crowd.Unstack(ent, now)
	if now < (ent.tifNextUnstack or 0) then return false end
	ent.tifNextUnstack = now + Crowd.UNSTACK_GAP
	local move = TIF.Move
	if not (move and move.Spread and move.SetGoal) then return false end
	local origin = ent:GetPos()
	local spot = move.Spread(ent, origin)
	if not spot or spot:DistToSqr(origin) < 400 then return false end
	if not move.SetGoal(ent, spot, "walk", "unstack") then return false end
	if ent.tifPost and ent.tifPost:DistToSqr(origin) < 10000 then
		ent.tifPost = spot
	end

	return true
end

local tifBodies, nearEntities = {}, {}
function Crowd.Tick(now)
	local enabled = cvCrowd:GetBool()
	prof_begin("crowd")
	local bodies = Crowd.Bodies(now)
	local tifCount = 0
	for i = 1, #bodies do
		local body = bodies[i]
		if body.tif and IsValid(body.e) then
			tifCount = tifCount + 1
			tifBodies[tifCount] = body
		end
	end

	for i = #tifBodies, tifCount + 1, -1 do
		tifBodies[i] = nil
	end
	for k in pairs(nearEntities) do
		nearEntities[k] = nil
	end

	if enabled then
		for i = 1, tifCount do
			local bodyA = tifBodies[i]
			for j = i + 1, tifCount do
				local bodyB = tifBodies[j]
				local dx = math.abs(bodyA.pos.x - bodyB.pos.x)
				local dy = math.abs(bodyA.pos.y - bodyB.pos.y)
				local dz = math.abs(bodyA.pos.z - bodyB.pos.z)
				if dx < Crowd.APART and dy < Crowd.APART and dz < 60 then
					nearEntities[bodyA.e], nearEntities[bodyB.e] = true, true
					if dx < Crowd.OVERLAP and dy < Crowd.OVERLAP then
						local overlaps = bodyA.e.tifCrowdOv
						if not overlaps then
							overlaps = {} bodyA.e.tifCrowdOv = overlaps
						end
						overlaps[bodyB.e] = overlaps[bodyB.e] or now
						if now - overlaps[bodyB.e] >= Crowd.GHOST_AFTER or in_root_clip(bodyA.e) or in_root_clip(bodyB.e) then
							enable_ghost(bodyA.e, now)
							enable_ghost(bodyB.e, now)
						end
						if now - overlaps[bodyB.e] >= Crowd.UNSTACK_AFTER and not is_unstacking(bodyA.e) and not is_unstacking(bodyB.e) then
							local idleA, idleB = is_idle_soldier(bodyA.e), is_idle_soldier(bodyB.e)
							local mover = (idleA and idleB) and (bodyA.e:EntIndex() > bodyB.e:EntIndex() and bodyA.e or bodyB.e) or (idleA and bodyA.e) or (idleB and bodyB.e)
							if mover then
								Crowd.Unstack(mover, now)
							end
						end
					elseif bodyA.e.tifCrowdOv then
						bodyA.e.tifCrowdOv[bodyB.e] = nil
					end
				elseif bodyA.e.tifCrowdOv then
					bodyA.e.tifCrowdOv[bodyB.e] = nil
				end
			end
		end
	end

	for i = 1, tifCount do
		local ent = tifBodies[i].e
		if not nearEntities[ent] then
			ent.tifCrowdOv = nil
		end
		local ghostData = ent.tifCrowdGhost
		if ghostData and (not enabled or (not nearEntities[ent] and now - ghostData.t >= Crowd.GHOST_MIN)) then
			disable_ghost(ent)
		end
	end

	prof_end()
end

timer.Create("tif_crowd_tick", 0.25, 0, function()
	if TIF.AIDisabled and TIF.AIDisabled() then return end
	local ok, err = pcall(Crowd.Tick, CurTime())
	if not ok and TIF.Error then
		TIF.Error("crowd: ", tostring(err))
	end
end)

cvars.AddChangeCallback("tif_crowd", function(_, _, new)
	if new ~= "0" then return end
	for _, ent in ipairs(ents.GetAll()) do if ent.tifCrowdGhost then disable_ghost(ent) end end
end, "tif_crowd")
