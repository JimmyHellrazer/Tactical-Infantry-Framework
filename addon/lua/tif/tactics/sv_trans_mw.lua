-- Turns in place, starts and stops with MW19's own transition clips (MW19 body), so feet stop sliding when a
-- soldier turns on the spot, sets off or arrives. Called from TIF.Move (sv_move.lua):
--   T.Turn(npc, wantYaw)       standing still and needing to face far off: a turn clip (picked by its measured
--                              yaw, the rest blended in so he ends exactly on wantYaw)
--   T.Start(npc, m)            a fresh path from a standstill: the start clip toward the path's first leg
--   T.Stop(npc, m)             close to the goal on the last leg: the stop clip, warped to end on the goal (and
--                              on m.faceYaw, the post's facing, when the goal has one)
-- Sets by posture: calm (relaxed walk, stealth patrol), alert (MW19 alert walk), walk / jog (weapon-up strafe
-- walk / jog: the body keeps its facing), stand / pstl / crouch turns. Clips: mwt_* (manifest trans_family).
-- While one plays the action is marked trans: path following holds and facing code leaves the body to the clip.

local TIF = TIF
local Act = TIF.Action

TIF.TransMW = TIF.TransMW or {}
local T = TIF.TransMW

T.TURN_MIN = 60          -- degrees off before a turn clip is used (smaller turns: the normal yaw rate)
T.TURN_RESIDUAL = 50     -- at most this much is blended in on top of the clip's own turn
T.COMBAT_RATE = 1.5      -- turns while fighting play faster
T.STOP_TAGS = { post = true, patrol = true, investigate = true, search = true, hold = true, advance = true,
	shift = true, back_off = true, maneuver = true, move = true, close = true, flee = true, formation = true }
T.START_TAGS = { post = true, patrol = true, investigate = true, search = true, hold = true, advance = true,
	shift = true, back_off = true, formation = true, maneuver = true, move = true, close = true }
T.STOP_SLACK = 10        -- start the stop this much before its own travel runs out
T.STOP_WINDOW = 45       -- ...and at the latest this close (TIF counts a move as arrived within ~37)

local NUMPAD = { [8] = 0, [7] = 45, [4] = 90, [1] = 135, [2] = 180, [3] = -135, [6] = -90, [9] = -45 }
T.STRAFE_SETS = { walk = true, jog = true, cwalk = true, cfast = true }
T.PRONE_TURN_MIN = 30
T.PRONE_TURN_ONE = 135

-- Measured end of a clip's root curve: x, y, yaw.
local function curve_end(c)
	local cv = c.curve
	if not cv or #cv < 3 then return 0, 0, 0 end
	return cv[#cv - 2], cv[#cv - 1], cv[#cv]
end

-- Per host: { turn = { set = { {name, yaw, dur} } }, start = { set = { {name, dir, dist, yaw} } }, stop = ... }
local cache = {}
local function sets(host)
	local s = cache[host]
	if s then return s end
	s = { turn = {}, start = {}, stop = {}, rev = {} }
	for name, c in pairs(TIF.GTG.Clips(host) or {}) do
		local kind, set, rest = string.match(name, "^mwt_(%a+)_(%a+)_(.+)$")
		if kind and s[kind] then
			local x, y, r = curve_end(c)
			local n = tonumber(string.match(rest, "(%d)$") or "")
			-- Direction: the measured travel, except for clips that hardly travel and carry their numpad direction in
			-- the name (MW22 AI strafe stops drift 10-40 units, at angles up to 60 deg off their direction).
			local dist = math.sqrt(x * x + y * y)
			local dir = (dist > 1) and math.deg(math.atan2(y, x)) or (n and NUMPAD[n] or 0)
			-- (Strafe stops only: calm / alert stops number the turn they end on.)
			if n and NUMPAD[n] and dist < 45 and kind == "stop" and T.STRAFE_SETS[set] then dir = NUMPAD[n] end
			local e = { name = name, yaw = r, dur = c.dur, dist = dist, dir = dir, n = n }
			-- Reversals (mwt_rev_<set>_<a>_<b>): from numpad a to b; path following takes over at code_move.
			if kind == "rev" then
				local a, b = string.match(rest, "^(%d)_(%d)$")
				e.from, e.to = NUMPAD[tonumber(a or "")], NUMPAD[tonumber(b or "")]
				e.handU = 0.7
				for _, tg in ipairs(c.tags or {}) do
					local ev = istable(tg[4]) and tg[4].MoveEvent
					if ev == "code_move" then e.handU = tg[2] break end
				end
			end
			s[kind][set] = s[kind][set] or {}
			table.insert(s[kind][set], e)
		end
	end
	cache[host] = s
	return s
end
T.Sets = sets

function T.Use(npc)
	return npc.tifHomeHost ~= nil and npc.tifHostId == npc.tifHomeHost and TIF.GTG.IsVB(npc.tifHostId)
end

local function pistol(npc)
	local def = npc.tifWep and TIF.GTG.WeaponDef(npc.tifWep.class)
	return def and string.find(string.lower(tostring(def.hold or "")), "pistol", 1, true) ~= nil
end

local function free(npc)
	return not (npc.tifAct or npc.tifCov or npc.tifVeh or npc.tifProne or npc.tifDowned or npc.tifActivity
		or npc.tifPassiveBusy or npc.tifDying or npc.tifLeaving or npc.tifBoard)
end

local function relaxed(npc) return npc.tifMode == TIF.Anim.MODE_RELAXED end

-- Flashlight on: the calm / alert sets' flashlight versions (calmf / alertf) where they exist.
local function lit(npc, set)
	if (set == "calm" or set == "alert") and npc:GetNW2Bool("tif_light", false) and not pistol(npc) then
		local s = sets(npc.tifHomeHost)
		if s.turn[set .. "f"] or s.start[set .. "f"] then return set .. "f" end
	end
	return set
end

-- The movement set for the current gait.
local function move_set(npc, speed)
	if npc:GetTIFStance() == TIF.Anim.STANCE_CROUCH then
		if pistol(npc) or relaxed(npc) then return nil end
		if speed == "tactical" or speed == "walk" then return "cwalk" end
		if speed == "run" or speed == "aimrun" or speed == "sprint" then return "cfast" end
		return nil
	end
	if speed == "walk" and relaxed(npc) then return lit(npc, "calm") end
	if speed == "alert" then return lit(npc, "alert") end
	-- Pistol: MW19's AI exposed-pistol starts / stops for its runs (pstljog / pstlrun); its aimed walk has none.
	if pistol(npc) then
		if speed == "sprint" then return "pstlrun" end
		if speed == "run" or speed == "aimrun" then return "pstljog" end
		return nil
	end
	if speed == "tactical" then return "walk" end
	if speed == "run" or speed == "aimrun" then return "jog" end
	if speed == "sprint" then return "run" end
	return nil
end
T.MoveSet = move_set

local function mark(npc) if npc.tifAct then npc.tifAct.trans = true end end

-- Turn ------------------------------------------------------------------------------------------------------
-- Returns true if a turn clip started.
function T.Turn(npc, want)
	if T.ProneReady and T.ProneReady(npc) then return T.ProneTurn(npc, want) end
	if not T.Use(npc) or not free(npc) then return false end
	local cur = npc:GetAngles().y
	local diff = math.AngleDifference(want, cur)
	if math.abs(diff) < T.TURN_MIN then return false end
	local set
	if npc:GetTIFStance() == TIF.Anim.STANCE_CROUCH then set = "crouch"
	elseif pistol(npc) then set = "pstl"
	elseif relaxed(npc) then set = "calm"
	elseif npc.tifAware ~= TIF.AWARE.ENGAGED and npc.tifHomeHost and TIF.GTG.Clip("mwt_turn_alert_4", npc.tifHomeHost)
		and (npc.tifAware == TIF.AWARE.SUSPICIOUS or npc.tifAware == TIF.AWARE.SEARCHING) then set = "alert"
	else set = "stand" end
	set = lit(npc, set)
	local list = sets(npc.tifHomeHost).turn[set] or sets(npc.tifHomeHost).turn.stand
	if not list then return false end
	local best, bd
	for _, e in ipairs(list) do
		-- 180s come as 2l (+180) and 2r (-180): measure both ways round.
		local d = math.abs(math.AngleDifference(diff, e.yaw))
		if math.abs(e.yaw) > 170 then d = math.min(d, math.abs(math.AngleDifference(diff, -e.yaw))) end
		if not bd or d < bd then best, bd = e, d end
	end
	if not best or bd > T.TURN_RESIDUAL then return false end
	-- The turn the right way round for 180s: 2l for left turns, 2r for right.
	if math.abs(best.yaw) > 170 then
		for _, e in ipairs(list) do
			if math.abs(e.yaw) > 170 and (e.yaw > 0) == (diff > 0) then best = e break end
		end
	end
	local rate = npc.tifAware == TIF.AWARE.ENGAGED and T.COMBAT_RATE or 1
	local d = Act.Play(npc, best.name, { root = true, to = { pos = npc:GetPos(), yaw = want }, clear = true, rate = rate })
	if not d then return false end
	mark(npc)
	return true
end

-- Start -----------------------------------------------------------------------------------------------------
-- The travel direction of the path's first leg relative to the facing, and how far it runs straight.
local function first_leg(npc)
	local path = npc.tifPath
	local seg = path:GetCurrentGoal() or path:FirstSegment()
	if not seg then return nil end
	local p = seg.pos
	local to = p - npc:GetPos()
	to.z = 0
	local len = to:Length()
	if len < 1 then return nil end
	return math.AngleDifference(to:Angle().y, npc:GetAngles().y), len
end

-- Prone (MW22 / MW19 MP crawl starts and stops, on the prone pelvis like the crawl loops): settled prone, no clip
-- playing. mwp_cstart_<dir> by its measured travel, mwp_cstop_<l|r> onto the goal.
local function prone_ready(npc)
	local p = npc.tifProne
	return p and p.phase == 2 and not npc.tifAct and T.Use(npc) and not npc.tifDowned and not npc.tifDying
end

local function prone_start(npc)
	local dir, len = first_leg(npc)
	if not dir then return false end
	local best, bd
	for name, c in pairs(TIF.GTG.Clips(npc.tifHomeHost) or {}) do
		if string.sub(name, 1, 11) == "mwp_cstart_" then
			local x, y = curve_end(c)
			if x * x + y * y > 1 then
				local d = math.abs(math.AngleDifference(dir, math.deg(math.atan2(y, x))))
				if not bd or d < bd then best, bd = { name = name, dist = math.sqrt(x * x + y * y) }, d end
			end
		end
	end
	if not best or bd > 35 or best.dist + 10 > len then return false end
	local d = Act.Play(npc, best.name, { root = true, clear = true })
	if not d then return false end
	mark(npc)
	return true
end

local function prone_stop(npc, m, here)
	local name = "mwp_cstop_" .. (math.random() < 0.5 and "l" or "r")
	if not TIF.GTG.Clip(name, npc.tifHomeHost) then return nil end
	if npc.loco:GetVelocity():Length2DSqr() < 10 * 10 then return nil end
	if not here then
		if not m.goal or npc:GetPos():DistToSqr(m.goal) > 30 * 30 then return nil end
	end
	local opts = { root = true, clear = true }
	if not here and m.goal then opts.to = { pos = Vector(m.goal.x, m.goal.y, npc:GetPos().z), yaw = npc:GetAngles().y } end
	local d = Act.Play(npc, name, opts)
	if not d then return nil end
	mark(npc)
	return d
end

T.ProneReady = prone_ready

function T.ProneTurn(npc, want)
	local cur = npc:GetAngles().y
	local diff = math.AngleDifference(want, cur)
	if math.abs(diff) < T.PRONE_TURN_MIN or npc.tifBipod then return false end
	local name = diff > 0 and "mwp_turn_l" or "mwp_turn_r"
	local c = TIF.GTG.Clip(name, npc.tifHomeHost)
	if not c then return false end
	local _, _, r = curve_end(c)
	if math.abs(r) < 10 then r = diff > 0 and 90 or -90 end
	local endYaw = math.abs(diff) <= T.PRONE_TURN_ONE and want or (cur + r)
	local rate = npc.tifAware == TIF.AWARE.ENGAGED and T.COMBAT_RATE or 1
	local d = Act.Play(npc, name, { root = true, to = { pos = npc:GetPos(), yaw = endYaw }, clear = true, rate = rate })
	if not d then return false end
	mark(npc)
	return true
end

-- Returns true if a start clip started (path following waits for it).
function T.Start(npc, m)
	if prone_ready(npc) then return prone_start(npc) end
	if not T.Use(npc) or not free(npc) or not T.START_TAGS[m.tag or ""] then return false end
	if npc.loco:GetVelocity():Length2DSqr() > 15 * 15 then return false end
	local set = move_set(npc, m.speed)
	local list = set and sets(npc.tifHomeHost).start[set]
	if not list then return false end
	local dir, len = first_leg(npc)
	if not dir then return false end
	local best, bd
	for _, e in ipairs(list) do
		local d = math.abs(math.AngleDifference(dir, e.dir))
		if not bd or d < bd then best, bd = e, d end
	end
	-- Off by too much, or the leg is shorter than the clip travels (a corner comes first): just walk.
	if not best or bd > 30 or best.dist + 20 > len then return false end
	-- Calm / alert starts turn the body onto the path: aim the clip's end straight down the leg.
	local d = Act.Play(npc, best.name, { root = true, clear = true })
	if not d then return false end
	mark(npc)
	return true
end

-- Stance --------------------------------------------------------------------------------------------------------
-- Standing still and going from standing to crouched or back: MW19's AI stance change (mwk_*) instead of the idles
-- cross-fading. Going down he can turn with it (MW22's 2 / 4 / 6: face behind / left / right as he crouches) when
-- he means to face somewhere else (npc.tifFace). Returns true if one started (it turns the body itself; the brain
-- sets the stance as usual).
T.STANCE_TURN_MIN = 35   -- turn wanted before a turning variant beats the straight one
function T.Stance(npc, from, to)
	if not T.Use(npc) or not free(npc) then return false end
	if npc.loco:GetVelocity():Length2DSqr() > 20 * 20 or (TIF.Move.Moving and TIF.Move.Moving(npc)) then return false end
	local host = npc.tifHomeHost
	local name
	if from == TIF.Anim.STANCE_STAND and to == TIF.Anim.STANCE_CROUCH then
		if pistol(npc) and TIF.GTG.Clip("mwk_down_pstl", host) then
			name = "mwk_down_pstl"
		else
			local want = 0
			if npc.tifFace then
				local d = npc.tifFace - npc:GetPos()
				want = math.AngleDifference(d:Angle().y, npc:GetAngles().y)
			end
			local best, be
			for _, n in ipairs({ "8", "2", "4", "6" }) do
				local c = TIF.GTG.Clip("mwk_down_" .. n, host)
				if c then
					local e = math.abs(math.AngleDifference(want, (c.move and c.move[3]) or 0))
					if n == "8" then e = e - T.STANCE_TURN_MIN end
					if not be or e < be then best, be = "mwk_down_" .. n, e end
				end
			end
			name = best
		end
	elseif from == TIF.Anim.STANCE_CROUCH and to == TIF.Anim.STANCE_STAND then
		name = TIF.GTG.Clip("mwk_up_8", host) and "mwk_up_8" or nil
	end
	if not name then return false end
	local d = Act.Play(npc, name, { root = true, clear = true })
	if not d then return false end
	mark(npc)
	return true
end

-- Reverse ---------------------------------------------------------------------------------------------------
-- Strafing (body keeps its facing: aiming somewhere) and the path now wants the opposite way: MW19's AI strafe
-- reversal (slow, plant, push off the other way) instead of the legs snapping round. The path waits until the
-- clip's code_move note, then takes over (sv_move: a.handU). Returns true if one started.
T.REV_MIN = 130        -- degrees between where he's going and where the path wants him
T.REV_SPEED = 45       -- at least this fast (a real change of direction, not a shuffle)
T.REV_COOLDOWN = 1.5
local function rev_set(npc, speed)
	if npc:GetTIFStance() == TIF.Anim.STANCE_CROUCH or relaxed(npc) or pistol(npc) or not npc.tifFace then return nil end
	local cqb = npc:GetNW2Bool("tif_cqb", false)
	if speed == "tactical" then return cqb and "cqbwalk" or "walk" end
	if speed == "run" or speed == "aimrun" then return cqb and "cqbfast" or "jog" end
	return nil
end
T.RevSet = rev_set

function T.Reverse(npc, m, now)
	if not T.Use(npc) or not free(npc) or not m.goal then return false end
	if now - (npc.tifRevAt or -99) < T.REV_COOLDOWN then return false end
	local set = rev_set(npc, m.speed)
	local list = set and sets(npc.tifHomeHost).rev[set]
	if not list then return false end
	local v = npc.loco:GetVelocity()
	v.z = 0
	if v:LengthSqr() < T.REV_SPEED * T.REV_SPEED then return false end
	local seg = npc.tifPath and npc.tifPath:GetCurrentGoal()
	if not seg then return false end
	local to = seg.pos - npc:GetPos()
	to.z = 0
	if to:LengthSqr() < 40 * 40 or npc:GetPos():DistToSqr(m.goal) < 120 * 120 then return false end
	local yaw = npc:GetAngles().y
	local vrel = math.AngleDifference(v:Angle().y, yaw)
	local drel = math.AngleDifference(to:Angle().y, yaw)
	if math.abs(math.AngleDifference(drel, vrel)) < T.REV_MIN then return false end
	local best, bd
	for _, e in ipairs(list) do
		if e.from and e.to then
			local d = math.abs(math.AngleDifference(vrel, e.from)) + math.abs(math.AngleDifference(drel, e.to))
			if not bd or d < bd then best, bd = e, d end
		end
	end
	if not best or bd > 80 then return false end
	local d = Act.Play(npc, best.name, { root = true, clear = true })
	if not d then return false end
	mark(npc)
	npc.tifAct.handU = best.handU
	npc.tifRevAt = now
	return true
end

-- Stop ------------------------------------------------------------------------------------------------------
-- The stop clip for travel direction `travel` (relative to the facing), turning onto faceYaw if given (calm /
-- alert stops turn; strafe stops keep the facing). Returns entry, clip name (either foot), end yaw.
local function pick_stop(npc, set, list, travel, faceYaw)
	local yaw = npc:GetAngles().y
	local turn = 0
	local turns = set == "calm" or set == "alert" or set == "calmf" or set == "alertf" or set == "pstljog" or set == "pstlrun"
		or set == "run"
	if turns and faceYaw then turn = math.AngleDifference(faceYaw, yaw) end
	local best, bd
	for _, e in ipairs(list) do
		local d = math.abs(math.AngleDifference(travel, e.dir)) + math.abs(math.AngleDifference(turn, e.yaw)) * 0.5
		if not bd or d < bd then best, bd = e, d end
	end
	if not best or bd > 60 then return nil end
	-- Both feet: the other variant half the time (the server doesn't know the walk phase).
	local name = best.name
	if math.random() < 0.5 then
		local other = string.gsub(name, "_([lr])_(%d)$", function(f, n) return "_" .. (f == "l" and "r" or "l") .. "_" .. n end)
		if TIF.GTG.Clip(other, npc.tifHomeHost) then name = other end
	end
	local endYaw = yaw + best.yaw
	if turns and faceYaw then endYaw = faceYaw end
	return best, name, endYaw
end
-- Returns the duration if a stop clip started (the move ends when it does).
function T.Stop(npc, m)
	if prone_ready(npc) then return prone_stop(npc, m, false) end
	if not T.Use(npc) or not free(npc) or not T.STOP_TAGS[m.tag or ""] or not m.goal then return nil end
	local set = move_set(npc, m.speed)
	local list = set and sets(npc.tifHomeHost).stop[set]
	if not list then return nil end
	-- Cheap out until the end is near.
	if npc:GetPos():DistToSqr(m.goal) > T.STOP_WINDOW * T.STOP_WINDOW then return nil end
	local path = npc.tifPath
	local last = path:LastSegment()
	local cur = path:GetCurrentGoal()
	if not last or not cur or cur.pos:DistToSqr(last.pos) > 4 then return nil end
	local to = m.goal - npc:GetPos()
	to.z = 0
	local dist = to:Length()
	local yaw = npc:GetAngles().y
	local best, name, endYaw = pick_stop(npc, set, list, math.AngleDifference(to:Angle().y, yaw), m.faceYaw)
	if not best then return nil end
	-- Not there yet: wait until the clip's own travel covers what's left (or the move is about to count as
	-- arrived: TIF arrives within ~37, so short stops start there and the warp covers the rest).
	if dist > math.max(best.dist + T.STOP_SLACK, T.STOP_WINDOW) then return nil end
	local d = Act.Play(npc, name, { root = true, to = { pos = Vector(m.goal.x, m.goal.y, npc:GetPos().z), yaw = endYaw }, clear = true })
	if not d then return nil end
	mark(npc)
	return d
end

-- Stopping short of the goal (a post, hold spot or patrol point counts as reached within 80-90, so the
-- brain stops the move there): the stop clip from where he is, on its own travel. Called by Move.Stop.
-- Returns true if one started.
function T.StopHere(npc, m)
	if prone_ready(npc) then return prone_stop(npc, m, true) ~= nil end
	if not T.Use(npc) or not free(npc) or not T.STOP_TAGS[m.tag or ""] then return false end
	local v = npc.loco:GetVelocity()
	if v:Length2DSqr() < 30 * 30 then return false end
	local set = move_set(npc, m.speed)
	local list = set and sets(npc.tifHomeHost).stop[set]
	if not list then return false end
	local yaw = npc:GetAngles().y
	local best, name, endYaw = pick_stop(npc, set, list, math.AngleDifference(v:Angle().y, yaw), m.faceYaw)
	if not best then return false end
	local d = Act.Play(npc, name, { root = true, clear = true })
	if not d then return false end
	-- The facing it ends on: the clip's own turn, eased onto the post's facing when it has one.
	if npc.tifAct and m.faceYaw then
		local a = npc.tifAct
		a.warp = { dx = 0, dy = 0, dyaw = math.AngleDifference(endYaw, yaw + best.yaw) }
	end
	mark(npc)
	return true
end
