--[[
脚本名称: ClientPathService
脚本类型: ModuleScript (客户端系统)
脚本位置: StarterPlayer/StarterPlayerScripts/ClientAI/ClientPathService
版本: V4.0 - 客户端AI迁移专用
]]

--[[
客户端寻路服务
职责:
1. 为客户端AI提供寻路能力
2. 管理单位的移动到目标位置
3. 处理路径计算、路点跟随、障碍物检测
4. 轻量化设计，减少客户端负载

V4.0设计要点:
- 与服务端PathService功能对齐
- 简化队列和批量处理逻辑（客户端只处理本地单位）
- 保留核心寻路算法
- 移除行军专用逻辑（客户端只管理战斗移动）
]]

local ClientPathService = {}

-- ==================== 依赖服务 ====================

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
	PATH_RECALC_COOLDOWN = 0.5,

	-- 目标移动阈值（studs）- 目标位置变化超过此值才重新寻路
	TARGET_MOVE_THRESHOLD = 10,

	-- Waypoint到达阈值（studs）
	WAYPOINT_REACH_THRESHOLD = 2,

	-- Agent默认参数
	DEFAULT_AGENT_RADIUS = 2,
	DEFAULT_AGENT_HEIGHT = 5,
	DEFAULT_AGENT_CAN_JUMP = false,

	-- 调试选项
	DEBUG_PATH_LOGS = false,

	-- 同时进行的ComputeAsync数量上限（避免大量单位时阻塞/卡帧）
	MAX_CONCURRENT_COMPUTES = 16,
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
	PARTIAL = "Partial", -- 目标不可达但有最近可达点
	FAILED = "Failed",
	BLOCKED = "Blocked",
	NEED_REPATH = "NeedRepath",
}

ClientPathService.PathStatus = PathStatus

-- ==================== 寻路请求结果枚举 ====================

local PathRequestResult = {
	INVALID = "Invalid",
	REUSED = "Reused",       -- 复用现有路径（目标未明显变化）
	QUEUED = "Queued",       -- 已入队等待计算
	COMPUTING = "Computing", -- 正在计算中
	COOLDOWN = "Cooldown",   -- 冷却中，未入队
}

ClientPathService.PathRequestResult = PathRequestResult

-- ==================== 私有变量 ====================

local pathStates = {}      -- [unitModel] = PathState
local pathQueue = {}       -- FIFO队列: requestTable
local queuedRequests = {}  -- [unitModel] = requestTable
local activeComputes = 0
local processScheduled = false
local generation = 0

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_PATH_LOGS then
		print(GameConfig.LOG_PREFIX, "[ClientPathService]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[ClientPathService]", ...)
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

--[[
V4.1修复：跳过"初始回头路点"
PathfindingService在NavMesh刚更新/起点靠近不可走区域边缘时，首个路点可能会落在目标反方向，
表现为单位先掉头走一段再折返。
该逻辑只在路径起始阶段(索引<=5)尝试跳过，避免影响正常绕障路径。

V5.11修复（增强）：
- 放宽角度阈值：dot >= 0.1 改为跳过侧向偏离的路点（>84°）
- 原来是 dot >= -0.2（只跳过>102°），太宽松了，导致V字型行军
]]
local function ShouldSkipInitialBacktrackWaypoint(startPos, waypointPos, targetPos)
	-- 只做XZ平面判断，忽略高度差
	local toTarget = Vector3.new(targetPos.X - startPos.X, 0, targetPos.Z - startPos.Z)
	local toWaypoint = Vector3.new(waypointPos.X - startPos.X, 0, waypointPos.Z - startPos.Z)

	if toTarget.Magnitude < 0.05 or toWaypoint.Magnitude < 0.05 then
		return false
	end

	-- V5.11修复：dot < 0.1 表示路点偏离目标方向超过约84°
	-- 原来是 dot >= -0.2（只跳过>102°），太宽松了，导致V字型行军
	local dot = toTarget.Unit:Dot(toWaypoint.Unit)
	if dot >= 0.1 then
		return false
	end

	-- 路点比当前位置"更远离目标"且步长不大时，认为是NavMesh投影导致的回头路点
	local startDist = GetHorizontalDistance(startPos, targetPos)
	local waypointDist = GetHorizontalDistance(waypointPos, targetPos)
	local stepDist = GetHorizontalDistance(startPos, waypointPos)

	-- V5.11修复：保留V5.10的宽松步长阈值，但结合更严格的角度检查
	local maxStepDist = 35
	if startDist <= 60 then
		maxStepDist = 80
	end

	return stepDist <= maxStepDist and (waypointDist - startDist) >= 1
end

-- ==================== 动态Agent尺寸计算 ====================

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

	-- 综合计算：footprint转换为studs（每格约4 studs）
	local footprintRadius = footprint * 2

	agentRadius = math.max(CONFIG.DEFAULT_AGENT_RADIUS, footprintRadius, modelRadius)
	agentHeight = math.max(CONFIG.DEFAULT_AGENT_HEIGHT, modelHeight)

	-- 限制最大值
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
		BlockedConnection = nil,
		MoveConnection = nil,
		CurrentWaypointIndex = nil, -- V4.2新增：记录当前正在前往的路点索引
		RequestId = 0, -- 异步请求ID（用于丢弃过期结果）
	}
	pathStates[unitModel] = pathState
	return pathState
end

local function GetPathState(unitModel)
	return pathStates[unitModel]
end

-- ==================== 异步寻路队列（核心修复：避免Heartbeat里ComputeAsync导致串行卡顿） ====================

local function RemoveQueuedRequest(unitModel)
	local req = queuedRequests[unitModel]
	if not req then
		return
	end

	queuedRequests[unitModel] = nil
	for i = #pathQueue, 1, -1 do
		if pathQueue[i] == req then
			table.remove(pathQueue, i)
		end
	end
end

local function BuildPathForRequest(request)
	-- generation变化（ClearAll）后直接丢弃旧请求，避免重新InitPathState导致“死灰复燃”
	if request.gen ~= generation then
		return
	end

	local unitModel = request.unitModel
	if not unitModel or not unitModel.Parent then
		return
	end

	local pathState = GetPathState(unitModel)
	if not pathState then
		return
	end

	-- 请求已过期（ClearPath/新请求）
	if (pathState.RequestId or 0) ~= request.requestId then
		return
	end

	local targetPos = request.targetPos
	local startPos = GetModelPosition(unitModel)
	if not startPos or not targetPos then
		pathState.Status = PathStatus.FAILED
		return
	end

	-- 清理旧路径（不调用ClearPath，避免额外MoveTo干扰）
	if pathState.Path then
		if pathState.BlockedConnection then
			pathState.BlockedConnection:Disconnect()
			pathState.BlockedConnection = nil
		end
		pcall(function() pathState.Path:Destroy() end)
		pathState.Path = nil
	end

	-- 异步重寻路时，旧MoveToFinished回调可能在新路径落地后推进Index，污染新路径状态
	if pathState.MoveConnection then
		pcall(function()
			pathState.MoveConnection:Disconnect()
		end)
		pathState.MoveConnection = nil
	end
	pathState.CurrentWaypointIndex = nil

	-- 动态计算Agent参数
	local agentRadius, agentHeight = CalculateAgentSize(unitModel)
	local waypointSpacing = math.max(2, agentRadius)

	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius,
		AgentHeight = agentHeight,
		AgentCanJump = CONFIG.DEFAULT_AGENT_CAN_JUMP,
		WaypointSpacing = waypointSpacing,
	})

	pathState.Path = path
	pathState.Status = PathStatus.COMPUTING

	local blockedConn
	blockedConn = path.Blocked:Connect(function(blockedWaypointIndex)
		-- 仅当前请求生效
		if request.gen ~= generation then
			return
		end
		if (pathState.RequestId or 0) ~= request.requestId then
			return
		end
		if blockedWaypointIndex >= (pathState.Index or 0) then
			pathState.Status = PathStatus.NEED_REPATH
			pathState.LastRequestTime = 0 -- 允许立即重算
			DebugLog(string.format("%s 路径被阻挡", unitModel.Name))
		end
	end)
	pathState.BlockedConnection = blockedConn

	local success, errorMsg = pcall(function()
		path:ComputeAsync(startPos, targetPos)
	end)

	-- 请求过期/单位已不存在：清理并退出
	if request.gen ~= generation or not unitModel.Parent or (pathState.RequestId or 0) ~= request.requestId then
		pcall(function()
			if blockedConn then blockedConn:Disconnect() end
			path:Destroy()
		end)
		if pathState.BlockedConnection == blockedConn then
			pathState.BlockedConnection = nil
		end
		if pathState.Path == path then
			pathState.Path = nil
		end
		return
	end

	if not success then
		pathState.Status = PathStatus.FAILED
		pathState.Waypoints = nil
		pathState.Index = 0
		pathState.CurrentWaypointIndex = nil
		WarnLog(string.format("%s ComputeAsync失败: %s", unitModel.Name, tostring(errorMsg)))
		pcall(function()
			if blockedConn then blockedConn:Disconnect() end
			path:Destroy()
		end)
		if pathState.BlockedConnection == blockedConn then
			pathState.BlockedConnection = nil
		end
		if pathState.Path == path then
			pathState.Path = nil
		end
		return
	end

	local status = path.Status
	local waypoints = path:GetWaypoints()

	if (status == Enum.PathStatus.Success or status == Enum.PathStatus.NoPath) and waypoints and #waypoints >= 2 then
		pathState.Waypoints = DeepCopyWaypoints(waypoints)
		pathState.Index = 2 -- 跳过起点
		pathState.CurrentWaypointIndex = nil
		pathState.LastTargetPos = targetPos
		pathState.Status = (status == Enum.PathStatus.Success) and PathStatus.SUCCESS or PathStatus.PARTIAL

		-- 跳过初始回头路点（增强版本，避免V字型/掉头）
		local skipped = 0
		while pathState.Waypoints
			and pathState.Index <= #pathState.Waypoints
			and pathState.Index <= 6
			and skipped < 4 do
			local wp = pathState.Waypoints[pathState.Index]
			if wp and ShouldSkipInitialBacktrackWaypoint(startPos, wp, targetPos) then
				pathState.Index += 1
				skipped += 1
			else
				break
			end
		end
		if pathState.Waypoints and pathState.Index > #pathState.Waypoints then
			pathState.Status = PathStatus.FAILED
			pathState.Waypoints = nil
			pathState.Index = 0
			return
		end

		DebugLog(string.format("%s 寻路完成: %s, waypoints=%d", unitModel.Name, tostring(pathState.Status), #waypoints))
		return
	end

	pathState.Status = PathStatus.FAILED
	pathState.Waypoints = nil
	pathState.Index = 0
	DebugLog(string.format("%s 寻路失败: Status=%s", unitModel.Name, tostring(status)))
	pcall(function()
		if blockedConn then blockedConn:Disconnect() end
		path:Destroy()
	end)
	if pathState.BlockedConnection == blockedConn then
		pathState.BlockedConnection = nil
	end
	if pathState.Path == path then
		pathState.Path = nil
	end
end

local ScheduleProcessQueue

local function ProcessQueue()
	while activeComputes < (CONFIG.MAX_CONCURRENT_COMPUTES or 8) and #pathQueue > 0 do
		local request = table.remove(pathQueue, 1)
		if not request or request.gen ~= generation or not request.unitModel then
			continue
		end

		-- 如果该单位的排队请求已被更新，跳过旧对象
		local latest = queuedRequests[request.unitModel]
		if latest ~= request then
			continue
		end

		queuedRequests[request.unitModel] = nil
		activeComputes += 1

		task.spawn(function()
			local ok, err = pcall(function()
				BuildPathForRequest(request)
			end)
			if not ok then
				WarnLog("异步寻路线程异常:", err)
			end
			activeComputes = math.max(0, activeComputes - 1)
			if ScheduleProcessQueue then
				ScheduleProcessQueue()
			end
		end)
	end
end

ScheduleProcessQueue = function()
	if processScheduled then
		return
	end
	processScheduled = true
	task.defer(function()
		processScheduled = false
		ProcessQueue()
	end)
end

-- ==================== 公共接口 ====================

--[[
清理单位的路径数据（供外部调用）
@param unitModel Model - 单位模型
]]
function ClientPathService.ClearPath(unitModel)
	local pathState = pathStates[unitModel]
	if not pathState then return end

	-- 取消队列中的请求，并使正在计算的结果失效
	RemoveQueuedRequest(unitModel)
	pathState.RequestId = (pathState.RequestId or 0) + 1

	-- 断开事件连接
	if pathState.BlockedConnection then
		pathState.BlockedConnection:Disconnect()
		pathState.BlockedConnection = nil
	end

	if pathState.MoveConnection then
		pathState.MoveConnection:Disconnect()
		pathState.MoveConnection = nil
	end

	-- 停止移动
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.new(0, 0, 0))

		-- V4.12修复：不使用MoveTo到当前位置，避免单位原地站住
		-- 直接清除速度即可
		local rootPart = unitModel:FindFirstChild("HumanoidRootPart") or unitModel.PrimaryPart
		if rootPart then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
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
	pathState.CurrentWaypointIndex = nil  -- V4.2新增：清理当前路点索引标记
end

--[[
请求寻路到目标位置
@param unitModel Model - 单位模型
@param targetPos Vector3 - 目标位置
@return string - PathRequestResult
]]
function ClientPathService.RequestPath(unitModel, targetPos)
	if not unitModel or not targetPos then
		return PathRequestResult.INVALID
	end

	local pathState = GetPathState(unitModel) or InitPathState(unitModel)

	-- 正在计算/排队时不重复入队（避免刷爆ComputeAsync）
	if pathState.Status == PathStatus.COMPUTING then
		return PathRequestResult.COMPUTING
	end
	if pathState.Status == PathStatus.QUEUED then
		local req = queuedRequests[unitModel]
		if req then
			req.targetPos = targetPos
		end
		return PathRequestResult.QUEUED
	end

	-- 已有有效路径且目标未明显移动：直接复用
	-- 注意：如果路径已走完（Index > #Waypoints），不能复用，否则上层会以为“有路径”但其实没有可跟随的路点
	if (pathState.Status == PathStatus.SUCCESS or pathState.Status == PathStatus.PARTIAL)
		and pathState.LastTargetPos
		and pathState.Waypoints
		and pathState.Index
		and pathState.Index <= #pathState.Waypoints then
		local distance = GetHorizontalDistance(pathState.LastTargetPos, targetPos)
		if distance < CONFIG.TARGET_MOVE_THRESHOLD and not ClientPathService.NeedRepath(unitModel) then
			-- V4.11：追逐移动目标时，允许复用路径但更新终点路点，避免“追旧点”
			if pathState.Status == PathStatus.SUCCESS and pathState.Waypoints and #pathState.Waypoints >= 2 then
				pathState.Waypoints[#pathState.Waypoints] = targetPos
			end
			return PathRequestResult.REUSED
		end
	end

	-- 冷却检查
	local now = tick()
	if (now - (pathState.LastRequestTime or 0)) < CONFIG.PATH_RECALC_COOLDOWN then
		return PathRequestResult.COOLDOWN
	end

	-- 入队异步计算
	pathState.LastRequestTime = now
	pathState.RequestId = (pathState.RequestId or 0) + 1
	pathState.Status = PathStatus.QUEUED

	local req = queuedRequests[unitModel]
	if not req then
		req = {
			unitModel = unitModel,
			requestId = pathState.RequestId,
			targetPos = targetPos,
			queueTime = now,
			gen = generation,
		}
		queuedRequests[unitModel] = req
		table.insert(pathQueue, req)
	else
		req.requestId = pathState.RequestId
		req.targetPos = targetPos
		req.queueTime = now
		req.gen = generation
	end

	ScheduleProcessQueue()
	return PathRequestResult.QUEUED
end

--[[
构建路径（内部核心逻辑）
@param unitModel Model - 单位模型
@param targetPos Vector3 - 目标位置
@return boolean - 是否成功
]]
function ClientPathService.BuildPath(unitModel, targetPos)
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

	-- 同BuildPathForRequest：避免重寻路时旧MoveToFinished回调污染新路径索引
	if pathState.MoveConnection then
		pcall(function()
			pathState.MoveConnection:Disconnect()
		end)
		pathState.MoveConnection = nil
	end
	pathState.CurrentWaypointIndex = nil

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
			DebugLog(string.format("%s 路径被阻挡", unitModel.Name))
		end
	end)

	-- 计算路径
	local success, errorMsg = pcall(function()
		path:ComputeAsync(startPos, targetPos)
	end)

	if not success then
		pathState.Status = PathStatus.FAILED
		WarnLog(string.format("%s ComputeAsync失败: %s", unitModel.Name, tostring(errorMsg)))
		return false
	end

	-- 处理路径结果
	if path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		if waypoints and #waypoints >= 2 then
			pathState.Waypoints = DeepCopyWaypoints(waypoints)
			pathState.Index = 2  -- 跳过起点
			pathState.CurrentWaypointIndex = nil  -- V4.2新增：清理路点索引标记，确保新路径会正确执行
			pathState.Status = PathStatus.SUCCESS

			-- V5.10加固：跳过初始“回头路点”（扩大检查窗口，覆盖更远的投影回头路点）
			local skipped = 0
			while pathState.Waypoints
				and pathState.Index <= #pathState.Waypoints
				and pathState.Index <= 6
				and skipped < 4 do
				local wp = pathState.Waypoints[pathState.Index]
				if wp and ShouldSkipInitialBacktrackWaypoint(startPos, wp, targetPos) then
					pathState.Index += 1
					skipped += 1
				else
					break
				end
			end
			if skipped > 0 then
				DebugLog(string.format("%s 跳过初始回头路点: %d", unitModel.Name, skipped))
			end
			-- 如果跳过后已经没有可用路点，视为失败，交给上层回退到直线移动
			if not pathState.Waypoints or pathState.Index > #pathState.Waypoints then
				pathState.Status = PathStatus.FAILED
				return false
			end

			DebugLog(string.format("%s 寻路成功: %d waypoints", unitModel.Name, #waypoints))
			return true
		end
	end

	pathState.Status = PathStatus.FAILED
	WarnLog(string.format("%s 寻路失败: Status=%s", unitModel.Name, tostring(path.Status)))
	return false
end

--[[
移动到目标位置（一次性移动）
@param unitModel Model - 单位模型
@param targetPos Vector3 - 目标位置
@param onReached function - 到达回调
@param onFailed function - 失败回调
]]
function ClientPathService.MoveToPosition(unitModel, targetPos, onReached, onFailed)
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid then
		if onFailed then onFailed("No Humanoid") end
		return
	end

	-- 请求寻路
	local result = ClientPathService.RequestPath(unitModel, targetPos)
	if result == PathRequestResult.INVALID then
		if onFailed then onFailed("Invalid Target") end
		return
	end

	-- 异步等待路径完成（该接口外部暂无使用，保持可用性）
	local startTime = tick()
	local timeout = 3
	task.spawn(function()
		while tick() - startTime < timeout do
			local status = ClientPathService.GetPathStatus(unitModel)
			if status == PathStatus.SUCCESS or status == PathStatus.PARTIAL then
				ClientPathService.FollowPath(unitModel, onReached, onFailed)
				return
			elseif status == PathStatus.FAILED then
				if onFailed then onFailed("No Valid Path") end
				return
			end
			task.wait(0.03)
		end
		if onFailed then onFailed("Path Timeout") end
	end)
end

--[[
跟随当前路径（供MoveToPosition和AI循环调用）
@param unitModel Model - 单位模型
@param onReached function - 到达回调
@param onFailed function - 失败回调
]]
function ClientPathService.FollowPath(unitModel, onReached, onFailed)
	local pathState = GetPathState(unitModel)
	if not pathState or not pathState.Waypoints or pathState.Index > #pathState.Waypoints then
		if onFailed then onFailed("No Waypoints") end
		return
	end

	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid then
		if onFailed then onFailed("No Humanoid") end
		return
	end

	-- 获取当前目标路点
	local currentWaypoint = pathState.Waypoints[pathState.Index]
	if not currentWaypoint then
		if onReached then onReached() end
		return
	end

	-- ==================== V4.2修复：防止路点索引死锁 ====================
	-- 如果当前正在走向同一个路点（通过索引比较），且连接还在，则什么都不做，直接返回
	-- 避免高频调用导致 MoveToFinished 事件被反复断开，导致永远无法前进到下一个路点
	if pathState.MoveConnection and pathState.CurrentWaypointIndex == pathState.Index then
		return
	end

	-- 记录当前正在前往的路点索引（用于比对）
	pathState.CurrentWaypointIndex = pathState.Index
	-- ==================== 修复结束 ====================

	-- 清理旧的Move连接
	if pathState.MoveConnection then
		pathState.MoveConnection:Disconnect()
		pathState.MoveConnection = nil
	end

	-- 移动到当前路点
	humanoid:MoveTo(currentWaypoint)

	-- 监听MoveToFinished
	pathState.MoveConnection = humanoid.MoveToFinished:Connect(function(reached)
		-- 只有当连接匹配时才处理（防止异步冲突）
		if not pathState.MoveConnection then return end

		-- ==================== V4.3修复：MoveTo控制权竞态 ====================
		-- 校验：当前位置是否真的接近目标路点
		-- 如果不接近，说明这个MoveToFinished是被其他MoveTo触发的（比如ClientUnitAI的直线MoveTo）
		-- 此时应该忽略这次回调，但必须重新发起MoveTo到当前路点，否则单位会卡住
		local unitPos = GetModelPosition(unitModel)
		if unitPos and currentWaypoint then
			local distanceToWaypoint = GetDistance3D(unitPos, currentWaypoint)
			-- 如果距离超过阈值的2倍，说明这不是到达当前路点的回调
			if distanceToWaypoint > CONFIG.WAYPOINT_REACH_THRESHOLD * 2 then
				DebugLog(string.format("%s MoveToFinished被误触发: 距离路点%.1f, 重新MoveTo",
					unitModel.Name, distanceToWaypoint))
				-- 关键修复：重新发起MoveTo到当前路点，否则单位会卡住
				humanoid:MoveTo(currentWaypoint)
				-- 保留连接，等待下次MoveToFinished
				return
			end
		end
		-- ==================== 修复结束 ====================

		pathState.MoveConnection:Disconnect()
		pathState.MoveConnection = nil
		pathState.CurrentWaypointIndex = nil  -- 清除当前目标索引标记

		if reached then
			-- 到达当前路点，前进到下一个
			pathState.Index = pathState.Index + 1
			if pathState.Index <= #pathState.Waypoints then
				-- 还有更多路点，继续移动
				ClientPathService.FollowPath(unitModel, onReached, onFailed)
			else
				-- 所有路点完成
				if onReached then onReached() end
			end
		else
			-- 未能到达路点
			if onFailed then onFailed("MoveToFinished Failed") end
		end
	end)
end

--[[
获取当前路径状态
@param unitModel Model - 单位模型
@return string - 路径状态
]]
function ClientPathService.GetPathStatus(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then
		return PathStatus.IDLE
	end

	-- V4.11：避免“路径状态Success/Partial但路点已走完”导致外部以为还能FollowPath，实际无路点可走而发呆
	if (pathState.Status == PathStatus.SUCCESS or pathState.Status == PathStatus.PARTIAL) then
		if not pathState.Waypoints
			or not pathState.Index
			or pathState.Index <= 0
			or pathState.Index > #pathState.Waypoints then
			return PathStatus.NEED_REPATH
		end
	end

	return pathState.Status
end

--[[
V5.0新增：获取路径状态对象（供ClientMarchService使用）
@param unitModel Model - 单位模型
@return table|nil - 路径状态对象
]]
function ClientPathService.GetPathState(unitModel)
	return GetPathState(unitModel)
end

--[[
仅清理MoveToFinished连接（不清理路径/路点）
用途：当外部采用Heartbeat驱动MoveTo（如行军/战斗切角）时，避免残留MoveToFinished回调推进Index造成竞态
@param unitModel Model - 单位模型
]]
function ClientPathService.ClearMoveConnection(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then
		return
	end

	if pathState.MoveConnection then
		pcall(function()
			pathState.MoveConnection:Disconnect()
		end)
		pathState.MoveConnection = nil
	end

	pathState.CurrentWaypointIndex = nil
end

--[[
V4.11：Heartbeat驱动切角 + MoveTo刷新（供ClientUnitAI/ClientMarchService复用）
用途：减少MoveToFinished竞态、避免怼墙/追旧点/走完路点后发呆
@param unitModel Model - 单位模型
@param opts table|nil
  - humanoid Humanoid|nil           传入可减少FindFirstChild开销
  - currentPos Vector3|nil          当前坐标（XZ距离计算用）
  - now number|nil                  默认tick()
  - lastMoveToUpdateTime number|nil 上次MoveTo时间（用于节流/刷新），默认0
  - refreshInterval number|nil      默认0.5
  - cornerCutThreshold number|nil   中间路点切角阈值，默认5.0
  - finalReachThreshold number|nil  终点路点到达阈值，默认1.5
  - mapWaypoint function|nil        function(rawWaypointPos)->Vector3，用于队形偏移等
  - disconnectMoveConnection boolean|nil 默认true：断开残留MoveToFinished连接，避免Index被回调推进
@return table result
  - ok boolean
  - moved boolean
  - advanced boolean
  - finished boolean
  - index number
  - target Vector3|nil
  - lastMoveToUpdateTime number
]]
function ClientPathService.StepPath(unitModel, opts)
	opts = opts or {}

	local pathState = GetPathState(unitModel)
	if not pathState or not pathState.Waypoints or not pathState.Index or pathState.Index <= 0 then
		return {
			ok = false,
			moved = false,
			advanced = false,
			finished = true,
			index = (pathState and pathState.Index) or 0,
			target = nil,
			lastMoveToUpdateTime = opts.lastMoveToUpdateTime or 0,
		}
	end

	local total = #pathState.Waypoints
	if pathState.Index > total then
		return {
			ok = false,
			moved = false,
			advanced = false,
			finished = true,
			index = pathState.Index,
			target = nil,
			lastMoveToUpdateTime = opts.lastMoveToUpdateTime or 0,
		}
	end

	-- Heartbeat驱动时，主动断开残留MoveToFinished连接，避免竞态推进Index
	if opts.disconnectMoveConnection ~= false then
		if pathState.MoveConnection then
			pcall(function()
				pathState.MoveConnection:Disconnect()
			end)
			pathState.MoveConnection = nil
		end
		pathState.CurrentWaypointIndex = nil
	end

	local humanoid = opts.humanoid or unitModel:FindFirstChild("Humanoid")
	if not humanoid then
		return {
			ok = false,
			moved = false,
			advanced = false,
			finished = false,
			index = pathState.Index,
			target = nil,
			lastMoveToUpdateTime = opts.lastMoveToUpdateTime or 0,
		}
	end

	local now = opts.now or tick()
	local lastUpdate = opts.lastMoveToUpdateTime or 0
	local currentPos = opts.currentPos or GetModelPosition(unitModel)
	if not currentPos then
		return {
			ok = false,
			moved = false,
			advanced = false,
			finished = false,
			index = pathState.Index,
			target = nil,
			lastMoveToUpdateTime = lastUpdate,
		}
	end

	local refreshInterval = opts.refreshInterval or 0.5
	local cornerCutThreshold = opts.cornerCutThreshold or 5.0
	local finalReachThreshold = opts.finalReachThreshold or 1.5
	local mapWaypoint = opts.mapWaypoint

	local function GetDesiredWaypoint()
		local raw = pathState.Waypoints[pathState.Index]
		if not raw then
			return nil
		end
		if mapWaypoint then
			local mapped = mapWaypoint(raw)
			if mapped then
				return mapped
			end
		end
		return raw
	end

	local desired = GetDesiredWaypoint()
	if not desired then
		return {
			ok = false,
			moved = false,
			advanced = false,
			finished = true,
			index = pathState.Index,
			target = nil,
			lastMoveToUpdateTime = lastUpdate,
		}
	end

	local advanced = false
	local distToWaypoint = GetHorizontalDistance(currentPos, desired)
	local isFinalPoint = pathState.Index >= total
	local reachThreshold = isFinalPoint and finalReachThreshold or cornerCutThreshold

	if distToWaypoint < reachThreshold then
		pathState.Index = pathState.Index + 1
		advanced = true
		lastUpdate = 0 -- 推进后强制立刻MoveTo下一个点
		if pathState.Index <= total then
			desired = GetDesiredWaypoint()
		else
			desired = nil
		end
	end

	local moved = false
	if desired and (lastUpdate == 0 or (now - lastUpdate) > refreshInterval) then
		humanoid:MoveTo(desired)
		moved = true
		lastUpdate = now
	end

	return {
		ok = true,
		moved = moved,
		advanced = advanced,
		finished = (pathState.Index > total) or (desired == nil),
		index = pathState.Index,
		target = desired,
		lastMoveToUpdateTime = lastUpdate,
	}
end

--[[
检查是否需要重新寻路
@param unitModel Model - 单位模型
@return boolean - 是否需要重新寻路
]]
function ClientPathService.NeedRepath(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then
		return false
	end
	return pathState.Status == PathStatus.NEED_REPATH or pathState.Status == PathStatus.BLOCKED
end

--[[
获取当前路径的剩余距离估算
@param unitModel Model - 单位模型
@return number - 剩余距离（studs）
]]
function ClientPathService.GetRemainingDistance(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState or not pathState.Waypoints or pathState.Index > #pathState.Waypoints then
		return 0
	end

	local unitPos = GetModelPosition(unitModel)
	if not unitPos then
		return 0
	end

	local totalDist = 0
	local prevPos = unitPos

	-- 累加所有剩余路点的距离
	for i = pathState.Index, #pathState.Waypoints do
		local waypoint = pathState.Waypoints[i]
		totalDist = totalDist + GetDistance3D(prevPos, waypoint)
		prevPos = waypoint
	end

	return totalDist
end

--[[
停止单位移动
@param unitModel Model - 单位模型
]]
function ClientPathService.StopMovement(unitModel)
	ClientPathService.ClearPath(unitModel)
end

--[[
清理所有路径数据（战斗结束时调用）
V4.8修复：增强清理逻辑，确保彻底清除所有路径状态和事件连接
]]
function ClientPathService.ClearAll()
	-- 先切换generation，确保所有在跑的异步任务都会丢弃结果
	generation += 1
	pathQueue = {}
	queuedRequests = {}
	activeComputes = 0
	processScheduled = false

	-- V4.8修复：先收集所有需要清理的单位（避免迭代过程中修改字典）
	local unitsToClean = {}
	for unitModel, pathState in pairs(pathStates) do
		table.insert(unitsToClean, unitModel)
	end

	-- 逐个清理路径（包括断开事件、停止移动、销毁Path）
	for _, unitModel in ipairs(unitsToClean) do
		pcall(function()
			ClientPathService.ClearPath(unitModel)
		end)
	end

	-- V4.8修复：强制重置pathStates为全新的空字典（不仅仅清空，而是重新创建）
	-- 这可以彻底避免任何残留的pathState引用或事件连接
	pathStates = {}

	DebugLog("所有路径数据已彻底清理")
end

return ClientPathService
