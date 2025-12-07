--=====================================================
-- UnitAI.lua (Modified RTS/MOBA Smooth Combat Movement)
-- Version: V5.6-R (Revised by ChatGPT)
--=====================================================

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

-------------------------------------------------------
-- Logging
-------------------------------------------------------
local function DebugLog(...)
	if CONFIG.DEBUG_LOGS then
		print("[UnitAI] ", ...)
	end
end

-------------------------------------------------------
-- Helpers
-------------------------------------------------------
local function GetDistance(modelA, modelB)
	local rootA = modelA:FindFirstChild("HumanoidRootPart") or modelA.PrimaryPart
	local rootB = modelB:FindFirstChild("HumanoidRootPart") or modelB.PrimaryPart
	if not rootA or not rootB then return 99999 end
	return (rootA.Position - rootB.Position).Magnitude
end

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
-- Combat Movement (with RTS/MOBA smoothing)
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
	local direction = (targetPos - myPos).Unit

	---------------------------------------------------
	-- ① 使用"迟滞区"决定是否保持当前攻击位置
	---------------------------------------------------
	local holdPosition = ShouldHoldAttackPosition(distance, dockingDistance, aiData)

	---------------------------------------------------
	-- ② 根据 holdPosition 选择移动策略
	---------------------------------------------------
	if holdPosition then
		-- ★ 在攻击区间：保持当前位置，尝试攻击
		humanoid:Move(Vector3.zero)
		AnimationController.SwitchToAttack(model, aiData, target)
		return
	end

	---------------------------------------------------
	-- ③ 若不在攻击区间 → 需要追击
	---------------------------------------------------
	AnimationController.SwitchToMove(model, aiData)

	-- 追击目标位置：射程边缘
	local desiredPos = targetPos - direction * dockingDistance

	-- MoveTo 节流（防抖）
	aiData.LastMoveTo = aiData.LastMoveTo or 0
	aiData.LastMoveTo -= deltaTime

	if aiData.LastMoveTo <= 0 then
		-- MoveTo（或 MoveToPosition）
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
			-- ★ 避免重寻路引起回头，仅做 MoveTo 重置
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
