local function wavs(base, n)
	local t = {}
	for i = 1, n do t[i] = string.format("tif/at4/%s_%02d.ogg", base, i) end
	return t
end
sound.Add({ name = "TIF_AT4.Fire", channel = CHAN_WEAPON, volume = 1, level = 140, pitch = { 97, 103 }, sound = wavs("shot", 4) })
sound.Add({ name = "TIF_AT4.TailOut", channel = CHAN_AUTO, volume = 0.9, level = 150, pitch = { 98, 102 }, sound = wavs("tail", 3) })
sound.Add({ name = "TIF_AT4.TailIn", channel = CHAN_AUTO, volume = 0.9, level = 120, pitch = { 98, 102 }, sound = wavs("tail_in", 3) })
local base = TIFG.WeaponBases and TIFG.WeaponBases["launcher"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_at4"
SWEP.PrintName = "AT4"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/at4.mdl"
SWEP.Primary = { ClipSize = 1, DefaultClip = 1, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.8000
SWEP.GTG.auto = false
SWEP.GTG.disposable = true
SWEP.GTG.spentModel = "models/tif_guns/at4_spent.mdl"
SWEP.GTG.reload_time = 0
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "at4", tiers = { "infantry" } }
SWEP.GTG.mw = { fire = "TIF_AT4.Fire", tailOut = "TIF_AT4.TailOut", tailIn = "TIF_AT4.TailIn" }
SWEP.TIFBaked.hold = { jgun = { t = { 0.1527, -2.5329, -10.93 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.41727, 0.64032, 0.64489, -0.12377, -0.66296, 0.73835, 0.90032, -0.38791, -0.19738 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.82721, -0.02923, -0.56113, 0.08719, 0.99323, 0.07679, 0.55508, -0.11245, 0.82416 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.80804, -0.58832, -0.03081, 0.58905, 0.80767, 0.02636, 0.00938, -0.03945, 0.99918 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.82144, 0.23323, 0.52042, -0.35689, 0.92201, 0.15011, -0.44482, -0.30904, 0.84061 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.47997, 0.87499, -0.06337, -0.8728, 0.48356, 0.06621, 0.08858, 0.02353, 0.99579 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.85376, 0.51974, -0.03093, -0.51941, 0.85432, 0.01845, 0.03601, 0.00031, 0.99935 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.37386, 0.67787, 0.63302, -0.9273, 0.2596, 0.26966, 0.01846, -0.68782, 0.72565 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.02472, 0.99919, -0.03171, -0.99817, 0.02642, 0.05434, 0.05513, 0.03031, 0.99802 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.98611, -0.16607, -0.00289, 0.16607, 0.98611, 0.00176, 0.00256, -0.00221, 0.99999 }, ["ValveBiped.Bip01_L_Finger3"] = { -0.01017, 0.67572, 0.73709, -0.89227, -0.33888, 0.29836, 0.4514, -0.65464, 0.60637 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.70629, 0.70778, 0.01411, -0.70787, 0.70633, 0.00231, -0.00833, -0.01162, 0.9999 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.99328, -0.11266, -0.02637, 0.1127, 0.99363, 0.0002, 0.02618, -0.00317, 0.99965 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.00444, 0.45461, 0.89068, -0.87348, -0.4354, 0.21787, 0.48684, -0.77702, 0.39902 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.76676, 0.61978, 0.16715, -0.61237, 0.78433, -0.09914, -0.19255, -0.02634, 0.98093 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.95561, -0.25284, -0.15123, 0.25122, 0.96746, -0.0301, 0.15392, -0.00923, 0.98804 } }, fingerPose = "ar_akilo47_l", gripL = { 7, 7.7, 0.3 } }
TIFG.RegisterWeaponDef(SWEP)
