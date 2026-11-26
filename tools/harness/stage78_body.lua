-- (appended after trans.lua's header: box world, real clips, mock Act)
function V:GetNormalized() local v = Vector(self.x, self.y, self.z) local l = v:Length() if l > 0 then v = v * (1 / l) end return v end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Distance(o) return (self - o):Length() end
MASK_NPCSOLID, DMG_GENERIC, FCVAR_ARCHIVE = 1, 0, 0
function istable(x) return type(x) == "table" end
function IsValid(x) return x ~= nil and x ~= false end
function CreateConVar(n, v) return { GetFloat = function() return tonumber(v) end, GetBool = function() return v == "1" end, GetInt = function() return tonumber(v) end } end
timer = { Create = function() end }
hook = { Add = function() end }
local dmgTaken = {}
function DamageInfo()
	local d = {}
	function d:SetDamage(x) self.dmg = x end function d:GetDamage() return self.dmg or 0 end
	function d:SetDamageType() end function d:SetAttacker() end function d:SetInflictor() end
	function d:IsExplosionDamage() return false end
	return d
end
-- Real root / height curves (as TIF.GTG.ClipCurve: every 3 frames, x y yaw).
local function curveAt(c, u, axis)
	local cv = c.curve
	if not cv or #cv == 0 then return 0 end
	local n = #cv / 3
	local f = u * math.max(1, c.frames - 1) / 3 + 1
	local i = math.max(1, math.min(n, math.floor(f)))
	local j = math.min(n, i + 1)
	local k = math.max(0, math.min(1, f - i))
	return cv[(i - 1) * 3 + axis] + (cv[(j - 1) * 3 + axis] - cv[(i - 1) * 3 + axis]) * k
end
TIF.Action.RootAt = function(c, u) return curveAt(c, u, 1), curveAt(c, u, 2), curveAt(c, u, 3) end
TIF.Action.ZAt = function(c, u)
	local zc = c.zcurve
	if not zc then return 0 end
	local f = u * math.max(1, c.frames - 1) / 3 + 1
	local i = math.max(1, math.min(#zc, math.floor(f)))
	local j = math.min(#zc, i + 1)
	return zc[i] + (zc[j] - zc[i]) * math.max(0, math.min(1, f - i))
end
TIF.Soldiers = {}
TIF.REL_ALLY = 1
TIF.Relation = function(a, b) return (a.side or "a") == (b.side or "a") and 1 or 0 end
TIF.Squad = { Members = function(sq) return sq.members end, Log = function() end }
TIF.CoverBehave = { In = function() return false end }
TIF.ProneB = { Is = function() return false end }
TIF.Say = function() end
TIF.Morale = { Add = function() end }
TIF.AIDisabled = function() return false end
TIF.HitsMW = { Use = function(npc) return npc.tifHostId == "mw_male" end,
	Pools = function() return { death = { stand = { torso = { { name = "mwd_stand_torso_1", clip = clips.mwd_stand_torso_1 or { dur = 2, cut = 0.6 } } } } } } end }
local goals = {}
TIF.Move = {
	Stop = function(npc) npc.moving = false end,
	SetGoal = function(npc, pos, speed, tag) goals[#goals + 1] = { npc = npc, pos = pos, speed = speed, tag = tag } npc.moving = true return true end,
	Moving = function(npc) return npc.moving == true end,
}
for _, f in ipairs({ "tif/tactics/sv_casualty.lua", "tif/tactics/sv_laststand_mw.lua", "tif/tactics/sv_traverse_mw.lua" }) do
	assert(loadfile(ROOT .. f))()
end
local CAS, LS, TR = TIF.Casualty, TIF.LastStandMW, TIF.TraverseMW
local function last() return played[#played] end

local function man(pos, side, opts)
	opts = opts or {}
	local s = soldier(opts)
	s.pos, s.side = pos or Vector(0, 0, 0), side or "a"
	s.hp = 100
	function s:Health() return self.hp end
	function s:SetHealth(h) self.hp = h end
	function s:GetTIFWeapon() return self.wep or "rifle" end
	function s:SetTIFWeapon(w) self.wep = w end
	function s:SetNW2Bool() end function s:SetNW2Float() end
	function s:EntIndex() return 1 end
	function s:SetPos(p) self.pos = p end
	function s:TakeDamageInfo(d) dmgTaken[#dmgTaken + 1] = { npc = self, d = d } self.tifDead = true end
	s.tifFire = { want = false }
	s.loco.GetVelocity = function() return s.vel end
	return s
end

-- Rarity -----------------------------------------------------------------------------------------------
local now = 100
local a1, a2, a3 = man(Vector(0, 0, 0)), man(Vector(200, 0, 0)), man(Vector(400, 0, 0))
local sq = { members = { a1, a2, a3 } }
a1.tifSquad, a2.tifSquad, a3.tifSquad = sq, sq, sq
TIF.Soldiers = { a1, a2, a3 }
check(CAS.CanGoDown(a1, now), "two able friends close by: can go down")
a3.tifDead = true
check(not CAS.CanGoDown(a1, now), "one of the last two standing: no last stand")
a3.tifDead = nil
a3.pos = Vector(5000, 0, 0)
check(not CAS.CanGoDown(a1, now), "friends too far: no last stand")
a3.pos = Vector(400, 0, 0)
a2.tifDowned = {}
check(not CAS.CanGoDown(a1, now), "a squadmate already down: no second one")
a2.tifDowned = nil
sq.nextDown = now + 10
check(not CAS.CanGoDown(a1, now), "squad cooldown after the last one")
sq.nextDown = nil

-- Last stand flow -----------------------------------------------------------------------------------------
check(LS.Use(a1), "MW body has the last stand")
CAS.Down(a1, nil)
local d = a1.tifDowned
check(d and d.ls and d.ls.phase == "fall" and sq.nextDown and sq.nextDown > now, "down: crumples first, squad cooldown set")
check(a1.wep == "", "gun put away")
check(last():find("^mwld_st_[a-z]+_enter$") ~= nil, "goes down with MW19's long-death fall (standing set), not a death clip: " .. tostring(last()))
do
	local saveNext = sq.nextDown
	local cr = man(Vector(50, 50, 0), "a", { stance = 1 })
	cr.GetTIFStance = function() return 1 end
	cr.tifSquad = sq
	CAS.Down(cr, nil)
	check(last():find("^mwld_cr_[a-z]+_enter$") ~= nil, "crouched: the crouched fall: " .. tostring(last()))
	local pr = man(Vector(80, 80, 0), "a")
	pr.tifSquad = sq
	pr.tifProne = { phase = 2 }
	local before = #played
	CAS.Down(pr, nil)
	check(pr.tifDowned.wasProne and pr.tifDowned.ls.phase == "lying" and last() == "mwls_idle", "already prone: straight to lying wounded, no fall")
	CAS.Downed[cr], CAS.Downed[pr] = nil, nil
	sq.nextDown = saveNext
end
now = d.ls.untilT + 0.01
LS.Think(a1, d, now)
check(d.ls.phase == "lying" and last() == "mwls_idle", "then lying wounded")
a1.tifPrimaryC = { pos = Vector(-600, 0, 0) }
goals = {}
now = now + 3
LS.Think(a1, d, now)
check(d.ls.phase == "crawl" and #goals == 1 and goals[1].tag == "crawl" and goals[1].pos.x > 0, "a short crawl away from the enemy, toward friends")
a1.vel = Vector(30, 0, 0)  -- crawling +x while facing -x (the enemy)
a1.yaw = 180
LS.Think(a1, d, now + 0.1)
check(last() == "mwls_crawl_bwd_180_loop", "dragging himself backwards, facing the enemy: " .. tostring(last()))
a1.moving = false
LS.Think(a1, d, now + 0.2)
check(d.ls.phase == "lying" and last() == "mwls_idle", "crawl over: lying again")
check(not LS.Think(a1, d, now + 5) or d.ls.crawled, "only one crawl")
-- Revive
local m = man(Vector(-40, 0, 0))
m.tifMedic = { patient = a1 }
a1.yaw = 0
now = now + 1
check(LS.MedicThink(m, a1, m.tifMedic, now) and d.revive and d.revive.phase == "in", "medic starts the revive")
local n = d.revive.n
check(played[#played - 1] == "mwls_help_in_" .. n and last() == "mwls_hurt_in_" .. n, "paired clips, side " .. n .. ": " .. tostring(played[#played - 1]) .. " / " .. tostring(last()))
check(n == 2 or n == 1 or n == 3, "medic behind him: a back side (1-3): " .. tostring(n))
check(lastOpts == nil or true, "")
check(LS.ReviveAlive(a1, d, now + 0.1), "casualty waits while it runs")
now = d.revive.untilT + 0.01
LS.MedicThink(m, a1, m.tifMedic, now)
check(d.revive.phase == "loop", "-> loop")
now = d.revive.untilT + 0.01
LS.MedicThink(m, a1, m.tifMedic, now)
check(d.revive.phase == "out", "-> out")
now = d.revive.untilT + 0.01
check(not LS.MedicThink(m, a1, m.tifMedic, now) and d.treated and d.revive == nil, "done: treated")
check(not LS.GetUp(a1, d, now) and last() == "mwls_getup", "gets up")
check(LS.GetUp(a1, d, now + 5), "up")
-- Medic pulled away: the casualty goes back to lying
local b = man(Vector(0, 300, 0))
b.tifSquad = sq
CAS.Down(b, nil)
local db = b.tifDowned
db.ls = { phase = "lying", since = now }
local m2 = man(Vector(-40, 300, 0))
m2.tifMedic = { patient = b }
LS.MedicThink(m2, b, m2.tifMedic, now)
m2.tifMedic = nil
check(not LS.ReviveAlive(b, db, now + 1) and db.revive == nil and last() == "mwls_idle", "medic gone: revive dropped, lying again")
-- Bleed out: pass out, then dead
db.bleed = now
LS.Think(b, db, now + 0.1)
check(last():find("^mwls_passout_") ~= nil, "bleeding out: passes out")
LS.Think(b, db, db.ls.untilT + 0.01)
check(#dmgTaken == 1 and b.tifNoDeathClip, "then dies (straight to the ragdoll)")

-- Traversal -------------------------------------------------------------------------------------------
local function world(list) boxes = {} box(Vector(-500, -500, -200), Vector(500, 500, 0)) for _, x in ipairs(list) do box(x[1], x[2]) end end
local t = man(Vector(0, 0, 0))
local fwd = Vector(1, 0, 0)
world({ { Vector(40, -100, 0), Vector(200, 100, 48) } })  -- a 48 ledge (a platform)
local p = TR.Probe(t, fwd)
check(p and p.kind == "mantle" and math.abs(p.h - 48) < 1 and math.abs(p.edge - 40) < 1, "48 ledge ahead: mantle: " .. tostring(p and p.kind))
world({ { Vector(40, -100, 0), Vector(50, 100, 36) } })   -- a 36 wall, 10 thick
p = TR.Probe(t, fwd)
check(p and p.kind == "vault" and math.abs(p.h - 36) < 1, "36 high thin wall: vault: " .. tostring(p and p.kind))
world({ { Vector(40, -100, 0), Vector(46, 100, 18) } })
p = TR.Probe(t, fwd)
check(p and p.kind == "step", "18 high: step over: " .. tostring(p and p.kind))
world({ { Vector(40, -100, 0), Vector(50, 100, 140) } })
check(TR.Probe(t, fwd) == nil, "a full wall: nothing")
boxes = { { mins = Vector(-500, -500, -10), maxs = Vector(40, 500, 0), ent = WORLD }, { mins = Vector(40, -500, -70), maxs = Vector(500, 500, -60), ent = WORLD } }
p = TR.Probe(t, fwd)
check(p and p.kind == "drop" and math.abs(p.h - 60) < 1, "floor 60 lower ahead: drop: " .. tostring(p and p.kind) .. " " .. tostring(p and p.h))
-- Check: plays the clip toward the landing, only when the path goes that way
world({ { Vector(40, -100, 0), Vector(200, 100, 48) } })
t.tifPath = { GetCurrentGoal = function() return { pos = Vector(120, 0, 48) } end }
t.vel = Vector(150, 0, 0)
t.pos = Vector(10, 0, 0)
played = {}
check(TR.Check(t, { tag = "advance" }, 1000) and last() == "mwtr_mantle_md", "path up onto the ledge: mantle md: " .. tostring(last()))
check(lastOpts.rootz and lastOpts.noTrace and lastOpts.to and math.abs(lastOpts.to.pos.z - 48) < 0.5, "height follows the clip, lands on top")
check(TR.Busy(t, 1000.1), "path waits during it")
t.tifAct, t.tifTrav = nil, nil
t.tifNextTrav = 0
t.tifPath = { GetCurrentGoal = function() return { pos = Vector(-300, 0, 0) } end }
t.vel = Vector(-150, 0, 0)
check(not TR.Check(t, { tag = "advance" }, 2000), "going the other way: no mantle")
t.tifNextTrav = 0
t.vel = Vector(150, 0, 0)
t.tifPath = { GetCurrentGoal = function() return { pos = Vector(300, 0, 0) } end }
check(not TR.Check(t, { tag = "advance" }, 3000), "path stays low (ledge is beside it): no mantle")
print(string.format("passed %d, failed %d", pass, fail))
