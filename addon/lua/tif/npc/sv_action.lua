local TIF = TIF
local GTG = TIF.GTG

TIF.Action = TIF.Action or {}
local Action = TIF.Action

local function sample_curve(clip, progress, axis)
	if not clip.curve or #clip.curve == 0 then return 0 end
	return GTG.ClipCurve(clip, progress * math.max(1, clip.frames - 1), axis)
end

function Action.RootAt(clip, progress)
	return sample_curve(clip, progress, 1), sample_curve(clip, progress, 2), sample_curve(clip, progress, 3)
end

function Action.ZAt(clip, progress)
	local zcurve = clip.zcurve
	if not zcurve or #zcurve == 0 then return 0 end
	local sampleIdx = progress * math.max(1, clip.frames - 1) / 3 + 1
	local idx = math.floor(sampleIdx)
	if idx >= #zcurve then return zcurve[#zcurve] end
	if idx < 1 then return zcurve[1] end
	local frac = sampleIdx - idx
	return zcurve[idx] + (zcurve[idx + 1] - zcurve[idx]) * frac
end

local function host_of(npc)
	return npc.tifHostId or npc.tifHomeHost or GTG.MW_HOST
end

function Action.Clip(npc, name)
	return GTG.Clip(name, host_of(npc)) or (npc.tifHomeHost and GTG.Clip(name, npc.tifHomeHost))
end

function Action.Play(npc, name, opts)
	if npc.tifActLock and not (opts and opts.lockOK) then return nil end
	local clip = GTG.Clip(name, host_of(npc))
	if not clip and npc.tifHomeHost and npc.tifHomeHost ~= host_of(npc) then
		clip = GTG.Clip(name, npc.tifHomeHost)
		if clip and npc.TIFSetHost then npc:TIFSetHost(npc.tifHomeHost) end
	end
	if not clip then
		TIF.Warn("Action clip missing: ", tostring(name))
		return nil
	end
	if opts and opts.base and not GTG.Clip(opts.base, host_of(npc)) then opts.base = nil end
	opts = opts or {}
	local now = CurTime()
	local rate = opts.rate or 1
	local act = {
		name = name,
		clip = clip,
		t0 = now,
		dur = clip.dur / rate,
		rate = rate,
		startPos = npc:GetPos(),
		startYaw = npc:GetAngles().y,
		root = opts.root == true,
		to = opts.to,
		loop = clip.loop and not opts.once,
		lift = opts.lift,
		noTrace = opts.noTrace,
		autoClear = opts.clear == true,
		rootz = opts.rootz == true and clip.zcurve ~= nil,
		warpU = opts.warpU or 1,
	}
	npc.tifAct = act
	if opts.root and opts.to then
		local rootX, rootY, rootYaw = Action.RootAt(clip, act.warpU)
		local rad = math.rad(act.startYaw)
		local cosY, sinY = math.cos(rad), math.sin(rad)
		local endX = act.startPos.x + rootX * cosY - rootY * sinY
		local endY = act.startPos.y + rootX * sinY + rootY * cosY
		act.warp = {
			dx = opts.to.pos.x - endX,
			dy = opts.to.pos.y - endY,
			dyaw = math.AngleDifference(opts.to.yaw, act.startYaw + rootYaw),
		}
		if act.rootz then
			act.warp.dz = opts.to.pos.z - (act.startPos.z + Action.ZAt(clip, act.warpU))
		end
		act.to = nil
	end
	npc:SetNW2String("tif_act", name)
	npc:SetNW2Float("tif_act_t", now)
	local sendRate = opts.reverse and -rate or rate
	if npc.tifActRateSent ~= sendRate then
		npc.tifActRateSent = sendRate
		npc:SetNW2Float("tif_act_rate", sendRate)
	end
	local baseClip = opts.base or ""
	if npc.tifActBaseSent ~= baseClip then
		npc.tifActBaseSent = baseClip
		npc:SetNW2String("tif_act_base", baseClip)
	end
	return act.dur
end

function Action.Loop(npc, name, opts)
	local act = npc.tifAct
	if act and act.name == name then return act.dur end
	return Action.Play(npc, name, opts)
end

function Action.Clear(npc, force)
	if not npc.tifAct then return end
	if npc.tifActLock and not force then return end
	npc.tifAct = nil
	npc:SetNW2String("tif_act", "")
	if npc.tifActBaseSent ~= "" then
		npc.tifActBaseSent = ""
		npc:SetNW2String("tif_act_base", "")
	end
end

function Action.Current(npc)
	return npc.tifAct
end

function Action.Progress(npc, now)
	local act = npc.tifAct
	if not act then return nil end
	return math.Clamp((now - act.t0) / math.max(0.01, act.dur), 0, 1)
end

function Action.Done(npc, now)
	local act = npc.tifAct
	return not act or (not act.loop and now - act.t0 >= act.dur)
end

local function smoothstep(t) return t * t * (3 - 2 * t) end

local HULL_MIN = Vector(-12, -12, 0)
local HULL_MAX = Vector(12, 12, 40)
local STEP_UP = Vector(0, 0, 4)
local SCRATCH_ANG = Angle(0, 0, 0)
local hullOut1, hullOut2 = {}, {}
local hullTrace1 = { mins = HULL_MIN, maxs = HULL_MAX, mask = MASK_NPCSOLID_BRUSHONLY, output = hullOut1 }
local hullTrace2 = { mins = HULL_MIN, maxs = HULL_MAX, mask = MASK_NPCSOLID_BRUSHONLY, output = hullOut2 }

function Action.Tick(npc, now)
	local act = npc.tifAct
	if not act or act.loop or act.finished then return end
	local progress = math.Clamp((now - act.t0) / math.max(0.01, act.dur), 0, 1)
	if progress >= 1 then act.finished = true end
	local curPos = npc:GetPos()
	local targetZ = act.lift and Lerp(smoothstep(progress), act.lift[1], act.lift[2]) or curPos.z
	local warpFrac = act.warp and smoothstep(math.min(1, progress / math.max(0.01, act.warpU or 1))) or 0
	if act.rootz then targetZ = act.startPos.z + Action.ZAt(act.clip, progress) + ((act.warp and act.warp.dz) or 0) * warpFrac end
	if act.to then
		local blend = smoothstep(progress)
		local pos = LerpVector(blend, act.startPos, act.to.pos)
		pos.z = targetZ
		npc:SetPos(pos)
		SCRATCH_ANG.y = act.startYaw + math.AngleDifference(act.to.yaw, act.startYaw) * blend
		npc:SetAngles(SCRATCH_ANG)
	elseif act.root then
		local rootX, rootY, rootYaw = Action.RootAt(act.clip, progress)
		local rad = math.rad(act.startYaw)
		local cosY, sinY = math.cos(rad), math.sin(rad)
		local pos = Vector(act.startPos.x + rootX * cosY - rootY * sinY, act.startPos.y + rootX * sinY + rootY * cosY, targetZ)
		if act.warp then
			pos.x, pos.y = pos.x + act.warp.dx * warpFrac, pos.y + act.warp.dy * warpFrac
			rootYaw = rootYaw + act.warp.dyaw * warpFrac
		end
		if act.noTrace then
			npc:SetPos(pos)
		else
			local liftedTarget = pos + STEP_UP
			hullTrace1.start, hullTrace1.endpos, hullTrace1.filter = curPos + STEP_UP, liftedTarget, npc
			local tr = util.TraceHull(hullTrace1)
			local hitPos = tr.HitPos
			if tr.Hit and not tr.StartSolid and tr.HitNormal then
				local normX, normY = tr.HitNormal.x, tr.HitNormal.y
				local normLenSqr = normX * normX + normY * normY
				if normLenSqr > 0.01 then
					local invLen = 1 / math.sqrt(normLenSqr)
					normX, normY = normX * invLen, normY * invLen
					local remX, remY = liftedTarget.x - hitPos.x, liftedTarget.y - hitPos.y
					local dot = remX * normX + remY * normY
					local slideX, slideY = remX - normX * dot, remY - normY * dot
					if slideX * slideX + slideY * slideY > 0.01 then
						hullTrace2.start, hullTrace2.endpos, hullTrace2.filter = hitPos, Vector(hitPos.x + slideX, hitPos.y + slideY, hitPos.z), npc
						local slideTr = util.TraceHull(hullTrace2)
						if not slideTr.StartSolid then hitPos = slideTr.HitPos end
					end
				end
			end
			npc:SetPos(hitPos - STEP_UP)
		end
		SCRATCH_ANG.y = act.startYaw + rootYaw
		npc:SetAngles(SCRATCH_ANG)
	end
	if act.finished and act.autoClear and npc.tifAct == act then Action.Clear(npc) end
	if act.stopU and progress >= act.stopU and npc.tifAct == act then Action.Clear(npc) end
end
