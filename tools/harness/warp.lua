-- Offline check of root-path warping in TIF.Action (npc/sv_action.lua): an arrival follows its own curve and
-- ends exactly on the target. ROOT, CLIPS set by the runner.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end return Vector(a.x * b, a.y * b, a.z * b) end
function V:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function V:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function V:Normalize() local l = math.sqrt(self:LengthSqr()) if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
math.AngleDifference = function(a, b) return (a - b + 180) % 360 - 180 end
local now = 10
function CurTime() return now end
util = { TraceHull = function(t) return { HitPos = t.endpos } end }
MASK_NPCSOLID_BRUSHONLY = 0
TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
-- The real curve sampler from TIF's GTA layer, simplified (every 3 frames, linear).
local function curve_at(clip, frame, axis)
	local c = clip.curve
	local n = #c / 3
	local fi = frame / 3
	if fi <= 0 then return c[axis] end
	if fi >= n - 1 then return c[(n - 1) * 3 + axis] end
	local i = math.floor(fi)
	return c[i * 3 + axis] + (c[i * 3 + 3 + axis] - c[i * 3 + axis]) * (fi - i)
end
TIF = { Factions = { army = { host = "gta" } }, Warn = print,
	GTG = { DEFAULT_HOST = "gta", Clip = function(n, id) return id == "mw_male" and clips[n] or nil end, ClipCurve = curve_at } }
local fn, err = loadfile(ROOT .. "tif/npc/sv_action.lua")
if not fn then error(err) end
fn()
local Act = TIF.Action
local npc = { tifHostId = "mw_male", tifHomeHost = "mw_male", pos = Vector(100, 50, 0), yaw = 30, nw = {} }
function npc:GetTIFFaction() return "army" end
function npc:GetPos() return self.pos end
function npc:SetPos(p) self.pos = p end
function npc:GetAngles() return Angle(0, self.yaw, 0) end
function npc:SetAngles(a) self.yaw = a.y end
function npc:SetNW2String() end
function npc:SetNW2Float() end

local name = "mwc_rs_arr_run_l_9"
local clip = clips[name]
check(clip and (clip.move[1] ~= 0 or clip.move[2] ~= 0 or clip.move[3] ~= 0), "arrival has its own root motion: " .. tostring(clip and table.concat(clip.move, ",")))
local target = { pos = Vector(130, 120, 0), yaw = 90 }
local d = Act.Play(npc, name, { root = true, to = target })
-- Halfway: on the clip's own path plus half the (smoothed) correction, not on the straight line.
local start = Vector(100, 50, 0)
now = now + d * 0.5
Act.Tick(npc, now)
local mid = npc.pos
local lx, ly = target.pos.x - start.x, target.pos.y - start.y
local cross = math.abs((mid.x - start.x) * ly - (mid.y - start.y) * lx) / math.sqrt(lx * lx + ly * ly)
check(cross > 1, string.format("halfway it's off the straight line (follows the clip's curve): %.1f units", cross))
now = now + d * 0.6
Act.Tick(npc, now)
check(math.abs(npc.pos.x - target.pos.x) < 0.01 and math.abs(npc.pos.y - target.pos.y) < 0.01, string.format("ends exactly on the node (%.2f, %.2f)", npc.pos.x, npc.pos.y))
check(math.abs(math.AngleDifference(npc.yaw, target.yaw)) < 0.01, "ends facing the node's yaw: " .. npc.yaw)
-- 2026-11-21: root motion that meets a wall slides along it (a clip clipping a jamb used to hang there)
do
	util.TraceHull = function(t)
		if t.endpos.x <= 188 then return { HitPos = t.endpos, Hit = false } end
		if t.start.x >= 188 then return { HitPos = t.start, Hit = true, StartSolid = false, HitNormal = Vector(-1, 0, 0) } end
		local f = (188 - t.start.x) / (t.endpos.x - t.start.x)
		return { HitPos = Vector(188, t.start.y + (t.endpos.y - t.start.y) * f, t.start.z + (t.endpos.z - t.start.z) * f),
			Hit = true, StartSolid = false, HitNormal = Vector(-1, 0, 0) }
	end
	local n2 = { tifHostId = "mw_male", tifHomeHost = "mw_male", pos = Vector(170, 0, 0), yaw = 45, nw = {} }
	for k, v in pairs(npc) do if type(v) == "function" then n2[k] = v end end
	local d2 = Act.Play(n2, name, { root = true })
	local y0 = n2.pos.y
	for k = 1, 30 do now = now + d2 / 30 Act.Tick(n2, now) end
	check(n2.pos.x <= 188.01, "kept out of the wall (x " .. string.format("%.1f", n2.pos.x) .. ")")
	check(math.abs(n2.pos.y - y0) > 34, "slid along it instead of stopping dead (moved " .. string.format("%.1f", n2.pos.y - y0) .. " along)")
end
print(string.format("passed %d, failed %d", pass, fail))
