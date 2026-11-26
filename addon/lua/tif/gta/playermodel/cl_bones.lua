local PMS = TIFG.PMS
local M = PMS.Math
local MERGE, ENGINE, QUAT = PMS.MERGE, PMS.ENGINE, PMS.QUAT
local IsValid, FrameNumber = IsValid, FrameNumber
local math_sqrt, math_abs, math_acos, math_max = math.sqrt, math.abs, math.acos, math.max
local F = PMS.Flat
local read, write, copy, mul, mul_rot, inv, turn, place_merge = F.read, F.write, F.copy, F.mul, F.mul_rot, F.inv, F.turn, F.place_merge

local T = {}
local QuatFromRows = TIFG.QuatFromRows

local function quat_of(A, a)
	local sx = math_sqrt(A[a + 1] ^ 2 + A[a + 5] ^ 2 + A[a + 9] ^ 2)
	local sy = math_sqrt(A[a + 2] ^ 2 + A[a + 6] ^ 2 + A[a + 10] ^ 2)
	local sz = math_sqrt(A[a + 3] ^ 2 + A[a + 7] ^ 2 + A[a + 11] ^ 2)
	if sx < 1e-6 or sy < 1e-6 or sz < 1e-6 then return 0, 0, 0, 1 end

	local m00, m01, m02 = A[a + 1] / sx, A[a + 2] / sy, A[a + 3] / sz
	local m10, m11, m12 = A[a + 5] / sx, A[a + 6] / sy, A[a + 7] / sz
	local m20, m21, m22 = A[a + 9] / sx, A[a + 10] / sy, A[a + 11] / sz
	return QuatFromRows(m00, m01, m02, m10, m11, m12, m20, m21, m22)
end

local weights = {}

local function quat_local(triggers, A, a, C, c)
	local x, y, z, w = quat_of(A, a)
	local n = #triggers
	local total = 0

	for i = 1, n do
		local tr = triggers[i]
		local q = tr.trigger
		local d = math_abs(q[1] * x + q[2] * y + q[3] * z + q[4] * w)

		if d > 1 then
			d = 1
		end

		local wt = math_max(0, 1 - 2 * math_acos(d) * tr.tol)
		weights[i] = wt
		total = total + wt
	end

	local qx, qy, qz, qw, px, py, pz = 0, 0, 0, 0, 0, 0, 0
	if total <= 0.001 then
		local t = triggers[1]
		qx, qy, qz, qw = t.quat[1], t.quat[2], t.quat[3], t.quat[4]
		px, py, pz = t.pos[1], t.pos[2], t.pos[3]
	else
		local invTotal = 1 / total
		for i = 1, n do
			local s = weights[i] * invTotal
			if s > 0 then
				local tr = triggers[i]
				local q = tr.quat

				if qx * q[1] + qy * q[2] + qz * q[3] + qw * q[4] < 0 then
					qx, qy, qz, qw = -qx, -qy, -qz, -qw
				end

				qx, qy, qz, qw = qx + s * q[1], qy + s * q[2], qz + s * q[3], qw + s * q[4]
				px, py, pz = px + s * tr.pos[1], py + s * tr.pos[2], pz + s * tr.pos[3]
			end
		end

		local l = math_sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
		if l > 1e-9 then
			qx, qy, qz, qw = qx / l, qy / l, qz / l, qw / l
		end
	end

	C[c + 1], C[c + 2], C[c + 3], C[c + 4] = 1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qw * qz), 2 * (qx * qz + qw * qy), px
	C[c + 5], C[c + 6], C[c + 7], C[c + 8] = 2 * (qx * qy + qw * qz), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qw * qx), py
	C[c + 9], C[c + 10], C[c + 11], C[c + 12] = 2 * (qx * qz - qw * qy), 2 * (qy * qz + qw * qx), 1 - 2 * (qx * qx + qy * qy), pz
end

function PMS.Solve(ent, map, ik, origin)
	local B, K, P, OFF, RL, Q = map.B, map.K, map.P, map.OFF, map.RL, map.Q
	local W, E, has, rot = map.W, map.E, map.HAS, map.ROT

	for k = 1, map.n do
		local o = k * 12 - 12
		local kind, p = K[k], P[k]
		local ok = (kind == MERGE or has[p]) and read(ent, B[k], E, o)
		has[k], rot[k] = ok, false

		if ok then
			local po = p * 12 - 12
			if kind == MERGE then
				place_merge(map, k, E, W, has, origin)
				local m = ik and ik[k]

				if m then
					copy(m, 0, W, o)
					rot[k] = true
				end
			elseif kind == ENGINE then
				if rot[p] then
					if K[p] == MERGE then
						mul_rot(E, po, OFF[p], T, 0)
					else
						copy(E, po, T, 0)
					end

					if inv(T, 0, T, 12) then
						mul(T, 12, E, o, T, 24)
						mul(W, po, T, 24, W, o)
					else
						copy(E, o, W, o)
					end

					rot[k] = true
				else
					copy(E, o, W, o)
					W[o + 4] = W[o + 4] + W[po + 4] - E[po + 4]
					W[o + 8] = W[o + 8] + W[po + 8] - E[po + 8]
					W[o + 12] = W[o + 12] + W[po + 12] - E[po + 12]
				end
			elseif kind == QUAT then
				local q = Q[k]
				if has[q.c] and has[q.cp] and inv(W, q.cp * 12 - 12, T, 0) then
					mul(T, 0, W, q.c * 12 - 12, T, 12)
					quat_local(q.triggers, T, 12, T, 24)
					mul(W, po, T, 24, W, o)
				else
					mul(W, po, RL[k], 0, W, o)
				end

				rot[k] = true
			else
				mul(W, po, RL[k], 0, W, o)
				rot[k] = true
			end

			write(ent, B[k], W, o)
		end
	end
end
