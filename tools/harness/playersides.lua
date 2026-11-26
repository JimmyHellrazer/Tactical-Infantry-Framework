timer = timer or { Create = function() end, Simple = function() end, Remove = function() end }
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
table.Copy = function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
TIF = { GTG = { DEFAULT_HOST = "mw_male", WeaponDef = function() return nil end } }
assert(loadfile(ROOT .. "tif/config/sh_content.lua"))()
local PF = "operators"
CreateConVar = function() return { GetString = function() return PF end, GetBool = function() return false end } end
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
bit = bit or { bor = function(a, b) return a + b end }
hook = hook or { Add = function() end }
GetConVar = function() return { GetBool = function() return false end, GetString = function() return "" end } end
local warned = 0
function Color() return {} end
function MsgC() warned = warned + 1 end
function IsValid(e) return e ~= nil end
assert(loadfile(ROOT .. "tif/core/sh_factions.lua"))()
local A, H, N = TIF.REL_ALLY, TIF.REL_HOSTILE, TIF.REL_NEUTRAL
local R = TIF.FactionRelation
local ply = { IsPlayer = function() return true end, GetNW2String = function(_, _, d) return d end }

check(TIF.PlayerFaction() == "usmc", "missing player faction falls back to usmc")
check(warned == 1, "warns once")
TIF.PlayerFaction()
check(warned == 1, "only once")
check(TIF.FactionOf(ply) == "usmc", "player counts as usmc")
check(TIF.Relation(ply, { TIFSoldier = true, GetTIFFaction = function() return "usmc" end }) == A, "regular Marines friendly to a player with a missing faction")
check(TIF.Relation(ply, { TIFSoldier = true, GetTIFFaction = function() return "usmc_woodland" end }) == A, "woodland too")
check(TIF.Relation(ply, { TIFSoldier = true, GetTIFFaction = function() return "insurgents" end }) == H, "insurgents still hostile")
TIF.Factions.operators = { side = "ally", allies = { usmc = true } } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
check(TIF.PlayerFaction() == "operators", "installed pack faction is used as-is")
TIF.Factions.operators = nil if TIF.ClearRelationCache then TIF.ClearRelationCache() end

PF = "blufor"
check(TIF.PlayerFaction() == "blufor", "blufor is a valid player faction")
check(TIF.FactionOf(ply) == "blufor", "player is blufor")
check(R("blufor", "usmc") == A and R("usmc", "blufor") == A, "blufor + usmc allied both ways")
check(R("blufor", "usmc_woodland") == A, "blufor + woodland")
check(R("blufor", "insurgents") == H and R("blufor", "russians") == H, "blufor vs insurgents / russians hostile")
check(R("blufor", "opfor") == H and R("blufor", "independent") == H, "player sides hostile to each other")
check(R("blufor", "blufor") == A, "blufor players friendly to each other")
TIF.Factions.operators = { side = "ally" } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
TIF.Factions.al_qatala = { side = "enemy" } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
check(R("blufor", "operators") == A and R("blufor", "al_qatala") == H, "pack factions sorted by side")

check(R("opfor", "insurgents") == A and R("opfor", "russians") == A, "opfor + insurgents / russians")
check(R("insurgents", "opfor") == A, "both ways")
check(R("opfor", "usmc") == H and R("opfor", "usmc_woodland") == H, "opfor vs Marines")
check(R("opfor", "al_qatala") == A and R("opfor", "operators") == H, "opfor pack factions by side")

check(R("independent", "usmc") == H and R("independent", "insurgents") == H and R("independent", "russians") == H, "independent hostile to all")
TIF.Factions.locals = { side = "neutral", neutral = { independent = true } } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
check(R("independent", "locals") == N, "a faction can list independent as neutral")
TIF.Factions.mercs = { side = "enemy", allies = { independent = true } } if TIF.ClearRelationCache then TIF.ClearRelationCache() end
check(R("independent", "mercs") == A, "or as an ally")
check(TIF.Factions.blufor == nil and TIF.Factions.opfor == nil and TIF.Factions.independent == nil, "sides aren't spawnable factions")
check(R("usmc", "insurgents") == H and R("usmc", "usmc_woodland") == A, "soldier relations unchanged")
local calls = 0
local real = TIF.Factions
TIF.Factions = setmetatable({}, { __index = function(_, k) calls = calls + 1 return real[k] end })
TIF.ClearRelationCache()
R("usmc", "insurgents")
local c1 = calls
R("usmc", "insurgents")
check(calls == c1, "a repeated relation comes from the cache")
TIF.Factions = real
TIF.ClearRelationCache()
check(R("usmc", "insurgents") == H, "same answer after a clear")
check(R("blufor", "newside") == H, "an unknown faction is hostile")
TIF.RegisterFaction("newside", { side = "ally" })
check(R("blufor", "newside") == A, "registering a faction clears the cache")
print(string.format("passed %d, failed %d", pass, fail))
