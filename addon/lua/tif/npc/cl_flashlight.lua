-- Soldier weapon lights (server: tactics/sv_flashlight.lua sets NW2 "tif_light"). The nearest few lit soldiers
-- get a real projected light (no shadows, to keep it cheap); every lit soldier in range gets a glow at the
-- lens. The beam follows the soldier's facing, aim yaw and aim pitch; lowered when the weapon is down.

local TIF = TIF

local cvMax = CreateClientConVar("tif_flashlight_max", "4", true, false, "Soldier flashlights drawn as real lights (nearest first)")
local cvDist = CreateClientConVar("tif_flashlight_dist", "3000", true, false, "How far soldier flashlights are drawn")

local GLOW = Material("sprites/light_glow02_add")
local pool = {}
local lit = {}

-- MW19's alert flashlight set holds a torch in the left hand (cl_body st.handLight): the beam starts there, and a
-- torch model rides the hand.
local function hand_light(ent)
	local st = TIF.Body and TIF.Body.State and TIF.Body.State(ent)
	if not (st and st.handLight) then return nil end
	local b = ent:LookupBone("ValveBiped.Bip01_L_Hand")
	return b and ent:GetBoneMatrix(b) or nil
end

local function beam(ent)
	local crouch = ent:GetTIFStance() == 1
	local aiming = ent:GetTIFMode() == 1
	local yaw = ent:GetAngles().y + (aiming and ent:GetNW2Float("tif_aim_yaw", 0) or 0)
	local pitch = aiming and ent:GetTIFAimPitch() or 28
	local ang = Angle(pitch, yaw, 0)
	local hm = hand_light(ent)
	if hm then return hm:GetTranslation() + ang:Forward() * 6, ang end
	local pos = ent:GetPos() + Vector(0, 0, crouch and 40 or 54) + ang:Forward() * 16 + ang:Right() * 4
	return pos, ang
end

local TORCH_MODELS = { "models/lamps/torch.mdl", "models/maxofs2d/lamp_flashlight.mdl" }
local torchModel
local torches = {}
hook.Add("Think", "tif_flashlight_torches", function()
	if torchModel == nil then
		torchModel = false
		for _, m in ipairs(TORCH_MODELS) do if util.IsValidModel(m) then torchModel = m break end end
	end
	for ent, t in pairs(torches) do
		if not IsValid(ent) or not ent:GetNW2Bool("tif_light", false) or ent:IsDormant() or not hand_light(ent) then
			if IsValid(t) then t:Remove() end
			torches[ent] = nil
		end
	end
	if not torchModel then return end
	for _, ent in ipairs(ents.FindByClass("tif_soldier")) do
		if not ent:IsDormant() and ent:GetNW2Bool("tif_light", false) then
			local hm = hand_light(ent)
			if hm then
				local t = torches[ent]
				if not IsValid(t) then
					t = ClientsideModel(torchModel)
					t:SetModelScale(torchModel == TORCH_MODELS[1] and 0.6 or 0.3)
					torches[ent] = t
				end
				local _, ang = beam(ent)
				t:SetPos(hm:GetTranslation() + ang:Forward() * 3)
				t:SetAngles(ang)
			end
		end
	end
end)

hook.Add("Think", "tif_flashlights", function()
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local eye = me:EyePos()
	local maxD2 = cvDist:GetFloat() ^ 2
	for i = #lit, 1, -1 do lit[i] = nil end
	for _, ent in ipairs(ents.FindByClass("tif_soldier")) do
		if not ent:IsDormant() and ent:GetNW2Bool("tif_light", false) then
			local d2 = ent:GetPos():DistToSqr(eye)
			if d2 < maxD2 then lit[#lit + 1] = { ent = ent, d2 = d2 } end
		end
	end
	table.sort(lit, function(a, b) return a.d2 < b.d2 end)
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
				pt:SetColor(Color(255, 244, 225))
				pt:SetEnableShadows(false)
				pool[i] = pt
			end
			local pos, ang = beam(e.ent)
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
	for _, e in ipairs(lit) do
		if IsValid(e.ent) then
			local pos, ang = beam(e.ent)
			-- Brighter when the light points at the viewer.
			local to = eye - pos
			to:Normalize()
			local k = math.Clamp(ang:Forward():Dot(to), 0, 1)
			local s = 6 + 26 * k * k
			render.DrawSprite(pos, s, s, Color(255, 244, 225, 90 + 160 * k))
		end
	end
end)
