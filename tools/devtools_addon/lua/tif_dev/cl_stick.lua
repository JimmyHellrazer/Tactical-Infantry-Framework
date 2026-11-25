-- Catching the "stick figure" pose (user, 0.38.5: soldiers rarely drawn rigid, arms and legs dead straight along the
-- torso; cause not pinned down yet). Two tools, client side:
--   tif_stickwatch 1   checks every soldier (host body and faction model) and nearby ragdoll a few times a second; the
--                      first time one is in that pose it writes a full snapshot (plus his last ~4 s of animation
--                      history) to data/tif/reports/stick.txt and prints a line. 0 = off.
--   tif_stickwhy       the same snapshot for the soldier / ragdoll you're looking at, now (whether or not it's stiff).
-- The pose test: all four limbs straight (elbows and knees under ~5 deg) and lined up with the spine. MW poses always
-- keep some bend, so normal animation doesn't trigger it.

local TIF = TIF
local Bd = TIF.Body

local REPORT = "tif/reports/stick.txt"
local cvWatch = CreateClientConVar("tif_stickwatch", "0", false, false, "Catch soldiers / ragdolls drawn as a rigid stick figure (writes data/tif/reports/stick.txt)")

local B = {
	pelvis = "ValveBiped.Bip01_Pelvis", spine = "ValveBiped.Bip01_Spine4",
	lu = "ValveBiped.Bip01_L_UpperArm", lf = "ValveBiped.Bip01_L_Forearm", lh = "ValveBiped.Bip01_L_Hand",
	ru = "ValveBiped.Bip01_R_UpperArm", rf = "ValveBiped.Bip01_R_Forearm", rh = "ValveBiped.Bip01_R_Hand",
	lt = "ValveBiped.Bip01_L_Thigh", lc = "ValveBiped.Bip01_L_Calf", lfo = "ValveBiped.Bip01_L_Foot",
	rt = "ValveBiped.Bip01_R_Thigh", rc = "ValveBiped.Bip01_R_Calf", rfo = "ValveBiped.Bip01_R_Foot",
}

local function bpos(e, name)
	local i = e:LookupBone(name)
	local m = i and e:GetBoneMatrix(i)
	return m and m:GetTranslation() or nil
end

-- Stiffness 0..1 (1 = every limb straight and along the spine) and a short description, or nil if bones are missing.
local function stiffness(e)
	if not IsValid(e) then return nil end
	local P = {}
	for k, n in pairs(B) do
		P[k] = bpos(e, n)
		if not P[k] then return nil end
	end
	local spine = (P.spine - P.pelvis):GetNormalized()
	local straight, along = 1, 0
	for _, l in ipairs({ { "lu", "lf", "lh" }, { "ru", "rf", "rh" }, { "lt", "lc", "lfo" }, { "rt", "rc", "rfo" } }) do
		local a, m, b = P[l[1]], P[l[2]], P[l[3]]
		local u1, u2 = (m - a):GetNormalized(), (b - m):GetNormalized()
		straight = math.min(straight, u1:Dot(u2))
		along = along + math.abs((b - a):GetNormalized():Dot(spine))
	end
	along = along / 4
	local horiz = math.abs(spine.z) < 0.5
	local stiff = (straight > 0.996 and along > 0.9) and 1 or 0
	return stiff, string.format("limbs straightness %.3f (1 = dead straight), along spine %.2f, spine %s", straight, along,
		horiz and "horizontal" or "upright")
end

-- Recent animation history per soldier (sampled while watching).
local hist = setmetatable({}, { __mode = "k" })
local function topname(w)
	local best, bw
	for clip, v in pairs(w or {}) do if not bw or v > bw then best, bw = clip, v end end
	return best and string.format("%s %.2f", tostring(best.from or best.seq), bw) or "-"
end
local function sample(ent, st, now)
	local h = hist[ent]
	if not h then h = {} hist[ent] = h end
	h[#h + 1] = string.format("%.2f act '%s' legs %s | ub %s | full %s prone %s knocked %s dying %s%s", now,
		ent:GetNW2String("tif_act", ""), topname(st.legW), topname(st.ubW), tostring(st.fullBody), tostring(st.vbProne),
		tostring(ent:GetNW2Bool("tif_knocked", false)), tostring(ent:GetNW2Bool("tif_dying", false)),
		st.lastErr and (" ERR " .. string.format("%.1f s ago", now - (st.lastErrAt or now))) or "")
	while #h > 16 do table.remove(h, 1) end
end

local function seqname(e, s) return (s and s >= 0) and (e:GetSequenceName(s) or "?") .. "#" .. s or tostring(s) end

local function snapshot(ent, why)
	local L = { "==== " .. os.date("%H:%M:%S") .. "  " .. why .. "  TIF " .. tostring(TIF.Version) }
	local function add(...) L[#L + 1] = table.concat({ ... }) end
	add(tostring(ent), " class ", ent:GetClass(), " model ", tostring(ent:GetModel()), " pos ", tostring(ent:GetPos()))
	if ent:GetClass() == "prop_ragdoll" then
		add("ragdoll: tif_vis '", ent:GetNW2String("tif_vis", ""),
			"' | vb_dress ", tostring(ent:GetNW2Bool("tif_vb_dress", false)), " | parts '", ent:GetNW2String("tif_parts", ""), "'")
		local s, d = stiffness(ent)
		add("pose: ", tostring(s), " ", tostring(d))
		for _, r in ipairs(Bd and Bd.Rags or {}) do
			if r.rag == ent and IsValid(r.ent) then
				local s2, d2 = stiffness(r.ent)
				add("dressing model ", r.ent:GetModel(), " pose: ", tostring(s2), " ", tostring(d2))
			end
		end
		return L
	end
	local st = Bd and Bd.State and Bd.State(ent)
	add("NW: act '", ent:GetNW2String("tif_act", ""), "' t ", string.format("%.2f", CurTime() - ent:GetNW2Float("tif_act_t", CurTime())),
		" ago | host '", ent:GetNW2String("tif_host", ""), "' | knocked ", tostring(ent:GetNW2Bool("tif_knocked", false)),
		" | dying ", tostring(ent:GetNW2Bool("tif_dying", false)), " | prone ", ent:GetNW2Int("tif_prone", 0),
		" | cqb ", tostring(ent:GetNW2Bool("tif_cqb", false)), " | lowready ", tostring(ent:GetNW2Bool("tif_lowready", false)),
		" | surrendered ", tostring(ent:GetNW2Bool("tif_surrendered", false)), " | veh ", tostring(ent:GetNW2Entity("tif_veh", NULL)),
		" | dormant ", tostring(ent:IsDormant()), " | nodraw ", tostring(ent:GetNoDraw()))
	add("main sequence ", seqname(ent, ent:GetSequence()), string.format(" cycle %.2f", ent:GetCycle()))
	for i = 0, 7 do
		local ok, s = pcall(ent.GetLayerSequence, ent, i)
		if ok then
			add(string.format("  layer %d: %s w %.3f cycle %.2f valid %s", i, seqname(ent, s), ent:GetLayerWeight(i), ent:GetLayerCycle(i),
				tostring(ent:IsValidLayer(i))))
		end
	end
	local s, d = stiffness(ent)
	add("host body pose: ", tostring(s), " ", tostring(d))
	if st then
		local f = st.follower
		if IsValid(f) then
			local s2, d2 = stiffness(f)
			add("faction model ", f:GetModel(), " parent ok ", tostring(f:GetParent() == ent), " nodraw ", tostring(f:GetNoDraw()),
				" retarget ", tostring(f.tifMap ~= nil), " | pose: ", tostring(s2), " ", tostring(d2))
		else
			add("faction model: none")
		end
		add("client: fullBody ", tostring(st.fullBody), " vbProne ", tostring(st.vbProne), " slotsOk ", tostring(st.slotsOk),
			" legs ", topname(st.legW), " | ub ", topname(st.ubW), " | jrotW ", string.format("%.2f", st.jrotW or -1))
		if st.lastErr then add("LAST ANIMATION ERROR (", string.format("%.1f", CurTime() - (st.lastErrAt or 0)), " s ago):\n", st.lastErr) end
	end
	add("history (oldest first):")
	for _, h in ipairs(hist[ent] or {}) do add("  ", h) end
	return L
end

local function write(L)
	file.CreateDir("tif/reports")
	file.Append(REPORT, table.concat(L, "\n") .. "\n")
end

concommand.Add("tif_stickwhy", function()
	local ply = LocalPlayer()
	local e = ply:GetEyeTrace().Entity
	-- (a soldier's faction model isn't traceable: the trace hits the soldier; ragdolls are)
	if not IsValid(e) then
		local best, bd = nil, 0.985
		for _, x in ipairs(ents.FindInSphere(ply:GetPos(), 3000)) do
			if x.TIFSoldier or x:GetClass() == "prop_ragdoll" then
				local d = (x:WorldSpaceCenter() - ply:EyePos()):GetNormalized():Dot(ply:GetAimVector())
				if d > bd then best, bd = x, d end
			end
		end
		e = best
	end
	if not IsValid(e) then MsgN("tif_stickwhy: look at a soldier or a ragdoll") return end
	local L = snapshot(e, "tif_stickwhy")
	for _, l in ipairs(L) do MsgN(l) end
	write(L)
	MsgN("(appended to data/", REPORT, ")")
end)

local caught = setmetatable({}, { __mode = "k" })
timer.Create("tif_stickwatch", 0.25, 0, function()
	if not cvWatch:GetBool() or not Bd or not Bd.States then return end
	local now = CurTime()
	for ent, st in pairs(Bd.States) do
		if IsValid(ent) and not ent:IsDormant() then
			sample(ent, st, now)
			if not caught[ent] then
				local s = stiffness(ent)
				local s2 = IsValid(st.follower) and not st.follower:GetNoDraw() and stiffness(st.follower) or 0
				if s == 1 or s2 == 1 then
					caught[ent] = true
					write(snapshot(ent, "tif_stickwatch caught a stiff " .. (s == 1 and "host body" or "faction model")))
					MsgC(Color(255, 160, 60), "[TIF] stick pose caught on ", tostring(ent), " (data/", REPORT, ")\n")
				end
			end
		end
	end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	for _, r in ipairs(ents.FindInSphere(ply:GetPos(), 2500)) do
		if r:GetClass() == "prop_ragdoll" and not caught[r] then
			local s = stiffness(r)
			if s == 1 then
				caught[r] = true
				write(snapshot(r, "tif_stickwatch caught a stiff ragdoll"))
				MsgC(Color(255, 160, 60), "[TIF] stick pose caught on ragdoll ", tostring(r), " (data/", REPORT, ")\n")
			end
		end
	end
end)
