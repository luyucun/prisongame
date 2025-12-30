--[[
脚本名称: HouseConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/HouseConfig
版本: V2.8
]]

--[[
房屋配置模块
职责: 存储房屋升级相关的配置参数
V2.8新增: 根据通关章节替换房屋模型
]]

local HouseConfig = {}

-- ==================== 房屋升级配置 ====================
-- 配置规则：
-- RequiredChapter: 需要通关的章节数 (0表示初始房屋)
-- ModelName: 房屋模型名称 (在ReplicatedStorage/House下)
-- YOffset: Y轴偏移量，用于调整模型高度（可选，默认0）

HouseConfig.Houses = {
	-- 初始房屋 (通关0章，即一开始就有)
	{
		RequiredChapter = 0,
		ModelName = "PrisonLv1",
		Name = "The Stone Vault",
		IdleCoinsPerMinute = 8,
		IdleMaxHours = 14,
		Description = "Simple stone vault to start your wealth. Solid walls protect early gains.",
		Icon = "rbxassetid://123586009142390",
		YOffset = 0,  -- 基准房屋，不需要偏移
	},
	-- 通关第1章后解锁
	{
		RequiredChapter = 1,
		ModelName = "PrisonLv2",
		Name = "The Elite Ward",
		IdleCoinsPerMinute = 10,
		IdleMaxHours = 16,
		Description = "Reinforced steel with better security. Boosts AFK speed and capacity.",
		Icon = "rbxassetid://127176612735348",
		YOffset = 0,  -- 如果模型插入地面，调整这个值（正数向上，负数向下）
	},
	-- 通关第2章后解锁
	{
		RequiredChapter = 2,
		ModelName = "PrisonLv3",
		Name = "The Elite Ward",
		IdleCoinsPerMinute = 12,
		IdleMaxHours = 18,
		Description = "Advanced facilities with major boost. Faster coins and longer AFK.",
		Icon = "rbxassetid://102214435450404",
		YOffset = 0,  -- 如果模型插入地面，调整这个值（正数向上，负数向下）
	},
}

-- ==================== 工具函数 ====================

--[[
根据通关章节数获取应该使用的房屋模型名称
@param completedChapters number - 已通关的章节数
@return string - 房屋模型名称
]]
function HouseConfig.GetHouseModelByChapter(completedChapters)
	local houseConfig = HouseConfig.GetHouseByChapter(completedChapters)
	return houseConfig and houseConfig.ModelName or "PrisonLv1"
end

--[[
获取房屋模型路径
@param modelName string - 模型名称
@return string - 完整路径
]]
function HouseConfig.GetHouseModelPath(modelName)
	return "House/" .. modelName
end

--[[
判断是否需要升级房屋
@param currentModelName string - 当前房屋模型名称
@param completedChapters number - 已通关章节数
@return boolean, string - 是否需要升级, 新模型名称
]]
function HouseConfig.ShouldUpgradeHouse(currentModelName, completedChapters)
	local targetModel = HouseConfig.GetHouseModelByChapter(completedChapters)

	if targetModel ~= currentModelName then
		return true, targetModel
	end

	return false, currentModelName
end

--[[
获取所有房屋配置
@return table - 房屋配置列表
]]
function HouseConfig.GetAllHouses()
	return HouseConfig.Houses
end

--[[
获取指定房屋模型的Y偏移量
@param modelName string - 房屋模型名称
@return number - Y偏移量
]]
function HouseConfig.GetYOffset(modelName)
	for _, house in ipairs(HouseConfig.Houses) do
		if house.ModelName == modelName then
			return house.YOffset or 0
		end
	end
	return 0
end

--[[
根据模型名称获取房屋配置
@param modelName string - 模型名称
@return table|nil - 房屋配置
]]
function HouseConfig.GetHouseByModel(modelName)
	for _, house in ipairs(HouseConfig.Houses) do
		if house.ModelName == modelName then
			return house
		end
	end
	return nil
end

--[[
根据通关章节数获取对应房屋配置（最高解锁）
@param completedChapters number - 已通关的章节数
@return table - 房屋配置
]]
function HouseConfig.GetHouseByChapter(completedChapters)
	completedChapters = completedChapters or 0

	local bestHouse = HouseConfig.Houses[1]
	for _, house in ipairs(HouseConfig.Houses) do
		if completedChapters >= house.RequiredChapter then
			if house.RequiredChapter >= bestHouse.RequiredChapter then
				bestHouse = house
			end
		end
	end

	return bestHouse
end

--[[
根据通关章节数获取挂机配置
@param completedChapters number - 已通关的章节数
@return table - {CoinsPerMinute, MaxHours, MaxMinutes, House}
]]
function HouseConfig.GetIdleConfigByCompletedChapters(completedChapters)
	local house = HouseConfig.GetHouseByChapter(completedChapters)
	if not house then
		return nil
	end

	local maxHours = tonumber(house.IdleMaxHours) or 0
	local maxMinutes = maxHours > 0 and (maxHours * 60) or 0

	return {
		CoinsPerMinute = tonumber(house.IdleCoinsPerMinute) or 0,
		MaxHours = maxHours,
		MaxMinutes = maxMinutes,
		House = house,
	}
end

return HouseConfig
