--[[
脚本名称: UnitAI
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitAI
版本: V1.5.1 - 重构为动画事件驱动 + AI节流
]]

--[[
兵种AI系统
职责:
1. 目标寻找与锁定
2. 移动与寻路
3. 攻击判定与执行
4. AI状态机管理

V1.5.1 重要改动:
- 移除所有 Touched 事件相关代码
- 攻击改为监听动画"Damage"事件
- AI更新改为批量节流（0.2秒）
- 寻敌改用 UnitManager 分组索引
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
local UnitManager = require(ServerScriptService.Systems.UnitManager)

-- ==================== 私有变量 ====================

-- 存储所有AI实例 [unitModel] = AIData
local activeAIs = {}

-- AI更新连接
local updateConnection = nil

-- 死亡事件连接
local deathEventConnection = nil

-- V1.5.1 新增: AI节流相关
local accumulatedTime = 0

-- 是否已初始化
local isInitialized = false

-- ==================== 数据结构 ====================

--[[
AIData = {
    UnitModel = Model,           -- 兵种模型
    Humanoid = Humanoid,         -- Humanoid对象
    HumanoidRootPart = Part,     -- HumanoidRootPart
    IsActive = boolean,          -- AI是否激活
    LastUpdateTime = number,     -- 上次更新时间
    PathfindingTimeout = number, -- 寻路超时时间
    CurrentMoveAnimation = AnimationTrack|nil,  -- 当前播放的移动动画
    CurrentAttackAnimation = AnimationTrack|nil, -- 当前播放的攻击动画
    AnimationConnections = {},   -- 动画事件连接 (V1.5.1新增)
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
播放移动动画
@param humanoid Humanoid - Humanoid对象
@param unitId string - 兵种ID
@return AnimationTrack|nil - 动画轨道
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

	-- 设置动画循环播放
	animationTrack.Looped = true

	-- 播放动画
	local playSuccess, playError = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		WarnLog(string.format("无法播放移动动画: %s, 错误: %s", animationId, playError))
		animation:Destroy()
		return nil
	end

	DebugLog(string.format("播放移动动画: %s (循环)", animationId))

	return animationTrack
end

--[[
播放攻击动画
@param humanoid Humanoid - Humanoid对象
@param animationId string - 动画ID
@return AnimationTrack|nil - 动画轨道
]]
local function PlayAttackAnimation(humanoid, animationId)
	-- 参数验证
	if not humanoid then
		return nil
	end

	-- 如果animationId为空或nil，则不播放自定义动画
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

	-- V1.5.1修复: 攻击动画不应该循环播放
	animationTrack.Looped = false

	-- 播放动画
	local playSuccess, playError = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		WarnLog(string.format("无法播放动画: %s, 错误: %s", animationId, playError))
		animation:Destroy()
		return nil
	end

	DebugLog(string.format("播放攻击动画: %s (单次)", animationId))

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
计算停靠点（Docking Point）
V1.5.1重构: 考虑模型物理尺寸,避免隔空挥拳
单位不会直接移动到目标脚下,而是停留在双方模型几乎贴身的位置
@param attackerRoot Part - 攻击方的HumanoidRootPart
@param targetRoot Part - 目标的HumanoidRootPart
@param attackRange number - 攻击距离
@param tolerance number - 容差（额外的安全距离）
@param combatProfile table - 战斗配置(包含ContactOffset)
@return Vector3 - 停靠点位置
]]
local function CalculateDockingPoint(attackerRoot, targetRoot, attackRange, tolerance, combatProfile)
	local myPos = attackerRoot.Position
	local targetPos = targetRoot.Position

	-- 计算方向向量
	local directionToTarget = (targetPos - myPos)
	local distance = directionToTarget.Magnitude

	-- 如果已经非常接近，返回当前位置
	if distance < 0.1 then
		return myPos
	end

	-- 单位化方向向量
	local normalizedDirection = directionToTarget.Unit

	-- ==================== V1.5.1核心改动: 考虑模型物理尺寸 ====================

	-- 获取双方模型的深度(Z轴尺寸)
	local attackerDepth = attackerRoot.Size.Z
	local targetDepth = targetRoot.Size.Z

	-- 计算接触距离(两个包围盒相贴时的中心距)
	local contactDistance = (attackerDepth + targetDepth) * 0.5

	-- 计算期望距离(接触距离 - 缓冲距离,避免完全重叠)
	local desiredDistance = math.max(contactDistance - BattleConfig.CONTACT_BUFFER, 0)

	-- 综合考虑攻击距离和物理尺寸
	-- 取两者中的较小值,确保既不超出攻击范围,也不隔空挥拳
	local baseDockingDistance = math.max(
		math.min(attackRange - tolerance, desiredDistance),
		BattleConfig.MIN_DOCKING_DISTANCE
	)

	-- 应用武器长度补偿(如果有)
	local contactOffset = (combatProfile and combatProfile.ContactOffset) or 0
	local dockingDistance = baseDockingDistance + contactOffset

	-- 计算停靠点(从目标位置往回退dockingDistance)
	local dockingPoint = targetPos - normalizedDirection * dockingDistance

	DebugLog(string.format(
		"计算停靠点: 距离=%.2f, 攻击距离=%.2f, 攻击者深度=%.2f, 目标深度=%.2f, 接触距离=%.2f, 期望距离=%.2f, 武器补偿=%.2f, 最终停靠距离=%.2f",
		distance, attackRange, attackerDepth, targetDepth, contactDistance, desiredDistance, contactOffset, dockingDistance
	))

	return dockingPoint
end

--[[
更新所有AI (V1.5.1优化: 批量更新)
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

	-- V1.5.1: 使用节流机制，累积时间达到阈值才批量更新
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
		CurrentMoveAnimation = nil,
		CurrentAttackAnimation = nil,
		AnimationConnections = {},  -- V1.5.1新增: 存储动画事件连接
	}

	activeAIs[unitModel] = aiData

	-- 设置移动速度
	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		humanoid.WalkSpeed = state.MoveSpeed
	end

	local unitId = state and state.UnitId or "Unknown"
	DebugLog(string.format("启动AI: %s", unitId))

	-- 立刻主动寻找目标并开始移动，避免延迟
	task.defer(function()
		if not aiData.IsActive then
			return
		end

		local target = UnitAI.FindNearestEnemy(unitModel)

		if target then
			CombatSystem.SetTarget(unitModel, target)
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
			-- 立刻播放移动动画
			UnitAI.MoveToTarget(unitModel, target, aiData)
			DebugLog(string.format("AI启动: %s 立刻开始移动到目标", unitId))
		else
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
		end
	end)

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

		-- 停止所有动画
		if aiData.CurrentMoveAnimation then
			aiData.CurrentMoveAnimation:Stop()
			aiData.CurrentMoveAnimation = nil
		end

		if aiData.CurrentAttackAnimation then
			aiData.CurrentAttackAnimation:Stop()
			aiData.CurrentAttackAnimation = nil
		end

		-- V1.5.1: 断开所有动画事件连接
		for _, connection in ipairs(aiData.AnimationConnections) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
		aiData.AnimationConnections = {}

		-- 停止移动
		if aiData.Humanoid and aiData.HumanoidRootPart then
			aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
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

		-- V1.5.1优化: 增加攻击距离宽容值,防止边界摇摆
		local effectiveAttackRange = state.AttackRange + BattleConfig.ATTACK_RANGE_TOLERANCE

		if distance <= effectiveAttackRange then
			-- 进入攻击范围,停止移动
			aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)

			-- 停止移动动画
			if aiData.CurrentMoveAnimation then
				aiData.CurrentMoveAnimation:Stop()
				aiData.CurrentMoveAnimation = nil
				DebugLog("停止移动动画，进入攻击状态")
			end

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

		-- V1.5.1优化: 增加更大的容差,防止目标推开时立刻追击
		local exitAttackRangeThreshold = state.AttackRange + BattleConfig.MOVE_STOP_TOLERANCE + BattleConfig.ATTACK_RANGE_TOLERANCE

		if distance > exitAttackRangeThreshold then
			-- 超出攻击范围,停止攻击动画并继续移动
			if aiData.CurrentAttackAnimation then
				aiData.CurrentAttackAnimation:Stop()
				aiData.CurrentAttackAnimation = nil
				DebugLog("目标远离，停止攻击动画，重新移动")
			end
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		else
			-- V1.5.1优化: 在攻击范围内，保持与目标的距离，避免被对方推开或互相挤在一起
			-- 但不要在攻击时让单位后退，防止身体转向异常
			local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
			if targetPart and state then
				local myPos = aiData.HumanoidRootPart.Position
				local targetPos = targetPart.Position
				local currentDistance = (targetPos - myPos).Magnitude

				local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)
				local dockingPoint = CalculateDockingPoint(
					aiData.HumanoidRootPart,
					targetPart,
					state.AttackRange,
					BattleConfig.ATTACK_RANGE_TOLERANCE,
					combatProfile
				)

				-- 计算停靠点的方向
				local directionToDocking = (dockingPoint - myPos)
				local distanceToDocking = directionToDocking.Magnitude

				-- V1.5.1修复: 只有在停靠点在"前方"且距离足够时才移动
				-- 如果停靠点在后方（表示已经太近了），就保持当前位置不动
				if distanceToDocking > 0.5 then
					-- 判断停靠点是否在前方（与朝向目标的方向夹角小于90度）
					local directionToTarget = (targetPos - myPos).Unit
					local directionToDockingUnit = directionToDocking.Unit
					local dotProduct = directionToTarget:Dot(directionToDockingUnit)

					if dotProduct > 0 then
						-- 停靠点在前方，可以移动
						aiData.Humanoid:MoveTo(dockingPoint)
					else
						-- 停靠点在后方（太近了），保持位置不动
						aiData.Humanoid:MoveTo(myPos)
						DebugLog(string.format("%s 距离过近(%.2f)，保持位置不后退", state.UnitId, currentDistance))
					end
				else
					-- 已经在正确位置，停止移动
					aiData.Humanoid:MoveTo(myPos)
				end
			end

			-- 执行攻击
			UnitAI.AttackTarget(unitModel, target, state, aiData)
		end
	end
end

--[[
寻找最近的敌方单位 (V1.5.1优化: 使用UnitManager)
@param unitModel Model - 兵种模型
@return Model|nil - 最近的敌方单位
]]
function UnitAI.FindNearestEnemy(unitModel)
	-- V1.5.1: 使用UnitManager的高效寻敌接口
	local enemy, distance = UnitManager.GetClosestEnemy(unitModel, BattleConfig.TARGET_SEARCH_RANGE)
	return enemy
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

	-- 获取兵种ID并播放移动动画（只在没有播放时才播放）
	local state = CombatSystem.GetUnitState(unitModel)
	if state and state.UnitId then
		-- 检查是否已经有移动动画在播放
		if not aiData.CurrentMoveAnimation or not aiData.CurrentMoveAnimation.IsPlaying then
			local moveAnimTrack = PlayMoveAnimation(aiData.Humanoid, state.UnitId)
			-- 保存当前播放的移动动画
			if moveAnimTrack then
				aiData.CurrentMoveAnimation = moveAnimTrack
				DebugLog(string.format("启动移动动画并保存引用"))
			end
		end
	end

	-- V1.5.1优化: 计算停靠点,避免两个单位挤在一起
	-- 停靠点考虑双方模型物理尺寸,让单位贴身战斗而非隔空挥拳
	local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)
	local dockingPoint = CalculateDockingPoint(
		aiData.HumanoidRootPart,
		targetPart,
		state.AttackRange,
		BattleConfig.ATTACK_RANGE_TOLERANCE,
		combatProfile
	)

	-- 调用MoveTo移动到停靠点,而不是目标的脚下
	-- 这样两个单位会自然地停在各自的安全距离上(攻击范围内),形成对峙并进行攻击
	aiData.Humanoid:MoveTo(dockingPoint)

	DebugLog(string.format("%s 追击中,目标距离=%.2f,攻击距离=%.2f,停靠点=%.2f,%.2f,%.2f",
		state.UnitId, (targetPart.Position - aiData.HumanoidRootPart.Position).Magnitude, state.AttackRange, dockingPoint.X, dockingPoint.Y, dockingPoint.Z))
end

--[[
攻击目标 (V1.5.1重构: 动画事件驱动)
@param unitModel Model - 兵种模型
@param target Model - 目标模型
@param state table - 兵种战斗状态
@param aiData AIData - AI数据
]]
function UnitAI.AttackTarget(unitModel, target, state, aiData)
	-- 检查攻击冷却 (由CombatSystem管理)
	if not CombatSystem.CanAttack(unitModel) then
		return
	end

	-- 确保移动动画已停止
	if aiData.CurrentMoveAnimation then
		aiData.CurrentMoveAnimation:Stop()
		aiData.CurrentMoveAnimation = nil
		DebugLog("攻击时停止移动动画")
	end

	-- V1.5.1修复: 停止并清理之前的攻击动画和事件连接
	if aiData.CurrentAttackAnimation then
		aiData.CurrentAttackAnimation:Stop()
		aiData.CurrentAttackAnimation = nil
	end

	-- 清理所有旧的动画事件连接，防止累积
	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}

	-- 面向目标
	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if targetPart then
		local lookVector = (targetPart.Position - aiData.HumanoidRootPart.Position).Unit
		aiData.HumanoidRootPart.CFrame = CFrame.new(aiData.HumanoidRootPart.Position, aiData.HumanoidRootPart.Position + lookVector)
	end

	-- 开始攻击 (进入Attacking阶段)
	local success = CombatSystem.BeginAttack(unitModel, target)
	if not success then
		return
	end

	-- ==================== V1.5.1核心改动: 监听动画"Damage"事件 ====================

	-- 获取攻击动画ID
	local animationId = UnitConfig.GetAttackAnimationId(state.UnitId)
	local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)

	-- 用于确保Damage事件只触发一次
	local damageEventFired = false

	-- 播放攻击动画
	if animationId and animationId ~= "" and combatProfile.UseAnimationEvent then
		local animTrack = PlayAttackAnimation(aiData.Humanoid, animationId)

		if animTrack then
			-- 监听动画的 "Damage" 事件
			local eventName = combatProfile.AnimationEventName or "Damage"

			local connection = animTrack:GetMarkerReachedSignal(eventName):Connect(function()
				-- V1.5.1修复: 确保Damage事件只触发一次
				if damageEventFired then
					DebugLog(string.format("%s Damage事件重复触发,已忽略", state.UnitId))
					return
				end
				damageEventFired = true

				-- 动画到达"Damage"关键帧,触发伤害判定
				DebugLog(string.format("%s 动画事件[%s]触发", state.UnitId, eventName))
				CombatSystem.OnDamageEvent(unitModel)
			end)

			-- 保存连接,用于清理
			table.insert(aiData.AnimationConnections, connection)

			-- 保存当前攻击动画
			aiData.CurrentAttackAnimation = animTrack

			-- V1.5.1修复: 动画播放完毕后自动清理连接
			animTrack.Stopped:Connect(function()
				if connection and connection.Connected then
					connection:Disconnect()
				end
			end)

			DebugLog(string.format("%s 播放攻击动画,监听[%s]事件", state.UnitId, eventName))
		else
			-- 动画加载失败,使用回退机制
			WarnLog(string.format("%s 动画加载失败,使用回退机制", state.UnitId))
			local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
			task.delay(fallbackDelay, function()
				-- V1.5.1 防御性编程: 检查单位是否还存活
				if unitModel and unitModel.Parent and not damageEventFired then
					-- 确保单位还在Attacking阶段
					if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
						damageEventFired = true
						CombatSystem.OnDamageEvent(unitModel)
					end
				end
			end)
		end
	else
		-- 没有配置动画或不使用动画事件,使用回退机制
		DebugLog(string.format("%s 无攻击动画配置或不使用动画事件,使用回退机制", state.UnitId))
		local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
		task.delay(fallbackDelay, function()
			-- V1.5.1 防御性编程: 检查单位是否还存活
			if unitModel and unitModel.Parent and not damageEventFired then
				if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
					damageEventFired = true
					CombatSystem.OnDamageEvent(unitModel)
				end
			end
		end)
	end
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
