local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local src = io.open(ROOT .. "tif/tactics/sv_cover_mw.lua"):read("*a")
local block = src:match("(MW%.GUERRILLA_BLIND_SUPP = .-\nend\n)")
check(block ~= nil, "found MW.BlindRole")
local have = {}
local MW = {}
local env = setmetatable({ MW = MW, TIF = { GTG = { Clip = function(n) return have[n] end } } }, { __index = _G })
assert(load(block, "br", "t", env))()
check(MW.GUERRILLA_BLIND_SUPP == 0.4 and MW.GUERRILLA_BLIND_POP == 0.2, "blind fire from 0.4 suppression, 1 in 5 pop-outs")
for i = 1, 6 do have["mwc_ls_gblind" .. i] = true end
local g = { tifGuerrilla = true }
local cov = { t = "ls", host = "mw_male" }
local seen = {}
for _ = 1, 200 do seen[MW.BlindRole(g, cov)] = true end
local n = 0
for k in pairs(seen) do
	n = n + 1
	check(k:match("^gblind[1-6]$") ~= nil, "guerrillas only use the wild blind fire (" .. k .. ")")
end
check(n >= 5, "and spread over the variants (" .. n .. " of 6 seen)")
local t = { tifGuerrilla = false }
local r = MW.BlindRole(t, cov)
check(r == "blind1" or r == "blind2", "trained soldiers keep the trained blind fire")
check(MW.BlindRole(g, { t = "ls", host = "mw_male", pstl = true }):match("^blind[12]$"), "pistols keep the trained clips")
check(MW.BlindRole(g, { t = "rc", host = "mw_male" }):match("^blind[12]$"), "a cover type without wild clips falls back")
check(src:find("(supp > 0.55 or (npc.tifGuerrilla and supp > MW.GUERRILLA_BLIND_SUPP)) and arch.aggression >= 0.3", 1, true) ~= nil, "suppressed guerrillas blind-fire a little earlier")
check(src:find("npc.tifGuerrilla and not cov.pstl and math.random() < MW.GUERRILLA_BLIND_POP", 1, true) ~= nil, "and sometimes instead of popping out")

local sol = io.open(ROOT .. "entities/tif_soldier.lua"):read("*a")
check(sol:find('self.tifGuerrilla = fac.style == "guerrilla" and math.random() < (fac.styleChance or 0.7)', 1, true) and sol:find('self:SetNW2Bool("tif_guerrilla", self.tifGuerrilla == true)', 1, true), "rolled per soldier from the faction's style")
local content = io.open(ROOT .. "tif/config/sh_content.lua"):read("*a")
local ins = content:match('TIF%.RegisterFaction%("insurgents", {(.-)\n}%)')
check(ins and ins:find('style = "guerrilla"', 1, true) and ins:find("styleChance = 0.7", 1, true), "Insurgents are guerrillas (70%)")
local usmc = content:match('TIF%.RegisterFaction%("usmc", {(.-)\n}%)')
local ru = content:match('TIF%.RegisterFaction%("russians", {(.-)\n}%)')
check(usmc and not usmc:find("style", 1, true) and ru and not ru:find("style =", 1, true), "Marines and Russians stay trained")
local save = io.open(ROOT .. "tif/core/sv_save.lua"):read("*a")
check(save:find("guerrilla = ent.tifGuerrilla == true or nil", 1, true) and save:find("ent.tifGuerrilla = rec.guerrilla == true", 1, true), "saves keep who is a guerrilla")
local body = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
check(body:find("if stance ~= 1 and st.guerrilla and legs.gaim and set == legs.aim then\n\t\t\tset = legs.gaim", 1, true) ~= nil, "guerrillas aim with the jittery rebel stance")
check(body:find("if st.guerrilla and legs.gsprint and sprint == legs.relaxed.sprint then\n\t\tsprint = legs.gsprint[st.idleVar % #legs.gsprint + 1]", 1, true) ~= nil, "and sprint with a rebel sprint loop")
check(body:find('st.guerrilla = ent:GetNW2Bool("tif_guerrilla", false)', 1, true) ~= nil, "the client reads the flag")
local anim = io.open(ROOT .. "tif/npc/sh_anim.lua"):read("*a")
check(anim:find("g.idle = clips.mwgr_aim", 1, true) and anim:find("L.gsprint = #gs > 0 and gs or nil", 1, true), "legs build the guerrilla aim and sprints")
print(string.format("passed %d, failed %d", pass, fail))
