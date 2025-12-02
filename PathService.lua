--[[
脚本名称: PathService
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/PathService
版本: V2.4 - 修复兵种原地转圈问题

职责：
1. 统一管理所有单位的路径状态
2. 封装PathfindingService，提供简洁的接口
3. 自动处理体型参数、重试、阻挡、降级
4. 提供多级回退策略
5. 集中调试可视化和日志
6. V2.4新增：修复路径计算前MoveTo导致原地转圈的问题

核心设计原则：
- 单一职责：只负责路径计算和管理，不涉及AI逻辑
- 异步处理：避免瞬间大量ComputeAsync
- 防御式编程：深拷贝数据，避免引用失效
- 智能降级：多级回退策略，确保单位总能移动
- V2.4新增：等待路径完成再移动，避免Humanoid自行寻路

V2.4修复要点：
- 路径状态为COMPUTING/QUEUED时，不执行MoveTo，原地等待
- 增加ForceStraightMove标志，只有多次失败后才允许直线移动
- 增加PathFailureCount计数，追踪失败次数
- 启动时不直接MoveTo目标，等待路径计算完成
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
	-- 路径请求冷却（秒）- V2.2优化：分档冷却
	PATH_RECALC_COOLDOWN_MARCH = 0.3,   -- 行军模式：保持响应性
	PATH_RECALC_COOLDOWN_BATTLE = 0.6,  -- 战斗模式：减少重算频率
	PATH_RECALC_COOLDOWN = 0.3,         -- 默认值（向后兼容）

	-- 目标移动阈值（studs）- V2.2优化：提高阈值避免频繁重算
	TARGET_MOVE_THRESHOLD = 35,  -- 从15提高到35，减少重算

	-- Waypoint到达阈值（studs）- V2.3修复：保持2避免卡在阈值
	WAYPOINT_REACH_THRESHOLD = 2,

	-- 最大重试次数
	MAX_RETRY_COUNT = 3,

	-- 连续阻挡次数上限 - V2.5优化：降低到1，立即触发重寻
	MAX_BLOCKED_COUNT = 1,

	-- 阻挡时间窗口（秒）- V2.5优化：缩短到0.5秒，更快响应
	BLOCKED_TIME_WINDOW = 0.5,

	-- 降级策略：减小AgentRadius的比例
	RADIUS_REDUCTION_RATIO = 0.85,
	
	-- V2.2: Multi-level fallback strategy
	RADIUS_REDUCTION_STEP2 = 0.75,  -- Second level
	RADIUS_REDUCTION_STEP3 = 0.6,   -- Third level

	-- 降级策略：最小AgentRadius
	MIN_AGENT_RADIUS = 0.5,

	-- 近邻点采样半径（studs）
	NEIGHBOR_SAMPLE_RADIUS = 10,

	-- 近邻点采样数量
	NEIGHBOR_SAMPLE_COUNT = 8,

	-- 体型参数缓存时间（秒），-1表示永久缓存
	AGENT_PARAMS_CACHE_TIME = -1,

	-- 路径参数
	WAYPOINT_SPACING = 4,  -- V2.2: from 6 to 4, better corners

	-- 体型参数自动计算
	AUTO_RADIUS_MULTIPLIER = 0.25,  -- max(X,Z) * 0.25
	AUTO_RADIUS_OFFSET = 0.2,       -- + 0.2 容差
	AUTO_HEIGHT_OFFSET = 1,         -- Y + 1 容差

	-- V2.2性能优化：大幅提升吞吐量
	-- V2.4优化：P0阶段参数调整（保守升级）
	BATCH_UPDATE_INTERVAL = 0.06,   -- 从0.08→0.06（加速队列处理）
	MAX_COMPUTE_PER_FRAME = 15,     -- 从10→15（提升吞吐量但避免尖峰）
	-- 动态调整：实际值为 min(MAX_COMPUTE_PER_FRAME, queueLength)

	-- V2.2优化：动态并发限制（不再硬编码）
	BATCH_START_DELAY = 0.25,       -- 批量启动延迟（秒）
	BATCH_START_SIZE = 6,           -- 每批启动的单位数量
	MARCH_BATCH_LIMIT_MIN = 20,     -- 最小并发数
	MARCH_BATCH_LIMIT_RATIO = 0.5,  -- 动态比例：max(20, ceil(totalUnits * 0.5))
	MARCH_TIMEOUT = 30,             -- 单位行军超时时间（秒）

	-- 调试选项
	DEBUG_SHOW_PATH = false,        -- 是否显示路径可视化
	DEBUG_PATH_LOGS = false,        -- 是否打印详细日志
	DEBUG_WAIT_PATH_LOGS = false,   -- V2.4新增：是否打印等待路径的日志
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

-- V2.0.5前置声明：避免调用nil值
local QueuePathCompute  -- 前置声明，稍后定义

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

	-- 策略1.5: 第二级降级（更小半径）
	if pathState.Retries == 1 then
		local originalRadius = pathState.AgentParams.Radius
		local reducedRadius = math.max(CONFIG.MIN_AGENT_RADIUS, originalRadius * CONFIG.RADIUS_REDUCTION_STEP2)

		DebugLog(string.format("%s [Fallback-1.5] Radius: %.1f → %.1f", unitId, originalRadius, reducedRadius))

		local newParams = {
			Radius = reducedRadius,
			Height = pathState.AgentParams.Height,
			CanJump = pathState.AgentParams.CanJump,
		}

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
				pathState.Path = path
				pathState.Waypoints = DeepCopyWaypoints(waypoints)
				pathState.Index = 2
				pathState.AgentParams = newParams
				pathState.Status = PathStatus.SUCCESS
				pathState.LastTargetPos = targetPos
				pathState.Retries = 0

				DrawPath(pathState.Waypoints, pathState)
				DebugLog(string.format("%s [Fallback-1.5] Success! %d waypoints", unitId, #pathState.Waypoints))
				return true
			end
		end

		path:Destroy()
	end

	-- 策略1.75: 第三级降级（最小半径）
	if pathState.Retries == 2 then
		local originalRadius = pathState.AgentParams.Radius
		local reducedRadius = math.max(CONFIG.MIN_AGENT_RADIUS, originalRadius * CONFIG.RADIUS_REDUCTION_STEP3)

		DebugLog(string.format("%s [Fallback-1.75] Radius: %.1f → %.1f", unitId, originalRadius, reducedRadius))

		local newParams = {
			Radius = reducedRadius,
			Height = pathState.AgentParams.Height,
			CanJump = pathState.AgentParams.CanJump,
		}

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
				pathState.Path = path
				pathState.Waypoints = DeepCopyWaypoints(waypoints)
				pathState.Index = 2
				pathState.AgentParams = newParams
				pathState.Status = PathStatus.SUCCESS
				pathState.LastTargetPos = targetPos
				pathState.Retries = 0

				DrawPath(pathState.Waypoints, pathState)
				DebugLog(string.format("%s [Fallback-1.75] Success! %d waypoints", unitId, #pathState.Waypoints))
				return true
			end
		end

		path:Destroy()
	end

	-- 策略2: 采样近邻点
	if pathState.Retries == 3 then
		DebugLog(string.format("%s [Fallback-2] Sample neighbor", unitId))

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

			-- V2.3修复：连续阻挡次数过多，立即清理路径并高优先级重寻
			if pathState.BlockedCount >= CONFIG.MAX_BLOCKED_COUNT then
				DebugLog(string.format("%s 路径连续阻挡%d次，立即重寻", unitId, pathState.BlockedCount))

				-- 清理旧路径
				ClearPathData(unitModel)
				pathState.Status = PathStatus.NEED_REPATH
				pathState.BlockedCount = 0
				pathState.LastRequestTime = 0  -- 允许立即重建

				-- V2.3关键修复：立即高优先级入队重寻，不等待下一帧
				QueuePathCompute(unitModel, targetModel, unitId, nil, "Campaign", "high")

				DebugLog(string.format("%s 已入队高优先级重寻", unitId))
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
请求路径（异步版本，用于战斗AI）- V2.0.5性能优化
走限流队列，避免频繁ComputeAsync
@param unitModel - 兵种模型
@param targetModel - 目标模型
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

	-- 目标Part（支持传Model或Part，ComputeQueue传Part更稳）
	local targetPart = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart
	if not targetPart then
		if callback then
			pcall(function() callback(false, nil) end)
		end
		return false
	end

	-- 入队限流（复用现有队列）
	QueuePathCompute(unitModel, targetPart, unitId or tostring(unitModel), function(success, pathState)
		if callback then
			pcall(function()
				callback(success, pathState)
			end)
		end
	end)

	return true
end

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

-- ==================== V2.2性能优化: 拆分队列与三段式优先级 ====================

-- V2.2新增：分离Campaign和Battle队列，防止相互干扰
-- 每个队列内部使用三段式优先级（high/medium/low），替代O(n²logn)的table.sort
local campaignQueue = {
	high = {},    -- 高优先级（距离<20studs）
	medium = {},  -- 中优先级（20-50studs）
	low = {}      -- 低优先级（>50studs）
}
local battleQueue = {
	high = {},
	medium = {},
	low = {}
}

local computingCount = 0  -- 当前正在计算的数量
local lastComputeCheckTime = 0

-- V2.2新增：优先级计算函数（基于距离）- 返回字符串"high"/"medium"/"low"
local function CalculatePathPriority(unitInstance, targetPart)
	local rootPart = unitInstance and unitInstance:FindFirstChild("HumanoidRootPart")
	if not rootPart or not targetPart then
		return "low"
	end

	local distance = (rootPart.Position - targetPart.Position).Magnitude

	if distance < 20 then
		return "high"  -- 即将接敌
	elseif distance < 50 then
		return "medium"
	else
		return "low"
	end
end

-- V2.2新增：获取总队列长度（用于动态调整MAX_COMPUTE_PER_FRAME）
local function GetTotalQueueLength()
	local total = 0
	for _, queue in ipairs({campaignQueue, battleQueue}) do
		total = total + #queue.high + #queue.medium + #queue.low
	end
	return total
end

-- 性能统计数据
local performanceStats = {
	TotalPathRequests = 0,       -- 总路径请求数
	TotalComputeAsync = 0,       -- 总ComputeAsync调用数
	QueuedRequests = 0,          -- 当前队列中的请求数
	ActiveMoveTasks = 0,         -- 当前活跃的移动任务数
	TotalUnitsMoving = 0,        -- 当前正在移动的单位数
	LastResetTime = tick(),      -- 上次重置时间

	-- V2.0.5新增：战斗寻路性能统计
	BattlePathComputes = 0,      -- 战斗寻路ComputeAsync调用数
	CampaignPathComputes = 0,    -- 战役寻路ComputeAsync调用数
	AverageComputeTime = 0,      -- 平均ComputeAsync耗时（秒）
}

--[[
获取性能统计数据
@return table - 统计数据
]]
function PathService.GetPerformanceStats()
	performanceStats.QueuedRequests = GetTotalQueueLength()  -- V2.2：使用新的总队列长度函数
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
	performanceStats.BattlePathComputes = 0       -- V2.0.5新增
	performanceStats.CampaignPathComputes = 0     -- V2.0.5新增
	performanceStats.AverageComputeTime = 0       -- V2.0.5新增
	performanceStats.LastResetTime = tick()
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
将路径计算请求加入队列（V2.2重构：三段式优先级队列，O(1)入队）
@param unitInstance - 单位实例
@param targetPart - 目标Part
@param unitId - 单位ID
@param callback - 完成回调 function(success, pathState)
@param pathType - 路径类型："Battle"或"Campaign"（默认"Battle"）
@param priority - 优先级（可选，自动计算）
]]
QueuePathCompute = function(unitInstance, targetPart, unitId, callback, pathType, priority)
	pathType = pathType or "Battle"
	priority = priority or CalculatePathPriority(unitInstance, targetPart)

	-- V2.2：根据pathType选择队列
	local queue = (pathType == "Campaign") and campaignQueue or battleQueue

	-- V2.2优化：检查是否已在队列中（遍历所有优先级）
	for _, priorityName in ipairs({"high", "medium", "low"}) do
		local subQueue = queue[priorityName]
		for i, request in ipairs(subQueue) do
			if request.unitInstance == unitInstance then
				-- 更新现有请求
				if request.targetPart and request.targetPart:IsA("Part") and request.targetPart.Name == "TempTarget" then
					pcall(function() request.targetPart:Destroy() end)
				end

				request.targetPart = targetPart
				request.callback = callback
				request.pathType = pathType
				request.queueTime = tick()

				-- V2.2关键优化：如果优先级改变，从旧队列移除并加入新队列
				if priorityName ~= priority then
					table.remove(subQueue, i)
					table.insert(queue[priority], {
						unitInstance = unitInstance,
						targetPart = targetPart,
						unitId = unitId,
						callback = callback,
						queueTime = tick(),
						pathType = pathType,
					})
					DebugLog(string.format("请求优先级变更: %s (%s → %s)", unitId, priorityName, priority))
				end
				return
			end
		end
	end

	-- V2.2：新增请求，直接插入对应优先级队列（O(1)，无需排序）
	table.insert(queue[priority], {
		unitInstance = unitInstance,
		targetPart = targetPart,
		unitId = unitId,
		callback = callback,
		queueTime = tick(),
		pathType = pathType,
	})

	performanceStats.TotalPathRequests = performanceStats.TotalPathRequests + 1
	DebugLog(string.format("入队成功: %s (%s,%s) 总队列长度:%d", unitId, pathType, priority, GetTotalQueueLength()))
end

--[[
处理路径计算队列（V2.2重构：三段式优先级队列+动态吞吐）
核心改进：
1. 三段式遍历（high → medium → low），O(1)出队
2. 动态MAX_COMPUTE_PER_FRAME：min(20, queueLength)
3. 动态BATCH_UPDATE_INTERVAL：队列积压时加速处理
4. Campaign/Battle分离，互不干扰
]]
local function ProcessComputeQueue()
	local now = tick()
	local queueLength = GetTotalQueueLength()

	-- V2.2优化：动态节流间隔（队列积压时加速）
	local updateInterval = (queueLength > 20) and 0.05 or CONFIG.BATCH_UPDATE_INTERVAL
	if now - lastComputeCheckTime < updateInterval then
		return
	end
	lastComputeCheckTime = now

	-- V2.2优化：动态并发限制（根据队列长度调整）
	local maxCompute = math.min(CONFIG.MAX_COMPUTE_PER_FRAME, queueLength)

	-- V2.3修复：按比例分配配额，避免Campaign队列饥饿
	-- 战斗队列获得60%配额，战役队列获得40%配额
	local battleQuota = math.ceil(maxCompute * 0.6)
	local campaignQuota = math.ceil(maxCompute * 0.4)

	-- V2.2：三段式优先级遍历（高→中→低）
	local function ProcessSingleQueue(queue, queueName, quota)
		local processed = 0
		for _, priorityName in ipairs({"high", "medium", "low"}) do
			local subQueue = queue[priorityName]
			while #subQueue > 0 and computingCount < maxCompute and processed < quota do
				local request = table.remove(subQueue, 1)  -- O(1) 出队

				-- 跳过无效请求
				if not request.unitInstance or not request.unitInstance.Parent then
					DebugLog(string.format("⚠️ 跳过无效请求: 单位已删除 (%s)", queueName))
					continue
				end

				if not request.targetPart or not request.targetPart.Parent then
					DebugLog(string.format("⚠️ 跳过无效请求: 目标已删除 (%s,%s)", queueName, request.unitId or "Unknown"))
					if request.callback then
						pcall(function()
							request.callback(false, nil)
						end)
					end
					continue
				end

				computingCount = computingCount + 1
				processed = processed + 1
				performanceStats.TotalComputeAsync = performanceStats.TotalComputeAsync + 1

				-- 分类统计
				if request.pathType == "Campaign" then
					performanceStats.CampaignPathComputes = performanceStats.CampaignPathComputes + 1
				else
					performanceStats.BattlePathComputes = performanceStats.BattlePathComputes + 1
				end

				-- 异步执行路径计算（pcall保护）
				task.spawn(function()
					local success = false
					local pathState = nil

					local pcallSuccess, pcallError = pcall(function()
						success = PathService.RequestPath(request.unitInstance, request.targetPart, request.unitId)
						pathState = GetPathState(request.unitInstance)
					end)

					if not pcallSuccess then
					end

					-- 无论成功失败，都减少 computingCount
					computingCount = computingCount - 1

					-- 触发回调
					if request.callback then
						pcall(function()
							request.callback(success, pathState)
						end)
					end
				end)
			end
		end
		return processed
	end

	-- 先处理战斗队列（战斗配额60%）
	local battleProcessed = ProcessSingleQueue(battleQueue, "Battle", battleQuota)
	-- 再处理战役队列（战役配额40%）
	local campaignProcessed = ProcessSingleQueue(campaignQueue, "Campaign", campaignQuota)

	-- 如果某个队列没用完配额，另一个队列可以补充使用剩余slot
	if battleProcessed < battleQuota and computingCount < maxCompute then
		ProcessSingleQueue(campaignQueue, "Campaign", maxCompute - computingCount)
	elseif campaignProcessed < campaignQuota and computingCount < maxCompute then
		ProcessSingleQueue(battleQueue, "Battle", maxCompute - computingCount)
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
5. V2.3新增：支持缓存路径，避免重复ComputeAsync
6. V2.7新增：到达后朝向战场中心

@param moveTargets table - {[unitInstance] = targetCFrame, ...}
@param callbacks table - 回调函数表 {
    onUnitArrived = function(unitInstance, status),  -- 单位到达时回调
    onAllSettled = function(arrivedList, timedOutList, failedList),  -- 所有单位完成时回调
    battleCenter = Vector3 (optional) - 战场中心位置，到达后兵种会朝向此位置
}
@return string - 移动任务ID，可用于取消
]]
function PathService.MoveUnitsToPositions(moveTargets, callbacks)  -- V2.3.1：移除cachedWaypoints参数
	if not moveTargets or type(moveTargets) ~= "table" then
		return nil
	end

	-- 兼容旧版API：callbacks可以是function（相当于onAllSettled）
	local onUnitArrived = nil
	local onAllSettled = nil
	local battleCenter = nil  -- V2.7新增：战场中心位置

	if type(callbacks) == "function" then
		onAllSettled = callbacks  -- 向后兼容
	elseif type(callbacks) == "table" then
		onUnitArrived = callbacks.onUnitArrived
		onAllSettled = callbacks.onAllSettled
		battleCenter = callbacks.battleCenter  -- V2.7新增：提取战场中心
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

	-- V2.1.3新增：内部分批调度
	local pendingQueue = {}  -- 等待启动的单位队列
	local marchingCount = 0  -- 当前正在行军的单位数量

	-- 1. 准备所有单位数据
	for unitInstance, targetCFrame in pairs(moveTargets) do
		if unitInstance and unitInstance:FindFirstChild("Humanoid") and (unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart) then
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
				StartTime = 0,  -- V2.1.3修正：实际启动时才设置StartTime
				LastPathRequest = 0,
				MoveToConnection = nil,  -- MoveToFinished连接
				PathRequested = false,   -- 是否已请求路径

				-- V2.0.4新增：持续MoveTo推进（V2.3：已整合到批处理器）
				LastMoveCommand = 0,     -- 上次发送MoveTo命令的时间
				CurrentWaypoint = nil,   -- 当前目标路径点

				-- V2.2: Stuck detection
				LastPosition = nil,         -- Last known position
				LastPositionTime = 0,       -- Time when position was recorded

				-- V2.4新增：防止路径计算前MoveTo导致原地转圈
				ForceStraightMove = false,  -- 是否强制直线移动（多次寻路失败后）
				PathFailureCount = 0,       -- 路径失败计数
			}

			table.insert(unitsList, unitInstance)
			moveCount = moveCount + 1
		end
	end

	if moveCount == 0 then
		if onAllSettled then
			onAllSettled({}, {}, {})
		end
		return nil
	end

	-- V2.2优化：动态计算并发限制 max(20, ceil(moveCount * 0.5))
	local dynamicBatchLimit = math.max(CONFIG.MARCH_BATCH_LIMIT_MIN, math.ceil(moveCount * CONFIG.MARCH_BATCH_LIMIT_RATIO))

	DebugLog(string.format("[PathService] 批量寻路开始，兵种数量: %d, MoveId: %s, 动态批次限制: %d (基于%d单位)",
		moveCount, moveId, dynamicBatchLimit, moveCount))

	-- ==================== 核心逻辑：事件驱动移动 ====================

	-- V2.1.3新增：前向声明
	local TryStartNextBatch  -- 前置声明，稍后定义
	local StartUnitMovement  -- 前置声明，稍后定义

	--[[
	V2.1.3新增：停止单位移动并播放Idle动画
	]]
	local function StopUnitMovement(unitInstance, reason)
		local data = moveData[unitInstance]
		if not data then return end

		local humanoid = unitInstance:FindFirstChild("Humanoid")
		local rootPart = unitInstance:FindFirstChild("HumanoidRootPart")

		-- V2.7修复：使用软停代替MoveTo(当前位置)，避免前倾抖动
		if humanoid then
			humanoid:Move(Vector3.zero, true)
		end

		-- 断开事件连接
		if data.MoveToConnection then
			data.MoveToConnection:Disconnect()
			data.MoveToConnection = nil
		end
		-- V2.3优化：HeartbeatConn已移除，不再需要断开

		-- 清理路径
		PathService.ClearPath(unitInstance)

		-- 播放Idle动画（如果有UnitAI或AnimationController）
		local animator = humanoid and humanoid:FindFirstChild("Animator")
		if animator then
			-- 停止所有正在播放的动画
			local tracks = animator:GetPlayingAnimationTracks()
			for _, track in ipairs(tracks) do
				track:Stop()
			end
		end

		DebugLog(string.format("⏹️ 单位已停止: %s (%s)", unitInstance.Name, reason or "未知原因"))
	end

	--[[
	V2.2优化：尝试从队列启动下一批单位（使用动态限制）
	V2.3.1修复：根据StartUnitMovement返回值决定是否增加marchingCount
	]]
	TryStartNextBatch = function()
		while marchingCount < dynamicBatchLimit and #pendingQueue > 0 do
			local unitInstance = table.remove(pendingQueue, 1)
			if unitInstance and unitInstance.Parent then
				-- V2.3.1：只有成功启动才增加marchingCount
				if StartUnitMovement(unitInstance) then
					marchingCount = marchingCount + 1
					DebugLog(string.format("🚀 从队列启动单位: %s (当前行军数: %d/%d)",
						unitInstance.Name, marchingCount, dynamicBatchLimit))
				end
			end
		end
	end

	--[[
	为单位启动移动（事件驱动）
	修复：
	1. 检查 reached 标志，避免盲目推进路径点
	2. 路径失效时重置 PathRequested 并重新入队
	V2.1.3修正：启动时才设置StartTime
	V2.3.1修正：返回布尔值，指示是否成功启动（解决marchingCount泄漏问题）
	@return boolean - true表示成功启动，false表示启动失败（无需占用并发槽位）
	]]
	StartUnitMovement = function(unitInstance)
		local data = moveData[unitInstance]
		-- V2.0修复：同时检查Arrived和Cancelled
		if not data or data.Arrived or data.Cancelled then
			-- V2.3.1：提前退出，返回false表示不应占用并发槽位
			return false
		end

		local humanoid = unitInstance:FindFirstChild("Humanoid")
		-- V2.3修复：支持HumanoidRootPart或PrimaryPart
		local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
		if not humanoid or not rootPart then
			-- V2.3.1修复：启动失败，标记为失败并返回false
			data.Arrived = true
			table.insert(failedList, unitInstance)
			DebugLog(string.format("⚠️ %s 缺少Humanoid或根部件，标记为失败", unitInstance.Name))
			return false
		end

		-- V2.3.2新增：启动移动前保险地确保解锚与移动能力
		-- 避免少数模型残留锚定/速度为0导致无法移动
		if rootPart.Anchored then
			rootPart.Anchored = false
			DebugLog(string.format("🔓 %s 解锚（启动移动前）", unitInstance.Name))
		end
		if humanoid.WalkSpeed <= 0 then
			humanoid.WalkSpeed = 16
			DebugLog(string.format("⚡ %s 恢复移动速度为16 (原值<=0)", unitInstance.Name))
		end

		-- V2.1.3新增：实际启动时才设置StartTime
		data.StartTime = tick()

		local unitId = unitInstance:GetAttribute("UnitId") or unitInstance.Name

		-- 关键修复2：检查 reached 标志的 MoveToFinished 回调
		data.MoveToConnection = humanoid.MoveToFinished:Connect(function(reached)
			-- V2.0修复：同时检查Arrived和Cancelled
			if data.Arrived or data.Cancelled then
				return
			end

			-- V2.1.3修复：无论 reached 是 true 还是 false，都先检查是否已接近最终目标
			local currentPos = rootPart.Position
			local targetPos = data.TargetCFrame.Position
			local distanceXZ = math.sqrt((currentPos.X - targetPos.X)^2 + (currentPos.Z - targetPos.Z)^2)
			local arrivalThreshold = GameConfig.Campaign.ArrivalThreshold or 8

			if distanceXZ < arrivalThreshold then
				-- 到达目标（无论 reached 是 true 还是 false）
				data.Arrived = true

				-- V2.7新增：到达后朝向战场中心
				if battleCenter and typeof(battleCenter) == "Vector3" then
					local lookAtPos = Vector3.new(battleCenter.X, rootPart.Position.Y, battleCenter.Z)
					local direction = (lookAtPos - rootPart.Position).Unit
					if direction.Magnitude > 0.1 then  -- 避免零向量
						local newCFrame = CFrame.new(rootPart.Position, rootPart.Position + direction)
						pcall(function()
							rootPart.CFrame = newCFrame
						end)
						DebugLog(string.format("🎯 %s 朝向战场中心", unitInstance.Name))
					end
				end

				-- 断开连接
				if data.MoveToConnection then
					data.MoveToConnection:Disconnect()
					data.MoveToConnection = nil
				end
				-- V2.3优化：HeartbeatConn已移除，不再需要断开

				-- 清理
				PathService.ClearPath(unitInstance)
				if data.TargetPart and data.TargetPart.Parent then
					data.TargetPart:Destroy()
				end

				table.insert(arrivedList, unitInstance)
				DebugLog(string.format("✅ 兵种到达: %s (距离=%.1f studs, reached=%s)", unitInstance.Name, distanceXZ, tostring(reached)))

				-- 触发回调
				if onUnitArrived then
					pcall(function()
						onUnitArrived(unitInstance, "Arrived")
					end)
				end

				-- V2.1.3新增：减少行军计数，尝试启动下一批
				marchingCount = marchingCount - 1
				TryStartNextBatch()

				return  -- 已到达，不再继续处理
			end

			-- 未到达目标，根据 reached 处理
			if not reached then
				-- V3.1修复：reached=false 立即高优先级重寻，不等待位置看门狗
				DebugLog(string.format("⚠️ %s MoveToFinished(reached=false)，立即高优先级重寻", unitId))

				-- 清理旧路径
				PathService.ClearPath(unitInstance)

				-- 立即高优先级重寻（绕过冷却）
				if not data.PathRequested then
					data.PathRequested = true

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
								DebugLog(string.format("🚀 %s reached=false重寻成功", unitId))
								-- 重寻成功，重置失败计数
								data.PathFailureCount = 0
							else
								-- 设置强制直线移动标志，允许直线移动
								data.ForceStraightMove = true
								humanoid:MoveTo(data.TargetCFrame.Position)
							end
						else
							-- 重寻失败，增加失败计数
							data.PathFailureCount = (data.PathFailureCount or 0) + 1
							if data.PathFailureCount >= CONFIG.MAX_RETRY_COUNT then
								-- 多次失败，允许强制直线移动
								data.ForceStraightMove = true
								DebugLog(string.format("⚠️ %s 多次重寻失败(%d次)，允许强制直线移动",
									unitId, data.PathFailureCount))
							end
							-- 设置强制直线移动标志
							data.ForceStraightMove = true
							humanoid:MoveTo(data.TargetCFrame.Position)
							DebugLog(string.format("⚠️ %s reached=false重寻失败，直线移动", unitId))
						end
					end, "Campaign", "high")  -- V3.1关键：高优先级重寻
				else
					-- V2.7修复：使用软停代替MoveTo(当前位置)，避免前倾抖动
					if humanoid then
						humanoid:Move(Vector3.zero, true)
					end
					DebugLog(string.format("⏳ %s 正在寻路队列中，原地待命", unitId))
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

		-- 注意：Roblox Humanoid 没有 MoveToBlocked 事件
		-- 已通过超时机制和批量检测来处理移动阻塞情况
		-- 如果需要更精确的阻塞检测，可以使用位置检测或 MoveToFinished 事件

		-- V2.3优化：移除per-unit Heartbeat连接
		-- 原V2.0.4的持续MoveTo推进逻辑已整合到checkConnection批处理器中
		-- 消除100个单位×10Hz=1000次/秒的Heartbeat回调开销

		-- 请求路径（加入限流队列）
		-- V2.3.1：移除缓存路径逻辑，所有单位使用真实起点per-unit寻路
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
						-- 路径成功，重置失败计数
						data.PathFailureCount = 0
					else
						-- 设置强制直线移动标志，允许使用兜底移动
						data.ForceStraightMove = true
						humanoid:MoveTo(data.TargetCFrame.Position)
					end
				else
					-- 路径计算失败，增加失败计数
					data.PathFailureCount = (data.PathFailureCount or 0) + 1
					if data.PathFailureCount >= CONFIG.MAX_RETRY_COUNT then
						-- 多次失败，允许强制直线移动
						data.ForceStraightMove = true
						DebugLog(string.format("⚠️ %s 多次寻路失败(%d次)，允许强制直线移动",
							unitId, data.PathFailureCount))
					end
					-- 设置强制直线移动标志
					data.ForceStraightMove = true
					humanoid:MoveTo(data.TargetCFrame.Position)
					DebugLog(string.format("⚠️ %s 寻路失败，直线移动", unitId))
				end
			end, "Campaign")  -- V2.0.5：标记为战役路径
		end

		-- V2.3.1：成功启动，返回true表示应占用并发槽位
		return true
	end

	-- 2. V2.2优化：分批启动单位，使用动态并发限制
	-- V2.3.1修复：根据StartUnitMovement返回值决定是否增加marchingCount
	for i = 1, #unitsList do
		if marchingCount < dynamicBatchLimit then
			-- V2.3.1：只有成功启动才增加marchingCount
			if StartUnitMovement(unitsList[i]) then
				marchingCount = marchingCount + 1
			end
		else
			table.insert(pendingQueue, unitsList[i])
		end
	end

	DebugLog(string.format("📊 批量寻路启动完成 - 立即启动: %d, 队列等待: %d, 动态限制: %d",
		marchingCount, #pendingQueue, dynamicBatchLimit))

	-- 保留旧的变量以兼容后续代码引用（实际不再使用task.spawn延迟启动）
	local startedCount = #unitsList  -- 所有单位都已分配（启动或排队）
	local batchSize = CONFIG.BATCH_START_SIZE
	local batchDelay = CONFIG.BATCH_START_DELAY

	-- V2.3.2新增：队列卡住兜底提额机制
	-- 记录上次成功启动下一批的时间，用于检测队列长期阻塞
	local lastBatchKickTime = tick()

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

		-- V2.3新增：批量处理所有单位的持续MoveTo推进
		-- 替代V2.0.4的per-unit Heartbeat，降低回调频率从1000次/秒到~60次/秒
		for unitInstance, data in pairs(moveData) do
			if not data.Arrived then
				-- V2.3.3关键修复：只要有一个单位未到达，本帧绝不可能全部到达
				-- 防止因为continue分支而误判allArrived=true
				allArrived = false

				-- V2.3修复：检查实例有效性，支持HumanoidRootPart或PrimaryPart
				local rootPart = (unitInstance and unitInstance:FindFirstChild("HumanoidRootPart")) or (unitInstance and unitInstance.PrimaryPart)
				if not unitInstance or not unitInstance.Parent or not rootPart then
					-- V2.1.3新增：停止单位移动
					StopUnitMovement(unitInstance, "实例失效")

					data.Arrived = true
					if data.MoveToConnection then
						data.MoveToConnection:Disconnect()
						data.MoveToConnection = nil
					end
					-- V2.3优化：移除HeartbeatConn断开（已不存在）
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end
					table.insert(failedList, unitInstance)
					arrivedCount = arrivedCount + 1
					DebugLog(string.format("⚠️ %s 实例失效，标记为失败", unitInstance and unitInstance.Name or "Unknown"))

					-- V2.1.3新增：减少行军计数，尝试启动下一批
					marchingCount = marchingCount - 1
					TryStartNextBatch()

					continue
				end

				-- V2.3新增：批量持续MoveTo推进逻辑（整合自V2.0.4的per-unit Heartbeat）
				-- 检查是否已接近最终目标
				-- V2.3修复：使用上面已获取的rootPart，而不是假设HumanoidRootPart存在
				local currentPos = rootPart.Position
				local finalTargetPos = data.TargetCFrame.Position
				local distanceXZToFinal = math.sqrt((currentPos.X - finalTargetPos.X)^2 + (currentPos.Z - finalTargetPos.Z)^2)
				local arrivalThreshold = GameConfig.Campaign.ArrivalThreshold or 8

				if distanceXZToFinal < arrivalThreshold then
					-- 已经接近最终目标，标记为到达
					data.Arrived = true

					-- 断开连接
					if data.MoveToConnection then
						data.MoveToConnection:Disconnect()
						data.MoveToConnection = nil
					end
					if data.MoveBlockedConnection then
						data.MoveBlockedConnection:Disconnect()
						data.MoveBlockedConnection = nil
					end

					-- 清理
					PathService.ClearPath(unitInstance)
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end

					table.insert(arrivedList, unitInstance)
					DebugLog(string.format("✅ 兵种到达 (批处理检测): %s (距离=%.1f studs)", unitInstance.Name, distanceXZToFinal))

					-- 触发回调
					if onUnitArrived then
						pcall(function()
							onUnitArrived(unitInstance, "Arrived")
						end)
					end

					-- V2.1.3新增：减少行军计数，尝试启动下一批
					marchingCount = marchingCount - 1
					TryStartNextBatch()

					arrivedCount = arrivedCount + 1
					-- continue到下一个单位
				else
					-- 未到达最终目标，持续推进MoveTo
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
						-- V2.3关键修复：路径失效/失败时，禁止直线MoveTo兜底
						-- 改为强制重新寻路，避免单位"直冲目标怼墙"
						if pathStatus == PathStatus.FAILED or pathStatus == PathStatus.NEED_REPATH or pathStatus == PathStatus.IDLE then
							-- 立即请求重新寻路（如果未在队列中）
							if not data.PathRequested then
								data.PathRequested = true
								DebugLog(string.format("🔄 %s 路径失效(%s)，强制重寻", unitInstance.Name, tostring(pathStatus)))

								QueuePathCompute(unitInstance, data.TargetPart, unitInstance.Name, function(success)
									data.PathRequested = false
									if success then
										DebugLog(string.format("✅ %s 重寻成功", unitInstance.Name))
										-- 重寻成功，重置失败计数
										data.PathFailureCount = 0
									else
										-- 重寻失败，增加失败计数
										data.PathFailureCount = (data.PathFailureCount or 0) + 1
										if data.PathFailureCount >= CONFIG.MAX_RETRY_COUNT then
											-- 多次失败，允许强制直线移动
											data.ForceStraightMove = true
											DebugLog(string.format("⚠️ %s 多次重寻失败(%d次)，允许强制直线移动",
												unitInstance.Name, data.PathFailureCount))
										end
									end
								end, "Campaign", "high")
							end
							-- V2.7修复：使用软停代替MoveTo(当前位置)，避免前倾抖动
							local humanoid = unitInstance:FindFirstChild("Humanoid")
							if humanoid then
								humanoid:Move(Vector3.zero, true)  -- 软停，停止移动但不触发前倾动画
							end
							-- V2.3.3保险：本单位未到达，防止allArrived被误判为true
							allArrived = false
							continue  -- 跳过本次MoveTo
						else
							-- V2.4修复：路径计算中(COMPUTING/QUEUED)时，不要设置targetPos
							-- 等待路径计算完成，避免Humanoid自行寻路导致原地转圈
							if pathStatus == PathStatus.COMPUTING or pathStatus == PathStatus.QUEUED then
								-- V2.7修复：路径计算中，保持等待即可（不再需要软停，因为没有提前播放动画）
								if CONFIG.DEBUG_WAIT_PATH_LOGS then
									DebugLog(string.format("⏳ %s 路径计算中(%s)，等待完成", unitInstance.Name, tostring(pathStatus)))
								end
								targetPos = nil  -- 设为nil，跳过本次MoveTo
								allArrived = false
								continue
							else
								-- 其他未知状态，且已设置强制直线移动标志时才允许直线移动
								if data.ForceStraightMove then
									targetPos = data.TargetCFrame.Position
								else
									targetPos = nil  -- 不强制移动，等待路径
								end
							end
						end
					end

					-- 检查是否还需要移动（距离阈值）
					if targetPos then
						local distance = (currentPos - targetPos).Magnitude

						-- 只有在距离超过阈值时才发送MoveTo
						if distance > CONFIG.WAYPOINT_REACH_THRESHOLD then
							-- V2.7增强：更严格的MoveTo节流，避免抖动
							local humanoid = unitInstance:FindFirstChild("Humanoid")
							if humanoid then
								local walkToPoint = humanoid.WalkToPoint
								local walkToDist = (walkToPoint - targetPos).Magnitude
								local timeSinceLastMove = now - (data.LastMoveCommand or 0)
								local isMoving = humanoid.MoveDirection.Magnitude > 0.05

								-- V2.7修复：已在向几乎相同的点移动且正在走，不重发
								if walkToDist < 0.8 and isMoving then
									allArrived = false
									continue
								end

								-- V2.7修复：同点重复发指令的时间防抖
								if walkToDist < 2.0 and timeSinceLastMove < 0.3 then
									allArrived = false
									continue
								end
							end

							-- 更新LastMoveCommand时间
							data.LastMoveCommand = now

							-- 发送持续的MoveTo命令
							local humanoid = unitInstance:FindFirstChild("Humanoid")
							if humanoid then
								pcall(function()
									humanoid:MoveTo(targetPos)
								end)
								DebugLog(string.format("📍 %s 批量推进: 距离=%.1f studs", unitInstance.Name, distance))
							end
						end
					end

					-- V3.1强化：卡住检测watchdog - 双重检测：位置变化+速度检测
				if data.StartTime > 0 then
					local currentPos = rootPart.Position
					local humanoid = unitInstance:FindFirstChild("Humanoid")
					local isStuck = false
					local stuckReason = ""

					-- V3.1新增：速度卡死检测 - 如果距离目标远但速度接近0持续0.8秒
					if humanoid and distanceXZToFinal > arrivalThreshold then
						local speed = humanoid.MoveDirection.Magnitude
						-- 初始化速度追踪
						if not data.LastLowSpeedTime then
							data.LastLowSpeedTime = 0
						end

						if speed < 0.05 then
							-- 速度很低
							if data.LastLowSpeedTime == 0 then
								data.LastLowSpeedTime = now
							elseif now - data.LastLowSpeedTime > 0.8 then
								-- 速度持续低于阈值超过0.8秒
								isStuck = true
								stuckReason = string.format("速度卡死(speed=%.3f持续%.1fs)", speed, now - data.LastLowSpeedTime)
								data.LastLowSpeedTime = 0  -- 重置，避免重复触发
							end
						else
							-- 速度恢复，重置计时
							data.LastLowSpeedTime = 0
						end
					end

					-- V3.1修改：位置卡住检测 - 放宽阈值从0.15到0.35 studs
					if data.LastPosition and not isStuck then
						local positionDelta = (currentPos - data.LastPosition).Magnitude
						local timeDelta = now - data.LastPositionTime

						-- V3.1优化：放宽卡住检测阈值（0.35 studs in 0.5s）
						if positionDelta < 0.35 and timeDelta > 0.5 and distanceXZToFinal > 5 then
							isStuck = true
							stuckReason = string.format("位置卡住(%.2f studs in %.1fs)", positionDelta, timeDelta)
						elseif timeDelta > 0.5 then
							-- 每0.5秒更新一次位置追踪
							data.LastPosition = currentPos
							data.LastPositionTime = now
						end
					elseif not data.LastPosition then
						-- 初始化位置追踪
						data.LastPosition = currentPos
						data.LastPositionTime = now
						allArrived = false
					end

					-- 卡住时强制高优先级重寻
					if isStuck then
						if not data.PathRequested then
							data.PathRequested = true
							DebugLog(string.format("🚨 %s 检测到%s，强制重寻",
								unitInstance.Name, stuckReason))

							-- 立即清理旧路径
							PathService.ClearPath(unitInstance)

							-- 高优先级重寻
							QueuePathCompute(unitInstance, data.TargetPart, unitInstance.Name,
								function(success)
									data.PathRequested = false
									if success then
										-- 重寻成功，立即开始移动
										local humanoid = unitInstance:FindFirstChild("Humanoid")
										if humanoid then
											local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
											if nextWaypoint then
												humanoid:MoveTo(nextWaypoint)
												DebugLog(string.format("✅ %s 重寻成功，恢复移动", unitInstance.Name))
											end
										end
										-- 重寻成功，重置失败计数
										data.PathFailureCount = 0
									else
										-- 重寻失败，增加失败计数
										data.PathFailureCount = (data.PathFailureCount or 0) + 1
										if data.PathFailureCount >= CONFIG.MAX_RETRY_COUNT then
											-- 多次失败，允许强制直线移动
											data.ForceStraightMove = true
											DebugLog(string.format("⚠️ %s 卡住重寻失败(%d次)，允许强制直线移动",
												unitInstance.Name, data.PathFailureCount))
										end
									end
								end, "Campaign", "high")
						end

						-- 更新位置追踪（避免重复触发）
						data.LastPosition = currentPos
						data.LastPositionTime = now
					end
				end

				-- 超时检测 - V2.3.1修复：只检测已启动的单位（StartTime > 0）
					-- 排队等待的单位 StartTime = 0，不应被视为超时
					if data.StartTime > 0 and now - data.StartTime > GameConfig.Campaign.MoveTimeout then

						-- V2.7修复：超时不再瞬移，改为重试机制
						local timeoutRetryCount = data.TimeoutRetryCount or 0

						if timeoutRetryCount < 2 then
							-- 重试寻路（最多2次）
							data.TimeoutRetryCount = timeoutRetryCount + 1
							data.StartTime = now  -- 重置超时计时器
							data.PathRequested = true

							DebugLog(string.format("⏰ %s 移动超时，尝试重新寻路 (第%d次重试)",
								unitInstance.Name, data.TimeoutRetryCount))

							-- 清理旧路径
							PathService.ClearPath(unitInstance)

							-- 高优先级重新寻路
							QueuePathCompute(unitInstance, data.TargetPart, unitInstance.Name,
								function(success)
									data.PathRequested = false
									if success then
										local humanoid = unitInstance:FindFirstChild("Humanoid")
										if humanoid then
											local nextWaypoint = PathService.GetNextWaypoint(unitInstance)
											if nextWaypoint then
												humanoid:MoveTo(nextWaypoint)
												DebugLog(string.format("✅ %s 超时重寻成功，恢复移动", unitInstance.Name))
												-- 重寻成功，重置到达状态
												data.Arrived = false
												return
											end
										end
									end
									-- 重寻失败，继续计时等待下次重试
									DebugLog(string.format("❌ %s 超时重寻失败", unitInstance.Name))
								end, "Campaign", "high")
						else
							-- 重试次数用尽，标记为超时失败（不瞬移）
							DebugLog(string.format("🚫 %s 超时重试次数用尽，停止移动", unitInstance.Name))

							-- V2.7修改：只停止移动，不改变位置
							StopUnitMovement(unitInstance, "超时")
							PathService.ClearPath(unitInstance)

							-- 标记为到达（实际是超时失败）
							data.Arrived = true
							data.ForceTeleported = false  -- V2.7：不再瞬移
							arrivedCount = arrivedCount + 1

							-- 清理
							if data.MoveToConnection then
								data.MoveToConnection:Disconnect()
								data.MoveToConnection = nil
							end
							if data.MoveBlockedConnection then
								data.MoveBlockedConnection:Disconnect()
								data.MoveBlockedConnection = nil
							end
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

							-- V2.1.3新增：减少行军计数，尝试启动下一批
							marchingCount = marchingCount - 1
							TryStartNextBatch()
						end
					else
						allArrived = false
					end
				end
			else
				arrivedCount = arrivedCount + 1
			end
		end

		-- V2.3.2新增：兜底启动下一批机制
		-- 即便没有单位完成（到达/超时/失败），也要持续放水
		-- 防止首批单位迟迟不出结果导致整个队列卡住
		if marchingCount < dynamicBatchLimit and #pendingQueue > 0 then
			TryStartNextBatch()
			lastBatchKickTime = now
			DebugLog(string.format("🔓 兜底启动下一批 (当前: %d/%d, 队列: %d)",
				marchingCount, dynamicBatchLimit, #pendingQueue))
		end

		-- V2.3.2新增：队列长期阻塞提额机制
		-- 如果队列积压超过1.5秒且队列有等待，则临时提高dynamicBatchLimit
		if #pendingQueue > 0 and now - lastBatchKickTime > 1.5 then
			if marchingCount >= dynamicBatchLimit then
				-- 队列积压超过1.5秒，提额5个单位
				local oldLimit = dynamicBatchLimit
				dynamicBatchLimit = math.min(moveCount, dynamicBatchLimit + 5)
				lastBatchKickTime = now
				DebugLog(string.format("⚠️ 队列积压提额: %d → %d, 队列等待: %d",
					oldLimit, dynamicBatchLimit, #pendingQueue))
				-- 立即启动提额后的单位
				TryStartNextBatch()
			end
		end

		-- V2.3.3最终兜底：用arrivedCount硬性校验，防止allArrived再次被遗漏
		-- 如果到达的单位数少于总单位数，说明还有单位未完成
		if arrivedCount < moveCount then
			allArrived = false
		end

		-- 所有兵种到达
		if allArrived then
			DebugLog(string.format("[PathService] 🎯 准备触发onAllSettled回调，到达:%d, 超时:%d, 失败:%d",
				#arrivedList, #timedOutList, #failedList))

			checkConnection:Disconnect()
			activeMoves[moveId] = nil

			DebugLog(string.format("[PathService] ✅ 批量寻路完成，到达: %d/%d", arrivedCount, moveCount))

			-- 清理所有连接和资源
			for unitInstance, data in pairs(moveData) do
				if data.MoveToConnection then
					data.MoveToConnection:Disconnect()
					data.MoveToConnection = nil
				end
				if data.MoveBlockedConnection then
					data.MoveBlockedConnection:Disconnect()
					data.MoveBlockedConnection = nil
				end
				if data.TargetPart and data.TargetPart.Parent then
					data.TargetPart:Destroy()
				end
			end

			-- 触发onAllSettled回调
			if onAllSettled then
				DebugLog("[PathService] 🚀 正在调用onAllSettled回调...")
				pcall(function()
					onAllSettled(arrivedList, timedOutList, failedList)
				end)
				DebugLog("[PathService] ✅ onAllSettled回调执行完成")
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
V2.3修复：从battleQueue和campaignQueue中清除请求，防止已取消的单位继续寻路
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

	-- V2.3修复：从battleQueue和campaignQueue中移除此任务相关的路径请求
	local cancelledCount = 0

	-- 遍历两个队列的所有优先级
	for _, queue in ipairs({battleQueue, campaignQueue}) do
		for _, priorityName in ipairs({"high", "medium", "low"}) do
			local subQueue = queue[priorityName]
			for i = #subQueue, 1, -1 do
				local request = subQueue[i]
				local data = moveTask.moveData[request.unitInstance]
				if data then
					-- 找到了此任务相关的请求，移除它
					table.remove(subQueue, i)
					cancelledCount = cancelledCount + 1
				end
			end
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
		if data.MoveBlockedConnection then
			data.MoveBlockedConnection:Disconnect()
			data.MoveBlockedConnection = nil
		end

		-- V2.3优化：移除HeartbeatConn断开（已不存在）

		-- 清理路径
		PathService.ClearPath(unitInstance)

		-- 删除目标Part
		if data.TargetPart and data.TargetPart.Parent then
			data.TargetPart:Destroy()
			data.TargetPart = nil  -- 防止重复Destroy
		end

		-- 停止移动
		-- V2.7修复：使用软停代替MoveTo(当前位置)，避免前倾抖动
		local humanoid = unitInstance and unitInstance:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:Move(Vector3.zero, true)
		end
	end

	activeMoves[moveId] = nil

	DebugLog("取消批量移动任务:", moveId, "清理队列请求:", cancelledCount)
	return true
end

--[[
获取路径状态（公共接口）
@param unitModel - 兵种模型
@return PathState|nil
]]
function PathService.GetPathState(unitModel)
	return pathStates[unitModel]
end

return PathService
