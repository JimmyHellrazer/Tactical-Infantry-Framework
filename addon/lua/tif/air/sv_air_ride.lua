-- Helicopter passengers: riding on the helicopter's CoD tags, then out with the CoD dismount clip and straight
-- into movement (no MP-style wait: TIF takes the man back at the clip's release point, already moving).
--
-- Seat data (tags, start offsets, hover heights, release points): TIF_AIR_INFIL, generated into the tif_air
-- addon by K:/jimmyproject/tif_air/heli_infil_data.py. Clips (mwhb_*): tif_mw_anims, family "heli".
--
-- A rider has npc.tifHeli (this module's state) and npc.tifVeh = the helicopter for as long as he's on board or in
-- the dismount clip: everything in TIF that leaves vehicle riders alone (movement, facing, cover, weapon choice,
-- reactions) leaves him alone too. The brain calls Ride.Think first (npc/sv_brain.lua).

local TIF = TIF
local Air = TIF.Air
local Act = TIF.Action

TIF.AirRide = TIF.AirRide or {}
local Ride = TIF.AirRide

local GHOST = COLLISION_GROUP_DEBRIS

-- Seat sets for a helicopter type: { <set id> = { kind = "land" | "rope", hub, men = { ... } } } or nil.
-- A man: { role, tag, off, yaw (his seat), exits = { <suffix> = { off, yaw, release, vel } } }: several exits are
-- styles (Little Bird bench: run / ready / patrol); the clip is <role>_<suffix>.
function Ride.Sets(typeId)
	return istable(TIF_AIR_INFIL) and TIF_AIR_INFIL[typeId] or nil
end

-- The seat set for a drop: kind = the route mode ("land" / "rope"); want = a set id, else one of that kind at random
-- (variety: the Little Bird has two landed sets).
function Ride.SetFor(typeId, mode, want)
	local sets = Ride.Sets(typeId)
	if not sets then return nil end
	if want and sets[want] and sets[want].kind == mode then return sets[want], want end
	local ids = {}
	for id, s in pairs(sets) do if s.kind == mode then ids[#ids + 1] = id end end
	if #ids == 0 then return nil end
	table.sort(ids)
	local id = ids[math.random(#ids)]
	return sets[id], id
end

-- Which exit a man uses. One exit: that one. Styles (Little Bird bench): with a fight on, mostly straight into a run,
-- some stop with the gun up; calm, mostly walk off on patrol. want: the game mode's pick for the whole drop.
local function pick_exit(npc, man, want)
	local ex = man.exits
	if want and ex[want] then return want end
	local keys = {}
	for k in pairs(ex) do keys[#keys + 1] = k end
	if #keys == 1 then return keys[1] end
	local AW = TIF.AWARE
	local hot = (AW ~= nil and npc.tifAware ~= nil and (npc.tifAware == AW.ENGAGED or npc.tifAware == AW.ALERTED))
		or (npc.tifSquad ~= nil and npc.tifSquad.engaged == true)
	local r = math.random()
	if hot then
		if ex.run and r < 0.7 then return "run" end
		if ex.ready then return "ready" end
	else
		if ex.patrol and r < 0.6 then return "patrol" end
		if ex.run then return "run" end
	end
	table.sort(keys)
	return keys[math.random(#keys)]
end

local function ghost(npc, on)
	if on then
		if npc.tifOldCollision == nil then npc.tifOldCollision = npc:GetCollisionGroup() end
		npc:SetCollisionGroup(GHOST)
	else
		npc:SetCollisionGroup(npc.tifOldCollision or COLLISION_GROUP_NPC)
		npc.tifOldCollision = nil
	end
end

-- A tag's place in the helicopter's own frame: local position and yaw.
local function tag_local(heli, tag)
	local id = heli:LookupAttachment(tag)
	local a = id and id > 0 and heli:GetAttachment(id)
	-- (tag_body: the CoD model frame itself, i.e. the entity's origin (the rotor hub); sets authored in the
	-- helicopter's own frame ride on it. Models built before 0.29.0 don't carry it as an attachment.)
	if not a and tag == "tag_body" then return Vector(0, 0, 0), 0 end
	if not a then return nil end
	local lp, la = WorldToLocal(a.Pos, a.Ang, heli:GetPos(), heli:GetAngles())
	return lp, la.y
end

-- Where a man sits (helicopter frame): the tag, then his clip's own start offset on it. place: the man (his seat)
-- or one of his exits (where that clip starts: the same spot, a few units off on some).
local function seat_local(heli, man, place)
	place = place or man
	local tp, tyaw = tag_local(heli, man.tag)
	if not tp then return nil end
	local o = Vector(place.off[1], place.off[2], place.off[3])
	o:Rotate(Angle(0, tyaw, 0))
	return tp + o, tyaw + place.yaw
end

local function clip_ok(npc, name)
	return Act.Clip(npc, name) ~= nil
end

-- Put soldiers on board (now, wherever they are). Returns how many got a seat.
function Ride.Board(heli, soldiers, set, setId, style)
	if not (IsValid(heli) and set) then return 0 end
	heli.tifRiders = heli.tifRiders or {}
	local n = 0
	for i, npc in ipairs(soldiers) do
		local man = set.men[i]
		if not man then break end
		if IsValid(npc) and not npc.tifDead then
			local lp, lyaw = seat_local(heli, man)
			if lp then
				TIF.Move.Stop(npc)
				if TIF.CoverBehave and TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "boarding") end
				npc.tifHeli = { heli = heli, man = man, set = set, setId = setId, style = style, state = "ride", lp = lp, lyaw = lyaw }
				npc.tifVeh = heli
				ghost(npc, true)
				-- Sent to every client that gets the helicopter (men popped in late when the helicopter came into view
				-- before they did), and no shadows while aboard / on the ropes (20 m up, Source stretched them huge).
				if npc.SetTransmitWithParent then npc:SetTransmitWithParent(true) end
				npc:SetNW2Bool("tif_noshadow", true)
				npc:SetMoveType(MOVETYPE_NONE)
				npc:SetParent(heli)
				npc:SetLocalPos(lp)
				npc:SetLocalAngles(Angle(0, lyaw, 0))
				if npc.loco then npc.loco:SetVelocity(vector_origin) end
				local idle = man.role .. "_idle"
				if clip_ok(npc, idle) then Act.Loop(npc, idle) else Act.Clear(npc) end
				npc.tifFire.want = false
				table.insert(heli.tifRiders, npc)
				n = n + 1
			end
		end
	end
	return n
end

-- Off the helicopter and moving normally again.
local function stand(npc, keep)
	npc:SetMoveType(MOVETYPE_CUSTOM)
	ghost(npc, false)
	npc.tifVeh = nil
	if not keep then npc.tifHeli = nil end
	if npc.SetTransmitWithParent then npc:SetTransmitWithParent(false) end
	npc:SetNW2Bool("tif_noshadow", false)
	if npc.loco and npc.loco.ClearStuck then npc.loco:ClearStuck() end
end

local function ground_below(p)
	local tr = util.TraceLine({ start = p + Vector(0, 0, 40), endpos = p - Vector(0, 0, 3000), mask = MASK_SOLID_BRUSHONLY })
	return tr.Hit and tr.HitPos or p
end

-- Start the dismount clip from his seat.
local function dismount(npc, now)
	local H = npc.tifHeli
	local heli, man = H.heli, H.man
	local suffix = pick_exit(npc, man, H.style)
	local ex = man.exits[suffix]
	H.ex = ex
	local clip = man.role .. "_" .. suffix
	local lp, lyaw = seat_local(heli, man, ex)
	local world = heli:LocalToWorld(lp or H.lp)
	local yaw = heli:LocalToWorldAngles(Angle(0, lyaw or H.lyaw, 0)).y
	npc:SetParent(nil)
	npc:SetPos(world)
	npc:SetAngles(Angle(0, yaw, 0))
	local c = Act.Clip(npc, clip)
	if not c then
		-- No clip (MW anims off): straight down to the ground beside the door.
		npc:SetPos(TIF.FreeSpot(ground_below(world) + Vector(0, 0, 2), npc))
		stand(npc)
		return
	end
	-- Where the clip would put his feet at its end: the real ground there (the drop is warped onto it).
	local x, y, r = Act.RootAt(c, 1)
	local rad = math.rad(yaw)
	local endPos = Vector(world.x + x * math.cos(rad) - y * math.sin(rad), world.y + x * math.sin(rad) + y * math.cos(rad), world.z)
	local g = ground_below(endPos + Vector(0, 0, (Act.ZAt(c, 1) or 0)))
	Act.Play(npc, clip, { root = true, rootz = true, noTrace = true, to = { pos = g, yaw = yaw + r } })
	-- Lead-in: the clip starts LEAD from now. The clip's name can reach a client after his position does; without
	-- this the client still showed him seated while the server already moved him down, then jumped into the clip at
	-- its landing frames (user: "the legs open for landing well after they landed"). Its first frame is his seat
	-- pose, so the wait doesn't show.
	local LEAD = 0.4
	if npc.tifAct then npc.tifAct.t0 = now + LEAD end
	npc:SetNW2Float("tif_act_t", now + LEAD)
	H.state, H.t0, H.dur, H.clip = "out", now + LEAD, c.dur, clip
	if H.set.kind == "rope" then heli:SetRopes(true) end
	npc.tifAction = "getting out of the helicopter"
end

-- Back to TIF at the release point: moving the way the clip was going, toward a spot clear of the helicopter.
local function release(npc, now)
	local H = npc.tifHeli
	local heli, ex = H.heli, H.ex
	local yaw = npc:GetAngles().y
	local a = npc.tifAct
	if a then yaw = a.startYaw end -- clip velocities are in the clip's starting frame
	local v = Vector(ex.vel[1], ex.vel[2], 0)
	v:Rotate(Angle(0, yaw, 0))
	if a then Act.Clear(npc) end
	npc:SetPos(ground_below(npc:GetPos()) + Vector(0, 0, 2))
	if IsValid(heli) then heli.tifOut = (heli.tifOut or 0) + 1 end
	hook.Run("TIF_HeliRiderOut", npc, heli)
	if ex.crouch then
		-- Landed down on a knee: he stays there, gun up, facing out, while the helicopter dusts off (user, 0.25.0).
		stand(npc, true)
		local out = npc:GetPos() - (IsValid(heli) and heli:GetPos() or npc:GetPos())
		out.z = 0
		if out:LengthSqr() < 1 then out = npc:GetForward() end
		out:Normalize()
		H.state, H.holdUntil, H.out = "hold", now + 10, out
		H.face = npc:GetPos() + out * 600 + Vector(0, 0, 40)
		TIF.Move.Stop(npc)
		-- (set now, not on the next think: for one brain tick he'd have stood up)
		npc.tifStance, npc.tifMode, npc.tifFace = 1, 1, H.face
		return
	end
	stand(npc)
	if npc.loco then npc.loco:SetVelocity(v) end
	Ride.GoOn(npc, heli, v)
end

-- His first goal off the helicopter: on along his exit (or straight away from it), clear of the rotor.
function Ride.GoOn(npc, heli, v)
	local dir = v and v:Length() > 20 and v:GetNormalized() or (npc:GetPos() - (IsValid(heli) and heli:GetPos() or npc:GetPos()))
	dir.z = 0
	if dir:LengthSqr() < 0.01 then dir = npc:GetForward() end
	dir:Normalize()
	local goal = TIF.Move.Snap(npc:GetPos() + dir * math.Rand(320, 460))
	if goal then
		TIF.Move.SetGoal(npc, goal, "run", "heli")
		npc.tifMove.fresh = nil -- already moving: no start-from-standing clip
	end
end

-- From the brain, first thing. Returns true while the soldier is on board or getting out.
function Ride.Think(npc, now)
	local H = npc.tifHeli
	if not H then return false end
	local heli = H.heli
	npc.tifFire.want = false
	npc.tifFace = nil
	if H.state == "ride" then
		if not IsValid(heli) then
			npc:SetParent(nil)
			stand(npc)
			return false
		end
		npc.tifStance, npc.tifMode = 0, 0
		npc.tifAction = "riding in the helicopter"
		if npc:GetMoveType() ~= MOVETYPE_NONE then npc:SetMoveType(MOVETYPE_NONE) end
		if npc:GetParent() ~= heli then npc:SetParent(heli) end
		if npc:GetLocalPos():DistToSqr(H.lp) > 4 then
			npc:SetLocalPos(H.lp)
			npc:SetLocalAngles(Angle(0, H.lyaw, 0))
		end
		if heli.Arrived and heli:Arrived() and heli:GetDoorsOpen() then
			-- A beat apart, so a stick doesn't move as one.
			H.goAt = H.goAt or now + math.Rand(0, 0.35)
			if now >= H.goAt then dismount(npc, now) end
		end
		return true
	end
	if H.state == "out" then
		local u = (now - H.t0) / math.max(0.05, H.dur)
		if u >= H.ex.release or not npc.tifAct or npc.tifAct.name ~= H.clip then
			release(npc, now)
			return H.state == "hold"
		end
		return true
	end
	if H.state == "hold" then
		-- Until the helicopter has lifted away (1.5 s into its climb) or gone, an enemy shows, or 10 s.
		local ph = IsValid(heli) and heli.phase
		local left = not IsValid(heli) or ph == "depart" or (ph == "climb" and now - (heli.phaseAt or now) > 1.5)
		local c = npc.tifPrimaryC
		if left or now > H.holdUntil or (c and c.visible) then
			npc.tifHeli = nil
			npc.tifFace = nil
			Ride.GoOn(npc, heli, H.out)
			return false
		end
		npc.tifStance, npc.tifMode = 1, 1
		npc.tifFace = H.face
		npc.tifAction = "covering the LZ while the helicopter leaves"
		return true
	end
	return false
end

-- Riders still on board when it goes down die with it; the ones on the ropes fall.
hook.Add("TIF_HeliDestroyed", "tif_air_riders", function(heli, attacker)
	for _, npc in ipairs(heli.tifRiders or {}) do
		local H = IsValid(npc) and npc.tifHeli
		if H and H.heli == heli and H.state == "hold" then
			-- (already on the ground: just free)
			npc.tifHeli, npc.tifFace = nil, nil
		elseif H and H.heli == heli then
			npc:SetParent(nil)
			if npc.tifAct then Act.Clear(npc) end
			stand(npc)
			local d = DamageInfo()
			d:SetDamage(npc:Health() + 100)
			d:SetDamageType(DMG_BLAST)
			d:SetAttacker(IsValid(attacker) and attacker or heli)
			d:SetInflictor(heli)
			npc:TakeDamageInfo(d)
		end
	end
end)

-- Everyone out: the helicopter leaves (unless the game mode holds it).
timer.Create("tif_air_rides", 0.25, 0, function()
	for _, heli in ipairs(Air.List()) do
		local r = heli.route
		if heli.tifRiders and heli.tifAutoLeave and heli:Arrived() then
			local left = 0
			for _, npc in ipairs(heli.tifRiders) do
				-- (men holding the LZ outside are out: the helicopter leaving is what they wait for)
				local H = IsValid(npc) and npc.tifHeli
				if H and H.heli == heli and H.state ~= "hold" then left = left + 1 end
			end
			-- (never left hovering for good if someone can't get out)
			if left > 0 and CurTime() - (heli.phaseAt or 0) > 45 then left = 0 end
			if left == 0 then
				heli.tifEmptyAt = heli.tifEmptyAt or CurTime()
				if CurTime() - heli.tifEmptyAt > 1.2 then
					heli.tifAutoLeave = nil
					heli:Release()
					if r and r.onEmpty then pcall(r.onEmpty, heli) end
					hook.Run("TIF_HeliEmpty", heli)
				end
			end
		end
	end
end)
