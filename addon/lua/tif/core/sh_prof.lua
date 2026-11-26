local TIF = TIF
TIF.Prof = TIF.Prof or {}
local P = TIF.Prof

local SysTime = SysTime
P.acc = P.acc or {}
P.cnt = P.cnt or {}
P.Last = P.Last or { times = {}, counts = {}, window = 1 }
local stack, depth = {}, 0
local windowStart = SysTime()

function P.Begin(key)
	depth = depth + 1
	stack[depth * 2 - 1] = key
	stack[depth * 2] = SysTime()
end

function P.End()
	if depth <= 0 then return end
	local key, t0 = stack[depth * 2 - 1], stack[depth * 2]
	depth = depth - 1
	local dt = SysTime() - t0
	local a = P.acc[key]
	if not a then
		a = { t = 0, n = 0, max = 0 }
		P.acc[key] = a
	end
	a.t, a.n = a.t + dt, a.n + 1
	if dt > a.max then a.max = dt end
end

function P.Count(key, n)
	P.cnt[key] = (P.cnt[key] or 0) + (n or 1)
end

local function roll()
	local now = SysTime()
	local window = math.max(0.001, now - windowStart)
	windowStart = now
	local times, counts = {}, {}
	for k, a in pairs(P.acc) do
		times[k] = { ms = a.t * 1000 / window, calls = a.n / window, max = a.max * 1000 }
		a.t, a.n, a.max = 0, 0, 0
	end
	for k, v in pairs(P.cnt) do
		counts[k] = v / window
		P.cnt[k] = 0
	end
	P.Last = { times = times, counts = counts, window = window }

	depth = 0
end

timer.Create("tif_prof_roll", 1, 0, roll)
