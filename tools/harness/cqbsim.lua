-- Offline (0.38.24): the whole sv_clear.lua driven through a clear of a closed single door: stack -> door -> entry ->
-- hold, every method. Catches runtime errors (an error in the tick releases the team: "they idle then lose interest").
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z)
	if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
V.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Distance(o) return (self - o):Length() end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:Add(o) self.x, self.y, self.z = self.x + o.x, self.y + o.y, self.z + o.z end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Clamp = function(v, a, b) return math.min(b, math.max(a, v)) end
math.Rand = function(a, b) return (a + b) / 2 end
math.AngleDifference = function(a, b) return (a - b + 180) % 360 - 180 end
function IsValid(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
function isstring(x) return type(x) == "string" end
function istable(x) return type(x) == "table" end
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
FCVAR_ARCHIVE, MASK_NPCSOLID_BRUSHONLY, MASK_NPCSOLID, COLLISION_GROUP_NPC, COLLISION_GROUP_NONE, COLLISION_GROUP_NPC_SCRIPTED = 1, 1, 1, 9, 0, 19
local cv = { tif_cqb_flash = 1, tif_cqb_flash_chance = 0, tif_cqb_variety = 1 }
function CreateConVar(n, d) cv[n] = cv[n] or tonumber(d) return { GetInt = function() return cv[n] end, GetFloat = function() return cv[n] end, GetBool = function() return cv[n] ~= 0 end } end
function GetConVar() return nil end
local timers = {}
timer = { Create = function(n, _, _, fn) timers[n] = fn end, Simple = function() end }
hook = { Run = function() end, Add = function() end }
-- the world: a wall at x -8..8 with a 48-wide opening (y -24..24) up to 110 high, the floor below z 0
local function in_wall(p) return p.x > -8 and p.x < 8 and (math.abs(p.y) > 24 or p.z > 110) end
local function seg_hits(a, b)
	for k = 0, 40 do
		local u = k / 40
		local p = Vector(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u)
		if in_wall(p) then return u end
	end
	return nil
end
util = { AddNetworkString = function() end,
	TraceHull = function(t)
		local function boxhit(p) for _, dx in ipairs({ -10, 10 }) do for _, dy in ipairs({ -10, 10 }) do
			if in_wall(Vector(p.x + dx, p.y + dy, p.z + 30)) then return true end end end return false end
		if boxhit(t.start) then return { Fraction = 0, StartSolid = true } end
		-- (a sweep: hit where the box first meets the wall)
		if t.start.x ~= t.endpos.x or t.start.y ~= t.endpos.y then
			for k = 1, 40 do
				local u = k / 40
				local q = Vector(t.start.x + (t.endpos.x - t.start.x) * u, t.start.y + (t.endpos.y - t.start.y) * u, t.start.z)
				if boxhit(q) then return { Hit = true, Fraction = u, StartSolid = false, HitPos = q } end
			end
		end
		return { Fraction = 1, StartSolid = false }
	end,
	TraceLine = function(t)
		local u = seg_hits(t.start, t.endpos)
		if u then return { Hit = true, HitPos = t.endpos, Fraction = u } end
		return { Hit = false, HitPos = t.endpos, Fraction = 1 }
	end }
net = {}
player = { Iterator = function() return ipairs({}) end }
local spawnedProps, portals = {}, {}
ents = ents or {}
ents.FindByClass = function(c) return c == "func_areaportal" and portals or {} end
ents.Create = function(c)
	local p = { cls = c, bg = {} }
	function p:SetModel(m) self.model = m end
	function p:SetPos(v) self.pos = v end
	function p:SetAngles(a) self.ang = a end
	function p:SetSkin() end
	function p:SetBodygroup() end
	function p:Spawn() end
	function p:SetCollisionGroup(g) self.group = g end
	function p:GetPhysicsObject() return { Wake = function() end, SetVelocity = function(_, v) p.vel = v end, AddAngleVelocity = function() end } end
	spawnedProps[#spawnedProps + 1] = p
	return p
end
function VectorRand() return Vector(0, 0, 0) end
function SafeRemoveEntityDelayed() end
COLLISION_GROUP_DEBRIS = 1
local errors = {}
local now = 0
function CurTime() return now end
local doorOpen = false
local door = { center = Vector(0, 0, 0), normal = Vector(1, 0, 0), width = 48, stair = false, id = 1,
	ent = { GetClass = function() return "prop_door_rotating" end, Fire = function() end, EmitSound = function() end,
	GetName = function() return "door1" end, SetCollisionGroup = function(e, g) e.group = g end, GetModel = function() return "models/props_c17/door01_left.mdl" end,
	GetPos = function() return Vector(0, 24, 0) end, GetAngles = function() return Angle() end, GetSkin = function() return 0 end,
	GetNumBodyGroups = function() return 1 end, GetBodygroup = function() return 0 end, SetNoDraw = function(e, v) e.hidden = v end,
	SetNotSolid = function(e, v) e.notSolid = v end,
		GetInternalVariable = function() return false end, WorldSpaceCenter = function() return Vector() end } }
-- clips: the real table
TIFG = { Clips = {} }
TIFG.RegisterClips = function(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips[next(TIFG.Clips)]

TIF = { AWARE = {}, Error = function(...) errors[#errors + 1] = table.concat({ ... }) end, Log = function() end,
	AIDisabled = function() return false end, Say = function() end,
	Squad = { List = {}, Log = function() end, Publish = function() end },
	Move = { SPRINT_DIST = 600, Snap = function(p) return p end },
	GTG = { Clip = function(n) return clips[n] end },
	-- (the real curve: an x, y, yaw triple every 3 frames)
	Action = { RootAt = function(c, u)
		local cv = c.curve
		if not cv or #cv == 0 then return 0, 0, 0 end
		local n = #cv / 3
		local f = u * math.max(1, (c.frames or n * 3) - 1) / 3
		local i = math.min(n - 1, math.floor(f))
		local j = math.min(n - 1, i + 1)
		local k = f - i
		local function ax(a) return cv[i * 3 + a] + (cv[j * 3 + a] - cv[i * 3 + a]) * k end
		return ax(1), ax(2), ax(3)
	end },
	Relation = function() return 1 end, REL_ALLY = 1 }
TIF.Building = {
	Closed = function(d) return d == door and not doorOpen end,
	Open = function() doorOpen = true end,
	OtherSide = function(d, from) return { id = 2, center = Vector(300, 0, 0) }, 1 end,
	StackSlots = function(d, inward, n)
		local out = {}
		for k = 1, n do local s = (k % 2 == 1) and 1 or -1 out[k] = { pos = Vector(-30, s * (48 + 34 * math.floor((k - 1) / 2)), 0), side = s } end
		return out
	end,
	EntryPoints = function() return { Vector(150, 100, 0), Vector(150, -100, 0), Vector(250, 0, 0), Vector(200, 50, 0) } end,
	DoorsOf = function() return {} end, RoomOf = function() return nil end, RoomAt = function() return { id = 2 } end,
	Scan = function() return { door } end,
}
door.exterior = true
TIF.Squad.Members = function(sq) return sq.members end
assert(loadfile(ROOT .. "tif/building/sv_clear.lua"))()
local CQB = TIF.CQB

local function soldier(pos)
	local m = { pos = Vector(pos), ang = Angle(), group = COLLISION_GROUP_NPC, tifHomeHost = "mw_male", tifArchId = "assault" }
	function m:GetPos() return Vector(self.pos) end
	function m:SetPos(p) self.pos = Vector(p) end
	function m:GetAngles() return self.ang end
	function m:SetAngles(a) self.ang = a end
	function m:GetCollisionGroup() return self.group end
	function m:SetCollisionGroup(g) self.group = g end
	function m:GetNW2Bool() return false end
	function m:SetNW2Bool() end
	function m:EntIndex() return 1 end
	function m:IsPlayer() return false end
	return m
end

for _, method in ipairs({ "open", "kick", "hammer", "grenade", false }) do
	doorOpen = false
	errors = {}
	local team = { soldier(Vector(-200, 50, 0)), soldier(Vector(-200, -50, 0)), soldier(Vector(-260, 50, 0)), soldier(Vector(-260, -50, 0)) }
	local sq = { id = 1, members = team }
	TIF.Squad.List = { sq }
	now = 0
	local ok = CQB.Start(sq, Vector(300, 0, 0), true, method and { method = method } or nil)
	check(ok and sq.cqb, tostring(method) .. ": started")
	local cq = sq.cqb
	-- everyone walks onto their stack spot (whatever the plan asks for); go clips run through the brain's steps
	local phases = {}
	local went, skipped = 0, 0
	for step = 1, 200 do
		now = now + 0.25
		for _, m in ipairs(team) do
			local t = m.tifCQB
			if t and t.goal then m.pos = Vector(t.goal) end
		end
		timers.tif_cqb_tick()
		for _, m in ipairs(team) do
			local q = m.tifCQBQueue
			if q and #q > 0 and now >= (m.tifCQBDelay or 0) then
				local item = table.remove(q, 1)
				local yaw = item.yawFn and item.yawFn(m) or item.yaw
				if item.check and not item.check(m, yaw or 0) then skipped = skipped + 1 else went = went + 1 end
			end
		end
		if not sq.cqb then break end
		phases[sq.cqb.phase] = phases[sq.cqb.phase] or now
	end
	check(#errors == 0, tostring(method) .. ": no errors (" .. (errors[1] or "") .. ")")
	check(doorOpen, tostring(method) .. ": the door opened")
	check(phases.entry ~= nil, tostring(method) .. ": went in (entry at " .. tostring(phases.entry) .. ")")
	check(phases.hold ~= nil, tostring(method) .. ": held the room")
	if method then check(went >= 1 and skipped == 0, tostring(method) .. ": the breach clips play (" .. went .. " played, " .. skipped .. " skipped)") end
	for _, m in ipairs(team) do
		if m.group ~= COLLISION_GROUP_NPC and not sq.cqb then check(false, tostring(method) .. ": collision group restored") break end
	end
	if sq.cqb then TIF.CQB.Stop(sq, "test end") end
end
-- 0.38.25: the second man's paired clip starts so he sets off just after the door gives (not after it: double wait)
do
	doorOpen = false
	local team = { soldier(Vector(-200, 50, 0)), soldier(Vector(-200, -50, 0)) }
	local sq = { id = 2, members = team }
	TIF.Squad.List = { sq }
	now = 0
	CQB.Start(sq, Vector(300, 0, 0), true, { method = "kick" })
	local cq = sq.cqb
	local delay, doorAt
	for step = 1, 80 do
		now = now + 0.25
		for _, m in ipairs(team) do local t = m.tifCQB if t and t.goal then m.pos = Vector(t.goal) end end
		timers.tif_cqb_tick()
		if cq.doorAt and not doorAt then doorAt = cq.doorAt delay = team[2].tifCQBDelay end
		if doorAt then break end
	end
	check(doorAt and delay and delay < doorAt + 0.25 - 1, "kick: the 2nd man's clip starts well before the door gives (" .. tostring(delay) .. " vs door " .. tostring(doorAt) .. ")")
	TIF.CQB.Stop(sq, "t")
end
-- 0.38.25: a team that hasn't got through the doorway isn't called clear after 5 s
do
	doorOpen = false
	local team = { soldier(Vector(-200, 50, 0)), soldier(Vector(-200, -50, 0)) }
	local sq = { id = 3, members = team }
	TIF.Squad.List = { sq }
	now = 0
	CQB.Start(sq, Vector(300, 0, 0), true, { method = "open", single = true })
	local cq = sq.cqb
	local holdAt, endAt
	for step = 1, 200 do
		now = now + 0.25
		-- they reach the stack, but never step inside
		for _, m in ipairs(team) do local t = m.tifCQB if t and t.goal and t.goal.x < 0 then m.pos = Vector(t.goal) end end
		timers.tif_cqb_tick()
		if sq.cqb and sq.cqb.phase == "hold" and not holdAt then holdAt = now end
		if not sq.cqb then endAt = now break end
	end
	check(holdAt and endAt and endAt - holdAt >= CQB.HOLD_ENTER_MAX - 0.5, "stuck outside: the hold waits " .. CQB.HOLD_ENTER_MAX .. " s for them to get in (" .. tostring(endAt and holdAt and endAt - holdAt) .. ")")
end
-- 2026-11-20 (log_sv squad 23 "1/3 stacked"): men still walking to the stack are waited for; a stuck one isn't
for _, stuck in ipairs({ false, true }) do
	doorOpen = false
	local team = { soldier(Vector(-60, 50, 0)), soldier(Vector(-500, 50, 0)), soldier(Vector(-520, -50, 0)) }
	local sq = { id = 4, members = team }
	TIF.Squad.List = { sq }
	now = 0
	CQB.Start(sq, Vector(300, 0, 0), true, { method = "open", single = true })
	local cq = sq.cqb
	local readyAtEntry
	for step = 1, 400 do
		now = now + 0.25
		for i, m in ipairs(team) do
			local t = m.tifCQB
			if t and t.goal then
				-- the point man is there at once; the other two walk 30 u/s (the far one not at all when stuck)
				local d = t.goal - m.pos
				local L = math.sqrt(d.x ^ 2 + d.y ^ 2)
				local sp = (i == 1 or cq.phase ~= "stack") and 1e9 or ((stuck and i == 3) and 0 or 7.5)
				if L <= sp then m.pos = Vector(t.goal) elseif sp > 0 then m.pos = m.pos + d * (sp / L) end
			end
		end
		timers.tif_cqb_tick()
		if sq.cqb and sq.cqb.phase ~= "stack" and not readyAtEntry then readyAtEntry = { sq.cqb.stackReady, now } end
		if readyAtEntry then break end
	end
	if not stuck then
		check(readyAtEntry and readyAtEntry[1] == 3 and readyAtEntry[2] > CQB.STACK_TIMEOUT, "slow walkers: waited for, in with all 3 (" .. tostring(readyAtEntry and readyAtEntry[1]) .. " at " .. tostring(readyAtEntry and readyAtEntry[2]) .. ")")
	else
		check(readyAtEntry and readyAtEntry[1] == 2 and readyAtEntry[2] < CQB.STACK_MAX, "one man stuck: in without him after the stall timeout (" .. tostring(readyAtEntry and readyAtEntry[1]) .. " at " .. tostring(readyAtEntry and readyAtEntry[2]) .. ")")
	end
	if sq.cqb then TIF.CQB.Stop(sq, "t") end
end
-- 2026-11-21 (log: "opening door 2 (kick)" and nothing after): the breach clips carry the two breachers off their
-- spots: the door still swings and they go in
for _, method in ipairs({ "kick", "open", "grenade" }) do
	doorOpen = false
	errors = {}
	local team = { soldier(Vector(-200, 50, 0)), soldier(Vector(-200, -50, 0)), soldier(Vector(-260, 50, 0)), soldier(Vector(-260, -50, 0)) }
	local sq = { id = 5, members = team }
	TIF.Squad.List = { sq }
	now = 0
	CQB.Start(sq, Vector(300, 0, 0), true, { method = method, single = true })
	local cq = sq.cqb
	local entryAt, openAt
	for step = 1, 200 do
		now = now + 0.25
		if cq.opening and not openAt then openAt = now end
		for i, m in ipairs(team) do
			local t = m.tifCQB
			-- (once the breach is under way the two breachers are wherever their clips took them: off their spots)
			if cq.opening and i <= 2 then m.pos = Vector(20, i == 1 and 30 or -30, 0)
			elseif t and t.goal then m.pos = Vector(t.goal) end
		end
		timers.tif_cqb_tick()
		for _, m in ipairs(team) do if m.tifCQBQueue and #m.tifCQBQueue > 0 then table.remove(m.tifCQBQueue, 1) end end
		if not sq.cqb then break end
		if sq.cqb.phase ~= "stack" and not entryAt then entryAt = now end
	end
	check(doorOpen, method .. ": breachers off their spots mid-breach: the door still opens")
	check(entryAt and openAt and entryAt - openAt < 8, method .. ": ... and go in straight after, not a stall timeout later (" .. tostring(entryAt and openAt and entryAt - openAt) .. " s)")
	if sq.cqb then TIF.CQB.Stop(sq, "t") end
end
-- a breacher 30 in off his spot: his go clip is blended onto the planned path, aimed as planned, checked from there
do
	doorOpen = false
	local team = { soldier(Vector(-200, 50, 0)), soldier(Vector(-200, -50, 0)) }
	local sq = { id = 6, members = team }
	TIF.Squad.List = { sq }
	now = 0
	CQB.Start(sq, Vector(300, 0, 0), true, { method = "kick", single = true })
	local cq = sq.cqb
	local item
	for step = 1, 80 do
		now = now + 0.25
		for i, m in ipairs(team) do
			local t = m.tifCQB
			if t and t.goal then m.pos = Vector(t.goal) + (i == 1 and Vector(0, 30, 0) or Vector()) end
		end
		timers.tif_cqb_tick()
		local q = team[1].tifCQBQueue
		if q and q[1] then item = q[1] break end
	end
	local b = cq.breachPlan and cq.breachPlan[1]
	check(item and item.opts.to and item.opts.warpU and item.opts.warpU > 0.2, "30 in off: the go clip is warped onto its path (" .. tostring(item and item.opts.warpU) .. ")")
	check(item and b and item.yawFn(team[1]) == b.yaw, "aimed as planned from his spot")
	check(item and item.check(team[1], b.yaw), "path checked from the planned spot: clear")
	if sq.cqb then TIF.CQB.Stop(sq, "t") end
end
-- 2026-11-21: the last stretch onto a spot is slid there (no stop-start shuffle); not through a wall
do
	TIF.Move = TIF.Move or {}
	local oldStop = TIF.Move.Stop
	TIF.Move.Stop = function(m) m.stopped = true end
	local m = soldier(Vector(60, 40, 0))
	m.tifCQB = { goal = Vector(30, 10, 0) }
	local goal = Vector(30, 10, 0)
	local t = 0
	local ok = CQB.Glide(m, goal, t)
	-- (the brain re-asks every 0.2 s; the slide steps every tick)
	for k = 1, 60 do
		t = t + 0.015
		if k % 13 == 0 then CQB.Glide(m, goal, t) end
		CQB.GlideStep(m, t)
	end
	check(ok and m.stopped and m.pos:DistToSqr(goal) < 1, "glide: 42 in from his spot, slid onto it (" .. string.format("%.1f", math.sqrt(m.pos:DistToSqr(goal))) .. " off)")
	local m2 = soldier(Vector(-40, 40, 0))
	check(not CQB.Glide(m2, Vector(20, 40, 0), 0), "glide: not through the wall (the path takes him round)")
	local m3 = soldier(Vector(200, 0, 0))
	check(not CQB.Glide(m3, Vector(30, 0, 0), 0), "glide: not from far off")
	TIF.Move.Stop = oldStop
end
-- 2026-11-21: a kicked door comes off (a loose prop, the door hidden); with an area portal on it it stays, not colliding
do
	local e = door.ent
	spawnedProps = {}
	e.hidden, e.notSolid, e.group = nil, nil, nil
	CQB.DoorOff(e, Vector(1, 0, 0), true)
	check(#spawnedProps == 1 and spawnedProps[1].group == 1 and e.hidden and e.notSolid, "kicked: off its hinges as a loose prop, the door hidden")
	check(spawnedProps[1] and spawnedProps[1].vel and spawnedProps[1].vel.x > 100, "... knocked into the room")
	e.hidden, e.notSolid, e.group = nil, nil, nil
	spawnedProps = {}
	portals = { { GetInternalVariable = function(_, k) return k == "target" and "door1" or nil end } }
	CQB.DoorOff(e, Vector(1, 0, 0), true)
	check(#spawnedProps == 0 and not e.hidden and e.group == 1, "with an area portal on it: kept, just not colliding")
	portals = {}
	e.group = nil
	CQB.DoorOff(e, Vector(1, 0, 0), false)
	check(#spawnedProps == 0 and e.group == 1, "opened by hand: kept, not colliding")
	e.group, e.hidden, e.notSolid = nil, nil, nil
end
-- 2026-11-21: the kick lands square and centred on the door; men across the door go via its front and slide through
do
	doorOpen = false
	local team = { soldier(Vector(-200, 50, 0)), soldier(Vector(-200, -50, 0)) }
	local sq = { id = 7, members = team }
	TIF.Squad.List = { sq }
	now = 0
	CQB.Start(sq, Vector(300, 0, 0), true, { method = "kick", single = true })
	local cq = sq.cqb
	local b = cq.breachPlan and cq.breachPlan[1]
	check(b and b.stand and b.warpU, "kick: the kicker has a placed spot and the warp to it")
	if b and b.stand then
		local c = clips[b.go]
		local x, y, r = TIF.Action.RootAt(c, b.warpU)
		local rad = math.rad(b.yaw)
		local at = Vector(b.stand.x + x * math.cos(rad) - y * math.sin(rad), b.stand.y + x * math.sin(rad) + y * math.cos(rad), 0)
		local want = door.center - cq.inward * CQB.KICK_BACK
		check(math.abs(at.y - want.y) < 1 and math.abs(at.x - want.x) < 1, string.format("at the kick: centred on the door, %d back (%.1f %.1f)", CQB.KICK_BACK, at.x, at.y))
		check(math.abs(math.AngleDifference(b.yaw + r, math.deg(math.atan2(cq.inward.y, cq.inward.x)))) < 1, "... square to it")
	end
	-- (open the door for the routing check)
	doorOpen = true
	TIF.Move.Stop = TIF.Move.Stop or function() end
	TIF.Move.Snap = TIF.Move.Snap or function(p) return p end
	local closedWas = TIF.Building.Closed
	TIF.Building.Closed = function() return false end
	local far = soldier(Vector(-200, 0, 0))
	local via = CQB.Through(far, cq, Vector(150, 0, 0), 1)
	check(type(via) == "table" and via.x < 0 and math.abs(via.y) < 1, "across the door, far: first to its front (" .. tostring(via and via.x) .. ")")
	local near = soldier(Vector(-45, 5, 0))
	near.tifCQB = { goal = Vector(150, 0, 0) }
	check(CQB.Through(near, cq, Vector(150, 0, 0), 1) == "glide" and near.tifGlide and near.tifGlide.goal.x > 0, "at the doorway: slid through it")
	local same = soldier(Vector(60, 0, 0))
	check(CQB.Through(same, cq, Vector(150, 0, 0), 1) == nil, "same side: his own goal")
	TIF.Building.Closed = closedWas
	if sq.cqb then TIF.CQB.Stop(sq, "t") end
end
-- 2026-11-21 ("door opener tends to have trouble with clearance"): each breacher's go clip, from where the plan
-- starts him, crosses the doorway at its middle (not by the jamb)
for _, method in ipairs({ "open", "grenade", "kick", "nodoor" }) do
	doorOpen = method == "nodoor"
	local team = { soldier(Vector(-200, 50, 0)), soldier(Vector(-200, -50, 0)) }
	local sq = { id = 8, members = team }
	TIF.Squad.List = { sq }
	now = 0
	CQB.Start(sq, Vector(300, 0, 0), true, { method = method, single = true })
	local cq = sq.cqb
	local bp = cq and cq.breachPlan
	local worst, n = 0, 0
	for i = 1, 2 do
		local b = bp and bp[i]
		if b and not b.stand then
			local c = clips[b.go]
			local r = math.rad(b.yaw)
			local prev, P
			for k = 0, 100 do
				local x, y = TIF.Action.RootAt(c, k / 100)
				local q = Vector(b.from.x + x * math.cos(r) - y * math.sin(r), b.from.y + x * math.sin(r) + y * math.cos(r), 0)
				if prev and prev.x < door.center.x and q.x >= door.center.x then P = q break end
				prev = q
			end
			n = n + 1
			if P then worst = math.max(worst, math.abs(P.y - door.center.y)) else worst = 999 end
		end
	end
	if n > 0 then check(worst < 3, method .. ": go clips cross the doorway at its middle (worst " .. string.format("%.1f", worst) .. " off, " .. n .. " clips)") end
	if sq.cqb then TIF.CQB.Stop(sq, "t") end
end
-- regression: 0.38.23's straight-segment hull check on the same clips from the stack spots (dropped them: the bug)
local function old_check(pos, c, yaw)
	local r = math.rad(yaw)
	local cs, sn = math.cos(r), math.sin(r)
	local prev = pos
	for _, u in ipairs({ 0.33, 0.66, 1 }) do
		local x, y = TIF.Action.RootAt(c, u)
		local p = Vector(pos.x + x * cs - y * sn, pos.y + x * sn + y * cs, pos.z)
		for k = 0, 10 do
			local q = Vector(prev.x + (p.x - prev.x) * k / 10, prev.y + (p.y - prev.y) * k / 10, 30)
			for _, dx in ipairs({ -10, 10 }) do for _, dy in ipairs({ -10, 10 }) do
				if in_wall(Vector(q.x + dx, q.y + dy, q.z)) then return false end end end
		end
		prev = p
	end
	return true
end
local oldSkips = 0
for _, n in ipairs({ "mwq_br_l_1st_open", "mwq_br_r_1st_open", "mwq_br_l_1st_kick", "mwq_br_r_1st_kick" }) do
	local c = clips[n]
	for _, side in ipairs({ 1, -1 }) do
		local pos = Vector(-30, side * 48, 0)
		local tgt = Vector(70, 0, 0)
		local yaw = math.deg(math.atan2(tgt.y - pos.y, tgt.x - pos.x)) - math.deg(math.atan2(c.move[2], c.move[1]))
		if not old_check(pos, c, yaw) then oldSkips = oldSkips + 1 end
	end
end
check(oldSkips >= 4, "regression: the 0.38.23 check dropped most opening / kick clips (" .. oldSkips .. " of 8)")
print(string.format("passed %d, failed %d", pass, fail))
