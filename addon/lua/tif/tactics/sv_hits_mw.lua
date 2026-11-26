local TIF = TIF
local Act = TIF.Action
local Move = TIF.Move
local A = TIF.Anim

TIF.HitsMW = TIF.HitsMW or {}
local H = TIF.HitsMW

H.PAIN_COOLDOWN = 2.5
H.BIG_PAIN = 35
H.FIRE_COOLDOWN = 9
H.PAIN_BUSY = 0.8
H.RUN_SPEED = 140

local poolsByHost = {}

H.BAN_FILE = "tif/death_bans.txt"

H.DEFAULT_BANS = { "sdr_com_exp_stand_death02_gut_lg_2" }
H.Banned = H.Banned or {}

local function load_bans()
	H.Banned = {}

	for _, n in ipairs(H.DEFAULT_BANS) do
		H.Banned[n] = true
	end

	local txt = file.Read(H.BAN_FILE, "DATA") or ""
	for line in string.gmatch(txt, "[^\r\n]+") do
		local n = string.Trim(line)
		if n ~= "" then
			H.Banned[n] = true
		end
	end
end

load_bans()

local function save_bans()
	file.CreateDir("tif")
	local t = {}

	for n in pairs(H.Banned) do
		t[#t + 1] = n
	end

	table.sort(t)
	file.Write(H.BAN_FILE, table.concat(t, "\n"))
	poolsByHost = {}
end

H.SaveBans = save_bans
H.Recent = H.Recent or {}
local HIT_BONE_M = Matrix and Matrix()
local CopyBone = TIF.CopyBone or function(ent, bone)
	return bone and ent:GetBoneMatrix(bone)
end

local function pools(host)
	local p = poolsByHost[host]
	if p then return p end

	p = { death = {}, pain = {} }
	local clips = TIF.GTG.Clips(host) or {}

	for name, c in pairs(clips) do
		local kind, sit, region = string.match(name, "^mw([dh])_(.+)_(%a+)_%d+$")
		if kind and (H.Banned[name] or H.Banned[c.from or ""] or H.Banned[c.seq or ""]) then
			kind = nil
		end

		if kind then
			local t = kind == "d" and p.death or p.pain
			t[sit] = t[sit] or {}
			t[sit][region] = t[sit][region] or {}
			table.insert(t[sit][region], { name = name, clip = c })
		end
	end

	poolsByHost[host] = p
	return p
end

H.Pools = pools

function H.Use(npc)
	return npc.tifHostId and TIF.GTG.IsVB(npc.tifHostId) or false
end

local REGION = { [HITGROUP_HEAD or 1] = "head", [HITGROUP_LEFTLEG or 6] = "legs", [HITGROUP_RIGHTLEG or 7] = "legs" }

local function push_local(npc, dmg)
	local f = dmg and dmg:GetDamageForce()
	if not f or f:LengthSqr() < 1 then
		local att = dmg and dmg:GetAttacker()
		f = IsValid(att) and (npc:GetPos() - att:GetPos()) or npc:GetForward() * -1
	end

	local yaw = math.rad(npc:GetAngles().y)
	local c, s = math.cos(yaw), math.sin(yaw)
	local x, y = f.x * c + f.y * s, -f.x * s + f.y * c
	local l = math.sqrt(x * x + y * y)
	if l < 1e-4 then return -1, 0 end

	return x / l, y / l
end

local function pick(list, key, px, py)
	if not list or #list == 0 then return nil end

	local scored = {}
	for _, e in ipairs(list) do
		local v = e.clip[key]
		local s = 0

		if v and (v[1] ~= 0 or v[2] ~= 0) then
			local l = math.sqrt(v[1] * v[1] + v[2] * v[2])
			s = (v[1] * px + v[2] * py) / l
		end

		scored[#scored + 1] = { e = e, s = s }
	end

	table.sort(scored, function(a, b) return a.s > b.s end)
	return scored[math.random(1, math.min(3, #scored))].e
end

local function region_list(t, sit, region)
	local s = t[sit]
	if not s then return nil end

	return s[region] or s.torso or s.any or select(2, next(s))
end

H.BLAST_MIN = 30

local function real_blast(dmg)
	return dmg and dmg:IsExplosionDamage() and not dmg:IsBulletDamage() and dmg:GetDamage() >= H.BLAST_MIN
end

H.RealBlast = real_blast

local OUT_OF_COVER = { move = true, side_out = true, side = true, side_turn = true }

local function base_situation(npc, dmg)
	local cov = npc.tifCov
	if real_blast(dmg) then return "explode" end
	if npc.tifProne then return "prone" end

	local act = npc.tifActivity
	if act and act.smart and act.smart.kind == "sit" and act.phase == "loop" then
		return "sit"
	end

	if cov and cov.mw and cov.t and not OUT_OF_COVER[cov.phase] then
		return "cover_" .. cov.t
	end

	if npc:GetTIFStance() == A.STANCE_CROUCH then return "crouch" end
	if npc.loco:GetVelocity():Length2D() > H.RUN_SPEED then return "run" end

	return "stand"
end

local function now_firing(npc)
	local t = npc.GetTIFShotTime and npc:GetTIFShotTime() or 0
	return t > 0 and CurTime() - t < 0.25
end

H.LEDGE_DROP = 110

local function ledge(npc)
	local pos, fwd = npc:GetPos(), npc:GetForward()
	fwd.z = 0
	fwd:Normalize()
	local function blocked(z, d)
		return util.TraceLine({ start = pos + Vector(0, 0, z), endpos = pos + Vector(0, 0, z) + fwd * d,
			mask = MASK_NPCSOLID_BRUSHONLY, filter = npc }).Hit
	end

	local function drop(d)
		local p = pos + fwd * d
		return not util.TraceLine({ start = p + Vector(0, 0, 12), endpos = p - Vector(0, 0, H.LEDGE_DROP),
			mask = MASK_NPCSOLID_BRUSHONLY, filter = npc }).Hit
	end

	if blocked(36, 36) and not blocked(62, 44) and drop(60) then
		return "rail"
	end

	if not blocked(20, 44) and not blocked(36, 44) and drop(44) then
		return "norail"
	end

	return nil
end

H.Ledge = ledge

H.FIREAIR_CHANCE = 0.35
local LOOK_DEATH = { under = true, under_low = true, over = true, high = true, down = true }
local ACT_DEATH = { smoke = true, phone = true, water = true }
local function situation(npc, dmg)
	local cov = npc.tifCov
	local crouched = npc:GetTIFStance() == A.STANCE_CROUCH
	local speed = npc.loco:GetVelocity():Length2D()

	if real_blast(dmg) then
		if npc.tifProne then return { "explode_prone", "explode" } end

		return crouched and { "explode_crouch", "explode" } or { "explode" }
	end

	if dmg and dmg:IsDamageType(DMG_BURN) then
		if npc.tifProne then return { "burn_prone", "prone" } end

		return crouched and { "burn_crouch", "burn", "crouch" } or { "burn", "stand" }
	end

	if npc.tifProne then return { "prone" } end

	local act = npc.tifActivity
	if act and act.smart and act.smart.kind == "sit" and act.phase == "loop" then
		return { "sit", "stand" }
	end

	local look = npc.tifLook
	if look and LOOK_DEATH[look.kind] then
		return { "look_" .. look.kind, "stand" }
	end

	if act and ACT_DEATH[act.name] then
		return { "act_" .. act.name, "stand" }
	end

	if cov and cov.mw and cov.t and not OUT_OF_COVER[cov.phase] then
		if cov.t == "cr" and (cov.phase == "aim" or cov.phase == "aim_in" or cov.phase == "aim_out") then
			return { "cover_crexp", "cover_cr" }
		end

		if cov.t == "lc" or cov.t == "rc" then return { "cover_cr", "crouch" } end

		return { "cover_" .. cov.t, "stand" }
	end

	if dmg and (dmg:IsDamageType(DMG_CLUB) or dmg:IsDamageType(DMG_SLASH)) and not crouched then
		return { "melee", "stand" }
	end

	if speed < H.RUN_SPEED then
		local l = ledge(npc)
		if l then
			return { "ledge_" .. l .. "_" .. (crouched and "cr" or "st"), "ledge_" .. l .. "_st", crouched and "crouch" or "stand" }
		end
	end

	if now_firing(npc) and math.random() < H.FIREAIR_CHANCE then
		return { crouched and "fireair_crouch" or "fireair_stand", crouched and "crouch" or "stand" }
	end

	if crouched then return { "crouch" } end

	if npc:GetNW2Bool("tif_cqb", false) and speed > 30 then
		return { speed > H.RUN_SPEED and "cqbfast" or "cqbwalk", speed > H.RUN_SPEED and "run" or "stand" }
	end

	if speed > H.RUN_SPEED then return { "run" } end

	return { "stand" }
end

H.Situation = situation

H.PRONE_SHIFT = 26.6
H.PRONE_CUT = { 0.4, 0.5 }
H.VEL_WINDOW = 0.1
local SHIFT_MIN, SHIFT_MAX = Vector(-6, -6, 0), Vector(6, 6, 8)

local function prone_death_shift(npc)
	npc.tifProne = nil
	npc:SetNW2Int("tif_prone", 0)
end

H.ProneDeathShift = prone_death_shift

H.LONG_CHANCE = 0.22
H.LONG_HOLD = { 2.5, 6 }
local cvLong = CreateConVar("tif_long_deaths", "1", FCVAR_ARCHIVE, "Wounded crawls / slow deaths sometimes (MW19 body)")
local LONG_KINDS = { st = { "back", "belly", "l", "r", "b", "l2", "r2", "knees" }, cr = { "back", "belly", "l", "r" } }
local function long_chain(npc, sit)
	local st = sit == "crouch" and "cr" or "st"
	local host = npc.tifHostId
	local kinds = {}

	for _, k in ipairs(LONG_KINDS[st]) do
		local p = "mwld_" .. st .. "_" .. k .. "_"
		if TIF.GTG.Clip(p .. "enter", host) and TIF.GTG.Clip(p .. "loop", host) and TIF.GTG.Clip(p .. "death", host) then
			kinds[#kinds + 1] = p
		end
	end

	if #kinds == 0 then return nil end

	local p = kinds[math.random(#kinds)]
	return { { name = p .. "enter" }, { name = p .. "loop", hold = math.Rand(H.LONG_HOLD[1], H.LONG_HOLD[2]) },
		{ name = p .. "death" } }
end

H.LongChain = long_chain

function H.Death(npc, dmg)
	if not H.Use(npc) or npc.tifVeh or npc.tifDowned or npc.tifNoDeathClip then
		return false
	end

	local P = pools(npc.tifHostId)
	local region = REGION[npc.tifLastHitGroup] or "torso"

	local sits = situation(npc, dmg)
	local sit, list = sits[1], nil

	for _, s in ipairs(sits) do
		list = region_list(P.death, s, region)

		if list and #list > 0 then
			sit = s
			break
		end
	end

	if cvLong:GetBool() and region ~= "head" and (sit == "stand" or sit == "crouch" or sit == "run")
		and math.random() < H.LONG_CHANCE then
		local chain = long_chain(npc, sit)
		local d = chain and (Move.Stop(npc) or true) and Act.Play(npc, chain[1].name, { root = true })

		if d then
			local now = CurTime()
			if TIF.CoverBehave and TIF.CoverBehave.In(npc) then
				npc.tifCov = nil
			end

			if TIF.SmartMW then
				TIF.SmartMW.Release(npc)
			end

			table.insert(H.Recent, 1, { name = chain[1].name, src = "long death", sit = sit, t = now, who = npc:EntIndex() })

			if #H.Recent > 10 then
				table.remove(H.Recent)
			end

			local c = TIF.GTG.Clip(chain[1].name, npc.tifHostId)
			npc.tifDying = { untilT = math.huge, chain = chain, stage = 1, stageEnd = now + d, prev = {}, prevT = now,
				seq = npc:LookupSequence(c.seq), t0 = now, dur = d }
			H.DyingLong[npc] = true
			npc:SetNW2Bool("tif_dying", true)
			npc:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			return true
		end
	end

	if not list or #list == 0 then
		list = region_list(P.death, "stand", region)
	end

	local px, py = push_local(npc, dmg)
	local e = pick(list, "fall", px, py)
	if not e then return false end

	local now = CurTime()
	Move.Stop(npc)

	if TIF.CoverBehave and TIF.CoverBehave.In(npc) then
		npc.tifCov = nil
	end

	local d = Act.Play(npc, e.name, { root = true })
	if not d then return false end

	table.insert(H.Recent, 1, { name = e.name, src = e.clip.from or e.clip.seq, sit = sit, t = now, who = npc:EntIndex() })

	if #H.Recent > 10 then
		table.remove(H.Recent)
	end

	if TIF.SmartMW then
		TIF.SmartMW.Release(npc)
	end

	local lying = sit == "prone" or sit == "burn_prone"
	if lying then
		prone_death_shift(npc)
	end

	local cut = e.clip.cut or 0.6

	if lying then
		cut = math.Clamp(cut, H.PRONE_CUT[1], H.PRONE_CUT[2])
	end

	npc.tifDying = { untilT = now + d * cut, prev = {}, prevT = now,

		seq = npc:LookupSequence(e.clip.seq), t0 = now, dur = d }
	npc:SetNW2Bool("tif_dying", true)
	npc:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	return true
end

H.SHOT_RADIUS = 9
H.DyingLong = H.DyingLong or {}

function H.ShotEnd(npc, pos, force)
	local dy = npc.tifDying
	if not (dy and dy.chain) or dy.shotEnd then return false end

	dy.shotEnd = true
	dy.untilT = CurTime()
	npc.tifDeathHit = { pos = pos, force = force or Vector(), fresh = true }
	local fx = EffectData()
	fx:SetOrigin(pos)
	fx:SetNormal(force and force:LengthSqr() > 1 and -force:GetNormalized() or Vector(0, 0, 1))
	util.Effect("BloodImpact", fx)
	return true
end

local SHOT_BONES = { "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Head1" }
local wallTr = { mask = MASK_SHOT }
hook.Add("EntityFireBullets", "tif_long_death_shot", function(shooter, data)
	if not data.Dir or not next(H.DyingLong) then return end

	local src = data.Src or (IsValid(shooter) and shooter:EyePos())
	if not src then return end

	local dir = Vector(data.Dir)
	dir:Normalize()
	local maxD = math.min(data.Distance or 56756, 8000)
	local best, bestT, bestPos

	for npc in pairs(H.DyingLong or {}) do
		local dy = IsValid(npc) and npc.tifDying
		if dy and dy.chain and not dy.shotEnd and npc ~= shooter then
			for _, bn in ipairs(SHOT_BONES) do
				local b = npc:LookupBone(bn)
				local m = b and (TIF.CopyBone and TIF.CopyBone(npc, b, HIT_BONE_M) or npc:GetBoneMatrix(b))

				if m then
					local v = m:GetTranslation() - src
					local t = v:Dot(dir)

					if t > 8 and t < maxD and (v - dir * t):Length() < H.SHOT_RADIUS and (not bestT or t < bestT) then
						best, bestT, bestPos = npc, t, m:GetTranslation()
					end
				end
			end
		end
	end

	if not best then return end

	wallTr.start, wallTr.endpos, wallTr.filter = src, src + dir * (bestT - 6), { shooter, best }
	if util.TraceLine(wallTr).Hit then return end

	local dmg = math.max(data.Damage or 0, 15)
	H.ShotEnd(best, bestPos, dir * math.Clamp(dmg * 150, 2000, 6000))
end)

hook.Add("EntityRemoved", "tif_long_death_list", function(ent) H.DyingLong[ent] = nil end)

hook.Add("EntityTakeDamage", "tif_long_death_hit", function(ent, dmg)
	local dy = ent.TIFSoldier and ent.tifDying
	if dy and dy.chain and not dy.shotEnd and dmg:GetDamage() > 0 then
		H.ShotEnd(ent, dmg:GetDamagePosition(), dmg:GetDamageForce())
	end
end)

function H.DyingThink(npc, now)
	local dy = npc.tifDying
	if not dy then return false end

	if dy.chain and not dy.shotEnd and now >= dy.stageEnd and dy.stage < #dy.chain then
		dy.stage = dy.stage + 1
		local s = dy.chain[dy.stage]
		local d = Act.Play(npc, s.name, { root = true })
		local c = TIF.GTG.Clip(s.name, npc.tifHostId)

		if d and c then
			dy.seq, dy.t0, dy.dur = npc:LookupSequence(c.seq), now, d

			if dy.stage == #dy.chain then
				dy.untilT = now + d * math.max(c.cut or 0.85, 0.85)
			else
				dy.stageEnd = now + math.min(d, s.hold or d)
			end
		else
			dy.untilT = now
		end
	end

	Act.Tick(npc, now)

	if npc.InvalidateBoneCache then
		npc:InvalidateBoneCache()
	end

	local dt = now - dy.prevT
	if now >= dy.untilT then
		local vel = {}
		local hist = dy.hist or {}

		local old, bestD
		for i = #hist, 1, -1 do
			local age = now - hist[i].t
			local dd = math.abs(age - H.VEL_WINDOW)

			if age >= 0.01 and (not bestD or dd < bestD) then
				old, bestD = hist[i], dd
			end
		end

		local span = old and (now - old.t) or 0
		if old and span > 0.01 then
			local cb = TIF.CopyBone
			for b, p in pairs(old.pos) do
				local m = cb and cb(npc, b, HIT_BONE_M) or npc:GetBoneMatrix(b)
				if m then
					vel[b] = (m:GetTranslation() - p) / span
				end
			end
		end

		npc.tifDying = nil
		H.DyingLong[npc] = nil
		npc:TIFFinishDeath(vel)
		return true
	end

	if dt > 0 then
		dy.prevT = now
		local pos = {}
		local cb = TIF.CopyBone

		for b = 0, npc:GetBoneCount() - 1 do
			local m = cb and cb(npc, b, HIT_BONE_M) or npc:GetBoneMatrix(b)
			if m then
				pos[b] = m:GetTranslation()
			end
		end

		dy.prev = pos

		dy.hist = dy.hist or {}
		table.insert(dy.hist, { t = now, pos = pos })

		while #dy.hist > 2 and now - dy.hist[2].t > H.VEL_WINDOW do
			table.remove(dy.hist, 1)
		end
	end

	return true
end

H.MOVE_PAIN_MIN = 40

function H.Pain(npc, dmg)
	if not H.Use(npc) or npc.tifDead then return false end

	if npc.tifKnock then return true end

	if real_blast(dmg) and dmg:GetDamage() >= H.KNOCK_MIN and npc:Health() > 0 and H.Knockdown(npc, dmg) then
		return true
	end

	local now = CurTime()

	if dmg:IsDamageType(DMG_BURN) then
		if now < (npc.tifNextFireReact or 0) or npc.tifAct or npc.tifCov or npc.tifVeh or npc.tifDowned then
			return true
		end

		local set = npc.tifProne and "mwz_fire_pr_" or "mwz_fire_"
		local list = {}

		for i = 1, 12 do
			if TIF.GTG.Clip(set .. i, npc.tifHostId) then
				list[#list + 1] = set .. i
			end
		end

		if #list == 0 then return false end

		Move.Stop(npc)

		if not npc.tifProne then
			npc.tifStance = A.STANCE_STAND
		end

		local d = Act.Play(npc, list[math.random(#list)], { root = true, clear = true })
		if not d then return false end

		npc.tifNextFireReact = now + H.FIRE_COOLDOWN
		npc.tifPainUntil = now + d * 0.85
		npc.tifAction = "on fire"
		TIF.Say(npc, "pain", 1)
		return true
	end

	local R22 = TIF.React22
	if R22 and R22.Assess(npc, dmg, now) then return true end

	local cov = npc.tifCov
	if cov and cov.mw and now >= (npc.tifNextPain or 0) and not npc.tifDowned and TIF.CoverBehave.MW.Pain then
		if math.random() > math.Clamp(dmg:GetDamage() / 30, 0.4, 0.9) then
			return false
		end

		local px, py = push_local(npc, dmg)

		local dir = math.abs(px) >= math.abs(py) and (px > 0 and "b" or "f") or (py > 0 and "r" or "l")
		local region = REGION[npc.tifLastHitGroup] or "torso"
		local d = TIF.CoverBehave.MW.Pain(npc, region, dir, dmg:GetDamage() >= 35, now)

		if d then
			npc.tifPainUntil = now + d * H.PAIN_BUSY
			npc.tifNextPain = now + d + H.PAIN_COOLDOWN
			return true
		end

		return false
	end

	if now < (npc.tifNextPain or 0) or npc.tifAct or npc.tifCov or npc.tifVeh or npc.tifDowned
		or npc.tifSurrendered or npc.tifPassiveBusy or npc.tifReact then
			return false
		end

	local chance = math.Clamp(dmg:GetDamage() / 30, 0.35, 0.9)
	if math.random() > chance then return false end

	local moveSpeed = npc.loco:GetVelocity():Length2D()
	local moving = moveSpeed > H.MOVE_PAIN_MIN and not npc.tifProne

	if not moving and R22 and R22.Shock(npc, dmg, now) then
		npc.tifPainUntil = now + 1
		npc.tifNextPain = now + 4 + H.PAIN_COOLDOWN
		return true
	end

	local P = pools(npc.tifHostId)
	local sit = base_situation(npc, dmg)

	if sit == "run" then
		local v = npc.loco:GetVelocity():Length2D()
		local g = v > 230 and "sprint" or (v > 160 and "run" or "jog")
		local n = "mwh_flinch_" .. g .. "_" .. math.random(1, 2)

		if TIF.GTG.Clip(n, npc.tifHostId) then
			local d = Act.Play(npc, n, { root = true, clear = true })
			if d then
				npc.tifPainUntil = now + d * 0.4
				npc.tifNextPain = now + d + H.PAIN_COOLDOWN
				npc.tifAction = "hit (running)"
				return true
			end
		end
	end

	if sit == "prone" then return false end
	if sit == "run" then return false end

	if sit == "explode" then
		sit = "stand"
	end

	local cqbMoving = sit == "stand" and npc:GetNW2Bool("tif_cqb", false) and moveSpeed > 30
	if moving and not cqbMoving then return false end

	local region = REGION[npc.tifLastHitGroup] or "torso"

	local cands = {}
	if TIF.CoverBehave.MW and TIF.CoverBehave.MW.HoldsPistol and TIF.CoverBehave.MW.HoldsPistol(npc) then
		cands[#cands + 1] = "pstl"
	end

	if dmg:GetDamage() >= H.BIG_PAIN and (sit == "stand" or sit == "crouch") then
		cands[#cands + 1] = sit .. "big"
	end

	local speed = npc.loco:GetVelocity():Length2D()
	if sit == "stand" and npc:GetNW2Bool("tif_cqb", false) and speed > 30 then
		cands[#cands + 1] = speed > H.RUN_SPEED * 0.75 and "cqbfast" or "cqbwalk"
	end

	cands[#cands + 1] = sit
	local list

	for _, s in ipairs(cands) do
		list = region_list(P.pain, s, region)
		if list and #list > 0 then break end
	end

	local px, py = push_local(npc, dmg)
	local e = pick(list, "push", px, py)
	if not e then return false end

	if sit ~= "run" then
		Move.Stop(npc)
	end

	local d = Act.Play(npc, e.name, { root = true, clear = true })
	if not d then return false end

	npc.tifPainUntil = now + d * H.PAIN_BUSY
	npc.tifNextPain = now + d + H.PAIN_COOLDOWN
	npc.tifAction = "hit"
	return true
end

H.KNOCK_MIN = 18
H.KNOCK_CHANCE = 0.75
H.KNOCK_TIME = { 1.4, 2.6 }
H.KNOCK_COOLDOWN = 8
local cvKnock = CreateConVar("tif_knockdowns", "1", FCVAR_ARCHIVE, "Blasts knock soldiers down (MW19 body: ragdoll, then a get-up)")
local KNOCK_POSE = {
	mwk_up_back_1 = { 3.3, -2.6, 130 }, mwk_up_back_2 = { 4.7, -0.7, 175 }, mwk_up_back_3 = { 4.1, 1.8, -140 },
	mwk_up_back_4 = { 1.0, -3.2, 85 }, mwk_up_back_6 = { -1.5, 0.6, -5 }, mwk_up_back_7 = { -0.9, -1.8, 40 },
	mwk_up_back_8 = { -1.5, 0.5, -5 }, mwk_up_back_9 = { -0.2, 2.6, -50 },
	mwk_up_stomach_1 = { 2.4, -1.7, 131 }, mwk_up_stomach_2 = { 3.4, -0.6, 176 }, mwk_up_stomach_3 = { 3.2, 0.9, -139 },
	mwk_up_stomach_4 = { 2.1, 1.8, -94 }, mwk_up_stomach_6 = { 1.0, -1.8, 86 }, mwk_up_stomach_7 = { -0.2, -0.9, 41 },
	mwk_up_stomach_8 = { -0.3, 0.6, -4 }, mwk_up_stomach_9 = { 0.6, 1.7, -49 },
	mwk_up_left_1 = { -2.4, -7.8, 126 }, mwk_up_left_2 = { 4.3, -8.2, 171 }, mwk_up_left_3 = { 9.3, -3.9, -144 },
	mwk_up_left_4 = { -6.7, -2.7, 81 }, mwk_up_left_6 = { 9.8, 2.7, -99 }, mwk_up_left_7 = { -6.2, 3.9, 36 },
	mwk_up_left_8 = { -1.2, 8.2, -9 }, mwk_up_left_9 = { 5.5, 7.8, -54 },
	mwk_up_right_1 = { 7.2, 5.0, 154 }, mwk_up_right_2 = { 2.0, 7.6, -161 }, mwk_up_right_3 = { -3.5, 5.7, -116 },
	mwk_up_right_4 = { 9.1, -0.4, 109 }, mwk_up_right_6 = { -6.0, 0.4, -71 }, mwk_up_right_7 = { 6.6, -5.7, 64 },
	mwk_up_right_8 = { 1.1, -7.6, 19 }, mwk_up_right_9 = { -4.1, -5.0, -26 },
}
H.KnockPose = KNOCK_POSE

local function bone_pos(rag, name)
	local b = rag:LookupBone(name)
	local m = b and CopyBone(rag, b, HIT_BONE_M)
	return m and m:GetTranslation() or nil
end

function H.LieOf(rag)
	local pel, head = bone_pos(rag, "ValveBiped.Bip01_Pelvis"), bone_pos(rag, "ValveBiped.Bip01_Head1")
	local l, r = bone_pos(rag, "ValveBiped.Bip01_L_UpperArm"), bone_pos(rag, "ValveBiped.Bip01_R_UpperArm")
	if not (pel and head and l and r) then return nil end

	local A, S = head - pel, r - l
	local F = A:Cross(S)
	F:Normalize()
	local side

	if F.z > 0.5 then
		side = "back"
		elseif F.z < -0.5 then
			side = "stomach"
	else
		side = S.z > 0 and "left" or "right"
	end

	return side, pel, math.deg(math.atan2(A.y, A.x))
end

function H.Knockdown(npc, dmg)
	if not cvKnock:GetBool() or not H.Use(npc) or npc.tifVeh or npc.tifProne or npc.tifDowned or npc.tifKnock
		or npc.tifDying or npc.tifDead or not npc.TIFMakeCorpse then
			return false
		end

	if not TIF.GTG.Clip("mwk_up_back_8", npc.tifHostId) then return false end

	local now = CurTime()
	if now < (npc.tifKnockNext or 0) or math.random() > H.KNOCK_CHANCE then
		return false
	end

	local f = dmg:GetDamageForce()
	if f:LengthSqr() < 1 then
		f = npc:WorldSpaceCenter() - dmg:GetDamagePosition()
		f:Normalize()
		f = f * 12000
	end

	f.z = math.max(f.z, f:Length() * 0.25)
	Move.Stop(npc)

	local ok, rag = pcall(npc.TIFMakeCorpse, npc, { pos = dmg:GetDamagePosition(), force = f * 1.5 }, nil)
	Act.Clear(npc)

	if TIF.CoverBehave and TIF.CoverBehave.In(npc) then
		TIF.CoverBehave.Leave(npc, "knocked down")
	end

	if not ok or not IsValid(rag) then return false end

	rag.tifKnockOwner = npc
	npc.tifKnock = { rag = rag, untilT = now + math.Rand(H.KNOCK_TIME[1], H.KNOCK_TIME[2]) }
	npc.tifKnockNext = now + H.KNOCK_COOLDOWN
	npc:SetNoDraw(true)
	npc:SetNotSolid(true)
	npc:SetNW2Bool("tif_knocked", true)
	npc.tifPainUntil = math.huge
	npc.tifAction = "knocked down"
	return true
end

local function knock_think(npc, now)
	local k = npc.tifKnock
	local rag = k.rag

	if not IsValid(rag) then
		npc.tifKnock = nil
		npc:SetNoDraw(false)
		npc:SetNotSolid(false)
		npc:SetNW2Bool("tif_knocked", false)
		npc.tifPainUntil = nil
		return false
	end

	local side, pel, headYaw = H.LieOf(rag)
	if pel then
		npc:SetPos(Vector(pel.x, pel.y, npc:GetPos().z))
	end

	if now < k.untilT then return true end

	local phys = rag:GetPhysicsObject()
	if IsValid(phys) and phys:GetVelocity():Length() > 40 and now < k.untilT + 2 then
		return true
	end

	if not side then
		side = "back"
	end

	local c = npc.tifPrimaryC
	local wantYaw = c and (c.pos - pel):Angle().y or nil
	local best, bestE, bestYaw

	for n = 1, 9 do
		local name = "mwk_up_" .. side .. "_" .. n
		local p = KNOCK_POSE[name]

		if p and TIF.GTG.Clip(name, npc.tifHostId) then
			local yaw = headYaw - p[3]
			local e = wantYaw and math.abs(math.AngleDifference(yaw, wantYaw)) or math.random() * 180

			if not bestE or e < bestE then
				best, bestE, bestYaw = name, e, yaw
			end
		end
	end

	local tr = util.TraceLine({ start = pel + Vector(0, 0, 16), endpos = pel - Vector(0, 0, 64), mask = MASK_NPCSOLID_BRUSHONLY, filter = { npc, rag } })
	local ground = tr.Hit and tr.HitPos.z or pel.z
	npc.tifKnock = nil
	npc:SetNW2Bool("tif_knocked", false)
	npc:SetNoDraw(false)
	npc:SetNotSolid(false)
	rag:Remove()

	if not best then
		npc.tifPainUntil = nil
		return false
	end

	local p = KNOCK_POSE[best]
	local r = math.rad(bestYaw)
	local cs, sn = math.cos(r), math.sin(r)
	npc:SetPos(Vector(pel.x - (p[1] * cs - p[2] * sn), pel.y - (p[1] * sn + p[2] * cs), ground))
	npc:SetAngles(Angle(0, bestYaw, 0))
	local d = Act.Play(npc, best, { root = true, clear = true })
	npc.tifPainUntil = now + (d or 0)
	npc.tifAction = "getting up"
	return true
end

hook.Add("EntityTakeDamage", "tif_knock_damage", function(ent, dmg)
	local owner = ent.tifKnockOwner
	if IsValid(owner) and owner.tifKnock and owner.tifKnock.rag == ent and not owner.tifDead then
		owner:TakeDamageInfo(dmg)
	end
end)

function H.KnockDeath(npc)
	local k = npc.tifKnock
	if not (k and IsValid(k.rag)) then return false end

	k.rag.tifKnockOwner = nil
	npc.tifKnock = nil
	return true
end

function H.Busy(npc, now)
	if npc.tifKnock then return knock_think(npc, now) end
	if not npc.tifPainUntil then return false end
	if now < npc.tifPainUntil then return true end

	npc.tifPainUntil = nil
	return false
end

local cvBlast = CreateConVar("tif_blast_scale", "1.6", FCVAR_ARCHIVE, "Multiplier on blast damage TIF soldiers take")

hook.Add("EntityTakeDamage", "tif_blast_scale", function(ent, dmg)
	if ent.TIFSoldier and real_blast(dmg) then
		dmg:ScaleDamage(math.max(0, cvBlast:GetFloat()))
	end
end)
