local TIF = TIF
TIF.Watchdog = TIF.Watchdog or {}
local Watchdog = TIF.Watchdog

Watchdog.WATCH_EVERY = 2
Watchdog.STACK_LONG = 45
Watchdog.ENTRY_LONG = 20
Watchdog.HOLD_LONG = 30
Watchdog.MARK_RADIUS = 1000

local function log_watch(...)
	if TIF.Event then
		TIF.Event("watch", ...)
	end
end

local function entity_label(ent)
	return IsValid(ent) and (ent:GetClass() .. "#" .. ent:EntIndex()) or "-"
end

function Watchdog.Check(now)
	local shield = TIF.Shield

	if TIF.Civ and TIF.Civ.List then
		local civs = TIF.Civ.List()
		for i = 1, #civs do
			local civ = civs[i]
			local held = civ.tifHeld

			if held and (held.done or not (shield and shield.List and shield.List[held])) then
				log_watch("held civilian with no live scene: ", entity_label(civ), " (state ", tostring(civ.state), "): let go")
				civ.tifHeld = nil
				civ.civOneShot = nil

				if civ.SetState then
					civ:SetState("flee")
				end
			elseif civ.state == "held" and not held then
				log_watch("civilian in state held with no scene: ", entity_label(civ), ": let go")

				if civ.SetState then
					civ:SetState("flee")
				end
			end
		end
	end

	local soldiers = TIF.Soldiers or {}
	for i = 1, #soldiers do
		local soldier = soldiers[i]
		if IsValid(soldier) and not soldier.tifDead then
			if soldier.tifActLock and not soldier.tifShield and not (soldier.tifMelee and soldier.tifMelee.fight) then
				log_watch("animation lock left on with no scene: ", entity_label(soldier), " (act ", soldier.tifAct and soldier.tifAct.name or "-", "): unlocked")
				soldier.tifActLock = nil
			end

			if soldier.tifVeh and not IsValid(soldier.tifVeh) then
				log_watch("orphaned vehicle state on ", entity_label(soldier), ": cleared")
				soldier.tifVeh = nil
				soldier.tifBoard = nil
				soldier.tifLeaving = nil
				soldier:SetParent(nil)
				soldier:SetCollisionGroup(COLLISION_GROUP_NPC)
				soldier:SetNW2Entity("tif_veh", NULL)
				soldier:SetNW2Int("tif_seat", 0)
			end

			if soldier.tifSwitch and now > (soldier.tifSwitch.done or 0) + 3 then
				log_watch("stalled weapon switch on ", entity_label(soldier), ": cleared")
				soldier.tifSwitch = nil
			end

			if soldier.tifSlim and not soldier.tifCQB and soldier.TIFSetSlim then
				soldier:TIFSetSlim(nil)
			end

			local act = soldier.tifAct
			if act and act.trans and not act.loop and now - act.t0 > math.max(act.dur + 2, 6) then
				log_watch("stalled transition clip on ", entity_label(soldier), " (", tostring(act.name), "): cleared")

				if TIF.Action then
					TIF.Action.Clear(soldier, true)
				end
			end
		end
	end

	local squadMod = TIF.Squad
	if squadMod and squadMod.List then
		for _, sq in pairs(squadMod.List) do
			local cq = sq.cqb
			if cq and cq.t0 then
				local team = cq.team or {}
				local stalled = (cq.phase == "stack" and now - cq.t0 > Watchdog.STACK_LONG)
					or (cq.phase == "entry" and now - cq.t0 > Watchdog.ENTRY_LONG and (cq.released or 0) < #team)
					or (cq.phase == "hold" and now - cq.t0 > Watchdog.HOLD_LONG)
				local key = cq.phase .. ":" .. tostring(cq.t0)

				if stalled and cq.tifWatched ~= key then
					cq.tifWatched = key
					local door = cq.door
					local acts = {}
					local seenCount = 0

					for i = 1, #team do
						local member = team[i]
						if IsValid(member) and member.tifPrimaryC and member.tifPrimaryC.visible then
							seenCount = seenCount + 1
						end
					end

					acts[1] = "seeing an enemy " .. seenCount .. ", all in " .. tostring(cq.allInAt ~= nil) .. " |"

					for i = 1, #team do
						local member = team[i]
						acts[#acts + 1] = string.format("%d:%s/%s", i,
							IsValid(member) and (member.tifCQB and member.tifCQB.label or "-") or "dead",
							IsValid(member) and (member.tifAct and member.tifAct.name or "-") or "-")
					end

					log_watch(string.format("cqb squad %s in %s for %.0f s: released %s/%d, ready %s, door %s%s, opening %s, flash %s | %s",
						tostring(sq.id), cq.phase, now - cq.t0, tostring(cq.released), #team, tostring(cq.stackReady),
						door and tostring(door.id) or "-", (door and TIF.Building and TIF.Building.Closed(door)) and " closed" or "",
						tostring(cq.opening ~= nil), tostring(cq.flashWait ~= nil), table.concat(acts, " ")))
				end
			end
		end
	end
end

timer.Create("tif_watchdog", Watchdog.WATCH_EVERY, 0, function()
	local ok, err = pcall(Watchdog.Check, CurTime())
	if not ok and TIF.Event then
		TIF.Event("watch", "watchdog error: ", tostring(err))
	end
end)

local function describe_entity(ent, origin)
	local pos = ent:GetPos()
	local parts = { entity_label(ent), string.format("%.0f u", pos:Distance(origin)) }

	if ent.TIFSoldier then
		parts[#parts + 1] = tostring(ent.GetTIFFaction and ent:GetTIFFaction() or "?")
		parts[#parts + 1] = "\"" .. tostring(ent.tifAction or "-") .. "\""
		parts[#parts + 1] = "act " .. (ent.tifAct and ent.tifAct.name or "-")

		if ent.tifCQB then
			parts[#parts + 1] = "cqb " .. tostring(ent.tifCQB.label)
		end

		if ent.tifShield then
			parts[#parts + 1] = "shield " .. tostring(ent.tifShield.varName) .. "/" .. tostring(ent.tifShield.phase)
		end

		if ent.tifMelee then
			parts[#parts + 1] = "melee " .. tostring(ent.tifMelee.fight or ent.tifMelee.phase)
		end

		if ent.tifMove and ent.tifMove.goal then
			parts[#parts + 1] = string.format("moving (%.0f u to go)", ent.tifMove.goal:Distance(pos))
		end

		if ent.tifDead or ent.tifDying then
			parts[#parts + 1] = "dying"
		end
	else
		parts[#parts + 1] = "state " .. tostring(ent.state)

		if ent.tifHeld then
			parts[#parts + 1] = "held"
		end

		parts[#parts + 1] = "clip " .. tostring(ent.civRole)
	end

	return table.concat(parts, ", ")
end

concommand.Add("tif_mark", function(ply, _, args)
	if not TIF.Event then return end

	local origin = IsValid(ply) and ply:GetPos() or Vector()
	local note = table.concat(args or {}, " ")
	TIF.Event("MARK", (IsValid(ply) and ply:Nick() or "console"), ": ", note ~= "" and note or "(no note)",
		string.format(" at (%.0f %.0f %.0f)", origin.x, origin.y, origin.z))
	local radiusSqr = Watchdog.MARK_RADIUS * Watchdog.MARK_RADIUS
	local nearby = {}
	local soldiers = TIF.Soldiers or {}

	for i = 1, #soldiers do
		local soldier = soldiers[i]
		if IsValid(soldier) and soldier:GetPos():DistToSqr(origin) < radiusSqr then
			nearby[#nearby + 1] = soldier
		end
	end

	if TIF.Civ and TIF.Civ.List then
		local civs = TIF.Civ.List()
		for i = 1, #civs do
			local civ = civs[i]
			if civ:GetPos():DistToSqr(origin) < radiusSqr then
				nearby[#nearby + 1] = civ
			end
		end
	end

	table.sort(nearby, function(a, b) return a:GetPos():DistToSqr(origin) < b:GetPos():DistToSqr(origin) end)

	for i = 1, math.min(#nearby, 16) do
		TIF.Event("MARK", "  ", describe_entity(nearby[i], origin))
	end

	if TIF.LogFile then
		TIF.LogFile.Flush()
	end

	if IsValid(ply) then
		ply:ChatPrint("[TIF] Marked in garrysmod/data/tif/log_sv.txt")
	end
end, nil, "tif_mark [note]: mark this moment in TIF's log file, with what the soldiers and civilians around you are doing")
