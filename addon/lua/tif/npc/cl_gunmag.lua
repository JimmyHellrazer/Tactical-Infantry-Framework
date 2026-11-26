-- Magazine motion on baked MW guns (models from tif_gunbake carry a second bone, tif_mag). Reloads follow the
-- MW19 clips' own notetracks:
--   drop_clip          the old mag leaves the gun (hidden on it; a copy falls to the ground)
--   attach_clip_left   the new mag is in the left hand (follows the palm)
--   detach_clip_left   the mag is seated (back on the gun)
-- LMG clips mark the box swap with ps_wfoly_lm_reload_npc_out / _in; the RPG's warhead is attach / detach with
-- nothing on the launcher before it. Guns without a tif_mag bone (GTA guns) are left alone.
-- Cost: one bone matrix per reloading gun while it's drawn, plus at most MAX_DROPS falling mags (a trace a frame
-- while they fall, nothing once they land).
TIF.GunMag = TIF.GunMag or {}
local M = TIF.GunMag

local cvDrop = CreateClientConVar("tif_mag_drop", "1", true, false, "Dropped magazines fall from reloading soldiers (0 = off)")
local L_HAND = "ValveBiped.Bip01_L_Hand"
local MAG_BONE, ROOT_BONE = "tif_mag", "tif_gun"
-- Mag centre in the left hand's frame (ValveBiped: x along the fingers, y toward the palm side).
M.PALM = Vector(3.4, 1.2, 0)
local MAX_DROPS, DROP_LIFE, DROP_RANGE = 8, 10, 1500
local TINY = Vector(0.001, 0.001, 0.001)

-- Per clip: the notetrack times (0..1), or false when the clip has no mag swap.
local events = {}
local function clip_events(clip)
	local e = events[clip]
	if e ~= nil then return e or nil end
	local drop, att, det
	for _, t in ipairs(clip.tags or {}) do
		local ev = t[1] == "MoveEvent" and istable(t[4]) and t[4].MoveEvent
		if ev == "drop_clip" then drop = drop or t[2]
		elseif ev == "attach_clip_left" then att = att or t[2]
		elseif ev == "detach_clip_left" then det = det or t[2]
		elseif isstring(ev) and string.find(ev, "_lm_reload_npc_out", 1, true) then att = att or t[2]
		elseif isstring(ev) and string.find(ev, "_lm_reload_npc_in", 1, true) then det = det or t[2] end
	end
	e = (att and det and det > att) and { drop = drop, att = att, det = det } or false
	events[clip] = e
	return e or nil
end

-- The mag bone and the root bone of a gun model, or false.
local boneOf = {}
local function mag_bones(g)
	local model = g:GetModel()
	local b = boneOf[model]
	if b == nil then
		local mb = g:LookupBone(MAG_BONE)
		b = mb and { mag = mb, root = g:LookupBone(ROOT_BONE) or 0 } or false
		boneOf[model] = b
	end
	return b or nil
end

local CopyBone = TIF.CopyBone or function(ent, bone) return bone and ent:GetBoneMatrix(bone) end
local M_ROOT, M_MAG, M_HAND, M_DROP = Matrix(), Matrix(), Matrix(), Matrix()
local lHandOf = {}

local relOf = {}
local function mag_rel(ent, b)
	local model = ent:GetModel()
	local r = relOf[model]
	if r then return r end
	local rm = CopyBone(ent, b.root, M_ROOT)
	local mm = CopyBone(ent, b.mag, M_MAG)
	if not (rm and mm) then return nil end
	r = rm:GetInverseTR() * mm
	relOf[model] = r
	return r
end

local function build_gun(ent)
	local mode = ent.tifMagMode
	if not mode then return end
	local b = mag_bones(ent)
	if not b then return end
	local mm = CopyBone(ent, b.mag, M_MAG)
	if not mm then return end
	if mode == "hide" then
		mm:Scale(TINY)
		ent:SetBoneMatrix(b.mag, mm)
	elseif mode == "hand" and ent.tifMagPalm then
		local rel = mag_rel(ent, b)
		local rm = CopyBone(ent, b.root, M_ROOT)
		if not (rel and rm) then return end
		local m = rm * rel
		m:SetTranslation(ent.tifMagPalm)
		ent:SetBoneMatrix(b.mag, m)
	end
end

-- Falling mags: a copy of the gun model with everything but the mag shrunk away.
local drops = {}
local function build_drop(ent)
	local b = mag_bones(ent)
	local d = ent.tifDrop
	if not (b and d) then return end
	local rm = CopyBone(ent, b.root, M_ROOT)
	if rm then
		rm:Scale(TINY)
		ent:SetBoneMatrix(b.root, rm)
	end
	M_DROP:Identity()
	M_DROP:SetTranslation(d.pos)
	M_DROP:SetAngles(d.ang)
	ent:SetBoneMatrix(b.mag, M_DROP)
end

local function spawn_drop(g, b)
	if not cvDrop:GetBool() then return end
	local mm = CopyBone(g, b.mag, M_MAG)
	if not mm then return end
	local pos = mm:GetTranslation()
	if pos:DistToSqr(EyePos()) > DROP_RANGE * DROP_RANGE then return end
	if #drops >= MAX_DROPS then
		local old = table.remove(drops, 1)
		if IsValid(old.ent) then old.ent:Remove() end
	end
	local e = ClientsideModel(g:GetModel(), RENDERGROUP_OPAQUE)
	if not IsValid(e) then return end
	e:SetPos(pos)
	e:SetSkin(g:GetSkin())
	e.tifDrop = { pos = pos, ang = mm:GetAngles(), vel = -g:GetUp() * 40 + VectorRand() * 15 + g:GetForward() * -10,
		spin = Angle(math.Rand(-300, 300), math.Rand(-200, 200), math.Rand(-300, 300)), t = CurTime(), landed = false }
	e:AddCallback("BuildBonePositions", build_drop)
	drops[#drops + 1] = { ent = e }
end

local traceOut = {}
local trace = { mask = MASK_SOLID_BRUSHONLY, output = traceOut }
local function think_drops(dt, now)
	for i = #drops, 1, -1 do
		local e = drops[i].ent
		local d = IsValid(e) and e.tifDrop
		if not d or now - d.t > DROP_LIFE then
			if IsValid(e) then e:Remove() end
			table.remove(drops, i)
		elseif not d.landed then
			d.vel.z = d.vel.z - 600 * dt
			local to = d.pos + d.vel * dt
			trace.start, trace.endpos = d.pos, to
			local tr = util.TraceLine(trace)
			if tr.Hit then
				d.pos = tr.HitPos + tr.HitNormal * 1.2
				d.ang.p, d.ang.r = 0, 90
				d.landed = true
			else
				d.pos = to
				d.ang.p = d.ang.p + d.spin.p * dt
				d.ang.y = d.ang.y + d.spin.y * dt
				d.ang.r = d.ang.r + d.spin.r * dt
			end
			e:SetPos(d.pos)
			e:InvalidateBoneCache()
		end
	end
end

hook.Add("Think", "tif_gunmag_drops", function()
	if #drops > 0 then think_drops(FrameTime(), CurTime()) end
end)

function M.Update(ent, st)
	local g = st.gun
	if not IsValid(g) then return end
	local b = mag_bones(g)
	if not b then return end
	if not g.tifMagHooked then
		g.tifMagHooked = true
		g:AddCallback("BuildBonePositions", build_gun)
	end
	local clip, u = st.magClip, st.magU
	local e = clip and u and clip_events(clip)
	local mode
	if e then
		local hideFrom = e.drop or (st.wkind == "rpg" and 0) or nil
		if u >= e.att and u < e.det then
			mode = "hand"
		elseif hideFrom and u >= hideFrom and u < e.att then
			mode = "hide"
		end
		if e.drop and u >= e.drop and u < e.att and st.magDropped ~= st.magKey then
			st.magDropped = st.magKey
			g:SetupBones()
			spawn_drop(g, b)
		end
	end
	if mode == "hand" then
		local mdl = ent:GetModel()
		local hb = lHandOf[mdl]
		if hb == nil then
			hb = ent:LookupBone(L_HAND) or false
			lHandOf[mdl] = hb
		end
		local hm = hb and CopyBone(ent, hb, M_HAND)
		if hm then
			g.tifMagPalm = LocalToWorld(M.PALM, angle_zero, hm:GetTranslation(), hm:GetAngles())
		else
			mode = nil
		end
	end
	if mode ~= g.tifMagMode then
		g.tifMagMode = mode
		g:InvalidateBoneCache()
	end
end

-- Gun removed with its soldier: its falling mags stay until they time out.
function M.Clear()
	for _, d in ipairs(drops) do
		if IsValid(d.ent) then d.ent:Remove() end
	end
	drops = {}
end
