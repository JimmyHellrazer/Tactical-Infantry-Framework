-- Faction relationships. TIF decides who fights whom itself; HL2 / addon NPCs get a side from their class (below) and
-- are told how to feel about soldiers from the same rules (compat/sv_hl2npc.lua).

local TIF = TIF

TIF.REL_HOSTILE, TIF.REL_NEUTRAL, TIF.REL_ALLY = -1, 0, 1

local cvPlayer = CreateConVar("tif_player_faction", "usmc", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Faction players belong to. Soldiers of this faction treat players as allies.")

-- HL2 / other addons' NPCs (0.38.15, user: "let them be able to acknowledge half life npcs, currently they ignore
-- eachother"): a side from the NPC's HL2 class. Player allies (rebels, vortigaunts...) are on the players' faction;
-- the Combine are "hl2_combine"; zombies / antlions / headcrabs / barnacles "hl2_monster" (hostile to everyone, as
-- every faction is to factions it isn't allied with). Non-combatants (passive citizens, bullseyes, fauna) have none.
-- An NPC of no known class (most addon SNPCs) goes by how it feels about players: hates them "hl2_hostile", likes
-- them the players' faction. An NW2 string "tif_faction" on the NPC overrides all of this (other addons).
local NPC_SIDE = {}
local function side(names, v) for _, n in ipairs(names) do if _G[n] then NPC_SIDE[_G[n]] = v end end end
side({ "CLASS_PLAYER_ALLY", "CLASS_PLAYER_ALLY_VITAL", "CLASS_CITIZEN_REBEL", "CLASS_VORTIGAUNT", "CLASS_CONSCRIPT",
	"CLASS_HACKED_ROLLERMINE" }, "player")
side({ "CLASS_COMBINE", "CLASS_COMBINE_GUNSHIP", "CLASS_MANHACK", "CLASS_METROPOLICE", "CLASS_MILITARY", "CLASS_SCANNER",
	"CLASS_STALKER", "CLASS_PROTOSNIPER", "CLASS_COMBINE_HUNTER" }, "hl2_combine")
side({ "CLASS_ANTLION", "CLASS_BARNACLE", "CLASS_HEADCRAB", "CLASS_ZOMBIE" }, "hl2_monster")
side({ "CLASS_BULLSEYE", "CLASS_CITIZEN_PASSIVE", "CLASS_MISSILE", "CLASS_FLARE", "CLASS_EARTH_FAUNA", "CLASS_PLAYER" }, false)
TIF.NPC_SIDE = NPC_SIDE
TIF.PlayerSides = TIF.PlayerSides or {
	blufor = { name = "BLUFOR", alliesSide = "ally" },
	opfor = { name = "OPFOR", alliesSide = "enemy" },
	independent = { name = "Independent" },
}
TIF.PlayerSideOrder = { "blufor", "opfor", "independent" }

local warnedPf
function TIF.PlayerFaction()
	local id = cvPlayer:GetString()
	if id == "" then return "usmc" end
	if TIF.PlayerSides[id] then return id end
	local F = TIF.Factions
	if not F or F[TIF.FactionCanon(id)] then return id end
	if warnedPf ~= id then
		warnedPf = id
		MsgC(Color(255, 120, 80), "[TIF] tif_player_faction \"" .. id .. "\" isn't installed: players count as usmc\n")
	end
	return "usmc"
end

-- (never combatants, whatever their class says)
TIF.NPC_IGNORE = { npc_bullseye = true, npc_enemyfinder = true, npc_launcher = true, npc_grenade_frag = true,
	npc_satchel = true, npc_tripmine = true, npc_furniture = true, npc_cranedriver = true, npc_apcdriver = true,
	npc_heli_avoidsphere = true, npc_puppet = true, monster_generic = true, generic_actor = true, cycler = true }

local function npc_faction(ent)
	local own = ent:GetNW2String("tif_faction", "")
	if own ~= "" then return own end
	if CLIENT or TIF.NPC_IGNORE[ent:GetClass()] then return nil end
	-- (cached per NPC: class and dispositions don't change in a fight; cleared by TIF.NPCRefresh)
	if ent.tifNpcSide ~= nil then
		return ent.tifNpcSide == "player" and TIF.PlayerFaction() or (ent.tifNpcSide or nil)
	end
	local ok, cls = pcall(ent.Classify, ent)
	local s = ok and NPC_SIDE[cls]
	if s == nil then
		-- unknown class: by its feeling about the (first) player, else none
		local ply = player.GetAll()[1]
		local d = IsValid(ply) and ent.Disposition and ent:Disposition(ply)
		s = (d == D_HT or d == D_FR) and "hl2_hostile" or (d == D_LI and "player") or false
	end
	ent.tifNpcSide = s
	return s == "player" and TIF.PlayerFaction() or (s or nil)
end
TIF.NPCFaction = npc_faction

-- (2026-11-25, user: "make em acknowledge my horde zombies mod") Addon NextBots that tag themselves with an NW2
-- "tif_faction" (horde_zombies' hz_zombie sets "hl2_monster") count like NPCs. TIF's own soldiers / civilians don't.
local function tagged_bot(ent)
	return ent.IsNextBot ~= nil and ent:IsNextBot() and not ent.TIFSoldier and not ent.TIFCivilian
		and ent:GetNW2String("tif_faction", "") ~= ""
end
TIF.TaggedBot = tagged_bot

-- Faction id of an entity, or nil if TIF doesn't consider it a combatant.
function TIF.FactionOf(ent)
	if not IsValid(ent) then return nil end
	if ent.TIFSoldier then return ent:GetTIFFaction() end
	if ent:IsPlayer() then
		local own = ent:GetNW2String("tif_faction", "")
		return own ~= "" and own or TIF.PlayerFaction()
	end
	if ent:IsNPC() or tagged_bot(ent) then return npc_faction(ent) end
	return nil
end

-- (2026-11-25) Old faction ids kept as aliases (militia -> insurgents, pmc -> usmc: config/sh_content.lua): the
-- faction an id stands for, and whether a list (allies / neutral) names it under any of its names.
function TIF.FactionCanon(id)
	local A = TIF.FactionAlias
	return (A and id and A[id]) or id
end
local function names_it(list, id)
	if not list then return false end
	if list[id] then return true end
	for old, new in pairs(TIF.FactionAlias or {}) do
		if new == id and list[old] then return true end
	end
	return false
end

function TIF.RelationId(id)
	local c = TIF.FactionCanon(id)
	local d = TIF.Factions and TIF.Factions[c]
	if d and type(d.relationsAs) == "string" and d.relationsAs ~= c then return TIF.FactionCanon(d.relationsAs) end
	return c
end

local relCache = {}
function TIF.ClearRelationCache() relCache = {} end
timer.Create("tif_relation_cache", 1, 0, TIF.ClearRelationCache)

local relation_of
function TIF.FactionRelation(fa, fb)
	if not fa or not fb or fa == "" or fb == "" then return TIF.REL_NEUTRAL end
	local row = relCache[fa]
	if not row then row = {} relCache[fa] = row end
	local r = row[fb]
	if r == nil then
		r = relation_of(fa, fb)
		row[fb] = r
	end
	return r
end

function relation_of(fa, fb)
	fa, fb = TIF.RelationId(fa), TIF.RelationId(fb)
	if fa == fb then return TIF.REL_ALLY end
	local P = TIF.PlayerSides
	local pa, pb = P[fa], P[fb]
	if pa and pb then return TIF.REL_HOSTILE end
	if pa or pb then
		local ps, oid = pa or pb, pa and fb or fa
		local o = TIF.Factions[oid]
		local mine = pa and fa or fb
		if o and names_it(o.allies, mine) then return TIF.REL_ALLY end
		if o and names_it(o.neutral, mine) then return TIF.REL_NEUTRAL end
		if o and ps.alliesSide and o.side == ps.alliesSide then return TIF.REL_ALLY end
		return TIF.REL_HOSTILE
	end
	local def = TIF.Factions[fa]
	if def then
		if names_it(def.allies, fb) then return TIF.REL_ALLY end
		if names_it(def.neutral, fb) then return TIF.REL_NEUTRAL end
	end
	local other = TIF.Factions[fb]
	if other then
		if names_it(other.allies, fa) then return TIF.REL_ALLY end
		if names_it(other.neutral, fa) then return TIF.REL_NEUTRAL end
	end
	-- Military factions are hostile to every faction they aren't allied or neutral with.
	return TIF.REL_HOSTILE
end

function TIF.Relation(a, b)
	return TIF.FactionRelation(TIF.FactionOf(a), TIF.FactionOf(b))
end

-- GMod's own AI switches (Utilities > AI options in the spawn menu, or the console).
local cvIgnorePlayers = GetConVar("ai_ignoreplayers")

function TIF.IgnorePlayers()
	cvIgnorePlayers = cvIgnorePlayers or GetConVar("ai_ignoreplayers")
	return cvIgnorePlayers ~= nil and cvIgnorePlayers:GetBool()
end

-- Is this entity something a soldier can fight right now?
function TIF.IsLiveCombatant(ent)
	if not IsValid(ent) then return false end
	if ent.TIFSoldier then
		-- Surrendered and downed soldiers are out of the fight.
		return not ent.tifDead and ent:Health() > 0 and not ent.tifSurrendered and not ent.tifDowned
	end
	if ent:IsPlayer() then
		if TIF.IgnorePlayers() then return false end
		return ent:Alive() and ent:GetMoveType() ~= MOVETYPE_NOCLIP and not ent:IsFlagSet(FL_NOTARGET)
	end
	-- HL2 / addon NPCs with a side (TIF.FactionOf), alive and targetable.
	if tagged_bot(ent) then
		if TIF.HL2NPCsOn and not TIF.HL2NPCsOn() then return false end
		-- (horde zombies: hz_dead while their death plays)
		return ent:Health() > 0 and not ent.hz_dead and not ent:IsFlagSet(FL_NOTARGET)
	end
	if ent:IsNPC() then
		if TIF.HL2NPCsOn and not TIF.HL2NPCsOn() then return false end
		return ent:Health() > 0 and not ent:IsFlagSet(FL_NOTARGET) and (ent.GetNPCState == nil or ent:GetNPCState() ~= NPC_STATE_DEAD)
			and TIF.FactionOf(ent) ~= nil
	end
	return false
end

-- Did this entity die (as opposed to becoming untargetable by noclip, notarget or ai_ignoreplayers)?
function TIF.IsDead(ent)
	if not IsValid(ent) then return true end
	if ent.TIFSoldier then return ent.tifDead == true end
	if ent:IsPlayer() then return not ent:Alive() end
	return ent:Health() <= 0
end

-- Eye position for sight checks. Soldiers report their stance height.
function TIF.EyeOf(ent)
	if ent.TIFSoldier then
		local st = ent:GetTIFStance()
		return ent:GetPos() + Vector(0, 0, st == 2 and 16 or (st == 1 and 40 or 62))
	end
	return ent:EyePos()
end
