local TIF = TIF
local Act = TIF.Action
local Move = TIF.Move

TIF.LastStandMW = TIF.LastStandMW or {}
local LS = TIF.LastStandMW

LS.CRAWL_DIST = 220
LS.CRAWL_TIME = 7
LS.LOOP_TIME = 3.5
LS.KNEEL = 30
LS.CHEST = { x = -6, y = -9 }

local function has(npc, n) return npc.tifHomeHost and TIF.GTG.Clip(n, npc.tifHomeHost) ~= nil end

function LS.Use(npc)
	return TIF.HitsMW and TIF.HitsMW.Use(npc) and has(npc, "mwls_idle") and has(npc, "mwls_getup")
end

local function frame(npc)
	local r = math.rad(npc:GetAngles().y)
	return Vector(math.cos(r), math.sin(r), 0), Vector(-math.sin(r), math.cos(r), 0)
end

local function chest(npc)
	local f, l = frame(npc)
	return npc:GetPos() + f * LS.CHEST.x + l * LS.CHEST.y
end

LS.FALL_END = 0.97

function LS.FallClip(npc, dmg)
	local d = npc.tifDowned
	if d and d.wasProne then return nil end
	local st = npc:GetTIFStance() == 1 and "cr" or "st"
	local side = "back"
	local f = dmg and dmg.GetDamageForce and dmg:GetDamageForce()
	if f and f:LengthSqr() > 1 and f:Dot(npc:GetRight()) < 0 then side = "l" end
	if math.random() < 0.25 then side = side == "l" and "back" or "l" end
	local name = "mwld_" .. st .. "_" .. side .. "_enter"
	if has(npc, name) then return name end
	name = "mwld_" .. st .. "_back_enter"
	return has(npc, name) and name or nil
end

function LS.Down(npc, dmg, now)
	local d = npc.tifDowned
	local name = LS.FallClip(npc, dmg)
	local dur = name and Act.Play(npc, name, { root = true }) or nil
	if dur then
		d.ls = { phase = "fall", untilT = now + dur * LS.FALL_END }
	else
		Act.Loop(npc, "mwls_idle")
		d.ls = { phase = "lying", since = now }
	end
	npc.tifHitboxPose = "down"
end

local CRAWL = { { 0, "fwd_0" }, { 45, "fwd_45" }, { 90, "fwd_90" }, { 135, "bwd_135" }, { 180, "bwd_180" },
	{ -135, "bwd_-135" }, { -90, "fwd_-90" }, { -45, "fwd_-45" } }
local function crawl_clip(rel)
	local best, bd
	for _, c in ipairs(CRAWL) do
		local d = math.abs(math.AngleDifference(rel, c[1]))
		if not bd or d < bd then best, bd = c[2], d end
	end
	return "mwls_crawl_" .. best .. "_loop"
end

local function crawl_goal(npc)
	local pos = npc:GetPos()
	local away = Vector(0, 0, 0)
	local c = npc.tifPrimaryC
	if c and c.pos then
		away = pos - c.pos
		away.z = 0
		away:Normalize()
	end
	local best, bd
	for _, o in ipairs(TIF.Soldiers) do
		if o ~= npc and IsValid(o) and not o.tifDead and not o.tifDowned and TIF.Relation(npc, o) == TIF.REL_ALLY then
			local dd = o:GetPos():DistToSqr(pos)
			if dd < 1500 * 1500 and (not bd or dd < bd) then best, bd = o, dd end
		end
	end
	local to = away
	if IsValid(best) then
		local t = best:GetPos() - pos
		t.z = 0
		t:Normalize()
		to = to + t
	end
	if to:LengthSqr() < 0.01 then return nil end
	to:Normalize()
	return pos + to * LS.CRAWL_DIST
end

function LS.Think(npc, d, now)
	local s = d.ls
	if not s then return false end

	if now >= d.bleed then
		if s.phase ~= "passout" then
			Move.Stop(npc)
			local n = "mwls_passout_" .. math.random(1, 2)
			local dur = Act.Play(npc, n, {}) or 0
			s.phase, s.untilT = "passout", now + dur * 0.9
		elseif now >= s.untilT then
			local dmg = DamageInfo()
			dmg:SetDamage(npc:Health() + 100)
			dmg:SetDamageType(DMG_GENERIC)
			dmg:SetAttacker(npc)
			dmg:SetInflictor(npc)
			npc.tifNoDown, npc.tifNoDeathClip = true, true
			npc:TakeDamageInfo(dmg)
		end
		return true
	end
	if s.phase == "fall" then
		Move.Stop(npc)
		if now >= s.untilT then
			Act.Loop(npc, "mwls_idle")
			s.phase, s.since = "lying", now
		end
		return true
	end

	if s.phase == "lying" and not s.crawled and now - s.since > math.Rand(1, 2.5) then
		s.crawled = true
		local g = crawl_goal(npc)
		if g and Move.SetGoal(npc, g, "crawl", "crawl") then s.phase, s.untilT = "crawl", now + LS.CRAWL_TIME end
	end
	if s.phase == "crawl" then
		local c = npc.tifPrimaryC
		npc.tifFace = c and c.pos or nil
		local v = npc.loco:GetVelocity()
		if not Move.Moving(npc) or now >= s.untilT then
			Move.Stop(npc)
			Act.Loop(npc, "mwls_idle")
			s.phase = "lying"
		elseif v:Length2DSqr() > 25 then
			local rel = math.AngleDifference(v:Angle().y, npc:GetAngles().y)
			local n = crawl_clip(rel)
			if not npc.tifAct or npc.tifAct.name ~= n then Act.Loop(npc, n) end
		end
		return true
	end
	Move.Stop(npc)
	return false
end

function LS.GetUp(npc, d, now)

	if d.buddyUp then
		d.buddyUp = nil
		return true
	end
	local s = d.ls or {}
	d.ls = s
	if s.phase ~= "getup" then
		local dur = Act.Play(npc, "mwls_getup", { root = true, clear = true }) or 0
		s.phase, s.untilT = "getup", now + dur
		return false
	end
	return now >= s.untilT
end

local NUM = { [8] = 0, [7] = 45, [4] = 90, [1] = 135, [2] = 180, [3] = -135, [6] = -90, [9] = -45 }
local function side(p, from)
	local rel = math.AngleDifference((from - p:GetPos()):Angle().y, p:GetAngles().y)
	local best, bd
	for n, a in pairs(NUM) do
		local d = math.abs(math.AngleDifference(rel, a))
		if has(p, "mwls_help_in_" .. n) and (not bd or d < bd) then best, bd = n, d end
	end
	return best
end

local function abort(p)
	local d = p.tifDowned
	if not d then return end
	d.revive = nil
	if d.ls then d.ls.phase, d.ls.since = "lying", CurTime() end
	Act.Loop(p, "mwls_idle")
end
LS.Abort = abort

LS.BUDDY_SHARE = 0.5
local function buddy_start(npc, p, d, now)
	local rel = math.AngleDifference((npc:GetPos() - p:GetPos()):Angle().y, p:GetAngles().y)
	local sd = rel > 0 and "4" or "6"
	local pre = "mwbr_laststand_"
	for _, ph in ipairs({ "in", "mid", "out" }) do
		if not (has(npc, pre .. "help_" .. ph .. "_" .. sd) and has(p, pre .. "hurt_" .. ph .. "_" .. sd)) then return nil end
	end
	Move.Stop(npc)
	Move.Stop(p)
	npc:SetPos(p:GetPos())
	npc:SetAngles(p:GetAngles())
	local dur = Act.Play(npc, pre .. "help_in_" .. sd, { root = true })
	if not dur then return nil end
	Act.Play(p, pre .. "hurt_in_" .. sd, { root = true })
	return { buddy = true, sd = sd, medic = npc, phase = "in", untilT = now + dur }
end

local function buddy_step(npc, p, d, r, now)
	if now < r.untilT then return true end
	local pre = "mwbr_laststand_"
	local nextPh = r.phase == "in" and "mid" or (r.phase == "mid" and "out" or nil)
	if not nextPh then
		d.revive = nil
		d.treated = true
		d.buddyUp = true
		if d.ls then d.ls.phase = nil end
		return false
	end
	local dur = Act.Play(npc, pre .. "help_" .. nextPh .. "_" .. r.sd, { root = true, clear = nextPh == "out" }) or 0
	Act.Play(p, pre .. "hurt_" .. nextPh .. "_" .. r.sd, { root = true })
	r.phase, r.untilT = nextPh, now + dur
	return true
end

function LS.MedicThink(npc, p, m, now)
	local d = p.tifDowned
	local r = d.revive
	npc.tifFire.want = false
	if not r and math.random() < LS.BUDDY_SHARE then
		r = buddy_start(npc, p, d, now)
		if r then
			d.revive = r
			TIF.Say(npc, "cover_me", 0.6)
		end
	end
	if r and r.buddy then
		r.seen = now
		npc.tifStance = TIF.Anim.STANCE_CROUCH
		npc.tifFace = nil
		return buddy_step(npc, p, d, r, now)
	end
	if not r then
		local n = side(p, npc:GetPos())
		if not n then return false end
		local c = chest(p)
		local yaw = p:GetAngles().y + NUM[n]
		local dir = Vector(math.cos(math.rad(yaw)), math.sin(math.rad(yaw)), 0)
		local spot = c + dir * LS.KNEEL
		Move.Stop(npc)
		Move.Stop(p)
		local dur = Act.Play(npc, "mwls_help_in_" .. n, { root = true, to = { pos = spot, yaw = (c - spot):Angle().y } })
		if not dur then return false end
		Act.Play(p, "mwls_hurt_in_" .. n)
		r = { n = n, medic = npc, phase = "in", untilT = now + dur }
		d.revive = r
		TIF.Say(npc, "cover_me", 0.6)
	end
	r.seen = now
	npc.tifStance = TIF.Anim.STANCE_CROUCH
	npc.tifFace = nil
	if r.phase == "in" and now >= r.untilT then
		Act.Loop(npc, "mwls_help_loop_" .. r.n)
		Act.Loop(p, "mwls_hurt_loop_" .. r.n)
		r.phase, r.untilT = "loop", now + LS.LOOP_TIME
	elseif r.phase == "loop" and now >= r.untilT then
		local dur = Act.Play(npc, "mwls_help_out_" .. r.n, { root = true, clear = true }) or 0
		Act.Play(p, "mwls_hurt_out_" .. r.n)
		r.phase, r.untilT = "out", now + dur
	elseif r.phase == "out" and now >= r.untilT then
		d.revive = nil
		d.treated = true
		if d.ls then d.ls.phase = nil end
		return false
	end
	return true
end

function LS.ReviveAlive(p, d, now)
	local r = d.revive
	if not r then return false end
	local m = r.medic
	if not IsValid(m) or m.tifDead or m.tifDowned or not m.tifMedic or m.tifMedic.patient ~= p or now - (r.seen or now) > 0.6 then
		abort(p)
		return false
	end
	return true
end
