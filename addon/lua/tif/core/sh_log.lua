-- TIF log file (0.38.30, user: "are errors like that readable or only noticed when i report them" -> a log file to read
-- after a session). garrysmod/data/tif/log_sv.txt (server) and log_cl.txt (client; on a listen server both are on the
-- host's disk), the previous session's kept as *_prev.txt. Every TIF.Log / TIF.Warn / TIF.Error line goes in (still
-- printed to the console as before), plus TIF.Event(tag, ...) lines that only go to the file (CQB steps, human shield
-- scenes, melee fights, watchdog findings: core/sv_watchdog.lua) and tif_mark notes (a player marking a moment:
-- what the soldiers / civilians around him were doing). Capped at MAX_BYTES a session. tif_logfile 0: off.

local TIF = TIF
TIF.LogFile = TIF.LogFile or {}
local L = TIF.LogFile

L.NAME = SERVER and "tif/log_sv.txt" or "tif/log_cl.txt"
L.PREV = SERVER and "tif/log_sv_prev.txt" or "tif/log_cl_prev.txt"
L.MAX_BYTES = 2 * 1024 * 1024
L.FLUSH = 1

local cv = SERVER and CreateConVar("tif_logfile", "1", FCVAR_ARCHIVE,
	"Write TIF's log to garrysmod/data/tif/log_sv.txt (errors, warnings, CQB / shield events, watchdog finds)")
	or CreateClientConVar("tif_logfile_cl", "1", true, false, "Write TIF's client log to garrysmod/data/tif/log_cl.txt")

local buf, written, started, full = {}, 0, false, false

local function start()
	started = true
	file.CreateDir("tif")
	if file.Exists(L.NAME, "DATA") then
		-- (keep the last session's: rename, else copy)
		if file.Exists(L.PREV, "DATA") then file.Delete(L.PREV) end
		local ok = file.Rename and pcall(file.Rename, L.NAME, L.PREV)
		if not ok then file.Write(L.PREV, file.Read(L.NAME, "DATA") or "") end
	end
	local map = game.GetMap and game.GetMap() or "?"
	file.Write(L.NAME, string.format("=== TIF %s, %s, %s, map %s ===\n", TIF.Version or "?", SERVER and "server" or "client",
		os.date("%Y-%m-%d %H:%M:%S"), map))
end

-- One line: time of day, CurTime, a short kind / tag, the text.
function L.Line(kind, text)
	if not cv:GetBool() or full then return end
	if not started then start() end
	local line = string.format("%s %9.2f %-8s %s\n", os.date("%H:%M:%S"), CurTime(), kind, text)
	written = written + #line
	if written > L.MAX_BYTES then
		full = true
		buf[#buf + 1] = "... log full for this session (tif/log, MAX_BYTES) ...\n"
		return
	end
	buf[#buf + 1] = line
end

function L.Flush()
	if #buf == 0 or not started then return end
	file.Append(L.NAME, table.concat(buf))
	buf = {}
end

timer.Create("tif_logfile_flush", L.FLUSH, 0, L.Flush)
hook.Add("ShutDown", "tif_logfile", L.Flush)

local function join(...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	return table.concat(t, "")
end

-- Console lines go to the file too.
local log0, warn0, err0 = TIF.Log, TIF.Warn, TIF.Error
function TIF.Log(...) log0(...) L.Line("log", join(...)) end
function TIF.Warn(...) warn0(...) L.Line("WARN", join(...)) end
function TIF.Error(...) err0(...) L.Line("ERROR", join(...)) end

-- File only: what happened, for reading after a session.
function TIF.Event(tag, ...) L.Line(tag, join(...)) end
