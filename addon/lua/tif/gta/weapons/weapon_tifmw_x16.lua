local base = TIFG.WeaponBases and TIFG.WeaponBases["pistol"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_x16"
SWEP.PrintName = "X16"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/x16.mdl"

SWEP.Primary = { ClipSize = 15, DefaultClip = 15, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.1500
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 1.60
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "x16", swep = "mg_glock", tiers = { "infantry", "police" } }

SWEP.GTG.mw = { fire = "weap_golf21_fire_plr", tailOut = "Atmo_Pistol.Outside", tailIn = "Atmo_Pistol.Inside", reload = { { 0.172414, "MW19_GLOCK.Magout" }, { 0.551724, "MW19_GLOCK.Maginsert" }, { 0.655172, "MW19_GLOCK.Magin" }, { 0.689655, "MW19_GLOCK.Reload_End" } }, reloadEmpty = { { 0, "MW19_GLOCK.Reload_Start_Empty" }, { 0.133333, "MW19_GLOCK.Magout_Empty" }, { 0.466667, "MW19_GLOCK.Maginsert_Empty" }, { 0.6, "MW19_GLOCK.Magin_Empty" }, { 0.8, "MW19_GLOCK.Charge" }, { 0.866667, "MW19_GLOCK.Reload_End_Empty" } } }
TIFG.RegisterWeaponDef(SWEP)
