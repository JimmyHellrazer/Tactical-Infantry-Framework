AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Attack Point"
ENT.Category = "Tactical Infantry"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Editable = true
ENT.RenderGroup = RENDERGROUP_BOTH

local RADIO_MODEL = "models/props_lab/citizenradio.mdl"

local function faction_values()
	local values = TIF.FactionComboValues and TIF.FactionComboValues() or {}
	local out = {}

	for label, id in pairs(values) do
		if id ~= "auto" and id ~= "random" then
			out[label] = id
		end
	end

	return out
end

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Active", { KeyName = "active", Edit = { type = "Boolean", order = 1 } })
	self:NetworkVar("String", 0, "Faction", { KeyName = "faction", Edit = { type = "Combo", text = "Attacking faction", values = faction_values(), order = 2 } })
	self:NetworkVar("Int", 0, "Radius", { KeyName = "radius", Edit = { type = "Int", min = 100, max = 30000, order = 3 } })

	if SERVER then
		self:SetActive(true)
		self:SetFaction("insurgents")
		self:SetRadius(500)
	end
end

if CLIENT then
	local ring = Color(255, 90, 60, 200)

	function ENT:Draw()
		self:DrawModel()
	end

	function ENT:DrawTranslucent()
		local ply = LocalPlayer()
		local w = IsValid(ply) and ply:GetActiveWeapon()
		if not (IsValid(w) and (w:GetClass() == "weapon_physgun" or w:GetClass() == "gmod_tool")) then return end

		local pos = self:GetPos()
		local r = self:GetRadius()
		local base = pos + Vector(0, 0, 2)
		local prev

		render.SetColorMaterial()
		for i = 0, 48 do
			local a = i / 48 * math.pi * 2
			local p = base + Vector(math.cos(a) * r, math.sin(a) * r, 0)

			if prev then
				render.DrawLine(prev, p, ring, true)
			end

			prev = p
		end

		local def = TIF and TIF.Factions and TIF.Factions[self:GetFaction()]
		local ang = (pos - EyePos()):Angle()
		ang:RotateAroundAxis(ang:Right(), 90)
		ang:RotateAroundAxis(ang:Up(), -90)
		cam.Start3D2D(pos + Vector(0, 0, 24), ang, 0.2)
		draw.SimpleTextOutlined("Attack point: " .. (def and def.name or self:GetFaction()) .. (self:GetActive() and "" or " (off)"),
			"DermaLarge", 0, 0, ring, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
		cam.End3D2D()
	end

	function ENT:Think()
		local r = self:GetRadius()
		if self.tifDrawnR ~= r then
			self.tifDrawnR = r
			self:SetRenderBounds(Vector(-r, -r, -16), Vector(r, r, 64))
		end
	end

	return
end

ENT.TICK = 1
ENT.REVEAL_EVERY = 3
ENT.EXPECT_FOR = 8
ENT.HOLD_AT = 0.6
ENT.HOLD_MAX = 600

function ENT:SpawnFunction(ply, tr, cls)
	if not tr.Hit then return end

	local ent = ents.Create(cls)
	ent:SetPos(tr.HitPos + tr.HitNormal * 2)
	ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
	ent:Spawn()
	return ent
end

function ENT:Initialize()
	self:SetModel(RADIO_MODEL)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionGroup(COLLISION_GROUP_WORLD)
	self:DrawShadow(false)
	self.tifSquads = {}
	self:NextThink(CurTime() + 1)
end

function ENT:Takes(sq)
	if not sq or not sq.members or #sq.members == 0 then return false end
	if sq.static then return false end

	local L = sq.leader
	if IsValid(L) and L:IsPlayer() then return false end

	for _, m in ipairs(sq.members) do
		if IsValid(m) and (m.tifBase or m.tifHunter or m.tifPress) then return false end
	end

	local claim = sq.tifAttack
	if IsValid(claim) and claim ~= self and claim:GetActive() then return false end

	return TIF.FactionCanon(sq.faction) == TIF.FactionCanon(self:GetFaction())
end

function ENT:Release(sq)
	if sq.tifAttack == self then
		sq.tifAttack = nil
		sq.tifAttackHeld = nil

		if sq.members and #sq.members > 0 then
			TIF.Squad.SetOrder(sq, "free")
		end
	end
end

function ENT:Enemies()
	local fac = self:GetFaction()
	local out = {}

	for _, e in ipairs(ents.FindInSphere(self:GetPos(), self:GetRadius())) do
		if IsValid(e) and TIF.IsLiveCombatant(e) and not (e:IsPlayer() and TIF.IgnorePlayers()) then
			local other = TIF.FactionOf(e)
			if other and TIF.FactionRelation(fac, other) == TIF.REL_HOSTILE then
				out[#out + 1] = e
			end
		end
	end

	return out
end

function ENT:Reveal(sq, enemies, now)
	local P = TIF.Perception
	local members = TIF.Squad.Members(sq)

	for _, m in ipairs(members) do
		m.tifExpectEnemy = now + self.EXPECT_FOR
	end

	for _, e in ipairs(enemies) do
		local pos = e:GetPos()
		TIF.API.SquadKnowsEnemy(sq, e, pos)

		for _, m in ipairs(members) do
			if m.tifK and P and P.Contact then
				local c = P.Contact(m, e)
				if not c.visible then
					c.confirmed = true
					c.pos = Vector(pos)
					c.vel = e:GetVelocity()
					c.heardAt = now
					c.baseUnc = 64
					c.lostAt = c.lostAt or now
					c.source = "objective"
				end
			end
		end
	end
end

function ENT:Think()
	local now = CurTime()
	self:NextThink(now + self.TICK)

	if not self:GetActive() or not TIF.Squad then
		for sq in pairs(self.tifSquads) do
			self:Release(sq)
		end

		self.tifSquads = {}
		return true
	end

	local pos = self:GetPos()
	local radius = self:GetRadius()
	local reveal = now >= (self.tifNextReveal or 0)
	local enemies = reveal and self:Enemies() or nil

	if reveal then
		self.tifNextReveal = now + self.REVEAL_EVERY
	end

	for sq in pairs(self.tifSquads) do
		if not self:Takes(sq) then
			self:Release(sq)
			self.tifSquads[sq] = nil
		end
	end

	for _, sq in pairs(TIF.Squad.List) do
		if self:Takes(sq) then
			local members = TIF.Squad.Members(sq)

			if #members > 0 then
				if not self.tifSquads[sq] then
					self.tifSquads[sq] = true
					sq.tifAttack = self
					sq.tifAttackHeld = nil
					TIF.API.SquadAdvance(sq, pos, { pace = "rush" })
				end

				local L = IsValid(sq.leader) and sq.leader or members[1]
				if not sq.tifAttackHeld and L:GetPos():DistToSqr(pos) < math.min(radius * self.HOLD_AT, self.HOLD_MAX) ^ 2 then
					sq.tifAttackHeld = true
					TIF.Squad.SetOrder(sq, "hold", pos)
				end

				if enemies then
					self:Reveal(sq, enemies, now)
				end
			end
		end
	end

	return true
end

function ENT:OnRemove()
	for sq in pairs(self.tifSquads or {}) do
		self:Release(sq)
	end
end
