local TIF = TIF

local cvOn = CreateConVar("tif_hl2_npcs", "1", FCVAR_ARCHIVE, "TIF soldiers and HL2 / addon NPCs see and fight (or help) each other (1/0)")

TIF.NPCs = TIF.NPCs or {}

local function enabled() return cvOn:GetBool() end
TIF.HL2NPCsOn = enabled

local function track(ent)
	if not IsValid(ent) or ent.TIFSoldier or ent.TIFCivilian then return end
	if not (ent:IsNPC() or (ent.IsNextBot and ent:IsNextBot())) then return end
	if TIF.NPC_IGNORE[ent:GetClass()] then return end
	for _, e in ipairs(TIF.NPCs) do if e == ent then return end end
	TIF.NPCs[#TIF.NPCs + 1] = ent
end

hook.Add("OnEntityCreated", "tif_hl2npc", function(ent)
	timer.Simple(0, function() track(ent) end)
end)
hook.Add("EntityRemoved", "tif_hl2npc", function(ent)
	if not (ent:IsNPC() or (ent.IsNextBot and ent:IsNextBot())) or ent.TIFSoldier then return end
	for i = #TIF.NPCs, 1, -1 do if TIF.NPCs[i] == ent then table.remove(TIF.NPCs, i) end end
end)

timer.Simple(1, function() for _, e in ipairs(ents.GetAll()) do track(e) end end)

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

	if tonumber(new) == 0 then
		for _, npc in ipairs(TIF.NPCs) do
			if IsValid(npc) and npc:IsNPC() then
				for _, s in ipairs(TIF.Soldiers) do if IsValid(s) then npc:AddEntityRelationship(s, D_NU, 60) end end
				npc.tifRelTo = nil
			end
		end
	end
end, "tif_hl2npc")
