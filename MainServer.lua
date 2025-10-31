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

print("==========================================")
print("游戏服务端启动中...")
print("==========================================")

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")

-- 引用配置
local GameConfig = require(ServerScriptService.Config.GameConfig)

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

-- ==================== 系统初始化顺序 ====================

local function InitializeServer()
    print(GameConfig.LOG_PREFIX, "开始初始化服务端系统...")
    print(GameConfig.LOG_PREFIX, "调试模式:", GameConfig.DEBUG_MODE and "开启" or "关闭")

    local initializationFailed = false

    -- 0. 初始化物理管理系统(必须首先初始化)
    print(GameConfig.LOG_PREFIX, "步骤0: 初始化物理管理系统...")
    local success, result = pcall(function()
        return PhysicsManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "物理管理系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "物理管理系统初始化失败(返回false)")
        initializationFailed = true
    else
        print(GameConfig.LOG_PREFIX, "物理管理系统初始化成功")
    end

    -- 1. 初始化基地系统(验证地图结构)
    print(GameConfig.LOG_PREFIX, "步骤1: 初始化基地系统...")
    local success, result = pcall(function()
        return HomeSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "基地系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "基地系统初始化失败(返回false)")
        initializationFailed = true
    else
        print(GameConfig.LOG_PREFIX, "基地系统初始化成功")
    end

    -- 2. 初始化货币系统(连接远程事件)
    print(GameConfig.LOG_PREFIX, "步骤2: 初始化货币系统...")
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
    else
        print(GameConfig.LOG_PREFIX, "货币系统初始化成功")
    end

    -- 3. 初始化玩家管理器(连接玩家事件)
    print(GameConfig.LOG_PREFIX, "步骤3: 初始化玩家管理器...")
    success, result = pcall(function()
        return PlayerManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "玩家管理器初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "玩家管理器初始化失败(返回false)")
        initializationFailed = true
    else
        print(GameConfig.LOG_PREFIX, "玩家管理器初始化成功")
    end

    -- 4. 初始化背包系统(连接背包事件)
    print(GameConfig.LOG_PREFIX, "步骤4: 初始化背包系统...")
    success, result = pcall(function()
        InventorySystem.Initialize()
        return true
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "背包系统初始化失败(异常):", result)
        -- 背包系统不是关键系统,失败不影响游戏运行
    else
        print(GameConfig.LOG_PREFIX, "背包系统初始化成功")
    end

    -- 5. 初始化放置系统(连接放置事件) V1.2新增
    print(GameConfig.LOG_PREFIX, "步骤5: 初始化放置系统...")
    success, result = pcall(function()
        return PlacementSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "放置系统初始化失败(异常):", result)
        -- 放置系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "放置系统初始化失败(返回false),放置功能将不可用")
    else
        print(GameConfig.LOG_PREFIX, "放置系统初始化成功")
    end

    -- 5.5. 初始化合成系统(连接合成事件) V1.4新增
    print(GameConfig.LOG_PREFIX, "步骤5.5: 初始化合成系统...")
    success, result = pcall(function()
        return MergeSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "合成系统初始化失败(异常):", result)
        -- 合成系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "合成系统初始化失败(返回false),合成功能将不可用")
    else
        print(GameConfig.LOG_PREFIX, "合成系统初始化成功")
    end

    -- 6. 初始化GM命令系统(连接聊天事件)
    print(GameConfig.LOG_PREFIX, "步骤6: 初始化GM命令系统...")
    success, result = pcall(function()
        GMCommandSystem.Initialize()
        return true
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "GM命令系统初始化失败(异常):", result)
        -- GM系统不是关键系统,失败不影响游戏运行
    else
        print(GameConfig.LOG_PREFIX, "GM命令系统初始化成功")
    end

    -- 7. 初始化战斗系统(V1.5新增, V1.5.1优化)
    print(GameConfig.LOG_PREFIX, "步骤7: 初始化战斗系统...")

    -- 7.0 初始化HitboxService (V1.5.1新增 - 碰撞判定服务)
    print(GameConfig.LOG_PREFIX, "步骤7.0a: 初始化碰撞判定服务...")
    success, result = pcall(function()
        return HitboxService.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "碰撞判定服务初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "碰撞判定服务初始化失败(返回false)")
    else
        print(GameConfig.LOG_PREFIX, "碰撞判定服务初始化成功")
    end

    -- 7.0b 初始化UnitManager (V1.5.1新增 - 单位索引管理)
    print(GameConfig.LOG_PREFIX, "步骤7.0b: 初始化单位索引管理...")
    success, result = pcall(function()
        return UnitManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "单位索引管理初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "单位索引管理初始化失败(返回false)")
    else
        print(GameConfig.LOG_PREFIX, "单位索引管理初始化成功")
    end

    -- 7.1 初始化CombatSystem
    print(GameConfig.LOG_PREFIX, "步骤7.1: 初始化战斗系统...")
    success, result = pcall(function()
        return CombatSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗系统初始化失败(返回false)")
    else
        print(GameConfig.LOG_PREFIX, "战斗系统初始化成功")
    end

    -- 7.2 初始化ProjectileSystem
    print(GameConfig.LOG_PREFIX, "步骤7.2: 初始化弹道系统...")
    success, result = pcall(function()
        return ProjectileSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "弹道系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "弹道系统初始化失败(返回false)")
    else
        print(GameConfig.LOG_PREFIX, "弹道系统初始化成功")
    end

    -- 7.3 初始化UnitAI
    print(GameConfig.LOG_PREFIX, "步骤7.3: 初始化兵种AI系统...")
    success, result = pcall(function()
        return UnitAI.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "兵种AI系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "兵种AI系统初始化失败(返回false)")
    else
        print(GameConfig.LOG_PREFIX, "兵种AI系统初始化成功")
    end

    -- 7.4 初始化BattleManager
    print(GameConfig.LOG_PREFIX, "步骤7.4: 初始化战斗管理器...")
    success, result = pcall(function()
        return BattleManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗管理器初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗管理器初始化失败(返回false)")
    else
        print(GameConfig.LOG_PREFIX, "战斗管理器初始化成功")
    end

    -- 7.5 初始化BattleTestSystem
    print(GameConfig.LOG_PREFIX, "步骤7.5: 初始化战斗测试系统...")
    success, result = pcall(function()
        return BattleTestSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗测试系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗测试系统初始化失败(返回false)")
    else
        print(GameConfig.LOG_PREFIX, "战斗测试系统初始化成功")
    end

    -- 检查是否有关键系统初始化失败
    if initializationFailed then
        warn("==========================================")
        warn(GameConfig.LOG_PREFIX, "警告: 一个或多个系统初始化失败!")
        warn(GameConfig.LOG_PREFIX, "服务端可能无法正常工作,请检查上述错误信息")
        warn("==========================================")
        return false
    end

    print("==========================================")
    print(GameConfig.LOG_PREFIX, "服务端初始化完成!")
    print(GameConfig.LOG_PREFIX, "等待玩家加入...")
    print("==========================================")
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
else
    print(GameConfig.LOG_PREFIX, "服务端运行正常")

    -- 显示系统信息
    if GameConfig.DEBUG_MODE then
        print("\n" .. GameConfig.LOG_PREFIX, "系统信息:")
        print("  - 最大玩家数:", GameConfig.MAX_PLAYERS)
        print("  - 基地数量:", GameConfig.HOME_COUNT)
        print("  - 初始金币:", GameConfig.INITIAL_COINS)
        print("")
    end
end

-- ==================== 调试命令(仅调试模式) ====================

if GameConfig.DEBUG_MODE then
    -- 提供一些调试函数
    _G.DebugAddCoins = function(playerName, amount)
        local Players = game:GetService("Players")
        local player = Players:FindFirstChild(playerName)
        if player then
            CurrencySystem.AddCoins(player, amount, "调试添加")
            print(GameConfig.LOG_PREFIX, "为", playerName, "添加", amount, "金币")
        else
            warn(GameConfig.LOG_PREFIX, "找不到玩家:", playerName)
        end
    end

    _G.DebugGetPlayerData = function(playerName)
        local Players = game:GetService("Players")
        local player = Players:FindFirstChild(playerName)
        if player then
            local data = DataManager.GetPlayerData(player)
            if data then
                print(GameConfig.LOG_PREFIX, "玩家数据:", playerName)
                print("  UserId:", data.UserId)
                print("  HomeSlot:", data.HomeSlot)
                print("  Coins:", data.Currency.Coins)
            else
                warn(GameConfig.LOG_PREFIX, "玩家数据不存在:", playerName)
            end
        else
            warn(GameConfig.LOG_PREFIX, "找不到玩家:", playerName)
        end
    end

    _G.DebugGetHomeOccupancy = function()
        local occupancy = PlayerManager.GetHomeOccupancy()
        print(GameConfig.LOG_PREFIX, "基地占用状态:")
        for slot = 1, GameConfig.HOME_COUNT do
            local player = occupancy[slot]
            if player then
                print(string.format("  基地%d: %s", slot, player.Name))
            else
                print(string.format("  基地%d: 空闲", slot))
            end
        end
    end

    print(GameConfig.LOG_PREFIX, "调试命令已加载:")
    print("  _G.DebugAddCoins(playerName, amount) - 为玩家添加金币")
    print("  _G.DebugGetPlayerData(playerName) - 查看玩家数据")
    print("  _G.DebugGetHomeOccupancy() - 查看基地占用状态")
end
