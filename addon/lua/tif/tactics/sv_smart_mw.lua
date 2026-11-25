-- Situational idles with MW19's smart-object animations (MW19 body): leaning a shoulder on a wall, a hand on a
-- table / counter / railing, sitting on a chair or bench. Used by TIF.PassiveMW as idle activities at posts.
--
-- Spots are found around the soldier's post (SM.Find): walls by traces at shoulder height; surfaces 26-42 high
-- (a ledge with open space above it); seats among chair / bench / stool / couch / sofa props (seat height from
-- a trace, facing away from the backrest). Each is placed with offsets measured from the clips (units):
--   wall lean   left wall 13.5, right wall 19 from the wall (shoulder at 9.5 / 15.2 + 4)
--   table lean  centre hand: surface edge 12.5 ahead; left hand: edge 15.5 to the left; right: 14.5 right;
--               set 30 for tops 26-33, 36 for 33-42 (the hand rests 2 above the top)
--   sitting     seat centre 6.3 behind the soldier's origin (upright clips), 2.7 ahead (sleeping)
-- Leans have enter / loop / exit / 4-direction startle clips. Sitting has no usable sit-down in MW19 (the
-- informant scene's transitions never move the pelvis), so like MW19's own stealth AI, soldiers whose post is
-- by a seat start the game seated; the startle clip stands them up, and sitting back down plays it reversed.
-- Roles: mws_wall_<l|r>_*, mws_table_<l|c|r>_<30|36>_*, mws_sit_<gun|laptop|phone|sleep>_<loop|react>.

local TIF = TIF
local Act = TIF.Action

TIF.SmartMW = TIF.SmartMW or {}
local SM = TIF.SmartMW

SM.REACH = 45          -- how far from where the soldier stands a spot may be (the enter clip covers it)
SM.POST_LEASH = 70     -- and from his post / formation slot (duty walks him back beyond 80)
SM.WALL_DIST = { l = 13.5, r = 19 }
SM.TABLE = { c = { edge = 12.5, turn = 0 }, l = { edge = 15.5, turn = -90 }, r = { edge = 14.5, turn = 90 } }
SM.SEAT_OFF = { gun = -6.3, laptop = -6.3, phone = -6.3, sleep = 2.7 }
SM.SEAT_MODELS = { "chair", "bench", "stool", "couch", "sofa", "seat" }

local MASK = MASK_SOLID
local function yaw_dir(y)
	local r = math.rad(y)
	return Vector(math.cos(r), math.sin(r), 0)
end
local function has(npc, name) return npc.tifHomeHost and TIF.GTG.Clip(name, npc.tifHomeHost) ~= nil end
local function clip(npc, name) return npc.tifHomeHost and TIF.GTG.Clip(name, npc.tifHomeHost) end

-- Only the world and props count (another soldier's box is not a wall to lean on).
local function trace(a, b, skip)
	return util.TraceLine({ start = a, endpos = b, mask = MASK, filter = function(x)
		return x ~= skip and not (x:IsNPC() or x:IsNextBot() or x:IsPlayer())
	end })
end

-- Standing room and floor at a node.
local function standable(npc, p)
	local g = trace(p + Vector(0, 0, 20), p - Vector(0, 0, 40), npc)
	if not g.Hit then return nil end
	local fp = g.HitPos
	if TIF.Room and not TIF.Room(fp) then return nil end
	return fp
end

-- Seats: while someone sits, the prop is frozen and stops colliding with characters (the soldier's box sits
-- inside it; otherwise physics would shove the chair away). Undone when he gets up, dies or is removed.
local function claim(seat, npc)
	seat.tifSeatTaken = npc
	seat.tifSeatCG = seat.tifSeatCG or seat:GetCollisionGroup()
	seat:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	local ph = seat:GetPhysicsObject()
	if IsValid(ph) then
		if seat.tifSeatMotion == nil then seat.tifSeatMotion = ph:IsMotionEnabled() end
		ph:EnableMotion(false)
	end
end

local function free(seat)
	if not IsValid(seat) then return end
	seat.tifSeatTaken = nil
	if seat.tifSeatCG then seat:SetCollisionGroup(seat.tifSeatCG) end
	seat.tifSeatCG = nil
	local ph = seat:GetPhysicsObject()
	if IsValid(ph) and seat.tifSeatMotion ~= nil then
		ph:EnableMotion(seat.tifSeatMotion)
		if seat.tifSeatMotion then ph:Wake() end
	end
	seat.tifSeatMotion = nil
end

-- Let go of this soldier's seat (getting up, dying).
function SM.Release(npc)
	local a = npc.tifActivity
	local seat = a and a.smart and a.smart.seat
	if seat and IsValid(seat) and seat.tifSeatTaken == npc then free(seat) end
end

-- A seat whose sitter is gone or no longer sitting there.
local function stale(seat)
	local t = seat.tifSeatTaken
	if not t then return false end
	local a = IsValid(t) and t.tifActivity
	if a and a.smart and a.smart.seat == seat and not t.tifDead then return false end
	free(seat)
	return true
end

local function near(npc, p, anchor)
	return p:Distance(npc:GetPos()) <= SM.REACH and p:Distance(anchor) <= SM.POST_LEASH
end

-- Spots around the soldier. watch: preferred facing (post yaw). Returns a list.
function SM.Find(npc, anchor, watch)
	local out = {}
	local base = npc:GetPos()
	watch = watch or npc:GetAngles().y
	for i = 0, 7 do
		local d = yaw_dir(i * 45)
		-- Walls: a vertical face at shoulder height.
		local w = trace(base + Vector(0, 0, 50), base + Vector(0, 0, 50) + d * 60, npc)
		if w.Hit and not w.HitSky and math.abs(w.HitNormal.z) < 0.3 then
			local n = Vector(w.HitNormal.x, w.HitNormal.y, 0)
			n:Normalize()
			local ny = n:Angle().y
			-- Wall on the left: facing = normal + 90; on the right: normal - 90. Take the one closer to watch.
			local side = math.abs(math.AngleDifference(ny + 90, watch)) <= math.abs(math.AngleDifference(ny - 90, watch)) and "l" or "r"
			local yaw = side == "l" and ny + 90 or ny - 90
			local node = Vector(w.HitPos.x, w.HitPos.y, base.z) + n * SM.WALL_DIST[side]
			node = standable(npc, node)
			if node and near(npc, node, anchor) and has(npc, "mws_wall_" .. side .. "_loop") then
				out[#out + 1] = { kind = "wall", prefix = "mws_wall_" .. side, pos = node, yaw = yaw }
			end
		end
		-- Surfaces: something at hip height with open space above (table, counter, railing, sandbags).
		local s = trace(base + Vector(0, 0, 30), base + Vector(0, 0, 30) + d * 55, npc)
		if s.Hit and not s.HitSky and math.abs(s.HitNormal.z) < 0.5 then
			local over = trace(base + Vector(0, 0, 50), base + Vector(0, 0, 50) + d * 70, npc)
			local inside = s.HitPos + d * 6
			local top = trace(Vector(inside.x, inside.y, base.z + 46), Vector(inside.x, inside.y, base.z + 20), npc)
			local h = top.Hit and (top.HitPos.z - base.z) or nil
			if not over.Hit and h and h >= 26 and h <= 42 then
				local set = h <= 33 and 30 or 36
				local hands = { "c", "l", "r" }
				local hand = hands[math.random(#hands)]
				local T = SM.TABLE[hand]
				-- Facing: the surface ahead (c), on the left (l: face 90 right of it) or on the right (r).
				local yaw = d:Angle().y + T.turn
				local edge = Vector(s.HitPos.x, s.HitPos.y, base.z)
				local node = standable(npc, edge - d * T.edge)
				local name = "mws_table_" .. hand .. "_" .. set
				if node and near(npc, node, anchor) and has(npc, name .. "_loop") then
					out[#out + 1] = { kind = "table", prefix = name, pos = node, yaw = yaw }
				end
			end
		end
	end
	-- Seats: chair / bench / stool / couch / sofa props nearby.
	for _, e in ipairs(ents.FindInSphere(anchor, SM.POST_LEASH + 30)) do
		local cls = e:GetClass()
		local mdl = string.lower(e:GetModel() or "")
		if (cls == "prop_physics" or cls == "prop_dynamic" or cls == "prop_physics_multiplayer") and mdl ~= "" then
			local isSeat = false
			for _, k in ipairs(SM.SEAT_MODELS) do if string.find(mdl, k, 1, true) then isSeat = true break end end
			if isSeat and e.tifSeatTaken then stale(e) end
			if isSeat and not e.tifSeatTaken then
				local c = e:WorldSpaceCenter()
				local top = util.TraceLine({ start = c + Vector(0, 0, 40), endpos = c - Vector(0, 0, 40),
					filter = function(x) return x == e end })
				local floor = trace(c, c - Vector(0, 0, 80), e)
				local h = (top.Hit and floor.Hit) and (top.HitPos.z - floor.HitPos.z) or nil
				if h and h >= 14 and h <= 24 then
					-- Backrest: the side that's blocked above the seat; face away from it.
					local face
					for k = 0, 3 do
						local dd = yaw_dir(e:GetAngles().y + k * 90)
						local b = util.TraceLine({ start = top.HitPos + Vector(0, 0, 14), endpos = top.HitPos + Vector(0, 0, 14) + dd * 24,
							filter = function(x) return x == e end })
						if b.Hit then face = e:GetAngles().y + k * 90 + 180 break end
					end
					face = face or watch
					local kinds = {}
					for k in pairs(SM.SEAT_OFF) do if has(npc, "mws_sit_" .. k .. "_loop") then kinds[#kinds + 1] = k end end
					if #kinds > 0 then
						local k = kinds[math.random(#kinds)]
						local node = Vector(top.HitPos.x, top.HitPos.y, floor.HitPos.z) - yaw_dir(face) * SM.SEAT_OFF[k]
						-- (inside the leash: duty walks a soldier back to his post past 80)
						if node:Distance(anchor) <= SM.POST_LEASH then
							out[#out + 1] = { kind = "sit", prefix = "mws_sit_" .. k, pos = node, yaw = face, seat = e }
						end
					end
				end
			end
		end
	end
	return out
end

-- Start a spot. seated: begin already in the loop (soldier spawned there). Returns the activity or nil.
function SM.Start(npc, spot, now, seated)
	local a = { smart = spot, name = spot.kind }
	if spot.kind == "sit" then
		if spot.seat then claim(spot.seat, npc) end
		if seated then
			npc:SetPos(spot.pos)
			npc:SetAngles(Angle(0, spot.yaw, 0))
			Act.Loop(npc, spot.prefix .. "_loop")
			a.phase, a.untilT = "loop", now
		else
			-- Sitting down: the startle stand-up reversed and slowed, sliding onto the seat.
			local d = Act.Play(npc, spot.prefix .. "_react", { to = { pos = spot.pos, yaw = spot.yaw }, reverse = true, rate = 0.7 })
			if not d then return nil end
			a.phase, a.untilT = "enter", now + d
		end
	else
		-- Leans: the enter clip's own path, warped onto the spot.
		local d = Act.Play(npc, spot.prefix .. "_enter", { root = true, to = { pos = spot.pos, yaw = spot.yaw } })
		if not d then return nil end
		a.phase, a.untilT = "enter", now + d
	end
	return a
end

-- One think of a running smart activity. Returns true while it's in charge.
function SM.Step(npc, a, now, loopFor)
	local s = a.smart
	if a.phase == "enter" and now >= a.untilT then
		npc:SetPos(s.pos)
		npc:SetAngles(Angle(0, s.yaw, 0))
		Act.Loop(npc, s.prefix .. "_loop")
		a.phase, a.loopUntil = "loop", now + loopFor
	elseif a.phase == "loop" then
		a.loopUntil = a.loopUntil or now + loopFor
		if now >= a.loopUntil then
			local d = SM.Leave(npc, a, now, false, nil)
			a.phase, a.untilT = "exit", now + (d or 0)
		end
	elseif a.phase == "exit" and now >= a.untilT then
		return false
	end
	return true
end

-- Numpad direction of a point from the soldier's facing.
local function dir_to(npc, pos)
	if not pos then return 8 end
	local d = math.AngleDifference((pos - npc:GetPos()):Angle().y, npc:GetAngles().y)
	if math.abs(d) <= 45 then return 8 end
	if math.abs(d) >= 135 then return 2 end
	return d > 0 and 4 or 6
end

-- Leave a spot: calmly (exit clip) or startled toward threatPos (react clip). Returns the clip's duration.
function SM.Leave(npc, a, now, startled, threatPos, hurry)
	local s = a.smart
	if s.seat and IsValid(s.seat) and s.seat.tifSeatTaken == npc then free(s.seat) end
	local name, opts = nil, { root = true, clear = true, rate = hurry and 1.4 or 1 }
	if s.kind == "sit" then
		name = s.prefix .. "_react"
		if not startled then opts.rate = 0.75 end
	elseif startled and a.phase == "loop" then
		name = s.prefix .. "_react_" .. dir_to(npc, threatPos)
	else
		name = s.prefix .. "_exit"
	end
	if not clip(npc, name) then name = s.prefix .. "_exit" end
	return Act.Play(npc, name, opts)
end
