-- Helicopter test commands (from air/sv_air.lua, 0.38.11).

local TIF = TIF
local Air = TIF.Air

-- Test commands --------------------------------------------------------------------------

local function dev(name, fn, help)
	concommand.Add(name, function(ply, _, args)
		if not TIF.CanUseDev(ply) then return end
		fn(ply, args)
	end, nil, help)
end

local function say(ply, ...)
	local msg = table.concat({ ... }, "")
	if IsValid(ply) then ply:ChatPrint("[TIF] " .. msg) end
	TIF.Log(msg)
end

local function aim(ply)
	return IsValid(ply) and ply:GetEyeTrace().HitPos or Vector()
end

-- Test command arguments in any order: a helicopter type (blackhawk, littlebird, mi8; default: any installed), a
-- mode (auto, land, rope, flyby), a seat set (land, rappel, bench, rope...: after the mode), an exit style (run,
-- ready, patrol), a number (count; with tif_heli: the yaw it comes from), anything else = faction.
local MODES = { auto = true, land = true, rope = true, flyby = true }
local STYLES = { run = true, ready = true, patrol = true }
local function parse(args)
	local o = {}
	for _, a in ipairs(args) do
		a = string.lower(a)
		if Air.Types[a] then o.type = a
		elseif MODES[a] and not o.mode then o.mode = a
		elseif STYLES[a] then o.style = a
		elseif tonumber(a) then o.num = tonumber(a)
		elseif o.mode and not o.set and (a == "rappel" or a == "bench" or a == "land" or a == "rope") then o.set = a
		else o.faction = a end
	end
	if not o.type then
		local list = Air.AvailableTypes()
		o.type = list[math.random(math.max(1, #list))] or "blackhawk"
	end
	return o
end

dev("tif_heli", function(ply, args)
	local o = parse(args)
	local heli, res = Air.Call({ type = o.type, pos = aim(ply), mode = o.mode or "auto", fromYaw = o.num })
	if heli then say(ply, Air.Type(o.type).name, " inbound (", res, ")") else say(ply, "No helicopter: ", tostring(res)) end
end, "Send a helicopter to your crosshair: tif_heli [blackhawk|littlebird|mi8] [auto|land|rope|flyby] [from yaw]")

dev("tif_heli_drop", function(ply, args)
	local o = parse(args)
	local faction = o.faction or "pmc"
	local heli, res = Air.Call({ type = o.type, pos = aim(ply), mode = o.mode or "auto",
		passengers = { faction = faction, count = o.num, set = o.set, style = o.style } })
	if heli then
		say(ply, Air.Type(o.type).name, " inbound with ", #(heli.tifRiders or {}), " ", faction, " (", res, ", seats: ",
			tostring(heli.route and heli.route.setId), ")")
	else say(ply, "No helicopter: ", tostring(res)) end
end, "Fly a squad in to your crosshair: tif_heli_drop [blackhawk|littlebird|mi8] [auto|land|rope] [set] [run|ready|patrol] [faction] [count]")

dev("tif_heli_lz", function(ply)
	local lz, why = Air.CheckLZ(aim(ply), "blackhawk", "auto")
	if lz then say(ply, "LZ ok: ", lz.mode, ", hover hub ", math.Round(lz.hubZ - lz.ground.z), " above ground")
	else say(ply, "LZ no good: ", why) end
end, "Check the spot at your crosshair as a landing zone")

dev("tif_heli_release", function(ply)
	for _, h in ipairs(Air.List()) do h:Release() end
	say(ply, "Helicopters released")
end, "Every helicopter waiting at its LZ leaves now")

dev("tif_heli_kill", function(ply)
	for _, h in ipairs(Air.List()) do
		local d = DamageInfo()
		d:SetDamage(h:Health() + 1)
		d:SetAttacker(IsValid(ply) and ply or game.GetWorld())
		d:SetDamageType(DMG_BLAST)
		h:TakeDamageInfo(d)
	end
end, "Shoot down every helicopter (crash test)")

dev("tif_heli_clear", function(ply)
	for _, h in ipairs(Air.List()) do h:Remove() end
	say(ply, "Helicopters removed")
end, "Remove every helicopter")
