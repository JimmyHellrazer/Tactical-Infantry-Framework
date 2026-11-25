TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local names = {}
for n in pairs(clips) do if n:find("^mwt_") or n:find("^mwl_") then names[#names + 1] = n end end
table.sort(names)
for _, n in ipairs(names) do
	local c = clips[n]
	local cv = c.curve or {}
	local k = #cv
	local x, y, r = cv[k - 2] or 0, cv[k - 1] or 0, cv[k] or 0
	local d = math.sqrt(x * x + y * y)
	local dir = d > 1 and math.deg(math.atan2(y, x)) or 0
	print(string.format("%-26s dur %.2f  end x %6.1f y %6.1f  yaw %7.1f  dist %5.1f  dir %6.1f", n, c.dur, x, y, r, d, dir))
end
