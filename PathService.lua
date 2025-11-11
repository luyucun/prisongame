--[[
脚本名称: PathService
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/PathService
版本: V2.0 - 寻路系统重构版

职责：
1. 统一管理所有单位的路径状态
2. 封装PathfindingService，提供简洁的接口
3. 自动处理体型参数、重试、阻挡、降级
4. 提供多级回退策略
5. 集中调试可视化和日志

核心设计原则：
- 单一职责：只负责路径计算和管理，不涉及AI逻辑
- 异步处理：避免瞬间大量ComputeAsync
- 防御式编程：深拷贝数据，避免引用失效
- 智能降级：多级回退策略，确保单位总能移动
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
	-- V2.0.4优化：从0.5降低到0.2，加速被挤停单位的重新寻路
	PATH_RECALC_COOLDOWN = 0.2,

	-- 目标移动阈值（studs）
	TARGET_MOVE_THRESHOLD = 8,

	-- Waypoint到达阈值（studs）
	WAYPOINT_REACH_THRESHOLD = 4,

	-- 最大重试次数
	MAX_RETRY_COUNT = 3,

	-- 连续阻挡次数上限
	MAX_BLOCKED_COUNT = 3,

	-- 阻挡时间窗口（秒）
	BLOCKED_TIME_WINDOW = 2,

	-- 降级策略：减小AgentRadius的比例
	RADIUS_REDUCTION_RATIO = 0.85,

	-- 降级策略：最小AgentRadius
	MIN_AGENT_RADIUS = 0.5,

	-- 近邻点采样半径（studs）
	-- V2.0.4优化：增大到10，让PathfindingService给出的路径更远离士兵
	NEIGHBOR_SAMPLE_RADIUS = 10,

	-- 近邻点采样数量
	NEIGHBOR_SAMPLE_COUNT = 8,

	-- 体型参数缓存时间（秒），-1表示永久缓存
	AGENT_PARAMS_CACHE_TIME = -1,

	-- 路径参数
	WAYPOINT_SPACING = 4,

	-- 体型参数自动计算
	-- V2.0.4优化：AUTO_RADIUS_MULTIPLIER从0.35降低到0.25，减少被挤阻概率
	AUTO_RADIUS_MULTIPLIER = 0.25,  -- max(X,Z) * 0.25
	AUTO_RADIUS_OFFSET = 0.2,       -- + 0.2 容差
	AUTO_HEIGHT_OFFSET = 1,         -- Y + 1 容差

	-- V2.0性能优化配置
	BATCH_UPDATE_INTERVAL = 0.15,   -- 批量更新间隔（秒），降低Heartbeat频率
	-- V2.0.4优化：从3提高到6，让同批次被阻挡的兵种更快拿到新路径
	MAX_COMPUTE_PER_FRAME = 6,      -- 每帧最多执行的ComputeAsync数量（限流）
	BATCH_START_DELAY = 0.25,       -- 批量启动延迟（秒）
	BATCH_START_SIZE = 8,           -- 每批启动的单位数量

	-- 调试选项
	DEBUG_SHOW_PATH = false,        -- 是否显示路径可视化
	DEBUG_PATH_LOGS = false,        -- 是否打印详细日志
	PATH_WAYPOINT_COLOR = Color3.new(0, 1, 0),  -- 绿色
	PATH_LINE_COLOR = Color3.new(1, 1, 0),       -- 黄色
}

-- 从BattleConfig读取配置（如果存在）
if BattleConfig then
	CONFIG.PATH_RECALC_COOLDOWN = BattleConfig.PATH_RECALC_COOLDOWN or CONFIG.PATH_RECALC_COOLDOWN
	CONFIG.TARGET_MOVE_THRESHOLD = BattleConfig.PATH_TARGET_MOVE_THRESHOLD or CONFIG.TARGET_MOVE_THRESHOLD
	CONFIG.WAYPOINT_REACH_THRESHOLD = BattleConfig.WAYPOINT_REACH_THRESHOLD or CONFIG.WAYPOINT_REACH_THRESHOLD
	CONFIG.MAX_RETRY_COUNT = BattleConfig.PATH_MAX_RETRY_COUNT or CONFIG.MAX_RETRY_COUNT
	CONFIG.DEBUG_SHOW_PATH = BattleConfig.DEBUG_SHOW_PATH or CONFIG.DEBUG_SHOW_PATH
	CONFIG.DEBUG_PATH_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_PATH_LOGS
	CONFIG.PATH_WAYPOINT_COLOR = BattleConfig.PATH_WAYPOINT_COLOR or CONFIG.PATH_WAYPOINT_COLOR
	CONFIG.PATH_LINE_COLOR = BattleConfig.PATH_LINE_COLOR or CONFIG.PATH_LINE_COLOR
end

-- ==================== 路径状态枚举 ====================

local PathStatus = {
	IDLE = "Idle",           -- 无路径
	QUEUED = "Queued",       -- 队列中
	COMPUTING = "Computing", -- 计算中
	SUCCESS = "Success",     -- 成功
	FAILED = "Failed",       -- 失败
	BLOCKED = "Blocked",     -- 被阻挡
	NEED_REPATH = "NeedRepath", -- 需要重建
}

-- ==================== 路径数据结构 ====================

--[[
PathState = {
	Path = Path|nil,                -- PathfindingService创建的Path对象
	Waypoints = {Vector3}|nil,      -- 深拷贝的路径点列表（只存Vector3）
	Index = number,                  -- 当前路径点索引
	LastTargetPos = Vector3|nil,    -- 上次目标位置
	LastRequestTime = number,        -- 上次请求时间
	Status = string,                 -- 路径状态（见PathStatus枚举）
	Retries = number,                -- 重试次数
	BlockedCount = number,           -- 连续阻挡次数
	LastBlockedTime = number,        -- 最后阻挡时间
	BlockedConnection = RBXScriptConnection|nil, -- 阻挡事件连接
	AgentParams = table|nil,         -- 缓存的体型参数
	DebugParts = {Part}|nil,         -- 调试可视化Part列表
}
]]

-- ==================== 私有变量 ====================

local pathStates = {}  -- [unitModel] = PathState
local agentParamsCache = {}  -- [unitId] = {Radius, Height, CanJump, CacheTime}

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_PATH_LOGS then
		print(GameConfig.LOG_PREFIX, "[PathService]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[PathService]", ...)
end

-- ==================== 工具函数 ====================

--[[
深拷贝waypoints，只保存Position（Vector3）
@param waypoints - PathWaypoint列表
@return {Vector3} - 深拷贝的Vector3列表
]]
local function DeepCopyWaypoints(waypoints)
	if not waypoints then
		return nil
	end

	local copy = {}
	for i, waypoint in ipairs(waypoints) do
		-- 只拷贝Position（Vector3），Action不需要了
		table.insert(copy, waypoint.Position)
	end

	return copy
end

--[[
获取模型的世界位置
@param model - Model对象或Part对象
@return Vector3|nil
]]
local function GetModelPosition(model)
	if not model then
		return nil
	end

	-- V2.0修复：如果是 Part，直接返回位置
	if model:IsA("BasePart") then
		return model.Position
	end

	-- 如果是 Model，查找 HumanoidRootPart 或 PrimaryPart
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not rootPart then
		return nil
	end

	return rootPart.Position
end

--[[
计算两个位置的距离
@param pos1 - Vector3
@param pos2 - Vector3
@return number
]]
local function GetDistance(pos1, pos2)
	if not pos1 or not pos2 then
		return math.huge
	end

	return (pos1 - pos2).Magnitude
end

-- ==================== 体型参数管理 ====================

--[[
自动计算Agent参数
@param unitModel - 兵种模型
@return {Radius: number, Height: number, CanJump: boolean}
]]
local function CalculateAgentParams(unitModel)
	local radius = 2  -- 默认值
	local height = 5  -- 默认值
	local canJump = true  -- 默认值

	-- 方法1: 从模型自动推算
	if unitModel then
		local success, size = pcall(function()
			return unitModel:GetExtentsSize()
		end)

		if success and size then
			-- AgentRadius = max(X,Z) * 0.35 + 0.2容差
			local baseRadius = math.max(size.X, size.Z) * CONFIG.AUTO_RADIUS_MULTIPLIER
			radius = baseRadius + CONFIG.AUTO_RADIUS_OFFSET

			-- AgentHeight = Y + 1容差
			height = size.Y + CONFIG.AUTO_HEIGHT_OFFSET

			-- 限制在合理范围
			radius = math.max(CONFIG.MIN_AGENT_RADIUS, radius)
			height = math.max(1, height)
		end
	end

	-- 方法2: 检查Humanoid的Jump能力
	if unitModel then
		local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			canJump = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		end
	end

	return {
		Radius = radius,
		Height = height,
		CanJump = canJump,
	}
end

--[[
获取Agent参数（带缓存）
@param unitModel - 兵种模型
@param unitId - 单位ID
@return {Radius: number, Height: number, CanJump: boolean}
]]
local function GetAgentParams(unitModel, unitId)
	-- 检查缓存
	local cached = agentParamsCache[unitId]
	if cached then
		-- 如果是永久缓存或未过期，直接返回
		if CONFIG.AGENT_PARAMS_CACHE_TIME < 0 or
		   (tick() - cached.CacheTime) < CONFIG.AGENT_PARAMS_CACHE_TIME then
			return cached.Params
		end
	end

	-- 优先读取UnitConfig中的显式配置
	local configParams = {}
	local hasConfig = false

	if UnitConfig.GetPathfindingAgentRadius then
		local configRadius = UnitConfig.GetPathfindingAgentRadius(unitId)
		if configRadius ~= nil then
			configParams.Radius = configRadius
			hasConfig = true
		end
	end

	if UnitConfig.GetPathfindingAgentHeight then
		local configHeight = UnitConfig.GetPathfindingAgentHeight(unitId)
		if configHeight ~= nil then
			configParams.Height = configHeight
			hasConfig = true
		end
	end

	if UnitConfig.GetPathfindingAgentCanJump then
		local configCanJump = UnitConfig.GetPathfindingAgentCanJump(unitId)
		if configCanJump ~= nil then
			configParams.CanJump = configCanJump
			hasConfig = true
		end
	end

	-- 如果有显式配置，使用配置；否则自动计算
	local params
	if hasConfig then
		-- 自动计算作为默认值
		local autoParams = CalculateAgentParams(unitModel)
		params = {
			Radius = configParams.Radius or autoParams.Radius,
			Height = configParams.Height or autoParams.Height,
			CanJump = configParams.CanJump ~= nil and configParams.CanJump or autoParams.CanJump,
		}
		DebugLog(string.format("%s 使用配置参数: R=%.1f, H=%.1f, Jump=%s",
			unitId, params.Radius, params.Height, tostring(params.CanJump)))
	else
		params = CalculateAgentParams(unitModel)
		DebugLog(string.format("%s 自动计算参数: R=%.1f, H=%.1f, Jump=%s",
			unitId, params.Radius, params.Height, tostring(params.CanJump)))
	end

	-- 缓存结果
	agentParamsCache[unitId] = {
		Params = params,
		CacheTime = tick(),
	}

	return params
end

-- ==================== 调试可视化 ====================

--[[
清理调试可视化Part
@param pathState - 路径状态
]]
local function ClearDebugParts(pathState)
	if not pathState or not pathState.DebugParts then
		return
	end

	for _, part in ipairs(pathState.DebugParts) do
		if part and part.Parent then
			pcall(function()
				part:Destroy()
			end)
		end
	end

	pathState.DebugParts = {}
end

--[[
绘制路径可视化
@param waypoints - 路径点列表（Vector3）
@param pathState - 路径状态
]]
local function DrawPath(waypoints, pathState)
	if not CONFIG.DEBUG_SHOW_PATH or not waypoints or #waypoints == 0 then
		return
	end

	-- 清理旧的调试Part
	ClearDebugParts(pathState)

	-- 绘制waypoint点
	for i, waypointPos in ipairs(waypoints) do
		local part = Instance.new("Part")
		part.Size = Vector3.new(1, 1, 1)
		part.Position = waypointPos
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.5
		part.Color = CONFIG.PATH_WAYPOINT_COLOR
		part.Name = "Waypoint_" .. i
		part.Parent = workspace

		table.insert(pathState.DebugParts, part)
	end

	-- 绘制连接线
	for i = 1, #waypoints - 1 do
		local start = waypoints[i]
		local finish = waypoints[i + 1]
		local distance = (finish - start).Magnitude
		local midpoint = (start + finish) / 2

		local line = Instance.new("Part")
		line.Size = Vector3.new(0.2, 0.2, distance)
		line.CFrame = CFrame.new(midpoint, finish)
		line.Anchored = true
		line.CanCollide = false
		line.Transparency = 0.7
		line.Color = CONFIG.PATH_LINE_COLOR
		line.Name = "PathLine_" .. i
		line.Parent = workspace

		table.insert(pathState.DebugParts, line)
	end

	DebugLog(string.format("路径可视化已绘制，共%d个点", #waypoints))
end

-- ==================== 路径状态管理 ====================

--[[
初始化路径状态
@param unitModel - 兵种模型
@return PathState
]]
local function InitPathState(unitModel)
	local pathState = {
		Path = nil,
		Waypoints = nil,
		Index = 0,
		LastTargetPos = nil,
		LastRequestTime = 0,
		Status = PathStatus.IDLE,
		Retries = 0,
		BlockedCount = 0,
		LastBlockedTime = 0,
		BlockedConnection = nil,
		AgentParams = nil,
		DebugParts = {},
	}

	pathStates[unitModel] = pathState
	return pathState
end

--[[
获取路径状态
@param unitModel - 兵种模型
@return PathState|nil
]]
local function GetPathState(unitModel)
	return pathStates[unitModel]
end

--[[
清理路径数据
@param unitModel - 兵种模型
]]
local function ClearPathData(unitModel)
	local pathState = pathStates[unitModel]
	if not pathState then
		return
	end

	-- 断开阻挡事件连接
	if pathState.BlockedConnection then
		pathState.BlockedConnection:Disconnect()
		pathState.BlockedConnection = nil
	end

	-- 销毁Path对象
	if pathState.Path then
		pcall(function()
			pathState.Path:Destroy()
		end)
		pathState.Path = nil
	end

	-- 清理调试可视化
	ClearDebugParts(pathState)

	-- 重置状态
	pathState.Waypoints = nil
	pathState.Index = 0
	pathState.LastTargetPos = nil
	pathState.Status = PathStatus.IDLE
	pathState.Retries = 0
	pathState.BlockedCount = 0
	pathState.LastBlockedTime = 0

	DebugLog("路径已清理")
end

-- ==================== 降级策略 ====================

--[[
尝试采样近邻可达点
@param unitModel - 兵种模型
@param targetPos - 目标位置
@param agentParams - Agent参数
@return Vector3|nil - 可达的近邻点
]]
local function SampleNeighborPoint(unitModel, targetPos, agentParams)
	local startPos = GetModelPosition(unitModel)
	if not startPos then
		return nil
	end

	-- 在目标周围采样多个点
	local sampleRadius = CONFIG.NEIGHBOR_SAMPLE_RADIUS
	local sampleCount = CONFIG.NEIGHBOR_SAMPLE_COUNT
	local angleStep = (2 * math.pi) / sampleCount

	for i = 0, sampleCount - 1 do
		local angle = i * angleStep
		local offsetX = math.cos(angle) * sampleRadius
		local offsetZ = math.sin(angle) * sampleRadius

		local samplePos = targetPos + Vector3.new(offsetX, 0, offsetZ)

		-- 尝试计算到这个点的路径
		local path = PathfindingService:CreatePath({
			AgentRadius = agentParams.Radius,
			AgentHeight = agentParams.Height,
			AgentCanJump = agentParams.CanJump,
			WaypointSpacing = CONFIG.WAYPOINT_SPACING,
		})

		local success, _ = pcall(function()
			path:ComputeAsync(startPos, samplePos)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			if waypoints and #waypoints >= 2 then
				DebugLog(string.format("找到可达近邻点 #%d，距离目标%.1f studs", i, (samplePos - targetPos).Magnitude))
				path:Destroy()
				return samplePos
			end
		end

		path:Destroy()
	end

	return nil
end

--[[
多级回退策略
@param unitModel - 兵种模型
@param targetModel - 目标模型
@param pathState - 路径状态
@param unitId - 单位ID
@return boolean - 是否成功
]]
local function TryFallbackStrategy(unitModel, targetModel, pathState, unitId)
	local startPos = GetModelPosition(unitModel)
	local targetPos = GetModelPosition(targetModel)

	if not startPos or not targetPos then
		return false
	end

	-- 策略1: 减小AgentRadius重试
	if pathState.Retries == 1 then
		local originalRadius = pathState.AgentParams.Radius
		local reducedRadius = math.max(CONFIG.MIN_AGENT_RADIUS, originalRadius * CONFIG.RADIUS_REDUCTION_RATIO)

		DebugLog(string.format("%s [回退策略1] 减小AgentRadius: %.1f → %.1f", unitId, originalRadius, reducedRadius))

		local newParams = {
			Radius = reducedRadius,
			Height = pathState.AgentParams.Height,
			CanJump = pathState.AgentParams.CanJump,
		}

		-- 尝试用新参数构建路径
		local path = PathfindingService:CreatePath({
			AgentRadius = newParams.Radius,
			AgentHeight = newParams.Height,
			AgentCanJump = newParams.CanJump,
			WaypointSpacing = CONFIG.WAYPOINT_SPACING,
		})

		local success, _ = pcall(function()
			path:ComputeAsync(startPos, targetPos)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			if waypoints and #waypoints >= 2 then
				-- 成功！更新路径状态
				pathState.Path = path
				pathState.Waypoints = DeepCopyWaypoints(waypoints)
				pathState.Index = 2
				pathState.AgentParams = newParams
				pathState.Status = PathStatus.SUCCESS
				pathState.LastTargetPos = targetPos
				pathState.Retries = 0

				DrawPath(pathState.Waypoints, pathState)
				DebugLog(string.format("%s [回退策略1] 成功！共%d个路径点", unitId, #pathState.Waypoints))
				return true
			end
		end

		path:Destroy()
	end

	-- 策略2: 采样近邻点
	if pathState.Retries == 2 then
		DebugLog(string.format("%s [回退策略2] 采样近邻可达点", unitId))

		local neighborPos = SampleNeighborPoint(unitModel, targetPos, pathState.AgentParams)

		if neighborPos then
			-- 尝试构建到近邻点的路径
			local path = PathfindingService:CreatePath({
				AgentRadius = pathState.AgentParams.Radius,
				AgentHeight = pathState.AgentParams.Height,
				AgentCanJump = pathState.AgentParams.CanJump,
				WaypointSpacing = CONFIG.WAYPOINT_SPACING,
			})

			local success, _ = pcall(function()
				path:ComputeAsync(startPos, neighborPos)
			end)

			if success and path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()
				if waypoints and #waypoints >= 2 then
					pathState.Path = path
					pathState.Waypoints = DeepCopyWaypoints(waypoints)
					pathState.Index = 2
					pathState.Status = PathStatus.SUCCESS
					pathState.LastTargetPos = neighborPos  -- 注意：这里目标变成近邻点了
					pathState.Retries = 0

					DrawPath(pathState.Waypoints, pathState)
					DebugLog(string.format("%s [回退策略2] 成功！路径到近邻点", unitId))
					return true
				end
			end

			path:Destroy()
		end
	end

	-- 策略3: 完全失败，标记为直线移动
	if pathState.Retries >= CONFIG.MAX_RETRY_COUNT then
		DebugLog(string.format("%s [回退策略3] 所有策略失败，标记为直线移动", unitId))
		pathState.Status = PathStatus.FAILED
		pathState.Retries = 0
		return false
	end

	return false
end

-- ==================== 路径构建 ====================

--[[
构建路径（核心函数）
@param unitModel - 兵种模型
@param targetModel - 目标模型
@param unitId - 单位ID
@return boolean - 是否成功
]]
local function BuildPath(unitModel, targetModel, unitId)
	local pathState = GetPathState(unitModel)
	if not pathState then
		pathState = InitPathState(unitModel)
	end

	-- 检查冷却
	local currentTime = tick()
	if (currentTime - pathState.LastRequestTime) < CONFIG.PATH_RECALC_COOLDOWN then
		return false
	end

	-- 获取起点和终点
	local startPos = GetModelPosition(unitModel)
	local targetPos = GetModelPosition(targetModel)

	if not startPos or not targetPos then
		return false
	end

	-- 获取Agent参数（带缓存）
	if not pathState.AgentParams then
		pathState.AgentParams = GetAgentParams(unitModel, unitId)
	end

	local agentParams = pathState.AgentParams

	-- 每次都创建新的Path对象，避免复用导致状态混乱
	if pathState.Path then
		if pathState.BlockedConnection then
			pathState.BlockedConnection:Disconnect()
			pathState.BlockedConnection = nil
		end
		pcall(function()
			pathState.Path:Destroy()
		end)
		pathState.Path = nil
	end

	-- 创建新Path对象
	local path = PathfindingService:CreatePath({
		AgentRadius = agentParams.Radius,
		AgentHeight = agentParams.Height,
		AgentCanJump = agentParams.CanJump,
		WaypointSpacing = CONFIG.WAYPOINT_SPACING,
	})

	pathState.Path = path

	-- 监听路径阻挡事件
	pathState.BlockedConnection = path.Blocked:Connect(function(blockedWaypointIndex)
		if blockedWaypointIndex >= pathState.Index then
			local now = tick()

			-- 短时间内多次阻挡，增加计数
			if now - pathState.LastBlockedTime < CONFIG.BLOCKED_TIME_WINDOW then
				pathState.BlockedCount = pathState.BlockedCount + 1
			else
				pathState.BlockedCount = 1
			end
			pathState.LastBlockedTime = now

			-- 连续阻挡次数过多，放弃寻路
			if pathState.BlockedCount >= CONFIG.MAX_BLOCKED_COUNT then
				DebugLog(string.format("%s 路径连续阻挡%d次，放弃寻路", unitId, pathState.BlockedCount))
				pathState.Status = PathStatus.FAILED
				pathState.LastRequestTime = now + 5  -- 5秒冷却
				ClearPathData(unitModel)
				return
			end

			DebugLog(string.format("%s 路径被阻挡在waypoint %d (第%d次)，标记需要重建",
				unitId, blockedWaypointIndex, pathState.BlockedCount))

			-- 标记需要重建
			pathState.Status = PathStatus.NEED_REPATH
			pathState.LastRequestTime = 0  -- 允许立即重建
		end
	end)

	-- 计算路径
	pathState.Status = PathStatus.COMPUTING

	local success, errorMsg = pcall(function()
		path:ComputeAsync(startPos, targetPos)
	end)

	if not success then
		WarnLog(string.format("%s 路径计算失败: %s", unitId, tostring(errorMsg)))
		pathState.Retries = pathState.Retries + 1
		pathState.LastRequestTime = currentTime

		-- 尝试降级策略
		return TryFallbackStrategy(unitModel, targetModel, pathState, unitId)
	end

	-- 检查路径状态
	if path.Status ~= Enum.PathStatus.Success then
		local statusName = tostring(path.Status)
		if path.Status == Enum.PathStatus.NoPath then
			statusName = "NoPath(找不到可行路径)"
		end

		DebugLog(string.format("%s 路径状态异常: %s", unitId, statusName))
		pathState.Retries = pathState.Retries + 1
		pathState.LastRequestTime = currentTime

		-- 尝试降级策略
		return TryFallbackStrategy(unitModel, targetModel, pathState, unitId)
	end

	-- 获取路径点
	local waypoints = path:GetWaypoints()
	if not waypoints or #waypoints < 2 then
		DebugLog(string.format("%s 路径点数量不足(%d)", unitId, waypoints and #waypoints or 0))
		pathState.Retries = pathState.Retries + 1
		pathState.LastRequestTime = currentTime

		-- 尝试降级策略
		return TryFallbackStrategy(unitModel, targetModel, pathState, unitId)
	end

	-- 深拷贝waypoints（只保存Vector3）
	pathState.Waypoints = DeepCopyWaypoints(waypoints)
	pathState.Index = 2  -- 跳过第一个点（起点）
	pathState.Status = PathStatus.SUCCESS
	pathState.LastTargetPos = targetPos
	pathState.LastRequestTime = currentTime
	pathState.Retries = 0
	pathState.BlockedCount = 0

	-- 绘制路径（调试）
	DrawPath(pathState.Waypoints, pathState)

	DebugLog(string.format("%s ✅路径构建成功，共%d个路径点", unitId, #pathState.Waypoints))
	return true
end

-- ==================== 公共接口 ====================

--[[
请求路径（主接口）
如果已有有效路径且目标未移动太多，则复用；否则构建新路径
@param unitModel - 兵种模型
@param targetModel - 目标模型
@param unitId - 单位ID（可选，用于日志）
@return boolean - 是否成功获取/构建路径
]]
function PathService.RequestPath(unitModel, targetModel, unitId)
	if not unitModel or not targetModel then
		return false
	end

	unitId = unitId or tostring(unitModel)

	local pathState = GetPathState(unitModel)
	if not pathState then
		pathState = InitPathState(unitModel)
	end

	-- 如果路径状态是NEED_REPATH，清理后重建
	if pathState.Status == PathStatus.NEED_REPATH then
		DebugLog(string.format("%s 路径需要重建", unitId))
		ClearPathData(unitModel)
		return BuildPath(unitModel, targetModel, unitId)
	end

	-- 如果已有成功的路径
	if pathState.Status == PathStatus.SUCCESS and pathState.Waypoints and #pathState.Waypoints > 0 then
		-- 检查目标是否移动过多
		local targetPos = GetModelPosition(targetModel)
		if targetPos and pathState.LastTargetPos then
			local distance = GetDistance(targetPos, pathState.LastTargetPos)
			if distance < CONFIG.TARGET_MOVE_THRESHOLD then
				-- 目标未移动太多，复用路径
				return true
			else
				DebugLog(string.format("%s 目标移动了%.1f studs，需要重建路径", unitId, distance))
			end
		end
	end

	-- 构建新路径
	return BuildPath(unitModel, targetModel, unitId)
end

--[[
获取下一个路径点
@param unitModel - 兵种模型
@return Vector3|nil - 下一个路径点位置，nil表示路径结束或无效
]]
function PathService.GetNextWaypoint(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState or pathState.Status ~= PathStatus.SUCCESS then
		return nil
	end

	if not pathState.Waypoints or pathState.Index > #pathState.Waypoints then
		return nil
	end

	return pathState.Waypoints[pathState.Index]
end

--[[
推进到下一个路径点
@param unitModel - 兵种模型
@return boolean - 是否还有更多路径点
]]
function PathService.AdvancePath(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState or pathState.Status ~= PathStatus.SUCCESS then
		return false
	end

	if not pathState.Waypoints then
		return false
	end

	pathState.Index = pathState.Index + 1

	if pathState.Index > #pathState.Waypoints then
		-- 路径已走完
		DebugLog("路径已走完")
		return false
	end

	return true
end

--[[
获取路径状态
@param unitModel - 兵种模型
@return string - 路径状态（PathStatus枚举）
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
@param unitModel - 兵种模型
]]
function PathService.ClearPath(unitModel)
	ClearPathData(unitModel)
end

--[[
强制重建路径
@param unitModel - 兵种模型
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
@param unitModel - 兵种模型
@param threshold - 到达阈值（可选，默认使用配置值）
@return boolean - 是否到达当前路径点
]]
function PathService.HasReachedWaypoint(unitModel, threshold)
	threshold = threshold or CONFIG.WAYPOINT_REACH_THRESHOLD

	local pathState = GetPathState(unitModel)
	if not pathState or pathState.Status ~= PathStatus.SUCCESS then
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

	-- 忽略Y轴，只比较XZ平面距离
	local distance = (Vector3.new(currentWaypoint.X, currentPos.Y, currentWaypoint.Z) -
	                  Vector3.new(currentPos.X, currentPos.Y, currentPos.Z)).Magnitude

	return distance < threshold
end

--[[
清理所有路径（用于战斗结束/系统关闭）
]]
function PathService.ClearAllPaths()
	for unitModel, _ in pairs(pathStates) do
		ClearPathData(unitModel)
	end

	pathStates = {}
	DebugLog("所有路径已清理")
end

--[[
清理指定战斗的路径
@param battleId - 战斗ID
@param getUnitState - 获取单位状态的函数（可选）
]]
function PathService.ClearBattlePaths(battleId, getUnitState)
	if not getUnitState then
		return
	end

	for unitModel, _ in pairs(pathStates) do
		local state = getUnitState(unitModel)
		if state and state.BattleId == battleId then
			ClearPathData(unitModel)
			pathStates[unitModel] = nil
		end
	end

	DebugLog(string.format("战斗%s的路径已清理", tostring(battleId)))
end

--[[
获取路径点数量
@param unitModel - 兵种模型
@return number - 路径点数量
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
@param unitModel - 兵种模型
@return number - 当前索引
]]
function PathService.GetCurrentWaypointIndex(unitModel)
	local pathState = GetPathState(unitModel)
	if not pathState then
		return 0
	end

	return pathState.Index
end

--[[
设置调试选项
@param showPath - 是否显示路径可视化
@param showLogs - 是否显示详细日志
]]
function PathService.SetDebugOptions(showPath, showLogs)
	if showPath ~= nil then
		CONFIG.DEBUG_SHOW_PATH = showPath
	end

	if showLogs ~= nil then
		CONFIG.DEBUG_PATH_LOGS = showLogs
	end
end

--[[
获取配置
@return table - 配置表
]]
function PathService.GetConfig()
	return CONFIG
end

-- ==================== V2.0新增: 批量寻路（战役系统） ====================

-- 存储活跃的批量移动任务
local activeMoves = {}  -- [moveId] = {connection, moveData}
local nextMoveId = 1

-- ==================== V2.0性能优化: 路径计算限流队列 ====================

-- 路径计算队列
local computeQueue = {}  -- {{unitInstance, targetPart, unitId, callback}, ...}
local computingCount = 0  -- 当前正在计算的数量
local lastComputeCheckTime = 0

-- 性能统计数据
local performanceStats = {
	TotalPathRequests = 0,       -- 总路径请求数
	TotalComputeAsync = 0,       -- 总ComputeAsync调用数
	QueuedRequests = 0,          -- 当前队列中的请求数
	ActiveMoveTasks = 0,         -- 当前活跃的移动任务数
	TotalUnitsMoving = 0,        -- 当前正在移动的单位数
	LastResetTime = tick(),      -- 上次重置时间
}

--[[
获取性能统计数据
@return table - 统计数据
]]
function PathService.GetPerformanceStats()
	performanceStats.QueuedRequests = #computeQueue
	performanceStats.ActiveMoveTasks = 0
	performanceStats.TotalUnitsMoving = 0

	for moveId, moveTask in pairs(activeMoves) do
		performanceStats.ActiveMoveTasks = performanceStats.ActiveMoveTasks + 1
		if moveTask.moveData then
			for _, data in pairs(moveTask.moveData) do
				if not data.Arrived then
					performanceStats.TotalUnitsMoving = performanceStats.TotalUnitsMoving + 1
				end
			end
		end
	end

	return performanceStats
end

--[[
重置性能统计
]]
function PathService.ResetPerformanceStats()
	performanceStats.TotalPathRequests = 0
	performanceStats.TotalComputeAsync = 0
	performanceStats.LastResetTime = tick()
	print("[PathService] 性能统计已重置")
end

--[[
打印性能统计
]]
function PathService.PrintPerformanceStats()
	local stats = PathService.GetPerformanceStats()
	local elapsed = tick() - stats.LastResetTime
	print("==================== PathService 性能统计 ====================")
	print(string.format("运行时间: %.1f 秒", elapsed))
	print(string.format("总路径请求数: %d", stats.TotalPathRequests))
	print(string.format("总ComputeAsync调用: %d", stats.TotalComputeAsync))
	print(string.format("当前队列长度: %d", stats.QueuedRequests))
	print(string.format("活跃移动任务: %d", stats.ActiveMoveTasks))
	print(string.format("正在移动单位数: %d", stats.TotalUnitsMoving))
	if elapsed > 0 then
		print(string.format("平均请求速率: %.2f 请求/秒", stats.TotalPathRequests / elapsed))
		print(string.format("平均计算速率: %.2f 计算/秒", stats.TotalComputeAsync / elapsed))
	end
	print("=============================================================")
end

--[[
将路径计算请求加入队列
@param unitInstance - 单位实例
@param targetPart - 目标Part
@param unitId - 单位ID
@param callback - 完成回调 function(success, pathState)
]]
local function QueuePathCompute(unitInstance, targetPart, unitId, callback)
	table.insert(computeQueue, {
		unitInstance = unitInstance,
		targetPart = targetPart,
		unitId = unitId,
		callback = callback,
		queueTime = tick()
	})

	performanceStats.TotalPathRequests = performanceStats.TotalPathRequests + 1
end

--[[
处理路径计算队列（每帧最多处理MAX_COMPUTE_PER_FRAME个）
修复：添加 pcall 保护，确保 computingCount 始终正确递减
]]
local function ProcessComputeQueue()
	local now = tick()

	-- 节流：每CONFIG.BATCH_UPDATE_INTERVAL秒检查一次
	if now - lastComputeCheckTime < CONFIG.BATCH_UPDATE_INTERVAL then
		return
	end
	lastComputeCheckTime = now

	-- 处理队列中的请求
	while #computeQueue > 0 and computingCount < CONFIG.MAX_COMPUTE_PER_FRAME do
		local request = table.remove(computeQueue, 1)

		-- V2.0修复：跳过无效请求（单位或目标已被删除）
		if not request.unitInstance or not request.unitInstance.Parent then
			DebugLog(string.format("⚠️ 跳过无效请求: 单位已被删除"))
			continue
		end

		if not request.targetPart or not request.targetPart.Parent then
			DebugLog(string.format("⚠️ 跳过无效请求: 目标Part已被删除 (%s)", request.unitId or "Unknown"))
			-- 仍然需要调用回调通知失败
			if request.callback then
				pcall(function()
					request.callback(false, nil)
				end)
			end
			continue
		end

		computingCount = computingCount + 1
		performanceStats.TotalComputeAsync = performanceStats.TotalComputeAsync + 1

		-- 异步执行路径计算（带异常保护）
		task.spawn(function()
			local success = false
			local pathState = nil

			-- 关键修复：使用 pcall 保护，确保异常不会导致 computingCount 泄漏
			local pcallSuccess, pcallError = pcall(function()
				success = PathService.RequestPath(request.unitInstance, request.targetPart, request.unitId)
				pathState = GetPathState(request.unitInstance)
			end)

			if not pcallSuccess then
				warn(string.format("[PathService] 路径计算异常: %s, 错误: %s",
					request.unitId or "Unknown", tostring(pcallError)))
			end

			-- 关键：无论成功或失败，都必须减少 computingCount
			computingCount = computingCount - 1

			-- 触发回调（回调本身也用 pcall 保护）
			if request.callback then
				pcall(function()
					request.callback(success, pathState)
				end)
			end
		end)
	end
end

-- 启动队列处理器
RunService.Heartbeat:Connect(ProcessComputeQueue)

--[[
批量移动兵种到指定位置（用于战役系统） - V2.0性能优化版
核心改进：
1. 事件驱动移动（MoveToFinished）而非Heartbeat逐帧遍历
2. 路径计算限流（队列机制）
3. 分批启动（避免瞬时大量ComputeAsync）
4. 降低更新频率（0.15秒而非60FPS）

@param moveTargets table - {[unitInstance] = targetCFrame, ...}
@param callbacks table - 回调函数表 {
    onUnitArrived = function(unitInstance, status),  -- 单位到达时回调
    onAllSettled = function(arrivedList, timedOutList, failedList),  -- 所有单位完成时回调
}
@return string - 移动任务ID，可用于取消
]]
function PathService.MoveUnitsToPositions(moveTargets, callbacks)
	if not moveTargets or type(moveTargets) ~= "table" then
		warn("[PathService] MoveUnitsToPositions: moveTargets无效")
		return nil
	end

	-- 兼容旧版API：callbacks可以是function（相当于onAllSettled）
	local onUnitArrived = nil
	local onAllSettled = nil

	if type(callbacks) == "function" then
		onAllSettled = callbacks  -- 向后兼容
	elseif type(callbacks) == "table" then
		onUnitArrived = callbacks.onUnitArrived
		onAllSettled = callbacks.onAllSettled
	end

	-- 生成移动任务ID
	local moveId = "Move_" .. tostring(nextMoveId)
	nextMoveId = nextMoveId + 1

	local moveData = {}
	local unitsList = {}  -- 用于分批启动
	local moveCount = 0

	-- 结果列表
	local arrivedList = {}
	local timedOutList = {}
	local failedList = {}

	-- 1. 准备所有单位数据
	for unitInstance, targetCFrame in pairs(moveTargets) do
		if unitInstance and unitInstance:FindFirstChild("Humanoid") and unitInstance:FindFirstChild("HumanoidRootPart") then
			-- 创建虚拟目标Part
			local targetPart = Instance.new("Part")
			targetPart.Size = Vector3.new(1, 1, 1)
			targetPart.CFrame = targetCFrame
			targetPart.Anchored = true
			targetPart.CanCollide = false
			targetPart.Transparency = 1
			targetPart.Name = "MarchTarget_" .. unitInstance.Name
			targetPart.Parent = workspace

			-- 初始化移动数据
			moveData[unitInstance] = {
				TargetPart = targetPart,
				TargetCFrame = targetCFrame,
				Arrived = false,
				ForceTeleported = false,
				StartTime = tick(),
				LastPathRequest = 0,
				MoveToConnection = nil,  -- MoveToFinished连接
				PathRequested = false,   -- 是否已请求路径

				-- V2.0.4新增：持续MoveTo推进
				LastMoveCommand = 0,     -- 上次发送MoveTo命令的时间
				CurrentWaypoint = nil,   -- 当前目标路径点
				HeartbeatConn = nil,     -- Heartbeat连接，用于持续推进
			}

			table.insert(unitsList, unitInstance)
			moveCount = moveCount + 1
		end
	end

	if moveCount == 0 then
		warn("[PathService] MoveUnitsToPositions: 没有有效的移动目标")
		if onAllSettled then
			onAllSettled({}, {}, {})
		end
		return nil
	end

	print(string.format("[PathService] 批量寻路开始，兵种数量: %d, MoveId: %s", moveCount, moveId))

	-- ==================== 核心逻辑：事件驱动移动 ====================

	--[[
	为单位启动移动（事件驱动）
	修复：
	1. 检查 reached 标志，避免盲目推进路径点
	2. 路径失效时重置 PathRequested 并重新入队
	]]
	local function StartUnitMovement(unitInstance)
		local data = moveData[unitInstance]
		-- V2.0修复：同时检查Arrived和Cancelled
		if not data or data.Arrived or data.Cancelled then
			return
		end

		local humanoid = unitInstance:FindFirstChild("Humanoid")
		local rootPart = unitInstance:FindFirstChild("HumanoidRootPart")
		if not humanoid or not rootPart then
			data.Arrived = true
			table.insert(failedList, unitInstance)
			return
		end

		local unitId = unitInstance:GetAttribute("UnitId") or unitInstance.Name

		-- 关键修复2：检查 reached 标志的 MoveToFinished 回调
		data.MoveToConnection = humanoid.MoveToFinished:Connect(function(reached)
			-- V2.0修复：同时检查Arrived和Cancelled
			if data.Arrived or data.Cancelled then
				return
			end

			-- 检查是否到达最终目标
			local currentPos = rootPart.Position
			local targetPos = data.TargetCFrame.Position
			local distanceXZ = math.sqrt((currentPos.X - targetPos.X)^2 + (currentPos.Z - targetPos.Z)^2)
			local arrivalThreshold = GameConfig.Campaign.ArrivalThreshold or 8

			if distanceXZ < arrivalThreshold then
				-- 到达目标
				data.Arrived = true

				-- 断开连接
				if data.MoveToConnection then
					data.MoveToConnection:Disconnect()
					data.MoveToConnection = nil
				end

				-- V2.0.4新增：断开Heartbeat连接
				if data.HeartbeatConn then
					data.HeartbeatConn:Disconnect()
					data.HeartbeatConn = nil
				end

				-- 清理
				PathService.ClearPath(unitInstance)
				if data.TargetPart and data.TargetPart.Parent then
					data.TargetPart:Destroy()
				end

				table.insert(arrivedList, unitInstance)
				DebugLog(string.format("✅ 兵种到达: %s", unitInstance.Name))

				-- 触发回调
				if onUnitArrived then
					pcall(function()
						onUnitArrived(unitInstance, "Arrived")
					end)
				end
			elseif not reached then
				-- 关键修复2：reached=false 表示被碰撞/打断，不要盲目推进路径点
				DebugLog(string.format("⚠️ %s 移动被打断 (reached=false)，保持当前路径点", unitId))

				local pathStatus = PathService.GetPathStatus(unitInstance)

				if pathStatus == PathStatus.SUCCESS then
					-- 路径有效，重新尝试移动到当前路径点（不推进索引）
					local currentWaypoint = PathService.GetNextWaypoint(unitInstance)
					if currentWaypoint then
						humanoid:MoveTo(currentWaypoint)
						DebugLog(string.format("🔄 %s 重试当前路径点", unitId))
					else
						-- 路径点无效，直线移动到目标
						humanoid:MoveTo(data.TargetCFrame.Position)
					end
				else
					-- 路径失效，需要重新寻路
					DebugLog(string.format("🔄 %s 路径失效，重新寻路", unitId))

					-- 🔑 关键修复：重试寻路时必须遵守"先 true，回调结束再 false"的约定
					-- 防止同一单位被重复入队
					if not data.PathRequested then
						data.PathRequested = true

						-- 重新加入限流队列
						QueuePathCompute(unitInstance, data.TargetPart, unitId, function(success, pathState)
							-- 🔑 关键：回调结束时无论成功失败都要重置
							data.PathRequested = false

							-- V2.0修复：检查任务是否已被取消
							if data.Arrived or data.Cancelled then
								DebugLog(string.format("⛔ %s 任务已取消，忽略重试回调", unitId))
								return
							end

							if success and pathState and pathState.Status == PathStatus.SUCCESS then
								local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
								if nextWaypoint then
									humanoid:MoveTo(nextWaypoint)
									DebugLog(string.format("🚀 %s 重新寻路成功", unitId))
								else
									humanoid:MoveTo(data.TargetCFrame.Position)
								end
							else
								-- 寻路失败，直线移动
								humanoid:MoveTo(data.TargetCFrame.Position)
								DebugLog(string.format("⚠️ %s 重新寻路失败，直线移动", unitId))
							end
						end)
					else
						-- 已经在排队中，直接直线移动到目标
						humanoid:MoveTo(data.TargetCFrame.Position)
						DebugLog(string.format("⏳ %s 正在寻路中，临时直线移动", unitId))
					end
				end
			else
				-- 关键修复2：reached=true，正常到达当前路径点，推进到下一个
				local pathStatus = PathService.GetPathStatus(unitInstance)
				if pathStatus == PathStatus.SUCCESS then
					-- 推进到下一个路径点
					if not PathService.AdvancePath(unitInstance) then
						-- 路径走完，直接移动到最终目标
						humanoid:MoveTo(data.TargetCFrame.Position)
						DebugLog(string.format("📍 %s 路径走完，直线移动到目标", unitId))
					else
						local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
						if nextWaypoint then
							humanoid:MoveTo(nextWaypoint)
						else
							humanoid:MoveTo(data.TargetCFrame.Position)
						end
					end
				else
					-- 路径失败，直线移动
					humanoid:MoveTo(data.TargetCFrame.Position)
				end
			end
		end)

		-- V2.0.4新增：注册持续MoveTo推进的Heartbeat连接
		-- 这样即使MoveToFinished被挤停（reached=false），也能在Heartbeat中持续重试
		local lastContinuousMove = 0
		data.HeartbeatConn = RunService.Heartbeat:Connect(function()
			-- V2.0.4：检查任务是否已完成或取消
			if data.Arrived or data.Cancelled or not unitInstance or not unitInstance.Parent then
				if data.HeartbeatConn then
					data.HeartbeatConn:Disconnect()
					data.HeartbeatConn = nil
				end
				return
			end

			local now = tick()
			-- 每0.1s尝试一次持续推进
			if now - lastContinuousMove < 0.1 then
				return
			end
			lastContinuousMove = now

			-- 获取当前路径点或目标位置
			local targetPos = nil
			local pathStatus = PathService.GetPathStatus(unitInstance)

			if pathStatus == PathStatus.SUCCESS then
				-- 路径有效，获取当前路径点
				local currentWaypoint = PathService.GetNextWaypoint(unitInstance)
				if currentWaypoint then
					targetPos = currentWaypoint
					data.CurrentWaypoint = currentWaypoint
				else
					targetPos = data.TargetCFrame.Position
				end
			else
				-- 路径无效或无路径，直线移动到目标
				targetPos = data.TargetCFrame.Position
			end

			-- 检查是否还需要移动（距离阈值）
			if targetPos then
				local currentPos = rootPart.Position
				local distance = (currentPos - targetPos).Magnitude

				-- 只有在距离超过阈值时才发送MoveTo
				if distance > CONFIG.WAYPOINT_REACH_THRESHOLD then
					-- 更新LastMoveCommand时间
					data.LastMoveCommand = now

					-- 发送持续的MoveTo命令
					pcall(function()
						humanoid:MoveTo(targetPos)
					end)

					DebugLog(string.format("📍 %s 持续推进: 距离=%.1f studs", unitId, distance))
				end
			end
		end)

		-- 请求路径（加入限流队列）
		if not data.PathRequested then
			data.PathRequested = true
			QueuePathCompute(unitInstance, data.TargetPart, unitId, function(success, pathState)
				-- 🔑 关键：回调结束时无论成功失败都要重置
				data.PathRequested = false

				-- V2.0修复：检查任务是否已被取消
				if data.Arrived or data.Cancelled then
					DebugLog(string.format("⛔ %s 任务已取消，忽略回调", unitId))
					return
				end

				if success and pathState and pathState.Status == PathStatus.SUCCESS then
					-- 路径计算成功，开始移动
					local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
					if nextWaypoint then
						humanoid:MoveTo(nextWaypoint)
						DebugLog(string.format("🚀 %s 开始移动", unitId))
					else
						humanoid:MoveTo(data.TargetCFrame.Position)
					end
				else
					-- 路径计算失败，直线移动
					humanoid:MoveTo(data.TargetCFrame.Position)
					DebugLog(string.format("⚠️ %s 寻路失败，直线移动", unitId))
				end
			end)
		end
	end

	-- 2. 分批启动单位（避免瞬时大量ComputeAsync）
	local startedCount = 0
	local batchSize = CONFIG.BATCH_START_SIZE
	local batchDelay = CONFIG.BATCH_START_DELAY

	task.spawn(function()
		while startedCount < #unitsList do
			local batchEnd = math.min(startedCount + batchSize, #unitsList)
			for i = startedCount + 1, batchEnd do
				StartUnitMovement(unitsList[i])
			end
			startedCount = batchEnd

			if startedCount < #unitsList then
				DebugLog(string.format("🔄 批量启动进度: %d/%d", startedCount, #unitsList))
				task.wait(batchDelay)
			end
		end
	end)

	-- 3. 定期检查超时和完成状态（降低频率）
	local lastCheckTime = tick()
	local checkConnection
	checkConnection = RunService.Heartbeat:Connect(function()
		local now = tick()

		-- 节流：每CONFIG.BATCH_UPDATE_INTERVAL秒检查一次
		if now - lastCheckTime < CONFIG.BATCH_UPDATE_INTERVAL then
			return
		end
		lastCheckTime = now

		local allArrived = true
		local arrivedCount = 0

		for unitInstance, data in pairs(moveData) do
			if not data.Arrived then
				-- 检查实例有效性
				if not unitInstance or not unitInstance.Parent or not unitInstance:FindFirstChild("HumanoidRootPart") then
					data.Arrived = true
					if data.MoveToConnection then
						data.MoveToConnection:Disconnect()
						data.MoveToConnection = nil
					end
					-- V2.0.4新增：断开Heartbeat连接
					if data.HeartbeatConn then
						data.HeartbeatConn:Disconnect()
						data.HeartbeatConn = nil
					end
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end
					table.insert(failedList, unitInstance)
					arrivedCount = arrivedCount + 1
					continue
				end

				-- 超时检测
				if now - data.StartTime > GameConfig.Campaign.MoveTimeout then
					warn(string.format("[PathService] ⏱️ 兵种寻路超时，强制传送: %s", unitInstance.Name))

					local rootPart = unitInstance.HumanoidRootPart
					rootPart.CFrame = data.TargetCFrame

					data.Arrived = true
					data.ForceTeleported = true
					arrivedCount = arrivedCount + 1

					-- 清理
					if data.MoveToConnection then
						data.MoveToConnection:Disconnect()
						data.MoveToConnection = nil
					end
					-- V2.0.4新增：断开Heartbeat连接
					if data.HeartbeatConn then
						data.HeartbeatConn:Disconnect()
						data.HeartbeatConn = nil
					end
					PathService.ClearPath(unitInstance)
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end

					table.insert(timedOutList, unitInstance)

					-- 触发回调
					if onUnitArrived then
						pcall(function()
							onUnitArrived(unitInstance, "TimedOut")
						end)
					end
				else
					allArrived = false
				end
			else
				arrivedCount = arrivedCount + 1
			end
		end

		-- 所有兵种到达
		if allArrived then
			checkConnection:Disconnect()
			activeMoves[moveId] = nil

			print(string.format("[PathService] ✅ 批量寻路完成，到达: %d/%d", arrivedCount, moveCount))

			-- 清理所有连接和资源
			for unitInstance, data in pairs(moveData) do
				if data.MoveToConnection then
					data.MoveToConnection:Disconnect()
					data.MoveToConnection = nil
				end
				if data.TargetPart and data.TargetPart.Parent then
					data.TargetPart:Destroy()
				end
			end

			-- 触发onAllSettled回调
			if onAllSettled then
				pcall(function()
					onAllSettled(arrivedList, timedOutList, failedList)
				end)
			end
		end
	end)

	-- 存储连接和数据，以便取消
	activeMoves[moveId] = {
		connection = checkConnection,
		moveData = moveData
	}

	return moveId
end

--[[
取消批量移动任务
@param moveId string - 移动任务ID
V2.0修复：清空computeQueue中的请求，防止已取消的单位继续寻路
]]
function PathService.CancelGroupMove(moveId)
	local moveTask = activeMoves[moveId]
	if not moveTask then
		return false
	end

	-- 断开Heartbeat连接
	if moveTask.connection then
		moveTask.connection:Disconnect()
	end

	-- V2.0修复：从computeQueue中移除此任务相关的路径请求
	local cancelledCount = 0
	for i = #computeQueue, 1, -1 do
		local request = computeQueue[i]
		local data = moveTask.moveData[request.unitInstance]
		if data then
			-- 找到了此任务相关的请求，移除它
			table.remove(computeQueue, i)
			cancelledCount = cancelledCount + 1
		end
	end

	if cancelledCount > 0 then
		DebugLog(string.format("从队列中移除 %d 个未处理的路径请求", cancelledCount))
	end

	-- 清理所有单位的路径、事件连接和目标Part
	for unitInstance, data in pairs(moveTask.moveData) do
		-- V2.0修复：标记为已取消，防止回调继续推进
		data.Arrived = true  -- 标记为已完成（取消也算完成）
		data.Cancelled = true  -- 标记为已取消

		-- 断开MoveToFinished事件连接
		if data.MoveToConnection then
			data.MoveToConnection:Disconnect()
			data.MoveToConnection = nil
		end

		-- V2.0.4新增：断开Heartbeat连接
		if data.HeartbeatConn then
			data.HeartbeatConn:Disconnect()
			data.HeartbeatConn = nil
		end

		-- 清理路径
		PathService.ClearPath(unitInstance)

		-- 删除目标Part
		if data.TargetPart and data.TargetPart.Parent then
			data.TargetPart:Destroy()
			data.TargetPart = nil  -- 防止重复Destroy
		end

		-- 停止移动
		local humanoid = unitInstance and unitInstance:FindFirstChild("Humanoid")
		if humanoid then
			local rootPart = unitInstance:FindFirstChild("HumanoidRootPart")
			if rootPart then
				humanoid:MoveTo(rootPart.Position)
			end
		end
	end

	activeMoves[moveId] = nil

	DebugLog("取消批量移动任务:", moveId, "清理队列请求:", cancelledCount)
	return true
end

return PathService
