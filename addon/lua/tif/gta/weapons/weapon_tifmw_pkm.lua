local base = TIFG.WeaponBases and TIFG.WeaponBases["lmg"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_pkm"
SWEP.PrintName = "PKM"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/pkm.mdl"

SWEP.Primary = { ClipSize = 100, DefaultClip = 100, Automatic = true, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.0923
SWEP.GTG.auto = true
SWEP.GTG.reload_time = 4.20
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "pkm", swep = "mg_pkilo", tiers = { "rebel", "ru_infantry" } }

SWEP.GTG.mw = { fire = "weap_pkilo_fire_plr", tailOut = "Atmo_LMG.Outside", tailIn = "Atmo_LMG.Inside" }

SWEP.TIFBaked.hold = { jgun = { t = { -1.4952, -2.2107, -11.251 } }, fingers = { ["ValveBiped.Bip01_L_Finger0"] = { 0.69396, 0.65822, 0.29184, -0.20619, -0.20668, 0.95644, 0.68986, -0.7239, -0.00771 }, ["ValveBiped.Bip01_L_Finger01"] = { 0.86295, -0.36022, -0.35433, 0.44063, 0.87971, 0.17879, 0.2473, -0.31041, 0.91787 }, ["ValveBiped.Bip01_L_Finger02"] = { 0.99874, 0.01118, 0.04895, -0.01084, 0.99991, -0.0073, -0.04903, 0.00676, 0.99877 }, ["ValveBiped.Bip01_L_Finger1"] = { 0.79309, 0.36582, 0.48702, -0.48154, 0.86619, 0.13353, -0.37301, -0.34042, 0.86312 }, ["ValveBiped.Bip01_L_Finger11"] = { 0.82571, 0.56212, -0.04717, -0.56174, 0.82702, 0.02228, 0.05153, 0.0081, 0.99864 }, ["ValveBiped.Bip01_L_Finger12"] = { 0.95805, 0.2866, -0.00138, -0.2866, 0.95805, -0.00064, 0.00114, 0.00101, 1 }, ["ValveBiped.Bip01_L_Finger2"] = { 0.56813, 0.54405, 0.61744, -0.79608, 0.55344, 0.24486, -0.2085, -0.63065, 0.74754 }, ["ValveBiped.Bip01_L_Finger21"] = { 0.50764, 0.86119, -0.02534, -0.86094, 0.50817, 0.02308, 0.03276, 0.0101, 0.99941 }, ["ValveBiped.Bip01_L_Finger22"] = { 0.8757, 0.48281, -0.00579, -0.48282, 0.87572, -0.00041, 0.00487, 0.00315, 0.99998 }, ["ValveBiped.Bip01_L_Finger3"] = { 0.38327, 0.53917, 0.74994, -0.92244, 0.18214, 0.34048, 0.04698, -0.82227, 0.56716 }, ["ValveBiped.Bip01_L_Finger31"] = { 0.46285, 0.88596, 0.02917, -0.88589, 0.46347, -0.02005, -0.03128, -0.01656, 0.99937 }, ["ValveBiped.Bip01_L_Finger32"] = { 0.99076, -0.13524, -0.01021, 0.13521, 0.99081, -0.00381, 0.01063, 0.00239, 0.99994 }, ["ValveBiped.Bip01_L_Finger4"] = { 0.2326, 0.44511, 0.86474, -0.94083, -0.12232, 0.31603, 0.24644, -0.88708, 0.39032 }, ["ValveBiped.Bip01_L_Finger41"] = { 0.78051, 0.60058, 0.1735, -0.59091, 0.79937, -0.10877, -0.20402, -0.01763, 0.97881 }, ["ValveBiped.Bip01_L_Finger42"] = { 0.95052, -0.27762, -0.1394, 0.2751, 0.96069, -0.03743, 0.14431, -0.00277, 0.98953 } }, fingerPose = "lm_pkilo_l" }
TIFG.RegisterWeaponDef(SWEP)
