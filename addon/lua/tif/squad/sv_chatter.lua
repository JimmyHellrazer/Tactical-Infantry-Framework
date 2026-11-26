local TIF = TIF
TIF.Chatter = TIF.Chatter or {}
local C = TIF.Chatter

C.GAP = { 4, 8 }
C.QUIET_AFTER = 2.5
C.SPAWN_DELAY = { 1, 3 }
C.SPAWN_CHANCE = 0.5
C.CRITICAL = 0.3
C.WEIGHTS = {
	contact = 3,
	suppressing = 3,
	swear = 1.5,
	cover_me = 0,
	moving = 0,
	advance = 0,
}

function C.ContactEvent(e)
	if not IsValid(e) then return "contact" end

	if e.TIFSoldier then
		local w = e.tifWep
		local def = w and w.def
		if def and def.projectile then return "contact_rpg" end

		local kind = w and TIF.GTG.WeaponKind(w.class)
		if kind == "lmg" then return "contact_mg" end

		local arch = e.tifArch
		if arch and arch.id == "marksman" then return "contact_sniper" end

		return "contact"
	end

	if e.IsPlayer and e:IsPlayer() and e.GetActiveWeapon then
		local wep = e:GetActiveWeapon()
		local cls = IsValid(wep) and string.lower(wep:GetClass()) or ""

		if string.find(cls, "rpg", 1, true) or string.find(cls, "launcher", 1, true) or string.find(cls, "at4", 1, true) then
			return "contact_rpg"
		end

		if string.find(cls, "sniper", 1, true) or string.find(cls, "awp", 1, true) or string.find(cls, "svd", 1, true) then
			return "contact_sniper"
		end

		if string.find(cls, "lmg", 1, true) or string.find(cls, "m249", 1, true) or string.find(cls, "pkm", 1, true) then
			return "contact_mg"
		end
	end

	return "contact"
end

local function can_talk(m)
	return IsValid(m) and not m.tifDead and not m.tifDowned and not m.tifSurrendered and not m.tifMelee
		and not m.tifShield
end

local function pick(weights)
	local sum = 0
	for _, w in pairs(weights) do
		sum = sum + w
	end

	if sum <= 0 then return nil end

	local r = math.random() * sum
	for ev, w in pairs(weights) do
		r = r - w
		if r <= 0 then return ev end
	end

	return nil
end

function C.EventFor(m, now)
	local w = {}
	for k, v in pairs(C.WEIGHTS) do
		w[k] = v
	end

	local supp = m.tifSupp or 0
	if supp > 0.5 then
		w.cover_me, w.swear, w.suppressing = 3, 2.5, 1
	end

	if now - (m.GetTIFShotTime and m:GetTIFShotTime() or 0) < 2 then
		w.suppressing = w.suppressing + 2
	end

	local mv = m.tifMove
	if mv and mv.goal then
		w.moving, w.advance = 2.5, (mv.tag == "advance" or m.tifRole == "maneuver") and 2 or 0
	end

	local ev = pick(w)
	if ev == "contact" then
		local c = m.tifPrimaryC
		ev = C.ContactEvent(c and c.ent or m.tifPrimary)
	end

	return ev
end

function C.Tick(sq, now)
	local members = TIF.Squad.Members(sq)
	if #members == 0 then return end

	if not sq.tifSpawnSaid then
		sq.tifSpawnSaid = now + math.Rand(C.SPAWN_DELAY[1], C.SPAWN_DELAY[2])
	elseif sq.tifSpawnSaid ~= true and now >= sq.tifSpawnSaid then
		sq.tifSpawnSaid = true
		local m = members[math.random(#members)]

		if can_talk(m) and m.tifAware ~= TIF.AWARE.ENGAGED then
			TIF.Say(m, "spawn", C.SPAWN_CHANCE)
		end
	end

	local engaged = {}
	for _, m in ipairs(members) do
		if can_talk(m) and m.tifAware == TIF.AWARE.ENGAGED then
			engaged[#engaged + 1] = m
		end
	end

	if #engaged == 0 then
		sq.tifChatNext = nil
		return
	end

	if not sq.tifChatNext then
		sq.tifChatNext = now + math.Rand(C.GAP[1], C.GAP[2]) * 0.5
		return
	end

	if now < sq.tifChatNext then return end

	if now - (sq.tifSaidAt or 0) < C.QUIET_AFTER then
		sq.tifChatNext = now + C.QUIET_AFTER
		return
	end

	local m = engaged[math.random(#engaged)]
	local ev = C.EventFor(m, now)

	if ev then
		TIF.Say(m, ev, 1)
	end

	sq.tifChatNext = now + math.Rand(C.GAP[1], C.GAP[2])
end
