-- Room-clearing overlay (tif_debug 1):
--   doorways  a bar across the opening and an arrow pointing indoors. Green = exterior,
--             blue = interior; door entities get a box
--   active clears: stack slots (yellow, numbered), entry points (magenta, numbered), the room
--             being cleared (its nav areas outlined in orange), the target (white), phase text

local doors, clears, received = {}, {}, 0

net.Receive("tif_debug_cqb", function()
	local dl = {}
	for i = 1, net.ReadUInt(7) do
		dl[i] = { center = net.ReadVector(), normal = net.ReadVector(), width = net.ReadFloat(),
			exterior = net.ReadBool(), ent = net.ReadBool() }
	end
	local cl = {}
	for i = 1, net.ReadUInt(3) do
		local c = { phase = net.ReadString(), slots = {}, points = {}, areas = {} }
		for j = 1, net.ReadUInt(4) do c.slots[j] = net.ReadVector() end
		for j = 1, net.ReadUInt(4) do c.points[j] = net.ReadVector() end
		for j = 1, net.ReadUInt(7) do
			c.areas[j] = { net.ReadVector(), net.ReadVector(), net.ReadVector(), net.ReadVector() }
		end
		c.target = net.ReadVector()
		cl[i] = c
	end
	doors, clears, received = dl, cl, CurTime()
end)

local EXT, INT, SLOT, POINT, ROOM = Color(80, 230, 110), Color(80, 160, 255), Color(255, 220, 60), Color(255, 80, 230), Color(255, 150, 40)
local Z = Vector(0, 0, 6)

hook.Add("PostDrawTranslucentRenderables", "tif_debug_cqb", function(depth, sky)
	if sky or depth then return end
	if CurTime() - received > 2 then return end
	for _, d in ipairs(doors) do
		local col = d.exterior and EXT or INT
		local side = Vector(-d.normal.y, d.normal.x, 0) * (d.width / 2)
		local c = d.center + Vector(0, 0, 40)
		render.DrawLine(c - side, c + side, col, false)
		render.DrawLine(d.center + Z, d.center + Z + d.normal * 50, col, false)
		render.DrawLine(d.center + Z + d.normal * 50, d.center + Z + d.normal * 38 + side * 0.25, col, false)
		render.DrawLine(d.center + Z + d.normal * 50, d.center + Z + d.normal * 38 - side * 0.25, col, false)
		if d.ent then render.DrawWireframeBox(c, Angle(0, d.normal:Angle().y, 0), Vector(-4, -d.width / 2, -40), Vector(4, d.width / 2, 60), col, false) end
	end
	for _, c in ipairs(clears) do
		for _, a in ipairs(c.areas) do
			for k = 1, 4 do render.DrawLine(a[k] + Z, a[k % 4 + 1] + Z, ROOM, true) end
		end
		for _, s in ipairs(c.slots) do render.DrawWireframeBox(s, Angle(), Vector(-12, -12, 0), Vector(12, 12, 6), SLOT, false) end
		for _, p in ipairs(c.points) do render.DrawWireframeSphere(p + Z, 14, 6, 6, POINT, false) end
		render.DrawWireframeSphere(c.target + Z, 20, 6, 6, color_white, false)
	end
	local ang = Angle(0, EyeAngles().y - 90, 90)
	for _, c in ipairs(clears) do
		local function label(p, txt, col)
			cam.Start3D2D(p + Vector(0, 0, 30), ang, 0.15)
				draw.SimpleTextOutlined(txt, "TIFDebug3D", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, color_black)
			cam.End3D2D()
		end
		for i, s in ipairs(c.slots) do label(s, "stack " .. i, SLOT) end
		for i, p in ipairs(c.points) do label(p, "entry " .. i, POINT) end
		label(c.target + Vector(0, 0, 40), "CLEAR: " .. c.phase, color_white)
	end
end)
