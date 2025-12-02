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
      - Price: 价格（必须设置，不再使用UnitConfig回退）
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
			-- 10001: Noob
			{
				ItemType = "Unit",
				UnitId = "10001",
				Price = 200,             -- 明确价格：200金币
				RobuxPrice = 10,
				DevProductId = "",
				Icon = nil,
				Sort = 10,
				Enabled = true,
				RefreshProbability = 0.6,
				StockMin = 3,
				StockMax = 6,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10002: Baseball
			{
				ItemType = "Unit",
				UnitId = "10002",
				Price = 200,
				RobuxPrice = 10,
				DevProductId = "",
				Icon = nil,
				Sort = 20,
				Enabled = true,
				RefreshProbability = 0.6,
				StockMin = 3,
				StockMax = 6,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10003: Mafia
			{
				ItemType = "Unit",
				UnitId = "10003",
				Price = 200,
				RobuxPrice = 10,
				DevProductId = "",
				Icon = nil,
				Sort = 30,
				Enabled = true,
				RefreshProbability = 0.5,
				StockMin = 2,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10004: MP5
			{
				ItemType = "Unit",
				UnitId = "10004",
				Price = 300,
				RobuxPrice = 10,
				DevProductId = "",
				Icon = nil,
				Sort = 40,
				Enabled = true,
				RefreshProbability = 0.5,
				StockMin = 2,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10005: Rookie
			{
				ItemType = "Unit",
				UnitId = "10005",
				Price = 400,
				RobuxPrice = 15,
				DevProductId = "",
				Icon = nil,
				Sort = 50,
				Enabled = true,
				RefreshProbability = 0.5,
				StockMin = 2,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10006: Batons
			{
				ItemType = "Unit",
				UnitId = "10006",
				Price = 500,
				RobuxPrice = 15,
				DevProductId = "",
				Icon = nil,
				Sort = 60,
				Enabled = true,
				RefreshProbability = 0.5,
				StockMin = 2,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10007: Florida
			{
				ItemType = "Unit",
				UnitId = "10007",
				Price = 600,
				RobuxPrice = 15,
				DevProductId = "",
				Icon = nil,
				Sort = 70,
				Enabled = true,
				RefreshProbability = 0.4,
				StockMin = 2,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10008: Shotgun
			{
				ItemType = "Unit",
				UnitId = "10008",
				Price = 800,
				RobuxPrice = 15,
				DevProductId = "",
				Icon = nil,
				Sort = 80,
				Enabled = true,
				RefreshProbability = 0.4,
				StockMin = 2,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10009: Hitter
			{
				ItemType = "Unit",
				UnitId = "10009",
				Price = 1000,
				RobuxPrice = 20,
				DevProductId = "",
				Icon = nil,
				Sort = 90,
				Enabled = true,
				RefreshProbability = 0.4,
				StockMin = 2,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10010: Mama
			{
				ItemType = "Unit",
				UnitId = "10010",
				Price = 1200,
				RobuxPrice = 20,
				DevProductId = "",
				Icon = nil,
				Sort = 100,
				Enabled = true,
				RefreshProbability = 0.4,
				StockMin = 2,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10011: Cowboy
			{
				ItemType = "Unit",
				UnitId = "10011",
				Price = 1500,
				RobuxPrice = 20,
				DevProductId = "",
				Icon = nil,
				Sort = 110,
				Enabled = true,
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10012: AK47
			{
				ItemType = "Unit",
				UnitId = "10012",
				Price = 1800,
				RobuxPrice = 20,
				DevProductId = "",
				Icon = nil,
				Sort = 120,
				Enabled = true,
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10013: OG
			{
				ItemType = "Unit",
				UnitId = "10013",
				Price = 2200,
				RobuxPrice = 25,
				DevProductId = "",
				Icon = nil,
				Sort = 130,
				Enabled = true,
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10014: Samurai
			{
				ItemType = "Unit",
				UnitId = "10014",
				Price = 2500,
				RobuxPrice = 25,
				DevProductId = "",
				Icon = nil,
				Sort = 140,
				Enabled = true,
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10015: Robocop
			{
				ItemType = "Unit",
				UnitId = "10015",
				Price = 3000,
				RobuxPrice = 25,
				DevProductId = "",
				Icon = nil,
				Sort = 150,
				Enabled = true,
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10016: S.W.A.T
			{
				ItemType = "Unit",
				UnitId = "10016",
				Price = 3500,
				RobuxPrice = 25,
				DevProductId = "",
				Icon = nil,
				Sort = 160,
				Enabled = true,
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10017: Athlete
			{
				ItemType = "Unit",
				UnitId = "10017",
				Price = 4000,
				RobuxPrice = 30,
				DevProductId = "",
				Icon = nil,
				Sort = 170,
				Enabled = true,
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10018: Beast
			{
				ItemType = "Unit",
				UnitId = "10018",
				Price = 4500,
				RobuxPrice = 30,
				DevProductId = "",
				Icon = nil,
				Sort = 180,
				Enabled = true,
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10019: Enforcer
			{
				ItemType = "Unit",
				UnitId = "10019",
				Price = 5000,
				RobuxPrice = 30,
				DevProductId = "",
				Icon = nil,
				Sort = 190,
				Enabled = true,
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10020: Tank
			{
				ItemType = "Unit",
				UnitId = "10020",
				Price = 6000,
				RobuxPrice = 30,
				DevProductId = "",
				Icon = nil,
				Sort = 200,
				Enabled = true,
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10021: Muscular
			{
				ItemType = "Unit",
				UnitId = "10021",
				Price = 7000,
				RobuxPrice = 30,
				DevProductId = "",
				Icon = nil,
				Sort = 210,
				Enabled = true,
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10022: CarThief
			{
				ItemType = "Unit",
				UnitId = "10022",
				Price = 8000,
				RobuxPrice = 40,
				DevProductId = "",
				Icon = nil,
				Sort = 220,
				Enabled = true,
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10023: Worker
			{
				ItemType = "Unit",
				UnitId = "10023",
				Price = 9000,
				RobuxPrice = 40,
				DevProductId = "",
				Icon = nil,
				Sort = 230,
				Enabled = true,
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10024: FBI
			{
				ItemType = "Unit",
				UnitId = "10024",
				Price = 10000,
				RobuxPrice = 40,
				DevProductId = "",
				Icon = nil,
				Sort = 240,
				Enabled = true,
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10025: Sapper
			{
				ItemType = "Unit",
				UnitId = "10025",
				Price = 12000,
				RobuxPrice = 40,
				DevProductId = "",
				Icon = nil,
				Sort = 250,
				Enabled = true,
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
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
					-- V2.1修复：强制使用ShopConfig价格，不再回退到UnitConfig
					local price = itemConfig.Price
					if price and price > 0 then
						-- 价格有效，添加商品
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
						-- 价格无效，跳过此商品
						warn(string.format(
							"[ShopConfig] 商品[%s]价格配置无效: %s，请检查配置",
							unitId, tostring(price)
						))
					end
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
	local errors = {} :: {string}
	local success = true

	for shopId, shopData in pairs(ShopConfig.Shops) do
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
			if itemConfig.ItemType == "Unit" then
				local unitId = itemConfig.UnitId
				if not UnitConfig.IsValidUnit(unitId) then
					table.insert(errors, string.format(
						"商店[%s]商品[%d]的UnitId不存在: %s",
						shopIdStr, i, tostring(unitId)
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
