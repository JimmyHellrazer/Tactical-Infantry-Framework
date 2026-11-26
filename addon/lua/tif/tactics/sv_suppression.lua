-- Suppression: incoming fire builds pressure (0..1) that changes decisions, not just aim.
-- Sources: bullets passing close, hits, nearby explosions. Decays over time; archetypes resist
-- differently (a guard panics, a support gunner shrugs).

local TIF = TIF
local Prof = TIF.Prof

TIF.Supp = TIF.Supp or {}
local S = TIF.Supp

local NEAR = 90
local NEAR_SQR = NEAR * NEAR
local PER_ROUND = 0.16
local DECAY = 0.22
local MAX_RANGE = 8000
local BLAST_RANGE = 450
local BLAST_RANGE_SQR = BLAST_RANGE * BLAST_RANGE

function S.Add(npc, amount, srcPos, shooter)
	if not IsValid(npc) or npc.tifDead then return end
	local resist = npc.tifArch and npc.tifArch.suppressResist or 0.3
	local before = npc.tifSupp or 0
	local after = math.min(1, before + amount * (1 - resist))
	npc.tifSupp = after
	npc.tifSuppAt = CurTime()
	local cur = npc:GetTIFSupp()
	if math.abs(cur - after) > 0.03 or (after == 1 and cur < 1) then npc:SetTIFSupp(after) end
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
local whizbyCount = {}
function S.Whizby(npc, now)
	if now < (npc.tifNextWhizby or 0) or math.random() > S.WHIZBY_CHANCE then return end
	npc.tifNextWhizby = now + S.WHIZBY_COOLDOWN
	if npc.tifProne or npc.tifVeh or npc.tifDowned or npc.tifKnock or npc.tifDying then return end
	if npc.loco:GetVelocity():Length2DSqr() > 200 * 200 then return end
	local host = npc.tifHomeHost
	if not host then return end
	local n = whizbyCount[host]
	if n == nil then
		n = 0
		for i = 1, 9 do if TIF.GTG.Clip("mwzw_" .. i, host) then n = i end end
		whizbyCount[host] = n
	end
	if n == 0 then return end
	npc:SetNW2Int("tif_whizby_n", math.random(n))
	npc:SetNW2Float("tif_whizby_t", now)
	npc.tifReactUntil = math.max(npc.tifReactUntil or 0, now + 0.3)
end

hook.Add("EntityFireBullets", "tif_suppression", function(shooter, data)
	local soldiers = TIF.Soldiers
	local n = #soldiers
	if n == 0 or not data.Dir then return end
	if IsValid(shooter) and shooter:IsPlayer() and TIF.IgnorePlayers() then return end
	Prof.Begin("suppression")
	local src = data.Src or shooter:GetPos()
	local d = data.Dir
	local dx, dy, dz = d.x, d.y, d.z
	local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
	if dl > 1e-6 then
		local inv = 1 / dl
		dx, dy, dz = dx * inv, dy * inv, dz * inv
	end
	local sx, sy, sz = src.x, src.y, src.z
	local maxD = math.min(data.Distance or MAX_RANGE, MAX_RANGE)
	local rounds = math.Clamp(data.Num or 1, 1, 8)
	local dmg = data.Damage and data.Damage > 0 and math.Clamp(data.Damage / 25, 0.5, 2) or 1
	local mult = PER_ROUND * dmg * math.sqrt(rounds)
	local ally = TIF.REL_ALLY
	local relation = TIF.Relation
	local now
	for i = 1, n do
		local npc = soldiers[i]
		if npc ~= shooter and IsValid(npc) and not npc.tifDead then
			local c = npc:WorldSpaceCenter()
			local vx, vy, vz = c.x - sx, c.y - sy, c.z - sz
			local t = vx * dx + vy * dy + vz * dz
			if t > 60 and t < maxD then
				local px, py, pz = vx - dx * t, vy - dy * t, vz - dz * t
				local perp2 = px * px + py * py + pz * pz
				if perp2 < NEAR_SQR and relation(npc, shooter) ~= ally then
					local perp = math.sqrt(perp2)
					S.Add(npc, (1 - perp / NEAR) * mult, src, shooter)
					if perp < NEAR * 0.5 and S.Whizby then
						now = now or CurTime()
						S.Whizby(npc, now)
					end
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
	local now = CurTime()
	if now - lastBlast.time < 0.15 and lastBlast.pos:DistToSqr(pos) < 64 * 64 then return end
	lastBlast.pos, lastBlast.time = pos, now
	local soldiers = TIF.Soldiers
	local att = dmg:GetAttacker()
	for i = 1, #soldiers do
		local npc = soldiers[i]
		if IsValid(npc) and not npc.tifDead then
			local d2 = npc:GetPos():DistToSqr(pos)
			if d2 < BLAST_RANGE_SQR then
				S.Add(npc, 0.7 * (1 - math.sqrt(d2) / BLAST_RANGE), pos, att)
			end
		end
	end
end)
