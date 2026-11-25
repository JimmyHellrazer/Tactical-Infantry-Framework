-- TIF's animation / weapon content layer (the TIF.GTG table; the name is historical). Clips, characters and weapon
-- definitions come from TIF's own registry (tif/gta/: global TIFG, sh_core.lua; the MW19 body "mw_male" and its clips,
-- the baked MW guns). Until TIF 0.38.0 this also carried a copy of GrandTheftGMod's GTA content (the GTA ped, its
-- clips, weapons, vehicle seats / drive-bys, sounds, projectiles); all of that is gone: the MW19 body is the only one.

local TIF = TIF
TIF.GTG = TIF.GTG or {}
local A = TIF.GTG
local GTG = TIFG

-- The one body (0.38.0). DEFAULT_HOST / FEMALE_HOST are kept as names for code and content packs that still use them.
A.MW_HOST = "mw_male"
A.DEFAULT_HOST = A.MW_HOST
A.FEMALE_HOST = A.MW_HOST

-- Symbols checked by the self-test. realm: "sh" both, "cl" client only.
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

-- A weapon's definition (TIF's MW guns, data only), else a registered SWEP. Has the fields TIF reads: WorldModel,
-- Primary, GTG (the TIF weapon table: hold, damage, rate, range, sounds...).
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

-- Hammer units per metre (the weapon ranges were authored in metres).
function A.Unit() return 39.3701 end

function A.Character(id)
	if not A.Present() then return nil end
	return GTG.Characters[id or A.MW_HOST]
end

function A.HostModel(id)
	local c = A.Character(id)
	return c and c.model or nil
end

-- Is this host a ValveBiped skeleton (faction models bone-merge straight on)? (Always, since 0.38.0.)
function A.IsVB(id)
	local c = A.Character(id)
	return c ~= nil and c.skeleton == "valvebiped"
end

-- The host every faction's soldiers use: the MW19 body.
function A.HostFor(fac)
	return A.MW_HOST
end

-- All clips available to a host character, keyed by clip name.
function A.Clips(id)
	local c = A.Character(id)
	return c and GTG.Clips[c.clips] or nil
end

function A.Clip(name, id)
	local clips = A.Clips(id)
	return clips and clips[name] or nil
end

-- Vehicle seats ---------------------------------------------------------------------------------
-- TIF's MW cars and helis answer for their own seats (ENT:TIFSeatPose / TIFSeatEntry, sv_vehicle). Any other Glide
-- vehicle (0.38.0: generic MW seat, user): an MW car's seated idle placed on the Glide seat pod, no door or get-in
-- clip (sv_vehicle walks him to the exit spot and sits him). Driver: the Cherokee driver; front passenger: its
-- passenger; rear seats: its rear idles. The MW seat clips stand MW_SEAT_DROP below the seat (their root is the car
-- floor: tag_seat is 38 above it in the MW cars); tif_mw_seat_drop tunes it live.
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
	local lyaw = veh:WorldToLocalAngles(pod:GetAngles()).y + 90 -- (pods face local yaw - 90)
	return { lp = lp, yaw = lyaw, clip = name, driver = n == 1, exact = true }
end

-- No get-in / get-out clips for other vehicles (sv_vehicle uses Glide's exit spot).
function A.SeatEntry(veh, n, hostId) return nil end

-- The part of a clip where the door moves (0..1 of the clip), from its "Door" tags, or nil.
function A.DoorWindow(clip)
	local a, b
	for _, t in ipairs(clip and clip.tags or {}) do
		if t[1] == "Door" and istable(t[4]) then
			if t[4].Start == true and not a then a = t[2] elseif t[4].Start == false and a and not b then b = t[2] end
		end
	end
	if a and b and b > a then return a, b end
	return nil
end

-- Drive-bys (window shooting) were GTA clips; dropped in 0.38.0 (user). Bed gunners on MW technicals still fire
-- (tif_mw_cars ENT:TIFRideThink).
function A.DriveBySet() return nil end
function A.DriveByWeapon() return false end
function A.SweepPhase() return 0.5 end

-- Doors opened by soldiers: NW2 float "tif_door<entry index>", 0..1 (MW cars pose their own doors from it).
if SERVER then
	function A.SetDoor(veh, index, ratio)
		veh:SetNW2Float("tif_door" .. index, math.Clamp(ratio, 0, 1))
		veh.tifHasDoors = true
		veh:SetNW2Bool("tif_doors", true)
	end
end

-- Gunfire and rockets (server) ----------------------------------------------------------------
if SERVER then
	-- (GTG's GTA gun audio is gone; sv_weapon plays the gun's MW sound or its own sound script.)
	function A.GunShot() return false end

	-- Launch a weapon's projectile as the soldier: TIF's rocket (entities/tif_rocket.lua).
	function A.Launch(npc, def, class, pos, dir)
		local p = def and def.projectile
		if not p then return nil end
		local e = ents.Create(p.entity or "tif_rocket")
		if not IsValid(e) then return nil end
		e:SetPos(pos)
		e:SetAngles(dir:Angle())
		if e.Setup then e:Setup(p, dir, npc) end
		e:Spawn()
		e:Activate()
		return e
	end
end

-- TIF weapon table (SWEP.GTG) for a weapon class, or nil.
function A.WeaponDef(class)
	local stored = A.Stored(class)
	if stored and istable(stored.GTG) then return stored.GTG end
	return nil
end

-- Which MW19 weapon set a gun uses, from its hold: "pistol" | "shotgun" | "rpg" | "lmg" | "smg" | "rifle".
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

-- Every weapon class TIF has a definition for (its MW guns).
function A.WeaponClasses()
	local out = {}
	for class, w in pairs(istable(TIFG) and TIFG.Weapons or {}) do
		if istable(w.GTG) and w.Primary and (w.Primary.ClipSize or 0) > 0 then out[#out + 1] = class end
	end
	table.sort(out)
	return out
end

-- (GTA relaxed-carry hold sets: gone with the GTA body.)
function A.HoldSet() return nil end

-- Frame of a looping clip at a foot-synced gait phase (strides: whole numbers left heel strikes, .5 right). Clips
-- without foot data fall back to phase % 1.
function A.FrameForPhase(clip, phase)
	if istable(GTG) and GTG.ClipFrameForPhase then return GTG.ClipFrameForPhase(clip, phase) end
	return (phase % 1) * math.max(1, clip.frames - 1)
end

-- Root motion curve value at a frame. axis: 1 = x (forward), 2 = y (left), 3 = yaw (CCW).
function A.ClipCurve(clip, frame, axis)
	if not (istable(GTG) and GTG.ClipCurve) then return 0 end
	return GTG.ClipCurve(clip, frame, axis)
end

-- Strides per second of a clip at its authored speed.
function A.StrideRate(clip)
	return clip.stride_rate or clip.phase_rate or 1 / math.max(0.1, clip.dur)
end

-- Skeleton reader and retarget map (TIFG.PMS): faction models on another rig's rest pose (codport CoD ports,
-- config/sh_modular.lua) wear the MW body through a retarget instead of a plain bone-merge.
function A.Skeleton(model)
	if not (istable(GTG) and istable(GTG.PMS) and GTG.PMS.Skeleton) then return nil end
	return GTG.PMS.Skeleton(model)
end

function A.MapFor(hostModel, visualModel)
	if not (istable(GTG) and istable(GTG.PMS) and GTG.PMS.MapFor) then return nil end
	return GTG.PMS.MapFor(hostModel, visualModel)
end

if CLIENT then
	function A.Solve(ent, map)
		GTG.PMS.Solve(ent, map, nil, nil)
	end
end
