local TIF = TIF

local cvOn = CreateConVar("tif_rescue", "1", FCVAR_ARCHIVE, "Rescue or remove soldiers that fell under the map (1/0)")
local cvAll = CreateConVar("tif_rescue_all", "0", FCVAR_ARCHIVE,
	"Also remove other NPCs / nextbots that fell under the map (1/0)")

local CHECKS = 3

local function lost(ent)
	local pos = ent:GetPos()
	if ent:WaterLevel() >= 3 then
		local a = navmesh.GetNearestNavArea(pos, false, 3000, false, true)
		return true, IsValid(a) and a:GetCenter().z > pos.z + 40 and a or nil
	end

	if IsValid(navmesh.GetNavArea(pos + Vector(0, 0, 20), 120)) then return false end

	local near = navmesh.GetNearestNavArea(pos, false, 400, false, false)
	if IsValid(near) and math.abs(near:GetClosestPointOnArea(pos).z - pos.z) < 120 then return false end

	local up = navmesh.GetNearestNavArea(pos, false, 2500, false, false)
	if IsValid(up) and up:GetClosestPointOnArea(pos).z > pos.z + 150 then return true, up end
	return false
end

local function busy(ent)
	return ent.tifDead or ent.tifVeh or ent.tifBoard or ent.tifLeaving or IsValid(ent:GetParent())
end

local function rescue(ent, area)
	ent.tifRescues = (ent.tifRescues or 0) + 1
	if area and ent.tifRescues <= 2 and ent.tifArchId then
		local p = area:GetClosestPointOnArea(ent:GetPos()) or area:GetCenter()
		p = TIF.FreeSpot(p + Vector(0, 0, 4), ent)
		ent:SetPos(p)
		if ent.loco then ent.loco:SetVelocity(vector_origin) end
		if TIF.Move and ent.tifMove then TIF.Move.Stop(ent) end
		TIF.Log("Soldier #", ent:EntIndex(), " fell under the map: put back on the navmesh at ",
			math.floor(p.x), " ", math.floor(p.y), " ", math.floor(p.z))
		return
	end
	TIF.Log((ent.tifArchId and "Soldier #" or (ent:GetClass() .. " #")), ent:EntIndex(), " fell under the map: removed")
	ent:Remove()
end

timer.Create("tif_rescue", 2, 0, function()
	if not cvOn:GetBool() or navmesh.GetNavAreaCount() == 0 then return end
	local list = {}
	for _, e in ipairs(TIF.Soldiers or {}) do list[#list + 1] = e end
	if cvAll:GetBool() then
		for _, e in ipairs(ents.GetAll()) do
			if (e:IsNPC() or e:IsNextBot()) and not e.tifArchId then list[#list + 1] = e end
		end
	end
	for _, e in ipairs(list) do
		if IsValid(e) and not busy(e) then
			local isLost, area = lost(e)
			if isLost then
				e.tifLostChecks = (e.tifLostChecks or 0) + 1
				if e.tifLostChecks >= CHECKS then
					e.tifLostChecks = 0
					rescue(e, e.tifArchId and area or nil)
				end
			else
				e.tifLostChecks = 0
			end
		end
	end
end)
