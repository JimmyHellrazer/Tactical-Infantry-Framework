AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.PrintName = "TIF Soldier"
ENT.Author = "TIF"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.TIFSoldier = true
ENT.TIFFaction = nil

local STAND_MAX = Vector(13, 13, 72)
local CROUCH_MAX = Vector(13, 13, 46)
local HULL_MIN = Vector(-13, -13, 0)

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "TIFFaction")
	self:NetworkVar("String", 1, "TIFVisual")
	self:NetworkVar("String", 2, "TIFWeapon")
	self:NetworkVar("String", 3, "TIFBodygroups")
	self:NetworkVar("Int", 0, "TIFStance")
	self:NetworkVar("Int", 1, "TIFMode")
	self:NetworkVar("Int", 2, "TIFAware")
	self:NetworkVar("Int", 3, "TIFSkin")
	self:NetworkVar("Float", 0, "TIFAimPitch")
	self:NetworkVar("Float", 1, "TIFShotTime")
	self:NetworkVar("Float", 2, "TIFReloadStart")
	self:NetworkVar("Float", 3, "TIFHitTime")
	self:NetworkVar("Float", 4, "TIFSupp")
	self:NetworkVar("Vector", 0, "TIFHitDir")
end

if CLIENT then
	function ENT:Initialize() TIF.Body.Add(self) end
	function ENT:Draw(flags) TIF.Body.DrawHost(self, flags) end

	function ENT:OnRemove(fullUpdate) TIF.Body.Remove(self) end
	return
end

local modelInfo = {}
local function model_info(model)
	local info = modelInfo[model]
	if info then return info end
	local e = ents.Create("prop_dynamic")
	info = { skins = 1, groups = {} }
	if IsValid(e) then
		e:SetModel(model)
		info.skins = math.max(1, e:SkinCount())
		for _, bg in ipairs(e:GetBodyGroups() or {}) do

			local blank = {}
			for k, sm in pairs(bg.submodels or {}) do
				if not isstring(sm) or sm == "" or string.lower(sm) == "blank" then
					blank[k] = true
				end
			end
			info.groups[#info.groups + 1] = { name = bg.name, num = bg.num, blank = blank }
		end
		e:Remove()
	end

	modelInfo[model] = info
	return info
end

local function random_look(model, fac)
	local info = model_info(model)
	local fid = fac and fac.id
	local function pick(key, fit)
		return (TIF.VarietyPick and TIF.VarietyPick(fid, key, fit)) or fit[math.random(#fit)]
	end

	local allowed = istable(fac and fac.bodygroups) and fac.bodygroups or {}
	local noBlank = fac and fac.noBlank
	local digits, byName = {}, {}
	for i, g in ipairs(info.groups) do
		local name = string.lower(g.name)
		local v = 0
		local ok = allowed[name]
		local function usable(x) return x >= 0 and x < g.num and not (noBlank and g.blank and g.blank[x]) end
		if istable(ok) and #ok > 0 then
			local fit = {}
			for _, x in ipairs(ok) do
				if isnumber(x) and usable(x) then
					fit[#fit + 1] = x
				end
			end
			v = #fit > 0 and pick(model .. "#" .. name, fit) or 0
		elseif g.num > 1 and name ~= "body" then

			local fit = {}
			for x = 0, g.num - 1 do if usable(x) then fit[#fit + 1] = x end end
			v = #fit > 0 and pick(model .. "#" .. name, fit) or 0
		end
		digits[i] = v
		byName[name] = i
	end

	for _, r in ipairs(istable(fac and fac.bodyRules) and fac.bodyRules or {}) do
		local gi, ni = byName[string.lower(tostring(r[1]))], byName[string.lower(tostring(r[2]))]
		if gi and ni and digits[ni] == 0 then
			digits[gi] = 0
		end
	end

	local skins = {}
	for x = 0, math.max(0, info.skins - 1) do
		skins[#skins + 1] = x
	end

	return pick(model .. "#skin", skins) or 0, table.concat(digits, " ")
end

function ENT:KeyValue(k, v)
	if k == "tif_faction" and v ~= "" then self.tifSpawnFaction = v
	elseif k == "tif_arch" and v ~= "" then self.tifArchId = TIF.Archetypes and TIF.Archetypes[v] and v or self.tifArchId end
end

function ENT:Initialize()
	local facId = self.TIFFaction or self.tifSpawnFaction or "insurgents"
	local fac = TIF.Factions[facId]
	local hostId = fac and TIF.GTG.HostFor(fac)
	local host = hostId and TIF.GTG.HostModel(hostId)
	if not host then
		TIF.Error("Can't spawn soldier: faction ", tostring(facId), " missing, or the MW19 body (mw_male) isn't loaded")
		SafeRemoveEntityDelayed(self, 0)
		return
	end

	self:SetModel(host)

	self.tifHostId, self.tifHomeHost = hostId, hostId
	self:SetNW2String("tif_host", hostId)
	self:SetTIFFaction(facId)

	local vis = TIF.PickVisual and TIF.PickVisual(fac, self) or fac.models[math.random(#fac.models)]

	local parts = ""

	local modMain, modParts
	if TIF.Modular and TIF.Modular.Pick then
		modMain, modParts = TIF.Modular.Pick(fac, self.tifArchId or "rifleman")
	end

	if modMain then
		vis, parts = modMain, modParts or ""
	end
	local skin, groups = random_look(vis, fac)
	if modMain and fac.modular.skins == false then
		skin = 0
	end

	if modMain then

		local digits = {}
		for i, g in ipairs(model_info(vis).groups) do
			local v = 0
			if string.find(string.lower(g.name), "placeholder", 1, true) then
				v = g.num - 1
				for k in pairs(g.blank or {}) do
					v = k
					break
				end
			end
			digits[i] = v
		end
		groups = table.concat(digits, " ")
	end

	self:SetNW2String("tif_parts", parts)
	self:SetTIFVisual(vis)
	self:SetTIFSkin(skin)
	self:SetTIFBodygroups(groups)

	self.tifArchId = self.tifArchId or "rifleman"
	self.tifArch = TIF.Archetype(self.tifArchId)
	local hpScale = GetConVar("tif_health_scale")
	self:SetHealth(math.max(1, math.floor((self.tifHealthOverride or self.tifArch.health) * (hpScale and hpScale:GetFloat() or 1))))
	self:SetMaxHealth(self:Health())
	self:SetBloodColor(BLOOD_COLOR_RED)
	self:SetCollisionBounds(HULL_MIN, STAND_MAX)

	local loco = self.loco
	loco:SetStepHeight(18)
	loco:SetJumpHeight(0)
	loco:SetDeathDropHeight(180)
	loco:SetAcceleration(700)
	loco:SetDeceleration(1100)
	loco:SetMaxYawRate(self.tifArch.turnRate)

	local idleClip = TIF.GTG.Clip("idle", hostId)
	local idle = self:LookupSequence(idleClip and idleClip.seq or "") or 0
	if idle < 0 then
		idle = 0
	end

	self:ResetSequence(idle)
	self.tifIdleSeq = idle
	self.tifSlots = {}
	self:TIFRefreshSlots()

	local primary, secondary, launcher = TIF.Loadout(fac, self.tifArchId)
	TIF.Weapon.Init(self, self.tifWeaponOverride or primary, self.tifSecondaryOverride or secondary,
		self.tifLauncherOverride or launcher)
	TIF.Perception.Init(self)
	TIF.Move.Init(self)
	TIF.Brain.Init(self)
	if TIF.Morale then
		TIF.Morale.Init(self)
	end

	self:TIFPickMainSequences(hostId)
	TIF.Register(self)

	timer.Simple(0, function()
		if IsValid(self) and not self.tifNoAutoSquad and not self.tifSquad then
			TIF.Squad.AutoJoin(self)
		end
	end)
end

local SLOT_WEIGHT = 0.002

function ENT:TIFRefreshSlots(nudge)
	local made = 0
	for i = 1, TIF.Anim.SLOTS do
		local id = self.tifSlots[i]
		if not (id and self:IsValidLayer(id)) then
			id = self:AddLayeredSequence(self.tifIdleSeq or 0, i)
			if id and id >= 0 then
				self:SetLayerPlaybackRate(id, 0)
				self:SetLayerCycle(id, 0)
				self:SetLayerLooping(id, true)
				self:SetLayerWeight(id, SLOT_WEIGHT)
				self.tifSlots[i] = id
				made = made + 1
			end
		elseif nudge then
			self:SetLayerSequence(id, self.tifIdleSeq or 0)
			self:SetLayerWeight(id, SLOT_WEIGHT + math.Rand(0, 0.0005))
		end
	end

	if made > 0 then
		TIF.Prof.Count("slots_rebuilt", made)
	end
	return made
end

util.AddNetworkString("tif_slots_missing")
local lastRefresh = setmetatable({}, { __mode = "k" })

net.Receive("tif_slots_missing", function(_, ply)
	local ent = net.ReadEntity()
	if not (IsValid(ent) and ent.TIFSoldier and ent.tifSlots and not ent.tifDead) then
		return
	end

	local now = CurTime()
	if (lastRefresh[ent] or 0) > now - 1 then return end
	lastRefresh[ent] = now
	TIF.Prof.Count("slots_refresh_requests", 1)
	ent:TIFRefreshSlots(true)
end)

function ENT:TIFPickMainSequences(host)
	local function seq(name)
		local c = TIF.GTG.Clip(name, host)
		return c and self:LookupSequence(c.seq) or -1
	end

	self.tifMainSeq = {
		relaxed = seq("idle"),
		aim = seq("mstg_idle"),
		crouch = seq("crouch_mstg_idle"),
		prone = seq("mwp_idle"),
	}
end

function ENT:TIFSetHost(id)
	if not id or id == self.tifHostId then return end
	local model = TIF.GTG.HostModel(id)
	if not model then return end
	self:SetModel(model)
	self.tifHostId = id
	self:SetNW2String("tif_host", id)
	local idleClip = TIF.GTG.Clip("idle", id)
	local idle = self:LookupSequence(idleClip and idleClip.seq or "") or 0
	self.tifIdleSeq = idle >= 0 and idle or 0
	self:TIFPickMainSequences(id)
	self:TIFRefreshSlots(true)
	self:TIFApplyStance()
	TIF.Prof.Count("host_swaps", 1)
end

local SLIM_MIN, SLIM_MAX, SLIM_CROUCH = Vector(-7, -7, 0), Vector(7, 7, 72), Vector(7, 7, 46)

function ENT:TIFApplyStance()
	local crouch = self:GetTIFStance() == 1

	if self.tifSlim then
		self:SetCollisionBounds(SLIM_MIN, crouch and SLIM_CROUCH or SLIM_MAX)
	else
		self:SetCollisionBounds(HULL_MIN, crouch and CROUCH_MAX or STAND_MAX)
	end
end

function ENT:TIFSetSlim(on)
	on = on or nil
	if self.tifSlim == on then return end
	self.tifSlim = on
	self:TIFApplyStance()
end

function ENT:TIFThink(dt)
	TIF.Brain.Think(self, dt)
end

function ENT:TIFHear(kind, pos, d2, src, faction)
	TIF.Perception.Hear(self, kind, pos, d2, src, faction)
end

function ENT:RunBehaviour()
	while true do
		if not self.tifDead and not TIF.AIDisabled() then
			TIF.Prof.Begin("move")
			TIF.Move.Step(self)
			TIF.Prof.End()
		end
		coroutine.yield()
	end
end

function ENT:BodyUpdate()

	local dy = self.tifDying
	if dy then
		if dy.seq and dy.seq >= 0 then
			if self:GetSequence() ~= dy.seq then
				self:ResetSequence(dy.seq)
			end
			self:SetCycle(math.Clamp((CurTime() - dy.t0) / math.max(0.05, dy.dur), 0, 1))
			self:SetPlaybackRate(0)
		end
		return
	end

	local a = self.tifDowned and self.tifAct
	local ac = a and a.clip
	if ac and ac.seq then
		local seq = self:LookupSequence(ac.seq)
		if seq and seq >= 0 then
			if self:GetSequence() ~= seq then
				self:ResetSequence(seq)
			end
			local t = (CurTime() - a.t0) * (a.rate or 1)
			local u = a.loop and (t / math.max(0.05, ac.dur)) % 1 or math.Clamp(t / math.max(0.05, ac.dur), 0, 1)
			local fixed = self:GetNW2Float("tif_act_cycle", -1)
			if fixed >= 0 then
				u = fixed
			end
			self:SetCycle(u)
			self:SetPlaybackRate(0)
			return
		end
	end

	local m = self.tifMainSeq
	if m then
		local want

		local prone = (self.tifProne ~= nil and self.tifProne.phase == 2) or self.tifDowned ~= nil
		if prone then want = m.prone
		elseif self.tifHitboxPose == "crouch" then
			want = m.crouch
		elseif self.tifHitboxPose == "aim" then
			want = m.aim
		else
			want = self:GetTIFStance() == 1 and m.crouch or (self:GetTIFMode() == 1 and m.aim or m.relaxed)
		end
		if want and want >= 0 and self:GetSequence() ~= want then
			self:ResetSequence(want)
			if prone then
				self:SetCycle(0)
				self:SetPlaybackRate(0)
			end
		end
	end

	if not ((self.tifProne and self.tifProne.phase == 2) or self.tifDowned) then
		self:FrameAdvance()
	end
end

function ENT:Think()
	local now = CurTime()
	local dt = math.min(0.2, now - (self.tifThinkAt or now))
	self.tifThinkAt = now
	if self.tifDying then
		TIF.HitsMW.DyingThink(self, now)
		self:NextThink(now)
		return true
	end

	if not self.tifDead and not TIF.AIDisabled() then
		TIF.Prof.Begin("tick")
		TIF.Action.Tick(self, now)
		if self.tifHostId ~= self.tifHomeHost then
			if self.tifAct or self.tifVeh or self.tifBoard then
				self.tifNoActSince = nil
			else
				self.tifNoActSince = self.tifNoActSince or now
				if now - self.tifNoActSince > 0.6 then
					self.tifNoActSince = nil
					self:TIFSetHost(self.tifHomeHost)
				end
			end
		end
		TIF.Move.Face(self, dt)
		local face = self.tifFace or self.tifAimAt
		local want = 0
		if face and self.tifMode == 1 then
			local d = face - TIF.EyeOf(self)
			want = -math.deg(math.atan2(d.z, math.max(1, d:Length2D())))
		end
		self.tifPitch = math.Approach(self.tifPitch or 0, want, 220 * dt)
		if math.abs(self.tifPitch - self:GetTIFAimPitch()) > 0.75 then
			self:SetTIFAimPitch(self.tifPitch)
		end
		local fw = self.tifFire
		local look = (fw and fw.want and fw.aimPos) or self.tifAimAt or self.tifFace
		local sent = self.tifLookSent
		if look then
			if not sent or sent:DistToSqr(look) > 32 * 32 then
				if sent then
					sent.x, sent.y, sent.z = look.x, look.y, look.z
				else
					sent = Vector(look)
					self.tifLookSent = sent
				end
				self:SetNW2Vector("tif_look", sent)
			end
		elseif sent then
			self.tifLookSent = nil
			self:SetNW2Vector("tif_look", vector_origin)
		end
		TIF.Weapon.Think(self, now)
		if now > (self.tifNextSlotCheck or 0) then
			self.tifNextSlotCheck = now + 2
			self:TIFRefreshSlots()
		end
		TIF.Prof.End()
	end

	self:NextThink(now)
	return true
end

local cvHead = CreateConVar("tif_headshot_mult", "2.5", FCVAR_ARCHIVE, "Damage multiplier for hits to a soldier's head")

function ENT:OnTraceAttack(dmg, dir, tr)
	local hg = tr.HitGroup
	self.tifLastHitGroup = hg
	if hg == HITGROUP_HEAD then dmg:ScaleDamage(cvHead:GetFloat())
	elseif hg == HITGROUP_LEFTARM or hg == HITGROUP_RIGHTARM or hg == HITGROUP_LEFTLEG or hg == HITGROUP_RIGHTLEG then
		dmg:ScaleDamage(0.75)
	end
end

function ENT:OnInjured(dmg)
	if self.tifDead then return end
	local att = dmg:GetAttacker()
	TIF.Perception.OnHurt(self, att)
	TIF.Supp.Add(self, 0.35, IsValid(att) and att:GetPos() or nil, att)
	if TIF.Morale then
		TIF.Morale.OnHurt(self, dmg:GetDamage())
	end

	local friendly = IsValid(att) and att ~= self and (att.TIFSoldier or att:IsPlayer()) and TIF.Relation(self, att) == TIF.REL_ALLY
	local crit = TIF.Chatter and self:Health() > 0 and self:Health() < self:GetMaxHealth() * TIF.Chatter.CRITICAL
	if friendly then TIF.Say(self, "friendly_fire", 0.9)
	elseif crit and not self.tifSaidCritical then
		self.tifSaidCritical = true
		TIF.Say(self, "critical", 0.9)
	else
		TIF.Say(self, "pain", 0.7)
	end

	local dir = dmg:GetDamageForce()
	if dir:LengthSqr() < 1 and IsValid(att) then
		dir = self:GetPos() - att:GetPos()
	end

	dir:Normalize()
	self:SetTIFHitDir(dir)
	self:SetTIFHitTime(CurTime())

	if TIF.HitsMW and not self.tifNoDeathClip and self:Health() > 0 then
		pcall(TIF.HitsMW.Pain, self, dmg)
	end
end

local CLIP_DEATH_HOLD = 0.2
function ENT:OnKilled(dmg)
	if self.tifDead then return end
	self.tifDead = true

	if TIF.Morale then
		pcall(TIF.Morale.OnDeath, self, dmg:GetAttacker())
	end
	TIF.Unregister(self)
	TIF.Cover.Release(self)
	TIF.Squad.Remove(self)
	TIF.Say(self, "death")

	for _, ally in ipairs(TIF.Soldiers) do
		if IsValid(ally) and ally:GetTIFFaction() == self:GetTIFFaction() and ally:GetPos():DistToSqr(self:GetPos()) < 1200 * 1200 then
			TIF.Perception.Stimulus(ally, self:GetPos(), "man_down", CurTime())
			if math.random() < 0.5 then
				TIF.Say(ally, "man_down")
			end
			break
		end
	end

	hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())

	hook.Run("TIF_SoldierKilled", self, dmg:GetAttacker())
	local ok, err = pcall(self.TIFDropWeapon, self)
	if not ok then
		TIF.Error("Weapon drop failed: ", tostring(err))
	end

	if self.tifKnock and TIF.HitsMW and TIF.HitsMW.KnockDeath and TIF.HitsMW.KnockDeath(self) then
		self:SetNoDraw(true)
		self:SetNotSolid(true)
		SafeRemoveEntityDelayed(self, 0)
		return
	end

	local hit = { pos = dmg:GetDamagePosition(), force = dmg:GetDamageForce() }

	local act = self.tifNoDeathClip and self.tifAct
	local seq = act and act.clip and act.clip.seq and self:LookupSequence(act.clip.seq)
	if seq and seq >= 0 and TIF.HitsMW and TIF.HitsMW.DyingThink then
		local now = CurTime()
		self.tifDying = { untilT = now + CLIP_DEATH_HOLD, prev = {}, prevT = now, seq = seq, t0 = act.t0 or now,
			dur = act.dur or 1, clipDeath = true }
		self:SetNW2Bool("tif_dying", true)
		self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		self.tifDeathHit = hit
		timer.Simple(3, function() if IsValid(self) and self.tifDying then self.tifDying = nil self:TIFFinishDeath({}) end end)
		return
	end

	local dying = false
	if TIF.HitsMW then
		ok, dying = pcall(TIF.HitsMW.Death, self, dmg)
		dying = ok and dying
	end

	if dying then
		self.tifDeathHit = hit

		local safety = (self.tifDying and self.tifDying.chain) and 20 or 6
		timer.Simple(safety, function() if IsValid(self) and self.tifDying then self.tifDying = nil self:TIFFinishDeath({}) end end)
		return
	end

	self.tifDeathHit = hit
	self:TIFFinishDeath(nil)
end

function ENT:TIFFinishDeath(boneVel)
	local ok, err = pcall(self.TIFMakeCorpse, self, self.tifDeathHit, boneVel)
	if not ok then
		TIF.Error("Corpse failed: ", tostring(err))
	end

	self:SetNoDraw(true)
	self:SetNotSolid(true)
	SafeRemoveEntityDelayed(self, 0)
end

local cvCorpse = CreateConVar("tif_corpse_time", "60", FCVAR_ARCHIVE, "Seconds soldier bodies and dropped guns stay (0 = until cleanup)")

local CORPSE_FALLBACK = { "models/humans/group03/male_07.mdl", "models/humans/group01/male_07.mdl", "models/kleiner.mdl" }
local warnedNoRag = {}
local function fallback_ragdoll()
	for _, m in ipairs(CORPSE_FALLBACK) do
		if util.IsValidRagdoll(m) then return m end
	end
	return nil
end

local BONE_VEL_MAX = 480
local CORPSE_SETTLE, SETTLE_ANG_DAMP = 0.45, 6
local floorOut = {}
local floorTr = { mask = MASK_SOLID_BRUSHONLY, output = floorOut }
local BONE_M = Matrix()

local function settle_corpse(rag, clampUp)
	if not IsValid(rag) then return end
	local n = rag:GetPhysicsObjectCount()
	local lift = 0
	for i = 0, n - 1 do
		local phys = rag:GetPhysicsObjectNum(i)

		if IsValid(phys) and bit.band(util.PointContents(phys:GetPos()), CONTENTS_SOLID) ~= 0 then
			local p = phys:GetPos()
			floorTr.start, floorTr.endpos = p + Vector(0, 0, 30), p
			local tr = util.TraceLine(floorTr)

			if tr.Hit and not tr.StartSolid and tr.HitNormal.z > 0.6 and tr.HitPos.z > p.z + 0.5 then
				lift = math.max(lift, tr.HitPos.z + 2 - p.z)
			end
		end
	end

	lift = math.min(lift, 24)
	rag.tifDamp = rag.tifDamp or {}
	for i = 0, n - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		if IsValid(phys) then
			if lift > 0.5 then
				phys:SetPos(phys:GetPos() + Vector(0, 0, lift))
			end
			if clampUp then
				local v = phys:GetVelocity()
				if v.z > 160 then
					phys:SetVelocity(Vector(v.x, v.y, 160))
				end
			end
			if not rag.tifDamp[i] then
				local lin, ang = phys:GetDamping()
				rag.tifDamp[i] = { lin, ang }
			end
			phys:SetDamping(rag.tifDamp[i][1], math.max(rag.tifDamp[i][2], SETTLE_ANG_DAMP))
		end
	end

	timer.Create("tif_settle_" .. rag:EntIndex(), CORPSE_SETTLE, 1, function()
		if not IsValid(rag) or not rag.tifDamp then return end
		for i, d in pairs(rag.tifDamp) do
			local phys = rag:GetPhysicsObjectNum(i)
			if IsValid(phys) then
				phys:SetDamping(d[1], d[2])
			end
		end
	end)
end
ENT.TIFSettleCorpse = settle_corpse

function ENT:TIFMakeCorpse(hit, boneVel)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end

	local vis = self:GetTIFVisual()
	local vbHost = TIF.GTG.IsVB(self.tifHostId)
	local own = vbHost and vis ~= "" and util.IsValidRagdoll(vis)

	local stand = vbHost and not own and fallback_ragdoll() or nil
	if stand and not warnedNoRag[vis] then
		warnedNoRag[vis] = true
		TIF.Warn("Faction model has no ragdoll physics, its corpses use a stand-in ragdoll: ", tostring(vis))
	end

	local restOff = own and TIF.Modular and TIF.Modular.NeedsRetarget(vis) and TIF.Modular.RestOffsets(self:GetModel(), vis) or nil
	rag:SetModel(own and vis or stand or self:GetModel())

	rag:SetNW2String("tif_parts", self:GetNW2String("tif_parts", ""))
	rag:SetPos(self:GetPos())
	rag:SetAngles(self:GetAngles())
	if own then
		rag:SetSkin(self:GetTIFSkin())
		for i, d in ipairs(string.Explode(" ", self:GetTIFBodygroups())) do
			rag:SetBodygroup(i - 1, tonumber(d) or 0)
		end
	else
		rag:SetNW2String("tif_vis", vis)
		rag:SetNW2Int("tif_skin", self:GetTIFSkin())
		rag:SetNW2String("tif_bg", self:GetTIFBodygroups())

		if stand then
			rag:SetNW2Bool("tif_vb_dress", true)
		end
	end

	local byName = own or stand ~= nil
	rag:Spawn()
	rag:Activate()
	rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

	local act = not boneVel and self.tifAct
	if act and act.clip and act.clip.seq then
		local seq = self:LookupSequence(act.clip.seq)
		if seq and seq >= 0 then
			self:ResetSequence(seq)
			self:SetCycle(math.Clamp((CurTime() - (act.t0 or CurTime())) / math.max(0.05, act.dur or 1), 0, 1))
			self:SetPlaybackRate(0)

			if self.InvalidateBoneCache then
				self:InvalidateBoneCache()
			end
			if self.SetupBones then
				self:SetupBones()
			end
		end
	end

	local vel = self.loco:GetVelocity()
	local hitPos = hit and hit.pos or self:WorldSpaceCenter()
	local force = hit and hit.force or Vector()
	if force:Length() > 9000 then
		force = force:GetNormalized() * 9000
	end

	if boneVel and not (hit and hit.fresh) then
		force = force * 0.25
	end
	local nearest, nearestD
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local rb = rag:TranslatePhysBoneToBone(i)

		local hb = byName and self:LookupBone(rag:GetBoneName(rb) or "") or (not byName and rb) or nil
		local m = hb and TIF.CopyBone(self, hb, BONE_M)
		if IsValid(phys) and m then
			phys:SetPos(m:GetTranslation())
			local off = restOff and restOff[string.lower(rag:GetBoneName(rb) or "")]
			if off then
				local r = Matrix()
				r:SetAngles(m:GetAngles())
				phys:SetAngles((r * off):GetAngles())
			else
				phys:SetAngles(m:GetAngles())
			end
			local bv = boneVel and hb and boneVel[hb]
			if bv and bv:LengthSqr() > BONE_VEL_MAX * BONE_VEL_MAX then
				bv = bv:GetNormalized() * BONE_VEL_MAX
			end
			if bv then
				phys:SetVelocity(bv)
			elseif hit and hit.posed then

				phys:SetVelocity(vel)
			else

				phys:SetVelocity(vel + VectorRand() * 45)
				phys:AddAngleVelocity(VectorRand() * 160)
			end
			local d = m:GetTranslation():DistToSqr(hitPos)
			if not nearestD or d < nearestD then
				nearest, nearestD = phys, d
			end
		end
	end

	if force:LengthSqr() > 1 then
		if boneVel then
			if nearest then
				nearest:ApplyForceCenter(force * 0.4)
			end
		else

			local n = rag:GetPhysicsObjectCount()
			for i = 0, n - 1 do
				local phys = rag:GetPhysicsObjectNum(i)
				if IsValid(phys) then
					phys:ApplyForceCenter(force * 0.4 * 0.5 / math.max(1, n))
				end
			end
			if nearest then
				nearest:ApplyForceCenter(force * 0.4 * 0.5)
			end
		end
	end

	settle_corpse(rag, boneVel ~= nil)

	if TIF.Foley and TIF.Foley.CorpseSounds then
		TIF.Foley.CorpseSounds(rag)
	end
	local t = cvCorpse:GetFloat()
	if t > 0 then
		SafeRemoveEntityDelayed(rag, t)
	end

	return rag
end

function ENT:TIFDropWeapon(which)
	local w = which or self.tifWep
	local stored = w and TIF.GTG.Stored(w.class)
	local model = stored and stored.WorldModel
	local def = w and w.def
	local spent = def and def.disposable and def.spentModel and (w.rockets or 0) <= 0
	if spent then
		model = def.spentModel
	end

	if not model or model == "" then return end
	local hand = self:LookupBone("PH_R_Hand") or self:LookupBone("ValveBiped.Bip01_R_Hand")
	local m = hand and TIF.CopyBone(self, hand, BONE_M)
	local prop = ents.Create("prop_physics")
	if not IsValid(prop) then return end
	prop:SetModel(model)
	prop:SetPos(m and m:GetTranslation() or self:WorldSpaceCenter())

	if m and string.sub(model, 1, 16) == "models/tif_guns/" then
		m = m * Matrix({ { 0, 1, 0, 0 }, { -1, 0, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } })
	end
	prop:SetAngles(m and m:GetAngles() or self:GetAngles())
	prop:Spawn()
	prop:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	if not IsValid(prop:GetPhysicsObject()) then
		prop:Remove()
		return
	end

	local po = prop:GetPhysicsObject()
	po:SetVelocity(self.loco:GetVelocity())
	if spent then
		prop.tifSpent = true
		po:SetVelocity(self.loco:GetVelocity() + self:GetRight() * 45 - Vector(0, 0, 30))
		po:AddAngleVelocity(Vector(math.Rand(-60, 60), math.Rand(-60, 60), math.Rand(-120, 120)))
	end

	if TIF.Foley and TIF.Foley.GunDropSounds then
		TIF.Foley.GunDropSounds(prop, TIF.GTG.WeaponKind(w.class))
	end
	local t = cvCorpse:GetFloat()
	if t > 0 then
		SafeRemoveEntityDelayed(prop, t)
	end
end

function ENT:OnRemove()
	TIF.Unregister(self)
	TIF.Cover.Release(self)
	TIF.Squad.Remove(self)
end

function ENT:OnStuck()
	self.loco:ClearStuck()
end
