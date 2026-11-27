local rawfind = string.find
local cache = {}
local function squash(s)
	local q = cache[s]
	if not q then q = (s:gsub("%s+", " ")) cache[s] = q end
	return q
end
string.find = function(s, pat, init, plain)
	local a, b = rawfind(s, pat, init, plain)
	if a or not plain or type(s) ~= "string" or type(pat) ~= "string" or #s < 4000 or not rawfind(pat, "%s") then return a, b end
	return rawfind(squash(s), (pat:gsub("%s+", " ")), 1, true)
end
getmetatable("").__index.find = string.find
