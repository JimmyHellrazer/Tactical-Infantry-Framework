-- TIF Dev Tools: the debug overlays and test / diagnostic commands, kept out of the TIF release (0.38.11). Loaded by
-- TIF's own loader (autorun/tif_init.lua, TIF.Dev) after all of TIF. Local only: not for upload.
--   overlays:  tif_debug, tif_debug_cover, tif_debug_paths (sv_debug / cl_debug, cl_cqb, cl_base, cl_vehicle)
--   soldiers:  tif_give, tif_reveal, tif_forget, tif_noise, tif_doors, tif_cover_scan, tif_suppress, tif_prone,
--              tif_cover_test, tif_cover_course, tif_info, tif_aimwhy (sv_commands)
--   bodies:    tif_stickwhy, tif_stickwatch (cl_stick); tif_modular_debug (in
--              TIF's config/sh_modular.lua, registered only with this addon)
--   deaths:    tif_deaths_recent, tif_death_ban, tif_death_unban (sv_deaths; the saved ban list is read by TIF itself)
--   vehicles:  tif_vehicle, tif_mount, tif_drive, tif_vpatrol, tif_dismount, tif_convoy*, tif_roads
--   helis:     tif_heli, tif_heli_drop, tif_heli_lz, tif_heli_release, tif_heli_kill, tif_heli_clear
--   other:     tif_bench / tif_bench_stop, tif_voice_test, tif_mw_view* (the MW clip viewer, entity tif_mw_viewer)

local FILES = {
	"sv_debug.lua", "cl_debug.lua", "cl_stick.lua",
	"sv_commands.lua",
	"sv_bench.lua", "cl_bench.lua",
	"cl_base.lua", "cl_cqb.lua",
	"sv_vehicle_commands.lua", "cl_vehicle.lua",
	"sv_heli.lua", "sv_deaths.lua", "sv_voice_test.lua",
	"sv_mw_view.lua",
}

for _, f in ipairs(FILES) do
	local path = "tif_dev/" .. f
	local prefix = string.sub(f, 1, 3)
	if prefix == "sv_" then
		if SERVER then include(path) end
	elseif prefix == "cl_" then
		if SERVER then AddCSLuaFile(path) else include(path) end
	else
		if SERVER then AddCSLuaFile(path) end
		include(path)
	end
end

MsgN("[TIF] dev tools loaded (", SERVER and "server" or "client", ")")
