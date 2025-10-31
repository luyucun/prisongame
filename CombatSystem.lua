--[[
脚本名称: CombatSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/CombatSystem
]]

--[[
战斗系统
职责:
1. 管理兵种的战斗状态(血量、是否存活)
2. 处理伤害计算
3. 处理死亡流程
4. 发送死亡通知给攻击者
版本: V1.5
]]

local CombatSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ServerScriptService.Config.GameConfig)
local UnitConfig = require(ServerScriptService.Config.UnitConfig)
local BattleConfig = require(ServerScriptService.Config.BattleConfig)

-- ==================== 私有变量 ====================

-- 存储所有兵种的战斗状态 [unitModel] = UnitCombatState
local unitStates = {}

-- 死亡事件
local unitDeathEvent = nil

-- ==================== 数据结构 ====================

--[[
UnitCombatState = {
    UnitInstance = Model,        -- 兵种模型实例
    UnitId = string,             -- 兵种ID (如"Noob")
    Level = number,              -- 等级 (1-3)
    Team = string,               -- 阵营: "Attack" 或 "Defense"
    BattleId = number,           -- 所属战斗ID

    -- 战斗属性
    MaxHealth = number,          -- 最大生命值
    CurrentHealth = number,      -- 当前生命值
    Attack = number,             -- 攻击力
    AttackSpeed = number,        -- 攻击速度(秒/次)
    AttackRange = number,        -- 攻击距离
    MoveSpeed = number,          -- 移动速度

    -- 战斗状态
    IsAlive = boolean,           -- 是否存活
    CurrentTarget = Model,       -- 当前攻击目标
    LastAttackTime = number,     -- 上次攻击时间
    State = string,              -- 状态: "Idle", "Moving", "Attacking", "Dead"
}
]]

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
    if BattleConfig.DEBUG_COMBAT_LOGS then
        print(GameConfig.LOG_PREFIX, "[CombatSystem]", ...)
    end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
    warn(GameConfig.LOG_PREFIX, "[CombatSystem]", ...)
end

-- ==================== 公共接口 ====================

--[[
初始化战斗系统
@return boolean - 是否初始化成功
]]
function CombatSystem.Initialize()
    DebugLog("正在初始化战斗系统...")

    -- 获取或创建死亡事件
    local eventsFolder = ReplicatedStorage:WaitForChild("Events")
    local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")

    if not battleEventsFolder then
        WarnLog("未找到BattleEvents文件夹,死亡通知将无法工作")
        return false
    end

    unitDeathEvent = battleEventsFolder:FindFirstChild("UnitDeath")

    if not unitDeathEvent then
        WarnLog("未找到UnitDeath事件,死亡通知将无法工作")
        return false
    end

    DebugLog("战斗系统初始化完成")
    return true
end

--[[
初始化兵种战斗状态
@param unitModel Model - 兵种模型实例
@param unitId string - 兵种ID
@param level number - 等级
@param team string - 阵营("Attack"或"Defense")
@param battleId number - 所属战斗ID
@return boolean - 是否初始化成功
]]
function CombatSystem.InitializeUnit(unitModel, unitId, level, team, battleId)
    if not unitModel or not unitModel:IsA("Model") then
        WarnLog("InitializeUnit失败: unitModel无效")
        return false
    end

    if not UnitConfig.IsValidUnit(unitId) then
        WarnLog("InitializeUnit失败: 无效的unitId:", unitId)
        return false
    end

    -- 计算战斗属性
    local maxHealth = UnitConfig.CalculateHealth(unitId, level)
    local attack = UnitConfig.CalculateAttack(unitId, level)
    local attackSpeed = UnitConfig.GetAttackSpeed(unitId)
    local attackRange = UnitConfig.GetAttackRange(unitId)
    local moveSpeed = UnitConfig.GetMoveSpeed(unitId)

    -- 创建战斗状态
    local combatState = {
        UnitInstance = unitModel,
        UnitId = unitId,
        Level = level,
        Team = team,
        BattleId = battleId,

        MaxHealth = maxHealth,
        CurrentHealth = maxHealth,
        Attack = attack,
        AttackSpeed = attackSpeed,
        AttackRange = attackRange,
        MoveSpeed = moveSpeed,

        IsAlive = true,
        CurrentTarget = nil,
        LastAttackTime = 0,
        State = BattleConfig.AIState.IDLE,
    }

    -- 存储状态
    unitStates[unitModel] = combatState

    DebugLog(string.format("初始化兵种战斗状态: %s Lv.%d [%s] HP:%d ATK:%d",
        unitId, level, team, maxHealth, attack))

    return true
end

--[[
获取兵种战斗状态
@param unitModel Model - 兵种模型实例
@return table|nil - 战斗状态,不存在返回nil
]]
function CombatSystem.GetUnitState(unitModel)
    return unitStates[unitModel]
end

--[[
检查兵种是否存活
@param unitModel Model - 兵种模型实例
@return boolean - 是否存活
]]
function CombatSystem.IsUnitAlive(unitModel)
    local state = unitStates[unitModel]
    if not state then
        return false
    end
    return state.IsAlive and state.CurrentHealth > 0
end

--[[
兵种受到伤害
@param unitModel Model - 受伤的兵种模型
@param damage number - 伤害值
@param attacker Model - 攻击者模型(可选)
@return boolean - 是否造成了伤害
]]
function CombatSystem.TakeDamage(unitModel, damage, attacker)
    local state = unitStates[unitModel]

    if not state then
        WarnLog("TakeDamage失败: 兵种未初始化")
        return false
    end

    if not state.IsAlive then
        return false
    end

    -- 扣除血量
    state.CurrentHealth = state.CurrentHealth - damage

    DebugLog(string.format("%s受到%d伤害, 剩余HP:%d/%d",
        state.UnitId, damage, state.CurrentHealth, state.MaxHealth))

    -- 检查是否死亡
    if state.CurrentHealth <= 0 then
        state.CurrentHealth = 0
        CombatSystem.KillUnit(unitModel, attacker)
    end

    return true
end

--[[
治疗兵种(预留接口)
@param unitModel Model - 兵种模型
@param amount number - 治疗量
@return boolean - 是否治疗成功
]]
function CombatSystem.Heal(unitModel, amount)
    local state = unitStates[unitModel]

    if not state then
        return false
    end

    if not state.IsAlive then
        return false
    end

    state.CurrentHealth = math.min(state.CurrentHealth + amount, state.MaxHealth)

    DebugLog(string.format("%s恢复%d生命值, 当前HP:%d/%d",
        state.UnitId, amount, state.CurrentHealth, state.MaxHealth))

    return true
end

--[[
杀死兵种
@param unitModel Model - 兵种模型
@param killer Model - 击杀者模型(可选)
]]
function CombatSystem.KillUnit(unitModel, killer)
    local state = unitStates[unitModel]

    if not state then
        WarnLog("KillUnit失败: 兵种未初始化")
        return
    end

    if not state.IsAlive then
        return  -- 已经死亡,不重复处理
    end

    -- 标记为死亡
    state.IsAlive = false
    state.State = BattleConfig.AIState.DEAD
    state.CurrentHealth = 0

    DebugLog(string.format("%s [%s] 已死亡", state.UnitId, state.Team))

    -- 先停止AI，避免死亡单位的AI继续运行
    local UnitAI = require(ServerScriptService.Systems.UnitAI)
    UnitAI.StopAI(unitModel)

    -- 立即从状态表中移除，避免其他系统访问死亡单位
    local battleId = state.BattleId
    unitStates[unitModel] = nil

    -- 触发死亡事件(通知攻击者)
    if unitDeathEvent then
        unitDeathEvent:Fire(unitModel, killer, battleId)
    end

    -- 播放死亡动画(暂时跳过)
    -- TODO: 播放死亡动画

    -- 延迟移除模型(让死亡动画有时间播放)
    task.delay(0.5, function()
        if unitModel and unitModel.Parent then
            unitModel:Destroy()
        end
    end)
end

--[[
设置兵种当前目标
@param unitModel Model - 兵种模型
@param target Model - 目标模型
]]
function CombatSystem.SetTarget(unitModel, target)
    local state = unitStates[unitModel]

    if not state then
        return
    end

    state.CurrentTarget = target
end

--[[
获取兵种当前目标
@param unitModel Model - 兵种模型
@return Model|nil - 目标模型
]]
function CombatSystem.GetTarget(unitModel)
    local state = unitStates[unitModel]

    if not state then
        return nil
    end

    return state.CurrentTarget
end

--[[
设置兵种AI状态
@param unitModel Model - 兵种模型
@param aiState string - AI状态
]]
function CombatSystem.SetAIState(unitModel, aiState)
    local state = unitStates[unitModel]

    if not state then
        return
    end

    state.State = aiState
end

--[[
获取兵种AI状态
@param unitModel Model - 兵种模型
@return string|nil - AI状态
]]
function CombatSystem.GetAIState(unitModel)
    local state = unitStates[unitModel]

    if not state then
        return nil
    end

    return state.State
end

--[[
更新上次攻击时间
@param unitModel Model - 兵种模型
@param time number - 时间戳
]]
function CombatSystem.UpdateLastAttackTime(unitModel, time)
    local state = unitStates[unitModel]

    if not state then
        return
    end

    state.LastAttackTime = time
end

--[[
检查是否可以攻击(冷却时间)
@param unitModel Model - 兵种模型
@return boolean - 是否可以攻击
]]
function CombatSystem.CanAttack(unitModel)
    local state = unitStates[unitModel]

    if not state then
        return false
    end

    if not state.IsAlive then
        return false
    end

    local currentTime = tick()
    return (currentTime - state.LastAttackTime) >= state.AttackSpeed
end

--[[
清理兵种战斗状态
@param unitModel Model - 兵种模型
]]
function CombatSystem.ClearUnitState(unitModel)
    unitStates[unitModel] = nil
end

--[[
清理战斗的所有兵种状态
@param battleId number - 战斗ID
]]
function CombatSystem.ClearBattleUnits(battleId)
    for unitModel, state in pairs(unitStates) do
        if state.BattleId == battleId then
            unitStates[unitModel] = nil
        end
    end

    DebugLog("已清理战斗", battleId, "的所有兵种状态")
end

--[[
获取所有战斗状态
@return table - 所有兵种状态
]]
function CombatSystem.GetAllUnitStates()
    return unitStates
end

return CombatSystem
