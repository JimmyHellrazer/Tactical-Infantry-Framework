local TIF = TIF
local Act = TIF.Action

TIF.Shield = TIF.Shield or {}
local SH = TIF.Shield
SH.List = SH.List or {}

SH.SNAP = 60
SH.FACE = 25
SH.MW_SWING = 50
SH.CH_FACE = -13
SH.CH_GRAB = 160
SH.ENEMY_MIN, SH.ENEMY_MAX = 100, 1000
SH.CHANCE = 0.5
SH.TRY_EVERY = 2
SH.COOLDOWN = 40
SH.MAX = 2
SH.RESCUE_DIST = 110
SH.HOLD = { 30, 55 }
SH.CH_HOLD_MAX = 120
SH.SEE_DIST = 4000
SH.GHOST = COLLISION_GROUP_NPC_SCRIPTED

SH.AI_SHOT_AFTER = 15
SH.AI_SHOT_RANGE = 1500
SH.AI_SHOT_WIN = 0.9
SH.AI_SHOT_RETRY = 4

SH.VARIANTS = {
	mw19 = {
		start = "grab", held = "idle", hold = "idle", shot = "death", rescue = "rescue", face = SH.FACE,
		phases = {
			grab = { att = "mwsh_grab_att", vic = "mwsh_grab_vic", next = "idle" },
			idle = { att = "mwsh_idle_att", vic = "mwsh_idle_vic", loop = true },
			death = { att = "mwsh_death_att", vic = "mwsh_death_vic" },
			rescue = { att = "mwsh_rescue_att", vic = "mwsh_rescue_vic" },
		},

		shift = { x = 20.2, y = 46.1, rampFrom = 0.45 },
	},
	ch = {
		start = "start", held = "hold", hold = "hold", shot = "death", vdeath = "vdeath", vdeathHead = "vdeath_hs",
		face = SH.CH_FACE,
		phases = {
			start = { att = "mwsc_aim_start_att", vic = "mwsc_aim_start_vic", next = "hold" },
			hold = { att = "mwsc_aim_att", vic = "mwsc_aim_vic", loop = true },
			death = { att = "mwsc_death_att", vic = "mwsc_live_vic" },
			vdeath = { att = "mwsc_live_att", vic = "mwsc_death_vic", vicKillU = 42 / 82 },
			vdeath_hs = { att = "mwsc_live_att", vic = "mwsc_death_hs_vic", vicKillU = 1 },
		},
	},
}

local cvShield = CreateConVar("tif_shield", "1", FCVAR_ARCHIVE,
	"Enemy soldiers sometimes grab a civilian as a human shield (MW19 / Clean House clips, 1/0)")

function SH.On()
	return cvShield:GetBool()
end

local function data(name)
	return TIF.ShieldData and TIF.ShieldData[name]
end

function SH.Sample(name, u)
	local D = data(name)
	if not D then return 0, 0, 0, 0 end

	local p, step, n = D.p, D.step, D.frames
	local cnt = #p / 4
	local fr = math.Clamp(u, 0, 1) * (n - 1)

	local i = math.floor(fr / step)
	local f0 = i * step
	local f1 = math.min(n - 1, f0 + step)

	if i >= cnt - 1 then
		i, f0, f1 = cnt - 1, n - 1, n - 1
	end

	local j = math.min(cnt - 1, i + 1)
	local k = f1 > f0 and (fr - f0) / (f1 - f0) or 0
	local a, b = i * 4, j * 4
	local function lerp(o)
		return p[a + o] + (p[b + o] - p[a + o]) * k
	end

	return lerp(1), lerp(2), lerp(3), p[a + 4] + math.AngleDifference(p[b + 4], p[a + 4]) * k
end

local function shift_k(sc, ph, u)
	local s = sc.var.shift
	if not s then return 0 end
	if ph ~= sc.var.start then return 1 end

	local k = math.Clamp((u - s.rampFrom) / (1 - s.rampFrom), 0, 1)
	return k * k * (3 - 2 * k)
end

local function place(ent, sc, name, u, shiftK)
	local x, y, z, yaw = SH.Sample(name, u)
	if shiftK and shiftK > 0 then
		local s = sc.var.shift
		x, y = x + s.x * shiftK, y + s.y * shiftK
	end

	local r = math.rad(sc.yaw)
	local c, s = math.cos(r), math.sin(r)
	local o = sc.origin
	ent:SetPos(Vector(o.x + x * c - y * s, o.y + x * s + y * c, o.z + math.max(0, z)))
	ent:SetAngles(Angle(0, sc.yaw + yaw, 0))
end

local function captor_ok(npc, variant)
	local v = SH.VARIANTS[variant or "mw19"]
	return IsValid(npc) and npc.TIFSoldier and not npc.tifDead and not npc.tifDying and npc.tifHomeHost
		and v ~= nil and Act.Clip(npc, v.phases[v.held].att) ~= nil
end

local function free(npc)
	return not (npc.tifAct or npc.tifVeh or npc.tifProne or npc.tifCov or npc.tifDowned or npc.tifSurrendered
		or npc.tifKnock or npc.tifMelee or npc.tifThrow or npc.tifBipod or npc.tifHeli or npc.tifShield or npc.tifCQB)
end

local function hostage_ok(civ)
	return IsValid(civ) and civ:GetClass() == "tif_civilian" and civ.mw and not civ.gone
		and not civ.tifHeld and civ:Health() > 0 and TIF.GTG.Clip("mwsh_grab_vic", "mw_male") ~= nil
end

local function ghost(e, on)
	if not IsValid(e) then return end

	if on then
		e.tifShieldGroup = e.tifShieldGroup or e:GetCollisionGroup()
		e:SetCollisionGroup(SH.GHOST)
	elseif e.tifShieldGroup then
		if e:GetCollisionGroup() == SH.GHOST then
			e:SetCollisionGroup(e.tifShieldGroup)
		end

		e.tifShieldGroup = nil
	end
end

local LOCK_OK = { lockOK = true }

local function play(sc, ph, now)
	local P = sc.var.phases[ph]
	local npc, civ = sc.captor, sc.hostage
	local d

	if P.loop then
		d = Act.Loop(npc, P.att, LOCK_OK)
	else
		d = Act.Play(npc, P.att, LOCK_OK)
	end

	local c = Act.Clip(npc, P.att)
	d = (isnumber(d) and d > 0 and d) or (c and c.dur) or 1
	sc.phase, sc.t0, sc.dur, sc.vicKilled = ph, now, d, nil

	if IsValid(civ) then
		civ.civOneShot = not P.loop or nil
		civ:Play(P.vic)
		civ:SetCycle(0)
	end

	sc.att, sc.vic = P.att, P.vic
end

local function free_hostage(sc)
	local civ = sc.hostage
	if not IsValid(civ) then return end

	civ.tifHeld = nil
	civ.civOneShot = nil

	civ.civHoldLast = civ.civRole
	ghost(civ, false)

	if civ.state == "held" then
		civ.fear = 1
		civ.dangerPos = IsValid(sc.captor) and sc.captor:GetPos() or civ:GetPos()
		civ.scaredAt = CurTime()
		civ.decided = true
		civ:SetState("flee")
	end
end

local function free_captor(sc)
	local npc = sc.captor
	if not IsValid(npc) then return end

	if npc.tifDead then
		npc.tifShield = nil
		return
	end

	npc.tifShield = nil
	npc.tifActLock = nil
	npc.tifShieldNext = CurTime() + SH.COOLDOWN
	ghost(npc, false)

	if npc.tifAct and sc.att and npc.tifAct.name == sc.att then
		Act.Clear(npc, true)
	end
end

local function finish(sc, outcome)
	if sc.done then return end

	sc.done = true
	SH.List[sc] = nil
	free_hostage(sc)
	free_captor(sc)
	hook.Run("TIF_ShieldEnd", sc, outcome)
	TIF.Log(string.format("[shield] %s (%s, captor %s)", outcome, sc.varName or "?", IsValid(sc.captor) and sc.captor:EntIndex() or "-"))
end

SH.Finish = finish

local function kill(ent, att, flag)
	if not IsValid(ent) or ent.tifDead or ent:Health() <= 0 then return end

	local d = DamageInfo()
	d:SetDamage(ent:Health() + 100)
	d:SetDamageType(DMG_BULLET)
	d:SetAttacker(IsValid(att) and att or game.GetWorld())
	d:SetInflictor(IsValid(att) and att or game.GetWorld())
	d:SetDamagePosition(ent:WorldSpaceCenter())
	d:SetDamageForce(Vector())
	ent[flag] = true
	ent:TakeDamageInfo(d)
	ent[flag] = nil
end

function SH.Start(npc, civ, opts)
	opts = opts or {}
	local varName = opts.variant or "mw19"
	local var = SH.VARIANTS[varName]

	if not var or not (captor_ok(npc, varName) and hostage_ok(civ)) then
		return nil
	end

	if npc.tifShield then return nil end

	local now = CurTime()

	local first = opts.held and var.held or var.start
	local origin = opts.pos and Vector(opts.pos) or npc:GetPos()
	local yaw = opts.yaw

	if not yaw then
		local sx, sy = SH.Sample(var.phases[first].vic, 0)
		local to = civ:GetPos() - origin
		yaw = math.deg(math.atan2(to.y, to.x)) - math.deg(math.atan2(sy, sx))
	end

	if varName == "ch" and not (TIF.Weapon and TIF.Weapon.ForcePistol and TIF.Weapon.ForcePistol(npc)) then
		return nil
	end

	local sc = { captor = npc, hostage = civ, origin = origin, yaw = yaw, opts = opts, started = now, var = var, varName = varName }
	local hold = opts.hold or (varName == "ch" and SH.CH_HOLD_MAX or SH.HOLD)
	sc.holdUntil = istable(hold) and now + math.Rand(hold[1], hold[2]) or (hold and now + hold) or nil
	TIF.Move.Stop(npc)
	npc.tifShield = sc
	npc.tifActLock = true
	npc.tifFire.want = false
	civ.tifHeld = sc
	civ:SetState("held")
	civ.loco:SetDesiredSpeed(0)
	ghost(npc, true)
	ghost(civ, true)
	SH.List[sc] = true
	play(sc, first, now)
	place(npc, sc, sc.att, 0)
	place(civ, sc, sc.vic, 0, shift_k(sc, first, 0))
	TIF.Say(npc, "contact", 0.8)

	if TIF.Event then
		TIF.Event("shield", "start ", varName, " ", first, ": captor ", npc:EntIndex(), ", hostage ", civ:EntIndex())
	end

	hook.Run("TIF_ShieldStart", sc)
	return sc
end

local function enemy_near(sc, dist)
	local npc = sc.captor
	local pos = npc:GetPos()
	local d2 = dist * dist

	for _, p in player.Iterator() do
		if TIF.IsLiveCombatant(p) and TIF.Relation(npc, p) == TIF.REL_HOSTILE and p:GetPos():DistToSqr(pos) < d2 then
			return p
		end
	end

	for _, s in ipairs(TIF.Soldiers) do
		if s ~= npc and TIF.IsLiveCombatant(s) and TIF.Relation(npc, s) == TIF.REL_HOSTILE and s:GetPos():DistToSqr(pos) < d2 then
			return s
		end
	end

	return nil
end

local function tick_scene(sc, now)
	local npc, civ = sc.captor, sc.hostage
	local var, ph = sc.var, sc.phase
	local P = var.phases[ph]

	if not IsValid(npc) or npc.tifDead then
		return finish(sc, "captor_killed")
	end

	if (not IsValid(civ) or civ:Health() <= 0) and not P.vicKillU then
		return finish(sc, "hostage_killed")
	end

	local u = (now - sc.t0) / math.max(0.01, sc.dur)
	if P.loop then
		u = u % 1
	end

	if not (npc.tifAct and npc.tifAct.name == sc.att) and not npc.tifDead then
		if TIF.Event then
			TIF.Event("shield", "captor ", npc:EntIndex(), " lost his clip (", npc.tifAct and npc.tifAct.name or "none", "): put back")
		end

		Act.Play(npc, sc.att, LOCK_OK)

		if npc.tifAct then
			npc.tifAct.t0 = sc.t0
			npc:SetNW2Float("tif_act_t", sc.t0)
		end
	end

	place(npc, sc, sc.att, u)

	if IsValid(civ) and civ:Health() > 0 then
		place(civ, sc, sc.vic, u, shift_k(sc, ph, u))
	end

	npc.tifFire.want = false

	if P.vicKillU and not sc.vicKilled and u >= P.vicKillU then
		sc.vicKilled = true

		if IsValid(civ) then
			civ.tifHeld = nil
			ghost(civ, false)
		end

		kill(civ, sc.killer, "tifShieldKilling")
	end

	if P.next and u >= 1 then
		play(sc, P.next, now)
	elseif ph == var.hold then
		sc.holdSince = sc.holdSince or now

		if now - sc.holdSince >= SH.AI_SHOT_AFTER and now >= (sc.nextAIShot or 0) and SH.AIShot(sc, now) then
			return
		end

		local timeUp = sc.holdUntil and now >= sc.holdUntil
		if var.rescue and not sc.opts.noRescue and (timeUp or enemy_near(sc, SH.RESCUE_DIST)) then
			play(sc, var.rescue, now)
		elseif not var.rescue and timeUp and not sc.opts.noRescue then
			return finish(sc, "released")
		end
	elseif ph == var.rescue and u >= 1 then
		return finish(sc, "rescue")
	elseif (ph == var.vdeath or ph == var.vdeathHead) and u >= 1 then
		return finish(sc, "hostage_killed")
	elseif ph == var.shot and u >= 1 then
		npc.tifNoDeathClip = true
		kill(npc, sc.killer, "tifShieldKilling")
		finish(sc, "shot")
	end
end

local shotOut = {}
local shotTr = { mask = MASK_SHOT, output = shotOut }
local SH_BONE_M = Matrix and Matrix()

function SH.AIShot(sc, now)
	sc.nextAIShot = now + SH.AI_SHOT_RETRY
	local npc, civ = sc.captor, sc.hostage
	local hb = npc:LookupBone("ValveBiped.Bip01_Head1")
	local hm = hb and (TIF.CopyBone and TIF.CopyBone(npc, hb, SH_BONE_M) or npc:GetBoneMatrix(hb))
	local head = hm and hm:GetTranslation() or (npc:GetPos() + Vector(0, 0, 64))
	local best, bd

	for _, s in ipairs(TIF.Soldiers or {}) do
		if IsValid(s) and s ~= npc and not s.tifDead and not s.tifShield and TIF.IsLiveCombatant(s)
			and TIF.Relation(s, npc) == TIF.REL_HOSTILE and s.tifWep then
			local d2 = s:GetPos():DistToSqr(head)
			if d2 < SH.AI_SHOT_RANGE * SH.AI_SHOT_RANGE and (not bd or d2 < bd) then
				shotTr.start, shotTr.endpos, shotTr.filter = s:EyePos(), head, { s }
				local tr = util.TraceLine(shotTr)

				if tr.Entity == npc then
					best, bd = s, d2
				end
			end
		end
	end

	if not best then return false end

	local to = head - best:GetPos()
	best:SetAngles(Angle(0, math.deg(math.atan2(to.y, to.x)), 0))
	local def = best.tifWep and best.tifWep.def
	local snd = def and def.mw and def.mw.fire
	best:EmitSound((snd and sound.GetProperties(snd) and snd) or (def and def.sound) or "Weapon_AR2.Single", 95, 100, 1, CHAN_WEAPON)

	if best.SetTIFShotTime then
		best:SetTIFShotTime(now)
	end

	if TIF.Event then
		TIF.Event("shield", "AI shot at captor ", npc:EntIndex(), " by ", best:EntIndex())
	end

	if math.random() > SH.AI_SHOT_WIN then return false end

	sc.killer = best
	play(sc, sc.var.shot, now)
	return true
end

hook.Add("Tick", "tif_shield", function()
	if next(SH.List) == nil then return end

	local now = CurTime()
	for sc in pairs(SH.List) do
		local ok, err = pcall(tick_scene, sc, now)
		if not ok then
			TIF.Error("Human shield: ", tostring(err))
			pcall(finish, sc, "removed")
		end
	end
end)

function SH.Busy(npc, now)
	local sc = npc.tifShield
	if not sc then return false end

	if sc.done then
		npc.tifShield = nil
		return false
	end

	TIF.Move.Stop(npc)
	npc.tifFire.want = false
	npc.tifFace = nil
	return true
end

function SH.Seen(ents_)
	for _, ply in player.Iterator() do
		if ply:Alive() then
			local eye = ply:EyePos()
			local aim = ply:GetAimVector()

			for _, e in ipairs(ents_) do
				local p = e:GetPos() + Vector(0, 0, 48)
				local to = p - eye
				local d = to:Length()

				if d < SH.SEE_DIST and (d < 1 or to:Dot(aim) / d > 0.45) then
					local tr = util.TraceLine({ start = eye, endpos = p, mask = MASK_SOLID_BRUSHONLY })
					if not tr.Hit or tr.Fraction > 0.97 then return true end
				end
			end
		end
	end

	return false
end

function SH.Try(npc, c, now)
	if not (cvShield:GetBool() and c and c.visible and IsValid(c.ent)) then
		return false
	end

	if now < (npc.tifShieldTry or 0) or now < (npc.tifShieldNext or 0) then
		return false
	end

	npc.tifShieldTry = now + SH.TRY_EVERY

	if table.Count(SH.List) >= SH.MAX or not captor_ok(npc, "mw19") or not free(npc) then
		return false
	end

	if math.random() > SH.CHANCE then return false end

	local bad = false
	for _, p in player.Iterator() do
		if TIF.Relation(npc, p) == TIF.REL_HOSTILE then
			bad = true
			break
		end
	end

	if not bad or not (TIF.Civ and TIF.Civ.List) then return false end

	local pos = npc:GetPos()
	local toE = c.ent:GetPos() - pos
	toE.z = 0
	local de = toE:Length()
	if de < SH.ENEMY_MIN or de > SH.ENEMY_MAX then return false end

	local enemyYaw = math.deg(math.atan2(toE.y, toE.x))
	local civs = {}

	for _, civ in ipairs(TIF.Civ.List()) do
		if hostage_ok(civ) and civ.state ~= "leave" and math.abs(civ:GetPos().z - pos.z) < 20 then
			civs[#civs + 1] = civ
		end
	end

	if #civs == 0 then return false end

	if captor_ok(npc, "ch") then
		local best, bd
		for _, civ in ipairs(civs) do
			local d2 = civ:GetPos():DistToSqr(pos)
			if d2 <= SH.CH_GRAB * SH.CH_GRAB and (not bd or d2 < bd) then
				best, bd = civ, d2
			end
		end

		if best and not SH.Seen({ npc, best }) then
			local sc = SH.Start(npc, best, { variant = "ch", yaw = enemyYaw - SH.CH_FACE })
			if sc then return true end
		end
	end

	local sx, sy = SH.Sample("mwsh_grab_vic", 0)
	local sa, sr = math.deg(math.atan2(sy, sx)), math.sqrt(sx * sx + sy * sy)
	local want = enemyYaw - SH.FACE
	local best, bd, byaw

	for _, civ in ipairs(civs) do
		local to = civ:GetPos() - pos
		to.z = 0
		local yaw = math.deg(math.atan2(to.y, to.x)) - sa
		local snap = math.abs(to:Length() - sr)

		if snap <= SH.SNAP and math.abs(math.AngleDifference(yaw, want)) <= SH.MW_SWING and (not bd or snap < bd) then
			best, bd, byaw = civ, snap, yaw
		end
	end

	if not best then return false end

	local r = math.rad(byaw)
	local spot = pos + Vector(sx * math.cos(r) - sy * math.sin(r), sx * math.sin(r) + sy * math.cos(r), 0)
	local g = util.TraceLine({ start = spot + Vector(0, 0, 30), endpos = spot - Vector(0, 0, 40), mask = MASK_NPCSOLID_BRUSHONLY })
	if not g.Hit or math.abs(g.HitPos.z - pos.z) > 14 then return false end

	return SH.Start(npc, best, { yaw = byaw }) ~= nil
end

hook.Add("EntityTakeDamage", "tif_shield", function(ent, dmg)
	local sc = ent.tifShield
	if sc and not sc.done and not ent.tifShieldKilling then
		local att = dmg:GetAttacker()
		local var = sc.var

		if att == sc.hostage then
			dmg:ScaleDamage(0)
			return true
		end

		if sc.phase == var.shot or sc.phase == var.vdeath or sc.phase == var.vdeathHead then
			dmg:ScaleDamage(0)
			return true
		end

		if dmg:IsExplosionDamage() and dmg:GetDamage() >= ent:Health() then
			ent.tifActLock = nil
			return
		end

		dmg:ScaleDamage(0)
		sc.killer = att
		play(sc, var.shot, CurTime())
		return true
	end

	local hs = ent.tifHeld
	if hs and not hs.done and not ent.tifShieldKilling then
		local att = dmg:GetAttacker()
		if att == hs.captor then
			dmg:ScaleDamage(0)
			return true
		end

		local var = hs.var
		if var.vdeath then
			if hs.phase == var.vdeath or hs.phase == var.vdeathHead or hs.phase == var.shot then
				dmg:ScaleDamage(0)
				return true
			end

			local head = dmg:GetDamagePosition().z > ent:GetPos().z + 50
			hs.killer = att
			dmg:ScaleDamage(0)
			play(hs, head and var.vdeathHead or var.vdeath, CurTime())
			return true
		end
	end
end)

hook.Add("EntityRemoved", "tif_shield", function(ent)
	local sc = ent.tifShield or ent.tifHeld
	if sc and not sc.done then
		local why = (ent == sc.hostage and ent:Health() <= 0 and "hostage_killed") or (ent == sc.captor and ent.tifDead and "captor_killed") or "removed"
		finish(sc, why)
	end
end)

function SH.Hostages()
	local out = {}
	for sc in pairs(SH.List) do
		if IsValid(sc.hostage) and sc.hostage:Health() > 0 then
			out[sc.hostage] = sc.captor
		end
	end

	return out
end
