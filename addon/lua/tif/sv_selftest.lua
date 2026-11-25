-- tif_selftest: checks every dependency, clip, model and voice set TIF relies on.
-- Writes data/tif/reports/selftest.txt.

local TIF = TIF

-- MW19 body clips the core systems use. Grouped so the report says what breaks if one is missing.
-- (GTA clips until 0.38.0; the GTA body is gone.)
local REQUIRED_CLIPS = {
	move = { "idle", "walk", "run", "sprint", "mstg_idle", "mstg_walk_fwd_0_loop", "crouch_mstg_idle", "crouch_mstg_walk_fwd_0_loop" },
	cover = { "mwc_ls_hide", "mwc_rs_hide", "mwc_cr_hide", "mwc_ls_aim", "mwc_cr_aim", "mwc_ls_exit_8", "mwc_cr_lean_in" },
	prone = { "mwp_down", "mwp_up", "mwp_idle", "mwp_aim" },
	cqb = { "cqb_idle", "cqb_walk_fwd_0_loop", "lowready", "lowready_cqb" },
	hits = { "mwk_up_back_8", "mwsu_down", "mwsu_idle" },
	recoil = { "mwfk_rifle_st_1", "mwfk_rifle_cr_1", "mwfk_prone_pr_1", "mwfk_lean_ls_1" },
	vehicle = { "mwck_s0_idle", "mwck_s1_idle", "mwck_s2_idle", "mwck_s3_idle" },
}

-- Throwaway entity to query a model's sequences and bodygroups without spawning anything visible.
local function probe(model)
	local e = ents.Create("prop_dynamic")
	if not IsValid(e) then return nil end
	e:SetModel(model)
	return e
end

local function check_dependencies(r)
	r:Section("Dependencies")
	local G = TIF.GTG
	r:Check(G.Present(), "TIF's clip registry (tif/gta)")
	for _, req in ipairs(G.REQUIRED) do
		if req[2] == "sh" then
			r:Check(G.Resolve(req[1]) ~= nil, "Registry symbol " .. req[1])
		end
	end
	r:Info("Bundled MW guns", tostring(table.Count(TIFG and TIFG.Weapons or {})))
	local mwSound = sound.GetProperties("mw19.akilo47.fire") ~= nil
	if mwSound then r:Pass("MW gun sounds") else r:Warn("MW gun sounds", "not registered: TIF packs them (config/sh_mwsounds.lua, sound/viper/); HL2 sounds are used instead") end

	r:Check(TIF.Glide.Present(), "Glide vehicle base")
	for _, class in ipairs({ "base_glide_car", "base_tif_mw_car" }) do
		local stored = scripted_ents.GetStored(class)
		if stored then r:Pass("Vehicle class " .. class) else r:Warn("Vehicle class " .. class, "not registered") end
	end
	local car = TIF.Mounted and TIF.Mounted.DefaultCar and TIF.Mounted.DefaultCar()
	if car then r:Pass("Default vehicle " .. car) else r:Warn("Default vehicle", "none: install the TIF vehicle addon (MW cars) for convoys and vehicle patrols") end
	r:Check(TIF.GTG.Character(TIF.GTG.MW_HOST) ~= nil, "MW19 animation host (mw_male)")

	if TIF.DV.Present() then
		local n = TIF.DV.WaypointCount()
		if n > 0 then r:Pass("Decent Vehicle", n .. " waypoints on this map")
		else r:Warn("Decent Vehicle", "installed, but no waypoints on this map: vehicle routes will use road detection") end
	else
		r:Warn("Decent Vehicle", "missing: vehicle routes will use road detection")
	end

	local areas = navmesh.GetNavAreaCount()
	if areas > 0 then r:Pass("Navmesh", areas .. " areas")
	else r:Fail("Navmesh", "none on this map: run nav_generate (NextBots can't path without it)") end
end

local function check_clips(r)
	r:Section("Clips on the MW19 body")
	local G = TIF.GTG
	local hostModel = G.HostModel()
	local clips = G.Clips()
	if not (hostModel and clips) then
		r:Fail("Body " .. G.MW_HOST, "not registered (models/tif_mw, lua/tif/gta/characters)")
		return
	end
	local ped = probe(hostModel)
	if not ped then r:Fail("Probe entity") return end
	local count = ped:GetSequenceCount()
	r:Info("Host model", hostModel .. " | " .. count .. " sequences | " .. ped:GetBoneCount() .. " bones")

	local maxIndex, over4095 = -1, {}
	for group, names in SortedPairs(REQUIRED_CLIPS) do
		local missing, bad = {}, {}
		for _, name in ipairs(names) do
			local c = clips[name]
			if not c then
				missing[#missing + 1] = name
			else
				local idx = ped:LookupSequence(c.seq)
				if idx < 0 then bad[#bad + 1] = name
				else
					if idx > maxIndex then maxIndex = idx end
					if idx > 4095 then over4095[#over4095 + 1] = name .. "#" .. idx end
				end
			end
		end
		if #missing == 0 and #bad == 0 then
			r:Pass("Clips: " .. group, #names .. " found")
		else
			if #missing > 0 then r:Fail("Clips: " .. group, "not in the clip table: " .. table.concat(missing, ", ")) end
			if #bad > 0 then r:Fail("Clips: " .. group, "sequence not on model: " .. table.concat(bad, ", ")) end
		end
	end
	r:Info("Highest required sequence index", tostring(maxIndex))
	if #over4095 > 0 then
		r:Warn("Required sequences above index 4095", #over4095 .. ": " .. table.concat(over4095, ", ")
			.. " (matters only if tif_spike_layers shows a 12-bit limit)")
	else
		r:Pass("All required sequences are at index 4095 or lower")
	end

	ped:Remove()
end

local function check_weapons(r)
	r:Section("Weapons")
	local G = TIF.GTG
	local classes = G.WeaponClasses()
	r:Info("MW guns with a definition", tostring(#classes))
	local noModel = {}
	for _, class in ipairs(classes) do
		local s = G.Stored(class)
		if not (s and s.WorldModel and util.IsValidModel(s.WorldModel)) then noModel[#noModel + 1] = class end
	end
	if #noModel == 0 then r:Pass("Every MW gun has its model") else r:Warn("Guns without a model", table.concat(noModel, ", ")) end
	for _, f in SortedPairs(TIF.Factions) do
		for _, class in ipairs(f.weapons or {}) do
			-- (GTA gun names from older configs resolve to their MW gun: TIF.WeaponAlias)
			local c = TIF.WeaponAlias and TIF.WeaponAlias(class) or class
			r:Check(G.WeaponDef(c) ~= nil, "Faction " .. f.id .. " weapon " .. class .. (c ~= class and (" -> " .. c) or ""))
		end
	end
end

local function check_models(r)
	r:Section("Visual models")
	local G = TIF.GTG
	local hostModel = G.HostModel()
	for _, f in SortedPairs(TIF.Factions) do
		for _, model in ipairs(f.models) do
			local label = f.id .. " " .. model
			if not util.IsValidModel(model) then
				r:Fail(label, "model not found")
			else
				local sk = G.Skeleton(model)
				r:Check(sk ~= nil, label .. ": ValveBiped skeleton", sk and (sk.n .. " bones") or "GTG's parser rejected it")
				local map = sk and hostModel and G.MapFor(hostModel, model)
				if map then
					r:Pass(label .. ": retarget map", map.n .. " bones mapped, oddness " .. TIF.Fmt(map.oddness)
						.. (map.own_all and " (keeps own proportions)" or ""))
				elseif sk then
					r:Fail(label .. ": retarget map", "PMS.MapFor returned nil")
				end
				local e = probe(model)
				if e then
					local missing = {}
					for _, s in ipairs(TIF.Prone.SEQUENCES) do
						if e:LookupSequence(s) < 0 then missing[#missing + 1] = s end
					end
					if #missing == 0 then r:Pass(label .. ": prone sequences")
					else r:Warn(label .. ": prone sequences", "missing " .. table.concat(missing, ", ")) end
					local groups = {}
					for _, bg in ipairs(e:GetBodyGroups() or {}) do
						if bg.num > 1 then groups[#groups + 1] = bg.name .. "(" .. bg.num .. ")" end
					end
					r:Info(label .. ": skins " .. e:SkinCount(), "bodygroups " .. (#groups > 0 and table.concat(groups, ", ") or "none"))
					e:Remove()
				end
			end
		end
	end
end

local function check_voices(r)
	r:Section("Voice packs")
	local V = TIF.Voice
	for _, f in SortedPairs(TIF.Factions) do
		local packs = V.FactionPacks(f)
		if #packs == 0 then r:Fail(f.id .. " voice " .. tostring(f.voice), "unknown pack") end
		for _, pack in ipairs(packs) do
			local set = V.Build(pack)
			local total, events = 0, {}
			for ev, list in SortedPairs(set.events) do
				total = total + #list
				events[#events + 1] = ev .. "=" .. #list
			end
			if total == 0 then
				r:Fail(f.id .. " voice " .. pack, "no sound files found under sound/" .. V.PACKS[pack].folder)
			else
				r:Pass(f.id .. " voice " .. pack, total .. " lines: " .. table.concat(events, ", "))
				local missing = {}
				for _, ev in ipairs(V.CORE_EVENTS) do
					if not set.events[ev] then missing[#missing + 1] = ev end
				end
				if #missing > 0 then r:Warn(f.id .. " voice " .. pack, "no lines for " .. table.concat(missing, ", ")) end
			end
		end
	end
end

function TIF.SelfTest()
	local r = TIF.NewReport("selftest", "TIF self-test")
	local steps = { check_dependencies, check_clips, check_weapons, check_models, check_voices }
	for _, step in ipairs(steps) do
		local ok, err = pcall(step, r)
		if not ok then r:Fail("Self-test step crashed", tostring(err)) end
	end
	r:Save()
	return r
end

concommand.Add("tif_selftest", function(ply)
	if not TIF.CanUseDev(ply) then return end
	TIF.SelfTest()
end, nil, "Check TIF's dependencies, clips, models and voices; writes data/tif/reports/selftest.txt")
