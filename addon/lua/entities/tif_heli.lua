-- TIF helicopter: flies a route planned by TIF.Air (tif/air/sv_air.lua): in at cruise height, slows over the LZ,
-- lands or hovers, holds, climbs out and leaves. Kinematic (a physics shadow follows the flight model), so it
-- collides and takes bullets but nothing knocks it off its path. Shot down: it falls as a real physics object,
-- spinning, and becomes a burning wreck where it hits.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "TIF Helicopter"
ENT.Author = "TIF"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.TIFHeli = true

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "HeliType")
	self:NetworkVar("Float", 0, "Rotor")      -- rotor speed 0..1
	self:NetworkVar("Bool", 0, "DoorsOpen")
	self:NetworkVar("Bool", 1, "Dying")
	self:NetworkVar("Bool", 2, "Ropes")      -- rappel ropes hanging from tag_fastrope_le / _ri
end

local function def_of(ent)
	return TIF.Air and TIF.Air.Type(ent:GetHeliType())
end

if CLIENT then
	local ROTOR_DPS = 1300 -- main rotor, degrees per second at full speed (with the blurred blades)

	function ENT:Initialize()
		self.rotA, self.tailA, self.doorT = 0, 0, 0
		self.nextWash, self.nextSmoke = 0, 0
	end

	-- (not "SetupBones": that's an engine Entity method and is found first, so ours never ran)
	function ENT:TIFInitBones(def)
		self.tifBones = {
			rotor = self:LookupBone(def.rotorBone or ""),
			tail = self:LookupBone(def.tailBone or ""),
			doors = {},
		}
		for _, b in ipairs(def.doors and def.doors.bones or {}) do
			local id = self:LookupBone(b)
			if id then table.insert(self.tifBones.doors, id) end
		end
		self.rotorBG = self:FindBodygroupByName("rotor")
		self.engines = { self:LookupAttachment("tag_engine_left"), self:LookupAttachment("tag_engine_right") }
	end

	-- Crew dummies (pilots, crew chiefs): client-side only, no AI. Each is the MW19 host body (invisible, for its
	-- bones) parented to the helicopter at its tag, playing its seat loop, with a faction model bone-merged on it.
	-- Seats: TIF_AIR_INFIL[type].crew (heli_infil_data.py). Crew chiefs only where the drop's set leaves them room.
	local CREW_HOST = "models/tif_mw/mw_male.mdl"

	function ENT:TIFMakeCrew(def)
		self.tifCrew = {}
		local data = istable(TIF_AIR_INFIL) and TIF_AIR_INFIL[self:GetHeliType()]
		local crew = data and data.crew
		if not crew or not util.IsValidModel(CREW_HOST) then return end
		local list = {}
		for _, m in ipairs(crew.pilots or {}) do list[#list + 1] = m end
		local set = data[self:GetNW2String("tif_crew_set", "")]
		for _, i in ipairs(set and set.chiefs or {}) do
			if crew.chiefs and crew.chiefs[i] then list[#list + 1] = crew.chiefs[i] end
		end
		local fac = TIF.Factions and TIF.Factions[self:GetNW2String("tif_crew_fac", "usmc")]
		local models = fac and fac.models or {}
		for k, m in ipairs(list) do
			local clip = TIF.GTG and TIF.GTG.Clip(m.role, TIF.GTG.MW_HOST)
			local id = self:LookupAttachment(m.tag)
			local a = id and id > 0 and self:GetAttachment(id)
			if clip and a then
				local tp, ta = WorldToLocal(a.Pos, a.Ang, self:GetPos(), self:GetAngles())
				local o = Vector(m.off[1], m.off[2], m.off[3])
				o:Rotate(Angle(0, ta.y, 0))
				local host = ClientsideModel(CREW_HOST, RENDERGROUP_TRANSLUCENT)
				if IsValid(host) then
					-- (drawn invisible rather than not drawn: a no-draw parent may skip building the bones the
					-- bone-merged model sits on)
					host:SetRenderMode(RENDERMODE_TRANSCOLOR)
					host:SetColor(Color(255, 255, 255, 0))
					host:DrawShadow(false) -- (crew shadows from inside the cabin were stretched huge)
					host:SetParent(self)
					host:SetLocalPos(tp + o)
					host:SetLocalAngles(Angle(0, ta.y + m.yaw, 0))
					local seq = host:LookupSequence(clip.seq)
					host:ResetSequence(seq >= 0 and seq or 0)
					local mdl = #models > 0 and models[(self:EntIndex() * 3 + k) % #models + 1] or nil
					local vis = mdl and util.IsValidModel(mdl) and ClientsideModel(mdl, RENDERGROUP_OPAQUE)
					if vis then
						vis:SetParent(host)
						vis:AddEffects(EF_BONEMERGE)
						vis:DrawShadow(false)
						vis:SetSkin((self:EntIndex() + k) % math.max(1, vis:SkinCount()))
					else
						host:SetColor(Color(255, 255, 255, 255)) -- no faction model: the host's own body shows
					end
					table.insert(self.tifCrew, { host = host, vis = vis, dur = math.max(0.1, clip.dur), phase = math.Rand(0, 1) })
				end
			end
		end
	end

	function ENT:TIFCrewThink()
		local t = CurTime()
		for _, c in ipairs(self.tifCrew or {}) do
			if IsValid(c.host) then
				c.host:SetCycle((t / c.dur + c.phase) % 1)
				c.host:InvalidateBoneCache()
			end
		end
	end

	function ENT:TIFRemoveCrew()
		for _, c in ipairs(self.tifCrew or {}) do
			if IsValid(c.vis) then c.vis:Remove() end
			if IsValid(c.host) then c.host:Remove() end
		end
		self.tifCrew = nil
	end

	function ENT:Think()
		local def = def_of(self)
		if not def then return end
		if not self.tifBones then self:TIFInitBones(def) end
		-- (built once the seat set and faction have arrived from the server: the set picks the crew chiefs)
		if not self.tifCrew and self:GetNW2String("tif_crew_fac", "") ~= "" then self:TIFMakeCrew(def) end
		self:TIFCrewThink()
		self:TIFRopesThink()
		local dt = FrameTime()
		local rpm = self:GetRotor()
		local B = self.tifBones
		-- Rotors.
		self.rotA = (self.rotA + ROTOR_DPS * rpm * dt) % 360
		self.tailA = (self.tailA + ROTOR_DPS * 4.6 * rpm * dt) % 360
		if B.rotor then self:ManipulateBoneAngles(B.rotor, Angle(0, self.rotA, 0)) end
		if B.tail then
			self:ManipulateBoneAngles(B.tail, def.tailAxis == "roll" and Angle(0, 0, self.tailA) or Angle(self.tailA, 0, 0))
		end
		if self.rotorBG and self.rotorBG >= 0 then
			local want = rpm > 0.55 and 1 or 0
			if self:GetBodygroup(self.rotorBG) ~= want then self:SetBodygroup(self.rotorBG, want) end
		end
		-- Sliding doors.
		local d = def.doors
		if d then
			local goal = self:GetDoorsOpen() and 1 or 0
			self.doorT = math.Approach(self.doorT, goal, dt / math.max(0.1, d.time))
			local s = self.doorT * self.doorT * (3 - 2 * self.doorT)
			for _, b in ipairs(B.doors) do self:ManipulateBonePosition(b, d.travel * s) end
		end
		self:RotorSound(def, rpm)
		if self.emitter then self.emitter:SetPos(self:GetPos()) end
		self:Wash(rpm)
		if self:GetDying() then self:Smoke() end
		self:SetNextClientThink(CurTime())
		return true
	end

	function ENT:RotorSound(def, rpm)
		if not self.loop and def.sound and rpm > 0.02 then
			self.loop = CreateSound(self, def.sound)
			self.loop:SetSoundLevel(105)
			self.loop:PlayEx(0, 70)
		end
		if self.loop then self.loop:ChangeVolume(math.min(1, rpm * 1.4), 0.2) self.loop:ChangePitch(70 + 30 * rpm, 0.2) end
	end

	-- Rotor wash: dust thrown out along the ground under the rotor when low.
	function ENT:Wash(rpm)
		local now = CurTime()
		if rpm < 0.6 or now < self.nextWash then return end
		self.nextWash = now + 0.06
		local pos = self:GetPos()
		local tr = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, 900), mask = MASK_SOLID_BRUSHONLY })
		if not tr.Hit then return end
		local k = 1 - tr.Fraction
		self.emitter = self.emitter or ParticleEmitter(pos)
		local col = (tr.MatType == MAT_DIRT or tr.MatType == MAT_SAND or tr.MatType == MAT_GRASS) and { 150, 130, 100 } or { 140, 140, 135 }
		for _ = 1, 3 do
			local a = math.Rand(0, math.pi * 2)
			local dir = Vector(math.cos(a), math.sin(a), 0)
			local p = self.emitter:Add("particle/particle_smokegrenade", tr.HitPos + dir * math.Rand(120, 380) + Vector(0, 0, 12))
			if p then
				p:SetVelocity(dir * math.Rand(500, 900) * k + Vector(0, 0, math.Rand(10, 60)))
				p:SetAirResistance(120)
				p:SetDieTime(math.Rand(1.2, 2.2))
				p:SetStartAlpha(70 * k)
				p:SetEndAlpha(0)
				p:SetStartSize(math.Rand(40, 70))
				p:SetEndSize(math.Rand(160, 240))
				p:SetRoll(math.Rand(0, 360))
				p:SetRollDelta(math.Rand(-1, 1))
				p:SetColor(col[1], col[2], col[3])
			end
		end
	end

	-- Shot down: black smoke from the engines.
	function ENT:Smoke()
		local now = CurTime()
		if now < self.nextSmoke then return end
		self.nextSmoke = now + 0.04
		self.emitter = self.emitter or ParticleEmitter(self:GetPos())
		for _, att in ipairs(self.engines or {}) do
			local a = att and att > 0 and self:GetAttachment(att)
			if a then
				local p = self.emitter:Add("particle/particle_smokegrenade", a.Pos)
				if p then
					p:SetVelocity(VectorRand() * 30 + Vector(0, 0, 60))
					p:SetDieTime(math.Rand(2.5, 4))
					p:SetStartAlpha(200)
					p:SetEndAlpha(0)
					p:SetStartSize(30)
					p:SetEndSize(math.Rand(120, 180))
					p:SetRoll(math.Rand(0, 360))
					p:SetColor(25, 25, 25)
				end
			end
		end
	end

	-- Ropes (0.29.0): the MWII fast-rope rope (tif_air/rope.mdl, 200 joints, 3 apart; K:/jimmyproject/tif_air/rope_build.py)
	-- hung from each rope tag and posed here every frame: thrown out, the end falling (gravity), then hanging to the
	-- ground and swaying, the rest lying on the ground; stretched (joint scale) when the drop is longer than the rope.
	-- When the ropes are cut (men down) they fall away and lie there a few seconds. No model: the old drawn lines.
	local ROPE_MDL = "models/tif_air/rope.mdl"
	local ROPE_N, ROPE_STEP, ROPE_G = 200, 3, 900
	local ropeWarned = false

	local function pose_rope(r)
		local e = r.ent
		local base = r.base
		if not base then
			base = e:LookupBone("j_rope_1")
			r.base = base
			if not base then return end
		end
		local A, G, now = r.A, r.G, CurTime()
		if not (A and G) then return end
		local drop = math.max(8, A.z - G.z)
		-- rope length: its own 600, stretched if the drop needs more (+ some lying on the ground)
		local L = math.max(ROPE_N * ROPE_STEP, drop + 60)
		local ds = L / ROPE_N
		local k = ds / ROPE_STEP
		local fallen = math.min(L, 40 + 0.5 * ROPE_G * (now - r.t0) ^ 2)
		local m = Matrix()
		m:SetTranslation(A)
		e:SetBoneMatrix(0, m)
		local prev = A
		for i = 1, ROPE_N do
			local s = math.min((i - 1) * ds, fallen)
			local p
			if s <= drop then
				local w = s / drop
				local sw = w * w * 9
				p = Vector(A.x + math.sin(now * 1.3 + r.ph + w * 3) * sw, A.y + math.cos(now * 1.1 + r.ph * 2 + w * 2) * sw, A.z - s)
			else
				-- on the ground, laid out away from the helicopter
				local g = s - drop
				p = Vector(G.x + r.dir.x * g, G.y + r.dir.y * g, G.z + 1)
			end
			local t = p - prev
			if i == 1 or t:LengthSqr() < 0.01 then t = Vector(0, 0, -1) end
			m = Matrix()
			m:SetAngles(t:Angle())
			m:SetTranslation(p)
			m:Scale(Vector(k, 1, 1))
			e:SetBoneMatrix(base + i - 1, m)
			prev = p
		end
	end

	-- Ropes on (server NW "Ropes"): one model per rope tag. Off: they fall from the helicopter and are removed later.
	function ENT:TIFRopesThink()
		local on = self:GetRopes()
		self.tifRopes = self.tifRopes or {}
		-- (0.29.0, user: every rope is the rope model; the old drawn HL2 lines are gone. Without the model (tif_air
		-- missing, or added while the game ran: new model files are only mounted at start) there are no ropes, and a
		-- console note says why.)
		if on and #self.tifRopes == 0 and not util.IsValidModel(ROPE_MDL) and not ropeWarned then
			ropeWarned = true
			MsgN("[TIF] Helicopter ropes need ", ROPE_MDL, " (tif_air addon); restart the game if it was just installed")
		end
		if on and #self.tifRopes == 0 and util.IsValidModel(ROPE_MDL) then
			local def = def_of(self)
			for k, tag in ipairs(def and def.ropeTags or {}) do
				local id = self:LookupAttachment(tag)
				if id and id > 0 then
					local e = ClientsideModel(ROPE_MDL, RENDERGROUP_OPAQUE)
					if IsValid(e) then
						e:DrawShadow(false)
						local out = self:GetRight() * (k % 2 == 0 and -1 or 1)
						local r = { ent = e, att = id, t0 = CurTime(), ph = k * 1.7, dir = (out - self:GetForward() * 0.3):GetNormalized() }
						e:AddCallback("BuildBonePositions", function() pose_rope(r) end)
						table.insert(self.tifRopes, r)
					end
				end
			end
		end
		for i = #self.tifRopes, 1, -1 do
			local r = self.tifRopes[i]
			if not IsValid(r.ent) then
				table.remove(self.tifRopes, i)
			else
				if on then
					local a = self:GetAttachment(r.att)
					if a then
						r.A = a.Pos
						local tr = util.TraceLine({ start = a.Pos, endpos = a.Pos - Vector(0, 0, 3000), mask = MASK_SOLID_BRUSHONLY })
						r.G = tr.HitPos
					end
				else
					-- cut: the top falls to the ground, then the rope lies there 8 s
					r.cut = r.cut or CurTime()
					if r.A and r.G then r.A = Vector(r.A.x, r.A.y, math.max(r.G.z + 2, r.A.z - 600 * FrameTime() * 1.5)) end
					if CurTime() - r.cut > 8 then r.ent:Remove() end
				end
				if r.A and r.G then
					local lo, hi = Vector(math.min(r.A.x, r.G.x) - 700, math.min(r.A.y, r.G.y) - 700, r.G.z - 20),
						Vector(math.max(r.A.x, r.G.x) + 700, math.max(r.A.y, r.G.y) + 700, r.A.z + 20)
					r.ent:SetPos(r.A)
					r.ent:SetRenderBoundsWS(lo, hi)
				end
			end
		end
	end

	function ENT:TIFRemoveRopes()
		for _, r in ipairs(self.tifRopes or {}) do if IsValid(r.ent) then r.ent:Remove() end end
		self.tifRopes = nil
	end

	function ENT:Draw() self:DrawModel() end
	function ENT:DrawTranslucent()
		self:DrawModel()
	end

	function ENT:OnRemove()
		if self.loop then self.loop:Stop() end
		if self.emitter then self.emitter:Finish() end
		self:TIFRemoveCrew()
		self:TIFRemoveRopes()
	end
	return
end

-- Server ------------------------------------------------------------------------

local HELI_THINK = 0 -- every tick

function ENT:Initialize()
	local def = def_of(self)
	if not def then
		SafeRemoveEntityDelayed(self, 0)
		return
	end
	self:SetModel(def.model)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:MakePhysicsObjectAShadow(false, false)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:SetMass(5000) end
	self:SetHealth(math.floor(def.health * (GetConVar("tif_heli_health_scale") and GetConVar("tif_heli_health_scale"):GetFloat() or 1)))
	self:SetMaxHealth(self:Health())
	self.def = def
	self.p = self:GetPos()
	self.v = Vector()
	self.a = Vector()
	self.yaw = self:GetAngles().y
	self.pitch, self.roll = 0, 0
	self.rpm = 1
	self:SetRotor(1)
	self.phase = self.phase or "inbound"
	self.phaseAt = CurTime()
	self.nextGround = 0
	self.groundAhead = nil
	self:NextThink(CurTime())
end

-- route: { entry, app (where the approach starts), hub (hover / landed hub position over the LZ), exit,
--          heading (yaw over the LZ), cruiseZ, ceilZ, mode ("land" | "rope" | "flyby"), hold (s, nil = until Release) }
function ENT:SetRoute(route)
	self.route = route
	self.phase = "inbound"
	self.phaseAt = CurTime()
	if route and route.doorsOpen then self:SetDoorsOpen(true) end
end

function ENT:Phase() return self.phase end
function ENT:Arrived() return self.phase == "hold" end

-- Leave now (hold over): the gamemode / dismount logic calls this when everyone is out.
function ENT:Release()
	if self.phase == "hold" or self.phase == "descend" or self.phase == "approach" then self:SetPhase("climb") end
end

function ENT:SetPhase(ph)
	if self.phase == ph then return end
	self.phase = ph
	self.phaseAt = CurTime()
	local r = self.route
	if ph == "hold" then
		self.holdUntil = r and r.hold and CurTime() + r.hold or nil
		if r and r.onArrive then pcall(r.onArrive, self) end
		hook.Run("TIF_HeliArrived", self)
	elseif ph == "climb" then
		if not (r and r.doorsOpen) then self:SetDoorsOpen(false) end
		self:SetRopes(false)
		hook.Run("TIF_HeliLeaving", self)
	end
end

-- Flight model ----------------------------------------------------------------------

local function flat(v) return Vector(v.x, v.y, 0) end

local function clamp_len(v, max)
	local l = v:Length()
	if l > max and l > 0 then return v * (max / l) end
	return v
end

-- Highest ground under the path ahead (sampled a few times a second), for terrain following at cruise.
function ENT:GroundAhead(now)
	if now < self.nextGround and self.groundAhead then return self.groundAhead end
	self.nextGround = now + 0.25
	local r = self.route
	local top = (r and r.ceilZ or self.p.z + 4000) - 10
	local best = -math.huge
	for _, t in ipairs({ 0, 1.2, 2.5 }) do
		local p = self.p + flat(self.v) * t
		local tr = util.TraceLine({ start = Vector(p.x, p.y, top), endpos = Vector(p.x, p.y, top - 30000), mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit and not tr.StartSolid then best = math.max(best, tr.HitPos.z) end
	end
	self.groundAhead = best > -math.huge and best or nil
	return self.groundAhead
end

-- Desired velocity toward a point, slowing to arrive (horizontal) and holding a height (vertical).
local function arrive(self, target, maxSpeed, decel)
	local to = flat(target - self.p)
	local dist = to:Length()
	local speed = math.min(maxSpeed, math.sqrt(2 * decel * math.max(0, dist - 10)))
	return dist > 1 and to * (speed / dist) or Vector(), dist
end

function ENT:CruiseZ(now)
	local r = self.route
	local z = r.cruiseZ
	local g = self:GroundAhead(now)
	if g then z = math.max(z, g + self.def.cruiseClearance * 0.6) end
	return math.min(z, r.ceilZ - 120)
end

function ENT:Fly(dt, now)
	local def, r = self.def, self.route
	local want = Vector()
	local face
	local ph = self.phase
	if not r then
		want = -self.v * 0.5
	elseif ph == "inbound" or ph == "depart" then
		local goal = ph == "inbound" and r.app or r.exit
		local to = flat(goal - self.p)
		local dist = to:Length()
		want = dist > 1 and to * (def.cruiseSpeed / dist) or Vector()
		want.z = math.Clamp((self:CruiseZ(now) - self.p.z) * 0.8, -def.sinkRate, def.climbRate)
		if ph == "inbound" then
			-- Start slowing early enough to stop over the LZ (approach takes over).
			local speed = flat(self.v):Length()
			if r.mode == "flyby" then
				if dist < 300 then self:SetPhase("depart") end
			elseif dist < math.max(speed * speed / (2 * def.accel * 0.8) + 200, (r.glideD or 0) + 150) then
				self:SetPhase("approach")
			end
		elseif dist < 400 then
			self:Remove()
			return
		end
	elseif ph == "approach" then
		local hdist
		local D = r.glideD
		if D then
			-- Down the slope: slowing evenly from cruise speed to a stop over the spot (deceleration so the speed
			-- profile starts at cruise where the slope starts), height following the slope by the distance left.
			local decel = math.max(def.accel * 0.25, def.cruiseSpeed * def.cruiseSpeed / (2 * D))
			want, hdist = arrive(self, r.hub, def.cruiseSpeed, decel)
			local top = r.hub.z + (r.settle or 0)
			-- (eased: pushes over gently at the top, flattens out low over the spot; a straight line asked for a sink
			-- rate the instant the slope began)
			local u = math.Clamp(hdist / D, 0, 1)
			local zt = top + (r.cruiseZ - top) * (u * u * (3 - 2 * u))
			-- Sink at the slope's own rate for the ground speed (feed-forward), plus a correction for what's off the
			-- line: correcting alone trailed the line by ~220.
			local grad = (r.cruiseZ - top) * 6 * u * (1 - u) / D
			local ff = -grad * flat(self.v):Length()
			want.z = math.Clamp(ff + (zt - self.p.z) * 1.5, -def.sinkRate * 1.8, def.climbRate)
			face = r.heading
			if hdist < 1500 and not self:GetDoorsOpen() then self:SetDoorsOpen(true) end
		else
			-- No clear slope: over the spot at height, then straight down (descend).
			local hz = math.max(r.hub.z + 250, math.min(self.p.z, self:CruiseZ(now)))
			want, hdist = arrive(self, r.hub, def.approachSpeed + (def.cruiseSpeed - def.approachSpeed) * 0.5, def.accel * 0.7)
			want.z = math.Clamp((hz - self.p.z) * 0.6, -def.sinkRate, def.climbRate)
			if hdist < 900 then face = r.heading end
		end
		if hdist < 40 and flat(self.v):Length() < 80 then self:SetPhase("descend") end
	elseif ph == "descend" then
		want = flat(r.hub - self.p) * 1.5
		local dz = r.hub.z - self.p.z
		local sink = math.min(def.sinkRate, math.sqrt(2 * 120 * math.abs(dz)) + 15)
		want.z = math.Clamp(dz * 1.2, -sink, sink)
		face = r.heading
		if dz > -500 and not self:GetDoorsOpen() then self:SetDoorsOpen(true) end
		if math.abs(dz) < 6 and math.abs(self.v.z) < 25 then self:SetPhase("hold") end
	elseif ph == "hold" then
		local target = r.hub
		if r.mode == "rope" and not self.tifRiders then
			-- A hover isn't perfectly still (held still while men are on the ropes: their clips are placed in the world).
			local t = now - self.phaseAt
			target = r.hub + Vector(math.sin(t * 0.7) * 10, math.cos(t * 0.53) * 8, math.sin(t * 0.9) * 6)
		end
		want = (target - self.p) * 2
		face = r.heading
		if self.holdUntil and now > self.holdUntil then self:SetPhase("climb") end
	elseif ph == "climb" then
		local up = self:CruiseZ(now)
		local fwd = Angle(0, r.heading, 0):Forward()
		local t = now - self.phaseAt
		want = Vector(0, 0, def.climbRate) + fwd * math.min(def.cruiseSpeed * 0.4, t * 120)
		face = r.heading
		if self.p.z > math.min(up - 100, r.hub.z + 700) then self:SetPhase("depart") end
	end

	-- Velocity follows the wanted one at limited acceleration (vertical separately).
	local dv = want - self.v
	local dvh = clamp_len(flat(dv), def.accel * dt)
	local dvz = math.Clamp(dv.z, -def.accel * 0.6 * dt, def.accel * 0.6 * dt)
	local acc = Vector(dvh.x, dvh.y, dvz) / math.max(dt, 0.001)
	self.v = self.v + Vector(dvh.x, dvh.y, dvz)
	self.p = self.p + self.v * dt
	self.a = LerpVector(math.min(1, dt * 4), self.a, acc)

	-- Heading: along the flight path when moving, else the wanted one.
	local hv = flat(self.v)
	if not face and hv:Length() > 250 then face = hv:Angle().y end
	if face then
		local diff = math.AngleDifference(face, self.yaw)
		self.yaw = self.yaw + math.Clamp(diff, -45 * dt, 45 * dt)
	end
	-- Attitude from acceleration and speed: nose down to speed up / cruise, up to slow; bank into turns.
	local f = Angle(0, self.yaw, 0):Forward()
	local rgt = Angle(0, self.yaw, 0):Right()
	local wantPitch = math.Clamp(self.a:Dot(f) * 0.03 + hv:Dot(f) * 0.005, -16, 14)
	local wantRoll = math.Clamp(self.a:Dot(rgt) * 0.035, -22, 22)
	if ph == "hold" and r and r.mode == "land" then wantPitch, wantRoll = 0, 0 end
	self.pitch = math.Approach(self.pitch, wantPitch, 20 * dt)
	self.roll = math.Approach(self.roll, wantRoll, 25 * dt)
end

function ENT:Think()
	local now = CurTime()
	local dt = engine.TickInterval()
	if self.crashing then
		self:CrashThink(now, dt)
	else
		self:Fly(dt, now)
		if not IsValid(self) then return end
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:UpdateShadow(self.p, Angle(self.pitch, self.yaw, self.roll), dt) end
	end
	self:NextThink(now + HELI_THINK)
	return true
end

-- Damage and crash ----------------------------------------------------------------------

function ENT:OnTakeDamage(dmg)
	if self.crashing or self.exploded then return end
	local n = dmg:GetDamage()
	if dmg:IsExplosionDamage() then n = n * 1.5 end
	self:SetHealth(self:Health() - n)
	local e = EffectData()
	e:SetOrigin(dmg:GetDamagePosition())
	e:SetNormal(-dmg:GetDamageForce():GetNormalized())
	e:SetMagnitude(1)
	e:SetScale(1)
	util.Effect("MetalSpark", e)
	if self:Health() <= 0 then self:Crash(dmg:GetAttacker()) end
end

-- Goes down: a real physics object from here (falls, spins, hits things), engines smoking.
function ENT:Crash(attacker)
	self.crashing = true
	self.attacker = attacker
	self:SetDying(true)
	self:SetDoorsOpen(false)
	self.crashAt = CurTime()
	hook.Run("TIF_HeliDestroyed", self, attacker)
	local r = self.route
	if r and r.onDestroyed then pcall(r.onDestroyed, self, attacker) end
	local v = self.v
	self:PhysicsInit(SOLID_VPHYSICS)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetMass(5000)
		phys:Wake()
		phys:EnableGravity(true)
		phys:SetVelocity(v)
		phys:AddAngleVelocity(Vector(math.Rand(-10, 10), math.Rand(-10, 10), math.Rand(90, 140) * (math.random() < 0.5 and -1 or 1)))
	end
	self:EmitSound("ambient/explosions/explode_7.wav", 120)
end

function ENT:CrashThink(now, dt)
	local phys = self:GetPhysicsObject()
	local t = now - self.crashAt
	self:SetRotor(math.max(0.35, self:GetRotor() - dt * 0.15))
	if IsValid(phys) then
		-- Spinning harder as it goes, a little lift left from the rotor.
		local av = phys:GetAngleVelocity()
		phys:AddAngleVelocity(Vector(0, 0, (av.z >= 0 and 1 or -1) * 60 * dt))
		phys:ApplyForceCenter(Vector(0, 0, phys:GetMass() * 260 * dt))
	end
	if t > 14 then self:Explode() end
end

function ENT:PhysicsCollide(data)
	if not self.crashing or self.exploded then return end
	if CurTime() - self.crashAt < 0.4 then return end
	if data.Speed > 120 or (data.HitEntity and data.HitEntity:IsWorld()) then
		timer.Simple(0, function() if IsValid(self) then self:Explode() end end)
	end
end

local cvWreck = CreateConVar("tif_heli_wreck_time", "120", FCVAR_ARCHIVE, "Seconds a shot-down helicopter's wreck stays (0 = until cleanup)")

function ENT:Explode()
	if self.exploded then return end
	self.exploded = true
	local pos = self:GetPos()
	local att = IsValid(self.attacker) and self.attacker or self
	util.BlastDamage(self, att, pos, 450, 180)
	local e = EffectData()
	e:SetOrigin(pos)
	util.Effect("Explosion", e)
	util.Effect("HelicopterMegaBomb", e)
	self:EmitSound("ambient/explosions/explode_4.wav", 140)
	-- The wreck, on the ground below, facing the way the helicopter did.
	local def = self.def
	if def.wreck and util.IsValidModel(def.wreck) then
		local tr = util.TraceLine({ start = pos + Vector(0, 0, 50), endpos = pos - Vector(0, 0, 2000), filter = self, mask = MASK_SOLID_BRUSHONLY })
		local w = ents.Create("prop_physics")
		if IsValid(w) then
			w:SetModel(def.wreck)
			w:SetPos(tr.HitPos + Vector(0, 0, 4))
			w:SetAngles(Angle(0, self:GetAngles().y, 0))
			w:Spawn()
			local wp = w:GetPhysicsObject()
			if IsValid(wp) then wp:EnableMotion(false) end
			w:Ignite(40, 0)
			local tm = cvWreck:GetFloat()
			if tm > 0 then SafeRemoveEntityDelayed(w, tm) end
		end
	end
	self:Remove()
end

function ENT:OnRemove()
	if TIF.Air and TIF.Air.Forget then TIF.Air.Forget(self) end
end
