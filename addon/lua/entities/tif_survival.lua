AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Soldier Survival"
ENT.Category = "Tactical Infantry"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Editable = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Active", { KeyName = "active", Edit = { type = "Boolean", order = 1 } })
	self:NetworkVar("Bool", 1, "ShowHUD", { KeyName = "showhud", Edit = { type = "Boolean", order = 2 } })
	self:NetworkVar("String", 0, "Faction", { KeyName = "faction", Edit = { type = "Generic", order = 3 } })
	self:NetworkVar("Int", 0, "StartSize", { KeyName = "startsize", Edit = { type = "Int", min = 1, max = 60, order = 4 } })
	self:NetworkVar("Int", 1, "Growth", { KeyName = "growth", Edit = { type = "Int", min = 0, max = 100, order = 5 } })
	self:NetworkVar("Int", 2, "MaxAlive", { KeyName = "maxalive", Edit = { type = "Int", min = 1, max = 80, order = 6 } })
	self:NetworkVar("Int", 3, "SquadMin", { KeyName = "squadmin", Edit = { type = "Int", min = 1, max = 12, order = 7 } })
	self:NetworkVar("Int", 4, "SquadMax", { KeyName = "squadmax", Edit = { type = "Int", min = 1, max = 12, order = 8 } })
	self:NetworkVar("Int", 5, "BreakTime", { KeyName = "breaktime", Edit = { type = "Int", min = 0, max = 300, order = 9 } })
	self:NetworkVar("Int", 6, "SpawnMin", { KeyName = "spawnmin", Edit = { type = "Int", min = 300, max = 6000, order = 10 } })
	self:NetworkVar("Int", 7, "SpawnMax", { KeyName = "spawnmax", Edit = { type = "Int", min = 600, max = 10000, order = 11 } })
	self:NetworkVar("Int", 8, "Wave")
	self:NetworkVar("Float", 0, "RunStart")
	self:NetworkVar("Float", 1, "BreakEnd")

	if SERVER then
		self:SetActive(true)
		self:SetShowHUD(true)
		self:SetFaction("auto")
		self:SetStartSize(6)
		self:SetGrowth(25)
		self:SetMaxAlive(24)
		self:SetSquadMin(3)
		self:SetSquadMax(5)
		self:SetBreakTime(25)
		self:SetSpawnMin(1000)
		self:SetSpawnMax(3000)
	end
end

if CLIENT then
	function ENT:Draw()
		local ply = LocalPlayer()
		local w = IsValid(ply) and ply:GetActiveWeapon()
		if IsValid(w) and (w:GetClass() == "weapon_physgun" or w:GetClass() == "gmod_tool") then self:DrawModel() end
	end

	surface.CreateFont("tif_surv_big", { font = "Roboto", size = 36, weight = 800 })
	surface.CreateFont("tif_surv_small", { font = "Roboto", size = 22, weight = 600 })

	local function clock(t)
		t = math.max(0, math.floor(t))
		return string.format("%d:%02d", math.floor(t / 60), t % 60)
	end

	local current, nextFind = nil, 0
	hook.Add("HUDPaint", "tif_survival", function()
		local now = CurTime()
		if now >= nextFind then
			nextFind = now + 1
			current = nil
			for _, ent in ipairs(ents.FindByClass("tif_survival")) do
				if ent:GetActive() and ent:GetRunStart() > 0 then current = ent break end
			end
		end
		local dir = current
		if not IsValid(dir) or not dir:GetShowHUD() or dir:GetRunStart() <= 0 then return end
		local x, y = ScrW() - 24, 20
		draw.SimpleTextOutlined("WAVE " .. math.max(dir:GetWave(), 1), "tif_surv_big", x, y, Color(230, 60, 40),
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 2, color_black)
		draw.SimpleTextOutlined(clock(now - dir:GetRunStart()), "tif_surv_small", x, y + 38, Color(235, 235, 235),
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 2, color_black)
		if dir:GetBreakEnd() > now then
			draw.SimpleTextOutlined("next wave " .. clock(dir:GetBreakEnd() - now + 0.99), "tif_surv_small", x, y + 62,
				Color(170, 170, 170), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 2, color_black)
		end
	end)

	return
end

function ENT:SpawnFunction(ply, tr, cls)
	if not tr.Hit then return end
	local ent = ents.Create(cls)
	ent:SetPos(tr.HitPos + tr.HitNormal * 8)
	ent:Spawn()
	return ent
end

function ENT:Initialize()
	self:SetModel("models/editor/playerstart.mdl")
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
		local ok, err = pcall(D.SurvivalThink, self, now)
		if not ok then TIF.Error("Survival director failed: ", tostring(err)) end
	elseif self:GetRunStart() > 0 then
		D.SurvivalReset(self)
	end
	self:NextThink(now + 0.5)
	return true
end

function ENT:OnRemove()
	if TIF and TIF.Director then TIF.Director.SurvivalReset(self) end
end
