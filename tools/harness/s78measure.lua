TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local names = {}
for n in pairs(clips) do if n:find("^mwv_") or n:find("^mwls_") or n:find("^mwg_") or n:find("^mwc_ls_pain_torso_md") then names[#names + 1] = n end end
table.sort(names)
for _, n in ipairs(names) do
	local c = clips[n]
	local cv = c.curve or {}
	local k = #cv
	local x, y, r = cv[k - 2] or 0, cv[k - 1] or 0, cv[k] or 0
	local z = c.zcurve and c.zcurve[#c.zcurve] or 0
	local zmax = 0
	for _, v in ipairs(c.zcurve or {}) do zmax = math.max(zmax, v) end
	local tag = ""
	for _, t in ipairs(c.tags or {}) do if type(t[4]) == "table" and t[4].MoveEvent then tag = tag .. t[4].MoveEvent .. "@" .. string.format("%.2f", t[2]) .. " " end end
	print(string.format("%-28s dur %5.2f end x %6.1f y %6.1f yaw %6.1f z %6.1f zmax %5.1f speed %s %s", n, c.dur, x, y, r, z, zmax, tostring(c.speed), tag))
end
