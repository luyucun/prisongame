--[[
脚本名称: MergeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/MergeSystem
]]

--[[
兵种合成系统模块
职责:
1. 处理两个相同兵种的合成
2. 验证合成条件（等级、UnitId）
3. 生成更高等级的兵种
4. 同步合成结果到客户端
版本: V1.4
]]

local MergeSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 引用模块
local GameConfig = require(ServerScriptService.Config.GameConfig)
local UnitConfig = require(ServerScriptService.Config.UnitConfig)
local InventorySystem = require(ServerScriptService.Systems.InventorySystem)
local PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)

-- 远程事件(延迟获取)
local MergeEvents = nil

-- ==================== 私有函数 ====================

--[[
初始化远程事件
@return boolean - 是否成功
]]
local function InitializeEvents()
    if not MergeEvents then
        local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
        if eventsFolder then
            MergeEvents = eventsFolder:FindFirstChild("MergeEvents")
        end

        if not MergeEvents and GameConfig.DEBUG_MODE then
            warn(GameConfig.LOG_PREFIX, "MergeEvents未找到!")
        end
    end
    return MergeEvents ~= nil
end

-- ==================== 公共接口 ====================

--[[
验证两个兵种是否可以合成
@param player Player
@param instanceIdA string - 兵种A的实例ID
@param instanceIdB string - 兵种B的实例ID
@return boolean, string - 是否可以合成, 失败原因
]]
function MergeSystem.CanMerge(player, instanceIdA, instanceIdB)
    -- 1. 检查两个实例ID不能相同
    if instanceIdA == instanceIdB then
        return false, "不能合成相同的兵种"
    end

    -- 2. 获取两个兵种实例
    local unitA = InventorySystem.GetUnitByInstanceId(player, instanceIdA)
    local unitB = InventorySystem.GetUnitByInstanceId(player, instanceIdB)

    if not unitA then
        return false, "兵种A不存在"
    end

    if not unitB then
        return false, "兵种B不存在"
    end

    -- 3. 检查两个兵种是否都已放置
    if not unitA.IsPlaced then
        return false, "兵种A未放置"
    end

    if not unitB.IsPlaced then
        return false, "兵种B未放置"
    end

    -- 4. 检查UnitId是否相同
    if unitA.UnitId ~= unitB.UnitId then
        return false, "兵种类型不同，无法合成"
    end

    -- 5. 检查等级是否相同
    if unitA.Level ~= unitB.Level then
        return false, "兵种等级不同，无法合成"
    end

    -- 6. 检查是否已经达到最高等级
    if unitA.Level >= UnitConfig.MAX_LEVEL then
        return false, "已达到最高等级，无法合成"
    end

    return true, "可以合成"
end

--[[
合成两个兵种
@param player Player
@param instanceIdA string - 要拖动的兵种实例ID
@param instanceIdB string - 目标兵种实例ID
@return boolean, string, table|nil - 是否成功, 消息, 新兵种实例数据
]]
function MergeSystem.MergeUnits(player, instanceIdA, instanceIdB)
    -- 1. 验证是否可以合成
    local canMerge, message = MergeSystem.CanMerge(player, instanceIdA, instanceIdB)
    if not canMerge then
        return false, message, nil
    end

    -- 2. 获取兵种实例
    local unitA = InventorySystem.GetUnitByInstanceId(player, instanceIdA)
    local unitB = InventorySystem.GetUnitByInstanceId(player, instanceIdB)

    -- 3. 记录位置（使用B的位置）
    local mergePosition = unitB.PlacedPosition
    local newLevel = unitA.Level + 1

    if GameConfig.DEBUG_MODE then
        print(string.format(
            "%s 开始合成 - 玩家:%s UnitId:%s 等级:%d -> %d",
            GameConfig.LOG_PREFIX, player.Name, unitA.UnitId, unitA.Level, newLevel
        ))
    end

    -- 4. 先创建新兵种（确保创建成功后再移除旧兵种，避免数据丢失）
    local success, newInstance = InventorySystem.AddUnit(player, unitA.UnitId)

    if not success then
        warn(GameConfig.LOG_PREFIX, "创建合成兵种失败:", newInstance)
        return false, "创建新兵种失败", nil
    end

    -- 5. 更新新兵种的等级
    newInstance.Level = newLevel

    -- 6. 移除两个旧兵种（从背包和场地移除）
    PlacementSystem.RemovePlacedUnit(player, instanceIdA)
    PlacementSystem.RemovePlacedUnit(player, instanceIdB)
    InventorySystem.RemoveUnit(player, instanceIdA)
    InventorySystem.RemoveUnit(player, instanceIdB)

    -- 7. 立即放置新兵种到原来的位置
    local placeSuccess, placeMessage = PlacementSystem.PlaceUnit(player, newInstance.InstanceId, mergePosition)

    if not placeSuccess then
        warn(GameConfig.LOG_PREFIX, "放置合成兵种失败:", placeMessage)
        -- 如果放置失败，兵种会留在背包中
    end

    if GameConfig.DEBUG_MODE then
        print(string.format(
            "%s 合成成功 - 新兵种ID:%s 等级:%d",
            GameConfig.LOG_PREFIX, newInstance.InstanceId, newLevel
        ))
    end

    return true, "合成成功", {
        InstanceId = newInstance.InstanceId,
        UnitId = newInstance.UnitId,
        Level = newLevel,
        Position = mergePosition,
    }
end

-- ==================== 远程事件处理 ====================

--[[
处理客户端请求合成
@param player Player
@param instanceIdA string - 拖动的兵种
@param instanceIdB string - 目标兵种
]]
local function OnRequestMerge(player, instanceIdA, instanceIdB)
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "收到合成请求:", player.Name, instanceIdA, "->", instanceIdB)
    end

    -- 执行合成
    local success, message, newUnitData = MergeSystem.MergeUnits(player, instanceIdA, instanceIdB)

    -- 通知客户端结果
    if InitializeEvents() then
        local responseEvent = MergeEvents:FindFirstChild("MergeResponse")
        if responseEvent then
            responseEvent:FireClient(player, success, message, newUnitData)
        end
    end
end

--[[
初始化合成系统
]]
function MergeSystem.Initialize()
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化MergeSystem...")
    end

    -- 初始化事件
    if not InitializeEvents() then
        warn(GameConfig.LOG_PREFIX, "MergeEvents未找到，合成系统将不可用!")
        return false
    end

    -- 连接远程事件
    local requestEvent = MergeEvents:FindFirstChild("RequestMerge")
    if requestEvent then
        requestEvent.OnServerEvent:Connect(OnRequestMerge)
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "已连接RequestMerge事件")
        end
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "MergeSystem初始化完成")
    end

    return true
end

return MergeSystem
