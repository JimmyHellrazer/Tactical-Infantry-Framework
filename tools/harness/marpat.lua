timer = timer or { Create = function() end, Simple = function() end, Remove = function() end }
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local ADDON = ROOT:gsub("lua/$", "")
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
local function exists(p) local f = io.open(p, "rb") if f then f:close() return true end return false end
TIF = { GTG = { DEFAULT_HOST = "mw_male", WeaponDef = function() return nil end } }
assert(loadfile(ROOT .. "tif/config/sh_content.lua"))()
local F, U = TIF.Factions.usmc_woodland, TIF.Factions.usmc
check(F ~= nil, "usmc_woodland registered")
check(F and F.name == "US Marines (MARPAT Woodland)", "name")
check(F and F.side == "ally" and F.relationsAs == "usmc", "relations as the Marines")
TIF.REL_ALLY, TIF.REL_NEUTRAL, TIF.REL_HOSTILE = 0, 1, 2
CreateConVar = CreateConVar or function() return { GetString = function() return "usmc" end, GetBool = function() return false end } end
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
hook = hook or { Add = function() end }
GetConVar = GetConVar or function() return { GetBool = function() return false end, GetString = function() return "" end } end
local okF, errF = pcall(function() assert(loadfile(ROOT .. "tif/core/sh_factions.lua"))() end)
if not okF then print(errF) end
check(okF and TIF.FactionRelation ~= nil, "faction relations loaded")
if TIF.FactionRelation then
	TIF.Factions.operators = { allies = { usmc = true, pmc = true } } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
	TIF.Factions.cartel = { neutral = { usmc = true } } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
	check(TIF.FactionRelation("usmc_woodland", "usmc") == TIF.REL_ALLY, "woodland and Marines are allies")
	check(TIF.FactionRelation("operators", "usmc_woodland") == TIF.REL_ALLY, "a faction allied with usmc is allied with woodland (the player as operators)")
	check(TIF.FactionRelation("usmc_woodland", "operators") == TIF.REL_ALLY, "both ways")
	check(TIF.FactionRelation("cartel", "usmc_woodland") == TIF.REL_NEUTRAL, "usmc's neutrals are woodland's neutrals")
	check(TIF.FactionRelation("usmc_woodland", "insurgents") == TIF.REL_HOSTILE, "usmc's enemies are woodland's enemies")
	check(TIF.FactionRelation("usmc_woodland", "pmc") == TIF.REL_ALLY, "the old pmc alias too")
end
check(F and #F.models == 3, "three outfits")
for _, m in ipairs(F and F.models or {}) do
	check(m:find("marpat_", 1, true) ~= nil, m .. " is a woodland model")
	for _, ext in ipairs({ ".mdl", ".vvd", ".dx90.vtx", ".phy" }) do
		check(exists(ADDON .. m:gsub("%.mdl$", ext)), m:gsub("%.mdl$", ext) .. " on disk")
	end
end
check(F and F.loadouts ~= U.loadouts and F.loadouts.rpg.launcher[1] == U.loadouts.rpg.launcher[1], "same loadouts as the Marines, own copy")
local W = ADDON .. "materials/models/tif/ins2/usmc_wood/"
for _, t in ipairs({ "t_usa_usmc_01_c", "t_usmc_helmet_01_c", "t_usmc_pants_01_c", "t_usmc_pants_02_c" }) do
	check(exists(W .. t .. ".vtf"), "woodland texture " .. t)
end
local vmt = io.open(W .. "t_usa_usmc_01.vmt"):read("*a")
check(vmt:find("usmc_wood/t_usa_usmc_01_c", 1, true) ~= nil, "uniform material uses the woodland diffuse")
check(vmt:find("models/tif/ins2/usmc/t_usa_usmc_01_n", 1, true) ~= nil, "and the base Marines' normal map")
print(string.format("passed %d, failed %d", pass, fail))
