-- TIF.API: the stable interface for other addons (server). Everything an outside addon (such as the
-- DTW campaign) needs to put soldiers on the map and give them jobs, without reaching into TIF's
-- internals, which may change. Version-checked with TIF.API.VERSION.
--
-- Soldiers and squads
--   API.SpawnSquad(faction, pos, archetypes, opts) -> squad, soldiers
--       archetypes: list of archetype ids (one soldier each), e.g. { "leader", "rifleman", "rpg" }
--       opts: radius (spread, default 200), face (Vector to face, or "random"), order ("hold",
--             "free", ...), orderPos, orderYaw, noSquad
--   API.SquadMembers(squad) -> living soldiers
--   API.SquadHold(squad, pos, yaw)         defend a position (leashed to it)
--   API.SquadFree(squad)                   fight on its own
--   API.SquadPatrol(squad, points)         walk a loop of points (on foot)
--   API.SquadSearch(squad, pos, dir)       search round a position (dir: heading or nil)
--   API.SquadAdvance(squad, pos)           move to a position in formation, then hold there
--   API.SquadKnowsEnemy(squad, ent, pos)   tell the squad an enemy is at pos (radio report)
--   API.RemoveSquad(squad)                 remove its soldiers
--   API.FormSquad(soldiers) -> squad       (v2) a squad of existing soldiers
--   API.SetCaptive(soldier, on)            (v2) kneeling captive (out of the fight) / set free and armed
-- Garrisons (TIF bases: posts, reserve, foot patrols, vehicle patrols, convoys, alert levels,
-- alarm, reserve dispatch, search and stand-down)
--   API.Garrison(def) -> base            def as for TIF.Base (see encounter/sv_base.lua):
--       name, faction, center, radius, posts = { { pos, yaw, job = "post"|"reserve", arch } },
--       routes = { { size, pts } }, vpatrols, convoys, reinforce
--   API.RemoveGarrison(base)               remove its soldiers and vehicles
--   API.GarrisonAdopt(base, squad, job)    (v2) take an outside squad into the garrison -> count
--   API.GarrisonSoldiers(base) -> living soldiers
--   API.GarrisonPending(base) -> soldiers still to spawn (a garrison is built over a few ticks)
--   API.SetPerception(soldier|squad, profile) -> count   "standard" | "long" (sight and spotting range);
--       or answer hook "TIF_PerceptionProfile" (npc) for every soldier (DTW returns "standard")
--   API.GarrisonLevel(base) -> "calm" | "alert" | "alarm"
-- Queries
--   API.Fighters(faction) -> soldiers of a faction still in the fight (not dead, downed or surrendered)
--   API.FightersNear(pos, radius, faction) -> count, list
--   API.IsFighting(soldier) -> true when engaged or alerted
--   API.FactionOf(ent) -> faction id (soldiers and players)
-- Vehicles
--   API.SpawnVehicle(class, pos, yaw) -> vehicle or nil, error
--   API.Mount(squad, vehicle) / API.DriveTo(squad, pos, stay) / API.Dismount(squad)
--   API.MountSeated(squad, vehicle)        (v2) mount with everyone put straight into their seats
--   API.MountPassive(squad, vehicle)       (v2) ride in a vehicle a player drives
--   API.PlayerSquad(ply) / API.AddToSquad(squad, soldier) / API.SquadOrder(squad, kind, pos, yaw)   (v2)
--   API.MountPhase(squad)                  (v2) the squad's vehicle phase, or nil
--   API.VehicleRoute(from, to, dvOnly)     (v2) road route points, source
--   API.Convoy(squads, pos, stay)          (v2) mounted squads drive there in a column
--   API.VehicleSeats(class)                (v2) seat count of a vehicle class (GTG cars), or nil
--   API.VehicleUsable(veh) / API.VehicleDestroyed(veh)   (v2) drivable / wrecked
-- Hooks fired by TIF
--   "TIF_SoldierKilled" (soldier, attacker)
--   "TIF_BaseLevel"     (base, levelName, why)

-- (v3, for Global Operations)
--   API.SquadClear(squad, pos) -> found a way in   room-clear the building at pos
--   API.SquadClearing(squad)                      still clearing a building?
--   API.SquadWithdraw(squad, pos)                 fall back to pos (TIF's withdraw in a fight), then hold
--   API.SquadState(squad) -> { alive, centroid, fighting, engaged, supp, pinned, tactic, clearing,
--                              order, enemies, lastContact, mount }
--   API.SquadEnemies(squad, maxAge) -> { { ent, pos, time } }  known live enemies
--   API.GarrisonRelease(base, soldiers) -> squad  take soldiers out of a garrison (no post or leash)

-- (v4, for SWAT Operations)
--   API.SetEngageFilter(owner, fn)    fn(soldier, target) -> "fight" | "cover" (aim, never shoot) |
--                                     "ignore"; nil fn removes it. Nothing changes until one is set.
--   API.SquadClear(squad, pos, opts)  opts: door, hold, method ("open"|"kick"), onEntry, single,
--                                     teamSize (building/sv_clear.lua); pos may be nil with a door
--   API.SquadClearGo(squad) -> bool   a squad holding on its stack goes in
--   API.SquadStopClear(squad, reason)
--   API.DoorAt(pos, radius) -> door   the doorway nearest pos (an opaque handle), or nil
--   API.DoorInfo(door) -> { center, normal, width, exterior, closed, locked, ent }
--   API.SoldierTask(soldier, task)    task = { goal, face, speed, crouch, label }: go there, face that
--                                     way, shoot whatever shows itself from there; nil ends it
--   API.SoldierTaskDone(soldier) -> at the goal (or no task)
--   SquadState also gives clear = { phase, stacked, total, holding, rooms }
--   API.SquadClearGo(squad, opts)     opts may change method / onEntry at the go
--   API.SquadClearDoor(squad) -> door   API.SquadSetLeader(squad, ent)   API.SquadFormation(squad, f)
--   API.RoomAt(pos) / API.DoorRooms(door, fromPos) -> near, far / API.RoomCenter(room)
--   API.Stun(soldier, seconds)        blind, won't shoot, shaken (flashbangs, gas)
--   API.Say(soldier, event, chance)   API.SoldierState(soldier) -> { dead, downed, surrendered,
--                                     engaged, alerted, supp, stunned, health, maxHealth, action, morale, task }
-- Hooks: "TIF_CQBRoomClear" (squad, room, cq), "TIF_CQBDone" (squad, reason, cq)

local TIF = TIF

TIF.API = TIF.API or {}
local API = TIF.API
API.VERSION = 4  -- 2: GarrisonAdopt; 3: SquadClear, SquadWithdraw, SquadState...; 4: engage filter, commanded entries, tasks

-- Soldiers and squads -------------------------------------------------------------------------

function API.SpawnSquad(faction, pos, archetypes, opts)
	opts = opts or {}
	local n = #archetypes
	if n == 0 then return nil, {} end
	local out = TIF.SpawnSoldiers(nil, faction, n, nil, pos, opts.face or "random", {
		-- Game modes keep the loose spread (a DTW FOB spreads far out); opts.tight = true for a compact group.
		archetypes = archetypes, radius = opts.radius or 200, loose = not opts.tight, order = opts.order,
		orderPos = opts.orderPos, orderYaw = opts.orderYaw, noSquad = opts.noSquad, points = opts.points,
	})
	local sq = out[1] and out[1].tifSquad or nil
	if not sq and #out == 1 and not opts.noSquad then
		sq = TIF.Squad.Create(faction, out)
		if opts.order then TIF.Squad.SetOrder(sq, opts.order, opts.orderPos, opts.orderYaw) end
	end
	return sq, out
end

-- Camo for a faction while a mode runs (config/sh_packs.lua): owner is the mode's name ("gops", "dtw");
-- mode "" or nil clears that faction, faction nil clears everything the owner set.
function API.SetCamo(owner, faction, mode)
	if TIF.SetVariantOverride then TIF.SetVariantOverride(owner, faction, mode) end
end

function API.SquadMembers(sq)
	return sq and TIF.Squad.Members(sq) or {}
end

function API.SquadHold(sq, pos, yaw) TIF.Squad.SetOrder(sq, "hold", pos, yaw) end

-- Civilians (entities/tif_civilian.lua, tactics/sv_civilian.lua). opts: home, radius, state ("wander" |
-- "hide" | ...), shelter (stays hidden), noLeave (never scatters out of the area), model.
function API.SpawnCivilian(pos, opts) return TIF.Civ and TIF.Civ.Spawn(pos, opts) or nil end
function API.ScareCivilians(pos, radius, amount) if TIF.Civ then TIF.Civ.Scare(pos, radius or 1500, amount or 0.6) end end
function API.Civilians() return TIF.Civ and TIF.Civ.List() or {} end
-- Share of civilians that scatter out of the area on their first scare (the rest hide close by).
function API.SetCivilianLeaveShare(k) if TIF.Civ then TIF.Civ.LEAVE_SHARE = math.Clamp(k, 0, 1) end end

-- Night (true) / day (false) for soldier flashlights, or nil to go by the map (tif_flashlights 2).
function API.SetFlashlights(state) if TIF.Flashlight then TIF.Flashlight.Set(state) end end
function API.SquadFree(sq) TIF.Squad.SetOrder(sq, "free") end
-- opts.pace: "rush" | "move" (default) | "careful" (TIF.Squad.SetOrder). In contact the squad bounds toward pos.
function API.SquadAdvance(sq, pos, opts) TIF.Squad.SetOrder(sq, "advance", pos, nil, opts) end

function API.SquadPatrol(sq, points)
	TIF.Squad.SetOrder(sq, "patrol")
	local route = {}
	for i, p in ipairs(points) do route[i] = TIF.Move.Snap(p) or p end
	sq.order.route = route
	TIF.Squad.Publish(sq)
end

function API.SquadSearch(sq, pos, dir)
	local now = CurTime()
	for _, m in ipairs(TIF.Squad.Members(sq)) do TIF.Brain.StartSearch(m, pos, dir, now) end
end

function API.SquadKnowsEnemy(sq, ent, pos)
	if not (sq and IsValid(ent)) then return end
	sq.knowledge[ent] = { pos = Vector(pos or ent:GetPos()), vel = Vector(), time = CurTime(), visible = false }
end

-- (v2) Make a squad of existing soldiers (same faction; leader = the "leader" archetype if any).
function API.FormSquad(list)
	local alive = {}
	for _, e in ipairs(list or {}) do if IsValid(e) and not e.tifDead then alive[#alive + 1] = e end end
	if #alive == 0 then return nil end
	local leader = alive[1]
	for _, e in ipairs(alive) do if e.tifArchId == "leader" then leader = e break end end
	for _, e in ipairs(alive) do if e.tifSquad then TIF.Squad.Remove(e) end end
	return TIF.Squad.Create(alive[1]:GetTIFFaction(), alive, leader)
end

-- (v2) Hold a soldier captive (kneeling, unarmed, out of the fight: nobody targets him), or set him
-- free (on his feet, armed with his archetype's loadout, steady; give him a squad with FormSquad).
function API.SetCaptive(npc, on)
	if not IsValid(npc) or npc.tifDead then return end
	local Act = TIF.Action
	if on then
		if npc.tifSurrendered then return end
		npc.tifCaptive, npc.tifSurrendered = true, true
		if TIF.CoverBehave and TIF.CoverBehave.In(npc) then TIF.CoverBehave.Leave(npc, "captive") end
		npc.tifProne = nil
		TIF.Move.Stop(npc)
		npc:SetTIFWeapon("")
		npc.tifFire.want = false
		if npc.tifSquad then TIF.Squad.Remove(npc) end
		npc:SetNW2Bool("tif_surrendered", true)
		npc:SetNW2String("tif_morale", "captive")
		-- (0.38.0) kneeling, hands up: straight into the loop (MW22 surrender; was a GTA get-up-to-knees frame)
		TIF.Morale.Kneel(npc, true)
	else
		if not npc.tifSurrendered then return end
		npc.tifCaptive, npc.tifSurrendered, npc.tifHitboxPose = nil, nil, nil
		npc.tifMoraleState, npc.tifMorale = "steady", 0.7
		npc:SetNW2Bool("tif_surrendered", false)
		npc:SetNW2String("tif_morale", "steady")
		npc:SetNW2Float("tif_act_cycle", -1)
		npc.tifKneelLoopAt = nil
		Act.Clear(npc)
		local primary, secondary, launcher = TIF.Loadout(npc:GetTIFFaction(), npc.tifArchId)
		TIF.Weapon.Init(npc, primary, secondary, launcher)
	end
end

function API.RemoveSquad(sq)
	for _, m in ipairs(TIF.Squad.Members(sq)) do if IsValid(m) then m:Remove() end end
end

-- (v3) Room-clear the building at pos (building/sv_clear.lua). True if a way in was found.
-- (v4) opts: a commanded entry (see the header).
function API.SquadClear(sq, pos, opts)
	if not (sq and TIF.CQB) then return false end
	return TIF.CQB.Start(sq, pos, true, opts) and true or false
end

function API.SquadClearing(sq) return sq ~= nil and sq.cqb ~= nil end

-- (0.38.20) Human shield (tactics/sv_shield.lua): soldier `captor` takes civilian `civ` (a tif_civilian) hostage.
-- opts: held (already holding, no grab), hold (seconds or {min, max} before he shoves her away and fights),
-- noRescue (never lets go on his own), yaw / pos (the scene's facing and his spot). Returns the scene table or nil.
-- Hooks: TIF_ShieldStart(scene), TIF_ShieldEnd(scene, outcome). Semi-scripted use: TIFDIDDY/HUMAN_SHIELD.md.
function API.HumanShield(captor, civ, opts) return TIF.Shield and TIF.Shield.Start(captor, civ, opts) or nil end
function API.HumanShieldOf(ent) return ent and (ent.tifShield or ent.tifHeld) or nil end

-- (v4) Commanded entries, doors, single-soldier tasks, engage filters --------------------------

function API.SquadClearGo(sq, opts) return TIF.CQB.Go(sq, opts) end
function API.SquadStopClear(sq, reason) TIF.CQB.Stop(sq, reason) end
-- The door a squad is clearing through right now (its first one while holding), or nil.
function API.SquadClearDoor(sq) return sq and sq.cqb and sq.cqb.door or nil end

-- Leader (a soldier or a player: members of a player-led squad keep formation on him) and formation.
function API.SquadSetLeader(sq, ent) if sq and IsValid(ent) then TIF.Squad.SetLeader(sq, ent) end end
function API.SquadFormation(sq, f)
	if sq and table.HasValue(TIF.Squad.FORMATIONS, f) then sq.formation = f TIF.Squad.Publish(sq) end
end

-- Rooms (opaque handles, nil = outdoors): the room at a position, and both sides of a doorway seen
-- from fromPos -> nearRoom, farRoom.
function API.RoomAt(pos) return TIF.Building.RoomAt(pos) end
function API.DoorRooms(d, fromPos)
	if not d then return nil, nil end
	local BLD = TIF.Building
	local ra, rb = BLD.RoomOf(d.areaA), BLD.RoomOf(d.areaB)
	local pa = IsValid(d.areaA) and d.areaA:GetCenter() or d.center - d.normal * 60
	local pb = IsValid(d.areaB) and d.areaB:GetCenter() or d.center + d.normal * 60
	if fromPos:DistToSqr(pa) <= fromPos:DistToSqr(pb) then return ra, rb end
	return rb, ra
end
function API.RoomCenter(room)
	if not (room and room.areas and #room.areas > 0) then return nil end
	local c = Vector()
	for _, a in ipairs(room.areas) do c:Add(a:GetCenter()) end
	return c / #room.areas
end

-- Stunned (flashbang, gas): sees nothing and doesn't shoot for `seconds`, and is shaken by it.
function API.Stun(npc, seconds)
	if not IsValid(npc) or not npc.TIFSoldier or npc.tifDead then return end
	local untilT = CurTime() + seconds
	npc.tifBlindUntil = math.max(npc.tifBlindUntil or 0, untilT)
	npc.tifLowReadyUntil = math.max(npc.tifLowReadyUntil or 0, untilT)
	if npc.tifFire then npc.tifFire.want = false end
	if TIF.Morale then TIF.Morale.Add(npc, -0.15) end
	npc:SetNW2Float("tif_stun_until", untilT)
end

-- A voice line (sh_voices events: contact, clear, moving, affirmative, negative, retreat...).
function API.Say(npc, event, chance) if IsValid(npc) and TIF.Say then TIF.Say(npc, event, chance or 1) end end

-- One soldier, for status displays.
function API.SoldierState(npc)
	if not IsValid(npc) or not npc.TIFSoldier then return nil end
	local a = npc.tifAware
	return { dead = npc.tifDead == true, downed = npc.tifDowned == true, surrendered = npc.tifSurrendered == true,
		engaged = a == TIF.AWARE.ENGAGED, alerted = a == TIF.AWARE.ALERTED, supp = npc.tifSupp or 0,
		stunned = (npc.tifBlindUntil or 0) > CurTime(), health = npc:Health(), maxHealth = npc:GetMaxHealth(),
		action = npc.tifAction or "", morale = npc.tifMoraleState or "steady", task = npc.tifCQB and npc.tifCQB.label or nil }
end

function API.DoorAt(pos, radius) return TIF.CQB.DoorAt(pos, radius) end

function API.DoorInfo(d)
	if not d then return nil end
	local e = d.ent
	local lockedOk, locked = false, false
	if IsValid(e) then lockedOk, locked = pcall(e.GetInternalVariable, e, "m_bLocked") end
	return { center = d.center, normal = d.normal, width = d.width, exterior = d.exterior,
		closed = TIF.Building.Closed(d), locked = lockedOk and locked == true, ent = e }
end

function API.SoldierTask(npc, task)
	if not IsValid(npc) or npc.tifDead then return end
	if task then
		local goal = TIF.Move.Snap(task.goal) or task.goal
		npc.tifCQB = { goal = goal, face = task.face, speed = task.speed or "tactical", crouch = task.crouch,
			label = task.label or "task", task = true }
	elseif npc.tifCQB and npc.tifCQB.task then
		npc.tifCQB = nil
	end
end

function API.SoldierTaskDone(npc)
	local t = IsValid(npc) and npc.tifCQB
	if not (t and t.task) then return true end
	return npc:GetPos():DistToSqr(t.goal) < 40 * 40
end

function API.SetEngageFilter(owner, fn)
	TIF.Perception.Filters[owner] = isfunction(fn) and fn or nil
end

-- (v3) Fall back to pos. In a fight the squad uses its own withdraw (everyone falls back together,
-- the nearest keep shooting) and then holds there; out of a fight it moves there and holds.
function API.SquadWithdraw(sq, pos)
	if not sq then return end
	local SQ = TIF.Squad
	if TIF.CQB and sq.cqb then TIF.CQB.Stop(sq, "withdraw") end
	local fighting = false
	for _, m in ipairs(SQ.Members(sq)) do
		if m.tifAware == TIF.AWARE.ENGAGED or m.tifAware == TIF.AWARE.ALERTED then fighting = true break end
	end
	SQ.SetOrder(sq, "advance", pos)
	if fighting then
		sq.tactic = { kind = "withdraw", goal = pos, started = CurTime() }
		sq.preWithdrawOrder = { kind = "hold", pos = pos, time = CurTime() }
		sq.nextWithdraw = CurTime() + 60
	end
end

-- (v3) A summary of a squad: how many are left, where, whether it's fighting or pinned, what it's
-- doing, how many live enemies it knows of.
function API.SquadState(sq)
	local members = TIF.Squad.Members(sq)
	local n = #members
	local st = { alive = n, fighting = false, engaged = 0, pinned = false, supp = 0, tactic = "",
		clearing = sq.cqb ~= nil, order = sq.order and sq.order.kind or "free", enemies = 0, lastContact = nil }
	if n == 0 then return st end
	local c = Vector()
	for _, m in ipairs(members) do
		c:Add(m:GetPos())
		local a = m.tifAware
		if a == TIF.AWARE.ENGAGED then st.engaged = st.engaged + 1 st.fighting = true
		elseif a == TIF.AWARE.ALERTED then st.fighting = true end
		st.supp = st.supp + (m.tifSupp or 0)
	end
	st.centroid = c / n
	st.supp = st.supp / n
	st.pinned = st.supp > 0.6
	st.tactic = sq.tactic and sq.tactic.kind or ""
	local now = CurTime()
	for ent, k in pairs(sq.knowledge or {}) do
		if TIF.IsLiveCombatant(ent) and now - k.time < 15 then
			st.enemies = st.enemies + 1
			if not st.lastContact or k.time > st.lastContact.time then st.lastContact = { pos = Vector(k.pos), time = k.time } end
		end
	end
	st.mount = sq.mount and sq.mount.phase or nil
	local cq = sq.cqb
	if cq then
		st.clear = { phase = cq.phase, stacked = cq.stackReady or 0, total = #(cq.team or {}),
			holding = cq.hold and not cq.go and cq.firstDoor or false, rooms = table.Count(cq.cleared or {}) }
	end
	return st
end

-- (v3) Known live enemies of a squad, seen or reported within maxAge seconds (default 20).
function API.SquadEnemies(sq, maxAge)
	local out, now = {}, CurTime()
	for ent, k in pairs(sq and sq.knowledge or {}) do
		if TIF.IsLiveCombatant(ent) and now - k.time < (maxAge or 20) then
			out[#out + 1] = { ent = ent, pos = Vector(k.pos), time = k.time }
		end
	end
	return out
end

-- Garrisons ---------------------------------------------------------------------------------

function API.Garrison(def) return TIF.Base.Garrison(def) end
function API.RemoveGarrison(base) if base then TIF.Base.Remove(base) end end
function API.GarrisonAdopt(base, sq, job) return TIF.Base.Adopt(base, sq, job) end

-- (v3) Take soldiers out of a garrison (survivors falling back, or sent elsewhere): no post, no
-- leash, not base members any more. Returns them as a new squad, or nil if nobody is left.
function API.GarrisonRelease(base, list)
	local out, set = {}, {}
	for _, m in ipairs(list or {}) do
		if IsValid(m) and not m.tifDead and not m.tifSurrendered then
			m.tifLeash, m.tifGuardPost, m.tifBase, m.tifJob = nil, nil, nil, nil
			m:SetNW2String("tif_job", "")
			set[m] = true
			out[#out + 1] = m
		end
	end
	if base and base.members then
		local keep = {}
		for _, m in ipairs(base.members) do if not set[m] then keep[#keep + 1] = m end end
		base.members = keep
	end
	if #out == 0 then return nil end
	return API.FormSquad(out)
end

function API.GarrisonSoldiers(base)
	local out = {}
	for _, m in ipairs(base and base.members or {}) do
		if IsValid(m) and not m.tifDead then out[#out + 1] = m end
	end
	return out
end

-- Perception profile ("standard", "long", or any in TIF.Perception.Profiles) for a soldier or every
-- member of a squad; nil goes back to the hook / tif_perception default.
function API.SetPerception(target, profile)
	local list = {}
	if istable(target) and target.id and TIF.Squad.List[target.id] then list = TIF.Squad.Members(target)
	elseif IsValid(target) then list = { target } end
	for _, m in ipairs(list) do
		m.tifPerception, m.tifProfAt = profile, nil
	end
	return #list
end

-- Soldiers of a garrison still to be spawned (garrisons are built a few soldiers per tick).
function API.GarrisonPending(base)
	return base and base.pending or 0
end

function API.GarrisonLevel(base)
	return base and TIF.Base.LEVEL_NAMES[base.level] or "calm"
end

-- Queries ---------------------------------------------------------------------------------------

local function fighter(e)
	return IsValid(e) and not e.tifDead and not e.tifDowned and not e.tifSurrendered
end

function API.Fighters(faction)
	local out = {}
	for _, e in ipairs(TIF.Soldiers) do
		if fighter(e) and (not faction or e:GetTIFFaction() == faction) then out[#out + 1] = e end
	end
	return out
end

function API.FightersNear(pos, radius, faction)
	local out = {}
	local r2 = radius * radius
	for _, e in ipairs(TIF.Soldiers) do
		if fighter(e) and (not faction or e:GetTIFFaction() == faction) and e:GetPos():DistToSqr(pos) < r2 then
			out[#out + 1] = e
		end
	end
	return #out, out
end

function API.IsFighting(e)
	local a = e.tifAware
	return a == TIF.AWARE.ENGAGED or a == TIF.AWARE.ALERTED
end

function API.FactionOf(ent) return TIF.FactionOf(ent) end

-- Vehicles ---------------------------------------------------------------------------------------

function API.SpawnVehicle(class, pos, yaw) return TIF.Mounted.SpawnVehicle(class, pos, yaw) end
-- A prop placed as cover (sandbags, HESCO): soldiers always consider it and prefer it.
function API.MarkCover(ent) if IsValid(ent) then ent.tifCover = true end end
-- Paint a vehicle: GTG Glide cars through their paint (and no livery), others with SetColor. c: Color.
function API.PaintVehicle(veh, c, c2)
	if not IsValid(veh) or not c then return end
	if veh.SetGTGPaint then
		veh:SetGTGPaint(Vector(c.r / 255, c.g / 255, c.b / 255))
		if veh.SetGTGPaint2 then local d = c2 or c veh:SetGTGPaint2(Vector(d.r / 255, d.g / 255, d.b / 255)) end
		if veh.SetGTGLivery then veh:SetGTGLivery(0) end
		veh:SetColor(Color(255, 255, 255, veh:GetColor().a))
	else
		veh:SetColor(Color(c.r, c.g, c.b, veh:GetColor().a))
	end
end
function API.Mount(sq, veh) return TIF.Mounted.Mount(sq, veh) end
-- (v2) Ride in a vehicle a player drives (passengers; no stopping for contact).
function API.MountPassive(sq, veh) return TIF.Mounted.MountPassive(sq, veh) end
-- (v2) The squad a player leads (soldiers in it follow him), and adding a soldier to a squad.
function API.PlayerSquad(ply) return TIF.Squad.ForPlayer(ply) end
function API.AddToSquad(sq, npc) TIF.Squad.Add(sq, npc) return npc.tifSquad == sq end
function API.SquadOrder(sq, kind, pos, yaw) TIF.Squad.SetOrder(sq, kind, pos, yaw) end
-- (v2) Mount with everyone put straight into their seats.
function API.MountSeated(sq, veh) return TIF.Mounted.MountSeated(sq, veh) end
function API.DriveTo(sq, pos, stay) return TIF.Mounted.DriveTo(sq, pos, stay) end
function API.Dismount(sq) return TIF.Mounted.Dismount(sq, nil, "ordered") end
-- (v2) The squad's vehicle phase: "boarding" | "ready" | "driving" | "stopping" | "dismounting" |
-- "dismounted", or nil when it has no vehicle.
function API.MountPhase(sq) return sq and sq.mount and sq.mount.phase or nil end
-- (v2) Mounted squads (column order, lead first) drive to pos as a convoy (TIF.Convoy: one route,
-- spacing, the whole column stops for contact). Returns the convoy or nil.
function API.Convoy(squads, pos, stay)
	local cv = TIF.Convoy and TIF.Convoy.Create(squads)
	if cv then TIF.Convoy.DriveTo(cv, pos, stay) end
	return cv
end

-- (v2) Vehicle state: usable (drivable: not blown up, chassis and engine alive, not sunk);
-- destroyed (gone, blown up or chassis at 0; an engine-dead vehicle is disabled, not destroyed).
function API.VehicleUsable(veh) return TIF.Glide.IsUsable(veh) end
function API.VehicleDestroyed(veh)
	if not IsValid(veh) or veh.hasExploded then return true end
	return veh.GetChassisHealth ~= nil and veh:GetChassisHealth() <= 0
end

-- (v2) Seats in a vehicle class without spawning one: GTG cars list them in their data; other
-- classes return nil (unknown until spawned).
function API.VehicleSeats(class)
	local stored = scripted_ents.GetStored(class)
	local t = stored and stored.t
	if t and istable(t.GTGData) and istable(t.GTGData.seats) then return #t.GTGData.seats end
	return nil
end

-- (v2) A vehicle route from -> to: points, source ("dv" Decent Vehicle roads, "roads" navmesh
-- road search, "direct"), or nil, reason. dvOnly: only a Decent Vehicle route (cheap; the navmesh
-- search can be slow over long distances).
function API.VehicleRoute(from, to, dvOnly)
	if dvOnly then
		local pts = TIF.DV.Route(from, to)
		if pts then return pts, "dv" end
		return nil, "no dv route"
	end
	return TIF.Routes.Build(from, to)
end
