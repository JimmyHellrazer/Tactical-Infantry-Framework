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

local function cat_of(p) return (p:match("([^/]+)$"):gsub("%.%w+$", ""):gsub("_?%d+$", ""):lower()) end
for _, ev in ipairs({ "moving", "cover_me", "clear", "advance", "negative", "retreat" }) do
	local p = V.Pick("bf3marine", ev)
	check(p ~= nil, "bf3marine has a line (own or fallback) for " .. ev)
end
check(cat_of(V.Pick("mercenary", "no_ammo") or "") == "reloading", "no_ammo falls back to reloading lines")
check(V.Pick("mercenary", "attack") ~= nil, "melee attack falls back to swears")
check(V.Pick("bf3marine", "no_ammo") ~= nil and cat_of(V.Pick("bf3marine", "no_ammo")) ~= "reloading", "bf3marine uses its own no_ammo lines")

local now = 100
CurTime = function() return now end
IsValid = function(e) return e ~= nil end
CHAN_VOICE = 2
local played = {}
local function npc(fac, sq, idx)
	local n = { tifSquad = sq }
	n.GetTIFFaction = function() return fac end
	n.EntIndex = function() return idx end
	n.EmitSound = function(_, snd, lvl) played[#played + 1] = { n = n, snd = snd, lvl = lvl } end
	return n
end
TIF.Factions = { usmc = { voices = { "bf3marine" } }, insurgents = { voices = { "mercenary" } } }
local sqA, sqB = {}, {}
local a1, a2, b1 = npc("usmc", sqA, 1), npc("usmc", sqA, 2), npc("usmc", sqB, 3)
check(TIF.Say(a1, "contact", 1) ~= nil, "a line plays")
check(played[#played].lvl == 90, "voice level 90")
check(TIF.Say(a2, "contact", 1) == nil, "same squad inside 0.5 s: held")
check(TIF.Say(b1, "contact", 1) ~= nil, "another squad of the same faction talks at the same time")
now = now + 0.6
check(TIF.Say(a2, "contact", 1) ~= nil, "same squad after 0.5 s: plays")
check(TIF.Say(a1, "contact", 1) == nil, "same soldier inside 1.8 s: held")
now = now + 1.3
check(TIF.Say(a1, "moving", 1) ~= nil, "same soldier after 1.8 s, bf3 'moving' via fallback")

TIF.AWARE = { ENGAGED = 3 }
TIF.GTG = { WeaponKind = function(c) return c == "lmg" and "lmg" or "rifle" end }
local members = {}
TIF.Squad = { Members = function() return members end }
math.Rand = function(x, y) return (x + y) / 2 end
assert(loadfile(ROOT .. "tif/squad/sv_chatter.lua"))()
local C = TIF.Chatter
local gunner = { TIFSoldier = true, tifWep = { class = "lmg" } }
local sniper = { TIFSoldier = true, tifWep = { class = "rifle" }, tifArch = { id = "marksman" } }
local rpgman = { TIFSoldier = true, tifWep = { class = "rpg", def = { projectile = {} } } }
check(C.ContactEvent(gunner) == "contact_mg", "spotting an LMG gunner: contact_mg")
check(C.ContactEvent(sniper) == "contact_sniper", "spotting a marksman: contact_sniper")
check(C.ContactEvent(rpgman) == "contact_rpg", "spotting a launcher: contact_rpg")

local sq = {}
played = {}
for i = 1, 4 do
	local m = npc("insurgents", sq, 10 + i)
	m.tifAware = 3
	m.GetTIFShotTime = function() return now - 1 end
	m.tifPrimaryC = { ent = gunner }
	members[i] = m
end
local t0 = now
local lines = 0
for s = 0, 120 do
	now = t0 + s
	local before = #played
	C.Tick(sq, now)
	lines = lines + (#played - before)
end
check(lines >= 12 and lines <= 32, "an engaged squad chatters every ~4-8 s over 2 minutes (" .. lines .. " lines)")
check(sq.tifSpawnSaid == true, "spawn line considered once")
local quiet = {}
for i = 1, 3 do
	local m = npc("insurgents", quiet, 20 + i)
	m.tifAware = 1
	members[i] = m
end
members[4] = nil
played = {}
for s = 0, 60 do now = t0 + 200 + s C.Tick(quiet, now) end
local chat = 0
for _, p in ipairs(played) do if cat_of(p.snd) ~= "spawn" and cat_of(p.snd) ~= "affirmative" and cat_of(p.snd) ~= "advance" then chat = chat + 1 end end
check(chat == 0, "no firefight chatter while not engaged")
print(string.format("passed %d, failed %d", pass, fail))
