-- Death clip housekeeping (from tactics/sv_hits_mw.lua, 0.38.11).

local TIF = TIF
local H = TIF.HitsMW

-- Death clip housekeeping (admins / single player).
local function allowed(ply) return not IsValid(ply) or ply:IsAdmin() or game.SinglePlayer() end
local function say(ply, msg) if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end end

concommand.Add("tif_deaths_recent", function(ply)
	if not allowed(ply) then return end
	if #H.Recent == 0 then say(ply, "[TIF] no MW19 deaths played yet") return end
	local now = CurTime()
	for i, r in ipairs(H.Recent) do
		say(ply, string.format("[TIF] %d. %.0fs ago  %s  (%s, source %s)", i, now - r.t, r.name, r.sit, tostring(r.src)))
	end
	say(ply, "[TIF] tif_death_ban <number from this list, or a name> takes one out")
end)

concommand.Add("tif_death_ban", function(ply, _, args)
	if not allowed(ply) then return end
	local a = args[1]
	if not a then say(ply, "[TIF] tif_death_ban <n | clip name>") return end
	local r = tonumber(a) and H.Recent[tonumber(a)]
	local name = r and (r.src or r.name) or a
	H.Banned[name] = true
	H.SaveBans()
	say(ply, "[TIF] banned " .. name .. " (data/" .. H.BAN_FILE .. ")")
end)

concommand.Add("tif_death_unban", function(ply, _, args)
	if not allowed(ply) or not args[1] then return end
	H.Banned[args[1]] = nil
	H.SaveBans()
	say(ply, "[TIF] unbanned " .. args[1])
end)
