local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
local errs = {}
function ErrorNoHalt(m) errs[#errs + 1] = m end
SERVER, CLIENT = true, false
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end, Create = function() end }
weapons = { GetStored = function() return nil end, GetList = function() return {} end }
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
file = { Find = function() return {}, {} end, Exists = function() return false end }
jit = jit or { off = function() end }
engine = { TickInterval = function() return 0.015 end, TickCount = function() return 1 end }
util = util or {}
function IsValid(x) return x ~= nil end

local function fresh(core)
	TIFG = nil
	local ok, err = pcall(dofile, core)
	if not ok then print("LOAD", err) end
	return TIFG
end

local function load_clips(T)
	local t0 = os.clock()
	dofile(CLIPS)
	return os.clock() - t0
end

local OLD = "K:/jimmyproject/_addon_backups/2026-11-26_mwmale_split/sh_core.lua"
local NEW = ROOT .. "tif/gta/sh_core.lua"

local To = fresh(OLD)
To.ClipSet({ "mw_male", "base_pack" })
local tOld = load_clips(To)
local oldList, oldClips, oldSet = To.ClipList.mw_male, To.Clips.mw_male, To.ClipList["mw_male+base_pack"]

local Tn = fresh(NEW)
Tn.ClipSet({ "mw_male", "base_pack" })
local tNew = load_clips(Tn)
local newList, newClips, newSet = Tn.ClipList.mw_male, Tn.Clips.mw_male, Tn.ClipList["mw_male+base_pack"]

check(oldList and newList and #oldList.names == #newList.names and #newList.names == 4332, "same clip count (" .. (newList and #newList.names or 0) .. ")")
local same = true
for i, n in ipairs(oldList.names) do
	if newList.names[i] ~= n or newList.index[n] ~= oldList.index[n] then same = false break end
end
check(same, "same names in the same order, same network indexes")
local sameClips = true
for n, c in pairs(oldClips) do
	local d = newClips[n]
	if not d or d.seq ~= c.seq or d.dur ~= c.dur or d.frames ~= c.frames then sameClips = false break end
end
check(sameClips, "same clip data")
check(newSet and oldSet and #newSet.names == #oldSet.names, "clip sets built the same")
check(#Tn.MissingPacks({ packs = { "mw_male" } }) == 0, "the pack counts as whole")
print(string.format("load: old %.0f ms, new %.0f ms", tOld * 1000, tNew * 1000))
check(tNew < tOld, "loading is cheaper than before")

local parts = Tn.ClipParts.mw_male
local p5 = parts[5]
local gone, kept
for n in pairs(p5) do if not gone then gone = n elseif not kept then kept = n end end
local re = {}
for n, c in pairs(p5) do if n ~= gone then re[n] = { seq = c.seq, dur = 9, frames = c.frames } end end
Tn.RegisterClips("mw_male", re, { part = 5, parts = #parts })
check(Tn.Clips.mw_male[gone] == nil and Tn.ClipList.mw_male.index[gone] == nil, "a refreshed part drops clips it no longer has")
check(Tn.Clips.mw_male[kept].dur == 9 and #Tn.ClipList.mw_male.names == 4331, "and its changes show, list rebuilt")

local Tp = fresh(NEW)
Tp.RegisterClips("half", { a = { seq = "a", frames = 2, dur = 1 } }, { part = 1, parts = 2 })
check(Tp.Clips.half.a ~= nil and Tp.ClipList.half == nil, "an incomplete pack has its clips but no list yet")
check(#Tp.MissingPacks({ packs = { "half" } }) == 1, "and counts as missing")
Tp.RegisterClips("half", { b = { seq = "b", frames = 2, dur = 1 } }, { part = 2, parts = 2 })
check(Tp.ClipList.half and #Tp.ClipList.half.names == 2, "the last part builds the list")
Tp.RegisterClips("whole", { c = { seq = "c", frames = 2, dur = 1 } })
check(Tp.ClipList.whole and #Tp.ClipList.whole.names == 1, "packs without parts register as before")
print(string.format("passed %d, failed %d", pass, fail))
