-- Tactical Infantry Framework loader.
-- Files are loaded by prefix: sv_ = server only, cl_ = client only, sh_ = both.

TIF = TIF or {}
TIF.Version = "0.38.50"
TIF.Root = "tif/"
-- The local dev addon (tif_devtools: debug overlays, test / diagnostic commands; not shipped) is loaded after
-- everything else when it's installed. TIF.Dev tells code that registers a dev-only command in place.
TIF.Dev = file.Exists("tif_dev/sh_init.lua", "LUA")

local MANIFEST = {
	"sh_core.lua",
	-- (0.38.30) TIF's log file (data/tif/log_sv.txt / log_cl.txt): console lines, events, watchdog finds.
	"core/sh_log.lua",

	-- TIF's animation / weapon content registry (global TIFG): the MW19 body's clips and character, the MW guns, the
	-- retarget library. (The folder name is from the GTA-content days; gta/sh_init.lua has the history.)
	"gta/sh_init.lua",

	-- Third-party adapters. Nothing outside compat/ may touch GTG, Glide, DV or prone globals.
	"compat/sh_gtg.lua",
	"compat/sh_glide.lua",
	"compat/sh_dv.lua",
	"compat/sh_prone.lua",
	"compat/sv_flashbangs.lua",
	-- NPCs bumping closed doors open them instead of damaging them (destructible-door mods)
	"compat/sv_doors.lua",

	"config/sh_content.lua",
	-- MW Base gun sounds TIF's guns use, packed in (sound/viper/..., 0.38.10); MW Base's own win where installed.
	"config/sh_mwsounds.lua",
	"config/sh_factions_custom.lua",
	"config/sh_archetypes.lua",

	"core/sh_prof.lua",
	"core/sh_factions.lua",
	-- HL2 / addon NPCs and TIF soldiers see each other and fight (or help): sides from core/sh_factions.lua.
	"compat/sv_hl2npc.lua",
	"sh_voices.lua",
	-- Modular factions: soldiers built from body / head / headgear parts (TIFDIDDY/MODULAR.md). Before the packs:
	-- packs queued before TIF loaded run at the end of sh_packs.lua and need it.
	"config/sh_modular.lua",
	-- Factions and voices from other addons (content packs), and camo variants.
	"config/sh_packs.lua",
	-- Spawn menu entries for every faction and role.
	"config/sh_spawnlist.lua",
	"core/sv_sched.lua",
	"core/sv_events.lua",
	"core/sv_precache.lua",
	-- Spawning soldiers (spawn menu, API, game modes, tif_spawn): room checks, spread points, squad mixes.
	"core/sv_spawn.lua",

	-- Soldier
	"npc/sh_anim.lua",
	"npc/sv_perception.lua",
	"npc/sv_weapon.lua",
	"npc/sv_move.lua",
	"npc/sv_crowd.lua",
	"npc/sv_action.lua",

	-- Tactics (Phase 2)
	"tactics/sv_cover.lua",
	"tactics/sv_cover_behave.lua",
	"tactics/sv_cover_mw.lua",
	"tactics/sv_smart_mw.lua",
	"tactics/sv_trans_mw.lua",
	"tactics/sv_search_mw.lua",
	"tactics/sv_bipod_mw.lua",
	"tactics/sv_passive_mw.lua",
	"tactics/sv_hits_mw.lua",
	-- Close-range melee: butt hits and paired fights (MW19 body).
	"tactics/sv_melee_mw.lua",
	"tactics/sv_shield_data.lua",
	"tactics/sv_shield.lua",
	"tactics/sv_react_mw22.lua",
	"tactics/sv_suppression.lua",
	"tactics/sv_prone.lua",
	"tactics/sv_search.lua",
	"tactics/sv_morale.lua",
	"tactics/sv_casualty.lua",
	"tactics/sv_laststand_mw.lua",
	"tactics/sv_traverse_mw.lua",
	"tactics/sv_door_mw.lua",
	"tactics/sv_flashlight.lua",
	"tactics/sv_civilian.lua",

	-- Squads (Phase 3)
	"squad/sv_squad.lua",
	"squad/sv_squad_tactics.lua",
	"squad/sv_radio.lua",

	"npc/sv_brain.lua",
	"npc/cl_body.lua",
	"npc/cl_gunmag.lua",
	"npc/cl_props_data.lua",
	"npc/cl_props.lua",
	-- MW19 movement sounds: footsteps, gear, landings, body falls (sound/tif/foley, foley_pack.py)
	"npc/sh_foley_data.lua",
	"npc/sh_foley.lua",
	"npc/cl_foley.lua",
	"npc/cl_gunhold.lua",
	"npc/cl_flashlight.lua",
	"npc/sv_rescue.lua",

	-- Bases and encounters (Phase 4)
	"encounter/sv_base.lua",

	-- Buildings and room clearing (Phase 5)
	"building/sv_building.lua",
	"building/sv_clear.lua",

	-- Vehicles (Phase 6)
	"vehicle/sv_vehicle.lua",
	"vehicle/sv_routes.lua",
	"vehicle/sv_driver.lua",
	"vehicle/sv_mounted.lua",
	"vehicle/sv_convoy.lua",
	"vehicle/sv_dvroads.lua",

	-- Interface for other addons (the DTW campaign)
	"api/sv_api.lua",

	-- Reinforcement helicopters (models: tif_air addon; TIFDIDDY/HELI_PLAN.md)
	"air/sh_air.lua",
	"air/sv_air.lua",
	"air/sv_air_ride.lua",
	"air/cl_air.lua",

	-- Player and admin commands: squad orders (tif_menu), spawning / clearing, bases (build, save, garrison).
	"squad/sv_orders.lua",
	"encounter/sv_base_commands.lua",
	-- Menus: the squad order menu (tif_menu) and the settings panel (spawn menu > Utilities, tif_settings).
	"ui/cl_menu.lua",
	"ui/cl_settings.lua",

	"sv_selftest.lua",
	-- (0.38.30) silent stuck states into the log file, and tif_mark
	"core/sv_watchdog.lua",
	-- (The Phase 0 engine spikes, built around the GTA body, were removed with it in 0.38.0. The debug overlays and
	-- test / diagnostic commands moved to the local dev addon tif_devtools in 0.38.11: loaded below when installed.)
}

local function load_file(path)
	local prefix = string.sub(string.match(path, "[^/]+$"), 1, 3)
	if prefix == "sv_" then
		if SERVER then include(path) end
	elseif prefix == "cl_" then
		if SERVER then AddCSLuaFile(path) else include(path) end
	else
		if SERVER then AddCSLuaFile(path) end
		include(path)
	end
end

for _, rel in ipairs(MANIFEST) do load_file(TIF.Root .. rel) end

-- The dev addon (not shipped): its own loader, after TIF so everything it hooks into exists.
if TIF.Dev then
	if SERVER then AddCSLuaFile("tif_dev/sh_init.lua") end
	include("tif_dev/sh_init.lua")
end

MsgN("[TIF] v", TIF.Version, " loaded (", SERVER and "server" or "client", ")")
