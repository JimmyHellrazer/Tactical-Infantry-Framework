local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local cas = io.open(ROOT .. "tif/tactics/sv_casualty.lua"):read("*a")
local down = cas:sub(cas:find("function CAS.Down(npc, dmg)", 1, true), cas:find("Move.Stop(npc)", cas:find("function CAS.Down(npc, dmg)", 1, true), true))
check(down:find('npc:SetNW2Int("tif_prone", 0)', 1, true) ~= nil, "going down clears the networked prone state (the client drew him prone through the downed / revive clips)")
check(down:find('npc:SetNW2Float("tif_prone_t", now)', 1, true) ~= nil, "and its time")
check(down:find("npc.tifDowned.wasProne = true", 1, true) ~= nil, "downed from prone still skips the fall")
local body = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
check(body:find('string.sub(actName, 1, 10) == "mwls_help_" or string.sub(actName, 1, 5) == "mwbr_"', 1, true) ~= nil, "MW22 buddy revives sling the medic's gun too (it stayed in his hand)")
local gh = io.open(ROOT .. "../../tools/guns/gun_holds.py")
if gh then
	local t = gh:read("*a")
	check(t:find('MP_UNUSABLE = re.compile(r"^sdr_mp_laststand_")', 1, true) ~= nil and t:find("or MP_UNUSABLE.search(name)", 1, true) ~= nil,
		"MP last-stand / revive clips: gun bone unusable (the medic's gun followed it everywhere)")
end
local U = {}
local f = io.open(ROOT .. "tif/gta/clips/zz_jgun.lua")
if f then for n in f:read("*a"):gmatch('%["([^"]+)"%] = true') do U[n] = true end end
check(U["sdr_mp_laststand_crouch_revive_loop_helper_2"] == true, "the generated table lists the MP revive helper clips")
check(U["sdr_com_buddy_revive_back_to_exposed_helper_4"] == nil, "MW22 buddy revives: gun bone decoded (0.38.64), off the unusable list")
local held = false
for _, part in ipairs({ "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13" }) do
	local hf = io.open(ROOT .. "tif/gta/clips/zz_jgun_h" .. part .. ".lua")
	if hf then
		local t = hf:read("*a")
		if t:find('H["sdr_com_buddy_revive_back_to_exposed_helper_4"]', 1, true) then held = true end
	end
end
check(held, "and the medic's gun follows the clip's own motion where he lets go of it")
check(body:find("Bd.CARRY_R = 0.35", 1, true) ~= nil and body:find("if r > Bd.CARRY_R then v = true break end", 1, true) ~= nil, "the seated sleep loop (gun 0.43 off the hand) carries the gun like its sit-down and wake-up")
print(string.format("passed %d, failed %d", pass, fail))
