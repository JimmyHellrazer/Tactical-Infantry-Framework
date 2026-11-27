local TIF = TIF
TIF.Body = TIF.Body or {}
local Bd = TIF.Body
Bd.Calm = Bd.Calm or {}
local CW = Bd.Calm

local cvWatch = GetConVar("tif_calm_watch") or CreateClientConVar("tif_calm_watch", "1", true, false, "Log soldiers standing in the calm idle while alerted, fighting or broken")

CW.MIN_TIME = 0.4
CW.SHOT_RECENT = 4
CW.HIT_RECENT = 3
CW.MAX_SPEED = 40
CW.DOMINANT = 0.5
CW.LOG_GAP = 10
CW.LOG_PER_MIN = 30
CW.AWARE_NAMES = { [0] = "unaware", [1] = "suspicious", [2] = "alerted", [3] = "engaged", [4] = "searching" }

local stats = Bd.Stats
if stats then
	stats.calmFrames = stats.calmFrames or 0
	stats.calmEpisodes = stats.calmEpisodes or 0
	stats.calmNow = stats.calmNow or 0
	stats.calmWhy = stats.calmWhy or {}
end

local calmSets = setmetatable({}, { __mode = "k" })

local function add_set(set, out)
	if type(set) ~= "table" then return end

	if set.idle then
		out[set.idle] = true
	end

	for _, v in ipairs(set.variants or {}) do
		out[v] = true
	end
end

function CW.CalmIdles(legs)
	local out = calmSets[legs]
	if out then return out end

	out = {}
	add_set(legs.relaxed, out)
	add_set(legs.relaxedFlash, out)

	for _, v in pairs(legs) do
		if type(v) == "table" and type(v.relaxed) == "table" then
			add_set(v.relaxed, out)
		end
	end

	calmSets[legs] = out
	return out
end

function CW.Reasons(aware, now, shotT, hitT, morale)
	local why = {}

	if aware == 2 or aware == 3 or aware == 4 then
		why[#why + 1] = CW.AWARE_NAMES[aware]
	end

	if shotT and shotT > 0 and now - shotT < CW.SHOT_RECENT then
		why[#why + 1] = "fired"
	end

	if hitT and hitT > 0 and now - hitT < CW.HIT_RECENT then
		why[#why + 1] = "hit"
	end

	if morale == "broken" then
		why[#why + 1] = "broken"
	end

	return why
end

local active = setmetatable({}, { __mode = "k" })
local logTimes = {}

local function may_log(now)
	for i = #logTimes, 1, -1 do
		if now - logTimes[i] > 60 then
			table.remove(logTimes, i)
		end
	end

	if #logTimes >= CW.LOG_PER_MIN then return false end

	logTimes[#logTimes + 1] = now
	return true
end

function CW.Watch(ent, st, legs, legTop, now, dt, actClip, stance, speed, aware, mode)
	if not cvWatch:GetBool() or not legs then return end

	local s = Bd.Stats
	local calm = false
	local why
	local top = legTop[1]

	if top and not actClip and stance == 0 and speed < CW.MAX_SPEED and not st.vbProne
		and not ent:GetNW2Bool("tif_dying", false) and not IsValid(ent:GetNW2Entity("tif_veh", NULL)) then
		local total = 0
		for i = 1, #legTop do
			total = total + legTop[i].w
		end

		if total > 0 and top.w / total >= CW.DOMINANT and CW.CalmIdles(legs)[top.clip] then
			why = CW.Reasons(aware, now, ent:GetTIFShotTime(), ent:GetTIFHitTime(), ent:GetNW2String("tif_morale", "steady"))
			calm = #why > 0
		end
	end

	if not calm then
		st.calmT, st.calmLogged = nil, nil
		active[ent] = nil
		return
	end

	st.calmT = (st.calmT or 0) + dt
	if st.calmT < CW.MIN_TIME then return end

	s.calmFrames = (s.calmFrames or 0) + 1
	active[ent] = now

	if st.calmLogged then return end

	st.calmLogged = true
	s.calmEpisodes = (s.calmEpisodes or 0) + 1
	local key = table.concat(why, "+")
	s.calmWhy = s.calmWhy or {}
	s.calmWhy[key] = (s.calmWhy[key] or 0) + 1

	if now - (st.calmLogAt or -99) > CW.LOG_GAP and may_log(now) and TIF.Log then
		st.calmLogAt = now
		TIF.Log(string.format("[calm idle] #%d %s: %s, mode %s, weapon %s, speed %.0f, morale %s, cqb %s, slots %s, clip %s",
			ent:EntIndex(), ent:GetTIFFaction(), key, mode == 1 and "aim" or "relaxed", ent:GetTIFWeapon(), speed,
			ent:GetNW2String("tif_morale", "steady"), tostring(st.cqbMode == true), tostring(st.slotsOk ~= false),
			tostring(top.clip.seq or "?")))
	end
end

function CW.Count(now)
	local n = 0

	for ent, t in pairs(active) do
		if IsValid(ent) and now - t < 0.25 then
			n = n + 1
		else
			active[ent] = nil
		end
	end

	Bd.Stats.calmNow = n
	return n
end

timer.Create("tif_calm_watch_count", 0.2, 0, function()
	CW.Count(CurTime())
end)
