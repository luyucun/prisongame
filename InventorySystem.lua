--[[
脚本名称: InventorySystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/InventorySystem
]]

--[[
背包系统模块
职责:
1. 管理玩家拥有的兵种实例
2. 提供添加/删除/查询兵种的接口
3. 支持多个相同兵种的存储
4. 为后续兵种放置和合成预留接口
]]

local InventorySystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用模块
local GameConfig = require(ServerScriptService.Config.GameConfig)
local UnitConfig = require(ServerScriptService.Config.UnitConfig)
local DataManager = require(ServerScriptService.Core.DataManager)

-- 远程事件(延迟获取)
local InventoryEvents = nil

-- ==================== 兵种实例数据结构 ====================
--[[
UnitInstance = {
    InstanceId = string,       -- 实例唯一ID(UUID)
    UnitId = string,           -- 兵种ID(对应UnitConfig中的配置)
    Level = number,            -- 当前等级(初始为BaseLevel)
    GridSize = number,         -- 占地面积
    CreatedTime = number,      -- 创建时间戳
    IsPlaced = boolean,        -- 是否已放置在场地上
    PlacedPosition = Vector3,  -- 放置位置(如果已放置)
}
]]

-- ==================== 私有函数 ====================

--[[
获取玩家背包数据
@param player Player - 玩家对象
@return table|nil - 玩家的Units数组
]]
local function GetPlayerUnits(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    -- 确保Units数组存在
    if not playerData.Units then
        playerData.Units = {}
    end

    return playerData.Units
end

--[[
生成唯一实例ID
@return string - UUID格式的实例ID
]]
local function GenerateInstanceId()
    -- 使用时间戳和随机数生成简单的UUID
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

--[[
创建兵种实例数据
@param unitId string - 兵种ID
@return table|nil - 兵种实例数据,配置不存在返回nil
]]
local function CreateUnitInstance(unitId)
    -- 获取兵种配置
    local unitConfig = UnitConfig.GetUnitById(unitId)
    if not unitConfig then
        warn(GameConfig.LOG_PREFIX, "CreateUnitInstance: 无效的兵种ID", unitId)
        return nil
    end

    -- 创建实例
    local instance = {
        InstanceId = GenerateInstanceId(),
        UnitId = unitId,
        Level = unitConfig.BaseLevel,
        GridSize = unitConfig.GridSize,
        CreatedTime = os.time(),
        IsPlaced = false,
        PlacedPosition = nil,
    }

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "创建兵种实例:", unitId, "InstanceId:", instance.InstanceId)
    end

    return instance
end

--[[
初始化远程事件
@return boolean - 是否成功
]]
local function InitializeEvents()
    if not InventoryEvents then
        local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
        if eventsFolder then
            InventoryEvents = eventsFolder:FindFirstChild("InventoryEvents")
        end

        if not InventoryEvents and GameConfig.DEBUG_MODE then
            warn(GameConfig.LOG_PREFIX, "InventoryEvents未找到,客户端通知将不可用")
        end
    end
    return InventoryEvents ~= nil
end

--[[
通知客户端兵种更新
@param player Player - 玩家对象
@param unitId string - 兵种ID
@param count number - 新的数量
]]
local function NotifyClientUnitUpdate(player, unitId, count)
    if not InitializeEvents() then
        return
    end

    local unitConfig = UnitConfig.GetUnitById(unitId)
    if not unitConfig then
        return
    end

    local unitUpdatedEvent = InventoryEvents:FindFirstChild("UnitUpdated")
    if unitUpdatedEvent then
        pcall(function()
            unitUpdatedEvent:FireClient(player, unitId, unitConfig.Name, count)
        end)
    end
end

--[[
通知客户端刷新整个背包
@param player Player - 玩家对象
]]
local function NotifyClientInventoryRefresh(player)
    if not InitializeEvents() then
        return
    end

    -- 构建背包数据
    local units = GetPlayerUnits(player)
    if not units then
        return
    end

    -- 统计每种兵种的数量和实例列表
    local inventoryData = {}
    for _, instance in ipairs(units) do
        local unitId = instance.UnitId
        if not inventoryData[unitId] then
            local unitConfig = UnitConfig.GetUnitById(unitId)
            inventoryData[unitId] = {
                Name = unitConfig and unitConfig.Name or unitId,
                Count = 0,
                Instances = {}  -- 添加实例列表
            }
        end
        inventoryData[unitId].Count = inventoryData[unitId].Count + 1
        -- 只传递必要的实例信息给客户端
        table.insert(inventoryData[unitId].Instances, {
            InstanceId = instance.InstanceId,
            IsPlaced = instance.IsPlaced or false,
            GridSize = instance.GridSize,
        })
    end

    local inventoryRefreshEvent = InventoryEvents:FindFirstChild("InventoryRefresh")
    if inventoryRefreshEvent then
        pcall(function()
            inventoryRefreshEvent:FireClient(player, inventoryData)
        end)
    end
end

-- ==================== 公共接口 ====================

--[[
添加兵种到玩家背包
@param player Player - 玩家对象
@param unitId string - 兵种ID
@return boolean, string|table - 是否成功, 失败返回错误信息/成功返回实例数据
]]
function InventorySystem.AddUnit(player, unitId)
    if not player then
        return false, "玩家对象为空"
    end

    -- 验证兵种ID
    if not UnitConfig.IsValidUnit(unitId) then
        return false, "无效的兵种ID: " .. tostring(unitId)
    end

    -- 获取玩家背包
    local units = GetPlayerUnits(player)
    if not units then
        return false, "无法获取玩家数据"
    end

    -- 创建兵种实例
    local instance = CreateUnitInstance(unitId)
    if not instance then
        return false, "创建兵种实例失败"
    end

    -- 添加到背包
    table.insert(units, instance)

    -- 通知客户端更新
    local count = InventorySystem.GetUnitCountByUnitId(player, unitId)
    NotifyClientUnitUpdate(player, unitId, count)

    if GameConfig.DEBUG_MODE then
        print(string.format(
            "%s 添加兵种成功 - 玩家:%s 兵种:%s 实例ID:%s 当前数量:%d",
            GameConfig.LOG_PREFIX, player.Name, unitId, instance.InstanceId, #units
        ))
    end

    return true, instance
end

--[[
删除玩家背包中的兵种实例
@param player Player - 玩家对象
@param instanceId string - 实例ID
@return boolean, string - 是否成功, 失败返回错误信息
]]
function InventorySystem.RemoveUnit(player, instanceId)
    if not player then
        return false, "玩家对象为空"
    end

    local units = GetPlayerUnits(player)
    if not units then
        return false, "无法获取玩家数据"
    end

    -- 查找并删除实例
    for i, instance in ipairs(units) do
        if instance.InstanceId == instanceId then
            local unitId = instance.UnitId
            table.remove(units, i)

            -- 通知客户端更新
            local count = InventorySystem.GetUnitCountByUnitId(player, unitId)
            NotifyClientUnitUpdate(player, unitId, count)

            if GameConfig.DEBUG_MODE then
                print(string.format(
                    "%s 删除兵种成功 - 玩家:%s 实例ID:%s 剩余数量:%d",
                    GameConfig.LOG_PREFIX, player.Name, instanceId, #units
                ))
            end

            return true, "删除成功"
        end
    end

    return false, "找不到指定的兵种实例"
end

--[[
获取玩家所有兵种实例
@param player Player - 玩家对象
@return table|nil - 兵种实例数组
]]
function InventorySystem.GetAllUnits(player)
    if not player then
        return nil
    end

    return GetPlayerUnits(player)
end

--[[
根据实例ID获取兵种实例
@param player Player - 玩家对象
@param instanceId string - 实例ID
@return table|nil - 兵种实例数据
]]
function InventorySystem.GetUnitByInstanceId(player, instanceId)
    local units = GetPlayerUnits(player)
    if not units then
        return nil
    end

    for _, instance in ipairs(units) do
        if instance.InstanceId == instanceId then
            return instance
        end
    end

    return nil
end

--[[
获取玩家指定兵种ID的所有实例
@param player Player - 玩家对象
@param unitId string - 兵种ID
@return table - 该兵种的所有实例数组
]]
function InventorySystem.GetUnitsByUnitId(player, unitId)
    local units = GetPlayerUnits(player)
    if not units then
        return {}
    end

    local result = {}
    for _, instance in ipairs(units) do
        if instance.UnitId == unitId then
            table.insert(result, instance)
        end
    end

    return result
end

--[[
获取玩家背包中兵种总数量
@param player Player - 玩家对象
@return number - 兵种总数量
]]
function InventorySystem.GetUnitCount(player)
    local units = GetPlayerUnits(player)
    if not units then
        return 0
    end

    return #units
end

--[[
获取玩家指定兵种ID的数量
@param player Player - 玩家对象
@param unitId string - 兵种ID
@return number - 该兵种的数量
]]
function InventorySystem.GetUnitCountByUnitId(player, unitId)
    local instances = InventorySystem.GetUnitsByUnitId(player, unitId)
    return #instances
end

--[[
清空玩家背包(调试用)
@param player Player - 玩家对象
@return boolean - 是否成功
]]
function InventorySystem.ClearInventory(player)
    local units = GetPlayerUnits(player)
    if not units then
        return false
    end

    -- 清空数组
    for i = #units, 1, -1 do
        units[i] = nil
    end

    -- 通知客户端刷新背包(显示为空)
    NotifyClientInventoryRefresh(player)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "清空玩家背包:", player.Name)
    end

    return true
end

--[[
刷新客户端背包显示（供其他系统调用）
@param player Player - 玩家对象
]]
function InventorySystem.RefreshClientInventory(player)
    NotifyClientInventoryRefresh(player)
end

--[[
打印玩家背包内容(调试用)
@param player Player - 玩家对象
@return string - 背包内容的文本描述
]]
function InventorySystem.PrintInventory(player)
    local units = GetPlayerUnits(player)
    if not units or #units == 0 then
        return "背包为空"
    end

    local result = string.format("玩家 %s 的背包 (共%d个兵种):\n", player.Name, #units)

    -- 统计每种兵种的数量
    local unitCounts = {}
    for _, instance in ipairs(units) do
        local unitId = instance.UnitId
        unitCounts[unitId] = (unitCounts[unitId] or 0) + 1
    end

    -- 构建显示文本
    for unitId, count in pairs(unitCounts) do
        local unitConfig = UnitConfig.GetUnitById(unitId)
        local unitName = unitConfig and unitConfig.Name or unitId
        result = result .. string.format("  - %s x%d\n", unitName, count)
    end

    return result
end

--[[
处理客户端请求背包数据
@param player Player - 请求的玩家
]]
local function OnClientRequestInventory(player)
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "客户端请求背包数据:", player.Name)
    end

    NotifyClientInventoryRefresh(player)
end

--[[
处理客户端请求可放置的兵种实例
@param player Player
@param unitId string
]]
local function OnClientRequestUnitInstance(player, unitId)
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "客户端请求兵种实例:", player.Name, unitId)
    end

    -- 获取该兵种的第一个未放置的实例
    local instances = InventorySystem.GetUnitsByUnitId(player, unitId)
    for _, instance in ipairs(instances) do
        if not instance.IsPlaced then
            -- 通知客户端可以开始放置
            local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
            if eventsFolder then
                local placementEvents = eventsFolder:FindFirstChild("PlacementEvents")
                if placementEvents then
                    local startEvent = placementEvents:FindFirstChild("StartPlacement")
                    if startEvent then
                        -- 直接在服务端触发PlacementController的逻辑，发送实例信息
                        -- 但实际上StartPlacement应该由客户端发起，所以这里改为通知客户端
                        local inventoryEvents = eventsFolder:FindFirstChild("InventoryEvents")
                        if inventoryEvents then
                            local responseEvent = inventoryEvents:FindFirstChild("UnitInstanceResponse")
                            if responseEvent then
                                responseEvent:FireClient(player, true, {
                                    InstanceId = instance.InstanceId,
                                    UnitId = unitId,
                                    GridSize = instance.GridSize,
                                })
                                return
                            end
                        end
                    end
                end
            end
            return
        end
    end

    -- 没有可用实例
    warn(GameConfig.LOG_PREFIX, "没有可放置的", unitId, "实例")
end

--[[
初始化背包系统
连接远程事件
]]
function InventorySystem.Initialize()
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化InventorySystem...")
    end

    -- 初始化事件
    InitializeEvents()

    -- 连接客户端请求事件
    if InventoryEvents then
        local requestEvent = InventoryEvents:FindFirstChild("RequestInventory")
        if requestEvent then
            requestEvent.OnServerEvent:Connect(OnClientRequestInventory)
            if GameConfig.DEBUG_MODE then
                print(GameConfig.LOG_PREFIX, "已连接RequestInventory事件")
            end
        end

        -- 连接请求实例事件
        local requestInstanceEvent = InventoryEvents:FindFirstChild("RequestUnitInstance")
        if requestInstanceEvent then
            requestInstanceEvent.OnServerEvent:Connect(OnClientRequestUnitInstance)
            if GameConfig.DEBUG_MODE then
                print(GameConfig.LOG_PREFIX, "已连接RequestUnitInstance事件")
            end
        end
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "InventorySystem初始化完成")
    end
end

return InventorySystem
