-- Doors and walking NPCs (2026-11-21). With a destructible-doors mod (e.g. "simple destructible doors remake", which
-- breaks prop_door_rotating on any damage) NPCs walking into a closed door dented and broke it, slow walks included:
-- the push is physics (crush) damage. Here that damage from an NPC / NextBot is dropped and the door opened away from
-- him instead (if it isn't locked). Bullets, blasts and blows still do what the mod says. tif_door_bump_open 0: off.

local cv = CreateConVar("tif_door_bump_open", "1", FCVAR_ARCHIVE, "NPCs walking into a closed door open it instead of damaging it (1/0)")
local SOFT = bit.bor(DMG_CRUSH, DMG_PHYSGUN, DMG_GENERIC)
local HARD = bit.bor(DMG_BULLET, DMG_BLAST, DMG_CLUB, DMG_SLASH, DMG_BUCKSHOT, DMG_BURN, DMG_SONIC)

local function npcish(e) return IsValid(e) and (e:IsNPC() or (e.IsNextBot and e:IsNextBot())) end

hook.Add("EntityTakeDamage", "tif_door_bump", function(ent, dmg)
	if not cv:GetBool() or not IsValid(ent) or ent:GetClass() ~= "prop_door_rotating" then return end
	local t = dmg:GetDamageType()
	if bit.band(t, HARD) ~= 0 then return end
	if t ~= 0 and bit.band(t, SOFT) == 0 then return end
	local by = dmg:GetAttacker()
	if not npcish(by) then by = dmg:GetInflictor() end
	if not npcish(by) then return end
	local ok, locked = pcall(ent.GetInternalVariable, ent, "m_bLocked")
	if not (ok and locked == true) then ent:Fire("OpenAwayFrom", "!activator", 0, by) end
	return true
end)
