--[[
脚本名称: UnitAI
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitAI
版本: V1.5.2 - 状态机重构版
]]

--[[
兵种AI系统 - 重构版
职责:
1. 清晰的状态机: SEEKING → MOVING → ATTACKING → RECOVERY → SEEKING
2. 统一的距离策略: 所有距离判定通过UnitAIRangePolicy
3. 状态驱动的更新逻辑
4. 集中的动画管理和失效目标处理

重构改进:
- 状态机收敛为核心闭环
- 距离策略模块化
- 动画清理集中化
- 目标验证下沉
- 日志系统优化
]]

local UnitAI = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- 引用系统
local CombatSystem = require(ServerScriptService.Systems.CombatSystem)
local UnitManager = require(ServerScriptService.Systems.UnitManager)

-- ==================== 私有变量 ====================

-- 存储所有AI实例 [unitModel] = AIData
local activeAIs = {}

-- AI更新连接
local updateConnection = nil

-- 死亡事件连接
local deathEventConnection = nil

-- AI节流相关
local accumulatedTime = 0

-- 是否已初始化
local isInitialized = false

-- ==================== 核心状态机定义 ====================

--[[
状态机规则表
每个状态定义：
- EnterConditions: 进入此状态的条件
- Actions: 此状态中执行的操作
- ExitConditions: 退出此状态的条件
- NextStates: 可能转移到的下一状态
]]
local AIStateMachine = {
	[BattleConfig.AIState.SEEKING] = {
		Description = "寻找目标",
		EnterConditions = "无目标 或 目标死亡/失效",
		Actions = "调用FindNearestEnemy寻找敌人",
		ExitConditions = "找到目标 → MOVING | 无目标 → IDLE",
		NextStates = { BattleConfig.AIState.MOVING, BattleConfig.AIState.IDLE }
	},

	[BattleConfig.AIState.MOVING] = {
		Description = "移动到目标",
		EnterConditions = "已有目标且距离 > 进入攻击阈值",
		Actions = "计算移动目标点, 调用MoveTo, 播放移动动画",
		ExitConditions = "距离 <= 进入攻击阈值 → ATTACKING | 目标失效 → SEEKING",
		NextStates = { BattleConfig.AIState.ATTACKING, BattleConfig.AIState.SEEKING }
	},

	[BattleConfig.AIState.ATTACKING] = {
		Description = "攻击目标",
		EnterConditions = "距离 <= 进入攻击阈值且可攻击",
		Actions = "停止移动, 面向目标, 触发攻击动画, 调用BeginAttack",
		ExitConditions = "距离 > 脱离攻击阈值 → MOVING | 目标失效 → SEEKING",
		NextStates = { BattleConfig.AIState.MOVING, BattleConfig.AIState.SEEKING }
	},

	-- RECOVERY阶段由CombatSystem管理，AI无需关心
	-- 单位在ATTACKING状态期间会自动经历 Attacking → Recovery → Idle 的攻击阶段
}

-- ==================== 距离策略模块 ====================

local UnitAIRangePolicy = {}

--[[
获取停靠距离
@param unitState - 兵种战斗状态
@param targetState - 目标战斗状态（可选）
@return number - 停靠距离
]]
function UnitAIRangePolicy.GetDockingDistance(unitState, targetState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		-- 远程单位：停在攻击距离 * RANGED_DOCKING_RATIO 处
		return unitState.AttackRange * BattleConfig.RANGED_DOCKING_RATIO
	else
		-- 近战单位：考虑模型物理尺寸，计算贴身距离
		local attackerRoot = unitState.UnitInstance:FindFirstChild("HumanoidRootPart")
		if not attackerRoot then
			return unitState.AttackRange
		end

		local attackerDepth = attackerRoot.Size.Z
		local targetDepth = 5  -- 默认值

		if targetState and targetState.UnitInstance then
			local targetRoot = targetState.UnitInstance:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				targetDepth = targetRoot.Size.Z
			end
		end

		-- 接触距离 = 两个半径相加
		local contactDistance = (attackerDepth + targetDepth) * 0.5

		-- 期望距离 = 接触距离 - 缓冲
		local desiredDistance = math.max(contactDistance - BattleConfig.CONTACT_BUFFER, 0)

		-- 综合考虑攻击距离和物理尺寸
		local combatProfile = UnitConfig.GetCombatProfile(unitState.UnitId)
		local contactOffset = (combatProfile and combatProfile.ContactOffset) or 0

		return math.max(
			math.min(unitState.AttackRange - BattleConfig.ATTACK_RANGE_TOLERANCE, desiredDistance),
			BattleConfig.MIN_DOCKING_DISTANCE
		) + contactOffset
	end
end

--[[
判断是否应该进入攻击状态
@param distance - 当前距离
@param unitState - 兵种战斗状态
@return boolean - 是否应该进入攻击
]]
function UnitAIRangePolicy.ShouldEnterAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		-- 远程单位：距离 <= 攻击距离 * RANGED_ENTER_ATTACK_RATIO
		local threshold = unitState.AttackRange * BattleConfig.RANGED_ENTER_ATTACK_RATIO
		return distance <= threshold
	else
		-- 近战单位：距离 <= 攻击距离 + 容差
		local threshold = unitState.AttackRange + BattleConfig.ATTACK_RANGE_TOLERANCE
		return distance <= threshold
	end
end

--[[
判断是否应该退出攻击状态
@param distance - 当前距离
@param unitState - 兵种战斗状态
@return boolean - 是否应该退出攻击
]]
function UnitAIRangePolicy.ShouldExitAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		-- 远程单位：距离 > 攻击距离 * RANGED_EXIT_ATTACK_RATIO
		local threshold = unitState.AttackRange * BattleConfig.RANGED_EXIT_ATTACK_RATIO
		return distance > threshold
	else
		-- 近战单位：距离 > 攻击距离 + 容差 + 移动停止容差
		local threshold = unitState.AttackRange + BattleConfig.ATTACK_RANGE_TOLERANCE + BattleConfig.MOVE_STOP_TOLERANCE
		return distance > threshold
	end
end

-- ==================== AIData数据结构 ====================

--[[
AIData = {
    UnitModel = Model,           -- 兵种模型
    Humanoid = Humanoid,         -- Humanoid对象
    HumanoidRootPart = Part,     -- HumanoidRootPart
    IsActive = boolean,          -- AI是否激活
    LastUpdateTime = number,     -- 上次更新时间

    -- 动画管理 (V1.5.2扩展)
    CurrentMoveAnimation = AnimationTrack|nil,
    CurrentAttackAnimation = AnimationTrack|nil,
    CurrentIdleAnimation = AnimationTrack|nil,  -- V1.5.2新增: 待机动画
    AnimationConnections = {},   -- 动画事件连接

    -- 方向缓存（防止零向量）
    LastDesiredDirection = Vector3|nil,
}
]]

-- ==================== 私有工具函数 ====================

--[[
输出调试日志
]]
local function DebugLog(...)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
	end
end

--[[
输出警告日志
]]
local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
end

--[[
状态变更日志（关键节点）
]]
local function LogStateChange(unitId, fromState, toState, reason)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, string.format("[UnitAI] %s: %s → %s (%s)",
			unitId, fromState or "nil", toState, reason or ""))
	end
end

--[[
计算两个模型之间的距离
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
播放移动动画
]]
local function PlayMoveAnimation(humanoid, unitId)
	if not humanoid or not unitId then
		return nil
	end

	local animationId = UnitConfig.GetMoveAnimationId(unitId)

	if not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	if not tonumber(animationId) then
		WarnLog(string.format("无效的移动动画ID格式: %s", animationId))
		return nil
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animationId

	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not animationTrack then
		animation:Destroy()
		return nil
	end

	animationTrack.Looped = true

	local playSuccess = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return nil
	end

	-- V1.5.2修复：循环动画在停止时清理Animation对象，防止内存泄漏
	animationTrack.Stopped:Connect(function()
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)

	return animationTrack
end

--[[
播放攻击动画
]]
local function PlayAttackAnimation(humanoid, animationId)
	if not humanoid then
		return nil
	end

	if not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	if not tonumber(animationId) then
		WarnLog(string.format("无效的动画ID格式: %s", animationId))
		return nil
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid.Parent:FindFirstChildOfClass("Animator")
	end

	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animationId

	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not animationTrack then
		animation:Destroy()
		return nil
	end

	animationTrack.Looped = false

	local playSuccess = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return nil
	end

	task.delay(animationTrack.Length + 0.1, function()
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)

	return animationTrack
end

--[[
播放死亡动画 (V1.5.2新增)
@param humanoid Humanoid - Humanoid对象
@param animationId string - 动画ID
@return AnimationTrack|nil - 动画轨道，失败返回nil
]]
local function PlayDeathAnimation(humanoid, animationId)
	if not humanoid then
		return nil
	end

	if not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	if not tonumber(animationId) then
		WarnLog(string.format("无效的死亡动画ID格式: %s", animationId))
		return nil
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid.Parent:FindFirstChildOfClass("Animator")
	end

	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animationId

	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not animationTrack then
		animation:Destroy()
		return nil
	end

	animationTrack.Looped = false

	local playSuccess = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return nil
	end

	-- 死亡动画播放完成后自动清理
	task.delay(animationTrack.Length + 0.1, function()
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)

	return animationTrack
end

--[[
播放待机动画 (V1.5.2新增)
@param humanoid Humanoid - Humanoid对象
@param animationId string - 动画ID
@return AnimationTrack|nil - 动画轨道，失败返回nil
]]
local function PlayIdleAnimation(humanoid, animationId)
	if not humanoid then
		return nil
	end

	if not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	if not tonumber(animationId) then
		WarnLog(string.format("无效的待机动画ID格式: %s", animationId))
		return nil
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid.Parent:FindFirstChildOfClass("Animator")
	end

	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animationId

	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not animationTrack then
		animation:Destroy()
		return nil
	end

	animationTrack.Looped = true  -- 待机动画循环播放

	local playSuccess = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return nil
	end

	-- V1.5.2修复：循环动画在停止时清理Animation对象，防止内存泄漏
	animationTrack.Stopped:Connect(function()
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)

	return animationTrack
end

--[[
重置动画状态（集中化清理）
@param aiData - AI数据
@param keepMove - 是否保留移动动画
@param keepIdle - 是否保留待机动画 (V1.5.2新增)
]]
local function ResetAnimationState(aiData, keepMove, keepIdle)
	-- 停止攻击动画
	if aiData.CurrentAttackAnimation then
		aiData.CurrentAttackAnimation:Stop()
		aiData.CurrentAttackAnimation = nil
	end

	-- 停止移动动画（除非保留）
	if not keepMove and aiData.CurrentMoveAnimation then
		aiData.CurrentMoveAnimation:Stop()
		aiData.CurrentMoveAnimation = nil
	end

	-- V1.5.2新增: 停止待机动画（除非保留）
	if not keepIdle and aiData.CurrentIdleAnimation then
		aiData.CurrentIdleAnimation:Stop()
		aiData.CurrentIdleAnimation = nil
	end

	-- 断开所有动画事件连接
	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}
end

--[[
确保单位停止移动
@param unitModel - 兵种模型
@param aiData - AI数据
]]
local function EnsureStopped(unitModel, aiData)
	if not aiData or not aiData.Humanoid or not aiData.HumanoidRootPart then
		return
	end

	-- 发送MoveTo到当前位置，确保停止
	aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)

	-- 停止移动动画
	if aiData.CurrentMoveAnimation then
		aiData.CurrentMoveAnimation:Stop()
		aiData.CurrentMoveAnimation = nil
	end
end

--[[
面向目标（防止零向量）
@param aiData - AI数据
@param target - 目标模型
@return boolean - 是否成功面向目标
]]
local function OrientTowardsTarget(aiData, target)
	if not aiData or not aiData.HumanoidRootPart then
		return false
	end

	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if not targetPart then
		return false
	end

	local lookVector = (targetPart.Position - aiData.HumanoidRootPart.Position)
	local lookDistance = lookVector.Magnitude

	-- 只有当向量不为零时才更新朝向
	if lookDistance > 0.01 then
		lookVector = lookVector.Unit
		aiData.HumanoidRootPart.CFrame = CFrame.new(
			aiData.HumanoidRootPart.Position,
			aiData.HumanoidRootPart.Position + lookVector
		)
		-- 缓存朝向
		aiData.LastDesiredDirection = lookVector
		return true
	end

	-- 距离太近，保持原朝向
	return false
end

--[[
验证并获取有效目标
@param unitModel - 兵种模型
@return Model|nil - 有效的目标，无效返回nil
]]
local function ValidateTarget(unitModel)
	local target = CombatSystem.GetTarget(unitModel)

	if not target or not target.Parent then
		return nil
	end

	if not CombatSystem.IsUnitAlive(target) then
		return nil
	end

	return target
end

-- ==================== 状态处理函数 ====================

--[[
处理SEEKING状态：寻找目标
]]
local function HandleSeeking(unitModel, aiData, state)
	local target = UnitAI.FindNearestEnemy(unitModel)

	if target then
		CombatSystem.SetTarget(unitModel, target)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		LogStateChange(state.UnitId, "SEEKING", "MOVING", "找到目标")
	else
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
	end
end

--[[
处理MOVING状态：移动到目标
]]
local function HandleMoving(unitModel, aiData, state)
	-- 验证目标
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		LogStateChange(state.UnitId, "MOVING", "SEEKING", "目标失效")
		return
	end

	-- 检查距离
	local distance = GetDistance(unitModel, target)

	-- 🔧 V1.5.3关键修复：远程单位提前停止策略（增强版）
	-- 当距离已经接近停靠距离时，停止移动，避免互相穿越
	local isRanged = UnitConfig.IsRangedUnit(state.UnitId)
	if isRanged then
		local targetState = CombatSystem.GetUnitState(target)
		local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

		-- 🔧 优化1: 增大提前停止的缓冲距离从+2改为+4 studs
		-- 原因：给AI更多的反应时间，避免惯性导致穿越
		-- 🔧 优化2: 如果已经在合适距离，也执行停止，防止边打边走
		if distance <= dockingDistance + 4 then
			DebugLog(string.format("%s (远程) 接近停靠距离(%.1f <= %.1f+4)，提前停止",
				state.UnitId, distance, dockingDistance))
			EnsureStopped(unitModel, aiData)

			-- 🔧 优化3: 如果距离已经在进入攻击阈值内，直接切换到ATTACKING
			if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
				LogStateChange(state.UnitId, "MOVING", "ATTACKING", string.format("提前停止后距离符合攻击条件(%.1f)", distance))
				return  -- 直接返回，避免后续MoveTo覆盖停止状态
			end
		end
	end

	-- 判断是否应该进入攻击
	if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
		-- 停止移动
		EnsureStopped(unitModel, aiData)

		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
		LogStateChange(state.UnitId, "MOVING", "ATTACKING", string.format("距离%.1f <= 阈值", distance))
	else
		-- 继续移动到目标
		UnitAI.MoveToTarget(unitModel, target, aiData, state)
	end
end

--[[
处理ATTACKING状态：攻击目标
]]
local function HandleAttacking(unitModel, aiData, state)
	-- 验证目标
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		LogStateChange(state.UnitId, "ATTACKING", "SEEKING", "目标失效")
		return
	end

	-- 检查距离
	local distance = GetDistance(unitModel, target)

	-- 判断是否应该退出攻击
	if UnitAIRangePolicy.ShouldExitAttack(distance, state) then
		-- 停止攻击动画和待机动画
		if aiData.CurrentAttackAnimation then
			aiData.CurrentAttackAnimation:Stop()
			aiData.CurrentAttackAnimation = nil
		end
		if aiData.CurrentIdleAnimation then
			aiData.CurrentIdleAnimation:Stop()
			aiData.CurrentIdleAnimation = nil
		end

		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		LogStateChange(state.UnitId, "ATTACKING", "MOVING", string.format("距离%.1f > 脱离阈值", distance))
	else
		-- 保持静止，面向目标
		EnsureStopped(unitModel, aiData)
		OrientTowardsTarget(aiData, target)

		-- V1.5.2新增: 如果处于IDLE攻击阶段且没有播放idle动画，则播放
		local attackPhase = CombatSystem.GetAttackPhase(unitModel)
		if attackPhase == BattleConfig.AttackPhase.IDLE then
			if not aiData.CurrentIdleAnimation or not aiData.CurrentIdleAnimation.IsPlaying then
				local idleAnimId = UnitConfig.GetIdleAnimationId(state.UnitId)
				if idleAnimId and idleAnimId ~= "" then
					local idleAnimTrack = PlayIdleAnimation(aiData.Humanoid, idleAnimId)
					if idleAnimTrack then
						aiData.CurrentIdleAnimation = idleAnimTrack
						DebugLog(string.format("%s 开始播放待机动画", state.UnitId))
					end
				end
			end
		end

		-- 执行攻击
		UnitAI.AttackTarget(unitModel, target, state, aiData)
	end
end

-- ==================== AI更新 ====================

--[[
更新所有AI (批量节流)
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
]]
function UnitAI.Initialize()
	if isInitialized then
		WarnLog("AI系统已经初始化过了")
		return true
	end

	DebugLog("正在初始化AI系统...")

	-- AI节流机制
	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulatedTime = accumulatedTime + dt
		if accumulatedTime >= BattleConfig.AI_BATCH_UPDATE_INTERVAL then
			UpdateAllAIs()
			accumulatedTime = 0
		end
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

	DebugLog(string.format("AI系统初始化完成 (节流间隔: %.2f秒)", BattleConfig.AI_BATCH_UPDATE_INTERVAL))
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
		CurrentMoveAnimation = nil,
		CurrentAttackAnimation = nil,
		CurrentIdleAnimation = nil,  -- V1.5.2新增: 待机动画
		AnimationConnections = {},
		LastDesiredDirection = nil,
	}

	activeAIs[unitModel] = aiData

	-- 设置移动速度
	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		humanoid.WalkSpeed = state.MoveSpeed
	end

	local unitId = state and state.UnitId or "Unknown"
	DebugLog(string.format("启动AI: %s", unitId))

	-- 立刻主动寻找目标并开始移动
	task.defer(function()
		if not aiData.IsActive then
			return
		end

		local target = UnitAI.FindNearestEnemy(unitModel)

		if target then
			CombatSystem.SetTarget(unitModel, target)
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
			LogStateChange(unitId, "IDLE", "MOVING", "AI启动，发现目标")
		else
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
		end
	end)

	return true
end

--[[
停止兵种AI
]]
function UnitAI.StopAI(unitModel)
	local aiData = activeAIs[unitModel]

	if aiData then
		aiData.IsActive = false

		-- 重置所有动画状态（V1.5.2修复：明确传递第三个参数）
		ResetAnimationState(aiData, false, false)  -- 不保留任何动画

		-- 停止移动
		if aiData.Humanoid and aiData.HumanoidRootPart then
			aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
		end

		activeAIs[unitModel] = nil

		DebugLog("停止AI")
	end
end

--[[
更新单个AI（核心状态机）
]]
function UnitAI.UpdateAI(unitModel, aiData)
	local state = CombatSystem.GetUnitState(unitModel)

	if not state or not state.IsAlive then
		UnitAI.StopAI(unitModel)
		return
	end

	-- 根据AI状态执行对应处理函数
	local aiState = state.State

	if aiState == BattleConfig.AIState.IDLE or aiState == BattleConfig.AIState.SEEKING then
		HandleSeeking(unitModel, aiData, state)

	elseif aiState == BattleConfig.AIState.MOVING then
		HandleMoving(unitModel, aiData, state)

	elseif aiState == BattleConfig.AIState.ATTACKING then
		HandleAttacking(unitModel, aiData, state)
	end
end

--[[
寻找最近的敌方单位
]]
function UnitAI.FindNearestEnemy(unitModel)
	local enemy, distance = UnitManager.GetClosestEnemy(unitModel, BattleConfig.TARGET_SEARCH_RANGE)
	return enemy
end

--[[
移动到目标（纯函数式计算，防止零向量和负向移动）
]]
function UnitAI.MoveToTarget(unitModel, target, aiData, state)
	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart

	if not targetPart then
		return
	end

	-- 播放移动动画（只在没有播放时才播放）
	if not aiData.CurrentMoveAnimation or not aiData.CurrentMoveAnimation.IsPlaying then
		local moveAnimTrack = PlayMoveAnimation(aiData.Humanoid, state.UnitId)
		if moveAnimTrack then
			aiData.CurrentMoveAnimation = moveAnimTrack
		end
	end

	local myPos = aiData.HumanoidRootPart.Position
	local targetPos = targetPart.Position

	-- ==================== 🔧 修复1: 防止零向量导致NaN ====================
	local offset = targetPos - myPos
	local currentDistance = offset.Magnitude

	-- 如果距离过近（接近重合），停止移动，复用上次的朝向
	if currentDistance < 0.1 then
		DebugLog(string.format("%s 距离过近(%.3f)，停止移动避免零向量", state.UnitId, currentDistance))
		EnsureStopped(unitModel, aiData)

		-- 如果有缓存的朝向，保持朝向
		if aiData.LastDesiredDirection then
			aiData.HumanoidRootPart.CFrame = CFrame.new(
				aiData.HumanoidRootPart.Position,
				aiData.HumanoidRootPart.Position + aiData.LastDesiredDirection
			)
		end
		return
	end

	-- 计算停靠距离
	local targetState = CombatSystem.GetUnitState(target)
	local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

	-- ==================== 🔧 修复2: 防止负向移动（目标在身后） ====================
	-- 计算需要移动的距离：当前距离 - 停靠距离
	local moveDistance = currentDistance - dockingDistance

	-- 如果已经进入停靠范围（或更近），停止移动
	-- 添加容差 0.5，避免频繁进出停靠范围
	if moveDistance <= 0.5 then
		DebugLog(string.format("%s 已到达停靠范围，当前距离=%.1f，停靠距离=%.1f",
			state.UnitId, currentDistance, dockingDistance))
		EnsureStopped(unitModel, aiData)
		return
	end

	-- ==================== 🔧 修复3: 只在需要移动时才MoveTo ====================
	-- 安全计算方向向量（已确保 currentDistance >= 0.1）
	local direction = offset.Unit

	-- 缓存方向向量
	aiData.LastDesiredDirection = direction

	-- 计算移动目标点：从目标位置往回退 dockingDistance
	local moveTarget = targetPos - direction * dockingDistance

	-- 检查移动阈值：只有移动距离足够大时才执行MoveTo
	local distanceToMoveTarget = (moveTarget - myPos).Magnitude
	if distanceToMoveTarget < 0.5 then
		-- 移动距离太小，停止避免抖动
		DebugLog(string.format("%s 移动距离过小(%.2f)，停止避免抖动", state.UnitId, distanceToMoveTarget))
		EnsureStopped(unitModel, aiData)
		return
	end

	-- 执行移动
	aiData.Humanoid:MoveTo(moveTarget)

	local unitType = UnitConfig.IsRangedUnit(state.UnitId) and "远程" or "近战"
	DebugLog(string.format("%s (%s) 移动中，当前距离=%.1f，停靠距离=%.1f，需移动=%.1f",
		state.UnitId, unitType, currentDistance, dockingDistance, moveDistance))
end

--[[
攻击目标（动画事件驱动）
]]
function UnitAI.AttackTarget(unitModel, target, state, aiData)
	-- 检查攻击冷却
	if not CombatSystem.CanAttack(unitModel) then
		return
	end

	-- V1.5.2修复：清理之前的攻击动画和事件（保留移动动画，停止idle动画）
	-- ResetAnimationState会停止idle和attack，所以不需要单独停止idle
	ResetAnimationState(aiData, true, false)

	-- 停止移动动画（攻击时不移动）
	if aiData.CurrentMoveAnimation then
		aiData.CurrentMoveAnimation:Stop()
		aiData.CurrentMoveAnimation = nil
	end

	-- 面向目标
	OrientTowardsTarget(aiData, target)

	-- 开始攻击（进入Attacking阶段）
	local success = CombatSystem.BeginAttack(unitModel, target)
	if not success then
		return
	end

	-- 获取配置
	local animationId = UnitConfig.GetAttackAnimationId(state.UnitId)
	local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)

	-- 用于确保Damage事件只触发一次
	local damageEventFired = false

	-- 判断是否为远程单位
	local isRangedUnit = UnitConfig.IsRangedUnit(state.UnitId)

	-- 播放攻击动画
	if animationId and animationId ~= "" and combatProfile.UseAnimationEvent then
		local animTrack = PlayAttackAnimation(aiData.Humanoid, animationId)

		if animTrack then
			-- 监听动画的 "Damage" 事件
			local eventName = combatProfile.AnimationEventName or "Damage"

			local connection = animTrack:GetMarkerReachedSignal(eventName):Connect(function()
				if damageEventFired then
					return
				end
				damageEventFired = true

				DebugLog(string.format("%s 动画事件[%s]触发", state.UnitId, eventName))

				-- 远程/近战分支
				if isRangedUnit then
					CombatSystem.OnRangedDamageEvent(unitModel, target)
				else
					CombatSystem.OnDamageEvent(unitModel)
				end
			end)

			table.insert(aiData.AnimationConnections, connection)
			aiData.CurrentAttackAnimation = animTrack

			-- 动画停止时自动清理连接
			animTrack.Stopped:Connect(function()
				if connection and connection.Connected then
					connection:Disconnect()
				end
			end)
		else
			-- 动画加载失败，使用回退机制
			local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
			task.delay(fallbackDelay, function()
				if unitModel and unitModel.Parent and not damageEventFired then
					if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
						damageEventFired = true
						if isRangedUnit then
							CombatSystem.OnRangedDamageEvent(unitModel, target)
						else
							CombatSystem.OnDamageEvent(unitModel)
						end
					end
				end
			end)
		end
	else
		-- 没有配置动画，使用回退机制
		local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
		task.delay(fallbackDelay, function()
			if unitModel and unitModel.Parent and not damageEventFired then
				if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
					damageEventFired = true
					if isRangedUnit then
						CombatSystem.OnRangedDamageEvent(unitModel, target)
					else
						CombatSystem.OnDamageEvent(unitModel)
					end
				end
			end
		end)
	end
end

--[[
当目标死亡时的回调
]]
function UnitAI.OnTargetDeath(deadUnit, battleId)
	for unitModel, aiData in pairs(activeAIs) do
		if not aiData.IsActive then
			continue
		end

		local state = CombatSystem.GetUnitState(unitModel)

		if state and state.BattleId == battleId then
			local currentTarget = CombatSystem.GetTarget(unitModel)

			if currentTarget == deadUnit then
				CombatSystem.SetTarget(unitModel, nil)
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)

				LogStateChange(state.UnitId, state.State, "SEEKING", "目标死亡")
			end
		end
	end
end

--[[
清理战斗的所有AI
]]
function UnitAI.ClearBattleAIs(battleId)
	for unitModel, aiData in pairs(activeAIs) do
		local state = CombatSystem.GetUnitState(unitModel)

		if not state or (state and state.BattleId == battleId) then
			UnitAI.StopAI(unitModel)
		end
	end

	DebugLog("已清理战斗", battleId, "的所有AI")
end

--[[
获取活跃AI数量
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

--[[
播放死亡动画 (V1.5.2新增 - 供CombatSystem调用)
@param unitModel Model - 兵种模型
@param animationId string - 死亡动画ID
@return AnimationTrack|nil - 动画轨道，失败返回nil
]]
function UnitAI.PlayDeathAnimation(unitModel, animationId)
	if not unitModel or not unitModel:IsA("Model") then
		return nil
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	return PlayDeathAnimation(humanoid, animationId)
end

return UnitAI
