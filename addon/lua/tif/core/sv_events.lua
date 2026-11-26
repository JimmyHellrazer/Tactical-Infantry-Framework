local TIF = TIF
local Prof = TIF.Prof
TIF.Events = TIF.Events or {}
local E = TIF.Events

local cvGunfire = CreateConVar("tif_gunfire_radius", "3500", FCVAR_ARCHIVE, "How far unsuppressed gunfire carries (units)")

E.Recent = E.Recent or {}
local RECENT_MAX = 24

function E.Emit(kind, pos, radius, src, faction)
	Prof.Begin("events")
	local r = E.Recent
	r[#r + 1] = { kind = kind, pos = pos, radius = radius, time = CurTime() }
	if #r > RECENT_MAX then table.remove(r, 1) end
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) and not npc.tifDead and npc ~= src then
			local reach = radius * (npc.tifArch and npc.tifArch.hearing or 1)
			local d2 = npc:GetPos():DistToSqr(pos)
			if d2 < reach * reach then npc:TIFHear(kind, pos, d2, src, faction) end
		end
	end
	Prof.End()
end

local function suppressed(ent)
	local w = ent.GetActiveWeapon and ent:GetActiveWeapon()
	if not IsValid(w) then return false end
	if w.Silenced or w.Suppressed or w.IsSilenced then return true end
	local c = w:GetClass()
	return string.find(c, "_sd", 1, true) ~= nil or string.find(c, "suppress", 1, true) ~= nil
end

local lastShotEvent = setmetatable({}, { __mode = "k" })
hook.Add("EntityFireBullets", "tif_events", function(ent, data)
	if not IsValid(ent) then return end

	local now = CurTime()
	if (lastShotEvent[ent] or 0) > now - 0.12 then return end
	lastShotEvent[ent] = now
	local radius = suppressed(ent) and 700 or cvGunfire:GetFloat()
	E.Emit("gunfire", data.Src or ent:GetPos(), radius, ent, TIF.FactionOf(ent))
end)

local lastStep = setmetatable({}, { __mode = "k" })
hook.Add("PlayerFootstep", "tif_events", function(ply, pos)
	local now = CurTime()
	if (lastStep[ply] or 0) > now - 0.3 then return end
	lastStep[ply] = now
	local speed = ply:GetVelocity():Length2D()
	local radius
	if ply:Crouching() or ply:KeyDown(IN_WALK) or (ply.IsProne and ply:IsProne()) then radius = 90
	elseif speed > 220 then radius = 550
	else radius = 260 end
	E.Emit("footstep", pos, radius, ply, TIF.FactionOf(ply))
end)

local lastBlast = 0
hook.Add("EntityTakeDamage", "tif_events", function(target, dmg)
	if not dmg:IsDamageType(DMG_BLAST) then return end
	local now = CurTime()
	if lastBlast > now - 0.25 then return end
	lastBlast = now
	E.Emit("explosion", dmg:GetDamagePosition(), 4500, dmg:GetAttacker(), TIF.FactionOf(dmg:GetAttacker()))
end)
