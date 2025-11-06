--[[
脚本名称: UnitAI (显式动画状态机版)
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitAI
版本: V1.5.4 - 显式动画状态机重构
]]

--[[
兵种AI系统 - 显式动画状态机版
职责:
1. 清晰的AI状态机: SEEKING → MOVING → ATTACKING
2. 独立的动画控制器: 统一管理所有动画切换
3. 正确的动画流程: 移动 → idle → attack → idle(冷却) → attack → ...
4. 攻击周期明确: attack结束 → idle开始 → 冷却结束 → 下次attack

核心改进:
- 显式动画状态(MOVE/IDLE/ATTACK)，杜绝互相踩踏
- 动画Track自动清理，攻击结束回调触发idle
- HandleAttacking只负责判断是否可以攻击，不直接操作动画
- 冷却期idle稳定播放，覆盖整个CD阶段
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

-- ==================== 调试日志 ====================

local function DebugLog(...)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
end

local function LogStateChange(unitId, fromState, toState, reason)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, string.format("[UnitAI] %s: %s → %s (%s)",
			unitId, fromState or "nil", toState, reason or ""))
	end
end

local function LogAnimationChange(unitId, fromAnim, toAnim, reason)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, string.format("[UnitAI] %s 动画: %s → %s (%s)",
			unitId, fromAnim or "None", toAnim, reason or ""))
	end
end

-- ==================== 动画基础函数 ====================

--[[
创建并播放动画
@param humanoid - Humanoid对象
@param animationId - 动画ID
@param looped - 是否循环
@return AnimationTrack|nil
]]
local function CreateAndPlayAnimation(humanoid, animationId, looped)
	if not humanoid or not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	if not tonumber(animationId) then
		WarnLog(string.format("无效的动画ID格式: %s", animationId))
		return nil
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid.Parent and humanoid.Parent:FindFirstChildOfClass("Animator")
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

	animationTrack.Looped = looped or false

	local playSuccess = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return nil
	end

	-- 清理Animation对象
	if looped then
		-- 循环动画：在停止时清理
		animationTrack.Stopped:Connect(function()
			if animation and animation.Parent then
				animation:Destroy()
			end
		end)
	else
		-- 单次动画：延迟清理（服务器上无法获取Length，使用固定延迟）
		task.delay(5, function()
			if animation and animation.Parent then
				animation:Destroy()
			end
		end)
	end

	return animationTrack
end

--[[
安全停止动画
@param animationTrack - 动画轨道
]]
local function SafeStopAnimation(animationTrack)
	if animationTrack and animationTrack.IsPlaying then
		pcall(function()
			animationTrack:Stop()
		end)
	end
end

-- ==================== 统一动画状态机 ====================

local AnimationState = {
	MOVE = "MOVE",
	IDLE = "IDLE",
	ATTACK = "ATTACK",
}

--[[
动画控制器 - 统一管理所有动画切换
职责：
1. 维护 Tracks 表存储所有动画轨道
2. 确保状态切换时精确停止需要的轨道
3. 攻击动画结束自动回到Idle
]]
local AnimationController = {}

--[[
切换到移动状态
@param unitModel - 兵种模型
@param aiData - AI数据
@param state - 单位状态
]]
function AnimationController.SwitchToMove(unitModel, aiData, state)
	-- 如果已经在播放移动动画，跳过
	if aiData.CurrentState == AnimationState.MOVE and
	   aiData.Tracks.Move and
	   aiData.Tracks.Move.IsPlaying then
		return
	end

	-- 停止 Idle 和 Attack
	if aiData.Tracks.Idle then
		SafeStopAnimation(aiData.Tracks.Idle)
		aiData.Tracks.Idle = nil
	end
	if aiData.Tracks.Attack then
		SafeStopAnimation(aiData.Tracks.Attack)
		aiData.Tracks.Attack = nil
	end

	-- 播放移动动画
	local animId = UnitConfig.GetMoveAnimationId(state.UnitId)
	if animId and animId ~= "" then
		local track = CreateAndPlayAnimation(aiData.Humanoid, animId, true)
		if track then
			aiData.Tracks.Move = track
			aiData.CurrentState = AnimationState.MOVE
			LogAnimationChange(state.UnitId, aiData.LastState, AnimationState.MOVE, "开始移动")
			aiData.LastState = AnimationState.MOVE
		end
	else
		aiData.CurrentState = AnimationState.MOVE
	end
end

--[[
切换到待机状态
@param unitModel - 兵种模型
@param aiData - AI数据
@param state - 单位状态
]]
function AnimationController.SwitchToIdle(unitModel, aiData, state)
	-- 严格检查1：如果已经在播放Idle动画，直接返回
	if aiData.CurrentState == AnimationState.IDLE then
		if aiData.Tracks.Idle and aiData.Tracks.Idle.IsPlaying then
			-- 已经在播放Idle，无需重复切换
			return
		end
	end

	-- 严格检查2：如果Attack正在播放，不要打断它
	if aiData.Tracks.Attack and aiData.Tracks.Attack.IsPlaying then
		-- Attack还在播放，不要打断，等它自然结束
		return
	end

	-- 停止 Move（但不停止 Attack，上面已经检查过了）
	if aiData.Tracks.Move then
		SafeStopAnimation(aiData.Tracks.Move)
		aiData.Tracks.Move = nil
	end

	-- 播放待机动画
	local animId = UnitConfig.GetIdleAnimationId(state.UnitId)
	if animId and animId ~= "" then
		local track = CreateAndPlayAnimation(aiData.Humanoid, animId, true)
		if track then
			aiData.Tracks.Idle = track
			aiData.CurrentState = AnimationState.IDLE
			LogAnimationChange(state.UnitId, aiData.LastState, AnimationState.IDLE, "进入待机")
			aiData.LastState = AnimationState.IDLE
		end
	else
		aiData.CurrentState = AnimationState.IDLE
	end
end

--[[
播放攻击动画
@param unitModel - 兵种模型
@param aiData - AI数据
@param state - 单位状态
@param target - 攻击目标
@param onDamageCallback - 伤害回调
]]
function AnimationController.PlayAttack(unitModel, aiData, state, target, onDamageCallback)
	-- 清理之前的攻击动画连接
	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}

	-- 获取配置
	local animationId = UnitConfig.GetAttackAnimationId(state.UnitId)
	local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)
	local isRangedUnit = UnitConfig.IsRangedUnit(state.UnitId)

	-- 全局防重复标志（基于单位模型）
	local damageEventFired = false
	local attackKey = tostring(unitModel) .. "_" .. tick()

	-- 保存旧轨道的引用，但先不停止
	local prevMove = aiData.Tracks.Move
	local prevIdle = aiData.Tracks.Idle

	-- 播放攻击动画
	if animationId and animationId ~= "" and combatProfile.UseAnimationEvent then
		local animTrack = CreateAndPlayAnimation(aiData.Humanoid, animationId, false)

		if animTrack then
			-- 攻击动画成功加载并播放后，再停止旧动画
			aiData.Tracks.Attack = animTrack
			aiData.CurrentState = AnimationState.ATTACK
			LogAnimationChange(state.UnitId, aiData.LastState, AnimationState.ATTACK, "开始攻击")
			aiData.LastState = AnimationState.ATTACK

			-- 关键修复：此时再停止旧轨道，保证无缝切换
			if prevMove then
				SafeStopAnimation(prevMove)
				aiData.Tracks.Move = nil
			end
			if prevIdle then
				SafeStopAnimation(prevIdle)
				aiData.Tracks.Idle = nil
			end

			-- 监听动画的 "Damage" 事件
			local eventName = combatProfile.AnimationEventName or "Damage"

			local damageConnection = animTrack:GetMarkerReachedSignal(eventName):Connect(function()
				-- 双重检查防止重复触发
				if damageEventFired then
					DebugLog(string.format("%s Damage事件重复触发，忽略", state.UnitId))
					return
				end
				damageEventFired = true

				DebugLog(string.format("%s 动画事件[%s]触发", state.UnitId, eventName))

				-- 调用伤害回调（这会触发 OnDamageEvent，进入 Recovery）
				if onDamageCallback then
					onDamageCallback(unitModel, target, isRangedUnit)
				end
			end)

			table.insert(aiData.AnimationConnections, damageConnection)

			-- 关键修复：攻击动画结束时立即切换到Idle，不等下一帧
			local stoppedConnection = animTrack.Stopped:Connect(function()
				-- 断开所有连接
				for _, conn in ipairs(aiData.AnimationConnections) do
					if conn and conn.Connected then
						conn:Disconnect()
					end
				end
				aiData.AnimationConnections = {}

				-- 清空攻击动画引用
				aiData.Tracks.Attack = nil

				DebugLog(string.format("%s 攻击动画已停止", state.UnitId))

				-- 立即切换到Idle，不等下一帧
				if aiData.IsActive and unitModel.Parent and CombatSystem.IsUnitAlive(unitModel) then
					local latestState = CombatSystem.GetUnitState(unitModel)
					if latestState then
						DebugLog(string.format("%s 攻击结束，立即切换到Idle", state.UnitId))
						AnimationController.SwitchToIdle(unitModel, aiData, latestState)
					end
				end
			end)

			table.insert(aiData.AnimationConnections, stoppedConnection)

			return true
		else
			-- 动画加载失败，使用回退机制
			local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
			task.delay(fallbackDelay, function()
				if unitModel and unitModel.Parent and not damageEventFired then
					if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
						damageEventFired = true
						if onDamageCallback then
							onDamageCallback(unitModel, target, isRangedUnit)
						end

						-- 回退机制：触发伤害后立即切换到 Idle
						if aiData.IsActive and unitModel.Parent and CombatSystem.IsUnitAlive(unitModel) then
							local latestState = CombatSystem.GetUnitState(unitModel)
							if latestState then
								DebugLog(string.format("%s (回退)立即切换到Idle", state.UnitId))
								AnimationController.SwitchToIdle(unitModel, aiData, latestState)
							end
						end
					end
				end
			end)

			return true
		end
	else
		-- 没有配置动画，使用回退机制
		local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
		task.delay(fallbackDelay, function()
			if unitModel and unitModel.Parent and not damageEventFired then
				if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
					damageEventFired = true
					if onDamageCallback then
						onDamageCallback(unitModel, target, isRangedUnit)
					end

					-- 回退机制：触发伤害后立即切换到 Idle
					if aiData.IsActive and unitModel.Parent and CombatSystem.IsUnitAlive(unitModel) then
						local latestState = CombatSystem.GetUnitState(unitModel)
						if latestState then
							DebugLog(string.format("%s (回退)立即切换到Idle", state.UnitId))
							AnimationController.SwitchToIdle(unitModel, aiData, latestState)
						end
					end
				end
			end
		end)

		return true
	end
end

--[[
停止所有动画
@param aiData - AI数据
]]
function AnimationController.StopAllAnimations(aiData)
	-- 停止所有轨道
	for animName, track in pairs(aiData.Tracks) do
		SafeStopAnimation(track)
	end
	aiData.Tracks = {}

	-- 断开所有动画事件连接
	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}

	aiData.CurrentState = nil
end

-- ==================== 私有变量 ====================

local activeAIs = {}
local updateConnection = nil
local deathEventConnection = nil
local accumulatedTime = 0
local isInitialized = false

-- ==================== AIData数据结构 ====================

--[[
AIData = {
    UnitModel = Model,
    Humanoid = Humanoid,
    HumanoidRootPart = Part,
    IsActive = boolean,
    LastUpdateTime = number,

    -- 动画状态（V1.5.5重构）
    CurrentState = string,               -- 当前动画状态: "MOVE"/"IDLE"/"ATTACK"
    LastState = string,                  -- 上次动画状态
    Tracks = {                           -- 动画轨道表
        Move = AnimationTrack|nil,
        Idle = AnimationTrack|nil,
        Attack = AnimationTrack|nil,
    },
    AnimationConnections = {},           -- 动画事件连接

    -- 其他
    LastDesiredDirection = Vector3|nil,
}
]]

-- ==================== 距离策略模块 ====================

local UnitAIRangePolicy = {}

function UnitAIRangePolicy.GetDockingDistance(unitState, targetState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		return unitState.AttackRange * BattleConfig.RANGED_DOCKING_RATIO
	else
		local attackerRoot = unitState.UnitInstance:FindFirstChild("HumanoidRootPart")
		if not attackerRoot then
			return unitState.AttackRange
		end

		local attackerDepth = attackerRoot.Size.Z
		local targetDepth = 5

		if targetState and targetState.UnitInstance then
			local targetRoot = targetState.UnitInstance:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				targetDepth = targetRoot.Size.Z
			end
		end

		local contactDistance = (attackerDepth + targetDepth) * 0.5
		local desiredDistance = math.max(contactDistance - BattleConfig.CONTACT_BUFFER, 0)

		local combatProfile = UnitConfig.GetCombatProfile(unitState.UnitId)
		local contactOffset = (combatProfile and combatProfile.ContactOffset) or 0

		return math.max(
			math.min(unitState.AttackRange - BattleConfig.ATTACK_RANGE_TOLERANCE, desiredDistance),
			BattleConfig.MIN_DOCKING_DISTANCE
		) + contactOffset
	end
end

function UnitAIRangePolicy.ShouldEnterAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		local threshold = unitState.AttackRange * BattleConfig.RANGED_ENTER_ATTACK_RATIO
		return distance <= threshold
	else
		local threshold = unitState.AttackRange + BattleConfig.ATTACK_RANGE_TOLERANCE
		return distance <= threshold
	end
end

function UnitAIRangePolicy.ShouldExitAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		local threshold = unitState.AttackRange * BattleConfig.RANGED_EXIT_ATTACK_RATIO
		return distance > threshold
	else
		local threshold = unitState.AttackRange + BattleConfig.ATTACK_RANGE_TOLERANCE + BattleConfig.MOVE_STOP_TOLERANCE
		return distance > threshold
	end
end

-- ==================== 工具函数 ====================

local function GetDistance(model1, model2)
	local part1 = model1:FindFirstChild("HumanoidRootPart") or model1.PrimaryPart
	local part2 = model2:FindFirstChild("HumanoidRootPart") or model2.PrimaryPart

	if not part1 or not part2 then
		return math.huge
	end

	return (part1.Position - part2.Position).Magnitude
end

local function EnsureStopped(unitModel, aiData)
	if not aiData or not aiData.Humanoid or not aiData.HumanoidRootPart then
		return
	end

	aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
end

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

	if lookDistance > 0.01 then
		lookVector = lookVector.Unit
		aiData.HumanoidRootPart.CFrame = CFrame.new(
			aiData.HumanoidRootPart.Position,
			aiData.HumanoidRootPart.Position + lookVector
		)
		aiData.LastDesiredDirection = lookVector
		return true
	end

	return false
end

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

-- ==================== 状态处理函数（重构版） ====================

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
		-- 无目标时播放Idle
		AnimationController.SwitchToIdle(unitModel, aiData, state)
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
		-- 目标失效，切换到Idle
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		return
	end

	-- 确保播放移动动画
	AnimationController.SwitchToMove(unitModel, aiData, state)

	-- 检查距离
	local distance = GetDistance(unitModel, target)

	-- 远程单位提前停止策略
	local isRanged = UnitConfig.IsRangedUnit(state.UnitId)
	if isRanged then
		local targetState = CombatSystem.GetUnitState(target)
		local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

		if distance <= dockingDistance + 4 then
			DebugLog(string.format("%s (远程) 接近停靠距离(%.1f <= %.1f+4)，提前停止",
				state.UnitId, distance, dockingDistance))
			EnsureStopped(unitModel, aiData)

			if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
				LogStateChange(state.UnitId, "MOVING", "ATTACKING", string.format("提前停止后距离符合攻击条件(%.1f)", distance))
				-- 进入攻击状态，停止移动动画即可，不需要立即播放Idle
				-- Idle会在攻击动画结束后自动播放
				if aiData.Tracks.Move then
					SafeStopAnimation(aiData.Tracks.Move)
					aiData.Tracks.Move = nil
				end
				return
			end
		end
	end

	-- 判断是否应该进入攻击
	if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
		EnsureStopped(unitModel, aiData)

		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
		LogStateChange(state.UnitId, "MOVING", "ATTACKING", string.format("距离%.1f <= 阈值", distance))

		-- 关键修复：进入攻击状态时，只停止移动动画，不要立即播放Idle
		-- Idle会在攻击动画结束后自动播放
		if aiData.Tracks.Move then
			SafeStopAnimation(aiData.Tracks.Move)
			aiData.Tracks.Move = nil
		end
	else
		-- 继续移动到目标
		UnitAI.MoveToTarget(unitModel, target, aiData, state)
	end
end

--[[
处理ATTACKING状态：攻击目标（重构版）
核心逻辑：
1. 如果Tracks.Attack为空 且 CanAttack()为true → 触发攻击
2. 如果Tracks.Attack不为空 → 正在播放攻击动画，等待结束
3. 如果Tracks.Attack为空 且 CanAttack()为false → 冷却中，维持Idle
4. 如果距离脱离 → 切回MOVING
]]
local function HandleAttacking(unitModel, aiData, state)
	-- 验证目标
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		LogStateChange(state.UnitId, "ATTACKING", "SEEKING", "目标失效")
		-- 切换到Idle
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		return
	end

	-- 检查距离
	local distance = GetDistance(unitModel, target)

	-- 判断是否应该退出攻击
	if UnitAIRangePolicy.ShouldExitAttack(distance, state) then
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		LogStateChange(state.UnitId, "ATTACKING", "MOVING", string.format("距离%.1f > 脱离阈值", distance))

		-- 关键修复：脱离攻击状态，切换到Move
		AnimationController.SwitchToMove(unitModel, aiData, state)
		return
	end

	-- 保持静止，面向目标
	EnsureStopped(unitModel, aiData)
	OrientTowardsTarget(aiData, target)

	-- 核心修复：攻击逻辑
	-- 情况1：正在播放攻击动画 → 什么都不做，等待动画结束回调
	if aiData.Tracks.Attack and aiData.Tracks.Attack.IsPlaying then
		-- 攻击动画播放中，保持等待
		return
	end

	-- 情况2：冷却中（CanAttack()为false） → 维持Idle动画
	if not CombatSystem.CanAttack(unitModel) then
		-- 确保Idle动画在播放
		if aiData.CurrentState ~= AnimationState.IDLE then
			AnimationController.SwitchToIdle(unitModel, aiData, state)
		end
		return
	end

	-- 情况3：可以攻击（CanAttack()为true 且 没有攻击动画在播） → 触发新一轮攻击
	UnitAI.TriggerAttack(unitModel, target, state, aiData)
end

-- ==================== AI更新 ====================

local function UpdateAllAIs()
	local currentTime = tick()

	for unitModel, aiData in pairs(activeAIs) do
		if not CombatSystem.IsUnitAlive(unitModel) then
			continue
		end

		if not aiData.IsActive then
			continue
		end

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

function UnitAI.Initialize()
	if isInitialized then
		WarnLog("AI系统已经初始化过了")
		return true
	end

	DebugLog("正在初始化AI系统...")

	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulatedTime = accumulatedTime + dt
		if accumulatedTime >= BattleConfig.AI_BATCH_UPDATE_INTERVAL then
			UpdateAllAIs()
			accumulatedTime = 0
		end
	end)

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

	local aiData = {
		UnitModel = unitModel,
		Humanoid = humanoid,
		HumanoidRootPart = rootPart,
		IsActive = true,
		LastUpdateTime = 0,

		-- 动画状态（V1.5.5重构）
		CurrentState = nil,
		LastState = nil,
		Tracks = {},
		AnimationConnections = {},

		LastDesiredDirection = nil,
	}

	activeAIs[unitModel] = aiData

	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		humanoid.WalkSpeed = state.MoveSpeed
	end

	local unitId = state and state.UnitId or "Unknown"
	DebugLog(string.format("启动AI: %s", unitId))

	task.defer(function()
		if not aiData.IsActive then
			return
		end

		local target = UnitAI.FindNearestEnemy(unitModel)

		if target then
			CombatSystem.SetTarget(unitModel, target)
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
			LogStateChange(unitId, "IDLE", "MOVING", "AI启动，发现目标")
			-- AI启动时播放移动动画
			if state then
				AnimationController.SwitchToMove(unitModel, aiData, state)
			end
		else
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
			-- 无目标时播放Idle
			if state then
				AnimationController.SwitchToIdle(unitModel, aiData, state)
			end
		end
	end)

	return true
end

function UnitAI.StopAI(unitModel, skipMoveTo)
	local aiData = activeAIs[unitModel]

	if aiData then
		aiData.IsActive = false

		-- 停止所有动画
		AnimationController.StopAllAnimations(aiData)

		-- 停止移动（可选跳过，用于死亡流程避免把尸体"扶正"）
		if not skipMoveTo then
			if aiData.Humanoid and aiData.HumanoidRootPart then
				aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
			end
		end

		activeAIs[unitModel] = nil

		DebugLog("停止AI")
	end
end

function UnitAI.UpdateAI(unitModel, aiData)
	local state = CombatSystem.GetUnitState(unitModel)

	if not state or not state.IsAlive then
		UnitAI.StopAI(unitModel)
		return
	end

	local aiState = state.State

	if aiState == BattleConfig.AIState.IDLE or aiState == BattleConfig.AIState.SEEKING then
		HandleSeeking(unitModel, aiData, state)

	elseif aiState == BattleConfig.AIState.MOVING then
		HandleMoving(unitModel, aiData, state)

	elseif aiState == BattleConfig.AIState.ATTACKING then
		HandleAttacking(unitModel, aiData, state)
	end
end

function UnitAI.FindNearestEnemy(unitModel)
	local enemy, distance = UnitManager.GetClosestEnemy(unitModel, BattleConfig.TARGET_SEARCH_RANGE)
	return enemy
end

function UnitAI.MoveToTarget(unitModel, target, aiData, state)
	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart

	if not targetPart then
		return
	end

	local myPos = aiData.HumanoidRootPart.Position
	local targetPos = targetPart.Position

	local offset = targetPos - myPos
	local currentDistance = offset.Magnitude

	if currentDistance < 0.1 then
		DebugLog(string.format("%s 距离过近(%.3f)，停止移动避免零向量", state.UnitId, currentDistance))
		EnsureStopped(unitModel, aiData)

		if aiData.LastDesiredDirection then
			aiData.HumanoidRootPart.CFrame = CFrame.new(
				aiData.HumanoidRootPart.Position,
				aiData.HumanoidRootPart.Position + aiData.LastDesiredDirection
			)
		end
		return
	end

	local targetState = CombatSystem.GetUnitState(target)
	local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

	local moveDistance = currentDistance - dockingDistance

	if moveDistance <= 0.5 then
		DebugLog(string.format("%s 已到达停靠范围，当前距离=%.1f，停靠距离=%.1f",
			state.UnitId, currentDistance, dockingDistance))
		EnsureStopped(unitModel, aiData)
		return
	end

	local direction = offset.Unit

	aiData.LastDesiredDirection = direction

	local moveTarget = targetPos - direction * dockingDistance

	local distanceToMoveTarget = (moveTarget - myPos).Magnitude
	if distanceToMoveTarget < 0.5 then
		DebugLog(string.format("%s 移动距离过小(%.2f)，停止避免抖动", state.UnitId, distanceToMoveTarget))
		EnsureStopped(unitModel, aiData)
		return
	end

	aiData.Humanoid:MoveTo(moveTarget)

	local unitType = UnitConfig.IsRangedUnit(state.UnitId) and "远程" or "近战"
	DebugLog(string.format("%s (%s) 移动中，当前距离=%.1f，停靠距离=%.1f，需移动=%.1f",
		state.UnitId, unitType, currentDistance, dockingDistance, moveDistance))
end

--[[
触发攻击（新函数，取代原AttackTarget）
职责：
1. 检查是否可以攻击
2. 调用BeginAttack进入攻击阶段
3. 调用AnimationController.PlayAttackAnimation播放攻击动画
4. 动画结束后由回调自动切换到Idle
]]
function UnitAI.TriggerAttack(unitModel, target, state, aiData)
	-- 检查攻击冷却
	if not CombatSystem.CanAttack(unitModel) then
		return
	end

	-- 面向目标
	OrientTowardsTarget(aiData, target)

	-- 开始攻击（进入Attacking阶段）
	local success = CombatSystem.BeginAttack(unitModel, target)
	if not success then
		return
	end

	-- 定义伤害回调
	local function onDamageCallback(unitModel, target, isRangedUnit)
		if isRangedUnit then
			CombatSystem.OnRangedDamageEvent(unitModel, target)
		else
			CombatSystem.OnDamageEvent(unitModel)
		end
	end

	-- 播放攻击动画
	-- 动画结束后会自动切换到Idle（在AnimationController.PlayAttack的回调中处理）
	AnimationController.PlayAttack(unitModel, aiData, state, target, onDamageCallback)
end

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

				-- 目标死亡，停止攻击动画
				if aiData.Tracks.Attack then
					SafeStopAnimation(aiData.Tracks.Attack)
					aiData.Tracks.Attack = nil
				end
			end
		end
	end
end

function UnitAI.ClearBattleAIs(battleId)
	for unitModel, aiData in pairs(activeAIs) do
		local state = CombatSystem.GetUnitState(unitModel)

		if not state or (state and state.BattleId == battleId) then
			UnitAI.StopAI(unitModel)
		end
	end

	DebugLog("已清理战斗", battleId, "的所有AI")
end

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
播放死亡动画（供CombatSystem调用）- 兼容旧版接口
]]
function UnitAI.PlayDeathAnimation(unitModel, animationId)
	if not unitModel or not unitModel:IsA("Model") then
		return nil
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	return CreateAndPlayAnimation(humanoid, animationId, false)
end

--[[
开始死亡动画流程（V1.5.6简化版）
职责：
1. 打断当前所有动画
2. 禁用Animate脚本
3. 播放死亡动画
4. 动画结束后锁定终帧姿势
5. 固定2.9秒后销毁

@param unitModel - 兵种模型
@param animationId - 死亡动画ID
@param unitId - 单位ID（可选，用于日志显示）
@return nil - 不再返回任何值
]]
function UnitAI.BeginDeathAnimation(unitModel, animationId, unitId)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("BeginDeathAnimation失败: unitModel无效")
		return
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		WarnLog("BeginDeathAnimation失败: 找不到Humanoid或HumanoidRootPart")
		return
	end

	-- 获取单位名称用于日志
	local unitName = unitId or unitModel.Name or "Unknown"

	DebugLog(string.format("[%s] 开始死亡动画流程, 动画ID: %s", unitName, animationId or "nil"))

	-- 步骤1: 打断当前所有动画
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = unitModel:FindFirstChildOfClass("Animator")
	end

	if animator then
		-- 停止所有正在播放的动画轨道
		local playingTracks = animator:GetPlayingAnimationTracks()
		for _, track in ipairs(playingTracks) do
			pcall(function()
				track:Stop(0)  -- 立即停止，无淡出
			end)
		end
		DebugLog(string.format("[%s] 已打断 %d 个正在播放的动画", unitName, #playingTracks))
	end

	-- 步骤2: 禁用Animate脚本，防止默认动画覆盖死亡姿势
	local animateScript = unitModel:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") then
		animateScript.Enabled = false
		DebugLog(string.format("[%s] 已禁用Animate脚本", unitName))
	end

	-- 步骤3: 设置AutoRotate=false，防止角色自动旋转
	pcall(function()
		humanoid.AutoRotate = false
	end)

	-- 步骤4: 播放死亡动画
	if animationId and animationId ~= "" and animationId ~= "0" then
		DebugLog(string.format("[%s] 正在加载死亡动画... (ID: %s)", unitName, animationId))
		local animTrack = CreateAndPlayAnimation(humanoid, animationId, false)

		if animTrack then
			DebugLog(string.format("[%s] ✅ 死亡动画播放成功", unitName))

			-- 延迟0.1秒设置Physics状态，让动画先播放
			task.delay(0.1, function()
				pcall(function()
					if humanoid and humanoid.Parent then
						humanoid:ChangeState(Enum.HumanoidStateType.Physics)
						DebugLog(string.format("[%s] 已设置Physics状态", unitName))
					end
				end)
			end)

			-- 在2.7秒时锁定动画终帧（留0.2秒缓冲）
			task.delay(2.7, function()
				pcall(function()
					if animTrack and animTrack.IsPlaying then
						animTrack:AdjustSpeed(0)  -- 速度设为0，冻结姿势
						DebugLog(string.format("[%s] 死亡动画已锁定在终帧", unitName))
					end
				end)
			end)
		else
			WarnLog(string.format("[%s] ❌ 死亡动画加载失败! 动画ID可能无效: %s", unitName, animationId))
			-- 动画加载失败，直接设置Physics状态倒地
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
	else
		DebugLog(string.format("[%s] 无死亡动画配置，直接倒地", unitName))
		-- 无动画配置时，直接设置为倒地状态
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
end

return UnitAI
