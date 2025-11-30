--[[
CameraController (LocalScript, client)
Location: StarterPlayer/StarterPlayerScripts/Controllers/CameraController.lua

Purpose (V2.7):
- Lock camera during battle, aim at friendly formation center, smooth follow
- Auto-follow player behind formation; disable manual move/jump input
- Unlock and restore controls after battle/settlement

V2.10新增：战斗特写镜头
- 行军时使用跟随模式（较高、较远）
- 接战后切换到战斗模式（较低、较近，给特写效果）
- 关卡结束后恢复跟随模式
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")  -- V2.10新增：寻路服务

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ============================================
-- V2.10新增：镜头模式配置
-- ============================================
-- 跟随模式（行军时）：高俯视角度，看整体阵型
local FOLLOW_MODE_OFFSET = Vector3.new(0, 28, 18)  -- Y大Z小 = 俯视
-- 战斗模式（接战时）：低平视角度，特写效果
local COMBAT_MODE_OFFSET = Vector3.new(0, 12, 25)  -- Y小Z大 = 平视特写
-- 镜头切换过渡速度（0-1，越大越快）
local MODE_TRANSITION_SPEED = 0.08

-- 当前使用的偏移量（会在两个模式之间平滑过渡）
local currentOffset = FOLLOW_MODE_OFFSET
-- 目标偏移量
local targetOffset = FOLLOW_MODE_OFFSET
-- 当前镜头模式: "Follow" 或 "Combat"
local cameraMode = "Follow"

local CAMERA_OFFSET = Vector3.new(0, 18, 35)  -- 保留兼容（实际使用currentOffset）
local SMOOTHNESS = 0.12
local DYNAMIC_ZOOM_PER_UNIT = 0.4
local DYNAMIC_ZOOM_MAX = 35
-- V2.8调整：跟随距离设为24（备用）
local FOLLOW_DISTANCE = 24
local FOLLOW_HEIGHT = 2
-- V2.9新增：主角到达WatchPart后的停止距离阈值
local WATCHPART_STOP_THRESHOLD = 2

-- V2.10新增：寻路相关变量
local currentPath = nil
local currentWaypoints = nil
local currentWaypointIndex = 1
local lastPathTarget = nil
local PATH_RECOMPUTE_DISTANCE = 5  -- 目标移动超过此距离时重新计算路径
-- V2.10新增：卡住检测
local lastCharacterPosition = nil
local stuckCheckTime = 0
local STUCK_TIME_THRESHOLD = 0.5  -- 卡住超过0.5秒就重新规划
local STUCK_DISTANCE_THRESHOLD = 0.5  -- 移动距离小于0.5视为卡住

local isActive = false
local renderConnection = nil
local characterAddedConnection = nil
-- V2.8新增：延迟跟随标记
local allowCharacterFollow = false
local characterFollowDelayTimer = nil
-- V2.8新增：质心移动检测（检测累计移动距离）
local initialCenterPosition = nil  -- 进入Marching时的初始质心位置
local centerIsMoving = false
local CENTER_MOVE_THRESHOLD = 3  -- 质心累计移动超过3 studs才认为兵种开始移动
-- V2.9新增：当前关卡编号
local currentStageNum = 0

local cachedCameraType = nil
local cachedCameraSubject = nil
local cachedHumanoidSettings = nil

local BlockActionName = "BattleCamera_BlockMove"
local currentState = "Idle"

local function getHumanoid()
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getIdleFloor()
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. tostring(homeSlot))
	if not playerHome then
		return nil
	end

	return playerHome:FindFirstChild("IdleFloor")
end

--[[
V2.9新增：获取当前关卡的WatchPart位置
@param stageNum number - 关卡编号
@return Vector3|nil - WatchPart的位置，未找到返回nil
]]
local function getWatchPartPosition(stageNum)
	if stageNum <= 0 then
		return nil
	end

	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. tostring(homeSlot))
	if not playerHome then
		return nil
	end

	-- 关卡文件夹在PlayerHome下的Stage文件夹中
	local stageContainer = playerHome:FindFirstChild("Stage")
	if not stageContainer then
		return nil
	end

	-- 获取对应关卡文件夹 (Stage001, Stage002, ...)
	local stageName = string.format("Stage%03d", stageNum)
	local stageFolder = stageContainer:FindFirstChild(stageName)
	if not stageFolder then
		return nil
	end

	-- 递归查找WatchPart
	local watchPart = stageFolder:FindFirstChild("WatchPart", true)
	if watchPart and watchPart:IsA("BasePart") then
		return watchPart.Position
	end

	return nil
end

local function collectAllyPositions()
	local positions = {}

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and inst:GetAttribute("CampaignKeepInstance") then
			local rootPart = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
			if rootPart then
				table.insert(positions, rootPart.Position)
			end
		end
	end

	if #positions == 0 then
		local idleFloor = getIdleFloor()
		if idleFloor then
			table.insert(positions, idleFloor.Position)
		end
	end

	return positions
end

local function computeCenter()
	local positions = collectAllyPositions()
	if #positions == 0 then
		return nil, 0
	end

	local sum = Vector3.zero
	for _, pos in ipairs(positions) do
		sum += pos
	end

	return sum / #positions, #positions
end

-- ============================================
-- V2.10新增：镜头模式切换函数
-- ============================================
--[[
切换到战斗模式（特写）
- 镜头往前推进、往低推进
- 给战斗一个特写效果
]]
local function setCombatMode()
	if cameraMode == "Combat" then
		return
	end
	cameraMode = "Combat"
	targetOffset = COMBAT_MODE_OFFSET
	print("[CameraController] 切换到战斗特写模式")
end

--[[
切换到跟随模式
- 镜头抬高、拉远
- 用于行军跟随
]]
local function setFollowMode()
	if cameraMode == "Follow" then
		return
	end
	cameraMode = "Follow"
	targetOffset = FOLLOW_MODE_OFFSET
	print("[CameraController] 切换到跟随模式")
end

--[[
重置镜头模式（立即重置，无过渡）
]]
local function resetCameraMode()
	cameraMode = "Follow"
	targetOffset = FOLLOW_MODE_OFFSET
	currentOffset = FOLLOW_MODE_OFFSET
end

local function unbindInputBlock()
	ContextActionService:UnbindAction(BlockActionName)
end

local function bindInputBlock()
	ContextActionService:BindActionAtPriority(
		BlockActionName,
		function()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Space,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
end

local function restoreHumanoidSettings()
	if not cachedHumanoidSettings then
		return
	end

	local humanoid = getHumanoid()
	if humanoid then
		if cachedHumanoidSettings.JumpPower then
			humanoid.JumpPower = cachedHumanoidSettings.JumpPower
		end
		if cachedHumanoidSettings.JumpHeight then
			humanoid.JumpHeight = cachedHumanoidSettings.JumpHeight
		end
		if cachedHumanoidSettings.AutoRotate ~= nil then
			humanoid.AutoRotate = cachedHumanoidSettings.AutoRotate
		end
	end

	cachedHumanoidSettings = nil
end

local function applyHumanoidLock()
	local humanoid = getHumanoid()
	if not humanoid or cachedHumanoidSettings then
		return
	end

	cachedHumanoidSettings = {
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
	}

	-- disable manual jump/rotation
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = true
end

local function updateCharacterFollow(center, targetCFrame)
	local humanoid = getHumanoid()
	local character = player.Character
	if not humanoid or not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- V2.9修改：目标位置改为当前关卡的WatchPart
	local watchPartPos = getWatchPartPosition(currentStageNum)
	local followTarget

	if watchPartPos then
		-- 使用WatchPart位置作为目标
		local targetY = math.max(hrp.Position.Y, watchPartPos.Y + FOLLOW_HEIGHT)
		followTarget = Vector3.new(watchPartPos.X, targetY, watchPartPos.Z)
	else
		-- 回退方案：如果找不到WatchPart，使用原来的质心跟随逻辑
		followTarget = center - targetCFrame.LookVector * FOLLOW_DISTANCE
		local targetY = math.max(hrp.Position.Y, center.Y + FOLLOW_HEIGHT)
		followTarget = Vector3.new(followTarget.X, targetY, followTarget.Z)
	end

	local distanceToTarget = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(followTarget.X, 0, followTarget.Z)).Magnitude

	-- 到达目标附近后停止移动并面朝战场
	if distanceToTarget <= WATCHPART_STOP_THRESHOLD then
		humanoid:Move(Vector3.zero, false)
		-- 清理寻路状态
		currentPath = nil
		currentWaypoints = nil
		currentWaypointIndex = 1
		lastPathTarget = nil
		lastCharacterPosition = nil
		stuckCheckTime = 0

		-- V2.10新增：到达后面朝战场中心（观察战斗）
		local lookAtPos = Vector3.new(center.X, hrp.Position.Y, center.Z)
		local lookDir = (lookAtPos - hrp.Position)
		if lookDir.Magnitude > 0.1 then
			local targetCF = CFrame.new(hrp.Position, lookAtPos)
			hrp.CFrame = hrp.CFrame:Lerp(targetCF, 0.1)  -- 平滑转向
		end
		return
	end

	-- V2.10新增：卡住检测
	local currentPos = hrp.Position
	local isStuck = false

	if lastCharacterPosition then
		local movedDistance = (currentPos - lastCharacterPosition).Magnitude
		if movedDistance < STUCK_DISTANCE_THRESHOLD then
			stuckCheckTime = stuckCheckTime + RunService.RenderStepped:Wait()
			if stuckCheckTime >= STUCK_TIME_THRESHOLD then
				isStuck = true
				stuckCheckTime = 0
			end
		else
			stuckCheckTime = 0
		end
	end
	lastCharacterPosition = currentPos

	-- V2.10新增：使用PathfindingService进行智能寻路
	-- 检查是否需要重新计算路径
	local needNewPath = false
	if not currentPath or not currentWaypoints then
		needNewPath = true
	elseif lastPathTarget and (lastPathTarget - followTarget).Magnitude > PATH_RECOMPUTE_DISTANCE then
		needNewPath = true
	elseif currentWaypointIndex > #currentWaypoints then
		needNewPath = true
	elseif isStuck then
		-- 卡住了，强制重新计算路径
		needNewPath = true
		print("[CameraController] 检测到角色卡住，重新规划路径")
	end

	if needNewPath then
		-- 创建新路径
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,  -- 允许跳跃绕过障碍
			AgentCanClimb = false,
			WaypointSpacing = 4,  -- 路径点间距
		})

		local success, errorMessage = pcall(function()
			path:ComputeAsync(hrp.Position, followTarget)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			currentPath = path
			currentWaypoints = path:GetWaypoints()
			currentWaypointIndex = 2  -- 跳过起点
			lastPathTarget = followTarget

			-- 监听路径被阻塞事件
			path.Blocked:Connect(function(blockedWaypointIndex)
				if blockedWaypointIndex >= currentWaypointIndex then
					-- 路径被阻塞，强制重新计算
					currentPath = nil
				end
			end)
		else
			-- 寻路失败，直接朝目标移动
			humanoid:MoveTo(followTarget)
			return
		end
	end

	-- 沿路径点移动
	if currentWaypoints and currentWaypointIndex <= #currentWaypoints then
		local waypoint = currentWaypoints[currentWaypointIndex]
		local waypointPos = waypoint.Position
		local distToWaypoint = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(waypointPos.X, 0, waypointPos.Z)).Magnitude

		if distToWaypoint < 2 then
			-- 到达当前路径点，移动到下一个
			currentWaypointIndex = currentWaypointIndex + 1
		end

		if currentWaypointIndex <= #currentWaypoints then
			local nextWaypoint = currentWaypoints[currentWaypointIndex]
			humanoid:MoveTo(nextWaypoint.Position)

			-- 如果是跳跃点，执行跳跃
			if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
		end
	else
		-- 没有有效路径点，直接MoveTo
		humanoid:MoveTo(followTarget)
	end
end

local function stopCharacterFollow()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	humanoid:Move(Vector3.zero, false)
	-- V2.10新增：清理寻路状态
	currentPath = nil
	currentWaypoints = nil
	currentWaypointIndex = 1
	lastPathTarget = nil
	lastCharacterPosition = nil
	stuckCheckTime = 0
end

local function updateCamera()
	if not isActive or not camera then
		return
	end

	local center, count = computeCenter()
	if not center then
		return
	end

	-- V2.10新增：平滑过渡镜头偏移量
	-- 使用Lerp让currentOffset平滑趋近targetOffset
	currentOffset = currentOffset:Lerp(targetOffset, MODE_TRANSITION_SPEED)

	-- V2.10修改：使用currentOffset代替固定的CAMERA_OFFSET
	local dynamicZoom = math.min(count * DYNAMIC_ZOOM_PER_UNIT, DYNAMIC_ZOOM_MAX)
	local offset = currentOffset + Vector3.new(0, dynamicZoom, dynamicZoom)
	local targetPosition = center + offset
	local targetCFrame = CFrame.new(targetPosition, center)

	camera.CFrame = camera.CFrame:Lerp(targetCFrame, SMOOTHNESS)

	-- V2.8修复：检测质心累计移动距离
	-- 只有当质心从初始位置移动超过阈值后才允许主角跟随
	-- V2.8.1修复：在Marching和Fighting状态下都需要检测质心移动
	local shouldTrackCenter = (currentState == "Marching" or currentState == "PrepareBattle" or currentState == "Fighting")

	if shouldTrackCenter then
		if not initialCenterPosition then
			-- 记录初始质心位置
			initialCenterPosition = center
		elseif not centerIsMoving then
			-- 检测累计移动距离
			local totalDelta = (center - initialCenterPosition).Magnitude
			if totalDelta > CENTER_MOVE_THRESHOLD then
				centerIsMoving = true
			end
		end
	elseif currentState == "StageClear" then
		-- StageClear状态：保持跟随状态但重置质心检测（准备进入下一关的行军）
		initialCenterPosition = nil
		-- 保持centerIsMoving为true，避免下一关开始时的延迟
	else
		-- 其他状态重置检测
		initialCenterPosition = nil
		centerIsMoving = false
	end

	-- V2.8.1修复：在战斗相关状态下都应该继续跟随
	-- Marching: 兵种行军到关卡
	-- PrepareBattle: 准备战斗阶段
	-- Fighting: 战斗中（兵种会追击敌人）
	-- StageClear: 过关后准备行军到下一关
	local shouldCharacterFollow = allowCharacterFollow and (
		currentState == "Marching" or
		currentState == "PrepareBattle" or
		currentState == "Fighting" or
		currentState == "StageClear"
	)

	if shouldCharacterFollow and centerIsMoving then
		updateCharacterFollow(center, targetCFrame)
	else
		stopCharacterFollow()
	end
end

local function stopCameraLock()
	if not isActive then
		return
	end

	isActive = false
	-- V2.8：清理所有跟随相关状态
	allowCharacterFollow = false
	centerIsMoving = false
	initialCenterPosition = nil
	if characterFollowDelayTimer then
		task.cancel(characterFollowDelayTimer)
		characterFollowDelayTimer = nil
	end

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	unbindInputBlock()
	restoreHumanoidSettings()

	if camera then
		camera.CameraType = cachedCameraType or Enum.CameraType.Custom
		if cachedCameraSubject then
			camera.CameraSubject = cachedCameraSubject
		end
	end

	cachedCameraType = nil
	cachedCameraSubject = nil
end

local function startCameraLock()
	if isActive then
		return
	end

	if not camera then
		return
	end

	isActive = true
	-- V2.8修复：跟随由状态事件控制，启动时默认关闭
	allowCharacterFollow = false

	cachedCameraType = camera.CameraType
	cachedCameraSubject = camera.CameraSubject
	camera.CameraType = Enum.CameraType.Scriptable

	bindInputBlock()
	applyHumanoidLock()

	if not characterAddedConnection then
		characterAddedConnection = player.CharacterAdded:Connect(function()
			if isActive then
				task.defer(applyHumanoidLock)
			end
		end)
	end

	renderConnection = RunService.RenderStepped:Connect(updateCamera)
end

-- Event-driven: battle states
task.spawn(function()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		return
	end

	local campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
	if campaignEvents then
		local stateUpdate = campaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate.OnClientEvent:Connect(function(state, stageNum)
				currentState = state or "Idle"
				-- V2.9新增：更新当前关卡编号
				if stageNum and type(stageNum) == "number" then
					currentStageNum = stageNum
				end

				-- V2.8.1修复：跟随时机绑定到状态
				-- 在行军、准备战斗、战斗、过关状态时都允许主角跟随
				if state == "Marching" then
					-- 进入行军状态，重置质心检测，延迟后开启跟随
					centerIsMoving = false
					initialCenterPosition = nil
					if characterFollowDelayTimer then
						task.cancel(characterFollowDelayTimer)
					end
					characterFollowDelayTimer = task.delay(0.1, function()
						allowCharacterFollow = true
						characterFollowDelayTimer = nil
					end)
					-- V2.10新增：行军时使用跟随模式（镜头抬高）
					setFollowMode()
				elseif state == "PrepareBattle" then
					-- V2.8.1修复：战斗准备阶段保持跟随
					if not allowCharacterFollow then
						allowCharacterFollow = true
					end
					-- V2.10新增：准备战斗时切换到战斗特写模式（镜头推近）
					setCombatMode()
				elseif state == "Fighting" then
					-- V2.8.1修复：战斗阶段保持跟随
					if not allowCharacterFollow then
						allowCharacterFollow = true
					end
					-- V2.10新增：战斗时保持战斗特写模式
					setCombatMode()
				elseif state == "StageClear" then
					-- V2.8.1修复：过关后保持跟随状态
					-- 重置质心检测为下一关做准备，但保持allowCharacterFollow
					initialCenterPosition = nil
					-- centerIsMoving保持true，避免下一关开始时延迟
					if not allowCharacterFollow then
						allowCharacterFollow = true
					end
					-- V2.10新增：关卡结束后立即切换到跟随模式（镜头抬高）
					setFollowMode()
				else
					-- 其他状态，关闭跟随并停止移动
					allowCharacterFollow = false
					centerIsMoving = false
					initialCenterPosition = nil
					if characterFollowDelayTimer then
						task.cancel(characterFollowDelayTimer)
						characterFollowDelayTimer = nil
					end
					stopCharacterFollow()
					-- V2.10新增：非战斗状态重置镜头模式
					if state == "Idle" then
						resetCameraMode()
					end
				end

				-- 战役流程中都保持镜头锁定；Idle 时解除
				if state == "Preparing"
					or state == "PrepareBattle"
					or state == "Marching"
					or state == "Fighting"
					or state == "StageClear"
					or state == "Victory"
					or state == "Defeat"
					or state == "Cleanup"
				then
					startCameraLock()
				elseif state == "Idle" then
					-- V2.9：重置关卡编号
					currentStageNum = 0
					stopCameraLock()
				end
			end)
		end
	end
end)

-- Expose to other client scripts
_G.BattleCameraController = {
	Start = startCameraLock,
	Stop = stopCameraLock,
	-- V2.10新增：镜头模式控制
	SetCombatMode = setCombatMode,      -- 切换到战斗特写模式
	SetFollowMode = setFollowMode,      -- 切换到跟随模式
	ResetCameraMode = resetCameraMode,  -- 重置镜头模式
}

return _G.BattleCameraController
