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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")  -- V2.1：添加DataStore服务
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- DataStore实例（V2.1库存系统：添加真正的持久化）
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_V2.1")

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
    ShopData = {               -- V2.1库存系统：商店数据持久化
        [shopId] = {
            LastRefreshTime = number,  -- 上次刷新时间戳
        }
    },
    LastSaveTime = number,     -- 最后保存时间
}
]]

-- ==================== 私有函数 ====================

--[[
从DataStore加载玩家数据（V2.1库存系统：实现真正的持久化）
@param player Player - 玩家对象
@return table|nil - 加载的数据，失败返回nil
]]
local function LoadFromDataStore(player)
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and data then
		return data
	elseif not success then
		warn(string.format(
			"%s [DataManager] DataStore加载失败 - 玩家:%s 错误:%s",
			GameConfig.LOG_PREFIX,
			player.Name,
			tostring(data)
		))
	end

	return nil
end

--[[
保存玩家数据到DataStore（V2.1库存系统：实现真正的持久化）
@param player Player - 玩家对象
@param playerData table - 玩家数据
@return boolean - 是否保存成功
]]
local function SaveToDataStore(player, playerData)
	-- 构造要保存的数据（去除Player引用等不可序列化字段）
	local dataToSave = {
		UserId = playerData.UserId,
		HomeSlot = playerData.HomeSlot,
		Currency = playerData.Currency,
		Units = playerData.Units,
		ShopData = playerData.ShopData,  -- V2.1库存系统：保存商店数据
		LastSaveTime = os.time(),
	}

	local success, errorMsg = pcall(function()
		PlayerDataStore:SetAsync("Player_" .. player.UserId, dataToSave)
	end)

	if success then
		return true
	else
		warn(string.format(
			"%s [DataManager] DataStore保存失败 - 玩家:%s 错误:%s",
			GameConfig.LOG_PREFIX,
			player.Name,
			tostring(errorMsg)
		))
		return false
	end
end

--[[
创建默认玩家数据
@param player Player - 玩家对象
@return table - 初始化的玩家数据
]]
local function CreateDefaultData(player)

    return {
        UserId = player.UserId,
        Player = player,
        HomeSlot = 0,  -- 初始为0,由PlayerManager分配
        Currency = {
            Coins = GameConfig.INITIAL_COINS,  -- 初始金币100
        },
        Units = {},  -- 后续版本使用
        ShopData = {},  -- V2.1库存系统：初始化空商店数据
        LastSaveTime = os.time(),
    }
end

-- ==================== 公共接口 ====================

--[[
初始化玩家数据（V2.1库存系统：从DataStore加载）
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
        return playerDataCache[player.UserId]
    end

    -- V2.1库存系统：尝试从DataStore加载数据
    local loadedData = LoadFromDataStore(player)
    local playerData

    if loadedData then
        -- 使用加载的数据，但重新设置Player引用
        playerData = loadedData
        playerData.Player = player

        -- 确保ShopData字段存在（向后兼容）
        if not playerData.ShopData then
            playerData.ShopData = {}
        end

    else
        -- 创建新数据
        playerData = CreateDefaultData(player)

    end

    playerDataCache[player.UserId] = playerData

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
V2.1库存系统：获取玩家商店数据
@param player Player - 玩家对象
@param shopId string - 商店ID
@return table|nil - 商店数据 {LastRefreshTime = number}
]]
function DataManager.GetShopData(player, shopId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    if not playerData.ShopData[shopId] then
        playerData.ShopData[shopId] = {
            LastRefreshTime = 0  -- 默认为0表示首次进入
        }
    end

    return playerData.ShopData[shopId]
end

--[[
V2.1库存系统：设置玩家商店刷新时间
@param player Player - 玩家对象
@param shopId string - 商店ID
@param refreshTime number - 刷新时间戳
@return boolean - 是否设置成功
]]
function DataManager.SetShopRefreshTime(player, shopId, refreshTime)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetShopRefreshTime: 找不到玩家数据")
        return false
    end

    if not playerData.ShopData[shopId] then
        playerData.ShopData[shopId] = {}
    end

    playerData.ShopData[shopId].LastRefreshTime = refreshTime


    return true
end

--[[
保存玩家数据（V2.1库存系统：保存到DataStore）
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

    -- V2.1库存系统：保存到DataStore
    return SaveToDataStore(player, playerData)
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

end

--[[
获取所有在线玩家数据(调试用)
@return table - 所有玩家数据
]]
function DataManager.GetAllPlayerData()
    return playerDataCache
end

return DataManager
