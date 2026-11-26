-- Suppression: incoming fire builds pressure (0..1) that changes decisions, not just aim.
-- Sources: bullets passing close, hits, nearby explosions. Decays over time; archetypes resist
-- differently (a guard panics, a support gunner shrugs).

local TIF = TIF
local Prof = TIF.Prof

TIF.Supp = TIF.Supp or {}
local S = TIF.Supp

local NEAR = 90           -- a bullet passing within this distance of the chest counts
local PER_ROUND = 0.16    -- pressure from one close round at zero distance
local DECAY = 0.22        -- per second, before resistance
local MAX_RANGE = 8000

function S.Add(npc, amount, srcPos, shooter)
	if not IsValid(npc) or npc.tifDead then return end
	local resist = npc.tifArch and npc.tifArch.suppressResist or 0.3
	local before = npc.tifSupp or 0
	local after = math.min(1, before + amount * (1 - resist))
	npc.tifSupp = after
	npc.tifSuppAt = CurTime()
	npc:SetTIFSupp(after)
	if before < 0.45 and after >= 0.45 then TIF.Say(npc, "swear", 0.5) end
	-- Rounds snapping past reveal roughly where they came from.
	if IsValid(shooter) and srcPos and TIF.Perception.OnSuppressed then
		TIF.Perception.OnSuppressed(npc, shooter, srcPos)
	end
end

function S.Decay(npc, dt)
	local s = npc.tifSupp or 0
	if s <= 0 then return end
	local resist = npc.tifArch and npc.tifArch.suppressResist or 0.3
	-- Pressure holds for a moment after the last round before fading.
	if CurTime() - (npc.tifSuppAt or 0) < 0.6 then return end
	s = math.max(0, s - dt * DECAY * (1 + resist))
	npc.tifSupp = s
	if math.abs(npc:GetTIFSupp() - s) > 0.03 or s == 0 then npc:SetTIFSupp(s) end
end

-- Whizby flinch (MW19 AI sdr_cqb_strafe_whizby, ~0.9 s): a round snapping close past a soldier, now and then.
-- (0.38.6) Those clips are additive data: played as a full-body action (mwz_whizby_<n>, until 0.38.5) they drew him
-- as a rigid stick figure for about a second, the user's "crumple". Now they're delta layers (mwzw_<n>) the clients
-- lay over whatever he's doing (cl_body, from NW2 tif_whizby_t / _n): standing, walking or crouched. He only checks
-- his fire for a moment.
S.WHIZBY_CHANCE, S.WHIZBY_COOLDOWN = 0.3, 4
function S.Whizby(npc, now)
	if now < (npc.tifNextWhizby or 0) or math.random() > S.WHIZBY_CHANCE then return end
	npc.tifNextWhizby = now + S.WHIZBY_COOLDOWN
	if npc.tifProne or npc.tifVeh or npc.tifDowned or npc.tifKnock or npc.tifDying then return end
	if npc.loco:GetVelocity():Length2DSqr() > 200 * 200 then return end
	local host = npc.tifHomeHost
	if not (host and TIF.GTG.Clip("mwzw_1", host)) then return end
	local n = 0
	for i = 1, 9 do if TIF.GTG.Clip("mwzw_" .. i, host) then n = i end end
	npc:SetNW2Int("tif_whizby_n", math.random(n))
	npc:SetNW2Float("tif_whizby_t", now)
	npc.tifReactUntil = math.max(npc.tifReactUntil or 0, now + 0.3)
end

-- Every bullet: who did it pass close to? Plain vector math, no traces.
hook.Add("EntityFireBullets", "tif_suppression", function(shooter, data)
	if #TIF.Soldiers == 0 or not data.Dir then return end
	if IsValid(shooter) and shooter:IsPlayer() and TIF.IgnorePlayers() then return end
	Prof.Begin("suppression")
	local src = data.Src or shooter:GetPos()
	local dir = Vector(data.Dir)
	dir:Normalize()
	local maxD = math.min(data.Distance or MAX_RANGE, MAX_RANGE)
	local rounds = math.Clamp(data.Num or 1, 1, 8)
	local dmg = data.Damage and data.Damage > 0 and math.Clamp(data.Damage / 25, 0.5, 2) or 1
	for _, npc in ipairs(TIF.Soldiers) do
		if npc ~= shooter and IsValid(npc) and not npc.tifDead then
			local v = npc:WorldSpaceCenter() - src
			local t = v:Dot(dir)
			if t > 60 and t < maxD then
				local perp = (v - dir * t):Length()
				if perp < NEAR and TIF.Relation(npc, shooter) ~= TIF.REL_ALLY then
					S.Add(npc, (1 - perp / NEAR) * PER_ROUND * dmg * math.sqrt(rounds), src, shooter)
					-- A close one: sometimes MW19's whizby flinch (standing, free, not in cover).
					if perp < NEAR * 0.5 and S.Whizby then S.Whizby(npc, CurTime()) end
				end
			end
		end
	end
	Prof.End()
end)

local lastBlast = { pos = Vector(), time = 0 }
hook.Add("EntityTakeDamage", "tif_suppression", function(target, dmg)
	if not dmg:IsDamageType(DMG_BLAST) then return end
	local pos = dmg:GetDamagePosition()
	-- One explosion damages many entities; count it once.
	local now = CurTime()
	if now - lastBlast.time < 0.15 and lastBlast.pos:DistToSqr(pos) < 64 * 64 then return end
	lastBlast.pos, lastBlast.time = pos, now
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) and not npc.tifDead then
			local d = npc:GetPos():Distance(pos)
			if d < 450 then S.Add(npc, 0.7 * (1 - d / 450), pos, dmg:GetAttacker()) end
		end
	end
end)
