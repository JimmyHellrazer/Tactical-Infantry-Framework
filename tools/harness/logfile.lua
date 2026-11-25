-- Offline (0.38.30): TIF's log file (core/sh_log.lua) and the watchdog (core/sv_watchdog.lua).
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function V:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:Distance(o) return (self - o):Length() end
function V:DistToSqr(o) local d = self - o return d.x ^ 2 + d.y ^ 2 + d.z ^ 2 end
function IsValid(x) return x ~= nil and x ~= false end
SERVER, CLIENT, FCVAR_ARCHIVE = true, false, 1
function Color() return {} end
color_white = {}
local console = {}
function MsgC(...) console[#console + 1] = table.concat({ select(4, ...) or "" }) end
local cvOn = "1"
function CreateConVar() return { GetBool = function() return cvOn ~= "0" end } end
local timers, hooks, cmds = {}, {}, {}
timer = { Create = function(n, _, _, fn) timers[n] = fn end }
hook = { Add = function(ev, id, fn) hooks[ev .. ":" .. id] = fn end }
concommand = { Add = function(n, fn) cmds[n] = fn end }
local now = 50
function CurTime() return now end
game = { GetMap = function() return "tif_cqb" end }
-- in-memory DATA folder
local files = { ["tif/log_sv.txt"] = "old session\n" }
file = {
	CreateDir = function() end,
	Exists = function(n) return files[n] ~= nil end,
	Delete = function(n) files[n] = nil end,
	Rename = function(a, b) files[b] = files[a] files[a] = nil return true end,
	Read = function(n) return files[n] end,
	Write = function(n, s) files[n] = s end,
	Append = function(n, s) files[n] = (files[n] or "") .. s end,
}
TIF = { Version = "0.38.30" }
assert(loadfile(ROOT .. "tif/sh_core.lua"))()
assert(loadfile(ROOT .. "tif/core/sh_log.lua"))()
local L = TIF.LogFile

TIF.Error("Human shield: ", "boom")
TIF.Warn("careful")
TIF.Event("cqb", "squad ", 3, ": entry")
check(console[1] and console[1]:find("boom"), "errors still printed to the console")
check(files["tif/log_sv_prev.txt"] == "old session\n", "the last session's log kept as _prev")
check(files["tif/log_sv.txt"]:find("=== TIF 0.38.30, server", 1, true), "a session header (version, realm, map)")
check(not files["tif/log_sv.txt"]:find("boom", 1, true), "buffered until a flush")
timers.tif_logfile_flush()
local log = files["tif/log_sv.txt"]
check(log:find("ERROR    Human shield: boom", 1, true) and log:find("WARN     careful", 1, true), "errors / warnings in the file")
check(log:find("cqb      squad 3: entry", 1, true), "events in the file")
check(not table.concat(console, "\n"):find("squad 3", 1, true), "events don't print to the console")

-- watchdog
local function civ(id, state, held)
	local c = { id = id, state = state, tifHeld = held, pos = Vector(id * 10, 0, 0) }
	function c:GetClass() return "tif_civilian" end
	function c:EntIndex() return self.id end
	function c:GetPos() return self.pos end
	function c:SetState(s) self.state = s end
	return c
end
local live = { done = false }
TIF.Shield = { List = { [live] = true } }
local orphan = civ(1, "held", { done = true })
local stray = civ(2, "held", nil)
local fine = civ(3, "held", live)
TIF.Civ = { List = function() return { orphan, stray, fine } end }
local s1 = { tifActLock = true, tifAct = { name = "mwsh_idle_att" }, TIFSoldier = true }
function s1:GetClass() return "tif_soldier" end
function s1:EntIndex() return 9 end
function s1:GetPos() return Vector(0, 0, 0) end
TIF.Soldiers = { s1 }
local team = { s1 }
TIF.Squad = { List = { { id = 4, cqb = { phase = "entry", t0 = 10, released = 0, team = team, door = { id = 2 }, stackReady = 1 } } } }
TIF.Building = { Closed = function() return false end }
assert(loadfile(ROOT .. "tif/core/sv_watchdog.lua"))()
now = 40
timers.tif_watchdog()
timers.tif_logfile_flush()
log = files["tif/log_sv.txt"]
check(orphan.tifHeld == nil and orphan.state == "flee" and log:find("held civilian with no live scene: tif_civilian#1", 1, true), "a held civilian whose scene ended: let go, logged")
check(stray.state == "flee" and log:find("civilian in state held with no scene: tif_civilian#2", 1, true), "a civilian left in held: let go, logged")
check(fine.state == "held" and fine.tifHeld == live, "a civilian in a live scene: left alone")
check(s1.tifActLock == nil and log:find("animation lock left on with no scene", 1, true), "a leaked animation lock: unlocked, logged")
check(log:find("cqb squad 4 in entry for 30 s: released 0/1", 1, true), "a CQB stuck in its entry: logged with what it's waiting on")
local n0 = select(2, log:gsub("cqb squad 4", ""))
now = 42
timers.tif_watchdog() timers.tif_logfile_flush()
check(select(2, files["tif/log_sv.txt"]:gsub("cqb squad 4", "")) == n0, "...once")
-- tif_mark
s1.tifAction, s1.tifCQB = "cqb: entry 1", { label = "entry 1" }
function s1:GetTIFFaction() return "pmc" end
local chats = {}
local ply = { GetPos = function() return Vector(0, 0, 0) end, Nick = function() return "tester" end, ChatPrint = function(_, s) chats[#chats + 1] = s end }
cmds.tif_mark(ply, "tif_mark", { "stuck", "at", "door" })
log = files["tif/log_sv.txt"]
check(log:find("MARK     tester: stuck at door", 1, true) and log:find("tif_soldier#9, 0 u, pmc, \"cqb: entry 1\"", 1, true), "tif_mark: the note and what's around, flushed at once")
check(chats[1] and chats[1]:find("log_sv.txt", 1, true), "tif_mark: tells the player where")
-- cap (last: once full, nothing more this session)
log = files["tif/log_sv.txt"]
L.MAX_BYTES = #log + 200
for i = 1, 50 do TIF.Event("spam", string.rep("x", 40)) end
timers.tif_logfile_flush()
check(files["tif/log_sv.txt"]:find("log full for this session", 1, true) and #files["tif/log_sv.txt"] < #log + 400, "capped a session")
cvOn = "0"
TIF.Event("x", "nothing")
timers.tif_logfile_flush()
check(not files["tif/log_sv.txt"]:find("nothing", 1, true), "tif_logfile 0: nothing written")
print(string.format("passed %d, failed %d", pass, fail))
