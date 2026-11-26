-- tif_bench <count> [battle|patrol|mixed] [seconds] [keep]
--   battle: two equal groups (side A at your crosshair, side B around you) fighting each other
--   patrol: every soldier unaware on duty, spread out far away
--   mixed:  half fighting, half idle
-- You are set to notarget for the run. Soldiers get extra health so the fight lasts.
-- Sides: tif_bench_a (insurgents) and tif_bench_b (usmc), any installed faction.
-- Writes data/tif/reports/bench_<count>_<mode>_<version>.txt

local TIF = TIF
util.AddNetworkString("tif_bench_start")
util.AddNetworkString("tif_bench_query")
util.AddNetworkString("tif_bench_reply")

local cvA = CreateConVar("tif_bench_a", "insurgents", FCVAR_ARCHIVE, "tif_bench: the side spawned at your crosshair")
local cvB = CreateConVar("tif_bench_b", "usmc", FCVAR_ARCHIVE, "tif_bench: the side spawned around you")

local KEYS = { "sched", "perception", "brain", "cover", "cover_mw", "cover_behave", "path", "tick", "move", "crowd", "events", "suppression" }
local TOTAL = { "sched", "tick", "move", "events", "path", "suppression" }
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
	local ver = string.gsub(TIF.Version or "x", "[^%w]", "_")
	local r = TIF.NewReport("bench_" .. b.count .. "_" .. b.mode .. "_" .. ver, "TIF benchmark: " .. b.count .. " soldiers, " .. b.mode)
	local tick = 1 / engine.TickInterval()
	r:Section("Setup")
	r:Info("Soldiers spawned", tostring(b.spawned))
	r:Info("Mode", b.mode)
	r:Info("Duration", b.seconds .. " s, sampled every second")
	r:Info("Server tick rate", TIF.Fmt(tick, 0) .. "/s")
	r:Info("Navmesh areas", tostring(navmesh.GetNavAreaCount()))
	for _, side in ipairs({ b.a, b.b }) do
		local def = TIF.Factions[side] or {}
		local list = {}
		for m, n in pairs(b.models[side] or {}) do list[#list + 1] = string.format("%s x%d", string.GetFileFromFilename(m), n) end
		table.sort(list)
		r:Info("Side " .. side, string.format("%s, %d spawned: %s", def.name or side, b.spawnedBy[side] or 0, table.concat(list, ", ")))
	end

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
		r:Line(string.format("  %-12s avg %7.2f ms/s  (%.3f ms/tick)   worst second %7.2f ms/s", k, avg[k], avg[k] / tick, peak[k]))
	end
	for _, k in ipairs(TOTAL) do total, totalPeak = total + avg[k], totalPeak + peak[k] end
	r:Line("  (perception, brain and the cover buckets run inside sched; crowd inside move)")
	r:Line(string.format("  TOTAL        avg %7.2f ms/s  (%.3f ms/tick)   worst second ~%.2f ms/s", total, total / tick, totalPeak))
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

	r:Section("Per-second samples (alive " .. b.a .. "/" .. b.b .. ", tiers 0/1/2/3, AI ms/s, tick interval avg/worst ms)")
	for i, s in ipairs(b.samples) do
		r:Line(string.format("  %3d  alive %2d/%2d  tiers %d/%d/%d/%d  ai %6.2f  tick %.2f/%.2f",
			i, s.alive[b.a] or 0, s.alive[b.b] or 0, s.tiers[0], s.tiers[1], s.tiers[2], s.tiers[3], s.total, s.frame, s.frameMax or 0))
	end

	r:Section("Client (host player)")
	if clientData then
		r:Info("Frame time", string.format("avg %.2f ms (%.0f fps), worst %.2f ms", clientData.avgFt, 1000 / math.max(0.01, clientData.avgFt), clientData.maxFt))
		r:Info("Animation composer", string.format("%.2f ms/s", clientData.animMs))
		r:Info("Retarget solves", string.format("%.0f/s at %.1f us each", clientData.solves, clientData.solveUs))
		r:Info("Soldiers animated", string.format("%.1f in the client's list, %.0f composes/s", clientData.soldiers or 0, clientData.composed or 0))
		r:Info("  of which compose", string.format("%.2f ms/s", clientData.composeMs or 0))
		r:Info("  of which bone build + gun placement", string.format("%.2f ms/s (includes the arm IK and foot callbacks)", clientData.bonesMs or 0))
		r:Info("  of which parts check", string.format("%.2f ms/s", clientData.partsMs or 0))
		r:Info("  of which foley", string.format("%.2f ms/s", clientData.foleyMs or 0))
		r:Info("  of which slots + spine pose", string.format("%.2f ms/s", clientData.poseMs or 0))
		r:Info("Out-of-view LOD", string.format("%s: %.0f cheap composes/s, %.0f skipped soldier-frames/s", clientData.lodOn and "on" or "off", clientData.lodOff or 0, clientData.lodSkip or 0))
		r:Info("Gun hold arm IK", string.format("%.2f ms/s (%.0f soldier-frames/s at %.1f us each)", clientData.ikMs or 0, clientData.ikN or 0, clientData.ikUs or 0))
		r:Info("Foot IK / turn lean", string.format("%.2f ms/s (%.0f soldier-frames/s at %.1f us each)", clientData.feetMs or 0, clientData.feetN or 0, clientData.feetUs or 0))
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
	s.total = 0
	for _, k in ipairs(TOTAL) do s.total = s.total + s.times[k] end
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) then
			local f = TIF.FactionCanon(npc:GetTIFFaction())
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

	local A, B = TIF.FactionCanon(cvA:GetString()), TIF.FactionCanon(cvB:GetString())
	for _, f in ipairs({ A, B }) do
		if not TIF.Factions[f] then TIF.Warn("tif_bench: faction '", f, "' isn't installed") return end
	end
	run = { ply = ply, count = count, mode = mode, seconds = seconds, keep = keep, ents = {}, samples = {}, a = A, b = B,
		models = {}, spawnedBy = {} }
	run.notargetBefore = ply:IsFlagSet(FL_NOTARGET)
	ply:AddFlags(FL_NOTARGET)

	local here = ply:GetPos()
	local there = ply:GetEyeTrace().HitPos
	local opts = { health = 400, radius = 400 }
	local function add(list) for _, e in ipairs(list or {}) do run.ents[#run.ents + 1] = e end end
	if mode == "patrol" then
		add(TIF.SpawnSoldiers(ply, A, count, "guard", there, "random", { radius = 2500 }))
	elseif mode == "mixed" then
		local fight = math.floor(count / 2)
		add(TIF.SpawnSoldiers(ply, A, math.ceil(fight / 2), "rifleman", there, here, opts))
		add(TIF.SpawnSoldiers(ply, B, math.floor(fight / 2), "rifleman", here, there, opts))
		add(TIF.SpawnSoldiers(ply, A, count - fight, "guard", there + (there - here):GetNormalized() * 2500, "random", { radius = 1500 }))
	else
		mode = "battle"
		run.mode = mode
		add(TIF.SpawnSoldiers(ply, A, math.ceil(count / 2), "rifleman", there, here, opts))
		add(TIF.SpawnSoldiers(ply, B, math.floor(count / 2), "rifleman", here, there, opts))
	end
	run.spawned = #run.ents
	timer.Simple(1, function()
		if not run then return end
		for _, e in ipairs(run.ents) do
			if IsValid(e) and e.GetTIFVisual then
				local f = TIF.FactionCanon(e:GetTIFFaction())
				local m = e:GetTIFVisual()
				run.spawnedBy[f] = (run.spawnedBy[f] or 0) + 1
				run.models[f] = run.models[f] or {}
				run.models[f][m] = (run.models[f][m] or 0) + 1
			end
		end
	end)
	TIF.Log("Benchmark: ", run.spawned, " soldiers (", A, " vs ", B, "), ", mode, ", ", seconds, " s. Keep looking at the area.")

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
