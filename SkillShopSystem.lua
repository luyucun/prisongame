--[[
=====================================================
脚本名称: SkillShopSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/SkillShopSystem.lua
版本: V3.1
=====================================================

功能描述:
- 管理技能商店的购买逻辑
- 处理金币和Robux两种支付方式
- 与兵种商店共享刷新周期
- 管理技能库存刷新
- 与DataManager集成实现数据持久化

=====================================================
]]

local SkillShopSystem = {}

-- 调试配置
local DEBUG_MODE = false

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

-- 引用配置模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))
local SkillShopConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillShopConfig"))

-- 延迟加载系统模块（避免循环依赖）
local CurrencySystem = nil
local DataManager = nil
local SoundSystem = nil  -- V3.8新增：音效系统

-- 私有变量
local PurchaseLocks = {}      -- 购买锁（防止并发购买）
local LastPurchaseTime = {}   -- 最后购买时间（冷却机制）

-- 库存系统变量
local PlayerSkillStockData = {}    -- 玩家技能库存数据: [player] = {[shopId] = {[skillId] = stock, LastRefreshTime = tick()}}
local SkillRefreshTimers = {}      -- 刷新定时器: [player] = timer
local SkillTimerUpdateConnections = {} -- 倒计时更新连接: [player] = connection
local LastSkillTimerUpdate = {}    -- 定时器更新时间戳: [player] = timestamp

-- 事件引用
local SkillShopEvents = nil
local RequestSkillShopList = nil
local SkillShopListEvent = nil
local PurchaseSkill = nil
local PurchaseSkillRobux = nil        -- Robux购买事件
local SkillPurchaseResult = nil
local SkillStockUpdate = nil
local SkillRefreshTimeUpdate = nil

-- 配置常量
local PURCHASE_COOLDOWN = 0.3  -- 购买冷却(秒)

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
			warn("[SkillShopSystem] CurrencySystem模块未找到")
			return false
		end
	end

	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if dataModule then
			DataManager = require(dataModule)
		else
			warn("[SkillShopSystem] DataManager模块未找到")
			return false
		end
	end

	return true
end

--[[
初始化SkillShopEvents事件
@return boolean - 是否成功
]]
local function InitializeEvents()
	if SkillShopEvents then
		return true -- 已初始化
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	SkillShopEvents = eventsFolder:FindFirstChild("SkillShopEvents")
	if not SkillShopEvents then
		-- 创建SkillShopEvents文件夹
		SkillShopEvents = Instance.new("Folder")
		SkillShopEvents.Name = "SkillShopEvents"
		SkillShopEvents.Parent = eventsFolder
	end

	-- 创建所需的RemoteEvent
	local eventNames = {
		"RequestSkillShopList",   -- 客户端→服务器：请求技能商店列表
		"SkillShopList",          -- 服务器→客户端：返回技能商店列表
		"PurchaseSkill",          -- 客户端→服务器：购买技能（金币）
		"PurchaseSkillRobux",     -- 客户端→服务器：购买技能（Robux）
		"SkillPurchaseResult",    -- 服务器→客户端：购买结果
		"SkillStockUpdate",       -- 服务器→客户端：库存更新
		"SkillRefreshTimeUpdate", -- 服务器→客户端：刷新倒计时
	}

	for _, eventName in ipairs(eventNames) do
		if not SkillShopEvents:FindFirstChild(eventName) then
			local event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = SkillShopEvents
		end
	end

	-- 获取事件引用
	RequestSkillShopList = SkillShopEvents:FindFirstChild("RequestSkillShopList")
	SkillShopListEvent = SkillShopEvents:FindFirstChild("SkillShopList")
	PurchaseSkill = SkillShopEvents:FindFirstChild("PurchaseSkill")
	PurchaseSkillRobux = SkillShopEvents:FindFirstChild("PurchaseSkillRobux")
	SkillPurchaseResult = SkillShopEvents:FindFirstChild("SkillPurchaseResult")
	SkillStockUpdate = SkillShopEvents:FindFirstChild("SkillStockUpdate")
	SkillRefreshTimeUpdate = SkillShopEvents:FindFirstChild("SkillRefreshTimeUpdate")

	return RequestSkillShopList and SkillShopListEvent and PurchaseSkill and SkillPurchaseResult
end

--[[
根据玩家位置确定附近的技能商店ID
@param player Player - 玩家实例
@return string|nil - 商店ID，未找到返回nil
]]
local function GetPlayerNearbySkillShopId(player)
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

	-- 遍历所有技能商店NPC
	for shopId, shopData in pairs(SkillShopConfig.Shops) do
		local npc = playerHome:FindFirstChild(shopData.NPCName)
		if npc then
			local npcPart = npc:FindFirstChild("HumanoidRootPart")
			             or npc.PrimaryPart
			             or npc:FindFirstChildWhichIsA("BasePart")

			if npcPart then
				local distance = (rootPart.Position - npcPart.Position).Magnitude
				if distance <= GameConfig.Shop.OpenDistance then
					return shopId
				end
			end
		end
	end

	return nil
end

-- ==================== 库存系统函数 ====================

-- 统一库存表key为字符串（RemoteEvent/DataStore会导致数字key不稳定）
local function NormalizeSkillStockData(stockData)
	if not stockData then
		return
	end

	for key, value in pairs(stockData) do
		if key ~= "LastRefreshTime" and type(key) ~= "string" then
			local stringKey = tostring(key)
			stockData[stringKey] = value
			stockData[key] = nil
		end
	end
end

--[[
初始化玩家技能库存数据
@param player Player - 玩家实例
@param shopId string - 商店ID
]]
local function InitializePlayerSkillStock(player, shopId)
	if not PlayerSkillStockData[player] then
		PlayerSkillStockData[player] = {}
	end

	if not PlayerSkillStockData[player][shopId] then
		-- 从DataManager读取持久化数据
		local shopData = DataManager and DataManager.GetShopData(player, "Skill_" .. shopId)
		local lastRefreshTime = shopData and shopData.LastRefreshTime or 0
		local savedStock = (shopData and shopData.Stock) or {}

		PlayerSkillStockData[player][shopId] = {
			LastRefreshTime = lastRefreshTime,
		}

		-- 恢复保存的库存数据
		for skillId, stock in pairs(savedStock) do
			if type(stock) == "number" then
				local stockKey = tostring(skillId)
				PlayerSkillStockData[player][shopId][stockKey] = stock
			end
		end

		NormalizeSkillStockData(PlayerSkillStockData[player][shopId])

		if DEBUG_MODE then
			local itemCount = 0
			for _ in pairs(savedStock) do
				itemCount = itemCount + 1
			end
			print(string.format(
				"%s [SkillShopSystem] 恢复技能库存 - 玩家:%s 商店:%s 恢复:%d个商品",
				GameConfig.LOG_PREFIX,
				player.Name,
				shopId,
				itemCount
			))
		end
	end
end

--[[
刷新技能商店库存
@param player Player - 玩家实例
@param shopId string - 商店ID
@return table - 刷新后的库存数据 {[skillId] = stock}
]]
local function RefreshSkillShopStock(player, shopId)
	InitializePlayerSkillStock(player, shopId)

	local stockData = PlayerSkillStockData[player][shopId]
	local shopData = SkillShopConfig.Shops[shopId]

	if not shopData then
		warn(string.format("[SkillShopSystem] 刷新库存失败: 商店[%s]不存在", shopId))
		return {}
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [SkillShopSystem] 开始刷新技能库存 - 玩家:%s 商店:%s",
			GameConfig.LOG_PREFIX,
			player.Name,
			shopId
		))
	end

	NormalizeSkillStockData(stockData)
	for key, _ in pairs(stockData) do
		if key ~= "LastRefreshTime" then
			stockData[key] = nil
		end
	end

	-- 遍历商店中的所有技能商品并刷新库存
	local refreshCount = 0
	for _, itemConfig in ipairs(shopData.Items) do
		if itemConfig.ItemType == "Skill" and itemConfig.Enabled then
			local skillId = itemConfig.SkillId
			local stockConfig = SkillShopConfig.GetStockConfig(shopId, skillId)

			if stockConfig then
				local probability = stockConfig.RefreshProbability
				local hasStock = math.random() <= probability

				if hasStock then
					local stock = math.random(stockConfig.StockMin, stockConfig.StockMax)
					local stockKey = tostring(skillId)
					stockData[stockKey] = stock
					refreshCount = refreshCount + 1
				else
					local stockKey = tostring(skillId)
					stockData[stockKey] = 0
				end
			end
		end
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [SkillShopSystem] 库存刷新完成 - 玩家:%s 有库存商品:%d/%d",
			GameConfig.LOG_PREFIX,
			player.Name,
			refreshCount,
			#shopData.Items
		))
	end

	-- 更新刷新时间
	stockData.LastRefreshTime = tick()

	-- 持久化到DataManager
	if DataManager then
		task.spawn(function()
			local playerData = DataManager.WaitForPlayerData(player, 10)
			if playerData then
				DataManager.SetShopRefreshTime(player, "Skill_" .. shopId, stockData.LastRefreshTime)
				DataManager.SetShopStock(player, "Skill_" .. shopId, stockData)
			end
		end)
	end

	-- 通知客户端库存更新
	if SkillStockUpdate then
		pcall(function()
			local stockToSend = {}
			for skillId, stock in pairs(stockData) do
				if skillId ~= "LastRefreshTime" and type(stock) == "number" then
					stockToSend[skillId] = stock
				end
			end
			SkillStockUpdate:FireClient(player, shopId, stockToSend)
		end)
	end

	return stockData
end

--[[
获取玩家技能商店库存
@param player Player - 玩家实例
@param shopId string - 商店ID
@param skillId number - 技能ID (可选)
@return number|table - 库存数量或库存表
]]
local function GetPlayerSkillStock(player, shopId, skillId)
	InitializePlayerSkillStock(player, shopId)

	local stockData = PlayerSkillStockData[player][shopId]
	NormalizeSkillStockData(stockData)

	if skillId then
		local stockKey = tostring(skillId)
		return stockData[stockKey] or 0
	else
		local result = {}
		for key, value in pairs(stockData) do
			if key ~= "LastRefreshTime" and type(value) == "number" then
				result[key] = value
			end
		end
		return result
	end
end

--[[
扣除技能库存
@param player Player - 玩家实例
@param shopId string - 商店ID
@param skillId number - 技能ID
@param amount number - 扣除数量
@return boolean - 是否成功
]]
local function DeductSkillStock(player, shopId, skillId, amount)
	amount = amount or 1
	local currentStock = GetPlayerSkillStock(player, shopId, skillId)

	if currentStock < amount then
		return false
	end

	local stockKey = tostring(skillId)
	PlayerSkillStockData[player][shopId][stockKey] = currentStock - amount

	-- 持久化
	if DataManager then
		task.spawn(function()
			local stockData = GetPlayerSkillStock(player, shopId)
			DataManager.SetShopStock(player, "Skill_" .. shopId, stockData)
		end)
	end

	-- 通知客户端
	if SkillStockUpdate then
		pcall(function()
			local stockToSend = GetPlayerSkillStock(player, shopId)
			SkillStockUpdate:FireClient(player, shopId, stockToSend)
		end)
	end

	return true
end

--[[
启动玩家的技能库存刷新定时器
@param player Player - 玩家实例
@param shopId string - 商店ID
]]
local function StartSkillRefreshTimer(player, shopId)
	-- 清理旧的定时器
	if SkillRefreshTimers[player] then
		task.cancel(SkillRefreshTimers[player])
		SkillRefreshTimers[player] = nil
	end
	if SkillTimerUpdateConnections[player] then
		SkillTimerUpdateConnections[player]:Disconnect()
		SkillTimerUpdateConnections[player] = nil
	end

	local refreshInterval = SkillShopConfig.GetRefreshInterval(shopId)
	if not refreshInterval or refreshInterval <= 0 then
		refreshInterval = GameConfig.Shop.DefaultRefreshInterval or 300
	end

	InitializePlayerSkillStock(player, shopId)

	local stockData = PlayerSkillStockData[player][shopId]
	local lastRefreshTime = stockData.LastRefreshTime

	-- 检查是否有恢复的库存数据
	local hasRestoredStock = false
	for skillId, stock in pairs(stockData) do
		if skillId ~= "LastRefreshTime" and type(stock) == "number" then
			hasRestoredStock = true
			break
		end
	end

	-- 计算下次刷新时间
	local nextRefreshTime
	if lastRefreshTime == 0 and not hasRestoredStock then
		-- 首次进入，立即刷新
		RefreshSkillShopStock(player, shopId)
		nextRefreshTime = tick() + refreshInterval
	elseif lastRefreshTime == 0 and hasRestoredStock then
		-- 老数据迁移场景
		stockData.LastRefreshTime = tick()
		nextRefreshTime = tick() + refreshInterval
	else
		-- 计算离线时间
		local offlineTime = tick() - lastRefreshTime
		if offlineTime >= refreshInterval then
			RefreshSkillShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
		else
			nextRefreshTime = lastRefreshTime + refreshInterval
		end
	end

	-- 设置刷新定时器
	local function scheduleRefresh()
		local remainingTime = nextRefreshTime - tick()
		if remainingTime <= 0 then
			RefreshSkillShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
			remainingTime = refreshInterval
		end

		SkillRefreshTimers[player] = task.delay(remainingTime, function()
			RefreshSkillShopStock(player, shopId)
			nextRefreshTime = tick() + refreshInterval
			scheduleRefresh()
		end)
	end

	scheduleRefresh()

	-- 启动倒计时更新
	if SkillRefreshTimeUpdate then
		SkillTimerUpdateConnections[player] = RunService.Heartbeat:Connect(function()
			local now = tick()
			if not LastSkillTimerUpdate[player] or (now - LastSkillTimerUpdate[player]) >= 1 then
				LastSkillTimerUpdate[player] = now
				local remainingTime = math.max(0, nextRefreshTime - now)
				pcall(function()
					SkillRefreshTimeUpdate:FireClient(player, math.floor(remainingTime))
				end)
			end
		end)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [SkillShopSystem] 启动技能刷新定时器 - 玩家:%s 商店:%s 间隔:%ds",
			GameConfig.LOG_PREFIX,
			player.Name,
			shopId,
			refreshInterval
		))
	end
end

--[[
停止玩家的技能库存刷新定时器
@param player Player - 玩家实例
]]
local function StopSkillRefreshTimer(player)
	if SkillRefreshTimers[player] then
		task.cancel(SkillRefreshTimers[player])
		SkillRefreshTimers[player] = nil
	end

	if SkillTimerUpdateConnections[player] then
		SkillTimerUpdateConnections[player]:Disconnect()
		SkillTimerUpdateConnections[player] = nil
	end

	LastSkillTimerUpdate[player] = nil
end

-- ==================== 辅助函数 ====================

--[[
发送购买失败结果
@param player Player - 玩家
@param message string - 失败消息
]]
local function SendFailure(player, message)
	if SkillPurchaseResult then
		pcall(function()
			SkillPurchaseResult:FireClient(player, false, message, nil, nil)
		end)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [SkillShopSystem] 购买失败 - 玩家:%s 原因:%s",
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
@param skillId number - 技能ID
@param newCoins number - 新的金币数量
]]
local function SendSuccess(player, message, skillId, newCoins)
	if SkillPurchaseResult then
		pcall(function()
			SkillPurchaseResult:FireClient(player, true, message, skillId, newCoins)
		end)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [SkillShopSystem] 购买成功 - 玩家:%s 技能:%d 剩余金币:%d",
			GameConfig.LOG_PREFIX,
			player.Name,
			skillId,
			newCoins
		))
	end
end

-- ==================== 事件处理函数 ====================

--[[
处理客户端请求技能商店列表
@param player Player - 请求的玩家
]]
local function OnRequestSkillShopList(player)
	local success, result = pcall(function()
		-- 确定商店ID
		local shopId = GetPlayerNearbySkillShopId(player)
		if not shopId then
			shopId = "SkillShop" -- 回退到默认商店
		end

		-- 获取商品列表
		local shopItems = SkillShopConfig.GetShopItems(shopId, player)

		-- 确保玩家有库存数据
		if not PlayerSkillStockData[player] or not PlayerSkillStockData[player][shopId] then
			SkillShopSystem.InitializePlayerSkillShopTimer(player, shopId)
		end

		-- 获取库存数据
		local stockData = GetPlayerSkillStock(player, shopId)

		-- 将库存信息添加到每个商品
		for _, item in ipairs(shopItems) do
			local stockKey = tostring(item.SkillId)
			item.Stock = stockData[stockKey] or 0
		end

		-- 发送到客户端
		if SkillShopListEvent then
			SkillShopListEvent:FireClient(player, shopItems)
		end

		if DEBUG_MODE then
			print(string.format(
				"%s [SkillShopSystem] 玩家 %s 请求技能商店[%s]，返回 %d 个商品",
				GameConfig.LOG_PREFIX,
				player.Name,
				shopId,
				#shopItems
			))
		end
	end)

	if not success then
		warn("[SkillShopSystem] OnRequestSkillShopList 错误: " .. tostring(result))
		if SkillShopListEvent then
			SkillShopListEvent:FireClient(player, {})
		end
	end
end

--[[
处理客户端购买技能请求
@param player Player - 购买的玩家
@param skillId number - 要购买的技能ID
]]
local function OnPurchaseSkill(player, skillId)
	local success, result = pcall(function()
		-- 1. 购买锁检查
		if PurchaseLocks[player] then
			SendFailure(player, "请稍等，正在处理上一个购买请求")
			return
		end

		PurchaseLocks[player] = true

		-- 2. 冷却检查
		local now = tick()
		if LastPurchaseTime[player] then
			local timeSinceLastPurchase = now - LastPurchaseTime[player]
			if timeSinceLastPurchase < PURCHASE_COOLDOWN then
				PurchaseLocks[player] = false
				SendFailure(player, "购买冷却中，请稍候")
				return
			end
		end

		-- 3. 确定商店ID
		local shopId = GetPlayerNearbySkillShopId(player)
		if not shopId then
			shopId = "SkillShop"
			if not SkillShopConfig.Shops[shopId] then
				PurchaseLocks[player] = false
				SendFailure(player, "商店不存在")
				return
			end
		end

		-- 4. 检查技能是否在售
		local onSale, reason = SkillShopConfig.IsSkillOnSale(shopId, skillId, player)
		if not onSale then
			PurchaseLocks[player] = false
			SendFailure(player, reason or "技能未上架")
			return
		end

		-- 5. 检查库存
		local stock = GetPlayerSkillStock(player, shopId, skillId)
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

		-- 6. 读取价格
		local price = SkillShopConfig.GetPrice(shopId, skillId)
		if not price or price <= 0 then
			PurchaseLocks[player] = false
			SendFailure(player, "价格配置错误")
			return
		end
		-- 确保price是有效数字（类型断言）
		local validPrice = price :: number

		if DEBUG_MODE then
			print(string.format(
				"%s [SkillShopSystem] 购买验证 - 玩家:%s SkillId:%d 价格:%d金币",
				GameConfig.LOG_PREFIX,
				player.Name,
				skillId,
				validPrice
			))
		end

		-- 7. 距离校验
		if GameConfig.Shop.EnableDistanceCheck then
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local homeSlot = player:GetAttribute("HomeSlot")
				local home = workspace:FindFirstChild("Home")
				local playerHome = home and home:FindFirstChild("PlayerHome" .. homeSlot)
				if playerHome then
					local shopData = SkillShopConfig.Shops[shopId]
					local npc = playerHome:FindFirstChild(shopData.NPCName)
					if npc then
						local npcPart = npc:FindFirstChild("HumanoidRootPart")
						             or npc.PrimaryPart
						             or npc:FindFirstChildWhichIsA("BasePart")
						if npcPart then
							local distance = (rootPart.Position - npcPart.Position).Magnitude
							if distance > GameConfig.Shop.OpenDistance then
								PurchaseLocks[player] = false
								SendFailure(player, "距离商人太远，无法购买")
								return
							end
						end
					end
				end
			end
		end

		-- 8. 校验金币是否足够
		if not CurrencySystem.HasEnoughCoins(player, validPrice) then
			PurchaseLocks[player] = false
			SendFailure(player, string.format("金币不足，需要 %d 金币", validPrice))
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

		-- 9. 扣除金币
		local deductSuccess, newCoins = CurrencySystem.RemoveCoins(player, validPrice, "购买技能: " .. skillId)
		if not deductSuccess then
			PurchaseLocks[player] = false
			SendFailure(player, "金币扣除失败")
			return
		end

		-- 10. 发放技能
		local addSuccess, newCount = DataManager.AddSkill(player, skillId, 1)
		if not addSuccess then
			-- 失败时回滚金币
			CurrencySystem.AddCoins(player, validPrice, "购买失败退款: " .. skillId, { ApplyVipBonus = false, ApplyFriendBonus = false })
			PurchaseLocks[player] = false
			SendFailure(player, "技能发放失败")
			return
		end

		-- 11. 扣除库存
		local stockDeductSuccess = DeductSkillStock(player, shopId, skillId, 1)
		if not stockDeductSuccess then
			-- 回滚金币和技能
			CurrencySystem.AddCoins(player, validPrice, "库存扣除失败退款: " .. skillId, { ApplyVipBonus = false, ApplyFriendBonus = false })
			DataManager.RemoveSkill(player, skillId, 1)
			PurchaseLocks[player] = false
			SendFailure(player, "库存扣除失败，已退款")
			return
		end

		-- 12. 保存玩家数据
		DataManager.SavePlayerDataThrottled(player)

		-- 13. 购买成功
		LastPurchaseTime[player] = now
		PurchaseLocks[player] = false

		SendSuccess(player, "购买成功", skillId, newCoins)

		-- 14. 同步技能背包到客户端
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			local skillEvents = eventsFolder:FindFirstChild("SkillEvents")
			if skillEvents then
				local inventoryUpdate = skillEvents:FindFirstChild("SkillInventoryUpdate")
				if inventoryUpdate then
					local inventory = DataManager.GetSkillInventory(player)
					inventoryUpdate:FireClient(player, inventory)
				end
			end
		end

	end)

	if not success then
		PurchaseLocks[player] = false
		warn("[SkillShopSystem] OnPurchaseSkill 严重错误: " .. tostring(result))
		SendFailure(player, "系统错误，请重试")
	end
end

--[[
处理客户端Robux购买请求
@param player Player - 玩家实例
@param skillId number - 技能ID
]]
local function OnPurchaseSkillRobux(player, skillId)
	local success, result = pcall(function()
		-- 1. 购买锁检查
		if PurchaseLocks[player] then
			SendFailure(player, "请稍等，正在处理上一个购买请求")
			return
		end
		PurchaseLocks[player] = true

		-- 2. 购买冷却检查
		local now = tick()
		if LastPurchaseTime[player] then
			local timeSinceLastPurchase = now - LastPurchaseTime[player]
			if timeSinceLastPurchase < PURCHASE_COOLDOWN then
				PurchaseLocks[player] = false
				SendFailure(player, "购买冷却中，请稍候")
				return
			end
		end

		-- 3. 验证技能ID
		if not SkillConfig.IsValidSkill(skillId) then
			PurchaseLocks[player] = false
			SendFailure(player, "无效的技能")
			return
		end

		-- 4. 获取商店ID和DevProductId（从SkillShopConfig获取）
		local shopId = GetPlayerNearbySkillShopId(player) or "SkillShop"
		local devProductId = SkillShopConfig.GetDevProductId(shopId, skillId)
		if not devProductId or devProductId == "" or devProductId == "0" then
			PurchaseLocks[player] = false
			SendFailure(player, "该技能不支持Robux购买")
			return
		end

		-- 5. 距离检查（可选）
		if GameConfig.Shop.EnableDistanceCheck then
			local nearbyShopId = GetPlayerNearbySkillShopId(player)
			if not nearbyShopId then
				PurchaseLocks[player] = false
				SendFailure(player, "距离商人太远，无法购买")
				return
			end
		end

		-- 6. 查找MarketplaceHandler模块
		local marketplaceModule = ServerScriptService.Systems:FindFirstChild("MarketplaceHandler")
		if not marketplaceModule then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			warn("[SkillShopSystem] 未找到 MarketplaceHandler 模块")
			return
		end

		if not marketplaceModule:IsA("ModuleScript") then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			warn("[SkillShopSystem] MarketplaceHandler 不是ModuleScript")
			return
		end

		-- 7. 加载MarketplaceHandler并提示购买
		local loadSuccess, loadResult = pcall(require, marketplaceModule)
		if not loadSuccess then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			warn("[SkillShopSystem] MarketplaceHandler 加载失败: " .. tostring(loadResult))
			return
		end

		local marketplaceHandler = loadResult :: any
		local shopId = GetPlayerNearbySkillShopId(player) or "SkillShop"
		local promptSuccess = marketplaceHandler.PromptSkillPurchase(player, skillId, shopId)

		if not promptSuccess then
			PurchaseLocks[player] = false
			SendFailure(player, "无法打开购买界面")
			return
		end

		-- 8. 重置购买状态
		LastPurchaseTime[player] = now
		PurchaseLocks[player] = false

		if DEBUG_MODE then
			print(string.format(
				"%s [SkillShopSystem] 提示Robux购买技能 - 玩家:%s SkillId:%d",
				GameConfig.LOG_PREFIX,
				player.Name,
				skillId
			))
		end
	end)

	if not success then
		PurchaseLocks[player] = false
		warn("[SkillShopSystem] OnPurchaseSkillRobux 错误: " .. tostring(result))
		SendFailure(player, "系统错误，请重试")
	end
end

--[[
玩家离开游戏时清理数据
@param player Player - 离开的玩家
]]
local function OnPlayerRemoving(player)
	PurchaseLocks[player] = nil
	LastPurchaseTime[player] = nil
	StopSkillRefreshTimer(player)
end

-- ==================== 公共接口 ====================

--[[
初始化技能商店系统
@return boolean - 是否成功
]]
function SkillShopSystem.Initialize()
	-- 1. 初始化依赖模块
	if not InitializeDependencies() then
		warn("[SkillShopSystem] 依赖模块初始化失败")
		return false
	end

	-- 2. 验证SkillShopConfig配置
	local configSuccess, configErrors = SkillShopConfig.ValidateShopConfig()
	if not configSuccess then
		warn("[SkillShopSystem] SkillShopConfig配置有误:")
		for _, err in ipairs(configErrors) do
			warn("  - " .. err)
		end
	end

	-- 3. 初始化事件
	if not InitializeEvents() then
		warn("[SkillShopSystem] 事件初始化失败")
		return false
	end

	-- 4. 绑定事件处理
	local bindSuccess, bindError = pcall(function()
		RequestSkillShopList.OnServerEvent:Connect(OnRequestSkillShopList)
		PurchaseSkill.OnServerEvent:Connect(OnPurchaseSkill)
		if PurchaseSkillRobux then
			PurchaseSkillRobux.OnServerEvent:Connect(OnPurchaseSkillRobux)
		end
	end)

	if not bindSuccess then
		warn("[SkillShopSystem] 事件绑定失败: " .. tostring(bindError))
		return false
	end

	-- 5. 绑定玩家离开事件
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- 6. 输出初始化结果（仅在调试模式下）
	if DEBUG_MODE then
		print(string.format(
			"%s [SkillShopSystem] 技能商店系统已就绪",
			GameConfig.LOG_PREFIX
		))
		print(string.format(
			"%s [SkillShopSystem] 配置状态: %s",
			GameConfig.LOG_PREFIX,
			configSuccess and "配置正常" or "配置异常"
		))
	end

	return true
end

--[[
初始化玩家技能商店定时器（在玩家进入游戏时调用）
@param player Player - 玩家实例
@param shopId string - 商店ID（可选，默认为"SkillShop"）
]]
function SkillShopSystem.InitializePlayerSkillShopTimer(player, shopId)
	shopId = shopId or "SkillShop"

	-- 初始化库存数据
	InitializePlayerSkillStock(player, shopId)

	-- 启动刷新定时器
	StartSkillRefreshTimer(player, shopId)
end

--[[
获取商店统计信息（调试用）
@return table - 统计信息
]]
function SkillShopSystem.GetShopStats()
	local stats = {
		TotalShops = #SkillShopConfig.GetAllShopIds(),
		ActivePlayers = 0,
		PendingPurchases = 0,
	}

	for player, _ in pairs(PurchaseLocks) do
		if player.Parent then
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
function SkillShopSystem.ClearPlayerLock(player)
	PurchaseLocks[player] = nil
	LastPurchaseTime[player] = nil
	if DEBUG_MODE then
		print(string.format(
			"%s [SkillShopSystem] 管理员清理玩家锁: %s",
			GameConfig.LOG_PREFIX,
			player.Name
		))
	end
end

return SkillShopSystem
