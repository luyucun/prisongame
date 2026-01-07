--[[
脚本名称: ShopSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/ShopSystem
版本: V2.1（数据驱动版 + Robux购买修复）
职责: 商店系统核心逻辑，基于ShopConfig提供购买服务
]]

local ShopSystem = {}

-- 调试配置
local DEBUG_MODE = false

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ShopConfig"))

-- 延迟加载系统模块（避免循环依赖）
local CurrencySystem = nil
local InventorySystem = nil
local DataManager = nil  -- V2.1库存系统：添加DataManager引用
local SoundSystem = nil  -- V3.8新增：音效系统

-- 私有变量
local PurchaseLocks = {}      -- 购买锁（防止并发购买）
local LastPurchaseTime = {}   -- 最后购买时间（冷却机制）

-- 库存系统变量 (V2.1库存功能)
local PlayerStockData = {}    -- 玩家库存数据: [player] = {[shopId] = {[unitId] = stock, LastRefreshTime = tick()}}
local RefreshTimers = {}      -- 刷新定时器: [player] = timer
local TimerUpdateConnections = {} -- 倒计时更新连接: [player] = connection
local LastTimerUpdate = {}    -- V2.1修复：定时器更新时间戳，移出Player实例 [player] = timestamp

local FIRST_OPEN_UNIT_ID = "10001"
local FIRST_OPEN_STOCK = 2
local FIRST_OPEN_STATE = {
	NEW = 0,
	ACTIVE = 1,
	SOLD_OUT = 2,
	COMPLETED = 3,
}


-- 事件引用
local ShopEvents = nil
local RequestShopList = nil
local ShopListEvent = nil
local PurchaseUnit = nil
local PurchaseUnitRobux = nil -- Robux购买事件
local PurchaseResult = nil
local StockUpdate = nil       -- 库存更新事件 (V2.1库存功能)
local RefreshTimeUpdate = nil -- 刷新倒计时更新事件 (V2.1库存功能)

-- ==================== 私有辅助函数 ====================

--[[ 初始化依赖模块（延迟加载） ]]
local function InitializeDependencies()
	if not CurrencySystem then
		local currencyModule = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
		if currencyModule then
			CurrencySystem = require(currencyModule)
		else
			warn("[ShopSystem] CurrencySystem模块未找到")
			return false
		end
	end

	if not InventorySystem then
		local inventoryModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if inventoryModule then
			InventorySystem = require(inventoryModule)
		else
			warn("[ShopSystem] InventorySystem模块未找到")
			return false
		end
	end

	-- V2.1库存系统：加载DataManager
	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if dataModule then
			DataManager = require(dataModule)
		else
			warn("[ShopSystem] DataManager模块未找到，库存刷新时间将无法持久化")
			return false
		end
	end

	return true
end

--[[ 初始化ShopEvents事件 ]]
local function InitializeEvents()
	if ShopEvents then
		return true -- 已初始化
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		warn("[ShopSystem] Events文件夹未找到")
		return false
	end

	ShopEvents = eventsFolder:FindFirstChild("ShopEvents")
	if not ShopEvents then
		warn("[ShopSystem] ShopEvents文件夹未找到，请确保已创建以下结构：")
		warn("  ReplicatedStorage/Events/ShopEvents/")
		warn("    ├── RequestShopList (RemoteEvent)")
		warn("    ├── ShopList (RemoteEvent)")
		warn("    ├── PurchaseUnit (RemoteEvent)")
		warn("    └── PurchaseResult (RemoteEvent)")
		return false
	end

	-- 获取各个事件
	RequestShopList = ShopEvents:FindFirstChild("RequestShopList")
	ShopListEvent = ShopEvents:FindFirstChild("ShopList")
	PurchaseUnit = ShopEvents:FindFirstChild("PurchaseUnit")
	PurchaseUnitRobux = ShopEvents:FindFirstChild("PurchaseUnitRobux")
	PurchaseResult = ShopEvents:FindFirstChild("PurchaseResult")
	StockUpdate = ShopEvents:FindFirstChild("StockUpdate")          -- V2.1库存功能
	RefreshTimeUpdate = ShopEvents:FindFirstChild("RefreshTimeUpdate") -- V2.1库存功能

	-- 验证基础事件是否都存在
	if not (RequestShopList and ShopListEvent and PurchaseUnit and PurchaseResult) then
		warn("[ShopSystem] 商店事件不完整，请检查是否创建了所有必需的RemoteEvent")
		return false
	end

	-- 库存事件是可选的，如果不存在仅发出警告
	if GameConfig.Shop.EnableStockSystem then
		if not StockUpdate then
			warn("[ShopSystem] ?? StockUpdate事件未找到，库存更新通知将不可用")
		end
		if not RefreshTimeUpdate then
			warn("[ShopSystem] ?? RefreshTimeUpdate事件未找到，刷新倒计时将不可用")
		end
	end

	-- Robux购买事件是可选的
	if not PurchaseUnitRobux then
		warn("[ShopSystem] ?? PurchaseUnitRobux事件未找到，Robux购买将不可用")
	end

	return true
end

--[[ 根据玩家位置确定附近的shopId ]]
local function GetPlayerNearbyShopId(player)
	local character = player.Character
	if not character then return nil end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end

	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then return nil end

	-- 查找玩家家园下的所有NPC
	local home = workspace:FindFirstChild("Home")
	if not home then return nil end

	local playerHome = home:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then return nil end

	-- 遍历所有可能的商店NPC
	for shopId, shopData in pairs(ShopConfig.Shops) do
		local npc = playerHome:FindFirstChild(shopData.NPCName)
		if npc then
			local npcPart = npc:FindFirstChild("HumanoidRootPart")
			                 or npc.PrimaryPart
			                 or npc:FindFirstChildWhichIsA("BasePart")

			if npcPart then
				local distance = (rootPart.Position - npcPart.Position).Magnitude
				-- V2.1修复：统一使用OpenDistance，不再使用1.5倍宽松判定
				if distance <= GameConfig.Shop.OpenDistance then
					return shopId
				end
			end
		end
	end

	return nil
end

-- ==================== 库存系统函数 (V2.1库存功能) ====================

--[[ 初始化玩家库存数据 ]]
local function InitializePlayerStock(player, shopId)
	if not PlayerStockData[player] then
		PlayerStockData[player] = {}
	end

	if not PlayerStockData[player][shopId] then
		-- 从DataManager读取持久化数据（包括库存和刷新时间）
		local shopData = DataManager and DataManager.GetShopData(player, shopId)
		local lastRefreshTime = shopData and shopData.LastRefreshTime or 0
		local savedStock = (shopData and shopData.Stock) or {}

		PlayerStockData[player][shopId] = {
			LastRefreshTime = lastRefreshTime,
		}

		for unitId, stock in pairs(savedStock) do
			PlayerStockData[player][shopId][unitId] = stock
		end

		if DEBUG_MODE then
			local itemCount = 0
			for _ in pairs(savedStock) do
				itemCount = itemCount + 1
			end
			print(string.format(
				"%s [ShopSystem] ??恢复库存 - 玩家:%s 商店:%s 恢复:%d个商品 上次刷新:%s",
				GameConfig.LOG_PREFIX,
				player.Name,
				shopId,
				itemCount,
				lastRefreshTime > 0 and os.date("%H:%M:%S", lastRefreshTime) or "首次进入"
			))
		end
	end
end

--[[ 刷新商店库存 ]]
local function EnsureFirstOpenState(player, shopId)
	if shopId ~= "UnitShop" or not DataManager then
		return FIRST_OPEN_STATE.COMPLETED
	end
	local shopData = DataManager.GetShopData(player, shopId)
	if not shopData then
		return FIRST_OPEN_STATE.COMPLETED
	end
	if shopData.FirstOpenState == nil then
		local playerData = DataManager.GetPlayerData(player)
		if playerData and playerData.IsNewPlayer then
			shopData.FirstOpenState = FIRST_OPEN_STATE.NEW
		else
			shopData.FirstOpenState = FIRST_OPEN_STATE.COMPLETED
		end
		DataManager.SavePlayerDataThrottled(player)
	end
	return shopData.FirstOpenState
end

local function SetFirstOpenState(player, shopId, newState)
	if shopId ~= "UnitShop" or not DataManager then
		return
	end
	local shopData = DataManager.GetShopData(player, shopId)
	if not shopData then
		return
	end
	shopData.FirstOpenState = newState
	if newState == FIRST_OPEN_STATE.COMPLETED then
		local playerData = DataManager.GetPlayerData(player)
		if playerData then
			playerData.IsNewPlayer = false
		end
	end
	DataManager.SavePlayerDataThrottled(player)
end

local function ApplyFirstOpenStock(player, shopId)
	InitializePlayerStock(player, shopId)
	local stockData = PlayerStockData[player][shopId]
	if not stockData then
		return nil
	end

	local currentStock = stockData[FIRST_OPEN_UNIT_ID]
	if type(currentStock) ~= "number" then
		currentStock = FIRST_OPEN_STOCK
	end

	local shopData = ShopConfig.Shops[shopId]
	if shopData then
		for _, itemConfig in ipairs(shopData.Items) do
			if itemConfig.ItemType == "Unit" then
				stockData[itemConfig.UnitId] = 0
			end
		end
	end

	stockData[FIRST_OPEN_UNIT_ID] = currentStock

	if DataManager then
		DataManager.SetShopStock(player, shopId, stockData)
	end

	return currentStock
end

local function RefreshShopStock(player, shopId, isFirstRefresh, forceNormal)
	if not GameConfig.Shop.EnableStockSystem then
		return {} -- 库存系统未启用
	end

	InitializePlayerStock(player, shopId)
	if shopId == "UnitShop" then
		local firstOpenState = EnsureFirstOpenState(player, shopId)
		if firstOpenState ~= FIRST_OPEN_STATE.COMPLETED and not forceNormal then
			return PlayerStockData[player][shopId] or {}
		end
	end
	local stockData = PlayerStockData[player][shopId]
	local shopData = ShopConfig.Shops[shopId]

	if not shopData then
		warn(string.format("[ShopSystem] 刷新库存失败: 商店[%s]不存在", shopId))
		return {}
	end

	-- 如果没有传入isFirstRefresh参数，则根据当前状态判断
	if isFirstRefresh == nil then
		local lastRefreshTime = stockData.LastRefreshTime or 0
		local hasAnyStock = false
		for unitId, stock in pairs(stockData) do
			if unitId ~= "LastRefreshTime" and type(stock) == "number" then
				hasAnyStock = true
				break
			end
		end
		isFirstRefresh = (lastRefreshTime == 0 and not hasAnyStock)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 开始刷新库存 - 玩家:%s 商店:%s 首次刷新:%s",
			GameConfig.LOG_PREFIX,
			player.Name,
			shopId,
			tostring(isFirstRefresh)
		))
	end

	local refreshCount = 0
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Unit" and itemConfig.Enabled then
			local unitId = itemConfig.UnitId

			-- V3.9.2新增：对UnitShop检查Show字段，隐藏的商品直接置0库存并跳过
			if shopId == "UnitShop" and itemConfig.Show == false then
				stockData[unitId] = 0
				if DEBUG_MODE then
					print(string.format(
						"  [%s] 商品隐藏，库存置0",
						unitId
					))
				end
				-- 跳过后续的概率刷新逻辑
				continue
			end

			local stockConfig = ShopConfig.GetStockConfig(shopId, unitId)

			if stockConfig then
				local probability = stockConfig.RefreshProbability
				local hasStock = false

				-- 新玩家首次刷新时，10001必定有库存
				if isFirstRefresh and shopId == "UnitShop" and unitId == "10001" then
					hasStock = true
					if DEBUG_MODE then
						print(string.format(
							"  [%s] 新玩家首次刷新，强制上架",
							unitId
						))
					end
				else
					hasStock = math.random() <= probability
				end

				if hasStock then
					local stock = math.random(stockConfig.StockMin, stockConfig.StockMax)
					stockData[unitId] = stock
					refreshCount = refreshCount + 1

					if DEBUG_MODE and refreshCount <= 5 then
						print(string.format(
							"  [%s] 库存:%d (概率:%.0f%% 范围:%d-%d)",
							unitId,
							stock,
							probability * 100,
							stockConfig.StockMin,
							stockConfig.StockMax
						))
					end
				else
					stockData[unitId] = 0
					if DEBUG_MODE and refreshCount <= 5 then
						print(string.format(
							"  [%s] 售罄 (概率:%.0f%% 未中)",
							unitId,
							probability * 100
						))
					end
				end
			end
		end
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 库存刷新完成 - 玩家:%s 有库存商品:%d/%d",
			GameConfig.LOG_PREFIX,
			player.Name,
			refreshCount,
			#shopData.Items
		))
	end

	stockData.LastRefreshTime = tick()

	-- 持久化刷新时间和库存数据
	if DataManager then
		task.spawn(function()
			local playerData = DataManager.WaitForPlayerData(player, 10)
			if playerData then
				DataManager.SetShopRefreshTime(player, shopId, stockData.LastRefreshTime)
				DataManager.SetShopStock(player, shopId, stockData)

				if DEBUG_MODE then
					print(string.format(
						"%s [ShopSystem] ??持久化库存 - 玩家:%s 商店:%s 保存:%d个商品",
						GameConfig.LOG_PREFIX,
						player.Name,
						shopId,
						refreshCount
					))
				end
			else
				warn(GameConfig.LOG_PREFIX, "RefreshShopStock: 玩家数据加载失败，跳过持久化 -", player.Name)
			end
		end)
	end

	-- 通知客户端库存更新
	if StockUpdate then
		pcall(function()
			local stockToSend = {}
			for unitId, stock in pairs(stockData) do
				if unitId ~= "LastRefreshTime" then
					stockToSend[unitId] = stock
				end
			end
			StockUpdate:FireClient(player, shopId, stockToSend)
		end)
	end

	return stockData
end

--[[ 获取玩家商店库存 ]]
local function GetPlayerStock(player, shopId, unitId)
	if not GameConfig.Shop.EnableStockSystem then
		return unitId and 999 or {} -- 库存系统未启用时返回无限库存
	end

	InitializePlayerStock(player, shopId)
	local stockData = PlayerStockData[player][shopId]

	if unitId then
		return stockData[unitId] or 0
	else
		local result = {}
		for key, value in pairs(stockData) do
			if key ~= "LastRefreshTime" then
				result[key] = value
			end
		end
		return result
	end
end

--[[ 扣除库存 ]]
local function DeductStock(player, shopId, unitId, amount)
	if not GameConfig.Shop.EnableStockSystem then
		return true -- 库存系统未启用时直接成功
	end

	amount = amount or 1
	local currentStock = GetPlayerStock(player, shopId, unitId)

	if currentStock < amount then
		return false
	end

	PlayerStockData[player][shopId][unitId] = currentStock - amount

	-- 持久化扣除后的库存数据
	if DataManager then
		task.spawn(function()
			local stockData = GetPlayerStock(player, shopId)
			DataManager.SetShopStock(player, shopId, stockData)

			if DEBUG_MODE then
				print(string.format(
					"%s [ShopSystem] ??扣除库存并持久化 - 玩家:%s UnitId:%s 剩余:%d",
					GameConfig.LOG_PREFIX,
					player.Name,
					unitId,
					currentStock - amount
				))
			end
		end)
	end

	-- 通知客户端库存更新
	if StockUpdate then
		pcall(function()
			local stockToSend = GetPlayerStock(player, shopId)
			StockUpdate:FireClient(player, shopId, stockToSend)
		end)
	end

	return true
end

--[[ 启动玩家的库存刷新定时器 ]]
local function StartRefreshTimer(player, shopId)
	if not GameConfig.Shop.EnableStockSystem then
		return
	end

	if RefreshTimers[player] then
		task.cancel(RefreshTimers[player])
		RefreshTimers[player] = nil
	end
	if TimerUpdateConnections[player] then
		TimerUpdateConnections[player]:Disconnect()
		TimerUpdateConnections[player] = nil
	end

	local refreshInterval = ShopConfig.GetRefreshInterval(shopId)
	if not refreshInterval or type(refreshInterval) ~= "number" or refreshInterval <= 0 then
		warn(string.format("%s [ShopSystem] 无效的刷新间隔，使用默认值300秒", GameConfig.LOG_PREFIX))
		refreshInterval = 300
	end

	InitializePlayerStock(player, shopId)
	local stockData = PlayerStockData[player][shopId]
	local lastRefreshTime = stockData.LastRefreshTime

	-- 检查是否有恢复的库存数据（防止误判首次进入）
	local hasRestoredStock = false
	for unitId, stock in pairs(stockData) do
		if unitId ~= "LastRefreshTime" and type(stock) == "number" then
			hasRestoredStock = true
			break
		end
	end

	local nextRefreshTime
	if lastRefreshTime == 0 and not hasRestoredStock then
		-- 首次进入，传递isFirstRefresh=true
		RefreshShopStock(player, shopId, true)
		nextRefreshTime = tick() + refreshInterval
	elseif lastRefreshTime == 0 and hasRestoredStock then
		stockData.LastRefreshTime = tick()
		nextRefreshTime = tick() + refreshInterval

		if DEBUG_MODE then
			print(string.format(
				"%s [ShopSystem] ??老数据迁移 - 玩家:%s 保留现有库存，设置时间戳",
				GameConfig.LOG_PREFIX,
				player.Name
			))
		end
	else
		local offlineTime = tick() - lastRefreshTime
		if offlineTime >= refreshInterval then
			RefreshShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
		else
			nextRefreshTime = lastRefreshTime + refreshInterval
		end
	end

	local function scheduleRefresh()
		local remainingTime = nextRefreshTime - tick()
		if remainingTime <= 0 then
			RefreshShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
			remainingTime = refreshInterval
		end

		RefreshTimers[player] = task.delay(remainingTime, function()
			RefreshShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
			scheduleRefresh()
		end)
	end

	scheduleRefresh()

	if RefreshTimeUpdate then
		TimerUpdateConnections[player] = game:GetService("RunService").Heartbeat:Connect(function()
			local now = tick()
			if not LastTimerUpdate[player] or (now - LastTimerUpdate[player]) >= GameConfig.Shop.RefreshTimerUpdateInterval then
				LastTimerUpdate[player] = now
				local remainingTime = math.max(0, nextRefreshTime - now)
				pcall(function()
					RefreshTimeUpdate:FireClient(player, math.floor(remainingTime))
				end)
			end
		end)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 启动刷新定时器 - 玩家:%s 商店:%s 间隔:%ds",
			GameConfig.LOG_PREFIX,
			player.Name,
			shopId,
			refreshInterval
		))
	end
end

--[[ 停止玩家的库存刷新定时器 ]]
local function StopRefreshTimer(player)
	if RefreshTimers[player] then
		task.cancel(RefreshTimers[player])
		RefreshTimers[player] = nil
	end

	if TimerUpdateConnections[player] then
		TimerUpdateConnections[player]:Disconnect()
		TimerUpdateConnections[player] = nil
	end

	LastTimerUpdate[player] = nil
end

-- ==================== 辅助函数 ====================

--[[ 发送购买失败结果 ]]
local function SendFailure(player, message)
	if PurchaseResult then
		pcall(function()
			PurchaseResult:FireClient(player, false, message, nil, nil, nil)
		end)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 购买失败 - 玩家:%s 原因:%s",
			GameConfig.LOG_PREFIX,
			player.Name,
			message
		))
	end
end

--[[ 发送购买成功结果 ]]
local function SendSuccess(player, message, unitId, newCoins, instanceId)
	if PurchaseResult then
		pcall(function()
			PurchaseResult:FireClient(player, true, message, unitId, newCoins, instanceId)
		end)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 购买成功 - 玩家:%s 兵种:%s 实例:%s 剩余金币:%d",
			GameConfig.LOG_PREFIX,
			player.Name,
			unitId,
			instanceId or "N/A",
			newCoins
		))
	end
end

--[[ 获取玩家到商店NPC的距离 ]]
local function GetDistanceToShopNPC(player)
	local character = player.Character
	if not character then return math.huge end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return math.huge end

	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then return math.huge end

	local home = workspace:FindFirstChild("Home")
	if not home then return math.huge end

	local playerHome = home:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then return math.huge end

	local npc = playerHome:FindFirstChild(GameConfig.Shop.NPCName)
	if not npc then return math.huge end

	local npcPart = npc:FindFirstChild("HumanoidRootPart")
	             or npc.PrimaryPart
	             or npc:FindFirstChildWhichIsA("BasePart")

	if not npcPart then return math.huge end

	return (rootPart.Position - npcPart.Position).Magnitude
end

-- ==================== 事件处理函数 ====================

--[[ 处理客户端请求商店列表 ]]
local function OnRequestShopList(player)
	local success, result = pcall(function()
		local shopId = GetPlayerNearbyShopId(player)
		if not shopId then
			shopId = "UnitShop"
		end

		local firstOpenState = nil
		local refreshedStock = nil
		if shopId == "UnitShop" then
			firstOpenState = EnsureFirstOpenState(player, shopId)
			if firstOpenState == FIRST_OPEN_STATE.SOLD_OUT then
				refreshedStock = RefreshShopStock(player, shopId, false, true)
				SetFirstOpenState(player, shopId, FIRST_OPEN_STATE.COMPLETED)
				firstOpenState = FIRST_OPEN_STATE.COMPLETED
			end
		end

		local shopItems = {}
		local useFallback = false

		if ShopConfig.Shops[shopId] then
			shopItems = ShopConfig.GetShopItems(shopId, player)
		else
			if GameConfig.Shop.FallbackToUnitConfig then
				warn(string.format(
					"[ShopSystem] 商店[%s]不存在，回退到UnitConfig模式",
					shopId
				))
				shopItems = ShopConfig.GetFallbackItemList()
				useFallback = true
			else
				shopItems = {}
			end
		end

		if shopId == "UnitShop" and firstOpenState and firstOpenState ~= FIRST_OPEN_STATE.COMPLETED and not useFallback then
			if firstOpenState == FIRST_OPEN_STATE.NEW then
				SetFirstOpenState(player, shopId, FIRST_OPEN_STATE.ACTIVE)
				firstOpenState = FIRST_OPEN_STATE.ACTIVE
			end

			local filteredItems = {}
			for _, item in ipairs(shopItems) do
				if item.UnitId == FIRST_OPEN_UNIT_ID then
					item.RobuxPrice = 0
					table.insert(filteredItems, item)
					break
				end
			end
			shopItems = filteredItems

			local currentStock = ApplyFirstOpenStock(player, shopId) or FIRST_OPEN_STOCK
			local stockData = GetPlayerStock(player, shopId)

			for _, item in ipairs(shopItems) do
				if GameConfig.Shop.EnableStockSystem then
					item.Stock = stockData[item.UnitId] or 0
				else
					item.Stock = currentStock
				end
				local isRanged = UnitConfig.IsRangedUnit(item.UnitId)
				item.Type = isRanged and UnitConfig.UnitType.RANGED or UnitConfig.UnitType.MELEE
			end

			if ShopListEvent then
				ShopListEvent:FireClient(player, shopItems)
			end

			return
		end

		-- Ensure Robux price is restored after first-open completion.
		if shopId == "UnitShop" and firstOpenState == FIRST_OPEN_STATE.COMPLETED and not useFallback then
			local configRobuxPrice = nil
			local shopConfig = ShopConfig.Shops[shopId]
			if shopConfig and shopConfig.Items then
				for _, itemConfig in ipairs(shopConfig.Items) do
					if itemConfig.ItemType == "Unit" and itemConfig.UnitId == FIRST_OPEN_UNIT_ID then
						configRobuxPrice = itemConfig.RobuxPrice
						break
					end
				end
			end
			if configRobuxPrice and configRobuxPrice > 0 then
				for _, item in ipairs(shopItems) do
					if item.UnitId == FIRST_OPEN_UNIT_ID and (not item.RobuxPrice or item.RobuxPrice <= 0) then
						item.RobuxPrice = configRobuxPrice
						break
					end
				end
			end
		end

		if GameConfig.Shop.EnableStockSystem and not useFallback then
			if not PlayerStockData[player] or not PlayerStockData[player][shopId] then
				warn(string.format(
					"[ShopSystem] ?? 玩家 %s 库存未初始化，正在补救性初始化（可能是时序问题）",
					player.Name
				))
				ShopSystem.InitializePlayerShopTimer(player, shopId)

				if not PlayerStockData[player] or not PlayerStockData[player][shopId] then
					warn(string.format(
						"[ShopSystem] ? 玩家 %s 库存初始化失败，将返回空库存",
						player.Name
					))
				end
			end

			local stockData = refreshedStock or GetPlayerStock(player, shopId)

			for _, item in ipairs(shopItems) do
				item.Stock = stockData[item.UnitId] or 0
				local isRanged = UnitConfig.IsRangedUnit(item.UnitId)
				item.Type = isRanged and UnitConfig.UnitType.RANGED or UnitConfig.UnitType.MELEE
			end
		end

		if ShopListEvent then
			ShopListEvent:FireClient(player, shopItems)
		end

		if DEBUG_MODE and shopItems and #shopItems > 0 then
			print(string.format(
				"%s [ShopSystem] 发送给客户端的商品数据（前5个）:",
				GameConfig.LOG_PREFIX
			))
			for i, item in ipairs(shopItems) do
				if i <= 5 then
					print(string.format(
						"  商品[%d] UnitId:%s 价格:%d 库存:%s 名称:%s",
						i,
						item.UnitId,
						item.Price or 0,
						tostring(item.Stock or "nil"),
						item.Name or "unknown"
					))
				end
			end
		end

		if DEBUG_MODE then
			print(string.format(
				"%s [ShopSystem] 玩家 %s 请求商店[%s]，返回 %d 个商品%s",
				GameConfig.LOG_PREFIX,
				player.Name,
				shopId,
				#shopItems,
				useFallback and " (回退模式)" or ""
			))
		end
	end)

	if not success then
		warn("[ShopSystem] OnRequestShopList 错误: " .. tostring(result))
		if ShopListEvent then
			ShopListEvent:FireClient(player, {})
		end
	end
end

--[[ 处理客户端购买请求 ]]
local function OnPurchaseUnit(player, unitId)
	local success, result = pcall(function()
		if PurchaseLocks[player] then
			SendFailure(player, "请稍等，正在处理上一个购买请求")
			return
		end

		PurchaseLocks[player] = true

		local now = tick()
		if LastPurchaseTime[player] then
			local timeSinceLastPurchase = now - LastPurchaseTime[player]
			if timeSinceLastPurchase < GameConfig.Shop.PurchaseCooldown then
				PurchaseLocks[player] = false
				SendFailure(player, "购买冷却中，请稍候")
				return
			end
		end

		local shopId = GetPlayerNearbyShopId(player)
		if not shopId then
			shopId = "UnitShop"
			if not ShopConfig.Shops[shopId] then
				PurchaseLocks[player] = false
				SendFailure(player, "商店不存在")
				return
			end
		end

		local firstOpenState = nil
		if shopId == "UnitShop" then
			firstOpenState = EnsureFirstOpenState(player, shopId)
			if firstOpenState ~= FIRST_OPEN_STATE.COMPLETED then
				if unitId ~= FIRST_OPEN_UNIT_ID then
					PurchaseLocks[player] = false
					SendFailure(player, "商品未上架")
					return
				end
				if firstOpenState == FIRST_OPEN_STATE.NEW then
					SetFirstOpenState(player, shopId, FIRST_OPEN_STATE.ACTIVE)
					firstOpenState = FIRST_OPEN_STATE.ACTIVE
				end
				ApplyFirstOpenStock(player, shopId)
			end
		end
		local onSale, reason = ShopConfig.IsUnitOnSale(shopId, unitId, player)
		if not onSale then
			PurchaseLocks[player] = false
			SendFailure(player, reason or "商品未上架")
			return
		end

		if GameConfig.Shop.EnableStockSystem then
			local stock = GetPlayerStock(player, shopId, unitId)
			if stock <= 0 then
				PurchaseLocks[player] = false
				SendFailure(player, "库存不足，已售罄")
				pcall(function()
					if not SoundSystem then
						local soundModule = ServerScriptService.Systems:FindFirstChild("SoundSystem")
						if soundModule then
							SoundSystem = require(soundModule)
						end
					end
					if SoundSystem then
						SoundSystem.OnPurchaseError(player)
					end
				end)
				return
			end
		end

		local price = ShopConfig.GetPrice(shopId, unitId)
		if not price then
			PurchaseLocks[player] = false
			SendFailure(player, string.format("商品[%s]价格配置错误", unitId))
			warn(string.format(
				"[ShopSystem] 商店[%s]中[%s]没有配置价格，请检查ShopConfig",
				shopId, unitId
			))
			return
		end

		if DEBUG_MODE then
			print(string.format(
				"%s [ShopSystem] 购买验证 - 玩家:%s UnitId:%s 价格:%d金币",
				GameConfig.LOG_PREFIX,
				player.Name,
				unitId,
				price
			))
		end

		if GameConfig.Shop.EnableDistanceCheck then
			local distance = GetDistanceToShopNPC(player)
			if distance > GameConfig.Shop.OpenDistance then
				PurchaseLocks[player] = false
				SendFailure(player, "距离商人太远，无法购买")
				return
			end
		end

		if not CurrencySystem.HasEnoughCoins(player, price) then
			PurchaseLocks[player] = false
			SendFailure(player, string.format("金币不足，需要 %d 金币", price))
			pcall(function()
				if not SoundSystem then
					local soundModule = ServerScriptService.Systems:FindFirstChild("SoundSystem")
					if soundModule then
						SoundSystem = require(soundModule)
					end
				end
				if SoundSystem then
					SoundSystem.OnPurchaseError(player)
				end
			end)
			return
		end

		local deductSuccess, newCoins = CurrencySystem.RemoveCoins(player, price, "购买兵种: " .. unitId)
		if not deductSuccess then
			PurchaseLocks[player] = false
			SendFailure(player, "金币扣除失败")
			return
		end

		local addSuccess, instanceData = InventorySystem.AddUnit(player, unitId)
		if not addSuccess then
			CurrencySystem.AddCoins(player, price, "购买失败退款: " .. unitId, { ApplyVipBonus = false })
			PurchaseLocks[player] = false
			SendFailure(player, "兵种发放失败: " .. tostring(instanceData))
			return
		end

		if GameConfig.Shop.EnableStockSystem then
			local deductStockSuccess = DeductStock(player, shopId, unitId, 1)
			if not deductStockSuccess then
				CurrencySystem.AddCoins(player, price, "库存扣除失败退款: " .. unitId, { ApplyVipBonus = false })
				if instanceData and instanceData.InstanceId then
					InventorySystem.RemoveUnit(player, instanceData.InstanceId)
				end
				PurchaseLocks[player] = false
				SendFailure(player, "库存扣除失败，已退款")
				warn(string.format("[ShopSystem] 库存扣除失败，理论上不应发生: %s", unitId))
				return
			end
		end

		if firstOpenState and firstOpenState ~= FIRST_OPEN_STATE.COMPLETED and unitId == FIRST_OPEN_UNIT_ID then
			local remainingStock = GetPlayerStock(player, shopId, unitId)
			if remainingStock <= 0 then
				SetFirstOpenState(player, shopId, FIRST_OPEN_STATE.SOLD_OUT)
			end
		end

		LastPurchaseTime[player] = now
		PurchaseLocks[player] = false

		local instanceId = type(instanceData) == "table" and instanceData.InstanceId or "unknown"
		SendSuccess(player, "购买成功", unitId, newCoins, instanceId)

		local taskModule = ServerScriptService.Systems:FindFirstChild("TaskSystem")
		if taskModule then
			local TaskSystem = require(taskModule)
			TaskSystem.OnPurchaseUnit(player, unitId)
		end

		-- 触发引导检查（购买第一个兵种后引导到IdleFloor）
		task.delay(0.5, function()
			if player and player.Parent then
				local guideModule = ServerScriptService.Systems:FindFirstChild("GuideSystem")
				if guideModule and guideModule:IsA("ModuleScript") then
					local GuideSystem = require(guideModule :: ModuleScript)
					GuideSystem.CheckAndTriggerGuides(player)
				end
			end
		end)
	end)

	if not success then
		PurchaseLocks[player] = false
		warn("[ShopSystem] OnPurchaseUnit 严重错误: " .. tostring(result))
		SendFailure(player, "系统错误，请重试")
	end
end

--[[ 处理客户端Robux购买请求 ]]
local function OnPurchaseUnitRobux(player, unitId)
	local success, result = pcall(function()
		if PurchaseLocks[player] then
			SendFailure(player, "请稍等，正在处理上一个购买请求")
			return
		end

		PurchaseLocks[player] = true

		local now = tick()
		if LastPurchaseTime[player] then
			local timeSinceLastPurchase = now - LastPurchaseTime[player]
			if timeSinceLastPurchase < GameConfig.Shop.PurchaseCooldown then
				PurchaseLocks[player] = false
				SendFailure(player, "购买冷却中，请稍候")
				return
			end
		end

		local shopId = GetPlayerNearbyShopId(player)
		if not shopId then
			shopId = "UnitShop"
		end

		local firstOpenState = nil
		if shopId == "UnitShop" then
			firstOpenState = EnsureFirstOpenState(player, shopId)
			if firstOpenState ~= FIRST_OPEN_STATE.COMPLETED then
				PurchaseLocks[player] = false
				SendFailure(player, "新手阶段暂不支持Robux购买")
				return
			end
		end
		local onSale, reason = ShopConfig.IsUnitOnSale(shopId, unitId, player)
		if not onSale then
			PurchaseLocks[player] = false
			SendFailure(player, reason or "商品未上架")
			return
		end

		local devProductId = ShopConfig.GetDevProductId(shopId, unitId)
		if not devProductId or devProductId == "" or devProductId == "0" then
			PurchaseLocks[player] = false
			SendFailure(player, "该商品不支持Robux购买")
			return
		end

		if GameConfig.Shop.EnableDistanceCheck then
			local distance = GetDistanceToShopNPC(player)
			if distance > GameConfig.Shop.OpenDistance then
				PurchaseLocks[player] = false
				SendFailure(player, "距离商人太远，无法购买")
				return
			end
		end

		-- 查找MarketplaceHandler模块
		local marketplaceModule = ServerScriptService.Systems:FindFirstChild("MarketplaceHandler")
		if not marketplaceModule then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			warn("[ShopSystem] 未找到 MarketplaceHandler 模块")
			return
		end

		if not marketplaceModule:IsA("ModuleScript") then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			warn("[ShopSystem] MarketplaceHandler 不是ModuleScript")
			return
		end

		-- 加载MarketplaceHandler并提示购买
		local loadSuccess, loadResult = pcall(require, marketplaceModule)

		if not loadSuccess then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			warn("[ShopSystem] MarketplaceHandler 加载失败: " .. tostring(loadResult))
			return
		end

		local marketplaceHandler = loadResult :: any
		local promptSuccess = marketplaceHandler.PromptUnitPurchase(player, unitId, shopId)

		if not promptSuccess then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			return
		end

		LastPurchaseTime[player] = now
		PurchaseLocks[player] = false

		if DEBUG_MODE then
			print(string.format(
				"%s [ShopSystem] 提示Robux购买 - 玩家:%s UnitId:%s",
				GameConfig.LOG_PREFIX,
				player.Name,
				unitId
			))
		end
	end)

	if not success then
		PurchaseLocks[player] = false
		warn("[ShopSystem] OnPurchaseUnitRobux 错误: " .. tostring(result))
		SendFailure(player, "系统错误，请重试")
	end
end

--[[ 玩家离开游戏时清理数据 ]]
local function OnPlayerRemoving(player)
	PurchaseLocks[player] = nil
	LastPurchaseTime[player] = nil

	if GameConfig.Shop.EnableStockSystem then
		StopRefreshTimer(player)
	end
end

-- ==================== 公共接口 ====================

--[[ 初始化商店系统 ]]
function ShopSystem.Initialize()
	if not InitializeDependencies() then
		warn("[ShopSystem] 依赖模块初始化失败")
		return false
	end

	local configSuccess, configErrors = ShopConfig.ValidateShopConfig()
	if not configSuccess then
		warn("[ShopSystem] ShopConfig配置有误，将回退到UnitConfig模式:")
		for _, error in ipairs(configErrors) do
			warn("  - " .. error)
		end
	end

	if not InitializeEvents() then
		warn("[ShopSystem] 事件初始化失败")
		return false
	end

	local bindSuccess, bindError = pcall(function()
		RequestShopList.OnServerEvent:Connect(OnRequestShopList)
		PurchaseUnit.OnServerEvent:Connect(OnPurchaseUnit)
		if PurchaseUnitRobux then
			PurchaseUnitRobux.OnServerEvent:Connect(OnPurchaseUnitRobux)
		end
	end)

	if not bindSuccess then
		warn("[ShopSystem] 事件绑定失败: " .. tostring(bindError))
		return false
	end

	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 商店系统已就绪（数据驱动模式）",
			GameConfig.LOG_PREFIX
		))
		print(string.format(
			"%s [ShopSystem] 配置状态: %s",
			GameConfig.LOG_PREFIX,
			configSuccess and "配置正常" or "配置异常，将回退到UnitConfig"
		))
	end

	return true
end

--[[ 获取商店统计信息（调试用） ]]
function ShopSystem.GetShopStats()
	local stats = {
		TotalShops = #ShopConfig.GetAllShopIds(),
		ActivePlayers = 0,
		PendingPurchases = 0,
	}

	for player, _ in pairs(PurchaseLocks) do
		if player.Parent then
			stats.ActivePlayers = stats.ActivePlayers + 1
		end
	end

	for _, locked in pairs(PurchaseLocks) do
		if locked then
			stats.PendingPurchases = stats.PendingPurchases + 1
		end
	end

	return stats
end

--[[ 强制清理玩家购买锁（管理员工具） ]]
function ShopSystem.ClearPlayerLock(player)
	PurchaseLocks[player] = nil
	LastPurchaseTime[player] = nil
	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 管理员清理玩家锁: %s",
			GameConfig.LOG_PREFIX,
			player.Name
		))
	end
end

--[[ V2.1库存系统：初始化玩家商店定时器 ]]
function ShopSystem.InitializePlayerShopTimer(player, shopId)
	if not GameConfig.Shop.EnableStockSystem then
		return
	end

	shopId = shopId or "UnitShop"

	InitializePlayerStock(player, shopId)
	StartRefreshTimer(player, shopId)

	-- V3.1新增：同时初始化技能商店定时器（共享刷新周期）
	local skillSystemModule = ServerScriptService.Systems:FindFirstChild("SkillShopSystem")
	if skillSystemModule then
		local success, result = pcall(function()
			return require(skillSystemModule)
		end)
		if success then
			local SkillShopSystem = result
			SkillShopSystem.InitializePlayerSkillShopTimer(player, "SkillShop")
		end
	end
end

return ShopSystem
