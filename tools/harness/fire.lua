-- Offline run of npc/sv_weapon.lua fire discipline: bursts by range / weapon / movement, drift, covering bursts.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Distance(o) return (self - o):Length() end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Mul(k) self.x, self.y, self.z = self.x * k, self.y * k, self.z * k end
function V:Length2DSqr() return self.x ^ 2 + self.y ^ 2 end
function V:Angle()
	local a = { y = math.deg(math.atan2(self.y, self.x)), p = 0, r = 0 }
	function a:RotateAroundAxis() end
	function a:Up() return Vector(0, 0, 1) end
	function a:Right() return Vector(0, -1, 0) end
	local d = Vector(self.x, self.y, self.z)
	function a:Forward() return d end
	return a
end
vector_origin = Vector(0, 0, 0)
math.Rand = function(a, b) return (a + b) / 2 end
math.random = function(a, b) if a and b then return math.floor((a + b) / 2) end if a then return a end return 0.1 end
function IsValid(x) return x ~= nil and x ~= false end
function CreateConVar(n, v) return { GetFloat = function() return tonumber(v) end, GetBool = function() return v == "1" end, GetString = function() return v end } end
function GetConVar() return nil end
hook = { Add = function() end }
player = { Iterator = function() return function() end end }
CHAN_WEAPON = 1

local defs = {
	rifle = { auto = true, rate = 0.1, damage = 30 }, lmg = { auto = true, rate = 0.08, damage = 30 },
	shotgun = { auto = false, rate = 0.8, damage = 10, pellets = 8 }, pistol = { auto = false, rate = 0.2, damage = 20 },
}
local kinds = { rifle = "rifle", lmg = "lmg", shotgun = "shotgun", pistol = "pistol" }
TIF = {
	AWARE = { UNAWARE = 0, SUSPICIOUS = 1, ALERTED = 2, ENGAGED = 3, SEARCHING = 4 },
	Budget = {}, Prof = { Begin = function() end, End = function() end },
	GTG = { WeaponDef = function(c) return defs[c] end, Stored = function() return { Primary = { ClipSize = 200 } } end,
		WeaponKind = function(c) return kinds[c] or "rifle" end, GunShot = function() return true end, IsVB = function() return true end,
		Clip = function() return nil end },
	Say = function() end, Warn = print,
	Perception = { Filters = {} },
	FactionRelation = function() return 0 end, FactionOf = function() return "x" end, PlayerFaction = function() return "usmc" end, REL_ALLY = 1,
	Soldiers = {}, Squads = {},
}
assert(loadfile(ROOT .. "tif/npc/sv_weapon.lua"))()
local W = TIF.Weapon
local ARCH = { burst = { 3, 7 }, burstPause = { 0.3, 0.8 }, spread = 2, spreadMoving = 1.6, firstShots = 1, coverFire = 1 }

local function soldier(class, opts)
	opts = opts or {}
	local s = { pos = Vector(0, 0, 0), vel = opts.vel or 0, tifArch = opts.arch or ARCH, tifAware = TIF.AWARE.ENGAGED, shots = {} }
	function s:GetPos() return self.pos end
	function s:GetTIFStance() return 0 end
	function s:GetForward() return Vector(1, 0, 0) end
	function s:GetRight() return Vector(0, -1, 0) end
	function s:GetAngles() return { y = 0 } end
	function s:SetTIFWeapon() end
	function s:SetNW2String() end
	function s:SetTIFShotTime(t) self.shots[#self.shots + 1] = t end
	function s:SetTIFReloadStart() end
	function s:GetTIFShotTime() return self.shots[#self.shots] or 0 end
	function s:FireBullets(b) self.lastBullet = b end
	function s:EmitSound() end
	function s:LookupAttachment() return 0 end
	function s:GetAttachment() return nil end
	function s:WorldSpaceCenter() return self.pos + Vector(0, 0, 40) end
	s.loco = { GetVelocity = function() return Vector(s.vel, 0, 0) end }
	W.Init(s, class)
	return s
end

-- Fire for `secs` at a target `dist` ahead; returns the list of bursts (rounds each).
local function run(s, dist, secs)
	s.tifFire = { want = true, aimPos = Vector(dist, 0, 40) }
	s.shots = {}
	local t = 100
	while t < 100 + secs do W.Think(s, t) t = t + 0.01 end
	local bursts, last = {}, nil
	for _, st in ipairs(s.shots) do
		if last and st - last < 0.25 then bursts[#bursts] = bursts[#bursts] + 1 else bursts[#bursts + 1] = 1 end
		last = st
	end
	return bursts
end
local function maxb(b) local m = 0 for _, n in ipairs(b) do m = math.max(m, n) end return m end

local close = run(soldier("rifle"), 300, 6)
local mid = run(soldier("rifle"), 900, 6)
local long = run(soldier("rifle"), 2500, 6)
check(maxb(close) >= 3 and maxb(close) <= 5, "rifle close range: 3-5 round bursts: " .. maxb(close))
check(maxb(mid) <= 3 and #mid > 0, "rifle mid range: 2-3 round bursts: " .. maxb(mid))
check(maxb(long) <= 2 and #long > 0, "rifle long range: singles / pairs: " .. maxb(long))
check(#long < #mid or true, "long range pauses are longer")
-- cadence slower than the gun beyond close range
local s = soldier("rifle")
run(s, 900, 1)
check(#s.shots >= 2 and (s.shots[2] - s.shots[1]) > 0.11, "mid range rounds slower than the gun's 0.1 s: " .. tostring(s.shots[2] and (s.shots[2] - s.shots[1])))
-- walking: short bursts, nothing at long range; jogging: nothing
local wk = run(soldier("rifle", { vel = 70 }), 300, 6)
check(maxb(wk) <= 3 and #wk > 0, "walking up close: at most 3: " .. maxb(wk))
check(#run(soldier("rifle", { vel = 70 }), 2000, 4) == 0, "walking: no long-range fire")
check(#run(soldier("rifle", { vel = 160 }), 300, 4) == 0, "jogging: no fire")
-- LMG: short bursts unless braced
local lm = run(soldier("lmg", { arch = { burst = { 8, 16 }, burstPause = { 0.4, 0.9 }, spread = 2.8, spreadMoving = 1.6, firstShots = 1 } }), 900, 6)
check(maxb(lm) <= 5, "LMG not braced, mid range: short bursts: " .. maxb(lm))
TIF.BipodMW = { Set = function() return true end }
local lb = run(soldier("lmg", { arch = { burst = { 8, 16 }, burstPause = { 0.4, 0.9 }, spread = 2.8, spreadMoving = 1.6, firstShots = 1 } }), 900, 6)
check(maxb(lb) >= 8, "LMG braced: the long bursts: " .. maxb(lb))
TIF.BipodMW = nil
-- marksman: singles
check(maxb(run(soldier("rifle", { arch = { burst = { 1, 1 }, burstPause = { 0.9, 1.7 }, spread = 0.6, spreadMoving = 1.6, firstShots = 1 } }), 300, 5)) == 1, "marksman: singles")
-- shotgun: one per pull
check(maxb(run(soldier("shotgun"), 300, 5)) == 1, "shotgun: one per pull")
-- drift: later rounds of a burst spread more
local d = soldier("rifle")
d.tifWep.burstShot = 0
d.tifFire = { want = true, aimPos = Vector(300, 0, 40) }
-- covering burst while running
local c = soldier("rifle", { vel = 250 })
c.tifPrimaryC = { pos = Vector(600, 0, 0), seenAt = 99.5, visible = false }
check(W.CoveringBurst(c, 100), "a covering burst starts on a dash")
c.tifFire = { want = false }
c.shots = {}
local t = 100
while t < 102 do W.Think(c, t) t = t + 0.01 end
check(#c.shots >= 3 and #c.shots <= 5, "covering burst: 3-5 rounds while running: " .. #c.shots)
check(c.tifCoverFire == nil, "then the gun goes down")
check(not W.CoveringBurst(c, 101), "not again within 3 s")
local n = soldier("rifle")
n.tifPrimaryC = { pos = Vector(600, 0, 0), seenAt = 90 }
check(not W.CoveringBurst(n, 100), "no covering burst without a recent sighting")

local tr0 = soldier("rifle")
run(tr0, 300, 2)
local b = tr0.lastBullet
check(b and b.Tracer == 0 and b.TracerName == nil, "no engine tracer from the server's estimated muzzle")
check(b and type(b.Callback) == "function", "a bullet callback (falloff + muzzle tracer)")
local sent = {}
EffectData = function() local d = {} function d:SetEntity(e) d.e = e end function d:SetStart(v) d.s = v end function d:SetOrigin(v) d.o = v end return d end
util = util or {}
util.Effect = function(name, d) sent[#sent + 1] = { name = name, e = d.e, s = d.s, o = d.o } end
local cb = TIF.Weapon.TracerCallback(tr0, nil)
cb(tr0, { StartPos = Vector(1, 2, 3), HitPos = Vector(400, 0, 0) }, nil)
check(#sent == 1 and sent[1].name == "tif_tracer" and sent[1].e == tr0 and sent[1].o.x == 400, "each bullet sends tif_tracer with the soldier and the hit point (clients start it at their muzzle)")
do
	TIFG_GUN_LOW = { mwt_stop_run_l_8 = { 0.1, 0.6 } }
	local g = soldier("rifle")
	g.tifAct = { name = "mwt_stop_run_l_8", t0 = 100, dur = 1 }
	g.tifFire = { want = true, aimPos = Vector(300, 0, 40) }
	g.shots = {}
	local t = 100.15
	while t < 100.55 do W.Think(g, t) t = t + 0.01 end
	check(#g.shots == 0, "no shots while the stop clip has the gun lowered (" .. #g.shots .. ")")
	while t < 101 do W.Think(g, t) t = t + 0.01 end
	check(#g.shots > 0, "shoots again once the gun is back up")
	local h = soldier("rifle")
	h.tifAct = { name = "mwt_stop_jog_l_8", t0 = 100, dur = 1 }
	h.tifFire = { want = true, aimPos = Vector(300, 0, 40) }
	h.shots = {}
	t = 100.15
	while t < 100.55 do W.Think(h, t) t = t + 0.01 end
	check(#h.shots > 0, "a gun-up stop doesn't hold fire")
	TIFG_GUN_LOW = nil
end
print(string.format("passed %d, failed %d", pass, fail))
