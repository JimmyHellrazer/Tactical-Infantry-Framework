local TIF = TIF
local Act = TIF.Action
local Cover = TIF.Cover
local Move = TIF.Move
local Weapon = TIF.Weapon
local A = TIF.Anim
local Prof = TIF.Prof

TIF.CoverBehave = TIF.CoverBehave or {}
local CB = TIF.CoverBehave

local UP40 = Vector(0, 0, 40)
local ENTER_VARIANTS = { "0-5m_00", "0-5m_180", "0-5m_-180", "faceleft", "faceright" }
local STILL_GOOD_EVERY = 1.5

local function yaw_dir(yaw)
	local r = math.rad(yaw)
	return Vector(math.cos(r), math.sin(r), 0)
end

local function face_yaw(cov)
	return cov.side == "l" and cov.ny - 90 or cov.ny + 90
end

local function prefixes(npc)
	local def = npc.tifWep and npc.tifWep.def
	local set = def and istable(def.cover) and def.cover.set or "cw2_"
	if set == "cw1_" then return "cov_", "cw1_" end

	return "cov2_", "cw2_"
end

local function clip_name(npc, candidates)
	for _, n in ipairs(candidates) do
		if Act.Clip(npc, n) then return n end
	end

	return nil
end

local function names(npc, cov, kind)
	local P, W = prefixes(npc)
	local h = cov.high and "high" or "low"
	local hw = cov.high and "hi" or "low"
	local s = cov.side

	if kind == "idle" then
		return { P .. h .. "_idle_" .. s, "cov2_" .. h .. "_idle_" .. s }
	end

	if kind == "peek" then
		return { P .. h .. "_idle_" .. s .. "_peek", "cov2_" .. h .. "_idle_" .. s .. "_peek" }
	end

	if kind == "intro" then
		local tail = cov.high and "_corner_long" or "_centre_long"
		return { W .. "intro_" .. hw .. "_" .. s .. tail, "cw2_intro_" .. hw .. "_" .. s .. tail }
	end

	if kind == "outro" then
		local tail = cov.high and "_corner_long" or "_centre_long"
		return { W .. "outro_" .. hw .. "_" .. s .. tail, "cw2_outro_" .. hw .. "_" .. s .. tail }
	end

	if kind == "reload" then
		return { W .. h .. "_reload", "cw2_" .. h .. "_reload" }
	end

	if kind == "switch" then
		local o = s == "l" and "r" or "l"
		return { P .. h .. "_" .. s .. "_to_" .. h .. "_" .. o, "cov2_" .. h .. "_" .. s .. "_to_" .. h .. "_" .. o }
	end

	if kind == "blind_in" then
		local v = cov.high and "_enter_hi" or "_enter_45"
		return { W .. "blindfire_" .. hw .. "_" .. s .. v, "cw2_blindfire_" .. hw .. "_" .. s .. v }
	end

	if kind == "blind" then
		return { W .. "blindfire_" .. hw .. "_" .. s .. "_aim_med", "cw2_blindfire_" .. hw .. "_" .. s .. "_aim_med" }
	end

	if kind == "blind_out" then
		return { W .. "blindfire_" .. hw .. "_" .. s .. "_exit", "cw2_blindfire_" .. hw .. "_" .. s .. "_exit" }
	end

	return {}
end

local function pick_side(pt, threat)
	local dir = threat - pt.pos
	dir.z = 0
	dir:Normalize()
	local l = yaw_dir(pt.ny - 90):Dot(dir) >= yaw_dir(pt.ny + 90):Dot(dir)
	local side = l and "l" or "r"

	if pt.high then
		if pt.shootFrom == "l" or pt.shootFrom == "r" then return pt.shootFrom end
		if side == "l" and not pt.edgeL and pt.edgeR then return "r" end
		if side == "r" and not pt.edgeR and pt.edgeL then return "l" end
	end

	return side
end

local cvDebug
local function dlog(npc, ...)
	cvDebug = cvDebug or GetConVar("tif_debug")

	if cvDebug and cvDebug:GetBool() then
		TIF.Log("[cover] #", npc:EntIndex(), " ", table.concat({ ... }, ""))
	end
end

CB.Log = dlog

local function set_phase(npc, cov, phase, now)
	if cov.phase ~= phase then
		dlog(npc, cov.phase or "-", " -> ", phase, cov.high and " (high " or " (low ", cov.side or "?", ")")
	end

	cov.phase, cov.t0 = phase, now
	npc.tifAction = "cover: " .. phase
end

local function caim(npc, on)
	if npc:GetNW2Bool("tif_caim", false) ~= on then
		npc:SetNW2Bool("tif_caim", on)
	end
end

function CB.In(npc)
	return npc.tifCov ~= nil
end

function CB.Leave(npc, reason)
	local cov = npc.tifCov
	if not cov then return end

	dlog(npc, "left cover (", tostring(reason), ") in phase ", tostring(cov.phase))

	local settled = { idle = true, look = true, twitch = true }
	if cov.mw and cov.origin and settled[cov.phase] then
		npc.tifLastCov = { origin = cov.origin, ny = cov.ny, t = cov.t, hy = cov.hy, time = CurTime() }
	end

	if (reason == "exposed" or reason == "flanked") and cov.pt and cov.pt.key then
		Cover.Cache[cov.pt.key] = nil
	end

	Act.Clear(npc)
	Cover.Release(npc)
	caim(npc, false)
	npc.tifCov = nil
	npc.tifBlind = false

	npc.tifAimAt, npc.tifAimFree, npc.tifMuzzle = nil, nil, nil

	if npc:GetNW2Float("tif_aim_yaw", 0) ~= 0 then
		npc:SetNW2Float("tif_aim_yaw", 0)
	end

	npc.tifHitboxPose = nil
	npc.tifCoverLeftAt = CurTime()
	npc.tifCoverLeaveReason = reason
end

function CB.Exit(npc, reason)
	local cov = npc.tifCov
	if not cov then return false end
	if cov.mw and CB.MW then return CB.MW.Exit(npc, reason) end

	local now = CurTime()
	if cov.phase == "exit" then
		if now >= cov.phaseEnd then
			CB.Leave(npc, cov.exitReason)
			return false
		end

		return true
	end

	if cov.phase ~= "idle" and cov.phase ~= "peek" then
		CB.Leave(npc, reason)
		return false
	end

	local P = prefixes(npc)
	local h = cov.high and "high" or "low"
	local n = clip_name(npc, { P .. "exit_" .. h .. "_" .. cov.side .. "_0-5m_00", "cov2_exit_" .. h .. "_" .. cov.side .. "_0-5m_00" })
	local dur = n and Act.Play(npc, n, { root = true })

	if not dur then
		CB.Leave(npc, reason)
		return false
	end

	caim(npc, false)
	cov.exitReason = reason
	cov.phaseEnd = now + dur
	set_phase(npc, cov, "exit", now)
	return true
end

local function want_cover(npc, now)
	local arch = npc.tifArch
	local supp = npc.tifSupp or 0

	if now > (npc.tifCoverRollAt or 0) then
		npc.tifCoverRollAt = now + math.Rand(5, 9)
		npc.tifCoverRoll = math.random()
		dlog(npc, string.format("wants cover: %s (roll %.2f vs %.2f)", tostring(npc.tifCoverRoll < arch.coverUse + supp * 0.5),
			npc.tifCoverRoll, arch.coverUse + supp * 0.5))
	end

	return (npc.tifCoverRoll or 1) < arch.coverUse + supp * 0.5
end

CB.SetPhase, CB.Caim, CB.PickSide, CB.WantCover = set_phase, caim, pick_side, want_cover

local function has_cover_clips(npc)
	if CB.MW and CB.MW.Use(npc) then return true end

	if npc.tifHasCoverClips == nil then
		local P, W = prefixes(npc)
		npc.tifHasCoverClips = (Act.Clip(npc, P .. "high_idle_l") or Act.Clip(npc, "cov2_high_idle_l")) ~= nil
			and (Act.Clip(npc, W .. "intro_low_l_centre_long") or Act.Clip(npc, "cw2_intro_low_l_centre_long")) ~= nil
	end

	return npc.tifHasCoverClips
end

function CB.Seek(npc, threat, now, opts)
	if now < (npc.tifNextCoverSearch or 0) or not has_cover_clips(npc) then
		return false
	end

	if not TIF.Budget.Take("cover_search", 1) then return false end

	npc.tifNextCoverSearch = now + math.Rand(2.5, 4)
	local avoid = {}

	for _, b in ipairs(npc.tifBadCover or {}) do
		if now - b.time < 30 then
			avoid[#avoid + 1] = b.pos
		end
	end

	opts = opts or { radius = 650, maxTravel = 900 }
	opts.avoid = avoid

	if npc.tifRole == "maneuver" and npc.tifCoverCenter then
		opts.center, opts.radius, opts.maxTravel = npc.tifCoverCenter, 380, 1600
	end

	local leashC, leashR = TIF.Squad.Leash(npc)
	if leashC and npc:GetPos():DistToSqr(leashC) > (leashR * 0.6) ^ 2 then
		opts.center = leashC
	end

	local pt, stats = Cover.Find(npc, threat, opts)
	if pt and leashC and pt.pos:DistToSqr(leashC) > leashR * leashR then
		pt = nil
		stats.outsideLeash = (stats.outsideLeash or 0) + 1
	end

	npc.tifCoverStats = stats
	npc.tifCoverSearchFailed = pt == nil or (pt.score or -99) < -2.5
	local parts = {}

	for k, v in SortedPairs(stats or {}) do
		parts[#parts + 1] = k .. "=" .. tostring(v)
	end

	dlog(npc, "search: ", table.concat(parts, " "), pt and string.format(" -> best %.1f %s %s", pt.score or -99,
		pt.high and "high" or "low", pt.canShoot and "shoot" or "hide") or " -> nothing")
	if npc.tifCoverSearchFailed then return false end

	Cover.Reserve(pt, npc)
	npc.tifCov = { pt = pt, origin = pt.pos, ny = pt.ny, high = pt.high, side = pick_side(pt, threat), canShoot = pt.canShoot }

	if CB.MW and CB.MW.Use(npc) then
		CB.MW.Prepare(npc, npc.tifCov)
	end

	set_phase(npc, npc.tifCov, "move", now)
	TIF.Say(npc, (npc.tifSupp or 0) > 0.4 and "cover_me" or "moving", 0.35)
	return true
end

local function start_idle(npc, cov, now)
	set_phase(npc, cov, "idle", now)
	local n = clip_name(npc, names(npc, cov, "idle"))

	if n then
		Act.Loop(npc, n)
	end

	local p = npc.tifArch.coverPause

	local roleK = npc.tifRole == "base" and 0.6 or 1
	cov.nextAim = now + math.Rand(p[1], p[2]) * roleK * (1 + (npc.tifSupp or 0) * 1.5)
end

local function snap_home(npc, cov)
	npc:SetPos(cov.origin)
	npc:SetAngles(Angle(0, face_yaw(cov), 0))
end

function CB.Update(npc, c, now)
	local cov = npc.tifCov
	local f = npc.tifFire

	if not cov then
		if not c or not want_cover(npc, now) then return false end
		if not CB.Seek(npc, c.pos, now) then return false end

		cov = npc.tifCov
	end

	if cov.mw and CB.MW then return CB.MW.Update(npc, c, now) end

	Prof.Begin("cover_behave")
	local arch = npc.tifArch
	local supp = npc.tifSupp or 0
	local lost = c and (now - math.max(c.seenAt, c.heardAt)) or 99
	local face = face_yaw(cov)
	npc.tifMode = A.MODE_AIM
	f.want = false
	npc.tifBlind = false
	local phase = cov.phase

	if npc.tifRole == "maneuver" and npc.tifCoverCenter and cov.origin:DistToSqr(npc.tifCoverCenter) > 360 * 360
		and (phase == "idle" or phase == "peek" or phase == "aim" or phase == "move") then
		CB.Leave(npc, "maneuver")
		npc.tifNextCoverSearch = 0
		Prof.End()
		return CB.Update(npc, c, now)
	end

	if phase == "exit" then
		if now >= cov.phaseEnd then
			CB.Leave(npc, cov.exitReason)
			Prof.End()
			return false
		end

		Prof.End()
		return true
	end

	if phase == "move" then
		npc.tifStance = A.STANCE_STAND
		npc.tifHitboxPose = nil
		local m = npc.tifMove

		if c and c.visible then
			npc.tifFace = c.ent:WorldSpaceCenter()

			if arch.aggression > 0.5 then
				f.want, f.aimPos = true, c.ent:WorldSpaceCenter()
			end
		else
			npc.tifFace = nil
		end

		local d2 = npc:GetPos():DistToSqr(cov.origin)
		local pathDone = m.goal == nil and m.result == "arrived" and d2 < 64 * 64

		if d2 < 40 * 40 or pathDone then
			Move.Stop(npc)
			npc.tifFace = nil

			local need = math.AngleDifference(face, npc:GetAngles().y)
			local P = prefixes(npc)
			local best, bestErr

			for _, v in ipairs(ENTER_VARIANTS) do
				local n = P .. "enter_" .. (cov.high and "high" or "low") .. "_" .. cov.side .. "_" .. v
				local clip = Act.Clip(npc, n)

				if clip then
					local err = math.abs(need - (clip.move and clip.move[3] or 0))
					if not bestErr or err < bestErr then
						best, bestErr = n, err
					end
				end
			end

			cov.phaseEnd = now + (best and Act.Play(npc, best, { to = { pos = cov.origin, yaw = face }, rate = 1.15 }) or 0)
			set_phase(npc, cov, "enter", now)
		else
			local accepted = Move.SetGoal(npc, cov.origin, Move.CombatGait(npc, cov.origin), "cover")
			local failed = m.goal == nil and (m.result == "fail" or m.result == "stuck" or m.result == "timeout")

			if not accepted or failed then
				npc.tifBadCover = npc.tifBadCover or {}
				table.insert(npc.tifBadCover, { pos = cov.origin, time = now })

				if #npc.tifBadCover > 8 then
					table.remove(npc.tifBadCover, 1)
				end

				CB.Leave(npc, accepted and ("path " .. tostring(m.result)) or "goal off navmesh or failed recently")
				Prof.End()
				return false
			end
		end
	elseif phase == "enter" then
		npc.tifStance = cov.high and A.STANCE_STAND or A.STANCE_CROUCH

		if now >= cov.phaseEnd then
			snap_home(npc, cov)
			start_idle(npc, cov, now)
		end
	elseif phase == "idle" or phase == "peek" then
		npc.tifFace = nil
		npc.tifStance = cov.high and A.STANCE_STAND or A.STANCE_CROUCH
		npc.tifHitboxPose = cov.high and "aim" or "crouch"
		local threat = c and c.pos

		if threat and now > (cov.nextCheck or 0) then
			cov.nextCheck = now + STILL_GOOD_EVERY
			local ok, why = Cover.StillGood(cov.pt, threat)

			if not ok then
				CB.Leave(npc, why)
				npc.tifNextCoverSearch = 0
				Prof.End()
				return false
			end
		end

		local w = npc.tifWep
		if w and w.ammo < w.clip * 0.35 and not Weapon.Reloading(npc) then
			local n = clip_name(npc, names(npc, cov, "reload"))
			if n then
				cov.phaseEnd = now + (Act.Play(npc, n, { to = { pos = cov.origin, yaw = face },
					base = clip_name(npc, names(npc, cov, "idle")) }) or 2)
				Weapon.StartReload(npc)
				set_phase(npc, cov, "reload", now)
				Prof.End()
				return true
			end
		end

		if threat then
			local want = pick_side(cov.pt, threat)
			local edgeOk = not cov.high or (want == "l" and cov.pt.edgeL) or (want == "r" and cov.pt.edgeR)

			if want ~= cov.side and edgeOk and now - cov.t0 > 1.5 then
				local n = clip_name(npc, names(npc, cov, "switch"))
				if n then
					cov.phaseEnd = now + (Act.Play(npc, n, { root = true }) or 1)
					cov.switchTo = want
					set_phase(npc, cov, "switch", now)
					Prof.End()
					return true
				end

				cov.side = want
			end
		end

		if c and now >= (cov.nextAim or 0) and lost < arch.loseContact + 4 then
			local canPop = cov.canShoot or not cov.high
			if supp > 0.55 and arch.aggression >= 0.3 then
				local n = clip_name(npc, names(npc, cov, "blind_in"))
				if n then
					cov.phaseEnd = now + (Act.Play(npc, n) or 0.3)
					set_phase(npc, cov, "blind_in", now)
					Prof.End()
					return true
				end
			elseif canPop and supp < 0.7 then
				local n = clip_name(npc, names(npc, cov, "intro"))
				if n then
					cov.phaseEnd = now + (Act.Play(npc, n, { root = true }) or 0.4)
					caim(npc, false)
					set_phase(npc, cov, "aim_in", now)
					Prof.End()
					return true
				end
			end

			cov.nextAim = now + 1.5
		end

		local wantPeek = c and not c.visible and lost < arch.loseContact + 4
		if wantPeek and not cov.high then
			if now > (cov.peekUntil or 0) and now > (cov.nextPeek or 0) then
				cov.peekUntil = now + math.Rand(0.8, 1.3)
				cov.nextPeek = cov.peekUntil + math.Rand(3, 5)
			end

			wantPeek = now < (cov.peekUntil or 0)
		end

		local idleName = clip_name(npc, names(npc, cov, "idle"))
		local loopName = wantPeek and clip_name(npc, names(npc, cov, "peek")) or idleName

		if loopName then
			Act.Loop(npc, loopName, loopName ~= idleName and { base = idleName } or nil)
		end

		cov.phase = wantPeek and "peek" or "idle"
		npc.tifAction = "cover: " .. cov.phase
	elseif phase == "aim_in" then
		npc.tifStance = A.STANCE_STAND
		npc.tifHitboxPose = "aim"

		if now >= cov.phaseEnd then
			local b = arch.coverBurst
			cov.aimUntil = now + math.Rand(b[1], b[2]) * (1 - 0.5 * supp)
			caim(npc, true)
			set_phase(npc, cov, "aim", now)
		end
	elseif phase == "aim" then
		npc.tifStance = A.STANCE_STAND
		npc.tifHitboxPose = "aim"

		if c and c.visible then
			local aim = c.ent:WorldSpaceCenter() + Vector(0, 0, 6)
			npc.tifFace, f.want, f.aimPos, f.target = aim, true, aim, c.ent
		elseif c and (lost < 1 or (npc.tifRole == "base" and lost < 6)) then
			npc.tifFace, f.want, f.aimPos = c.pos + UP40, true, c.pos + UP40

			if lost >= 1 and not cov.saidSuppress then
				cov.saidSuppress = true
				TIF.Say(npc, "suppressing", 0.5)
			end
		elseif c then
			npc.tifFace = c.pos + UP40
		end

		local maxLost = npc.tifRole == "base" and 6 or 1.5
		if now > cov.aimUntil or supp > 0.75 or not c or lost > maxLost then
			cov.saidSuppress = nil
			npc.tifFace = nil
			f.want = false
			local n = clip_name(npc, names(npc, cov, "outro"))
			cov.phaseEnd = now + (n and Act.Play(npc, n, { root = true }) or 0)
			caim(npc, false)
			set_phase(npc, cov, "aim_out", now)
		end
	elseif phase == "aim_out" then
		npc.tifStance = A.STANCE_STAND

		if now >= cov.phaseEnd then
			snap_home(npc, cov)
			start_idle(npc, cov, now)
		end
	elseif phase == "reload" then
		npc.tifStance = cov.high and A.STANCE_STAND or A.STANCE_CROUCH

		if now >= cov.phaseEnd and not Weapon.Reloading(npc) then
			start_idle(npc, cov, now)
		end
	elseif phase == "switch" then
		if now >= cov.phaseEnd then
			cov.side = cov.switchTo or (cov.side == "l" and "r" or "l")
			cov.origin = npc:GetPos()
			npc:SetAngles(Angle(0, face_yaw(cov), 0))
			start_idle(npc, cov, now)
		end
	elseif phase == "blind_in" then
		if now >= cov.phaseEnd then
			cov.blindUntil = now + math.Rand(1, 2)
			set_phase(npc, cov, "blind", now)
		end
	elseif phase == "blind" then
		npc.tifBlind = true

		if c then
			f.want, f.aimPos = true, c.pos + UP40
		end

		local n = clip_name(npc, names(npc, cov, "blind"))
		if n then
			Act.Loop(npc, n)
		end

		if now > cov.blindUntil or not c then
			npc.tifBlind = false
			f.want = false
			local o = clip_name(npc, names(npc, cov, "blind_out"))
			cov.phaseEnd = now + (o and Act.Play(npc, o) or 0)
			set_phase(npc, cov, "blind_out", now)
		end
	elseif phase == "blind_out" then
		if now >= cov.phaseEnd then
			start_idle(npc, cov, now)
		end
	end

	Prof.End()
	return true
end
