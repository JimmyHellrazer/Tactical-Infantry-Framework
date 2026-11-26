-- Actions: one GTA clip played as a full-body animation, with the server moving the soldier
-- along the clip's root motion (GTG stores it as curves: x forward, y left, yaw CCW, all in
-- the clip's starting frame). Clients play the same clip from the same start time.
--
-- Networked as NW2 "tif_act" (clip name, "" = none) and "tif_act_t" (start CurTime).

local TIF = TIF
local G = TIF.GTG

TIF.Action = TIF.Action or {}
local Act = TIF.Action

local function curve(clip, u, axis)
	if not clip.curve or #clip.curve == 0 then return 0 end
	return G.ClipCurve(clip, u * math.max(1, clip.frames - 1), axis)
end

-- Root offset at progress u (0..1): local x, y, yaw.
function Act.RootAt(clip, u)
	return curve(clip, u, 1), curve(clip, u, 2), curve(clip, u, 3)
end

-- Root height offset at progress u (0..1), from the clip's zcurve (every 3 frames), or 0.
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

-- (Until 0.38.0 a clip the MW19 body lacked was played on the faction's GTA body, switching the soldier to it for
-- the action. The GTA body is gone: the MW19 body is the only one.)
local function host_of(npc)
	return npc.tifHostId or npc.tifHomeHost or G.MW_HOST
end

-- A clip by name on the soldier's body, or nil.
function Act.Clip(npc, name)
	return G.Clip(name, host_of(npc)) or (npc.tifHomeHost and G.Clip(name, npc.tifHomeHost))
end

-- Play a clip.
-- opts.root = true:   move along the clip's own root motion from the current position and yaw.
-- opts.to = { pos, yaw }: instead, blend from the current position/yaw to this target over the clip.
-- Both: follow the clip's own root path, warped so it ends exactly on `to` (the difference between where
-- the clip would end and the target is spread smoothly over the clip: MW19 cover arrivals).
-- opts.rate = playback speed multiplier.
-- Returns the clip's duration, or nil if the clip doesn't exist.
function Act.Play(npc, name, opts)
	-- (0.38.29, user: "the animation of the human shield can be interrupted by them noticing u") A scene that owns his
	-- body (npc.tifActLock: a human shield) takes no other clip: reactions, flinches, turns... are refused (nil, as for
	-- a missing clip). The scene's own calls pass opts.lockOK.
	if npc.tifActLock and not (opts and opts.lockOK) then return nil end
	local clip = G.Clip(name, host_of(npc))
	if not clip and npc.tifHomeHost and npc.tifHomeHost ~= host_of(npc) then
		-- (an older save on another body: back to the home body for this)
		clip = G.Clip(name, npc.tifHomeHost)
		if clip and npc.TIFSetHost then npc:TIFSetHost(npc.tifHomeHost) end
	end
	if not clip then
		TIF.Warn("Action clip missing: ", tostring(name))
		return nil
	end
	-- An upper-body action's base clip must exist on the same body.
	if opts and opts.base and not G.Clip(opts.base, host_of(npc)) then opts.base = nil end
	opts = opts or {}
	local now = CurTime()
	local rate = opts.rate or 1
	npc.tifAct = {
		name = name, clip = clip, t0 = now, dur = clip.dur / rate, rate = rate,
		startPos = npc:GetPos(), startYaw = npc:GetAngles().y,
		-- once: a looping clip played as a single cycle, with its root motion (a shuffle step along cover).
		root = opts.root == true, to = opts.to, loop = clip.loop and not opts.once,
		-- lift = { z0, z1 }: height goes from z0 to z1 over the clip (getting into a seat).
		-- noTrace: root motion may pass through things (through a car door).
		lift = opts.lift, noTrace = opts.noTrace,
		-- clear: drop the action as soon as the clip ends (one-shots nobody follows up: reactions, pains...).
		-- Without it a finished one-shot holds its last frame until something replaces or clears it.
		autoClear = opts.clear == true,
		-- rootz: follow the clip's own height curve too (mantles, vaults, drops).
		rootz = opts.rootz == true and clip.zcurve ~= nil,
		-- warpU: the root+to warp lands on `to` at this point of the clip (a traversal hands back to
		-- locomotion before its run-out ends), not at its end.
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
	-- opts.reverse: the clip plays backwards (clients read a negative rate). Used to sit back down with a
	-- stand-up clip; root motion isn't applied backwards, so use it on clips that stay in place.
	npc:SetNW2Float("tif_act_rate", opts.reverse and -rate or rate)
	-- opts.base: an upper-body-only clip (GTA cover reloads, peeks). The client keeps this base
	-- clip on the legs and plays the action through the upper-body slots.
	npc:SetNW2String("tif_act_base", opts.base or "")
	return npc.tifAct.dur
end

-- Loop a clip with no root motion (cover idle, peek).
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
	npc:SetNW2String("tif_act_base", "")
end

function Act.Current(npc)
	return npc.tifAct
end

-- 0..1 progress of a one-shot action, or nil.
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

-- Every tick: apply root motion / blending.
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
