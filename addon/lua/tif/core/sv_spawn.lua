local TIF = TIF

local roomHull = { mins = Vector(-17, -17, 4), maxs = Vector(17, 17, 70), mask = MASK_NPCSOLID }
function TIF.Room(pos, ignore)
	roomHull.start, roomHull.endpos, roomHull.filter = pos, pos, ignore
	local t = util.TraceHull(roomHull)
	return not t.Hit and not t.StartSolid
end

function TIF.FreeSpot(pos, ignore)
	if TIF.Room(pos, ignore) then return pos end
	local down = { mask = MASK_SOLID_BRUSHONLY }
	for r = 40, 160, 40 do
		for k = 0, 7 do
			local a = math.rad(k * 45 + r)
			local p = pos + Vector(math.cos(a) * r, math.sin(a) * r, 0)
			down.start, down.endpos = p + Vector(0, 0, 40), p - Vector(0, 0, 60)
			local g = util.TraceLine(down)
			if g.Hit and not g.StartSolid then
				local q = g.HitPos + Vector(0, 0, 2)
				if TIF.Room(q, ignore) then return q end
			end
		end
	end
	return pos
end

function TIF.SpawnPoints(center, n, radius, loose)
	local areas = loose and navmesh.Find(center, radius or 350, 64, 64) or nil
	radius = radius or (120 + 25 * n)
	local pts = {}
	local tries = 0
	while #pts < n and tries < n * 30 do
		tries = tries + 1
		local p
		if loose then
			if #areas > 0 then
				p = areas[math.random(#areas)]:GetRandomPoint()
			else
				p = center + Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0) * radius
			end
		else

			local a, r = math.Rand(0, math.pi * 2), radius * math.sqrt(math.random()) * (tries < n * 15 and 1 or 0.6)
			p = center + Vector(math.cos(a) * r, math.sin(a) * r, 0)
			local area = navmesh.GetNearestNavArea(p, false, 200, false, true)
			if IsValid(area) then
				p = area:GetClosestPointOnArea(p) or p
			elseif navmesh.GetNavAreaCount() > 0 then
				p = nil
			end
			if p and (math.abs(p.z - center.z) > 160 or (p - center):Length2D() > radius + 24) then p = nil end
		end
		local free = p ~= nil and TIF.Room(p)
		if free then
			for _, q in ipairs(pts) do
				if q:DistToSqr(p) < 48 * 48 then free = false break end
			end
		end
		if free then pts[#pts + 1] = p end
	end
	return pts
end

function TIF.SpawnSoldiers(ply, faction, count, arch, center, face, opts)
	opts = opts or {}
	if navmesh.GetNavAreaCount() == 0 then
		local msg = "This map has no navmesh: soldiers can't move, find cover or withdraw. Run nav_generate (then reload the map)."
		TIF.Warn(msg)
		if IsValid(ply) then ply:ChatPrint("[TIF] " .. msg) end
	end
	if not TIF.Factions[faction] then
		TIF.Error("Unknown faction ", tostring(faction), ". Known: ", table.concat(table.GetKeys(TIF.Factions), ", "))
		return {}
	end
	if arch and not TIF.Archetypes[arch] then
		TIF.Warn("Unknown archetype ", arch, "; using rifleman")
		arch = "rifleman"
	end
	local out = {}

	local pts = opts.points or TIF.SpawnPoints(center, count, opts.radius, opts.loose)
	if IsValid(ply) then undo.Create("TIF Soldiers") end
	for _, p in ipairs(pts) do
		local ent = ents.Create("tif_soldier_" .. faction)
		if not IsValid(ent) then
			ent = ents.Create("tif_soldier")
			if IsValid(ent) then ent.tifSpawnFaction = faction end
		end
		if IsValid(ent) then
			local yaw
			if face == "random" then yaw = math.Rand(-180, 180)
			elseif isvector(face) then yaw = (face - p):Angle().y
			elseif face == "away" and IsValid(ply) then yaw = (p - ply:GetPos()):Angle().y
			elseif IsValid(ply) then yaw = (ply:GetPos() - p):Angle().y
			else yaw = 0 end
			ent.tifArchId = (opts.archetypes and opts.archetypes[#out + 1]) or arch or "rifleman"
			ent.tifHealthOverride = opts.health
			ent.tifNoAutoSquad = #pts > 1 or opts.noSquad
			ent:SetPos(p + Vector(0, 0, 4))
			ent:SetAngles(Angle(0, yaw, 0))
			ent:Spawn()
			ent:Activate()
			out[#out + 1] = ent
			if IsValid(ply) then undo.AddEntity(ent) end
		end
	end
	if IsValid(ply) then
		undo.SetPlayer(ply)
		undo.Finish()
	end

	if #out > 1 and not opts.noSquad then
		local leader = out[1]
		for _, e in ipairs(out) do if e.tifArchId == "leader" then leader = e break end end
		local sq = TIF.Squad.Create(faction, out, leader)
		if opts.order then TIF.Squad.SetOrder(sq, opts.order, opts.orderPos, opts.orderYaw) end
	end
	return out
end

local SQUAD_MIX = {
	"leader", "rifleman", "support", "rifleman", "assault", "marksman", "rpg", "assault",
	"support", "rifleman", "breacher", "rifleman",
}
TIF.SquadMix = SQUAD_MIX
