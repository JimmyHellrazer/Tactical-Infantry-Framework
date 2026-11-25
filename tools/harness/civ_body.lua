-- (after trans.lua's header: box world, real clips)
function V:GetNormalized() local l = self:Length() return l > 0 and Vector(self.x / l, self.y / l, self.z / l) or Vector(0, 0, 0) end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Distance(o) return (self - o):Length() end
function VectorRand() return Vector(1, 0, 0) end
MASK_SOLID_BRUSHONLY, MASK_SHOT, DMG_BLAST = 1, 1, 64
function CurTime() return NOW end
NOW = 100
math.random = function(a, b) if a and b then return a end if a then return 1 end return RND end
RND = 0.1
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[ev] = fn end, Run = function() end }
timer = { Create = function(n, t, r, fn) hooks["timer_" .. n] = fn end }
util.IsValidModel = function(m) return m:find("drem") ~= nil end
local humans = {}
player = { GetHumans = function() return humans end }
navmesh = { GetNearestNavArea = function(p) return { GetClosestPointOnArea = function(_, q) return Vector(q.x, q.y, 0) end } end }
IsValid = function(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
assert(loadfile(ROOT .. "tif/tactics/sv_civilian.lua"))()
local Civ = TIF.Civ

check(Civ.PickModel():find("models/drem/cch/") ~= nil, "Czech civilian models used when installed")

-- A civilian with the entity's Scare logic.
local ENTsrc = io.open(ROOT:gsub("lua/$", "lua/") .. "entities/tif_civilian.lua"):read("*a")
local scareFn = ENTsrc:match("(function ENT:Scare%(pos, amount%).-\nend)")
local setFn = ENTsrc:match("(function ENT:SetState%(st%).-\nend)")
ENT = {}
assert(load("local function C() return TIF.Civ end\n" .. setFn .. "\n" .. scareFn))()
local function civ(pos)
	local c = setmetatable({ pos = pos, state = "wander", fear = 0 }, { __index = ENT })
	function c:GetPos() return self.pos end
	function c:SetNW2String() end
	function c:Remove() self.removed = true end
	Civ.Register(c)
	return c
end
local a, b, far = civ(Vector(200, 0, 0)), civ(Vector(400, 0, 0)), civ(Vector(5000, 0, 0))
RND = 0.1 -- below LEAVE_SHARE: scatters
Civ.Scare(Vector(0, 0, 0), 1600, 0.6)
check(a.state == "leave" and a.decided and a.leaving, "first scare, unlucky roll: scatters out of the area")
check(far.state == "wander", "far away: didn't notice")
RND = 0.9
local c2 = civ(Vector(300, 300, 0))
Civ.Scare(Vector(0, 0, 0), 1600, 0.6)
check(c2.state == "flee" and not c2.leaving, "other roll: stays and hides nearby")
c2.state = "hide"
RND = 0.1
Civ.Scare(Vector(1500, 1500, 0), 2400, 0.6)
check(c2.state == "hide" and not c2.leaving, "decided once: a later scare far off doesn't make him scatter")
Civ.Scare(Vector(300, 200, 0), 1000, 0.8)
check(c2.state == "leave" or c2.state == "flee", "shooting right at his hiding place: he moves on: " .. tostring(c2.state))
local sh = civ(Vector(100, 100, 0))
sh.shelter = true
Civ.Scare(Vector(0, 0, 0), 1600, 0.8)
check(not sh.leaving, "sheltering civilians never scatter")

-- Hide spot: away from the danger, behind a wall that blocks its view.
boxes = {}
box(Vector(-2000, -2000, -10), Vector(2000, 2000, 0))
box(Vector(500, -1000, 0), Vector(520, 1000, 300)) -- a wall between 500 and 520
local h = civ(Vector(400, 0, 0))
local spot = Civ.HideSpot(h, Vector(0, 0, 0))
check(spot and spot.pos.x > 520, "hides on the far side of the wall: " .. tostring(spot and spot.pos.x))
-- Leave point: far, away from the danger.
local lp = Civ.LeavePoint(h, Vector(0, 0, 0))
check(lp and lp.x > 1500, "scatters away from the danger: " .. tostring(lp and lp.x))

-- Gone once out of sight and far: removed, reported.
local left = {}
hook.Run = function(ev, c) if ev == "TIF_CivilianLeft" then left[#left + 1] = c end end
a.Remove = function(self) self.removed = true end
NOW = 110
local ply = { Alive = function() return true end, EyePos = function() return Vector(-3000, 0, 60) end, GetPos = function() return Vector(-3000, 0, 0) end,
	GetAimVector = function() return Vector(-1, 0, 0) end }
humans = { ply }
hooks["timer_tif_civilians"]()
check(a.removed and left[1] == a, "scattered civilian out of sight: removed and reported")
local v = civ(Vector(700, 0, 0))
v.state, v.scaredAt = "leave", NOW - 5
ply.EyePos = function() return Vector(500, 0, 60) end
ply.GetPos = function() return Vector(500, 0, 0) end
hooks["timer_tif_civilians"]()
check(not v.removed, "still in a player's view: kept")
print(string.format("passed %d, failed %d", pass, fail))
