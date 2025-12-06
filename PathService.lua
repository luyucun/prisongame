--[[
脚本名称: PathService
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/PathService
版本: V5.4 - 修复行军/战斗MoveTo冲突

V5.4更新内容：
1. ✅ 关键修复：ClearPath增强 - 同时清理activeMoves中的行军任务数据
   - 从所有activeMoves中移除单位，断开MoveConnection
   - 防止行军Heartbeat继续发送MoveTo指令与战斗AI冲突
   - 这是解决"卡顿/回头"问题的核心修复之一

V5.3更新内容：
1. ✅ 修复"走错路"误判：放宽阈值并忽略终点附近(15 studs内)的后退检测

V5.2更新内容：
1. ✅ 实现切角机制 - 中间路点距离<5时立即切换，不等MoveToFinished
2. ✅ 放宽卡住检测 - 降低检测频率(0.5→1.0秒)和最小速度阈值(0.5→0.1)
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

-- ==================== 配置常量 ====================

local CONFIG = {
	-- 路径请求冷却（秒）
	PATH_RECALC_COOLDOWN = 0.3,

	-- 目标移动阈值（studs）- 目标位置变化超过此值才重新寻路
	TARGET_MOVE_THRESHOLD = 8,

	-- Waypoint到达阈值（studs）
	WAYPOINT_REACH_THRESHOLD = 1.5,

	-- 最大重试次数（缩小半径重试）
	MAX_RETRY_COUNT = 2,

	-- Agent默认参数
	DEFAULT_AGENT_RADIUS = 2,
	DEFAULT_AGENT_HEIGHT = 5,
	DEFAULT_AGENT_CAN_JUMP = false,

	-- 时间预算（毫秒）
	TIME_BUDGET_MS = 8,              -- 基础预算
	TIME_BUDGET_MAX_MS = 16,         -- 队列堆积时的最大预算
	QUEUE_THRESHOLD_FOR_BOOST = 10,  -- 超过此队列长度时提高预算

	-- 行军卡住检测配置
	MARCH_STUCK_CHECK_INTERVAL = 1.0,   -- 检测间隔（秒）- 降低检测频率
	MARCH_STUCK_MIN_VELOCITY = 0.1,     -- 最小速度阈值（studs）- 只要还在动就不算卡住
	MARCH_STUCK_COUNT_THRESHOLD = 5,    -- 连续卡住次数阈值 - 给更多容错机会
	MARCH_REPATH_COOLDOWN = 1.5,        -- 重寻路冷却（秒）

	-- V5.1/V5.3 走错路检测配置
	MARCH_WRONG_WAY_THRESHOLD = 5,      -- [修改] 增加容错次数 (3->5)
	MARCH_WRONG_WAY_DISTANCE = 5,       -- [修改] 增加距离阈值 (2->5)，防止被挤退时误判

	-- V5.1新增：周期性重寻路配置
	MARCH_PERIODIC_REPATH_DELAY = 15,   -- 周期性重寻路间隔（秒）
	MARCH_PERIODIC_MIN_DISTANCE = 15,   -- 触发周期性重寻路的最小距离

	-- V5.1新增：MoveToFinished失败处理
	MARCH_MOVETO_FAIL_THRESHOLD = 3,    -- 连续失败次数阈值

	-- 拥挤豁免配置
	CROWD_CHECK_RADIUS = 5,             -- 拥挤检测半径
	CROWD_THRESHOLD = 3,                -- 周围超过此数量友军时豁免

	-- 分散重寻路延迟
	REPATH_RANDOM_DELAY_MAX = 0.2,      -- 随机延迟最大值（秒）

	-- 调试选项
	DEBUG_PATH_LOGS = false,
}

-- 从BattleConfig读取配置
if BattleConfig then
	CONFIG.DEBUG_PATH_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_PATH_LOGS
end

-- ==================== 路径状态枚举 ====================

local PathStatus = {
	IDLE = "Idle",
	QUEUED = "Queued",
	COMPUTING = "Computing",
	SUCCESS = "Success",
	PARTIAL = "Partial",    -- 目标不可达但有最近可达点
	FAILED = "Failed",
	BLOCKED = "Blocked",
	NEED_REPATH = "NeedRepath",
}

PathService.PathStatus = PathStatus

-- ==================== 私有变量 ====================

local pathStates = {}      -- [unitModel] = PathState
local pathQueue = {}       -- FIFO队列
local isProcessing = false
local activeMoves = {}     -- 批量移动任务
local nextMoveId = 1

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_PATH_LOGS then
		print(GameConfig.LOG_PREFIX, "[PathService-V5]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[PathService-V5]", ...)
end

-- ==================== 工具函数 ====================

local function GetModelPosition(model)
	if not model then return nil end
	if model:IsA("BasePart") then
		return model.Position
	end
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not rootPart then return nil end
	return rootPart.Position
end

local function GetHorizontalDistance(pos1, pos2)
	if not pos1 or not pos2 then return math.huge end
	return math.sqrt((pos1.X - pos2.X)^2 + (pos1.Z - pos2.Z)^2)
end

local function GetDistance3D(pos1, pos2)
	if not pos1 or not pos2 then return math.huge end
	return (pos1 - pos2).Magnitude
end

-- 深拷贝路径点（只保留Position）
local function DeepCopyWaypoints(waypoints)
	if not waypoints then return nil end
	local copy = {}
	for i, waypoint in ipairs(waypoints) do
		table.insert(copy, waypoint.Position)
	end
	return copy
end

-- ==================== 动态Agent尺寸计算 ====================

--[[
根据兵种模型尺寸计算合适的AgentRadius
优先级：GridWidth/GridDepth > 模型实际尺寸 > 默认值
@param unitModel Model - 兵种模型
@return number agentRadius, number agentHeight
]]
local function CalculateAgentSize(unitModel)
	local agentRadius = CONFIG.DEFAULT_AGENT_RADIUS
	local agentHeight = CONFIG.DEFAULT_AGENT_HEIGHT

	if not unitModel then
		return agentRadius, agentHeight
	end

	-- 方法1：从Attribute读取GridWidth/GridDepth
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
		modelRadius = math.max(extents.X, extents.Z) / 2 + 0.3
		modelHeight = extents.Y + 0.3
	end

	-- 方法3：从UnitConfig读取
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

	-- 综合计算：footprint转换为studs（每格约4 studs）
	local footprintRadius = footprint * 2

	agentRadius = math.max(CONFIG.DEFAULT_AGENT_RADIUS, footprintRadius, modelRadius)
	agentHeight = math.max(CONFIG.DEFAULT_AGENT_HEIGHT, modelHeight)

	-- 限制最大值，避免过大导致完全找不到路
	-- V5.1修复：恢复agentRadius上限为8，支持大型单位
	agentRadius = math.min(agentRadius, 8)
	agentHeight = math.min(agentHeight, 10)

	return agentRadius, agentHeight
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
		NearestReachablePoint = nil,  -- PARTIAL状态下的最近可达点
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

	-- 断开Blocked事件连接
	if pathState.BlockedConnection then
		pathState.BlockedConnection:Disconnect()
		pathState.BlockedConnection = nil
	end

	-- 销毁Path对象
	if pathState.Path then
		pcall(function() pathState.Path:Destroy() end)
		pathState.Path = nil
	end

	pathState.Waypoints = nil
	pathState.Index = 0
	pathState.LastTargetPos = nil
	pathState.Status = PathStatus.IDLE
	pathState.Retries = 0
	pathState.NearestReachablePoint = nil
end

-- ==================== 核心路径构建 ====================

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

	-- 动态计算Agent参数
	local agentRadius, agentHeight = CalculateAgentSize(unitModel)
	local waypointSpacing = math.max(2, agentRadius)

	-- 创建路径
	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius,
		AgentHeight = agentHeight,
		AgentCanJump = CONFIG.DEFAULT_AGENT_CAN_JUMP,
		WaypointSpacing = waypointSpacing,
	})

	pathState.Path = path
	pathState.Status = PathStatus.COMPUTING

	-- 监听Blocked事件
	pathState.BlockedConnection = path.Blocked:Connect(function(blockedWaypointIndex)
		if blockedWaypointIndex >= pathState.Index then
			pathState.Status = PathStatus.NEED_REPATH
			pathState.LastRequestTime = 0  -- 允许立即重寻
			DebugLog(string.format("%s 路径被阻挡在waypoint %d", unitId or "Unknown", blockedWaypointIndex))
		end
	end)

	-- 计算路径
	local success, errorMsg = pcall(function()
		path:ComputeAsync(startPos, targetPos)
	end)

	if not success then
		pathState.Status = PathStatus.FAILED
		pathState.Retries = pathState.Retries + 1
		WarnLog(string.format("%s ComputeAsync失败: %s", unitId or "Unknown", tostring(errorMsg)))
		return false
	end

	-- 处理路径结果
	if path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		if waypoints and #waypoints >= 2 then
			pathState.Waypoints = DeepCopyWaypoints(waypoints)
			pathState.Index = 2  -- 跳过起点
			pathState.Status = PathStatus.SUCCESS
			pathState.LastTargetPos = targetPos
			pathState.LastRequestTime = tick()
			pathState.Retries = 0
			pathState.NearestReachablePoint = nil
			DebugLog(string.format("%s 寻路成功，%d个路径点", unitId or "Unknown", #pathState.Waypoints))
			return true
		end
	elseif path.Status == Enum.PathStatus.NoPath then
		-- 目标不可达，检查是否有部分路径
		local waypoints = path:GetWaypoints()
		if waypoints and #waypoints >= 2 then
			-- 有部分路径，返回PARTIAL状态（不是SUCCESS！）
			pathState.Waypoints = DeepCopyWaypoints(waypoints)
			pathState.Index = 2
			pathState.Status = PathStatus.PARTIAL
			pathState.LastTargetPos = targetPos
			pathState.LastRequestTime = tick()
			pathState.Retries = 0
			pathState.NearestReachablePoint = waypoints[#waypoints].Position
			DebugLog(string.format("⚠️ %s NoPath但有%d个路径点，标记为PARTIAL", unitId or "Unknown", #waypoints))
			return true
		end
	end

	-- 路径失败，尝试缩小半径重试
	if pathState.Retries < CONFIG.MAX_RETRY_COUNT then
		pathState.Retries = pathState.Retries + 1

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
				-- 清理旧path
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

-- ==================== 时间预算队列处理器 ====================

local function ProcessQueueWithTimeBudget()
	if #pathQueue == 0 then
		isProcessing = false
		return
	end

	isProcessing = true

	-- 动态时间预算
	local budgetMs = CONFIG.TIME_BUDGET_MS
	if #pathQueue > CONFIG.QUEUE_THRESHOLD_FOR_BOOST then
		budgetMs = CONFIG.TIME_BUDGET_MAX_MS
	end

	local budgetEndTime = tick() + (budgetMs / 1000)
	local processedCount = 0

	while #pathQueue > 0 and tick() < budgetEndTime do
		local request = table.remove(pathQueue, 1)

		-- 检查有效性
		if not request.unitModel or not request.unitModel.Parent then
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

	-- 队列还有剩余，下一帧继续
	if #pathQueue > 0 then
		task.defer(ProcessQueueWithTimeBudget)
	else
		isProcessing = false
	end
end

-- ==================== Blockcast障碍检测 ====================

--[[
使用Blockcast检测前方是否有障碍物
@param unitModel Model - 单位模型
@param targetPos Vector3 - 目标位置
@return boolean - true表示路径畅通，false表示有障碍
]]
local function IsPathClear(unitModel, targetPos)
	local root = unitModel:FindFirstChild("HumanoidRootPart") or unitModel.PrimaryPart
	if not root then return false end

	local startPos = root.Position
	local direction = targetPos - startPos
	local distance = direction.Magnitude

	if distance < 3 then return true end

	-- Blockcast检测盒：宽3, 高5, 深1
	local size = Vector3.new(3, 5, 1)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- 排除自己和所有兵种
	local filterList = {unitModel}
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		table.insert(filterList, unitsFolder)
	end
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	-- 构建检测方向（只在水平面）
	local cframe = CFrame.lookAt(startPos, Vector3.new(targetPos.X, startPos.Y, targetPos.Z))
	local detectDistance = math.max(1, distance - 2)

	local result = workspace:Blockcast(cframe, size, direction.Unit * detectDistance, rayParams)

	if result and result.Instance.CanCollide then
		return false
	end
	return true
end

-- ==================== 拥挤检测 ====================

--[[
检测单位周围是否有足够多的友军（用于拥挤豁免）
@param unitModel Model - 单位模型
@param moveData table - 所有行军单位数据
@return boolean - true表示周围拥挤
]]
local function IsInCrowdedArea(unitModel, moveData)
	local root = unitModel:FindFirstChild("HumanoidRootPart") or unitModel.PrimaryPart
	if not root then return false end

	local myPos = root.Position
	local nearbyCount = 0

	for otherUnit, otherData in pairs(moveData) do
		if otherUnit ~= unitModel and not otherData.Arrived then
			local otherRoot = otherUnit:FindFirstChild("HumanoidRootPart") or otherUnit.PrimaryPart
			if otherRoot then
				local dist = (otherRoot.Position - myPos).Magnitude
				if dist < CONFIG.CROWD_CHECK_RADIUS then
					nearbyCount = nearbyCount + 1
					if nearbyCount >= CONFIG.CROWD_THRESHOLD then
						return true
					end
				end
			end
		end
	end

	return false
end

-- ==================== 公共接口 ====================

--[[
异步请求路径
@param unitModel Model - 兵种模型
@param targetModel Model|BasePart - 目标
@param unitId string - 单位ID
@param callback function - 回调 function(success, pathState)
@return boolean - 是否成功入队
]]
function PathService.RequestPathAsync(unitModel, targetModel, unitId, callback)
	if not unitModel or not targetModel then
		if callback then
			pcall(function() callback(false, nil) end)
		end
		return false
	end

	local targetPos = GetModelPosition(targetModel)
	if not targetPos then
		if callback then
			pcall(function() callback(false, nil) end)
		end
		return false
	end

	-- 检查是否已在队列中（防止重复入队）
	for i, req in ipairs(pathQueue) do
		if req.unitModel == unitModel then
			req.targetPos = targetPos
			req.callback = callback
			return true
		end
	end

	local pathState = GetPathState(unitModel) or InitPathState(unitModel)
	pathState.Status = PathStatus.QUEUED

	table.insert(pathQueue, {
		unitModel = unitModel,
		targetPos = targetPos,
		unitId = unitId,
		callback = callback,
		queueTime = tick(),
	})

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

	-- 需要重建
	if pathState.Status == PathStatus.NEED_REPATH then
		ClearPathData(unitModel)
	end

	-- 复用现有路径
	if pathState.Status == PathStatus.SUCCESS and pathState.Waypoints and #pathState.Waypoints > 0 then
		local targetPos = GetModelPosition(targetModel)
		if targetPos and pathState.LastTargetPos then
			local distance = GetDistance3D(targetPos, pathState.LastTargetPos)
			if distance < CONFIG.TARGET_MOVE_THRESHOLD then
				return true
			end
		end
	end

	-- 检查冷却
	local currentTime = tick()
	if (currentTime - pathState.LastRequestTime) < CONFIG.PATH_RECALC_COOLDOWN then
		return pathState.Status == PathStatus.SUCCESS or pathState.Status == PathStatus.PARTIAL
	end

	local targetPos = GetModelPosition(targetModel)
	return BuildPathInternal(unitModel, targetPos, unitId)
end

--[[
获取下一个路径点
]]
function PathService.GetNextWaypoint(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then return nil end
	if pathState.Status ~= PathStatus.SUCCESS and pathState.Status ~= PathStatus.PARTIAL then
		return nil
	end
	if not pathState.Waypoints or pathState.Index > #pathState.Waypoints then
		return nil
	end
	return pathState.Waypoints[pathState.Index]
end

--[[
推进到下一个路径点
]]
function PathService.AdvancePath(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then return false end
	if pathState.Status ~= PathStatus.SUCCESS and pathState.Status ~= PathStatus.PARTIAL then
		return false
	end
	if not pathState.Waypoints then return false end

	pathState.Index = pathState.Index + 1
	return pathState.Index <= #pathState.Waypoints
end

--[[
获取路径状态
]]
function PathService.GetPathStatus(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then return PathStatus.IDLE end
	return pathState.Status
end

--[[
清理路径
⭐⭐ V5.0增强：同时清理activeMoves中的行军任务数据 ⭐⭐
]]
function PathService.ClearPath(unitModel)
	ClearPathData(unitModel)

	-- 从队列中移除
	for i = #pathQueue, 1, -1 do
		if pathQueue[i].unitModel == unitModel then
			table.remove(pathQueue, i)
			break
		end
	end

	-- ⭐⭐ V5.0关键修复：从所有activeMoves中移除该单位 ⭐⭐
	-- 这是防止行军和战斗MoveTo冲突的核心修复
	for moveId, moveTask in pairs(activeMoves) do
		if moveTask.moveData and moveTask.moveData[unitModel] then
			local data = moveTask.moveData[unitModel]

			-- 标记为已到达，停止后续处理
			data.Arrived = true

			-- 断开MoveToFinished监听
			if data.MoveConnection then
				data.MoveConnection:Disconnect()
				data.MoveConnection = nil
			end

			-- 销毁目标Part
			if data.TargetPart and data.TargetPart.Parent then
				data.TargetPart:Destroy()
			end

			-- 从moveData中移除
			moveTask.moveData[unitModel] = nil

			DebugLog(string.format("🛑 [V5.0] 从行军任务 %s 中移除单位", tostring(moveId)))
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
]]
function PathService.HasReachedWaypoint(unitModel, threshold)
	threshold = threshold or CONFIG.WAYPOINT_REACH_THRESHOLD

	local pathState = GetPathState(unitModel)
	if not pathState then return false end
	if pathState.Status ~= PathStatus.SUCCESS and pathState.Status ~= PathStatus.PARTIAL then
		return false
	end

	local currentWaypoint = pathState.Waypoints and pathState.Waypoints[pathState.Index]
	if not currentWaypoint then return false end

	local currentPos = GetModelPosition(unitModel)
	if not currentPos then return false end

	return GetHorizontalDistance(currentPos, currentWaypoint) < threshold
end

--[[
检查是否为Partial路径
]]
function PathService.IsPartialPath(unitModel)
	local pathState = GetPathState(unitModel)
	return pathState and pathState.Status == PathStatus.PARTIAL
end

--[[
获取最近可达点（仅PARTIAL路径有效）
]]
function PathService.GetNearestReachablePoint(unitModel)
	local pathState = GetPathState(unitModel)
	if pathState and pathState.Status == PathStatus.PARTIAL then
		return pathState.NearestReachablePoint
	end
	return nil
end

--[[
获取路径状态对象
]]
function PathService.GetPathState(unitModel)
	return pathStates[unitModel]
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

	local toClear = {}
	for unitModel, _ in pairs(pathStates) do
		local state = getUnitState(unitModel)
		if state and state.BattleId == battleId then
			table.insert(toClear, unitModel)
		end
	end

	for _, unitModel in ipairs(toClear) do
		ClearPathData(unitModel)
		pathStates[unitModel] = nil
	end
end

--[[
获取配置
]]
function PathService.GetConfig()
	return CONFIG
end

-- ==================== 批量移动（行军系统）====================

--[[
批量移动兵种到指定位置
支持slot站位系统，每个单位有自己的目标点

@param moveTargets table - {[unitModel] = CFrame}
@param callbacks table|function - {onUnitArrived, onAllSettled} 或单个回调函数
@return string|nil - moveId
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
				-- 卡住检测数据
				LastStuckCheckTime = tick(),
				LastStuckCheckPos = rootPart.Position,
				StuckCount = 0,
				LastRepathTime = 0,
				-- 距离追踪
				PrevDistanceToTarget = nil,
				-- V5.1新增：走错路检测
				WrongWayCount = 0,
				-- V5.1新增：周期性重寻路
				LastPeriodicRepathTime = tick(),
				-- V5.1新增：MoveToFinished失败计数
				MoveToFailCount = 0,
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

	DebugLog(string.format("[MoveUnitsToPositions] 开始移动 %d 个单位", totalCount))

	-- 分批发起寻路请求
	local BATCH_SIZE = 4
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
		if batchIndex > BATCH_SIZE then
			batchIndex = 1
			task.wait()
		end

		-- 请求路径
		data.PathRequested = true
		PathService.RequestPathAsync(unitInstance, data.TargetPart, unitId, function(success, pathState)
			data.PathRequested = false
			if data.Arrived then return end

			local humanoid = unitInstance:FindFirstChild("Humanoid")
			if not humanoid then return end

			if success and pathState and (pathState.Status == PathStatus.SUCCESS or pathState.Status == PathStatus.PARTIAL) then
				local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
				if nextWaypoint then
					humanoid:MoveTo(nextWaypoint)
				elseif pathState.Status == PathStatus.PARTIAL then
					humanoid:Move(Vector3.zero)
				else
					humanoid:MoveTo(data.TargetCFrame.Position)
				end
			else
				humanoid:Move(Vector3.zero)
				DebugLog(string.format("⚠️ [行军] %s 初始寻路失败", unitInstance.Name))
			end
		end)

		-- V5.2优化：不再依赖MoveToFinished来驱动中间路点，改用Heartbeat切角机制
		-- MoveToFinished只用于检测失败情况（reached=false）
		local humanoid = unitInstance:FindFirstChild("Humanoid")
		if humanoid then
			data.MoveConnection = humanoid.MoveToFinished:Connect(function(reached)
				if data.Arrived then return end

				local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
				if not rootPart or not rootPart.Parent then return end

				local currentPos = rootPart.Position
				local targetPos = data.TargetCFrame.Position
				local distanceXZ = GetHorizontalDistance(currentPos, targetPos)
				local arrivalThreshold = GameConfig.Campaign and GameConfig.Campaign.ArrivalThreshold or 8

				-- 检查是否到达最终目标
				if distanceXZ < arrivalThreshold then
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
					return
				end

				-- 只处理 reached=false 的情况（MoveTo超时或被阻挡）
				if not reached then
					local now = tick()
					local canRepath = (now - data.LastRepathTime) >= CONFIG.MARCH_REPATH_COOLDOWN

					data.MoveToFailCount = (data.MoveToFailCount or 0) + 1

					-- 连续失败达到阈值且冷却已过才触发重寻路
					if data.MoveToFailCount >= CONFIG.MARCH_MOVETO_FAIL_THRESHOLD and canRepath then
						DebugLog(string.format("⚠️ [行军] %s MoveToFinished连续失败%d次，重寻路",
							unitInstance.Name, data.MoveToFailCount))
						humanoid:Move(Vector3.zero)
						PathService.ClearPath(unitInstance)
						data.MoveToFailCount = 0
						data.LastRepathTime = now

						-- 延迟后重寻路
						local delay = math.random() * CONFIG.REPATH_RANDOM_DELAY_MAX
						task.delay(delay, function()
							if data.Arrived then return end
							data.PathRequested = true
							PathService.RequestPathAsync(unitInstance, data.TargetPart, unitInstance.Name, function(success, pathState)
								data.PathRequested = false
								local humanoid = unitInstance:FindFirstChild("Humanoid")
								if success and pathState and (pathState.Status == PathStatus.SUCCESS or pathState.Status == PathStatus.PARTIAL) and humanoid then
									local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
									if nextWaypoint then
										humanoid:MoveTo(nextWaypoint)
									end
								elseif humanoid then
									humanoid:Move(Vector3.zero)
								end
							end)
						end)
					end
				else
					-- reached=true，重置失败计数
					data.MoveToFailCount = 0
				end
			end)
		end
	end

	-- 定期检查：卡住检测、到达检测、超时
	local checkConnection
	local lastCheckTime = tick()
	local moveTimeout = GameConfig.Campaign and GameConfig.Campaign.MoveTimeout or 30

	checkConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		-- V5.2优化：提高检测频率到0.05秒，确保切角及时
		if now - lastCheckTime < 0.05 then return end
		lastCheckTime = now

		local allDone = true

		for unitInstance, data in pairs(moveData) do
			if not data.Arrived then
				allDone = false

				-- 检查实例有效性
				if not unitInstance or not unitInstance.Parent then
					data.Arrived = true
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

				local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
				if not rootPart or not rootPart.Parent then continue end

				local humanoid = unitInstance:FindFirstChild("Humanoid")
				if not humanoid then continue end

				local currentPos = rootPart.Position
				local targetPos = data.TargetCFrame.Position
				local distanceXZ = GetHorizontalDistance(currentPos, targetPos)
				local arrivalThreshold = GameConfig.Campaign and GameConfig.Campaign.ArrivalThreshold or 8

				-- ==================== V5.2核心优化：丝滑切角寻路 ====================

				-- 获取路径状态
				local pathStatus = PathService.GetPathStatus(unitInstance)

				-- 如果有有效路径，检查是否到达了"当前路点"(Waypoints[index])
				if pathStatus == PathStatus.SUCCESS or pathStatus == PathStatus.PARTIAL then
					local nextWaypoint = PathService.GetNextWaypoint(unitInstance)

					if nextWaypoint then
						local distToWaypoint = GetHorizontalDistance(currentPos, nextWaypoint)

						-- [关键优化] 切角阈值：如果是中间点，距离 < 5 就切向下一个点
						-- 如果是最后一个点，还是需要精确到达
						local pathState = GetPathState(unitInstance)
						local isFinalPoint = pathState and (pathState.Index >= #pathState.Waypoints)
						local reachThreshold = isFinalPoint and 1.5 or 5.0  -- 中间点放宽到 5 studs

						if distToWaypoint < reachThreshold then
							-- 到达当前路点，推进到下一个
							if PathService.AdvancePath(unitInstance) then
								local newTarget = PathService.GetNextWaypoint(unitInstance)
								if newTarget then
									humanoid:MoveTo(newTarget)  -- 立即前往下一个，不刹车
								end
							end
						end

						-- 持续刷新 MoveTo，防止 MoveTo 超时（默认8秒）导致发呆
						-- 每0.5秒强制MoveTo一次当前目标，确保单位持续移动
						local lastMoveToTime = data.LastMoveToUpdateTime or 0
						if now - lastMoveToTime > 0.5 then
							humanoid:MoveTo(nextWaypoint)
							data.LastMoveToUpdateTime = now
						end
					end
				end
				-- ==============================================================

				-- 到达最终目标检测
				if distanceXZ < arrivalThreshold then
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
					continue
				end

				-- 卡住检测（保持原有逻辑，但频率已降低）
				if now - data.LastStuckCheckTime >= CONFIG.MARCH_STUCK_CHECK_INTERVAL then
					data.LastStuckCheckTime = now

					-- 跳过正在等待寻路的单位
					if data.PathRequested then
						data.StuckCount = 0
						continue
					end

					-- 基于WalkSpeed的位移检测
					local humanoid = unitInstance:FindFirstChild("Humanoid")
					local walkSpeed = humanoid and humanoid.WalkSpeed or 16
					local lastPos = data.LastStuckCheckPos
					local actualDistance = GetHorizontalDistance(currentPos, lastPos)
					data.LastStuckCheckPos = currentPos

					-- 预期位移 = WalkSpeed * 时间 * 容差
					local expectedDistance = walkSpeed * CONFIG.MARCH_STUCK_CHECK_INTERVAL * 0.5
					local minDistThreshold = math.max(CONFIG.MARCH_STUCK_MIN_VELOCITY, expectedDistance * 0.3)

					-- 距离变化追踪
					local prevDist = data.PrevDistanceToTarget or distanceXZ
					local isProgressing = distanceXZ < (prevDist - 0.1)
					data.PrevDistanceToTarget = distanceXZ

					-- 重寻路冷却检查
					local canRepath = (now - data.LastRepathTime) >= CONFIG.MARCH_REPATH_COOLDOWN

					-- 卡住判定
					local isStuck = actualDistance < minDistThreshold
						and not isProgressing
						and distanceXZ > 5
						and canRepath

					if isStuck then
						-- 拥挤豁免
						if IsInCrowdedArea(unitInstance, moveData) then
							data.StuckCount = 0
							DebugLog(string.format("⚠️ [行军] %s 疑似卡住但周围拥挤，豁免", unitInstance.Name))
						else
							data.StuckCount = data.StuckCount + 1

							if data.StuckCount >= CONFIG.MARCH_STUCK_COUNT_THRESHOLD then
								DebugLog(string.format("🚀 [行军] %s 确认卡住，直接瞬移到目的地", unitInstance.Name))
								data.StuckCount = 0
								data.LastRepathTime = now

								-- 停止移动
								if humanoid then
									humanoid:Move(Vector3.zero)
								end
								PathService.ClearPath(unitInstance)

								-- 直接瞬移到目的地
								local targetPos = data.TargetCFrame.Position
								pcall(function()
									rootPart.CFrame = CFrame.new(targetPos.X, rootPart.Position.Y, targetPos.Z)
								end)

								-- 标记为到达
								data.Arrived = true
								if data.MoveConnection then
									data.MoveConnection:Disconnect()
									data.MoveConnection = nil
								end
								if data.TargetPart and data.TargetPart.Parent then
									data.TargetPart:Destroy()
								end
								table.insert(arrivedList, unitInstance)

								if onUnitArrived then
									pcall(function() onUnitArrived(unitInstance, "Teleported") end)
								end
							end
						end
					else
						if actualDistance > minDistThreshold then
							data.StuckCount = 0
						end
					end

					-- ==================== V5.3新增：走错路检测修正 ====================
					-- 距离连续增加说明可能走错方向
					-- [修复] 增加 distanceXZ > 15 判断，忽略终点附近的回退
					if distanceXZ > 15 and distanceXZ > prevDist + CONFIG.MARCH_WRONG_WAY_DISTANCE then
						data.WrongWayCount = (data.WrongWayCount or 0) + 1
						if data.WrongWayCount >= CONFIG.MARCH_WRONG_WAY_THRESHOLD and canRepath then
							DebugLog(string.format("🚀 [行军] %s 走错路(距离%.1f→%.1f)，直接瞬移到目的地",
								unitInstance.Name, prevDist, distanceXZ))
							data.WrongWayCount = 0
							data.LastRepathTime = now
							PathService.ClearPath(unitInstance)

							-- 停止移动
							if humanoid then
								humanoid:Move(Vector3.zero)
							end

							-- 直接瞬移到目的地
							local targetPos = data.TargetCFrame.Position
							pcall(function()
								rootPart.CFrame = CFrame.new(targetPos.X, rootPart.Position.Y, targetPos.Z)
							end)

							-- 标记为到达
							data.Arrived = true
							if data.MoveConnection then
								data.MoveConnection:Disconnect()
								data.MoveConnection = nil
							end
							if data.TargetPart and data.TargetPart.Parent then
								data.TargetPart:Destroy()
							end
							table.insert(arrivedList, unitInstance)

							if onUnitArrived then
								pcall(function() onUnitArrived(unitInstance, "Teleported") end)
							end
						end
					else
						data.WrongWayCount = 0
					end
					-- ==================== 走错路检测结束 ====================

					-- ==================== V5.1新增：周期性重寻路兜底（改为瞬移）====================
					local timeSinceStart = now - data.StartTime
					local lastPeriodicRepath = data.LastPeriodicRepathTime or data.StartTime
					if timeSinceStart > 5 and (now - lastPeriodicRepath) > CONFIG.MARCH_PERIODIC_REPATH_DELAY then
						if distanceXZ > CONFIG.MARCH_PERIODIC_MIN_DISTANCE and canRepath then
							DebugLog(string.format("🚀 [行军] %s 周期性检测仍未到达(距离=%.1f)，直接瞬移到目的地", unitInstance.Name, distanceXZ))
							data.LastPeriodicRepathTime = now
							data.LastRepathTime = now
							PathService.ClearPath(unitInstance)

							-- 停止移动
							if humanoid then
								humanoid:Move(Vector3.zero)
							end

							-- 直接瞬移到目的地
							local targetPos = data.TargetCFrame.Position
							pcall(function()
								rootPart.CFrame = CFrame.new(targetPos.X, rootPart.Position.Y, targetPos.Z)
							end)

							-- 标记为到达
							data.Arrived = true
							if data.MoveConnection then
								data.MoveConnection:Disconnect()
								data.MoveConnection = nil
							end
							if data.TargetPart and data.TargetPart.Parent then
								data.TargetPart:Destroy()
							end
							table.insert(arrivedList, unitInstance)

							if onUnitArrived then
								pcall(function() onUnitArrived(unitInstance, "Teleported") end)
							end
						end
					end
					-- ==================== 周期性检测结束 ====================
				end

				-- 超时检测
				if now - data.StartTime > moveTimeout then
					data.Arrived = true
					if data.MoveConnection then
						data.MoveConnection:Disconnect()
						data.MoveConnection = nil
					end
					PathService.ClearPath(unitInstance)
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end

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

		-- 所有单位完成
		if allDone then
			checkConnection:Disconnect()

			-- ⭐⭐ V5.4关键修复：在删除activeMoves前，清理所有单位的MoveConnection ⭐⭐
			-- 之前只是 activeMoves[moveId] = nil，但各单位的 MoveConnection 还在监听
			-- 这会导致延迟的 task.delay 回调在战斗开始后仍然发送 MoveTo 指令
			for unitInstance, data in pairs(moveData) do
				if data.MoveConnection then
					data.MoveConnection:Disconnect()
					data.MoveConnection = nil
				end
				-- 销毁目标Part（如果还没销毁）
				if data.TargetPart and data.TargetPart.Parent then
					data.TargetPart:Destroy()
				end
			end

			activeMoves[moveId] = nil

			DebugLog(string.format("[MoveUnitsToPositions] 完成 - 到达:%d, 超时:%d, 失败:%d",
				#arrivedList, #timedOutList, #failedList))

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
			data.MoveConnection = nil
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

-- ==================== 调试接口 ====================

function PathService.GetPerformanceStats()
	return {
		QueuedRequests = #pathQueue,
		ActiveMoveTasks = 0,
		TotalUnitsMoving = 0,
	}
end

function PathService.SetDebugOptions(showPath, showLogs)
	if showLogs ~= nil then
		CONFIG.DEBUG_PATH_LOGS = showLogs
	end
end

return PathService