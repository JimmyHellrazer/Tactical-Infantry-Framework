local PMS = TIFG.PMS
local M = PMS.Math
local mul3, tr3, mulv, sub, unit, swing, frame, cross = M.mul3, M.tr3, M.mulv, M.sub, M.unit, M.swing, M.frame, M.cross
local math_atan2, math_deg, math_sqrt = math.atan2, math.deg, math.sqrt

local PELVIS = "valvebiped.bip01_pelvis"

PMS.MERGE, PMS.ENGINE, PMS.QUAT, PMS.BIND = 1, 2, 3, 4
local MERGE, ENGINE, QUAT, BIND = PMS.MERGE, PMS.ENGINE, PMS.QUAT, PMS.BIND

PMS.Aim = {
	[PELVIS] = false,
	["valvebiped.bip01_spine"] = false, ["valvebiped.bip01_spine1"] = false, ["valvebiped.bip01_spine2"] = false,
	["valvebiped.bip01_spine3"] = false, ["valvebiped.bip01_spine4"] = false,
	["valvebiped.bip01_neck1"] = false, ["valvebiped.bip01_head1"] = false,
	["valvebiped.bip01_l_hand"] = "valvebiped.bip01_l_finger2",
	["valvebiped.bip01_r_hand"] = "valvebiped.bip01_r_finger2",
}

PMS.Palm = {}

for _, side in ipairs({ "l", "r" }) do
	local pre = "valvebiped.bip01_" .. side .. "_"
	local def = { pre .. "hand", pre .. "finger1", pre .. "finger4", pre .. "finger2" }
	PMS.Palm[pre .. "hand"], PMS.Palm[pre .. "forearm"] = def, def

	for finger = 0, 4 do
		for joint = 0, 2 do
			PMS.Aim[pre .. "finger" .. finger .. (joint > 0 and joint or "")] = false
		end
	end
end

PMS.OwnLength = {
	["valvebiped.bip01_spine"] = true, ["valvebiped.bip01_spine1"] = true, ["valvebiped.bip01_spine2"] = true,
	["valvebiped.bip01_spine3"] = true, ["valvebiped.bip01_spine4"] = true,
	["valvebiped.bip01_neck1"] = true, ["valvebiped.bip01_head1"] = true,
}

local function palm_normal(sk, def)
	local ix = sk.index
	local h, f1, f4, f2 = ix[def[1]], ix[def[2]], ix[def[3]], ix[def[4]]
	if not (h and f1 and f4 and f2) then return nil end

	local aim = unit(sub(sk.t[f2], sk.t[h]))
	return aim and unit(cross(sub(sk.t[f1], sk.t[f4]), aim))
end

function M.angles(R)
	local fx, fy, fz = R[1], R[4], R[7]
	local xy = math_sqrt(fx * fx + fy * fy)

	if xy > 0.001 then
		return math_deg(math_atan2(-fz, xy)), math_deg(math_atan2(fy, fx)), math_deg(math_atan2(R[8], R[9]))
	end

	return math_deg(math_atan2(-fz, xy)), math_deg(math_atan2(-R[2], R[5])), 0
end

local function offsets(lsk, fsk, merged, children)
	local fname, fparent = fsk.name, fsk.parent
	local S, off = {}, {}
	local function aim_of(i)
		local want = PMS.Aim[fname[i]]
		if want == false then return nil end

		local kids = children[i]
		if not kids then return nil end

		if want then
			for _, c in ipairs(kids) do
				if fname[c] == want then
					return c
				end
			end
		end

		return #kids == 1 and kids[1] or nil
	end

	for i = 0, fsk.n - 1 do
		local li = merged[i]
		if li then
			local s
			local c = aim_of(i)

			if c then
				local df = unit(sub(fsk.t[c], fsk.t[i]))
				local dl = unit(sub(lsk.t[merged[c]], lsk.t[li]))

				if df and dl then
					local palm = PMS.Palm[fname[i]]
					if palm then
						local nf, nl = palm_normal(fsk, palm), palm_normal(lsk, palm)
						local ff, fl = nf and frame(df, nf), nl and frame(dl, nl)

						if ff and fl then
							s = mul3(fl, tr3(ff))
						end
					end

					s = s or swing(df, dl)
				end
			end

			if not s then
				local a = fparent[i]
				while a >= 0 and not S[a] do
					a = fparent[a]
				end

				s = a >= 0 and S[a] or M.IDENTITY
			end

			S[i] = s
			off[i] = mul3(tr3(lsk.R[li]), mul3(s, fsk.R[i]))
		end
	end

	return off
end

local function local_of(fsk, i, p)
	local rpt = tr3(fsk.R[p])
	local r = mul3(rpt, fsk.R[i])
	local t = mulv(rpt, sub(fsk.t[i], fsk.t[p]))
	return { r[1], r[2], r[3], t[1], r[4], r[5], r[6], t[2], r[7], r[8], r[9], t[3] }
end

local function order_steps(fsk, kind)
	local order, seen = {}, {}
	local function visit(i)
		if seen[i] then return end

		seen[i] = true
		local p = fsk.parent[i]

		if p >= 0 and kind[p] then
			visit(p)
		end

		if kind[i] == QUAT then
			local c = fsk.rule[i].control
			visit(c)
			visit(fsk.parent[c])
		end

		order[#order + 1] = i
	end

	for i = 0, fsk.n - 1 do
		if kind[i] then
			visit(i)
		end
	end

	return order
end

local function hit_data(fsk, kof, P)
	local hits, need = {}, {}
	for _, h in ipairs(fsk.hitboxes) do
		local k = kof[h.bone]
		if k then
			local mn, mx = h.min, h.max
			local ex, ey, ez = (mx[1] - mn[1]) / 2, (mx[2] - mn[2]) / 2, (mx[3] - mn[3]) / 2
			hits[#hits + 1] = { k = k, group = h.group, index = h.index, min = mn, max = mx,
				c = { (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2, (mn[3] + mx[3]) / 2 }, r2 = ex * ex + ey * ey + ez * ez }

			while k ~= 0 and not need[k] do
				need[k] = true
				k = P[k]
			end
		end
	end

	local steps = {}
	for k in pairs(need) do
		steps[#steps + 1] = k
	end

	table.sort(steps)
	return hits, steps
end

local REACH_PAD = 24
local function hit_bounds(fsk)
	local zmin, zmax, r = math.huge, -math.huge, 0
	for _, h in ipairs(fsk.hitboxes) do
		local R, t = fsk.R[h.bone], fsk.t[h.bone]
		for c = 0, 7 do
			local v = { c % 2 == 0 and h.min[1] or h.max[1], c % 4 < 2 and h.min[2] or h.max[2], c < 4 and h.min[3] or h.max[3] }
			local w = mulv(R, v)
			local x, y, z = w[1] + t[1], w[2] + t[2], w[3] + t[3]
			zmin, zmax, r = math.min(zmin, z), math.max(zmax, z), math.max(r, math_sqrt(x * x + y * y))
		end
	end

	if zmax < zmin then return 0, 0 end

	local half = (zmax - zmin) / 2
	return zmin + half, math_sqrt(half * half + r * r) + REACH_PAD
end

function PMS.BuildMap(lsk, fsk, mode)
	mode = mode or 1
	local oddness = PMS.Oddness(lsk, fsk)
	local own_all = mode == 2 or (mode == 1 and oddness > PMS.OddRatio)
	local n, fname, fparent, proc, rule = fsk.n, fsk.name, fsk.parent, fsk.proc, fsk.rule

	local merged, needed, children = {}, {}, {}
	for i = 0, n - 1 do
		merged[i] = lsk.index[fname[i]]
	end

	for _, h in ipairs(fsk.hitboxes) do
		needed[h.bone] = true
	end

	for i = n - 1, 0, -1 do
		if fsk.weighted[i] or needed[i] then
			needed[i] = true

			if fparent[i] >= 0 then
				needed[fparent[i]] = true
			end
		end
	end

	for i = 0, n - 1 do
		local p = fparent[i]
		if merged[i] and p >= 0 then
			children[p] = children[p] or {}
			children[p][#children[p] + 1] = i
		end
	end

	local off = offsets(lsk, fsk, merged, children)

	local kind = {}
	for i = 0, n - 1 do
		if needed[i] then
			local p = fparent[i]
			local pk = p >= 0 and kind[p]

			if merged[i] then
				kind[i] = MERGE
			elseif pk then
				if proc[i] == PMS.PROC_QUAT and rule[i] then
					kind[i] = QUAT
				elseif (proc[i] == 0 or proc[i] == PMS.PROC_JIGGLE) and (pk == MERGE or pk == ENGINE) then
					kind[i] = ENGINE
				else
					kind[i] = BIND
				end
			end
		end
	end

	for i = 0, n - 1 do
		if kind[i] == QUAT then
			local c = rule[i].control
			local ok = c >= 0 and c < n and kind[c] and fparent[c] >= 0 and kind[fparent[c]]

			if not ok then
				kind[i] = BIND
			end
		end
	end

	local order = order_steps(fsk, kind)
	local kof = {}

	for k, i in ipairs(order) do
		kof[i] = k
	end

	local map = { n = #order, B = {}, K = {}, P = {}, LB = {}, OFF = {}, FK = {}, RL = {}, Q = {}, MAN = {},
		oddness = oddness, own_all = own_all, scale = 1, W = {}, E = {}, HAS = {}, ROT = {}, SW = {}, SE = {}, SH = {} }

	if own_all then
		map.scale = fsk.t[fsk.index[PELVIS]][3] / math.max(1, lsk.t[lsk.index[PELVIS]][3])
	end

	for k, i in ipairs(order) do
		local p = fparent[i]
		local pk = p >= 0 and kof[p] or 0
		map.B[k], map.K[k], map.P[k] = i, kind[i], pk

		if kind[i] == MERGE then
			map.LB[k], map.OFF[k] = merged[i], off[i]

			if fname[i] == PELVIS then
				map.root = k
			end

			if pk ~= 0 and (own_all or PMS.OwnLength[fname[i]]) then
				map.FK[k] = mulv(tr3(fsk.R[p]), sub(fsk.t[i], fsk.t[p]))
			end
		else
			local L = local_of(fsk, i, p)
			map.RL[k] = L

			if kind[i] == QUAT then
				local c = rule[i].control
				map.Q[k] = { c = kof[c], cp = kof[fparent[c]], triggers = rule[i].triggers }
			elseif kind[i] == ENGINE and kind[p] == MERGE then
				local o = off[p]
				local R = { L[1], L[2], L[3], L[5], L[6], L[7], L[9], L[10], L[11] }
				local t = { L[4], L[8], L[12] }
				local pitch, yaw, roll = M.angles(mul3(tr3(R), mul3(o, R)))
				local ot = mulv(o, t)
				map.MAN[#map.MAN + 1] = { b = i, ang = { pitch, yaw, roll }, pos = { ot[1] - t[1], ot[2] - t[2], ot[3] - t[3] } }
			end
		end
	end

	map.hits, map.hit_steps = hit_data(fsk, kof, map.P)
	map.hit_mid, map.hit_reach = hit_bounds(fsk)

	if own_all then
		local on_chain = {}
		map.hands = {}

		for _, side in ipairs({ "r", "l" }) do
			local name = "valvebiped.bip01_" .. side .. "_hand"
			local fh, lh = fsk.index[name], lsk.index[name]

			if fh and lh and kof[fh] and kind[fh] == MERGE then
				local a = fh
				while a >= 0 and kof[a] do
					on_chain[kof[a]] = true
					a = fparent[a]
				end

				local subtree = {}
				for j = 0, lsk.n - 1 do
					local b = j
					while b >= 0 and b ~= lh do
						b = lsk.parent[b]
					end

					if b == lh then
						subtree[#subtree + 1] = j
					end
				end

				map.hands[#map.hands + 1] = { k = kof[fh], lb = lh, sub = subtree, side = side }
			end
		end

		map.chain = {}

		for k = 1, map.n do
			if on_chain[k] then
				map.chain[#map.chain + 1] = k
			end
		end

		local function k_of(name)
			local i = fsk.index["valvebiped.bip01_" .. name]
			return i and kof[i]
		end

		local ua, fa, lh, rh = k_of("l_upperarm"), k_of("l_forearm"), k_of("l_hand"), k_of("r_hand")
		if ua and fa and lh and rh and on_chain[ua] and on_chain[fa] and on_chain[lh] and on_chain[rh]
			and map.K[ua] == MERGE and map.K[fa] == MERGE then
			map.left = { ua = ua, fa = fa, hand = lh, rhand = rh }
		end
	end

	return map
end

local proportions = CreateConVar("tif_gta_pm_proportions", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Retargeted faction models' limbs: 0 = on the soldier body's joints (guns sit in the palm), 1 = automatic (models far from human proportions keep their own), 2 = always their own", 0, 2)

PMS.ResetMaps()

function PMS.MapFor(leader_model, follower_model)
	if not (leader_model and follower_model) then return nil end

	local mode = math.Clamp(math.floor(proportions:GetFloat()), 0, 2)
	if mode ~= PMS.MapMode then
		PMS.ResetMaps()
		PMS.MapMode = mode
	end

	local key = string.lower(leader_model) .. "\n" .. string.lower(follower_model) .. "\n" .. mode
	local map = PMS.Maps[key]

	PMS.MapRetry = PMS.MapRetry or {}

	if map == false and CurTime() >= (PMS.MapRetry[key] or 0) then
		map = nil
	end

	if map == nil then
		local lsk, fsk = PMS.Skeleton(leader_model), PMS.Skeleton(follower_model)
		map = lsk and fsk and PMS.BuildMap(lsk, fsk, mode) or false

		if map then
			for _, m in ipairs(map.MAN) do
				m.angle, m.vector = Angle(m.ang[1], m.ang[2], m.ang[3]), Vector(m.pos[1], m.pos[2], m.pos[3])
			end
		end

		PMS.Maps[key] = map

		if not map then
			PMS.MapRetry[key] = CurTime() + 10
		end
	end

	return map or nil
end
