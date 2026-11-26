local TIF = TIF
TIF.FactionEditor = TIF.FactionEditor or {}
local FE = TIF.FactionEditor

FE.ROLES = { "default", "leader", "rifleman", "support", "marksman", "assault", "rpg", "breacher" }
FE.DIR = "tif/factions"

TIF.BuiltinFactions = TIF.BuiltinFactions or table.Copy(TIF.Factions)

local function clean_list(t, check)
	local out = {}
	for _, v in ipairs(istable(t) and t or {}) do
		if isstring(v) then
			v = string.Trim(v)
			if v ~= "" and (not check or check(v)) and not table.HasValue(out, v) then out[#out + 1] = v end
		end
		if #out >= 24 then break end
	end
	return out
end

function FE.Sanitize(t)
	if not istable(t) then return nil, "not a table" end
	local id = isstring(t.id) and string.lower(t.id) or ""
	if not string.match(id, "^[a-z][a-z0-9_]*$") or #id > 24 then return nil, "id must be a-z, 0-9, _ (up to 24)" end
	local def = {
		id = id,
		name = isstring(t.name) and string.sub(t.name, 1, 48) or id,
		side = (t.side == "enemy" or t.side == "ally" or t.side == "neutral") and t.side or "enemy",
		models = clean_list(t.models, SERVER and util.IsValidModel or nil),
		voice = isstring(t.voice) and t.voice or "mercenary",

		vehicles = clean_list(istable(t.vehicles) and (function()
			local out = {}
			for i, c in ipairs(t.vehicles) do
				out[i] = (isstring(c) and TIF.Mounted and TIF.Mounted.VehicleClass) and TIF.Mounted.VehicleClass(c) or c
			end
			return out
		end)() or t.vehicles, function(c) return isstring(c) and scripted_ents.GetStored(c) ~= nil end),
		loadouts = {},
		allies = {},
	}

	local packs = TIF.Voice and TIF.Voice.PACKS
	def.voices = clean_list(istable(t.voices) and t.voices or { def.voice }, packs and function(p) return packs[p] ~= nil end or nil)
	if #def.voices == 0 then def.voices = { "mercenary" } end
	def.voice = def.voices[1]

	if istable(t.variants) then
		local vars, ids = {}, {}
		for _, v in ipairs(t.variants) do
			if istable(v) and isstring(v.id) and v.id ~= "" and not ids[v.id] then
				local ms = clean_list(v.models, SERVER and util.IsValidModel or nil)
				if #ms > 0 then
					ids[v.id] = true
					vars[#vars + 1] = { id = string.sub(v.id, 1, 32), name = isstring(v.name) and string.sub(v.name, 1, 48) or v.id, models = ms }
				end
			end
		end
		if #vars > 0 then
			def.variants = vars
			def.models = TIF.FlattenVariants(def)
			local m = t.variantMode
			def.variantMode = (m == "mixed" or (isstring(m) and ids[m])) and m or "squad"
		end
	end

	if istable(t.bodygroups) then
		local bg = {}
		for k, list in pairs(t.bodygroups) do
			if isstring(k) and istable(list) then
				local vals = {}
				for _, x in ipairs(list) do if isnumber(x) and x >= 0 and x < 64 then vals[#vals + 1] = math.floor(x) end end
				if #vals > 0 then bg[string.lower(k)] = vals end
			end
		end
		if next(bg) then def.bodygroups = bg end
	end
	if istable(t.bodyRules) then
		local rules = {}
		for _, r in ipairs(t.bodyRules) do
			if istable(r) and isstring(r[1]) and isstring(r[2]) then
				rules[#rules + 1] = { string.lower(r[1]), string.lower(r[2]) }
			end
		end
		if #rules > 0 then def.bodyRules = rules end
	end
	if t.noBlank == true then def.noBlank = true end

	if istable(t.modular) and istable(t.modular.slots) then
		local mod = { main = isstring(t.modular.main) and t.modular.main or "body", slots = {}, combos = {}, chance = {},
			retarget = t.modular.retarget == true }
		if t.modular.skins == false then mod.skins = false end
		for slot, list in pairs(t.modular.slots) do
			if isstring(slot) and istable(list) then
				mod.slots[slot] = clean_list(list, SERVER and util.IsValidModel or nil)
			end
		end
		for _, c in ipairs(istable(t.modular.combos) and t.modular.combos or {}) do
			if istable(c) then
				local e = {}
				for slot, idx in pairs(c) do
					if slot == "arch" and istable(idx) then

						e.arch = {}
						for _, a in ipairs(idx) do if isstring(a) then e.arch[#e.arch + 1] = a end end
					elseif isstring(slot) and istable(idx) then
						e[slot] = {}
						for _, x in ipairs(idx) do if isnumber(x) then e[slot][#e[slot] + 1] = math.floor(x) end end
					end
				end
				mod.combos[#mod.combos + 1] = e
			end
		end
		for slot, p in pairs(istable(t.modular.chance) and t.modular.chance or {}) do
			if isstring(slot) and isnumber(p) then mod.chance[slot] = math.Clamp(p, 0, 1) end
		end
		if mod.slots[mod.main] and #mod.slots[mod.main] > 0 then
			def.modular = mod
			if #def.models == 0 then def.models = table.Copy(mod.slots[mod.main]) end
			if TIF.Modular and TIF.Modular.Prepare then TIF.Modular.Prepare(def) end
		end
	end
	if #def.models == 0 then return nil, "at least one valid model is needed" end
	local isGun = function(c) return TIF.GTG.WeaponDef(c) ~= nil end
	for _, role in ipairs(FE.ROLES) do
		local l = istable(t.loadouts) and t.loadouts[role]
		if istable(l) then
			local p, s = clean_list(l.primary, isGun), clean_list(l.secondary, isGun)
			if #p > 0 or #s > 0 then
				def.loadouts[role] = { primary = #p > 0 and p or nil, secondary = #s > 0 and s or nil }
			end
		end
	end
	if not def.loadouts.default or not def.loadouts.default.primary then
		return nil, "the default role needs at least one primary weapon"
	end
	def.weapons = def.loadouts.default.primary
	if istable(t.allies) then
		for k, v in pairs(t.allies) do
			local a = isstring(k) and k or v
			if isstring(a) and a ~= id then def.allies[a] = true end
		end
	end
	return def
end

if SERVER then
	util.AddNetworkString("tif_factions")
	util.AddNetworkString("tif_faction_save")
	util.AddNetworkString("tif_faction_delete")

	local function path(id) return FE.DIR .. "/" .. id .. ".json" end

	function FE.Register(def)
		TIF.RegisterFaction(def.id, def)
		def.custom = true
		if TIF.RefreshSpawnList then TIF.RefreshSpawnList() end
	end

	function FE.LoadAll()
		file.CreateDir(FE.DIR)
		for _, f in ipairs(file.Find(FE.DIR .. "/*.json", "DATA")) do
			local def, err = FE.Sanitize(util.JSONToTable(file.Read(FE.DIR .. "/" .. f, "DATA") or "") or {})
			if def then FE.Register(def) else TIF.Warn("Faction file ", f, ": ", err) end
		end
	end

	function FE.Send(to)
		local list = {}
		for id, def in pairs(TIF.Factions) do
			list[id] = { id = id, name = def.name, side = def.side, models = def.models, voice = def.voice,
				voices = TIF.Voice and TIF.Voice.FactionPacks(def) or { def.voice },
				variants = def.variants, variantMode = def.variantMode, pack = def.pack,
				bodygroups = def.bodygroups, bodyRules = def.bodyRules, noBlank = def.noBlank,
				modular = def.modular and { main = def.modular.main, slots = def.modular.slots,
					combos = def.modular.combos, chance = def.modular.chance, retarget = def.modular.retarget,
					skins = def.modular.skins } or nil,
				loadouts = def.loadouts, vehicles = def.vehicles or {}, allies = def.allies or {}, custom = def.custom == true,
				builtin = TIF.BuiltinFactions[id] ~= nil }
		end
		local data = util.Compress(util.TableToJSON(list))
		if not data or #data == 0 then return end
		net.Start("tif_factions")
		net.WriteUInt(#data, 20)
		net.WriteData(data, #data)
		if to then net.Send(to) else net.Broadcast() end
	end

	local function admin(ply) return not IsValid(ply) or ply:IsSuperAdmin() or game.SinglePlayer() or ply:IsListenServerHost() end

	net.Receive("tif_faction_save", function(_, ply)
		if not admin(ply) then return end
		local len = math.min(net.ReadUInt(20), 65536)
		if len <= 0 then return end
		local raw = util.Decompress(net.ReadData(len)) or ""
		local def, err = FE.Sanitize(util.JSONToTable(raw) or {})
		if not def then
			if IsValid(ply) then ply:ChatPrint("[TIF] Faction not saved: " .. err) end
			return
		end
		file.CreateDir(FE.DIR)
		file.Write(path(def.id), util.TableToJSON(def, true))
		FE.Register(def)
		FE.Send()
		if IsValid(ply) then ply:ChatPrint("[TIF] Faction '" .. def.id .. "' saved (" .. #def.models .. " model(s)). New soldiers use it.") end
	end)

	net.Receive("tif_faction_delete", function(_, ply)
		if not admin(ply) then return end
		local id = string.gsub(string.lower(net.ReadString() or ""), "[^%w_%-]", "")
		if id == "" or not file.Exists(path(id), "DATA") then return end
		file.Delete(path(id))
		if TIF.BuiltinFactions[id] then
			TIF.Factions[id] = table.Copy(TIF.BuiltinFactions[id])
			if IsValid(ply) then ply:ChatPrint("[TIF] '" .. id .. "' is back to its defaults") end
		else
			TIF.Factions[id] = nil
			if IsValid(ply) then ply:ChatPrint("[TIF] Faction '" .. id .. "' deleted") end
		end
		if TIF.RefreshSpawnList then TIF.RefreshSpawnList() end
		FE.Send()
	end)

	util.AddNetworkString("tif_ready")
	local lastReady = {}
	net.Receive("tif_ready", function(_, ply)
		if not IsValid(ply) or (lastReady[ply] and CurTime() - lastReady[ply] < 4) then return end
		lastReady[ply] = CurTime()
		FE.Send(ply)
	end)
	hook.Add("PlayerDisconnected", "tif_ready", function(ply) lastReady[ply] = nil end)

	hook.Add("InitPostEntity", "tif_factions", FE.LoadAll)
	if game.GetWorld and IsValid(game.GetWorld()) then timer.Simple(0, function() FE.LoadAll() FE.Send() end) end
end

if CLIENT then
	FE.List = FE.List or {}
	hook.Add("InitPostEntity", "tif_ready", function()
		net.Start("tif_ready")
		net.SendToServer()
	end)
	net.Receive("tif_factions", function()
		local t = util.JSONToTable(util.Decompress(net.ReadData(net.ReadUInt(20))) or "") or {}
		FE.List = t

		for id, def in pairs(t) do
			TIF.Factions[id] = TIF.Factions[id] or {}
			for k, v in pairs(def) do TIF.Factions[id][k] = v end
		end
		for id in pairs(TIF.Factions) do if not t[id] then TIF.Factions[id] = nil end end
		if TIF.RefreshSpawnList then TIF.RefreshSpawnList() end
		if IsValid(FE.Frame) and FE.Frame.Refresh then FE.Frame:Refresh() end
	end)

	local function gtg_weapons()
		local out = {}
		for _, w in ipairs(weapons.GetList()) do
			if istable(w.GTG) and w.ClassName then out[#out + 1] = w.ClassName end
		end
		table.sort(out)
		return out
	end

	local function glide_vehicles()
		local out = {}
		for class, t in pairs(scripted_ents.GetList()) do
			local tt = t.t or t
			if tt.IsGlideVehicle or (isstring(tt.Base) and string.StartWith(tt.Base, "base_glide")) then
				if not string.StartWith(class, "base_") then out[#out + 1] = class end
			end
		end
		table.sort(out)
		return out
	end

	local function split(s)
		local out = {}
		for part in string.gmatch(s or "", "[^,\n]+") do
			part = string.Trim(part)
			if part ~= "" then out[#out + 1] = part end
		end
		return out
	end

	local function list_field(parent, label, choices, value)
		local row = vgui.Create("DPanel", parent)
		row:Dock(TOP)
		row:SetTall(46)
		row:DockMargin(0, 2, 0, 2)
		row.Paint = nil
		local l = vgui.Create("DLabel", row)
		l:SetText(label)
		l:Dock(TOP)
		l:SetDark(true)
		local bottom = vgui.Create("DPanel", row)
		bottom:Dock(FILL)
		bottom.Paint = nil
		local add = vgui.Create("DComboBox", bottom)
		add:Dock(RIGHT)
		add:SetWide(170)
		add:SetValue("+ add")
		for _, c in ipairs(choices) do add:AddChoice(c) end
		local txt = vgui.Create("DTextEntry", bottom)
		txt:Dock(FILL)
		txt:SetValue(table.concat(value or {}, ", "))
		add.OnSelect = function(_, _, v)
			local cur = split(txt:GetValue())
			if not table.HasValue(cur, v) then cur[#cur + 1] = v end
			txt:SetValue(table.concat(cur, ", "))
			add:SetValue("+ add")
		end
		return txt
	end

	function FE.Open()
		if IsValid(FE.Frame) then FE.Frame:Remove() end
		local f = vgui.Create("DFrame")
		FE.Frame = f
		f:SetTitle("Tactical Infantry: factions")
		f:SetSize(math.min(ScrW() - 80, 980), math.min(ScrH() - 80, 720))
		f:Center()
		f:MakePopup()
		local left = vgui.Create("DListView", f)
		left:Dock(LEFT)
		left:SetWide(220)
		left:AddColumn("Faction")
		left:AddColumn("Side")
		local right = vgui.Create("DScrollPanel", f)
		right:Dock(FILL)
		right:DockMargin(8, 0, 0, 0)
		local guns, cars = gtg_weapons(), glide_vehicles()

		local function edit(def)
			right:Clear()
			def = def or { id = "", name = "New faction", side = "enemy", models = {}, voice = "mercenary", loadouts = {}, vehicles = {} }
			local fields = {}
			local function text(label, value)
				local l = right:Add("DLabel")
				l:SetText(label) l:Dock(TOP) l:SetDark(true)
				local t = right:Add("DTextEntry")
				t:Dock(TOP) t:SetValue(value or "")
				return t
			end
			fields.id = text("Id (a-z, 0-9, _): soldiers are tif_soldier with this faction", def.id)
			if def.id ~= "" then fields.id:SetEnabled(false) end
			fields.name = text("Name", def.name)
			local l = right:Add("DLabel") l:SetText("Side (for menus; who fights whom: allies below)") l:Dock(TOP) l:SetDark(true)
			fields.side = right:Add("DComboBox") fields.side:Dock(TOP)
			for _, s in ipairs({ "enemy", "ally", "neutral" }) do fields.side:AddChoice(s, nil, s == def.side) end
			local packIds = {}
			for k in SortedPairs((TIF.Voice and TIF.Voice.PACKS) or { mercenary = true }) do packIds[#packIds + 1] = k end
			fields.voices = list_field(right, "Voice packs (several for variety: each soldier gets one of them)", packIds,
				def.voices or { def.voice })
			if def.variants then

				local lc = right:Add("DLabel") lc:SetText("Camo (" .. #def.variants .. " variants)") lc:Dock(TOP) lc:SetDark(true)
				fields.variantMode = right:Add("DComboBox") fields.variantMode:Dock(TOP)
				local cur = def.variantMode or "squad"
				fields.variantMode:AddChoice("One camo per squad", "squad", cur == "squad")
				fields.variantMode:AddChoice("Mixed (any camo per soldier)", "mixed", cur == "mixed")
				for _, v in ipairs(def.variants) do
					fields.variantMode:AddChoice("Only " .. v.name .. " (" .. #v.models .. ")", v.id, cur == v.id)
				end
			end
			local lm = right:Add("DLabel")
			lm:SetText(def.variants and "Models (from the camo variants; edit them in the pack)" or "Models (one per line; a random one per soldier)")
			lm:Dock(TOP) lm:SetDark(true)
			fields.models = right:Add("DTextEntry")
			fields.models:Dock(TOP) fields.models:SetTall(70) fields.models:SetMultiline(true)
			fields.models:SetValue(table.concat(def.models or {}, "\n"))
			local addPM = right:Add("DButton") addPM:Dock(TOP) addPM:SetText("Add the model I'm wearing")
			addPM.DoClick = function()
				local m = LocalPlayer():GetModel()
				fields.models:SetValue(string.Trim(fields.models:GetValue() .. "\n" .. m))
			end
			fields.loadouts = {}
			for _, role in ipairs(FE.ROLES) do
				local lo = (def.loadouts or {})[role] or {}
				fields.loadouts[role] = {
					primary = list_field(right, role .. ": primary weapons", guns, lo.primary),
					secondary = list_field(right, role .. ": secondary (pistol / small SMG doubles as drive-by gun)", guns, lo.secondary),
				}
			end
			fields.vehicles = list_field(right, "Vehicles (Glide; the campaign's convoys and backup use these)", cars, def.vehicles)
			local allies = {}
			for k in pairs(def.allies or {}) do allies[#allies + 1] = k end
			local facIds = {}
			for k in pairs(TIF.Factions) do facIds[#facIds + 1] = k end
			table.sort(facIds)
			fields.allies = list_field(right, "Allied factions", facIds, allies)

			local save = right:Add("DButton")
			save:Dock(TOP) save:DockMargin(0, 10, 0, 0) save:SetTall(30) save:SetText("Save faction")
			save.DoClick = function()
				local out = { id = fields.id:GetValue(), name = fields.name:GetValue(), side = fields.side:GetSelected() or def.side,
					voices = split(fields.voices:GetValue()), models = split(fields.models:GetValue()), vehicles = split(fields.vehicles:GetValue()),
					allies = split(fields.allies:GetValue()), loadouts = {} }
				out.bodygroups, out.bodyRules, out.noBlank = def.bodygroups, def.bodyRules, def.noBlank
				out.modular = def.modular
				if def.variants then
					out.variants = def.variants
					local _, mode = fields.variantMode:GetSelected()
					out.variantMode = mode or def.variantMode
				end
				for role, fl in pairs(fields.loadouts) do
					out.loadouts[role] = { primary = split(fl.primary:GetValue()), secondary = split(fl.secondary:GetValue()) }
				end
				local data = util.Compress(util.TableToJSON(out))
				net.Start("tif_faction_save")
				net.WriteUInt(#data, 20)
				net.WriteData(data, #data)
				net.SendToServer()
			end
			if def.custom then
				local del = right:Add("DButton")
				del:Dock(TOP) del:DockMargin(0, 4, 0, 0)
				del:SetText(def.builtin and "Reset to the built-in defaults" or "Delete this faction")
				del.DoClick = function()
					net.Start("tif_faction_delete") net.WriteString(def.id) net.SendToServer()
				end
			end
		end

		function f:Refresh()
			left:Clear()
			for id, def in SortedPairs(FE.List) do
				local line = left:AddLine((def.name or id) .. (def.custom and " *" or ""), def.side or "")
				line.def = def
			end
			left:AddLine("+ New faction", "")
		end
		left.OnRowSelected = function(_, _, line) edit(line.def) end
		f:Refresh()
		edit(nil)
	end

	concommand.Add("tif_factions", FE.Open, nil, "Open the faction editor (models, weapons, vehicles)")
	hook.Add("PopulateToolMenu", "tif_factions", function()
		spawnmenu.AddToolMenuOption("Utilities", "Tactical Infantry", "tif_factions_menu", "Factions", "", "", function(panel)
			panel:Help("Make factions or change the built-in ones: models, voices, weapons by role, vehicles.")
			local b = panel:Button("Open the faction editor")
			b.DoClick = FE.Open
		end)
	end)
end
