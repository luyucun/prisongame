--[[
脚本名称: MainServer
脚本类型: Script (服务端主脚本)
脚本位置: ServerScriptService/MainServer
]]

--[[
服务端主启动脚本
职责:
1. 初始化所有服务端系统
2. 按正确的顺序加载各个模块
3. 处理系统启动错误
]]

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 引用核心模块
local DataManager = require(ServerScriptService.Core.DataManager)
local PlayerManager = require(ServerScriptService.Core.PlayerManager)

-- 引用系统模块
local CurrencySystem = require(ServerScriptService.Systems.CurrencySystem)
local HomeSystem = require(ServerScriptService.Systems.HomeSystem)
local InventorySystem = require(ServerScriptService.Systems.InventorySystem)
local PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)
local MergeSystem = require(ServerScriptService.Systems.MergeSystem)  -- V1.4新增
local PhysicsManager = require(ServerScriptService.Systems.PhysicsManager)
local GMCommandSystem = require(ServerScriptService.Systems.GMCommandSystem)
-- V1.5新增 - 战斗系统
local CombatSystem = require(ServerScriptService.Systems.CombatSystem)
local ProjectileSystem = require(ServerScriptService.Systems.ProjectileSystem)
local UnitAI = require(ServerScriptService.Systems.UnitAI)
local BattleManager = require(ServerScriptService.Systems.BattleManager)
local BattleTestSystem = require(ServerScriptService.Systems.BattleTestSystem)
-- V1.5.1新增 - 战斗基础服务
local HitboxService = require(ServerScriptService.Systems.HitboxService)
local UnitManager = require(ServerScriptService.Systems.UnitManager)
-- V1.5.4新增 - 武器特效系统
local WeaponEffectSystem = require(ServerScriptService.Systems.WeaponEffectSystem)
-- V2.0新增 - 战役系统
local CampaignManager = require(ServerScriptService.Systems.CampaignManager)
-- V2.0.1新增 - 门控系统
local DoorControlService = require(ServerScriptService.Systems.DoorControlService)
-- V2.1新增 - 商店系统
local ShopSystem = require(ServerScriptService.Systems.ShopSystem)

-- ==================== 系统初始化顺序 ====================

local function InitializeServer()
    local initializationFailed = false

    -- 0. 初始化物理管理系统(必须首先初始化)
    local success, result = pcall(function()
        return PhysicsManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "物理管理系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "物理管理系统初始化失败(返回false)")
        initializationFailed = true
    end

    -- 1. 初始化基地系统(验证地图结构)
    success, result = pcall(function()
        return HomeSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "基地系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "基地系统初始化失败(返回false)")
        initializationFailed = true
    end

    -- 1.1 初始化门控系统 (V2.0.1新增)
    success, result = pcall(function()
        return DoorControlService.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "门控系统初始化失败(异常):", result)
        -- 门控不是关键系统，失败不阻止游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "门控系统初始化失败(返回false)")
    end

    -- 2. 初始化货币系统(连接远程事件)
    success, result = pcall(function()
        return CurrencySystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "货币系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "货币系统初始化失败(返回false),无法处理货币操作!")
        warn(GameConfig.LOG_PREFIX, "请检查ReplicatedStorage/Events/CurrencyEvents是否存在")
        initializationFailed = true
    end

    -- 3. 初始化玩家管理器(连接玩家事件)
    success, result = pcall(function()
        return PlayerManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "玩家管理器初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "玩家管理器初始化失败(返回false)")
        initializationFailed = true
    end

    -- 4. 初始化背包系统(连接背包事件)
    success, result = pcall(function()
        InventorySystem.Initialize()
        return true
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "背包系统初始化失败(异常):", result)
        -- 背包系统不是关键系统,失败不影响游戏运行
    end

    -- 5. 初始化放置系统(连接放置事件) V1.2新增
    success, result = pcall(function()
        return PlacementSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "放置系统初始化失败(异常):", result)
        -- 放置系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "放置系统初始化失败(返回false),放置功能将不可用")
    end

    -- 5.5. 初始化合成系统(连接合成事件) V1.4新增
    success, result = pcall(function()
        return MergeSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "合成系统初始化失败(异常):", result)
        -- 合成系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "合成系统初始化失败(返回false),合成功能将不可用")
    end

    -- 5.6. 初始化商店系统(V2.1新增 - 数据驱动版)
    success, result = pcall(function()
        return ShopSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "⚠️ 商店系统初始化失败(异常):", result)
        warn(GameConfig.LOG_PREFIX, "请检查：")
        warn("  1. ReplicatedStorage/Events/ShopEvents 是否已创建")
        warn("  2. ShopEvents 下是否有 RequestShopList、ShopList、PurchaseUnit、PurchaseResult")
        warn("  3. ReplicatedStorage/Config/ShopConfig 是否已创建")
        warn("  4. ShopConfig 是否正确配置")
        -- 商店系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "商店系统初始化失败(返回false),购买功能将不可用")
    end

    -- 6. 初始化GM命令系统(连接聊天事件)
    success, result = pcall(function()
        GMCommandSystem.Initialize()
        return true
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "GM命令系统初始化失败(异常):", result)
        -- GM系统不是关键系统,失败不影响游戏运行
    end

    -- 7. 初始化战斗系统(V1.5新增, V1.5.1优化)

    -- 7.0 初始化HitboxService (V1.5.1新增 - 碰撞判定服务)
    success, result = pcall(function()
        return HitboxService.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "碰撞判定服务初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "碰撞判定服务初始化失败(返回false)")
    end

    -- 7.0b 初始化UnitManager (V1.5.1新增 - 单位索引管理)
    success, result = pcall(function()
        return UnitManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "单位索引管理初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "单位索引管理初始化失败(返回false)")
    end

    -- 7.1 初始化CombatSystem
    success, result = pcall(function()
        return CombatSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗系统初始化失败(返回false)")
    end

    -- 7.2 初始化ProjectileSystem
    success, result = pcall(function()
        return ProjectileSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "弹道系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "弹道系统初始化失败(返回false)")
    end

    -- 7.2.5 初始化WeaponEffectSystem (V1.5.4新增)
    success, result = pcall(function()
        return WeaponEffectSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "武器特效系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "武器特效系统初始化失败(返回false)")
    end

    -- 7.3 初始化UnitAI
    success, result = pcall(function()
        return UnitAI.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "兵种AI系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "兵种AI系统初始化失败(返回false)")
    end

    -- 7.4 初始化BattleManager
    success, result = pcall(function()
        return BattleManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗管理器初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗管理器初始化失败(返回false)")
    end

    -- 7.5 初始化BattleTestSystem
    success, result = pcall(function()
        return BattleTestSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗测试系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗测试系统初始化失败(返回false)")
    end

    -- 8. 初始化战役系统 (V2.0新增)
    success, result = pcall(function()
        return CampaignManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战役系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战役系统初始化失败(返回false)")
    end

    -- 检查是否有关键系统初始化失败
    if initializationFailed then
        warn("==========================================")
        warn(GameConfig.LOG_PREFIX, "警告: 一个或多个系统初始化失败!")
        warn(GameConfig.LOG_PREFIX, "服务端可能无法正常工作,请检查上述错误信息")
        warn("==========================================")
        return false
    end

    return true
end

-- ==================== 启动服务端 ====================

-- 使用pcall包裹初始化过程,防止崩溃
local success, result = pcall(InitializeServer)

if not success then
    warn("==========================================")
    warn(GameConfig.LOG_PREFIX, "严重错误: 服务端初始化过程崩溃!")
    warn(GameConfig.LOG_PREFIX, "错误信息:", result)
    warn("==========================================")
elseif result == false then
    warn("==========================================")
    warn(GameConfig.LOG_PREFIX, "服务端初始化未完全成功,某些功能可能不可用")
    warn("==========================================")
end

-- ==================== 调试命令(仅调试模式) ====================

if GameConfig.DEBUG_MODE then
    -- 提供一些调试函数
    _G.DebugAddCoins = function(playerName, amount)
        local Players = game:GetService("Players")
        local player = Players:FindFirstChild(playerName)
        if player then
            CurrencySystem.AddCoins(player, amount, "调试添加")
        else
            warn(GameConfig.LOG_PREFIX, "找不到玩家:", playerName)
        end
    end

    _G.DebugGetPlayerData = function(playerName)
        local Players = game:GetService("Players")
        local player = Players:FindFirstChild(playerName)
        if player then
            local data = DataManager.GetPlayerData(player)
            if not data then
                warn(GameConfig.LOG_PREFIX, "玩家数据不存在:", playerName)
            end
        else
            warn(GameConfig.LOG_PREFIX, "找不到玩家:", playerName)
        end
    end

    _G.DebugGetHomeOccupancy = function()
        local occupancy = PlayerManager.GetHomeOccupancy()
        for slot = 1, GameConfig.HOME_COUNT do
            local player = occupancy[slot]
        end
    end
end

-- ==================== 玩家事件处理 (V2.0.1新增) ====================

local Players = game:GetService("Players")

-- 玩家加入时初始化基地
Players.PlayerAdded:Connect(function(player)
	-- 等待PlayerManager分配基地
	task.wait(1)

	-- 获取玩家基地ID
	local homeId = PlayerManager.GetPlayerHomeId(player)
	if homeId and homeId > 0 then
		-- 初始化玩家基地（确保门关闭）
		pcall(function()
			HomeSystem.InitializePlayerHome(homeId, player)
		end)
	end
end)

-- 玩家离开时清理
Players.PlayerRemoving:Connect(function(player)
	local playerId = player.UserId
	local homeId = PlayerManager.GetPlayerHomeId(player)

	-- 1. 如果玩家在战役中，强制结束战役并关门
	local campaignData = CampaignManager.ActiveCampaigns[playerId]
	if campaignData then
		pcall(function()
			CampaignManager.OnCampaignEnd(campaignData, false)
		end)
	end

	-- 2. 清理基地（关闭门）
	if homeId then
		pcall(function()
			HomeSystem.CleanupPlayerHome(homeId, player)
		end)
	end
end)

