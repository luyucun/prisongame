--=====================================================
-- UnitAI.lua (Modified RTS/MOBA Smooth Combat Movement)
-- Version: V5.7 (Multi-Ring Swarm System / 多层围攻系统)
--=====================================================
--[[
V5.7 围攻系统更新:
1. 自动多层围攻 (Adaptive Multi-Ring Swarm)
   - 第一批士兵进入内圈(6人)
   - 人多自动开启第二圈(12人)、第三圈(18人)...
   - 每层都有自己的角度分布,永远不会挤成一团

2. 单位智能角度分配 (Deterministic Angle Assignment)
   - 每个单位根据 SpawnIndex/UnitIndex 自动分到一个"扇形位"
   - 不抖动、不刷新、不重复随机

3. 避免友军密堆 (Local Separation / Boids避让)
   - 如果两单位距离太近 → 自动稍微改变偏移位置
   - 类似《魔兽争霸》或 MOBA 中的近战 AI

4. 动态扩圈 (Auto Radius Expansion)
   - 如果目标周围过满,自动把环半径扩张
   - 让30个兵围攻也能完美铺开

5. 适配迟滞区追击系统,不回头、不抖动
]]

local UnitAI = {}

-------------------------------------------------------
-- Services
-------------------------------------------------------
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-------------------------------------------------------
-- Config
-------------------------------------------------------
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-------------------------------------------------------
-- Lazy-loaded systems
-------------------------------------------------------
local CombatSystem = nil
local PathService = nil
local UnitManager = nil

local function LoadSystems()
	if not CombatSystem then
		CombatSystem = require(ServerScriptService.Systems.CombatSystem)
	end
	if not PathService then
		PathService = require(ServerScriptService.Systems.PathService)
	end
	if not UnitManager then
		UnitManager = require(ServerScriptService.Systems.UnitManager)
	end
end

-------------------------------------------------------
-- AI Config
-------------------------------------------------------
local CONFIG = {
	MAX_DIRECT_MOVE_DISTANCE = 10,

	-- MoveTo throttle
	MOVETO_THROTTLE_INTERVAL = 0.25,
	MOVETO_POSITION_THRESHOLD = 1.0,

	-- Stuck detection
	STUCK_CHECK_INTERVAL = 0.5,
	STUCK_MIN_VELOCITY = 0.5,
	STUCK_COUNT_THRESHOLD = 3,
	MIN_DISTANCE_FOR_CHECK = 5,

	DEBUG_LOGS = true,  -- 临时开启调试

	-- ==================== V5.7 围攻系统配置 ====================
	SURROUND = {
		-- 基础环形配置
		BASE_UNITS_PER_RING = 6,       -- 第一圈基础单位数
		RING_UNIT_INCREMENT = 6,       -- 每圈增加的单位数
		BASE_RING_RADIUS = 0.7,        -- 第一圈半径系数(相对于攻击距离)
		RING_RADIUS_INCREMENT = 4,     -- 每圈半径增加(studs)

		-- 动态扩圈配置
		MAX_RINGS = 5,                 -- 最大圈数
		CROWD_EXPANSION_THRESHOLD = 4, -- 过于拥挤时扩圈的单位数阈值(每圈)
		RADIUS_EXPANSION_STEP = 1.5,   -- 拥挤时半径扩张步长

		-- Boids避让配置
		SEPARATION_DISTANCE = 3.5,     -- 友军避让触发距离(studs)
		SEPARATION_STRENGTH = 0.4,     -- 避让力度系数
		MAX_SEPARATION_OFFSET = 2.0,   -- 最大避让偏移(studs)

		-- 角度抖动抑制
		ANGLE_STABILITY_THRESHOLD = 0.3, -- 角度变化阈值(弧度),小于此值不更新
		POSITION_UPDATE_COOLDOWN = 0.15, -- 位置更新冷却(秒)

		-- 调试
		DEBUG_SURROUND = false,        -- 是否输出围攻调试日志
	},
}

if BattleConfig then
	CONFIG.DEBUG_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_LOGS
end

-------------------------------------------------------
-- Constants
-------------------------------------------------------
local AIMode = {
	MARCH = "MarchMode",
	COMBAT = "CombatMode",
}

local AnimationState = {
	MOVE = "MOVE",
	IDLE = "IDLE",
	ATTACK = "ATTACK",
}

-------------------------------------------------------
-- Private state
-------------------------------------------------------
local activeAIs = {}
local updateConnection = nil
local deathEventConnection = nil
local accumulatedTime = 0

-- V5.7 围攻系统状态
local surroundTargetData = {}  -- [targetModel] = { units = {model=true}, lastUpdate = tick }

-- 全局递增计数器,用于分配唯一SlotId (替代GetDebugId)
local nextSlotIdCounter = 1

-------------------------------------------------------
-- Logging
-------------------------------------------------------
local function DebugLog(...)
	if CONFIG.DEBUG_LOGS then
		print("[UnitAI] ", ...)
	end
end

local function SurroundLog(...)
	if CONFIG.SURROUND.DEBUG_SURROUND then
		print("[UnitAI:Surround] ", ...)
	end
end

-------------------------------------------------------
-- Helpers (前置定义,供围攻系统使用)
-------------------------------------------------------
local function GetDistance(modelA: Model, modelB: Model): number
	local rootA = modelA:FindFirstChild("HumanoidRootPart") or modelA.PrimaryPart
	local rootB = modelB:FindFirstChild("HumanoidRootPart") or modelB.PrimaryPart
	if not rootA or not rootB then return 99999 end
	return ((rootA :: BasePart).Position - (rootB :: BasePart).Position).Magnitude
end

-------------------------------------------------------
-- V5.7 围攻系统核心模块 (Multi-Ring Swarm System)
-------------------------------------------------------
local SurroundSystem = {}

-- 获取单位的唯一槽位ID (确定性分配,不随机)
-- 优先使用SpawnIndex/UnitIndex属性,否则分配递增ID
local function GetUnitSlotId(model)
	-- 优先使用已存在的属性
	local slotId = model:GetAttribute("SpawnIndex")
		or model:GetAttribute("UnitIndex")
		or model:GetAttribute("UID")
		or model:GetAttribute("InstanceId")
		or model:GetAttribute("_AISlotId")  -- 内部分配的ID

	if slotId then
		-- 如果是字符串,转换为数字hash
		if type(slotId) == "string" then
			local hash = 0
			for i = 1, #slotId do
				hash = (hash * 31 + string.byte(slotId, i)) % 1000000
			end
			return hash
		end
		return tonumber(slotId) or 0
	end

	-- 没有任何属性时,分配一个新的递增ID并保存到模型属性
	-- 这样确保每个单位实例都有唯一的SlotId
	local newId = nextSlotIdCounter
	nextSlotIdCounter = nextSlotIdCounter + 1
	model:SetAttribute("_AISlotId", newId)

	return newId
end

-- 获取围攻同一目标的所有友军单位
local function GetUnitsAttackingSameTarget(targetModel: Model, myTeam: string, battleId: string)
	LoadSystems()

	local attackers = {}
	local count = 0

	-- 遍历所有活跃AI,找出攻击同一目标的友军
	for unitModel, aiData in pairs(activeAIs) do
		if unitModel and unitModel.Parent and aiData.Mode == AIMode.COMBAT then
			-- 检查是否是同队友军
			local unitInfo = UnitManager.GetUnitBattleInfo(unitModel)
			if unitInfo and unitInfo.Team == myTeam and unitInfo.BattleId == battleId then
				-- 检查是否攻击同一目标
				local currentTarget = CombatSystem.GetTarget(unitModel)
				if currentTarget == targetModel then
					count = count + 1
					attackers[unitModel] = {
						SlotId = GetUnitSlotId(unitModel),
						Distance = GetDistance(unitModel, targetModel),
						AttackRange = aiData.Stat.AttackRange or 6,
					}
				end
			end
		end
	end

	return attackers, count
end

-- 计算环形站位偏移 (核心算法)
-- 参数:
--   slotId: 单位唯一槽位ID
--   attackRange: 攻击距离
--   totalAttackers: 攻击同一目标的总单位数
--   attackersList: 攻击者列表(用于计算在哪一层)
-- 返回:
--   Vector3 偏移量 (相对于目标位置)
function SurroundSystem.ComputeRingOffset(slotId: number, attackRange: number, totalAttackers: number, attackersList)
	local cfg = CONFIG.SURROUND

	-- 对所有攻击者按SlotId排序,确定当前单位的排序位置
	local sortedSlots = {}
	for unitModel, data in pairs(attackersList) do
		table.insert(sortedSlots, { SlotId = data.SlotId, Model = unitModel })
	end
	table.sort(sortedSlots, function(a, b) return a.SlotId < b.SlotId end)

	-- 找到当前单位的排序索引(0-based)
	local myIndex = 0
	for i, entry in ipairs(sortedSlots) do
		if entry.SlotId == slotId then
			myIndex = i - 1
			break
		end
	end

	-- 计算所在环层和环内位置
	-- 第1层: 0 ~ BASE_UNITS_PER_RING-1
	-- 第2层: BASE_UNITS_PER_RING ~ BASE_UNITS_PER_RING+RING_UNIT_INCREMENT-1
	-- ...
	local ringIndex = 0        -- 第几圈(0-based)
	local indexInRing = 0      -- 圈内第几个(0-based)
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
	-- 第1圈: attackRange * BASE_RING_RADIUS
	-- 后续圈: 第1圈半径 + ringIndex * RING_RADIUS_INCREMENT
	local baseRadius = attackRange * cfg.BASE_RING_RADIUS
	local radius = baseRadius + ringIndex * cfg.RING_RADIUS_INCREMENT

	-- 动态扩圈: 如果当前圈太拥挤,稍微扩大半径
	local crowdInRing = 0
	for _, entry in ipairs(sortedSlots) do
		local entryIndex = 0
		local acc = 0
		for r = 0, cfg.MAX_RINGS - 1 do
			local uir = cfg.BASE_UNITS_PER_RING + r * cfg.RING_UNIT_INCREMENT
			if entry.SlotId < acc + uir then
				if r == ringIndex then
					crowdInRing = crowdInRing + 1
				end
				break
			end
			acc = acc + uir
		end
	end
	-- 实际用sortedSlots的位置来判断更准确
	-- 重新计算当前圈的实际人数
	crowdInRing = 0
	for i, entry in ipairs(sortedSlots) do
		local idx = i - 1
		local acc = 0
		for r = 0, cfg.MAX_RINGS - 1 do
			local uir = cfg.BASE_UNITS_PER_RING + r * cfg.RING_UNIT_INCREMENT
			if idx < acc + uir then
				if r == ringIndex then
					crowdInRing = crowdInRing + 1
				end
				break
			end
			acc = acc + uir
		end
	end

	if crowdInRing > cfg.CROWD_EXPANSION_THRESHOLD then
		local expansion = (crowdInRing - cfg.CROWD_EXPANSION_THRESHOLD) * cfg.RADIUS_EXPANSION_STEP * 0.3
		radius = radius + expansion
	end

	-- 计算角度 (均匀分布在圆周上)
	-- 使用黄金角度偏移,让多圈之间的单位错开
	local goldenAngle = math.pi * (3 - math.sqrt(5))  -- ~137.5度
	local baseAngle = (indexInRing / unitsInCurrentRing) * math.pi * 2
	local ringOffset = ringIndex * goldenAngle  -- 每圈错开一个黄金角

	local angle = baseAngle + ringOffset

	-- 计算最终偏移
	local offsetX = math.cos(angle) * radius
	local offsetZ = math.sin(angle) * radius

	SurroundLog(string.format("SlotId=%s, Ring=%d, IndexInRing=%d/%d, Radius=%.1f, Angle=%.1f",
		tostring(slotId), ringIndex :: number, indexInRing :: number, unitsInCurrentRing :: number, radius :: number, math.deg(angle) :: number))

	return Vector3.new(offsetX, 0, offsetZ)
end

-- Boids式友军避让 (Local Separation)
-- 检测附近友军,计算避让偏移
function SurroundSystem.ComputeSeparationOffset(model: Model, myPosition: Vector3, myTeam: string, battleId: string): Vector3
	LoadSystems()
	local cfg = CONFIG.SURROUND

	local separationForce = Vector3.zero
	local neighborCount = 0

	-- 遍历活跃AI,找附近的友军
	for otherModel, otherAiData in pairs(activeAIs) do
		if otherModel ~= model and otherModel and otherModel.Parent then
			-- 检查是否是同队友军
			local unitInfo = UnitManager.GetUnitBattleInfo(otherModel)
			if unitInfo and unitInfo.Team == myTeam and unitInfo.BattleId == battleId then
				local otherRoot = otherModel:FindFirstChild("HumanoidRootPart")
				if otherRoot then
					local otherPos = (otherRoot :: BasePart).Position
					local toOther = otherPos - myPosition
					local dist = toOther.Magnitude

					-- 如果太近,计算推开力
					if dist > 0.1 and dist < cfg.SEPARATION_DISTANCE then
						-- 距离越近,推力越大
						local strength = (cfg.SEPARATION_DISTANCE - dist) / cfg.SEPARATION_DISTANCE
						local pushDir = -toOther.Unit  -- 反方向
						separationForce = separationForce + pushDir * strength
						neighborCount = neighborCount + 1
					end
				end
			end
		end
	end

	-- 平均化并限制最大偏移
	if neighborCount > 0 then
		separationForce = separationForce / neighborCount
		separationForce = separationForce * cfg.SEPARATION_STRENGTH

		-- 限制最大偏移
		if separationForce.Magnitude > cfg.MAX_SEPARATION_OFFSET then
			separationForce = separationForce.Unit * cfg.MAX_SEPARATION_OFFSET
		end

		-- 只保留水平方向
		separationForce = Vector3.new(separationForce.X, 0, separationForce.Z)
	end

	return separationForce
end

-- 计算围攻目标位置 (整合环形站位 + 避让)
-- @param skipSeparation: 是否跳过避让计算(追击时跳过,微调时使用)
function SurroundSystem.ComputeSurroundPosition(model: Model, aiData, target: Model, skipSeparation: boolean?): (Vector3?, boolean)
	LoadSystems()

	local myRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tarRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not myRoot or not tarRoot then return nil, false end

	local myPos = myRoot.Position
	local targetPos = tarRoot.Position

	-- 获取单位信息
	local unitInfo = UnitManager.GetUnitBattleInfo(model)
	if not unitInfo then return nil, false end

	local myTeam = unitInfo.Team
	local battleId = unitInfo.BattleId
	local attackRange = aiData.Stat.AttackRange or 6
	local slotId = GetUnitSlotId(model)

	-- 获取攻击同一目标的所有友军
	local attackers, totalAttackers = GetUnitsAttackingSameTarget(target, myTeam, battleId)

	-- 如果只有自己,直接朝目标移动
	if totalAttackers <= 1 then
		local direction = (targetPos - myPos).Unit
		local dockingDistance = attackRange * 0.8
		return targetPos - direction * dockingDistance, false
	end

	-- 计算环形站位偏移
	local ringOffset = SurroundSystem.ComputeRingOffset(slotId, attackRange, totalAttackers, attackers)

	-- 计算避让偏移 (追击时跳过,只在微调时使用)
	local separationOffset = Vector3.zero
	if not skipSeparation then
		separationOffset = SurroundSystem.ComputeSeparationOffset(model, myPos, myTeam, battleId)
	end

	-- 合成最终位置
	local surroundPos = targetPos + ringOffset + separationOffset

	-- 抖动抑制: 如果新位置与上次位置差异很小,保持不变
	if aiData._LastSurroundPos then
		local posDiff = (surroundPos - aiData._LastSurroundPos).Magnitude
		local timeSinceUpdate = tick() - (aiData._LastSurroundTime or 0)

		if posDiff < 1.5 and timeSinceUpdate < CONFIG.SURROUND.POSITION_UPDATE_COOLDOWN then
			return aiData._LastSurroundPos, true
		end
	end

	-- 更新缓存
	aiData._LastSurroundPos = surroundPos
	aiData._LastSurroundTime = tick()

	SurroundLog(string.format("%s -> 围攻位置 (Total=%d, Ring偏移=%.1f,%.1f, 避让=%.1f,%.1f)",
		model.Name, totalAttackers :: number,
		ringOffset.X, ringOffset.Z,
		separationOffset.X, separationOffset.Z))

	return surroundPos, true
end

-------------------------------------------------------
-- Helpers (其他辅助函数)
-------------------------------------------------------
local function SafeStopAnimation(track)
	if track and track.IsPlaying then
		pcall(function() track:Stop(0.15) end)
	end
end

-------------------------------------------------------
-- Animation Controller (完整实现)
-------------------------------------------------------
local AnimationController = {}

-- 获取或创建Animator
local function GetAnimator(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

-- 加载动画轨道
local function LoadAnimationTrack(model, animationId)
	if not animationId or animationId == "" then return nil end

	local animator = GetAnimator(model)
	if not animator then return nil end

	local anim = Instance.new("Animation")
	-- 确保动画ID格式正确
	if not animationId:match("^rbxassetid://") then
		anim.AnimationId = "rbxassetid://" .. animationId
	else
		anim.AnimationId = animationId
	end

	local success, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)

	anim:Destroy()

	if success and track then
		return track
	end
	return nil
end

function AnimationController.SwitchToIdle(model, aiData)
	if aiData.CurrentAnimState == AnimationState.IDLE then return end
	aiData.CurrentAnimState = AnimationState.IDLE

	-- 停止移动动画
	SafeStopAnimation(aiData.Tracks.Move)
	-- 停止攻击动画
	SafeStopAnimation(aiData.Tracks.Attack)
	-- 停止idle动画（如果有的话，为了重新播放）
	SafeStopAnimation(aiData.Tracks.Idle)
end

function AnimationController.SwitchToMove(model, aiData)
	-- 停止攻击动画
	SafeStopAnimation(aiData.Tracks.Attack)

	-- 检查移动动画是否已在播放
	if aiData.Tracks.Move and aiData.Tracks.Move.IsPlaying then
		return  -- 已经在播放移动动画
	end

	aiData.CurrentAnimState = AnimationState.MOVE

	-- 播放移动动画
	local moveAnimId = aiData.Stat.MoveAnimationId
	if moveAnimId and moveAnimId ~= "" then
		local track = LoadAnimationTrack(model, moveAnimId)
		if track then
			track.Priority = Enum.AnimationPriority.Movement
			track.Looped = true
			track:Play(0.2)
			aiData.Tracks.Move = track
			DebugLog(model.Name .. " 播放移动动画 (AnimId: " .. tostring(moveAnimId) .. ")")
		else
			DebugLog(model.Name .. " 移动动画加载失败 (AnimId: " .. tostring(moveAnimId) .. ")")
		end
	end
end

function AnimationController.SwitchToAttack(model, aiData, target)
	-- 攻击状态需要每次都尝试攻击（不检查CurrentAnimState）
	-- 因为攻击有冷却，需要持续尝试

	LoadSystems()

	-- 检查是否可以攻击（CombatSystem的冷却检查）
	if not CombatSystem.CanAttack(model) then
		-- 攻击冷却中，播放idle动画
		AnimationController.PlayIdleAnimation(model, aiData)
		return false
	end

	-- 停止移动动画
	SafeStopAnimation(aiData.Tracks.Move)

	-- 开始攻击（设置CombatSystem状态）
	local beginSuccess = CombatSystem.BeginAttack(model, target)
	if not beginSuccess then
		return false
	end

	aiData.CurrentAnimState = AnimationState.ATTACK

	-- 播放攻击动画
	local attackAnimId = aiData.Stat.AttackAnimationId
	if attackAnimId and attackAnimId ~= "" then
		local track = LoadAnimationTrack(model, attackAnimId)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			track:Play(0.1)
			aiData.Tracks.Attack = track

			-- 监听动画事件（Damage事件触发伤害）
			local markerConnection
			markerConnection = track:GetMarkerReachedSignal("Damage"):Connect(function()
				-- 检查是否是远程单位
				local isRanged = UnitConfig.IsRangedUnit and UnitConfig.IsRangedUnit(aiData.UnitId)
				if isRanged then
					CombatSystem.OnRangedDamageEvent(model, target)
				else
					CombatSystem.OnDamageEvent(model)
				end
			end)

			-- 动画结束时：断开连接并播放idle动画
			track.Stopped:Once(function()
				if markerConnection then
					markerConnection:Disconnect()
				end
				-- 攻击动画结束后切换到idle动画
				aiData.CurrentAnimState = AnimationState.IDLE
				AnimationController.PlayIdleAnimation(model, aiData)
			end)

			DebugLog(string.format("%s 播放攻击动画", model.Name))
		else
			-- 如果没有攻击动画，直接触发伤害
			task.delay(0.3, function()
				if CombatSystem.GetAttackPhase(model) == BattleConfig.AttackPhase.ATTACKING then
					local isRanged = UnitConfig.IsRangedUnit and UnitConfig.IsRangedUnit(aiData.UnitId)
					if isRanged then
						CombatSystem.OnRangedDamageEvent(model, target)
					else
						CombatSystem.OnDamageEvent(model)
					end
				end
				-- 切换到idle
				aiData.CurrentAnimState = AnimationState.IDLE
				AnimationController.PlayIdleAnimation(model, aiData)
			end)
		end
	end

	return true
end

-- 播放Idle动画（攻击准备姿势）
function AnimationController.PlayIdleAnimation(model, aiData)
	-- 如果已经在播放idle动画，不重复播放
	if aiData.Tracks.Idle and aiData.Tracks.Idle.IsPlaying then
		return
	end

	local idleAnimId = aiData.Stat.IdleAnimationId
	if idleAnimId and idleAnimId ~= "" then
		local track = LoadAnimationTrack(model, idleAnimId)
		if track then
			track.Priority = Enum.AnimationPriority.Idle
			track.Looped = true
			track:Play(0.15)
			aiData.Tracks.Idle = track
			DebugLog(string.format("%s 播放Idle动画", model.Name))
		end
	end
end

-------------------------------------------------------
-- Validate Target
-------------------------------------------------------
local function ValidateTarget(model)
	LoadSystems()  -- 确保CombatSystem已加载
	local target = CombatSystem.GetTarget(model)
	if not target then return nil end
	if not target.Parent then return nil end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then return nil end
	return target
end

-------------------------------------------------------
-- Find and Set Target (寻找最近敌人并设置目标)
-------------------------------------------------------
local function FindAndSetTarget(model, aiData)
	LoadSystems()

	-- 获取最近的敌人
	local closestEnemy, distance = UnitManager.GetClosestEnemy(model, 9999)

	if closestEnemy then
		-- 检查敌人是否存活
		local enemyHumanoid = closestEnemy:FindFirstChildOfClass("Humanoid")
		if enemyHumanoid and enemyHumanoid.Health > 0 then
			CombatSystem.SetTarget(model, closestEnemy)
			return closestEnemy
		end
	end

	-- 没找到有效目标，清除当前目标
	CombatSystem.SetTarget(model, nil)
	return nil
end

-------------------------------------------------------
-- RTS/MOBA Smooth Combat Distance Control
--
-- ★ 核心改动点：加入迟滞区（Hysteresis）
-------------------------------------------------------

local function ShouldHoldAttackPosition(distance, dockingDistance, aiData)
	-- 进入攻击状态的阈值（稍微大一些）
	local ENTER_RANGE = dockingDistance + 1.0

	-- 退出攻击（需要追上去）的阈值（更大）
	local EXIT_RANGE = dockingDistance + 3.0

	-- 若当前尚未进入攻击区，则当距离 <= ENTER_RANGE 切换为“保持不动”
	if not aiData._InAttackHold then
		if distance <= ENTER_RANGE then
			aiData._InAttackHold = true
		end
	else
		-- 已经处于保持区，若距离超过一个更大的阈值，才退出保持区
		if distance >= EXIT_RANGE then
			aiData._InAttackHold = false
		end
	end

	-- 返回该单位是否应该保持不动（不移动）
	return aiData._InAttackHold
end

-------------------------------------------------------
-- Combat Movement (with RTS/MOBA smoothing + V5.7围攻系统)
-- 注: 只有玩家方(Attack)使用围攻系统,敌方(Defense)使用简单追击
-------------------------------------------------------

local function HandleCombatMovement(model, aiData, deltaTime)
	local humanoid = aiData.Humanoid
	if not humanoid then return end

	-- ⭐ 首先验证当前目标，如果无效则寻找新目标
	local target = ValidateTarget(model)
	if not target then
		-- 当前目标无效，尝试寻找新目标
		target = FindAndSetTarget(model, aiData)
	end

	-- 如果仍然没有目标，进入待机状态
	if not target then
		AnimationController.SwitchToIdle(model, aiData)
		return
	end

	local myRoot = model:FindFirstChild("HumanoidRootPart")
	local tarRoot = target:FindFirstChild("HumanoidRootPart")
	if not myRoot or not tarRoot then return end

	local myPos = myRoot.Position
	local targetPos = tarRoot.Position

	-- 兵种攻击距离（含 docking）
	local stat = aiData.Stat
	local dockingDistance = stat.AttackRange or 6

	local distance = (targetPos - myPos).Magnitude

	-- 判断是否是玩家方单位(只有玩家方使用围攻系统)
	local unitInfo = UnitManager.GetUnitBattleInfo(model)
	local isPlayerUnit = unitInfo and unitInfo.Team == "Attack"

	---------------------------------------------------
	-- ① 使用"迟滞区"决定是否保持当前攻击位置
	---------------------------------------------------
	local holdPosition = ShouldHoldAttackPosition(distance, dockingDistance, aiData)

	---------------------------------------------------
	-- ② 根据 holdPosition 选择移动策略
	---------------------------------------------------
	if holdPosition then
		-- ★ 在攻击区间：尝试攻击
		local attackStarted = AnimationController.SwitchToAttack(model, aiData, target)

		if not attackStarted then
			-- 攻击冷却中
			if isPlayerUnit then
				-- V5.7: 玩家方使用围攻位置微调 (此时使用避让)
				local surroundPos, usingSurround = SurroundSystem.ComputeSurroundPosition(model, aiData, target, false)
				if surroundPos and usingSurround then
					local toSurround = surroundPos - myPos
					local distToSurround = toSurround.Magnitude

					-- 只有距离围攻位置较远时才微调
					if distToSurround > 1.5 then
						humanoid:MoveTo(surroundPos)
					else
						humanoid:Move(Vector3.zero)
					end
				else
					humanoid:Move(Vector3.zero)
				end
			else
				-- 敌方单位: 简单停止移动
				humanoid:Move(Vector3.zero)
			end
		else
			-- 正在攻击,停止移动
			humanoid:Move(Vector3.zero)
		end
		return
	end

	---------------------------------------------------
	-- ③ 若不在攻击区间 → 需要追击
	---------------------------------------------------
	AnimationController.SwitchToMove(model, aiData)

	local desiredPos

	if isPlayerUnit then
		-- V5.7: 玩家方使用围攻系统计算目标位置 (追击时跳过避让,避免蜗牛速度)
		local surroundPos, usingSurround = SurroundSystem.ComputeSurroundPosition(model, aiData, target, true)
		if surroundPos then
			desiredPos = surroundPos
		else
			-- 围攻系统无法计算位置,使用传统方式
			local direction = (targetPos - myPos).Unit
			desiredPos = targetPos - direction * dockingDistance
		end
	else
		-- 敌方单位: 简单直线追击
		local direction = (targetPos - myPos).Unit
		desiredPos = targetPos - direction * dockingDistance
	end

	-- MoveTo 节流（防抖）
	aiData.LastMoveTo = aiData.LastMoveTo or 0
	aiData.LastMoveTo = aiData.LastMoveTo - deltaTime

	if aiData.LastMoveTo <= 0 then
		humanoid:MoveTo(desiredPos)
		aiData.LastMoveTo = CONFIG.MOVETO_THROTTLE_INTERVAL
	end

	---------------------------------------------------
	-- ④ 卡住检测（适当放宽）
	---------------------------------------------------
	aiData._stuckTimer = (aiData._stuckTimer or 0) + deltaTime

	if aiData._stuckTimer >= CONFIG.STUCK_CHECK_INTERVAL then
		aiData._stuckTimer = 0

		local velocity = myRoot.Velocity.Magnitude
		local tooClose = (distance <= dockingDistance + 1)
		if not tooClose and velocity <= CONFIG.STUCK_MIN_VELOCITY then
			aiData._stuckCount = (aiData._stuckCount or 0) + 1
		else
			aiData._stuckCount = 0
		end

		if aiData._stuckCount >= CONFIG.STUCK_COUNT_THRESHOLD then
			aiData._stuckCount = 0
			-- ★ 卡住时清除围攻位置缓存(仅玩家方有效)
			aiData._LastSurroundPos = nil
			humanoid:MoveTo(desiredPos)
		end
	end
end

-------------------------------------------------------
-- March Movement (unchanged from your latest)
-------------------------------------------------------

local function HandleMarchMovement(model, aiData, deltaTime)
	local humanoid = aiData.Humanoid
	if not humanoid then return end

	if PathService.IsUnitMarching(model) then
		AnimationController.SwitchToMove(model, aiData)
	else
		AnimationController.SwitchToIdle(model, aiData)
	end
end

-------------------------------------------------------
-- AI Update Loop
-------------------------------------------------------

local function UpdateAI(deltaTime)
	for model, aiData in pairs(activeAIs) do
		if not model.Parent then
			activeAIs[model] = nil
			continue
		end

		if aiData.Mode == AIMode.MARCH then
			HandleMarchMovement(model, aiData, deltaTime)
		else
			HandleCombatMovement(model, aiData, deltaTime)
		end
	end
end

-------------------------------------------------------
-- Start AI
-------------------------------------------------------

function UnitAI.StartAI(model)
	LoadSystems()

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- 获取UnitId: 优先从属性获取，其次从模型名解析，最后使用模型名
	local unitId = model:GetAttribute("UnitId")
	if not unitId then
		-- 尝试从模型名解析 (格式如 "10001_Lv1_1")
		unitId = model.Name:match("^(%d+)_") or model.Name
	end

	-- 如果UnitId是名称（如"Baseball"），尝试通过名称反向查找
	local stat = UnitConfig.Units[unitId]
	if not stat then
		-- 遍历查找匹配的Name字段
		for id, unitData in pairs(UnitConfig.Units) do
			if unitData.Name == unitId or unitData.Name == model.Name then
				stat = unitData
				unitId = id
				break
			end
		end
	end

	if not stat then
		warn("[UnitAI] Cannot find UnitConfig for", model.Name, "UnitId:", unitId)
		return
	end

	-- 清空行军状态（避免 PathService 冲突）
	PathService.ClearPath(model)

	-- AI 初始化
	activeAIs[model] = {
		Humanoid = humanoid,
		Mode = AIMode.COMBAT,
		Stat = stat,
		UnitId = unitId,  -- 保存UnitId用于攻击判定
		CurrentAnimState = AnimationState.IDLE,
		Tracks = {},  -- 动画轨道存储

		_InAttackHold = false, -- ★ 用于迟滞区
		_stuckTimer = 0,
		_stuckCount = 0,

		-- V5.7 围攻系统状态
		_LastSurroundPos = nil,    -- 上次围攻位置缓存
		_LastSurroundTime = 0,     -- 上次围攻位置更新时间
	}

	DebugLog(string.format("StartAI: %s (UnitId: %s)", model.Name, unitId))
	AnimationController.SwitchToIdle(model, activeAIs[model])
end

-------------------------------------------------------
-- Stop AI
-------------------------------------------------------

function UnitAI.StopAI(model)
	local aiData = activeAIs[model]
	if aiData then
		-- 停止所有动画
		SafeStopAnimation(aiData.Tracks.Move)
		SafeStopAnimation(aiData.Tracks.Attack)
		activeAIs[model] = nil
	end
end

-------------------------------------------------------
-- Clear Battle AIs (清理指定战斗的所有AI)
-------------------------------------------------------

function UnitAI.ClearBattleAIs(battleId)
	LoadSystems()

	local clearedCount = 0
	for model, aiData in pairs(activeAIs) do
		-- 通过UnitManager检查单位是否属于这个战斗
		local unitInfo = UnitManager.GetUnitBattleInfo(model)
		if unitInfo and unitInfo.BattleId == battleId then
			-- 停止动画
			SafeStopAnimation(aiData.Tracks.Move)
			SafeStopAnimation(aiData.Tracks.Attack)
			SafeStopAnimation(aiData.Tracks.Idle)

			-- 停止Humanoid移动,防止抖动
			if aiData.Humanoid then
				pcall(function()
					aiData.Humanoid:Move(Vector3.zero)
				end)
			end

			activeAIs[model] = nil
			clearedCount = clearedCount + 1
		end
	end

	DebugLog(string.format("ClearBattleAIs: 清理了 %d 个AI (BattleId: %s)", clearedCount, tostring(battleId)))
end

-------------------------------------------------------
-- Initialize (供MainServer调用)
-------------------------------------------------------

function UnitAI.Initialize()
	-- UnitAI的初始化逻辑已在模块顶层完成（Heartbeat连接和死亡事件绑定）
	-- 此函数用于兼容MainServer的统一初始化流程
	print("[UnitAI] 兵种AI系统初始化完成")
	return true
end

-------------------------------------------------------
-- Set AI Mode (供CampaignManager调用)
-------------------------------------------------------

function UnitAI.SetMode(model, mode)
	local aiData = activeAIs[model]
	if aiData then
		if mode == "MarchMode" or mode == AIMode.MARCH then
			aiData.Mode = AIMode.MARCH
		elseif mode == "CombatMode" or mode == AIMode.COMBAT then
			aiData.Mode = AIMode.COMBAT
		end
		DebugLog(string.format("SetMode: %s -> %s", model.Name, mode))
		return true
	end
	return false
end

-------------------------------------------------------
-- Animation Playback (供CampaignManager调用)
-------------------------------------------------------

function UnitAI.PlayMoveAnimation(model)
	if not model or not model.Parent then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn("[UnitAI] PlayMoveAnimation: 模型没有Animator -", model.Name)
		return
	end

	-- 获取UnitId: 优先从属性获取，其次从模型名解析
	local unitId = model:GetAttribute("UnitId")
	if not unitId then
		unitId = model.Name:match("^(%d+)_") or model.Name
	end

	-- 如果UnitId是名称，尝试通过名称反向查找
	local unitData = UnitConfig.Units[unitId]
	if not unitData then
		for id, data in pairs(UnitConfig.Units) do
			if data.Name == unitId or data.Name == model.Name then
				unitData = data
				unitId = id
				break
			end
		end
	end

	if not unitData then
		warn("[UnitAI] PlayMoveAnimation: 找不到UnitConfig -", model.Name, "UnitId:", tostring(unitId))
		return
	end

	local moveAnimId = unitData.MoveAnimationId
	if not moveAnimId or moveAnimId == "" then
		return  -- 没有移动动画配置
	end

	-- 确保动画ID格式正确
	local animationId = tostring(moveAnimId)
	if not string.match(animationId, "^rbxassetid://") then
		animationId = "rbxassetid://" .. animationId
	end

	-- 创建并播放动画
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId

	local success, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)

	if success and track then
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = true
		track:Play(0.2)

		-- 存储到aiData以便后续停止
		local aiData = activeAIs[model]
		if aiData then
			aiData.Tracks = aiData.Tracks or {}
			aiData.Tracks.Move = track
		end

		print("[UnitAI] " .. model.Name .. " 播放移动动画 (UnitId: " .. tostring(unitId) .. ", AnimId: " .. tostring(moveAnimId) .. ")")
	else
		warn("[UnitAI] PlayMoveAnimation: 动画加载失败 -", model.Name, animationId)
	end

	anim:Destroy()
end

function UnitAI.StopMoveAnimation(model)
	if not model then return end

	local aiData = activeAIs[model]
	if aiData and aiData.Tracks and aiData.Tracks.Move then
		SafeStopAnimation(aiData.Tracks.Move)
		aiData.Tracks.Move = nil
	end
end

-------------------------------------------------------
-- Death Animation (供CombatSystem调用)
-------------------------------------------------------

function UnitAI.BeginDeathAnimation(model, deathAnimId, unitId)
	if not model or not model.Parent then return end

	print("[UnitAI] BeginDeathAnimation 调用: " .. model.Name .. ", AnimId: " .. tostring(deathAnimId))

	-- 停止AI并清理动画
	local aiData = activeAIs[model]
	if aiData then
		SafeStopAnimation(aiData.Tracks.Move)
		SafeStopAnimation(aiData.Tracks.Attack)
		SafeStopAnimation(aiData.Tracks.Idle)
	end

	-- 禁用Animate脚本（防止干扰死亡动画）
	local animateScript = model:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = true
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn("[UnitAI] BeginDeathAnimation: 没有Animator -", model.Name)
		return
	end

	-- 停止所有当前动画
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function() track:Stop(0) end)
	end

	-- 播放死亡动画
	if deathAnimId and deathAnimId ~= "" then
		-- 确保动画ID格式正确
		local animationId = tostring(deathAnimId)
		if not string.match(animationId, "^rbxassetid://") then
			animationId = "rbxassetid://" .. animationId
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = animationId

		local success, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)

		if success and track then
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			track:Play(0)
			print("[UnitAI] " .. model.Name .. " 播放死亡动画成功 (AnimId: " .. tostring(deathAnimId) .. ")")
		else
			warn("[UnitAI] BeginDeathAnimation: 动画加载失败 -", model.Name, animationId)
		end

		anim:Destroy()
	else
		warn("[UnitAI] BeginDeathAnimation: 没有死亡动画配置 -", model.Name)
	end
end

-------------------------------------------------------
-- Reset Model Transparency (供CampaignManager/CombatSystem调用)
-------------------------------------------------------

function UnitAI.ResetModelTransparency(model)
	if not model then return end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			-- HumanoidRootPart通常是透明的，保持不变
			if part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0
			end
			-- 清除临时保存的原始透明度属性
			pcall(function()
				part:SetAttribute("_OrigTrans", nil)
			end)
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 0
			pcall(function()
				part:SetAttribute("_OrigTrans", nil)
			end)
		end
	end

	DebugLog(string.format("%s 透明度已重置", model.Name))
end

-------------------------------------------------------
-- Bind Global Update
-------------------------------------------------------

if not updateConnection then
	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulatedTime += dt
		UpdateAI(dt)
	end)
end

-------------------------------------------------------
-- Bind death auto cleanup
-------------------------------------------------------

if not deathEventConnection then
	-- 延迟绑定死亡事件，因为UnitDeath是BindableEvent
	local eventsFolder = ReplicatedStorage:WaitForChild("Events")
	local battleEventsFolder = eventsFolder:WaitForChild("BattleEvents")
	local unitDeathEvent = battleEventsFolder:WaitForChild("UnitDeath")

	if unitDeathEvent then
		deathEventConnection = unitDeathEvent.Event:Connect(function(model, killer, battleId)
			UnitAI.StopAI(model)
		end)
	end
end

-------------------------------------------------------
-- Return
-------------------------------------------------------

return UnitAI
