local TIF = TIF
local Act = TIF.Action

TIF.SmartMW = TIF.SmartMW or {}
local SM = TIF.SmartMW

SM.REACH = 45
SM.POST_LEASH = 70
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

local function trace(a, b, skip)
	return util.TraceLine({ start = a, endpos = b, mask = MASK, filter = function(x)
		return x ~= skip and not (x:IsNPC() or x:IsNextBot() or x:IsPlayer())
	end })
end

local function standable(npc, p)
	local g = trace(p + Vector(0, 0, 20), p - Vector(0, 0, 40), npc)
	if not g.Hit then return nil end
	local fp = g.HitPos
	if TIF.Room and not TIF.Room(fp) then return nil end
	return fp
end

local function claim(seat, npc)
	seat.tifSeatTaken = npc
	seat.tifSeatCG = seat.tifSeatCG or seat:GetCollisionGroup()
	seat:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	local ph = seat:GetPhysicsObject()
	if IsValid(ph) then
		if seat.tifSeatMotion == nil then
			seat.tifSeatMotion = ph:IsMotionEnabled()
		end
		ph:EnableMotion(false)
	end
end

local function free(seat)
	if not IsValid(seat) then return end
	seat.tifSeatTaken = nil
	if seat.tifSeatCG then
		seat:SetCollisionGroup(seat.tifSeatCG)
	end

	seat.tifSeatCG = nil
	local ph = seat:GetPhysicsObject()
	if IsValid(ph) and seat.tifSeatMotion ~= nil then
		ph:EnableMotion(seat.tifSeatMotion)
		if seat.tifSeatMotion then
			ph:Wake()
		end
	end

	seat.tifSeatMotion = nil
end

function SM.Release(npc)
	local a = npc.tifActivity
	local seat = a and a.smart and a.smart.seat
	if seat and IsValid(seat) and seat.tifSeatTaken == npc then
		free(seat)
	end
end

local function stale(seat)
	local t = seat.tifSeatTaken
	if not t then return false end
	local a = IsValid(t) and t.tifActivity
	if a and a.smart and a.smart.seat == seat and not t.tifDead then
		return false
	end

	free(seat)
	return true
end

local function near(npc, p, anchor)
	return p:Distance(npc:GetPos()) <= SM.REACH and p:Distance(anchor) <= SM.POST_LEASH
end

function SM.Find(npc, anchor, watch)
	local out = {}
	local base = npc:GetPos()
	watch = watch or npc:GetAngles().y
	for i = 0, 7 do
		local d = yaw_dir(i * 45)

		local w = trace(base + Vector(0, 0, 50), base + Vector(0, 0, 50) + d * 60, npc)
		if w.Hit and not w.HitSky and math.abs(w.HitNormal.z) < 0.3 then
			local n = Vector(w.HitNormal.x, w.HitNormal.y, 0)
			n:Normalize()
			local ny = n:Angle().y

			local side = math.abs(math.AngleDifference(ny + 90, watch)) <= math.abs(math.AngleDifference(ny - 90, watch)) and "l" or "r"
			local yaw = side == "l" and ny + 90 or ny - 90
			local node = Vector(w.HitPos.x, w.HitPos.y, base.z) + n * SM.WALL_DIST[side]
			node = standable(npc, node)
			if node and near(npc, node, anchor) and has(npc, "mws_wall_" .. side .. "_loop") then
				out[#out + 1] = { kind = "wall", prefix = "mws_wall_" .. side, pos = node, yaw = yaw }
			end
		end

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

	for _, e in ipairs(ents.FindInSphere(anchor, SM.POST_LEASH + 30)) do
		local cls = e:GetClass()
		local mdl = string.lower(e:GetModel() or "")
		if (cls == "prop_physics" or cls == "prop_dynamic" or cls == "prop_physics_multiplayer") and mdl ~= "" then
			local isSeat = false
			for _, k in ipairs(SM.SEAT_MODELS) do if string.find(mdl, k, 1, true) then isSeat = true break end end
			if isSeat and e.tifSeatTaken then
				stale(e)
			end
			if isSeat and not e.tifSeatTaken then
				local c = e:WorldSpaceCenter()
				local top = util.TraceLine({ start = c + Vector(0, 0, 40), endpos = c - Vector(0, 0, 40),
					filter = function(x) return x == e end })
				local floor = trace(c, c - Vector(0, 0, 80), e)
				local h = (top.Hit and floor.Hit) and (top.HitPos.z - floor.HitPos.z) or nil
				if h and h >= 14 and h <= 24 then

					local face
					for k = 0, 3 do
						local dd = yaw_dir(e:GetAngles().y + k * 90)
						local b = util.TraceLine({ start = top.HitPos + Vector(0, 0, 14), endpos = top.HitPos + Vector(0, 0, 14) + dd * 24,
							filter = function(x) return x == e end })
						if b.Hit then
							face = e:GetAngles().y + k * 90 + 180
							break
						end
					end
					face = face or watch
					local kinds = {}
					for k in pairs(SM.SEAT_OFF) do if has(npc, "mws_sit_" .. k .. "_loop") then kinds[#kinds + 1] = k end end
					if #kinds > 0 then
						local k = kinds[math.random(#kinds)]
						local node = Vector(top.HitPos.x, top.HitPos.y, floor.HitPos.z) - yaw_dir(face) * SM.SEAT_OFF[k]

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

function SM.Start(npc, spot, now, seated)
	local a = { smart = spot, name = spot.kind }
	if spot.kind == "sit" then
		if spot.seat then
			claim(spot.seat, npc)
		end
		if seated then
			npc:SetPos(spot.pos)
			npc:SetAngles(Angle(0, spot.yaw, 0))
			Act.Loop(npc, spot.prefix .. "_loop")
			a.phase, a.untilT = "loop", now
		else

			local d = Act.Play(npc, spot.prefix .. "_react", { to = { pos = spot.pos, yaw = spot.yaw }, reverse = true, rate = 0.7 })
			if not d then return nil end
			a.phase, a.untilT = "enter", now + d
		end
	else

		local d = Act.Play(npc, spot.prefix .. "_enter", { root = true, to = { pos = spot.pos, yaw = spot.yaw } })
		if not d then return nil end
		a.phase, a.untilT = "enter", now + d
	end

	return a
end

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

local function dir_to(npc, pos)
	if not pos then return 8 end
	local d = math.AngleDifference((pos - npc:GetPos()):Angle().y, npc:GetAngles().y)
	if math.abs(d) <= 45 then return 8 end
	if math.abs(d) >= 135 then return 2 end
	return d > 0 and 4 or 6
end

function SM.Leave(npc, a, now, startled, threatPos, hurry)
	local s = a.smart
	if s.seat and IsValid(s.seat) and s.seat.tifSeatTaken == npc then
		free(s.seat)
	end

	local name, opts = nil, { root = true, clear = true, rate = hurry and 1.4 or 1 }
	if s.kind == "sit" then
		name = s.prefix .. "_react"
		if not startled then
			opts.rate = 0.75
		end
	elseif startled and a.phase == "loop" then
		name = s.prefix .. "_react_" .. dir_to(npc, threatPos)
	else
		name = s.prefix .. "_exit"
	end

	if not clip(npc, name) then
		name = s.prefix .. "_exit"
	end
	return Act.Play(npc, name, opts)
end
