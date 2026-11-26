local TIF = TIF
local Prof = TIF.Prof

TIF.Soldiers = TIF.Soldiers or {}
TIF.Sched = TIF.Sched or { idx = 1 }
local Sched = TIF.Sched

local cvBudgetMs = CreateConVar("tif_think_budget_ms", "3", FCVAR_ARCHIVE, "Max milliseconds of AI thinking per server tick")
local cvDisabled = CreateConVar("tif_ai_disabled", "0", 0, "1 = freeze all TIF soldier thinking")
local cvTraceBudget = CreateConVar("tif_trace_budget", "60", FCVAR_ARCHIVE, "Max sight traces per server tick")
local cvPathBudget = CreateConVar("tif_path_budget", "3", FCVAR_ARCHIVE, "Max path computations per server tick")
local cvCoverTraceBudget = CreateConVar("tif_cover_trace_budget", "150", FCVAR_ARCHIVE, "Max cover-search traces per server tick")
local cvCoverSearchBudget = CreateConVar("tif_cover_search_budget", "2", FCVAR_ARCHIVE, "Max cover searches started per server tick")

local cvGmodDisabled
function TIF.AIDisabled()
	if cvDisabled:GetBool() then return true end

	cvGmodDisabled = cvGmodDisabled or GetConVar("ai_disabled")
	return cvGmodDisabled ~= nil and cvGmodDisabled:GetBool()
end

Sched.TIER_INTERVAL = { [0] = 0.1, [1] = 0.25, [2] = 0.75, [3] = 3 }
Sched.TIER_NAMES = { [0] = "combat-near", [1] = "combat-far/alert", [2] = "routine-near", [3] = "dormant" }

TIF.Budget = TIF.Budget or {}
local Budget = TIF.Budget
Budget.left = { trace = 0, path = 0, cover_trace = 0, cover_search = 0 }

function Budget.Take(kind, amount)
	amount = amount or 1

	if Budget.left[kind] >= amount then
		Budget.left[kind] = Budget.left[kind] - amount
		Prof.Count(kind, amount)
		return true
	end

	Prof.Count(kind .. "_denied", 1)
	return false
end

local CurTime, SysTime, IsValid = CurTime, SysTime, IsValid
local math_min, math_rand = math.min, math.Rand

function TIF.Register(npc)
	local soldiers = TIF.Soldiers
	for i = 1, #soldiers do
		if soldiers[i] == npc then
			return
		end
	end

	soldiers[#soldiers + 1] = npc
	npc.tifNextThink = CurTime() + math_rand(0, 0.3)
	npc.tifTier = 1
end

function TIF.Unregister(npc)
	table.RemoveByValue(TIF.Soldiers, npc)
end

local errorsLogged = 0
local function think_soldier(npc, now)
	local dt = math_min(1, now - (npc.tifLastThink or now))
	npc.tifLastThink = now
	npc.tifNextThink = now + Sched.TIER_INTERVAL[npc.tifTier or 2] * math_rand(0.9, 1.1)
	local startTime = SysTime()
	local ok, err = pcall(npc.TIFThink, npc, dt)
	npc.tifThinkMs = (SysTime() - startTime) * 1000
	Prof.Count("thinks", 1)

	if not ok and errorsLogged < 20 then
		errorsLogged = errorsLogged + 1
		TIF.Error("Soldier think error (", tostring(npc), "): ", tostring(err))
	end
end

local function update_tiers()
	local players = player.GetHumans()
	local playerCount = #players
	local soldiers = TIF.Soldiers
	local awareEngaged, awareUnaware = TIF.AWARE.ENGAGED, TIF.AWARE.UNAWARE

	for i = 1, #soldiers do
		local npc = soldiers[i]
		if IsValid(npc) then
			local pos, nearestDistSqr = npc:GetPos(), math.huge
			for j = 1, playerCount do
				local distSqr = pos:DistToSqr(players[j]:GetPos())
				if distSqr < nearestDistSqr then
					nearestDistSqr = distSqr
				end
			end

			local aware = npc.tifAware or 0
			local tier

			if aware == awareEngaged then
				tier = nearestDistSqr < 6250000 and 0 or 1
			elseif aware > awareUnaware then
				tier = 1
			else
				tier = nearestDistSqr < 9000000 and 2 or 3
			end

			npc.tifTier = tier
		end
	end
end

timer.Create("tif_sched_tiers", 1, 0, update_tiers)

hook.Add("Tick", "tif_sched", function()
	Budget.left.trace = cvTraceBudget:GetInt()
	Budget.left.path = cvPathBudget:GetInt()
	Budget.left.cover_trace = cvCoverTraceBudget:GetInt()
	Budget.left.cover_search = cvCoverSearchBudget:GetInt()
	if TIF.AIDisabled() then return end

	local soldiers = TIF.Soldiers
	local count = #soldiers
	if count == 0 then return end

	Prof.Begin("sched")
	local budgetSec = cvBudgetMs:GetFloat() / 1000
	local startTime, now = SysTime(), CurTime()

	for _ = 1, count do
		if Sched.idx > #soldiers then
			Sched.idx = 1
		end

		local npc = soldiers[Sched.idx]
		Sched.idx = Sched.idx + 1

		if IsValid(npc) then
			if not npc.tifDead and now >= (npc.tifNextThink or 0) then
				think_soldier(npc, now)

				if SysTime() - startTime > budgetSec then
					Prof.Count("sched_over_budget", 1)
					break
				end
			end
		else
			table.RemoveByValue(soldiers, npc)
		end
	end

	Prof.End()
end)
