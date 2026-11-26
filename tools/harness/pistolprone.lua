local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local function src(p) return io.open(ROOT .. p):read("*a") end
local an, body, cm, wp = src("tif/npc/sh_anim.lua"), src("tif/npc/cl_body.lua"), src("tif/tactics/sv_cover_mw.lua"), src("tif/npc/sv_weapon.lua")
check(an:find("L.prone.pistol = { idle = clips.mwp_pstl_idle, aim = clips.mwp_pstl_aim, up = clips.mwp_pstl_up,", 1, true) ~= nil, "the prone set gets a pistol table")
check(body:find("local PRp = st.pistol and PR.pistol or nil", 1, true) ~= nil, "pistol out lying down: the pistol prone clips")
check(body:find("if PRp and st.vbProne == 3 and PRp.up then tr = PRp.up end", 1, true) ~= nil, "getting up with a pistol: the pistol get-up")
check(body:find("or tr == (PRp and PRp.up)) and PR.up) and PR.up.dur", 1, true) ~= nil, "stretched to the rifle get-up the server times")
check(body:find("local AIMc = (PRp and PRp.aim) or PR.aim", 1, true) ~= nil and body:find("st.aim9 = still and AIMc.aim9 or nil", 1, true) ~= nil, "pistol prone aim blend")
check(body:find("add(LT, still and AIMc or IDLEc, 1 - moveK)", 1, true) ~= nil, "pistol prone idle / aim")
check(body:find("if PRp and PRp.crawl8 and math.abs(relAng) < 35 then", 1, true) ~= nil, "crawling forward with a pistol: its own crawl; other ways the rifle crawl")
check(cm:find('local name = "mwc_" .. cov.t .. (slot == "secondary" and "_to_pistol" or "_to_rifle")', 1, true) ~= nil, "in cover: the cover type's switch clip")
check(cm:find('if cov.phase ~= "idle" and cov.phase ~= "look" and cov.phase ~= "twitch" then return nil end', 1, true) ~= nil, "only from settled cover")
check(cm:find('if phase == "switch" then\n\t\tf.want = false\n\t\tif now >= cov.phaseEnd then start_hide(npc, cov, now) end', 1, true) ~= nil, "no firing through the switch, back to hiding (with the new weapon's set) after")
check(wp:find("local covClip = CBm and CBm.PlaySwitch and CBm.PlaySwitch(npc, slot)", 1, true) ~= nil and wp:find("if covClip then opts = opts or {} opts.clip = covClip end", 1, true) ~= nil,
	"the weapon swap times itself off the cover clip's own notes")
print(string.format("passed %d, failed %d", pass, fail))
