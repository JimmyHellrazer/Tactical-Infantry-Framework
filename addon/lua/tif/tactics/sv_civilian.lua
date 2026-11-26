

local TIF = TIF

TIF.Civ = TIF.Civ or {}
local Civ = TIF.Civ

Civ.LEAVE_SHARE = 0.8
Civ.TOO_CLOSE = 700
Civ.FAR_GONE = 3500
Civ.LEAVE_DIST = 3200
Civ.GONE_DIST = 1100
Civ.SHOT_RADIUS = 2400
Civ.BLAST_RADIUS = 2200

Civ.MODELS = Civ.MODELS or {}
Civ.HL2 = {
	"models/humans/group01/male_01.mdl", "models/humans/group01/male_02.mdl", "models/humans/group01/male_04.mdl",
	"models/humans/group01/male_07.mdl", "models/humans/group01/female_01.mdl", "models/humans/group01/female_03.mdl",
}

function Civ.AddModels(list)
	for _, m in ipairs(list) do table.insert(Civ.MODELS, m) end
end

local czech = {}
for _, n in ipairs({ "01", "02", "03", "04", "05", "06", "07", "08", "09" }) do czech[#czech + 1] = "models/drem/cch/male_" .. n .. ".mdl" end
for _, n in ipairs({ "01", "02", "03", "04", "06", "07" }) do czech[#czech + 1] = "models/drem/cch/female_" .. n .. ".mdl" end

local usable
function Civ.PickModel()
	if not usable then
		usable = {}
		for _, m in ipairs(Civ.MODELS) do if util.IsValidModel(m) then usable[#usable + 1] = m end end
		for _, m in ipairs(czech) do if util.IsValidModel(m) then usable[#usable + 1] = m end end
		if #usable == 0 then
			for _, m in ipairs(Civ.HL2) do if util.IsValidModel(m) then usable[#usable + 1] = m end end
		end
	end
	return usable[math.random(math.max(1, #usable))] or "models/humans/group01/male_01.mdl"
end

local list = {}
function Civ.Register(civ) list[civ] = true end

function Civ.Unregister(civ) list[civ] = nil end

function Civ.List()
	local out = {}
	for c in pairs(list) do if IsValid(c) then out[#out + 1] = c end end
	return out
end

function Civ.Spawn(pos, opts)
	opts = opts or {}
	local civ = ents.Create("tif_civilian")
	if not IsValid(civ) then return nil end
	civ:SetPos(pos + Vector(0, 0, 4))
	civ:SetAngles(Angle(0, opts.yaw or math.random(0, 359), 0))
	civ.home, civ.homeRadius = opts.home or pos, opts.radius or 1200
	civ.state, civ.shelter, civ.noLeave, civ.civModel = opts.state, opts.shelter, opts.noLeave, opts.model
	civ:Spawn()
	return civ
end

local function snap(p)
	local a = navmesh.GetNearestNavArea(p, false, 400, false, true)
	return IsValid(a) and a:GetClosestPointOnArea(p) or nil
end

function Civ.RandomPoint(center, radius)
	for _ = 1, 6 do
		local a = math.rad(math.random(0, 359))
		local d = math.Rand(0.2, 1) * radius
		local p = snap(center + Vector(math.cos(a) * d, math.sin(a) * d, 0))
		if p then return p end
	end
	return nil
end

local tr = { mask = MASK_SOLID_BRUSHONLY }
local function hit(a, b)
	tr.start, tr.endpos = a, b
	return util.TraceLine(tr)
end

local function indoors(p)
	return hit(p + Vector(0, 0, 40), p + Vector(0, 0, 400)).Hit
end

function Civ.HideSpot(civ, danger)
	local pos = civ:GetPos()
	local away = pos - danger
	away.z = 0
	if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
	away:Normalize()
	local best, bs
	for i = 1, 8 do
		local a = math.rad(math.Rand(-70, 70))
		local c, s = math.cos(a), math.sin(a)
		local dir = Vector(away.x * c - away.y * s, away.x * s + away.y * c, 0)
		local p = snap(pos + dir * math.Rand(500, 1200))
		if p then
			local score = math.random()
			if hit(danger + Vector(0, 0, 50), p + Vector(0, 0, 40)).Hit then score = score + 2 end
			if indoors(p) then score = score + 1.5 end

			local wall, yaw
			local toD = (danger - p)
			toD.z = 0
			toD:Normalize()
			local left = Vector(-toD.y, toD.x, 0)
			for _, side in ipairs({ { "l", left }, { "r", left * -1 } }) do
				local w = hit(p + Vector(0, 0, 40), p + Vector(0, 0, 40) + side[2] * 40)
				if w.Hit and math.abs(w.HitNormal.z) < 0.3 then
					wall = side[1]

					yaw = toD:Angle().y
					score = score + 1
					break
				end
			end
			if not bs or score > bs then best, bs = { pos = p, yaw = yaw or toD:Angle().y, wall = wall }, score end
		end
	end
	return best
end

function Civ.LeavePoint(civ, danger)
	local pos = civ:GetPos()
	local away = pos - danger
	away.z = 0
	if away:LengthSqr() < 1 then away = VectorRand() away.z = 0 end
	away:Normalize()
	for _, k in ipairs({ 1, 0.7, 0.45 }) do
		for _ = 1, 3 do
			local a = math.rad(math.Rand(-45, 45))
			local c, s = math.cos(a), math.sin(a)
			local dir = Vector(away.x * c - away.y * s, away.x * s + away.y * c, 0)
			local p = snap(pos + dir * Civ.LEAVE_DIST * k)
			if p and p:DistToSqr(pos) > 600 * 600 then return p end
		end
	end
	return nil
end

function Civ.Helper(civ)
	local pos = civ:GetPos()
	for _, ply in ipairs(player.GetHumans()) do
		if ply:Alive() and ply:GetPos():DistToSqr(pos) < 300 * 300 then return ply end
	end
	for _, s in ipairs(TIF.Soldiers or {}) do
		if IsValid(s) and not s.tifDead and s:GetPos():DistToSqr(pos) < 260 * 260 then return s end
	end
	return nil
end

function Civ.Scare(pos, radius, amount)
	local r2 = radius * radius
	for c in pairs(list) do
		if IsValid(c) then
			local d2 = c:GetPos():DistToSqr(pos)
			if d2 < r2 then c:Scare(pos, (amount or 0.6) * (1 - math.sqrt(d2) / radius * 0.6)) end
		end
	end
end

local lastShot = 0
hook.Add("EntityFireBullets", "tif_civilians", function(ent, data)
	if next(list) == nil then return end
	local now = CurTime()
	if now - lastShot < 0.25 then return end
	lastShot = now
	local src = data.Src or (IsValid(ent) and ent:GetPos())
	if not src then return end
	Civ.Scare(src, Civ.SHOT_RADIUS, 0.6)

	if data.Dir then
		local t = util.TraceLine({ start = src, endpos = src + data.Dir * 4000, mask = MASK_SHOT, filter = ent })
		if t.HitPos then Civ.Scare(t.HitPos, 1000, 0.8) end
	end
end)

hook.Add("EntityTakeDamage", "tif_civilians", function(target, dmg)
	if next(list) == nil or not dmg:IsDamageType(DMG_BLAST) then return end
	Civ.Scare(dmg:GetDamagePosition(), Civ.BLAST_RADIUS, 1)
end)

local function seen(p, players)
	local near = false
	for _, ply in ipairs(players) do
		if ply:GetPos():DistToSqr(p) < Civ.FAR_GONE * Civ.FAR_GONE then near = true end
	end
	if not near then return false end
	for _, ply in ipairs(players) do
		local eye = ply:EyePos()
		if eye:DistToSqr(p) < Civ.GONE_DIST * Civ.GONE_DIST then return true end
		local dir = (p - eye):GetNormalized()
		if dir:Dot(ply:GetAimVector()) > 0.4 and not hit(eye, p + Vector(0, 0, 50)).Hit then return true end
	end
	return false
end

timer.Create("tif_civilians", 1, 0, function()
	if next(list) == nil then return end
	local players = {}
	for _, ply in ipairs(player.GetHumans()) do if ply:Alive() then players[#players + 1] = ply end end
	for c in pairs(list) do
		if IsValid(c) and c.state == "leave" and not c.gone and CurTime() - (c.scaredAt or 0) > 2
			and not seen(c:GetPos(), players) then
			c.gone = true
			hook.Run("TIF_CivilianLeft", c)
			c:Remove()
		end
	end
end)
