local TIF = TIF

TIF.SPAWN_ROLES = { "rifleman", "leader", "assault", "support", "marksman", "rpg", "breacher", "guard" }
TIF.SPAWN_GROUPS = { { key = "fireteam", name = "Fireteam (4)", count = 4 }, { key = "squad", name = "Squad (8)", count = 8 } }

local added = {}

local function category(def, id)
	return "TIF - " .. (def.name or id)
end

function TIF.RefreshSpawnList()
	local npcs = list.GetForEdit("NPC")
	local now = {}

	for id, def in pairs(TIF.Factions or {}) do
		if istable(def) and not def.hidden and (def.models or def.variants) then
			local cat = category(def, id)
			local side = def.side == "ally" and " (ally)" or (def.side == "enemy" and " (enemy)" or "")

			for _, arch in ipairs(TIF.SPAWN_ROLES) do
				local a = TIF.Archetypes and TIF.Archetypes[arch]
				if a then
					local key = "tif_" .. id .. "_" .. arch
					npcs[key] = { Name = (a.label or arch) .. side, Class = "tif_soldier", Category = cat,
						KeyValues = { tif_faction = id, tif_arch = arch } }
					now[key] = true
				end
			end

			for _, g in ipairs(TIF.SPAWN_GROUPS) do
				local key = "tif_" .. id .. "_" .. g.key
				npcs[key] = { Name = g.name .. side, Class = "tif_spawner", Category = cat,
					KeyValues = { tif_faction = id, tif_count = tostring(g.count) } }
				now[key] = true
			end
		end
	end

	local CIV = "TIF - Civilians"
	for key, e in pairs({
		tif_civ_one = { Name = "Civilian", KeyValues = {} },
		tif_civ_stay = { Name = "Civilian (stays, hides)", KeyValues = { tif_civ_noleave = "1" } },
		tif_civ_crowd = { Name = "Crowd (8)", KeyValues = { tif_civ_crowd = "8" } },
	}) do
		npcs[key] = { Name = e.Name, Class = "tif_civilian", Category = CIV, KeyValues = e.KeyValues }
		now[key] = true
	end

	local changed = false
	for key in pairs(added) do
		if not now[key] then
			npcs[key] = nil
			changed = true
		end
	end

	for key in pairs(now) do
		if not added[key] then
			changed = true
		end
	end

	added = now

	if CLIENT and changed and IsValid(g_SpawnMenu) then
		timer.Create("tif_spawnmenu_reload", 1, 1, function() RunConsoleCommand("spawnmenu_reload") end)
	end
end

TIF.RefreshSpawnList()
