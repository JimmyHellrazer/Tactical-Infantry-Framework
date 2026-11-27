-- Offline (0.38.8): hip turn for forward-only walks, calm wading falling back to the gun-up wades off-axis.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
local src = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
local block = src:match("(local function add%(t, clip, w%).-\n)local function ub_targets")
check(block ~= nil, "leg_targets block")
local Bd = {}
local A = { PickDir = function(set, ang) return set[1].clip, set[1].clip, 0 end }
local env = setmetatable({ Bd = Bd, A = A, CurTime = function() return 0 end }, { __index = _G })
local leg_targets = assert(load(block .. "\nreturn leg_targets", "lt", "t", env))()

local function c(n, sp) return { name = n, speed = sp or 50, dur = 1 } end
local dirset = { { clip = c("strafe"), ang = 0 }, speed = 60 }
local legs = {
	relaxed = { idle = c("idle"), walk = c("walk"), run = c("run"), sprint = c("sprint"), walkSpeed = 60, runSpeed = 180, sprintSpeed = 260 },
	aim = { idle = c("aidle"), walk = dirset, run = dirset, walkSpeed = 60, runSpeed = 180 },
	crouch = { idle = c("cidle"), walk = dirset, run = dirset, walkSpeed = 50, runSpeed = 90 },
	alert = { idle = c("alidle"), walk = c("alwalk"), walkSpeed = 50 },
	wade = { aim = { idle = c("wdidle"), walk = dirset, run = dirset, walkSpeed = 50, runSpeed = 90 },
		knee = { idle = c("kidle"), walk = c("kwalk"), walkSpeed = 50 } },
}
local function run(st, mode, speed, rel)
	st.idleVar = st.idleVar or 0
	st.legCycle = st.legCycle or {}
	local T = leg_targets(st, legs, mode, 0, speed, rel)
	local names = {}
	for k, w in pairs(T) do if w > 0.01 then names[k.name] = w end end
	return names
end

-- calm walk, 40 deg off: the forward walk with the hips turned 40 left
local st = {}
local n = run(st, 0, 60, 40)
check(n.walk and math.abs(st.hipWant - 40) < 0.5, "calm walk 40 off: hips 40 (" .. tostring(st.hipWant) .. ")")
run(st, 0, 60, -30)
check(math.abs(st.hipWant + 30) < 0.5, "to the right: -30 (" .. tostring(st.hipWant) .. ")")
run(st, 0, 60, 74)
check(math.abs(st.hipWant - Bd.HIP_MAX) < 0.5, "capped at HIP_MAX")
n = run(st, 0, 60, 120)
check(n.strafe and st.hipWant == 0, "past 75: the aimed strafes, hips straight")
run(st, 0, 0, 40)
check(st.hipWant == 0, "standing: hips straight")
run(st, 0, 15, 40)
check(st.hipWant > 0 and st.hipWant < 40, "slow: part of the way (" .. tostring(st.hipWant) .. ")")
-- alert posture walking at 50 deg: the alert walk, hips turned
st = { alertPosture = true }
n = run(st, 1, 45, 50)
check(n.alwalk and math.abs(st.hipWant - 50) < 0.5, "alert walk 50 off: hips 50 (" .. tostring(st.hipWant) .. ")")
-- aimed strafes: no hip turn
st = {}
run(st, 1, 60, 50)
check(st.hipWant == 0, "aimed 8-way strafes: hips straight")
-- calm wading: forward walk + hips within 75, gun-up 8-way wades past it
st = { wade = 1 }
n = run(st, 0, 45, 40)
check(n.kwalk and math.abs(st.hipWant - 40) < 0.5, "calm wade 40 off: forward wade, hips 40")
n = run(st, 0, 45, 110)
check(n.strafe and not n.kwalk and st.hipWant == 0, "calm wade 110 off: the gun-up 8-way wades (no sideways slide)")
n = run(st, 0, 10, 110)
check(n.kidle and not n.strafe, "calm wade barely moving: still the calm set")
-- vb_pose applies it to pelvis / Spine / Spine1 and resets it on full-body actions
check(src:find("SCRATCH_ANG.p, SCRATCH_ANG.y, SCRATCH_ANG.r = h, 0, 0", 1, true) and src:find("SCRATCH_ANG2.p, SCRATCH_ANG2.y, SCRATCH_ANG2.r = 0, 0, -h * 0.5", 1, true) and src:find("ManipulateBoneAngles(st.vbSp0, SCRATCH_ANG2)", 1, true),
	"pelvis pitch, spine roll back")
check(src:find("st.hipWant = 0", 1, true) ~= nil, "reset each frame before the action branches")
-- 0.38.9: an activity clip that lets go of the gun anywhere carries it all through (no code sling at its ends)
TIFG_JGUN_UNDRIVEN = { mp_walk = true }
TIFG_JGUN_HOLD = { smoke_in = { r = { 0, 0, 0.3, 1, 1 } }, held = { r = { 0, 0, 0 } } }
check(Bd.ClipCarriesGun({ from = "smoke_in" }) == true, "smoke clip (lets go mid-way): carries the gun from its first frame")
check(Bd.ClipCarriesGun({ from = "held" }) == false, "gun never let go: not carried (the code sling where it's a sling act)")
check(Bd.ClipCarriesGun({ from = "mp_walk" }) == false and Bd.ClipCarriesGun({ from = "unknown" }) == false, "undriven / unknown: no")
check(src:find("actClip ~= nil and Bd.ClipCarriesGun(actClip)", 1, true) ~= nil, "sling decided per clip, not per frame")
print(string.format("passed %d, failed %d", pass, fail))
