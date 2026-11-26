TIF.GunMag = TIF.GunMag or {}
local GunMag = TIF.GunMag

local cvDrop = CreateClientConVar("tif_mag_drop", "1", true, false, "Dropped magazines fall from reloading soldiers (0 = off)")
local L_HAND = "ValveBiped.Bip01_L_Hand"
local MAG_BONE, ROOT_BONE = "tif_mag", "tif_gun"

GunMag.PALM = Vector(3.4, 1.2, 0)
local MAX_DROPS, DROP_LIFE, DROP_RANGE = 8, 10, 1500
local TINY_SCALE = Vector(0.001, 0.001, 0.001)

local clipEventCache = {}
local function get_clip_events(clip)
	local cached = clipEventCache[clip]
	if cached ~= nil then return cached or nil end
	local dropTime, attachTime, detachTime
	for _, tag in ipairs(clip.tags or {}) do
		local eventName = tag[1] == "MoveEvent" and istable(tag[4]) and tag[4].MoveEvent
		if eventName == "drop_clip" then dropTime = dropTime or tag[2]
		elseif eventName == "attach_clip_left" then attachTime = attachTime or tag[2]
		elseif eventName == "detach_clip_left" then detachTime = detachTime or tag[2]
		elseif isstring(eventName) and string.find(eventName, "_lm_reload_npc_out", 1, true) then attachTime = attachTime or tag[2]
		elseif isstring(eventName) and string.find(eventName, "_lm_reload_npc_in", 1, true) then detachTime = detachTime or tag[2] end
	end
	cached = (attachTime and detachTime and detachTime > attachTime) and { drop = dropTime, att = attachTime, det = detachTime } or false
	clipEventCache[clip] = cached
	return cached or nil
end

local magBoneCache = {}
local function get_mag_bones(gun)
	local model = gun:GetModel()
	local bones = magBoneCache[model]
	if bones == nil then
		local magBone = gun:LookupBone(MAG_BONE)
		bones = magBone and { mag = magBone, root = gun:LookupBone(ROOT_BONE) or 0 } or false
		magBoneCache[model] = bones
	end
	return bones or nil
end

local CopyBone = TIF.CopyBone or function(ent, bone) return bone and ent:GetBoneMatrix(bone) end
local ROOT_MAT, MAG_MAT, HAND_MAT, DROP_MAT = Matrix(), Matrix(), Matrix(), Matrix()
local leftHandCache = {}

local restRelCache = {}
local function get_mag_rest_rel(ent, bones)
	local model = ent:GetModel()
	local rel = restRelCache[model]
	if rel then return rel end
	local rootMat = CopyBone(ent, bones.root, ROOT_MAT)
	local magMat = CopyBone(ent, bones.mag, MAG_MAT)
	if not (rootMat and magMat) then return nil end
	rel = rootMat:GetInverseTR() * magMat
	restRelCache[model] = rel
	return rel
end

local function on_build_gun(ent)
	local mode = ent.tifMagMode
	if not mode then return end
	local bones = get_mag_bones(ent)
	if not bones then return end
	local magMat = CopyBone(ent, bones.mag, MAG_MAT)
	if not magMat then return end
	if mode == "hide" then
		magMat:Scale(TINY_SCALE)
		ent:SetBoneMatrix(bones.mag, magMat)
	elseif mode == "hand" and ent.tifMagPalm then
		local rel = get_mag_rest_rel(ent, bones)
		local rootMat = CopyBone(ent, bones.root, ROOT_MAT)
		if not (rel and rootMat) then return end
		local worldMat = rootMat * rel
		worldMat:SetTranslation(ent.tifMagPalm)
		ent:SetBoneMatrix(bones.mag, worldMat)
	end
end

local droppedMags = {}
local function on_build_drop(ent)
	local bones = get_mag_bones(ent)
	local drop = ent.tifDrop
	if not (bones and drop) then return end
	local rootMat = CopyBone(ent, bones.root, ROOT_MAT)
	if rootMat then
		rootMat:Scale(TINY_SCALE)
		ent:SetBoneMatrix(bones.root, rootMat)
	end
	DROP_MAT:Identity()
	DROP_MAT:SetTranslation(drop.pos)
	DROP_MAT:SetAngles(drop.ang)
	ent:SetBoneMatrix(bones.mag, DROP_MAT)
end

local function spawn_drop(gun, bones)
	if not cvDrop:GetBool() then return end
	local magMat = CopyBone(gun, bones.mag, MAG_MAT)
	if not magMat then return end
	local pos = magMat:GetTranslation()
	if pos:DistToSqr(EyePos()) > DROP_RANGE * DROP_RANGE then return end
	if #droppedMags >= MAX_DROPS then
		local oldest = table.remove(droppedMags, 1)
		if IsValid(oldest.ent) then oldest.ent:Remove() end
	end
	local ent = ClientsideModel(gun:GetModel(), RENDERGROUP_OPAQUE)
	if not IsValid(ent) then return end
	ent:SetPos(pos)
	ent:SetSkin(gun:GetSkin())
	ent.tifDrop = {
		pos = pos,
		ang = magMat:GetAngles(),
		vel = -gun:GetUp() * 40 + VectorRand() * 15 + gun:GetForward() * -10,
		spin = Angle(math.Rand(-300, 300), math.Rand(-200, 200), math.Rand(-300, 300)),
		t = CurTime(),
		landed = false,
	}
	ent:AddCallback("BuildBonePositions", on_build_drop)
	droppedMags[#droppedMags + 1] = { ent = ent }
end

local traceOut = {}
local traceInput = { mask = MASK_SOLID_BRUSHONLY, output = traceOut }
local function step_drops(dt, now)
	for i = #droppedMags, 1, -1 do
		local ent = droppedMags[i].ent
		local drop = IsValid(ent) and ent.tifDrop
		if not drop or now - drop.t > DROP_LIFE then
			if IsValid(ent) then ent:Remove() end
			table.remove(droppedMags, i)
		elseif not drop.landed then
			drop.vel.z = drop.vel.z - 600 * dt
			local nextPos = drop.pos + drop.vel * dt
			traceInput.start, traceInput.endpos = drop.pos, nextPos
			local tr = util.TraceLine(traceInput)
			if tr.Hit then
				drop.pos = tr.HitPos + tr.HitNormal * 1.2
				drop.ang.p, drop.ang.r = 0, 90
				drop.landed = true
			else
				drop.pos = nextPos
				drop.ang.p = drop.ang.p + drop.spin.p * dt
				drop.ang.y = drop.ang.y + drop.spin.y * dt
				drop.ang.r = drop.ang.r + drop.spin.r * dt
			end
			ent:SetPos(drop.pos)
			ent:InvalidateBoneCache()
		end
	end
end

hook.Add("Think", "tif_gunmag_drops", function()
	if #droppedMags > 0 then step_drops(FrameTime(), CurTime()) end
end)

function GunMag.Update(ent, state)
	local gun = state.gun
	if not IsValid(gun) then return end
	local bones = get_mag_bones(gun)
	if not bones then return end
	if not gun.tifMagHooked then
		gun.tifMagHooked = true
		gun:AddCallback("BuildBonePositions", on_build_gun)
	end
	local clip, cycle = state.magClip, state.magU
	local events = clip and cycle and get_clip_events(clip)
	local mode
	if events then
		local hideFrom = events.drop or (state.wkind == "rpg" and 0) or nil
		if cycle >= events.att and cycle < events.det then
			mode = "hand"
		elseif hideFrom and cycle >= hideFrom and cycle < events.att then
			mode = "hide"
		end
		if events.drop and cycle >= events.drop and cycle < events.att and state.magDropped ~= state.magKey then
			state.magDropped = state.magKey
			gun:SetupBones()
			spawn_drop(gun, bones)
		end
	end
	if mode == "hand" then
		local model = ent:GetModel()
		local handBone = leftHandCache[model]
		if handBone == nil then
			handBone = ent:LookupBone(L_HAND) or false
			leftHandCache[model] = handBone
		end
		local handMat = handBone and CopyBone(ent, handBone, HAND_MAT)
		if handMat then
			gun.tifMagPalm = LocalToWorld(GunMag.PALM, angle_zero, handMat:GetTranslation(), handMat:GetAngles())
		else
			mode = nil
		end
	end
	if mode ~= gun.tifMagMode then
		gun.tifMagMode = mode
		gun:InvalidateBoneCache()
	end
end

function GunMag.Clear()
	for i = 1, #droppedMags do
		local ent = droppedMags[i].ent
		if IsValid(ent) then ent:Remove() end
	end
	droppedMags = {}
end
