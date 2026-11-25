-- 2026-11-21: soldiers open doors in their way when the MW19 door clip can't play (crouched, mid clip, at an angle);
-- NPC physics bumps don't damage doors (compat/sv_doors.lua, destructible-door mods).
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function IsValid(x) return x ~= nil and x ~= false end
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[ev .. ":" .. id] = fn end }
function CreateConVar() return { GetBool = function() return true end } end
FCVAR_ARCHIVE = 0
DMG_CRUSH, DMG_PHYSGUN, DMG_GENERIC, DMG_BULLET, DMG_BLAST, DMG_CLUB, DMG_SLASH, DMG_BUCKSHOT, DMG_BURN, DMG_SONIC =
	1, 2, 0, 4, 8, 16, 32, 64, 128, 256
bit = require("bit")
timer = { Simple = function() end }

local function door(pos, locked)
	local d = { pos = pos, fired = {}, locked = locked }
	function d:GetClass() return "prop_door_rotating" end
	function d:GetInternalVariable(k) if k == "m_eDoorState" then return 0 end if k == "m_bLocked" then return self.locked end end
	function d:WorldSpaceCenter() return self.pos + Vector(0, 0, 50) end
	function d:GetPos() return self.pos + Vector(0, 24, 0) end
	function d:Fire(i) self.fired[#self.fired + 1] = i end
	function d:EmitSound() end
	return d
end
local doors = {}
ents = { FindInSphere = function() return doors end }
TIF = { Action = { RootAt = function() return 60, 0, 0 end, Play = function() return 1 end },
	GTG = { IsVB = function() return true end, Clip = function() return nil end }, Anim = { STANCE_CROUCH = 1 } }
assert(loadfile(ROOT .. "tif/tactics/sv_door_mw.lua"))()
assert(loadfile(ROOT .. "tif/compat/sv_doors.lua"))()
local D = TIF.DoorMW

local function soldier(pos, vel, crouch)
	local s = { pos = pos, tifHomeHost = "mw_male", tifHostId = "mw_male" }
	function s:GetPos() return self.pos end
	function s:GetTIFStance() return crouch and 1 or 0 end
	function s:IsNPC() return false end
	function s:IsNextBot() return true end
	s.loco = { GetVelocity = function() return Vector(vel, 0, 0) end }
	return s
end

-- crouched, walking into a closed door 40 ahead: no clip for that: it's opened
local d1 = door(Vector(40, 0, 0))
doors = { d1 }
local s1 = soldier(Vector(0, 0, 0), 60, true)
D.Check(s1, {}, 1)
check(d1.fired[1] == "OpenAwayFrom", "crouched into a door: opened as he gets to it")
-- still 90 away: not yet
local d2 = door(Vector(90, 0, 0))
doors = { d2 }
D.Check(soldier(Vector(0, 0, 0), 60, true), {}, 2)
check(#d2.fired == 0, "90 away: not yet")
-- mid another clip: opened too
local d3 = door(Vector(30, 0, 0))
doors = { d3 }
local s3 = soldier(Vector(0, 0, 0), 100, false)
s3.tifAct = { name = "mwt_start" }
D.Check(s3, {}, 3)
check(d3.fired[1] == "OpenAwayFrom", "mid a start clip: opened")

-- the bump compat
local h = hooks["EntityTakeDamage:tif_door_bump"]
local function dmg(t, att) return { GetDamageType = function() return t end, GetAttacker = function() return att end, GetInflictor = function() return nil end } end
local npc = soldier(Vector(0, 0, 0), 0)
local d4 = door(Vector(30, 0, 0))
check(h(d4, dmg(DMG_CRUSH, npc)) == true and d4.fired[1] == "OpenAwayFrom", "an NPC's physics bump: no damage, the door opens")
local d5 = door(Vector(30, 0, 0))
check(h(d5, dmg(DMG_BULLET, npc)) == nil and #d5.fired == 0, "shot by an NPC: the mod's damage stands")
local ply = { IsNPC = function() return false end, IsNextBot = function() return false end }
check(h(door(Vector(0, 0, 0)), dmg(DMG_CRUSH, ply)) == nil, "a player's bump: untouched")
local d6 = door(Vector(30, 0, 0), true)
check(h(d6, dmg(DMG_CRUSH, npc)) == true and #d6.fired == 0, "locked: no damage, stays shut")
print(string.format("passed %d, failed %d", pass, fail))
