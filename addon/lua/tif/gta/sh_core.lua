jit.off(true, true)
TIFG = TIFG or {}
local TIFG = TIFG

TIFG.Version = "0.98.0-tif"

TIFG.Data = TIFG.Data or { U = 39.3701, heels = {}, guns = { hands = {}, weapons = {} }, melee = { unarmed = {}, weapons = {} } }

local math_floor, math_sqrt, math_min, math_max = math.floor, math.sqrt, math.min, math.max
local string_lower = string.lower

function TIFG.Smooth(x)
	if x <= 0 then return 0 end
	if x >= 1 then return 1 end
	return x * x * (3 - 2 * x)
end

function TIFG.QuatFromRows(m00, m01, m02, m10, m11, m12, m20, m21, m22)
	local tr = m00 + m11 + m22
	if tr > 0 then
		local s = math_sqrt(tr + 1) * 2
		return (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, s / 4
	elseif m00 > m11 and m00 > m22 then
		local s = math_sqrt(1 + m00 - m11 - m22) * 2
		return s / 4, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s
	elseif m11 > m22 then
		local s = math_sqrt(1 + m11 - m00 - m22) * 2
		return (m01 + m10) / s, s / 4, (m12 + m21) / s, (m02 - m20) / s
	end
	local s = math_sqrt(1 + m22 - m00 - m11) * 2
	return (m02 + m20) / s, (m12 + m21) / s, s / 4, (m10 - m01) / s
end

function TIFG.TickOf(t) return math.floor(t / engine.TickInterval() + 0.5) end

local Frame = CLIENT and FrameNumber or engine.TickCount
TIFG.Frame = Frame

function TIFG.Piecewise(pts, x)
	if x <= pts[1] then return pts[2] end
	for i = 3, #pts, 2 do
		if x <= pts[i] then
			local x0, y0 = pts[i - 2], pts[i - 1]
			return y0 + (pts[i + 1] - y0) * (x - x0) / math_max(1e-6, pts[i] - x0)
		end
	end
	return pts[#pts]
end

function TIFG.ApproachAngle(from, to, step)
	return math.NormalizeAngle(from + math.Clamp(math.AngleDifference(to, from), -step, step))
end

TIFG.Recs = TIFG.Recs or {}
local Recs = TIFG.Recs

local function Rec(ply)
	local r = Recs[ply]
	if not r then
		r = {}
		Recs[ply] = r
	end
	return r
end
TIFG.Rec = Rec

hook.Add("EntityRemoved", "tif_gta_assets_rec", function(ent, full_update)
	if not full_update then Recs[ent] = nil end
end)
local sight_out = {}
local sight_tr = { mask = MASK_SOLID_BRUSHONLY, output = sight_out }

function TIFG.ClearSight(from, to, filter)
	sight_tr.start, sight_tr.endpos, sight_tr.filter = from, to, filter
	util.TraceLine(sight_tr)
	return not sight_out.Hit
end
local MUZZLES = { "Gun_Muzzle", "muzzle", "muzzle_flash" }
local HANDS = { "PH_R_Hand", "ValveBiped.Bip01_R_Hand" }

local bone_ids = {}
function TIFG.BoneOf(ent, name, model)
	model = model or ent:GetModel() or ""
	local ids = bone_ids[model]
	if not ids then
		ids = {}
		bone_ids[model] = ids
	end
	local b = ids[name]
	if b == nil then
		b = ent:LookupBone(name)
		if not b then
			if ent:GetBoneCount() <= 0 then return nil end
			b = false
		end
		ids[name] = b
	end
	return b or nil
end

function TIFG.HandData(w)
	local G = w.GTG
	return G and G.hand or TIFG.Data.guns.hands[w:GetClass()]
end

function TIFG.MuzzleAttachment(e)
	local model = e:GetModel()
	if e.gtg_muz_model ~= model or e.gtg_muz_axis == nil or e.gtg_muz_side == nil then
		if e:GetBoneCount() <= 0 then return 0, false, false end
		local a, axis, side = 0, false, false
		for i, n in ipairs(MUZZLES) do
			a = e:LookupAttachment(n) or 0
			if a > 0 then
				axis, side = i == 1, n == "muzzle_flash"
				break
			end
		end
		e.gtg_muz_model, e.gtg_muz_att, e.gtg_muz_axis, e.gtg_muz_side = model, a, axis, side
	end
	return e.gtg_muz_att, e.gtg_muz_axis, e.gtg_muz_side
end
TIFG.FPS = 30
local FPS = TIFG.FPS

TIFG.Clips = TIFG.Clips or {}
TIFG.ClipList = TIFG.ClipList or {}
TIFG.ClipMeta = TIFG.ClipMeta or {}
TIFG.ClipSetPacks = TIFG.ClipSetPacks or {}
TIFG.ClipParts = TIFG.ClipParts or {}
TIFG.MaxClips = 32767

local function curve_at(clip, frame, axis)
	local c = clip.curve
	local n = #c / 3
	if n == 0 then return 0 end
	local fi = frame / 3
	if fi <= 0 then return c[axis] end
	if fi >= n - 1 then return c[(n - 1) * 3 + axis] end
	local i = math_floor(fi)
	local a = c[i * 3 + axis]
	return a + (c[i * 3 + 3 + axis] - a) * (fi - i)
end
TIFG.ClipCurve = curve_at

function TIFG.ClipSpeedAt(clip, frame)
	local a, b = math_max(0, frame - 3), math_min(clip.frames - 1, frame + 3)
	if b <= a then return 0 end
	local dx = curve_at(clip, b, 1) - curve_at(clip, a, 1)
	local dy = curve_at(clip, b, 2) - curve_at(clip, a, 2)
	return math_sqrt(dx * dx + dy * dy) / ((b - a) / FPS)
end

function TIFG.ClipZ(clip, frame)
	local z = clip.zcurve
	if not z or #z == 0 then return 0 end
	local fi = frame / 3
	if fi <= 0 then return z[1] end
	if fi >= #z - 1 then return z[#z] end
	local i = math_floor(fi)
	return z[i + 1] + (z[i + 2] - z[i + 1]) * (fi - i)
end

TIFG.TagNames = {
	["0x6A82789F"] = "blend_out_start", ["0xFC86B701"] = "blend_out_stop", ["0x5988CE8B"] = "blend_out_180",
	["0x1B29D114"] = "blend_out_walk_to_run", ["0xE3439045"] = "blend_out_run_to_walk",
	["0x895645CC"] = "blend_out_idle_intro", ["0x02E312A0"] = "blend_out_idle_turn",
	["0x08F7E474"] = "use_left_foot_transition", ["0x7E1C8464"] = "restart_window",
	["0xF4AD8374"] = "rf_cross", ["0x3CA0F9B7"] = "lf_cross", ["0x02514515"] = "transition_switch_blend_out",
	["0x47A803B7"] = "interrupt_window", ["0xC5DDBCB4"] = "exit_launch", ["0xD4D6E7A9"] = "land_right_foot",
	["0x210E0F0B"] = "takeoff", ["0x5592F240"] = "blend_out_transition", ["0x6D3BD180"] = "leftsided",
	exitlaunch = "exit_launch", landrightfoot = "land_right_foot",
	["0x7D508457"] = "melee_homing", ["0xDFAFBD8C"] = "melee_collision", ["0xC1E9C6E6"] = "melee_contact",
	["0x3E141A7C"] = "melee_dodge", ["0x577687C7"] = "melee_invulnerability",
	["0xC38BDAB2"] = "switch_to_ragdoll",
	["0x2EDADD93"] = "releaseammoclip", ["0x0DD0E14B"] = "createammoclipinlefthand", ["0x2DDC39F4"] = "createammoclip",
	["0xB248F4EC"] = "allowswapweapon", ["0x01E6EFFA"] = "reloadanimfinished",
	["0xA5F6D578"] = "ik",
	["0x40B09B11"] = "loop_event",
}

local function resolve_tags(clip)
	local tags, first, list = clip.tags, {}, {}
	for i = 1, tags and #tags or 0 do
		local t = tags[i]
		local n = t[1]
		if n == "MoveEvent" and istable(t[4]) and isstring(t[4].MoveEvent) then n = t[4].MoveEvent end
		n = string_lower(TIFG.TagNames[n] or n)
		list[i] = n
		if not first[n] then first[n] = t end
		local ev = istable(t[4]) and t[4].Event
		if isstring(ev) then
			ev = "event:" .. string_lower(TIFG.TagNames[ev] or ev)
			if not first[ev] then first[ev] = t end
		end
	end
	clip.tag_first, clip.tag_names = first, list
end

function TIFG.ClipTagPhase(clip, name)
	local first = clip.tag_first
	local t = first and (first[name] or first[string_lower(name)])
	if t then return t[2], t[3] end
end

function TIFG.ClipInTag(clip, name, p)
	local tags, names = clip.tags, clip.tag_names
	if not names then return false end
	name = string_lower(name)
	for i = 1, #names do
		if names[i] == name then
			local t = tags[i]
			if p >= t[2] and p <= t[3] then return true end
		end
	end
	return false
end

local function dedupe_wrap(plants, frames)
	if #plants >= 2 and plants[1] == 0 and frames - 1 - plants[#plants] < (plants[2] - plants[1]) * 0.5 then
		local out = {}
		for i = 2, #plants do out[i - 1] = plants[i] end
		return out
	end
	return plants
end

local function heel_plants(clip)
	local tags = clip.tags
	if not tags then return nil end
	local l, r = {}, {}
	for _, t in ipairs(tags) do
		local a = t[4]
		if t[1] == "Foot" and istable(a) and a.Heel == true then
			local f = math_floor(t[2] * (clip.frames - 1) + 0.5)
			if a.Right == true then r[#r + 1] = f else l[#l + 1] = f end
		end
	end
	if #l == 0 or #r == 0 then return nil end
	table.sort(l)
	table.sort(r)
	return l, r
end

local function by_frame(a, b) return a[1] < b[1] end

local function build_phase(clip)
	local tl, tr = heel_plants(clip)
	clip.plants_from = tl and "tags" or "detected"
	local lp, rp = tl or clip.lplant or {}, tr or clip.rplant or {}
	if clip.loop then lp, rp = dedupe_wrap(lp, clip.frames), dedupe_wrap(rp, clip.frames) end

	local events = {}
	for _, f in ipairs(lp) do events[#events + 1] = { f, false } end
	for _, f in ipairs(rp) do events[#events + 1] = { f, true } end
	table.sort(events, by_frame)

	local pts, phase = {}, nil
	for i, e in ipairs(events) do
		if not phase then phase = e[2] and 0.5 or 0
		else phase = phase + (events[i - 1][2] ~= e[2] and 0.5 or 1) end
		pts[i] = { e[1], phase }
	end

	clip.strides = nil
	if clip.loop and #lp >= 1 then
		local strides = #lp
		clip.strides = strides
		local period, n, wrapped = clip.frames - 1, #pts, {}
		for i = 1, n do
			local p = pts[i]
			wrapped[i] = { p[1] - period, p[2] - strides }
			wrapped[n + i] = p
			wrapped[2 * n + i] = { p[1] + period, p[2] + strides }
		end
		pts = wrapped
		clip.stride_len = math_sqrt(clip.move[1] ^ 2 + clip.move[2] ^ 2) / strides
	end
	clip.phase_pts = pts
	clip.phase_base = clip.strides and pts[#pts / 3 + 1][2] or (pts[1] and pts[1][2] or 0)
	clip.stride_rate = clip.strides and clip.strides / math_max(0.01, clip.dur) or nil
	clip.phase_rate = clip.stride_rate or 1 / math_max(0.1, clip.dur)
end

local function lerp_pts(a, b, frame)
	return a[2] + (b[2] - a[2]) * (frame - a[1]) / math_max(1, b[1] - a[1])
end

function TIFG.ClipPhase(clip, frame)
	local pts = clip.phase_pts
	local n = pts and #pts or 0
	if n == 0 then return frame / math_max(1, clip.frames - 1) end
	if n == 1 then return pts[1][2] + (frame - pts[1][1]) / (clip.frames / 2) end
	if frame <= pts[1][1] then return lerp_pts(pts[1], pts[2], frame) end
	for i = 2, n do
		if frame <= pts[i][1] then return lerp_pts(pts[i - 1], pts[i], frame) end
	end
	local a, b = pts[n - 1], pts[n]
	return b[2] + (frame - b[1]) * (b[2] - a[2]) / math_max(1, b[1] - a[1])
end

function TIFG.ClipFrameForPhase(clip, phase)
	local pts, strides = clip.phase_pts, clip.strides
	if not strides or not pts or #pts < 2 then return (phase % 1) * (clip.frames - 1) end
	local base = clip.phase_base
	local p = base + ((phase - base) % strides)
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if p <= b[2] then
			return (a[1] + (b[1] - a[1]) * (p - a[2]) / math_max(1e-6, b[2] - a[2])) % (clip.frames - 1)
		end
	end
	return 0
end

local function path_speed(clip)
	local c, len = clip.curve, 0
	for i = 4, #c, 3 do
		local dx, dy = c[i] - c[i - 3], c[i + 1] - c[i - 2]
		len = len + math_sqrt(dx * dx + dy * dy)
	end
	return len / math_max(0.01, clip.dur)
end

local function derive(clip, name, pack)
	clip.name, clip.pack = name, pack
	clip.move = clip.move or { 0, 0, 0 }
	clip.curve = clip.curve or {}
	clip.travel = math.deg(math.atan2(clip.move[2], clip.move[1]))
	clip.dist = math_sqrt(clip.move[1] ^ 2 + clip.move[2] ^ 2)
	clip.path_speed = path_speed(clip)
	clip.yaw_rate = clip.move[3] / math_max(0.01, clip.dur)
	clip.handover = nil
	resolve_tags(clip)
	build_phase(clip)
end

local function build_list(key, clips)
	local names = {}
	for name in pairs(clips) do names[#names + 1] = name end
	table.sort(names)
	local list = { names = names, index = {}, byindex = {}, idx = {} }
	for i, n in ipairs(names) do
		local c = clips[n]
		list.index[n], list.byindex[i], list.idx[c] = i, c, i
	end
	if #names > TIFG.MaxClips then
		ErrorNoHalt("[TIF/GTA] clip set " .. key .. " has " .. #names .. " clips; only " .. TIFG.MaxClips .. " can be networked\n")
	end
	return list
end

local function build_set(key, packs)
	local merged = {}
	for i = #packs, 1, -1 do
		local clips = TIFG.Clips[packs[i]]
		if clips and key ~= packs[i] then
			for name, clip in pairs(clips) do merged[name] = clip end
		end
	end
	TIFG.Clips[key], TIFG.ClipList[key] = merged, build_list(key, merged)
end

function TIFG.ClipSet(packs)
	if #packs == 1 then return packs[1] end
	local key = table.concat(packs, "+")
	TIFG.ClipSetPacks[key] = packs
	build_set(key, packs)
	return key
end

function TIFG.MissingPacks(char)
	local out = {}
	for _, p in ipairs(char.packs or { char.clips }) do
		local parts, meta = TIFG.ClipParts[p], TIFG.ClipMeta[p]
		local whole = TIFG.Clips[p] ~= nil
		for i = 1, parts and meta and meta.parts or 0 do
			if not parts[i] then whole = false break end
		end
		if not whole then out[#out + 1] = p end
	end
	return out
end

local function merge_parts(pack, part, clips, meta)
	local parts = TIFG.ClipParts[pack] or {}
	TIFG.ClipParts[pack] = parts
	parts[part] = clips
	if part == 1 or not TIFG.ClipMeta[pack] then TIFG.ClipMeta[pack] = meta end
	local merged = {}
	for i = 1, tonumber(TIFG.ClipMeta[pack].parts) or table.maxn(parts) do
		for name, clip in pairs(parts[i] or {}) do merged[name] = clip end
	end
	return merged
end

function TIFG.RegisterClips(pack, clips, meta)
	if not isstring(pack) or not istable(clips) then
		ErrorNoHalt("[TIF/GTA] RegisterClips: needs a pack name and a table of clips\n")
		return
	end
	for name, clip in pairs(clips) do derive(clip, name, pack) end
	meta = istable(meta) and meta or nil
	local part = meta and tonumber(meta.part)
	if part then
		clips = merge_parts(pack, part, clips, meta)
	else
		TIFG.ClipParts[pack] = nil
		TIFG.ClipMeta[pack] = meta
	end
	TIFG.Clips[pack], TIFG.ClipList[pack] = clips, build_list(pack, clips)
	for key, packs in pairs(TIFG.ClipSetPacks) do
		for _, p in ipairs(packs) do
			if p == pack then build_set(key, packs) break end
		end
	end
	return clips
end

for pack, clips in pairs(TIFG.Clips) do
	if not TIFG.ClipSetPacks[pack] then
		for name, clip in pairs(clips) do
			if istable(clip) and clip.frames then derive(clip, name, pack) end
		end
	end
end

local WEAPON_BASES = { weapon_gtg_fists = "unarmed", weapon_gtg_melee = "melee", weapon_gtg_gun = "guns", weapon_gtg_thrown = "guns" }

local function weapon_kind(swep, class)
	if WEAPON_BASES[class] then return WEAPON_BASES[class] end
	local base = swep.Base
	for _ = 1, 8 do
		if not isstring(base) then return nil end
		local kind = WEAPON_BASES[base]
		if kind then return kind end
		local b = weapons.GetStored(base)
		base = b and b.Base
	end
end

function TIFG.TintConVar(class) return "tif_gta_tint_" .. class end

function TIFG.RegisterWeapon(swep, class)
	local def = swep.GTG
	if not istable(def) then return end
	class = isstring(swep.ClassNameOverride) and swep.ClassNameOverride or class
	local kind = weapon_kind(swep, class)
	if not kind then return end
	if kind == "unarmed" then TIFG.Data.melee.unarmed[class] = true else TIFG.Data[kind].weapons[class] = def end
	local T = def.thrown
	if istable(T) and T.ammo and T.max then
		local cap, all = T.max, TIFG.Data[kind].weapons
		for _, d in pairs(all) do
			local t = istable(d.thrown) and d.thrown
			if t and t.ammo == T.ammo and t.max and t.max > cap then cap = t.max end
		end
		for _, d in pairs(all) do
			local t = istable(d.thrown) and d.thrown
			if t and t.ammo == T.ammo then t.shared_max = cap end
		end
	end
	if isstring(def.twin) then
		TIFG.Data.twins = TIFG.Data.twins or {}
		TIFG.Data.twins[def.twin] = class
	end
	if kind == "guns" and CLIENT then
		CreateClientConVar(TIFG.TintConVar(class), "0", true, true, "GTA tint of " .. class .. " (0-7)")
	end
end

function TIFG.Unarmed(w)
	return IsValid(w) and TIFG.Data.melee.unarmed[w:GetClass()] == true
end
TIFG.Characters = TIFG.Characters or {}
TIFG.ByModel = TIFG.ByModel or {}
TIFG.Aliases = TIFG.Aliases or {}

TIFG.PMS = TIFG.PMS or {}

function TIFG.PMS.Worn(ent)
	local model = ent:GetNW2String("gtgpm_model", "")
	return model ~= "" and model or nil
end

function TIFG.IsPerson(e) return IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) end
function TIFG.IsLivePerson(e) return IsValid(e) and (e:IsPlayer() and e:Alive() or e:IsNPC() or e:IsNextBot()) end

function TIFG.HeelLift(ent)
	if ent:IsPlayer() and TIFG.PMS.Worn(ent) then return 0 end
	local id = TIFG.ByModel[ent:GetModel()]
	return id and TIFG.Data.heels[id] or 0
end
TIFG.RegistryVersion = TIFG.RegistryVersion or 0

local DEFAULT_SEQUENCES = { idle = "gtg_idle", walk = "gtg_walk", run = "gtg_run", sprint = "gtg_sprint" }
local DEFAULT_SPEEDS = { walk = 73, run = 183, sprint = 251 }

function TIFG.RegisterCharacter(id, def)
	if not isstring(id) or id == "" then
		ErrorNoHalt("[TIF/GTA] RegisterCharacter: the id must be a non-empty string\n")
		return
	end
	if not istable(def) or not isstring(def.model) then
		ErrorNoHalt("[TIF/GTA] RegisterCharacter(" .. id .. "): the definition needs a model path\n")
		return
	end

	local char = table.Copy(def)
	char.id = id
	char.name = char.name or id
	char.model = string_lower((string.gsub(char.model, "\\", "/")))
	char.speeds = char.speeds or {}
	for key, default in pairs(DEFAULT_SPEEDS) do char.speeds[key] = tonumber(char.speeds[key]) or default end
	char.sequences = char.sequences or {}
	for key, default in pairs(DEFAULT_SEQUENCES) do char.sequences[key] = char.sequences[key] or default end

	char.ownPack = char.ownPack or char.clips or id
	char.libraries = istable(char.libraries) and char.libraries or {}
	char.packs = { char.ownPack }
	local seen = {}
	local function add(lib)
		if not isstring(lib) or lib == char.ownPack or seen[lib] then return end
		seen[lib] = true
		char.packs[#char.packs + 1] = lib
		local meta = TIFG.ClipMeta[lib]
		for _, inc in ipairs(meta and istable(meta.includes) and meta.includes or {}) do add(inc) end
	end
	for _, lib in ipairs(char.libraries) do add(lib) end
	char.clips = TIFG.ClipSet(char.packs)

	char.playerModelKey = "gtg_" .. id
	util.PrecacheModel(char.model)

	TIFG.Characters[id] = char
	TIFG.ByModel[char.model] = id
	for model in pairs(TIFG.Aliases[id] or {}) do TIFG.ByModel[model] = id end
	TIFG.RegistryVersion = TIFG.RegistryVersion + 1
	return char
end

function TIFG.AddCharacterModel(id, model)
	if not TIFG.Characters[id] or not isstring(model) or model == "" then return false end
	model = string_lower((string.gsub(model, "\\", "/")))
	TIFG.Aliases[id] = TIFG.Aliases[id] or {}
	TIFG.Aliases[id][model] = true
	if TIFG.ByModel[model] ~= id then
		TIFG.ByModel[model] = id
		TIFG.RegistryVersion = TIFG.RegistryVersion + 1
	end
	return true
end

local function by_name(a, b) return a.name < b.name end

function TIFG.GetCharacterList()
	local out = {}
	for _, char in pairs(TIFG.Characters) do out[#out + 1] = char end
	table.sort(out, by_name)
	return out
end
local check_content
function TIFG.GetCharacter(ply)
	local r = Rec(ply)
	local now = Frame()
	if r.char_at == now and r.regver == TIFG.RegistryVersion then return r.char end
	r.char_at = now
	local model = ply:GetModel()
	if r.model ~= model or r.regver ~= TIFG.RegistryVersion then
		r.model, r.regver = model, TIFG.RegistryVersion
		local id = model and TIFG.ByModel[string_lower(model)]
		r.char = id and TIFG.Characters[id] or nil
		r.seqs, r.tier = nil, nil
		if check_content and r.char then check_content(r.char) end
	end
	return r.char
end

for id, char in pairs(TIFG.Characters) do TIFG.RegisterCharacter(id, char) end

TIFG.Config = TIFG.Config or { enabled = 1, vehicles = 1, vehicle_doors = 1, vehicle_jacking = 1, vehicle_driveby = 1, loco = 1 }
TIFG.Ragdoll = TIFG.Ragdoll or { Active = {}, Owner = {}, Push = function() end, Start = function() end, Stun = function() return false end }
TIFG.Motion = TIFG.Motion or { CHUTE = -1, COVER = -2, STRAFE = -3, State = function() return nil end,
	Heading = function(ent) return IsValid(ent) and ent:EyeAngles().y or 0 end, ActionTrigger = function() end }
TIFG.IN_BLOCK, TIFG.IN_DETONATE = IN_BULLRUSH, IN_GRENADE2

TIFG.Weapons = TIFG.Weapons or {}
function TIFG.RegisterWeaponDef(swep)
	TIFG.Weapons[swep.ClassName] = swep
	TIFG.RegisterWeapon(swep, swep.ClassName)
end
