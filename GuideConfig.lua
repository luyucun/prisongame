--[[
脚本名称: GuideConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/GuideConfig
]]

--[[
新手引导配置模块 V3.5
职责: 存储所有新手引导的配置信息
]]

local GuideConfig = {}

-- ==================== 引导类型枚举 ====================
GuideConfig.GuideType = {
	SHOP = "SHOP",           -- 引导前往兵种商店
	MAIL = "MAIL",           -- 引导前往挂机金币邮箱
}

-- ==================== 引导配置 ====================
-- 每个引导都有一个唯一的ID，用于数据存储和判断是否已完成
GuideConfig.Guides = {
	-- 引导1：前往兵种商店
	[1001] = {
		GuideId = 1001,
		GuideType = GuideConfig.GuideType.SHOP,
		Name = "ShopGuide",
		Description = "引导前往兵种商店",
		TargetName = "KeepShoper01",          -- 目标对象名称
		TriggerCondition = "FIRST_JOIN",      -- 触发条件：首次进入游戏
		ArrivalDistance = 10,                 -- 到达判定距离(studs)
		Sort = 1,                             -- 排序
		Enabled = true,                       -- 是否启用
	},

	-- 引导2：前往挂机金币邮箱
	[1002] = {
		GuideId = 1002,
		GuideType = GuideConfig.GuideType.MAIL,
		Name = "MailGuide",
		Description = "引导前往挂机奖励邮箱",
		TargetName = "Mail",                  -- 目标对象名称
		TriggerCondition = "HAS_IDLE_COINS",  -- 触发条件：有挂机金币可领取
		ArrivalDistance = 10,                 -- 到达判定距离(studs)
		Sort = 2,                             -- 排序
		Enabled = true,                       -- 是否启用
	},
}

-- ==================== 引导表现配置 ====================
GuideConfig.Display = {
	-- Guide资源路径（ReplicatedStorage/Effect下）
	GuideStartPartName = "Guide01",           -- 起始点Part名称（绑定到玩家）
	GuideEndPartName = "Guide02",             -- 终点Part名称（放在目标位置）

	-- 检测间隔
	CheckInterval = 0.5,                      -- 玩家距离检测间隔(秒)

	-- 引导资源父级
	EffectFolderPath = "Effect",              -- Effect文件夹路径（相对于ReplicatedStorage）

	-- 玩家绑定位置（绑定到躯干）
	AttachmentPartName = "Torso",             -- 绑定到玩家的哪个Part
	AttachmentOffset = Vector3.new(0, 1, 0),  -- 绑定偏移量
}

-- ==================== 公共接口 ====================

--[[
获取指定ID的引导配置
@param guideId number - 引导ID
@return table|nil - 引导配置
]]
function GuideConfig.GetGuideById(guideId)
	return GuideConfig.Guides[guideId]
end

--[[
检查引导ID是否有效
@param guideId number - 引导ID
@return boolean - 是否有效
]]
function GuideConfig.IsValidGuide(guideId)
	return GuideConfig.Guides[guideId] ~= nil
end

--[[
获取所有引导ID列表
@return table - 引导ID数组
]]
function GuideConfig.GetAllGuideIds()
	local ids = {}
	for guideId, _ in pairs(GuideConfig.Guides) do
		table.insert(ids, guideId)
	end
	-- 按Sort排序
	table.sort(ids, function(a, b)
		local guideA = GuideConfig.Guides[a]
		local guideB = GuideConfig.Guides[b]
		return (guideA.Sort or 0) < (guideB.Sort or 0)
	end)
	return ids
end

--[[
获取指定类型的引导配置
@param guideType string - 引导类型
@return table|nil - 引导配置
]]
function GuideConfig.GetGuideByType(guideType)
	for _, guide in pairs(GuideConfig.Guides) do
		if guide.GuideType == guideType then
			return guide
		end
	end
	return nil
end

--[[
获取所有启用的引导
@return table - 启用的引导配置数组
]]
function GuideConfig.GetEnabledGuides()
	local guides = {}
	for _, guide in pairs(GuideConfig.Guides) do
		if guide.Enabled then
			table.insert(guides, guide)
		end
	end
	-- 按Sort排序
	table.sort(guides, function(a, b)
		return (a.Sort or 0) < (b.Sort or 0)
	end)
	return guides
end

--[[
获取引导数量
@return number - 引导总数
]]
function GuideConfig.GetGuideCount()
	local count = 0
	for _ in pairs(GuideConfig.Guides) do
		count = count + 1
	end
	return count
end

return GuideConfig
