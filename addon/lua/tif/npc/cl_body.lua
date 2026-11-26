local TIF = TIF
local G = TIF.GTG
local A = TIF.Anim
local Prof = TIF.Prof

local CurTime, RealTime, FrameTime, FrameNumber, SysTime = CurTime, RealTime, FrameTime, FrameNumber, SysTime
local IsValid, Vector, Angle, Matrix = IsValid, Vector, Angle, Matrix
local WorldToLocal, LocalToWorld, LerpVector, LerpAngle = WorldToLocal, LocalToWorld, LerpVector, LerpAngle
local math_abs, math_min, math_max, math_floor = math.abs, math.min, math.max, math.floor
local math_deg, math_rad, math_atan2, math_clamp, math_approach = math.deg, math.rad, math.atan2, math.Clamp, math.Approach
local string_sub, string_find, string_match = string.sub, string.find, string.match
local pairs, ipairs = pairs, ipairs

TIF.Body = TIF.Body or {}
local Bd = TIF.Body

Bd.States = Bd.States or setmetatable({}, { __mode = "k" })
local States = Bd.States
Bd.Rags = Bd.Rags or {}
Bd.Stats = { composed = 0, checks = 0, overwritten = 0, missingSlots = 0, soldiers = 0, missingNow = 0, refreshAsked = 0 }

local cvRetarget = CreateClientConVar("tif_cl_retarget", "1", true, false, "Draw faction models on soldiers (0 = show the bare GTA ped)")

local MUZZLES = { "Gun_Muzzle", "muzzle", "muzzle_flash", "1" }
local FLASH_MAT = Material("effects/muzzleflash2")
local GLOW_MAT = Material("sprites/light_glow02_add")
local FLASH_GLOW_COL = Color(255, 200, 120, 160)
local FLASH_TIME = 0.05
local FLINCH_TIME = 0.35
local LEG_RATE, UB_RATE, FIRE_RATE = 7, 4, 14

local IDLE_WEIGHT = 0.002

local function host_bone_check(e)
	local st = States[e]
	if not st or not st.want0 then return end
	if st.writeFrame ~= FrameNumber() then
		Bd.Stats.early = (Bd.Stats.early or 0) + 1
		return
	end
	Bd.Stats.checks = Bd.Stats.checks + 1
	if e:GetLayerSequence(0) ~= st.want0 then Bd.Stats.overwritten = Bd.Stats.overwritten + 1 end
end

function Bd.Add(ent)
	if States[ent] then return end

	States[ent] = { legW = {}, ubW = {}, phase = 0, idleT = math.Rand(0, 10), pitch = 0, idleVar = (ent:EntIndex() * 7) % 60 }
	if not ent.tifBoneCb then ent.tifBoneCb = ent:AddCallback("BuildBonePositions", host_bone_check) end
end

local function remove_parts(st)
	if IsValid(st.follower) then st.follower:Remove() end
	if IsValid(st.gun) then st.gun:Remove() end
	if IsValid(st.backGun) then st.backGun:Remove() end
	if IsValid(st.launcherGun) then st.launcherGun:Remove() end
	st.follower, st.gun, st.backGun, st.backClass = nil, nil, nil, nil
	st.launcherGun, st.launcherClass = nil, nil
end

function Bd.State(ent) return States[ent] end

function Bd.Remove(ent)
	local st = States[ent]
	if st and not st.handedOver then remove_parts(st) end
	if st and TIF.Props then TIF.Props.Remove(st) end
	States[ent] = nil
end

local function rest_pose(f)
	local seq = f:LookupSequence("reference")
	if not seq or seq < 0 then seq = f:LookupSequence("ragdoll") end
	if seq and seq >= 0 then
		f:ResetSequence(seq)
		f.tifRestSeq = seq
	end
	f:SetCycle(0)
	f:SetPlaybackRate(0)
end

local function solve_cb(fe)
	local map = fe.tifMap
	if not map then return end
	local t0 = SysTime()
	G.Solve(fe, map)
	Prof.Count("cl_solve_us", (SysTime() - t0) * 1e6)
	Prof.Count("cl_solves", 1)
end

local function apply_look(f, skin, bodygroups)
	f:SetSkin(skin or 0)
	local digits = string.Explode(" ", bodygroups or "")
	for i = 0, f:GetNumBodyGroups() - 1 do f:SetBodygroup(i, tonumber(digits[i + 1]) or 0) end
end

local function make_follower(parent, model, skin, bodygroups, vb)
	local map = not vb and G.MapFor(parent:GetModel(), model) or nil
	if not vb and not map then return nil end
	local f = ClientsideModel(model, RENDERGROUP_OPAQUE)
	if not IsValid(f) then return nil end
	rest_pose(f)
	apply_look(f, skin, bodygroups)
	f:SetParent(parent)
	f:AddEffects(EF_BONEMERGE)
	f:AddEffects(EF_BONEMERGE_FASTCULL)
	if vb then
		f:CreateShadow()
		return f
	end
	for _, m in ipairs(map.MAN) do
		f:ManipulateBoneAngles(m.b, m.angle)
		f:ManipulateBonePosition(m.b, m.vector)
	end
	f.tifMap = map
	f:AddCallback("BuildBonePositions", solve_cb)
	f:CreateShadow()
	return f
end

local function make_gun(ent, class, vb)
	local stored = TIF.GTG.Stored(class)
	local wm = stored and stored.WorldModel
	if not wm or wm == "" then return nil end
	local g = ClientsideModel(wm, RENDERGROUP_OPAQUE)
	if not IsValid(g) then return nil end

	if not g:LookupBone("PH_R_Hand") then g.tifFree = true end

	g.tifHold = stored.TIFBaked and stored.TIFBaked.hold or nil
	if vb or g.tifFree then return g end
	g:SetParent(ent)
	g:AddEffects(EF_BONEMERGE)
	g:AddEffects(EF_BONEMERGE_FASTCULL)
	return g
end
Bd.MakeGun = make_gun

local function mw_weapon(hostId, class)
	local def = G.WeaponDef(class)
	local kind = G.WeaponKind(class)
	local base = kind == "rifle" and "mw_reload" or ("mw_reload_" .. kind)
	local stand = G.Clip(base, hostId) or G.Clip("mw_reload", hostId)
	local crouch = G.Clip(base .. "_cr", hostId) or G.Clip("mw_reload_cr", hostId) or stand
	local function fires(prefix)
		local list = {}
		for n = 1, 4 do
			local c = G.Clip(prefix .. n, hostId)
			if c then list[#list + 1] = c end
		end
		return #list > 0 and list or nil
	end
	local fs = fires("mw_fire_" .. kind .. "_")
	return kind, stand, crouch, def and def.reload_time or 2.2, fs, fires("mw_fire_" .. kind .. "_cr_") or fs
end

local function ensure_parts(ent, st)
	local host = TIF.Factions[ent:GetTIFFaction()]

	local byModel = TIFG and TIFG.ByModel and TIFG.ByModel[string.lower(ent:GetModel() or "")]
	local hostId = byModel or (host and host.host) or G.DEFAULT_HOST
	if st.hostId and st.hostId ~= hostId then

		remove_parts(st)
		st.vis, st.wclass, st.legs, st.wset, st.mwReload = nil, nil, nil, nil, nil
		st.legW, st.ubW, st.legCycle, st.ubCycle = {}, {}, {}, {}
		st.proneOn, st.vbSpine2, st.vbSpine4, st.spine, st.pitch = false, nil, nil, nil, 0
		st.vbPelvis, st.vbSp0, st.vbSp1, st.eyeHead = nil, nil, nil, nil
		st.lastB2P, st.lastB2Y, st.lastB4Y = nil, nil, nil
		for i = 0, ent:GetBoneCount() - 1 do ent:ManipulateBoneAngles(i, angle_zero) end
		if st.tiltOn then ent:SetRenderAngles(nil) end
		st.tiltOn, st.tiltP, st.tiltR = false, 0, 0
		Bd.Stats.hostSwaps = (Bd.Stats.hostSwaps or 0) + 1
	end
	st.hostId = hostId
	st.vb = G.IsVB(hostId)
	local vis = cvRetarget:GetBool() and ent:GetTIFVisual() or ""

	if st.visFrom and st.visFrom ~= vis then st.visFrom, st.visAlt, st.visFails = nil, nil, 0 end
	if vis ~= "" and st.visFrom == vis and st.visAlt then vis = st.visAlt end
	if IsValid(st.follower) then st.visFails = 0 end

	local now = CurTime()
	if now >= (st.partRetry or 0) then
		st.partRetry = now + 2
		if vis ~= "" and not IsValid(st.follower) then
			st.vis = nil
			st.visFails = (st.visFails or 0) + 1
			if st.visFails >= 2 and not st.visAlt and host and TIF.UsableVisuals then
				local list = TIF.UsableVisuals(host, host.models or {})
				local alt = list[math.random(#list)]
				if alt and alt ~= vis and TIF.VisualUsable(host.host, alt) then
					st.visFrom, st.visAlt = vis, alt
					Bd.VisAlt = Bd.VisAlt or {}
					Bd.VisAlt[vis] = alt
					vis = alt
					Bd.Stats.visualFallbacks = (Bd.Stats.visualFallbacks or 0) + 1
				end
			end
		end
		if ent:GetTIFWeapon() ~= "" and not IsValid(st.gun) then st.wclass = nil end
	end
	if vis ~= st.vis then
		if IsValid(st.follower) then st.follower:Remove() end

		local plain = st.vb and not (TIF.Modular and TIF.Modular.NeedsRetarget(vis))
		st.follower = vis ~= "" and make_follower(ent, vis, ent:GetTIFSkin(), ent:GetTIFBodygroups(), plain) or nil
		st.vis = vis
		st.look = nil
		st.proneOn = false

		ent:DrawShadow(not IsValid(st.follower))
	end

	if IsValid(st.follower) then
		local skin, groups = ent:GetTIFSkin(), ent:GetTIFBodygroups()
		local look = tostring(skin) .. "|" .. groups
		if look ~= st.look then
			apply_look(st.follower, skin, groups)
			st.look = look
		end
	end
	local class = ent:GetTIFWeapon()
	if class ~= st.wclass then
		if IsValid(st.gun) then st.gun:Remove() end
		st.gun = class ~= "" and make_gun(ent, class, st.vb) or nil
		st.wclass = class
		st.gunDropped = nil
		if st.vb then

			st.wset = nil
			st.wkind, st.mwReload, st.mwReloadCr, st.mwReloadTime, st.mwFire, st.mwFireCr = mw_weapon(st.hostId, class)
			st.pistol = st.wkind == "pistol"
		else
			st.wkind, st.pistol, st.mwFire, st.mwFireCr, st.fireClip = nil, G.WeaponKind(class) == "pistol", nil, nil, nil
			st.wset = A.WeaponSet(st.hostId, G.WeaponDef(class))
		end
		st.muzzle = nil
		st.gunOff, st.gunGripInv = nil, nil
		st.proneOn = false
	end
	if not st.legs then st.legs = A.Legs(st.hostId) end
end

local function approach(w, target, rate, dt)
	if w < target then return math.min(target, w + rate * dt) end
	return math.max(target, w - rate * dt)
end

local function settle(weights, targets, rate, dt)
	for clip, w in pairs(weights) do
		local t = targets[clip] or 0
		local nw = approach(w, t, rate, dt)
		if nw <= 0.001 and t <= 0 then weights[clip] = nil else weights[clip] = nw end
	end
	for clip, t in pairs(targets) do
		if not weights[clip] and t > 0 then weights[clip] = approach(0, t, rate, dt) end
	end
end

local function top(weights, n, sorted)
	local pool = sorted._p
	if not pool then pool = {} sorted._p = pool end
	local count = 0
	for clip, w in pairs(weights) do
		count = count + 1
		local e = pool[count]
		if not e then e = {} pool[count] = e end
		e.clip, e.w = clip, w
		local j = count
		while j > 1 and sorted[j - 1].w < w do
			sorted[j] = sorted[j - 1]
			j = j - 1
		end
		sorted[j] = e
	end
	local keep = count < n and count or n
	for i = #sorted, keep + 1, -1 do sorted[i] = nil end
	return sorted
end
local LEG_BUF, UB_BUF = {}, {}
local LEG_TGT, UB_TGT = {}, {}

local function clear_table(t)
	for k in pairs(t) do t[k] = nil end
	return t
end

local function add(t, clip, w)
	if clip and w > 0.0005 then t[clip] = (t[clip] or 0) + w end
end

Bd.HIP_MAX, Bd.HIP_RATE = 70, 240
local function hip_turn(st, relAng, moveK)
	st.hipWant = math.Clamp(relAng, -Bd.HIP_MAX, Bd.HIP_MAX) * math.Clamp(moveK, 0, 1)
end
Bd.HipTurn = hip_turn

Bd.CARRY_R = 0.35
local carryCache = {}
function Bd.ClipCarriesGun(clip)
	local src = clip.from or clip.seq or ""
	local v = carryCache[src]
	if v ~= nil then return v end
	v = false
	local U, H = TIFG_JGUN_UNDRIVEN, TIFG_JGUN_HOLD
	local e = U and not U[src] and H and H[src]
	if e and e.r then
		for _, r in ipairs(e.r) do if r > Bd.CARRY_R then v = true break end end
	end
	if H then carryCache[src] = v end
	return v
end

local function leg_targets(st, legs, mode, stance, speed, relAng)
	local T = {}
	st.hipWant = 0

	local PS = (st.pistol and legs.pistol) or (st.wkind and legs[st.wkind]) or nil

	if mode ~= 1 and stance ~= 1 and speed > 25 and math.abs(relAng) > 75 then mode = 1 end

	local rg = st.runGun and legs.rungun and legs.rungun[st.runGun]
	if rg and speed > 100 and not PS then
		add(T, rg, 1)
		return T, legs.relaxed
	end

	local GR = legs.grade
	local grade = st.grade or 0
	if GR and speed > 30 and math.abs(grade) > 0.22 and math.abs(relAng) < 50 and stance ~= 1 and not PS then
		local ud = grade > 0 and "up" or "down"
		local clip
		if math.abs(grade) > 0.45 then
			local key
			if mode == 1 then key = speed > 200 and "run" or (speed > 140 and "fast" or "aim")
			elseif st.alertPosture then key = (st.light and GR.stairs["alertf_" .. ud]) and "alertf" or "alert"
			else key = speed > 120 and "run" or ((st.light and GR.stairs["calmf_" .. ud]) and "calmf" or "calm") end
			clip = GR.stairs[key .. "_" .. ud]
		else
			local g = speed > 200 and "sprint" or (speed > 150 and "run" or (speed > 100 and "jog"
				or ((mode == 1 or st.alertPosture) and "walk" or "slwalk")))
			clip = GR.slope[g .. "_" .. ud]
		end
		if clip then
			add(T, clip, 1)
			hip_turn(st, relAng, 1)
			return T, legs.relaxed
		end
	end

	local WD = st.wade and st.wade > 0 and stance ~= 1 and not st.pistol and legs.wade
	if WD then

		if mode == 1 or not (WD.knee or WD.chest) or (speed > 25 and math.abs(relAng) > 75) then
			local set = WD.aim
			local moveK = math.Clamp(speed / (set.walkSpeed * 0.6), 0, 1)
			local rk = set.run and math.Clamp((speed - set.walkSpeed) / math.max(1, set.runSpeed - set.walkSpeed), 0, 1) or 0
			add(T, set.idle, 1 - moveK)
			if moveK > 0 then
				local a, b, k = A.PickDir(set.walk, relAng)
				add(T, a, moveK * (1 - rk) * (1 - k))
				add(T, b, moveK * (1 - rk) * k)
				if rk > 0 then
					local ra, rb, rkk = A.PickDir(set.run, relAng)
					add(T, ra, moveK * rk * (1 - rkk))
					add(T, rb, moveK * rk * rkk)
				end
			end
			return T, set
		end
		local set = (st.wade == 2 and WD.chest) or WD.knee or WD.chest
		local moveK = math.Clamp(speed / (set.walkSpeed * 0.6), 0, 1)
		add(T, set.idle, 1 - moveK)
		add(T, set.walk, moveK)
		hip_turn(st, relAng, moveK)
		return T, set
	end

	local AL =(PS and PS.alert) or (st.light and legs.alertFlash) or legs.alert
	if AL and st.alertPosture and mode == 1 and stance ~= 1
		and (speed < 10 or (math.abs(relAng) < 70 and speed < AL.walkSpeed * 1.5)) then
		st.handLight = AL.handLight == true
		local moveK = math.Clamp(speed / (AL.walkSpeed * 0.6), 0, 1)
		add(T, AL.variants and AL.variants[st.idleVar % #AL.variants + 1] or AL.idle, 1 - moveK)
		add(T, AL.walkVariants and AL.walkVariants[st.idleVar % #AL.walkVariants + 1] or AL.walk, moveK)
		hip_turn(st, relAng, moveK)
		return T, AL
	end
	if stance == 1 or mode == 1 then
		local set = stance == 1 and ((PS and PS.crouch) or legs.crouch) or ((PS and PS.aim) or legs.aim)

		if stance ~= 1 and st.cqbMode and legs.cqb and not st.pistol then set = legs.cqb end
		local moveK = math.Clamp(speed / (set.walkSpeed * 0.6), 0, 1)
		local rk = set.run and math.Clamp((speed - set.walkSpeed) / math.max(1, set.runSpeed - set.walkSpeed), 0, 1) or 0

		local idle = set.idle
		if set.twitches then
			local now, tw = CurTime(), st.aimTw
			local quiet = now - (st.lastShot or 0) > 2
			if tw and (moveK > 0.05 or not quiet or now - st.aimTwT >= tw.dur) then st.aimTw, tw = nil, nil end
			if not tw and moveK < 0.05 and quiet and now >= (st.aimTwNext or 0) then
				if st.aimTwNext then
					tw = set.twitches[math.random(#set.twitches)]
					st.aimTw, st.aimTwT = tw, now
				end
				st.aimTwNext = now + math.Rand(6, 12)
			end
			if tw then
				st.legCycle[tw] = math.Clamp((now - st.aimTwT) / tw.dur, 0, 1)
				idle = tw
			end
		end
		add(T, idle, 1 - moveK)
		if moveK > 0 then
			local a, b, k = A.PickDir(set.walk, relAng)
			add(T, a, moveK * (1 - rk) * (1 - k))
			add(T, b, moveK * (1 - rk) * k)
			if rk > 0 and set.run then
				local ra, rb, rkk = A.PickDir(set.run, relAng)
				add(T, ra, moveK * rk * (1 - rkk))
				add(T, rb, moveK * rk * rkk)
			end
		end
		return T, set
	end
	local set = (PS and PS.relaxed) or (st.light and legs.relaxedFlash) or legs.relaxed
	local moveK = math.Clamp(speed / (set.walkSpeed * 0.6), 0, 1)
	local rk = math.Clamp((speed - set.walkSpeed) / math.max(1, set.runSpeed - set.walkSpeed), 0, 1)
	local sk = set.sprint and math.Clamp((speed - set.runSpeed) / math.max(1, set.sprintSpeed - set.runSpeed), 0, 1) or 0
	add(T, set.variants and set.variants[st.idleVar % #set.variants + 1] or set.idle, 1 - moveK)
	local walk = set.walkVariants and set.walkVariants[st.idleVar % #set.walkVariants + 1] or set.walk
	add(T, walk, moveK * (1 - rk))
	add(T, set.run or walk, moveK * rk * (1 - sk))
	add(T, set.sprint, moveK * rk * sk)
	hip_turn(st, relAng, moveK)
	return T, set
end

local function ub_targets(ent, st, mode, speed, now)
	local W = st.wset
	local T = clear_table(UB_TGT)

	if st.vb then
		local shot = ent:GetTIFShotTime()
		local crouched = ent:GetTIFStance() == 1
		if shot ~= st.lastShot then
			st.lastShot, st.flashAt = shot, now

			local list = crouched and st.mwFireCr or st.mwFire
			st.fireClip = list and list[math.random(#list)] or nil
		end

		local sw = ent:GetNW2String("tif_switch_clip", "")
		if sw ~= "" and not st.fullBody then
			local S = G.Clip(sw, st.hostId)
			local u = S and (now - ent:GetNW2Float("tif_switch_t", 0)) / math.max(0.1, S.dur)
			if S and u >= 0 and u < 1 then
				st.ubCycle[S] = u
				st.switchClip, st.switchU = S, u
				add(T, S, 1)
				return T, UB_RATE * 3
			end
		end
		local rs = ent:GetTIFReloadStart()

		local R = crouched and st.mwReloadCr or st.mwReload

		if rs > 0 and R and not st.fullBody then
			local u = (now - rs) / math.max(0.3, st.mwReloadTime or 2.2)
			if u < 1 then
				st.ubCycle[R] = math.Clamp(u, 0, 1)
				st.magClip, st.magU, st.magKey = R, st.ubCycle[R], rs
				add(T, R, 1)
				return T, UB_RATE * 2
			end
		end
		local F = st.fireClip
		if F and not st.fullBody and st.flashAt then
			local u = (now - st.flashAt) / math.max(0.05, F.dur)
			if u < 1 then
				st.ubCycle[F] = u
				add(T, F, 1)
				return T, UB_RATE * 4
			end
		end

		if mode == 1 and not st.fullBody and not st.pistol and st.wkind ~= "rpg" and ent:GetNW2Bool("tif_lowready", false) then
			local LR = (st.cqbMode and G.Clip("lowready_cqb", st.hostId)) or G.Clip("lowready", st.hostId)
			if LR then
				st.ubCycle[LR] = (st.idleT / LR.dur) % 1
				add(T, LR, 1)
				return T, UB_RATE * 1.2
			end
		end
		return T, UB_RATE * 2
	end

	if st.ubAct then
		st.ubCycle[st.ubAct] = st.ubActCycle
		add(T, st.ubAct, 1)
		return T, UB_RATE * 2
	end
	if not W then return T, nil end

	if st.fullBody then
		local shot = ent:GetTIFShotTime()
		if shot ~= st.lastShot then st.lastShot, st.flashAt = shot, now end
		return T, UB_RATE * 1.5
	end
	local rs = ent:GetTIFReloadStart()
	if rs > 0 and W.reload and now - rs < W.reload.dur then
		st.ubCycle[W.reload] = math.Clamp((now - rs) / W.reload.dur, 0, 1)
		add(T, W.reload, 1)
		return T, UB_RATE * 2
	end
	if mode == 1 then
		local shot = ent:GetTIFShotTime()
		if shot ~= st.lastShot then
			if not st.lastShot or shot - st.lastShot > W.rate * 2.5 then st.burstStart = shot end
			st.lastShot = shot
			st.flashAt = now
		end
		local since = st.lastShot and (now - st.lastShot) or 99
		if W.fire and since < math.max(W.rate * 1.6, 0.12) then
			st.ubCycle[W.fire] = ((now - (st.burstStart or now)) / W.fire.dur) % 1
			add(T, W.fire, 1)
			return T, FIRE_RATE
		end
		if W.settle and since < W.settle.dur then
			st.ubCycle[W.settle] = math.Clamp(since / W.settle.dur, 0, 1)
			add(T, W.settle, 1)
			return T, UB_RATE
		end
		st.ubCycle[W.aim] = 0
		add(T, W.aim, 1)
		return T, UB_RATE
	end

	local legs = st.legs.relaxed
	local moveK = math.Clamp(speed / (legs.walkSpeed * 0.6), 0, 1)
	local rk = math.Clamp((speed - legs.walkSpeed) / math.max(1, legs.runSpeed - legs.walkSpeed), 0, 1)
	add(T, W.holdIdle or W.aim, 1 - moveK)
	add(T, W.holdWalk or W.holdIdle, moveK * (1 - rk))
	add(T, W.holdRun or W.holdWalk, moveK * rk)
	return T, UB_RATE
end

local function write_slot(ent, slot, seq, cycle, w)
	if seq and seq >= 0 and w > IDLE_WEIGHT then
		ent:SetLayerSequence(slot, seq)
		ent:SetLayerCycle(slot, cycle)
		ent:SetLayerWeight(slot, w)
		ent:SetLayerPlaybackRate(slot, 0)
	else
		ent:SetLayerWeight(slot, IDLE_WEIGHT)
	end
end

local function first_plant(c)
	local l, r = c.lplant and c.lplant[1], c.rplant and c.rplant[1]
	if l == 0 and r == 0 then return nil end
	if l and (not r or l <= r) then return "l" end
	if r then return "r" end
	return nil
end

local function last_plant(c)
	local frames = math.max(1, (c.frames or 2) - 1)
	if (c.lplant and c.lplant[1]) == 0 and (c.rplant and c.rplant[1]) == 0 then return nil end
	local best, foot = -1, nil
	for _, f in ipairs(c.lplant or {}) do if f <= frames and f > best then best, foot = f, "l" end end
	for _, f in ipairs(c.rplant or {}) do if f <= frames and f > best then best, foot = f, "r" end end
	if not foot then return nil end
	return foot, (frames - best) * c.dur / frames
end

local STOP_FOOT = { "^(mwt_stop_%a+_)([lr])(_%d)$", "^(mwp_cstop_)([lr])()$" }
function Bd.StopFoot(ent, st, name)
	if name == "" or string.sub(name, 5, 8) ~= "stop" and string.sub(name, 5, 9) ~= "cstop" then return name end
	local t0 = ent:GetNW2Float("tif_act_t", 0)
	local sw = st.stopFoot
	if sw and sw.t0 == t0 and sw.from == name then return sw.to end
	local to = name
	for _, pat in ipairs(STOP_FOOT) do
		local a, foot, b = string.match(name, pat)
		if a then
			local want = (st.phase % 1) < 0.5 and "r" or "l"
			local c = G.Clip(name, st.hostId)
			local have = c and (first_plant(c) or foot)
			if have and have ~= want then
				local other = a .. (foot == "l" and "r" or "l") .. b
				local oc = G.Clip(other, st.hostId)
				if oc and (first_plant(oc) or (foot == "l" and "r" or "l")) == want then to = other end
			end
			break
		end
	end
	st.stopFoot = { t0 = t0, from = name, to = to }
	return to
end

function Bd.FootHandoff(st, prev, cur, now)
	if not prev or prev == "" then return end
	if string.sub(prev, 1, 10) ~= "mwt_start_" and string.sub(prev, 1, 11) ~= "mwp_cstart_" then return end
	local c = G.Clip(prev, st.hostId)
	if not c then return end
	local foot, since = last_plant(c)
	if foot then st.footHand = { foot = foot, since = since, at = now } end
end

local function clip_cycle(st, clip, moving)
	local fixed = st.legCycle and st.legCycle[clip]
	if fixed then return fixed end
	local frames = math.max(1, clip.frames - 1)

	if clip.loop and (clip.speed or 0) > 1 then
		return G.FrameForPhase(clip, st.phase) / frames
	end

	if clip.loop then
		local t0 = st.loopStart and st.loopStart[clip] or 0
		return ((st.idleT - t0) % clip.dur) / clip.dur
	end
	return 0
end

local KICK_SLOTS = { 5, 6, 7 }
Bd.KICK_W = 1
Bd.BIPOD_W = 0.4
Bd.BIPOD_HOLD = 1.2
local cvKick = CreateClientConVar("tif_recoil_scale", "1", true, false, "MW19 body: strength of the recoil kicks (0 = off)")
local function pool_of(K, kind, st)
	local p = K[kind] and K[kind][st]
	return p and #p > 0 and p or nil
end

local function kick_pool(ent, st, K)
	if st.wkind == "rpg" then return nil end
	local kind = st.pistol and "pistol" or (st.wkind == "shotgun" and "shotgun") or "rifle"
	local crouched = ent:GetTIFStance() == 1
	local function own(cr)
		return pool_of(K, kind, cr and "cr" or "st") or pool_of(K, kind, "st") or pool_of(K, "rifle", cr and "cr" or "st")
	end
	if st.vbProne then

		if st.vbProne ~= 2 or not (st.aim9 or st.bipod == "set") then return nil end
		return pool_of(K, "prone", "pr") or own(true), st.bipod == "set" and Bd.BIPOD_W or 1
	end
	local an = st.actName or ""
	local t, p = string.match(an, "^mwc_(%a%a)(p?)_aim$")
	if t then
		if p == "p" or st.pistol then return pool_of(K, "pistol", "st") or own(false), 1 end
		if t == "cr" then return own(true), 1 end
		if t == "st" then return own(false), 1 end
		return pool_of(K, "lean", t) or own(t == "lc" or t == "rc"), 1
	end
	if string.match(an, "^mwb_%a+_aim$") then
		return own(string.find(an, "crouch", 1, true) ~= nil), Bd.BIPOD_W
	end
	if st.fullBody then return nil end
	return own(crouched), 1
end
Bd.KickPool = kick_pool
local function recoil_kicks(ent, st, legs, now)
	if not (st.vb and (legs.kicks or legs.whizby)) then return end
	local K = legs.kicks
	st.kicks = st.kicks or {}
	local shot = ent:GetTIFShotTime()
	if K and shot ~= st.kickShot then
		st.kickShot = shot
		if shot > 0 and now - shot < 0.5 then
			local pool, kw = kick_pool(ent, st, K)
			if pool then
				st.kickI = (st.kickI or 0) % #KICK_SLOTS + 1
				st.kicks[KICK_SLOTS[st.kickI]] = { clip = pool[math.random(#pool)], t0 = now, w = kw or 1 }
			end
		end
	end

	local wt = ent:GetNW2Float("tif_whizby_t", 0)
	if wt ~= st.whizT then
		st.whizT = wt
		local c = legs.whizby and legs.whizby[ent:GetNW2Int("tif_whizby_n", 1)]
		if c and wt > 0 and now - wt < 0.5 and not st.fullBody and not st.vbProne then
			st.kickI = (st.kickI or 0) % #KICK_SLOTS + 1
			st.kicks[KICK_SLOTS[st.kickI]] = { clip = c, t0 = now, w = 1, flinch = true }
		end
	end
	local w = Bd.KICK_W * cvKick:GetFloat()

	local stop = st.fullBody and not (st.vbProne or string.match(st.actName or "", "^mw[cb]_.-_aim$"))
	for _, slot in ipairs(KICK_SLOTS) do
		local k = st.kicks[slot]
		if k then
			local u = (now - k.t0) / math.max(0.05, k.clip.dur)

			local kw = k.flinch and (k.w or 1) or w * (k.w or 1)
			if u >= 1 or stop or kw <= 0 then
				st.kicks[slot] = nil
			else
				write_slot(ent, slot, A.Seq(ent, k.clip, false), u, kw)
			end
		end
	end
end

local function check_slots(ent, st, now)
	if now < (st.nextSlotCheck or 0) then return st.slotsOk end
	st.nextSlotCheck = now + 0.5
	local ok = true
	for i = 0, A.SLOTS - 1 do
		if not ent:IsValidLayer(i) then ok = false break end
	end
	st.slotsOk = ok
	if not ok and now > (st.nextRefreshAsk or 0) then
		st.nextRefreshAsk = now + 2
		Bd.Stats.refreshAsked = Bd.Stats.refreshAsked + 1
		net.Start("tif_slots_missing")
		net.WriteEntity(ent)
		net.SendToServer()
	end
	return ok
end

local SCRATCH_ANG = Angle(0, 0, 0)
local SCRATCH_ANG2 = Angle(0, 0, 0)

local function flinch(ent, st, now)
	local ht = ent:GetTIFHitTime()
	if ht ~= st.hitTime then st.hitTime = ht end
	local bone = st.spine
	if bone == nil then
		bone = ent:LookupBone("ValveBiped.Bip01_Spine2") or false
		st.spine = bone
	end
	if not bone then return end
	local k = ht > 0 and 1 - (now - ht) / FLINCH_TIME or 0
	if k > 0 then
		local d = ent:GetTIFHitDir()
		local push = d:Dot(ent:GetForward())
		local side = d:Dot(ent:GetRight())
		SCRATCH_ANG.p, SCRATCH_ANG.y, SCRATCH_ANG.r = side * 9 * k, 0, push * -12 * k
		ent:ManipulateBoneAngles(bone, SCRATCH_ANG)
		st.flinching = true
	elseif st.flinching then
		ent:ManipulateBoneAngles(bone, angle_zero)
		st.flinching = false
	end
end

local cvTrim = CreateClientConVar("tif_aim_trim", "1.2", true, false, "MW19 body: degrees the aimed upper body is tipped down (gun level at ~1.2)")
Bd.AIM_TRIM = 1.2
Bd.KICK, Bd.KICK_T = 2.5, 0.09
local function vb_pose(ent, st, now, dt)
	local b2, b4 = st.vbSpine2, st.vbSpine4
	if b2 == nil then
		b2 = ent:LookupBone("ValveBiped.Bip01_Spine2") or false
		b4 = ent:LookupBone("ValveBiped.Bip01_Spine4") or false
		st.vbSpine2, st.vbSpine4 = b2, b4
	end
	if not (b2 and b4) then return end
	local aiming = ent:GetTIFMode() == 1 and not st.fullBody and not ent:GetNW2Bool("tif_lowready", false)
	Bd.AIM_TRIM = cvTrim:GetFloat()
	local want = aiming and math_clamp(ent:GetTIFAimPitch() + Bd.AIM_TRIM, -55, 55) or 0
	st.pitch = approach(st.pitch or 0, want, 140, dt)
	local kick = 0
	if st.flashAt and not (st.legs and st.legs.kicks) then
		local t = now - st.flashAt
		if t < Bd.KICK_T then kick = -Bd.KICK * (1 - t / Bd.KICK_T) ^ 2 end
	end
	local side, push = 0, 0
	local ht = ent:GetTIFHitTime()
	local k = ht > 0 and 1 - (now - ht) / FLINCH_TIME or 0
	if k > 0 then
		local d = ent:GetTIFHitDir()
		push = d:Dot(ent:GetForward()) * 12 * k
		side = d:Dot(ent:GetRight()) * 9 * k
	end
	local b2p = side
	local b2y = st.pitch * 0.45 + push + kick
	local b4y = st.pitch * 0.45 + kick * 0.6
	if b2p ~= st.lastB2P or b2y ~= st.lastB2Y then
		st.lastB2P, st.lastB2Y = b2p, b2y
		SCRATCH_ANG.p, SCRATCH_ANG.y, SCRATCH_ANG.r = b2p, b2y, 0
		ent:ManipulateBoneAngles(b2, SCRATCH_ANG)
	end
	if b4y ~= st.lastB4Y then
		st.lastB4Y = b4y
		SCRATCH_ANG.p, SCRATCH_ANG.y, SCRATCH_ANG.r = 0, b4y, 0
		ent:ManipulateBoneAngles(b4, SCRATCH_ANG)
	end

	local bp = st.vbPelvis
	if bp == nil then
		bp = ent:LookupBone("ValveBiped.Bip01_Pelvis") or false
		st.vbPelvis = bp
		st.vbSp0 = ent:LookupBone("ValveBiped.Bip01_Spine") or false
		st.vbSp1 = ent:LookupBone("ValveBiped.Bip01_Spine1") or false
	end
	if bp and st.vbSp0 and st.vbSp1 then
		local hwant = st.fullBody and 0 or (st.hipWant or 0)
		st.hip = approach(st.hip or 0, hwant, Bd.HIP_RATE, dt)
		if math_abs(st.hip) > 0.05 or st.hipOn then
			st.hipOn = math_abs(st.hip) > 0.05
			local h = st.hipOn and st.hip or 0
			SCRATCH_ANG.p, SCRATCH_ANG.y, SCRATCH_ANG.r = h, 0, 0
			SCRATCH_ANG2.p, SCRATCH_ANG2.y, SCRATCH_ANG2.r = 0, 0, -h * 0.5
			ent:ManipulateBoneAngles(bp, SCRATCH_ANG)
			ent:ManipulateBoneAngles(st.vbSp0, SCRATCH_ANG2)
			ent:ManipulateBoneAngles(st.vbSp1, SCRATCH_ANG2)
		end
	end
end

local HOLD_POS = Vector(0, 0, 0)
local function hold_of(clip, u)
	local U, H = TIFG_JGUN_UNDRIVEN, TIFG_JGUN_HOLD
	local src = clip.from or clip.seq or ""
	if not U or U[src] then return 0 end
	local e = H and H[src]
	if not e then return 0 end
	local n = #e.r
	local x = math_clamp(u or 0, 0, 1) * ((clip.frames or (n * 3)) - 1) / 3 + 1
	local i = math_clamp(math_floor(x), 1, n)
	local k = math_clamp(x - i, 0, 1)
	local i2 = math_min(n, i + 1)
	return e.r[i] + (e.r[i2] - e.r[i]) * k, e, i, i2, k
end

local function hold_pos(e, i, i2, k)
	local o = e.o
	if not o or #o < i2 * 3 then return nil end
	local a, b = (i - 1) * 3, (i2 - 1) * 3
	local x = o[a + 1] + (o[b + 1] - o[a + 1]) * k
	local y = o[a + 2] + (o[b + 2] - o[a + 2]) * k
	local z = o[a + 3] + (o[b + 3] - o[a + 3]) * k

	HOLD_POS.x, HOLD_POS.y, HOLD_POS.z = -y, x, z
	return HOLD_POS
end

local function clip_driven(clip)
	local U = TIFG_JGUN_UNDRIVEN
	local src = clip.from or clip.seq or ""
	return (U and not U[src] and TIFG_JGUN_HOLD) and 1 or 0
end

local function compose(ent, st, dt, now)
	local legs = st.legs
	if not legs then return end
	local pos = ent:GetPos()
	local vx, vy, vz = 0, 0, 0
	if st.lastPos then
		local invDt = 1 / math_max(dt, 0.001)
		vx = (pos.x - st.lastPos.x) * invDt
		vy = (pos.y - st.lastPos.y) * invDt
		vz = (pos.z - st.lastPos.z) * invDt
		if vx * vx + vy * vy + vz * vz > 640000 then vx, vy, vz = 0, 0, 0 end
	end
	st.lastPos = pos
	local sv = st.vel
	if sv then
		local a = math_min(1, dt * 10)
		sv.x = sv.x + (vx - sv.x) * a
		sv.y = sv.y + (vy - sv.y) * a
		sv.z = sv.z + (vz - sv.z) * a
	else
		sv = Vector(vx, vy, vz)
		st.vel = sv
	end
	local speed = sv:Length2D()
	local g = speed > 20 and math_clamp(sv.z / speed, -1.5, 1.5) or 0
	st.grade = st.grade and (st.grade + (g - st.grade) * math_min(1, dt * 4)) or g
	local lv = WorldToLocal(sv, angle_zero, vector_origin, ent:GetAngles())
	local relAng = math_deg(math_atan2(lv.y, lv.x))
	local mode, stance = ent:GetTIFMode(), ent:GetTIFStance()
	st.idleT = st.idleT + dt
	st.loopOffset = st.loopOffset or (ent:EntIndex() * 0.737) % 7

	st.legCycle = st.legCycle or {}
	local actName = ent:GetNW2String("tif_act", "")
	if actName ~= (st.footAct or "") then
		Bd.FootHandoff(st, st.footAct, actName, now)
		st.footAct = actName
	end
	actName = Bd.StopFoot(ent, st, actName)
	st.actName = actName
	local actClip = actName ~= "" and G.Clip(actName, st.hostId) or nil
	if not (actClip and actClip.loop) then st.actLoopT0 = nil end
	local caim = ent:GetNW2Bool("tif_caim", false)

	local baseName = actClip and ent:GetNW2String("tif_act_base", "") or ""
	local baseClip = baseName ~= "" and G.Clip(baseName, st.hostId) or nil
	st.fullBody = actClip ~= nil and not caim and not baseClip

	st.aim9 = actClip and actClip.aim9 or nil

	local aware = ent:GetTIFAware()
	st.cqbMode = st.vb and ent:GetNW2Bool("tif_cqb", false)

	st.light = st.vb and ent:GetNW2Bool("tif_light", false)
	st.wade = st.vb and ent:GetNW2Int("tif_wade", 0) or 0
	local rgs = st.vb and ent:GetNW2String("tif_rungun", "") or ""
	st.runGun = rgs ~= "" and rgs or nil
	st.handLight = false
	st.alertPosture = st.vb and not st.cqbMode and (aware == 0 or aware == 1 or aware == 4)

	local mwxAct = string.match(actName, "^mwx_(%a+)_")
	local slingAct = st.vb and ((mwxAct == "smoke" or mwxAct == "phone" or mwxAct == "water") or string.find(actName, "_grenade", 1, true) ~= nil
		or string.sub(actName, 1, 4) == "mwg_" or string.sub(actName, 1, 10) == "mwls_help_" or string.sub(actName, 1, 5) == "mwbr_"
		or (string.sub(actName, 1, 8) == "mws_sit_" and string.sub(actName, 1, 11) ~= "mws_sit_gun"))

	local carried = IsValid(st.gun) and (st.gun.tifHold or st.gun.tifFree) and actClip ~= nil and Bd.ClipCarriesGun(actClip)
	st.slung = (slingAct and not carried) or false

	st.hideGun = st.vb and ent:GetNW2Bool("tif_dying", false)

	if st.wasFullBody and not st.fullBody then st.ubFastUntil = now + 0.4 end
	st.wasFullBody = st.fullBody
	st.ubAct = nil
	st.hipWant = 0
	local LT

	local proneAct = actClip and (string.sub(actName, 1, 4) == "mwg_" or actName == "mwp_flash" or string.sub(actName, 1, 8) == "mwp_csta"
		or string.sub(actName, 1, 8) == "mwp_csto" or string.sub(actName, 1, 9) == "mwp_dive_" or string.sub(actName, 1, 9) == "mwp_turn_"
		or string.sub(actName, 1, 12) == "mwz_fire_pr_")
	local PR = (st.vbProne and not proneAct) and legs.prone or nil
	if PR then

		local t0 = ent:GetNW2Float("tif_prone_t", now)
		local tr = st.vbProne == 1 and PR.down or (st.vbProne == 3 and PR.up or nil)
		local PRp = st.pistol and PR.pistol or nil
		if PRp and st.vbProne == 3 and PRp.up then tr = PRp.up end
		local BPd = st.wkind == "lmg" and PR.bipod
		if tr and BPd then
			if st.vbProne == 1 then
				if st.bipodDownT ~= t0 then
					st.bipodDownT = t0
					st.bipodDown = ent:GetTIFMode() == 1 and BPd.into ~= nil
				end
				if st.bipodDown then tr = BPd.into end
			elseif st.vbProne == 3 then
				if st.bipodUpT ~= t0 then
					st.bipodUpT = t0
					st.bipodUp = st.bipod == "set" and BPd.out ~= nil
				end
				if st.bipodUp then tr = BPd.out end
			end
		end
		if tr then
			local span = ((tr == (BPd and BPd.out) or tr == (PRp and PRp.up)) and PR.up) and PR.up.dur or tr.dur
			st.legCycle[tr] = math.Clamp((now - t0) / math.max(0.05, span), 0, 1)
			LT = { [tr] = 1 }
			st.bipod = nil
			if st.bipodDown and st.vbProne == 1 then st.bipodWantT = now end
		else
			LT = {}
			local moveK = PR.crawl and math.Clamp(speed / 12, 0, 1) or 0

			local rs = ent:GetTIFReloadStart()
			local RL = st.pistol and PR.reloadPistol or PR.reload
			local ru = rs > 0 and (now - rs) / math.max(0.3, st.mwReloadTime or 2.2) or 1

			local BP = st.wkind == "lmg" and PR.bipod
			local still = PR.aim and ent:GetTIFMode() == 1 and moveK < 0.5
			if BP then
				local want = still and ru >= 1

				if want then st.bipodWantT = now
				elseif ru >= 1 and moveK < 0.5 and st.bipodWantT and now - st.bipodWantT < Bd.BIPOD_HOLD then want = true end
				if st.bipodDown then
					st.bipodDown = nil
					if want then st.bipod, st.bipodT = "set", now end
				end
				if want and st.bipod ~= "set" then st.bipod, st.bipodT = "set", now
				elseif not want and st.bipod then st.bipod = nil end
			else
				st.bipod = nil
			end
			if RL and ru < 1 and not st.bipod then
				st.legCycle[RL] = math.Clamp(ru, 0, 1)
				st.magClip, st.magU, st.magKey = RL, st.legCycle[RL], rs
				add(LT, RL, 1)
				st.aim9 = nil
			elseif st.bipod == "set" then
				st.aim9 = BP.aim.aim9
				add(LT, BP.aim, 1)
			else

				local AIMc = (PRp and PRp.aim) or PR.aim
				local IDLEc = (PRp and PRp.idle) or PR.idle
				st.aim9 = still and AIMc.aim9 or nil

				local tw = st.proneTw
				if tw and (still or moveK > 0.05 or now - st.proneTwT >= tw.dur) then st.proneTw, tw = nil, nil end
				if not tw and not still and moveK < 0.05 and PR.twitches and now >= (st.proneTwNext or 0) then
					if st.proneTwNext then
						tw = PR.twitches[math.random(#PR.twitches)]
						st.proneTw, st.proneTwT = tw, now
					end
					st.proneTwNext = now + math.Rand(8, 16)
				end
				if tw then
					st.legCycle[tw] = math.Clamp((now - st.proneTwT) / tw.dur, 0, 1)
					add(LT, tw, 1 - moveK)
				else
					add(LT, still and AIMc or IDLEc, 1 - moveK)
				end
				if moveK > 0 then
					if PRp and PRp.crawl8 and math.abs(relAng) < 35 then
						add(LT, PRp.crawl8, moveK)
					else
						local a, b, k = A.PickDir(PR.crawl, relAng)
						add(LT, a, moveK * (1 - k))
						add(LT, b, moveK * k)
					end
				end
			end
		end
		st.fullBody = true
		actClip = nil
	elseif actClip then
		local rate = ent:GetNW2Float("tif_act_rate", 1)
		local t = (now - ent:GetNW2Float("tif_act_t", now)) * math.abs(rate)
		local u
		if actClip.loop and (actClip.speed or 0) < 1 then

			if not st.actLoopT0 then st.actLoopT0 = ent:GetNW2Float("tif_act_t", now) end
			u = ((now - st.actLoopT0) / actClip.dur) % 1
		else
			st.actLoopT0 = nil
			u = actClip.loop and (t / actClip.dur) % 1 or math.Clamp(t / actClip.dur, 0, 1)

			if rate < 0 then u = 1 - u end
		end

		local fixed = ent:GetNW2Float("tif_act_cycle", -1)
		if fixed >= 0 then
			st.cycleSm = st.cycleSm and (st.cycleSm + (fixed - st.cycleSm) * math.min(1, dt * 12)) or fixed
			u = st.cycleSm
		else
			st.cycleSm = nil
		end

		st.actClipCur, st.actU = actClip, u

		if string.find(actName, "reload", 1, true) then
			st.magClip, st.magU, st.magKey = actClip, u, ent:GetNW2Float("tif_act_t", 0)
		end
		if baseClip then
			st.legCycle[baseClip] = ((now + st.loopOffset) / baseClip.dur) % 1
			LT = { [baseClip] = 1 }
			st.ubAct, st.ubActCycle = actClip, u
		else
			st.legCycle[actClip] = u
			LT = { [actClip] = 1 }
		end
		if caim then mode = 1 end
	else

		local legMode = (st.slotsOk == false and st.wset) and 1 or mode
		LT = leg_targets(st, legs, legMode, stance, speed, relAng)
	end

	st.loopStart = st.loopStart or {}
	for clip, t in pairs(LT) do
		if t > 0 and not st.legW[clip] then st.loopStart[clip] = st.idleT end
	end
	settle(st.legW, LT, actClip and LEG_RATE * 1.3 or LEG_RATE, dt)

	for k in pairs(st.legCycle) do
		if not st.legW[k] then st.legCycle[k] = nil end
	end
	for k in pairs(st.loopStart) do
		if not st.legW[k] then st.loopStart[k] = nil end
	end
	local legTop = top(st.legW, #A.LEG_SLOTS, LEG_BUF)
	local dom
	for i = 1, #legTop do
		local c = legTop[i].clip
		if (c.speed or 0) > 1 then dom = c break end
	end
	if dom then
		local h = st.footHand
		if h then
			st.footHand = nil
			if now - h.at < 0.5 then
				st.phase = math_floor(st.phase) + (h.foot == "l" and 0 or 0.5) + h.since * G.StrideRate(dom)
			end
		end
		st.phase = st.phase + dt * G.StrideRate(dom) * math_clamp(speed / math_max(1, dom.speed), 0, 2)
	end
	local total = 0
	for i = 1, #legTop do total = total + legTop[i].w end
	local acc = 0
	st.want0 = nil
	st.legPlay = st.legPlay or {}
	st.legPlayN = 0
	st.speed2d = speed
	local moving = speed > 5
	for i = 1, #A.LEG_SLOTS do
		local slot = A.LEG_SLOTS[i]
		local e = legTop[i]
		if e and total > 0 then
			acc = acc + e.w
			local seq = A.Seq(ent, e.clip, false)
			local cyc = clip_cycle(st, e.clip, moving)
			local lp = st.legPlay[i]
			if not lp then lp = {} st.legPlay[i] = lp end
			st.legPlayN = i
			lp.clip, lp.cycle, lp.w = e.clip, cyc, e.w / total
			write_slot(ent, slot, seq, cyc, e.w / acc)
			if i == 1 then
				st.want0 = seq
				st.mainSeq, st.mainCycle = seq, cyc
			end
		else
			write_slot(ent, slot, nil, 0, 0)
		end
	end

	st.ubCycle = st.ubCycle or {}
	local UT, rate = ub_targets(ent, st, mode, speed, now)
	rate = rate or UB_RATE
	if st.ubFastUntil and now < st.ubFastUntil then rate = math_max(rate, LEG_RATE * 2.5) end
	settle(st.ubW, UT, rate, dt)
	local ubTop = top(st.ubW, #A.UB_SLOTS, UB_BUF)
	local utotal, uacc = 0, 0
	for i = 1, #ubTop do utotal = utotal + ubTop[i].w end
	for i = 1, #A.UB_SLOTS do
		local slot = A.UB_SLOTS[i]
		local e = ubTop[i]
		if e and utotal > 0 then
			uacc = uacc + e.w
			local cyc = st.ubCycle[e.clip]
			if cyc == nil then cyc = clip_cycle(st, e.clip, moving) end
			write_slot(ent, slot, A.Seq(ent, e.clip, true), cyc, i == 1 and math_min(1, utotal) or e.w / uacc)
		else
			write_slot(ent, slot, nil, 0, 0)
		end
	end
	for i = 5, A.SLOTS - 1 do ent:SetLayerWeight(i, IDLE_WEIGHT) end
	recoil_kicks(ent, st, legs, now)

	if not (TIFG_JGUN_UNDRIVEN and TIFG_JGUN_HOLD) and not Bd.WarnedJgun then
		Bd.WarnedJgun = true
		MsgC(Color(255, 120, 80), "[TIF] tif_mw_anims gun tables (zz_jgun.lua) not loaded on this client: guns follow the hand, not the gun bone\n")
	end
	local lj, uj, best, bestW = 0, 0, nil, 0
	local ld, ud = 0, 0
	local bestO
	for idx = 1, #legTop do
		local e = legTop[idx]
		local r, h, i, i2, k = hold_of(e.clip, st.legCycle[e.clip] or clip_cycle(st, e.clip, moving))
		lj = lj + e.w * r
		ld = ld + e.w * clip_driven(e.clip)
		if h and e.w * r > bestW then best, bestW, bestO = h, e.w * r, hold_pos(h, i, i2, k) end
	end
	if total > 0 then lj, ld = lj / total, ld / total end
	local uw = math_min(1, utotal)
	for idx = 1, #ubTop do
		local e = ubTop[idx]
		local r, h, i, i2, k = hold_of(e.clip, st.ubCycle[e.clip])
		uj = uj + e.w * r
		ud = ud + e.w * clip_driven(e.clip)
		if h and e.w * r * 2 > bestW then best, bestW, bestO = h, e.w * r * 2, hold_pos(h, i, i2, k) end
	end
	if utotal > 0 then uj, ud = uj / utotal, ud / utotal end
	st.jgunW = uw * uj + (1 - uw) * lj
	st.jrotW = uw * ud + (1 - uw) * ld
	if best then
		if not best.m then
			local a = best.a
			best.m = Matrix({ { a[1], a[2], a[3], a[4] }, { a[5], a[6], a[7], a[8] }, { a[9], a[10], a[11], a[12] }, { 0, 0, 0, 1 } })
		end
		st.jgunA = best.m
	end
	if bestO then
		local jo = st.jgunO
		if not jo then jo = Vector() st.jgunO = jo end
		jo.x, jo.y, jo.z = bestO.x, bestO.y, bestO.z
	else
		st.jgunO = nil
	end
	st.rikW = 0

	if st.wset then
		local want = mode == 1 and A.PitchPose(st.wset, ent:GetTIFAimPitch()) or 0
		st.pitch = approach(st.pitch, want, 4, dt)
		ent:SetPoseParameter("gtg_aim_pitch", st.pitch)
	end
	ent:SetPoseParameter("gtg_hold_gait", 0)
	if st.vb then

		local a9 = st.aim9
		local yaw = a9 and math.Clamp(ent:GetNW2Float("tif_aim_yaw", 0), -a9.yaw, a9.yaw) or 0
		local pitch = a9 and math.Clamp(ent:GetTIFAimPitch(), -a9.pitch, a9.pitch) or 0
		st.a9y = approach(st.a9y or 0, yaw, 180, dt)
		st.a9p = approach(st.a9p or 0, pitch, 180, dt)
		ent:SetPoseParameter("mw_aim_yaw", st.a9y)
		ent:SetPoseParameter("mw_aim_pitch", st.a9p)
	end
	Bd.Stats.composed = Bd.Stats.composed + 1
end

local function attach(part, ent, force)
	if not IsValid(part) then return end
	if force or part:GetParent() ~= ent then
		part:SetParent(nil)
		part:SetParent(ent)
		part:RemoveEffects(EF_BONEMERGE)
		part:AddEffects(EF_BONEMERGE)
		part:AddEffects(EF_BONEMERGE_FASTCULL)
		part:SetLocalPos(vector_origin)
		part:SetLocalAngles(angle_zero)
		Bd.Stats.reattached = (Bd.Stats.reattached or 0) + 1
	end
end

local PRONE_SEQ = { [1] = "pronedown_stand", [3] = "proneup_stand" }
local PRONE_IDLE, PRONE_CRAWL = "prone_ar2", "prone_walktwohand"
local R_HAND, PH_HAND = "ValveBiped.Bip01_R_Hand", "PH_R_Hand"

local function measure_gun_offset(ent, st)
	if st.gunOff or not IsValid(st.gun) or st.idleT < 0.5 then return end
	local f = st.follower
	local pb = ent:LookupBone(PH_HAND)
	local pm = pb and ent:GetBoneMatrix(pb)
	local hm
	if IsValid(f) then
		local fb = f:LookupBone(R_HAND)
		hm = fb and f:GetBoneMatrix(fb)
	else
		local rb = ent:LookupBone(R_HAND)
		hm = rb and ent:GetBoneMatrix(rb)
	end
	if not (hm and pm) then return end
	local p, a = WorldToLocal(pm:GetTranslation(), pm:GetAngles(), hm:GetTranslation(), hm:GetAngles())

	if p:Length() > 20 then return end
	st.gunOff = { pos = p, ang = a }
end

local GRIP_IN = 3.2
local gunInfo = {}
local function gun_info(model)
	local gi = gunInfo[model]
	if gi ~= nil then return gi or nil end
	gi = false
	local e = ClientsideModel(model, RENDERGROUP_OTHER)
	if IsValid(e) then
		e:SetNoDraw(true)
		e:SetPos(vector_origin)
		e:SetAngles(angle_zero)
		e:SetupBones()
		local b = e:LookupBone(PH_HAND) or e:LookupBone(R_HAND)
		local bm = b and e:GetBoneMatrix(b)
		local grip = bm and bm:GetTranslation() or Vector()
		local at
		for _, n in ipairs(MUZZLES) do
			local i = e:LookupAttachment(n)
			if i and i > 0 then at = e:GetAttachment(i) break end
		end

		local mins, maxs = e:GetModelBounds()
		local ext = maxs - mins
		local barrel = (ext.x >= ext.y and ext.x >= ext.z) and Vector(1, 0, 0)
			or ((ext.y >= ext.z) and Vector(0, 1, 0) or Vector(0, 0, 1))
		if at and (at.Pos - grip):Dot(barrel) < 0 then barrel = -barrel end
		local c = (mins + maxs) * 0.5 - grip
		local up = c - barrel * c:Dot(barrel)
		if up:LengthSqr() < 0.25 then up = Vector(0, 0, 1) - barrel * barrel.z end

		local function att(name)
			local i = e:LookupAttachment(name)
			return i and i > 0 and e:GetAttachment(i) or nil
		end
		local gr, ab, au = att("grip_r"), att("tif_axis_b"), att("tif_axis_u")
		if gr then grip = gr.Pos end
		if at and ab and au then
			barrel = at.Pos - ab.Pos
			barrel:Normalize()
			up = au.Pos - at.Pos
			up = up - barrel * up:Dot(barrel)
		end
		up:Normalize()
		local m = Matrix()
		m:SetForward(barrel)
		m:SetRight(-up:Cross(barrel))
		m:SetUp(up)
		local gl, gv = att("grip_l"), att("grip_v")
		local mn, mx = e:GetModelBounds()
		gi = { grip = grip, inv = m:GetInverseTR(), gripL = gl and gl.Pos or nil, gripV = gv and gv.Pos or nil,

			barrel = barrel, up = up, length = (mx - mn):Length() }
		e:Remove()
	end
	gunInfo[model] = gi
	return gi or nil
end
Bd.GunInfo = gun_info

local UNTURN = Matrix({ { 0, 1, 0, 0 }, { -1, 0, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } })
local KR = Matrix({ { 0.9966, -0.0653, 0.0500, 0 }, { -0.0672, -0.9970, 0.0374, 0 }, { 0.0474, -0.0406, -0.9981, 0 },
	{ 0, 0, 0, 1 } })
local KR_UNTURN = KR * UNTURN

local rHandOf, jGunOf = {}, {}
local function cached_bone(cache, ent, name)
	local mdl = ent:GetModel()
	local b = cache[mdl]
	if b == nil then
		b = ent:LookupBone(name) or false
		cache[mdl] = b
	end
	return b or nil
end

local GUN_M = Matrix()
local GUN_OFF = Vector()
local BONE_RM, BONE_JM, BONE_MUZ = Matrix(), Matrix(), Matrix()
local CopyBone = TIF.CopyBone

local function gun_pose(st, src, gi)
	local rb = cached_bone(rHandOf, src, R_HAND)
	local rm = gi and rb and CopyBone(src, rb, BONE_RM)
	if not rm then return nil end
	local baked = IsValid(st.gun) and (st.gun.tifHold or st.gun.tifFree)
	if baked then
		local hp = rm:GetTranslation()
		local ha = (rm * UNTURN):GetAngles()
		local rw = st.pistol and 0 or (st.jrotW or 0)
		local jw = st.jgunW or 0
		if rw < 0.001 and jw < 0.001 then return hp, ha end
		local jb = cached_bone(jGunOf, src, "j_gun")
		local jm = jb and CopyBone(src, jb, BONE_JM)
		if not jm then return hp, ha end
		local ga = (jm * KR_UNTURN):GetAngles()
		local ang = rw >= 0.999 and ga or LerpAngle(rw, ha, ga)
		local pos = hp
		if jw > 0.001 then
			local o = st.jgunO
			local rp = o and src:LocalToWorld(o) or (st.jgunA and (jm * st.jgunA):GetTranslation())
			if rp then pos = LerpVector(jw, hp, rp) end
		end
		return pos, ang
	end
	local fwd, right, up = rm:GetForward(), rm:GetRight(), rm:GetUp()
	local grip = rm:GetTranslation() + fwd * GRIP_IN
	local barrel = st.pistol and (fwd * 0.97 - right * 0.24 + up * 0.06) or (fwd * 0.84 + right * 0.49 - up * 0.24)
	barrel:Normalize()
	local wup = -up * 0.99 - fwd * 0.08 - right * 0.12
	wup = wup - barrel * wup:Dot(barrel)
	if wup:LengthSqr() < 0.01 then wup = -up end
	wup:Normalize()
	GUN_M:Identity()
	GUN_M:SetForward(barrel)
	GUN_M:SetRight(-wup:Cross(barrel))
	GUN_M:SetUp(wup)
	local ang = (GUN_M * gi.inv):GetAngles()
	local g = gi.grip
	GUN_OFF.x, GUN_OFF.y, GUN_OFF.z = g.x, g.y, g.z
	GUN_OFF:Rotate(ang)
	return grip - GUN_OFF, ang
end
Bd.GunPose = gun_pose

local function place_gun_vb(st, src)
	local g = st.gun
	if not (IsValid(g) and IsValid(src)) then return end
	local gi = gun_info(g:GetModel())
	local pos, ang = gun_pose(st, src, gi)
	if not pos then return end

	local GH = TIF.GunHold
	if GH and (st.slingW or 0) > 0.001 then
		local sp, sa = GH.SlingPose(src, st, gi)
		if sp then
			local k = st.slingW
			pos = LerpVector(k, pos, sp)
			ang = LerpAngle(k, ang, sa)
		end
	end
	g:SetPos(pos)
	g:SetAngles(ang)
	g:InvalidateBoneCache()
end

local function prone_enter(ent, st)
	if st.proneOn then return end
	st.proneOn = true
	local f, g = st.follower, st.gun
	if IsValid(f) then
		f:RemoveEffects(EF_BONEMERGE)
		f:RemoveEffects(EF_BONEMERGE_FASTCULL)
		local map = f.tifMap
		f.tifSavedMap, f.tifMap = map, nil
		for _, m in ipairs(map and map.MAN or {}) do
			f:ManipulateBoneAngles(m.b, angle_zero)
			f:ManipulateBonePosition(m.b, vector_origin)
		end
		f:SetParent(ent)
		f:SetLocalPos(vector_origin)
		f:SetLocalAngles(angle_zero)
	end
	if IsValid(g) then
		g:RemoveEffects(EF_BONEMERGE)
		g:SetParent(nil)

		g:SetupBones()
		local gb = g:LookupBone(PH_HAND) or g:LookupBone(R_HAND)
		local gm = gb and g:GetBoneMatrix(gb)
		if gm then
			local lp, la = WorldToLocal(gm:GetTranslation(), gm:GetAngles(), g:GetPos(), g:GetAngles())
			local ip, ia = WorldToLocal(vector_origin, angle_zero, lp, la)
			st.gunGripInv = { pos = ip, ang = ia }
		end
	end
end

local function prone_exit(ent, st)
	if not st.proneOn then return end
	st.proneOn = false
	local f = st.follower
	if IsValid(f) then
		f.tifMap = f.tifSavedMap
		for _, m in ipairs(f.tifMap and f.tifMap.MAN or {}) do
			f:ManipulateBoneAngles(m.b, m.angle)
			f:ManipulateBonePosition(m.b, m.vector)
		end

		f:SetPoseParameter("body_pitch", 0)
		f:SetPoseParameter("body_yaw", 0)
		rest_pose(f)
		f:InvalidateBoneCache()
	end
	attach(st.follower, ent, true)
	if not st.vb and not (IsValid(st.gun) and st.gun.tifFree) then attach(st.gun, ent, true) end
end

local function prone_update(ent, st, phase, now)
	local f = st.follower
	if not IsValid(f) then return end
	local t0 = ent:GetNW2Float("tif_prone_t", now)
	local moving = st.vel and st.vel:Length2D() > 5
	local name = PRONE_SEQ[phase] or (moving and PRONE_CRAWL or PRONE_IDLE)
	local seq = f:LookupSequence(name)
	if not seq or seq < 0 then return end
	if f:GetSequence() ~= seq then f:ResetSequence(seq) end
	local dur = math.max(0.05, f:SequenceDuration(seq))
	local cyc = PRONE_SEQ[phase] and math.Clamp((now - t0) / dur, 0, 1) or ((st.idleT % dur) / dur)
	f:SetCycle(cyc)
	f:SetPlaybackRate(0)
	f:SetPoseParameter("body_pitch", math.Clamp(-ent:GetTIFAimPitch(), -10, 50))
	f:SetPoseParameter("body_yaw", 0)
	f:InvalidateBoneCache()
	local g = st.gun

	if st.vb or (IsValid(g) and not (st.gunOff and st.gunGripInv)) then
		f:SetupBones()
		place_gun_vb(st, f)
	elseif IsValid(g) and st.gunOff and st.gunGripInv then
		f:SetupBones()
		local hb = f:LookupBone(R_HAND)
		local hm = hb and f:GetBoneMatrix(hb)
		if hm then
			local gp, ga = LocalToWorld(st.gunOff.pos, st.gunOff.ang, hm:GetTranslation(), hm:GetAngles())
			local op, oa = LocalToWorld(st.gunGripInv.pos, st.gunGripInv.ang, gp, ga)
			g:SetPos(op)
			g:SetAngles(oa)
		end
	end
end

local TILT_MAX = 35
local tiltStart, tiltEnd, tiltOut = Vector(), Vector(), {}
local tiltTrace = { start = tiltStart, endpos = tiltEnd, mask = MASK_SOLID_BRUSHONLY, output = tiltOut }
local function ground_z(x, y, z)
	tiltStart.x, tiltStart.y, tiltStart.z = x, y, z + 30
	tiltEnd.x, tiltEnd.y, tiltEnd.z = x, y, z - 60
	local tr = util.TraceLine(tiltTrace)
	return tr.Hit and tr.HitPos.z or nil
end

local function prone_tilt(ent, st, dt, now, weight, target)
	if weight > 0 and now >= (st.tiltNext or 0) then
		st.tiltNext = now + 0.15
		local pos, yaw = ent:GetPos(), ent:GetAngles().y
		local r = math_rad(yaw)
		local cx, sy = math.cos(r), math.sin(r)
		local zf, zb = ground_z(pos.x + cx * 30, pos.y + sy * 30, pos.z), ground_z(pos.x - cx * 30, pos.y - sy * 30, pos.z)
		local zr, zl = ground_z(pos.x + sy * 12, pos.y - cx * 12, pos.z), ground_z(pos.x - sy * 12, pos.y + cx * 12, pos.z)
		st.tiltWantP = (zf and zb) and math_clamp(math_deg(math_atan2(zb - zf, 60)), -TILT_MAX, TILT_MAX) or 0
		st.tiltWantR = (zr and zl) and math_clamp(math_deg(math_atan2(zl - zr, 24)), -TILT_MAX, TILT_MAX) or 0
	end
	local wp, wr = (st.tiltWantP or 0) * weight, (st.tiltWantR or 0) * weight
	st.tiltP = approach(st.tiltP or 0, wp, 60, dt)
	st.tiltR = approach(st.tiltR or 0, wr, 60, dt)
	local on = math_abs(st.tiltP) > 0.05 or math_abs(st.tiltR) > 0.05
	if target == "host" then
		if on then
			SCRATCH_ANG.p, SCRATCH_ANG.y, SCRATCH_ANG.r = st.tiltP, ent:GetAngles().y, st.tiltR
			ent:SetRenderAngles(SCRATCH_ANG)
			st.tiltOn = true
		elseif st.tiltOn then
			ent:SetRenderAngles(nil)
			st.tiltOn = false
		end
	elseif IsValid(target) then
		SCRATCH_ANG.p, SCRATCH_ANG.y, SCRATCH_ANG.r = st.tiltP, 0, st.tiltR
		target:SetLocalAngles(SCRATCH_ANG)
	end
end

local LOD_PARTS = { "gun", "backGun", "launcherGun", "prop" }
local function hide_placed(st)
	for _, k in ipairs(LOD_PARTS) do
		local e = st[k]
		if IsValid(e) then e:SetNoDraw(true) end
	end
end
Bd.HidePlaced = hide_placed

local function update(ent, st, dt, now)
	Prof.Begin("cl_parts")
	ensure_parts(ent, st)
	Prof.End()
	local dormant = ent:IsDormant()

	local knocked = ent:GetNW2Bool("tif_knocked", false)
	if IsValid(st.follower) then st.follower:SetNoDraw(dormant or knocked) end
	if IsValid(st.gun) then st.gun:SetNoDraw(dormant or knocked) end
	if IsValid(st.backGun) then st.backGun:SetNoDraw(dormant or knocked) end
	if IsValid(st.launcherGun) then st.launcherGun:SetNoDraw(dormant or knocked) end
	if knocked then return end
	if dormant then
		st.wasDormant = true
		return
	end
	local woke = st.wasDormant == true
	st.wasDormant = false
	local prone = ent:GetNW2Int("tif_prone", 0)

	st.vbProne = st.vb and prone > 0 and st.legs and st.legs.prone and prone or nil
	if prone > 0 and not st.vbProne then
		prone_enter(ent, st)
		st.idleT = st.idleT + dt
		local pos = ent:GetPos()
		local vel = st.lastPos and (pos - st.lastPos) / math.max(dt, 0.001) or Vector()
		st.lastPos = pos
		st.vel = vel:LengthSqr() < 640000 and vel or Vector()
		st.want0 = nil
		if woke and IsValid(st.follower) then
			st.follower:SetParent(nil)
			st.follower:SetParent(ent)
			st.follower:SetLocalPos(vector_origin)
			st.follower:SetLocalAngles(angle_zero)
		end
		prone_update(ent, st, prone, now)

		local pt = now - ent:GetNW2Float("tif_prone_t", now)
		local w = prone == 2 and 1 or (prone == 1 and math.Clamp(pt / 1.4, 0, 1) or 1 - math.Clamp(pt / 1.6, 0, 1))
		prone_tilt(ent, st, dt, now, w, st.follower)
		if ent:GetTIFShotTime() ~= st.lastShot then st.lastShot, st.flashAt = ent:GetTIFShotTime(), now end
		return
	end
	if st.proneOn then prone_exit(ent, st) end

	local f = st.follower
	if IsValid(f) and f.tifRestSeq and now >= (st.restCheck or 0) then
		st.restCheck = now + 0.5
		if f:GetSequence() ~= f.tifRestSeq or f:GetCycle() ~= 0 then
			rest_pose(f)
			f:InvalidateBoneCache()
			Bd.Stats.restFixed = (Bd.Stats.restFixed or 0) + 1
		end
	end
	attach(st.follower, ent, woke)
	local freeGun = IsValid(st.gun) and st.gun.tifFree
	if not st.vb and not freeGun then
		attach(st.gun, ent, woke)
		measure_gun_offset(ent, st)
	end
	if woke then

		st.lastPos, st.vel = nil, nil
		st.nextSlotCheck = 0
	end
	local L = Bd.LOD
	local off = st.vb and L.on and not L.OnScreen(ent, st) and not ent:GetNW2Bool("tif_light", false)
	if off then
		st.lodN = (st.lodN or 0) + 1
		if st.lodN < L.every and not woke then
			st.lodDt = (st.lodDt or 0) + dt
			Bd.Stats.lodSkipped = (Bd.Stats.lodSkipped or 0) + 1
			hide_placed(st)
			return
		end
	end
	dt = dt + (st.lodDt or 0)
	st.lodN, st.lodDt = 0, 0
	st.offScreen = off
	ent:SetPlaybackRate(0)
	st.magClip, st.magU, st.magKey = nil, nil, nil
	st.actClipCur, st.actU, st.switchClip, st.switchU = nil, nil, nil, nil
	Prof.Begin("cl_compose")
	compose(ent, st, dt, now)
	Prof.End()

	Prof.Begin("cl_foley")
	if st.vb and TIF.FoleyCL then TIF.FoleyCL.Update(ent, st, now) end
	Prof.End()
	Prof.Begin("cl_pose")
	if not check_slots(ent, st, now) then

		Bd.Stats.missingSlots = Bd.Stats.missingSlots + 1
		if st.mainSeq and st.mainSeq >= 0 then
			ent:SetSequence(st.mainSeq)
			ent:SetCycle(st.mainCycle or 0)
		end
	end
	if st.vb then vb_pose(ent, st, now, dt) else flinch(ent, st, now) end

	if st.vb and (st.vbProne or st.tiltOn) then
		local w = 0
		local PR = st.vbProne and st.legs and st.legs.prone
		if PR then
			local pt = now - ent:GetNW2Float("tif_prone_t", now)
			if st.vbProne == 2 then w = 1
			elseif st.vbProne == 1 then w = math.Clamp(pt / math.max(0.1, PR.down.dur), 0, 1)
			else w = 1 - math.Clamp(pt / math.max(0.1, PR.up.dur), 0, 1) end
		end
		prone_tilt(ent, st, dt, now, w, "host")
	end
	Prof.End()
	st.writeFrame = FrameNumber()
	ent:InvalidateBoneCache()
	if off then
		Bd.Stats.lodOff = (Bd.Stats.lodOff or 0) + 1
		hide_placed(st)
		return
	end
	Prof.Begin("cl_bones")

	if not st.vb and freeGun and IsValid(st.follower) then
		st.follower:SetupBones()
		place_gun_vb(st, st.follower)
	end
	if st.vb and IsValid(st.gun) then
		st.gun:SetNoDraw(st.hideGun == true)

		st.slingW = math.Approach(st.slingW or 0, st.slung and 1 or 0, dt * 3.5)
		if TIF.Feet then TIF.Feet.Prepare(ent, st, now, dt) end
		if TIF.GunHold then TIF.GunHold.Prepare(ent, st, now) end
		ent:SetupBones()
		place_gun_vb(st, ent)
		if TIF.Eyes then TIF.Eyes.Update(ent, st) end

		if TIF.GunMag and not st.hideGun then TIF.GunMag.Update(ent, st) end

		if TIF.GunHold then TIF.GunHold.Post(ent, st) end
	end

	if st.vb and TIF.Props then
		if not (IsValid(st.gun)) then ent:SetupBones() end
		TIF.Props.Update(ent, st, now)
	end
	Prof.End()
end

local cvLOD = CreateClientConVar("tif_anim_lod", "1", true, false, "Soldiers out of view animate cheaply (no bone build, fewer updates)", 0, 1)
local cvLODEvery = CreateClientConVar("tif_anim_lod_every", "4", true, false, "Soldiers out of view update every this many frames", 1, 16)
Bd.LOD = Bd.LOD or {}
local L = Bd.LOD
L.NEAR, L.RADIUS, L.MARGIN, L.OFF_AFTER = 160, 64, 12, 0.3
L.on, L.every = true, 4
L.eye, L.fwd, L.half = Vector(), Vector(1, 0, 0), math.pi
L.view = nil
local LOD_VIEW = { pos = Vector(), fwd = Vector(1, 0, 0), fov = 90, t = 0 }
hook.Add("RenderScene", "tif_body_lod", function(origin, angles, fov)
	LOD_VIEW.pos.x, LOD_VIEW.pos.y, LOD_VIEW.pos.z = origin.x, origin.y, origin.z
	LOD_VIEW.fwd = angles:Forward()
	LOD_VIEW.fov = fov
	LOD_VIEW.t = RealTime()
	L.view = LOD_VIEW
end)
function L.Frame()
	L.on = cvLOD:GetBool()
	L.every = math.max(1, cvLODEvery:GetInt())
	local v = L.view
	if not L.on or not v or RealTime() - v.t > 0.5 then
		L.live = false
		return
	end
	L.live = true
	L.eye, L.fwd = v.pos, v.fwd
	local ply = LocalPlayer()
	local fov = math.max(v.fov or 0, IsValid(ply) and ply.GetFOV and ply:GetFOV() or 0)
	if fov <= 0 then fov = 90 end
	local aspect = ScrW() / math.max(1, ScrH())
	local th = math.tan(math.rad(math.min(fov, 170)) / 2) * aspect * 0.75
	local tv = th / aspect
	L.half = math.atan(math.sqrt(th * th + tv * tv)) + math.rad(L.MARGIN)
end
local function in_cone(ent)
	local d = ent:WorldSpaceCenter() - L.eye
	local dist2 = d.x * d.x + d.y * d.y + d.z * d.z
	if dist2 < L.NEAR * L.NEAR then return true end
	local dist = math.sqrt(dist2)
	local a = L.half + math.asin(math.min(1, L.RADIUS / dist))
	if a >= math.pi then return true end
	return d:Dot(L.fwd) >= dist * math.cos(a)
end
function L.OnScreen(ent, st)
	if not L.live then return true end
	if in_cone(ent) then
		if st then st.lodOutT = nil end
		return true
	end
	if not st then return false end
	local now = RealTime()
	st.lodOutT = st.lodOutT or now
	return now - st.lodOutT < L.OFF_AFTER
end

hook.Add("PreRender", "tif_body", function()
	if next(States) == nil then return end
	Prof.Begin("cl_anim")
	L.Frame()
	local dt, now = FrameTime(), CurTime()
	local n, missing = 0, 0
	for ent, st in pairs(States) do
		if IsValid(ent) then
			n = n + 1
			local ok, err = xpcall(update, debug.traceback, ent, st, dt, now)
			if not ok then

				st.lastErr, st.lastErrAt = tostring(err), now
				if not st.errored then
					st.errored = true
					TIF.Error("Soldier animation error: ", tostring(err))
				end
			end
			if st.slotsOk == false and not ent:IsDormant() then missing = missing + 1 end
		end
	end
	Bd.Stats.soldiers = n
	Bd.Stats.missingNow = missing
	Prof.End()
end)

function Bd.DrawHost(ent, flags)
	local st = States[ent]

	if not st then Bd.Add(ent) end
	if st and IsValid(st.follower) then return end
	ent:DrawModel(flags)
end

local muzzleOf = {}
local function muzzle_local(model)
	local m = muzzleOf[model]
	if m ~= nil then return m or nil end
	m = false
	local e = ClientsideModel(model, RENDERGROUP_OTHER)
	if IsValid(e) then
		e:SetNoDraw(true)
		e:SetPos(vector_origin)
		e:SetAngles(angle_zero)
		e:SetupBones()
		local a
		for _, n in ipairs(MUZZLES) do
			local i = e:LookupAttachment(n)
			if i and i > 0 then a = i break end
		end
		local b = e:LookupBone(PH_HAND) or e:LookupBone(R_HAND) or 0
		local at = a and e:GetAttachment(a)
		local bm = at and e:GetBoneMatrix(b)
		if bm then
			local p, ang = WorldToLocal(at.Pos, at.Ang, bm:GetTranslation(), bm:GetAngles())
			m = { bone = e:GetBoneName(b), boneIdx = b, pos = p, ang = ang }
		end
		e:Remove()
	end
	muzzleOf[model] = m
	return m or nil
end

local function muzzle_world_pa(g)
	local m = muzzle_local(g:GetModel())
	if not m then return nil end
	local bm = m.boneIdx and CopyBone(g, m.boneIdx, BONE_MUZ)
	if not bm then return nil end
	return LocalToWorld(m.pos, m.ang, bm:GetTranslation(), bm:GetAngles())
end

function Bd.MuzzleWorld(ent)
	local st = States[ent]
	if not st or st.offScreen or not IsValid(st.gun) or ent:IsDormant() then return nil end
	local p, a = muzzle_world_pa(st.gun)
	return p and { Pos = p, Ang = a } or nil
end

hook.Add("PostDrawTranslucentRenderables", "tif_body_flash", function(depth, sky)
	if sky or next(States) == nil then return end
	local now = CurTime()
	for ent, st in pairs(States) do
		if st.flashAt and not st.offScreen and now - st.flashAt < FLASH_TIME and IsValid(st.gun) and IsValid(ent) and not ent:IsDormant() then
			local pos, ang = muzzle_world_pa(st.gun)
			if pos then
				local s = math.Rand(10, 16)
				render.SetMaterial(FLASH_MAT)
				render.DrawSprite(pos + ang:Forward() * 3, s, s, color_white)
				render.SetMaterial(GLOW_MAT)
				render.DrawSprite(pos, s * 2.2, s * 2.2, FLASH_GLOW_COL)
				if st.lightAt ~= st.flashAt then
					st.lightAt = st.flashAt
					local dl = DynamicLight(ent:EntIndex())
					if dl then
						dl.pos, dl.r, dl.g, dl.b = pos, 255, 190, 110
						dl.brightness, dl.decay, dl.size, dl.dietime = 2, 3000, 160, now + 0.05
					end
				end
			end
		end
	end
end)

local pending = {}
local function hide(self) end

hook.Add("OnEntityCreated", "tif_body_corpse", function(ent)
	if IsValid(ent) and ent:GetClass() == "prop_ragdoll" then pending[ent] = RealTime() + 3 end
end)

local function dress_corpse(rag)
	local vis = rag:GetNW2String("tif_vis", "")
	if vis == "" then return false end
	vis = (Bd.VisAlt and Bd.VisAlt[vis]) or vis

	local vb = rag:GetNW2Bool("tif_vb_dress", false) and not (TIF.Modular and TIF.Modular.NeedsRetarget(vis))
	if not vb and not cvRetarget:GetBool() then return true end
	local f = make_follower(rag, vis, rag:GetNW2Int("tif_skin", 0), rag:GetNW2String("tif_bg", ""), vb)
	if f then
		rag.RenderOverride = hide
		Bd.Rags[#Bd.Rags + 1] = { ent = f, rag = rag }
	end
	return true
end

hook.Add("Think", "tif_body_corpse", function()
	if next(pending) ~= nil then
		local now = RealTime()
		for rag, deadline in pairs(pending) do
			if not IsValid(rag) or now > deadline or dress_corpse(rag) then pending[rag] = nil end
		end
	end
end)

timer.Create("tif_body_rags", 0.25, 0, function()
	for i = #Bd.Rags, 1, -1 do
		local r = Bd.Rags[i]
		if not IsValid(r.ent) or not IsValid(r.rag) then
			if IsValid(r.ent) then r.ent:Remove() end
			table.remove(Bd.Rags, i)
		else
			local dormant = r.rag:IsDormant()
			r.ent:SetNoDraw(dormant)
			if not dormant and (r.wasDormant or r.ent:GetParent() ~= r.rag) then attach(r.ent, r.rag, true) end
			r.wasDormant = dormant
		end
	end
end)

for _, class in ipairs({ "tif_soldier", "tif_soldier_militia", "tif_soldier_pmc" }) do
	killicon.AddAlias(class, "weapon_ar2")
end

concommand.Add("tif_cl_reset_bodies", function()
	for _, st in pairs(States) do
		remove_parts(st)
		st.vis, st.wclass = nil, nil
	end
end, nil, "Rebuild every soldier's faction model and gun")
