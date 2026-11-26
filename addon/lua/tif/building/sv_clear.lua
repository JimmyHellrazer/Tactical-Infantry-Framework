local TIF = TIF
local AW = TIF.AWARE
local SQ = TIF.Squad
local BLD = TIF.Building

TIF.CQB = TIF.CQB or {}
local CQB = TIF.CQB

CQB.TEAM = 4
CQB.STACK_TIMEOUT = 15

CQB.STACK_MAX = 45
CQB.STACK_SETTLE = 1.0
CQB.ENTRY_GAP = 0.45
CQB.HOLD_MIN = 1.0
CQB.HOLD_WAIT = 5
CQB.HOLD_ENTER_MAX = 15
CQB.MAX_ROOMS = 10
CQB.TIMEOUT = 180
local TEAM_PREF = { assault = 1, breacher = 1, rifleman = 2, leader = 3, support = 5, marksman = 6 }

local function log(sq, ...)
	if SQ.Log then
		SQ.Log(sq, "[cqb] ", ...)
	end

	if TIF.Event then
		TIF.Event("cqb", "squad ", sq.id, " ", sq.faction or "", ": ", ...)
	end
end

local function flat(v)
	local f = Vector(v.x, v.y, 0)
	f:Normalize()
	return f
end

local function members(sq)
	local out = {}
	for _, m in ipairs(SQ.Members(sq)) do
		out[#out + 1] = m
	end

	return out
end

local function centroid(list)
	local c = Vector()
	for _, m in ipairs(list) do
		c:Add(m:GetPos())
	end

	return c / math.max(1, #list)
end

local breach_plan, pick_method

CQB.NODOOR_CHANCE = 0.5
CQB.METHOD_WEIGHTS = { open = 4, kick = 3, grenade = 3, hammer = 2 }
local cvVariety = CreateConVar("tif_cqb_variety", "1", FCVAR_ARCHIVE,
	"Room entries vary: doors opened by hand, kicked, sledgehammered or grenaded, open doorways entered two at once (0: always the same)")
CQB.Variety = function() return cvVariety:GetBool() end

local function setup_door(cq, d, fromRoom)
	local toRoom, sign = BLD.OtherSide(d, fromRoom)
	cq.door, cq.room = d, toRoom
	cq.inward = d.normal * sign
	if d.stair then
		cq.slots, cq.points = BLD.StairPlan(d, sign > 0, toRoom, #cq.team)
	else
		cq.slots = BLD.StackSlots(d, cq.inward, #cq.team)
		cq.points = BLD.EntryPoints(d, cq.inward, toRoom)
	end

	cq.flow = fromRoom ~= nil
	cq.phase, cq.t0 = "stack", CurTime()
	cq.released = 0
	cq.quietSince = nil
	cq.opening, cq.entryPrep, cq.stackReady = nil, nil, 0
	cq.stackBest, cq.progressAt = {}, CurTime()
	cq.doorAt, cq.doorBy = nil, nil
	cq.flashed, cq.flashWait = nil, nil
	cq.doorMethod, cq.doorDue, cq.nodoorGo, cq.wentIn, cq.allInAt = nil, nil, nil, nil, nil
	cq.stalledLogged, cq.committed = nil, nil

	cq.breachPlan = nil
	if d.stair then return end
	if BLD.Closed(d) then
		local commanded = cq.firstDoor ~= false and cq.methodSet
		local method = commanded and cq.method or pick_method(cq, d)
		cq.breachPlan = breach_plan(cq, cq.team, method)

		if not cq.breachPlan and (method == "grenade" or method == "hammer") then
			cq.breachPlan = breach_plan(cq, cq.team, method == "hammer" and "kick" or "open")
		end
	elseif cvVariety:GetBool() and #cq.team >= 2 and math.random() < CQB.NODOOR_CHANCE then
		cq.breachPlan = breach_plan(cq, cq.team, "nodoor")
	end
end

local function locked(d)
	local e = d.ent
	if not IsValid(e) then return false end
	local ok, v = pcall(e.GetInternalVariable, e, "m_bLocked")
	return ok and v == true
end

local cvDoorOff = CreateConVar("tif_cqb_door_off", "1", FCVAR_ARCHIVE, "Room clears: kicked doors come off, opened doors stop blocking (1/0)")

local function door_has_portal(e)
	local name = e:GetName()
	if not name or name == "" then return false end
	for _, ap in ipairs(ents.FindByClass("func_areaportal")) do
		local ok, t = pcall(ap.GetInternalVariable, ap, "target")
		if ok and t == name then return true end
	end

	return false
end
CQB.DoorHasPortal = door_has_portal

local function door_off(e, inward, hard)
	if not (cvDoorOff:GetBool() and IsValid(e)) then return end
	if not hard or e:GetClass() ~= "prop_door_rotating" or door_has_portal(e) then
		e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		return
	end

	local p = ents.Create("prop_physics")
	if not IsValid(p) then
		e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		return
	end

	p:SetModel(e:GetModel())
	p:SetPos(e:GetPos())
	p:SetAngles(e:GetAngles())
	p:SetSkin(e:GetSkin() or 0)
	for i = 0, (e:GetNumBodyGroups() or 1) - 1 do
		p:SetBodygroup(i, e:GetBodygroup(i))
	end

	p:Spawn()
	p:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	local ph = p:GetPhysicsObject()
	if IsValid(ph) then
		ph:Wake()
		ph:SetVelocity((inward or Vector()) * 320 + Vector(0, 0, 60))
		ph:AddAngleVelocity(VectorRand() * 120)
	end

	SafeRemoveEntityDelayed(p, 90)
	e:SetNoDraw(true)
	e:SetNotSolid(true)
	e.tifDoorOff = true
end
CQB.DoorOff = door_off

local function open_door(d, by, method, inward)
	local e = d.ent
	local hard = method == "kick" or method == "breach" or method == "hammer"

	if method == "grenade" and IsValid(e) and e:GetClass() == "prop_door_rotating" then
		e:Fire("SetSpeed", "300")
	end

	if method == "hammer" and IsValid(e) then
		e:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 90, math.random(90, 100))
		method = "kick"
	end

	if (method == "kick" or method == "breach") and IsValid(e) then
		e:Fire("Unlock")
		if e:GetClass() == "prop_door_rotating" then
			e:Fire("SetSpeed", "450")
		end
		if method == "breach" then
			e:EmitSound("weapons/shotgun/shotgun_fire" .. math.random(6, 7) .. ".wav", 100, math.random(92, 100))
			local ed = EffectData()
			ed:SetOrigin(e:WorldSpaceCenter())
			util.Effect("MetalSpark", ed, true, true)
		end
		e:EmitSound("physics/wood/wood_furniture_break" .. math.random(1, 2) .. ".wav", 85, math.random(95, 105))
	end

	BLD.Open(d, by)
	door_off(e, inward, hard)
end

local function next_door(cq, room)
	local best, bestCost
	for _, d in ipairs(BLD.DoorsOf(room)) do
		local other = BLD.OtherSide(d, room)
		if other and not cq.cleared[other.id] then
			local cost = d.center:Distance(cq.target) + (d.stair and 150 or 0)
			if not bestCost or cost < bestCost then
				best, bestCost = d, cost
			end
		end
	end

	return best
end

CQB.GHOST = COLLISION_GROUP_NPC_SCRIPTED

local function team_ghost(m, on)
	if not IsValid(m) or not m.GetCollisionGroup then return end
	if on then
		if m.tifCQBGroup == nil and not m.tifVeh then
			local g = m:GetCollisionGroup()
			if g == COLLISION_GROUP_NPC or g == COLLISION_GROUP_NONE then
				m.tifCQBGroup = g
				m:SetCollisionGroup(CQB.GHOST)
			end
		end
	elseif m.tifCQBGroup ~= nil then

		local held = false
		if m.tifCrowdGhost then
			m.tifCrowdGhost.old, held = m.tifCQBGroup, true
		end
		if m.tifShieldGroup then
			m.tifShieldGroup, held = m.tifCQBGroup, true
		end
		if not held and m:GetCollisionGroup() == CQB.GHOST then
			m:SetCollisionGroup(m.tifCQBGroup)
		end
		m.tifCQBGroup = nil
	end
end
CQB.TeamGhost = team_ghost

local function clear_acts(m)
	team_ghost(m, false)
	if m.TIFSetSlim then
		m:TIFSetSlim(false)
	end

	m.tifGlide, m.tifCQBAlt, m.tifCQBFails = nil, nil, nil
	if m.tifAct and (m.tifAct.name == m.tifCQBLoop or m.tifAct.name == m.tifCQBActName) then
		TIF.Action.Clear(m)
	end

	m.tifCQBQueue, m.tifCQBActUntil, m.tifCQBLoop, m.tifCQBDelay, m.tifCQBActName = nil, nil, nil, nil, nil
	if m.GetNW2Bool and m:GetNW2Bool("tif_sledge", false) then
		m:SetNW2Bool("tif_sledge", false)
	end
end

local function release(sq, cq, reason)
	for _, m in ipairs(members(sq)) do
		m.tifCQB = nil
		clear_acts(m)
	end

	log(sq, "done: ", reason, " (", table.Count(cq.cleared), " room(s) cleared)")
	sq.cqb = nil
	if cq.prevOrder then
		sq.order = cq.prevOrder
		sq.order.time = CurTime()
		SQ.Publish(sq)
	end

	hook.Run("TIF_CQBDone", sq, reason, cq)
end

function CQB.DoorAt(pos, radius)
	radius = radius or 120
	local best, bestD
	for _, d in ipairs(BLD.Scan(pos, math.max(radius, 300))) do
		local dd = d.center:DistToSqr(pos)
		if dd < radius * radius and (not bestD or dd < bestD) then
			best, bestD = d, dd
		end
	end

	return best
end

local function near_side_room(d, from)
	local pa = IsValid(d.areaA) and d.areaA:GetCenter() or d.center - d.normal * 60
	local pb = IsValid(d.areaB) and d.areaB:GetCenter() or d.center + d.normal * 60
	local onA = from:DistToSqr(pa) <= from:DistToSqr(pb)
	return BLD.RoomOf(onA and d.areaA or d.areaB), onA
end

function CQB.Start(sq, target, quiet, opts)
	if not sq or sq.cqb then return false end
	opts = opts or {}
	local list = members(sq)
	if #list == 0 then return false end
	local from = centroid(list)
	local best, fromRoom
	local targetRoom
	if opts.door then

		best = opts.door
		local onA
		fromRoom, onA = near_side_room(best, from)
		targetRoom = BLD.RoomOf(onA and best.areaB or best.areaA)
		if not target then
			target = best.center + best.normal * (onA and 200 or -200)
		end
	else
		local doors = BLD.Scan(target, 1100)
		targetRoom = BLD.RoomAt(target)

		local bestCost
		for _, d in ipairs(doors) do
			if d.exterior then
				local cost = from:Distance(d.center) + d.center:Distance(target) * 1.5
				if targetRoom and BLD.RoomOf(d.areaB) == targetRoom then
					cost = cost - 600
				end
				if not bestCost or cost < bestCost then
					best, bestCost = d, cost
				end
			end
		end
	end

	if not best then
		if not quiet then
			log(sq, "no way in found near ", tostring(target))
		end
		return false
	end

	local size = opts.teamSize or CQB.TEAM
	table.sort(list, function(a, b) return (TEAM_PREF[a.tifArchId] or 4) < (TEAM_PREF[b.tifArchId] or 4) end)
	local team, outside = {}, {}
	for _, m in ipairs(list) do
		if #team < size and (TEAM_PREF[m.tifArchId] or 4) < 5 then
			team[#team + 1] = m
		else
			outside[#outside + 1] = m
		end
	end

	if #team < 2 then

		team, outside = {}, {}
		for i, m in ipairs(list) do if i <= size then team[#team + 1] = m else outside[#outside + 1] = m end end
	end

	if #team < (opts.door and 1 or 2) then return false end
	local cq = { target = Vector(target), targetRoom = targetRoom, team = team, outside = outside,
		cleared = {}, started = CurTime(), hold = opts.hold and true or false, method = opts.method or "open",
		methodSet = opts.method ~= nil,
		onEntry = opts.onEntry, single = opts.single and true or false, firstDoor = true }
	cq.prevOrder = sq.order
	sq.cqb = cq
	for _, m in ipairs(team) do
		team_ghost(m, true)
	end

	sq.order = { kind = "clear", pos = Vector(target), time = CurTime() }
	SQ.Publish(sq)
	setup_door(cq, best, fromRoom)

	if opts.door then
		cq.flow = false
	end

	for i, m in ipairs(outside) do
		local side = Vector(-cq.inward.y, cq.inward.x, 0) * ((i % 2 == 0) and 1 or -1)
		local p = TIF.Move.Snap(best.center - cq.inward * (220 + 40 * i) + side * (90 + 30 * i)) or m:GetPos()
		m.tifCQB = { goal = p, face = best.center + Vector(0, 0, 50), speed = "tactical", crouch = true, label = "cover the building" }
	end

	log(sq, "start: team ", #team, ", outside ", #outside, ", door ", best.id, " (", #cq.slots, " slots)")
	TIF.Say(team[1], "moving", 0.8)
	return true
end

local function cclip(m, n) return m.tifHomeHost and TIF.GTG.Clip(n, m.tifHomeHost) or nil end

local function travel_yaw(c) return math.deg(math.atan2(c.move[2], c.move[1])) end

local function flat_yaw(v) return Vector(v.x, v.y, 0):Angle().y end

local function lr_variant(m, fmt, wantLeft)
	local any, anyC
	for _, s in ipairs({ "l", "r" }) do
		local n = string.format(fmt, s)
		local c = cclip(m, n)
		if c then

			if (c.move[3] > 0) == wantLeft then return n, c end
			any, anyC = any or n, anyC or c
		end
	end

	return any, anyC
end

local function aim_travel(c, pos, target)
	return flat_yaw(target - pos) - travel_yaw(c)
end

CQB.CROSS_SHIFT_MAX = 40

local function cross_point(c, S, yaw, center, n)
	if not TIF.Action.RootAt then return nil end
	local r = math.rad(yaw)
	local cs, sn = math.cos(r), math.sin(r)
	local prev, pu
	for k = 0, 50 do
		local u = k / 50
		local x, y = TIF.Action.RootAt(c, u)
		local P = Vector(S.x + x * cs - y * sn, S.y + x * sn + y * cs, S.z)
		local side = (P - center):Dot(n)
		if prev and prev < 0 and side >= 0 then
			local f = prev / (prev - side)
			local x0, y0 = TIF.Action.RootAt(c, pu)
			local P0 = Vector(S.x + x0 * cs - y0 * sn, S.y + x0 * sn + y0 * cs, S.z)
			return P0 + (P - P0) * f
		end
		prev, pu = side, u
	end

	return nil
end

local function centre_cross(c, S0, target, center, n)
	local S = Vector(S0)
	local lat = Vector(-n.y, n.x, 0)
	for _ = 1, 4 do
		local yaw = aim_travel(c, S, target)
		local P = cross_point(c, S, yaw, center, n)
		if not P then return S0, aim_travel(c, S0, target) end
		local off = (P - center):Dot(lat)
		if math.abs(off) < 1 then break end
		S = S - lat * off
	end

	local shift = Vector(S.x - S0.x, S.y - S0.y, 0):Length()
	if shift > CQB.CROSS_SHIFT_MAX then return S0, aim_travel(c, S0, target) end
	return S, aim_travel(c, S, target)
end
CQB.CentreCross = centre_cross

CQB.BREACH_READY = 45
CQB.GO_HULL = { Vector(-10, -10, 8), Vector(10, 10, 60) }

CQB.GLIDE_R = 64
CQB.GLIDE_SPEED = 110
local GLIDE_MIN, GLIDE_MAX = Vector(-12, -12, 4), Vector(12, 12, 60)

function CQB.Glide(npc, goal, now, maxR)
	local gl = npc.tifGlide
	if gl and gl.goal.x == goal.x and gl.goal.y == goal.y then
		gl.seen = now
		return true
	end

	local pos = npc:GetPos()
	local d = goal - pos
	local dz = d.z
	d.z = 0
	local dist = d:Length()
	if dist > (maxR or CQB.GLIDE_R) or dist < 1 or math.abs(dz) > 18 then
		npc.tifGlide = nil
		return false
	end

	if npc.tifAct and not npc.tifAct.loop and not npc.tifAct.finished then
		return false
	end
	local tr = util.TraceHull({ start = pos, endpos = goal, mins = GLIDE_MIN, maxs = GLIDE_MAX, mask = MASK_NPCSOLID_BRUSHONLY, filter = npc })
	if tr.Hit then return false end
	TIF.Move.Stop(npc)
	if npc.tifAct and npc.tifAct.trans then
		TIF.Action.Clear(npc)
	end

	npc.tifGlide = { goal = Vector(goal), speed = CQB.GLIDE_SPEED, seen = now, t = now }
	return true
end

function CQB.GlideStep(npc, now)
	local gl = npc.tifGlide
	if not gl then return false end
	if not npc.tifCQB or now - gl.seen > 0.5 or (npc.tifAct and not npc.tifAct.loop and not npc.tifAct.finished) then
		npc.tifGlide = nil
		return false
	end

	local dt = math.Clamp(now - (gl.t or now), 0, 0.1)
	gl.t = now
	local pos = npc:GetPos()
	local d = gl.goal - pos
	local dz = d.z
	d.z = 0
	local dist = d:Length()
	if dist < 0.5 then
		npc.tifGlide = nil
		return false
	end

	local step = math.min(dist, gl.speed * dt)
	d:Normalize()
	npc:SetPos(Vector(pos.x + d.x * step, pos.y + d.y * step, pos.z + dz * (step / dist)))
	return true
end

CQB.THROUGH_BACK, CQB.THROUGH_IN, CQB.THROUGH_NEAR = 40, 48, 72

function CQB.Through(npc, cq, goal, now)
	local d = cq and cq.door
	if not (d and cq.inward and not d.stair) or BLD.Closed(d) then return nil end
	local c, n = d.center, cq.inward
	local pos = npc:GetPos()
	local sm, sg = (pos - c):Dot(n), (goal - c):Dot(n)
	if sm * sg >= 0 or math.abs(sg) < 8 then return nil end
	local side = sm < 0 and -1 or 1
	local front = c + n * (side * CQB.THROUGH_BACK)
	front.z = pos.z
	local fd = Vector(pos.x - front.x, pos.y - front.y, 0):Length()
	local cd = Vector(pos.x - c.x, pos.y - c.y, 0):Length()
	if fd < CQB.THROUGH_NEAR or cd < CQB.THROUGH_NEAR then
		local inside = c - n * (side * CQB.THROUGH_IN)
		inside.z = pos.z
		if CQB.Glide(npc, inside, now, 170) then return "glide" end
	end

	return (TIF.Move.Snap(front)) or front
end

function CQB.PathTrouble(npc, goal, ok, now)
	local m = npc.tifMove
	local failed = not ok or (m and m.goal == nil and (m.result == "fail" or m.result == "stuck" or m.result == "timeout"))
	if not failed then return nil end
	npc.tifCQBFails = (npc.tifCQBFails or 0) + 1
	if npc.tifCQBFails == 3 then
		local sq = npc.tifSquad
		if TIF.Event then TIF.Event("cqb", "squad ", sq and sq.id or "?", ": ", npc:GetClass(), "#", npc:EntIndex(),
			string.format(" can't get to his spot %.0f u away (%s)", npc:GetPos():Distance(goal), tostring(m and m.result or "goal refused"))) end
	end

	if npc.tifCQBFails >= 2 then
		local a = math.random() * math.pi * 2
		local alt = TIF.Move.Snap(goal + Vector(math.cos(a) * 36, math.sin(a) * 36, 0))
		if alt then
			npc.tifCQBAlt = { pos = alt, untilT = now + 3, for_ = goal }
		end
	end

	return true
end

CQB.GO_WARP_MIN = 6
CQB.GO_WARP_AT = 0.1

local UP40 = Vector(0, 0, 40)

local function line_clear(a, b, npc)
	local tr = util.TraceLine({ start = a + UP40, endpos = b + UP40, mask = MASK_NPCSOLID_BRUSHONLY, filter = npc })
	return not tr.Hit or tr.Fraction > 0.97
end

local function clip_path_clear(npc, c, yaw, cq, from)
	if not (c and TIF.Action.RootAt and cq and cq.door) then return true end
	local p0 = from or npc:GetPos()
	local r = math.rad(yaw)
	local x, y = TIF.Action.RootAt(c, 1)
	local e = Vector(p0.x + x * math.cos(r) - y * math.sin(r), p0.y + x * math.sin(r) + y * math.cos(r), p0.z)
	local dc = cq.door.center
	if (e - dc):Dot(cq.inward) < 12 then return false end
	local tr = util.TraceHull({ start = e + Vector(0, 0, 2), endpos = e + Vector(0, 0, 2), mins = CQB.GO_HULL[1], maxs = CQB.GO_HULL[2],
		mask = MASK_NPCSOLID_BRUSHONLY, filter = npc })
	if tr.StartSolid then return false end
	return line_clear(p0, dc, npc) and line_clear(dc, e, npc)
end
CQB.ClipPathClear = clip_path_clear

local function go_item(cq, b, m)
	local target = cq.door.center + cq.inward * 70
	local opts = { root = true }

	if b.stand and IsValid(m) then
		local c = cclip(m, b.go)
		if c and TIF.Action.RootAt then
			local wu = b.warpU or 0.3
			local x, y, rr = TIF.Action.RootAt(c, wu)
			local r = math.rad(b.yaw)
			local cs, sn = math.cos(r), math.sin(r)
			opts.to = { pos = b.stand + Vector(x * cs - y * sn, x * sn + y * cs, 0), yaw = b.yaw + (b.warpU and rr or 0) }
			opts.warpU = wu
		end
	end

	local warped = false
	if not b.stand and b.from and IsValid(m) then
		local c = cclip(m, b.go)
		local off = m:GetPos() - b.from
		off.z = 0
		if c and TIF.Action.RootAt and off:Length() > CQB.GO_WARP_MIN then
			local wu = math.Clamp(math.max(b.doorU or 0.35, b.moveU or 0) + CQB.GO_WARP_AT, 0.25, 0.7)
			local x, y, r = TIF.Action.RootAt(c, wu)
			local rad = math.rad(b.yaw)
			local cs, sn = math.cos(rad), math.sin(rad)
			opts.to = { pos = b.from + Vector(x * cs - y * sn, x * sn + y * cs, 0), yaw = b.yaw + r }
			opts.warpU = wu
			warped = true
		end
	end

	return { name = b.go, opts = opts, hold = 0.9,
		yawFn = function(npc)
			if b.stand or warped then return b.yaw end
			local c = cclip(npc, b.go)
			return c and aim_travel(c, npc:GetPos(), target) or b.yaw
		end,

		check = function(npc, yaw)
			if b.stand ~= nil then return true end
			if warped then
				return clip_path_clear(npc, cclip(npc, b.go), b.yaw, cq, b.from)
			end
			return clip_path_clear(npc, cclip(npc, b.go), yaw, cq)
		end }
end

CQB.BREACH_CLIPS = {
	open = { "mwq_br_%s_1st_open", "mwq_br_%s_2nd_go", "mwq_br_%s_1st_idle", "mwq_br_%s_kick_idle" },
	kick = { "mwq_br_%s_1st_kick", "mwq_br_%s_kick_2nd_go", "mwq_br_%s_kick_idle", "mwq_br_%s_kick_idle" },
	grenade = { "mwq_br_%s_gren_1st", "mwq_br_%s_gren_2nd", "mwq_br_%s_gren_idle", "mwq_br_%s_gren_idle" },
	nodoor = { "mwq_br_%s_nodoor_1st", "mwq_br_%s_nodoor_2nd", "mwq_br_%s_nodoor_idle", "mwq_br_%s_nodoor_idle" },
}
CQB.BREACH_CLIPS.breach = CQB.BREACH_CLIPS.kick

CQB.BREACH_CLIPS.hammer = { "mwq_br_sledge", "mwq_br_%s_kick_2nd_go", "mwq_br_%s_kick_idle", "mwq_br_%s_kick_idle", hammer = true }
CQB.HAMMER_HIT = { 11, 47 }
CQB.HAMMER_YAW = -90
CQB.HAMMER_EDGE = 10
CQB.KICK_BACK = 34

CQB.BREACH_U = {
	mwq_br_l_gren_1st = { door = 0.19, rel = 0.27 },
	mwq_br_r_gren_1st = { door = 0.40, rel = 0.52 },
	mwq_br_l_gren_2nd = { move = 0.72 },
	mwq_br_r_gren_2nd = { move = 0.57 },
}

function CQB.MoveStartU(c)
	if not (c and TIF.Action.RootAt) then return 0 end
	for k = 1, 50 do
		local u = k / 50
		local x, y = TIF.Action.RootAt(c, u)
		if x * x + y * y > 36 then return u - 0.02 end
	end

	return 0
end

function breach_plan(cq, team, method)
	local d = cq.door
	local set = CQB.BREACH_CLIPS[method] or CQB.BREACH_CLIPS.open
	local plan = { method = method }
	for i = 1, math.min(2, #team) do
		local m, slot = team[i], cq.slots[i]
		if not slot then break end
		local wantLeft = slot.side == 1
		local goN, goC = lr_variant(m, set[i], wantLeft)

		local cross = {}
		if goC and not (set.hammer and i == 1) then
			local tgt = d.center + cq.inward * 70

			local function ok(c)
				if not c then return false end
				local S, yw = centre_cross(c, slot.pos, tgt, d.center, cq.inward)
				local free = S == slot.pos or not util.TraceHull({ start = S + Vector(0, 0, 8), endpos = S + Vector(0, 0, 8),
					mins = Vector(-13, -13, 0), maxs = Vector(13, 13, 64), mask = MASK_NPCSOLID_BRUSHONLY }).StartSolid
				if not free then
					S, yw = slot.pos, aim_travel(c, slot.pos, tgt)
				end
				cross[c] = { S, yw }
				return clip_path_clear(m, c, yw, cq, S)
			end
			if not ok(goC) then
				local n2, c2 = lr_variant(m, set[i], not wantLeft)
				if c2 and n2 ~= goN and ok(c2) then
					goN, goC = n2, c2
				else
					goN, goC = nil, nil
				end
			end
		end
		if not goC then

			if i == 1 then return nil end
			break
		end

		local hammer = set.hammer and i == 1
		local s = hammer and (slot.side == 1 and "l" or "r") or string.match(goN, "mwq_br_(%a)_") or "r"
		local idleN = string.format(set[i + 2], s)
		local target = d.center + cq.inward * 70
		local from = cross[goC] and cross[goC][1] or Vector(slot.pos)
		local yaw = cross[goC] and cross[goC][2] or aim_travel(goC, slot.pos, target)
		local stand
		if hammer then

			yaw = flat_yaw(cq.inward) + CQB.HAMMER_YAW
			local left = Vector(-cq.inward.y, cq.inward.x, 0)
			local hit = d.center + left * (slot.side * math.max(0, d.width / 2 - CQB.HAMMER_EDGE))
			local r = math.rad(yaw)
			local fx, fy = math.cos(r), math.sin(r)
			local hx, hy = CQB.HAMMER_HIT[1], CQB.HAMMER_HIT[2]
			local p = hit - Vector(hx * fx - hy * fy, hx * fy + hy * fx, 0)
			p.z = slot.pos.z
			local tr = util.TraceHull({ start = p + Vector(0, 0, 8), endpos = p + Vector(0, 0, 8), mins = Vector(-13, -13, 0),
				maxs = Vector(13, 13, 64), mask = MASK_NPCSOLID_BRUSHONLY })
			if tr.StartSolid then return nil end
			stand = p
		end
		local U = CQB.BREACH_U[goN] or {}
		plan[i] = { m = m, go = goN, goDur = goC.dur, wait = cclip(m, idleN) and { name = idleN, yaw = yaw } or nil, yaw = yaw,
			from = Vector(from),
			doorU = U.door or 0.35, relU = U.rel, moveU = U.move or CQB.MoveStartU(goC), stand = stand }

		for _, tg in ipairs(goC.tags or {}) do
			local ev = istable(tg[4]) and tg[4].MoveEvent
			if isstring(ev) and (string.find(ev, "door", 1, true) or string.find(ev, "kick", 1, true)) then
				plan[i].doorU = tg[2] break
			end
		end

		if (method == "kick" or method == "breach") and i == 1 and TIF.Action.RootAt then
			local du = plan[i].doorU
			local x, y, r = TIF.Action.RootAt(goC, du)
			local y0 = flat_yaw(cq.inward) - r
			local rad = math.rad(y0)
			local cs, sn = math.cos(rad), math.sin(rad)
			local atDoor = d.center - cq.inward * CQB.KICK_BACK
			atDoor.z = slot.pos.z
			local p = atDoor - Vector(x * cs - y * sn, x * sn + y * cs, 0)
			local tr = util.TraceHull({ start = p + Vector(0, 0, 8), endpos = p + Vector(0, 0, 8), mins = Vector(-13, -13, 0),
				maxs = Vector(13, 13, 64), mask = MASK_NPCSOLID_BRUSHONLY })
			if not tr.StartSolid and line_clear(p, atDoor, m) then
				plan[i].stand, plan[i].yaw, plan[i].warpU = p, y0, du
				if plan[i].wait then
					plan[i].wait.yaw = y0
				end
			end
		end
	end

	return plan[1] and plan or nil
end

local function corner_look(d, p)
	local dir = p - d.center
	dir.z = 0
	dir:Normalize()
	return p + dir * 120 + Vector(0, 0, 50)
end

CQB.FLASH_DEPTH = 220
local cvFlash = CreateConVar("tif_cqb_flash", "1", FCVAR_ARCHIVE, "Breachers flash rooms first: 0 off, 1 allies of players, 2 all")

local function allied_to_players(m)
	for _, ply in player.Iterator() do
		if TIF.Relation(m, ply) == TIF.REL_ALLY then return true end
	end
	return false
end

CQB.DOOR_FLASH = {
	mwdr_l_flash = { yaw = 15, hand = Vector(40, 3, 42), u = 0.373 },
	mwdr_r_flash = { yaw = -106, hand = Vector(-2, -40, 43), u = 0.351 },
}

local function door_flash(m, toYaw)
	local best, bestYaw, bestTurn
	for name, k in pairs(CQB.DOOR_FLASH) do
		if m.tifHomeHost and TIF.GTG.Clip(name, m.tifHomeHost) then
			local y = toYaw - k.yaw
			local turn = math.abs(math.AngleDifference(y, m:GetAngles().y))
			if not bestTurn or turn < bestTurn then
				best, bestYaw, bestTurn = name, y, turn
			end
		end
	end

	if not best then return nil end
	local k = CQB.DOOR_FLASH[best]
	return best, bestYaw, k.hand, k.u
end

local cvFlashChance = CreateConVar("tif_cqb_flash_chance", "0.55", FCVAR_ARCHIVE, "Share of rooms breachers flash first (0-1)")
CQB.AFTER_BANG = 0.25
CQB.FLASH_WAIT_MAX = 5

local function flash_in(sq, cq, team, now)
	local mode = cvFlash:GetInt()
	local GR = TIF.GrenadeMW
	local m = team[2] or team[1]
	if mode == 0 or not (GR and GR.Throw) or not IsValid(m) or cq.door.stair then
		return nil
	end

	if GR.HL2 and GR.HL2(m) then return nil end
	if mode == 1 and not allied_to_players(m) then return nil end
	if math.random() > cvFlashChance:GetFloat() then return nil end
	local target = cq.door.center + cq.inward * CQB.FLASH_DEPTH
	local toYaw = flat_yaw(target - m:GetPos())

	local name, yaw, hand, u = door_flash(m, toYaw)
	if not name then
		name = m.tifHomeHost and TIF.GTG.Clip("mwg_throw_stand", m.tifHomeHost) and "mwg_throw_stand" or nil
		yaw, hand = toYaw, Vector(16, 0, 58)
	end

	m:SetAngles(Angle(0, yaw, 0))
	local d = name and TIF.Action.Play(m, name, { clear = true }) or 0
	local c = name and TIF.GTG.Clip(name, m.tifHomeHost)
	local rel = (u or (c and GR.ReleaseU and GR.ReleaseU(c)) or 0.5) * d
	local wait = { untilT = now + rel + CQB.FLASH_WAIT_MAX }
	cq.flashWait = wait
	local force = { pos = target, door = Vector(cq.door.center), inward = Vector(cq.inward) }
	timer.Simple(rel, function()
		if not IsValid(m) or m.tifDead then
			wait.lost = true
			return
		end
		local a = Angle(0, yaw, 0)
		local src = m:GetPos() + a:Forward() * hand.x - a:Right() * hand.y + Vector(0, 0, hand.z)
		wait.g = GR.Throw(m, target, src, "flash", { force = force }) or false
	end)
	TIF.Say(m, "grenade_out", 0.9)
	log(sq, "flashbang in (", m:EntIndex(), ")")
	return true
end

local function flash_waiting(cq, now)
	local w = cq.flashWait
	if not w then return false end
	if w.lost or w.g == false or now >= w.untilT then
		cq.flashWait = nil
		return false
	end

	if w.g ~= nil and not w.boom and (not IsValid(w.g) or w.g.tifDone) then
		w.boom = now
	end
	if w.boom and now >= w.boom + CQB.AFTER_BANG then
		cq.flashWait = nil
		return false
	end

	return true
end

local function flash_ok(m)
	local mode = cvFlash:GetInt()
	local GR = TIF.GrenadeMW
	if mode == 0 or not (GR and GR.Throw) or not IsValid(m) then return false end
	if GR.HL2 and GR.HL2(m) then return false end
	return mode == 2 or allied_to_players(m)
end

function pick_method(cq, d)
	if not cvVariety:GetBool() then return "open" end

	if locked(d) then
		return (CQB.METHOD_WEIGHTS.hammer or 0) > 0 and math.random() < 0.4 and "hammer" or "kick"
	end
	local w, total = {}, 0
	for k, v in pairs(CQB.METHOD_WEIGHTS) do
		if v > 0 and (k ~= "grenade" or flash_ok(cq.team[1])) then
			w[#w + 1] = { k, v } total = total + v
		end
	end

	table.sort(w, function(a, b) return a[1] < b[1] end)
	local r = math.random() * total
	for _, e in ipairs(w) do
		r = r - e[2]
		if r <= 0 then return e[1] end
	end

	return "open"
end

local function grenade_breach(sq, cq, m, rel, now)
	local GR = TIF.GrenadeMW
	cq.flashed = true
	local wait = { untilT = now + rel + CQB.FLASH_WAIT_MAX }
	cq.flashWait = wait
	local door, inward = Vector(cq.door.center), Vector(cq.inward)
	local target = door + inward * CQB.FLASH_DEPTH
	local force = { pos = target, door = Vector(door), inward = Vector(inward) }
	timer.Simple(rel, function()
		if not (IsValid(m) and GR and GR.Throw) or m.tifDead then
			wait.lost = true
			return
		end
		wait.g = GR.Throw(m, target, door + inward * 14 + Vector(0, 0, 20), "flash", { force = force }) or false
	end)
	log(sq, "grenade breach (", m:EntIndex(), ")")
end

local function anyone_sees_enemy(list, now)
	for _, m in ipairs(list) do
		local c = m.tifPrimaryC
		if c and c.visible then return true end
	end

	return false
end

local function tick(sq, cq, now)

	local team = {}
	for _, m in ipairs(cq.team) do if IsValid(m) and not m.tifDead then team[#team + 1] = m end end
	cq.team = team
	if #team == 0 then return release(sq, cq, "entry team lost") end

	if now - cq.started > CQB.TIMEOUT and not (cq.hold and not cq.go) then
		return release(sq, cq, "timed out")
	end
	local d = cq.door
	local doorAim = d.center + Vector(0, 0, 50)
	local seen = anyone_sees_enemy(team, now)

	if cq.phase == "stack" then
		local ready = 0
		for i, m in ipairs(team) do
			local slot = cq.slots[i]
			if slot then

				local bp = cq.breachPlan and cq.breachPlan[i]

				local spot = (bp and bp.m == m and (bp.stand or bp.from)) or slot.pos
				local far = m:GetPos():DistToSqr(spot) > TIF.Move.SPRINT_DIST * TIF.Move.SPRINT_DIST

				m.tifCQB = { goal = spot, face = doorAim, speed = far and "sprint" or "tactical", crouch = false,
					label = "stack " .. i, wait = (bp and bp.m == m and not cq.opening) and bp.wait or nil,
					lowReady = i ~= 1 and m:GetPos():DistToSqr(spot) < 60 * 60 }

				local tol = (bp and bp.m == m) and CQB.BREACH_READY or 45
				local d2 = m:GetPos():DistToSqr(spot)
				if d2 < tol * tol then
					ready = ready + 1
				end

				local best = cq.stackBest and cq.stackBest[m]
				local dist = math.sqrt(d2)
				if cq.stackBest and (not best or dist < best - 16) then
					cq.stackBest[m], cq.progressAt = dist, now
				end

				local sledge = cq.breachPlan and cq.breachPlan.method == "hammer" and bp and bp.m == m and i == 1 or false
				if m:GetNW2Bool("tif_sledge", false) ~= sledge then
					m:SetNW2Bool("tif_sledge", sledge)
				end
			else

				m.tifCQB = { goal = TIF.Move.Snap(d.center - cq.inward * (90 + 40 * i)) or m:GetPos(), face = doorAim,
					speed = "tactical", crouch = false, label = "stack (back) " .. i, lowReady = true }
				ready = ready + 1
			end
		end
		local waited = now - cq.t0
		cq.stackReady = ready

		if cq.hold and cq.firstDoor and not cq.go then return end

		local enough = ready >= #team
		if enough then
			cq.fullAt = cq.fullAt or now
		else
			cq.fullAt = nil
		end
		local settled = enough and now - cq.fullAt >= CQB.STACK_SETTLE
		if cq.go and cq.firstDoor then
			settled = ready > 0
		end
		local stalled = now - (cq.progressAt or cq.t0) > CQB.STACK_TIMEOUT or waited > CQB.STACK_MAX

		if cq.committed or settled or (stalled and ready > 0) then
			cq.committed = true
			if not settled and not cq.stalledLogged and not cq.opening then
				cq.stalledLogged = true
				local far = {}
				for i, m in ipairs(team) do
					local slot = cq.slots[i]
					local bp = cq.breachPlan and cq.breachPlan[i]
					local spot = slot and ((bp and bp.m == m and (bp.stand or bp.from)) or slot.pos)
					if spot and m:GetPos():DistToSqr(spot) > 45 * 45 then
						far[#far + 1] = string.format("%d (%.0f u off, %s)", i, m:GetPos():Distance(spot), m.tifAct and m.tifAct.name or "no clip")
					end
				end
				log(sq, string.format("going without the full stack after %.0f s (%d/%d): ", waited, ready, #team), table.concat(far, ", "))
			end
			if BLD.Closed(d) then
				if not cq.opening then
					cq.opening = now
					local bp = cq.breachPlan
					local method = bp and bp.method or (cq.firstDoor and cq.method or "open")
					cq.doorMethod = method
					if bp and bp[1] and bp[1].m == team[1] then

						local b1 = bp[1]
						team[1].tifCQBQueue = { go_item(cq, b1, team[1]) }

						cq.wentIn = true
						cq.doorAt = now + b1.goDur * b1.doorU
						cq.doorDue, cq.doorBy = cq.doorAt, team[1]
						local rel = method == "grenade" and b1.goDur * (b1.relU or 0.3) or nil
						if rel then
							grenade_breach(sq, cq, team[1], rel, now)
						end
						if bp[2] and bp[2].m == team[2] then
							team[2].tifCQBQueue = { go_item(cq, bp[2], team[2]) }

							team[2].tifCQBDelay = rel and (now + math.max(0, rel + 1.3 - bp[2].goDur * (bp[2].moveU or 0)))
								or math.max(now, cq.doorAt + 0.25 - bp[2].goDur * (bp[2].moveU or 0))
						end
					else
						open_door(d, team[1], method, cq.inward)
					end
					log(sq, "opening door ", d.id, " (", method, bp and ", breach clips" or "", ")")
				elseif cq.doorAt and now >= cq.doorAt then
					cq.doorAt = nil
					open_door(d, cq.doorBy, cq.doorMethod or "open", cq.inward)
				elseif now - math.max(cq.opening, cq.doorDue or 0) > 2 and BLD.Closed(d) then
					return release(sq, cq, locked(d) and "door locked" or "door won't open")
				end
				return
			end

			if cq.firstDoor and cq.onEntry and not cq.entryPrep then
				local ok, delay = pcall(cq.onEntry, sq, cq)
				if not ok then
					TIF.Error("CQB onEntry: ", tostring(delay))
				end
				cq.entryPrep = now + math.Clamp((ok and tonumber(delay)) or 0, 0, 6)
			end

			if not cq.entryPrep and not cq.flashed then
				cq.flashed = true
				if not cq.wentIn then
					flash_in(sq, cq, team, now)
				end
			end
			if cq.entryPrep and now < cq.entryPrep then return end

			if flash_waiting(cq, now) then return end
			cq.phase, cq.t0, cq.nextRelease = "entry", now, now

			local bp = cq.breachPlan
			if bp and bp.method == "nodoor" and not cq.nodoorGo then
				cq.nodoorGo = true
				for i = 1, 2 do
					local b = bp[i]
					if b and b.m == team[i] then
						team[i].tifCQBQueue = { go_item(cq, b, team[i]) }
						cq.released = i
					end
				end
				cq.nextRelease = now + CQB.ENTRY_GAP
			end
			TIF.Say(team[1], "moving", 0.9)
			log(sq, "entry at door ", d.id, " (", ready, "/", #team, " stacked)")
		end
		return
	end

	if cq.phase == "entry" then

		local gate = true
		if cq.released == 1 and not d.stair and IsValid(team[1]) then
			local through = (team[1]:GetPos() - d.center):Dot(cq.inward) > -12
			gate = through or now - cq.t0 > 1.2
		end
		if gate and now >= cq.nextRelease and cq.released < #team then
			cq.released = cq.released + 1
			cq.nextRelease = now + CQB.ENTRY_GAP
		end
		for i, m in ipairs(team) do
			if i <= cq.released then

				local slot = cq.slots[i]
				local s = slot and slot.side or 1
				local idx
				if d.stair then idx = i
				elseif i == 1 then
					idx = s == 1 and 2 or 1
				elseif i == 2 then
					idx = s == 1 and 2 or 1
					if cq.points[idx] == team[1].tifCQB.goal then
						idx = idx == 1 and 2 or 1
					end
				else
					idx = i
				end
				local p = cq.points[idx] or cq.points[1]

				m.tifCQB = { goal = p, face = corner_look(d, p), speed = "tactical", label = "entry " .. i }
			end
		end
		if cq.released >= #team then
			cq.phase, cq.t0 = "hold", now
		end
		return
	end

	if cq.phase == "hold" then
		local there = 0
		for _, m in ipairs(team) do
			local t = m.tifCQB
			if t and m:GetPos():DistToSqr(t.goal) < 60 * 60 then
				there = there + 1
			end
			if t then
				t.speed, t.label = "tactical", "hold sector"
				if m:GetPos():DistToSqr(t.goal) < 60 * 60 then
					t.face = (cq.room and cq.room.center or (d.center + cq.inward * 300)) + Vector(0, 0, 50)
				end
			end
		end

		if not cq.allInAt then
			local inside = 0
			for _, m in ipairs(team) do
				if d.stair or (m:GetPos() - d.center):Dot(cq.inward) > 16 then
					inside = inside + 1
				end
			end
			if inside >= #team or now - cq.t0 >= CQB.HOLD_ENTER_MAX then
				cq.allInAt = now
			end
		end
		if seen then
			cq.quietSince = nil
			return
		end
		if not cq.allInAt then return end
		if there < #team and now - cq.allInAt < CQB.HOLD_WAIT then return end
		cq.quietSince = cq.quietSince or now
		if now - cq.quietSince < CQB.HOLD_MIN then return end

		local room = cq.room
		if room then
			cq.cleared[room.id] = true
		end
		TIF.Say(team[math.random(#team)], "clear", 0.9)
		log(sq, "room ", room and room.id or "?", " clear", d.stair and " (via stairs)" or "")
		hook.Run("TIF_CQBRoomClear", sq, room, cq)
		cq.firstDoor = false
		if cq.single then return release(sq, cq, "room clear") end
		if table.Count(cq.cleared) >= CQB.MAX_ROOMS then
			return release(sq, cq, "room limit")
		end
		local nd = room and next_door(cq, room)

		if not nd and room then
			local seenR, queue = { [room.id] = true }, { room }
			while #queue > 0 and not nd do
				local r = table.remove(queue, 1)
				for _, dd in ipairs(BLD.DoorsOf(r)) do
					local o = BLD.OtherSide(dd, r)
					if o and not seenR[o.id] then
						if not cq.cleared[o.id] then
							nd = dd room = r
							break
						end
						seenR[o.id] = true
						queue[#queue + 1] = o
					end
				end
			end
		end
		if not nd then return release(sq, cq, "building clear") end
		setup_door(cq, nd, room)
		log(sq, "next door ", nd.id, " (", #cq.slots, " slots)")
	end
end

timer.Create("tif_cqb_tick", 0.25, 0, function()
	if TIF.AIDisabled() then return end
	local now = CurTime()
	for _, sq in pairs(SQ.List) do
		if sq.cqb then
			local ok, err = pcall(tick, sq, sq.cqb, now)
			if not ok then
				TIF.Error("CQB error: ", tostring(err))
				pcall(release, sq, sq.cqb, "error")
			end
		end
	end
end)

function CQB.Stop(sq, reason)
	if sq and sq.cqb then
		release(sq, sq.cqb, reason or "stopped")
	end
end

function CQB.Go(sq, opts)
	local cq = sq and sq.cqb
	if not (cq and cq.hold and not cq.go) then return false end
	if opts then
		if opts.method then
			cq.method, cq.methodSet = opts.method, true

			local d = cq.door
			if d and not d.stair and BLD.Closed(d) and not cq.opening then
				cq.breachPlan = breach_plan(cq, cq.team, cq.method)
				if not cq.breachPlan and (cq.method == "grenade" or cq.method == "hammer") then
					cq.breachPlan = breach_plan(cq, cq.team, cq.method == "hammer" and "kick" or "open")
				end
			end
		end
		if opts.onEntry ~= nil then
			cq.onEntry = opts.onEntry or nil
		end
	end

	cq.go = true
	cq.started = CurTime()
	return true
end

util.AddNetworkString("tif_debug_cqb")
CQB.ShowDoors = CQB.ShowDoors or {}

timer.Create("tif_debug_cqb_send", 0.5, 0, function()
	local cv = GetConVar("tif_debug")
	if not cv or not cv:GetBool() then return end
	local viewers = {}
	for _, ply in player.Iterator() do if TIF.CanUseDev(ply) then viewers[#viewers + 1] = ply end end
	if #viewers == 0 then return end
	local now = CurTime()

	local doors, seenDoor = {}, {}
	local function addDoor(d) if d and not seenDoor[d] then seenDoor[d] = true doors[#doors + 1] = d end end
	if CQB.ShowDoors.untilT and now < CQB.ShowDoors.untilT then for _, d in ipairs(CQB.ShowDoors.list) do addDoor(d) end end
	local active = {}
	for _, sq in pairs(SQ.List) do if sq.cqb then active[#active + 1] = sq.cqb addDoor(sq.cqb.door) end end
	net.Start("tif_debug_cqb")
	net.WriteUInt(math.min(#doors, 127), 7)
	for i = 1, math.min(#doors, 127) do
		local d = doors[i]
		net.WriteVector(d.center)
		net.WriteVector(d.normal)
		net.WriteFloat(d.width)
		net.WriteBool(d.exterior)
		net.WriteBool(IsValid(d.ent))
	end

	net.WriteUInt(math.min(#active, 7), 3)
	for i = 1, math.min(#active, 7) do
		local cq = active[i]
		net.WriteString(cq.phase)
		net.WriteUInt(#cq.slots, 4)
		for _, s in ipairs(cq.slots) do
			net.WriteVector(s.pos)
		end
		net.WriteUInt(#cq.points, 4)
		for _, p in ipairs(cq.points) do
			net.WriteVector(p)
		end
		local areas = cq.room and cq.room.areas or {}
		local n = math.min(#areas, 60)
		net.WriteUInt(n, 7)
		for j = 1, n do
			local a = areas[j]
			for k = 0, 3 do
				net.WriteVector(a:GetCorner(k))
			end
		end
		net.WriteVector(cq.target)
	end

	net.Send(viewers)
end)
