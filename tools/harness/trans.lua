math.Clamp = math.Clamp or function(v, a, b) return math.max(a, math.min(b, v)) end
CurTime = CurTime or function() return 0 end
istable = istable or function(v) return type(v) == "table" end
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
for _, f in ipairs({ "tif/tactics/sv_trans_mw.lua", "tif/tactics/sv_search_mw.lua" }) do
	assert(loadfile(ROOT .. f))()
end
local G = TIF.GTG
G.ClipCurve = G.ClipCurve or function(clip, frame, axis)
	local c = clip.curve
	local n = #c / 3
	local fi = frame / 3
	if fi <= 0 then return c[axis] end
	if fi >= n - 1 then return c[(n - 1) * 3 + axis] end
	local i = math.floor(fi)
	return c[i * 3 + axis] + (c[i * 3 + 3 + axis] - c[i * 3 + axis]) * (fi - i)
end
local T, S, AW = TIF.TransMW, TIF.SearchMW, TIF.AWARE
local function last() return played[#played] end

local function soldier(opts)
	opts = opts or {}
	local s = ent({ npc = true, tifHomeHost = "mw_male", tifHostId = "mw_male", pos = Vector(0, 0, 0), yaw = opts.yaw or 0,
		vel = opts.vel or Vector(0, 0, 0), tifMode = opts.mode or 1, stance = opts.stance or 0, tifAware = opts.aware or AW.UNAWARE,
		tifWep = { class = opts.wep or "rifle" } })
	function s:GetPos() return self.pos end
	function s:GetAngles() return Angle(0, self.yaw, 0) end
	function s:GetTIFStance() return self.stance end
	function s:GetNW2Bool(k, d) if self.nw and self.nw[k] ~= nil then return self.nw[k] end return d or false end
	s.loco = { GetVelocity = function() return s.vel end }
	s.tifPath = {
		segs = opts.segs or { Vector(300, 0, 0) },
		GetCurrentGoal = function(self) return { pos = self.segs[1] } end,
		FirstSegment = function(self) return { pos = self.segs[1] } end,
		LastSegment = function(self) return { pos = self.segs[#self.segs] } end,
	}
	return s
end

-- Turns
local a = soldier({ mode = 0 })
check(not T.Turn(a, 40), "small turn: no clip")
check(T.Turn(a, 90) and last() == "mwt_turn_calm_4", "calm 90 left: calm turn 4: " .. tostring(last()))
check(lastOpts.to and lastOpts.to.yaw == 90 and lastOpts.root, "ends exactly on the wanted yaw")
check(a.tifAct.trans == true, "marked as a transition")
a.tifAct = nil
a.tifMode, a.tifAware = 1, AW.ENGAGED
check(T.Turn(a, -135) and last() == "mwt_turn_stand_3" and lastOpts.rate == T.COMBAT_RATE, "fighting, 135 right: stand turn 3, faster: " .. tostring(last()))
a.tifAct = nil
check(T.Turn(a, 178) and last() == "mwt_turn_stand_2l", "about-face to the left: 2l: " .. tostring(last()))
a.tifAct = nil
check(T.Turn(a, -178) and last() == "mwt_turn_stand_2r", "about-face to the right: 2r: " .. tostring(last()))
a.tifAct = nil
a.tifWep.class = "pistol"
check(T.Turn(a, 45 + 20) and last() == "mwt_turn_pstl_7", "pistol: pistol turns: " .. tostring(last()))
a.tifAct, a.tifWep.class = nil, "rifle"
a.stance = 1
check(T.Turn(a, -90) and (last() == "mwt_turn_crouch_6" or last() == "mwt_turn_crouch_6v"), "crouched: crouch turn (MW19 or MW22 AI): " .. tostring(last()))
a.tifAct, a.stance = nil, 0
a.tifAware = AW.SUSPICIOUS
check(T.Turn(a, 90) and (last() == "mwt_turn_alert_4" or last() == "mwt_turn_alert_4v"), "suspicious: alert turn (MW19 or MW22 AI): " .. tostring(last()))
a.tifAct = nil
a.tifCov = {}
check(not T.Turn(a, 90), "not in cover")
a.tifCov = nil

-- Starts
local b = soldier({ mode = 0, segs = { Vector(0, 300, 0) } })
check(T.Start(b, { tag = "post", speed = "walk" }) and last() == "mwt_start_calm_4", "calm, path to the left: calm start 4: " .. tostring(last()))
b.tifAct = nil
b.tifPath.segs = { Vector(-300, -300, 0) }
b.tifAware = AW.SUSPICIOUS
check(T.Start(b, { tag = "investigate", speed = "alert" }) and last() == "mwt_start_alert_3", "alert, back-right: alert start 3: " .. tostring(last()))
b.tifAct = nil
b.tifMode = 1
b.tifPath.segs = { Vector(400, 0, 0) }
check(T.Start(b, { tag = "advance", speed = "tactical" }) and last() == "mwt_start_walk_8", "aiming, forward: strafe start 8: " .. tostring(last()))
b.tifAct = nil
b.tifPath.segs = { Vector(100, 0, 0), Vector(100, 300, 0) }
check(not T.Start(b, { tag = "advance", speed = "tactical" }), "corner closer than the clip travels: no start")
b.tifPath.segs = { Vector(400, 0, 0) }
check(not T.Start(b, { tag = "flee", speed = "run" }), "fleeing: no start")
b.vel = Vector(80, 0, 0)
check(not T.Start(b, { tag = "advance", speed = "tactical" }), "already moving: no start")

-- Stops
local c = soldier({ mode = 0, vel = Vector(60, 0, 0), segs = { Vector(30, 0, 0) } })
local m = { tag = "post", speed = "walk", goal = Vector(200, 0, 0) }
check(T.Stop(c, m) == nil, "far from the goal: no stop yet")
m.goal = Vector(30, 0, 0)
local d = T.Stop(c, m)
check(d and last():find("^mwt_stop_calm_[lr]_2$"), "calm, no facing wanted: the straight stop (2): " .. tostring(last()))
check(lastOpts.to and lastOpts.to.pos.x == 30, "warped onto the goal")
c.tifAct = nil
m.faceYaw = 90
T.Stop(c, m)
check(last():find("^mwt_stop_calm_[lr]_4$") and lastOpts.to.yaw == 90, "calm, post faces left: stop turning left (4): " .. tostring(last()))
c.tifAct = nil
c.tifMode = 1
c.tifPath.segs = { Vector(0, 30, 0) }
local m2 = { tag = "hold", speed = "tactical", goal = Vector(0, 30, 0) }
T.Stop(c, m2)
check(last():find("^mwt_stop_walk_[lr]_4$"), "strafing left: strafe stop 4: " .. tostring(last()))
c.tifAct = nil
c.tifPath.segs = { Vector(30, 0, 0), Vector(30, 100, 0) }
check(T.Stop(c, { tag = "hold", speed = "tactical", goal = Vector(30, 100, 0) }) == nil, "not on the last leg: no stop")
-- Halting short (Move.Stop at a post 80 out)
local e = soldier({ mode = 0, vel = Vector(60, 0, 0) })
check(T.StopHere(e, { tag = "post", speed = "walk", goal = Vector(80, 0, 0), faceYaw = 180 }) and last():find("^mwt_stop_calm_[lr]_8$"),
	"halting at a post facing back: the turning-round stop: " .. tostring(last()))
e.tifAct = nil
e.vel = Vector(5, 0, 0)
check(not T.StopHere(e, { tag = "post", speed = "walk", goal = Vector(80, 0, 0) }), "already still: no stop clip")

-- Search looks
local function world(list) boxes = {} box(Vector(-500, -500, -10), Vector(500, 500, 0)) for _, b in ipairs(list) do box(b[1], b[2]) end end
local f = soldier()
world({ { Vector(40, -30, 28), Vector(80, 30, 32) } })   -- a table top ahead (open beneath)
local kinds = {}
for _, x in ipairs(S.Find(f, 0)) do kinds[x.kind] = kinds[x.kind] or x.yaw end
check(kinds.under == 0, "table ahead: look under it")
world({ { Vector(40, -60, 0), Vector(50, 60, 45) } })    -- a low wall ahead
kinds = {}
for _, x in ipairs(S.Find(f, 0)) do kinds[x.kind] = kinds[x.kind] or x.yaw end
check(kinds.over == 0 and not kinds.under, "low wall ahead: look over it")
world({ { Vector(40, -40, 10), Vector(120, 40, 55) } })  -- a car body ahead, a gap under it
kinds = {}
for _, x in ipairs(S.Find(f, 0)) do kinds[x.kind] = kinds[x.kind] or x.yaw end
check(kinds.under_low == 0, "car ahead: look under it, low")
boxes = { { mins = Vector(-500, -500, -10), maxs = Vector(30, 500, 0), ent = WORLD } }  -- floor ends 30 ahead
kinds = {}
for _, x in ipairs(S.Find(f, 0)) do kinds[x.kind] = kinds[x.kind] or x.yaw end
check(kinds.down == 0, "a drop ahead: look down")
world({ { Vector(300, -200, 0), Vector(320, 200, 400) } })  -- a tall building ahead, open sky
kinds = {}
for _, x in ipairs(S.Find(f, 0)) do kinds[x.kind] = kinds[x.kind] or x.yaw end
check(kinds.high == 0, "tall building ahead under open sky: look up")
-- running one
world({ { Vector(40, -30, 28), Vector(80, 30, 32) } })
rnd = 0.01
local now = 10
check(S.Look(f, now, 0) and last() == "mwl_under_enter" and f.tifLook.kind == "under", "a look starts: " .. tostring(last()))
check(S.Busy(f, now + 0.1), "busy while looking")
now = f.tifLook.untilT + 0.01
S.Busy(f, now)
check(f.tifLook.phase == "loop" and last() == "mwl_under_loop", "enter -> loop")
now = f.tifLook.untilT + 0.01
S.Busy(f, now)
check(f.tifLook.phase == "exit" and last() == "mwl_under_exit", "loop -> exit")
now = f.tifLook.untilT + 0.01
check(not S.Busy(f, now) and f.tifLook == nil, "done")
f.tifAct = nil
S.Look(f, now, 0)
f.tifAware = AW.ENGAGED
check(not S.Busy(f, now + 0.1) and f.tifLook == nil and f.tifAct == nil, "a fight drops the look at once")

-- 0.31.1: strafe reversals (AI CQB trans clips), handed back to the path at code_move.
V.LengthSqr = function(self) return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
local function strafer(vel, seg, cqb)
	local r = soldier({ vel = vel, segs = { seg } })
	r.tifFace = Vector(500, 0, 0)
	function r:GetNW2Bool() return cqb == true end
	return r
end
local r = strafer(Vector(-80, 0, 0), Vector(300, 0, 0))
played = {}
check(T.Reverse(r, { goal = Vector(600, 0, 0), speed = "tactical" }, 10) and last() == "mwt_rev_walk_2_8", "backing up, path ahead: reversal 2 -> 8 (" .. tostring(last()) .. ")")
check(r.tifAct and r.tifAct.handU and r.tifAct.handU > 0.4 and r.tifAct.handU < 0.95, "hands back at code_move (" .. tostring(r.tifAct and r.tifAct.handU) .. ")")
r.tifAct = nil
check(not T.Reverse(r, { goal = Vector(600, 0, 0), speed = "tactical" }, 10.5), "not again within the cooldown")
local q = strafer(Vector(0, 80, 0), Vector(0, -300, 0), true)
check(T.Reverse(q, { goal = Vector(0, -600, 0), speed = "tactical" }, 10) and last() == "mwt_rev_cqbwalk_4_6", "CQB, strafing left then right: cqbwalk 4 -> 6 (" .. tostring(last()) .. ")")
local j = strafer(Vector(150, 0, 0), Vector(-300, 0, 0))
check(T.Reverse(j, { goal = Vector(-600, 0, 0), speed = "run" }, 10) and last() == "mwt_rev_jog_8_2", "jogging: jog 8 -> 2 (" .. tostring(last()) .. ")")
local s2 = strafer(Vector(80, 0, 0), Vector(0, 300, 0))
check(not T.Reverse(s2, { goal = Vector(0, 600, 0), speed = "tactical" }, 10), "a 90 deg change is not a reversal")
local calm = strafer(Vector(-80, 0, 0), Vector(300, 0, 0))
calm.tifMode = 0
check(not T.Reverse(calm, { goal = Vector(600, 0, 0), speed = "walk" }, 10), "calm walkers turn, they don't reverse")
local slow = strafer(Vector(-20, 0, 0), Vector(300, 0, 0))
check(not T.Reverse(slow, { goal = Vector(600, 0, 0), speed = "tactical" }, 10), "too slow: no reversal")

-- 0.33.1: stance changes in place (mwk_down_* / mwk_up_8).
local st = soldier({ mode = 1 })
function st:GetTIFStance() return self.stance end
TIF.Move.Moving = function() return false end
played = {}
check(T.Stance(st, 0, 1) and last() == "mwk_down_8", "stand -> crouch facing ahead: straight down (" .. tostring(last()) .. ")")
st.tifAct = nil
st.tifFace = Vector(0, 300, 0)
check(T.Stance(st, 0, 1) and last() == "mwk_down_4", "crouching to face left: the turning variant (" .. tostring(last()) .. ")")
st.tifAct = nil
st.tifFace = Vector(-300, 0, 0)
check(T.Stance(st, 0, 1) and last() == "mwk_down_2", "crouching to face behind: down_2 (" .. tostring(last()) .. ")")
st.tifAct, st.tifFace = nil, nil
check(T.Stance(st, 1, 0) and last() == "mwk_up_8", "crouch -> stand: up (" .. tostring(last()) .. ")")
st.tifAct = nil
local mov = soldier({ mode = 1, vel = Vector(80, 0, 0) })
check(not T.Stance(mov, 0, 1), "moving: no stance clip (the legs blend)")
local ps = soldier({ mode = 1, wep = "pistol" })
check(T.Stance(ps, 0, 1) and last() == "mwk_down_pstl", "pistol: its own crouch (" .. tostring(last()) .. ")")

-- 0.34.0: flashlight sets and pistol run starts / stops.
local fl = soldier({ mode = 0, vel = Vector(0, 0, 0) })
fl.nw = { tif_light = true }
played = {}
check(T.Turn(fl, 90) and last():find("^mwt_turn_calmf_"), "calm with a light on: the flashlight turn (" .. tostring(last()) .. ")")
fl.tifAct = nil
check(T.Start(fl, { tag = "patrol", speed = "walk" }) and last():find("^mwt_start_calmf_"), "calm start with a light (" .. tostring(last()) .. ")")
local dark = soldier({ mode = 0 })
dark.nw = { tif_light = false }
check(T.Turn(dark, 90) and last():find("^mwt_turn_calm_"), "no light: the plain calm turn (" .. tostring(last()) .. ")")
local pr = soldier({ mode = 1, wep = "pistol" })
check(T.Start(pr, { tag = "advance", speed = "sprint" }) and last():find("^mwt_start_pstlrun_"), "pistol sprinting off: AI pistol run start (" .. tostring(last()) .. ")")

local sp = soldier({ mode = 1 })
check(T.Start(sp, { tag = "maneuver", speed = "sprint" }) and last():find("^mwt_start_run_"), "rifle sprint off on a squad bound: AI run start (" .. tostring(last()) .. ")")
local cr = soldier({ mode = 1, stance = 1 })
check(T.Start(cr, { tag = "move", speed = "tactical" }) and last():find("^mwt_start_cwalk_"), "crouched walk off: crouch walk start (" .. tostring(last()) .. ")")
cr.tifAct = nil
check(T.Start(cr, { tag = "close", speed = "run" }) and last():find("^mwt_start_cfast_"), "crouched run off: crouch fast start (" .. tostring(last()) .. ")")
local crp = soldier({ mode = 1, stance = 1, wep = "pistol" })
check(not T.Start(crp, { tag = "move", speed = "tactical" }), "crouched pistol: no rifle crouch start")
local cov = soldier({ mode = 1 })
check(not T.Start(cov, { tag = "cover", speed = "tactical" }), "cover moves keep their own MW cover arrivals")
local function stopper(o, goal)
	local s = soldier(o)
	s.tifPath.segs = { goal }
	return s
end
local rs = stopper({ mode = 1, vel = Vector(200, 0, 0) }, Vector(40, 0, 0))
check(T.Stop(rs, { tag = "maneuver", speed = "sprint", goal = Vector(40, 0, 0) }) and last():find("^mwt_stop_run_[lr]_"), "sprint ending on a bound: AI run stop (" .. tostring(last()) .. ")")
local cs = stopper({ mode = 1, stance = 1, vel = Vector(70, 0, 0) }, Vector(30, 0, 0))
check(T.Stop(cs, { tag = "move", speed = "tactical", goal = Vector(30, 0, 0) }) and last():find("^mwt_stop_cwalk_"), "crouched walk ending: crouch stop (" .. tostring(last()) .. ")")

local pn = soldier({ mode = 1 })
pn.tifProne = { phase = 2 }
check(not T.Turn(pn, 20), "prone, small turn: no clip")
check(T.Turn(pn, 90) and last() == "mwp_turn_l" and lastOpts.to and lastOpts.to.yaw == 90, "prone 90 left: MP prone shimmy left onto the wanted yaw (" .. tostring(last()) .. ")")
pn.tifAct = nil
check(T.Turn(pn, -110) and last() == "mwp_turn_r" and lastOpts.to.yaw == -110, "prone 110 right: shimmy right")
pn.tifAct = nil
check(T.Turn(pn, 170) and last() == "mwp_turn_l" and math.abs(lastOpts.to.yaw) < 140, "prone about-face: one 90 now, the rest next time")
pn.tifAct = nil
pn.tifBipod = true
check(not T.Turn(pn, 90), "prone on the bipod: no shimmy")
local startClip = { dur = 1.4, frames = 43, curve = {} }
for i = 0, 14 do local x = i * 6.5 startClip.curve[#startClip.curve + 1] = x startClip.curve[#startClip.curve + 1] = 0 startClip.curve[#startClip.curve + 1] = 0 end
local v = T.ExitVel(startClip, 0)
check(v and math.abs(v.x - 65) < 3 and math.abs(v.y) < 0.5, "a start's exit speed from its last root samples (65 u/s forward)")
local v90 = T.ExitVel(startClip, 90)
check(v90 and math.abs(v90.y - 65) < 3 and math.abs(v90.x) < 0.5, "turned by the yaw he started at")
check(T.ExitVel({ dur = 1, frames = 31, curve = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }, 0) == nil, "a start that doesn't travel hands nothing")
local stopClip = { dur = 2.0, frames = 61, curve = {} }
for i = 0, 20 do
	local x = math.min(i, 8) * 5
	stopClip.curve[#stopClip.curve + 1] = x stopClip.curve[#stopClip.curve + 1] = 0 stopClip.curve[#stopClip.curve + 1] = 0
end
local su = T.SettleU(stopClip)
check(math.abs(su - 24 / 60) < 0.02, "a stop settles where its root motion ends (frame 24 of 60), not at the clip's end: " .. tostring(su))
check(T.SettleU({ dur = 1, frames = 31, curve = { 0, 0, 0, 10, 0, 0, 20, 0, 0, 30, 0, 0, 40, 0, 0, 50, 0, 0, 60, 0, 0, 70, 0, 0, 80, 0, 0, 90, 0, 0, 100, 0, 0 } }) == 1, "a stop still moving at its end plays out")
local trs = io.open(ROOT .. "tif/tactics/sv_trans_mw.lua"):read("*a")
check(select(2, trs:gsub("\n\tsettle_stop%(npc, name%)", "")) == 2, "both stop paths settle early")
check(trs:find("a.warpU = u", 1, true) ~= nil, "the stop's landing warp completes at the settle point")
local act = io.open(ROOT .. "tif/npc/sv_action.lua"):read("*a")
check(act:find("if act.stopU and progress >= act.stopU and npc.tifAct == act then Action.Clear(npc) end", 1, true) ~= nil, "cleared a moment after settling")
local mv = io.open(ROOT .. "tif/npc/sv_move.lua"):read("*a")
check(mv:find("if now >= ex.doneAt - 0.1 and now < ex.doneAt + 0.4 then npc.loco:SetVelocity(ex.vel) end", 1, true) ~= nil, "the start's speed is handed to the locomotion only when it played through")
do
	local e = { tifHomeHost = "mw_male", tifAware = TIF.AWARE.ENGAGED }
	local calmGuy = { tifHomeHost = "mw_male", tifAware = TIF.AWARE.ALERTED }
	check(T.FightStopSet(e, "run") == "jog", "engaged, stopping from a sprint: the gun-up jog stops")
	check(T.FightStopSet(calmGuy, "run") == "run", "not in a fight: the sprint arrival as before")
	check(T.FightStopSet(e, "pstlrun") == "pstlrun" and T.FightStopSet(e, "walk") == "walk", "other sets unchanged (pistol stops: fire held while low instead)")
end
print(string.format("passed %d, failed %d", pass, fail))
