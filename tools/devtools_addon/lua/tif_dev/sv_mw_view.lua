-- Stage 1 checks for the MW19 host "mw_male" (registered with TIF from lua/tif/gta/characters + clips).
--   tif_mw_view list                     print the roles (TIF clip names) with their MW19 source clip
--   tif_mw_view <role|number|next> [still]   play a role at your crosshair; it walks its root motion unless "still"
--   tif_mw_view_pm <playermodel path>    bone-merge a playermodel on the viewer ("" = show the Breen host body)
--   tif_mw_view_clear                    remove the viewer
if CLIENT then return end

local function roles()
	local set = TIFG and TIFG.Clips and TIFG.Clips.mw_male
	local out = {}
	for name in pairs(set or {}) do out[#out + 1] = name end
	table.sort(out)
	return out, set
end

local viewer
local nextIdx = 0

local function say(ply, msg)
	if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end

concommand.Add("tif_mw_view", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local list, set = roles()
	if #list == 0 then say(ply, "tif_mw_view: mw_male clips aren't registered (is TIF loaded?)") return end
	local want = args[1] or "list"
	if want == "list" then
		for i, n in ipairs(list) do say(ply, string.format("%3d  %-40s %s", i, n, set[n].from or "")) end
		return
	end
	local role
	if want == "next" then
		nextIdx = nextIdx % #list + 1
		role = list[nextIdx]
	elseif tonumber(want) then
		role = list[tonumber(want)]
	elseif set[want] then
		role = want
	else
		for _, n in ipairs(list) do if string.find(n, want, 1, true) then role = n break end end
	end
	if not role then say(ply, "tif_mw_view: no role matches " .. want) return end

	if not IsValid(viewer) then
		local tr = IsValid(ply) and ply:GetEyeTrace()
		viewer = ents.Create("tif_mw_viewer")
		viewer:SetPos(tr and tr.HitPos or vector_origin)
		viewer:SetAngles(Angle(0, IsValid(ply) and (ply:GetAngles().y + 180) or 0, 0))
		viewer:Spawn()
	end
	viewer.origin = viewer.origin or viewer:GetPos()
	viewer:SetPos(viewer.origin)
	viewer:SetAngles(Angle(0, viewer.yaw or viewer:GetAngles().y, 0))
	viewer:SetRole(role)
	viewer:SetTravel(args[2] ~= "still")
	viewer:SetStart(CurTime())
	local c = set[role]
	say(ply, string.format("tif_mw_view: %s (%s) %.2fs%s, travel %.0f, speed %.0f", role, c.from or "?", c.dur,
		c.loop and " loop" or "", math.sqrt(c.move[1] ^ 2 + c.move[2] ^ 2), c.speed or 0))
end)

concommand.Add("tif_mw_view_pm", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	if IsValid(viewer) then viewer:SetPlayermodel(args[1] or "") end
end)

concommand.Add("tif_mw_view_clear", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	if IsValid(viewer) then viewer:Remove() end
end)
