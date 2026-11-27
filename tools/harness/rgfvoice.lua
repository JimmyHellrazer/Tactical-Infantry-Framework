local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local SOUND = ROOT:gsub("lua/$", "sound/")
file = { Find = function(pattern)
	local dir, ext = pattern:match("^sound/(.-)/%*%.(%w+)$")
	local out = {}
	local p = io.popen('dir /b "' .. (SOUND .. dir):gsub("/", "\\") .. '\\*.' .. ext .. '" 2>nul')
	for line in p:lines() do out[#out + 1] = line end
	p:close()
	return out, {}
end }
CreateConVar = function() return { GetBool = function() return true end, GetFloat = function() return 1 end } end
GetConVar = function() return nil end
CreateClientConVar = CreateConVar
SERVER, CLIENT = true, false
util = { AddNetworkString = function() end }
hook = { Add = function() end }
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function() end }
net = {}
TIF = { Factions = {} }
local ok, err = pcall(dofile, ROOT .. "tif/sh_voices.lua")
check(ok, "sh_voices loads: " .. tostring(err))
local V = TIF.Voice
for i = 1, 4 do
	local id = "tif_rgf" .. i
	check(V.PACKS[id] and V.PACKS[id].folder == "vo/" .. id, id .. " is registered")
	local set = V.Build(id)
	for _, ev in ipairs({ "contact", "reloading", "grenade_out", "grenade_incoming", "man_down", "pain", "death", "moving", "advance", "attack" }) do
		check(set and set.events[ev] and #set.events[ev] > 0, id .. " has " .. ev .. " lines")
	end
	local ogg = true
	for _, list in pairs(set.events) do for _, f in ipairs(list) do if not f:find("%.ogg$") then ogg = false end end end
	check(ogg, id .. " is all ogg")
end
check(#V.Build("tif_rgf1").events.kill == 6 and V.Build("tif_rgf4").events.kill == nil, "kill lines where the voice has them (rus4 has none)")
local content = io.open(ROOT .. "tif/config/sh_content.lua"):read("*a")
check(content:find('voices = { "tif_rgf1", "tif_rgf2", "tif_rgf3", "tif_rgf4", "mercenary" }', 1, true) ~= nil, "Russians use the four Spetsnaz voices plus mercenary")
print(string.format("passed %d, failed %d", pass, fail))
