table.Copy = table.Copy or function(t)
	local function cp(x) if type(x) ~= "table" then return x end local o = {} for k, v in pairs(x) do o[k] = cp(v) end return o end
	return cp(t)
end
TIFG = { Data = { U = 39.3701 }, Weapons = {} }
function TIFG.RegisterWeaponDef(s) TIFG.Weapons[s.ClassName] = s end
local dir = ROOT .. "tif/gta/weapons/"
local files = {}
for f in io.popen('dir /b "' .. dir:gsub("/", "\\") .. '"'):lines() do files[#files + 1] = f end
table.sort(files)
local baseOf = {}
for _, f in ipairs(files) do
	local src = io.open(dir .. f):read("*a")
	local b = src:match('WeaponBases%["(%a+)"%]')
	assert(loadfile(dir .. f))()
	local cls = f:gsub("%.lua$", "")
	baseOf[cls] = b
end
local rows = {}
for class, s in pairs(TIFG.Weapons) do
	local g = s.GTG
	rows[#rows + 1] = { class:gsub("^weapon_tifmw_", ""), baseOf[class] or "?", g.rate, g.auto and "auto" or "semi", s.Primary.ClipSize,
		g.damage, g.pellets or 1, g.fire_rounds or 0 }
end
table.sort(rows, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
for _, r in ipairs(rows) do
	print(string.format("ROW|%s|%s|%.3f|%d|%s|%d|%s|%d|%d", r[1], r[2], r[3], math.floor(60 / r[3] + 0.5), r[4], r[5], tostring(r[6]), r[7], r[8]))
end
