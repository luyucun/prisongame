--[[
脚本名称: PathService
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/PathService
版本: V3.0 - 彻底重构，简化设计

重构要点（参考重构指南）：
1. ✅ 移除复杂的三段式优先级队列
2. ✅ 使用"时间预算"(Time Budget)代替"数量限制"
3. ✅ 简化队列逻辑，FIFO处理
4. ✅ 移除过度的节流和冷却机制
5. ✅ 保持接口兼容，不影响调用方

核心设计原则：
- 简单就是力量：复杂的优先级队列弊大于利
- 响应性优先：战斗启动时快速响应比节省CPU更重要
- 时间预算：每帧4ms时间预算，而非固定数量限制
]]

local PathService = {}

-- ==================== 依赖服务 ====================

local ServerScriptService = game:GetService("ServerScriptService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ==================== 引用配置 ====================

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 配置常量（V3.0简化版）====================

local CONFIG = {
	-- 路径请求冷却（秒）- V3.0简化：统一冷却
	PATH_RECALC_COOLDOWN = 0.2,  -- 降低到0.2秒，加快响应

	-- 目标移动阈值（studs）
	TARGET_MOVE_THRESHOLD = 10,  -- 降低到10，更快触发重寻

	-- Waypoint到达阈值（studs）
	WAYPOINT_REACH_THRESHOLD = 2,

	-- 最大重试次数
	MAX_RETRY_COUNT = 2,  -- 减少到2次，失败就直线移动

	-- 路径参数
	WAYPOINT_SPACING = 4,

	-- V3.0新增：统一的AgentRadius（避免每个兵种单独计算）
	DEFAULT_AGENT_RADIUS = 2,
	DEFAULT_AGENT_HEIGHT = 5,
	DEFAULT_AGENT_CAN_JUMP = false,

	-- V3.0新增：时间预算（毫秒）
	TIME_BUDGET_MS = 4,  -- 每帧4ms时间预算

	-- 调试选项
	DEBUG_SHOW_PATH = false,
	DEBUG_PATH_LOGS = false,
}

-- 从BattleConfig读取配置（如果存在）
if BattleConfig then
	CONFIG.DEBUG_PATH_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_PATH_LOGS
end

-- ==================== 路径状态枚举 ====================

local PathStatus = {
	IDLE = "Idle",
	QUEUED = "Queued",
	COMPUTING = "Computing",
	SUCCESS = "Success",
	FAILED = "Failed",
	BLOCKED = "Blocked",
	NEED_REPATH = "NeedRepath",
	PARTIAL = "Partial",  -- V4.0新增：部分路径（目标不可达但有最近可达点）
}

-- ==================== 私有变量 ====================

local pathStates = {}  -- [unitModel] = PathState
local pathQueue = {}   -- V3.0简化：单一FIFO队列
local isProcessing = false

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_PATH_LOGS then
		print(GameConfig.LOG_PREFIX, "[PathService-V3]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[PathService-V3]", ...)
end

-- ==================== 工具函数 ====================

local function DeepCopyWaypoints(waypoints)
	if not waypoints then return nil end
	local copy = {}
	for i, waypoint in ipairs(waypoints) do
		table.insert(copy, waypoint.Position)
	end
	return copy
end

local function GetModelPosition(model)
	if not model then return nil end
	if model:IsA("BasePart") then
		return model.Position
	end
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not rootPart then return nil end
	return rootPart.Position
end

local function GetDistance(pos1, pos2)
	if not pos1 or not pos2 then return math.huge end
	return (pos1 - pos2).Magnitude
end

-- ==================== 路径状态管理 ====================

local function InitPathState(unitModel)
	local pathState = {
		Path = nil,
		Waypoints = nil,
		Index = 0,
		LastTargetPos = nil,
		LastRequestTime = 0,
		Status = PathStatus.IDLE,
		Retries = 0,
		BlockedConnection = nil,
	}
	pathStates[unitModel] = pathState
	return pathState
end

local function GetPathState(unitModel)
	return pathStates[unitModel]
end

local function ClearPathData(unitModel)
	local pathState = pathStates[unitModel]
	if not pathState then return end

	if pathState.BlockedConnection then
		pathState.BlockedConnection:Disconnect()
		pathState.BlockedConnection = nil
	end

	if pathState.Path then
		pcall(function() pathState.Path:Destroy() end)
		pathState.Path = nil
	end

	pathState.Waypoints = nil
	pathState.Index = 0
	pathState.LastTargetPos = nil
	pathState.Status = PathStatus.IDLE
	pathState.Retries = 0
end

-- ==================== V4.2新增：动态Agent尺寸计算 ====================

--[[
根据兵种模型尺寸计算合适的AgentRadius
@param unitModel Model - 兵种模型
@return number agentRadius, number agentHeight
]]
local function CalculateAgentSize(unitModel)
	local agentRadius = CONFIG.DEFAULT_AGENT_RADIUS
	local agentHeight = CONFIG.DEFAULT_AGENT_HEIGHT

	if not unitModel then
		return agentRadius, agentHeight
	end

	-- 方法1：从Attribute读取GridWidth/GridDepth（如果有）
	local gridWidth = unitModel:GetAttribute("GridWidth") or 1
	local gridDepth = unitModel:GetAttribute("GridDepth") or 1
	local footprint = math.max(gridWidth, gridDepth)

	-- 方法2：从模型实际尺寸计算
	local modelRadius = agentRadius
	local modelHeight = agentHeight
	local success, extents = pcall(function()
		return unitModel:GetExtentsSize()
	end)
	if success and extents then
		-- 取XZ平面的最大半径，加0.5安全边距
		modelRadius = math.max(extents.X, extents.Z) / 2 + 0.5
		modelHeight = extents.Y + 0.5
	end

	-- 方法3：从UnitConfig读取（如果可用）
	local unitId = unitModel:GetAttribute("UnitId")
	if unitId and UnitConfig then
		local configSuccess, configData = pcall(function()
			return UnitConfig.GetUnitData and UnitConfig.GetUnitData(unitId)
		end)
		if configSuccess and configData then
			if configData.GridWidth then
				footprint = math.max(footprint, configData.GridWidth)
			end
			if configData.GridDepth then
				footprint = math.max(footprint, configData.GridDepth)
			end
		end
	end

	-- 综合计算：取各方法的最大值
	-- footprint转换为studs：每格约4 studs，半径=footprint*2
	local footprintRadius = footprint * 2

	agentRadius = math.max(CONFIG.DEFAULT_AGENT_RADIUS, footprintRadius, modelRadius)
	agentHeight = math.max(CONFIG.DEFAULT_AGENT_HEIGHT, modelHeight)

	-- 限制最大值，避免过大导致完全找不到路
	agentRadius = math.min(agentRadius, 8)
	agentHeight = math.min(agentHeight, 10)

	return agentRadius, agentHeight
end

-- ==================== 核心路径构建（V4.2重构版）====================

local function BuildPathInternal(unitModel, targetPos, unitId)
	local pathState = GetPathState(unitModel) or InitPathState(unitModel)

	local startPos = GetModelPosition(unitModel)
	if not startPos or not targetPos then
		pathState.Status = PathStatus.FAILED
		return false
	end

	-- 清理旧路径
	if pathState.Path then
		if pathState.BlockedConnection then
			pathState.BlockedConnection:Disconnect()
			pathState.BlockedConnection = nil
		end
		pcall(function() pathState.Path:Destroy() end)
		pathState.Path = nil
	end

	-- ✅ V4.2关键修复：根据兵种尺寸动态计算Agent参数
	local agentRadius, agentHeight = CalculateAgentSize(unitModel)

	-- V4.2优化：降低WaypointSpacing提高贴墙精度
	local waypointSpacing = math.max(2, agentRadius)  -- 至少2，或与半径匹配

	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius,
		AgentHeight = agentHeight,
		AgentCanJump = CONFIG.DEFAULT_AGENT_CAN_JUMP,
		WaypointSpacing = waypointSpacing,
	})

	DebugLog(string.format("%s 寻路参数: Radius=%.1f, Height=%.1f, Spacing=%.1f",
		unitId or "Unknown", agentRadius, agentHeight, waypointSpacing))

	pathState.Path = path
	pathState.Status = PathStatus.COMPUTING

	-- 监听阻挡事件
	pathState.BlockedConnection = path.Blocked:Connect(function(blockedWaypointIndex)
		if blockedWaypointIndex >= pathState.Index then
			pathState.Status = PathStatus.NEED_REPATH
			pathState.LastRequestTime = 0
			DebugLog(string.format("%s 路径被阻挡，标记重寻", unitId or "Unknown"))
		end
	end)

	-- 计算路径
	local success, errorMsg = pcall(function()
		path:ComputeAsync(startPos, targetPos)
	end)

	if not success then
		pathState.Status = PathStatus.FAILED
		pathState.Retries = pathState.Retries + 1
		return false
	end

	if path.Status ~= Enum.PathStatus.Success then
		-- ✅ V4.0重构：处理 NoPath (目标不可达，可能在墙里)
		-- 关键修复：不再伪装成SUCCESS！改用PARTIAL状态，禁止后续直线移动到真实目标
		if path.Status == Enum.PathStatus.NoPath then
			DebugLog(string.format("%s 目标不可达(NoPath)，检查是否有部分路径", unitId or "Unknown"))
			local waypoints = path:GetWaypoints()
			if waypoints and #waypoints >= 2 then
				-- 有部分路径，标记为PARTIAL状态（不是SUCCESS！）
				-- 调用方应该走到最近可达点后停下来，而不是继续直线冲向真实目标
				pathState.Waypoints = DeepCopyWaypoints(waypoints)
				pathState.Index = 2
				pathState.Status = PathStatus.PARTIAL  -- ✅ 使用PARTIAL而非SUCCESS
				pathState.LastTargetPos = targetPos
				pathState.LastRequestTime = tick()
				pathState.Retries = 0
				-- 保存最近可达点位置，供调用方使用
				pathState.NearestReachablePoint = waypoints[#waypoints].Position
				DebugLog(string.format("⚠️ %s NoPath但有%d个路径点，标记为PARTIAL（不是SUCCESS）", unitId or "Unknown", #waypoints))
				return true  -- 返回true表示有部分路径可用
			else
				-- 完全没有路径点，标记为FAILED
				DebugLog(string.format("❌ %s NoPath且无路径点，标记为FAILED", unitId or "Unknown"))
				pathState.Status = PathStatus.FAILED
				pathState.Retries = pathState.Retries + 1
				return false
			end
		end

		-- 路径失败，尝试缩小半径重试
		if pathState.Retries < CONFIG.MAX_RETRY_COUNT then
			pathState.Retries = pathState.Retries + 1

			-- V4.2修复：基于动态计算的半径缩小，而非固定值
			local reducedRadius = agentRadius * 0.6
			local reducedPath = PathfindingService:CreatePath({
				AgentRadius = reducedRadius,
				AgentHeight = agentHeight,
				AgentCanJump = CONFIG.DEFAULT_AGENT_CAN_JUMP,
				WaypointSpacing = waypointSpacing,
			})

			DebugLog(string.format("%s 缩小半径重试: %.1f -> %.1f", unitId or "Unknown", agentRadius, reducedRadius))

			local retrySuccess = pcall(function()
				reducedPath:ComputeAsync(startPos, targetPos)
			end)

			if retrySuccess and reducedPath.Status == Enum.PathStatus.Success then
				local waypoints = reducedPath:GetWaypoints()
				if waypoints and #waypoints >= 2 then
					-- V3.0.2修复：销毁旧的path对象，避免内存泄漏
					if pathState.BlockedConnection then
						pathState.BlockedConnection:Disconnect()
						pathState.BlockedConnection = nil
					end
					pcall(function() path:Destroy() end)

					pathState.Path = reducedPath
					pathState.Waypoints = DeepCopyWaypoints(waypoints)
					pathState.Index = 2
					pathState.Status = PathStatus.SUCCESS
					pathState.LastTargetPos = targetPos
					pathState.LastRequestTime = tick()
					pathState.Retries = 0
					DebugLog(string.format("%s 缩小半径后寻路成功", unitId or "Unknown"))
					return true
				end
			end
			reducedPath:Destroy()
		end

		pathState.Status = PathStatus.FAILED
		return false
	end

	local waypoints = path:GetWaypoints()
	if not waypoints or #waypoints < 2 then
		pathState.Status = PathStatus.FAILED
		return false
	end

	pathState.Waypoints = DeepCopyWaypoints(waypoints)
	pathState.Index = 2  -- 跳过起点
	pathState.Status = PathStatus.SUCCESS
	pathState.LastTargetPos = targetPos
	pathState.LastRequestTime = tick()
	pathState.Retries = 0

	DebugLog(string.format("%s 寻路成功，%d个路径点", unitId or "Unknown", #pathState.Waypoints))
	return true
end

-- ==================== V3.0新增：时间预算队列处理器 ====================

local function ProcessQueueWithTimeBudget()
	if #pathQueue == 0 then
		isProcessing = false
		return
	end

	isProcessing = true
	local budgetEndTime = tick() + (CONFIG.TIME_BUDGET_MS / 1000)  -- 转换为秒
	local processedCount = 0

	while #pathQueue > 0 and tick() < budgetEndTime do
		local request = table.remove(pathQueue, 1)  -- FIFO出队

		-- 检查有效性
		if not request.unitModel or not request.unitModel.Parent then
			-- 单位已删除，跳过
			if request.callback then
				pcall(function() request.callback(false, nil) end)
			end
			continue
		end

		if not request.targetPos then
			if request.callback then
				pcall(function() request.callback(false, nil) end)
			end
			continue
		end

		-- 执行路径计算
		local success = BuildPathInternal(request.unitModel, request.targetPos, request.unitId)
		local pathState = GetPathState(request.unitModel)

		if request.callback then
			pcall(function() request.callback(success, pathState) end)
		end

		processedCount = processedCount + 1
	end

	-- 如果队列还有剩余，下一帧继续处理
	if #pathQueue > 0 then
		task.defer(ProcessQueueWithTimeBudget)
	else
		isProcessing = false
	end

	if processedCount > 0 then
		DebugLog(string.format("本帧处理%d个路径请求，剩余%d个", processedCount, #pathQueue))
	end
end

-- ==================== 公共接口 ====================

--[[
请求路径（异步版本）
@param unitModel - 兵种模型
@param targetModel - 目标模型（Model或Part）
@param unitId - 单位ID
@param callback - 回调函数 function(success:boolean, pathState:table|nil)
@return boolean - 是否成功入队
]]
function PathService.RequestPathAsync(unitModel, targetModel, unitId, callback)
	if not unitModel or not targetModel then
		if callback then
			pcall(function() callback(false, nil) end)
		end
		return false
	end

	-- 获取目标位置
	local targetPos = GetModelPosition(targetModel)
	if not targetPos then
		if callback then
			pcall(function() callback(false, nil) end)
		end
		return false
	end

	-- V3.0简化：检查是否已在队列中（防止重复入队）
	for i, req in ipairs(pathQueue) do
		if req.unitModel == unitModel then
			-- 更新现有请求的目标位置和回调
			req.targetPos = targetPos
			req.callback = callback
			return true
		end
	end

	-- 更新路径状态为QUEUED
	local pathState = GetPathState(unitModel) or InitPathState(unitModel)
	pathState.Status = PathStatus.QUEUED

	-- 入队
	table.insert(pathQueue, {
		unitModel = unitModel,
		targetPos = targetPos,
		unitId = unitId,
		callback = callback,
		queueTime = tick(),
	})

	-- 启动处理器（如果未运行）
	if not isProcessing then
		task.defer(ProcessQueueWithTimeBudget)
	end

	return true
end

--[[
同步请求路径（向后兼容）
]]
function PathService.RequestPath(unitModel, targetModel, unitId)
	if not unitModel or not targetModel then
		return false
	end

	unitId = unitId or tostring(unitModel)
	local pathState = GetPathState(unitModel) or InitPathState(unitModel)

	-- 如果需要重建，清理后构建
	if pathState.Status == PathStatus.NEED_REPATH then
		ClearPathData(unitModel)
	end

	-- 如果已有成功路径，检查是否需要更新
	if pathState.Status == PathStatus.SUCCESS and pathState.Waypoints and #pathState.Waypoints > 0 then
		local targetPos = GetModelPosition(targetModel)
		if targetPos and pathState.LastTargetPos then
			local distance = GetDistance(targetPos, pathState.LastTargetPos)
			if distance < CONFIG.TARGET_MOVE_THRESHOLD then
				return true  -- 复用路径
			end
		end
	end

	-- 检查冷却
	local currentTime = tick()
	if (currentTime - pathState.LastRequestTime) < CONFIG.PATH_RECALC_COOLDOWN then
		return pathState.Status == PathStatus.SUCCESS
	end

	local targetPos = GetModelPosition(targetModel)
	return BuildPathInternal(unitModel, targetPos, unitId)
end

--[[
获取下一个路径点
V4.0修改：同时支持SUCCESS和PARTIAL状态
]]
function PathService.GetNextWaypoint(unitModel)
	local pathState = GetPathState(unitModel)
	-- V4.0修复：PARTIAL状态也可以获取路径点（但调用方需要知道这是部分路径）
	if not pathState or (pathState.Status ~= PathStatus.SUCCESS and pathState.Status ~= PathStatus.PARTIAL) then
		return nil
	end
	if not pathState.Waypoints or pathState.Index > #pathState.Waypoints then
		return nil
	end
	return pathState.Waypoints[pathState.Index]
end

--[[
推进到下一个路径点
V4.0修改：同时支持SUCCESS和PARTIAL状态
]]
function PathService.AdvancePath(unitModel)
	local pathState = GetPathState(unitModel)
	-- V4.0修复：PARTIAL状态也可以推进路径
	if not pathState or (pathState.Status ~= PathStatus.SUCCESS and pathState.Status ~= PathStatus.PARTIAL) then
		return false
	end
	if not pathState.Waypoints then
		return false
	end

	pathState.Index = pathState.Index + 1
	if pathState.Index > #pathState.Waypoints then
		return false
	end
	return true
end

--[[
获取路径状态
]]
function PathService.GetPathStatus(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then
		return PathStatus.IDLE
	end
	return pathState.Status
end

--[[
清理路径
]]
function PathService.ClearPath(unitModel)
	ClearPathData(unitModel)

	-- 同时从队列中移除
	for i = #pathQueue, 1, -1 do
		if pathQueue[i].unitModel == unitModel then
			table.remove(pathQueue, i)
			break
		end
	end
end

--[[
强制重建路径
]]
function PathService.ForceRepath(unitModel)
	local pathState = GetPathState(unitModel)
	if pathState then
		pathState.Status = PathStatus.NEED_REPATH
		pathState.LastRequestTime = 0
	end
end

--[[
检查是否到达路径点
V4.0修改：同时支持SUCCESS和PARTIAL状态
]]
function PathService.HasReachedWaypoint(unitModel, threshold)
	threshold = threshold or CONFIG.WAYPOINT_REACH_THRESHOLD

	local pathState = GetPathState(unitModel)
	-- V4.0修复：PARTIAL状态也可以检查到达
	if not pathState or (pathState.Status ~= PathStatus.SUCCESS and pathState.Status ~= PathStatus.PARTIAL) then
		return false
	end

	local currentWaypoint = pathState.Waypoints[pathState.Index]
	if not currentWaypoint then
		return false
	end

	local currentPos = GetModelPosition(unitModel)
	if not currentPos then
		return false
	end

	-- XZ平面距离
	local distance = math.sqrt(
		(currentWaypoint.X - currentPos.X)^2 +
		(currentWaypoint.Z - currentPos.Z)^2
	)
	return distance < threshold
end

--[[
清理所有路径
]]
function PathService.ClearAllPaths()
	for unitModel, _ in pairs(pathStates) do
		ClearPathData(unitModel)
	end
	pathStates = {}
	pathQueue = {}
	DebugLog("所有路径已清理")
end

--[[
清理指定战斗的路径
]]
function PathService.ClearBattlePaths(battleId, getUnitState)
	if not getUnitState then return end

	-- 先收集需要清理的单位，避免迭代时修改表
	local toClear = {}
	for unitModel, _ in pairs(pathStates) do
		local state = getUnitState(unitModel)
		if state and state.BattleId == battleId then
			table.insert(toClear, unitModel)
		end
	end

	-- 然后清理
	for _, unitModel in ipairs(toClear) do
		ClearPathData(unitModel)
		pathStates[unitModel] = nil
	end
end

--[[
获取路径点数量
]]
function PathService.GetWaypointCount(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState or not pathState.Waypoints then
		return 0
	end
	return #pathState.Waypoints
end

--[[
获取当前路径点索引
]]
function PathService.GetCurrentWaypointIndex(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then
		return 0
	end
	return pathState.Index
end

--[[
获取路径状态对象（公共接口）
]]
function PathService.GetPathState(unitModel)
	return pathStates[unitModel]
end

--[[
V4.0新增：检查路径是否为部分路径（目标不可达）
@return boolean - true表示是部分路径，调用方应该在路径走完后停下来而非直线冲刺
]]
function PathService.IsPartialPath(unitModel)
	local pathState = GetPathState(unitModel)
	return pathState and pathState.Status == PathStatus.PARTIAL
end

--[[
V4.0新增：获取最近可达点（仅对PARTIAL路径有效）
@return Vector3|nil - 最近可达点的位置
]]
function PathService.GetNearestReachablePoint(unitModel)
	local pathState = GetPathState(unitModel)
	if pathState and pathState.Status == PathStatus.PARTIAL then
		return pathState.NearestReachablePoint
	end
	return nil
end

--[[
获取配置
]]
function PathService.GetConfig()
	return CONFIG
end

-- ==================== V3.1新增：行军用障碍检测辅助函数 ====================

--[[
检测单位到目标位置是否有障碍物（用于行军阶段）
V3.1新增：复制自UnitAI的IsPathClear逻辑，用于行军期间的障碍检测

@param unitInstance Model - 单位模型
@param targetPos Vector3 - 目标位置
@return boolean - true表示路径畅通，false表示有障碍
]]
local function IsPathClearForMarch(unitInstance, targetPos)
	local root = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
	if not root then return false end

	local startPos = root.Position
	local direction = targetPos - startPos
	local distance = direction.Magnitude

	if distance < 3 then return true end

	-- 使用 Blockcast 检测
	local size = Vector3.new(3, 5, 1)  -- 宽3, 高5
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local filterList = {unitInstance}
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		table.insert(filterList, unitsFolder)
	end
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	local cframe = CFrame.lookAt(startPos, Vector3.new(targetPos.X, startPos.Y, targetPos.Z))
	local detectDistance = math.max(1, distance - 2)
	local result = workspace:Blockcast(cframe, size, direction.Unit * detectDistance, rayParams)

	if result and result.Instance.CanCollide then
		return false  -- 有障碍
	end
	return true
end

-- ==================== V3.0简化版批量移动（战役系统）====================

local activeMoves = {}
local nextMoveId = 1

--[[
批量移动兵种到指定位置
简化版本：去除过度复杂的批次管理，专注于基本功能
]]
function PathService.MoveUnitsToPositions(moveTargets, callbacks)
	if not moveTargets or type(moveTargets) ~= "table" then
		return nil
	end

	local onUnitArrived = nil
	local onAllSettled = nil

	if type(callbacks) == "function" then
		onAllSettled = callbacks
	elseif type(callbacks) == "table" then
		onUnitArrived = callbacks.onUnitArrived
		onAllSettled = callbacks.onAllSettled
	end

	local moveId = "Move_" .. tostring(nextMoveId)
	nextMoveId = nextMoveId + 1

	local moveData = {}
	local unitsList = {}
	local arrivedList = {}
	local timedOutList = {}
	local failedList = {}
	local totalCount = 0

	-- 准备单位数据
	for unitInstance, targetCFrame in pairs(moveTargets) do
		local humanoid = unitInstance and unitInstance:FindFirstChild("Humanoid")
		local rootPart = unitInstance and (unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart)

		if humanoid and rootPart then
			-- 创建目标Part
			local targetPart = Instance.new("Part")
			targetPart.Size = Vector3.new(1, 1, 1)
			targetPart.CFrame = targetCFrame
			targetPart.Anchored = true
			targetPart.CanCollide = false
			targetPart.Transparency = 1
			targetPart.Name = "MarchTarget_" .. unitInstance.Name
			targetPart.Parent = workspace

			moveData[unitInstance] = {
				TargetPart = targetPart,
				TargetCFrame = targetCFrame,
				Arrived = false,
				StartTime = tick(),
				PathRequested = false,
			}

			table.insert(unitsList, unitInstance)
			totalCount = totalCount + 1
		end
	end

	if totalCount == 0 then
		if onAllSettled then
			onAllSettled({}, {}, {})
		end
		return nil
	end

	-- 启动所有单位的路径请求
	-- ✅ V4.1修复：分批发起寻路请求，避免一口气塞爆队列
	local BATCH_SIZE = 4  -- 每批4个单位
	local batchIndex = 0

	for _, unitInstance in ipairs(unitsList) do
		local data = moveData[unitInstance]
		local unitId = unitInstance:GetAttribute("UnitId") or unitInstance.Name

		-- 确保解锚
		local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
		if rootPart and rootPart.Anchored then
			rootPart.Anchored = false
		end

		-- V4.1分批：每BATCH_SIZE个单位等待一帧
		batchIndex = batchIndex + 1
		if batchIndex > BATCH_SIZE then
			batchIndex = 1
			task.wait()  -- 让出一帧给队列处理
		end

		-- 请求路径
		data.PathRequested = true
		PathService.RequestPathAsync(unitInstance, data.TargetPart, unitId, function(success, pathState)
			data.PathRequested = false

			if data.Arrived then return end

			local humanoid = unitInstance:FindFirstChild("Humanoid")
			if not humanoid then return end

			-- ✅ V4.1修复：同时处理SUCCESS和PARTIAL状态
			if success and pathState and (pathState.Status == PathStatus.SUCCESS or pathState.Status == PathStatus.PARTIAL) then
				local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
				if nextWaypoint then
					humanoid:MoveTo(nextWaypoint)
				elseif pathState.Status == PathStatus.PARTIAL then
					-- PARTIAL但没有路径点，停在原地等待
					humanoid:Move(Vector3.zero)
					DebugLog(string.format("⚠️ [行军] %s PARTIAL但无路径点，原地待命", unitInstance.Name))
				else
					-- SUCCESS但没路径点（已经很近），直接去目标
					humanoid:MoveTo(data.TargetCFrame.Position)
				end
			else
				-- 寻路失败，原地等待重试
				humanoid:Move(Vector3.zero)
				DebugLog(string.format("⚠️ [行军] %s 初始寻路失败，等待重试", unitInstance.Name))
			end
		end)

		-- 监听MoveToFinished
		local humanoid = unitInstance:FindFirstChild("Humanoid")
		if humanoid then
			data.MoveConnection = humanoid.MoveToFinished:Connect(function(reached)
				if data.Arrived then return end

				local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
				if not rootPart then return end

				local currentPos = rootPart.Position
				local targetPos = data.TargetCFrame.Position
				local distanceXZ = math.sqrt((currentPos.X - targetPos.X)^2 + (currentPos.Z - targetPos.Z)^2)
				local arrivalThreshold = GameConfig.Campaign and GameConfig.Campaign.ArrivalThreshold or 8

				if distanceXZ < arrivalThreshold then
					-- 到达
					data.Arrived = true
					if data.MoveConnection then
						data.MoveConnection:Disconnect()
						data.MoveConnection = nil
					end
					PathService.ClearPath(unitInstance)
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end
					table.insert(arrivedList, unitInstance)

					if onUnitArrived then
						pcall(function() onUnitArrived(unitInstance, "Arrived") end)
					end
				else
					-- ✅ V4.2关键修复：处理reached==false（撞墙/无法到达waypoint）
					if not reached then
						-- MoveTo超时但未到达waypoint，说明被墙挡住了
						-- 立即停止并触发重寻路
						DebugLog(string.format("⚠️ [行军] %s MoveToFinished reached=false，可能撞墙，触发重寻路", unitInstance.Name))
						humanoid:Move(Vector3.zero)  -- 先停下
						PathService.ClearPath(unitInstance)  -- 清除错误路径
						data.ForceRepath = true  -- 标记需要重寻路
						data.WallHitCount = (data.WallHitCount or 0) + 1
						return
					end

					-- 未到达但reached==true，继续移动
					local pathStatus = PathService.GetPathStatus(unitInstance)
					-- ✅ V4.1修复：同时处理SUCCESS和PARTIAL状态
					if pathStatus == PathStatus.SUCCESS or pathStatus == PathStatus.PARTIAL then
						local isPartial = (pathStatus == PathStatus.PARTIAL)

						PathService.AdvancePath(unitInstance)
						local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
						if nextWaypoint then
							humanoid:MoveTo(nextWaypoint)
						else
							-- 路径点用完
							if isPartial then
								-- ✅ PARTIAL路径走完，停在最近可达点，不要直线冲刺！
								humanoid:Move(Vector3.zero)
								DebugLog(string.format("⚠️ [行军] %s PARTIAL路径走完，停在最近可达点", unitInstance.Name))
							else
								-- SUCCESS路径走完，检查是否接近目标
								local distToTarget = (rootPart.Position - targetPos).Magnitude
								if distToTarget < 5 then
									humanoid:MoveTo(targetPos)
								else
									humanoid:Move(Vector3.zero)
								end
							end
						end
					else
						-- 无有效路径，原地等待重寻路
						humanoid:Move(Vector3.zero)
					end
				end
			end)
		end
	end

	-- 定期检查超时
	local checkConnection
	local lastCheckTime = tick()
	local moveTimeout = GameConfig.Campaign and GameConfig.Campaign.MoveTimeout or 30

	checkConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastCheckTime < 0.1 then return end
		lastCheckTime = now

		local allDone = true
		local arrivedThisFrame = 0

		for unitInstance, data in pairs(moveData) do
			if not data.Arrived then
				allDone = false

				-- 检查实例有效性
				if not unitInstance or not unitInstance.Parent then
					data.Arrived = true
					arrivedThisFrame = arrivedThisFrame + 1
					if data.MoveConnection then
						data.MoveConnection:Disconnect()
						data.MoveConnection = nil
					end
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end
					table.insert(failedList, unitInstance)
					continue
				end

				-- 检查是否已到达
				local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
				if rootPart then
					local currentPos = rootPart.Position
					local targetPos = data.TargetCFrame.Position
					local distanceXZ = math.sqrt((currentPos.X - targetPos.X)^2 + (currentPos.Z - targetPos.Z)^2)
					local arrivalThreshold = GameConfig.Campaign and GameConfig.Campaign.ArrivalThreshold or 8

					if distanceXZ < arrivalThreshold then
						data.Arrived = true
						arrivedThisFrame = arrivedThisFrame + 1
						if data.MoveConnection then
							data.MoveConnection:Disconnect()
							data.MoveConnection = nil
						end
						PathService.ClearPath(unitInstance)
						if data.TargetPart and data.TargetPart.Parent then
							data.TargetPart:Destroy()
						end
						table.insert(arrivedList, unitInstance)

						if onUnitArrived then
							pcall(function() onUnitArrived(unitInstance, "Arrived") end)
						end
						continue
					end

					-- ==================== V4.0重构：行军期间的障碍检测和防卡死 ====================
					-- 每0.5秒检查一次
					local checkInterval = 0.5
					if now - (data.LastObstacleCheck or 0) > checkInterval then
						data.LastObstacleCheck = now

						-- ✅ V4.0关键修复：如果正在等待路径计算，跳过所有卡住检测！
						-- 避免狂刷队列导致一卡一卡
						if data.PathRequested then
							-- 正在等待寻路结果，不要触发任何重寻路逻辑
							-- 重置卡住计数器，因为等待期间不算卡住
							data.StuckCount = 0
							data.WrongWayCount = 0
						else
							-- 1. 卡住检测 (V3.5重构：基于WalkSpeed的距离对比检测)
							-- 获取单位的实际WalkSpeed
							local humanoid = unitInstance:FindFirstChild("Humanoid")
							local walkSpeed = humanoid and humanoid.WalkSpeed or 16  -- 默认16 studs/s

							-- 计算预期移动距离 = 移动速度 * 时间 * 容差系数(0.5表示只要移动不到预期的一半就算卡住)
							local expectedDistance = walkSpeed * checkInterval * 0.5

							-- 计算实际移动距离
							local currentPos = rootPart.Position
							local lastPos = data.LastStuckCheckPos or currentPos
							local actualDistance = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude

							-- 更新位置记录
							data.LastStuckCheckPos = currentPos

							-- 如果实际移动距离 < 预期移动距离 且 离目标还有距离，判定为卡住
							-- V4.0修复：增加重试退避机制
							if actualDistance < expectedDistance and distanceXZ > 5 then
								data.StuckCount = (data.StuckCount or 0) + 1
								DebugLog(string.format("⚠️ [行军] %s 卡住检测: 实际%.2f < 预期%.2f (速度%.0f, 次数%d)",
									unitInstance.Name, actualDistance, expectedDistance, walkSpeed, data.StuckCount))

								-- V4.0修复：卡住2次才触发重寻路（增加容忍度，避免频繁重寻）
								if data.StuckCount >= 2 then
									DebugLog(string.format("⚠️ [行军] %s 确认卡住，触发重新寻路", unitInstance.Name))
									data.StuckCount = 0
									data.ForceRepath = true
								end
							else
								data.StuckCount = 0
							end

							-- 2. 障碍检测 (Blockcast)
							-- V4.0修复：只有在没有有效路径且不在等待时才检测障碍
							local pathStatus = PathService.GetPathStatus(unitInstance)
							-- V4.0修复：PARTIAL状态也算有路径，不要触发障碍检测
							if pathStatus ~= "Success" and pathStatus ~= "Partial" and not IsPathClearForMarch(unitInstance, targetPos) then
								DebugLog(string.format("⚠️ [行军] %s 检测到障碍，请求寻路", unitInstance.Name))
								data.ForceRepath = true
							end

							-- 3. 走错路检测 (距离越来越远)
							-- 记录上次距离，如果连续3次检测距离都在增加，说明走错路了
							local lastDistance = data.LastDistanceToTarget or distanceXZ
							if distanceXZ > lastDistance + 1 then  -- 距离增加超过1 stud
								data.WrongWayCount = (data.WrongWayCount or 0) + 1
								if data.WrongWayCount >= 3 then  -- 连续3次（约1.5秒）距离增加
									DebugLog(string.format("⚠️ [行军] %s 走错路(距离增加 %.1f→%.1f)，强制重寻路",
										unitInstance.Name, lastDistance, distanceXZ))
									data.WrongWayCount = 0
									data.ForceRepath = true
									PathService.ClearPath(unitInstance)  -- 清除错误路径
								end
							else
								data.WrongWayCount = 0
							end
							data.LastDistanceToTarget = distanceXZ

							-- 4. 周期性重寻路 (每5秒强制重算一次)
							-- V4.0修复：延长周期到8秒，减少不必要的重寻
							local timeSinceStart = now - data.StartTime
							local lastRepath = data.LastRepathTime or 0
							if timeSinceStart > 3 and (now - lastRepath) > 8 then  -- 开始3秒后，每8秒检查
								if distanceXZ > 10 then  -- 还没接近目标
									DebugLog(string.format("⚠️ [行军] %s 周期性重寻路检查(距离=%.1f)", unitInstance.Name, distanceXZ))
									data.LastRepathTime = now
									data.ForceRepath = true
									PathService.ClearPath(unitInstance)
								end
							end
						end -- end of if not data.PathRequested
					end

					-- 如果触发了强制重寻
					if data.ForceRepath then
						data.ForceRepath = false
						data.PathRequested = true

						-- 清理旧路径
						PathService.ClearPath(unitInstance)

						-- V4.0修复：增加重试退避计数
						data.RepathRetryCount = (data.RepathRetryCount or 0) + 1
						local retryDelay = math.min(0.1 * data.RepathRetryCount, 1.0)  -- 最大1秒退避

						-- 稍微延迟后再发起寻路请求（避免狂刷队列）
						task.delay(retryDelay, function()
							if data.Arrived then return end  -- 如果已到达则跳过

							-- 重新发起寻路请求
							PathService.RequestPathAsync(unitInstance, data.TargetPart, unitInstance.Name, function(success, pathState)
								data.PathRequested = false
								local humanoid = unitInstance:FindFirstChild("Humanoid")

								-- V4.0修复：Success和Partial都可以移动
								if success and pathState and (pathState.Status == "Success" or pathState.Status == "Partial") and humanoid then
									local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
									if nextWaypoint then
										humanoid:MoveTo(nextWaypoint)
										-- 寻路成功，重置重试计数
										data.RepathRetryCount = 0
									elseif pathState.Status == "Partial" then
										-- PARTIAL但没路径点，停下等待
										humanoid:Move(Vector3.zero)
									end
								elseif humanoid then
									-- ✅ V4.0修复：寻路失败时，物理刹车，原地等待下一次重试
									-- 绝对不要再 humanoid:MoveTo(targetPos) 了！
									humanoid:Move(Vector3.zero)
									DebugLog(string.format("⚠️ [行军] %s 寻路失败(第%d次)，原地待命等待重试",
										unitInstance.Name, data.RepathRetryCount or 0))
								end
							end)
						end)
					end
					-- ==================== V4.0重构结束 ====================
				end

				-- 超时检查
				if now - data.StartTime > moveTimeout then
					data.Arrived = true
					arrivedThisFrame = arrivedThisFrame + 1
					if data.MoveConnection then
						data.MoveConnection:Disconnect()
						data.MoveConnection = nil
					end
					PathService.ClearPath(unitInstance)
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end

					-- 停止移动
					local humanoid = unitInstance:FindFirstChild("Humanoid")
					if humanoid then
						humanoid:Move(Vector3.zero, true)
					end

					table.insert(timedOutList, unitInstance)

					if onUnitArrived then
						pcall(function() onUnitArrived(unitInstance, "TimedOut") end)
					end
				end
			end
		end

		-- 重新检查是否所有都完成（因为可能本帧有新的到达）
		if arrivedThisFrame > 0 then
			allDone = true
			for _, data in pairs(moveData) do
				if not data.Arrived then
					allDone = false
					break
				end
			end
		end

		if allDone then
			checkConnection:Disconnect()
			activeMoves[moveId] = nil

			if onAllSettled then
				pcall(function()
					onAllSettled(arrivedList, timedOutList, failedList)
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
取消批量移动任务
]]
function PathService.CancelGroupMove(moveId)
	local moveTask = activeMoves[moveId]
	if not moveTask then
		return false
	end

	if moveTask.connection then
		moveTask.connection:Disconnect()
	end

	for unitInstance, data in pairs(moveTask.moveData) do
		data.Arrived = true

		if data.MoveConnection then
			data.MoveConnection:Disconnect()
			data.MoveConnection = nil  -- V3.0.2修复：置nil避免重复断开
		end

		PathService.ClearPath(unitInstance)

		if data.TargetPart and data.TargetPart.Parent then
			data.TargetPart:Destroy()
		end

		local humanoid = unitInstance and unitInstance:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:Move(Vector3.zero, true)
		end
	end

	activeMoves[moveId] = nil
	return true
end

-- ==================== 性能统计（简化版）====================

function PathService.GetPerformanceStats()
	return {
		QueuedRequests = #pathQueue,
		ActiveMoveTasks = 0,
		TotalUnitsMoving = 0,
	}
end

function PathService.ResetPerformanceStats()
	-- V3.0简化：无需复杂统计
end

function PathService.PrintPerformanceStats()
	print("==================== PathService-V3 状态 ====================")
	print(string.format("队列长度: %d", #pathQueue))
	print("=============================================================")
end

function PathService.SetDebugOptions(showPath, showLogs)
	if showPath ~= nil then
		CONFIG.DEBUG_SHOW_PATH = showPath
	end
	if showLogs ~= nil then
		CONFIG.DEBUG_PATH_LOGS = showLogs
	end
end

return PathService
