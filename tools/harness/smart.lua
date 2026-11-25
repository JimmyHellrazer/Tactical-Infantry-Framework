-- Offline run of tactics/sv_smart_mw.lua + its sv_passive_mw.lua wiring, with box geometry and real clip data.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local function near(a, b, e) return math.abs(a - b) <= (e or 0.6) end

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	return Vector(a.x * b, a.y * b, a.z * b)
end
V.__tostring = function(a) return string.format("(%.1f %.1f %.1f)", a.x, a.y, a.z) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Distance(o) return (self - o):Length() end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:Angle() return { p = 0, y = math.deg(math.atan2(self.y, self.x)) % 360, r = 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
math.Rand = function(a, b) return (a + b) / 2 end
math.AngleDifference = function(a, b) return (a - b + 180) % 360 - 180 end
local rolls = {}
math.random = function(a, b)
	if a then return a end           -- first entry of any list
	return table.remove(rolls, 1) or 0.1
end
function IsValid(x) return x ~= nil and x ~= false end
MASK_SOLID, COLLISION_GROUP_DEBRIS, COLLISION_GROUP_NONE = 1, 1, 0

-- World: axis-aligned boxes, each owned by an entity (world or a prop).
local function ent(t)
	t.IsNPC = function() return t.npc == true end
	t.IsNextBot = function() return t.npc == true end
	t.IsPlayer = function() return false end
	return t
end
local WORLD = ent({ class = "worldspawn" })
local boxes = {}
local function box(mins, maxs, owner) boxes[#boxes + 1] = { mins = mins, maxs = maxs, ent = owner or WORLD } end
local function slab(a, b, lo, hi)
	local d = b - a
	if math.abs(d) < 1e-9 then
		if a < lo or a > hi then return nil end
		return -math.huge, math.huge
	end
	local t1, t2 = (lo - a) / d, (hi - a) / d
	if t1 > t2 then t1, t2 = t2, t1 end
	return t1, t2
end
util = {}
function util.TraceLine(t)
	local best, bn, be = 2, nil, nil
	for _, bx in ipairs(boxes) do
		local skip = false
		if type(t.filter) == "function" then skip = not t.filter(bx.ent)
		elseif t.filter == bx.ent then skip = true end
		if not skip then
			local tin, tout, axis = -math.huge, math.huge, nil
			local ok = true
			for _, k in ipairs({ "x", "y", "z" }) do
				local a, b = slab(t.start[k], t.endpos[k], bx.mins[k], bx.maxs[k])
				if not a then ok = false break end
				if a > tin then tin, axis = a, k end
				if b < tout then tout = b end
			end
			if ok and tin <= tout and tin >= 0 and tin <= 1 and tin < best then
				best, be = tin, bx.ent
				bn = Vector(0, 0, 0)
				bn[axis] = (t.endpos[axis] - t.start[axis]) > 0 and -1 or 1
			end
		end
	end
	if best > 1 then return { Hit = false, HitPos = t.endpos, Fraction = 1 } end
	return { Hit = true, HitPos = t.start + (t.endpos - t.start) * best, HitNormal = bn, Entity = be, Fraction = best }
end
local props = {}
ents = { FindInSphere = function(c, r)
	local out = {}
	for _, p in ipairs(props) do if p.center:Distance(c) <= r then out[#out + 1] = p end end
	return out
end }

TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local played = {}
local function last() return played[#played] end
TIF = {
	AWARE = { UNAWARE = 0, SUSPICIOUS = 1, ALERTED = 2, ENGAGED = 3, SEARCHING = 4 },
	GTG = { IsVB = function(id) return id == "mw_male" end, Clip = function(name, id) return id == "mw_male" and clips[name] or nil end },
	Move = { Stop = function(npc) end },
	Say = function() end, Perception = { Stimulus = function() end }, Soldiers = {},
}
local lastOpts
TIF.Action = {
	Play = function(npc, name, opts)
		local c = clips[name]
		if not c then return nil end
		played[#played + 1] = name
		lastOpts = opts or {}
		npc.tifAct = { name = name }
		return c.dur / ((opts and opts.rate) or 1)
	end,
	Loop = function(npc, name) played[#played + 1] = name npc.tifAct = { name = name, loop = true } return 1 end,
	Clear = function(npc) npc.tifAct = nil end,
}
for _, f in ipairs({ "tif/tactics/sv_smart_mw.lua", "tif/tactics/sv_passive_mw.lua" }) do
	local fn, err = loadfile(ROOT .. f)
	if not fn then error(err) end
	fn()
end
local SM, P, AW = TIF.SmartMW, TIF.PassiveMW, TIF.AWARE
P.TAKE_CHANCE, P.SMART_CHANCE = 1, 1

local function soldier(pos, yaw)
	local s = ent({ npc = true, tifHomeHost = "mw_male", pos = pos or Vector(0, 0, 0), yaw = yaw or 0, vel = 0, tifAware = AW.UNAWARE, created = 0 })
	function s:GetPos() return self.pos end
	function s:SetPos(p) self.pos = p end
	function s:GetAngles() return Angle(0, self.yaw, 0) end
	function s:SetAngles(a) self.yaw = a.y end
	function s:GetTIFFaction() return "army" end
	function s:GetCreationTime() return self.created end
	s.loco = { GetVelocity = function() return Vector(s.vel, 0, 0) end }
	return s
end
local function reset() boxes = {} props = {} box(Vector(-500, -500, -10), Vector(500, 500, 0)) end

-- A wall ahead: a shoulder lean along it, the right distance off it.
reset()
box(Vector(40, -200, 0), Vector(60, 200, 120))
local a = soldier()
local spots = SM.Find(a, a:GetPos(), 0)
local w
for _, s in ipairs(spots) do if s.kind == "wall" then w = s end end
check(w ~= nil, "wall found")
if w then
	local d = SM.WALL_DIST[w.prefix:sub(-1)]
	check(near(w.pos.x, 40 - d) and near(w.pos.z, 0), "lean spot " .. d .. " off the wall: " .. tostring(w.pos))
	check(near(math.abs(math.AngleDifference(w.yaw, 0)), 90), "standing along the wall: yaw " .. w.yaw)
	-- wall on the left side (l) faces so that the wall's normal points to his right
	local side = w.prefix:sub(-1)
	local right = Vector(math.cos(math.rad(w.yaw - 90)), math.sin(math.rad(w.yaw - 90)), 0)
	local towall = right.x * 1 > 0 and "r" or "l"
	check(side == towall, "lean side matches where the wall is: " .. side .. " vs " .. towall)
end
-- another soldier's box is not a wall
reset()
local other = soldier(Vector(30, 0, 0))
box(Vector(20, -16, 0), Vector(40, 16, 72), other)
local n = 0
for _, s in ipairs(SM.Find(a, a:GetPos(), 0)) do if s.kind == "wall" then n = n + 1 end end
check(n == 0, "no lean on another soldier")

-- A table ahead, 32 high: the 30 set, hand spot at the edge.
reset()
box(Vector(30, -20, 0), Vector(60, 20, 32))
local t
for _, s in ipairs(SM.Find(a, a:GetPos(), 0)) do if s.kind == "table" then t = s end end
check(t ~= nil, "table found")
if t then
	local hand = t.prefix:match("mws_table_(%a)_")
	check(t.prefix:find("_30$") ~= nil, "30 set for a 32 top: " .. t.prefix)
	check(near(t.pos.x, 30 - SM.TABLE[hand].edge), "table spot off the edge: " .. tostring(t.pos))
	check(near(math.AngleDifference(t.yaw, SM.TABLE[hand].turn), 0), "table facing for hand " .. hand .. ": " .. t.yaw)
end
-- too high (a 50 shelf) and a counter with a wall above: nothing
reset()
box(Vector(30, -20, 0), Vector(60, 20, 50))
n = 0
for _, s in ipairs(SM.Find(a, a:GetPos(), 0)) do if s.kind == "table" then n = n + 1 end end
check(n == 0, "no table lean on a 50 high shelf")

-- A chair 60 to the left, backrest at -x: sit facing +x.
reset()
local chair = ent({ center = Vector(0, 60, 20), cg = 0, motion = true })
function chair:GetClass() return "prop_physics" end
function chair:GetModel() return "models/props_c17/chair02a.mdl" end
function chair:WorldSpaceCenter() return self.center end
function chair:GetAngles() return Angle(0, 0, 0) end
function chair:GetCollisionGroup() return self.cg end
function chair:SetCollisionGroup(g) self.cg = g end
local phys = { IsMotionEnabled = function() return chair.motion end, EnableMotion = function(_, m) chair.motion = m end, Wake = function() end }
function chair:GetPhysicsObject() return phys end
props[1] = chair
box(Vector(-10, 50, 0), Vector(10, 70, 18), chair)
box(Vector(-12, 50, 18), Vector(-10, 70, 40), chair)
local seat
for _, s in ipairs(SM.Find(a, a:GetPos(), 90)) do if s.kind == "sit" then seat = s end end
check(seat ~= nil, "chair found")
if seat then
	local k = seat.prefix:match("mws_sit_(%a+)")
	check(near(seat.yaw % 360, 0), "faces away from the backrest: " .. seat.yaw)
	check(near(seat.pos.x, -SM.SEAT_OFF[k]) and near(seat.pos.y, 60) and near(seat.pos.z, 0), "seat spot for " .. k .. ": " .. tostring(seat.pos))
end
local plain = ent({ center = Vector(0, -60, 20) })
function plain:GetClass() return "prop_physics" end
function plain:GetModel() return "models/props_junk/wood_crate001a.mdl" end
props[2] = plain
n = 0
for _, s in ipairs(SM.Find(a, a:GetPos(), 90)) do if s.kind == "sit" then n = n + 1 end end
check(n == 1, "a crate isn't a seat")

-- Spawned by the chair: starts seated, chair frozen and out of the way; startled: stands up toward the threat.
local now = 10
local b = soldier(Vector(0, 0, 0), 90)
b.created = now - 1
check(P.Duty(b, now, true) and b.tifActivity and b.tifActivity.phase == "loop", "spawned by a chair: seated at once")
check(last():find("^mws_sit_%a+_loop$") ~= nil and near(b.pos.y, 60), "seated loop on the chair: " .. tostring(last()) .. " " .. tostring(b.pos))
check(chair.tifSeatTaken == b and chair.motion == false and chair.cg == COLLISION_GROUP_DEBRIS, "chair claimed and frozen")
local c2 = soldier(Vector(0, 10, 0))
n = 0
for _, s in ipairs(SM.Find(c2, c2:GetPos(), 90)) do if s.kind == "sit" then n = n + 1 end end
check(n == 0, "a taken chair isn't offered")
b.tifAware = AW.ALERTED
b.tifPrimaryC = { pos = Vector(300, 60, 0) }
check(P.Busy(b, now + 1) and last():find("^mws_sit_%a+_react$") ~= nil, "startled while seated: stands up: " .. tostring(last()))
check(b.tifActivity == nil and b.tifPassiveBusy and b.tifPassiveBusy.kind == "away", "busy while getting up")
check(chair.tifSeatTaken == nil and chair.motion == true and chair.cg == 0, "chair given back")
-- a sitter that vanished frees its chair on the next search
claimed = SM.Start(c2, seat, now, true)
c2.tifActivity = claimed
c2.tifActivity = nil
SM.Find(a, a:GetPos(), 90)
check(chair.tifSeatTaken == nil and chair.motion == true, "stale claim released")

-- Leaning on a wall at a post: enter (warped onto the spot), loop, calm exit, cooldown.
reset()
box(Vector(40, -200, 0), Vector(60, 200, 120))
local d = soldier()
d.created = -100
now = 100
P.Duty(d, now, true)
now = now + 40
check(P.Duty(d, now, true) and d.tifActivity and d.tifActivity.smart and last():find("^mws_wall_%a_enter$") ~= nil, "a wall lean starts: " .. tostring(last()))
check(lastOpts.root == true and lastOpts.to ~= nil, "enter follows the clip path onto the spot")
now = d.tifActivity.untilT + 0.01
P.Duty(d, now, true)
check(d.tifActivity.phase == "loop" and last():find("_loop$") ~= nil and near(d.pos.x, d.tifActivity.smart.pos.x), "enter -> loop, snapped on the spot")
now = d.tifActivity.loopUntil + 0.01
P.Duty(d, now, true)
check(d.tifActivity.phase == "exit" and last():find("_exit$") ~= nil, "loop -> calm exit")
now = d.tifActivity.untilT + 0.01
check(not P.Duty(d, now, true) and d.tifActivity == nil and d.tifNextActivity > now, "done, cooldown")
-- startled while leaning: the 4-way react toward the threat (behind -> 2)
now = now + 200
P.Duty(d, now, true)
now = now + 40
P.Duty(d, now, true)
now = d.tifActivity.untilT + 0.01
P.Duty(d, now, true)
d.tifAware = AW.SUSPICIOUS
d.tifStim = { pos = d.pos - Vector(math.cos(math.rad(d.yaw)), math.sin(math.rad(d.yaw)), 0) * 300 }
check(P.Busy(d, now) and last():find("_react_2$") ~= nil, "noise behind while leaning: startle to the back: " .. tostring(last()))
-- walking off mid-lean: calm exit
d.tifPassiveBusy, d.tifAware = nil, AW.UNAWARE
now = now + 200
P.Duty(d, now, true)
now = now + 40
P.Duty(d, now, true)
now = d.tifActivity.untilT + 0.01
P.Duty(d, now, true)
check(P.Duty(d, now, false) and last():find("_exit$") ~= nil and d.tifActivity == nil, "ordered off: calm exit first")

-- Sitting back down later: the stand-up clip reversed, slowed, onto the seat.
reset()
props = { chair }
box(Vector(-10, 50, 0), Vector(10, 70, 18), chair)
box(Vector(-12, 50, 18), Vector(-10, 70, 40), chair)
local e = soldier(Vector(0, 20, 0))
e.created = -100
now = 1000
P.Duty(e, now, true)
now = now + 40
check(P.Duty(e, now, true) and last():find("^mws_sit_%a+_react$") ~= nil and lastOpts.reverse == true, "sits down: reversed stand-up: " .. tostring(last()))
check(lastOpts.to and lastOpts.rate < 1, "slides onto the seat, slowed")
now = e.tifActivity.untilT + 0.01
P.Duty(e, now, true)
check(e.tifActivity.phase == "loop" and last():find("_loop$") ~= nil, "then the seated loop")
print(string.format("passed %d, failed %d", pass, fail))
