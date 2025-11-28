--[[
CameraController (LocalScript, client)
Location: StarterPlayer/StarterPlayerScripts/Controllers/CameraController.lua

Purpose (V2.7):
- Lock camera during battle, aim at friendly formation center, smooth follow
- Auto-follow player behind formation; disable manual move/jump input
- Unlock and restore controls after battle/settlement
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local CAMERA_OFFSET = Vector3.new(0, 20, 35)
local SMOOTHNESS = 0.12
local DYNAMIC_ZOOM_PER_UNIT = 0.4
local DYNAMIC_ZOOM_MAX = 35
-- V2.8调整：跟随距离设为24（备用）
local FOLLOW_DISTANCE = 24
local FOLLOW_HEIGHT = 2
-- V2.9新增：主角到达WatchPart后的停止距离阈值
local WATCHPART_STOP_THRESHOLD = 2

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
	if watchPartPos then
		-- 使用WatchPart位置作为目标
		local targetY = math.max(hrp.Position.Y, watchPartPos.Y + FOLLOW_HEIGHT)
		local followTarget = Vector3.new(watchPartPos.X, targetY, watchPartPos.Z)

		local distanceToTarget = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(followTarget.X, 0, followTarget.Z)).Magnitude

		-- 到达WatchPart附近后停止移动
		if distanceToTarget > WATCHPART_STOP_THRESHOLD then
			humanoid:MoveTo(followTarget)
		else
			humanoid:Move(Vector3.zero, false)
		end
	else
		-- 回退方案：如果找不到WatchPart，使用原来的质心跟随逻辑
		local followTarget = center - targetCFrame.LookVector * FOLLOW_DISTANCE
		local targetY = math.max(hrp.Position.Y, center.Y + FOLLOW_HEIGHT)
		followTarget = Vector3.new(followTarget.X, targetY, followTarget.Z)

		if (hrp.Position - followTarget).Magnitude > 1 then
			humanoid:MoveTo(followTarget)
		else
			humanoid:Move(Vector3.zero, false)
		end
	end
end

local function stopCharacterFollow()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	humanoid:Move(Vector3.zero, false)
end

local function updateCamera()
	if not isActive or not camera then
		return
	end

	local center, count = computeCenter()
	if not center then
		return
	end

	local dynamicZoom = math.min(count * DYNAMIC_ZOOM_PER_UNIT, DYNAMIC_ZOOM_MAX)
	local offset = CAMERA_OFFSET + Vector3.new(0, dynamicZoom, dynamicZoom)
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
				elseif state == "PrepareBattle" or state == "Fighting" then
					-- V2.8.1修复：战斗准备和战斗阶段保持跟随
					-- 不重置质心检测，让主角继续跟随到设定距离
					if not allowCharacterFollow then
						-- 如果之前没有开启跟随，现在开启
						allowCharacterFollow = true
					end
					-- 保持centerIsMoving状态，让主角继续移动
				elseif state == "StageClear" then
					-- V2.8.1修复：过关后保持跟随状态
					-- 重置质心检测为下一关做准备，但保持allowCharacterFollow
					initialCenterPosition = nil
					-- centerIsMoving保持true，避免下一关开始时延迟
					if not allowCharacterFollow then
						allowCharacterFollow = true
					end
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
}

return _G.BattleCameraController
