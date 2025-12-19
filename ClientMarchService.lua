--[[
脚本名称: ClientMarchService
脚本类型: ModuleScript (客户端系统)
脚本位置: StarterPlayer/StarterPlayerScripts/ClientAI/ClientMarchService
版本: V1.0 - 客户端行军系统

功能描述:
- 负责客户端的单位行军控制
- 接收服务端的行军指令，在客户端执行寻路和移动
- 支持分批寻路、Heartbeat驱动、切角机制、卡住检测
- 到达后向服务端报告完成状态

核心职责:
1. 批量行军管理（MoveUnitsToPositions）
2. 寻路请求和路径跟随
3. 卡住检测和走错路检测
4. 超时处理和失败报告
5. 行军动画播放

关键差异（vs 服务端 PathService）:
- 瞬移兜底：卡住/走错路/超时会瞬移到目标点（必要时），避免“少兵进战斗”
- 轻量化：只处理本地玩家的单位
- 状态同步：完成后通过 RemoteEvent 向服务端报告
]]

local ClientMarchService = {}

-- ==================== 依赖服务 ====================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- ==================== 引用配置 ====================

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 私有变量 ====================

local ClientUnitManager = nil
local ClientPathService = nil
local activeMoves = {}
local nextMoveId = 1
local LocalPlayer = Players.LocalPlayer

-- ==================== 配置常量 ====================

local CONFIG = {
	-- 到达阈值（studs）
	ARRIVAL_THRESHOLD = 8,

	-- 队形分散（解决行军单列排队）
	LANE_SPACING = 6,
	MAX_LANE_OFFSET = 12,
	-- V5.1修复：将FADE范围改为全程保持偏移，避免"先散开再聚拢"的V字形行军
	LANE_FADE_START_DISTANCE = 999,  -- 始终应用偏移（原值80）
	LANE_FADE_END_DISTANCE = 0,      -- 直到到达目标（原值25）

	-- 卡住检测配置
	STUCK_CHECK_INTERVAL = 1.0,
	STUCK_MIN_VELOCITY = 0.1,
	STUCK_COUNT_THRESHOLD = 5,

	-- 走错路检测配置
	WRONG_WAY_THRESHOLD = 5,
	WRONG_WAY_DISTANCE = 5,

	-- 超时配置
	MOVE_TIMEOUT = 30,

	-- 寻路重试配置
	REPATH_COOLDOWN = 1.5,

	-- 分批寻路配置
	BATCH_SIZE = 4,

	-- 调试选项
	DEBUG_LOGS = false,
}

-- 从BattleConfig读取配置
if BattleConfig then
	CONFIG.DEBUG_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_LOGS
end

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_LOGS then
		print(GameConfig.LOG_PREFIX, "[ClientMarchService]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[ClientMarchService]", ...)
end

-- ==================== 工具函数 ====================

local function GetModelPosition(model)
	if not model then return nil end
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not rootPart then return nil end
	return rootPart.Position
end

local function GetHorizontalDistance(pos1, pos2)
	if not pos1 or not pos2 then return math.huge end
	return math.sqrt((pos1.X - pos2.X)^2 + (pos1.Z - pos2.Z)^2)
end

local function RoundToNearestInt(value)
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

local function RoundToStep(value, step)
	if not step or step <= 0 then
		return value
	end
	return RoundToNearestInt(value / step) * step
end

local function GetLaneWeight(distanceToTarget)
	local fadeStart = CONFIG.LANE_FADE_START_DISTANCE
	local fadeEnd = CONFIG.LANE_FADE_END_DISTANCE

	if fadeStart <= fadeEnd then
		return 0
	end
	if distanceToTarget <= fadeEnd then
		return 0
	end
	if distanceToTarget >= fadeStart then
		return 1
	end

	return (distanceToTarget - fadeEnd) / (fadeStart - fadeEnd)
end

--[[
播放行军动画
@param unitModel Model - 单位模型
@param unitId string - 单位ID
]]
local function PlayMarchAnimation(unitModel, unitId)
	if not unitModel or not unitId then return end

	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- 获取行军动画ID（优先使用 MoveAnimation，其次使用 RunAnimation）
	local animId = UnitConfig.GetMoveAnimationId and UnitConfig.GetMoveAnimationId(unitId)
	if not animId or animId == "" or animId == "0" then
		animId = UnitConfig.GetRunAnimationId and UnitConfig.GetRunAnimationId(unitId)
	end

	if not animId or animId == "" or animId == "0" then
		return
	end

	-- 停止所有正在播放的动画
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			track:Stop(0.1)
		end)
	end

	-- 加载并播放行军动画
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animId

	local success, animTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and animTrack then
		animTrack.Priority = Enum.AnimationPriority.Movement
		animTrack.Looped = true
		animTrack:Play(0.1)
		DebugLog(string.format("播放行军动画: %s (UnitId=%s)", unitModel.Name, unitId))
	end

	animation:Destroy()
end

--[[
停止行军动画
@param unitModel Model - 单位模型
]]
local function StopMarchAnimation(unitModel)
	if not unitModel then return end

	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then return end

	-- 停止所有正在播放的动画
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			track:Stop(0.1)
		end)
	end
end

-- ==================== 公共接口 ====================

--[[
初始化（依赖注入）
@param clientUnitManager table - ClientUnitManager模块
@param clientPathService table - ClientPathService模块
]]
function ClientMarchService.Initialize(clientUnitManager, clientPathService)
	ClientUnitManager = clientUnitManager
	ClientPathService = clientPathService
	DebugLog("ClientMarchService已初始化")
end

--[[
批量行军到指定位置
@param moveTargets table - {[unitModel] = CFrame}
@param callbacks table - {onUnitArrived, onAllSettled}
@return string|nil - moveId
]]
function ClientMarchService.MoveUnitsToPositions(moveTargets, callbacks)
	if not moveTargets or type(moveTargets) ~= "table" then
		WarnLog("MoveUnitsToPositions: moveTargets无效")
		return nil
	end

	if not ClientPathService then
		WarnLog("MoveUnitsToPositions: ClientPathService未初始化")
		return nil
	end

	local onUnitArrived = callbacks and callbacks.onUnitArrived
	local onAllSettled = callbacks and callbacks.onAllSettled

	local moveId = "ClientMove_" .. tostring(nextMoveId)
	nextMoveId = nextMoveId + 1

	local moveData = {}
	local unitsList = {}
	local arrivedList = {}
	local failedList = {}
	local totalCount = 0

	-- 准备单位数据
	for unitInstance, targetCFrame in pairs(moveTargets) do
		local humanoid = unitInstance and unitInstance:FindFirstChild("Humanoid")
		local rootPart = unitInstance and (unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart)

		if humanoid and rootPart then
			moveData[unitInstance] = {
				TargetCFrame = targetCFrame,
				TargetPos = targetCFrame.Position,
				Arrived = false,
				StartTime = tick(),
				PathRequested = false,
				-- 卡住检测数据
				LastStuckCheckTime = tick(),
				LastStuckCheckPos = rootPart.Position,
				StuckCount = 0,
				LastRepathTime = 0,
				-- 距离追踪
				PrevDistanceToTarget = nil,
				WrongWayCount = 0,
				-- V5.0新增：持续MoveTo刷新
				LastMoveToUpdateTime = 0,
			}

			table.insert(unitsList, unitInstance)
			totalCount = totalCount + 1
		end
	end

	if totalCount == 0 then
		WarnLog("MoveUnitsToPositions: 没有有效单位")
		if onAllSettled then
			onAllSettled({}, {})
		end
		return nil
	end

	DebugLog(string.format("[MoveUnitsToPositions] 开始移动 %d 个单位", totalCount))

	-- 队形分散：基于队伍行军方向分配“车道偏移”，避免所有单位挤到同一路点导致单列排队
	local startSum = Vector3.zero
	local targetSum = Vector3.zero
	local centerCount = 0

	for unitInstance, data in pairs(moveData) do
		local rootPart = unitInstance and (unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart)
		if rootPart and data and data.TargetPos then
			startSum += Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
			targetSum += Vector3.new(data.TargetPos.X, 0, data.TargetPos.Z)
			centerCount += 1
		end
	end

	local startCenter = Vector3.zero
	local targetCenter = Vector3.zero
	if centerCount > 0 then
		startCenter = startSum / centerCount
		targetCenter = targetSum / centerCount
	end

	local marchDir = Vector3.new(targetCenter.X - startCenter.X, 0, targetCenter.Z - startCenter.Z)
	if marchDir.Magnitude < 0.05 then
		marchDir = Vector3.new(0, 0, -1)
	else
		marchDir = marchDir.Unit
	end

	local marchRight = Vector3.new(-marchDir.Z, 0, marchDir.X)
	if marchRight.Magnitude < 0.05 then
		marchRight = Vector3.new(1, 0, 0)
	else
		marchRight = marchRight.Unit
	end

	for unitInstance, data in pairs(moveData) do
		local startPos = data and data.LastStuckCheckPos
		if startPos then
			local offset = Vector3.new(startPos.X - startCenter.X, 0, startPos.Z - startCenter.Z)
			local lateral = offset:Dot(marchRight)
			local lane = RoundToStep(lateral, CONFIG.LANE_SPACING)
			data.LaneOffset = math.clamp(lane, -CONFIG.MAX_LANE_OFFSET, CONFIG.MAX_LANE_OFFSET)
		else
			data.LaneOffset = 0
		end
	end

	local function ApplyLaneOffset(data, basePos, distanceToFinal)
		if not basePos or not data then
			return basePos
		end

		local laneOffset = data.LaneOffset or 0
		if laneOffset == 0 then
			return basePos
		end

		local weight = GetLaneWeight(distanceToFinal)
		if weight <= 0 then
			return basePos
		end

		return basePos + marchRight * (laneOffset * weight)
	end

	-- 兜底：卡住/走错路/超时后，直接瞬移到目标点，避免“少兵进战斗”
	local function TeleportToTarget(unitInstance, data, reason)
		if not unitInstance or not data or not data.TargetPos then
			return false
		end

		-- 如果已切换为战斗模式，禁止行军阶段瞬移（避免竞态）
		local aiMode = unitInstance:GetAttribute("UnitAIMode")
		if aiMode == "CombatMode" or aiMode == "Combat" then
			return false
		end

		local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
		if not rootPart then
			return false
		end

		local humanoid = unitInstance:FindFirstChild("Humanoid")

		StopMarchAnimation(unitInstance)
		ClientPathService.ClearPath(unitInstance)
		if humanoid then
			humanoid:Move(Vector3.zero)
		end

		local targetPos = data.TargetPos
		local targetY = targetPos.Y

		-- 射线检测确保落在地面上（避免落点悬空/穿地）
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { unitInstance }
		rayParams.IgnoreWater = true

		local rayResult = workspace:Raycast(
			Vector3.new(targetPos.X, targetPos.Y + 10, targetPos.Z),
			Vector3.new(0, -80, 0),
			rayParams
		)
		if rayResult then
			targetY = rayResult.Position.Y + 3
		end

		local ok = pcall(function()
			rootPart.CFrame = CFrame.new(targetPos.X, targetY, targetPos.Z)
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end)
		if not ok then
			return false
		end

		data.Arrived = true
		table.insert(arrivedList, unitInstance)

		if onUnitArrived then
			pcall(function() onUnitArrived(unitInstance, reason or "Teleported") end)
		end

		DebugLog(string.format("%s 瞬移到目标点: %s", unitInstance.Name, tostring(reason or "Teleported")))
		return true
	end

	-- 分批发起寻路请求
	local batchIndex = 0

	for _, unitInstance in ipairs(unitsList) do
		local data = moveData[unitInstance]
		local unitId = unitInstance:GetAttribute("UnitId") or unitInstance.Name

		-- 确保解锚
		local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
		if rootPart and rootPart.Anchored then
			rootPart.Anchored = false
		end

		-- 分批处理
		batchIndex = batchIndex + 1
		if batchIndex > CONFIG.BATCH_SIZE then
			batchIndex = 1
			task.wait()
		end

		-- 播放行军动画
		task.delay(0.1, function()
			if not data.Arrived then
				PlayMarchAnimation(unitInstance, unitId)
			end
		end)

		-- 请求路径
		-- 行军开始前先清理任何残留的战斗MoveTo/路点状态，避免MoveToFinished竞态
		if ClientPathService and ClientPathService.StopMovement then
			ClientPathService.StopMovement(unitInstance)
		end

		data.PathRequested = true
		ClientPathService.RequestPath(unitInstance, data.TargetPos)
		data.PathRequested = false

		-- 开始移动
		local humanoid = unitInstance:FindFirstChild("Humanoid")
		if humanoid then
			-- 尝试跟随路径（ClientPathService为异步队列，初始大概率是Queued/Computing，这里不要直线MoveTo怼墙）
			if ClientPathService.ClearMoveConnection then
				ClientPathService.ClearMoveConnection(unitInstance)
			end

			local pathStatus = ClientPathService.GetPathStatus(unitInstance)
			if (pathStatus == "Success" or pathStatus == "Partial") and ClientPathService.StepPath then
				local targetDistance = rootPart and GetHorizontalDistance(rootPart.Position, data.TargetPos) or math.huge
				local stepResult = ClientPathService.StepPath(unitInstance, {
					humanoid = humanoid,
					currentPos = rootPart and rootPart.Position or nil,
					now = tick(),
					lastMoveToUpdateTime = 0,
					mapWaypoint = function(rawWaypoint)
						return ApplyLaneOffset(data, rawWaypoint, targetDistance)
					end,
				})
				if stepResult and stepResult.lastMoveToUpdateTime then
					data.LastMoveToUpdateTime = stepResult.lastMoveToUpdateTime
				end
			end
		end
	end

	-- Heartbeat循环检查
	local checkConnection
	local lastCheckTime = tick()

	checkConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastCheckTime < 0.05 then return end
		lastCheckTime = now

		local allDone = true

		for unitInstance, data in pairs(moveData) do
			if not data.Arrived then
				allDone = false

				-- 检查实例有效性
				if not unitInstance or not unitInstance.Parent then
					data.Arrived = true
					table.insert(failedList, unitInstance)
					StopMarchAnimation(unitInstance)
					continue
				end

				local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
				if not rootPart or not rootPart.Parent then continue end

				local humanoid = unitInstance:FindFirstChild("Humanoid")
				if not humanoid then continue end

				local currentPos = rootPart.Position
				local distanceXZ = GetHorizontalDistance(currentPos, data.TargetPos)

				-- 到达检测
				if distanceXZ < CONFIG.ARRIVAL_THRESHOLD then
					data.Arrived = true
					StopMarchAnimation(unitInstance)
					ClientPathService.ClearPath(unitInstance)

					table.insert(arrivedList, unitInstance)

					if onUnitArrived then
						pcall(function() onUnitArrived(unitInstance, "Arrived") end)
					end

					DebugLog(string.format("%s 到达目的地", unitInstance.Name))
					continue
				end

				-- 更新路径跟随（如果有路径的话）
				local pathStatus = ClientPathService.GetPathStatus(unitInstance)
				if pathStatus == "Success" or pathStatus == "Partial" then
					if ClientPathService.StepPath then
						local stepResult = ClientPathService.StepPath(unitInstance, {
							humanoid = humanoid,
							currentPos = currentPos,
							now = now,
							lastMoveToUpdateTime = data.LastMoveToUpdateTime,
							mapWaypoint = function(rawWaypoint)
								return ApplyLaneOffset(data, rawWaypoint, distanceXZ)
							end,
						})
						if stepResult and stepResult.lastMoveToUpdateTime then
							data.LastMoveToUpdateTime = stepResult.lastMoveToUpdateTime
						end
					else
					-- ==================== V5.0核心优化：丝滑切角寻路 ====================
					-- 参考服务端PathService的实现
					local pathState = ClientPathService.GetPathState and ClientPathService.GetPathState(unitInstance)
					if pathState and pathState.Waypoints and pathState.Index then
						-- 首次进入有路径状态：立即发出一次MoveTo，避免等0.5秒刷新窗口导致“发呆”
						if data.LastMoveToUpdateTime == 0 then
							local firstWaypoint = pathState.Waypoints[pathState.Index]
							local firstTarget = ApplyLaneOffset(data, firstWaypoint or data.TargetPos, distanceXZ)
							humanoid:MoveTo(firstTarget)
							data.LastMoveToUpdateTime = now
						end

						local currentWaypoint = pathState.Waypoints[pathState.Index]
						if currentWaypoint then
							local desiredWaypoint = ApplyLaneOffset(data, currentWaypoint, distanceXZ)
							local distToWaypoint = GetHorizontalDistance(currentPos, desiredWaypoint)

							-- 切角阈值：如果是中间点，距离 < 5 就切向下一个点
							local isFinalPoint = pathState.Index >= #pathState.Waypoints
							local reachThreshold = isFinalPoint and 1.5 or 5.0

							if distToWaypoint < reachThreshold then
								-- 到达当前路点，推进到下一个
								pathState.Index = pathState.Index + 1
								if pathState.Index <= #pathState.Waypoints then
									local newTarget = pathState.Waypoints[pathState.Index]
									if newTarget then
										humanoid:MoveTo(ApplyLaneOffset(data, newTarget, distanceXZ))
										data.LastMoveToUpdateTime = now
									end
								end
							end
						end

						-- 持续刷新 MoveTo，防止 MoveTo 超时（默认8秒）导致发呆
						if now - data.LastMoveToUpdateTime > 0.5 then
							local targetWaypoint = pathState.Waypoints[pathState.Index]
							if targetWaypoint then
								humanoid:MoveTo(ApplyLaneOffset(data, targetWaypoint, distanceXZ))
							else
								humanoid:MoveTo(ApplyLaneOffset(data, data.TargetPos, distanceXZ))
							end
							data.LastMoveToUpdateTime = now
						end
					end
					-- ==============================================================
					end
				elseif pathStatus == "NeedRepath" or pathStatus == "Blocked" then
					-- 需要重新寻路
					local canRepath = (now - data.LastRepathTime) >= CONFIG.REPATH_COOLDOWN
					if canRepath and not data.PathRequested then
						data.LastRepathTime = now
						data.PathRequested = true
						ClientPathService.RequestPath(unitInstance, data.TargetPos)
						data.PathRequested = false
						-- 异步队列：不要立即检查结果/直线MoveTo，等待下一次循环变为Success/Partial再接管MoveTo
					end
				elseif pathStatus == "Queued" or pathStatus == "Computing" then
					-- 正在排队/计算中：等待
				else
					-- 无有效路径：尝试重请求（避免直线MoveTo怼墙导致卡住/走错路误判）
					local canRepath = (now - data.LastRepathTime) >= CONFIG.REPATH_COOLDOWN
					if canRepath and not data.PathRequested then
						data.LastRepathTime = now
						data.PathRequested = true
						ClientPathService.RequestPath(unitInstance, data.TargetPos)
						data.PathRequested = false
					end
				end

				-- 卡住检测
				if (pathStatus == "Success" or pathStatus == "Partial") and now - data.LastStuckCheckTime >= CONFIG.STUCK_CHECK_INTERVAL then
					data.LastStuckCheckTime = now

					local lastPos = data.LastStuckCheckPos
					local actualDistance = GetHorizontalDistance(currentPos, lastPos)
					data.LastStuckCheckPos = currentPos

					-- 预期位移
					local walkSpeed = humanoid.WalkSpeed or 16
					local expectedDistance = walkSpeed * CONFIG.STUCK_CHECK_INTERVAL * 0.5
					local minDistThreshold = math.max(CONFIG.STUCK_MIN_VELOCITY, expectedDistance * 0.3)

					-- 距离变化追踪
					local prevDist = data.PrevDistanceToTarget or distanceXZ
					local isProgressing = distanceXZ < (prevDist - 0.1)
					data.PrevDistanceToTarget = distanceXZ

					-- 卡住判定
					local isStuck = actualDistance < minDistThreshold
						and not isProgressing
						and distanceXZ > 5

					if isStuck then
						data.StuckCount = data.StuckCount + 1

						if data.StuckCount >= CONFIG.STUCK_COUNT_THRESHOLD then
							data.StuckCount = 0
							if not TeleportToTarget(unitInstance, data, "StuckTeleported") then
								-- 兜底：无法瞬移时按失败处理（保持旧行为）
								DebugLog(string.format("⚠ %s 确认卡住但无法瞬移，标记为失败", unitInstance.Name))
								data.Arrived = true
								StopMarchAnimation(unitInstance)
								ClientPathService.ClearPath(unitInstance)

								humanoid:Move(Vector3.zero)

								table.insert(failedList, unitInstance)
							end
						end
					else
						if actualDistance > minDistThreshold then
							data.StuckCount = 0
						end
					end

					-- 走错路检测
					if distanceXZ > 15 and distanceXZ > prevDist + CONFIG.WRONG_WAY_DISTANCE then
						data.WrongWayCount = (data.WrongWayCount or 0) + 1
						if data.WrongWayCount >= CONFIG.WRONG_WAY_THRESHOLD then
							data.WrongWayCount = 0
							if not TeleportToTarget(unitInstance, data, "WrongWayTeleported") then
								DebugLog(string.format("⚠ %s 走错路但无法瞬移(%.1f→%.1f)，标记为失败", unitInstance.Name, prevDist, distanceXZ))
								data.Arrived = true
								StopMarchAnimation(unitInstance)
								ClientPathService.ClearPath(unitInstance)

								humanoid:Move(Vector3.zero)

								table.insert(failedList, unitInstance)
							end
						end
					else
						data.WrongWayCount = 0
					end
				end

				-- 超时检测
				if now - data.StartTime > CONFIG.MOVE_TIMEOUT then
					if not TeleportToTarget(unitInstance, data, "TimedOutTeleported") then
						data.Arrived = true
						StopMarchAnimation(unitInstance)
						ClientPathService.ClearPath(unitInstance)

						humanoid:Move(Vector3.zero)

						table.insert(failedList, unitInstance)

						DebugLog(string.format("⚠ %s 移动超时", unitInstance.Name))
					end
				end
			end
		end

		-- 所有单位完成
		if allDone then
			checkConnection:Disconnect()
			activeMoves[moveId] = nil

			DebugLog(string.format("[MoveUnitsToPositions] 完成 - 到达:%d, 失败:%d",
				#arrivedList, #failedList))

			if onAllSettled then
				pcall(function()
					onAllSettled(arrivedList, {}, failedList)  -- 中间参数是timedOutList，客户端合并到failedList
				end)
			end
		end
	end)

	activeMoves[moveId] = {
		connection = checkConnection,
		moveData = moveData,
	}

	return moveId
end

--[[
停止单位行军
@param unitModel Model - 单位模型
]]
function ClientMarchService.StopMarch(unitModel)
	if not unitModel then return end

	-- 停止动画
	StopMarchAnimation(unitModel)

	-- 清理路径
	if ClientPathService then
		ClientPathService.ClearPath(unitModel)
	end

	-- 停止移动
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero)
	end

	-- 从所有活跃的行军任务中移除该单位
	for moveId, moveTask in pairs(activeMoves) do
		if moveTask.moveData and moveTask.moveData[unitModel] then
			moveTask.moveData[unitModel].Arrived = true
			moveTask.moveData[unitModel] = nil
		end
	end
end

--[[
停止所有行军
]]
function ClientMarchService.StopAllMarches()
	for moveId, moveTask in pairs(activeMoves) do
		if moveTask.connection then
			moveTask.connection:Disconnect()
		end

		for unitInstance, data in pairs(moveTask.moveData) do
			StopMarchAnimation(unitInstance)
			if ClientPathService then
				ClientPathService.ClearPath(unitInstance)
			end

			local humanoid = unitInstance and unitInstance:FindFirstChild("Humanoid")
			if humanoid then
				humanoid:Move(Vector3.zero)
			end
		end
	end

	activeMoves = {}
	DebugLog("所有行军任务已停止")
end

--[[
获取单位行军状态
@param unitModel Model - 单位模型
@return string - "Idle" | "Marching" | "Arrived"
]]
function ClientMarchService.GetMarchState(unitModel)
	for moveId, moveTask in pairs(activeMoves) do
		if moveTask.moveData and moveTask.moveData[unitModel] then
			local data = moveTask.moveData[unitModel]
			if data.Arrived then
				return "Arrived"
			else
				return "Marching"
			end
		end
	end

	return "Idle"
end

return ClientMarchService
