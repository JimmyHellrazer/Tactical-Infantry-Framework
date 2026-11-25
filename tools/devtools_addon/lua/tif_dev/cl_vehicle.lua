-- Vehicle overlay (tif_debug 1): each known vehicle's state over it, its route (cyan, done
-- part dimmed), the pursuit target (white), and road classification from tif_roads
-- (yellow = road, grey = drivable, red = not drivable).

local vehs, roads, received = {}, {}, 0

net.Receive("tif_debug_veh", function()
	local list = {}
	for i = 1, net.ReadUInt(4) do
		local v = { ent = net.ReadEntity(), text = net.ReadString(), pts = {} }
		for k = 1, net.ReadUInt(6) do v.pts[k] = net.ReadVector() end
		v.i = net.ReadUInt(6)
		if net.ReadBool() then v.target = net.ReadVector() end
		list[i] = v
	end
	local r = {}
	for k = 1, net.ReadUInt(9) do
		local s = net.ReadUInt(2)
		r[k] = { s = s, net.ReadVector(), net.ReadVector(), net.ReadVector(), net.ReadVector() }
	end
	vehs, roads, received = list, r, CurTime()
end)

local ROUTE, DONE, ROAD, GROUND, NO = Color(60, 220, 255), Color(60, 120, 140), Color(255, 220, 60), Color(150, 150, 150), Color(255, 70, 60)
local UP = Vector(0, 0, 12)

hook.Add("PostDrawTranslucentRenderables", "tif_debug_veh", function(depth, sky)
	if sky or depth then return end
	if CurTime() - received > 2 then return end
	for _, r in ipairs(roads) do
		local col = r.s == 2 and ROAD or (r.s == 1 and GROUND or NO)
		for k = 1, 4 do render.DrawLine(r[k] + Vector(0, 0, 4), r[k % 4 + 1] + Vector(0, 0, 4), col, true) end
	end
	for _, v in ipairs(vehs) do
		local prev = IsValid(v.ent) and v.ent:GetPos() or nil
		for k, p in ipairs(v.pts) do
			if k > 1 then render.DrawLine(v.pts[k - 1] + UP, p + UP, k <= v.i and DONE or ROUTE, true) end
			render.DrawWireframeSphere(p + UP, 16, 6, 6, k < v.i and DONE or ROUTE, true)
		end
		if prev and v.target then render.DrawLine(prev + UP * 4, v.target + UP, color_white, false) end
	end
	local ang = Angle(0, EyeAngles().y - 90, 90)
	for _, v in ipairs(vehs) do
		if IsValid(v.ent) then
			cam.Start3D2D(v.ent:GetPos() + Vector(0, 0, 130), ang, 0.2)
				draw.SimpleTextOutlined(v.text, "TIFDebug3D", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, color_black)
			cam.End3D2D()
		end
	end
end)
