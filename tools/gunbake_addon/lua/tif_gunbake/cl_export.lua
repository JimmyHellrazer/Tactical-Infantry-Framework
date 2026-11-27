-- Client half: dumps the built gun (its world model and every attachment's third-person model) as one mesh in
-- the frame of the world model's right-hand bone, so the baked gun's origin is the grip, the way TIF places guns.
-- Magazine parts (attachments based on att_magazine, and gun geometry on mag bones) go on a second bone,
-- tif_mag, so reloads can move the mag.
local GB = TIF_GUNBAKE
local OUT = "tif_gunbake"

-- Fewest triangles worth keeping before the offline decimate (it takes the coarsest LOD above these).
local MIN_TRIS = { gun = 3000, mag = 150, part = 250 }
-- Gun bones whose geometry belongs to the magazine (rockets and belt boxes too). Numbered mag bones only:
-- j_magrel (mag release) and j_magnifier_lever are part of the gun.
local MAG_BONE = { "^j_mag%d", "^tag_clip", "^j_rocket", "^j_belt", "^j_ammobox", "^j_box" }

local function is_mag_bone(name)
	name = string.lower(name or "")
	for _, p in ipairs(MAG_BONE) do
		if string.find(name, p) then return true end
	end
	return false
end

local function based_on(att, base)
	local c = att and att.ClassName
	local guard = 0
	while c and guard < 20 do
		if c == base then return true end
		local a = MW_ATTS and MW_ATTS[c]
		c = a and a.Base
		guard = guard + 1
	end
	return false
end

local function body_mask(ent)
	local groups = ent:GetBodyGroups() or {}
	table.sort(groups, function(a, b) return a.id < b.id end)
	local mask, stride = 0, 1
	for _, g in ipairs(groups) do
		mask = mask + ent:GetBodygroup(g.id) * stride
		stride = stride * math.max(1, g.num or 1)
	end
	return mask
end

local function count_tris(meshes)
	local n = 0
	for _, m in ipairs(meshes) do n = n + #(m.triangles or {}) / 3 end
	return n
end

-- The coarsest LOD that still has minTris (LOD 0 if none has).
local function pick_lod(model, mask, minTris)
	local best, bind, lod, tris, tris0, last
	for l = 0, 7 do
		local m, b = util.GetModelMeshes(model, l, mask)
		if not m then break end
		local n = count_tris(m)
		if l == 0 then tris0 = n end
		if n == last then break end
		last = n
		if l == 0 or n >= minTris then best, bind, lod, tris = m, b, l, n end
		if n < minTris then break end
	end
	return best, bind, lod, tris, tris0
end

local function num(x) return string.format("%.4f", x) end

local function mat_rot(m)
	local r = Matrix(m)
	r:SetTranslation(vector_origin)
	return r
end

local function vec_json(v) return { v.x, v.y, v.z } end
local function ang_json(a) return { a.p, a.y, a.r } end

-- One model's triangles into lines (SMD triangle blocks), in the frame `inv`.
local function dump_model(ent, part, inv, lines, info)
	local model = ent:GetModel()
	local mask = body_mask(ent)
	local meshes, bind, lod, tris, tris0 = pick_lod(model, mask, MIN_TRIS[part.role] or MIN_TRIS.part)
	info.model, info.mask, info.lod, info.tris, info.tris_lod0 = model, mask, lod, tris, tris0
	info.skin = ent:GetSkin()
	local col = ent:GetColor()
	info.color = { col.r, col.g, col.b, col.a }
	if not meshes then info.error = "no meshes" return end
	ent:InvalidateBoneCache()
	ent:SetupBones()
	-- Skinning matrices: bone world matrix * bind pose, then into the export frame.
	local skin, rot, magOf = {}, {}, {}
	for b = 0, ent:GetBoneCount() - 1 do
		local bm = ent:GetBoneMatrix(b)
		local bp = bind and bind[b]
		if bm and bp and bp.matrix then
			local m = inv * bm * bp.matrix
			skin[b], rot[b] = m, mat_rot(m)
		end
		-- A gun bone is a mag bone if it or a parent is named like one.
		local p, isMag, guard = b, false, 0
		while p and p >= 0 and guard < 64 do
			if is_mag_bone(ent:GetBoneName(p)) then isMag = true break end
			p = ent:GetBoneParent(p)
			guard = guard + 1
		end
		magOf[b] = isMag
	end
	-- Materials: the model's own list with this entity's submaterial overrides (MW camos, blueprint finishes).
	local mats, sub = ent:GetMaterials() or {}, {}
	for i, m in ipairs(mats) do
		local s = ent:GetSubMaterial(i - 1)
		if s and s ~= "" then sub[string.lower(m)] = s end
	end
	info.materials, info.submaterials = mats, sub
	local magTris, allTris = 0, 0
	for _, mesh in ipairs(meshes) do
		local mat = mesh.material or "missing"
		mat = sub[string.lower(mat)] or mat
		local tv = mesh.triangles or {}
		for i = 1, #tv - 2, 3 do
			local block = { mat }
			local onMag = part.role == "mag"
			if not onMag and part.role == "gun" then
				-- Whole triangle follows its first vertex's heaviest bone.
				local v = tv[i]
				local hb, hw = nil, -1
				for _, wt in ipairs(v.weights or {}) do
					if wt.weight > hw then hb, hw = wt.bone, wt.weight end
				end
				onMag = hb ~= nil and magOf[hb] == true
			end
			local boneId = onMag and 1 or 0
			for k = 0, 2 do
				local v = tv[i + k]
				local p, n = Vector(0, 0, 0), Vector(0, 0, 0)
				local ws = v.weights
				if ws and #ws > 0 then
					for _, wt in ipairs(ws) do
						local m = skin[wt.bone]
						if m then
							p = p + (m * v.pos) * wt.weight
							n = n + (rot[wt.bone] * (v.normal or vector_up)) * wt.weight
						end
					end
				else
					local m = skin[0]
					p = m and m * v.pos or v.pos
					n = m and rot[0] * (v.normal or vector_up) or (v.normal or vector_up)
				end
				if n:LengthSqr() > 0 then n:Normalize() end
				block[#block + 1] = table.concat({ boneId, num(p.x), num(p.y), num(p.z), num(n.x), num(n.y), num(n.z),
					string.format("%.5f", v.u or 0), string.format("%.5f", 1 - (v.v or 0)) }, " ")
			end
			lines[#lines + 1] = table.concat(block, "\n")
			allTris = allTris + 1
			if onMag then magTris = magTris + 1 end
		end
	end
	info.exported_tris, info.mag_tris = allTris, magTris
end

local function tags_of(ent, inv, all)
	local t = {}
	ent:SetupBones()
	for b = 0, ent:GetBoneCount() - 1 do
		local name = ent:GetBoneName(b)
		local low = string.lower(name or "")
		if all or string.sub(low, 1, 4) == "tag_" or string.find(low, "grip", 1, true) or string.find(low, "ik", 1, true) then
			local bm = ent:GetBoneMatrix(b)
			if bm then
				local m = inv * bm
				t[name] = { pos = vec_json(m:GetTranslation()), ang = ang_json(m:GetAngles()),
					parent = ent:GetBoneParent(b) >= 0 and ent:GetBoneName(ent:GetBoneParent(b)) or nil }
			end
		end
	end
	return t
end

local function export(id, w)
	local e = GB.ById[id]
	if not e then return "not in this client's roster" end
	if not IsValid(w) then return "weapon not valid on the client" end
	if not w.GetAllAttachmentsInUse then return "not an MW base weapon" end
	-- What the preset asked for that the gun doesn't have (bad key, blocked by another part, conversion).
	local missing, have = {}, {}
	for _, a in ipairs(e.atts) do
		local check = (e.swaps and e.swaps[a]) or a
		if not w:HasAttachment(check) then missing[#missing + 1] = a end
	end
	for slot, att in pairs(w:GetAllAttachmentsInUse()) do have[#have + 1] = { slot = slot, cls = att.ClassName } end
	table.sort(have, function(a, b) return a.slot < b.slot end)

	-- The world model as it's drawn when held: its sling offset applied (cl_worldmodel_render).
	local off = w.WorldModelOffsets
	local ob = off and w:LookupBone(off.Bone)
	if ob and ob > 0 then
		w:ManipulateBoneAngles(ob, off.Angles)
		w:ManipulateBonePosition(ob, off.Pos)
	end
	w:InvalidateBoneCache()
	w:SetupBones()
	local frameName = "ValveBiped.Bip01_R_Hand"
	local fb = w:LookupBone(frameName)
	if not fb then fb, frameName = 0, w:GetBoneName(0) end
	local fm = w:GetBoneMatrix(fb)
	if not fm then return "no bone matrix on the world model (is it drawn?)" end
	local inv = fm:GetInverseTR()

	local lines, parts = {}, {}
	local gunInfo = { role = "gun", cls = e.swep }
	dump_model(w, gunInfo, inv, lines, gunInfo)
	gunInfo.bones = tags_of(w, inv, true)
	parts[#parts + 1] = gunInfo
	for slot, att in SortedPairs(w:GetAllAttachmentsInUse()) do
		local m = att.m_TpModel
		if IsValid(m) and not att.DisableWorldModelRender then
			local role = based_on(att, "att_magazine") and "mag" or "part"
			local info = { role = role, cls = att.ClassName, slot = slot, category = att.Category,
				children = #m:GetChildren(), laser = att.Laser ~= nil, reticle = att.Reticle ~= nil }
			if m:GetParent() ~= w and IsValid(m:GetParent()) then info.parent = m:GetParent():GetModel() end
			m:InvalidateBoneCache()
			m:SetupBones()
			dump_model(m, info, inv, lines, info)
			info.tags = tags_of(m, inv, false)
			parts[#parts + 1] = info
		end
	end

	file.CreateDir(OUT)
	local smd = { "version 1", "nodes", '0 "tif_gun" -1', '1 "tif_mag" 0', "end", "skeleton", "time 0",
		"0 0 0 0 0 0 0", "1 0 0 0 0 0 0", "end", "triangles" }
	smd[#smd + 1] = table.concat(lines, "\n")
	smd[#smd + 1] = "end\n"
	file.Write(OUT .. "/" .. id .. "_smd.txt", table.concat(smd, "\n"))
	local total, mag = 0, 0
	for _, p in ipairs(parts) do total, mag = total + (p.exported_tris or 0), mag + (p.mag_tris or 0) end
	local meta = { id = id, swep = e.swep, kind = e.kind, tiers = e.tiers, suppressed = e.suppressed == true,
		tint = e.tint, note = e.note, frame = frameName, atts_asked = e.atts, atts_have = have, missing = missing,
		parts = parts, tris = total, mag_tris = mag, worldmodel = w:GetModel() }
	file.Write(OUT .. "/" .. id .. ".json", util.TableToJSON(meta, true))
	return nil, total, mag, missing
end

-- Sounds only: the built gun's fire sound (suppressor / calibre conversions applied by the MW base), its reverb
-- tails, and its reload foley with times as a share of the reload. Event callbacks are run against a stand-in
-- that records DoSound and ignores everything else.
local function reload_events(anim)
	if not istable(anim) or not istable(anim.Events) then return nil end
	local len = tonumber(anim.Length) or 0
	local out = {}
	for _, ev in ipairs(anim.Events) do
		if isfunction(ev.Callback) then
			local got
			local fake = setmetatable({}, { __index = function(_, k)
				if k == "DoSound" then return function(_, s) got = s end end
				return function() end
			end })
			pcall(ev.Callback, fake)
			if isstring(got) and got ~= "" then out[#out + 1] = { tonumber(ev.Time) or 0, got } end
		end
	end
	if #out == 0 then return nil end
	table.sort(out, function(a, b) return a[1] < b[1] end)
	if len <= 0 then len = out[#out][1] + 0.3 end
	for _, e in ipairs(out) do e[1] = math.Clamp(e[1] / len, 0, 1) end
	return out
end

local function export_sounds(id, w)
	if not IsValid(w) or not w.GetAllAttachmentsInUse then return "not an MW base weapon" end
	local rv = istable(w.Reverb) and istable(w.Reverb.Sounds) and w.Reverb.Sounds or {}
	local anims = istable(w.Animations) and w.Animations or {}
	local s = {
		fire = w.Primary and w.Primary.Sound,
		tailOut = rv.Outside and rv.Outside.Layer, tailIn = rv.Inside and rv.Inside.Layer,
		reload = reload_events(anims.Reload), reloadEmpty = reload_events(anims.Reload_Empty),
	}
	file.CreateDir(OUT)
	file.Write(OUT .. "/" .. id .. "_sounds.json", util.TableToJSON(s, true))
	return nil, s
end

local function guess_kind(w)
	local hold = string.lower(w.GetHoldType and w:GetHoldType() or w.HoldType or "")
	local cat = string.lower(tostring(w.SubCategory or w.Category or "") .. " " .. w:GetClass())

	if hold == "rpg" or string.find(cat, "launcher", 1, true) then return "rpg" end
	if hold == "shotgun" or string.find(cat, "shotgun", 1, true) then return "shotgun" end
	if hold == "pistol" or hold == "revolver" or string.find(cat, "handgun", 1, true) or string.find(cat, "pistol", 1, true) then
		return "pistol"
	end
	if string.find(cat, "machine gun", 1, true) or string.find(cat, "lmg", 1, true) then return "lmg" end
	if hold == "smg" or string.find(cat, "smg", 1, true) or string.find(cat, "submachine", 1, true) then return "smg" end
	if string.find(cat, "marksman", 1, true) or string.find(cat, "sniper", 1, true) then return "dmr" end

	return "rifle"
end

local function held_entry(id, w, kind)
	local atts, suppressed = {}, false

	for _, att in SortedPairs(w:GetAllAttachmentsInUse()) do
		local cls = att.ClassName or ""
		atts[#atts + 1] = cls
		local c = string.lower(cls)

		if string.find(c, "silencer", 1, true) or string.find(c, "suppress", 1, true) then
			suppressed = true
		end
	end

	if kind == "auto" then
		kind = guess_kind(w)
	end

	local e = { id = id, swep = w:GetClass(), kind = kind, tiers = { "held" }, atts = atts,
		suppressed = suppressed or nil, note = "baked from the held gun" }
	GB.ById[id] = e

	local quoted = {}
	for i, a in ipairs(atts) do
		quoted[i] = '"' .. a .. '"'
	end

	local line = string.format('add{ id = "%s", swep = "%s", kind = "%s", tiers = { "held" },%s\n\tatts = { %s },\n\tnote = "baked from the held gun" }',
		id, e.swep, kind, suppressed and " suppressed = true," or "", table.concat(quoted, ", "))
	file.CreateDir(OUT)
	file.Write(OUT .. "/" .. id .. "_roster.txt", line .. "\n")
	return e
end

net.Receive("tif_gunbake", function()
	local id = net.ReadString()
	local w = net.ReadEntity()
	local mode = net.ReadString()
	local heldMode, heldKind = string.match(mode, "^held_(%a+):(%a+)$")

	if heldMode then
		if not (IsValid(w) and w.GetAllAttachmentsInUse) then
			print("[tif_gunbake] " .. id .. ": not an MW base weapon on this client")
			net.Start("tif_gunbake")
			net.SendToServer()
			return
		end

		local e = GB.ById[id]
		if heldMode == "mesh" or not e then
			e = held_entry(id, w, heldKind)
			print(string.format("[tif_gunbake] %s: %s as %s, %d attachments%s (roster line in data/%s/%s_roster.txt)",
				id, e.swep, e.kind, #e.atts, e.suppressed and ", suppressed" or "", OUT, id))
		end

		mode = heldMode == "sounds" and "sounds" or "mesh"
	end

	if mode == "sounds" then
		local ok, err, s = pcall(export_sounds, id, w)
		if not ok or err then
			print("[tif_gunbake] " .. id .. ": sounds: " .. tostring(ok and err or err))
		else
			print(string.format("[tif_gunbake] %s: fire %s, reload %d / empty %d events", id, tostring(s.fire),
				s.reload and #s.reload or 0, s.reloadEmpty and #s.reloadEmpty or 0))
		end
		net.Start("tif_gunbake")
		net.SendToServer()
		return
	end
	local ok, err, total, mag, missing = pcall(export, id, w)
	if not ok then
		print("[tif_gunbake] " .. id .. ": export error: " .. tostring(err))
	elseif err then
		print("[tif_gunbake] " .. id .. ": " .. err)
	else
		local miss = #missing > 0 and ("  NOT APPLIED: " .. table.concat(missing, ", ")) or ""
		print(string.format("[tif_gunbake] %s: %d tris (%d on the mag)%s", id, total, mag, miss))
	end
	net.Start("tif_gunbake")
	net.SendToServer()
end)
