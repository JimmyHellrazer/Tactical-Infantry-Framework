-- TIF weapon bases (TIF 0.38.0): the stats and fire behaviour the baked MW guns start from (weapon_tifmw_*:
-- table.Copy of a base, then their own model, name, sounds and hold). Flattened from the GTA definitions TIF
-- used to ship (tools: scratchpad make_bases.py), without their GTA-body animation names and models.
-- Keys: rifle, smg, lmg, shotgun, marksman, pistol, launcher. GTG.hold picks the MW weapon kind
-- (TIF.GTG.WeaponKind); damage / rate / range / falloff / spread / recoil are TIF sv_weapon's.
TIFG.WeaponBases = TIFG.WeaponBases or {}
local B = TIFG.WeaponBases

-- (was weapon_gtg_assaultrifle)
B["rifle"] = {
	GTG = {
		auto = true,
		damage = 22,
		empty = "Weapon_AR2.Empty",
		falloff = {
			1870.08,
			4724.41,
			0.3,
		},
		fire_rounds = 8,
		force = 75,
		head = 1.7,
		hold = "assault",
		limb = 0.5,
		range = 7874.02,
		rate = 0.1,
		recoil = {
			amount = 2.2,
			gap = 0.1,
			shake = "ASSAULT_RIFLE_RECOIL_SHAKE",
		},
		reload_sound = "Weapon_AR2.Reload",
		reload_time = 2.033,
		sound = "Weapon_AR2.Single",
		spread = 1.5,
		tracer = 1,
	},
	HoldType = "ar2",
	Primary = {
		Ammo = "gtg_rifle",
		Automatic = true,
		ClipSize = 30,
		DefaultClip = 30,
	},
	Slot = 2,
}

-- (was weapon_gtg_smg)
B["smg"] = {
	GTG = {
		auto = true,
		damage = 15,
		empty = "Weapon_SMG1.Empty",
		falloff = {
			1574.8,
			4724.41,
			0.3,
		},
		fire_rounds = 8,
		force = 75,
		head = 2.5,
		hold = "smg",
		limb = 0.5,
		range = 7874.02,
		rate = 0.083,
		recoil = {
			amount = 2.06,
			gap = 0,
			shake = "SMG_RECOIL_SHAKE",
		},
		reload_sound = "Weapon_SMG1.Reload",
		reload_time = 2.533,
		sound = "Weapon_SMG1.Single",
		spread = 1.47,
		tracer = 0.75,
	},
	HoldType = "smg",
	Primary = {
		Ammo = "gtg_smg",
		Automatic = true,
		ClipSize = 30,
		DefaultClip = 30,
	},
	Slot = 2,
}

-- (was weapon_gtg_mg)
B["lmg"] = {
	GTG = {
		auto = true,
		damage = 27,
		empty = "Weapon_AR2.Empty",
		falloff = {
			1870.08,
			4724.41,
			0.3,
		},
		fire_rounds = 10,
		force = 75,
		head = 1.7,
		hold = "mg",
		limb = 0.5,
		range = 7874.02,
		rate = 0.096,
		recoil = {
			amount = 6.2,
			gap = 0,
			shake = "MG_RECOIL_SHAKE",
		},
		reload_sound = "Weapon_AR2.Reload",
		reload_time = 3.467,
		sound = "Weapon_AR2.Single",
		spread = 2.31,
		tracer = 0.75,
	},
	HoldType = "ar2",
	Primary = {
		Ammo = "gtg_mg",
		Automatic = true,
		ClipSize = 54,
		DefaultClip = 54,
	},
	Slot = 2,
}

-- (was weapon_gtg_pumpshotgun)
B["shotgun"] = {
	GTG = {
		batch_spread = 0.04,
		damage = 24,
		empty = "Weapon_Shotgun.Empty",
		falloff = {
			393.701,
			1574.8,
			0.3,
		},
		force = 14,
		head = 1,
		hold = "pump",
		limb = 1,
		pellets = 8,
		range = 1968.51,
		rate = 0.8,
		recoil = {
			amount = 2,
			gap = 0.15,
			shake = "SHOTGUN_RECOIL_SHAKE",
		},
		reload_sound = "Weapon_Shotgun.Reload",
		reload_time = 2.167,
		sound = "Weapon_Shotgun.Single",
		spread = 1.75,
		tracer = 1,
	},
	HoldType = "shotgun",
	Primary = {
		Ammo = "gtg_shotgun",
		Automatic = false,
		ClipSize = 8,
		DefaultClip = 8,
	},
	Slot = 3,
}

-- (was weapon_gtg_marksmanrifle)
B["marksman"] = {
	GTG = {
		auto = true,
		damage = 44,
		empty = "Weapon_Pistol.Empty",
		falloff = {
			9842.52,
			39370.1,
			0.3,
		},
		fire_rounds = 8,
		force = 100,
		head = 1,
		hold = "assault",
		limb = 0.5,
		range = 39370.1,
		rate = 0.21,
		recoil = {
			amount = 1.74,
			gap = 0.15,
			shake = "DEFAULT_FIRST_PERSON_RECOIL_SHAKE",
		},
		reload_sound = "Weapon_357.Reload",
		reload_time = 2.033,
		scope = {
			fov = 20,
			fov_min = 20,
			reticle = "large",
		},
		sound = "NPC_Sniper.FireBullet",
		spread = 0,
		tracer = 0.75,
	},
	HoldType = "ar2",
	Primary = {
		Ammo = "gtg_sniper",
		Automatic = true,
		ClipSize = 8,
		DefaultClip = 8,
	},
	Slot = 3,
}

-- (was weapon_gtg_pistol)
B["pistol"] = {
	GTG = {
		damage = 26,
		empty = "Weapon_Pistol.Empty",
		falloff = {
			1574.8,
			4724.41,
			0.3,
		},
		force = 50,
		head = 2,
		hold = "pistol",
		limb = 0.5,
		range = 7874.02,
		rate = 0.37,
		recoil = {
			amount = 6.2,
			gap = 0.15,
			shake = "PISTOL_RECOIL_SHAKE",
		},
		reload_empty = "wpis_reload_aim_empty",
		reload_sound = "Weapon_Pistol.Reload",
		reload_time = 1.833,
		sound = "Weapon_Pistol.Single",
		spread = 0.63,
		tracer = 0.75,
		w_reload_empty = "w_reload_aim_empty",
	},
	HoldType = "pistol",
	Primary = {
		Ammo = "gtg_pistol",
		Automatic = false,
		ClipSize = 12,
		DefaultClip = 12,
	},
}

-- (was weapon_gtg_rpg)
B["launcher"] = {
	GTG = {
		damage = 0,
		empty = "Weapon_Pistol.Empty",
		force = 0,
		head = 1,
		hold = "rpg",
		limb = 0.5,
		ordnance = true,
		projectile = {
			burst = true,
			damping = 0,
			entity = "tif_rocket",
			explode = "ROCKET",
			gravity = 0.02,
			life = 5,
			look = "rocket",
			model = "models/weapons/w_missile_closed.mdl",
			rocket = {
				accel = 8000,
				max = 4000,
				start = 500,
			},
			trail = true,
		},
		range = 3346.46,
		rate = 0.8,
		recoil = {
			amount = 1,
			gap = 0.15,
			shake = "RPG_RECOIL_SHAKE",
		},
		reload_sound = "Weapon_AR2.Reload",
		reload_time = 2.733,
		sound = "Weapon_RPG.Single",
		spread = 1,
		tracer = 0,
	},
	HoldType = "physgun",
	Primary = {
		Ammo = "gtg_rpg",
		Automatic = false,
		ClipSize = 1,
		DefaultClip = 1,
	},
	Slot = 4,
}
