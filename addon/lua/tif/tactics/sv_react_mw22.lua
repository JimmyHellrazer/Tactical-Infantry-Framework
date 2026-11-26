local TIF = TIF
local Act = TIF.Action
local Move = TIF.Move
local A = TIF.Anim

TIF.React22 = TIF.React22 or {}
local R = TIF.React22

R.GRENADE_R = 300
R.DIVE_R = 140
R.SCAN_EVERY = 0.2
R.GRENADES = { npc_grenade_frag = true, grenade_ar2 = true, npc_contactgrenade = true, cw_grenade_thrown = true,
	m9k_thrown_m61 = true, tfa_mwb_frag = true, tif_grenade = true }
R.SHOCK_MIN, R.SHOCK_CHANCE = 45, 0.35
R.ASSESS_CHANCE = 0.8

local cvOn = CreateConVar("tif_react22", "1", FCVAR_ARCHIVE, "MW22 reactions: grenade dodges, pain shock, hit while unaware")

local function clip(npc, name) return npc.tifHomeHost and TIF.GTG.Clip(name, npc.tifHomeHost) or nil end

local function free(npc)
	if not cvOn:GetBool() or npc.tifDead or npc.tifDying or npc.tifVeh or npc.tifDowned or npc.tifProne
		or npc.tifSurrendered or npc.tifCov or npc.tifReact or npc.tifBoard or npc.tifLeaving then return false end
	if not (TIF.HitsMW and TIF.HitsMW.Use(npc)) then return false end
	if npc.tifHostId ~= npc.tifHomeHost then return false end
	local a = npc.tifAct

	if a and not string.find(a.name or "", "^mw[tlxsrika]_") then return false end
	return true
end
R.Free = free

local function by_travel(npc, names, ang)
	local best, be
	for _, n in ipairs(names) do
		local c = clip(npc, n)
		if c and (c.move[1] ~= 0 or c.move[2] ~= 0) then
			local e = math.abs(math.AngleDifference(math.deg(math.atan2(c.move[2], c.move[1])), ang))
			if not be or e < be then best, be = n, e end
		end
	end
	return best, be
end
R.ByTravel = by_travel

local function hold(npc, now, d, label)
	npc.tifReact = { untilT = now + d }
	npc.tifAction = label
	npc.tifFire.want = false
end

local function play(npc, name, opts)
	Move.Stop(npc)
	npc.tifActivity, npc.tifLook, npc.tifPassiveBusy = nil, nil, nil
	return Act.Play(npc, name, opts or { root = true, clear = true })
end

local JUMPS = { "mwe_jump_2", "mwe_jump_4", "mwe_jump_6", "mwe_jump_8", "mwe_dodge_4", "mwe_dodge_6" }

function R.Dodge(npc, gpos, now)
	if not free(npc) then return false end
	local away = npc:GetPos() - gpos
	away.z = 0
	local dist = away:Length()
	if dist < 1 then away = -npc:GetForward() end
	local awayYaw = away:Angle().y
	if dist < R.DIVE_R and clip(npc, "mwe_dive_8") then

		npc:SetAngles(Angle(0, awayYaw, 0))
		local d1 = play(npc, "mwe_dive_8")
		if not d1 then return false end
		npc.tifReactChain = clip(npc, "mwe_dive_up_8") and { at = now + d1, name = "mwe_dive_up_8" } or nil
		local d2 = npc.tifReactChain and clip(npc, "mwe_dive_up_8").dur or 0
		hold(npc, now, d1 + d2, "diving from a grenade")
		return true
	end
	local rel = math.AngleDifference(awayYaw, npc:GetAngles().y)
	local name = by_travel(npc, JUMPS, rel)
	if not name then return false end
	local d = play(npc, name)
	if not d then return false end
	hold(npc, now, d, "jumping away from a grenade")
	return true
end

local nextScan = 0
hook.Add("Think", "tif_react22_grenades", function()
	local now = CurTime()
	if now < nextScan or TIF.AIDisabled() then return end
	nextScan = now + R.SCAN_EVERY
	for cls in pairs(R.GRENADES) do
		for _, g in ipairs(ents.FindByClass(cls)) do

			if IsValid(g) and not g.tifDodged and g.tifDodgeable ~= false and g:GetVelocity():LengthSqr() < 250 * 250 then
				local gp = g:GetPos()
				local owner = g:GetOwner()
				local any = false
				for _, s in ipairs(TIF.Soldiers) do
					if IsValid(s) and s ~= owner and not s.tifDead and s:GetPos():DistToSqr(gp) < R.GRENADE_R * R.GRENADE_R
						and math.abs(s:GetPos().z - gp.z) < 80 then
						any = true
						if R.Dodge(s, gp, now) then TIF.Say(s, "grenade_incoming", 0.7) end
					end
				end

				if any then g.tifDodged = true end
			end
		end
	end
end)

R.VEH_SPEED, R.VEH_TIME, R.VEH_LANE = 220, 1.3, 70

local function is_vehicle(e)
	if e:IsVehicle() then return true end
	local c = e:GetClass()
	return string.find(c, "glide", 1, true) ~= nil or string.find(c, "fphysics", 1, true) ~= nil or e.IsGlideVehicle == true
end

function R.VehicleDodge(npc, veh, now)
	if not free(npc) or npc.tifVeh then return false end
	local v = veh:GetVelocity()
	v.z = 0
	local speed = v:Length()
	local dir = v / math.max(1, speed)
	local rel = npc:GetPos() - veh:GetPos()
	rel.z = 0
	local along = rel:Dot(dir)
	local lateral = rel:Dot(Vector(-dir.y, dir.x, 0))
	if along < 0 or along / speed > R.VEH_TIME or math.abs(lateral) > R.VEH_LANE then return false end

	local awayW = Vector(-dir.y, dir.x, 0) * (lateral >= 0 and 1 or -1)
	local ang = math.AngleDifference(awayW:Angle().y, npc:GetAngles().y)
	local close = along / speed < 0.6
	local names = {}
	for _, n in ipairs({ "2", "4", "6", "8" }) do
		names[#names + 1] = (close and "mwz_vdodge_short_" or "mwz_vdodge_") .. n
	end
	local name = by_travel(npc, names, ang) or by_travel(npc, { "mwz_vdodge_2", "mwz_vdodge_4", "mwz_vdodge_6", "mwz_vdodge_8" }, ang)
	if not name then return false end
	local d = play(npc, name)
	if not d then return false end
	hold(npc, now, d * 0.7, "dodging a vehicle")
	TIF.Say(npc, "swear", 0.8)
	return true
end

local nextVeh, nextList, vehList = 0, 0, {}
hook.Add("Think", "tif_react22_vehicles", function()
	local now = CurTime()
	if now < nextVeh or TIF.AIDisabled() or not cvOn:GetBool() then return end
	nextVeh = now + R.SCAN_EVERY

	if now >= nextList then
		nextList = now + 2
		vehList = {}
		for _, e in ipairs(ents.GetAll()) do if IsValid(e) and is_vehicle(e) then vehList[#vehList + 1] = e end end
	end
	for _, veh in ipairs(vehList) do
		if IsValid(veh) and is_vehicle(veh) and veh:GetVelocity():Length2DSqr() > R.VEH_SPEED * R.VEH_SPEED then
			local vp = veh:GetPos()
			for _, s in ipairs(TIF.Soldiers) do
				if IsValid(s) and not s.tifDead and not s.tifVeh and s:GetPos():DistToSqr(vp) < 600 * 600 then
					R.VehicleDodge(s, veh, now)
				end
			end
		end
	end
end)

function R.Shock(npc, dmg, now)
	if not free(npc) or dmg:GetDamage() < R.SHOCK_MIN or math.random() > R.SHOCK_CHANCE then return false end
	local st = npc:GetTIFStance() == A.STANCE_CROUCH and "crouch" or "stand"
	local d1 = play(npc, "mwe_shock_" .. st)
	if not d1 then return false end
	local rec = "mwe_shock_" .. st .. "_rec"
	npc.tifReactChain = clip(npc, rec) and { at = now + d1, name = rec } or nil
	hold(npc, now, d1 + (npc.tifReactChain and clip(npc, rec).dur or 0), "in shock")
	return true
end

function R.Assess(npc, dmg, now)
	if not free(npc) or npc.tifAware ~= TIF.AWARE.UNAWARE or math.random() > R.ASSESS_CHANCE then return false end
	local att = dmg:GetAttacker()
	local from = IsValid(att) and att:GetPos() or (npc:GetPos() - dmg:GetDamageForce())
	local want = math.AngleDifference((from - npc:GetPos()):Angle().y, npc:GetAngles().y)
	local best, be
	for _, n in ipairs({ "mwe_assess_2", "mwe_assess_4", "mwe_assess_6", "mwe_assess_8" }) do
		local c = clip(npc, n)
		if c then
			local e = math.abs(math.AngleDifference(c.move[3] or 0, want))
			if not be or e < be then best, be = n, e end
		end
	end
	local d = best and play(npc, best)
	if not d then return false end
	hold(npc, now, d * 0.85, "hit: where from?")
	return true
end

function R.Think(npc, now)
	local ch = npc.tifReactChain
	if ch and now >= ch.at then
		npc.tifReactChain = nil
		Act.Play(npc, ch.name, { root = true, clear = true })
	end
end
