local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local now = 100
function CurTime() return now end
TIF = {}
local src = io.open(ROOT .. "tif/config/sh_packs.lua"):read("*a")
local a = src:find("TIF.VARIETY_WINDOW = 8", 1, true)
local b = src:find("\nend\n", src:find("function TIF.VarietyPick", a, true), true)
check(a and b, "variety block found")
assert(loadstring(src:sub(a, b + 4)))()
local opts = { "light", "standard", "heavy" }
local seen = {}
for i = 1, 6 do local p = TIF.VarietyPick("usmc", "model", opts) seen[p] = (seen[p] or 0) + 1 now = now + 0.2 end
check(seen.light == 2 and seen.standard == 2 and seen.heavy == 2, "a 6-man squad wears each of 3 outfits twice")
local first = {}
for i = 1, 3 do first[TIF.VarietyPick("insurgents", "model", opts)] = true end
check(first.light and first.standard and first.heavy, "another faction has its own bag: its first 3 are all different")
local g = {}
for i = 1, 4 do g[TIF.VarietyPick("usmc", "m.mdl#helmet", { 0, 1, 2, 3 })] = true end
check(g[0] and g[1] and g[2] and g[3], "a bodygroup's 4 options used once each before any repeats")
now = now + 9
local c = {}
for i = 1, 3 do c[TIF.VarietyPick("usmc", "model", opts)] = (c[TIF.VarietyPick("usmc", "model", opts)] or 0) end
check(TIF.VarietyBags.usmc.counts.model.light == 2 and TIF.VarietyBags.usmc.counts.model.heavy == 2, "after a gap the bag starts over (6 new picks spread 2/2/2)")
check(TIF.VarietyPick("usmc", "x", { "only" }) == "only" and TIF.VarietyPick("usmc", "x", {}) == nil, "one option / none")
local randoms = {}
for i = 1, 40 do
	TIF.VarietyBags = {}
	randoms[TIF.VarietyPick("usmc", "model", opts)] = true
end
check(randoms.light and randoms.standard and randoms.heavy, "ties are broken at random")
local soldier = io.open(ROOT .. "entities/tif_soldier.lua"):read("*a")
check(select(2, soldier:gsub('pick%(model %.%. "#" %.%. name, fit%)', "")) == 2, "both bodygroup paths go through the bag")
check(soldier:find('pick(model .. "#skin", skins)', 1, true) ~= nil, "skins through the bag")
local mod = io.open(ROOT .. "tif/config/sh_modular.lua"):read("*a")
check(mod:find('TIF.VarietyPick(def.id, "combo", use)', 1, true) and mod:find('TIF.VarietyPick(def.id, "slot#" .. slot, idx)', 1, true), "modular combos and parts through the bag")
print(string.format("passed %d, failed %d", pass, fail))
