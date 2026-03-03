--[[
脚本名称: RebirthSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/RebirthSystem
版本: V7.0
职责: 重生系统服务端流程（条件校验、重置、奖励、数据同步）
]]

local RebirthSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local RebirthConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("RebirthConfig"))
local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

local DataManager = nil
local CurrencySystem = nil
local InventorySystem = nil
local PlacementSystem = nil
local ShopSystem = nil
local HouseUpgradeSystem = nil

local RebirthEvents = nil
local RequestRebirthDataEvent = nil
local RebirthDataEvent = nil
local AttemptRebirthEvent = nil
local RebirthResultEvent = nil
local RebirthPanelClosedEvent = nil
local RebirthStateChangedEvent = nil

local rebirthLocks = {}
local pendingHouseUpgradeByUserId = {}

local COIN_ICON = "rbxassetid://92295649647469"
local ATTACK_BONUS_ICON = "rbxassetid://76416297088295"
local COIN_BONUS_ICON = "rbxassetid://93607334203626"

local function FormatNumberWithCommas(value)
	local amount = math.floor(tonumber(value) or 0)
	local sign = ""
	if amount < 0 then
		sign = "-"
		amount = math.abs(amount)
	end

	local text = tostring(amount)
	local formatted = text
	while true do
		local replaced, count = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end

	return sign .. formatted
end

local function FormatMultiplier(rate)
	local value = 1 + math.max(0, tonumber(rate) or 0)
	local text = string.format("%.2f", value)
	text = string.gsub(text, "%.?0+$", "")
	return "x" .. text
end

local function SafeRequireSystem(moduleName)
	local module = ServerScriptService.Systems:FindFirstChild(moduleName)
	if not module then
		return nil
	end

	local success, result = pcall(require, module)
	if not success then
		warn("[RebirthSystem] 加载模块失败:", moduleName, result)
		return nil
	end
	return result
end

local function InitializeDependencies()
	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if not dataModule then
			warn("[RebirthSystem] DataManager模块未找到")
			return false
		end
		DataManager = require(dataModule)
	end

	if not CurrencySystem then
		CurrencySystem = SafeRequireSystem("CurrencySystem")
	end
	if not InventorySystem then
		InventorySystem = SafeRequireSystem("InventorySystem")
	end
	if not PlacementSystem then
		PlacementSystem = SafeRequireSystem("PlacementSystem")
	end
	if not ShopSystem then
		ShopSystem = SafeRequireSystem("ShopSystem")
	end
	if not HouseUpgradeSystem then
		HouseUpgradeSystem = SafeRequireSystem("HouseUpgradeSystem")
	end

	if not (DataManager and CurrencySystem and InventorySystem and PlacementSystem) then
		warn("[RebirthSystem] 关键依赖缺失，初始化失败")
		return false
	end

	return true
end

local function InitializeEvents()
	if RebirthEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	RebirthEvents = eventsFolder:FindFirstChild("RebirthEvents")
	if not RebirthEvents then
		RebirthEvents = Instance.new("Folder")
		RebirthEvents.Name = "RebirthEvents"
		RebirthEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = RebirthEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = RebirthEvents
		end
		return event
	end

	RequestRebirthDataEvent = GetOrCreateEvent("RequestRebirthData")
	RebirthDataEvent = GetOrCreateEvent("RebirthData")
	AttemptRebirthEvent = GetOrCreateEvent("AttemptRebirth")
	RebirthResultEvent = GetOrCreateEvent("RebirthResult")
	RebirthPanelClosedEvent = GetOrCreateEvent("RebirthPanelClosed")
	RebirthStateChangedEvent = GetOrCreateEvent("RebirthStateChanged")

	return true
end

local function GetHouseRank(modelName)
	if HouseConfig.GetHouseRank then
		return HouseConfig.GetHouseRank(modelName)
	end
	return 0
end

local function GetCurrentOrPendingHouseModel(player)
	local currentModel = DataManager.GetCurrentHouseModel(player)
	local pending = pendingHouseUpgradeByUserId[player.UserId]
	if not pending or not pending.TargetModel then
		return currentModel
	end

	local currentRank = GetHouseRank(currentModel)
	local pendingRank = GetHouseRank(pending.TargetModel)
	if pendingRank > currentRank then
		return pending.TargetModel
	end
	return currentModel
end

local function ShouldShowHouseReward(player, unlockModel)
	if type(unlockModel) ~= "string" or unlockModel == "" then
		return false
	end

	local currentModel = GetCurrentOrPendingHouseModel(player)
	local currentRank = GetHouseRank(currentModel)
	local unlockRank = GetHouseRank(unlockModel)
	return unlockRank > currentRank
end

local function GetUnitIcon(unitId)
	local unitData = UnitConfig.GetUnitById(tostring(unitId or ""))
	if not unitData then
		return "rbxassetid://0"
	end
	return tostring(unitData.Icon or "rbxassetid://0")
end

local function GetUnitCountByUnitId(player, unitId)
	if not InventorySystem or not InventorySystem.GetUnitCountByUnitId then
		return 0
	end
	return tonumber(InventorySystem.GetUnitCountByUnitId(player, tostring(unitId or ""))) or 0
end

local function BuildRewardDisplayData(player, nextConfig)
	if not nextConfig then
		return {}
	end

	local rewards = {}

	local rewardCoins = tonumber(nextConfig.RewardCoins) or 0
	if rewardCoins > 0 then
		table.insert(rewards, {
			Type = "Coins",
			Icon = COIN_ICON,
			Num = FormatNumberWithCommas(rewardCoins),
			Name = "",
			ShowNum = true,
			ShowName = false,
		})
	end

	local rewardUnitId = tostring(nextConfig.RewardUnitId or "")
	local rewardUnitCount = tonumber(nextConfig.RewardUnitCount) or 0
	if rewardUnitId ~= "" and rewardUnitCount > 0 then
		table.insert(rewards, {
			Type = "Unit",
			UnitId = rewardUnitId,
			Icon = GetUnitIcon(rewardUnitId),
			Num = tostring(rewardUnitCount),
			Name = "",
			ShowNum = true,
			ShowName = false,
		})
	end

	local coinBonusRate = tonumber(nextConfig.CoinBonusRate) or 0
	table.insert(rewards, {
		Type = "CoinBonus",
		Icon = COIN_BONUS_ICON,
		Num = FormatMultiplier(coinBonusRate),
		Name = "",
		ShowNum = true,
		ShowName = false,
	})

	local attackBonusRate = tonumber(nextConfig.AttackBonusRate) or 0
	table.insert(rewards, {
		Type = "AttackBonus",
		Icon = ATTACK_BONUS_ICON,
		Num = FormatMultiplier(attackBonusRate),
		Name = "",
		ShowNum = true,
		ShowName = false,
	})

	local unlockHouseModel = tostring(nextConfig.UnlockHouseModel or "")
	if unlockHouseModel ~= "" and ShouldShowHouseReward(player, unlockHouseModel) then
		local houseData = HouseConfig.GetHouseByModel(unlockHouseModel)
		table.insert(rewards, {
			Type = "House",
			ModelName = unlockHouseModel,
			Icon = tostring(houseData and houseData.Icon or "rbxassetid://0"),
			Num = "",
			Name = "New!",
			ShowNum = false,
			ShowName = true,
		})
	end

	return rewards
end

local function BuildCostDisplayData(player, nextConfig, currentCoins)
	if not nextConfig then
		return {}
	end

	local costs = {}
	local requiredCoins = tonumber(nextConfig.RequiredCoins) or 0
	table.insert(costs, {
		Type = "Coins",
		Icon = COIN_ICON,
		Current = currentCoins,
		Required = requiredCoins,
		Text = string.format("$%s/$%s", FormatNumberWithCommas(currentCoins), FormatNumberWithCommas(requiredCoins)),
		IsEnough = currentCoins >= requiredCoins,
	})

	local requiredUnitId = tostring(nextConfig.RequiredUnitId or "")
	local requiredUnitCount = tonumber(nextConfig.RequiredUnitCount) or 0
	local ownedUnitCount = GetUnitCountByUnitId(player, requiredUnitId)
	table.insert(costs, {
		Type = "Unit",
		UnitId = requiredUnitId,
		Icon = GetUnitIcon(requiredUnitId),
		Current = ownedUnitCount,
		Required = requiredUnitCount,
		Text = string.format("%d/%d", ownedUnitCount, requiredUnitCount),
		IsEnough = ownedUnitCount >= requiredUnitCount,
	})

	return costs
end

local function BuildRebirthPayload(player)
	local rebirthData = DataManager.GetRebirthData(player)
	local currentCount = rebirthData and (tonumber(rebirthData.Count) or 0) or 0
	if currentCount < 0 then
		currentCount = 0
	end

	local maxCount = RebirthConfig.GetMaxRebirthCount()
	if currentCount > maxCount then
		currentCount = maxCount
	end

	local nextConfig = RebirthConfig.GetNextConfig(currentCount)
	local currentCoins = tonumber(CurrencySystem.GetCoins(player)) or 0
	if currentCoins < 0 then
		currentCoins = 0
	end

	local requiredCoins = nextConfig and (tonumber(nextConfig.RequiredCoins) or 0) or 0
	local requiredUnitId = nextConfig and tostring(nextConfig.RequiredUnitId or "") or ""
	local requiredUnitCount = nextConfig and (tonumber(nextConfig.RequiredUnitCount) or 0) or 0
	local ownedUnitCount = nextConfig and GetUnitCountByUnitId(player, requiredUnitId) or 0

	local canRebirth = false
	local failCode = "MAX_LEVEL"
	if nextConfig then
		local enoughCoins = currentCoins >= requiredCoins
		local enoughUnits = ownedUnitCount >= requiredUnitCount
		canRebirth = enoughCoins and enoughUnits
		if canRebirth then
			failCode = "OK"
		elseif not enoughCoins then
			failCode = "NOT_ENOUGH_COINS"
		else
			failCode = "NOT_ENOUGH_UNITS"
		end
	end

	local progressScale = 0
	if requiredCoins > 0 then
		local ratio = math.clamp(currentCoins / requiredCoins, 0, 1)
		progressScale = ratio * 0.998
	end

	return {
		CurrentCount = currentCount,
		MaxCount = maxCount,
		IsMaxLevel = (nextConfig == nil),
		CanRebirth = canRebirth,
		FailCode = failCode,
		CurrentCoins = currentCoins,
		RequiredCoins = requiredCoins,
		RequiredUnitId = requiredUnitId,
		RequiredUnitCount = requiredUnitCount,
		CurrentUnitCount = ownedUnitCount,
		ProgressScale = progressScale,
		ProgressText = string.format("$%s/$%s", FormatNumberWithCommas(currentCoins), FormatNumberWithCommas(requiredCoins)),
		Rewards = BuildRewardDisplayData(player, nextConfig),
		Costs = BuildCostDisplayData(player, nextConfig, currentCoins),
		NextConfig = nextConfig,
		PendingHouseUnlock = pendingHouseUpgradeByUserId[player.UserId] ~= nil,
		ServerTime = os.time(),
	}
end

local function SendRebirthData(player, useStateEvent)
	if not player or not player.Parent then
		return
	end
	if not (RebirthDataEvent and RebirthStateChangedEvent) then
		return
	end

	local payload = BuildRebirthPayload(player)
	if useStateEvent then
		RebirthStateChangedEvent:FireClient(player, payload)
	else
		RebirthDataEvent:FireClient(player, payload)
	end
end

local function QueuePendingHouseUpgrade(player, unlockHouseModel)
	if type(unlockHouseModel) ~= "string" or unlockHouseModel == "" then
		return false
	end

	if not ShouldShowHouseReward(player, unlockHouseModel) then
		return false
	end

	local userId = player.UserId
	local existing = pendingHouseUpgradeByUserId[userId]
	if existing and existing.TargetModel then
		if GetHouseRank(existing.TargetModel) >= GetHouseRank(unlockHouseModel) then
			return true
		end
	end

	pendingHouseUpgradeByUserId[userId] = {
		TargetModel = unlockHouseModel,
		CreatedAt = os.time(),
	}
	return true
end

local function TryPlayPendingHouseUpgrade(player)
	if not player or not player.Parent then
		return
	end
	if not HouseUpgradeSystem or not HouseUpgradeSystem.ReplaceHouseModelWithCinematic then
		return
	end

	local pending = pendingHouseUpgradeByUserId[player.UserId]
	if not pending or not pending.TargetModel then
		return
	end

	local currentModel = DataManager.GetCurrentHouseModel(player)
	if GetHouseRank(currentModel) >= GetHouseRank(pending.TargetModel) then
		pendingHouseUpgradeByUserId[player.UserId] = nil
		return
	end

	local targetModel = pending.TargetModel
	pendingHouseUpgradeByUserId[player.UserId] = nil
	task.spawn(function()
		if not player or not player.Parent then
			return
		end
		local success, err = pcall(function()
			HouseUpgradeSystem.ReplaceHouseModelWithCinematic(player, targetModel)
		end)
		if not success then
			warn("[RebirthSystem] 播放监狱升级表现失败:", err)
		end
		SendRebirthData(player, true)
	end)
end

local function ResetPlayerCoinsAndUnits(player)
	local currencyType = GameConfig.CurrencyType and GameConfig.CurrencyType.COINS or "Coins"
	local setSuccess = CurrencySystem.SetCurrency(player, currencyType, 0, "RebirthReset")
	if not setSuccess then
		return false, "RESET_COINS_FAILED"
	end

	local clearPlacedSuccess = true
	if PlacementSystem and PlacementSystem.ClearAllPlacedUnits then
		local ok, result = pcall(function()
			return PlacementSystem.ClearAllPlacedUnits(player)
		end)
		clearPlacedSuccess = ok and result ~= nil
	end

	local clearInventorySuccess = false
	if InventorySystem and InventorySystem.ClearInventory then
		local ok, result = pcall(function()
			return InventorySystem.ClearInventory(player)
		end)
		clearInventorySuccess = ok and result == true
	end

	if not clearPlacedSuccess or not clearInventorySuccess then
		return false, "RESET_UNITS_FAILED"
	end

	return true, "OK"
end

local function GrantRebirthRewards(player, nextConfig)
	local rewardCoins = tonumber(nextConfig.RewardCoins) or 0
	if rewardCoins > 0 then
		local success = CurrencySystem.AddCoins(player, rewardCoins, "RebirthReward", {
			ApplyVipBonus = false,
			ApplyFriendBonus = false,
			ApplyRebirthBonus = false,
		})
		if not success then
			return false, "GRANT_COINS_FAILED"
		end
	end

	local rewardUnitId = tostring(nextConfig.RewardUnitId or "")
	local rewardUnitCount = tonumber(nextConfig.RewardUnitCount) or 0
	if rewardUnitId ~= "" and rewardUnitCount > 0 then
		for _ = 1, rewardUnitCount do
			local success = InventorySystem.AddUnit(player, rewardUnitId, true)
			if not success then
				return false, "GRANT_UNITS_FAILED"
			end
		end
		InventorySystem.RefreshClientInventory(player)
	end

	if DataManager.SetRebirthData then
		DataManager.SetRebirthData(
			player,
			nextConfig.RebirthCount,
			nextConfig.CoinBonusRate,
			nextConfig.AttackBonusRate
		)
	end

	-- 七日登录奖励：首次重生后解锁
	if tonumber(nextConfig.RebirthCount) and tonumber(nextConfig.RebirthCount) >= 1 then
		player:SetAttribute("SevenDaysUnlocked", true)
	end

	local unlockHouseModel = tostring(nextConfig.UnlockHouseModel or "")
	local queuedHouse = QueuePendingHouseUpgrade(player, unlockHouseModel)

	if ShopSystem and ShopSystem.TryRefreshSingleUnitStock then
		local unlockUnitId = tostring(nextConfig.UnlockUnitId or "")
		if unlockUnitId ~= "" then
			pcall(function()
				ShopSystem.TryRefreshSingleUnitStock(player, "UnitShop", unlockUnitId)
			end)
		end
	end

	DataManager.SavePlayerDataThrottled(player, true)
	return true, "OK", queuedHouse
end

local function HandleAttemptRebirth(player)
	if not player or not player.Parent then
		return
	end
	if rebirthLocks[player] then
		return
	end

	rebirthLocks[player] = true

	local payload = BuildRebirthPayload(player)
	if payload.IsMaxLevel then
		rebirthLocks[player] = nil
		return
	end

	if not payload.CanRebirth then
		if RebirthResultEvent then
			RebirthResultEvent:FireClient(player, false, payload.FailCode or "CAN_NOT_REBIRTH", payload)
		end
		rebirthLocks[player] = nil
		return
	end

	local nextConfig = payload.NextConfig
	if type(nextConfig) ~= "table" then
		rebirthLocks[player] = nil
		return
	end

	local resetSuccess, resetCode = ResetPlayerCoinsAndUnits(player)
	if not resetSuccess then
		if RebirthResultEvent then
			RebirthResultEvent:FireClient(player, false, resetCode, payload)
		end
		rebirthLocks[player] = nil
		return
	end

	local rewardSuccess, rewardCode, queuedHouse = GrantRebirthRewards(player, nextConfig)
	if not rewardSuccess then
		if RebirthResultEvent then
			RebirthResultEvent:FireClient(player, false, rewardCode, payload)
		end
		rebirthLocks[player] = nil
		return
	end

	local latestPayload = BuildRebirthPayload(player)
	if RebirthResultEvent then
		RebirthResultEvent:FireClient(player, true, "SUCCESS", {
			NewCount = latestPayload.CurrentCount,
			IsMaxLevelAfter = latestPayload.IsMaxLevel,
			QueuedHouseUpgrade = queuedHouse == true,
			FailCode = "OK",
		})
	end

	SendRebirthData(player, true)
	rebirthLocks[player] = nil
end

local function HandleRequestRebirthData(player)
	if not player or not player.Parent then
		return
	end
	SendRebirthData(player, false)
end

local function HandleRebirthPanelClosed(player)
	if not player or not player.Parent then
		return
	end
	TryPlayPendingHouseUpgrade(player)
end

local function HandlePlayerRemoving(player)
	rebirthLocks[player] = nil
	pendingHouseUpgradeByUserId[player.UserId] = nil
end

function RebirthSystem.SyncPlayer(player)
	if not player or not player.Parent then
		return
	end
	SendRebirthData(player, true)
end

function RebirthSystem.Initialize()
	if not InitializeDependencies() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	RequestRebirthDataEvent.OnServerEvent:Connect(HandleRequestRebirthData)
	AttemptRebirthEvent.OnServerEvent:Connect(HandleAttemptRebirth)
	RebirthPanelClosedEvent.OnServerEvent:Connect(HandleRebirthPanelClosed)
	Players.PlayerRemoving:Connect(HandlePlayerRemoving)

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			if player and player.Parent then
				SendRebirthData(player, true)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			if player and player.Parent then
				SendRebirthData(player, true)
			end
		end)
	end

	return true
end

return RebirthSystem
