local base = TIFG.WeaponBases and TIFG.WeaponBases["marksman"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_svd_plague"
SWEP.PrintName = "SVD PLAGUE"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/svd_plague.mdl"

SWEP.Primary = { ClipSize = 10, DefaultClip = 10, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.3000
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 2.50
SWEP.GTG.semi = "dmr"
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "svd_plague", swep = "mg_delta", tiers = { "ru_sof" } }

SWEP.GTG.mw = { fire = "weap_delta_fire_plr", tailOut = "Atmo_Sniper2.Outside", tailIn = "Atmo_Shotgun.Inside", reload = { { 0.0101538, "wfoly_plr_sn_delta_reload_01" }, { 0.153846, "wfoly_plr_sn_delta_reload_02" }, { 0.276923, "wfoly_plr_sn_delta_reload_03" }, { 0.492308, "wfoly_plr_sn_delta_reload_04" }, { 0.574462, "wfoly_plr_sn_delta_reload_05" }, { 0.707692, "wfoly_plr_sn_delta_reload_055" }, { 0.8, "wfoly_plr_sn_delta_reload_06" } }, reloadEmpty = { { 0.0697674, "wfoly_plr_sn_delta_reload_empty_01" }, { 0.193721, "wfoly_plr_sn_delta_reload_empty_02" }, { 0.216977, "wfoly_plr_sn_delta_reload_empty_03" }, { 0.356512, "wfoly_plr_sn_delta_reload_empty_04" }, { 0.527209, "wfoly_plr_sn_delta_reload_empty_045" }, { 0.635581, "wfoly_plr_sn_delta_reload_empty_05" }, { 0.72093, "wfoly_plr_sn_delta_reload_empty_06" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 1.02, -2.9263, -10.8844 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.6611, 0.6836, 0.30925, -0.22732, -0.2103, 0.95084, 0.71503, -0.6989, 0.01637 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.80102, -0.47371, -0.36601, 0.55843, 0.81158, 0.17173, 0.2157, -0.34195, 0.91463 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.98431, 0.16479, 0.06309, -0.1641, 0.98631, -0.01598, -0.06486, 0.00538, 0.99788 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.8287, 0.25757, 0.4969, -0.36368, 0.92265, 0.12827, -0.42543, -0.28702, 0.85827 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.48047, 0.87396, -0.07308, -0.87336, 0.4844, 0.05102, 0.07999, 0.03931, 0.99602 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.76735, 0.64032, -0.03425, -0.6405, 0.76793, 0.00683, 0.03067, 0.01669, 0.99939 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.50287, 0.60733, 0.61504, -0.85462, 0.45588, 0.24859, -0.12942, -0.65063, 0.74828 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.06103, 0.9977, -0.02967, -0.99741, 0.06209, 0.03635, 0.03811, 0.02737, 0.9989 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.96645, -0.25633, 0.01663, 0.2563, 0.96659, 0.00439, -0.0172, 2e-05, 0.99985 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.18715, 0.752, 0.63204, -0.95254, -0.01834, 0.30387, 0.2401, -0.65891, 0.71288 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.49327, 0.8694, 0.02862, -0.86933, 0.49386, -0.01897, -0.03063, -0.01552, 0.99941 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.99076, -0.13524, -0.01021, 0.13521, 0.99081, -0.00387, 0.01064, 0.00245, 0.99994 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.05122, 0.47891, 0.87637, -0.86589, -0.45852, 0.19996, 0.4976, -0.7486, 0.43817 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.83844, 0.52357, 0.15128, -0.51515, 0.85198, -0.09352, -0.17786, 0.00048, 0.98406 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.95052, -0.27762, -0.1394, 0.2751, 0.96069, -0.03743, 0.14431, -0.00277, 0.98953 } }, fingerPose = "sn_delta_l" }
TIFG.RegisterWeaponDef(SWEP)
