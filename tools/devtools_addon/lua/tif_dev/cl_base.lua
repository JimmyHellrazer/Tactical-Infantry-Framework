-- Base overlay (tif_debug 1): area ring and level, guard posts (red) and reserve spots
-- (orange) with facing lines, patrol routes (cyan), reinforcement point (purple), and the
-- base's last known enemy position (white cross).

local LEVEL_COLORS = {
	[-1] = Color(200, 200, 200), [0] = Color(80, 220, 120), [1] = Color(255, 200, 60), [2] = Color(255, 70, 60),
}
local LEVEL_NAMES = { [-1] = "DRAFT", [0] = "CALM", [1] = "ALERT", [2] = "ALARM" }
local POST, RESERVE, ROUTE, REINF = Color(255, 80, 80), Color(255, 160, 40), Color(60, 220, 255), Color(190, 90, 255)

local bases, received = {}, 0

net.Receive("tif_debug_bases", function()
	local list = {}
	for i = 1, net.ReadUInt(4) do
		local b = { name = net.ReadString(), level = net.ReadInt(3), info = net.ReadString(),
			center = net.ReadVector(), radius = net.ReadFloat(), posts = {}, routes = {} }
		for j = 1, net.ReadUInt(6) do
			b.posts[j] = { pos = net.ReadVector(), yaw = net.ReadFloat(), reserve = net.ReadBool() }
		end
		for j = 1, net.ReadUInt(4) do
			local pts = {}
			for k = 1, net.ReadUInt(6) do pts[k] = net.ReadVector() end
			b.routes[j] = pts
		end
		if net.ReadBool() then b.reinforce = net.ReadVector() end
		if net.ReadBool() then b.lkp = net.ReadVector() end
		list[i] = b
	end
	bases, received = list, CurTime()
end)

local UP = Vector(0, 0, 8)
local function ring(c, r, col)
	local prev
	for i = 0, 48 do
		local a = i / 48 * math.pi * 2
		local p = c + Vector(math.cos(a) * r, math.sin(a) * r, 8)
		if prev then render.DrawLine(prev, p, col, true) end
		prev = p
	end
end

hook.Add("PostDrawTranslucentRenderables", "tif_debug_bases", function(depth, sky)
	if sky or depth then return end
	if CurTime() - received > 3 then return end
	for _, b in ipairs(bases) do
		local col = LEVEL_COLORS[b.level] or color_white
		ring(b.center, b.radius, col)
		for _, p in ipairs(b.posts) do
			local c = p.reserve and RESERVE or POST
			render.DrawWireframeBox(p.pos, Angle(0, p.yaw, 0), Vector(-10, -10, 0), Vector(10, 10, 4), c, true)
			local r = math.rad(p.yaw)
			render.DrawLine(p.pos + UP, p.pos + UP + Vector(math.cos(r), math.sin(r), 0) * 60, c, true)
		end
		for _, pts in ipairs(b.routes) do
			for i = 1, #pts do
				local a, n = pts[i], pts[i % #pts + 1]
				render.DrawLine(a + UP, n + UP, ROUTE, true)
				render.DrawWireframeSphere(a + UP, 10, 6, 6, ROUTE, true)
			end
		end
		if b.reinforce then render.DrawWireframeSphere(b.reinforce + UP, 40, 8, 8, REINF, true) end
		if b.lkp then
			render.DrawLine(b.lkp + Vector(-30, -30, 10), b.lkp + Vector(30, 30, 10), color_white, false)
			render.DrawLine(b.lkp + Vector(-30, 30, 10), b.lkp + Vector(30, -30, 10), color_white, false)
		end
	end
	local eyeAng = EyeAngles()
	local ang = Angle(0, eyeAng.y - 90, 90)
	for _, b in ipairs(bases) do
		cam.Start3D2D(b.center + Vector(0, 0, 220), ang, 0.4)
			draw.SimpleTextOutlined("BASE " .. b.name .. ": " .. (LEVEL_NAMES[b.level] or "?"), "TIFDebug3D", 0, 0,
				LEVEL_COLORS[b.level] or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, color_black)
			draw.SimpleTextOutlined(b.info, "TIFDebug3D", 0, 30, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, color_black)
		cam.End3D2D()
	end
end)
