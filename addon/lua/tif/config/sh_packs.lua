local TIF = TIF

TIF.ContentPacks = TIF.ContentPacks or {}

local function run(name, fn)
	local before = {}
	for id in pairs(TIF.Factions) do
		before[id] = true
	end

	local ok, err = pcall(fn)
	if not ok then
		(TIF.Error or print)("Content pack '", tostring(name), "': ", tostring(err))
		return
	end

	local n = 0
	for id, def in pairs(TIF.Factions) do
		if not before[id] then
			def.pack = name
			n = n + 1
			if TIF.BuiltinFactions then
				TIF.BuiltinFactions[id] = table.Copy(def)
			end
		end
	end

	TIF.ContentPacks[name] = n
	if TIF.Log then
		TIF.Log("Content pack '", name, "': ", n, " faction(s)")
	end

	if TIF.RefreshSpawnList then
		TIF.RefreshSpawnList()
	end
end

function TIF.RegisterContent(name, fn)
	run(name, fn)
end

function TIF.FlattenVariants(def)
	local out, seen = {}, {}
	for _, v in ipairs(def.variants or {}) do
		for _, m in ipairs(v.models or {}) do
			if not seen[m] then
				seen[m] = true out[#out + 1] = m
			end
		end
	end

	return out
end

local function variant_by_id(def, id)
	for _, v in ipairs(def.variants or {}) do
		if v.id == id then return v end
	end
	return nil
end

TIF.VariantOverrides = TIF.VariantOverrides or {}

function TIF.SetVariantOverride(owner, faction, mode)
	if faction == nil then
		TIF.VariantOverrides[owner] = nil
		return
	end

	local t = TIF.VariantOverrides[owner] or {}
	t[faction] = (isstring(mode) and mode ~= "") and mode or nil
	TIF.VariantOverrides[owner] = next(t) and t or nil
end

local function override_for(id)
	for _, t in pairs(TIF.VariantOverrides) do
		if t[id] then return t[id] end
	end
end

function TIF.CamoChoices(id)
	local def = TIF.Factions and TIF.Factions[id]
	if not (def and istable(def.variants) and #def.variants > 0) then
		return {}
	end

	local out = { { "", "Faction default" }, { "squad", "One camo per squad" }, { "mixed", "Mixed (any camo per soldier)" } }
	for _, v in ipairs(def.variants) do
		out[#out + 1] = { v.id, "Only " .. (v.name or v.id) }
	end

	return out
end

local usable, usableRetry, warnedModel = {}, {}, {}
function TIF.VisualUsable(hostId, model)
	local G = TIF.GTG
	if not (G and G.MapFor and G.HostModel) then return true end

	if G.IsVB and G.IsVB(hostId) then return true end
	local host = G.HostModel(hostId or G.DEFAULT_HOST)
	if not host then return true end
	local key = host .. "|" .. string.lower(model)
	local v = usable[key]
	if v == false and CurTime() >= (usableRetry[key] or 0) then
		v = nil
	end

	if v == nil then
		v = G.MapFor(host, model) ~= nil
		usable[key] = v
		if not v then
			usableRetry[key] = CurTime() + 60
		end
	end

	if v then return true end
	local why = G.Skeleton and not G.Skeleton(model) and "its skeleton couldn't be read (missing file or not a ValveBiped skeleton)"
		or "its bones don't match the GTA body"
	return false, why
end

local function usable_of(def, list)
	local out = {}
	for _, m in ipairs(list) do
		local ok, why = TIF.VisualUsable(def.host, m)
		if ok then
			out[#out + 1] = m
		elseif not warnedModel[m] then
			warnedModel[m] = true
			TIF.Warn("Faction ", tostring(def.id or def.name), ": model ", m, " isn't used: ", why)
		end
	end

	return #out > 0 and out or list
end
TIF.UsableVisuals = usable_of

local function check_all(print_ok)
	local bad = 0
	for id, def in SortedPairs(TIF.Factions or {}) do
		for _, m in ipairs(def.models or {}) do
			local ok, why = TIF.VisualUsable(def.host, m)
			if not ok then
				bad = bad + 1
				MsgC(Color(255, 160, 80), "[TIF] ", id, ": ", m, ": ", why, "\n")
			end
		end
	end

	if bad == 0 and print_ok then
		MsgN("[TIF] Every faction model can dress the soldier body.")
	end
	return bad
end

if SERVER then
	hook.Add("InitPostEntity", "tif_visual_check", function()
		timer.Simple(8, function()
			local n = check_all(false)
			if n > 0 then
				TIF.Warn(n, " faction model(s) can't dress the soldier body; soldiers get the faction's other models instead")
			end
		end)
	end)
end

TIF.VisualCheck = check_all

TIF.VARIETY_WINDOW = 8
TIF.VarietyBags = TIF.VarietyBags or {}

function TIF.VarietyPick(facId, key, options)
	local n = options and #options or 0
	if n == 0 then return nil end
	if n == 1 then return options[1] end
	local now = CurTime()
	local bag = TIF.VarietyBags[facId or "?"]
	if not bag or now - bag.t > TIF.VARIETY_WINDOW then
		bag = { counts = {} }
		TIF.VarietyBags[facId or "?"] = bag
	end

	bag.t = now
	local used = bag.counts[key]
	if not used then
		used = {} bag.counts[key] = used
	end

	local best, ties = math.huge, {}
	for _, o in ipairs(options) do
		local c = used[o] or 0
		if c < best then best, ties = c, { o }
		elseif c == best then ties[#ties + 1] = o end
	end

	local pick = ties[math.random(#ties)]
	used[pick] = (used[pick] or 0) + 1
	return pick
end

function TIF.PickVisual(def, ent)
	local vars = def.variants
	if not (istable(vars) and #vars > 0) then
		local list = usable_of(def, def.models)
		return TIF.VarietyPick(def.id, "model", list) or list[math.random(#list)]
	end

	local fid = def.id or (IsValid(ent) and ent.GetTIFFaction and ent:GetTIFFaction()) or nil
	local mode = (IsValid(ent) and ent.tifVariant) or (fid and override_for(fid)) or def.variantMode or "squad"
	local v = variant_by_id(def, mode)
	if not v then
		if mode == "mixed" then
			v = vars[math.random(#vars)]
		else
			local now = CurTime()
			local g = def._variantGroup
			if not g or now > g.untilT or not variant_by_id(def, g.id) then
				g = { id = vars[math.random(#vars)].id, untilT = now + 4 }
				def._variantGroup = g
			end
			v = variant_by_id(def, g.id)
		end
	end

	local models = usable_of(def, v and v.models or def.models)
	if IsValid(ent) then
		ent.tifVariantId = v and v.id or nil
	end

	return TIF.VarietyPick(fid, "model", models) or models[math.random(#models)]
end

for _, e in ipairs(TIF_CONTENT or {}) do
	if istable(e) and isfunction(e[2]) then
		run(e[1], e[2])
	end
end

TIF_CONTENT = nil
