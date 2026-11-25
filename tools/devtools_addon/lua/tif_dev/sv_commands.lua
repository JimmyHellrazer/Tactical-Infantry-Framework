-- TIF dev / test commands (local dev addon, not shipped). Need the listen host, server console or a superadmin.
--   tif_give, tif_reveal, tif_forget, tif_noise, tif_doors, tif_cover_scan, tif_suppress, tif_prone, tif_cover_test,
--   tif_cover_course, tif_info, tif_aimwhy, tif_shield_test

local TIF = TIF

local function dev(name, fn, help)
	concommand.Add(name, function(ply, cmd, args)
		if not TIF.CanUseDev(ply) then return end
		fn(ply, args)
	end, nil, help)
end

local function crosshair(ply)
	local tr = ply:GetEyeTrace()
	return tr.HitPos
end

dev("tif_give", function(ply, args)
	if not IsValid(ply) then return end
	local class = args[1]
	if not class or not TIF.GTG.WeaponDef(class) then
		TIF.Log("Unknown weapon class: ", tostring(class), " (baked MW guns are weapon_tifmw_<id>)")
		return
	end
	local list = {}
	if args[2] == "all" then
		list = table.Copy(TIF.Soldiers)
	else
		local e = ply:GetEyeTrace().Entity
		if IsValid(e) and e.TIFSoldier then list = { e } end
	end
	for _, npc in ipairs(list) do
		if IsValid(npc) then
			local sec = npc.tifArms and npc.tifArms.secondary
			TIF.Weapon.Init(npc, class, sec and sec.class or nil)
		end
	end
	TIF.Log("Gave ", class, " to ", #list, " soldier(s)")
end, "tif_give <weapon class> [all]: the soldier you look at (or every soldier) takes this primary")

dev("tif_reveal", function(ply)
	if not IsValid(ply) then return end
	TIF.Perception.Reveal(ply)
	TIF.Log("Every hostile soldier now knows where you are")
end, "Every hostile soldier spots you")

dev("tif_forget", function()
	TIF.Perception.ForgetSight()
	TIF.Log("All soldiers lost sight of their targets (they keep the last known positions)")
end, "Every soldier loses sight of everyone; they keep last known positions and start searching")

dev("tif_noise", function(ply)
	if not IsValid(ply) then return end
	local pos = crosshair(ply)
	TIF.Events.Emit("gunfire", pos, GetConVar("tif_gunfire_radius"):GetFloat(), ply, TIF.FactionOf(ply))
	TIF.Log("Gunshot sound emitted at ", tostring(pos))
end, "A gunshot sound at your crosshair, as if you fired there")

-- Phase 5: buildings -------------------------------------------------------------

dev("tif_doors", function(ply, args)
	if not IsValid(ply) then return end
	local pos = ply:GetEyeTrace().HitPos
	local t0 = SysTime()
	local list = TIF.Building.Scan(pos, tonumber(args[1]) or 1200)
	local ext, int, ent = 0, 0, 0
	for _, d in ipairs(list) do
		if d.exterior then ext = ext + 1 else int = int + 1 end
		if IsValid(d.ent) then ent = ent + 1 end
	end
	TIF.CQB.ShowDoors = { list = list, untilT = CurTime() + 60 }
	local room = TIF.Building.RoomAt(pos)
	ply:ChatPrint(string.format("[TIF] %d doorways near your crosshair (%d exterior, %d interior, %d door entities) in %.1f ms. %s",
		#list, ext, int, ent, (SysTime() - t0) * 1000,
		room and ("Crosshair room: " .. #room.areas .. " nav areas") or "Crosshair is outdoors"))
end, "tif_doors [radius]: find doorways near your crosshair and draw them for 60 s (tif_debug 1)")

-- Phase 2 ----------------------------------------------------------------------

local function looked_soldiers(ply, coneDeg)
	local out = {}
	local eye, aim = ply:EyePos(), ply:GetAimVector()
	local cosHalf = math.cos(math.rad(coneDeg or 12))
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) and not npc.tifDead then
			local to = npc:WorldSpaceCenter() - eye
			to:Normalize()
			if to:Dot(aim) >= cosHalf then out[#out + 1] = npc end
		end
	end
	return out
end

dev("tif_cover_scan", function(ply, args)
	if not IsValid(ply) then return end
	-- Aiming at a wall puts the crosshair on its surface: step back off it and drop to the floor.
	local et = ply:GetEyeTrace()
	local center = et.HitPos + et.HitNormal * 32
	local down = util.TraceLine({ start = center + Vector(0, 0, 8), endpos = center - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
	if down.Hit then center = down.HitPos end
	-- A throwaway "soldier" stand-in so scoring has an archetype and a position.
	local probe = { tifArch = TIF.Archetype(args[1]), GetPos = function() return center end }
	setmetatable(probe, { __index = function(_, k) return nil end })
	local best, stats = TIF.Cover.Find(probe, ply:GetPos(), { center = center, radius = tonumber(args[2]) or 600 })
	local parts = {}
	for k, v in SortedPairs(stats or {}) do parts[#parts + 1] = k .. "=" .. tostring(v) end
	TIF.Log("Search: ", table.concat(parts, "  "))
	if best then
		TIF.Log(string.format("Best cover vs you: %s, %s, score %.1f (%s)", best.high and "high" or "low",
			best.canShoot and "can shoot" or "hide only", best.score, best.why or ""))
	else
		TIF.Log("No usable cover near the crosshair against you")
	end
	TIF.Log("Turn on tif_debug 1 and tif_debug_cover 1 to see every evaluated point")
end, "tif_cover_scan [archetype] [radius]: evaluate cover around your crosshair, with you as the threat")

dev("tif_suppress", function(ply, args)
	if not IsValid(ply) then return end
	local amount = tonumber(args[1]) or 0.8
	local list = looked_soldiers(ply, 15)
	for _, npc in ipairs(list) do TIF.Supp.Add(npc, amount / math.max(0.05, 1 - npc.tifArch.suppressResist), ply:EyePos(), ply) end
	TIF.Log("Suppressed ", #list, " soldier(s) in your view")
end, "tif_suppress [amount 0-1]: suppress the soldiers you're looking at (as if you were shooting at them)")

dev("tif_prone", function(ply)
	if not IsValid(ply) then return end
	local npc = ply:GetEyeTrace().Entity
	if not (IsValid(npc) and npc.TIFSoldier) then TIF.Log("Look at a TIF soldier") return end
	if TIF.ProneB.Is(npc) then
		TIF.ProneB.GetUp(npc)
		TIF.Log("Getting up")
	elseif TIF.ProneB.GoDown(npc, "dev") then
		TIF.Log("Going prone (it gets up again when it's not fighting)")
	else
		TIF.Log("Can't go prone here (no room, or the body has no prone clips)")
	end
end, "Toggle prone on the soldier you're looking at")

dev("tif_cover_test", function(ply, args)
	if not IsValid(ply) then return end
	local spawned = TIF.SpawnSoldiers(ply, args[1] or "militia", tonumber(args[2]) or 1, args[3] or "rifleman", crosshair(ply), "me")
	timer.Simple(0.5, function()
		if IsValid(ply) then TIF.Perception.Reveal(ply) end
	end)
	TIF.Log("Spawned ", #spawned, " soldier(s) that know where you are. Watch them pick and use cover.")
end, "tif_cover_test [faction] [count] [archetype]: spawn soldiers at your crosshair that already know where you are")

-- A fair low-cover test: a row of waist-high props between you and freshly spawned soldiers.
local COURSE_PROPS = {
	"models/props_c17/concrete_barrier001a.mdl",
	"models/props_junk/wood_crate001a.mdl",
	"models/props_c17/concrete_barrier001a.mdl",
	"models/props_junk/wood_crate001a.mdl",
}

dev("tif_cover_course", function(ply, args)
	if not IsValid(ply) then return end
	local fwd = ply:GetAimVector()
	fwd.z = 0
	fwd:Normalize()
	local right = Vector(fwd.y, -fwd.x, 0)
	local base = ply:GetPos()
	local soldierDist = tonumber(args[3]) or 1100
	local propDist = soldierDist - 350
	undo.Create("TIF Cover Course")
	for i, model in ipairs(COURSE_PROPS) do
		local p = base + fwd * propDist + right * ((i - 2.5) * 170)
		local g = util.TraceLine({ start = p + Vector(0, 0, 200), endpos = p - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY })
		local prop = ents.Create("prop_physics")
		if IsValid(prop) and g.Hit then
			prop:SetModel(model)
			prop:SetAngles(Angle(0, fwd:Angle().y + 90, 0))
			prop:SetPos(g.HitPos)
			prop:Spawn()
			prop:SetPos(g.HitPos - Vector(0, 0, prop:OBBMins().z))
			local phys = prop:GetPhysicsObject()
			if IsValid(phys) then phys:EnableMotion(false) end
			undo.AddEntity(prop)
		end
	end
	undo.SetPlayer(ply)
	undo.Finish()
	-- Spawn tightly, well behind the props, so the props are actually between them and you.
	local spawned = TIF.SpawnSoldiers(ply, args[1] or "militia", tonumber(args[2]) or 2, "rifleman",
		base + fwd * soldierDist, "me", { radius = 110 })
	timer.Simple(0.5, function()
		if IsValid(ply) then TIF.Perception.Reveal(ply) end
	end)
	TIF.Log("Cover course: 4 waist-high props ", propDist, " units ahead, ", #spawned, " soldiers ", soldierDist,
		" units ahead who know where you are. Stay back; undo removes the props.")
end, "tif_cover_course [faction] [count] [distance]: waist-high props between you and new soldiers, to test low cover")

dev("tif_info", function(ply)
	if not IsValid(ply) then return end
	local npc = ply:GetEyeTrace().Entity
	if not (IsValid(npc) and npc.TIFSoldier) then TIF.Log("Look at a TIF soldier") return end
	local now = CurTime()
	TIF.Log(tostring(npc), " ", npc:GetTIFFaction(), " / ", npc.tifArchId, " | ", TIF.AWARE_NAMES[npc.tifAware], " | ", npc.tifAction or "")
	local parts = {}
	for k, v in SortedPairs(npc.tifCoverStats or {}) do parts[#parts + 1] = k .. "=" .. tostring(v) end
	MsgN("  last cover search: ", #parts > 0 and table.concat(parts, "  ") or "none yet",
		npc.tifCoverLeaveReason and ("  | last left cover: " .. npc.tifCoverLeaveReason) or "")
	MsgN(string.format("  suppression %.2f  prone %s", npc.tifSupp or 0, tostring(npc.tifProne and npc.tifProne.phase)))
	for e, c in pairs(npc.tifK.contacts) do
		MsgN(string.format("  %s  confirmed=%s visible=%s meter=%.2f seen %.1fs ago heard %.1fs ago unc=%d source=%s",
			tostring(e), tostring(c.confirmed), tostring(c.visible), c.meter,
			now - c.seenAt, now - c.heardAt, c.unc or 0, c.source or "-"))
	end
end, "Print what the soldier you're looking at knows")

-- Why he aims where he does (0.35.3, user: soldiers aiming high). Server side here, the client's leg / upper-body
-- clips and spine bend from tif_aimwhy_cl (cl_debug). Both append to data/tif/reports/aimwhy.txt.
dev("tif_aimwhy", function(ply)
	if not IsValid(ply) then return end
	local npc = ply:GetEyeTrace().Entity
	if not (IsValid(npc) and npc.TIFSoldier) then
		-- nearest soldier to the crosshair
		local best, bd = nil, 0.97
		local ep, ad = ply:EyePos(), ply:GetAimVector()
		for _, e in ipairs(ents.GetAll()) do
			if e.TIFSoldier and not e.tifDead then
				local d = (e:WorldSpaceCenter() - ep):GetNormalized():Dot(ad)
				if d > bd then best, bd = e, d end
			end
		end
		npc = best
	end
	if not IsValid(npc) then TIF.Log("Look at a TIF soldier") return end
	local L = {}
	local function line(...) L[#L + 1] = table.concat({ ... }) end
	local eye = TIF.EyeOf(npc)
	line("== ", tostring(npc), " ", os.date("%H:%M:%S"), "  TIF ", TIF.Version)
	line("action: ", tostring(npc.tifAction), " | aware ", tostring(TIF.AWARE_NAMES[npc.tifAware]), " | mode ", tostring(npc.tifMode),
		" | stance ", tostring(npc.tifStance), " (net ", tostring(npc:GetTIFStance()), ")")
	local function pt(name, p)
		if not p then line(name, ": none") return end
		local d = p - eye
		line(string.format("%s: dz %+.0f, dist %.0f -> pitch %+.1f (+ = down)", name, d.z, d:Length2D(),
			-math.deg(math.atan2(d.z, math.max(1, d:Length2D())))))
	end
	pt("tifFace", npc.tifFace)
	pt("tifAimAt", npc.tifAimAt)
	pt("fire aimPos", npc.tifFire and npc.tifFire.want and npc.tifFire.aimPos or nil)
	line(string.format("aim pitch: server %.1f, net %.1f", npc.tifPitch or 0, npc:GetTIFAimPitch()))
	local cq = npc.tifCQB
	line("cqb: ", cq and (tostring(cq.label) .. " lowReady=" .. tostring(cq.lowReady)) or "no", " | nw cqb ", tostring(npc:GetNW2Bool("tif_cqb", false)),
		" | lowready ", tostring(npc:GetNW2Bool("tif_lowready", false)), " | rungun '", npc:GetNW2String("tif_rungun", ""), "'",
		" | wade ", tostring(npc:GetNW2Int("tif_wade", 0)), " | light ", tostring(npc:GetNW2Bool("tif_light", false)))
	line("act: ", npc.tifAct and npc.tifAct.name or "none", " | nw act '", npc:GetNW2String("tif_act", ""), "' | cover ",
		npc.tifCov and (tostring(npc.tifCov.t) .. " " .. tostring(npc.tifCov.phase)) or "no", " | weapon ", npc:GetTIFWeapon())
	for _, s in ipairs(L) do MsgN(s) end
	file.CreateDir("tif/reports")
	file.Append("tif/reports/aimwhy.txt", table.concat(L, "\n") .. "\n")
	ply:ConCommand("tif_aimwhy_cl " .. npc:EntIndex())
end, "Why the soldier you look at aims where he does (writes data/tif/reports/aimwhy.txt)")

-- (0.38.20) Human shield on demand: the soldier you look at (else the nearest to your crosshair) takes the nearest
-- civilian hostage (TIF.Shield.Start: the civilian is put on the grab's start spot). "held": already holding.
dev("tif_shield_test", function(ply, args)
	if not (IsValid(ply) and TIF.Shield and TIF.Civ) then return end
	local at = crosshair(ply)
	local npc = ply:GetEyeTrace().Entity
	if not (IsValid(npc) and npc.TIFSoldier) then
		npc = nil
		local bd
		for _, s in ipairs(TIF.Soldiers) do
			local d = IsValid(s) and not s.tifDead and s:GetPos():DistToSqr(at)
			if d and (not bd or d < bd) then npc, bd = s, d end
		end
	end
	if not npc then TIF.Log("tif_shield_test: no soldier") return end
	local civ, cd
	for _, c in ipairs(TIF.Civ.List()) do
		local d = not c.tifHeld and c:GetPos():DistToSqr(npc:GetPos())
		if d and (not cd or d < cd) then civ, cd = c, d end
	end
	if not civ then TIF.Log("tif_shield_test: no civilian (spawn one: tif_civilian)") return end
	-- (0.38.28) "ch": Clean House's held-in-front variant
	local sc = TIF.Shield.Start(npc, civ, { held = args[1] == "held", variant = args[1] == "ch" and "ch" or nil })
	TIF.Log(sc and ("tif_shield_test: soldier " .. npc:EntIndex() .. " holds civilian " .. civ:EntIndex())
		or "tif_shield_test: couldn't start (busy soldier, or the clips missing on this body)")
end, "tif_shield_test [held|ch]: the soldier you look at (or nearest your crosshair) takes the nearest civilian hostage (ch: Clean House, held in front)")
