--[[
=====================================================
脚本名称: DoorControlService
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/DoorControlService.lua
版本: V2.0.1 - 重构版
最后更新: 2025-01-11

功能说明：
管理玩家基地的门开关动画
- 每个PlayerHome有一个MetalDoor，包含DoorLeft和DoorRight
- 支持1秒动画打开（90°/-90°）和关闭（0°）
- 统一的状态机和旋转实现
- 配置驱动、职责清晰、容错健壮

核心改进：
1. BuildDoorData独立资源定位逻辑
2. ApplyRotation统一旋转实现（Model/Part兼容）
3. Transition统一状态转换逻辑
4. 配置解耦到GameConfig.Door
5. HasDoor容错检查
6. warnOnce避免日志刷屏

核心API：
- Initialize() - 初始化所有门并缓存
- OpenDoor(homeId, onCompleted) - 打开门
- CloseDoor(homeId, onCompleted) - 关闭门
- SetDoorState(homeId, state) - 直接设置状态
- GetDoorState(homeId) - 获取当前状态
- IsMoving(homeId) - 门是否在动画中
- HasDoor(homeId) - 检查门是否可用

门状态FSM：
CLOSED <-> OPENING -> OPEN <-> CLOSING -> CLOSED
=====================================================
]]

local DoorControlService = {}

-- ==================== 服务引用 ====================
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 配置引用
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- ==================== 常量定义 ====================
local DoorState = {
	CLOSED = "Closed",
	OPENING = "Opening",
	OPEN = "Open",
	CLOSING = "Closing"
}

-- 从GameConfig读取门配置
local DOOR_CONFIG = GameConfig.Door or {
	TweenDuration = 1,
	LeftOpenAngle = 90,
	RightOpenAngle = -90,
	ClosedAngle = 0,
	EasingStyle = Enum.EasingStyle.Quad,
	EasingDirection = Enum.EasingDirection.InOut
}

-- ==================== 私有变量 ====================
-- DoorCache结构：
-- [homeId] = {
--   HomeId: number,
--   Left: { Node: Model|Part, Origin: BasePart|nil, Type: "Model"|"Part" },
--   Right: { Node: Model|Part, Origin: BasePart|nil, Type: "Model"|"Part" },
--   State: string,
--   Tweens: { Left: Tween|Connection|nil, Right: Tween|Connection|nil }
-- }
-- Failed结构：
-- [homeId] = string (失败原因)
local DoorCache = {
	Valid = {},   -- 有效的门
	Failed = {}   -- 初始化失败的门（记录原因）
}

local Initialized = false

-- warnOnce缓存，避免重复警告
local WarnOnceCache = {}

-- ==================== 工具函数 ====================
local function Log(message)
	if GameConfig.DEBUG_MODE then
		print("[DoorControlService]", message)
	end
end

local function WarnLog(message)
	warn("[DoorControlService]", message)
end

--[[
	只警告一次（避免战斗流程刷日志）
	@param key string - 警告唯一标识
	@param message string - 警告信息
]]
local function WarnOnce(key, message)
	if not WarnOnceCache[key] then
		WarnOnceCache[key] = true
		WarnLog(message)
	end
end

--[[
	缓动函数 (Quad InOut)
	@param t number - 进度 (0-1)
	@return number - 缓动后的值 (0-1)
]]
local function EaseInOutQuad(t)
	if t < 0.5 then
		return 2 * t * t
	else
		return 1 - math.pow(-2 * t + 2, 2) / 2
	end
end

-- ==================== 步骤1：资源定位与DoorData构建 ====================

--[[
	为单扇门（Left或Right）构建NodeInfo
	@param door Folder - MetalDoor或MetalDoor01
	@param sideName string - "DoorLeft" 或 "DoorRight"
	@return table|nil - { Node: Model|Part, Origin: BasePart|nil, Type: "Model"|"Part" }
	@return string|nil - 错误原因
]]
local function BuildNodeInfo(door, sideName)
	local node = door:FindFirstChild(sideName)
	if not node then
		return nil, sideName .. " 不存在"
	end

	-- 判断类型：Model 或 BasePart
	if node:IsA("Model") then
		-- Model类型：尝试找Origin作为旋转轴心（可选）
		local origin = node:FindFirstChild("Origin")

		-- Origin是可选的：
		-- - 如果有Origin且是BasePart，使用Origin作为铰链
		-- - 如果没有Origin，直接旋转整个Model（以Model的Pivot为中心）
		if origin and origin:IsA("BasePart") then
			-- 有Origin，使用Origin作为固定铰链
			return {
				Node = node,
				Origin = origin,
				Type = "Model"
			}, nil
		else
			-- 没有Origin，直接旋转整个Model
			if origin and not origin:IsA("BasePart") then
				WarnOnce(door.Parent.Name .. "_" .. sideName .. "_InvalidOrigin",
					"警告: " .. door.Parent.Name .. " " .. sideName .. " 的Origin不是BasePart，将直接旋转Model")
			end

			return {
				Node = node,
				Origin = nil,  -- 没有Origin，直接旋转Model
				Type = "Model"
			}, nil
		end

	elseif node:IsA("BasePart") then
		-- BasePart类型：直接使用Part本身
		return {
			Node = node,
			Origin = nil,  -- BasePart不需要Origin
			Type = "Part"
		}, nil

	else
		return nil, sideName .. " 类型不正确: " .. node.ClassName .. " (需要 Model 或 BasePart)"
	end
end

--[[
	构建单个基地的DoorData
	职责：定位资源、验证结构、打包数据
	@param home Instance - PlayerHome实例
	@return table|nil - DoorData结构
	@return string|nil - 失败原因
]]
local function BuildDoorData(home)
	local homeId = tonumber(home.Name:match("%d+"))
	if not homeId then
		return nil, "无法从 " .. home.Name .. " 解析HomeId"
	end

	-- 兼容两种命名：MetalDoor 和 MetalDoor01
	local door = home:FindFirstChild("MetalDoor") or home:FindFirstChild("MetalDoor01")
	if not door then
		return nil, "缺少 MetalDoor 或 MetalDoor01"
	end

	-- 构建左门NodeInfo
	local leftInfo, leftError = BuildNodeInfo(door, "DoorLeft")
	if not leftInfo then
		return nil, leftError
	end

	-- 构建右门NodeInfo
	local rightInfo, rightError = BuildNodeInfo(door, "DoorRight")
	if not rightInfo then
		return nil, rightError
	end

	-- 打包成DoorData
	return {
		HomeId = homeId,
		Left = leftInfo,
		Right = rightInfo,
		State = DoorState.CLOSED,
		Tweens = { Left = nil, Right = nil }
	}, nil
end

-- ==================== 步骤2：统一旋转实现 ====================

--[[
	手动Tween Model旋转（通过Pivot + Heartbeat）
	支持两种模式：
	1. 如果有origin，以origin为固定铰链旋转（门绕铰链开关）
	2. 如果没有origin，以Model的当前Pivot为中心旋转
	@param model Model - 要旋转的Model
	@param origin BasePart|nil - 旋转轴心（可选，如果为nil则以Model的Pivot为中心）
	@param targetAngleY number - 目标Y轴角度(度)
	@param duration number - 动画时长(秒)
	@param onComplete function|nil - 完成回调
	@return Connection - RunService连接(用于取消)
]]
local function TweenModelRotation(model, origin, targetAngleY, duration, onComplete)
	local startTime = tick()

	-- 确定旋转中心点
	local pivotPosition
	if origin then
		-- 有Origin：以Origin的位置为固定铰链（铰链不动，门绕它旋转）
		pivotPosition = origin.Position
	else
		-- 没有Origin：以Model当前Pivot的位置为中心
		pivotPosition = model:GetPivot().Position
	end

	-- 从当前Pivot中提取起始Y轴角度
	local currentPivot = model:GetPivot()
	local _, startY, _ = currentPivot:ToOrientation()
	local startAngleDeg = math.deg(startY)

	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / duration, 1)

		-- 应用缓动
		local easedAlpha = EaseInOutQuad(alpha)

		-- 计算当前角度
		local currentAngle = startAngleDeg + (targetAngleY - startAngleDeg) * easedAlpha

		-- 以pivotPosition为中心，绕Y轴旋转
		local newPivot = CFrame.new(pivotPosition) * CFrame.Angles(0, math.rad(currentAngle), 0)

		-- 应用到Model
		model:PivotTo(newPivot)

		-- 完成时断开连接
		if alpha >= 1 then
			connection:Disconnect()
			if onComplete then
				task.spawn(onComplete)
			end
		end
	end)

	return connection
end

--[[
	统一的旋转实现（兼容Model和BasePart）
	职责：根据nodeInfo.Type选择合适的旋转方式
	@param nodeInfo table - { Node: Model|Part, Origin: BasePart|nil, Type: "Model"|"Part" }
	@param targetAngle number - 目标Y轴角度（度）
	@param duration number - 动画时长（秒）
	@param onComplete function|nil - 完成回调
	@return Tween|Connection - 用于取消的句柄
]]
local function ApplyRotation(nodeInfo, targetAngle, duration, onComplete)
	if nodeInfo.Type == "Model" then
		-- Model：使用手动Tween + PivotTo
		return TweenModelRotation(
			nodeInfo.Node,
			nodeInfo.Origin,
			targetAngle,
			duration,
			onComplete
		)

	elseif nodeInfo.Type == "Part" then
		-- BasePart：使用TweenService
		local currentCFrame = nodeInfo.Node.CFrame
		local position = currentCFrame.Position
		local targetCFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(targetAngle), 0)

		local tweenInfo = TweenInfo.new(
			duration,
			DOOR_CONFIG.EasingStyle,
			DOOR_CONFIG.EasingDirection
		)

		local tween = TweenService:Create(
			nodeInfo.Node,
			tweenInfo,
			{ CFrame = targetCFrame }
		)

		if onComplete then
			tween.Completed:Connect(function()
				task.spawn(onComplete)
			end)
		end

		tween:Play()
		return tween

	else
		error("未知的Node类型: " .. tostring(nodeInfo.Type))
	end
end

-- ==================== 步骤3：状态机与资源管理 ====================

--[[
	取消门的所有Tween
	@param doorData table - DoorData
]]
local function CancelDoorTweens(doorData)
	-- 取消左门
	if doorData.Tweens.Left then
		if type(doorData.Tweens.Left.Cancel) == "function" then
			-- TweenService Tween
			doorData.Tweens.Left:Cancel()
		elseif type(doorData.Tweens.Left.Disconnect) == "function" then
			-- RunService Connection
			doorData.Tweens.Left:Disconnect()
		end
		doorData.Tweens.Left = nil
	end

	-- 取消右门
	if doorData.Tweens.Right then
		if type(doorData.Tweens.Right.Cancel) == "function" then
			doorData.Tweens.Right:Cancel()
		elseif type(doorData.Tweens.Right.Disconnect) == "function" then
			doorData.Tweens.Right:Disconnect()
		end
		doorData.Tweens.Right = nil
	end
end

--[[
	统一的门状态转换函数
	职责：状态机核心，防重入、取消旧Tween、创建新Tween、两扇门都完成才切换状态
	改进：支持单扇门缺失、确保资源正确清理
	@param homeId number - 基地ID
	@param targetState string - 目标状态（"Open" 或 "Closed"）
	@param options table - { onCompleted: function|nil }
	@return boolean - 是否成功开始转换
]]
local function Transition(homeId, targetState, options)
	local doorData = DoorCache.Valid[homeId]
	if not doorData then
		WarnOnce("Transition_NoData_" .. homeId, "PlayerHome" .. homeId .. " 门数据不存在")
		return false
	end

	options = options or {}
	local onCompleted = options.onCompleted

	-- 防重入：如果当前状态就是目标状态
	local currentState = doorData.State
	local finalState, transitionState, leftAngle, rightAngle

	if targetState == "Open" then
		finalState = DoorState.OPEN
		transitionState = DoorState.OPENING
		leftAngle = DOOR_CONFIG.LeftOpenAngle
		rightAngle = DOOR_CONFIG.RightOpenAngle

		if currentState == DoorState.OPEN then
			if onCompleted then
				task.spawn(onCompleted)
			end
			return true
		end

		if currentState == DoorState.OPENING then
			return true
		end

	elseif targetState == "Closed" then
		finalState = DoorState.CLOSED
		transitionState = DoorState.CLOSING
		leftAngle = DOOR_CONFIG.ClosedAngle
		rightAngle = DOOR_CONFIG.ClosedAngle

		if currentState == DoorState.CLOSED then
			if onCompleted then
				task.spawn(onCompleted)
			end
			return true
		end

		if currentState == DoorState.CLOSING then
			return true
		end

	else
		WarnLog("未知的目标状态: " .. tostring(targetState))
		return false
	end

	-- 取消旧的Tween（防抖）
	CancelDoorTweens(doorData)

	-- 设置过渡状态
	doorData.State = transitionState

	-- 完成计数器：统计需要等待的门数
	local totalDoors = 0
	local completedCount = 0

	-- 检查哪些门存在
	local hasLeft = doorData.Left and doorData.Left.Node
	local hasRight = doorData.Right and doorData.Right.Node

	if hasLeft then
		totalDoors = totalDoors + 1
	end
	if hasRight then
		totalDoors = totalDoors + 1
	end

	-- 边界情况：如果两扇门都不存在
	if totalDoors == 0 then
		WarnLog("PlayerHome" .. homeId .. " 没有任何可用的门")
		doorData.State = finalState
		if onCompleted then
			task.spawn(onCompleted)
		end
		return false
	end

	-- 统一的完成回调（两扇门都完成才触发）
	local function onOneDoorCompleted()
		completedCount = completedCount + 1
		if completedCount >= totalDoors then
			-- 所有门都完成，切换到最终状态
			doorData.State = finalState

			-- 清理引用（避免残留）
			doorData.Tweens.Left = nil
			doorData.Tweens.Right = nil

			-- 触发回调
			if onCompleted then
				task.spawn(onCompleted)
			end
		end
	end

	-- 创建左门Tween（如果存在）
	if hasLeft then
		local success, result = pcall(function()
			return ApplyRotation(
				doorData.Left,
				leftAngle,
				DOOR_CONFIG.TweenDuration,
				onOneDoorCompleted
			)
		end)

		if success then
			doorData.Tweens.Left = result
		else
			WarnLog("创建左门Tween失败: " .. tostring(result))
			-- 即使失败也标记为完成，避免卡死
			onOneDoorCompleted()
		end
	end

	-- 创建右门Tween（如果存在）
	if hasRight then
		local success, result = pcall(function()
			return ApplyRotation(
				doorData.Right,
				rightAngle,
				DOOR_CONFIG.TweenDuration,
				onOneDoorCompleted
			)
		end)

		if success then
			doorData.Tweens.Right = result
		else
			WarnLog("创建右门Tween失败: " .. tostring(result))
			-- 即使失败也标记为完成，避免卡死
			onOneDoorCompleted()
		end
	end

	return true
end

-- ==================== 步骤6：对外API ====================

--[[
	初始化门控制服务
	在MainServer启动时调用，缓存所有门的引用
	@return boolean - 是否初始化成功
]]
function DoorControlService.Initialize()
	if Initialized then
		WarnLog("DoorControlService已初始化，跳过")
		return true
	end

	local workspace = game:GetService("Workspace")
	local homeFolder = workspace:FindFirstChild("Home")

	if not homeFolder then
		WarnLog("Workspace.Home 不存在，门控制服务初始化失败")
		return false
	end

	local successCount = 0

	for homeId = 1, 6 do
		local homeName = "PlayerHome" .. homeId
		local home = homeFolder:FindFirstChild(homeName)

		if not home then
			local reason = homeName .. " 不存在于Workspace.Home"
			DoorCache.Failed[homeId] = reason
			WarnLog(reason)
			continue
		end

		-- 构建DoorData
		local doorData, errorReason = BuildDoorData(home)
		if not doorData then
			local fullReason = homeName .. " 初始化失败: " .. errorReason
			DoorCache.Failed[homeId] = fullReason
			WarnLog(fullReason)
			continue
		end

		-- 缓存到Valid
		DoorCache.Valid[homeId] = doorData

		-- 直接设置初始物理状态为关闭（不通过公共API，避免循环依赖）
		-- 左门
		if doorData.Left and doorData.Left.Node then
			pcall(function()
				if doorData.Left.Type == "Model" then
					-- Model：确定旋转中心（有Origin用Origin，没有用Model的Pivot）
					local pivotPosition
					if doorData.Left.Origin then
						pivotPosition = doorData.Left.Origin.Position
					else
						pivotPosition = doorData.Left.Node:GetPivot().Position
					end
					local newPivot = CFrame.new(pivotPosition) * CFrame.Angles(0, math.rad(DOOR_CONFIG.ClosedAngle), 0)
					doorData.Left.Node:PivotTo(newPivot)
				else
					local position = doorData.Left.Node.Position
					doorData.Left.Node.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(DOOR_CONFIG.ClosedAngle), 0)
				end
			end)
		end

		-- 右门
		if doorData.Right and doorData.Right.Node then
			pcall(function()
				if doorData.Right.Type == "Model" then
					-- Model：确定旋转中心（有Origin用Origin，没有用Model的Pivot）
					local pivotPosition
					if doorData.Right.Origin then
						pivotPosition = doorData.Right.Origin.Position
					else
						pivotPosition = doorData.Right.Node:GetPivot().Position
					end
					local newPivot = CFrame.new(pivotPosition) * CFrame.Angles(0, math.rad(DOOR_CONFIG.ClosedAngle), 0)
					doorData.Right.Node:PivotTo(newPivot)
				else
					local position = doorData.Right.Node.Position
					doorData.Right.Node.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(DOOR_CONFIG.ClosedAngle), 0)
				end
			end)
		end

		-- 确保状态标记为关闭
		doorData.State = DoorState.CLOSED

		successCount = successCount + 1
	end

	Initialized = true
	Log("门控制服务初始化完成，成功: " .. successCount .. "/6")

	-- 输出失败信息
	if next(DoorCache.Failed) then
		WarnLog("以下基地的门初始化失败:")
		for homeId, reason in pairs(DoorCache.Failed) do
			WarnLog("  PlayerHome" .. homeId .. ": " .. reason)
		end
	end

	return successCount > 0
end

--[[
	检查门是否可用（容错检查）
	@param homeId number - 基地ID (1-6)
	@return boolean - 门是否可用
]]
function DoorControlService.HasDoor(homeId)
	if not Initialized then
		return false
	end

	return DoorCache.Valid[homeId] ~= nil
end

--[[
	打开指定基地的门
	@param homeId number - 基地ID (1-6)
	@param onCompleted function|nil - 动画完成后的回调（可选）
	@return boolean - 是否成功开始打开
]]
function DoorControlService.OpenDoor(homeId, onCompleted)
	if not Initialized then
		WarnOnce("OpenDoor_NotInitialized", "DoorControlService未初始化，无法打开门")
		return false
	end

	if not DoorControlService.HasDoor(homeId) then
		WarnOnce("OpenDoor_NoDoor_Home" .. homeId,
			"PlayerHome" .. homeId .. " 门不可用: " .. (DoorCache.Failed[homeId] or "未知原因"))
		return false
	end

	return Transition(homeId, "Open", { onCompleted = onCompleted })
end

--[[
	关闭指定基地的门
	@param homeId number - 基地ID (1-6)
	@param onCompleted function|nil - 动画完成后的回调（可选）
	@return boolean - 是否成功开始关闭
]]
function DoorControlService.CloseDoor(homeId, onCompleted)
	if not Initialized then
		WarnOnce("CloseDoor_NotInitialized", "DoorControlService未初始化，无法关闭门")
		return false
	end

	if not DoorControlService.HasDoor(homeId) then
		WarnOnce("CloseDoor_NoDoor_Home" .. homeId,
			"PlayerHome" .. homeId .. " 门不可用: " .. (DoorCache.Failed[homeId] or "未知原因"))
		return false
	end

	return Transition(homeId, "Closed", { onCompleted = onCompleted })
end

--[[
	直接设置门状态（无动画，用于重连恢复或强制重置）
	@param homeId number - 基地ID (1-6)
	@param state string - 目标状态 ("Open" 或 "Closed")
	@return boolean - 是否成功设置
]]
function DoorControlService.SetDoorState(homeId, state)
	if not Initialized then
		WarnOnce("SetDoorState_NotInitialized", "DoorControlService未初始化，无法设置门状态")
		return false
	end

	-- 检查门是否可用
	if not DoorControlService.HasDoor(homeId) then
		-- 如果门在Failed列表中，说明初始化失败，只在Debug模式下警告
		if DoorCache.Failed[homeId] then
			-- 静默失败，因为Initialize时已经警告过了
			-- 只有在首次调用时才警告（避免HomeSystem重复警告）
			WarnOnce("SetDoorState_InitFailed_Home" .. homeId,
				"[调试] PlayerHome" .. homeId .. " 门初始化失败，跳过状态设置: " .. DoorCache.Failed[homeId])
		else
			-- 门不存在且不在Failed中，这是真正的错误
			WarnLog("PlayerHome" .. homeId .. " 门不存在（既不在Valid也不在Failed中）")
		end
		return false
	end

	local doorData = DoorCache.Valid[homeId]

	-- 取消所有动画
	CancelDoorTweens(doorData)

	local targetAngle
	local finalState

	if state == "Open" or state == DoorState.OPEN then
		targetAngle = { left = DOOR_CONFIG.LeftOpenAngle, right = DOOR_CONFIG.RightOpenAngle }
		finalState = DoorState.OPEN
	elseif state == "Closed" or state == DoorState.CLOSED then
		targetAngle = { left = DOOR_CONFIG.ClosedAngle, right = DOOR_CONFIG.ClosedAngle }
		finalState = DoorState.CLOSED
	else
		WarnLog("未知的门状态: " .. tostring(state))
		return false
	end

	-- 直接设置角度（不播动画）
	-- 左门
	if doorData.Left and doorData.Left.Node then
		local success, err = pcall(function()
			if doorData.Left.Type == "Model" then
				-- Model：确定旋转中心（有Origin用Origin，没有用Model的Pivot）
				local pivotPosition
				if doorData.Left.Origin then
					pivotPosition = doorData.Left.Origin.Position
				else
					pivotPosition = doorData.Left.Node:GetPivot().Position
				end
				local newPivot = CFrame.new(pivotPosition) * CFrame.Angles(0, math.rad(targetAngle.left), 0)
				doorData.Left.Node:PivotTo(newPivot)
			else
				-- BasePart：直接设置CFrame
				local position = doorData.Left.Node.Position
				doorData.Left.Node.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(targetAngle.left), 0)
			end
		end)
		if not success then
			WarnLog("设置左门状态失败: " .. tostring(err))
		end
	end

	-- 右门
	if doorData.Right and doorData.Right.Node then
		local success, err = pcall(function()
			if doorData.Right.Type == "Model" then
				-- Model：确定旋转中心（有Origin用Origin，没有用Model的Pivot）
				local pivotPosition
				if doorData.Right.Origin then
					pivotPosition = doorData.Right.Origin.Position
				else
					pivotPosition = doorData.Right.Node:GetPivot().Position
				end
				local newPivot = CFrame.new(pivotPosition) * CFrame.Angles(0, math.rad(targetAngle.right), 0)
				doorData.Right.Node:PivotTo(newPivot)
			else
				-- BasePart：直接设置CFrame
				local position = doorData.Right.Node.Position
				doorData.Right.Node.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(targetAngle.right), 0)
			end
		end)
		if not success then
			WarnLog("设置右门状态失败: " .. tostring(err))
		end
	end

	doorData.State = finalState
	return true
end

--[[
	获取门的当前状态
	@param homeId number - 基地ID (1-6)
	@return string|nil - 当前状态
]]
function DoorControlService.GetDoorState(homeId)
	if not Initialized then
		return nil
	end

	local doorData = DoorCache.Valid[homeId]
	if not doorData then
		return nil
	end

	return doorData.State
end

--[[
	检查门是否在动画中
	@param homeId number - 基地ID (1-6)
	@return boolean - 是否在动画中
]]
function DoorControlService.IsMoving(homeId)
	local state = DoorControlService.GetDoorState(homeId)
	return state == DoorState.OPENING or state == DoorState.CLOSING
end

--[[
	获取所有门的状态（调试用）
	@return table - 所有门的状态信息
]]
function DoorControlService.GetAllDoorStates()
	local states = {}
	for homeId, doorData in pairs(DoorCache.Valid) do
		states[homeId] = doorData.State
	end
	return states
end

--[[
	调试输出（开发期使用）
	打印每个门的详细结构和状态
]]
function DoorControlService.DebugPrint()
	Log("=== 门控制服务调试信息 ===")
	Log("初始化状态: " .. tostring(Initialized))

	Log("\n有效门 (" .. #DoorCache.Valid .. "):")
	for homeId, doorData in pairs(DoorCache.Valid) do
		Log("  PlayerHome" .. homeId .. ":")
		Log("    状态: " .. doorData.State)
		Log("    左门: " .. doorData.Left.Type .. " (" .. doorData.Left.Node.Name .. ")")
		Log("    右门: " .. doorData.Right.Type .. " (" .. doorData.Right.Node.Name .. ")")
		Log("    Tweens: Left=" .. tostring(doorData.Tweens.Left ~= nil) .. ", Right=" .. tostring(doorData.Tweens.Right ~= nil))
	end

	if next(DoorCache.Failed) then
		Log("\n失败门:")
		for homeId, reason in pairs(DoorCache.Failed) do
			Log("  PlayerHome" .. homeId .. ": " .. reason)
		end
	end

	Log("========================")
end

--[[
	刷新门缓存（热加载用，重新扫描场景）
	注意：会中断当前所有动画，并重新读取配置
	@return boolean - 是否刷新成功
]]
function DoorControlService.Refresh()
	Log("正在刷新门控制服务...")

	-- 取消所有正在进行的Tween
	for homeId, doorData in pairs(DoorCache.Valid) do
		CancelDoorTweens(doorData)
	end

	-- 清空缓存
	DoorCache.Valid = {}
	DoorCache.Failed = {}
	WarnOnceCache = {}
	Initialized = false

	-- 重新读取配置（热更新）
	-- 注意：Roblox中require会缓存模块，这里直接重新require并手动更新DOOR_CONFIG
	local success, newConfig = pcall(function()
		local configModule = ReplicatedStorage:FindFirstChild("Config")
		if configModule then
			local gameConfigModule = configModule:FindFirstChild("GameConfig")
			if gameConfigModule then
				-- 直接重新require（虽然会返回缓存，但我们手动更新配置）
				return require(gameConfigModule)
			end
		end
		return nil
	end)

	if success and newConfig and newConfig.Door then
		-- 手动更新全局配置（这样即使模块被缓存，配置也能更新）
		for key, value in pairs(newConfig.Door) do
			DOOR_CONFIG[key] = value
		end
		Log("✓ 门配置已热更新: TweenDuration=" .. tostring(DOOR_CONFIG.TweenDuration)
			.. ", LeftOpenAngle=" .. tostring(DOOR_CONFIG.LeftOpenAngle))
	else
		WarnLog("配置热更新失败，使用旧配置")
	end

	-- 重新初始化
	return DoorControlService.Initialize()
end

-- ==================== 模块导出 ====================
return DoorControlService
