AddCSLuaFile()

ENT.Type = "point"
ENT.PrintName = "TIF group"
ENT.Spawnable = false

function ENT:KeyValue(k, v)
	if k == "tif_faction" then self.tifFaction = v
	elseif k == "tif_count" then self.tifCount = tonumber(v) end
end

if CLIENT then return end

hook.Add("PlayerSpawnedNPC", "tif_spawner", function(ply, ent)
	if IsValid(ent) and ent:GetClass() == "tif_spawner" then ent.tifPly = ply end
end)

function ENT:Initialize()

	timer.Simple(0, function()
		if not IsValid(self) then return end
		local faction = self.tifFaction or "insurgents"
		local n = math.Clamp(self.tifCount or 4, 1, 12)
		local mix = {}
		for i = 1, n do mix[i] = (TIF.SquadMix and TIF.SquadMix[i]) or (i == 1 and "leader" or "rifleman") end
		local ply = self.tifPly or self:GetCreator()
		if TIF.SpawnSoldiers and TIF.Factions[faction] then
			TIF.SpawnSoldiers(IsValid(ply) and ply or nil, faction, n, nil, self:GetPos(), IsValid(ply) and "away" or "random", { archetypes = mix })
		end
		self:Remove()
	end)
end
