local TIF = TIF
local AW = TIF.AWARE
local SQ = TIF.Squad

TIF.Base = TIF.Base or {}
local B = TIF.Base
B.List = B.List or {}
B.NextId = B.NextId or 1

B.CALM, B.ALERT, B.ALARM = 0, 1, 2
B.LEVEL_NAMES = { [0] = "calm", [1] = "alert", [2] = "alarm" }

B.POST_LEASH = 420
B.RESERVE_LEASH = 260
B.ALARM_DELAY = { 1.5, 3 }
B.ALARM_QUIET = 25
B.ALERT_QUIET = 90
B.REINFORCE_DELAY = { 12, 20 }
B.REINFORCE_LOSSES = 0.6

local REINFORCE_MIX = { "leader", "rifleman", "support", "rpg", "assault", "marksman", "rifleman", "assault" }
local RESERVE_MIX = { "leader", "rifleman", "assault", "rifleman", "support", "rifleman", "assault", "marksman" }

function B.Log(base, ...)
	local cv = GetConVar("tif_debug")
	if cv and cv:GetBool() then
		TIF.Log("[base ", base.name, "] ", table.concat({ ... }, ""))
	end
end

local function spawn_one(faction, arch, pos, yaw)

	local p = TIF.FreeSpot(TIF.Move.Snap(pos) or pos)
	local ent = ents.Create("tif_soldier_" .. faction)
	if not IsValid(ent) then
		ent = ents.Create("tif_soldier")
		if IsValid(ent) then
			ent.tifSpawnFaction = faction
		end
	end

	if not IsValid(ent) then return nil end
	ent.tifArchId = TIF.Archetypes[arch or ""] and arch or "rifleman"
	ent.tifNoAutoSquad = true
	ent:SetPos(p + Vector(0, 0, 4))
	ent:SetAngles(Angle(0, yaw or 0, 0))
	ent:Spawn()
	ent:Activate()
	return ent
end

local function set_job(base, npc, job)
	npc.tifBase, npc.tifJob = base, job
	npc:SetNW2String("tif_job", base.name .. ": " .. job)
	base.members[#base.members + 1] = npc
end

local function squads(base)
	local out = {}
	for _, sq in pairs(base.squads) do
		if SQ.List[sq.id] then
			out[#out + 1] = sq
		end
	end

	return out
end
B.Squads = squads

B.SPAWN_PER_TICK = 2
B.Building = B.Building or {}

local function planned(def)
	local n = 0
	for _, p in ipairs(def.posts or {}) do
		local j = p.job or "post"
		if j == "post" or j == "reserve" then
			n = n + 1
		end
	end

	for _, r in ipairs(def.routes or {}) do
		if r.pts and #r.pts >= 2 then
			n = n + math.max(1, r.size or 3)
		end
	end

	for _, vp in ipairs(def.vpatrols or {}) do
		if vp.pts and #vp.pts >= 2 then
			n = n + math.Clamp(vp.size or 4, 1, 8)
		end
	end

	for _, cd in ipairs(def.convoys or {}) do
		if cd.pts and #cd.pts >= 2 then
			n = n + math.Clamp(cd.count or 2, 1, 6) * math.Clamp(cd.size or 4, 1, 8)
		end
	end

	return n
end

local build

function B.Garrison(def)
	local base = {
		id = B.NextId, name = def.name or ("base" .. B.NextId), faction = def.faction or "insurgents",
		center = Vector(def.center), radius = def.radius or 1800, def = def,
		members = {}, squads = {}, knowledge = {},
		level = B.CALM, levelSince = CurTime(), quietSince = CurTime(),
	}
	B.NextId = B.NextId + 1
	base.pending = planned(def)
	base.startSize = base.pending
	B.List[base.id] = base
	local co = coroutine.create(build)
	local ok, err = coroutine.resume(co, base, def)
	if not ok then
		base.pending = 0
		TIF.Error("Base '", base.name, "' garrison: ", tostring(err))
	elseif coroutine.status(co) ~= "dead" then
		B.Building[base] = co
	end

	return base
end

hook.Add("Tick", "tif_base_build", function()
	local base, co = next(B.Building)
	if not base then return end
	local ok, err = coroutine.resume(co)
	if not ok then
		base.pending = 0
		TIF.Error("Base '", base.name, "' garrison: ", tostring(err))
	end

	if not ok or coroutine.status(co) == "dead" then
		B.Building[base] = nil
	end
end)

build = function(base, def)
	local f = base.faction
	local made = 0
	local raw = spawn_one

	local function spawn_one(fac, arch, pos, yaw)
		if made >= B.SPAWN_PER_TICK then
			coroutine.yield()
			made = 0
		end
		made = made + 1
		base.pending = math.max(0, base.pending - 1)
		return raw(fac, arch, pos, yaw)
	end

	local guards = {}
	for _, p in ipairs(def.posts or {}) do
		if (p.job or "post") == "post" then
			local npc = spawn_one(f, p.arch, p.pos, p.yaw)
			if npc then
				npc.tifGuardPost = { pos = TIF.Move.Snap(p.pos) or p.pos, yaw = p.yaw or 0 }
				npc.tifLeash = { pos = npc.tifGuardPost.pos, radius = B.POST_LEASH }
				set_job(base, npc, "post")
				guards[#guards + 1] = npc
			end
		end
	end

	if #guards > 0 then
		local sq = SQ.Create(f, guards)
		sq.static = true
		base.squads.guard = sq
	end

	local reserve = {}
	for _, p in ipairs(def.posts or {}) do
		if p.job == "reserve" then
			local npc = spawn_one(f, p.arch or RESERVE_MIX[#reserve + 1], p.pos, p.yaw)
			if npc then
				npc.tifGuardPost = { pos = TIF.Move.Snap(p.pos) or p.pos, yaw = p.yaw or 0 }
				npc.tifLeash = { pos = npc.tifGuardPost.pos, radius = B.RESERVE_LEASH }
				set_job(base, npc, "reserve")
				reserve[#reserve + 1] = npc
			end
		end
	end

	if #reserve > 0 then
		local leader = reserve[1]
		for _, e in ipairs(reserve) do if e.tifArchId == "leader" then leader = e break end end
		local sq = SQ.Create(f, reserve, leader)
		sq.static = true
		base.squads.reserve = sq
	end

	for ri, r in ipairs(def.routes or {}) do
		if r.pts and #r.pts >= 2 then
			local list = {}
			for i = 1, math.max(1, r.size or 3) do
				local off = Vector(-60 * (i - 1), 0, 0)
				local npc = spawn_one(f, (r.archs and r.archs[i]) or (i == 1 and "leader" or "rifleman"), r.pts[1] + off, 0)
				if npc then
					set_job(base, npc, "patrol " .. ri)
					list[#list + 1] = npc
				end
			end
			if #list > 0 then
				local sq = SQ.Create(f, list, list[1])
				local route = {}
				for i, p in ipairs(r.pts) do
					route[i] = TIF.Move.Snap(p) or p
				end
				SQ.SetOrder(sq, "patrol")
				sq.order.route = route
				sq.formation = #list > 2 and "file" or "column"
				SQ.Publish(sq)
				base.squads["patrol" .. ri] = sq
			end
		end
	end

	for vi, vp in ipairs(def.vpatrols or {}) do
		if TIF.Mounted and vp.pts and #vp.pts >= 2 then
			local p1, p2 = vp.pts[1], vp.pts[2]
			local veh, err = TIF.Mounted.SpawnVehicle(vp.class, p1, (p2 - p1):Angle().y)
			if veh then
				local crew = {}
				local dir = (p2 - p1):GetNormalized()
				local side = Vector(-dir.y, dir.x, 0)
				for i = 1, math.Clamp(vp.size or 4, 1, 8) do
					local npc = spawn_one(f, (vp.archs and vp.archs[i]) or (i == 2 and "leader" or "rifleman"),
						p1 - dir * 200 + side * (i - 2.5) * 55, 0)
					if npc then
						set_job(base, npc, "vehicle patrol " .. vi)
						crew[#crew + 1] = npc
					end
				end
				if #crew > 0 then
					local leader = crew[2] or crew[1]
					local sq = SQ.Create(f, crew, leader)
					base.squads["vpatrol" .. vi] = sq
					base.vehicles = base.vehicles or {}
					base.vehicles[#base.vehicles + 1] = veh
					local route = {}
					for i, p in ipairs(vp.pts) do
						route[i] = TIF.Move.Snap(p) or p
					end

					timer.Simple(0.5, function()
						if SQ.List[sq.id] and IsValid(veh) then
							TIF.Mounted.Mount(sq, veh)
							TIF.Mounted.Patrol(sq, route)
						end
					end)
				end
			else
				TIF.Warn("Base '", base.name, "' vehicle patrol: ", tostring(err))
			end
		end
	end

	for ci, cd in ipairs(def.convoys or {}) do
		if TIF.Convoy and cd.pts and #cd.pts >= 2 then
			local p1, p2 = cd.pts[1], cd.pts[2]
			local dir = (p2 - p1):GetNormalized()
			local side = Vector(-dir.y, dir.x, 0)
			local pairs_ = {}
			for k = 1, math.Clamp(cd.count or 2, 1, 6) do
				local at = p1 - dir * (k - 1) * 480
				local veh, err = TIF.Mounted.SpawnVehicle(cd.class or TIF.Mounted.DefaultCar(), at, dir:Angle().y)
				if veh then
					base.vehicles = base.vehicles or {}
					base.vehicles[#base.vehicles + 1] = veh
					local crew = {}
					for i = 1, math.Clamp(cd.size or 4, 1, 8) do
						local npc = spawn_one(f, (cd.archs and cd.archs[i]) or (i == 2 and "leader" or (i == 4 and "rpg" or "rifleman")),
							at + side * 170 + dir * (i - 2.5) * 50, 0)
						if npc then
							set_job(base, npc, "convoy " .. ci)
							crew[#crew + 1] = npc
						end
					end
					if #crew > 0 then
						local sq = SQ.Create(f, crew, crew[2] or crew[1])
						base.squads["convoy" .. ci .. "_" .. k] = sq
						pairs_[#pairs_ + 1] = { sq = sq, veh = veh }
					end
				else
					TIF.Warn("Base '", base.name, "' convoy: ", tostring(err))
				end
			end
			local route = {}
			for i, p in ipairs(cd.pts) do
				route[i] = TIF.Move.Snap(p) or p
			end
			timer.Simple(0.6, function()
				local list = {}
				for _, pr in ipairs(pairs_) do
					if SQ.List[pr.sq.id] and IsValid(pr.veh) then
						TIF.Mounted.Mount(pr.sq, pr.veh)
						list[#list + 1] = pr.sq
					end
				end
				local cv = TIF.Convoy.Create(list)
				if cv then
					TIF.Convoy.Patrol(cv, route)
				end
			end)
		end
	end

	base.pending = 0
	base.startSize = #base.members
	TIF.Log("Base '", base.name, "' garrisoned: ", base.startSize, " soldiers (", #guards, " on posts, ",
		#reserve, " reserve, ", #(def.routes or {}), " patrol(s))")
end

function B.Remove(base)

	B.Building[base] = nil
	base.pending = 0
	for _, m in ipairs(base.members) do if IsValid(m) then m:Remove() end end
	for _, v in ipairs(base.vehicles or {}) do if IsValid(v) then v:Remove() end end
	B.List[base.id] = nil
end

local function set_level(base, level, now, why)
	if base.level == level then return end
	B.Log(base, string.upper(B.LEVEL_NAMES[level]), " (", why or "", ")")
	base.level, base.levelSince, base.quietSince = level, now, now

	hook.Run("TIF_BaseLevel", base, B.LEVEL_NAMES[level], why)
end
B.SetLevel = set_level

local function share(base, now)
	for _, sq in ipairs(squads(base)) do
		for ent, bk in pairs(base.knowledge) do
			local k = sq.knowledge[ent]
			if not k or bk.time > k.time + 0.5 then
				sq.knowledge[ent] = { pos = Vector(bk.pos), vel = Vector(bk.vel), time = bk.time, visible = false }
			end
		end
	end
end

local function newest(base)
	local best
	for ent, k in pairs(base.knowledge) do
		if not best or k.time > best.time then
			best = k
		end
	end

	return best
end

local function dispatch_reserve(base, now)
	local sq = base.squads.reserve
	if not sq or not sq.static or not SQ.List[sq.id] then return end
	sq.static = false
	for _, m in ipairs(SQ.Members(sq)) do
		m.tifLeash = nil
	end

	B.Log(base, "reserve sent out (", #SQ.Members(sq), ")")
	local m = SQ.Members(sq)[1]
	if m then
		TIF.Say(m, "moving", 0.9)
	end
end

local function raise_alarm(base, now)
	set_level(base, B.ALARM, now, "contact")
	if IsValid(base.alarmBy) then
		TIF.Say(base.alarmBy, "backup", 1)
	end

	share(base, now)
	dispatch_reserve(base, now)
end

function B.Adopt(base, sq, job)
	if not (base and sq and SQ.List[sq.id]) then return 0 end
	local n = 0
	for _, m in ipairs(SQ.Members(sq)) do
		if IsValid(m) and not m.tifDead then
			set_job(base, m, job or "reinforcement")
			n = n + 1
		end
	end

	base.adopted = (base.adopted or 0) + 1
	base.squads["adopted" .. base.adopted] = sq
	share(base, CurTime())
	B.Log(base, "adopted a squad of ", n, " (", job or "reinforcement", ")")
	return n
end

local function watched(pos)
	local tr = { mask = MASK_SOLID_BRUSHONLY }
	for _, ply in player.Iterator() do
		if ply:Alive() then
			local eye = ply:EyePos()
			if eye:DistToSqr(pos) < 1500 * 1500 then return true end
			tr.start, tr.endpos = eye, pos + Vector(0, 0, 60)
			if not util.TraceLine(tr).Hit and eye:DistToSqr(pos) < 3000 * 3000 then
				return true
			end
		end
	end

	return false
end

local function maybe_reinforce(base, now)
	local r = base.def.reinforce
	if not r or base.reinforced then return end
	local losses = #base.members + (base.pending or 0) <= base.startSize * B.REINFORCE_LOSSES
	if not base.reinforceAt then
		if losses or now - base.levelSince > 45 then
			base.reinforceAt = now + math.Rand(B.REINFORCE_DELAY[1], B.REINFORCE_DELAY[2])
			B.Log(base, "reinforcements requested")
			local m = base.members[1]
			if IsValid(m) then
				TIF.Say(m, "backup", 0.8)
			end
		end
		return
	end

	if now < base.reinforceAt then return end
	if watched(r.pos) then
		base.reinforceAt = now + 3
		return
	end

	local size = math.Clamp(r.size or 6, 2, 8)
	local mix = {}
	for i = 1, size do
		mix[i] = REINFORCE_MIX[i]
	end

	local out = TIF.SpawnSoldiers(nil, base.faction, size, nil, r.pos, base.center, { archetypes = mix, radius = 200 })
	base.reinforced = true
	for _, npc in ipairs(out) do
		set_job(base, npc, "reinforcement")
	end

	if out[1] and out[1].tifSquad then
		base.squads.reinforce = out[1].tifSquad
	end
	share(base, now)
	B.Log(base, "reinforcements arrived (", #out, ")")
end

local function sweep(base, now)
	local k = newest(base)
	if not k then return end
	local sq = base.squads.reserve
	if not sq or not SQ.List[sq.id] or #SQ.Members(sq) == 0 then
		sq = base.squads.reinforce
	end

	if not sq or not SQ.List[sq.id] then return end
	local dir = k.vel and k.vel:Length2D() > 30 and Vector(k.vel.x, k.vel.y, 0):GetNormalized() or nil
	for _, m in ipairs(SQ.Members(sq)) do
		if m.tifAware ~= AW.ENGAGED then
			TIF.Brain.StartSearch(m, k.pos, dir, now)
		end
	end

	B.Log(base, "sweep of the last known position by squad ", sq.id)
end

local function stand_down(base, now)
	local sq = base.squads.reserve
	if sq and SQ.List[sq.id] then
		sq.static = true
		for _, m in ipairs(SQ.Members(sq)) do
			if m.tifGuardPost then
				m.tifLeash = { pos = m.tifGuardPost.pos, radius = B.RESERVE_LEASH }
			end
		end
	end

	for _, s in ipairs(squads(base)) do
		if s.order.kind == "patrol" then
			s.order.i = nil
		end

		local mt = s.mount
		if mt and mt.phase == "dismounted" and mt.patrol and TIF.Mounted then
			TIF.Mounted.Remount(s)
		end
	end

	base.knowledge = {}
	base.reinforced, base.reinforceAt = false, nil
end

local function tick(base, now)

	local alive = {}
	for _, m in ipairs(base.members) do
		if IsValid(m) and not m.tifDead then
			alive[#alive + 1] = m
		end
	end

	local lost = #base.members - #alive
	base.members = alive
	if #alive == 0 then
		B.Log(base, "wiped out")
		B.List[base.id] = nil
		return
	end

	local engaged, busy, suspicious
	for _, m in ipairs(alive) do
		local a = m.tifAware
		if a == AW.ENGAGED then
			engaged = engaged or m
		end
		if a == AW.ENGAGED or a == AW.ALERTED or a == AW.SEARCHING then
			busy = true
		end
		if a == AW.SUSPICIOUS then
			suspicious = true
		end
	end

	for _, sq in ipairs(squads(base)) do
		for ent, k in pairs(sq.knowledge) do
			local bk = base.knowledge[ent]
			if not bk or k.time > bk.time then
				base.knowledge[ent] = { pos = Vector(k.pos), vel = Vector(k.vel or vector_origin), time = k.time }
			end
		end
	end

	for ent in pairs(base.knowledge) do
		if not TIF.IsLiveCombatant(ent) then
			base.knowledge[ent] = nil
		end
	end

	if busy or suspicious then
		base.quietSince = now
	end

	if base.level < B.ALERT and (suspicious or busy or lost > 0) then
		set_level(base, B.ALERT, now, lost > 0 and "lost a man" or (busy and "contact" or "suspicious"))
	end
	if engaged and base.level < B.ALARM and not base.alarmAt then
		base.alarmAt = now + math.Rand(B.ALARM_DELAY[1], B.ALARM_DELAY[2])
		base.alarmBy = engaged
	end

	if base.alarmAt and now >= base.alarmAt then
		base.alarmAt = nil
		raise_alarm(base, now)
	end

	if base.level == B.ALARM then
		share(base, now)
		maybe_reinforce(base, now)
		if engaged then
			base.lastFight = now
		end
		local k = newest(base)
		if now - (base.lastFight or base.levelSince) > B.ALARM_QUIET and (not k or now - k.time > B.ALARM_QUIET) then
			set_level(base, B.ALERT, now, "contact lost")
			sweep(base, now)
		end
	elseif base.level == B.ALERT and now - base.quietSince > B.ALERT_QUIET then
		set_level(base, B.CALM, now, "all quiet")
		stand_down(base, now)
	end

	if base.level >= B.ALERT then
		for _, m in ipairs(alive) do
			m.tifHeightenedUntil = math.max(m.tifHeightenedUntil or 0, now + 10)
		end
	end
end

timer.Create("tif_base_tick", 0.5, 0, function()
	if TIF.AIDisabled() then return end
	local now = CurTime()
	for _, base in pairs(B.List) do
		local ok, err = pcall(tick, base, now)
		if not ok then
			TIF.Error("Base tick error: ", tostring(err))
		end
	end
end)

local function vec_out(v) return { math.Round(v.x, 1), math.Round(v.y, 1), math.Round(v.z, 1) } end

local function vec_in(t) return Vector(t[1], t[2], t[3]) end

function B.Serialize(def)
	local out = { name = def.name, faction = def.faction, center = vec_out(def.center), radius = def.radius, posts = {}, routes = {} }
	for i, p in ipairs(def.posts or {}) do
		out.posts[i] = { pos = vec_out(p.pos), yaw = math.Round(p.yaw or 0), job = p.job, arch = p.arch }
	end

	for i, r in ipairs(def.routes or {}) do
		local pts = {}
		for j, p in ipairs(r.pts) do
			pts[j] = vec_out(p)
		end
		out.routes[i] = { size = r.size, pts = pts }
	end

	if def.reinforce then
		out.reinforce = { pos = vec_out(def.reinforce.pos), size = def.reinforce.size }
	end
	return out
end

function B.Deserialize(t)
	local def = { name = t.name, faction = t.faction, center = vec_in(t.center), radius = t.radius, posts = {}, routes = {} }
	for i, p in ipairs(t.posts or {}) do
		def.posts[i] = { pos = vec_in(p.pos), yaw = p.yaw, job = p.job, arch = p.arch }
	end

	for i, r in ipairs(t.routes or {}) do
		local pts = {}
		for j, p in ipairs(r.pts) do
			pts[j] = vec_in(p)
		end
		def.routes[i] = { size = r.size, pts = pts }
	end

	if t.reinforce then
		def.reinforce = { pos = vec_in(t.reinforce.pos), size = t.reinforce.size }
	end
	return def
end

function B.SavedPath(name)
	return "tif/bases/" .. game.GetMap() .. "_" .. name .. ".json"
end

function B.Presets()
	local path = "tif/encounter/presets/" .. game.GetMap() .. ".lua"
	if not file.Exists(path, "LUA") then return {} end
	local ok, t = pcall(include, path)
	return ok and istable(t) and t or {}
end

function B.FindDef(name)
	if name then
		local raw = file.Read(B.SavedPath(name), "DATA")
		if raw then
			local t = util.JSONToTable(raw)
			if t then return B.Deserialize(t) end
		end
		return B.Presets()[name]
	end

	for _, def in pairs(B.Presets()) do
		return def
	end
	return nil
end

util.AddNetworkString("tif_debug_bases")

local function write_def(def, level, info)
	net.WriteString(def.name or "?")
	net.WriteInt(level, 3)
	net.WriteString(info or "")
	net.WriteVector(def.center)
	net.WriteFloat(def.radius or 0)
	local posts = def.posts or {}
	net.WriteUInt(math.min(#posts, 63), 6)
	for i = 1, math.min(#posts, 63) do
		local p = posts[i]
		net.WriteVector(p.pos)
		net.WriteFloat(p.yaw or 0)
		net.WriteBool(p.job == "reserve")
	end

	local routes = def.routes or {}
	net.WriteUInt(math.min(#routes, 15), 4)
	for i = 1, math.min(#routes, 15) do
		local pts = routes[i].pts or {}
		net.WriteUInt(math.min(#pts, 63), 6)
		for j = 1, math.min(#pts, 63) do
			net.WriteVector(pts[j])
		end
	end

	net.WriteBool(def.reinforce ~= nil)
	if def.reinforce then
		net.WriteVector(def.reinforce.pos)
	end
end

timer.Create("tif_debug_bases_send", 1, 0, function()
	local cv = GetConVar("tif_debug")
	if not cv or not cv:GetBool() then return end
	local viewers = {}
	for _, ply in player.Iterator() do if TIF.CanUseDev(ply) then viewers[#viewers + 1] = ply end end
	if #viewers == 0 then return end
	local now = CurTime()
	local list = {}
	for _, base in pairs(B.List) do
		list[#list + 1] = base
	end

	net.Start("tif_debug_bases")
	net.WriteUInt(math.min(#list, 7) + (B.Draft and 1 or 0), 4)
	for i = 1, math.min(#list, 7) do
		local base = list[i]
		local k = newest(base)
		local info = string.format("%d/%d alive  %ds in %s%s%s", #base.members, base.startSize, now - base.levelSince,
			B.LEVEL_NAMES[base.level], base.alarmAt and "  (alarm coming)" or "",
			base.reinforced and "  reinforced" or (base.reinforceAt and "  reinforcements called" or ""))
		write_def(base.def, base.level, info)
		net.WriteBool(k ~= nil)
		if k then
			net.WriteVector(k.pos)
		end
	end

	if B.Draft then
		write_def(B.Draft, -1, "draft (tif_base_save to keep)")
		net.WriteBool(false)
	end

	net.Send(viewers)
end)
