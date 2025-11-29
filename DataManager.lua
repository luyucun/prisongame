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

-- 🔥修复服务器关闭时数据保存：保存状态跟踪
local pendingSaves = {}  -- [UserId] = true 表示正在保存
local isShuttingDown = false  -- 服务器是否正在关闭

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
    PlacedUnits = {            -- 🔥修复持久化：已放置兵种数据
        [instanceId] = {
            UnitId = string,       -- 兵种ID
            Level = number,        -- 等级
            GridX = number,        -- 网格X坐标
            GridZ = number,        -- 网格Z坐标
            GridSize = number,     -- 占地大小(向后兼容)
            GridWidth = number,    -- 占地宽度(格数)
            GridDepth = number,    -- 占地深度(格数)
            IsActivated = boolean, -- 是否已激活(用于战役系统)
            Health = number,       -- 当前生命值
            MaxHealth = number,    -- 最大生命值
        }
    },
    ShopData = {               -- V2.1库存系统：商店数据持久化
        [shopId] = {
            LastRefreshTime = number,  -- 上次刷新时间戳
        }
    },
    IdleCoinData = {           -- V2.6挂机金币系统
        LastLogoutTime = number,   -- 上次登出时间戳
        PendingCoins = number,     -- 待领取的挂机金币
    },
    ChapterProgress = {        -- V2.8章节进度系统
        CurrentChapter = number,   -- 当前挑战章节(从1开始)
        CompletedChapters = number, -- 已通关的章节数(0表示未通关任何章节)
        CurrentHouseModel = string, -- 当前房屋模型名称
    },
    LastSaveTime = number,     -- 最后保存时间
}
]]

-- ==================== 私有函数 ====================

--[[
把值清洗为DataStore可接受的类型（number/boolean/string/table）
@param v any - 要清洗的值
@return any - 清洗后的值
]]
local function SanitizeForDataStore(v)
    local t = typeof(v)
    if t == "Vector3" then
        return {__type="Vector3", x=v.X, y=v.Y, z=v.Z}
    elseif t == "CFrame" then
        local cf = {v:GetComponents()}
        return {__type="CFrame", components=cf}
    elseif t == "Color3" then
        return {__type="Color3", r=v.R, g=v.G, b=v.B}
    elseif t == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[k] = SanitizeForDataStore(val)
        end
        return out
    elseif t == "Instance" then
        return nil -- 丢弃Instance，不能序列化
    else
        return v  -- number/boolean/string/nil直接返回
    end
end

--[[
清洗Units数组，处理其中的Vector3等不可序列化类型
@param units table|nil - 兵种数组
@return table - 清洗后的兵种数组
]]
local function CleanUnits(units)
    if type(units) ~= "table" then
        return {}
    end

    local out = {}
    for i, unitInstance in ipairs(units) do
        local cleaned = SanitizeForDataStore(unitInstance)
        if cleaned then  -- 过滤掉nil值
            table.insert(out, cleaned)
        end
    end
    return out
end

--[[
还原Vector3等类型（加载时使用）
@param data any - 要还原的数据
@return any - 还原后的数据
]]
local function RestoreFromDataStore(data)
    if type(data) == "table" then
        if data.__type == "Vector3" then
            return Vector3.new(data.x, data.y, data.z)
        elseif data.__type == "CFrame" then
            return CFrame.new(unpack(data.components))
        elseif data.__type == "Color3" then
            return Color3.new(data.r, data.g, data.b)
        else
            -- 普通table，递归处理
            local out = {}
            for k, v in pairs(data) do
                out[k] = RestoreFromDataStore(v)
            end
            return out
        end
    else
        return data
    end
end

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
		-- 还原Vector3等类型（如果需要）
		if data.Units then
			data.Units = RestoreFromDataStore(data.Units)
		end
		if data.Currency then
			data.Currency = RestoreFromDataStore(data.Currency)
		end
		if data.PlacedUnits then
			data.PlacedUnits = RestoreFromDataStore(data.PlacedUnits)  -- 🔥修复持久化：恢复放置数据
		end
		if data.ShopData then
			data.ShopData = RestoreFromDataStore(data.ShopData)
		end
		if data.IdleCoinData then
			data.IdleCoinData = RestoreFromDataStore(data.IdleCoinData)  -- V2.6：恢复挂机金币数据
		end
		if data.ChapterProgress then
			data.ChapterProgress = RestoreFromDataStore(data.ChapterProgress)  -- V2.8：恢复章节进度数据
		end
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
local function SaveToDataStore(player, playerData, userId)
	-- 🔥修复服务器关闭时数据保存：支持直接传入userId
	local targetUserId = userId or (player and player.UserId) or playerData.UserId
	local playerName = (player and player.Name) or ("UserId_" .. targetUserId)

	-- 构造要保存的数据（去除Player引用等不可序列化字段）
	local dataToSave = {
		UserId = playerData.UserId,
		HomeSlot = playerData.HomeSlot,
		Currency = SanitizeForDataStore(playerData.Currency),
		Units = CleanUnits(playerData.Units),  -- 关键：清洗Units中的Vector3等类型
		PlacedUnits = SanitizeForDataStore(playerData.PlacedUnits),  -- 🔥修复持久化：保存放置数据
		ShopData = SanitizeForDataStore(playerData.ShopData),  -- V2.1库存系统：保存商店数据
		IdleCoinData = SanitizeForDataStore(playerData.IdleCoinData),  -- V2.6：保存挂机金币数据
		ChapterProgress = SanitizeForDataStore(playerData.ChapterProgress),  -- V2.8：保存章节进度数据
		LastSaveTime = os.time(),
	}

	local success, errorMsg = pcall(function()
		PlayerDataStore:SetAsync("Player_" .. targetUserId, dataToSave)
	end)

	if success then
		return true
	else
		warn(string.format(
			"%s [DataManager] DataStore保存失败 - 玩家:%s 错误:%s",
			GameConfig.LOG_PREFIX,
			playerName,
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
        PlacedUnits = {},  -- 🔥修复持久化：初始化空的放置数据
        ShopData = {},  -- V2.1库存系统：初始化空商店数据
        IdleCoinData = {  -- V2.6挂机金币系统：初始化
            LastLogoutTime = 0,
            PendingCoins = 0,
        },
        ChapterProgress = {  -- V2.8章节进度系统：初始化
            CurrentChapter = 1,       -- 默认从第1章开始
            CompletedChapters = 0,    -- 未通关任何章节
            CurrentHouseModel = "PrisonLv1",  -- 默认初始房屋
        },
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

        -- 🔥重要：清除旧的HomeSlot，让PlayerManager重新分配
        -- HomeSlot是运行时动态分配的，不应该从存档恢复
        playerData.HomeSlot = nil

        -- 确保ShopData字段存在（向后兼容）
        if not playerData.ShopData then
            playerData.ShopData = {}
        end

        -- 🔥修复库存售罄：向后兼容 - 为所有已有商店数据添加Stock字段
        for shopId, shopData in pairs(playerData.ShopData) do
            if not shopData.Stock then
                shopData.Stock = {}
            end
        end

        -- 🔥修复持久化：确保PlacedUnits字段存在（向后兼容）
        if not playerData.PlacedUnits then
            playerData.PlacedUnits = {}
        end

        -- V2.6挂机金币：确保IdleCoinData字段存在（向后兼容）
        if not playerData.IdleCoinData then
            playerData.IdleCoinData = {
                LastLogoutTime = 0,
                PendingCoins = 0,
            }
        end

        -- V2.8章节进度：确保ChapterProgress字段存在（向后兼容）
        if not playerData.ChapterProgress then
            playerData.ChapterProgress = {
                CurrentChapter = 1,
                CompletedChapters = 0,
                CurrentHouseModel = "PrisonLv1",
            }
        end

    else
        -- 创建新数据
        playerData = CreateDefaultData(player)

    end

    playerDataCache[player.UserId] = playerData

    return playerData
end

--[[
等待玩家数据加载完成（修复竞态条件）
@param player Player - 玩家对象
@param timeout number - 超时时间（秒），默认10秒
@return table|nil - 玩家数据，超时返回nil
]]
function DataManager.WaitForPlayerData(player, timeout)
    if not player then
        warn(GameConfig.LOG_PREFIX, "WaitForPlayerData: player为空")
        return nil
    end

    timeout = timeout or 10  -- 默认10秒超时
    local startTime = tick()

    -- 如果数据已存在，直接返回
    if playerDataCache[player.UserId] then
        return playerDataCache[player.UserId]
    end

    -- 等待数据加载完成
    while tick() - startTime < timeout do
        if playerDataCache[player.UserId] then
            return playerDataCache[player.UserId]
        end
        task.wait(0.1)  -- 每100ms检查一次
    end

    -- 超时
    warn(GameConfig.LOG_PREFIX, "WaitForPlayerData: 等待玩家数据超时 -", player.Name)
    return nil
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
@return table|nil - 商店数据 {LastRefreshTime = number, Stock = {[unitId] = number}}
]]
function DataManager.GetShopData(player, shopId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    if not playerData.ShopData[shopId] then
        playerData.ShopData[shopId] = {
            LastRefreshTime = 0,  -- 默认为0表示首次进入
            Stock = {}           -- 🔥修复库存售罄：添加Stock字段存储库存数据
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
        playerData.ShopData[shopId] = {
            Stock = {}  -- 🔥修复库存售罄：确保Stock字段存在
        }
    end

    playerData.ShopData[shopId].LastRefreshTime = refreshTime


    return true
end

--[[
🔥修复库存售罄：保存玩家商店库存数据
@param player Player - 玩家对象
@param shopId string - 商店ID
@param stockData table - 库存数据 {[unitId] = stock}
@return boolean - 是否设置成功
]]
function DataManager.SetShopStock(player, shopId, stockData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetShopStock: 找不到玩家数据")
        return false
    end

    if not playerData.ShopData[shopId] then
        playerData.ShopData[shopId] = {
            LastRefreshTime = 0
        }
    end

    -- 保存库存数据（清洗掉LastRefreshTime等非库存字段）
    local cleanedStock = {}
    for unitId, stock in pairs(stockData) do
        if unitId ~= "LastRefreshTime" and type(stock) == "number" then
            cleanedStock[unitId] = stock
        end
    end

    playerData.ShopData[shopId].Stock = cleanedStock

    return true
end

--[[
🔥修复库存售罄：获取玩家商店库存数据
@param player Player - 玩家对象
@param shopId string - 商店ID
@return table - 库存数据 {[unitId] = stock}
]]
function DataManager.GetShopStock(player, shopId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {}
    end

    if not playerData.ShopData[shopId] then
        return {}
    end

    return playerData.ShopData[shopId].Stock or {}
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

    -- 🔥修复服务器关闭时数据保存：标记保存开始
    pendingSaves[player.UserId] = true

    -- 🔥修复持久化：只在保存成功后才更新LastSaveTime，避免保存失败后节流机制阻止重试
    local saveSuccess = SaveToDataStore(player, playerData)
    if saveSuccess then
        playerData.LastSaveTime = os.time()
    end

    -- 🔥修复服务器关闭时数据保存：标记保存完成
    pendingSaves[player.UserId] = nil

    return saveSuccess
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

-- ==================== 🔥修复持久化：放置单位数据管理 ====================

--[[
保存放置单位数据
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@param placedData table - 放置数据 {UnitId, Level, GridX, GridZ, GridSize, IsActivated, Health, MaxHealth}
@return boolean - 是否保存成功
]]
function DataManager.SavePlacedUnit(player, instanceId, placedData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SavePlacedUnit: 找不到玩家数据")
        return false
    end

    -- 确保PlacedUnits字段存在
    if not playerData.PlacedUnits then
        playerData.PlacedUnits = {}
    end

    -- 保存放置数据（只保存可序列化的数据，不包含Model引用）
    playerData.PlacedUnits[instanceId] = {
        UnitId = placedData.UnitId,
        Level = placedData.Level or 1,
        GridX = placedData.GridX,
        GridZ = placedData.GridZ,
        GridSize = placedData.GridSize or 1,
        IsActivated = placedData.IsActivated or false,
        Health = placedData.Health,
        MaxHealth = placedData.MaxHealth,
    }

    return true
end

--[[
移除放置单位数据
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@return boolean - 是否移除成功
]]
function DataManager.RemovePlacedUnit(player, instanceId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "RemovePlacedUnit: 找不到玩家数据")
        return false
    end

    if playerData.PlacedUnits and playerData.PlacedUnits[instanceId] then
        playerData.PlacedUnits[instanceId] = nil
        return true
    end

    return false
end

--[[
获取玩家的所有放置单位数据
@param player Player - 玩家对象
@return table - 放置单位数据表 {[instanceId] = placedData}
]]
function DataManager.GetPlacedUnits(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {}
    end

    return playerData.PlacedUnits or {}
end

--[[
获取特定放置单位的数据
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@return table|nil - 放置单位数据，不存在返回nil
]]
function DataManager.GetPlacedUnit(player, instanceId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData or not playerData.PlacedUnits then
        return nil
    end

    return playerData.PlacedUnits[instanceId]
end

--[[
更新放置单位的位置
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@param gridX number - 新的网格X坐标
@param gridZ number - 新的网格Z坐标
@return boolean - 是否更新成功
]]
function DataManager.UpdatePlacedUnitPosition(player, instanceId, gridX, gridZ)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData or not playerData.PlacedUnits or not playerData.PlacedUnits[instanceId] then
        warn(GameConfig.LOG_PREFIX, "UpdatePlacedUnitPosition: 找不到放置单位数据")
        return false
    end

    playerData.PlacedUnits[instanceId].GridX = gridX
    playerData.PlacedUnits[instanceId].GridZ = gridZ
    return true
end

--[[
更新放置单位的生命值
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@param health number - 当前生命值
@param maxHealth number - 最大生命值（可选）
@return boolean - 是否更新成功
]]
function DataManager.UpdatePlacedUnitHealth(player, instanceId, health, maxHealth)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData or not playerData.PlacedUnits or not playerData.PlacedUnits[instanceId] then
        warn(GameConfig.LOG_PREFIX, "UpdatePlacedUnitHealth: 找不到放置单位数据")
        return false
    end

    playerData.PlacedUnits[instanceId].Health = health
    if maxHealth then
        playerData.PlacedUnits[instanceId].MaxHealth = maxHealth
    end
    return true
end

--[[
节流式保存玩家数据（避免频繁保存）
@param player Player - 玩家对象
@param forceImmediate boolean - 是否强制立即保存（可选，默认false）
@return boolean - 是否保存成功
]]
function DataManager.SavePlayerDataThrottled(player, forceImmediate)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SavePlayerDataThrottled: 找不到玩家数据")
        return false
    end

    local currentTime = os.time()
    local timeSinceLastSave = currentTime - (playerData.LastSaveTime or 0)
    local SAVE_THROTTLE_SECONDS = 30  -- 30秒内避免重复保存
    local RETRY_AFTER_FAILURE_SECONDS = 5  -- 保存失败后5秒允许重试

    -- 判断是否需要保存
    local shouldSave = false

    if forceImmediate then
        shouldSave = true
        -- print(string.format("[DataManager] 🔥 强制立即保存: 玩家 %s", player.Name))
    elseif timeSinceLastSave >= SAVE_THROTTLE_SECONDS then
        shouldSave = true
        -- print(string.format("[DataManager] 🔥 正常节流保存: 玩家 %s (距离上次 %d 秒)", player.Name, timeSinceLastSave))
    elseif playerData.LastSaveFailedTime and (currentTime - playerData.LastSaveFailedTime) >= RETRY_AFTER_FAILURE_SECONDS then
        shouldSave = true
        -- print(string.format("[DataManager] 🔥 保存失败重试: 玩家 %s (距离失败 %d 秒)", player.Name, currentTime - playerData.LastSaveFailedTime))
    end

    if shouldSave then
        local saveSuccess = DataManager.SavePlayerData(player)
        if not saveSuccess then
            -- 记录保存失败的时间，允许较快重试
            playerData.LastSaveFailedTime = currentTime
            warn(string.format(
                "%s [DataManager] 🔥 保存失败，将在 %d 秒后允许重试: 玩家 %s",
                GameConfig.LOG_PREFIX,
                RETRY_AFTER_FAILURE_SECONDS,
                player.Name
            ))
        else
            -- 保存成功，清除失败标记
            playerData.LastSaveFailedTime = nil
        end
        return saveSuccess
    else
        -- 标记需要保存，但暂不执行（节流中）
        return true
    end
end

--[[
🔥修复服务器关闭时数据保存：设置关机状态
]]
function DataManager.SetShuttingDown(value)
    isShuttingDown = value
end

--[[
🔥修复服务器关闭时数据保存：获取关机状态
@return boolean - 是否正在关机
]]
function DataManager.IsShuttingDown()
    return isShuttingDown
end

--[[
🔥修复服务器关闭时数据保存：获取所有玩家数据（从缓存）
@return table - 所有玩家数据 {[UserId] = PlayerData}
]]
function DataManager.GetAllPlayerData()
    return playerDataCache
end

--[[
🔥修复服务器关闭时数据保存：根据UserId保存缓存数据
@param userId number - 玩家UserId
@return boolean - 是否保存成功
]]
function DataManager.SaveCachedPlayerData(userId)
    local playerData = playerDataCache[userId]
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SaveCachedPlayerData: 找不到缓存数据 -", userId)
        return false
    end

    -- 标记保存开始
    pendingSaves[userId] = true

    -- 创建临时Player对象用于保存（仅用于日志）
    local success = SaveToDataStore(nil, playerData, userId)

    -- 标记保存完成
    pendingSaves[userId] = nil

    return success
end

--[[
🔥修复服务器关闭时数据保存：等待所有保存完成
@param timeout number - 超时时间（秒），默认10秒
@return boolean - 是否在超时前全部完成
]]
function DataManager.WaitForAllSavesToComplete(timeout)
    timeout = timeout or 10
    local startTime = tick()

    while tick() - startTime < timeout do
        local hasPendingSaves = false
        for _ in pairs(pendingSaves) do
            hasPendingSaves = true
            break
        end

        if not hasPendingSaves then
            return true  -- 全部完成
        end

        task.wait(0.1)
    end

    return false  -- 超时
end

--[[
🔥修复服务器关闭时数据保存：获取待保存数量
@return number - 待保存的玩家数量
]]
function DataManager.GetPendingSaveCount()
    local count = 0
    for _ in pairs(pendingSaves) do
        count = count + 1
    end
    return count
end

--[[
🔥修复服务器关闭时数据保存：同步放置单位数据
@param player Player - 玩家对象
@param placedUnitsData table - 放置单位数据
]]
function DataManager.SyncPlacedUnits(player, placedUnitsData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SyncPlacedUnits: 找不到玩家数据")
        return false
    end

    -- 清洗数据，移除不可序列化的字段（如Model引用）
    local cleanedData = {}
    for instanceId, unitData in pairs(placedUnitsData) do
        local gridWidth = unitData.GridWidth or unitData.GridSize or 1
        local gridDepth = unitData.GridDepth or unitData.GridSize or gridWidth

        cleanedData[instanceId] = {
            InstanceId = unitData.InstanceId,
            UnitId = unitData.UnitId,
            Level = unitData.Level or 1,
            GridX = unitData.GridX,
            GridZ = unitData.GridZ,
            GridSize = unitData.GridSize,
            GridWidth = gridWidth,
            GridDepth = gridDepth,
            PlacedTime = unitData.PlacedTime,
            -- 注意：不包含Position和Model，因为这些可以通过其他数据重建
        }
    end

    playerData.PlacedUnits = cleanedData
    return true
end

--[[
🔥修复服务器关闭时数据保存：添加单个放置单位
@param player Player - 玩家对象
@param instanceId string - 实例ID
@param unitData table - 单位数据
]]
function DataManager.AddPlacedUnit(player, instanceId, unitData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "AddPlacedUnit: 找不到玩家数据")
        return false
    end

    if not playerData.PlacedUnits then
        playerData.PlacedUnits = {}
    end

    -- 清洗数据
    local gridWidth = unitData.GridWidth or unitData.GridSize or 1
    local gridDepth = unitData.GridDepth or unitData.GridSize or gridWidth

    playerData.PlacedUnits[instanceId] = {
        InstanceId = unitData.InstanceId,
        UnitId = unitData.UnitId,
        Level = unitData.Level or 1,
        GridX = unitData.GridX,
        GridZ = unitData.GridZ,
        GridSize = unitData.GridSize,
        GridWidth = gridWidth,
        GridDepth = gridDepth,
        PlacedTime = unitData.PlacedTime or os.time(),
    }

    return true
end

-- ==================== V2.6挂机金币系统接口 ====================

--[[
获取玩家挂机金币数据
@param player Player - 玩家对象
@return table - {LastLogoutTime = number, PendingCoins = number}
]]
function DataManager.GetIdleCoinData(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {LastLogoutTime = 0, PendingCoins = 0}
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
        }
    end

    return playerData.IdleCoinData
end

--[[
设置玩家待领取的挂机金币
@param player Player - 玩家对象
@param coins number - 待领取金币数量
@return boolean - 是否设置成功
]]
function DataManager.SetPendingIdleCoins(player, coins)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetPendingIdleCoins: 找不到玩家数据")
        return false
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
        }
    end

    playerData.IdleCoinData.PendingCoins = coins
    return true
end

--[[
设置玩家上次登出时间
@param player Player - 玩家对象
@param timestamp number - 登出时间戳
@return boolean - 是否设置成功
]]
function DataManager.SetLastLogoutTime(player, timestamp)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetLastLogoutTime: 找不到玩家数据")
        return false
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
        }
    end

    playerData.IdleCoinData.LastLogoutTime = timestamp
    return true
end

--[[
增加玩家待领取的挂机金币
@param player Player - 玩家对象
@param amount number - 增加数量
@return boolean, number - 是否成功, 新的待领取金币数量
]]
function DataManager.AddPendingIdleCoins(player, amount)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "AddPendingIdleCoins: 找不到玩家数据")
        return false, 0
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
        }
    end

    playerData.IdleCoinData.PendingCoins = (playerData.IdleCoinData.PendingCoins or 0) + amount
    return true, playerData.IdleCoinData.PendingCoins
end

--[[
清空玩家待领取的挂机金币
@param player Player - 玩家对象
@return number - 清空前的金币数量
]]
function DataManager.ClearPendingIdleCoins(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "ClearPendingIdleCoins: 找不到玩家数据")
        return 0
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
        }
        return 0
    end

    local oldAmount = playerData.IdleCoinData.PendingCoins or 0
    playerData.IdleCoinData.PendingCoins = 0
    return oldAmount
end

--[[
GM命令：重置玩家所有数据
@param player Player - 玩家对象
@return boolean - 是否重置成功
说明: 此函数会清空玩家的所有数据并保存到DataStore
]]
function DataManager.ResetAllPlayerData(player)
    if not player then
        warn(GameConfig.LOG_PREFIX, "ResetAllPlayerData: player为空")
        return false
    end

    local userId = player.UserId

    -- 创建全新的默认数据
    local newData = CreateDefaultData(player)

    -- 更新缓存
    playerDataCache[userId] = newData

    -- 立即保存到DataStore
    local saveSuccess = SaveToDataStore(player, newData)

    if saveSuccess then
        print(string.format(
            "%s [DataManager] ✅ 玩家 %s 的所有数据已重置",
            GameConfig.LOG_PREFIX,
            player.Name
        ))
    else
        warn(string.format(
            "%s [DataManager] ⚠ 玩家 %s 数据重置后保存失败",
            GameConfig.LOG_PREFIX,
            player.Name
        ))
    end

    return saveSuccess
end

-- ==================== V2.8章节进度系统接口 ====================

--[[
获取玩家章节进度数据
@param player Player - 玩家对象
@return table - {CurrentChapter = number, CompletedChapters = number, CurrentHouseModel = string}
]]
function DataManager.GetChapterProgress(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {CurrentChapter = 1, CompletedChapters = 0, CurrentHouseModel = "PrisonLv1"}
    end

    if not playerData.ChapterProgress then
        playerData.ChapterProgress = {
            CurrentChapter = 1,
            CompletedChapters = 0,
            CurrentHouseModel = "PrisonLv1",
        }
    end

    return playerData.ChapterProgress
end

--[[
获取玩家当前挑战章节
@param player Player - 玩家对象
@return number - 当前章节ID
]]
function DataManager.GetCurrentChapter(player)
    local progress = DataManager.GetChapterProgress(player)
    return progress.CurrentChapter or 1
end

--[[
获取玩家已通关章节数
@param player Player - 玩家对象
@return number - 已通关章节数
]]
function DataManager.GetCompletedChapters(player)
    local progress = DataManager.GetChapterProgress(player)
    return progress.CompletedChapters or 0
end

--[[
设置玩家当前挑战章节
@param player Player - 玩家对象
@param chapterId number - 章节ID
@return boolean - 是否设置成功
]]
function DataManager.SetCurrentChapter(player, chapterId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetCurrentChapter: 找不到玩家数据")
        return false
    end

    if not playerData.ChapterProgress then
        playerData.ChapterProgress = {
            CurrentChapter = 1,
            CompletedChapters = 0,
            CurrentHouseModel = "PrisonLv1",
        }
    end

    playerData.ChapterProgress.CurrentChapter = chapterId
    return true
end

--[[
通关章节（增加已通关章节数）
@param player Player - 玩家对象
@param chapterId number - 通关的章节ID
@return boolean, number - 是否成功, 新的已通关章节数
]]
function DataManager.CompleteChapter(player, chapterId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "CompleteChapter: 找不到玩家数据")
        return false, 0
    end

    if not playerData.ChapterProgress then
        playerData.ChapterProgress = {
            CurrentChapter = 1,
            CompletedChapters = 0,
            CurrentHouseModel = "PrisonLv1",
        }
    end

    -- 只有通关当前章节才更新进度（防止重复通关刷进度）
    if chapterId == playerData.ChapterProgress.CurrentChapter then
        -- 更新已通关章节数
        if chapterId > playerData.ChapterProgress.CompletedChapters then
            playerData.ChapterProgress.CompletedChapters = chapterId
        end
        -- 自动进入下一章
        playerData.ChapterProgress.CurrentChapter = chapterId + 1
    end

    return true, playerData.ChapterProgress.CompletedChapters
end

--[[
获取玩家当前房屋模型名称
@param player Player - 玩家对象
@return string - 房屋模型名称
]]
function DataManager.GetCurrentHouseModel(player)
    local progress = DataManager.GetChapterProgress(player)
    return progress.CurrentHouseModel or "PrisonLv1"
end

--[[
设置玩家当前房屋模型名称
@param player Player - 玩家对象
@param modelName string - 新的房屋模型名称
@return boolean - 是否设置成功
]]
function DataManager.SetCurrentHouseModel(player, modelName)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetCurrentHouseModel: 找不到玩家数据")
        return false
    end

    if not playerData.ChapterProgress then
        playerData.ChapterProgress = {
            CurrentChapter = 1,
            CompletedChapters = 0,
            CurrentHouseModel = "PrisonLv1",
        }
    end

    playerData.ChapterProgress.CurrentHouseModel = modelName
    return true
end

return DataManager
