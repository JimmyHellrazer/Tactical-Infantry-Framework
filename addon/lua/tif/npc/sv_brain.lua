local TIF = TIF
local AW = TIF.AWARE
local Per = TIF.Perception
local Move = TIF.Move
local Weapon = TIF.Weapon
local A = TIF.Anim
local Prof = TIF.Prof
local Act = TIF.Action

TIF.Brain = TIF.Brain or {}
local B = TIF.Brain

local SUSPICIOUS_TIMEOUT = 20
local ALERTED_TIMEOUT = 30
local HEIGHTENED_TIME = 90
local UP40 = Vector(0, 0, 40)
local UP60 = Vector(0, 0, 60)
local HEAD_OFF = Vector(0, 0, 3)
local CHEST_OFF = Vector(0, 0, 6)
local SEC_OPT = { secondary = true }

function B.Init(npc)
	npc.tifAware = AW.UNAWARE
	npc.tifAwareSince = CurTime()
	npc.tifAction = "duty"
	npc.tifStance = A.STANCE_STAND
	npc.tifMode = A.MODE_RELAXED
end

local function set_aware(npc, st, now)
	if npc.tifAware == st then return end

	local old = npc.tifAware
	npc.tifAware = st
	npc.tifAwareSince = now
	npc:SetTIFAware(st)

	if TIF.PassiveMW then
		TIF.PassiveMW.OnAware(npc, old, st, now)
	end
end

local function look_random(npc, around, spread, now)
	if now < (npc.tifNextLook or 0) then return end

	npc.tifNextLook = now + math.Rand(2.5, 5)
	local yaw = (around or npc:GetAngles().y) + math.Rand(-spread, spread)
	local a = math.rad(yaw)
	local p = npc:GetPos()
	npc.tifFace = Vector(p.x + math.cos(a) * 300, p.y + math.sin(a) * 300, p.z + 60)
end

local function aim_point(npc, c, now)
	local e = c.ent
	if now > (npc.tifAimPickAt or 0) then
		npc.tifAimPickAt = now + math.Rand(0.8, 2)
		npc.tifAimHead = math.random() < npc.tifArch.headshotChance
	end

	if npc.tifAimHead then return TIF.EyeOf(e) - HEAD_OFF end

	return e:WorldSpaceCenter() + CHEST_OFF
end

local function gait(npc, kind, dist, now)
	local g = npc.tifGait

	if g and g.kind == kind and (now < g.untilT or Move.Moving(npc)) then
		return g.speed
	end

	local speed
	if kind == "move" or kind == "advance" then
		local len = dist
		if kind == "advance" then
			len = dist - (npc.tifArch.prefRange and npc.tifArch.prefRange[2] or 0) * 0.85
		end

		speed = len > Move.SPRINT_DIST and "sprint" or "tactical"
	else
		speed = "tactical"
	end

	npc.tifGait = { kind = kind, speed = speed, untilT = now + math.Rand(3, 7) }
	return speed
end

local function short_of(npc, target, keep)
	local d = npc:GetPos() - target
	d.z = 0
	local len = d:Length()
	if len <= keep + 1 then return npc:GetPos() end

	return target + d * (keep / len)
end

local WADE_KNEE, WADE_WAIST = Vector(0, 0, 14), Vector(0, 0, 34)
local LR_QUIET, LR_ENTER, LR_ENTER_CROSS, LR_MIN = 2.5, 0.4, 0.15, 0.8

local CROSS_R, CROSS_W = 170, 26
local function mate_across(npc)
	local sq = npc.tifSquad
	local members = sq and sq.members
	if not members then return false end

	local pos, fwd = npc:GetPos(), npc:GetForward()
	for i = 1, #members do
		local m = members[i]
		if m ~= npc and IsValid(m) and not m.tifDead then
			local mp = m:GetPos()
			local dx, dy, dz = mp.x - pos.x, mp.y - pos.y, mp.z - pos.z
			local ahead = dx * fwd.x + dy * fwd.y

			if ahead > 8 and ahead < CROSS_R and math.abs(dz) < 60 then
				local side = dx * fwd.y - dy * fwd.x
				if math.abs(side) < CROSS_W then return true end
			end
		end
	end

	return false
end

local function low_ready(npc, now, coverFire)
	local c = npc.tifPrimaryC
	local hot = npc.tifFire.want or coverFire or (c and c.visible)

	if hot then
		npc.tifLastHotAt = now
	end

	local eligible = npc.tifMode == A.MODE_AIM and npc.tifStance ~= 2 and not TIF.CoverBehave.In(npc)
		and not npc.tifDowned and not npc.tifBipod
	local quiet = now - (npc.tifLastHotAt or -99) > LR_QUIET
	local ffLine = (npc.tifLowReadyUntil or 0) > now
	local cq, enter = npc.tifCQB, LR_ENTER
	local reason

	if cq and cq.lowReady then
		reason = true
	elseif cq then
		reason = ffLine or mate_across(npc)
		enter = LR_ENTER_CROSS
	else
		reason = ffLine or quiet
	end

	local want = eligible and not hot and reason
	local on = npc:GetNW2Bool("tif_lowready", false)

	if want then
		npc.tifLRWant = npc.tifLRWant or now

		if not on and now - npc.tifLRWant >= enter then
			npc:SetNW2Bool("tif_lowready", true)
			npc.tifLROn = now
		end
	else
		npc.tifLRWant = nil

		if on and (hot or not eligible or now - (npc.tifLROn or 0) >= LR_MIN) then
			npc:SetNW2Bool("tif_lowready", false)
		end
	end

	if on and (npc.tifLowReadyUntil or 0) > now and npc.tifAction then
		npc.tifAction = npc.tifAction .. " [friendly in line]"
	end
end

local function sidestep_point(npc, threatPos, avoid)
	local pos = npc:GetPos()
	local to = threatPos - pos
	to.z = 0
	to:Normalize()
	local side = Vector(-to.y, to.x, 0) * (math.random() < 0.5 and -1 or 1)

	if IsValid(avoid) and side:Dot(avoid:GetPos() - pos) > 0 then
		side:Mul(-1)
	end

	return Move.Snap(pos + side * math.Rand(110, 240))
end

local function update_awareness(npc, c, now)
	local arch = npc.tifArch
	local st = npc.tifAware

	if c then
		local fix = math.max(c.seenAt, c.heardAt)
		if c.visible then
			if st ~= AW.ENGAGED then
				npc.tifReactUntil = now + math.Rand(arch.reaction[1], arch.reaction[2]) * TIF.ReactionScale()
				npc.tifEngagedAt = now
				TIF.Say(npc, TIF.Chatter and TIF.Chatter.ContactEvent(c.ent) or "contact", 0.9)
				Per.Share(npc, c)
			elseif c.reacquired and c.reacquired > (npc.tifLastReacq or 0) then
				npc.tifLastReacq = c.reacquired
				npc.tifReactUntil = now + math.Rand(arch.reaction[1], arch.reaction[2]) * 0.5 * TIF.ReactionScale()
				npc.tifEngagedAt = now
			end

			set_aware(npc, AW.ENGAGED, now)
			return
		end

		local lost = now - fix
		if st == AW.ENGAGED then
			if lost > arch.loseContact then
				npc.tifSearch = { start = now, pos = c.pos, dir = c.dir, points = nil, i = 0 }
				set_aware(npc, AW.SEARCHING, now)
			end

			return
		end

		if st == AW.SEARCHING then
			if not npc.tifSearch or c.heardAt > npc.tifSearch.start then
				npc.tifSearch = { start = now, pos = c.pos, dir = c.dir, points = nil, i = 0 }
			end

			if now - npc.tifSearch.start > arch.searchTime then
				npc.tifHeightenedUntil = now + HEIGHTENED_TIME

				for _, k in pairs(npc.tifK.contacts) do
					k.confirmed, k.meter = false, 0
				end

				TIF.Say(npc, "clear", 0.5)
				set_aware(npc, AW.UNAWARE, now)
			end

			return
		end

		if lost < ALERTED_TIMEOUT then
			set_aware(npc, AW.ALERTED, now)
		else
			npc.tifSearch = { start = now, pos = c.pos, dir = c.dir, points = nil, i = 0 }
			set_aware(npc, AW.SEARCHING, now)
		end

		return
	end

	if st == AW.ENGAGED or st == AW.ALERTED then
		npc.tifHeightenedUntil = now + HEIGHTENED_TIME
		npc.tifSearch = nil
		set_aware(npc, AW.UNAWARE, now)
		return
	end

	if st == AW.SEARCHING then
		local sq = npc.tifSquad
		local limit = (sq and sq.order and sq.order.kind == "advance") and math.min(arch.searchTime, 8) or arch.searchTime

		if not npc.tifSearch or now - npc.tifSearch.start > limit then
			npc.tifHeightenedUntil = now + HEIGHTENED_TIME
			npc.tifSearch = nil
			set_aware(npc, AW.UNAWARE, now)
		end

		return
	end

	local stim = npc.tifStim
	local suspect = Per.Suspect(npc, now)

	if suspect or (stim and now - stim.time < SUSPICIOUS_TIMEOUT) then
		if st == AW.UNAWARE then
			TIF.Say(npc, "swear", 0.15)
		end

		set_aware(npc, AW.SUSPICIOUS, now)
		return
	end

	if st == AW.SUSPICIOUS and now - npc.tifAwareSince > SUSPICIOUS_TIMEOUT then
		set_aware(npc, AW.UNAWARE, now)
	end
end

local function duty(npc, now)
	npc.tifMode = (npc.tifHeightenedUntil or 0) > now and A.MODE_AIM or A.MODE_RELAXED
	npc.tifStance = A.STANCE_STAND
	npc.tifFire.want = false
	npc.tifAction = "duty"

	local gp = npc.tifGuardPost
	if gp then
		npc.tifPost, npc.tifPostYaw = gp.pos, gp.yaw
	end

	local PM = TIF.PassiveMW

	if TIF.Squad.Duty(npc, now) then
		if PM and PM.Duty(npc, now, not Move.Moving(npc)) then
			Move.Stop(npc)
		end

		return
	end

	npc.tifFormationLook = nil
	local post = npc.tifPost

	if post and npc:GetPos():DistToSqr(post) > 80 * 80 then
		if PM and PM.Duty(npc, now, false) then return end

		npc.tifAction = "return to post"
		npc.tifFace = nil

		if not Move.SetGoal(npc, post, "walk", "post", npc.tifPostYaw) then
			npc.tifPost = npc:GetPos()
		end

		return
	end

	Move.Stop(npc)
	if PM and PM.Duty(npc, now, true) then return end

	look_random(npc, npc.tifPostYaw, 70, now)

	if Weapon.Reloading(npc) == false and npc.tifWep.ammo < npc.tifWep.clip * 0.5 then
		Weapon.StartReload(npc)
	end
end

local function investigate(npc, now)
	npc.tifMode = A.MODE_AIM
	npc.tifStance = A.STANCE_STAND
	npc.tifFire.want = false
	local suspect = Per.Suspect(npc, now)
	local pos = (suspect and suspect.suspectPos) or (npc.tifStim and npc.tifStim.pos)
	if not pos then return end

	npc.tifFace = pos + UP40
	npc.tifAction = "investigate"

	local PM = TIF.PassiveMW and TIF.PassiveMW.Use(npc) and TIF.PassiveMW
	if now - npc.tifAwareSince > 1.5 and npc:GetPos():DistToSqr(pos) > 120 * 120 then
		Move.SetGoal(npc, pos, PM and "alert" or "tactical", "investigate")
	elseif not Move.Moving(npc) and npc:GetPos():DistToSqr(pos) <= 120 * 120 then
		npc.tifAction = "look around"
		npc.tifFace = nil

		local stim = npc.tifStim
		local key = stim and stim.time or 0
		if npc.tifAct and npc.tifAct.trans then return end

		if TIF.SearchMW and npc.tifLookedAt ~= key and not (stim and stim.kind == "man_down") then
			npc.tifLookedAt = key

			if math.random() < 0.6 and TIF.SearchMW.Look(npc, now, (pos - npc:GetPos()):Angle().y) then
				return
			end
		end

		if PM and PM.Investigate(npc, now) then return end

		look_random(npc, nil, 160, now)
	end
end

local function alerted(npc, c, now)
	local arch = npc.tifArch
	npc.tifMode = A.MODE_AIM
	npc.tifFire.want = false

	if TIF.CoverBehave.Update(npc, c, now) then return end

	local goal = npc.tifRole == "maneuver" and npc.tifCoverCenter
	if goal and npc:GetPos():DistToSqr(goal) > 100 * 100 then
		npc.tifAction = "maneuver (not seen yet)"
		npc.tifStance = A.STANCE_STAND
		npc.tifFace = nil

		if not Move.SetGoal(npc, goal, gait(npc, "move", 0, now), "maneuver") then
			npc.tifCoverCenter = nil
		end

		return
	end

	npc.tifFace = c.pos + UP40
	local dist = npc:GetPos():Distance(c.pos)

	if arch.aggression >= 0.55 or dist < 900 then
		npc.tifAction = "close in"
		npc.tifStance = A.STANCE_STAND

		if dist > arch.prefRange[2] * 0.7 then
			Move.SetGoal(npc, short_of(npc, c.pos, math.max(150, arch.prefRange[2] * 0.6)), gait(npc, "advance", dist, now), "close_in")
		else
			Move.Stop(npc)
		end
	else
		npc.tifAction = "hold, watching"
		npc.tifStance = A.STANCE_CROUCH
		Move.Stop(npc)
	end
end

local function prone_fight(npc, c, now, dist)
	local Pr = TIF.ProneB
	local arch = npc.tifArch
	local f = npc.tifFire
	npc.tifMode = A.MODE_AIM
	npc.tifStance = 2
	Move.Stop(npc)

	if not Pr.Ready(npc) then
		f.want = false
		npc.tifAction = "prone: moving"
		return
	end

	npc.tifAction = "prone"
	local p = npc.tifProne

	if c.visible then
		local aim = aim_point(npc, c, now)
		npc.tifFace, f.want, f.aimPos = aim, true, aim
	else
		npc.tifFace, f.want = c.pos + UP40, false

		local GRN = TIF.GrenadeMW
		if GRN and GRN.OpenThrow and GRN.OpenThrow(npc, c, now, now - math.max(c.seenAt, c.heardAt)) then
			return
		end
	end

	local supp = npc.tifSupp or 0
	local lost = now - math.max(c.seenAt, c.heardAt)
	local held = now - p.since
	local done

	if p.reason == "pinned" then
		done = supp < 0.25 and held > 6
	else
		done = dist < 900 or lost > 4
	end

	if done or held > 40 then
		Pr.GetUp(npc)
	end
end

local function engage(npc, c, now)
	local arch = npc.tifArch
	local pos = npc:GetPos()
	local dist = pos:Distance(c.pos)
	local f = npc.tifFire
	npc.tifMode = A.MODE_AIM
	f.target = c.ent

	if TIF.MeleeMW and dist < 200 and TIF.MeleeMW.Try(npc, c, now) then
		return
	end

	if TIF.Shield and TIF.Shield.Try(npc, c, now) then return end
	if TIF.Launcher and TIF.Launcher.Consider(npc, c, now) then return end

	local Pr = TIF.ProneB
	local supp = npc.tifSupp or 0

	local GRN = TIF.GrenadeMW
	if GRN and npc.tifThrow and GRN.OpenThink(npc, now) then return end

	if Pr.Is(npc) then
		prone_fight(npc, c, now, dist)
		return
	end

	local BP = TIF.BipodMW
	if BP and npc.tifBipod and BP.Update(npc, c, now) then return end
	if TIF.CoverBehave.Update(npc, c, now) then return end

	local goal = npc.tifRole == "maneuver" and npc.tifCoverCenter
	if goal and pos:DistToSqr(goal) > 100 * 100 then
		npc.tifAction = "maneuver"
		npc.tifStance = A.STANCE_STAND

		local sp = Move.CombatGait(npc, goal)
		if c.visible and sp ~= "sprint" then
			local aim = aim_point(npc, c, now)
			npc.tifFace, f.aimPos, f.want = aim, aim, true
		else
			npc.tifFace, f.want = nil, false
		end

		if not Move.SetGoal(npc, goal, sp, "maneuver") then
			npc.tifCoverCenter = nil
		end

		return
	end

	if now - (npc.tifLastProneAt or -99) > 8 and not Move.Moving(npc) then
		if supp > 0.65 and npc.tifCoverSearchFailed ~= false and math.random() < arch.proneChance then
			if Pr.GoDown(npc, "pinned") then return end
		elseif arch.longRangeProne and c.visible and dist > 1400 and supp < 0.5 and math.random() < 0.3 then
			if Pr.GoDown(npc, "long range") then return end
		end
	end

	if BP and not npc.tifBipod and dist >= arch.prefRange[1] and BP.Update(npc, c, now) then
		return
	end

	local careful = B.Careful(npc)

	if c.visible then
		local aim = aim_point(npc, c, now)
		npc.tifFace = aim
		f.aimPos, f.want = aim, true
		npc.tifAction = "engage"

		local em = npc.tifEngageMove
		if em and now > em.minUntil then
			if (em.kind == "advance" and dist < arch.prefRange[2] * 0.85)
				or (em.kind == "back" and dist > arch.prefRange[1] * 1.2) then
					em = nil
				end
		end

		if not em then
			if dist > arch.prefRange[2] then
				em = { kind = "advance", minUntil = now + 2 }
			elseif dist < arch.prefRange[1] then
				em = { kind = "back", minUntil = now + 2 }
			end
		end

		npc.tifEngageMove = em

		local covering = careful and npc.tifRole == "base" and B.Bounding(npc)

		if em and em.kind == "advance" and not TIF.Morale.Shaken(npc) and not covering then
			npc.tifAction = "advance"

			if not Move.Moving(npc) then
				TIF.Say(npc, "advance", 0.3)
			end

			local sp = gait(npc, "advance", dist, now)
			if careful and B.UnderFire(npc, now) then
				sp = "tactical"
			end

			if sp == "run" or sp == "sprint" then
				f.want, npc.tifFace = false, nil
				npc.tifAction = "advance (run)"
			end

			Move.SetGoal(npc, B.LineCap(npc, short_of(npc, c.pos, math.max(150, arch.prefRange[2] * 0.75)), c.pos, careful), sp, "advance")
		elseif em and em.kind == "back" then
			npc.tifAction = "back off"
			local away = pos - c.pos
			away.z = 0
			away:Normalize()

			if not Move.SetGoal(npc, pos + away * 280, "tactical", "back_off") then
				Move.Stop(npc)
			end
		elseif (npc.tifFFBlockedAt or 0) > now - 1 or now > (npc.tifNextShift or 0) then
			npc.tifNextShift = now + math.Rand(4, 9)
			local blocked = (npc.tifFFBlockedAt or 0) > now - 1

			if blocked or math.random() < 0.25 + arch.aggression * 0.3 then
				local p = sidestep_point(npc, c.pos, blocked and npc.tifFFBlocker or nil)
				if p then
					npc.tifAction = blocked and "clear line of fire" or "shift"
					Move.SetGoal(npc, p, "tactical", "shift")
				end
			end
		elseif npc.tifMove.tag ~= "shift" or not Move.Moving(npc) then
			Move.Stop(npc)
		end
	else
		local lost = npc.tifPress and (now - c.seenAt) or (now - math.max(c.seenAt, c.heardAt))

		if GRN and GRN.OpenThrow and GRN.OpenThrow(npc, c, now, lost) then
			return
		end

		npc.tifFace = c.pos + UP40

		local baseFire = npc.tifRole == "base" and lost < 5

		local wdef = npc.tifWep and npc.tifWep.def
		local harass = (c.source == "fired on" or c.source == "hit") and lost < 25 and dist > 1200
			and not (wdef and wdef.projectile) and not TIF.Morale.Shaken(npc)

		if (lost < 1.2 and arch.aggression > 0.45 and c.source == "sight") or baseFire then
			f.aimPos, f.want = c.pos + UP40, true
			npc.tifAction = baseFire and "suppressing" or "covering fire"
		elseif harass then
			if now >= (npc.tifNextTap or 0) then
				npc.tifNextTap = now + math.Rand(1.2, 3.5)
				local j = dist * 0.04
				npc.tifTapAim = c.pos + UP40 + Vector(math.Rand(-j, j), math.Rand(-j, j), math.Rand(-j * 0.3, j * 0.5))

				npc.tifTapUntil = now + 0.1
			end

			local aim = npc.tifTapAim or (c.pos + UP40)
			npc.tifFace, f.aimPos = aim, aim
			f.want = now < (npc.tifTapUntil or 0)
			npc.tifAction = "return fire (long range)"

			if npc.tifMove.tag == "reacquire" then
				Move.Stop(npc)
			end
		else
			f.want = false
			npc.tifAction = "reacquire"

			if lost > 1.5 then
				local keep = careful and arch.prefRange[1] or 150
				Move.SetGoal(npc, B.LineCap(npc, short_of(npc, c.pos, keep), c.pos, careful), gait(npc, "close", dist, now), "reacquire")
			end
		end
	end

	if Move.Moving(npc) then
		npc.tifStance = A.STANCE_STAND
	elseif now > (npc.tifNextStance or 0) then
		npc.tifNextStance = now + math.Rand(3, 6)
		npc.tifStance = (dist > 450 and math.random() < arch.crouchChance) and A.STANCE_CROUCH or A.STANCE_STAND
	end
end

local function cqb(npc, c, now)
	local t = npc.tifCQB
	local f = npc.tifFire
	npc.tifMode = A.MODE_AIM
	npc.tifAction = "cqb: " .. (t.label or "")

	if TIF.MeleeMW and c and c.visible and npc:GetPos():DistToSqr(c.pos) < 200 * 200 and TIF.MeleeMW.Try(npc, c, now) then
		return
	end

	local shooting = c and c.visible and c.ent and npc:GetPos():DistToSqr(c.pos) < 1800 * 1800

	local cqS = npc.tifSquad and npc.tifSquad.cqb
	if shooting and cqS and cqS.phase == "stack" and not cqS.committed then
		local close = npc:GetPos():DistToSqr(c.pos) < 220 * 220
		if not close and now - (npc.tifHurtAt or -99) > 3 then
			shooting = false
		end
	end

	local q = npc.tifCQBQueue
	if npc.tifCQBActUntil and now >= npc.tifCQBActUntil then
		npc.tifCQBActUntil = nil

		if npc.TIFSetSlim then
			npc:TIFSetSlim(false)
		end

		if npc.tifAct and npc.tifAct.name == npc.tifCQBActName and not (q and #q > 0) then
			TIF.Action.Clear(npc)
		end

		npc.tifCQBActName = nil
	end

	if not npc.tifCQBActUntil and q and #q > 0 and now >= (npc.tifCQBDelay or 0) then
		npc.tifCQBDelay = nil
		local item = table.remove(q, 1)

		local yaw = item.yawFn and item.yawFn(npc) or item.yaw
		if item.check and not item.check(npc, yaw or npc:GetAngles().y) then
			if TIF.Debug then
				TIF.Debug("cqb: ", item.name, " skipped (path blocked)")
			end

			return
		end

		if yaw then
			npc:SetAngles(Angle(0, yaw, 0))
		end

		local d = Act.Play(npc, item.name, item.opts or { root = true })
		if d then
			npc.tifCQBActUntil = now + d * (item.hold or 1)
			npc.tifCQBActName = item.name
			npc.tifCQBLoop = nil

			if npc.TIFSetSlim then
				npc:TIFSetSlim(true)
			end
		end

		if item.onStart then
			item.onStart(npc, now, d or 0)
		end
	end

	if npc.tifCQBActUntil then
		Move.Stop(npc)
		f.want = false
		npc.tifFace = nil
		npc.tifStance = A.STANCE_STAND
		return
	end

	local wait = t.wait
	local atSpot = npc:GetPos():DistToSqr(t.goal) < 32 * 32

	if wait and atSpot and not shooting and npc.tifCQBLoop ~= wait.name then
		npc:SetAngles(Angle(0, wait.yaw, 0))

		local wc = TIF.GTG.Clip(wait.name, npc.tifHomeHost)
		if wc and not wc.loop then
			Act.Play(npc, wait.name)
		else
			Act.Loop(npc, wait.name)
		end

		npc.tifCQBLoop = wait.name
	elseif npc.tifCQBLoop and (shooting or not atSpot or not wait or wait.name ~= npc.tifCQBLoop) then
		if npc.tifAct and npc.tifAct.name == npc.tifCQBLoop then
			Act.Clear(npc)
		end

		npc.tifCQBLoop = nil
	end

	if npc.tifCQBLoop then
		Move.Stop(npc)
		f.want = false
		npc.tifFace = nil
		npc.tifStance = A.STANCE_STAND
		return
	end

	if shooting then
		local aim = aim_point(npc, c, now)
		npc.tifFace, f.aimPos, f.want, f.target = aim, aim, true, c.ent
	else
		f.want = false
		npc.tifFace = t.face
	end

	local there = npc:GetPos():DistToSqr(t.goal) < 32 * 32
	if there then
		Move.Stop(npc)
		npc.tifStance = (t.crouch and not shooting) and A.STANCE_CROUCH or A.STANCE_STAND
		npc.tifCQBGlideT = nil
	elseif TIF.CQB and TIF.CQB.Glide and TIF.CQB.Glide(npc, t.goal, now) then
		npc.tifStance = A.STANCE_STAND
	else
		npc.tifStance = A.STANCE_STAND
		local CQ = TIF.CQB

		local via = CQ and CQ.Through and CQ.Through(npc, cqS, t.goal, now)
		if via ~= "glide" then
			local goal = via or t.goal

			local alt = npc.tifCQBAlt
			if alt and (now > alt.untilT or alt.for_ ~= goal) then
				npc.tifCQBAlt, alt = nil, nil
			end

			if alt then
				goal = alt.pos
			end

			local ok = Move.SetGoal(npc, goal, t.speed or "tactical", "cqb")
			if CQ and CQ.PathTrouble and not CQ.PathTrouble(npc, goal, ok, now) then
				npc.tifCQBFails = nil
			end
		end
	end
end

local function search_points(s)
	local pts = { s.pos }
	local areas = navmesh.Find(s.pos, 700, 120, 120)
	local scored = {}

	for _, a in ipairs(areas) do
		local p = a:GetCenter()
		local d = p:Distance(s.pos)

		if d > 150 then
			local score = math.random()
			if s.dir then
				local to = p - s.pos
				to.z = 0
				to:Normalize()
				score = score + to:Dot(s.dir) * 1.5
			end

			scored[#scored + 1] = { p = p, score = score }
		end
	end

	table.sort(scored, function(a, b) return a.score > b.score end)

	for i = 1, math.min(3, #scored) do
		pts[#pts + 1] = scored[i].p
	end

	return pts
end

local function search(npc, now)
	local s = npc.tifSearch
	npc.tifMode = A.MODE_AIM
	npc.tifStance = A.STANCE_STAND
	npc.tifFire.want = false
	if not s then return end

	if s.watch then
		if npc:GetPos():DistToSqr(s.watch) > 80 * 80 then
			npc.tifAction = "search: to overwatch"
			npc.tifFace = s.pos + UP40

			if not Move.SetGoal(npc, s.watch, "tactical", "search") then
				s.watch = nil
			end
		else
			Move.Stop(npc)
			npc.tifAction = "search: overwatch"
			npc.tifStance = A.STANCE_CROUCH

			if now > (npc.tifNextLook or 0) then
				npc.tifNextLook = now + math.Rand(1.5, 3)
				local yaw = (s.pos - npc:GetPos()):Angle().y + math.Rand(-25, 25)
				local r = math.rad(yaw)
				npc.tifFace = npc:GetPos() + Vector(math.cos(r), math.sin(r), 0) * 400 + UP40
			end
		end

		return
	end

	if not s.points then
		s.points, s.i = search_points(s), 1
	end

	local target = s.points[s.i]
	if not target then
		npc.tifAction = "search: watching"
		npc.tifFace = nil
		Move.Stop(npc)
		look_random(npc, nil, 180, now)
		return
	end

	npc.tifAction = "search " .. s.i .. "/" .. #s.points
	local m = npc.tifMove
	if m.goal == nil and (m.result == "arrived" or m.result == "fail" or m.result == "stuck" or m.result == "timeout")
		and s.lastGoal == target then
		if npc.tifAct and npc.tifAct.trans then return end

		if not s.lookUntil and TIF.SearchMW and TIF.SearchMW.Look(npc, now, (s.pos - npc:GetPos()):Angle().y) then
			s.lookUntil = now + 0.5
			return
		end

		s.lookUntil = s.lookUntil or now + math.Rand(2, 4)
		npc.tifFace = nil
		look_random(npc, nil, 180, now)

		if now > s.lookUntil then
			s.i, s.lookUntil, m.result = s.i + 1, nil, nil
		end

		return
	end

	npc.tifFace = target + Vector(0, 0, 50)
	s.lastGoal = target

	if not Move.SetGoal(npc, target, gait(npc, "close", 0, now), "search") then
		s.i = s.i + 1
	end
end

function B.StartSearch(npc, pos, dir, now)
	npc.tifSearch = { start = now, pos = Vector(pos), dir = dir, points = nil, i = 0 }
	set_aware(npc, AW.SEARCHING, now)
end

B.LINE_LEAD = 500
B.UNDER_FIRE_HURT = 3
B.UNDER_FIRE_SUPP = 0.2

function B.Careful(npc)
	if npc.tifGuerrilla or npc.tifHunter or npc.tifPress then return false end

	local sq = npc.tifSquad
	if not sq or not sq.members or #sq.members < 2 then return false end

	local o = sq.order
	if o and o.kind == "advance" then return false end

	return true
end

function B.Bounding(npc)
	local t = npc.tifSquad and npc.tifSquad.tactic
	return t ~= nil and t.kind == "bound"
end

function B.UnderFire(npc, now)
	return now - (npc.tifHurtAt or -99) < B.UNDER_FIRE_HURT or (npc.tifSupp or 0) > B.UNDER_FIRE_SUPP
end

function B.LineCap(npc, goal, threat, careful)
	if not careful or not goal or not threat then return goal end

	local sq = npc.tifSquad
	local cx, cy, n = 0, 0, 0

	for _, m in ipairs(TIF.Squad.Members(sq)) do
		if m ~= npc and IsValid(m) and not m.tifDead then
			local p = m:GetPos()
			cx, cy, n = cx + p.x, cy + p.y, n + 1
		end
	end

	if n == 0 then return goal end

	cx, cy = cx / n, cy / n
	local dx, dy = threat.x - cx, threat.y - cy
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then return goal end

	dx, dy = dx / len, dy / len
	local ahead = (goal.x - cx) * dx + (goal.y - cy) * dy
	if ahead <= B.LINE_LEAD then return goal end

	local back = ahead - B.LINE_LEAD
	return Vector(goal.x - dx * back, goal.y - dy * back, goal.z)
end

B.CALM_STAND_AFTER = 0.3
B.CALM_STAND_SPEED = 40

function B.NoCalmStand(npc, now)
	local aw = npc.tifAware
	local standing = npc.tifMode == A.MODE_RELAXED and npc.tifStance == A.STANCE_STAND and not npc.tifAct
		and (aw == AW.ENGAGED or aw == AW.ALERTED or npc.tifMoraleState == "broken")
		and not npc.tifVeh and not npc.tifBoard and not npc.tifLeaving and not npc.tifDowned and not npc.tifSurrendered
		and npc.loco and npc.loco:GetVelocity():Length2DSqr() < B.CALM_STAND_SPEED * B.CALM_STAND_SPEED

	if not standing then
		npc.tifCalmSince = nil
		return false
	end

	npc.tifCalmSince = npc.tifCalmSince or now
	if now - npc.tifCalmSince < B.CALM_STAND_AFTER then return false end

	if npc.tifMoraleState == "broken" then
		npc.tifStance = A.STANCE_CROUCH
	else
		npc.tifMode = A.MODE_AIM
	end

	return true
end

function B.Think(npc, dt)
	local now = CurTime()
	if not npc.tifPost then
		npc.tifPost = npc:GetPos()
		npc.tifPostYaw = npc:GetAngles().y
	end

	Prof.Begin("perception")
	Per.Update(npc, dt, now)

	if npc.tifSquad then
		if next(npc.tifK.contacts) ~= nil then
			for _, c in pairs(npc.tifK.contacts) do
				if c.confirmed and (c.visible or c.source == "heard" or c.source == "hit" or c.source == "fired on") then
					TIF.Squad.Report(npc, c)
				end
			end
		end

		TIF.Squad.Sync(npc, now)
	end

	Prof.End()

	Prof.Begin("brain")
	TIF.Supp.Decay(npc, dt)
	local c = Per.Primary(npc, now)
	npc.tifPrimary = c and c.ent or nil
	npc.tifPrimaryC = c

	if (npc.tifAware or AW.UNAWARE) > AW.UNAWARE or (npc.tifMove and npc.tifMove.goal ~= nil) then
		Move.UpdateThreatAreas(npc)
	end

	update_awareness(npc, c, now)

	local st = npc.tifAware
	local fighting = (st == AW.ENGAGED or st == AW.ALERTED) and c ~= nil

	local exiting = false
	if not fighting then
		if TIF.CoverBehave.In(npc) then
			exiting = TIF.CoverBehave.Exit(npc, "fight over")
		end

		if TIF.ProneB.Is(npc) then
			TIF.ProneB.GetUp(npc)
		end
	end

	if npc.tifVeh and not IsValid(npc.tifVeh) then
		npc.tifVeh, npc.tifBoard, npc.tifLeaving = nil, nil, nil
		npc:SetParent(nil)
		npc:SetCollisionGroup(COLLISION_GROUP_NPC)
	end

	local V = TIF.Vehicle

	if npc.tifHeli and TIF.AirRide and TIF.AirRide.Think(npc, now) then
	elseif npc.tifVeh then
		V.RideThink(npc, now)
	elseif npc.tifLeaving and V.LeaveThink(npc, now) then
	elseif npc.tifBoard and V.BoardThink(npc, now) then
	elseif npc.tifSurrendered then
		TIF.Morale.SurrenderThink(npc, now)
	elseif npc.tifDowned then
		TIF.Casualty.DownThink(npc, now)
	elseif exiting then
		npc.tifFire.want = false
		npc.tifFace = nil
		Move.Stop(npc)
	elseif TIF.Shield and TIF.Shield.Busy(npc, now) then
	elseif TIF.MeleeMW and TIF.MeleeMW.Busy(npc, now) then
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.ReactMW and TIF.ReactMW.Think(npc, now) then
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.PassiveMW and TIF.PassiveMW.Busy(npc, now) then
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.BipodMW and npc.tifBipod and npc.tifAware ~= AW.ENGAGED and TIF.BipodMW.Update(npc, npc.tifPrimaryC, now) then
	elseif TIF.SearchMW and TIF.SearchMW.Busy(npc, now) then
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.HitsMW and TIF.HitsMW.Busy(npc, now) then
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.ProneB.Update(npc, now) then
		npc.tifFire.want = false
	elseif TIF.ProneB.Is(npc) and not fighting then
		npc.tifFire.want = false
	elseif npc.tifLaunch and TIF.Launcher and TIF.Launcher.Think(npc, c, now) then
	elseif npc.tifMedic and TIF.Casualty.MedicThink(npc, c, now) then
	elseif TIF.Morale.BrokenThink(npc, c, now) then
	elseif npc.tifCQB and not TIF.ProneB.Is(npc) then
		if TIF.CoverBehave.In(npc) then
			TIF.CoverBehave.Leave(npc, "room clearing")
		end

		cqb(npc, c, now)
	elseif st == AW.ENGAGED and c then
		engage(npc, c, now)
	elseif st == AW.SEARCHING then
		search(npc, now)
	elseif st == AW.ALERTED and c then
		alerted(npc, c, now)
	elseif st == AW.SUSPICIOUS then
		investigate(npc, now)
	else
		duty(npc, now)
	end

	if not (st == AW.ENGAGED and c) then
		npc.tifFire.target = nil
	end

	if TIF.ProneB.Is(npc) then
		npc.tifStance = 2
	end

	local inCqb = npc.tifCQB ~= nil
	if npc.tifCqbNet ~= inCqb then
		npc.tifCqbNet = inCqb
		npc:SetNW2Bool("tif_cqb", inCqb)
	end

	if now >= (npc.tifWadeNext or 0) then
		npc.tifWadeNext = now + 0.4
		local p = npc:GetPos()
		local w = 0

		if bit.band(util.PointContents(p + WADE_KNEE), CONTENTS_WATER) ~= 0 then
			w = bit.band(util.PointContents(p + WADE_WAIST), CONTENTS_WATER) ~= 0 and 2 or 1
		end

		if w ~= (npc.tifWade or 0) then
			npc.tifWade = w
			npc:SetNW2Int("tif_wade", w)
		end
	end

	if not npc.tifVeh and not npc.tifBoard and not npc.tifLeaving and not npc.tifDowned and not npc.tifSurrendered then
		if fighting and c then
			local indoorsLongGun = npc.tifCQB ~= nil and npc.tifArch.secondaryBelow ~= nil
			Weapon.Choose(npc, npc:GetPos():Distance(c.pos), now, indoorsLongGun and SEC_OPT or nil)
		elseif not fighting then
			Weapon.Choose(npc, nil, now)
		end
	end

	local mv = npc.tifMove
	local coverFire = npc.tifCoverFire and now < npc.tifCoverFire.untilT

	if coverFire then
		npc.tifMode = A.MODE_AIM
	end

	if mv.goal and mv.speed == "sprint" and not coverFire and not exiting and npc.tifStance ~= 2 then
		npc.tifFire.want = false
	end

	if npc.tifMode == A.MODE_AIM and mv.goal and (mv.speed == "run" or mv.speed == "sprint")
		and not npc.tifFire.want and npc.tifStance ~= 2 and not exiting and not coverFire then
		npc.tifMode = A.MODE_RELAXED
		npc.tifStance = A.STANCE_STAND
	end

	B.NoCalmStand(npc, now)

	low_ready(npc, now, coverFire)

	if npc:GetTIFMode() ~= npc.tifMode then
		npc:SetTIFMode(npc.tifMode)
	end

	if npc.tifKeepCrouchUntil then
		if now < npc.tifKeepCrouchUntil and npc.tifStance == A.STANCE_STAND and not TIF.CoverBehave.In(npc) then
			npc.tifStance = A.STANCE_CROUCH
		elseif now >= npc.tifKeepCrouchUntil then
			npc.tifKeepCrouchUntil = nil
		end
	end

	local cur = npc:GetTIFStance()
	local a = npc.tifAct
	local inStanceClip = a and (string.sub(a.name, 1, 9) == "mwk_down_" or a.name == "mwk_up_8") and now - a.t0 < a.dur

	if cur ~= npc.tifStance and not inStanceClip then
		if (cur == 0 or cur == 1) and (npc.tifStance == 0 or npc.tifStance == 1) and TIF.TransMW and TIF.TransMW.Stance then
			TIF.TransMW.Stance(npc, cur, npc.tifStance)
		end

		npc:SetTIFStance(npc.tifStance)

		if npc.tifStance ~= 2 then
			npc:TIFApplyStance()
		end
	end

	Prof.End()
end
