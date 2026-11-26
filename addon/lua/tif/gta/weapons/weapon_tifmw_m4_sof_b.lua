local base = TIFG.WeaponBases and TIFG.WeaponBases["rifle"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_m4_sof_b"
SWEP.PrintName = "M4 SOF B"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/m4_sof_b.mdl"

SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.0750
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 2.30
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "m4_sof_b", swep = "mg_mike4", tiers = { "infantry", "sof" } }

SWEP.GTG.mw = { fire = "mw19.mike4.fire", tailOut = "Atmo_AR2.Outside", tailIn = "Atmo_AR.Inside", reload = { { 0, "wfoly_plr_ar_mike4_reload_01" }, { 0.318182, "wfoly_plr_ar_mike4_reload_02" }, { 0.513636, "wfoly_plr_ar_mike4_reload_03" }, { 0.604545, "wfoly_plr_ar_mike4_reload_04" }, { 0.8, "wfoly_plr_ar_mike4_reload_05" } }, reloadEmpty = { { 0, "wfoly_plr_ar_mike4_reload_empty_01" }, { 0.113043, "wfoly_plr_ar_mike4_reload_empty_02" }, { 0.447826, "wfoly_plr_ar_mike4_reload_empty_03" }, { 0.578261, "wfoly_plr_ar_mike4_reload_empty_04" }, { 0.765217, "wfoly_plr_ar_mike4_reload_empty_05" }, { 0.926087, "wfoly_plr_ar_mike4_reload_empty_06" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 0.4319, -2.2339, -11.237 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.36001, 0.88295, 0.30131, -0.02404, -0.31408, 0.94909, 0.93264, -0.34893, -0.09184 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.62312, -0.30156, -0.72165, 0.70201, 0.62242, 0.34607, 0.34481, -0.72225, 0.59954 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.92275, -0.36115, -0.13454, 0.32597, 0.91761, -0.22746, 0.2056, 0.16603, 0.96445 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.6373, 0.75633, 0.14771, -0.74024, 0.65411, -0.1555, -0.21423, -0.01024, 0.97673 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.64319, 0.76305, -0.06376, -0.76252, 0.64587, 0.0375, 0.0698, 0.0245, 0.99726 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.7393, 0.67233, -0.03755, -0.67254, 0.74001, 0.00836, 0.03341, 0.01908, 0.99926 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.46176, 0.87278, 0.15823, -0.87737, 0.47564, -0.06313, -0.13036, -0.10967, 0.98538 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.30556, 0.95176, -0.02816, -0.95148, 0.30633, 0.02907, 0.03629, 0.01791, 0.99918 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.72362, 0.69007, -0.01335, -0.69011, 0.7237, 0.00193, 0.01099, 0.00782, 0.99991 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.50439, 0.83814, 0.20761, -0.85556, 0.51758, -0.01092, -0.11661, -0.17212, 0.97815 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.41224, 0.91058, 0.02995, -0.91051, 0.41292, -0.0217, -0.03213, -0.01833, 0.99932 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.60539, 0.79569, 0.01972, -0.79568, 0.60563, -0.00993, -0.01984, -0.00968, 0.99976 }, ["ValveBiped.Bip01_L_Finger4"] = { 0.67678, 0.56591, 0.47087, -0.69788, 0.69681, 0.16559, -0.2344, -0.44067, 0.86653 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.63981, 0.73842, 0.21302, -0.72752, 0.67127, -0.14178, -0.24769, -0.06426, 0.96671 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.61508, 0.76871, 0.1754, -0.77244, 0.6321, -0.0615, -0.15815, -0.09766, 0.98257 } }, fingerPose = "ar_mike4_l_grip" }
TIFG.RegisterWeaponDef(SWEP)
