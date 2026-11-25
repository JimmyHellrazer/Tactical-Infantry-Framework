timer = timer or { Create = function() end, Simple = function() end }
-- Offline (0.38.14): close-range melee (tactics/sv_melee_mw.lua) on the real clip table.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Rand = function(a, b) return (a + b) / 2 end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
local RND = 0.1
math.random = function(a, b) if a and b then return a end if a then return 1 end return RND end
DMG_CLUB, MASK_NPCSOLID_BRUSHONLY, CHAN_WEAPON, COLLISION_GROUP_DEBRIS = 128, 1, 1, 1
FCVAR_ARCHIVE = 0
function CreateConVar() return { GetBool = function() return true end } end
function istable(x) return type(x) == "table" end
function IsValid(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[ev] = fn end }
sound = { GetProperties = function() return nil end }
-- (vertical traces hit the floor at z 0; level ones (0.38.28: the fight spot's line) are clear; hulls fit)
util = { TraceLine = function(t)
	if math.abs(t.start.z - t.endpos.z) > 1 then return { Hit = true, HitPos = Vector(t.endpos.x, t.endpos.y, 0) } end
	return { Hit = false, HitPos = t.endpos, Fraction = 1 }
end, TraceHull = function() return { StartSolid = false, Fraction = 1 } end }
local dmgLog = {}
function DamageInfo()
	local d = {}
	function d:SetDamage(x) self.dmg = x end
	function d:SetDamageType(x) self.type = x end
	function d:SetAttacker(x) self.att = x end
	function d:GetAttacker() return self.att end
	function d:SetInflictor() end
	function d:SetDamagePosition() end
	function d:SetDamageForce() end
	return d
end

local played = {}
TIF = {
	Anim = { STANCE_STAND = 0 }, REL_ALLY = 1, REL_ENEMY = 2,
	GTG = { IsVB = function() return true end, WeaponKind = function(c) return c == "pistol" and "pistol" or (c == "rpg" and "rpg" or "rifle") end },
	Move = { Stop = function() end },
	Say = function() end,
	Relation = function(a, b) return (a.side and b.side and a.side == b.side) and 1 or 2 end,
}
TIF.Action = {
	Clip = function(npc, n) return clips[n] end,
	Play = function(npc, n, o) if npc.tifActLock and not (o and o.lockOK) then return nil end local c = clips[n] if not c then return nil end played[#played + 1] = { npc, n, o } npc.tifAct = { name = n } return c.dur end,
	Clear = function(npc, force) if npc.tifActLock and not force then return end npc.tifAct = nil end,
}
assert(loadfile(ROOT .. "tif/tactics/sv_melee_mw.lua"))()
local M = TIF.MeleeMW

local function ent(pos, yaw, o)
	o = o or {}
	local e = { pos = pos, yaw = yaw or 0, hp = o.hp or 100, side = o.side, group = 0 }
	function e:GetPos() return self.pos end
	function e:SetPos(p) self.pos = p end
	function e:GetAngles() return Angle(0, self.yaw, 0) end
	function e:SetAngles(a) self.yaw = a.y end
	function e:GetForward() local r = math.rad(self.yaw) return Vector(math.cos(r), math.sin(r), 0) end
	function e:WorldSpaceCenter() return self.pos + Vector(0, 0, 40) end
	function e:Health() return self.hp end
	function e:IsPlayer() return o.player == true end
	function e:TakeDamageInfo(d)
		dmgLog[#dmgLog + 1] = { who = self, dmg = d.dmg, type = d.type }
		if hooks.EntityTakeDamage then hooks.EntityTakeDamage(self, d) end
		self.hp = self.hp - d.dmg
		if self.hp <= 0 then self.tifDead = true end
	end
	function e:EmitSound() end
	function e:ViewPunch() self.punched = true end
	function e:SetVelocity() end
	function e:GetCollisionGroup() return self.group end
	function e:SetCollisionGroup(g) self.group = g end
	function e:SetTIFShotTime(t) self.shot = t end
	if o.soldier then
		e.TIFSoldier, e.tifHomeHost, e.tifArch = true, "mw_male", { aggression = 0.5 }
		e.tifFire = {}
		e.tifWep = { class = o.wep or "rifle" }
		e.loco = { GetVelocity = function() return o.vel or Vector() end }
		function e:GetTIFStance() return 0 end
	end
	return e
end

-- clips and their notes
check(clips.mwm_melee_1 and clips.mwm_pmelee_1 and clips.mwm_to_melee_1 and clips.mwm_run_to_melee_1, "strike / step-in clips built")
local hits1 = M.Events(clips.mwm_melee_1, "fire")
check(#hits1 == 2 and hits1[1] < hits1[2], "melee01 strikes twice (" .. #hits1 .. ")")
check(#M.Events(clips.mwm_fight_aw_def, "melee_death") == 1 and #M.Events(clips.mwm_fight_dw_att, "melee_death") == 1, "fight death notes")

-- A player right there: a butt hit, damage at each strike, never a fight
local now = 100
local s = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" })
local ply = ent(Vector(50, 0, 0), 180, { player = true, side = "b" })
check(M.Try(s, { visible = true, ent = ply }, now) == true and s.tifMelee and s.tifMelee.phase == "strike", "player within reach: strike")
check(played[#played][2]:find("^mwm_melee_") ~= nil, "rifle strike clip")
local dur = s.tifMelee.dur
local t = now
while s.tifMelee and t < now + dur + 0.1 do t = t + 0.03 M.Busy(s, t) end
local n = 0
for _, d in ipairs(dmgLog) do if d.who == ply and d.type == DMG_CLUB then n = n + 1 end end
check(n == #M.Events(clips[played[#played][2]], "fire"), "one hit per fire note (" .. n .. ")")
check(ply.punched, "player's view punched")
check(s.tifMelee == nil and s.tifNextMelee > t, "done, then a cooldown")
check(M.Try(s, { visible = true, ent = ply }, t + 0.1) == false, "cooldown holds")

-- Pistol: the pistol whip
dmgLog = {}
local ps = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a", wep = "pistol" })
M.Try(ps, { visible = true, ent = ply }, 200)
check(played[#played][2]:find("^mwm_pmelee_") ~= nil, "pistol: pistol whip")

-- A bit further: the step-in first, then the strike
local s2 = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" })
local p2 = ent(Vector(90, 0, 0), 180, { player = true, side = "b" })
check(M.Try(s2, { visible = true, ent = p2 }, 300) and s2.tifMelee.phase == "step" and played[#played][2]:find("^mwm_to_melee_"), "90 away: step in")
M.Busy(s2, 300 + s2.tifMelee.dur + 0.01)
check(s2.tifMelee and s2.tifMelee.phase == "strike", "then the strike")
-- Running at him from further: the charge
local s3 = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a", vel = Vector(200, 0, 0) })
local p3 = ent(Vector(150, 0, 0), 180, { player = true, side = "b" })
check(M.Try(s3, { visible = true, ent = p3 }, 400) and played[#played][2]:find("^mwm_run_to_melee_"), "running, 150 away: charge in")
-- RPG: none; too far: none
local r = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a", wep = "rpg" })
check(M.Try(r, { visible = true, ent = ply }, 500) == false, "RPG: no melee")
local far = ent(Vector(400, 0, 0), 180, { player = true })
check(M.Try(ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" }), { visible = true, ent = far }, 500) == false, "too far: none")
-- Players never get a fight even at fight range
local s4 = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" })
local p4 = ent(Vector(100, 0, 0), 180, { player = true, side = "b" })
M.Try(s4, { visible = true, ent = p4 }, 600)
check(not (s4.tifMelee and s4.tifMelee.fight), "player at 100: no fight")

-- Enemy soldier ~105 away: a paired fight (RND 0.1 < chance), attacker on his scene spot
played = {}
local A = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" })
local D = ent(Vector(105, 0, 0), 180, { soldier = true, side = "b" })
check(M.Try(A, { visible = true, ent = D }, 700) == true and A.tifMelee and A.tifMelee.fight, "enemy soldier at 105: a fight")
local F = M.FIGHT[A.tifMelee.fight]
check(D.tifMelee and D.tifMelee.partner == A and A.tifMelee.partner == D, "both in it, partnered")
local off = A.pos - D.pos
check(math.abs(off:Length2D() - math.sqrt(F.x ^ 2 + F.y ^ 2)) < 1, "attacker on his scene spot (" .. off:Length2D() .. ")")
check(math.abs(((A.yaw - D.yaw + 180) % 360) - 180) > 179 or math.abs(((A.yaw - D.yaw) % 360) - 180) < 1, "facing each other")
check(A.group == COLLISION_GROUP_DEBRIS and D.group == COLLISION_GROUP_DEBRIS, "no pushing while locked together")
-- (2026-11-20) both halves locked: nothing else (a reaction, a turn) replaces one man's clip mid fight
check(A.tifActLock == "melee" and D.tifActLock == "melee", "both locked to their fight clips")
check(TIF.Action.Play(A, "mwm_melee_1", { root = true }) == nil and A.tifAct.name == A.tifMelee.clipName, "another clip is refused mid fight")
local loser = A.tifMelee.loser
local winner = loser == A and D or A
local tt = 700
while (A.tifMelee or D.tifMelee) and tt < 720 do tt = tt + 0.05 M.Busy(A, tt) M.Busy(D, tt) end
check(loser.tifDead and loser.tifNoDeathClip, "the loser dies at melee_death, from the fight clip's frame")
check(winner.hp == 100 and not winner.tifDead, "the winner unhurt")
check(winner.tifMelee == nil and winner.group == 0, "the winner played it out and let go")
check(winner.tifActLock == nil, "the winner's lock off after the fight")
check(winner.shot ~= nil, "the winner's finishing shot")
-- An outsider shoots one mid-fight: off for both
local A2 = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" })
local D2 = ent(Vector(105, 0, 0), 180, { soldier = true, side = "b" })
M.Try(A2, { visible = true, ent = D2 }, 800)
check(A2.tifMelee and A2.tifMelee.fight, "second fight")
local outsider = ent(Vector(500, 0, 0), 0, { soldier = true, side = "c" })
local d = DamageInfo() d:SetDamage(10) d:SetAttacker(outsider) d:SetDamageType(2)
D2:TakeDamageInfo(d)
check(A2.tifMelee == nil and D2.tifMelee == nil and A2.group == 0 and D2.group == 0, "an outsider's shot ends it for both")
check(A2.tifActLock == nil and D2.tifActLock == nil, "locks off when an outsider ends it")
-- Friendly soldier: never
local F1 = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" })
local F2 = ent(Vector(105, 0, 0), 180, { soldier = true, side = "a" })
M.Try(F1, { visible = true, ent = F2 }, 900)
check(not (F1.tifMelee and F1.tifMelee.fight), "allies don't fight")
-- (0.38.28) a fight from 60 in apart, the defender crouched: allowed now
do
	local A3 = ent(Vector(0, 0, 0), 0, { soldier = true, side = "a" })
	local D3 = ent(Vector(60, 0, 0), 180, { soldier = true, side = "b" })
	D3.GetTIFStance = function() return 1 end
	math.random = function(a, b) if a then return a end return 0 end
	local ok = M.Try(A3, { visible = true, ent = D3 }, 500)
	check(ok and A3.tifMelee and A3.tifMelee.fight ~= nil, "60 in apart, defender crouched: a paired fight")
end
-- (0.38.31) close 1-on-1s: the scanner starts the fight, a step / turn clip in the way or not
do
	local P1 = ent(Vector(0, 3000, 0), 0, { soldier = true, side = "a" })
	local P2 = ent(Vector(100, 3000, 0), 180, { soldier = true, side = "b" })
	P1.tifPrimary = P2
	P1.tifAct = { name = "mwt_turn_4", trans = true }
	P2.tifReact = { untilT = 99999 }
	local far1 = ent(Vector(0, 5000, 0), 0, { soldier = true, side = "a" })
	local far2 = ent(Vector(400, 5000, 0), 180, { soldier = true, side = "b" })
	far1.tifPrimary = far2
	local al1 = ent(Vector(0, 7000, 0), 0, { soldier = true, side = "a" })
	local al2 = ent(Vector(100, 7000, 0), 180, { soldier = true, side = "a" })
	al1.tifPrimary = al2
	local cv1 = ent(Vector(0, 9000, 0), 0, { soldier = true, side = "a" })
	local cv2 = ent(Vector(100, 9000, 0), 180, { soldier = true, side = "b" })
	cv1.tifPrimary, cv1.tifCov = cv2, {}
	TIF.Soldiers = { P1, P2, far1, far2, al1, al2, cv1, cv2 }
	math.random = function(a, b) if a then return a end return 0 end
	M.PairScan(900)
	check(P1.tifMelee and P1.tifMelee.fight and P2.tifMelee and P2.tifMelee.fight, "scanner: an engaged pair 100 in apart fights (a turn clip didn't stop it)")
	check(P2.tifReact == nil and P2.tifAct and P2.tifAct.name == P2.tifMelee.clipName, "a reaction in the way: dropped, his fight half plays")
	check(not far1.tifMelee, "scanner: 400 in apart: no")
	check(not al1.tifMelee, "scanner: allies: no")
	check(not cv1.tifMelee, "scanner: one in cover: no")
	local ssrc = io.open(ROOT .. "entities/tif_soldier.lua"):read("*a")
	check(ssrc:find("if TIF.HitsMW and not self.tifNoDeathClip and self:Health() > 0 then pcall(TIF.HitsMW.Pain", 1, true) ~= nil,
		"no pain stagger on a killing hit / a clip death (the corpse is posed from the fight clip, not an A-pose stagger)")
end
print(string.format("passed %d, failed %d", pass, fail))
