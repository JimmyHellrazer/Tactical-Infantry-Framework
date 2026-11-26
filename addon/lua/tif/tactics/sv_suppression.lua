local TIF = TIF
local Prof = TIF.Prof

TIF.Supp = TIF.Supp or {}
local Supp = TIF.Supp

local NEAR_RADIUS = 90
local NEAR_RADIUS_SQR = NEAR_RADIUS * NEAR_RADIUS
local PER_ROUND = 0.16
local DECAY_RATE = 0.22
local MAX_RANGE = 8000
local BLAST_RANGE = 450
local BLAST_RANGE_SQR = BLAST_RANGE * BLAST_RANGE

function Supp.Add(npc, amount, srcPos, shooter)
	if not IsValid(npc) or npc.tifDead then return end
	local resist = npc.tifArch and npc.tifArch.suppressResist or 0.3
	local before = npc.tifSupp or 0
	local after = math.min(1, before + amount * (1 - resist))
	npc.tifSupp = after
	npc.tifSuppAt = CurTime()
	local synced = npc:GetTIFSupp()
	if math.abs(synced - after) > 0.03 or (after == 1 and synced < 1) then npc:SetTIFSupp(after) end
	if before < 0.45 and after >= 0.45 then TIF.Say(npc, "swear", 0.5) end
	if IsValid(shooter) and srcPos and TIF.Perception.OnSuppressed then
		TIF.Perception.OnSuppressed(npc, shooter, srcPos)
	end
end

function Supp.Decay(npc, dt)
	local level = npc.tifSupp or 0
	if level <= 0 then return end
	local resist = npc.tifArch and npc.tifArch.suppressResist or 0.3
	if CurTime() - (npc.tifSuppAt or 0) < 0.6 then return end
	level = math.max(0, level - dt * DECAY_RATE * (1 + resist))
	npc.tifSupp = level
	if math.abs(npc:GetTIFSupp() - level) > 0.03 or level == 0 then npc:SetTIFSupp(level) end
end

Supp.WHIZBY_CHANCE, Supp.WHIZBY_COOLDOWN = 0.3, 4
local whizbyCounts = {}
function Supp.Whizby(npc, now)
	if now < (npc.tifNextWhizby or 0) or math.random() > Supp.WHIZBY_CHANCE then return end
	npc.tifNextWhizby = now + Supp.WHIZBY_COOLDOWN
	if npc.tifProne or npc.tifVeh or npc.tifDowned or npc.tifKnock or npc.tifDying then return end
	if npc.loco:GetVelocity():Length2DSqr() > 200 * 200 then return end
	local host = npc.tifHomeHost
	if not host then return end
	local count = whizbyCounts[host]
	if count == nil then
		count = 0
		for i = 1, 9 do if TIF.GTG.Clip("mwzw_" .. i, host) then count = i end end
		whizbyCounts[host] = count
	end
	if count == 0 then return end
	npc:SetNW2Int("tif_whizby_n", math.random(count))
	npc:SetNW2Float("tif_whizby_t", now)
	npc.tifReactUntil = math.max(npc.tifReactUntil or 0, now + 0.3)
end

hook.Add("EntityFireBullets", "tif_suppression", function(shooter, data)
	local soldiers = TIF.Soldiers
	local soldierCount = #soldiers
	if soldierCount == 0 or not data.Dir then return end
	if IsValid(shooter) and shooter:IsPlayer() and TIF.IgnorePlayers() then return end
	Prof.Begin("suppression")
	local src = data.Src or shooter:GetPos()
	local rawDir = data.Dir
	local dirX, dirY, dirZ = rawDir.x, rawDir.y, rawDir.z
	local dirLen = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
	if dirLen > 1e-6 then
		local invLen = 1 / dirLen
		dirX, dirY, dirZ = dirX * invLen, dirY * invLen, dirZ * invLen
	end
	local srcX, srcY, srcZ = src.x, src.y, src.z
	local maxDist = math.min(data.Distance or MAX_RANGE, MAX_RANGE)
	local rounds = math.Clamp(data.Num or 1, 1, 8)
	local dmgScale = data.Damage and data.Damage > 0 and math.Clamp(data.Damage / 25, 0.5, 2) or 1
	local suppMult = PER_ROUND * dmgScale * math.sqrt(rounds)
	local relAlly = TIF.REL_ALLY
	local getRelation = TIF.Relation
	local now
	for i = 1, soldierCount do
		local npc = soldiers[i]
		if npc ~= shooter and IsValid(npc) and not npc.tifDead then
			local center = npc:WorldSpaceCenter()
			local relX, relY, relZ = center.x - srcX, center.y - srcY, center.z - srcZ
			local along = relX * dirX + relY * dirY + relZ * dirZ
			if along > 60 and along < maxDist then
				local perpX, perpY, perpZ = relX - dirX * along, relY - dirY * along, relZ - dirZ * along
				local perpSqr = perpX * perpX + perpY * perpY + perpZ * perpZ
				if perpSqr < NEAR_RADIUS_SQR and getRelation(npc, shooter) ~= relAlly then
					local perpDist = math.sqrt(perpSqr)
					Supp.Add(npc, (1 - perpDist / NEAR_RADIUS) * suppMult, src, shooter)
					if perpDist < NEAR_RADIUS * 0.5 and Supp.Whizby then
						now = now or CurTime()
						Supp.Whizby(npc, now)
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
	local blastPos = dmg:GetDamagePosition()
	local now = CurTime()
	if now - lastBlast.time < 0.15 and lastBlast.pos:DistToSqr(blastPos) < 64 * 64 then return end
	lastBlast.pos, lastBlast.time = blastPos, now
	local soldiers = TIF.Soldiers
	local attacker = dmg:GetAttacker()
	for i = 1, #soldiers do
		local npc = soldiers[i]
		if IsValid(npc) and not npc.tifDead then
			local distSqr = npc:GetPos():DistToSqr(blastPos)
			if distSqr < BLAST_RANGE_SQR then
				Supp.Add(npc, 0.7 * (1 - math.sqrt(distSqr) / BLAST_RANGE), blastPos, attacker)
			end
		end
	end
end)
