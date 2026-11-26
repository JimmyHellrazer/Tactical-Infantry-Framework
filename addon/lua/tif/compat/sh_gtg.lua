local TIF = TIF
TIF.GTG = TIF.GTG or {}
local A = TIF.GTG
local GTG = TIFG

A.MW_HOST = "mw_male"
A.DEFAULT_HOST = A.MW_HOST
A.FEMALE_HOST = A.MW_HOST

A.REQUIRED = {
	{ "TIFG", "sh" },
	{ "TIFG.Characters", "sh" },
	{ "TIFG.Clips", "sh" },
	{ "TIFG.ClipList", "sh" },
	{ "TIFG.ClipPhase", "sh" },
	{ "TIFG.ClipFrameForPhase", "sh" },
	{ "TIFG.ClipCurve", "sh" },
	{ "TIFG.PMS", "sh" },
	{ "TIFG.PMS.Skeleton", "sh" },
	{ "TIFG.PMS.MapFor", "sh" },
	{ "TIFG.PMS.Solve", "cl" },
	{ "TIFG.Weapons", "sh" },
	{ "TIFG.WeaponBases", "sh" },
}

function A.Stored(class)
	if not isstring(class) then return nil end
	local w = istable(TIFG) and TIFG.Weapons and TIFG.Weapons[class]
	return w or weapons.GetStored(class)
end

local function resolve(path)
	local cur = _G
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then return nil end
		cur = cur[part]
		if cur == nil then return nil end
	end

	return cur
end
A.Resolve = resolve

function A.Present()
	return istable(GTG) and istable(GTG.Characters) and istable(GTG.Clips)
end

function A.Version()
	return TIF.Version or "?"
end

function A.Unit() return 39.3701 end

function A.Character(id)
	if not A.Present() then return nil end
	return GTG.Characters[id or A.MW_HOST]
end

function A.HostModel(id)
	local c = A.Character(id)
	return c and c.model or nil
end

function A.IsVB(id)
	local c = A.Character(id)
	return c ~= nil and c.skeleton == "valvebiped"
end

function A.HostFor(fac)
	return A.MW_HOST
end

function A.Clips(id)
	local c = A.Character(id)
	return c and GTG.Clips[c.clips] or nil
end

function A.Clip(name, id)
	local clips = A.Clips(id)
	return clips and clips[name] or nil
end

local cvSeatDrop = CreateConVar("tif_mw_seat_drop", "34", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Units the generic MW seat pose sits below a Glide vehicle's seat (vehicles without TIF seat data)")
local GENERIC_SEAT = { "mwck_s0_idle", "mwck_s1_idle", "mwck_s2_idle", "mwck_s3_idle" }
function A.SeatPose(veh, n, hostId)
	local pod = istable(veh.seats) and veh.seats[n]
	if not IsValid(pod) then return nil end
	local clips = A.Clips(hostId or A.MW_HOST)
	if not clips then return nil end
	local name = GENERIC_SEAT[n] or GENERIC_SEAT[(n % 2 == 1) and 3 or 4]
	if not clips[name] then return nil end
	local lp = veh:WorldToLocal(pod:GetPos()) - Vector(0, 0, cvSeatDrop:GetFloat())
	local lyaw = veh:WorldToLocalAngles(pod:GetAngles()).y + 90
	return { lp = lp, yaw = lyaw, clip = name, driver = n == 1, exact = true }
end

function A.SeatEntry(veh, n, hostId) return nil end

function A.DoorWindow(clip)
	local a, b
	for _, t in ipairs(clip and clip.tags or {}) do
		if t[1] == "Door" and istable(t[4]) then
			if t[4].Start == true and not a then
				a = t[2] elseif t[4].Start == false and a and not b then b = t[2]
			end
		end
	end

	if a and b and b > a then return a, b end
	return nil
end

function A.DriveBySet() return nil end

function A.DriveByWeapon() return false end

function A.SweepPhase() return 0.5 end

if SERVER then
	function A.SetDoor(veh, index, ratio)
		veh:SetNW2Float("tif_door" .. index, math.Clamp(ratio, 0, 1))
		veh.tifHasDoors = true
		veh:SetNW2Bool("tif_doors", true)
	end
end

if SERVER then

	function A.GunShot() return false end

	function A.Launch(npc, def, class, pos, dir)
		local p = def and def.projectile
		if not p then return nil end
		local e = ents.Create(p.entity or "tif_rocket")
		if not IsValid(e) then return nil end
		e:SetPos(pos)
		e:SetAngles(dir:Angle())
		if e.Setup then
			e:Setup(p, dir, npc)
		end
		e:Spawn()
		e:Activate()
		return e
	end
end

function A.WeaponDef(class)
	local stored = A.Stored(class)
	if stored and istable(stored.GTG) then return stored.GTG end
	return nil
end

local KIND = {
	pistol = "pistol", ap_pistol = "pistol", pistol50 = "pistol", revolver = "pistol", revolver_mk2 = "pistol",
	double_action = "pistol", navy_revolver = "pistol",
	pump = "shotgun", sawnoff = "shotgun", assault_shotgun = "shotgun", combat_shotgun = "shotgun",
	double_barrel = "shotgun", sweeper = "shotgun",
	rpg = "rpg", grenade_launcher = "rpg",
	mg = "lmg", combat_mg = "lmg", mg_mk2 = "lmg", minigun = "lmg",
	smg = "smg", micro_smg = "smg", assault_smg = "smg",
}
A.WEAPON_KIND = KIND

function A.WeaponKind(class)
	local def = class and A.WeaponDef(class)
	return KIND[string.lower(def and tostring(def.hold or "") or "")] or "rifle"
end

function A.WeaponClasses()
	local out = {}
	for class, w in pairs(istable(TIFG) and TIFG.Weapons or {}) do
		if istable(w.GTG) and w.Primary and (w.Primary.ClipSize or 0) > 0 then
			out[#out + 1] = class
		end
	end

	table.sort(out)
	return out
end

function A.HoldSet() return nil end

function A.FrameForPhase(clip, phase)
	if istable(GTG) and GTG.ClipFrameForPhase then
		return GTG.ClipFrameForPhase(clip, phase)
	end
	return (phase % 1) * math.max(1, clip.frames - 1)
end

function A.ClipCurve(clip, frame, axis)
	if not (istable(GTG) and GTG.ClipCurve) then return 0 end
	return GTG.ClipCurve(clip, frame, axis)
end

function A.StrideRate(clip)
	return clip.stride_rate or clip.phase_rate or 1 / math.max(0.1, clip.dur)
end

function A.Skeleton(model)
	if not (istable(GTG) and istable(GTG.PMS) and GTG.PMS.Skeleton) then
		return nil
	end
	return GTG.PMS.Skeleton(model)
end

function A.MapFor(hostModel, visualModel)
	if not (istable(GTG) and istable(GTG.PMS) and GTG.PMS.MapFor) then
		return nil
	end
	return GTG.PMS.MapFor(hostModel, visualModel)
end

if CLIENT then
	function A.Solve(ent, map)
		GTG.PMS.Solve(ent, map, nil, nil)
	end
end
