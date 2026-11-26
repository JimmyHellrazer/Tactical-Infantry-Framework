local TIF = TIF

timer.Create("tif_air_rider_shadows", 0.2, 0, function()
	local Bd = TIF.Body
	if not (Bd and Bd.States) then return end
	for ent, st in pairs(Bd.States) do
		if IsValid(ent) then
			local off = ent:GetNW2Bool("tif_noshadow", false)

			if off ~= st.tifNoShadow or st.tifShadowFollower ~= st.follower or st.tifShadowGun ~= st.gun then
				st.tifNoShadow, st.tifShadowFollower, st.tifShadowGun = off, st.follower, st.gun
				if IsValid(st.follower) then
					st.follower:DrawShadow(not off)
				end
				if IsValid(st.gun) then
					st.gun:DrawShadow(not off)
				end
				if IsValid(st.backGun) then
					st.backGun:DrawShadow(not off)
				end
				if IsValid(st.launcherGun) then
					st.launcherGun:DrawShadow(not off)
				end
			end
		end
	end
end)
