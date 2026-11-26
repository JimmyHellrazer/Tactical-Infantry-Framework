local base = TIFG.WeaponBases and TIFG.WeaponBases["pistol"]
if not base then return end
local SWEP = table.Copy(base)
SWEP.ClassName = "weapon_tifmw_m19"
SWEP.PrintName = "M19"
SWEP.Category = "TIF MW guns"
SWEP.WorldModel = "models/tif_guns/m19.mdl"

SWEP.Primary = { ClipSize = 17, DefaultClip = 17, Automatic = false, Ammo = SWEP.Primary and SWEP.Primary.Ammo }
SWEP.GTG.rate = 0.1500
SWEP.GTG.auto = false
SWEP.GTG.reload_time = 1.60
SWEP.GTG.mag = nil
SWEP.TIFBaked = { id = "m19", swep = "mg_p320", tiers = { "infantry", "sof" } }

SWEP.GTG.mw = { fire = "weap_papa320_fire_plr", tailOut = "Atmo_Pistol.Outside", tailIn = "Atmo_Pistol.Inside", reload = { { 0, "MW19_P320.Reload_Start" }, { 0.22, "MW19_P320.Magout" }, { 0.6, "MW19_P320.Maginsert" }, { 0.686667, "MW19_P320.Magin" }, { 0.8, "MW19_P320.Reload_End" } }, reloadEmpty = { { 0, "MW19_P320.Reload_Start_Empty" }, { 0.18, "MW19_P320.Magout_Empty" }, { 0.55, "MW19_P320.Maginsert_Empty" }, { 0.665, "MW19_P320.Magin_Empty" }, { 0.815, "MW19_P320.Charge" }, { 0.815, "MW19_P320.Reload_End_Empty" } } }
TIFG.RegisterWeaponDef(SWEP)
