--[[
=====================================================
脚本名称: SkillShopConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/SkillShopConfig.lua
版本: V3.1
=====================================================

功能描述:
- 定义技能商店的商品配置
- 提供库存刷新概率和数量配置
- 与兵种商店共享刷新周期

=====================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillConfig = require(script.Parent.SkillConfig)

local SkillShopConfig = {}

-- ==================== 商店配置表 ====================
--[[
商店数据结构说明：
- Shops[shopId] = {
    NPCName: 关联的NPC名称（用于自动识别商店ID）
    DisplayName: 商店显示名称
    RefreshInterval: 库存刷新间隔（与兵种商店共享，此处仅作备用）
    Items: 商品列表数组
      - ItemType: 商品类型（"Skill"）
      - SkillId: 技能ID（关联SkillConfig）
      - Price: 金币价格
      - RobuxPrice: 罗布币价格
      - DevProductId: 开发者商品ID
      - RefreshProbability: 刷新概率（0-1）
      - StockMin: 库存下限
      - StockMax: 库存上限
      - Sort: 排序权重（数字越小越靠前）
      - Enabled: 是否上架（true/false）
  }
]]

SkillShopConfig.Shops = {
	-- ==================== 技能商店 ====================
	["SkillShop"] = {
		NPCName = "KeepShoper02",        -- 关联NPC（技能商人）
		DisplayName = "Skill Shop",
		RefreshInterval = 300,           -- 库存刷新间隔(秒) 5分钟（与兵种商店共享）
		Items = {
			-- 1001: 喷水枪
			{
				ItemType = "Skill",
				SkillId = 1001,
				Price = 200,             -- 金币价格
				RobuxPrice = 10,         -- 罗布币价格
				DevProductId = "3476850130",       -- 开发者商品ID（需在Roblox开发者门户配置）
				RefreshProbability = 0.8, -- 100%概率刷新
				StockMin = 3,
				StockMax = 5,
				Sort = 10,
				Enabled = true,
			},
			-- 1002: 毒气炸弹
			{
				ItemType = "Skill",
				SkillId = 1002,
				Price = 300,
				RobuxPrice = 10,
				DevProductId = "3476850326",
				RefreshProbability = 0.5, -- 100%概率刷新
				StockMin = 3,
				StockMax = 5,
				Sort = 20,
				Enabled = true,
			},
			-- 1003: 大火
			{
				ItemType = "Skill",
				SkillId = 1003,
				Price = 600,
				RobuxPrice = 15,
				DevProductId = "3476850400",
				RefreshProbability = 0.4, -- 100%概率刷新
				StockMin = 1,
				StockMax = 2,
				Sort = 30,
				Enabled = true,
			},
		}
	},
}

-- ==================== 公共接口 ====================

--[[
根据NPC实例查找对应的商店ID
@param npc Instance - NPC模型实例
@return string|nil - 商店ID，未找到返回nil
]]
function SkillShopConfig.GetShopIdForNPC(npc)
	if not npc then return nil end

	-- 优先读取NPC节点的Attribute或StringValue
	local shopIdAttr = npc:GetAttribute("ShopId")
	if shopIdAttr then
		return shopIdAttr
	end

	local shopIdValue = npc:FindFirstChild("ShopId")
	if shopIdValue and shopIdValue:IsA("StringValue") then
		return shopIdValue.Value
	end

	-- 回退：按NPC名称匹配
	local npcName = npc.Name
	for shopId, shopData in pairs(SkillShopConfig.Shops) do
		if shopData.NPCName == npcName then
			return shopId
		end
	end

	return nil
end

--[[
获取商店商品列表（已过滤、排序）
@param shopId string - 商店ID
@param player Player - 玩家实例（用于检查解锁条件，暂不用）
@return table - 商品数据数组 {{SkillId, Name, Price, Icon, ...}, ...}
]]
function SkillShopConfig.GetShopItems(shopId, player)
	local shopData = SkillShopConfig.Shops[shopId]
	if not shopData then
		warn("[SkillShopConfig] 未找到商店: " .. tostring(shopId))
		return {}
	end

	local items = {}

	for _, itemConfig in ipairs(shopData.Items) do
		-- 检查是否上架
		if itemConfig.Enabled then
			if itemConfig.ItemType == "Skill" then
				local skillId = itemConfig.SkillId
				local skillData = SkillConfig.GetSkillById(skillId)

				if skillData then
					local price = itemConfig.Price
					if price and price > 0 then
						table.insert(items, {
							SkillId = skillId,
							Name = skillData.Name,
							Price = price,
							Icon = skillData.Icon or "rbxassetid://0",
							SkillType = skillData.SkillType,
							EffectType = skillData.EffectType,
							Range = skillData.Range,
							Description = skillData.Extra and skillData.Extra.Description or "",
							Sort = itemConfig.Sort,
							-- 罗布币相关字段
							RobuxPrice = itemConfig.RobuxPrice,
							DevProductId = itemConfig.DevProductId,
						})
					else
						warn(string.format(
							"[SkillShopConfig] 商品[%d]价格配置无效: %s，请检查配置",
							skillId, tostring(price)
							))
					end
				else
					warn("[SkillShopConfig] SkillId不存在: " .. skillId)
				end
			end
		end
	end

	-- 按Sort排序
	table.sort(items, function(a, b)
		return a.Sort < b.Sort
	end)

	return items
end

--[[
检查商品是否在售
@param shopId string - 商店ID
@param skillId number - 技能ID
@param player Player - 玩家实例
@return boolean - 是否在售
@return string - 失败原因（如果返回false）
]]
function SkillShopConfig.IsSkillOnSale(shopId, skillId, player)
	local shopData = SkillShopConfig.Shops[shopId]
	if not shopData then
		return false, "商店不存在"
	end

	-- 查找商品
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Skill" and itemConfig.SkillId == skillId then
			-- 检查上架状态
			if not itemConfig.Enabled then
				return false, "商品未上架"
			end

			return true, "在售"
		end
	end

	return false, "商品不存在"
end

--[[
获取商品价格
@param shopId string - 商店ID
@param skillId number - 技能ID
@return number|nil - 价格，未找到返回nil
]]
function SkillShopConfig.GetPrice(shopId, skillId)
	local shopData = SkillShopConfig.Shops[shopId]
	if not shopData then
		return nil
	end

	-- 查找商品配置
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Skill" and itemConfig.SkillId == skillId then
			return itemConfig.Price
		end
	end

	return nil
end

--[[
获取商品罗布币价格
@param shopId string - 商店ID
@param skillId number - 技能ID
@return number|nil - 罗布币价格，未找到返回nil
]]
function SkillShopConfig.GetRobuxPrice(shopId, skillId)
	local shopData = SkillShopConfig.Shops[shopId]
	if not shopData then
		return nil
	end

	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Skill" and itemConfig.SkillId == skillId then
			return itemConfig.RobuxPrice
		end
	end

	return nil
end

--[[
获取商品开发者商品ID
@param shopId string - 商店ID
@param skillId number - 技能ID
@return string|nil - DevProductId，未找到返回nil
]]
function SkillShopConfig.GetDevProductId(shopId, skillId)
	local shopData = SkillShopConfig.Shops[shopId]
	if not shopData then
		return nil
	end

	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Skill" and itemConfig.SkillId == skillId then
			return itemConfig.DevProductId
		end
	end

	return nil
end

--[[
根据DevProductId查找对应的技能ID和商店ID
@param devProductId string - 开发者商品ID
@return number|nil - 技能ID，未找到返回nil
@return string|nil - 商店ID
]]
function SkillShopConfig.FindSkillByDevProductId(devProductId)
	local devProductIdStr = tostring(devProductId)
	for shopId, shopData in pairs(SkillShopConfig.Shops) do
		for _, itemConfig in ipairs(shopData.Items) do
			if itemConfig.ItemType == "Skill" and tostring(itemConfig.DevProductId) == devProductIdStr then
				return itemConfig.SkillId, shopId
			end
		end
	end
	return nil, nil
end

--[[
获取所有商店ID列表
@return table - 商店ID数组
]]
function SkillShopConfig.GetAllShopIds()
	local shopIds = {}
	for shopId, _ in pairs(SkillShopConfig.Shops) do
		table.insert(shopIds, shopId)
	end
	return shopIds
end

--[[
获取商店显示名称
@param shopId string - 商店ID
@return string - 显示名称
]]
function SkillShopConfig.GetShopDisplayName(shopId)
	local shopData = SkillShopConfig.Shops[shopId]
	return shopData and shopData.DisplayName or "未知商店"
end

--[[
获取商品库存配置
@param shopId string - 商店ID
@param skillId number - 技能ID
@return table|nil - 库存配置 {RefreshProbability, StockMin, StockMax}
]]
function SkillShopConfig.GetStockConfig(shopId, skillId)
	local shopData = SkillShopConfig.Shops[shopId]
	if not shopData then
		return nil
	end

	-- 查找商品配置
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Skill" and itemConfig.SkillId == skillId then
			return {
				RefreshProbability = itemConfig.RefreshProbability or 1.0,
				StockMin = itemConfig.StockMin or 1,
				StockMax = itemConfig.StockMax or 999,
			}
		end
	end

	return nil
end

--[[
获取商店刷新间隔
@param shopId string - 商店ID
@return number - 刷新间隔（秒）
]]
function SkillShopConfig.GetRefreshInterval(shopId)
	local shopData = SkillShopConfig.Shops[shopId]
	if shopData and shopData.RefreshInterval then
		return shopData.RefreshInterval
	end

	-- 使用GameConfig中的默认值
	local GameConfig = require(script.Parent.GameConfig)
	return GameConfig.Shop.DefaultRefreshInterval or 300
end

--[[
验证SkillShopConfig配置完整性（用于调试）
@return boolean - 是否通过验证
@return table - 错误列表
]]
function SkillShopConfig.ValidateShopConfig()
	local errors = {}
	local success = true

	for shopId, shopData in pairs(SkillShopConfig.Shops) do
		local shopIdStr = tostring(shopId)

		-- 检查必要字段
		if not shopData.NPCName then
			table.insert(errors, string.format("商店[%s]缺少NPCName", shopIdStr))
			success = false
		end

		if not shopData.Items or #shopData.Items == 0 then
			table.insert(errors, string.format("商店[%s]没有商品", shopIdStr))
			success = false
		end

		-- 检查每个商品
		for i, itemConfig in ipairs(shopData.Items or {}) do
			if itemConfig.ItemType == "Skill" then
				local skillId = itemConfig.SkillId
				if not SkillConfig.IsValidSkill(skillId) then
					table.insert(errors, string.format(
						"商店[%s]商品[%d]的SkillId不存在: %s",
						shopIdStr, i, tostring(skillId)
						))
					success = false
				end
			end
		end
	end

	return success, errors
end

-- ==================== 初始化验证 ====================
local function Initialize()
	local success, errors = SkillShopConfig.ValidateShopConfig()
	if not success then
		warn("[SkillShopConfig] 配置验证失败:")
		for _, err in ipairs(errors) do
			warn("  - " .. err)
		end
	else
		print("[SkillShopConfig] 配置验证通过，共" .. #SkillShopConfig.GetAllShopIds() .. "个商店")
	end
end

-- 延迟初始化（确保SkillConfig已加载）
task.defer(Initialize)

return SkillShopConfig
