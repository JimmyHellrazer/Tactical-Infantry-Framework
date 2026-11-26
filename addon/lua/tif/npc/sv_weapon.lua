local TIF = TIF
local Budget = TIF.Budget
local Prof = TIF.Prof

TIF.Weapon = TIF.Weapon or {}
local W = TIF.Weapon

local cvDamage = CreateConVar("tif_damage_scale", "1", FCVAR_ARCHIVE, "Multiplier on soldier weapon damage")

local cvDamageFriendly = CreateConVar("tif_damage_friendly", "1", FCVAR_ARCHIVE, "Multiplier on damage dealt by soldiers on the players' side")
local cvDamageEnemy = CreateConVar("tif_damage_enemy", "1", FCVAR_ARCHIVE, "Multiplier on damage dealt by soldiers not on the players' side")

function TIF.SideDamageScale(npc)
	local friendly = TIF.FactionRelation(TIF.FactionOf(npc), TIF.PlayerFaction()) == TIF.REL_ALLY
	return math.max(0, (friendly and cvDamageFriendly or cvDamageEnemy):GetFloat())
end

local cvAccuracy = CreateConVar("tif_accuracy_scale", "1", FCVAR_ARCHIVE, "Higher = more accurate soldiers (divides aim error)")

CreateConVar("tif_health_scale", "1", FCVAR_ARCHIVE, "Multiplier on soldier health (new soldiers)")
local cvReaction = CreateConVar("tif_reaction_scale", "1", FCVAR_ARCHIVE, "Multiplier on how long soldiers take to react to a new enemy (lower = faster)")
local cvView = CreateConVar("tif_view_scale", "1", FCVAR_ARCHIVE, "Multiplier on how far soldiers can see")

function TIF.ReactionScale() return math.max(0, cvReaction:GetFloat()) end

function TIF.ViewScale() return math.max(0.1, cvView:GetFloat()) end

hook.Add("EntityTakeDamage", "tif_side_damage", function(target, dmg)
	if not dmg:IsDamageType(DMG_BLAST) then return end
	local att = dmg:GetAttacker()
	if not (IsValid(att) and att.TIFSoldier) then return end
	dmg:ScaleDamage(math.max(0, cvDamage:GetFloat()) * TIF.SideDamageScale(att))
end)

local FALLBACK_CLASS = "weapon_tifmw_m4_sof_a"
local AIM_TOLERANCE = math.cos(math.rad(14))

local function make(class, fallback)
	local def = TIF.GTG.WeaponDef(class or "")
	if not def then
		if not fallback then return nil end

		local fb = TIF.WeaponAlias and TIF.WeaponAlias(FALLBACK_CLASS) or FALLBACK_CLASS
		TIF.Warn("Weapon ", tostring(class), " has no GTG definition; using ", fb)
		class = fb
		def = TIF.GTG.WeaponDef(class)
	end

	local stored = TIF.GTG.Stored(class)
	local clip = stored and stored.Primary and stored.Primary.ClipSize or 30
	if clip <= 0 then
		clip = 30
	end

	return { class = class, def = def, clip = clip, ammo = clip, nextShot = 0, burstLeft = 0, reloadEnd = 0 }
end

function W.IsLauncher(class)
	local def = class and TIF.GTG.WeaponDef(class)
	return def ~= nil and def.projectile ~= nil
end

function W.LauncherRifle(npc)
	local fac = TIF.Factions and npc.GetTIFFaction and TIF.Factions[npc:GetTIFFaction()]
	local L = fac and fac.loadouts or {}
	local pool = {}
	for _, list in ipairs({ L.default and L.default.primary, L.rifleman and L.rifleman.primary, fac and fac.weapons }) do
		for _, c in ipairs(list or {}) do
			if not W.IsLauncher(c) then
				pool[#pool + 1] = c
			end
		end
		if #pool > 0 then break end
	end

	local c = pool[1] and pool[math.random(#pool)] or FALLBACK_CLASS
	return TIF.WeaponAlias and TIF.WeaponAlias(c) or c
end

function W.Init(npc, primary, secondary, launcher)

	local alias = TIF.WeaponAlias
	if alias then
		primary = primary and alias(primary) or primary
		secondary = secondary and alias(secondary) or secondary
		launcher = launcher and alias(launcher) or launcher
	end

	if primary and W.IsLauncher(primary) then
		launcher = launcher or primary
		primary = W.LauncherRifle(npc)
	end

	npc.tifArms = { primary = make(primary, true), secondary = make(secondary, false) }
	local lw = launcher and W.IsLauncher(launcher) and make(launcher, false)
	if lw then
		lw.rockets = TIF.Launcher and TIF.Launcher.Rockets(lw.def) or 1
		npc.tifArms.launcher = lw
	end

	npc.tifSlot = "primary"
	npc.tifWep = npc.tifArms.primary
	npc.tifFire = { want = false }
	npc.tifLaunch = nil
	npc:SetTIFWeapon(npc.tifWep.class)

	npc:SetNW2String("tif_primary", npc.tifArms.primary.class)
	npc:SetNW2String("tif_launcher", lw and lw.class or "")
end

W.SWITCH_TIME = 0.65

function W.Switch(npc, slot, now, opts)
	local arms = npc.tifArms
	if not arms or not arms[slot] or npc.tifSlot == slot or npc.tifSwitch then
		return false
	end

	local w = npc.tifWep
	if w.reloadEnd > 0 then
		w.reloadEnd = 0
		npc:SetTIFReloadStart(0)
	end

	w.burstLeft = 0
	npc.tifSwitch = { to = slot, swapAt = now + W.SWITCH_TIME * 0.5, done = now + W.SWITCH_TIME,
		drop = opts and opts.drop or nil }

	local home = npc.tifHomeHost
	if home and npc.tifHostId == home and TIF.GTG.IsVB(home) then
		local base = slot == "secondary" and "mw_draw_pistol" or "mw_draw_rifle"
		local name = base .. (npc.tifStance == 1 and "_cr" or "")
		local c
		local CBm = not (opts and opts.clip) and TIF.CoverBehave and TIF.CoverBehave.MW
		local covClip = CBm and CBm.PlaySwitch and CBm.PlaySwitch(npc, slot)
		if covClip then
			opts = opts or {} opts.clip = covClip
		end
		if opts and opts.clip then
			c = TIF.GTG.Clip(opts.clip, home)
			if c then
				name = opts.clip
			end
		end
		if not c then
			c = TIF.GTG.Clip(name, home)
			if not c then
				c, name = TIF.GTG.Clip(base, home), base
			end
		end
		if c then
			local swapU, readyU, dropU = 0.45, 0.75, nil
			for _, t in ipairs(c.tags or {}) do
				local ev = istable(t[4]) and t[4].MoveEvent
				if ev == "pistol_pickup" or ev == "pistol_putaway" then
					swapU = t[2]
				end
				if ev == "start_aim" then
					readyU = t[2]
				end
				if ev == "dropgun" then
					dropU = t[2]
				end
			end
			npc.tifSwitch.swapAt, npc.tifSwitch.done = now + c.dur * swapU, now + c.dur * readyU
			if npc.tifSwitch.drop and dropU then
				npc.tifSwitch.dropAt = now + c.dur * dropU
			end
			npc:SetNW2String("tif_switch_clip", c.name or name)
			npc:SetNW2Float("tif_switch_t", now)
		end
	end

	return true
end

function W.Switching(npc) return npc.tifSwitch ~= nil end

W.SIDEARM = "weapon_tifmw_m19"

function W.ForcePistol(npc)
	local arms = npc.tifArms
	if not arms then return false end
	local function pistol(w) return w and TIF.GTG.WeaponKind(w.class) == "pistol" end
	if pistol(npc.tifWep) then return true end
	if not pistol(arms.secondary) then
		local cls = TIF.WeaponAlias and TIF.WeaponAlias(W.SIDEARM) or W.SIDEARM
		local w = make(cls, false)
		if not pistol(w) then return false end
		arms.secondary = w
	end

	npc.tifSwitch = nil
	npc.tifSlot, npc.tifWep = "secondary", arms.secondary
	npc:SetTIFWeapon(npc.tifWep.class)
	return true
end

function W.Choose(npc, dist, now, opts)
	local arms = npc.tifArms
	if not arms or npc.tifSwitch or npc.tifLaunch then return end
	if npc.tifSlot == "launcher" then
		W.Switch(npc, "primary", now)
		return
	end

	if not arms.secondary then return end
	if now < (npc.tifNextSwitch or 0) then return end
	local arch = npc.tifArch
	local below = arch.secondaryBelow
	local want
	if opts and opts.secondary ~= nil then
		want = opts.secondary and "secondary" or "primary"
	elseif npc.tifSlot == "secondary" and arms.secondary.ammo <= 0 and arms.primary.ammo > 0 then

		want = "primary"
	elseif not dist then
		want = "primary"
	elseif below and dist < below then
		want = "secondary"
	elseif npc.tifSlot == "primary" and arms.primary.ammo <= 0 and dist < 600 then

		want = "secondary"
	elseif npc.tifSlot == "secondary" then

		local lull = now - (npc:GetTIFShotTime() or 0) > 3
		if below then want = dist > below * 1.4 and "primary" or "secondary"
		else
			want = (dist > 700 or lull) and "primary" or "secondary"
		end
	else
		want = "primary"
	end

	if want ~= npc.tifSlot and W.Switch(npc, want, now) then
		npc.tifNextSwitch = now + 3
	end
end

local function switch_tick(npc, now)
	local s = npc.tifSwitch
	if s.drop and not s.dropped and now >= (s.dropAt or s.swapAt) and npc.tifArms.launcher then
		s.dropped = true
		if npc.TIFDropWeapon then
			pcall(npc.TIFDropWeapon, npc, npc.tifArms.launcher)
		end
		npc.tifArms.launcher = nil
		npc:SetNW2String("tif_launcher", "")
		if not s.swapped then
			npc:SetTIFWeapon("")
		end
	end

	if not s.swapped and now >= s.swapAt then
		s.swapped = true
		npc.tifSlot = s.to
		npc.tifWep = npc.tifArms[s.to]
		npc:SetTIFWeapon(npc.tifWep.class)
		npc:SetTIFReloadStart(0)
	end

	if now >= s.done then
		npc.tifSwitch = nil
	end
end

function W.Reloading(npc)
	return npc.tifWep and npc.tifWep.reloadEnd > 0
end

function W.StartReload(npc)
	local w = npc.tifWep
	if not w or w.reloadEnd > 0 or w.ammo >= w.clip then return end
	if w.rockets and w.rockets <= w.ammo then return end
	local now = CurTime()
	w.reloadEnd = now + ((w.def and w.def.reload_time) or 2.2) * (npc.tifPanic and W.PANIC_RELOAD or 1)
	w.burstLeft = 0
	npc:SetTIFReloadStart(now)
	if w.ammo <= 0 and not w.rockets then
		TIF.Say(npc, "no_ammo", 0.7)
	else
		TIF.Say(npc, "reloading", 0.65)
	end

	local mw = w.def and w.def.mw
	local list = mw and ((w.ammo <= 0 and mw.reloadEmpty) or mw.reload)
	if list then
		local dur = w.reloadEnd - now
		for _, e in ipairs(list) do
			timer.Simple(e[1] * dur, function()

				if IsValid(npc) and npc.tifWep == w and w.reloadEnd > 0 and sound.GetProperties(e[2]) then
					npc:EmitSound(e[2], 72, 100, 1, CHAN_AUTO)
				end
			end)
		end
	end
end

W.BAND_CLOSE, W.BAND_MID = 400, 1500
W.WALK_FIRE_MAX = 110
W.DRIFT = { auto = 0.14, braced = 0.05, cap = 2.0 }
W.PROFILES = {

	rifle   = { close = { 3, 5 }, mid = { 2, 3 }, long = { 1, 2 }, cad = { 1.15, 1.45 }, pause = { 1, 1.25, 1.8 } },
	smg     = { close = { 4, 6 }, mid = { 2, 4 }, long = { 1, 2 }, cad = { 1.05, 1.3 }, pause = { 0.9, 1.2, 1.8 } },
	lmg     = { close = { 4, 7 }, mid = { 3, 5 }, long = { 2, 4 }, cad = { 1.05, 1.25 }, pause = { 1, 1.2, 1.5 } },
	shotgun = { close = { 1, 1 }, mid = { 1, 1 }, long = { 1, 1 }, cad = { 1, 1 }, pause = { 1, 1.2, 1.4 } },

	pistol  = { close = { 2, 5 }, mid = { 2, 3 }, long = { 1, 2 }, cad = { 1, 1 }, pause = { 1, 1.4, 2 } },
	rpg     = { close = { 1, 1 }, mid = { 1, 1 }, long = { 1, 1 }, cad = { 1, 1 }, pause = { 1, 1, 1 } },
}

W.PISTOL = { shot = { 0.11, 0.22 }, hitch = 0.2, hitchT = { 0.1, 0.3 }, gap = { 0.3, 0.75 } }

W.SEMI = {
	dmr = { close = { 2, 3 }, mid = { 1, 2 }, long = { 1, 1 },
		gap = { { 0.3, 0.4 }, { 1.0, 1.4 }, { 1.6, 2.2 } }, pause = { { 0.9, 1.4 }, { 1.0, 1.4 }, { 1.8, 2.8 } } },
	heavy = { close = { 1, 1 }, mid = { 1, 1 }, long = { 1, 1 },
		gap = { { 1.8, 2.2 }, { 2.2, 2.7 }, { 2.7, 3.3 } }, pause = { { 1.8, 2.2 }, { 2.2, 2.7 }, { 2.7, 3.3 } } },
}

local function semi_of(def) return def and def.semi and W.SEMI[def.semi] or nil end

local function band(dist)
	if dist < W.BAND_CLOSE then return "close", 1 end
	if dist < W.BAND_MID then return "mid", 2 end
	return "long", 3
end

local function kind_of(w)
	w.kind = w.kind or TIF.GTG.WeaponKind(w.class)
	return w.kind
end

W.PANIC_SPREAD, W.PANIC_PAUSE, W.PANIC_RELOAD = 3, 0.45, 1.5
W.PANIC_BURST, W.PANIC_SEMI = { 6, 12 }, { 2, 4 }

local function burst_size(npc, w, def, dist, braced, walking)
	if npc.tifPanic then
		local r = (def and def.auto) and W.PANIC_BURST or W.PANIC_SEMI
		return math.random(r[1], r[2])
	end

	local arch = npc.tifArch
	local b = arch.burst

	local S = semi_of(def)
	if S then
		local r = S[band(dist)]
		local n = math.random(r[1], r[2])
		return walking and math.min(n, 2) or n
	end

	local kind = kind_of(w)
	if b[2] <= 1 and kind ~= "pistol" then return 1 end
	local P = W.PROFILES[kind] or W.PROFILES.rifle
	local bn = band(dist)
	if def and not def.auto and kind ~= "shotgun" and kind ~= "pistol" then
		return (bn == "close" and math.random() < 0.5) and 2 or 1
	end

	if kind == "lmg" and braced then return math.random(b[1], b[2]) end
	local r = P[bn]

	local scale = kind == "lmg" and 1 or ((b[1] + b[2]) / 2) / 5
	local n = math.random(r[1], r[2])
	n = math.max(1, math.floor(n * math.min(scale, 1.6) + 0.5))
	if walking then
		n = math.min(n, bn == "close" and 3 or 2)
	end

	return n
end

local function cadence(w, def, dist)
	local S = semi_of(def)
	if S then
		local _, i = band(dist)
		local g = S.gap[i]
		return math.max(def.rate or 0.1, math.Rand(g[1], g[2]))
	end

	local P = W.PROFILES[kind_of(w)] or W.PROFILES.rifle
	if kind_of(w) == "pistol" then
		local Q = W.PISTOL
		local t = math.Rand(Q.shot[1], Q.shot[2]) * (dist >= W.BAND_MID and 1.4 or 1)
		if math.random() < Q.hitch then
			t = t + math.Rand(Q.hitchT[1], Q.hitchT[2])
		end
		return t
	end

	local rate = def and def.rate or 0.1
	if dist < W.BAND_CLOSE then return rate * math.Rand(1, 1.12) end
	return rate * math.Rand(P.cad[1], P.cad[2])
end

local function pause(npc, w, def, dist, walking)
	local S = semi_of(def)
	if S then
		local _, i = band(dist)
		local p = S.pause[i]
		return math.max(def.rate or 0.1, math.Rand(p[1], p[2]) * (walking and 1.2 or 1) * (npc.tifPanic and W.PANIC_PAUSE or 1))
	end

	local P = W.PROFILES[kind_of(w)] or W.PROFILES.rifle
	local _, i = band(dist)
	if kind_of(w) == "pistol" then
		local Q = W.PISTOL
		return math.Rand(Q.gap[1], Q.gap[2]) * P.pause[i] * (walking and 1.2 or 1) * (npc.tifPanic and W.PANIC_PAUSE or 1)
	end

	local p = npc.tifArch.burstPause
	local t = math.Rand(p[1], p[2]) * P.pause[i] * (walking and 1.3 or 1)
	if npc.tifPanic then
		t = t * W.PANIC_PAUSE
	end

	return math.max(def and def.rate or 0.1, t)
end

function W.CoveringBurst(npc, now)
	local arch = npc.tifArch
	local w = npc.tifWep
	if not w or w.reloadEnd > 0 or w.ammo < 4 or (w.def and w.def.projectile) then
		return false
	end

	if npc.tifAware ~= TIF.AWARE.ENGAGED or now < (npc.tifNextCoverFire or 0) or npc.tifVeh or npc.tifProne then
		return false
	end
	npc.tifNextCoverFire = now + 3
	local c = npc.tifPrimaryC
	if not c or now - (c.seenAt or -99) > 2.5 then return false end
	if math.random() > (arch.coverFire or 0.35) then return false end
	local aim = (c.visible and IsValid(c.ent)) and c.ent:WorldSpaceCenter() or (c.pos + Vector(0, 0, 40))
	npc.tifCoverFire = { untilT = now + math.Rand(0.55, 0.9), aim = aim, shots = math.random(3, 5) }
	w.burstLeft = 0
	return true
end

function W.CoverFiring(npc, now)
	local cf = npc.tifCoverFire
	return cf ~= nil and now < cf.untilT and cf.shots > 0
end

local fallCache = setmetatable({}, { __mode = "k" })
local tracerData
function W.TracerCallback(npc, inner)
	return function(att, tr, dmg)
		if inner then
			inner(att, tr, dmg)
		end
		tracerData = tracerData or (EffectData and EffectData())
		if not tracerData then return end
		tracerData:SetEntity(npc)
		tracerData:SetStart(tr.StartPos)
		tracerData:SetOrigin(tr.HitPos)
		util.Effect("tif_tracer", tracerData)
	end
end

local function falloff_cb(def)
	local fo = def and def.falloff
	if not fo then return nil end
	local cb = fallCache[def]
	if cb then return cb end
	local near, far, low = fo[1], fo[2], fo[3]
	cb = function(_, tr, dmg)
		local d = tr.StartPos:Distance(tr.HitPos)
		if d > near then
			dmg:ScaleDamage(1 + (low - 1) * math.min(1, (d - near) / math.max(1, far - near)))
		end
	end

	fallCache[def] = cb
	return cb
end

local CHEST_Z = { [0] = 42, 30, 10 }
local BODY = 24
local PAST_TARGET = 500
local CHEST_VEC = Vector()

local function in_cone(src, dir, dist, tanc, chest)
	local rx, ry, rz = chest.x - src.x, chest.y - src.y, chest.z - src.z
	local along = rx * dir.x + ry * dir.y + rz * dir.z
	if along < 16 or along > dist + PAST_TARGET then return false end
	local rad = BODY + along * tanc
	local lat2 = rx * rx + ry * ry + rz * rz - along * along
	return lat2 < rad * rad
end

local function ally_in_line(npc, src, aim, deg)
	local dir = aim - src
	local dist = dir:Length()
	if dist < 1 then return nil end
	dir:Mul(1 / dist)
	local tanc = math.tan(math.rad(math.min(deg, 60) * 0.7))
	local reach = dist + PAST_TARGET
	local reach2 = reach * reach
	local ally = TIF.REL_ALLY
	local relation = TIF.Relation
	local soldiers = TIF.Soldiers
	for i = 1, #soldiers do
		local e = soldiers[i]
		if e ~= npc and IsValid(e) and not e.tifDead then
			local ep = e:GetPos()
			if ep:DistToSqr(src) < reach2 and relation(npc, e) == ally then
				CHEST_VEC.x, CHEST_VEC.y, CHEST_VEC.z = ep.x, ep.y, ep.z + (CHEST_Z[e:GetTIFStance()] or 42)
				if in_cone(src, dir, dist, tanc, CHEST_VEC) then return e end
			end
		end
	end

	for _, p in player.Iterator() do
		if p:Alive() and p:GetPos():DistToSqr(src) < reach2 and relation(npc, p) == ally
			and in_cone(src, dir, dist, tanc, p:WorldSpaceCenter()) then
			return p
		end
	end

	local npcs = TIF.NPCs
	if npcs then
		for i = 1, #npcs do
			local e = npcs[i]
			if IsValid(e) and e:Health() > 0 and e:GetPos():DistToSqr(src) < reach2 and relation(npc, e) == ally
				and in_cone(src, dir, dist, tanc, e:WorldSpaceCenter()) then
				return e
			end
		end
	end

	if TIF.Shield and next(TIF.Shield.List) ~= nil then
		for h, captor in pairs(TIF.Shield.Hostages()) do
			local hp = h:GetPos()
			CHEST_VEC.x, CHEST_VEC.y, CHEST_VEC.z = hp.x, hp.y, hp.z + 26
			if captor ~= npc and ((CHEST_VEC.x - src.x) * dir.x + (CHEST_VEC.y - src.y) * dir.y + (CHEST_VEC.z - src.z) * dir.z) < dist + 30
				and in_cone(src, dir, dist, tanc, CHEST_VEC) then
				return h
			end
		end
	end

	return nil
end
W.AllyInLine = ally_in_line

local MUZZLE_Z = { [0] = 58, 38, 12 }

function W.MuzzleSrc(npc, aimPos)

	local veh = npc.tifVeh
	if IsValid(veh) and aimPos then
		local o = npc:GetPos() + Vector(0, 0, 38)
		local dir = (aimPos - o):GetNormalized()
		local far = o + dir * 400
		local hit = util.IntersectRayWithOBB(far, o - far, veh:GetPos(), veh:GetAngles(), veh:OBBMins(), veh:OBBMaxs())
		return (hit or o) + dir * 10
	end

	if npc.tifMuzzle and not npc.tifBlind then return npc.tifMuzzle end
	local z = MUZZLE_Z[npc:GetTIFStance()] or 58
	if npc.tifBlind then

		return npc:GetPos() + Vector(0, 0, z + 14) + npc:GetForward() * 6
	end

	return npc:GetPos() + Vector(0, 0, z) + npc:GetRight() * 7 + npc:GetForward() * 10
end

local function spread_deg(npc, now)
	local arch = npc.tifArch
	local deg = arch.spread
	if npc.loco:GetVelocity():Length2D() > 20 then
		deg = deg * arch.spreadMoving
	end

	local since = now - (npc.tifEngagedAt or -99)
	if since < 1.5 then
		deg = deg * (1 + (arch.firstShots - 1) * (1 - since / 1.5))
	end

	local f = npc.tifFire
	if IsValid(f.target) and f.target:GetVelocity():Length2D() > 150 then
		deg = deg * 1.3
	end

	deg = deg * (1 + 1.5 * (npc.tifSupp or 0))
	if npc.tifBlind then
		deg = deg * 4
	end

	if TIF.Morale and TIF.Morale.Shaken(npc) then
		deg = deg * 1.25
	end
	if npc.tifPanic then
		deg = deg * W.PANIC_SPREAD
	end

	local w = npc.tifWep
	if w and (w.burstShot or 0) > 0 then
		local k = (npc.tifBraced and W.DRIFT.braced or W.DRIFT.auto) * w.burstShot
		deg = deg * math.min(W.DRIFT.cap, 1 + k)
	end

	if W.CoverFiring(npc, now) then
		deg = deg * 2.2
	end

	local veh = npc.tifVeh
	if IsValid(veh) then
		deg = deg * (1.8 + math.min(2, veh:GetVelocity():Length() / 400))
	end

	return deg / math.max(0.1, cvAccuracy:GetFloat())
end

local skyStart, skyEnd, skyOut = Vector(), Vector(), {}
local skyTrace = { start = skyStart, endpos = skyEnd, mask = MASK_SOLID_BRUSHONLY, output = skyOut }
function W.Outdoors(npc)
	local now = CurTime()
	if (npc.tifOutAt or 0) > now then return npc.tifOut end
	npc.tifOutAt = now + 3
	local p = npc:GetPos()
	skyStart.x, skyStart.y, skyStart.z = p.x, p.y, p.z + 64
	skyEnd.x, skyEnd.y, skyEnd.z = p.x, p.y, p.z + 1564
	local tr = util.TraceLine(skyTrace)
	npc.tifOut = (not tr.Hit) or tr.HitSky
	return npc.tifOut
end

local hasSound = {}
local function registered(name)
	if not isstring(name) then return false end
	local h = hasSound[name]
	if h == nil then
		h = sound.GetProperties(name) ~= nil or string.find(name, "%.wav$") ~= nil or string.find(name, "%.mp3$") ~= nil
		hasSound[name] = h
	end

	return h
end

local function shot_sound(npc, w, src)
	local mw = w.def and w.def.mw
	if mw and registered(mw.fire) then
		npc:EmitSound(mw.fire, 95, math.random(97, 103), 1, CHAN_WEAPON)
		local tail = W.Outdoors(npc) and mw.tailOut or mw.tailIn
		if registered(tail) and (w.burstLeft or 0) <= 1 then
			npc:EmitSound(tail, 110, 100, 0.8, CHAN_AUTO)
		end
		return
	end

	local def = w.def
	npc:EmitSound((def and def.sound) or "Weapon_AR2.Single", 95, math.random(96, 104), 1, CHAN_WEAPON)
end

local BULLET_DATA = { Spread = vector_origin, Tracer = 0 }
local function bullet_callback(att, tr, dmg)
	local w = att and att.tifWep
	local cb = w and falloff_cb(w.def)
	if cb then
		cb(att, tr, dmg)
	end

	tracerData = tracerData or (EffectData and EffectData())
	if not tracerData then return end
	tracerData:SetEntity(att)
	tracerData:SetStart(tr.StartPos)
	tracerData:SetOrigin(tr.HitPos)
	util.Effect("tif_tracer", tracerData)
end

local function fire_one(npc, w, aimPos, now)
	local def = w.def
	local src = W.MuzzleSrc(npc, aimPos)
	local dir = aimPos - src
	dir:Normalize()
	local ang = dir:Angle()
	local deg = spread_deg(npc, now)
	ang:RotateAroundAxis(ang:Up(), (math.Rand(-1, 1) + math.Rand(-1, 1)) * 0.5 * deg)
	ang:RotateAroundAxis(ang:Right(), (math.Rand(-1, 1) + math.Rand(-1, 1)) * 0.5 * deg * 0.7)
	if def and def.projectile then
		local fwd = ang:Forward()
		TIF.GTG.Launch(npc, def, w.class, src + fwd * 30, fwd)
		shot_sound(npc, w, src)
		npc:SetTIFShotTime(now)
		w.ammo = w.ammo - 1
		if w.rockets then
			w.rockets = math.max(0, w.rockets - 1)
		end
		if TIF.Launcher and npc.tifLaunch then
			TIF.Launcher.Fired(npc, now)
		end
		return
	end

	BULLET_DATA.Attacker = npc
	BULLET_DATA.Inflictor = npc
	BULLET_DATA.Damage = (def and def.damage or 20) * cvDamage:GetFloat() * TIF.SideDamageScale(npc)
	BULLET_DATA.Num = def and def.pellets or 1
	BULLET_DATA.Src = src
	BULLET_DATA.Dir = ang:Forward()
	BULLET_DATA.Distance = def and def.range or 56756
	BULLET_DATA.Force = def and math.min(10, (def.force or 75) / 20) or 3
	BULLET_DATA.IgnoreEntity = npc
	BULLET_DATA.Callback = bullet_callback
	npc:FireBullets(BULLET_DATA)
	shot_sound(npc, w, src)
	npc:SetTIFShotTime(now)
	w.ammo = w.ammo - 1
end

function W.Think(npc, now)
	if npc.tifSwitch then
		switch_tick(npc, now)
		return
	end

	local w = npc.tifWep
	if not w then return end
	if w.reloadEnd > 0 then
		if now >= w.reloadEnd then
			w.ammo, w.reloadEnd = w.clip, 0
			npc:SetTIFReloadStart(0)
		end
		return
	end

	local f = npc.tifFire

	local cf = npc.tifCoverFire
	local covering = cf and now < cf.untilT and cf.shots > 0
	if cf and not covering then
		npc.tifCoverFire, cf = nil, nil
	end

	local want, aimPos = f.want, f.aimPos
	if covering then
		want, aimPos = true, cf.aim
	end

	if not want or not aimPos or now < w.nextShot then
		if not want then
			w.burstLeft, w.burstShot = 0, 0
		end
		return
	end

	local act = npc.tifAct
	local low = act and TIFG_GUN_LOW and TIFG_GUN_LOW[act.name]
	if low then
		local u = (now - act.t0) / math.max(0.01, act.dur)
		if u >= low[1] and u <= low[2] then
			w.burstLeft, w.burstShot = 0, 0
			return
		end
	end

	local speed = npc.loco:GetVelocity():Length2D()
	local walking = speed > 20 and not npc.tifVeh
	local dist = npc:GetPos():Distance(aimPos)
	if not covering and walking and (speed > W.WALK_FIRE_MAX or dist >= W.BAND_MID) then
		w.burstLeft, w.burstShot = 0, 0
		return
	end

	if next(TIF.Perception.Filters) ~= nil then
		local t = IsValid(f.target) and f.target or npc.tifPrimary
		if IsValid(t) and TIF.Perception.Engage(npc, t) ~= "fight" then
			w.burstLeft = 0
			return
		end
	end

	if w.ammo <= 0 then
		W.StartReload(npc)
		return
	end

	if npc.tifSlot == "launcher" and not (TIF.Launcher and TIF.Launcher.Ready(npc, now)) then
		return
	end
	if now < (npc.tifReactUntil or 0) then return end
	if now < (npc.tifLowReadyUntil or 0) then return end

	local to = aimPos - npc:GetPos()
	to.z = 0
	to:Normalize()
	local fwd = npc:GetForward()

	if not npc.tifBlind and not npc.tifVeh and not npc.tifAimFree and to:Dot(fwd) < (covering and 0.5 or AIM_TOLERANCE) then
		return
	end

	local def = w.def

	if def and def.projectile and npc:GetPos():DistToSqr(aimPos) < 320 * 320 then
		return
	end

	local blocker = ally_in_line(npc, W.MuzzleSrc(npc, aimPos), aimPos, spread_deg(npc, now))
	if blocker then
		npc.tifFFBlockedAt, npc.tifFFBlocker = now, blocker

		npc.tifLowReadyUntil = now + math.Rand(0.8, 1.4)
		w.burstLeft = 0
		w.nextShot = now + 0.35
		return
	end

	local braced = TIF.BipodMW and TIF.BipodMW.Set(npc, now) or false
	npc.tifBraced = braced

	if not braced and not covering and npc.tifProne and npc.tifProne.phase == 2 and TIF.BipodMW and TIF.BipodMW.Use(npc)
		and dist > W.BAND_CLOSE then
		w.nextShot = now + 0.2
		return
	end

	if w.burstLeft <= 0 then
		w.burstLeft = covering and cf.shots or burst_size(npc, w, def, dist, braced, walking)
		w.burstShot = 0
	end

	fire_one(npc, w, aimPos, now)
	w.burstLeft = w.burstLeft - 1
	w.burstShot = (w.burstShot or 0) + 1
	if covering then
		cf.shots = cf.shots - 1
	end

	if w.burstLeft <= 0 then
		w.nextShot = now + pause(npc, w, def, dist, walking)
		w.burstShot = 0
	else
		w.nextShot = now + cadence(w, def, covering and 0 or dist) * (walking and not covering and 1.3 or 1)
	end

	if w.ammo <= 0 then
		W.StartReload(npc)
	end
end
