-- Traversal with MW19's clips (MW19 body): instead of walking into a low wall, spinning on a ledge or
-- dropping off an edge in his walk cycle, a moving soldier mantles up onto it, drops down off it, vaults or
-- steps over what's in the way. Checked from TIF.Move.Step ahead along the path (a few traces):
--   up    a face ahead with a top 20-100 above his feet, room above it, and the path going up there: mantle
--         (sm <= 36, md <= 70, lg <= 100)
--   over  a low obstacle (a wall, sandbags, a fence) whose far side is back at his own height, the path going
--         past it: step (<= 22), vault (sm <= 42, md <= 66, lg <= 100)
--   down  the floor ending ahead with the path going down 24-100: drop (sm <= 36, md <= 70, lg <= 100)
-- Each clip is warped (root + height) so its contact point lands on the edge / obstacle, and ends on the
-- landing spot at its code_move / finish notetrack, where locomotion takes back over (the run-out is cut).
-- Paths may climb up to MAX_UP for these soldiers (TIF.Move's cost lets them through, with a penalty).
-- Roles: mwtr_<mantle|drop|vault>_<sm|md|lg>, mwtr_step.

local TIF = TIF
local Act = TIF.Action

TIF.TraverseMW = TIF.TraverseMW or {}
local T = TIF.TraverseMW

T.MAX_UP = 100
T.MAX_DROP = 210         -- deepest drop looked for (MW22 xl drop)
T.WALK_SPEED = 120       -- slower than this: the walking traversals (mwtr_*_walk); faster than FAST_SPEED: *_fast
T.FAST_SPEED = 200
T.LOOK = 70              -- how far ahead to look for an obstacle / edge
T.CHECK_EVERY = 0.15
T.SIZES = {
	mantle = { { "sm", 36 }, { "md", 70 }, { "lg", 100 } },
	vault = { { "sm", 42 }, { "md", 66 }, { "lg", 100 } },
	-- (xl1: MW22's running drop off a high ledge, 200 down and ~250 forward; only with room ahead, T.Check.)
	drop = { { "sm", 36 }, { "md", 70 }, { "lg", 100 }, { "xl1", 210 } },
}
-- Each clip's contact notetrack (where the edge / obstacle is) and hand-back notetrack.
local CONTACT = { mantle = "warp_up_end", vault = "warp_up_apex", step = "warp_up_end", drop = "warp_down_start" }
local HANDBACK = { "code_move", "finish" }

local function trace(a, b, skip)
	return util.TraceLine({ start = a, endpos = b, mask = MASK_NPCSOLID, filter = function(x)
		return x ~= skip and not (x:IsNPC() or x:IsNextBot() or x:IsPlayer())
	end })
end

function T.Use(npc)
	return npc.tifHomeHost ~= nil and npc.tifHostId == npc.tifHomeHost and TIF.GTG.IsVB(npc.tifHostId)
		and TIF.GTG.Clip("mwtr_mantle_sm", npc.tifHomeHost) ~= nil
end

local function tag_u(c, name)
	for _, t in ipairs(c.tags or {}) do
		local a = t[4]
		if istable(a) and a.MoveEvent == name then return t[2] end
	end
	return nil
end

-- Per clip: contact u, hand-back u, forward distance at each, height at the hand-back. Cached.
local info = {}
local function clip_info(host, name)
	local key = host .. "/" .. name
	if info[key] ~= nil then return info[key] or nil end
	local c = TIF.GTG.Clip(name, host)
	if not c then info[key] = false return nil end
	local kind = string.match(name, "^mwtr_(%a+)")
	local cu = tag_u(c, CONTACT[kind] or "warp_up_end") or 0.3
	local hu
	for _, n in ipairs(HANDBACK) do hu = hu or tag_u(c, n) end
	hu = hu or 0.9
	local xc = Act.RootAt(c, cu)
	local xh = Act.RootAt(c, hu)
	local e = { clip = c, name = name, cu = cu, hu = hu, xc = xc, xh = xh, zh = Act.ZAt(c, hu) }
	info[key] = e
	return e
end
T.Info = clip_info

local function pick(kind, h)
	for _, s in ipairs(T.SIZES[kind]) do
		if h <= s[2] then return "mwtr_" .. kind .. "_" .. s[1] end
	end
	return nil
end

-- What's ahead along dir (unit, flat): { kind, h, edge (distance to the face / edge / obstacle centre), land
-- (floor z beyond) } or nil.
function T.Probe(npc, dir)
	local base = npc:GetPos()
	local z0 = base.z
	local knee = trace(base + Vector(0, 0, 14), base + Vector(0, 0, 14) + dir * T.LOOK, npc)
	if knee.Hit and math.abs(knee.HitNormal.z) < 0.5 then
		local D = knee.Fraction * T.LOOK
		local inside = base + dir * (D + 4)
		local top = trace(inside + Vector(0, 0, T.MAX_UP + 20), inside + Vector(0, 0, 4), npc)
		if top.StartSolid or not top.Hit then return nil end
		local h = top.HitPos.z - z0
		if h < 18 or h > T.MAX_UP then return nil end
		-- Room above the top to get over / onto it.
		local over = trace(Vector(base.x, base.y, z0 + h + 36), Vector(base.x, base.y, z0 + h + 36) + dir * (D + 50), npc)
		if over.Hit then return nil end
		-- Thickness: where the top ends, and the floor beyond.
		for t = 8, 56, 8 do
			local p = base + dir * (D + t)
			local g = trace(p + Vector(0, 0, h + 10), p - Vector(0, 0, 40), npc)
			if g.Hit and g.HitPos.z < z0 + h - 12 then
				-- The far side drops away: back near his own height = an obstacle to get over.
				local land = g.HitPos.z
				if math.abs(land - z0) <= 20 then
					return { kind = h <= 22 and "step" or "vault", h = h, edge = D + t * 0.5, land = land, thick = t }
				end
				return nil
			end
		end
		-- A top that carries on: a ledge to climb onto.
		return { kind = "mantle", h = h, edge = D, land = z0 + h }
	end
	-- No face: does the floor end ahead?
	for t = 16, T.LOOK, 12 do
		local p = base + dir * t
		local g = trace(p + Vector(0, 0, 18), p - Vector(0, 0, T.MAX_DROP + 10), npc)
		local fz = g.Hit and g.HitPos.z or (z0 - T.MAX_DROP - 10)
		if z0 - fz > 24 then
			if not g.Hit then return nil end
			return { kind = "drop", h = z0 - fz, edge = t - 6, land = fz }
		end
	end
	return nil
end

-- Called by TIF.Move.Step while moving (MW19 body). Returns true if a traversal started (the path waits).
function T.Check(npc, m, now)
	if not T.Use(npc) or npc.tifAct or npc.tifVeh or npc.tifProne or npc.tifDowned or npc.tifCov then return false end
	if m.tag == "crawl" or m.tag == "board" or npc:GetTIFStance() == TIF.Anim.STANCE_CROUCH then return false end
	if now < (npc.tifNextTrav or 0) then return false end
	npc.tifNextTrav = now + T.CHECK_EVERY
	local seg = npc.tifPath:GetCurrentGoal()
	if not seg then return false end
	local to = seg.pos - npc:GetPos()
	local dz = to.z
	to.z = 0
	local len = to:Length()
	if len < 8 then return false end
	to:Normalize()
	-- Only along the way he's going.
	local v = npc.loco:GetVelocity()
	v.z = 0
	if v:LengthSqr() > 100 then
		local vn = v:GetNormalized()
		if vn:Dot(to) < 0.8 then return false end
	end
	local pr = T.Probe(npc, to)
	if not pr then return false end
	-- The path has to want it: up there / past it / down there.
	if pr.kind == "mantle" and dz < pr.h * 0.5 then return false end
	if pr.kind == "drop" and dz > -pr.h * 0.5 then return false end
	if (pr.kind == "vault" or pr.kind == "step") and len < pr.edge + 10 then return false end
	-- The big drop runs on a long way after landing: only with that much path ahead.
	if pr.kind == "drop" and pr.h > 100 and len < 220 then return false end
	local name = pr.kind == "step" and "mwtr_step" or pick(pr.kind, pr.h)
	-- At his pace: MW19's AI walk / fast versions where they exist (the jog set otherwise).
	local spd = v:Length()
	local gait = spd < T.WALK_SPEED and "walk" or (spd > T.FAST_SPEED and "fast" or nil)
	if name and gait and clip_info(npc.tifHomeHost, name .. "_" .. gait) then name = name .. "_" .. gait end
	local e = name and clip_info(npc.tifHomeHost, name)
	if not e then return false end
	-- Start once the clip's own contact point would land on the edge (a little early is fine: the warp eats it).
	if pr.edge > e.xc + 12 then return false end
	local yaw = to:Angle().y
	local landD = pr.edge + (e.xh - e.xc)
	local land = npc:GetPos() + to * landD
	land.z = pr.land
	local d = Act.Play(npc, name, { root = true, rootz = true, noTrace = true, warpU = e.hu,
		to = { pos = land, yaw = yaw } })
	if not d then return false end
	npc.tifAct.trans = true
	npc.tifTrav = { untilT = now + d * e.hu, name = name }
	npc.tifAction = "traverse: " .. name
	return true
end

-- While one plays: true until the hand-back point, then the clip is dropped and locomotion carries on.
function T.Busy(npc, now)
	local t = npc.tifTrav
	if not t then return false end
	local a = npc.tifAct
	if not a or a.name ~= t.name then npc.tifTrav = nil return false end
	if now < t.untilT then return true end
	npc.tifTrav = nil
	Act.Clear(npc)
	return false
end
