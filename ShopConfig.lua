--[[
脚本名称: ShopConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/ShopConfig
版本: V2.2（补全DevProductId）
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
      - Price: 价格（同步监狱数据表配置）
      - Icon: 图标（同步监狱数据表Icon）
      - Sort: 排序权重（数字越小越靠前）
      - Enabled: 是否上架（true/false）
      - Show: 是否在商店中显示（true/false，仅对UnitShop生效）
      - RobuxPrice: 罗布币价格
      - DevProductId: 开发者商品ID（同步监狱数据表）
      - LimitPerDay: 每日限购次数（0=不限购）
      - LimitTotal: 总限购次数（0=不限购）
      - UnlockStage: 解锁关卡（0=无限制）
      - RefreshProbability: 刷新概率（0-1）
      - StockMin/Max: 库存上下限
  }
]]
ShopConfig.Shops = {
	-- ==================== 兵种商店 ====================
	["UnitShop"] = {
		NPCName = "KeepShoper01",        -- 关联NPC
		DisplayName = "兵种商店",
		RefreshInterval = 300,           -- 库存刷新间隔(秒) 5分钟
		Items = {
			-- 10001: Rookie（基础近战）
			{
				ItemType = "Unit",
				UnitId = "10001",
				Price = 100,              -- 同步监狱数据表价格
				RobuxPrice = 10,
				DevProductId = "3472102223", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://98616255072587", -- 同步监狱数据表Icon
				Sort = 10,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.7,
				StockMin = 4,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10002: Bat Thug（突击手）
			{
				ItemType = "Unit",
				UnitId = "10002",
				Price = 150,              -- 同步监狱数据表价格
				RobuxPrice = 10,
				DevProductId = "3472102380", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://133527593486392", -- 同步监狱数据表Icon
				Sort = 20,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.7,
				StockMin = 4,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10003: Pot Lid（主坦克）
			{
				ItemType = "Unit",
				UnitId = "10003",
				Price = 250,              -- 同步监狱数据表价格
				RobuxPrice = 10,
				DevProductId = "3472105673", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://114892183819195", -- 同步监狱数据表Icon
				Sort = 30,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.7,
				StockMin = 4,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10004: Pistol Boy（中程游侠）
			{
				ItemType = "Unit",
				UnitId = "10004",
				Price = 250,              -- 同步监狱数据表价格
				RobuxPrice = 10,
				DevProductId = "3472102983", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://80744151898936", -- 同步监狱数据表Icon
				Sort = 40,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.7,
				StockMin = 4,
				StockMax = 5,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10005: Patrol Cop（基础近战）
			{
				ItemType = "Unit",
				UnitId = "10005",
				Price = 500,              -- 同步监狱数据表价格
				RobuxPrice = 15,
				DevProductId = "3472103245", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://80710637196540", -- 同步监狱数据表Icon
				Sort = 50,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.5,
				StockMin = 3,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10006: Pipe Girl（突击手）
			{
				ItemType = "Unit",
				UnitId = "10006",
				Price = 750,              -- 同步监狱数据表价格
				RobuxPrice = 15,
				DevProductId = "3472104357", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://123524507681699", -- 同步监狱数据表Icon
				Sort = 60,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.5,
				StockMin = 3,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10007: Baton Cop（突击手）
			{
				ItemType = "Unit",
				UnitId = "10007",
				Price = 750,              -- 同步监狱数据表价格
				RobuxPrice = 15,
				DevProductId = "3472103372", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://96910755166910", -- 同步监狱数据表Icon
				Sort = 70,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.5,
				StockMin = 3,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10008: Mechanic（主坦克）
			{
				ItemType = "Unit",
				UnitId = "10008",
				Price = 1000,              -- 同步监狱数据表价格
				RobuxPrice = 15,
				DevProductId = "3472105731", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://87038735300763", -- 同步监狱数据表Icon
				Sort = 80,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.5,
				StockMin = 3,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10009: Girl Recruit（远程狙击）
			{
				ItemType = "Unit",
				UnitId = "10009",
				Price = 1000,              -- 同步监狱数据表价格
				RobuxPrice = 20,
				DevProductId = "3472103709", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://123162348831885", -- 同步监狱数据表Icon
				Sort = 90,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.5,
				StockMin = 3,
				StockMax = 4,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10010: Muscle Prisoner（重装战士）
			{
				ItemType = "Unit",
				UnitId = "10010",
				Price = 2000,              -- 同步监狱数据表价格
				RobuxPrice = 20,
				DevProductId = "3472105294", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://74819350235405", -- 同步监狱数据表Icon
				Sort = 100,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 2,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10011: Heavy Cop（重装战士）
			{
				ItemType = "Unit",
				UnitId = "10011",
				Price = 2500,              -- 同步监狱数据表价格
				RobuxPrice = 20,
				DevProductId = "3472105457", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://75652304417710", -- 同步监狱数据表Icon
				Sort = 110,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 2,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10012: Sailor Girl（突击手）
			{
				ItemType = "Unit",
				UnitId = "10012",
				Price = 3500,              -- 同步监狱数据表价格
				RobuxPrice = 20,
				DevProductId = "3472105191", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://130658905780133", -- 同步监狱数据表Icon
				Sort = 120,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 2,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10013: Florida（中程游侠）
			{
				ItemType = "Unit",
				UnitId = "10013",
				Price = 4000,              -- 同步监狱数据表价格
				RobuxPrice = 25,
				DevProductId = "3472103485", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://140057693756084", -- 同步监狱数据表Icon
				Sort = 130,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 2,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10014: Shotgun Cop（中程游侠）
			{
				ItemType = "Unit",
				UnitId = "10014",
				Price = 4500,              -- 同步监狱数据表价格
				RobuxPrice = 25,
				DevProductId = "3472103600", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://109694053639716", -- 同步监狱数据表Icon
				Sort = 140,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 2,
				StockMax = 3,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10015: Boxer（基础近战）
			{
				ItemType = "Unit",
				UnitId = "10015",
				Price = 6000,              -- 同步监狱数据表价格
				RobuxPrice = 25,
				DevProductId = "3472103096", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://129425310745524", -- 同步监狱数据表Icon
				Sort = 150,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10016: Riot FBI（主坦克）
			{
				ItemType = "Unit",
				UnitId = "10016",
				Price = 6000,             -- 同步监狱数据表价格
				RobuxPrice = 25,
				DevProductId = "3472105796", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://88477019377142", -- 同步监狱数据表Icon
				Sort = 160,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10017: Gangster（远程狙击）
			{
				ItemType = "Unit",
				UnitId = "10017",
				Price = 8000,             -- 同步监狱数据表价格
				RobuxPrice = 30,
				DevProductId = "3472104653", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://96684518109328", -- 同步监狱数据表Icon
				Sort = 170,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.3,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10018: Tattoo Heavy（重装战士）
			{
				ItemType = "Unit",
				UnitId = "10018",
				Price = 10000,             -- 同步监狱数据表价格
				RobuxPrice = 30,
				DevProductId = "3472105522", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://107612488818992", -- 同步监狱数据表Icon
				Sort = 180,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10019: Yakuza（突击手）
			{
				ItemType = "Unit",
				UnitId = "10019",
				Price = 12000,             -- 同步监狱数据表价格
				RobuxPrice = 30,
				DevProductId = "3472104884", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://127241024884061", -- 同步监狱数据表Icon
				Sort = 190,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10020: Cowboy（中程游侠）
			{
				ItemType = "Unit",
				UnitId = "10020",
				Price = 15000,             -- 同步监狱数据表价格
				RobuxPrice = 30,
				DevProductId = "3472104457", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://78069816818003", -- 同步监狱数据表Icon
				Sort = 200,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.2,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10021: Psycho（基础近战）
			{
				ItemType = "Unit",
				UnitId = "10021",
				Price = 30000,             -- 同步监狱数据表价格
				RobuxPrice = 30,
				DevProductId = "3472104793", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://102001177844916", -- 同步监狱数据表Icon
				Sort = 210,
				Enabled = true,
				Show = true,              -- 是否在商店中显示
				RefreshProbability = 0.1,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10022: SWAT（远程狙击）
			{
				ItemType = "Unit",
				UnitId = "10022",
				Price = 40000,             -- 同步监狱数据表价格
				RobuxPrice = 40,
				DevProductId = "3472105103", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://86449419798698", -- 同步监狱数据表Icon
				Sort = 220,
				Enabled = false,
				Show = false,              -- 是否在商店中显示
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10023: Robocop（中程游侠）
			{
				ItemType = "Unit",
				UnitId = "10023",
				Price = 50000,             -- 同步监狱数据表价格
				RobuxPrice = 40,
				DevProductId = "3472104998", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://96284212262078", -- 同步监狱数据表Icon
				Sort = 230,
				Enabled = false,
				Show = false,              -- 是否在商店中显示
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10024: Juggernaut（主坦克）
			{
				ItemType = "Unit",
				UnitId = "10024",
				Price = 100000,             -- 同步监狱数据表价格
				RobuxPrice = 40,
				DevProductId = "3472105858", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://102620601082371", -- 同步监狱数据表Icon
				Sort = 240,
				Enabled = false,
				Show = false,              -- 是否在商店中显示
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
			-- 10025: Titan Police（重装战士）
			{
				ItemType = "Unit",
				UnitId = "10025",
				Price = 100000,             -- 同步监狱数据表价格
				RobuxPrice = 40,
				DevProductId = "3472105595", -- 同步监狱数据表开发者商品ID
				Icon = "rbxassetid://105156254180465", -- 同步监狱数据表Icon
				Sort = 250,
				Enabled = false,
				Show = false,              -- 是否在商店中显示
				RefreshProbability = 0.15,
				StockMin = 1,
				StockMax = 2,
				LimitPerDay = 0,
				LimitTotal = 0,
				UnlockStage = 0,
			},
		}
	},
}

-- ==================== 公共接口 ====================
-- 根据NPC实例查找对应的商店ID
function ShopConfig.GetShopIdForNPC(npc)
	if not npc then return nil end
	local shopIdAttr = npc:GetAttribute("ShopId")
	if shopIdAttr then
		return shopIdAttr
	end
	local shopIdValue = npc:FindFirstChild("ShopId")
	if shopIdValue and shopIdValue:IsA("StringValue") then
		return shopIdValue.Value
	end
	local npcName = npc.Name
	for shopId, shopData in pairs(ShopConfig.Shops) do
		if shopData.NPCName == npcName then
			return shopId
		end
	end
	return nil
end

-- 获取商店商品列表（已过滤、排序）
function ShopConfig.GetShopItems(shopId, player)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		warn("[ShopConfig] 未找到商店: " .. tostring(shopId))
		return {}
	end
	local items = {}
	for _, itemConfig in ipairs(shopData.Items) do
		-- V3.9.2新增：对UnitShop检查Show字段
		if shopId == "UnitShop" and itemConfig.Show == false then
			-- 跳过不显示的商品
			continue
		end

		if itemConfig.Enabled then
			if itemConfig.ItemType == "Unit" then
				local unitId = itemConfig.UnitId
				local unitData = UnitConfig.GetUnitById(unitId)
				if unitData then
					local price = itemConfig.Price
					if price and price > 0 then
						-- 补充DevProductId到返回数据中
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
							BaseHealth = UnitConfig.CalculateHealth(unitId, unitData.BaseLevel),
							BaseAttack = UnitConfig.CalculateAttack(unitId, unitData.BaseLevel),
							BaseAttackSpeed = unitData.BaseAttackSpeed,
							BaseAttackRange = unitData.BaseAttackRange,
							RobuxPrice = itemConfig.RobuxPrice,
							DevProductId = itemConfig.DevProductId, -- 新增返回DevProductId
							LimitPerDay = itemConfig.LimitPerDay,
							LimitTotal = itemConfig.LimitTotal,
						})
					else
						warn(string.format("[ShopConfig] 商品[%s]价格配置无效: %s", unitId, tostring(price)))
					end
				else
					warn("[ShopConfig] UnitId不存在: " .. unitId)
				end
			end
		end
	end
	table.sort(items, function(a, b)
		return a.Sort < b.Sort
	end)
	return items
end

-- 检查商品是否在售
function ShopConfig.IsUnitOnSale(shopId, unitId, player)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		return false, "商店不存在"
	end
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Unit" and itemConfig.UnitId == unitId then
			if not itemConfig.Enabled then
				return false, "商品未上架"
			end
			-- V3.9.2新增：对UnitShop检查Show字段
			if shopId == "UnitShop" and itemConfig.Show == false then
				return false, "商品不在售"
			end
			return true, "在售"
		end
	end
	return false, "商品不存在"
end

-- 获取商品价格（新增：可同时获取DevProductId）
function ShopConfig.GetPriceAndDevProductId(shopId, unitId)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		return nil, nil
	end
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Unit" and itemConfig.UnitId == unitId then
			return itemConfig.Price, itemConfig.DevProductId
		end
	end
	return nil, nil
end

-- 获取商品价格（兼容原有接口）
function ShopConfig.GetPrice(shopId, unitId)
	local price, _ = ShopConfig.GetPriceAndDevProductId(shopId, unitId)
	return price
end

-- 获取开发者商品ID（新增专属接口）
function ShopConfig.GetDevProductId(shopId, unitId)
	local _, devProductId = ShopConfig.GetPriceAndDevProductId(shopId, unitId)
	return devProductId
end

-- 获取所有商店ID列表
function ShopConfig.GetAllShopIds()
	local shopIds = {}
	for shopId, _ in pairs(ShopConfig.Shops) do
		table.insert(shopIds, shopId)
	end
	return shopIds
end

-- 获取商店显示名称
function ShopConfig.GetShopDisplayName(shopId)
	local shopData = ShopConfig.Shops[shopId]
	return shopData and shopData.DisplayName or "未知商店"
end

-- 验证ShopConfig配置完整性（新增DevProductId校验）
function ShopConfig.ValidateShopConfig()
	local errors = {}
	local success = true
	for shopId, shopData in pairs(ShopConfig.Shops) do
		local shopIdStr = tostring(shopId)
		if not shopData.NPCName then
			table.insert(errors, string.format("商店[%s]缺少NPCName", shopIdStr))
			success = false
		end
		if not shopData.Items or #shopData.Items == 0 then
			table.insert(errors, string.format("商店[%s]没有商品", shopIdStr))
			success = false
		end
		for i, itemConfig in ipairs(shopData.Items or {}) do
			if itemConfig.ItemType == "Unit" then
				local unitId = itemConfig.UnitId
				if not UnitConfig.IsValidUnit(unitId) then
					table.insert(errors, string.format("商店[%s]商品[%d]的UnitId不存在: %s", shopIdStr, i, tostring(unitId)))
					success = false
				end
				-- 校验DevProductId格式（数字字符串）
				local devProductId = itemConfig.DevProductId
				if devProductId and type(devProductId) == "string" and devProductId ~= "" then
					if not string.match(devProductId :: string, "^%d+$") then
						table.insert(errors, string.format("商店[%s]商品[%d]的DevProductId格式错误（需为纯数字）: %s", shopIdStr, i, tostring(devProductId)))
						success = false
					end
				else
					table.insert(errors, string.format("商店[%s]商品[%d]缺少DevProductId: %s", shopIdStr, i, tostring(unitId)))
					success = false
				end
			end
		end
	end
	return success, errors
end

-- 获取商品库存配置
function ShopConfig.GetStockConfig(shopId, unitId)
	local shopData = ShopConfig.Shops[shopId]
	if not shopData then
		return nil
	end
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

-- 获取商店刷新间隔
function ShopConfig.GetRefreshInterval(shopId)
	local shopData = ShopConfig.Shops[shopId]
	if shopData and shopData.RefreshInterval then
		return shopData.RefreshInterval
	end
	local GameConfig = require(script.Parent.GameConfig)
	return GameConfig.Shop.DefaultRefreshInterval or 300
end

-- 从UnitConfig生成默认列表（回退机制）
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
			BaseHealth = UnitConfig.CalculateHealth(unitId, unitData.BaseLevel),
			BaseAttack = UnitConfig.CalculateAttack(unitId, unitData.BaseLevel),
			BaseAttackSpeed = unitData.BaseAttackSpeed,
			BaseAttackRange = unitData.BaseAttackRange,
		})
		sortCounter = sortCounter + 10
	end
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