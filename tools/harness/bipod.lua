-- Offline run of tactics/sv_trans_mw.lua + sv_search_mw.lua with real clip data, mock path and box world.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:Length2DSqr() return self.x ^ 2 + self.y ^ 2 end
function V:DistToSqr(o) return (self - o):Length() ^ 2 end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Rand = function(a, b) return (a + b) / 2 end
math.AngleDifference = function(a, b) return (a - b + 180) % 360 - 180 end
local rnd = 0.9
math.random = function(a, b) if a then return a end return rnd end
MASK_SOLID = 1

-- box world (as in smart.lua)
local function ent(t)
	t.IsNPC = function() return t.npc == true end
	t.IsNextBot = function() return t.npc == true end
	t.IsPlayer = function() return false end
	return t
end
local WORLD = ent({})
local boxes = {}
local function box(mins, maxs) boxes[#boxes + 1] = { mins = mins, maxs = maxs, ent = WORLD } end
local function slab(a, b, lo, hi)
	local d = b - a
	if math.abs(d) < 1e-9 then if a < lo or a > hi then return nil end return -math.huge, math.huge end
	local t1, t2 = (lo - a) / d, (hi - a) / d
	if t1 > t2 then t1, t2 = t2, t1 end
	return t1, t2
end
util = { TraceLine = function(t)
	local best, bn = 2, nil
	for _, bx in ipairs(boxes) do
		if not (type(t.filter) == "function" and not t.filter(bx.ent)) then
			local tin, tout, axis, ok = -math.huge, math.huge, nil, true
			for _, k in ipairs({ "x", "y", "z" }) do
				local a, b = slab(t.start[k], t.endpos[k], bx.mins[k], bx.maxs[k])
				if not a then ok = false break end
				if a > tin then tin, axis = a, k end
				if b < tout then tout = b end
			end
			if ok and tin <= tout and tin >= 0 and tin <= 1 and tin < best then
				best = tin
				bn = Vector(0, 0, 0)
				bn[axis] = (t.endpos[axis] - t.start[axis]) > 0 and -1 or 1
			end
		end
	end
	if best > 1 then return { Hit = false, HitPos = t.endpos, Fraction = 1 } end
	return { Hit = true, HitPos = t.start + (t.endpos - t.start) * best, HitNormal = bn, Fraction = best }
end }

TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local defs = { rifle = { hold = "carbine" }, pistol = { hold = "pistol" } }
TIF = {
	AWARE = { UNAWARE = 0, SUSPICIOUS = 1, ALERTED = 2, ENGAGED = 3, SEARCHING = 4 },
	Anim = { MODE_RELAXED = 0, MODE_AIM = 1, STANCE_STAND = 0, STANCE_CROUCH = 1 },
	GTG = { IsVB = function(id) return id == "mw_male" end, Clip = function(n, id) return id == "mw_male" and clips[n] or nil end,
		Clips = function(id) return id == "mw_male" and clips or nil end, WeaponDef = function(c) return defs[c] end },
	Move = { Stop = function() end },
}
local played, lastOpts = {}, nil
TIF.Action = {
	Play = function(npc, name, opts)
		local c = clips[name]
		if not c then return nil end
		played[#played + 1] = name
		lastOpts = opts or {}
		npc.tifAct = { name = name }
		return c.dur / ((opts and opts.rate) or 1)
	end,
	Loop = function(npc, name) played[#played + 1] = name npc.tifAct = { name = name, loop = true } return 1 end,
	Clear = function(npc) npc.tifAct = nil end,
}
assert(loadfile(ROOT .. "tif/tactics/sv_bipod_mw.lua"))()
local B = TIF.BipodMW
TIF.GTG.WeaponKind = function() return "lmg" end
local function world(h) boxes = {} box(Vector(-500, -500, -10), Vector(500, 500, 0)) if h then box(Vector(30, -60, 0), Vector(45, 60, h)) end end
local s = { pos = Vector(0, 0, 0), tifHomeHost = "mw_male", tifHostId = "mw_male", tifWep = { class = "m" } }
function s:GetPos() return self.pos end
s.IsNPC = function() return true end s.IsNextBot = s.IsNPC s.IsPlayer = function() return false end
for _, c in ipairs({ { 34, "crouch" }, { 45, "stand" }, { 54, "high" } }) do
	world(c[1])
	local f = B.Find(s, 0)
	check(f and f.set.name == c[2] and math.abs(f.pos.x - (30 - B.STANDOFF)) < 0.6, c[1] .. " high rest: " .. c[2] .. " bipod: " .. tostring(f and f.set.name))
end
world(80)
check(B.Find(s, 0) == nil, "a full wall: no bipod")
world(nil)
check(B.Find(s, 0) == nil, "open ground: no bipod")
world(45)
check(B.Find(s, 90) == nil, "rest not toward the target: no bipod")
print(string.format("passed %d, failed %d", pass, fail))