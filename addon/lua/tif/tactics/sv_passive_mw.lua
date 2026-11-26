local TIF = TIF
local Act = TIF.Action
local Move = TIF.Move
local AW = TIF.AWARE

TIF.PassiveMW = TIF.PassiveMW or {}
local P = TIF.PassiveMW

P.ACTIVITIES = { "smoke", "phone", "water" }

P.ACTIVITY_GROUPS = {
	{ "smoke" }, { "phone" }, { "water" },

	{ "hum1", "hum2" }, { "radio1", "radio2", "radio3", "radio4" }, { "look1", "look2", "look3" },
	{ "scratch1", "scratch2", "scratch3", "scratch4", "scratch5", "scratch6", "scratch7", "scratch8" },
	{ "stretch1", "stretch2", "stretch3", "stretch4" },
}
P.START_AFTER = { 8, 35 }

P.TAKE_CHANCE = 0.65
P.SMART_CHANCE = 0.75
P.REACT_DELAY = { 0.05, 0.5 }
P.CALM_DELAY = { 0.4, 2.5 }
P.LOOP_FOR = { 15, 45 }
P.COOLDOWN = { 25, 70 }
P.ALARM_RADIUS = 1500

local function has(npc, name)
	return npc.tifHomeHost and TIF.GTG.Clip(name, npc.tifHomeHost) ~= nil
end

function P.Use(npc)
	local home = npc.tifHomeHost
	if not home or not TIF.GTG.IsVB(home) then return false end

	if npc.tifMwPassive == nil then
		npc.tifMwPassive = has(npc, "mwa_idle")
	end

	return npc.tifMwPassive
end

local function moving(npc)
	return npc.loco and npc.loco:GetVelocity():Length2D() > 20
end

local function busy(npc, now, d, kind, after)
	npc.tifPassiveBusy = { untilT = now + (d or 0), kind = kind, after = after }
end

local function put_away(npc, now, hurry, startled, threatPos)
	local a = npc.tifActivity
	if not a then return false end

	npc.tifActivity = nil
	npc.tifNextActivity = now + math.Rand(P.COOLDOWN[1], P.COOLDOWN[2])
	Move.Stop(npc)
	local d

	if a.smart and TIF.SmartMW then
		if a.phase == "exit" then
			d = math.max(0, a.untilT - now)
		else
			d = TIF.SmartMW.Leave(npc, a, now, startled, threatPos, hurry)
		end
	elseif a.phase == "end" then
		d = math.max(0, a.untilT - now)
	else
		d = Act.Play(npc, "mwx_" .. a.name .. "_end", { rate = hurry and 1.6 or 1, clear = true })
	end

	if d and d > 0 then
		busy(npc, now, d, "away")

		if hurry then
			npc.tifReactUntil = math.max(npc.tifReactUntil or 0, now + d)
		end

		return true
	end

	Act.Clear(npc)
	return false
end

P.PutAway = put_away

function P.Duty(npc, now, still)
	if not P.Use(npc) then return false end

	local a = npc.tifActivity
	if not still then
		npc.tifStillSince = nil
		return a ~= nil and put_away(npc, now, false)
	end

	npc.tifStillSince = npc.tifStillSince or now
	local SM = TIF.SmartMW

	if not a and SM and not npc.tifSmartChecked then
		npc.tifSmartChecked = true

		if now - (npc.GetCreationTime and npc:GetCreationTime() or now) < 6 and math.random() < 0.7 then
			for _, s in ipairs(SM.Find(npc, npc.tifPost or npc:GetPos(), npc.tifPostYaw)) do
				if s.kind == "sit" then
					npc.tifActivity = SM.Start(npc, s, now, true)
					if npc.tifActivity then return true end
				end
			end
		end
	end

	if not a then
		if (npc.tifHeightenedUntil or 0) > now or now < (npc.tifNextActivity or 0) then
			return false
		end

		if now - npc.tifStillSince < (npc.tifStillNeed or math.Rand(P.START_AFTER[1], P.START_AFTER[2])) then
			npc.tifStillNeed = npc.tifStillNeed or math.Rand(P.START_AFTER[1], P.START_AFTER[2])
			return false
		end

		npc.tifStillNeed = nil

		if math.random() > P.TAKE_CHANCE then
			npc.tifNextActivity = now + math.Rand(P.COOLDOWN[1], P.COOLDOWN[2]) * 0.5
			return false
		end

		if SM and math.random() < P.SMART_CHANCE then
			local spots = SM.Find(npc, npc.tifPost or npc:GetPos(), npc.tifPostYaw)
			if #spots > 0 then
				local s = spots[math.random(#spots)]
				npc.tifActivity = SM.Start(npc, s, now, false)

				if npc.tifActivity then
					npc.tifAction = "duty: " .. s.kind
					npc.tifFace = nil
					return true
				end
			end
		end

		local groups = {}
		for _, g in ipairs(P.ACTIVITY_GROUPS) do
			local ok = {}
			for _, n in ipairs(g) do
				if has(npc, "mwx_" .. n .. "_start") and has(npc, "mwx_" .. n .. "_loop") then
					ok[#ok + 1] = n
				end
			end

			if #ok > 0 then
				groups[#groups + 1] = ok
			end
		end

		if #groups == 0 then return false end

		local g = groups[math.random(#groups)]
		local name = g[math.random(#g)]
		local d = Act.Play(npc, "mwx_" .. name .. "_start")
		if not d then return false end

		npc.tifActivity = { name = name, phase = "start", untilT = now + d, loopUntil = now + d + math.Rand(P.LOOP_FOR[1], P.LOOP_FOR[2]) }
		npc.tifAction = "duty: " .. name
		npc.tifFace = nil
		return true
	end

	npc.tifFace = nil
	npc.tifAction = "duty: " .. a.name

	if a.smart and SM then
		if SM.Step(npc, a, now, math.Rand(P.LOOP_FOR[1], P.LOOP_FOR[2]) * 1.5) then
			return true
		end

		npc.tifActivity = nil
		npc.tifNextActivity = now + math.Rand(P.COOLDOWN[1], P.COOLDOWN[2])
		return false
	end

	if a.phase == "start" and now >= a.untilT then
		local lc = TIF.GTG.Clip("mwx_" .. a.name .. "_loop", npc.tifHomeHost)
		if lc and not lc.loop then
			local d = Act.Play(npc, "mwx_" .. a.name .. "_loop") or 0
			a.loopUntil = now + d
		else
			Act.Loop(npc, "mwx_" .. a.name .. "_loop")
		end

		a.phase = "loop"
	elseif a.phase == "loop" and now >= a.loopUntil then
		local d = Act.Play(npc, "mwx_" .. a.name .. "_end", { clear = true }) or 0
		a.phase, a.untilT = "end", now + d
	elseif a.phase == "end" and now >= a.untilT then
		npc.tifActivity = nil
		npc.tifNextActivity = now + math.Rand(P.COOLDOWN[1], P.COOLDOWN[2])
		Act.Clear(npc)
		return false
	end

	return true
end

local function in_cqb(npc)
	return npc.tifCQB ~= nil or (npc.tifSquad ~= nil and npc.tifSquad.cqb ~= nil)
end

P.InCQB = in_cqb

function P.Busy(npc, now)
	local pend = npc.tifPendingReact
	if pend and now >= pend.at then
		npc.tifPendingReact = nil

		if not npc.tifPassiveBusy and not npc.tifAct and npc.tifAware ~= AW.ENGAGED and not in_cqb(npc) then
			pend.fn(now)
		end
	end

	local r = npc.tifPassiveBusy
	if r then
		if r.kind == "react" and npc.tifAware == AW.ENGAGED and r.engagedOk ~= true then
			npc.tifPassiveBusy = nil
			Act.Clear(npc)
			return false
		end

		if now < r.untilT then return true end

		npc.tifPassiveBusy = nil

		if r.after then
			r.after(npc, now)
		end

		return false
	end

	if npc.tifActivity and npc.tifAware ~= AW.UNAWARE then
		local c, stim = npc.tifPrimaryC, npc.tifStim
		local threat = (c and c.pos) or (stim and stim.pos)
		return put_away(npc, now, npc.tifAware == AW.ENGAGED or npc.tifAware == AW.ALERTED, true, threat)
	end

	return false
end

local function dir_to(npc, pos)
	if not pos then return 8 end

	local d = math.AngleDifference((pos - npc:GetPos()):Angle().y, npc:GetAngles().y)
	if math.abs(d) <= 45 then return 8 end
	if math.abs(d) >= 135 then return 2 end

	return d > 0 and 4 or 6
end

P.NEWENEMY_R = 600
P.POINT_R = 900
P.POINT_SQUAD_COOLDOWN = 25

local function dir8(npc, pos)
	local d = math.AngleDifference((pos - npc:GetPos()):Angle().y, npc:GetAngles().y)
	local a = math.abs(d)
	if a <= 22.5 then return "8" end
	if a >= 157.5 then return d > 0 and "2l" or "2r" end
	if a <= 67.5 then return d > 0 and "7" or "9" end
	if a <= 112.5 then return d > 0 and "4" or "6" end

	return d > 0 and "1" or "3"
end

local function dir_num(npc, pos)
	return (string.gsub(dir8(npc, pos), "^2[lr]$", "2"))
end

local GRADE = { footstep = "sm", gunfire = "smed", explosion = "smed", man_down = "smed", alarm = "smed" }

P.MW22_SHARE = 0.5

local function mw22_variant(npc, grade, posture, mv, pos)
	local kind = (grade == "lg") and "threat" or "cur"
	local d = dir_to(npc, pos)
	local ds = tostring(d)

	if d == 2 and pos then
		ds = math.AngleDifference((pos - npc:GetPos()):Angle().y, npc:GetAngles().y) > 0 and "2l" or "2r"
	end

	for _, n in ipairs({ "mwr2_" .. posture .. "_" .. mv .. "_" .. kind .. "_" .. ds,
		"mwr2_" .. posture .. "_idle_" .. kind .. "_" .. ds }) do
		if has(npc, n) then return n end
	end

	return nil
end

local function react(npc, now, grade, pos, posture, opts)
	local mv = moving(npc) and "walk" or "idle"
	local name = "mwr_" .. posture .. "_" .. mv .. "_" .. grade .. "_" .. dir_to(npc, pos)

	if not has(npc, name) then
		name = "mwr_" .. posture .. "_idle_" .. grade .. "_" .. dir_to(npc, pos)
	end

	if grade ~= "look" and math.random() < P.MW22_SHARE then
		name = mw22_variant(npc, grade, posture, mv, pos) or name
	end

	if not has(npc, name) then return false end

	Move.Stop(npc)
	local rate = opts and opts.rate or 1
	local d = Act.Play(npc, name, { root = true, rate = rate, clear = true })
	if not d then return false end

	busy(npc, now, d, "react")
	npc.tifPassiveBusy.engagedOk = opts and opts.engagedOk
	npc.tifAction = "reacting (" .. grade .. ")"
	return true, d
end

function P.OnAware(npc, old, new, now)
	if not P.Use(npc) or npc.tifCov or npc.tifProne or npc.tifVeh or npc.tifDowned or npc.tifSurrendered then
		return
	end

	if in_cqb(npc) then
		npc.tifPendingReact = nil
		return
	end

	if npc.tifActivity then return end
	if npc.tifPassiveBusy then return end

	local calm = old == AW.UNAWARE and (npc.tifHeightenedUntil or 0) <= now
	local posture = calm and "patrol" or "alert"
	local stim = npc.tifStim
	local c = npc.tifPrimaryC

	local function later(delay, fn)
		npc.tifPendingReact = { at = now + math.Rand(delay[1], delay[2]), fn = fn }
	end

	if new == AW.SUSPICIOUS and old == AW.UNAWARE then
		local kind = stim and now - stim.time < 3 and stim.kind or nil
		local pos = stim and stim.pos
		later(P.REACT_DELAY, function(t) react(npc, t, GRADE[kind] or "sm", pos, posture) end)
	elseif new == AW.ALERTED and (old == AW.UNAWARE or old == AW.SUSPICIOUS) then
		local pos = c and c.pos or (stim and stim.pos)
		later(P.REACT_DELAY, function(t) react(npc, t, "lg", pos, posture) end)
	elseif new == AW.ENGAGED and old == AW.UNAWARE and calm then
		npc.tifPendingReact = nil

		local wait = math.max(0.3, (npc.tifReactUntil or now) - now)
		local name = "mwr_patrol_" .. (moving(npc) and "walk" or "idle") .. "_lg_" .. dir_to(npc, c and c.pos)
		local clip = has(npc, name) and TIF.GTG.Clip(name, npc.tifHomeHost)
		local rate = clip and math.Clamp(clip.dur / (wait + 0.5), 1.2, 2.4) or 1.6
		local ok, d = react(npc, now, "lg", c and c.pos, "patrol", { rate = rate, engagedOk = true })

		if ok then
			npc.tifReactUntil = math.max(npc.tifReactUntil or 0, now + d)
		end
	elseif new == AW.ENGAGED and (old == AW.SUSPICIOUS or old == AW.ALERTED) and c and not moving(npc)
		and npc:GetPos():DistToSqr(c.pos) < P.NEWENEMY_R * P.NEWENEMY_R and npc:GetTIFStance() ~= TIF.Anim.STANCE_CROUCH then
		npc.tifPendingReact = nil
		local name = "mwe_newenemy_" .. dir8(npc, c.pos)

		if has(npc, name) then
			local d = Act.Play(npc, name, { root = true, rate = 1.3, clear = true })
			if d then
				busy(npc, now, d, "react")
				npc.tifPassiveBusy.engagedOk = true
				npc.tifReactUntil = math.max(npc.tifReactUntil or 0, now + d * 0.7)
				npc.tifAction = "new enemy close"
			end
		end
	elseif new == AW.ENGAGED and (old == AW.SUSPICIOUS or old == AW.ALERTED) and c and not moving(npc)
		and npc:GetPos():DistToSqr(c.pos) > P.POINT_R * P.POINT_R and (npc.tifSupp or 0) < 0.2
		and npc:GetTIFStance() ~= TIF.Anim.STANCE_CROUCH then
		local sq = npc.tifSquad
		if sq and now < (sq.nextPointOut or 0) then return end

		local name = "mwe_point" .. (math.random() < 0.5 and "2" or "") .. "_" .. dir_num(npc, c.pos)
		if not has(npc, name) then
			name = "mwe_point_" .. dir8(npc, c.pos)
		end

		if has(npc, name) then
			npc.tifPendingReact = nil
			local d = Act.Play(npc, name, { root = true, rate = 1.4, clear = true })

			if d then
				if sq then
					sq.nextPointOut = now + P.POINT_SQUAD_COOLDOWN
				end

				busy(npc, now, d, "react")
				npc.tifPassiveBusy.engagedOk = true
				npc.tifReactUntil = math.max(npc.tifReactUntil or 0, now + d * 0.6)
				npc.tifAction = "pointing out contact"
				TIF.Say(npc, "contact", 0.9)
			end
		end
	elseif new == AW.SEARCHING and old == AW.ENGAGED and c and not moving(npc) and npc:GetTIFStance() ~= TIF.Anim.STANCE_CROUCH then
		later(P.REACT_DELAY, function(t)
			if moving(npc) or npc.tifAware ~= AW.SEARCHING then return end

			local name = "mwe_look" .. (math.random() < 0.5 and "2" or "") .. "_" .. dir_num(npc, c.pos)
			if not has(npc, name) then
				name = "mwe_look_" .. dir8(npc, c.pos)
			end

			if not has(npc, name) then return end

			local d = Act.Play(npc, name, { root = true, clear = true })
			if d then
				busy(npc, t, d, "react")
				npc.tifAction = "looking around"
			end
		end)
	elseif new == AW.UNAWARE and old ~= AW.UNAWARE and has(npc, "mwa_calm") then
		later(P.CALM_DELAY, function(t)
			if moving(npc) or npc.tifAware ~= AW.UNAWARE then return end

			local d = Act.Play(npc, "mwa_calm", { clear = true })
			if d then
				busy(npc, t, d, "react")
			end
		end)
	end
end

local INVESTIGATE = { "mwi_around", "mwi_middle", "mwi_up", "mwi_radio",

	"mwi_area1", "mwi_area2", "mwi_area3", "mwi_area4", "mwi_threat1", "mwi_threat2", "mwi_threat3" }

function P.Investigate(npc, now)
	if not P.Use(npc) then return false end

	local stim = npc.tifStim
	if stim and stim.kind == "man_down" and not stim.checked then
		stim.checked = true
		local n = "mwk_body" .. math.random(1, 4)
		local d = has(npc, n) and Act.Play(npc, n, { root = true, clear = true })
		npc.tifAction = "checking a body"
		local function alarm(s, t)
			s.tifHeightenedUntil = t + 120
			TIF.Say(s, "man_down", 1)

			for _, ally in ipairs(TIF.Soldiers) do
				if IsValid(ally) and ally ~= s and ally:GetTIFFaction() == s:GetTIFFaction()
					and ally:GetPos():DistToSqr(s:GetPos()) < P.ALARM_RADIUS ^ 2 and (ally.tifHeightenedUntil or 0) < t then
					ally.tifHeightenedUntil = t + 120
					TIF.Perception.Stimulus(ally, stim.pos, "alarm", t)
				end
			end
		end

		if d then
			busy(npc, now, d, "body", alarm)
		else
			alarm(npc, now)
		end

		return true
	end

	if now < (npc.tifNextInvestigateIdle or 0) then return npc.tifAct ~= nil end

	local pool = {}
	for _, n in ipairs(INVESTIGATE) do
		if has(npc, n) then
			pool[#pool + 1] = n
		end
	end

	if #pool == 0 then return false end

	local d = Act.Play(npc, pool[math.random(#pool)], { clear = true }) or 0
	npc.tifNextInvestigateIdle = now + d + math.Rand(1.5, 4)
	npc.tifAction = "look around"
	return true
end
