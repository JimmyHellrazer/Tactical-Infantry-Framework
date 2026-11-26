local base = TIFG.WeaponBases and TIFG.WeaponBases["lmg"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_bruen_sof"
SWEP.PrintName = "BRUEN SOF"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/bruen_sof.mdl"

SWEP.Primary = { ClipSize = 100, DefaultClip = 100, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.0800
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 4.20
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "bruen_sof", swep = "mg_mkilo3", tiers = { "sof" } }

SWEP.GTG.mw = { fire = "weap_mkilo3_fire_plr", tailOut = "Atmo_AR5.Outside", tailIn = "Atmo_LMG.Inside" }

SWEP.TIFBaked.hold = { jgun = { t = { -0.9623, -2.7223, -10.3406 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.68854, 0.68187, 0.2469, -0.1366, -0.21241, 0.96759, 0.71222, -0.69995, -0.05311 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.83701, -0.41231, -0.35974, 0.49478, 0.85105, 0.17581, 0.23366, -0.32515, 0.91634 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.99874, 0.01112, 0.04895, -0.01078, 0.99992, -0.0073, -0.04903, 0.00676, 0.99877 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.79737, 0.355, 0.48802, -0.46982, 0.87271, 0.13279, -0.37876, -0.33517, 0.86267 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.219, 0.97235, -0.08108, -0.97166, 0.22491, 0.07273, 0.08895, 0.06285, 0.99405 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.82664, 0.5621, -0.02669, -0.56221, 0.82699, 0.00385, 0.02424, 0.01182, 0.99964 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.41515, 0.83847, 0.35301, -0.90934, 0.39419, 0.13311, -0.02754, -0.37627, 0.9261 }, ["ValveBiped.Bip01_L_Finger21"] = { -0.03072, 0.99252, 0.11812, -0.9988, -0.035, 0.03432, 0.0382, -0.11692, 0.99241 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.89573, -0.44408, 0.02138, 0.44401, 0.89598, 0.00833, -0.02286, 0.00203, 0.99974 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.04738, 0.89137, 0.45079, -0.96392, -0.07755, 0.25464, 0.26194, -0.44659, 0.85554 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.40237, 0.90075, 0.16354, -0.91502, 0.40133, 0.04086, -0.02883, -0.16608, 0.98569 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.85608, -0.51642, -0.02068, 0.51633, 0.85633, -0.01009, 0.02292, -0.00204, 0.99974 }, ["ValveBiped.Bip01_L_Finger4"] = { -0.33454, 0.54331, 0.77, -0.78392, -0.61391, 0.09258, 0.52301, -0.57265, 0.63129 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.8075, 0.53631, 0.24559, -0.55759, 0.82984, 0.02121, -0.19243, -0.15406, 0.96914 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.86694, -0.46248, -0.18582, 0.45779, 0.8863, -0.07006, 0.19709, -0.02433, 0.98008 } }, fingerPose = "lm_mkilo3_l" }
TIFG.RegisterWeaponDef(SWEP)
