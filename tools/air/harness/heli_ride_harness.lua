-- Offline: a Black Hawk flies a squad in, they ride on its tags, get out with the real clip data and TIF's real
-- action code, and are handed back moving; the helicopter leaves once it's empty. Run via heli_ride_harness.py.
local TIFDIR, ADDONS, TAGS = ...
local fails, passes = 0, 0
local function check(ok, label, detail)
	if ok then passes = passes + 1 print("[PASS] " .. label .. (detail and ("  -- " .. detail) or ""))
	else fails = fails + 1 print("[FAIL] " .. label .. (detail and ("  -- " .. detail) or "")) end
end

-- Vector / Angle ------------------------------------------------------------------------
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
vector_origin = Vector()
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
function V:Rotate(a)
	local r = math.rad(a.y)
	local c, s = math.cos(r), math.sin(r)
	self.x, self.y = self.x * c - self.y * s, self.x * s + self.y * c
end
function V:Angle()
	return Angle(-math.deg(math.atan2(self.z, math.sqrt(self.x ^ 2 + self.y ^ 2))), math.deg(math.atan2(self.y, self.x)), 0)
end
local A = {}
A.__index = A
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, A) end
function A:Forward()
	local p, y = math.rad(self.p), math.rad(self.y)
	return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function A:Right() local y = math.rad(self.y) return Vector(math.sin(y), -math.cos(y), 0) end
function Lerp(t, a, b) return a + (b - a) * t end
function LerpVector(t, a, b) return a + (b - a) * t end
function math.Clamp(v, a, b) return math.min(math.max(v, a), b) end
function math.Approach(c, t, d) if c < t then return math.min(c + d, t) end return math.max(c - d, t) end
function math.AngleDifference(a, b) return (a - b + 180) % 360 - 180 end
function math.Rand(a, b) return a + (b - a) * math.random() end
function isvector(v) return getmetatable(v) == V end
function istable(t) return type(t) == "table" end
function isstring(s) return type(s) == "string" end
function isfunction(f) return type(f) == "function" end
-- (yaw only: enough for the harness)
function WorldToLocal(pos, ang, opos, oang)
	local d = pos - opos
	d:Rotate(Angle(0, -oang.y, 0))
	return d, Angle(0, ang.y - oang.y, 0)
end

-- World: flat ground at 0, sky at 6000 ---------------------------------------------------
WORLD = { sky = 6000, ground = 0, boxes = {} }
local function sweep(start, endpos, mins, maxs)
	local n = 300
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
			if p.z >= WORLD.sky then return { Hit = true, HitSky = true, HitPos = Vector(c.x, c.y, WORLD.sky - math.max(0, o.z)), Fraction = t, HitNormal = Vector(0, 0, -1), StartSolid = i == 0 } end
			if p.z <= WORLD.ground then return { Hit = true, HitPos = Vector(c.x, c.y, o.z < 0 and WORLD.ground - o.z or WORLD.ground), Fraction = t, HitNormal = Vector(0, 0, 1), StartSolid = i == 0 } end
		end
	end
	return { Hit = false, HitPos = endpos, Fraction = 1, HitNormal = Vector(0, 0, 1) }
end
util = {
	TraceLine = function(t) return sweep(t.start, t.endpos) end,
	TraceHull = function(t) return sweep(t.start, t.endpos, t.mins, t.maxs) end,
	IsValidModel = function() return true end, BlastDamage = function() end, Effect = function() end,
}
MASK_SOLID, MASK_SOLID_BRUSHONLY, MASK_NPCSOLID_BRUSHONLY = 1, 2, 3
SOLID_VPHYSICS, MOVETYPE_VPHYSICS, MOVETYPE_NONE, MOVETYPE_CUSTOM, DMG_BLAST, FCVAR_ARCHIVE = 6, 6, 0, 11, 64, 128
COLLISION_GROUP_DEBRIS, COLLISION_GROUP_NPC = 1, 9
SERVER, CLIENT = true, false
NOW = 0
function CurTime() return NOW end
engine = { TickInterval = function() return 0.015 end }
function AddCSLuaFile() end
function CreateConVar(n, d) return { GetFloat = function() return tonumber(d) end, GetBool = function() return d ~= "0" end } end
function GetConVar() return { GetFloat = function() return 1 end } end
local HOOKS = {}
FIRED = {}
hook = {
	Add = function(name, id, fn) HOOKS[name] = HOOKS[name] or {} HOOKS[name][id] = fn end,
	Run = function(name, ...) FIRED[#FIRED + 1] = name for _, fn in pairs(HOOKS[name] or {}) do fn(...) end end,
}
local TIMERS = {}
timer = { Create = function(name, d, r, fn) TIMERS[name] = { d = d, fn = fn, next = 0 } end, Simple = function(d, fn) fn() end }
concommand = { Add = function() end }
NULL = {}
-- (rawget: stub objects answer any missing method with a function, which would read as "removed")
function IsValid(e) return e ~= nil and e ~= NULL and type(e) == "table" and not rawget(e, "removed") end
function SafeRemoveEntityDelayed(e) e.removed = true end
function EffectData() return setmetatable({}, { __index = function() return function() end end }) end
function DamageInfo()
	local d = { dmg = 0 }
	return setmetatable(d, { __index = function(t, k)
		if k == "SetDamage" then return function(s, v) s.dmg = v end end
		if k == "GetDamage" then return function(s) return s.dmg end end
		return function() end
	end })
end
game = { GetWorld = function() return {} end }

TIF = { Log = function() end, Warn = function(...) print("WARN", ...) end, Error = function(...) print("ERR", ...) end,
	CanUseDev = function() return true end }

-- Clip data (the real build) and TIF's real action code ------------------------------------------
local CLIPS
TIFG = { RegisterClips = function(pack, t) CLIPS = t end }
assert(loadfile(ADDONS .. "tif_mw_anims/lua/tif/gta/clips/mw_male.lua"))()
assert(loadfile(ADDONS .. "tif_air/lua/autorun/tif_air_infil.lua"))()
local function curve_at(clip, frame, axis)
	local c = clip.curve
	local n = #c / 3
	if n == 0 then return 0 end
	local fi = frame / 3
	if fi <= 0 then return c[axis] end
	if fi >= n - 1 then return c[(n - 1) * 3 + axis] end
	local i = math.floor(fi)
	local a = c[i * 3 + axis]
	return a + (c[i * 3 + 3 + axis] - a) * (fi - i)
end
TIF.GTG = { DEFAULT_HOST = "mw_male", Clip = function(name) return CLIPS[name] end, ClipCurve = curve_at }
TIF.Factions = { pmc = { host = "mw_male" } }
local function load(rel) assert(loadfile(TIFDIR .. rel))() end
load("lua/tif/npc/sv_action.lua")

-- Soldiers (stubs) ------------------------------------------------------------------------------
local SOLDIERS = {}
local ORDERS = {}
local GOALS = {}
local function make_npc(pos)
	local e = { pos = Vector(pos.x, pos.y, pos.z), yaw = 0, hp = 100, nw = {}, tifFire = {}, tifMove = {}, tifHostId = "mw_male",
		tifHomeHost = "mw_male", mt = MOVETYPE_CUSTOM, cg = COLLISION_GROUP_NPC }
	e.loco = { SetVelocity = function(_, v) e.vel = v end, ClearStuck = function() end }
	function e:GetTIFFaction() return "pmc" end
	function e:SetPos(p) self.pos = Vector(p.x, p.y, p.z) end
	function e:GetPos()
		if IsValid(self.parent) then return self.parent:LocalToWorld(self.lp or Vector()) end
		return self.pos
	end
	function e:SetAngles(a) self.yaw = a.y end
	function e:GetAngles()
		if IsValid(self.parent) then return Angle(0, self.parent:GetAngles().y + (self.lyaw or 0), 0) end
		return Angle(0, self.yaw, 0)
	end
	function e:SetParent(p) self.parent = p end
	function e:GetParent() return self.parent end
	function e:SetLocalPos(p) self.lp = Vector(p.x, p.y, p.z) end
	function e:GetLocalPos() return self.lp or Vector() end
	function e:SetLocalAngles(a) self.lyaw = a.y end
	function e:SetMoveType(m) self.mt = m end
	function e:GetMoveType() return self.mt end
	function e:SetCollisionGroup(g) self.cg = g end
	function e:GetCollisionGroup() return self.cg end
	function e:SetNW2String(k, v) self.nw[k] = v end
	function e:SetNW2Bool(k, v) self.nw[k] = v end
	function e:SetTransmitWithParent(v) self.twp = v end
	function e:GetForward() return Angle(0, self.yaw, 0):Forward() end
	function e:SetNW2Float(k, v) self.nw[k] = v end
	function e:Health() return self.hp end
	function e:TakeDamageInfo(d) self.hp = self.hp - d:GetDamage() if self.hp <= 0 then self.tifDead = true end end
	function e:Remove() self.removed = true end
	SOLDIERS[#SOLDIERS + 1] = e
	return e
end
TIF.SquadMix = { "leader", "rifleman", "support", "rifleman", "assault", "marksman", "rpg", "assault" }
TIF.Squad = { SetOrder = function(sq, kind, pos) ORDERS[#ORDERS + 1] = { sq = sq, kind = kind, pos = pos } end,
	Members = function(sq) return sq.members end }
SPAWN_AT = {}
TIF.API = { SpawnSquad = function(faction, pos, arch, opts)
	local sq = { members = {} }
	for i = 1, #arch do
		local p = opts and opts.points and opts.points[i] or pos
		SPAWN_AT[#SPAWN_AT + 1] = p
		local n = make_npc(p) n.tifSquad = sq sq.members[i] = n
	end
	return sq, sq.members
end }
TIF.Move = { Stop = function() end, Snap = function(p) return p end,
	SetGoal = function(npc, pos, speed, tag) GOALS[npc] = { pos = pos, speed = speed, tag = tag, t = NOW } end }
TIF.CoverBehave = { In = function() return false end }
TIF.FreeSpot = function(p) return p end

-- Helicopter (the real entity) ----------------------------------------------------------------
ENT = {}
load("lua/entities/tif_heli.lua")
local HELI = ENT
HELI.__index = HELI
local function make_heli()
	local e = setmetatable({ nw = {}, pos = Vector(), ang = Angle(), hp = 0 }, HELI)
	e.SetHeliType = function(s, v) s.nw.type = v end
	e.SetNW2String = function(s, k, v) s.nw[k] = v end
	e.GetHeliType = function(s) return s.nw.type end
	for _, k in ipairs({ "Rotor", "DoorsOpen", "Dying", "Ropes" }) do
		e["Set" .. k] = function(s, v) s.nw[k] = v if k == "Ropes" and v then s.ropesSeen = true end end
		e["Get" .. k] = function(s) return s.nw[k] end
	end
	for _, k in ipairs({ "SetModel", "PhysicsInit", "SetMoveType", "SetSolid", "MakePhysicsObjectAShadow", "SetMaxHealth",
		"Activate", "NextThink", "EmitSound" }) do e[k] = function() end end
	e.phys = setmetatable({ UpdateShadow = function(_, pos, ang) e.pos, e.ang = pos, ang end, GetMass = function() return 5000 end,
		GetAngleVelocity = function() return Vector() end }, { __index = function() return function() end end })
	e.GetPhysicsObject = function(s) return s.phys end
	e.SetHealth = function(s, v) s.hp = v end
	e.Health = function(s) return s.hp end
	e.GetPos = function(s) return s.pos end
	e.SetPos = function(s, p) s.pos = p end
	e.GetAngles = function(s) return s.ang end
	e.SetAngles = function(s, a) s.ang = a end
	e.Spawn = function(s) s:Initialize() end
	e.Remove = function(s) s.removed = true end
	-- (attachments = the type's tags, from its model's skeleton)
	e.LookupAttachment = function(s, name)
		s.att = s.att or {}
		for i, n in ipairs(s.att) do if n == name then return i end end
		if TAGS[s.nw.type] and TAGS[s.nw.type][name] then s.att[#s.att + 1] = name return #s.att end
		return 0
	end
	e.GetAttachment = function(s, id)
		local t = TAGS[s.nw.type][s.att[id]]
		if not t then return nil end
		return { Pos = s:LocalToWorld(Vector(t[1], t[2], t[3])), Ang = Angle(0, s.ang.y + t[4], 0) }
	end
	e.LocalToWorld = function(s, v) local w = Vector(v.x, v.y, v.z) w:Rotate(Angle(0, s.ang.y, 0)) return s.pos + w end
	e.LocalToWorldAngles = function(s, a) return Angle(0, s.ang.y + a.y, 0) end
	return e
end
ents = { Create = function(cls) if cls == "tif_heli" then return make_heli() end end }

load("lua/tif/air/sh_air.lua")
load("lua/tif/air/sv_air.lua")
load("lua/tif/air/sv_air_ride.lua")
local Air, Ride = TIF.Air, TIF.AirRide

-- One drop, flown to the end -------------------------------------------------------------------------
local function drop(mode, yaw, typeId, set, style, count)
	SOLDIERS, ORDERS, GOALS, FIRED = {}, {}, {}, {}
	NOW = 0
	local heli, res = Air.Call({ type = typeId, pos = Vector(0, 0, 0), mode = mode, fromYaw = yaw,
		passengers = { faction = "pmc", set = set, style = style, count = count } })
	if not heli then return nil, res end
	-- (0.30.1) passengers are made at the helicopter, never on the LZ under the player's crosshair
	local far = 0
	for _, p in ipairs(SPAWN_AT) do far = math.max(far, (p - heli:GetPos()):Length()) end
	SPAWN_AT = {}
	check(far < 1, typeId .. " " .. tostring(set) .. ": passengers spawned at the helicopter", string.format("%.0f", far))
	local riders = {}
	for i, n in ipairs(heli.tifRiders or {}) do riders[i] = n end
	local out = { heli = heli, riders = riders, mode = res, maxSeatDrift = 0, released = {}, holdAt = nil, gone = nil }
	local seatDist = {}
	for i, n in ipairs(riders) do seatDist[i] = (n:GetPos() - heli:GetPos()):Length() end
	local nextBrain, nextTimer = 0, 0
	out.doorsShut = false
	while NOW < 200 and not heli.removed do
		NOW = NOW + 0.015
		heli:Think()
		if not heli:GetDoorsOpen() then out.doorsShut = true end
		if heli.phase == "hold" and not out.holdAt then out.holdAt = NOW end
		for i, n in ipairs(riders) do
			TIF.Action.Tick(n, NOW)
			if n.tifHeli and n.tifHeli.state == "ride" and not heli.removed then
				out.maxSeatDrift = math.max(out.maxSeatDrift, math.abs((n:GetPos() - heli:GetPos()):Length() - seatDist[i]))
			end
		end
		if NOW >= nextBrain then
			nextBrain = NOW + 0.1
			for i, n in ipairs(riders) do
				local was = n.tifHeli ~= nil
				if was then Ride.Think(n, NOW) end
				local H = n.tifHeli
				if was and H and H.state == "out" then out.clip = out.clip or {} out.clip[i] = H.clip end
				-- handed back: off the helicopter for good, or holding the LZ crouched
				if was and not out.released[i] and (not H or H.state == "hold") then
					out.released[i] = { t = NOW, pos = n:GetPos(), vel = n.vel, mt = n.mt, cg = n.cg, hold = H ~= nil }
				end
				if H and H.state == "hold" then
					out.holders = out.holders or {}
					out.holders[i] = true
					if n.tifStance ~= 1 or not n.tifFace then out.badHold = true end
					if heli.phase ~= "hold" and heli.phase ~= "climb" then out.heldLate = true end
				end
				if out.holders and out.holders[i] and not H and not out.holdEnd then out.holdEnd = heli.phase end
			end
		end
		if NOW >= nextTimer then
			nextTimer = NOW + 0.25
			for _, t in pairs(TIMERS) do t.fn() end
		end
	end
	out.gone = heli.removed and NOW
	return out
end

-- Every drop of every helicopter ------------------------------------------------------------------------
-- clear: where a man counts as clear of the airframe (helicopter frame): |y| past the side, or behind / ahead of it.
local CLEAR = {
	blackhawk = { side = 60, rear = -130, nose = 200 },  -- (cabin ~55 wide a side, cockpit ~47)
	littlebird = { side = 58, rear = -45, nose = 100 },  -- (benches out to ~55)
	mi8 = { side = 60, rear = -175, nose = 225 },        -- (rear men go out the open back)
	heavy = { side = 75, rear = -300, nose = 290 },      -- (front doors at 187, ramp from -240)
}
local CASES = {
	{ "blackhawk", "land", nil, nil, nil, 6, hub = 163.3, within = 6.5, doors = true },
	{ "blackhawk", "rope", "rappel", nil, nil, 8, hub = 920, within = 11.5, ropes = true },
	{ "blackhawk", "rope", "fastrope", nil, nil, 6, hub = "set", within = 16, ropes = true }, -- (the campaign clips: walk to the door, hook up, 440 slide)
	{ "blackhawk", "rope", "mpleft", nil, nil, 3, hub = "set", within = 10, ropes = true },
	{ "blackhawk", "rope", "mpright", nil, nil, 3, hub = "set", within = 11, ropes = true },
	{ "littlebird", "land", "land", nil, nil, 6, hub = 113.2, within = 6.5 },
	{ "littlebird", "land", "bench", "run", nil, 6, hub = 113.2, within = 4.5 },
	{ "littlebird", "land", "bench", "ready", nil, 6, hub = 113.2, within = 4.5 },
	{ "littlebird", "land", "bench", "patrol", nil, 6, hub = 113.2, within = 4.5 },
	{ "mi8", "land", nil, nil, nil, 12, hub = 165.2, within = 8 },
	{ "mi8", "land", nil, nil, 13, 13, hub = 165.2, within = 8 },
	{ "mi8", "rope", nil, nil, nil, 12, hub = 690, within = 19.5, ropes = true },
	{ "heavy", "land", nil, nil, nil, 12, hub = 249.4, within = 9 },
	{ "heavy", "rope", nil, nil, nil, 12, hub = "set", within = 20, ropes = true },
}
for k, c in ipairs(CASES) do
	local typeId, mode, set, style, count, want = c[1], c[2], c[3], c[4], c[5], c[6]
	local tag = string.format("%s %s%s%s%s:", typeId, mode, set and (" " .. set) or "", style and (" " .. style) or "",
		count and (" x" .. count) or "")
	local r, why = drop(mode, (k * 47) % 360, typeId, set, style, count)
	check(r ~= nil, tag .. " sent", why or (r and r.mode))
	if r then
		local route = r.heli.route
		check(#r.riders == want, tag .. " " .. want .. " aboard", tostring(#r.riders))
		local wantHub = c.hub
		if wantHub == "set" then wantHub = TIF_AIR_INFIL[typeId][route.setId].hub end
		check(math.abs(route.hub.z - wantHub) < 1, tag .. " hub at the clips' height", string.format("hub %.1f (set %s)", route.hub.z, tostring(wantHub)))
		check(r.maxSeatDrift < 0.5, tag .. " riders stay on their seats in flight", string.format("max drift %.2f", r.maxSeatDrift))
		if c.doors then check(not r.doorsShut, tag .. " doors open the whole flight") end
		if c.ropes then check(r.heli.ropesSeen and not r.heli:GetRopes(), tag .. " ropes out for the drop, gone after") end
		local n, maxZ, lastT, minV, notClear = 0, 0, 0, math.huge, 0
		local L = CLEAR[typeId]
		for i, rel in pairs(r.released) do
			n = n + 1
			maxZ = math.max(maxZ, math.abs(rel.pos.z))
			lastT = math.max(lastT, rel.t)
			minV = math.min(minV, rel.vel and rel.vel:Length() or 0)
			local lp = rel.pos - route.hub
			lp:Rotate(Angle(0, -route.heading, 0))
			-- (rope drops land under a hover 20 m up: the airframe isn't in the way)
			if mode ~= "rope" and not (math.abs(lp.y) > L.side or lp.x < L.rear or lp.x > L.nose) then
				notClear = notClear + 1
				print(string.format("       not clear: %s at (%.0f %.0f)", r.clip and r.clip[i] or "?", lp.x, lp.y))
			end
		end
		check(n == want, tag .. " all handed back", tostring(n))
		check(maxZ < 3, tag .. " on the ground when handed back", string.format("max |z| %.1f", maxZ))
		check(notClear == 0, tag .. " handed back clear of the airframe", notClear .. " not clear")
		check(r.holdAt and lastT - r.holdAt < c.within, tag .. " everyone out within " .. c.within .. " s",
			r.holdAt and string.format("%.1f s, slowest hand-back %.0f u/s", lastT - r.holdAt, minV))
		local goals = 0
		for _, g in pairs(GOALS) do if g.speed == "run" then goals = goals + 1 end end
		check(goals == want, tag .. " each one runs on straight away", tostring(goals))
		if style then
			local ok = true
			for _, cl in pairs(r.clip or {}) do if not string.find(cl, "_" .. style, 1, true) then ok = false end end
			check(ok, tag .. " every man uses the " .. style .. " exit")
		end
		local clean = true
		for _, rel in pairs(r.released) do if rel.mt ~= MOVETYPE_CUSTOM or rel.cg ~= COLLISION_GROUP_NPC then clean = false end end
		check(clean, tag .. " moving and colliding normally again")
		local shadows, twp = true, true
		for _, n in ipairs(r.riders) do
			if n.nw.tif_noshadow ~= false then shadows = false end
			if n.twp ~= false then twp = false end
		end
		check(shadows and twp, tag .. " shadows back on and sent normally again once off")
		if r.holders then
			local nh = 0
			for _ in pairs(r.holders) do nh = nh + 1 end
			check(not r.badHold, tag .. " " .. nh .. " landed crouched: hold down, gun up, facing out")
			check(not r.heldLate and r.holdEnd ~= nil, tag .. " ...until the helicopter lifts away, then move on",
				tostring(r.holdEnd))
		end
		check(r.gone ~= nil, tag .. " helicopter leaves once empty", r.gone and string.format("gone at %.0f s", r.gone))
	end
end
local x, w = drop("rope", 0, "littlebird")
check(x == nil, "littlebird rope: refused (it only lands)", w)
-- Styles chosen by the situation (no style given): calm drop, mostly patrol / run.
do
	local seen = {}
	for _ = 1, 6 do
		local r = drop("land", 0, "littlebird", "bench")
		for _, cl in pairs(r and r.clip or {}) do seen[string.match(cl, "_(%a+)$")] = true end
	end
	check(seen.patrol and seen.run, "littlebird bench: calm drops mix patrol and run exits")
end

-- 3. Shot down with men aboard -----------------------------------------------------------------------
SOLDIERS, FIRED = {}, {}
NOW = 0
local heli = Air.Call({ pos = Vector(0, 0, 0), mode = "land", fromYaw = 0, passengers = { faction = "pmc" } })
for _ = 1, 200 do NOW = NOW + 0.015 heli:Think() end
heli:Crash(nil)
local dead = 0
for _, n in ipairs(heli.tifRiders) do if n.tifDead and not n.tifHeli and n.parent == nil then dead = dead + 1 end end
check(dead == 6, "shot down: the men aboard die with it", tostring(dead))

print(string.format("Summary: %d passed, %d failed", passes, fails))
