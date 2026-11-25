-- Squads: a leader (a soldier, or a player for friendly squads), members, a standing order,
-- a formation, and shared knowledge of enemies (radio-style: sightings reach every member).
--
-- Orders:
--   free     each soldier acts on its own (Phase 1-2 behaviour); posts are where they spawned
--   hold     stay around a position; fight from there without chasing beyond the leash
--   follow   keep formation on the leader (soldier or player); fight within a leash of it
--   regroup  close up on the leader, then follow
--   advance  the leader moves to a position, the rest follow in formation, then hold there

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

-- Leader-local offsets (x forward, y left) for member slot i (1-based, leader excluded).
local function slot_offset(formation, i, spacing)
	spacing = spacing or 95
	if formation == "column" then
		return Vector(-spacing * i, 0, 0)
	elseif formation == "line" then
		local k = math.ceil(i / 2)
		return Vector(-20, (i % 2 == 1 and 1 or -1) * spacing * k, 0)
	elseif formation == "file" then
		-- Two files behind the leader (good for roads and corridors).
		local k = math.ceil(i / 2)
		return Vector(-spacing * k, (i % 2 == 1 and 1 or -1) * 45, 0)
	end
	-- wedge
	local k = math.ceil(i / 2)
	return Vector(-spacing * k, (i % 2 == 1 and 1 or -1) * spacing * k, 0)
end

local publish -- defined below; used by SQ.Add above its definition

local function is_valid_leader(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() then return ent:Alive() end
	return ent.TIFSoldier and not ent.tifDead
end

-- With tif_debug 1, squad decisions go to the console (and console.log with -condebug).
function SQ.Log(sq, ...)
	local cv = GetConVar("tif_debug")
	if cv and cv:GetBool() then TIF.Log("[squad ", sq.id, " ", sq.faction, "] ", table.concat({ ... }, "")) end
end

function SQ.Of(npc)
	return npc.tifSquad
end

function SQ.Members(sq)
	local out = {}
	for _, m in ipairs(sq.members) do
		if IsValid(m) and not m.tifDead then out[#out + 1] = m end
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
	for _, m in ipairs(members or {}) do SQ.Add(sq, m) end
	SQ.SetLeader(sq, leader or sq.members[1])
	return sq
end

function SQ.Add(sq, npc)
	if not IsValid(npc) or npc.tifSquad == sq then return end
	if npc.tifSquad then SQ.Remove(npc) end
	if #sq.members >= SQ.MAX_SIZE then return end
	table.insert(sq.members, npc)
	npc.tifSquad = sq
	npc:SetNW2Int("tif_squad", sq.id)
	publish(sq)
end

-- Pick the next leader: a "leader" archetype first, then the healthiest soldier.
local function best_leader(sq)
	local best, bestScore
	for _, m in ipairs(SQ.Members(sq)) do
		local s = m:Health() + (m.tifArchId == "leader" and 1000 or 0)
		if not bestScore or s > bestScore then best, bestScore = m, s end
	end
	return best
end

-- Debug overlay info on each member: leader entity and order name.
publish = function(sq)
	for _, m in ipairs(sq.members) do
		if IsValid(m) then
			m:SetNW2Entity("tif_sqlead", IsValid(sq.leader) and sq.leader or NULL)
			m:SetNW2String("tif_order", sq.order.kind .. (sq.formation ~= "wedge" and (" / " .. sq.formation) or ""))
		end
	end
end
SQ.Publish = publish

function SQ.SetLeader(sq, leader)
	if IsValid(sq.leader) and sq.leader.TIFSoldier then sq.leader:SetNW2Bool("tif_leader", false) end
	sq.leader = leader
	if IsValid(leader) and leader.TIFSoldier then leader:SetNW2Bool("tif_leader", true) end
	publish(sq)
end

-- An empty squad goes; a room clear it was on ended with it, silently until 2026-11-20 (log_sv: squads 18 / 20 said
-- "next door" and nothing after): into the log file, with where it was.
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
	if IsValid(npc) then npc:SetNW2Int("tif_squad", 0) end
	if sq.leader == npc then
		local nl = best_leader(sq)
		SQ.SetLeader(sq, nl)
		if IsValid(nl) then
			-- Stop and regroup on the new leader.
			if sq.order.kind == "advance" then sq.order = { kind = "hold", pos = nl:GetPos(), time = CurTime() } end
			TIF.Say(nl, "backup", 0.6)
		end
	end
	if #SQ.Members(sq) == 0 then drop_squad(sq, "empty (last man removed)") end
end

-- opts.pace (advance): "rush" (jog until close or in contact), "move" (default: jog while the objective is far
-- and it's quiet, then the tactical walk), "careful" (tactical walk all the way).
function SQ.SetOrder(sq, kind, pos, yaw, opts)
	sq.order = { kind = kind, pos = pos, yaw = yaw, time = CurTime(), pace = opts and opts.pace or nil }
	publish(sq)
	-- One acknowledgement per order, from someone in the squad.
	local m = SQ.Members(sq)
	if #m > 0 then TIF.Say(m[math.random(#m)], "affirmative", 0.8) end
	for _, mem in ipairs(m) do
		mem.tifPost = nil -- recomputed from the order
		mem.tifSearch = nil
	end
	SQ.Signal(sq, kind)
end

-- The leader's hand signal for an order (MW22 gestures, MW19 body): "on me" toward his men for follow / regroup /
-- advance, "hold" for hold. Only standing (or crouched) still, not fighting, nothing else playing.
SQ.SIGNAL_CHANCE = 0.7
function SQ.Signal(sq, kind)
	local L = sq.leader
	if not is_valid_leader(L) or L.tifAct or L.tifCov or L.tifProne or L.tifVeh or L.tifDowned or L.tifReact then return end
	if not (L.tifHomeHost and TIF.GTG.IsVB(L.tifHomeHost)) or math.random() > SQ.SIGNAL_CHANCE then return end
	if L.loco:GetVelocity():Length2DSqr() > 20 * 20 or L.tifAware == TIF.AWARE.ENGAGED then return end
	local name
	if kind == "hold" then
		name = "mwgs_stop"
	elseif kind == "follow" or kind == "regroup" or kind == "advance" then
		-- Toward the middle of his men (numpad round his facing: 8 ahead, 4 left, 6 right, 2l / 2r behind).
		local c, n = Vector(), 0
		for _, mem in ipairs(SQ.Members(sq)) do
			if mem ~= L then c:Add(mem:GetPos()) n = n + 1 end
		end
		if n == 0 then return end
		c:Div(n)
		local a = math.AngleDifference((c - L:GetPos()):Angle().y, L:GetAngles().y)
		local dir = math.abs(a) <= 45 and "8" or (math.abs(a) >= 135 and (a > 0 and "2l" or "2r") or (a > 0 and "4" or "6"))
		local st = L:GetTIFStance() == TIF.Anim.STANCE_CROUCH and "crouch" or "stand"
		name = "mwgs_come_" .. st .. "_" .. dir
		if st == "crouch" and dir == "2r" then name = "mwgs_come_crouch_2l" end
	end
	if name and TIF.GTG.Clip(name, L.tifHomeHost) then TIF.Action.Play(L, name, { root = true, clear = true }) end
end

-- Leash for a soldier: where it must stay near during fights, or nil.
function SQ.Leash(npc)
	-- A personal leash (base guard on a post) comes first.
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

-- Formation slot for a member, in world space, or nil (leaders and free squads have none).
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

-- Patrol leader: walk the route loop, pausing a few seconds at each point. The rest of the
-- squad follows in formation (file by default).
local function patrol_lead(npc, sq, o, now)
	local pts = o.route
	if not o.i then
		-- Resume at the nearest point (after a fight or at the start).
		local best, bestD
		for i, p in ipairs(pts) do
			local d = p:DistToSqr(npc:GetPos())
			if not bestD or d < bestD then best, bestD = i, d end
		end
		o.i = best
	end
	local p = pts[o.i]
	if npc:GetPos():DistToSqr(p) < 90 * 90 then
		o.waitUntil = o.waitUntil or now + math.Rand(2, 5)
		Move.Stop(npc)
		npc.tifAction = "patrol: pause"
		if not o.lookYaw then o.lookYaw = npc:GetAngles().y + math.Rand(-70, 70) end
		local r = math.rad(o.lookYaw)
		npc.tifFace = npc:GetPos() + Vector(math.cos(r), math.sin(r), 0) * 300 + Vector(0, 0, 60)
		if now > o.waitUntil then o.i, o.waitUntil, o.lookYaw = o.i % #pts + 1, nil, nil end
	else
		npc.tifAction = "patrol " .. o.i .. "/" .. #pts
		npc.tifFace = nil
		if not Move.SetGoal(npc, p, npc.tifMode == 1 and "tactical" or "walk", "patrol") then
			o.i = o.i % #pts + 1
		end
	end
	return true
end

-- How fast an advance goes (see SQ.SetOrder opts.pace). Jogging while it's far and quiet; the tactical walk
-- once close (rush: 700, move: 1600) or once the squad has had contact in the last 25 s (the push itself is
-- then the squad tactics' bounds). Once slowed it stays slowed for this order (no jog / walk flipping).
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

-- Out of combat: move to and keep the formation slot / order position.
-- Returns true if the squad order controlled the soldier this think.
function SQ.Duty(npc, now)
	local sq = npc.tifSquad
	if not sq or sq.order.kind == "free" then return false end
	local o = sq.order
	npc.tifFire.want = false
	-- The soldier leading an advance walks to the target, then the squad holds there.
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
		return false -- leader holding still: normal duty (look around)
	end
	local slot, yaw = SQ.Slot(npc)
	if not slot then return false end
	local d2 = npc:GetPos():DistToSqr(slot)
	local leader = sq.leader
	local leaderSpeed = IsValid(leader) and leader:GetVelocity():Length2D() or 0
	if d2 > 70 * 70 then
		-- Keep up with a jogging leader (an advance at pace), else walk.
		local lm = IsValid(leader) and leader.tifMove
		local leaderJogs = lm and lm.goal and (lm.speed == "run" or lm.speed == "sprint")
		local speed = (d2 > 450 * 450 or leaderSpeed > 200 or leaderJogs) and "run" or (npc.tifMode == 1 and "tactical" or "walk")
		npc.tifAction = o.kind == "regroup" and "regrouping" or "in formation"
		npc.tifFace = nil
		Move.SetGoal(npc, slot, speed, "formation")
	else
		Move.Stop(npc)
		npc.tifAction = "in formation (" .. o.kind .. ")"
		-- Face where the leader faces, with a little spread so the group covers more angles.
		npc.tifFormationLook = npc.tifFormationLook or math.Rand(-35, 35)
		local r = math.rad((yaw or 0) + npc.tifFormationLook)
		npc.tifFace = npc:GetPos() + Vector(math.cos(r), math.sin(r), 0) * 300 + Vector(0, 0, 60)
		if o.kind == "regroup" and now - o.time > 4 then SQ.SetOrder(sq, "follow") end
	end
	return true
end

-- Shared knowledge -----------------------------------------------------------

-- A member saw/heard an enemy: the rest of the squad hears it on the radio shortly after.
function SQ.Report(npc, c)
	local sq = npc.tifSquad
	if not sq or not IsValid(c.ent) then return end
	local k = sq.knowledge[c.ent]
	local t = math.max(c.seenAt, c.heardAt)
	if k and k.time >= t then return end
	sq.knowledge[c.ent] = { pos = Vector(c.pos), vel = Vector(c.vel), time = t, by = npc, visible = c.visible }
end

-- Bring a member's unseen contacts up to date with the squad's newest information.
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
				if not npc.tifStim or now - npc.tifStim.time > 2 then TIF.Perception.Stimulus(npc, c.pos, "squad", now) end
			end
		end
	end
end

-- Join soldiers spawned one at a time (spawn menu) to a nearby squad of the same faction.
function SQ.AutoJoin(npc)
	if not IsValid(npc) or npc.tifSquad then return end
	local best, bestD
	for _, sq in pairs(SQ.List) do
		if sq.faction == npc:GetTIFFaction() and #SQ.Members(sq) < SQ.MAX_SIZE and not (IsValid(sq.leader) and sq.leader:IsPlayer()) then
			for _, m in ipairs(SQ.Members(sq)) do
				local d = m:GetPos():DistToSqr(npc:GetPos())
				if d < 700 * 700 and (not bestD or d < bestD) then best, bestD = sq, d end
			end
		end
	end
	if best then SQ.Add(best, npc) else SQ.Create(npc:GetTIFFaction(), { npc }) end
end

-- Player-led squad for a player (friendly soldiers that follow them).
function SQ.ForPlayer(ply)
	for _, sq in pairs(SQ.List) do
		if sq.leader == ply then return sq end
	end
	local sq = SQ.Create(TIF.FactionOf(ply), {}, nil)
	SQ.SetLeader(sq, ply)
	sq.order = { kind = "follow", time = CurTime() }
	return sq
end

-- Housekeeping: dead player leaders hand over to a soldier; empty squads vanish.
timer.Create("tif_squad_gc", 1, 0, function()
	for id, sq in pairs(SQ.List) do
		local alive = SQ.Members(sq)
		if #alive == 0 and not (IsValid(sq.leader) and sq.leader:IsPlayer()) then
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
