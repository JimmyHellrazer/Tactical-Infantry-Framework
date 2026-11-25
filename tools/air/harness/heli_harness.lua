-- Offline harness for tif/air + entities/tif_heli (server side) on a stub GMod: flat ground at z=0, sky at
-- WORLD.sky, optional box obstacles. Run through lupa (heli_harness.py).
local ROOT = ...
local fails, passes = 0, 0
local function check(ok, label, detail)
	if ok then passes = passes + 1 print("[PASS] " .. label .. (detail and ("  -- " .. detail) or ""))
	else fails = fails + 1 print("[FAIL] " .. label .. (detail and ("  -- " .. detail) or "")) end
end

-- Vector / Angle ----------------------------------------------------------------
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
V.__mul = function(a, b)
	if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
	if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
	return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
V.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
V.__tostring = function(a) return string.format("(%.0f %.0f %.0f)", a.x, a.y, a.z) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function V:GetNormalized() local l = self:Length() return l > 0 and self / l or Vector() end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:DistToSqr(b) return (self - b):LengthSqr() end
function V:Distance(b) return (self - b):Length() end
function V:Angle()
	local yaw = math.deg(math.atan2(self.y, self.x))
	local pitch = -math.deg(math.atan2(self.z, math.sqrt(self.x ^ 2 + self.y ^ 2)))
	return Angle(pitch, yaw, 0)
end
local A = {}
A.__index = A
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, A) end
function A:Forward()
	local p, y = math.rad(self.p), math.rad(self.y)
	return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function A:Right()
	local y = math.rad(self.y)
	return Vector(math.sin(y), -math.cos(y), 0)
end
function LerpVector(t, a, b) return a + (b - a) * t end

function math.Clamp(v, a, b) return math.min(math.max(v, a), b) end
function math.Approach(c, t, d) if c < t then return math.min(c + d, t) end return math.max(c - d, t) end
function math.AngleDifference(a, b) local d = (a - b + 180) % 360 - 180 return d end
function math.Rand(a, b) return a + (b - a) * math.random() end
function math.Round(v) return math.floor(v + 0.5) end
function table.insert(t, v) t[#t + 1] = v end

-- World ---------------------------------------------------------------------------
WORLD = { sky = 4000, ground = 0, boxes = {} }
local function in_box(p, b) return p.x >= b.lo.x and p.x <= b.hi.x and p.y >= b.lo.y and p.y <= b.hi.y and p.z >= b.lo.z and p.z <= b.hi.z end
-- Swept sample trace (cheap and good enough here): steps along the line, a hull is sampled at its corners + centre.
local function sweep(start, endpos, mins, maxs)
	local n = 400
	local offs = { Vector() }
	if mins then
		for _, x in ipairs({ mins.x, maxs.x }) do for _, y in ipairs({ mins.y, maxs.y }) do for _, z in ipairs({ mins.z, maxs.z }) do
			offs[#offs + 1] = Vector(x, y, z)
		end end end
	end
	for i = 0, n do
		local t = i / n
		local c = start + (endpos - start) * t
		for _, o in ipairs(offs) do
			local p = c + o
			local hitN
			if p.z <= WORLD.ground then hitN = Vector(0, 0, 1) end
			if p.z >= WORLD.sky then return { Hit = true, HitSky = true, HitPos = Vector(c.x, c.y, WORLD.sky - (o.z > 0 and o.z or 0)), Fraction = t, HitNormal = Vector(0, 0, -1), StartSolid = i == 0 } end
			for _, b in ipairs(WORLD.boxes) do if in_box(p, b) then hitN = Vector(0, 0, 1) end end
			if hitN then
				return { Hit = true, HitPos = Vector(c.x, c.y, (o.z < 0 and p.z - o.z) or (p.z <= WORLD.ground and WORLD.ground or p.z)), Fraction = t, HitNormal = hitN, StartSolid = i == 0 }
			end
		end
	end
	return { Hit = false, HitPos = endpos, Fraction = 1, HitNormal = Vector(0, 0, 1) }
end
util = {
	TraceLine = function(t) return sweep(t.start, t.endpos) end,
	TraceHull = function(t) return sweep(t.start, t.endpos, t.mins, t.maxs) end,
	IsValidModel = function() return true end,
	BlastDamage = function() end,
	Effect = function() end,
}
MASK_SOLID, MASK_SOLID_BRUSHONLY, MASK_NPCSOLID_BRUSHONLY = 1, 2, 3
SOLID_VPHYSICS, MOVETYPE_VPHYSICS, DMG_BLAST, FCVAR_ARCHIVE = 6, 6, 64, 128
SERVER, CLIENT = true, false
NOW = 0
function CurTime() return NOW end
engine = { TickInterval = function() return 0.015 end }
function AddCSLuaFile() end
function CreateConVar(n, d) return { GetFloat = function() return tonumber(d) end } end
function GetConVar(n) return { GetFloat = function() return 1 end } end
hook = { Run = function(name, ...) HOOKS = HOOKS or {} HOOKS[#HOOKS + 1] = name end, Add = function() end }
timer = { Create = function() end }
concommand = { Add = function() end }
function IsValid(e) return e ~= nil and e ~= NULL and (type(e) ~= "table" or not rawget(e, "removed")) end
NULL = {}
function SafeRemoveEntityDelayed(e) e.removed = true end
function EffectData() return setmetatable({}, { __index = function() return function() end end }) end
function pcall(f, ...) return true, f(...) end -- surface errors
game = { GetWorld = function() return {} end }

TIF = { Log = function(...) end, CanUseDev = function() return true end }

-- Entities ------------------------------------------------------------------------
ENT = {}
local function load(rel) local f = assert(loadfile(ROOT .. rel)) f() end
load("lua/entities/tif_heli.lua")
local HELI = ENT
HELI.__index = HELI
local function make_ent()
	local e = setmetatable({ nw = {}, pos = Vector(), ang = Angle(), hp = 0 }, HELI)
	e.SetHeliType = function(s, v) s.nw.type = v end
	e.GetHeliType = function(s) return s.nw.type end
	for _, k in ipairs({ "Rotor", "DoorsOpen", "Dying", "Ropes" }) do
		e["Set" .. k] = function(s, v) s.nw[k] = v end
		e["Get" .. k] = function(s) return s.nw[k] end
	end
	e.SetModel = function() end
	e.SetNW2String = function(s, k, v) s.nw[k] = v end
	e.PhysicsInit = function() end
	e.SetMoveType = function() end
	e.SetSolid = function() end
	e.MakePhysicsObjectAShadow = function() end
	e.phys = { SetMass = function() end, UpdateShadow = function(p, pos, ang) e.pos, e.ang = pos, ang end,
		Wake = function() end, EnableGravity = function() end, SetVelocity = function() end, AddAngleVelocity = function() end,
		GetAngleVelocity = function() return Vector() end, ApplyForceCenter = function() end, GetMass = function() return 5000 end }
	setmetatable(e.phys, { __index = function() return function() end end })
	e.GetPhysicsObject = function(s) return s.phys end
	e.SetHealth = function(s, v) s.hp = v end
	e.Health = function(s) return s.hp end
	e.SetMaxHealth = function() end
	e.GetPos = function(s) return s.pos end
	e.SetPos = function(s, p) s.pos = p end
	e.GetAngles = function(s) return s.ang end
	e.SetAngles = function(s, a) s.ang = a end
	e.Spawn = function(s) s:Initialize() end
	e.Activate = function() end
	e.NextThink = function() end
	e.Remove = function(s) s.removed = true end
	e.EmitSound = function() end
	return e
end
ents = { Create = function(cls) if cls == "tif_heli" then return make_ent() end return nil end }

load("lua/tif/air/sh_air.lua")
load("lua/tif/air/sv_air.lua")
local Air = TIF.Air

-- Fly one helicopter to the end; record the phases.
local function fly(opts, maxT)
	HOOKS = {}
	NOW = 0
	slopeOff, descZ = nil, nil
	local heli, res = Air.Call(opts)
	if not heli then return nil, res end
	local phases, last = {}, nil
	local minGround = math.huge
	local maxPitch, maxRoll = 0, 0
	local holdPos
	local t0 = {}
	while NOW < (maxT or 240) and not heli.removed do
		NOW = NOW + 0.015
		heli:Think()
		if heli.phase ~= last then
			phases[#phases + 1] = heli.phase
			t0[heli.phase] = NOW
			last = heli.phase
		end
		if heli.phase == "hold" then holdPos = heli.p end
		-- On the slope: how far off the line (height for the distance left) it flies.
		local r = heli.route
		if heli.phase == "approach" and r and r.glideD then
			local top = r.hub.z + (r.settle or 0)
			local d = (heli.p - r.hub):Length2D()
			local u = math.Clamp(d / r.glideD, 0, 1)
			local zt = top + (r.cruiseZ - top) * (u * u * (3 - 2 * u))
			if math.abs(heli.p.z - zt) > (slopeOff or 0) then
				slopeOff = math.abs(heli.p.z - zt)
				slopeAt = string.format("at %.0f of %.0f left, z %.0f vs %.0f, speed %.0f, vz %.0f", d, r.glideD, heli.p.z, zt,
					heli.v:Length2D(), heli.v.z)
			end
		end
		if heli.phase == "descend" and not descZ then descZ = heli.p.z - r.hub.z end
		if not heli.removed then
			minGround = math.min(minGround, heli.p.z)
			maxPitch = math.max(maxPitch, math.abs(heli.pitch))
			maxRoll = math.max(maxRoll, math.abs(heli.roll))
		end
	end
	return { heli = heli, mode = res, phases = table.concat(phases, ">"), t = NOW, minZ = minGround, pitch = maxPitch,
		roll = maxRoll, hold = holdPos, t0 = t0, hooks = table.concat(HOOKS, ","), slopeOff = slopeOff, descZ = descZ }
end

-- 1. Open field: land.
local r, why = fly({ pos = Vector(0, 0, 0), mode = "auto", fromYaw = 0 })
check(r ~= nil, "open field: helicopter sent", why or (r and r.mode))
if r then
	check(r.mode == "land", "open field: lands", r.mode)
	check(r.phases == "inbound>approach>descend>hold>climb>depart", "open field: phases", r.phases)
	check(r.heli.removed, "open field: leaves and is removed", string.format("t=%.0fs", r.t))
	check(r.hold and math.abs(r.hold.z - 163.3) < 8, "open field: hub on landing height", r.hold and string.format("hub z %.1f", r.hold.z))
	check(r.hold and r.hold:Length2D() < 30, "open field: on the LZ", r.hold and string.format("%.0f off", r.hold:Length2D()))
	check(r.minZ > 150, "open field: never below landed height", string.format("min hub z %.0f", r.minZ))
	check(r.pitch <= 16.1 and r.roll <= 22.1, "open field: attitude limits", string.format("pitch %.1f roll %.1f", r.pitch, r.roll))
	check(r.hooks:find("TIF_HeliArrived") ~= nil and r.hooks:find("TIF_HeliLeaving") ~= nil, "open field: hooks", r.hooks)
	local rt = r.heli.route
	check(rt.glideAng == 12, "open field: comes in down a 12 deg slope", tostring(rt.glideAng))
	check(r.slopeOff and r.slopeOff < 120, "open field: stays near the slope on the way in",
		r.slopeOff and string.format("max %.0f off the line %s", r.slopeOff, slopeAt or ""))
	check(r.descZ and r.descZ < 130, "open field: arrives low over the spot (only a short settle left)",
		r.descZ and string.format("%.0f above the landed height", r.descZ))
	local inbound = (r.t0.approach or 0)
	print(string.format("       timing: approach at %.1fs, descend %.1fs, hold %.1fs, climb %.1fs, depart %.1fs, gone %.1fs",
		r.t0.approach or -1, r.t0.descend or -1, r.t0.hold or -1, r.t0.climb or -1, r.t0.depart or -1, r.t))
end

-- 2. Rope: a 300-high block in the middle of the LZ.
WORLD.boxes = { { lo = Vector(-100, -100, 0), hi = Vector(100, 100, 300) } }
local lz = Air.CheckLZ(Vector(150, 0, 0), "blackhawk", "auto")
check(lz and lz.mode == "rope", "cluttered LZ: hover instead of land", lz and lz.mode)
check(lz and lz.hubZ >= 430, "cluttered LZ: hover hub clears the block", lz and string.format("hub %.0f", lz.hubZ))
r, why = fly({ pos = Vector(150, 0, 0), mode = "auto", fromYaw = 90 })
check(r and r.phases == "inbound>approach>descend>hold>climb>depart", "cluttered LZ: phases", r and r.phases or why)
check(r and r.hold and math.abs(r.hold.z - lz.hubZ) < 20, "cluttered LZ: hovers at the hub height", r and r.hold and string.format("%.0f vs %.0f", r.hold.z, lz.hubZ))

-- 3. Land refused under a low ceiling; flyby works.
WORLD.boxes = {}
WORLD.sky = 400
local x, w = Air.CheckLZ(Vector(0, 0, 0), "blackhawk", "land")
check(x == nil, "low sky: no landing", w)
WORLD.sky = 4000
r, why = fly({ pos = Vector(0, 0, 0), mode = "flyby", fromYaw = 180 })
check(r and r.phases == "inbound>depart", "flyby: passes over and leaves", r and r.phases or why)

-- 4. Walls: only one clear way in (a corridor along +x).
WORLD.boxes = { { lo = Vector(-20000, 600, 0), hi = Vector(20000, 900, 5000) }, { lo = Vector(-20000, -900, 0), hi = Vector(20000, -600, 5000) },
	{ lo = Vector(-2500, -900, 0), hi = Vector(-2200, 900, 5000) } }
local route = Air.PlanRoute(Air.CheckLZ(Vector(0, 0, 0), "blackhawk", "rope") or {}, Air.Type("blackhawk"), { fromYaw = 90 })
check(route and route.entry.x > 1000 and math.abs(route.entry.y) < 50, "corridor: comes in along the open way", route and tostring(route.entry))
WORLD.boxes = {}

-- 5. Held until released.
r = nil
NOW = 0
local heli = Air.Call({ pos = Vector(0, 0, 0), mode = "land", holdUntilRelease = true, fromYaw = 45 })
for _ = 1, 8000 do NOW = NOW + 0.015 heli:Think() end
check(heli.phase == "hold", "hold until release: still waiting at 120 s", heli.phase)
heli:Release()
for _ = 1, 8000 do NOW = NOW + 0.015 if not heli.removed then heli:Think() end end
check(heli.removed, "hold until release: leaves after Release()")

-- 6. Shot down mid-flight.
NOW = 0
heli = Air.Call({ pos = Vector(0, 0, 0), mode = "land", fromYaw = 0 })
for _ = 1, 300 do NOW = NOW + 0.015 heli:Think() end
heli:Crash(nil)
check(heli.crashing and heli:GetDying(), "crash: goes down")
for _ = 1, 1000 do NOW = NOW + 0.015 if not heli.removed then heli:Think() end end
check(heli.removed and heli.exploded, "crash: explodes within 14 s even with no collision")

-- 7. Slope blocked: a tall block on the way in makes it steeper; a wall right beside the LZ on every side, straight down.
WORLD.boxes = { { lo = Vector(-2600, -500, 0), hi = Vector(-2300, 500, 600) } } -- under a 12 deg slope coming from -x
local lz7 = Air.CheckLZ(Vector(0, 0, 0), "blackhawk", "land")
local rt7 = Air.PlanRoute(lz7, Air.Type("blackhawk"), { fromYaw = 180 })
check(rt7 and rt7.glideAng and rt7.glideAng > 12, "slope blocked: steeper slope instead", rt7 and tostring(rt7.glideAng))
WORLD.boxes = {}

-- 8. Out along the longest way to the edge of the map: walls 6000 out everywhere but +y.
WORLD.boxes = { { lo = Vector(6000, -40000, 0), hi = Vector(6300, 40000, 9000) }, { lo = Vector(-6300, -40000, 0), hi = Vector(-6000, 40000, 9000) },
	{ lo = Vector(-40000, -6300, 0), hi = Vector(40000, -6000, 9000) } }
local lz8 = Air.CheckLZ(Vector(0, 0, 0), "blackhawk", "land")
local rt8 = Air.PlanRoute(lz8, Air.Type("blackhawk"), { fromYaw = 0 })
check(rt8 and rt8.exit.y > 20000 and math.abs(rt8.exit.x) < 2000, "out: leaves along the longest way, to the edge",
	rt8 and tostring(rt8.exit))
WORLD.boxes = {}

print(string.format("Summary: %d passed, %d failed", passes, fails))
