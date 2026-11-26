AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "TIF Rocket"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

local MODEL = "models/weapons/w_missile_closed.mdl"

if SERVER then
	local cvDamage = CreateConVar("tif_rocket_damage", "200", FCVAR_ARCHIVE, "TIF launcher rocket damage at the centre")
	local cvRadius = CreateConVar("tif_rocket_radius", "250", FCVAR_ARCHIVE, "TIF launcher rocket blast radius")

	function ENT:Setup(p, dir, owner)
		self.tifP = p or {}
		self.tifDir = dir
		local r = self.tifP.rocket or {}
		self.tifSpeed = r.start or self.tifP.speed or 1500
		self.tifAccel = r.accel or 0
		self.tifMax = r.max or self.tifSpeed
		self.tifGrav = (self.tifP.gravity or 0) * 600
		self.tifDie = CurTime() + (self.tifP.life or 5)
		if IsValid(owner) then
			self:SetOwner(owner)
		end
	end

	function ENT:Initialize()
		self:SetModel(util.IsValidModel(MODEL) and MODEL or "models/weapons/w_grenade.mdl")
		self:SetMoveType(MOVETYPE_FLY)
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionBounds(Vector(-3, -3, -3), Vector(3, 3, 3))
		self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
		self.tifDir = self.tifDir or self:GetForward()
		self.tifSpeed = self.tifSpeed or 1500
		self.tifDie = self.tifDie or (CurTime() + 5)
		self.tifVel = self.tifDir * self.tifSpeed
		self:SetVelocity(self.tifVel)
		self:SetAngles(self.tifDir:Angle())
		self:EmitSound("weapons/rpg/rocket1.wav", 80, 100, 0.8)
		self.tifLast = CurTime()
	end

	local ROCKET_MIN, ROCKET_MAX = Vector(-3, -3, -3), Vector(3, 3, 3)
	local rocketOut = {}
	local rocketHull = { mins = ROCKET_MIN, maxs = ROCKET_MAX, mask = MASK_SHOT, filter = {}, output = rocketOut }

	function ENT:Think()
		if self.tifDone then return end
		local now = CurTime()
		local dt = math.max(0, now - (self.tifLast or now))
		self.tifLast = now
		if now >= self.tifDie then
			self:Burst(self:GetPos())
			return
		end

		local v = self.tifVel or self:GetVelocity()
		local len = v:Length()
		local speed = math.min(self.tifMax or len, len + (self.tifAccel or 0) * dt)
		local d = len > 1e-4 and (v / len) or self:GetForward()
		v = d * speed
		v.z = v.z - (self.tifGrav or 0) * dt

		local pos = self:GetPos()
		rocketHull.start = pos
		rocketHull.endpos = pos + v * math.max(dt, FrameTime())
		rocketHull.filter[1], rocketHull.filter[2] = self, self:GetOwner()
		local tr = util.TraceHull(rocketHull)
		if tr.Hit then
			if tr.HitSky then
				self.tifDone = true
				self:StopSound("weapons/rpg/rocket1.wav")
				SafeRemoveEntityDelayed(self, 0)
			else
				self:Burst(tr.HitPos + tr.HitNormal * 4, tr.HitNormal)
			end
			return
		end
		self.tifVel = v
		self:SetLocalVelocity(v)
		self:SetAngles(v:Angle())
		self:NextThink(now)
		return true
	end

	function ENT:Touch(ent)
		if self.tifDone or ent == self:GetOwner() then return end
		if ent:IsSolid() then
			self:Burst(self:GetPos())
		end
	end

	function ENT:Burst(pos, normal)
		if self.tifDone then return end
		self.tifDone = true
		self:StopSound("weapons/rpg/rocket1.wav")
		local owner = IsValid(self:GetOwner()) and self:GetOwner() or self
		local ed = EffectData()
		ed:SetOrigin(pos)
		ed:SetMagnitude(1)
		ed:SetScale(1)
		util.Effect("Explosion", ed, true, true)
		normal = normal or Vector(0, 0, 1)
		util.Decal("Scorch", pos + normal * 8, pos - normal * 32, self)
		util.BlastDamage(self, owner, pos, math.max(1, cvRadius:GetFloat()), math.max(0, cvDamage:GetFloat()))
		util.ScreenShake(pos, 8, 150, 1, 1400)
		SafeRemoveEntityDelayed(self, 0)
	end

	function ENT:OnRemove()
		self:StopSound("weapons/rpg/rocket1.wav")
	end
else
	function ENT:Initialize()
		self.tifEmitter = ParticleEmitter(self:GetPos())
		self.tifNextPuff = 0
	end

	function ENT:Think()
		local em = self.tifEmitter
		if not em then
			em = ParticleEmitter(self:GetPos())
			self.tifEmitter = em
		end
		if not em then return end
		local now = CurTime()
		if now >= (self.tifNextPuff or 0) then
			self.tifNextPuff = now + 0.015
			local back = self:GetPos() - self:GetForward() * 14
			local p = em:Add("particle/particle_smokegrenade", back)
			if p then
				p:SetVelocity(VectorRand() * 12)
				p:SetDieTime(math.Rand(1.2, 2))
				p:SetStartAlpha(110)
				p:SetEndAlpha(0)
				p:SetStartSize(4)
				p:SetEndSize(math.Rand(22, 34))
				p:SetRoll(math.Rand(0, 360))
				p:SetColor(200, 200, 200)
			end
		end
	end

	function ENT:Draw()
		self:DrawModel()

		local dl = DynamicLight(self:EntIndex())
		if dl then
			dl.pos = self:GetPos() - self:GetForward() * 12
			dl.r, dl.g, dl.b = 255, 170, 80
			dl.brightness = 2
			dl.decay = 1000
			dl.size = 160
			dl.dietime = CurTime() + 0.1
		end
	end

	function ENT:OnRemove(fullUpdate)
		if fullUpdate then return end
		if self.tifEmitter then
			self.tifEmitter:Finish() self.tifEmitter = nil
		end
	end
end
