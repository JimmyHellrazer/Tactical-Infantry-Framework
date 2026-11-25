-- Offline (0.38.21): friendly flashes (tif_flash_friendly) - reach and stun scaled on the thrower's own side.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:Distance(o) return (self - o):Length() end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
function Lerp(k, a, b) return a + (b - a) * k end
math.Clamp = function(v, a, b) return math.min(b, math.max(a, v)) end
function IsValid(x) return x ~= nil and x ~= false end
FCVAR_ARCHIVE, MASK_SOLID, CONTENTS_GRATE = 1, 1, 0
local share = "0.3"
function CreateConVar() return { GetFloat = function() return tonumber(share) end } end
hook = { Add = function() end }
timer = { Simple = function() end }
scripted_ents = {}
util = { TraceLine = function() return { Hit = false, Fraction = 1 } end }
local stuns = {}
TIF = { Soldiers = {}, REL_ALLY = 1, API = { Stun = function(npc, s) stuns[npc] = s end },
	Relation = function(a, b) return a.side == b.side and 1 or -1 end,
	EyeOf = function(n) return n.pos end }
assert(loadfile(ROOT .. "tif/compat/sv_flashbangs.lua"))()
local function soldier(x, side)
	return { pos = Vector(x, 0, 0), side = side, GetForward = function() return Vector(-1, 0, 0) end }
end
local thrower = soldier(0, "a")
local nade = { GetOwner = function() return thrower end }
local ally_near, ally_far, enemy_far = soldier(100, "a"), soldier(400, "a"), soldier(400, "b")
TIF.Soldiers = { ally_near, ally_far, enemy_far }
TIF.FlashAt(Vector(0, 0, 0), 780, nade)
check(stuns[enemy_far] ~= nil, "enemy at 400: stunned (full range)")
check(stuns[ally_far] == nil, "ally at 400: out of the friendly reach (0.3 x 780 = 234)")
check(stuns[ally_near] ~= nil, "ally at 100: still stunned")
-- the ally's stun is the share of what an enemy there would get
local friendly = stuns[ally_near]
TIF.Soldiers = { soldier(100, "b") }
stuns = {}
TIF.FlashAt(Vector(0, 0, 0), 780, nade)
local full = select(2, next(stuns))
check(friendly and full and friendly < full * 0.5, "ally's stun much shorter than an enemy's at the same spot (" .. tostring(friendly) .. " vs " .. tostring(full) .. ")")
-- 0: no effect at all on the thrower's side
share = "0"
TIF.Soldiers = { ally_near, enemy_far }
stuns = {}
TIF.FlashAt(Vector(0, 0, 0), 780, nade)
check(stuns[ally_near] == nil and stuns[enemy_far] ~= nil, "tif_flash_friendly 0: allies untouched, enemies still stunned")
-- unknown thrower (other addons' flashbangs): full on everyone
stuns = {}
TIF.FlashAt(Vector(0, 0, 0), 780, {})
check(stuns[ally_near] ~= nil, "no thrower known: full flash")
-- players: the grenade uses the same scale
check(TIF.FlashScale(thrower, { side = "a" }) == 0 and TIF.FlashScale(thrower, { side = "b" }) == 1, "FlashScale: own side scaled, enemies 1")
local g = io.open(ROOT .. "entities/tif_grenade.lua"):read("*a")
check(g:find("TIF.FlashScale(thrower, ply)", 1, true) and g:find("local R = FLASH_R * s", 1, true), "players' white-out scaled the same way")
print(string.format("passed %d, failed %d", pass, fail))
