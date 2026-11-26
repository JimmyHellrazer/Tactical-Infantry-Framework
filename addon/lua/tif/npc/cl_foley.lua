-- MW19 body foley on the client (sh_foley.lua has the sounds and surfaces). Driven by the notetracks of the clip the
-- legs play (cl_body hands it over every frame: st.legPlay[1] with its cycle), so every walk, run, turn, arrival,
-- traversal and death clip sounds where MW19 put its sounds:
--   Foot (heel plants, left / right)            footstep for his gait on the surface under him
--   mvmt_step_pre / mvmt_step_post              gear / cloth with the step (his vest kind), now and then weapon rattle
--   land                                        a landing (and the weapon's rattle)
--   ps_bodyfall_head / limb_small / limb_large / torso   body falls in the death clips
-- plus stance changes (crouch, stand, going prone and up) and a mantle sound on traversals (mwtr_). Each client plays
-- its own (EmitSound on the client: nothing over the network); only within RANGE of the local player.

TIF.FoleyCL = TIF.FoleyCL or {}
local C = TIF.FoleyCL
local F = TIF.Foley

local cvOn = CreateClientConVar("tif_foley", "1", true, false, "MW19 movement sounds on soldiers: footsteps, gear, body falls (1/0)")
local cvVol = CreateClientConVar("tif_foley_volume", "1", true, false, "Volume of the soldiers' movement sounds (0-2)")
C.RANGE = 2000
C.SURF_EVERY = 0.25
C.RATTLE_CHANCE = 0.3
-- per gait: footstep volume, sound level, the gear set's gait
local GAIT = {
	creep = { vol = 0.32, lvl = 62, step = "walk", mvmt = "creep" },
	walk = { vol = 0.5, lvl = 68, step = "walk", mvmt = "walk" },
	run = { vol = 0.7, lvl = 72, step = "run", mvmt = "run" },
	sprint = { vol = 0.85, lvl = 75, step = "sprint", mvmt = "sprint" },
	prone = { vol = 0.35, lvl = 62, step = "walk", mvmt = "prone" },
}
C.GAIT = GAIT
local FALL = { ps_bodyfall_head = "head", ps_bodyfall_limb_small = "limb_sm", ps_bodyfall_limb_large = "limb_lrg",
	ps_bodyfall_torso = "torso" }
local VESTS = { "vestlight", "vestheavy", "vestaq" }

-- A clip's sound points, sorted by time (0..1): { t, kind, arg }.
local cache = {}
local function events_of(clip)
	local ev = cache[clip]
	if ev then return ev end
	ev = {}
	local feet = false
	for _, t in ipairs(clip.tags or {}) do
		if t[1] == "Foot" and istable(t[4]) then
			feet = true
			ev[#ev + 1] = { t[2], "step", t[4].Right and "r" or "l" }
		elseif t[1] == "MoveEvent" and istable(t[4]) then
			local n = t[4].MoveEvent
			if n == "mvmt_step_pre" then ev[#ev + 1] = { t[2], "gear", "pre" }
			elseif n == "mvmt_step_post" then ev[#ev + 1] = { t[2], "gear", "post" }
			elseif n == "land" then ev[#ev + 1] = { t[2], "land" }
			elseif FALL[n] then ev[#ev + 1] = { t[2], "fall", FALL[n] }
			-- (2026-11-21, user: "melee pairs need some sort of hit of body and hit noise") the paired fights' beat
			-- cues (MW's own: one per grapple impact, each fighter), the gun knocked away, the loser going down
			elseif isstring(n) and string.sub(n, 1, 16) == "ps_hm_grnd_melee" then ev[#ev + 1] = { t[2], "scuffle" }
			elseif n == "dropgun" or n == "gun_drop" then ev[#ev + 1] = { t[2], "gundrop" }
			elseif n == "melee_death" then ev[#ev + 1] = { t[2], "fall", "torso" } end
		end
	end
	-- (moving clips without Foot notes: their foot plants, frame numbers)
	if not feet and (clip.speed or 0) > 1 and clip.frames and clip.frames > 1 then
		for _, side in ipairs({ "l", "r" }) do
			for _, fr in ipairs(clip[side .. "plant"] or {}) do ev[#ev + 1] = { fr / (clip.frames - 1), "step", side } end
		end
	end
	-- (moving clips without the gear notes: the gear with each foot plant)
	local hasGear = false
	for _, e in ipairs(ev) do if e[2] == "gear" then hasGear = true break end end
	if not hasGear and (clip.speed or 0) > 1 then
		local n = #ev
		for i = 1, n do
			local e = ev[i]
			if e[2] == "step" then ev[#ev + 1] = { math.min(1, e[1] + 0.01), "gear", "post" } end
		end
	end
	table.sort(ev, function(a, b) return a[1] < b[1] end)
	cache[clip] = ev
	return ev
end
C.EventsOf = events_of

local function vest_of(ent, st)
	if st.folVest then return st.folVest end
	local v
	if st.wkind == "lmg" or st.wkind == "rpg" then v = "vestheavy"
	else
		local s, h = tostring(ent.GetTIFFaction and ent:GetTIFFaction() or ""), 0
		for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 9973 end
		v = VESTS[h % #VESTS + 1]
	end
	st.folVest = v
	return v
end
-- (stance and mantle sounds have no "vestaq")
local function vest2(v) return v == "vestaq" and "vestlight" or v end

local function rattle_set(st)
	local k = st.wkind
	if k == "rpg" then return "launcher" end
	if k == "lmg" then return "large" end
	if k == "pistol" then return "small" end
	if k == "smg" then return "medium" end
	return math.random() < 0.5 and "medium" or "large"
end

local function surface(ent, st, now)
	if st.wade == 2 then return "waist" end
	if st.wade == 1 then return "knee" end
	if not st.folSurf or now >= (st.folSurfT or 0) then
		st.folSurfT = now + C.SURF_EVERY
		st.folSurf = F.SurfaceAt(ent:GetPos(), ent) or "concrete"
	end
	return st.folSurf
end

local function gait_of(ent, st, clip)
	if st.vbProne then return "prone" end
	local sp = (clip and (clip.speed or 0) > 1) and clip.speed or (st.speed2d or 0)
	if not st.civ and ent:GetTIFStance() == 1 then return "creep" end
	if sp < 80 then return "walk" end
	if sp < 170 then return "run" end
	return "sprint"
end

C.MAX_PER_FRAME = 10
local frameNo, played = -1, 0
function C.HearDist(lvl)
	if lvl >= 75 then return 2000 end
	if lvl >= 70 then return 1400 end
	if lvl >= 66 then return 1000 end
	return 700
end

local function play(ent, snd, lvl, vol, pitch)
	if not snd then return end
	vol = vol * cvVol:GetFloat()
	if vol <= 0.01 then return end
	local fn = FrameNumber()
	if fn ~= frameNo then frameNo, played = fn, 0 end
	if played >= C.MAX_PER_FRAME then return end
	local hd = C.HearDist(lvl) * math.sqrt(math.min(1, vol) + 0.25)
	if ent:GetPos():DistToSqr(EyePos()) > hd * hd then return end
	played = played + 1
	ent:EmitSound(snd, lvl, pitch or math.random(96, 104), math.min(1, vol), CHAN_AUTO)
end
C.Play = play

-- One sound point of the playing clip.
function C.Fire(ent, st, e, clip, now)
	if FrameNumber() == frameNo and played >= C.MAX_PER_FRAME then return end
	local kind = e[2]
	local row = F.ROW[surface(ent, st, now)] or F.ROW.concrete
	local g = GAIT[gait_of(ent, st, clip)]
	if kind == "step" then
		if st.vbProne then return end
		local s = row[1]
		play(ent, F.PickAny("step/" .. s .. "/" .. g.step .. "_" .. e[3], "step/" .. s .. "/" .. g.step .. "_" .. (e[3] == "l" and "r" or "l"),
			"step/" .. s .. "/run_" .. e[3], "step/" .. s .. "/walk_" .. e[3], "step/concrete/" .. g.step .. "_" .. e[3]), g.lvl, g.vol)
	elseif kind == "gear" then
		local v = vest_of(ent, st)
		play(ent, F.PickAny("mvmt/" .. v .. "/" .. g.mvmt .. "_" .. e[3], "mvmt/" .. v .. "/" .. g.mvmt .. "_pre",
			"mvmt/vestlight/" .. g.mvmt .. "_" .. e[3]), g.lvl - 6, g.vol * 0.45)
		if not st.civ and e[3] == "post" and (g.mvmt == "run" or g.mvmt == "sprint") and math.random() < C.RATTLE_CHANCE then
			play(ent, F.Pick("rattle/" .. rattle_set(st)), g.lvl - 8, g.vol * 0.35)
		end
	elseif kind == "land" then
		play(ent, F.PickAny("land/" .. row[1], "land/concrete"), 75, 0.9)
		if not st.civ then play(ent, F.Pick("rattle/land"), 68, 0.45) end
	elseif kind == "scuffle" then
		play(ent, "physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 75, 0.75)
		play(ent, F.Pick("accent"), 70, 0.6)
		play(ent, F.PickAny("mvmt/" .. vest_of(ent, st) .. "/run_post", "mvmt/cloth/run_post"), 68, 0.5)
	elseif kind == "gundrop" then
		play(ent, F.PickAny("drop/metal_ar/" .. row[3], "drop/metal_ar/concrete"), 70, 0.8)
	elseif kind == "fall" then
		play(ent, F.PickAny("fall/" .. row[2] .. "/" .. e[3], "fall/concrete_dry/" .. e[3]), 72, e[3] == "limb_sm" and 0.6 or 0.9)
	end
end

-- Every frame from cl_body (MW19 body, drawn): the notetracks the top leg clip passed since last frame.
function C.Update(ent, st, now)
	if not cvOn:GetBool() or not F then return end
	local lp = st.legPlay and st.legPlayN and st.legPlayN > 0 and st.legPlay[1]
	local me = LocalPlayer()
	local near = IsValid(me) and ent:GetPos():DistToSqr(me:GetPos()) < C.RANGE * C.RANGE
	-- Stance changes, going prone / getting up, traversals.
	local stance, prone, act = ent:GetTIFStance(), st.vbProne or 0, st.actName or ""
	if near and st.folStance ~= nil then
		local v = vest2(vest_of(ent, st))
		if prone ~= st.folProne then
			if prone == 1 then
				play(ent, F.Pick("stance/" .. v .. "/prone"), 66, 0.55)
				st.folProneAt = now + 0.55
			elseif prone == 3 then
				play(ent, F.Pick("stance/" .. v .. "/prone_up"), 66, 0.55)
			end
		elseif prone == 0 and stance ~= st.folStance then
			play(ent, F.Pick("stance/" .. v .. (stance == 1 and "/down" or "/up")), 62, 0.4)
		end
		if act ~= st.folAct and string.sub(act, 1, 5) == "mwtr_" then
			local h = (string.find(act, "step", 1, true) and "32up") or (string.find(act, "_sm", 1, true) and "32over") or "48over"
			play(ent, F.PickAny("mantle/" .. v .. "/" .. h, "mantle/vestlight/48over"), 68, 0.7)
		end
	end
	-- (the body hitting the ground, a moment into the get-down)
	if st.folProneAt and now >= st.folProneAt then
		st.folProneAt = nil
		if near then
			local row = F.ROW[surface(ent, st, now)] or F.ROW.concrete
			play(ent, F.PickAny("prone/" .. row[4], "prone/concrete"), 68, 0.7)
		end
	end
	st.folStance, st.folProne, st.folAct = stance, prone, act
	if not lp then st.folClip = nil return end
	C.Track(ent, st, now, lp.clip, lp.cycle or 0, near)
end

-- The sound points a clip passed since last time it was seen (same clip, last cycle -> this one, round the end for
-- loops). Shared by soldiers (cl_body's top leg clip) and civilians (their server-played sequence).
function C.Track(ent, st, now, clip, cyc, near)
	-- Same clip as last frame: the points between its last cycle and this one (round the end for loops).
	if clip == st.folClip and st.folCyc and near then
		local p = st.folCyc
		local ev = events_of(clip)
		if #ev > 0 and cyc ~= p then
			local wrapped = cyc < p
			if wrapped and not clip.loop then
				-- (a one-shot clip restarted: nothing this frame)
			elseif not wrapped and cyc - p > 0.5 then
				-- (a jump: a teleport, a resync)
			else
				for i = 1, #ev do
					local e = ev[i]
					local t = e[1]
					if (not wrapped and t > p and t <= cyc) or (wrapped and (t > p or t <= cyc)) then C.Fire(ent, st, e, clip, now) end
				end
			end
		end
	end
	st.folClip, st.folCyc = clip, cyc
end

-- Civilians (tif_civilian on the MW19 host): the server plays their clip as the entity's sequence; its name gives the
-- clip (TIFG mw_male, by seq) and GetCycle the point in it. Their gear is plain cloth, no weapon rattle.
C.CIV_SCAN = 0.5
local civs, civScanT, bySeq = {}, 0, nil
local civState = setmetatable({}, { __mode = "k" })
local function clip_of_seq(name)
	if not bySeq then
		bySeq = {}
		local all = TIFG and TIFG.Clips and TIFG.Clips.mw_male or {}
		for _, c in pairs(all) do
			if c.seq and not bySeq[string.lower(c.seq)] then bySeq[string.lower(c.seq)] = c end
		end
	end
	return bySeq[string.lower(name or "")]
end
C.ClipOfSeq = clip_of_seq

hook.Add("Think", "tif_foley_civ", function()
	if not cvOn:GetBool() or not F then return end
	local now = CurTime()
	if now >= civScanT then
		civScanT = now + C.CIV_SCAN
		civs = ents.FindByClass("tif_civilian")
	end
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local mp = me:GetPos()
	for _, ent in ipairs(civs) do
		if IsValid(ent) and not ent:IsDormant() then
			local st = civState[ent]
			if not st then st = { civ = true, folVest = "cloth" } civState[ent] = st end
			local near = ent:GetPos():DistToSqr(mp) < C.RANGE * C.RANGE
			local seq = ent:GetSequence()
			local c = seq and seq >= 0 and clip_of_seq(ent:GetSequenceName(seq))
			if c then
				st.speed2d = ent:GetVelocity():Length2D()
				C.Track(ent, st, now, c, ent:GetCycle() % 1, near)
			else
				st.folClip = nil
			end
		end
	end
end)
