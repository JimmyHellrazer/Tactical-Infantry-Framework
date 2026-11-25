-- Offline run of DTW's CA.Furnish (sv_campaign.lua) on a flat floor.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local DROOT = "K:/SteamLibrary/steamapps/common/GarrysMod/garrysmod/addons/dtw_campaign/lua/dtw/"

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function V:Distance(o) return math.sqrt((self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2) end
function V:DistToSqr(o) return self:Distance(o) ^ 2 end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Normalize() end
function V:Angle() return { y = math.deg(math.atan2(self.y, self.x)) } end
local A = {}
A.__index = A
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, A) end
function A:Forward() local r = math.rad(self.y) return Vector(math.cos(r), math.sin(r), 0) end
math.random = function(a, b) if a and b then return a end if a then return 1 end return 0.5 end
function IsValid(x) return x ~= nil end
hook = { Add = function() end, Run = function() end }
timer = { Create = function() end }
player = { Iterator = function() return function() end end }
bit = { bor = function(a, b) return a + b end }
MASK_SOLID, MASK_SOLID_BRUSHONLY, CONTENTS_WATER = 1, 2, 4
local blocked = {}
local mwOn = true
function GetConVar(n) if n == "tif_mw_anims" then return { GetBool = function() return mwOn end } end end
util = {
	IsValidModel = function(m) return true end,
	AddNetworkString = function() end,
	TraceLine = function(t) return { Hit = true, HitPos = Vector(t.start.x, t.start.y, 0) } end,
	TraceHull = function(t)
		for _, b in ipairs(blocked) do if b:Distance(t.start) < 30 then return { Hit = true } end end
		return { Hit = false }
	end,
}
local made = {}
ents = { Create = function(cls)
	local e = { cls = cls }
	function e:SetModel(m) self.model = m end
	function e:SetAngles(a) self.ang = a end
	function e:SetPos(p) self.pos = p end
	function e:GetPos() return self.pos end
	function e:Spawn() end
	function e:GetPhysicsObject() return { EnableMotion = function() end } end
	function e:OBBMins() return Vector(0, 0, -18) end
	function e:Remove() self.removed = true end
	made[#made + 1] = e
	return e
end }
local covered = 0
DTW = {
	AI = { MarkCover = function() covered = covered + 1 end },
	Garrison = { Seen = function() return false end },
	Reinforce = {},
	Roads = { HasRoads = function() return false end },
	Debug = function() end,
}
local fn = assert(loadfile(DROOT .. "config/sh_config.lua"))
DTW.Config = nil
local okc = pcall(fn)
if not DTW.Config then DTW.Config = { Campaign = {} } end
local C = DTW.Config
assert(loadfile(DROOT .. "sv_campaign.lua"))()
local CA = DTW.Campaign
check(C.Campaign.Furnish ~= nil, "config has Furnish (config load ok: " .. tostring(okc) .. ")")

local L = { posts = {}, reserve = { Vector(0, 0, 0), Vector(300, 0, 0), Vector(600, 0, 0) } }
local s = { id = "hq1", name = "HQ", type = "hq", state = {} }
CA.Furnish(s, "enemy", L)
local chairs, tables = 0, 0
for _, e in ipairs(made) do
	if e.model:find("chair") then chairs = chairs + 1 elseif e.model:find("table") then tables = tables + 1 end
end
check(chairs == 2 and tables == 1, "HQ: 2 chairs, 1 table: " .. chairs .. " / " .. tables)
check(covered == 0, "furniture isn't marked as cover")
check(#(CA.Furn.hq1 or {}) == 3 and CA.Forts.hq1 == nil, "kept apart from the walls")
local c1 = made[1]
check(math.abs(Vector(c1.pos.x, c1.pos.y, 0):Distance(L.reserve[1]) - 32) < 1 and math.abs(c1.pos.z - 18) < 0.1, "chair 32 off the reserve spot, on the floor")
local n0 = #made
CA.Furnish(s, "enemy", L)
check(#made == n0, "not furnished twice")
CA.Unfortify("hq1")
check(c1.removed and CA.Furn.hq1 == nil, "removed with the garrison")

made = {}
CA.Furnish({ id = "t1", name = "Town", type = "town", state = {} }, "enemy", L)
check(#made == 0, "no furniture in towns")
CA.Furnish({ id = "o1", name = "Outpost", type = "outpost", state = {} }, "enemy", L)
local tb = 0
for _, e in ipairs(made) do if e.model:find("table") then tb = tb + 1 end end
check(#made == 2 and tb == 0, "outpost: chairs only: " .. #made)
made = {}
mwOn = false
CA.Furnish({ id = "m1", name = "Mil", type = "military", state = {} }, "enemy", L)
check(#made == 0, "nothing without TIF's MW19 animations")
mwOn = true
blocked = { Vector(32, 0, 14), Vector(332, 0, 14), Vector(632, 0, 14) }
CA.Furnish({ id = "m2", name = "Mil", type = "military", state = {} }, "enemy", L)
check(#made == 0, "no chair where there's no room")
print(string.format("passed %d, failed %d", pass, fail))


