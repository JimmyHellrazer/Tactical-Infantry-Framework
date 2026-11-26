local TIF = TIF
local B = TIF.Base

local function dev(name, fn, help)
	concommand.Add(name, function(ply, cmd, args)
		if not TIF.CanUseDev(ply) then return end
		fn(ply, args)
	end, nil, help)
end

local function say(ply, ...)
	local msg = table.concat({ ... }, "")
	TIF.Log(msg)
	if IsValid(ply) then
		ply:ChatPrint("[TIF] " .. msg)
	end
end

dev("tif_base_garrison", function(ply, args)
	local name = args[1]
	local def = (name == "draft" and B.Draft) or B.FindDef(name)
	if not def then
		say(ply, "No base '", tostring(name or "(preset)"), "' for ", game.GetMap(), ". tif_base_list shows what exists; tif_base_new builds one.")
		return
	end

	if navmesh.GetNavAreaCount() == 0 then
		say(ply, "This map has no navmesh: run nav_generate first.")
		return
	end

	local base = B.Garrison(def)
	say(ply, "Base '", base.name, "' garrisoned with ", base.startSize, " soldiers")
end, "tif_base_garrison [name|draft]: spawn a base's garrison")

dev("tif_base_clear", function(ply)
	local n = 0
	for _, base in pairs(table.Copy(B.List)) do
		B.Remove(base) n = n + 1
	end

	say(ply, "Removed ", n, " base(s)")
end, "Remove all bases and their soldiers")

dev("tif_base_info", function(ply)
	local now = CurTime()
	local any = false
	for _, base in pairs(B.List) do
		any = true
		local jobs = {}
		for _, m in ipairs(base.members) do
			local j = (m.tifJob or "?"):match("^(%a+)")
			jobs[j] = (jobs[j] or 0) + 1
		end
		local parts = {}
		for j, n in pairs(jobs) do
			parts[#parts + 1] = j .. " " .. n
		end
		say(ply, "Base '", base.name, "': ", string.upper(B.LEVEL_NAMES[base.level]), " for ", math.floor(now - base.levelSince),
			" s, ", #base.members, "/", base.startSize, " alive (", table.concat(parts, ", "), ")",
			base.reinforced and ", reinforced" or "")
	end

	if not any then
		say(ply, "No bases. tif_base_garrison spawns one.")
	end
end, "Print each base's alert level and garrison")

dev("tif_base_level", function(ply, args)
	local want = ({ calm = B.CALM, alert = B.ALERT, alarm = B.ALARM })[args[1] or ""]
	if not want then
		say(ply, "tif_base_level <calm|alert|alarm>")
		return
	end

	local now = CurTime()
	for _, base in pairs(B.List) do
		if want == B.ALARM then

			if IsValid(ply) then
				base.knowledge[ply] = { pos = ply:GetPos(), vel = Vector(), time = now }
			end
			base.alarmAt = now
		else
			B.SetLevel(base, want, now, "forced")
		end
	end

	say(ply, "Bases set to ", args[1])
end, "tif_base_level <calm|alert|alarm>: force every base's level (alarm points them at you)")

dev("tif_base_list", function(ply)
	local presets = {}
	for name in pairs(B.Presets()) do
		presets[#presets + 1] = name
	end

	local saved = {}
	for _, f in ipairs(file.Find("tif/bases/" .. game.GetMap() .. "_*.json", "DATA")) do
		saved[#saved + 1] = f:sub(#game.GetMap() + 2, -6)
	end

	say(ply, "Presets: ", #presets > 0 and table.concat(presets, ", ") or "none",
		"   Saved: ", #saved > 0 and table.concat(saved, ", ") or "none")
end, "List saved and preset bases for this map")

local function draft(ply)
	if not B.Draft then
		say(ply, "No draft: tif_base_new <name> first")
	end
	return B.Draft
end

dev("tif_base_new", function(ply, args)
	if not IsValid(ply) then return end
	B.Draft = {
		name = args[1] or "base", faction = args[2] or "insurgents", radius = tonumber(args[3]) or 1800,
		center = ply:GetPos(), posts = {}, routes = {},
	}
	say(ply, "Draft base '", B.Draft.name, "' (", B.Draft.faction, ") centred here. Add posts, routes, then tif_base_save.")
end, "tif_base_new <name> [faction] [radius]: start a base draft centred on you")

dev("tif_base_post", function(ply, args)
	local d = draft(ply)
	if not d or not IsValid(ply) then return end
	local job = args[1] == "reserve" and "reserve" or "post"
	d.posts[#d.posts + 1] = { pos = ply:GetPos(), yaw = math.Round(ply:EyeAngles().y), job = job, arch = args[2] }
	d.lastAdd = "post"
	say(ply, job, " #", #d.posts, " added")
end, "tif_base_post [post|reserve] [archetype]: add a guard post or reserve spot here, facing where you look")

dev("tif_base_route", function(ply, args)
	local d = draft(ply)
	if not d or not IsValid(ply) then return end
	d.routes[#d.routes + 1] = { size = math.Clamp(tonumber(args[1]) or 3, 1, 8), pts = { ply:GetPos() } }
	d.lastAdd = "point"
	say(ply, "Route #", #d.routes, " started here; add points with tif_base_point")
end, "tif_base_route [size]: start a patrol route here")

dev("tif_base_point", function(ply)
	local d = draft(ply)
	if not d or not IsValid(ply) then return end
	local r = d.routes[#d.routes]
	if not r then
		say(ply, "No route: tif_base_route first")
		return
	end

	r.pts[#r.pts + 1] = ply:GetPos()
	d.lastAdd = "point"
	say(ply, "Route #", #d.routes, " point ", #r.pts)
end, "tif_base_point: add your position to the last route")

dev("tif_base_reinforce", function(ply, args)
	local d = draft(ply)
	if not d or not IsValid(ply) then return end
	d.reinforce = { pos = ply:GetPos(), size = math.Clamp(tonumber(args[1]) or 6, 2, 8) }
	say(ply, "Reinforcements will arrive here (", d.reinforce.size, ")")
end, "tif_base_reinforce [size]: reinforcements arrive at your position")

dev("tif_base_undo", function(ply)
	local d = draft(ply)
	if not d then return end
	if d.lastAdd == "point" and #d.routes > 0 then
		local r = d.routes[#d.routes]
		table.remove(r.pts)
		if #r.pts == 0 then
			table.remove(d.routes)
		end
		say(ply, "Removed the last route point")
	elseif #d.posts > 0 then
		table.remove(d.posts)
		say(ply, "Removed the last post")
	end
end, "Remove the last post or route point from the draft")

dev("tif_base_save", function(ply)
	local d = draft(ply)
	if not d then return end
	file.CreateDir("tif/bases")
	local path = B.SavedPath(d.name)
	file.Write(path, util.TableToJSON(B.Serialize(d), true))
	say(ply, "Saved to data/", path, ". tif_base_garrison ", d.name, " spawns it.")
end, "Save the draft base for this map")
