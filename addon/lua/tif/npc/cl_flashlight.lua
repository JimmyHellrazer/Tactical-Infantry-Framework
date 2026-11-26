local TIF = TIF
local IsValid, Vector, Angle, Color = IsValid, Vector, Angle, Color
local CopyBone = TIF.CopyBone or function(ent, bone)
	return bone and ent:GetBoneMatrix(bone)
end

local cvMaxLights = CreateClientConVar("tif_flashlight_max", "4", true, false, "Soldier flashlights drawn as real lights (nearest first)")
local cvMaxDist = CreateClientConVar("tif_flashlight_dist", "3000", true, false, "How far soldier flashlights are drawn")

local GLOW_MAT = Material("sprites/light_glow02_add")
local LIGHT_COLOR = Color(255, 244, 225)
local GLOW_COLOR = Color(255, 244, 225, 255)
local HAND_MAT = Matrix()
local BEAM_ANG = Angle()
local leftHandCache = {}
local lightPool = {}
local litSoldiers, litEntryPool = {}, {}

local function by_dist_sqr(a, b)
	return a.distSqr < b.distSqr
end

local function get_hand_light_matrix(ent, state)
	state = state or (TIF.Body and TIF.Body.State and TIF.Body.State(ent))
	if not (state and state.handLight) then return nil end

	local model = ent:GetModel()
	local bone = leftHandCache[model]

	if bone == nil then
		bone = ent:LookupBone("ValveBiped.Bip01_L_Hand") or false
		leftHandCache[model] = bone
	end

	return bone and CopyBone(ent, bone, HAND_MAT) or nil
end

local function compute_beam(ent, state)
	local crouching = ent:GetTIFStance() == 1
	local aiming = ent:GetTIFMode() == 1
	local yaw = ent:GetAngles().y + (aiming and ent:GetNW2Float("tif_aim_yaw", 0) or 0)
	local pitch = aiming and ent:GetTIFAimPitch() or 28
	BEAM_ANG.p, BEAM_ANG.y, BEAM_ANG.r = pitch, yaw, 0
	local handMat = get_hand_light_matrix(ent, state)

	if handMat then
		return handMat:GetTranslation() + BEAM_ANG:Forward() * 6, BEAM_ANG
	end

	local pos = ent:GetPos()
	local forward, right = BEAM_ANG:Forward(), BEAM_ANG:Right()
	return Vector(
		pos.x + forward.x * 16 + right.x * 4,
		pos.y + forward.y * 16 + right.y * 4,
		pos.z + (crouching and 40 or 54) + forward.z * 16 + right.z * 4
	), BEAM_ANG
end

local TORCH_MODELS = { "models/lamps/torch.mdl", "models/maxofs2d/lamp_flashlight.mdl" }
local torchModel
local torchModels = {}

hook.Add("Think", "tif_flashlights", function()
	local states = TIF.Body and TIF.Body.States
	if not states then return end

	if torchModel == nil then
		torchModel = false

		for i = 1, #TORCH_MODELS do
			if util.IsValidModel(TORCH_MODELS[i]) then
				torchModel = TORCH_MODELS[i]
				break
			end
		end
	end

	for ent, torch in pairs(torchModels) do
		local state = states[ent]
		if not IsValid(ent) or not state or not ent:GetNW2Bool("tif_light", false) or ent:IsDormant() or not state.handLight then
			if IsValid(torch) then
				torch:Remove()
			end

			torchModels[ent] = nil
		end
	end

	local localPly = LocalPlayer()
	if not IsValid(localPly) then return end

	local eyePos = localPly:EyePos()
	local maxDist = cvMaxDist:GetFloat()
	local maxDistSqr = maxDist * maxDist
	local litCount = 0

	for ent, state in pairs(states) do
		if IsValid(ent) and not ent:IsDormant() and ent:GetNW2Bool("tif_light", false) then
			if torchModel and state.handLight then
				local handMat = get_hand_light_matrix(ent, state)
				if handMat then
					local torch = torchModels[ent]
					if not IsValid(torch) then
						torch = ClientsideModel(torchModel)
						torch:SetModelScale(torchModel == TORCH_MODELS[1] and 0.6 or 0.3)
						torchModels[ent] = torch
					end

					local _, ang = compute_beam(ent, state)
					torch:SetPos(handMat:GetTranslation() + ang:Forward() * 3)
					torch:SetAngles(ang)
				end
			end

			local distSqr = ent:GetPos():DistToSqr(eyePos)
			if distSqr < maxDistSqr then
				litCount = litCount + 1
				local entry = litEntryPool[litCount]

				if not entry then
					entry = {}
					litEntryPool[litCount] = entry
				end

				entry.ent, entry.state, entry.distSqr = ent, state, distSqr
				litSoldiers[litCount] = entry
			end
		end
	end

	for i = #litSoldiers, litCount + 1, -1 do
		litSoldiers[i] = nil
	end

	if litCount > 1 then
		table.sort(litSoldiers, by_dist_sqr)
	end

	local maxActive = math.max(0, cvMaxLights:GetInt())
	for i = 1, math.max(maxActive, #lightPool) do
		local entry = i <= maxActive and litSoldiers[i] or nil
		local projTex = lightPool[i]

		if entry then
			if not IsValid(projTex) then
				projTex = ProjectedTexture()
				projTex:SetTexture("effects/flashlight001")
				projTex:SetFOV(48)
				projTex:SetFarZ(950)
				projTex:SetNearZ(8)
				projTex:SetBrightness(2.2)
				projTex:SetColor(LIGHT_COLOR)
				projTex:SetEnableShadows(false)
				lightPool[i] = projTex
			end

			local pos, ang = compute_beam(entry.ent, entry.state)
			projTex:SetPos(pos)
			projTex:SetAngles(ang)
			projTex:Update()
		elseif IsValid(projTex) then
			projTex:Remove()
			lightPool[i] = nil
		end
	end
end)

hook.Add("PostDrawTranslucentRenderables", "tif_flashlights", function(depth, sky)
	if sky or #litSoldiers == 0 then return end

	render.SetMaterial(GLOW_MAT)
	local eyePos = EyePos()

	for i = 1, #litSoldiers do
		local entry = litSoldiers[i]
		if IsValid(entry.ent) then
			local pos, ang = compute_beam(entry.ent, entry.state)
			local toViewer = eyePos - pos
			toViewer:Normalize()
			local facing = math.Clamp(ang:Forward():Dot(toViewer), 0, 1)
			local size = 6 + 26 * facing * facing
			GLOW_COLOR.a = 90 + 160 * facing
			render.DrawSprite(pos, size, size, GLOW_COLOR)
		end
	end
end)
