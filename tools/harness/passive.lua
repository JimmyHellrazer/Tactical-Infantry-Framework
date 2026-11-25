-- Offline run of tactics/sv_passive_mw.lua with the real generated clip data. ROOT, CLIPS set by the runner.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
math.Rand = function(a, b) return (a + b) / 2 end
math.AngleDifference = function(a, b) return (a - b + 180) % 360 - 180 end
function IsValid(x) return x ~= nil end

TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local played, said, stims = {}, {}, {}
TIF = {
	AWARE = { UNAWARE = 0, SUSPICIOUS = 1, ALERTED = 2, ENGAGED = 3, SEARCHING = 4 },
	GTG = { IsVB = function(id) return id == "mw_male" end, Clip = function(name, id) return id == "mw_male" and clips[name] or nil end },
	Move = { Stop = function(npc) npc.stopped = (npc.stopped or 0) + 1 end },
	Say = function(npc, ev) said[#said + 1] = ev end,
	Perception = { Stimulus = function(npc, pos, kind) stims[#stims + 1] = { npc = npc, kind = kind } end },
	Soldiers = {},
}
TIF.Action = {
	Play = function(npc, name, opts)
		local c = clips[name]
		if not c then return nil end
		played[#played + 1] = name
		npc.tifAct = { name = name }
		return c.dur / ((opts and opts.rate) or 1)
	end,
	Loop = function(npc, name) played[#played + 1] = name npc.tifAct = { name = name, loop = true } return 1 end,
	Clear = function(npc) npc.tifAct = nil end,
}
local fn, err = loadfile(ROOT .. "tif/tactics/sv_passive_mw.lua")
if not fn then error(err) end
fn()
local P, AW = TIF.PassiveMW, TIF.AWARE
P.TAKE_CHANCE = 1

local function soldier(faction)
	local s = { tifHomeHost = "mw_male", pos = Vector(0, 0, 0), yaw = 0, vel = 0, tifAware = AW.UNAWARE, faction = faction or "army" }
	function s:GetPos() return self.pos end
	function s:GetAngles() return Angle(0, self.yaw, 0) end
	function s:GetTIFFaction() return self.faction end
	s.loco = { GetVelocity = function() return Vector(s.vel, 0, 0) end }
	return s
end
local last = function() return played[#played] end

-- Activities at a post
local now = 100
local a = soldier()
check(P.Use(a), "used on the MW body")
check(not P.Duty(a, now, true), "no activity before standing still a while")
now = now + 40
check(P.Duty(a, now, true) and last():find("^mwx_[%a%d]+_start$"), "an activity starts after standing still: " .. tostring(last()))
local act = a.tifActivity.name
now = a.tifActivity.untilT + 0.01
P.Duty(a, now, true)
check(a.tifActivity.phase == "loop" and last() == "mwx_" .. act .. "_loop", "start -> loop")
now = a.tifActivity.loopUntil + 0.01
P.Duty(a, now, true)
check(a.tifActivity.phase == "end" and last() == "mwx_" .. act .. "_end", "loop -> end")
now = a.tifActivity.untilT + 0.01
check(not P.Duty(a, now, true) and a.tifActivity == nil, "done, cooldown")
check(not P.Duty(a, now + 5, true), "no new activity during the cooldown")

-- Ordered to move during an activity: put away first
now = now + 200
P.Duty(a, now, true)
now = now + 40
P.Duty(a, now, true)
check(a.tifActivity ~= nil, "second activity started")
check(P.Duty(a, now, false) and a.tifActivity == nil and a.tifPassiveBusy and a.tifPassiveBusy.kind == "away", "walking off: put away first")
check(P.Busy(a, now + 0.1), "busy while putting it away")

-- Caught off guard: spotted an enemy while smoking -> hurried put-away, first shot waits
now = now + 100
a.tifPassiveBusy = nil
a.tifActivity, a.tifNextActivity = { name = "smoke", phase = "loop", untilT = now, loopUntil = now + 30 }, 0
a.tifAware = AW.ENGAGED
a.tifReactUntil = now + 0.4
check(P.Busy(a, now) and last() == "mwx_smoke_end", "engaged while smoking: puts it away")
check(a.tifReactUntil > now + 0.5, "no shot before the hands are free")
check(P.Busy(a, now + 0.2), "can't be cut short (putting away)")

-- Graded reactions
local b = soldier()
b.tifStim = { pos = Vector(0, 300, 0), kind = "footstep", time = now }
P.OnAware(b, AW.UNAWARE, AW.SUSPICIOUS, now)
check(b.tifPendingReact and not (last() or ""):find("^mwr_"), "reaction waits for its own small delay")
P.Busy(b, now + 1)
check(last() == "mwr_patrol_idle_sm_4" or last() == "mwr2_patrol_idle_cur_4", "footstep on the left, standing: small patrol (or MW22 curious) reaction to the left: " .. tostring(last()))
b.tifPassiveBusy, b.tifAct = nil, nil
b.tifStim = { pos = Vector(-300, 0, 0), kind = "gunfire", time = now }
b.vel = 60
P.OnAware(b, AW.UNAWARE, AW.SUSPICIOUS, now)
P.Busy(b, now + 1)
check(last() == "mwr_patrol_walk_smed_2", "gunfire behind while walking: medium walking reaction to the back: " .. tostring(last()))
b.tifPassiveBusy, b.tifAct = nil, nil
b.vel = 0
b.tifHeightenedUntil = now + 50
b.tifPrimaryC = { pos = Vector(0, -300, 0) }
P.OnAware(b, AW.SUSPICIOUS, AW.ALERTED, now)
P.Busy(b, now + 1)
check(last() == "mwr_alert_idle_lg_6", "on edge, enemy known on the right: large alert reaction to the right: " .. tostring(last()))
-- a fight cuts a (non-spotting) reaction short
b.tifAware = AW.ENGAGED
check(not P.Busy(b, now + 0.1) and b.tifPassiveBusy == nil, "a fight cuts the reaction short")
-- spotted while calm: quick large reaction, shot waits for it
local c = soldier()
c.tifReactUntil = now + 0.5
c.tifPrimaryC = { pos = Vector(300, 0, 0) }
P.OnAware(c, AW.UNAWARE, AW.ENGAGED, now)
check(last() == "mwr_patrol_idle_lg_8" and c.tifReactUntil > now + 0.5, "spotted in front while calm: quick large reaction, first shot after it")
c.tifAware = AW.ENGAGED
check(P.Busy(c, now + 0.1), "the spotting reaction itself isn't cut by the fight it started")
-- calm down
local d = soldier()
d.tifAware = AW.UNAWARE
P.OnAware(d, AW.SUSPICIOUS, AW.UNAWARE, now)
P.Busy(d, now + 3)
check(last() == "mwa_calm", "calming down: alert -> patrol clip")

-- Investigating: idles; a body: check it, then the alarm
local e = soldier()
check(P.Investigate(e, now) and last():find("^mwi_"), "investigation idle: " .. tostring(last()))
local ally, far = soldier(), soldier()
ally.pos, far.pos = Vector(500, 0, 0), Vector(5000, 0, 0)
TIF.Soldiers = { e, ally, far }
e.tifStim = { pos = Vector(50, 0, 0), kind = "man_down", time = now }
check(P.Investigate(e, now) and last():find("^mwk_body"), "a downed ally: checks the body")
check(P.Busy(e, now + 1), "busy while checking")
local t = e.tifPassiveBusy.untilT + 0.01
check(not P.Busy(e, t), "done checking")
check(said[#said] == "man_down" and e.tifHeightenedUntil > t, "raises the alarm")
local alerted = {}
for _, s in ipairs(stims) do alerted[s.npc] = s.kind end
check(alerted[ally] == "alarm" and alerted[far] == nil, "nearby allies alerted, far ones not")

-- a delayed reaction is dropped if a fight started in the meantime
local f2 = soldier()
f2.tifStim = { pos = Vector(0, 300, 0), kind = "footstep", time = now }
local n0 = #played
P.OnAware(f2, AW.UNAWARE, AW.SUSPICIOUS, now)
f2.tifAware = AW.ENGAGED
P.Busy(f2, now + 1)
check(#played == n0, "no late reaction once fighting")
print(string.format("passed %d, failed %d", pass, fail))
