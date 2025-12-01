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
4. V2.8.2新增：基地初始化时立即替换正确等级的房屋
]]

local HomeSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local DataManager = require(ServerScriptService.Core.DataManager)
local DoorControlService = require(ServerScriptService.Systems.DoorControlService)  -- V2.0.1新增

-- V2.8.2新增：延迟加载HouseConfig和HouseUpgradeSystem避免循环依赖
local HouseConfig
local HouseUpgradeSystem

local function EnsureHouseModulesLoaded()
	if not HouseConfig then
		HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
	end
	if not HouseUpgradeSystem then
		local houseModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("HouseUpgradeSystem")
		if houseModule then
			HouseUpgradeSystem = require(houseModule)
		end
	end
end

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
初始化玩家基地 (V2.8.2修改：立即替换正确等级的房屋，无延迟)
@param homeId number - 基地编号 (1~6)
@param player Player - 玩家对象
@return boolean - 是否初始化成功
]]
function HomeSystem.InitializePlayerHome(homeId, player)
    if not homeId or not player then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 参数无效")
        return false
    end

    -- 验证基地编号范围
    if homeId < GameConfig.MIN_HOME_SLOT or homeId > GameConfig.MAX_HOME_SLOT then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 基地编号超出范围", homeId)
        return false
    end

    -- 获取基地文件夹
    local homeFolder = GetHomeFolder(homeId)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 获取基地文件夹失败", homeId)
        return false
    end

    -- 获取出生点
    local spawnLocation = homeFolder:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
    if not spawnLocation then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 找不到出生点", homeId)
        return false
    end

    -- 验证出生点的有效性
    if not spawnLocation:IsA("BasePart") then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: SpawnLocation不是有效的BasePart", homeId)
        return false
    end

    -- V2.8.2新增：立即替换正确等级的房屋（无延迟）
    EnsureHouseModulesLoaded()
    if HouseConfig and HouseUpgradeSystem then
        local completedChapters = DataManager.GetCompletedChapters(player)
        local targetModelName = HouseConfig.GetHouseModelByChapter(completedChapters)

        -- 获取场景中当前的房屋模型
        local houseFolder = homeFolder:FindFirstChild("House")
        local currentHouseModel = nil
        if houseFolder then
            for _, child in ipairs(houseFolder:GetChildren()) do
                if child:IsA("Model") then
                    currentHouseModel = child
                    break
                end
            end
        end

        local actualModelName = currentHouseModel and currentHouseModel.Name or "PrisonLv1"

        -- 如果当前房屋不是目标房屋，立即替换
        if actualModelName ~= targetModelName then
            print(string.format(
                "%s [HomeSystem] V2.8.2 立即替换房屋: %s -> %s (玩家: %s, 通关章节: %d)",
                GameConfig.LOG_PREFIX,
                actualModelName,
                targetModelName,
                player.Name,
                completedChapters
            ))

            -- 立即执行替换，不使用延迟
            local success = HouseUpgradeSystem.ReplaceHouseModel(player, targetModelName)
            if success then
                print(string.format(
                    "%s [HomeSystem] V2.8.2 房屋替换成功: %s",
                    GameConfig.LOG_PREFIX,
                    targetModelName
                ))
            else
                warn(string.format(
                    "%s [HomeSystem] V2.8.2 房屋替换失败: %s",
                    GameConfig.LOG_PREFIX,
                    targetModelName
                ))
            end
        else
            if GameConfig.DEBUG_MODE then
                print(string.format(
                    "%s [HomeSystem] V2.8.2 房屋已是正确等级: %s",
                    GameConfig.LOG_PREFIX,
                    actualModelName
                ))
            end
        end

        -- 更新存档中的房屋模型名称
        local savedModelName = DataManager.GetCurrentHouseModel(player)
        if savedModelName ~= targetModelName then
            DataManager.SetCurrentHouseModel(player, targetModelName)
        end
    end

    -- 创建基地数据
    local homeData = {
        Player = player,
        HomeSlot = homeId,
        HomeFolder = homeFolder,
        SpawnLocation = spawnLocation,
        Units = {},  -- 后续版本用于存储兵种
    }

    playerHomes[player.UserId] = homeData

    -- V2.0.1新增：初始化基地门状态（确保门关闭）
    pcall(function()
        DoorControlService.SetDoorState(homeId, "Closed")
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "初始化基地门状态: PlayerHome" .. homeId .. " -> Closed")
        end
    end)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化玩家基地:", player.Name, "基地编号:", homeId)
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
清理玩家基地数据 (V2.0.1新增：支持基地门关闭)
@param homeId number - 基地编号 (1~6)
@param player Player - 玩家对象
]]
function HomeSystem.CleanupPlayerHome(homeId, player)
    if not homeId or not player then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.CleanupPlayerHome: 参数无效")
        return
    end

    -- V2.0.1新增：关闭基地门
    pcall(function()
        DoorControlService.CloseDoor(homeId)
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "清理时关闭基地门: PlayerHome" .. homeId)
        end
    end)

    -- 调用原有清理逻辑
    HomeSystem.ClearPlayerHome(player)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "清理玩家基地完成:", player.Name, "基地编号:", homeId)
    end
end

--[[
清除玩家基地数据 (V2.0.1保留：向下兼容)
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
