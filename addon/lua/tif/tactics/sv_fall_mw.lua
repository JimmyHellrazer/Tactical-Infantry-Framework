local TIF = TIF
TIF.Fall = TIF.Fall or {}
local F = TIF.Fall

local cvOn = CreateConVar("tif_fall_damage", "1", FCVAR_ARCHIVE, "Soldiers land hard, stumble and take damage from falls (1/0)")
local cvMult = CreateConVar("tif_fall_damage_mult", "1", FCVAR_ARCHIVE, "Multiplier on soldiers' fall damage")

F.HARD = 120
F.STUMBLE = 250
F.HEAVY = 450
F.LETHAL = 700
F.STUMBLE_DMG = { 10, 40 }
F.HEAVY_DMG = { 40, 90 }
F.LETHAL_DMG = 1000
F.MOVING = 60
F.NO_FIRE = 1.0
F.DIRS = { [0] = "8", [45] = "7", [90] = "4", [135] = "1", [180] = "2", [-45] = "9", [-90] = "6", [-135] = "3" }

function F.Enabled()
	return cvOn:GetBool()
end

function F.Tier(h)
	if h < F.HARD then return nil end
	if h < F.STUMBLE then return "hard" end
	if h < F.HEAVY then return "stumble" end
	if h < F.LETHAL then return "heavy" end

	return "lethal"
end

local function lerp_range(r, h, lo, hi)
	local k = math.Clamp((h - lo) / math.max(1, hi - lo), 0, 1)
	return r[1] + (r[2] - r[1]) * k
end

function F.Damage(h)
	local tier = F.Tier(h)
	local d = 0

	if tier == "stumble" then
		d = lerp_range(F.STUMBLE_DMG, h, F.STUMBLE, F.HEAVY)
	elseif tier == "heavy" then
		d = lerp_range(F.HEAVY_DMG, h, F.HEAVY, F.LETHAL)
	elseif tier == "lethal" then
		return F.LETHAL_DMG
	end

	return math.floor(d * cvMult:GetFloat() + 0.5)
end

function F.Skip(npc)
	return npc.tifDead or npc.tifDying or npc.tifTrav or npc.tifVeh or npc.tifBoard or npc.tifLeaving or npc.tifHeli
		or npc.tifKnock or npc.tifDowned or npc.tifSurrendered or npc.tifProne
end

function F.DirOf(npc, vel)
	local rel = math.NormalizeAngle(vel:Angle().y - npc:GetAngles().y)
	local snap = math.Round(rel / 45) * 45

	if snap <= -180 then
		snap = 180
	end

	return F.DIRS[snap] or "8"
end

function F.Gait(speed)
	return speed > 230 and "sprint" or (speed > 160 and "run" or "jog")
end

function F.Clip(npc, tier, vel)
	local speed = vel:Length2D()
	local moving = speed > F.MOVING
	local has = function(n) return TIF.GTG.Clip(n, npc.tifHostId) ~= nil end
	local pick

	if tier == "hard" then
		pick = moving and ("mwfl_land_" .. F.DirOf(npc, vel)) or "mwfl_land"
		if not has(pick) then
			pick = "mwfl_land"
		end
	elseif moving then
		pick = "mwfl_stumble_" .. F.Gait(speed) .. math.random(1, 2)
	else
		local d = speed > 10 and F.DirOf(npc, vel) or "8"
		d = (d == "2" or d == "4" or d == "6") and d or "8"
		pick = "mwfl_stumble" .. math.random(1, 2) .. "_" .. d
	end

	return has(pick) and pick or nil, moving
end

function F.Leave(npc)
	if not F.Enabled() or F.Skip(npc) then
		npc.tifAirFrom = nil
		return
	end

	npc.tifAirFrom = npc:GetPos().z
	npc.tifAirAt = CurTime()
end

function F.Land(npc)
	local from = npc.tifAirFrom
	npc.tifAirFrom = nil
	if not from or not F.Enabled() or F.Skip(npc) then return nil end

	local h = from - npc:GetPos().z
	local tier = F.Tier(h)
	if not tier then return nil end

	local now = CurTime()
	local vel = npc.loco:GetVelocity()
	local dmgAmt = F.Damage(h)

	if dmgAmt > 0 then
		local dmg = DamageInfo()
		dmg:SetDamage(dmgAmt)
		dmg:SetDamageType(DMG_FALL)
		dmg:SetAttacker(game.GetWorld())
		dmg:SetInflictor(game.GetWorld())
		dmg:SetDamagePosition(npc:GetPos())
		dmg:SetDamageForce(Vector(0, 0, -dmgAmt * 30))
		npc:TakeDamageInfo(dmg)
	end

	if tier == "lethal" or npc.tifDead or npc.tifDying or npc.tifDowned then
		return tier
	end

	local name, moving = F.Clip(npc, tier, vel)
	if name and TIF.Action then
		local d = TIF.Action.Play(npc, name, { root = true, clear = true })

		if d and tier ~= "hard" then
			npc.tifPainUntil = now + math.max(F.NO_FIRE, moving and d * 0.4 or d * 0.8)
			npc.tifFire.want = false
		end
	end

	npc.tifAction = "landed (" .. tier .. ")"

	if TIF.Event and tier ~= "hard" then
		TIF.Event("fall", "#", npc:EntIndex(), " fell ", math.floor(h), " u: ", tier, ", ", dmgAmt, " damage", name and (", " .. name) or "")
	end

	return tier
end
