local TIF = TIF
local GL = TIF.Glide
local V = TIF.Vehicle

TIF.Driver = TIF.Driver or {}
local D = TIF.Driver
D.Active = D.Active or {}

D.CRUISE = 520
D.ARRIVE = 220

local function flat(v)
	local f = Vector(v.x, v.y, 0)
	f:Normalize()
	return f
end

function D.Drive(veh, points, opts)
	opts = opts or {}
	veh.tifDrive = {
		pts = points, i = 1, speed = opts.speed or D.CRUISE, arrive = opts.arrive or D.ARRIVE,
		onArrive = opts.onArrive, label = opts.label or "drive", source = opts.source or "?",
		t0 = CurTime(), stuckSince = nil, reverseUntil = nil, state = "drive",
	}
	D.Active[veh] = true
	GL.StartEngine(veh)
end

function D.Stop(veh, why)
	local d = veh.tifDrive
	if d then d.state, d.why = "stop", why end
end

function D.Resume(veh)
	local d = veh.tifDrive
	if d then d.state, d.stuckSince = "drive", nil end
end

function D.Clear(veh)
	veh.tifDrive = nil
	D.Active[veh] = nil
	if IsValid(veh) then GL.Drive(veh, 0, 0, 1, true) end
end

local function ahead(d, pos, dist)
	local pts = d.pts
	local prev = pos
	for k = d.i, #pts do
		local p = pts[k]
		local seg = prev:Distance(p)
		if seg >= dist then return prev + (p - prev):GetNormalized() * dist, k end
		dist = dist - seg
		prev = p
	end
	return pts[#pts], #pts
end

local probe = { mins = Vector(-40, -40, 25), maxs = Vector(40, 40, 70), mask = MASK_SOLID }

local function tick(veh, d, now)
	local driver = V.Driver(veh)
	if not GL.IsUsable(veh) or not driver then
		d.state = "no driver"
		GL.Release(veh)
		return
	end
	local pos = veh:GetPos()
	local fwd = flat(veh:GetForward())
	local vel = veh:GetVelocity()
	local speed = vel:Dot(veh:GetForward())
	d.speedNow = speed

	if d.state == "stop" or d.state == "arrived" then
		GL.Drive(veh, 0, 0, math.abs(speed) > 40 and 1 or 0, math.abs(speed) < 60)
		return
	end

	local pts = d.pts
	while d.i < #pts do
		local p = pts[d.i]
		local to = p - pos
		to.z = 0
		if to:Length() < 200 or (to:Dot(fwd) < 0 and to:Length() < 450) then d.i = d.i + 1 else break end
	end
	local final = pts[#pts]
	local toEnd = Vector(final.x - pos.x, final.y - pos.y, 0):Length()
	if d.i == #pts and toEnd < d.arrive then
		d.state = "arrived"
		GL.Drive(veh, 0, 0, 1, math.abs(speed) < 60)
		if d.onArrive then
			local cb = d.onArrive
			d.onArrive = nil
			local ok, err = pcall(cb, veh)
			if not ok then TIF.Error("onArrive error: ", tostring(err)) end
		end
		return
	end

	local look = math.Clamp(math.abs(speed) * 0.9, 260, 900)
	local target = ahead(d, pos, look)
	d.target = target
	local want = (target - pos):Angle().y
	local err = math.AngleDifference(want, veh:GetAngles().y)
	local steer = math.Clamp(-err / 32, -1, 1)

	local far = ahead(d, pos, look * 2)
	local turn = math.abs(math.AngleDifference((far - target):Angle().y, want))
	local vT = d.speed * math.Clamp(1 - math.max(turn, math.abs(err)) / 100, 0.3, 1)
	if d.i >= #pts - 1 then vT = math.min(vT, toEnd * 0.7 + 80) end

	if d.speedCap then vT = math.min(vT, d.speedCap) end

	local plen = math.Clamp(math.abs(speed) * 1.1, 140, 700)
	probe.start = pos + fwd * 60
	probe.endpos = probe.start + fwd * plen
	probe.filter = { veh }
	for _, c in ipairs(veh:GetChildren()) do probe.filter[#probe.filter + 1] = c end
	local hit = util.TraceHull(probe)

	if hit.Hit and hit.HitWorld and hit.HitNormal.z > 0.64 then hit = { Hit = false, Fraction = 1 } end
	d.blocked = hit.Hit and not hit.HitWorld and IsValid(hit.Entity) and hit.Entity ~= veh
	if hit.Hit then vT = math.min(vT, math.max(0, (hit.Fraction * plen - 80) * 1.2)) end

	if d.reverseUntil then
		if now < d.reverseUntil then
			GL.Drive(veh, 0, -d.reverseSteer, 1, false)
			d.state = "reversing"
			return
		end
		d.reverseUntil, d.stuckSince = nil, nil
	end
	if vT >= 40 and math.abs(speed) < 25 then
		d.stuckSince = d.stuckSince or now
		if now - d.stuckSince > 2.5 then
			d.reverseUntil, d.reverseSteer = now + 1.5, steer ~= 0 and steer or 1
			return
		end
	else
		d.stuckSince = nil
	end

	local throttle, brake = 0, 0
	if vT >= 40 then d.blockedSince = nil end
	if vT < 40 then

		d.vT, d.state = vT, "blocked"

		d.blockedSince = d.blockedSince or now
		if hit.HitWorld and now - d.blockedSince > 3 then
			d.blockedSince = nil
			d.reverseUntil, d.reverseSteer = now + 1.5, steer ~= 0 and steer or 1
			return
		end
		GL.Drive(veh, 0, steer, speed > 30 and 1 or 0, speed <= 30)
		return
	elseif speed < vT - 30 then
		throttle = math.Clamp((vT - speed) / 220, 0.3, 1)
	elseif speed > vT + 60 then
		brake = math.Clamp((speed - vT) / 300, 0.2, 1)
	else
		throttle = 0.15
	end
	d.vT, d.state = vT, "drive"
	GL.Drive(veh, throttle, steer, brake, false)
end

timer.Create("tif_driver_tick", 0.1, 0, function()
	if TIF.AIDisabled() then return end
	local now = CurTime()
	for veh in pairs(D.Active) do
		if not IsValid(veh) or not veh.tifDrive then
			D.Active[veh] = nil
		else
			local ok, err = pcall(tick, veh, veh.tifDrive, now)
			if not ok then
				TIF.Error("Driver error: ", tostring(err))
				D.Clear(veh)
			end
		end
	end
end)
