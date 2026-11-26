local SECTIONS = {
	{ "AI", {
		{ "check", "tif_ai_disabled", "Freeze all TIF soldiers" },
		{ "check", "ai_ignoreplayers", "Soldiers ignore players (GMod setting)" },
		{ "faction", "tif_player_faction", "Players' side" },
	} },
	{ "Balance (1 = default)", {
		{ "slider", "tif_damage_scale", "Damage soldiers deal (everyone)", 0.1, 3, 2 },
		{ "slider", "tif_damage_friendly", "...friendly soldiers (players' side)", 0, 3, 2 },
		{ "slider", "tif_damage_enemy", "...enemy soldiers", 0, 3, 2 },
		{ "slider", "tif_accuracy_scale", "Accuracy", 0.25, 3, 2 },
		{ "slider", "tif_health_scale", "Soldier health (new soldiers)", 0.25, 4, 2 },
		{ "slider", "tif_reaction_scale", "Reaction time (lower = faster)", 0, 3, 2 },
		{ "choice", "tif_perception", "Perception (DTW always uses standard)", { "long", "standard" } },
		{ "slider", "tif_view_scale", "View distance", 0.25, 2, 2 },
		{ "slider", "tif_detect_scale", "Spotting speed", 0.25, 3, 2 },
		{ "slider", "tif_headshot_mult", "Headshot multiplier (on soldiers)", 1, 5, 1 },
	} },
	{ "Combat", {
		{ "slider", "tif_gunfire_radius", "How far gunfire is heard", 500, 8000, 0 },
		{ "slider", "tif_recoil_scale", "Recoil kick strength (0 = off)", 0, 2, 2 },
		{ "slider", "tif_flash_friendly", "Friendly flashbangs on their own side (0 = no effect)", 0, 1, 2 },
		{ "slider", "tif_rpg_rockets", "Rockets per AT gunner (reusable launchers)", 0, 6, 0 },
		{ "slider", "tif_rpg_lone_chance", "Chance an AT gunner rockets a lone soldier", 0, 1, 2 },
		{ "slider", "tif_rocket_radius", "Rocket blast radius", 100, 500, 0 },
	} },
	{ "Morale and casualties", {
		{ "check", "tif_morale", "Morale (soldiers get shaken and break)" },
		{ "check", "tif_downed", "Wounded soldiers go down instead of dying" },
		{ "slider", "tif_downed_chance", "Chance a killing hit downs instead", 0, 1, 2 },
		{ "slider", "tif_bleedout", "Seconds until a downed soldier bleeds out", 10, 120, 0 },
	} },
	{ "Squads and radio", {
		{ "slider", "tif_radio_range", "Radio range (0 = no squad-to-squad radio)", 0, 10000, 0 },
		{ "check", "tif_voice", "Voice callouts" },
	} },
	{ "Vehicles", {
		{ "slider", "tif_mw_seat_drop", "Seat height in other Glide vehicles (not TIF's own)", 10, 60, 0 },
		{ "check", "tif_board_unseen", "Unseen soldiers get straight into their seats" },
	} },
	{ "Safety", {
		{ "check", "tif_rescue", "Rescue soldiers that fall under the map" },
		{ "check", "tif_rescue_all", "Also remove other NPCs that fall under the map" },
	} },
	{ "Bodies", {
		{ "slider", "tif_corpse_time", "Seconds bodies stay (0 = until cleanup)", 0, 300, 0 },
		{ "check", "tif_foot_ik", "Feet on the real ground (slopes, steps)" },
		{ "slider", "tif_foot_ik_range", "Foot IK range", 300, 4000, 0 },
		{ "check", "tif_turn_lean", "Runners lean into turns" },
		{ "check", "tif_anim_lod", "Cheap animation for soldiers out of view" },
		{ "slider", "tif_anim_lod_every", "Out-of-view soldiers update every N frames", 1, 8, 0 },
	} },
}

if TIF and TIF.Dev then
	SECTIONS[#SECTIONS + 1] = { "Debug (dev tools)", {
		{ "check", "tif_debug", "Debug overlay and console log" },
		{ "check", "tif_debug_cover", "Show cover points" },
		{ "check", "tif_debug_paths", "Show movement paths" },
	} }
end

local BUTTONS = {
	{ "Spawn militia squad at crosshair", "tif_spawn_squad militia 6" },
	{ "Spawn PMC squad (follows you)", "tif_spawn_squad pmc 6 follow" },
	{ "Garrison this map's base", "tif_base_garrison" },
	{ "Squad order menu", "tif_menu" },
	{ "Faction editor (models, weapons, vehicles)", "tif_factions" },
	{ "Remove all soldiers", "tif_clear" },
	{ "Remove all bases", "tif_base_clear" },
}

local function build(panel)
	panel:Help("Tactical Infantry Framework " .. tostring(TIF and TIF.Version or ""))
	for _, sec in ipairs(SECTIONS) do
		local h = panel:Help(sec[1])
		h:SetFont("DermaDefaultBold")
		for _, s in ipairs(sec[2]) do
			if s[1] == "check" then
				panel:CheckBox(s[3], s[2])
			elseif s[1] == "slider" then
				panel:NumSlider(s[3], s[2], s[4], s[5], s[6])
			elseif s[1] == "choice" then
				local box = panel:ComboBox(s[3], s[2])
				for _, v in ipairs(s[4]) do box:AddChoice(v) end
			elseif s[1] == "faction" then
				local box = panel:ComboBox(s[3], s[2])
				for _, id in ipairs(TIF and TIF.PlayerSideOrder or {}) do box:AddChoice(id) end
				for id in pairs(TIF and TIF.Factions or {}) do box:AddChoice(id) end
			end
		end
	end
	local h = panel:Help("Quick actions")
	h:SetFont("DermaDefaultBold")
	for _, b in ipairs(BUTTONS) do
		local btn = panel:Button(b[1])
		btn.DoClick = function() LocalPlayer():ConCommand(b[2]) end
	end
end

hook.Add("PopulateToolMenu", "tif_settings", function()
	spawnmenu.AddToolMenuOption("Utilities", "Tactical Infantry", "tif_settings", "Settings", "", "", build)
end)

concommand.Add("tif_settings", function()
	local f = vgui.Create("DFrame")
	f:SetTitle("Tactical Infantry settings")
	f:SetSize(360, math.min(ScrH() - 80, 760))
	f:Center()
	f:MakePopup()
	local scroll = vgui.Create("DScrollPanel", f)
	scroll:Dock(FILL)
	local form = vgui.Create("DForm", scroll)
	form:Dock(TOP)
	form:SetName("Settings")
	build(form)
end, nil, "Open the Tactical Infantry settings window")
