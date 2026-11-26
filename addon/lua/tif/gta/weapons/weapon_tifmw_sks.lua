local base = TIFG.WeaponBases and TIFG.WeaponBases["marksman"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_sks"
SWEP.PrintName = "SKS"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/sks.mdl"

SWEP.Primary = { ClipSize = 10, DefaultClip = 10, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.2500
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 2.50
SWEP.GTG.semi = "dmr"
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "sks", swep = "mg_sksierra", tiers = { "rebel" } }

SWEP.GTG.mw = { fire = "mw19.sksierra.fire", tailOut = "Atmo_br1.Outside", tailIn = "Atmo_Shotgun.Inside", reload = { { 0, "ps_wfoly_plr_sn_sksierra_reload_01" }, { 0.213158, "ps_wfoly_plr_sn_sksierra_reload_02" }, { 0.488722, "ps_wfoly_plr_sn_sksierra_reload_03" }, { 0.576316, "ps_wfoly_plr_sn_sksierra_reload_035" }, { 0.61391, "ps_wfoly_plr_sn_sksierra_reload_04" } }, reloadEmpty = { { 0, "ps_wfoly_plr_sn_sksierra_reload_empty_01" }, { 0.238908, "ps_wfoly_plr_sn_sksierra_reload_empty_02" }, { 0.398294, "ps_wfoly_plr_sn_sksierra_reload_empty_03" }, { 0.477816, "ps_wfoly_plr_sn_sksierra_reload_empty_035" }, { 0.580205, "ps_wfoly_plr_sn_sksierra_reload_empty_04" }, { 0.762116, "ps_wfoly_plr_sn_sksierra_reload_empty_05" }, { 0.898635, "ps_wfoly_plr_sn_sksierra_reload_empty_06" } } }

SWEP.TIFBaked.hold = { jgun = { t = { -0.183, -2.6156, -10.6325 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.59745, 0.72872, 0.3347, -0.24656, -0.23023, 0.94138, 0.76306, -0.64495, 0.04213 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.86299, -0.36018, -0.35429, 0.44056, 0.87975, 0.17874, 0.24731, -0.31033, 0.9179 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.99874, 0.01112, 0.04895, -0.01078, 0.99992, -0.0073, -0.04903, 0.00676, 0.99877 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.81261, 0.3124, 0.49201, -0.42368, 0.89634, 0.13064, -0.4002, -0.31461, 0.86073 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.39145, 0.91701, -0.07654, -0.91637, 0.39605, 0.05843, 0.0839, 0.04727, 0.99535 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.7673, 0.64038, -0.03431, -0.64056, 0.76788, 0.00687, 0.03074, 0.01671, 0.99939 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.50282, 0.60729, 0.61512, -0.85466, 0.45577, 0.24866, -0.12935, -0.65075, 0.7482 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.04709, 0.99845, -0.0297, -0.99816, 0.04817, 0.03676, 0.03814, 0.02791, 0.99888 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.98216, -0.18746, 0.01479, 0.18743, 0.98227, 0.00324, -0.01513, -0.00041, 0.99989 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.18721, 0.75202, 0.63199, -0.95254, -0.01824, 0.30387, 0.24005, -0.65889, 0.71291 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.46272, 0.88603, 0.02909, -0.88595, 0.46334, -0.02007, -0.03126, -0.01648, 0.99938 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.99076, -0.13524, -0.01021, 0.13521, 0.99081, -0.00387, 0.01064, 0.00245, 0.99994 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.07473, 0.47691, 0.87577, -0.85373, -0.48444, 0.19096, 0.51532, -0.7334, 0.44336 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.78048, 0.60062, 0.17353, -0.59096, 0.79934, -0.10872, -0.20401, -0.0177, 0.97881 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.95052, -0.27762, -0.1394, 0.2751, 0.96069, -0.03743, 0.14431, -0.00277, 0.98953 } }, fingerPose = "sn_sksierra_l" }
TIFG.RegisterWeaponDef(SWEP)
