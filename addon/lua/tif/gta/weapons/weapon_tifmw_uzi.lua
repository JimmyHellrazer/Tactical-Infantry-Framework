local base = TIFG.WeaponBases and TIFG.WeaponBases["smg"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_uzi"
SWEP.PrintName = "UZI"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/uzi.mdl"

SWEP.Primary = { ClipSize = 32, DefaultClip = 32, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.1000
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 2.30
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "uzi", swep = "mg_uzulu", tiers = { "rebel" } }

SWEP.GTG.mw = { fire = "weap_uzulu_fire_plr", tailOut = "Atmo_SMG.Outside", tailIn = "Atmo_SMG.Inside", reload = { { 0, "ps_wfoly_plr_sm_uzulu_reload_01" }, { 0.2532, "ps_wfoly_plr_sm_uzulu_reload_02" }, { 0.28, "ps_wfoly_plr_sm_uzulu_reload_03" }, { 0.44, "ps_wfoly_plr_sm_uzulu_reload_04" }, { 0.5732, "ps_wfoly_plr_sm_uzulu_reload_05" }, { 0.68, "ps_wfoly_plr_sm_uzulu_reload_06" }, { 0.8132, "ps_wfoly_plr_sm_uzulu_reload_07" } }, reloadEmpty = { { 0, "ps_wfoly_plr_sm_uzulu_reload_empty_01" }, { 0.143692, "ps_wfoly_plr_sm_uzulu_reload_empty_02" }, { 0.194769, "ps_wfoly_plr_sm_uzulu_reload_empty_03" }, { 0.348615, "ps_wfoly_plr_sm_uzulu_reload_empty_04" }, { 0.379385, "ps_wfoly_plr_sm_uzulu_reload_empty_05" }, { 0.523077, "ps_wfoly_plr_sm_uzulu_reload_empty_06" }, { 0.717846, "ps_wfoly_plr_sm_uzulu_reload_empty_07" }, { 0.861538, "ps_wfoly_plr_sm_uzulu_reload_empty_08" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 3.8394, -2.5641, -10.583 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.63993, 0.67136, 0.37385, -0.26695, -0.26198, 0.92742, 0.72057, -0.69328, 0.01157 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.76357, -0.14115, -0.63011, 0.25182, 0.96365, 0.08928, 0.5946, -0.22685, 0.77136 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.94091, -0.33843, 0.01242, 0.33841, 0.94099, 0.0038, -0.01297, 0.00063, 0.99992 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.81069, 0.43184, 0.39533, -0.4618, 0.88672, -0.02161, -0.35988, -0.16505, 0.91828 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.27613, 0.95907, -0.06272, -0.95506, 0.28112, 0.09397, 0.10775, 0.03395, 0.9936 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.91986, 0.39209, -0.01078, -0.39212, 0.91992, 9e-05, 0.00995, 0.00414, 0.99994 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.45384, 0.81095, 0.3693, -0.86004, 0.50708, -0.05661, -0.23317, -0.29192, 0.92758 }, ["ValveBiped.Bip01_L_Finger21"] = { -0.03077, 0.99908, -0.02984, -0.9988, -0.02959, 0.03909, 0.03817, 0.03101, 0.99879 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.8957, -0.44414, 0.02138, 0.44406, 0.89596, 0.00834, -0.02286, 0.00203, 0.99974 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.09295, 0.88437, 0.45743, -0.99513, 0.06739, 0.07191, 0.03277, -0.46189, 0.88633 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.42303, 0.90563, 0.02976, -0.90555, 0.4237, -0.0214, -0.03199, -0.0179, 0.99933 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.85608, -0.51642, -0.02074, 0.51632, 0.85633, -0.0101, 0.02298, -0.00206, 0.99973 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.20882, 0.62248, 0.75426, -0.95586, -0.29292, -0.02289, 0.20669, -0.72575, 0.65617 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.80749, 0.5667, 0.16372, -0.55758, 0.82387, -0.1017, -0.19251, -0.00917, 0.98125 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.86694, -0.4625, -0.18576, 0.4578, 0.88629, -0.07012, 0.19706, -0.02425, 0.98009 } }, fingerPose = "sm_uzulu_l" }
TIFG.RegisterWeaponDef(SWEP)
