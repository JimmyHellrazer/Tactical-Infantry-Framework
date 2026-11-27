local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local V = {}
V.__index = V
function Vector(x, y, z) if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function isvector(v) return getmetatable(v) == V end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function Angle(p, y, r) return { p = p, y = y, r = r } end
vector_origin = Vector()
function IsValid(x) return x ~= nil and x ~= false and (type(x) ~= "table" or not x.removed) end
function CurTime() return 50 end
local timers, hooks = {}, {}
timer = { Create = function(n, d, r, f) timers[n] = f end }
hook = { Add = function(ev, id, f) hooks[ev] = f end }
util = { IsValidModel = function(m) return m:find("%.mdl$") ~= nil end }
local registered = {}
duplicator = { RegisterEntityClass = function(c, f, ...) registered[c] = { f = f, args = { ... } } end }
local stored = { tif_soldier = { t = { TIFSoldier = true } }, tif_soldier_pmc = { t = { Base = "tif_soldier" } }, prop_physics = { t = {} } }
scripted_ents = { GetList = function() return stored end, GetStored = function(c) return stored[c] end }

TIF = { Factions = { insurgents = { models = { "models/a.mdl", "models/b.mdl" } }, usmc = { modular = true, models = {} } } }
function TIF.FactionCanon(id) return id end
local warned = 0
function TIF.Warn() warned = warned + 1 end
local SQ = { List = {}, NextId = 1 }
TIF.Squad = SQ
function SQ.Publish() end
function SQ.Add(sq, e) if e.tifSquad then for i, m in ipairs(e.tifSquad.members) do if m == e then table.remove(e.tifSquad.members, i) end end end sq.members[#sq.members + 1] = e e.tifSquad = sq end
function SQ.Create(f, list, leader) local sq = { id = SQ.NextId, faction = f, members = {}, order = { kind = "free" } } SQ.NextId = SQ.NextId + 1 for _, e in ipairs(list) do SQ.Add(sq, e) end sq.leader = leader or list[1] return sq end
function SQ.SetLeader(sq, l) sq.leader = l end
function SQ.ForPlayer(ply) for _, sq in pairs(SQ.List) do if sq.leader == ply then return sq end end local sq = SQ.Create("usmc", {}) sq.leader = ply SQ.List[sq.id] = sq return sq end
TIF.API = {
	FormSquad = function(list) local leader = list[1] for _, e in ipairs(list) do if e.tifArchId == "leader" then leader = e end end return SQ.Create(list[1]:GetTIFFaction(), list, leader) end,
	SquadPatrol = function(sq, route) sq.order = { kind = "patrol", route = route } end,
}

local Ent = {}
Ent.__index = Ent
function Ent:GetTable() return self end
function Ent:GetTIFFaction() return self.nv.TIFFaction end
function Ent:SetTIFFaction(v) self.nv.TIFFaction = v end
function Ent:GetTIFVisual() return self.nv.TIFVisual end
function Ent:SetTIFVisual(v) self.nv.TIFVisual = v end
function Ent:GetTIFSkin() return self.nv.TIFSkin end
function Ent:SetTIFSkin(v) self.nv.TIFSkin = v end
function Ent:GetTIFBodygroups() return self.nv.TIFBodygroups end
function Ent:SetTIFBodygroups(v) self.nv.TIFBodygroups = v end
function Ent:GetNW2String(k, d) return self.nw[k] or d end
function Ent:SetNW2String(k, v) self.nw[k] = v end
function Ent:Health() return self.hp end
function Ent:SetHealth(v) self.hp = v end
function Ent:GetMaxHealth() return self.maxhp end
function Ent:SetMaxHealth(v) self.maxhp = v end
function Ent:SetPos(p) self.pos = p end
function Ent:SetAngles(a) self.ang = a end
function Ent:IsPlayer() return false end
function Ent:Activate() end
local rolls = 0
function Ent:Spawn()
	local fac = self.TIFFaction or self.tifSpawnFaction
	rolls = rolls + 1
	self:SetTIFFaction(fac)
	self:SetTIFVisual(TIF.Factions[fac].models[1] or "models/mod_main.mdl")
	self:SetTIFSkin(9) self:SetTIFBodygroups("9 9") self:SetNW2String("tif_parts", "rolled")
	self.tifArchId = self.tifArchId or "rifleman"
	self.hp, self.maxhp = 100, 100
	self.tifHomeHost = "mw_male"
	self.tifArms = { primary = { class = self.tifWeaponOverride or "default_rifle" }, secondary = { class = self.tifSecondaryOverride or "default_pistol" } }
	if self.tifLauncherOverride then self.tifArms.launcher = { class = self.tifLauncherOverride, rockets = 1 } end
end
local created = {}
ents = { Create = function(class) local e = setmetatable({ class = class, nv = {}, nw = {}, TIFSoldier = true }, Ent) created[#created + 1] = e return e end }
local function soldier(fac, arch)
	local e = ents.Create("tif_soldier")
	e.tifSpawnFaction, e.tifArchId = fac, arch
	e:Spawn()
	return e
end

assert(loadfile(ROOT .. "tif/core/sv_save.lua"))()
local S = TIF.Save
hooks.InitPostEntity()
check(registered.tif_soldier and registered.tif_soldier_pmc and not registered.prop_physics, "soldier classes (and faction subclasses) get their own paste function")
check(registered.tif_soldier.args[1] == "Data", "the paste function gets the whole saved record")

local a = soldier("insurgents", "leader")
a:SetTIFVisual("models/b.mdl") a:SetTIFSkin(2) a:SetTIFBodygroups("1 0 3") a:SetNW2String("tif_parts", "helmet=2")
a.hp = 60
a.tifArms = { primary = { class = "weapon_tifmw_akm", mag = 12 }, secondary = { class = "weapon_tifmw_pistol" }, launcher = { class = "weapon_tifmw_rpg7", rockets = 0 } }
a.tifK = { contacts = { [{}] = { pos = Vector() } } }
a.tifAct = { clip = {}, t0 = 3 }
a.tifPost, a.tifPostYaw = Vector(10, 20, 0), 90
local b = soldier("insurgents", "rifleman")
local sq = SQ.Create("insurgents", { a, b }, a)
sq.order = { kind = "hold", pos = Vector(500, 0, 0), yaw = 45, time = 3 }
a.Pos = "stale"

local data = {}
for k, v in pairs(a:GetTable()) do data[k] = v end
data.Pos, data.Class, data.DT, data.BodyG, data.Skin = Vector(1, 2, 3), "tif_soldier", { TIFStance = 2, TIFAware = 3 }, { [1] = 2 }, 4
data.PhysicsObjects = {}
S.Strip(a, data)
check(data.tifK == nil and data.tifAct == nil and data.tifSquad == nil and data.tifArms == nil, "live state (contacts, action, squad, weapons) stays out of the save")
check(data.DT == nil and data.BodyG == nil and data.Skin == nil, "network vars (stance, awareness) and host bodygroups aren't saved")
check(isvector(data.Pos) and data.Pos.x == 1 and data.Class == "tif_soldier" and data.PhysicsObjects, "position, class and physics are kept")
local r = data.TIFSave
check(r.faction == "insurgents" and r.arch == "leader", "faction and role saved")
check(r.vis == "models/b.mdl" and r.skin == 2 and r.groups == "1 0 3" and r.parts == "helmet=2", "his look saved")
check(r.primary == "weapon_tifmw_akm" and r.secondary == "weapon_tifmw_pistol" and r.launcher == "weapon_tifmw_rpg7" and r.rockets == 0, "his guns saved (and a fired launcher stays empty)")
check(r.health == 60 and r.maxHealth == 100, "health saved")
check(r.squad == sq.id and r.leader and r.order.kind == "hold" and r.order.pos.x == 500 and r.order.yaw == 45, "squad, leadership and order saved")
check(r.post.x == 10 and r.postYaw == 90, "his post saved")
for k, v in pairs(r) do
	local t = type(v)
	if t == "table" and not isvector(v) then for _, w in pairs(v) do if type(w) == "table" and not isvector(w) then t = "bad" end end end
	check(t ~= "function" and t ~= "userdata" and t ~= "bad", "record field " .. k .. " is plain data")
end

local d1 = soldier("insurgents") d1.tifDead = true
local d2 = soldier("insurgents") d2.tifDowned = { t0 = 1 }
local d3 = soldier("insurgents") d3.tifVeh = {}
check(S.Record(d1).skip and S.Record(d2).skip and S.Record(d3).skip, "dead, downed and seated soldiers aren't saved")
local nb = #created
check(S.Create(nil, { Class = "tif_soldier", TIFSave = { skip = true } }) == nil and #created == nb, "and nothing is pasted for them")

local bdata = {}
for k, v in pairs(b:GetTable()) do bdata[k] = v end
bdata.Pos, bdata.Class = Vector(5, 5, 0), "tif_soldier"
S.Strip(b, bdata)

rolls = 0
local na = S.Create(nil, data)
check(na and na.pos.x == 1 and rolls == 1, "a saved soldier spawns once, where he stood")
check(na.tifArchId == "leader" and na:GetTIFFaction() == "insurgents", "same faction and role")
check(na:GetTIFVisual() == "models/b.mdl" and na:GetTIFSkin() == 2 and na:GetTIFBodygroups() == "1 0 3" and na:GetNW2String("tif_parts") == "helmet=2", "same look (not re-rolled)")
check(na.tifArms.primary.class == "weapon_tifmw_akm" and na.tifArms.launcher.rockets == 0, "same guns")
check(na.hp == 60 and na.maxhp == 100, "same health")
check(na.tifPost.x == 10 and na.tifPostYaw == 90, "same post")
check(na.tifNoAutoSquad and na.tifSquad == nil, "he waits for his squad instead of auto-joining a random one")
check(na.tifK == nil and na.tifAct == nil, "fresh brain")
local nbb = S.Create(nil, bdata)
check(timers.tif_save_rebuild ~= nil, "squads are rebuilt once the paste is done")
local made = S.Rebuild()
check(#made == 1 and na.tifSquad == nbb.tifSquad and na.tifSquad ~= sq, "the two are back in one (new) squad")
check(made[1].leader == na, "with the same leader")
check(made[1].order.kind == "hold" and made[1].order.pos.x == 500 and made[1].order.yaw == 45 and made[1].order.time == 50, "and the same order")
check(#S.Pending == 0, "pending list cleared")

local p1 = soldier("insurgents") local p2 = soldier("insurgents")
local psq = SQ.Create("insurgents", { p1, p2 })
psq.order = { kind = "patrol", route = { Vector(1, 0, 0), Vector(2, 0, 0), Vector(3, 0, 0) }, i = 2 }
local d = {}
for _, e in ipairs({ p1, p2 }) do local t = { Class = "tif_soldier", Pos = Vector() } S.Strip(e, t) d[#d + 1] = t end
for _, t in ipairs(d) do S.Create(nil, t) end
local m2 = S.Rebuild()
check(#m2 == 1 and m2[1].order.kind == "patrol" and #m2[1].order.route == 3 and m2[1].order.route[3].x == 3, "patrols keep their route")

local ply = { IsPlayer = function() return true end }
local f1 = soldier("usmc") local f2 = soldier("usmc")
local fsq = SQ.Create("usmc", { f1, f2 }) fsq.leader = ply fsq.order = { kind = "follow" }
local fd = {}
for _, e in ipairs({ f1, f2 }) do local t = { Class = "tif_soldier", Pos = Vector() } S.Strip(e, t) fd[#fd + 1] = t end
check(fd[1].TIFSave.plyLed and not fd[1].TIFSave.leader, "your squadmates remember they followed you")
local ply2 = { IsPlayer = function() return true end }
local nf = {}
for _, t in ipairs(fd) do nf[#nf + 1] = S.Create(ply2, t) end
local m3 = S.Rebuild()
check(m3[1].leader == ply2 and nf[1].tifSquad == m3[1] and nf[2].tifSquad == m3[1] and m3[1].order.kind == "follow", "and follow you again after the load")

local solo = soldier("insurgents")
local sd = { Class = "tif_soldier", Pos = Vector() } S.Strip(solo, sd)
local ns = S.Create(nil, sd)
check(ns and not ns.tifNoAutoSquad, "a soldier saved without a squad joins one as usual")

local u = soldier("usmc")
local ud = { Class = "tif_soldier", Pos = Vector() } S.Strip(u, ud)
ud.TIFSave.vis = "models/mod_x.mdl"
local nu = S.Create(nil, ud)
check(nu:GetTIFVisual() == "models/mod_x.mdl", "modular factions keep their assembled model")
local bad = { Class = "tif_soldier", Pos = Vector(), TIFSave = { faction = "insurgents", arch = "rifleman", vis = "models/not_ours.mdl", skin = 3 } }
local nbad = S.Create(nil, bad)
check(nbad:GetTIFVisual() == "models/a.mdl" and nbad:GetTIFSkin() == 9, "a look that's no longer in the faction is re-rolled instead")
local gone = { Class = "tif_soldier", Pos = Vector(), TIFSave = { faction = "removed_pack", arch = "rifleman" } }
check(S.Create(nil, gone) == nil and warned == 1, "a soldier whose faction pack is gone is skipped with a warning")

local old = { Class = "tif_soldier", Pos = Vector(7, 0, 0), DT = { TIFFaction = "insurgents", TIFStance = 2 }, tifArchId = "support", tifK = { junk = true }, tifSquad = { id = 99 } }
local no = S.Create(nil, old)
check(no and no:GetTIFFaction() == "insurgents" and no.tifArchId == "support" and no.tifK == nil and no.tifSquad == nil, "saves made before this load as fresh soldiers of the same faction and role")

local src = io.open(ROOT .. "entities/tif_soldier.lua"):read("*a")
check(src:find("function ENT:OnEntityCopyTableFinish(data)\n\tTIF.Save.Strip(self, data)", 1, true) ~= nil, "the soldier strips itself when copied")
local init = io.open(ROOT .. "autorun/tif_init.lua"):read("*a")
check(init:find('"core/sv_save.lua"', 1, true) ~= nil, "the module loads")
print(string.format("passed %d, failed %d", pass, fail))
