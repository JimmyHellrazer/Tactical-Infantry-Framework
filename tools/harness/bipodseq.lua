-- Offline (0.38.22): bipod order - prone set only after lying still AND aiming 2.9 s (hold 1.2 s through aim drops),
-- a wall set-up asked to pack up finishes first, client prone bipod reverses mid-clip instead of restarting.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function V:Length2DSqr() return self.x ^ 2 + self.y ^ 2 end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Rand = function(a, b) return (a + b) / 2 end
function IsValid(x) return x ~= nil end
local played = {}
TIF = { AWARE = { ENGAGED = 3 }, GTG = { WeaponKind = function() return "lmg" end, IsVB = function() return true end,
	Clip = function() return { dur = 2 } end },
	Action = { Play = function(npc, n) npc.tifAct = { name = n } played[#played + 1] = n return 2 end,
		Loop = function(npc, n) npc.tifAct = { name = n } played[#played + 1] = n return 1 end } }
assert(loadfile(ROOT .. "tif/tactics/sv_bipod_mw.lua"))()
local B = TIF.BipodMW
local mode = 0
local vel = Vector()
local npc = { tifWep = { class = "lmg" }, tifProne = { phase = 2 }, loco = { GetVelocity = function() return vel end },
	GetTIFMode = function() return mode end, GetPos = function() return Vector() end, GetAngles = function() return Angle() end,
	SetNW2Float = function() end, GetNW2Float = function() return 0 end }
-- lying still, not aiming: never set
for t = 0, 10, 0.5 do B.Set(npc, t) end
check(not B.Set(npc, 10), "lying still unaimed: not set (the client hasn't set it up)")
-- aiming from t=10: set at 12.9
mode = 1
check(not B.Set(npc, 10) and not B.Set(npc, 12.5), "aiming: not yet during the set-up")
check(B.Set(npc, 13.0), "aiming 2.9 s+: set")
-- the aim drops for a moment between bursts: still set
mode = 0
check(B.Set(npc, 13.8), "aim drops 0.8 s: still set (hold)")
mode = 1
check(B.Set(npc, 14.0), "back on aim: set")
-- the aim gone for longer: packed (client too), set-up again needed
mode = 0
B.Set(npc, 14.5) B.Set(npc, 16.0)
mode = 1
check(not B.Set(npc, 16.1), "aim gone 1.5 s+: needs setting up again")
check(B.Set(npc, 19.1), "...set again 2.9 s later")
-- crawling: reset
vel = Vector(40, 0, 0)
B.Set(npc, 19.2)
vel = Vector()
check(not B.Set(npc, 20), "crawled: set up again")

-- wall bipod: a move order mid set-up waits for it to finish, then packs up from the set pose
local w = { tifAct = { name = "mwb_stand_in" }, GetPos = function() return Vector() end, GetAngles = function() return Angle() end,
	SetNW2Float = function() end, GetNW2Float = function() return 0 end }
w.tifBipod = { set = { name = "stand" }, phase = "in", untilT = 5, since = 3 }
played = {}
check(B.Leave(w, 4) == true and #played == 0 and w.tifBipod.leave, "move order mid set-up: keeps setting up (no snap to the set pose)")
check(B.Leave(w, 5.1) == true and played[1] == "mwb_stand_out" and w.tifBipod.phase == "out", "set-up done: packs up from there")
check(B.Leave(w, 6.0) == true and B.Leave(w, 7.2) == false, "packing, then free")

-- weapon: a prone LMG holds fire until set (not up close)
local src = io.open(ROOT .. "tif/npc/sv_weapon.lua"):read("*a")
check(src:find("if not braced and not covering and npc.tifProne and npc.tifProne.phase == 2", 1, true) ~= nil, "prone LMG holds fire through the set-up")
-- client: reversible prone set-up / pack-up, hold through aim drops
local cl = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
check(cl:find("st.bipod, st.bipodT = \"out\", now - (1 - ui) * BP.out.dur / OUTK", 1, true) ~= nil, "client: set-up turned round packs up from the matching point")
check(cl:find("st.bipod, st.bipodT = \"in\", now - (1 - uo) * BP.into.dur", 1, true) ~= nil, "client: pack-up turned round sets up from the matching point")
check(cl:find("now - st.bipodWantT < Bd.BIPOD_HOLD", 1, true) ~= nil and cl:find("Bd.BIPOD_HOLD = 1.2", 1, true) ~= nil and B.PRONE_HOLD == 1.2, "client and server hold the same 1.2 s")
print(string.format("passed %d, failed %d", pass, fail))
