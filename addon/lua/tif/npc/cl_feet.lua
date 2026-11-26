local TIF = TIF
TIF.Feet = TIF.Feet or {}
local Feet = TIF.Feet
local Body = TIF.Body

local cvIK = CreateClientConVar("tif_foot_ik", "1", true, false, "Soldiers' feet stand on the real ground (slopes, steps, kerbs)", 0, 1)
local cvRange = CreateClientConVar("tif_foot_ik_range", "1200", true, false, "No foot IK on soldiers further than this", 100, 6000)
local cvMax = CreateClientConVar("tif_foot_ik_max", "8", true, false, "At most this many soldiers get foot IK per frame", 0, 64)
local cvLean = CreateClientConVar("tif_turn_lean", "1", true, false, "Running soldiers lean into turns", 0, 1)

Feet.UP = Vector(0, 0, 1)
Feet.SPEED_FULL, Feet.SPEED_OFF = 60, 170
Feet.OFF_MAX, Feet.DROP_MAX = 18, 16
Feet.LEAN_MAX, Feet.LEAN_K, Feet.LEAN_SPEED = 9, 0.035, 120
Feet.ACTS = { mwt_ = true, mwc_ = true, mwk_ = true }

local lastFrame, frameUsed = -1, 0

local legRigCache = {}
local function get_leg_rig(ent)
	local model = ent:GetModel()
	local rig = legRigCache[model]
	if rig ~= nil then return rig or nil end
	rig = false
	local pelvis = ent:LookupBone("ValveBiped.Bip01_Pelvis")
	if pelvis then
		rig = { pelvis = pelvis, sub = {}, sides = {} }
		for _, sideName in ipairs({ "L", "R" }) do
			local prefix = "ValveBiped.Bip01_" .. sideName .. "_"
			local thigh = ent:LookupBone(prefix .. "Thigh")
			local calf = ent:LookupBone(prefix .. "Calf")
			local foot = ent:LookupBone(prefix .. "Foot")
			if not (thigh and calf and foot) then
				rig = false
				break
			end
			rig.sides[#rig.sides + 1] = { u = thigh, f = calf, h = foot, gov = {} }
		end
		if rig then
			for bone = 0, ent:GetBoneCount() - 1 do
				local parent, depth, underPelvis = bone, 0, false
				while parent and parent >= 0 and depth < 64 do
					if parent == pelvis then
						underPelvis = true
						break
					end
					parent = ent:GetBoneParent(parent)
					depth = depth + 1
				end
				if underPelvis then
					rig.sub[#rig.sub + 1] = bone
				end
				for _, leg in ipairs(rig.sides) do
					if bone ~= leg.u and bone ~= leg.f and bone ~= leg.h then
						local cur, steps = ent:GetBoneParent(bone), 0
						while cur and cur >= 0 and steps < 64 do
							if cur == leg.h then
								leg.gov[bone] = "h"
								break
							end
							if cur == leg.f then
								leg.gov[bone] = "f"
								break
							end
							if cur == leg.u then
								leg.gov[bone] = "u"
								break
							end
							cur = ent:GetBoneParent(cur)
							steps = steps + 1
						end
					end
				end
			end
		end
	end

	legRigCache[model] = rig
	return rig or nil
end

local function is_action_allowed(actName)
	if not actName or actName == "" then return true end
	return Feet.ACTS[string.sub(actName, 1, 4)] == true
end

local traceStart, traceEnd, traceOut = Vector(), Vector(), {}
local traceInput = { start = traceStart, endpos = traceEnd, mask = MASK_PLAYERSOLID_BRUSHONLY, output = traceOut }
local function sample_ground(ent, footPos, baseZ)
	traceStart.x, traceStart.y, traceStart.z = footPos.x, footPos.y, baseZ + 22
	traceEnd.x, traceEnd.y, traceEnd.z = footPos.x, footPos.y, baseZ - 26
	traceInput.filter = ent
	local tr = util.TraceLine(traceInput)
	if not tr.Hit or tr.StartSolid or tr.HitNormal.z < 0.5 then return 0 end
	return math.Clamp(tr.HitPos.z - baseZ, -Feet.OFF_MAX, Feet.OFF_MAX)
end

local BONE_MAT = Matrix()
local CopyBone = TIF.CopyBone or function(ent, bone) return bone and ent:GetBoneMatrix(bone) end

local function build_body_matrix(ent, rig, drop, leanAngle)
	if leanAngle ~= 0 then
		local pelvisMat = CopyBone(ent, rig.pelvis, BONE_MAT)
		if not pelvisMat then return nil end
		local axis = ent:GetForward()
		local pivot = pelvisMat:GetTranslation() - Feet.UP * 30
		local rad = math.rad(leanAngle)
		local cosA, sinA = math.cos(rad), math.sin(rad)
		local x, y, z = axis.x, axis.y, axis.z
		local t = 1 - cosA
		local rotMat = Matrix({
			{ t * x * x + cosA, t * x * y - sinA * z, t * x * z + sinA * y, 0 },
			{ t * x * y + sinA * z, t * y * y + cosA, t * y * z - sinA * x, 0 },
			{ t * x * z - sinA * y, t * y * z + sinA * x, t * z * z + cosA, 0 },
			{ 0, 0, 0, 1 } })
		local toPivot, fromPivot = Matrix(), Matrix()
		toPivot:SetTranslation(pivot + Feet.UP * drop)
		fromPivot:SetTranslation(-pivot)
		return toPivot * rotMat * fromPivot
	end

	local mat = Matrix()
	mat:SetTranslation(Feet.UP * drop)
	return mat
end

local function on_build_bones(ent)
	local state = Body.State and Body.State(ent)
	if not state or not state.feetOn or state.writeFrame ~= FrameNumber() then
		return
	end

	local footWeight, leanWeight = state.footW or 0, state.leanW or 0
	local rig = get_leg_rig(ent)
	if not rig then return end
	local startTime = SysTime()
	local drop = 0
	if footWeight > 0.01 and state.footOff then
		drop = math.Clamp(math.min(state.footOff[1], state.footOff[2], 0), -Feet.DROP_MAX, 0) * footWeight
	end

	if drop > -0.05 then
		drop = 0
	end
	if math.abs(leanWeight) < 0.05 then
		leanWeight = 0
	end

	if drop ~= 0 or leanWeight ~= 0 then
		local bodyMat = build_body_matrix(ent, rig, drop, leanWeight)
		if bodyMat then
			local subBones = rig.sub
			for i = 1, #subBones do
				local bone = subBones[i]
				local mat = CopyBone(ent, bone, BONE_MAT)
				if mat then
					ent:SetBoneMatrix(bone, bodyMat * mat)
				end
			end
		end
	end

	if footWeight > 0.01 and state.footOff then
		local solveTwoBone = TIF.GunHold and TIF.GunHold.SolveTwoBone
		if solveTwoBone then
			local sides = rig.sides
			for i = 1, #sides do
				local leg = sides[i]
				local offset = state.footOff[i] * footWeight
				if math.abs(offset - drop) > 0.05 then
					local footMat = CopyBone(ent, leg.h, BONE_MAT)
					if footMat then
						solveTwoBone(ent, leg, footMat:GetTranslation() + Feet.UP * (offset - drop))
					end
				end
			end
		end
	end

	local prof = TIF.Prof
	if prof then
		prof.Count("cl_feet_us", (SysTime() - startTime) * 1e6)
		prof.Count("cl_feet_n", 1)
	end
end

function Feet.Prepare(ent, state, now, dt)
	if not ent.tifFeetCb then
		ent.tifFeetCb = ent:AddCallback("BuildBonePositions", on_build_bones)
	end
	local frame = FrameNumber()
	if frame ~= lastFrame then
		lastFrame, frameUsed = frame, 0
	end

	local speed = state.speed2d or 0
	local range = cvRange:GetFloat()
	local near = ent:GetPos():DistToSqr(EyePos()) < range * range
	local allowed = near and state.vb and not state.vbProne and is_action_allowed(state.actName) and frameUsed < cvMax:GetInt()
	local wantFoot = (allowed and cvIK:GetBool()) and math.Clamp(1 - (speed - Feet.SPEED_FULL) / (Feet.SPEED_OFF - Feet.SPEED_FULL), 0, 1) or 0
	state.footW = math.Approach(state.footW or 0, wantFoot, dt * 6)
	local yaw = ent:GetAngles().y
	local yawRate = state.leanYaw and math.AngleDifference(yaw, state.leanYaw) / math.max(dt, 0.001) or 0
	state.leanYaw = yaw
	local targetLean = 0
	if allowed and cvLean:GetBool() and speed > Feet.LEAN_SPEED then
		targetLean = math.Clamp(-yawRate * speed * Feet.LEAN_K / 100, -Feet.LEAN_MAX, Feet.LEAN_MAX)
	end

	state.leanW = Lerp(math.min(1, dt * 5), state.leanW or 0, targetLean)
	state.feetOn = state.footW > 0.01 or math.abs(state.leanW) >= 0.05
	if not state.feetOn then return end
	frameUsed = frameUsed + 1
	if state.footW > 0.01 then
		state.footOff = state.footOff or { 0, 0 }
		state.footTick = (state.footTick or 0) + 1
		if state.footTick % 2 == 0 then
			local rig = get_leg_rig(ent)
			if rig then
				local baseZ = ent:GetPos().z
				state.footTgt = state.footTgt or { 0, 0 }
				local sides = rig.sides
				for i = 1, #sides do
					local footMat = CopyBone(ent, sides[i].h, BONE_MAT)
					if footMat then
						state.footTgt[i] = sample_ground(ent, footMat:GetTranslation(), baseZ)
					end
				end
			end
		end
		if state.footTgt then
			local blend = math.min(1, dt * 12)
			state.footOff[1] = Lerp(blend, state.footOff[1], state.footTgt[1])
			state.footOff[2] = Lerp(blend, state.footOff[2], state.footTgt[2])
		end
	end
end
