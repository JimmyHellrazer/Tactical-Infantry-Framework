local PMS = TIFG.PMS
local MERGE = PMS.MERGE
local math_abs = math.abs

local OUT = Matrix()
local IN = Matrix()
local ENTITY, VMATRIX = FindMetaTable("Entity"), FindMetaTable("VMatrix")
local GetBoneMatrix, CopyBoneMatrix, SetBoneMatrix = ENTITY.GetBoneMatrix, ENTITY.CopyBoneMatrix, ENTITY.SetBoneMatrix
local Unpack, SetUnpacked, SetField = VMATRIX.Unpack, VMATRIX.SetUnpacked, VMATRIX.SetField

local function read(ent, bone, A, o)
	if CopyBoneMatrix and TIF and TIF.FAST_BONE_COPY then
		SetField(IN, 4, 4, 0)
		CopyBoneMatrix(ent, bone, IN)
		local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, _, _, _, m16 = Unpack(IN)
		if m16 == 0 then return false end

		A[o + 1], A[o + 2], A[o + 3], A[o + 4], A[o + 5], A[o + 6], A[o + 7], A[o + 8], A[o + 9], A[o + 10], A[o + 11], A[o + 12] =
			a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12
		return true
	end

	local m = GetBoneMatrix(ent, bone)
	if not m then return false end

	A[o + 1], A[o + 2], A[o + 3], A[o + 4], A[o + 5], A[o + 6], A[o + 7], A[o + 8], A[o + 9], A[o + 10], A[o + 11], A[o + 12] = Unpack(m)
	return true
end

local function write(ent, bone, A, o)
	SetUnpacked(OUT, A[o + 1], A[o + 2], A[o + 3], A[o + 4], A[o + 5], A[o + 6], A[o + 7], A[o + 8],
		A[o + 9], A[o + 10], A[o + 11], A[o + 12], 0, 0, 0, 1)
	SetBoneMatrix(ent, bone, OUT)
end

local function copy(A, a, C, c)
	for i = 1, 12 do
		C[c + i] = A[a + i]
	end
end

local function mul(A, a, B, b, C, c)
	local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 =
		A[a + 1], A[a + 2], A[a + 3], A[a + 4], A[a + 5], A[a + 6], A[a + 7], A[a + 8], A[a + 9], A[a + 10], A[a + 11], A[a + 12]
	local b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12 =
		B[b + 1], B[b + 2], B[b + 3], B[b + 4], B[b + 5], B[b + 6], B[b + 7], B[b + 8], B[b + 9], B[b + 10], B[b + 11], B[b + 12]
	C[c + 1], C[c + 2], C[c + 3] = a1 * b1 + a2 * b5 + a3 * b9, a1 * b2 + a2 * b6 + a3 * b10, a1 * b3 + a2 * b7 + a3 * b11
	C[c + 4] = a1 * b4 + a2 * b8 + a3 * b12 + a4
	C[c + 5], C[c + 6], C[c + 7] = a5 * b1 + a6 * b5 + a7 * b9, a5 * b2 + a6 * b6 + a7 * b10, a5 * b3 + a6 * b7 + a7 * b11
	C[c + 8] = a5 * b4 + a6 * b8 + a7 * b12 + a8
	C[c + 9], C[c + 10], C[c + 11] = a9 * b1 + a10 * b5 + a11 * b9, a9 * b2 + a10 * b6 + a11 * b10, a9 * b3 + a10 * b7 + a11 * b11
	C[c + 12] = a9 * b4 + a10 * b8 + a11 * b12 + a12
end

local function mul_rot(A, a, R, C, c)
	local a1, a2, a3, a5, a6, a7, a9, a10, a11 = A[a + 1], A[a + 2], A[a + 3], A[a + 5], A[a + 6], A[a + 7], A[a + 9], A[a + 10], A[a + 11]
	C[c + 1], C[c + 2], C[c + 3] = a1 * R[1] + a2 * R[4] + a3 * R[7], a1 * R[2] + a2 * R[5] + a3 * R[8], a1 * R[3] + a2 * R[6] + a3 * R[9]
	C[c + 5], C[c + 6], C[c + 7] = a5 * R[1] + a6 * R[4] + a7 * R[7], a5 * R[2] + a6 * R[5] + a7 * R[8], a5 * R[3] + a6 * R[6] + a7 * R[9]
	C[c + 9], C[c + 10], C[c + 11] = a9 * R[1] + a10 * R[4] + a11 * R[7], a9 * R[2] + a10 * R[5] + a11 * R[8], a9 * R[3] + a10 * R[6] + a11 * R[9]
	C[c + 4], C[c + 8], C[c + 12] = A[a + 4], A[a + 8], A[a + 12]
end

local function inv(A, a, C, c)
	local m1, m2, m3, m5, m6, m7, m9, m10, m11 = A[a + 1], A[a + 2], A[a + 3], A[a + 5], A[a + 6], A[a + 7], A[a + 9], A[a + 10], A[a + 11]
	local tx, ty, tz = A[a + 4], A[a + 8], A[a + 12]
	local c1, c2, c3 = m6 * m11 - m7 * m10, m7 * m9 - m5 * m11, m5 * m10 - m6 * m9
	local d = m1 * c1 + m2 * c2 + m3 * c3
	if math_abs(d) < 1e-12 then return false end

	d = 1 / d
	local r1, r2, r3 = c1 * d, (m3 * m10 - m2 * m11) * d, (m2 * m7 - m3 * m6) * d
	local r5, r6, r7 = c2 * d, (m1 * m11 - m3 * m9) * d, (m3 * m5 - m1 * m7) * d
	local r9, r10, r11 = c3 * d, (m2 * m9 - m1 * m10) * d, (m1 * m6 - m2 * m5) * d
	C[c + 1], C[c + 2], C[c + 3], C[c + 4] = r1, r2, r3, -(r1 * tx + r2 * ty + r3 * tz)
	C[c + 5], C[c + 6], C[c + 7], C[c + 8] = r5, r6, r7, -(r5 * tx + r6 * ty + r7 * tz)
	C[c + 9], C[c + 10], C[c + 11], C[c + 12] = r9, r10, r11, -(r9 * tx + r10 * ty + r11 * tz)
	return true
end

local function turn(A, a, Q, x, y, z, C, c)
	local a1, a2, a3, a5, a6, a7, a9, a10, a11 = A[a + 1], A[a + 2], A[a + 3], A[a + 5], A[a + 6], A[a + 7], A[a + 9], A[a + 10], A[a + 11]
	C[c + 1], C[c + 2], C[c + 3] = Q[1] * a1 + Q[2] * a5 + Q[3] * a9, Q[1] * a2 + Q[2] * a6 + Q[3] * a10, Q[1] * a3 + Q[2] * a7 + Q[3] * a11
	C[c + 5], C[c + 6], C[c + 7] = Q[4] * a1 + Q[5] * a5 + Q[6] * a9, Q[4] * a2 + Q[5] * a6 + Q[6] * a10, Q[4] * a3 + Q[5] * a7 + Q[6] * a11
	C[c + 9], C[c + 10], C[c + 11] = Q[7] * a1 + Q[8] * a5 + Q[9] * a9, Q[7] * a2 + Q[8] * a6 + Q[9] * a10, Q[7] * a3 + Q[8] * a7 + Q[9] * a11
	C[c + 4], C[c + 8], C[c + 12] = x, y, z
end

local function place_merge(map, k, E, W, has, origin)
	local o = k * 12 - 12
	mul_rot(E, o, map.OFF[k], W, o)
	local s = map.scale

	if k == map.root and s ~= 1 and origin then
		W[o + 4] = origin.x + (W[o + 4] - origin.x) * s
		W[o + 8] = origin.y + (W[o + 8] - origin.y) * s
		W[o + 12] = origin.z + (W[o + 12] - origin.z) * s
	end

	local fk, p = map.FK[k], map.P[k]
	if fk and p ~= 0 and has[p] then
		local po = p * 12 - 12
		local x, y, z = fk[1], fk[2], fk[3]
		W[o + 4] = W[po + 1] * x + W[po + 2] * y + W[po + 3] * z + W[po + 4]
		W[o + 8] = W[po + 5] * x + W[po + 6] * y + W[po + 7] * z + W[po + 8]
		W[o + 12] = W[po + 9] * x + W[po + 10] * y + W[po + 11] * z + W[po + 12]
	end
end

function PMS.Chain(src, map, origin, steps)
	local W, E, has = map.SW, map.SE, map.SH
	local K, P, RL = map.K, map.P, map.RL

	for i = 1, #steps do
		local k = steps[i]
		local o, p = k * 12 - 12, P[k]
		local ok

		if K[k] == MERGE then
			ok = read(src, map.LB[k], E, o)

			if ok then
				place_merge(map, k, E, W, has, origin)
			end
		else
			ok = p ~= 0 and has[p]

			if ok then
				mul(W, p * 12 - 12, RL[k], 0, W, o)
			end
		end

		has[k] = ok
		if not ok then return false end
	end

	return true
end

PMS.Flat = { read = read, write = write, copy = copy, mul = mul, mul_rot = mul_rot, inv = inv, turn = turn, place_merge = place_merge }
