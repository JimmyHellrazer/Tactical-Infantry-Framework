local CATEGORY = "TacticalInfantry"

hook.Add("AddToolMenuCategories", "tif_menu_category", function()
	spawnmenu.AddToolCategory("Options", CATEGORY, "Tactical Infantry")
end)

local function add_reset_button(form, convars)
	local button = form:Button("Reset")
	button.DoClick = function()
		for i = 1, #convars do
			local name = convars[i]
			local cv = GetConVar(name)
			if cv then RunConsoleCommand(name, cv:GetDefault()) end
		end
	end
end

local function Section(panel, title, expanded, build)
	local form = vgui.Create("DForm", panel)
	form:SetName(title)
	form:SetExpanded(expanded)
	panel:AddItem(form)

	local convars = {}
	local ui = { form = form }

	function ui.Check(label, convar)
		convars[#convars + 1] = convar
		return form:CheckBox(label, convar)
	end

	function ui.Slider(label, convar, lo, hi, decimals)
		convars[#convars + 1] = convar
		return form:NumSlider(label, convar, lo, hi, decimals)
	end

	function ui.Choice(label, convar, choices)
		convars[#convars + 1] = convar
		local box = form:ComboBox(label, convar)
		for i = 1, #choices do
			local item = choices[i]
			if istable(item) then
				box:AddChoice(item[1], item[2])
			else
				box:AddChoice(item)
			end
		end
		return box
	end

	function ui.FactionChoice(label, convar)
		convars[#convars + 1] = convar
		local box = form:ComboBox(label, convar)
		local added = {}
		local order = TIF and TIF.PlayerSideOrder or {}
		for i = 1, #order do
			local id = order[i]
			box:AddChoice(id)
			added[id] = true
		end
		for id, def in SortedPairs(TIF and TIF.Factions or {}) do
			if istable(def) and not def.hidden and not added[id] then
				box:AddChoice(id)
				added[id] = true
			end
		end
		return box
	end

	function ui.Note(text)
		return form:ControlHelp(text)
	end

	function ui.Button(label, command)
		local btn = form:Button(label)
		if command then
			btn.DoClick = function() LocalPlayer():ConCommand(command) end
		end
		return btn
	end

	build(ui)
	if #convars > 0 then add_reset_button(form, convars) end

	return form
end

local function ServerPanel(panel)
	panel:ClearControls()
	panel:Help("Tactical Infantry Framework " .. tostring(TIF and TIF.Version or ""))
	panel:Help("Only the host or an admin can change these")

	Section(panel, "Spawning & Actions", true, function(ui)
		local facBox = ui.form:ComboBox("Faction")
		local firstFac
		for id, def in SortedPairs(TIF and TIF.Factions or {}) do
			if istable(def) and not def.hidden and (def.models or def.variants) then
				local label = def.name and (def.name .. " (" .. id .. ")") or id
				facBox:AddChoice(label, id, not firstFac)
				firstFac = firstFac or id
			end
		end

		local sizeSlider = ui.form:NumSlider("Squad size", nil, 1, 12, 0)
		sizeSlider:SetValue(6)

		ui.Button("Spawn squad at crosshair").DoClick = function()
			local _, facId = facBox:GetSelected()
			local count = math.Round(sizeSlider:GetValue())
			LocalPlayer():ConCommand("tif_spawn_squad " .. (facId or firstFac or "insurgents") .. " " .. count)
		end

		ui.Button("Spawn following squad").DoClick = function()
			local _, facId = facBox:GetSelected()
			local count = math.Round(sizeSlider:GetValue())
			LocalPlayer():ConCommand("tif_spawn_squad " .. (facId or firstFac or "usmc") .. " " .. count .. " follow")
		end

		ui.Button("Garrison map base", "tif_base_garrison")
		ui.Button("Squad order menu", "tif_menu")
		ui.Button("Faction editor", "tif_factions")
		ui.Button("Remove all soldiers", "tif_clear")
		ui.Button("Remove all bases", "tif_base_clear")
	end)

	Section(panel, "AI & Factions", false, function(ui)
		ui.Check("Freeze all soldiers", "tif_ai_disabled")
		ui.Check("Ignore players", "ai_ignoreplayers")
		ui.Note("Uses Garry's Mod ai_ignoreplayers")
		ui.FactionChoice("Players' side", "tif_player_faction")
		ui.Check("HL2 & addon NPC relations", "tif_hl2_npcs")
		ui.Check("Crowd steering & unstacking", "tif_crowd")
	end)

	Section(panel, "Damage & Accuracy", false, function(ui)
		ui.Slider("Damage multiplier (all)", "tif_damage_scale", 0.1, 3, 2)
		ui.Slider("Friendly damage multiplier", "tif_damage_friendly", 0, 3, 2)
		ui.Slider("Enemy damage multiplier", "tif_damage_enemy", 0, 3, 2)
		ui.Slider("Accuracy multiplier", "tif_accuracy_scale", 0.25, 3, 2)
		ui.Slider("Health multiplier", "tif_health_scale", 0.25, 4, 2)
		ui.Note("Applies to newly spawned soldiers")
		ui.Slider("Headshot multiplier", "tif_headshot_mult", 1, 5, 1)
		ui.Slider("Blast damage taken", "tif_blast_scale", 0.25, 3, 2)
	end)

	Section(panel, "Senses & Reactions", false, function(ui)
		ui.Choice("Perception profile", "tif_perception", { "long", "standard" })
		ui.Note("DTW always uses standard")
		ui.Slider("View distance", "tif_view_scale", 0.25, 2, 2)
		ui.Slider("Spotting speed", "tif_detect_scale", 0.25, 3, 2)
		ui.Slider("Reaction time", "tif_reaction_scale", 0, 3, 2)
		ui.Note("Lower values react faster")
		ui.Slider("Gunshot hearing range", "tif_gunfire_radius", 500, 8000, 0)
	end)

	Section(panel, "Combat & Ordnance", false, function(ui)
		ui.Check("Throw grenades from cover", "tif_grenades")
		ui.Slider("Grenade damage", "tif_grenade_damage", 25, 300, 0)
		ui.Slider("Grenade blast radius", "tif_grenade_radius", 100, 500, 0)
		ui.Slider("Rockets per AT gunner", "tif_rpg_rockets", 0, 6, 0)
		ui.Slider("AT lone-target chance", "tif_rpg_lone_chance", 0, 1, 2)
		ui.Slider("Rocket damage", "tif_rocket_damage", 50, 400, 0)
		ui.Slider("Rocket blast radius", "tif_rocket_radius", 100, 500, 0)
		ui.Slider("Friendly flashbang effect", "tif_flash_friendly", 0, 1, 2)
		ui.Note("0 disables friendly flashbang stun")
		ui.Check("Human shields", "tif_shield")
		ui.Check("MW22 combat reactions", "tif_react22")
	end)

	Section(panel, "CQB & Doors", false, function(ui)
		ui.Choice("Room flashbangs", "tif_cqb_flash", {
			{ "Off", "0" },
			{ "Allies of players", "1" },
			{ "All factions", "2" },
		})
		ui.Slider("Room flash chance", "tif_cqb_flash_chance", 0, 1, 2)
		ui.Check("Kicked doors come off hinges", "tif_cqb_door_off")
		ui.Check("Door opening animations", "tif_door_anims")
		ui.Check("Bump closed doors open", "tif_door_bump_open")
	end)

	Section(panel, "Morale & Casualties", false, function(ui)
		ui.Check("Morale (shaken & broken)", "tif_morale")
		ui.Check("Wounded soldiers go down", "tif_downed")
		ui.Slider("Downed chance on lethal hit", "tif_downed_chance", 0, 1, 2)
		ui.Slider("Bleedout time (s)", "tif_bleedout", 10, 120, 0)
		ui.Check("Long wounded deaths", "tif_long_deaths")
		ui.Check("Blast knockdowns", "tif_knockdowns")
	end)

	Section(panel, "Squads, Vehicles & Safety", false, function(ui)
		ui.Slider("Squad radio range", "tif_radio_range", 0, 10000, 0)
		ui.Note("0 disables squad-to-squad radio")
		ui.Check("Voice callouts", "tif_voice")
		ui.Choice("Weapon flashlights", "tif_flashlights", {
			{ "Off", "0" },
			{ "Always on", "1" },
			{ "Dark maps only", "2" },
		})
		ui.Slider("Glide seat drop", "tif_mw_seat_drop", 10, 60, 0)
		ui.Check("Unseen soldiers warp to seats", "tif_board_unseen")
		ui.Check("Rescue soldiers under map", "tif_rescue")
		ui.Check("Remove other NPCs under map", "tif_rescue_all")
		ui.Slider("Corpse lifetime (s)", "tif_corpse_time", 0, 300, 0)
		ui.Note("0 keeps bodies until cleanup")
	end)

	Section(panel, "Server Performance", false, function(ui)
		ui.Slider("AI think budget (ms/tick)", "tif_think_budget_ms", 0.5, 10, 1)
		ui.Slider("Sight trace budget", "tif_trace_budget", 10, 200, 0)
		ui.Slider("Path compute budget", "tif_path_budget", 1, 15, 0)
		ui.Slider("Cover trace budget", "tif_cover_trace_budget", 30, 400, 0)
		ui.Slider("Cover search budget", "tif_cover_search_budget", 1, 10, 0)
		ui.Check("Precache models on map start", "tif_precache")
	end)
end

local function ClientPanel(panel)
	panel:ClearControls()

	Section(panel, "Animation & Detail", true, function(ui)
		ui.Check("Out-of-view animation LOD", "tif_anim_lod")
		ui.Slider("Out-of-view update interval", "tif_anim_lod_every", 1, 16, 0)
		ui.Note("Frames skipped per off-screen soldier")
		ui.Check("Foot IK on slopes & steps", "tif_foot_ik")
		ui.Slider("Foot IK range", "tif_foot_ik_range", 300, 4000, 0)
		ui.Slider("Max foot IK per frame", "tif_foot_ik_max", 0, 32, 0)
		ui.Check("Left-hand weapon IK", "tif_hand_ik")
		ui.Check("Runners lean into turns", "tif_turn_lean")
		ui.Check("Eye tracking", "tif_eyes")
		ui.Slider("Recoil kick strength", "tif_recoil_scale", 0, 2, 2)
		ui.Check("Draw faction models", "tif_cl_retarget")
	end)

	Section(panel, "Visuals & Effects", false, function(ui)
		ui.Check("Dropped reload magazines", "tif_mag_drop")
		ui.Slider("Max real flashlights", "tif_flashlight_max", 0, 16, 0)
		ui.Slider("Flashlight draw distance", "tif_flashlight_dist", 500, 6000, 0)
	end)

	Section(panel, "Audio", false, function(ui)
		ui.Check("Movement & foley sounds", "tif_foley")
		ui.Slider("Foley volume", "tif_foley_volume", 0, 2, 2)
	end)

	if TIF and TIF.Dev then
		Section(panel, "Debug", false, function(ui)
			ui.Check("Debug overlay & console log", "tif_debug")
			ui.Check("Show cover points", "tif_debug_cover")
			ui.Check("Show movement paths", "tif_debug_paths")
		end)
	end
end

hook.Add("PopulateToolMenu", "tif_settings", function()
	spawnmenu.AddToolMenuOption("Options", CATEGORY, "tif_server", "Server", "", "", ServerPanel)
	spawnmenu.AddToolMenuOption("Options", CATEGORY, "tif_client", "Client", "", "", ClientPanel)
end)

concommand.Add("tif_settings", function()
	local frame = vgui.Create("DFrame")
	frame:SetTitle("Tactical Infantry")
	frame:SetSize(400, math.min(ScrH() - 80, 760))
	frame:Center()
	frame:MakePopup()

	local sheet = vgui.Create("DPropertySheet", frame)
	sheet:Dock(FILL)

	local function add_tab(name, buildFn)
		local scroll = vgui.Create("DScrollPanel", sheet)
		scroll:Dock(FILL)
		local list = vgui.Create("DForm", scroll)
		list:Dock(TOP)
		list:SetName(name)
		list.ClearControls = function() end
		buildFn(list)
		sheet:AddSheet(name, scroll)
	end

	add_tab("Server", ServerPanel)
	add_tab("Client", ClientPanel)
end, nil, "Open the Tactical Infantry settings window")
