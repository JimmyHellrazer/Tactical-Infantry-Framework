-- Client half of tif_bench: collects frame time and animation stats while the benchmark runs.

local TIF = TIF

local col

net.Receive("tif_bench_start", function()
	local s = TIF.Body.Stats
	col = { frames = 0, ft = 0, maxFt = 0, animMs = 0, solves = 0, solveUs = 0, seconds = 0, missingPeak = 0,
		checks0 = s.checks, over0 = s.overwritten, early0 = s.early or 0, missing0 = s.missingSlots, asked0 = s.refreshAsked, skipUntil = RealTime() + 3 }
	hook.Add("Think", "tif_bench_client", function()
		if RealTime() < col.skipUntil then return end
		local ft = FrameTime()
		col.frames = col.frames + 1
		col.ft = col.ft + ft
		if ft > col.maxFt then col.maxFt = ft end
		local m = TIF.Body.Stats.missingNow or 0
		if m > col.missingPeak then col.missingPeak = m end
	end)
	timer.Create("tif_bench_client", 1, 0, function()
		if RealTime() < col.skipUntil then return end
		local last = TIF.Prof.Last
		col.seconds = col.seconds + 1
		col.animMs = col.animMs + (last.times.cl_anim and last.times.cl_anim.ms or 0)
		col.solves = col.solves + (last.counts.cl_solves or 0)
		col.solveUs = col.solveUs + (last.counts.cl_solve_us or 0)
	end)
end)

net.Receive("tif_bench_query", function()
	if not col then return end
	hook.Remove("Think", "tif_bench_client")
	timer.Remove("tif_bench_client")
	local s = TIF.Body.Stats
	local checks = s.checks - col.checks0
	local secs = math.max(1, col.seconds)
	local out = {
		avgFt = col.frames > 0 and col.ft / col.frames * 1000 or 0,
		maxFt = col.maxFt * 1000,
		animMs = col.animMs / secs,
		solves = col.solves / secs,
		solveUs = col.solves > 0 and col.solveUs / col.solves or 0,
		overwritten = checks > 0 and (s.overwritten - col.over0) / checks or 0,
		missing = s.missingSlots - col.missing0,
		missingPeak = col.missingPeak,
		early = (s.early or 0) - col.early0,
		checked = checks,
		refreshAsked = s.refreshAsked - col.asked0,
	}
	col = nil
	net.Start("tif_bench_reply")
	net.WriteString(util.TableToJSON(out))
	net.SendToServer()
end)
