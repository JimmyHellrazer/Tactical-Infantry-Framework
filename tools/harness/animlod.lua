local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z)
	if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
local cvals = { tif_anim_lod = 1, tif_anim_lod_every = 4 }
function CreateClientConVar(n, d) return { GetBool = function() return (cvals[n] or tonumber(d)) ~= 0 end, GetInt = function() return cvals[n] or tonumber(d) end } end
local rt, fovP, scrW, scrH = 10, 90, 1920, 1080
function RealTime() return rt end
function LocalPlayer() return { GetFOV = function() return fovP end } end
function IsValid(x) return x ~= nil end
function ScrW() return scrW end
function ScrH() return scrH end
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[ev] = fn end }
local function ang(fx, fy, fz) return { Forward = function() return Vector(fx, fy, fz) end } end
local src = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
local a = src:find("Bd.LOD = Bd.LOD or {}", 1, true)
local b = src:find("\nend\n", src:find("function L.OnScreen", a, true), true)
check(a and b, "LOD block found")
Bd = {}
assert(loadstring("local Bd = Bd\nlocal cvLOD = CreateClientConVar('tif_anim_lod', '1')\nlocal cvLODEvery = CreateClientConVar('tif_anim_lod_every', '4')\n" .. src:sub(a, b + 4)))()
local L = Bd.LOD
local function at(x, y, z) return { WorldSpaceCenter = function() return Vector(x, y, z) end } end
L.Frame()
check(not L.live and L.OnScreen(at(-1000, 0, 0), {}), "no main view seen yet: everyone counts as on screen")
check(hooks.RenderScene ~= nil, "the main view comes from RenderScene")
hooks.RenderScene(Vector(0, 0, 0), ang(1, 0, 0), 90)
L.Frame()
check(L.live and L.on and L.every == 4, "live with a main view")
check(L.OnScreen(at(1000, 0, 0)), "straight ahead")
check(not L.OnScreen(at(-1000, 0, 0)), "behind: out of view")
check(not L.OnScreen(at(0, -1000, 0)) and not L.OnScreen(at(0, 1000, 0)), "90 deg to the side: out of view")
check(L.OnScreen(at(1000, 700, 0)), "35 deg off: in view")
check(L.OnScreen(at(1000, 1700, 0)), "near the 16:9 edge: in view (margin)")
check(L.OnScreen(at(-100, 0, 0)), "within 160: always full")
check(L.OnScreen(at(300, 0, -900)) and L.OnScreen(at(1000, 0, 500)), "below / above")
local st = {}
check(L.OnScreen(at(-1000, 0, 0), st), "just left the view: still full for a moment")
rt = rt + 0.2
check(L.OnScreen(at(-1000, 0, 0), st), "0.2 s out: still full")
rt = rt + 0.2
check(not L.OnScreen(at(-1000, 0, 0), st), "0.4 s out: cheap")
check(L.OnScreen(at(1000, 0, 0), st) and st.lodOutT == nil, "back in view: full at once, timer reset")
hooks.RenderScene(Vector(0, 0, 0), ang(1, 0, 0), 130)
L.Frame()
check(L.OnScreen(at(1000, 2200, 0)), "a wider view fov widens the cone")
rt = rt + 1
L.Frame()
check(not L.live and L.OnScreen(at(-1000, 0, 0), {}), "the main view went stale (RenderScene stopped): everyone full")
hooks.RenderScene(Vector(0, 0, 0), ang(1, 0, 0), 90)
cvals.tif_anim_lod = 0
L.Frame()
check(not L.on and not L.live, "tif_anim_lod 0 turns it off")
check(src:find("local off = st.vb and L.on and not L.OnScreen(ent, st) and not ent:GetNW2Bool(\"tif_light\", false)", 1, true) ~= nil, "MW19 bodies only, flashlight carriers full")
check(src:find("if st.lodN < L.every and not woke then", 1, true) ~= nil, "skips frames, never on the frame he wakes")
check(src:find("dt = dt + (st.lodDt or 0)", 1, true) ~= nil, "skipped time carried into the next compose")
check(src:find("if not st or st.offScreen or not IsValid(st.gun)", 1, true) ~= nil, "no stale muzzle for tracers")
check(src:find("if st.flashAt and not st.offScreen", 1, true) ~= nil, "no stale muzzle flash / light")
check(src:find('local LOD_PARTS = { "gun", "backGun", "launcherGun", "prop" }', 1, true) ~= nil, "the hand-placed models (gun, slung primary, launcher, prop) are known")
local _, nHide = src:gsub("\n%s*hide_placed%(st%)", "")
check(nHide == 2, "hidden on skipped frames and on the cheap compose (they'd hang where he left them): " .. nHide)
check(src:gsub("%s+", " "):find("if IsValid(st.gun) then st.gun:SetNoDraw(dormant or knocked) end", 1, true) ~= nil, "shown again (and placed) the frame he's back in view")
print(string.format("passed %d, failed %d", pass, fail))
