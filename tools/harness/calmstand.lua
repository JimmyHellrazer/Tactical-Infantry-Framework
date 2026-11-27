local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local src = io.open(ROOT .. "tif/npc/sv_brain.lua"):read("*a")
local block = src:match("(B%.CALM_STAND_AFTER = .-\nend\n)")
check(block ~= nil, "found B.NoCalmStand")
local A = { MODE_RELAXED = 0, MODE_AIM = 1, STANCE_STAND = 0, STANCE_CROUCH = 1 }
local AW = { UNAWARE = 0, SUSPICIOUS = 1, ALERTED = 2, ENGAGED = 3, SEARCHING = 4 }
local B = {}
local env = setmetatable({ B = B, A = A, AW = AW }, { __index = _G })
assert(load(block, "ncs", "t", env))()

local function mk(aware, speed)
	local v = { speed = speed or 0 }
	return { tifAware = aware, tifMode = 0, tifStance = 0, loco = { GetVelocity = function() return { Length2DSqr = function() return v.speed * v.speed end } end }, v = v }
end

local n = mk(AW.ENGAGED)
check(not B.NoCalmStand(n, 10) and n.tifMode == 0, "not on the first tick (run starts keep their relaxed start)")
check(not B.NoCalmStand(n, 10.2) and n.tifMode == 0, "nor under 0.3 s")
check(B.NoCalmStand(n, 10.35) and n.tifMode == 1, "an engaged soldier standing relaxed for 0.3 s gets his gun up")
n.tifMode = 0
check(B.NoCalmStand(n, 10.4) and n.tifMode == 1, "and keeps it while the brain keeps relaxing him")
n.tifMode = 0
n.v.speed = 200
check(not B.NoCalmStand(n, 10.5) and n.tifMode == 0 and n.tifCalmSince == nil, "running: relaxed gun-down run stays")

local b = mk(AW.ENGAGED)
b.tifMoraleState = "broken"
B.NoCalmStand(b, 1)
B.NoCalmStand(b, 1.4)
check(b.tifStance == 1 and b.tifMode == 0, "a broken soldier stuck standing cowers instead")

local bs = mk(AW.SEARCHING)
bs.tifMoraleState = "broken"
B.NoCalmStand(bs, 1) B.NoCalmStand(bs, 1.4)
check(bs.tifStance == 1, "a broken soldier who lost contact (searching) cowers too")
local a = mk(AW.ALERTED)
B.NoCalmStand(a, 1)
B.NoCalmStand(a, 1.4)
check(a.tifMode == 1, "alerted too")
for _, case in ipairs({
	{ AW.UNAWARE, "unaware" }, { AW.SEARCHING, "searching (has its own posture)" },
}) do
	local x = mk(case[1])
	B.NoCalmStand(x, 1) B.NoCalmStand(x, 1.4)
	check(x.tifMode == 0, case[2] .. " soldiers keep the calm idle")
end
for _, f in ipairs({ "tifAct", "tifVeh", "tifDowned", "tifSurrendered", "tifBoard", "tifLeaving" }) do
	local x = mk(AW.ENGAGED)
	x[f] = true
	B.NoCalmStand(x, 1) B.NoCalmStand(x, 1.4)
	check(x.tifMode == 0, "left alone with " .. f)
end
local c = mk(AW.ENGAGED)
c.tifStance = 1
B.NoCalmStand(c, 1) B.NoCalmStand(c, 1.4)
check(c.tifMode == 0, "crouched soldiers aren't in the calm idle")
check(src:find("B.NoCalmStand(npc, now)\n\n\tlow_ready(npc, now, coverFire)", 1, true) ~= nil, "runs after the mode rules, before low ready")
print(string.format("passed %d, failed %d", pass, fail))
