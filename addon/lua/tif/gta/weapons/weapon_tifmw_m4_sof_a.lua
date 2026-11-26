local base = TIFG.WeaponBases and TIFG.WeaponBases["rifle"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_m4_sof_a"
SWEP.PrintName = "M4 SOF A"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/m4_sof_a.mdl"

SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.0750
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 2.30
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "m4_sof_a", swep = "mg_mike4", tiers = { "infantry", "sof" } }

SWEP.GTG.mw = { fire = "mw19.mike4.fire", tailOut = "Atmo_AR2.Outside", tailIn = "Atmo_AR.Inside", reload = { { 0, "wfoly_plr_ar_mike4_reload_01" }, { 0.318182, "wfoly_plr_ar_mike4_reload_02" }, { 0.513636, "wfoly_plr_ar_mike4_reload_03" }, { 0.604545, "wfoly_plr_ar_mike4_reload_04" }, { 0.8, "wfoly_plr_ar_mike4_reload_05" } }, reloadEmpty = { { 0, "wfoly_plr_ar_mike4_reload_empty_01" }, { 0.113043, "wfoly_plr_ar_mike4_reload_empty_02" }, { 0.447826, "wfoly_plr_ar_mike4_reload_empty_03" }, { 0.578261, "wfoly_plr_ar_mike4_reload_empty_04" }, { 0.765217, "wfoly_plr_ar_mike4_reload_empty_05" }, { 0.926087, "wfoly_plr_ar_mike4_reload_empty_06" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 0.4319, -2.2339, -11.237 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.62419, 0.67954, 0.38551, -0.28541, -0.261, 0.92218, 0.72728, -0.68564, 0.03103 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.82047, -0.35525, -0.44792, 0.45177, 0.88302, 0.12719, 0.35034, -0.30671, 0.88498 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.99874, 0.01112, 0.04895, -0.01078, 0.99992, -0.0073, -0.04903, 0.00676, 0.99877 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.83793, 0.2176, 0.50053, -0.31955, 0.93906, 0.1267, -0.44246, -0.26611, 0.8564 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.81155, 0.58223, -0.04882, -0.58183, 0.81297, 0.02351, 0.05338, 0.00932, 0.99853 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.99294, 0.1183, 0.0082, -0.11829, 0.99298, -0.00225, -0.00841, 0.00127, 0.99996 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.68714, 0.37199, 0.62407, -0.62025, 0.74766, 0.23727, -0.37833, -0.55011, 0.74447 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.28051, 0.95943, -0.02844, -0.95915, 0.28131, 0.02976, 0.03656, 0.01893, 0.99915 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.99564, -0.09252, 0.01216, 0.0925, 0.99571, 0.00189, -0.01228, -0.00076, 0.99992 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.54555, 0.55812, 0.6252, -0.83146, 0.454, 0.32025, -0.10511, -0.69454, 0.71173 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.64865, 0.76067, 0.02517, -0.76061, 0.64906, -0.01397, -0.02696, -0.01008, 0.99959 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.81608, 0.57782, 0.01199, -0.5778, 0.81616, -0.00487, -0.0126, -0.00296, 0.99992 }, ["ValveBiped.Bip01_L_Finger4"] = { 0.21157, 0.45128, 0.86694, -0.94009, -0.14867, 0.30681, 0.26735, -0.87991, 0.39279 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.8873, 0.44306, 0.12802, -0.43593, 0.89635, -0.08077, -0.15053, 0.01586, 0.98848 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.99162, -0.09248, -0.09022, 0.09143, 0.99569, -0.01571, 0.09128, 0.00733, 0.9958 } }, fingerPose = "ar_mike4_l" }
TIFG.RegisterWeaponDef(SWEP)
