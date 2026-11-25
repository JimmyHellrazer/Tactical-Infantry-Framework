-- Offline: MW22 additions (TIF 0.20.0) against the real generated clip table: grenade dodges, CQB breach / slice
-- helpers (sv_clear.lua), cover lean spot and shuffle plan data.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
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
function V:Length() return math.sqrt(self:Dot(self)) end
function V:LengthSqr() return self:Dot(self) end
function V:DistToSqr(o) return (self - o):LengthSqr() end
function V:Normalize() local l = self:Length() if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function V:GetNormalized() local v = Vector(self.x, self.y, self.z) v:Normalize() return v end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)), p = 0, r = 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.AngleDifference = function(a, b) local d = (a - b) % 360 if d > 180 then d = d - 360 end return d end
math.Rand = function(a, b) return (a + b) / 2 end
function IsValid(x) return x ~= nil end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function CurTime() return 10 end
function CreateConVar() return { GetBool = function() return true end } end
FCVAR_ARCHIVE = 0
hook = { Add = function() end }
ents = { FindByClass = function() return {} end }

TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
check(clips.mwq_br_l_1st_open and clips.mwc_ls_arr_lean_8 and clips.mwe_jump_4 and clips.mwbr_laststand_help_in_4,
	"MW22 roles in the clip table")

local played = {}
TIF = { AWARE = { UNAWARE = 0 }, Anim = { STANCE_CROUCH = 1 }, Soldiers = {},
	GTG = { Clip = function(n) return clips[n] end },
	HitsMW = { Use = function() return true end },
	Move = { Stop = function() end },
	Action = { Play = function(npc, n, o) played[#played + 1] = n npc.tifAct = { name = n } return clips[n] and clips[n].dur end },
	AIDisabled = function() return false end, Say = function() end }
dofile(ROOT .. "tif/tactics/sv_react_mw22.lua")
local R = TIF.React22

local function soldier(pos, yaw)
	local s = { pos = pos, yaw = yaw or 0, tifHomeHost = "mw_male", tifHostId = "mw_male", tifFire = {}, nw = {} }
	function s:GetPos() return self.pos end
	function s:GetAngles() return Angle(0, self.yaw, 0) end
	function s:SetAngles(a) self.yaw = a.y end
	function s:GetForward() local r = math.rad(self.yaw) return Vector(math.cos(r), math.sin(r), 0) end
	function s:GetTIFStance() return 0 end
	return s
end

-- Grenade dodges: the chosen clip travels away from the grenade.
local function travel(name) local c = clips[name] return math.deg(math.atan2(c.move[2], c.move[1])) end
for _, g in ipairs({ { Vector(200, 0, 0), "in front" }, { Vector(0, 200, 0), "on the left" }, { Vector(0, -200, 0), "on the right" },
	{ Vector(-200, 0, 0), "behind" } }) do
	local s = soldier(Vector(), 0)
	played = {}
	check(R.Dodge(s, g[1], 10), "dodges a grenade " .. g[2])
	local away = math.deg(math.atan2(-g[1].y, -g[1].x))
	check(math.abs(math.AngleDifference(travel(played[1]), away)) < 70, "grenade " .. g[2] .. ": " .. played[1] .. " heads away")
end
do
	local s = soldier(Vector(), 0)
	played = {}
	check(R.Dodge(s, Vector(80, 0, 0), 10) and played[1] == "mwe_dive_8", "very close grenade: a dive")
	check(math.abs(math.AngleDifference(s.yaw, 180)) < 1, "turned away from it before the dive")
	check(s.tifReactChain and s.tifReactChain.name == "mwe_dive_up_8", "then gets up")
	check(not R.Dodge(s, Vector(80, 0, 0), 10), "one reaction at a time")
end

-- CQB helpers (sv_clear.lua), loaded from the file.
local src = io.open(ROOT .. "tif/building/sv_clear.lua"):read("*a")
local block = src:match("(local function cclip.-\nlocal function anyone_sees_enemy)")
assert(block, "cqb helper block")
block = block:gsub("\nlocal function anyone_sees_enemy$", "")
local env = setmetatable({ TIF = TIF, CQB = {}, CreateConVar = function() return { GetInt = function() return 1 end } end, BLD = { Closed = function() return true end } }, { __index = _G })
local fn = assert(load(block .. "\nreturn lr_variant, aim_travel, breach_plan, corner_look, door_flash", "cqb", "t", env))
local lr_variant, aim_travel, breach_plan, corner_look, door_flash = fn()
-- 0.35.2: the door flash clip that turns him least, aimed so its throw heads at the target.
do
	check(clips.mwdr_l_flash and clips.mwdr_r_flash, "door flash clips built")
	local m = soldier(Vector(), 0)
	m.tifHomeHost = "mw_male"
	-- target straight ahead: l's throw is ~forward (15 deg off), r's sideways (106)
	local n, y, hand, u = door_flash(m, 0)
	check(n == "mwdr_l_flash" and math.abs(y + 15) < 1 and u > 0.3 and u < 0.45, "door flash ahead: the left clip, turned " .. tostring(y))
	-- target to his right (-90): r's throw goes right, almost no turn
	n, y = door_flash(m, -90)
	check(n == "mwdr_r_flash" and math.abs(math.AngleDifference(y, 16)) < 1, "door flash to the right: the right clip (" .. tostring(n) .. ", " .. tostring(y) .. ")")
	-- release spot: the hand, rotated with the body, ends toward the throw
	local k = env.CQB.DOOR_FLASH.mwdr_r_flash
	local r = math.rad(16)
	local fx, fy = math.cos(r), math.sin(r)
	local rx, ry = fy, -fx
	local sx, sy = fx * k.hand.x - rx * k.hand.y, fy * k.hand.x - ry * k.hand.y
	check(math.abs(math.AngleDifference(math.deg(math.atan2(sy, sx)), -90)) < 25, "right clip: the hand is out toward the throw at release")
end
local m = { tifHomeHost = "mw_male" }
local n1 = lr_variant(m, "mwq_br_%s_1st_open", true)
local n2 = lr_variant(m, "mwq_br_%s_1st_open", false)
check(n1 ~= n2 and clips[n1].move[3] > 0 and clips[n2].move[3] < 0, "breach: left-side man turns left into the room (" .. n1 .. "), right-side man right (" .. n2 .. ")")
-- A door facing +x (inward = +x), team stacked outside on both sides.
local door = { center = Vector(0, 0, 0), stair = false }
local cq = { door = door, inward = Vector(1, 0, 0),
	slots = { { pos = Vector(-30, 50, 0), side = 1 }, { pos = Vector(-30, -50, 0), side = -1 } } }
local team = { { tifHomeHost = "mw_male" }, { tifHomeHost = "mw_male" } }
for _, method in ipairs({ "open", "kick" }) do
	local plan = breach_plan(cq, team, method)
	check(plan and plan[1] and plan[2], "breach plan (" .. method .. ") for both men")
	for i = 1, 2 do
		local p = plan[i]
		local c = clips[p.go]
		-- Where the clip's travel heads from his spot with that facing: into the room (+x).
		local r = math.rad(p.yaw)
		local tx = c.move[1] * math.cos(r) - c.move[2] * math.sin(r)
		check(tx > 10, method .. " man " .. i .. ": " .. p.go .. " carries him into the room (" .. string.format("%.0f", tx) .. ")")
		check(p.doorU > 0 and p.doorU < 1, method .. " man " .. i .. ": door moment inside the clip")
	end
	check(plan[1].wait ~= nil, method .. ": first man has a waiting pose")
end
-- 0.30.2: breach_plan is forward-declared before setup_door (it called a nil global: every closed door errored),
-- and the open-door entry has no slice clips any more (stack and cross).
check(src:find("\nlocal breach_plan, pick_method\n", 1, true) ~= nil and src:find("local breach_plan", 1, true) < src:find("local function setup_door", 1, true), "breach_plan declared before setup_door uses it")
-- 0.38.17 variety: grenade breach and the no-door stack.
for _, method in ipairs({ "grenade", "nodoor" }) do
	local plan = breach_plan(cq, team, method)
	check(plan and plan[1] and plan[2] and plan.method == method, "breach plan (" .. method .. ") for both men")
	for i = 1, 2 do
		local p = plan and plan[i]
		if p then
			local c = clips[p.go]
			local r = math.rad(p.yaw)
			local tx = c.move[1] * math.cos(r) - c.move[2] * math.sin(r)
			check(tx > 10, method .. " man " .. i .. ": " .. p.go .. " carries him into the room (" .. string.format("%.0f", tx) .. ")")
			check(p.wait ~= nil and p.wait.name:find(method == "grenade" and "_gren_idle" or "_nodoor_idle", 1, true), method .. " man " .. i .. ": waits in the " .. method .. " stack pose")
		end
	end
	if method == "grenade" and plan then
		check(plan[1].relU and plan[1].relU > plan[1].doorU, "grenade: the door cracks before the throw")
		check(plan[2].moveU and plan[2].moveU > 0.3, "grenade: second man's set-off point known")
	end
end
-- pick_method: weighted, locked doors kicked, grenade only for those allowed to flash, off -> by hand
do
	local variety, isLocked, flashMode = true, false, 1
	env.cvVariety = { GetBool = function() return variety end }
	env.locked = function() return isLocked end
	env.cvFlash = { GetInt = function() return flashMode end }
	env.player = { Iterator = function() return ipairs({ {} }) end }
	env.TIF.REL_ALLY = env.TIF.REL_ALLY or 1
	local rel0 = env.TIF.Relation
	env.TIF.Relation = function() return env.TIF.REL_ALLY end
	env.TIF.GrenadeMW = { Throw = function() end, HL2 = function() return false end }
	env.CQB.METHOD_WEIGHTS = { open = 4, kick = 3, grenade = 3 }
	local pm = env.pick_method
	local cqp = { team = { { tifHomeHost = "mw_male" } } }
	env.IsValid = function(x) return x ~= nil end
	local seen = {}
	for _ = 1, 400 do seen[pm(cqp, door)] = true end
	check(seen.open and seen.kick and seen.grenade, "pick_method: all three methods come up")
	-- (cvFlash is local to the block, fixed at 1 here: an HL2-grenade faction stands in for "not allowed to flash")
	env.TIF.GrenadeMW.HL2 = function() return true end
	seen = {}
	for _ = 1, 400 do seen[pm(cqp, door)] = true end
	check(seen.open and seen.kick and not seen.grenade, "pick_method: no grenade breach for a man who can't flash")
	isLocked = true
	check(pm(cqp, door) == "kick", "pick_method: a locked door is kicked")
	variety = false
	check(pm(cqp, door) == "open", "pick_method: tif_cqb_variety 0 -> by hand")
	env.TIF.Relation = rel0
end
check(src:find('breach_plan(cq, cq.team, "nodoor")', 1, true) ~= nil, "open doorways can get the no-door stack")
-- 0.38.19: sledgehammer breach. He faces the door, back from it so the swing lands on his side's handle edge.
do
	local blocked = false
	env.util = { TraceHull = function() return { StartSolid = blocked } end }
	env.MASK_NPCSOLID_BRUSHONLY = 1
	door.width = 48
	local plan = breach_plan(cq, team, "hammer")
	check(plan and plan.method == "hammer" and plan[1].go == "mwq_br_sledge", "hammer plan: the sledge clip for the first man")
	check(plan and plan[2] and plan[2].go:find("_kick_2nd_go", 1, true), "hammer plan: the second man goes in as after a kick")
	local p1 = plan and plan[1]
	check(p1 and math.abs(p1.yaw + 90) < 0.5, "hammer: side-on, the door on his left (" .. tostring(p1 and p1.yaw) .. ")")
	check(p1 and p1.doorU > 0.25 and p1.doorU < 0.4, "hammer: door gives on sledge_vs_door (" .. tostring(p1 and p1.doorU) .. ")")
	local H = env.CQB.HAMMER_HIT
	if p1 and p1.stand then
		-- his spot + the swing's reach (in his frame, turned by his yaw) = a point on the door, inside his own half
		local r = math.rad(p1.yaw)
		local hx = p1.stand.x + H[1] * math.cos(r) - H[2] * math.sin(r)
		local hy = p1.stand.y + H[1] * math.sin(r) + H[2] * math.cos(r)
		check(math.abs(hx) < 1 and hy > 0 and hy < door.width / 2, "hammer: the swing lands on the door, his side (" .. hx .. ", " .. hy .. ")")
		check(p1.stand.x < -30, "hammer: he waits back from the door")
	else
		check(false, "hammer: a standing spot")
	end
	blocked = true
	check(breach_plan(cq, team, "hammer") == nil, "hammer: no room to swing -> no plan (falls back to a kick)")
	blocked = false
	local c = clips.mwq_br_sledge
	check(c and c.frames == 91 and math.abs(c.move[3]) < 2, "sledge clip trimmed at f90, no turn")
	local data = io.open(ROOT .. "tif/npc/cl_props_data.lua"):read("*a")
	local nfr = select(2, data:gsub("\n\t\t{ [12],", ""))
	check(nfr == c.frames, "sledge prop: a pose for every clip frame (" .. nfr .. ")")
	check(io.open(ROOT .. "../models/tif_mw/props/sledgehammer.mdl", "rb") ~= nil, "sledgehammer model built")
end
-- 0.38.23: go clips aimed from where he stands, skipped into a wall; the team passes through itself; no flash after
-- a clip breach
check(src:find("yawFn = function(npc)", 1, true) and src:find("clip_path_clear(npc, cclip(npc, b.go), yaw, cq)", 1, true), "go clips: aimed from his spot, path checked")
check(src:find("for _, m in ipairs(team) do team_ghost(m, true) end", 1, true) and src:find("team_ghost(m, false)", 1, true), "entry team passes through itself, restored on release")
check(src:find("if not cq.wentIn then flash_in(sq, cq, team, now) end", 1, true) ~= nil, "no flash after a clip breach")
local brain = io.open(ROOT .. "tif/npc/sv_brain.lua"):read("*a")
check(brain:find("local yaw = item.yawFn and item.yawFn(npc) or item.yaw", 1, true) and brain:find("if item.check and not item.check(npc", 1, true), "brain: queue uses yawFn / check")
check(src:find('m:SetNW2Bool("tif_sledge", sledge)', 1, true) and src:find('m:SetNW2Bool("tif_sledge", false)', 1, true), "sledge shown stowed while he has a hammer breach, cleared on release")
check(src:find("grenade_breach(sq, cq, team[1], rel, now)", 1, true) ~= nil, "grenade breach throws on the first man's clip")
check(src:find("slice_queue", 1, true) == nil, "no wide slice clips in the open-door entry")
-- The door swings on the clip's own door note (export 1's notetracks carried onto export 2's clips).
local plan = breach_plan(cq, team, "open")
check(math.abs(plan[1].doorU - 0.35) > 0.001, "open breach: door moment from the clip's door_open note (" .. string.format("%.2f", plan[1].doorU) .. ")")
local look = corner_look(door, Vector(60, 150, 0))
check(look.y > 150 and look.x > 60, "on the way in he looks past his point into his corner")

-- 0.35.1: the stack waits for every man, then settles a second; low ready on the stack except the point man.
check(src:find("local enough = ready >= #team\n", 1, true) ~= nil and src:find("CQB.STACK_SETTLE", 1, true) ~= nil, "full stack + settle before going in")
check(src:find("lowReady = i ~= 1", 1, true) ~= nil, "stack low ready for all but the point man")
do
	local bsrc = io.open(ROOT .. "tif/npc/sv_brain.lua"):read("*a")
	local lb = bsrc:match("(local LR_QUIET.-\n)local function sidestep_point")
	assert(lb, "low_ready block")
	local benv = setmetatable({ A = { MODE_AIM = 1 }, TIF = { CoverBehave = { In = function() return false end } } }, { __index = _G })
	local low_ready = assert(load(lb .. "\nreturn low_ready", "lr", "t", benv))()
	local function man(pos, yaw)
		local s = soldier(pos, yaw)
		s.tifMode, s.tifStance = 1, 0
		function s:GetNW2Bool(k, d) local v = self.nw[k] if v == nil then return d end return v end
		function s:SetNW2Bool(k, v) self.nw[k] = v end
		return s
	end
	local function run(s, t0, t1) for t = t0, t1, 0.1 do low_ready(s, t, false) end return s.nw.tif_lowready == true end
	local a, b = man(Vector(0, 0, 0), 0), man(Vector(-40, 0, 0), 0)
	local sq = { members = { a, b } }
	a.tifSquad, b.tifSquad = sq, sq
	-- On the stack: number two down, point man up.
	a.tifCQB, b.tifCQB = { lowReady = false }, { lowReady = true }
	check(not run(a, 0, 2), "point man stays at the ready on the stack")
	check(run(b, 0, 2), "number two holds low ready on the stack")
	-- Moving in: up even with nothing seen for a long time; b has a up close in front of him (the point man).
	a.tifCQB, b.tifCQB = { label = "entry 1" }, { label = "entry 2" }
	check(not run(a, 10, 20), "moving in CQB: gun up though quiet")
	check(run(b, 10, 11), "a mate across his muzzle: low ready")
	a.pos = Vector(0, 120, 0)
	check(not run(b, 11.1, 13), "mate clear: gun back up")
	-- Outside CQB the quiet rule still lowers it.
	local c = man(Vector(500, 0, 0), 0)
	check(run(c, 0, 4), "out of CQB: quiet low ready as before")
end
print(string.format("passed %d, failed %d", pass, fail))
