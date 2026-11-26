local TIF = TIF
TIF.Voice = TIF.Voice or {}
local V = TIF.Voice

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

V.SANDSTORM_EVENTS = V.PACKS.mercenary.events

V.PACKS.specops = V.PACKS.specops or { folder = "vo/specops", events = V.SANDSTORM_EVENTS }
V.PACKS.tif_arab_rebel = V.PACKS.tif_arab_rebel or { folder = "vo/tif_arab_rebel", events = V.SANDSTORM_EVENTS }
V.PACKS.tif_arab_operative = V.PACKS.tif_arab_operative or { folder = "vo/tif_arab_operative", events = V.SANDSTORM_EVENTS }

function V.RegisterPack(id, def)
	V.PACKS[id] = def
	V.Sets[id] = nil
end

function V.FactionPacks(def)
	local out = {}
	for _, p in ipairs(istable(def and def.voices) and def.voices or {}) do
		if V.PACKS[p] then
			out[#out + 1] = p
		end
	end

	if #out == 0 and def and V.PACKS[def.voice or ""] then
		out[1] = def.voice
	end
	return out
end

V.CORE_EVENTS = { "contact", "reloading", "grenade_out", "grenade_incoming", "man_down", "suppressing", "kill", "pain", "death" }

V.Sets = V.Sets or {}

local function category_of(fname)
	local base = string.gsub(fname, "%.%w+$", "")
	base = string.gsub(base, "_?%d+$", "")
	return string.lower(base)
end

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
			for _, p in ipairs(byCat[c] or {}) do
				list[#list + 1] = p
			end
		end
		if #list > 0 then
			set.events[event] = list
		end
	end

	V.Sets[packId] = set
	return set
end

function V.Get(packId)
	return V.Sets[packId] or V.Build(packId)
end

V.FALLBACK = {
	moving = { "advance", "affirmative" },
	advance = { "moving", "affirmative" },
	cover_me = { "suppressing", "moving" },
	clear = { "affirmative" },
	negative = { "swear" },
	retreat = { "moving", "negative", "backup" },
	attack = { "swear" },
	no_ammo = { "reloading" },
	critical = { "pain" },
	contact_mg = { "contact" },
	contact_sniper = { "contact" },
	contact_rpg = { "contact" },
	friendly_fire = { "swear" },
	spawn = { "affirmative", "advance" },
	backup = { "cover_me", "contact" },
	suppressing = { "cover_me" },
}

function V.Pick(packId, event)
	local set = V.Get(packId)
	local list = set and set.events[event]
	if not list then
		for _, alt in ipairs(V.FALLBACK[event] or {}) do
			list = set and set.events[alt]
			if list then
				event = alt
				break
			end
		end
	end

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
	V.LEVEL = 90
	V.SOLDIER_GAP = 1.8
	V.GROUP_GAP = 0.5

	function V.Play(ent, packId, event, level)
		local snd = V.Pick(packId, event)
		if not snd or not IsValid(ent) then return nil end
		ent:EmitSound(snd, level or V.LEVEL, math.random(97, 103), 1, CHAN_VOICE)
		return snd
	end

	local cvVoice = CreateConVar("tif_voice", "1", FCVAR_ARCHIVE, "Soldier voice lines on/off")
	local groupNext = setmetatable({}, { __mode = "k" })
	local loneNext = {}
	local FORCE = { death = true, pain = true }

	local function group_of(npc)
		local sq = npc.tifSquad
		if sq then return groupNext, sq end
		return loneNext, npc:GetTIFFaction() .. "#" .. math.floor(npc:EntIndex() / 4)
	end

	function TIF.Say(npc, event, chance)
		if not cvVoice:GetBool() or not IsValid(npc) then return end
		if chance and math.random() > chance then return end
		local now = CurTime()
		local fac = npc:GetTIFFaction()
		local gt, gk = group_of(npc)
		if not FORCE[event] then
			if (npc.tifNextSay or 0) > now or (gt[gk] or 0) > now then return end
		elseif event == "pain" and (npc.tifNextSay or 0) > now then
			return
		end
		local def = TIF.Factions[fac]

		if npc.tifVoiceFac ~= fac then
			local packs = V.FactionPacks(def)
			npc.tifVoice = packs[math.random(math.max(1, #packs))]
			npc.tifVoiceFac = fac
		end
		local snd = npc.tifVoice and V.Play(npc, npc.tifVoice, event)
		if snd then
			npc.tifNextSay = now + V.SOLDIER_GAP
			gt[gk] = now + V.GROUP_GAP
			npc.tifSaidAt = now
			local sq = npc.tifSquad
			if sq then
				sq.tifSaidAt = now
			end
		end
		return snd
	end

end
