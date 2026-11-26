local base = TIFG.WeaponBases and TIFG.WeaponBases["pistol"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_m1911_jav"
SWEP.PrintName = "M1911 JAV"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/m1911_jav.mdl"

SWEP.Primary = { ClipSize = 8, DefaultClip = 8, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.1667
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 1.50
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "m1911_jav", swep = "mg_m1911", tiers = { "sof" } }

SWEP.GTG.mw = { fire = "weap_mike1911_fire_plr", tailOut = "Atmo_Pistol.Outside", tailIn = "Atmo_Pistol.Inside", reload = { { 0.037037, "MW19_M1911.Reload_Start" }, { 0.37037, "MW19_M1911.Magout" }, { 0.592593, "MW19_M1911.Maginsert" }, { 0.740741, "MW19_M1911.Reload_End" }, { 0.762963, "MW19_M1911.Magin" } }, reloadEmpty = { { 0, "MW19_M1911.Reload_Start_Empty" }, { 0.2, "MW19_M1911.Magout_Empty" }, { 0.466667, "MW19_M1911.Maginsert_Empty" }, { 0.6, "MW19_M1911.Magin_Empty" }, { 0.8, "MW19_M1911.Charge" }, { 0.866667, "MW19_M1911.Reload_End_Empty" } } }
TIFG.RegisterWeaponDef(SWEP)
