-- Load every faction model and bundled gun model while the map loads. Otherwise each one is read
-- from disk the first time a soldier wearing or carrying it comes into view, which on a big garrison
-- (many models at once) shows up as a stutter. tif_precache 0 turns it off.

local TIF = TIF

local cv = CreateConVar("tif_precache", "1", FCVAR_ARCHIVE, "Load soldier and gun models at map start (fewer stutters when a garrison appears)")

local function precache()
	if not cv:GetBool() then return end
	local done, n = {}, 0
	local function add(m)
		if isstring(m) and m ~= "" and not done[m] then
			done[m] = true
			util.PrecacheModel(m)
			n = n + 1
		end
	end
	-- Content-pack factions (dozens of camo models) only when in use: the players' faction, or one
	-- an addon names through hook "TIF_PrecacheFactions" (tbl) by setting tbl[id] = true (DTW: its sides).
	local want = {}
	local pf = GetConVar("tif_player_faction")
	if pf then want[pf:GetString()] = true end
	hook.Run("TIF_PrecacheFactions", want)
	for id, fac in pairs(TIF.Factions or {}) do
		if not fac.pack or want[id] then
			for _, m in ipairs(fac.models or {}) do add(m) end
			if fac.host and TIF.GTG and TIF.GTG.HostModel then
				add(TIF.GTG.HostModel(fac.host))
				if TIF.GTG.HostFor then add(TIF.GTG.HostModel(TIF.GTG.HostFor(fac))) end
			end
		end
	end
	for _, w in pairs(TIFG and TIFG.Weapons or {}) do add(w.WorldModel) end
	TIF.Log("Precached ", n, " soldier and gun models")
end

hook.Add("InitPostEntity", "tif_precache", precache)
