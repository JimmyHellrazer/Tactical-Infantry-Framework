-- Debug snapshot sender. Off by default; when tif_debug is 0 the only cost is one convar check
-- every 0.2 s. Only sent to the server console's listen host and superadmins.

local TIF = TIF
util.AddNetworkString("tif_debug")

local cvDebug = CreateConVar("tif_debug", "0", FCVAR_ARCHIVE, "Send TIF AI debug overlays to admins (1/0)")
local cvPaths = CreateConVar("tif_debug_paths", "1", FCVAR_ARCHIVE, "Include movement paths in the debug overlay")

local MAX_SOLDIERS = 80
local MAX_PATH_POINTS = 10
local TIME_KEYS = { "sched", "perception", "brain", "path", "tick", "events", "cover", "cover_behave", "suppression" }
local COUNT_KEYS = { "thinks", "trace", "trace_denied", "path", "path_denied", "sched_over_budget", "slots_rebuilt", "slots_refresh_requests",
	"cover_searches", "cover_traces", "cover_cache_hits" }

util.AddNetworkString("tif_debug_cover")
local cvCover = CreateConVar("tif_debug_cover", "0", FCVAR_ARCHIVE, "Show evaluated cover points in the debug overlay")

-- Cover points evaluated in the last 12 s near each viewer.
timer.Create("tif_debug_cover_send", 0.5, 0, function()
	if not (cvDebug:GetBool() and cvCover:GetBool()) then return end
	local now = CurTime()
	for _, ply in player.Iterator() do
		if TIF.CanUseDev(ply) then
			local me = ply:GetPos()
			local list = {}
			for _, pt in ipairs(TIF.Cover.Recent) do
				local p = pt.pos or pt.probe
				if now - pt.time < 12 and p:DistToSqr(me) < 3500 * 3500 then list[#list + 1] = pt end
			end
			local n = math.min(#list, 120)
			net.Start("tif_debug_cover")
			net.WriteUInt(n, 8)
			for i = #list - n + 1, #list do
				local pt = list[i]
				local reserved = pt.key and TIF.Cover.Reserved[pt.key]
				net.WriteVector(pt.pos or pt.probe)
				net.WriteBool(pt.normal ~= nil)
				if pt.normal then net.WriteFloat(pt.ny) end
				net.WriteString(pt.reject or pt.lastReject or "")
				net.WriteBool(pt.high == true)
				net.WriteBool(pt.edgeL == true)
				net.WriteBool(pt.edgeR == true)
				net.WriteBool(pt.canShoot == true)
				net.WriteBool(reserved ~= nil)
				net.WriteFloat(pt.score or -99)
				net.WriteString(pt.why or "")
				net.WriteString(pt.material or "")
			end
			local rays = {}
			for _, r in ipairs(TIF.Cover.RecentRays) do
				if now - r.time < 6 and r.a:DistToSqr(me) < 3500 * 3500 then rays[#rays + 1] = r end
			end
			local nr = math.min(#rays, 200)
			net.WriteUInt(nr, 8)
			for i = #rays - nr + 1, #rays do
				local r = rays[i]
				net.WriteVector(r.a)
				net.WriteVector(r.b)
				net.WriteUInt(r.kind, 2)
			end
			net.Send(ply)
		end
	end
end)

local function path_points(npc)
	local p = npc.tifPath
	if not (p and p:IsValid()) then return nil end
	local segs = p:GetAllSegments()
	local n = #segs
	if n == 0 then return nil end
	local out = {}
	local step = math.max(1, math.ceil(n / MAX_PATH_POINTS))
	for i = 1, n, step do out[#out + 1] = segs[i].pos end
	if out[#out] ~= segs[n].pos and #out < MAX_PATH_POINTS + 1 then out[#out + 1] = segs[n].pos end
	return out
end

local function best_meter(npc)
	local m = 0
	for _, c in pairs(npc.tifK and npc.tifK.contacts or {}) do
		if not c.confirmed and c.meter > m then m = c.meter end
	end
	return m
end

timer.Create("tif_debug_send", 0.2, 0, function()
	if not cvDebug:GetBool() then return end
	local viewers = {}
	for _, ply in player.Iterator() do if TIF.CanUseDev(ply) then viewers[#viewers + 1] = ply end end
	if #viewers == 0 then return end
	local now = CurTime()
	local last = TIF.Prof.Last
	local withPaths = cvPaths:GetBool()

	net.Start("tif_debug")
	for _, k in ipairs(TIME_KEYS) do
		local t = last.times[k]
		net.WriteFloat(t and t.ms or 0)
		net.WriteFloat(t and t.max or 0)
	end
	for _, k in ipairs(COUNT_KEYS) do net.WriteFloat(last.counts[k] or 0) end
	net.WriteFloat(1 / engine.TickInterval())

	local list = TIF.Soldiers
	local n = math.min(#list, MAX_SOLDIERS)
	net.WriteUInt(n, 8)
	for i = 1, n do
		local npc = list[i]
		local ok = IsValid(npc) and npc.tifK ~= nil
		net.WriteBool(ok)
		if ok then
			net.WriteUInt(npc:EntIndex(), 13)
			net.WriteUInt(npc.tifTier or 0, 2)
			net.WriteUInt(math.Clamp(npc:Health(), 0, 1023), 10)
			local w = npc.tifWep
			net.WriteUInt(math.Clamp(w and w.ammo or 0, 0, 255), 8)
			net.WriteUInt(math.Clamp(w and w.clip or 0, 0, 255), 8)
			net.WriteString(npc.tifAction or "")
			net.WriteString(npc.tifArchId or "")
			net.WriteFloat(npc.tifThinkMs or 0)
			net.WriteUInt(math.floor(best_meter(npc) * 255), 8)
			net.WriteBool(npc.tifFire and npc.tifFire.want == true)
			net.WriteUInt(math.floor(math.Clamp(npc.tifSupp or 0, 0, 1) * 255), 8)
			local c = npc.tifPrimaryC
			net.WriteBool(c ~= nil)
			if c then
				net.WriteVector(c.pos)
				net.WriteBool(c.visible)
				net.WriteFloat(now - math.max(c.seenAt, c.heardAt))
				net.WriteFloat(c.unc or 0)
				net.WriteString(c.source or "")
			end
			local goal = npc.tifMove and npc.tifMove.goal
			net.WriteBool(goal ~= nil)
			if goal then net.WriteVector(goal) end
			local pts = withPaths and path_points(npc) or nil
			net.WriteUInt(pts and #pts or 0, 4)
			for _, p in ipairs(pts or {}) do net.WriteVector(p) end
		end
	end

	local ev = TIF.Events.Recent
	local recent = {}
	for _, e in ipairs(ev) do if now - e.time < 3 then recent[#recent + 1] = e end end
	net.WriteUInt(math.min(#recent, 31), 5)
	for i = 1, math.min(#recent, 31) do
		local e = recent[i]
		net.WriteString(e.kind)
		net.WriteVector(e.pos)
		net.WriteFloat(e.radius)
		net.WriteFloat(now - e.time)
	end
	net.Send(viewers)
end)
