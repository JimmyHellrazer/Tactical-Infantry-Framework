local TIF = TIF
TIF.Modular = TIF.Modular or {}
local M = TIF.Modular

M.Retarget = M.Retarget or {}

if M.ForearmPalm == nil then M.ForearmPalm = false end
function M.NeedsRetarget(model)
	return isstring(model) and M.Retarget[string.lower(model)] == true
end

do
	local PMS = TIFG and TIFG.PMS
	if PMS and istable(PMS.Required) then
		for i = #PMS.Required, 1, -1 do
			if PMS.Required[i] == "valvebiped.bip01_spine" then table.remove(PMS.Required, i) end
		end
	end
end

local function prep_follower(sk)
	local PMS = TIFG.PMS
	if not sk or sk.tifAllBones then return sk end
	sk.tifAllBones = true
	for i = 0, sk.n - 1 do
		sk.weighted[i] = true

		sk.proc[i] = 99
	end
	return sk
end

do
	local PMS = TIFG and TIFG.PMS
	if PMS and PMS.MapFor and not PMS.tifAllBonesWrapped then
		PMS.tifAllBonesWrapped = true
		local mapFor = PMS.MapFor
		PMS.MapFor = function(leader, follower)
			if not (M.NeedsRetarget(follower) and PMS.Skeleton) then return mapFor(leader, follower) end
			prep_follower(PMS.Skeleton(follower))

			local palm, saved = PMS.Palm, {}
			if M.ForearmPalm == false and palm then
				for _, s in ipairs({ "l", "r" }) do
					local k = "valvebiped.bip01_" .. s .. "_forearm"
					saved[k], palm[k] = palm[k], nil
				end
			end

			local aim, savedAim = PMS.Aim, {}
			if aim then
				for _, s in ipairs({ "l", "r" }) do
					local pre = "valvebiped.bip01_" .. s .. "_"
					for bone, child in pairs({ upperarm = "forearm", forearm = "hand" }) do
						savedAim[pre .. bone] = { aim[pre .. bone] }
						aim[pre .. bone] = pre .. child
					end
				end
			end
			local map = mapFor(leader, follower)
			for k, v in pairs(saved) do palm[k] = v end
			for k, v in pairs(savedAim) do aim[k] = v[1] end
			return map
		end
	end
end

local physNames, corpseMaps = {}, {}
local function phys_bones(model)
	local key = string.lower(model)
	if physNames[key] ~= nil then return physNames[key] or nil end
	local text = file.Read(string.gsub(key, "%.mdl$", ".phy"), "GAME")
	local set = {}
	for name in string.gmatch(text or "", '"name"%s*"([^"]+)"') do set[string.lower(name)] = true end
	if next(set) == nil then
		physNames[key] = false
		return nil
	end
	set["valvebiped.bip01_head1"], set["valvebiped.bip01_neck1"] = true, true
	physNames[key] = set
	return set
end

function M.CorpseMap(leaderModel, model)
	local key = string.lower(leaderModel) .. "|" .. string.lower(model)
	if corpseMaps[key] ~= nil then return corpseMaps[key] or nil end
	local PMS = TIFG and TIFG.PMS
	local trusted = phys_bones(leaderModel)
	local lsk, fsk = PMS and PMS.Skeleton(leaderModel), PMS and prep_follower(PMS.Skeleton(model))
	if not (trusted and lsk and fsk) then
		corpseMaps[key] = false
		return nil
	end
	local only = setmetatable({}, { __index = lsk })
	only.index = {}
	for name, i in pairs(lsk.index) do if trusted[name] then only.index[name] = i end end
	local ok, map = pcall(PMS.BuildMap, only, fsk, 1)
	map = ok and map or nil
	if map then
		for _, m in ipairs(map.MAN) do
			m.angle, m.vector = Angle(m.ang[1], m.ang[2], m.ang[3]), Vector(m.pos[1], m.pos[2], m.pos[3])
		end
	end
	corpseMaps[key] = map or false
	return map
end

local restOff = {}
function M.RestOffsets(host, model)
	local key = string.lower(host or "") .. "|" .. string.lower(model or "")
	if restOff[key] ~= nil then return restOff[key] or nil end
	local G, PMS = TIF.GTG, TIFG and TIFG.PMS
	local map = G and G.MapFor and G.MapFor(host, model)
	local fsk = map and PMS and PMS.Skeleton(model)
	if not (map and fsk) then
		restOff[key] = false
		return nil
	end
	local out = {}
	for k = 1, map.n do
		local o = map.OFF[k]
		if map.K[k] == PMS.MERGE and o then
			out[fsk.name[map.B[k]]] = Matrix({ { o[1], o[2], o[3], 0 }, { o[4], o[5], o[6], 0 }, { o[7], o[8], o[9], 0 }, { 0, 0, 0, 1 } })
		end
	end
	restOff[key] = out
	return out
end

function M.Prepare(def)
	local mod = def and def.modular
	if not istable(mod) or not istable(mod.slots) then return def end
	mod.main = mod.main or "body"
	if not istable(def.models) or #def.models == 0 then
		def.models = table.Copy(mod.slots[mod.main] or {})
	end
	if mod.retarget then

		for _, list in pairs(mod.slots) do
			for _, m in ipairs(list) do M.Retarget[string.lower(m)] = true end
		end
	end
	return def
end

local function combos_of(mod)
	if mod.tifCombos ~= nil then return mod.tifCombos or nil end
	if not istable(mod.combos) or #mod.combos == 0 then
		mod.tifCombos = false
		return nil
	end
	local seen, out = {}, {}
	for _, c in ipairs(mod.combos) do
		local keys = {}
		for k in pairs(c) do if k ~= "arch" then keys[#keys + 1] = k end end
		table.sort(keys)
		local arch = istable(c.arch) and c.arch or nil
		local archKey = arch and table.concat(arch, "+") or ""
		local function walk(i, cur)
			if i > #keys then
				local id = {}
				for _, k in ipairs(keys) do id[#id + 1] = k .. "=" .. cur[k] end
				id = archKey .. ":" .. table.concat(id, ",")
				if not seen[id] then
					seen[id] = true
					local e = table.Copy(cur)
					if arch then
						e.tifArch = {}
						for _, a in ipairs(arch) do e.tifArch[a] = true end
					end
					out[#out + 1] = e
				end
				return
			end
			for _, v in ipairs(c[keys[i]]) do
				cur[keys[i]] = v
				walk(i + 1, cur)
			end
			cur[keys[i]] = nil
		end
		walk(1, {})
	end
	mod.tifCombos = out
	return out
end

if SERVER then
	local precached = {}

	function M.Pick(def, archId)
		local mod = def and def.modular
		if not istable(mod) or not istable(mod.slots) then return nil end
		local main = mod.main or "body"
		if not precached[mod] then
			precached[mod] = true
			for _, list in pairs(mod.slots) do
				for _, m in ipairs(list) do util.PrecacheModel(m) end
			end
		end
		local pick = {}
		local list = combos_of(mod)
		if list and #list > 0 then

			local fit, free = {}, {}
			for _, e in ipairs(list) do
				if e.tifArch then
					if archId and e.tifArch[archId] then fit[#fit + 1] = e end
				else
					free[#free + 1] = e
				end
			end
			local use = #fit > 0 and fit or (#free > 0 and free or list)
			local combo = (TIF.VarietyPick and TIF.VarietyPick(def.id, "combo", use)) or use[math.random(#use)]
			for k, v in pairs(combo) do if k ~= "tifArch" then pick[k] = v end end
		end
		local chance = istable(mod.chance) and mod.chance or {}
		local slots = {}
		for slot in pairs(mod.slots) do slots[#slots + 1] = slot end
		table.sort(slots)
		local model, parts = nil, {}
		for _, slot in ipairs(slots) do
			local l = mod.slots[slot]
			if #l > 0 then
				local i = pick[slot]
				if not i then
					local idx = {}
					for x = 1, #l do idx[x] = x end
					i = (TIF.VarietyPick and TIF.VarietyPick(def.id, "slot#" .. slot, idx)) or math.random(#l)
				end
				local worn = slot == main or pick[slot] ~= nil or math.random() < (chance[slot] or 1)
				local m = i > 0 and l[i] or nil
				if m and worn then
					local seed = mod.skins == false and 0 or math.random(0, 9999)
					if slot == main then model = m else parts[#parts + 1] = m .. "#" .. seed end
				end
			end
		end
		if not model then return nil end
		return model, table.concat(parts, ";")
	end
end

if CLIENT then

	M.TwistShares = M.TwistShares or { forearm = 0.3, wrist = 0.8, shoulder = 0.78 }

	local function rows(m)
		local t = m:ToTable()
		return { t[1][1], t[1][2], t[1][3], t[2][1], t[2][2], t[2][3], t[3][1], t[3][2], t[3][3] }, Vector(t[1][4], t[2][4], t[3][4])
	end
	local function mul(a, b)
		return {
			a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
			a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
			a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9] }
	end
	local function tr(a) return { a[1], a[4], a[7], a[2], a[5], a[8], a[3], a[6], a[9] } end
	local function axis_rot(a, ang)
		local c, s = math.cos(ang), math.sin(ang)
		local x, y, z, k = a[1], a[2], a[3], 1 - math.cos(ang)
		return { c + x * x * k, x * y * k - z * s, x * z * k + y * s,
			y * x * k + z * s, c + y * y * k, y * z * k - x * s,
			z * x * k - y * s, z * y * k + x * s, c + z * z * k }
	end

	local function twist(d, a)
		local w = math.sqrt(math.max(0, 1 + d[1] + d[5] + d[9])) / 2
		if w < 1e-6 then return math.pi end
		local vx, vy, vz = (d[8] - d[6]) / (4 * w), (d[3] - d[7]) / (4 * w), (d[4] - d[2]) / (4 * w)
		return 2 * math.atan2(vx * a[1] + vy * a[2] + vz * a[3], w)
	end
	local function unit(v)
		local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
		return l > 1e-6 and { v[1] / l, v[2] / l, v[3] / l } or { 1, 0, 0 }
	end
	local function set(ent, i, R, p)
		ent:SetBoneMatrix(i, Matrix({ { R[1], R[2], R[3], p.x }, { R[4], R[5], R[6], p.y }, { R[7], R[8], R[9], p.z }, { 0, 0, 0, 1 } }))
	end

	local twistData = {}
	local function twist_data(model)
		local key = string.lower(model)
		if twistData[key] ~= nil then return twistData[key] or nil end
		local PMS = TIFG and TIFG.PMS
		local sk = PMS and PMS.Skeleton(model)
		local out = {}
		for _, side in ipairs({ "l", "r" }) do
			local function ix(n) return sk and sk.index["valvebiped.bip01_" .. side .. "_" .. n] end
			local c, u, f, h, w, s = ix("clavicle"), ix("upperarm"), ix("forearm"), ix("hand"), ix("wrist"), ix("shoulder")
			if c and u and f and h then
				local function rel(a, b) return mul(tr(sk.R[a]), sk.R[b]) end
				local function loc(a, b)
					local d = { sk.t[b][1] - sk.t[a][1], sk.t[b][2] - sk.t[a][2], sk.t[b][3] - sk.t[a][3] }
					local R = tr(sk.R[a])
					return Vector(R[1] * d[1] + R[2] * d[2] + R[3] * d[3], R[4] * d[1] + R[5] * d[2] + R[6] * d[3], R[7] * d[1] + R[8] * d[2] + R[9] * d[3])
				end
				local fl = loc(f, h)
				local ul = loc(u, f)

				local carry = {}
				for i = 0, sk.n - 1 do
					local p, skip = sk.parent[i], i == h or i == w
					local under = false
					while p and p >= 0 and not skip do
						if p == h then skip = true break end
						if p == f then under = true break end
						p = sk.parent[p]
					end
					if under and not skip then carry[#carry + 1] = i end
				end

				local carryU = {}
				for i = 0, sk.n - 1 do
					local p, skip = sk.parent[i], i == f or i == s
					local under = false
					while p and p >= 0 and not skip do
						if p == f then skip = true break end
						if p == u then under = true break end
						p = sk.parent[p]
					end
					if under and not skip then carryU[#carryU + 1] = i end
				end

				local fr = loc(u, h)
				local fd = unit({ fr.x - ul.x, fr.y - ul.y, fr.z - ul.z })
				local ua = unit({ ul.x, ul.y, ul.z })
				local hU = unit({ ua[2] * fd[3] - ua[3] * fd[2], ua[3] * fd[1] - ua[1] * fd[3], ua[1] * fd[2] - ua[2] * fd[1] })
				local Ruf = rel(u, f)
				local hF = { Ruf[1] * hU[1] + Ruf[4] * hU[2] + Ruf[7] * hU[3], Ruf[2] * hU[1] + Ruf[5] * hU[2] + Ruf[8] * hU[3],
					Ruf[3] * hU[1] + Ruf[6] * hU[2] + Ruf[9] * hU[3] }
				out[#out + 1] = {
					carry = carry, carryU = carryU, hU = hU, hF = hF,
					c = c, u = u, f = f, h = h, w = w, s = s,
					fAxis = unit({ fl.x, fl.y, fl.z }), uAxis = unit({ ul.x, ul.y, ul.z }),
					hRest = rel(f, h), uRest = rel(c, u),
					wRest = w and rel(f, w), wPos = w and loc(f, w),
					sRest = s and rel(u, s), sPos = s and loc(u, s),
				}
			end
		end
		twistData[key] = #out > 0 and out or false
		return twistData[key] or nil
	end

	local function app(R, v) return { R[1] * v[1] + R[2] * v[2] + R[3] * v[3], R[4] * v[1] + R[5] * v[2] + R[6] * v[3], R[7] * v[1] + R[8] * v[2] + R[9] * v[3] } end
	local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
	local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end

	local function angle_about(a, b, k)
		local pa, pb = dot(a, k), dot(b, k)
		a = { a[1] - k[1] * pa, a[2] - k[2] * pa, a[3] - k[3] * pa }
		b = { b[1] - k[1] * pb, b[2] - k[2] * pb, b[3] - k[3] * pb }
		return math.atan2(dot(k, cross(a, b)), dot(a, b))
	end
	local MOD_M, MOD_MC, MOD_MU, MOD_MF, MOD_MH = Matrix(), Matrix(), Matrix(), Matrix(), Matrix()
	local CopyBone = TIF.CopyBone or function(ent, bone) return bone and ent:GetBoneMatrix(bone) end

	local function turn_bones(ent, list, D, o)
		for idx = 1, #list do
			local i = list[idx]
			local m = CopyBone(ent, i, MOD_M)
			if m then
				local R, p = rows(m)
				local d = p - o
				set(ent, i, mul(D, R), o + Vector(D[1] * d.x + D[2] * d.y + D[3] * d.z, D[4] * d.x + D[5] * d.y + D[6] * d.z,
					D[7] * d.x + D[8] * d.y + D[9] * d.z))
			end
		end
	end

	function M.ArmTwist(ent)
		local data = twist_data(ent:GetModel() or "")
		if not data then return end
		local sh = M.TwistShares
		local FOREARM_SHARE, WRIST_SHARE, SHOULDER_SHARE = sh.forearm or 0, sh.wrist or 0, sh.shoulder or 0
		for ai = 1, #data do
			local a = data[ai]
			local mc = CopyBone(ent, a.c, MOD_MC)
			local mu = CopyBone(ent, a.u, MOD_MU)
			local mf = CopyBone(ent, a.f, MOD_MF)
			local mh = CopyBone(ent, a.h, MOD_MH)
			if mc and mu and mf and mh then
				local C = rows(mc)
				local U, pu = rows(mu)
				local F, pf = rows(mf)
				local H, ph = rows(mh)
				local dU = unit({ pf.x - pu.x, pf.y - pu.y, pf.z - pu.z })
				local dF = unit({ ph.x - pf.x, ph.y - pf.y, ph.z - pf.z })
				local nb = cross(dU, dF)
				local sb = math.sqrt(dot(nb, nb))
				local wgt = math.Clamp((math.deg(math.atan2(sb, dot(dU, dF))) - 4) / 12, 0, 1)
				if wgt > 0 then
					nb = { nb[1] / sb, nb[2] / sb, nb[3] / sb }
					local Du = axis_rot(dU, angle_about(app(U, a.hU), nb, dU) * wgt)
					U = mul(Du, U)
					set(ent, a.u, U, pu)
					turn_bones(ent, a.carryU, Du, pu)
				end
				local Df = axis_rot(dF, angle_about(app(F, a.hF), app(U, a.hU), dF))
				local Fb = mul(Df, F)
				local th = twist(mul(mul(tr(Fb), H), tr(a.hRest)), a.fAxis)
				local roll = axis_rot(a.fAxis, th * FOREARM_SHARE)
				local F2 = mul(Fb, roll)
				set(ent, a.f, F2, pf)
				local D = mul(F2, tr(F))
				for ci = 1, #a.carry do
					local i = a.carry[ci]
					local m = CopyBone(ent, i, MOD_M)
					if m then
						local R, p = rows(m)
						local d = p - pf
						set(ent, i, mul(D, R), pf + Vector(D[1] * d.x + D[2] * d.y + D[3] * d.z, D[4] * d.x + D[5] * d.y + D[6] * d.z,
							D[7] * d.x + D[8] * d.y + D[9] * d.z))
					end
				end
				ent:SetBoneMatrix(a.h, mh)
				if a.w then
					local Rw = mul(mul(Fb, axis_rot(a.fAxis, th * WRIST_SHARE)), a.wRest)
					local o = a.wPos
					set(ent, a.w, Rw, pf + Vector(Fb[1] * o.x + Fb[2] * o.y + Fb[3] * o.z, Fb[4] * o.x + Fb[5] * o.y + Fb[6] * o.z, Fb[7] * o.x + Fb[8] * o.y + Fb[9] * o.z))
				end
				if a.s then

					local du = mul(mul(tr(C), U), tr(a.uRest))
					local au = a.uRest
					local ax = unit({ au[1] * a.uAxis[1] + au[2] * a.uAxis[2] + au[3] * a.uAxis[3],
						au[4] * a.uAxis[1] + au[5] * a.uAxis[2] + au[6] * a.uAxis[3],
						au[7] * a.uAxis[1] + au[8] * a.uAxis[2] + au[9] * a.uAxis[3] })
					local tu = twist(du, ax)
					local Rs = mul(mul(U, axis_rot(a.uAxis, -tu * SHOULDER_SHARE)), a.sRest)
					local o = a.sPos
					set(ent, a.s, Rs, pu + Vector(U[1] * o.x + U[2] * o.y + U[3] * o.z, U[4] * o.x + U[5] * o.y + U[6] * o.z, U[7] * o.x + U[8] * o.y + U[9] * o.z))
				end
			end
		end
	end

	M.SwaySettings = M.SwaySettings or { gravity = 386, stiffness = 120, drag = 6, limit = 70, dist = 800, on = true }
	M.SwayModels = M.SwayModels or {}

	if CreateClientConVar then
		local function cv(name, key, def)
			local c = CreateClientConVar(name, tostring(def), true, false)
			local function apply() M.SwaySettings[key] = key == "on" and c:GetBool() or c:GetFloat() end
			apply()
			cvars.AddChangeCallback(name, apply, "tif_sway")
		end
		cv("tif_sway", "on", 1)
		cv("tif_sway_gravity", "gravity", 386)
		cv("tif_sway_stiffness", "stiffness", 120)
		cv("tif_sway_drag", "drag", 6)
		cv("tif_sway_limit", "limit", 70)
		cv("tif_sway_dist", "dist", 800)
	end

	local function swing_rot(a, b)
		local ax = cross(a, b)
		local s = math.sqrt(dot(ax, ax))
		if s < 1e-6 then return nil end
		return axis_rot({ ax[1] / s, ax[2] / s, ax[3] / s }, math.atan2(s, dot(a, b)))
	end

	local swayData = {}
	local function sway_data(model)
		local key = string.lower(model)
		if swayData[key] ~= nil then return swayData[key] or nil end
		local PMS = TIFG and TIFG.PMS
		local sk = PMS and PMS.Skeleton(model)
		local out = {}
		if sk and M.SwayModels[key] ~= false then
			local kids = {}
			for i = 0, sk.n - 1 do
				local p = sk.parent[i]
				if p and p >= 0 then kids[p] = kids[p] or {} kids[p][#kids[p] + 1] = i end
			end
			local function cosmetic(i) return string.find(sk.name[i] or "", "j_cosmetic", 1, true) ~= nil end
			for i = 0, sk.n - 1 do
				if cosmetic(i) then
					local c
					for _, k in ipairs(kids[i] or {}) do if cosmetic(k) then c = k break end end
					if c then
						local d = { sk.t[c][1] - sk.t[i][1], sk.t[c][2] - sk.t[i][2], sk.t[c][3] - sk.t[i][3] }
						local len = math.sqrt(dot(d, d))

						local a = sk.parent[i]
						while a and a >= 0 and cosmetic(a) do a = sk.parent[a] end
						local an = a and a >= 0 and string.lower(sk.name[a] or "") or ""
						local cloth = an == "valvebiped.bip01_head1" or an == "valvebiped.bip01_neck1"
						if len > 0.3 and len <= 6 and (cloth or d[3] < -0.6 * len) then
							local R = tr(sk.R[i])
							local desc, stack = {}, { i }
							while #stack > 0 do
								local j = table.remove(stack)
								for _, k in ipairs(kids[j] or {}) do desc[#desc + 1] = k stack[#stack + 1] = k end
							end
							out[#out + 1] = { b = i, off = app(R, d), len = len, desc = desc,
								stiff = cloth and 4 or 1, limit = cloth and 0.5 or 1 }
						end
					end
				end
			end
		end
		table.sort(out, function(a, b) return a.b < b.b end)
		swayData[key] = #out > 0 and out or false
		return swayData[key] or nil
	end
	M.SwayChains = sway_data

	function M.Sway(ent)
		local S = M.SwaySettings
		if not S.on then return end
		local model = ent:GetModel() or ""
		local data = sway_data(model)
		if not data then return end
		local over = M.SwayModels[string.lower(model)]
		if istable(over) then S = setmetatable(over, { __index = M.SwaySettings }) end
		local st = ent.tifSway
		local m0 = CopyBone(ent, data[1].b, MOD_M)
		if not m0 then return end
		local _, p0 = rows(m0)
		if EyePos and (EyePos() - p0):LengthSqr() > S.dist * S.dist then
			ent.tifSway = nil
			return
		end
		local now, frame = RealTime(), FrameNumber()
		local step = true
		if st and st.frame == frame then step = false end
		local dt = st and (now - st.t) or 0
		local reset = not st or dt > 0.25 or dt < 0
		if reset then st = { p = {}, v = {}, o = {} } ent.tifSway = st end
		if step then st.frame, st.t = frame, now end
		local n = step and not reset and math.min(4, math.max(1, math.ceil(dt * 90))) or 0
		local h = n > 0 and dt / n or 0
		local K, drag, g = S.stiffness, S.drag, S.gravity
		local cosLim = math.cos(math.rad(S.limit))
		for k = 1, #data do
			local c = data[k]
			local K, cosLim = K * c.stiff, math.cos(math.rad(S.limit * c.limit))
			local m = CopyBone(ent, c.b, MOD_M)
			if m then
				local R, o = rows(m)
				local ov = { o.x, o.y, o.z }
				local off = app(R, c.off)
				local tdir = { off[1] / c.len, off[2] / c.len, off[3] / c.len }
				local target = { ov[1] + off[1], ov[2] + off[2], ov[3] + off[3] }
				local p, v, po = st.p[k], st.v[k], st.o[k]
				if not p or (p[1] - target[1]) ^ 2 + (p[2] - target[2]) ^ 2 + (p[3] - target[3]) ^ 2 > 400 then
					p, v, po = { target[1], target[2], target[3] }, { 0, 0, 0 }, ov
				end

				local va = { 0, 0, 0 }
				if n > 0 and po then
					va = { (ov[1] - po[1]) / dt, (ov[2] - po[2]) / dt, (ov[3] - po[3]) / dt }
					if dot(va, va) > 1000000 then va = { 0, 0, 0 } end
				end
				for _ = 1, n do
					local f = math.exp(-drag * h)
					for a = 1, 3 do
						v[a] = v[a] + ((target[a] - p[a]) * K - (a == 3 and g or 0)) * h
						v[a] = va[a] + (v[a] - va[a]) * f
						p[a] = p[a] + v[a] * h
					end

					local d = { p[1] - ov[1], p[2] - ov[2], p[3] - ov[3] }
					local l = math.sqrt(dot(d, d))
					local dir = l > 1e-6 and { d[1] / l, d[2] / l, d[3] / l } or tdir

					local cd = dot(dir, tdir)
					if cd < cosLim then
						local perp = { dir[1] - tdir[1] * cd, dir[2] - tdir[2] * cd, dir[3] - tdir[3] * cd }
						local pl = math.sqrt(dot(perp, perp))
						if pl > 1e-6 then
							local sn = math.sqrt(1 - cosLim * cosLim)
							dir = { tdir[1] * cosLim + perp[1] / pl * sn, tdir[2] * cosLim + perp[2] / pl * sn, tdir[3] * cosLim + perp[3] / pl * sn }
						else
							dir = tdir
						end
						v[1], v[2], v[3] = v[1] * 0.5, v[2] * 0.5, v[3] * 0.5
					end
					local vr = dot(v, dir)
					v[1], v[2], v[3] = v[1] - dir[1] * vr, v[2] - dir[2] * vr, v[3] - dir[3] * vr
					p[1], p[2], p[3] = ov[1] + dir[1] * c.len, ov[2] + dir[2] * c.len, ov[3] + dir[3] * c.len
				end
				st.p[k], st.v[k] = p, v
				if step then st.o[k] = ov end
				local d = { p[1] - ov[1], p[2] - ov[2], p[3] - ov[3] }
				local D = swing_rot(tdir, unit(d))
				if D then
					set(ent, c.b, mul(D, R), o)
					turn_bones(ent, c.desc, D, o)
				end
			end
		end
	end

	local function arm_twist_cb(fe) M.ArmTwist(fe) M.Sway(fe) if M.CheckMerge then M.CheckMerge(fe) end end

	local cvEyes = CreateClientConVar("tif_eyes", "1", true, false, "Modular faction heads: eyes look where the head points")
	local eyeData = {}
	local function eye_data(model)
		local key = string.lower(model)
		if eyeData[key] ~= nil then return eyeData[key] or nil end
		local sk = TIFG and TIFG.PMS and TIFG.PMS.Skeleton(model)
		local h = sk and sk.index["valvebiped.bip01_head1"]
		eyeData[key] = h and { head = h, fwd = app(tr(sk.R[h]), { 1, 0, 0 }) } or false
		return eyeData[key] or nil
	end
	function M.Eyes(f)
		if not cvEyes:GetBool() then return end
		local d = eye_data(f:GetModel() or "")
		local m = d and f:GetBoneMatrix(d.head)
		if not m then return end
		local w = app(rows(m), d.fwd)
		local target = m:GetTranslation() + Vector(w[1], w[2], w[3]) * 200

		f.tifEyesAtt = f.tifEyesAtt or f:LookupAttachment("eyes") or 0
		local a = f.tifEyesAtt > 0 and f:GetAttachment(f.tifEyesAtt)
		if a then
			f:SetEyeTarget((WorldToLocal(target, angle_zero, a.Pos, a.Ang)))
		else
			f:SetEyeTarget(f:WorldToLocal(target))
		end
	end

	local Parts = {}
	M.Parts = Parts
	local AllParts = {}
	M.AllParts = AllParts

	local function blank_option(bg)
		for k, sm in pairs(bg.submodels or {}) do
			if not isstring(sm) or sm == "" or string.lower(sm) == "blank" then return k end
		end
		return math.max(0, (bg.num or 1) - 1)
	end

	local PELVIS = "ValveBiped.Bip01_Pelvis"
	local function check_merge(fe)
		local leader = fe:GetParent()
		if not IsValid(leader) then fe.tifBroken = (fe.tifBroken or 0) + 1 return end
		fe.tifPelvis = fe.tifPelvis or fe:LookupBone(PELVIS) or -1
		if leader.tifPelvisModel ~= leader:GetModel() then
			leader.tifPelvisModel, leader.tifPelvis = leader:GetModel(), leader:LookupBone(PELVIS) or -1
		end
		if fe.tifPelvis < 0 or leader.tifPelvis < 0 then return end
		local a, b = fe:GetBoneMatrix(fe.tifPelvis), leader:GetBoneMatrix(leader.tifPelvis)
		if a and b and a:GetTranslation():DistToSqr(b:GetTranslation()) > 48 * 48 then
			fe.tifBroken = (fe.tifBroken or 0) + 1
		else
			fe.tifBroken = nil
		end
	end
	M.CheckMerge = check_merge

	local function solve_part(fe)
		if fe.tifMap and TIF.GTG.Solve then
			TIF.GTG.Solve(fe, fe.tifMap)
			M.ArmTwist(fe)
			M.Sway(fe)
			check_merge(fe)
		end
	end

	local function make_part(leader, model, seed)
		local map
		if M.NeedsRetarget(model) then

			if leader:GetClass() == "prop_ragdoll" and M.NeedsRetarget(leader:GetModel()) then
				map = M.CorpseMap(leader:GetModel(), model)
			else
				map = TIF.GTG.MapFor and TIF.GTG.MapFor(leader:GetModel(), model)
			end
			if not map then return nil end
		end
		local e = ClientsideModel(model, RENDERGROUP_OPAQUE)
		if not IsValid(e) then return nil end
		e:SetSkin(seed % math.max(1, e:SkinCount()))

		for _, bg in ipairs(e:GetBodyGroups() or {}) do
			e:SetBodygroup(bg.id, string.find(string.lower(bg.name), "placeholder", 1, true) and blank_option(bg) or 0)
		end
		if map then
			local seq = e:LookupSequence("reference")
			if seq and seq >= 0 then e:ResetSequence(seq) end
			e:SetCycle(0)
			e:SetPlaybackRate(0)
			for _, m in ipairs(map.MAN or {}) do
				e:ManipulateBoneAngles(m.b, m.angle)
				e:ManipulateBonePosition(m.b, m.vector)
			end
			e.tifMap = map
			e:AddCallback("BuildBonePositions", solve_part)
		end
		e:SetParent(leader)
		e:AddEffects(EF_BONEMERGE)
		e:AddEffects(EF_BONEMERGE_FASTCULL)
		e:SetLocalPos(vector_origin)
		e:SetLocalAngles(angle_zero)
		e:CreateShadow()
		AllParts[e] = true
		return e
	end

	local function clear(rec)
		for _, e in ipairs(rec.ents) do
			AllParts[e] = nil
			if IsValid(e) then e:Remove() end
		end
		rec.ents = {}
	end

	timer.Create("tif_modular_sweep", 2, 0, function()
		local owned = {}
		for _, rec in pairs(Parts) do for _, e in ipairs(rec.ents) do owned[e] = true end end
		for e in pairs(AllParts) do
			if not IsValid(e) then
				AllParts[e] = nil
			elseif not owned[e] then
				AllParts[e] = nil
				e:Remove()
				M.Swept = (M.Swept or 0) + 1
			end
		end
	end)

	hook.Add("PostCleanupMap", "tif_modular_cleanup", function()
		for owner, rec in pairs(Parts) do clear(rec) Parts[owner] = nil end
		for e in pairs(AllParts) do if IsValid(e) then e:Remove() end AllParts[e] = nil end
	end)

	function M.Ensure(owner, str, leader)
		leader = leader or owner
		if not (IsValid(owner) and IsValid(leader)) then return end
		local rec = Parts[owner]
		if rec and rec.str == str and rec.leader == leader then return rec end
		if rec then clear(rec) end
		rec = rec or { ents = {} }
		rec.str, rec.leader = str, leader
		Parts[owner] = rec
		for piece in string.gmatch(str or "", "[^;]+") do
			local model, seed = string.match(piece, "^(.-)#(%d+)$")
			local e = make_part(leader, model or piece, tonumber(seed) or 0)
			if e then rec.ents[#rec.ents + 1] = e end
		end
		return rec
	end

	local function reattach(owner, rec)
		local leader = IsValid(rec.leader) and rec.leader or owner
		for _, e in ipairs(rec.ents) do
			if IsValid(e) then
				e:SetParent(nil)
				e:SetParent(leader)
				e:RemoveEffects(EF_BONEMERGE)
				e:AddEffects(EF_BONEMERGE)
				e:AddEffects(EF_BONEMERGE_FASTCULL)
				e:SetLocalPos(vector_origin)
				e:SetLocalAngles(angle_zero)
			end
		end
	end

	if TIF.Dev then
		concommand.Add("tif_modular_debug", function()
			local recs, parts, broken = 0, 0, 0
			for owner, rec in pairs(Parts) do
				recs = recs + 1
				for _, e in ipairs(rec.ents) do
					parts = parts + 1
					if IsValid(e) and (e.tifBroken or 0) > 0 then broken = broken + 1 end
				end
				print(string.format("  owner %s  leader %s  parts %d  hidden %s", tostring(owner), tostring(rec.leader), #rec.ents, tostring(rec.hidden)))
			end
			local all = 0
			for _ in pairs(AllParts) do all = all + 1 end
			print(string.format("tif_modular: %d records, %d parts (%d alive in total), %d off their leader now, %d re-attaches, %d strays swept",
				recs, parts, all, broken, M.Healed or 0, M.Swept or 0))
		end)
	end

	local corpses = {}
	hook.Add("OnEntityCreated", "tif_modular_corpse", function(ent)
		if IsValid(ent) and ent:GetClass() == "prop_ragdoll" then corpses[ent] = RealTime() + 4 end
	end)

	hook.Add("Think", "tif_modular_parts", function()
		local Bd = TIF.Body

		for ent, st in pairs(Bd and Bd.States or {}) do

			if IsValid(st.follower) and not st.follower.tifArmTwist and st.follower.tifMap
				and M.NeedsRetarget(st.follower:GetModel()) then
				st.follower.tifArmTwist = true
				st.follower:AddCallback("BuildBonePositions", arm_twist_cb)
			end
			if IsValid(ent) and IsValid(st.follower) then

				local f = st.follower

				if (f.tifBroken or 0) >= 3 and not ent:IsDormant() and ent:GetNW2Int("tif_prone", 0) == 0 then
					f.tifBroken = nil
					f:SetParent(nil)
					f:SetParent(ent)
					f:RemoveEffects(EF_BONEMERGE)
					f:AddEffects(EF_BONEMERGE)
					f:AddEffects(EF_BONEMERGE_FASTCULL)
					f:SetLocalPos(vector_origin)
					f:SetLocalAngles(angle_zero)
					f:InvalidateBoneCache()
					M.Healed = (M.Healed or 0) + 1
				end
				if f.tifMap and M.NeedsRetarget(f:GetModel()) and not ent:IsDormant() and not f.tifEyesByBody then M.Eyes(f) end
				local str = ent:GetNW2String("tif_parts", "")
				if str ~= "" or Parts[st.follower] then
					local rec = M.Ensure(st.follower, str, ent)
					if rec then
						local noShadow = ent:GetNW2Bool("tif_noshadow", false)
						if rec.noShadow ~= noShadow then
							rec.noShadow = noShadow
							for _, e in ipairs(rec.ents) do if IsValid(e) then e:DrawShadow(not noShadow) end end
						end
					end
				end
			end
		end

		local now = RealTime()
		for rag, deadline in pairs(corpses) do
			if not IsValid(rag) then
				corpses[rag] = nil
			else
				local str = rag:GetNW2String("tif_parts", "")
				local owner
				if rag:GetNW2String("tif_vis", "") == "" then
					owner = rag
				else
					for _, r in ipairs(Bd and Bd.Rags or {}) do
						if r.rag == rag and IsValid(r.ent) then owner = r.ent break end
					end
				end
				if str ~= "" and owner then

					if owner == rag and not rag.tifSwayCb and M.NeedsRetarget(rag:GetModel()) then
						rag.tifSwayCb = true
						rag:AddCallback("BuildBonePositions", function(e) M.Sway(e) end)
					end
					M.Ensure(owner, str, rag)
					corpses[rag] = nil
				elseif now > deadline then
					corpses[rag] = nil
				end
			end
		end

		for owner, rec in pairs(Parts) do

			local leader = rec.leader
			if not IsValid(owner) or (leader ~= nil and not IsValid(leader)) then
				clear(rec)
				Parts[owner] = nil
			else

				local hidden = owner:GetNoDraw() or (owner:EntIndex() > 0 and owner:IsDormant())
					or (leader ~= owner and (leader:GetNoDraw() or (leader:EntIndex() > 0 and leader:IsDormant())))
				if hidden ~= rec.hidden then
					if rec.hidden and not hidden then reattach(owner, rec) end
					rec.hidden = hidden
					for _, e in ipairs(rec.ents) do if IsValid(e) then e:SetNoDraw(hidden) end end
				elseif not hidden and rec.ents[1] and IsValid(rec.ents[1])
					and rec.ents[1]:GetParent() ~= (IsValid(rec.leader) and rec.leader or owner) then
					reattach(owner, rec)
				elseif not hidden then

					local worst = 0
					for _, e in ipairs(rec.ents) do if IsValid(e) then worst = math.max(worst, e.tifBroken or 0) end end
					if worst >= 3 then
						rec.heals = (rec.heals or 0) + 1
						M.Healed = (M.Healed or 0) + 1
						if rec.heals > 3 then
							local s, l = rec.str, rec.leader
							clear(rec)
							rec.str, rec.heals = nil, 0
							M.Ensure(owner, s, l)
						else
							reattach(owner, rec)
							for _, e in ipairs(rec.ents) do if IsValid(e) then e.tifBroken = nil e:InvalidateBoneCache() end end
						end
					elseif worst == 0 then
						rec.heals = 0
					end
				end
			end
		end
	end)
end
