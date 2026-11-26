local TIF = TIF
TIF.Glide = TIF.Glide or {}
local A = TIF.Glide

function A.Present()
	return istable(Glide) and scripted_ents.GetStored("base_glide") ~= nil
end

function A.IsVehicle(ent)
	return IsValid(ent) and ent.IsGlideVehicle == true
end

function A.IsUsable(veh)
	if not A.IsVehicle(veh) then return false end
	if veh.hasExploded then return false end
	if veh.GetChassisHealth and veh:GetChassisHealth() <= 0 then return false end
	if veh.GetEngineHealth and veh:GetEngineHealth() <= 0 then return false end
	if veh:WaterLevel() >= 3 then return false end

	return true
end

if SERVER then
	function A.StartEngine(veh)
		if veh.GetEngineState and veh:GetEngineState() == 0 and veh.TurnOn then
			veh:TurnOn()
		end
	end

	function A.StopEngine(veh)
		if veh.TurnOff then
			veh:TurnOff()
		end
	end

	function A.Drive(veh, throttle, steer, brake, handbrake)
		if veh.AwakePhysics then
			veh:AwakePhysics()
		end

		veh:SetInputFloat(1, "accelerate", math.Clamp(throttle or 0, 0, 1))
		veh:SetInputFloat(1, "steer", math.Clamp(steer or 0, -1, 1))
		veh:SetInputFloat(1, "brake", math.Clamp(brake or 0, 0, 1))

		local hb = handbrake == true
		if (veh:GetInputBool(1, "handbrake") == true) ~= hb then
			veh:SetInputBool(1, "handbrake", hb)
		end
	end

	function A.Release(veh)
		A.Drive(veh, 0, 0, 0, false)
	end
end
