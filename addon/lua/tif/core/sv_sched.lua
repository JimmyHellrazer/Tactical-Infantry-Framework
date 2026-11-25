-- AI scheduler and per-tick budgets.
-- All soldier thinking runs from one Tick hook: round-robin, each soldier at its tier's rate,
-- stopping when the per-tick time budget is spent. Expensive operations (sight traces, path
-- computes) draw from per-tick budgets so a busy fight can't spike a single tick.

local TIF = TIF
local Prof = TIF.Prof

TIF.Soldiers = TIF.Soldiers or {}
TIF.Sched = TIF.Sched or { idx = 1 }
local S = TIF.Sched

local cvBudget = CreateConVar("tif_think_budget_ms", "3", FCVAR_ARCHIVE, "Max milliseconds of AI thinking per server tick")
local cvDisabled = CreateConVar("tif_ai_disabled", "0", 0, "1 = freeze all TIF soldier thinking")
local cvTraces = CreateConVar("tif_trace_budget", "60", FCVAR_ARCHIVE, "Max sight traces per server tick")
local cvPaths = CreateConVar("tif_path_budget", "3", FCVAR_ARCHIVE, "Max path computations per server tick")
local cvCoverTraces = CreateConVar("tif_cover_trace_budget", "150", FCVAR_ARCHIVE, "Max cover-search traces per server tick")
local cvCoverSearches = CreateConVar("tif_cover_search_budget", "2", FCVAR_ARCHIVE, "Max cover searches started per server tick")

-- Frozen by our own switch or GMod's "Disable thinking" (ai_disabled).
local cvGmodDisabled
function TIF.AIDisabled()
	if cvDisabled:GetBool() then return true end
	cvGmodDisabled = cvGmodDisabled or GetConVar("ai_disabled")
	return cvGmodDisabled ~= nil and cvGmodDisabled:GetBool()
end

-- Seconds between thinks per tier. 0 = fighting near a player ... 3 = idle and far away.
S.TIER_INTERVAL = { [0] = 0.1, [1] = 0.25, [2] = 0.75, [3] = 3 }
S.TIER_NAMES = { [0] = "combat-near", [1] = "combat-far/alert", [2] = "routine-near", [3] = "dormant" }

TIF.Budget = TIF.Budget or {}
local B = TIF.Budget
B.left = { trace = 0, path = 0, cover_trace = 0, cover_search = 0 }

function B.Take(kind, n)
	n = n or 1
	if B.left[kind] >= n then
		B.left[kind] = B.left[kind] - n
		Prof.Count(kind, n)
		return true
	end
	Prof.Count(kind .. "_denied", 1)
	return false
end

function TIF.Register(npc)
	local list = TIF.Soldiers
	for _, e in ipairs(list) do if e == npc then return end end
	list[#list + 1] = npc
	npc.tifNextThink = CurTime() + math.Rand(0, 0.3)
	npc.tifTier = 1
end

function TIF.Unregister(npc)
	table.RemoveByValue(TIF.Soldiers, npc)
end

local errorsLogged = 0
local function think_one(npc, now)
	local dt = math.min(1, now - (npc.tifLastThink or now))
	npc.tifLastThink = now
	npc.tifNextThink = now + S.TIER_INTERVAL[npc.tifTier or 2] * math.Rand(0.9, 1.1)
	local t0 = SysTime()
	local ok, err = pcall(npc.TIFThink, npc, dt)
	npc.tifThinkMs = (SysTime() - t0) * 1000
	Prof.Count("thinks", 1)
	if not ok and errorsLogged < 20 then
		errorsLogged = errorsLogged + 1
		TIF.Error("Soldier think error (", tostring(npc), "): ", tostring(err))
	end
end

-- Tiers: decided by distance to the nearest player and awareness.
local function update_tiers()
	local players = player.GetHumans()
	for _, npc in ipairs(TIF.Soldiers) do
		if IsValid(npc) then
			local pos, best = npc:GetPos(), math.huge
			for _, ply in ipairs(players) do
				local d = pos:DistToSqr(ply:GetPos())
				if d < best then best = d end
			end
			local aware = npc.tifAware or 0
			local tier
			if aware == TIF.AWARE.ENGAGED then tier = best < 2500 * 2500 and 0 or 1
			elseif aware > TIF.AWARE.UNAWARE then tier = 1
			else tier = best < 3000 * 3000 and 2 or 3 end
			npc.tifTier = tier
		end
	end
end
timer.Create("tif_sched_tiers", 1, 0, update_tiers)

hook.Add("Tick", "tif_sched", function()
	B.left.trace = cvTraces:GetInt()
	B.left.path = cvPaths:GetInt()
	B.left.cover_trace = cvCoverTraces:GetInt()
	B.left.cover_search = cvCoverSearches:GetInt()
	if TIF.AIDisabled() then return end
	local list = TIF.Soldiers
	local n = #list
	if n == 0 then return end
	Prof.Begin("sched")
	local budget = cvBudget:GetFloat() / 1000
	local t0, now = SysTime(), CurTime()
	for _ = 1, n do
		if S.idx > #list then S.idx = 1 end
		local npc = list[S.idx]
		S.idx = S.idx + 1
		if IsValid(npc) then
			if not npc.tifDead and now >= (npc.tifNextThink or 0) then
				think_one(npc, now)
				if SysTime() - t0 > budget then
					Prof.Count("sched_over_budget", 1)
					break
				end
			end
		else
			table.RemoveByValue(list, npc)
		end
	end
	Prof.End()
end)
