local TIF = TIF
local Act = TIF.Action

TIF.TransMW = TIF.TransMW or {}
local T = TIF.TransMW

T.TURN_MIN = 60
T.TURN_RESIDUAL = 50
T.COMBAT_RATE = 1.5
T.STOP_TAGS = { post = true, patrol = true, investigate = true, search = true, hold = true, advance = true,
	shift = true, back_off = true, maneuver = true, move = true, close = true, flee = true, formation = true }
T.START_TAGS = { post = true, patrol = true, investigate = true, search = true, hold = true, advance = true,
	shift = true, back_off = true, formation = true, maneuver = true, move = true, close = true }
T.STOP_SLACK = 10
T.STOP_WINDOW = 45

local NUMPAD = { [8] = 0, [7] = 45, [4] = 90, [1] = 135, [2] = 180, [3] = -135, [6] = -90, [9] = -45 }
T.STRAFE_SETS = { walk = true, jog = true, cwalk = true, cfast = true }
T.PRONE_TURN_MIN = 30
T.PRONE_TURN_ONE = 135

local function curve_end(c)
	local cv = c.curve
	if not cv or #cv < 3 then return 0, 0, 0 end
	return cv[#cv - 2], cv[#cv - 1], cv[#cv]
end

T.SETTLE_TAIL = 0.2
local settleOf = {}
function T.SettleU(c)
	if not c then return 1 end
	local v = settleOf[c]
	if v then return v end
	local cv = c.curve
	local n = cv and math.floor(#cv / 3) or 0
	if n < 3 or not c.frames or c.frames < 4 then
		settleOf[c] = 1
		return 1
	end
	local ex, ey, er = cv[(n - 1) * 3 + 1], cv[(n - 1) * 3 + 2], cv[(n - 1) * 3 + 3]
	local k = n - 1
	for i = n - 1, 0, -1 do
		local dx, dy = cv[i * 3 + 1] - ex, cv[i * 3 + 2] - ey
		if dx * dx + dy * dy > 4 or math.abs(cv[i * 3 + 3] - er) > 3 then break end
		k = i
	end
	v = math.Clamp(k * 3 / (c.frames - 1), 0.05, 1)
	settleOf[c] = v
	return v
end
local function settle_stop(npc, name)
	local a = npc.tifAct
	if not a then return end
	local c = TIF.GTG.Clip(name, npc.tifHomeHost)
	local u = T.SettleU(c)
	if u >= 1 then return end
	a.warpU = u
	a.stopU = math.min(1, u + T.SETTLE_TAIL / math.max(0.1, a.dur or (c and c.dur) or 1))
end
T.SettleStop = settle_stop

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

			local dist = math.sqrt(x * x + y * y)
			local dir = (dist > 1) and math.deg(math.atan2(y, x)) or (n and NUMPAD[n] or 0)

			if n and NUMPAD[n] and dist < 45 and kind == "stop" and T.STRAFE_SETS[set] then dir = NUMPAD[n] end
			local e = { name = name, yaw = r, dur = c.dur, dist = dist, dir = dir, n = n }

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

local function lit(npc, set)
	if (set == "calm" or set == "alert") and npc:GetNW2Bool("tif_light", false) and not pistol(npc) then
		local s = sets(npc.tifHomeHost)
		if s.turn[set .. "f"] or s.start[set .. "f"] then return set .. "f" end
	end
	return set
end

local function move_set(npc, speed)
	if npc:GetTIFStance() == TIF.Anim.STANCE_CROUCH then
		if pistol(npc) or relaxed(npc) then return nil end
		if speed == "tactical" or speed == "walk" then return "cwalk" end
		if speed == "run" or speed == "aimrun" or speed == "sprint" then return "cfast" end
		return nil
	end
	if speed == "walk" and relaxed(npc) then return lit(npc, "calm") end
	if speed == "alert" then return lit(npc, "alert") end

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

T.FIGHT_STOP = { run = "jog" }
function T.FightStopSet(npc, set)
	local alt = set and T.FIGHT_STOP[set]
	if alt and npc.tifAware == TIF.AWARE.ENGAGED and sets(npc.tifHomeHost).stop[alt] then return alt end
	return set
end

local function mark(npc) if npc.tifAct then npc.tifAct.trans = true end end

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

		local d = math.abs(math.AngleDifference(diff, e.yaw))
		if math.abs(e.yaw) > 170 then d = math.min(d, math.abs(math.AngleDifference(diff, -e.yaw))) end
		if not bd or d < bd then best, bd = e, d end
	end
	if not best or bd > T.TURN_RESIDUAL then return false end

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

	if not best or bd > 30 or best.dist + 20 > len then return false end

	local yaw0 = npc:GetAngles().y
	local d = Act.Play(npc, best.name, { root = true, clear = true })
	if not d then return false end
	mark(npc)
	local v = T.ExitVel(TIF.GTG.Clip(best.name, npc.tifHomeHost), yaw0)
	npc.tifStartExit = v and { vel = v, doneAt = CurTime() + d } or nil
	return true
end

function T.ExitVel(c, yaw0, u)
	if not c or not c.curve or #c.curve < 9 or not c.frames or c.frames < 4 then return nil end
	local G = TIF.GTG
	local f = math.max(3, math.floor(math.Clamp(u or 1, 0, 1) * (c.frames - 1)))
	local dx = G.ClipCurve(c, f, 1) - G.ClipCurve(c, f - 3, 1)
	local dy = G.ClipCurve(c, f, 2) - G.ClipCurve(c, f - 3, 2)
	local dt = 3 * c.dur / f
	if dt <= 0 then return nil end
	local r = math.rad(yaw0)
	local cs, sn = math.cos(r), math.sin(r)
	local v = Vector((dx * cs - dy * sn) / dt, (dx * sn + dy * cs) / dt, 0)
	if v:Length2DSqr() < 25 * 25 then return nil end
	return v
end

T.STANCE_TURN_MIN = 35
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

T.REV_MIN = 130
T.REV_SPEED = 45
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

	local name = best.name
	if math.random() < 0.5 then
		local other = string.gsub(name, "_([lr])_(%d)$", function(f, n) return "_" .. (f == "l" and "r" or "l") .. "_" .. n end)
		if TIF.GTG.Clip(other, npc.tifHomeHost) then name = other end
	end
	local endYaw = yaw + best.yaw
	if turns and faceYaw then endYaw = faceYaw end
	return best, name, endYaw
end

function T.Stop(npc, m)
	if prone_ready(npc) then return prone_stop(npc, m, false) end
	if not T.Use(npc) or not free(npc) or not T.STOP_TAGS[m.tag or ""] or not m.goal then return nil end
	local set = T.FightStopSet(npc, move_set(npc, m.speed))
	local list = set and sets(npc.tifHomeHost).stop[set]
	if not list then return nil end

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

	if dist > math.max(best.dist + T.STOP_SLACK, T.STOP_WINDOW) then return nil end
	local d = Act.Play(npc, name, { root = true, to = { pos = Vector(m.goal.x, m.goal.y, npc:GetPos().z), yaw = endYaw }, clear = true })
	if not d then return nil end
	mark(npc)
	settle_stop(npc, name)
	return d
end

function T.StopHere(npc, m)
	if prone_ready(npc) then return prone_stop(npc, m, true) ~= nil end
	if not T.Use(npc) or not free(npc) or not T.STOP_TAGS[m.tag or ""] then return false end
	local v = npc.loco:GetVelocity()
	if v:Length2DSqr() < 30 * 30 then return false end
	local set = T.FightStopSet(npc, move_set(npc, m.speed))
	local list = set and sets(npc.tifHomeHost).stop[set]
	if not list then return false end
	local yaw = npc:GetAngles().y
	local best, name, endYaw = pick_stop(npc, set, list, math.AngleDifference(v:Angle().y, yaw), m.faceYaw)
	if not best then return false end
	local d = Act.Play(npc, name, { root = true, clear = true })
	if not d then return false end

	if npc.tifAct and m.faceYaw then
		local a = npc.tifAct
		a.warp = { dx = 0, dy = 0, dyaw = math.AngleDifference(endYaw, yaw + best.yaw) }
	end
	mark(npc)
	settle_stop(npc, name)
	return true
end
