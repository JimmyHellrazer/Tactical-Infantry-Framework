-- Vehicle commands (Phase 6). Dev only.
--   tif_vehicle [class]      spawn a Glide vehicle at your crosshair, facing where you look
--                            (default: the first installed MW car, TIF.Mounted.DefaultCar)
--   tif_mount                the squad you look at (or lead, or the nearest) boards the vehicle you
--                            look at, or the nearest one within 2000 units of the squad
--   tif_drive [stay]         that squad drives to your crosshair and gets out (stay = keep riding)
--   tif_vpatrol              that squad drives back and forth between where it is and your crosshair
--   tif_dismount             everyone out now
--   tif_roads [radius]       show which nav areas count as road (yellow) / drivable (grey) for 30 s

local TIF = TIF
local SQ = TIF.Squad
local V = TIF.Vehicle
local MT = TIF.Mounted
local D = TIF.Driver

local function dev(name, fn, help)
	concommand.Add(name, function(ply, cmd, args)
		if not TIF.CanUseDev(ply) then return end
		fn(ply, args)
	end, nil, help)
end

local function say(ply, ...)
	local msg = table.concat({ ... }, "")
	TIF.Log(msg)
	if IsValid(ply) then ply:ChatPrint("[TIF] " .. msg) end
end

-- The squad to command: looked-at soldier's, then one the player leads, then the nearest with a
-- vehicle, then the nearest at all.
local function pick_squad(ply, wantMounted)
	local tr = ply:GetEyeTrace()
	local e = tr.Entity
	if IsValid(e) and e.TIFSoldier and e.tifSquad then return e.tifSquad end
	if IsValid(e) and e.tifSeats then
		for _, o in pairs(e.tifSeats) do if IsValid(o) and o.tifSquad then return o.tifSquad end end
	end
	for _, s in pairs(SQ.List) do if s.leader == ply then return s end end
	local best, bestD
	for _, s in pairs(SQ.List) do
		if not wantMounted or s.mount then
			for _, m in ipairs(SQ.Members(s)) do
				local d = m:GetPos():DistToSqr(ply:GetPos())
				if not bestD or d < bestD then best, bestD = s, d end
			end
		end
	end
	return best
end

dev("tif_vehicle", function(ply, args)
	if not IsValid(ply) then return end
	local class = args[1] -- (nil: TIF.Mounted.DefaultCar)
	local veh, err = MT.SpawnVehicle(class, ply:GetEyeTrace().HitPos, ply:EyeAngles().y)
	if not veh then say(ply, "Couldn't spawn: ", err) return end
	undo.Create("TIF Vehicle")
	undo.AddEntity(veh)
	undo.SetPlayer(ply)
	undo.Finish()
	say(ply, veh:GetClass(), ": ", V.SeatCount(veh), " seats", isfunction(veh.TIFSeatPose) and " (its own TIF seats)" or " (generic MW seat on the Glide seats)")
end, "tif_vehicle [class]: spawn a Glide vehicle at your crosshair")

dev("tif_mount", function(ply)
	if not IsValid(ply) then return end
	local sq = pick_squad(ply)
	if not sq then say(ply, "No squad found") return end
	local tr = ply:GetEyeTrace()
	local veh = IsValid(tr.Entity) and tr.Entity.IsGlideVehicle and tr.Entity or nil
	if not veh then
		local members = SQ.Members(sq)
		local c = members[1] and members[1]:GetPos() or ply:GetPos()
		local bestD
		for _, e in ipairs(ents.FindInSphere(c, 2000)) do
			if TIF.Glide.IsUsable(e) then
				local d = e:GetPos():DistToSqr(c)
				if not bestD or d < bestD then veh, bestD = e, d end
			end
		end
	end
	if not veh then say(ply, "No usable vehicle near squad ", sq.id) return end
	local n = MT.Mount(sq, veh)
	say(ply, "Squad ", sq.id, ": ", n, " soldier(s) boarding")
end, "tif_mount: a squad boards the vehicle you look at (or the nearest)")

dev("tif_drive", function(ply, args)
	if not IsValid(ply) then return end
	local sq = pick_squad(ply, true)
	if not sq or not sq.mount then say(ply, "No mounted squad (tif_mount first)") return end
	local pos = ply:GetEyeTrace().HitPos
	if MT.DriveTo(sq, pos, args[1] == "stay") then
		say(ply, "Squad ", sq.id, " driving to your crosshair", args[1] == "stay" and "" or ", getting out there")
	else
		say(ply, "No route there")
	end
end, "tif_drive [stay]: the mounted squad drives to your crosshair (and gets out unless 'stay')")

dev("tif_vpatrol", function(ply)
	if not IsValid(ply) then return end
	local sq = pick_squad(ply, true)
	if not sq or not sq.mount then say(ply, "No mounted squad (tif_mount first)") return end
	local veh = sq.mount.veh
	MT.Patrol(sq, { ply:GetEyeTrace().HitPos, veh:GetPos() })
	say(ply, "Squad ", sq.id, " patrolling between here and your crosshair")
end, "tif_vpatrol: the mounted squad drives back and forth between where it is and your crosshair")

dev("tif_dismount", function(ply)
	if not IsValid(ply) then return end
	local sq = pick_squad(ply, true)
	if not sq or not sq.mount then say(ply, "No mounted squad") return end
	MT.Dismount(sq, nil, "ordered")
	say(ply, "Squad ", sq.id, " getting out")
end, "tif_dismount: the mounted squad gets out")

-- Convoys ----------------------------------------------------------------------------------------
--   tif_convoy [count] [faction] [class]   a column of vehicles at your crosshair (facing your view),
--                                          each with a squad of 4 that boards it
--   tif_convoy_drive [stay]                the nearest convoy drives to your crosshair and gets out
--   tif_convoy_patrol                      it loops between where its lead is and your crosshair

local CV = TIF.Convoy
local CREW = { "rifleman", "leader", "rifleman", "rpg" }

local function nearest_convoy(ply)
	local best, bestD
	for _, cv in pairs(CV.List) do
		local sq = cv.squads[1]
		local veh = sq and sq.mount and sq.mount.veh
		if IsValid(veh) then
			local d = veh:GetPos():DistToSqr(ply:GetPos())
			if not bestD or d < bestD then best, bestD = cv, d end
		end
	end
	return best
end

dev("tif_convoy", function(ply, args)
	if not IsValid(ply) then return end
	local count = math.Clamp(tonumber(args[1]) or 3, 1, 6)
	local faction = args[2] or "militia"
	local class = args[3] or TIF.Mounted.DefaultCar()
	local tr = ply:GetEyeTrace()
	local yaw = ply:EyeAngles().y
	local fwd = Angle(0, yaw, 0):Forward()
	local side = Angle(0, yaw, 0):Right()
	local squads, vehs = {}, {}
	undo.Create("TIF Convoy")
	for i = 1, count do
		local at = tr.HitPos - fwd * (i - 1) * 480
		local veh, err = MT.SpawnVehicle(class, at, yaw)
		if not veh then say(ply, "Couldn't spawn: ", err) break end
		undo.AddEntity(veh)
		vehs[i] = veh
		local out = TIF.SpawnSoldiers(nil, faction, 4, nil, at + side * 160, at, { archetypes = CREW, radius = 120 })
		for _, e in ipairs(out) do undo.AddEntity(e) end
		if out[1] and out[1].tifSquad then squads[i] = out[1].tifSquad end
	end
	undo.SetPlayer(ply)
	undo.Finish()
	timer.Simple(0.4, function()
		local list = {}
		for i, sq in ipairs(squads) do
			if SQ.List[sq.id] and IsValid(vehs[i]) then
				MT.Mount(sq, vehs[i])
				list[#list + 1] = sq
			end
		end
		local cv = CV.Create(list)
		if cv then say(ply, "Convoy ", cv.id, ": ", #list, " vehicles boarding. tif_convoy_drive / tif_convoy_patrol to move it.") end
	end)
end, "tif_convoy [count] [faction] [class]: a column of vehicles with crews at your crosshair")

dev("tif_convoy_drive", function(ply, args)
	if not IsValid(ply) then return end
	local cv = nearest_convoy(ply)
	if not cv then say(ply, "No convoy (tif_convoy first)") return end
	CV.DriveTo(cv, ply:GetEyeTrace().HitPos, args[1] == "stay")
	say(ply, "Convoy ", cv.id, " driving to your crosshair", args[1] == "stay" and "" or ", getting out there")
end, "tif_convoy_drive [stay]: the nearest convoy drives to your crosshair")

dev("tif_convoy_patrol", function(ply)
	if not IsValid(ply) then return end
	local cv = nearest_convoy(ply)
	if not cv then say(ply, "No convoy (tif_convoy first)") return end
	local lead = cv.squads[1].mount.veh
	CV.Patrol(cv, { lead:GetPos(), ply:GetEyeTrace().HitPos })
	say(ply, "Convoy ", cv.id, " patrolling between its position and your crosshair")
end, "tif_convoy_patrol: the nearest convoy loops between where it is and your crosshair")

-- Debug data ------------------------------------------------------------------------------------

util.AddNetworkString("tif_debug_veh")
local roadsShow = { untilT = 0, list = {} }

dev("tif_roads", function(ply, args)
	if not IsValid(ply) then return end
	local t0 = SysTime()
	local list = TIF.Routes.Classify(ply:GetPos(), tonumber(args[1]) or 3000)
	local n = { road = 0, ground = 0, no = 0 }
	for _, e in ipairs(list) do n[e.surface] = n[e.surface] + 1 end
	roadsShow.list, roadsShow.untilT = list, CurTime() + 30
	say(ply, string.format("%d nav areas: %d road, %d drivable, %d not drivable (%.1f ms). Drawn for 30 s with tif_debug 1.",
		#list, n.road, n.ground, n.no, (SysTime() - t0) * 1000))
end, "tif_roads [radius]: show road / drivable nav areas around you")

timer.Create("tif_debug_veh_send", 0.5, 0, function()
	local cv = GetConVar("tif_debug")
	if not cv or not cv:GetBool() then return end
	local viewers = {}
	for _, ply in player.Iterator() do if TIF.CanUseDev(ply) then viewers[#viewers + 1] = ply end end
	if #viewers == 0 then return end
	local vehs = {}
	for veh in pairs(V.Known) do if IsValid(veh) then vehs[#vehs + 1] = veh end end
	net.Start("tif_debug_veh")
	net.WriteUInt(math.min(#vehs, 15), 4)
	for i = 1, math.min(#vehs, 15) do
		local veh = vehs[i]
		local d = veh.tifDrive
		net.WriteEntity(veh)
		local occ = #V.Occupants(veh)
		local txt = string.format("%d/%d seated", occ, V.SeatCount(veh))
		if d then
			txt = txt .. string.format("  %s (%s)  %s  %d u/s -> %d", d.label, d.source, d.state, d.speedNow or 0, d.vT or 0)
			if d.why then txt = txt .. "  [" .. d.why .. "]" end
		end
		net.WriteString(txt)
		local pts = d and d.pts or {}
		local n = math.min(#pts, 60)
		net.WriteUInt(n, 6)
		for k = 1, n do net.WriteVector(pts[k]) end
		net.WriteUInt(d and math.min(d.i, 63) or 0, 6)
		net.WriteBool(d and d.target ~= nil)
		if d and d.target then net.WriteVector(d.target) end
	end
	local show = CurTime() < roadsShow.untilT and roadsShow.list or {}
	local n = math.min(#show, 400)
	net.WriteUInt(n, 9)
	for k = 1, n do
		local a = show[k].area
		net.WriteUInt(show[k].surface == "road" and 2 or (show[k].surface == "ground" and 1 or 0), 2)
		for c = 0, 3 do net.WriteVector(a:GetCorner(c)) end
	end
	net.Send(viewers)
end)
