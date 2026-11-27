local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function math.Round(x) return math.floor(x + 0.5) end
function math.NormalizeAngle(a) a = a % 360 if a > 180 then a = a - 360 end return a end
local now = 50
function CurTime() return now end
local on, mult = true, 1
function CreateConVar(name) return { GetBool = function() return on end, GetFloat = function() return mult end } end
DMG_FALL = 32
local taken
function DamageInfo()
	local d = {}
	function d:SetDamage(v) self.dmg = v end
	function d:SetDamageType(v) self.type = v end
	function d:SetAttacker(v) end
	function d:SetInflictor(v) end
	function d:SetDamagePosition(v) end
	function d:SetDamageForce(v) end
	return d
end
game = { GetWorld = function() return {} end }
local played, events = {}, {}
TIF = { GTG = { Clip = function(n) return n:find("^mwfl_") and { seq = n } or nil end },
	Action = { Play = function(npc, n, o) played[#played + 1] = { n = n, o = o } return 1.2 end },
	Event = function(...) events[#events + 1] = table.concat({ ... }) end }
assert(loadfile(ROOT .. "tif/tactics/sv_fall_mw.lua"))()
local F = TIF.Fall

check(F.Tier(100) == nil and F.Tier(200) == "hard" and F.Tier(300) == "stumble" and F.Tier(500) == "heavy" and F.Tier(800) == "lethal", "tiers by drop height")
check(F.Damage(200) == 0, "a hard landing does no damage")
check(F.Damage(250) == 10 and F.Damage(450) == 40, "stumble damage runs 10 -> 40")
check(F.Damage(450) == 40 and F.Damage(699) >= 89, "heavy damage runs 40 -> 90")
check(F.Damage(900) == 1000, "lethal falls kill")
mult = 0.5
check(F.Damage(450) == 20, "tif_fall_damage_mult scales it")
mult = 1

local function mk(z, yaw, vel)
	local e = { z = z, yaw = yaw or 0, v = vel or Vector(), hp = 100, tifFire = { want = true }, tifHostId = "mw_male" }
	function e:GetPos() return Vector(0, 0, self.z) end
	function e:GetAngles() return { y = self.yaw } end
	e.loco = { GetVelocity = function() return e.v end }
	function e:TakeDamageInfo(d) taken = d self.hp = self.hp - d.dmg if self.hp <= 0 then self.tifDead = true end end
	function e:EntIndex() return 9 end
	return e
end

local a = mk(500)
F.Leave(a)
a.z = 420
taken, played = nil, {}
check(F.Land(a) == nil and taken == nil and #played == 0, "an 80 u drop is nothing")

local b = mk(500)
F.Leave(b)
b.z = 320
taken, played = nil, {}
check(F.Land(b) == "hard" and taken == nil and played[1].n == "mwfl_land", "a 180 u drop standing: hard landing clip, no damage")
check(b.tifPainUntil == nil, "and he can keep shooting")

local c = mk(500, 0, Vector(200, 0, -300))
F.Leave(c)
c.z = 320
played = {}
F.Land(c)
check(played[1].n == "mwfl_land_8", "moving forward: the forward jog landing")
local c2 = mk(500, 90, Vector(200, 0, -300))
F.Leave(c2)
c2.z = 320
played = {}
F.Land(c2)
check(played[1].n == "mwfl_land_6", "moving to his right: the right landing")

local d = mk(500)
F.Leave(d)
d.z = 150
taken, played = nil, {}
check(F.Land(d) == "stumble" and taken.dmg == 25 and taken.type == DMG_FALL, "a 350 u drop: stumble and 25 fall damage")
check(played[1].n:match("^mwfl_stumble[12]_8$") and played[1].o.root and played[1].o.clear, "standing: a forward stumble clip with root motion")
check(d.tifPainUntil and d.tifPainUntil > now and d.tifFire.want == false, "and he can't fire for a moment")
check(#events == 1 and events[1]:find("fell 350", 1, true), "logged as a fall event")

local e = mk(500, 0, Vector(250, 0, -400))
F.Leave(e)
e.z = 100
played = {}
F.Land(e)
check(played[1].n:match("^mwfl_stumble_sprint[12]$"), "sprinting off a ledge: the sprint stumble, keeps going")

local f = mk(1000)
F.Leave(f)
f.z = 200
played = {}
check(F.Land(f) == "lethal" and f.tifDead and #played == 0, "an 800 u fall kills him outright")

for _, flag in ipairs({ "tifTrav", "tifHeli", "tifVeh", "tifKnock", "tifDowned" }) do
	local g = mk(500)
	g[flag] = true
	F.Leave(g)
	g.z = 100
	taken = nil
	F.Land(g)
	check(taken == nil, "no fall damage with " .. flag)
end
local h = mk(500)
F.Leave(h)
h.tifTrav = true
h.z = 100
taken = nil
F.Land(h)
check(taken == nil, "a traversal starting mid-air cancels the fall")
on = false
local i = mk(500)
F.Leave(i)
i.z = 100
taken = nil
check(F.Land(i) == nil and taken == nil, "tif_fall_damage 0 turns it off")
on = true

local src = io.open(ROOT .. "entities/tif_soldier.lua"):read("*a")
check(src:find("function ENT:OnLeaveGround()\n\tif TIF.Fall then\n\t\tTIF.Fall.Leave(self)", 1, true) and src:find("function ENT:OnLandOnGround()\n\tif TIF.Fall then\n\t\tTIF.Fall.Land(self)", 1, true), "the soldier reports leaving and landing")
local init = io.open(ROOT .. "autorun/tif_init.lua"):read("*a")
check(init:find('"tactics/sv_fall_mw.lua"', 1, true) ~= nil, "the module loads")
print(string.format("passed %d, failed %d", pass, fail))
