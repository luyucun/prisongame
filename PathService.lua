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
	PATH_RECALC_COOLDOWN = 0.5,

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
	NEIGHBOR_SAMPLE_RADIUS = 6,

	-- 近邻点采样数量
	NEIGHBOR_SAMPLE_COUNT = 8,

	-- 体型参数缓存时间（秒），-1表示永久缓存
	AGENT_PARAMS_CACHE_TIME = -1,

	-- 路径参数
	WAYPOINT_SPACING = 4,

	-- 体型参数自动计算
	AUTO_RADIUS_MULTIPLIER = 0.35,  -- max(X,Z) * 0.35
	AUTO_RADIUS_OFFSET = 0.2,       -- + 0.2 容差
	AUTO_HEIGHT_OFFSET = 1,         -- Y + 1 容差

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

--[[
批量移动兵种到指定位置（用于战役系统） - 重构版
使用真正的PathfindingService进行寻路，支持避障
@param moveTargets table - {[unitInstance] = targetCFrame, ...}
@param onAllArrived function - 所有兵种到达后的回调
]]
function PathService.MoveUnitsToPositions(moveTargets, onAllArrived)
	if not moveTargets or type(moveTargets) ~= "table" then
		warn("[PathService] MoveUnitsToPositions: moveTargets无效")
		return
	end

	local moveData = {}
	local moveCount = 0

	-- 1. 为每个单位创建虚拟目标Part并开始寻路
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
				StartTime = tick(),
				LastPathRequest = 0
			}

			-- 请求路径
			local unitId = unitInstance:GetAttribute("UnitId") or unitInstance.Name
			PathService.RequestPath(unitInstance, targetPart, unitId)

			moveCount = moveCount + 1
		end
	end

	if moveCount == 0 then
		warn("[PathService] MoveUnitsToPositions: 没有有效的移动目标")
		if onAllArrived then
			onAllArrived({})
		end
		return
	end

	print("[PathService] 批量寻路开始，兵种数量:", moveCount)

	-- 2. 持续更新单位移动
	local checkConnection
	checkConnection = RunService.Heartbeat:Connect(function()
		local allArrived = true
		local arrivedCount = 0

		for unitInstance, data in pairs(moveData) do
			if not data.Arrived then
				-- 检查实例是否有效
				if not unitInstance or not unitInstance.Parent or not unitInstance:FindFirstChild("HumanoidRootPart") then
					data.Arrived = true
					arrivedCount = arrivedCount + 1
					-- 清理目标Part
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end
					continue
				end

				local rootPart = unitInstance.HumanoidRootPart
				local humanoid = unitInstance.Humanoid
				local distance = (rootPart.Position - data.TargetCFrame.Position).Magnitude

				-- 到达检测
				local arrivalThreshold = GameConfig.Campaign.ArrivalThreshold or 2
				if distance < arrivalThreshold then
					data.Arrived = true
					arrivedCount = arrivedCount + 1

					-- 停止移动
					humanoid:MoveTo(rootPart.Position)

					-- 清理路径
					PathService.ClearPath(unitInstance)

					-- 清理目标Part
					if data.TargetPart and data.TargetPart.Parent then
						data.TargetPart:Destroy()
					end

					DebugLog(string.format("兵种到达目标: %s", unitInstance.Name))
				else
					allArrived = false

					-- 超时检测
					if tick() - data.StartTime > GameConfig.Campaign.MoveTimeout then
						warn("[PathService] 兵种寻路超时，强制传送:", unitInstance.Name)

						-- 强制传送到目标位置
						rootPart.CFrame = data.TargetCFrame

						data.Arrived = true
						arrivedCount = arrivedCount + 1

						-- 清理
						PathService.ClearPath(unitInstance)
						if data.TargetPart and data.TargetPart.Parent then
							data.TargetPart:Destroy()
						end
					else
						-- 正常寻路逻辑
						local pathStatus = PathService.GetPathStatus(unitInstance)

						-- 如果需要重新寻路
						if pathStatus == PathStatus.NEED_REPATH or pathStatus == PathStatus.IDLE or pathStatus == PathStatus.FAILED then
							local now = tick()
							if now - data.LastPathRequest >= CONFIG.PATH_RECALC_COOLDOWN then
								local unitId = unitInstance:GetAttribute("UnitId") or unitInstance.Name
								PathService.RequestPath(unitInstance, data.TargetPart, unitId)
								data.LastPathRequest = now
							end
						end

						-- 如果有有效路径，沿路径点移动
						if pathStatus == PathStatus.SUCCESS then
							local nextWaypoint = PathService.GetNextWaypoint(unitInstance)

							if nextWaypoint then
								-- 移动到当前路径点
								humanoid:MoveTo(nextWaypoint)

								-- 检查是否到达当前路径点
								if PathService.HasReachedWaypoint(unitInstance) then
									-- 推进到下一个路径点
									if not PathService.AdvancePath(unitInstance) then
										-- 路径走完，直接移动到目标
										humanoid:MoveTo(data.TargetCFrame.Position)
									end
								end
							else
								-- 没有路径点，直接移动到目标
								humanoid:MoveTo(data.TargetCFrame.Position)
							end
						elseif pathStatus == PathStatus.FAILED then
							-- 寻路失败，直线移动
							humanoid:MoveTo(data.TargetCFrame.Position)
						end
					end
				end
			else
				arrivedCount = arrivedCount + 1
			end
		end

		-- 所有兵种到达
		if allArrived then
			checkConnection:Disconnect()

			print("[PathService] 批量寻路完成，到达数量:", arrivedCount, "/", moveCount)

			-- 清理所有虚拟目标Part
			for _, data in pairs(moveData) do
				if data.TargetPart and data.TargetPart.Parent then
					data.TargetPart:Destroy()
				end
			end

			-- 触发回调
			if onAllArrived then
				onAllArrived(moveTargets)
			end
		end
	end)
end

return PathService
