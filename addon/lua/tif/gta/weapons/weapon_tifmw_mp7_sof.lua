local base = TIFG.WeaponBases and TIFG.WeaponBases["smg"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_mp7_sof"
SWEP.PrintName = "MP7 SOF"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/mp7_sof.mdl"

SWEP.Primary = { ClipSize = 40, DefaultClip = 40, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.0632
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 2.30
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "mp7_sof", swep = "mg_mpapa7", tiers = { "sof" } }
SWEP.MWA_Suppressed = true

SWEP.GTG.mw = { fire = "weap_mpapa7_fire_plr_sup", tailOut = "Atmo_SMG_Sup.Outside", tailIn = "Atmo_Pistol_Sup.Inside", reload = { { 0.0157143, "ps_wfoly_plr_sm_mpapa7_reload_01" }, { 0.190476, "ps_wfoly_plr_sm_mpapa7_reload_02" }, { 0.25381, "ps_wfoly_plr_sm_mpapa7_reload_03" }, { 0.365238, "ps_wfoly_plr_sm_mpapa7_reload_04" }, { 0.571429, "ps_wfoly_plr_sm_mpapa7_reload_05" }, { 0.682381, "ps_wfoly_plr_sm_mpapa7_reload_055" }, { 0.809524, "ps_wfoly_plr_sm_mpapa7_reload_06" } }, reloadEmpty = { { 0.0152778, "ps_wfoly_plr_sm_mpapa7_reload_empty_01" }, { 0.169907, "ps_wfoly_plr_sm_mpapa7_reload_empty_02" }, { 0.416667, "ps_wfoly_plr_sm_mpapa7_reload_empty_03" }, { 0.586574, "ps_wfoly_plr_sm_mpapa7_reload_empty_035" }, { 0.648148, "ps_wfoly_plr_sm_mpapa7_reload_empty_04" }, { 0.709722, "ps_wfoly_plr_sm_mpapa7_reload_empty_05" }, { 0.87963, "ps_wfoly_plr_sm_mpapa7_reload_empty_06" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 3.3038, -3.348, -10.7825 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.46374, 0.88548, 0.02966, -0.44379, 0.20318, 0.87279, 0.76681, -0.41791, 0.48719 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.48859, -0.81376, -0.31478, 0.87084, 0.47717, 0.11812, 0.05408, -0.33183, 0.94179 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.97344, 0.22894, 0.00301, -0.22832, 0.96964, 0.0876, 0.01713, -0.08596, 0.99615 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.72383, 0.2822, 0.62963, -0.38308, 0.92333, 0.02656, -0.57386, -0.26043, 0.77644 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.95813, 0.28531, -0.02419, -0.28511, 0.95843, 0.01126, 0.0264, -0.00389, 0.99964 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.93762, 0.34748, -0.01157, -0.34753, 0.93766, -0.00288, 0.00985, 0.00672, 0.99993 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.53844, 0.43935, 0.71907, -0.75068, 0.63777, 0.17243, -0.38284, -0.63263, 0.67321 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.77228, 0.63501, -0.01851, -0.63482, 0.77251, 0.01526, 0.02399, -3e-05, 0.99971 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.89419, 0.44767, -0.00452, -0.44767, 0.8942, -0.00061, 0.00377, 0.00257, 0.99999 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.3937, 0.48783, 0.77911, -0.89562, 0.39444, 0.20561, -0.20701, -0.77874, 0.59221 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.67278, 0.73944, 0.02449, -0.73938, 0.67316, -0.01318, -0.02623, -0.00924, 0.99961 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.93903, 0.3438, 0.00438, -0.34379, 0.93904, -0.00261, -0.00501, 0.00094, 0.99999 }, ["ValveBiped.Bip01_L_Finger4"] = { 0.24562, 0.40583, 0.88033, -0.9656, 0.02248, 0.25905, 0.08534, -0.91367, 0.39739 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.78048, 0.60062, 0.17351, -0.59095, 0.79934, -0.10878, -0.20403, -0.01764, 0.97881 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.97859, 0.20573, -0.00585, -0.20574, 0.97861, -0.00122, 0.00547, 0.0024, 0.99998 } }, fingerPose = "sm_mpapa7_gripvert_l" }
TIFG.RegisterWeaponDef(SWEP)
