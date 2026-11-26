function EFFECT:Init(data)
	local ent = data:GetEntity()
	local start = data:GetStart()
	local Bd = TIF and TIF.Body

	if IsValid(ent) and Bd and Bd.MuzzleWorld then
		local at = Bd.MuzzleWorld(ent)
		if at then
			start = at.Pos
		end
	end

	local ed = EffectData()
	ed:SetStart(start)
	ed:SetOrigin(data:GetOrigin())
	ed:SetScale(6000)
	ed:SetEntity(ent)
	util.Effect("Tracer", ed)
end

function EFFECT:Think()
	return false
end

function EFFECT:Render() end
