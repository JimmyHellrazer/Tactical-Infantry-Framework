local TIF = TIF
local Act = TIF.Action

TIF.MeleeMW = TIF.MeleeMW or {}
local M = TIF.MeleeMW

M.REACH = 62
M.STEP_REACH = 100
M.RUN_REACH = 170
M.RUN_SPEED = 140
M.HIT_RANGE = 78
M.COOLDOWN = { 2.5, 4 }
M.DMG_PLAYER, M.DMG_SOLDIER, M.DMG_OTHER = 30, 45, 45

M.FIGHT = {
	aw = { att = "mwm_fight_aw_att", def = "mwm_fight_aw_def", x = 109.2, y = -7.1, loser = "def" },
	dw = { att = "mwm_fight_dw_att", def = "mwm_fight_dw_def", x = 95.9, y = 1.0, loser = "att" },
}

M.FIGHT_CHANCE = 0.6
M.FIGHT_MIN, M.FIGHT_MAX = 50, 160
M.FIGHT_SNAP = 70
M.FIGHT_COOLDOWN = 20
M.ATT_WIN = 0.65

local function cvar(name, def, help)
	return CreateConVar(name, def, FCVAR_ARCHIVE, help)
end
local cvMelee = cvar("tif_melee", "1", "MW19 soldiers butt-stroke enemies up close (1/0)")
local cvFights = cvar("tif_melee_fights", "1", "MW19 soldiers wrestle enemy soldiers up close: paired melee fights (1/0)")

local function body_ok(npc)
	return IsValid(npc) and npc.TIFSoldier and not npc.tifDead and not npc.tifDying and npc.tifHomeHost
		and TIF.GTG.IsVB(npc.tifHomeHost) and Act.Clip(npc, "mwm_melee_1") ~= nil
end

local function free(npc, anyStance)
	return not (npc.tifAct or npc.tifVeh or npc.tifProne or npc.tifCov or npc.tifDowned or npc.tifSurrendered
		or npc.tifKnock or npc.tifMelee or npc.tifThrow or npc.tifBipod or npc.tifHeli or npc.tifShield)
		and (anyStance or npc:GetTIFStance() == TIF.Anim.STANCE_STAND)
end

local function is_pistol(npc)
	local w = npc.tifWep
	return w and TIF.GTG.WeaponKind(w.class) == "pistol"
end

local evCache = {}
local function events(clip, ev)
	local key = (clip.seq or "") .. ":" .. ev
	local out = evCache[key]
	if out then return out end
	out = {}
	for _, t in ipairs(clip.tags or {}) do
		if t[1] == "MoveEvent" and istable(t[4]) and t[4].MoveEvent == ev then out[#out + 1] = t[2] end
	end
	table.sort(out)
	evCache[key] = out
	return out
end
M.Events = events

local function flat_dist(a, b)
	local d = b:GetPos() - a:GetPos()
	d.z = 0
	return d:Length(), d
end

local function face_now(npc, pos)
	local to = pos - npc:GetPos()
	to.z = 0
	if to:LengthSqr() > 1 then npc:SetAngles(Angle(0, to:Angle().y, 0)) end
end

local function strike(npc, target, now)
	local m = npc.tifMelee
	local n = m.n
	local name = (m.pistol and "mwm_pmelee_" or "mwm_melee_") .. n
	face_now(npc, target:GetPos())
	local d = Act.Play(npc, name, { root = true, clear = true })
	if not d then npc.tifMelee = nil return end
	m.phase, m.clip, m.t0, m.dur = "strike", Act.Clip(npc, name), now, d
	m.hits, m.done = events(m.clip, "fire"), 0
	if #m.hits == 0 then m.hits = { 0.2 } end
	TIF.Say(npc, "attack", 0.3)
end

local function land(npc, target)
	if not IsValid(target) then return end
	local dist, to = flat_dist(npc, target)
	if dist > M.HIT_RANGE then return end
	to:Normalize()
	if to:Dot(npc:GetForward()) < 0.5 then return end
	local d = DamageInfo()
	local amount = target:IsPlayer() and M.DMG_PLAYER or (target.TIFSoldier and M.DMG_SOLDIER or M.DMG_OTHER)
	d:SetDamage(amount)
	d:SetDamageType(DMG_CLUB)
	d:SetAttacker(npc)
	d:SetInflictor(npc)
	d:SetDamagePosition(target:WorldSpaceCenter() + Vector(0, 0, 14))
	d:SetDamageForce(to * 9000)
	target:TakeDamageInfo(d)
	npc:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 75, math.random(95, 105))
	if target:IsPlayer() then
		target:ViewPunch(Angle(math.Rand(-10, -6), math.Rand(-8, 8), math.Rand(-4, 4)))
		target:SetVelocity(to * 180 + Vector(0, 0, 40))
	end
end

local function end_fight(npc)
	local m = npc.tifMelee
	npc.tifMelee = nil
	if m and m.fight then
		if npc.tifActLock == "melee" then npc.tifActLock = nil end
		if npc.tifAct and (npc.tifAct.name == m.clipName) then Act.Clear(npc) end
		if IsValid(npc) and m.group then npc:SetCollisionGroup(m.group) end
	end
end

local function start_fight(att, def, now)
	local which = math.random() < M.ATT_WIN * math.Clamp(0.6 + (att.tifArch.aggression or 0.5) * 0.8, 0.5, 1.3)
		* math.Clamp(att:Health() / math.max(1, def:Health()), 0.6, 1.4) and "aw" or "dw"
	local F = M.FIGHT[which]
	if not (Act.Clip(att, F.att) and Act.Clip(def, F.def)) then return false end

	local dyaw = (att:GetPos() - def:GetPos()):Angle().y
	local rad = math.rad(dyaw)
	local c, s = math.cos(rad), math.sin(rad)
	local spot = def:GetPos() + Vector(F.x * c - F.y * s, F.x * s + F.y * c, 0)
	if spot:DistToSqr(att:GetPos()) > M.FIGHT_SNAP * M.FIGHT_SNAP then return false end

	local g = util.TraceLine({ start = spot + Vector(0, 0, 30), endpos = spot - Vector(0, 0, 40), mask = MASK_NPCSOLID_BRUSHONLY })
	if not g.Hit or math.abs(g.HitPos.z - def:GetPos().z) > 14 then return false end

	local sp = Vector(spot.x, spot.y, g.HitPos.z)
	local room = util.TraceHull({ start = sp + Vector(0, 0, 4), endpos = sp + Vector(0, 0, 4), mins = Vector(-13, -13, 0),
		maxs = Vector(13, 13, 64), mask = MASK_NPCSOLID_BRUSHONLY })
	if room.StartSolid then return false end
	local path = util.TraceLine({ start = att:GetPos() + Vector(0, 0, 40), endpos = sp + Vector(0, 0, 40), mask = MASK_NPCSOLID_BRUSHONLY })
	if path.Hit then return false end
	TIF.Move.Stop(att)
	TIF.Move.Stop(def)
	att:SetPos(Vector(spot.x, spot.y, g.HitPos.z))
	att:SetAngles(Angle(0, dyaw + 180, 0))
	def:SetAngles(Angle(0, dyaw, 0))

	for _, s in ipairs({ att, def }) do
		s.tifReact, s.tifLook, s.tifActivity, s.tifPassiveBusy, s.tifFace = nil, nil, nil, nil, nil
		Act.Clear(s, true)
	end
	local da = Act.Play(att, F.att, { root = true, noTrace = true, lockOK = true })
	local dd = Act.Play(def, F.def, { root = true, noTrace = true, lockOK = true })
	if not (da and dd) then Act.Clear(att) Act.Clear(def) return false end
	att.tifActLock, def.tifActLock = "melee", "melee"
	local loser = F.loser == "att" and att or def
	local lclip = Act.Clip(loser, F.loser == "att" and F.att or F.def)
	local du = events(lclip, "melee_death")[1] or 0.75
	for _, e in ipairs({ { att, "att", F.att, da }, { def, "def", F.def, dd } }) do
		local npc = e[1]
		npc.tifMelee = { fight = which, role = e[2], partner = e[2] == "att" and def or att, clipName = e[3],
			t0 = now, dur = e[4], loser = loser, deathAt = now + (loser == npc and du * e[4] or 0),
			group = npc:GetCollisionGroup(), phase = "fight" }
		npc:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		npc.tifFire.want = false
	end
	att.tifMeleeFightAt, def.tifMeleeFightAt = now, now
	TIF.Say(att, "attack", 0.6)
	if TIF.Event then TIF.Event("melee", "paired fight ", which, ": ", att:EntIndex(), " vs ", def:EntIndex()) end
	return true
end

local function fight_think(npc, m, now)
	local p = m.partner

	if m.loserDown then
		local u = (now - m.t0) / math.max(0.01, m.dur)
		local fireU = not m.fired and events(Act.Clip(npc, m.clipName) or {}, "fire")[1]
		if fireU and u >= fireU then
			m.fired = true
			local def = npc.tifWep and npc.tifWep.def
			local snd = def and def.mw and def.mw.fire
			npc:EmitSound((snd and sound.GetProperties(snd) and snd) or (def and def.sound) or "Weapon_AR2.Single", 95, 100, 1, CHAN_WEAPON)
			npc:SetTIFShotTime(now)
		end
		if u >= 1 then end_fight(npc) return false end
		return true
	end

	if not IsValid(p) or p.tifDead or not p.tifMelee or p.tifMelee.partner ~= npc then
		end_fight(npc)
		return false
	end
	if m.loser == npc and now >= m.deathAt and not m.killed then
		m.killed = true
		p.tifMelee.loserDown = true
		npc.tifNoDeathClip = true
		local d = DamageInfo()
		d:SetDamage(npc:Health() + 50)
		d:SetDamageType(DMG_CLUB)
		d:SetAttacker(p)
		d:SetInflictor(p)
		d:SetDamagePosition(npc:WorldSpaceCenter())
		d:SetDamageForce(Vector())
		npc:TakeDamageInfo(d)
		return true
	end
	if now - m.t0 >= m.dur then
		end_fight(npc)
		return false
	end
	return true
end

function M.Busy(npc, now)
	local m = npc.tifMelee
	if not m then return false end
	if m.fight then return fight_think(npc, m, now) end
	local target = m.target
	if m.phase == "step" then
		if now - m.t0 >= m.dur then
			if IsValid(target) then strike(npc, target, now) else npc.tifMelee = nil return false end
		end
		return true
	end

	local u = (now - m.t0) / math.max(0.01, m.dur)
	while m.done < #m.hits and u >= m.hits[m.done + 1] do
		m.done = m.done + 1
		land(npc, target)
	end
	if u >= 1 or (npc.tifAct == nil and u > 0.2) then
		npc.tifMelee = nil
		npc.tifNextMelee = now + math.Rand(M.COOLDOWN[1], M.COOLDOWN[2])
		return false
	end
	return true
end

function M.Try(npc, c, now)
	if not (cvMelee:GetBool() and c and c.visible and IsValid(c.ent)) then return false end
	if now < (npc.tifNextMelee or 0) or not body_ok(npc) or not free(npc, true) then return false end
	local target = c.ent
	if npc.tifWep and TIF.GTG.WeaponKind(npc.tifWep.class) == "rpg" then return false end
	local dist, to = flat_dist(npc, target)
	if dist > M.RUN_REACH or math.abs(target:GetPos().z - npc:GetPos().z) > 30 then return false end
	npc.tifNextMelee = now + 0.5

	if cvFights:GetBool() and target.TIFSoldier and body_ok(target) and free(target, true) and dist > M.FIGHT_MIN and dist < M.FIGHT_MAX
		and TIF.Relation(npc, target) ~= TIF.REL_ALLY and now - (npc.tifMeleeFightAt or -99) > M.FIGHT_COOLDOWN
		and now - (target.tifMeleeFightAt or -99) > M.FIGHT_COOLDOWN and math.random() < M.FIGHT_CHANCE then
		if start_fight(npc, target, now) then return true end
	end

	if npc:GetTIFStance() ~= TIF.Anim.STANCE_STAND then return false end
	to:Normalize()
	local speed = npc.loco:GetVelocity():Length2D()
	local pistol = is_pistol(npc)
	local n = math.random(1, 4)
	local m = { target = target, pistol = pistol, n = n }
	if dist <= M.REACH then
		npc.tifMelee = m
		TIF.Move.Stop(npc)
		strike(npc, target, now)
		return npc.tifMelee ~= nil
	end
	local step
	if speed > M.RUN_SPEED and dist <= M.RUN_REACH then step = pistol and "mwm_prun_to_melee_" or "mwm_run_to_melee_"
	elseif dist <= M.STEP_REACH then step = pistol and "mwm_pto_melee_" or "mwm_to_melee_" end
	if not step then return false end
	TIF.Move.Stop(npc)
	face_now(npc, target:GetPos())
	local d = Act.Play(npc, step .. n, { root = true })
	if not d then return false end
	m.phase, m.t0, m.dur = "step", now, d
	npc.tifMelee = m
	npc.tifFire.want = false
	return true
end

M.PAIR_EVERY = 0.5
M.PAIR_CHANCE = 0.9

local function interruptible(npc)
	local a = npc.tifAct
	if not a then return true end
	return (a.trans or a.loop) and not npc.tifCov and not npc.tifCQBActUntil and not npc.tifActLock
end

local function pair_free(npc)
	if not body_ok(npc) or not interruptible(npc) then return false end
	return not (npc.tifVeh or npc.tifProne or npc.tifCov or npc.tifDowned or npc.tifSurrendered or npc.tifKnock
		or npc.tifMelee or npc.tifThrow or npc.tifBipod or npc.tifHeli or npc.tifShield)
end
M.PairFree = pair_free

function M.PairScan(now)
	if not (cvMelee:GetBool() and cvFights:GetBool()) then return end
	local list = {}
	for _, s in ipairs(TIF.Soldiers or {}) do
		if IsValid(s) and now - (s.tifMeleeFightAt or -99) > M.FIGHT_COOLDOWN and pair_free(s) then list[#list + 1] = s end
	end
	local used = {}
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			if not used[a] and not used[b] and TIF.Relation(a, b) ~= TIF.REL_ALLY then
				local dist = flat_dist(a, b)
				local engaged = a.tifPrimary == b or b.tifPrimary == a
				if engaged and dist > M.FIGHT_MIN and dist < M.FIGHT_MAX and math.abs(a:GetPos().z - b:GetPos().z) < 30 then
					local tr = util.TraceLine({ start = a:GetPos() + Vector(0, 0, 40), endpos = b:GetPos() + Vector(0, 0, 40),
						mask = MASK_NPCSOLID_BRUSHONLY })
					if not tr.Hit and math.random() < M.PAIR_CHANCE then

						local att, def = a, b
						if b.tifPrimary == a and a.tifPrimary ~= b then att, def = b, a end
						for _, s in ipairs({ att, def }) do
							if s.tifAct and (s.tifAct.trans or s.tifAct.loop) then Act.Clear(s) end
						end
						if start_fight(att, def, now) or start_fight(def, att, now) then
							used[a], used[b] = true, true
						end
					end
				end
			end
		end
	end
end

timer.Create("tif_melee_pairs", M.PAIR_EVERY, 0, function()
	if TIF.AIDisabled and TIF.AIDisabled() then return end
	local ok, err = pcall(M.PairScan, CurTime())
	if not ok then TIF.Error("Melee pairs: ", tostring(err)) end
end)

hook.Add("EntityTakeDamage", "tif_melee_fight", function(ent, dmg)
	local m = ent.tifMelee
	if not (m and m.fight) then return end
	local att = dmg:GetAttacker()
	if IsValid(att) and att == m.partner then return end

	local p = m.partner
	end_fight(ent)
	if IsValid(p) and p.tifMelee and p.tifMelee.partner == ent then end_fight(p) end
end)
