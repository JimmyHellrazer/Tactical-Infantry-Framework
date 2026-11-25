-- Offline (0.36.0): recoil kicks. The clip table has the kick pools; cl_body's recoil_kicks() starts one per new shot
-- on the next of slots 5-7, plays it through and drops it; nothing during full-body actions / prone / launchers.
local pass, fail = 0, 0
local function check(c, what) if c then pass = pass + 1 else fail = fail + 1 print("FAIL: " .. what) end end
TIFG = { Clips = {} }
function TIFG.RegisterClips(pack, clips) TIFG.Clips[pack] = TIFG.Clips[pack] or {} for k, v in pairs(clips) do TIFG.Clips[pack][k] = v end end
dofile(CLIPS)
local clips = TIFG.Clips.mw_male
local pools = {}
for name, c in pairs(clips) do
	local kind, st = string.match(name, "^mwfk_(%a+)_(%a+)_%d+$")
	if kind then
		pools[kind .. "_" .. st] = (pools[kind .. "_" .. st] or 0) + 1
		check(c.kick == true and c.loop == false and c.dur >= 0.19 and c.dur < 1.5 or kind == "shotgun", name .. " is a short kick (" .. tostring(c.dur) .. ")")
		check(c.move[1] == 0 and c.move[2] == 0, name .. " has no root motion")
	end
end
for _, k in ipairs({ "rifle_st", "rifle_cr", "pistol_st", "shotgun_st", "shotgun_cr" }) do
	check((pools[k] or 0) > 0, "kick pool " .. k .. " (" .. tostring(pools[k]) .. ")")
end

-- recoil_kicks() from cl_body, with stubs.
local src = io.open(ROOT .. "tif/npc/cl_body.lua"):read("*a")
local block = src:match("(local KICK_SLOTS = .-\n)%-%- Checked twice a second")
check(block ~= nil, "recoil_kicks block")
local written = {}
local env = setmetatable({
	Bd = {}, A = { Seq = function(_, c) return c.seqN end },
	CreateClientConVar = function() return { GetFloat = function() return 1 end } end,
	write_slot = function(_, slot, seq, u, w) written[#written + 1] = { slot = slot, seq = seq, u = u, w = w } end,
}, { __index = _G })
local recoil_kicks = assert(load(block .. "\nreturn recoil_kicks", "rk", "t", env))()
local K = { rifle = { st = { { seqN = 1, dur = 0.33 } }, cr = { { seqN = 2, dur = 0.33 } } }, pistol = { st = { { seqN = 3, dur = 0.4 } } } }
local shotT, stance = 0, 0
local nw = {}
local ent = { GetTIFShotTime = function() return shotT end, GetTIFStance = function() return stance end,
	GetNW2Float = function(_, k, d) return nw[k] or d end, GetNW2Int = function(_, k, d) return nw[k] or d end }
local st = { vb = true, wkind = "rifle" }
local legs = { kicks = K }
recoil_kicks(ent, st, legs, 10)
check(#written == 0, "no shot yet: nothing")
shotT = 10
recoil_kicks(ent, st, legs, 10.0)
check(#written == 1 and written[1].slot == 5 and written[1].seq == 1, "first shot: standing rifle kick on slot 5")
for i = 1, 3 do shotT = 10 + i * 0.08 written = {} recoil_kicks(ent, st, legs, shotT) end
local slots = {}
for _, w in ipairs(written) do slots[w.slot] = true end
check(slots[5] and slots[6] and slots[7], "auto fire: kicks on slots 5, 6 and 7 at once")
written = {}
recoil_kicks(ent, st, legs, 11)
check(#written == 0, "all kicks finished after their length")
stance, shotT = 1, 12
written = {}
recoil_kicks(ent, st, legs, 12)
check(written[1] and written[1].seq == 2, "crouched: the crouched pool")
st.pistol, stance, shotT = true, 1, 13
written = {}
recoil_kicks(ent, st, legs, 13)
check(written[1] and written[1].seq == 3, "pistol crouched: falls back to the pistol standing pool")
st.pistol, st.fullBody, shotT = false, true, 14
written = {}
recoil_kicks(ent, st, legs, 14)
check(#written == 0, "full-body action: no kick")
st.fullBody, st.wkind, shotT = false, "rpg", 15
written = {}
recoil_kicks(ent, st, legs, 15)
check(#written == 0, "launcher: no kick")
st.wkind, shotT = "rifle", 16
written = {}
recoil_kicks(ent, st, legs, 30)
check(#written == 0, "a stale shot time (joining late) doesn't kick")
check(src:find("if st.flashAt and not (st.legs and st.legs.kicks) then", 1, true) ~= nil, "spine kick off where kick clips exist")

-- 0.38.6: whizby flinches are layers too (not the full-body stick-figure clips any more), not scaled by recoil.
do
	local st2 = { vb = true, wkind = "rifle" }
	local legs2 = { kicks = K, whizby = { { seqN = 21, dur = 1.0 }, { seqN = 22, dur = 1.0 } } }
	nw.tif_whizby_t, nw.tif_whizby_n = 50, 2
	written = {}
	recoil_kicks(ent, st2, legs2, 50.05)
	check(#written == 1 and written[1].seq == 22 and written[1].w == 1, "whizby: the flinch layer, full strength")
	written = {}
	recoil_kicks(ent, st2, legs2, 50.5)
	check(#written == 1 and written[1].seq == 22, "whizby: still playing half way")
	written = {}
	recoil_kicks(ent, st2, legs2, 51.2)
	check(#written == 0, "whizby: done after its length")
	nw.tif_whizby_t = 60
	st2.fullBody = true
	written = {}
	recoil_kicks(ent, st2, legs2, 60.05)
	check(#written == 0, "whizby: not over a full-body action")
	local only = { vb = true }
	nw.tif_whizby_t = 70
	written = {}
	recoil_kicks(ent, only, { whizby = legs2.whizby }, 70.05)
	check(#written == 1, "whizby works without kick pools")
	local sup = io.open(ROOT .. "tif/tactics/sv_suppression.lua"):read("*a")
	check(sup:find('SetNW2Float("tif_whizby_t", now)', 1, true) and not sup:find("Action.Play", 1, true), "server sends a whizby event, no full-body action")
end

-- 0.36.1: firing from cover, prone, bipods.
for _, k in ipairs({ "lean_ls", "lean_rs", "lean_lc", "lean_rc", "prone_pr" }) do
	check((pools[k] or 0) > 0, "kick pool " .. k .. " (" .. tostring(pools[k]) .. ")")
end
local kick_pool = env.Bd.KickPool
local KK = { rifle = { st = { "rst" }, cr = { "rcr" } }, pistol = { st = { "pst" } }, lean = { ls = { "lls" }, rc = { "lrc" } },
	prone = { pr = { "pr" } } }
local function pick(stt, stance)
	stance = stance or 0
	local e = { GetTIFStance = function() return stance end }
	local p, w = kick_pool(e, stt, KK)
	return p and p[1], w
end
check(pick({ wkind = "rifle", fullBody = true, actName = "mwc_ls_aim" }) == "lls", "leaning round a left standing corner: its lean kicks")
check(pick({ wkind = "rifle", fullBody = true, actName = "mwc_rc_aim" }) == "lrc", "right crouched corner: its lean kicks")
check(pick({ wkind = "rifle", fullBody = true, actName = "mwc_rs_aim" }) == "rst", "right standing corner without its own pool: standing kicks")
check(pick({ wkind = "rifle", fullBody = true, actName = "mwc_cr_aim" }) == "rcr", "over low cover: crouched kicks")
check(pick({ wkind = "rifle", fullBody = true, actName = "mwc_st_aim" }) == "rst", "over chest-high cover: standing kicks")
check(pick({ pistol = true, fullBody = true, actName = "mwc_lsp_aim" }) == "pst", "pistol in cover: pistol kicks")
check(pick({ wkind = "rifle", fullBody = true, actName = "mwc_ls_blind1" }) == nil, "blindfire: none (its own firing)")
check(pick({ wkind = "rifle", fullBody = true, actName = "mwc_ls_hide" }) == nil, "hiding: none")
local p, w = pick({ wkind = "rifle", fullBody = true, vbProne = 2, aim9 = { 1 } })
check(p == "pr" and w == 1, "lying and aiming: prone kicks")
check(pick({ wkind = "rifle", fullBody = true, vbProne = 2 }) == nil, "lying, gun down / crawling: none")
check(pick({ wkind = "rifle", fullBody = true, vbProne = 1, aim9 = { 1 } }) == nil, "getting down: none")
p, w = pick({ wkind = "lmg", fullBody = true, vbProne = 2, bipod = "set" })
check(p == "pr" and w == env.Bd.BIPOD_W, "prone bipod: prone kicks, softened")
p, w = pick({ wkind = "lmg", fullBody = true, actName = "mwb_crouch_aim" })
check(p == "rcr" and w == env.Bd.BIPOD_W, "low-wall bipod: crouched kicks, softened")
p, w = pick({ wkind = "lmg", fullBody = true, actName = "mwb_high_aim" })
check(p == "rst" and w == env.Bd.BIPOD_W, "ledge bipod: standing kicks, softened")
check(pick({ wkind = "rpg", fullBody = true, actName = "mwc_ls_aim" }) == nil, "launcher in cover: none")
print(string.format("passed %d, failed %d", pass, fail))
