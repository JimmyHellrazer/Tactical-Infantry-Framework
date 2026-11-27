local TIF = TIF
TIF.Save = TIF.Save or {}
local S = TIF.Save

S.KEEP = {
	Pos = true, Angle = true, Class = true, Model = true, Mins = true, Maxs = true, ColGroup = true, Name = true,
	WorkshopID = true, CurHealth = true, MaxHealth = true, Persistent = true, ModelScale = true, MapCreationID = true,
	PhysicsObjects = true, EntityMods = true, BoneMods = true,
}
S.ORDER_KINDS = { free = true, hold = true, follow = true, regroup = true, advance = true, patrol = true }
S.REBUILD_DELAY = 0.3

local function saveable(ent)
	return not (ent.tifDead or ent.tifDying or ent.tifDowned or ent.tifSurrendered or ent.tifCaptive or ent.tifVeh)
end
S.Saveable = saveable

local function vec(v)
	return isvector(v) and Vector(v) or nil
end

local function arm_class(a)
	return a and a.class or nil
end

function S.Record(ent)
	if not saveable(ent) then return { skip = true } end
	local arms = ent.tifArms or {}
	local rec = {
		faction = ent:GetTIFFaction(), arch = ent.tifArchId or "rifleman",
		vis = ent:GetTIFVisual(), parts = ent:GetNW2String("tif_parts", ""), skin = ent:GetTIFSkin(),
		groups = ent:GetTIFBodygroups(), health = ent:Health(), maxHealth = ent:GetMaxHealth(),
		primary = arm_class(arms.primary), secondary = arm_class(arms.secondary), launcher = arm_class(arms.launcher),
		rockets = arms.launcher and arms.launcher.rockets or nil,
		post = vec(ent.tifPost), postYaw = ent.tifPostYaw,
	}
	local sq = ent.tifSquad
	if sq then
		rec.squad = sq.id
		rec.leader = sq.leader == ent or nil
		rec.plyLed = IsValid(sq.leader) and sq.leader:IsPlayer() or nil
		local o = sq.order
		if o and S.ORDER_KINDS[o.kind] then
			local route
			if o.route then
				route = {}
				for i, p in ipairs(o.route) do route[i] = vec(p) end
			end
			rec.order = { kind = o.kind, pos = vec(o.pos), yaw = o.yaw, pace = o.pace, route = route }
		end
	end
	return rec
end

function S.Strip(ent, data)
	for k in pairs(ent:GetTable()) do
		if not S.KEEP[k] then data[k] = nil end
	end
	data.DT, data.BodyG, data.BoneManip, data.Flex, data.FlexScale, data.Skin = nil, nil, nil, nil, nil, nil
	data.TIFSave = S.Record(ent)
end

local function from_old(data)
	local dt = istable(data.DT) and data.DT or {}
	local fac = isstring(dt.TIFFaction) and dt.TIFFaction ~= "" and dt.TIFFaction or data.TIFFaction or data.tifSpawnFaction
	return { faction = fac, arch = isstring(data.tifArchId) and data.tifArchId or nil }
end

S.Pending = S.Pending or {}

function S.Create(ply, data)
	local rec = istable(data.TIFSave) and data.TIFSave or from_old(data)
	if rec.skip then return end
	local fac = rec.faction and TIF.FactionCanon(rec.faction)
	if not (fac and TIF.Factions[fac]) then
		TIF.Warn("Saved soldier skipped: faction ", tostring(rec.faction), " isn't loaded")
		return
	end
	local ent = ents.Create(data.Class or "tif_soldier")
	if not IsValid(ent) then
		ent = ents.Create("tif_soldier")
	end

	if not IsValid(ent) then return end
	ent.tifSpawnFaction = fac
	ent.tifArchId = rec.arch
	ent.tifWeaponOverride = rec.primary
	ent.tifSecondaryOverride = rec.secondary
	ent.tifLauncherOverride = rec.launcher
	ent.tifNoAutoSquad = rec.squad ~= nil or nil
	ent:SetPos(data.Pos or vector_origin)
	ent:SetAngles(Angle(0, data.Angle and data.Angle.y or 0, 0))
	ent:Spawn()
	ent:Activate()
	if not IsValid(ent) or not ent.tifArms then return ent end
	S.ApplyLook(ent, rec)
	if rec.maxHealth and rec.maxHealth > 0 then ent:SetMaxHealth(rec.maxHealth) end
	if rec.health and rec.health > 0 then ent:SetHealth(math.min(rec.health, ent:GetMaxHealth())) end
	if rec.rockets and ent.tifArms.launcher then ent.tifArms.launcher.rockets = rec.rockets end
	if rec.post then ent.tifPost, ent.tifPostYaw = Vector(rec.post), rec.postYaw end
	if rec.squad then
		S.Pending[#S.Pending + 1] = { ent = ent, rec = rec, ply = ply }
		timer.Create("tif_save_rebuild", S.REBUILD_DELAY, 1, S.Rebuild)
	end
	return ent
end

function S.ApplyLook(ent, rec)
	if not (isstring(rec.vis) and rec.vis ~= "" and util.IsValidModel(rec.vis)) then return end
	local fac = TIF.Factions[ent:GetTIFFaction()]
	if fac and fac.models and not fac.modular then
		local known = false
		for _, m in ipairs(fac.models) do
			if m == rec.vis then known = true break end
		end
		if not known then return end
	end
	ent:SetTIFVisual(rec.vis)
	ent:SetNW2String("tif_parts", isstring(rec.parts) and rec.parts or "")
	ent:SetTIFSkin(tonumber(rec.skin) or 0)
	ent:SetTIFBodygroups(isstring(rec.groups) and rec.groups or "")
end

local function apply_order(sq, o)
	if not (o and S.ORDER_KINDS[o.kind]) then return end
	if o.kind == "patrol" and o.route and #o.route >= 2 then
		TIF.API.SquadPatrol(sq, o.route)
		return
	end
	sq.order = { kind = o.kind, pos = o.pos and Vector(o.pos) or nil, yaw = o.yaw, pace = o.pace, time = CurTime() }
	TIF.Squad.Publish(sq)
end

function S.Rebuild()
	local list = S.Pending
	S.Pending = {}
	local groups, order = {}, {}
	for _, p in ipairs(list) do
		if IsValid(p.ent) and not p.ent.tifDead then
			local g = groups[p.rec.squad]
			if not g then
				g = { members = {}, recs = {} }
				groups[p.rec.squad] = g
				order[#order + 1] = p.rec.squad
			end
			g.members[#g.members + 1] = p.ent
			g.recs[#g.recs + 1] = p.rec
			g.ply = g.ply or p.ply
			g.plyLed = g.plyLed or p.rec.plyLed
			g.order = g.order or p.rec.order
			if p.rec.leader then g.leader = p.ent end
		end
	end
	local made = {}
	for _, id in ipairs(order) do
		local g = groups[id]
		local sq
		if g.plyLed and IsValid(g.ply) and g.ply:IsPlayer() then
			sq = TIF.Squad.ForPlayer(g.ply)
			for _, e in ipairs(g.members) do TIF.Squad.Add(sq, e) end
			sq.order = { kind = "follow", time = CurTime() }
			TIF.Squad.Publish(sq)
		else
			sq = TIF.API.FormSquad(g.members)
			if sq then
				if IsValid(g.leader) and g.leader.tifSquad == sq then TIF.Squad.SetLeader(sq, g.leader) end
				apply_order(sq, g.order)
			end
		end
		if sq then made[#made + 1] = sq end
	end
	return made
end

function S.Register(class)
	duplicator.RegisterEntityClass(class, S.Create, "Data")
end

S.OLD_CLASSES = { "tif_soldier_militia", "tif_soldier_pmc" }

function S.RegisterAll()
	S.Register("tif_soldier")

	for _, class in ipairs(S.OLD_CLASSES) do
		S.Register(class)
	end

	for class, t in pairs(scripted_ents.GetList()) do
		local tt = t.t or t
		if class ~= "tif_soldier" and (tt.Base == "tif_soldier" or tt.TIFSoldier) then S.Register(class) end
	end
end

hook.Add("InitPostEntity", "tif_save", S.RegisterAll)
hook.Add("OnReloaded", "tif_save", S.RegisterAll)
if scripted_ents.GetStored("tif_soldier") then S.RegisterAll() end
