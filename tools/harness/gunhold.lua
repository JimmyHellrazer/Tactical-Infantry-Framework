SysTime = SysTime or os.clock
-- Offline: cl_gunhold.lua (0.18.0): left-hand two-bone IK, notetrack weights, sling poses. GMod Matrix / Vector
-- mocked with plain 4x4 math.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local function near(a, b, eps) return math.abs(a - b) < (eps or 0.05) end

local V = {}
V.__index = V
function Vector(x, y, z)
	if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Cross(o) return Vector(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x) end
function V:Length() return math.sqrt(self:Dot(self)) end
function V:LengthSqr() return self:Dot(self) end
function V:Distance(o) return (self - o):Length() end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:GetNormalized() local l = self:Length() return l > 0 and self * (1 / l) or Vector() end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
vector_origin = Vector()
angle_zero = {}

local MM = {}
MM.__index = MM
function Matrix(t)
	local m = setmetatable({ r = {} }, MM)
	for i = 1, 4 do
		m.r[i] = {}
		for j = 1, 4 do
			if t and t.r then m.r[i][j] = t.r[i][j]
			elseif t then m.r[i][j] = t[i][j]
			else m.r[i][j] = i == j and 1 or 0 end
		end
	end
	return m
end
function MM:SetTranslation(v) self.r[1][4], self.r[2][4], self.r[3][4] = v.x, v.y, v.z end
function MM:GetTranslation() return Vector(self.r[1][4], self.r[2][4], self.r[3][4]) end
function MM:GetRight() return Vector(-self.r[1][2], -self.r[2][2], -self.r[3][2]) end
MM.__mul = function(a, b)
	if getmetatable(b) == V then
		local r = a.r
		return Vector(r[1][1] * b.x + r[1][2] * b.y + r[1][3] * b.z, r[2][1] * b.x + r[2][2] * b.y + r[2][3] * b.z,
			r[3][1] * b.x + r[3][2] * b.y + r[3][3] * b.z)
	end
	local m = Matrix()
	for i = 1, 4 do for j = 1, 4 do
		local s = 0
		for k = 1, 4 do s = s + a.r[i][k] * b.r[k][j] end
		m.r[i][j] = s
	end end
	return m
end
function MM:GetInverseTR()
	local m = Matrix()
	for i = 1, 3 do for j = 1, 3 do m.r[i][j] = self.r[j][i] end end
	local t = self:GetTranslation()
	for i = 1, 3 do m.r[i][4] = -(m.r[i][1] * t.x + m.r[i][2] * t.y + m.r[i][3] * t.z) end
	return m
end
-- (Matrix * Vector in GMod includes translation for points; our IK only multiplies pure rotations by vectors.)
function LerpVector(t, a, b) return a + (b - a) * t end
-- (Angles stay opaque here: the hand turn is checked for running, not for its numbers.)
function MM:SetAngles() end
function MM:GetAngles() return {} end
function LerpAngle(t, a, b) return b end
function LocalToWorld(p) return p end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
math.Approach = function(c, t, s) if c < t then return math.min(c + s, t) end return math.max(c - s, t) end
function IsValid(x) return x ~= nil end
function istable(x) return type(x) == "table" end
function CreateClientConVar() return { GetBool = function() return true end } end
function FrameTime() return 1 end
function EyePos() return Vector() end
function CurTime() return 0 end
function FrameNumber() return 100 end
timer = { Create = function() end }

-- A host with a left arm: shoulder at origin, elbow 12 out along x and bent down, hand 11 further.
local bones = {
	{ name = "ValveBiped.Bip01_L_UpperArm", parent = -1, pos = Vector(0, 0, 0) },
	{ name = "ValveBiped.Bip01_L_Forearm", parent = 0, pos = Vector(10, 0, -6) },
	{ name = "ValveBiped.Bip01_L_Hand", parent = 1, pos = Vector(16, 4, -14) },
	{ name = "ValveBiped.Bip01_L_Finger0", parent = 2, pos = Vector(18, 5, -15) },
	{ name = "ValveBiped.Bip01_L_Ulna", parent = 1, pos = Vector(13, 2, -10) },
}
local mats = {}
for i, b in ipairs(bones) do local m = Matrix() m:SetTranslation(b.pos) mats[i - 1] = m end
local target = Vector(19, 6, -10) -- 5.4 from the clip's hand: inside IK_NEAR, full IK
local cb
local host = {
	GetModel = function() return "host" end,
	LookupBone = function(_, n) for i, b in ipairs(bones) do if b.name == n then return i - 1 end end end,
	GetBoneCount = function() return #bones end,
	GetBoneParent = function(_, i) return bones[i + 1].parent end,
	GetBoneMatrix = function(_, i) return mats[i] end,
	SetBoneMatrix = function(_, i, m) mats[i] = m end,
	AddCallback = function(_, _, f) cb = f return 1 end,
	GetPos = function() return Vector() end,
}
local gun = { GetModel = function() return "gun" end }
local st = { gun = gun, ikW = 1, writeFrame = 100 }
TIF = { GTG = { WeaponKind = function() return "rifle" end }, Body = {
	State = function() return st end,
	GunInfo = function() return { gripL = target, grip = Vector(), inv = Matrix() } end,
	GunPose = function() return Vector(), {} end,
} }
dofile(ROOT .. "tif/npc/cl_gunhold.lua")
local GH = TIF.GunHold
local lenA0 = bones[1].pos:Distance(bones[2].pos)
local lenB0 = bones[2].pos:Distance(bones[3].pos)
local fingerOff0 = bones[4].pos - bones[3].pos
GH.Prepare(host, st, 0)
check(cb ~= nil, "IK callback added to the host")
st.ikW = 1
cb(host)
local A, Bq, C = mats[0]:GetTranslation(), mats[1]:GetTranslation(), mats[2]:GetTranslation()
check(C:Distance(target) < 0.05, "hand reaches the grip: " .. C:Distance(target))
check(near(A:Distance(Bq), lenA0), "upper arm length kept")
check(near(Bq:Distance(C), lenB0), "forearm length kept")
check(Bq.z < 0, "elbow keeps bending the same way (down)")
check(near((mats[3]:GetTranslation() - C):Length(), fingerOff0:Length()), "fingers follow the hand")
check(mats[4]:GetTranslation():Distance(Bq) < 20, "forearm helper bone follows the forearm")
-- Clip hand far from the grip: no IK.
for i, b in ipairs(bones) do local m = Matrix() m:SetTranslation(b.pos) mats[i - 1] = m end
TIF.Body.GunInfo = function() return { gripL = Vector(60, 40, 30), grip = Vector(), inv = Matrix() } end
cb(host)
check(mats[2]:GetTranslation():Distance(bones[3].pos) < 0.001, "far grip (clip hand elsewhere): untouched")

-- Notetrack weights
local clip = { tags = { { "MoveEvent", 0.1, 0.1, { MoveEvent = "ik_out_start_left_hand" } },
	{ "MoveEvent", 0.2, 0.2, { MoveEvent = "ik_out_end_left_hand" } },
	{ "MoveEvent", 0.7, 0.7, { MoveEvent = "ik_in_start_left_hand" } },
	{ "MoveEvent", 0.8, 0.8, { MoveEvent = "ik_in_end_left_hand" } } } }
check(GH.ClipIK(clip, 0.05) == 1, "before ik_out: on the gun")
check(near(GH.ClipIK(clip, 0.15), 0.5), "letting go: half")
check(GH.ClipIK(clip, 0.5) == 0, "off the gun mid reload")
check(near(GH.ClipIK(clip, 0.75), 0.5), "coming back: half")
check(GH.ClipIK(clip, 0.9) == 1, "back on the gun")
check(GH.ClipIK({ tags = {} }, 0.5) == 1, "clip without notetracks: on")
check(GH.ClipIK(nil, nil) == 1, "no clip: on")
-- Swing rotation helper (kept for the IK).
do
	local a, b = Vector(1, 0, 0), Vector(0.6, 0.8, 0)
	local r = GH.RotBetween(a, b) * a
	check(near(r.x, 0.6, 0.001) and near(r.y, 0.8, 0.001) and near(r.z, 0, 0.001), "rotation maps one direction onto another")
end
-- Finger pose: local rotation becomes the pose's, length kept, children follow.
do
	local fb = {
		{ name = "ValveBiped.Bip01_L_Hand", parent = -1, pos = Vector(0, 0, 0) },
		{ name = "ValveBiped.Bip01_L_Finger1", parent = 0, pos = Vector(3, 0, 0) },
		{ name = "ValveBiped.Bip01_L_Finger11", parent = 1, pos = Vector(4.5, 0, 0) },
	}
	local fm = {}
	for i, b in ipairs(fb) do local m = Matrix() m:SetTranslation(b.pos) fm[i - 1] = m end
	local fe = {
		GetModel = function() return "fingers" end,
		LookupBone = function(_, n) for i, b in ipairs(fb) do if b.name == n then return i - 1 end end end,
		GetBoneParent = function(_, i) return fb[i + 1].parent end,
		GetBoneMatrix = function(_, i) return fm[i] end,
		SetBoneMatrix = function(_, i, m) fm[i] = m end,
	}
	-- 90 degrees about z for both finger bones (row-major 3x3)
	local R = { 0, -1, 0, 1, 0, 0, 0, 0, 1 }
	GH.ApplyFingers(fe, { ["ValveBiped.Bip01_L_Finger1"] = R, ["ValveBiped.Bip01_L_Finger11"] = R })
	local f1, f11 = fm[1]:GetTranslation(), fm[2]:GetTranslation()
	check(near(f1.x, 3) and near(f1.y, 0), "first knuckle stays at its offset from the hand")
	check(near(f1:Distance(f11), 1.5), "finger segment length kept: " .. f1:Distance(f11))
	check(near(f11.x, 3) and near(f11.y, 1.5), "curled 90 degrees: next joint turned with it")
end
st.writeFrame = 99
local sets = 0
local realSet = host.SetBoneMatrix
host.SetBoneMatrix = function(...) sets = sets + 1 return realSet(...) end
cb(host)
check(sets == 0, "a bone build TIF didn't ask for this frame (shadow / early): no IK")
host.SetBoneMatrix = realSet
st.writeFrame = 100
print(string.format("passed %d, failed %d", pass, fail))
