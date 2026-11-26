local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local VM = {}
VM.__index = VM
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VM) end
VM.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VM.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VM.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function VM:DistToSqr(o) local d = self - o return d.x * d.x + d.y * d.y + d.z * d.z end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Matrix() return {} end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
math.Approach = function(c, t, d) if c < t then return math.min(t, c + d) end return math.max(t, c - d) end
math.AngleDifference = function(a, b) return (a - b + 180) % 360 - 180 end
function Lerp(t, a, b) return a + (b - a) * t end
local cv = {}
function CreateClientConVar(n, d) local c = { v = d } c.GetBool = function() return tonumber(c.v) ~= 0 end c.GetFloat = function() return tonumber(c.v) end c.GetInt = function() return tonumber(c.v) end cv[n] = c return c end
local frame = 1
function FrameNumber() return frame end
local eye = Vector(0, 0, 0)
function EyePos() return eye end
MASK_PLAYERSOLID_BRUSHONLY = 1
local groundZ = 6
util = { TraceLine = function(t) return { Hit = true, HitPos = Vector(t.start.x, t.start.y, groundZ), HitNormal = Vector(0, 0, 1) } end }
TIF = { Body = { State = function() return nil end } }
assert(loadfile(ROOT .. "tif/npc/cl_feet.lua"))()
local F = TIF.Feet

local BONES = { "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot",
	"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot" }
local PARENT = { [0] = -1, 0, 1, 2, 0, 4, 5 }
local function soldier(pos)
	local e = { pos = pos, yaw = 0 }
	e.GetPos = function() return e.pos end
	e.GetModel = function() return "m" end
	e.LookupBone = function(_, n) for i, b in ipairs(BONES) do if b == n then return i - 1 end end end
	e.GetBoneCount = function() return #BONES end
	e.GetBoneParent = function(_, b) return PARENT[b] end
	e.GetBoneMatrix = function(_, b) return { GetTranslation = function() return Vector(e.pos.x + (b == 3 and 4 or -4), e.pos.y, e.pos.z + 2) end } end
	e.AddCallback = function() return 1 end
	e.GetAngles = function() return Angle(0, e.yaw, 0) end
	return e
end
local function st(speed, extra)
	local s = { vb = true, speed2d = speed, actName = "" }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end
local function run(e, s, n, dt)
	for _ = 1, n do
		frame = frame + 1
		F.Prepare(e, s, 0, dt or 0.05)
	end
end

local a, sa = soldier(Vector(100, 0, 0)), st(0)
run(a, sa, 30)
check(sa.footW > 0.95, "near and still: foot IK on (" .. sa.footW .. ")")
check(sa.footOff and math.abs(sa.footOff[1] - 6) < 0.5, "foot offset settles on the ground 6 up (" .. tostring(sa.footOff and sa.footOff[1]) .. ")")
local b, sb = soldier(Vector(5000, 0, 0)), st(0)
run(b, sb, 30)
check(sb.footW < 0.01, "beyond tif_foot_ik_range: off")
local c, sc = soldier(Vector(100, 0, 0)), st(200)
run(c, sc, 30)
check(sc.footW < 0.01, "running: off")
local d, sd = soldier(Vector(100, 0, 0)), st(100)
run(d, sd, 30)
check(sd.footW > 0.3 and sd.footW < 0.8, "jogging pace: partly faded (" .. sd.footW .. ")")
local p, sp = soldier(Vector(100, 0, 0)), st(0, { vbProne = 2 })
run(p, sp, 30)
check(sp.footW < 0.01, "prone: off")
local m, sm = soldier(Vector(100, 0, 0)), st(0, { actName = "mwme_fight_a" })
run(m, sm, 30)
check(sm.footW < 0.01, "melee / other full-body actions: off")
local t, stt = soldier(Vector(100, 0, 0)), st(0, { actName = "mwt_turn_stand_4" })
run(t, stt, 30)
check(stt.footW > 0.95, "transitions (turns, starts, stops): on")

frame = frame + 1
local many = {}
for i = 1, 16 do many[i] = { soldier(Vector(100 + i, 0, 0)), st(0, { footW = 1 }) } end
for _, x in ipairs(many) do F.Prepare(x[1], x[2], 0, 0.05) end
local on = 0
for _, x in ipairs(many) do if x[2].footW >= 0.99 then on = on + 1 end end
check(on == 12, "at most tif_foot_ik_max (12) soldiers a frame (" .. on .. ")")

local r, sr = soldier(Vector(100, 0, 0)), st(220)
for i = 1, 20 do
	r.yaw = r.yaw + 4
	frame = frame + 1
	F.Prepare(r, sr, 0, 0.05)
end
check(sr.leanW < -2, "running and turning left: leans left (" .. sr.leanW .. ")")
local w, sw = soldier(Vector(100, 0, 0)), st(60)
for i = 1, 20 do
	w.yaw = w.yaw + 4
	frame = frame + 1
	F.Prepare(w, sw, 0, 0.05)
end
check(math.abs(sw.leanW) < 0.05, "walking: no lean")
cv.tif_turn_lean.v = "0"
local o, so = soldier(Vector(100, 0, 0)), st(220)
for i = 1, 20 do o.yaw = o.yaw + 4 frame = frame + 1 F.Prepare(o, so, 0, 0.05) end
check(math.abs(so.leanW) < 0.05, "tif_turn_lean 0: no lean")
print(string.format("passed %d, failed %d", pass, fail))
