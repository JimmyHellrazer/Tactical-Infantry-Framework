AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Soldier Director"
ENT.Category = "Tactical Infantry"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Editable = true
ENT.RenderGroup = RENDERGROUP_BOTH

local RADIO_MODEL = "models/props_lab/citizenradio.mdl"

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Active", { KeyName = "active", Edit = { type = "Boolean", order = 1 } })
	self:NetworkVar("String", 0, "Faction", { KeyName = "faction", Edit = { type = "Combo", text = "Auto (hostile to you)", values = TIF.FactionComboValues and TIF.FactionComboValues() or { ["Auto (hostile to you)"] = "auto" }, order = 2 } })
	self:NetworkVar("Int", 0, "MaxAlive", { KeyName = "maxalive", Edit = { type = "Int", min = 1, max = 80, order = 3 } })
	self:NetworkVar("Int", 1, "AmbientSquads", { KeyName = "ambientsquads", Edit = { type = "Int", min = 0, max = 10, order = 4 } })
	self:NetworkVar("Int", 2, "AssaultSquads", { KeyName = "assaultsquads", Edit = { type = "Int", min = 0, max = 6, order = 5 } })
	self:NetworkVar("Int", 3, "SquadMin", { KeyName = "squadmin", Edit = { type = "Int", min = 1, max = 12, order = 6 } })
	self:NetworkVar("Int", 4, "SquadMax", { KeyName = "squadmax", Edit = { type = "Int", min = 1, max = 12, order = 7 } })
	self:NetworkVar("Int", 5, "AssaultMin", { KeyName = "assaultmin", Edit = { type = "Int", min = 15, max = 900, order = 8 } })
	self:NetworkVar("Int", 6, "AssaultMax", { KeyName = "assaultmax", Edit = { type = "Int", min = 15, max = 900, order = 9 } })
	self:NetworkVar("Int", 7, "SpawnMin", { KeyName = "spawnmin", Edit = { type = "Int", min = 300, max = 6000, order = 10 } })
	self:NetworkVar("Int", 8, "SpawnMax", { KeyName = "spawnmax", Edit = { type = "Int", min = 600, max = 10000, order = 11 } })
	self:NetworkVar("Int", 9, "PeakIntensity", { KeyName = "peak", Edit = { type = "Int", min = 20, max = 400, order = 12 } })
	self:NetworkVar("Int", 10, "RelaxIntensity", { KeyName = "relax", Edit = { type = "Int", min = 0, max = 200, order = 13 } })
	self:NetworkVar("Int", 11, "RelaxTime", { KeyName = "relaxtime", Edit = { type = "Int", min = 0, max = 600, order = 14 } })
	self:NetworkVar("String", 1, "Phase")

	if SERVER then
		self:SetActive(true)
		self:SetFaction("auto")
		self:SetMaxAlive(24)
		self:SetAmbientSquads(3)
		self:SetAssaultSquads(2)
		self:SetSquadMin(4)
		self:SetSquadMax(6)
		self:SetAssaultMin(60)
		self:SetAssaultMax(120)
		self:SetSpawnMin(1200)
		self:SetSpawnMax(3500)
		self:SetPeakIntensity(120)
		self:SetRelaxIntensity(25)
		self:SetRelaxTime(40)
		self:SetPhase("starting")
	end
end

if CLIENT then
	function ENT:Draw()
		self:DrawModel()

		local ply = LocalPlayer()
		local w = IsValid(ply) and ply:GetActiveWeapon()
		if not (IsValid(w) and (w:GetClass() == "weapon_physgun" or w:GetClass() == "gmod_tool")) then return end

		local ang = (self:GetPos() - EyePos()):Angle()
		ang:RotateAroundAxis(ang:Right(), 90)
		ang:RotateAroundAxis(ang:Up(), -90)
		cam.Start3D2D(self:GetPos() + Vector(0, 0, 24), ang, 0.2)
		draw.SimpleTextOutlined("TIF director: " .. (self:GetActive() and self:GetPhase() or "off"), "DermaLarge", 0, 0,
			color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
		cam.End3D2D()
	end

	return
end

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
	self:NextThink(CurTime() + 1)
end

function ENT:Think()
	local D = TIF and TIF.Director
	if not D then return end
	local now = CurTime()
	if self:GetActive() then
		local ok, phase = pcall(D.DirectorThink, self, now)
		if ok then
			self:SetPhase(phase or "")
		else
			self:SetPhase("error")
			TIF.Error("Director failed: ", tostring(phase))
		end
	elseif self.tifDir then
		D.DirectorClear(self)
		self:SetPhase("off")
	end
	self:NextThink(now + 0.5)
	return true
end

function ENT:OnRemove()
	if TIF and TIF.Director then TIF.Director.DirectorClear(self) end
end
