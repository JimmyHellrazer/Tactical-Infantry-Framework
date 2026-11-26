local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function CreateConVar() return { GetBool = function() return true end } end
FCVAR_ARCHIVE = 1
hook = { Add = function() end }
timer = { Create = function() end }
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
CurTime = function() return 100 end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function V.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function V.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function V.__mul(a, s) return Vector(a.x * s, a.y * s, a.z * s) end
function V:DistToSqr(o) local d = self - o return d.x * d.x + d.y * d.y + d.z * d.z end
function V:Normalize() local l = math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function IsValid(e) return e ~= nil end
local goal
TIF = {
	AWARE = {}, Anim = { MODE_RELAXED = 0, STANCE_STAND = 0, STANCE_CROUCH = 1 },
	Action = { Clip = function() return false end, Loop = function() end }, Soldiers = {},
	Move = { Snap = function(p) return p end, SetGoal = function(_, g) goal = g return true end, Stop = function() end },
	CoverBehave = { In = function() return false end, Leave = function() end },
	ProneB = { Is = function() return false end },
	Squad = { Remove = function() end, Members = function() return {} end },
	Say = function() end,
	AIDisabled = function() return false end,
}
assert(loadfile(ROOT .. "tif/tactics/sv_morale.lua"))()
local MO = TIF.Morale
check(MO.Enabled(), "morale is on")
check(MO.SURRENDER == false, "surrender is off")
local npc = {
	tifArch = { suppressResist = 0.3 }, tifFire = {}, tifMoraleState = "broken",
	GetPos = function() return Vector(0, 0, 0) end, GetForward = function() return Vector(1, 0, 0) end,
	GetTIFFaction = function() return "insurgents" end, Health = function() return 10 end, GetMaxHealth = function() return 100 end,
	SetNW2Bool = function() end, SetNW2String = function() end, SetTIFWeapon = function() end, TIFDropWeapon = function() end,
}
TIF.Soldiers = { npc }
local c = { pos = Vector(200, 0, 0), visible = true }
local surrendered = false
for i = 1, 50 do
	npc.tifSurrenderRolled, npc.tifFlee = nil, nil
	MO.BrokenThink(npc, c, 100)
	if npc.tifSurrendered then surrendered = true end
end
check(not surrendered, "alone, hurt, enemy at 200: never surrenders")
check(npc.tifFire.want == false, "broken: holds fire")
check(goal and goal.x < 0, "broken: runs away from the enemy")
check(npc.tifAction == "broken: running", "broken: running state")
MO.SURRENDER = true
math.random = function() return 0 end
npc.tifSurrenderRolled = nil
MO.BrokenThink(npc, c, 100)
check(npc.tifSurrendered == true, "MO.SURRENDER = true brings surrender back")
print(string.format("passed %d, failed %d", pass, fail))
