-- Offline (0.38.0): the MW guns stand alone (TIF weapon bases, no GTA definitions): load order like sh_init (sorted,
-- _tif_bases first), every gun registers with stats, hold kind and its own model; the RPG-7 fires TIF's rocket.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
table.Copy = table.Copy or function(t)
	local function cp(x) if type(x) ~= "table" then return x end local o = {} for k, v in pairs(x) do o[k] = cp(v) end return o end
	return cp(t)
end
TIFG = { Data = { U = 39.3701 }, Weapons = {} }
CHAN_WEAPON, CHAN_AUTO = 1, 0
local sounds = {}
sound = { Add = function(s) sounds[s.name] = s end }
function TIFG.RegisterWeaponDef(s) TIFG.Weapons[s.ClassName] = s end
local dir = ROOT .. "tif/gta/weapons/"
local files = {}
for f in io.popen('dir /b "' .. dir:gsub("/", "\\") .. '"'):lines() do files[#files + 1] = f end
table.sort(files)
check(files[1] == "_tif_bases.lua", "bases load first (" .. tostring(files[1]) .. ")")
local gtaLeft = 0
for _, f in ipairs(files) do
	if f:find("^weapon_gtg_") then gtaLeft = gtaLeft + 1 end
	assert(loadfile(dir .. f))()
end
check(gtaLeft == 0, "no GTA weapon definitions left")
local n = 0
for class, s in pairs(TIFG.Weapons) do
	n = n + 1
	local g = s.GTG
	check(class:find("^weapon_tifmw_"), class .. " is an MW gun")
	check(g and g.damage and g.rate and g.range and g.hold, class .. " has stats and a hold")
	check(s.WorldModel and s.WorldModel:find("^models/tif_guns/"), class .. " uses its own model")
	check(s.Primary and s.Primary.ClipSize and s.Primary.ClipSize > 0, class .. " has a magazine")
	check(not (s.WorldModel or ""):find("gta") and not (g.mag or ""):find("gta"), class .. " names no GTA asset")
end
check(n == 45, "45 MW guns registered (44 baked + the AT4) (" .. n .. ")")
local rpg = TIFG.Weapons.weapon_tifmw_rpg7
check(rpg and rpg.GTG.projectile and rpg.GTG.projectile.entity == "tif_rocket", "RPG-7 fires TIF's rocket")
check(rpg and not rpg.GTG.projectile.model:find("gta"), "rocket model isn't a GTA asset")
local kinds = {}
local KIND = { pistol = "pistol", pump = "shotgun", rpg = "rpg", mg = "lmg", smg = "smg" }
for _, s in pairs(TIFG.Weapons) do kinds[KIND[s.GTG.hold] or "rifle"] = true end
for _, k in ipairs({ "rifle", "pistol", "shotgun", "lmg", "smg", "rpg" }) do check(kinds[k], "a " .. k .. " among the guns") end
print(string.format("passed %d, failed %d", pass, fail))
