--[[
脚本名称: HomeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/HomeSystem
]]

--[[
基地系统模块
职责:
1. 管理玩家基地的初始化
2. 为后续兵种放置功能预留接口
3. 基地内容管理(后续版本扩展)
]]

local HomeSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")

-- 引用模块
local GameConfig = require(ServerScriptService.Config.GameConfig)
local DataManager = require(ServerScriptService.Core.DataManager)

-- 存储每个玩家的基地信息 [UserId] = HomeData
local playerHomes = {}

--[[
基地数据结构:
HomeData = {
    Player = Player,              -- 玩家对象
    HomeSlot = number,            -- 基地编号
    HomeFolder = Instance,        -- 基地文件夹引用
    SpawnLocation = Instance,     -- 出生点引用
    Units = {},                   -- 放置的兵种列表(后续版本)
}
]]

-- ==================== 私有函数 ====================

--[[
获取基地文件夹
@param homeSlot number - 基地编号
@return Instance|nil - 基地文件夹
]]
local function GetHomeFolder(homeSlot)
    local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "HomeSystem: 找不到Home文件夹!")
        return nil
    end

    local playerHomeName = GameConfig.HOME_PREFIX .. homeSlot
    local playerHome = homeFolder:FindFirstChild(playerHomeName)
    if not playerHome then
        warn(GameConfig.LOG_PREFIX, "HomeSystem: 找不到基地:", playerHomeName)
        return nil
    end

    return playerHome
end

-- ==================== 公共接口 ====================

--[[
初始化玩家基地
@param player Player - 玩家对象
@return boolean - 是否初始化成功
]]
function HomeSystem.InitializePlayerHome(player)
    if not player then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: player为空")
        return false
    end

    -- 获取玩家的基地编号
    local homeSlot = DataManager.GetPlayerHomeSlot(player)
    if not homeSlot or homeSlot == 0 then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 玩家未分配基地", player.Name)
        return false
    end

    -- 获取基地文件夹
    local homeFolder = GetHomeFolder(homeSlot)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 获取基地文件夹失败", homeSlot)
        return false
    end

    -- 获取出生点
    local spawnLocation = homeFolder:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
    if not spawnLocation then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 找不到出生点", homeSlot)
        return false
    end

    -- 验证出生点的有效性
    if not spawnLocation:IsA("BasePart") then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: SpawnLocation不是有效的BasePart", homeSlot)
        return false
    end

    -- 创建基地数据
    local homeData = {
        Player = player,
        HomeSlot = homeSlot,
        HomeFolder = homeFolder,
        SpawnLocation = spawnLocation,
        Units = {},  -- 后续版本用于存储兵种
    }

    playerHomes[player.UserId] = homeData

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化玩家基地:", player.Name, "基地编号:", homeSlot)
    end

    return true
end

--[[
获取玩家基地数据
@param player Player - 玩家对象
@return table|nil - 基地数据
]]
function HomeSystem.GetPlayerHome(player)
    if not player then
        return nil
    end

    return playerHomes[player.UserId]
end

--[[
清除玩家基地数据
@param player Player - 玩家对象
]]
function HomeSystem.ClearPlayerHome(player)
    if not player then
        return
    end

    local homeData = playerHomes[player.UserId]
    if homeData then
        -- TODO: 后续版本在此清理基地上的兵种等内容

        playerHomes[player.UserId] = nil

        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "清除玩家基地数据:", player.Name)
        end
    end
end

-- ==================== 后续版本预留接口 ====================

--[[
在基地上放置兵种(预留接口)
@param player Player - 玩家对象
@param unitId string - 兵种ID
@param position Vector3 - 放置位置
@return boolean - 是否成功
]]
function HomeSystem.PlaceUnit(player, unitId, position)
    -- TODO: 后续版本实现
    warn(GameConfig.LOG_PREFIX, "HomeSystem.PlaceUnit: 功能未实现,等待后续版本")
    return false
end

--[[
从基地移除兵种(预留接口)
@param player Player - 玩家对象
@param unitInstanceId string - 兵种实例ID
@return boolean - 是否成功
]]
function HomeSystem.RemoveUnit(player, unitInstanceId)
    -- TODO: 后续版本实现
    warn(GameConfig.LOG_PREFIX, "HomeSystem.RemoveUnit: 功能未实现,等待后续版本")
    return false
end

--[[
获取基地上的所有兵种(预留接口)
@param player Player - 玩家对象
@return table - 兵种列表
]]
function HomeSystem.GetHomeUnits(player)
    local homeData = HomeSystem.GetPlayerHome(player)
    if not homeData then
        return {}
    end

    return homeData.Units
end

--[[
初始化基地系统
]]
function HomeSystem.Initialize()
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化HomeSystem...")
    end

    -- 验证workspace中的基地结构
    local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "警告: workspace中找不到Home文件夹!")
        warn(GameConfig.LOG_PREFIX, "请确保workspace中存在Home文件夹,包含PlayerHome1到PlayerHome6")
    else
        -- 检查所有基地是否存在
        for i = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
            local playerHomeName = GameConfig.HOME_PREFIX .. i
            local playerHome = homeFolder:FindFirstChild(playerHomeName)

            if not playerHome then
                warn(GameConfig.LOG_PREFIX, "警告: 找不到基地:", playerHomeName)
            else
                local spawnLocation = playerHome:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
                if not spawnLocation then
                    warn(GameConfig.LOG_PREFIX, "警告:", playerHomeName, "缺少SpawnLocation")
                end
            end
        end

        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "基地结构验证完成")
        end
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "HomeSystem初始化完成")
    end
end

return HomeSystem
