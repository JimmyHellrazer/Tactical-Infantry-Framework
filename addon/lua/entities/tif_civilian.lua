AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "Civilian"
ENT.Category = "Tactical Infantry"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true
ENT.TIFCivilian = true

local HOST = "models/tif_mw/mw_male.mdl"

local function apply_look(e, seed)
	if not IsValid(e) or not seed or seed <= 0 then return end
	local skins = e:SkinCount() or 1
	if skins > 1 then e:SetSkin(seed % skins) end
	for i = 0, (e:GetNumBodyGroups() or 1) - 1 do
		local n = e:GetBodygroupCount(i) or 1
		if n > 1 then e:SetBodygroup(i, math.floor(seed / (i + 1) * 7919) % n) end
	end
end

if CLIENT then

	function ENT:Initialize()
		self:DrawShadow(false)
	end

	local function follower(self)
		local vis = self:GetNW2String("tif_civ_vis", "")
		if vis == "" or self:GetModel() ~= HOST then return nil end
		local f = self.civFollower
		if IsValid(f) and self.civFollowerVis == vis then
			if f:GetParent() ~= self then
				f:SetParent(self)
				f:AddEffects(EF_BONEMERGE)
			end
			return f
		end
		if IsValid(f) then f:Remove() end
		f = ClientsideModel(vis, RENDERGROUP_OPAQUE)
		if not IsValid(f) then return nil end
		f:SetParent(self)
		f:AddEffects(EF_BONEMERGE)
		f:AddEffects(EF_BONEMERGE_FASTCULL)
		apply_look(f, self:GetNW2Int("tif_civ_seed", 0))
		f:SetNoDraw(true)
		self.civFollower, self.civFollowerVis = f, vis
		return f
	end

	function ENT:Draw()
		local f = follower(self)
		if f then

			self:SetupBones()
			f:DrawModel()
		else
			self:DrawModel()
		end
	end

	function ENT:OnRemove()
		if IsValid(self.civFollower) then self.civFollower:Remove() end
	end
	return
end

local function C() return TIF.Civ end

function ENT:Initialize()
	local Civ = C()
	local vis = self.civModel or (Civ and Civ.PickModel()) or "models/humans/group01/male_01.mdl"
	self.mw = util.IsValidModel(HOST) and TIF.GTG and TIF.GTG.Clip("civ_walk", "mw_male") ~= nil
	self.civSeed = math.random(1, 1000000)
	self:SetNW2Int("tif_civ_seed", self.civSeed)
	if self.mw then
		self:SetModel(HOST)
		self:SetNW2String("tif_civ_vis", vis)
	else
		self:SetModel(util.IsValidModel(vis) and vis or "models/humans/group01/male_01.mdl")
		apply_look(self, self.civSeed)
	end
	self.civVis = vis

	self:SetHealth(1)
	self:SetMaxHealth(1)
	self:SetCollisionBounds(Vector(-12, -12, 0), Vector(12, 12, 70))
	self:SetUseType(SIMPLE_USE)
	self.loco:SetStepHeight(20)
	self.loco:SetJumpHeight(40)
	self.loco:SetDeathDropHeight(300)
	self.loco:SetAcceleration(500)
	self.state = self.state or "wander"
	self.home = self.home or self:GetPos()
	self.homeRadius = self.homeRadius or 1200
	self.fear = 0

	self.var = math.random(1, 99)
	if Civ then Civ.Register(self) end
end

function ENT:OnRemove()
	local Civ = C()
	if Civ then Civ.Unregister(self) end
end

function ENT:KeyValue(k, v)
	if k == "tif_civ_noleave" then self.noLeave = v == "1"
	elseif k == "tif_civ_crowd" then self.civCrowd = tonumber(v) end
end

function ENT:Think()
	local n = self.civCrowd
	if n and n > 1 then
		self.civCrowd = nil
		local Civ = C()
		for _ = 2, n do
			local p = Civ and Civ.RandomPoint(self:GetPos(), 350)
			if p then Civ.Spawn(p, { home = self:GetPos(), radius = 900 }) end
		end
	end
end

local function clip(role) return TIF.GTG and TIF.GTG.Clip(role, "mw_male") end

function ENT:Variant(prefix, max)
	for i = 0, max - 1 do
		local n = (self.var + i) % max + 1
		if clip(prefix .. n) then return prefix .. n end
	end
	return nil
end

function ENT:Play(role, rate)
	local c = clip(role)
	if not c then return 0 end
	self.civClip = c
	local seq = self:LookupSequence(c.seq)
	if seq and seq >= 0 and (self:GetSequence() ~= seq or not c.loop and self.civRole ~= role) then
		self:ResetSequence(seq)
		self:SetCycle(0)
	end
	self.civRole = role
	self:SetPlaybackRate(rate or 1)
	return c.dur / (rate or 1)
end

function ENT:ActFallback(act)
	if self.curAct == act then return end
	self.curAct = act
	local seq = self:SelectWeightedSequence(act)
	self:StartActivity((seq and seq > 0) and act or ACT_IDLE)
end

function ENT:FromPool(pool)
	for i = 0, #pool - 1 do
		local r = pool[(self.var + i) % #pool + 1]
		if clip(r) then return r end
	end
	return nil
end

local WALKS = { "civ_walk", "civ_walk_1", "civ_walk_2", "civ_walk_3", "civ_walk_4" }

function ENT:MoveClip(kind)
	if kind == "wounded" then return "civ_wounded_run" end
	if kind == "duck" then return clip("civ_duck_run") and "civ_duck_run" or self:MoveClip("panic_run") end
	if kind == "panic_run" then return self:Variant("civ_prun_", 9) or "civ_run_1" end
	if kind == "panic_jog" then return self:Variant("civ_pjog_", 9) or "civ_jog" end
	if kind == "panic_walk" then return self:Variant("civ_pwalk_", 6) or "civ_walk" end
	if kind == "jog" then return "civ_jog" end
	if kind == "run" then return (self.var % 2 == 0) and "civ_run_2" or "civ_run_1" end
	if (self.fear or 0) > 0.05 then
		local w = self:Variant("civ_wwalk_", 4)
		if w then return w end
	end
	return self:FromPool(WALKS) or "civ_walk"
end

function ENT:FleeKind(default)
	local d = self.dangerPos
	if self.mw and d and (self.fear or 0) > 0.85 and self.var % 3 == 0 and clip("civ_duck_run")
		and d:DistToSqr(self:GetPos()) < 700 * 700 then
		return "duck"
	end
	return default
end

local FALLBACK_ACT = { walk = ACT_WALK, panic_walk = ACT_WALK, wounded = ACT_WALK }

function ENT:BodyUpdate()
	if self.mw then

		local c = self.civClip
		if c and c.loop and (c.speed or 0) > 1 then
			local v = self.loco:GetVelocity():Length2D()
			self:SetPlaybackRate(math.Clamp(v / c.speed, 0.4, 1.6))
		end
		self:FrameAdvance()

		if c and not c.loop and not self.civOneShot and self:GetCycle() >= 0.99 and self.civRole ~= self.civHoldLast then
			self:SetCycle(0)
		end
	else
		self:BodyMoveXY()
	end
end

function ENT:GoTo(pos, kind, keepState, timeout)
	local path = Path("Follow")
	path:SetMinLookAheadDistance(200)
	path:SetGoalTolerance(40)
	if not path:Compute(self, pos) then return "failed" end
	local role = self:MoveClip(kind)
	local c = clip(role)
	local speed = (c and c.speed and c.speed > 20) and c.speed or (kind == "walk" and 70 or 220)
	self.loco:SetDesiredSpeed(speed)
	if self.mw then self:Play(role) else self:ActFallback(FALLBACK_ACT[kind] or ACT_RUN) end
	local st = self.state
	local deadline = CurTime() + (timeout or 40)

	local Crowd = TIF.Crowd
	local watch = { t = CurTime(), pos = self:GetPos() }
	local stuckN, side = 0, nil
	while path:IsValid() and CurTime() < deadline do
		if self.state ~= st and not keepState then return "interrupted" end
		if self.gone or self.tifHeld then return "interrupted" end
		local now = CurTime()
		if side then
			self.loco:SetDesiredSpeed(speed)
			self.loco:Approach(side.pos, 1)
			if now > side.untilT or self:GetPos():DistToSqr(side.pos) < 16 * 16 then
				side = nil
				watch = { t = now, pos = self:GetPos() }
				if not path:Compute(self, pos) then return "failed" end
			end
		else
			local want, steer = speed, nil
			if Crowd and Crowd.Steer then
				local fwd = self.loco:GetVelocity()
				fwd.z = 0
				if fwd:LengthSqr() < 100 then fwd = pos - self:GetPos() fwd.z = 0 end
				if fwd:LengthSqr() > 1 then
					fwd:Normalize()
					want, steer = Crowd.Steer(self, fwd, speed, pos, now)
				end
			end
			self.loco:SetDesiredSpeed(want)
			path:Update(self)
			if steer then self.loco:Approach(steer, Crowd.WEIGHT) end
			if Crowd and Crowd.On() and now - watch.t >= self.STUCK_T then
				local moved = (self:GetPos() - watch.pos):Length2D()
				local expect = want * (now - watch.t)
				watch = { t = now, pos = self:GetPos() }
				if want >= 30 and moved < math.max(6, expect * 0.25) then
					stuckN = stuckN + 1
					if stuckN >= self.STUCK_MAX then self:HandleStuck() return "stuck" end
					local f = self.loco:GetVelocity()
					f.z = 0
					if f:LengthSqr() < 1 then f = pos - self:GetPos() f.z = 0 end
					if f:LengthSqr() < 1 then f = self:GetForward() end
					f:Normalize()
					local p = Crowd.SidePoint(self, f, 44)
					if p then side = { pos = p, untilT = now + self.CIV_SIDE_T } end
				else
					stuckN = 0
				end
			end
		end
		if self.loco:IsStuck() then
			self:HandleStuck()
			return "stuck"
		end
		coroutine.yield()
	end
	return "ok"
end

ENT.STUCK_T, ENT.STUCK_MAX, ENT.CIV_SIDE_T = 0.6, 3, 0.8

function ENT:Wait(t, keepState)
	local st = self.state
	local untilT = CurTime() + t
	while CurTime() < untilT do
		if (self.state ~= st and not keepState) or self.gone or self.tifHeld then return false end
		if st == "wander" or st == "talk" then self:Dodge() end
		coroutine.yield()
	end
	return true
end

local function numpad(rel)
	local a = math.abs(rel)
	if a < 22.5 then return "8" elseif a > 157.5 then return "2" end
	local left = rel > 0
	if a < 67.5 then return left and "7" or "9" end
	if a < 112.5 then return left and "4" or "6" end
	return left and "1" or "3"
end
ENT.Numpad = numpad

local UP = Vector(0, 0, 18)

local function hull(self)
	local mins, maxs = self:GetCollisionBounds()
	return Vector(mins.x, mins.y, 0), Vector(maxs.x, maxs.y, math.max(20, maxs.z - 18))
end

function ENT:RoomFor(c)
	local m = c and c.move
	if not m or math.abs(m[1]) + math.abs(m[2]) < 4 then return true end
	local p, rad = self:GetPos(), math.rad(self:GetAngles().y)
	local cs, sn = math.cos(rad), math.sin(rad)
	local e = Vector(p.x + m[1] * cs - m[2] * sn, p.y + m[1] * sn + m[2] * cs, p.z)
	local mins, maxs = hull(self)
	local t = util.TraceHull({ start = p + UP, endpos = e + UP, mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = self })
	if t.Hit then return false end
	return util.TraceLine({ start = e + UP, endpos = e - Vector(0, 0, 60), mask = MASK_NPCSOLID_BRUSHONLY }).Hit
end

function ENT:OneShot(role, keepState)
	if not self.mw or not clip(role) then return false end
	local c = clip(role)
	self.civOneShot = true
	local d = self:Play(role)
	local p0, y0 = self:GetPos(), self:GetAngles().y
	local rad = math.rad(y0)
	local cs, sn = math.cos(rad), math.sin(rad)
	local mins, maxs = hull(self)
	local t0 = CurTime()
	local st = self.state
	self.loco:SetDesiredSpeed(0)
	local done = true
	while CurTime() - t0 < d do
		if (self.state ~= st and not keepState) or self.gone or self.tifHeld then done = false break end
		local u = math.Clamp((CurTime() - t0) / d, 0, 1)
		local x, y, r = TIF.Action.RootAt(c, u)
		if math.abs(x) + math.abs(y) > 0.5 or math.abs(r) > 0.5 then
			local cur = self:GetPos()
			local np = Vector(p0.x + x * cs - y * sn, p0.y + x * sn + y * cs, cur.z)
			if np:DistToSqr(cur) > 0.01 then
				local t = util.TraceHull({ start = cur + UP, endpos = np + UP, mins = mins, maxs = maxs, mask = MASK_NPCSOLID, filter = self })
				local g = not t.Hit and util.TraceLine({ start = np + UP, endpos = np - Vector(0, 0, 40), mask = MASK_NPCSOLID_BRUSHONLY })

				if t.Hit and t.StartSolid then g = util.TraceLine({ start = np + UP, endpos = np - Vector(0, 0, 40), mask = MASK_NPCSOLID_BRUSHONLY }) end
				if not (g and g.Hit) then done = false break end
				self:SetPos(Vector(np.x, np.y, g.HitPos.z))
			end
			self:SetAngles(Angle(0, y0 + r, 0))
		end
		coroutine.yield()
	end

	if not self.tifHeld then self.civOneShot = nil end
	return done
end

local CALM = { "civ_idle_1", "civ_stand_1", "civ_stand_2", "civ_stand_3", "civ_stand_4", "civ_stand_5", "civ_stand_6", "civ_stand_7" }
function ENT:Idle()
	if self.mw then
		local f = self.fear or 0
		local r = (f >= 0.5 and self:Variant("civ_panic_idle_", 12)) or (f > 0.05 and self:Variant("civ_scared_idle_", 7))
			or self:FromPool(CALM)
		self:Play(r or "civ_idle_1")
	else
		self:ActFallback(ACT_IDLE)
	end
	self.loco:SetDesiredSpeed(0)
end

function ENT:Dodge()
	if not self.mw or self.civOneShot then return false end
	local now = CurTime()
	if now < (self.nextDodgeCheck or 0) then return false end
	self.nextDodgeCheck = now + 0.2
	if now < (self.nextDodge or 0) then return false end
	local pos = self:GetPos()
	local function try(m)
		local off = pos - m:GetPos()
		off.z = 0
		local d = off:Length()
		if d > 110 or d < 1 then return false end
		local v = (m.loco and m.loco:GetVelocity()) or m:GetVelocity()
		v = Vector(v.x, v.y, 0)
		local sp = v:Length()
		if sp < 40 or v:Dot(off) / (sp * d) < 0.7 then return false end
		local side = Vector(v.y, -v.x, 0)
		if side:Dot(off) < 0 then side = side * -1 end
		local n = numpad(math.AngleDifference(side:Angle().y, self:GetAngles().y))
		n = (n == "7" or n == "9") and "8" or ((n == "1" or n == "3") and "2" or n)
		local role = ((self.fear or 0) > 0.3 and clip("civ_pevade_" .. n)) and ("civ_pevade_" .. n) or ("civ_evade_" .. n)
		if not self:RoomFor(clip(role)) then return false end
		self.nextDodge = now + 2
		local prev, cyc = self.civRole, self:GetCycle()
		self:OneShot(role)
		self.nextDodge = CurTime() + 2
		if prev and not self.gone then
			self:Play(prev)
			if clip(prev) and clip(prev).loop then self:SetCycle(cyc) end
		end
		return true
	end
	for _, ply in ipairs(player.GetHumans()) do
		if ply:Alive() and try(ply) then return true end
	end
	for _, s in ipairs(TIF.Soldiers or {}) do
		if IsValid(s) and not s.tifDead and try(s) then return true end
	end
	return false
end

function ENT:React()
	local pos = self.reactAt
	self.reactAt = nil
	if not (self.mw and pos) then return end
	local rel = math.AngleDifference((pos - self:GetPos()):Angle().y, self:GetAngles().y)
	local n = numpad(rel)
	local startle = "civ_startle_" .. (n == "2" and (rel > 0 and "2l" or "2r") or n)
	local f = self.fear or 0
	if pos:DistToSqr(self:GetPos()) > 1200 * 1200 and f < 0.5 then
		self:OneShot(startle, true)
		return
	end
	local v = (self.var % 2) + 1
	local sizes = f >= 0.85 and { "lg1", "md" .. v, "sm" .. v } or (f >= 0.5 and { "md" .. v, "sm" .. v } or { "sm" .. v })
	for _, sz in ipairs(sizes) do
		local role = "civ_react_" .. sz .. "_" .. n
		local c = clip(role)
		if c and self:RoomFor(c) then
			self:OneShot(role, true)
			return
		end
	end
	if self:RoomFor(clip(startle)) then self:OneShot(startle, true) end
end

function ENT:FaceTo(pos)
	local yaw = (pos - self:GetPos()):Angle().y
	self:SetAngles(Angle(0, yaw, 0))
end

function ENT:SetState(st)
	if self.state == st then return end

	if self.tifHeld and st ~= "held" then return end
	self.state = st
	self:SetNW2String("tif_civ_state", st)
end

function ENT:Scare(pos, amount)
	if self.gone then return end
	local Civ = C()
	local now = CurTime()
	self.fear = math.min(1, (self.fear or 0) + (amount or 0.5))
	self.dangerPos = pos
	self.scaredAt = now

	if self.state == "held" then return end

	if not self.decided and self.fear >= 0.2 then
		self.decided = true
		local share = (Civ and Civ.LEAVE_SHARE) or 0.8
		if self.shelter or self.noLeave then share = 0 end
		if math.random() < share then self.leaving = true end
	end

	if self.state == "wander" or self.state == "talk" then
		self.reactAt = pos
	end
	if self.leaving then
		if self.state ~= "leave" then self:SetState("leave") end
	elseif self.state ~= "flee" and self.state ~= "hide" and self.state ~= "evacuate" then
		self:SetState("flee")
	elseif self.state == "hide" and pos:DistToSqr(self:GetPos()) < ((Civ and Civ.TOO_CLOSE) or 700) ^ 2
		and now > (self.nextRelocate or 0) and not self.shelter then

		self.nextRelocate = now + 8
		self.relocations = (self.relocations or 0) + 1
		if not self.noLeave and math.random() < 0.5 * self.relocations then
			self.leaving = true
			self:SetState("leave")
		else
			self:SetState("flee")
		end
	end
end

local SCARED = { "civ_cower_1", "civ_cower_2", "civ_cower_3", "civ_kneel_2", "civ_kneel_4", "civ_kneel_5",
	"chain_1", "chain_2", "chain_3" }

function ENT:ScaredPose()
	if (self.fear or 0) >= 0.9 and self.var % 2 == 0 then
		local p = self:Variant("civ_prone_", 6)
		if p then return p end
	end
	for i = 0, #SCARED - 1 do
		local r = SCARED[(self.var + i) % #SCARED + 1]
		local ch = string.match(r, "^chain_(%d)$")
		if ch then
			if clip("civ_tocower_" .. ch) and clip("civ_cowering_" .. ch) then return r end
		elseif clip(r) then
			return r
		end
	end
	return "civ_idle_1"
end

function ENT:Uncower()
	local ch = self.civChain
	if not ch then return end
	self.civChain = nil
	self:OneShot("civ_uncower_" .. ch, true)
end

function ENT:RunBehaviour()
	while true do
		local Civ = C()
		local st = self.state
		if self.gone then
			coroutine.yield()
		elseif st == "wander" then

			if (self.fear or 0) > 0 and CurTime() - (self.scaredAt or 0) > 45 then self.fear = 0 end
			local p = Civ and Civ.RandomPoint(self.home, self.homeRadius)
			if p and math.random() < 0.65 then self:GoTo(p, "walk") end
			self:Idle()

			if self.mw and (self.fear or 0) <= 0.05 and math.random() < 0.35 and self:Wait(math.Rand(2, 5))
				and self:OneShot("civ_idle_" .. math.random(2, 6)) then
				self:Idle()
			end
			self:Wait(math.Rand(4, 14))
		elseif st == "talk" then

			local chat = self.mw and (self.fear or 0) <= 0.05 and self:Variant("civ_chat_", 6)
			if chat then
				self:Play(chat)
				self:SetCycle(math.Rand(0, 0.9))
				self.loco:SetDesiredSpeed(0)
			else
				self:Idle()
			end
			if IsValid(self.partner) then self:FaceTo(self.partner:GetPos()) end
			self:Wait(math.Rand(8, 18))
			if self.state == "talk" then self:SetState("wander") end
		elseif st == "flee" then
			self:React()

			local spot = Civ and Civ.HideSpot(self, self.dangerPos or self:GetPos())
			self.hideSpot = spot
			if spot then self:GoTo(spot.pos, self:FleeKind(self.fear > 0.6 and "panic_run" or "panic_jog"), true, 25) end
			self:SetState("hide")
		elseif st == "hide" then
			self:Hide(Civ)
		elseif st == "leave" then
			self:React()

			local p = Civ and Civ.LeavePoint(self, self.dangerPos or self:GetPos())
			if p then
				local r = self:GoTo(p, "panic_run", true, 60)
				if r ~= "ok" then self.leaveTries = (self.leaveTries or 0) + 1 end
			else
				self.leaveTries = (self.leaveTries or 0) + 1
			end

			if (self.leaveTries or 0) >= 2 then self.leaving = false self:SetState("hide") end
			self:Idle()
			self:Wait(0.5, true)
		elseif st == "evacuate" then
			if self.evacPos then
				local r = self:GoTo(self.evacPos, "jog")
				if r == "ok" or self:GetPos():DistToSqr(self.evacPos) < 300 * 300 then
					self.evacuated = true
					hook.Run("TIF_CivilianLeft", self)
					self:Remove()
					return
				end
			end
			self:SetState("wander")
		elseif st == "injured" then

			self:SetState("hide")
		elseif st == "held" then

			self.loco:SetDesiredSpeed(0)
			if not self.tifHeld then self:SetState("flee") end
		else
			self:Wait(1)
		end
		coroutine.yield()
	end
end

function ENT:BeckonOthers(Civ)
	local now = CurTime()
	if now < (self.nextBeckon or 0) then return end
	self.nextBeckon = now + 1
	local pos = self:GetPos()
	for _, o in ipairs(Civ.List()) do
		if o ~= self and (o.state == "flee" or o.state == "leave") and not o.gone then
			local d2 = o:GetPos():DistToSqr(pos)
			if d2 < 700 * 700 and d2 > 150 * 150 then
				self.nextBeckon = now + 15
				local rel = math.AngleDifference((o:GetPos() - pos):Angle().y, self:GetAngles().y)
				return self:OneShot("civ_beckon_" .. numpad(rel))
			end
		end
	end
end

function ENT:Hide(Civ)
	local spot = self.hideSpot
	local role, wall
	if self.mw then

		if self.hideFor ~= spot or not self.hideRole then
			self:Uncower()
			self.hideFor = spot
			if spot and spot.wall then self.hideRole = self:Variant("civ_wall_" .. spot.wall .. "_", 4) else self.hideRole = nil end
			self.hideRole = self.hideRole or self:ScaredPose()
		end
		role = self.hideRole
		wall = spot and spot.wall and string.find(role, "^civ_wall_") ~= nil
		if spot and spot.yaw then self:SetAngles(Angle(0, spot.yaw, 0)) end
		local ch = string.match(role, "^chain_(%d)$")
		if ch then
			if self.civChain ~= ch then
				self:Uncower()
				self:OneShot("civ_tocower_" .. ch, true)
				self.civChain = ch
			end
			role = "civ_cowering_" .. ch
		end
		self:Play(role)
	else
		self:ActFallback(ACT_COWER or ACT_CROUCH)
	end
	self.loco:SetDesiredSpeed(0)
	local function leaving()

		self.hideRole, self.hideFor = nil, nil
		if not self.gone then self:Uncower() end
	end
	local untilT = CurTime() + math.Rand(6, 12)
	while CurTime() < untilT do
		if self.state ~= "hide" or self.gone or self.tifHeld then return leaving() end
		local h = self.mw and self.dangerPos and Civ and CurTime() - (self.scaredAt or 0) < 60 and Civ.Helper(self)
		local prone = string.find(role or "", "^civ_prone_") ~= nil
		if h and h ~= self.pointedFor and not prone then
			self.pointedFor = h

			local ch = self.civChain
			self:Uncower()
			local rel = math.AngleDifference((self.dangerPos - self:GetPos()):Angle().y, self:GetAngles().y)
			self:OneShot("civ_point_" .. numpad(rel))
			if ch and self.state == "hide" then
				self:OneShot("civ_tocower_" .. ch, true)
				self.civChain = ch
			end
			self:Play(role)
		elseif wall and self:BeckonOthers(Civ) then
			self:Play(role)
		end
		coroutine.yield()
	end

	if CurTime() - (self.scaredAt or 0) > 40 then
		self.fear = math.max(0, (self.fear or 0) - 0.5)
		if self.fear <= 0.2 and not self.shelter then
			self:SetState("wander")
			leaving()
		end
	end
end

function ENT:OnInjured(dmg)
	local att = dmg:GetAttacker()
	hook.Run("TIF_CivilianHurt", self, dmg, att)

	if self:Health() - dmg:GetDamage() > 0 then self:Scare(dmg:GetDamagePosition(), 1) end
end

function ENT:OnKilled(dmg)
	local att = dmg:GetAttacker()
	hook.Run("TIF_CivilianKilled", self, att)
	if self.mw and util.IsValidRagdoll(self.civVis or "") then

		local rag = ents.Create("prop_ragdoll")
		if IsValid(rag) then
			rag:SetModel(self.civVis)
			apply_look(rag, self.civSeed)
			rag:SetPos(self:GetPos())
			rag:SetAngles(self:GetAngles())
			rag:Spawn()
			rag:Activate()
			rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			local force = dmg:GetDamageForce()
			if force:Length() > 6000 then force = force:GetNormalized() * 6000 end
			local hit = dmg:GetDamagePosition()
			local nearest, nd
			local bm = Matrix()
			for i = 0, rag:GetPhysicsObjectCount() - 1 do
				local phys = rag:GetPhysicsObjectNum(i)
				local hb = self:LookupBone(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)) or "")
				local m = hb and TIF.CopyBone(self, hb, bm)
				if IsValid(phys) and m then
					phys:SetPos(m:GetTranslation())
					phys:SetAngles(m:GetAngles())
					phys:SetVelocity(self.loco:GetVelocity())
					local d = m:GetTranslation():DistToSqr(hit)
					if not nd or d < nd then nearest, nd = phys, d end
				end
			end
			if nearest then nearest:ApplyForceCenter(force * 0.4) end

			if TIF.Foley and TIF.Foley.CorpseSounds then TIF.Foley.CorpseSounds(rag) end
			local t = GetConVar("tif_corpse_time")
			if t and t:GetFloat() > 0 then SafeRemoveEntityDelayed(rag, t:GetFloat()) end
		end
		self:Remove()
		return
	end
	self:BecomeRagdoll(dmg)
end

function ENT:Use(ply)
	if not (IsValid(ply) and ply:IsPlayer()) then return end
	if CurTime() < (self.nextUse or 0) then return end
	self.nextUse = CurTime() + 2
	hook.Run("TIF_CivilianUse", self, ply)
end
