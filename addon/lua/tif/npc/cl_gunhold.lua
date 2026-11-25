-- How MW19-body soldiers hold and carry their guns (client):
--   Left-hand IK   the left hand goes onto the gun's grip_l point (baked MW guns: the handguard / foregrip),
--                  inside the host's bone build, with a two-bone arm solve that keeps the clip's hand rotation
--                  and elbow direction. Weighted by the clips' own ik_out / ik_in notetracks (reloads, draws,
--                  cover actions let go on their own) and faded out when the clip's hand is far from the gun.
--                  Then the gun's MW19 left-hand finger pose (handguard or foregrip grip).
--   Sling          fallback for actions whose clips don't carry the gun themselves (campaign clips move the gun
--                  bone, j_gun, which cl_body follows): a chest sling (long guns), across the back (launchers) or a
--                  thigh holster (pistols), placed from the torso bones.
--   Slung primary  while the sidearm is out, the primary hangs on the sling.
-- Cost: IK only for soldiers in view within IK_RANGE (a few matrix ops); one extra model only while a pistol is
-- drawn.
TIF.GunHold = TIF.GunHold or {}
local M = TIF.GunHold
local Bd = TIF.Body
local G = TIF.GTG

local cvIK = CreateClientConVar("tif_hand_ik", "1", true, false, "Soldiers' left hand holds the gun's handguard / foregrip (0 = off)")
local IK_RANGE = 1600
local IK_NEAR, IK_FAR = 8, 16  -- clip hand this close to the grip: full IK; this far: none

local B = {
	pelvis = "ValveBiped.Bip01_Pelvis", spine4 = "ValveBiped.Bip01_Spine4", neck = "ValveBiped.Bip01_Neck1",
	lclav = "ValveBiped.Bip01_L_Clavicle", rclav = "ValveBiped.Bip01_R_Clavicle",
	rthigh = "ValveBiped.Bip01_R_Thigh", rcalf = "ValveBiped.Bip01_R_Calf",
	lup = "ValveBiped.Bip01_L_UpperArm", lfore = "ValveBiped.Bip01_L_Forearm", lhand = "ValveBiped.Bip01_L_Hand",
}

local function bpos(ent, name)
	local i = ent:LookupBone(name)
	local m = i and ent:GetBoneMatrix(i)
	return m and m:GetTranslation() or nil
end

-- Torso frame from bone positions (independent of how the skeleton's bone axes are set up).
local function torso(ent)
	local p, s, n = bpos(ent, B.pelvis), bpos(ent, B.spine4), bpos(ent, B.neck)
	local l, r = bpos(ent, B.lclav), bpos(ent, B.rclav)
	if not (p and s and n and l and r) then return nil end
	local up = n - p
	up:Normalize()
	local left = l - r
	left = left - up * left:Dot(up)
	if left:LengthSqr() < 0.01 then return nil end
	left:Normalize()
	local fwd = left:Cross(up)
	return s, fwd, left, up
end

local function frame_pose(gi, grip, barrel, up)
	barrel:Normalize()
	up = up - barrel * up:Dot(barrel)
	if up:LengthSqr() < 0.0001 then return nil end
	up:Normalize()
	local w = Matrix()
	w:SetForward(barrel)
	w:SetRight(-up:Cross(barrel))
	w:SetUp(up)
	local ang = (w * gi.inv):GetAngles()
	local off = Vector(gi.grip)
	off:Rotate(ang)
	return grip - off, ang
end

local function kind_of(st, class)
	if class then return G.WeaponKind(class) end
	return st.pistol and "pistol" or (st.wkind or "rifle")
end

-- Where a slung gun sits (world pos / angles of the gun entity), by weapon kind. src: the body with built bones.
function M.SlingPose(src, st, gi, class)
	if not gi then return nil end
	local kind = kind_of(st, class)
	if kind == "pistol" then
		-- Thigh holster, right side: grip up out of the holster, muzzle down, slide facing forward.
		local t, k = bpos(src, B.rthigh), bpos(src, B.rcalf)
		local c, fwd, left = torso(src)
		if not (t and k and c) then return nil end
		local down = k - t
		down:Normalize()
		local grip = t + down * 4 - left * 5 + fwd * 0.5
		return frame_pose(gi, grip, down + fwd * 0.15, Vector(fwd))
	end
	local c, fwd, left, up = torso(src)
	if not c then return nil end
	if kind == "rpg" then
		-- Across the back, muzzle up past the right shoulder, sights facing out.
		local grip = c - fwd * 9 - up * 8
		return frame_pose(gi, grip, up * 0.8 - left * 0.45 - fwd * 0.1, -fwd)
	end
	-- Long guns on a front sling: muzzle down to his left, stock up toward the right shoulder, the gun's side
	-- against the chest. Bigger guns hang a little lower.
	local drop = math.Clamp(((gi.length or 36) - 30) * 0.15, 0, 4)
	local grip = c + fwd * 9 - up * (5 + drop) - left * 3
	local barrel = -up * 0.8 + left * 0.5 + fwd * 0.12
	return frame_pose(gi, grip, barrel, left * 0.8 + up * 0.55)
end

-- IK weight from a clip's hand notetracks at cycle u (side "left" / "right", default left): 1 on the gun, 0
-- between ik_out_end and ik_in_start, ramps between. Clips without them: 1 (the other checks decide).
local ikTags = { left = {}, right = {} }
local function clip_ik(clip, u, side)
	if not clip or not u then return 1 end
	side = side or "left"
	local cache = ikTags[side]
	local t = cache[clip]
	if t == nil then
		t = {}
		local suf = "_" .. side .. "_hand"
		for _, tag in ipairs(clip.tags or {}) do
			local ev = tag[1] == "MoveEvent" and istable(tag[4]) and tag[4].MoveEvent
			if ev == "ik_out_start" .. suf then t.os = t.os or tag[2]
			elseif ev == "ik_out_end" .. suf then t.oe = t.oe or tag[2]
			elseif ev == "ik_in_start" .. suf then t.is = tag[2]
			elseif ev == "ik_in_end" .. suf then t.ie = tag[2] end
		end
		if not (t.os and t.oe) then t = false end
		cache[clip] = t
	end
	if not t then return 1 end
	if u < t.os then return 1 end
	if u < t.oe then return 1 - (u - t.os) / math.max(0.001, t.oe - t.os) end
	if not t.is or u < t.is then return 0 end
	if t.ie and u < t.ie then return (u - t.is) / math.max(0.001, t.ie - t.is) end
	return 1
end
M.ClipIK = clip_ik

-- Two-bone IK ---------------------------------------------------------------------------------------------------

local function rot_between(a, b)
	local v = a:Cross(b)
	local c = a:Dot(b)
	if c < -0.9999 then
		local axis = math.abs(a.x) < 0.9 and Vector(1, 0, 0) or Vector(0, 1, 0)
		axis = a:Cross(axis)
		axis:Normalize()
		local x, y, z = axis.x, axis.y, axis.z
		return Matrix({ { 2 * x * x - 1, 2 * x * y, 2 * x * z, 0 }, { 2 * y * x, 2 * y * y - 1, 2 * y * z, 0 },
			{ 2 * z * x, 2 * z * y, 2 * z * z - 1, 0 }, { 0, 0, 0, 1 } })
	end
	local k = 1 / (1 + c)
	local x, y, z = v.x, v.y, v.z
	return Matrix({
		{ x * x * k + c, x * y * k - z, x * z * k + y, 0 },
		{ y * x * k + z, y * y * k + c, y * z * k - x, 0 },
		{ z * x * k - y, z * y * k + x, z * z * k + c, 0 },
		{ 0, 0, 0, 1 } })
end

local function tr(v)
	local m = Matrix()
	m:SetTranslation(v)
	return m
end

-- Per model and side: the arm bones and, for every other bone under the upper arm, which of them carries it.
local armOf = { L = {}, R = {} }
local function arm(ent, side)
	side = side or "L"
	local model = ent:GetModel()
	local a = armOf[side][model]
	if a ~= nil then return a or nil end
	local pre = "ValveBiped.Bip01_" .. side .. "_"
	local u, f, h = ent:LookupBone(pre .. "UpperArm"), ent:LookupBone(pre .. "Forearm"), ent:LookupBone(pre .. "Hand")
	a = false
	if u and f and h then
		a = { u = u, f = f, h = h, gov = {} }
		for b = 0, ent:GetBoneCount() - 1 do
			if b ~= u and b ~= f and b ~= h then
				local p, guard = ent:GetBoneParent(b), 0
				while p and p >= 0 and guard < 64 do
					if p == h then a.gov[b] = "h" break end
					if p == f then a.gov[b] = "f" break end
					if p == u then a.gov[b] = "u" break end
					p = ent:GetBoneParent(p)
					guard = guard + 1
				end
			end
		end
	end
	armOf[side][model] = a
	return a or nil
end

-- Two-bone solve of one arm toward hand position T (weight already applied), keeping the elbow on its side.
-- handRot: the hand's new world rotation (a Matrix, translation ignored), or nil to keep the clip's.
local function solve_arm(e, a, T, handRot)
	local mU, mF, mH = e:GetBoneMatrix(a.u), e:GetBoneMatrix(a.f), e:GetBoneMatrix(a.h)
	if not (mU and mF and mH) then return false end
	local A, Bp, C = mU:GetTranslation(), mF:GetTranslation(), mH:GetTranslation()
	local lenA, lenB = A:Distance(Bp), Bp:Distance(C)
	local AT = T - A
	local dist = math.Clamp(AT:Length(), 0.5, lenA + lenB - 0.05)
	local dir = AT:GetNormalized()
	local along = (lenA * lenA - lenB * lenB + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(lenA * lenA - along * along, 0))
	local pole = Bp - A
	pole = pole - dir * pole:Dot(dir)
	if pole:LengthSqr() < 0.0001 then pole = -mU:GetRight() end
	pole:Normalize()
	local B2 = A + dir * along + pole * h
	local T2 = A + dir * dist
	local R1 = rot_between((Bp - A):GetNormalized(), (B2 - A):GetNormalized())
	local newU = tr(A) * R1 * tr(-A) * mU
	local f1 = R1 * (C - Bp)
	local R2 = rot_between(f1:GetNormalized(), (T2 - B2):GetNormalized())
	local newF = tr(B2) * R2 * R1 * tr(-Bp) * mF
	local newH = Matrix(handRot or mH)
	newH:SetTranslation(T2)
	local delta = { u = newU * mU:GetInverseTR(), f = newF * mF:GetInverseTR(), h = newH * mH:GetInverseTR() }
	for b, which in pairs(a.gov) do
		local m = e:GetBoneMatrix(b)
		if m then e:SetBoneMatrix(b, delta[which] * m) end
	end
	e:SetBoneMatrix(a.u, newU)
	e:SetBoneMatrix(a.f, newF)
	e:SetBoneMatrix(a.h, newH)
	return true
end

-- A rotation-only matrix from angles.
local function rot_of(ang)
	local m = Matrix()
	m:SetAngles(ang)
	return m
end

-- MW19 left-hand finger poses (per gun, from mp_fingers_<gun>[_grip]_l via gun_holds.py): local rotations of
-- the L finger bones relative to their parents, parents first. Applied while the hand is on the gun.
local FINGERS = {
	"ValveBiped.Bip01_L_Finger0", "ValveBiped.Bip01_L_Finger01", "ValveBiped.Bip01_L_Finger02",
	"ValveBiped.Bip01_L_Finger1", "ValveBiped.Bip01_L_Finger11", "ValveBiped.Bip01_L_Finger12",
	"ValveBiped.Bip01_L_Finger2", "ValveBiped.Bip01_L_Finger21", "ValveBiped.Bip01_L_Finger22",
	"ValveBiped.Bip01_L_Finger3", "ValveBiped.Bip01_L_Finger31", "ValveBiped.Bip01_L_Finger32",
	"ValveBiped.Bip01_L_Finger4", "ValveBiped.Bip01_L_Finger41", "ValveBiped.Bip01_L_Finger42",
}
local fingerBones = {}
local function finger_bones(e)
	local model = e:GetModel()
	local list = fingerBones[model]
	if list then return list end
	list = {}
	for _, n in ipairs(FINGERS) do
		local b = e:LookupBone(n)
		local p = b and e:GetBoneParent(b)
		if b and p and p >= 0 then list[#list + 1] = { name = n, b = b, p = p } end
	end
	fingerBones[model] = list
	return list
end

local function apply_fingers(e, F)
	local list = finger_bones(e)
	-- Each finger keeps its length (its offset from its parent); only the rotation is the pose's.
	local offs = {}
	for i, f in ipairs(list) do
		local wb, wp = e:GetBoneMatrix(f.b), e:GetBoneMatrix(f.p)
		if wb and wp then offs[i] = (wp:GetInverseTR() * wb):GetTranslation() end
	end
	F._m = F._m or {}
	for i, f in ipairs(list) do
		local r = F[f.name]
		local wp = offs[i] and e:GetBoneMatrix(f.p)
		if r and wp then
			local m = F._m[f.name]
			if not m then
				m = Matrix({ { r[1], r[2], r[3], 0 }, { r[4], r[5], r[6], 0 }, { r[7], r[8], r[9], 0 }, { 0, 0, 0, 1 } })
				F._m[f.name] = m
			end
			local l = Matrix(m)
			l:SetTranslation(offs[i])
			e:SetBoneMatrix(f.b, wp * l)
		end
	end
end
M.ApplyFingers = apply_fingers

local TURN = Matrix({ { 0, -1, 0, 0 }, { 1, 0, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } })
local LH = Matrix({ { 0.8743, 0.1756, 0.4524, 0 }, { 0.4463, -0.6573, -0.6072, 0 }, { 0.1908, 0.7329, -0.6531, 0 },
	{ 0, 0, 0, 1 } })

local R_NEAR, R_FAR = 12, 20  -- right hand: the clip's hand this close to the grip, full IK; this far, none

local function ik_cb(e)
	local st = Bd.State and Bd.State(e)
	if not st or not IsValid(st.gun) then return end
	local la = arm(e, "L")
	local lm = la and e:GetBoneMatrix(la.h)
	local wR0, wL0 = st.ikRW or 0, st.ikW or 0
	if wR0 < 0.01 and wL0 < 0.01 then return end
	local gi = Bd.GunInfo(st.gun:GetModel())
	if not gi then return end
	local pos, ang = Bd.GunPose(st, e, gi)
	if not pos then return end

	-- Right hand onto the grip, as MW19 does: held, the gun's frame is the hand's (baked guns), so the hand goes
	-- to the gun's origin with the gun's rotation.
	if wR0 > 0.01 then
		local a = arm(e, "R")
		local mH = a and e:GetBoneMatrix(a.h)
		if mH then
			local C = mH:GetTranslation()
			local w = wR0 * math.Clamp(1 - (C:Distance(pos) - R_NEAR) / (R_FAR - R_NEAR), 0, 1)
			if w > 0.01 then
				solve_arm(e, a, LerpVector(w, C, pos), rot_of(LerpAngle(w, mH:GetAngles(), ang)))
			end
		end
	end

	-- Left hand onto the handguard (grip_l, MW19's tag_ik_loc_le: the wrist's spot) in the clip's own hand
	-- rotation, or around a vertical foregrip in a rotation built from the gun's axes.
	-- (0.19.3 aimed at the grip with the palm facing back; 0.19.4 turned the clip's hand by a fixed rotation, but
	-- MW19's handguard hand isn't palm-up, so it came out above the grip with the fingers pointing down.)
	local hold = st.gun.tifHold
	local fp = hold and hold.fingerPose or ""
	local vert = gi.gripV and string.find(fp, "grip", 1, true) and not string.find(fp, "ang", 1, true)
	-- (hold.gripL: the left-hand spot for guns whose model has no tag_ik_loc_le, e.g. the RPG; gun_holds.py)
	local hgl = hold and hold.gripL
	local tgt = gi.gripL or gi.gripV or (hgl and Vector(hgl[1], hgl[2], hgl[3]))
	if wL0 < 0.01 or not tgt then return end
	-- Vertical grip, model space (after studiomdl's turn): forward +y, left +x, up -z. grip_v is 2.8 below the rail
	-- mount (the grip runs 0-4.1 below it): the wrist 2 behind and 2 left of the grip's middle, so the palm lies on
	-- its left side and the fingers wrap its front (within ~1 of MW19's tag_ik_loc_le).
	if vert then tgt = gi.gripV + Vector(2.0, -2.05, -0.8) end
	local a = la
	local mH = lm
	if not mH then return end
	local target = LocalToWorld(tgt, angle_zero, pos, ang)
	local C = mH:GetTranslation()
	local w = wL0 * math.Clamp(1 - (C:Distance(target) - IK_NEAR) / (IK_FAR - IK_NEAR), 0, 1)
	if w < 0.01 then return end
	local handRot
	if vert then
		-- ValveBiped left hand (rest pose): +x wrist -> knuckles, index on +z, palm toward -y. On a vertical grip:
		-- knuckles forward and a little round to the right, index on top, palm facing right (onto the grip).
		-- Baked guns after studiomdl's turn: barrel = -Right, top = -Up, the gun's right = -Forward.
		local F, U, Rt = -ang:Right(), -ang:Up(), -ang:Forward()
		local X = F * 0.93 + Rt * 0.36
		X = X - U * X:Dot(U)
		X:Normalize()
		local Y = U:Cross(X)
		local hm = Matrix()
		hm:SetForward(X)
		hm:SetRight(-Y)
		hm:SetUp(U)
		handRot = rot_of(LerpAngle(w, mH:GetAngles(), hm:GetAngles()))
	elseif st.wkind ~= "rpg" then
		-- On the handguard: the hand turned like MW19's handguard hold relative to the gun (LH, the left hand in the
		-- gun's frame over 169 aim / CQB frames, 12 deg spread; scratchpad lhand_rot.py). The clip's own hand is
		-- 30-50 deg off it in calm / alert carries (the retarget's wrist bend): it hung open below the handguard.
		-- Game frames: hand = gun * TURN * LH (TURN = studiomdl's +90 deg about Z, the gun's frame being turned).
		local full = rot_of(ang) * TURN * LH
		full:SetTranslation(vector_origin)
		handRot = rot_of(LerpAngle(w, mH:GetAngles(), full:GetAngles()))
	end	solve_arm(e, a, LerpVector(w, C, target), handRot)
	-- The gun's own MW19 grip for the fingers (handguard, or the foregrip's).
	if hold and hold.fingers and w > 0.5 then apply_fingers(e, hold.fingers) end
end
M.RotBetween = rot_between

-- Every frame before the host's bones are built (cl_body update): IK weight and its bone callback.
function M.Prepare(ent, st, now)
	if not ent.tifIKCb then ent.tifIKCb = ent:AddCallback("BuildBonePositions", ik_cb) end
	local want, wantR = 0, 0
	local gi = IsValid(st.gun) and Bd.GunInfo(st.gun:GetModel())
	local ok = cvIK:GetBool() and gi and not st.hideGun and (st.slingW or 0) < 0.01
		and ent:GetPos():DistToSqr(EyePos()) < IK_RANGE * IK_RANGE
	local hgl = IsValid(st.gun) and st.gun.tifHold and st.gun.tifHold.gripL
	-- (Not while the left hand holds the handheld flashlight: MW19's alert flashlight set, st.handLight.)
	if ok and (gi.gripL or gi.gripV or hgl) and not st.pistol and not st.handLight then
		want = math.min(clip_ik(st.magClip, st.magU), clip_ik(st.actClipCur, st.actU), clip_ik(st.switchClip, st.switchU))
	end
	-- Right hand: only where the gun follows the clip's gun bone (in the hand otherwise: nothing to fix), and
	-- only while the clip has the hand on the grip (st.rikW, cl_body) and its notetracks don't take it off.
	local hold = IsValid(st.gun) and st.gun.tifHold
	if ok and hold and hold.jgun and (st.jgunW or 0) > 0.01 then
		wantR = (st.rikW or 0) * math.min(clip_ik(st.magClip, st.magU, "right"), clip_ik(st.actClipCur, st.actU, "right"),
			clip_ik(st.switchClip, st.switchU, "right"))
	end
	st.ikW = math.Approach(st.ikW or 0, want, FrameTime() * 8)
	st.ikRW = math.Approach(st.ikRW or 0, wantR, FrameTime() * 8)
end

-- After the gun is placed (cl_body update): the primary on the sling while the sidearm is out.
function M.Post(ent, st)
	local primary = ent:GetNW2String("tif_primary", "")
	-- (Only with another gun in hand: captives, the surrendered and the downed have none, and showed a rifle slung.)
	local need = primary ~= "" and (st.wclass or "") ~= "" and primary ~= st.wclass and not st.hideGun
	if not need then
		if IsValid(st.backGun) then st.backGun:Remove() end
		st.backGun, st.backClass = nil, nil
		return
	end
	if st.backClass ~= primary or not IsValid(st.backGun) then
		if IsValid(st.backGun) then st.backGun:Remove() end
		st.backGun, st.backClass = Bd.MakeGun(ent, primary, true), primary
	end
	local g = st.backGun
	if not IsValid(g) then return end
	local pos, ang = M.SlingPose(ent, st, Bd.GunInfo(g:GetModel()), primary)
	if pos then
		g:SetPos(pos)
		g:SetAngles(ang)
		g:InvalidateBoneCache()
	end
end

-- (Dropped guns: the server's ENT:TIFDropWeapon. 0.18.0 dropped a client copy here too, so two guns fell.)
