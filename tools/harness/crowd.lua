-- Offline (0.38.18): TIF.Crowd (npc/sv_crowd.lua) - steering round bodies ahead, overlap ghosting, side points.
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
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function IsValid(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
COLLISION_GROUP_NONE, COLLISION_GROUP_DEBRIS, COLLISION_GROUP_NPC, COLLISION_GROUP_NPC_SCRIPTED = 0, 1, 9, 19
MOVETYPE_NOCLIP, MASK_NPCSOLID, FCVAR_ARCHIVE = 8, 1, 1
local cvOn = "1"
function CreateConVar() return { GetBool = function() return cvOn ~= "0" end } end
local cbs = {}
cvars = { AddChangeCallback = function(n, fn) cbs[n] = fn end }
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[ev .. ":" .. id] = fn end }
function CurTime() return 300 end
local timers = {}
timer = { Create = function(n, _, _, fn) timers[n] = fn end }
local walls = {}   -- x/y boxes { x0, x1, y0, y1 }
util = { TraceHull = function(t)
	local f = 1
	for _, w in ipairs(walls) do
		for k = 1, 20 do
			local u = k / 20
			local x, y = t.start.x + (t.endpos.x - t.start.x) * u, t.start.y + (t.endpos.y - t.start.y) * u
			if x > w[1] and x < w[2] and y > w[3] and y < w[4] then f = math.min(f, (k - 1) / 20) break end
		end
	end
	return { Fraction = f }
end }
player = { GetAll = function() return {} end }
local all = {}
ents = { GetAll = function() return all end }
local function body(pos, vel)
	local e = { pos = pos, vel = vel or Vector(), group = COLLISION_GROUP_NPC }
	function e:GetPos() return Vector(self.pos) end
	function e:GetVelocity() return Vector(self.vel) end
	function e:GetCollisionGroup() return self.group end
	function e:SetCollisionGroup(g) self.group = g end
	e.loco = { GetVelocity = function() return Vector(e.vel) end }
	all[#all + 1] = e
	return e
end
local profN = 0
TIF = { Soldiers = {}, NPCs = {}, Prof = { Begin = function() profN = profN + 1 end, End = function() end } }
assert(loadfile(ROOT .. "tif/npc/sv_crowd.lua"))()
local C = TIF.Crowd
local now = 100
local fwd = Vector(1, 0, 0)

-- someone standing in the lane ahead: eased past on the right (-y), nobody in the way: nothing
local me = body(Vector(0, 0, 0), Vector(100, 0, 0))
local st = body(Vector(50, 0, 0))
TIF.Soldiers = { me, st }
local pace, p = C.Steer(me, fwd, 100, Vector(400, 0, 0), now)
check(p ~= nil and p.y < -10 and p.x > 0, "standing ahead: eased past on his right")
check(profN > 0, "timed under the profiler")
-- already to my right: past on the left
C.Invalidate() me.tifCrowd = nil
st.pos = Vector(50, -12, 0)
pace, p = C.Steer(me, fwd, 100, Vector(400, 0, 0), now)
check(p and p.y > 10, "blocker already to my right: past on the left")
-- right side walled: left
C.Invalidate() me.tifCrowd = nil
st.pos = Vector(50, 0, 0)
walls = { { -10, 60, -60, -14 } }
pace, p = C.Steer(me, fwd, 100, Vector(400, 0, 0), now)
check(p and p.y > 10, "right side walled: past on the left")
walls = {}
-- head-on: both keep their own right (mirror: they pass)
C.Invalidate() me.tifCrowd = nil
st.vel = Vector(-100, 0, 0)
pace, p = C.Steer(me, fwd, 100, Vector(400, 0, 0), now)
st.tifCrowd = nil
local pace2, p2 = C.Steer(st, Vector(-1, 0, 0), 100, Vector(-400, 0, 0), now)
check(p and p2 and p.y < 0 and p2.y > 0, "head-on: each to his own right, so they pass")
-- walking my way ahead: behind him at his pace, no passing
C.Invalidate() me.tifCrowd = nil
st.vel = Vector(60, 0, 0)
st.pos = Vector(45, 0, 0)
pace, p = C.Steer(me, fwd, 120, Vector(400, 0, 0), now)
check(p == nil and math.abs(pace - 60) < 1, "file: kept behind at his pace (" .. pace .. ")")
-- past my goal / behind me / off the lane: ignored
C.Invalidate() me.tifCrowd = nil
st.vel = Vector()
pace, p = C.Steer(me, fwd, 100, Vector(20, 0, 0), now)
check(p == nil and pace == 100, "someone past where I stop: ignored")
C.Invalidate() me.tifCrowd = nil
st.pos = Vector(-40, 0, 0)
pace, p = C.Steer(me, fwd, 100, Vector(400, 0, 0), now)
check(p == nil, "behind me: ignored")
C.Invalidate() me.tifCrowd = nil
st.pos = Vector(50, 60, 0)
pace, p = C.Steer(me, fwd, 100, Vector(400, 0, 0), now)
check(p == nil, "off to the side, out of my lane: ignored")
-- rescans only every SCAN_T
C.Invalidate() me.tifCrowd = nil
st.pos = Vector(50, 0, 0)
C.Steer(me, fwd, 100, Vector(400, 0, 0), now)
local n0 = profN
C.Steer(me, fwd, 100, Vector(400, 0, 0), now + 0.05)
check(profN == n0, "no rescan inside SCAN_T")
-- off: nothing
cvOn = "0"
me.tifCrowd = nil
pace, p = C.Steer(me, fwd, 100, Vector(400, 0, 0), now + 1)
check(p == nil and pace == 100, "tif_crowd 0: no steering")
cvOn = "1"

-- ghosting
local a = body(Vector(0, 300, 0))
local b = body(Vector(10, 305, 0))
TIF.Soldiers = { a, b }
C.Invalidate()
timers.tif_crowd_tick = timers.tif_crowd_tick
C.Tick(200)
check(a.group == COLLISION_GROUP_NPC, "overlap just started: not yet")
C.Invalidate() C.Tick(200.6)
check(a.group == COLLISION_GROUP_NPC_SCRIPTED and b.group == COLLISION_GROUP_NPC_SCRIPTED, "overlapping 0.5 s+: both pass through each other")
-- still close: kept; apart and the minimum passed: back
b.pos = Vector(40, 300, 0)
C.Invalidate() C.Tick(200.9)
check(a.group == COLLISION_GROUP_NPC_SCRIPTED, "apart but under GHOST_MIN: kept")
C.Invalidate() C.Tick(201.4)
check(a.group == COLLISION_GROUP_NPC and b.group == COLLISION_GROUP_NPC, "apart: normal collisions back")
-- root-motion clip into someone: at once
b.pos = Vector(8, 300, 0)
a.tifAct = { root = true }
C.Invalidate() C.Tick(210)
check(a.group == COLLISION_GROUP_NPC_SCRIPTED and b.group == COLLISION_GROUP_NPC_SCRIPTED, "root-motion clip into someone: ghosted at once")
a.tifAct = nil
-- someone else changed the group meanwhile (vehicle / death): left alone
b.group = COLLISION_GROUP_DEBRIS
b.pos = Vector(200, 300, 0)
C.Invalidate() C.Tick(212)
check(b.group == COLLISION_GROUP_DEBRIS and a.group == COLLISION_GROUP_NPC, "a group set by something else isn't overwritten")
-- vehicle riders / other groups never ghosted
local c1 = body(Vector(0, 600, 0))
local c2 = body(Vector(5, 600, 0))
c2.group = COLLISION_GROUP_DEBRIS
TIF.Soldiers = { c1, c2 }
C.Invalidate() C.Tick(220) C.Invalidate() C.Tick(221)
check(c2.group == COLLISION_GROUP_DEBRIS, "a debris-group body isn't ghosted")
-- off: restores
c2.group = COLLISION_GROUP_NPC
C.Invalidate() C.Tick(222) C.Invalidate() C.Tick(223)
check(c1.group == COLLISION_GROUP_NPC_SCRIPTED, "(ghosted)")
cvOn = "0"
cbs.tif_crowd(nil, "1", "0")
check(c1.group == COLLISION_GROUP_NPC and c2.group == COLLISION_GROUP_NPC, "tif_crowd 0: ghosts restored")
cvOn = "1"

-- side point
local s = body(Vector(0, 900, 0))
walls = { { -50, 50, 850, 890 } }   -- wall on his right (-y)
local sp = C.SidePoint(s, fwd, 44)
check(sp and sp.y > 900, "side point: the open side")
walls = { { -50, 50, 850, 890 }, { -50, 50, 910, 950 } }
check(C.SidePoint(s, fwd, 44) == nil, "hemmed in: none")
walls = {}

-- 0.38.26: stuck pressed together -> through each other for 1.5 s; an idle soldier steps out of the line
do
	local a = body(Vector(0, 1500, 0))
	local b = body(Vector(25, 1500, 0))
	TIF.Soldiers = { a, b }
	C.Invalidate()
	check(C.GhostPair(a, b, 1.5, 300) and a.group == COLLISION_GROUP_NPC_SCRIPTED and b.group == COLLISION_GROUP_NPC_SCRIPTED, "GhostPair: both pass through")
	b.pos = Vector(200, 1500, 0)
	C.Invalidate() C.Tick(300.5)
	check(a.group == COLLISION_GROUP_NPC_SCRIPTED, "held the 1.5 s even once apart")
	C.Invalidate() C.Tick(301.6)
	check(a.group == COLLISION_GROUP_NPC and b.group == COLLISION_GROUP_NPC, "then back")
	cvOn = "0"
	check(not C.GhostPair(a, b, 1.5, 302), "tif_crowd 0: no")
	cvOn = "1"
	-- make way: standing soldier ahead and a little to the mover's right steps further right
	local mover = body(Vector(0, 2000, 0))
	local stand = body(Vector(30, 1995, 0))
	stand.TIFSoldier, stand.tifMove = true, {}
	local approached
	stand.loco = { GetVelocity = function() return Vector() end, SetDesiredSpeed = function() end, Approach = function(_, p) approached = p end }
	check(C.MakeWay(stand, mover, Vector(1, 0, 0), 300), "MakeWay: an idle soldier steps aside")
	local w = C.Way[stand]
	check(w and w.pos.y < 1995 - 20, "...out of the mover's line, on the side he already leans to (" .. tostring(w and w.pos.y) .. ")")
	hooks["Tick:tif_crowd_way"]()
	check(approached ~= nil, "...walked there every tick")
	check(not C.MakeWay(stand, mover, Vector(1, 0, 0), 301), "not again straight away")
	local busy = body(Vector(30, 2100, 0))
	busy.TIFSoldier, busy.tifMove, busy.tifCov = true, {}, true
	busy.loco = stand.loco
	check(not C.MakeWay(busy, mover, Vector(1, 0, 0), 300), "a soldier in cover doesn't move")
	local mv = io.open(ROOT .. "tif/npc/sv_move.lua"):read("*a")
	check(mv:find("C.GhostPair(npc, b, M.PASS_T, now)", 1, true) and mv:find("C.MakeWay(b, npc, fwd, now)", 1, true), "unstick: pass through + make way on TIF bodies")
	check(mv:find("bestP = me - fwd * M.BACKOFF", 1, true) and mv:find("m.avoid = {", 1, true) and mv:find("cost = cost + dist * 6", 1, true), "unstick: back off further and path round the spot otherwise")
end
-- hooked into soldier movement and civilians
local mv = io.open(ROOT .. "tif/npc/sv_move.lua"):read("*a")
check(mv:find("want, steer = TIF.Crowd.Steer(npc, fwd, want, m.goal, now)", 1, true) and mv:find("npc.loco:Approach(steer, TIF.Crowd.WEIGHT)", 1, true), "soldier path following steers")
local cv = io.open(ROOT .. "entities/tif_civilian.lua"):read("*a")
check(cv:find("Crowd.Steer(self, fwd, speed, pos, now)", 1, true) and cv:find("Crowd.SidePoint(self, f, 44)", 1, true), "civilians steer and sidestep when stuck")
check(not cv:find("ENT.STUCK_T", cv:find("function ENT:GoTo", 1, true), true) or cv:find("ENT.STUCK_T, ENT.STUCK_MAX", 1, true) > cv:find("return \"ok\"", 1, true), "civ GoTo reads self.STUCK_T at run time")
local init = io.open(ROOT .. "autorun/tif_init.lua"):read("*a")
check(init:find('"npc/sv_crowd.lua"', 1, true) ~= nil, "loaded")
print(string.format("passed %d, failed %d", pass, fail))
