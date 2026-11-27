local TIF = TIF
TIF.Director = TIF.Director or {}
local D = TIF.Director

D.HUNT_EVERY = 3
D.STRAGGLE = 25
D.RECYCLE_EVERY = 2
D.INTENSITY_DECAY, D.INTENSITY_DROP = 0.93, 1
D.KILL_INTENSITY = 8
D.CLOSE_INTENSITY = 3
D.CLOSE_RANGE = 700
D.SURV_MORALE = 0.4
D.SURV_PREFER_PLAYERS = 800
D.SQUAD_ROLES = { "leader", "rifleman", "assault", "support", "rifleman", "marksman", "rpg", "assault" }
D.Intensity = D.Intensity or 0

local up56 = Vector(0, 0, 56)
local seenOut = {}
local seenTr = { mask = MASK_OPAQUE, output = seenOut }

function D.Players()
	local out = {}
	for _, ply in player.Iterator() do
		if IsValid(ply) and ply:Alive() and not (TIF.IgnorePlayers and TIF.IgnorePlayers()) then out[#out + 1] = ply end
	end
	return out
end

function D.Nearest(pos, players)
	local best, bestD
	for _, ply in ipairs(players or D.Players()) do
		local d = ply:GetPos():DistToSqr(pos)
		if not bestD or d < bestD then best, bestD = ply, d end
	end
	return best, bestD and math.sqrt(bestD) or math.huge
end

function D.SeenByPlayers(pos, near, players)
	near = near or 600
	local head = pos + up56
	for _, ply in ipairs(players or D.Players()) do
		local eye = ply:EyePos()
		local to = head - eye
		local dist = to:Length()
		if dist < near then return true end
		if dist > 1 and to:Dot(ply:GetAimVector()) / dist > 0.25 then
			seenTr.start, seenTr.endpos, seenTr.filter = eye, head, ply
			if not util.TraceLine(seenTr).Hit then return true end
		end
	end
	return false
end

local headings = setmetatable({}, { __mode = "k" })
timer.Create("tif_director_heading", 0.5, 0, function()
	for _, ply in player.Iterator() do
		local pos = ply:GetPos()
		local h = headings[ply] or {}
		headings[ply] = h
		if h.last then
			local moved = Vector(pos.x - h.last.x, pos.y - h.last.y, 0)
			if moved:LengthSqr() > 400 then
				moved:Normalize()
				h.dir = h.dir and (h.dir * 0.6 + moved * 0.4) or moved
				if h.dir:LengthSqr() > 0.01 then h.dir:Normalize() end
			end
		end
		h.last = pos
	end
end)

function D.Heading(ply)
	local h = headings[ply]
	if h and h.dir then return h.dir end
	local aim = ply:GetAimVector()
	aim.z = 0
	return aim:LengthSqr() > 0.01 and aim:GetNormalized() or nil
end

local areaCache, areaCacheAt = nil, -99
local function all_areas()
	local now = CurTime()
	if not areaCache or now - areaCacheAt > 60 then
		areaCache, areaCacheAt = {}, now
		for _, a in ipairs(navmesh.GetAllNavAreas() or {}) do
			if IsValid(a) and not a:IsUnderwater() and a:GetSizeX() >= 32 and a:GetSizeY() >= 32 then areaCache[#areaCache + 1] = a end
		end
	end
	return areaCache
end
D.Areas = all_areas

function D.FindSpawn(minD, maxD, opts)
	opts = opts or {}
	local players = D.Players()
	if #players == 0 then return nil end
	local areas = all_areas()
	if #areas == 0 then return nil end
	local found = {}
	local want = opts.ahead and 5 or 1
	for _ = 1, (opts.tries or 40) do
		local a = areas[math.random(#areas)]
		local p = a:GetCenter()
		local ply, dist = D.Nearest(p, players)
		if ply and dist >= minD and dist <= maxD and math.abs(p.z - ply:GetPos().z) < (opts.maxDz or 600)
			and not D.SeenByPlayers(p, minD * 0.6, players) then
			local far = true
			for _, q in ipairs(opts.avoid or {}) do
				if q:DistToSqr(p) < (opts.avoidR or 700) ^ 2 then far = false break end
			end
			if far then
				found[#found + 1] = { area = a, pos = p, ply = ply }
				if #found >= want then break end
			end
		end
	end
	if #found == 0 then return nil end
	local pick = found[math.random(#found)]
	if opts.ahead and #found > 1 then
		local best
		for _, f in ipairs(found) do
			local h = D.Heading(f.ply)
			local to = Vector(f.pos.x - f.ply:GetPos().x, f.pos.y - f.ply:GetPos().y, 0)
			local s = (h and to:LengthSqr() > 1) and to:GetNormalized():Dot(h) or 0
			if not best or s > best then pick, best = f, s end
		end
	end
	return pick.pos, pick.ply, pick.area
end

function D.HostileFaction(want)
	if want and want ~= "" and want ~= "auto" and want ~= "random" and TIF.Factions[TIF.FactionCanon(want)] then
		return TIF.FactionCanon(want)
	end
	local pf = TIF.PlayerFaction and TIF.PlayerFaction() or "usmc"
	local list = {}
	for id, def in pairs(TIF.Factions) do
		if not def.hidden and not def.alias and TIF.FactionRelation(id, pf) == TIF.REL_HOSTILE then list[#list + 1] = id end
	end
	table.sort(list)
	if #list == 0 then return nil end
	if want == "random" then return list[math.random(#list)] end
	for _, id in ipairs(list) do if id == "insurgents" then return id end end
	return list[1]
end

function D.SpawnSquad(faction, pos, size, faceAt)
	local roles = {}
	for i = 1, size do roles[i] = D.SQUAD_ROLES[(i - 1) % #D.SQUAD_ROLES + 1] end
	local yaw = faceAt and (faceAt - pos):Angle().y or math.Rand(-180, 180)
	local pts = TIF.FormationPoints and TIF.FormationPoints(pos, size, yaw) or nil
	local sq, out = TIF.API.SpawnSquad(faction, pos, roles, { face = faceAt or "random", points = pts })
	if pts then
		for _, e in ipairs(out) do if IsValid(e) then e:SetAngles(Angle(0, yaw, 0)) end end
	end
	return sq, out
end

function D.Alive(list)
	local n = 0
	for i = #list, 1, -1 do
		local e = list[i]
		if IsValid(e) and not e.tifDead then n = n + 1 else table.remove(list, i) end
	end
	return n
end

function D.Hunt(sq, now, players)
	if not sq or not sq.members then return end
	local members = TIF.Squad.Members(sq)
	if #members == 0 then return end
	local lead = sq.leader
	local ref = IsValid(lead) and lead:GetPos() or members[1]:GetPos()
	local ply = D.Nearest(ref, players)
	if not IsValid(ply) then return end
	local pos = ply:GetPos()
	TIF.API.SquadKnowsEnemy(sq, ply, pos)
	local P = TIF.Perception
	for _, m in ipairs(members) do
		if IsValid(m) and m.tifK and P and P.Contact then
			local c = P.Contact(m, ply)
			if not c.visible then
				c.confirmed = true
				c.pos = Vector(pos)
				c.vel = ply:GetVelocity()
				c.heardAt = now
				c.baseUnc = 48
				c.lostAt = c.lostAt or now
				c.source = "director"
				if P.Stimulus then P.Stimulus(m, c.pos, "callout", now) end
			end
		end
	end
	local fighting = (sq.lastContact or -99) > now - 4
	if not fighting then
		local o = sq.order
		if not (o and o.kind == "advance" and o.pos and o.pos:DistToSqr(pos) < 250 * 250) then
			TIF.API.SquadAdvance(sq, pos, { pace = "rush" })
		end
	end
end

function D.Recycle(list, now, maxD, onRemove, players)
	for i = #list, 1, -1 do
		local e = list[i]
		if IsValid(e) and not e.tifDead then
			local pos = e:GetPos()
			local _, dist = D.Nearest(pos, players)
			local engaged = e.tifAware == TIF.AWARE.ENGAGED
			local moved = e.tifDirLast and e.tifDirLast:DistToSqr(pos) > 64 * 64
			if moved or not e.tifDirLast then e.tifDirLast, e.tifDirProgress = pos, now end
			local stuck = e.tifHunter and now - (e.tifDirProgress or now) > D.STRAGGLE and not engaged
			if (dist > maxD and not engaged) or stuck then
				if not D.SeenByPlayers(pos, 900, players) then
					table.remove(list, i)
					e:Remove()
					if onRemove then onRemove(e, stuck) end
				end
			end
		end
	end
end

hook.Add("EntityTakeDamage", "tif_director_intensity", function(target, dmg)
	if not target:IsPlayer() then return end
	local a = dmg:GetAttacker()
	if IsValid(a) and a.TIFSoldier then D.Intensity = D.Intensity + dmg:GetDamage() end
end)

hook.Add("TIF_SoldierKilled", "tif_director_intensity", function(npc, attacker)
	if IsValid(attacker) and attacker:IsPlayer() then D.Intensity = D.Intensity + D.KILL_INTENSITY end
end)

timer.Create("tif_director_intensity", 1, 0, function()
	local players = D.Players()
	local close = 0
	if #players > 0 then
		for _, s in ipairs(TIF.Soldiers or {}) do
			if IsValid(s) and not s.tifDead and s.tifAware == TIF.AWARE.ENGAGED then
				local _, d = D.Nearest(s:GetPos(), players)
				if d < D.CLOSE_RANGE then close = close + 1 end
			end
		end
	end
	D.Intensity = math.max(0, D.Intensity * D.INTENSITY_DECAY - D.INTENSITY_DROP + close * D.CLOSE_INTENSITY)
end)

local function pick_size(lo, hi)
	return math.random(math.max(1, lo), math.max(lo, hi))
end
D.PickSize = pick_size

function D.DirectorThink(ent, now)
	local st = ent.tifDir
	if not st then
		st = { owned = {}, ambient = {}, hunters = {}, phase = "buildup", nextAssault = now + math.Rand(ent:GetAssaultMin(), ent:GetAssaultMax()), nextAmbient = 0 }
		ent.tifDir = st
	end
	local players = D.Players()
	if #players == 0 then return "no players" end
	local faction = D.HostileFaction(ent:GetFaction())
	if not faction then return "no hostile faction" end
	if now >= (st.nextRecycle or 0) then
		st.nextRecycle = now + D.RECYCLE_EVERY
		D.Recycle(st.owned, now, ent:GetSpawnMax() * 1.6, nil, players)
	end
	D.Alive(st.owned)
	D.Alive(st.hunters)
	local alive = #st.owned
	local I = D.Intensity
	if st.phase == "buildup" then
		if I >= ent:GetPeakIntensity() then
			st.phase = "peak"
		else
			if alive < ent:GetMaxAlive() and now >= st.nextAmbient then
				st.nextAmbient = now + 4
				local groups = 0
				for _, sq in pairs(st.ambient) do if sq.members and #TIF.Squad.Members(sq) > 0 then groups = groups + 1 end end
				if groups < ent:GetAmbientSquads() then
					local pos = D.FindSpawn(ent:GetSpawnMin(), ent:GetSpawnMax(), { ahead = true })
					if pos then
						local size = pick_size(ent:GetSquadMin(), ent:GetSquadMax())
						local sq, out = D.SpawnSquad(faction, pos, math.min(size, ent:GetMaxAlive() - alive), nil)
						if sq then
							st.ambient[sq] = sq
							for _, e in ipairs(out) do st.owned[#st.owned + 1] = e end
							if st.chill then
								sq.tifDirChill = true
							else
								local route = {}
								for k = 1, 3 do
									local p = D.FindSpawn(ent:GetSpawnMin() * 0.5, ent:GetSpawnMax(), { tries = 10 })
									if p then route[#route + 1] = p end
								end
								if #route >= 2 and math.random() < 0.6 then TIF.API.SquadPatrol(sq, route) end
							end
						end
					end
				end
			end
			if now >= st.nextAssault and alive < ent:GetMaxAlive() then
				st.nextAssault = now + math.Rand(ent:GetAssaultMin(), ent:GetAssaultMax())
				st.chill = nil
				local n = math.random(1, math.max(1, ent:GetAssaultSquads()))
				local avoid = {}
				for _ = 1, n do
					local pos = D.FindSpawn(ent:GetSpawnMin(), ent:GetSpawnMax(), { avoid = avoid, avoidR = 500 })
					if pos then
						avoid[#avoid + 1] = pos
						local size = pick_size(ent:GetSquadMin(), ent:GetSquadMax())
						local ply = D.Nearest(pos, players)
						local sq, out = D.SpawnSquad(faction, pos, math.min(size, ent:GetMaxAlive() - #st.owned), IsValid(ply) and ply:GetPos() or nil)
						if sq then
							for _, e in ipairs(out) do
								e.tifHunter = true
								st.owned[#st.owned + 1] = e
								st.hunters[#st.hunters + 1] = e
							end
							st.huntSquads = st.huntSquads or {}
							st.huntSquads[sq] = sq
							D.Hunt(sq, now, players)
						end
					end
				end
			end
		end
	elseif st.phase == "peak" then
		if I < ent:GetRelaxIntensity() then
			st.phase = "relax"
			st.relaxEnd = now + ent:GetRelaxTime()
		end
	elseif st.phase == "relax" then
		if I >= ent:GetPeakIntensity() then
			st.phase = "peak"
		elseif now >= (st.relaxEnd or 0) then
			st.phase = "buildup"
			st.chill = true
			st.nextAssault = math.max(st.nextAssault, now + math.Rand(ent:GetAssaultMin(), ent:GetAssaultMax()))
		end
	end
	if now >= (st.nextHunt or 0) then
		st.nextHunt = now + D.HUNT_EVERY
		for k, sq in pairs(st.huntSquads or {}) do
			if sq.members and #TIF.Squad.Members(sq) > 0 then D.Hunt(sq, now, players) else st.huntSquads[k] = nil end
		end
	end
	return st.phase .. (st.chill and st.phase == "buildup" and " (calm)" or "")
end

function D.DirectorClear(ent)
	local st = ent.tifDir
	if not st then return end
	for _, e in ipairs(st.owned) do if IsValid(e) then e:Remove() end end
	ent.tifDir = nil
end

D.ONSLAUGHT = {
	BANK0 = 2, RATE0 = 0.15, RAMP = 0.08, RATE_MAX = 1.2, BANK_MAX = 8,
	HEAT_STEP = 90, CROWD0 = 0.25, CROWD_FULL = 8, CROWD_GROW = 0.1, CROWD_MAX = 2,
	HEALTH = 0.02, HEALTH_MAX = 0.5, SURGE_EVERY = 75, SURGE_MIN = 40, SURGE_SIZE = 4, SURGE_PER_LEVEL = 2,
}

function D.OnslaughtMinutes(ent, now)
	local t0 = ent:GetRunStart()
	if t0 <= 0 then return 0 end
	return math.max(now - t0, 0) / 60
end

function D.OnslaughtCap(ent, now)
	local O = D.ONSLAUGHT
	local cap = ent:GetMaxAlive()
	local m = D.OnslaughtMinutes(ent, now)
	local grown = O.CROWD0 + (1 - O.CROWD0) * math.min(m / O.CROWD_FULL, 1)
	grown = math.min(grown + math.max(m - O.CROWD_FULL, 0) * O.CROWD_GROW, O.CROWD_MAX)
	return math.max(math.floor(cap * grown), math.min(cap, ent:GetSquadMax()))
end

local function surv_start(ent, st, now)
	ent:SetRunStart(now)
	ent:SetWave(0)
	ent:SetHeat(0)
	st.mode = ent:GetOnslaught() and "onslaught" or "waves"
	if st.mode == "onslaught" then
		ent:SetBreakEnd(0)
		ent:SetHeat(1)
		st.bank = D.ONSLAUGHT.BANK0
		st.nextSurge = now + D.ONSLAUGHT.SURGE_EVERY
	else
		ent:SetBreakEnd(now + math.min(ent:GetBreakTime(), 10))
	end
end

local function surv_spawn(ent, st, faction, size, now, players, health)
	local pos = D.FindSpawn(ent:GetSpawnMin(), ent:GetSpawnMax(), { avoid = st.sources, avoidR = 400 })
	if not pos or size <= 0 then return 0 end
	local ply = D.Nearest(pos, players)
	local sq, out = D.SpawnSquad(faction, pos, size, IsValid(ply) and ply:GetPos() or nil)
	if not sq then return 0 end
	for _, e in ipairs(out) do
		e.tifHunter = true
		e.tifMoraleScale = D.SURV_MORALE
		e.tifPreferPlayers = D.SURV_PREFER_PLAYERS
		st.owned[#st.owned + 1] = e
		if health and health > 1 and IsValid(e) then
			local hp = math.max(1, math.floor(e:GetMaxHealth() * health))
			e:SetMaxHealth(hp)
			e:SetHealth(hp)
		end
	end
	st.squads[sq] = sq
	st.sources[#st.sources + 1] = pos
	if #st.sources > 3 then table.remove(st.sources, 1) end
	D.Hunt(sq, now, players)
	return #out
end

function D.SurvivalThink(ent, now)
	local st = ent.tifSurv
	if not st then
		st = { owned = {}, squads = {}, sources = {}, left = 0, bank = 0 }
		ent.tifSurv = st
	end
	local players = D.Players()
	if #players == 0 then
		if ent:GetRunStart() > 0 then
			st.deadSince = st.deadSince or now
			if now - st.deadSince > 6 then D.SurvivalReset(ent) end
		end
		return
	end
	st.deadSince = nil
	if ent:GetRunStart() <= 0 then
		surv_start(ent, st, now)
		return
	end
	if st.mode ~= (ent:GetOnslaught() and "onslaught" or "waves") then
		D.SurvivalReset(ent)
		st = { owned = {}, squads = {}, sources = {}, left = 0, bank = 0 }
		ent.tifSurv = st
		surv_start(ent, st, now)
		return
	end
	local faction = D.HostileFaction(ent:GetFaction())
	if not faction then return end
	local onslaught = st.mode == "onslaught"
	if now >= (st.nextRecycle or 0) then
		st.nextRecycle = now + D.RECYCLE_EVERY
		D.Recycle(st.owned, now, ent:GetSpawnMax() * 1.8, function()
			if onslaught then st.bank = st.bank + 1 else st.left = st.left + 1 end
		end, players)
	end
	D.Alive(st.owned)
	if onslaught then
		local O = D.ONSLAUGHT
		local m = D.OnslaughtMinutes(ent, now)
		local level = 1 + math.floor(m * 60 / O.HEAT_STEP)
		if level ~= ent:GetHeat() then ent:SetHeat(level) end
		local dt = math.min(now - (st.lastT or now), 2)
		st.lastT = now
		local bankMax = O.BANK_MAX
		if now >= (st.nextSurge or 0) then
			st.nextSurge = now + math.max(O.SURGE_EVERY - m * 2, O.SURGE_MIN)
			st.bank = st.bank + O.SURGE_SIZE + level * O.SURGE_PER_LEVEL
		end
		local rate = math.min(O.RATE0 + O.RAMP * m, O.RATE_MAX)
		st.bank = math.min(st.bank + rate * dt, math.max(bankMax, st.bank))
		local cap = D.OnslaughtCap(ent, now)
		local room = cap - #st.owned
		local want = math.min(math.floor(st.bank), pick_size(ent:GetSquadMin(), ent:GetSquadMax()), room)
		if now >= (st.nextSpawn or 0) and want >= math.min(ent:GetSquadMin(), math.max(1, room)) and want > 0 then
			st.nextSpawn = now + 2
			local health = 1 + math.min(m * O.HEALTH, O.HEALTH_MAX)
			st.bank = st.bank - surv_spawn(ent, st, faction, want, now, players, health)
		end
	elseif ent:GetBreakEnd() > 0 then
		if now >= ent:GetBreakEnd() then
			local wave = ent:GetWave() + 1
			ent:SetWave(wave)
			ent:SetBreakEnd(0)
			st.left = math.max(1, math.Round(ent:GetStartSize() * (1 + ent:GetGrowth() / 100) ^ (wave - 1)))
			st.sources = {}
		end
		return
	elseif st.left > 0 and now >= (st.nextSpawn or 0) and #st.owned < ent:GetMaxAlive() then
		st.nextSpawn = now + 2
		local size = math.min(st.left, pick_size(ent:GetSquadMin(), ent:GetSquadMax()), ent:GetMaxAlive() - #st.owned)
		st.left = st.left - surv_spawn(ent, st, faction, size, now, players)
	elseif st.left <= 0 and #st.owned == 0 then
		ent:SetBreakEnd(now + math.max(ent:GetBreakTime(), 1))
	end
	if now >= (st.nextHunt or 0) then
		st.nextHunt = now + D.HUNT_EVERY
		for k, sq in pairs(st.squads) do
			if sq.members and #TIF.Squad.Members(sq) > 0 then D.Hunt(sq, now, players) else st.squads[k] = nil end
		end
	end
end

function D.SurvivalReset(ent)
	local st = ent.tifSurv
	if st then
		for _, e in ipairs(st.owned) do if IsValid(e) then e:Remove() end end
	end
	ent.tifSurv = nil
	ent:SetRunStart(0)
	ent:SetWave(0)
	ent:SetBreakEnd(0)
	ent:SetHeat(0)
end
