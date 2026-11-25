-- 2026-11-20: soldier foley (sh_foley + cl_foley) on the real clip data and the packed sound folders.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local SND = ROOT:gsub("lua/$", "sound/")
local function exists(p) local f = io.open(SND .. p, "rb") if f then f:close() return true end return false end

local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function V:Length2D() return math.sqrt(self.x ^ 2 + self.y ^ 2) end
function V:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2 end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
MAT_CONCRETE, MAT_DIRT, MAT_GRASS, MAT_WOOD, MAT_METAL = 67, 68, 85, 87, 77
MASK_PLAYERSOLID, MASK_WATER, CHAN_AUTO = 1, 2, 0
SERVER, CLIENT = false, true
local floorMat, floorProp, water = MAT_CONCRETE, "concrete", nil
util = {
	TraceLine = function(t)
		if t.mask == MASK_WATER then
			if water then return { Hit = true, HitPos = Vector(t.endpos.x, t.endpos.y, water) } end
			return { Hit = false }
		end
		return { Hit = true, HitPos = Vector(t.start.x, t.start.y, 0), MatType = floorMat, SurfaceProps = 1 }
	end,
	GetSurfacePropName = function() return floorProp end,
}
function CreateClientConVar(_, d) return { GetBool = function() return d ~= "0" end, GetFloat = function() return tonumber(d) end } end
function IsValid(x) return x ~= nil end
local me = { GetPos = function() return Vector(0, 0, 0) end }
function LocalPlayer() return me end

local hooks, civList = {}, {}
hook = { Add = function(ev, id, fn) hooks[ev .. ":" .. id] = fn end }
ents = { FindByClass = function(c) return c == "tif_civilian" and civList or {} end }
local clock = 0
function CurTime() return clock end
TIF = {}
TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
dofile(ROOT .. "tif/npc/sh_foley_data.lua")
dofile(ROOT .. "tif/npc/sh_foley.lua")
dofile(ROOT .. "tif/npc/cl_foley.lua")
local F, C = TIF.Foley, TIF.FoleyCL

-- every surface row's sets are packed (step walk / run / sprint, land, falls, prone)
local missing = {}
for name, row in pairs(F.ROW) do
	for _, g in ipairs({ "walk", "run", "sprint" }) do
		if not (F.Pick("step/" .. row[1] .. "/" .. g .. "_l") or F.Pick("step/" .. row[1] .. "/" .. g .. "_r")) then missing[#missing + 1] = name .. ":step " .. g end
	end
	for _, part in ipairs({ "head", "limb_lrg", "limb_sm", "torso" }) do
		if not F.Pick("fall/" .. row[2] .. "/" .. part) then missing[#missing + 1] = name .. ":fall " .. part end
	end
	if not F.Pick("prone/" .. row[4]) then missing[#missing + 1] = name .. ":prone " .. row[4] end
	if not F.Pick("drop/metal_ar/" .. row[3]) then missing[#missing + 1] = name .. ":drop " .. row[3] end
end
check(#missing == 0, "every surface has its sets packed (" .. table.concat(missing, ", ") .. ")")

-- the notetracks of a walk loop and a run loop
local walk, run = clips.aim_walk_8 or clips.mstg_walk_8, nil
for n, c in pairs(clips) do
	if not walk and c.loop and (c.speed or 0) > 50 and (c.speed or 0) < 80 then walk = c end
	if not run and c.loop and (c.speed or 0) > 120 and (c.speed or 0) < 170 then run = c end
end
check(walk and run, "found a walk and a run loop")
local ew = C.EventsOf(walk)
local steps, gear = 0, 0
for _, e in ipairs(ew) do if e[2] == "step" then steps = steps + 1 elseif e[2] == "gear" then gear = gear + 1 end end
check(steps >= 2, "walk loop: at least two foot plants (" .. steps .. ")")

-- play it through: sounds at each plant, the right surface, files on disk
local played = {}
local ent = { pos = Vector(100, 0, 0) }
function ent:GetPos() return self.pos end
function ent:GetTIFStance() return 0 end
function ent:GetTIFFaction() return "usmc" end
function ent:EmitSound(s, lvl, pitch, vol) played[#played + 1] = { s = s, lvl = lvl, vol = vol } end
local function run_clip(st, clip, loops)
	st.legPlay, st.legPlayN = { { clip = clip, cycle = 0, w = 1 } }, 1
	local now = 0
	for i = 0, loops * 60 do
		st.legPlay[1].cycle = (i / 60) % 1
		now = now + 1 / 60
		C.Update(ent, st, now)
	end
end
local st = { speed2d = walk.speed, wkind = "rifle" }
run_clip(st, walk, 2)
local stepSnd, onDisk = 0, true
for _, p in ipairs(played) do
	if p.s:find("^tif/foley/step/concrete/walk_") then stepSnd = stepSnd + 1 end
	if not exists(p.s) then onDisk = false print("  missing file " .. p.s) end
end
check(stepSnd >= steps * 2 - 1, "two walk loops: a concrete walk step per plant (" .. stepSnd .. " for " .. steps .. " a loop)")
check(onDisk and #played > 0, "every sound played is a packed file (" .. #played .. ")")
-- run on grass, gear and rattle with it
played = {}
floorMat, floorProp = MAT_GRASS, "grass"
local st2 = { speed2d = run.speed, wkind = "lmg" }
run_clip(st2, run, 3)
local grass, mv = 0, 0
for _, p in ipairs(played) do
	if p.s:find("^tif/foley/step/grass_short/run_") then grass = grass + 1 end
	if p.s:find("^tif/foley/mvmt/vestheavy/run_") then mv = mv + 1 end
end
check(grass > 0, "run on grass: grass run steps (" .. grass .. ")")
check(#C.EventsOf(run) == 0 or mv > 0 or gear == 0, "LMG gunner: heavy-vest gear with the run steps (" .. mv .. ")")
-- far away: nothing
played = {}
ent.pos = Vector(9000, 0, 0)
run_clip({ speed2d = walk.speed }, walk, 1)
check(#played == 0, "beyond RANGE: silent")
ent.pos = Vector(100, 0, 0)
-- a death clip's body falls
local death
for n, c in pairs(clips) do
	for _, e in ipairs(C.EventsOf(c)) do if e[2] == "fall" then death = c break end end
	if death then break end
end
check(death ~= nil, "a death clip with body-fall notes")
if death then
	played = {}
	floorMat, floorProp = MAT_CONCRETE, "concrete"
	local s3 = { speed2d = 0 }
	s3.legPlay, s3.legPlayN = { { clip = death, cycle = 0, w = 1 } }, 1
	for i = 0, 60 do s3.legPlay[1].cycle = i / 60 C.Update(ent, s3, i / 60) end
	local falls = 0
	for _, p in ipairs(played) do if p.s:find("^tif/foley/fall/concrete_dry/") and exists(p.s) then falls = falls + 1 end end
	check(falls > 0, "death clip: concrete body falls on its notes (" .. falls .. ")")
end
-- a puddle over concrete
water = 4
check(F.SurfaceAt(Vector(0, 0, 0)) == "puddle", "shallow water over the floor: puddle")
water = nil
-- 2026-11-21: paired fights: body hits on their beat cues, the gun drop, the fall
do
	local fa, fd = clips.mwm_fight_aw_att, clips.mwm_fight_aw_def
	check(fa and fd, "fight clips")
	if fa and fd then
		played = {}
		floorMat, floorProp = MAT_CONCRETE, "concrete"
		local sa, sd = { speed2d = 0 }, { speed2d = 0 }
		sa.legPlay, sa.legPlayN = { { clip = fa, cycle = 0, w = 1 } }, 1
		sd.legPlay, sd.legPlayN = { { clip = fd, cycle = 0, w = 1 } }, 1
		for i = 0, 120 do
			sa.legPlay[1].cycle, sd.legPlay[1].cycle = i / 120, i / 120
			C.Update(ent, sa, i / 30)
			C.Update(ent, sd, i / 30)
		end
		local hits, drops, falls = 0, 0, 0
		for _, p in ipairs(played) do
			if p.s:find("body_medium_impact_hard") then hits = hits + 1 end
			if p.s:find("^tif/foley/drop/") then drops = drops + 1 end
			if p.s:find("^tif/foley/fall/") then falls = falls + 1 end
		end
		check(hits >= 6, "fight: a body hit on each beat of both fighters (" .. hits .. ")")
		check(drops == 1 and falls >= 1, "fight: the gun knocked away, the loser down (" .. drops .. " drop, " .. falls .. " fall)")
	end
end
-- a civilian walking (server-played sequence): cloth gear, steps, no weapon rattle
do
	local cwalk = clips.civ_walk
	check(cwalk ~= nil, "civ_walk clip")
	if cwalk then
		local civ = { pos = Vector(50, 0, 0), cyc = 0 }
		function civ:GetPos() return self.pos end
		function civ:IsDormant() return false end
		function civ:GetSequence() return 3 end
		function civ:GetSequenceName() return cwalk.seq end
		function civ:GetCycle() return self.cyc end
		function civ:GetVelocity() return Vector(cwalk.speed or 60, 0, 0) end
		function civ:EmitSound(s, lvl, pitch, vol) played[#played + 1] = { s = s } end
		civList = { civ }
		played = {}
		floorMat, floorProp = MAT_CONCRETE, "concrete"
		local think = hooks["Think:tif_foley_civ"]
		for i = 0, 120 do
			civ.cyc = (i / 60) % 1
			clock = i / 60
			think()
		end
		local st, cl, rat = 0, 0, 0
		for _, p in ipairs(played) do
			if p.s:find("^tif/foley/step/concrete/walk_") then st = st + 1 end
			if p.s:find("^tif/foley/mvmt/cloth/") then cl = cl + 1 end
			if p.s:find("^tif/foley/rattle/") then rat = rat + 1 end
		end
		check(st >= 2, "civilian walking: concrete walk steps (" .. st .. ")")
		check(cl > 0 and rat == 0, "civilian: cloth gear, no weapon rattle (" .. cl .. " cloth, " .. rat .. " rattle)")
	end
end
print(string.format("passed %d, failed %d", pass, fail))
