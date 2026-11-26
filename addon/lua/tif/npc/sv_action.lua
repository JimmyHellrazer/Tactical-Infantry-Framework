local TIF = TIF
local G = TIF.GTG

TIF.Action = TIF.Action or {}
local Act = TIF.Action

local function curve(clip, u, axis)
	if not clip.curve or #clip.curve == 0 then return 0 end
	return G.ClipCurve(clip, u * math.max(1, clip.frames - 1), axis)
end

function Act.RootAt(clip, u)
	return curve(clip, u, 1), curve(clip, u, 2), curve(clip, u, 3)
end

function Act.ZAt(clip, u)
	local zc = clip.zcurve
	if not zc or #zc == 0 then return 0 end
	local f = u * math.max(1, clip.frames - 1) / 3 + 1
	local i = math.floor(f)
	if i >= #zc then return zc[#zc] end
	if i < 1 then return zc[1] end
	local k = f - i
	return zc[i] + (zc[i + 1] - zc[i]) * k
end

local function host_of(npc)
	return npc.tifHostId or npc.tifHomeHost or G.MW_HOST
end

function Act.Clip(npc, name)
	return G.Clip(name, host_of(npc)) or (npc.tifHomeHost and G.Clip(name, npc.tifHomeHost))
end

function Act.Play(npc, name, opts)

	if npc.tifActLock and not (opts and opts.lockOK) then return nil end
	local clip = G.Clip(name, host_of(npc))
	if not clip and npc.tifHomeHost and npc.tifHomeHost ~= host_of(npc) then

		clip = G.Clip(name, npc.tifHomeHost)
		if clip and npc.TIFSetHost then npc:TIFSetHost(npc.tifHomeHost) end
	end
	if not clip then
		TIF.Warn("Action clip missing: ", tostring(name))
		return nil
	end

	if opts and opts.base and not G.Clip(opts.base, host_of(npc)) then opts.base = nil end
	opts = opts or {}
	local now = CurTime()
	local rate = opts.rate or 1
	npc.tifAct = {
		name = name, clip = clip, t0 = now, dur = clip.dur / rate, rate = rate,
		startPos = npc:GetPos(), startYaw = npc:GetAngles().y,

		root = opts.root == true, to = opts.to, loop = clip.loop and not opts.once,

		lift = opts.lift, noTrace = opts.noTrace,

		autoClear = opts.clear == true,

		rootz = opts.rootz == true and clip.zcurve ~= nil,

		warpU = opts.warpU or 1,
	}
	if opts.root and opts.to then
		local a = npc.tifAct
		local x, y, r = Act.RootAt(clip, a.warpU)
		local rad = math.rad(a.startYaw)
		local c, s = math.cos(rad), math.sin(rad)
		local endPos = Vector(a.startPos.x + x * c - y * s, a.startPos.y + x * s + y * c, a.startPos.z)
		a.warp = { dx = opts.to.pos.x - endPos.x, dy = opts.to.pos.y - endPos.y,
			dyaw = math.AngleDifference(opts.to.yaw, a.startYaw + r) }
		if a.rootz then
			a.warp.dz = opts.to.pos.z - (a.startPos.z + Act.ZAt(clip, a.warpU))
		end
		a.to = nil
	end
	npc:SetNW2String("tif_act", name)
	npc:SetNW2Float("tif_act_t", now)
	local sendRate = opts.reverse and -rate or rate
	if npc.tifActRateSent ~= sendRate then
		npc.tifActRateSent = sendRate
		npc:SetNW2Float("tif_act_rate", sendRate)
	end
	local base = opts.base or ""
	if npc.tifActBaseSent ~= base then
		npc.tifActBaseSent = base
		npc:SetNW2String("tif_act_base", base)
	end
	return npc.tifAct.dur
end

function Act.Loop(npc, name, opts)
	local a = npc.tifAct
	if a and a.name == name then return a.dur end
	return Act.Play(npc, name, opts)
end

function Act.Clear(npc, force)
	if not npc.tifAct then return end
	if npc.tifActLock and not force then return end
	npc.tifAct = nil
	npc:SetNW2String("tif_act", "")
	if npc.tifActBaseSent ~= "" then
		npc.tifActBaseSent = ""
		npc:SetNW2String("tif_act_base", "")
	end
end

function Act.Current(npc)
	return npc.tifAct
end

function Act.Progress(npc, now)
	local a = npc.tifAct
	if not a then return nil end
	return math.Clamp((now - a.t0) / math.max(0.01, a.dur), 0, 1)
end

function Act.Done(npc, now)
	local a = npc.tifAct
	return not a or (not a.loop and now - a.t0 >= a.dur)
end

local function smooth(u) return u * u * (3 - 2 * u) end

local ACT_MIN = Vector(-12, -12, 0)
local ACT_MAX = Vector(12, 12, 40)
local ACT_UP4 = Vector(0, 0, 4)
local ACT_ANG = Angle(0, 0, 0)
local actOut1, actOut2 = {}, {}
local actHull1 = { mins = ACT_MIN, maxs = ACT_MAX, mask = MASK_NPCSOLID_BRUSHONLY, output = actOut1 }
local actHull2 = { mins = ACT_MIN, maxs = ACT_MAX, mask = MASK_NPCSOLID_BRUSHONLY, output = actOut2 }

function Act.Tick(npc, now)
	local a = npc.tifAct
	if not a or a.loop or a.finished then return end
	local u = math.Clamp((now - a.t0) / math.max(0.01, a.dur), 0, 1)
	if u >= 1 then a.finished = true end
	local curPos = npc:GetPos()
	local z = a.lift and Lerp(smooth(u), a.lift[1], a.lift[2]) or curPos.z
	local wk = a.warp and smooth(math.min(1, u / math.max(0.01, a.warpU or 1))) or 0
	if a.rootz then z = a.startPos.z + Act.ZAt(a.clip, u) + ((a.warp and a.warp.dz) or 0) * wk end
	if a.to then
		local k = smooth(u)
		local p = LerpVector(k, a.startPos, a.to.pos)
		p.z = z
		npc:SetPos(p)
		ACT_ANG.y = a.startYaw + math.AngleDifference(a.to.yaw, a.startYaw) * k
		npc:SetAngles(ACT_ANG)
	elseif a.root then
		local x, y, r = Act.RootAt(a.clip, u)
		local rad = math.rad(a.startYaw)
		local c, s = math.cos(rad), math.sin(rad)
		local p = Vector(a.startPos.x + x * c - y * s, a.startPos.y + x * s + y * c, z)
		if a.warp then
			p.x, p.y = p.x + a.warp.dx * wk, p.y + a.warp.dy * wk
			r = r + a.warp.dyaw * wk
		end
		if a.noTrace then
			npc:SetPos(p)
		else
			local pUp = p + ACT_UP4
			actHull1.start, actHull1.endpos, actHull1.filter = curPos + ACT_UP4, pUp, npc
			local tr = util.TraceHull(actHull1)
			local hp = tr.HitPos
			if tr.Hit and not tr.StartSolid and tr.HitNormal then
				local nx, ny = tr.HitNormal.x, tr.HitNormal.y
				local nlen2 = nx * nx + ny * ny
				if nlen2 > 0.01 then
					local invN = 1 / math.sqrt(nlen2)
					nx, ny = nx * invN, ny * invN
					local rx, ry = pUp.x - hp.x, pUp.y - hp.y
					local d = rx * nx + ry * ny
					local sx, sy = rx - nx * d, ry - ny * d
					if sx * sx + sy * sy > 0.01 then
						actHull2.start, actHull2.endpos, actHull2.filter = hp, Vector(hp.x + sx, hp.y + sy, hp.z), npc
						local tr2 = util.TraceHull(actHull2)
						if not tr2.StartSolid then hp = tr2.HitPos end
					end
				end
			end
			npc:SetPos(hp - ACT_UP4)
		end
		ACT_ANG.y = a.startYaw + r
		npc:SetAngles(ACT_ANG)
	end
	if a.finished and a.autoClear and npc.tifAct == a then Act.Clear(npc) end
	if a.stopU and u >= a.stopU and npc.tifAct == a then Act.Clear(npc) end
end
