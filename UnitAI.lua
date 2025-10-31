--[[
脚本名称: UnitAI
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitAI
]]

--[[
兵种AI系统
职责:
1. 目标寻找与锁定
2. 移动与寻路
3. 攻击判定与执行
4. AI状态机管理
版本: V1.5
]]

local UnitAI = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引用配置
local GameConfig = require(ServerScriptService.Config.GameConfig)
local UnitConfig = require(ServerScriptService.Config.UnitConfig)
local BattleConfig = require(ServerScriptService.Config.BattleConfig)

-- 引用系统
local CombatSystem = require(ServerScriptService.Systems.CombatSystem)
local ProjectileSystem = require(ServerScriptService.Systems.ProjectileSystem)

-- ==================== 私有变量 ====================

-- 存储所有AI实例 [unitModel] = AIData
local activeAIs = {}

-- AI更新连接
local updateConnection = nil

-- 死亡事件连接
local deathEventConnection = nil

-- 存储武器接触连接 [weaponPart] = {connection, target, attacker, damage}
local weaponTouchConnections = {}

-- 存储最近攻击时间，防止连续触发 [weaponPart] = lastHitTime
local weaponCooldowns = {}

-- ==================== 数据结构 ====================

--[[
AIData = {
    UnitModel = Model,           -- 兵种模型
    Humanoid = Humanoid,         -- Humanoid对象
    HumanoidRootPart = Part,     -- HumanoidRootPart
    IsActive = boolean,          -- AI是否激活
    LastUpdateTime = number,     -- 上次更新时间
    PathfindingTimeout = number, -- 寻路超时时间
}
]]

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
    if BattleConfig.DEBUG_AI_LOGS then
        print(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
    end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
    warn(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
end

--[[
设置武器接触检测（近战）
@param unitModel Model - 兵种模型
@param weaponPart Part - 武器部件
@param target Model - 目标
@param damage number - 伤害值
]]
local function SetupWeaponTouch(unitModel, weaponPart, target, damage)
    -- 如果已经有连接，先断开
    if weaponTouchConnections[weaponPart] then
        if weaponTouchConnections[weaponPart].connection then
            weaponTouchConnections[weaponPart].connection:Disconnect()
        end
    end

    -- 连接Touched事件
    local connection = weaponPart.Touched:Connect(function(otherPart)
        -- 检查冷却时间（防止连续触发）
        local currentTime = tick()
        local lastHitTime = weaponCooldowns[weaponPart] or 0

        if currentTime - lastHitTime < BattleConfig.MELEE_DAMAGE_COOLDOWN then
            return
        end

        -- 检查是否击中目标
        if otherPart.Parent == target or otherPart == target then
            -- 检查目标是否还存活
            if not CombatSystem.IsUnitAlive(target) then
                return
            end

            -- 造成伤害
            CombatSystem.TakeDamage(target, damage, unitModel)

            -- 更新冷却时间
            weaponCooldowns[weaponPart] = currentTime

            DebugLog(string.format("武器接触命中! 造成%d伤害", damage))
        end
    end)

    -- 存储连接信息
    weaponTouchConnections[weaponPart] = {
        connection = connection,
        target = target,
        attacker = unitModel,
        damage = damage,
    }
end

--[[
清除武器接触检测
@param weaponPart Part - 武器部件
]]
local function ClearWeaponTouch(weaponPart)
    if weaponTouchConnections[weaponPart] then
        if weaponTouchConnections[weaponPart].connection then
            weaponTouchConnections[weaponPart].connection:Disconnect()
        end
        weaponTouchConnections[weaponPart] = nil
    end

    weaponCooldowns[weaponPart] = nil
end

--[[
播放移动动画
@param humanoid Humanoid - Humanoid对象
@param unitId string - 兵种ID
]]
local function PlayMoveAnimation(humanoid, unitId)
    -- 参数验证
    if not humanoid or not unitId then
        return nil
    end

    -- 从配置表获取移动动画ID
    local animationId = UnitConfig.GetMoveAnimationId(unitId)

    -- 如果animationId为空或nil，则不播放自定义动画
    if not animationId or animationId == "" or animationId == "0" then
        DebugLog("没有配置移动动画ID，使用Humanoid默认移动")
        return nil
    end

    -- 检查animationId是否为有效的数字格式
    if not tonumber(animationId) then
        WarnLog(string.format("无效的移动动画ID格式: %s (应为纯数字)", animationId))
        return nil
    end

    -- 获取Animator
    local animator = humanoid:FindFirstChild("Animator")

    if not animator then
        WarnLog("找不到Animator对象")
        return nil
    end

    -- 创建Animation实例
    local animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. animationId

    -- 使用pcall保护加载过程
    local success, animationTrack = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if not success or not animationTrack then
        WarnLog(string.format("无法加载移动动画: %s", animationId))
        animation:Destroy()
        return nil
    end

    -- 播放动画
    local playSuccess, playError = pcall(function()
        animationTrack:Play()
    end)

    if not playSuccess then
        WarnLog(string.format("无法播放移动动画: %s, 错误: %s", animationId, playError))
        animation:Destroy()
        return nil
    end

    DebugLog(string.format("播放移动动画: %s", animationId))

    return animationTrack
end

--[[
播放攻击动画
@param humanoid Humanoid - Humanoid对象
@param animationId string - 动画ID
@return Animator|nil - 动画对象 (如果播放成功)
]]
local function PlayAttackAnimation(humanoid, animationId)
    -- 参数验证
    if not humanoid then
        return nil
    end

    -- 如果animationId为空或nil，则不播放自定义动画
    -- Roblox标准Rig的Humanoid会有默认的攻击动画
    if not animationId or animationId == "" or animationId == "0" then
        DebugLog("没有配置攻击动画ID，使用默认动作")
        return nil
    end

    -- 检查animationId是否为有效的数字格式
    if not tonumber(animationId) then
        WarnLog(string.format("无效的动画ID格式: %s (应为纯数字)", animationId))
        return nil
    end

    -- 获取Animator
    local animator = humanoid:FindFirstChild("Animator")

    if not animator then
        -- 如果找不到Animator，从Parent的所有子元素查找
        animator = humanoid.Parent:FindFirstChildOfClass("Animator")
    end

    if not animator then
        WarnLog("找不到Animator对象")
        return nil
    end

    -- 创建Animation实例
    local animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. animationId

    -- 使用pcall保护加载过程，防止错误导致AI更新失败
    local success, animationTrack = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if not success or not animationTrack then
        WarnLog(string.format("无法加载动画: %s", animationId))
        animation:Destroy()
        return nil
    end

    -- 播放动画
    local playSuccess, playError = pcall(function()
        animationTrack:Play()
    end)

    if not playSuccess then
        WarnLog(string.format("无法播放动画: %s, 错误: %s", animationId, playError))
        animation:Destroy()
        return nil
    end

    DebugLog(string.format("播放攻击动画: %s", animationId))

    -- 动画播放完毕后清理
    task.delay(animationTrack.Length + 0.1, function()
        if animation and animation.Parent then
            animation:Destroy()
        end
    end)

    return animationTrack
end

--[[
计算两个模型之间的距离
@param model1 Model - 模型1
@param model2 Model - 模型2
@return number - 距离
]]
local function GetDistance(model1, model2)
    local part1 = model1:FindFirstChild("HumanoidRootPart") or model1.PrimaryPart
    local part2 = model2:FindFirstChild("HumanoidRootPart") or model2.PrimaryPart

    if not part1 or not part2 then
        return math.huge
    end

    return (part1.Position - part2.Position).Magnitude
end

--[[
更新所有AI
]]
local function UpdateAllAIs()
    local currentTime = tick()

    for unitModel, aiData in pairs(activeAIs) do
        -- 检查单位是否还存活
        if not CombatSystem.IsUnitAlive(unitModel) then
            continue
        end

        -- 检查是否激活
        if not aiData.IsActive then
            continue
        end

        -- 更新AI
        local success, err = pcall(function()
            UnitAI.UpdateAI(unitModel, aiData)
        end)

        if not success then
            WarnLog("AI更新失败:", err)
        end

        aiData.LastUpdateTime = currentTime
    end
end

-- ==================== 公共接口 ====================

--[[
初始化AI系统
@return boolean - 是否初始化成功
]]
function UnitAI.Initialize()
    if isInitialized then
        WarnLog("AI系统已经初始化过了")
        return true
    end

    DebugLog("正在初始化AI系统...")

    -- 连接更新循环
    updateConnection = RunService.Heartbeat:Connect(function()
        UpdateAllAIs()
    end)

    -- 连接死亡事件
    local eventsFolder = ReplicatedStorage:WaitForChild("Events")
    local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")

    if battleEventsFolder then
        local unitDeathEvent = battleEventsFolder:FindFirstChild("UnitDeath")

        if unitDeathEvent then
            deathEventConnection = unitDeathEvent.Event:Connect(function(deadUnit, killer, battleId)
                UnitAI.OnTargetDeath(deadUnit, battleId)
            end)
        end
    end

    isInitialized = true

    DebugLog("AI系统初始化完成")
    return true
end

--[[
关闭AI系统
]]
function UnitAI.Shutdown()
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end

    if deathEventConnection then
        deathEventConnection:Disconnect()
        deathEventConnection = nil
    end

    activeAIs = {}
    isInitialized = false

    DebugLog("AI系统已关闭")
end

--[[
启动兵种AI
@param unitModel Model - 兵种模型
@return boolean - 是否启动成功
]]
function UnitAI.StartAI(unitModel)
    if not unitModel or not unitModel:IsA("Model") then
        WarnLog("StartAI失败: unitModel无效")
        return false
    end

    local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
    local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

    if not humanoid or not rootPart then
        WarnLog("StartAI失败: 找不到Humanoid或HumanoidRootPart")
        return false
    end

    -- 创建AI数据
    local aiData = {
        UnitModel = unitModel,
        Humanoid = humanoid,
        HumanoidRootPart = rootPart,
        IsActive = true,
        LastUpdateTime = 0,
        PathfindingTimeout = 0,
    }

    activeAIs[unitModel] = aiData

    -- 设置移动速度
    local state = CombatSystem.GetUnitState(unitModel)
    if state then
        humanoid.WalkSpeed = state.MoveSpeed
    end

    local unitId = state and state.UnitId or "Unknown"
    DebugLog(string.format("启动AI: %s", unitId))

    return true
end

--[[
停止兵种AI
@param unitModel Model - 兵种模型
]]
function UnitAI.StopAI(unitModel)
    local aiData = activeAIs[unitModel]

    if aiData then
        aiData.IsActive = false

        -- 停止移动
        if aiData.Humanoid and aiData.HumanoidRootPart then
            aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
        end

        -- 清理武器接触连接
        local state = CombatSystem.GetUnitState(unitModel)
        if state then
            local weaponName = UnitConfig.GetWeaponName(state.UnitId)
            local weaponPart = unitModel:FindFirstChild(weaponName)
            if weaponPart then
                ClearWeaponTouch(weaponPart)
            end
        end

        activeAIs[unitModel] = nil

        DebugLog("停止AI")
    end
end

--[[
更新单个AI
@param unitModel Model - 兵种模型
@param aiData AIData - AI数据
]]
function UnitAI.UpdateAI(unitModel, aiData)
    local state = CombatSystem.GetUnitState(unitModel)

    if not state or not state.IsAlive then
        UnitAI.StopAI(unitModel)
        return
    end

    -- 根据AI状态执行不同逻辑
    local aiState = state.State

    if aiState == BattleConfig.AIState.IDLE or aiState == BattleConfig.AIState.SEEKING then
        -- 寻找目标
        local target = UnitAI.FindNearestEnemy(unitModel)

        if target then
            CombatSystem.SetTarget(unitModel, target)
            CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
        else
            CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
        end

    elseif aiState == BattleConfig.AIState.MOVING then
        -- 移动到目标
        local target = CombatSystem.GetTarget(unitModel)

        if not target or not target.Parent or not CombatSystem.IsUnitAlive(target) then
            -- 目标无效,重新寻找
            CombatSystem.SetTarget(unitModel, nil)
            CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
            return
        end

        -- 检查距离
        local distance = GetDistance(unitModel, target)

        if distance <= state.AttackRange then
            -- 进入攻击范围,停止移动
            aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
            CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
        else
            -- 继续移动到目标
            UnitAI.MoveToTarget(unitModel, target, aiData)
        end

    elseif aiState == BattleConfig.AIState.ATTACKING then
        -- 攻击目标
        local target = CombatSystem.GetTarget(unitModel)

        if not target or not target.Parent or not CombatSystem.IsUnitAlive(target) then
            -- 目标无效,重新寻找
            CombatSystem.SetTarget(unitModel, nil)
            CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
            return
        end

        -- 检查距离
        local distance = GetDistance(unitModel, target)

        if distance > state.AttackRange + BattleConfig.MOVE_STOP_TOLERANCE then
            -- 超出攻击范围,继续移动
            CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
        else
            -- 在攻击范围内,执行攻击
            UnitAI.AttackTarget(unitModel, target, state, aiData)
        end
    end
end

--[[
寻找最近的敌方单位
@param unitModel Model - 兵种模型
@return Model|nil - 最近的敌方单位
]]
function UnitAI.FindNearestEnemy(unitModel)
    local state = CombatSystem.GetUnitState(unitModel)

    if not state then
        return nil
    end

    local myTeam = state.Team
    local myBattleId = state.BattleId

    local nearestEnemy = nil
    local nearestDistance = math.huge

    -- 遍历所有单位状态,寻找敌方单位
    for otherModel, otherState in pairs(CombatSystem.GetAllUnitStates()) do
        -- 跳过自己
        if otherModel == unitModel then
            continue
        end

        -- 跳过同队
        if otherState.Team == myTeam then
            continue
        end

        -- 跳过不同战斗
        if otherState.BattleId ~= myBattleId then
            continue
        end

        -- 跳过死亡单位
        if not otherState.IsAlive then
            continue
        end

        -- 跳过模型不存在的单位
        if not otherModel or not otherModel.Parent then
            continue
        end

        -- 计算距离
        local distance = GetDistance(unitModel, otherModel)

        if distance < nearestDistance and distance <= BattleConfig.TARGET_SEARCH_RANGE then
            nearestDistance = distance
            nearestEnemy = otherModel
        end
    end

    return nearestEnemy
end

--[[
移动到目标
@param unitModel Model - 兵种模型
@param target Model - 目标模型
@param aiData AIData - AI数据
]]
function UnitAI.MoveToTarget(unitModel, target, aiData)
    local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart

    if not targetPart then
        return
    end

    -- 获取兵种ID并播放移动动画
    local state = CombatSystem.GetUnitState(unitModel)
    if state and state.UnitId then
        PlayMoveAnimation(aiData.Humanoid, state.UnitId)
    end

    -- 简单移动(直线移动)
    -- 注意: 当前使用简单的MoveTo，在复杂地形可能卡住
    -- TODO: 后续可使用PathfindingService实现复杂寻路
    -- 如果单位长时间无法到达目标，AI状态机会重新寻找目标
    aiData.Humanoid:MoveTo(targetPart.Position)
end

--[[
攻击目标
@param unitModel Model - 兵种模型
@param target Model - 目标模型
@param state table - 兵种战斗状态
@param aiData AIData - AI数据
]]
function UnitAI.AttackTarget(unitModel, target, state, aiData)
    -- 检查攻击冷却
    if not CombatSystem.CanAttack(unitModel) then
        return
    end

    -- 面向目标
    local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    if targetPart then
        local lookVector = (targetPart.Position - aiData.HumanoidRootPart.Position).Unit
        aiData.HumanoidRootPart.CFrame = CFrame.new(aiData.HumanoidRootPart.Position, aiData.HumanoidRootPart.Position + lookVector)
    end

    -- 播放攻击动画 (使用pcall保护，防止异常)
    local animationId = UnitConfig.GetAttackAnimationId(state.UnitId)
    local animSuccess, animErr = pcall(function()
        PlayAttackAnimation(aiData.Humanoid, animationId)
    end)

    if not animSuccess then
        WarnLog(string.format("播放动画失败: %s", animErr))
    end

    -- 判断是近战还是远程
    if UnitConfig.IsRangedUnit(state.UnitId) then
        -- 远程单位: 发射弹道
        local projectileSpeed = UnitConfig.GetProjectileSpeed(state.UnitId)

        if projectileSpeed > 0 then
            ProjectileSystem.CreateProjectile(unitModel, target, state.Attack, projectileSpeed)
            DebugLog(string.format("%s发射弹道攻击", state.UnitId))
        end

    else
        -- 近战单位: 使用武器接触检测
        local weaponName = UnitConfig.GetWeaponName(state.UnitId)
        local weaponPart = unitModel:FindFirstChild(weaponName)

        if not weaponPart then
            -- 武器不存在，Fallback到HumanoidRootPart
            weaponPart = unitModel:FindFirstChild("HumanoidRootPart")
            if not weaponPart then
                WarnLog("近战单位没有找到武器或HumanoidRootPart")
                return
            end
        end

        -- 设置武器接触检测
        SetupWeaponTouch(unitModel, weaponPart, target, state.Attack)

        DebugLog(string.format("%s触发近战攻击,等待武器接触", state.UnitId))
    end

    -- 更新攻击时间
    CombatSystem.UpdateLastAttackTime(unitModel, tick())
end

--[[
当目标死亡时的回调
@param deadUnit Model - 死亡的单位
@param battleId number - 战斗ID
]]
function UnitAI.OnTargetDeath(deadUnit, battleId)
    -- 通知所有以该单位为目标的AI重新寻找目标
    for unitModel, aiData in pairs(activeAIs) do
        if not aiData.IsActive then
            continue
        end

        local state = CombatSystem.GetUnitState(unitModel)

        if state and state.BattleId == battleId then
            local currentTarget = CombatSystem.GetTarget(unitModel)

            if currentTarget == deadUnit then
                -- 当前目标死亡,重新寻找
                CombatSystem.SetTarget(unitModel, nil)
                CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)

                DebugLog(string.format("%s的目标死亡,重新寻找目标", state.UnitId))
            end
        end
    end
end

--[[
清理战斗的所有AI
@param battleId number - 战斗ID
]]
function UnitAI.ClearBattleAIs(battleId)
    for unitModel, aiData in pairs(activeAIs) do
        local state = CombatSystem.GetUnitState(unitModel)

        -- 如果state不存在或者battleId匹配，都需要清理
        if not state or (state and state.BattleId == battleId) then
            UnitAI.StopAI(unitModel)
        end
    end

    DebugLog("已清理战斗", battleId, "的所有AI")
end

--[[
获取活跃AI数量
@return number - 活跃AI数量
]]
function UnitAI.GetActiveAICount()
    local count = 0

    for _, aiData in pairs(activeAIs) do
        if aiData.IsActive then
            count = count + 1
        end
    end

    return count
end

return UnitAI
