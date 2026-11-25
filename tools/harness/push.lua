-- (0.38.21: sv_flashbangs makes tif_flash_friendly at load)
CreateConVar = CreateConVar or function() return { GetFloat = function() return 0.3 end, GetBool = function() return true end, GetInt = function() return 1 end } end
-- Offline: TIF.FlashAt (compat/sv_flashbangs.lua) and TIF.Squad.AdvancePace (squad/sv_squad.lua).
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
function V:DistToSqr(o) return (self - o):Length() ^ 2 end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
function Lerp(t, a, b) return a + (b - a) * t end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
function IsValid(x) return x ~= nil end
MASK_SOLID, CONTENTS_GRATE = 1, 0
local wallX
util = { TraceLine = function(t)
	if wallX and (t.start.x - wallX) * (t.endpos.x - wallX) < 0 then return { Hit = true, Fraction = 0.5 } end
	return { Hit = false, Fraction = 1 }
end }
hook = { Add = function() end }
timer = { Simple = function() end }
scripted_ents = { GetStored = function() return nil end }
local stunned = {}
TIF = { API = { Stun = function(npc, s) stunned[npc] = s end } }
local function soldier(pos, fx)
	local s = { pos = pos, fx = fx or -1 }
	function s:GetPos() return self.pos end
	function s:GetForward() return Vector(self.fx, 0, 0) end
	return s
end
assert(loadfile(ROOT .. "tif/compat/sv_flashbangs.lua"))()
local near, far, away, behind, out = soldier(Vector(100, 0, 0)), soldier(Vector(700, 0, 0)), soldier(Vector(300, 0, 0), 1), soldier(Vector(-300, 0, 0)), soldier(Vector(2000, 0, 0))
TIF.Soldiers = { near, far, away, behind, out }
wallX = -150
local n = TIF.FlashAt(Vector(0, 0, 60), 787, nil)
check(stunned[near] and stunned[near] >= 5.5, "next to it: long stun: " .. tostring(stunned[near]))
check(stunned[far] and stunned[far] < stunned[near], "further: shorter: " .. tostring(stunned[far]))
check(stunned[away] and stunned[away] < 5, "looking away: shorter: " .. tostring(stunned[away]))
check(stunned[behind] == nil, "behind a wall: not stunned")
check(stunned[out] == nil and n == 3, "out of range: not stunned")

-- AdvancePace
local src = io.open(ROOT .. "tif/squad/sv_squad.lua"):read("*a")
local block = src:match("(SQ%.PACE = %b{}.-function SQ%.AdvancePace%(.-\nend)")
assert(block, "AdvancePace not found")
local SQ = {}
assert(load("local SQ = ...\n" .. block))(SQ)
local lead = soldier(Vector(0, 0, 0))
local o = { pace = "rush", pos = Vector(3000, 0, 0) }
local sq = {}
check(SQ.AdvancePace(sq, lead, o, 100) == "run", "rush, far and quiet: jog")
lead.pos = Vector(2400, 0, 0)
check(SQ.AdvancePace(sq, lead, o, 101) == "tactical", "rush, close: tactical")
lead.pos = Vector(0, 0, 0)
check(SQ.AdvancePace(sq, lead, o, 102) == "tactical", "slowed stays slowed (no flipping)")
local o2 = { pos = Vector(3000, 0, 0) }
check(SQ.AdvancePace(sq, lead, o2, 100) == "run", "move (default), far: jog")
sq.lastContact = 95
local o3 = { pos = Vector(3000, 0, 0) }
check(SQ.AdvancePace(sq, lead, o3, 100) == "tactical", "contact in the last 25 s: tactical")
check(SQ.AdvancePace({}, lead, { pace = "careful", pos = Vector(5000, 0, 0) }, 100) == "tactical", "careful: tactical")
print(string.format("passed %d, failed %d", pass, fail))
