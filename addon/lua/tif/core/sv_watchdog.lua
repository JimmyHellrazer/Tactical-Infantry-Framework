local TIF = TIF
TIF.Watchdog = TIF.Watchdog or {}
local W = TIF.Watchdog

W.WATCH_EVERY = 2
W.STACK_LONG = 45
W.ENTRY_LONG = 20
W.HOLD_LONG = 30
W.MARK_RADIUS = 1000

local function ev(...) if TIF.Event then TIF.Event("watch", ...) end end
local function name_of(e) return IsValid(e) and (e:GetClass() .. "#" .. e:EntIndex()) or "-" end

function W.Check(now)
	local SH = TIF.Shield

	if TIF.Civ and TIF.Civ.List then
		for _, c in ipairs(TIF.Civ.List()) do
			local held = c.tifHeld
			if held and (held.done or not (SH and SH.List and SH.List[held])) then
				ev("held civilian with no live scene: ", name_of(c), " (state ", tostring(c.state), "): let go")
				c.tifHeld = nil
				c.civOneShot = nil
				if c.SetState then c:SetState("flee") end
			elseif c.state == "held" and not held then
				ev("civilian in state held with no scene: ", name_of(c), ": let go")
				if c.SetState then c:SetState("flee") end
			end
		end
	end
	for _, s in ipairs(TIF.Soldiers or {}) do
		if IsValid(s) and s.tifActLock and not s.tifShield and not (s.tifMelee and s.tifMelee.fight) and not s.tifDead then
			ev("animation lock left on with no scene: ", name_of(s), " (act ", s.tifAct and s.tifAct.name or "-", "): unlocked")
			s.tifActLock = nil
		end
	end

	local SQ = TIF.Squad
	if SQ and SQ.List then
		for _, sq in pairs(SQ.List) do
			local cq = sq.cqb
			if cq and cq.t0 then
				local long = (cq.phase == "stack" and now - cq.t0 > W.STACK_LONG) or
					(cq.phase == "entry" and now - cq.t0 > W.ENTRY_LONG and (cq.released or 0) < #(cq.team or {})) or
						(cq.phase == "hold" and now - cq.t0 > W.HOLD_LONG)
				local key = cq.phase .. ":" .. tostring(cq.t0)
				if long and cq.tifWatched ~= key then
					cq.tifWatched = key
					local d = cq.door
					local acts = {}
					local seen = 0
					for _, m in ipairs(cq.team or {}) do if IsValid(m) and m.tifPrimaryC and m.tifPrimaryC.visible then seen = seen + 1 end end
					acts[1] = "seeing an enemy " .. seen .. ", all in " .. tostring(cq.allInAt ~= nil) .. " |"
					for i, m in ipairs(cq.team or {}) do
						acts[#acts + 1] = string.format("%d:%s/%s", i, IsValid(m) and (m.tifCQB and m.tifCQB.label or "-") or "dead",
							IsValid(m) and (m.tifAct and m.tifAct.name or "-") or "-")
					end
					ev(string.format("cqb squad %s in %s for %.0f s: released %s/%d, ready %s, door %s%s, opening %s, flash %s | %s",
						tostring(sq.id), cq.phase, now - cq.t0, tostring(cq.released), #(cq.team or {}), tostring(cq.stackReady),
						d and tostring(d.id) or "-", (d and TIF.Building and TIF.Building.Closed(d)) and " closed" or "",
						tostring(cq.opening ~= nil), tostring(cq.flashWait ~= nil), table.concat(acts, " ")))
				end
			end
		end
	end
end

timer.Create("tif_watchdog", W.WATCH_EVERY, 0, function()
	local ok, err = pcall(W.Check, CurTime())
	if not ok and TIF.Event then TIF.Event("watch", "watchdog error: ", tostring(err)) end
end)

local function describe(e, from)
	local p = e:GetPos()
	local bits = { name_of(e), string.format("%.0f u", p:Distance(from)) }
	if e.TIFSoldier then
		bits[#bits + 1] = tostring(e.GetTIFFaction and e:GetTIFFaction() or "?")
		bits[#bits + 1] = "\"" .. tostring(e.tifAction or "-") .. "\""
		bits[#bits + 1] = "act " .. (e.tifAct and e.tifAct.name or "-")
		if e.tifCQB then bits[#bits + 1] = "cqb " .. tostring(e.tifCQB.label) end
		if e.tifShield then bits[#bits + 1] = "shield " .. tostring(e.tifShield.varName) .. "/" .. tostring(e.tifShield.phase) end
		if e.tifMelee then bits[#bits + 1] = "melee " .. tostring(e.tifMelee.fight or e.tifMelee.phase) end
		if e.tifMove and e.tifMove.goal then bits[#bits + 1] = string.format("moving (%.0f u to go)", e.tifMove.goal:Distance(p)) end
		if e.tifDead or e.tifDying then bits[#bits + 1] = "dying" end
	else
		bits[#bits + 1] = "state " .. tostring(e.state)
		if e.tifHeld then bits[#bits + 1] = "held" end
		bits[#bits + 1] = "clip " .. tostring(e.civRole)
	end
	return table.concat(bits, ", ")
end

concommand.Add("tif_mark", function(ply, _, args)
	if not TIF.Event then return end
	local from = IsValid(ply) and ply:GetPos() or Vector()
	local note = table.concat(args or {}, " ")
	TIF.Event("MARK", (IsValid(ply) and ply:Nick() or "console"), ": ", note ~= "" and note or "(no note)",
		string.format(" at (%.0f %.0f %.0f)", from.x, from.y, from.z))
	local list = {}
	for _, s in ipairs(TIF.Soldiers or {}) do if IsValid(s) and s:GetPos():Distance(from) < W.MARK_RADIUS then list[#list + 1] = s end end
	if TIF.Civ and TIF.Civ.List then
		for _, c in ipairs(TIF.Civ.List()) do if c:GetPos():Distance(from) < W.MARK_RADIUS then list[#list + 1] = c end end
	end
	table.sort(list, function(a, b) return a:GetPos():DistToSqr(from) < b:GetPos():DistToSqr(from) end)
	for i = 1, math.min(#list, 16) do TIF.Event("MARK", "  ", describe(list[i], from)) end
	if TIF.LogFile then TIF.LogFile.Flush() end
	if IsValid(ply) then ply:ChatPrint("[TIF] Marked in garrysmod/data/tif/log_sv.txt") end
end, nil, "tif_mark [note]: mark this moment in TIF's log file, with what the soldiers and civilians around you are doing")
