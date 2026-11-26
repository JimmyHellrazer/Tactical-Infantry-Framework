local TIF = TIF
local frame

local ORDERS = {
	{ "Follow me", "tif_order follow" },
	{ "Hold at crosshair", "tif_order hold" },
	{ "Advance to crosshair", "tif_order advance" },
	{ "Regroup on me", "tif_order regroup" },
	{ "Free (fight on own)", "tif_order free" },
	{ "Clear building at crosshair", "tif_order clear" },
}
local FORMS = { "wedge", "column", "line", "file" }
local SQUAD = {
	{ "Take command (nearby allies)", "tif_follow" },
	{ "Dismiss squad", "tif_dismiss" },
}

local function button(parent, label, cmd, close)
	local b = vgui.Create("DButton", parent)
	b:Dock(TOP)
	b:DockMargin(0, 0, 0, 3)
	b:SetTall(26)
	b:SetText(label)
	b.DoClick = function()
		LocalPlayer():ConCommand(cmd)
		surface.PlaySound("buttons/lightswitch2.wav")

		if close and IsValid(frame) then
			frame:Close()
		end
	end

	return b
end

local function header(parent, text)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(0, 6, 0, 2)
	l:SetText(text)
	l:SetFont("DermaDefaultBold")
	l:SetTextColor(Color(230, 230, 230))
end

local function open(holdMode)
	if IsValid(frame) then
		frame:Remove()
	end

	frame = vgui.Create("DFrame")
	frame:SetTitle("Squad orders")
	frame:SetSize(240, 460)
	frame:SetPos(ScrW() * 0.5 + 60, ScrH() * 0.5 - 230)
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)
	frame.tifHold = holdMode

	header(frame, "Orders")

	for _, o in ipairs(ORDERS) do
		button(frame, o[1], o[2], not holdMode)
	end

	header(frame, "Formation")

	for _, f in ipairs(FORMS) do
		button(frame, f:sub(1, 1):upper() .. f:sub(2), "tif_formation " .. f, not holdMode)
	end

	header(frame, "Squad")

	for _, s in ipairs(SQUAD) do
		button(frame, s[1], s[2], not holdMode)
	end
end

concommand.Add("tif_menu", function() open(false) end, nil, "Open the squad order menu")

concommand.Add("+tif_menu", function() open(true) end)

concommand.Add("-tif_menu", function() if IsValid(frame) then frame:Close() end end)
