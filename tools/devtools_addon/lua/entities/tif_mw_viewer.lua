-- Stage 1 checker for the MW19 host ("mw_male"): plays one clip on the host model and moves it along the clip's
-- root curve exactly like TIF's actions do, so foot sliding and travel can be judged by eye.
-- Spawned by the tif_mw_view command (lua/autorun/tif_mw_view.lua).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "TIF MW19 clip viewer"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Role")
	self:NetworkVar("String", 1, "Playermodel")
	self:NetworkVar("Float", 0, "Start")
	self:NetworkVar("Bool", 0, "Travel")
end

local function clip_of(role)
	local set = TIFG and TIFG.Clips and TIFG.Clips.mw_male
	return set and set[role]
end

function ENT:Initialize()
	self:SetModel("models/tif_mw/mw_male.mdl")
	if SERVER then
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
		self.origin, self.yaw = self:GetPos(), self:GetAngles().y
	end
end

-- Root offset (local x forward, y left, yaw) of the clip at time t, counting whole loops for looping clips.
local function root_at(clip, t)
	local dur = math.max(0.01, clip.dur)
	local loops, u = 0, t / dur
	if clip.loop then loops = math.floor(u) u = u - loops else u = math.Clamp(u, 0, 1) end
	local f = u * math.max(1, clip.frames - 1)
	local x = TIFG.ClipCurve(clip, f, 1) + loops * clip.move[1]
	local y = TIFG.ClipCurve(clip, f, 2) + loops * clip.move[2]
	local r = TIFG.ClipCurve(clip, f, 3) + loops * clip.move[3]
	return x, y, r, u
end

function ENT:Think()
	local clip = clip_of(self:GetRole())
	if not clip then return end
	local t = CurTime() - self:GetStart()
	local seq = self:LookupSequence(clip.seq)
	if seq and seq >= 0 and self:GetSequence() ~= seq then self:ResetSequence(seq) end
	local x, y, r, u = root_at(clip, t)
	self:SetCycle(u)
	self:SetPlaybackRate(0)
	if SERVER then
		if self:GetTravel() then
			-- loops go 3 laps and come back, so the clip stays in view
			if clip.loop and t > clip.dur * 3 then self:SetStart(CurTime()) end
			local rad = math.rad(self.yaw)
			local c, s = math.cos(rad), math.sin(rad)
			self:SetPos(self.origin + Vector(x * c - y * s, x * s + y * c, 0))
			self:SetAngles(Angle(0, self.yaw + r, 0))
		end
		if not clip.loop and t > clip.dur + 1 then
			self:SetStart(CurTime())
			self:SetPos(self.origin)
			self:SetAngles(Angle(0, self.yaw, 0))
		end
	end
	self:NextThink(CurTime())
	return true
end

if CLIENT then
	local GUN = "models/weapons/w_smg1.mdl"

	function ENT:Draw()
		self:InvalidateBoneCache()
		local pm = self:GetPlayermodel()
		if pm ~= "" then
			-- A playermodel bone-merged straight onto the host (same ValveBiped names): the Stage 2 setup.
			if not IsValid(self.pm) or self.pmModel ~= pm then
				if IsValid(self.pm) then self.pm:Remove() end
				self.pm = ClientsideModel(pm, RENDERGROUP_OPAQUE)
				if IsValid(self.pm) then
					self.pm:SetParent(self)
					self.pm:AddEffects(EF_BONEMERGE)
					self.pm:SetNoDraw(true)
				end
				self.pmModel = pm
			end
			self:SetupBones()
			if IsValid(self.pm) then self.pm:DrawModel() end
		else
			if IsValid(self.pm) then self.pm:Remove() end
			self:DrawModel()
		end
		-- A stand-in gun on j_gun: the clip's own weapon motion (no grip fitting yet).
		local b = self:LookupBone("j_gun")
		local m = b and self:GetBoneMatrix(b)
		if m then
			if not IsValid(self.gun) then
				self.gun = ClientsideModel(GUN, RENDERGROUP_OPAQUE)
				if IsValid(self.gun) then self.gun:SetNoDraw(true) end
			end
			if IsValid(self.gun) then
				self.gun:SetPos(m:GetTranslation())
				self.gun:SetAngles(m:GetAngles())
				self.gun:SetupBones()
				self.gun:DrawModel()
			end
		end
	end

	function ENT:OnRemove()
		if IsValid(self.pm) then self.pm:Remove() end
		if IsValid(self.gun) then self.gun:Remove() end
	end
end
