local TIF = TIF
TIF.Props = TIF.Props or {}
local Props = TIF.Props
Props.BLEND = 0.25
Props.CARRY = { tif_sledge = "mwq_br_sledge" }

local UNTURN_MAT = Matrix({ { 0, 1, 0, 0 }, { -1, 0, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } })
local SCRATCH_MAT = Matrix()
local function unturn(ang)
	SCRATCH_MAT:SetAngles(ang)
	return (SCRATCH_MAT * UNTURN_MAT):GetAngles()
end
Props.Unturn = unturn

local function ensure_prop_entity(state, model)
	local prop = state.prop
	if IsValid(prop) and prop:GetModel() == model then return prop end
	if IsValid(prop) then prop:Remove() end
	prop = ClientsideModel(model, RENDERGROUP_OPAQUE)
	if not IsValid(prop) then return nil end
	prop:SetNoDraw(true)
	state.prop = prop
	return prop
end

function Props.Remove(state)
	if IsValid(state.prop) then state.prop:Remove() end
	state.prop, state.propFrom, state.propKey = nil, nil, nil
end

local CopyBone = TIF.CopyBone or function(ent, bone) return bone and ent:GetBoneMatrix(bone) end
local BONE_MAT = Matrix()
local propBoneCache = {}
local function bone_world_pose(ent, boneName)
	local model = ent.GetModel and ent:GetModel() or ""
	local cache = propBoneCache[model]
	if not cache then cache = {} propBoneCache[model] = cache end
	local bone = cache[boneName]
	if bone == nil then
		bone = ent:LookupBone(boneName) or false
		cache[boneName] = bone
	end
	local mat = bone and CopyBone(ent, bone, BONE_MAT)
	if not mat then return nil end
	return mat:GetTranslation(), mat:GetAngles()
end

local VEC_A, VEC_B = Vector(), Vector()
local ANG_A, ANG_B = Angle(), Angle()

local function clip_pose(ent, def, cycle)
	local frames = def.frames
	local count = #frames
	local frameFloat = math.Clamp(cycle, 0, 1) * (count - 1) + 1
	local idx = math.min(count, math.floor(frameFloat))
	local frameA, frameB = frames[idx], frames[math.min(count, idx + 1)]
	local frac = frameFloat - idx
	if frameA[1] ~= frameB[1] then
		if frac >= 0.5 then frameA = frameB end
		frac = 0
	end
	local bonePos, boneAng = bone_world_pose(ent, def.bones[frameA[1]])
	if not bonePos then return nil end
	VEC_A.x, VEC_A.y, VEC_A.z = frameA[2], frameA[3], frameA[4]
	VEC_B.x, VEC_B.y, VEC_B.z = frameB[2], frameB[3], frameB[4]
	ANG_A.p, ANG_A.y, ANG_A.r = frameA[5], frameA[6], frameA[7]
	ANG_B.p, ANG_B.y, ANG_B.r = frameB[5], frameB[6], frameB[7]
	local localPos = LerpVector(frac, VEC_A, VEC_B)
	local localAng = LerpAngle(frac, ANG_A, ANG_B)
	return LocalToWorld(localPos, localAng, bonePos, boneAng)
end

local function stow_pose(ent, def)
	local stow = def.stow
	local bonePos, boneAng = bone_world_pose(ent, def.bones[2])
	if not bonePos then return nil end
	VEC_A.x, VEC_A.y, VEC_A.z = stow[1], stow[2], stow[3]
	ANG_A.p, ANG_A.y, ANG_A.r = stow[4], stow[5], stow[6]
	return LocalToWorld(VEC_A, ANG_A, bonePos, boneAng)
end

function Props.Update(ent, state, now)
	local propClips = TIF.PropClips
	if not propClips then return end

	local def, key, pos, ang
	local activeClip = state.actClipCur
	if activeClip and state.actU then
		for clipName, clipDef in pairs(propClips) do
			local resolved = TIF.GTG and TIF.GTG.Clip(clipName, state.hostId)
			if resolved and resolved == activeClip then def, key = clipDef, "clip:" .. clipName break end
		end
	end
	if not def then
		for flag, clipName in pairs(Props.CARRY) do
			if ent:GetNW2Bool(flag, false) and propClips[clipName] then def, key = propClips[clipName], "stow:" .. clipName break end
		end
	end

	if not def or ent:IsDormant() or state.hideGun then
		if IsValid(state.prop) then state.prop:SetNoDraw(true) end
		state.propKey = nil
		return
	end
	if string.sub(key, 1, 5) == "clip:" then
		pos, ang = clip_pose(ent, def, state.actU)
	else
		pos, ang = stow_pose(ent, def)
	end
	if not pos then return end
	local prop = ensure_prop_entity(state, def.model)
	if not prop then return end

	if state.propKey ~= key then
		if state.propKey and state.propPos then
			state.propFrom = { pos = state.propPos, ang = state.propAng, t = now }
		else
			state.propFrom = nil
		end
		state.propKey = key
	end
	local blendFrom = state.propFrom
	if blendFrom then
		local frac = (now - blendFrom.t) / Props.BLEND
		if frac >= 1 then
			state.propFrom = nil
		else
			frac = frac * frac * (3 - 2 * frac)
			pos, ang = LerpVector(frac, blendFrom.pos, pos), LerpAngle(frac, blendFrom.ang, ang)
		end
	end
	state.propPos, state.propAng = pos, ang
	prop:SetPos(pos)
	prop:SetAngles(unturn(ang))
	prop:SetNoDraw(false)
end
