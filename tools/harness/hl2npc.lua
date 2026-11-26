timer = timer or { Create = function() end, Simple = function() end, Remove = function() end }
-- Offline (0.38.15): HL2 / addon NPCs get a side (core/sh_factions.lua) and NPC <-> soldier relationships (compat/sv_hl2npc.lua).
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
SERVER, CLIENT = true, false
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
bit = { bor = function(a, b) return a + b end }
local cv = { tif_player_faction = "pmc", tif_hl2_npcs = "1" }
function CreateConVar(name, def) cv[name] = cv[name] or def return {
	GetString = function() return cv[name] end, GetBool = function() return cv[name] ~= "0" end } end
function GetConVar(name) return cv[name] and { GetBool = function() return cv[name] == "1" end } or nil end
local cbs = {}
cvars = { AddChangeCallback = function(n, fn) cbs[n] = fn end }
CLASS_PLAYER, CLASS_PLAYER_ALLY, CLASS_PLAYER_ALLY_VITAL, CLASS_ANTLION, CLASS_BARNACLE, CLASS_BULLSEYE = 1, 2, 3, 4, 5, 6
CLASS_CITIZEN_PASSIVE, CLASS_CITIZEN_REBEL, CLASS_COMBINE, CLASS_COMBINE_GUNSHIP, CLASS_CONSCRIPT, CLASS_HEADCRAB = 7, 8, 9, 10, 11, 12
CLASS_MANHACK, CLASS_METROPOLICE, CLASS_MILITARY, CLASS_SCANNER, CLASS_STALKER, CLASS_VORTIGAUNT, CLASS_ZOMBIE = 13, 14, 15, 16, 17, 18, 19
CLASS_PROTOSNIPER, CLASS_MISSILE, CLASS_FLARE, CLASS_EARTH_FAUNA, CLASS_HACKED_ROLLERMINE, CLASS_COMBINE_HUNTER = 20, 21, 22, 23, 24, 25
D_ER, D_HT, D_FR, D_LI, D_NU = 0, 1, 2, 3, 4
FL_NOTARGET, MOVETYPE_NOCLIP, NPC_STATE_DEAD = 1, 8, 7
function IsValid(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
local plyDisp = {}
local ply = { IsPlayer = function() return true end, IsNPC = function() return false end, GetNW2String = function(_, _, d) return d end,
	Alive = function() return true end, GetMoveType = function() return 0 end, IsFlagSet = function() return false end }
player = { GetAll = function() return { ply } end }
TIF = { Factions = { pmc = { side = "ally" }, militia = { side = "enemy" } } }
assert(loadfile(ROOT .. "tif/core/sh_factions.lua"))()

local function npc(class, cls, o)
	o = o or {}
	local e = { class = class, cls = cls, hp = o.hp or 50, rel = {} }
	function e:IsNPC() return true end
	function e:IsPlayer() return false end
	function e:GetClass() return self.class end
	function e:Classify() return self.cls end
	function e:Health() return self.hp end
	function e:IsFlagSet() return false end
	function e:GetNPCState() return 3 end
	function e:GetNW2String(_, d) return o.tag or d end
	function e:Disposition(p) return o.disp or D_NU end
	function e:AddEntityRelationship(t, d) self.rel[t] = d end
	return e
end
local function soldier(f)
	return { TIFSoldier = true, GetTIFFaction = function() return f end, IsPlayer = function() return false end,
		IsNPC = function() return false end, Health = function() return 100 end }
end

local combine = npc("npc_combine_s", CLASS_COMBINE)
local cop = npc("npc_metropolice", CLASS_METROPOLICE)
local rebel = npc("npc_citizen", CLASS_PLAYER_ALLY)
local vort = npc("npc_vortigaunt", CLASS_VORTIGAUNT)
local zombie = npc("npc_zombie", CLASS_ZOMBIE)
local antlion = npc("npc_antlion", CLASS_ANTLION)
local passive = npc("npc_citizen", CLASS_CITIZEN_PASSIVE)
local bull = npc("npc_bullseye", CLASS_BULLSEYE)
local vjHater = npc("npc_vj_thing", 0, { disp = D_HT })
local vjFriend = npc("npc_vj_pal", 0, { disp = D_LI })
local tagged = npc("npc_whatever", CLASS_COMBINE, { tag = "militia" })
check(TIF.FactionOf(combine) == "hl2_combine" and TIF.FactionOf(cop) == "hl2_combine", "Combine / metrocops: hl2_combine")
check(TIF.FactionOf(rebel) == "pmc" and TIF.FactionOf(vort) == "pmc", "rebels / vortigaunts: the players' faction")
check(TIF.FactionOf(zombie) == "hl2_monster" and TIF.FactionOf(antlion) == "hl2_monster", "zombies / antlions: hl2_monster")
check(TIF.FactionOf(passive) == nil and TIF.FactionOf(bull) == nil, "passive citizens / bullseyes: no side")
check(TIF.FactionOf(vjHater) == "hl2_hostile" and TIF.FactionOf(vjFriend) == "pmc", "unknown class: by how it feels about players")
check(TIF.FactionOf(tagged) == "militia", "an NW2 tif_faction tag wins")
local pmc, mil = soldier("pmc"), soldier("militia")
check(TIF.Relation(pmc, combine) == TIF.REL_HOSTILE and TIF.Relation(mil, combine) == TIF.REL_HOSTILE, "Combine: hostile to TIF factions")
check(TIF.Relation(pmc, rebel) == TIF.REL_ALLY and TIF.Relation(mil, rebel) == TIF.REL_HOSTILE, "rebels: with the PMC, against the militia")
check(TIF.Relation(pmc, zombie) == TIF.REL_HOSTILE and TIF.Relation(mil, zombie) == TIF.REL_HOSTILE, "zombies: everyone's enemy")
check(TIF.Relation(mil, tagged) == TIF.REL_ALLY, "a militia-tagged NPC is the militia's ally")
check(TIF.IsLiveCombatant(combine) and TIF.IsLiveCombatant(zombie) and not TIF.IsLiveCombatant(passive), "combatants: sided NPCs only")
local dead = npc("npc_combine_s", CLASS_COMBINE, { hp = 0 })
check(not TIF.IsLiveCombatant(dead), "a dead NPC isn't")
-- the players' faction changes: rebels follow (cache cleared by TIF.NPCRefresh)
cv.tif_player_faction = "militia"
check(TIF.FactionOf(rebel) == "militia", "rebels follow tif_player_faction")
cv.tif_player_faction = "pmc"

-- sync: NPC -> soldier relationships
local function bot(class, o)
	o = o or {}
	local e = { class = class, hp = o.hp or 100 }
	function e:IsNPC() return false end
	function e:IsNextBot() return true end
	function e:IsPlayer() return false end
	function e:GetClass() return self.class end
	function e:Health() return self.hp end
	function e:IsFlagSet() return false end
	function e:GetNW2String(k, d) if k == "tif_faction" and o.tag then return o.tag end return d end
	return e
end
-- 2026-11-25: horde_zombies' hz_zombie (a NextBot tagged tif_faction = hl2_monster)
local hz = bot("hz_zombie", { tag = "hl2_monster" })
local civBot = bot("tif_civilian")
civBot.TIFCivilian = true
local plainBot = bot("some_nextbot")
check(TIF.FactionOf(hz) == "hl2_monster", "horde zombie: its tif_faction tag (hl2_monster)")
check(TIF.Relation(pmc, hz) == TIF.REL_HOSTILE and TIF.Relation(mil, hz) == TIF.REL_HOSTILE, "horde zombies: hostile to every TIF faction")
check(TIF.IsLiveCombatant(hz), "a live horde zombie is a combatant")
hz.hz_dead = true
check(not TIF.IsLiveCombatant(hz), "... not while its death plays (hz_dead)")
hz.hz_dead = nil
check(TIF.FactionOf(civBot) == nil and not TIF.IsLiveCombatant(civBot), "TIF civilians: no side")
check(TIF.FactionOf(plainBot) == nil and not TIF.IsLiveCombatant(plainBot), "an untagged NextBot: no side")

local hooks, timers = {}, {}
hook = { Add = function(ev, id, fn) hooks[ev] = fn end }
timer = { Simple = function(_, fn) fn() end, Create = function(n, _, _, fn) timers[n] = fn end }
ents = { GetAll = function() return { combine, rebel, zombie, passive, bull, hz, civBot } end }
TIF.Soldiers = { pmc, mil }
TIF.NPCs = {}
assert(loadfile(ROOT .. "tif/compat/sv_hl2npc.lua"))()
check(#TIF.NPCs == 5, "tracked: the NPCs and the horde zombie, not the bullseye or civilian (" .. #TIF.NPCs .. ")")
local okSync = pcall(timers.tif_hl2npc_sync)
check(okSync, "sync skips the NextBots (no NPC relationships on them)")
check(combine.rel[pmc] == D_HT and combine.rel[mil] == D_HT, "Combine hate both soldiers")
check(rebel.rel[pmc] == D_LI and rebel.rel[mil] == D_HT, "rebels like the PMC, hate the militia")
check(zombie.rel[pmc] == D_HT, "zombies hate soldiers")
check(next(passive.rel) == nil, "passive citizens untouched")
local calls = 0
local add0 = combine.AddEntityRelationship
combine.AddEntityRelationship = function(s, t, d) calls = calls + 1 add0(s, t, d) end
timers.tif_hl2npc_sync()
check(calls == 0, "set once per pair, not every second")
-- switched off: neutral again, and not combatants
cv.tif_hl2_npcs = "0"
check(pcall(cbs.tif_hl2_npcs, nil, "1", "0"), "switching off: no error on the NextBots")
check(combine.rel[pmc] == D_NU, "tif_hl2_npcs 0: NPCs back to neutral")
check(not TIF.IsLiveCombatant(combine), "tif_hl2_npcs 0: not combatants")
cv.tif_hl2_npcs = "1"
-- perception scans them
local src = io.open(ROOT .. "tif/npc/sv_perception.lua"):read("*a")
check(src:find("for _, e in ipairs(TIF.NPCs) do if IsValid(e) then consider(e) end end", 1, true) ~= nil, "perception considers NPCs")
-- 2026-11-25: old faction ids as aliases (militia -> insurgents, pmc -> usmc)
do
	TIF.Factions.insurgents = { side = "enemy" } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
	TIF.Factions.usmc = { side = "ally" } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
	TIF.Factions.chechen = { side = "enemy", allies = { militia = true } }   -- a content pack naming the old id
	if TIF.ClearRelationCache then TIF.ClearRelationCache() end
	TIF.Factions.contractors = { side = "ally", allies = { pmc = true } } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
	TIF.FactionAlias = { militia = "insurgents", pmc = "usmc" }
	local R = TIF.FactionRelation
	check(R("militia", "insurgents") == TIF.REL_ALLY and R("pmc", "usmc") == TIF.REL_ALLY, "an alias is its faction")
	check(R("chechen", "insurgents") == TIF.REL_ALLY and R("insurgents", "chechen") == TIF.REL_ALLY, "allied with militia = allied with the insurgents, both ways")
	check(R("contractors", "usmc") == TIF.REL_ALLY, "allied with pmc = allied with the marines")
	check(R("insurgents", "usmc") == TIF.REL_HOSTILE and R("militia", "pmc") == TIF.REL_HOSTILE, "insurgents vs marines: hostile (old ids too)")
	check(R("chechen", "usmc") == TIF.REL_HOSTILE, "others stay hostile")
	TIF.FactionAlias = nil
end
print(string.format("passed %d, failed %d", pass, fail))
