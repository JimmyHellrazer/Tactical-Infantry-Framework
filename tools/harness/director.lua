local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end return Vector(a.x * b, a.y * b, a.z * b) end
V.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:LengthSqr() return self:Dot(self) end
function V:Length() return math.sqrt(self:Dot(self)) end
function V:DistToSqr(o) local d = self - o return d:Dot(d) end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:GetNormalized() local v = Vector(self) v:Normalize() return v end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
function Angle(p, y, r) return { p = p, y = y, r = r } end
function IsValid(x) return x ~= nil and x ~= false and (type(x) ~= "table" or not x.removed) end
function math.Rand(a, b) return (a + b) / 2 end
function math.Round(x) return math.floor(x + 0.5) end
function setmetatable_weak(t) return t end
MASK_OPAQUE = 1
local now = 100
function CurTime() return now end
local timers, hooks = {}, {}
timer = { Create = function(n, d, r, f) timers[n] = f end }
hook = { Add = function(ev, id, f) hooks[ev] = hooks[ev] or {} hooks[ev][id] = f end }

local players = {}
local function mkply(pos, aim)
	local p = { pos = pos, aim = aim, IsPlayer = function() return true end }
	function p:GetPos() return Vector(self.pos) end
	function p:EyePos() return self.pos + Vector(0, 0, 64) end
	function p:GetAimVector() return Vector(self.aim) end
	function p:Alive() return true end
	function p:GetVelocity() return Vector() end
	return p
end
player = { Iterator = function() local i = 0 return function() i = i + 1 if players[i] then return i, players[i] end end end }
local blocked = false
local cues = 0
util = { TraceLine = function(t) return { Hit = blocked } end, AddNetworkString = function() end }
net = { Start = function() end, WriteString = function(x) lastCue = x end, Broadcast = function() cues = cues + 1 end }

local areas = {}
local function mkarea(pos)
	return { c = pos, IsUnderwater = function() return false end, GetSizeX = function() return 64 end, GetSizeY = function() return 64 end,
		GetCenter = function(self) return Vector(self.c) end }
end
navmesh = { GetAllNavAreas = function() return areas end }

local rnd = 0
local realRandom = math.random
math.random = function(a, b)
	if not a then return 0.99 end
	if not b then rnd = rnd % a + 1 return rnd end
	return a
end

TIF = { Factions = { usmc = {}, insurgents = {}, russians = {}, civilians = {} }, REL_HOSTILE = -1, AWARE = { ENGAGED = 3 }, Soldiers = {} }
function TIF.FactionCanon(id) return id end
function TIF.PlayerFaction() return "usmc" end
function TIF.FactionRelation(a, b) if a == "civilians" or a == b then return 0 end return -1 end
function TIF.IgnorePlayers() return false end
function TIF.FormationPoints(c, n, yaw) local o = {} for i = 1, n do o[i] = c + Vector(-60 * i, 0, 0) end return o end
local spawned, squads, advances, patrols = {}, {}, {}, {}
local function mknpc(pos)
	local e = { pos = pos, tifK = { contacts = {} } }
	function e:GetPos() return Vector(self.pos) end
	function e:SetAngles(a) self.ang = a end
	function e:Remove() self.removed = true end
	function e:GetMaxHealth() return self.mh or 100 end
	function e:SetMaxHealth(v) self.mh = v end
	function e:SetHealth(v) self.hp = v end
	return e
end
TIF.Squad = { Members = function(sq) local o = {} for _, m in ipairs(sq.members) do if IsValid(m) and not m.tifDead then o[#o + 1] = m end end return o end }
TIF.Perception = {
	Contact = function(npc, ent) local c = npc.tifK.contacts[ent] or { visible = false } npc.tifK.contacts[ent] = c return c end,
	Stimulus = function() end,
}
TIF.API = {
	SpawnSquad = function(fac, pos, roles, opts)
		local sq = { faction = fac, members = {}, knowledge = {}, roles = roles, opts = opts }
		for i, p in ipairs(opts.points or {}) do local e = mknpc(p) sq.members[i] = e spawned[#spawned + 1] = e end
		sq.leader = sq.members[1]
		squads[#squads + 1] = sq
		return sq, sq.members
	end,
	SquadKnowsEnemy = function(sq, ent, pos) sq.knowledge[ent] = { pos = pos } end,
	SquadAdvance = function(sq, pos, opts) sq.order = { kind = "advance", pos = pos } advances[#advances + 1] = { sq = sq, pace = opts.pace } end,
	SquadPatrol = function(sq, route) sq.order = { kind = "patrol" } patrols[#patrols + 1] = sq end,
}
function TIF.Error(...) print("ERR", ...) end

assert(loadfile(ROOT .. "tif/director/sv_director.lua"))()
local D = TIF.Director

local ply = mkply(Vector(0, 0, 0), Vector(1, 0, 0))
players[1] = ply

check(D.SeenByPlayers(Vector(300, 0, 0), 600), "a spot close to the player counts as seen")
check(not D.SeenByPlayers(Vector(-2000, 0, 0), 600), "a spot behind the player is unseen")
check(D.SeenByPlayers(Vector(2000, 0, 0), 600), "a spot in front with a clear line is seen")
blocked = true
check(not D.SeenByPlayers(Vector(2000, 0, 0), 600), "a spot in front behind a wall is unseen")

areas = { mkarea(Vector(200, 0, 0)), mkarea(Vector(9000, 0, 0)), mkarea(Vector(0, 2000, 0)), mkarea(Vector(-2000, 0, 0)), mkarea(Vector(2000, 300, 0)) }
local pos = D.FindSpawn(1200, 3500, { ahead = true, tries = 40 })
check(pos and pos.x == 2000, "spawn picks an unseen spot in the window, ahead of where the player heads")
blocked = false
local pos2 = D.FindSpawn(1200, 3500, { tries = 40 })
check(pos2 and pos2.x <= 0, "with a clear view ahead it only uses spots out of sight")
blocked = true

check(D.HostileFaction("auto") == "insurgents", "auto picks the insurgents against a usmc player")
check(D.HostileFaction("russians") == "russians", "an explicit faction is kept")

D.Intensity = 0
local dmg = { GetAttacker = function() return { TIFSoldier = true } end, GetDamage = function() return 30 end }
hooks.EntityTakeDamage.tif_director_intensity(ply, dmg)
check(D.Intensity == 30, "soldier damage on a player raises intensity")
hooks.TIF_SoldierKilled.tif_director_intensity({}, ply)
check(D.Intensity == 38, "killing a soldier raises it too")
timers.tif_director_intensity()
check(math.abs(D.Intensity - (38 * 0.93 - 1)) < 0.01, "intensity decays each second")

local function mkdir()
	local e = { nv = { Faction = "auto", MaxAlive = 24, AmbientSquads = 2, AssaultSquads = 1, SquadMin = 4, SquadMax = 4,
		AssaultMin = 60, AssaultMax = 60, SpawnMin = 1200, SpawnMax = 3500, PeakIntensity = 120, RelaxIntensity = 25, RelaxTime = 40 } }
	setmetatable(e, { __index = function(t, k)
		local n = k:match("^Get(.+)") if n then return function(self) return self.nv[n] end end
		n = k:match("^Set(.+)") if n then return function(self, v) self.nv[n] = v end end
	end })
	return e
end

areas = { mkarea(Vector(-2000, 0, 0)), mkarea(Vector(-2000, 1500, 0)), mkarea(Vector(-1500, -1500, 0)), mkarea(Vector(-3000, 0, 0)) }
D.Intensity = 0
local dir = mkdir()
local ph = D.DirectorThink(dir, now)
check(ph == "buildup", "the director starts in buildup")
check(#squads == 1 and #dir.tifDir.owned == 4, "buildup spawns an ambient squad")
check(squads[1].opts.points ~= nil, "ambient squads spawn in formation")
now = now + 5
D.DirectorThink(dir, now)
check(#squads == 2, "up to the ambient squad count")
now = now + 5
D.DirectorThink(dir, now)
check(#squads == 2, "no more than that")
check(#advances == 0, "ambient squads don't hunt")

now = 100 + 61
D.DirectorThink(dir, now)
check(#squads == 3 and squads[3].members[1].tifHunter, "an assault squad spawns on the timer")
check(advances[#advances].sq == squads[3] and advances[#advances].pace == "rush", "assault squads rush the player")
check(squads[3].knowledge[ply] ~= nil, "the squad knows where the player is")
local c = squads[3].members[2].tifK.contacts[ply]
check(c and c.confirmed and c.source == "director", "every hunter has the player as a confirmed contact")
local nAdv = #advances
now = now + 3.1
ply.pos = Vector(600, 0, 0)
D.DirectorThink(dir, now)
check(#advances == nAdv + 1, "hunters re-route when the player moves")
now = now + 3.1
D.DirectorThink(dir, now)
check(#advances == nAdv + 1, "but not when he stays put")
squads[3].lastContact = now
ply.pos = Vector(-200, 900, 0)
now = now + 3.1
D.DirectorThink(dir, now)
check(#advances == nAdv + 1, "squads in a firefight fight instead of re-routing")
ply.pos = Vector(0, 0, 0)

D.Intensity = 150
check(D.DirectorThink(dir, now) == "peak", "high intensity is the peak")
local before = #squads
for _, e in ipairs(squads[1].members) do e.tifDead = true end
now = now + 100
D.Intensity = 150
D.DirectorThink(dir, now)
check(#squads == before, "no spawns during the peak")
D.Intensity = 10
check(D.DirectorThink(dir, now) == "relax", "intensity falling off starts the relax")
now = now + 20
D.DirectorThink(dir, now)
check(#squads == before, "no spawns during the relax")
now = now + 25
local ph2 = D.DirectorThink(dir, now)
check(ph2 == "buildup (calm)", "after the relax the next area is calm")
local nPat = #patrols
now = now + 5
D.DirectorThink(dir, now)
check(#squads == before + 1 and squads[#squads].tifDirChill, "the next ambient squad is chill")
check(#patrols == nPat, "chill squads stay put instead of patrolling")

local e = dir.tifDir.owned[1]
e.pos = Vector(-9000, 0, 0)
local n0 = #dir.tifDir.owned
dir.tifDir.nextRecycle = 0
D.DirectorThink(dir, now)
check(e.removed and #dir.tifDir.owned == n0 - 1, "soldiers left far behind and out of sight are cleaned up")

local hunter = squads[3].members[1]
hunter.tifDirLast, hunter.tifDirProgress = Vector(hunter.pos), now - 30
dir.tifDir.nextRecycle = 0
D.DirectorThink(dir, now)
check(hunter.removed, "stuck hunters are recycled")

local held = { pos = Vector(100, 0, 0), tifAware = 3, tifK = { contacts = {} } }
function held:GetPos() return Vector(self.pos) end
function held:Remove() self.removed = true end
D.Recycle({ held }, now, 100, nil, players)
check(not held.removed, "soldiers in a fight are never despawned")

D.DirectorClear(dir)
check(squads[2].members[1].removed and dir.tifDir == nil, "removing the director removes its soldiers")

squads = {}
local surv = mkdir()
surv.nv = { Faction = "auto", StartSize = 6, Growth = 50, MaxAlive = 24, SquadMin = 3, SquadMax = 3, BreakTime = 20, SpawnMin = 1200, SpawnMax = 3500, Wave = 0, RunStart = 0, BreakEnd = 0 }
now = 1000
D.SurvivalThink(surv, now)
check(surv.nv.RunStart == now and surv.nv.BreakEnd == now + 10, "survival starts with a short break")
now = now + 11
D.SurvivalThink(surv, now)
check(surv.nv.Wave == 1 and surv.tifSurv.left == 6, "wave 1 is the start size")
check(cues == 1 and lastCue == "tif/director/walla_alert.ogg", "a new wave plays the alert walla")
D.SurvivalThink(surv, now)
check(#squads == 1 and surv.tifSurv.left == 3, "waves spawn as squads")
check(advances[#advances].sq == squads[1], "survival squads hunt the player straight away")
now = now + 2.1
D.SurvivalThink(surv, now)
check(#squads == 2 and surv.tifSurv.left == 0, "until the wave is out")
check(squads[1].opts.points[1]:DistToSqr(squads[2].opts.points[1]) > 400 * 400, "squads of a wave come from different places")
for _, sq in ipairs(squads) do for _, m in ipairs(sq.members) do m.tifDead = true end end
now = now + 2.1
D.SurvivalThink(surv, now)
check(surv.nv.BreakEnd == now + 20, "a cleared wave starts the break")
now = now + 21
D.SurvivalThink(surv, now)
check(surv.nv.Wave == 2 and surv.tifSurv.left == 9, "each wave grows")
D.SurvivalThink(surv, now)
local m = squads[#squads].members[1]
m.pos = Vector(-20000, 0, 0)
surv.tifSurv.nextRecycle = 0
local left0 = surv.tifSurv.left
now = now + 2.1
D.SurvivalThink(surv, now)
check(m.removed and surv.tifSurv.left >= left0 + 1 - 3, "lost soldiers go back into the wave")
local survSq1 = squads[1]
D.SurvivalReset(surv)
check(surv.nv.RunStart == 0 and surv.tifSurv == nil, "reset clears the run")

check(squads[1].members[1].tifMoraleScale == D.SURV_MORALE and squads[1].members[1].tifPreferPlayers == D.SURV_PREFER_PLAYERS, "survival soldiers are harder to break and go for players")

squads, advances = {}, {}
local ons = mkdir()
ons.nv = { Faction = "auto", Onslaught = true, StartSize = 6, Growth = 25, MaxAlive = 24, SquadMin = 3, SquadMax = 3, BreakTime = 20, SpawnMin = 1200, SpawnMax = 3500, Wave = 0, RunStart = 0, BreakEnd = 0, Heat = 0 }
now = 5000
D.SurvivalThink(ons, now)
check(ons.nv.RunStart == now and ons.nv.BreakEnd == 0 and ons.nv.Heat == 1, "onslaught starts at once: no lead-in break, heat 1")
local cuesOn = cues
check(D.OnslaughtCap(ons, now) == 6, "the crowd starts at a quarter of max alive")
now = now + 0.5
D.SurvivalThink(ons, now)
check(#squads == 0, "the starting bank (2) is under a squad, so nothing yet")
for _ = 1, 16 do now = now + 0.5 D.SurvivalThink(ons, now) end
check(#squads == 1 and #squads[1].members == 3, "the bank fills and a squad spawns")
check(advances[#advances].sq == squads[1], "onslaught squads hunt straight away")
check(ons.nv.BreakEnd == 0 and ons.nv.Wave == 0, "no waves and no breaks")
for _, sq in ipairs(squads) do for _, m in ipairs(sq.members) do m.tifDead = true end end
local nsq = #squads
now = now + 1
D.SurvivalThink(ons, now)
check(ons.nv.BreakEnd == 0, "clearing everyone doesn't start a break either")
local bank0 = ons.tifSurv.bank
now = 5000 + 76
ons.tifSurv.lastT = now
ons.tifSurv.nextSpawn = now + 99
D.SurvivalThink(ons, now)
check(ons.tifSurv.bank >= bank0 + D.ONSLAUGHT.SURGE_SIZE + D.ONSLAUGHT.SURGE_PER_LEVEL, "a surge dumps a burst into the bank")
check(cues == cuesOn + 1, "and plays the walla")
check(ons.tifSurv.nextSurge < now + 75, "surges come a little sooner as it goes on")
now = 5000 + 91
D.SurvivalThink(ons, now)
check(ons.nv.Heat == 2, "heat goes up every 90 s")
check(D.OnslaughtCap(ons, 5000 + 8 * 60) == 24, "the crowd reaches max alive by 8 minutes")
check(D.OnslaughtCap(ons, 5000 + 30 * 60) == 48, "and keeps growing, up to double")
local hpEnt = mknpc(Vector())
function hpEnt:GetMaxHealth() return self.mh or 100 end
function hpEnt:SetMaxHealth(v) self.mh = v end
function hpEnt:SetHealth(v) self.hp = v end
local realSpawn = TIF.API.SpawnSquad
TIF.API.SpawnSquad = function(fac, pos, roles, opts) local sq = { members = { hpEnt }, knowledge = {}, opts = opts } hpEnt.pos = pos squads[#squads + 1] = sq return sq, sq.members end
now = 5000 + 20 * 60
ons.tifSurv.bank, ons.tifSurv.nextSpawn, ons.tifSurv.lastT = 20, 0, now
for _, e in ipairs(ons.tifSurv.owned) do e.tifDead = true end
D.SurvivalThink(ons, now)
TIF.API.SpawnSquad = realSpawn
check(hpEnt.mh == 140 and hpEnt.hp == 140, "late onslaught soldiers are tougher (+2% health a minute, capped)")
ons.nv.Onslaught = false
now = now + 1
D.SurvivalThink(ons, now)
check(ons.tifSurv.mode == "waves" and ons.nv.RunStart == now and ons.nv.Heat == 0, "switching the mode off restarts as waves")

local mo = io.open(ROOT .. "tif/tactics/sv_morale.lua"):read("*a")
check(mo:find("if amount < 0 and npc.tifMoraleScale then\n\t\tamount = amount * npc.tifMoraleScale", 1, true) ~= nil, "morale losses scale down (gains don't)")
check(mo:find("(supp - 0.4) * 0.06 * (1 - resist) * loss", 1, true) and mo:find("m = m - 0.012 * loss", 1, true), "suppression and outnumbered drift scale down too")
local pe = io.open(ROOT .. "tif/npc/sv_perception.lua"):read("*a")
check(pe:find("if npc.tifPreferPlayers and IsValid(e) and e:IsPlayer() then\n\t\t\t\tscore = score + npc.tifPreferPlayers", 1, true) ~= nil, "target choice favours players for them")

local src = io.open(ROOT .. "autorun/tif_init.lua"):read("*a")
check(src:find('"director/sv_director.lua"', 1, true) ~= nil, "the director module loads")
for _, f in ipairs({ "entities/tif_director.lua", "entities/tif_survival.lua" }) do
	local s = io.open(ROOT .. f):read("*a")
	check(s:find("ENT.Spawnable = true", 1, true) and s:find("ENT.AdminOnly = true", 1, true), f .. " is an admin spawnable")
end
math.random = realRandom

local sv = io.open(ROOT .. "entities/tif_survival.lua"):read("*a")
check(sv:find('net.Receive("tif_surv_cue"', 1, true) and sv:find("surface.PlaySound(snd)", 1, true), "clients play the cue")
local f = io.open(ROOT .. "../sound/tif/director/walla_alert.ogg", "rb")
check(f and f:read(4) == "OggS", "the cue is a real ogg in the addon")
print(string.format("passed %d, failed %d", pass, fail))
