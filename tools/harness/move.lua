-- Offline: sv_move.lua 0.19.7 movement fixes: goal spreading, sprint ramp, stuck watch + sidestep.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Length() return math.sqrt(self:Dot(self)) end
function V:LengthSqr() return self:Dot(self) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:Length2DSqr() return self.x ^ 2 + self.y ^ 2 end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Distance(o) return (self - o):Length() end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:Mul(k) self.x, self.y, self.z = self.x * k, self.y * k, self.z * k end
function Lerp(t, a, b) return a + (b - a) * t end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
function IsValid(x) return x ~= nil and x ~= false end
MASK_NPCSOLID, MASK_NPCSOLID_BRUSHONLY = 1, 2
local now = 10
function CurTime() return now end
function Path() return { SetMinLookAheadDistance = function() end, SetGoalTolerance = function() end,
	IsValid = function() return true end, Invalidate = function() end, Compute = function() return true end,
	Update = function() end } end
navmesh = { GetNearestNavArea = function(p) return { GetClosestPointOnArea = function(_, q) return q end } end }
local walls = {}  -- x-ranges blocked for traces
util = {
	TraceLine = function(t) return { Hit = false } end,
	TraceHull = function(t)
		for _, w in ipairs(walls) do if w(t.endpos) then return { Fraction = 0.1 } end end
		return { Fraction = 1 }
	end,
}
local near = {}
ents = { FindInSphere = function() return near end }
TIF = { Budget = { Take = function() return true end }, Prof = { Begin = function() end, End = function() end },
	Anim = { Speeds = function() return { walk = 68, tactical = 100, alert = 90, run = 186, aimrun = 150, sprint = 278, crouch = 50 } end },
	Factions = {}, Soldiers = {}, Weapon = {}, Action = { Done = function() return true end, Clear = function() end } }
dofile(ROOT .. "tif/npc/sv_move.lua")
local M = TIF.Move

local function soldier(pos)
	local s = { pos = pos, vel = Vector(), fwd = Vector(1, 0, 0), tifArch = { speeds = {}, turnRate = 200 }, tifHomeHost = "mw_male" }
	function s:GetPos() return self.pos end
	function s:GetForward() return self.fwd end
	function s:IsNPC() return false end
	function s:IsPlayer() return false end
	function s:IsNextBot() return true end
	s.nw = {}
	function s:GetNW2String(k, d) return self.nw[k] or d end
	function s:SetNW2String(k, v) self.nw[k] = v end
	s.loco = { want = 0,
		SetDesiredSpeed = function(_, v) s.loco.want = v end, GetVelocity = function() return Vector(s.vel.x, s.vel.y, 0) end,
		Approach = function(_, p) s.approached = p end, IsStuck = function() return false end, ClearStuck = function() end,
		GetStepHeight = function() return 18 end, GetDeathDropHeight = function() return 200 end }
	M.Init(s)
	TIF.Soldiers[#TIF.Soldiers + 1] = s
	return s
end

-- Spreading: three soldiers sent to one sound each get their own spot.
local a, b, c = soldier(Vector(0, 0, 0)), soldier(Vector(0, 400, 0)), soldier(Vector(-400, 0, 0))
local sound = Vector(600, 0, 0)
check(M.SetGoal(a, sound, "alert", "investigate"), "first goal set")
check(a.tifMove.goal:DistToSqr(sound) < 1, "first soldier: the spot itself")
M.SetGoal(b, sound, "alert", "investigate")
M.SetGoal(c, sound, "alert", "investigate")
local ga, gb, gc = a.tifMove.goal, b.tifMove.goal, c.tifMove.goal
check(gb:DistToSqr(ga) >= M.SPREAD_R ^ 2 and gc:DistToSqr(ga) >= M.SPREAD_R ^ 2 and gc:DistToSqr(gb) >= M.SPREAD_R ^ 2,
	"three soldiers, three spots " .. M.SPREAD_R .. "+ apart")
check(gb:DistToSqr(sound) < 100 ^ 2 and gc:DistToSqr(sound) < 100 ^ 2, "the spread spots stay around the sound")
check((gb - sound).y > 0, "b's spot is on b's side (he came from +y)")
-- the same order again (every think): no re-spread, no new path
b.tifMove.needCompute = false
M.SetGoal(b, sound, "alert", "investigate")
check(b.tifMove.goal == gb and not b.tifMove.needCompute, "repeating the order keeps the spread spot")
-- exempt moves are left alone
local d = soldier(Vector(0, -400, 0))
M.SetGoal(d, sound, "walk", "formation")
check(d.tifMove.goal:DistToSqr(sound) < 1, "formation moves aren't spread")

-- Sprint ramp: from the current pace up to full over SPRINT_RAMP.
local r = soldier(Vector(3000, 3000, 0))
M.SetGoal(r, Vector(5000, 3000, 0), "sprint", "maneuver")
r.tifMove.fresh = nil
M.Step(r) -- path compute
M.Step(r)
local s0 = r.loco.want
now = now + 0.75
r.pos = r.pos + Vector(150, 0, 0)
M.Step(r)
local s1 = r.loco.want
now = now + 1.0
r.pos = r.pos + Vector(250, 0, 0)
M.Step(r)
local s2 = r.loco.want
check(s0 <= 101 and s1 > s0 and s1 < 278 and math.abs(s2 - 278 * M.SPRINT_SCALE) < 0.01, string.format("sprint builds up: %.0f -> %.0f -> %.0f", s0, s1, s2))

-- Stuck: trying to walk but not moving -> sidestep away from the soldier in the way, then a fresh path.
TIF.Soldiers = {}
local w = soldier(Vector(0, 0, 0))
local blockerS = soldier(Vector(30, 8, 0))
near = { w, blockerS }
M.SetGoal(w, Vector(800, 0, 0), "tactical", "maneuver")
w.tifMove.fresh = nil
w.vel = Vector(100, 0, 0)
M.Step(w) -- compute
for i = 1, 10 do now = now + 0.1 M.Step(w) end
check(w.tifMove.detour ~= nil, "caught on a squadmate: a sidestep starts")
check(w.tifMove.detour and w.tifMove.detour.pos.y < 0, "steps to the side away from him (he's at +y)")
now = now + 1.0
M.Step(w)
check(w.tifMove.detour == nil and w.tifMove.needCompute, "after the sidestep: a fresh path")
-- Walls on the free side: the other side.
near = {}
walls = { function(p) return p.y < -5 end }
w.tifMove.needCompute = false
w.tifMove.watch = nil
for i = 1, 10 do now = now + 0.1 M.Step(w) end
check(w.tifMove.detour and w.tifMove.detour.pos.y > 0, "wall on one side: steps to the open one")
-- Gives up after STUCK_MAX tries in a row.
for k = 1, 4 do
	w.tifMove.detour, w.tifMove.needCompute = nil, false
	for i = 1, 8 do now = now + 0.1 M.Step(w) end
end
check(w.tifMove.goal == nil and w.tifMove.result == "stuck", "still stuck after " .. M.STUCK_MAX .. " tries: goal given up")
-- Moving fine: never flagged.
TIF.Soldiers = {}
walls = {}
local f = soldier(Vector(0, 0, 0))
M.SetGoal(f, Vector(2000, 0, 0), "tactical", "maneuver")
f.tifMove.fresh = nil
M.Step(f)
for i = 1, 30 do now = now + 0.1 f.pos = f.pos + Vector(10, 0, 0) M.Step(f) end
check(f.tifMove.detour == nil and f.tifMove.stuckN == 0, "walking normally: no sidesteps")

-- 0.35.0: run and gun: which way the gun points off the run.
V.Angle = function(self) return { y = math.deg(math.atan2(self.y, self.x)) } end
math.AngleDifference = math.AngleDifference or function(a, b) return (a - b + 180) % 360 - 180 end
local rgClips = { mwrg_f = true, mwrg_l = true, mwrg_r = true, mwrg_bl = true, mwrg_br = true }
TIF.GTG = { IsVB = function() return true end, Clip = function(n) return rgClips[n] and {} or nil end }
local rg = soldier(Vector(0, 0, 0))
rg.vel = Vector(200, 0, 0)
for _, c in ipairs({ { Vector(500, 0, 0), "f" }, { Vector(0, 500, 0), "l" }, { Vector(0, -500, 0), "r" },
	{ Vector(-400, 300, 0), "bl" }, { Vector(-400, -300, 0), "br" } }) do
	rg.tifCoverFire = { aim = c[1] }
	check(M.RunGunDir(rg) == c[2], "run and gun at " .. c[2] .. " (" .. tostring(M.RunGunDir(rg)) .. ")")
end
rg.vel = Vector(40, 0, 0)
check(M.RunGunDir(rg) == "", "too slow: no run and gun")
print(string.format("passed %d, failed %d", pass, fail))
