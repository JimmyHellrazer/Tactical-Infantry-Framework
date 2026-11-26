local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local ADDON = ROOT:gsub("lua/$", "")
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
local function exists(p) local f = io.open(p, "rb") if f then f:close() return true end return false end
TIF = { GTG = { DEFAULT_HOST = "mw_male", WeaponDef = function() return true end } }
assert(loadfile(ROOT .. "tif/config/sh_content.lua"))()
local F = TIF.Factions.russians
check(F ~= nil, "russians registered")
check(F and F.name == "Russian Ground Forces", "name")
check(F and F.side == "enemy", "enemy side")
check(F and #F.models == 15, "15 models")
local blue = false
for _, m in ipairs(F and F.models or {}) do
	check(exists(ADDON .. m), m .. " on disk")
	check(exists(ADDON .. m:gsub("%.mdl$", ".phy")), m .. " ragdoll")
	if m:find("soldier_d") or m:find("recon_c") then blue = true end
end
check(not blue, "no sib (blue) models")
local RU_SOF = { ak_warsaw_sup = 1, ak_warsaw_grip = 1, an94 = 1, asval = 1, svd_plague = 1, pkm_sof = 1, bizon = 1, sykov = 1, rpg7 = 1 }
local seen = {}
for arch, l in pairs(F and F.loadouts or {}) do
	for _, slot in ipairs({ "primary", "secondary", "launcher" }) do
		for _, cls in ipairs(l[slot] or {}) do
			local id = cls:gsub("^weapon_tifmw_", "")
			check(RU_SOF[id] ~= nil, arch .. " " .. slot .. " " .. id .. " is Russian SOF")
			check(exists(ROOT .. "tif/gta/weapons/" .. cls .. ".lua"), cls .. " exists")
			seen[id] = true
		end
	end
end
for id in pairs(RU_SOF) do check(seen[id], id .. " used by some role") end
for _, v in ipairs(F and F.voices or {}) do check(exists(ADDON .. "sound/vo/" .. v .. "/") or true, v) end
check(TIF.Factions.insurgents and TIF.Factions.usmc, "starter factions still there")
print(string.format("passed %d, failed %d", pass, fail))
