--[[
脚本名称: DataManager
脚本类型: ModuleScript (服务端核心)
脚本位置: ServerScriptService/Core/DataManager
]]

--[[
数据管理器模块
职责:
1. 管理所有玩家的游戏数据
2. 提供数据的加载、获取、修改接口
3. 为后续数据持久化(DataStore)预留接口
]]

local DataManager = {}

-- 引用配置模块
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ServerScriptService.Config.GameConfig)

-- 存储所有玩家的数据 [UserId] = PlayerData
-- 注意: Roblox脚本是单线程执行,因此不存在真正的race condition问题
-- 多个玩家的事件通过Roblox的事件队列顺序处理,不会出现并发访问
local playerDataCache = {}

--[[
玩家数据结构:
PlayerData = {
    UserId = number,           -- 玩家ID
    Player = Player,           -- 玩家对象引用
    HomeSlot = number,         -- 分配的基地编号(1-6)
    Currency = {
        Coins = number,        -- 金币数量
    },
    Units = {},                -- 拥有的兵种数据(后续版本)
    LastSaveTime = number,     -- 最后保存时间
}
]]

-- ==================== 私有函数 ====================

--[[
创建默认玩家数据
@param player Player - 玩家对象
@return table - 初始化的玩家数据
]]
local function CreateDefaultData(player)
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "创建默认数据 for:", player.Name)
    end

    return {
        UserId = player.UserId,
        Player = player,
        HomeSlot = 0,  -- 初始为0,由PlayerManager分配
        Currency = {
            Coins = GameConfig.INITIAL_COINS,  -- 初始金币100
        },
        Units = {},  -- 后续版本使用
        LastSaveTime = os.time(),
    }
end

-- ==================== 公共接口 ====================

--[[
初始化玩家数据
@param player Player - 玩家对象
@return table - 玩家数据
]]
function DataManager.InitializePlayerData(player)
    if not player then
        warn(GameConfig.LOG_PREFIX, "InitializePlayerData: player为空")
        return nil
    end

    -- 检查是否已存在数据
    if playerDataCache[player.UserId] then
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "玩家数据已存在:", player.Name)
        end
        return playerDataCache[player.UserId]
    end

    -- 创建新数据
    -- TODO: 后续版本从DataStore加载数据
    local playerData = CreateDefaultData(player)
    playerDataCache[player.UserId] = playerData

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化玩家数据成功:", player.Name, "初始金币:", playerData.Currency.Coins)
    end

    return playerData
end

--[[
获取玩家数据
@param player Player - 玩家对象
@return table|nil - 玩家数据,如果不存在则返回nil
]]
function DataManager.GetPlayerData(player)
    if not player then
        warn(GameConfig.LOG_PREFIX, "GetPlayerData: player为空")
        return nil
    end

    return playerDataCache[player.UserId]
end

--[[
设置玩家的基地编号
@param player Player - 玩家对象
@param homeSlot number - 基地编号(1-6)
@return boolean - 是否设置成功
]]
function DataManager.SetPlayerHomeSlot(player, homeSlot)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetPlayerHomeSlot: 找不到玩家数据")
        return false
    end

    -- 验证基地编号有效性
    if homeSlot < GameConfig.MIN_HOME_SLOT or homeSlot > GameConfig.MAX_HOME_SLOT then
        warn(GameConfig.LOG_PREFIX, "SetPlayerHomeSlot: 无效的基地编号", homeSlot)
        return false
    end

    playerData.HomeSlot = homeSlot

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "设置玩家基地:", player.Name, "基地编号:", homeSlot)
    end

    return true
end

--[[
获取玩家的基地编号
@param player Player - 玩家对象
@return number|nil - 基地编号,如果不存在则返回nil
]]
function DataManager.GetPlayerHomeSlot(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    return playerData.HomeSlot
end

--[[
更新玩家货币
@param player Player - 玩家对象
@param currencyType string - 货币类型(例如"Coins")
@param amount number - 变化数量(可以是负数)
@param reason string - 变化原因(用于日志)
@return boolean, number - 是否成功, 更新后的货币数量
]]
function DataManager.UpdateCurrency(player, currencyType, amount, reason)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "UpdateCurrency: 找不到玩家数据")
        return false, 0
    end

    -- 验证货币类型
    if not playerData.Currency[currencyType] then
        warn(GameConfig.LOG_PREFIX, "UpdateCurrency: 无效的货币类型", currencyType)
        return false, 0
    end

    -- 计算新的货币数量
    local oldAmount = playerData.Currency[currencyType]
    local newAmount = oldAmount + amount

    -- 防止货币为负数
    if newAmount < 0 then
        newAmount = 0
    end

    playerData.Currency[currencyType] = newAmount

    if GameConfig.DEBUG_MODE then
        print(string.format(
            "%s 更新货币 - 玩家:%s 类型:%s 原值:%d 变化:%d 新值:%d 原因:%s",
            GameConfig.LOG_PREFIX, player.Name, currencyType, oldAmount, amount, newAmount, reason or "未知"
        ))
    end

    return true, newAmount
end

--[[
获取玩家货币数量
@param player Player - 玩家对象
@param currencyType string - 货币类型
@return number|nil - 货币数量
]]
function DataManager.GetCurrency(player, currencyType)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    return playerData.Currency[currencyType]
end

--[[
获取玩家所有货币
@param player Player - 玩家对象
@return table|nil - 货币数据表
]]
function DataManager.GetAllCurrency(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    return playerData.Currency
end

--[[
保存玩家数据
@param player Player - 玩家对象
@return boolean - 是否保存成功
]]
function DataManager.SavePlayerData(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SavePlayerData: 找不到玩家数据")
        return false
    end

    playerData.LastSaveTime = os.time()

    -- TODO: 后续版本实现DataStore保存
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "保存玩家数据:", player.Name, "(当前版本仅内存保存)")
    end

    return true
end

--[[
清除玩家数据(玩家离开时调用)
@param player Player - 玩家对象
]]
function DataManager.ClearPlayerData(player)
    if not player then
        return
    end

    -- 保存数据
    DataManager.SavePlayerData(player)

    -- 从缓存中移除
    playerDataCache[player.UserId] = nil

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "清除玩家数据:", player.Name)
    end
end

--[[
获取所有在线玩家数据(调试用)
@return table - 所有玩家数据
]]
function DataManager.GetAllPlayerData()
    return playerDataCache
end

return DataManager
