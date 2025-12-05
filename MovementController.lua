--[[
脚本名称: MovementController
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/MovementController
版本: V1.1

功能描述（参考寻路逻辑重写方案.lua）：
- 路径跟随：根据PathService提供的waypoints移动
- 局部避障：使用Blockcast检测前方障碍，动态调整方向
- 卡住检测：基于WalkSpeed的位移检测，避免误判拥堵
- arrive行为：接近目标时减速停止
- 拥挤豁免：周围友军多时放宽卡住判定

设计原则：
- MovementController只负责"怎么走"，不管"去哪里"
- 与PathService解耦：PathService算路，MovementController跟随
- 简单状态机：Idle -> Moving -> NearTarget

使用说明：
- 这是一个可选的独立移动控制器
- UnitAI_New 使用内置移动逻辑，不依赖本模块
- 如需在其他场景使用独立移动控制，可引入本模块
- 调用 StartMoveTo() 开始移动，StopMove() 停止移动
]]

local MovementController = {}

-- ==================== 依赖服务 ====================

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ==================== 配置 ====================

local CONFIG = {
	-- 基础移动
	WAYPOINT_REACH_THRESHOLD = 1.5,     -- 路径点到达阈值
	NEAR_TARGET_THRESHOLD = 3.0,        -- 接近目标阈值
	DIRECT_MOVE_DISTANCE = 10,          -- 直线移动最大距离

	-- Blockcast检测
	BLOCKCAST_WIDTH = 3,
	BLOCKCAST_HEIGHT = 5,

	-- 卡住检测
	STUCK_CHECK_INTERVAL = 0.5,         -- 检测间隔（秒）
	STUCK_MIN_VELOCITY = 0.5,           -- 最小速度阈值
	STUCK_COUNT_THRESHOLD = 3,          -- 连续卡住次数阈值
	REPATH_COOLDOWN = 1.5,              -- 重寻路冷却（秒）

	-- 拥挤豁免
	CROWD_CHECK_RADIUS = 5,             -- 拥挤检测半径
	CROWD_THRESHOLD = 3,                -- 友军数量阈值

	-- MoveTo节流
	MOVETO_THROTTLE_INTERVAL = 0.25,    -- 同目标MoveTo最小间隔
	MOVETO_POSITION_THRESHOLD = 1.0,    -- 位置变化阈值

	-- 分离力
	SEPARATION_RADIUS = 3,
	SEPARATION_FORCE = 1.5,
	SEPARATION_INTERVAL = 0.1,

	-- 调试
	DEBUG_LOGS = false,
}

-- ==================== 移动状态枚举 ====================

local MoveState = {
	IDLE = "Idle",
	MOVING_PATH = "MovingPath",         -- 沿路径移动
	MOVING_DIRECT = "MovingDirect",     -- 直线移动
	NEAR_TARGET = "NearTarget",         -- 接近目标（减速）
	STUCK = "Stuck",                    -- 卡住
	ARRIVED = "Arrived",                -- 到达
}

MovementController.MoveState = MoveState

-- ==================== 私有变量 ====================

local movementData = {}    -- [unitModel] = MovementData
local updateConnection = nil
local accumulatedTime = 0
local lastSeparationTime = 0

-- 引用其他系统（延迟加载）
local PathService = nil
local UnitManager = nil

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if CONFIG.DEBUG_LOGS then
		local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
		print(GameConfig.LOG_PREFIX, "[MovementController]", ...)
	end
end

-- ==================== 工具函数 ====================

local function GetModelPosition(model)
	if not model then return nil end
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return rootPart and rootPart.Position
end

local function GetHorizontalDistance(pos1, pos2)
	if not pos1 or not pos2 then return math.huge end
	return math.sqrt((pos1.X - pos2.X)^2 + (pos1.Z - pos2.Z)^2)
end

-- ==================== Blockcast障碍检测 ====================

--[[
使用Blockcast检测前方是否有障碍物
@param unitModel Model - 单位模型
@param targetPos Vector3 - 目标位置
@return boolean - true表示路径畅通
]]
local function IsPathClear(unitModel, targetPos)
	local root = unitModel:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	local startPos = root.Position
	local direction = targetPos - startPos
	local distance = direction.Magnitude

	if distance < 3 then return true end

	local size = Vector3.new(CONFIG.BLOCKCAST_WIDTH, CONFIG.BLOCKCAST_HEIGHT, 1)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local filterList = {unitModel}
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		table.insert(filterList, unitsFolder)
	end
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	local cframe = CFrame.lookAt(startPos, Vector3.new(targetPos.X, startPos.Y, targetPos.Z))
	local detectDistance = math.max(1, distance - 2)

	local result = workspace:Blockcast(cframe, size, direction.Unit * detectDistance, rayParams)

	return not (result and result.Instance and result.Instance.CanCollide)
end

-- ==================== 拥挤检测 ====================

--[[
检测单位周围是否拥挤
@param unitModel Model - 单位模型
@return boolean - true表示周围拥挤
]]
local function IsInCrowdedArea(unitModel)
	local root = unitModel:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	local myPos = root.Position
	local nearbyCount = 0

	for otherUnit, data in pairs(movementData) do
		if otherUnit ~= unitModel and data.State ~= MoveState.IDLE and data.State ~= MoveState.ARRIVED then
			local otherRoot = otherUnit:FindFirstChild("HumanoidRootPart")
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

-- ==================== 分离力计算 ====================

local function ApplySeparationForces()
	local now = tick()
	if now - lastSeparationTime < CONFIG.SEPARATION_INTERVAL then return end
	lastSeparationTime = now

	local positions = {}
	for unitModel, data in pairs(movementData) do
		if data.State == MoveState.MOVING_PATH or data.State == MoveState.MOVING_DIRECT then
			local root = unitModel:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(positions, {
					model = unitModel,
					root = root,
					position = root.Position,
				})
			end
		end
	end

	for _, unit1 in ipairs(positions) do
		local totalForce = Vector3.zero
		local neighborCount = 0

		for _, unit2 in ipairs(positions) do
			if unit1.model ~= unit2.model then
				local diff = unit1.position - unit2.position
				local distXZ = math.sqrt(diff.X^2 + diff.Z^2)

				if distXZ < CONFIG.SEPARATION_RADIUS and distXZ > 0.3 then
					local pushDir = Vector3.new(diff.X, 0, diff.Z)
					if pushDir.Magnitude > 0.1 then
						pushDir = pushDir.Unit
						local forceMag = (CONFIG.SEPARATION_RADIUS - distXZ) / CONFIG.SEPARATION_RADIUS
						totalForce = totalForce + pushDir * forceMag
						neighborCount = neighborCount + 1
					end
				end
			end
		end

		if neighborCount > 0 and totalForce.Magnitude > 0.1 then
			local finalForce = totalForce.Unit * CONFIG.SEPARATION_FORCE
			pcall(function()
				local vel = unit1.root.AssemblyLinearVelocity
				unit1.root.AssemblyLinearVelocity = Vector3.new(
					vel.X + finalForce.X,
					vel.Y,
					vel.Z + finalForce.Z
				)
			end)
		end
	end
end

-- ==================== 移动数据管理 ====================

local function InitMovementData(unitModel)
	local humanoid = unitModel:FindFirstChild("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return nil
	end

	local data = {
		UnitModel = unitModel,
		Humanoid = humanoid,
		RootPart = rootPart,
		State = MoveState.IDLE,

		-- 目标信息
		TargetModel = nil,
		TargetPosition = nil,
		ArrivalCallback = nil,

		-- 卡住检测
		LastStuckCheckTime = tick(),
		LastStuckCheckPos = rootPart.Position,
		StuckCount = 0,
		LastRepathTime = 0,
		PrevDistanceToTarget = nil,

		-- MoveTo节流
		LastMoveToPos = nil,
		LastMoveToTime = 0,

		-- 状态标记
		IsActive = true,
		PathRequested = false,
	}

	movementData[unitModel] = data
	return data
end

local function GetMovementData(unitModel)
	return movementData[unitModel]
end

-- ==================== 节流MoveTo ====================

local function ThrottledMoveTo(data, targetPos)
	if not data or not data.Humanoid or not targetPos then
		return false
	end

	local now = tick()

	if data.LastMoveToPos then
		local distDiff = (targetPos - data.LastMoveToPos).Magnitude
		local timeDiff = now - data.LastMoveToTime

		if distDiff < CONFIG.MOVETO_POSITION_THRESHOLD and timeDiff < CONFIG.MOVETO_THROTTLE_INTERVAL then
			return false
		end
	end

	data.Humanoid:MoveTo(targetPos)
	data.LastMoveToPos = targetPos
	data.LastMoveToTime = now
	return true
end

-- ==================== 核心移动逻辑 ====================

--[[
更新单个单位的移动状态
]]
local function UpdateUnitMovement(data)
	if not data.IsActive then return end
	if not data.UnitModel or not data.UnitModel.Parent then return end
	if data.State == MoveState.IDLE or data.State == MoveState.ARRIVED then return end

	-- 延迟加载PathService
	if not PathService then
		PathService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PathService"))
	end

	local currentPos = GetModelPosition(data.UnitModel)
	local targetPos = data.TargetPosition
	if not currentPos or not targetPos then return end

	local distanceToTarget = GetHorizontalDistance(currentPos, targetPos)

	-- 检查到达
	local arrivalThreshold = data.ArrivalThreshold or CONFIG.NEAR_TARGET_THRESHOLD
	if distanceToTarget < arrivalThreshold then
		data.State = MoveState.ARRIVED
		data.Humanoid:Move(Vector3.zero, true)
		PathService.ClearPath(data.UnitModel)

		if data.ArrivalCallback then
			pcall(function() data.ArrivalCallback(data.UnitModel, true) end)
		end
		return
	end

	-- 检查接近目标（减速）
	if distanceToTarget < CONFIG.NEAR_TARGET_THRESHOLD * 2 then
		data.State = MoveState.NEAR_TARGET
		ThrottledMoveTo(data, targetPos)
		return
	end

	-- 获取路径状态
	local pathStatus = PathService.GetPathStatus(data.UnitModel)
	local isPartialPath = PathService.IsPartialPath(data.UnitModel)
	local now = tick()

	-- 决定移动方式
	local shouldUsePath = false

	if distanceToTarget > CONFIG.DIRECT_MOVE_DISTANCE then
		shouldUsePath = true
	elseif not IsPathClear(data.UnitModel, targetPos) then
		shouldUsePath = true
	end

	if shouldUsePath then
		-- 使用路径移动
		if pathStatus == "Success" or pathStatus == "Partial" then
			data.State = MoveState.MOVING_PATH

			-- 检查是否到达当前路径点
			if PathService.HasReachedWaypoint(data.UnitModel, CONFIG.WAYPOINT_REACH_THRESHOLD) then
				if not PathService.AdvancePath(data.UnitModel) then
					-- 路径走完
					if isPartialPath then
						-- Partial路径走完，停下等待重寻路
						data.Humanoid:Move(Vector3.zero)
						PathService.ClearPath(data.UnitModel)
						data.PathRequested = false
						DebugLog(string.format("%s Partial路径走完", data.UnitModel.Name))
						return
					else
						-- Success路径走完，尝试直接移动
						data.State = MoveState.MOVING_DIRECT
						ThrottledMoveTo(data, targetPos)
						return
					end
				end
			end

			local nextWaypoint = PathService.GetNextWaypoint(data.UnitModel)
			if nextWaypoint then
				ThrottledMoveTo(data, nextWaypoint)
			end

			-- 卡住检测
			if now - data.LastStuckCheckTime >= CONFIG.STUCK_CHECK_INTERVAL then
				data.LastStuckCheckTime = now

				if not data.PathRequested then
					local walkSpeed = data.Humanoid.WalkSpeed or 16
					local lastPos = data.LastStuckCheckPos
					local actualDistance = GetHorizontalDistance(currentPos, lastPos)
					data.LastStuckCheckPos = currentPos

					local expectedDistance = walkSpeed * CONFIG.STUCK_CHECK_INTERVAL * 0.5
					local minDistThreshold = math.max(CONFIG.STUCK_MIN_VELOCITY, expectedDistance * 0.3)

					local prevDist = data.PrevDistanceToTarget or distanceToTarget
					local isProgressing = distanceToTarget < (prevDist - 0.1)
					data.PrevDistanceToTarget = distanceToTarget

					local canRepath = (now - data.LastRepathTime) >= CONFIG.REPATH_COOLDOWN

					local isStuck = actualDistance < minDistThreshold
						and not isProgressing
						and distanceToTarget > 5
						and canRepath

					if isStuck then
						if IsInCrowdedArea(data.UnitModel) then
							data.StuckCount = 0
							DebugLog(string.format("⚠️ %s 疑似卡住但拥挤豁免", data.UnitModel.Name))
						else
							data.StuckCount = data.StuckCount + 1

							if data.StuckCount >= CONFIG.STUCK_COUNT_THRESHOLD then
								DebugLog(string.format("🔄 %s 确认卡住，重寻路", data.UnitModel.Name))
								data.StuckCount = 0
								data.LastRepathTime = now
								data.State = MoveState.STUCK
								data.Humanoid:Move(Vector3.zero)
								PathService.ClearPath(data.UnitModel)
								PathService.ForceRepath(data.UnitModel)
								data.PathRequested = false
							end
						end
					else
						if actualDistance > minDistThreshold then
							data.StuckCount = 0
						end
					end
				end
			end

		elseif pathStatus == "Computing" or pathStatus == "Queued" then
			-- 等待路径计算
			return

		else
			-- 无路径或失败，请求新路径
			if not data.PathRequested then
				data.PathRequested = true

				PathService.RequestPathAsync(data.UnitModel, data.TargetModel, data.UnitModel.Name, function(success, pathState)
					data.PathRequested = false

					if not data.IsActive or not data.UnitModel.Parent then return end

					if success and pathState and (pathState.Status == "Success" or pathState.Status == "Partial") then
						local nextWaypoint = PathService.GetNextWaypoint(data.UnitModel)
						if nextWaypoint then
							ThrottledMoveTo(data, nextWaypoint)
						end
					else
						-- 寻路失败，停下等待
						data.Humanoid:Move(Vector3.zero)
						DebugLog(string.format("⚠️ %s 寻路失败", data.UnitModel.Name))
					end
				end)
			end
		end
	else
		-- 直线移动
		data.State = MoveState.MOVING_DIRECT
		ThrottledMoveTo(data, targetPos)
		PathService.ClearPath(data.UnitModel)

		-- 简单卡住检测（直线移动时）
		local velocity = data.RootPart.AssemblyLinearVelocity
		local speed = math.sqrt(velocity.X^2 + velocity.Z^2)

		if data.Humanoid.MoveDirection.Magnitude > 0.1 and speed < 0.3 then
			data.StuckCount = (data.StuckCount or 0) + 1
			if data.StuckCount > 5 then
				-- 撞墙，切换到寻路
				DebugLog(string.format("⚠️ %s 直线移动撞墙", data.UnitModel.Name))
				shouldUsePath = true
				data.StuckCount = 0
			end
		else
			data.StuckCount = 0
		end
	end
end

-- ==================== 主更新循环 ====================

local function UpdateAllMovements(dt)
	accumulatedTime = accumulatedTime + dt

	if accumulatedTime < 0.05 then return end
	accumulatedTime = 0

	-- 分离力
	ApplySeparationForces()

	-- 更新所有单位
	for unitModel, data in pairs(movementData) do
		if not unitModel or not unitModel.Parent then
			continue
		end

		local success, err = pcall(function()
			UpdateUnitMovement(data)
		end)

		if not success then
			DebugLog("移动更新失败:", err)
		end
	end
end

-- ==================== 公共接口 ====================

--[[
开始移动到目标
@param unitModel Model - 单位模型
@param targetModel Model - 目标模型
@param options table? - 可选参数 {arrivalThreshold, onArrival}
@return boolean - 是否成功开始移动
]]
function MovementController.StartMoveTo(unitModel, targetModel, options)
	if not unitModel or not targetModel then
		return false
	end

	options = options or {}

	local data = GetMovementData(unitModel) or InitMovementData(unitModel)
	if not data then
		return false
	end

	local targetPos = GetModelPosition(targetModel)
	if not targetPos then
		return false
	end

	data.TargetModel = targetModel
	data.TargetPosition = targetPos
	data.ArrivalThreshold = options.arrivalThreshold
	data.ArrivalCallback = options.onArrival
	data.State = MoveState.MOVING_PATH
	data.IsActive = true
	data.PathRequested = false
	data.StuckCount = 0
	data.LastRepathTime = 0

	-- 延迟加载PathService
	if not PathService then
		PathService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PathService"))
	end

	-- 清理旧路径并请求新路径
	PathService.ClearPath(unitModel)

	return true
end

--[[
更新目标位置
@param unitModel Model - 单位模型
@param targetModel Model - 新目标
]]
function MovementController.UpdateTarget(unitModel, targetModel)
	local data = GetMovementData(unitModel)
	if not data then return end

	local newPos = GetModelPosition(targetModel)
	if not newPos then return end

	local oldPos = data.TargetPosition
	if oldPos then
		local moved = GetHorizontalDistance(newPos, oldPos)
		if moved < 8 then
			return  -- 目标移动不大，不更新
		end
	end

	data.TargetModel = targetModel
	data.TargetPosition = newPos
end

--[[
停止移动
]]
function MovementController.StopMove(unitModel)
	local data = GetMovementData(unitModel)
	if not data then return end

	data.State = MoveState.IDLE
	data.IsActive = false

	if data.Humanoid then
		data.Humanoid:Move(Vector3.zero, true)
	end

	-- 延迟加载PathService
	if not PathService then
		PathService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PathService"))
	end

	PathService.ClearPath(unitModel)
end

--[[
获取移动状态
]]
function MovementController.GetMoveState(unitModel)
	local data = GetMovementData(unitModel)
	if not data then return MoveState.IDLE end
	return data.State
end

--[[
清理单位数据
]]
function MovementController.Cleanup(unitModel)
	local data = movementData[unitModel]
	if data then
		data.IsActive = false
	end
	movementData[unitModel] = nil

	if PathService then
		PathService.ClearPath(unitModel)
	end
end

--[[
初始化系统
]]
function MovementController.Initialize()
	if updateConnection then
		return true
	end

	updateConnection = RunService.Heartbeat:Connect(UpdateAllMovements)
	DebugLog("MovementController初始化完成")
	return true
end

--[[
关闭系统
]]
function MovementController.Shutdown()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	for unitModel, _ in pairs(movementData) do
		MovementController.Cleanup(unitModel)
	end

	movementData = {}
	DebugLog("MovementController已关闭")
end

--[[
获取活跃单位数量
]]
function MovementController.GetActiveCount()
	local count = 0
	for _, data in pairs(movementData) do
		if data.IsActive and data.State ~= MoveState.IDLE and data.State ~= MoveState.ARRIVED then
			count = count + 1
		end
	end
	return count
end

--[[
设置调试选项
]]
function MovementController.SetDebugMode(enabled)
	CONFIG.DEBUG_LOGS = enabled
end

return MovementController
