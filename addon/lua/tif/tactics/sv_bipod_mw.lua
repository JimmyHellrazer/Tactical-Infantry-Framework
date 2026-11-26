local TIF = TIF
local Act = TIF.Action
local AW = TIF.AWARE

TIF.BipodMW = TIF.BipodMW or {}
local B = TIF.BipodMW

B.SETS = {
	{ name = "crouch", lo = 28, hi = 40, gun = 42, stance = 1 },
	{ name = "stand", lo = 40, hi = 50, gun = 52, stance = 0 },
	{ name = "high", lo = 50, hi = 60, gun = 58, stance = 0 },
}
B.STANDOFF = 18
B.ARC = 70
B.CHECK_EVERY = { 2, 4 }
B.HOLD_MAX = 30
B.PRONE_SET_AFTER = 0.4
B.PRONE_HOLD = 1.2

local UP40 = Vector(0, 0, 40)

local function trace(a, b, skip)
	return util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID, filter = function(x)
		return x ~= skip and not (x:IsNPC() or x:IsNextBot() or x:IsPlayer())
	end })
end

local function lmg(npc)
	return npc.tifWep and TIF.GTG.WeaponKind(npc.tifWep.class) == "lmg"
end

function B.Use(npc)
	return npc.tifHomeHost ~= nil and npc.tifHostId == npc.tifHomeHost and TIF.GTG.IsVB(npc.tifHostId)
		and lmg(npc) and TIF.GTG.Clip("mwb_stand_aim", npc.tifHomeHost) ~= nil
end

function B.Set(npc, now)
	local b = npc.tifBipod
	if b and b.phase == "aim" then return true end
	local p = npc.tifProne
	if p and p.phase == 2 and lmg(npc) then
		npc.tifProneStill = npc.tifProneStill or now
		if npc.loco:GetVelocity():Length2DSqr() > 25 then npc.tifProneStill = now end

		if npc:GetTIFMode() == 1 then npc.tifProneAimAt = now
		elseif now - (npc.tifProneAimAt or -99) > B.PRONE_HOLD then npc.tifProneStill = now end
		return now - npc.tifProneStill >= B.PRONE_SET_AFTER
	end
	npc.tifProneStill = nil
	return false
end

function B.Find(npc, yaw)
	local base = npc:GetPos()
	local r = math.rad(yaw)
	local d = Vector(math.cos(r), math.sin(r), 0)
	local low = trace(base + Vector(0, 0, 22), base + Vector(0, 0, 22) + d * 40, npc)
	if not low.Hit or math.abs(low.HitNormal.z) > 0.5 then return nil end
	local dist = low.Fraction * 40
	if dist < 12 then return nil end
	local inside = base + d * (dist + 5)
	local top = trace(inside + Vector(0, 0, 70), inside + Vector(0, 0, 20), npc)
	if not top.Hit then return nil end
	local h = top.HitPos.z - base.z
	for _, s in ipairs(B.SETS) do
		if h >= s.lo and h < s.hi then

			local over = trace(Vector(inside.x, inside.y, base.z + h + 8), Vector(inside.x, inside.y, base.z + h + 8) + d * 60, npc)
			if over.Hit then return nil end
			if not TIF.GTG.Clip("mwb_" .. s.name .. "_aim", npc.tifHomeHost) then return nil end
			return { set = s, pos = base + d * (dist - B.STANDOFF), yaw = yaw }
		end
	end
	return nil
end

local function stop(npc)
	npc.tifBipod = nil
	npc.tifAimAt, npc.tifAimFree, npc.tifMuzzle = nil, nil, nil
	if npc:GetNW2Float("tif_aim_yaw", 0) ~= 0 then npc:SetNW2Float("tif_aim_yaw", 0) end
end
B.Stop = stop

local function pack(npc, b, now)
	if b.phase == "out" then return now < b.untilT end
	if b.phase == "in" then
		b.leave = true
		npc.tifAction = "bipod: packing up"

		if now < b.untilT then return true end
		b.phase = "aim"
	end
	local d = Act.Play(npc, "mwb_" .. b.set.name .. "_out", { root = true, to = { pos = npc:GetPos(), yaw = npc:GetAngles().y }, clear = true })
	npc.tifAimAt, npc.tifAimFree, npc.tifMuzzle = nil, nil, nil
	b.phase, b.untilT = "out", now + (d or 0)
	return (d or 0) > 0
end

function B.Update(npc, c, now)
	local b = npc.tifBipod
	if not b then
		if not B.Use(npc) or not c or not c.visible or npc.tifAct or npc.tifCov or npc.tifProne or npc.tifVeh
			or TIF.Move.Moving(npc) or now < (npc.tifNextBipod or 0) then return false end
		npc.tifNextBipod = now + math.Rand(B.CHECK_EVERY[1], B.CHECK_EVERY[2])
		local spot = B.Find(npc, (c.pos - npc:GetPos()):Angle().y)
		if not spot then return false end
		local d = Act.Play(npc, "mwb_" .. spot.set.name .. "_in", { root = true, to = { pos = spot.pos, yaw = spot.yaw } })
		if not d then return false end
		npc.tifBipod = { set = spot.set, phase = "in", untilT = now + d, since = now, yaw = spot.yaw }
		npc:SetTIFStance(spot.set.stance)
		npc.tifStance = spot.set.stance
		npc.tifFire.want = false
		npc.tifAction = "bipod: setting up"
		return true
	end
	local f = npc.tifFire
	npc.tifStance = b.set.stance
	if b.phase == "out" then
		f.want = false
		if now < b.untilT then npc.tifAction = "bipod: packing up" return true end
		stop(npc)
		npc.tifNextBipod = now + 6
		return false
	end

	local a = npc.tifAct
	if not a or string.sub(a.name or "", 1, 4) ~= "mwb_" then stop(npc) return false end
	if b.phase == "in" then
		f.want = false
		npc.tifAction = "bipod: setting up"
		if now >= b.untilT then
			Act.Loop(npc, "mwb_" .. b.set.name .. "_aim")
			b.phase = "aim"

			if b.leave then pack(npc, b, now) end
		end
		return true
	end

	npc.tifFace = nil
	npc.tifAimFree = true
	local lost = c and (now - math.max(c.seenAt or 0, c.heardAt or 0)) or 99
	local aim = c and (c.visible and c.ent:WorldSpaceCenter() + Vector(0, 0, 6) or c.pos + UP40) or nil
	local yaw = aim and math.AngleDifference((aim - npc:GetPos()):Angle().y, npc:GetAngles().y) or 0

	if not c or lost > 5 or math.abs(yaw) > B.ARC or now - b.since > B.HOLD_MAX or npc.tifAware ~= AW.ENGAGED
		or (npc.tifSupp or 0) > 0.9 then
		f.want = false
		pack(npc, b, now)
		npc.tifAction = "bipod: packing up"
		return true
	end
	npc.tifAimAt = aim
	local r = math.rad(npc:GetAngles().y)
	npc.tifMuzzle = npc:GetPos() + Vector(math.cos(r), math.sin(r), 0) * 30 + Vector(0, 0, b.set.gun)
	if math.abs(yaw - npc:GetNW2Float("tif_aim_yaw", 0)) > 1 then npc:SetNW2Float("tif_aim_yaw", yaw) end

	f.want = c.visible or lost < 2.5
	f.aimPos, f.target = aim, c.ent
	npc.tifAction = c.visible and "bipod: firing" or "bipod: suppressing"
	return true
end

function B.Leave(npc, now)
	local b = npc.tifBipod
	if not b then return false end
	return pack(npc, b, now)
end
