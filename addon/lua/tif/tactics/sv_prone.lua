-- Prone. The faction model plays the Prone Mod's ValveBiped animations itself on the client;
-- the server keeps a low hull and a face-down GTA pose for hitboxes.
-- Networked: NW2Int "tif_prone" (0 none, 1 going down, 2 down, 3 getting up), NW2Float "tif_prone_t".

local TIF = TIF
local A = TIF.Anim

TIF.ProneB = TIF.ProneB or {}
local P = TIF.ProneB

P.NONE, P.DOWN, P.IN, P.UP = 0, 1, 2, 3
P.HULL = Vector(13, 13, 22)
P.CRAWL_SPEED = 34
P.TURN_RATE = 80

local durations = {}
-- Get-down / get-up durations from the faction model's own sequences (cached per model).
local function durs(model)
	local d = durations[model]
	if d then return d end
	d = { down = 1.4, up = 1.6, ok = false }
	local e = ents.Create("prop_dynamic")
	if IsValid(e) then
		e:SetModel(model)
		local sd, su = e:LookupSequence("pronedown_stand"), e:LookupSequence("proneup_stand")
		if sd and sd >= 0 and su and su >= 0 then
			d.down, d.up, d.ok = e:SequenceDuration(sd), e:SequenceDuration(su), true
		end
		e:Remove()
	end
	durations[model] = d
	return d
end

-- MW19 body: its own prone clips (mwp_down / mwp_up / mwp_idle / mwp_crawl_*), played on the host by the
-- client like any other locomotion; no Prone Mod needed.
local function mw_durs(npc)
	local id = npc.tifHomeHost
	if not (id and TIF.GTG.IsVB(id)) then return nil end
	local d, u = TIF.GTG.Clip("mwp_down", id), TIF.GTG.Clip("mwp_up", id)
	if not (d and u) then return nil end
	return { down = d.dur, up = u.dur, ok = true }
end

local function durations_of(npc)
	return mw_durs(npc) or durs(npc:GetTIFVisual())
end

function P.Available(npc)
	if mw_durs(npc) then return true end
	return TIF.Prone.Present() and durs(npc:GetTIFVisual()).ok
end

function P.Is(npc) return npc.tifProne ~= nil end
function P.Ready(npc) return npc.tifProne ~= nil and npc.tifProne.phase == P.IN end

local function net_phase(npc, phase, now)
	npc:SetNW2Int("tif_prone", phase)
	npc:SetNW2Float("tif_prone_t", now)
end

-- Running and going prone: MW19's AI dive (mwp_dive_<jog|run>_<foot>_<n>) instead of stopping and lying down. The
-- one that ends facing the threat (else the way he runs), with room ahead for its slide (90-150 units). It plays
-- as an action over the prone set (cl_body proneAct) and moves him along its root. Returns the dive's length or nil.
P.DIVE_SPEED = 110
local function dive(npc)
	local id = npc.tifHomeHost
	if not (id and TIF.GTG.IsVB(id)) then return nil end
	local v = npc.loco:GetVelocity()
	v.z = 0
	local speed = v:Length()
	if speed < P.DIVE_SPEED then return nil end
	local gait = speed > 170 and "run" or "jog"
	local yaw = v:Angle().y
	local c = npc.tifPrimaryC
	local want = c and (c.pos - npc:GetPos()):Angle().y or yaw
	local best, be, bc
	for _, foot in ipairs({ "l", "r" }) do
		for _, n in ipairs({ "1", "2", "3", "4", "6", "7", "8", "9" }) do
			local name = "mwp_dive_" .. gait .. "_" .. foot .. "_" .. n
			local cl = TIF.GTG.Clip(name, id)
			if cl then
				local e = math.abs(math.AngleDifference(yaw + (cl.move[3] or 0), want)) + math.random() * 10
				if not be or e < be then best, be, bc = name, e, cl end
			end
		end
	end
	if not best then return nil end
	-- Room for the slide (its travel, along the run).
	local dist = math.sqrt(bc.move[1] ^ 2 + bc.move[2] ^ 2)
	local pos = npc:GetPos() + Vector(0, 0, 8)
	local tr = util.TraceHull({ start = pos, endpos = pos + v:GetNormalized() * (dist + 16), mins = Vector(-12, -12, 0),
		maxs = Vector(12, 12, 24), mask = MASK_NPCSOLID, filter = npc })
	if tr.Hit then return nil end
	npc:SetAngles(Angle(0, yaw, 0))
	return TIF.Action.Play(npc, best, { root = true })
end

function P.GoDown(npc, reason)
	if npc.tifProne or not P.Available(npc) then return false end
	local now = CurTime()
	-- (the dive reads his run before the stop: the loco keeps its velocity this tick; the dive replaces any stop clip)
	local v0 = npc.loco:GetVelocity()
	TIF.Move.Stop(npc)
	local diveD = mw_durs(npc) and v0:Length2D() >= P.DIVE_SPEED and dive(npc)
	if diveD then
		if TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "diving prone") end
		npc.tifProne = { phase = P.DOWN, t0 = now, phaseEnd = now + diveD, since = now, reason = reason, dive = true }
		npc.tifStance = 2
		npc:SetTIFStance(2)
		npc:SetCollisionBounds(Vector(-13, -13, 0), P.HULL)
		net_phase(npc, P.DOWN, now)
		return true
	end
	TIF.Move.Stop(npc)
	TIF.Action.Clear(npc)
	if TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "going prone") end
	-- Still on the GTA body after a GTA-only action: back to the MW19 body, whose prone clips are used.
	if mw_durs(npc) and npc.tifHostId ~= npc.tifHomeHost and npc.TIFSetHost then npc:TIFSetHost(npc.tifHomeHost) end
	local d = durations_of(npc)
	npc.tifProne = { phase = P.DOWN, t0 = now, phaseEnd = now + d.down, since = now, reason = reason }
	npc.tifStance = 2
	npc:SetTIFStance(2)
	npc:SetCollisionBounds(Vector(-13, -13, 0), P.HULL)
	net_phase(npc, P.DOWN, now)
	return true
end

function P.GetUp(npc)
	local p = npc.tifProne
	if not p or p.phase == P.UP or p.phase == P.DOWN then return end
	local now = CurTime()
	local d = durations_of(npc)
	p.phase, p.t0, p.phaseEnd = P.UP, now, now + d.up
	net_phase(npc, P.UP, now)
end

-- Called every think. Finishes transitions. Returns true while the soldier can't do anything else.
function P.Update(npc, now)
	local p = npc.tifProne
	if not p then return false end
	if p.phase == P.DOWN and now >= p.phaseEnd then
		p.phase = P.IN
		-- (a dive was an action: lying now, the prone set takes over)
		if p.dive and npc.tifAct and string.sub(npc.tifAct.name, 1, 9) == "mwp_dive_" then TIF.Action.Clear(npc) end
		net_phase(npc, P.IN, now)
	elseif p.phase == P.UP and now >= p.phaseEnd then
		npc.tifProne = nil
		npc.tifStance = A.STANCE_STAND
		npc:SetTIFStance(A.STANCE_STAND)
		npc:TIFApplyStance()
		net_phase(npc, P.NONE, now)
		npc.tifLastProneAt = now
		return false
	end
	return p.phase ~= P.IN
end
