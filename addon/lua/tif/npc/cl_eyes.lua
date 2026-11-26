local TIF = TIF
TIF.Eyes = TIF.Eyes or {}
local E = TIF.Eyes

local cvEyes = GetConVar("tif_eyes") or CreateClientConVar("tif_eyes", "1", true, false, "Soldiers' eyes look at what they're aiming at or facing")

E.RANGE = 900
E.CONE = 40
E.AHEAD = 200
E.HEAD = "ValveBiped.Bip01_Head1"

local offsets = {}
local cosCone = math.cos(math.rad(E.CONE))

local function eyes_offset(f, ent, head)
	local model = f:GetModel() or ""
	local o = offsets[model]
	if o ~= nil then return o or nil end
	o = false
	local idx = f:LookupAttachment("eyes")
	if idx and idx > 0 then
		local a = f:GetAttachment(idx)
		local hm = ent:GetBoneMatrix(head)
		if a and hm then
			local lp, la = WorldToLocal(a.Pos, a.Ang, hm:GetTranslation(), hm:GetAngles())
			o = { pos = lp, ang = la }
		end
	end
	offsets[model] = o
	return o or nil
end

local function in_cone(fwd, want)
	local d = want:Dot(fwd)
	if d >= cosCone then return want end
	local side = want - fwd * d
	if side:LengthSqr() < 1e-6 then return fwd end
	side:Normalize()
	local r = math.rad(E.CONE)
	return fwd * math.cos(r) + side * math.sin(r)
end

function E.Update(ent, st)
	if not cvEyes:GetBool() then return end
	local f = st.follower
	if not IsValid(f) then return end
	if ent:GetPos():DistToSqr(EyePos()) > E.RANGE * E.RANGE then return end
	local head = st.eyeHead
	if head == nil then
		head = ent:LookupBone(E.HEAD) or false
		st.eyeHead = head
	end
	if not head then return end
	local o = eyes_offset(f, ent, head)
	if not o then return end
	local hm = ent:GetBoneMatrix(head)
	if not hm then return end
	local ePos, eAng = LocalToWorld(o.pos, o.ang, hm:GetTranslation(), hm:GetAngles())
	local fwd = eAng:Forward()
	local dir = fwd
	local look = ent:GetNW2Vector("tif_look", vector_origin)
	if look ~= vector_origin then
		local to = look - ePos
		if to:LengthSqr() > 16 then
			to:Normalize()
			dir = in_cone(fwd, to)
		end
	end
	f:SetEyeTarget((WorldToLocal(ePos + dir * E.AHEAD, angle_zero, ePos, eAng)))
	f.tifEyesByBody = true
end
