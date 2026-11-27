local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function V:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function Angle(p, y, r) return { p = p, y = y, r = r } end
function IsValid(x) return x ~= nil and x ~= false and (type(x) ~= "table" or not x.removed) end
function AddCSLuaFile() end
SERVER, CLIENT = true, false
MOVETYPE_NONE, SOLID_BBOX, COLLISION_GROUP_WORLD = 0, 2, 1
local now = 100
function CurTime() return now end

local orders, advances, knows = {}, {}, {}
local function ent(fac, pos, player)
	local e = { fac = fac, p = pos or Vector(), tifK = { contacts = {} } }
	function e:GetPos() return self.p end
	function e:IsPlayer() return player == true end
	function e:GetVelocity() return Vector() end
	return e
end
local list = {}
local function squad(fac, n, opts)
	local sq = { faction = fac, members = {}, order = { kind = "free" } }
	for i = 1, n do sq.members[i] = ent(fac, Vector(-2000, i * 50, 0)) end
	sq.leader = sq.members[1]
	for k, v in pairs(opts or {}) do sq[k] = v end
	list[#list + 1] = sq
	return sq
end
local inSphere = {}
TIF = {
	REL_HOSTILE = -1,
	FactionCanon = function(id) return id == "militia" and "insurgents" or id end,
	FactionComboValues = function() return { ["Auto (hostile to you)"] = "auto", ["Random hostile"] = "random", ["Insurgents (insurgents)"] = "insurgents", ["US Marines (usmc)"] = "usmc" } end,
	FactionOf = function(e) return e.fac end,
	FactionRelation = function(a, b) if a == b then return 1 end return -1 end,
	IsLiveCombatant = function(e) return not e.dead end,
	IgnorePlayers = function() return false end,
	Squad = {
		List = list,
		Members = function(sq) local o = {} for _, m in ipairs(sq.members) do if IsValid(m) then o[#o + 1] = m end end return o end,
		SetOrder = function(sq, kind, pos) sq.order = { kind = kind, pos = pos } orders[#orders + 1] = { sq = sq, kind = kind } end,
	},
	API = {
		SquadAdvance = function(sq, pos, opts) sq.order = { kind = "advance", pos = pos } advances[#advances + 1] = { sq = sq, pace = opts and opts.pace } end,
		SquadKnowsEnemy = function(sq, e, pos) knows[#knows + 1] = { sq = sq, e = e } end,
	},
	Perception = { Contact = function(npc, e) local c = npc.tifK.contacts[e] or { visible = false } npc.tifK.contacts[e] = c return c end },
}
ents = { FindInSphere = function() return inSphere end }

ENT = {}
assert(loadfile(ROOT .. "entities/tif_attack_point.lua"))()
local E = ENT
ENT = nil

local function point(fac)
	local p = setmetatable({ nv = { Active = true, Faction = fac or "insurgents", Radius = 500 }, pos = Vector(0, 0, 0) }, { __index = E })
	function p:GetActive() return self.nv.Active end
	function p:SetActive(v) self.nv.Active = v end
	function p:GetFaction() return self.nv.Faction end
	function p:GetRadius() return self.nv.Radius end
	function p:GetPos() return self.pos end
	function p:SetModel() end
	function p:SetMoveType() end
	function p:SetSolid(v) self.solid = v end
	function p:SetCollisionGroup(v) self.cg = v end
	function p:DrawShadow() end
	function p:NextThink() end
	p:Initialize()
	return p
end

local ins = squad("insurgents", 4)
local mil = squad("militia", 3)
local usmc = squad("usmc", 4)
local plyLed = squad("insurgents", 3)
plyLed.leader = ent("insurgents", Vector(), true)
local static = squad("insurgents", 2, { static = true })
local garrison = squad("insurgents", 2)
garrison.members[2].tifBase = {}
local hunters = squad("insurgents", 3)
hunters.members[1].tifHunter = true
local empty = squad("insurgents", 0)

local foe = ent("usmc", Vector(100, 0, 0))
local foePly = ent("usmc", Vector(-100, 0, 0), true)
inSphere = { foe, foePly, ent("insurgents", Vector(0, 50, 0)) }

local ap = point("insurgents")
check(ap.cg == COLLISION_GROUP_WORLD, "no collision with players or soldiers")
local vals = E.SetupDataTables and true
ap:Think()
local adv = {}
for _, a in ipairs(advances) do adv[a.sq] = a.pace end
check(adv[ins] == "rush" and adv[mil] == "rush", "the faction's squads (aliases too) rush it")
check(not adv[usmc], "other factions are left alone")
check(not adv[plyLed] and not adv[static] and not adv[garrison] and not adv[hunters] and not adv[empty], "player-led, static, garrisoned, director / survival and empty squads are left alone")
check(ins.tifAttack == ap, "the squad is claimed by the point")
local n = #advances
ap:Think()
check(#advances == n, "the order is given once, not every tick")

local known = {}
for _, k in ipairs(knows) do if k.sq == ins then known[k.e] = true end end
check(known[foe] and known[foePly], "enemies in its radius (soldiers and players) are known to the squad")
local c = ins.members[2].tifK.contacts[foe]
check(c and c.confirmed and c.source == "objective", "every assaulter has them as confirmed contacts")
check((ins.members[3].tifExpectEnemy or 0) > now, "and expects them (no surprise reaction)")
local friendly = false
for _, k in ipairs(knows) do if k.e.fac == "insurgents" then friendly = true end end
check(not friendly, "own side in the radius isn't marked")

ins.leader.p = Vector(100, 0, 0)
now = now + 1
ap:Think()
check(ins.order.kind == "hold", "the squad holds on the point once its leader gets there")
local holds = 0
for _, o in ipairs(orders) do if o.sq == ins and o.kind == "hold" then holds = holds + 1 end end
now = now + 1
ap:Think()
local holds2 = 0
for _, o in ipairs(orders) do if o.sq == ins and o.kind == "hold" then holds2 = holds2 + 1 end end
check(holds == 1 and holds2 == 1, "once")

local ap2 = point("insurgents")
advances = {}
ap2:Think()
local stolen = false
for _, a in ipairs(advances) do if a.sq == ins or a.sq == mil then stolen = true end end
check(not stolen, "a second point for the same faction doesn't steal claimed squads")

ap:SetActive(false)
ap:Think()
check(ins.order.kind == "free" and ins.tifAttack == nil and mil.order.kind == "free", "switching it off frees its squads")
ap2:Think()
check(ins.tifAttack == ap2, "and another point can take them")
ap2:OnRemove()
check(ins.tifAttack == nil and ins.order.kind == "free", "removing it frees them too")

local pm = io.open(ROOT .. "tif/tactics/sv_passive_mw.lua"):read("*a")
check(pm:find("if (npc.tifExpectEnemy or 0) > now and new ~= AW.UNAWARE then", 1, true) ~= nil, "assaulters skip the startle / new-enemy / point-out reactions")
local src = io.open(ROOT .. "entities/tif_attack_point.lua"):read("*a")
check(src:find('local RADIO_MODEL = "models/props_lab/citizenradio.mdl"', 1, true) and src:find('id ~= "auto" and id ~= "random"', 1, true), "a radio, with a faction dropdown of real factions")
local br = io.open(ROOT .. "tif/npc/sv_brain.lua"):read("*a")
check(br:find('if o and o.kind == "advance" then return false end', 1, true) ~= nil, "the rush isn't slowed by the careful-advance rules")
print(string.format("passed %d, failed %d", pass, fail))
