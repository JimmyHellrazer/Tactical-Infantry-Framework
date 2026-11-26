local TIF = TIF
local AW = TIF.AWARE
local SQ = TIF.Squad

TIF.Radio = TIF.Radio or {}
local RD = TIF.Radio
RD.Pending = RD.Pending or {}

local cvRange = CreateConVar("tif_radio_range", "4000", FCVAR_ARCHIVE, "How far squads share sightings and call for backup (0 = off)")

RD.DELAY = { 2, 4 }
RD.BACKUP_EVERY = 40

local function centroid(sq)
	local list = SQ.Members(sq)
	if #list == 0 then return nil end
	local c = Vector()
	for _, m in ipairs(list) do c:Add(m:GetPos()) end
	return c / #list
end

local function fighting(sq)
	for _, m in ipairs(SQ.Members(sq)) do
		if m.tifAware == AW.ENGAGED or m.tifAware == AW.ALERTED then return true end
	end
	return false
end

local function give(sq, ent, k)
	local mine = sq.knowledge[ent]
	if mine and mine.time >= k.time - 0.5 then return end
	sq.knowledge[ent] = { pos = Vector(k.pos), vel = Vector(k.vel or vector_origin), time = k.time, visible = false }
end

local function losing(sq, now)
	local members = SQ.Members(sq)
	if #members == 0 then return false end
	if (sq.peakSize or #members) > #members then return true end
	if TIF.Morale and TIF.Morale.Enabled() and TIF.Morale.SquadAverage(sq) < 0.5 then return true end
	local enemies = 0
	for ent, k in pairs(sq.knowledge) do
		if now - k.time < 10 and TIF.IsLiveCombatant(ent) then enemies = enemies + 1 end
	end
	return enemies > #members
end

local function tick(now)
	local range = cvRange:GetFloat()
	if range <= 0 then return end
	local r2 = range * range
	local list = {}
	for _, sq in pairs(SQ.List) do
		local c = centroid(sq)
		if c then list[#list + 1] = { sq = sq, c = c } end
	end

	for _, a in ipairs(list) do
		local sa = a.sq

		for ent, k in pairs(sa.knowledge) do
			if now - k.time < 5 and TIF.IsLiveCombatant(ent) and (not k.radioed or k.radioed < k.time) then
				k.radioed = k.time
				for _, b in ipairs(list) do
					if b.sq ~= sa and b.sq.faction == sa.faction and a.c:DistToSqr(b.c) < r2 then
						RD.Pending[#RD.Pending + 1] = { sq = b.sq, ent = ent, k = { pos = Vector(k.pos), vel = k.vel, time = k.time },
							at = now + math.Rand(RD.DELAY[1], RD.DELAY[2]) }
					end
				end
			end
		end

		if fighting(sa) and now > (sa.nextBackup or 0) and losing(sa, now) and not (IsValid(sa.leader) and sa.leader:IsPlayer()) then
			local best, bestD
			for _, b in ipairs(list) do
				local sb = b.sq
				if sb ~= sa and sb.faction == sa.faction and not sb.static and not sb.cqb
					and not (IsValid(sb.leader) and sb.leader:IsPlayer()) and not fighting(sb)
					and not (TIF.Mounted and TIF.Mounted.Busy(sb)) then
					local d = a.c:DistToSqr(b.c)
					if d < r2 and (not bestD or d < bestD) then best, bestD = sb, d end
				end
			end
			sa.nextBackup = now + RD.BACKUP_EVERY
			local caller = IsValid(sa.leader) and sa.leader.TIFSoldier and sa.leader or SQ.Members(sa)[1]
			if caller then TIF.Say(caller, "backup", 1) end
			if best then
				for ent, k in pairs(sa.knowledge) do
					if TIF.IsLiveCombatant(ent) then give(best, ent, k) end
				end
				best.backupFor = sa

				if best.order.kind == "hold" then SQ.SetOrder(best, "free") end
				local m = SQ.Members(best)[1]
				if m then TIF.Say(m, "affirmative", 0.9) end
				SQ.Log(sa, "[radio] backup requested; squad ", best.id, " answering (", math.floor(math.sqrt(bestD)), "u away)")
			else
				SQ.Log(sa, "[radio] backup requested; nobody free in range")
			end
		end
	end

	local keep = {}
	for _, p in ipairs(RD.Pending) do
		if now >= p.at then
			if SQ.List[p.sq.id] and TIF.IsLiveCombatant(p.ent) then give(p.sq, p.ent, p.k) end
		else
			keep[#keep + 1] = p
		end
	end
	RD.Pending = keep
end

timer.Create("tif_radio_tick", 1, 0, function()
	if TIF.AIDisabled() then return end
	local ok, err = pcall(tick, CurTime())
	if not ok then TIF.Error("Radio error: ", tostring(err)) end
end)
