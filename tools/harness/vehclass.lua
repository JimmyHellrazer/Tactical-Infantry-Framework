-- Offline (0.37.0): GTA car classes resolve to an installed MW car; MW / other classes pass through.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local stored = { tif_mw_ram1500 = {}, tif_mw_hilux = {}, gtav_insurgent = {} }
local src = io.open(ROOT .. "tif/vehicle/sv_mounted.lua"):read("*a")
local block = src:match("(MT%.CAR_FALLBACK = .-\nend\n%s*function MT%.VehicleClass.-\nend\n)")
check(block ~= nil, "fallback block")
local MT = {}
local env = setmetatable({ MT = MT, isstring = function(x) return type(x) == "string" end, scripted_ents = { GetStored = function(c) return stored[c] end } }, { __index = _G })
assert(load(block, "vc", "t", env))()
check(MT.DefaultCar() == "tif_mw_ram1500", "default: first installed MW car (" .. tostring(MT.DefaultCar()) .. ")")
check(MT.VehicleClass("tif_gta_glide_cars_baller2") == "tif_mw_ram1500", "old TIF GTA car -> MW car")
check(MT.VehicleClass("gtg_grandtheftgmod_rebel2") == "tif_mw_ram1500", "old GTG car -> MW car")
check(MT.VehicleClass("tif_mw_hilux") == "tif_mw_hilux", "an installed MW car stays")
check(MT.VehicleClass("gtav_insurgent") == "gtav_insurgent", "Glide's own cars stay")
check(MT.VehicleClass(nil) == "tif_mw_ram1500", "nothing named: the default car")
check(MT.VehicleClass("some_other_mod_car") == "some_other_mod_car", "unknown non-GTA class passes through (spawn reports it)")
stored = {}
check(MT.DefaultCar() == nil and MT.VehicleClass("tif_gta_glide_cars_baller2") == "tif_gta_glide_cars_baller2", "no MW cars installed: class kept, spawn fails cleanly")
print(string.format("passed %d, failed %d", pass, fail))
