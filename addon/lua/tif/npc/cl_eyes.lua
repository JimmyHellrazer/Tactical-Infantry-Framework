local TIF = TIF
TIF.Eyes = TIF.Eyes or {}
local Eyes = TIF.Eyes

local cvEyes = GetConVar("tif_eyes") or CreateClientConVar("tif_eyes", "1", true, false, "Soldiers' eyes look at what they're aiming at or facing")

Eyes.RANGE = 900
Eyes.CONE = 40
Eyes.AHEAD = 200
Eyes.HEAD = "ValveBiped.Bip01_Head1"

local eyeOffsets = {}
local coneRad = math.rad(Eyes.CONE)
local cosCone, sinCone = math.cos(coneRad), math.sin(coneRad)
local HEAD_MAT = Matrix and Matrix()
local CopyBone = TIF.CopyBone or function(ent, bone)
	return bone and ent:GetBoneMatrix(bone)
end

local function get_eye_offset(follower, ent, headBone)
	local model = follower:GetModel() or ""
	local offset = eyeOffsets[model]
	if offset ~= nil then return offset or nil end

	offset = false
	local attIdx = follower:LookupAttachment("eyes")

	if attIdx and attIdx > 0 then
		local att = follower:GetAttachment(attIdx)
		local headMat = CopyBone(ent, headBone, HEAD_MAT)

		if att and headMat then
			local localPos, localAng = WorldToLocal(att.Pos, att.Ang, headMat:GetTranslation(), headMat:GetAngles())
			offset = { pos = localPos, ang = localAng }
		end
	end

	eyeOffsets[model] = offset
	return offset or nil
end

local function clamp_to_cone(forward, targetDir)
	local dot = targetDir:Dot(forward)
	if dot >= cosCone then return targetDir end

	local side = targetDir - forward * dot
	if side:LengthSqr() < 1e-6 then return forward end

	side:Normalize()
	return forward * cosCone + side * sinCone
end

function Eyes.Update(ent, state)
	if not cvEyes:GetBool() then return end

	local follower = state.follower
	if not IsValid(follower) then return end
	if ent:GetPos():DistToSqr(EyePos()) > Eyes.RANGE * Eyes.RANGE then return end

	local headBone = state.eyeHead
	if headBone == nil then
		headBone = ent:LookupBone(Eyes.HEAD) or false
		state.eyeHead = headBone
	end

	if not headBone then return end

	local offset = get_eye_offset(follower, ent, headBone)
	if not offset then return end

	local headMat = CopyBone(ent, headBone, HEAD_MAT)
	if not headMat then return end

	local eyePos, eyeAng = LocalToWorld(offset.pos, offset.ang, headMat:GetTranslation(), headMat:GetAngles())
	local forward = eyeAng:Forward()
	local lookDir = forward
	local lookTarget = ent:GetNW2Vector("tif_look", vector_origin)

	if lookTarget ~= vector_origin then
		local toTarget = lookTarget - eyePos
		if toTarget:LengthSqr() > 16 then
			toTarget:Normalize()
			lookDir = clamp_to_cone(forward, toTarget)
		end
	end

	follower:SetEyeTarget((WorldToLocal(eyePos + lookDir * Eyes.AHEAD, angle_zero, eyePos, eyeAng)))
	follower.tifEyesByBody = true
end
