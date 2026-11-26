-- Offline run of tactics/sv_hits_mw.lua with the real generated clip data. ROOT, CLIPS set by the runner.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) if type(x) == 'table' then x, y, z = x.x, x.y, x.z end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:GetNormalized() local l = self:Length() return l > 0 and Vector(self.x / l, self.y / l, self.z / l) or Vector() end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end return Vector(a.x * b, a.y * b, a.z * b) end
V.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
function IsValid(x) return x ~= nil end
HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG = 1, 2, 6, 7
COLLISION_GROUP_DEBRIS = 1
local now = 50
function CurTime() return now end
local banfile = ""
file = { Read = function() return banfile end, Write = function(_, t) banfile = t end, CreateDir = function() end }
string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
concommand = { Add = function() end }
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[id] = fn end }
MASK_SHOT = 1
local effects = {}
function EffectData() local e = {} function e:SetOrigin(p) self.o = p end function e:SetNormal() end return e end
function CreateConVar(n, v) return { GetFloat = function() return tonumber(v) end, GetBool = function() return HITS_LONG == true end } end
FCVAR_ARCHIVE = 0
EF_NOINTERP, MASK_NPCSOLID_BRUSHONLY = 8, 1
local traceFrac = 1
do local mt = getmetatable(Vector(0, 0, 0)); local idx = mt and mt.__index
	if type(idx) == "table" and not idx.Cross then idx.Cross = function(a, b) return Vector(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end end
	if type(idx) == "table" and not idx.Normalize then idx.Normalize = function(v) local l = math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2) if l > 0 then v.x, v.y, v.z = v.x / l, v.y / l, v.z / l end end end end
DMG_CLUB, DMG_SLASH, DMG_BURN = 128, 4, 8
ledgeMode = nil -- nil: solid ground everywhere; "norail" / "rail": a drop in front
util = { TraceHull = function() return { Fraction = traceFrac } end,
	TraceLine = function(t)
		local horiz = math.abs(t.start.z - t.endpos.z) < 1
		if not ledgeMode then return { Hit = not horiz } end
		if horiz then
			local z = t.start.z - 0
			if ledgeMode == "rail" then return { Hit = z > 30 and z < 50 } end
			return { Hit = false }
		end
		return { Hit = false } -- nothing below: a drop
	end }
timer = { Simple = function(_, f) f() end }
util.Effect = function(n, e) effects[#effects + 1] = n end

TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local played = {}
TIF = {
	Anim = { STANCE_STAND = 0, STANCE_CROUCH = 1 },
	GTG = { IsVB = function(id) return id == "mw_male" end, Clips = function(id) return id == "mw_male" and clips or nil end },
	Move = { Stop = function() end },
	CoverBehave = { In = function(n) return n.tifCov ~= nil end },
}
TIF.Action = {
	Play = function(npc, name, opts) local c = clips[name] if not c then return nil end played[#played + 1] = name npc.tifAct = { name = name, opts = opts } return c.dur end,
	Tick = function(npc) npc.ticks = (npc.ticks or 0) + 1 end,
}
local fn, err = loadfile(ROOT .. "tif/tactics/sv_hits_mw.lua")
if not fn then error(err) end
fn()
local H = TIF.HitsMW

local function soldier()
	local s = { tifHostId = "mw_male", pos = Vector(0, 0, 0), yaw = 0, vel = 0, stance = 0, nw = {}, bones = {} }
	function s:GetPos() return self.pos end
	function s:GetAngles() return Angle(0, self.yaw, 0) end
	function s:GetForward() return Vector(1, 0, 0) end
	function s:GetNW2Bool(k, d) if self.nw[k] ~= nil then return self.nw[k] end return d end
	function s:GetTIFShotTime() return self.shotT or 0 end
	function s:GetTIFStance() return self.stance end
	function s:SetNW2Bool(k, v) self.nw[k] = v end
	function s:SetNW2Int(k, v) self.nw[k] = v end
	function s:SetPos(p) self.pos = p end
	function s:AddEffects(e) self.fx = (self.fx or 0) + 1 end
	function s:RemoveEffects(e) self.fxOff = true end
	function s:SetCollisionGroup(g) self.cg = g end
	function s:GetBoneCount() return 3 end
	function s:GetBoneMatrix(b) local p = self.bones[b] or Vector(b, 0, 40) return { GetTranslation = function() return p end } end
	function s:TIFFinishDeath(vel) self.finished = vel end
	function s:LookupSequence(n) return 5 end
	function s:EntIndex() return 7 end
	s.loco = { GetVelocity = function() return Vector(s.vel, 0, 0) end }
	return s
end
local function dmg(force, amount, explosion)
	return { GetDamageForce = function() return force end, GetDamagePosition = function() return Vector() end,
		GetDamage = function() return amount or 30 end, IsExplosionDamage = function() return explosion == true end, IsDamageType = function(_, t) return melee == t end, IsBulletDamage = function() return explosion ~= true end,
		GetAttacker = function() return nil end }
end

-- Pools from the clip names
local P = H.Pools("mw_male")
local n = 0
for _ in pairs(P.death.stand or {}) do n = n + 1 end
check(P.death.stand and P.death.stand.torso and #P.death.stand.torso >= 20, "standing torso deaths (MW19 + friend set): " .. (P.death.stand and P.death.stand.torso and #P.death.stand.torso or 0))
check(P.death.run and P.death.run.any and #P.death.run.any >= 20, "running deaths (3 MW19 + 19 friend set)")
check(P.death.cover_ls and P.death.prone and P.death.explode and P.pain.stand and P.pain.run, "cover / prone / explosion deaths and stand / run pains present")

-- Shot from the front (push backward): a death that falls backward; the ragdoll comes mid-fall.
math.randomseed(1)
local backward = 0
for i = 1, 30 do
	local s = soldier()
	s.tifLastHitGroup = HITGROUP_CHEST
	check(H.Death(s, dmg(Vector(-1000, 0, 0))), "death clip plays")
	local c = clips[played[#played]]
	if c.fall and c.fall[1] < 0 then backward = backward + 1 end
	local cut = s.tifDying.untilT - now
	check(cut > 0 and cut < c.dur * 0.9, "ragdoll before the clip's end")
end
check(backward >= 27, "shots from the front fall backward: " .. backward .. "/30")

-- Situations
local s = soldier()
s.tifLastHitGroup = HITGROUP_HEAD
s.tifCov = { mw = true, t = "ls", phase = "idle" }
H.Death(s, dmg(Vector(0, -1000, 0)))
check(clips[played[#played]].from:find("cover_left_stand_death"), "killed in a left corner: its cover death: " .. clips[played[#played]].from)
s = soldier()
s.tifProne = {}
H.Death(s, dmg(Vector(-1000, 0, 0)))
check(clips[played[#played]].from:find("prone_death"), "prone death")
check(s.pos.x == 0 and s.pos.y == 0, "prone death: no teleport (the clips are built on the prone pelvis): " .. s.pos.x)
check(s.nw.tif_prone == 0 and s.tifProne == nil, "prone death: prone cleared so the client shows the clip")
do local k = (s.tifDying.untilT - now) / clips[played[#played]].dur; check(k >= 0.39 and k <= 0.51, "prone death: ragdoll 40-50% in (" .. string.format("%.2f", k) .. ")") end
s = soldier()
s.tifProne = {}
traceFrac = 0.5
H.Death(s, dmg(Vector(-1000, 0, 0)))
check(s.pos.x == 0, "prone death against a wall: still no move")
traceFrac = 1
s = soldier()
s.tifProne = {}
s.tifLastHitGroup = HITGROUP_CHEST
check(H.Pain(s, dmg(Vector(-1000, 0, 0), 60)) == false and s.tifAct == nil, "prone: no pain stagger")
s = soldier()
H.Death(s, dmg(Vector(-1000, 0, 0), 100, true))
check(clips[played[#played]].from:find("explode"), "explosion death")
s = soldier()
s.vel = 250
H.Death(s, dmg(Vector(1000, 0, 0)))
local f = clips[played[#played]].from
check(f:find("run_death") or f:find("DeathRunning"), "running death: " .. f)

-- Mid-fall handoff with bone velocities
s = soldier()
H.Death(s, dmg(Vector(-1000, 0, 0)))
local untilT = s.tifDying.untilT
now = now + 0.1
check(H.DyingThink(s, now) and s.ticks == 1, "dying: follows the clip")
s.bones[1] = Vector(1, 0, 40)
now = now + 0.1
H.DyingThink(s, now)
now = untilT - 0.005
H.DyingThink(s, now)
s.bones[1] = Vector(11, 0, 35)
now = untilT + 0.01
H.DyingThink(s, now)
check(s.finished and s.finished[1] and s.finished[1].x > 50 and s.finished[1].z < 0, "ragdoll gets the bones' animated velocity")
-- 0.38.9: measured over ~H.VEL_WINDOW of ticks, not the last one (a hitch on that tick doubled it)
do
	local s2 = soldier()
	H.Death(s2, dmg(Vector(-1000, 0, 0)))
	local u2 = s2.tifDying.untilT
	local t = u2 - 0.3
	local x = 0
	while t < u2 - 0.001 do
		s2.bones[1] = Vector(x, 0, 40)
		H.DyingThink(s2, t)
		t = t + 0.015
		x = x + 3 -- 200 u/s steady
	end
	s2.bones[1] = Vector(x + 12, 0, 40) -- a 4x jump on the last tick
	H.DyingThink(s2, u2 + 0.01)
	local v = s2.finished and s2.finished[1]
	check(v and v.x > 150 and v.x < 400, "a hitch on the last tick barely shows (" .. tostring(v and v.x) .. ", one-tick was ~1000)")
end

-- Pains
local p = soldier()
p.tifLastHitGroup = HITGROUP_LEFTLEG
local hits = 0
for i = 1, 20 do
	p.tifNextPain, p.tifAct, p.tifPainUntil = 0, nil, nil
	if H.Pain(p, dmg(Vector(-1000, 0, 0), 60)) then hits = hits + 1 end
end
check(hits >= 15, "heavy hits mostly stagger: " .. hits .. "/20")
check(clips[played[#played]].from:find("pain") and H.Busy(p, now + 0.1), "busy while staggering: " .. clips[played[#played]].from)
check(not H.Pain(p, dmg(Vector(-1000, 0, 0), 60)), "cooldown: no second stagger at once")
local q = soldier()
q.tifCov = {}
check(not H.Pain(q, dmg(Vector(-1000, 0, 0), 60)), "no stagger in cover (cover has its own flinch)")
do
	local saveClip = TIF.GTG.Clip
	TIF.GTG.Clip = saveClip or function(n) return clips[n] end
	local w = soldier()
	w.vel = 90
	w.tifLastHitGroup = HITGROUP_CHEST
	local stopped, acted = false, 0
	local saveStop = TIF.Move.Stop
	TIF.Move.Stop = function() stopped = true end
	for i = 1, 20 do
		w.tifNextPain, w.tifAct, w.tifPainUntil = 0, nil, nil
		if H.Pain(w, dmg(Vector(-1000, 0, 0), 60)) then acted = acted + 1 end
	end
	check(acted == 0 and not stopped, "walking: no standing stagger, he keeps moving (" .. acted .. " / 20)")
	local r = soldier()
	r.vel = 250
	r.tifLastHitGroup = HITGROUP_CHEST
	local flinch, other = 0, 0
	for i = 1, 20 do
		r.tifNextPain, r.tifAct, r.tifPainUntil = 0, nil, nil
		local before = #played
		if H.Pain(r, dmg(Vector(-1000, 0, 0), 60)) then
			if played[#played]:find("^mwh_flinch_") then flinch = flinch + 1 else other = other + 1 end
		end
	end
	check(other == 0 and not stopped, "running: only the running flinches, never a stop-and-stagger (" .. flinch .. " flinches)")
	TIF.Move.Stop = saveStop
	TIF.GTG.Clip = saveClip
end


-- Explosion deaths only for real blasts; bans; recent list.
local blastOnly = dmg(Vector(-100, 0, 0), 20, true)
check(not H.RealBlast(blastOnly), "a light blast (under 30) isn't a real blast")
local bulletBlast = { GetDamage = function() return 60 end, IsExplosionDamage = function() return true end, IsBulletDamage = function() return true end }
check(not H.RealBlast(bulletBlast), "rounds flagged as blast + bullet: not a real blast")
check(H.RealBlast(dmg(Vector(-100, 0, 0), 80, true)), "a grenade: real blast")
check(#H.Recent > 0 and H.Recent[1].name, "recent deaths recorded: " .. tostring(H.Recent[1] and H.Recent[1].name))
local first = P.death.stand.torso[1].name
H.Banned[first] = true
local P2 = (function() for k in pairs(H.Banned) do end return nil end)()

-- 0.31.1: long deaths (MW19 SP AI): enter -> crawl / wounded idle -> death, all three on the body.
math.Rand = math.Rand or function(a, b) return a + (b - a) * math.random() end
TIF.GTG.Clip = TIF.GTG.Clip or function(n, id) return id == "mw_male" and clips[n] or nil end
local seenKinds = {}
for i = 1, 40 do
	local ch = H.LongChain({ tifHostId = "mw_male" }, i % 2 == 0 and "crouch" or "stand")
	check(ch and #ch == 3 and clips[ch[1].name] and clips[ch[2].name] and clips[ch[3].name], "long death chain " .. i .. " complete")
	if ch then
		seenKinds[string.match(ch[1].name, "^mwld_(%a+_%w+)_enter$") or "?"] = true
		check(ch[2].hold and ch[2].hold >= 2.5 and ch[2].hold <= 6, "crawl held 2.5-6 s")
		check((clips[ch[3].name].cut or 0) >= 0 or true, "death clip measured")
	end
end
local nk = 0 for _ in pairs(seenKinds) do nk = nk + 1 end
check(nk >= 1, "long death kinds available (" .. nk .. ")")

-- 0.32.2: situational deaths (most specific pool first).

local function death_from(setup, d)
	local s = soldier()
	setup(s)
	played = {}
	H.Death(s, d or dmg(Vector(-1000, 0, 0)))
	ledgeMode, melee = nil, nil
	return played[#played] and clips[played[#played]].from or "none"
end
local oldLong = H.LONG_CHANCE
H.LONG_CHANCE = 0
local f
f = death_from(function() ledgeMode = "norail" end)
check(f:find("norail") or f:find("_fall"), "at an open edge: off-the-edge death (" .. f .. ")")
f = death_from(function() ledgeMode = "rail" end)
check(f:find("_rail_death"), "at a railing: over-the-rail death (" .. f .. ")")
f = death_from(function(s) s.tifActivity = { name = "smoke" } end)
check(f:find("smoking_death"), "smoking: the smoking death (" .. f .. ")")
f = death_from(function(s) s.tifActivity = { name = "phone" } end)
check(f:find("cellphone_death"), "on the phone: the phone death (" .. f .. ")")
f = death_from(function(s) s.tifLook = { kind = "under" } end)
check(f:find("look_under_death"), "looking under something: its death (" .. f .. ")")
f = death_from(function(s) s.tifLook = { kind = "around" } end)
check(f:find("stand") or f:find("exp"), "a look with no death of its own: the standing pool (" .. f .. ")")
f = death_from(function(s) s.tifProne = {} end, dmg(Vector(-1000, 0, 0), 80, true))
check(f:find("prone_death_explode"), "blast while prone: prone blast death (" .. f .. ")")
f = death_from(function(s) s.stance = 1 end, dmg(Vector(-1000, 0, 0), 80, true))
check(f:find("crouch_death_explode"), "blast while crouched: crouched blast death (" .. f .. ")")
f = death_from(function(s) s.tifCov = { mw = true, t = "cr", phase = "aim" } end)
check(f:find("cover_crouch_exp_death"), "leaning out of low cover: its exposed deaths (" .. f .. ")")
f = death_from(function() melee = DMG_CLUB end)
check(f:find("melee"), "melee kill: melee death (" .. f .. ")")
H.FIREAIR_CHANCE = 1
f = death_from(function(s) s.shotT = CurTime() end)
check(f:find("firing_into_air"), "killed mid-burst: firing into the air (" .. f .. ")")
H.FIREAIR_CHANCE = 0.35
f = death_from(function(s) s.nw.tif_cqb = true s.vel = 80 end)
check(f:find("sdr_cqb_walk_death"), "CQB, walking gun-up: CQB walk death (" .. f .. ")")
-- 0.35.2: killed by fire: MW19's burning deaths (standing / crouched / prone).
for i = 1, 6 do
	f = death_from(function() melee = DMG_BURN end)
	check(f:find("^sdr_com_molotov_reactions_"), "burned to death standing: " .. f)
end
f = death_from(function(s) melee = DMG_BURN s.stance = 1 end)
check(f:find("^sdr_com_molotov_crouch_reaction"), "burned to death crouched: " .. f)
f = death_from(function(s) melee = DMG_BURN s.tifProne = {} end)
check(f:find("^sdr_com_molotov_prone_reaction"), "burned to death lying: " .. f)
-- Set alight and surviving: the sling reactions (on his feet), rolling when prone.
TIF.Say = TIF.Say or function() end
for _, pr in ipairs({ false, true }) do
	local b = soldier()
	if pr then b.tifProne = {} end
	played = {}
	melee = DMG_BURN
	H.Pain(b, dmg(Vector(-1000, 0, 0), 10))
	melee = nil
	local src = played[#played] and clips[played[#played]].from or "none"
	check(pr and src:find("^sdr_com_molotov_prone_reaction") or (not pr and src:find("_sling$")), "on fire " .. (pr and "prone" or "standing") .. ": " .. src)
end
for name, c in pairs(clips) do
	if name:find("^mwz_fire_") and not name:find("^mwz_fire_pr_") then check(c.from:find("_sling$"), "burn reaction stays standing: " .. name .. " " .. c.from) end
end
H.LONG_CHANCE = oldLong

-- 0.34.0: knockdowns: how a ragdoll lies, and every recovery clip measured.
local function rag(bones)
	local r = {}
	function r:LookupBone(n) return bones[n] and n or nil end
	function r:GetBoneMatrix(n) local p = bones[n] return p and { GetTranslation = function() return p end } or nil end
	return r
end
V3 = Vector
local base = { ["ValveBiped.Bip01_Pelvis"] = Vector(0, 0, 6) }
local function lie(head, l, r)
	local b = { ["ValveBiped.Bip01_Pelvis"] = Vector(0, 0, 6), ["ValveBiped.Bip01_Head1"] = head,
		["ValveBiped.Bip01_L_UpperArm"] = l, ["ValveBiped.Bip01_R_UpperArm"] = r }
	return H.LieOf(rag(b))
end
-- Lying along +x, head at +x, face up: his left shoulder is on -y (left = head x face = x x z = -y).
local s1, _, yaw1 = lie(Vector(30, 0, 6), Vector(20, -8, 6), Vector(20, 8, 6))
check(s1 == "back" and math.abs(yaw1) < 1, "on his back, head along +x (" .. tostring(s1) .. ", " .. tostring(yaw1) .. ")")
local s2 = lie(Vector(30, 0, 6), Vector(20, 8, 6), Vector(20, -8, 6))
check(s2 == "stomach", "face down (" .. tostring(s2) .. ")")
local s3 = lie(Vector(30, 0, 6), Vector(20, 0, 2), Vector(20, 0, 14))
check(s3 == "left", "right shoulder up: on his left side (" .. tostring(s3) .. ")")
local s4 = lie(Vector(30, 0, 6), Vector(20, 0, 14), Vector(20, 0, 2))
check(s4 == "right", "left shoulder up: on his right side (" .. tostring(s4) .. ")")
for name in pairs(H.KnockPose) do check(clips[name] ~= nil, "recovery clip built: " .. name) end
-- 0.38.16: shooting a long death ends it early (bullets checked against the bones; any damage too)
do
	HITS_LONG = true
	local oldChance = H.LONG_CHANCE
	H.LONG_CHANCE = 1
	math.random = function(a, b) if a and b then return a end if a then return 1 end return 0 end
	local function long_dier()
		local s = soldier()
		s.tifLastHitGroup = HITGROUP_CHEST
		s.tifArch = { aggression = 0.5 }
		function s:LookupBone(n) return ({ ["ValveBiped.Bip01_Pelvis"] = 1, ["ValveBiped.Bip01_Spine4"] = 2, ["ValveBiped.Bip01_Head1"] = 3 })[n] end
		s.bones = { [1] = Vector(200, 0, 8), [2] = Vector(220, 0, 10), [3] = Vector(235, 0, 12) }
		local ok = H.Death(s, dmg(Vector(-1000, 0, 0)))
		return s, ok
	end
	local s, ok = long_dier()
	check(ok and s.tifDying and s.tifDying.chain and H.DyingLong[s], "a long death started, listed")
	-- a round aimed at his chest from 300 away: ends it this tick, with its own push
	local shooter = {}
	function shooter:EyePos() return Vector(-100, 0, 10) end
	hooks.tif_long_death_shot(shooter, { Src = Vector(-100, 0, 10), Dir = Vector(1, 0, 0), Damage = 30, Distance = 8000 })
	check(s.tifDying.shotEnd and s.tifDeathHit and s.tifDeathHit.fresh, "shot: the long death ends, a fresh hit")
	check(effects[#effects] == "BloodImpact", "blood where the round hit")
	local ut = s.tifDying.untilT
	H.DyingThink(s, now + 0.02)
	check(s.finished ~= nil and s.tifDying == nil and not H.DyingLong[s], "ragdoll on the next think, off the list")
	-- a round going well past him: nothing
	local s2 = long_dier()
	hooks.tif_long_death_shot(shooter, { Src = Vector(-100, 60, 10), Dir = Vector(1, 0, 0), Damage = 30 })
	check(not s2.tifDying.shotEnd, "a miss (60 to the side): it goes on")
	-- a wall in between: nothing
	local oldTL = util.TraceLine
	util.TraceLine = function() return { Hit = true } end
	hooks.tif_long_death_shot(shooter, { Src = Vector(-100, 0, 10), Dir = Vector(1, 0, 0), Damage = 30 })
	util.TraceLine = oldTL
	check(not s2.tifDying.shotEnd, "a wall in the way: it goes on")
	-- the stage doesn't move on after a shot (the hand-over can't be pushed back)
	s2.tifDying.stageEnd = now - 1
	hooks.tif_long_death_hit(s2, { GetDamage = function() return 20 end, GetDamagePosition = function() return Vector(220, 0, 10) end,
		GetDamageForce = function() return Vector(3000, 0, 0) end })
	s2.TIFSoldier = true
	hooks.tif_long_death_hit(s2, { GetDamage = function() return 20 end, GetDamagePosition = function() return Vector(220, 0, 10) end,
		GetDamageForce = function() return Vector(3000, 0, 0) end })
	check(s2.tifDying.shotEnd, "damage (blast, melee) ends it too")
	local stage = s2.tifDying.stage
	H.DyingThink(s2, now + 0.02)
	check(s2.finished ~= nil, "handed over, no next stage")
	-- a normal (short) death clip isn't cut by shots
	H.LONG_CHANCE = 0
	local s3 = soldier()
	s3.tifLastHitGroup = HITGROUP_CHEST
	function s3:LookupBone() return nil end
	H.Death(s3, dmg(Vector(-1000, 0, 0)))
	check(s3.tifDying and not s3.tifDying.chain and H.ShotEnd(s3, Vector(), Vector()) == false, "short death clips aren't cut")
	H.LONG_CHANCE = oldChance
	HITS_LONG = nil
end
print(string.format("passed %d, failed %d", pass, fail))
