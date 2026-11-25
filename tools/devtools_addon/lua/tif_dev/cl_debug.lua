-- Debug overlay: per-soldier state above heads, last known positions, sight lines, view cones,
-- paths, heard sounds, and a performance panel. Draws nothing unless the server is sending data
-- (tif_debug 1).

local TIF = TIF
local Bd = TIF.Body

local TIME_KEYS = { "sched", "perception", "brain", "path", "tick", "events", "cover", "cover_behave", "suppression" }
local COUNT_KEYS = { "thinks", "trace", "trace_denied", "path", "path_denied", "sched_over_budget", "slots_rebuilt", "slots_refresh_requests",
	"cover_searches", "cover_traces", "cover_cache_hits" }
local AWARE_COLORS = {
	[0] = Color(150, 220, 150), Color(240, 220, 90), Color(255, 160, 60), Color(255, 70, 70), Color(120, 170, 255),
}

local data

net.Receive("tif_debug", function()
	local d = { time = RealTime(), times = {}, counts = {}, soldiers = {}, events = {} }
	for _, k in ipairs(TIME_KEYS) do d.times[k] = { ms = net.ReadFloat(), max = net.ReadFloat() } end
	for _, k in ipairs(COUNT_KEYS) do d.counts[k] = net.ReadFloat() end
	d.tickrate = net.ReadFloat()
	for _ = 1, net.ReadUInt(8) do
		if net.ReadBool() then
			local s = {
				idx = net.ReadUInt(13), tier = net.ReadUInt(2), hp = net.ReadUInt(10),
				ammo = net.ReadUInt(8), clip = net.ReadUInt(8), action = net.ReadString(), arch = net.ReadString(),
				ms = net.ReadFloat(), meter = net.ReadUInt(8) / 255, firing = net.ReadBool(),
				supp = net.ReadUInt(8) / 255,
			}
			if net.ReadBool() then
				s.lkp, s.visible, s.age, s.unc, s.source = net.ReadVector(), net.ReadBool(), net.ReadFloat(), net.ReadFloat(), net.ReadString()
			end
			if net.ReadBool() then s.goal = net.ReadVector() end
			local np = net.ReadUInt(4)
			if np > 0 then
				s.path = {}
				for i = 1, np do s.path[i] = net.ReadVector() end
			end
			d.soldiers[#d.soldiers + 1] = s
		end
	end
	for _ = 1, net.ReadUInt(5) do
		d.events[#d.events + 1] = { kind = net.ReadString(), pos = net.ReadVector(), radius = net.ReadFloat(), age = net.ReadFloat() }
	end
	data = d
end)

local function live()
	return data and RealTime() - data.time < 1
end

local function ring(center, radius, color, segs)
	segs = segs or 24
	local prev
	for i = 0, segs do
		local a = i / segs * math.pi * 2
		local p = center + Vector(math.cos(a) * radius, math.sin(a) * radius, 4)
		if prev then render.DrawLine(prev, p, color, true) end
		prev = p
	end
end

local CYAN, GREEN, RED, ORANGE, WHITE = Color(80, 220, 255), Color(90, 255, 120), Color(255, 60, 60), Color(255, 150, 40), Color(255, 255, 255)

hook.Add("PostDrawTranslucentRenderables", "tif_debug", function(depth, sky)
	if sky or not live() then return end
	for _, s in ipairs(data.soldiers) do
		local ent = Entity(s.idx)
		if IsValid(ent) and ent.TIFSoldier then
			local base = ent:GetPos()
			local eye = base + Vector(0, 0, ent:GetTIFStance() == 1 and 40 or 62)
			if s.path then
				for i = 2, #s.path do render.DrawLine(s.path[i - 1], s.path[i], CYAN, true) end
			end
			if s.goal then render.DrawWireframeSphere(s.goal, 8, 8, 8, GREEN, true) end
			-- Squad: line to the leader, in a colour per squad.
			local sqId = ent:GetNW2Int("tif_squad", 0)
			local lead = ent:GetNW2Entity("tif_sqlead")
			if sqId > 0 and IsValid(lead) and lead ~= ent then
				local col = HSVToColor((sqId * 67) % 360, 0.7, 1)
				render.DrawLine(eye, lead:GetPos() + Vector(0, 0, 60), col, true)
			end
			-- Maneuver goal (bound / flank) as a magenta line and ring.
			local mg = ent:GetNW2Vector("tif_mgoal", vector_origin)
			if mg ~= vector_origin and ent:GetNW2String("tif_role", "") == "maneuver" then
				local mcol = Color(255, 80, 255)
				render.DrawLine(base + Vector(0, 0, 10), mg + Vector(0, 0, 10), mcol, true)
				render.DrawWireframeSphere(mg, 12, 8, 8, mcol, true)
			end
			if s.lkp then
				local col = s.visible and RED or ORANGE
				render.DrawLine(eye, s.lkp + Vector(0, 0, 40), col, true)
				render.DrawWireframeSphere(s.lkp + Vector(0, 0, 40), 6, 6, 6, col, true)
				if s.unc and s.unc > 8 then ring(s.lkp, s.unc, col) end
			end
			-- View cone edges.
			local arch = TIF.Archetype(s.arch)
			local aware = ent:GetTIFAware()
			local fov = aware >= TIF.AWARE.ALERTED and arch.fov or arch.fovUnaware
			local yaw = ent:GetAngles().y
			for _, side in ipairs({ -1, 1 }) do
				local a = math.rad(yaw + side * fov * 0.5)
				render.DrawLine(eye, eye + Vector(math.cos(a), math.sin(a), 0) * 160, AWARE_COLORS[aware] or WHITE, true)
			end
		end
	end
	for _, e in ipairs(data.events) do
		local k = 1 - math.Clamp(e.age / 3, 0, 1)
		local col = e.kind == "gunfire" and Color(255, 90, 90, 255 * k) or Color(200, 200, 255, 255 * k)
		ring(e.pos, math.min(e.radius, 400) * (0.4 + 0.6 * (1 - k)), col, 20)
	end
end)

surface.CreateFont("TIFDebug3D", { font = "Roboto", size = 26, weight = 600, antialias = true })
surface.CreateFont("TIFDebugHUD", { font = "Roboto Mono", size = 15, weight = 500, antialias = true })

hook.Add("PostDrawTranslucentRenderables", "tif_debug_text", function(depth, sky)
	if sky or not live() then return end
	local eyeAng = EyeAngles()
	local ang = Angle(0, eyeAng.y - 90, 90)
	local me = LocalPlayer():GetPos()
	for _, s in ipairs(data.soldiers) do
		local ent = Entity(s.idx)
		if IsValid(ent) and ent.TIFSoldier and me:DistToSqr(ent:GetPos()) < 2500 * 2500 then
			local aware = ent:GetTIFAware()
			local col = AWARE_COLORS[aware] or WHITE
			local pos = ent:GetPos() + Vector(0, 0, 84)
			cam.Start3D2D(pos, ang, 0.12)
				local lines = {
					string.upper(TIF.AWARE_NAMES[aware] or "?") .. "  " .. (TIF.Archetype(s.arch).label or s.arch),
					s.action .. (s.firing and "  [FIRING]" or ""),
					string.format("hp %d  ammo %d/%d  tier %d  %.2f ms", s.hp, s.ammo, s.clip, s.tier, s.ms),
				}
				if s.lkp then
					lines[#lines + 1] = string.format("target %s  %s %.1fs ago  +-%d", s.visible and "SEEN" or "lost", s.source, s.age, s.unc or 0)
				end
				if s.meter > 0.01 then lines[#lines + 1] = string.format("detecting %d%%", s.meter * 100) end
				local sqId = ent:GetNW2Int("tif_squad", 0)
				if sqId > 0 then
					local lead = ent:GetNW2Entity("tif_sqlead")
					local who = ent:GetNW2Bool("tif_leader", false) and "LEADER" or
						(IsValid(lead) and lead:IsPlayer() and ("follows " .. lead:Nick()) or "")
					lines[#lines + 1] = string.format("squad %d  %s  %s", sqId, ent:GetNW2String("tif_order", ""), who)
					local role, tactic = ent:GetNW2String("tif_role", ""), ent:GetNW2String("tif_tactic", "")
					if role ~= "" or tactic ~= "" then
						lines[#lines + 1] = string.format("plan: %s  role: %s", tactic ~= "" and tactic or "-", role ~= "" and role or "-")
					end
				end
				local job = ent:GetNW2String("tif_job", "")
				if job ~= "" then lines[#lines + 1] = "job: " .. job end
				local mo = ent:GetNW2String("tif_morale", "")
				if mo ~= "" and mo ~= "steady" then lines[#lines + 1] = "morale: " .. string.upper(mo) end
				if ent:GetNW2Bool("tif_downed", false) then lines[#lines + 1] = "DOWNED" end
				if s.supp > 0.01 then
					lines[#lines + 1] = "suppressed " .. string.rep("|", math.ceil(s.supp * 20)) .. string.format(" %d%%", s.supp * 100)
				end
				-- What the server asked for vs. what this client is actually drawing.
				local act = ent:GetNW2String("tif_act", "")
				if act ~= "" then
					lines[#lines + 1] = "server clip: " .. act .. (ent:GetNW2Bool("tif_caim", false) and "  [aiming over]" or "")
				end
				local ok, seq = pcall(ent.GetLayerSequence, ent, 0)
				local okw, w = pcall(ent.GetLayerWeight, ent, 0)
				if ok and seq then
					lines[#lines + 1] = string.format("client slot0: %s  w %.2f  stance %d mode %d", ent:GetSequenceName(seq) or "?",
						okw and w or -1, ent:GetTIFStance(), ent:GetTIFMode())
				end
				for i, l in ipairs(lines) do
					draw.SimpleTextOutlined(l, "TIFDebug3D", 0, (i - 1) * 28, i == 1 and col or WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, color_black)
				end
			cam.End3D2D()
		end
	end
end)

-- Cover points ------------------------------------------------------------------
-- green: usable, can shoot   yellow: usable, hide only   blue: reserved   grey: rejected (reason shown)

local coverPts, coverRays, coverTime = {}, {}, 0
net.Receive("tif_debug_cover", function()
	local list = {}
	for i = 1, net.ReadUInt(8) do
		local p = { pos = net.ReadVector() }
		if net.ReadBool() then p.ny = net.ReadFloat() end
		p.reject = net.ReadString()
		p.high, p.edgeL, p.edgeR, p.canShoot, p.reserved = net.ReadBool(), net.ReadBool(), net.ReadBool(), net.ReadBool(), net.ReadBool()
		p.score, p.why, p.material = net.ReadFloat(), net.ReadString(), net.ReadString()
		list[i] = p
	end
	local rays = {}
	for i = 1, net.ReadUInt(8) do
		rays[i] = { a = net.ReadVector(), b = net.ReadVector(), kind = net.ReadUInt(2) }
	end
	coverPts, coverRays, coverTime = list, rays, RealTime()
end)

-- Search rays: green = found an obstacle between soldier and threat, orange = obstacle facing the
-- threat (not cover from it), grey = hit nothing.
local RAY_COLORS = { [0] = Color(120, 120, 120, 120), Color(80, 255, 100), Color(255, 150, 40) }

local GREY, YELLOW, BLUE = Color(140, 140, 140), Color(255, 220, 60), Color(80, 140, 255)

hook.Add("PostDrawTranslucentRenderables", "tif_debug_cover", function(depth, sky)
	if sky or RealTime() - coverTime > 1.5 then return end
	local me = LocalPlayer():GetPos()
	local eyeAng = EyeAngles()
	local textAng = Angle(0, eyeAng.y - 90, 90)
	for _, r in ipairs(coverRays or {}) do
		render.DrawLine(r.a, r.b, RAY_COLORS[r.kind] or WHITE, true)
	end
	for _, p in ipairs(coverPts) do
		local bad = p.reject ~= "" and p.reject ~= "taken" and p.reject ~= "too far"
		local col = p.reserved and BLUE or (bad and GREY or (p.canShoot and GREEN or YELLOW))
		local h = p.high and 72 or 40
		render.DrawWireframeBox(p.pos, angle_zero, Vector(-4, -4, 0), Vector(4, 4, h), col, true)
		if p.ny then
			local n = Vector(math.cos(math.rad(p.ny)), math.sin(math.rad(p.ny)), 0)
			render.DrawLine(p.pos + Vector(0, 0, 20), p.pos + Vector(0, 0, 20) - n * 20, col, true)
			-- side = wall normal rotated +90 = the "r" lean direction.
			local side = Vector(-n.y, n.x, 0)
			if p.edgeR then render.DrawLine(p.pos + Vector(0, 0, h), p.pos + Vector(0, 0, h) + side * 14, col, true) end
			if p.edgeL then render.DrawLine(p.pos + Vector(0, 0, h), p.pos + Vector(0, 0, h) - side * 14, col, true) end
		end
		if p.pos:DistToSqr(me) < 700 * 700 then
			cam.Start3D2D(p.pos + Vector(0, 0, h + 10), textAng, 0.08)
				local t1 = bad and p.reject or string.format("%s %s  %.1f", p.high and "HIGH" or "LOW", p.canShoot and "shoot" or "hide", p.score)
				draw.SimpleTextOutlined(t1, "TIFDebug3D", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, color_black)
				if not bad and p.why ~= "" then
					draw.SimpleTextOutlined(p.why, "TIFDebug3D", 0, 26, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, color_black)
				end
			cam.End3D2D()
		end
	end
end)

-- Client animation stats, per second.
local clRate = { overwritten = 0, missing = 0, solveUs = 0 }
local lastStats = {}
timer.Create("tif_debug_clstats", 1, 0, function()
	local s = Bd and Bd.Stats
	if not s then return end
	local checks = s.checks - (lastStats.checks or 0)
	local over = s.overwritten - (lastStats.overwritten or 0)
	clRate.overwritten = checks > 0 and over / checks or 0
	clRate.missing = s.missingSlots - (lastStats.missingSlots or 0)
	local c = TIF.Prof.Last.counts
	clRate.solveUs = (c.cl_solves or 0) > 0 and (c.cl_solve_us or 0) / c.cl_solves or 0
	clRate.solves = c.cl_solves or 0
	lastStats = { checks = s.checks, overwritten = s.overwritten, missingSlots = s.missingSlots }
end)
TIF.DebugClientRates = clRate

hook.Add("HUDPaint", "tif_debug", function()
	if not live() then return end
	local x, y = 20, ScrH() * 0.25
	local lines = { "TIF debug  (tif_debug 0 to hide)" }
	local counts = {}
	for _, s in ipairs(data.soldiers) do
		local ent = Entity(s.idx)
		if IsValid(ent) and ent.TIFSoldier then
			local a = ent:GetTIFAware()
			counts[a] = (counts[a] or 0) + 1
		end
	end
	local aw = {}
	for i = 0, 4 do aw[#aw + 1] = TIF.AWARE_NAMES[i] .. " " .. (counts[i] or 0) end
	lines[#lines + 1] = string.format("soldiers %d  |  %s", #data.soldiers, table.concat(aw, ", "))
	lines[#lines + 1] = "server ms/s (worst call ms):"
	local tick = data.tickrate > 0 and data.tickrate or 66
	local totalMs = 0
	for _, k in ipairs(TIME_KEYS) do
		local t = data.times[k]
		lines[#lines + 1] = string.format("  %-11s %7.2f  (%.2f)", k, t.ms, t.max)
		-- perception and brain run inside sched, so they aren't added again.
		if k == "sched" or k == "tick" or k == "events" or k == "path" or k == "suppression" then totalMs = totalMs + t.ms end
	end
	lines[#lines + 1] = string.format("  = %.3f ms per tick at %d ticks/s", totalMs / tick, tick)
	local c = data.counts
	lines[#lines + 1] = string.format("thinks/s %d  traces/s %d (denied %d)  paths/s %d (denied %d)  over budget %d",
		c.thinks, c.trace, c.trace_denied, c.path, c.path_denied, c.sched_over_budget)
	lines[#lines + 1] = string.format("layer slots: rebuilt by server %.1f/s, client refresh requests %.1f/s",
		c.slots_rebuilt, c.slots_refresh_requests)
	local cl = TIF.Prof.Last.times.cl_anim
	lines[#lines + 1] = string.format("client: anim %.2f ms/s  solve %.1f us x %d/s  overwritten %.0f%%  soldiers missing slots now %d  fps %d",
		cl and cl.ms or 0, clRate.solveUs, clRate.solves or 0, clRate.overwritten * 100, Bd.Stats.missingNow or 0, math.floor(1 / math.max(FrameTime(), 0.0001)))
	for i, l in ipairs(lines) do
		draw.SimpleTextOutlined(l, "TIFDebugHUD", x, y + (i - 1) * 17, i == 1 and Color(120, 200, 255) or WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
	end
end)


-- tif_aimwhy (server, sv_commands) asks for this: the leg / upper-body clips and the spine bend the client draws.
concommand.Add("tif_aimwhy_cl", function(_, _, args)
	local ent = args[1] and Entity(tonumber(args[1]) or -1) or LocalPlayer():GetEyeTrace().Entity
	local st = IsValid(ent) and TIF.Body and TIF.Body.State and TIF.Body.State(ent)
	if not st then MsgN("tif_aimwhy_cl: no body state") return end
	local L = { "  client: pitch " .. string.format("%.1f", st.pitch or 0) .. " | fullBody " .. tostring(st.fullBody)
		.. " | cqbMode " .. tostring(st.cqbMode) .. " | alertPosture " .. tostring(st.alertPosture) .. " | pistol " .. tostring(st.pistol)
		.. " | wkind " .. tostring(st.wkind) .. " | wade " .. tostring(st.wade) .. " | light " .. tostring(st.light) }
	local function dump(label, w)
		local list = {}
		for clip, v in pairs(w or {}) do list[#list + 1] = { n = tostring(clip.from or clip.seq or "?"), w = v } end
		table.sort(list, function(a, b) return a.w > b.w end)
		for i = 1, math.min(4, #list) do L[#L + 1] = string.format("  %s %.2f %s", label, list[i].w, list[i].n) end
	end
	dump("legs", st.legW)
	dump("ub  ", st.ubW)
	for _, b in ipairs({ "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4" }) do
		local i = ent:LookupBone(b)
		if i then L[#L + 1] = "  " .. b .. " manip " .. tostring(ent:GetManipulateBoneAngles(i)) end
	end
	-- Host skeleton vs the faction model drawn over it (retargeted CoD-rest models can differ): the hands' line
	-- (right -> left hand, where the gun lies) and the chest, as pitch relative to the soldier (+ = down).
	local yaw = ent:GetAngles().y
	local function rel_pitch(v)
		local l = WorldToLocal(v, angle_zero, vector_origin, Angle(0, yaw, 0))
		return -math.deg(math.atan2(l.z, math.max(0.001, math.sqrt(l.x * l.x + l.y * l.y))))
	end
	local function report(label, e)
		if not IsValid(e) then return end
		e:SetupBones()
		local function pos(n) local i = e:LookupBone(n) local m = i and e:GetBoneMatrix(i) return m and m:GetTranslation() end
		local r, l = pos("ValveBiped.Bip01_R_Hand"), pos("ValveBiped.Bip01_L_Hand")
		local s1, s4, nk = pos("ValveBiped.Bip01_Spine1") or pos("ValveBiped.Bip01_Spine"), pos("ValveBiped.Bip01_Spine4"), pos("ValveBiped.Bip01_Neck1")
		-- chest: the spine1 -> neck line's pitch (-90 = upright; -80 = leaning 10 deg forward, -100 = 10 back)
		L[#L + 1] = string.format("  %s %s | hands line %s | chest %s", label, e:GetModel(),
			(r and l) and string.format("%+.1f", rel_pitch(l - r)) or "?",
			(s1 and nk) and string.format("%+.1f", rel_pitch(nk - s1)) or "?")
		if r then L[#L + 1] = string.format("    R hand %s  L hand %s", tostring(r and (r - ent:GetPos())), tostring(l and (l - ent:GetPos()))) end
	end
	report("host    ", ent)
	report("faction ", st.follower)
	L[#L + 1] = "  faction retargeted: " .. tostring(IsValid(st.follower) and TIF.Modular and TIF.Modular.NeedsRetarget
		and TIF.Modular.NeedsRetarget(st.follower:GetModel()) or false) .. " | parts '" .. ent:GetNW2String("tif_parts", "") .. "'"
	if IsValid(st.gun) then
		L[#L + 1] = string.format("  gun %s pitch %+.1f (+ = down) | jrotW %.2f jgunW %.2f", st.gun:GetModel(),
			rel_pitch(st.gun:GetForward()), st.jrotW or -1, st.jgunW or -1)
	end
	-- The gun-bone tables (tif_mw_anims zz_jgun.lua): without them every clip holds the gun in the hand's frame.
	local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
	L[#L + 1] = string.format("  client tables: TIFG_JGUN_UNDRIVEN %s (%d)  TIFG_JGUN_HOLD %s (%d)",
		type(TIFG_JGUN_UNDRIVEN), count(TIFG_JGUN_UNDRIVEN), type(TIFG_JGUN_HOLD), count(TIFG_JGUN_HOLD))
	local topClip, topW
	for clip, v in pairs(st.legW or {}) do if not topW or v > topW then topClip, topW = clip, v end end
	if topClip then
		local src = topClip.from or topClip.seq or "?"
		L[#L + 1] = string.format("  top leg clip %s: undriven %s, hold entry %s", src,
			tostring(TIFG_JGUN_UNDRIVEN and TIFG_JGUN_UNDRIVEN[src] or false), tostring(TIFG_JGUN_HOLD and TIFG_JGUN_HOLD[src] ~= nil or false))
	end
	for _, s in ipairs(L) do MsgN(s) end
	file.CreateDir("tif/reports")
	file.Append("tif/reports/aimwhy.txt", table.concat(L, "\n") .. "\n")
end)
