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

	-- 远程单位停靠距离系数
	RANGED_DOCKING_RATIO = 0.65,

	-- 调试日志
	DEBUG_LOGS = false,
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
		BattleConfig.TARGET_SEARCH_RANGE
	)

	if enemyUnit then
		-- 发现敌人，切换到SEEKING状态
		aiData.State = AIState.SEEKING
		aiData.CurrentTarget = enemyUnit
		aiData.LastTargetCheckTime = tick()
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
		return
	end

	-- 检查目标是否死亡（V4.1增强：同时检查IsDead属性作为兜底）
	local targetHumanoid = aiData.CurrentTarget:FindFirstChild("Humanoid")
	local targetIsDead = aiData.CurrentTarget:GetAttribute("IsDead")
	if not targetHumanoid or targetHumanoid.Health <= 0 or targetIsDead then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
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
]]
local function UpdateMovingState(aiData, deltaTime)
	-- 检查目标是否有效
	if not aiData.CurrentTarget or not aiData.CurrentTarget.Parent then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		ClientPathService.StopMovement(aiData.UnitModel)
		return
	end

	-- 检查目标是否死亡（V4.1增强：同时检查IsDead属性作为兜底）
	local targetHumanoid = aiData.CurrentTarget:FindFirstChild("Humanoid")
	local targetIsDead = aiData.CurrentTarget:GetAttribute("IsDead")
	if not targetHumanoid or targetHumanoid.Health <= 0 or targetIsDead then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		ClientPathService.StopMovement(aiData.UnitModel)
		return
	end

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

	-- 持续移动到目标位置
	local targetRoot = aiData.CurrentTarget:FindFirstChild("HumanoidRootPart")
	if targetRoot then
		local targetPos = targetRoot.Position
		-- 简化移动：直接使用Humanoid:MoveTo（避免频繁寻路）
		local humanoid = aiData.UnitModel:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:MoveTo(targetPos)
		end
	end
end

--[[
ATTACKING状态：在攻击距离内，执行攻击
]]
local function UpdateAttackingState(aiData, deltaTime)
	-- 检查目标是否有效
	if not aiData.CurrentTarget or not aiData.CurrentTarget.Parent then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		aiData.IsAttacking = false
		return
	end

	-- 检查目标是否死亡（V4.1增强：同时检查IsDead属性作为兜底）
	local targetHumanoid = aiData.CurrentTarget:FindFirstChild("Humanoid")
	local targetIsDead = aiData.CurrentTarget:GetAttribute("IsDead")
	if not targetHumanoid or targetHumanoid.Health <= 0 or targetIsDead then
		aiData.State = AIState.IDLE
		aiData.CurrentTarget = nil
		aiData.IsAttacking = false
		return
	end

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

	print(GameConfig.LOG_PREFIX, "[ClientUnitAI] 客户端AI系统初始化完成")
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

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		WarnLog("启动AI失败：找不到Animator", unitModel.Name)
		return false
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
]]
function ClientUnitAI.MarkDead(unitModel)
	local aiData = activeAIs[unitModel]
	if not aiData then
		return
	end

	aiData.State = AIState.DEAD
	aiData.CurrentTarget = nil

	-- 停止移动
	ClientPathService.ClearPath(unitModel)

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
	print("=== ClientUnitAI Debug ===")
	for unitModel, aiData in pairs(activeAIs) do
		print(string.format("  %s: State=%s, Target=%s",
			unitModel.Name, aiData.State, aiData.CurrentTarget and aiData.CurrentTarget.Name or "nil"))
	end
	print("==========================")
end

return ClientUnitAI
