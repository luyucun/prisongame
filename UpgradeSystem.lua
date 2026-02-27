--[[
脚本名称: UpgradeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UpgradeSystem
版本: V6.7
职责: 养成系统服务端逻辑（数据同步、金币升级、Robux升级）
]]

local UpgradeSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UpgradeConfig"))

local DataManager = nil
local CurrencySystem = nil
local PowerSystem = nil

local upgradeEvents = nil
local requestUpgradeDataEvent = nil
local upgradeDataEvent = nil
local purchaseUpgradeByCoinEvent = nil
local purchaseUpgradeByRobuxEvent = nil
local upgradePurchaseResultEvent = nil

local purchaseLocks = {}

local function InitializeModules()
    if not DataManager then
        local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
        if not dataModule then
            warn("[UpgradeSystem] DataManager模块未找到")
            return false
        end
        DataManager = require(dataModule)
    end

    if not CurrencySystem then
        local currencyModule = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
        if not currencyModule then
            warn("[UpgradeSystem] CurrencySystem模块未找到")
            return false
        end
        CurrencySystem = require(currencyModule)
    end

    return true
end

local function GetPowerSystem()
    if PowerSystem then
        return PowerSystem
    end

    local powerModule = ServerScriptService.Systems:FindFirstChild("PowerSystem")
    if not powerModule then
        return nil
    end

    local success, result = pcall(require, powerModule)
    if success and result then
        PowerSystem = result
        return PowerSystem
    end

    warn("[UpgradeSystem] PowerSystem加载失败:", result)
    return nil
end

local function InitializeEvents()
    if upgradeEvents then
        return true
    end

    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if not eventsFolder then
        eventsFolder = Instance.new("Folder")
        eventsFolder.Name = "Events"
        eventsFolder.Parent = ReplicatedStorage
    end

    upgradeEvents = eventsFolder:FindFirstChild("UpgradeEvents")
    if not upgradeEvents then
        upgradeEvents = Instance.new("Folder")
        upgradeEvents.Name = "UpgradeEvents"
        upgradeEvents.Parent = eventsFolder
    end

    local function GetOrCreateEvent(name)
        local event = upgradeEvents:FindFirstChild(name)
        if not event then
            event = Instance.new("RemoteEvent")
            event.Name = name
            event.Parent = upgradeEvents
        end
        return event
    end

    requestUpgradeDataEvent = GetOrCreateEvent("RequestUpgradeData")
    upgradeDataEvent = GetOrCreateEvent("UpgradeData")
    purchaseUpgradeByCoinEvent = GetOrCreateEvent("PurchaseUpgradeByCoin")
    purchaseUpgradeByRobuxEvent = GetOrCreateEvent("PurchaseUpgradeByRobux")
    upgradePurchaseResultEvent = GetOrCreateEvent("UpgradePurchaseResult")

    return true
end

local function BuildDefaultMultipliers()
    return {
        MoveSpeedMultiplier = 1,
        AttackSpeedMultiplier = 1,
        AttackMultiplier = 1,
        HealthMultiplier = 1,
        Levels = {},
        Ratios = {},
    }
end

local function GetSafeLevel(upgradeData, typeId)
    local initialLevel = UpgradeConfig.GetInitialLevel(typeId)
    local maxLevel = UpgradeConfig.GetMaxLevel(typeId)

    local rawLevel = nil
    if type(upgradeData) == "table" then
        rawLevel = tonumber(upgradeData[typeId]) or tonumber(upgradeData[tostring(typeId)])
    end

    local level = math.floor(rawLevel or initialLevel)
    if level < initialLevel then
        level = initialLevel
    end
    if maxLevel > 0 and level > maxLevel then
        level = maxLevel
    end

    return level
end

local function GetLevelBonusRatio(typeId, level)
    local cfg = UpgradeConfig.GetLevelConfig(typeId, level)
    if not cfg then
        return 0
    end
    return math.max(0, tonumber(cfg.BonusRatio) or 0)
end

local function BuildPlayerMultipliers(player)
    if not InitializeModules() then
        return BuildDefaultMultipliers()
    end

    local playerData = DataManager.GetUpgradeData(player)
    if type(playerData) ~= "table" then
        return BuildDefaultMultipliers()
    end

    local result = BuildDefaultMultipliers()

	for _, typeId in ipairs(UpgradeConfig.GetTypeIds()) do
		local level = GetSafeLevel(playerData, typeId)
		local ratio = GetLevelBonusRatio(typeId, level)
		result.Levels[typeId] = level
		result.Ratios[typeId] = ratio
	end

	local rebirthAttackBonusRate = 0
	if DataManager and DataManager.GetRebirthAttackBonusRate then
		rebirthAttackBonusRate = math.max(0, tonumber(DataManager.GetRebirthAttackBonusRate(player)) or 0)
	end

	result.MoveSpeedMultiplier = 1 + (result.Ratios[UpgradeConfig.TYPE.MOVE_SPEED] or 0)
	result.AttackSpeedMultiplier = 1 + (result.Ratios[UpgradeConfig.TYPE.ATTACK_SPEED] or 0)
	result.AttackMultiplier = 1 + (result.Ratios[UpgradeConfig.TYPE.ATTACK] or 0) + rebirthAttackBonusRate
	result.HealthMultiplier = 1 + (result.Ratios[UpgradeConfig.TYPE.HEALTH] or 0)
	result.RebirthAttackBonusRate = rebirthAttackBonusRate

	return result
end

local function RoundUpIfDecimal(value)
	local numeric = tonumber(value) or 0
	if numeric <= 0 then
		return 0
	end
	return math.ceil(numeric - 1e-6)
end

local function BuildTypePayload(upgradeData, typeId)
    local currentLevel = GetSafeLevel(upgradeData, typeId)
    local maxLevel = UpgradeConfig.GetMaxLevel(typeId)
    local isMax = maxLevel > 0 and currentLevel >= maxLevel

    local currentCfg = UpgradeConfig.GetLevelConfig(typeId, currentLevel)
    local currentBonusRatio = tonumber(currentCfg and currentCfg.BonusRatio) or 0

    local nextLevel = nil
    local nextPrice = nil
    if not isMax then
        nextLevel = currentLevel + 1
        local nextCfg = UpgradeConfig.GetLevelConfig(typeId, nextLevel)
        if nextCfg then
            nextPrice = tonumber(nextCfg.Price) or 0
        end
    end

    return {
        TypeId = typeId,
        TypeName = UpgradeConfig.GetTypeName(typeId),
        CurrentLevel = currentLevel,
        CurrentBonusRatio = currentBonusRatio,
        CurrentBonusText = UpgradeConfig.FormatBonusPercent(currentBonusRatio),
        MaxLevel = maxLevel,
        IsMax = isMax,
        NextLevel = nextLevel,
        NextPrice = nextPrice,
        DevProductId = UpgradeConfig.GetDevProductId(typeId),
    }
end

local function BuildPlayerUpgradePayload(player)
    local payload = {
        Entries = {},
        Levels = {},
        ServerTime = os.time(),
    }

    local upgradeData = nil
    if InitializeModules() then
        upgradeData = DataManager.GetUpgradeData(player)
    end

    for _, typeId in ipairs(UpgradeConfig.GetTypeIds()) do
        local entry = BuildTypePayload(upgradeData, typeId)
        payload.Levels[typeId] = entry.CurrentLevel
        table.insert(payload.Entries, entry)
    end

    return payload
end

local function SendPurchaseResult(player, success, message, typeId, purchaseType, extra)
    if not upgradePurchaseResultEvent then
        return
    end

    local payload = {
        Success = success == true,
        Message = message or "",
        TypeId = tonumber(typeId),
        PurchaseType = purchaseType,
        Data = extra,
    }

    upgradePurchaseResultEvent:FireClient(player, payload)
end

local function TryRecalculatePower(player)
    local power = GetPowerSystem()
    if power and power.RecalculatePlayerPower then
        task.spawn(function()
            local ok, err = pcall(function()
                power.RecalculatePlayerPower(player)
            end)
            if not ok then
                warn("[UpgradeSystem] 战斗力重算失败:", err)
            end
        end)
    end
end

local function CommitLevelUp(player, typeId, source, extra)
    local success, newLevel = DataManager.IncreaseUpgradeLevel(player, typeId, 1)
    if not success then
        return false, "Upgrade failed.", nil
    end

    DataManager.SavePlayerDataThrottled(player)
    UpgradeSystem.SyncPlayer(player)
    TryRecalculatePower(player)

    local responseData = {
        NewLevel = newLevel,
        Source = source,
        TypeId = typeId,
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            responseData[key] = value
        end
    end

    return true, "Upgrade Successful", responseData
end

local function HandleRequestUpgradeData(player)
    if not player or not player.Parent then
        return
    end

    UpgradeSystem.SyncPlayer(player)
end

local function HandlePurchaseUpgradeByCoin(player, rawTypeId)
    if not player or not player.Parent then
        return
    end

    if purchaseLocks[player] then
        SendPurchaseResult(player, false, "Purchase processing.", rawTypeId, "Coin")
        return
    end

    purchaseLocks[player] = true

    local typeId = tonumber(rawTypeId)
    if not typeId then
        SendPurchaseResult(player, false, "Invalid type.", rawTypeId, "Coin")
        purchaseLocks[player] = nil
        return
    end

    if not InitializeModules() then
        SendPurchaseResult(player, false, "System not ready.", typeId, "Coin")
        purchaseLocks[player] = nil
        return
    end

    local upgradeData = DataManager.GetUpgradeData(player)
    if not upgradeData then
        SendPurchaseResult(player, false, "Data not ready.", typeId, "Coin")
        purchaseLocks[player] = nil
        return
    end

    local currentLevel = GetSafeLevel(upgradeData, typeId)
    local maxLevel = UpgradeConfig.GetMaxLevel(typeId)
    if maxLevel <= 0 then
        SendPurchaseResult(player, false, "Config invalid.", typeId, "Coin")
        purchaseLocks[player] = nil
        return
    end

    if currentLevel >= maxLevel then
        SendPurchaseResult(player, false, "Max Level", typeId, "Coin")
        purchaseLocks[player] = nil
        return
    end

    local nextLevel = currentLevel + 1
    local nextCfg = UpgradeConfig.GetLevelConfig(typeId, nextLevel)
    local price = tonumber(nextCfg and nextCfg.Price) or 0
    if price < 0 then
        price = 0
    end

    if not CurrencySystem.HasEnoughCoins(player, price) then
        SendPurchaseResult(player, false, "Not Enough Coins", typeId, "Coin", { Price = price })
        purchaseLocks[player] = nil
        return
    end

    local removeSuccess, newCoins = CurrencySystem.RemoveCoins(player, price, "UpgradeCoin")
    if not removeSuccess then
        SendPurchaseResult(player, false, "Failed to deduct coins.", typeId, "Coin", { Price = price })
        purchaseLocks[player] = nil
        return
    end

    local commitSuccess, commitMessage, commitData = CommitLevelUp(player, typeId, "Coin", {
        Price = price,
        NewCoins = newCoins,
    })

    if not commitSuccess then
        CurrencySystem.AddCoins(player, price, "UpgradeCoinRefund", { ApplyVipBonus = false, ApplyFriendBonus = false, ApplyRebirthBonus = false })
        SendPurchaseResult(player, false, commitMessage, typeId, "Coin")
        purchaseLocks[player] = nil
        return
    end

    SendPurchaseResult(player, true, commitMessage, typeId, "Coin", commitData)
    purchaseLocks[player] = nil
end

local function HandlePurchaseUpgradeByRobux(player, rawTypeId)
    if not player or not player.Parent then
        return
    end

    local typeId = tonumber(rawTypeId)
    if not typeId then
        SendPurchaseResult(player, false, "Invalid type.", rawTypeId, "Robux")
        return
    end

    if not InitializeModules() then
        SendPurchaseResult(player, false, "System not ready.", typeId, "Robux")
        return
    end

    local upgradeData = DataManager.GetUpgradeData(player)
    local currentLevel = GetSafeLevel(upgradeData, typeId)
    local maxLevel = UpgradeConfig.GetMaxLevel(typeId)
    if maxLevel <= 0 then
        SendPurchaseResult(player, false, "Config invalid.", typeId, "Robux")
        return
    end

    if currentLevel >= maxLevel then
        SendPurchaseResult(player, false, "Max Level", typeId, "Robux")
        return
    end

    local productId = UpgradeConfig.GetDevProductId(typeId)
    if not productId then
        SendPurchaseResult(player, false, "Product config invalid.", typeId, "Robux")
        return
    end

    local promptSuccess, promptErr = pcall(function()
        MarketplaceService:PromptProductPurchase(player, productId)
    end)

    if not promptSuccess then
        warn("[UpgradeSystem] PromptProductPurchase失败:", promptErr)
        SendPurchaseResult(player, false, "Unable to open purchase prompt.", typeId, "Robux")
    end
end

function UpgradeSystem.Initialize()
    if not InitializeModules() then
        return false
    end

    if not InitializeEvents() then
        return false
    end

    requestUpgradeDataEvent.OnServerEvent:Connect(HandleRequestUpgradeData)
    purchaseUpgradeByCoinEvent.OnServerEvent:Connect(HandlePurchaseUpgradeByCoin)
    purchaseUpgradeByRobuxEvent.OnServerEvent:Connect(HandlePurchaseUpgradeByRobux)

    Players.PlayerRemoving:Connect(function(leavingPlayer)
        purchaseLocks[leavingPlayer] = nil
    end)

    return true
end

function UpgradeSystem.SyncPlayer(player)
    if not player or not player.Parent then
        return
    end

    if not upgradeDataEvent then
        if not InitializeEvents() then
            return
        end
    end

    local payload = BuildPlayerUpgradePayload(player)
    upgradeDataEvent:FireClient(player, payload)
end

function UpgradeSystem.GetPlayerMultipliers(player)
    if not player or not player.Parent then
        return BuildDefaultMultipliers()
    end
    return BuildPlayerMultipliers(player)
end

function UpgradeSystem.GetMultipliersByUserId(userId)
    local uid = tonumber(userId)
    if not uid then
        return BuildDefaultMultipliers()
    end

    local player = Players:GetPlayerByUserId(uid)
    if not player then
        return BuildDefaultMultipliers()
    end

    return BuildPlayerMultipliers(player)
end

function UpgradeSystem.ApplyMultipliersToStats(baseStats, multipliers)
    local source = type(baseStats) == "table" and baseStats or {}
    local m = type(multipliers) == "table" and multipliers or BuildDefaultMultipliers()

    local attack = tonumber(source.Attack) or 0
    local maxHealth = tonumber(source.MaxHealth) or 0
    local attackSpeed = tonumber(source.AttackSpeed) or 1
    local moveSpeed = tonumber(source.MoveSpeed) or 16

    local attackMultiplier = tonumber(m.AttackMultiplier) or 1
    local healthMultiplier = tonumber(m.HealthMultiplier) or 1
    local attackSpeedMultiplier = tonumber(m.AttackSpeedMultiplier) or 1
    local moveSpeedMultiplier = tonumber(m.MoveSpeedMultiplier) or 1

    if attackMultiplier <= 0 then attackMultiplier = 1 end
    if healthMultiplier <= 0 then healthMultiplier = 1 end
    if attackSpeedMultiplier <= 0 then attackSpeedMultiplier = 1 end
    if moveSpeedMultiplier <= 0 then moveSpeedMultiplier = 1 end

	local result = {
		Attack = math.max(1, RoundUpIfDecimal(attack * attackMultiplier)),
		MaxHealth = math.max(1, maxHealth * healthMultiplier),
		AttackSpeed = math.max(0.05, attackSpeed / attackSpeedMultiplier),
		MoveSpeed = math.max(1, moveSpeed * moveSpeedMultiplier),
	}

    return result
end

function UpgradeSystem.ProcessRobuxReceipt(player, productId)
    if not player or not player.Parent then
        return false, "Player unavailable"
    end

    if not InitializeModules() then
        return false, "System not ready"
    end

    local typeId = UpgradeConfig.GetTypeByDevProductId(productId)
    if not typeId then
        return false, "Unknown product"
    end

    local upgradeData = DataManager.GetUpgradeData(player)
    local currentLevel = GetSafeLevel(upgradeData, typeId)
    local maxLevel = UpgradeConfig.GetMaxLevel(typeId)

    if maxLevel > 0 and currentLevel >= maxLevel then
        SendPurchaseResult(player, false, "Max Level", typeId, "Robux")
        return true, "Already max level"
    end

    local commitSuccess, commitMessage, commitData = CommitLevelUp(player, typeId, "Robux")
    if not commitSuccess then
        return false, commitMessage
    end

    SendPurchaseResult(player, true, commitMessage, typeId, "Robux", commitData)
    return true, commitMessage
end

return UpgradeSystem
