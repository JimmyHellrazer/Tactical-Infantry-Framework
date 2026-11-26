local TIF = TIF
TIF.Feet = TIF.Feet or {}
local F = TIF.Feet
local Bd = TIF.Body

local cvIK = CreateClientConVar("tif_foot_ik", "1", true, false, "Soldiers' feet stand on the real ground (slopes, steps, kerbs)", 0, 1)
local cvRange = CreateClientConVar("tif_foot_ik_range", "1200", true, false, "No foot IK on soldiers further than this", 100, 6000)
local cvMax = CreateClientConVar("tif_foot_ik_max", "8", true, false, "At most this many soldiers get foot IK per frame", 0, 64)
local cvLean = CreateClientConVar("tif_turn_lean", "1", true, false, "Running soldiers lean into turns", 0, 1)

F.UP = Vector(0, 0, 1)
F.SPEED_FULL, F.SPEED_OFF = 60, 170
F.OFF_MAX, F.DROP_MAX = 18, 16
F.LEAN_MAX, F.LEAN_K, F.LEAN_SPEED = 9, 0.035, 120
F.ACTS = { mwt_ = true, mwc_ = true, mwk_ = true }

local frameNo, used = -1, 0

local legsOf = {}
local function legs(ent)
	local model = ent:GetModel()
	local L = legsOf[model]
	if L ~= nil then return L or nil end
	L = false
	local pel = ent:LookupBone("ValveBiped.Bip01_Pelvis")
	if pel then
		L = { pelvis = pel, sub = {}, sides = {} }
		for _, s in ipairs({ "L", "R" }) do
			local pre = "ValveBiped.Bip01_" .. s .. "_"
			local u, f, h = ent:LookupBone(pre .. "Thigh"), ent:LookupBone(pre .. "Calf"), ent:LookupBone(pre .. "Foot")
			if not (u and f and h) then L = false break end
			L.sides[#L.sides + 1] = { u = u, f = f, h = h, gov = {} }
		end
		if L then
			for b = 0, ent:GetBoneCount() - 1 do
				local p, guard, under = b, 0, false
				while p and p >= 0 and guard < 64 do
					if p == pel then under = true break end
					p = ent:GetBoneParent(p)
					guard = guard + 1
				end
				if under then L.sub[#L.sub + 1] = b end
				for _, a in ipairs(L.sides) do
					if b ~= a.u and b ~= a.f and b ~= a.h then
						local q, g2 = ent:GetBoneParent(b), 0
						while q and q >= 0 and g2 < 64 do
							if q == a.h then a.gov[b] = "h" break end
							if q == a.f then a.gov[b] = "f" break end
							if q == a.u then a.gov[b] = "u" break end
							q = ent:GetBoneParent(q)
							g2 = g2 + 1
						end
					end
				end
			end
		end
	end
	legsOf[model] = L
	return L or nil
end

local function act_ok(name)
	if not name or name == "" then return true end
	return F.ACTS[string.sub(name, 1, 4)] == true
end

local traceIn = { mask = MASK_PLAYERSOLID_BRUSHONLY }
local function ground(ent, p, base)
	traceIn.start = Vector(p.x, p.y, base + 22)
	traceIn.endpos = Vector(p.x, p.y, base - 26)
	traceIn.filter = ent
	local tr = util.TraceLine(traceIn)
	if not tr.Hit or tr.StartSolid or tr.HitNormal.z < 0.5 then return 0 end
	return math.Clamp(tr.HitPos.z - base, -F.OFF_MAX, F.OFF_MAX)
end

local function body_matrix(ent, L, drop, lw)
	local M
	if lw ~= 0 then
		local pm = ent:GetBoneMatrix(L.pelvis)
		if not pm then return nil end
		local axis = ent:GetForward()
		local piv = pm:GetTranslation() - F.UP * 30
		local c, s = math.cos(math.rad(lw)), math.sin(math.rad(lw))
		local x, y, z = axis.x, axis.y, axis.z
		local t = 1 - c
		local rot = Matrix({
			{ t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0 },
			{ t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0 },
			{ t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0 },
			{ 0, 0, 0, 1 } })
		local T1, T2 = Matrix(), Matrix()
		T1:SetTranslation(piv + F.UP * drop)
		T2:SetTranslation(-piv)
		M = T1 * rot * T2
	else
		M = Matrix()
		M:SetTranslation(F.UP * drop)
	end
	return M
end

local function cb(ent)
	local st = Bd.State and Bd.State(ent)
	if not st or not st.feetOn or st.writeFrame ~= FrameNumber() then return end
	local fw, lw = st.footW or 0, st.leanW or 0
	local L = legs(ent)
	if not L then return end
	local t0 = SysTime()
	local drop = 0
	if fw > 0.01 and st.footOff then
		drop = math.Clamp(math.min(st.footOff[1], st.footOff[2], 0), -F.DROP_MAX, 0) * fw
	end
	if drop > -0.05 then drop = 0 end
	if math.abs(lw) < 0.05 then lw = 0 end
	if drop ~= 0 or lw ~= 0 then
		local M = body_matrix(ent, L, drop, lw)
		if M then
			for _, b in ipairs(L.sub) do
				local m = ent:GetBoneMatrix(b)
				if m then ent:SetBoneMatrix(b, M * m) end
			end
		end
	end
	if fw > 0.01 and st.footOff then
		local solve = TIF.GunHold and TIF.GunHold.SolveTwoBone
		if solve then
			for i, a in ipairs(L.sides) do
				local off = st.footOff[i] * fw
				if math.abs(off - drop) > 0.05 then
					local m = ent:GetBoneMatrix(a.h)
					if m then solve(ent, a, m:GetTranslation() + F.UP * (off - drop)) end
				end
			end
		end
	end
	local Prof = TIF.Prof
	if Prof then
		Prof.Count("cl_feet_us", (SysTime() - t0) * 1e6)
		Prof.Count("cl_feet_n", 1)
	end
end

function F.Prepare(ent, st, now, dt)
	if not ent.tifFeetCb then ent.tifFeetCb = ent:AddCallback("BuildBonePositions", cb) end
	local fn = FrameNumber()
	if fn ~= frameNo then frameNo, used = fn, 0 end
	local speed = st.speed2d or 0
	local near = ent:GetPos():DistToSqr(EyePos()) < cvRange:GetFloat() ^ 2
	local able = near and st.vb and not st.vbProne and act_ok(st.actName) and used < cvMax:GetInt()
	local want = (able and cvIK:GetBool()) and math.Clamp(1 - (speed - F.SPEED_FULL) / (F.SPEED_OFF - F.SPEED_FULL), 0, 1) or 0
	st.footW = math.Approach(st.footW or 0, want, dt * 6)
	local yaw = ent:GetAngles().y
	local rate = st.leanYaw and math.AngleDifference(yaw, st.leanYaw) / math.max(dt, 0.001) or 0
	st.leanYaw = yaw
	local lean = 0
	if able and cvLean:GetBool() and speed > F.LEAN_SPEED then
		lean = math.Clamp(-rate * speed * F.LEAN_K / 100, -F.LEAN_MAX, F.LEAN_MAX)
	end
	st.leanW = Lerp(math.min(1, dt * 5), st.leanW or 0, lean)
	st.feetOn = st.footW > 0.01 or math.abs(st.leanW) >= 0.05
	if not st.feetOn then return end
	used = used + 1
	if st.footW > 0.01 then
		st.footOff = st.footOff or { 0, 0 }
		st.footTick = (st.footTick or 0) + 1
		if st.footTick % 2 == 0 then
			local L = legs(ent)
			if L then
				local base = ent:GetPos().z
				st.footTgt = st.footTgt or { 0, 0 }
				for i, a in ipairs(L.sides) do
					local m = ent:GetBoneMatrix(a.h)
					if m then st.footTgt[i] = ground(ent, m:GetTranslation(), base) end
				end
			end
		end
		if st.footTgt then
			local k = math.min(1, dt * 12)
			st.footOff[1] = Lerp(k, st.footOff[1], st.footTgt[1])
			st.footOff[2] = Lerp(k, st.footOff[2], st.footTgt[2])
		end
	end
end
