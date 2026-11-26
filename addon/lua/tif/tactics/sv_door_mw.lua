local TIF = TIF
local Act = TIF.Action

TIF.DoorMW = TIF.DoorMW or {}
local D = TIF.DoorMW

D.CONTACT = { tac = 0.36, shoulder = 0.5, kick = 0.3 }
D.RUN_SPEED = 160
D.LOOK = 110
D.CHECK_EVERY = 0.2
D.HANDU = 0.8
local cv = CreateConVar("tif_door_anims", "1", FCVAR_ARCHIVE, "Soldiers open doors in their way with MW19's door animations")

local function closed_door(e)
	if not (IsValid(e) and e:GetClass() == "prop_door_rotating") then
		return false
	end
	local ok, st = pcall(e.GetInternalVariable, e, "m_eDoorState")
	if ok and st ~= nil and st ~= 0 then return false end
	local okL, locked = pcall(e.GetInternalVariable, e, "m_bLocked")
	return not (okL and locked == true)
end

local variantCache = {}
local function variants(host, side, kind)
	local key = tostring(host) .. ":" .. side .. ":" .. kind
	local cached = variantCache[key]
	if cached then return cached end
	local out = {}
	for _, v in ipairs({ "a", "b", "c" }) do
		local n = "mwdr_" .. side .. "_" .. kind .. "_" .. v
		local c = TIF.GTG.Clip(n, host)
		if c then
			out[#out + 1] = { name = n, clip = c }
		end
	end

	variantCache[key] = out
	return out
end

D.TOUCH = 44

function D.Check(npc, m, now)
	if not cv:GetBool() or npc.tifCQB or npc.tifVeh or npc.tifDowned or npc.tifCov then
		return false
	end
	if now < (npc.tifNextDoorCheck or 0) then return false end
	local host = npc.tifHomeHost
	local canClip = not npc.tifAct and not npc.tifProne and host and npc.tifHostId == host and TIF.GTG.IsVB(host)
		and npc:GetTIFStance() ~= TIF.Anim.STANCE_CROUCH
	npc.tifNextDoorCheck = now + D.CHECK_EVERY
	local v = npc.loco:GetVelocity()
	v.z = 0
	local speed = v:Length()
	if speed < 30 then return false end
	local dir = v:GetNormalized()
	local pos = npc:GetPos()
	local best, bestD
	for _, e in ipairs(ents.FindInSphere(pos + dir * (D.LOOK * 0.5) + Vector(0, 0, 40), D.LOOK * 0.6)) do
		if closed_door(e) then

			local mid = e:WorldSpaceCenter()
			local ahead = (mid - pos):Dot(dir)
			local side = math.abs((mid - pos):Dot(Vector(-dir.y, dir.x, 0)))
			if ahead > -6 and ahead < D.LOOK and side < 48 and (not bestD or ahead < bestD) then
				best, bestD = e, ahead
			end
		end
	end

	if not best then return false end
	local started, waiting = false, false
	if canClip then
		started, waiting = D.PlayClip(npc, best, bestD, speed, dir, pos, now)
	end

	if started then return true end

	if not waiting and bestD < D.TOUCH then
		best:Fire("OpenAwayFrom", "!activator", 0, npc)
		npc.tifNextDoorCheck = now + 0.6
	end

	return false
end

function D.PlayClip(npc, best, bestD, speed, dir, pos, now)
	local host = npc.tifHomeHost
	local kind = speed > D.RUN_SPEED and (math.random() < 0.5 and "shoulder" or "kick") or "tac"

	local right = Vector(dir.y, -dir.x, 0)
	local hingeRight = (best:GetPos() - pos):Dot(right) > 0
	local cands = {}
	for _, s in ipairs({ "l", "r" }) do
		for _, e in ipairs(variants(host, s, kind)) do
			local drift = e.clip.move[2] or 0
			if (drift > 0) == hingeRight or math.abs(drift) < 4 then
				cands[#cands + 1] = e
			end
		end
	end

	if #cands == 0 and kind ~= "tac" then
		kind = "tac"
		for _, s in ipairs({ "l", "r" }) do
			for _, e in ipairs(variants(host, s, kind)) do
				if ((e.clip.move[2] or 0) > 0) == hingeRight then
					cands[#cands + 1] = e
				end
			end
		end
	end

	if #cands == 0 then return false end
	local pick = cands[math.random(#cands)]
	local u = D.CONTACT[kind] or 0.35
	local xc = Act.RootAt(pick.clip, u)

	if bestD > xc + 10 then return false, true end
	npc:SetAngles(Angle(0, dir:Angle().y, 0))
	local d = Act.Play(npc, pick.name, { root = true, clear = true, noTrace = true })
	if not d then return false end
	npc.tifAct.trans = true
	npc.tifAct.handU = D.HANDU
	local door = best
	local clipName = pick.name
	timer.Simple(d * u, function()
		if not (IsValid(door) and IsValid(npc)) or npc.tifDead then return end
		if not (npc.tifAct and npc.tifAct.name == clipName) then return end
		if kind ~= "tac" then
			door:Fire("SetSpeed", "400")
			door:EmitSound("physics/wood/wood_furniture_break" .. math.random(1, 2) .. ".wav", 80, math.random(95, 105))
		end
		door:Fire("OpenAwayFrom", "!activator", 0, npc)
	end)
	npc.tifAction = "door: " .. pick.name
	return true
end
