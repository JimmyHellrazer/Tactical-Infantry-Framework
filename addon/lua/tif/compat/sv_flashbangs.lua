-- Flashbangs from other addons on TIF soldiers. They're NextBots, and most flashbang addons only stun
-- ent:IsNPC() entities, so TIF soldiers never noticed them (no blinding, no MW19 flash reaction).
--   TIF.FlashAt(pos, radius, attacker): every TIF soldier within radius with line of sight to the bang is
--   stunned (TIF.API.Stun: blind, no shooting, shaken; the MW19 body plays its flash reaction), longer
--   close up and when looking at it (2-7 s).
--   SandSWEP throwables (sandswep_flashbang): its Detonate is wrapped once its entity is registered; SandSWEP
--   itself is not edited.

local TIF = TIF

TIF.FLASH = { min = 2, max = 7, behind = 0.45 }

-- (0.38.21, user: "way lower the effect of friendly flashes, like range and duration ... have maybe a debug option for
-- no effect") A flash on the thrower's own side (him, his allies, allied players) reaches tif_flash_friendly of its
-- range and lasts that share as long; 0: friendly flashes do nothing to them. Enemies get the full flash.
local cvFriendly = CreateConVar("tif_flash_friendly", "0.3", FCVAR_ARCHIVE,
	"Friendly flashbangs on the thrower's own side: share of range and duration (1 full, 0 no effect)")
-- The scale (range and duration) of a flash thrown by `thrower` on `ent`: 1 for enemies / unknown throwers.
function TIF.FlashScale(thrower, ent)
	if not (IsValid(thrower) and IsValid(ent)) then return 1 end
	if thrower ~= ent and TIF.Relation(thrower, ent) ~= TIF.REL_ALLY then return 1 end
	return math.Clamp(cvFriendly:GetFloat(), 0, 1)
end
local function thrower_of(inflictor)
	if not IsValid(inflictor) then return nil end
	local o = inflictor.GetOwner and inflictor:GetOwner()
	return IsValid(o) and o or nil
end

local function los(a, b, filter)
	local tr = util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID - CONTENTS_GRATE, filter = filter })
	return not tr.Hit or tr.Fraction > 0.98
end

function TIF.FlashAt(pos, radius, inflictor, thrower)
	if not TIF.API or not TIF.API.Stun then return 0 end
	thrower = thrower or thrower_of(inflictor)
	local n = 0
	for _, npc in ipairs(TIF.Soldiers or {}) do
		if IsValid(npc) and not npc.tifDead then
			-- (friendly: a smaller reach and a shorter stun, none at 0)
			local s = TIF.FlashScale(thrower, npc)
			local r = radius * s
			local eye = (TIF.EyeOf and TIF.EyeOf(npc)) or (npc:GetPos() + Vector(0, 0, 60))
			local d = eye:Distance(pos)
			if s > 0 and d < r and los(pos, eye, { inflictor, npc }) then
				local to = (pos - eye):GetNormalized()
				local facing = npc:GetForward():Dot(to)
				local k = (1 - d / r) * Lerp((facing + 1) / 2, TIF.FLASH.behind, 1)
				local secs = Lerp(math.Clamp(k, 0, 1), TIF.FLASH.min, TIF.FLASH.max)
				-- Right next to it: blinded whichever way he faced.
				if d < r * 0.15 then secs = math.max(secs, TIF.FLASH.max * 0.8) end
				TIF.API.Stun(npc, secs * s)
				n = n + 1
			end
		end
	end
	return n
end

-- SandSWEP: wrap the flashbang's Detonate (once).
local function hook_sandswep()
	local t = scripted_ents.GetStored and scripted_ents.GetStored("sandswep_flashbang")
	t = t and t.t
	if not t or t.tifWrapped or not t.Detonate then return end
	t.tifWrapped = true
	local orig = t.Detonate
	t.Detonate = function(self, ...)
		local done = self.Done
		local r = orig(self, ...)
		if not done then
			local f = (self.Cfg and self.Cfg.Flash) or self.FlashDefaults or {}
			TIF.FlashAt(self:GetPos() + Vector(0, 0, 4), math.max(f.Radius or 787, f.ShockRadius or 787), self)
		end
		return r
	end
end
hook.Add("InitPostEntity", "tif_flashbangs", hook_sandswep)
hook.Add("OnReloaded", "tif_flashbangs", hook_sandswep)
timer.Simple(0, hook_sandswep)
