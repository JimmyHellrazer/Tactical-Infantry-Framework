local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function IsValid(x) return x ~= nil and x ~= false end
local src = io.open(ROOT .. "tif/npc/sv_brain.lua"):read("*a")
local block = src:match("(B%.LINE_LEAD = .-\n)B%.CALM_STAND_AFTER")
check(block ~= nil, "found the careful-soldier helpers")
local B = {}
local TIFm = { Squad = { Members = function(sq) return sq.members end } }
assert(load(block, "careful", "t", setmetatable({ B = B, TIF = TIFm }, { __index = _G })))()

local function mate(x, y)
	local m = { p = Vector(x, y, 0) }
	function m:GetPos() return self.p end
	return m
end
local function soldier(opts)
	local sq = { members = {}, order = { kind = "free" } }
	local n = mate(0, 0)
	for k, v in pairs(opts or {}) do n[k] = v end
	n.tifSquad = sq
	sq.members[1] = n
	sq.members[2] = mate(0, 100)
	sq.members[3] = mate(0, -100)
	return n, sq
end

local a = soldier()
check(B.Careful(a), "a trained soldier in a squad fight is careful")
check(not B.Careful(soldier({ tifGuerrilla = true })), "guerrillas charge as before")
check(not B.Careful(soldier({ tifHunter = true })), "director / survival hunters charge as before")
check(not B.Careful(soldier({ tifPress = true })), "survival pressers charge as before")
local o, osq = soldier()
osq.order = { kind = "advance" }
check(not B.Careful(o), "a squad under an advance order keeps its pace")
local lone = mate(0, 0)
check(not B.Careful(lone), "a lone soldier is unchanged")
local pair, psq = soldier()
psq.members = { pair }
check(not B.Careful(pair), "a squad of one is unchanged")

check(B.UnderFire({ tifHurtAt = 10 }, 11.5), "hit in the last 3 s: under fire")
check(not B.UnderFire({ tifHurtAt = 10 }, 14), "not after 3 s")
check(B.UnderFire({ tifSupp = 0.3 }, 50) and not B.UnderFire({ tifSupp = 0.1 }, 50), "suppression above 0.2: under fire")

local threat = Vector(3000, 0, 0)
local g = B.LineCap(a, Vector(2000, 50, 8), threat, true)
check(math.abs(g.x - 500) < 1 and g.y == 50 and g.z == 8, "an advance 2000 u past the line stops 500 u ahead of the squad")
local g2 = B.LineCap(a, Vector(400, 0, 0), threat, true)
check(g2.x == 400, "within 500 u ahead of the line: unchanged")
local g3 = B.LineCap(a, Vector(2000, 0, 0), threat, false)
check(g3.x == 2000, "not careful: unchanged")
local solo, ssq = soldier()
ssq.members = { solo }
check(B.LineCap(solo, Vector(2000, 0, 0), threat, true).x == 2000, "nobody else in the squad: no line to keep")

local t = { tifSquad = { tactic = { kind = "bound" } } }
check(B.Bounding(t) and not B.Bounding({ tifSquad = { tactic = { kind = "engage" } } }) and not B.Bounding({}), "bounding is the squad's bound tactic")

check(src:find("local careful = B.Careful(npc)", 1, true) ~= nil, "engage works out careful once")
check(src:find('local covering = careful and npc.tifRole == "base" and B.Bounding(npc)', 1, true) and src:find('if em and em.kind == "advance" and not TIF.Morale.Shaken(npc) and not covering then', 1, true), "1: the covering half holds and fires during a bound")
check(src:find('if careful and B.UnderFire(npc, now) then\n\t\t\t\tsp = "tactical"', 1, true) ~= nil, "2: under fire the open advance is the aimed walk")
check(src:find("Move.SetGoal(npc, B.LineCap(npc, short_of(npc, c.pos, math.max(150, arch.prefRange[2] * 0.75)), c.pos, careful), sp, \"advance\")", 1, true) ~= nil, "3: the advance keeps to the squad line")
check(src:find("local keep = careful and arch.prefRange[1] or 150", 1, true) and src:find("B.LineCap(npc, short_of(npc, c.pos, keep), c.pos, careful)", 1, true), "4: reacquire stops at preferred range, and keeps to the line")
check(src:find('local sp = Move.CombatGait(npc, goal)', 1, true) ~= nil, "bound dashes (maneuver) still pick their own pace")
print(string.format("passed %d, failed %d", pass, fail))
