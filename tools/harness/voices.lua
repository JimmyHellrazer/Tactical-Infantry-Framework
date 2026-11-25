-- 2026-11-25: the default factions' voice packs (mercenary, bf3marine) ship in the base: every event of theirs finds
-- lines in the base's own sound folder (nothing from other addons).
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local SND = ROOT:gsub("lua/$", "")
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
local listing = {}
local function ls(dir)
	if listing[dir] then return listing[dir] end
	local out = {}
	local p = io.popen('dir /b "' .. (SND .. dir):gsub("/", "\\") .. '" 2>nul')
	for l in p:lines() do out[#out + 1] = l end
	p:close()
	listing[dir] = out
	return out
end
file = { Find = function(pat, where)
	local dir, ext = pat:match("^(.*)/%*%.(%w+)$")
	local out = {}
	for _, f in ipairs(ls(dir)) do if f:match("%." .. ext .. "$") then out[#out + 1] = f end end
	return out
end }
local dummy
dummy = setmetatable({}, { __index = function() return dummy end, __call = function() return dummy end })
function CreateConVar() return { GetBool = function() return true end, GetFloat = function() return 1 end, GetInt = function() return 1 end, GetString = function() return "" end } end
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end, Create = function() end }
util = setmetatable({}, { __index = function() return dummy end })
net = setmetatable({}, { __index = function() return dummy end })
TIF = { Log = function() end, Warn = function() end }
assert(loadfile(ROOT .. "tif/sh_voices.lua"))()
local V = TIF.Voice
check(V and V.PACKS, "voice table loaded")
for _, id in ipairs({ "mercenary", "bf3marine", "specops", "tif_arab_rebel", "tif_arab_operative" }) do
	local pack = V.PACKS[id]
	check(pack ~= nil, id .. ": defined")
	if pack then
		local set = V.Build(id)
		local missing, n = {}, 0
		-- (the pack's own gaps: tif_arab_operative has no "cover me" lines anywhere; TIF skips the call)
		local KNOWN = { tif_arab_operative = { cover_me = true } }
		for ev in pairs(pack.events) do
			n = n + 1
			if not (set.events[ev] and #set.events[ev] > 0) and not (KNOWN[id] and KNOWN[id][ev]) then missing[#missing + 1] = ev end
		end
		table.sort(missing)
		check(#missing == 0, id .. ": all " .. n .. " events have lines in the base (missing: " .. table.concat(missing, ", ") .. ")")
	end
end
print(string.format("passed %d, failed %d", pass, fail))
