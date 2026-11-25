-- Searching looks with MW19's smart-object clips (MW19 body): at a search point or where a noise came from,
-- the soldier looks at what's actually there instead of turning on the spot:
--   under      something table-high with space beneath (table, desk, bench)
--   under_low  something low with a gap under it (a car)
--   over       a low wall / ledge / sandbags with open space beyond
--   down       a drop ahead (a balcony edge, a ledge)
--   high       open sky above and a tall structure ahead (looking up at windows / a roof line)
--   around     nothing particular
-- Each is enter / loop / exit (mwl_<kind>_*). TIF.SearchMW.Look starts one; Busy (called by the brain before
-- any behaviour, like TIF.PassiveMW.Busy) runs it and drops it the moment a fight starts.

local TIF = TIF
local Act = TIF.Action
local AW = TIF.AWARE

TIF.SearchMW = TIF.SearchMW or {}
local S = TIF.SearchMW

S.LOOP_FOR = { 2.5, 4.5 }
S.PREFER = { under = 3, under_low = 3, over = 2.5, down = 2.5, high = 1.5 }   -- weights over plain "around"

local function yaw_dir(y)
	local r = math.rad(y)
	return Vector(math.cos(r), math.sin(r), 0)
end

local function trace(a, b, skip)
	return util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID, filter = function(x)
		return x ~= skip and not (x:IsNPC() or x:IsNextBot() or x:IsPlayer())
	end })
end

function S.Use(npc)
	return npc.tifHomeHost ~= nil and npc.tifHostId == npc.tifHomeHost and TIF.GTG.IsVB(npc.tifHostId)
		and TIF.GTG.Clip("mwl_around_loop", npc.tifHomeHost) ~= nil
end

local function has(npc, kind) return TIF.GTG.Clip("mwl_" .. kind .. "_loop", npc.tifHomeHost) ~= nil end

-- What's around: a list of { kind, yaw }. hint: a yaw to favour (toward the last known position).
function S.Find(npc, hint)
	local out = {}
	local base = npc:GetPos()
	for i = 0, 7 do
		local yaw = i * 45
		local d = yaw_dir(yaw)
		local mid = trace(base + Vector(0, 0, 30), base + Vector(0, 0, 30) + d * 60, npc)
		if mid.Hit and math.abs(mid.HitNormal.z) < 0.5 then
			local dist = mid.Fraction * 60
			local high = trace(base + Vector(0, 0, 62), base + Vector(0, 0, 62) + d * (dist + 80), npc)
			local low = trace(base + Vector(0, 0, 12), base + Vector(0, 0, 12) + d * (dist + 25), npc)
			local gap = trace(base + Vector(0, 0, 4), base + Vector(0, 0, 4) + d * (dist + 30), npc)
			if not low.Hit and not high.Hit then
				out[#out + 1] = { kind = "under", yaw = yaw }        -- a table: open at shin height
			elseif low.Hit and not gap.Hit then
				out[#out + 1] = { kind = "under_low", yaw = yaw }    -- a car: body down to the knees, a gap under it
			elseif not high.Hit then
				out[#out + 1] = { kind = "over", yaw = yaw }         -- a low wall: solid to the ground, open above
			end
		else
			-- A drop: no floor a little way ahead.
			local p = base + d * 50
			local g = trace(p + Vector(0, 0, 20), p - Vector(0, 0, 120), npc)
			if not g.Hit then out[#out + 1] = { kind = "down", yaw = yaw } end
		end
	end
	-- Up: open sky and something tall ahead.
	local up = trace(base + Vector(0, 0, 64), base + Vector(0, 0, 400), npc)
	if not up.Hit or up.HitSky then
		local y = hint or npc:GetAngles().y
		local tall = trace(base + Vector(0, 0, 220), base + Vector(0, 0, 220) + yaw_dir(y) * 500, npc)
		if tall.Hit and not tall.HitSky then out[#out + 1] = { kind = "high", yaw = y } end
	end
	local ok = {}
	for _, f in ipairs(out) do if has(npc, f.kind) then ok[#ok + 1] = f end end
	return ok
end

-- Pick one: weighted by kind, favouring the hint direction.
local function choose(npc, list, hint)
	local total, w = 1, {}
	for i, f in ipairs(list) do
		local k = S.PREFER[f.kind] or 1
		if hint then k = k * (1.5 - math.abs(math.AngleDifference(f.yaw, hint)) / 180) end
		w[i] = k
		total = total + k
	end
	local r = math.random() * total
	for i, f in ipairs(list) do
		r = r - w[i]
		if r <= 0 then return f end
	end
	return { kind = "around", yaw = hint or npc:GetAngles().y }
end

-- Start a look. hint: a yaw to favour. Returns true if one started.
function S.Look(npc, now, hint)
	if not S.Use(npc) or npc.tifLook or npc.tifAct or npc.tifCov or npc.tifProne or npc.tifVeh then return false end
	local f = choose(npc, S.Find(npc, hint), hint)
	local d = Act.Play(npc, "mwl_" .. f.kind .. "_enter", { root = true, to = { pos = npc:GetPos(), yaw = f.yaw } })
	if not d then return false end
	npc.tifLook = { kind = f.kind, phase = "enter", untilT = now + d, yaw = f.yaw }
	npc.tifAction = "search: look " .. f.kind
	return true
end

local function stop(npc)
	npc.tifLook = nil
	local a = npc.tifAct
	if a and a.name and string.sub(a.name, 1, 4) == "mwl_" then Act.Clear(npc) end
end
S.Stop = stop

-- Called by the brain before any behaviour. True while a look is in charge.
function S.Busy(npc, now)
	local l = npc.tifLook
	if not l then return false end
	-- A fight, or something else took the body over (a reaction, a hit): drop the look.
	local a = npc.tifAct
	if npc.tifAware == AW.ENGAGED or not a or string.sub(a.name or "", 1, 4) ~= "mwl_" then
		stop(npc)
		return false
	end
	TIF.Move.Stop(npc)
	if l.phase == "enter" and now >= l.untilT then
		Act.Loop(npc, "mwl_" .. l.kind .. "_loop")
		l.phase, l.untilT = "loop", now + math.Rand(S.LOOP_FOR[1], S.LOOP_FOR[2])
	elseif l.phase == "loop" and now >= l.untilT then
		local d = Act.Play(npc, "mwl_" .. l.kind .. "_exit", { root = true, to = { pos = npc:GetPos(), yaw = l.yaw }, clear = true })
		l.phase, l.untilT = "exit", now + (d or 0)
	elseif l.phase == "exit" and now >= l.untilT then
		npc.tifLook = nil
		return false
	end
	return true
end
