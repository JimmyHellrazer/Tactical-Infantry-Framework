-- HL2 / addon NPCs and TIF soldiers (0.38.15, user: "let them be able to acknowledge half life npcs, currently they
-- ignore eachother"). Both ways:
--   TIF -> NPC: every NPC with a side (TIF.FactionOf, core/sh_factions.lua: rebels with the players, the Combine,
--     monsters, addon NPCs by how they feel about players) is in TIF.NPCs, which perception scans like players and
--     soldiers; gunfire, hits and suppression already work on any combatant.
--   NPC -> TIF: NPCs ignore NextBots unless told: each NPC gets a relationship to every soldier from the same rules
--     (hostile = D_HT, allied = D_LI, else D_NU), set once per pair and again when the answer changes (a soldier's
--     faction, tif_player_faction). Checked once a second.
-- tif_hl2_npcs 0 turns it off (both ways).

local TIF = TIF

local cvOn = CreateConVar("tif_hl2_npcs", "1", FCVAR_ARCHIVE, "TIF soldiers and HL2 / addon NPCs see and fight (or help) each other (1/0)")

TIF.NPCs = TIF.NPCs or {}

local function enabled() return cvOn:GetBool() end
TIF.HL2NPCsOn = enabled

-- (2026-11-25) addon NextBots too (horde zombies): whether they count is TIF.FactionOf's call (a tif_faction tag)
local function track(ent)
	if not IsValid(ent) or ent.TIFSoldier or ent.TIFCivilian then return end
	if not (ent:IsNPC() or (ent.IsNextBot and ent:IsNextBot())) then return end
	if TIF.NPC_IGNORE[ent:GetClass()] then return end
	for _, e in ipairs(TIF.NPCs) do if e == ent then return end end
	TIF.NPCs[#TIF.NPCs + 1] = ent
end

-- (a tick later: the NPC's class and keyvalues are set once it has spawned)
hook.Add("OnEntityCreated", "tif_hl2npc", function(ent)
	timer.Simple(0, function() track(ent) end)
end)
hook.Add("EntityRemoved", "tif_hl2npc", function(ent)
	if not (ent:IsNPC() or (ent.IsNextBot and ent:IsNextBot())) or ent.TIFSoldier then return end
	for i = #TIF.NPCs, 1, -1 do if TIF.NPCs[i] == ent then table.remove(TIF.NPCs, i) end end
end)
-- (NPCs already there when TIF loads: a map's own, or after a Lua refresh)
timer.Simple(1, function() for _, e in ipairs(ents.GetAll()) do track(e) end end)

-- Forget cached sides (the players' faction changed, or another addon re-tagged NPCs).
function TIF.NPCRefresh()
	for _, e in ipairs(TIF.NPCs) do if IsValid(e) then e.tifNpcSide, e.tifRelTo = nil, nil end end
end
cvars.AddChangeCallback("tif_player_faction", function() TIF.NPCRefresh() end, "tif_hl2npc")

local DISP = { [TIF.REL_HOSTILE] = D_HT, [TIF.REL_ALLY] = D_LI, [TIF.REL_NEUTRAL] = D_NU }

local function sync()
	if not enabled() then return end
	for i = #TIF.NPCs, 1, -1 do
		local npc = TIF.NPCs[i]
		if not IsValid(npc) then
			table.remove(TIF.NPCs, i)
		elseif npc:IsNPC() and npc:Health() > 0 and TIF.FactionOf(npc) then
			npc.tifRelTo = npc.tifRelTo or {}
			for _, s in ipairs(TIF.Soldiers) do
				if IsValid(s) and not s.tifDead then
					local d = DISP[TIF.Relation(npc, s)] or D_NU
					if npc.tifRelTo[s] ~= d then
						npc.tifRelTo[s] = d
						npc:AddEntityRelationship(s, d, 60)
					end
				end
			end
		end
	end
end
TIF.NPCSync = sync
timer.Create("tif_hl2npc_sync", 1, 0, sync)

cvars.AddChangeCallback("tif_hl2_npcs", function(_, _, new)
	-- Off: back to ignoring each other (NPCs neutral to every soldier).
	if tonumber(new) == 0 then
		for _, npc in ipairs(TIF.NPCs) do
			if IsValid(npc) and npc:IsNPC() then
				for _, s in ipairs(TIF.Soldiers) do if IsValid(s) then npc:AddEntityRelationship(s, D_NU, 60) end end
				npc.tifRelTo = nil
			end
		end
	end
end, "tif_hl2npc")
