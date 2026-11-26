local TIF = TIF
local Act = TIF.Action
local Cover = TIF.Cover
local Move = TIF.Move
local Weapon = TIF.Weapon
local A = TIF.Anim
local Prof = TIF.Prof
local CB = TIF.CoverBehave

CB.MW = CB.MW or {}
local MW = CB.MW

MW.WALL_DIST = 16
MW.EDGE_OFF = { ls = 12, rs = 10, lc = 12, rc = 10 }
MW.AIM_YAW_MAX = 60
local UP40 = Vector(0, 0, 40)
local FLASHABLE = { idle = true, look = true, look_in = true, look_out = true, twitch = true, aim_in = true,
	aim = true, aim_out = true, blind = true }
local STILL_GOOD_EVERY = 1.5
local ARRIVE_LOOK = 170
MW.LEAN_ARRIVE = 0.6
MW.BUSY_SHARE = 0.35
MW.SHOCK_CHANCE = 0.35

local function yaw_dir(yaw)
	local r = math.rad(yaw)
	return Vector(math.cos(r), math.sin(r), 0)
end

local function clip_on_body(npc, name)
	return TIF.GTG.Clip(name, npc.tifHomeHost)
end

function MW.Use(npc)
	local home = npc.tifHomeHost
	if not home or not TIF.GTG.IsVB(home) then return false end
	if npc.tifMwCover == nil then npc.tifMwCover = clip_on_body(npc, "mwc_ls_hide") ~= nil end
	return npc.tifMwCover
end

local function role(cov, r)
	if cov.pstl and cov.host then
		local n = "mwc_" .. cov.t .. "p_" .. r
		if TIF.GTG.Clip(n, cov.host) then return n end
	end
	return "mwc_" .. cov.t .. "_" .. r
end
MW.Role = role

local function clip(npc, cov, r)
	local n = role(cov, r)
	return clip_on_body(npc, n) and n or nil
end

local LEFT = { ls = true, lc = true }
local CORNER = { ls = true, rs = true, lc = true, rc = true }
local CROUCHED = { cr = true, lc = true, rc = true, st = true }
local OVER = { cr = true, st = true }
MW.CROUCH_CORNER = 0.4
local function has_type(cov, t) return cov.host and TIF.GTG.Clip("mwc_" .. t .. "_hide", cov.host) ~= nil end
local function cover_type(cov)
	if cov.high then
		local l = cov.side == "l"
		if cov.lowCorner and has_type(cov, l and "lc" or "rc") then return l and "lc" or "rc" end
		return l and "ls" or "rs"
	end
	if cov.pt and cov.pt.mid and has_type(cov, "st") then return "st" end
	return "cr"
end

local function hide_yaw(cov) return LEFT[cov.t] and cov.ny - 90 or cov.ny + 90 end
local function threat_yaw(cov) return cov.ny + 180 end

local function find_edge(pt, t, z)
	local n = pt.normal or yaw_dir(pt.ny)
	local tr = { mask = Cover.MASK }
	for d = 0, Cover.EDGE_STEP + 16, 4 do
		local a = pt.pos + t * d + Vector(0, 0, z)
		tr.start, tr.endpos = a, a - n * (Cover.HUG + 24)
		if not util.TraceLine(tr).Hit then return d end
	end
	return nil
end

local function place(cov)
	local pt = cov.pt
	local n = pt.normal or yaw_dir(pt.ny)
	local wall = pt.pos - n * Cover.HUG
	local node = wall + n * MW.WALL_DIST
	node.z = pt.pos.z
	if CORNER[cov.t] then
		local t = LEFT[cov.t] and yaw_dir(pt.ny - 90) or yaw_dir(pt.ny + 90)
		local e = LEFT[cov.t] and cov.edgeL or cov.edgeR
		if e then node = node + t * (e - (MW.EDGE_OFF[cov.t] or 10)) end
	end
	cov.origin = node
	cov.hy = hide_yaw(cov)
end

local function holds_pistol(npc)
	local def = npc.tifWep and TIF.GTG.WeaponDef(npc.tifWep.class)
	return def and string.find(string.lower(tostring(def.hold or "")), "pistol", 1, true) ~= nil or false
end
MW.HoldsPistol = holds_pistol

function MW.Prepare(npc, cov)
	cov.mw = true
	cov.host = npc.tifHomeHost
	cov.pstl = holds_pistol(npc)

	cov.lowCorner = math.random() < MW.CROUCH_CORNER + 0.3 * math.min(1, npc.tifSupp or 0)
	local pt = cov.pt
	if pt.high then
		cov.edgeL = pt.edgeL and find_edge(pt, yaw_dir(pt.ny - 90), Cover.HEAD) or nil
		cov.edgeR = pt.edgeR and find_edge(pt, yaw_dir(pt.ny + 90), Cover.HEAD) or nil

		if cov.side == "l" and not cov.edgeL and cov.edgeR then cov.side = "r" end
		if cov.side == "r" and not cov.edgeR and cov.edgeL then cov.side = "l" end
	end
	cov.t = cover_type(cov)
	place(cov)
	cov.shuffle = MW.PlanShuffle(npc, cov)
end

MW.SHUFFLE_MIN, MW.SHUFFLE_MAX = 50, 380

local TO_R = { rs = true, cr = true, st = true, rc = true }
local TO_L = { ls = true, cr = true, st = true, lc = true }
local SHUF_TO = { ls = { r = TO_R }, lc = { r = TO_R }, rs = { l = TO_L }, rc = { l = TO_L },
	cr = { l = TO_L, r = TO_R }, st = { l = TO_L, r = TO_R } }
local function travel(c) return c and math.sqrt(c.move[1] ^ 2 + c.move[2] ^ 2) or 0 end

function MW.PlanShuffle(npc, cov)
	local L = npc.tifLastCov
	if not L or CurTime() - L.time > 1.5 or npc:GetPos():DistToSqr(L.origin) > 30 * 30 then return nil end
	if math.abs(math.AngleDifference(cov.ny, L.ny)) > 20 then return nil end
	local delta = cov.origin - L.origin
	if math.abs(delta:Dot(yaw_dir(L.ny))) > 24 or math.abs(delta.z) > 16 then return nil end
	local lat = delta:Dot(yaw_dir(L.ny + 90))
	local dist = math.abs(lat)
	if dist < MW.SHUFFLE_MIN or dist > MW.SHUFFLE_MAX then return nil end
	local dir = lat > 0 and "r" or "l"
	local ok = SHUF_TO[L.t] and SHUF_TO[L.t][dir]
	if not (ok and ok[cov.t]) then return nil end
	local inN, loopN, outN = "mwc_" .. L.t .. "_to_shuf_" .. dir, "mwc_shuf_" .. dir, "mwc_shuf_" .. dir .. "_to_" .. cov.t
	local ci, cl, co = clip_on_body(npc, inN), clip_on_body(npc, loopN), clip_on_body(npc, outN)
	if not (ci and cl and co) then return nil end

	local up = Vector(0, 0, 20)
	local tr = util.TraceHull({ start = L.origin + up, endpos = cov.origin + up, mins = Vector(-10, -10, 0),
		maxs = Vector(10, 10, 30), mask = MASK_NPCSOLID, filter = npc })
	if tr.Hit then return nil end
	local step = math.max(8, travel(cl))
	local cycles = math.max(0, math.floor((dist - travel(ci) - travel(co)) / step + 0.5))
	return { inN = inN, loopN = loopN, outN = outN, cycles = math.min(cycles, 8) }
end

local function arrival_start(c)
	local mx, my, myaw = c.move[1], c.move[2], c.move[3]
	local r = math.rad(-myaw)
	local cs, sn = math.cos(r), math.sin(r)
	return Vector(-mx * cs + my * sn, -mx * sn - my * cs, 0), -myaw
end

local GAITS = { jog = true, run = true }

MW.CQB_WALK_MAX = 130
local function cqb_style(npc, cov)
	if npc.tifCQB or npc:GetNW2Bool("tif_cqb", false) then return true end
	if cov.indoor == nil then
		local B = TIF.Building
		cov.indoor = (B and B.Indoor and B.Indoor(cov.origin)) and true or false
	end
	return cov.indoor
end
MW.CqbStyle = cqb_style
local function arrivals(npc, cov, gait)
	cov.arrCache = cov.arrCache or {}
	local key = cov.t .. gait
	local list = cov.arrCache[key]
	if list then return list end
	list = {}
	for _, foot in ipairs({ "l", "r" }) do
		for _, n in ipairs({ "1", "2", "3", "4", "6", "7", "8", "9", "8l", "8r" }) do
			local name = role(cov, "arr_" .. gait .. "_" .. foot .. "_" .. n)
			local c = clip_on_body(npc, name)
			if c then
				local ps, sy = arrival_start(c)
				list[#list + 1] = { name = name, ps = ps, dist = ps:Length2D(), sy = sy, dur = c.dur }
			end
		end
	end
	cov.arrCache[key] = list
	return list
end

local function lean_arrivals(npc, cov)
	cov.arrCache = cov.arrCache or {}
	local key = cov.t .. "lean"
	if cov.arrCache[key] then return cov.arrCache[key] end
	local list = {}
	for _, n in ipairs({ "1", "2", "3", "4", "6", "7", "8", "9" }) do
		local name = role(cov, "arr_lean_" .. n)
		local c = clip_on_body(npc, name)
		if c then
			local ps, sy = arrival_start(c)
			list[#list + 1] = { name = name, ps = ps, dist = ps:Length2D(), sy = sy, dur = c.dur }
		end
	end
	cov.arrCache[key] = list
	return list
end

local function lean_spot(npc, cov)
	local c = clip_on_body(npc, role(cov, "lean_in"))
	if not c then return nil end
	local r = math.rad(cov.hy)
	local cs, sn = math.cos(r), math.sin(r)
	local p = cov.origin + Vector(c.move[1] * cs - c.move[2] * sn, c.move[1] * sn + c.move[2] * cs, 0)
	return p, threat_yaw(cov)
end
MW.LeanSpot = lean_spot

local function pick_arrival(npc, cov, speed, lean)
	local list, base, baseYaw
	if lean then
		base, baseYaw = lean_spot(npc, cov)
		list = base and lean_arrivals(npc, cov) or {}
		if #list == 0 then return nil end
	else

		if cqb_style(npc, cov) or speed < MW.CQB_WALK_MAX then
			list = arrivals(npc, cov, speed < MW.CQB_WALK_MAX and "cwalk" or "cfast")
		end
		if not list or #list == 0 then list = arrivals(npc, cov, speed > 160 and "run" or "jog") end
		if #list == 0 then list = arrivals(npc, cov, "jog") end
	end
	base, baseYaw = base or cov.origin, baseYaw or cov.hy
	local rel = npc:GetPos() - base
	rel.z = 0
	local r = math.rad(-baseYaw)
	local cs, sn = math.cos(r), math.sin(r)
	local q = Vector(rel.x * cs - rel.y * sn, rel.x * sn + rel.y * cs, 0)
	local qd = q:Length2D()
	local qy = math.AngleDifference(npc:GetAngles().y, baseYaw)
	local best, bestS
	for _, a in ipairs(list) do
		local dirErr = 0
		if qd > 4 and a.dist > 4 then
			local dot = (q.x * a.ps.x + q.y * a.ps.y) / (qd * a.dist)
			dirErr = math.deg(math.acos(math.Clamp(dot, -1, 1)))
		end
		local s = dirErr + 0.35 * math.abs(math.AngleDifference(qy, a.sy)) + 0.15 * math.abs(qd - a.dist)
		if not bestS or s < bestS then best, bestS = a, s end
	end
	return best, qd
end

local function pick_exit(npc, cov, yaw, sets)
	yaw = yaw or cov.ny
	local want = math.AngleDifference(yaw, cov.hy)

	if not sets then
		sets = { "exit_" }
		if cqb_style(npc, cov) then sets = { ((npc.tifSupp or 0) > 0.5) and "cfexit_" or "cexit_", "exit_" } end
	end
	for _, pre in ipairs(sets) do
		local best, bestE
		for n = 1, 9 do
			local name = role(cov, pre .. n)
			local c = clip_on_body(npc, name)
			if c and (c.move[1] ~= 0 or c.move[2] ~= 0) then
				local e = math.abs(math.AngleDifference(math.deg(math.atan2(c.move[2], c.move[1])), want))
				if not bestE or e < bestE then best, bestE = name, e end
			end
		end
		if best then return best, bestE end
	end
	return nil
end

MW.EXIT_COMMIT = 45
MW.EXIT_CUT = 0.5
MW.EXIT_WALK_CUT = 0.8
local function exit_goal(npc)
	local pos = npc:GetPos()
	local sq = npc.tifSquad
	local lead = sq and sq.leader
	if IsValid(lead) and lead ~= npc and not lead.tifDead and lead:GetPos():DistToSqr(pos) > 220 * 220 then return lead:GetPos() end
	local post = (npc.tifGuardPost and npc.tifGuardPost.pos) or npc.tifPost
	if post and post:DistToSqr(pos) > 150 * 150 then return post end
	return nil
end
MW.ExitGoal = exit_goal

function MW.PickCalmExit(npc, cov)
	local goal = exit_goal(npc)
	local yaw
	if goal then
		local d = goal - npc:GetPos()
		yaw = math.deg(math.atan2(d.y, d.x))
	end
	if cqb_style(npc, cov) then
		local n = pick_exit(npc, cov, yaw)
		return n, 1
	end
	if goal then
		local n, e = pick_exit(npc, cov, yaw, { "exit_" })
		if n and e <= MW.EXIT_COMMIT then return n, 1 end
	end
	local n = pick_exit(npc, cov, yaw, { "cexit_" })
	if n then return n, goal and 1 or MW.EXIT_WALK_CUT end
	n = pick_exit(npc, cov, yaw, { "exit_" })
	return n, MW.EXIT_CUT
end

MW.XIN_DIST = 75
MW.XIN_MAX_ERR = 60

function MW.PickXin(npc, cov, maxErr, yaw, crouched)
	if not cov.t then return nil end
	local want = math.AngleDifference(cov.hy, yaw or npc:GetAngles().y)
	if crouched == nil then crouched = npc:GetTIFStance() == A.STANCE_CROUCH end
	for _, st in ipairs(crouched and { "cr", "st" } or { "st", "cr" }) do
		local best, be, bt
		for k = 1, 12 do
			local n = "mwc_" .. cov.t .. "_xin_" .. st .. "_" .. k
			local c = clip_on_body(npc, n)
			if not c then break end
			local e = math.abs(math.AngleDifference(want, c.move[3] or 0))

			if not be or e < be - 1 or (math.abs(e - be) <= 1 and math.random() < 0.5) then best, be, bt = n, e, c.move[3] or 0 end
		end
		if best and be <= (maxErr or MW.XIN_MAX_ERR) then return best, bt end
	end
	return nil
end

local set_phase = function(npc, cov, phase, now) CB.SetPhase(npc, cov, phase, now) end

local function snap_home(npc, cov)
	npc:SetPos(cov.origin)
	npc:SetAngles(Angle(0, cov.hy, 0))
end

local function stance(npc, cov)

	local low = CROUCHED[cov.t] and not (cov.t == "st" and (cov.phase == "aim" or cov.phase == "aim_in"))
	npc.tifStance = low and A.STANCE_CROUCH or A.STANCE_STAND
	npc.tifHitboxPose = low and "crouch" or "aim"
end

local function aim_off(npc)
	npc.tifAimAt, npc.tifAimFree, npc.tifMuzzle = nil, nil, nil
	if npc:GetNW2Float("tif_aim_yaw", 0) ~= 0 then npc:SetNW2Float("tif_aim_yaw", 0) end
end

local function start_hide(npc, cov, now)
	aim_off(npc)
	set_phase(npc, cov, "idle", now)
	local n = clip(npc, cov, "hide")
	if n then Act.Loop(npc, n) end
	local p = npc.tifArch.coverPause
	local roleK = npc.tifRole == "base" and 0.6 or 1
	cov.nextAim = now + math.Rand(p[1], p[2]) * roleK * (1 + (npc.tifSupp or 0) * 1.5)
	cov.nextTwitch = cov.nextTwitch or now + math.Rand(5, 11)
end

local function one_shot(npc, cov, r, phase, now, opts)
	local n = clip(npc, cov, r)
	local d = n and Act.Play(npc, n, opts)
	if not d then return false end
	cov.phaseEnd = now + d
	set_phase(npc, cov, phase, now)
	return true
end

MW.SIDE_CHANCE = 0.2
MW.SIDE_EVERY = 12
MW.SIDE_PAST = 24
MW.SIDE_LOW_EDGE = 72
MW.SIDE_TURN_OK = 25
local SIDE_T = { ls = true, rs = true, cr = true }
local SIDE_HULL_MIN, SIDE_HULL_MAX = Vector(-12, -12, 4), Vector(12, 12, 36)
local SIDE_EYE = Vector(0, 0, 38)

local function side_spot(npc, cov, aimAt, enemy)
	local cands = {}
	if cov.t == "ls" or cov.t == "rs" then

		cands[1] = cov.origin + yaw_dir(cov.hy) * ((MW.EDGE_OFF[cov.t] or 10) + MW.SIDE_PAST)
	else
		local pt = cov.pt
		for _, s in ipairs(math.random() < 0.5 and { -90, 90 } or { 90, -90 }) do
			local t = yaw_dir(pt.ny + s)
			local e = find_edge(pt, t, 20)
			if e and e <= MW.SIDE_LOW_EDGE then cands[#cands + 1] = cov.origin + t * (e + MW.SIDE_PAST) end
		end
	end
	for _, p in ipairs(cands) do
		local ok = true

		local g = util.TraceLine({ start = p + Vector(0, 0, 24), endpos = p - Vector(0, 0, 32), mask = MASK_NPCSOLID_BRUSHONLY })
		if not g.Hit or math.abs(g.HitPos.z - cov.origin.z) > 18 then ok = false else p = Vector(p.x, p.y, g.HitPos.z) end

		if ok and util.TraceHull then
			local tr = util.TraceHull({ start = cov.origin, endpos = p, mins = SIDE_HULL_MIN, maxs = SIDE_HULL_MAX,
				mask = MASK_NPCSOLID, filter = npc })
			if tr.Hit then ok = false end
		end

		if ok then
			local tr = util.TraceLine({ start = p + SIDE_EYE, endpos = aimAt, mask = MASK_SHOT, filter = { npc, enemy } })
			if tr.Hit and tr.Entity ~= enemy then ok = false end
		end
		if ok and Move.Taken and Move.Taken(npc, p) then ok = false end
		if ok then return p end
	end
	return nil
end

function MW.SideOut(npc, cov, c, now)
	if not (SIDE_T[cov.t] and c and c.visible and IsValid(c.ent)) then return false end
	if not MW.PickXin(npc, cov, 180, nil, true) then return false end
	local p = side_spot(npc, cov, c.ent:WorldSpaceCenter(), c.ent)
	if not p or not Move.SetGoal(npc, p, "crouch", "cover") then return false end
	aim_off(npc)
	Act.Clear(npc)
	npc.tifStance, npc.tifHitboxPose = A.STANCE_CROUCH, "crouch"
	cov.sideAt = { pos = p }
	set_phase(npc, cov, "side_out", now)
	if TIF.Event then TIF.Event("cover", "beside-cover fight", npc, cov.t) end
	return true
end

local function side_in(npc, cov, now)
	local sd = cov.sideAt or {}
	local n = MW.PickXin(npc, cov, 180, nil, true)
	local d = n and Act.Play(npc, n, { root = true, noTrace = true, to = { pos = cov.origin, yaw = cov.hy } })
	cov.sideAt = nil
	npc.tifFace = nil
	if not d then

		local dist = npc:GetPos():Distance(cov.origin)
		d = math.Clamp(dist / 110, 0.12, 0.6)
		cov.slide = { p0 = npc:GetPos(), y0 = npc:GetAngles().y, t0 = now, dur = d }
	end
	cov.phaseEnd = now + d
	set_phase(npc, cov, "enter", now)
end

local function side_back(npc, cov, now)
	Move.Stop(npc)
	npc.tifFire.want = false
	aim_off(npc)
	local _, turn = MW.PickXin(npc, cov, 180, nil, true)
	local sd = cov.sideAt
	if turn and sd then
		sd.yaw = cov.hy - turn
		if math.abs(math.AngleDifference(sd.yaw, npc:GetAngles().y)) > MW.SIDE_TURN_OK then
			set_phase(npc, cov, "side_turn", now)
			return
		end
	end
	side_in(npc, cov, now)
end

local PAIN_HIDDEN = { idle = true, look = true, look_in = true, look_out = true, twitch = true }
local PAIN_EXPOSED = { aim_in = true, aim = true }
function MW.Pain(npc, region, dir, big, now)
	local cov = npc.tifCov
	if not (cov and cov.mw and cov.t) then return nil end
	local phase = cov.phase
	local exposed = PAIN_EXPOSED[phase]
	if not exposed and not PAIN_HIDDEN[phase] then return nil end
	local g = big and "lg" or "md"
	local r
	for _, reg in ipairs({ region, "torso" }) do
		for _, gg in ipairs({ g, g == "lg" and "md" or "lg" }) do
			local name = "pain_" .. reg .. "_" .. gg .. "_" .. dir .. (exposed and "_hide" or "")
			if clip(npc, cov, name) then r = name break end
		end
		if r then break end
	end
	if not r then return nil end

	if big and math.random() < MW.SHOCK_CHANCE and clip(npc, cov, "shock") then r = "shock" end
	if exposed then
		npc.tifFire.want = false
		aim_off(npc)
	end
	local d = one_shot(npc, cov, r, r == "shock" and "shock" or "pain", now,
		exposed and { to = { pos = cov.origin, yaw = cov.hy } } or nil)
	if not d then return nil end
	return cov.phaseEnd - now
end

local function lean_muzzle(npc, cov)
	local fwd = yaw_dir(npc:GetAngles().y)
	local left = yaw_dir(npc:GetAngles().y + 90)
	local side = LEFT[cov.t] and 8 or ((cov.t == "rs" or cov.t == "rc") and -6 or 0)
	local z = (cov.t == "cr" or cov.t == "lc" or cov.t == "rc") and 44 or 56
	return npc:GetPos() + fwd * 16 + left * side + Vector(0, 0, z)
end

local function stunned_until(npc)
	return npc:GetNW2Float("tif_stun_until", 0)
end
MW.StunnedUntil = stunned_until

MW.KEEP_CROUCH = 2

function MW.PlaySwitch(npc, slot)
	local cov = npc.tifCov
	if not cov or not cov.mw or not cov.t then return nil end
	if cov.phase ~= "idle" and cov.phase ~= "look" and cov.phase ~= "twitch" then return nil end
	local name = "mwc_" .. cov.t .. (slot == "secondary" and "_to_pistol" or "_to_rifle")
	if not clip_on_body(npc, name) then return nil end
	local d = Act.Play(npc, name, {})
	if not d then return nil end
	local now = CurTime()
	cov.phaseEnd = now + d
	set_phase(npc, cov, "switch", now)
	return name
end

local function pick_lean_exit(npc, cov, yaw)
	local want = math.AngleDifference(yaw, npc:GetAngles().y)
	local best, bestE
	for _, k in ipairs({ "1", "2", "3", "4", "6", "7", "8", "9" }) do
		local c = clip_on_body(npc, role(cov, "exit_lean_" .. k))
		if c and (c.move[1] ~= 0 or c.move[2] ~= 0) then
			local e = math.abs(math.AngleDifference(math.deg(math.atan2(c.move[2], c.move[1])), want))
			if not bestE or e < bestE then best, bestE = role(cov, "exit_lean_" .. k), e end
		end
	end
	return best, bestE
end

function MW.FinishExit(npc, cov)
	local v, search = cov.exitVel, cov.exitSearch
	CB.Leave(npc, cov.exitReason)
	if v and npc.loco then
		npc.loco:SetVelocity(v)
		npc.tifStance = A.STANCE_STAND
		if npc:GetTIFStance() ~= A.STANCE_STAND then
			npc:SetTIFStance(A.STANCE_STAND)
			npc:TIFApplyStance()
		end
	end
	if search then npc.tifNextCoverSearch = 0 end
end

function MW.ExitTo(npc, goal, reason)
	local cov = npc.tifCov
	if not cov or not cov.mw or not goal then return false end
	local now = CurTime()
	if cov.phase == "exit" then
		if now < cov.phaseEnd then return true end
		MW.FinishExit(npc, cov)
		return false
	end
	if cov.phase ~= "idle" and cov.phase ~= "look" and cov.phase ~= "aim" then return false end
	local d = goal - npc:GetPos()
	if d:Length2DSqr() < 120 * 120 then return false end
	local yaw = math.deg(math.atan2(d.y, d.x))
	local n, e
	if cov.phase == "aim" then n, e = pick_lean_exit(npc, cov, yaw) end
	if not n then
		local sets = { "exit_" }
		if cqb_style(npc, cov) then sets = { "cfexit_", "cexit_", "exit_" } end
		n, e = pick_exit(npc, cov, yaw, sets)
	end
	if not n then return false end
	aim_off(npc)
	local yaw0 = npc:GetAngles().y
	local dur = Act.Play(npc, n, { root = true })
	if not dur then return false end
	local share = (e or 180) <= MW.EXIT_COMMIT and 1 or MW.EXIT_CUT
	local T = TIF.TransMW
	cov.exitVel = T and T.ExitVel and T.ExitVel(clip_on_body(npc, n), yaw0, share) or nil
	cov.exitReason, cov.exitSearch = reason, reason == "maneuver" or nil
	cov.exitCut = share < 1 or nil
	cov.phaseEnd = now + dur * share
	npc.tifFire.want = false
	set_phase(npc, cov, "exit", now)
	return true
end

function MW.Exit(npc, reason)
	local cov = npc.tifCov
	if not cov then return false end
	local now = CurTime()
	if cov.phase == "exit" then
		if now >= cov.phaseEnd then

			MW.FinishExit(npc, cov)
			return false
		end
		return true
	end

	if cov.phase == "aim" then
		aim_off(npc)

		local goal = exit_goal(npc)
		local gy = cov.ny
		if goal then local gd = goal - npc:GetPos() gy = math.deg(math.atan2(gd.y, gd.x)) end
		local best, bestE = pick_lean_exit(npc, cov, gy)
		local yaw0 = npc:GetAngles().y
		local d = best and Act.Play(npc, best, { root = true })
		if d then
			cov.exitReason = reason
			local share = (goal and bestE <= MW.EXIT_COMMIT) and 1 or MW.EXIT_CUT
			cov.exitVel = TIF.TransMW and TIF.TransMW.ExitVel and TIF.TransMW.ExitVel(clip_on_body(npc, best), yaw0, share) or nil
			cov.exitCut = share < 1 or nil
			cov.phaseEnd = now + d * share
			set_phase(npc, cov, "exit", now)
			return true
		end
	end
	if cov.phase ~= "idle" and cov.phase ~= "look" then
		CB.Leave(npc, reason)
		return false
	end
	aim_off(npc)
	local n, share = MW.PickCalmExit(npc, cov)
	local yaw0 = npc:GetAngles().y
	local d = n and Act.Play(npc, n, { root = true })
	if not d then
		CB.Leave(npc, reason)
		return false
	end
	cov.exitReason = reason
	share = share or 1
	cov.exitVel = TIF.TransMW and TIF.TransMW.ExitVel and TIF.TransMW.ExitVel(clip_on_body(npc, n), yaw0, share) or nil
	cov.exitCut = share < 1 or nil
	cov.phaseEnd = now + d * share
	set_phase(npc, cov, "exit", now)
	return true
end

function MW.Update(npc, c, now)
	local cov = npc.tifCov
	local f = npc.tifFire
	Prof.Begin("cover_mw")
	local arch = npc.tifArch
	local supp = npc.tifSupp or 0
	local lost = c and (now - math.max(c.seenAt, c.heardAt)) or 99
	npc.tifMode = A.MODE_AIM
	f.want = false
	npc.tifBlind = false

	local ps = holds_pistol(npc)
	if ps ~= cov.pstl then cov.pstl, cov.arrCache = ps, nil end
	local phase = cov.phase

	if npc.tifRole == "maneuver" and npc.tifCoverCenter and cov.origin:DistToSqr(npc.tifCoverCenter) > 360 * 360
		and (phase == "idle" or phase == "look" or phase == "aim" or phase == "move") then
		if phase ~= "move" and MW.ExitTo(npc, npc.tifCoverCenter, "maneuver") then
			Prof.End()
			return true
		end
		if npc.tifCov then CB.Leave(npc, "maneuver") end
		npc.tifNextCoverSearch = 0
		Prof.End()
		return CB.Update(npc, c, now)
	end

	local stun = stunned_until(npc)
	if stun > now + 0.4 and cov.flashedFor ~= stun and FLASHABLE[phase] then
		cov.flashedFor = stun
		f.want = false
		aim_off(npc)
		snap_home(npc, cov)
		if one_shot(npc, cov, "flash", "flash", now) then
			Prof.End()
			return true
		end
		start_hide(npc, cov, now)
		phase = cov.phase
	end

	if phase == "switch" then
		f.want = false
		if now >= cov.phaseEnd then start_hide(npc, cov, now) end
		Prof.End()
		return true
	end

	if phase == "exit" then
		if now >= cov.phaseEnd then
			MW.FinishExit(npc, cov)
			Prof.End()
			return false
		end

	elseif phase == "move" and cov.shuffle and not cov.shuffling then

		local sh = cov.shuffle
		cov.shuffling = true
		Move.Stop(npc)
		aim_off(npc)
		local d = Act.Play(npc, sh.inN, { root = true })
		if not d then
			cov.shuffle, cov.shuffling = nil, nil
		else
			sh.left = sh.cycles
			cov.phaseEnd = now + d
			set_phase(npc, cov, "shuffle", now)
		end

	elseif phase == "shuffle" then
		npc.tifStance, npc.tifHitboxPose = A.STANCE_CROUCH, "crouch"
		npc.tifFace = nil
		if now >= cov.phaseEnd then
			local sh = cov.shuffle
			if sh.left > 0 then
				sh.left = sh.left - 1
				cov.phaseEnd = now + (Act.Play(npc, sh.loopN, { root = true, once = true }) or 0)
			else
				local d = Act.Play(npc, sh.outN, { root = true, noTrace = true, to = { pos = cov.origin, yaw = cov.hy } })
				cov.shuffle = nil
				cov.phaseEnd = now + (d or 0)
				set_phase(npc, cov, "enter", now)
			end
		end

	elseif phase == "move" then
		npc.tifStance = A.STANCE_STAND
		npc.tifHitboxPose = nil
		local m = npc.tifMove
		if c and c.visible then
			npc.tifFace = c.ent:WorldSpaceCenter()
			if arch.aggression > 0.5 then f.want, f.aimPos = true, c.ent:WorldSpaceCenter() end
		else
			npc.tifFace = nil
		end
		local d2 = npc:GetPos():DistToSqr(cov.origin)

		if cov.xinTried == nil then
			cov.xinTried = true
			local xn = d2 < MW.XIN_DIST * MW.XIN_DIST and npc.loco:GetVelocity():Length2D() < 40 and MW.PickXin(npc, cov)
			if xn then
				Move.Stop(npc)
				npc.tifFace, f.want = nil, false
				local d = Act.Play(npc, xn, { root = true, noTrace = true, to = { pos = cov.origin, yaw = cov.hy } })
				if d then
					cov.phaseEnd = now + d
					set_phase(npc, cov, "enter", now)
					Prof.End()
					return true
				end
			end
		end
		local pathDone = m.goal == nil and m.result == "arrived" and d2 < 64 * 64
		local arrive
		if d2 < ARRIVE_LOOK * ARRIVE_LOOK or pathDone then
			local speed = npc.loco:GetVelocity():Length2D()

			if cov.wantLean == nil then
				local canLean = (LEFT[cov.t] and cov.edgeL) or (CORNER[cov.t] and not LEFT[cov.t] and cov.edgeR)
				cov.wantLean = (canLean and cov.canShoot and c and c.visible and math.random() < MW.LEAN_ARRIVE) and true or false
			end
			local best, qd
			if cov.wantLean then
				best, qd = pick_arrival(npc, cov, speed, true)
				if best and (qd <= best.dist + 12 or pathDone or qd < 40) then arrive, cov.enterLean = best, true end
			end
			if not arrive then
				best, qd = pick_arrival(npc, cov, speed)
				if best and (qd <= best.dist + 12 or pathDone or qd < 40) then arrive, cov.enterLean = best, nil end
				if not best and (pathDone or qd < 40) then arrive = false end
			end
		end
		if arrive ~= nil then
			Move.Stop(npc)
			npc.tifFace = nil
			f.want = false

			local tp, ty = cov.origin, cov.hy
			if arrive and cov.enterLean then tp, ty = lean_spot(npc, cov) end

			local d = arrive and Act.Play(npc, arrive.name, { root = true, noTrace = true, to = { pos = tp, yaw = ty } })
			cov.slide = nil
			if not d then

				local dist = npc:GetPos():Distance(cov.origin)
				if dist > 4 then
					d = math.Clamp(dist / 110, 0.12, 0.6)
					cov.slide = { p0 = npc:GetPos(), y0 = npc:GetAngles().y, t0 = now, dur = d }
				end
			end
			cov.phaseEnd = now + (d or 0)
			set_phase(npc, cov, "enter", now)
		else

			local accepted = Move.SetGoal(npc, cov.origin, Move.CombatGait(npc, cov.origin), "cover")
			local failed = m.goal == nil and (m.result == "fail" or m.result == "stuck" or m.result == "timeout")
			if not accepted or failed then
				npc.tifBadCover = npc.tifBadCover or {}
				table.insert(npc.tifBadCover, { pos = cov.origin, time = now })
				if #npc.tifBadCover > 8 then table.remove(npc.tifBadCover, 1) end
				CB.Leave(npc, accepted and ("path " .. tostring(m.result)) or "goal off navmesh or failed recently")
				Prof.End()
				return false
			end
		end

	elseif phase == "enter" then
		stance(npc, cov)
		local sl = cov.slide
		if sl then
			local k = math.Clamp((now - sl.t0) / sl.dur, 0, 1)
			k = k * k * (3 - 2 * k)
			npc:SetPos(LerpVector(k, sl.p0, cov.origin))
			npc:SetAngles(Angle(0, sl.y0 + math.AngleDifference(cov.hy, sl.y0) * k, 0))
			if k >= 1 then cov.slide = nil end
		end
		if now >= cov.phaseEnd then
			if cov.enterLean then

				cov.enterLean = nil
				local b = arch.coverBurst
				cov.aimUntil = now + math.Rand(b[1], b[2]) * (1 - 0.5 * supp)
				npc:SetAngles(Angle(0, threat_yaw(cov), 0))
				local n = clip(npc, cov, "aim")
				if n then Act.Loop(npc, n) end
				set_phase(npc, cov, "aim", now)
			else
				snap_home(npc, cov)
				start_hide(npc, cov, now)
			end
		end

	elseif phase == "idle" or phase == "look" then
		npc.tifFace = nil
		stance(npc, cov)
		local threat = c and c.pos
		if threat and now > (cov.nextCheck or 0) then
			cov.nextCheck = now + STILL_GOOD_EVERY
			local ok, why = Cover.StillGood(cov.pt, threat)
			if not ok then
				local crouched = npc:GetTIFStance() == A.STANCE_CROUCH
				CB.Leave(npc, why)
				if crouched then
					npc.tifStance = A.STANCE_CROUCH
					npc.tifKeepCrouchUntil = now + MW.KEEP_CROUCH
				end
				npc.tifNextCoverSearch = 0
				Prof.End()
				return false
			end
		end
		local w = npc.tifWep
		if w and w.ammo < w.clip * 0.35 and not Weapon.Reloading(npc) then
			if phase == "look" then snap_home(npc, cov) end

			local kind = TIF.GTG.WeaponKind(w.class)
			local r = (kind ~= "rifle" and clip(npc, cov, "reload_" .. kind)) and ("reload_" .. kind) or "reload"
			if one_shot(npc, cov, r, "reload", now) then
				Weapon.StartReload(npc)
				Prof.End()
				return true
			end
		end

		if threat and CORNER[cov.t] and now - cov.t0 > 1.5 then
			local want = CB.PickSide(cov.pt, threat)
			local other = want == "l" and cov.edgeL or (want == "r" and cov.edgeR)
			if want ~= cov.side and other and clip(npc, cov, "switch") then
				local old = { t = cov.t, side = cov.side }
				cov.side = want
				cov.t = cover_type(cov)
				place(cov)
				local name = role(old, "switch")
				local d = Act.Play(npc, name, { to = { pos = cov.origin, yaw = cov.hy } })
				cov.phaseEnd = now + (d or 0)
				set_phase(npc, cov, "switch", now)
				Prof.End()
				return true
			end
		end

		if c and not c.visible and TIF.GrenadeMW and clip(npc, cov, "grenade") and TIF.GrenadeMW.Want(npc, c, now, lost) then
			if phase == "look" then snap_home(npc, cov) end
			local cl = clip_on_body(npc, role(cov, "grenade"))
			if one_shot(npc, cov, "grenade", "grenade", now) then
				cov.grenadeAt, cov.thrown = c.pos, false
				cov.releaseT = now + (cov.phaseEnd - now) * TIF.GrenadeMW.ReleaseU(cl)
				cov.grenadeHand = TIF.GrenadeMW.Hand(cl)
				Prof.End()
				return true
			end
		end
		if c and now >= (cov.nextAim or 0) and lost < arch.loseContact + 4 then
			local canLean = OVER[cov.t] or (LEFT[cov.t] and cov.edgeL) or (CORNER[cov.t] and not LEFT[cov.t] and cov.edgeR)
			local canPop = canLean and (cov.canShoot or OVER[cov.t])
			if phase == "look" then snap_home(npc, cov) end

			local side = c.visible and supp < 0.5 and not cov.pstl and SIDE_T[cov.t] and now >= (cov.nextSide or 0)
				and math.random() < MW.SIDE_CHANCE
			if side then cov.nextSide = now + MW.SIDE_EVERY end

			if side and MW.SideOut(npc, cov, c, now) then
				Prof.End()
				return true
			elseif supp > 0.55 and arch.aggression >= 0.3 and not cov.pstl then
				if one_shot(npc, cov, math.random() < 0.5 and "blind1" or "blind2", "blind", now) then
					Prof.End()
					return true
				end
			elseif canPop and supp < 0.7 then
				if one_shot(npc, cov, "lean_in", "aim_in", now, { root = true }) then
					Prof.End()
					return true
				end
			end
			cov.nextAim = now + 1.5
		end

		local wantLook = c and not c.visible and lost < arch.loseContact + 4
		if wantLook then
			if now > (cov.lookUntil or 0) and now > (cov.nextLook or 0) then
				cov.lookUntil = now + math.Rand(1.2, 2.2)
				cov.nextLook = cov.lookUntil + math.Rand(3, 6)
			end
			wantLook = now < (cov.lookUntil or 0)
		end
		if wantLook and phase == "idle" then
			if one_shot(npc, cov, "look_in", "look_in", now) then
				Prof.End()
				return true
			end
		elseif not wantLook and phase == "look" then
			if one_shot(npc, cov, "look_out", "look_out", now) then
				Prof.End()
				return true
			end
			start_hide(npc, cov, now)
		elseif phase == "idle" and now >= (cov.nextTwitch or 0) then
			cov.nextTwitch = now + math.Rand(7, 14)

			local r = math.random() < 0.5 and "twitch1" or "twitch2"
			if math.random() < MW.BUSY_SHARE then
				local busyList = {}
				for i = 1, 5 do if clip(npc, cov, "busy_" .. i) then busyList[#busyList + 1] = "busy_" .. i end end
				if #busyList > 0 then r = busyList[math.random(#busyList)] end
			end
			if one_shot(npc, cov, r, "twitch", now) then
				Prof.End()
				return true
			end
		end

	elseif phase == "look_in" then
		stance(npc, cov)
		if now >= cov.phaseEnd then
			local n = clip(npc, cov, "look")
			if n then Act.Loop(npc, n) end
			set_phase(npc, cov, "look", now)
		end

	elseif phase == "look_out" or phase == "twitch" or phase == "flash" or phase == "blind" or phase == "reload"
		or phase == "grenade" or phase == "pain" then
		if phase == "pain" then f.want = false end
		stance(npc, cov)
		if phase == "grenade" and not cov.thrown and now >= (cov.releaseT or 0) then

			cov.thrown = true
			local fwd = yaw_dir(OVER[cov.t] and threat_yaw(cov) or npc:GetAngles().y)

			local side = yaw_dir(npc:GetAngles().y + 90) * ((cov.grenadeHand == "left" and 9) or (cov.grenadeHand == "right" and -9) or 0)
			TIF.GrenadeMW.Throw(npc, cov.grenadeAt, npc:GetPos() + fwd * 14 + side + Vector(0, 0, CROUCHED[cov.t] and 50 or 60))
		end
		if phase == "blind" and c then

			local u = (now - cov.t0) / math.max(0.1, cov.phaseEnd - cov.t0)
			if u > 0.3 and u < 0.75 then
				npc.tifBlind = true
				f.want, f.aimPos = true, c.pos + UP40
			end
		end
		if now >= cov.phaseEnd and not (phase == "reload" and Weapon.Reloading(npc)) then
			snap_home(npc, cov)
			start_hide(npc, cov, now)
		end

	elseif phase == "shock" then
		f.want = false
		stance(npc, cov)
		if now >= cov.phaseEnd and not one_shot(npc, cov, "shock_rec", "pain", now) then
			snap_home(npc, cov)
			start_hide(npc, cov, now)
		end

	elseif phase == "switch" then
		if now >= cov.phaseEnd then
			snap_home(npc, cov)
			start_hide(npc, cov, now)
		end

	elseif phase == "aim_in" then
		stance(npc, cov)
		if now >= cov.phaseEnd then
			local b = arch.coverBurst
			cov.aimUntil = now + math.Rand(b[1], b[2]) * (1 - 0.5 * supp)

			npc:SetAngles(Angle(0, threat_yaw(cov), 0))
			local n = clip(npc, cov, "aim")
			if n then Act.Loop(npc, n) end
			set_phase(npc, cov, "aim", now)
		end

	elseif phase == "aim" then
		stance(npc, cov)
		npc.tifFace = nil
		npc.tifAimFree = true
		npc.tifMuzzle = lean_muzzle(npc, cov)
		local aim
		if c and c.visible then
			aim = c.ent:WorldSpaceCenter() + Vector(0, 0, 6)
			f.want, f.aimPos, f.target = true, aim, c.ent
		elseif c and (lost < 1 or (npc.tifRole == "base" and lost < 6)) then
			aim = c.pos + UP40
			f.want, f.aimPos = true, aim
			if lost >= 1 and not cov.saidSuppress then
				cov.saidSuppress = true
				TIF.Say(npc, "suppressing", 0.5)
			end
		elseif c then
			aim = c.pos + UP40
		end
		if aim then
			npc.tifAimAt = aim
			local yaw = math.AngleDifference((aim - npc:GetPos()):Angle().y, npc:GetAngles().y)

			if math.abs(yaw) > MW.AIM_YAW_MAX then f.want = false end
			yaw = math.Clamp(yaw, -MW.AIM_YAW_MAX, MW.AIM_YAW_MAX)
			if math.abs(yaw - npc:GetNW2Float("tif_aim_yaw", 0)) > 1 then npc:SetNW2Float("tif_aim_yaw", yaw) end
		end
		local maxLost = npc.tifRole == "base" and 6 or 1.5
		if now > cov.aimUntil or supp > 0.75 or not c or lost > maxLost then
			cov.saidSuppress = nil
			f.want = false
			aim_off(npc)
			if not one_shot(npc, cov, "lean_out", "aim_out", now, { root = true }) then
				snap_home(npc, cov)
				start_hide(npc, cov, now)
			end
		end

	elseif phase == "aim_out" then
		stance(npc, cov)
		if now >= cov.phaseEnd then
			snap_home(npc, cov)
			start_hide(npc, cov, now)
		end

	elseif phase == "side_out" or phase == "side" or phase == "side_turn" then
		npc.tifStance, npc.tifHitboxPose = A.STANCE_CROUCH, "crouch"
		local sd = cov.sideAt
		if not sd then
			side_in(npc, cov, now)
			Prof.End()
			return true
		end
		local m = npc.tifMove
		if phase == "side_turn" then
			npc.tifFace = npc:GetPos() + yaw_dir(sd.yaw) * 300 + SIDE_EYE
			if math.abs(math.AngleDifference(sd.yaw, npc:GetAngles().y)) <= MW.SIDE_TURN_OK or now - cov.t0 > 1.5 then
				side_in(npc, cov, now)
			end
			Prof.End()
			return true
		end
		if c and c.visible and IsValid(c.ent) then
			local aim = c.ent:WorldSpaceCenter()
			npc.tifFace = aim
			f.want, f.aimPos, f.target = true, aim, c.ent
		elseif c then
			npc.tifFace = c.pos + UP40
		end
		if phase == "side_out" then
			if npc:GetPos():DistToSqr(sd.pos) < 14 * 14 or (m.goal == nil and m.result == "arrived") then
				Move.Stop(npc)
				local b = arch.coverBurst
				sd.untilT = now + math.Rand(b[1], b[2]) * 1.3
				set_phase(npc, cov, "side", now)
			elseif (m.goal == nil and m.result ~= nil) or now - cov.t0 > 3 then
				side_back(npc, cov, now)
			else
				Move.SetGoal(npc, sd.pos, "crouch", "cover")
			end
		else
			local w = npc.tifWep
			if now > sd.untilT or supp > 0.7 or not c or lost > 1.5 or (w and w.ammo < w.clip * 0.2) then
				side_back(npc, cov, now)
			end
		end
	end

	Prof.End()
	return true
end

TIF.ReactMW = TIF.ReactMW or {}
local R = TIF.ReactMW
local FLASH = {
	stand = { long = { "sdr_com_exposed_stand_flashbang_react_01", "sdr_com_exposed_stand_flashbang_react_02" },
		short = { "sdr_com_exposed_stand_flashbang_srt_react_01", "sdr_com_exposed_stand_flashbang_srt_react_02" } },
	crouch = { long = { "sdr_com_exposed_crouch_flashbang_react_01" }, short = { "sdr_com_exposed_crouch_flashbang_srt_react_01" } },
}

local INTERRUPTIBLE = { mwt_ = true, mwl_ = true, mwx_ = true, mws_ = true, mwr_ = true, mwi_ = true, mwa_ = true,
	mwk_ = true }
function R.Think(npc, now)

	if TIF.React22 then TIF.React22.Think(npc, now) end
	local r = npc.tifReact
	if r then
		if now < r.untilT then return true end
		npc.tifReact = nil
		return false
	end
	if not MW.Use(npc) or npc.tifCov or npc.tifVeh or npc.tifDowned then return false end

	local a = npc.tifAct
	if a and not INTERRUPTIBLE[string.sub(a.name or "", 1, 4)] then return false end
	local prone = npc.tifProne
	if prone and prone.phase ~= 2 then return false end
	local stun = stunned_until(npc)
	if stun <= now + 0.4 or npc.tifReactedTo == stun then return false end
	npc.tifReactedTo = stun
	local name
	if prone then
		name = "mwp_flash"
	else
		local set = FLASH[npc:GetTIFStance() == A.STANCE_CROUCH and "crouch" or "stand"]
		local list = (stun - now) > 3.5 and set.long or set.short
		name = list[math.random(#list)]
	end
	if not clip_on_body(npc, name) then return false end

	npc.tifActivity, npc.tifLook, npc.tifPassiveBusy = nil, nil, nil
	if npc.tifMove then npc.tifMove.stopping = nil end
	Move.Stop(npc)
	local d = Act.Play(npc, name, { root = true, clear = true })
	if not d then return false end
	npc.tifReact = { untilT = now + d }
	npc.tifAction = "flashbanged"
	return true
end

TIF.GrenadeMW = TIF.GrenadeMW or {}
local GR = TIF.GrenadeMW
GR.MIN, GR.MAX = 250, 1300
GR.COOLDOWN = { 20, 40 }
GR.SQUAD_COOLDOWN = 8
local cvGrenades = CreateConVar("tif_grenades", "1", FCVAR_ARCHIVE, "Soldiers throw frag grenades from cover (MW19 body)")

function GR.ReleaseU(c)
	for _, t in ipairs(c and c.tags or {}) do
		local a = t[4]
		if istable(a) and isstring(a.MoveEvent) and string.find(a.MoveEvent, "grenade_throw", 1, true) then return t[2] end
	end
	return 0.58
end

function GR.Hand(c)
	for _, t in ipairs(c and c.tags or {}) do
		local a = t[4]
		if istable(a) and a.MoveEvent == "grenade_left" then return "left" end
		if istable(a) and a.MoveEvent == "grenade_right" then return "right" end
	end
	return nil
end

function GR.Want(npc, c, now, lost)
	if not cvGrenades:GetBool() or lost < 1.5 or lost > 12 then return false end
	npc.tifGrenades = npc.tifGrenades or (npc.tifArch.grenades or 1)
	if npc.tifGrenades <= 0 or now < (npc.tifNextGrenade or 0) then return false end
	local sq = npc.tifSquad
	if sq and now < (sq.nextGrenade or 0) then return false end
	local d = npc:GetPos():Distance(c.pos)
	if d < GR.MIN or d > GR.MAX then return false end
	for _, s in ipairs(TIF.Soldiers) do
		if IsValid(s) and s ~= npc and TIF.Relation(s, npc) ~= TIF.REL_HOSTILE and s:GetPos():DistToSqr(c.pos) < 320 * 320 then
			return false
		end
	end
	if math.random() > 0.25 + (npc.tifArch.aggression or 0.5) * 0.5 then
		npc.tifNextGrenade = now + 6
		return false
	end
	return true
end

local OPEN = { [0] = "mwg_throw_stand", [1] = "mwg_throw_crouch", [2] = "mwg_throw_prone" }
function GR.OpenThrow(npc, c, now, lost)
	if npc.tifThrow or npc.tifAct or npc.tifCov or npc.tifVeh or npc.tifDowned or not c or c.visible then return false end
	if not (TIF.HitsMW and TIF.HitsMW.Use(npc)) then return false end
	local st = npc.tifProne and 2 or (npc:GetTIFStance() == A.STANCE_CROUCH and 1 or 0)
	local name = OPEN[st]
	local cl = name and clip_on_body(npc, name)
	if not cl or TIF.Move.Moving(npc) or not GR.Want(npc, c, now, lost) then return false end
	local yaw = (c.pos - npc:GetPos()):Angle().y
	local d = Act.Play(npc, name, { to = { pos = npc:GetPos(), yaw = yaw }, clear = true })
	if not d then return false end
	npc.tifThrow = { untilT = now + d * 0.85, releaseT = now + d * GR.ReleaseU(cl), target = c.pos, stance = st, name = name }
	npc.tifFire.want = false
	npc.tifAction = "grenade (open)"
	return true
end

function GR.OpenThink(npc, now)
	local t = npc.tifThrow
	if not t then return false end
	local a = npc.tifAct
	if not a or a.name ~= t.name then npc.tifThrow = nil return false end
	npc.tifFire.want = false
	TIF.Move.Stop(npc)
	if not t.thrown and now >= t.releaseT then
		t.thrown = true
		local f = npc:GetForward()
		local z = t.stance == 2 and 24 or (t.stance == 1 and 44 or 64)
		GR.Throw(npc, t.target, npc:GetPos() + f * 12 + Vector(0, 0, z))
	end
	if now >= t.untilT then npc.tifThrow = nil return false end
	return true
end

local function hl2_grenades(npc)
	local f = TIF.Factions and TIF.Factions[npc:GetTIFFaction()]
	return f and f.grenades == "hl2"
end
GR.HL2 = hl2_grenades

function GR.Throw(npc, target, src, kind, opts)
	if not (IsValid(npc) and target) then return end
	kind = kind or "frag"
	local now = CurTime()
	local hl2 = hl2_grenades(npc)
	if kind == "frag" then
		npc.tifGrenades = (npc.tifGrenades or 1) - 1
		npc.tifNextGrenade = now + math.Rand(GR.COOLDOWN[1], GR.COOLDOWN[2])
		if npc.tifSquad then npc.tifSquad.nextGrenade = now + GR.SQUAD_COOLDOWN end
	elseif hl2 then
		return nil
	end
	local g = ents.Create(hl2 and "npc_grenade_frag" or "tif_grenade")
	if not IsValid(g) then return end
	if not hl2 then
		g:SetKind(kind)
		if opts and opts.force then g.tifForce = opts.force end
	end
	local to = target - src
	local h = to.z
	to.z = 0
	local d = to:Length()
	to:Normalize()
	local T = math.Clamp(d / 520, 0.7, 1.7)
	local grav = physenv and physenv.GetGravity and physenv.GetGravity():Length() or 600
	local vel = to * (d / T) + Vector(0, 0, (h + 0.5 * grav * T * T) / T)
	g:SetPos(src)
	g:SetOwner(npc)
	g:Spawn()
	g:Activate()
	if hl2 then
		g:SetSaveValue("m_hThrower", npc)
		g:Fire("SetTimer", tostring(T + 0.5))
	else

		g:SetFuse(T + (kind == "flash" and 0.35 or 0.5))
	end
	local ph = g:GetPhysicsObject()
	if IsValid(ph) then
		ph:SetVelocity(vel)
		ph:AddAngleVelocity(Vector(math.Rand(-300, 300), math.Rand(-300, 300), math.Rand(-300, 300)))
	end
	TIF.Say(npc, "grenade_out", 0.9)
	if kind ~= "frag" then return g end
	local called = false
	for _, s in ipairs(TIF.Soldiers) do
		if IsValid(s) and s:GetPos():DistToSqr(target) < 400 * 400
			and TIF.FactionRelation(s:GetTIFFaction(), npc:GetTIFFaction()) == TIF.REL_HOSTILE then
			if TIF.Supp then TIF.Supp.Add(s, 0.6, target, npc) end
			if not called then
				called = true
				TIF.Say(s, "grenade_incoming", 0.8)
			end
		end
	end
	return g
end
