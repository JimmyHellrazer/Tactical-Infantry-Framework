AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "TIF Grenade"
ENT.Spawnable = false

local MODELS = {
	frag = { "models/weapons/sandswep/throwables/w_sand_m67.mdl", "models/weapons/w_grenade.mdl" },
	flash = { "models/weapons/sandswep/throwables/w_sand_m84.mdl", "models/weapons/w_grenade.mdl" },
}

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "Kind")
end

if SERVER then
	local cvDamage = CreateConVar("tif_grenade_damage", "150", FCVAR_ARCHIVE, "TIF frag grenade damage at the centre")
	local cvRadius = CreateConVar("tif_grenade_radius", "320", FCVAR_ARCHIVE, "TIF frag grenade blast radius")
	local FLASH_R = 780

	local function model_for(kind)
		for _, m in ipairs(MODELS[kind] or MODELS.frag) do
			if util.IsValidModel(m) then return m end
		end
		return "models/weapons/w_grenade.mdl"
	end

	function ENT:Initialize()
		local kind = self:GetKind()
		if kind == "" then kind = "frag" self:SetKind(kind) end
		self:SetModel(model_for(kind))
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		local ph = self:GetPhysicsObject()
		if IsValid(ph) then ph:Wake() ph:SetDamping(0.2, 1.5) end
		self.tifFuseAt = self.tifFuseAt or (CurTime() + 3)

		self.tifDodgeable = kind == "frag"
	end

	function ENT:SetFuse(t) self.tifFuseAt = CurTime() + t end

	function ENT:PhysicsCollide(data)
		if data.Speed > 60 and CurTime() - (self.tifLastBounce or 0) > 0.15 then
			self.tifLastBounce = CurTime()
			self:EmitSound("physics/metal/metal_grenade_impact_hard" .. math.random(1, 3) .. ".wav", 70, math.random(95, 110),
				math.Clamp(data.Speed / 400, 0.2, 1))
		end
	end

	local IN_ROOM = 24
	local function depth(f, pos) return (pos - f.door):Dot(f.inward) end

	function ENT:GuideThink()
		local f = self.tifForce
		if not f then return end
		local d = depth(f, self:GetPos())
		local ph = self:GetPhysicsObject()
		if d > IN_ROOM then
			f.wasIn = true
		elseif f.wasIn and IsValid(ph) then

			local v = ph:GetVelocity()
			local out = v:Dot(f.inward)
			if out < 0 then ph:SetVelocity(v - f.inward * (2 * out)) end
		end
	end

	function ENT:Think()
		if self.tifDone then return end
		if self.tifForce then self:GuideThink() end
		if CurTime() >= (self.tifFuseAt or 0) then
			self.tifDone = true
			local f = self.tifForce
			if f and depth(f, self:GetPos()) < IN_ROOM then
				self:SetPos(f.pos + Vector(0, 0, 6))
				self.tifForced = true
			end
			if self:GetKind() == "flash" then self:Flash() else self:Frag() end
			SafeRemoveEntityDelayed(self, 0)
			return
		end
		self:NextThink(CurTime() + 0.05)
		return true
	end

	function ENT:Frag()
		local pos = self:GetPos() + Vector(0, 0, 4)
		local owner = IsValid(self:GetOwner()) and self:GetOwner() or self
		local ed = EffectData()
		ed:SetOrigin(pos)
		ed:SetMagnitude(1)
		ed:SetScale(1)
		util.Effect("Explosion", ed, true, true)
		util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 32), self)
		util.BlastDamage(self, owner, pos, math.max(1, cvRadius:GetFloat()), math.max(0, cvDamage:GetFloat()))
		util.ScreenShake(pos, 6, 120, 0.8, 900)
	end

	local FLASH_MASK = bit.band(MASK_SOLID, bit.bnot(CONTENTS_GRATE))
	local flashOut = {}
	local flashTr = { mask = FLASH_MASK, filter = {}, output = flashOut }

	function ENT:Flash()
		local pos = self:GetPos() + Vector(0, 0, 6)
		self:EmitSound("BaseExplosionEffect.Sound", 100, 150)
		local ed = EffectData()
		ed:SetOrigin(pos)
		util.Effect("cball_explode", ed, true, true)
		local dl = ents.Create("light_dynamic")
		if IsValid(dl) then
			dl:SetPos(pos)
			dl:SetKeyValue("_light", "255 255 255 255")
			dl:SetKeyValue("brightness", "8")
			dl:SetKeyValue("distance", "600")
			dl:Spawn()
			dl:Fire("TurnOn")
			SafeRemoveEntityDelayed(dl, 0.15)
		end

		local thrower = IsValid(self:GetOwner()) and self:GetOwner() or nil
		if TIF and TIF.FlashAt then TIF.FlashAt(pos, FLASH_R, self, thrower) end

		flashTr.start = pos
		flashTr.filter[1] = self
		for _, ply in player.Iterator() do
			if ply:Alive() then
				local s = TIF and TIF.FlashScale and TIF.FlashScale(thrower, ply) or 1
				local R = FLASH_R * s
				local eye = ply:EyePos()
				local d = eye:Distance(pos)
				if s > 0 and d < R then
					flashTr.endpos = eye
					flashTr.filter[2] = ply
					if not util.TraceLine(flashTr).Hit then
						local facing = ply:GetAimVector():Dot((pos - eye):GetNormalized())
						local k = (1 - d / R) * Lerp((facing + 1) / 2, 0.35, 1)
						ply:ScreenFade(SCREENFADE.IN, color_white, (0.6 + 3.5 * k) * s, (0.2 + 2.5 * k) * s)
						if k > 0.25 and s >= 0.5 then ply:SetDSP(37, false) end
					end
				end
			end
		end
	end
end
