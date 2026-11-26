local TIF = TIF
local G = TIF.GTG
TIF.Anim = TIF.Anim or {}
local A = TIF.Anim

A.MODE_RELAXED, A.MODE_AIM = 0, 1
A.STANCE_STAND, A.STANCE_CROUCH = 0, 1
A.SLOTS = 8
A.LEG_SLOTS = { 0, 1, 2 }
A.UB_SLOTS = { 3, 4 }

local seqCache = {}

function A.Seq(ent, clip, ub)
	if not clip then return -1 end

	local model = ent:GetModel()
	local m = seqCache[model]

	if not m then
		m = {}
		seqCache[model] = m
	end

	local name = ub and (clip.ub or clip.seq) or clip.seq
	local s = m[name]

	if s == nil then
		s = ent:LookupSequence(name) or -1
		m[name] = s
	end

	return s
end

local function dir_set(clips, prefix)
	local set = {}
	for name, clip in pairs(clips) do
		if string.sub(name, 1, #prefix) == prefix then
			local rest = string.sub(name, #prefix + 1)
			if string.match(rest, "^[fb]wd_%-?%d+_loop$") and clip.loop and clip.travel then
				set[#set + 1] = { clip = clip, ang = clip.travel, name = name }
			end
		end
	end

	table.sort(set, function(a, b) return a.ang < b.ang end)

	local i = 1
	while i <= #set and #set > 1 do
		local j = i % #set + 1
		local gap = (set[j].ang - set[i].ang) % 360

		if j ~= i and gap < 8 then
			local dropI = string.find(set[j].name, "fwd", 1, true) and not string.find(set[i].name, "fwd", 1, true)
			table.remove(set, dropI and i or j)
		else
			i = i + 1
		end
	end

	if #set == 0 then return nil end

	local sp = 0
	for _, e in ipairs(set) do
		sp = sp + (e.clip.speed or 0)
	end

	set.speed = sp / #set
	return set
end

function A.PickDir(set, ang)
	local n = #set
	if n == 1 then return set[1].clip, set[1].clip, 0 end

	for i = 1, n do
		local a, b = set[i], set[i % n + 1]
		local span = (b.ang - a.ang) % 360

		if span == 0 then
			span = 360
		end

		local off = (ang - a.ang) % 360
		if off <= span then return a.clip, b.clip, off / span end
	end

	return set[1].clip, set[1].clip, 0
end

local legCache = {}

function A.Legs(hostId)
	local cached = legCache[hostId or "default"]
	if cached ~= nil then return cached or nil end

	local clips = G.Clips(hostId)
	if not clips then return nil end

	local L = {
		relaxed = { idle = clips.idle, walk = clips.walk, run = clips.run, sprint = clips.sprint },
		aim = { idle = clips.mstg_idle, walk = dir_set(clips, "mstg_walk_"), run = dir_set(clips, "mstg_run_") },
		crouch = { idle = clips.crouch_mstg_idle, walk = dir_set(clips, "crouch_mstg_walk_"), run = dir_set(clips, "crouch_mstg_run_") },
	}
	local ok = L.relaxed.idle and L.relaxed.walk and L.aim.idle and L.aim.walk and L.crouch.idle and L.crouch.walk

	if not ok then
		TIF.Error("Locomotion clips missing for host ", tostring(hostId))
		legCache[hostId or "default"] = false
		return nil
	end

	if clips.mwp_down and clips.mwp_up and clips.mwp_idle then
		L.prone = { down = clips.mwp_down, up = clips.mwp_up, idle = clips.mwp_idle, crawl = dir_set(clips, "mwp_crawl_"),
			aim = clips.mwp_aim }

		local tw = {}
		for i = 1, 9 do
			if clips["mwp_twitch_" .. i] then
				tw[#tw + 1] = clips["mwp_twitch_" .. i]
			end
		end

		L.prone.twitches = #tw > 0 and tw or nil

		if clips.mwp_pstl_idle then
			L.prone.pistol = { idle = clips.mwp_pstl_idle, aim = clips.mwp_pstl_aim, up = clips.mwp_pstl_up,
				crawl8 = clips.mwp_pstl_crawl_8_loop }
		end
	end

	if clips.pstl_idle then
		local walk, run = dir_set(clips, "pstl_walk_"), dir_set(clips, "pstl_run_")
		if walk then
			L.pistol = {
				aim = { idle = clips.pstl_idle, walk = walk, run = run, walkSpeed = walk.speed,
					runSpeed = run and run.speed or walk.speed * 1.8 },

				crouch = { idle = clips.pstl_crouch_idle or L.crouch.idle, walk = L.crouch.walk, run = L.crouch.run,
					walkSpeed = L.crouch.walk.speed or 50,
					runSpeed = L.crouch.run and L.crouch.run.speed or (L.crouch.walk.speed or 50) * 1.8 },
				relaxed = { idle = clips.pstl_calm_idle or L.relaxed.idle, walk = clips.pstl_calm_walk or L.relaxed.walk,
					run = clips.pstl_jog or L.relaxed.run, sprint = clips.pstl_sprint or L.relaxed.sprint },
				alert = clips.pstl_alert_idle and { idle = clips.pstl_alert_idle, walk = clips.pstl_calm_walk or L.relaxed.walk,
					walkSpeed = (clips.pstl_calm_walk or L.relaxed.walk).speed or 40 } or nil,
			}

			local tw = {}
			for i = 1, 20 do
				if clips["pstl_twitch_" .. i] then
					tw[#tw + 1] = clips["pstl_twitch_" .. i]
				end
			end

			L.pistol.aim.twitches = #tw > 0 and tw or nil
			local R = L.pistol.relaxed
			R.walkSpeed = R.walk.speed or 40
			R.runSpeed = R.run and R.run.speed or 180
			R.sprintSpeed = R.sprint and R.sprint.speed or 250
		end
	end

	if clips.cqb_idle then
		local walk, fast = dir_set(clips, "cqb_walk_"), dir_set(clips, "cqb_fast_")
		if walk then
			L.cqb = { idle = L.aim.idle or clips.cqb_idle, walk = walk, run = fast, walkSpeed = walk.speed,
				runSpeed = fast and fast.speed or walk.speed * 1.8 }
		end
	end

	if clips.mwwd_idle then
		local walk, fast = dir_set(clips, "mwwd_walk_"), dir_set(clips, "mwwd_fast_")
		if walk then
			L.wade = { aim = { idle = clips.mwwd_idle, walk = walk, run = fast, walkSpeed = walk.speed,
				runSpeed = fast and fast.speed or walk.speed * 1.6 } }

			for _, depth in ipairs({ "knee", "chest" }) do
				local idle, w = clips["mwwd_calm_" .. depth .. "_idle"], clips["mwwd_calm_" .. depth .. "_walk"]
				if idle and w then
					L.wade[depth] = { idle = idle, walk = w, walkSpeed = w.speed or 50 }
				end
			end
		end
	end

	if clips.mwa_idle and clips.mwa_walk then
		L.alert = { idle = clips.mwa_idle, walk = clips.mwa_walk, walkSpeed = clips.mwa_walk.speed or 50 }
	end

	local function variants(first, prefix)
		local list = { first }
		for n = 2, 9 do
			if clips[prefix .. n] then
				list[#list + 1] = clips[prefix .. n]
			end
		end

		return #list > 1 and list or nil
	end

	L.relaxed.variants = variants(L.relaxed.idle, "mwv_idle_")

	if L.alert then
		L.alert.variants = variants(L.alert.idle, "mwv_alert_")
	end

	L.relaxed.walkVariants = variants(L.relaxed.walk, "mwv_walk_")

	if L.alert then
		L.alert.walkVariants = variants(L.alert.walk, "mwv_awalk_")
	end

	L.relaxed.walkSpeed = L.relaxed.walk.speed or 68
	L.relaxed.runSpeed = L.relaxed.run and L.relaxed.run.speed or 186
	L.relaxed.sprintSpeed = L.relaxed.sprint and L.relaxed.sprint.speed or 278

	L.grade = { stairs = {}, slope = {} }

	for name, c in pairs(clips) do
		local st, ud = string.match(name, "^mwst_(%a+)_(%a+)$")
		if st then
			L.grade.stairs[st .. "_" .. ud] = c
		end

		local g, ud2 = string.match(name, "^mwsl_(%a+)_(%a+)$")
		if g then
			L.grade.slope[g .. "_" .. ud2] = c
		end
	end

	for n = 1, 9 do
		local c = clips["mwzw_" .. n]
		if c then
			L.whizby = L.whizby or {}
			L.whizby[n] = c
		end
	end

	for name, c in pairs(clips) do
		local kind, st = string.match(name, "^mwfk_(%a+)_(%a+)_%d+$")
		if kind then
			L.kicks = L.kicks or {}
			L.kicks[kind] = L.kicks[kind] or {}
			L.kicks[kind][st] = L.kicks[kind][st] or {}
			table.insert(L.kicks[kind][st], c)
		end
	end

	if clips.mwrg_f then
		L.rungun = { f = clips.mwrg_f, l = clips.mwrg_l, r = clips.mwrg_r, bl = clips.mwrg_bl, br = clips.mwrg_br }
	end

	if clips.mwf_calm_idle and clips.mwf_calm_walk then
		local R = L.relaxed
		L.relaxedFlash = { idle = clips.mwf_calm_idle, walk = clips.mwf_calm_walk, run = R.run, sprint = R.sprint,
			variants = variants(clips.mwf_calm_idle, "mwf_calm_idle_"), walkVariants = variants(clips.mwf_calm_walk, "mwf_calm_walk_"),
			walkSpeed = clips.mwf_calm_walk.speed or R.walkSpeed, runSpeed = R.runSpeed, sprintSpeed = R.sprintSpeed }
	end

	if L.alert and clips.mwf_alert_idle and clips.mwf_alert_walk then
		L.alertFlash = { idle = clips.mwf_alert_idle, walk = clips.mwf_alert_walk, handLight = true,
			variants = variants(clips.mwf_alert_idle, "mwf_alert_idle_"), walkVariants = variants(clips.mwf_alert_walk, "mwf_alert_walk_"),
			walkSpeed = clips.mwf_alert_walk.speed or L.alert.walkSpeed }
	end

	L.aim.walkSpeed = L.aim.walk.speed
	L.aim.runSpeed = L.aim.run and L.aim.run.speed or L.aim.walk.speed * 2
	L.crouch.walkSpeed = L.crouch.walk.speed
	L.crouch.runSpeed = L.crouch.run and L.crouch.run.speed or L.crouch.walk.speed * 1.8

	local function shallow(t)
		local o = {}
		for k, v in pairs(t) do
			o[k] = v
		end

		return o
	end

	local function with_idles(kind, aimIdle, crouchIdle, alertIdle)
		if not aimIdle then return end

		local aim, crouch = shallow(L.aim), shallow(L.crouch)
		aim.idle = aimIdle

		if crouchIdle then
			crouch.idle = crouchIdle
		end

		local alert = L.alert
		if alert and alertIdle then
			alert = shallow(L.alert)
			alert.idle, alert.variants = alertIdle, nil
		end

		L[kind] = { aim = aim, crouch = crouch, relaxed = L.relaxed, alert = alert }
	end

	with_idles("lmg", clips.lmg_idle, nil, clips.lmg_alert_idle)
	with_idles("rpg", clips.rpg_idle, clips.rpg_crouch_idle, nil)

	if L.rpg and clips.rpg_calm_idle then
		local R = L.rpg
		local aw, ar = dir_set(clips, "rpg_mstg_walk_"), dir_set(clips, "rpg_mstg_run_")

		if aw then
			R.aim.walk, R.aim.run = aw, ar or R.aim.run
			R.aim.walkSpeed, R.aim.runSpeed = aw.speed, ar and ar.speed or R.aim.runSpeed
		end

		local cw, cr = dir_set(clips, "rpg_crouch_walk_"), dir_set(clips, "rpg_crouch_run_")
		if cw then
			R.crouch.walk, R.crouch.run = cw, cr or R.crouch.run
			R.crouch.walkSpeed, R.crouch.runSpeed = cw.speed, cr and cr.speed or R.crouch.runSpeed
		end

		local rel = shallow(L.relaxed)
		rel.idle, rel.variants = clips.rpg_calm_idle, nil
		rel.walk, rel.walkVariants = clips.rpg_calm_walk or rel.walk, nil
		rel.run = clips.rpg_calm_run or rel.run
		rel.sprint = clips.rpg_calm_sprint or rel.sprint
		rel.walkSpeed = rel.walk.speed or rel.walkSpeed
		rel.runSpeed = rel.run and rel.run.speed or rel.runSpeed
		rel.sprintSpeed = rel.sprint and rel.sprint.speed or rel.sprintSpeed
		R.relaxed = rel

		if L.alert and clips.rpg_alert_idle and clips.rpg_alert_walk then
			local al = shallow(L.alert)
			al.idle, al.walk, al.variants, al.walkVariants = clips.rpg_alert_idle, clips.rpg_alert_walk, nil, nil
			al.walkSpeed = clips.rpg_alert_walk.speed or al.walkSpeed
			R.alert = al
		end
	end

	if clips.smg_sprint then
		local relaxed = shallow(L.relaxed)
		relaxed.sprint = clips.smg_sprint
		relaxed.sprintSpeed = clips.smg_sprint.speed or relaxed.sprintSpeed
		L.smg = { aim = L.aim, crouch = L.crouch, relaxed = relaxed, alert = L.alert }
	end

	if L.prone then
		L.prone.reload, L.prone.reloadPistol = clips.mwp_reload, clips.mwp_reload_pistol

		if clips.mwb_prone_in and clips.mwb_prone_aim and clips.mwb_prone_out then
			L.prone.bipod = { into = clips.mwb_prone_in, aim = clips.mwb_prone_aim, out = clips.mwb_prone_out }
		end
	end

	legCache[hostId or "default"] = L
	return L
end

function A.Speeds(hostId)
	local L = A.Legs(hostId)
	if not L then
		return { walk = 68, tactical = 90, run = 186, sprint = 278, crouch = 70 }
	end

	return {
		walk = L.relaxed.walkSpeed,
		tactical = L.aim.walkSpeed,
		run = L.relaxed.runSpeed,
		aimrun = L.aim.runSpeed,
		sprint = L.relaxed.sprintSpeed,
		crouch = L.crouch.walkSpeed,
		alert = L.alert and L.alert.walkSpeed or L.aim.walkSpeed,
	}
end

local weaponCache = setmetatable({}, { __mode = "k" })

function A.WeaponSet()
	return nil
end

function A.PitchPose()
	return 0
end
