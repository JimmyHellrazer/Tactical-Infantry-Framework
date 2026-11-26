local TIF = TIF

local cvRescue = CreateConVar("tif_rescue", "1", FCVAR_ARCHIVE, "Rescue or remove soldiers that fell under the map (1/0)")
local cvRescueAll = CreateConVar("tif_rescue_all", "0", FCVAR_ARCHIVE,
	"Also remove other NPCs / nextbots that fell under the map (1/0)")

local LOST_THRESHOLD = 3
local UP_20 = Vector(0, 0, 20)
local UP_4 = Vector(0, 0, 4)

local function is_lost(ent)
	local pos = ent:GetPos()
	if ent:WaterLevel() >= 3 then
		local area = navmesh.GetNearestNavArea(pos, false, 3000, false, true)
		return true, IsValid(area) and area:GetCenter().z > pos.z + 40 and area or nil
	end

	if IsValid(navmesh.GetNavArea(pos + UP_20, 120)) then return false end

	local nearArea = navmesh.GetNearestNavArea(pos, false, 400, false, false)
	if IsValid(nearArea) and math.abs(nearArea:GetClosestPointOnArea(pos).z - pos.z) < 120 then
		return false
	end

	local aboveArea = navmesh.GetNearestNavArea(pos, false, 2500, false, false)
	if IsValid(aboveArea) and aboveArea:GetClosestPointOnArea(pos).z > pos.z + 150 then
		return true, aboveArea
	end

	return false
end

local function is_busy(ent)
	return ent.tifDead or ent.tifVeh or ent.tifBoard or ent.tifLeaving or IsValid(ent:GetParent())
end

local function rescue_entity(ent, area)
	ent.tifRescues = (ent.tifRescues or 0) + 1
	if area and ent.tifRescues <= 2 and ent.tifArchId then
		local spot = area:GetClosestPointOnArea(ent:GetPos()) or area:GetCenter()
		spot = TIF.FreeSpot(spot + UP_4, ent)
		if TIF.Action and ent.tifAct then
			TIF.Action.Clear(ent, true)
		end
		ent.tifGlide = nil
		ent:SetPos(spot)
		if ent.loco then
			ent.loco:SetVelocity(vector_origin)
			ent.loco:ClearStuck()
		end
		if TIF.Move and ent.tifMove then
			TIF.Move.Stop(ent)
		end
		TIF.Log("Soldier #", ent:EntIndex(), " fell under the map: put back on the navmesh at ",
			math.floor(spot.x), " ", math.floor(spot.y), " ", math.floor(spot.z))
		return
	end

	TIF.Log((ent.tifArchId and "Soldier #" or (ent:GetClass() .. " #")), ent:EntIndex(), " fell under the map: removed")
	ent:Remove()
end

timer.Create("tif_rescue", 2, 0, function()
	if not cvRescue:GetBool() or navmesh.GetNavAreaCount() == 0 then return end
	local candidates = {}
	local soldiers = TIF.Soldiers or {}
	for i = 1, #soldiers do
		candidates[#candidates + 1] = soldiers[i]
	end

	if cvRescueAll:GetBool() then
		local allEnts = ents.GetAll()
		for i = 1, #allEnts do
			local ent = allEnts[i]
			if (ent:IsNPC() or ent:IsNextBot()) and not ent.tifArchId then
				candidates[#candidates + 1] = ent
			end
		end
	end

	for i = 1, #candidates do
		local ent = candidates[i]
		if IsValid(ent) and not is_busy(ent) then
			local lost, area = is_lost(ent)
			if lost then
				ent.tifLostChecks = (ent.tifLostChecks or 0) + 1
				if ent.tifLostChecks >= LOST_THRESHOLD then
					ent.tifLostChecks = 0
					rescue_entity(ent, ent.tifArchId and area or nil)
				end
			else
				ent.tifLostChecks = 0
			end
		end
	end
end)
