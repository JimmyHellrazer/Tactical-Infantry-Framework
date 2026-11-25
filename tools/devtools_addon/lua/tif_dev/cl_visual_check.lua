-- Faction model check on this client (from config/sh_packs.lua, 0.38.11).

concommand.Add("tif_visual_check", function() TIF.VisualCheck(true) end, nil,
	"List faction models that can't dress the soldier body on this client")
