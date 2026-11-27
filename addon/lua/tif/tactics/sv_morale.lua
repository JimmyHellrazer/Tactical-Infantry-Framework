local TIF = TIF
local AW = TIF.AWARE
local A = TIF.Anim
local Act = TIF.Action
local Move = TIF.Move

TIF.Morale = TIF.Morale or {}
local MO = TIF.Morale

local cvOn = CreateConVar("tif_morale", "1", FCVAR_ARCHIVE, "Soldiers get shaken and break (1/0)")

MO.SHAKEN, MO.BROKEN, MO.RECOVER = 0.45, 0.2, 0.35

MO.OFF = false
MO.SURRENDER = false

function MO.Enabled()
	return not MO.OFF and cvOn:GetBool()
end

local function base_of(npc)
	return math.Clamp(0.65 + 0.4 * (npc.tifArch.suppressResist or 0.3), 0.5, 0.95)
end

function MO.Init(npc)
	npc.tifMorale = base_of(npc)
	npc.tifMoraleState = "steady"
end

local function log(npc, ...)
	local sq = npc.tifSquad
	if sq and TIF.Squad.Log then
		TIF.Squad.Log(sq, "[morale] #", npc:EntIndex(), " ", ...)
	end
end

local function set_state(npc, st, now)
	if npc.tifMoraleState == st then return end

	log(npc, npc.tifMoraleState or "?", " -> ", st, string.format(" (%.2f)", npc.tifMorale))
	npc.tifMoraleState = st
	npc.tifMoraleSince = now
	npc:SetNW2String("tif_morale", st)

	if st ~= "broken" then
		npc.tifPanic = nil
	end

	if st == "broken" then
		TIF.Say(npc, "retreat", 0.6)
	end
end

function MO.Add(npc, amount)
	if not IsValid(npc) or not npc.tifMorale or npc.tifDead then return end

	if amount < 0 and npc.tifMoraleScale then
		amount = amount * npc.tifMoraleScale
	end

	npc.tifMorale = math.Clamp(npc.tifMorale + amount, 0, 1)
end

function MO.State(npc)
	return npc.tifMoraleState or "steady"
end

function MO.Shaken(npc)
	return MO.Enabled() and npc.tifMoraleState ~= nil and npc.tifMoraleState ~= "steady"
end

function MO.OnDeath(npc, attacker)
	if not MO.Enabled() then return end

	local pos, fac, sq = npc:GetPos(), npc:GetTIFFaction(), npc.tifSquad
	local wasLeader = sq and sq.leader == npc

	for _, o in ipairs(TIF.Soldiers) do
		if o ~= npc and IsValid(o) and not o.tifDead and o:GetTIFFaction() == fac then
			local d2 = o:GetPos():DistToSqr(pos)
			if o.tifSquad == sq and sq then
				MO.Add(o, wasLeader and -0.38 or -0.18)
			elseif d2 < 1000 * 1000 then
				MO.Add(o, -0.10)
			end
		end
	end

	if IsValid(attacker) and attacker.TIFSoldier then
		MO.Add(attacker, 0.08)
		local asq = attacker.tifSquad

		if asq then
			for _, m in ipairs(TIF.Squad.Members(asq)) do
				if m ~= attacker then
					MO.Add(m, 0.03)
				end
			end
		end
	end
end

function MO.OnHurt(npc, dmg)
	if not MO.Enabled() then return end

	MO.Add(npc, -math.min(0.25, dmg / 120))
end

hook.Add("PlayerDeath", "tif_morale_kills", function(ply, inflictor, attacker)
	if IsValid(attacker) and attacker.TIFSoldier then
		MO.Add(attacker, 0.08)
		local sq = attacker.tifSquad

		if sq then
			for _, m in ipairs(TIF.Squad.Members(sq)) do
				if m ~= attacker then
					MO.Add(m, 0.03)
				end
			end
		end
	end
end)

local function drift(npc, now)
	local supp = npc.tifSupp or 0
	local resist = npc.tifArch.suppressResist or 0.3
	local m = npc.tifMorale
	local loss = npc.tifMoraleScale or 1

	if supp > 0.4 then
		m = m - (supp - 0.4) * 0.06 * (1 - resist) * loss
	end

	local sq = npc.tifSquad
	if sq and sq.knowledge then
		local enemies = 0
		for ent, k in pairs(sq.knowledge) do
			if now - k.time < 10 and TIF.IsLiveCombatant(ent) then
				enemies = enemies + 1
			end
		end

		local mine = #TIF.Squad.Members(sq)
		if enemies > mine * 1.5 then
			m = m - 0.012 * loss
		end
	end

	local quiet = supp < 0.1 and now - (npc:GetTIFHitTime() or 0) > 5
	if quiet then
		local base = base_of(npc)
		local rate = 0.02

		if sq and IsValid(sq.leader) and sq.leader ~= npc and sq.leader:GetPos():DistToSqr(npc:GetPos()) < 600 * 600 then
			rate = 0.035
		end

		if m < base then
			m = math.min(base, m + rate)
		end
	end

	npc.tifMorale = math.Clamp(m, 0, 1)

	local st = npc.tifMoraleState or "steady"
	if st == "broken" then
		if npc.tifMorale > MO.RECOVER and now - (npc.tifMoraleSince or now) > 12 then
			set_state(npc, npc.tifMorale > MO.SHAKEN and "steady" or "shaken", now)
		end
	elseif npc.tifMorale < MO.BROKEN then
		set_state(npc, "broken", now)
	elseif npc.tifMorale < MO.SHAKEN then
		set_state(npc, "shaken", now)
	elseif npc.tifMorale > MO.SHAKEN + 0.05 then
		set_state(npc, "steady", now)
	end
end

timer.Create("tif_morale_tick", 1, 0, function()
	if not MO.Enabled() or TIF.AIDisabled() then return end

	local now = CurTime()
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) and not npc.tifDead and npc.tifMorale and not npc.tifSurrendered then
			drift(npc, now)
		end
	end
end)

function MO.Kneel(npc, quick)
	local down = not quick and Act.Clip(npc, "mwsu_down") and Act.Play(npc, "mwsu_down", { root = true, clear = true })
	if down then
		npc.tifKneelLoopAt = CurTime() + down * 0.97
	else
		npc.tifKneelLoopAt = nil

		if Act.Clip(npc, "mwsu_idle") then
			Act.Loop(npc, "mwsu_idle")
		end
	end

	npc.tifHitboxPose = "crouch"
end

local function kneel_think(npc, now)
	if npc.tifKneelLoopAt and now >= npc.tifKneelLoopAt then
		npc.tifKneelLoopAt = nil

		if Act.Clip(npc, "mwsu_idle") then
			Act.Loop(npc, "mwsu_idle")
		end
	end
end

MO.KneelThink = kneel_think

function MO.Surrender(npc, now)
	if npc.tifSurrendered then return end

	npc.tifSurrendered = true
	log(npc, "surrenders")

	if TIF.CoverBehave.In(npc) then
		TIF.CoverBehave.Leave(npc, "surrender")
	end

	if TIF.ProneB.Is(npc) then
		npc.tifProne = nil
	end

	Move.Stop(npc)
	pcall(npc.TIFDropWeapon, npc)
	npc:SetTIFWeapon("")
	npc.tifFire.want = false
	TIF.Squad.Remove(npc)
	npc:SetNW2Bool("tif_surrendered", true)
	npc:SetNW2String("tif_morale", "surrendered")
	MO.Kneel(npc)
	TIF.Say(npc, "negative", 0.8)
end

function MO.SurrenderThink(npc, now)
	npc.tifFire.want = false
	npc.tifFace = nil
	npc.tifMode = A.MODE_RELAXED
	npc.tifStance = A.STANCE_CROUCH
	npc.tifAction = "surrendered"
	Move.Stop(npc)
	kneel_think(npc, now or CurTime())
end

MO.PANIC_HIDE, MO.PANIC_RUN = 1000, 400
MO.PANIC_RUN_GAP = { 1.0, 2.0 }

local function panic_target(npc, c, now, range)
	if not (c and IsValid(c.ent)) then return nil end
	if not (c.visible or now - (c.seenAt or -99) < 1) then return nil end
	if npc:GetPos():DistToSqr(c.pos) > range * range then return nil end

	return c.visible and c.ent:WorldSpaceCenter() or (c.pos + Vector(0, 0, 40))
end

function MO.BrokenThink(npc, c, now)
	if not MO.Enabled() or npc.tifMoraleState ~= "broken" then
		npc.tifFlee = nil
		npc.tifPanic = nil
		return false
	end

	npc.tifPanic = true
	local f = npc.tifFire
	f.want = false
	local threat = c and c.pos

	if MO.SURRENDER and c and c.visible and npc:GetPos():DistToSqr(c.pos) < 500 * 500 then
		local helpers = 0
		for _, o in ipairs(TIF.Soldiers) do
			if o ~= npc and IsValid(o) and not o.tifDead and not o.tifSurrendered and o:GetTIFFaction() == npc:GetTIFFaction()
				and o:GetPos():DistToSqr(npc:GetPos()) < 600 * 600 then
					helpers = helpers + 1
				end
		end

		local hurt = npc:Health() < npc:GetMaxHealth() * 0.5
		if (helpers == 0 or hurt) and not npc.tifSurrenderRolled then
			npc.tifSurrenderRolled = true

			if math.random() < 0.65 then
				MO.Surrender(npc, now)
				return true
			end
		end
	end

	local fl = npc.tifFlee
	if not fl or (threat and fl.from:DistToSqr(threat) > 400 * 400) then
		local away = threat and (npc:GetPos() - threat) or npc:GetForward() * -1
		away.z = 0
		away:Normalize()
		local goal = Move.Snap(npc:GetPos() + away * 1200) or Move.Snap(npc:GetPos() + away * 600)
		fl = { goal = goal, from = threat and Vector(threat) or npc:GetPos() }
		npc.tifFlee = fl

		if TIF.CoverBehave.In(npc) then
			TIF.CoverBehave.Leave(npc, "broken")
		end
	end

	npc.tifMode = A.MODE_RELAXED
	local W = TIF.Weapon

	if fl.goal and npc:GetPos():DistToSqr(fl.goal) > 80 * 80 then
		npc.tifAction = "broken: running"
		npc.tifStance = A.STANCE_STAND
		npc.tifFace = nil

		if not Move.SetGoal(npc, fl.goal, "sprint", "flee") then
			fl.goal = nil
		end

		local aim = panic_target(npc, c, now, MO.PANIC_RUN)
		local w = npc.tifWep
		if aim and w and w.reloadEnd <= 0 and w.ammo > 0 and not (w.def and w.def.projectile)
			and now >= (npc.tifPanicNext or 0) and not (W.CoverFiring and W.CoverFiring(npc, now)) then
			npc.tifCoverFire = { untilT = now + math.Rand(0.7, 1.1), aim = aim, shots = math.random(5, 9) }
			npc.tifPanicNext = now + math.Rand(MO.PANIC_RUN_GAP[1], MO.PANIC_RUN_GAP[2])
			w.burstLeft = 0
			npc.tifAction = "broken: running, firing back"
		end
	else
		npc.tifAction = "broken: hiding"
		npc.tifStance = A.STANCE_CROUCH
		Move.Stop(npc)
		npc.tifFace = threat and (threat + Vector(0, 0, 40)) or nil
		local aim = panic_target(npc, c, now, MO.PANIC_HIDE)

		if aim then
			npc.tifMode = A.MODE_AIM
			f.want, f.aimPos, f.target = true, aim, c.ent
			npc.tifAction = "broken: panic firing"
		end
	end

	return true
end

function MO.SquadAverage(sq)
	local sum, n = 0, 0
	for _, m in ipairs(TIF.Squad.Members(sq)) do
		if m.tifMorale then
			sum, n = sum + m.tifMorale, n + 1
		end
	end

	return n > 0 and sum / n or 1
end
