TIF.GunHold = TIF.GunHold or {}
local M = TIF.GunHold
local Bd = TIF.Body
local G = TIF.GTG

local cvIK = CreateClientConVar("tif_hand_ik", "1", true, false, "Soldiers' left hand holds the gun's handguard / foregrip (0 = off)")
local IK_RANGE = 1600
local IK_NEAR, IK_FAR = 8, 16

local B = {
	pelvis = "ValveBiped.Bip01_Pelvis", spine4 = "ValveBiped.Bip01_Spine4", neck = "ValveBiped.Bip01_Neck1",
	lclav = "ValveBiped.Bip01_L_Clavicle", rclav = "ValveBiped.Bip01_R_Clavicle",
	rthigh = "ValveBiped.Bip01_R_Thigh", rcalf = "ValveBiped.Bip01_R_Calf",
	lup = "ValveBiped.Bip01_L_UpperArm", lfore = "ValveBiped.Bip01_L_Forearm", lhand = "ValveBiped.Bip01_L_Hand",
}

local CopyBone = TIF.CopyBone or function(ent, bone)
	return bone and ent:GetBoneMatrix(bone)
end

local BONE_TMP = Matrix()
local boneCache = {}
local function bpos(ent, name)
	local mdl = ent:GetModel()
	local c = boneCache[mdl]

	if not c then
		c = {}
		boneCache[mdl] = c
	end

	local i = c[name]
	if i == nil then
		i = ent:LookupBone(name) or false
		c[name] = i
	end

	local m = i and CopyBone(ent, i, BONE_TMP)
	return m and m:GetTranslation() or nil
end

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

M.DISPOSABLE_LIFT = 5
M.BACK_DIST = 6.5

local function kind_of(st, class)
	if class then return G.WeaponKind(class) end

	return st.pistol and "pistol" or (st.wkind or "rifle")
end

function M.SlingPose(src, st, gi, class)
	if not gi then return nil end

	local kind = kind_of(st, class)
	if kind == "pistol" then
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
		local def = class and G.WeaponDef(class)
		local lift = (def and def.disposable) and M.DISPOSABLE_LIFT or 0
		local grip = c - fwd * M.BACK_DIST - up * (8 - lift)
		return frame_pose(gi, grip, up * 0.8 - left * 0.45 - fwd * 0.1, -fwd)
	end

	local drop = math.Clamp(((gi.length or 36) - 30) * 0.15, 0, 4)
	local grip = c + fwd * 9 - up * (5 + drop) - left * 3
	local barrel = -up * 0.8 + left * 0.5 + fwd * 0.12
	return frame_pose(gi, grip, barrel, left * 0.8 + up * 0.55)
end

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
			if ev == "ik_out_start" .. suf then
				t.os = t.os or tag[2]
			elseif ev == "ik_out_end" .. suf then
				t.oe = t.oe or tag[2]
			elseif ev == "ik_in_start" .. suf then
				t.is = tag[2]
			elseif ev == "ik_in_end" .. suf then
				t.ie = tag[2]
			end
		end

		if not (t.os and t.oe) then
			t = false
		end

		cache[clip] = t
	end

	if not t then return 1 end
	if u < t.os then return 1 end
	if u < t.oe then return 1 - (u - t.os) / math.max(0.001, t.oe - t.os) end
	if not t.is or u < t.is then return 0 end

	if t.ie and u < t.ie then
		return (u - t.is) / math.max(0.001, t.ie - t.is)
	end

	return 1
end

M.ClipIK = clip_ik

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
					if p == h then
						a.gov[b] = "h"
						break
					end

					if p == f then
						a.gov[b] = "f"
						break
					end

					if p == u then
						a.gov[b] = "u"
						break
					end

					p = ent:GetBoneParent(p)
					guard = guard + 1
				end
			end
		end
	end

	armOf[side][model] = a
	return a or nil
end

local M_U, M_F, M_H, M_G = Matrix(), Matrix(), Matrix(), Matrix()
local DELTA_BUF = {}

local function solve_arm(e, a, T, handRot)
	local mU = CopyBone(e, a.u, M_U)
	local mF = CopyBone(e, a.f, M_F)
	local mH = CopyBone(e, a.h, M_H)
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

	if pole:LengthSqr() < 0.0001 then
		pole = -mU:GetRight()
	end

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
	DELTA_BUF.u, DELTA_BUF.f, DELTA_BUF.h = newU * mU:GetInverseTR(), newF * mF:GetInverseTR(), newH * mH:GetInverseTR()

	for b, which in pairs(a.gov) do
		local m = CopyBone(e, b, M_G)
		if m then
			e:SetBoneMatrix(b, DELTA_BUF[which] * m)
		end
	end

	e:SetBoneMatrix(a.u, newU)
	e:SetBoneMatrix(a.f, newF)
	e:SetBoneMatrix(a.h, newH)
	return true
end

local function rot_of(ang)
	local m = Matrix()
	m:SetAngles(ang)
	return m
end

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

		if b and p and p >= 0 then
			list[#list + 1] = { name = n, b = b, p = p }
		end
	end

	fingerBones[model] = list
	return list
end

local FINGER_OFFS = {}
local F_WB, F_WP = Matrix(), Matrix()

local function apply_fingers(e, F)
	local list = finger_bones(e)
	local n = #list

	for i = 1, n do
		local f = list[i]
		local wb = CopyBone(e, f.b, F_WB)
		local wp = CopyBone(e, f.p, F_WP)
		FINGER_OFFS[i] = (wb and wp) and (wp:GetInverseTR() * wb):GetTranslation() or false
	end

	F._m = F._m or {}

	for i = 1, n do
		local f = list[i]
		local r = F[f.name]
		local off = FINGER_OFFS[i]
		local wp = off and CopyBone(e, f.p, F_WP)

		if r and wp then
			local m = F._m[f.name]
			if not m then
				m = Matrix({ { r[1], r[2], r[3], 0 }, { r[4], r[5], r[6], 0 }, { r[7], r[8], r[9], 0 }, { 0, 0, 0, 1 } })
				F._m[f.name] = m
			end

			m:SetTranslation(off)
			e:SetBoneMatrix(f.b, wp * m)
		end
	end
end

M.ApplyFingers = apply_fingers

local TURN = Matrix({ { 0, -1, 0, 0 }, { 1, 0, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } })
local LH = Matrix({ { 0.8743, 0.1756, 0.4524, 0 }, { 0.4463, -0.6573, -0.6072, 0 }, { 0.1908, 0.7329, -0.6531, 0 },
	{ 0, 0, 0, 1 } })
local TURN_LH = TURN * LH
local VERT_OFF = Vector(2.0, -2.05, -0.8)

M.FINGER_RANGE = 700
local R_NEAR, R_FAR = 12, 20
local IK_LM, IK_RM = Matrix(), Matrix()

local function ik_solve(e)
	local st = Bd.State and Bd.State(e)
	if not st or not IsValid(st.gun) or st.writeFrame ~= FrameNumber() then
		return
	end

	local la = arm(e, "L")
	local lm = la and CopyBone(e, la.h, IK_LM)
	local wR0, wL0 = st.ikRW or 0, st.ikW or 0
	if wR0 < 0.01 and wL0 < 0.01 then return end

	local gi = Bd.GunInfo(st.gun:GetModel())
	if not gi then return end

	local pos, ang = Bd.GunPose(st, e, gi)
	if not pos then return end

	if wR0 > 0.01 then
		local a = arm(e, "R")
		local mH = a and CopyBone(e, a.h, IK_RM)

		if mH then
			local C = mH:GetTranslation()
			local w = wR0 * math.Clamp(1 - (C:Distance(pos) - R_NEAR) / (R_FAR - R_NEAR), 0, 1)

			if w > 0.01 then
				solve_arm(e, a, LerpVector(w, C, pos), rot_of(LerpAngle(w, mH:GetAngles(), ang)))
			end
		end
	end

	local hold = st.gun.tifHold
	local fp = hold and hold.fingerPose or ""
	local vert = gi.gripV and string.find(fp, "grip", 1, true) and not string.find(fp, "ang", 1, true)
	local hgl = hold and hold.gripL
	local tgt = gi.gripL or gi.gripV or (hgl and Vector(hgl[1], hgl[2], hgl[3]))
	if wL0 < 0.01 or not tgt then return end

	if vert then
		tgt = gi.gripV + VERT_OFF
	end

	local a = la
	local mH = lm
	if not mH then return end

	local target = LocalToWorld(tgt, angle_zero, pos, ang)
	local C = mH:GetTranslation()
	local w = wL0 * math.Clamp(1 - (C:Distance(target) - IK_NEAR) / (IK_FAR - IK_NEAR), 0, 1)
	if w < 0.01 then return end

	local handRot
	if vert then
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
		local full = rot_of(ang) * TURN_LH
		full:SetTranslation(vector_origin)
		handRot = rot_of(LerpAngle(w, mH:GetAngles(), full:GetAngles()))
	end

	solve_arm(e, a, LerpVector(w, C, target), handRot)

	if hold and hold.fingers and w > 0.5 and e:GetPos():DistToSqr(EyePos()) < M.FINGER_RANGE * M.FINGER_RANGE then
		apply_fingers(e, hold.fingers)
	end
end

M.RotBetween = rot_between
M.SolveTwoBone = solve_arm

local function ik_cb(e)
	local t0 = SysTime()
	ik_solve(e)
	local Prof = TIF.Prof

	if Prof then
		Prof.Count("cl_ik_us", (SysTime() - t0) * 1e6)
		Prof.Count("cl_ik_n", 1)
	end
end

function M.Prepare(ent, st, now)
	if not ent.tifIKCb then
		ent.tifIKCb = ent:AddCallback("BuildBonePositions", ik_cb)
	end

	local want, wantR = 0, 0
	local gi = IsValid(st.gun) and Bd.GunInfo(st.gun:GetModel())
	local ok = cvIK:GetBool() and gi and not st.hideGun and (st.slingW or 0) < 0.01
		and ent:GetPos():DistToSqr(EyePos()) < IK_RANGE * IK_RANGE
	local hgl = IsValid(st.gun) and st.gun.tifHold and st.gun.tifHold.gripL

	if ok and (gi.gripL or gi.gripV or hgl) and not st.pistol and not st.handLight then
		want = math.min(clip_ik(st.magClip, st.magU), clip_ik(st.actClipCur, st.actU), clip_ik(st.switchClip, st.switchU))
	end

	local hold = IsValid(st.gun) and st.gun.tifHold
	if ok and hold and hold.jgun and (st.jgunW or 0) > 0.01 then
		wantR = (st.rikW or 0) * math.min(clip_ik(st.magClip, st.magU, "right"), clip_ik(st.actClipCur, st.actU, "right"),
			clip_ik(st.switchClip, st.switchU, "right"))
	end

	st.ikW = math.Approach(st.ikW or 0, want, FrameTime() * 8)
	st.ikRW = math.Approach(st.ikRW or 0, wantR, FrameTime() * 8)
end

local function post_launcher(ent, st)
	local cls = ent:GetNW2String("tif_launcher", "")
	local need = cls ~= "" and cls ~= (st.wclass or "") and not st.hideGun and not st.slung

	if not need then
		if IsValid(st.launcherGun) then
			st.launcherGun:Remove()
		end

		st.launcherGun, st.launcherClass = nil, nil
		return
	end

	if st.launcherClass ~= cls or not IsValid(st.launcherGun) then
		if IsValid(st.launcherGun) then
			st.launcherGun:Remove()
		end

		st.launcherGun, st.launcherClass = Bd.MakeGun(ent, cls, true), cls
	end

	local g = st.launcherGun
	if not IsValid(g) then return end

	local pos, ang = M.SlingPose(ent, st, Bd.GunInfo(g:GetModel()), cls)
	if pos then
		g:SetPos(pos)
		g:SetAngles(ang)
		g:InvalidateBoneCache()
	end
end

function M.Post(ent, st)
	post_launcher(ent, st)
	local primary = ent:GetNW2String("tif_primary", "")

	local need = primary ~= "" and (st.wclass or "") ~= "" and primary ~= st.wclass and not st.hideGun
	if not need then
		if IsValid(st.backGun) then
			st.backGun:Remove()
		end

		st.backGun, st.backClass = nil, nil
		return
	end

	if st.backClass ~= primary or not IsValid(st.backGun) then
		if IsValid(st.backGun) then
			st.backGun:Remove()
		end

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
