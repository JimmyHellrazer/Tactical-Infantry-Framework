-- Soldier decision making (Phase 1).
-- Awareness: unaware -> suspicious -> alerted -> engaged -> searching -> back to duty.
-- Each think picks one behaviour from the awareness state; behaviours set a move goal,
-- a facing target, a stance and whether to fire. Cover, squads and suppression are later phases.

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
	-- MW19 body: graded reaction clips (tactics/sv_passive_mw.lua).
	if TIF.PassiveMW then TIF.PassiveMW.OnAware(npc, old, st, now) end
end

local function look_random(npc, around, spread, now)
	if now < (npc.tifNextLook or 0) then return end
	npc.tifNextLook = now + math.Rand(2.5, 5)
	local yaw = (around or npc:GetAngles().y) + math.Rand(-spread, spread)
	local a = math.rad(yaw)
	npc.tifFace = npc:GetPos() + Vector(math.cos(a), math.sin(a), 0) * 300 + Vector(0, 0, 60)
end

local function aim_point(npc, c, now)
	local e = c.ent
	if now > (npc.tifAimPickAt or 0) then
		npc.tifAimPickAt = now + math.Rand(0.8, 2)
		npc.tifAimHead = math.random() < npc.tifArch.headshotChance
	end
	if npc.tifAimHead then return TIF.EyeOf(e) - Vector(0, 0, 3) end
	return e:WorldSpaceCenter() + Vector(0, 0, 6)
end

-- How to move, picked per soldier and kept for a few seconds, so a squad doesn't all walk the
-- same way at the same time. Kinds:
--   advance  closing on an enemy: far away mostly run (gun down), nearer an aimed jog or walk
--   close    reacquiring / searching: aimed walk or jog
--   move     getting to a spot (maneuver goal) with nothing to shoot: run or sprint
local function gait(npc, kind, dist, now)
	local g = npc.tifGait
	-- Kept for the whole move once picked (no switching between jog and walk halfway), and for a few
	-- seconds after so back-to-back moves don't flip either.
	if g and g.kind == kind and (now < g.untilT or Move.Moving(npc)) then return g.speed end
	-- In a fight: the aimed walk for short moves (shooting), a sprint for long ones (gun down). No aimed jog.
	-- dist: how far the move goes ("advance": to the enemy, so the stretch is down to 85% of preferred range).
	local speed
	if kind == "move" or kind == "advance" then
		local len = dist
		if kind == "advance" then len = dist - (npc.tifArch.prefRange and npc.tifArch.prefRange[2] or 0) * 0.85 end
		speed = len > Move.SPRINT_DIST and "sprint" or "tactical"
	else
		speed = "tactical"
	end
	npc.tifGait = { kind = kind, speed = speed, untilT = now + math.Rand(3, 7) }
	return speed
end

-- A spot beside the soldier, sideways relative to the threat, on the navmesh.
-- A point on his own line to a target, `keep` units short of it. Advancing, closing in and reacquiring used the
-- enemy's position itself as the goal: two sides closing on each other walked into one another, and friends all
-- headed for the same spot (user clip, 2026-11-17).
local function short_of(npc, target, keep)
	local d = npc:GetPos() - target
	d.z = 0
	local len = d:Length()
	if len <= keep + 1 then return npc:GetPos() end
	return target + d * (keep / len)
end

-- Low ready (NW2 tif_lowready; cl_body lays MW19's AI gun-down pose over the upper body, legs untouched). Weapon up
-- (aim mode) but nothing to shoot: a friendly in the line of fire, or no enemy seen / fired at for a while. Down only
-- after the reason has held LR_ENTER s, up at once when an enemy shows or he wants to fire, else after LR_MIN s.
-- (Until 0.31.0 it switched him to the calm set for 0.8-1.4 s, only for friendlies in line: the walk flickered.)
local WADE_KNEE, WADE_WAIST = Vector(0, 0, 14), Vector(0, 0, 34)
local LR_QUIET, LR_ENTER, LR_ENTER_CROSS, LR_MIN = 2.5, 0.4, 0.15, 0.8
-- CQB (user, 0.35.1): on the stack everyone but the point man is down (tifCQB.lowReady, sv_clear). Moving through
-- the building the gun stays up, quiet or not, and only dips while a squadmate is across the muzzle.
local CROSS_R, CROSS_W = 170, 26
local function mate_across(npc)
	local sq = npc.tifSquad
	if not sq or not sq.members then return false end
	local pos, fwd = npc:GetPos(), npc:GetForward()
	for _, m in ipairs(sq.members) do
		if m ~= npc and IsValid(m) and not m.tifDead then
			local d = m:GetPos() - pos
			local ahead = d.x * fwd.x + d.y * fwd.y
			if ahead > 8 and ahead < CROSS_R and math.abs(d.z) < 60 then
				local side = d.x * fwd.y - d.y * fwd.x
				if math.abs(side) < CROSS_W then return true end
			end
		end
	end
	return false
end
local function low_ready(npc, now, coverFire)
	local c = npc.tifPrimaryC
	local hot = npc.tifFire.want or coverFire or (c and c.visible)
	if hot then npc.tifLastHotAt = now end
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
		if on and (hot or not eligible or now - (npc.tifLROn or 0) >= LR_MIN) then npc:SetNW2Bool("tif_lowready", false) end
	end
	if on and (npc.tifLowReadyUntil or 0) > now and npc.tifAction then npc.tifAction = npc.tifAction .. " [friendly in line]" end
end

local function sidestep_point(npc, threatPos, avoid)
	local pos = npc:GetPos()
	local to = threatPos - pos
	to.z = 0
	to:Normalize()
	local side = Vector(-to.y, to.x, 0) * (math.random() < 0.5 and -1 or 1)
	-- Step away from the friendly that's in the line of fire, not toward it.
	if IsValid(avoid) and side:Dot(avoid:GetPos() - pos) > 0 then side:Mul(-1) end
	return Move.Snap(pos + side * math.Rand(110, 240))
end

-- Awareness transitions ------------------------------------------------------

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
			-- New information (a shot heard, a callout) restarts the search around the new position.
			if c.heardAt > (npc.tifSearch and npc.tifSearch.start or 0) then
				npc.tifSearch = { start = now, pos = c.pos, dir = c.dir, points = nil, i = 0 }
			end
			if now - npc.tifSearch.start > arch.searchTime then
				npc.tifHeightenedUntil = now + HEIGHTENED_TIME
				for _, k in pairs(npc.tifK.contacts) do k.confirmed, k.meter = false, 0 end
				TIF.Say(npc, "clear", 0.5)
				set_aware(npc, AW.UNAWARE, now)
			end
			return
		end
		-- Known enemy, never seen by this soldier (heard, hit, or told).
		if lost < ALERTED_TIMEOUT then
			set_aware(npc, AW.ALERTED, now)
		else
			npc.tifSearch = { start = now, pos = c.pos, dir = c.dir, points = nil, i = 0 }
			set_aware(npc, AW.SEARCHING, now)
		end
		return
	end

	if st == AW.ENGAGED or st == AW.ALERTED then
		-- The enemy is dead or gone from memory: back to duty, but on edge.
		npc.tifHeightenedUntil = now + HEIGHTENED_TIME
		npc.tifSearch = nil
		set_aware(npc, AW.UNAWARE, now)
		return
	end
	if st == AW.SEARCHING then
		-- A squad pushing on an objective (advance order) only looks briefly, then carries on with the push.
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
		if st == AW.UNAWARE then TIF.Say(npc, "swear", 0.15) end
		set_aware(npc, AW.SUSPICIOUS, now)
		return
	end
	if st == AW.SUSPICIOUS and now - npc.tifAwareSince > SUSPICIOUS_TIMEOUT then
		set_aware(npc, AW.UNAWARE, now)
	end
end

-- Behaviours -----------------------------------------------------------------

local function duty(npc, now)
	npc.tifMode = (npc.tifHeightenedUntil or 0) > now and A.MODE_AIM or A.MODE_RELAXED
	npc.tifStance = A.STANCE_STAND
	npc.tifFire.want = false
	npc.tifAction = "duty"
	-- Base guards and reserves always come back to their own spot.
	local gp = npc.tifGuardPost
	if gp then npc.tifPost, npc.tifPostYaw = gp.pos, gp.yaw end
	-- MW19 body: idle activities (smoke, phone, water) while standing still; put away before walking.
	local PM = TIF.PassiveMW
	-- Squad orders (formation, hold position, advance) take over routine duty.
	if TIF.Squad.Duty(npc, now) then
		if PM and PM.Duty(npc, now, not Move.Moving(npc)) then Move.Stop(npc) end
		return
	end
	npc.tifFormationLook = nil
	local post = npc.tifPost
	if post and npc:GetPos():DistToSqr(post) > 80 * 80 then
		if PM and PM.Duty(npc, now, false) then return end
		npc.tifAction = "return to post"
		npc.tifFace = nil
		if not Move.SetGoal(npc, post, "walk", "post", npc.tifPostYaw) then npc.tifPost = npc:GetPos() end
		return
	end
	Move.Stop(npc)
	if PM and PM.Duty(npc, now, true) then return end
	look_random(npc, npc.tifPostYaw, 70, now)
	if Weapon.Reloading(npc) == false and npc.tifWep.ammo < npc.tifWep.clip * 0.5 then Weapon.StartReload(npc) end
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
	-- Look first; walk over after a moment if nothing more is seen.
	local PM = TIF.PassiveMW and TIF.PassiveMW.Use(npc) and TIF.PassiveMW
	if now - npc.tifAwareSince > 1.5 and npc:GetPos():DistToSqr(pos) > 120 * 120 then
		-- MW19 body: the alert walk, at its own speed.
		Move.SetGoal(npc, pos, PM and "alert" or "tactical", "investigate")
	elseif not Move.Moving(npc) and npc:GetPos():DistToSqr(pos) <= 120 * 120 then
		npc.tifAction = "look around"
		npc.tifFace = nil
		-- MW19 body: once per noise, a look at what's around the spot (under, over, down...); then
		-- investigation idles, or checking a downed ally's body (then the alarm).
		local stim = npc.tifStim
		local key = stim and stim.time or 0
		if npc.tifAct and npc.tifAct.trans then return end -- still finishing the stop clip
		if TIF.SearchMW and npc.tifLookedAt ~= key and not (stim and stim.kind == "man_down") then
			npc.tifLookedAt = key
			if math.random() < 0.6 and TIF.SearchMW.Look(npc, now, (pos - npc:GetPos()):Angle().y) then return end
		end
		if PM and PM.Investigate(npc, now) then return end
		look_random(npc, nil, 160, now)
	end
end

local function alerted(npc, c, now)
	local arch = npc.tifArch
	npc.tifMode = A.MODE_AIM
	npc.tifFire.want = false
	-- Take cover facing where the threat was heard; pop out only once it's seen.
	if TIF.CoverBehave.Update(npc, c, now) then return end
	-- Squad maneuver (a reserve sent out, a bound toward a heard enemy): go, gun down.
	local goal = npc.tifRole == "maneuver" and npc.tifCoverCenter
	if goal and npc:GetPos():DistToSqr(goal) > 100 * 100 then
		npc.tifAction = "maneuver (not seen yet)"
		npc.tifStance = A.STANCE_STAND
		npc.tifFace = nil
		if not Move.SetGoal(npc, goal, gait(npc, "move", 0, now), "maneuver") then npc.tifCoverCenter = nil end
		return
	end
	npc.tifFace = c.pos + UP40
	local dist = npc:GetPos():Distance(c.pos)
	if arch.aggression >= 0.55 or dist < 900 then
		npc.tifAction = "close in"
		npc.tifStance = A.STANCE_STAND
		if dist > arch.prefRange[2] * 0.7 then
			Move.SetGoal(npc, short_of(npc, c.pos, math.max(150, arch.prefRange[2] * 0.6)), gait(npc, "advance", dist, now), "close_in")
		else Move.Stop(npc) end
	else
		npc.tifAction = "hold, watching"
		npc.tifStance = A.STANCE_CROUCH
		Move.Stop(npc)
	end
end

-- Lying down: shoot what's visible, turn slowly, get up when the fight needs movement.
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
		-- Lying behind something with the enemy out of sight: the prone frag throw (MW19 body).
		local GRN = TIF.GrenadeMW
		if GRN and GRN.OpenThrow and GRN.OpenThrow(npc, c, now, now - math.max(c.seenAt, c.heardAt)) then return end
	end
	local supp = npc.tifSupp or 0
	local lost = now - math.max(c.seenAt, c.heardAt)
	local held = now - p.since
	local done
	if p.reason == "pinned" then done = supp < 0.25 and held > 6
	else done = dist < 900 or lost > 4 end
	if done or held > 40 then Pr.GetUp(npc) end
end

local function engage(npc, c, now)
	local arch = npc.tifArch
	local pos = npc:GetPos()
	local dist = pos:Distance(c.pos)
	local f = npc.tifFire
	npc.tifMode = A.MODE_AIM
	f.target = c.ent
	-- Right on top of him: a butt hit, or with an enemy soldier sometimes a paired fight (TIF.MeleeMW).
	if TIF.MeleeMW and dist < 200 and TIF.MeleeMW.Try(npc, c, now) then return end
	-- (0.38.20) a civilian between him and the enemy: sometimes grabbed as a human shield (TIF.Shield)
	if TIF.Shield and TIF.Shield.Try(npc, c, now) then return end
	if TIF.Launcher and TIF.Launcher.Consider(npc, c, now) then return end
	local Pr = TIF.ProneB
	local supp = npc.tifSupp or 0

	-- MW19 body throwing a frag in the open (TIF.GrenadeMW.OpenThrow): nothing else until it's out.
	local GRN = TIF.GrenadeMW
	if GRN and npc.tifThrow and GRN.OpenThink(npc, now) then return end
	if Pr.Is(npc) then prone_fight(npc, c, now, dist) return end
	-- MW19 LMG on its bipod: it decides when to pack up (before cover or moves take him away).
	local BP = TIF.BipodMW
	if BP and npc.tifBipod and BP.Update(npc, c, now) then return end
	if TIF.CoverBehave.Update(npc, c, now) then return end

	-- Squad maneuver with no cover taken: move to the bound / flank goal, shooting on the way.
	local goal = npc.tifRole == "maneuver" and npc.tifCoverCenter
	if goal and pos:DistToSqr(goal) > 100 * 100 then
		npc.tifAction = "maneuver"
		npc.tifStance = A.STANCE_STAND
		-- Sprint the bound (the base of fire covers it); the aimed walk, shooting, for the last short stretch.
		local sp = Move.CombatGait(npc, goal)
		if c.visible and sp ~= "sprint" then
			local aim = aim_point(npc, c, now)
			npc.tifFace, f.aimPos, f.want = aim, aim, true
		else
			npc.tifFace, f.want = nil, false
		end
		if not Move.SetGoal(npc, goal, sp, "maneuver") then npc.tifCoverCenter = nil end
		return
	end

	-- No cover: lie down when pinned, or settle in prone for a long-range fight.
	if now - (npc.tifLastProneAt or -99) > 8 and not Move.Moving(npc) then
		if supp > 0.65 and npc.tifCoverSearchFailed ~= false and math.random() < arch.proneChance then
			if Pr.GoDown(npc, "pinned") then return end
		elseif arch.longRangeProne and c.visible and dist > 1400 and supp < 0.5 and math.random() < 0.3 then
			if Pr.GoDown(npc, "long range") then return end
		end
	end
	-- MW19 LMG holding still with a wall top / ledge / low wall toward the target: onto the bipod.
	if BP and not npc.tifBipod and dist >= arch.prefRange[1] and BP.Update(npc, c, now) then return end

	if c.visible then
		local aim = aim_point(npc, c, now)
		npc.tifFace = aim
		f.aimPos, f.want = aim, true
		npc.tifAction = "engage"
		-- Range keeping with hysteresis and a minimum commitment: once he starts closing in he keeps going
		-- until well inside his range (85%), backing off until well outside the near edge (120%), and
		-- neither is dropped within 2 s of starting (no stop-start at the band edges).
		local em = npc.tifEngageMove
		if em and now > em.minUntil then
			if (em.kind == "advance" and dist < arch.prefRange[2] * 0.85)
				or (em.kind == "back" and dist > arch.prefRange[1] * 1.2) then em = nil end
		end
		if not em then
			if dist > arch.prefRange[2] then em = { kind = "advance", minUntil = now + 2 }
			elseif dist < arch.prefRange[1] then em = { kind = "back", minUntil = now + 2 } end
		end
		npc.tifEngageMove = em
		if em and em.kind == "advance" and not TIF.Morale.Shaken(npc) then
			npc.tifAction = "advance"
			if not Move.Moving(npc) then TIF.Say(npc, "advance", 0.3) end
			local sp = gait(npc, "advance", dist, now)
			if sp == "run" or sp == "sprint" then
				-- Running to close the distance: no shooting on the move, face the way it's going.
				f.want, npc.tifFace = false, nil
				npc.tifAction = "advance (run)"
			end
			-- (To a point inside his range on his own line, not onto the enemy: the move ends at 85% anyway.)
			Move.SetGoal(npc, short_of(npc, c.pos, math.max(150, arch.prefRange[2] * 0.75)), sp, "advance")
		elseif em and em.kind == "back" then
			npc.tifAction = "back off"
			local away = pos - c.pos
			away.z = 0
			away:Normalize()
			if not Move.SetGoal(npc, pos + away * 280, "tactical", "back_off") then Move.Stop(npc) end
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
		local lost = now - math.max(c.seenAt, c.heardAt)
		-- Out of sight behind something: sometimes a frag over it (MW19 body, open-ground throw).
		if GRN and GRN.OpenThrow and GRN.OpenThrow(npc, c, now, lost) then return end
		npc.tifFace = c.pos + UP40
		-- Keep the last burst going briefly at the last known position. Base of fire keeps it up
		-- longer: that's the suppression that lets the maneuver group move.
		local baseFire = npc.tifRole == "base" and lost < 5
		-- Shot at from further than he can see (a sniper on a hill): harassing fire. Single aimed
		-- taps every 1.2-3.5 s toward where the shots came from, scattered by about 4% of the range;
		-- no walking out into the open toward it. Not with a launcher.
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
				-- A short trigger pull: one round (two at most from a fast rifle).
				npc.tifTapUntil = now + 0.1
			end
			local aim = npc.tifTapAim or (c.pos + UP40)
			npc.tifFace, f.aimPos = aim, aim
			f.want = now < (npc.tifTapUntil or 0)
			npc.tifAction = "return fire (long range)"
			if npc.tifMove.tag == "reacquire" then Move.Stop(npc) end
		else
			f.want = false
			npc.tifAction = "reacquire"
			if lost > 1.5 then Move.SetGoal(npc, short_of(npc, c.pos, 150), gait(npc, "close", dist, now), "reacquire") end
		end
	end

	-- Crouch when holding still, decided every few seconds.
	if Move.Moving(npc) then
		npc.tifStance = A.STANCE_STAND
	elseif now > (npc.tifNextStance or 0) then
		npc.tifNextStance = now + math.Rand(3, 6)
		npc.tifStance = (dist > 450 and math.random() < arch.crouchChance) and A.STANCE_CROUCH or A.STANCE_STAND
	end
end

-- Room clearing: follow the squad's plan (npc.tifCQB from TIF.CQB). Anything seen is shot from
-- where the soldier is; no cover search indoors.
local function cqb(npc, c, now)
	local t = npc.tifCQB
	local f = npc.tifFire
	npc.tifMode = A.MODE_AIM
	npc.tifAction = "cqb: " .. (t.label or "")
	-- Clearing a room and an enemy right there: a butt hit (or a paired fight) instead of shooting (TIF.MeleeMW).
	if TIF.MeleeMW and c and c.visible and npc:GetPos():DistToSqr(c.pos) < 200 * 200 and TIF.MeleeMW.Try(npc, c, now) then return end
	local shooting = c and c.visible and c.ent and npc:GetPos():DistToSqr(c.pos) < 1800 * 1800
	-- (2026-11-21, user: on the stack they "shouldnt like telegraph too hard to the enemy or shoot at them before
	-- clearing") Waiting on the stack: no shooting at what's seen through the door (eyes on the door, the clear goes
	-- on), unless it's right there or he's being hit.
	local cqS = npc.tifSquad and npc.tifSquad.cqb
	if shooting and cqS and cqS.phase == "stack" and not cqS.committed then
		local close = npc:GetPos():DistToSqr(c.pos) < 220 * 220
		if not close and now - (npc.tifHurtAt or -99) > 3 then shooting = false end
	end
	-- MW22 room-clearing clips (TIF.CQB): a queue of one-shots (breach, slicing the doorway, quick entry) that
	-- carry the soldier along their own root motion, and a waiting loop at the stack (breach pose) held while he
	-- stays on his spot. Movement waits for a one-shot; a fight breaks the waiting loop.
	local q = npc.tifCQBQueue
	if npc.tifCQBActUntil and now >= npc.tifCQBActUntil then
		npc.tifCQBActUntil = nil
		if npc.TIFSetSlim then npc:TIFSetSlim(false) end
		-- Done (or cut at its hold point): dropped, or the finished clip stayed on its last frame while he walked on
		-- (user, 0.20.1: the wide slice froze and slid).
		if npc.tifAct and npc.tifAct.name == npc.tifCQBActName and not (q and #q > 0) then TIF.Action.Clear(npc) end
		npc.tifCQBActName = nil
	end
	if not npc.tifCQBActUntil and q and #q > 0 and now >= (npc.tifCQBDelay or 0) then
		npc.tifCQBDelay = nil
		local item = table.remove(q, 1)
		-- (0.38.23) yawFn: aimed from where he stands now (sv_clear go_item); check: the clip's path is clear, else
		-- it's skipped (he goes in on foot)
		local yaw = item.yawFn and item.yawFn(npc) or item.yaw
		if item.check and not item.check(npc, yaw or npc:GetAngles().y) then
			if TIF.Debug then TIF.Debug("cqb: ", item.name, " skipped (path blocked)") end
			return
		end
		if yaw then npc:SetAngles(Angle(0, yaw, 0)) end
		local d = Act.Play(npc, item.name, item.opts or { root = true })
		if d then
			npc.tifCQBActUntil = now + d * (item.hold or 1)
			npc.tifCQBActName = item.name
			npc.tifCQBLoop = nil
			-- (2026-11-21) a narrower body while the clip takes him through the doorway with the others close by
			if npc.TIFSetSlim then npc:TIFSetSlim(true) end
		end
		if item.onStart then item.onStart(npc, now, d or 0) end
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
		-- (A wait clip built as a one-shot plays once and holds its last frame.)
		local wc = TIF.GTG.Clip(wait.name, npc.tifHomeHost)
		if wc and not wc.loop then Act.Play(npc, wait.name) else Act.Loop(npc, wait.name) end
		npc.tifCQBLoop = wait.name
	elseif npc.tifCQBLoop and (shooting or not atSpot or not wait or wait.name ~= npc.tifCQBLoop) then
		if npc.tifAct and npc.tifAct.name == npc.tifCQBLoop then Act.Clear(npc) end
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
		-- (the last stretch onto the spot: slid straight there, TIF.CQB.Glide)
		npc.tifStance = A.STANCE_STAND
	else
		npc.tifStance = A.STANCE_STAND
		local CQ = TIF.CQB
		-- Across the door being cleared: to the doorway, then slid through it (CQB.Through).
		local via = CQ and CQ.Through and CQ.Through(npc, cqS, t.goal, now)
		if via ~= "glide" then
			local goal = via or t.goal
			-- (a spot beside it for a while when the path there keeps failing: CQB.PathTrouble)
			local alt = npc.tifCQBAlt
			if alt and (now > alt.untilT or alt.for_ ~= goal) then npc.tifCQBAlt, alt = nil, nil end
			if alt then goal = alt.pos end
			local ok = Move.SetGoal(npc, goal, t.speed or "tactical", "cqb")
			if CQ and CQ.PathTrouble and not CQ.PathTrouble(npc, goal, ok, now) then npc.tifCQBFails = nil end
		end
	end
end

-- Pick a few nav points around the last known position, favouring the direction the enemy moved.
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
	for i = 1, math.min(3, #scored) do pts[#pts + 1] = scored[i].p end
	return pts
end

local function search(npc, now)
	local s = npc.tifSearch
	npc.tifMode = A.MODE_AIM
	npc.tifStance = A.STANCE_STAND
	npc.tifFire.want = false
	if not s then return end
	-- Overwatch (given by the squad search): watch the last known position from a distance.
	if s.watch then
		if npc:GetPos():DistToSqr(s.watch) > 80 * 80 then
			npc.tifAction = "search: to overwatch"
			npc.tifFace = s.pos + UP40
			if not Move.SetGoal(npc, s.watch, "tactical", "search") then s.watch = nil end
		else
			Move.Stop(npc)
			npc.tifAction = "search: overwatch"
			npc.tifStance = A.STANCE_CROUCH
			-- Sweep the area round the LKP.
			if now > (npc.tifNextLook or 0) then
				npc.tifNextLook = now + math.Rand(1.5, 3)
				local yaw = (s.pos - npc:GetPos()):Angle().y + math.Rand(-25, 25)
				local r = math.rad(yaw)
				npc.tifFace = npc:GetPos() + Vector(math.cos(r), math.sin(r), 0) * 400 + UP40
			end
		end
		return
	end
	if not s.points then s.points, s.i = search_points(s), 1 end
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
		-- Reached (or gave up on) this point: look around, then move on. MW19 body: a look at what's there
		-- (TIF.SearchMW runs it from the busy check; the point is done once it ends).
		if npc.tifAct and npc.tifAct.trans then return end -- still finishing the stop clip
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
	if not Move.SetGoal(npc, target, gait(npc, "close", 0, now), "search") then s.i = s.i + 1 end
end

-- Start searching round a position (used by bases sending a squad to sweep).
function B.StartSearch(npc, pos, dir, now)
	npc.tifSearch = { start = now, pos = Vector(pos), dir = dir, points = nil, i = 0 }
	set_aware(npc, AW.SEARCHING, now)
end

-- Main think ------------------------------------------------------------------

function B.Think(npc, dt)
	local now = CurTime()
	if not npc.tifPost then
		npc.tifPost = npc:GetPos()
		npc.tifPostYaw = npc:GetAngles().y
	end

	Prof.Begin("perception")
	Per.Update(npc, dt, now)
	-- Squad radio: report what this soldier sees, take in what the others reported.
	if npc.tifSquad then
		for _, c in pairs(npc.tifK.contacts) do
			if c.confirmed and (c.visible or c.source == "heard" or c.source == "hit" or c.source == "fired on") then
				TIF.Squad.Report(npc, c)
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
	Move.UpdateThreatAreas(npc)
	update_awareness(npc, c, now)

	local st = npc.tifAware
	local fighting = (st == AW.ENGAGED or st == AW.ALERTED) and c ~= nil
	-- Cover and prone belong to fights; outside one, get up and step out.
	local exiting = false
	if not fighting then
		if TIF.CoverBehave.In(npc) then exiting = TIF.CoverBehave.Exit(npc, "fight over") end
		if TIF.ProneB.Is(npc) then TIF.ProneB.GetUp(npc) end
	end

	local V = TIF.Vehicle
	-- (helicopter riders also carry tifVeh, so this comes first: the Glide seat code below isn't for them)
	if npc.tifHeli and TIF.AirRide and TIF.AirRide.Think(npc, now) then
		-- Riding in a helicopter, or getting out of it (tif/air/sv_air_ride.lua).
	elseif npc.tifVeh then
		-- In a vehicle: ride (the squad's vehicle plan decides when to get out).
		V.RideThink(npc, now)
	elseif npc.tifLeaving and V.LeaveThink(npc, now) then
		-- Getting out: nothing else until the clip ends.
	elseif npc.tifBoard and V.BoardThink(npc, now) then
		-- Walking to / climbing into a seat.
	elseif npc.tifSurrendered then
		TIF.Morale.SurrenderThink(npc, now)
	elseif npc.tifDowned then
		TIF.Casualty.DownThink(npc, now)
	elseif exiting then
		-- Stepping out of cover: nothing else until the clip ends.
		npc.tifFire.want = false
		npc.tifFace = nil
		Move.Stop(npc)
	elseif TIF.Shield and TIF.Shield.Busy(npc, now) then
		-- Holding a hostage (tactics/sv_shield.lua): the scene places and plays him.
	elseif TIF.MeleeMW and TIF.MeleeMW.Busy(npc, now) then
		-- MW19 body: a butt hit (stepping in, striking) or a paired melee fight (tactics/sv_melee_mw.lua).
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.ReactMW and TIF.ReactMW.Think(npc, now) then
		-- Flashbanged in the open (MW19 body): reacting, nothing else until the clip ends.
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.PassiveMW and TIF.PassiveMW.Busy(npc, now) then
		-- MW19 body: a reaction, putting an activity away, or checking a body.
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.BipodMW and npc.tifBipod and npc.tifAware ~= AW.ENGAGED and TIF.BipodMW.Update(npc, npc.tifPrimaryC, now) then
		-- MW19 LMG packing up off its bipod after the fight moved on.
	elseif TIF.SearchMW and TIF.SearchMW.Busy(npc, now) then
		-- MW19 body: a search look (under a table, over a wall, down a drop...).
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.HitsMW and TIF.HitsMW.Busy(npc, now) then
		-- MW19 body: staggering from a hit.
		npc.tifFire.want = false
		npc.tifFace = nil
	elseif TIF.ProneB.Update(npc, now) then
		-- Mid get-down / get-up: nothing else this think.
		npc.tifFire.want = false
	elseif TIF.ProneB.Is(npc) and not fighting then
		npc.tifFire.want = false
	elseif npc.tifLaunch and TIF.Launcher and TIF.Launcher.Think(npc, c, now) then
	elseif npc.tifMedic and TIF.Casualty.MedicThink(npc, c, now) then
		-- Going to / treating a downed squadmate.
	elseif TIF.Morale.BrokenThink(npc, c, now) then
		-- Broken: running or hiding (or just surrendered).
	elseif npc.tifCQB and not TIF.ProneB.Is(npc) then
		if TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "room clearing") end
		cqb(npc, c, now)
	elseif st == AW.ENGAGED and c then engage(npc, c, now)
	elseif st == AW.SEARCHING then search(npc, now)
	elseif st == AW.ALERTED and c then alerted(npc, c, now)
	elseif st == AW.SUSPICIOUS then investigate(npc, now)
	else duty(npc, now) end

	if not (st == AW.ENGAGED and c) then npc.tifFire.target = nil end
	if TIF.ProneB.Is(npc) then npc.tifStance = 2 end
	-- Room clearing: clients use the CQB movement set (MW19 body).
	local inCqb = npc.tifCQB ~= nil
	if npc.tifCqbNet ~= inCqb then
		npc.tifCqbNet = inCqb
		npc:SetNW2Bool("tif_cqb", inCqb)
	end
	-- Wading (0.35.2): water at the knees (1) or the waist (2). Clients use MW22's wading sets; sv_move caps the pace.
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

	-- Primary or secondary: long guns go to the sidearm up close and indoors; anyone draws it
	-- when the primary runs dry at close range; back to the primary when there's room.
	-- (Seated soldiers are handled by the drive-by code.)
	if not npc.tifVeh and not npc.tifBoard and not npc.tifLeaving and not npc.tifDowned and not npc.tifSurrendered then
		if fighting and c then
			local indoorsLongGun = npc.tifCQB ~= nil and npc.tifArch.secondaryBelow ~= nil
			Weapon.Choose(npc, npc:GetPos():Distance(c.pos), now, indoorsLongGun and { secondary = true } or nil)
		elseif not fighting then
			Weapon.Choose(npc, nil, now)
		end
	end
	-- Running or sprinting without shooting: gun down (relaxed carry and run legs), not an
	-- aimed jog. Cover entry, maneuvers and long advances all go through here.
	local mv = npc.tifMove
	-- (Not during a covering burst: the gun stays up for those few rounds, TIF.Weapon.CoveringBurst.)
	local coverFire = npc.tifCoverFire and now < npc.tifCoverFire.untilT
	if coverFire then npc.tifMode = A.MODE_AIM end
	-- A sprint never shoots (whatever asked for fire on the way: cover moves, maneuvers).
	if mv.goal and mv.speed == "sprint" and not coverFire and not exiting and npc.tifStance ~= 2 then
		npc.tifFire.want = false
	end
	if npc.tifMode == A.MODE_AIM and mv.goal and (mv.speed == "run" or mv.speed == "sprint")
		and not npc.tifFire.want and npc.tifStance ~= 2 and not exiting and not coverFire then
		npc.tifMode = A.MODE_RELAXED
		npc.tifStance = A.STANCE_STAND
	end
	low_ready(npc, now, coverFire)
	npc:SetTIFMode(npc.tifMode)
	if npc.tifKeepCrouchUntil then
		if CurTime() < npc.tifKeepCrouchUntil and npc.tifStance == A.STANCE_STAND and not TIF.CoverBehave.In(npc) then
			npc.tifStance = A.STANCE_CROUCH
		elseif CurTime() >= npc.tifKeepCrouchUntil then
			npc.tifKeepCrouchUntil = nil
		end
	end
	local cur = npc:GetTIFStance()
	-- Mid stance-change clip (mwk_*): a flip back waits until it's done, or the clip and the idle fought.
	local a = npc.tifAct
	-- (only the stance clips: mwk_ also holds the body checks, knockdown falls and recoveries)
	local inStanceClip = a and (string.sub(a.name, 1, 9) == "mwk_down_" or a.name == "mwk_up_8") and CurTime() - a.t0 < a.dur
	if cur ~= npc.tifStance and not inStanceClip then
		-- Standing still, stand <-> crouch: MW19's AI stance change instead of the idles cross-fading.
		if (cur == 0 or cur == 1) and (npc.tifStance == 0 or npc.tifStance == 1) and TIF.TransMW and TIF.TransMW.Stance then
			TIF.TransMW.Stance(npc, cur, npc.tifStance)
		end
		npc:SetTIFStance(npc.tifStance)
		if npc.tifStance ~= 2 then npc:TIFApplyStance() end
	end
	Prof.End()
end
