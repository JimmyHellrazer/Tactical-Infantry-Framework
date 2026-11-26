local TIF = TIF
local IsValid, Vector, Angle, Color = IsValid, Vector, Angle, Color
local CopyBone = TIF.CopyBone or function(ent, bone) return bone and ent:GetBoneMatrix(bone) end

local cvMax = CreateClientConVar("tif_flashlight_max", "4", true, false, "Soldier flashlights drawn as real lights (nearest first)")
local cvDist = CreateClientConVar("tif_flashlight_dist", "3000", true, false, "How far soldier flashlights are drawn")

local GLOW = Material("sprites/light_glow02_add")
local LIGHT_COL = Color(255, 244, 225)
local GLOW_COL = Color(255, 244, 225, 255)
local HAND_M = Matrix()
local BEAM_ANG = Angle()
local lHandOf = {}
local pool = {}
local lit, litPool = {}, {}

local function by_dist(a, b) return a.d2 < b.d2 end

local function hand_light(ent, st)
	st = st or (TIF.Body and TIF.Body.State and TIF.Body.State(ent))
	if not (st and st.handLight) then return nil end
	local mdl = ent:GetModel()
	local b = lHandOf[mdl]
	if b == nil then
		b = ent:LookupBone("ValveBiped.Bip01_L_Hand") or false
		lHandOf[mdl] = b
	end
	return b and CopyBone(ent, b, HAND_M) or nil
end

local function beam(ent, st)
	local crouch = ent:GetTIFStance() == 1
	local aiming = ent:GetTIFMode() == 1
	local yaw = ent:GetAngles().y + (aiming and ent:GetNW2Float("tif_aim_yaw", 0) or 0)
	local pitch = aiming and ent:GetTIFAimPitch() or 28
	BEAM_ANG.p, BEAM_ANG.y, BEAM_ANG.r = pitch, yaw, 0
	local hm = hand_light(ent, st)
	if hm then return hm:GetTranslation() + BEAM_ANG:Forward() * 6, BEAM_ANG end
	local pos = ent:GetPos()
	local fwd, right = BEAM_ANG:Forward(), BEAM_ANG:Right()
	return Vector(pos.x + fwd.x * 16 + right.x * 4, pos.y + fwd.y * 16 + right.y * 4,
		pos.z + (crouch and 40 or 54) + fwd.z * 16 + right.z * 4), BEAM_ANG
end

local TORCH_MODELS = { "models/lamps/torch.mdl", "models/maxofs2d/lamp_flashlight.mdl" }
local torchModel
local torches = {}

hook.Add("Think", "tif_flashlights", function()
	local states = TIF.Body and TIF.Body.States
	if not states then return end
	if torchModel == nil then
		torchModel = false
		for i = 1, #TORCH_MODELS do
			if util.IsValidModel(TORCH_MODELS[i]) then torchModel = TORCH_MODELS[i] break end
		end
	end
	for ent, t in pairs(torches) do
		local st = states[ent]
		if not IsValid(ent) or not st or not ent:GetNW2Bool("tif_light", false) or ent:IsDormant() or not st.handLight then
			if IsValid(t) then t:Remove() end
			torches[ent] = nil
		end
	end
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local eye = me:EyePos()
	local dist = cvDist:GetFloat()
	local maxD2 = dist * dist
	local count = 0
	for ent, st in pairs(states) do
		if IsValid(ent) and not ent:IsDormant() and ent:GetNW2Bool("tif_light", false) then
			if torchModel and st.handLight then
				local hm = hand_light(ent, st)
				if hm then
					local t = torches[ent]
					if not IsValid(t) then
						t = ClientsideModel(torchModel)
						t:SetModelScale(torchModel == TORCH_MODELS[1] and 0.6 or 0.3)
						torches[ent] = t
					end
					local _, ang = beam(ent, st)
					t:SetPos(hm:GetTranslation() + ang:Forward() * 3)
					t:SetAngles(ang)
				end
			end
			local d2 = ent:GetPos():DistToSqr(eye)
			if d2 < maxD2 then
				count = count + 1
				local e = litPool[count]
				if not e then e = {} litPool[count] = e end
				e.ent, e.st, e.d2 = ent, st, d2
				lit[count] = e
			end
		end
	end
	for i = #lit, count + 1, -1 do lit[i] = nil end
	if count > 1 then table.sort(lit, by_dist) end
	local n = math.max(0, cvMax:GetInt())
	for i = 1, math.max(n, #pool) do
		local e = i <= n and lit[i] or nil
		local pt = pool[i]
		if e then
			if not IsValid(pt) then
				pt = ProjectedTexture()
				pt:SetTexture("effects/flashlight001")
				pt:SetFOV(48)
				pt:SetFarZ(950)
				pt:SetNearZ(8)
				pt:SetBrightness(2.2)
				pt:SetColor(LIGHT_COL)
				pt:SetEnableShadows(false)
				pool[i] = pt
			end
			local pos, ang = beam(e.ent, e.st)
			pt:SetPos(pos)
			pt:SetAngles(ang)
			pt:Update()
		elseif IsValid(pt) then
			pt:Remove()
			pool[i] = nil
		end
	end
end)

hook.Add("PostDrawTranslucentRenderables", "tif_flashlights", function(depth, sky)
	if sky or #lit == 0 then return end
	render.SetMaterial(GLOW)
	local eye = EyePos()
	for i = 1, #lit do
		local e = lit[i]
		if IsValid(e.ent) then
			local pos, ang = beam(e.ent, e.st)
			local to = eye - pos
			to:Normalize()
			local k = math.Clamp(ang:Forward():Dot(to), 0, 1)
			local s = 6 + 26 * k * k
			GLOW_COL.a = 90 + 160 * k
			render.DrawSprite(pos, s, s, GLOW_COL)
		end
	end
end)
