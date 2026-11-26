-- Crowd (0.38.18, user: "make sure they wont get stuck on eachother. its something i see alot both in and outdoors,
-- and on civillians"). Soldiers and civilians used to notice each other only after bumping (sv_move watch_stuck:
-- 0.6 s without progress, a sidestep and a fresh path; civilians only the engine's slow stuck check). Three parts:
--   Steer      a moving body looks a little way along where it's going. Someone ahead walking the same way: it
--              keeps to their pace behind them. Someone standing, crossing or coming the other way: it eases past on
--              its right (everyone keeps right, so two meeting head-on don't mirror each other), or its left when
--              that side is walled / the other is already to its right. No new path: an extra Approach blended into
--              the path's own.
--   Ghost      two TIF bodies overlapping (root-motion clips move the body with a world-only trace, spawns, vehicle
--              exits) for GHOST_AFTER s, or at once when one is in a root-motion clip: both go to
--              COLLISION_GROUP_NPC_SCRIPTED (NPCs in scripts that don't collide with each other; bullets and players
--              still hit them) until they're apart, then back.
--   SidePoint  the open spot beside a body (hull traced), for civilians' quick stuck check (tif_civilian GoTo).
-- tif_crowd 0: all off. Timed under "crowd" in TIF's profiler.

local TIF = TIF
TIF.Crowd = TIF.Crowd or {}
local C = TIF.Crowd
local Prof = TIF.Prof

local cv = CreateConVar("tif_crowd", "1", FCVAR_ARCHIVE,
	"Soldiers and civilians steer round each other and come apart when they overlap (0: off)")
function C.On() return cv:GetBool() end

C.LOOK = 80          -- how far ahead someone counts as in the way
C.LANE = 26          -- half width of the lane ahead (two hulls side by side)
C.SCAN_T = 0.2       -- each mover looks again this often
C.SIDE = 36          -- how far to the side he eases
C.WEIGHT = 1.5       -- the side pull against the path's own (1)
C.FOLLOW = 25        -- someone ahead faster than this along my way is walked behind, not passed
C.OVERLAP = 22       -- hull centres closer than this on both axes = overlapping (hulls are 24-26 wide)
C.APART = 28         -- back to normal collisions once nobody is this close
C.GHOST_AFTER = 0.5
C.GHOST_MIN = 0.6
C.GHOST_GROUP = COLLISION_GROUP_NPC_SCRIPTED
C.UNSTACK_AFTER = 1.0
C.UNSTACK_GAP = 2.0

local function prof(n) if Prof then Prof.Begin(n) end end
local function unprof() if Prof then Prof.End() end end

local function vel_of(e)
	local v = (e.loco and e.loco:GetVelocity()) or e:GetVelocity()
	return Vector(v.x, v.y, 0)
end

-- Everyone who can be in the way, shared for 0.1 s: TIF soldiers and civilians, players, other NPCs.
local list, listT = {}, -1
function C.Bodies(now)
	if now - listT < 0.1 then return list end
	listT, list = now, {}
	local function add(e, tif)
		list[#list + 1] = { e = e, pos = e:GetPos(), vel = vel_of(e), tif = tif }
	end
	for _, s in ipairs(TIF.Soldiers or {}) do
		if IsValid(s) and not s.tifDead and not s.tifVeh then add(s, true) end
	end
	if TIF.Civ and TIF.Civ.List then
		for _, c in ipairs(TIF.Civ.List()) do if not c.gone and not c.dead then add(c, true) end end
	end
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP then add(p, false) end
	end
	for _, n in ipairs(TIF.NPCs or {}) do if IsValid(n) and n:Health() > 0 then add(n, false) end end
	return list
end
function C.Invalidate() listT = -1 end

local SIDE_MIN, SIDE_MAX = Vector(-12, -12, 8), Vector(12, 12, 56)
local function open_frac(ent, from, to)
	local tr = util.TraceHull({ start = from, endpos = to, mins = SIDE_MIN, maxs = SIDE_MAX, filter = ent, mask = MASK_NPCSOLID })
	return tr.Fraction
end

-- The open spot dist to the side of ent (sgn 1 = its right of fwd; nil: either, the opener first), or nil.
function C.SidePoint(ent, fwd, dist, sgn)
	local me = ent:GetPos()
	local right = Vector(fwd.y, -fwd.x, 0)
	local order = sgn and { sgn, -sgn } or (math.random() < 0.5 and { 1, -1 } or { -1, 1 })
	local best, bf
	for _, s in ipairs(order) do
		local to = me + right * (s * dist) + fwd * 10
		local f = open_frac(ent, me, to)
		if f > 0.9 then return to end
		if not bf or f > bf then best, bf = me + (to - me) * f, f end
	end
	return (bf and bf > 0.4) and best or nil
end

-- Steer: called by a mover each step with where it's heading (fwd, flat unit), its pace and its goal. Returns the
-- pace to use (kept behind someone walking ahead) and, when easing past someone, a point to blend in
-- (loco:Approach(p, C.WEIGHT) after the path's update). Looks again every SCAN_T.
function C.Steer(ent, fwd, want, goal, now)
	if not cv:GetBool() or not fwd then return want, nil end
	local st = ent.tifCrowd
	if not st then st = {} ent.tifCrowd = st end
	if now >= (st.nextT or 0) then
		st.nextT = now + C.SCAN_T
		prof("crowd")
		st.cap, st.sgn = nil, nil
		local me = ent:GetPos()
		local right = Vector(fwd.y, -fwd.x, 0)
		local goalD = goal and Vector(goal.x - me.x, goal.y - me.y, 0):Length() or math.huge
		local best, bestA, bestLat
		local reach = C.LOOK + 30
		for _, b in ipairs(C.Bodies(now)) do
			if b.e ~= ent then
				local dx, dy = b.pos.x - me.x, b.pos.y - me.y
				if dx * dx + dy * dy < reach * reach and math.abs(b.pos.z - me.z) < 60 then
					local ahead = dx * fwd.x + dy * fwd.y
					local lat = dx * right.x + dy * right.y
					-- (in my lane, ahead of me, and not past where I'm stopping anyway)
					if ahead > 4 and ahead < C.LOOK and math.abs(lat) < C.LANE and ahead < goalD + 10
						and (not bestA or ahead < bestA) then
						best, bestA, bestLat = b, ahead, lat
					end
				end
			end
		end
		if best then
			local along = best.vel:Dot(fwd)
			if along > C.FOLLOW then
				-- Walking my way: keep behind at his pace once close (no passing in a file).
				if bestA < 60 and along < want then st.cap = math.max(along, 30) end
			else
				-- Standing, crossing or coming at me: past on my right, or my left if he's already to my right.
				local sgn = bestLat > 6 and -1 or 1
				local p = C.SidePoint(ent, fwd, C.SIDE, sgn)
				if p then
					st.sgn = (p - me):Dot(right) >= 0 and 1 or -1
					st.fwd = Vector(fwd)
				elseif bestA < 40 then
					st.cap = math.min(want, 30)   -- (nowhere to go: slow, the stuck check does the rest)
				end
				if along < -C.FOLLOW and bestA < 40 then st.cap = math.min(st.cap or want, want * 0.6) end
			end
		end
		unprof()
	end
	local pace = st.cap and math.min(want, st.cap) or want
	if st.sgn then
		local f = st.fwd or fwd
		local p = ent:GetPos() + f * 40 + Vector(f.y, -f.x, 0) * (st.sgn * C.SIDE)
		return pace, p
	end
	return pace, nil
end

-- Ghost ---------------------------------------------------------------------------------------------------------

local function root_clip(e)
	local a = e.tifAct
	return a and (a.root or a.to) and not a.finished
end

local function can_ghost(e)
	if e.tifVeh or e.tifBoarding or e.tifLeaving or e.tifDead then return false end
	local g = e:GetCollisionGroup()
	return g == COLLISION_GROUP_NPC or g == COLLISION_GROUP_NONE or g == C.GHOST_GROUP
end

local function ghost(e, now)
	if e.tifCrowdGhost then e.tifCrowdGhost.t = now return end
	if not can_ghost(e) then return end
	e.tifCrowdGhost = { old = e:GetCollisionGroup(), t = now }
	if e.tifCrowdGhost.old ~= C.GHOST_GROUP then e:SetCollisionGroup(C.GHOST_GROUP) end
end

local function unghost(e)
	local g = e.tifCrowdGhost
	e.tifCrowdGhost = nil
	-- (only if nothing else changed it meanwhile: vehicles, melee, deaths set their own)
	if g and IsValid(e) and e:GetCollisionGroup() == C.GHOST_GROUP and g.old ~= C.GHOST_GROUP then e:SetCollisionGroup(g.old) end
end
C.Unghost = unghost

-- (0.38.26) Two TIF bodies stuck pressed together (sv_move unstick: hulls touching never overlap, so the rule below
-- doesn't catch them): through each other for `secs` (then back once they're apart, as for overlaps). True if both
-- could be ghosted.
function C.GhostPair(a, b, secs, now)
	if not cv:GetBool() or not (IsValid(a) and IsValid(b)) then return false end
	if not (can_ghost(a) and can_ghost(b)) then return false end
	ghost(a, now)
	ghost(b, now)
	-- (Tick lets go GHOST_MIN after the last refresh: held at least secs)
	local hold = now + secs - C.GHOST_MIN
	for _, e in ipairs({ a, b }) do
		local g = e.tifCrowdGhost
		if g then g.t = math.max(g.t, hold) end
	end
	return a.tifCrowdGhost ~= nil and b.tifCrowdGhost ~= nil
end

-- (0.38.26) Make way: a soldier standing about (no goal, nothing on) that someone is stuck on side-steps WAY_DIST
-- out of that one's line, at a walk, for up to WAY_T s (driven every tick below; anything else he starts takes over).
C.WAY_DIST, C.WAY_T, C.WAY_SPEED, C.WAY_AGAIN = 40, 1.2, 70, 4
C.Way = C.Way or {}
function C.MakeWay(b, mover, fwd, now)
	if not cv:GetBool() or not (IsValid(b) and b.TIFSoldier and b.tifMove and b.loco and IsValid(mover)) then return false end
	if b.tifMove.goal or b.tifAct or b.tifCov or b.tifProne or b.tifVeh or b.tifShield or b.tifMelee or b.tifBipod
		or b.tifDowned or b.tifDead or (b.tifCQB and b.tifCQB.wait) then return false end
	if now < (b.tifWayNext or 0) then return false end
	local right = Vector(fwd.y, -fwd.x, 0)
	local lat = (b:GetPos() - mover:GetPos()):Dot(right)
	local p = C.SidePoint(b, fwd, C.WAY_DIST, lat >= 0 and 1 or -1)
	if not p then return false end
	b.tifWayNext = now + C.WAY_AGAIN
	C.Way[b] = { pos = p, untilT = now + C.WAY_T }
	return true
end

hook.Add("Tick", "tif_crowd_way", function()
	if next(C.Way) == nil then return end
	local now = CurTime()
	for b, w in pairs(C.Way) do
		if not IsValid(b) or b.tifDead or b.tifMove.goal or b.tifAct or now > w.untilT or b:GetPos():DistToSqr(w.pos) < 10 * 10 then
			C.Way[b] = nil
		else
			b.loco:SetDesiredSpeed(C.WAY_SPEED)
			b.loco:Approach(w.pos, 1)
		end
	end
end)

-- Every 0.25 s: overlapping TIF pairs, how long, ghosting and un-ghosting.
local function idle_soldier(e)
	if not (e.TIFSoldier and not e.tifDead) then return false end
	if e.tifCov or e.tifProne or e.tifVeh or e.tifDowned or e.tifSurrendered or e.tifAct or e.tifMedic or e.tifBipod
		or e.tifCQB or e.tifBoarding or e.tifLeaving then return false end
	if e.tifMove and e.tifMove.goal then return false end
	return e.loco and e.loco:GetVelocity():Length2DSqr() < 15 * 15
end
C.IdleSoldier = idle_soldier

local function unstacking(e) return e.tifMove and e.tifMove.goal and e.tifMove.tag == "unstack" end

function C.Unstack(e, now)
	if now < (e.tifNextUnstack or 0) then return false end
	e.tifNextUnstack = now + C.UNSTACK_GAP
	local Mv = TIF.Move
	if not (Mv and Mv.Spread and Mv.SetGoal) then return false end
	local me = e:GetPos()
	local spot = Mv.Spread(e, me)
	if not spot or spot:DistToSqr(me) < 20 * 20 then return false end
	if not Mv.SetGoal(e, spot, "walk", "unstack") then return false end
	if e.tifPost and e.tifPost:DistToSqr(me) < 100 * 100 then e.tifPost = spot end
	return true
end

function C.Tick(now)
	local on = cv:GetBool()
	prof("crowd")
	local tifs = {}
	for _, b in ipairs(C.Bodies(now)) do if b.tif and IsValid(b.e) then tifs[#tifs + 1] = b end end
	local near = {}
	if on then
		for i = 1, #tifs do
			local a = tifs[i]
			for j = i + 1, #tifs do
				local b = tifs[j]
				local dx, dy, dz = math.abs(a.pos.x - b.pos.x), math.abs(a.pos.y - b.pos.y), math.abs(a.pos.z - b.pos.z)
				if dx < C.APART and dy < C.APART and dz < 60 then
					near[a.e], near[b.e] = true, true
					if dx < C.OVERLAP and dy < C.OVERLAP then
						local ov = a.e.tifCrowdOv or {}
						a.e.tifCrowdOv = ov
						ov[b.e] = ov[b.e] or now
						if now - ov[b.e] >= C.GHOST_AFTER or root_clip(a.e) or root_clip(b.e) then
							ghost(a.e, now)
							ghost(b.e, now)
						end
						if now - ov[b.e] >= C.UNSTACK_AFTER and not unstacking(a.e) and not unstacking(b.e) then
							local ia, ib = idle_soldier(a.e), idle_soldier(b.e)
							local mover = (ia and ib) and (a.e:EntIndex() > b.e:EntIndex() and a.e or b.e) or (ia and a.e) or (ib and b.e)
							if mover then C.Unstack(mover, now) end
						end
					elseif a.e.tifCrowdOv then
						a.e.tifCrowdOv[b.e] = nil
					end
				elseif a.e.tifCrowdOv then
					a.e.tifCrowdOv[b.e] = nil
				end
			end
		end
	end
	for _, b in ipairs(tifs) do
		local e = b.e
		if not near[e] then e.tifCrowdOv = nil end
		local g = e.tifCrowdGhost
		if g and (not on or (not near[e] and now - g.t >= C.GHOST_MIN)) then unghost(e) end
	end
	unprof()
end

timer.Create("tif_crowd_tick", 0.25, 0, function()
	if TIF.AIDisabled and TIF.AIDisabled() then return end
	local ok, err = pcall(C.Tick, CurTime())
	if not ok and TIF.Error then TIF.Error("crowd: ", tostring(err)) end
end)

cvars.AddChangeCallback("tif_crowd", function(_, _, new)
	if new ~= "0" then return end
	for _, e in ipairs(ents.GetAll()) do if e.tifCrowdGhost then unghost(e) end end
end, "tif_crowd")
