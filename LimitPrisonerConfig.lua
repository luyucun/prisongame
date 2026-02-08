--[[
脚本名称: LimitPrisonerConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/LimitPrisonerConfig
版本: V6.0
]]

local LimitPrisonerConfig = {}

LimitPrisonerConfig.RefreshHoursUtc = { 0 }
LimitPrisonerConfig.Proximity = {
	OpenDistance = 8,
	HoldDuration = 0,
	KeyCode = Enum.KeyCode.E,
}

LimitPrisonerConfig.Prisoners = {
	{
		UnitId = "10021",
		Weight = 25,
		GoldPrice = 50000,
		RobuxPrice = 899,
		DevProductId = 3472104793,
		HandcuffCost = 3,
	},
	{
		UnitId = "10022",
		Weight = 25,
		GoldPrice = 60000,
		RobuxPrice = 939,
		DevProductId = 3472105103,
		HandcuffCost = 3,
	},
	{
		UnitId = "10023",
		Weight = 25,
		GoldPrice = 80000,
		RobuxPrice = 999,
		DevProductId = 3472104998,
		HandcuffCost = 3,
	},
	{
		UnitId = "10024",
		Weight = 13,
		GoldPrice = 120000,
		RobuxPrice = 1099,
		DevProductId = 3472105858,
		HandcuffCost = 4,
	},
	{
		UnitId = "10025",
		Weight = 13,
		GoldPrice = 140000,
		RobuxPrice = 1199,
		DevProductId = 3472105595,
		HandcuffCost = 4,
	},
}

function LimitPrisonerConfig.GetPrisoners()
	return LimitPrisonerConfig.Prisoners
end

function LimitPrisonerConfig.GetPrisonerByUnitId(unitId)
	local target = tostring(unitId or "")
	for _, prisoner in ipairs(LimitPrisonerConfig.Prisoners) do
		if tostring(prisoner.UnitId) == target then
			return prisoner
		end
	end
	return nil
end

function LimitPrisonerConfig.GetPrisonerByDevProductId(productId)
	local target = tostring(productId or "")
	for _, prisoner in ipairs(LimitPrisonerConfig.Prisoners) do
		if tostring(prisoner.DevProductId or "") == target then
			return prisoner
		end
	end
	return nil
end

function LimitPrisonerConfig.RollPrisoner()
	local totalWeight = 0
	for _, prisoner in ipairs(LimitPrisonerConfig.Prisoners) do
		local weight = tonumber(prisoner.Weight) or 0
		if weight > 0 then
			totalWeight = totalWeight + weight
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = math.random(1, totalWeight)
	local current = 0
	for _, prisoner in ipairs(LimitPrisonerConfig.Prisoners) do
		local weight = tonumber(prisoner.Weight) or 0
		if weight > 0 then
			current = current + weight
			if roll <= current then
				return prisoner
			end
		end
	end

	return nil
end

return LimitPrisonerConfig
