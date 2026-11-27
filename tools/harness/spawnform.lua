local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:DistToSqr(o) local d = self - o return d:Dot(d) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function IsValid(x) return x ~= nil and x ~= false end
navmesh = { GetNearestNavArea = function() return nil end, GetNavAreaCount = function() return 10 end }
util = { TraceHull = function() return { Hit = false, StartSolid = false } end, TraceLine = function(t) return { Hit = true, HitPos = t.endpos } end }
MASK_NPCSOLID, MASK_SOLID_BRUSHONLY = 1, 2
TIF = { Squad = {} }
function TIF.Squad.SlotOffset(f, i, spacing)
	local k = math.ceil(i / 2)
	return Vector(-spacing * k, (i % 2 == 1 and 1 or -1) * spacing * k, 0)
end
assert(loadfile(ROOT .. "tif/core/sv_spawn.lua"))()
local center = Vector(1000, 0, 0)
local player = Vector(0, 0, 0)
local yaw = (player - center):Angle().y
local pts = TIF.FormationPoints(center, 8, yaw)
check(#pts == 8, "8 points for a squad of 8")
check(pts[1]:DistToSqr(center) < 1, "the leader stands on the spot aimed at")
local toPlayer = Vector(-1, 0, 0)
local behind = true
for i = 2, #pts do if (pts[i] - center):Dot(toPlayer) > -1 then behind = false end end
check(behind, "everyone else forms up behind him, on the far side from the player")
local spread = true
for i = 1, #pts do for j = i + 1, #pts do if pts[i]:DistToSqr(pts[j]) < 40 * 40 then spread = false end end end
check(spread, "nobody spawns on top of anyone")
check(math.abs(pts[2].y + pts[3].y) < 1 and pts[2].y * pts[3].y < 0, "a wedge: pairs left and right of the leader")
local src = io.open(ROOT .. "tif/core/sv_spawn.lua"):read("*a")
check(src:find("formYaw = (ply:GetPos() - center):Angle().y", 1, true) ~= nil, "the formation faces the spawning player")
check(src:find("if formYaw then\n\t\t\t\tyaw = formYaw", 1, true) ~= nil, "every soldier faces the same way (not a fan)")
local sp = io.open(ROOT .. "entities/tif_spawner.lua"):read("*a")
check(sp:find('"me" or "random",', 1, true) and sp:find("formation = true", 1, true), "spawn-menu fireteams / squads spawn in formation facing you")
local ord = io.open(ROOT .. "tif/squad/sv_orders.lua"):read("*a")
check(ord:find('local face = args[4] or "me"', 1, true) and ord:find('formation = face == "me"', 1, true), "tif_spawn_squad does too by default")
print(string.format("passed %d, failed %d", pass, fail))
