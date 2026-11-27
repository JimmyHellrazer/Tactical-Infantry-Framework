local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local on = true
function GetConVar() return nil end
function CreateClientConVar() return { GetBool = function() return on end } end
local timers = {}
timer = { Create = function(n, d, r, f) timers[n] = f end }
function IsValid(x) return x ~= nil and x ~= false and x ~= NULL end
NULL = {}
local now = 100
function CurTime() return now end
local logs = {}
TIF = { Body = { Stats = { composed = 0 } }, Log = function(m) logs[#logs + 1] = m end }
assert(loadfile(ROOT .. "tif/npc/cl_calmwatch.lua"))()
local CW = TIF.Body.Calm
local S = TIF.Body.Stats

local idle, idle2, walk, aimIdle, pIdle, flashIdle = { seq = "idle" }, { seq = "idle_b" }, { seq = "walk" }, { seq = "mstg_idle" }, { seq = "pstl_calm_idle" }, { seq = "idle_flash" }
local legs = {
	relaxed = { idle = idle, variants = { idle, idle2 }, walk = walk },
	relaxedFlash = { idle = flashIdle },
	aim = { idle = aimIdle },
	pistol = { relaxed = { idle = pIdle } },
}
local set = CW.CalmIdles(legs)
check(set[idle] and set[idle2] and set[pIdle] and set[flashIdle], "calm idles: relaxed, its variants, pistol and flashlight relaxed")
check(not set[aimIdle] and not set[walk], "aimed idles and walks aren't calm idles")

local function mkent(aware, shot, hit, morale)
	local e = { aware = aware, shot = shot or 0, hit = hit or 0, nw = { tif_morale = morale or "steady" } }
	function e:GetTIFShotTime() return self.shot end
	function e:GetTIFHitTime() return self.hit end
	function e:GetNW2String(k, d) return self.nw[k] or d end
	function e:GetNW2Bool(k, d) return self.nw[k] or d end
	function e:GetNW2Entity() return NULL end
	function e:EntIndex() return 7 end
	function e:GetTIFFaction() return "insurgents" end
	function e:GetTIFWeapon() return "weapon_tifmw_akm" end
	return e
end
local function run(e, st, clip, frames, opts)
	opts = opts or {}
	for _ = 1, frames do
		now = now + 0.1
		CW.Watch(e, st, legs, { { clip = clip, w = opts.w or 1 }, { clip = walk, w = opts.other or 0 } }, now, 0.1,
			opts.act, opts.stance or 0, opts.speed or 0, e.aware, opts.mode or 0)
	end
end

local e = mkent(3)
local st = {}
run(e, st, idle, 3)
check((S.calmEpisodes or 0) == 0, "a blink under 0.4 s doesn't count")
run(e, st, idle, 3)
check(S.calmEpisodes == 1 and S.calmFrames >= 2, "an engaged soldier standing in the calm idle is an episode")
check(S.calmWhy.engaged == 1, "tagged with why it's wrong")
check(#logs == 1 and logs[1]:find("[calm idle] #7 insurgents: engaged", 1, true) and logs[1]:find("clip idle", 1, true), "and logged with his context")
run(e, st, idle, 20)
check(S.calmEpisodes == 1, "one long stretch is one episode")
check(CW.Count(now) == 1, "counted as one soldier in it now")
run(e, st, aimIdle, 1)
check(st.calmT == nil and CW.Count(now) == 0, "leaving it ends the episode")

local calm = mkent(0)
local cst = {}
run(calm, cst, idle, 10)
check(S.calmEpisodes == 1, "an unaware soldier in the calm idle is fine")
local e2, st2 = mkent(2), {}
run(e2, st2, idle, 10, { act = { seq = "mwx_smoke" } })
run(e2, st2, idle, 10, { stance = 1 })
run(e2, st2, idle, 10, { speed = 120 })
run(e2, st2, idle, 10, { w = 0.3, other = 0.7 })
check(S.calmEpisodes == 1, "not counted under an action clip, crouched, moving, or when the idle isn't dominant")

local fired = mkent(0, now + 0.5)
run(fired, {}, idle, 6)
check(S.calmWhy.fired == 1, "a soldier who just fired counts even if marked unaware")
local hurt = mkent(0, 0, now + 0.5)
run(hurt, {}, idle, 6)
check(S.calmWhy.hit == 1, "and one who was just hit")
local broke = mkent(3, 0, 0, "broken")
run(broke, {}, pIdle, 6)
check(S.calmWhy["engaged+broken"] == 1, "a broken soldier in the pistol calm idle, both reasons")

logs = {}
for i = 1, 40 do
	local x = mkent(3)
	run(x, {}, idle, 6)
end
check(#logs <= CW.LOG_PER_MIN, "the log is capped per minute (" .. #logs .. ")")
local before = S.calmEpisodes
on = false
run(mkent(3), {}, idle, 10)
check(S.calmEpisodes == before, "tif_calm_watch 0 turns it off")
on = true

local body = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
check(body:find("Bd.Calm.Watch(ent, st, legs, legTop, now, dt, actClip, stance, speed, aware, mode)", 1, true) ~= nil, "compose runs the watch on the chosen leg clips")
local init = io.open(ROOT .. "autorun/tif_init.lua"):read("*a")
check(init:find('"npc/cl_calmwatch.lua"', 1, true) ~= nil, "the watch loads")
local sv = io.open("K:/SteamLibrary/steamapps/common/GarrysMod/garrysmod/addons/tif_devtools/lua/tif_dev/sv_bench.lua"):read("*a")
check(sv:find('r:Warn("Calm idle while alerted / fighting"', 1, true) ~= nil, "the bench reports it")
print(string.format("passed %d, failed %d", pass, fail))
