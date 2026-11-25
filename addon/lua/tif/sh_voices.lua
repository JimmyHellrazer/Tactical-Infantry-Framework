-- Voice packs. Built straight from the sound folders: file names minus their trailing
-- number give the line category (e.g. "fragout3.mp3" -> "fragout").
-- The TFA VOX pack scripts aren't used, so the TFA VOX base isn't needed.

local TIF = TIF
TIF.Voice = TIF.Voice or {}
local V = TIF.Voice

-- TIF event -> categories in each pack, in order of preference.
V.PACKS = {
	mercenary = {
		folder = "vo/mercenary",
		events = {
			contact = { "alert" },
			contact_sniper = { "alertsniper" },
			contact_mg = { "alertmg" },
			contact_rpg = { "alertrpg" },
			reloading = { "reloading", "reloadingcoverme", "reloadingswear" },
			grenade_out = { "fragout" },
			grenade_incoming = { "grenade" },
			man_down = { "mandown" },
			suppressing = { "suppressing" },
			moving = { "moving" },
			cover_me = { "coverme" },
			kill = { "kill", "killswear" },
			pain = { "pain", "painswear", "hit" },
			death = { "death" },
			critical = { "criticalhit" },
			affirmative = { "affirmative" },
			negative = { "negative" },
			retreat = { "retreat" },
			clear = { "clear" },
			backup = { "backup" },
			friendly_fire = { "friendlyfire" },
			swear = { "swear", "hitswear" },
			spawn = { "spawn" },
			advance = { "forwardtaunt" },
		},
	},
	bf3marine = {
		folder = "vo/bf3marine",
		events = {
			contact = { "alert", "attack" },
			contact_sniper = { "alertsniper" },
			contact_mg = { "alerthmg" },
			contact_rpg = { "alertrpg" },
			reloading = { "reloading" },
			no_ammo = { "noammo" },
			grenade_out = { "fragout" },
			grenade_incoming = { "grenade" },
			man_down = { "mandown" },
			suppressing = { "suppressing" },
			kill = { "kill", "niceshot" },
			pain = { "pain", "hit", "hitswear" },
			death = { "death" },
			critical = { "criticalhit" },
			affirmative = { "yes" },
			backup = { "backup", "help" },
			friendly_fire = { "friendlyfire" },
			swear = { "swear" },
		},
	},
	-- Insurgency security force (TFA VOX Insurgency Security Force Improved, Workshop 3144830145).
	-- Optional: only used by factions that list it. "subdown" is "subject down" (a kill).
	securityforce = {
		folder = "vo/securityforce",
		events = {
			contact = { "contact", "target" },
			contact_sniper = { "sniper" },
			contact_mg = { "machinegun" },
			contact_rpg = { "rpg" },
			reloading = { "reloading" },
			no_ammo = { "ammolow" },
			grenade_out = { "frag" },
			grenade_incoming = { "incominggrenade" },
			man_down = { "wounded" },
			suppressing = { "suppressing", "suppress" },
			moving = { "moving" },
			cover_me = { "cover", "coveryou" },
			kill = { "subdown" },
			pain = { "wounded", "suppressed" },
			death = { "pl_deathshout" },
			affirmative = { "affirmative" },
			negative = { "negative" },
			clear = { "clear" },
			backup = { "backup" },
			advance = { "aggressiveinv" },
		},
	},
	securityforcevip = {
		folder = "vo/securityforcevip",
		events = {
			contact = { "contact", "target" },
			contact_mg = { "machinegun" },
			contact_rpg = { "rpg" },
			reloading = { "reloading" },
			no_ammo = { "ammolow" },
			grenade_out = { "frag" },
			grenade_incoming = { "incominggrenade" },
			man_down = { "wounded" },
			suppressing = { "suppress" },
			moving = { "moving", "go" },
			cover_me = { "coverme", "coveryou" },
			kill = { "subdown" },
			pain = { "wounded", "suppressed" },
			death = { "wounded" },
			affirmative = { "affirmative" },
			negative = { "negative" },
			clear = { "clear" },
			backup = { "backup" },
			advance = { "go", "aggressiveinv" },
		},
	},
}

-- Insurgency: Sandstorm packs all share the mercenary pack's line names: reuse its event map.
V.SANDSTORM_EVENTS = V.PACKS.mercenary.events

-- (2026-11-25) Shipped with the base for the starter factions' variety (until now only in TIF Faction Pack, which
-- registers them too): a US special operations pack and two Arabic insurgent packs, all Sandstorm line names.
V.PACKS.specops = V.PACKS.specops or { folder = "vo/specops", events = V.SANDSTORM_EVENTS }
V.PACKS.tif_arab_rebel = V.PACKS.tif_arab_rebel or { folder = "vo/tif_arab_rebel", events = V.SANDSTORM_EVENTS }
V.PACKS.tif_arab_operative = V.PACKS.tif_arab_operative or { folder = "vo/tif_arab_operative", events = V.SANDSTORM_EVENTS }

-- Add a voice pack (content packs: config/sh_packs.lua). def = { folder = "vo/x", events = {...} }.
function V.RegisterPack(id, def)
	V.PACKS[id] = def
	V.Sets[id] = nil
end

-- A faction's voice packs: def.voices (a list; each soldier gets one of them for life) or the
-- single def.voice. Unknown packs are skipped.
function V.FactionPacks(def)
	local out = {}
	for _, p in ipairs(istable(def and def.voices) and def.voices or {}) do
		if V.PACKS[p] then out[#out + 1] = p end
	end
	if #out == 0 and def and V.PACKS[def.voice or ""] then out[1] = def.voice end
	return out
end

-- Events every pack should cover; missing ones are reported by the self-test.
V.CORE_EVENTS = { "contact", "reloading", "grenade_out", "grenade_incoming", "man_down", "suppressing", "kill", "pain", "death" }

V.Sets = V.Sets or {}

local function category_of(fname)
	local base = string.gsub(fname, "%.%w+$", "")
	base = string.gsub(base, "_?%d+$", "")
	return string.lower(base)
end

-- Scan a pack's folder and build event -> { sound paths }.
function V.Build(packId)
	local pack = V.PACKS[packId]
	if not pack then return nil end
	local byCat = {}
	for _, ext in ipairs({ "mp3", "wav", "ogg" }) do
		local found = file.Find("sound/" .. pack.folder .. "/*." .. ext, "GAME")
		for _, f in ipairs(found or {}) do
			local cat = category_of(f)
			byCat[cat] = byCat[cat] or {}
			table.insert(byCat[cat], pack.folder .. "/" .. f)
		end
	end
	local set = { id = packId, categories = byCat, events = {} }
	for event, cats in pairs(pack.events) do
		local list = {}
		for _, c in ipairs(cats) do
			for _, p in ipairs(byCat[c] or {}) do list[#list + 1] = p end
		end
		if #list > 0 then set.events[event] = list end
	end
	V.Sets[packId] = set
	return set
end

function V.Get(packId)
	return V.Sets[packId] or V.Build(packId)
end

-- Pick a line for an event, avoiding the last one played from the same list.
function V.Pick(packId, event)
	local set = V.Get(packId)
	local list = set and set.events[event]
	if not list then return nil end
	if #list == 1 then return list[1] end
	local last = set.last and set.last[event]
	local pick
	for _ = 1, 4 do
		pick = list[math.random(#list)]
		if pick ~= last then break end
	end
	set.last = set.last or {}
	set.last[event] = pick
	return pick
end

if SERVER then
	function V.Play(ent, packId, event, level)
		local snd = V.Pick(packId, event)
		if not snd or not IsValid(ent) then return nil end
		ent:EmitSound(snd, level or 80, math.random(97, 103), 1, CHAN_VOICE)
		return snd
	end

	-- Soldier speech with cooldowns: per soldier, and per faction so a whole group
	-- doesn't shout the same line at once.
	local cvVoice = CreateConVar("tif_voice", "1", FCVAR_ARCHIVE, "Soldier voice lines on/off")
	local factionNext = {}
	local SOLDIER_COOLDOWN, FACTION_COOLDOWN = 2.5, 0.9
	local FORCE = { death = true, pain = true }

	function TIF.Say(npc, event, chance)
		if not cvVoice:GetBool() or not IsValid(npc) then return end
		if chance and math.random() > chance then return end
		local now = CurTime()
		local fac = npc:GetTIFFaction()
		if not FORCE[event] then
			if (npc.tifNextSay or 0) > now or (factionNext[fac] or 0) > now then return end
		elseif event == "pain" and (npc.tifNextSay or 0) > now then
			return
		end
		local def = TIF.Factions[fac]
		-- One voice pack per soldier, picked from the faction's list the first time he speaks.
		if npc.tifVoiceFac ~= fac then
			local packs = V.FactionPacks(def)
			npc.tifVoice = packs[math.random(math.max(1, #packs))]
			npc.tifVoiceFac = fac
		end
		local snd = npc.tifVoice and V.Play(npc, npc.tifVoice, event)
		if snd then
			npc.tifNextSay = now + SOLDIER_COOLDOWN
			factionNext[fac] = now + FACTION_COOLDOWN
		end
	end

	-- (tif_voice_test: the local dev addon since 0.38.11)
end
