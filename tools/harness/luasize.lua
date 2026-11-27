local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local LIMIT = 200000
local p = io.popen('dir /s /b "' .. ROOT:gsub("/", "\\") .. '*.lua"')
local n, big = 0, {}
for line in p:lines() do
	local f = io.open(line, "rb")
	if f then
		local size = f:seek("end")
		f:close()
		n = n + 1
		if size > LIMIT then big[#big + 1] = line .. " (" .. size .. ")" end
	end
end
p:close()
check(n > 100, "found the addon's Lua files (" .. n .. ")")
check(#big == 0, "every Lua file is small enough to reach multiplayer clients: " .. table.concat(big, ", "))
local clips = ROOT .. "tif/gta/clips/"
check(io.open(clips .. "mw_male.lua") == nil, "the old single clip file is gone")
local parts, total = 0, nil
for i = 1, 999 do
	local f = io.open(string.format("%smw_male_p%02d.lua", clips, i))
	if not f then break end
	local s = f:read("*a")
	f:close()
	parts = i
	local pi, pn = s:match("{ part = (%d+), parts = (%d+) }%) end%)%(%);")
	check(tonumber(pi) == i, "part file " .. i .. " registers as part " .. i)
	total = total or tonumber(pn)
	check(tonumber(pn) == total, "part file " .. i .. " agrees on the part count")
end
check(parts > 1 and parts == total, "all " .. tostring(total) .. " clip parts are there")
local parts_loaded = {}
TIFG = { RegisterClips = function(pack, c, m) local k = 0 for _ in pairs(c) do k = k + 1 end parts_loaded[m.part] = k end }
dofile(CLIPS)
local roles = 0
for i = 1, total do roles = roles + (parts_loaded[i] or 0) end
check(roles == 4399, "the parts hold all 4399 clips (" .. roles .. ")")
local init = io.open(ROOT .. "tif/gta/sh_init.lua"):read("*a")
check(init:find('{ dir = "clips" }', 1, true) ~= nil, "the clips folder loads every file in it")
print(string.format("passed %d, failed %d", pass, fail))
