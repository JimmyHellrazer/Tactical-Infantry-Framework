-- TIF gun bake: exports MW base presets as raw meshes for the offline NPC gun pipeline (decimate, textures,
-- compile). Single player tool, run by the host:
--   tif_gunbake            bake every roster entry
--   tif_gunbake <id> ...   only those (ids from lua/tif_gunbake/sh_roster.lua; a trailing * matches a prefix)
--   tif_gunbake_list       print the roster
-- Output: garrysmod/data/tif_gunbake/<id>_smd.txt (mesh, two bones: tif_gun / tif_mag) and <id>.json (parts,
-- materials, skins, tag bones, what couldn't be applied).
AddCSLuaFile()
AddCSLuaFile("tif_gunbake/sh_roster.lua")
AddCSLuaFile("tif_gunbake/cl_export.lua")
include("tif_gunbake/sh_roster.lua")
if SERVER then
	include("tif_gunbake/sv_run.lua")
else
	include("tif_gunbake/cl_export.lua")
end
