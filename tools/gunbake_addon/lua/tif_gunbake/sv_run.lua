-- Server half: gives the host each roster gun in turn, applies its preset through the MW base, then asks the
-- client to export it once the attachments have reached it.
util.AddNetworkString("tif_gunbake")

local GB = TIF_GUNBAKE
local queue, host, current, timeoutId = {}, nil, nil, "tif_gunbake_timeout"
local mode = "mesh" -- "mesh" (tif_gunbake) or "sounds" (tif_gunbake_sounds: sound names / reload timing only)
local SETTLE = 2.5  -- seconds for the attachment entities to reach the client and the gun to build there

local function say(msg)
	print("[tif_gunbake] " .. msg)
	if IsValid(host) then host:ChatPrint("[tif_gunbake] " .. msg) end
end

local function strip_mw(ply)
	for _, w in ipairs(ply:GetWeapons()) do
		if weapons.IsBasedOn(w:GetClass(), "mg_base") then ply:StripWeapon(w:GetClass()) end
	end
end

local step
local function next_step() timer.Simple(0.3, step) end

step = function()
	timer.Remove(timeoutId)
	if not IsValid(host) then queue = {} return end
	current = table.remove(queue, 1)
	if not current then
		strip_mw(host)
		say("done. Files in garrysmod/data/tif_gunbake/")
		return
	end
	local e = current
	if not weapons.GetStored(e.swep) then
		say(e.id .. ": SWEP " .. e.swep .. " isn't installed, skipped")
		next_step()
		return
	end
	strip_mw(host)
	local w = host:Give(e.swep)
	if not IsValid(w) then
		say(e.id .. ": couldn't give " .. e.swep .. ", skipped")
		next_step()
		return
	end
	host:SelectWeapon(e.swep)
	timer.Simple(0.6, function()
		if not (IsValid(w) and IsValid(host)) then next_step() return end
		mw_utils.LoadPreset(w, { SWEP = e.swep, Name = e.id, Attachments = e.atts })
		timer.Simple(SETTLE, function()
			if not (IsValid(w) and IsValid(host)) then next_step() return end
			net.Start("tif_gunbake")
			net.WriteString(e.id)
			net.WriteEntity(w)
			net.WriteString(mode)
			net.Send(host)
			-- (a client that errors out never answers)
			timer.Create(timeoutId, 20, 1, function()
				say(e.id .. ": no answer from the client, moving on")
				step()
			end)
		end)
	end)
end

local held

net.Receive("tif_gunbake", function(_, ply)
	if ply ~= host then return end

	if held then
		timer.Remove(timeoutId)
		if held.stage == "mesh" and IsValid(held.w) then
			held.stage = "sounds"
			net.Start("tif_gunbake")
			net.WriteString(held.id)
			net.WriteEntity(held.w)
			net.WriteString("held_sounds:" .. held.kind)
			net.Send(host)
			return
		end

		say(held.id .. ": done. Tell Claude where to use it (faction / role), it runs the offline build")
		held = nil
		return
	end

	next_step()
end)

local function allowed(ply)
	return not IsValid(ply) or ply:IsListenServerHost() or game.SinglePlayer()
end

local function start(ply, args, m)
	if not allowed(ply) then return end
	mode = m
	host = IsValid(ply) and ply or player.GetHumans()[1]
	if not IsValid(host) then print("[tif_gunbake] needs a player in game") return end
	if not mw_utils or not mw_utils.LoadPreset then say("the MW base isn't installed") return end
	queue = {}
	for _, e in ipairs(GB.Roster) do
		local want = #args == 0
		for _, a in ipairs(args) do
			if a == e.id or (string.sub(a, -1) == "*" and string.sub(e.id, 1, #a - 1) == string.sub(a, 1, -2)) then
				want = true
			end
		end
		if want then queue[#queue + 1] = e end
	end
	say(#queue .. " gun(s) queued (" .. mode .. ", about " .. math.ceil(#queue * (SETTLE + 1.5)) .. " s). Don't switch weapons while it runs.")
	step()
end

concommand.Add("tif_gunbake", function(ply, _, args) start(ply, args, "mesh") end)
concommand.Add("tif_gunbake_sounds", function(ply, _, args) start(ply, args, "sounds") end)

GB.HELD_KINDS = { rifle = true, smg = true, lmg = true, shotgun = true, pistol = true, rpg = true, dmr = true }

concommand.Add("tif_gunbake_held", function(ply, _, args)
	if not allowed(ply) then return end

	host = IsValid(ply) and ply or player.GetHumans()[1]
	if not IsValid(host) then
		print("[tif_gunbake] needs a player in game")
		return
	end

	local id = string.lower(args[1] or "")
	if not string.match(id, "^[a-z][a-z0-9_]*$") then
		say("usage: tif_gunbake_held <id> [rifle|smg|lmg|shotgun|pistol|rpg|dmr] (id: lowercase letters, digits, _)")
		return
	end

	local kind = string.lower(args[2] or "auto")
	if kind ~= "auto" and not GB.HELD_KINDS[kind] then
		say("unknown kind " .. kind .. ": use rifle, smg, lmg, shotgun, pistol, rpg or dmr")
		return
	end

	if GB.ById[id] and args[3] ~= "force" then
		say(id .. " is a roster gun: pick another id, or add force to overwrite its export")
		return
	end

	local w = host:GetActiveWeapon()
	if not (IsValid(w) and weapons.IsBasedOn(w:GetClass(), "mg_base")) then
		say("hold an MW base weapon (mg_*) set up the way you want it")
		return
	end

	queue, current = {}, nil
	held = { id = id, kind = kind, w = w, stage = "mesh" }
	say(id .. ": exporting the held " .. w:GetClass() .. " (mesh, then sounds). Don't switch weapons")
	net.Start("tif_gunbake")
	net.WriteString(id)
	net.WriteEntity(w)
	net.WriteString("held_mesh:" .. kind)
	net.Send(host)
	timer.Create(timeoutId, 20, 1, function()
		say(id .. ": no answer from the client")
		held = nil
	end)
end)

concommand.Add("tif_gunbake_list", function(ply)
	if not allowed(ply) then return end
	for _, e in ipairs(GB.Roster) do
		print(string.format("%-16s %-16s %-8s %s", e.id, e.swep, e.kind, e.note or ""))
	end
end)
