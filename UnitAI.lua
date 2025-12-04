--[[
脚本名称: UnitAI (V4.5重构版)
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitAI
版本: V4.5 - 与PathService保持一致的宽松位移检测

V4.5更新内容：
1. ✅ 提高最小位移阈值：0.3→0.5 studs
2. ✅ 降低容差系数：0.25→0.2（更宽松）
3. ✅ 提高卡住次数阈值：2→3次（约1.5秒）
4. ✅ 延长重寻路冷却：0.8→1.5秒
5. ✅ 与PathService V4.5保持参数一致

重构要点（参考重构指南）：
1. ✅ 移除HasLineOfSight的Raycast，改用Blockcast检测体积碰撞
2. ✅ 简化HandleMoving逻辑：If not path then RequestPath, If path then FollowWaypoint
3. ✅ 添加分离力机制防止兵种重叠
4. ✅ 移除复杂的卡住检测，依赖简单的超时机制
5. ✅ 状态机只负责状态切换，不做复杂决策

核心改进：
- Blockcast检测前方障碍物（宽度检测，不再是细射线）
- 只有距离<10 studs且无障碍才直线移动，否则一律寻路
- 分离力让重叠的兵慢慢推开
- 状态机简洁：SEEKING找目标→MOVING走路→ATTACKING打架
- V4.4新增：智能位移检测，避免拥堵时误判卡住
]]

local UnitAI = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- 引用系统
local CombatSystem = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CombatSystem")) :: any
local UnitManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("UnitManager")) :: any
local PathService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PathService")) :: any

-- ==================== 配置常量（V3.0新增）====================

local MOVEMENT_CONFIG = {
	-- 直线移动的最大距离（超过这个距离一律寻路）
	MAX_DIRECT_MOVE_DISTANCE = 10,

	-- Blockcast检测宽度（兵种体宽）
	BLOCKCAST_WIDTH = 3,
	BLOCKCAST_HEIGHT = 4,

	-- 分离力配置
	SEPARATION_RADIUS = 3,        -- 触发分离的距离
	SEPARATION_FORCE = 2,         -- 分离力强度
	SEPARATION_UPDATE_INTERVAL = 0.1,  -- 分离力更新间隔

	-- MoveTo节流
	MOVETO_THROTTLE_INTERVAL = 0.3,  -- 相同目标的MoveTo间隔
	MOVETO_POSITION_THRESHOLD = 1.0,  -- 位置变化阈值

	-- V4.5修改：路径模式位移检测配置（更宽松，与PathService保持一致）
	PATH_DISPLACEMENT_CHECK_INTERVAL = 0.5,  -- 位移检测间隔（秒）
	PATH_STUCK_MIN_DISTANCE = 0.5,           -- 提高到0.5 studs
	PATH_STUCK_TOLERANCE = 0.2,              -- 降低到0.2（更宽松）
	PATH_STUCK_THRESHOLD = 3,                -- 提高到3次（约1.5秒）才重寻路
	PATH_MIN_DISTANCE_FOR_CHECK = 5,         -- 最小检测距离：离目标太近就不检测了
	PATH_REPATH_COOLDOWN = 1.5,              -- 延长到1.5秒
}

-- ==================== 调试日志 ====================

local function DebugLog(...)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitAI-V3]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[UnitAI-V3]", ...)
end

-- ==================== 动画相关（保留原有逻辑）====================

local AnimationState = {
	MOVE = "MOVE",
	IDLE = "IDLE",
	ATTACK = "ATTACK",
}

-- 创建并播放动画
local function CreateAndPlayAnimation(humanoid, animationId, looped, priority)
	if not humanoid or not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	local animIdStr = tostring(animationId)
	if not tonumber(animIdStr) then
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
	animation.AnimationId = "rbxassetid://" .. animIdStr

	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not animationTrack then
		animation:Destroy()
		return nil
	end

	if priority then
		animationTrack.Priority = priority
	end
	animationTrack.Looped = looped or false

	pcall(function()
		animationTrack:Play()
	end)

	if looped then
		animationTrack.Stopped:Connect(function()
			if animation and animation.Parent then
				animation:Destroy()
			end
		end)
	else
		task.delay(5, function()
			if animation and animation.Parent then
				animation:Destroy()
			end
		end)
	end

	return animationTrack
end

local function SafeStopAnimation(animationTrack)
	if animationTrack and animationTrack.IsPlaying then
		pcall(function()
			animationTrack:Stop()
		end)
	end
end

-- 动画控制器（简化版）
local AnimationController = {}

function AnimationController.SwitchToMove(unitModel, aiData, state)
	if aiData.CurrentAnimState == AnimationState.MOVE and
	   aiData.Tracks.Move and aiData.Tracks.Move.IsPlaying then
		return
	end

	if aiData.Tracks.Idle then
		SafeStopAnimation(aiData.Tracks.Idle)
		aiData.Tracks.Idle = nil
	end
	if aiData.Tracks.Attack then
		SafeStopAnimation(aiData.Tracks.Attack)
		aiData.Tracks.Attack = nil
	end

	local animId = UnitConfig.GetMoveAnimationId(state.UnitId)
	if animId and animId ~= "" then
		local track = CreateAndPlayAnimation(aiData.Humanoid, animId, true, Enum.AnimationPriority.Movement)
		if track then
			aiData.Tracks.Move = track
			aiData.CurrentAnimState = AnimationState.MOVE
		end
	else
		aiData.CurrentAnimState = AnimationState.MOVE
	end
end

function AnimationController.SwitchToIdle(unitModel, aiData, state)
	if aiData.CurrentAnimState == AnimationState.IDLE and
	   aiData.Tracks.Idle and aiData.Tracks.Idle.IsPlaying then
		return
	end

	if aiData.Tracks.Attack and aiData.Tracks.Attack.IsPlaying then
		return  -- 不打断攻击动画
	end

	if aiData.Tracks.Move then
		SafeStopAnimation(aiData.Tracks.Move)
		aiData.Tracks.Move = nil
	end

	local animId = UnitConfig.GetIdleAnimationId(state.UnitId)
	if animId and animId ~= "" then
		if not aiData.Tracks.Idle or not aiData.Tracks.Idle.IsPlaying then
			local track = CreateAndPlayAnimation(aiData.Humanoid, animId, true, Enum.AnimationPriority.Idle)
			if track then
				aiData.Tracks.Idle = track
				aiData.CurrentAnimState = AnimationState.IDLE
			end
		else
			aiData.CurrentAnimState = AnimationState.IDLE
		end
	else
		aiData.CurrentAnimState = AnimationState.IDLE
	end
end

function AnimationController.PlayAttack(unitModel, aiData, state, target, onDamageCallback)
	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}

	local animationId = UnitConfig.GetAttackAnimationId(state.UnitId)
	local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)
	local isRangedUnit = UnitConfig.IsRangedUnit(state.UnitId)
	local damageEventFired = false

	if aiData.Tracks.Move then
		SafeStopAnimation(aiData.Tracks.Move)
		aiData.Tracks.Move = nil
	end
	if aiData.Tracks.Idle then
		SafeStopAnimation(aiData.Tracks.Idle)
		aiData.Tracks.Idle = nil
	end

	if animationId and animationId ~= "" and combatProfile.UseAnimationEvent then
		local animTrack = CreateAndPlayAnimation(aiData.Humanoid, animationId, false, Enum.AnimationPriority.Action)

		if animTrack then
			aiData.Tracks.Attack = animTrack
			aiData.CurrentAnimState = AnimationState.ATTACK

			local eventName = combatProfile.AnimationEventName or "Damage"

			local damageConnection = animTrack:GetMarkerReachedSignal(eventName):Connect(function()
				if damageEventFired then return end
				damageEventFired = true

				if onDamageCallback then
					onDamageCallback(unitModel, target, isRangedUnit)
				end
			end)
			table.insert(aiData.AnimationConnections, damageConnection)

			-- 兜底伤害
			local fallbackDelay = state.AttackSpeed * (BattleConfig.ANIMATION_FALLBACK_RATIO or 0.5)
			task.delay(fallbackDelay, function()
				if damageEventFired then return end
				if not aiData.IsActive or not unitModel.Parent then return end
				if CombatSystem.GetAttackPhase(unitModel) ~= BattleConfig.AttackPhase.ATTACKING then return end

				damageEventFired = true
				if onDamageCallback then
					onDamageCallback(unitModel, target, isRangedUnit)
				end
			end)

			local stoppedConnection = animTrack.Stopped:Connect(function()
				for _, conn in ipairs(aiData.AnimationConnections) do
					if conn and conn.Connected then
						conn:Disconnect()
					end
				end
				aiData.AnimationConnections = {}
				aiData.Tracks.Attack = nil

				if aiData.IsActive and unitModel.Parent and CombatSystem.IsUnitAlive(unitModel) then
					local latestState = CombatSystem.GetUnitState(unitModel)
					if latestState then
						AnimationController.SwitchToIdle(unitModel, aiData, latestState)
					end
				end
			end)
			table.insert(aiData.AnimationConnections, stoppedConnection)

			return true
		end
	end

	-- 无动画配置，使用回退
	local fallbackDelay = state.AttackSpeed * (BattleConfig.ANIMATION_FALLBACK_RATIO or 0.5)
	task.delay(fallbackDelay, function()
		if unitModel and unitModel.Parent and not damageEventFired then
			if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
				damageEventFired = true
				if onDamageCallback then
					onDamageCallback(unitModel, target, isRangedUnit)
				end
			end
		end
	end)

	return true
end

function AnimationController.StopAllAnimations(aiData)
	for _, track in pairs(aiData.Tracks) do
		if track and track.IsPlaying then
			pcall(function() track:Stop(0.1) end)
		end
	end
	aiData.Tracks = {}

	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}
	aiData.CurrentAnimState = nil
end

-- ==================== 私有变量 ====================

local activeAIs = {}
local updateConnection = nil
local deathEventConnection = nil
local accumulatedTime = 0
local isInitialized = false
local lastSeparationUpdate = 0

local AIMode = {
	MARCH = "MarchMode",
	COMBAT = "CombatMode",
}

-- ==================== V3.0核心改进：Blockcast障碍检测 ====================

--[[
使用Blockcast检测前方是否有障碍物
比Raycast更准确，因为考虑了兵种的体积宽度

V3.1修复：
1. 不再抬高起点，直接从RootPart中心发射，确保能检测到矮障碍物
2. 增加检测盒高度到5，覆盖全身高度
3. 缩短检测距离，留出缓冲避免检测到目标本身

@param unitModel Model - 攻击方单位
@param targetModel Model - 目标单位
@return boolean - true表示路径畅通，false表示有障碍
]]
local function IsPathClear(unitModel, targetModel)
	local root = unitModel:FindFirstChild("HumanoidRootPart")
	-- 目标可能是 Model 也可能是 Part
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart

	if not root or not targetRoot then
		return false
	end

	-- V3.1修复: 不要抬高起点，直接从 RootPart 中心发射，确保能检测到地面矮障碍物
	local startPos = root.Position
	local endPos = targetRoot.Position
	local direction = endPos - startPos
	local distance = direction.Magnitude

	-- 短距离直接返回true
	if distance < 3 then
		return true
	end

	-- V3.1修复: 调整检测盒大小
	-- 宽度=3(兵种宽), 高度=5(覆盖全身，确保能检测到矮墙), 深度=1
	local size = Vector3.new(
		MOVEMENT_CONFIG.BLOCKCAST_WIDTH,
		5,  -- 增加高度，确保覆盖矮墙
		1
	)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- 排除自己、目标和所有兵种
	local filterList = {unitModel, targetModel}
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		table.insert(filterList, unitsFolder)
	end
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	-- V3.1修复: 缩短检测距离，留出一点缓冲，避免检测到目标本身
	local detectDistance = math.max(1, distance - 3)

	-- 使用 CFrame 构建检测方向（只在水平面上看向目标，避免Y轴影响）
	local cframe = CFrame.lookAt(startPos, Vector3.new(endPos.X, startPos.Y, endPos.Z))

	-- 执行检测
	local result = workspace:Blockcast(cframe, size, direction.Unit * detectDistance, rayParams)

	if result then
		-- 如果打到了任何 CanCollide 的东西，视为障碍
		if result.Instance.CanCollide then
			DebugLog(string.format("Blockcast检测到障碍: %s (距离: %.1f)", result.Instance.Name, result.Distance))
			return false
		end
	end

	return true
end

-- ==================== V3.0核心改进：分离力机制 ====================

--[[
对所有兵种施加分离力，防止重叠
每隔一定时间执行一次，避免每帧计算
]]
local function ApplySeparationForces()
	local now = tick()
	if now - lastSeparationUpdate < MOVEMENT_CONFIG.SEPARATION_UPDATE_INTERVAL then
		return
	end
	lastSeparationUpdate = now

	-- 收集所有活跃单位的位置
	local unitPositions = {}
	for unitModel, aiData in pairs(activeAIs) do
		if aiData.IsActive and unitModel.Parent then
			local root = unitModel:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(unitPositions, {
					model = unitModel,
					position = root.Position,
					root = root,
					aiData = aiData,
				})
			end
		end
	end

	-- 计算分离力
	for i, unit1 in ipairs(unitPositions) do
		local totalForce = Vector3.zero
		local neighborCount = 0

		for j, unit2 in ipairs(unitPositions) do
			if i ~= j then
				local diff = unit1.position - unit2.position
				local distXZ = math.sqrt(diff.X^2 + diff.Z^2)  -- 只计算水平距离

				if distXZ < MOVEMENT_CONFIG.SEPARATION_RADIUS and distXZ > 0.3 then
					-- 越近推力越大
					local pushDir = Vector3.new(diff.X, 0, diff.Z)
					if pushDir.Magnitude > 0.1 then
						pushDir = pushDir.Unit
						local forceMagnitude = (MOVEMENT_CONFIG.SEPARATION_RADIUS - distXZ) / MOVEMENT_CONFIG.SEPARATION_RADIUS
						totalForce = totalForce + pushDir * forceMagnitude
						neighborCount = neighborCount + 1
					end
				end
			end
		end

		-- 施加分离力
		if neighborCount > 0 and totalForce.Magnitude > 0.1 then
			local finalForce = totalForce.Unit * MOVEMENT_CONFIG.SEPARATION_FORCE

			-- 通过速度施加力（而非MoveTo）
			pcall(function()
				local currentVel = unit1.root.AssemblyLinearVelocity
				unit1.root.AssemblyLinearVelocity = Vector3.new(
					currentVel.X + finalForce.X,
					currentVel.Y,
					currentVel.Z + finalForce.Z
				)
			end)
		end
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

--[[
节流MoveTo：避免重复发送相同位置的移动命令
]]
local function ThrottledMoveTo(aiData, targetPos)
	if not aiData or not aiData.Humanoid or not targetPos then
		return false
	end

	local now = tick()

	if aiData.LastMoveToPos then
		local distDiff = (targetPos - aiData.LastMoveToPos).Magnitude
		local timeDiff = now - (aiData.LastMoveToTick or 0)

		-- 目标位置变化很小且时间间隔短，跳过
		if distDiff < MOVEMENT_CONFIG.MOVETO_POSITION_THRESHOLD and
		   timeDiff < MOVEMENT_CONFIG.MOVETO_THROTTLE_INTERVAL then
			return false
		end
	end

	aiData.Humanoid:MoveTo(targetPos)
	aiData.LastMoveToPos = targetPos
	aiData.LastMoveToTick = now
	return true
end

--[[
朝向目标（增加角度容差）
]]
local function OrientTowardsTarget(aiData, target)
	if not aiData or not aiData.HumanoidRootPart then
		return false
	end

	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if not targetPart then
		return false
	end

	local myPos = aiData.HumanoidRootPart.Position
	local targetPos = targetPart.Position
	local lookVector = Vector3.new(targetPos.X, myPos.Y, targetPos.Z) - myPos

	if lookVector.Magnitude > 0.1 then
		local currentLook = aiData.HumanoidRootPart.CFrame.LookVector
		local dot = currentLook:Dot(lookVector.Unit)

		-- 角度偏差超过5度才旋转
		if dot < 0.996 then
			local newCFrame = CFrame.lookAt(myPos, myPos + lookVector)
			aiData.HumanoidRootPart.CFrame = newCFrame
			return true
		end
	end

	return false
end

-- ==================== 距离策略模块 ====================

local UnitAIRangePolicy = {}

function UnitAIRangePolicy.GetDockingDistance(unitState, targetState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		return unitState.AttackRange * (BattleConfig.RANGED_DOCKING_RATIO or 0.8)
	else
		local attackerModel = unitState.UnitInstance
		if not attackerModel then
			return unitState.AttackRange
		end

		local attackerSize = attackerModel:GetExtentsSize()
		local attackerDepth = attackerSize.Z

		local targetDepth = attackerDepth
		if targetState and targetState.UnitInstance then
			local targetSize = targetState.UnitInstance:GetExtentsSize()
			targetDepth = targetSize.Z
		end

		local contactOffset = UnitConfig.GetContactOffset(unitState.UnitId) or 0
		local contactDistance = (attackerDepth + targetDepth) * 0.5
		local desiredDistance = contactDistance - contactOffset + (BattleConfig.CONTACT_BUFFER or 0.5)

		return math.max(desiredDistance, BattleConfig.MIN_DOCKING_DISTANCE or 1)
	end
end

function UnitAIRangePolicy.ShouldEnterAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		local threshold = unitState.AttackRange * (BattleConfig.RANGED_ENTER_ATTACK_RATIO or 0.95)
		return distance <= threshold
	else
		local targetState = nil
		if unitState.CurrentTarget then
			targetState = CombatSystem.GetUnitState(unitState.CurrentTarget)
		end
		local docking = UnitAIRangePolicy.GetDockingDistance(unitState, targetState)
		local threshold = math.min(unitState.AttackRange, docking) + (BattleConfig.ATTACK_ENTER_TOLERANCE or 0.5)
		return distance <= threshold
	end
end

function UnitAIRangePolicy.ShouldExitAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		local threshold = unitState.AttackRange * (BattleConfig.RANGED_EXIT_ATTACK_RATIO or 1.1)
		return distance > threshold
	else
		local targetState = nil
		if unitState.CurrentTarget then
			targetState = CombatSystem.GetUnitState(unitState.CurrentTarget)
		end
		local docking = UnitAIRangePolicy.GetDockingDistance(unitState, targetState)
		local threshold = math.min(unitState.AttackRange, docking) + (BattleConfig.ATTACK_EXIT_TOLERANCE or 1.0)
		return distance > threshold
	end
end

-- ==================== V3.0简化状态处理函数 ====================

--[[
处理SEEKING状态：寻找目标
V3.0简化：找到目标就切换到MOVING，不做复杂的黏滞判断
]]
local function HandleSeeking(unitModel, aiData, state)
	local target = UnitAI.FindNearestEnemy(unitModel)

	if target then
		CombatSystem.SetTarget(unitModel, target)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		DebugLog(string.format("%s SEEKING→MOVING 找到目标", state.UnitId))
	else
		-- 无目标，播放Idle
		AnimationController.SwitchToIdle(unitModel, aiData, state)
	end
end

--[[
处理MOVING状态：移动到目标
V3.0核心简化：
1. 距离<10且无障碍 → 直线移动
2. 否则 → 请求寻路，沿路径走
3. 到达攻击范围 → 切换ATTACKING

V3.1修复：
4. 增加撞墙兜底检测：如果决定直线走但速度为0，强制切换回寻路
]]
local function HandleMoving(unitModel, aiData, state)
	-- 验证目标
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		CombatSystem.ResetAttackPhase(unitModel)
		PathService.ClearPath(unitModel)
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		return
	end

	-- 播放移动动画
	AnimationController.SwitchToMove(unitModel, aiData, state)

	local distance = GetDistance(unitModel, target)
	local targetState = CombatSystem.GetUnitState(target)
	local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

	-- 检查是否到达攻击范围
	if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
		-- 停止移动
		aiData.Humanoid:Move(Vector3.zero, true)
		PathService.ClearPath(unitModel)

		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
		DebugLog(string.format("%s MOVING→ATTACKING 距离=%.1f", state.UnitId, distance))

		if aiData.Tracks.Move then
			SafeStopAnimation(aiData.Tracks.Move)
			aiData.Tracks.Move = nil
		end
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		return
	end

	-- V3.0核心逻辑：选择移动策略
	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if not targetPart then return end

	local myPos = aiData.HumanoidRootPart.Position
	local targetPos = targetPart.Position

	-- 计算停靠点（不要直接走到目标位置）
	local direction = (targetPos - myPos)
	direction = Vector3.new(direction.X, 0, direction.Z)  -- 忽略Y轴
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit
	local moveTargetPos = targetPos - direction * dockingDistance

	-- 决策：直线移动还是寻路
	local shouldUsePath = false

	if distance > MOVEMENT_CONFIG.MAX_DIRECT_MOVE_DISTANCE then
		-- 距离太远，必须寻路
		shouldUsePath = true
	elseif not IsPathClear(unitModel, target) then
		-- 有障碍物，需要寻路
		shouldUsePath = true
	end

	-- ==================== V3.1修复：兜底检测 ====================
	-- 如果上一次决定直走，但速度极慢，说明撞墙了，强制切换寻路
	if not shouldUsePath then
		local velocity = aiData.HumanoidRootPart.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		-- 只有当它应该在动(MoveDirection>0) 但实际没动(speed<0.5) 时
		if aiData.Humanoid.MoveDirection.Magnitude > 0.1 and speed < 0.5 then
			-- 增加积压计数器
			aiData.StuckAccumulator = (aiData.StuckAccumulator or 0) + 1

			-- 连续卡住 5 帧 (约0.1秒)
			if aiData.StuckAccumulator > 5 then
				DebugLog(string.format("⚠️ %s 直线移动卡死(速度0)，强制切换寻路", state.UnitId))
				shouldUsePath = true  -- 强制覆盖决策
				aiData.StuckAccumulator = 0  -- 重置
			end
		else
			aiData.StuckAccumulator = 0
		end
	end
	-- ==================== V3.1修复结束 ====================

	if shouldUsePath then
		-- 使用寻路
		local pathStatus = PathService.GetPathStatus(unitModel)

		-- V4.0修复：同时处理Success和Partial状态
		if pathStatus == "Success" or pathStatus == "Partial" then
			-- 有路径（完整或部分），沿路径走
			local isPartialPath = (pathStatus == "Partial")

			-- ==================== V4.5重构：智能位移检测 ====================
			-- 目标：避免拥堵/战斗时的误判，只在真正卡死时才重寻路
			-- V4.5更新：阈值放宽到0.5，冷却延长到1.5秒，需要3次才确认
			local now = tick()
			local checkInterval = MOVEMENT_CONFIG.PATH_DISPLACEMENT_CHECK_INTERVAL
			local lastCheck = aiData.PathDisplacementCheckTime or 0

			if now - lastCheck >= checkInterval then
				aiData.PathDisplacementCheckTime = now

				-- 1. 检查重寻路冷却
				local lastRepathTime = aiData.LastRepathTriggerTime or 0
				local canRepath = (now - lastRepathTime) >= MOVEMENT_CONFIG.PATH_REPATH_COOLDOWN

				-- 2. 计算实际位移（XZ平面）
				local currentPos = aiData.HumanoidRootPart.Position
				local lastPos = aiData.PathLastCheckPos or currentPos
				local actualDistance = math.sqrt(
					(currentPos.X - lastPos.X)^2 + (currentPos.Z - lastPos.Z)^2
				)
				aiData.PathLastCheckPos = currentPos

				-- 3. 记录距离变化（检查是否在向目标前进）
				local prevDistToTarget = aiData.PrevDistanceToTarget or distance
				local isProgressingToTarget = distance < (prevDistToTarget - 0.1)  -- 距离在减少
				aiData.PrevDistanceToTarget = distance

				-- 4. 智能卡住判定
				-- 只有同时满足以下条件才算真正卡住：
				-- a) 实际位移几乎为0（低于最小阈值）
				-- b) 且距离目标没有在减少
				-- c) 且离目标还有一定距离
				-- d) 且冷却时间已过
				local isReallyStuck = actualDistance < MOVEMENT_CONFIG.PATH_STUCK_MIN_DISTANCE
					and not isProgressingToTarget
					and distance > MOVEMENT_CONFIG.PATH_MIN_DISTANCE_FOR_CHECK
					and canRepath

				if isReallyStuck then
					aiData.PathDisplacementStuckCount = (aiData.PathDisplacementStuckCount or 0) + 1
					DebugLog(string.format("⚠️ %s 疑似卡住: 位移%.2f, 距离%.1f→%.1f, 次数%d",
						state.UnitId, actualDistance, prevDistToTarget, distance, aiData.PathDisplacementStuckCount))

					-- V4.5：需要连续3次（约1.5秒）才确认卡住
					if aiData.PathDisplacementStuckCount >= MOVEMENT_CONFIG.PATH_STUCK_THRESHOLD then
						DebugLog(string.format("🔄 %s 确认卡住，触发重寻路", state.UnitId))
						aiData.PathDisplacementStuckCount = 0
						aiData.LastRepathTriggerTime = now
						aiData.Humanoid:Move(Vector3.zero)  -- 先停下
						PathService.ClearPath(unitModel)
						PathService.ForceRepath(unitModel)
						return  -- 本帧不继续移动，等下一帧重新寻路
					end
				else
					-- 在移动中，重置计数
					if actualDistance > MOVEMENT_CONFIG.PATH_STUCK_MIN_DISTANCE then
						aiData.PathDisplacementStuckCount = 0
					end
				end
			end
			-- ==================== V4.5智能位移检测结束 ====================

			-- 瞬时速度检测（作为快速兜底，但也要检查冷却）
			local velocity = aiData.HumanoidRootPart.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local lastRepathTime = aiData.LastRepathTriggerTime or 0
			local canQuickRepath = (now - lastRepathTime) >= MOVEMENT_CONFIG.PATH_REPATH_COOLDOWN

			if aiData.Humanoid.MoveDirection.Magnitude > 0.1 and speed < 0.3 and canQuickRepath then
				aiData.PathStuckCount = (aiData.PathStuckCount or 0) + 1
				-- 收紧到8帧（约0.13秒）
				if aiData.PathStuckCount > 8 then
					DebugLog(string.format("⚠️ %s 有路径但速度为0，清除路径触发重寻", state.UnitId))
					PathService.ClearPath(unitModel)
					PathService.ForceRepath(unitModel)
					aiData.PathStuckCount = 0
					aiData.LastRepathTriggerTime = now
					aiData.Humanoid:Move(Vector3.zero)
					return
				end
			else
				aiData.PathStuckCount = 0
			end

			if PathService.HasReachedWaypoint(unitModel) then
				if not PathService.AdvancePath(unitModel) then
					-- 路径走完
					if isPartialPath then
						-- ✅ V4.0关键修复：PARTIAL路径走完后，绝对不能直线移动！
						-- 停在最近可达点，等待下一次寻路（NavMesh更新后可能有新路径）
						PathService.ClearPath(unitModel)
						DebugLog(string.format("⚠️ %s PARTIAL路径走完，停在最近可达点等待重寻路", state.UnitId))
						if aiData.Humanoid then
							aiData.Humanoid:Move(Vector3.zero)
						end
						-- 给一个重试冷却
						aiData.LastUpdateTime = tick() + 0.3
						return  -- 直接返回，禁止执行下面的直线移动
					else
						-- SUCCESS路径走完，可以尝试直线移动到停靠点
						PathService.ClearPath(unitModel)
						shouldUsePath = false
					end
				end
			end

			-- V3.0.2修复：只有在shouldUsePath仍为true时才尝试获取下一个路径点
			if shouldUsePath then
				local nextWaypoint = PathService.GetNextWaypoint(unitModel)
				if nextWaypoint then
					ThrottledMoveTo(aiData, nextWaypoint)
					return
				else
					-- 路径点为空
					if isPartialPath then
						-- ✅ V4.0修复：PARTIAL路径点为空，停下等待
						PathService.ClearPath(unitModel)
						if aiData.Humanoid then
							aiData.Humanoid:Move(Vector3.zero)
						end
						aiData.LastUpdateTime = tick() + 0.3
						return
					else
						-- SUCCESS路径点为空，清理并继续直线移动
						PathService.ClearPath(unitModel)
						shouldUsePath = false
					end
				end
			end
		elseif pathStatus == "Computing" or pathStatus == "Queued" then
			-- 路径计算中，原地等待（不要MoveTo目标导致转圈）
			return
		else
			-- 无路径或路径失败，请求新路径
			if not aiData.PathRequested then
				aiData.PathRequested = true

				PathService.RequestPathAsync(unitModel, target, state.UnitId, function(success, pathState)
					aiData.PathRequested = false

					if not aiData.IsActive or not unitModel.Parent then return end

					-- V4.0修复：Success和Partial都可以移动，但Partial需要特殊处理
					if success and pathState and (pathState.Status == "Success" or pathState.Status == "Partial") then
						local nextWaypoint = PathService.GetNextWaypoint(unitModel)
						if nextWaypoint then
							ThrottledMoveTo(aiData, nextWaypoint)
						elseif pathState.Status == "Partial" then
							-- Partial但没有路径点，停下等待
							if aiData.Humanoid then
								aiData.Humanoid:Move(Vector3.zero)
							end
						end
					else
						-- ✅ V4.0修复：寻路失败时，绝对不要直线移动！
						-- 应该停下来，等待下一次 UpdateAI 再次尝试
						DebugLog(string.format("⚠️ %s 寻路失败(NavMesh可能未更新)，原地待命重试", state.UnitId))

						-- 物理刹车
						if aiData.Humanoid then
							aiData.Humanoid:Move(Vector3.zero)
						end

						-- 给一个微小的重试冷却，避免日志刷屏
						aiData.LastUpdateTime = tick() + 0.5
					end
				end)
			end
			return
		end
	end

	-- ✅ V4.0安全检查：到达这里说明shouldUsePath=false且路径是SUCCESS完成的
	-- 如果之前是PARTIAL路径，上面已经return了，不会到达这里
	-- 直线移动到停靠点
	local distanceToTarget = (moveTargetPos - myPos).Magnitude
	if distanceToTarget > 0.5 then
		ThrottledMoveTo(aiData, moveTargetPos)
	end
end

--[[
处理ATTACKING状态：攻击目标
V3.0简化：专注于攻击逻辑，不做复杂的移动判断
]]
local function HandleAttacking(unitModel, aiData, state)
	-- 验证目标
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		CombatSystem.ResetAttackPhase(unitModel)
		PathService.ClearPath(unitModel)
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		return
	end

	local distance = GetDistance(unitModel, target)

	-- 检查是否脱离攻击范围
	if UnitAIRangePolicy.ShouldExitAttack(distance, state) then
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		DebugLog(string.format("%s ATTACKING→MOVING 距离=%.1f 脱离范围", state.UnitId, distance))
		PathService.ClearPath(unitModel)
		AnimationController.SwitchToMove(unitModel, aiData, state)
		return
	end

	-- 朝向目标
	OrientTowardsTarget(aiData, target)

	-- 攻击动画播放中，等待
	if aiData.Tracks.Attack and aiData.Tracks.Attack.IsPlaying then
		return
	end

	-- 冷却中，播放Idle
	if not CombatSystem.CanAttack(unitModel) then
		if not aiData.Tracks.Idle or not aiData.Tracks.Idle.IsPlaying then
			AnimationController.SwitchToIdle(unitModel, aiData, state)
		end
		return
	end

	-- 可以攻击，触发攻击
	UnitAI.TriggerAttack(unitModel, target, state, aiData)
end

-- ==================== AI更新 ====================

local AI_UPDATE_INTERVALS = {
	[BattleConfig.AIState.SEEKING] = 0.5,
	[BattleConfig.AIState.MOVING] = 0.15,  -- 移动状态需要较频繁检查
	[BattleConfig.AIState.ATTACKING] = 0.1,
	[BattleConfig.AIState.IDLE] = 0.8,
}

local function UpdateAllAIs()
	local currentTime = tick()

	-- 应用分离力
	ApplySeparationForces()

	for unitModel, aiData in pairs(activeAIs) do
		-- V3.0.2修复：检查unitModel是否仍在场景中
		if not unitModel or not unitModel.Parent then
			continue
		end

		if not CombatSystem.IsUnitAlive(unitModel) or not aiData.IsActive then
			continue
		end

		-- 行军模式跳过战斗AI
		if aiData.Mode == AIMode.MARCH then
			continue
		end

		local state = CombatSystem.GetUnitState(unitModel)
		if state then
			local updateInterval = AI_UPDATE_INTERVALS[state.State] or 0.2

			if currentTime - (aiData.LastUpdateTime or 0) < updateInterval then
				continue
			end
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
		return true
	end

	DebugLog("正在初始化AI系统(V3.0)...")

	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulatedTime = accumulatedTime + dt
		if accumulatedTime >= (BattleConfig.AI_BATCH_UPDATE_INTERVAL or 0.05) then
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
	DebugLog("AI系统(V3.0)初始化完成")
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
		return false
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return false
	end

	local aiData = {
		UnitModel = unitModel,
		Humanoid = humanoid,
		HumanoidRootPart = rootPart,
		IsActive = true,
		LastUpdateTime = 0,
		Mode = AIMode.COMBAT,
		PathRequested = false,
		LastMoveToPos = nil,
		LastMoveToTick = 0,
		CurrentAnimState = nil,
		Tracks = {},
		AnimationConnections = {},
		-- V4.4更新：位移检测相关
		PathDisplacementCheckTime = 0,
		PathLastCheckPos = nil,
		PathDisplacementStuckCount = 0,
		PrevDistanceToTarget = nil,
		LastRepathTriggerTime = 0,
	}

	activeAIs[unitModel] = aiData

	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		humanoid.WalkSpeed = state.MoveSpeed
	else
		WarnLog("StartAI: 单位没有CombatSystem状态!")
		return false
	end

	-- 停止所有正在播放的动画
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function() track:Stop(0) end)
		end
	end

	-- 禁用Animate脚本
	local animateScript = unitModel:FindFirstChild("Animate", true)
	if animateScript and animateScript:IsA("BaseScript") then
		animateScript.Enabled = false
	end

	-- 设置网络所有权
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	-- 初始寻敌
	task.defer(function()
		if not aiData.IsActive then return end

		local target = UnitAI.FindNearestEnemy(unitModel)
		if target then
			CombatSystem.SetTarget(unitModel, target)
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
			if state then
				AnimationController.SwitchToMove(unitModel, aiData, state)
			end
		else
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
			if state then
				AnimationController.SwitchToIdle(unitModel, aiData, state)
			end
		end
	end)

	DebugLog(string.format("启动AI: %s", state and state.UnitId or unitModel.Name))
	return true
end

function UnitAI.StopAI(unitModel, options)
	local aiData = activeAIs[unitModel]
	if not aiData then return end

	aiData.IsActive = false

	local opts = {}
	if type(options) == "boolean" then
		opts.skipMoveTo = options
	elseif type(options) == "table" then
		opts = options
	end

	AnimationController.StopAllAnimations(aiData)
	PathService.ClearPath(unitModel)

	if not opts.skipMoveTo and aiData.Humanoid and aiData.HumanoidRootPart then
		aiData.Humanoid:Move(Vector3.zero, true)
	end

	activeAIs[unitModel] = nil
	DebugLog("停止AI")
end

function UnitAI.UpdateAI(unitModel, aiData)
	local state = CombatSystem.GetUnitState(unitModel)

	if not state or not state.IsAlive then
		UnitAI.StopAI(unitModel)
		return
	end

	if aiData.Mode == AIMode.MARCH then
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
	local state = CombatSystem.GetUnitState(unitModel)
	if not state then return nil end

	local enemy, distance = UnitManager.GetClosestEnemy(unitModel, BattleConfig.TARGET_SEARCH_RANGE or 100)
	return enemy
end

function UnitAI.TriggerAttack(unitModel, target, state, aiData)
	if not CombatSystem.CanAttack(unitModel) then
		return
	end

	-- 面向目标
	if aiData.HumanoidRootPart and target then
		local targetRoot = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
		if targetRoot then
			local lookVec = targetRoot.Position - aiData.HumanoidRootPart.Position
			lookVec = Vector3.new(lookVec.X, 0, lookVec.Z)
			if lookVec.Magnitude > 0 then
				lookVec = lookVec.Unit
				local pos = aiData.HumanoidRootPart.Position
				aiData.HumanoidRootPart.CFrame = CFrame.lookAt(pos, pos + lookVec)
			end
		end
	end

	local success = CombatSystem.BeginAttack(unitModel, target)
	if not success then return end

	local function onDamageCallback(unitModel, target, isRangedUnit)
		if isRangedUnit then
			CombatSystem.OnRangedDamageEvent(unitModel, target)
		else
			CombatSystem.OnDamageEvent(unitModel)
		end
	end

	AnimationController.PlayAttack(unitModel, aiData, state, target, onDamageCallback)
end

function UnitAI.OnTargetDeath(deadUnit, battleId)
	for unitModel, aiData in pairs(activeAIs) do
		if not aiData.IsActive then continue end

		-- V3.0.2修复：检查unitModel是否仍在场景中
		if not unitModel or not unitModel.Parent then continue end

		local state = CombatSystem.GetUnitState(unitModel)
		if state and state.BattleId == battleId then
			local currentTarget = CombatSystem.GetTarget(unitModel)

			if currentTarget == deadUnit then
				CombatSystem.SetTarget(unitModel, nil)
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
				CombatSystem.ResetAttackPhase(unitModel)

				if aiData.Tracks.Attack then
					SafeStopAnimation(aiData.Tracks.Attack)
					aiData.Tracks.Attack = nil
				end

				PathService.ClearPath(unitModel)
			end
		end
	end
end

function UnitAI.ClearBattleAIs(battleId)
	-- 先收集需要清理的单位，避免迭代时修改表
	local toClear = {}
	for unitModel, aiData in pairs(activeAIs) do
		local state = CombatSystem.GetUnitState(unitModel)

		if not state or (state and state.BattleId == battleId) then
			table.insert(toClear, {
				model = unitModel,
				keepIdle = state and state.IsAlive,
			})
		end
	end

	-- 然后清理
	for _, item in ipairs(toClear) do
		UnitAI.StopAI(item.model, { keepIdle = item.keepIdle })
	end

	PathService.ClearBattlePaths(battleId, CombatSystem.GetUnitState)
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

-- 模式切换
function UnitAI.SetMode(unitModel, mode)
	local aiData = activeAIs[unitModel]
	if not aiData then return false end

	if mode ~= AIMode.MARCH and mode ~= AIMode.COMBAT then
		return false
	end

	aiData.Mode = mode

	if mode == AIMode.MARCH then
		PathService.ClearPath(unitModel)
		aiData.PathRequested = false
	end

	return true
end

function UnitAI.PrepareForCombat(unitModel)
	local aiData = activeAIs[unitModel]
	if not aiData then return false end

	aiData.Mode = AIMode.COMBAT
	PathService.ClearPath(unitModel)

	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		AnimationController.SwitchToIdle(unitModel, aiData, state)
	end

	return true
end

-- 死亡动画相关（保留原有接口）
function UnitAI.PlayDeathAnimation(unitModel, animationId)
	if not unitModel or not unitModel:IsA("Model") then return nil end
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	return CreateAndPlayAnimation(humanoid, animationId, false)
end

function UnitAI.BeginDeathAnimation(unitModel, animationId, unitId)
	-- 保留原有的死亡动画逻辑...
	-- 简化版本
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then return end

	-- 禁用Animate
	local animateScript = unitModel:FindFirstChild("Animate", true)
	if animateScript and animateScript:IsA("BaseScript") then
		animateScript.Enabled = false
	end

	-- 播放死亡动画
	if animationId and animationId ~= "" and animationId ~= "0" then
		local animator = humanoid:FindFirstChild("Animator")
		if animator then
			-- 停止所有动画
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				pcall(function() track:Stop(0) end)
			end

			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. tostring(animationId)

			local success, animTrack = pcall(function()
				return animator:LoadAnimation(animation)
			end)

			if success and animTrack then
				animTrack.Priority = Enum.AnimationPriority.Action4
				animTrack.Looped = false
				pcall(function() animTrack:Play(0) end)

				animTrack.Stopped:Connect(function()
					-- 冻结尸体
					pcall(function()
						humanoid.BreakJointsOnDeath = false
						humanoid.PlatformStand = true
						rootPart.Anchored = true
						rootPart.AssemblyLinearVelocity = Vector3.zero
					end)
				end)

				task.delay(5, function()
					if animation and animation.Parent then
						animation:Destroy()
					end
				end)
			end
		end
	else
		-- 无动画直接冻结
		pcall(function()
			rootPart.Anchored = true
		end)
	end
end

function UnitAI.PlayMoveAnimation(unitModel)
	if not unitModel or not unitModel:IsA("Model") then return end
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local unitId = unitModel:GetAttribute("UnitId") or unitModel.Name
	local moveAnimId = UnitConfig.GetMoveAnimationId(unitId)
	if not moveAnimId or moveAnimId == "" then return end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then return end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function() track:Stop(0.2) end)
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. moveAnimId

	local success, animTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and animTrack then
		animTrack.Looped = true
		animTrack.Priority = Enum.AnimationPriority.Movement
		pcall(function() animTrack:Play() end)
	end

	animation:Destroy()
end

function UnitAI.StopMoveAnimation(unitModel)
	if not unitModel or not unitModel:IsA("Model") then return end
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function() track:Stop(0.2) end)
		end
	end

	local unitId = unitModel:GetAttribute("UnitId") or unitModel.Name
	local idleAnimId = UnitConfig.GetIdleAnimationId(unitId)
	if not idleAnimId or idleAnimId == "" then return end

	if not animator then return end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. idleAnimId

	local success, animTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and animTrack then
		animTrack.Looped = true
		pcall(function() animTrack:Play() end)
	end

	animation:Destroy()
end

function UnitAI.ResetModelTransparency(unitModel)
	if not unitModel then return end
	for _, inst in ipairs(unitModel:GetDescendants()) do
		local orig = inst:GetAttribute("_OrigTrans")
		if orig ~= nil then
			if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
				inst.Transparency = orig
			end
			inst:SetAttribute("_OrigTrans", nil)
		end
	end
end

function UnitAI.ClearAllSurroundData()
	-- V3.0简化：移除围攻系统
end

function UnitAI.ClearTargetSurroundData(targetModel)
	-- V3.0简化：移除围攻系统
end

return UnitAI
