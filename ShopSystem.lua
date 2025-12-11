--[[
脚本名称: ShopSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/ShopSystem
版本: V2.1（数据驱动版）
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

-- 事件引用
local ShopEvents = nil
local RequestShopList = nil
local ShopListEvent = nil
local PurchaseUnit = nil
local PurchaseResult = nil
local StockUpdate = nil       -- 库存更新事件 (V2.1库存功能)
local RefreshTimeUpdate = nil -- 刷新倒计时更新事件 (V2.1库存功能)

-- ==================== 私有辅助函数 ====================

--[[
初始化依赖模块（延迟加载）
@return boolean - 是否成功
]]
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

--[[
初始化ShopEvents事件
@return boolean - 是否成功
]]
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
			warn("[ShopSystem] ⚠️ StockUpdate事件未找到，库存更新通知将不可用")
		end
		if not RefreshTimeUpdate then
			warn("[ShopSystem] ⚠️ RefreshTimeUpdate事件未找到，刷新倒计时将不可用")
		end
	end

	return true
end

--[[
根据玩家位置确定附近的shopId
@param player Player - 玩家实例
@return string|nil - 商店ID，未找到返回nil
]]
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

--[[
初始化玩家库存数据（V2.1库存系统：使用DataManager持久化，🔥修复库存售罄：恢复完整库存数据）
@param player Player - 玩家实例
@param shopId string - 商店ID
]]
local function InitializePlayerStock(player, shopId)
	if not PlayerStockData[player] then
		PlayerStockData[player] = {}
	end

	if not PlayerStockData[player][shopId] then
		-- 🔥修复库存售罄：从DataManager读取持久化数据（包括库存和刷新时间）
		local shopData = DataManager and DataManager.GetShopData(player, shopId)
		local lastRefreshTime = shopData and shopData.LastRefreshTime or 0
		local savedStock = (shopData and shopData.Stock) or {}

		-- 初始化PlayerStockData，包含LastRefreshTime和所有库存数据
		PlayerStockData[player][shopId] = {
			LastRefreshTime = lastRefreshTime,
		}

		-- 🔥修复库存售罄：恢复所有保存的库存数据
		for unitId, stock in pairs(savedStock) do
			PlayerStockData[player][shopId][unitId] = stock
		end

		-- 调试日志
		if DEBUG_MODE then
			local itemCount = 0
			for _ in pairs(savedStock) do
				itemCount = itemCount + 1
			end
			print(string.format(
				"%s [ShopSystem] 🔥恢复库存 - 玩家:%s 商店:%s 恢复:%d个商品 上次刷新:%s",
				GameConfig.LOG_PREFIX,
				player.Name,
				shopId,
				itemCount,
				lastRefreshTime > 0 and os.date("%H:%M:%S", lastRefreshTime) or "首次进入"
			))
		end
	end
end

--[[
刷新商店库存
@param player Player - 玩家实例
@param shopId string - 商店ID
@return table - 刷新后的库存数据 {[unitId] = stock}
]]
local function RefreshShopStock(player, shopId)
	if not GameConfig.Shop.EnableStockSystem then
		return {} -- 库存系统未启用
	end

	InitializePlayerStock(player, shopId)

	local stockData = PlayerStockData[player][shopId]
	local shopData = ShopConfig.Shops[shopId]

	if not shopData then
		warn(string.format("[ShopSystem] 刷新库存失败: 商店[%s]不存在", shopId))
		return {}
	end

	-- V2.1调试：记录刷新开始
	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 开始刷新库存 - 玩家:%s 商店:%s",
			GameConfig.LOG_PREFIX,
			player.Name,
			shopId
		))
	end

	-- 遍历商店中的所有商品并刷新库存
	local refreshCount = 0
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Unit" and itemConfig.Enabled then
			local unitId = itemConfig.UnitId
			local stockConfig = ShopConfig.GetStockConfig(shopId, unitId)

			if stockConfig then
				-- 根据刷新概率决定是否有库存
				local probability = stockConfig.RefreshProbability
				local hasStock = math.random() <= probability

				if hasStock then
					-- 在上下限之间随机库存数量
					local stock = math.random(stockConfig.StockMin, stockConfig.StockMax)
					stockData[unitId] = stock
					refreshCount = refreshCount + 1

					-- V2.1调试：详细记录每个商品的库存
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
					-- 无库存
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

	-- V2.1调试：总结刷新结果
	if DEBUG_MODE then
		print(string.format(
			"%s [ShopSystem] 库存刷新完成 - 玩家:%s 有库存商品:%d/%d",
			GameConfig.LOG_PREFIX,
			player.Name,
			refreshCount,
			#shopData.Items
		))
	end

	-- 更新刷新时间
	stockData.LastRefreshTime = tick()

	-- 🔥修复库存售罄：持久化刷新时间和完整库存数据到DataManager
	if DataManager then
		task.spawn(function()
			local playerData = DataManager.WaitForPlayerData(player, 10)
			if playerData then
				DataManager.SetShopRefreshTime(player, shopId, stockData.LastRefreshTime)

				-- 🔥修复库存售罄：同时保存完整的库存数据
				DataManager.SetShopStock(player, shopId, stockData)

				if DEBUG_MODE then
					print(string.format(
						"%s [ShopSystem] 🔥持久化库存 - 玩家:%s 商店:%s 保存:%d个商品",
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
			-- 只发送库存数量数据，不包括LastRefreshTime
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

--[[
获取玩家商店库存
@param player Player - 玩家实例
@param shopId string - 商店ID
@param unitId string - 兵种ID (可选，获取特定商品库存)
@return number|table - 库存数量或库存表
]]
local function GetPlayerStock(player, shopId, unitId)
	if not GameConfig.Shop.EnableStockSystem then
		return unitId and 999 or {} -- 库存系统未启用时返回无限库存
	end

	InitializePlayerStock(player, shopId)

	local stockData = PlayerStockData[player][shopId]

	if unitId then
		return stockData[unitId] or 0
	else
		-- 返回库存副本（不包括LastRefreshTime）
		local result = {}
		for key, value in pairs(stockData) do
			if key ~= "LastRefreshTime" then
				result[key] = value
			end
		end
		return result
	end
end

--[[
扣除库存
@param player Player - 玩家实例
@param shopId string - 商店ID
@param unitId string - 兵种ID
@param amount number - 扣除数量（默认1）
@return boolean - 是否成功
]]
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

	-- 🔥修复库存售罄：立即持久化扣除后的库存数据
	if DataManager then
		task.spawn(function()
			local stockData = GetPlayerStock(player, shopId)
			DataManager.SetShopStock(player, shopId, stockData)

			if DEBUG_MODE then
				print(string.format(
					"%s [ShopSystem] 🔥扣除库存并持久化 - 玩家:%s UnitId:%s 剩余:%d",
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

--[[
启动玩家的库存刷新定时器
@param player Player - 玩家实例
@param shopId string - 商店ID
]]
local function StartRefreshTimer(player, shopId)
	if not GameConfig.Shop.EnableStockSystem then
		return
	end

	-- 清理旧的定时器
	if RefreshTimers[player] then
		task.cancel(RefreshTimers[player])
		RefreshTimers[player] = nil
	end
	if TimerUpdateConnections[player] then
		TimerUpdateConnections[player]:Disconnect()
		TimerUpdateConnections[player] = nil
	end

	local refreshInterval = ShopConfig.GetRefreshInterval(shopId)
	-- 修复：确保refreshInterval是有效的数字
	if not refreshInterval or type(refreshInterval) ~= "number" or refreshInterval <= 0 then
		warn(string.format("%s [ShopSystem] 无效的刷新间隔，使用默认值300秒", GameConfig.LOG_PREFIX))
		refreshInterval = 300  -- 默认5分钟
	end

	InitializePlayerStock(player, shopId)

	local stockData = PlayerStockData[player][shopId]
	local lastRefreshTime = stockData.LastRefreshTime

	-- 🔥修复库存售罄：检查是否有恢复的库存数据（防止误判首次进入）
	local hasRestoredStock = false
	for unitId, stock in pairs(stockData) do
		if unitId ~= "LastRefreshTime" and type(stock) == "number" then
			hasRestoredStock = true
			break
		end
	end

	-- 计算下次刷新时间
	local nextRefreshTime
	if lastRefreshTime == 0 and not hasRestoredStock then
		-- 真正的首次进入（无刷新时间且无库存数据），立即刷新
		RefreshShopStock(player, shopId)
		nextRefreshTime = tick() + refreshInterval
	elseif lastRefreshTime == 0 and hasRestoredStock then
		-- 🔥修复库存售罄：老数据迁移场景（有库存但无时间戳），不刷新，设置时间戳
		stockData.LastRefreshTime = tick()
		nextRefreshTime = tick() + refreshInterval

		if DEBUG_MODE then
			print(string.format(
				"%s [ShopSystem] 🔥老数据迁移 - 玩家:%s 保留现有库存，设置时间戳",
				GameConfig.LOG_PREFIX,
				player.Name
			))
		end
	else
		-- 计算离线时间
		local offlineTime = tick() - lastRefreshTime
		if offlineTime >= refreshInterval then
			-- 离线时间超过刷新间隔，立即刷新
			RefreshShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
		else
			-- 继续倒计时
			nextRefreshTime = lastRefreshTime + refreshInterval
		end
	end

	-- 设置刷新定时器
	local function scheduleRefresh()
		local remainingTime = nextRefreshTime - tick()
		if remainingTime <= 0 then
			-- 立即刷新
			RefreshShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
			remainingTime = refreshInterval
		end

		RefreshTimers[player] = task.delay(remainingTime, function()
			RefreshShopStock(player, shopId)
			-- 递归设置下一次刷新
			nextRefreshTime = tick() + refreshInterval
			scheduleRefresh()
		end)
	end

	scheduleRefresh()

	-- 启动倒计时更新（每秒更新一次）
	if RefreshTimeUpdate then
		TimerUpdateConnections[player] = game:GetService("RunService").Heartbeat:Connect(function()
			local now = tick()
			-- V2.1修复：使用模块内表而非Player实例字段
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

--[[
停止玩家的库存刷新定时器
@param player Player - 玩家实例
]]
local function StopRefreshTimer(player)
	if RefreshTimers[player] then
		task.cancel(RefreshTimers[player])
		RefreshTimers[player] = nil
	end

	if TimerUpdateConnections[player] then
		TimerUpdateConnections[player]:Disconnect()
		TimerUpdateConnections[player] = nil
	end

	-- V2.1修复：清理定时器更新时间戳
	LastTimerUpdate[player] = nil

end

-- ==================== 辅助函数 ====================

--[[
发送购买失败结果
@param player Player - 玩家
@param message string - 失败消息
]]
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

--[[
发送购买成功结果
@param player Player - 玩家
@param message string - 成功消息
@param unitId string - 兵种ID
@param newCoins number - 新的金币数量
@param instanceId string - 新创建的兵种实例ID
]]
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

--[[
获取玩家到商店NPC的距离
@param player Player - 玩家
@return number - 距离，无法获取返回math.huge
]]
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

	-- 查找KeepShoper01
	local npc = playerHome:FindFirstChild(GameConfig.Shop.NPCName)
	if not npc then return math.huge end

	local npcPart = npc:FindFirstChild("HumanoidRootPart")
	             or npc.PrimaryPart
	             or npc:FindFirstChildWhichIsA("BasePart")

	if not npcPart then return math.huge end

	return (rootPart.Position - npcPart.Position).Magnitude
end

-- ==================== 事件处理函数 ====================

--[[
处理客户端请求商店列表
@param player Player - 请求的玩家
]]
local function OnRequestShopList(player)
	local success, result = pcall(function()

		-- 确定商店ID
		local shopId = GetPlayerNearbyShopId(player)
		if not shopId then
			shopId = "UnitShop" -- 回退到默认商店
		end

		-- 获取商品列表
		local shopItems = {}
		local useFallback = false

		if ShopConfig.Shops[shopId] then
			-- 使用ShopConfig
			shopItems = ShopConfig.GetShopItems(shopId, player)
		else
			-- 回退到UnitConfig
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

		-- V2.1库存功能：添加库存信息到商品列表
		if GameConfig.Shop.EnableStockSystem and not useFallback then
			-- V2.1修复：直接使用外层shopId，避免重复定义
			-- 确保玩家有库存数据（正常情况下在玩家进入游戏时已初始化）
			if not PlayerStockData[player] or not PlayerStockData[player][shopId] then
				-- 🔥修复库存售罄：如果没有初始化，现在初始化（兼容性处理）
				warn(string.format(
					"[ShopSystem] ⚠️ 玩家 %s 库存未初始化，正在补救性初始化（可能是时序问题）",
					player.Name
				))
				ShopSystem.InitializePlayerShopTimer(player, shopId)

				-- 再次检查是否初始化成功
				if not PlayerStockData[player] or not PlayerStockData[player][shopId] then
					warn(string.format(
						"[ShopSystem] ❌ 玩家 %s 库存初始化失败，将返回空库存",
						player.Name
					))
				end
			end

			-- 获取库存数据
			local stockData = GetPlayerStock(player, shopId)

			-- 将库存信息添加到每个商品，并确保Type字段正确
			for _, item in ipairs(shopItems) do
				item.Stock = stockData[item.UnitId] or 0

				-- V2.1关键修复：强制添加/覆盖Type字段（确保客户端读到的Type与配置一致）
				local isRanged = UnitConfig.IsRangedUnit(item.UnitId)
				item.Type = isRanged and UnitConfig.UnitType.RANGED or UnitConfig.UnitType.MELEE

				-- V2.1补充校验：调试输出兵种类型判定
			end
		end

		-- 发送到客户端
		if ShopListEvent then
			ShopListEvent:FireClient(player, shopItems)
		end

		-- V2.1调试：详细打印发送给客户端的价格数据
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
		-- 发送空列表作为降级
		if ShopListEvent then
			ShopListEvent:FireClient(player, {})
		end
	end
end

--[[
处理客户端购买请求
@param player Player - 购买的玩家
@param unitId string - 要购买的兵种ID
]]
local function OnPurchaseUnit(player, unitId)
	local success, result = pcall(function()
		-- 1. 购买锁检查（防止并发购买）
		if PurchaseLocks[player] then
			SendFailure(player, "请稍等，正在处理上一个购买请求")
			return
		end

		PurchaseLocks[player] = true

		-- 2. 冷却检查
		local now = tick()
		if LastPurchaseTime[player] then
			local timeSinceLastPurchase = now - LastPurchaseTime[player]
			if timeSinceLastPurchase < GameConfig.Shop.PurchaseCooldown then
				PurchaseLocks[player] = false
				SendFailure(player, "购买冷却中，请稍候")
				return
			end
		end

		-- 3. 确定商店ID
		local shopId = GetPlayerNearbyShopId(player)
		if not shopId then
			shopId = "UnitShop" -- 回退到默认商店
			if not ShopConfig.Shops[shopId] then
				PurchaseLocks[player] = false
				SendFailure(player, "商店不存在")
				return
			end
		end

		-- 4. 检查商品是否在售（ShopConfig核心功能）
		local onSale, reason = ShopConfig.IsUnitOnSale(shopId, unitId, player)
		if not onSale then
			PurchaseLocks[player] = false
			SendFailure(player, reason or "商品未上架")
			return
		end

		-- 4.1. V2.1库存功能：检查库存
		if GameConfig.Shop.EnableStockSystem then
			local stock = GetPlayerStock(player, shopId, unitId)
			if stock <= 0 then
				PurchaseLocks[player] = false
				SendFailure(player, "库存不足，已售罄")
				return
			end
		end

		-- 5. 读取价格（V2.1修复：优先且强制使用ShopConfig价格）
		local price = ShopConfig.GetPrice(shopId, unitId)
		if not price then
			-- ShopConfig中必须配置价格，如果没有则是配置错误
			PurchaseLocks[player] = false
			SendFailure(player, string.format("商品[%s]价格配置错误", unitId))
			warn(string.format(
				"[ShopSystem] 商店[%s]中[%s]没有配置价格，请检查ShopConfig",
				shopId, unitId
			))
			return
		end

		-- V2.1调试：记录实际使用的价格
		if DEBUG_MODE then
			print(string.format(
				"%s [ShopSystem] 购买验证 - 玩家:%s UnitId:%s 价格:%d金币",
				GameConfig.LOG_PREFIX,
				player.Name,
				unitId,
				price
			))
		end

		-- 6. 距离校验（可选）
		if GameConfig.Shop.EnableDistanceCheck then
			local distance = GetDistanceToShopNPC(player)
			if distance > GameConfig.Shop.OpenDistance then
				PurchaseLocks[player] = false
				SendFailure(player, "距离商人太远，无法购买")
				return
			end
		end

		-- 7. 校验金币是否足够
		if not CurrencySystem.HasEnoughCoins(player, price) then
			PurchaseLocks[player] = false
			SendFailure(player, string.format("金币不足，需要 %d 金币", price))
			-- V3.8新增：播放错误音效
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

		-- 8. 扣除金币
		local deductSuccess, newCoins = CurrencySystem.RemoveCoins(player, price, "购买兵种: " .. unitId)
		if not deductSuccess then
			PurchaseLocks[player] = false
			SendFailure(player, "金币扣除失败")
			return
		end

		-- 9. 发放兵种
		local addSuccess, instanceData = InventorySystem.AddUnit(player, unitId)
		if not addSuccess then
			-- 失败时回滚金币
			CurrencySystem.AddCoins(player, price, "购买失败退款: " .. unitId)
			PurchaseLocks[player] = false
			SendFailure(player, "兵种发放失败: " .. tostring(instanceData))
			return
		end

		-- 9.1. V2.1库存功能：扣除库存
		if GameConfig.Shop.EnableStockSystem then
			local deductSuccess = DeductStock(player, shopId, unitId, 1)
			if not deductSuccess then
				-- 扣除库存失败（理论上不应该发生，因为之前已检查）
				-- 回滚金币和兵种
				CurrencySystem.AddCoins(player, price, "库存扣除失败退款: " .. unitId)
				InventorySystem.RemoveUnit(player, instanceData.InstanceId) -- 需要InventorySystem支持移除
				PurchaseLocks[player] = false
				SendFailure(player, "库存扣除失败，已退款")
				warn(string.format("[ShopSystem] 库存扣除失败，理论上不应发生: %s", unitId))
				return
			end
		end

		-- 10. 购买成功
		LastPurchaseTime[player] = now
		PurchaseLocks[player] = false

		local instanceId = type(instanceData) == "table" and instanceData.InstanceId or "unknown"
		SendSuccess(player, "购买成功", unitId, newCoins, instanceId)

		-- V3.3任务系统：通知购买兵种
		local TaskSystem = nil
		local taskModule = ServerScriptService.Systems:FindFirstChild("TaskSystem")
		if taskModule then
			TaskSystem = require(taskModule)
			TaskSystem.OnPurchaseUnit(player, unitId)
		end

	end)

	if not success then
		-- 发生未预料的错误，清理锁并通知客户端
		PurchaseLocks[player] = false
		warn("[ShopSystem] OnPurchaseUnit 严重错误: " .. tostring(result))
		SendFailure(player, "系统错误，请重试")
	end
end

--[[
玩家离开游戏时清理数据（V2.1库存系统：保留PlayerStockData以支持快速重登）
@param player Player - 离开的玩家
]]
local function OnPlayerRemoving(player)
	-- 清理玩家相关数据
	PurchaseLocks[player] = nil
	LastPurchaseTime[player] = nil

	-- V2.1库存系统：停止刷新定时器，但保留库存数据（已持久化到DataManager）
	if GameConfig.Shop.EnableStockSystem then
		StopRefreshTimer(player)
		-- 注意：不再清空 PlayerStockData[player]，因为：
		-- 1. LastRefreshTime 已持久化到 DataManager
		-- 2. 保留内存数据可以在玩家快速重登时减少重新初始化开销
		-- 3. 玩家真正离线后，数据会自然被垃圾回收
	end

end

-- ==================== 公共接口 ====================

--[[
初始化商店系统
@return boolean - 是否成功
]]
function ShopSystem.Initialize()

	-- 1. 初始化依赖模块
	if not InitializeDependencies() then
		warn("[ShopSystem] 依赖模块初始化失败")
		return false
	end

	-- 2. 验证ShopConfig配置
	local configSuccess, configErrors = ShopConfig.ValidateShopConfig()
	if not configSuccess then
		warn("[ShopSystem] ShopConfig配置有误，将回退到UnitConfig模式:")
		for _, error in ipairs(configErrors) do
			warn("  - " .. error)
		end
	end

	-- 3. 初始化事件
	if not InitializeEvents() then
		warn("[ShopSystem] 事件初始化失败")
		return false
	end

	-- 4. 绑定事件处理
	local bindSuccess, bindError = pcall(function()
		RequestShopList.OnServerEvent:Connect(OnRequestShopList)
		PurchaseUnit.OnServerEvent:Connect(OnPurchaseUnit)
	end)

	if not bindSuccess then
		warn("[ShopSystem] 事件绑定失败: " .. tostring(bindError))
		return false
	end

	-- 5. 绑定玩家离开事件
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- 6. 输出初始化结果（仅在调试模式下）
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

--[[
获取商店统计信息（调试用）
@return table - 统计信息
]]
function ShopSystem.GetShopStats()
	local stats = {
		TotalShops = #ShopConfig.GetAllShopIds(),
		ActivePlayers = 0,
		PendingPurchases = 0,
	}

	-- 统计活跃玩家和待处理购买
	for player, _ in pairs(PurchaseLocks) do
		if player.Parent then -- 玩家仍在游戏中
			stats.ActivePlayers = stats.ActivePlayers + 1
		end
	end

	for player, locked in pairs(PurchaseLocks) do
		if locked then
			stats.PendingPurchases = stats.PendingPurchases + 1
		end
	end

	return stats
end

--[[
强制清理玩家购买锁（管理员工具）
@param player Player - 要清理的玩家
]]
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

--[[
V2.1库存系统：初始化玩家商店定时器（在玩家进入游戏时调用）
@param player Player - 玩家实例
@param shopId string - 商店ID（可选，默认为"UnitShop"）
]]
function ShopSystem.InitializePlayerShopTimer(player, shopId)
	if not GameConfig.Shop.EnableStockSystem then
		return
	end

	shopId = shopId or "UnitShop" -- 默认商店

	-- 初始化库存数据（从DataManager恢复）
	InitializePlayerStock(player, shopId)

	-- 启动刷新定时器
	StartRefreshTimer(player, shopId)

	-- V3.1新增：同时初始化技能商店定时器（共享刷新周期）
	local SkillShopSystem = nil
	local skillSystemModule = ServerScriptService.Systems:FindFirstChild("SkillShopSystem")
	if skillSystemModule then
		local success, result = pcall(function()
			return require(skillSystemModule)
		end)
		if success then
			SkillShopSystem = result
			SkillShopSystem.InitializePlayerSkillShopTimer(player, "SkillShop")
		end
	end
end

return ShopSystem