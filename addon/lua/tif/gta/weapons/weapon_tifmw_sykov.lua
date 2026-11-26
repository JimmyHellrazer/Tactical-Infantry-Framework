local base = TIFG.WeaponBases and TIFG.WeaponBases["pistol"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_sykov"
SWEP.PrintName = "SYKOV"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/sykov.mdl"

SWEP.Primary = { ClipSize = 12, DefaultClip = 12, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.1500
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 1.60
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "sykov", swep = "mg_makarov", tiers = { "rebel", "ru_infantry", "ru_sof" } }

SWEP.GTG.mw = { fire = "weap_mike_fire_plr", tailOut = "Atmo_Pistol.Outside", tailIn = "Atmo_Pistol.Inside", reload = { { 0, "MW19_Makarov.Reload_Start" }, { 0.180723, "MW19_Makarov.Magout" }, { 0.60241, "MW19_Makarov.Magin" }, { 0.819277, "MW19_Makarov.Reload_End" } }, reloadEmpty = { { 0, "MW19_Makarov.Reload_Start_Empty" }, { 0.132743, "MW19_Makarov.Magout_Empty" }, { 0.411504, "MW19_Makarov.Maginsert_Empty" }, { 0.442478, "MW19_Makarov.Magin_Empty" }, { 0.690265, "MW19_Makarov.Charge" }, { 0.823009, "MW19_Makarov.Reload_End_Empty" } } }
TIFG.RegisterWeaponDef(SWEP)
