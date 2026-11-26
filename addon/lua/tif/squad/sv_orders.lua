local TIF = TIF
local SQUAD_MIX = TIF.SquadMix

local function admin(name, fn, help)
	concommand.Add(name, function(ply, cmd, args)
		if not TIF.CanUseDev(ply) then return end
		fn(ply, args)
	end, nil, help)
end

local function crosshair(ply)
	local tr = ply:GetEyeTrace()
	return tr.HitPos
end

admin("tif_spawn", function(ply, args)
	if not IsValid(ply) then return end
	local faction = args[1] or "insurgents"
	local count = math.Clamp(tonumber(args[2]) or 1, 1, 64)
	local spawned = TIF.SpawnSoldiers(ply, faction, count, args[3], crosshair(ply), args[4] or "me")
	TIF.Log("Spawned ", #spawned, " ", faction, " soldier(s)")
end, "tif_spawn <militia|pmc> [count] [archetype] [me|away|random]")

admin("tif_clear", function(ply, args)
	local n = 0
	for _, npc in ipairs(table.Copy(TIF.Soldiers)) do
		if IsValid(npc) and (not args[1] or npc:GetTIFFaction() == args[1]) then
			npc:Remove()
			n = n + 1
		end
	end

	TIF.Log("Removed ", n, " soldier(s)")
end, "tif_clear [faction]: remove soldiers")

admin("tif_spawn_squad", function(ply, args)
	if not IsValid(ply) then return end
	local faction = args[1] or "insurgents"
	local size = math.Clamp(tonumber(args[2]) or 6, 2, 12)
	local mix = {}
	for i = 1, size do
		mix[i] = SQUAD_MIX[i]
	end

	local order = args[3]
	local tr = ply:GetEyeTrace()
	local spawned = TIF.SpawnSoldiers(ply, faction, size, nil, tr.HitPos, args[4] or "away",
		{ archetypes = mix, radius = 200, order = order, orderPos = order and tr.HitPos or nil, orderYaw = order and ply:EyeAngles().y or nil })
	TIF.Log("Spawned a ", faction, " squad of ", #spawned, order and (" with order " .. order) or "")
end, "tif_spawn_squad <faction> [size] [order: hold|follow|free] [face: me|away|random]: mixed squad (leader, support, marksman, assault, riflemen)")

local function nearest_allied_squad(ply)
	local best, bestD
	for _, sq in pairs(TIF.Squad.List) do
		if TIF.FactionRelation(sq.faction, TIF.FactionOf(ply)) == TIF.REL_ALLY then
			for _, m in ipairs(TIF.Squad.Members(sq)) do
				local d = m:GetPos():DistToSqr(ply:GetPos())
				if not bestD or d < bestD then
					best, bestD = sq, d
				end
			end
		end
	end

	return best
end

admin("tif_follow", function(ply, args)
	if not IsValid(ply) then return end
	local radius = tonumber(args[1]) or 1200
	local sq = TIF.Squad.ForPlayer(ply)
	local n = 0
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) and not npc.tifDead and npc.tifSquad ~= sq and TIF.Relation(npc, ply) == TIF.REL_ALLY
			and npc:GetPos():DistToSqr(ply:GetPos()) < radius * radius then
			TIF.Squad.Add(sq, npc)
			n = n + 1
		end
	end

	TIF.Squad.SetOrder(sq, "follow")
	TIF.Log(n, " soldier(s) joined your squad (", #TIF.Squad.Members(sq), " total), following you")
end, "tif_follow [radius]: allied soldiers near you join your squad and follow you")

admin("tif_dismiss", function(ply)
	if not IsValid(ply) then return end
	for _, sq in pairs(TIF.Squad.List) do
		if sq.leader == ply then
			local members = TIF.Squad.Members(sq)
			for _, m in ipairs(members) do
				TIF.Squad.Remove(m)
			end
			if #members > 0 then
				local nsq = TIF.Squad.Create(sq.faction, members)
				TIF.Squad.SetOrder(nsq, "hold", ply:GetPos(), ply:EyeAngles().y)
			end
			TIF.Squad.List[sq.id] = nil
			TIF.Log("Your squad now holds here on its own")
			return
		end
	end

	TIF.Log("You don't lead a squad")
end, "tif_dismiss: your squad stops following you and holds where it is")

local ORDERS = { hold = true, follow = true, regroup = true, advance = true, free = true, clear = true }
admin("tif_order", function(ply, args)
	if not IsValid(ply) then return end
	local kind = args[1]
	if not ORDERS[kind] then
		TIF.Log("Orders: hold, follow, regroup, advance, free, clear")
		return
	end

	local tr = ply:GetEyeTrace()
	local sq

	if IsValid(tr.Entity) and tr.Entity.TIFSoldier and tr.Entity.tifSquad and TIF.Relation(tr.Entity, ply) == TIF.REL_ALLY then
		sq = tr.Entity.tifSquad
	end
	if not sq then
		for _, s in pairs(TIF.Squad.List) do if s.leader == ply then sq = s break end end
	end

	sq = sq or nearest_allied_squad(ply)
	if not sq then
		TIF.Log("No squad to order: look at a soldier, or use tif_follow first")
		return
	end

	if sq.cqb then
		TIF.CQB.Stop(sq, "new order")
	end
	if kind == "clear" then
		if TIF.CQB.Start(sq, tr.HitPos) then
			ply:ChatPrint("[TIF] Squad " .. sq.id .. " clearing the building at your crosshair")
		else
			ply:ChatPrint("[TIF] No way into a building found near your crosshair (look at or into a building)")
		end
		return
	end

	local pos, yaw
	if kind == "hold" or kind == "advance" then
		pos, yaw = tr.HitPos, ply:EyeAngles().y
		if kind == "advance" and IsValid(sq.leader) and sq.leader:IsPlayer() then
			kind = "hold"
		end
	end

	TIF.Squad.SetOrder(sq, kind, pos, yaw)
	TIF.Log("Squad ", sq.id, " (", #TIF.Squad.Members(sq), " soldiers): ", kind, pos and " at your crosshair" or "")
end, "tif_order <hold|follow|regroup|advance|free|clear>: order your squad (or the looked-at soldier's). hold/advance/clear use your crosshair")

admin("tif_formation", function(ply, args)
	if not IsValid(ply) then return end
	local f = args[1]
	if not table.HasValue(TIF.Squad.FORMATIONS, f or "") then
		TIF.Log("Formations: ", table.concat(TIF.Squad.FORMATIONS, ", "))
		return
	end

	local tr = ply:GetEyeTrace()
	local sq = IsValid(tr.Entity) and tr.Entity.TIFSoldier and TIF.Relation(tr.Entity, ply) == TIF.REL_ALLY and tr.Entity.tifSquad or nil
	if not sq then for _, s in pairs(TIF.Squad.List) do if s.leader == ply then sq = s break end end end
	if not sq then
		TIF.Log("No squad: look at a soldier, or lead one with tif_follow")
		return
	end

	sq.formation = f
	TIF.Squad.Publish(sq)
	TIF.Log("Squad ", sq.id, " formation: ", f)
end, "tif_formation <wedge|column|line|file>: formation of your squad (or the looked-at soldier's)")
