local base = TIFG.WeaponBases and TIFG.WeaponBases["rifle"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_oden"
SWEP.PrintName = "ODEN"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/oden.mdl"

SWEP.Primary = { ClipSize = 20, DefaultClip = 20, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.1154
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 2.10
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "oden", swep = "mg_asierra12", tiers = { "ru_infantry" } }

SWEP.GTG.mw = { fire = "mw19.asierra12.fire", tailOut = "Atmo_AR2.Outside", tailIn = "Atmo_AR.Inside", reload = { { 0.0264, "wfoly_plr_ar_asierra12_reload_01" }, { 0.092, "wfoly_plr_ar_asierra12_reload_02" }, { 0.224, "wfoly_plr_ar_asierra12_reload_03" }, { 0.584, "wfoly_plr_ar_asierra12_reload_04" }, { 0.784, "wfoly_plr_ar_asierra12_reload_045" }, { 0.88, "wfoly_plr_ar_asierra12_reload_05" } }, reloadEmpty = { { 0.0194118, "wfoly_plr_ar_asierra12_reload_empty_01" }, { 0.105882, "wfoly_plr_ar_asierra12_reload_empty_02" }, { 0.214706, "wfoly_plr_ar_asierra12_reload_empty_03" }, { 0.391176, "wfoly_plr_ar_asierra12_reload_empty_04" }, { 0.479412, "wfoly_plr_ar_asierra12_reload_empty_05" }, { 0.567647, "wfoly_plr_ar_asierra12_reload_empty_055" }, { 0.664706, "wfoly_plr_ar_asierra12_reload_empty_06" }, { 0.714706, "wfoly_plr_ar_asierra12_reload_empty_07" }, { 0.852941, "wfoly_plr_ar_asierra12_reload_empty_08" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 0.1527, -2.5329, -10.93 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.36819, 0.54395, 0.75402, -0.80126, -0.22573, 0.5541, 0.47161, -0.80818, 0.35274 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.7357, -0.533, -0.41792, 0.61764, 0.78118, 0.09099, 0.27797, -0.32507, 0.90392 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.58379, -0.80946, -0.06299, 0.81154, 0.58409, 0.01546, 0.02428, -0.06014, 0.99789 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.32711, 0.94498, 0.00176, -0.94463, 0.32704, -0.02694, -0.02603, 0.00715, 0.99964 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.40064, 0.91306, -0.07618, -0.91242, 0.40517, 0.05772, 0.08357, 0.04639, 0.99542 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.86583, 0.4999, -0.02078, -0.49997, 0.86604, 0.00208, 0.01903, 0.00859, 0.99978 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.18687, 0.98197, 0.02864, -0.97502, 0.18183, 0.12761, 0.1201, -0.05177, 0.99141 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.06545, 0.99741, -0.0297, -0.99713, 0.06651, 0.03617, 0.03805, 0.02724, 0.9989 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.92607, 0.37734, -0.00221, -0.37734, 0.92607, -0.00081, 0.00174, 0.00159, 1 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.2825, 0.93199, 0.22712, -0.93373, 0.2129, 0.28777, 0.21985, -0.29337, 0.93038 }, ["ValveBiped.Bip01_L_Finger31"] = { -0.1447, 0.98895, 0.03238, -0.98887, -0.14338, -0.03982, -0.03474, -0.03778, 0.99868 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.90156, 0.43259, 0.00718, -0.43258, 0.90159, -0.00318, -0.00785, -0.00023, 0.99997 }, ["ValveBiped.Bip01_L_Finger4"] = { 0.58775, 0.73629, 0.3353, -0.80218, 0.47647, 0.35984, 0.10519, -0.48047, 0.87068 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.2364, 0.93357, 0.26937, -0.9198, 0.30437, -0.24766, -0.31319, -0.18922, 0.93065 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.67745, 0.71855, 0.15731, -0.72145, 0.69077, -0.04838, -0.14343, -0.08072, 0.98636 } }, fingerPose = "ar_akilo47_vertgrip_l" }
TIFG.RegisterWeaponDef(SWEP)
