-- Casualties (Phase 7): wounded soldiers who go down instead of dying, and squadmates who come
-- to get them back up.
--
-- Going down:  a hit that would kill has a chance (tif_downed_chance) to leave the soldier on the
--              ground at 10 health instead. Not for head shots, blasts, or hits over 150 damage.
--              Downed: lying on the back (first frame of GTG's injured get-up from the back), gun
--              put away, out of the fight (enemies stop targeting them). Any further damage kills.
-- Bleeding out: dies after tif_bleedout seconds unless treated.
-- Treating:    the nearest squadmate (within 1500, not the leader if anyone else can) runs over when
--              no enemy is in sight of it within 800, kneels beside the casualty for 5 s, and the
--              casualty gets up (injured get-up to the knees, then to standing) with 40 health.
--              "man down" / "cover me" callouts. If the medic sees an enemy it fights and comes
--              back after.

local TIF = TIF
local AW = TIF.AWARE
local A = TIF.Anim
local Act = TIF.Action
local Move = TIF.Move

TIF.Casualty = TIF.Casualty or {}
local CAS = TIF.Casualty
CAS.Downed = CAS.Downed or {}

local cvOn = CreateConVar("tif_downed", "1", FCVAR_ARCHIVE, "Soldiers can be wounded and go down instead of dying (1/0)")
local cvChance = CreateConVar("tif_downed_chance", "0.2", FCVAR_ARCHIVE, "Chance that a killing hit downs a soldier instead (0..1)")
local cvBleed = CreateConVar("tif_bleedout", "45", FCVAR_ARCHIVE, "Seconds a downed soldier lasts without treatment")

CAS.TREAT_TIME = 5
CAS.MEDIC_RANGE = 1500
-- Rarity (like CoD): never one of the last men standing (at least MIN_ALLIES able friendlies within
-- ALLY_RANGE), one casualty per squad at a time, and SQUAD_COOLDOWN seconds before the squad's next.
CAS.MIN_ALLIES = 2
CAS.ALLY_RANGE = 1500
CAS.SQUAD_COOLDOWN = 40

local function able(o)
	return IsValid(o) and not o.tifDead and not o.tifDowned and not o.tifSurrendered and o.tifMoraleState ~= "broken"
end

function CAS.CanGoDown(npc, now)
	local sq = npc.tifSquad
	if sq then
		if now < (sq.nextDown or 0) then return false end
		for _, m in ipairs(TIF.Squad.Members(sq)) do
			if m ~= npc and IsValid(m) and m.tifDowned then return false end
		end
	end
	local n, r2, pos = 0, CAS.ALLY_RANGE * CAS.ALLY_RANGE, npc:GetPos()
	for _, o in ipairs(TIF.Soldiers) do
		if o ~= npc and able(o) and o:GetPos():DistToSqr(pos) < r2 and TIF.Relation(npc, o) == TIF.REL_ALLY then
			n = n + 1
			if n >= CAS.MIN_ALLIES then return true end
		end
	end
	return false
end

local DOWN_CLIPS = { "getup_tki_back", "getup_tk_back", "getup_ts_back" }
local UP_CLIPS = { { "getup_tki_back", "getup_tk_back" }, { "getup_dki_getup_r_0", "getup_dki_getup_l_0" } }

local function log(npc, ...)
	local sq = npc.tifSquad
	if sq and TIF.Squad.Log then TIF.Squad.Log(sq, "[casualty] #", npc:EntIndex(), " ", ...) end
end

local function first_clip(npc, list)
	for _, n in ipairs(list) do if Act.Clip(npc, n) then return n end end
	return nil
end

-- Called from EntityTakeDamage before the damage lands. Returns true if the soldier went down.
function CAS.TryDown(npc, dmg)
	if not cvOn:GetBool() or npc.tifDowned or npc.tifDead or npc.tifVeh or npc.tifSurrendered or npc.tifNoDown then return false end
	local amount = dmg:GetDamage()
	if amount < npc:Health() then return false end
	if amount > 150 or dmg:IsExplosionDamage() or npc.tifLastHitGroup == HITGROUP_HEAD then return false end
	if math.random() > cvChance:GetFloat() then return false end
	local now = CurTime()
	if not CAS.CanGoDown(npc, now) then return false end
	dmg:SetDamage(math.max(0, npc:Health() - 10))
	CAS.Down(npc, dmg)
	return true
end

function CAS.Down(npc, dmg)
	local now = CurTime()
	npc.tifDowned = { t0 = now, bleed = now + cvBleed:GetFloat() }
	CAS.Downed[npc] = true
	if npc.tifSquad then npc.tifSquad.nextDown = now + CAS.SQUAD_COOLDOWN end
	if TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "downed") end
	if TIF.ProneB.Is(npc) then
		npc.tifDowned.wasProne = true
		npc.tifProne = nil
	end
	if npc:GetNW2Int("tif_prone", 0) ~= 0 then
		npc:SetNW2Int("tif_prone", 0)
		npc:SetNW2Float("tif_prone_t", now)
	end
	Move.Stop(npc)
	npc.tifFire.want = false
	npc.tifDownedWeapon = npc:GetTIFWeapon()
	npc:SetTIFWeapon("")
	-- MW19 body: its last stand (falls, lies wounded, crawls a little; TIF.LastStandMW).
	local LS = TIF.LastStandMW
	if LS and LS.Use(npc) then
		LS.Down(npc, dmg, now)
	else
		local clip = first_clip(npc, DOWN_CLIPS)
		if clip then
			Act.Play(npc, clip)
			npc:SetNW2Float("tif_act_cycle", 0)
		end
	end
	npc.tifHitboxPose = "down"
	npc:SetNW2Bool("tif_downed", true)
	log(npc, "down")
	TIF.Say(npc, "pain", 1)
	-- Someone calls it.
	local sq = npc.tifSquad
	for _, m in ipairs(sq and TIF.Squad.Members(sq) or {}) do
		if m ~= npc and not m.tifDowned then TIF.Say(m, "man_down", 0.8) break end
	end
	if TIF.Morale then
		for _, m in ipairs(sq and TIF.Squad.Members(sq) or {}) do if m ~= npc then TIF.Morale.Add(m, -0.08) end end
	end
end

-- Back on his feet (treated).
local function back_up(npc)
	npc.tifDowned = nil
	CAS.Downed[npc] = nil
	Act.Clear(npc)
	npc:SetHealth(math.max(npc:Health(), 40))
	npc:SetTIFWeapon(npc.tifDownedWeapon ~= "" and npc.tifDownedWeapon or (npc.tifWep and npc.tifWep.class or ""))
	npc.tifHitboxPose = nil
	npc:SetNW2Bool("tif_downed", false)
	if TIF.Morale then TIF.Morale.Add(npc, 0.15) end
	log(npc, "back up")
end
CAS.BackUp = back_up

local function revive(npc, now)
	local d = npc.tifDowned
	if not d then return end
	-- MW19 body: its own get-up (the revive clips already played).
	local LS = TIF.LastStandMW
	if LS and LS.Use(npc) then
		if LS.GetUp(npc, d, now) then back_up(npc) end
		return
	end
	d.getUp = d.getUp or { step = 0 }
	local g = d.getUp
	if g.step == 0 then
		npc:SetNW2Float("tif_act_cycle", -1)
		local c1 = first_clip(npc, UP_CLIPS[1])
		g.step, g.until_ = 1, now + (c1 and Act.Play(npc, c1, { root = true }) or 0)
		return
	end
	if g.step == 1 and now >= g.until_ then
		local c2 = first_clip(npc, UP_CLIPS[2])
		g.step, g.until_ = 2, now + (c2 and Act.Play(npc, c2, { root = true }) or 0)
		return
	end
	if g.step == 2 and now >= g.until_ then back_up(npc) end
end

-- Every think of a downed soldier.
function CAS.DownThink(npc, now)
	local d = npc.tifDowned
	npc.tifFire.want = false
	npc.tifFace = nil
	npc.tifStance = A.STANCE_CROUCH
	npc.tifMode = A.MODE_RELAXED
	local LS = TIF.LastStandMW
	local mw = LS and LS.Use(npc)
	if not mw then Move.Stop(npc) end
	if d.treated or d.getUp then
		if mw then Move.Stop(npc) end
		npc.tifAction = "getting up"
		revive(npc, now)
		return
	end
	npc.tifAction = string.format("downed (%ds)", math.max(0, d.bleed - now))
	-- MW19 body: lying wounded, a short crawl away from the enemy / toward friends; passing out at the end.
	if mw then
		-- A medic is working on him (the medic runs both sides' clips).
		if d.revive and LS.ReviveAlive(npc, d, now) then Move.Stop(npc) return end
		if LS.Think(npc, d, now) then return end
	end
	if now >= d.bleed then
		log(npc, "bled out")
		local dmg = DamageInfo()
		dmg:SetDamage(npc:Health() + 100)
		dmg:SetDamageType(DMG_GENERIC)
		dmg:SetAttacker(npc)
		dmg:SetInflictor(npc)
		npc.tifNoDown = true
		npc:TakeDamageInfo(dmg)
		return
	end
	if now > (d.nextPain or 0) then
		d.nextPain = now + math.Rand(4, 8)
		TIF.Say(npc, "pain", 0.5)
	end
end

-- Medics ------------------------------------------------------------------------------------------

-- Returns true while treating controls the soldier.
function CAS.MedicThink(npc, c, now)
	local m = npc.tifMedic
	local p = m.patient
	if not IsValid(p) or p.tifDead or not p.tifDowned or p.tifDowned.treated then
		npc.tifMedic = nil
		return false
	end
	-- An enemy in sight close by: fight first.
	if c and c.visible and npc:GetPos():DistToSqr(c.pos) < 800 * 800 then
		m.start = nil
		return false
	end
	local pos = p:GetPos()
	npc.tifFire.want = false
	if npc:GetPos():DistToSqr(pos) > 60 * 60 then
		local CBh = TIF.CoverBehave
		if CBh and CBh.In(npc) then
			local MWc = CBh.MW
			if MWc and MWc.ExitTo and MWc.ExitTo(npc, pos, "medic") then
				npc.tifAction = "leaving cover for the casualty"
				return true
			end
			if CBh.In(npc) then CBh.Leave(npc, "medic") end
		end
		npc.tifAction = "to the casualty"
		npc.tifStance = A.STANCE_STAND
		npc.tifFace = nil
		if not m.said then m.said = true TIF.Say(npc, "cover_me", 0.7) end
		-- (Sprints to him, or the aimed walk for the last few steps: the fight gaits, no jog with the gun down.)
		if not Move.SetGoal(npc, pos, Move.CombatGait(npc, pos), "medic") then npc.tifMedic = nil return false end
		m.start = nil
		return true
	end
	-- MW19 bodies (both): MW19's revive, kneeling on the near side (TIF.LastStandMW).
	local LS = TIF.LastStandMW
	if LS and LS.Use(npc) and LS.Use(p) then
		npc.tifAction = "treating"
		if LS.MedicThink(npc, p, m, now) then return true end
		npc.tifMedic = nil
		return false
	end
	Move.Stop(npc)
	npc.tifStance = A.STANCE_CROUCH
	npc.tifFace = pos + Vector(0, 0, 10)
	npc.tifAction = "treating"
	m.start = m.start or now
	if now - m.start >= CAS.TREAT_TIME then
		p.tifDowned.treated = true
		npc.tifMedic = nil
		log(npc, "treated #", p:EntIndex())
	end
	return true
end

-- Twice a second: give each downed soldier a medic.
timer.Create("tif_casualty_tick", 0.5, 0, function()
	if TIF.AIDisabled() then return end
	for npc in pairs(CAS.Downed) do
		if not IsValid(npc) or npc.tifDead or not npc.tifDowned then
			CAS.Downed[npc] = nil
		elseif not npc.tifDowned.treated then
			local busy = false
			for _, o in ipairs(TIF.Soldiers) do
				if IsValid(o) and o.tifMedic and o.tifMedic.patient == npc then busy = true break end
			end
			local sq = npc.tifSquad
			if not busy and sq then
				local best, bestD
				for _, o in ipairs(TIF.Squad.Members(sq)) do
					if o ~= npc and not o.tifDowned and not o.tifMedic and not o.tifVeh and not o.tifCQB
						and not o.tifSurrendered and (o.tifMoraleState ~= "broken") then
						local d = o:GetPos():DistToSqr(npc:GetPos())
						if o == sq.leader then d = d * 4 end
						if d < CAS.MEDIC_RANGE ^ 2 and (not bestD or d < bestD) then best, bestD = o, d end
					end
				end
				if best then
					best.tifMedic = { patient = npc }
					log(best, "going to treat #", npc:EntIndex())
				end
			end
		end
	end
end)

hook.Add("EntityTakeDamage", "tif_casualty", function(ent, dmg)
	if ent.TIFSoldier then CAS.TryDown(ent, dmg) end
end)
