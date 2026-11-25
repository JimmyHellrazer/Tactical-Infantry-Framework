-- Offline (0.38.4): CQB flashes are a chance per room; the entry waits for the bang; the grenade is kept in the
-- room (tif_grenade tifForce); knockdown ragdolls start from the action pose and go loose.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function IsValid(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end

-- flash_waiting from sv_clear
local src = io.open(ROOT .. "tif/building/sv_clear.lua"):read("*a")
local fw = src:match("(local function flash_waiting%(cq, now%).-\nend\n)")
check(fw ~= nil, "flash_waiting found")
local CQB = { AFTER_BANG = 0.25 }
local flash_waiting = assert(load(fw .. "\nreturn flash_waiting", "fw", "t", setmetatable({ CQB = CQB, IsValid = IsValid }, { __index = _G })))()
local cq = { flashWait = { untilT = 10 } }
check(flash_waiting(cq, 1) == true, "thrown not yet released: waits")
local g = {}
cq.flashWait.g = g
check(flash_waiting(cq, 2) == true, "in the air: waits")
g.tifDone = true
check(flash_waiting(cq, 2.5) == true, "just went off: a beat more")
check(flash_waiting(cq, 2.8) == false and cq.flashWait == nil, "after the bang + 0.25 s: in")
cq = { flashWait = { untilT = 10, lost = true } }
check(flash_waiting(cq, 1) == false, "thrower died before release: no wait")
cq = { flashWait = { untilT = 3 } }
check(flash_waiting(cq, 3.1) == false, "safety timeout")
check(src:find('math.random() > cvFlashChance:GetFloat()', 1, true) ~= nil, "a chance per room (tif_cqb_flash_chance)")
check(src:find("cq.flashed, cq.flashWait = nil, nil", 1, true) ~= nil, "a fresh roll for every room")
check(src:find('GR.Throw(m, target, src, "flash", { force = force })', 1, true) ~= nil, "the flash is thrown with its room")

-- tif_grenade guide: kept in the room
local gsrc = io.open(ROOT .. "entities/tif_grenade.lua"):read("*a")
local guide = gsrc:match("(local IN_ROOM = .-\n\tfunction ENT:Think%(%).-\n\tend\n)")
check(guide ~= nil, "grenade guide found")
local ENT = {}
local CurTime = function() return 5 end
local envG = setmetatable({ ENT = ENT, CurTime = CurTime, Vector = Vector, SafeRemoveEntityDelayed = function() end }, { __index = _G })
assert(load(guide, "g", "t", envG))()
local function nade(pos, vel)
	local e = { pos = pos, vel = vel, fuse = 99, tifFuseAt = 99, kind = "flash" }
	function e:GetPos() return self.pos end
	function e:SetPos(p) self.pos = p end
	function e:GetPhysicsObject() local s = self return { GetVelocity = function() return s.vel end, SetVelocity = function(_, v) s.vel = v end } end
	function e:GetKind() return self.kind end
	function e:Flash() self.flashedAt = Vector(self.pos.x, self.pos.y, self.pos.z) end
	function e:Frag() end
	function e:NextThink() end
	for k, f in pairs(ENT) do e[k] = f end
	e.tifForce = { pos = Vector(220, 0, 0), door = Vector(0, 0, 0), inward = Vector(1, 0, 0) }
	return e
end
local n1 = nade(Vector(60, 0, 0), Vector(300, 0, 0))
n1:Think()
check(n1.tifForce.wasIn, "inside the room: noted")
n1.pos, n1.vel = Vector(10, 0, 0), Vector(-250, 40, 0)
n1:Think()
check(n1.vel.x > 0, "bouncing back out the doorway: turned back in (" .. n1.vel.x .. ")")
local n2 = nade(Vector(-40, 30, 0), Vector(0, 0, 0))
n2.tifFuseAt = 1
n2:Think()
check(n2.flashedAt and n2.flashedAt.x == 220, "outside when the fuse ends: goes off at the target in the room")
local n3 = nade(Vector(150, 20, 0), Vector(0, 0, 0))
n3.tifFuseAt = 1
n3:Think()
check(n3.flashedAt and n3.flashedAt.x == 150, "already in the room: goes off where it lies")

-- knockdown / no-clip ragdolls
local ssrc = io.open(ROOT .. "entities/tif_soldier.lua"):read("*a")
check(ssrc:find("local act = not boneVel and self.tifAct", 1, true) ~= nil, "ragdoll posed from the action he was in")
check(ssrc:find("phys:AddAngleVelocity(VectorRand() * 160)", 1, true) ~= nil, "limbs get their own motion (no rigid plank)")
check(ssrc:find("fallback_ragdoll", 1, true) ~= nil, "models without ragdoll physics get a stand-in ragdoll")
local hsrc = io.open(ROOT .. "tif/tactics/sv_hits_mw.lua"):read("*a")
local a = hsrc:find("pcall(npc.TIFMakeCorpse, npc, { pos = dmg:GetDamagePosition()", 1, true)
local b = hsrc:find("Act.Clear(npc)", a or 1, true)
check(a and b and a < b, "knockdown: ragdoll made before the action is cleared")
print(string.format("passed %d, failed %d", pass, fail))
