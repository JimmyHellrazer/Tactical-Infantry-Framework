local base = TIFG.WeaponBases and TIFG.WeaponBases["marksman"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_m13_dmr"
SWEP.PrintName = "M13 DMR"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/m13_dmr.mdl"

SWEP.Primary = { ClipSize = 20, DefaultClip = 20, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.2000
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 2.40
SWEP.GTG.semi = "dmr"
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "m13_dmr", swep = "mg_mcharlie", tiers = { "sof" } }
SWEP.MWA_Suppressed = true

SWEP.GTG.mw = { fire = "mw19_mcharlie.fire.s", tailOut = "Atmo_AR_Sup.Outside", tailIn = "Atmo_AR_Sup.Inside", reload = { { 0.0291304, "wfoly_plr_ar_mcharlie_reload_01" }, { 0.130435, "wfoly_plr_ar_mcharlie_reload_02" }, { 0.478261, "wfoly_plr_ar_mcharlie_reload_04" }, { 0.478261, "wfoly_plr_ar_mcharlie_reload_03" }, { 0.578261, "wfoly_plr_ar_mcharlie_reload_045" } }, reloadEmpty = { { 0.0264, "wfoly_plr_ar_mcharlie_reload_empty_01" }, { 0.212, "wfoly_plr_ar_mcharlie_reload_empty_02" }, { 0.28, "wfoly_plr_ar_mcharlie_reload_empty_03" }, { 0.5464, "wfoly_plr_ar_mcharlie_reload_empty_045" }, { 0.5464, "wfoly_plr_ar_mcharlie_reload_empty_04" }, { 0.76, "wfoly_plr_ar_mcharlie_reload_empty_05" }, { 0.76, "wfoly_plr_ar_mcharlie_reload_empty_06" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 0.5308, -3.1839, -11.6745 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.01596, 0.65995, 0.75114, -0.52792, -0.63243, 0.56687, 0.84914, -0.40559, 0.33831 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.57949, -0.81459, 0.02514, 0.79324, 0.57085, 0.2119, -0.18697, -0.10285, 0.97697 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.7486, -0.64528, -0.15234, 0.64266, 0.7627, -0.07257, 0.16302, -0.04358, 0.98566 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.83156, 0.30337, 0.46527, -0.24541, 0.95214, -0.18221, -0.49828, 0.03733, 0.86621 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.57576, 0.81478, -0.0681, -0.81421, 0.57896, 0.04313, 0.07457, 0.03062, 0.99675 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.88696, 0.46152, -0.01714, -0.46157, 0.8871, 0.0012, 0.01576, 0.00685, 0.99985 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.35442, 0.73746, 0.57493, -0.90243, 0.43081, 0.00371, -0.24495, -0.52015, 0.8182 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.20814, 0.97767, -0.02899, -0.97739, 0.20903, 0.03196, 0.03731, 0.02168, 0.99907 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.96899, 0.24707, 0.00201, -0.24707, 0.969, -0.00075, -0.00213, 0.00023, 1 }, ["ValveBiped.Bip01_L_Finger3"] = { -0.00569, 0.76718, 0.6414, -0.99998, -0.00282, -0.00549, -0.00241, -0.64142, 0.76718 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.43989, 0.89756, 0.02956, -0.89749, 0.44054, -0.02088, -0.03177, -0.01734, 0.99934 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.9675, 0.25285, 0.00145, -0.25285, 0.9675, -0.00228, -0.00198, 0.00184, 1 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.24712, 0.42483, 0.87089, -0.96731, -0.16096, -0.19596, 0.05693, -0.89085, 0.45072 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.67195, 0.71158, 0.20527, -0.70109, 0.7005, -0.13332, -0.23866, -0.05433, 0.96958 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.99149, 0.12696, -0.02875, -0.12709, 0.99189, -0.0026, 0.02818, 0.00623, 0.99958 } }, fingerPose = "ar_mcharlie_l" }
TIFG.RegisterWeaponDef(SWEP)
