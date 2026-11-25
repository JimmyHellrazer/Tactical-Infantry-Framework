-- Shared helpers: logging, admin checks, report files.

local TIF = TIF

local COLOR_TAG = Color(120, 200, 255)
local COLOR_WARN = Color(255, 190, 80)
local COLOR_ERR = Color(255, 90, 90)

function TIF.Log(...)
	MsgC(COLOR_TAG, "[TIF] ", color_white, table.concat({ ... }, ""), "\n")
end

function TIF.Warn(...)
	MsgC(COLOR_TAG, "[TIF] ", COLOR_WARN, table.concat({ ... }, ""), "\n")
end

function TIF.Error(...)
	MsgC(COLOR_TAG, "[TIF] ", COLOR_ERR, table.concat({ ... }, ""), "\n")
end

-- Dev commands run for the server console, the listen-server host and superadmins.
function TIF.CanUseDev(ply)
	if not IsValid(ply) then return true end
	if game.SinglePlayer() or ply:IsListenServerHost() then return true end
	return ply:IsSuperAdmin()
end

-- A report is a list of lines written to data/tif/reports/<name>.txt and echoed to console.
-- Client-side reports get a "cl_" prefix so they don't overwrite server ones on a listen server.
local Report = {}
Report.__index = Report

function TIF.NewReport(name, title)
	local r = setmetatable({ name = name, lines = {}, fails = 0, warns = 0 }, Report)
	r:Line("# ", title or name)
	r:Line("TIF ", TIF.Version, " | map ", game.GetMap(), " | ", os.date("%Y-%m-%d %H:%M:%S"),
		" | ", SERVER and "server" or "client")
	r:Line("")
	return r
end

function Report:Line(...)
	self.lines[#self.lines + 1] = table.concat({ ... }, "")
end

function Report:Section(title)
	self:Line("")
	self:Line("## ", title)
end

function Report:Pass(label, detail)
	self:Line("[PASS] ", label, detail and ("  -- " .. detail) or "")
end

function Report:Fail(label, detail)
	self.fails = self.fails + 1
	self:Line("[FAIL] ", label, detail and ("  -- " .. detail) or "")
end

function Report:Warn(label, detail)
	self.warns = self.warns + 1
	self:Line("[WARN] ", label, detail and ("  -- " .. detail) or "")
end

function Report:Info(label, detail)
	self:Line("[INFO] ", label, detail and ("  -- " .. detail) or "")
end

function Report:Check(ok, label, detail)
	if ok then self:Pass(label, detail) else self:Fail(label, detail) end
	return ok
end

function Report:Save()
	self:Line("")
	self:Line("Summary: ", self.fails, " fail(s), ", self.warns, " warning(s)")
	local text = table.concat(self.lines, "\n") .. "\n"
	file.CreateDir("tif")
	file.CreateDir("tif/reports")
	local fname = (CLIENT and "cl_" or "") .. self.name .. ".txt"
	file.Write("tif/reports/" .. fname, text)
	for _, l in ipairs(self.lines) do
		if string.sub(l, 1, 6) == "[FAIL]" then TIF.Error(l)
		elseif string.sub(l, 1, 6) == "[WARN]" then TIF.Warn(l)
		else MsgN(l) end
	end
	TIF.Log("Report written to garrysmod/data/tif/reports/", fname)
	return fname
end

-- Format a number with fixed decimals.
function TIF.Fmt(n, dec)
	return string.format("%." .. (dec or 2) .. "f", n or 0)
end

-- Trace from a player's eyes to find a spawn spot on the ground in front of them.
function TIF.SpotInFront(ply, dist)
	local start = ply:EyePos()
	local fwd = ply:GetAimVector()
	fwd.z = 0
	fwd:Normalize()
	local tr = util.TraceLine({ start = start, endpos = start + fwd * (dist or 200), filter = ply, mask = MASK_SOLID })
	local p = tr.HitPos - fwd * 32
	local down = util.TraceLine({ start = p + Vector(0, 0, 16), endpos = p - Vector(0, 0, 256), mask = MASK_SOLID })
	return down.HitPos, Angle(0, fwd:Angle().y, 0)
end
