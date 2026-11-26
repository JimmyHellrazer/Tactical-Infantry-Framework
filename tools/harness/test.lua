-- Offline run of tactics/sv_cover_mw.lua with the real generated clip data (tif_mw_anims) and a mock world:
-- a wall along the line x = 0 (solid for x < 0) from y = -200 to y = 40, so a spot at (20, 0) has its left
-- edge (facing the wall, i.e. facing -x, left is -y... see below) checked by traces. ROOT, CLIPS set by runner.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end

-- Vector / Angle -----------------------------------------------------------------------------------------
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
V.__mul = function(a, b)
	if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
	return Vector(a.x * b, a.y * b, a.z * b)
end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:Length2DSqr() return self.x ^ 2 + self.y ^ 2 end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function V:Distance(o) return math.sqrt(self:DistToSqr(o)) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)), p = 0, r = 0 } end
vector_origin = Vector()
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
math.Rand = function(a, b) return (a + b) / 2 end
math.AngleDifference = function(a, b) local d = (a - b + 180) % 360 - 180 return d end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
local now = 100
function CurTime() return now end

-- World: wall face at x = 0 between y = -200 and y = 40 (the wall body is x < 0) --------------------------
util = {}
function util.TraceLine(t)
	local a, b = t.start, t.endpos
	if a.z > 0 and b.z < 0 and math.abs(a.x - b.x) < 0.01 and math.abs(a.y - b.y) < 0.01 then
		return { Hit = true, HitPos = Vector(a.x, a.y, 0) }
	end
	if a.x > 0 and b.x <= 0 then
		local f = a.x / (a.x - b.x)
		local y = a.y + (b.y - a.y) * f
		if y >= -200 and y <= 40 then return { Hit = true, HitPos = Vector(0, y, a.z) } end
	end
	return { Hit = false }
end

function util.TraceHull(t) local r = util.TraceLine({ start = t.start + Vector(0, 0, 20), endpos = t.endpos + Vector(0, 0, 20) }) return r end

-- TIF mocks ------------------------------------------------------------------------------------------------
TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local played = {}
TIF = {
	GTG = {
		IsVB = function(id) return id == "mw_male" end,
		Clip = function(name, id) return id == "mw_male" and clips[name] or nil end,
		WeaponKind = function(c) return c == "shotgun" and "shotgun" or "rifle" end,
		WeaponDef = function(c) return { hold = c == "pistol" and "pistol" or "carbine" } end,
	},
	Anim = { MODE_AIM = 1, STANCE_STAND = 0, STANCE_CROUCH = 1 },
	Prof = { Begin = function() end, End = function() end },
	Say = function() end,
	Cover = { HUG = 20, EDGE_STEP = 36, HEAD = 60, MASK = 1, StillGood = function() return true end, Release = function() end },
	Move = { Stop = function(npc) npc.tifMove.goal = nil npc.stopped = true end, SetGoal = function(npc, pos) npc.tifMove.goal = pos return true end },
	Weapon = { Reloading = function(npc) return npc.reloading end, StartReload = function(npc) npc.reloading = true end },
}
TIF.Action = {
	Play = function(npc, name, opts)
		local c = clips[name]
		if not c then return nil end
		played[#played + 1] = name
		npc.tifAct = { name = name, opts = opts }
		if opts and opts.to then npc.pos, npc.yaw = opts.to.pos, opts.to.yaw end
		return c.dur
	end,
	Loop = function(npc, name) played[#played + 1] = name npc.tifAct = { name = name, loop = true } return 1 end,
	Clear = function(npc) npc.tifAct = nil end,
}
local left
TIF.CoverBehave = {
	SetPhase = function(npc, cov, phase, t) cov.phase, cov.t0 = phase, t end,
	PickSide = function(pt, threat)
		local d = threat - pt.pos
		local function dir(y) return Vector(math.cos(math.rad(y)), math.sin(math.rad(y)), 0) end
		return dir(pt.ny - 90):Dot(d) >= dir(pt.ny + 90):Dot(d) and "l" or "r"
	end,
	Leave = function(npc, why) left = why npc.tifCov = nil end,
}
-- grenade bits
FCVAR_ARCHIVE = 0
function CreateConVar() return { GetBool = function() return true end } end
function IsValid(x) return x ~= nil and x ~= false end
TIF.Soldiers = {}
TIF.REL_HOSTILE = -1
TIF.FactionRelation = function(a, b) return a ~= b and -1 or 1 end
local supp, grenades = {}, {}
TIF.Supp = { Add = function(s, a) supp[#supp + 1] = s end }
TIF.Say = function(n, ev) n.said = ev end
ents = { Create = function(cls)
	local g = { cls = cls }
	function g:SetPos(p) self.pos = p end
	function g:SetOwner(o) self.owner = o end
	function g:Spawn() end
	function g:Activate() end
	function g:SetSaveValue() end
	function g:Fire(i, v) self.fuse = tonumber(v) end
	function g:SetFuse(t) self.fuse = t end
	function g:SetKind(k) self.kind = k end
	function g:GetPhysicsObject() return { SetVelocity = function(_, v) g.vel = v end, AddAngleVelocity = function() end } end
	grenades[#grenades + 1] = g
	return g
end }
local fn, err = loadfile(ROOT .. "tif/tactics/sv_cover_mw.lua")
if not fn then error(err) end
fn()
local MW = TIF.CoverBehave.MW
MW.CROUCH_CORNER = -1 -- standing corners unless a test asks (0.33: crouched corners are a random share)
MW.SIDE_CHANCE = 0    -- no beside-cover fights unless a test asks (2026-11-20)

-- A soldier ------------------------------------------------------------------------------------------------
local npc = { tifHomeHost = "mw_male", pos = Vector(200, -60, 0), yaw = 180, nw = {}, tifFire = {},
	tifArch = { coverPause = { 1, 2 }, coverBurst = { 1.5, 2.5 }, loseContact = 6, aggression = 0.6 },
	tifMove = {}, tifWep = { ammo = 30, clip = 30 }, vel = 200 }
function npc:GetPos() return self.pos end
function npc:SetPos(p) self.pos = p end
function npc:GetAngles() return Angle(0, self.yaw, 0) end
function npc:SetAngles(a) self.yaw = a.y end
function npc:GetNW2Float(k, d) return self.nw[k] or d end
function npc:GetNW2Bool(k, d) if self.nw[k] ~= nil then return self.nw[k] end return d end
function npc:SetNW2Float(k, v) self.nw[k] = v end
npc.loco = { GetVelocity = function() return Vector(npc.vel, 0, 0) end }
npc.tifGrenades = 0 -- (the cover frags have their own test below; none here, they broke the flash step)

check(MW.Use(npc), "MW cover used on the MW body")
-- Cover spot 20 in front of the wall (normal +x, ny = 0), 36 short of the left... edge test below.
-- Facing the wall means facing -x (yaw 180); its left is -y... TIF: edge "l" is along ny - 90 = -90 => -y.
-- The wall ends at y = 40, i.e. along +y = ny + 90 = TIF's "r" side. So the soldier should take the right corner.
local pt = { pos = Vector(20, 0, 0), ny = 0, normal = Vector(1, 0, 0), high = true, edgeL = false, edgeR = true, canShoot = true }
local cov = { pt = pt, origin = pt.pos, ny = 0, high = true, side = "l", canShoot = true }
npc.tifCov = cov
MW.Prepare(npc, cov)
check(cov.side == "r" and cov.t == "rs", "no left edge -> right corner (rs), got " .. tostring(cov.t))
check(cov.edgeR and cov.edgeR >= 36 and cov.edgeR <= 44, "right edge found near y = 40: " .. tostring(cov.edgeR))
check(math.abs(cov.origin.x - 16) < 0.01, "node 16 from the wall: " .. cov.origin.x)
check(math.abs(cov.origin.y - (cov.edgeR - 10)) < 0.01, "node 10 short of the right edge: " .. cov.origin.y)
check(cov.hy == 90, "rs hide faces along the wall toward the corner (ny + 90): " .. cov.hy)

-- Arrive: the soldier comes from behind-left of the node (away from the wall, toward -y).
local function enemy(visible) return { pos = Vector(-600, 300, 0), ent = { WorldSpaceCenter = function() return Vector(-600, 300, 40) end },
	seenAt = visible and now or now - 3, heardAt = visible and now or now - 3, visible = visible } end
cov.phase = "move"
npc.pos = Vector(cov.origin.x + 60, cov.origin.y - 40, 0)
npc.yaw = 90
MW.Update(npc, enemy(false), now)
check(cov.phase == "enter", "arrival starts when close: " .. tostring(cov.phase))
local arr = played[#played]
check(arr and arr:find("^mwc_rs_arr_run_"), "a run arrival of the right corner: " .. tostring(arr))
check(npc.pos.x == cov.origin.x and npc.yaw == 90, "arrival ends on the node, facing along the wall")
now = now + 5
MW.Update(npc, enemy(false), now)
check(cov.phase == "idle" and played[#played] == "mwc_rs_hide", "hide idle after arriving: " .. tostring(played[#played]))

-- Enemy out of sight: a peek (look in -> look loop).
now = now + 0.1
MW.Update(npc, enemy(false), now)
check(cov.phase == "look_in", "peeks while the enemy is unseen: " .. cov.phase)
now = now + 2
MW.Update(npc, enemy(false), now)
check(cov.phase == "look" and played[#played] == "mwc_rs_look", "look loop")

-- Enemy visible: lean in -> aim with the blend, firing, aim yaw networked, body anchored toward the threat.
now = now + 3
MW.Update(npc, enemy(true), now)
check(cov.phase == "aim_in" and played[#played] == "mwc_rs_lean_in", "leans out to shoot: " .. cov.phase .. " " .. tostring(played[#played]))
now = now + 1
MW.Update(npc, enemy(true), now)
check(cov.phase == "aim" and played[#played] == "mwc_rs_aim", "aim blend loop")
check(npc.yaw == 180, "body faces the threat side (ny + 180): " .. npc.yaw)
now = now + 0.1
MW.Update(npc, enemy(true), now)
check(npc.tifFire.want and npc.tifAimFree and npc.tifMuzzle ~= nil, "fires with the anchored aim")
local ay = npc.nw.tif_aim_yaw or 0
check(ay < 0 and ay >= -60, "enemy to the right of the lean (+y is left; enemy at y 300 is... ) aim yaw " .. ay)
now = now + 5
MW.Update(npc, enemy(true), now)
check(cov.phase == "aim_out" and played[#played] == "mwc_rs_lean_out" and not npc.tifAimFree, "leans back after the burst")
now = now + 2
MW.Update(npc, enemy(false), now)
check(cov.phase == "idle", "back in hiding")

-- Low ammo: the cover reload.
npc.tifWep.ammo = 3
now = now + 0.1
MW.Update(npc, enemy(false), now)
check(cov.phase == "reload" and played[#played] == "mwc_rs_reload" and npc.reloading, "cover reload")
npc.reloading, npc.tifWep.ammo = false, 30
now = now + 5
MW.Update(npc, enemy(false), now)
check(cov.phase == "idle", "back to hide after reloading")
-- A shotgunner reloads with the shotgun cover clip.
npc.tifWep.class, npc.tifWep.ammo = "shotgun", 3
now = now + 0.1
MW.Update(npc, enemy(false), now)
check(cov.phase == "reload" and played[#played] == "mwc_rs_reload_shotgun", "shotgun cover reload: " .. tostring(played[#played]))
npc.reloading, npc.tifWep.ammo, npc.tifWep.class = false, 30, nil
now = now + 5
MW.Update(npc, enemy(false), now)
-- Hit in cover: hidden = a flinch in place; leaning out = knocked back into hiding.
check(cov.phase == "idle" and MW.Pain(npc, "torso", "f", false, now) and played[#played] == "mwc_rs_pain_torso_md_f" and cov.phase == "pain",
	"hit while hidden: flinch in cover: " .. tostring(played[#played]))
now = cov.phaseEnd + 0.01
MW.Update(npc, enemy(false), now)
check(cov.phase == "idle", "back to hiding after the flinch")
cov.phase = "aim"
check(MW.Pain(npc, "head", "l", true, now) and played[#played] == "mwc_rs_pain_head_lg_l_hide", "hit while leaning out: knocked back into hiding: " .. tostring(played[#played]))
cov.phase = "reload"
check(MW.Pain(npc, "torso", "f", false, now) == nil, "no pain clip mid reload")
cov.phase = "pain"
now = cov.phaseEnd + 0.01
MW.Update(npc, enemy(false), now)

-- A perception blackout (tifBlindUntil only) is not a flashbang: no reaction.
npc.tifBlindUntil = now + 4
now = now + 0.1
MW.Update(npc, enemy(false), now)
check(cov.phase ~= "flash", "a blackout doesn't trigger the flash reaction")
-- Flashbanged (TIF.API.Stun sets tif_stun_until): the flash reaction.
npc.nw.tif_stun_until = now + 4
now = now + 0.1
MW.Update(npc, enemy(false), now)
check(cov.phase == "flash" and played[#played] == "mwc_rs_flash", "flash reaction in cover")
now = now + 6
MW.Update(npc, enemy(false), now)

-- Heavy suppression: blindfire, firing only mid-clip.
npc.tifSupp = 0.8
cov.nextAim = 0
now = now + 0.1
MW.Update(npc, enemy(true), now)
check(cov.phase == "blind" and played[#played]:find("^mwc_rs_blind"), "blindfire under fire")
MW.Update(npc, enemy(true), now + 0.05)
check(not npc.tifFire.want, "no shots at the start of the blindfire clip")
local mid = cov.t0 + (cov.phaseEnd - cov.t0) * 0.5
MW.Update(npc, enemy(true), mid)
check(npc.tifFire.want and npc.tifBlind, "shots in the middle of the blindfire clip")
now = cov.phaseEnd + 0.1
npc.tifSupp = 0
MW.Update(npc, enemy(false), now)

-- Calm exit (0.35.2): nowhere to go next: the gun-up walk exit away from the wall, ended a bit early.
local leaving = MW.Exit(npc, "fight over")
check(leaving and cov.phase == "exit" and played[#played]:find("^mwc_rs_cexit_") and cov.exitCut, "exit clip, nowhere to go: " .. tostring(played[#played]))
-- His squad leader off along the wall normal: the jog exit heading there, played out in full (commits).
do
	local saveP, saveC, saveE = cov.phase, cov.phaseEnd, cov.exitCut
	cov.phase = "idle"
	local lead = { tifDead = false, GetPos = function() return npc:GetPos() + Vector(math.cos(math.rad(cov.ny)), math.sin(math.rad(cov.ny)), 0) * 600 end }
	npc.tifSquad = { leader = lead }
	local n, share = MW.PickCalmExit(npc, cov)
	check(n and n:find("^mwc_rs_exit_") and share == 1, "exit toward the leader: jog exit, committed (" .. tostring(n) .. ", " .. tostring(share) .. ")")
	local c = TIF.GTG.Clip(n, npc.tifHomeHost)
	local heading = math.deg(math.atan2(c.move[2], c.move[1])) + cov.hy
	check(math.abs(math.AngleDifference(heading, cov.ny)) <= MW.EXIT_COMMIT, "it heads toward him")
	npc.tifSquad = nil
	cov.phase, cov.phaseEnd, cov.exitCut = saveP, saveC, saveE
end

-- Low cover: crouch type, node 16 from the wall, hide facing ny + 90.
local pt2 = { pos = Vector(20, -100, 0), ny = 0, normal = Vector(1, 0, 0), high = false, canShoot = true }
local cov2 = { pt = pt2, origin = pt2.pos, ny = 0, high = false, side = "l", canShoot = true }
MW.Prepare(npc, cov2)
check(cov2.t == "cr" and math.abs(cov2.origin.x - 16) < 0.01 and cov2.origin.y == -100 and cov2.hy == 90, "low wall -> cr node")

-- Flashbanged in the open: MW19's exposed reaction; nothing again for the same stun.
local R = TIF.ReactMW
local s = { tifHomeHost = "mw_male", pos = Vector(300, 300, 0), yaw = 0, nw = {}, tifFire = {}, tifMove = {}, stance = 0 }
function s:GetNW2Float(k, d) return self.nw[k] or d end
function s:GetNW2Bool(k, d) if self.nw[k] ~= nil then return self.nw[k] end return d end
function s:GetTIFStance() return self.stance end
function s:GetPos() return self.pos end
function s:GetAngles() return Angle(0, self.yaw, 0) end
check(not R.Think(s, now), "no stun: no reaction")
s.nw.tif_stun_until = now + 5
check(R.Think(s, now) and played[#played]:find("exposed_stand_flashbang_react_0"), "long stand reaction for a 5 s stun: " .. tostring(played[#played]))
check(R.Think(s, now + 1), "still reacting during the clip")
s.tifAct = nil
check(not R.Think(s, now + 10), "done after the clip, no repeat for the same stun")
s.stance = 1
s.nw.tif_stun_until = now + 12
check(R.Think(s, now + 10) and played[#played]:find("exposed_crouch_flashbang_srt_react"), "short crouch reaction for a 2 s stun")

-- Grenades from cover: enemy known but out of sight a few seconds -> throw clip, release on its frame.
local gnpc = { tifHomeHost = "mw_male", pos = Vector(16, 0, 0), yaw = 90, nw = {}, tifFire = {}, tifMove = {},
	tifArch = { coverPause = { 1, 2 }, coverBurst = { 1.5, 2.5 }, loseContact = 6, aggression = 1 }, tifWep = { ammo = 30, clip = 30 } }
for k, v in pairs(npc) do if type(v) == "function" then gnpc[k] = v end end
gnpc.loco = { GetVelocity = function() return Vector(0, 0, 0) end }
function gnpc:GetTIFFaction() return "army" end
local gpt = { pos = Vector(20, 0, 0), ny = 0, normal = Vector(1, 0, 0), high = false, canShoot = true }
local gcov = { pt = gpt, origin = gpt.pos, ny = 0, high = false, side = "l", canShoot = true }
gnpc.tifCov = gcov
MW.Prepare(gnpc, gcov)
gcov.phase, gcov.t0, gcov.nextAim, gcov.nextTwitch = "idle", now, now + 99, now + 99
local tgt = Vector(-600, 100, 0)
local hidden = { pos = tgt, ent = enemy(false).ent, seenAt = now - 4, heardAt = now - 4, visible = false }
math.randomseed(3)
MW.Update(gnpc, hidden, now)
check(gcov.phase == "grenade" and played[#played] == "mwc_cr_grenade", "throws a grenade at the hidden enemy: " .. tostring(gcov.phase))
local rel = gcov.releaseT
check(#grenades == 0 and rel > now, "not before the release frame")
MW.Update(gnpc, hidden, rel + 0.01)
local g = grenades[1]
check(g and g.cls == "tif_grenade" and g.kind == "frag" and g.owner == gnpc and gnpc.said == "grenade_out", "released on the grenade_throw frame, called out")
-- the arc lands on the target: x(T) = src + v*T, fuse a bit after
local T = g.fuse - 0.5
local land = Vector(g.pos.x + g.vel.x * T, g.pos.y + g.vel.y * T, g.pos.z + g.vel.z * T - 0.5 * 600 * T * T)
check(math.abs(land.x - tgt.x) < 1 and math.abs(land.y - tgt.y) < 1 and math.abs(land.z - tgt.z) < 1, string.format("lands on the target (%.0f %.0f %.0f)", land.x, land.y, land.z))
check(gnpc.tifGrenades == 0, "one grenade used")
gcov.phase, gcov.nextAim = "idle", now + 99
gnpc.tifNextGrenade, gnpc.tifSquad = 0, nil
MW.Update(gnpc, hidden, rel + 30)
check(gcov.phase ~= "grenade", "no grenades left: no more throws")
gnpc.tifGrenades, gnpc.tifNextGrenade = 1, 0
local mate = { pos = Vector(-580, 90, 0) }
function mate:GetPos() return self.pos end
function mate:GetTIFFaction() return "army" end
TIF.Soldiers = { gnpc, mate }
gcov.phase = "idle"
MW.Update(gnpc, hidden, rel + 60)
check(gcov.phase ~= "grenade", "no throw with a friendly near the target")


-- 0.33.0: crouched corners, stand cover (chest-high wall), pistol sets, shuffles into the new types.
local function prep(ptOpts, wep)
	local p = { pos = Vector(20, 0, 0), ny = 0, normal = Vector(1, 0, 0), canShoot = true, edgeL = false, edgeR = true }
	for k, v in pairs(ptOpts) do p[k] = v end
	local c = { pt = p, origin = p.pos, ny = 0, high = p.high, side = "l", canShoot = true }
	local s = { tifHomeHost = "mw_male", pos = Vector(16, 0, 0), yaw = 90, nw = {}, tifFire = {}, tifMove = {},
		tifArch = gnpc.tifArch, tifWep = { ammo = 12, clip = 12, class = wep or "rifle" } }
	for k, v in pairs(npc) do if type(v) == "function" then s[k] = v end end
	s.loco = { GetVelocity = function() return Vector(0, 0, 0) end }
	s.tifCov = c
	MW.Prepare(s, c)
	return s, c
end
MW.CROUCH_CORNER = 1
local s1, c1 = prep({ high = true })
check(c1.t == "rc", "crouched corner when picked: rc (" .. tostring(c1.t) .. ")")
check(c1.hy == 90, "rc hides facing the corner like rs (" .. tostring(c1.hy) .. ")")
check(math.abs(c1.origin.y - (c1.edgeR - 10)) < 0.01, "rc node short of the edge like rs")
MW.CROUCH_CORNER = -1
local s2, c2 = prep({ high = false, mid = true })
check(c2.t == "st", "chest-high wall: stand cover st (" .. tostring(c2.t) .. ")")
check(c2.hy == 90, "st hide faces along the wall like cr (" .. tostring(c2.hy) .. ")")
local s3, c3 = prep({ high = false, mid = false })
check(c3.t == "cr", "low wall: still crouch cover (" .. tostring(c3.t) .. ")")
-- st: crouched while hidden, standing while it fires over
c2.phase = "idle"
MW.Update(s2, nil, now)
check(s2.tifStance == 1, "st hidden crouched")
-- pistol: the type's pistol set where MW19 has it, the rifle's otherwise
local s4, c4 = prep({ high = false }, "pistol")
check(c4.pstl == true and MW.Role(c4, "hide") == "mwc_crp_hide", "pistol in low cover: its pistol hide (" .. MW.Role(c4, "hide") .. ")")
check(MW.Role(c4, "blind1") == "mwc_cr_blind1", "pistol: no pistol blindfire, the rifle role name (" .. MW.Role(c4, "blind1") .. ")")
check(MW.Role(c4, "aim") == "mwc_crp_aim", "pistol aim blend (" .. MW.Role(c4, "aim") .. ")")
local s5, c5 = prep({ high = false, mid = true }, "pistol")
check(MW.Role(c5, "lean_in") == "mwc_stp_lean_in", "pistol in stand cover: its pistol rise (" .. MW.Role(c5, "lean_in") .. ")")
check(MW.Role(c1, "hide") == "mwc_rc_hide", "rifle stays on the rifle set")
-- every role the cover code plays exists for the new types
for _, t in ipairs({ "st", "lc", "rc" }) do
	for _, r in ipairs({ "hide", "lean_in", "aim", "lean_out", "exit_2" }) do
		check(clips["mwc_" .. t .. "_" .. r] ~= nil, t .. " has " .. r)
	end
end
-- shuffles into / out of the new types
for _, n in ipairs({ "mwc_st_to_shuf_l", "mwc_st_to_shuf_r", "mwc_lc_to_shuf_r", "mwc_rc_to_shuf_l", "mwc_shuf_l_to_st",
	"mwc_shuf_r_to_st", "mwc_shuf_l_to_lc", "mwc_shuf_r_to_rc" }) do
	check(clips[n] ~= nil, "shuffle clip " .. n)
end

-- 2026-11-20: beside-cover fight: out past the corner / low wall's end, crouched, firing; back in with the
-- hand-plant into-cover clip (mwc_<t>_xin_cr_<k>), turning first when far off its start facing.
MW.SIDE_CHANCE = 1
do
	local s6, c6 = prep({ high = true })
	function s6:GetTIFStance() return self.tifStance or 0 end
	s6.pos, s6.yaw = c6.origin, c6.hy
	c6.phase, c6.t0, c6.nextAim, c6.nextTwitch = "idle", now, 0, now + 99
	MW.Update(s6, enemy(true), now)
	local g = s6.tifMove.goal
	local t6 = now
	check(c6.phase == "side_out" and g, "rs: out beside the cover instead of leaning (" .. tostring(c6.phase) .. ")")
	check(g and math.abs(g.x - 16) < 0.01 and math.abs(g.y - (c6.edgeR + MW.SIDE_PAST)) < 0.01, "spot past the corner edge: " .. (g and (g.x .. " " .. g.y) or "nil"))
	check(s6.tifStance == 1 and s6.tifAct == nil, "crouched, hide clip cleared")
	s6.pos, s6.yaw = g, 180
	now = now + 1
	MW.Update(s6, enemy(true), now)
	check(c6.phase == "side", "arrived: firing from beside the cover (" .. c6.phase .. ")")
	now = now + 0.1
	MW.Update(s6, enemy(true), now)
	check(s6.tifFire.want and s6.tifFace ~= nil and not s6.tifAimFree, "fires from the exposed crouch, facing the enemy")
	now = now + 10
	MW.Update(s6, enemy(true), now)
	check(c6.phase == "enter" and played[#played]:find("^mwc_rs_xin_cr_"), "back in with the into-cover clip: " .. tostring(played[#played]))
	local xc = clips[played[#played]]
	check(math.abs(math.AngleDifference(c6.hy - xc.move[3], 180)) < 1, "its start facing is his (no turn needed)")
	check(s6.pos == c6.origin and s6.yaw == c6.hy and s6.tifAct.opts.noTrace, "warped onto the node")
	now = now + 3
	MW.Update(s6, enemy(false), now)
	check(c6.phase == "idle", "hiding again")
	check(c6.nextSide == t6 + MW.SIDE_EVERY, "not again for SIDE_EVERY seconds")
	c6.nextSide, c6.nextAim = now + 1, 0
	now = now + 0.5
	MW.Update(s6, enemy(true), now)
	check(c6.phase == "aim_in", "while waiting: the normal lean (" .. c6.phase .. ")")
	-- low wall: past its end (the wall ends at y = 40), and a turn first (no cr clip starts facing the threat)
	local s7, c7 = prep({ high = false })
	function s7:GetTIFStance() return self.tifStance or 0 end
	s7.pos, s7.yaw = c7.origin, c7.hy
	c7.phase, c7.t0, c7.nextAim, c7.nextTwitch = "idle", now, 0, now + 99
	MW.Update(s7, enemy(true), now)
	local g7 = s7.tifMove.goal
	check(c7.phase == "side_out" and g7 and g7.y > 40 and g7.y < 40 + MW.SIDE_PAST + 8, "cr: out past the low wall's end: " .. (g7 and g7.y or "nil"))
	s7.pos, s7.yaw = g7, 180
	now = now + 1
	MW.Update(s7, enemy(true), now)
	now = now + 10
	MW.Update(s7, enemy(true), now)
	check(c7.phase == "side_turn", "turns toward the clip's start first (" .. c7.phase .. ")")
	s7.yaw = c7.sideAt.yaw
	now = now + 0.2
	MW.Update(s7, enemy(true), now)
	check(c7.phase == "enter" and played[#played]:find("^mwc_cr_xin_cr_"), "then the low-cover into-cover clip: " .. tostring(played[#played]))
	-- no room / no shot: leans as before
	local s8, c8 = prep({ high = false, pos = Vector(20, -100, 0) })
	function s8:GetTIFStance() return 0 end
	s8.pos, s8.yaw = c8.origin, c8.hy
	c8.phase, c8.t0, c8.nextAim, c8.nextTwitch = "idle", now, 0, now + 99
	MW.Update(s8, enemy(true), now)
	check(c8.phase == "aim_in", "low wall with no end near: the normal pop-up (" .. c8.phase .. ")")
end
MW.SIDE_CHANCE = 0
do
	local saveT = TIF.TransMW
	local handVel
	TIF.TransMW = { ExitVel = function(c, y0, u) handVel = { c = c, y0 = y0, u = u } return Vector(140, 0, 0) end }
	local function soldier(stance)
		local x = { tifHomeHost = "mw_male", pos = Vector(16, 30, 0), yaw = 90, nw = {}, tifFire = {}, tifMove = {}, stance = stance or 0,
			tifArch = { coverPause = { 1, 2 }, coverBurst = { 1.5, 2.5 }, loseContact = 6, aggression = 0.6 }, tifWep = { ammo = 30, clip = 30 } }
		function x:GetPos() return self.pos end
		function x:SetPos(p) self.pos = p end
		function x:GetAngles() return Angle(0, self.yaw, 0) end
		function x:SetAngles(a) self.yaw = a.y end
		function x:GetNW2Float(k, d) return self.nw[k] or d end
		function x:GetNW2Bool(k, d) if self.nw[k] ~= nil then return self.nw[k] end return d end
		function x:SetNW2Float(k, v) self.nw[k] = v end
		function x:SetNW2Bool(k, v) self.nw[k] = v end
		function x:GetTIFStance() return self.stance end
		function x:SetTIFStance(v) self.stance = v end
		function x:TIFApplyStance() self.applied = true end
		x.loco = { GetVelocity = function() return Vector(0, 0, 0) end, SetVelocity = function(_, v) x.handed = v end }
		local p = { pos = Vector(20, 0, 0), ny = 0, normal = Vector(1, 0, 0), high = true, edgeL = false, edgeR = true, canShoot = true }
		local cv = { pt = p, origin = p.pos, ny = 0, high = true, side = "l", canShoot = true, mw = true }
		x.tifCov = cv
		MW.Prepare(x, cv)
		cv.phase = "idle"
		return x, cv
	end
	local x, cv = soldier(0)
	local goal = Vector(900, 40, 0)
	check(MW.ExitTo(x, goal, "maneuver") and cv.phase == "exit", "a maneuver out of settled cover plays an exit clip: " .. tostring(cv.phase))
	local n = played[#played]
	check(n and n:find("^mwc_rs_exit_"), "the jog exit (" .. tostring(n) .. ")")
	local c = TIFG.Clips.mw_male[n]
	local head = c and math.deg(math.atan2(c.move[2], c.move[1])) + x.yaw
	check(c and math.abs(math.AngleDifference(head, 0)) <= 60, "it heads toward the maneuver goal (" .. tostring(head) .. ")")
	check(handVel and handVel.c == c and handVel.y0 == 90, "the exit's own speed is taken at the point it hands over")
	check(MW.ExitTo(x, goal, "maneuver") == true, "still exiting mid clip")
	local at = cv.phaseEnd
	now = at + 0.01
	check(MW.ExitTo(x, goal, "maneuver") == false and x.tifCov == nil, "done: out of cover")
	check(x.handed and x.handed.x == 140, "his movement carries on at the clip's speed (no stop / start)")
	check(x.stance == 0 and x.tifStance == 0, "standing, as the jog exit ends")
	check(x.tifNextCoverSearch == 0, "a maneuver looks for its next cover at once")
	local y, cy = soldier(0)
	cy.phase = "reload"
	check(MW.ExitTo(y, goal, "maneuver") == false and cy.phase == "reload", "mid reload: no exit clip (the caller leaves)")
	local z, cz = soldier(0)
	check(MW.ExitTo(z, z.pos + Vector(60, 0, 0), "medic") == false, "a goal right beside him: no exit clip")
	local k, ck = soldier(1)
	TIF.Cover.StillGood = function() return false, "flanked" end
	k.tifCov.nextCheck = 0
	local before = #played
	MW.Update(k, enemy(true), now)
	TIF.Cover.StillGood = function() return true end
	local exitPlayed = false
	for i = before + 1, #played do if played[i]:find("exit") then exitPlayed = true end end
	check(k.tifCov == nil and not exitPlayed, "flanked: straight out, no exit clip")
	check(k.tifStance == 1 and k.tifKeepCrouchUntil and k.tifKeepCrouchUntil > now, "flanked while crouched: he stays crouched")
	local w, cw = soldier(0)
	check(MW.PlaySwitch(w, "secondary") == "mwc_rs_to_pistol" and cw.phase == "switch", "drawing the pistol in settled cover: the cover switch clip (" .. tostring(played[#played]) .. ")")
	w.tifFire.want = true
	check(MW.Update(w, enemy(true), now) == true and w.tifFire.want == false, "holds fire through the switch")
	now = cw.phaseEnd + 0.01
	MW.Update(w, enemy(false), now)
	check(cw.phase ~= "switch", "back to hiding after it (" .. tostring(cw.phase) .. ")")
	local v, cv2 = soldier(0)
	check(MW.PlaySwitch(v, "primary") == "mwc_rs_to_rifle", "back to the rifle: the other way round")
	local u, cu = soldier(0)
	cu.phase = "aim"
	check(MW.PlaySwitch(u, "secondary") == nil and cu.phase == "aim", "leaning out aiming: no cover switch clip (the draw plays as before)")
	TIF.TransMW = saveT
end
print(string.format("passed %d, failed %d", pass, fail))
