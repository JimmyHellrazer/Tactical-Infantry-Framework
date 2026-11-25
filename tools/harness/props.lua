-- Offline (0.38.19): cl_props - the breach sledgehammer follows its clip frame by frame, stowed between uses.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function LerpVector(k, a, b) return Vector(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k) end
function LerpAngle(k, a, b) return Angle(a.p + (b.p - a.p) * k, a.y + (b.y - a.y) * k, a.r + (b.r - a.r) * k) end
-- (bones stay unrotated here: world = bone pos + local pos)
function LocalToWorld(lp, la, bp, ba) return lp + bp, la end
function IsValid(x) return x ~= nil and x ~= false and not (type(x) == "table" and x.removed) end
RENDERGROUP_OPAQUE = 1
math.Clamp = function(v, a, b) return math.min(b, math.max(a, v)) end
-- Matrix: just carries the angles through (the UNTURN product is checked by its effect on yaw)
local MM = {}
MM.__index = MM
function Matrix(rows) return setmetatable({ ang = Angle(), unturn = rows ~= nil }, MM) end
function MM:SetAngles(a) self.ang = a end
function MM:GetAngles() return self.ang end
MM.__mul = function(a, b) local m = Matrix() m.ang = Angle(a.ang.p, a.ang.y + (b.unturn and -90 or 0), a.ang.r) return m end
local made = 0
function ClientsideModel(m)
	made = made + 1
	local e = { model = m, nodraw = false }
	function e:GetModel() return self.model end
	function e:SetNoDraw(b) self.nodraw = b end
	function e:SetPos(p) self.pos = p end
	function e:SetAngles(a) self.ang = a end
	function e:Remove() self.removed = true end
	return e
end
local clips = {}
TIF = { GTG = { Clip = function(n) return clips[n] end } }
assert(loadfile(ROOT .. "tif/npc/cl_props_data.lua"))()
assert(loadfile(ROOT .. "tif/npc/cl_props.lua"))()
local P = TIF.Props
local def = TIF.PropClips.mwq_br_sledge
check(def and #def.frames > 80 and def.stow, "sledge data loaded")
clips.mwq_br_sledge = { name = "sledge" }
local nw = {}
local hand, chest = Vector(100, 0, 50), Vector(0, 0, 60)
local ent = { GetNW2Bool = function(_, k, d) if nw[k] == nil then return d end return nw[k] end, IsDormant = function() return false end,
	LookupBone = function(_, n) return n end,
	GetBoneMatrix = function(_, n)
		local p = n == "ValveBiped.Bip01_R_Hand" and hand or chest
		return { GetTranslation = function() return p end, GetAngles = function() return Angle() end }
	end }
local st = { hostId = "mw_male" }
-- nothing: no prop
P.Update(ent, st, 0)
check(made == 0, "no clip, no flag: no prop made")
-- carried for a hammer breach: stowed on the chest
nw.tif_sledge = true
P.Update(ent, st, 1)
check(made == 1 and st.prop and not st.prop.nodraw, "tif_sledge: the sledge shown")
local s = def.stow
check(math.abs(st.prop.pos.x - (chest.x + s[1])) < 0.01, "stowed: on the chest bone")
check(math.abs(st.prop.ang.y - (s[5] - 90)) < 0.01, "the mesh's studiomdl +90 taken back off (UNTURN)")
-- the clip starts: blends from the chest to the hand over BLEND
st.actClipCur, st.actU = clips.mwq_br_sledge, 0
P.Update(ent, st, 2)
local f1 = def.frames[1]
check(math.abs(st.prop.pos.x - (chest.x + s[1])) < 0.5, "clip start: still where it was (blend)")
P.Update(ent, st, 2 + P.BLEND + 0.01)
check(math.abs(st.prop.pos.x - (hand.x + f1[2])) < 0.01, "after the blend: in the hand, the clip's first frame")
-- mid clip: interpolated between frames on the hand
st.actU = 0.3
P.Update(ent, st, 3)
local n = #def.frames
local x = 0.3 * (n - 1) + 1
local i = math.floor(x)
local a, b = def.frames[i], def.frames[i + 1]
check(math.abs(st.prop.pos.x - (hand.x + a[2] + (b[2] - a[2]) * (x - i))) < 0.01, "mid swing: between its two frames")
-- end: stowed frames are on the chest
st.actU = 1
P.Update(ent, st, 4)
local last = def.frames[n]
check(last[1] == 2 and math.abs(st.prop.pos.x - (chest.x + last[2])) < 0.6, "clip end: on the chest (stowed)")
-- clip over, flag cleared: hidden; dying: hidden
st.actClipCur, st.actU = nil, nil
nw.tif_sledge = false
P.Update(ent, st, 5)
check(st.prop.nodraw, "done: hidden")
nw.tif_sledge = true
st.hideGun = true
P.Update(ent, st, 6)
check(st.prop.nodraw, "dying: hidden")
P.Remove(st)
check(st.prop == nil, "removed with the soldier")
print(string.format("passed %d, failed %d", pass, fail))
