-- TIF's animation / weapon content (global TIFG): the clip and character registry, the retarget library for
-- faction models on other rigs, the MW19 body's clips and character, the MW guns.
-- (Until TIF 0.38.0 this was a copy of GrandTheftGMod's GTA content built by tools/build_gta_bundle.py: GTA ped,
-- clips, weapons, vehicles, drive-bys, sounds, projectiles. All of that was removed: the MW19 body is the only one.)
TIFG = TIFG or {}
local ROOT = "tif/gta/"
local MANIFEST = {
	"sh_core.lua",
	"playermodel/sh_skeleton.lua", "playermodel/sh_map.lua", "playermodel/sh_pose.lua", "playermodel/cl_bones.lua",
	{ dir = "clips" }, { dir = "characters" }, { dir = "weapons" },
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
for _, e in ipairs(MANIFEST) do
	if istable(e) then
		local found = file.Find(ROOT .. e.dir .. "/*.lua", "LUA")
		table.sort(found)
		for _, f in ipairs(found) do load_file(ROOT .. e.dir .. "/" .. f) end
	else
		load_file(ROOT .. e)
	end
end
TIFG.Version = "0.98.0-tif"
