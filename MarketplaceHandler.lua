--[[
=====================================================
脚本名称: MarketplaceHandler
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/MarketplaceHandler.lua
版本: V1.0
=====================================================

功能描述:
- 统一处理Roblox MarketplaceService的购买回调
- 支持兵种商店和技能商店的Robux购买
- 处理购买成功后的商品发放
- 防止重复发放和作弊

=====================================================
]]

local MarketplaceHandler = {}

-- 调试配置
local DEBUG_MODE = false

-- 引用服务
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ShopConfig"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))
local SkillShopConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillShopConfig"))
local LimitPrisonerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("LimitPrisonerConfig"))

-- 挂机金币10倍购买
local IDLE_COIN_PRODUCT_ID = 3487946200
local IDLE_COIN_MULTIPLIER = 10
local SEVEN_DAYS_UNLOCK_PRODUCT_ID = 3489888670
local ARMY_PACK_PRODUCTS = {
	[3511148249] = {
		{ Type = "Unit", UnitId = "10016", Count = 4 },
		{ Type = "Unit", UnitId = "10017", Count = 4 },
		{ Type = "Unit", UnitId = "10012", Count = 4 },
		{ Type = "Unit", UnitId = "10014", Count = 4 },
	},
	[3511148622] = {
		{ Type = "Unit", UnitId = "10010", Count = 4 },
		{ Type = "Unit", UnitId = "10011", Count = 4 },
		{ Type = "Unit", UnitId = "10018", Count = 4 },
	},
}
local REVIVE_PRODUCTS = {}
do
	local reviveConfig = GameConfig.Revive or {}
	if reviveConfig.ProductIdsByChapter then
		for _, productId in pairs(reviveConfig.ProductIdsByChapter) do
			if productId then
				REVIVE_PRODUCTS[productId] = true
			end
		end
	end
end

-- 延迟加载系统模块（避免循环依赖）
local InventorySystem = nil
local DataManager = nil
local IdleCoinSystem = nil
local SevenDaysSystem = nil
local TaskSystem = nil
local armyPackEvents = nil
local armyPackPurchaseResultEvent = nil
local limitPrisonerEvents = nil
local limitPrisonerPurchaseResultEvent = nil
local reviveEvents = nil
local reviveResultEvent = nil

-- 私有变量
local ProcessedReceipts = {}  -- 已处理的收据ID: [receiptId] = true
local PurchaseHistory = {}    -- 购买历史: [player] = {[receiptId] = {time, productId}}

-- ==================== 私有辅助函数 ====================

--[[
初始化依赖模块（延迟加载）
@return boolean - 是否成功
]]
local function InitializeDependencies()
	if not InventorySystem then
		local inventoryModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if inventoryModule then
			InventorySystem = require(inventoryModule)
		else
			warn("[MarketplaceHandler] InventorySystem模块未找到")
			return false
		end
	end

	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if dataModule then
			DataManager = require(dataModule)
		else
			warn("[MarketplaceHandler] DataManager模块未找到")
			return false
		end
	end

	return true
end

--[[
延迟获取IdleCoinSystem
]]
local function GetIdleCoinSystem()
	if not IdleCoinSystem then
		local idleModule = ServerScriptService.Systems:FindFirstChild("IdleCoinSystem")
		if idleModule then
			IdleCoinSystem = require(idleModule)
		else
			warn("[MarketplaceHandler] IdleCoinSystem模块未找到")
		end
	end
	return IdleCoinSystem
end

local function GetSevenDaysSystem()
	if not SevenDaysSystem then
		local sevenDaysModule = ServerScriptService.Systems:FindFirstChild("SevenDaysSystem")
		if sevenDaysModule then
			SevenDaysSystem = require(sevenDaysModule)
		else
			warn("[MarketplaceHandler] SevenDaysSystem模块未找到")
		end
	end
	return SevenDaysSystem
end

local function GetTaskSystem()
	if not TaskSystem then
		local taskModule = ServerScriptService.Systems:FindFirstChild("TaskSystem")
		if taskModule and taskModule:IsA("ModuleScript") then
			local ok, result = pcall(require, taskModule)
			if ok then
				TaskSystem = result
			else
				warn("[MarketplaceHandler] TaskSystem妯″潡鍔犺浇澶辫触:", result)
			end
		end
	end
	return TaskSystem
end

local function EnsureArmyPackEvents()
	if armyPackPurchaseResultEvent then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	armyPackEvents = eventsFolder:FindFirstChild("ArmyPackEvents")
	if not armyPackEvents then
		armyPackEvents = Instance.new("Folder")
		armyPackEvents.Name = "ArmyPackEvents"
		armyPackEvents.Parent = eventsFolder
	end

	local event = armyPackEvents:FindFirstChild("ArmyPackPurchaseResult")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "ArmyPackPurchaseResult"
		event.Parent = armyPackEvents
	end

	armyPackPurchaseResultEvent = event
	return true
end

local function SendArmyPackPurchaseResult(player, success, message, productId, rewards)
	if not player or not player.Parent then
		return
	end
	if not EnsureArmyPackEvents() then
		return
	end
	if armyPackPurchaseResultEvent then
		armyPackPurchaseResultEvent:FireClient(player, success, message or "", productId, rewards)
	end
end

local function EnsureLimitPrisonerEvents()
	if limitPrisonerPurchaseResultEvent then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	limitPrisonerEvents = eventsFolder:FindFirstChild("LimitPrisonerEvents")
	if not limitPrisonerEvents then
		limitPrisonerEvents = Instance.new("Folder")
		limitPrisonerEvents.Name = "LimitPrisonerEvents"
		limitPrisonerEvents.Parent = eventsFolder
	end

	local event = limitPrisonerEvents:FindFirstChild("LimitPrisonerPurchaseResult")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "LimitPrisonerPurchaseResult"
		event.Parent = limitPrisonerEvents
	end

	limitPrisonerPurchaseResultEvent = event
	return true
end

local function SendLimitPrisonerPurchaseResult(player, success, message, unitId)
	if not player or not player.Parent then
		return
	end
	if not EnsureLimitPrisonerEvents() then
		return
	end
	if limitPrisonerPurchaseResultEvent then
		limitPrisonerPurchaseResultEvent:FireClient(player, success, message or "", "Robux", unitId or "", nil)
	end
end

local function EnsureReviveEvents()
	if reviveResultEvent then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	reviveEvents = eventsFolder:FindFirstChild("BattleEvents")
	if not reviveEvents then
		reviveEvents = Instance.new("Folder")
		reviveEvents.Name = "BattleEvents"
		reviveEvents.Parent = eventsFolder
	end

	local event = reviveEvents:FindFirstChild("ReviveResult")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "ReviveResult"
		event.Parent = reviveEvents
	end

	reviveResultEvent = event
	return true
end

local function SendReviveResult(player, success, message)
	if not player or not player.Parent then
		return
	end
	if not EnsureReviveEvents() then
		return
	end
	if reviveResultEvent then
		reviveResultEvent:FireClient(player, success, message or "")
	end
end

--[[
根据DevProductId查找对应的兵种ID
@param devProductId string - 开发者商品ID
@return string|nil - 兵种ID，未找到返回nil
@return string|nil - 商店ID
]]
local function FindUnitByDevProductId(devProductId)
	for shopId, shopData in pairs(ShopConfig.Shops) do
		for _, itemConfig in ipairs(shopData.Items) do
			if itemConfig.ItemType == "Unit" and itemConfig.DevProductId == devProductId then
				return itemConfig.UnitId, shopId
			end
		end
	end
	return nil, nil
end

--[[
根据DevProductId查找对应的技能ID
@param devProductId number - 开发者商品ID
@return number|nil - 技能ID，未找到返回nil
@return string|nil - 商店ID
]]
local function FindSkillByDevProductId(devProductId)
	-- 从SkillShopConfig中查找（DevProductId在商店配置中）
	return SkillShopConfig.FindSkillByDevProductId(devProductId)
end

--[[
检查收据是否已处理
@param receiptId string - 收据ID
@return boolean - 是否已处理
]]
local function IsReceiptProcessed(receiptId)
	return ProcessedReceipts[receiptId] == true
end

--[[
标记收据为已处理
@param receiptId string - 收据ID
]]
local function MarkReceiptProcessed(receiptId)
	ProcessedReceipts[receiptId] = true
end

--[[
记录购买历史
@param player Player - 玩家
@param receiptId string - 收据ID
@param productId number - 商品ID
]]
local function RecordPurchaseHistory(player, receiptId, productId)
	if not PurchaseHistory[player] then
		PurchaseHistory[player] = {}
	end
	PurchaseHistory[player][receiptId] = {
		Time = tick(),
		ProductId = productId,
	}
end

--[[
发放兵种商品
@param player Player - 玩家
@param unitId string - 兵种ID
@param shopId string - 商店ID
@return boolean - 是否成功
@return string - 消息
]]
local function GrantUnitProduct(player, unitId, shopId)
	-- 发放兵种
	local addSuccess, instanceData = InventorySystem.AddUnit(player, unitId)
	if not addSuccess then
		return false, "兵种发放失败: " .. tostring(instanceData)
	end

	-- 扣除库存（如果启用库存系统）
	if tostring(shopId) == "LimitPrisoner" then
		local taskSystem = GetTaskSystem()
		if taskSystem and taskSystem.OnPurchaseUnit then
			taskSystem.OnPurchaseUnit(player, unitId)
		end
	end

	if GameConfig.Shop.EnableStockSystem then
		local ShopSystem = require(ServerScriptService.Systems:WaitForChild("ShopSystem"))
		-- 注意：这里不扣除库存，因为Robux购买不受库存限制
		-- 如果需要扣除库存，取消下面的注释
		-- ShopSystem.DeductStock(player, shopId, unitId, 1)
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [MarketplaceHandler] 发放兵种成功 - 玩家:%s UnitId:%s",
			GameConfig.LOG_PREFIX,
			player.Name,
			unitId
		))
	end

	return true, "购买成功"
end

--[[
发放技能商品
@param player Player - 玩家
@param skillId number - 技能ID
@param shopId string - 商店ID
@return boolean - 是否成功
@return string - 消息
]]
local function GrantSkillProduct(player, skillId, shopId)
	-- 发放技能
	local addSuccess, newCount = DataManager.AddSkill(player, skillId, 1)
	if not addSuccess then
		return false, "技能发放失败"
	end

	-- 扣除库存（如果启用库存系统）
	-- 注意：Robux购买通常不受库存限制

	-- 同步技能背包到客户端
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local skillEvents = eventsFolder:FindFirstChild("SkillEvents")
		if skillEvents then
			local inventoryUpdate = skillEvents:FindFirstChild("SkillInventoryUpdate")
			if inventoryUpdate then
				local inventory = DataManager.GetSkillInventory(player)
				pcall(function()
					inventoryUpdate:FireClient(player, inventory)
				end)
			end
		end
	end

	if DEBUG_MODE then
		print(string.format(
			"%s [MarketplaceHandler] 发放技能成功 - 玩家:%s SkillId:%d",
			GameConfig.LOG_PREFIX,
			player.Name,
			skillId
		))
	end

	return true, "购买成功"
end

local function RollbackArmyPackUnits(player, grantedUnits)
	for _, instance in ipairs(grantedUnits) do
		if instance and instance.InstanceId then
			InventorySystem.RemoveUnit(player, instance.InstanceId)
		end
	end
end

local function GrantArmyPackProduct(player, rewards)
	local grantedUnits = {}
	local rewardPayload = {}

	for _, reward in ipairs(rewards) do
		local unitId = tostring(reward.UnitId or "")
		local count = tonumber(reward.Count) or 0
		if unitId == "" or count <= 0 then
			RollbackArmyPackUnits(player, grantedUnits)
			return false, "Invalid reward config"
		end

		for i = 1, count do
			local success, result = InventorySystem.AddUnit(player, unitId)
			if not success then
				RollbackArmyPackUnits(player, grantedUnits)
				return false, tostring(result or "Unit grant failed")
			end
			if type(result) == "table" and result.InstanceId then
				table.insert(grantedUnits, result)
			end
		end

		table.insert(rewardPayload, {
			Type = "Unit",
			UnitId = unitId,
			Count = count,
		})
	end

	return true, "Purchase Successful!", rewardPayload
end

-- ==================== 公共接口 ====================

--[[
处理购买收据回调
@param receiptInfo table - 收据信息
@return Enum.ProductPurchaseDecision - 购买决策
]]
function MarketplaceHandler.ProcessReceipt(receiptInfo)
	local success, result = pcall(function()
		-- 1. 初始化依赖
		if not InitializeDependencies() then
			warn("[MarketplaceHandler] 依赖模块初始化失败")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 2. 获取玩家
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- 玩家已离线，稍后重试
			warn(string.format(
				"[MarketplaceHandler] 玩家已离线，稍后重试 - UserId:%d ReceiptId:%s",
				receiptInfo.PlayerId,
				receiptInfo.PurchaseId
			))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 3. 检查收据是否已处理（防止重复发放）
		if IsReceiptProcessed(receiptInfo.PurchaseId) then
			if DEBUG_MODE then
				print(string.format(
					"%s [MarketplaceHandler] 收据已处理，跳过 - ReceiptId:%s",
					GameConfig.LOG_PREFIX,
					receiptInfo.PurchaseId
				))
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		-- 4. 转换ProductId为字符串（兼容配置格式）
		local productIdStr = tostring(receiptInfo.ProductId)
		local limitPrisoner = LimitPrisonerConfig.GetPrisonerByDevProductId(receiptInfo.ProductId)
		local limitUnitId = limitPrisoner and tostring(limitPrisoner.UnitId or "") or nil

		if DEBUG_MODE then
			print(string.format(
				"%s [MarketplaceHandler] 处理购买 - 玩家:%s ProductId:%s ReceiptId:%s",
				GameConfig.LOG_PREFIX,
				player.Name,
				productIdStr,
				receiptInfo.PurchaseId
			))
		end

		-- 5. 查找商品类型（兵种或技能）
		local unitId, unitShopId = FindUnitByDevProductId(productIdStr)
		local skillId, skillShopId = FindSkillByDevProductId(receiptInfo.ProductId)
		local armyPackRewards = ARMY_PACK_PRODUCTS[receiptInfo.ProductId]
		local isReviveProduct = REVIVE_PRODUCTS[receiptInfo.ProductId]

		local grantSuccess = false
		local grantMessage = ""

		if limitUnitId and limitUnitId ~= "" then
			grantSuccess, grantMessage = GrantUnitProduct(player, limitUnitId, "LimitPrisoner")
			if grantSuccess then
				SendLimitPrisonerPurchaseResult(player, true, "Purchase successful.", limitUnitId)
			end
		elseif unitId then
			-- 发放兵种
			grantSuccess, grantMessage = GrantUnitProduct(player, unitId, unitShopId)
		elseif skillId then
			-- 发放技能
			grantSuccess, grantMessage = GrantSkillProduct(player, skillId, skillShopId)
		elseif armyPackRewards then
			local rewardPayload
			grantSuccess, grantMessage, rewardPayload = GrantArmyPackProduct(player, armyPackRewards)
			if grantSuccess then
				SendArmyPackPurchaseResult(player, true, grantMessage, receiptInfo.ProductId, rewardPayload)
			end
		elseif isReviveProduct then
			local CampaignManager = require(ServerScriptService.Systems:WaitForChild("CampaignManager"))
			local reviveSuccess, reviveMessage = false, "复活失败"
			local ok, err = pcall(function()
				reviveSuccess, reviveMessage = CampaignManager.ProcessRevivePurchase(player, receiptInfo.ProductId)
			end)
			if not ok then
				reviveSuccess = false
				reviveMessage = "复活失败"
				warn("[MarketplaceHandler] 复活处理异常:", err)
			end
			SendReviveResult(player, reviveSuccess, reviveMessage)
			grantSuccess = true
			grantMessage = reviveMessage or "Purchase Successful!"
		elseif receiptInfo.ProductId == IDLE_COIN_PRODUCT_ID then
			-- 挂机金币10倍购买发放
			local idleSystem = GetIdleCoinSystem()
			if not idleSystem then
				warn("[MarketplaceHandler] IdleCoinSystem不可用，稍后重试")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			local awarded, awardCoins = idleSystem.ProcessIdleCoinPurchase(player, receiptInfo.ProductId, IDLE_COIN_MULTIPLIER)
			if awarded then
				grantSuccess, grantMessage = true, "购买成功"
				if DEBUG_MODE then
					print(string.format(
						"%s [MarketplaceHandler] 挂机金币购买成功 - 玩家:%s 发放:%d",
						GameConfig.LOG_PREFIX,
						player.Name,
						awardCoins
					))
				end
			elseif awardCoins <= 0 then
				-- 待领取金币为0时也视为已处理，避免重复扣款重试
				grantSuccess, grantMessage = true, "购买成功"
				warn(string.format(
					"[MarketplaceHandler] 挂机金币购买未产生奖励 - 玩家:%s 待领取金币不足",
					player.Name
				))
			else
				-- 发放失败，稍后重试
				warn(string.format(
					"[MarketplaceHandler] 挂机金币购买发放失败 - 玩家:%s",
					player.Name
				))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		elseif receiptInfo.ProductId == SEVEN_DAYS_UNLOCK_PRODUCT_ID then
			-- 七日登录奖励一键解锁
			local sevenDaysSystem = GetSevenDaysSystem()
			if not sevenDaysSystem then
				warn("[MarketplaceHandler] SevenDaysSystem不可用，稍后重试")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			local ok, unlockSuccess, unlockMessage = pcall(function()
				return sevenDaysSystem.UnlockAll(player)
			end)

			if ok and unlockSuccess then
				grantSuccess, grantMessage = true, "购买成功"
			else
				warn(string.format(
					"[MarketplaceHandler] 七日奖励解锁失败 - 玩家:%s 原因:%s",
					player.Name,
					ok and tostring(unlockMessage) or "异常"
				))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		else
			-- 未找到对应商品
			warn(string.format(
				"[MarketplaceHandler] 未找到对应商品 - ProductId:%s",
				productIdStr
			))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 6. 处理发放结果
		if grantSuccess then
			-- 标记收据为已处理
			MarkReceiptProcessed(receiptInfo.PurchaseId)

			-- 记录购买历史
			RecordPurchaseHistory(player, receiptInfo.PurchaseId, receiptInfo.ProductId)

			-- 保存玩家数据
			if DataManager then
				DataManager.SavePlayerDataThrottled(player)
			end

			if DEBUG_MODE then
				print(string.format(
					"%s [MarketplaceHandler] 购买成功 - 玩家:%s 商品:%s",
					GameConfig.LOG_PREFIX,
					player.Name,
					unitId or skillId
				))
			end

			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			-- 发放失败，稍后重试
			warn(string.format(
				"[MarketplaceHandler] 商品发放失败 - 玩家:%s 原因:%s",
				player.Name,
				grantMessage
			))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end)

	if not success then
		warn("[MarketplaceHandler] ProcessReceipt 严重错误: " .. tostring(result))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return result
end

--[[
提示玩家购买商品（兵种）
@param player Player - 玩家
@param unitId string - 兵种ID
@param shopId string - 商店ID
@return boolean - 是否成功提示
]]
function MarketplaceHandler.PromptUnitPurchase(player, unitId, shopId)
	local success, result = pcall(function()
		-- 获取DevProductId
		local devProductId = ShopConfig.GetDevProductId(shopId, unitId)
		if not devProductId or devProductId == "" or devProductId == "0" then
			warn(string.format(
				"[MarketplaceHandler] 兵种[%s]未配置DevProductId",
				unitId
			))
			return false
		end

		-- 转换为数字
		local productId = tonumber(devProductId)
		if not productId then
			warn(string.format(
				"[MarketplaceHandler] DevProductId格式错误: %s",
				devProductId
			))
			return false
		end

		-- 提示购买
		MarketplaceService:PromptProductPurchase(player, productId)

		if DEBUG_MODE then
			print(string.format(
				"%s [MarketplaceHandler] 提示购买兵种 - 玩家:%s UnitId:%s ProductId:%d",
				GameConfig.LOG_PREFIX,
				player.Name,
				unitId,
				productId
			))
		end

		return true
	end)

	if not success then
		warn("[MarketplaceHandler] PromptUnitPurchase 错误: " .. tostring(result))
		return false
	end

	return result
end

--[[
提示玩家购买商品（技能）
@param player Player - 玩家
@param skillId number - 技能ID
@param shopId string - 商店ID
@return boolean - 是否成功提示
]]
function MarketplaceHandler.PromptSkillPurchase(player, skillId, shopId)
	local success, result = pcall(function()
		-- 从SkillShopConfig获取DevProductId
		local devProductId = SkillShopConfig.GetDevProductId(shopId, skillId)
		if not devProductId or devProductId == "" or devProductId == "0" then
			warn(string.format(
				"[MarketplaceHandler] 技能[%d]在商店[%s]未配置DevProductId",
				skillId,
				shopId
			))
			return false
		end

		-- 转换为数字
		local productId = tonumber(devProductId)
		if not productId then
			warn(string.format(
				"[MarketplaceHandler] DevProductId格式错误: %s",
				devProductId
			))
			return false
		end

		-- 提示购买
		MarketplaceService:PromptProductPurchase(player, productId)

		if DEBUG_MODE then
			print(string.format(
				"%s [MarketplaceHandler] 提示购买技能 - 玩家:%s SkillId:%d ProductId:%d",
				GameConfig.LOG_PREFIX,
				player.Name,
				skillId,
				productId
			))
		end

		return true
	end)

	if not success then
		warn("[MarketplaceHandler] PromptSkillPurchase 错误: " .. tostring(result))
		return false
	end

	return result
end

--[[
初始化MarketplaceHandler
@return boolean - 是否成功
]]
function MarketplaceHandler.Initialize()
	-- 1. 初始化依赖模块
	if not InitializeDependencies() then
		warn("[MarketplaceHandler] 依赖模块初始化失败")
		return false
	end

	-- 2. 设置ProcessReceipt回调
	MarketplaceService.ProcessReceipt = MarketplaceHandler.ProcessReceipt

	EnsureArmyPackEvents()

	-- 3. 绑定玩家离开事件（清理购买历史）
	Players.PlayerRemoving:Connect(function(player)
		PurchaseHistory[player] = nil
	end)

	if DEBUG_MODE then
		print(string.format(
			"%s [MarketplaceHandler] MarketplaceHandler已就绪",
			GameConfig.LOG_PREFIX
		))
	end

	return true
end

--[[
获取玩家购买历史（调试用）
@param player Player - 玩家
@return table - 购买历史
]]
function MarketplaceHandler.GetPurchaseHistory(player)
	return PurchaseHistory[player] or {}
end

return MarketplaceHandler
