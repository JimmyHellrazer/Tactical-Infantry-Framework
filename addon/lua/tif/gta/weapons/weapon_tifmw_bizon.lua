local base = TIFG.WeaponBases and TIFG.WeaponBases["smg"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_bizon"
SWEP.PrintName = "BIZON"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/bizon.mdl"

SWEP.Primary = { ClipSize = 64, DefaultClip = 64, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.0882
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 2.60
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "bizon", swep = "mg_beta", tiers = { "ru_sof", "ru_infantry" } }

SWEP.GTG.mw = { fire = "weap_beta_fire_plr_lfe", tailOut = "Atmo_SMG.Outside", tailIn = "Atmo_SMG.Inside", reload = { { 0.029646, "ps_wfoly_plr_sm_beta_reload_01" }, { 0.0738938, "ps_wfoly_plr_sm_beta_reload_02" }, { 0.191593, "ps_wfoly_plr_sm_beta_reload_03" }, { 0.530973, "ps_wfoly_plr_sm_beta_reload_04" }, { 0.722566, "ps_wfoly_plr_sm_beta_reload_045" }, { 0.737611, "ps_wfoly_plr_sm_beta_reload_05" } }, reloadEmpty = { { 0.0115385, "ps_wfoly_plr_sm_beta_reload_empty_01" }, { 0.0933566, "ps_wfoly_plr_sm_beta_reload_empty_02" }, { 0.303147, "ps_wfoly_plr_sm_beta_reload_empty_03" }, { 0.41958, "ps_wfoly_plr_sm_beta_reload_empty_04" }, { 0.570979, "ps_wfoly_plr_sm_beta_reload_empty_045" }, { 0.699301, "ps_wfoly_plr_sm_beta_reload_empty_05" }, { 0.710839, "ps_wfoly_plr_sm_beta_reload_empty_06" } } }

SWEP.TIFBaked.hold = { jgun = { t = { 1.2116, -2.512, -10.009 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.53602, 0.84229, 0.05682, -0.47859, 0.24774, 0.84236, 0.69544, -0.47871, 0.53591 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.84617, -0.47093, -0.24945, 0.52527, 0.81602, 0.24125, 0.08995, -0.33516, 0.93786 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.99072, -0.13371, 0.02431, 0.13322, 0.99087, 0.02066, -0.02685, -0.01723, 0.99949 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.71816, 0.45553, 0.52606, -0.44832, 0.88105, -0.15088, -0.53221, -0.12749, 0.83696 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.85621, 0.51482, -0.04322, -0.51447, 0.85728, 0.01979, 0.04724, 0.00529, 0.99887 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.92805, 0.37219, -0.01387, -0.37226, 0.92812, -0.0027, 0.01186, 0.00767, 0.9999 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.49488, 0.56302, 0.6619, -0.75886, 0.65111, 0.01353, -0.42335, -0.50898, 0.74947 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.467, 0.88387, -0.02608, -0.88362, 0.46758, 0.02423, 0.03361, 0.01172, 0.99937 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.99952, 0.02985, 0.00864, -0.02986, 0.99955, 0.00055, -0.00862, -0.00081, 0.99996 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.27611, 0.64871, 0.70918, -0.94985, 0.29685, 0.09828, -0.14677, -0.70075, 0.69814 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.69648, 0.71718, 0.02377, -0.71712, 0.69684, -0.0124, -0.02546, -0.00841, 0.99964 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.95809, 0.28645, 0.0025, -0.28644, 0.95809, -0.00236, -0.00308, 0.00155, 0.99999 }, ["ValveBiped.Bip01_L_Finger4"] = { 0.06256, 0.42598, 0.90257, -0.98979, -0.08959, 0.11089, 0.1281, -0.90029, 0.41602 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.93394, 0.34339, 0.09922, -0.33785, 0.9387, -0.0686, -0.1167, 0.03055, 0.9927 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.99547, 0.086, -0.04048, -0.08624, 0.99627, -0.00402, 0.03998, 0.0075, 0.99917 } }, fingerPose = "sm_beta_l" }
TIFG.RegisterWeaponDef(SWEP)
