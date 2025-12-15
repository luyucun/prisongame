--[[
脚本名称: ClientUnitAI
脚本类型: ModuleScript (客户端系统)
脚本位置: StarterPlayer/StarterPlayerScripts/ClientAI/ClientUnitAI
版本: V4.0 - 客户端AI迁移专用
]]

--[[
客户端单位AI
职责:
1. 管理单位的AI状态机（IDLE→SEEKING→MOVING→ATTACKING→DEAD）
2. 驱动单位移动、寻敌、攻击动画播放
3. 向服务端请求攻击判定
4. 简化版AI，移除复杂围攻系统（客户端性能优先）

V4.0设计要点:
- 与服务端UnitAI功能对齐，但大幅简化
- 移除多层围攻系统（减少客户端计算）
- 简单的直线移动到攻击距离
- 攻击判定由服务端完成
- 动画播放由客户端控制
]]

local ClientUnitAI = {}

-- ==================== 依赖服务 ====================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- 引用本地客户端模块
local ClientUnitManager = nil
local ClientPathService = nil

-- ==================== 引用配置 ====================

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== RemoteEvent引用 ====================

local ClientAIEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ClientAIEvents")
local RequestAttack = ClientAIEvents:WaitForChild("RequestAttack")
local ReportUnitPosition = ClientAIEvents:WaitForChild("ReportUnitPosition")

-- ==================== AI状态枚举 ====================

local AIState = {
	IDLE = "Idle",
	SEEKING = "Seeking",
	MOVING = "Moving",
	ATTACKING = "Attacking",
	DEAD = "Dead",
}

ClientUnitAI.AIState = AIState

-- ==================== 动画状态枚举 ====================

local AnimationState = {
	IDLE = "IDLE",
	MOVE = "MOVE",
	ATTACK = "ATTACK",
}

-- ==================== AI配置 ====================

local CONFIG = {
	-- AI更新间隔（秒）
	AI_UPDATE_INTERVAL = 0.1,

	-- 位置上报间隔（秒）
	POSITION_REPORT_INTERVAL = 0.5,

	-- 攻击距离容差（studs）
	ATTACK_RANGE_TOLERANCE = 1.0,

	-- 近战停靠距离容差（studs）
	MELEE_CONTACT_BUFFER = 0.5,

	-- 远程单位停靠距离系数（1.0 = 在满射程处停下）
	RANGED_DOCKING_RATIO = 1.0,

	-- 调试日志
	DEBUG_LOGS = false,

	-- V4.1修复：目标重新评估（防止初始化/复制窗口导致锁定远处目标）
	TARGETING = {
		RECHECK_INTERVAL = 0.5,          -- 重新评估间隔（秒）
		SWITCH_DISTANCE_MARGIN = 15,     -- 新目标需要比当前目标近多少才切换（studs）
		MIN_DISTANCE_TO_RECHECK = 35,    -- 当前目标距离超过此值才触发重新评估（studs）
		INITIAL_CORRECTION_WINDOW = 1.0, -- 仅允许在锁定目标后的前N秒内纠偏一次（避免中途反复回头换目标）
	},

	-- V4.1新增：简化围攻系统配置
	SURROUND = {
		BASE_UNITS_PER_RING = 6,       -- 第一圈基础单位数
		RING_UNIT_INCREMENT = 6,       -- 每圈增加的单位数
		BASE_RING_RADIUS = 0.7,        -- 第一圈半径系数(相对于攻击距离)
		RING_RADIUS_INCREMENT = 3,     -- 每圈半径增加(studs)
		MAX_RINGS = 4,                 -- 最大圈数
	},

	-- V4.1新增：Y轴地面钳定配置
	GROUND_CLAMP = {
		ENABLED = true,                -- 是否启用地面钳定
		CHECK_INTERVAL = 0.2,          -- 检测间隔（秒）
		MAX_HEIGHT_DIFF = 3,           -- 最大允许高度差（studs）
		RAYCAST_DISTANCE = 50,         -- 射线检测距离（studs）
	},

	-- 寻路配置
	PATHFINDING = {
		ENABLED = true,                -- 是否启用寻路（禁用则直线移动）
		REPATH_COOLDOWN = 0.5,         -- 重新寻路冷却时间（秒）
		DIRECT_MOVE_THRESHOLD = 8,     -- 距离小于此值时直接移动（studs）
	},
}

if BattleConfig then
	CONFIG.DEBUG_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_LOGS
end

-- ==================== 私有变量 ====================

local activeAIs = {}  -- [unitModel] = AIData
local updateConnection = nil
local accumulatedTime = 0
local positionReportTime = 0

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_LOGS then
		print(GameConfig.LOG_PREFIX, "[ClientUnitAI]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[ClientUnitAI]", ...)
end

-- ==================== 工具函数 ====================

local function GetDistance(modelA, modelB)
	local rootA = modelA:FindFirstChild("HumanoidRootPart") or modelA.PrimaryPart
	local rootB = modelB:FindFirstChild("HumanoidRootPart") or modelB.PrimaryPart
	if not rootA or not rootB then return 99999 end
	return (rootA.Position - rootB.Position).Magnitude
end

--[[
计算停靠距离（根据兵种类型和攻击距离）
@param aiData AIData
@return number - 停靠距离
]]
local function GetDockingDistance(aiData)
	local attackRange = aiData.Stat.AttackRange

	if aiData.UnitType == UnitConfig.UnitType.MELEE then
		-- 近战：攻击距离 - 缓冲
		return math.max(1, attackRange - CONFIG.MELEE_CONTACT_BUFFER)
	else
		-- 远程：攻击距离 * 停靠系数
		return attackRange * CONFIG.RANGED_DOCKING_RATIO
	end
end

--[[
V4.1修复：在移动/追击过程中，定期重新评估最近敌人
目的：避免单位在目标列表/部件复制未就绪的短窗口内锁到远处目标后一直不切换
@param aiData table
@return boolean - 是否发生了目标切换
]]
local function MaybeSwitchToCloserTarget(aiData)
	if not aiData or not aiData.CurrentTarget or not aiData.CurrentTarget.Parent then
		return false
	end

	local now = tick()
	local cfg = CONFIG.TARGETING or {}
	local correctionWindow = cfg.INITIAL_CORRECTION_WINDOW or 1.0

	-- 只做“开战初期”的一次纠偏，避免单位在追击过程中频繁切换目标导致回头/扭动
	if aiData.TargetAcquiredTime and (now - aiData.TargetAcquiredTime) > correctionWindow then
		return false
	end
	if aiData._DidInitialTargetCorrection then
		return false
	end

	local recheckInterval = cfg.RECHECK_INTERVAL or 0.5
	if aiData.LastTargetCheckTime and (now - aiData.LastTargetCheckTime) < recheckInterval then
		return false
	end
	aiData.LastTargetCheckTime = now

	local currentDist = GetDistance(aiData.UnitModel, aiData.CurrentTarget)
	local minDistToRecheck = cfg.MIN_DISTANCE_TO_RECHECK or 25
	if currentDist < minDistToRecheck then
		return false
	end

	-- 强制刷新位置，避免缓存/复制窗口导致的距离误差
	local nearest, nearestDist = ClientUnitManager.GetClosestEnemy(
		aiData.UnitModel,
		BattleConfig.TARGET_SEARCH_RANGE,
		true
	)

	if not nearest or nearest == aiData.CurrentTarget then
		return false
	end

	local switchMargin = cfg.SWITCH_DISTANCE_MARGIN or 5
	if nearestDist + switchMargin < currentDist then
		aiData.CurrentTarget = nearest
		aiData.State = AIState.SEEKING
		ClientPathService.StopMovement(aiData.UnitModel)
		aiData._DidInitialTargetCorrection = true
		aiData.TargetAcquiredTime = now
		DebugLog(aiData.UnitModel.Name, "切换更近目标:", nearest.Name,
			string.format("(%.1f -> %.1f)", currentDist, nearestDist))
		return true
	end

	return false
end

-- ==================== V4.1新增：简化围攻系统 ====================

-- 全局递增计数器，用于分配唯一SlotId
local nextSlotIdCounter = 1

--[[
获取单位的唯一槽位ID（确定性分配）
@param model Model - 单位模型
@return number - 槽位ID
]]
local function GetUnitSlotId(model)
	-- 优先使用已存在的属性
	local slotId = model:GetAttribute("SpawnIndex")
		or model:GetAttribute("UnitIndex")
		or model:GetAttribute("_ClientAISlotId")

	if slotId then
		if type(slotId) == "string" then
			local hash = 0
			for i = 1, #slotId do
				hash = (hash * 31 + string.byte(slotId, i)) % 1000000
			end
			return hash
		end
		return tonumber(slotId) or 0
	end

	-- 分配新的递增ID
	local newId = nextSlotIdCounter
	nextSlotIdCounter = nextSlotIdCounter + 1
	model:SetAttribute("_ClientAISlotId", newId)

	return newId
end

--[[
获取攻击同一目标的友军数量和列表
@param targetModel Model - 目标模型
@param myTeam string - 我方队伍
@param battleId number - 战斗ID
@return table, number - 攻击者列表, 总数
]]
local function GetUnitsAttackingSameTarget(targetModel, myTeam, battleId)
	local attackers = {}
	local count = 0

	for unitModel, aiData in pairs(activeAIs) do
		if unitModel and unitModel.Parent and aiData.Team == myTeam and aiData.BattleId == battleId then
			if aiData.CurrentTarget == targetModel then
				count = count + 1
				attackers[unitModel] = {
					SlotId = GetUnitSlotId(unitModel),
					AttackRange = aiData.Stat.AttackRange or 6,
				}
			end
		end
	end

	return attackers, count
end

--[[
计算围攻位置偏移（简化版环形站位）
@param slotId number - 单位槽位ID
@param attackRange number - 攻击距离
@param totalAttackers number - 攻击同一目标的总单位数
@param attackersList table - 攻击者列表
@return Vector3 - 偏移量
]]
local function ComputeSurroundOffset(slotId, attackRange, totalAttackers, attackersList)
	local cfg = CONFIG.SURROUND

	-- 对所有攻击者按SlotId排序
	local sortedSlots = {}
	for unitModel, data in pairs(attackersList) do
		table.insert(sortedSlots, { SlotId = data.SlotId, Model = unitModel })
	end
	table.sort(sortedSlots, function(a, b) return a.SlotId < b.SlotId end)

	-- 找到当前单位的排序索引
	local myIndex = 0
	for i, entry in ipairs(sortedSlots) do
		if entry.SlotId == slotId then
			myIndex = i - 1
			break
		end
	end

	-- 计算所在环层和环内位置
	local ringIndex = 0
	local indexInRing = 0
	local unitsInCurrentRing = cfg.BASE_UNITS_PER_RING

	local accumulated = 0
	for ring = 0, cfg.MAX_RINGS - 1 do
		local unitsInRing = cfg.BASE_UNITS_PER_RING + ring * cfg.RING_UNIT_INCREMENT
		if myIndex < accumulated + unitsInRing then
			ringIndex = ring
			indexInRing = myIndex - accumulated
			unitsInCurrentRing = unitsInRing
			break
		end
		accumulated = accumulated + unitsInRing
	end

	-- 计算环半径
	local baseRadius = attackRange * cfg.BASE_RING_RADIUS
	local radius = baseRadius + ringIndex * cfg.RING_RADIUS_INCREMENT

	-- 计算角度（黄金角度偏移让多圈错开）
	local goldenAngle = math.pi * (3 - math.sqrt(5))
	local baseAngle = (indexInRing / unitsInCurrentRing) * math.pi * 2
	local ringOffset = ringIndex * goldenAngle

	local angle = baseAngle + ringOffset

	-- 计算最终偏移
	local offsetX = math.cos(angle) * radius
	local offsetZ = math.sin(angle) * radius

	return Vector3.new(offsetX, 0, offsetZ)
end

--[[
计算围攻目标位置
@param aiData table - AI数据
@param target Model - 目标模型
@return Vector3|nil - 围攻位置
]]
local function ComputeSurroundPosition(aiData, target)
	local myRoot = aiData.UnitModel:FindFirstChild("HumanoidRootPart")
	local tarRoot = target:FindFirstChild("HumanoidRootPart")
	if not myRoot or not tarRoot then return nil end

	local targetPos = tarRoot.Position
	local attackRange = aiData.Stat.AttackRange or 6
	local slotId = GetUnitSlotId(aiData.UnitModel)

	-- 获取攻击同一目标的所有友军
	local attackers, totalAttackers = GetUnitsAttackingSameTarget(target, aiData.Team, aiData.BattleId)

	-- 如果只有自己，直接朝目标移动
	if totalAttackers <= 1 then
		local myPos = myRoot.Position
		local direction = (targetPos - myPos)
		if direction.Magnitude > 0.1 then
			direction = direction.Unit
		else
			direction = Vector3.new(1, 0, 0)
		end
		local dockingDistance = GetDockingDistance(aiData)
		return targetPos - direction * dockingDistance
	end

	-- 计算环形站位偏移
	local surroundOffset = ComputeSurroundOffset(slotId, attackRange, totalAttackers, attackers)

	return targetPos + surroundOffset
end

-- ==================== V4.1新增：Y轴地面钳定 ====================

--[[
将单位钳定到地面（防止被顶起后沿空中移动）
@param aiData table - AI数据
]]
local function ClampToGround(aiData)
	if not CONFIG.GROUND_CLAMP.ENABLED then return end

	local unitModel = aiData.UnitModel
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- 检测间隔控制
	local now = tick()
	if aiData._LastGroundClampTime and (now - aiData._LastGroundClampTime) < CONFIG.GROUND_CLAMP.CHECK_INTERVAL then
		return
	end
	aiData._LastGroundClampTime = now

	-- 记录初始地面高度（首次检测时）
	if not aiData._BaseGroundY then
		-- 向下射线检测地面
		local rayOrigin = rootPart.Position
		local rayDirection = Vector3.new(0, -CONFIG.GROUND_CLAMP.RAYCAST_DISTANCE, 0)

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {unitModel}

		local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
		if result then
			aiData._BaseGroundY = result.Position.Y
		else
			aiData._BaseGroundY = rootPart.Position.Y
		end
	end

	-- 检查当前高度是否异常
	local currentY = rootPart.Position.Y
	local baseY = aiData._BaseGroundY
	local heightDiff = currentY - baseY

	-- 如果高度差超过阈值，强制拉回地面
	if heightDiff > CONFIG.GROUND_CLAMP.MAX_HEIGHT_DIFF then
		-- 向下射线检测当前位置的地面
		local rayOrigin = rootPart.Position + Vector3.new(0, 2, 0)
		local rayDirection = Vector3.new(0, -CONFIG.GROUND_CLAMP.RAYCAST_DISTANCE, 0)

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {unitModel}

		local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
		if result then
			local targetY = result.Position.Y + 3  -- 加上角色高度偏移
			-- 平滑下降而非瞬移
			local newY = currentY - math.min(heightDiff * 0.5, 2)
			newY = math.max(newY, targetY)

			rootPart.CFrame = CFrame.new(
				rootPart.Position.X,
				newY,
				rootPart.Position.Z
			) * CFrame.Angles(0, math.rad(rootPart.Orientation.Y), 0)
		end
	end
end

-- ==================== 动画管理 ====================

--[[
播放动画
@param aiData AIData
@param animState string - 动画状态
]]
local function PlayAnimation(aiData, animState)
	-- 攻击动画特殊处理：每次攻击都要重新播放
	if animState ~= AnimationState.ATTACK and aiData.CurrentAnimState == animState then
		return  -- 已经在播放该动画（非攻击动画）
	end

	-- 停止当前动画（攻击动画除外，让它自然播完）
	if aiData.CurrentAnimTrack and animState ~= AnimationState.ATTACK then
		aiData.CurrentAnimTrack:Stop(0.15)
		aiData.CurrentAnimTrack = nil
	end

	-- 播放新动画
	local animTrack = nil
	if animState == AnimationState.IDLE then
		animTrack = aiData.AnimTrack.Idle
	elseif animState == AnimationState.MOVE then
		animTrack = aiData.AnimTrack.Move
	elseif animState == AnimationState.ATTACK then
		animTrack = aiData.AnimTrack.Attack
	end

	if animTrack then
		-- 攻击动画：先停止其他动画再播放
		if animState == AnimationState.ATTACK then
			-- 停止Idle和Move动画
			if aiData.AnimTrack.Idle and aiData.AnimTrack.Idle.IsPlaying then
				aiData.AnimTrack.Idle:Stop(0.1)
			end
			if aiData.AnimTrack.Move and aiData.AnimTrack.Move.IsPlaying then
				aiData.AnimTrack.Move:Stop(0.1)
			end

			animTrack:Play(0.1)
			aiData.CurrentAnimTrack = animTrack
			aiData.CurrentAnimState = animState
			DebugLog(string.format("%s 播放攻击动画", aiData.UnitModel.Name))

			-- 攻击动画结束后自动回到Idle
			animTrack.Stopped:Once(function()
				if aiData and aiData.State ~= AIState.DEAD then
					aiData.CurrentAnimState = nil  -- 清除状态，允许下次播放
					-- 如果还在攻击状态，播放Idle等待下次攻击
					if aiData.State == AIState.ATTACKING then
						PlayAnimation(aiData, AnimationState.IDLE)
					end
				end
			end)
		else
			animTrack:Play(0.15)
			aiData.CurrentAnimTrack = animTrack
			aiData.CurrentAnimState = animState
		end
	else
		if animState == AnimationState.ATTACK then
			WarnLog(string.format("%s 攻击动画轨道不存在!", aiData.UnitModel.Name))
		end
	end
end

-- ==================== AI状态机核心 ====================

--[[
IDLE状态：待机，等待发现敌人
]]
local function UpdateIdleState(aiData, deltaTime)
	-- 播放待机动画
	PlayAnimation(aiData, AnimationState.IDLE)

	-- 寻找最近的敌人
	local enemyUnit, distance = ClientUnitManager.GetClosestEnemy(
		aiData.UnitModel,
		BattleConfig.TARGET_SEARCH_RANGE,
		true
	)

	if enemyUnit then
		-- 发现敌人，切换到SEEKING状态
		aiData.State = AIState.SEEKING
		aiData.CurrentTarget = enemyUnit
		aiData.TargetAcquiredTime = tick()
		aiData._DidInitialTargetCorrection = false
		-- 允许在下一帧SEEKING里立刻做一次“初期纠偏”（避免先走错方向再回头）
		aiData.LastTargetCheckTime = 0
		DebugLog(aiData.UnitModel.Name, "发现敌人:", enemyUnit.Name)
	end
end

--[[
SEEKING状态：发现敌人，判断是否需要移动
]]
local function UpdateSeekingState(aiData, deltaTime)
	-- 检查目标是否有效
	if not aiData.CurrentTarget or not aiData.CurrentTarget.Parent then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		-- 立即播放idle动画
		PlayAnimation(aiData, AnimationState.IDLE)
		return
	end

	-- 检查目标是否死亡（V4.1增强：同时检查IsDead属性作为兜底）
	-- 注意：客户端偶发存在Humanoid未复制完成的短窗口，此时不应直接判定目标无效
	local targetHumanoid = aiData.CurrentTarget:FindFirstChild("Humanoid")
	local targetIsDead = aiData.CurrentTarget:GetAttribute("IsDead")
	if targetIsDead or (targetHumanoid and targetHumanoid.Health <= 0) then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		-- 立即播放idle动画
		PlayAnimation(aiData, AnimationState.IDLE)
		return
	end

	-- V4.1修复：目标仍存活但距离很远时，定期重新评估最近目标（避免偶发锁到远处目标）
	if MaybeSwitchToCloserTarget(aiData) then
		return
	end

	-- 计算距离
	local distance = GetDistance(aiData.UnitModel, aiData.CurrentTarget)
	local dockingDistance = GetDockingDistance(aiData)

	if distance <= dockingDistance + CONFIG.ATTACK_RANGE_TOLERANCE then
		-- 已在攻击距离内，切换到ATTACKING状态
		aiData.State = AIState.ATTACKING
		aiData.AttackCooldown = 0
		aiData.IsAttacking = false
		DebugLog(aiData.UnitModel.Name, "进入攻击距离")

		-- 停止移动
		ClientPathService.StopMovement(aiData.UnitModel)
	else
		-- 距离过远，切换到MOVING状态
		aiData.State = AIState.MOVING
		DebugLog(aiData.UnitModel.Name, "开始移动到目标")
	end
end

--[[
MOVING状态：移动到攻击距离
V4.1增强：使用围攻位置系统 + Y轴地面钳定
]]
local function UpdateMovingState(aiData, deltaTime)
	-- 检查目标是否有效
	if not aiData.CurrentTarget or not aiData.CurrentTarget.Parent then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		ClientPathService.StopMovement(aiData.UnitModel)
		-- 立即播放idle动画
		PlayAnimation(aiData, AnimationState.IDLE)
		return
	end

	-- 检查目标是否死亡（V4.1增强：同时检查IsDead属性作为兜底）
	-- 注意：客户端偶发存在Humanoid未复制完成的短窗口，此时不应直接判定目标无效
	local targetHumanoid = aiData.CurrentTarget:FindFirstChild("Humanoid")
	local targetIsDead = aiData.CurrentTarget:GetAttribute("IsDead")
	if targetIsDead or (targetHumanoid and targetHumanoid.Health <= 0) then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		ClientPathService.StopMovement(aiData.UnitModel)
		-- 立即播放idle动画
		PlayAnimation(aiData, AnimationState.IDLE)
		return
	end

	-- V4.1修复：目标仍存活但距离很远时，定期重新评估最近目标（避免偶发锁到远处目标）
	if MaybeSwitchToCloserTarget(aiData) then
		return
	end

	-- V4.1新增：Y轴地面钳定（防止被顶起后沿空中移动）
	ClampToGround(aiData)

	-- 播放移动动画
	PlayAnimation(aiData, AnimationState.MOVE)

	-- 计算距离
	local distance = GetDistance(aiData.UnitModel, aiData.CurrentTarget)
	local dockingDistance = GetDockingDistance(aiData)

	if distance <= dockingDistance + CONFIG.ATTACK_RANGE_TOLERANCE then
		-- 到达攻击距离，切换到ATTACKING状态
		aiData.State = AIState.ATTACKING
		aiData.AttackCooldown = 0
		aiData.IsAttacking = false
		ClientPathService.StopMovement(aiData.UnitModel)
		DebugLog(aiData.UnitModel.Name, "到达攻击距离")
		return
	end

	-- V4.1增强：使用围攻位置系统计算目标位置
	local humanoid = aiData.UnitModel:FindFirstChild("Humanoid")
	if humanoid then
		-- 计算围攻位置（近战兵使用围攻系统，远程兵直接朝目标）
		local moveTarget = nil
		if aiData.UnitType == UnitConfig.UnitType.MELEE then
			moveTarget = ComputeSurroundPosition(aiData, aiData.CurrentTarget)
		end

		if not moveTarget then
			-- 远程兵或围攻计算失败，使用传统方式（保持停靠距离）
			local myRoot = aiData.UnitModel:FindFirstChild("HumanoidRootPart")
			local targetRoot = aiData.CurrentTarget:FindFirstChild("HumanoidRootPart")
			if myRoot and targetRoot then
				local myPos = myRoot.Position
				local targetPos = targetRoot.Position
				local direction = (targetPos - myPos)
				if direction.Magnitude > 0.1 then
					direction = direction.Unit
				else
					direction = Vector3.new(1, 0, 0)
				end
				-- 远程兵需要保持停靠距离，不能直接冲到目标位置
				local dockingDist = GetDockingDistance(aiData)
				moveTarget = targetPos - direction * dockingDist
			end
		end

		if moveTarget then
			-- ==================== V4.3修复：MoveTo控制权竞态 ====================
			-- 寻路修复：使用ClientPathService进行寻路，避免与FollowPath的MoveTo冲突
			if CONFIG.PATHFINDING.ENABLED and distance > CONFIG.PATHFINDING.DIRECT_MOVE_THRESHOLD then
				-- 距离较远时使用寻路
				local pathStatus = ClientPathService.GetPathStatus(aiData.UnitModel)

				-- 检查是否需要重新寻路
				local needRepath = ClientPathService.NeedRepath(aiData.UnitModel)
				local noPath = pathStatus == ClientPathService.PathStatus.IDLE or pathStatus == ClientPathService.PathStatus.FAILED

				if needRepath or noPath then
					-- 请求新路径
					local success = ClientPathService.RequestPath(aiData.UnitModel, moveTarget)
					if success then
						-- 开始跟随路径
						ClientPathService.FollowPath(aiData.UnitModel, nil, nil)
						DebugLog(aiData.UnitModel.Name, "寻路成功，开始跟随路径")
					else
						-- 寻路失败，回退到直线移动
						-- V4.3关键：先清理路径状态，避免MoveToFinished冲突
						ClientPathService.StopMovement(aiData.UnitModel)
						humanoid:MoveTo(moveTarget)
						DebugLog(aiData.UnitModel.Name, "寻路失败，使用直线移动")
					end
				elseif pathStatus == ClientPathService.PathStatus.SUCCESS then
					-- ✅ 已有有效路径，继续跟随
					-- V4.3修复：不额外调用MoveTo，避免与FollowPath内部的MoveTo冲突
					-- FollowPath会在内部自动调用humanoid:MoveTo(waypoint)
					-- 这里只调用FollowPath，确保路径继续推进
					ClientPathService.FollowPath(aiData.UnitModel, nil, nil)
				else
					-- 路径正在计算中或其他状态，暂时直线移动
					-- V4.3关键：先清理路径状态，避免MoveToFinished冲突
					ClientPathService.StopMovement(aiData.UnitModel)
					humanoid:MoveTo(moveTarget)
				end
			else
				-- 距离较近时直接移动（不需要寻路）
				-- V4.3关键修复：切换到直线移动前，必须先清理路径状态
				-- 否则FollowPath的MoveToFinished回调还活着，会收到误触发
				ClientPathService.StopMovement(aiData.UnitModel)
				humanoid:MoveTo(moveTarget)
			end
			-- ==================== 修复结束 ====================
		end
	end
end

--[[
ATTACKING状态：在攻击距离内，执行攻击
V4.1增强：添加Y轴地面钳定
]]
local function UpdateAttackingState(aiData, deltaTime)
	-- 检查目标是否有效
	if not aiData.CurrentTarget or not aiData.CurrentTarget.Parent then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		aiData.IsAttacking = false
		-- 立即播放idle动画（不等下一帧）
		PlayAnimation(aiData, AnimationState.IDLE)
		return
	end

	-- 检查目标是否死亡（V4.1增强：同时检查IsDead属性作为兜底）
	local targetHumanoid = aiData.CurrentTarget:FindFirstChild("Humanoid")
	local targetIsDead = aiData.CurrentTarget:GetAttribute("IsDead")
	if not targetHumanoid or targetHumanoid.Health <= 0 or targetIsDead then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		aiData.IsAttacking = false
		-- 立即播放idle动画（不等下一帧）
		PlayAnimation(aiData, AnimationState.IDLE)
		return
	end

	-- V4.1新增：Y轴地面钳定（防止被顶起后悬空攻击）
	ClampToGround(aiData)

	-- 计算距离
	local distance = GetDistance(aiData.UnitModel, aiData.CurrentTarget)
	local dockingDistance = GetDockingDistance(aiData)

	-- 检查是否脱离攻击距离
	if distance > dockingDistance + CONFIG.ATTACK_RANGE_TOLERANCE * 2 then
		-- 脱离攻击距离，切换回MOVING状态
		aiData.State = AIState.MOVING
		aiData.IsAttacking = false
		DebugLog(aiData.UnitModel.Name, "脱离攻击距离")
		return
	end

	-- 更新攻击冷却
	aiData.AttackCooldown = aiData.AttackCooldown - deltaTime

	-- 检查是否可以发起攻击
	if aiData.AttackCooldown <= 0 and not aiData.IsAttacking then
		-- 播放攻击动画
		PlayAnimation(aiData, AnimationState.ATTACK)

		-- 向服务端请求攻击判定
		local attackType = aiData.UnitType == UnitConfig.UnitType.MELEE and "Melee" or "Ranged"
		RequestAttack:FireServer(aiData.BattleId, aiData.UnitModel, aiData.CurrentTarget, attackType)

		-- 重置攻击冷却
		aiData.AttackCooldown = aiData.Stat.AttackSpeed
		aiData.IsAttacking = true

		DebugLog(aiData.UnitModel.Name, "发起攻击:", aiData.CurrentTarget.Name)

		-- 攻击动画播放完毕后重置IsAttacking标志
		task.delay(0.3, function()
			if aiData then
				aiData.IsAttacking = false
			end
		end)
	else
		-- 等待攻击冷却，播放待机动画
		if not aiData.IsAttacking then
			PlayAnimation(aiData, AnimationState.IDLE)
		end
	end
end

--[[
DEAD状态：单位死亡，停止所有AI
]]
local function UpdateDeadState(aiData, deltaTime)
	-- 死亡状态不做任何更新
	-- 等待服务端通知清理
end

-- ==================== AI更新循环 ====================

--[[
更新单个AI
@param aiData AIData
@param deltaTime number - 时间增量
]]
local function UpdateSingleAI(aiData, deltaTime)
	-- 根据状态调用对应的更新函数
	if aiData.State == AIState.IDLE then
		UpdateIdleState(aiData, deltaTime)
	elseif aiData.State == AIState.SEEKING then
		UpdateSeekingState(aiData, deltaTime)
	elseif aiData.State == AIState.MOVING then
		UpdateMovingState(aiData, deltaTime)
	elseif aiData.State == AIState.ATTACKING then
		UpdateAttackingState(aiData, deltaTime)
	elseif aiData.State == AIState.DEAD then
		UpdateDeadState(aiData, deltaTime)
	end
end

--[[
主更新循环（Heartbeat驱动）
]]
local function OnHeartbeat(deltaTime)
	accumulatedTime = accumulatedTime + deltaTime
	positionReportTime = positionReportTime + deltaTime

	-- AI更新节流
	if accumulatedTime < CONFIG.AI_UPDATE_INTERVAL then
		return
	end

	local dt = accumulatedTime
	accumulatedTime = 0

	-- 更新所有活跃AI
	for unitModel, aiData in pairs(activeAIs) do
		if unitModel and unitModel.Parent then
			UpdateSingleAI(aiData, dt)
		else
			-- 单位已被移除，清理AI数据
			activeAIs[unitModel] = nil
		end
	end

	-- 定期上报位置到服务端
	if positionReportTime >= CONFIG.POSITION_REPORT_INTERVAL then
		positionReportTime = 0
		for unitModel, aiData in pairs(activeAIs) do
			if unitModel and unitModel.Parent and aiData.State ~= AIState.DEAD then
				local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
				if rootPart then
					ReportUnitPosition:FireServer(
						aiData.BattleId,
						unitModel,
						rootPart.Position,
						aiData.State
					)
				end
			end
		end
	end
end

-- ==================== 公共接口 ====================

--[[
初始化客户端AI系统（依赖注入）
@param unitManager ClientUnitManager
@param pathService ClientPathService
]]
function ClientUnitAI.Initialize(unitManager, pathService)
	ClientUnitManager = unitManager
	ClientPathService = pathService

	-- 启动更新循环
	if not updateConnection then
		updateConnection = RunService.Heartbeat:Connect(OnHeartbeat)
	end

	DebugLog("客户端AI系统初始化完成")
	return true
end

--[[
启动单位AI
@param battleId number - 战斗ID
@param unitModel Model - 单位模型
@param unitId string - 单位配置ID
@param level number - 单位等级
@param team string - 队伍
@return boolean - 是否成功
]]
function ClientUnitAI.StartAI(battleId, unitModel, unitId, level, team)
	if not battleId or not unitModel or not unitId or not level or not team then
		WarnLog("启动AI失败：参数缺失")
		return false
	end

	-- 获取单位配置
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData then
		WarnLog("启动AI失败：找不到UnitConfig", unitId)
		return false
	end

	-- 获取Humanoid和Animator
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid then
		WarnLog("启动AI失败：找不到Humanoid", unitModel.Name)
		return false
	end

	-- V4.1修复：启动战斗AI前，强制停止任何残留的移动指令（行军/旧MoveTo/旧路径）
	-- 否则会出现“进入战斗先回头走一下再扭回来”的现象（旧目标点先被执行一帧）
	pcall(function()
		if ClientPathService then
			ClientPathService.StopMovement(unitModel)
		end
	end)
	pcall(function()
		humanoid:Move(Vector3.new(0, 0, 0))
		local rootPart = unitModel:FindFirstChild("HumanoidRootPart") or unitModel.PrimaryPart
		if rootPart then
			-- 用“走到当前位置”覆盖掉可能残留的WalkToPoint
			humanoid:MoveTo(rootPart.Position)
		end
	end)

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		-- V4.7修复：如果没有Animator，自动创建一个
		-- 这对于从ReplicatedStorage克隆的敌方单位很重要
		animator = Instance.new("Animator")
		animator.Parent = humanoid
		DebugLog(string.format("%s 自动创建Animator", unitModel.Name))
	end

	-- V4.0修复：禁用模型自带的Animate脚本，防止与客户端AI动画冲突
	local animateScript = unitModel:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = true
		DebugLog(string.format("%s 已禁用Animate脚本", unitModel.Name))
	end

	-- 加载动画并设置正确的Priority/Looped
	local animTrack = {
		Idle = nil,
		Move = nil,
		Attack = nil,
	}

	if unitData.IdleAnimationId and unitData.IdleAnimationId ~= "" then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. unitData.IdleAnimationId
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Idle
		track.Looped = true
		animTrack.Idle = track
	end

	if unitData.MoveAnimationId and unitData.MoveAnimationId ~= "" then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. unitData.MoveAnimationId
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = true
		animTrack.Move = track
	end

	if unitData.AttackAnimationId and unitData.AttackAnimationId ~= "" then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. unitData.AttackAnimationId
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		animTrack.Attack = track
		DebugLog(string.format("%s 加载攻击动画: %s (Priority=Action, Looped=false)", unitModel.Name, tostring(unitData.AttackAnimationId)))
	else
		WarnLog(string.format("%s 没有攻击动画ID!", unitModel.Name))
	end

	-- 创建AI数据
	local aiData = {
		BattleId = battleId,
		UnitModel = unitModel,
		UnitId = unitId,
		Level = level,
		Team = team,
		UnitType = unitData.Type,

		-- AI状态
		State = AIState.IDLE,
		CurrentTarget = nil,
		LastTargetCheckTime = 0,
		TargetAcquiredTime = 0,
		_DidInitialTargetCorrection = false,

		-- 攻击状态
		AttackCooldown = 0,
		IsAttacking = false,

		-- 单位属性
		Stat = {
			AttackRange = UnitConfig.GetAttackRange(unitId),
			AttackSpeed = UnitConfig.GetAttackSpeed(unitId),
			MoveSpeed = UnitConfig.GetMoveSpeed(unitId),
		},

		-- 动画
		AnimTrack = animTrack,
		CurrentAnimTrack = nil,
		CurrentAnimState = nil,
	}

	-- 注册到activeAIs
	activeAIs[unitModel] = aiData

	-- 设置移动速度
	humanoid.WalkSpeed = aiData.Stat.MoveSpeed

	DebugLog(string.format("启动AI: Unit=%s, UnitId=%s, Team=%s, BattleId=%s",
		tostring(unitModel.Name), tostring(unitId), tostring(team), tostring(battleId)))

	return true
end

--[[
停止单位AI
@param unitModel Model - 单位模型
]]
function ClientUnitAI.StopAI(unitModel)
	local aiData = activeAIs[unitModel]
	if not aiData then
		return
	end

	-- 停止所有动画
	if aiData.CurrentAnimTrack then
		aiData.CurrentAnimTrack:Stop(0)
	end

	-- 清理路径
	ClientPathService.ClearPath(unitModel)

	-- 停止移动
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.new(0, 0, 0))
	end

	-- 移除AI数据
	activeAIs[unitModel] = nil

	DebugLog("停止AI:", unitModel.Name)
end

--[[
标记单位死亡
@param unitModel Model - 单位模型
V4.2修复：立即停止所有移动和动画，冻结物理状态
]]
function ClientUnitAI.MarkDead(unitModel)
	local aiData = activeAIs[unitModel]
	if not aiData then
		return
	end

	aiData.State = AIState.DEAD
	aiData.CurrentTarget = nil
	aiData.IsAttacking = false

	-- 停止移动路径
	ClientPathService.ClearPath(unitModel)

	-- V4.2修复：立即停止所有动画（除了死亡动画由服务端控制）
	if aiData.CurrentAnimTrack then
		pcall(function()
			aiData.CurrentAnimTrack:Stop(0)
		end)
		aiData.CurrentAnimTrack = nil
	end

	-- 停止Idle和Move动画
	if aiData.AnimTrack then
		if aiData.AnimTrack.Idle then
			pcall(function() aiData.AnimTrack.Idle:Stop(0) end)
		end
		if aiData.AnimTrack.Move then
			pcall(function() aiData.AnimTrack.Move:Stop(0) end)
		end
		if aiData.AnimTrack.Attack then
			pcall(function() aiData.AnimTrack.Attack:Stop(0) end)
		end
	end

	-- V4.6修复：客户端侧避免继续驱动物理/动画
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		pcall(function()
			humanoid:Move(Vector3.zero)
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.AutoRotate = false
		end)
	end

	-- 清除速度（服务端已收回NetworkOwner，这里做兜底）
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if rootPart then
		pcall(function()
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	DebugLog("单位死亡:", unitModel.Name)
end

--[[
清理所有AI（战斗结束时调用）
]]
function ClientUnitAI.ClearAll()
	for unitModel, aiData in pairs(activeAIs) do
		ClientUnitAI.StopAI(unitModel)
	end
	activeAIs = {}
	DebugLog("所有AI已清理")
end

--[[
获取单位的AI状态
@param unitModel Model - 单位模型
@return string|nil - AI状态
]]
function ClientUnitAI.GetState(unitModel)
	local aiData = activeAIs[unitModel]
	if not aiData then
		return nil
	end
	return aiData.State
end

--[[
调试：打印所有AI状态
]]
function ClientUnitAI.DebugPrintAllStates()
	if not CONFIG.DEBUG_LOGS then
		return
	end

	DebugLog("=== ClientUnitAI Debug ===")
	for unitModel, aiData in pairs(activeAIs) do
		DebugLog(string.format("  %s: State=%s, Target=%s",
			unitModel.Name, aiData.State, aiData.CurrentTarget and aiData.CurrentTarget.Name or "nil"))
	end
	DebugLog("==========================")
end

return ClientUnitAI
