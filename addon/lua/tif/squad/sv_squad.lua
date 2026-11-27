local TIF = TIF
local Move = TIF.Move

TIF.Squad = TIF.Squad or {}
local SQ = TIF.Squad
SQ.List = SQ.List or {}
SQ.NextId = SQ.NextId or 1

SQ.MAX_SIZE = 12
SQ.HOLD_LEASH = 550
SQ.FOLLOW_LEASH = 900
SQ.RADIO_DELAY = { 0.3, 0.9 }
SQ.FORMATIONS = { "wedge", "column", "line", "file" }

local function slot_offset(formation, i, spacing)
	spacing = spacing or 95

	if formation == "column" then
		return Vector(-spacing * i, 0, 0)
	elseif formation == "line" then
		local k = math.ceil(i / 2)
		return Vector(-20, (i % 2 == 1 and 1 or -1) * spacing * k, 0)
	elseif formation == "file" then
		local k = math.ceil(i / 2)
		return Vector(-spacing * k, (i % 2 == 1 and 1 or -1) * 45, 0)
	end

	local k = math.ceil(i / 2)
	return Vector(-spacing * k, (i % 2 == 1 and 1 or -1) * spacing * k, 0)
end
SQ.SlotOffset = slot_offset

local publish

local function is_valid_leader(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() then return ent:Alive() end

	return ent.TIFSoldier and not ent.tifDead
end

function SQ.Log(sq, ...)
	local cv = GetConVar("tif_debug")
	if cv and cv:GetBool() then
		TIF.Log("[squad ", sq.id, " ", sq.faction, "] ", table.concat({ ... }, ""))
	end
end

function SQ.Of(npc)
	return npc.tifSquad
end

function SQ.Members(sq)
	local out = {}
	for _, m in ipairs(sq.members) do
		if IsValid(m) and not m.tifDead then
			out[#out + 1] = m
		end
	end

	return out
end

function SQ.Create(faction, members, leader)
	local sq = {
		id = SQ.NextId, faction = faction, members = {}, leader = nil,
		order = { kind = "free", time = CurTime() }, formation = "wedge", knowledge = {},
	}
	SQ.NextId = SQ.NextId + 1
	SQ.List[sq.id] = sq

	for _, m in ipairs(members or {}) do
		SQ.Add(sq, m)
	end

	SQ.SetLeader(sq, leader or sq.members[1])
	return sq
end

function SQ.Add(sq, npc)
	if not IsValid(npc) or npc.tifSquad == sq then return end

	if npc.tifSquad then
		SQ.Remove(npc)
	end

	if #sq.members >= SQ.MAX_SIZE then return end

	table.insert(sq.members, npc)
	npc.tifSquad = sq
	npc:SetNW2Int("tif_squad", sq.id)
	publish(sq)
end

local function best_leader(sq)
	local best, bestScore
	for _, m in ipairs(SQ.Members(sq)) do
		local s = m:Health() + (m.tifArchId == "leader" and 1000 or 0)
		if not bestScore or s > bestScore then
			best, bestScore = m, s
		end
	end

	return best
end

publish = function(sq)
	local lead = IsValid(sq.leader) and sq.leader or NULL
	local orderStr = sq.order.kind .. (sq.formation ~= "wedge" and (" / " .. sq.formation) or "")
	local members = sq.members

	for i = 1, #members do
		local m = members[i]
		if IsValid(m) then
			if m:GetNW2Entity("tif_sqlead", NULL) ~= lead then
				m:SetNW2Entity("tif_sqlead", lead)
			end

			if m:GetNW2String("tif_order", "") ~= orderStr then
				m:SetNW2String("tif_order", orderStr)
			end
		end
	end
end

SQ.Publish = publish

function SQ.SetLeader(sq, leader)
	if IsValid(sq.leader) and sq.leader.TIFSoldier then
		sq.leader:SetNW2Bool("tif_leader", false)
	end

	sq.leader = leader

	if IsValid(leader) and leader.TIFSoldier then
		leader:SetNW2Bool("tif_leader", true)
	end

	publish(sq)
end

local function drop_squad(sq, why)
	local cq = sq.cqb
	if cq and TIF.Event then
		TIF.Event("cqb", "squad ", sq.id, " ", sq.faction or "", ": clear ended, squad ", why, " (", tostring(cq.phase),
			" at door ", cq.door and tostring(cq.door.id) or "-", ", ", table.Count(cq.cleared or {}), " room(s) cleared)")
	end

	SQ.List[sq.id] = nil
end

function SQ.Remove(npc)
	local sq = npc.tifSquad
	if not sq then return end

	table.RemoveByValue(sq.members, npc)
	npc.tifSquad = nil
	npc.tifRole, npc.tifCoverCenter = nil, nil

	if IsValid(npc) then
		npc:SetNW2Int("tif_squad", 0)
	end

	if sq.leader == npc then
		local nl = best_leader(sq)
		if IsValid(nl) then
			if sq.order.kind == "advance" then
				sq.order = { kind = "hold", pos = nl:GetPos(), time = CurTime() }
			end

			TIF.Say(nl, "backup", 0.6)
		end

		SQ.SetLeader(sq, nl)
	end

	if #SQ.Members(sq) == 0 then
		drop_squad(sq, "empty (last man removed)")
	end
end

function SQ.SetOrder(sq, kind, pos, yaw, opts)
	sq.order = { kind = kind, pos = pos, yaw = yaw, time = CurTime(), pace = opts and opts.pace or nil }
	publish(sq)

	local m = SQ.Members(sq)
	if #m > 0 then
		TIF.Say(m[math.random(#m)], "affirmative", 0.8)
	end

	for _, mem in ipairs(m) do
		mem.tifPost = nil
		mem.tifSearch = nil
	end

	SQ.Signal(sq, kind)
end

SQ.SIGNAL_CHANCE = 0.7

function SQ.Signal(sq, kind)
	local L = sq.leader
	if not is_valid_leader(L) or not L.TIFSoldier or not L.loco or L.tifAct or L.tifCov or L.tifProne or L.tifVeh or L.tifDowned or L.tifReact then
		return
	end

	if not (L.tifHomeHost and TIF.GTG.IsVB(L.tifHomeHost)) or math.random() > SQ.SIGNAL_CHANCE then
		return
	end

	if L.loco:GetVelocity():Length2DSqr() > 20 * 20 or L.tifAware == TIF.AWARE.ENGAGED then
		return
	end

	local name
	if kind == "hold" then
		name = "mwgs_stop"
	elseif kind == "follow" or kind == "regroup" or kind == "advance" then
		local c, n = Vector(), 0
		for _, mem in ipairs(SQ.Members(sq)) do
			if mem ~= L then
				c:Add(mem:GetPos())
				n = n + 1
			end
		end

		if n == 0 then return end

		c:Div(n)
		local a = math.AngleDifference((c - L:GetPos()):Angle().y, L:GetAngles().y)
		local dir = math.abs(a) <= 45 and "8" or (math.abs(a) >= 135 and (a > 0 and "2l" or "2r") or (a > 0 and "4" or "6"))
		local st = L:GetTIFStance() == TIF.Anim.STANCE_CROUCH and "crouch" or "stand"
		name = "mwgs_come_" .. st .. "_" .. dir

		if st == "crouch" and dir == "2r" then
			name = "mwgs_come_crouch_2l"
		end
	end

	if name and TIF.GTG.Clip(name, L.tifHomeHost) then
		TIF.Action.Play(L, name, { root = true, clear = true })
	end
end

function SQ.Leash(npc)
	local own = npc.tifLeash
	if own then return own.pos, own.radius end

	local sq = npc.tifSquad
	if not sq then return nil end

	local o = sq.order
	if o.kind == "hold" and o.pos then return o.pos, SQ.HOLD_LEASH end

	if (o.kind == "follow" or o.kind == "regroup") and is_valid_leader(sq.leader) and sq.leader ~= npc then
		return sq.leader:GetPos(), SQ.FOLLOW_LEASH
	end

	return nil
end

function SQ.Slot(npc)
	local sq = npc.tifSquad
	if not sq or sq.leader == npc then return nil end

	local o = sq.order
	if o.kind == "free" then return nil end

	local anchor, yaw
	if o.kind == "hold" and o.pos then
		anchor, yaw = o.pos, o.yaw or 0
	elseif is_valid_leader(sq.leader) then
		anchor = sq.leader:GetPos()
		yaw = sq.leader:IsPlayer() and sq.leader:EyeAngles().y or sq.leader:GetAngles().y
	else
		return nil
	end

	local index = 0
	for _, m in ipairs(sq.members) do
		if m ~= sq.leader and IsValid(m) and not m.tifDead then
			index = index + 1
			if m == npc then break end
		end
	end

	local spacing = o.kind == "regroup" and 60 or 95
	local formation = o.kind == "hold" and "line" or sq.formation
	local off = slot_offset(formation, index, spacing)
	local r = math.rad(yaw)
	local c, s = math.cos(r), math.sin(r)
	local p = anchor + Vector(off.x * c - off.y * s, off.x * s + off.y * c, 0)
	return Move.Snap(p) or anchor, yaw
end

local function patrol_lead(npc, sq, o, now)
	local pts = o.route
	if not o.i then
		local best, bestD
		for i, p in ipairs(pts) do
			local d = p:DistToSqr(npc:GetPos())
			if not bestD or d < bestD then
				best, bestD = i, d
			end
		end

		o.i = best
	end

	local p = pts[o.i]
	if not p then
		o.i = 1
		p = pts[1]
		if not p then return false end
	end

	if npc:GetPos():DistToSqr(p) < 90 * 90 then
		o.waitUntil = o.waitUntil or now + math.Rand(2, 5)
		Move.Stop(npc)
		npc.tifAction = "patrol: pause"

		if not o.lookYaw then
			o.lookYaw = npc:GetAngles().y + math.Rand(-70, 70)
		end

		local r = math.rad(o.lookYaw)
		npc.tifFace = npc:GetPos() + Vector(math.cos(r), math.sin(r), 0) * 300 + Vector(0, 0, 60)

		if now > o.waitUntil then
			o.i, o.waitUntil, o.lookYaw = o.i % #pts + 1, nil, nil
		end
	else
		npc.tifAction = "patrol " .. o.i .. "/" .. #pts
		npc.tifFace = nil

		if not Move.SetGoal(npc, p, npc.tifMode == 1 and "tactical" or "walk", "patrol") then
			o.i = o.i % #pts + 1
		end
	end

	return true
end

SQ.PACE = { rush = 700, move = 1600 }

function SQ.AdvancePace(sq, npc, o, now)
	local pace = o.pace or "move"
	if pace == "careful" or o.slowed then return "tactical" end

	local near = SQ.PACE[pace] or SQ.PACE.move
	local contact = (sq.lastContact or -99) > now - 25

	if contact or npc:GetPos():DistToSqr(o.pos) < near * near then
		o.slowed = true
		return "tactical"
	end

	return "run"
end

function SQ.Duty(npc, now)
	local sq = npc.tifSquad
	if not sq or sq.order.kind == "free" then return false end

	local o = sq.order
	npc.tifFire.want = false

	if sq.leader == npc then
		if o.kind == "patrol" and o.route and #o.route > 0 then
			return patrol_lead(npc, sq, o, now)
		end

		if o.kind == "advance" and o.pos then
			npc.tifAction = "leading advance"
			npc.tifMode = 1

			if npc:GetPos():DistToSqr(o.pos) < 90 * 90 then
				SQ.SetOrder(sq, "hold", o.pos, npc:GetAngles().y)
			elseif not Move.SetGoal(npc, o.pos, SQ.AdvancePace(sq, npc, o, now), "advance") then
				SQ.SetOrder(sq, "hold", npc:GetPos(), npc:GetAngles().y)
			end

			return true
		end

		if o.kind == "hold" and o.pos and npc:GetPos():DistToSqr(o.pos) > 80 * 80 then
			npc.tifAction = "to hold position"
			Move.SetGoal(npc, o.pos, "walk", "hold")
			return true
		end

		return false
	end

	local slot, yaw = SQ.Slot(npc)
	if not slot then return false end

	local d2 = npc:GetPos():DistToSqr(slot)
	local leader = sq.leader
	local leaderSpeed = IsValid(leader) and leader:GetVelocity():Length2D() or 0

	if d2 > 70 * 70 then
		local lm = IsValid(leader) and leader.tifMove
		local leaderJogs = lm and lm.goal and (lm.speed == "run" or lm.speed == "sprint")
		local speed = (d2 > 450 * 450 or leaderSpeed > 200 or leaderJogs) and "run" or (npc.tifMode == 1 and "tactical" or "walk")
		npc.tifAction = o.kind == "regroup" and "regrouping" or "in formation"
		npc.tifFace = nil
		Move.SetGoal(npc, slot, speed, "formation")
	else
		Move.Stop(npc)
		npc.tifAction = "in formation (" .. o.kind .. ")"

		npc.tifFormationLook = npc.tifFormationLook or math.Rand(-35, 35)
		local r = math.rad((yaw or 0) + npc.tifFormationLook)
		npc.tifFace = npc:GetPos() + Vector(math.cos(r), math.sin(r), 0) * 300 + Vector(0, 0, 60)

		if o.kind == "regroup" and now - o.time > 4 then
			SQ.SetOrder(sq, "follow")
		end
	end

	return true
end

function SQ.Report(npc, c)
	local sq = npc.tifSquad
	if not sq or not IsValid(c.ent) then return end

	local k = sq.knowledge[c.ent]
	local t = math.max(c.seenAt, c.heardAt)
	if k and k.time >= t then return end

	sq.knowledge[c.ent] = { pos = Vector(c.pos), vel = Vector(c.vel), time = t, by = npc, visible = c.visible }
end

function SQ.Sync(npc, now)
	local sq = npc.tifSquad
	if not sq then return end

	local contacts = npc.tifK.contacts
	for ent, k in pairs(sq.knowledge) do
		if not TIF.IsLiveCombatant(ent) then
			sq.knowledge[ent] = nil
		elseif k.by ~= npc and now - k.time > SQ.RADIO_DELAY[1] then
			local c = contacts[ent]
			if not c then
				c = TIF.Perception.Contact(npc, ent)
			end

			if not c.visible and k.time > math.max(c.seenAt, c.heardAt) + 0.25 then
				c.confirmed = true
				c.pos = Vector(k.pos)
				c.vel = Vector(k.vel)
				c.heardAt = k.time
				c.baseUnc = 48
				c.lostAt = c.lostAt or now
				c.source = "squad"

				if not npc.tifStim or now - npc.tifStim.time > 2 then
					TIF.Perception.Stimulus(npc, c.pos, "squad", now)
				end
			end
		end
	end
end

function SQ.AutoJoin(npc)
	if not IsValid(npc) or npc.tifSquad then return end

	local best, bestD
	for _, sq in pairs(SQ.List) do
		if sq.faction == npc:GetTIFFaction() and #SQ.Members(sq) < SQ.MAX_SIZE and not (IsValid(sq.leader) and sq.leader:IsPlayer()) then
			for _, m in ipairs(SQ.Members(sq)) do
				local d = m:GetPos():DistToSqr(npc:GetPos())
				if d < 700 * 700 and (not bestD or d < bestD) then
					best, bestD = sq, d
				end
			end
		end
	end

	if best then
		SQ.Add(best, npc)
	else
		SQ.Create(npc:GetTIFFaction(), { npc })
	end
end

function SQ.ForPlayer(ply)
	for _, sq in pairs(SQ.List) do
		if sq.leader == ply then return sq end
	end

	local sq = SQ.Create(TIF.FactionOf(ply), {}, nil)
	SQ.SetLeader(sq, ply)
	sq.order = { kind = "follow", time = CurTime() }
	return sq
end

timer.Create("tif_squad_gc", 1, 0, function()
	for id, sq in pairs(SQ.List) do
		local members = sq.members
		for i = #members, 1, -1 do
			local m = members[i]
			if not IsValid(m) or m.tifDead then
				table.remove(members, i)
			end
		end

		if #members == 0 and not (IsValid(sq.leader) and sq.leader:IsPlayer()) then
			drop_squad(sq, "empty (all dead or removed)")
		elseif not is_valid_leader(sq.leader) then
			local old = sq.leader
			SQ.SetLeader(sq, best_leader(sq))

			if IsValid(old) and old:IsPlayer() and IsValid(sq.leader) then
				sq.order = { kind = "hold", pos = sq.leader:GetPos(), yaw = sq.leader:GetAngles().y, time = CurTime() }
				publish(sq)
			end
		end
	end
end)
