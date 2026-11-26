local TIF = TIF
TIF.Launcher = TIF.Launcher or {}
local L = TIF.Launcher

local cvRockets = CreateConVar("tif_rpg_rockets", "2", FCVAR_ARCHIVE, "Rockets an AT gunner carries for a reusable launcher (disposables always 1)")
local cvLone = CreateConVar("tif_rpg_lone_chance", "0.1", FCVAR_ARCHIVE, "Chance an AT gunner fires at a single exposed soldier (per check)")

L.RANGE = { 500, 2600 }
L.GAP = { 25, 40 }
L.FIRST = { 4, 10 }
L.SQUAD_GAP = 15
L.TARGET_GAP = 20
L.CHECK = 1.5
L.LONE_EVERY = 4
L.CLUSTER = 3
L.CLUSTER_R = 250
L.DUG_IN = 8
L.SETTLE = { 0.9, 1.3 }
L.HOLD_AFTER = 0.6
L.FRIENDLY_R = 320
L.GIVE_UP = 7
L.LOST = 2
L.WARN_R = 2600

function L.Rockets(def)
	if def and def.disposable then return 1 end
	return math.max(0, cvRockets:GetInt())
end

local function launcher(npc)
	local w = npc.tifArms and npc.tifArms.launcher
	if not w or (w.rockets or 0) <= 0 then return nil end
	return w
end

function L.IsVehicle(e)
	if not IsValid(e) then return false end
	if e:IsVehicle() or e.tifVeh or e.IsGlideVehicle or e.tifHeli then return true end
	local c = e:GetClass()
	if string.find(c, "glide", 1, true) or string.find(c, "heli", 1, true) or string.find(c, "lvs_", 1, true) then return true end
	if e:IsPlayer() and e:InVehicle() then return true end
	return false
end

local function hostiles_near(npc, pos, r)
	local n, r2 = 0, r * r
	for _, o in ipairs(TIF.Soldiers or {}) do
		if IsValid(o) and o ~= npc and not o.tifDead and o:GetPos():DistToSqr(pos) < r2
			and TIF.Relation(npc, o) == TIF.REL_HOSTILE then n = n + 1 end
	end
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and p:GetPos():DistToSqr(pos) < r2 and TIF.Relation(npc, p) == TIF.REL_HOSTILE then n = n + 1 end
	end
	return n
end

local function friendly_near(npc, pos, r)
	local r2 = r * r
	for _, o in ipairs(TIF.Soldiers or {}) do
		if IsValid(o) and o ~= npc and not o.tifDead and o:GetPos():DistToSqr(pos) < r2
			and TIF.Relation(npc, o) ~= TIF.REL_HOSTILE then return true end
	end
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and p:GetPos():DistToSqr(pos) < r2 and TIF.Relation(npc, p) ~= TIF.REL_HOSTILE then return true end
	end
	return false
end

local function outdoors(npc)
	local p = npc:GetPos() + Vector(0, 0, 64)
	local tr = util.TraceLine({ start = p, endpos = p + Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY })
	return not tr.Hit or tr.HitSky
end

local function clear_line(npc, e, aim)
	local src = npc:GetPos() + Vector(0, 0, 60)
	local tr = util.TraceLine({ start = src, endpos = aim, filter = npc, mask = MASK_SHOT })
	if tr.Entity == e then return true end
	return tr.HitPos:DistToSqr(aim) < 90 * 90
end

function L.AimAt(e, kind)
	if not IsValid(e) then return nil end
	if kind == "vehicle" then return e:WorldSpaceCenter() end
	return e:GetPos() + Vector(0, 0, 14)
end

local function track(npc, e, now)
	local t = npc.tifLaunchTrack
	local hp = e:Health()
	if not t or t.ent ~= e then
		t = { ent = e, since = now, hp = hp }
		npc.tifLaunchTrack = t
	elseif hp < t.hp then
		t.since, t.hp = now, hp
	end
	return now - t.since
end

function L.Worth(npc, c, now)
	local e = c.ent
	if not IsValid(e) then return nil end
	if L.IsVehicle(e) then return "vehicle" end
	if hostiles_near(npc, c.pos, L.CLUSTER_R) >= L.CLUSTER then return "cluster" end
	if track(npc, e, now) >= L.DUG_IN then return "dug in" end
	if now >= (npc.tifLaunchLoneAt or 0) then
		npc.tifLaunchLoneAt = now + L.LONE_EVERY
		if math.random() < cvLone:GetFloat() then return "lone" end
	end
	return nil
end

function L.Blocked(npc, c, now)
	if npc.tifCQB or npc.tifVeh or npc.tifBoard or npc.tifDowned or npc.tifSurrendered then return "busy" end
	if TIF.ProneB and TIF.ProneB.Is(npc) then return "prone" end
	if npc.tifBipod or npc.tifThrow or npc.tifShield or npc.tifMelee then return "busy" end
	if TIF.Morale and TIF.Morale.Shaken(npc) then return "shaken" end
	if now < (npc.tifLaunchNext or 0) then return "cooldown" end
	local sq = npc.tifSquad
	if sq and now < (sq.tifLaunchNext or 0) then return "squad cooldown" end
	if not c or not c.visible or not IsValid(c.ent) then return "no target" end
	local d = npc:GetPos():Distance(c.pos)
	if d < L.RANGE[1] or d > L.RANGE[2] then return "range" end
	return nil
end

function L.Consider(npc, c, now)
	local w = launcher(npc)
	if not w or npc.tifLaunch or npc.tifSwitch then return false end
	if now < (npc.tifLaunchCheck or 0) then return false end
	npc.tifLaunchCheck = now + L.CHECK
	if not npc.tifLaunchNext then
		npc.tifLaunchNext = now + math.Rand(L.FIRST[1], L.FIRST[2])
		return false
	end
	if L.Blocked(npc, c, now) then return false end
	local e = c.ent
	local kind = L.Worth(npc, c, now)
	if not kind then return false end
	if kind ~= "vehicle" and now < (e.tifRocketedAt or 0) + L.TARGET_GAP then return false end
	if not outdoors(npc) then return false end
	local aim = L.AimAt(e, kind)
	if not clear_line(npc, e, aim) then return false end
	if friendly_near(npc, aim, L.FRIENDLY_R) then return false end
	if TIF.CoverBehave and TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "launcher") end
	if not TIF.Weapon.Switch(npc, "launcher", now) then return false end
	npc.tifLaunch = { target = e, kind = kind, started = now, seenAt = now }
	TIF.Move.Stop(npc)
	TIF.Say(npc, "cover_me", 0.6)
	L.Warn(npc, now)
	if TIF.Event then TIF.Event("launcher", npc, kind) end
	return true
end

function L.Warn(npc, now)
	local pos = npc:GetPos()
	local best, bd
	for _, o in ipairs(TIF.Soldiers or {}) do
		if IsValid(o) and not o.tifDead and TIF.Relation(o, npc) == TIF.REL_HOSTILE then
			local d = o:GetPos():DistToSqr(pos)
			if d < L.WARN_R * L.WARN_R and (not bd or d < bd) and o:Visible(npc) then best, bd = o, d end
		end
	end
	if best then
		timer.Simple(math.Rand(0.3, 0.7), function()
			if IsValid(best) and not best.tifDead then TIF.Say(best, "contact_rpg", 1) end
		end)
	end
end

function L.Ready(npc, now)
	local la = npc.tifLaunch
	return la ~= nil and la.readyAt ~= nil and now >= la.readyAt and not la.firedAt
end

function L.Fired(npc, now)
	local la = npc.tifLaunch
	if not la then return end
	la.firedAt = now
	npc.tifLaunchNext = now + math.Rand(L.GAP[1], L.GAP[2])
	local sq = npc.tifSquad
	if sq then sq.tifLaunchNext = now + L.SQUAD_GAP end
	if IsValid(la.target) then la.target.tifRocketedAt = now end
	npc.tifLaunchTrack = nil
end

function L.Stow(npc, now)
	local la = npc.tifLaunch
	if npc.tifSlot ~= "launcher" then
		npc.tifLaunch = nil
		return
	end
	local w = npc.tifArms.launcher
	local drop = w and w.def and w.def.disposable and (w.rockets or 0) <= 0
	local W = TIF.Weapon
	local ok
	if drop then
		local crouched = npc.tifStance == 1
		local useP = not crouched and npc.tifArms.secondary and npc.tifArms.primary.ammo <= 0
			and TIF.GTG.WeaponKind(npc.tifArms.secondary.class) == "pistol"
		local clip = crouched and "at4_drop_cr" or (useP and "at4_drop_pstl" or "at4_drop")
		ok = W.Switch(npc, useP and "secondary" or "primary", now, { clip = clip, drop = true })
	else
		ok = W.Switch(npc, "primary", now)
	end
	if ok then la.stowing = true end
end

function L.Think(npc, c, now)
	local la = npc.tifLaunch
	if not la then return false end
	local f = npc.tifFire
	if la.stowing then
		f.want = false
		if not npc.tifSwitch then npc.tifLaunch = nil return false end
		return true
	end
	if npc.tifSwitch then
		f.want = false
		TIF.Move.Stop(npc)
		if IsValid(la.target) then npc.tifFace = L.AimAt(la.target, la.kind) end
		return true
	end
	if npc.tifSlot ~= "launcher" then
		npc.tifLaunch = nil
		return false
	end
	if not la.readyAt then la.readyAt = now + math.Rand(L.SETTLE[1], L.SETTLE[2]) end
	local e = la.target
	if c and c.ent == e and c.visible then la.seenAt = now end
	local giveUp = not IsValid(e) or (e.Alive and e:IsPlayer() and not e:Alive()) or e.tifDead
		or now - la.seenAt > L.LOST or now - la.started > L.GIVE_UP + L.SETTLE[2]
		or npc.tifCQB or (TIF.Morale and TIF.Morale.Shaken(npc))
	if la.firedAt then
		f.want = false
		if now >= la.firedAt + L.HOLD_AFTER then L.Stow(npc, now) end
		return true
	end
	if giveUp then
		f.want = false
		L.Stow(npc, now)
		return true
	end
	local aim = L.AimAt(e, la.kind)
	TIF.Move.Stop(npc)
	npc.tifMode = TIF.Anim.MODE_AIM
	npc.tifFace = aim
	f.aimPos, f.target, f.want = aim, e, now >= la.readyAt
	npc.tifAction = "launcher (" .. la.kind .. ")"
	return true
end

function L.Active(npc) return npc.tifLaunch ~= nil end
