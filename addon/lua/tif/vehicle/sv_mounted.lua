-- Mounted squads (Phase 6): a squad boards a vehicle, drives somewhere or patrols a loop, and
-- dismounts at the destination or when it meets the enemy.
--
-- sq.mount = { veh, phase, riders = { npc = seat }, ... }
--   boarding     members walk to their seats (driver: a rifleman, not the leader; the leader rides
--                in seat 2). Ready when all are in, or after 25 s with a driver.
--   ready        waiting for orders
--   driving      the driver follows the route (TIF.Driver)
--   stopping     contact: the driver brakes; when slow, everyone gets out
--   dismounting  passengers out first, one every 0.35 s, then the driver
--   dismounted   on foot; normal squad tactics. A patrol squad remounts when its base is calm.
-- Contact = any rider sees an enemy, or hears/is told of one within 1500 units.

local TIF = TIF
local SQ = TIF.Squad
local V = TIF.Vehicle
local D = TIF.Driver
local R = TIF.Routes
local GL = TIF.Glide

TIF.Mounted = TIF.Mounted or {}
local MT = TIF.Mounted

MT.CONTACT_RANGE = 1500
MT.EXIT_GAP = 0.35
MT.EXIT_SPEED = 25  -- a routine dismount waits until the vehicle is slower than this (u/s)
local DRIVER_PREF = { rifleman = 1, assault = 2, breacher = 2, support = 4, marksman = 4, leader = 9 }

local function log(sq, ...)
	if SQ.Log then SQ.Log(sq, "[vehicle] ", ...) end
end

-- (0.37.0) TIF no longer ships GTA cars (its tif_gta_glide_cars_<car> copies of GTG's pack); vehicles come from the
-- TIF vehicle addons (tif_mw_cars). Saved factions, presets and settings that still name a GTA car (old
-- gtg_grandtheftgmod_<car> or tif_gta_glide_cars_<car>) get the first installed MW car instead: an SUV / pickup for
-- the cars, in MT.CAR_FALLBACK order. MT.DefaultCar() is the class to use when nothing is named.
MT.CAR_FALLBACK = { "tif_mw_cherokee", "tif_mw_ram1500", "tif_mw_hilux", "tif_mw_tundra", "tif_mw_defender",
	"tif_mw_ram1500_armor", "tif_mw_choptop" }
function MT.DefaultCar()
	for _, c in ipairs(MT.CAR_FALLBACK) do
		if scripted_ents.GetStored(c) then return c end
	end
	return nil
end
function MT.VehicleClass(class)
	if not isstring(class) then return MT.DefaultCar() end
	if scripted_ents.GetStored(class) then return class end
	local car = string.match(class, "^gtg_grandtheftgmod_(.+)$") or string.match(class, "^tif_gta_glide_cars_(.+)$")
	if car then
		if scripted_ents.GetStored("tif_gta_glide_cars_" .. car) then return "tif_gta_glide_cars_" .. car end
		return MT.DefaultCar() or class
	end
	return class
end

function MT.SpawnVehicle(class, pos, yaw)
	class = MT.VehicleClass(class)
	if not class then return nil, "no vehicle class (install the TIF vehicle addon)" end
	if not scripted_ents.GetStored(class) then return nil, "no entity class " .. tostring(class) end
	local veh = ents.Create(class)
	if not IsValid(veh) then return nil, "couldn't create " .. class end
	veh:SetPos(pos + Vector(0, 0, 40))
	veh:SetAngles(Angle(0, yaw or 0, 0))
	veh:Spawn()
	veh:Activate()
	if not GL.IsVehicle(veh) then
		veh:Remove()
		return nil, class .. " isn't a Glide vehicle"
	end
	V.Known[veh] = true
	return veh
end

-- Board a vehicle. Returns the number of soldiers assigned a seat.
function MT.Mount(sq, veh)
	if not GL.IsUsable(veh) then return 0 end
	local members = SQ.Members(sq)
	local seats = V.SeatCount(veh)
	if seats == 0 or #members == 0 then return 0 end
	local riders, n = {}, 0
	-- Anyone already sitting in this vehicle keeps their seat.
	local waiting = {}
	for _, m in ipairs(members) do
		if m.tifVeh == veh and m.tifSeatIdx then
			riders[m] = m.tifSeatIdx
			n = n + 1
		else
			if m.tifBoard then V.CancelBoard(m, "new boarding order") end
			m.tifBoardFails = 0
			waiting[#waiting + 1] = m
		end
	end
	-- The driver's seat: the most driver-like soldier that isn't the leader.
	if V.SeatFree(veh, 1) then
		table.sort(waiting, function(a, b)
			local pa = (DRIVER_PREF[a.tifArchId] or 3) + (a == sq.leader and 10 or 0)
			local pb = (DRIVER_PREF[b.tifArchId] or 3) + (b == sq.leader and 10 or 0)
			return pa < pb
		end)
		local d = table.remove(waiting, 1)
		if d and V.Board(d, veh, 1) then riders[d] = 1 n = n + 1 end
	end
	-- Everyone else: the free seat whose door is nearest, leader first.
	table.sort(waiting, function(a, b) return a == sq.leader and b ~= sq.leader end)
	for _, m in ipairs(waiting) do
		local best, bestD
		for s = 2, seats do
			if V.SeatFree(veh, s, m) then
				local p = V.EntryPoint(m, veh, s)
				local d = p:DistToSqr(m:GetPos())
				if not bestD or d < bestD then best, bestD = s, d end
			end
		end
		if best and V.Board(m, veh, best) then riders[m] = best n = n + 1 end
	end
	sq.mount = { veh = veh, phase = "boarding", riders = riders, t0 = CurTime(), prevOrder = sq.order }
	sq.order = { kind = "mounted", time = CurTime() }
	SQ.Publish(sq)
	log(sq, "boarding ", tostring(veh), ": ", n, " of ", #members, " (", seats, " seats)")
	return n
end

-- Board a vehicle someone else drives (a player): passengers only, no stopping for contact (they
-- shoot from the windows), out with MT.Dismount. Returns the number assigned a seat.
function MT.MountPassive(sq, veh)
	local n = MT.Mount(sq, veh)
	if sq.mount then sq.mount.passive = true end
	return n
end

-- Mount with everyone put straight into their seats (no walk to the doors): for a squad that's
-- already "in" the vehicle as far as the story goes, e.g. a convoy appearing mid-journey. The
-- squad is ready on the next tick.
function MT.MountSeated(sq, veh)
	local n = MT.Mount(sq, veh)
	if n == 0 or not sq.mount then return n end
	for m, seat in pairs(sq.mount.riders) do
		if IsValid(m) and m.tifBoard then
			-- (V.Sit stops him and clears the boarding state and the seat claim.)
			V.Sit(m, veh, seat)
		end
	end
	log(sq, "seated directly in ", tostring(veh))
	return n
end

local function seated(sq)
	local mt = sq.mount
	local inside, total = 0, 0
	for m in pairs(mt.riders) do
		if IsValid(m) and not m.tifDead then
			total = total + 1
			if m.tifVeh == mt.veh then inside = inside + 1 end
		end
	end
	return inside, total
end

local function start_drive(sq, dest, dismount, label)
	local mt = sq.mount
	local veh = mt.veh
	local pts, src = R.Build(veh:GetPos(), dest)
	if not pts then
		log(sq, "no route to ", tostring(dest), " (", tostring(src), ")")
		return false
	end
	mt.phase, mt.dest, mt.dismountOnArrive = "driving", dest, dismount
	D.Drive(veh, pts, { source = src, label = label or "drive", onArrive = function()
		if not sq.mount or sq.mount.veh ~= veh then return end
		if sq.mount.patrol then
			local p = sq.mount.patrol
			p.i = p.i % #p.pts + 1
			start_drive(sq, p.pts[p.i], false, "patrol " .. p.i .. "/" .. #p.pts)
		elseif sq.mount.dismountOnArrive then
			MT.Dismount(sq, nil, "arrived")
		else
			sq.mount.phase = "ready"
		end
	end })
	log(sq, label or "drive", ": route of ", #pts, " points (", src, ")")
	return true
end

-- Drive to pos; dismount there unless stay.
function MT.DriveTo(sq, pos, stay)
	local mt = sq.mount
	if not mt then return false end
	mt.patrol = nil
	if mt.phase == "boarding" then mt.pending = { pos = pos, stay = stay } return true end
	return start_drive(sq, pos, not stay)
end

-- Drive a loop of points until contact.
function MT.Patrol(sq, pts)
	local mt = sq.mount
	if not mt or #pts < 2 then return false end
	mt.patrol = { pts = pts, i = 1 }
	if mt.phase == "boarding" then mt.pending = { patrol = true } return true end
	return start_drive(sq, pts[1], false, "patrol 1/" .. #pts)
end

-- Everyone out. threat: where the enemy is (for the debug log; exits use each seat's door).
function MT.Dismount(sq, threat, why)
	local mt = sq.mount
	if not mt or mt.phase == "dismounting" or mt.phase == "dismounted" then return end
	D.Stop(mt.veh, why)
	mt.phase, mt.exitQueue, mt.nextExit, mt.dismountT = "dismounting", {}, CurTime(), CurTime()
	-- Passengers first, driver last.
	local list = {}
	for m, seat in pairs(mt.riders) do
		if IsValid(m) and not m.tifDead then list[#list + 1] = { m = m, seat = seat } end
	end
	table.sort(list, function(a, b) return (a.seat == 1 and 99 or a.seat) < (b.seat == 1 and 99 or b.seat) end)
	for _, e in ipairs(list) do mt.exitQueue[#mt.exitQueue + 1] = e.m end
	mt.combat = threat ~= nil
	log(sq, "dismount (", why or "?", "), ", #list, " getting out")
	if threat and list[1] then TIF.Say(list[1].m, "contact", 0.9) end
end

-- Back in (a patrol after the all-clear).
function MT.Remount(sq)
	local mt = sq.mount
	if not mt or not GL.IsUsable(mt.veh) then return false end
	local patrol = mt.patrol
	local prev = mt.prevOrder
	local convoy = mt.convoy
	sq.mount = nil
	MT.Mount(sq, mt.veh)
	if sq.mount then
		sq.mount.prevOrder = prev
		sq.mount.convoy = convoy
		if patrol then
			sq.mount.patrol = patrol
			sq.mount.pending = { patrol = true }
		end
	end
	return true
end

-- The nearest enemy any rider knows about: contact, distance from the vehicle.
local function contact(sq)
	local mt = sq.mount
	local best, bestD
	for m in pairs(mt.riders) do
		if IsValid(m) and not m.tifDead and m.tifVeh == mt.veh then
			local c = m.tifPrimaryC
			if c and c.confirmed ~= false then
				local d = mt.veh:GetPos():Distance(c.pos)
				if (c.visible or d < MT.CONTACT_RANGE) and (not bestD or d < bestD) then best, bestD = c, d end
			end
		end
	end
	return best, bestD
end

-- When to stop and get out: a patrol (or a parked vehicle) stops for anything within 1200; a
-- vehicle driving somewhere pushes on unless the enemy is within 600. Further enemies only get
-- shot at from the windows (drive-by).
MT.STOP_PATROL = 1200
MT.STOP_TRANSIT = 600

local function tick(sq, mt, now)
	local veh = mt.veh
	if not IsValid(veh) then sq.mount = nil return end
	if not GL.IsUsable(veh) and mt.phase ~= "dismounted" and mt.phase ~= "dismounting" then
		MT.Dismount(sq, nil, "vehicle disabled")
	end

	if mt.phase == "boarding" then
		-- Riders whose boarding failed: try another free seat (3 tries). After 20 s, anyone standing
		-- right by the vehicle is put in a seat directly.
		for m, seat in pairs(mt.riders) do
			if IsValid(m) and not m.tifDead and m.tifVeh ~= veh and not m.tifBoard and not m.tifLeaving then
				local s = V.SeatFree(veh, seat, m) and seat or nil
				if not s then
					for k = 2, V.SeatCount(veh) do if V.SeatFree(veh, k, m) then s = k break end end
				end
				if s and (m.tifBoardFails or 0) < 3 then
					if V.Board(m, veh, s) then mt.riders[m] = s end
				elseif s and now - mt.t0 > 20 and m:GetPos():DistToSqr(veh:GetPos()) < 260 * 260 then
					V.Sit(m, veh, s)
					mt.riders[m] = s
					log(sq, "#", m:EntIndex(), " put straight into seat ", s)
				elseif not s then
					mt.riders[m] = nil
					log(sq, "#", m:EntIndex(), " has no seat left")
				end
			end
		end
		local inside, total = seated(sq)
		local driverIn = V.Driver(veh) ~= nil
		if total == 0 then sq.mount = nil return end
		if inside >= total or (now - mt.t0 > 25 and driverIn) then
			mt.phase = "ready"
			log(sq, "mounted (", inside, "/", total, ")")
			local p = mt.pending
			mt.pending = nil
			if mt.convoy then
				-- Part of a convoy: the convoy sets off when every vehicle is ready.
			elseif p and p.patrol and mt.patrol then
				start_drive(sq, mt.patrol.pts[mt.patrol.i], false, "patrol " .. mt.patrol.i .. "/" .. #mt.patrol.pts)
			elseif p and p.pos then
				start_drive(sq, p.pos, not p.stay)
			end
		elseif now - mt.t0 > 30 then
			log(sq, "boarding failed (", inside, "/", total, " in, no driver)")
			MT.Dismount(sq, nil, "boarding failed")
		end
		return
	end

	-- Passengers of a player-driven vehicle (MountPassive): the player decides when to stop; they
	-- get out when told (Dismount) or when the vehicle is wrecked.
	if mt.passive and (mt.phase == "driving" or mt.phase == "ready") then return end

	if mt.phase == "driving" or mt.phase == "ready" then
		local c, d = contact(sq)
		local transit = mt.phase == "driving" and not mt.patrol and mt.dest ~= nil
		local stopAt = transit and MT.STOP_TRANSIT or MT.STOP_PATROL
		if c and d < stopAt then
			mt.threat = Vector(c.pos)
			mt.phase = "stopping"
			D.Stop(veh, "contact")
			log(sq, "contact, stopping")
		end
		return
	end

	if mt.phase == "stopping" then
		if veh:GetVelocity():Length() < 140 or now - (mt.stopT or now) > 4 then
			MT.Dismount(sq, mt.threat, "contact")
		end
		mt.stopT = mt.stopT or now
		return
	end

	if mt.phase == "dismounting" then
		-- Not under fire: the vehicle comes to a proper stop before anyone gets out (up to 6 s; a
		-- combat dismount doesn't wait, and jumps out of a moving vehicle if it has to).
		if not mt.combat and IsValid(veh) and veh:GetVelocity():Length() > MT.EXIT_SPEED and now - (mt.dismountT or now) < 6 then
			mt.nextExit = now + 0.5
			return
		end
		if now >= mt.nextExit then
			local m = table.remove(mt.exitQueue, 1)
			while m and not (IsValid(m) and m.tifVeh == veh) do m = table.remove(mt.exitQueue, 1) end
			if m then
				V.Leave(m, mt.combat)
				mt.nextExit = now + MT.EXIT_GAP
			end
		end
		if #mt.exitQueue == 0 and #V.Occupants(veh) == 0 then
			mt.phase = "dismounted"
			-- On foot: back to the squad's order before mounting (or free).
			local prev = mt.prevOrder
			if prev and prev.kind ~= "mounted" then sq.order = prev prev.time = now else sq.order = { kind = "free", time = now } end
			SQ.Publish(sq)
			log(sq, "on foot")
		end
		return
	end
end

timer.Create("tif_mounted_tick", 0.25, 0, function()
	if TIF.AIDisabled() then return end
	local now = CurTime()
	for _, sq in pairs(SQ.List) do
		if sq.mount then
			local ok, err = pcall(tick, sq, sq.mount, now)
			if not ok then TIF.Error("Mounted squad error: ", tostring(err)) end
		end
	end
end)

-- Is the squad busy with its vehicle (tactics should wait)?
function MT.Busy(sq)
	return sq.mount ~= nil and sq.mount.phase ~= "dismounted"
end
