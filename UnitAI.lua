--[[
脚本名称: UnitAI
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitAI
版本: V5.1 - 修复潜在问题版

V5.1更新内容：
1. ✅ 移除对MovementController的无效引用（使用内置移动逻辑）
2. ✅ 与PathService V5.1保持参数一致
3. ✅ 完善代码注释

重构目标（参考寻路逻辑重写方案.lua）：
1. ✅ 简化状态机：SEEKING -> MOVING -> ATTACKING
2. ✅ 内置移动逻辑：直接调用PathService，不依赖MovementController
3. ✅ Blockcast检测：体积检测替代细射线
4. ✅ 清晰的距离策略：远程/近战分开处理
5. ✅ 动画控制：独立模块，不影响AI逻辑

核心改进：
- 状态机只负责状态切换，不做复杂移动逻辑
- 移动交给PathService（内置逻辑，不用MovementController）
- PARTIAL路径正确处理：停在最近可达点
- 拥挤场景不误判卡住

注意：MovementController.lua 是一个可选的独立移动控制器，
本文件使用内置的HandleMoving逻辑，两者可以并存但互不依赖。
如需使用MovementController，请在上层调用方自行整合。
]]

local UnitAI = {}

-- ==================== 依赖服务 ====================

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ==================== 引用配置 ====================

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 引用系统（延迟加载）====================

local CombatSystem = nil
local UnitManager = nil
local PathService = nil

local function LoadSystems()
	if not CombatSystem then
		CombatSystem = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CombatSystem"))
	end
	if not UnitManager then
		UnitManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("UnitManager"))
	end
	if not PathService then
		PathService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PathService"))
	end
	-- 注意：不再加载MovementController，使用内置移动逻辑
end

-- ==================== 配置常量 ====================

local CONFIG = {
	-- 直线移动的最大距离（超过这个距离一律寻路）
	MAX_DIRECT_MOVE_DISTANCE = 10,

	-- Blockcast检测尺寸
	BLOCKCAST_WIDTH = 3,
	BLOCKCAST_HEIGHT = 5,

	-- 分离力配置
	SEPARATION_RADIUS = 3,
	SEPARATION_FORCE = 1.5,
	SEPARATION_INTERVAL = 0.1,

	-- MoveTo节流
	MOVETO_THROTTLE_INTERVAL = 0.25,
	MOVETO_POSITION_THRESHOLD = 1.0,

	-- 卡住检测（与PathService保持一致）
	STUCK_CHECK_INTERVAL = 0.5,
	STUCK_MIN_VELOCITY = 0.5,
	STUCK_COUNT_THRESHOLD = 3,
	REPATH_COOLDOWN = 1.5,
	MIN_DISTANCE_FOR_CHECK = 5,

	-- 调试
	DEBUG_LOGS = false,
}

-- 从BattleConfig读取
if BattleConfig then
	CONFIG.DEBUG_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_LOGS
end

-- ==================== AI模式枚举 ====================

local AIMode = {
	MARCH = "MarchMode",
	COMBAT = "CombatMode",
}

-- ==================== 动画状态枚举 ====================

local AnimationState = {
	MOVE = "MOVE",
	IDLE = "IDLE",
	ATTACK = "ATTACK",
}

-- ==================== 私有变量 ====================

local activeAIs = {}
local updateConnection = nil
local deathEventConnection = nil
local accumulatedTime = 0
local isInitialized = false
local lastSeparationUpdate = 0

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitAI-V5]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[UnitAI-V5]", ...)
end

-- ==================== 动画控制器 ====================

local AnimationController = {}

local function CreateAndPlayAnimation(humanoid, animationId, looped, priority)
	if not humanoid or not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	local animIdStr = tostring(animationId)
	if not tonumber(animIdStr) then return nil end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid.Parent and humanoid.Parent:FindFirstChildOfClass("Animator")
	end
	if not animator then return nil end

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
	-- 清理旧连接
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

	if animationId and animationId ~= "" and combatProfile and combatProfile.UseAnimationEvent then
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

-- ==================== 工具函数 ====================

local function GetDistance(model1, model2)
	local part1 = model1:FindFirstChild("HumanoidRootPart") or model1.PrimaryPart
	local part2 = model2:FindFirstChild("HumanoidRootPart") or model2.PrimaryPart

	if not part1 or not part2 then
		return math.huge
	end

	return (part1.Position - part2.Position).Magnitude
end

local function GetHorizontalDistance(pos1, pos2)
	if not pos1 or not pos2 then return math.huge end
	return math.sqrt((pos1.X - pos2.X)^2 + (pos1.Z - pos2.Z)^2)
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

-- ==================== Blockcast障碍检测 ====================

local function IsPathClear(unitModel, targetModel)
	local root = unitModel:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart

	if not root or not targetRoot then
		return false
	end

	local startPos = root.Position
	local endPos = targetRoot.Position
	local direction = endPos - startPos
	local distance = direction.Magnitude

	if distance < 3 then return true end

	local size = Vector3.new(CONFIG.BLOCKCAST_WIDTH, CONFIG.BLOCKCAST_HEIGHT, 1)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local filterList = {unitModel, targetModel}
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		table.insert(filterList, unitsFolder)
	end
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	local detectDistance = math.max(1, distance - 3)
	local cframe = CFrame.lookAt(startPos, Vector3.new(endPos.X, startPos.Y, endPos.Z))

	local result = workspace:Blockcast(cframe, size, direction.Unit * detectDistance, rayParams)

	if result and result.Instance.CanCollide then
		return false
	end

	return true
end

-- ==================== 分离力 ====================

local function ApplySeparationForces()
	local now = tick()
	if now - lastSeparationUpdate < CONFIG.SEPARATION_INTERVAL then
		return
	end
	lastSeparationUpdate = now

	local unitPositions = {}
	for unitModel, aiData in pairs(activeAIs) do
		if aiData.IsActive and unitModel.Parent then
			-- 只在移动/寻敌时施加分离力，避免交战时被互相推开导致抖动
			local state = CombatSystem and CombatSystem.GetUnitState(unitModel)
			if state and (state.State == BattleConfig.AIState.MOVING or state.State == BattleConfig.AIState.SEEKING) then
				local root = unitModel:FindFirstChild("HumanoidRootPart")
				if root then
					table.insert(unitPositions, {
						model = unitModel,
						position = root.Position,
						root = root,
					})
				end
			end
		end
	end

	for i, unit1 in ipairs(unitPositions) do
		local totalForce = Vector3.zero
		local neighborCount = 0

		for j, unit2 in ipairs(unitPositions) do
			if i ~= j then
				local diff = unit1.position - unit2.position
				local distXZ = math.sqrt(diff.X^2 + diff.Z^2)

				if distXZ < CONFIG.SEPARATION_RADIUS and distXZ > 0.3 then
					local pushDir = Vector3.new(diff.X, 0, diff.Z)
					if pushDir.Magnitude > 0.1 then
						pushDir = pushDir.Unit
						local forceMagnitude = (CONFIG.SEPARATION_RADIUS - distXZ) / CONFIG.SEPARATION_RADIUS
						totalForce = totalForce + pushDir * forceMagnitude
						neighborCount = neighborCount + 1
					end
				end
			end
		end

		if neighborCount > 0 and totalForce.Magnitude > 0.1 then
			local finalForce = totalForce.Unit * CONFIG.SEPARATION_FORCE
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

-- ==================== 节流MoveTo ====================

local function ThrottledMoveTo(aiData, targetPos)
	if not aiData or not aiData.Humanoid or not targetPos then
		return false
	end

	local now = tick()

	if aiData.LastMoveToPos then
		local distDiff = (targetPos - aiData.LastMoveToPos).Magnitude
		local timeDiff = now - (aiData.LastMoveToTick or 0)

		if distDiff < CONFIG.MOVETO_POSITION_THRESHOLD and timeDiff < CONFIG.MOVETO_THROTTLE_INTERVAL then
			return false
		end
	end

	aiData.Humanoid:MoveTo(targetPos)
	aiData.LastMoveToPos = targetPos
	aiData.LastMoveToTick = now
	return true
end

-- ==================== 距离策略 ====================

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
		local thresholdBase = math.max(unitState.AttackRange * 0.9, docking)
		local threshold = thresholdBase + (BattleConfig.ATTACK_ENTER_TOLERANCE or 0.5)
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
		local thresholdBase = math.max(unitState.AttackRange * 0.95, docking)
		local threshold = thresholdBase + (BattleConfig.ATTACK_EXIT_TOLERANCE or 1.0)
		return distance > threshold
	end
end

-- ==================== 朝向目标 ====================

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

		if dot < 0.996 then
			local newCFrame = CFrame.lookAt(myPos, myPos + lookVector)
			aiData.HumanoidRootPart.CFrame = newCFrame
			return true
		end
	end

	return false
end

-- ==================== 状态处理函数 ====================

-- SEEKING: 寻找目标
local function HandleSeeking(unitModel, aiData, state)
	local target = UnitAI.FindNearestEnemy(unitModel)

	if target then
		CombatSystem.SetTarget(unitModel, target)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		DebugLog(string.format("%s SEEKING→MOVING 找到目标", state.UnitId))
	else
		AnimationController.SwitchToIdle(unitModel, aiData, state)
	end
end

-- MOVING: ???????????????
local function HandleMoving(unitModel, aiData, state)
	-- ????????????
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		CombatSystem.ResetAttackPhase(unitModel)
		PathService.ClearPath(unitModel)
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		return
	end

	-- ??????????????????
	AnimationController.SwitchToMove(unitModel, aiData, state)

	local distance = GetDistance(unitModel, target)
	local targetState = CombatSystem.GetUnitState(target)
	local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

	-- ??????????????????????????????
	if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
		aiData.Humanoid:Move(Vector3.zero, true)
		PathService.ClearPath(unitModel)

		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
		DebugLog(string.format("%s MOVING->ATTACKING ??????=%.1f", state.UnitId, distance))

		if aiData.Tracks.Move then
			SafeStopAnimation(aiData.Tracks.Move)
			aiData.Tracks.Move = nil
		end
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		return
	end

	-- ?????????????????????
	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if not targetPart then return end

	local myPos = aiData.HumanoidRootPart.Position
	local targetPos = targetPart.Position

	local direction = (targetPos - myPos)
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.1 then return end
	direction = direction.Unit
	local moveTargetPos = targetPos - direction * dockingDistance

	-- ?????????????????????????????????
	local shouldUsePath = false

	if distance > CONFIG.MAX_DIRECT_MOVE_DISTANCE then
		shouldUsePath = true
	elseif not IsPathClear(unitModel, target) then
		shouldUsePath = true
	end

	-- ??????????????????????????????
	if not shouldUsePath then
		local velocity = aiData.HumanoidRootPart.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		if aiData.Humanoid.MoveDirection.Magnitude > 0.1 and speed < 0.5 then
			aiData.StuckAccumulator = (aiData.StuckAccumulator or 0) + 1
			if aiData.StuckAccumulator > 5 then
				DebugLog(string.format("%s ?????????????????????????????????", state.UnitId))
				aiData.StuckAccumulator = 0
				shouldUsePath = true
				PathService.ClearPath(unitModel)
				PathService.ForceRepath(unitModel)
			end
		else
			aiData.StuckAccumulator = 0
		end
	end

	if shouldUsePath then
		-- ????????????
		local pathStatus = PathService.GetPathStatus(unitModel)

		if pathStatus == "Success" or pathStatus == "Partial" then
			local isPartialPath = (pathStatus == "Partial")
			local now = tick()

			-- ????????????
			local checkInterval = CONFIG.STUCK_CHECK_INTERVAL
			local lastCheck = aiData.PathDisplacementCheckTime or 0

			if now - lastCheck >= checkInterval then
				aiData.PathDisplacementCheckTime = now

				local lastRepathTime = aiData.LastRepathTriggerTime or 0
				local canRepath = (now - lastRepathTime) >= CONFIG.REPATH_COOLDOWN

				local currentPos = aiData.HumanoidRootPart.Position
				local lastPos = aiData.PathLastCheckPos or currentPos
				local actualDistance = GetHorizontalDistance(currentPos, lastPos)
				aiData.PathLastCheckPos = currentPos

				local prevDistToTarget = aiData.PrevDistanceToTarget or distance
				local isProgressingToTarget = distance < (prevDistToTarget - 0.1)
				aiData.PrevDistanceToTarget = distance

				local isReallyStuck = actualDistance < CONFIG.STUCK_MIN_VELOCITY
					and not isProgressingToTarget
					and distance > CONFIG.MIN_DISTANCE_FOR_CHECK
					and canRepath

				if isReallyStuck then
					aiData.PathDisplacementStuckCount = (aiData.PathDisplacementStuckCount or 0) + 1

					if aiData.PathDisplacementStuckCount >= CONFIG.STUCK_COUNT_THRESHOLD then
						DebugLog(string.format("%s ????????????????????????", state.UnitId))
						aiData.PathDisplacementStuckCount = 0
						aiData.LastRepathTriggerTime = now
						aiData.Humanoid:Move(Vector3.zero)
						PathService.ClearPath(unitModel)
						PathService.ForceRepath(unitModel)
						aiData.PathRequested = false
						return
					end
				else
					if actualDistance > CONFIG.STUCK_MIN_VELOCITY then
						aiData.PathDisplacementStuckCount = 0
					end
				end
			end

			-- ?????????????????????
			if PathService.HasReachedWaypoint(unitModel) then
				if not PathService.AdvancePath(unitModel) then
					-- ????????????
					if isPartialPath then
						-- PARTIAL????????????????????????????????????
						PathService.ClearPath(unitModel)
						DebugLog(string.format("?????? %s PARTIAL??????????????????????????????", state.UnitId))
						aiData.Humanoid:Move(Vector3.zero)
						aiData.LastUpdateTime = tick() + 0.3
						return
					else
						-- SUCCESS?????????????????????????????????
						PathService.ClearPath(unitModel)
						shouldUsePath = false
					end
				end
			end

			if shouldUsePath then
				local nextWaypoint = PathService.GetNextWaypoint(unitModel)
				if nextWaypoint then
					ThrottledMoveTo(aiData, nextWaypoint)
					return
				else
					if isPartialPath then
						PathService.ClearPath(unitModel)
						aiData.Humanoid:Move(Vector3.zero)
						aiData.LastUpdateTime = tick() + 0.3
						return
					else
						PathService.ClearPath(unitModel)
						shouldUsePath = false
					end
				end
			end

		elseif pathStatus == "Computing" or pathStatus == "Queued" then
			-- ????????????
			return

		else
			-- ???????????????????????????
			if not aiData.PathRequested then
				aiData.PathRequested = true

				PathService.RequestPathAsync(unitModel, target, state.UnitId, function(success, pathState)
					aiData.PathRequested = false

					if not aiData.IsActive or not unitModel.Parent then return end

					if success and pathState and (pathState.Status == "Success" or pathState.Status == "Partial") then
						local nextWaypoint = PathService.GetNextWaypoint(unitModel)
						if nextWaypoint then
							ThrottledMoveTo(aiData, nextWaypoint)
						elseif pathState.Status == "Partial" then
							aiData.Humanoid:Move(Vector3.zero)
						end
					else
						-- ???????????????????????????
						DebugLog(string.format("?????? %s ????????????", state.UnitId))
						aiData.Humanoid:Move(Vector3.zero)
						aiData.LastUpdateTime = tick() + 0.5
					end
				end)
			end
			return
		end
	end

	-- ????????????
	local distanceToTarget = (moveTargetPos - myPos).Magnitude
	if distanceToTarget > 0.5 then
		ThrottledMoveTo(aiData, moveTargetPos)
	end
end

-- ATTACKING: 攻击目标
local function HandleAttacking(unitModel, aiData, state)
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

	-- 攻击动画播放中
	if aiData.Tracks.Attack and aiData.Tracks.Attack.IsPlaying then
		return
	end

	-- 冷却中
	if not CombatSystem.CanAttack(unitModel) then
		if not aiData.Tracks.Idle or not aiData.Tracks.Idle.IsPlaying then
			AnimationController.SwitchToIdle(unitModel, aiData, state)
		end
		return
	end

	-- 触发攻击
	UnitAI.TriggerAttack(unitModel, target, state, aiData)
end

-- ==================== 更新间隔配置 ====================

local AI_UPDATE_INTERVALS = {
	[BattleConfig.AIState.SEEKING] = 0.5,
	[BattleConfig.AIState.MOVING] = 0.1,
	[BattleConfig.AIState.ATTACKING] = 0.1,
	[BattleConfig.AIState.IDLE] = 0.8,
}

-- ==================== 主更新循环 ====================

local function UpdateAllAIs()
	local currentTime = tick()

	-- 分离力
	ApplySeparationForces()

	for unitModel, aiData in pairs(activeAIs) do
		if not unitModel or not unitModel.Parent then
			continue
		end

		if not CombatSystem.IsUnitAlive(unitModel) or not aiData.IsActive then
			continue
		end

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

	LoadSystems()

	DebugLog("正在初始化AI系统(V5.0)...")

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
	DebugLog("AI系统(V5.0)初始化完成")
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

	LoadSystems()

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
		PathDisplacementCheckTime = 0,
		PathLastCheckPos = nil,
		PathDisplacementStuckCount = 0,
		PrevDistanceToTarget = nil,
		LastRepathTriggerTime = 0,
		StuckAccumulator = 0,
	}

	activeAIs[unitModel] = aiData

	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		humanoid.WalkSpeed = state.MoveSpeed
	else
		WarnLog("StartAI: 单位没有CombatSystem状态!")
		return false
	end

	-- 停止所有动画
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

-- ==================== 动画辅助接口（兼容旧代码）====================

function UnitAI.PlayDeathAnimation(unitModel, animationId)
	if not unitModel or not unitModel:IsA("Model") then return nil end
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	return CreateAndPlayAnimation(humanoid, animationId, false)
end

function UnitAI.BeginDeathAnimation(unitModel, animationId, unitId)
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then return end

	local animateScript = unitModel:FindFirstChild("Animate", true)
	if animateScript and animateScript:IsA("BaseScript") then
		animateScript.Enabled = false
	end

	if animationId and animationId ~= "" and animationId ~= "0" then
		local animator = humanoid:FindFirstChild("Animator")
		if animator then
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
	-- V5.0简化：移除围攻系统
end

function UnitAI.ClearTargetSurroundData(targetModel)
	-- V5.0简化：移除围攻系统
end

return UnitAI
