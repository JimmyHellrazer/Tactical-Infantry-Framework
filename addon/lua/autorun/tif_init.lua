TIF = TIF or {}
TIF.Version = "0.38.86"
TIF.Root = "tif/"

TIF.Dev = file.Exists("tif_dev/sh_init.lua", "LUA")

local MANIFEST = {
	"sh_core.lua",

	"core/sh_log.lua",

	"gta/sh_init.lua",

	"compat/sh_gtg.lua",
	"compat/sh_glide.lua",
	"compat/sh_dv.lua",
	"compat/sh_prone.lua",
	"compat/sv_flashbangs.lua",

	"compat/sv_doors.lua",

	"config/sh_content.lua",

	"config/sh_mwsounds.lua",
	"config/sh_factions_custom.lua",
	"config/sh_archetypes.lua",

	"core/sh_prof.lua",
	"core/sh_factions.lua",

	"compat/sv_hl2npc.lua",
	"sh_voices.lua",

	"config/sh_modular.lua",

	"config/sh_packs.lua",

	"config/sh_spawnlist.lua",
	"core/sv_sched.lua",
	"core/sv_events.lua",
	"core/sv_precache.lua",

	"core/sv_spawn.lua",
	"core/sv_save.lua",

	"npc/sh_anim.lua",
	"npc/sv_perception.lua",
	"npc/sv_weapon.lua",
	"npc/sv_move.lua",
	"npc/sv_crowd.lua",
	"npc/sv_action.lua",

	"tactics/sv_cover.lua",
	"tactics/sv_cover_behave.lua",
	"tactics/sv_cover_mw.lua",
	"tactics/sv_smart_mw.lua",
	"tactics/sv_trans_mw.lua",
	"tactics/sv_search_mw.lua",
	"tactics/sv_bipod_mw.lua",
	"tactics/sv_passive_mw.lua",
	"tactics/sv_hits_mw.lua",
	"tactics/sv_fall_mw.lua",

	"tactics/sv_melee_mw.lua",
	"tactics/sv_shield_data.lua",
	"tactics/sv_shield.lua",
	"tactics/sv_launcher.lua",
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

	"squad/sv_squad.lua",
	"squad/sv_squad_tactics.lua",
	"squad/sv_chatter.lua",
	"squad/sv_radio.lua",

	"npc/sv_brain.lua",
	"npc/cl_body.lua",
	"npc/cl_gunmag.lua",
	"npc/cl_props_data.lua",
	"npc/cl_props.lua",

	"npc/sh_foley_data.lua",
	"npc/sh_foley.lua",
	"npc/cl_foley.lua",
	"npc/cl_gunhold.lua",
	"npc/cl_feet.lua",
	"npc/cl_eyes.lua",
	"npc/cl_calmwatch.lua",
	"npc/cl_flashlight.lua",
	"npc/sv_rescue.lua",

	"encounter/sv_base.lua",

	"building/sv_building.lua",
	"building/sv_clear.lua",

	"vehicle/sv_vehicle.lua",
	"vehicle/sv_routes.lua",
	"vehicle/sv_driver.lua",
	"vehicle/sv_mounted.lua",
	"vehicle/sv_convoy.lua",
	"vehicle/sv_dvroads.lua",

	"api/sv_api.lua",
	"director/sv_director.lua",

	"air/sh_air.lua",
	"air/sv_air.lua",
	"air/sv_air_ride.lua",
	"air/cl_air.lua",

	"squad/sv_orders.lua",
	"encounter/sv_base_commands.lua",

	"ui/cl_menu.lua",
	"ui/cl_settings.lua",

	"sv_selftest.lua",

	"core/sv_watchdog.lua",
}

local function load_file(path)
	local prefix = string.sub(string.match(path, "[^/]+$"), 1, 3)
	if prefix == "sv_" then
		if SERVER then
			include(path)
		end
	elseif prefix == "cl_" then
		if SERVER then
			AddCSLuaFile(path)
		else
			include(path)
		end
	else
		if SERVER then
			AddCSLuaFile(path)
		end

		include(path)
	end
end

for _, rel in ipairs(MANIFEST) do
	load_file(TIF.Root .. rel)
end

if TIF.Dev then
	if SERVER then
		AddCSLuaFile("tif_dev/sh_init.lua")
	end

	include("tif_dev/sh_init.lua")
end

MsgN("[TIF] v", TIF.Version, " loaded (", SERVER and "server" or "client", ")")
