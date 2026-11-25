-- (after trans.lua's header: box world, real clips) 0.38.7: civilian animation choices in entities/tif_civilian.lua.
function V:GetNormalized() local l = self:Length() return l > 0 and Vector(self.x / l, self.y / l, self.z / l) or Vector(0, 0, 0) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
V.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
MASK_NPCSOLID, MASK_NPCSOLID_BRUSHONLY, MASK_SHOT = 1, 1, 1
NOW = 100
function CurTime() return NOW end
SERVER, CLIENT = true, false
AddCSLuaFile = function() end
IsValid = function(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
local humans = {}
player = { GetHumans = function() return humans end }
hook = { Run = function() end }
-- hull trace: a line at mid height (enough for the box world)
util.TraceHull = function(t)
	return util.TraceLine({ start = t.start + Vector(0, 0, 20), endpos = t.endpos + Vector(0, 0, 20) })
end
-- root motion from the clip's curve (frame triplets x, y, yaw), linear
TIF.Action.RootAt = function(c, u)
	local cv = c.curve
	if not cv or #cv < 3 then return 0, 0, 0 end
	local n = #cv / 3
	local f = u * (n - 1)
	local i = math.floor(f)
	local k = f - i
	local a, b = i * 3, math.min(i + 1, n - 1) * 3
	return cv[a + 1] + (cv[b + 1] - cv[a + 1]) * k, cv[a + 2] + (cv[b + 2] - cv[a + 2]) * k, cv[a + 3] + (cv[b + 3] - cv[a + 3]) * k
end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
coroutine.yield = function() NOW = NOW + 0.05 end

ENT = {}
assert(loadfile(ROOT .. "entities/tif_civilian.lua"))()
local E = ENT

local function civ(pos, yaw, var)
	local c = setmetatable({ pos = pos, yaw = yaw or 0, var = var or 1, mw = true, state = "wander", fear = 0, played = {} }, { __index = E })
	function c:GetPos() return self.pos end
	function c:SetPos(p) self.pos = p end
	function c:GetAngles() return Angle(0, self.yaw, 0) end
	function c:SetAngles(a) self.yaw = a.y end
	function c:GetCollisionBounds() return Vector(-12, -12, 0), Vector(12, 12, 70) end
	function c:LookupSequence(s) return 1 end
	function c:GetSequence() return 0 end
	function c:ResetSequence() end
	function c:SetCycle(x) self.cyc = x end
	function c:GetCycle() return self.cyc or 0 end
	function c:SetPlaybackRate() end
	function c:SetNW2String() end
	c.loco = { SetDesiredSpeed = function() end, GetVelocity = function() return Vector(0, 0, 0) end }
	local play = c.Play
	function c:Play(role, rate) self.played[#self.played + 1] = role return play(self, role, rate) end
	return c
end
local function lastp(c) return c.played[#c.played] end

-- numpad
local np = E.Numpad
check(np(0) == "8" and np(180) == "2" and np(-179) == "2", "numpad: ahead 8, behind 2")
check(np(90) == "4" and np(-90) == "6" and np(45) == "7" and np(-45) == "9" and np(135) == "1" and np(-135) == "3", "numpad: + is left")

-- the new clips exist and are full-body (moves where expected)
for _, r in ipairs({ "civ_react_sm1_2", "civ_react_lg1_8", "civ_startle_2l", "civ_panic_idle_1", "civ_scared_idle_1",
	"civ_tocower_1", "civ_cowering_1", "civ_uncower_1", "civ_prone_1", "civ_stand_1", "civ_walk_1", "civ_wwalk_1",
	"civ_chat_1", "civ_pevade_4", "civ_duck_run" }) do
	check(clips[r] ~= nil, "clip " .. r)
end
local r2, r4 = clips.civ_react_sm1_2, clips.civ_react_sm1_4
check(r2 and r2.move[1] > 60, "react with the threat behind: runs forward (" .. tostring(r2 and r2.move[1]) .. ")")
check(r4 and r4.move[2] < -60 and math.abs(r4.move[3] + 90) < 20, "threat on the left: runs off to the right, turned right ("
	.. tostring(r4 and r4.move[2]) .. ", " .. tostring(r4 and r4.move[3]) .. ")")
local s4 = clips.civ_startle_4
check(s4 and math.abs(s4.move[3] - 90) < 20, "startle at 4: turns left to face it (" .. tostring(s4 and s4.move[3]) .. ")")
check(clips.civ_walk_1.loop and clips.civ_walk_1.speed > 20, "MW22 walk loops with speed " .. tostring(clips.civ_walk_1.speed))
check(clips.civ_duck_run.loop and clips.civ_duck_run.speed > 80, "duck run speed " .. tostring(clips.civ_duck_run.speed))

-- open ground
boxes = {}
box(Vector(-5000, -5000, -10), Vector(5000, 5000, 0))

-- React: close, scared: the run-off reaction for the threat's direction
local a = civ(Vector(0, 0, 0), 0, 1)
a.fear, a.reactAt = 0.6, Vector(-300, 0, 0) -- behind
a:React()
check(a.played[1] == "civ_react_md2_2", "close threat behind, scared: md reaction 2: " .. tostring(a.played[1]))
check(a.pos.x > 60, "root motion carried it forward: " .. a.pos.x)
check(a.reactAt == nil and not a.civOneShot, "reaction done")
local b = civ(Vector(0, 0, 0), 0, 2)
b.fear, b.reactAt = 0.3, Vector(3000, 0, 0) -- far ahead, not much of a scare
b:React()
check(b.played[1] == "civ_startle_8", "far off, mild: startle toward it: " .. tostring(b.played[1]))
local c = civ(Vector(0, 0, 0), 0, 2)
c.fear, c.reactAt = 0.3, Vector(-3000, 10, 0)
c:React()
check(c.played[1] == "civ_startle_2l", "far behind (left side): about-face left: " .. tostring(c.played[1]))
local d = civ(Vector(0, 0, 0), 0, 1)
d.fear, d.reactAt = 1, Vector(0, 300, 0) -- left, terrified
d:React()
check(d.played[1] == "civ_react_lg1_4", "terrified, threat left: big reaction 4: " .. tostring(d.played[1]))
check(d.pos.y < -60 and math.abs(math.AngleDifference(d.yaw, -90)) < 25, "ran off to the right, facing away: " .. d.pos.y .. " yaw " .. d.yaw)
-- a wall where it would run: a shorter reaction, else a startle
box(Vector(-20, -400, 0), Vector(20, -150, 200)) -- a wall to the right, past the small reaction? (sm ~ -196)
local e = civ(Vector(0, 0, 0), 0, 1)
e.fear, e.reactAt = 1, Vector(0, 300, 0)
e:React()
check(e.played[1] ~= "civ_react_lg1_4" and e.played[1] ~= "civ_react_md2_4", "no room for the long run: not the big one: " .. tostring(e.played[1]))
check(e.pos.y > -150, "never through the wall: " .. e.pos.y)
boxes = {}
box(Vector(-5000, -5000, -10), Vector(5000, 5000, 0))
-- root motion stops at a wall met on the way (OneShot)
box(Vector(80, -50, 0), Vector(100, 50, 200))
local f = civ(Vector(0, 0, 0), 0, 1)
f.fear, f.reactAt = 0.6, Vector(-300, 0, 0)
f:React()
check(f.pos.x < 80, "stops short at a wall in the way (" .. f.pos.x .. ")")
boxes = {}
box(Vector(-5000, -5000, -10), Vector(5000, 5000, 0))

-- Idles by fear; walks
local g = civ(Vector(0, 0, 0), 0, 3)
g:Idle()
check(lastp(g):find("^civ_stand_") or lastp(g) == "civ_idle_1", "calm: a standing idle: " .. lastp(g))
g.fear = 0.3
g:Idle()
check(lastp(g):find("^civ_scared_idle_"), "scared: scared idle: " .. lastp(g))
g.fear = 0.7
g:Idle()
check(lastp(g):find("^civ_panic_idle_"), "panicked: panic idle: " .. lastp(g))
g.fear = 0
check(g:MoveClip("walk"):find("^civ_walk"), "calm walk: " .. g:MoveClip("walk"))
g.fear = 0.15
check(g:MoveClip("walk"):find("^civ_wwalk_"), "after a scare: wary walk: " .. g:MoveClip("walk"))
local walks = {}
for v = 1, 10 do local w = civ(Vector(0, 0, 0), 0, v) walks[w:MoveClip("walk")] = true end
local nw = 0
for _ in pairs(walks) do nw = nw + 1 end
check(nw >= 4, "civilians walk differently (" .. nw .. " walks over 10)")
local h = civ(Vector(0, 0, 0), 0, 3)
h.fear, h.dangerPos = 0.9, Vector(400, 0, 0)
check(h:FleeKind("panic_run") == "duck" and h:MoveClip("duck") == "civ_duck_run", "gunfire very close: doubled over (var 3)")
h.var = 4
check(h:FleeKind("panic_run") == "panic_run", "others just run")
h.var, h.dangerPos = 3, Vector(2000, 0, 0)
check(h:FleeKind("panic_run") == "panic_run", "far: run upright")

-- Hiding in the open: the MW22 cower chain (down, cower, up when leaving)
local k
for v = 1, 20 do
	local t = civ(Vector(0, 0, 0), 0, v)
	if t:ScaredPose():find("^chain_") then k = t break end
end
check(k ~= nil, "some civilians use the MW22 cower")
if k then
	k.state, k.hideSpot = "hide", { pos = Vector(0, 0, 0), yaw = 0 }
	k.dangerPos, k.scaredAt = Vector(-500, 0, 0), NOW
	local Civ = { Helper = function() return nil end, List = function() return {} end }
	k:Hide(Civ)
	local s = table.concat(k.played, ",")
	check(s:find("civ_tocower_") and s:find("civ_cowering_"), "gets down into the cower, then cowers: " .. s)
	check(k.civChain ~= nil, "remembers it's cowering")
	k.played = {}
	-- shooting comes close while it cowers: the state turns to flee mid-hide
	local ch = k.civChain
	local y0 = coroutine.yield
	local tFlee = NOW + 1
	coroutine.yield = function() y0() if NOW > tFlee and k.state == "hide" then k.played = {} k.state = "flee" end end
	k:Hide(Civ)
	coroutine.yield = y0
	check(k.played[1] == "civ_uncower_" .. ch and k.civChain == nil, "leaving: back up out of the cower: " .. tostring(k.played[1]))
end
local p = civ(Vector(0, 0, 0), 0, 2)
p.fear = 0.95
check(p:ScaredPose():find("^civ_prone_"), "badly scared (even var): flat on the ground: " .. p:ScaredPose())

-- Dodge: a player walking into a standing civilian
local q = civ(Vector(0, 0, 0), 0, 1)
q.civRole = "civ_idle_1"
local ply = { Alive = function() return true end, GetPos = function() return Vector(-60, 10, 0) end, GetVelocity = function() return Vector(150, 0, 0) end }
humans = { ply }
TIF.Soldiers = {}
check(q:Dodge() == true, "someone walking into it: steps aside")
check(q.played[1] == "civ_evade_6", "they pass on its left side: steps right (6): " .. tostring(q.played[1]))
check(q.pos.y < -10, "moved right: " .. q.pos.y)
check(lastp(q) == "civ_idle_1", "back to its idle after")
q.played = {}
check(q:Dodge() == false, "not twice in a row")
NOW = NOW + 5
ply.GetVelocity = function() return Vector(-150, 0, 0) end
q.nextDodgeCheck = 0
check(q:Dodge() == false, "walking away from it: no")
humans = {}
print(string.format("passed %d, failed %d", pass, fail))

