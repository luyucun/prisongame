--[[
脚本名称: ShopConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/ShopConfig
版本: V2.1
职责: 商店配置数据与商品管理逻辑
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UnitConfig = require(script.Parent.UnitConfig)

local ShopConfig = {}

-- ==================== 商店配置表 ====================
--[[
商店数据结构说明：
- Shops[shopId] = {
    NPCName: 关联的NPC名称（用于自动识别商店ID）
    DisplayName: 商店显示名称
    Items: 商品列表数组
      - ItemType: 商品类型（"Unit" / "Skill"）
      - UnitId: 兵种ID（关联UnitConfig）
      - Price: 价格（可选，覆盖UnitConfig；nil则使用UnitConfig.Price）
      - Icon: 图标（可选，nil则使用UnitConfig.Icon）
      - Sort: 排序权重（数字越小越靠前）
      - Enabled: 是否上架（true/false）
      - LimitPerDay: 每日限购次数（0=不限购，V2.1暂不启用）
      - LimitTotal: 总限购次数（0=不限购，V2.1暂不启用）
      - UnlockStage: 解锁关卡（0=无限制，V2.1暂不启用）
  }
]]

ShopConfig.Shops = {
	-- ==================== 兵种商店 ====================
	["UnitShop"] = {
		NPCName = "KeepShoper01",        -- 关联NPC
		DisplayName = "兵种商店",
		RefreshInterval = 300,           -- 库存刷新间隔(秒) 5分钟（V2.1库存系统）
		Items = {
			-- Noob：基础近战单位
			{
				ItemType = "Unit",
				UnitId = "Noob",
				Price = 100,             -- 游戏币价格
				RobuxPrice = 10,         -- 罗布币价格（V2.1新增，此版本仅用于展示）
				DevProductId = "",       -- 开发者商品ID（V2.1新增，预留字段）
				Icon = nil,              -- nil使用UnitConfig.Icon
				Sort = 10,               -- 排序：最靠前
				Enabled = true,          -- 上架
				-- 库存系统字段（V2.1库存功能）
				RefreshProbability = 0.6,  -- 刷新概率（60%概率有库存）
				StockMin = 3,            -- 库存下限（刷新时最少数量）
				StockMax = 6,            -- 库存上限（刷新时最多数量）
				-- 预留扩展字段（V2.1暂不启用）
				LimitPerDay = 0,         -- 不限购
				LimitTotal = 0,
				UnlockStage = 0,         -- 无解锁条件
			},
			-- Rookie：进阶近战单位
			{
				ItemType = "Unit",
				UnitId = "Rookie",
				Price = 200,
				RobuxPrice = 20,         -- 罗布币价格（V2.1新增）
				DevProductId = "",       -- 开发者商品ID（V2.1新增）
				Icon = nil,
				Sort = 20,
				Enabled = true,
				-- 库存系统字段（V2.1库存功能）
				RefreshProbability = 0.5,
				StockMin = 2,
				StockMax = 5,
				-- 预留扩展字段
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- AK-47：远程单位
			{
				ItemType = "Unit",
				UnitId = "AK-47",
				Price = 300,             -- 可以设置不同于UnitConfig的价格
				RobuxPrice = 30,         -- 罗布币价格（V2.1新增）
				DevProductId = "",       -- 开发者商品ID（V2.1新增）
				Icon = nil,
				Sort = 30,
				Enabled = true,          -- 可以设置为false下架
				-- 库存系统字段（V2.1库存功能）
				RefreshProbability = 0.4,
				StockMin = 1,
				StockMax = 3,
				-- 预留扩展字段
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- Mafia：远程单位
			{
				ItemType = "Unit",
				UnitId = "Mafia",
				Price = nil,             -- nil则使用UnitConfig.Price
				RobuxPrice = 50,         -- 罗布币价格（V2.1新增）
				DevProductId = "",       -- 开发者商品ID（V2.1新增）
				Icon = nil,
				Sort = 40,
				Enabled = true,
				-- 库存系统字段（V2.1库存功能）
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 2,
				-- 预留扩展字段
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
		}
	},

	-- ==================== 技能商店（示例，暂不实现）====================
	-- ["SkillShop"] = {
	--     NPCName = "KeepShoper02",
	--     DisplayName = "技能商店",
	--     Items = {}
	-- },
}

-- ==================== 公共接口 ====================

--[[
根据NPC实例查找对应的商店ID
@param npc Instance - NPC模型实例
@return string|nil - 商店ID，未找到返回nil
]]
function ShopConfig.GetShopIdForNPC(npc)
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
	for shopId, shopData in pairs(ShopConfig.Shops) do
		if shopData.NPCName == npcName then
			return shopId
		end
	end

	return nil
end

--[[
获取商店商品列表（已过滤、排序）
@param shopId string - 商店ID
@param player Player - 玩家实例（用于检查解锁条件，V2.1暂不用）
@return table - 商品数据数组 {{UnitId, Name, Price, Icon, ...}, ...}
]]
function ShopConfig.GetShopItems(shopId, player)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		warn("[ShopConfig] 未找到商店: " .. tostring(shopId))
		return {}
	end

	local items = {}

	for _, itemConfig in ipairs(shopData.Items) do
		-- 检查是否上架
		if itemConfig.Enabled then
			-- 检查解锁条件（V2.1暂不启用，预留）
			-- if itemConfig.UnlockStage > 0 and player then
			--     local playerStage = GetPlayerCurrentStage(player)
			--     if playerStage < itemConfig.UnlockStage then
			--         goto continue
			--     end
			-- end

			-- 构造商品数据
			if itemConfig.ItemType == "Unit" then
				local unitId = itemConfig.UnitId
				local unitData = UnitConfig.GetUnitById(unitId)

				if unitData then
					local price = itemConfig.Price or unitData.Price
					local icon = itemConfig.Icon or unitData.Icon or "rbxassetid://0"

					table.insert(items, {
						UnitId = unitId,
						Name = unitData.Name,
						Price = price,
						Icon = icon,
						Description = unitData.Description,
						GridSize = unitData.GridSize,
						Quality = unitData.Quality or "Common",
						Type = unitData.Type,
						Sort = itemConfig.Sort,
						-- 战斗属性
						BaseHealth = UnitConfig.CalculateHealth(unitId, unitData.BaseLevel),
						BaseAttack = UnitConfig.CalculateAttack(unitId, unitData.BaseLevel),
						BaseAttackSpeed = unitData.BaseAttackSpeed,
						BaseAttackRange = unitData.BaseAttackRange,
						-- 罗布币相关字段（V2.1新增）
						RobuxPrice = itemConfig.RobuxPrice,
						DevProductId = itemConfig.DevProductId,
						-- 预留字段
						LimitPerDay = itemConfig.LimitPerDay,
						LimitTotal = itemConfig.LimitTotal,
					})
				else
					warn("[ShopConfig] UnitId不存在: " .. unitId)
				end
			end
			-- 后续可支持 ItemType == "Skill"
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
@param unitId string - 兵种ID
@param player Player - 玩家实例（用于检查限购，V2.1暂不用）
@return boolean - 是否在售
@return string - 失败原因（如果返回false）
]]
function ShopConfig.IsUnitOnSale(shopId, unitId, player)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		return false, "商店不存在"
	end

	-- 查找商品
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Unit" and itemConfig.UnitId == unitId then
			-- 检查上架状态
			if not itemConfig.Enabled then
				return false, "商品未上架"
			end

			-- 检查解锁条件（V2.1暂不启用）
			-- if itemConfig.UnlockStage > 0 and player then
			--     local playerStage = GetPlayerCurrentStage(player)
			--     if playerStage < itemConfig.UnlockStage then
			--         return false, "未解锁（需通关关卡" .. itemConfig.UnlockStage .. "）"
			--     end
			-- end

			-- 检查限购（V2.1暂不启用）
			-- if itemConfig.LimitPerDay > 0 or itemConfig.LimitTotal > 0 then
			--     -- 需要从DataManager获取购买记录
			--     -- local purchaseCount = GetPurchaseCount(player, unitId)
			--     -- if purchaseCount >= limit then
			--     --     return false, "已达限购次数"
			--     -- end
			-- end

			return true, "在售"
		end
	end

	return false, "商品不存在"
end

--[[
获取商品价格
@param shopId string - 商店ID
@param unitId string - 兵种ID
@return number|nil - 价格，未找到返回nil
]]
function ShopConfig.GetPrice(shopId, unitId)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		return nil
	end

	-- 查找商品配置
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Unit" and itemConfig.UnitId == unitId then
			-- 优先ShopConfig价格，回退UnitConfig
			local price = itemConfig.Price
			if price then
				return price
			else
				local unitData = UnitConfig.GetUnitById(unitId)
				return unitData and unitData.Price or nil
			end
		end
	end

	return nil
end

--[[
获取所有商店ID列表
@return table - 商店ID数组
]]
function ShopConfig.GetAllShopIds()
	local shopIds = {}
	for shopId, _ in pairs(ShopConfig.Shops) do
		table.insert(shopIds, shopId)
	end
	return shopIds
end

--[[
获取商店显示名称
@param shopId string - 商店ID
@return string - 显示名称
]]
function ShopConfig.GetShopDisplayName(shopId)
	local shopData = ShopConfig.Shops[shopId]
	return shopData and shopData.DisplayName or "未知商店"
end

--[[
验证ShopConfig配置完整性（用于调试）
@return boolean - 是否通过验证
@return table - 错误列表
]]
function ShopConfig.ValidateShopConfig()
	local errors = {}
	local success = true

	for shopId, shopData in pairs(ShopConfig.Shops) do
		-- 检查必要字段
		if not shopData.NPCName then
			table.insert(errors, string.format("商店[%s]缺少NPCName", shopId))
			success = false
		end

		if not shopData.Items or #shopData.Items == 0 then
			table.insert(errors, string.format("商店[%s]没有商品", shopId))
			success = false
		end

		-- 检查每个商品
		for i, itemConfig in ipairs(shopData.Items or {}) do
			if itemConfig.ItemType == "Unit" then
				local unitId = itemConfig.UnitId
				if not UnitConfig.IsValidUnit(unitId) then
					table.insert(errors, string.format(
						"商店[%s]商品[%d]的UnitId不存在: %s",
						shopId, i, unitId
					))
					success = false
				end
			end
		end
	end

	return success, errors
end

--[[
获取商品库存配置
@param shopId string - 商店ID
@param unitId string - 兵种ID
@return table|nil - 库存配置 {RefreshProbability, StockMin, StockMax}
]]
function ShopConfig.GetStockConfig(shopId, unitId)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		return nil
	end

	-- 查找商品配置
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Unit" and itemConfig.UnitId == unitId then
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
function ShopConfig.GetRefreshInterval(shopId)
	local shopData = ShopConfig.Shops[shopId]
	if shopData and shopData.RefreshInterval then
		return shopData.RefreshInterval
	end

	-- 使用GameConfig中的默认值
	local GameConfig = require(script.Parent.GameConfig)
	return GameConfig.Shop.DefaultRefreshInterval or 300
end

-- ==================== 回退机制：从UnitConfig生成默认列表 ====================
--[[
从UnitConfig生成默认商店列表（回退机制）
@return table - 商品数据数组
]]
function ShopConfig.GetFallbackItemList()
	local items = {}
	local sortCounter = 10

	for unitId, unitData in pairs(UnitConfig.GetAllUnits()) do
		table.insert(items, {
			UnitId = unitId,
			Name = unitData.Name,
			Price = unitData.Price,
			Icon = unitData.Icon or "rbxassetid://0",
			Description = unitData.Description,
			GridSize = unitData.GridSize,
			Quality = unitData.Quality or "Common",
			Type = unitData.Type,
			Sort = sortCounter,
			-- 战斗属性
			BaseHealth = UnitConfig.CalculateHealth(unitId, unitData.BaseLevel),
			BaseAttack = UnitConfig.CalculateAttack(unitId, unitData.BaseLevel),
			BaseAttackSpeed = unitData.BaseAttackSpeed,
			BaseAttackRange = unitData.BaseAttackRange,
		})
		sortCounter = sortCounter + 10
	end

	-- 按价格排序
	table.sort(items, function(a, b)
		return a.Price < b.Price
	end)

	return items
end

-- ==================== 初始化验证 ====================
local function Initialize()
	local success, errors = ShopConfig.ValidateShopConfig()
	if not success then
		warn("[ShopConfig] 配置验证失败:")
		for _, error in ipairs(errors) do
			warn("  - " .. error)
		end
	else
		print("[ShopConfig] 配置验证通过，共" .. #ShopConfig.GetAllShopIds() .. "个商店")
	end
end

-- 延迟初始化（确保UnitConfig已加载）
task.defer(Initialize)

return ShopConfig
