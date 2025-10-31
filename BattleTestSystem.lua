--[[
脚本名称: BattleTestSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/BattleTestSystem
]]

--[[
战斗测试系统
职责:
1. 处理测试UI的请求
2. 在指定位置生成测试兵种
3. 管理测试战斗流程
版本: V1.5
]]

local BattleTestSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

-- 引用配置
local GameConfig = require(ServerScriptService.Config.GameConfig)
local UnitConfig = require(ServerScriptService.Config.UnitConfig)
local BattleConfig = require(ServerScriptService.Config.BattleConfig)

-- 引用系统
local CombatSystem = require(ServerScriptService.Systems.CombatSystem)
local BattleManager = require(ServerScriptService.Systems.BattleManager)

-- ==================== 私有变量 ====================

-- RemoteEvent引用
local requestBattleTestEvent = nil
local battleTestResponseEvent = nil
local cleanupBattleTestEvent = nil

-- 是否已初始化
local isInitialized = false

-- ==================== 数据结构 ====================

--[[
TestSpawnRequest = {
    Team = string,               -- "Attack" 或 "Defense"
    UnitId = string,             -- 兵种ID
    Level = number,              -- 等级 (1-3)
    Position = number,           -- 位置编号 (1-5)
}
]]

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
    if BattleConfig.DEBUG_COMBAT_LOGS then
        print(GameConfig.LOG_PREFIX, "[BattleTestSystem]", ...)
    end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
    warn(GameConfig.LOG_PREFIX, "[BattleTestSystem]", ...)
end

--[[
设置兵种碰撞组
@param unitModel Model - 兵种模型
]]
local function SetupUnitCollision(unitModel)
    -- 确保碰撞组存在
    pcall(function()
        PhysicsService:RegisterCollisionGroup(BattleConfig.UNIT_COLLISION_GROUP)
    end)

    -- 将所有BasePart设置到碰撞组
    for _, descendant in ipairs(unitModel:GetDescendants()) do
        if descendant:IsA("BasePart") then
            pcall(function()
                PhysicsService:SetPartCollisionGroup(descendant, BattleConfig.UNIT_COLLISION_GROUP)
            end)
        end
    end
end

--[[
初始化碰撞组设置
]]
local function InitializeCollisionGroups()
    -- 注册碰撞组
    pcall(function()
        PhysicsService:RegisterCollisionGroup(BattleConfig.UNIT_COLLISION_GROUP)
    end)

    pcall(function()
        PhysicsService:RegisterCollisionGroup(BattleConfig.PROJECTILE_COLLISION_GROUP)
    end)

    -- 设置碰撞关系
    -- 兵种之间根据配置决定是否碰撞
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(
            BattleConfig.UNIT_COLLISION_GROUP,
            BattleConfig.UNIT_COLLISION_GROUP,
            BattleConfig.ENABLE_UNIT_COLLISION
        )
    end)

    -- 弹道与兵种之间可以碰撞（用于伤害检测）
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(
            BattleConfig.PROJECTILE_COLLISION_GROUP,
            BattleConfig.UNIT_COLLISION_GROUP,
            true
        )
    end)

    -- 弹道之间不碰撞
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(
            BattleConfig.PROJECTILE_COLLISION_GROUP,
            BattleConfig.PROJECTILE_COLLISION_GROUP,
            false
        )
    end)

    DebugLog("碰撞组初始化完成")
end

--[[
获取生成位置
@param team string - 队伍 ("Attack" 或 "Defense")
@param positionIndex number - 位置编号 (1-5)
@return Vector3|nil - 位置坐标
]]
local function GetSpawnPosition(team, positionIndex)
    local battleTestFolder = Workspace:FindFirstChild(BattleConfig.BATTLE_TEST_FOLDER)

    if not battleTestFolder then
        WarnLog("找不到BattleTest文件夹")
        return nil
    end

    local teamFolder = nil

    if team == BattleConfig.Team.ATTACK then
        teamFolder = battleTestFolder:FindFirstChild(BattleConfig.ATTACK_FOLDER)
    elseif team == BattleConfig.Team.DEFENSE then
        teamFolder = battleTestFolder:FindFirstChild(BattleConfig.DEFENSE_FOLDER)
    end

    if not teamFolder then
        WarnLog("找不到队伍文件夹:", team)
        return nil
    end

    local positionName = BattleConfig.POSITION_PREFIX .. tostring(positionIndex)
    local positionPart = teamFolder:FindFirstChild(positionName)

    if not positionPart then
        WarnLog("找不到生成位置:", positionName)
        return nil
    end

    return positionPart.Position
end

--[[
根据路径查找模型的辅助函数
@param parent Instance - 查找的起点
@param path string - 路径 (如 "Role/Basic/Noob")
@return Instance|nil - 找到的实例
]]
local function FindModelByPath(parent, path)
    local parts = string.split(path, "/")
    local current = parent

    for _, part in ipairs(parts) do
        if not current then
            return nil
        end
        current = current:FindFirstChild(part)
    end

    return current
end

--[[
生成测试兵种
@param unitId string - 兵种ID
@param level number - 等级
@param team string - 队伍
@param position Vector3 - 生成位置
@param battleId number - 战斗ID
@return Model|nil - 生成的兵种模型
]]
local function SpawnTestUnit(unitId, level, team, position, battleId)
    -- 验证兵种ID
    if not UnitConfig.IsValidUnit(unitId) then
        WarnLog("无效的兵种ID:", unitId)
        return nil
    end

    -- 获取兵种配置
    local unitData = UnitConfig.GetUnitById(unitId)

    -- 获取模型
    local modelPath = unitData.ModelPath
    local replicatedStorage = game:GetService("ReplicatedStorage")

    -- 使用路径查找模型
    local modelTemplate = FindModelByPath(replicatedStorage, modelPath)

    if not modelTemplate then
        WarnLog("找不到兵种模型:", modelPath)
        DebugLog("已尝试搜索路径: ReplicatedStorage/" .. modelPath)
        return nil
    end

    -- 复制模型
    local unitModel = modelTemplate:Clone()
    unitModel.Parent = Workspace

    -- 设置位置
    if unitModel.PrimaryPart then
        unitModel:SetPrimaryPartCFrame(CFrame.new(position))
    elseif unitModel:FindFirstChild("HumanoidRootPart") then
        unitModel.HumanoidRootPart.CFrame = CFrame.new(position)
    end

    -- 初始化战斗状态
    CombatSystem.InitializeUnit(unitModel, unitId, level, team, battleId)

    -- 设置碰撞组
    SetupUnitCollision(unitModel)

    -- 更新等级显示
    local head = unitModel:FindFirstChild("Head")
    if head then
        local billboard = head:FindFirstChild("BillboardGui")
        if billboard then
            local textLabel = billboard:FindFirstChild("TextLabel")
            if textLabel then
                if level >= UnitConfig.MAX_LEVEL then
                    textLabel.Text = "Lv.Max"
                else
                    textLabel.Text = "Lv." .. tostring(level)
                end
            end
        end
    end

    DebugLog(string.format("生成测试兵种: %s Lv.%d [%s]", unitId, level, team))

    return unitModel
end

-- ==================== 公共接口 ====================

--[[
初始化战斗测试系统
@return boolean - 是否初始化成功
]]
function BattleTestSystem.Initialize()
    if isInitialized then
        WarnLog("战斗测试系统已经初始化过了")
        return true
    end

    DebugLog("正在初始化战斗测试系统...")

    -- 初始化碰撞组设置
    InitializeCollisionGroups()

    -- 获取RemoteEvent
    local eventsFolder = ReplicatedStorage:WaitForChild("Events")
    local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")

    if not battleEventsFolder then
        WarnLog("未找到BattleEvents文件夹")
        return false
    end

    requestBattleTestEvent = battleEventsFolder:FindFirstChild("RequestBattleTest")
    battleTestResponseEvent = battleEventsFolder:FindFirstChild("BattleTestResponse")
    cleanupBattleTestEvent = battleEventsFolder:FindFirstChild("CleanupBattleTest")

    if not requestBattleTestEvent or not battleTestResponseEvent then
        WarnLog("未找到BattleTest相关事件")
        return false
    end

    -- 如果清理事件不存在，创建它
    if not cleanupBattleTestEvent then
        DebugLog("清理事件不存在，已创建")
        cleanupBattleTestEvent = Instance.new("RemoteEvent")
        cleanupBattleTestEvent.Name = "CleanupBattleTest"
        cleanupBattleTestEvent.Parent = battleEventsFolder
    end

    -- 连接事件
    requestBattleTestEvent.OnServerEvent:Connect(function(player, attackUnitsData, defenseUnitsData)
        BattleTestSystem.HandleBattleTestRequest(player, attackUnitsData, defenseUnitsData)
    end)

    -- 连接清理事件
    cleanupBattleTestEvent.OnServerEvent:Connect(function(player)
        BattleTestSystem.HandleCleanupRequest(player)
    end)

    isInitialized = true

    DebugLog("战斗测试系统初始化完成")
    return true
end

--[[
处理战斗测试请求
@param player Player - 请求的玩家
@param attackUnitsData table - 攻击方兵种数据列表
@param defenseUnitsData table - 防守方兵种数据列表
]]
function BattleTestSystem.HandleBattleTestRequest(player, attackUnitsData, defenseUnitsData)
    DebugLog(string.format("收到战斗测试请求: 玩家%s", player.Name))

    -- 验证参数
    if not attackUnitsData or not defenseUnitsData then
        battleTestResponseEvent:FireClient(player, false, nil, "参数无效")
        return
    end

    -- 创建战斗实例
    local battleId = BattleManager.CreateBattle(player.UserId, {}, {})

    if not battleId then
        battleTestResponseEvent:FireClient(player, false, nil, "无法创建战斗实例")
        return
    end

    local attackUnits = {}
    local defenseUnits = {}

    -- 生成攻击方兵种
    for _, unitData in ipairs(attackUnitsData) do
        local position = GetSpawnPosition(BattleConfig.Team.ATTACK, unitData.Position)

        if position then
            local unitModel = SpawnTestUnit(unitData.UnitId, unitData.Level, BattleConfig.Team.ATTACK, position, battleId)

            if unitModel then
                table.insert(attackUnits, unitModel)
                BattleManager.AddAttackUnit(battleId, unitModel)
            end
        end
    end

    -- 生成防守方兵种
    for _, unitData in ipairs(defenseUnitsData) do
        local position = GetSpawnPosition(BattleConfig.Team.DEFENSE, unitData.Position)

        if position then
            local unitModel = SpawnTestUnit(unitData.UnitId, unitData.Level, BattleConfig.Team.DEFENSE, position, battleId)

            if unitModel then
                table.insert(defenseUnits, unitModel)
                BattleManager.AddDefenseUnit(battleId, unitModel)
            end
        end
    end

    -- 检查是否成功生成兵种
    if #attackUnits == 0 and #defenseUnits == 0 then
        BattleManager.CleanupBattle(battleId)
        battleTestResponseEvent:FireClient(player, false, nil, "未能生成任何兵种")
        return
    end

    -- 开始战斗
    local success = BattleManager.StartBattle(battleId)

    if success then
        DebugLog(string.format("战斗测试开始: BattleId=%d", battleId))
        battleTestResponseEvent:FireClient(player, true, battleId, "战斗开始")
    else
        BattleManager.CleanupBattle(battleId)
        battleTestResponseEvent:FireClient(player, false, nil, "战斗启动失败")
    end
end

--[[
生成单个测试兵种(用于UI单独生成)
@param player Player - 请求的玩家
@param unitId string - 兵种ID
@param level number - 等级
@param team string - 队伍
@param positionIndex number - 位置编号
@return boolean - 是否成功
]]
function BattleTestSystem.SpawnSingleTestUnit(player, unitId, level, team, positionIndex)
    -- 获取或创建玩家的战斗实例
    local battle = BattleManager.GetPlayerBattle(player.UserId)
    local battleId = nil

    if not battle then
        -- 创建新战斗实例
        battleId = BattleManager.CreateBattle(player.UserId, {}, {})

        if not battleId then
            return false
        end
    else
        battleId = battle.BattleId
    end

    -- 获取生成位置
    local position = GetSpawnPosition(team, positionIndex)

    if not position then
        return false
    end

    -- 生成兵种
    local unitModel = SpawnTestUnit(unitId, level, team, position, battleId)

    if not unitModel then
        return false
    end

    -- 添加到战斗实例
    if team == BattleConfig.Team.ATTACK then
        BattleManager.AddAttackUnit(battleId, unitModel)
    else
        BattleManager.AddDefenseUnit(battleId, unitModel)
    end

    return true
end

--[[
处理清理请求
@param player Player - 请求的玩家
]]
function BattleTestSystem.HandleCleanupRequest(player)
    DebugLog(string.format("收到清理请求: 玩家%s", player.Name))

    -- 清理该玩家的所有战斗
    local battle = BattleManager.GetPlayerBattle(player.UserId)

    if battle then
        BattleManager.CleanupBattle(battle.BattleId)
        DebugLog(string.format("已清理玩家%s的战斗: BattleId=%d", player.Name, battle.BattleId))
    else
        DebugLog(string.format("玩家%s没有活跃的战斗", player.Name))
    end
end

return BattleTestSystem
