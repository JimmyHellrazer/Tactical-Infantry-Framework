local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end return Vector(a.x * b, a.y * b, a.z * b) end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:LengthSqr() return self:Dot(self) end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Normalize() local l = math.sqrt(self:LengthSqr()) if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
vector_origin = Vector(0, 0, 0)
angle_zero = {}
local fwdA = { Forward = function() return Vector(1, 0, 0) end }
function LocalToWorld(p, a, op, oa) return op + p, fwdA end
function WorldToLocal(p, a, op, oa) return p - op, fwdA end
function EyePos() return Vector(0, 0, 0) end
function IsValid(x) return x ~= nil end
local cvOn = true
function GetConVar() return { GetBool = function() return cvOn end } end
TIF = {}
assert(loadfile(ROOT .. "tif/npc/cl_eyes.lua"))()
local E = TIF.Eyes
local target
local f = { GetModel = function() return "m.mdl" end, LookupAttachment = function() return 1 end,
	GetAttachment = function() return { Pos = Vector(100, 0, 64), Ang = fwdA } end,
	SetEyeTarget = function(self, t) target = t end }
local hm = { GetTranslation = function() return Vector(100, 0, 60) end, GetAngles = function() return fwdA end }
local look = vector_origin
local ent = { GetPos = function() return Vector(100, 0, 0) end, LookupBone = function() return 6 end,
	GetBoneMatrix = function() return hm end, GetNW2Vector = function() return look end }
local st = { follower = f }
E.Update(ent, st)
check(target and target.x > 150 and math.abs(target.y) < 1e-6, "nothing to look at: straight ahead of the face")
look = Vector(300, 200, 64)
E.Update(ent, st)
local ang = math.deg(math.atan2(target.y, target.x))
check(target and math.abs(ang - 40) < 0.5, "looking at something 45 deg off: eyes turn to the 40 deg cone edge (" .. tostring(ang) .. ")")
look = Vector(300, 50, 64)
E.Update(ent, st)
ang = math.deg(math.atan2(target.y, target.x))
check(ang > 13 and ang < 15, "inside the cone: straight at it (" .. ang .. ")")
local saved = target
ent.GetPos = function() return Vector(2000, 0, 0) end
E.Update(ent, st)
check(target == saved, "beyond 900: left alone")
check(f.tifEyesByBody == true, "the old head-forward code steps aside for it")
local soldier = io.open(ROOT .. "entities/tif_soldier.lua"):read("*a")
check(soldier:find('local look = (fw and fw.want and fw.aimPos) or self.tifAimAt or self.tifFace', 1, true) ~= nil, "server: look point = shooting at, else aiming at, else facing")
check(soldier:find("if not sent or sent:DistToSqr(look) > 32 * 32 then", 1, true) ~= nil, "only resent when it moves 32+ units")
local body = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
check(body:find("place_gun_vb(st, ent)\n\t\tif TIF.Eyes then TIF.Eyes.Update(ent, st) end", 1, true) ~= nil, "run after the bone build (on-screen soldiers only)")
print(string.format("passed %d, failed %d", pass, fail))
