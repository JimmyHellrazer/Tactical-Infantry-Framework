-- Client half of tif_bench: collects frame time and animation stats while the benchmark runs.

local TIF = TIF

local col

net.Receive("tif_bench_start", function()
	local s = TIF.Body.Stats
	col = { frames = 0, ft = 0, maxFt = 0, animMs = 0, solves = 0, solveUs = 0, feetUs = 0, feetN = 0, ikUs = 0, ikN = 0, composeMs = 0, bonesMs = 0, partsMs = 0, foleyMs = 0, poseMs = 0, soldiers = 0, seconds = 0, missingPeak = 0,
		checks0 = s.checks, over0 = s.overwritten, early0 = s.early or 0, missing0 = s.missingSlots, asked0 = s.refreshAsked, skipUntil = RealTime() + 3 }
	hook.Add("Think", "tif_bench_client", function()
		if RealTime() < col.skipUntil then return end
		col.composed0 = col.composed0 or TIF.Body.Stats.composed
		col.lodOff0 = col.lodOff0 or (TIF.Body.Stats.lodOff or 0)
		col.lodSkip0 = col.lodSkip0 or (TIF.Body.Stats.lodSkipped or 0)
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
		col.feetUs = col.feetUs + (last.counts.cl_feet_us or 0)
		col.feetN = col.feetN + (last.counts.cl_feet_n or 0)
		col.ikUs = col.ikUs + (last.counts.cl_ik_us or 0)
		col.composeMs = col.composeMs + (last.times.cl_compose and last.times.cl_compose.ms or 0)
		col.bonesMs = col.bonesMs + (last.times.cl_bones and last.times.cl_bones.ms or 0)
		col.partsMs = col.partsMs + (last.times.cl_parts and last.times.cl_parts.ms or 0)
		col.foleyMs = col.foleyMs + (last.times.cl_foley and last.times.cl_foley.ms or 0)
		col.poseMs = col.poseMs + (last.times.cl_pose and last.times.cl_pose.ms or 0)
		col.ikN = col.ikN + (last.counts.cl_ik_n or 0)
		col.soldiers = col.soldiers + (TIF.Body.Stats.soldiers or 0)
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
		feetMs = col.feetUs / 1000 / secs,
		feetUs = col.feetN > 0 and col.feetUs / col.feetN or 0,
		feetN = col.feetN / secs,
		ikMs = col.ikUs / 1000 / secs,
		ikUs = col.ikN > 0 and col.ikUs / col.ikN or 0,
		ikN = col.ikN / secs,
		soldiers = col.soldiers / secs,
		composeMs = col.composeMs / secs,
		bonesMs = col.bonesMs / secs,
		partsMs = col.partsMs / secs,
		foleyMs = col.foleyMs / secs,
		poseMs = col.poseMs / secs,
		lodOff = ((s.lodOff or 0) - (col.lodOff0 or s.lodOff or 0)) / math.max(0.001, col.ft),
		lodSkip = ((s.lodSkipped or 0) - (col.lodSkip0 or s.lodSkipped or 0)) / math.max(0.001, col.ft),
		lodOn = TIF.Body.LOD and TIF.Body.LOD.on or false,
		composed = (s.composed - (col.composed0 or s.composed)) / math.max(0.001, col.ft),
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
