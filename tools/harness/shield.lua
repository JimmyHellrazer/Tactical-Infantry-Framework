-- Offline (0.38.20): TIF.Shield (tactics/sv_shield.lua) - human shield scenes.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z)
	if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Clamp = function(v, a, b) return math.min(b, math.max(a, v)) end
math.Rand = function(a, b) return a + (b - a) * 0.5 end
math.AngleDifference = function(a, b) local d = (a - b + 180) % 360 - 180 return d end
function IsValid(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
function isnumber(x) return type(x) == "number" end
function istable(x) return type(x) == "table" end
table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
COLLISION_GROUP_NPC, COLLISION_GROUP_NPC_SCRIPTED, FCVAR_ARCHIVE, MASK_NPCSOLID_BRUSHONLY, DMG_BULLET = 9, 19, 1, 1, 2
local cvOn = "1"
function CreateConVar() return { GetBool = function() return cvOn ~= "0" end } end
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[ev] = fn end, Run = function(ev, ...) hooks["run_" .. ev] = { ... } end }
MASK_SOLID_BRUSHONLY = 2
MASK_SHOT = 3
local shotHits = nil
-- (ground checks hit the floor; sight lines (SH.Seen, MASK_SOLID_BRUSHONLY) are clear)
util = { TraceLine = function(t)
	if t.mask == MASK_SOLID_BRUSHONLY then return { Hit = false, Fraction = 1 } end
	if t.mask == MASK_SHOT then return { Hit = true, Entity = shotHits, Fraction = 0.9 } end
	return { Hit = true, HitPos = Vector(t.endpos.x, t.endpos.y, 0), Fraction = 1 }
end }
local now = 100
function CurTime() return now end
local logs = {}
local plys = {}
player = { Iterator = function() return ipairs(plys) end }
game = { GetWorld = function() return { world = true } end }
function DamageInfo()
	local d = { dmg = 0 }
	function d:SetDamage(x) self.dmg = x end
	function d:SetDamageType() end
	function d:SetAttacker(a) self.att = a end
	function d:SetInflictor() end
	function d:SetDamagePosition() end
	function d:SetDamageForce() end
	return d
end
local function dmginfo(att, amount, blast)
	return { att = att, amount = amount or 30, GetAttacker = function(s) return s.att end,
		ScaleDamage = function(s, k) s.amount = s.amount * k end, GetDamage = function(s) return s.amount end,
		IsExplosionDamage = function() return blast == true end }
end
local played = {}
local clipsOK = true
TIF = {
	Soldiers = {}, NPCs = {}, REL_HOSTILE = -1, REL_ALLY = 1,
	Log = function(...) logs[#logs + 1] = table.concat({ ... }) end, Error = function(...) print("ERR", ...) end,
	Say = function() end,
	Move = { Stop = function(n) n.stopped = true end },
	Weapon = { ForcePistol = function(n) if n.noPistol then return false end n.pistolForced = true return true end },
	GTG = { IsVB = function() return true end, Clip = function(n) return clipsOK and { dur = 2, name = n } or nil end },
	Anim = { STANCE_STAND = 0 },
	Relation = function(a, b) return (a.side and b.side and a.side ~= b.side) and -1 or 1 end,
	IsLiveCombatant = function(e) return IsValid(e) and not e.tifDead end,
}
TIF.Action = {
	Clip = function(npc, n) return clipsOK and { dur = 2, name = n } or nil end,
	Play = function(npc, n) npc.tifAct = { name = n } played[#played + 1] = n return 2 end,
	Loop = function(npc, n) npc.tifAct = { name = n } played[#played + 1] = n return 4 end,
	Clear = function(npc) npc.tifAct = nil end,
}
assert(loadfile(ROOT .. "tif/tactics/sv_shield_data.lua"))()
assert(loadfile(ROOT .. "tif/tactics/sv_shield.lua"))()
local SH = TIF.Shield

local function ent(pos, o)
	o = o or {}
	local e = { pos = Vector(pos), ang = Angle(), hp = o.hp or 100, group = COLLISION_GROUP_NPC, side = o.side }
	function e:GetPos() return Vector(self.pos) end
	function e:SetPos(p) self.pos = Vector(p) end
	function e:SetAngles(a) self.ang = a end
	function e:GetAngles() return self.ang end
	function e:Health() return self.hp end
	function e:GetCollisionGroup() return self.group end
	function e:SetCollisionGroup(g) self.group = g end
	function e:EntIndex() return 7 end
	function e:WorldSpaceCenter() return self.pos + Vector(0, 0, 40) end
	function e:GetTIFStance() return 0 end
	function e:SetNW2String() end
	function e:SetNW2Float() end
	function e:SetNW2Bool() end
	function e:TakeDamageInfo(d) self.killedBy = d.att self.actAtDeath = self.tifAct and self.tifAct.name self.tifDead = true end
	return e
end
local function soldier(pos, side)
	local s = ent(pos, { side = side })
	s.TIFSoldier, s.tifHomeHost, s.tifFire = true, "mw_male", { want = true }
	function s:SetNW2Float() end
	return s
end
local function civilian(pos)
	local c = ent(pos, { hp = 1 })
	c.mw, c.state = true, "wander"
	c.loco = { SetDesiredSpeed = function() end }
	function c:GetClass() return "tif_civilian" end
	function c:SetState(st) self.state = st end
	function c:Play(r) self.role = r return 2 end
	function c:SetCycle() end
	return c
end

-- Sample: the placement table read back
local x, y = SH.Sample("mwsh_idle_vic", 0)
check(math.abs(x - 6) < 2 and math.abs(y + 33) < 2, "hold: the hostage kneels ~33 in to his right (" .. x .. ", " .. y .. ")")
local gx, gy = SH.Sample("mwsh_grab_vic", 0)
check(gy < -70, "grab: she starts ~80 in off his right (" .. gy .. ")")
local ex, ey = SH.Sample("mwsh_grab_vic", 1)
check(math.abs(ey) < 40, "grab: pulled in by its end (" .. ey .. ")")
local mx = SH.Sample("mwsh_grab_vic", 0.5)
check(mx ~= nil, "mid-clip sample")

-- Try: an enemy 400 ahead (+x), a civilian ~82 in toward him, hostile to the player
local plyAim = Vector(-1, 0, 0)
local ply = { side = "player", GetPos = function() return Vector(400, 0, 0) end, Alive = function() return true end,
	EyePos = function() return Vector(400, 0, 60) end, GetAimVector = function() return plyAim end }
plys = { ply }
local bad = soldier(Vector(0, 0, 0), "enemy")
local enemy = soldier(Vector(400, 0, 0), "player")
-- (0.38.27) the scene faces him at the enemy (+x): the grab starts ~82 in to his right-rear
TIF.Soldiers = { bad, enemy }
local sx, sy = SH.Sample("mwsh_grab_vic", 0)
local r0 = math.rad(-SH.FACE)
local civ = civilian(Vector(sx * math.cos(r0) - sy * math.sin(r0) + 15, sx * math.sin(r0) + sy * math.cos(r0) - 10, 0))
local wrong = civilian(Vector(80, 0, 0))   -- right between him and the enemy: not where the grab starts
TIF.Civ = { List = function() return { wrong, civ } end }
math.random = function() return 0 end
local c = { visible = true, ent = enemy }
check(SH.Try(bad, c, now), "an enemy in sight and a civilian where the grab starts: grabbed")
local sc = bad.tifShield
check(sc and civ.tifHeld == sc and civ.state == "held" and not wrong.tifHeld, "the civilian at the grab spot is held")
check(sc and sc.varName == "mw19", "the player sees it: the MW19 grab")
check(sc and math.abs(math.AngleDifference(sc.yaw + SH.FACE, 0)) <= SH.MW_SWING, "the scene faces him near the enemy (" .. tostring(sc and sc.yaw) .. ")")
check(bad.group == COLLISION_GROUP_NPC_SCRIPTED and civ.group == COLLISION_GROUP_NPC_SCRIPTED, "both pass through each other")
check(played[#played] == "mwsh_grab_att" and civ.role == "mwsh_grab_vic", "the grab pair plays")
check(civ.pos.y < -50, "she starts on the grab's spot, to his right")
check(SH.Busy(bad, now) and bad.tifFire.want == false, "busy: no firing, no moving")
-- second one: busy captor
check(not SH.Try(bad, c, now + 10), "one scene per captor")

-- line of fire: a hostage between a shooter and the captor
local hs = SH.Hostages()
check(hs[civ] == bad, "hostage listed for line-of-fire checks")
local src = io.open(ROOT .. "tif/npc/sv_weapon.lua"):read("*a")
check(src:find("TIF.Shield.Hostages()", 1, true) ~= nil, "sv_weapon holds fire through hostages")

-- ticks: grab -> idle
now = now + 2.1
hooks.Tick()
check(sc.phase == "idle" and played[#played] == "mwsh_idle_att", "after the grab: holding")
-- (0.38.28) held, she kneels in front of him (between him and the enemy), not at his side
do
	local f = math.rad(sc.yaw + SH.FACE)
	local d = civ.pos - bad.pos
	local ahead = d.x * math.cos(f) + d.y * math.sin(f)
	local side = -d.x * math.sin(f) + d.y * math.cos(f)
	check(ahead > 20 and math.abs(side) < 15, "held: she's in front of him (" .. string.format("%.0f ahead, %.0f to the side", ahead, side) .. ")")
end
-- the hostage's own hits on him don't count; the captor's on her neither
check(hooks.EntityTakeDamage(bad, dmginfo(civ, 30)) == true and sc.phase == "idle", "her (nonexistent) hits ignored")
-- an enemy close: he shoves her away (rescue)
enemy.pos = Vector(90, 0, 0)
now = now + 0.5
hooks.Tick()
check(sc.phase == "rescue", "enemy within reach: he shoves her away")
now = now + 2.1
hooks.Tick()
check(sc.done and civ.state == "flee" and not civ.tifHeld and bad.tifShield == nil, "rescue done: she flees, he fights")
check(bad.group == COLLISION_GROUP_NPC and civ.group == COLLISION_GROUP_NPC, "collisions back")
check(hooks.run_TIF_ShieldEnd and hooks.run_TIF_ShieldEnd[2] == "rescue", "TIF_ShieldEnd(rescue)")

-- semi-scripted: held, no rescue; a hit on him -> death pair, killed at its end
local bad2 = soldier(Vector(1000, 0, 0), "enemy")
local civ2 = civilian(Vector(1006, -33, 0))
local sc2 = SH.Start(bad2, civ2, { held = true, noRescue = true, yaw = 0 })
check(sc2 and sc2.phase == "idle", "held: starts holding (no grab)")
enemy.pos = Vector(1010, 0, 0)
now = now + 1
hooks.Tick()
check(sc2.phase == "idle", "noRescue: an enemy close doesn't make him let go")
local shooter = soldier(Vector(1400, 0, 0), "player")
local d = dmginfo(shooter, 30)
check(hooks.EntityTakeDamage(bad2, d) == true and d.amount == 0 and sc2.phase == "death", "a hit on him: the death pair, the damage blocked")
now = now + 2.1
hooks.Tick()
check(bad2.tifDead and bad2.killedBy == shooter and bad2.tifNoDeathClip, "killed at the clip's end by the shooter, corpse from its last frame")
check(bad2.actAtDeath == "mwsh_death_att" and bad2.tifAct and bad2.tifAct.name == "mwsh_death_att", "killed while still in the death clip, and it stays (the corpse is posed from it: no A-pose)")
check(civ2.state == "flee", "she runs")
-- a killing blast: just dies
local bad3 = soldier(Vector(2000, 0, 0), "enemy")
local civ3 = civilian(Vector(2006, -33, 0))
local sc3 = SH.Start(bad3, civ3, { held = true, yaw = 0 })
bad3.hp = 20
check(hooks.EntityTakeDamage(bad3, dmginfo(shooter, 200, true)) == nil, "a blast that kills him outright goes through")
bad3.tifDead = true
hooks.Tick()
check(sc3.done and civ3.state == "flee", "captor killed: she runs")
-- hostage killed: he lets go
local bad4 = soldier(Vector(3000, 0, 0), "enemy")
local civ4 = civilian(Vector(3006, -33, 0))
local sc4 = SH.Start(bad4, civ4, { held = true, yaw = 0 })
civ4.hp = 0
hooks.Tick()
check(sc4.done and bad4.tifShield == nil, "hostage killed: he lets go and fights")
-- off / no players hostile: no grabs
cvOn = "0"
local bad5 = soldier(Vector(0, 500, 0), "enemy")
check(not SH.Try(bad5, { visible = true, ent = enemy }, now + 100), "tif_shield 0: none")
cvOn = "1"
-- API + hooks wiring
local api = io.open(ROOT .. "tif/api/sv_api.lua"):read("*a")
check(api:find("function API.HumanShield(captor, civ, opts)", 1, true) ~= nil, "API.HumanShield")
local brain = io.open(ROOT .. "tif/npc/sv_brain.lua"):read("*a")
check(brain:find("TIF.Shield.Busy(npc, now)", 1, true) and brain:find("TIF.Shield.Try(npc, c, now)", 1, true), "brain: busy chain + engage")
local civsrc = io.open(ROOT .. "entities/tif_civilian.lua"):read("*a")
check(civsrc:find('if self.state == "held" then return end', 1, true) and civsrc:find('elseif st == "held" then', 1, true), "civilian: held state, scares don't break it")
-- (0.38.28) Clean House: no player sees it -> held in front from the start
do
	plyAim = Vector(1, 0, 0)   -- looking away
	local cap = soldier(Vector(5000, 0, 0), "enemy")
	local foe = soldier(Vector(5400, 0, 0), "player")
	local h1 = civilian(Vector(5090, 60, 0))
	TIF.Civ = { List = function() return { h1 } end }
	TIF.Soldiers = { cap, foe }
	enemy.pos = Vector(-9000, 0, 0)
	played = {}
	check(SH.Try(cap, { visible = true, ent = foe }, now), "unseen: a scene starts")
	local s1 = cap.tifShield
	check(s1 and s1.varName == "ch" and played[1] == "mwsc_aim_start_att" and h1.role == "mwsc_aim_start_vic", "unseen: Clean House, starting held (aim lead-in)")
	local f = math.rad(s1.yaw + SH.CH_FACE)
	local d = h1.pos - cap.pos
	check(d.x * math.cos(f) + d.y * math.sin(f) > 12, "Clean House: she's held in front of him")
	check(math.abs(math.AngleDifference(s1.yaw + SH.CH_FACE, 0)) < 1, "Clean House: he faces the enemy")
	now = now + 2.1 hooks.Tick()
	check(s1.phase == "hold" and played[#played] == "mwsc_aim_att", "then the aim hold")
	-- she's shot in the head: her headshot death with his reaction; she's killed at its end, then he fights on
	local dh = dmginfo(foe, 30)
	dh.GetDamagePosition = function() return h1.pos + Vector(0, 0, 58) end
	check(hooks.EntityTakeDamage(h1, dh) == true and dh.amount == 0 and s1.phase == "vdeath_hs", "hostage headshot: her headshot death, his reaction")
	check(played[#played] == "mwsc_live_att" and h1.role == "mwsc_death_hs_vic", "...the pair plays")
	now = now + 2.1 hooks.Tick()
	check(h1.tifDead and h1.killedBy == foe, "she's killed on it, by the shooter")
	check(s1.done and cap.tifShield == nil, "then he lets go and fights on")
	-- the captor shot: his neck-shot death with her live clip (cut before she grabs his gun)
	local cap2 = soldier(Vector(7000, 0, 0), "enemy")
	local h2 = civilian(Vector(7020, 0, 0))
	local s2 = SH.Start(cap2, h2, { variant = "ch", held = true, yaw = 0 })
	check(s2 and s2.phase == "hold", "semi-scripted Clean House: held straight away")
	local d2 = dmginfo(foe, 30)
	check(hooks.EntityTakeDamage(cap2, d2) == true and s2.phase == "death" and h2.role == "mwsc_live_vic", "captor shot: his death, her live clip")
	now = now + 2.1 hooks.Tick()
	check(cap2.tifDead and cap2.actAtDeath == "mwsc_death_att" and h2.state == "flee", "he dies on his clip (posed), she flees")
	-- a body removed as it dies reports the death, not "removed"
	local cap3 = soldier(Vector(9000, 0, 0), "enemy")
	local h3 = civilian(Vector(9020, 0, 0))
	local s3 = SH.Start(cap3, h3, { held = true, yaw = 0 })
	h3.hp = 0
	hooks.EntityRemoved(h3)
	check(s3.done and hooks.run_TIF_ShieldEnd[2] == "hostage_killed", "mw19 hostage killed (body removed): hostage_killed")
end
-- (0.38.29) "the animation of the human shield can be interrupted by them noticing u": his body is locked to the
-- scene; anything that still replaces his clip is put back in step
do
	local cap = soldier(Vector(11000, 0, 0), "enemy")
	local h = civilian(Vector(11020, 0, 0))
	local s = SH.Start(cap, h, { held = true, yaw = 0 })
	check(cap.tifActLock == true, "scene start: his body locked")
	cap.tifAct = { name = "mwe_newenemy_6" }
	now = now + 0.1 hooks.Tick()
	check(cap.tifAct and cap.tifAct.name == s.att, "a reaction that got in: the scene's clip back")
	SH.Finish(s, "test")
	check(cap.tifActLock == nil, "released: unlocked")
	-- the hostage's state can't leave "held" while grabbed (a flee / hide still running when she was taken)
	local csrc = io.open(ROOT .. "entities/tif_civilian.lua"):read("*a")
	local setFn = csrc:match("(function ENT:SetState%(st%).-\nend)")
	ENT = {}
	assert(load(setFn))()
	local c = { state = "held", tifHeld = {}, SetNW2String = function() end }
	setmetatable(c, { __index = ENT })
	c:SetState("hide")
	check(c.state == "held", "held: her own behaviour can't switch her state")
	c.tifHeld = nil
	c:SetState("flee")
	check(c.state == "flee", "let go: it can")
	local cflat = csrc:gsub("%s+", " ")
	check(cflat:find("self.gone or self.tifHeld then return \"interrupted\" end", 1, true) and cflat:find("or self.tifHeld then done = false break end", 1, true)
		and cflat:find("or self.tifHeld then return false end", 1, true) and cflat:find("or self.tifHeld then return leaving() end", 1, true),
		"her walk / one-shot / wait / hide loops stop when she's grabbed")
	check(csrc:find("self.civRole ~= self.civHoldLast then", 1, true) ~= nil and csrc:find("self:SetCycle(0)", 1, true) ~= nil, "released: her last scene clip doesn't loop")
	-- the real Act.Play / Act.Clear honour the lock
	local saved = TIF.Action
	TIF.GTG.MW_HOST = "mw_male"
	TIF.Warn = function() end
	assert(loadfile(ROOT .. "tif/npc/sv_action.lua"))()
	local A = TIF.Action
	local nw = {}
	local npc = { tifHomeHost = "mw_male", tifHostId = "mw_male", tifActLock = true, GetPos = function() return Vector() end,
		GetAngles = function() return Angle() end, SetNW2String = function(_, k, v) nw[k] = v end, SetNW2Float = function() end }
	check(A.Play(npc, "mwe_newenemy_6") == nil and npc.tifAct == nil, "locked: other clips refused")
	check(A.Play(npc, "mwsh_idle_att", { lockOK = true }) ~= nil and npc.tifAct.name == "mwsh_idle_att", "the scene's own clip plays")
	A.Clear(npc)
	check(npc.tifAct ~= nil, "locked: an ordinary Clear doesn't drop it")
	A.Clear(npc, true)
	check(npc.tifAct == nil, "the scene's forced Clear does")
	TIF.Action = saved
end
-- (0.38.28) paired fights more likely: 50-160 in, crouched too, 60%
local msrc = io.open(ROOT .. "tif/tactics/sv_melee_mw.lua"):read("*a")
check(msrc:find("M.FIGHT_CHANCE = 0.6", 1, true) and msrc:find("M.FIGHT_MIN, M.FIGHT_MAX = 50, 160", 1, true) and msrc:find("free(target, true)", 1, true), "paired fights: wider window, crouched too, 60%")
-- 2026-11-21: clean house forces a pistol (no pistol: no ch scene); held long, a hostile soldier takes the shot
do
	for sc in pairs(SH.List) do SH.Finish(sc, "t") end
	local cap = soldier(Vector(0, 0, 0), "red")
	local civ = civilian(Vector(30, 0, 0))
	local sc = SH.Start(cap, civ, { variant = "ch", held = true })
	check(sc and cap.pistolForced, "clean house: a pistol forced into his hand")
	if sc then SH.Finish(sc, "t") end
	local cap2 = soldier(Vector(500, 0, 0), "red")
	cap2.noPistol = true
	check(SH.Start(cap2, civilian(Vector(530, 0, 0)), { variant = "ch", held = true }) == nil, "clean house with no pistol to be had: not started")
	-- the AI shot
	local cap3 = soldier(Vector(0, 900, 0), "red")
	function cap3:LookupBone() return 1 end
	function cap3:GetBoneMatrix() return { GetTranslation = function() return Vector(0, 900, 64) end } end
	local civ3 = civilian(Vector(30, 900, 0))
	local sc3 = SH.Start(cap3, civ3, { held = true, noRescue = true, hold = 999 })
	check(sc3 ~= nil, "a held scene")
	local shooter = soldier(Vector(400, 900, 0), "blue")
	shooter.tifWep = { def = { sound = "x" } }
	function shooter:EyePos() return self.pos + Vector(0, 0, 64) end
	function shooter:EmitSound(s) self.fired = s end
	sound = { GetProperties = function() return nil end }
	TIF.Soldiers = { shooter }
	shotHits = cap3
	local realRand = math.random
	math.random = function(a, b) if a then return a end return 0.1 end
	local tick = hooks["Tick"]
	for k = 1, 10 do now = now + 1 tick() end
	check(sc3 and sc3.phase ~= sc3.var.shot and not shooter.fired, "before AI_SHOT_AFTER: nobody takes it")
	for k = 1, 10 do now = now + 1 tick() end
	check(shooter.fired ~= nil and sc3.killer == shooter and sc3.phase == sc3.var.shot, "held " .. SH.AI_SHOT_AFTER .. "+ s: a hostile soldier takes the shot, the captor's death plays")
	-- through the hostage: no shot
	for sc in pairs(SH.List) do SH.Finish(sc, "t") end
	local cap4 = soldier(Vector(0, 1800, 0), "red")
	function cap4:LookupBone() return 1 end
	function cap4:GetBoneMatrix() return { GetTranslation = function() return Vector(0, 1800, 64) end } end
	local civ4 = civilian(Vector(30, 1800, 0))
	local sc4 = SH.Start(cap4, civ4, { held = true, noRescue = true, hold = 999 })
	shooter.pos, shooter.fired = Vector(400, 1800, 0), nil
	shotHits = civ4
	for k = 1, 25 do now = now + 1 tick() end
	check(sc4 and not shooter.fired and sc4.phase ~= sc4.var.shot, "the hostage in the line: no shot")
	math.random = realRand
	TIF.Soldiers = {}
	for sc in pairs(SH.List) do SH.Finish(sc, "t") end
end
print(string.format("passed %d, failed %d", pass, fail))
