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

-- ==================== 系统初始化顺序 ====================

local function InitializeServer()
    print(GameConfig.LOG_PREFIX, "开始初始化服务端系统...")
    print(GameConfig.LOG_PREFIX, "调试模式:", GameConfig.DEBUG_MODE and "开启" or "关闭")

    local initializationFailed = false

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
