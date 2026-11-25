-- Offline (0.35.4): cl_body's top() lists for legs and upper body are separate tables (they shared one: the gun code
-- read the upper-body list as the legs, jrotW stayed 0).
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
local src = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
local block = src:match("(local function top%(weights, n, sorted%).-\nlocal LEG_BUF, UB_BUF = {}, {}\n)")
check(block ~= nil, "top() takes its own buffer")
if block then
	local top, LB, UB = assert(load(block .. "return top, LEG_BUF, UB_BUF"))()
	local legW = { a = 0.7, b = 0.2, c = 0.1 }
	local legTop = top(legW, 3, LB)
	local ubTop = top({}, 2, UB)
	check(#legTop == 3 and legTop[1].clip == "a", "leg list intact after the upper-body list is built (" .. #legTop .. ")")
	check(#ubTop == 0 and legTop ~= ubTop, "separate tables")
end
check(src:find("top(st.legW, #A.LEG_SLOTS, LEG_BUF)", 1, true) and src:find("top(st.ubW, #A.UB_SLOTS, UB_BUF)", 1, true), "compose uses both buffers")
print(string.format("passed %d, failed %d", pass, fail))
