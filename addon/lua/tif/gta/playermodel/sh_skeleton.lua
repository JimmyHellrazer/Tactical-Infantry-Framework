-- From GrandTheftGMod 0.98 (playermodel/sh_skeleton.lua), trimmed for TIF: parts TIF uses. Built by tools/build_gta_bundle.py.
local PMS = TIFG.PMS


local string_lower, string_match, bit_band = string.lower, string.match, bit.band
local math_sqrt, math_abs = math.sqrt, math.abs

local M = {}
PMS.Math = M

function M.mul3(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end

function M.tr3(a) return { a[1], a[4], a[7], a[2], a[5], a[8], a[3], a[6], a[9] } end
function M.mulv(a, v)
	return { a[1] * v[1] + a[2] * v[2] + a[3] * v[3], a[4] * v[1] + a[5] * v[2] + a[6] * v[3], a[7] * v[1] + a[8] * v[2] + a[9] * v[3] }
end
function M.sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
function M.dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
function M.cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
function M.len(a) return math_sqrt(M.dot(a, a)) end

function M.unit(a)
	local l = M.len(a)
	if l < 1e-6 then return nil end
	return { a[1] / l, a[2] / l, a[3] / l }
end

M.IDENTITY = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

function M.swing(a, b)
	local v, c = M.cross(a, b), M.dot(a, b)
	if c > 0.999999 then return M.IDENTITY end
	if c < -0.999999 then
		local p = M.unit(M.cross(a, math_abs(a[1]) < 0.9 and { 1, 0, 0 } or { 0, 1, 0 }))
		local x, y, z = p[1], p[2], p[3]
		return { 2 * x * x - 1, 2 * x * y, 2 * x * z, 2 * x * y, 2 * y * y - 1, 2 * y * z, 2 * x * z, 2 * y * z, 2 * z * z - 1 }
	end
	local k = 1 / (1 + c)
	local x, y, z = v[1], v[2], v[3]
	return {
		1 - (y * y + z * z) * k, -z + x * y * k, y + x * z * k,
		z + x * y * k, 1 - (x * x + z * z) * k, -x + y * z * k,
		-y + x * z * k, x + y * z * k, 1 - (x * x + y * y) * k,
	}
end

function M.frame(a, b)
	local d = M.dot(b, a)
	local n = M.unit({ b[1] - a[1] * d, b[2] - a[2] * d, b[3] - a[3] * d })
	if not n then return nil end
	local c = M.cross(a, n)
	return { a[1], n[1], c[1], a[2], n[2], c[2], a[3], n[3], c[3] }
end

local HDR_NUMBONES = 156
local BONE_SIZE, BONE_POSETOBONE, BONE_FLAGS, BONE_PROCTYPE, BONE_PROCINDEX = 216, 96, 160, 164, 168
local TRIGGER_SIZE = 48
local HDR_NUMHITBOXSETS, HITBOX_SIZE = 172, 68
local MAX_BONES, MAX_TRIGGERS, MAX_HITBOXES = 256, 32, 256
local VERTEX_MASK = 0x0003FC00

PMS.PROC_QUAT, PMS.PROC_JIGGLE = 2, 5

local PELVIS = "valvebiped.bip01_pelvis"
local L_THIGH, R_THIGH = "valvebiped.bip01_l_thigh", "valvebiped.bip01_r_thigh"

PMS.Required = {
	PELVIS, "valvebiped.bip01_spine",
	L_THIGH, "valvebiped.bip01_l_calf", "valvebiped.bip01_l_foot",
	R_THIGH, "valvebiped.bip01_r_calf", "valvebiped.bip01_r_foot",
	"valvebiped.bip01_l_upperarm", "valvebiped.bip01_l_forearm", "valvebiped.bip01_l_hand",
	"valvebiped.bip01_r_upperarm", "valvebiped.bip01_r_forearm", "valvebiped.bip01_r_hand",
}
local UP_BONES = { "valvebiped.bip01_head1", "valvebiped.bip01_neck1", "valvebiped.bip01_spine4", "valvebiped.bip01_spine2",
	"valvebiped.bip01_spine1", "valvebiped.bip01_spine" }

local function read_name(f, at)
	f:Seek(at)
	return string_lower(string_match(f:Read(64) or "", "^[^%z]*"))
end

local function read_floats(f, at, n, out)
	f:Seek(at)
	for k = 1, n do out[k] = f:ReadFloat() end
	return out
end

local function read_quat_rule(f, at, size)
	f:Seek(at)
	local control, count, index = f:ReadLong(), f:ReadLong(), f:ReadLong()
	if count < 1 or count > MAX_TRIGGERS or at + index < 0 or at + index + count * TRIGGER_SIZE > size then return nil end
	local triggers = {}
	for k = 1, count do
		local v = read_floats(f, at + index + (k - 1) * TRIGGER_SIZE, 12, {})
		triggers[k] = { tol = v[1], trigger = { v[2], v[3], v[4], v[5] }, pos = { v[6], v[7], v[8] }, quat = { v[9], v[10], v[11], v[12] } }
	end
	return { control = control, triggers = triggers }
end

local function read_hitboxes(f, size, n)
	f:Seek(HDR_NUMHITBOXSETS)
	local sets, at = f:ReadLong(), f:ReadLong()
	if sets < 1 or at < 0 or at + 12 > size then return {} end
	f:Seek(at + 4)
	local count, index = f:ReadLong(), f:ReadLong()
	if count < 0 or count > MAX_HITBOXES or at + index < 0 or at + index + count * HITBOX_SIZE > size then return {} end
	local out, v = {}, {}
	for h = 0, count - 1 do
		local o = at + index + h * HITBOX_SIZE
		f:Seek(o)
		local bone, group = f:ReadLong(), f:ReadLong()
		read_floats(f, o + 8, 6, v)
		if bone >= 0 and bone < n then
			out[#out + 1] = { bone = bone, group = group, index = h, min = { v[1], v[2], v[3] }, max = { v[4], v[5], v[6] } }
		end
	end
	return out
end

local BONE_GROUP = {
	["valvebiped.bip01_head1"] = HITGROUP_HEAD,
	["valvebiped.bip01_neck1"] = HITGROUP_CHEST, ["valvebiped.bip01_spine2"] = HITGROUP_CHEST,
	["valvebiped.bip01_spine3"] = HITGROUP_CHEST, ["valvebiped.bip01_spine4"] = HITGROUP_CHEST,
	["valvebiped.bip01_l_clavicle"] = HITGROUP_CHEST, ["valvebiped.bip01_r_clavicle"] = HITGROUP_CHEST,
	["valvebiped.bip01_pelvis"] = HITGROUP_STOMACH, ["valvebiped.bip01_spine"] = HITGROUP_STOMACH,
	["valvebiped.bip01_spine1"] = HITGROUP_STOMACH,
	["valvebiped.bip01_l_upperarm"] = HITGROUP_LEFTARM, ["valvebiped.bip01_r_upperarm"] = HITGROUP_RIGHTARM,
	["valvebiped.bip01_l_thigh"] = HITGROUP_LEFTLEG, ["valvebiped.bip01_r_thigh"] = HITGROUP_RIGHTLEG,
}

local function group_of(sk, i)
	while i >= 0 do
		local g = BONE_GROUP[sk.name[i]]
		if g then return g end
		i = sk.parent[i]
	end
	return HITGROUP_GENERIC
end

local function infer_groups(sk)
	for _, h in ipairs(sk.hitboxes) do
		if h.group ~= HITGROUP_GENERIC then return end
	end
	for _, h in ipairs(sk.hitboxes) do h.group = group_of(sk, h.bone) end
end

local function read_bones(f, size)
	if size < HDR_NUMBONES + 8 or f:Read(4) ~= "IDST" then return nil end
	f:Seek(HDR_NUMBONES)
	local n, base = f:ReadLong(), f:ReadLong()
	if n < 1 or n > MAX_BONES or base < 0 or base + n * BONE_SIZE > size then return nil end
	local sk = { n = n, name = {}, index = {}, parent = {}, R = {}, t = {}, weighted = {}, proc = {}, rule = {} }
	local p = {}
	for i = 0, n - 1 do
		local o = base + i * BONE_SIZE
		f:Seek(o)
		local name_at, parent = f:ReadLong(), f:ReadLong()
		read_floats(f, o + BONE_POSETOBONE, 12, p)
		f:Seek(o + BONE_FLAGS)
		local flags, proctype, procindex = f:ReadLong(), f:ReadLong(), f:ReadLong()
		local name = read_name(f, o + name_at)
		if parent < -1 or parent >= i then return nil end
		local R = { p[1], p[5], p[9], p[2], p[6], p[10], p[3], p[7], p[11] }
		sk.R[i] = R
		sk.t[i] = { -(R[1] * p[4] + R[2] * p[8] + R[3] * p[12]), -(R[4] * p[4] + R[5] * p[8] + R[6] * p[12]),
			-(R[7] * p[4] + R[8] * p[8] + R[9] * p[12]) }
		sk.name[i], sk.parent[i] = name, parent
		sk.weighted[i] = bit_band(flags, VERTEX_MASK) ~= 0
		sk.proc[i] = procindex ~= 0 and proctype or 0
		if sk.proc[i] == PMS.PROC_QUAT then sk.rule[i] = read_quat_rule(f, o + procindex, size) end
		if not sk.index[name] then sk.index[name] = i end
	end
	sk.hitboxes = read_hitboxes(f, size, n)
	infer_groups(sk)
	return sk
end

local function to_entity_space(sk)
	local ix, top = sk.index, nil
	for _, name in ipairs(UP_BONES) do
		if ix[name] then top = ix[name] break end
	end
	local up = M.unit(M.sub(sk.t[top], sk.t[ix[PELVIS]]))
	local left = up and M.sub(sk.t[ix[L_THIGH]], sk.t[ix[R_THIGH]])
	if not left then return false end
	local d = M.dot(left, up)
	left = M.unit({ left[1] - up[1] * d, left[2] - up[2] * d, left[3] - up[3] * d })
	if not left then return false end
	local fwd = M.cross(left, up)
	local W = { fwd[1], fwd[2], fwd[3], left[1], left[2], left[3], up[1], up[2], up[3] }
	for i = 0, sk.n - 1 do
		sk.R[i] = M.mul3(W, sk.R[i])
		sk.t[i] = M.mulv(W, sk.t[i])
	end
	return true
end

function PMS.ParseSkeleton(path)
	local f = file.Open(path, "rb", "GAME")
	if not f then return nil end
	local ok, sk = pcall(read_bones, f, f:Size())
	f:Close()
	if not ok or not sk then return nil end
	for _, name in ipairs(PMS.Required) do
		if not sk.index[name] then return nil end
	end
	if not to_entity_space(sk) then return nil end
	return sk
end

PMS.Skeletons = {}
PMS.SkeletonRetry = {}

function PMS.Skeleton(model)
	model = string_lower(model)
	local sk = PMS.Skeletons[model]
	-- (TIF) A failed read is tried again after 10 s (the model may not have been readable yet).
	if sk == nil or (sk == false and CurTime() >= (PMS.SkeletonRetry[model] or 0)) then
		sk = PMS.ParseSkeleton(model) or false
		PMS.Skeletons[model] = sk
		if not sk then PMS.SkeletonRetry[model] = CurTime() + 10 end
	end
	return sk or nil
end

PMS.OddRatio = 1.25
PMS.Limbs = {
	{ "valvebiped.bip01_r_upperarm", "valvebiped.bip01_r_forearm" }, { "valvebiped.bip01_r_forearm", "valvebiped.bip01_r_hand" },
	{ "valvebiped.bip01_l_upperarm", "valvebiped.bip01_l_forearm" }, { "valvebiped.bip01_l_forearm", "valvebiped.bip01_l_hand" },
	{ "valvebiped.bip01_r_thigh", "valvebiped.bip01_r_calf" }, { "valvebiped.bip01_r_calf", "valvebiped.bip01_r_foot" },
	{ "valvebiped.bip01_l_thigh", "valvebiped.bip01_l_calf" }, { "valvebiped.bip01_l_calf", "valvebiped.bip01_l_foot" },
}

local function dist(sk, a, b)
	local ia, ib = sk.index[a], sk.index[b]
	if not (ia and ib) then return nil end
	return M.len(M.sub(sk.t[ia], sk.t[ib]))
end

function PMS.Oddness(lsk, fsk)
	local worst = 1
	local function take(a, b)
		if a and b and a > 0.01 and b > 0.01 then worst = math.max(worst, a / b, b / a) end
	end
	for _, l in ipairs(PMS.Limbs) do take(dist(fsk, l[1], l[2]), dist(lsk, l[1], l[2])) end
	local fp, lp = fsk.t[fsk.index[PELVIS]], lsk.t[lsk.index[PELVIS]]
	take(fp[3], lp[3])
	local R, L = "valvebiped.bip01_r_upperarm", "valvebiped.bip01_l_upperarm"
	take(dist(fsk, R, L), dist(lsk, R, L))
	take(fsk.t[fsk.index[R]][3] - fp[3], lsk.t[lsk.index[R]][3] - lp[3])
	return worst
end

function PMS.ResetMaps()
	PMS.Maps = {}
	PMS.Gen = (PMS.Gen or 0) + 1
end

if PMS.Maps then PMS.ResetMaps() end
