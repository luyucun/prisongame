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
}

-- 从BattleConfig读取配置
if BattleConfig then
	CONFIG.DEBUG_PATH_LOGS = BattleConfig.DEBUG_AI_LOGS or CONFIG.DEBUG_PATH_LOGS
end

-- ==================== 路径状态枚举 ====================

local PathStatus = {
	IDLE = "Idle",
	COMPUTING = "Computing",
	SUCCESS = "Success",
	FAILED = "Failed",
	BLOCKED = "Blocked",
	NEED_REPATH = "NeedRepath",
}

ClientPathService.PathStatus = PathStatus

-- ==================== 私有变量 ====================

local pathStates = {}      -- [unitModel] = PathState

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
V4.1修复：跳过“初始回头路点”
PathfindingService在NavMesh刚更新/起点靠近不可走区域边缘时，首个路点可能会落在目标反方向，
表现为单位先掉头走一段再折返。
该逻辑只在路径起始阶段(索引<=3)尝试跳过，避免影响正常绕障路径。
]]
local function ShouldSkipInitialBacktrackWaypoint(startPos, waypointPos, targetPos)
	-- 只做XZ平面判断，忽略高度差
	local toTarget = Vector3.new(targetPos.X - startPos.X, 0, targetPos.Z - startPos.Z)
	local toWaypoint = Vector3.new(waypointPos.X - startPos.X, 0, waypointPos.Z - startPos.Z)

	if toTarget.Magnitude < 0.05 or toWaypoint.Magnitude < 0.05 then
		return false
	end

	-- dot<0 表示路点在目标的反方向(>90°)
	local dot = toTarget.Unit:Dot(toWaypoint.Unit)
	if dot >= -0.2 then
		return false
	end

	-- 路点比当前位置“更远离目标”且步长不大时，认为是NavMesh投影导致的回头路点
	local startDist = GetHorizontalDistance(startPos, targetPos)
	local waypointDist = GetHorizontalDistance(waypointPos, targetPos)
	local stepDist = GetHorizontalDistance(startPos, waypointPos)

	return stepDist <= 18 and (waypointDist - startDist) >= 2
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
	}
	pathStates[unitModel] = pathState
	return pathState
end

local function GetPathState(unitModel)
	return pathStates[unitModel]
end

-- ==================== 公共接口 ====================

--[[
清理单位的路径数据（供外部调用）
@param unitModel Model - 单位模型
]]
function ClientPathService.ClearPath(unitModel)
	local pathState = pathStates[unitModel]
	if not pathState then return end

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
end

--[[
请求寻路到目标位置
@param unitModel Model - 单位模型
@param targetPos Vector3 - 目标位置
@return boolean - 是否成功发起寻路
]]
function ClientPathService.RequestPath(unitModel, targetPos)
	if not unitModel or not targetPos then
		return false
	end

	local pathState = GetPathState(unitModel) or InitPathState(unitModel)

	-- 冷却检查
	local now = tick()
	if now - pathState.LastRequestTime < CONFIG.PATH_RECALC_COOLDOWN then
		return false
	end

	-- 检查目标是否明显移动
	if pathState.LastTargetPos and pathState.Status == PathStatus.SUCCESS then
		local distance = GetHorizontalDistance(pathState.LastTargetPos, targetPos)
		if distance < CONFIG.TARGET_MOVE_THRESHOLD then
			return false  -- 目标未明显移动，继续使用当前路径
		end
	end

	pathState.LastRequestTime = now
	pathState.LastTargetPos = targetPos

	-- 开始构建路径
	return ClientPathService.BuildPath(unitModel, targetPos)
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
			pathState.Status = PathStatus.SUCCESS

			-- V4.1修复：跳过初始“回头路点”（最多跳过2个，且只在起始阶段）
			local skipped = 0
			while pathState.Waypoints
				and pathState.Index <= #pathState.Waypoints
				and pathState.Index <= 3
				and skipped < 2 do
				local wp = pathState.Waypoints[pathState.Index]
				if wp and ShouldSkipInitialBacktrackWaypoint(startPos, wp, targetPos) then
					pathState.Index += 1
					skipped += 1
				else
					break
				end
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
	local success = ClientPathService.RequestPath(unitModel, targetPos)
	if not success then
		if onFailed then onFailed("Path Request Failed") end
		return
	end

	local pathState = GetPathState(unitModel)
	if not pathState or pathState.Status ~= PathStatus.SUCCESS then
		if onFailed then onFailed("No Valid Path") end
		return
	end

	-- 开始跟随路径
	ClientPathService.FollowPath(unitModel, onReached, onFailed)
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

	-- 清理旧的Move连接
	if pathState.MoveConnection then
		pathState.MoveConnection:Disconnect()
		pathState.MoveConnection = nil
	end

	-- 获取当前目标路点
	local currentWaypoint = pathState.Waypoints[pathState.Index]
	if not currentWaypoint then
		if onReached then onReached() end
		return
	end

	-- 移动到当前路点
	humanoid:MoveTo(currentWaypoint)

	-- 监听MoveToFinished
	pathState.MoveConnection = humanoid.MoveToFinished:Connect(function(reached)
		if pathState.MoveConnection then
			pathState.MoveConnection:Disconnect()
			pathState.MoveConnection = nil
		end

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
	return pathState.Status
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
]]
function ClientPathService.ClearAll()
	for unitModel, pathState in pairs(pathStates) do
		ClientPathService.ClearPath(unitModel)
	end
	pathStates = {}
	DebugLog("所有路径数据已清理")
end

return ClientPathService
