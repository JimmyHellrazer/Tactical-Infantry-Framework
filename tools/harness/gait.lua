-- Offline: combat gaits (0.17.0). TIF.Move.CombatGait, the brain's gait picker, and no aimed jog left in fights.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:DistToSqr(o) return (self - o):LengthSqr() end

local function read(p) return io.open(ROOT .. p):read("*a") end

-- CombatGait (sv_move.lua)
local mv = read("tif/npc/sv_move.lua")
local block = mv:match("(M%.SPRINT_DIST = %d+.-function M%.CombatGait%(.-\nend)")
assert(block, "CombatGait not found")
local M = {}
assert(load("local M, SAME_GOAL = ...\n" .. block))(M, 48)
local function npc(pos) return { pos = pos, tifMove = {}, GetPos = function(s) return s.pos end } end
local a = npc(Vector(0, 0, 0))
check(M.CombatGait(a, Vector(1000, 0, 0)) == "sprint", "long move: sprint")
check(M.CombatGait(a, Vector(150, 0, 0)) == "tactical", "short move: aimed walk")
check(M.CombatGait(a, Vector(150, 0, 900)) == "tactical", "height doesn't count")
-- committed: a sprint to the same goal stays a sprint when close
a.tifMove.goal, a.tifMove.speed = Vector(1000, 0, 0), "sprint"
a.pos = Vector(900, 0, 0)
check(M.CombatGait(a, Vector(1010, 0, 0)) == "sprint", "same goal: keeps sprinting when close")
check(M.CombatGait(a, Vector(1200, 300, 0)) == "sprint", "new far goal: sprint")
a.tifMove.goal, a.tifMove.speed = Vector(950, 0, 0), "run"
check(M.CombatGait(a, Vector(950, 0, 0)) == "tactical", "an old jog isn't kept: re-picked")

-- Brain gait picker (sv_brain.lua)
local br = read("tif/npc/sv_brain.lua")
local g = br:match("(local function gait%(npc, kind, dist, now%).-\nend)")
assert(g, "gait not found")
local Move = { SPRINT_DIST = M.SPRINT_DIST, Moving = function() return false end }
math.Rand = function(x, y) return (x + y) / 2 end
local gait = assert(load("local Move = ...\n" .. g .. "\nreturn gait"))(Move)
local s = { tifArch = { prefRange = { 300, 1200 }, aggression = 0.9 } }
local seen = {}
for i = 1, 200 do
	s.tifGait = nil
	for _, case in ipairs({ { "advance", 3000 }, { "advance", 1200 }, { "move", 900 }, { "move", 100 }, { "shift", 200 } }) do
		s.tifGait = nil
		local sp = gait(s, case[1], case[2], i)
		seen[sp] = true
		if case[1] == "advance" and case[2] == 3000 then check(sp == "sprint", "far advance: sprint") end
		if case[1] == "advance" and case[2] == 1200 then check(sp == "tactical", "advance inside range: aimed walk") end
		if case[1] == "move" and case[2] == 900 then check(sp == "sprint", "long maneuver: sprint") end
		if case[1] == "move" and case[2] == 100 then check(sp == "tactical", "short maneuver: aimed walk") end
		if case[1] == "shift" then check(sp == "tactical", "shift: aimed walk") end
	end
end
check(not seen.aimrun and not seen.run, "never an aimed jog or a jog in a fight")

-- No aimed jog requested anywhere in fights; covering burst walks.
for _, f in ipairs({ "tif/npc/sv_brain.lua", "tif/tactics/sv_cover_mw.lua", "tif/tactics/sv_cover_behave.lua", "tif/building/sv_clear.lua" }) do
	check(not read(f):find('"aimrun"', 1, true), f .. ": no aimrun")
end
-- (0.35.0: run and gun with the MW clips during a covering burst, else the aimed walk; only while CoverFiring)
check(mv:find('TIF.Weapon.CoverFiring(npc, now) then', 1, true) ~= nil and mv:find('if rg == "" then sp = "tactical" end', 1, true) ~= nil, "covering burst: run and gun, else the aimed walk")
check(br:find('mv.speed == "sprint" and not coverFire', 1, true) ~= nil, "sprint never shoots")
print(string.format("passed %d, failed %d", pass, fail))
