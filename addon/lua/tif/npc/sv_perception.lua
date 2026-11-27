local TIF = TIF
local AW = TIF.AWARE
local Budget = TIF.Budget
local Prof = TIF.Prof

local CurTime, IsValid, Vector = CurTime, IsValid, Vector
local math_sqrt, math_min, math_max, math_clamp = math.sqrt, math.min, math.max, math.Clamp
local math_cos, math_sin, math_rad, math_rand = math.cos, math.sin, math.rad, math.Rand
local pairs = pairs

TIF.Perception = TIF.Perception or {}
local P = TIF.Perception

local MAX_CHECKS = 3
local TOUCH_RANGE = 140
local TOUCH_RANGE_SQR = TOUCH_RANGE * TOUCH_RANGE
local SUSPICIOUS_AT = 0.35
local MEMORY = 240
local SHARE_RANGE = 1300
local SHARE_RANGE_SQR = SHARE_RANGE * SHARE_RANGE
local STALE_SIGHT = 0.6

function P.Init(npc)
	npc.tifK = { contacts = {} }
end

P.Profiles = {
	standard = { view = 1, detect = 1, ref = 1000, fov = 0 },
	long = { view = 1.6, detect = 1.5, ref = 1800, fov = 25 },
}
local cvProfile = CreateConVar("tif_perception", "long", FCVAR_ARCHIVE,
	"Soldier perception profile: long (see and spot far, the default) or standard (original, shorter)")
local cvDetect = CreateConVar("tif_detect_scale", "1", FCVAR_ARCHIVE, "Multiplier on how quickly soldiers spot someone (higher = faster)")

function P.Profile(npc, now)
	if npc.tifProfAt and now < npc.tifProfAt then return npc.tifProf end

	local name = npc.tifPerception or hook.Run("TIF_PerceptionProfile", npc) or cvProfile:GetString()
	npc.tifProf = P.Profiles[name] or P.Profiles.long
	npc.tifProfAt = now + 5
	return npc.tifProf
end

local function contact(npc, ent)
	local list = npc.tifK.contacts
	local c = list[ent]

	if not c then
		c = { ent = ent, meter = 0, confirmed = false, visible = false, seenAt = -math.huge, heardAt = -math.huge,
			pos = ent:GetPos(), vel = Vector(), unc = 0 }
		list[ent] = c
	end

	return c
end

P.Contact = contact

local function rand2d(scale)
	local a = math.Rand(0, math.pi * 2)
	local r = math.Rand(0.3, 1) * scale
	return Vector(math.cos(a) * r, math.sin(a) * r, 0)
end

local traceOut = {}
local traceData = { mask = MASK_BLOCKLOS, filter = {}, output = traceOut }
local function line_clear(from, to, a, b)
	traceData.start, traceData.endpos = from, to
	traceData.filter[1], traceData.filter[2] = a, b
	return not util.TraceLine(traceData).Hit
end

function P.CanSee(npc, eye, ent)
	if not Budget.Take("trace", 1) then return nil end
	if line_clear(eye, TIF.EyeOf(ent), npc, ent) then return true end
	if not Budget.Take("trace", 1) then return nil end

	return line_clear(eye, ent:WorldSpaceCenter(), npc, ent)
end

local function stance_factor(ent)
	if ent.TIFSoldier then return ent:GetTIFStance() == 1 and 0.6 or 1 end

	if ent:IsPlayer() then
		if ent.IsProne and ent:IsProne() then return 0.35 end
		if ent:Crouching() then return 0.6 end
	end

	return 1
end

P.Filters = P.Filters or {}
local RANK = { fight = 0, cover = 1, ignore = 2 }
function P.Engage(npc, e)
	local worst = "fight"
	for owner, fn in pairs(P.Filters) do
		local ok, r = pcall(fn, npc, e)
		if not ok then
			TIF.Error("Engage filter '", tostring(owner), "': ", tostring(r))
			P.Filters[owner] = nil
		elseif RANK[r] and RANK[r] > RANK[worst] then
			worst = r
		end
	end

	return worst
end

local CAND_OUT, CAND_POOL = {}, {}
local function by_d2(a, b)
	return a.d2 < b.d2
end

local function candidates(npc, eye, maxD2)
	local count = 0
	local filtered = next(P.Filters) ~= nil
	local hostile = TIF.REL_HOSTILE
	local isLive, relation = TIF.IsLiveCombatant, TIF.Relation
	local function consider(e)
		if e == npc then return end

		local d2 = eye:DistToSqr(e:GetPos())
		if d2 < maxD2 and isLive(e) and relation(npc, e) == hostile
			and not (filtered and P.Engage(npc, e) == "ignore") then
			count = count + 1
			local slot = CAND_POOL[count]

			if not slot then
				slot = {}
				CAND_POOL[count] = slot
			end

			slot.ent, slot.d2 = e, d2
			CAND_OUT[count] = slot
		end
	end

	for _, ply in player.Iterator() do
		consider(ply)
	end

	local soldiers = TIF.Soldiers
	for i = 1, #soldiers do
		local s = soldiers[i]
		if IsValid(s) then
			consider(s)
		end
	end

	if TIF.NPCs and TIF.HL2NPCsOn and TIF.HL2NPCsOn() then
		local npcs = TIF.NPCs
		for i = 1, #npcs do
			local e = npcs[i]
			if IsValid(e) then
				consider(e)
			end
		end
	end

	for i = #CAND_OUT, count + 1, -1 do
		CAND_OUT[i] = nil
	end

	if count > 1 then
		table.sort(CAND_OUT, by_d2)
	end

	return CAND_OUT, count
end

function P.Update(npc, dt, now)
	local K, arch = npc.tifK, npc.tifArch
	local eye = TIF.EyeOf(npc)
	local fwd = npc:GetForward()
	local aware = npc.tifAware or AW.UNAWARE
	local prof = P.Profile(npc, now)
	local fov = aware >= AW.ALERTED and arch.fov or (arch.fovUnaware + prof.fov)
	local cosHalf = math_cos(math_rad(fov * 0.5))
	local heightened = (npc.tifHeightenedUntil or 0) > now
	local blind = (npc.tifBlindUntil or 0) > now
	local vd = arch.viewDist * TIF.ViewScale() * prof.view
	local detectK = math_max(0.05, cvDetect:GetFloat()) * prof.detect
	local cand, candN

	if blind then
		candN = 0
	else
		cand, candN = candidates(npc, eye, vd * vd)
	end

	local checked = 0
	for i = 1, candN do
		local cd = cand[i]
		local e = cd.ent
		local c = K.contacts[e]
		local isPrimary = npc.tifPrimary == e
		if checked >= MAX_CHECKS and not isPrimary then break end

		local to = e:WorldSpaceCenter() - eye
		to:Normalize()
		local dotFwd = to:Dot(fwd)
		local touch = cd.d2 < TOUCH_RANGE_SQR

		if touch or dotFwd >= cosHalf then
			checked = checked + 1
			local vis = P.CanSee(npc, eye, e)

			if vis == nil then
			elseif vis then
				c = c or contact(npc, e)
				c.lastCheck = now
				local dist = math_sqrt(cd.d2)
				local speed = e:GetVelocity():Length2D()
				local moveF = speed > 150 and 1.5 or (speed > 30 and 1.0 or 0.7)
				local periph = dotFwd > 0.85 and 1 or 0.55
				local awareF = aware >= AW.ALERTED and 2.2 or (heightened and 1.6 or (aware == AW.SUSPICIOUS and 1.3 or 0.8))
				local distF = math_clamp(prof.ref / math_max(dist, 1), 0.15, 3) ^ 0.8
				local rate = (1 / arch.detectTime) * distF * stance_factor(e) * moveF * periph * awareF * detectK
				c.meter = touch and 1 or math_min(1, c.meter + rate * dt)

				if c.meter >= 1 then
					if not c.confirmed or (now - c.seenAt) > 3 then
						c.reacquired = now
					end

					c.confirmed = true
					c.visible = true
					c.seenAt = now
					c.pos = e:GetPos()
					c.vel = e:GetVelocity()
					c.unc = 0
					c.lostAt = nil
					c.source = "sight"
				else
					c.suspectPos = e:GetPos() + rand2d((1 - c.meter) * 180)
					c.suspectAt = now
				end
			elseif c then
				c.lastCheck = now
				c.visible = false
			end
		elseif c then
			c.visible = false
		end
	end

	for e, c in pairs(K.contacts) do
		if not TIF.IsLiveCombatant(e) then
			if npc.tifPrimary == e and c.confirmed and (now - c.seenAt) < 3 and TIF.IsDead(e) then
				TIF.Say(npc, "kill", 0.6)
			end

			K.contacts[e] = nil
		else
			if c.visible and (now - (c.lastCheck or 0)) > STALE_SIGHT then
				c.visible = false
			end

			if not c.visible then
				if c.confirmed and not c.lostAt and c.seenAt > -math.huge then
					c.lostAt = now
					local v = Vector(c.vel)
					v.z = 0
					c.dir = v:LengthSqr() > 100 and v:GetNormalized() or nil
				end

				if not c.confirmed then
					c.meter = math.max(0, c.meter - 0.25 * dt)
				end

				local since = now - math.max(c.seenAt, c.heardAt)
				c.unc = math.min(1200, (c.baseUnc or 0) + since * math.min(220, c.vel:Length2D() + 60))

				if since > MEMORY and not c.confirmed and c.meter <= 0 then
					K.contacts[e] = nil
				end
			end
		end
	end
end

function P.Primary(npc, now)
	local best, bestScore
	local pos = npc:GetPos()

	for e, c in pairs(npc.tifK.contacts) do
		if c.confirmed then
			local age = now - math.max(c.seenAt, c.heardAt)
			local score = (c.visible and 1000 or 0) - age * 12 - pos:Distance(c.pos) / 40

			if e == npc.tifPrimary then
				score = score + 150
			end

			if npc.tifPreferPlayers and IsValid(e) and e:IsPlayer() then
				score = score + npc.tifPreferPlayers
			end

			if not bestScore or score > bestScore then
				best, bestScore = c, score
			end
		end
	end

	return best
end

function P.Suspect(npc, now)
	local best
	for _, c in pairs(npc.tifK.contacts) do
		if not c.confirmed and c.meter >= SUSPICIOUS_AT and (now - (c.suspectAt or -99)) < 2 then
			if not best or c.meter > best.meter then
				best = c
			end
		end
	end

	return best
end

function P.Stimulus(npc, pos, kind, now)
	npc.tifStim = { pos = pos, kind = kind, time = now }
end

function P.Hear(npc, kind, pos, d2, src, faction)
	local now = CurTime()
	local rel = TIF.FactionRelation(npc:GetTIFFaction(), faction)

	if rel == TIF.REL_ALLY and IsValid(src) and src:IsPlayer() then return end

	local dist = math.sqrt(d2)
	if kind == "gunfire" then
		if rel == TIF.REL_HOSTILE and IsValid(src) and TIF.IsLiveCombatant(src) then
			local c = contact(npc, src)
			if not c.visible then
				local unc = math.Clamp(dist * 0.12, 40, 500)
				c.pos = pos + rand2d(unc)
				c.baseUnc = unc
				c.heardAt = now
				c.lostAt = c.lostAt or now
				c.source = "heard"
			end

			if dist < 1600 then
				c.confirmed = true
			end

			P.Stimulus(npc, c.pos, "gunfire", now)
			npc.tifHeardAt = now
		elseif rel == TIF.REL_ALLY and dist < 1500 then
			P.Stimulus(npc, pos, "ally_fire", now)
		elseif rel ~= TIF.REL_ALLY and not (IsValid(src) and src:IsPlayer() and TIF.IgnorePlayers()) then
			P.Stimulus(npc, pos, "gunfire", now)
		end
	elseif kind == "footstep" then
		if rel == TIF.REL_HOSTILE and TIF.IsLiveCombatant(src) then
			local c = contact(npc, src)
			if not c.visible then
				c.suspectPos = pos + rand2d(math.Clamp(dist * 0.2, 30, 150))
				c.suspectAt = now
				c.meter = math.max(c.meter, SUSPICIOUS_AT)
			end

			P.Stimulus(npc, c.suspectPos or pos, "footstep", now)
		end
	elseif kind == "explosion" then
		P.Stimulus(npc, pos, "explosion", now)
	end
end

function P.OnHurt(npc, attacker)
	if not IsValid(attacker) or not TIF.IsLiveCombatant(attacker) then return end
	if TIF.Relation(npc, attacker) ~= TIF.REL_HOSTILE then return end

	local now = CurTime()
	local c = contact(npc, attacker)
	c.confirmed = true

	if not c.visible then
		local dist = npc:GetPos():Distance(attacker:GetPos())
		local unc = math.min(300, dist * 0.15)
		c.pos = attacker:GetPos() + rand2d(unc)
		c.baseUnc = unc
		c.heardAt = now
		c.lostAt = c.lostAt or now
		c.source = "hit"
	end

	P.Stimulus(npc, c.pos, "hit", now)
	npc.tifHurtAt = now
end

function P.OnSuppressed(npc, shooter, srcPos)
	if not TIF.IsLiveCombatant(shooter) or TIF.Relation(npc, shooter) ~= TIF.REL_HOSTILE then
		return
	end

	local now = CurTime()
	local c = contact(npc, shooter)
	c.confirmed = true

	if not c.visible then
		local unc = math.Clamp(npc:GetPos():Distance(srcPos) * 0.08, 60, 400)
		c.pos = srcPos + rand2d(unc)
		c.baseUnc = unc
		c.heardAt = now
		c.lostAt = c.lostAt or now
		c.source = "fired on"
	end

	P.Stimulus(npc, c.pos, "fired_on", now)
end

function P.Share(npc, c)
	local now = CurTime()
	local pos = npc:GetPos()
	local fac = npc:GetTIFFaction()
	local soldiers = TIF.Soldiers

	for i = 1, #soldiers do
		local ally = soldiers[i]
		if ally ~= npc and IsValid(ally) and not ally.tifDead and ally:GetTIFFaction() == fac
			and pos:DistToSqr(ally:GetPos()) < SHARE_RANGE_SQR then
			local ac = contact(ally, c.ent)
			if not ac.visible then
				ac.confirmed = true
				ac.pos = c.pos + rand2d(64)
				ac.vel = Vector(c.vel)
				ac.baseUnc = 64
				ac.heardAt = now
				ac.lostAt = ac.lostAt or now
				ac.source = "callout"
				P.Stimulus(ally, ac.pos, "callout", now)
			end
		end
	end
end

function P.Reveal(ent)
	local now = CurTime()
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) and not npc.tifDead and TIF.Relation(npc, ent) == TIF.REL_HOSTILE then
			local c = contact(npc, ent)
			c.confirmed, c.meter, c.seenAt, c.pos, c.vel, c.unc, c.lostAt = true, 1, now, ent:GetPos(), ent:GetVelocity(), 0, nil
			c.source = "dev"
		end
	end
end

function P.ForgetSight()
	local now = CurTime()
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) and npc.tifK then
			for _, c in pairs(npc.tifK.contacts) do
				if c.confirmed then
					c.visible = false
					c.seenAt = math.min(c.seenAt, now - (npc.tifArch.loseContact + 0.5))
					c.heardAt = math.min(c.heardAt, c.seenAt)
					c.lostAt = c.seenAt
				end
			end

			npc.tifBlindUntil = now + 3
		end
	end
end
