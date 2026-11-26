-- Helicopter passengers, client side: no shadows while a soldier rides or is on his way out (NW2 "tif_noshadow",
-- set by tif/air/sv_air_ride.lua). Source stretched the shadows of the men 20 m up or tucked in a cabin into huge
-- blobs on the ground (user, 0.25.0). The soldier's drawn parts are cl_body's faction model and gun.

local TIF = TIF

timer.Create("tif_air_rider_shadows", 0.2, 0, function()
	local Bd = TIF.Body
	if not (Bd and Bd.States) then return end
	for ent, st in pairs(Bd.States) do
		if IsValid(ent) then
			local off = ent:GetNW2Bool("tif_noshadow", false)
			-- (re-applied when cl_body rebuilt a part: a new follower / gun comes with its shadow on)
			if off ~= st.tifNoShadow or st.tifShadowFollower ~= st.follower or st.tifShadowGun ~= st.gun then
				st.tifNoShadow, st.tifShadowFollower, st.tifShadowGun = off, st.follower, st.gun
				if IsValid(st.follower) then st.follower:DrawShadow(not off) end
				if IsValid(st.gun) then st.gun:DrawShadow(not off) end
				if IsValid(st.backGun) then st.backGun:DrawShadow(not off) end
				if IsValid(st.launcherGun) then st.launcherGun:DrawShadow(not off) end
			end
		end
	end
end)
