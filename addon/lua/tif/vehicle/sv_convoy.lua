local TIF = TIF
local SQ = TIF.Squad
local MT = TIF.Mounted
local D = TIF.Driver
local R = TIF.Routes
local GL = TIF.Glide

TIF.Convoy = TIF.Convoy or {}
local CV = TIF.Convoy
CV.List = CV.List or {}
CV.NextId = CV.NextId or 1

CV.PACE = 380
CV.GAP = 420
CV.HALT_RANGE = 2000

local function log(cv, ...)
	local cvd = GetConVar("tif_debug")
	if cvd and cvd:GetBool() then
		TIF.Log("[convoy ", cv.id, "] ", table.concat({ ... }, ""))
	end
end

function CV.Create(squads)
	local cv = { id = CV.NextId, squads = {}, state = "forming", pace = CV.PACE, gap = CV.GAP }
	CV.NextId = CV.NextId + 1

	for _, sq in ipairs(squads) do
		if sq.mount then
			cv.squads[#cv.squads + 1] = sq
			sq.mount.convoy = cv
		end
	end

	if #cv.squads == 0 then return nil end

	CV.List[cv.id] = cv
	log(cv, "formed with ", #cv.squads, " vehicles")
	return cv
end

local function alive(cv)
	local out = {}
	for _, sq in ipairs(cv.squads) do
		local mt = sq.mount
		if SQ.List[sq.id] and mt and IsValid(mt.veh) and GL.IsUsable(mt.veh) then
			out[#out + 1] = sq
		end
	end

	return out
end

local function loop_route(pts)
	local all, src = {}, nil
	for i = 1, #pts do
		local a, b = pts[i], pts[i % #pts + 1]
		local leg, s = R.Build(a, b)
		if not leg then return nil, s end

		src = src or s

		for _, p in ipairs(leg) do
			all[#all + 1] = p
		end
	end

	return all, src
end

function CV.DriveTo(cv, pos, stay)
	cv.mode, cv.dest, cv.stay, cv.loop = "transit", Vector(pos), stay, nil
	cv.state = "forming"
	return true
end

function CV.Patrol(cv, pts)
	cv.mode, cv.loop, cv.dest = "patrol", pts, nil
	cv.state = "forming"

	for _, sq in ipairs(cv.squads) do
		if sq.mount then
			sq.mount.patrol = { pts = pts, i = 1, convoy = true }
		end
	end

	return true
end

local function set_off(cv, list)
	local lead = list[1].mount.veh
	local pts, src

	if cv.mode == "patrol" then
		pts, src = loop_route(cv.loop)
	elseif cv.dest then
		pts, src = R.Build(lead:GetPos(), cv.dest)
	end

	if not pts then
		log(cv, "no route (", tostring(src), ")")
		cv.state = "idle"
		return
	end

	cv.pts, cv.state, cv.halted = pts, "driving", nil

	for i, sq in ipairs(list) do
		local mt = sq.mount
		mt.phase = "driving"
		mt.dest = cv.mode == "transit" and cv.dest or nil
		mt.dismountOnArrive = false
		D.Drive(mt.veh, pts, {
			source = src, label = "convoy " .. cv.id .. " #" .. i, speed = cv.pace * 1.3,
			arrive = D.ARRIVE + cv.gap * (i - 1),

			onArrive = i == 1 and function()
				cv.leadArrived = true
			end or nil,
		})
	end

	log(cv, cv.mode, ": ", #pts, " route points (", src, "), ", #list, " vehicles")
end

local function halt(cv, list, why, threat)
	cv.state, cv.halted = "halted", true

	for _, sq in ipairs(list) do
		local mt = sq.mount
		if mt.phase == "driving" or mt.phase == "ready" then
			if threat and mt.veh:GetPos():DistToSqr(threat) > CV.HALT_RANGE ^ 2 then
				D.Stop(mt.veh, why)
				mt.phase = "ready"
			else
				mt.threat = threat and Vector(threat) or nil
				mt.phase = "stopping"
				D.Stop(mt.veh, why)
			end
		end
	end

	log(cv, "halt: ", why)
end

local function tick(cv, now)
	local list = alive(cv)
	if #list == 0 then
		CV.List[cv.id] = nil
		return
	end

	if cv.state == "forming" or cv.state == "idle" then
		local ready = true
		for _, sq in ipairs(list) do
			local p = sq.mount.phase
			if p ~= "ready" and p ~= "driving" then
				ready = false
				break
			end
		end

		if ready and (cv.mode == "patrol" or cv.dest) and cv.state == "forming" then
			set_off(cv, list)
		end

		return
	end

	if cv.state == "halted" then
		local busy = false
		for _, sq in ipairs(list) do
			for _, m in ipairs(SQ.Members(sq)) do
				local a = m.tifAware
				if a == TIF.AWARE.ENGAGED or a == TIF.AWARE.ALERTED or a == TIF.AWARE.SEARCHING then
					busy = true
					break
				end
			end

			if busy then break end
		end

		if busy then
			cv.quietSince = nil
		else
			cv.quietSince = cv.quietSince or now
		end

		if cv.quietSince and now - cv.quietSince > 30 then
			cv.quietSince = nil

			for _, sq in ipairs(list) do
				if sq.mount.phase == "dismounted" then
					MT.Remount(sq)
				end
			end

			log(cv, "all quiet, remounting")
		end

		local allReady = true
		for _, sq in ipairs(list) do
			if sq.mount.phase ~= "ready" then
				allReady = false
				break
			end
		end

		if allReady then
			log(cv, "everyone back in, moving on")
			cv.state = "forming"
		end

		return
	end

	for _, sq in ipairs(list) do
		local mt = sq.mount
		if mt.phase == "stopping" or mt.phase == "dismounting" or mt.phase == "dismounted" then
			halt(cv, list, "contact (squad " .. sq.id .. ")", mt.threat)
			return
		end
	end

	if cv.leadArrived then
		cv.leadArrived = nil

		if cv.mode == "patrol" then
			set_off(cv, list)
		else
			cv.state = "arrived"

			for _, sq in ipairs(list) do
				D.Stop(sq.mount.veh, "arrived")

				if not cv.stay then
					MT.Dismount(sq, nil, "convoy arrived")
				else
					sq.mount.phase = "ready"
				end
			end

			log(cv, "arrived", cv.stay and "" or ", getting out")
		end

		return
	end

	for i, sq in ipairs(list) do
		local veh = sq.mount.veh
		local d = veh.tifDrive

		if d then
			local cap = cv.pace
			if i == 1 then
				local behind = list[2] and list[2].mount.veh
				local g = behind and behind:GetPos():Distance(veh:GetPos()) or 0

				if g > cv.gap * 3.5 then
					cap = 0
				elseif g > cv.gap * 2.2 then
					cap = 150
				end
			else
				local ahead = list[i - 1].mount.veh
				local g = ahead:GetPos():Distance(veh:GetPos())

				if g < cv.gap * 0.6 then
					cap = 0
				elseif g < cv.gap then
					cap = math.max(0, ahead:GetVelocity():Length() * 0.9)
				elseif g > cv.gap * 1.6 then
					cap = cv.pace * 1.3
				end
			end

			d.speedCap = cap
		end
	end
end

timer.Create("tif_convoy_tick", 0.25, 0, function()
	if TIF.AIDisabled() then return end

	local now = CurTime()
	for id, cv in pairs(CV.List) do
		local ok, err = pcall(tick, cv, now)
		if not ok then
			TIF.Error("Convoy error: ", tostring(err))
			CV.List[id] = nil
		end
	end
end)

function CV.Of(sq)
	return sq.mount and sq.mount.convoy or nil
end
