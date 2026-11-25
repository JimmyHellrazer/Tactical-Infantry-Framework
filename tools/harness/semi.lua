-- Offline (0.38.2): semi-auto patterns per gun (sv_weapon W.SEMI): DMRs / FAL string shots up close and space them
-- out far away, the Rytec stays heavy and spaced, whoever carries them. Runs sv_weapon's own burst_size / cadence /
-- pause on a shot loop and measures the gaps.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
math.Rand = function(a, b) return a + (b - a) * math.random() end
local src = io.open(ROOT .. "tif/npc/sv_weapon.lua"):read("*a")
local block = src:match("(W%.BAND_CLOSE, W%.BAND_MID.-\nlocal function pause%(.-\nend\n)")
check(block ~= nil, "firing block found")
local W = {}
local env = setmetatable({ W = W, TIF = { GTG = { WeaponKind = function(c) return c == "pistol" and "pistol" or "rifle" end } } }, { __index = _G })
local fn = assert(load(block .. "\nreturn burst_size, cadence, pause", "fire", "t", env))
local burst_size, cadence, pause = fn()
local ARCH = { marksman = { burst = { 1, 1 }, burstPause = { 0.9, 1.7 } }, rifleman = { burst = { 3, 7 }, burstPause = { 0.3, 0.8 } } }
-- shots over 60 s of fire at a distance; returns mean gap, min gap, mean string length
local function run(def, archId, dist)
	local npc = { tifArch = ARCH[archId] }
	local w = { class = "dmr" }
	local t, last, gaps, minGap, strings, rounds = 0, nil, 0, 99, 0, 0
	local count = 0
	while t < 60 do
		local n = burst_size(npc, w, def, dist, false, false)
		strings = strings + 1
		for i = 1, n do
			if last then local g = t - last gaps = gaps + g count = count + 1 if g < minGap then minGap = g end end
			last = t
			rounds = rounds + 1
			if i < n then t = t + cadence(w, def, dist) end
		end
		t = t + pause(npc, w, def, dist, false)
	end
	return gaps / math.max(1, count), minGap, rounds / strings
end
local DMR = { rate = 60 / 240, auto = false, semi = "dmr" }
local FAL = { rate = 60 / 650, auto = false, semi = "dmr" }
local RYTEC = { rate = 60 / 65, auto = false, semi = "heavy" }
local bands = { close = 300, mid = 900, long = 2500 }
local out = {}
for _, g in ipairs({ { "DMR", DMR }, { "FAL", FAL }, { "Rytec", RYTEC } }) do
	for _, a in ipairs({ "marksman", "rifleman" }) do
		local r = {}
		for _, b in ipairs({ "close", "mid", "long" }) do
			local mean, mn, len = run(g[2], a, bands[b])
			r[b] = { mean = mean, min = mn, len = len }
		end
		out[g[1] .. "/" .. a] = r
		print(string.format("%-6s %-9s close %.2fs (min %.2f, %.1f/str)  mid %.2fs (min %.2f, %.1f/str)  long %.2fs (min %.2f, %.1f/str)",
			g[1], a, r.close.mean, r.close.min, r.close.len, r.mid.mean, r.mid.min, r.mid.len, r.long.mean, r.long.min, r.long.len))
	end
end
for _, k in ipairs({ "DMR/marksman", "DMR/rifleman", "FAL/rifleman" }) do
	local r = out[k]
	check(r.close.len >= 2 and r.close.min >= 0.29 and r.close.min < 0.45, k .. ": strings of 2-3, ~0.3-0.4 s apart up close")
	check(r.mid.len >= 1 and r.mid.len <= 2 and r.mid.min >= 0.95, k .. ": 1-2 at mid range, ~1-1.4 s apart")
	check(r.long.len == 1 and r.long.min >= 1.75, k .. ": single spaced shots far out")
	check(r.close.mean < r.mid.mean and r.mid.mean < r.long.mean, k .. ": spacing grows with range")
end
check(out["DMR/marksman"].close.mean == out["DMR/marksman"].close.mean, "same pattern for any carrier")
for _, a in ipairs({ "marksman", "rifleman" }) do
	local r = out["Rytec/" .. a]
	check(r.close.len == 1 and r.close.min >= 1.79, "Rytec (" .. a .. "): single shots, >= 1.8 s up close")
	check(r.long.min >= 2.69, "Rytec (" .. a .. "): >= 2.7 s far out")
end
-- guns without a pattern are untouched (a rifleman's AK still bursts)
local npc = { tifArch = ARCH.rifleman }
local n = 0
for i = 1, 50 do n = n + burst_size(npc, { class = "ak" }, { rate = 0.1, auto = true }, 900, false, false) end
check(n / 50 > 1.5, "an automatic rifle still fires bursts (" .. n / 50 .. ")")
print(string.format("passed %d, failed %d", pass, fail))
