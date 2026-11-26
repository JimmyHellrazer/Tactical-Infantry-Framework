local base = TIFG.WeaponBases and TIFG.WeaponBases["rifle"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_an94"
SWEP.PrintName = "AN94"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/an94.mdl"

SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.0923
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 2.40
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "an94", swep = "mg_anovember94", tiers = { "ru_sof" } }

SWEP.GTG.mw = { fire = "mw19.anovember94.fire", tailOut = "Atmo_AR5.Outside", tailIn = "Atmo_AR.Inside", reload = { { 0.0279167, "ps_wfoly_plr_ar_anovember94_reload_01" }, { 0.291667, "ps_wfoly_plr_ar_anovember94_reload_02" }, { 0.36125, "ps_wfoly_plr_ar_anovember94_reload_03" }, { 0.555417, "ps_wfoly_plr_ar_anovember94_reload_04" }, { 0.666667, "ps_wfoly_plr_ar_anovember94_reload_045" }, { 0.777917, "ps_wfoly_plr_ar_anovember94_reload_05" }, { 0.875, "ps_wfoly_plr_ar_anovember94_reload_06" } }, reloadEmpty = { { 0, "ps_wfoly_plr_ar_anovember94_reload_empty_01" }, { 0.230769, "ps_wfoly_plr_ar_anovember94_reload_empty_02" }, { 0.281923, "ps_wfoly_plr_ar_anovember94_reload_empty_03" }, { 0.538462, "ps_wfoly_plr_ar_anovember94_reload_empty_04" }, { 0.615385, "ps_wfoly_plr_ar_anovember94_reload_empty_045" }, { 0.718077, "ps_wfoly_plr_ar_anovember94_reload_empty_05" }, { 0.820385, "ps_wfoly_plr_ar_anovember94_reload_empty_06" }, { 0.884615, "ps_wfoly_plr_ar_anovember94_reload_empty_07" } } }

SWEP.TIFBaked.hold = { jgun = { t = { -0.986, -2.6976, -10.9765 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.52452, 0.74593, 0.41045, -0.32523, -0.26999, 0.90627, 0.78683, -0.60885, 0.10098 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.78561, -0.23855, -0.57088, 0.41976, 0.88336, 0.20853, 0.45455, -0.40346, 0.79411 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.98578, -0.168, 0.00209, 0.16729, 0.98258, 0.08096, -0.01566, -0.07946, 0.99671 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.78012, 0.34394, 0.5226, -0.39421, 0.91888, -0.01628, -0.48581, -0.19332, 0.85242 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.61709, 0.7854, -0.04845, -0.78265, 0.61899, 0.06564, 0.08154, -0.00259, 0.99667 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.6058, 0.79402, -0.0504, -0.79442, 0.60714, 0.01641, 0.04363, 0.0301, 0.99859 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.3983, 0.82911, 0.39233, -0.90148, 0.43281, 0.00054, -0.16936, -0.3539, 0.91982 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.1725, 0.98458, -0.02917, -0.98429, 0.17343, 0.03299, 0.03754, 0.02302, 0.99903 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.89573, -0.44408, 0.02139, 0.44401, 0.89598, 0.00827, -0.02284, 0.00209, 0.99974 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.06477, 0.86879, 0.49093, -0.99427, 0.01424, 0.10597, 0.08508, -0.49497, 0.86473 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.46791, 0.88205, 0.05526, -0.88326, 0.46886, -0.00486, -0.0302, -0.04653, 0.99846 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.94719, -0.31999, -0.02117, 0.32044, 0.94698, 0.02349, 0.01253, -0.02903, 0.9995 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.33891, 0.54484, 0.767, -0.88111, -0.46962, -0.05574, 0.32983, -0.6947, 0.63923 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.88866, 0.43277, 0.15165, -0.43196, 0.90101, -0.03998, -0.15394, -0.02998, 0.98762 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.9317, -0.32841, -0.15516, 0.33264, 0.94305, 0.00138, 0.14587, -0.05289, 0.98789 } }, fingerPose = "ar_anovember94_l" }
TIFG.RegisterWeaponDef(SWEP)
