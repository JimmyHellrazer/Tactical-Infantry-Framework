-- tif_bench <count> [battle|patrol|mixed] [seconds] [keep]
--   battle: two equal groups (militia at your crosshair, PMC around you) fighting each other
--   patrol: every soldier unaware on duty, spread out far away
--   mixed:  half fighting, half idle
-- You are set to notarget for the run. Soldiers get extra health so the fight lasts.
-- Writes data/tif/reports/bench_<count>_<mode>.txt

local TIF = TIF
util.AddNetworkString("tif_bench_start")
util.AddNetworkString("tif_bench_query")
util.AddNetworkString("tif_bench_reply")

local KEYS = { "sched", "perception", "brain", "path", "tick", "events", "cover", "cover_behave", "suppression" }
local COUNTS = { "thinks", "trace", "trace_denied", "path", "path_denied", "sched_over_budget", "slots_rebuilt", "slots_refresh_requests",
	"cover_searches", "cover_traces", "cover_cache_hits" }

local run

-- Real time between server ticks (engine.ServerFrameTime doesn't exist in every build).
local tickStats = { last = nil, sum = 0, n = 0, max = 0 }
hook.Add("Tick", "tif_bench_ticktime", function()
	if not run then tickStats.last = nil return end
	local now = SysTime()
	if tickStats.last then
		local dt = now - tickStats.last
		tickStats.sum, tickStats.n = tickStats.sum + dt, tickStats.n + 1
		if dt > tickStats.max then tickStats.max = dt end
	end
	tickStats.last = now
end)

local function finish_report(clientData)
	local b = run
	local r = TIF.NewReport("bench_" .. b.count .. "_" .. b.mode, "TIF benchmark: " .. b.count .. " soldiers, " .. b.mode)
	local tick = 1 / engine.TickInterval()
	r:Section("Setup")
	r:Info("Soldiers spawned", tostring(b.spawned))
	r:Info("Mode", b.mode)
	r:Info("Duration", b.seconds .. " s, sampled every second")
	r:Info("Server tick rate", TIF.Fmt(tick, 0) .. "/s")
	r:Info("Navmesh areas", tostring(navmesh.GetNavAreaCount()))

	local avg, peak = {}, {}
	for _, k in ipairs(KEYS) do avg[k], peak[k] = 0, 0 end
	local cAvg = {}
	for _, k in ipairs(COUNTS) do cAvg[k] = 0 end
	local n = #b.samples
	for _, s in ipairs(b.samples) do
		for _, k in ipairs(KEYS) do
			avg[k] = avg[k] + s.times[k] / n
			if s.times[k] > peak[k] then peak[k] = s.times[k] end
		end
		for _, k in ipairs(COUNTS) do cAvg[k] = cAvg[k] + s.counts[k] / n end
	end

	r:Section("Server AI cost (ms per second of game time; per-tick = divided by tick rate)")
	local total, totalPeak = 0, 0
	for _, k in ipairs(KEYS) do
		r:Line(string.format("  %-11s avg %7.2f ms/s  (%.3f ms/tick)   worst second %7.2f ms/s", k, avg[k], avg[k] / tick, peak[k]))
	end
	-- perception, brain, cover and cover_behave run inside sched; the rest are separate.
	for _, k in ipairs({ "sched", "tick", "events", "path", "suppression" }) do total, totalPeak = total + avg[k], totalPeak + peak[k] end
	r:Line(string.format("  TOTAL       avg %7.2f ms/s  (%.3f ms/tick)   worst second ~%.2f ms/s", total, total / tick, totalPeak))
	local perTick = total / tick
	local budget = engine.TickInterval() * 1000
	local share = perTick / budget * 100
	local msg = TIF.Fmt(share, 1) .. "% of a " .. TIF.Fmt(budget, 1) .. " ms tick"
	if share < 15 then r:Pass("AI share of the server tick", msg)
	elseif share < 35 then r:Warn("AI share of the server tick", msg)
	else r:Fail("AI share of the server tick", msg) end

	r:Section("Workload per second")
	for _, k in ipairs(COUNTS) do r:Line(string.format("  %-18s %8.1f", k, cAvg[k])) end
	if cAvg.trace_denied > 0 then r:Info("Sight traces were deferred by the budget", "soldiers kept their last result for that tick") end

	r:Section("Per-second samples (alive militia/pmc, tiers 0/1/2/3, AI ms/s, tick interval avg/worst ms)")
	for i, s in ipairs(b.samples) do
		r:Line(string.format("  %3d  alive %2d/%2d  tiers %d/%d/%d/%d  ai %6.2f  tick %.2f/%.2f",
			i, s.alive.militia or 0, s.alive.pmc or 0, s.tiers[0], s.tiers[1], s.tiers[2], s.tiers[3], s.total, s.frame, s.frameMax or 0))
	end

	r:Section("Client (host player)")
	if clientData then
		r:Info("Frame time", string.format("avg %.2f ms (%.0f fps), worst %.2f ms", clientData.avgFt, 1000 / math.max(0.01, clientData.avgFt), clientData.maxFt))
		r:Info("Animation composer", string.format("%.2f ms/s", clientData.animMs))
		r:Info("Retarget solves", string.format("%.0f/s at %.1f us each", clientData.solves, clientData.solveUs))
		r:Info("Bone builds checked after the layer write", string.format("%d (plus %d earlier in the frame, discarded)",
			clientData.checked or 0, clientData.early or 0))
		local over = clientData.overwritten * 100
		if over < 5 then r:Pass("Layer writes survive until bone setup", string.format("%.1f%% overwritten", over))
		else r:Fail("Layer writes survive until bone setup", string.format("%.1f%% overwritten: blending must move later in the frame", over)) end
		if (clientData.missingPeak or 0) == 0 then r:Pass("No soldier was ever missing layer slots on the client")
		else
			r:Warn("Soldiers missing layer slots", string.format("peak %d at once, %d soldier-frames, %d refresh requests sent",
				clientData.missingPeak or 0, clientData.missing or 0, clientData.refreshAsked or 0))
		end
	else
		r:Warn("No client data", "the host didn't reply")
	end
	r:Save()
end

local function stop()
	if not run then return end
	timer.Remove("tif_bench_sample")
	if IsValid(run.ply) and run.notargetBefore ~= nil then
		if not run.notargetBefore then run.ply:RemoveFlags(FL_NOTARGET) end
	end
	if not run.keep then
		for _, e in ipairs(run.ents) do if IsValid(e) then e:Remove() end end
	end
	run = nil
end

local function sample()
	local last = TIF.Prof.Last
	local s = { times = {}, counts = {}, alive = {}, tiers = { [0] = 0, 0, 0, 0 } }
	for _, k in ipairs(KEYS) do s.times[k] = last.times[k] and last.times[k].ms or 0 end
	for _, k in ipairs(COUNTS) do s.counts[k] = last.counts[k] or 0 end
	s.total = s.times.sched + s.times.tick + s.times.events + s.times.path + s.times.suppression
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) then
			local f = npc:GetTIFFaction()
			s.alive[f] = (s.alive[f] or 0) + 1
			s.tiers[npc.tifTier or 2] = (s.tiers[npc.tifTier or 2] or 0) + 1
		end
	end
	-- Average and worst real time between ticks over the last second (singleplayer: tied to client fps).
	s.frame = tickStats.n > 0 and tickStats.sum / tickStats.n * 1000 or 0
	s.frameMax = tickStats.max * 1000
	tickStats.sum, tickStats.n, tickStats.max = 0, 0, 0
	run.samples[#run.samples + 1] = s
end

local function finish(clientData)
	if not run or run.reported then return end
	run.reported = true
	local ok, err = pcall(finish_report, clientData)
	if not ok then TIF.Error("Benchmark report failed: ", tostring(err)) end
	stop()
end

concommand.Add("tif_bench", function(ply, _, args)
	if not TIF.CanUseDev(ply) or not IsValid(ply) then return end
	if run then TIF.Warn("A benchmark is already running") return end
	local count = math.Clamp(tonumber(args[1]) or 10, 2, 100)
	local mode = args[2] or "battle"
	local seconds = math.Clamp(tonumber(args[3]) or 45, 10, 300)
	local keep = args[4] == "keep"
	for _, npc in ipairs(table.Copy(TIF.Soldiers)) do if IsValid(npc) then npc:Remove() end end

	run = { ply = ply, count = count, mode = mode, seconds = seconds, keep = keep, ents = {}, samples = {} }
	run.notargetBefore = ply:IsFlagSet(FL_NOTARGET)
	ply:AddFlags(FL_NOTARGET)

	local here = ply:GetPos()
	local there = ply:GetEyeTrace().HitPos
	local opts = { health = 400, radius = 400 }
	local function add(list) for _, e in ipairs(list) do run.ents[#run.ents + 1] = e end end
	if mode == "patrol" then
		add(TIF.SpawnSoldiers(ply, "militia", count, "guard", there, "random", { radius = 2500 }))
	elseif mode == "mixed" then
		local fight = math.floor(count / 2)
		add(TIF.SpawnSoldiers(ply, "militia", math.ceil(fight / 2), "rifleman", there, here, opts))
		add(TIF.SpawnSoldiers(ply, "pmc", math.floor(fight / 2), "rifleman", here, there, opts))
		add(TIF.SpawnSoldiers(ply, "militia", count - fight, "guard", there + (there - here):GetNormalized() * 2500, "random", { radius = 1500 }))
	else
		mode = "battle"
		run.mode = mode
		add(TIF.SpawnSoldiers(ply, "militia", math.ceil(count / 2), "rifleman", there, here, opts))
		add(TIF.SpawnSoldiers(ply, "pmc", math.floor(count / 2), "rifleman", here, there, opts))
	end
	run.spawned = #run.ents
	TIF.Log("Benchmark: ", run.spawned, " soldiers, ", mode, ", ", seconds, " s. Keep looking at the area.")

	net.Start("tif_bench_start")
	net.Send(ply)
	-- Skip the first 3 seconds (spawning, first paths) before sampling.
	timer.Simple(3, function()
		if not run then return end
		timer.Create("tif_bench_sample", 1, seconds, function()
			if not run then return end
			local ok, err = pcall(sample)
			if not ok then
				TIF.Error("Benchmark sample failed, stopping: ", tostring(err))
				stop()
				return
			end
			if #run.samples >= run.seconds then
				if IsValid(run.ply) then
					net.Start("tif_bench_query")
					net.Send(run.ply)
				end
				timer.Simple(3, function() finish(nil) end)
			end
		end)
	end)
end, nil, "tif_bench <count> [battle|patrol|mixed] [seconds] [keep]: measure AI cost and write a report")

net.Receive("tif_bench_reply", function(_, ply)
	if not run or ply ~= run.ply then return end
	finish(util.JSONToTable(net.ReadString() or "") or nil)
end)

concommand.Add("tif_bench_stop", function(ply)
	if not TIF.CanUseDev(ply) then return end
	if not run then TIF.Log("No benchmark running") return end
	timer.Remove("tif_bench_sample")
	if #run.samples == 0 then
		stop()
		TIF.Log("Benchmark stopped (no samples yet, no report)")
		return
	end
	-- Still collect the client's numbers before writing the report.
	if IsValid(run.ply) then
		net.Start("tif_bench_query")
		net.Send(run.ply)
	end
	timer.Simple(3, function() finish(nil) end)
	TIF.Log("Benchmark stopped early; writing the report")
end, nil, "Stop a running benchmark early (still writes a report)")
