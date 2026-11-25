-- 2026-11-20: a clip death (paired fight loser, tifNoDeathClip) carries on the clip on the server (tifDying) and the
-- corpse comes from it after CLIP_DEATH_HOLD, with bone velocities; not straight away from the hidden stance pose.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end

-- permissive world: any unknown global is a callable, indexable dummy
local dummy
dummy = setmetatable({}, { __index = function() return dummy end, __call = function() return dummy end })
setmetatable(_G, { __index = function(_, k) return dummy end })
local now = 50
CurTime = function() return now end
local timers = {}
timer = { Simple = function(t, f) timers[#timers + 1] = { t = now + t, f = f } end, Create = function() end }
IsValid = function(e) return e ~= nil and e ~= false and e ~= dummy end
COLLISION_GROUP_DEBRIS = 1
ENT = {}
CLIENT, SERVER = false, true
TIF = { Error = function(...) print("TIF.Error", ...) end, Log = function() end }
local finished
TIF.HitsMW = { DyingThink = function() end, Death = function() return false end }
TIF.Morale, TIF.Unregister = nil, function() end
TIF.Cover = { Release = function() end }
TIF.Squad = { Remove = function() end }
TIF.Say = function() end
TIF.Soldiers = {}
hook = { Run = function() end, Add = function() end }
local f = assert(loadfile(ROOT .. "entities/tif_soldier.lua"))
f()

local function soldier(noClip)
	local s = { nw = {}, tifAct = { name = "mwm_fight_aw_def", clip = { seq = "mwm_fight_aw_def" }, t0 = now - 1.5, dur = 3 },
		tifNoDeathClip = noClip }
	function s:LookupSequence(n) return n == "mwm_fight_aw_def" and 42 or -1 end
	function s:SetNW2Bool(k, v) self.nw[k] = v end
	function s:SetCollisionGroup(g) self.group = g end
	function s:GetTIFFaction() return "a" end
	function s:GetPos() return dummy end
	s.TIFDropWeapon = function() end
	s.TIFFinishDeath = function(self, bv) finished = { bv = bv } end
	return s
end
local dmg = { GetDamagePosition = function() return "p" end, GetDamageForce = function() return "f" end,
	GetAttacker = function() return nil end, GetInflictor = function() return nil end }

finished = nil
local s = soldier(true)
ENT.OnKilled(s, dmg)
local dy = s.tifDying
check(dy and dy.seq == 42 and dy.t0 == now - 1.5 and dy.dur == 3, "the fight clip carries on on the server from where it was")
check(dy and dy.untilT > now and dy.untilT <= now + 0.5 and dy.prevT == now, "for a moment (" .. tostring(dy and dy.untilT - now) .. " s), no bone sample from the kill's tick")
check(finished == nil, "no corpse in the kill's own tick (bones there are the hidden stance pose)")
check(s.nw.tif_dying == true and s.group == 1, "dying flag (gun hidden), out of the way")
-- a normal death goes the usual way
finished = nil
local s2 = soldier(nil)
ENT.OnKilled(s2, dmg)
check(s2.tifDying == nil and finished ~= nil, "no clip death: the corpse at once as before")
print(string.format("passed %d, failed %d", pass, fail))
