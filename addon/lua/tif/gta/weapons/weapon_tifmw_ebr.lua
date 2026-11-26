local base = TIFG.WeaponBases and TIFG.WeaponBases["marksman"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_ebr"
SWEP.PrintName = "EBR"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/ebr.mdl"

SWEP.Primary = { ClipSize = 10, DefaultClip = 10, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.2500
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 2.50
SWEP.GTG.semi = "dmr"
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "ebr", swep = "mg_mike14", tiers = { "infantry", "sof" } }

SWEP.GTG.mw = { fire = "mw19.mike14.fire", tailOut = "Atmo_br1.Outside", tailIn = "Atmo_Shotgun.Inside", reload = { { 0.0165, "ps_wfoly_plr_sn_mike14_reload_xmag_01" }, { 0.1, "ps_wfoly_plr_sn_mike14_reload_xmag_02" }, { 0.35, "ps_wfoly_plr_sn_mike14_reload_xmag_03" }, { 0.55, "ps_wfoly_plr_sn_mike14_reload_xmag_04" }, { 0.65, "ps_wfoly_plr_sn_mike14_reload_xmag_045" }, { 0.6665, "ps_wfoly_plr_sn_mike14_reload_xmag_05" }, { 0.8165, "ps_wfoly_plr_sn_mike14_reload_xmag_06" } }, reloadEmpty = { { 0, "ps_wfoly_plr_sn_mike14_reload_empty_xmag_01" }, { 0.192308, "ps_wfoly_plr_sn_mike14_reload_empty_xmag_02" }, { 0.410385, "ps_wfoly_plr_sn_mike14_reload_empty_xmag_03" }, { 0.512692, "ps_wfoly_plr_sn_mike14_reload_empty_xmag_035" }, { 0.615385, "ps_wfoly_plr_sn_mike14_reload_empty_xmag_04" }, { 0.769231, "ps_wfoly_plr_sn_mike14_reload_empty_xmag_05" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 1.3652, -1.9218, -11.4457 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.57805, 0.74642, 0.32972, -0.23175, -0.23725, 0.9434, 0.7824, -0.62175, 0.03584 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.85883, -0.36903, -0.35528, 0.4498, 0.87516, 0.17828, 0.24513, -0.31292, 0.9176 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.99874, 0.01106, 0.04894, -0.01072, 0.99992, -0.00729, -0.04902, 0.00676, 0.99877 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.82863, 0.25761, 0.49701, -0.36376, 0.92262, 0.12826, -0.42551, -0.28707, 0.85822 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.60139, 0.79618, -0.06656, -0.79562, 0.6044, 0.041, 0.07288, 0.0283, 0.99694 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.7673, 0.64037, -0.03434, -0.64056, 0.76788, 0.00681, 0.03073, 0.01677, 0.99939 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.50289, 0.67408, 0.54103, -0.85461, 0.48146, 0.19451, -0.12936, -0.56019, 0.8182 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.27413, 0.96127, -0.02846, -0.96099, 0.27494, 0.03, 0.03667, 0.01913, 0.99914 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.98216, -0.18746, 0.01479, 0.18743, 0.98227, 0.00324, -0.01513, -0.00041, 0.99989 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.18725, 0.81983, 0.54112, -0.95252, 0.0169, 0.304, 0.24009, -0.57235, 0.78407 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.66639, 0.7452, 0.02459, -0.74514, 0.66678, -0.01342, -0.0264, -0.00938, 0.99961 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.99076, -0.13524, -0.01021, 0.13521, 0.99081, -0.00387, 0.01064, 0.00245, 0.99994 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.01141, 0.57827, 0.81577, -0.88446, -0.38642, 0.26155, 0.46648, -0.71853, 0.51586 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.86756, 0.47779, 0.13805, -0.4701, 0.87842, -0.08595, -0.16233, 0.00967, 0.98669 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.95052, -0.27762, -0.1394, 0.2751, 0.96069, -0.03743, 0.14431, -0.00277, 0.98953 } }, fingerPose = "sn_mike14_l" }
TIFG.RegisterWeaponDef(SWEP)
