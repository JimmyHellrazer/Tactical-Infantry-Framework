-- Vehicle occupancy (Phase 6): soldiers boarding, riding in and leaving Glide vehicles.
--
-- Glide seats are player pods. Soldiers don't sit in them: a soldier claims seat n, is parented
-- to the vehicle at the GTA seat position (GTGData) and loops GTG's seat clip (driver: steering
-- pose, passenger: sit). The pod is marked so players can't take it.
--
-- With GTG entry data (GTG car packs) boarding follows GTG's own sequence:
--   walk to the door's stand point -> d_open_out (the door swings open with the clip's Door tags;
--   networked as NW2 "tif_door<entry>", posed on clients by TIF.GTG's door bones)
--   -> get_in (root motion, lifted from the ground to the seat) -> sit -> d_close_in (door shuts).
-- Leaving: get_out (or jump_out when moving; door opens) -> d_close_out (door shuts). Combat
-- dismounts are faster and leave the doors open.
-- Without entry data: walk to Glide's exit position and sit / stand up there.
--
-- While boarding, seated or getting out, soldiers use COLLISION_GROUP_DEBRIS: they don't block
-- each other or the vehicle, and bullets still hit them.
-- Wrecked: occupants of an exploded vehicle die; a removed vehicle drops its occupants.

local TIF = TIF
local GL = TIF.Glide
local G = TIF.GTG
local Act = TIF.Action
local Move = TIF.Move

TIF.Vehicle = TIF.Vehicle or {}
local V = TIF.Vehicle
V.Known = V.Known or setmetatable({}, { __mode = "k" })
V.DoorAnims = V.DoorAnims or {}

local GHOST = COLLISION_GROUP_DEBRIS

local function host_of(npc)
	local f = TIF.Factions[npc:GetTIFFaction()]
	return f and f.host
end

local function log(npc, ...)
	local sq = npc.tifSquad
	if sq and TIF.Squad.Log then TIF.Squad.Log(sq, "[vehicle] #", npc:EntIndex(), " ", ...) end
end

local function norm(y) return math.NormalizeAngle(y) end

function V.SeatCount(veh)
	return istable(veh.seats) and #veh.seats or 0
end

function V.Occupant(veh, n)
	local o = veh.tifSeats and veh.tifSeats[n]
	if IsValid(o) and not o.tifDead and o.tifVeh == veh then return o end
	return nil
end

-- Free for a soldier: nobody sits there or has claimed it (except `except`), no player in the pod.
function V.SeatFree(veh, n, except)
	local o = V.Occupant(veh, n)
	if o and o ~= except then return false end
	local claim = veh.tifClaims and veh.tifClaims[n]
	if IsValid(claim) and claim ~= except and not claim.tifDead and claim.tifBoard then return false end
	local pod = veh.seats and veh.seats[n]
	return IsValid(pod) and not IsValid(pod:GetDriver())
end

function V.Occupants(veh)
	local out = {}
	for n = 1, V.SeatCount(veh) do
		local o = V.Occupant(veh, n)
		if o then out[#out + 1] = o end
	end
	return out
end

function V.Driver(veh) return V.Occupant(veh, 1) end

local function ghost(npc, on)
	if on then
		if npc.tifOldCollision == nil then npc.tifOldCollision = npc:GetCollisionGroup() end
		npc:SetCollisionGroup(GHOST)
	else
		npc:SetCollisionGroup(npc.tifOldCollision or COLLISION_GROUP_NPC)
		npc.tifOldCollision = nil
	end
end

-- Seat fit, tunable live (seated soldiers re-fit within a second):
local cvDrop = CreateConVar("tif_seat_drop", "6", FCVAR_ARCHIVE, "Units soldiers sit lower on vehicles without their own TIF seats")
local cvFwd = CreateConVar("tif_seat_forward", "0", FCVAR_ARCHIVE, "Units soldiers sit further forward on vehicles without their own TIF seats")
local cvDrvFwd = CreateConVar("tif_driver_forward", "6", FCVAR_ARCHIVE, "Extra units the driver sits forward on vehicles without their own TIF seats")

local function fit_stamp()
	return cvDrop:GetFloat() .. ":" .. cvFwd:GetFloat() .. ":" .. cvDrvFwd:GetFloat()
end

-- A vehicle can answer for its own seats (MW cars, tif_mw_cars; VEHICLE_PLAN.md stage 3): ENT:TIFSeatPose(n, npc)
-- and ENT:TIFSeatEntry(n, npc), used instead of the GTA seat data when they return something.
local function own_pose(veh, n, npc)
	if not isfunction(veh.TIFSeatPose) then return nil end
	local ok, p = pcall(veh.TIFSeatPose, veh, n, npc)
	return ok and p or nil
end

local function own_entry(veh, n, npc)
	if not isfunction(veh.TIFSeatEntry) then return nil end
	local ok, e = pcall(veh.TIFSeatEntry, veh, n, npc)
	return ok and e or nil
end

-- Where a soldier sits in seat n: world position and yaw, seat clip, local position and yaw.
local function seat_pose(npc, veh, n)
	local p = own_pose(veh, n, npc) or G.SeatPose(veh, n, host_of(npc))
	local lp, lyaw
	if p and p.lp then
		lp, lyaw = Vector(p.lp), p.yaw
	else
		-- No GTA seat data: sit on the pod (pods face local yaw - 90).
		local pod = veh.seats[n]
		lp = veh:WorldToLocal(pod:GetPos()) - Vector(0, 0, 18)
		lyaw = veh:WorldToLocalAngles(pod:GetAngles()).y + 90
	end
	-- (exact: the vehicle's own seat, made for these clips; the fit cvars are for GTA seats)
	if not (p and p.exact) then
		local fwd = cvFwd:GetFloat() + (n == 1 and cvDrvFwd:GetFloat() or 0)
		local r = math.rad(lyaw)
		lp = lp + Vector(math.cos(r) * fwd, math.sin(r) * fwd, -cvDrop:GetFloat())
	end
	return veh:LocalToWorld(lp), norm(veh:GetAngles().y + lyaw), p and p.clip, lp, lyaw
end

local function ground(pos)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 60), endpos = pos - Vector(0, 0, 160), mask = MASK_SOLID_BRUSHONLY })
	return tr.Hit and tr.HitPos or pos
end

-- Where to stand to get in / out of seat n (world, on the ground), facing yaw, and GTG entry data.
function V.EntryPoint(npc, veh, n)
	local e = own_entry(veh, n, npc) or G.SeatEntry(veh, n, host_of(npc))
	local pos, yaw
	if e then
		pos = veh:LocalToWorld(Vector(e.stand.x, e.stand.y, 0))
		yaw = norm(veh:GetAngles().y + e.face)
	else
		pos = veh.GetSeatExitPos and veh:GetSeatExitPos(n) or veh:GetPos()
		yaw = (veh:GetPos() - pos):Angle().y
	end
	return ground(pos), yaw, e
end

-- Doors ------------------------------------------------------------------------------------------

local function door_ratio(veh, index)
	return veh.tifDoor and veh.tifDoor[index] or 0
end

-- Swing a door from -> to over the Door-tagged part of a clip played at `rate`.
local function door_anim(veh, index, npc, clipName, from, to, rate)
	if not index then return end
	local clip = clipName and Act.Clip(npc, clipName)
	if not clip then
		veh.tifDoor = veh.tifDoor or {}
		veh.tifDoor[index] = to
		G.SetDoor(veh, index, to)
		return
	end
	local wa, wb = G.DoorWindow(clip)
	V.DoorAnims[veh] = V.DoorAnims[veh] or {}
	V.DoorAnims[veh][index] = { from = from, to = to, t0 = CurTime(), dur = clip.dur / (rate or 1), wa = wa or 0.15, wb = wb or 0.6 }
end

hook.Add("Tick", "tif_vehicle_doors", function()
	if next(V.DoorAnims) == nil then return end
	local now = CurTime()
	for veh, list in pairs(V.DoorAnims) do
		if not IsValid(veh) then
			V.DoorAnims[veh] = nil
		else
			for index, d in pairs(list) do
				local u = (now - d.t0) / math.max(0.01, d.dur)
				local k = math.Clamp((u - d.wa) / math.max(0.01, d.wb - d.wa), 0, 1)
				local r = d.from + (d.to - d.from) * k
				veh.tifDoor = veh.tifDoor or {}
				veh.tifDoor[index] = r
				G.SetDoor(veh, index, r)
				if u >= 1 then list[index] = nil end
			end
			if next(list) == nil then V.DoorAnims[veh] = nil end
		end
	end
end)

-- Sit down (parent to the vehicle) -------------------------------------------------------------

function V.Sit(npc, veh, n, settleClip)
	veh.tifSeats = veh.tifSeats or {}
	veh.tifClaims = veh.tifClaims or {}
	veh.tifSeats[n] = npc
	veh.tifClaims[n] = nil
	V.Known[veh] = true
	npc.tifVeh, npc.tifSeatIdx, npc.tifBoard = veh, n, nil
	npc.tifDBSet, npc.tifDriveBy = nil, nil
	npc:SetNW2Float("tif_act_cycle", -1)
	Move.Stop(npc)
	if TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "boarding") end
	local _, _, clip, lp, lyaw = seat_pose(npc, veh, n)
	ghost(npc, true)
	npc:SetMoveType(MOVETYPE_NONE)
	npc:SetParent(veh)
	npc:SetLocalPos(lp)
	npc:SetLocalAngles(Angle(0, lyaw, 0))
	npc.tifSeatLP, npc.tifSeatLYaw = Vector(lp), lyaw
	npc.tifFitStamp = fit_stamp()
	npc.tifSeatClip = clip
	-- Closing the door from inside first, then the seat loop.
	if settleClip and Act.Clip(npc, settleClip) then
		npc.tifSettleUntil = CurTime() + (Act.Play(npc, settleClip) or 0)
	elseif clip then
		Act.Loop(npc, clip)
	else
		Act.Clear(npc)
	end
	npc:SetNW2Entity("tif_veh", veh)
	npc:SetNW2Int("tif_seat", n)
	local pod = veh.seats[n]
	if IsValid(pod) then pod.tifNPC = npc end
	npc.tifFire.want = false
end

-- Leave the seat (unparent) at pos/yaw, still ghosted and not moving on its own.
local function unsit(npc, pos, yaw)
	local veh, n = npc.tifVeh, npc.tifSeatIdx
	if IsValid(veh) and veh.tifSeats and veh.tifSeats[n] == npc then
		veh.tifSeats[n] = nil
		local pod = veh.seats and veh.seats[n]
		if IsValid(pod) then pod.tifNPC = nil end
	end
	npc.tifVeh, npc.tifSeatIdx, npc.tifSettleUntil = nil, nil, nil
	npc.tifDriveBy, npc.tifDBSet = nil, nil
	npc:SetNW2Float("tif_act_cycle", -1)
	npc.tifFire.want = false
	npc:SetParent(nil)
	npc:SetPos(pos)
	npc:SetAngles(Angle(0, yaw, 0))
	npc:SetNW2Entity("tif_veh", NULL)
	npc:SetNW2Int("tif_seat", 0)
	if npc.loco then npc.loco:SetVelocity(vector_origin) end
end

-- Back on its feet: moving and colliding normally.
local function stand(npc)
	npc:SetMoveType(MOVETYPE_CUSTOM)
	ghost(npc, false)
	Act.Clear(npc)
end

-- Boarding ---------------------------------------------------------------------------------------

function V.Board(npc, veh, n)
	if not GL.IsUsable(veh) or not V.SeatFree(veh, n, npc) then return false end
	veh.tifClaims = veh.tifClaims or {}
	veh.tifClaims[n] = npc
	npc.tifBoard = { veh = veh, n = n, phase = "walk", t0 = CurTime() }
	npc.tifBoardFails = npc.tifBoardFails or 0
	ghost(npc, true)
	return true
end

function V.CancelBoard(npc, why)
	local b = npc.tifBoard
	if not b then return end
	if IsValid(b.veh) and b.veh.tifClaims and b.veh.tifClaims[b.n] == npc then b.veh.tifClaims[b.n] = nil end
	npc.tifBoard = nil
	npc.tifBoardFails = (npc.tifBoardFails or 0) + 1
	if b.phase ~= "walk" then stand(npc) else ghost(npc, false) end
	log(npc, "boarding seat ", b.n, " failed: ", why or "?")
end

-- Is another soldier using the door at `pos` right now (opening it or climbing in / out)?
local function door_busy(npc, veh, pos)
	for _, o in ipairs(TIF.Soldiers) do
		if o ~= npc and IsValid(o) then
			local b = o.tifBoard
			local using = (b and b.veh == veh and b.phase ~= "walk" and b.standPos) or (o.tifLeavingVeh == veh and o.tifLeavingAt)
			if using and using:DistToSqr(pos) < 70 * 70 then return true end
		end
	end
	return false
end

-- Could a player see this spot (or is one close to it)?
local function seen(pos)
	local tr = { mask = MASK_SOLID_BRUSHONLY }
	for _, ply in player.Iterator() do
		if ply:Alive() then
			local eye = ply:EyePos()
			local d2 = eye:DistToSqr(pos)
			if d2 < 1000 * 1000 then return true end
			if d2 < 4000 * 4000 then
				tr.start, tr.endpos = eye, pos + Vector(0, 0, 40)
				if not util.TraceLine(tr).Hit then return true end
			end
		end
	end
	return false
end
V.Seen = seen

local cvUnseen = CreateConVar("tif_board_unseen", "1", FCVAR_ARCHIVE,
	"Soldiers boarding where no player can see them go straight into their seats (1/0)")

-- The navmesh doesn't know about the vehicle, so a soldier whose door is on the far side would
-- walk into the bodywork. Corner points (vehicle-local) to go round the front or back instead.
local function around(npc, veh, pos)
	local lo, hi = veh:OBBMins(), veh:OBBMaxs()
	local a, b = veh:WorldToLocal(npc:GetPos()), veh:WorldToLocal(pos)
	local pad = 55
	if (a.y >= 0) == (b.y >= 0) then return {} end
	local yt = b.y >= 0 and hi.y + pad or lo.y - pad
	-- Already clear of the front or back: one corner on the door's side.
	if a.x > hi.x + pad or a.x < lo.x - pad then
		return { Vector(a.x > hi.x and hi.x + pad or lo.x - pad, yt, 0) }
	end
	local front = (a.x + b.x) > (lo.x + hi.x)
	local x = front and hi.x + pad or lo.x - pad
	local ys = a.y >= 0 and hi.y + pad or lo.y - pad
	return { Vector(x, ys, 0), Vector(x, yt, 0) }
end

-- Returns true while boarding controls the soldier.
function V.BoardThink(npc, now)
	local b = npc.tifBoard
	local veh = b.veh
	if not GL.IsUsable(veh) then V.CancelBoard(npc, "vehicle unusable") return false end
	if veh:GetVelocity():Length() > 120 then V.CancelBoard(npc, "vehicle moving") return false end
	if now - b.t0 > 30 then V.CancelBoard(npc, "took too long") return false end
	npc.tifFire.want = false
	npc.tifStance = 0

	if b.phase == "walk" then
		local pos, yaw, e = V.EntryPoint(npc, veh, b.n)
		npc.tifFace = nil
		npc.tifMode = (npc.tifAware == TIF.AWARE.ENGAGED or npc.tifAware == TIF.AWARE.ALERTED) and 1 or 0

		-- Nobody watching: straight into the seat (saves the walk round and the door clips).
		if cvUnseen:GetBool() and npc:GetPos():DistToSqr(veh:GetPos()) < 2000 * 2000
			and not seen(npc:GetPos()) and not seen(veh:GetPos()) then
			log(npc, "seat ", b.n, ": straight in (nobody watching)")
			Move.Stop(npc)
			V.Sit(npc, veh, b.n)
			return true
		end

		-- Round the vehicle first if the door is on the other side.
		if not b.via then
			b.via = {}
			for _, lp in ipairs(around(npc, veh, pos)) do b.via[#b.via + 1] = ground(veh:LocalToWorld(lp)) end
		end
		local via = b.via[1]
		if via and npc:GetPos():DistToSqr(via) < 45 * 45 then
			table.remove(b.via, 1)
			via = b.via[1]
			b.best = nil
		end
		-- Not getting any closer for 3 s (pressed against the car or another soldier): step past it
		-- when nobody's looking, else skip that corner / plan the way round again.
		local target = via or pos
		local dist = npc:GetPos():Distance(target)
		if not b.best or dist < b.best - 15 then
			b.best, b.bestT = dist, now
		elseif now - b.bestT > 3 and dist > 40 then
			b.best = nil
			if not seen(npc:GetPos()) then
				log(npc, "seat ", b.n, ": stuck, stepped past")
				npc:SetPos(target)
				if via then table.remove(b.via, 1) via = b.via[1] end
			elseif via then
				table.remove(b.via, 1)
				via = b.via[1]
			else
				b.via = nil
				return true
			end
		end
		if via then
			npc.tifAction = "round the vehicle (seat " .. b.n .. ")"
			if Move.SetGoal(npc, via, "walk", "board") then return true end
			table.remove(b.via, 1)  -- that corner isn't on the navmesh: skip it
			return true
		end

		local d2 = npc:GetPos():DistToSqr(pos)
		-- Someone else is at this door: wait a step back.
		if d2 < 150 * 150 and door_busy(npc, veh, pos) then
			npc.tifAction = "waiting for the door"
			local back = pos + (pos - veh:GetPos()):GetNormalized() * 90
			if npc:GetPos():DistToSqr(back) > 30 * 30 then Move.SetGoal(npc, back, "walk", "board") else Move.Stop(npc) end
			return true
		end
		if d2 > 28 * 28 then
			npc.tifAction = "to the door (seat " .. b.n .. ")"
			if Move.SetGoal(npc, pos, d2 > 300 * 300 and "run" or "walk", "board") then return true end
			-- No path to the exact spot: close enough is fine.
			if d2 > 140 * 140 then V.CancelBoard(npc, "can't reach the door") return false end
		end
		-- At the door.
		Move.Stop(npc)
		b.standPos, b.yaw, b.e = pos, yaw, e
		npc:SetMoveType(MOVETYPE_NONE)
		npc:SetPos(pos)
		npc:SetAngles(Angle(0, yaw, 0))
		if e and e.door and e.open and door_ratio(veh, e.index) < 0.5 then
			b.phase = "open"
			b.until_ = now + (Act.Play(npc, e.open, { root = true, noTrace = true }) or 0.5)
			door_anim(veh, e.index, npc, e.open, door_ratio(veh, e.index), 1)
			npc.tifAction = "opening the door"
			return true
		end
		b.phase = "open"
		b.until_ = now
	end

	if b.phase == "open" then
		if now < b.until_ then return true end
		local e = b.e
		if e and e.getIn then
			local seatPos, seatYaw = seat_pose(npc, veh, b.n)
			b.phase = "in"
			local opts = { root = true, noTrace = true, lift = { npc:GetPos().z, seatPos.z } }
			-- rootz: the clip climbs in by itself; warped to end exactly in the seat.
			if e.rootz then opts = { root = true, rootz = true, noTrace = true, to = { pos = seatPos, yaw = seatYaw } } end
			b.until_ = now + (Act.Play(npc, e.getIn, opts) or 0.5)
			hook.Run("TIF_SeatClip", npc, veh, b.n, "in", e.getIn)
			npc.tifAction = "getting in"
			return true
		end
		V.Sit(npc, veh, b.n)
		return true
	end

	if b.phase == "in" then
		if now < b.until_ then return true end
		local e = b.e
		local close = e and e.door and e.closeIn or nil
		V.Sit(npc, veh, b.n, close)
		if e and e.door then door_anim(veh, e.index, npc, close, door_ratio(veh, e.index), 0) end
		return true
	end
	return false
end

-- Leaving ---------------------------------------------------------------------------------------

-- Get out now. combat = faster, doors left open, jump out when the vehicle is moving.
-- Returns the time it takes.
function V.Leave(npc, combat)
	local veh, n = npc.tifVeh, npc.tifSeatIdx
	if not IsValid(veh) then
		if npc.tifVeh ~= nil then unsit(npc, npc:GetPos(), npc:GetAngles().y) stand(npc) end
		return 0
	end
	local seatPos, seatYaw = seat_pose(npc, veh, n)
	local pos, yaw, e = V.EntryPoint(npc, veh, n)
	local moving = veh:GetVelocity():Length() > 150
	local clip = e and ((moving and e.jumpOut) or (combat and e.combatOut) or e.getOut)
	if clip and e.rootz then
		-- The vehicle's own exit clip (MW cars): starts on the seat (or its own start spot), carries its own height,
		-- warped so the feet end on the real ground, and hands him back at its release point.
		local from = e.from and e.from[clip]
		if from then
			seatPos = veh:LocalToWorld(Vector(from.lp))
			seatYaw = norm(veh:GetAngles().y + from.lyaw)
		end
		unsit(npc, seatPos, seatYaw)
		npc:SetMoveType(MOVETYPE_NONE)
		ghost(npc, true)
		local c = Act.Clip(npc, clip)
		local opts = { root = true, rootz = true, noTrace = true }
		if c then
			local x, y, r = Act.RootAt(c, 1)
			local rad = math.rad(seatYaw)
			local endPos = Vector(seatPos.x + x * math.cos(rad) - y * math.sin(rad),
				seatPos.y + x * math.sin(rad) + y * math.cos(rad), seatPos.z + (Act.ZAt(c, 1) or 0))
			opts.to = { pos = ground(endPos), yaw = seatYaw + r }
		end
		local dur = Act.Play(npc, clip, opts) or 0
		hook.Run("TIF_SeatClip", npc, veh, n, "out", clip)
		-- (the hand-back time is what callers wait for: he's moving on from there)
		local out = dur * math.Clamp(e.release and e.release[clip] or 1, 0.05, 1)
		npc.tifLeaving = CurTime() + out
		npc.tifLeavingVeh, npc.tifLeavingAt, npc.tifLeavingEntry = veh, pos, e
		npc.tifLeaveClose = nil
		npc.tifAction = "getting out"
		return out
	end
	if not clip then
		local p = TIF.FreeSpot(pos + Vector(0, 0, 4), npc)
		unsit(npc, p, norm(yaw + 180))
		stand(npc)
		V.GuardExit(npc, p)
		return 0
	end
	local rate = combat and 1.35 or 1
	unsit(npc, seatPos, seatYaw)
	npc:SetMoveType(MOVETYPE_NONE)
	ghost(npc, true)
	local dur = Act.Play(npc, clip, { root = true, noTrace = true, lift = { seatPos.z, pos.z }, rate = rate }) or 0
	if e.door then door_anim(veh, e.index, npc, clip, door_ratio(veh, e.index), 1, rate) end
	local now = CurTime()
	npc.tifLeaving = now + dur
	npc.tifLeavingVeh, npc.tifLeavingAt, npc.tifLeavingEntry = veh, pos, e
	-- Shut the door behind, unless it's a fight.
	npc.tifLeaveClose = (not combat and not moving and e.door and e.closeOut) or nil
	npc.tifAction = "getting out"
	return dur
end

-- While getting out: nothing else. Returns true while leaving.
function V.LeaveThink(npc, now)
	if not npc.tifLeaving then return false end
	npc.tifFire.want = false
	Move.Stop(npc)
	if now < npc.tifLeaving then return true end
	local close = npc.tifLeaveClose
	local veh, e = npc.tifLeavingVeh, npc.tifLeavingEntry
	if close and IsValid(veh) then
		npc.tifLeaveClose = nil
		npc.tifLeaving = now + (Act.Play(npc, close, { root = true }) or 0)
		door_anim(veh, e.index, npc, close, door_ratio(veh, e.index), 0)
		npc.tifAction = "closing the door"
		return true
	end
	npc.tifLeaving, npc.tifLeavingVeh, npc.tifLeavingAt, npc.tifLeavingEntry = nil, nil, nil, nil
	-- Settle on the ground, clear of the vehicle and of anyone who got out at the same door, and move
	-- normally again.
	local p = TIF.FreeSpot(ground(npc:GetPos()) + Vector(0, 0, 2), npc)
	npc:SetPos(p)
	stand(npc)
	V.GuardExit(npc, p)
	return false
end

-- The NextBot locomotion keeps a "last valid position", updated only while the bot walks, and puts
-- the bot back there whenever it thinks it's stuck inside something. A soldier who got in without
-- walking to the door (put straight into his seat, e.g. a convoy appearing mid-journey) still has his
-- spawn spot as that position, and the moment after getting out (touching the car) could send him
-- back down the road. So: the stuck state is cleared, and for 3 s any sudden jump away from where he
-- got out is undone.
function V.GuardExit(npc, p)
	if npc.loco and npc.loco.ClearStuck then npc.loco:ClearStuck() end
	npc.tifExitGuard = { pos = Vector(p), untilT = CurTime() + 3 }
end

hook.Add("Tick", "tif_vehicle_exit_guard", function()
	local now = CurTime()
	for _, npc in ipairs(TIF.Soldiers) do
		local g = IsValid(npc) and npc.tifExitGuard
		if g then
			if now > g.untilT or npc.tifVeh or npc.tifDead then
				npc.tifExitGuard = nil
			elseif npc:GetPos():DistToSqr(g.pos) > 250 * 250 then
				npc:SetPos(g.pos)
				if npc.loco then npc.loco:SetVelocity(vector_origin) end
				if npc.loco and npc.loco.ClearStuck then npc.loco:ClearStuck() end
			else
				-- Walking on normally: follow him, so only a jump counts.
				g.pos = npc:GetPos()
			end
		end
	end
end)

-- Riding ----------------------------------------------------------------------------------------

-- (Passenger drive-bys from the windows were GTA clips: dropped with the GTG removal in 0.38.0, user. Bed gunners on
-- MW technicals still fire, through the vehicle's own TIFRideThink below.)
local function driveby() return false end
local function end_driveby(npc)
	if not npc.tifDriveBy then return end
	npc.tifDriveBy = nil
	npc:SetNW2Float("tif_act_cycle", -1)
	if npc.tifSeatClip then Act.Loop(npc, npc.tifSeatClip) end
end

function V.RideThink(npc, now)
	local veh = npc.tifVeh
	if not IsValid(veh) then
		unsit(npc, npc:GetPos(), npc:GetAngles().y)
		stand(npc)
		return false
	end
	npc.tifFace = nil
	npc.tifStance = 0
	npc.tifMode = 0
	-- The vehicle's own riding behaviour first (MW cars: bed gunners turn and fire from their seat). true = it's
	-- handling him this tick.
	if isfunction(veh.TIFRideThink) and not npc.tifSettleUntil then
		local ok, busy = pcall(veh.TIFRideThink, veh, npc, npc.tifSeatIdx, now)
		if ok and busy then return true end
	end
	if driveby(npc, veh, now) then return true end
	end_driveby(npc)
	npc.tifFire.want = false
	npc.tifAction = (npc.tifSeatIdx == 1 and "driving" or ("riding, seat " .. tostring(npc.tifSeatIdx)))
	if npc.tifSettleUntil and now >= npc.tifSettleUntil then
		npc.tifSettleUntil = nil
		if npc.tifSeatClip then Act.Loop(npc, npc.tifSeatClip) end
	end
	if npc:GetParent() ~= veh then V.Sit(npc, veh, npc.tifSeatIdx) end
	-- Seat fit cvars changed: move into the new spot.
	if npc.tifFitStamp ~= fit_stamp() then
		local _, _, _, lp, lyaw = seat_pose(npc, veh, npc.tifSeatIdx)
		npc:SetLocalPos(lp)
		npc:SetLocalAngles(Angle(0, lyaw, 0))
		npc.tifSeatLP, npc.tifSeatLYaw = Vector(lp), lyaw
		npc.tifFitStamp = fit_stamp()
	end
	-- Held in the seat: anything that shoved him (a physgun, a jolt, the engine pushing a parented
	-- entity) is undone straight away.
	if npc:GetMoveType() ~= MOVETYPE_NONE then npc:SetMoveType(MOVETYPE_NONE) end
	local lp = npc.tifSeatLP
	if lp and npc:GetLocalPos():DistToSqr(lp) > 4 then
		npc:SetLocalPos(lp)
		npc:SetLocalAngles(Angle(0, npc.tifSeatLYaw or 0, 0))
	end
	return true
end

-- Soldiers in a vehicle, climbing in or getting out can't be picked up with the physgun or the
-- gravity gun (it pulls them out of their seat or the door animation).
local function in_vehicle(ent)
	return IsValid(ent) and (ent.tifVeh ~= nil or ent.tifLeaving ~= nil or (ent.tifBoard ~= nil and ent.tifBoard.phase ~= "walk"))
end
hook.Add("PhysgunPickup", "tif_vehicle_riders", function(ply, ent)
	if in_vehicle(ent) then return false end
end)
hook.Add("GravGunPickupAllowed", "tif_vehicle_riders", function(ply, ent)
	if in_vehicle(ent) then return false end
end)

-- Glide pods held by soldiers can't be taken by players.
hook.Add("CanPlayerEnterVehicle", "tif_vehicle_seats", function(ply, pod)
	if IsValid(pod.tifNPC) and not pod.tifNPC.tifDead then return false end
end)

-- Wrecks: occupants of an exploded vehicle die; a disabled one is abandoned.
timer.Create("tif_vehicle_watch", 0.5, 0, function()
	for veh in pairs(V.Known) do
		if not IsValid(veh) then
			V.Known[veh] = nil
		elseif veh.hasExploded or not GL.IsUsable(veh) then
			for _, o in ipairs(V.Occupants(veh)) do
				if veh.hasExploded then
					unsit(o, o:GetPos() + Vector(0, 0, 10), o:GetAngles().y)
					stand(o)
					local d = DamageInfo()
					d:SetDamage(o:Health() + 50)
					d:SetDamageType(DMG_BLAST)
					d:SetAttacker(veh)
					d:SetInflictor(veh)
					o:TakeDamageInfo(d)
				else
					V.Leave(o, true)
				end
			end
		end
	end
end)

hook.Add("EntityRemoved", "tif_vehicle_removed", function(ent)
	if not V.Known[ent] then return end
	for n = 1, 16 do
		local o = ent.tifSeats and ent.tifSeats[n]
		if IsValid(o) and o.tifVeh == ent then
			o.tifVeh, o.tifSeatIdx = nil, nil
			o:SetParent(nil)
			o:SetMoveType(MOVETYPE_CUSTOM)
			o:SetCollisionGroup(o.tifOldCollision or COLLISION_GROUP_NPC)
			o.tifOldCollision = nil
		end
	end
end)
