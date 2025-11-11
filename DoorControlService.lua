--[[
=====================================================
脚本名称: DoorControlService
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/DoorControlService.lua
版本: V2.0.1
最后更新: 2025-01-11

功能说明：
管理玩家基地的门开关动画
- 每个PlayerHome有一个MetalDoor，包含DoorLeft和DoorRight
- 支持1秒动画打开（90°/-90°）和关闭（0°）
- 状态机管理，防止重复调用冲突
- 支持战役流程中的门控制

核心API：
- DoorControlService.Initialize() - 初始化所有门并缓存
- DoorControlService.OpenDoor(homeId, onCompleted) - 打开门
- DoorControlService.CloseDoor(homeId, onCompleted) - 关闭门
- DoorControlService.SetDoorState(homeId, state) - 直接设置状态（重连用）
- DoorControlService.GetDoorState(homeId) - 获取当前状态
- DoorControlService.IsMoving(homeId) - 门是否在动画中

门状态：
- Closed: 门关闭（0°）
- Opening: 门打开中（Tween播放中）
- Open: 门已打开（90°/-90°）
- Closing: 门关闭中（Tween播放中）
=====================================================
]]

local DoorControlService = {}

-- ==================== 服务引用 ====================
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- ==================== 常量定义 ====================
local DoorState = {
	CLOSED = "Closed",
	OPENING = "Opening",
	OPEN = "Open",
	CLOSING = "Closing"
}

-- 门动画配置
local DOOR_CONFIG = {
	TweenDuration = 1,                    -- 动画时长（秒）
	LeftOpenAngle = 90,                   -- 左门打开角度（度）
	RightOpenAngle = -90,                 -- 右门打开角度（度）
	ClosedAngle = 0,                      -- 关闭角度（度）
	EasingStyle = Enum.EasingStyle.Quad,  -- 缓动样式
	EasingDirection = Enum.EasingDirection.InOut
}

-- ==================== 私有变量 ====================
local DoorCache = {}  -- [homeId] = { 门数据 }
local Initialized = false

-- ==================== 工具函数 ====================
local function Log(message)
	print("[DoorControlService]", message)
end

local function WarnLog(message)
	warn("[DoorControlService]", message)
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

--[[
	手动 Tween Model 旋转 (用于 Model 类型的门)
	@param model Model - 要旋转的 Model
	@param targetAngleY number - 目标Y轴角度(度)
	@param duration number - 动画时长(秒)
	@param onComplete function - 完成回调
	@return Connection - RunService连接(用于取消)
]]
local function TweenModelRotation(model, targetAngleY, duration, onComplete)
	local startTime = tick()
	local startPivot = model:GetPivot()
	local startPos = startPivot.Position

	-- 从当前旋转中提取Y轴角度
	local _, startY, _ = startPivot:ToOrientation()
	local startAngleDeg = math.deg(startY)

	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / duration, 1)

		-- 应用缓动
		local easedAlpha = EaseInOutQuad(alpha)

		-- 计算当前角度
		local currentAngle = startAngleDeg + (targetAngleY - startAngleDeg) * easedAlpha

		-- 创建新的 CFrame (保持位置，只改变Y轴旋转)
		local newCFrame = CFrame.new(startPos) * CFrame.Angles(0, math.rad(currentAngle), 0)
		model:PivotTo(newCFrame)

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
	根据角度创建目标CFrame
	@param doorPart BasePart|Model - 门部件
	@param angleY number - Y轴角度（度）
	@return CFrame - 目标CFrame
]]
local function CreateTargetCFrame(doorPart, angleY)
	if not doorPart then
		return nil
	end

	-- 获取当前位置
	local currentCFrame
	if doorPart:IsA("Model") then
		currentCFrame = doorPart:GetPivot()
	else
		currentCFrame = doorPart.CFrame
	end

	-- 保持原位置，只改变Y轴旋转
	local position = currentCFrame.Position
	local rotation = CFrame.Angles(0, math.rad(angleY), 0)

	return CFrame.new(position) * rotation
end

--[[
	取消门的Tween动画
	@param doorData table - 门数据
]]
local function CancelDoorTweens(doorData)
	if doorData.LeftTween then
		doorData.LeftTween:Cancel()
		doorData.LeftTween = nil
	end

	if doorData.RightTween then
		doorData.RightTween:Cancel()
		doorData.RightTween = nil
	end

	-- 取消手动 Tween 连接（用于 Model）
	if doorData.LeftConnection then
		doorData.LeftConnection:Disconnect()
		doorData.LeftConnection = nil
	end

	if doorData.RightConnection then
		doorData.RightConnection:Disconnect()
		doorData.RightConnection = nil
	end
end

--[[
	确保门处于关闭状态（不播放动画，直接设置）
	@param homeId number - 基地ID
]]
local function EnsureDoorClosed(homeId)
	local doorData = DoorCache[homeId]
	if not doorData then
		return
	end

	-- 直接设置角度，不播放动画
	if doorData.DoorLeft then
		local targetCFrame = CreateTargetCFrame(doorData.DoorLeft, DOOR_CONFIG.ClosedAngle)
		if targetCFrame then
			if doorData.DoorLeft:IsA("Model") then
				doorData.DoorLeft:PivotTo(targetCFrame)
			else
				doorData.DoorLeft.CFrame = targetCFrame
			end
		end
	end

	if doorData.DoorRight then
		local targetCFrame = CreateTargetCFrame(doorData.DoorRight, DOOR_CONFIG.ClosedAngle)
		if targetCFrame then
			if doorData.DoorRight:IsA("Model") then
				doorData.DoorRight:PivotTo(targetCFrame)
			else
				doorData.DoorRight.CFrame = targetCFrame
			end
		end
	end

	doorData.State = DoorState.CLOSED
	Log("门已强制关闭: PlayerHome" .. homeId)
end

-- ==================== 公共方法 ====================

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

	Log("开始初始化门控制服务...")

	local workspace = game:GetService("Workspace")
	local homeFolder = workspace:FindFirstChild("Home")

	if not homeFolder then
		WarnLog("Workspace.Home 不存在，门控制服务初始化失败")
		return false
	end

	local successCount = 0
	local failedHomes = {}  -- 记录失败的基地及原因

	for homeId = 1, 6 do
		local homeName = "PlayerHome" .. homeId
		local home = homeFolder:FindFirstChild(homeName)

		if not home then
			local reason = homeName .. " 不存在于Workspace.Home"
			WarnLog(reason)
			failedHomes[homeId] = reason
			continue
		end

		-- 兼容两种命名：MetalDoor 和 MetalDoor01
		local door = home:FindFirstChild("MetalDoor") or home:FindFirstChild("MetalDoor01")
		if not door then
			local reason = homeName .. " 缺少 MetalDoor 或 MetalDoor01 文件夹"
			WarnLog(reason)
			failedHomes[homeId] = reason
			continue
		end

		-- 记录实际使用的门名称（用于日志）
		local doorName = door.Name
		Log("检测到 " .. homeName .. " 使用门: " .. doorName)

		local doorLeft = door:FindFirstChild("DoorLeft")
		local doorRight = door:FindFirstChild("DoorRight")

		if not doorLeft or not doorRight then
			local reason = homeName .. " " .. doorName .. " 缺少 " .. (not doorLeft and "DoorLeft" or "") .. (not doorRight and " DoorRight" or "")
			WarnLog(reason)
			failedHomes[homeId] = reason
			continue
		end

		-- 验证DoorLeft和DoorRight是否为BasePart或Model
		if not (doorLeft:IsA("BasePart") or doorLeft:IsA("Model")) then
			local reason = homeName .. " " .. doorName .. " - DoorLeft 不是 BasePart 或 Model: " .. doorLeft.ClassName
			WarnLog(reason)
			failedHomes[homeId] = reason
			continue
		end

		if not (doorRight:IsA("BasePart") or doorRight:IsA("Model")) then
			local reason = homeName .. " " .. doorName .. " - DoorRight 不是 BasePart 或 Model: " .. doorRight.ClassName
			WarnLog(reason)
			failedHomes[homeId] = reason
			continue
		end

		-- 缓存门数据（直接使用 DoorLeft 和 DoorRight）
		DoorCache[homeId] = {
			HomeId = homeId,
			Door = door,
			DoorLeft = doorLeft,
			DoorRight = doorRight,
			State = DoorState.CLOSED,
			LeftTween = nil,       -- 用于 BasePart 的 Tween
			RightTween = nil,      -- 用于 BasePart 的 Tween
			LeftConnection = nil,  -- 用于 Model 的手动 Tween 连接
			RightConnection = nil  -- 用于 Model 的手动 Tween 连接
		}

		-- 确保初始状态是关闭
		EnsureDoorClosed(homeId)

		successCount = successCount + 1
		Log("✓ " .. homeName .. " 门结构正确，已缓存")
	end

	Initialized = true
	Log("门控制服务初始化完成，成功: " .. successCount .. "/6")

	-- 输出失败的基地信息
	if next(failedHomes) then
		WarnLog("以下基地的门初始化失败:")
		for homeId, reason in pairs(failedHomes) do
			WarnLog("  PlayerHome" .. homeId .. ": " .. reason)
		end
	end

	return successCount > 0
end

--[[
	打开指定基地的门
	@param homeId number - 基地ID (1-6)
	@param onCompleted function|nil - 动画完成后的回调（可选）
	@return boolean - 是否成功开始打开
]]
function DoorControlService.OpenDoor(homeId, onCompleted)
	if not Initialized then
		WarnLog("DoorControlService未初始化，无法打开门")
		return false
	end

	local doorData = DoorCache[homeId]
	if not doorData then
		WarnLog("PlayerHome" .. homeId .. " 门数据不存在")
		return false
	end

	-- 检查当前状态
	if doorData.State == DoorState.OPEN then
		Log("门已经是打开状态: PlayerHome" .. homeId)
		if onCompleted then
			task.spawn(onCompleted)
		end
		return true
	end

	if doorData.State == DoorState.OPENING then
		Log("门正在打开中: PlayerHome" .. homeId .. "，跳过重复调用")
		return true
	end

	Log("开始打开门: PlayerHome" .. homeId)

	-- 取消旧的Tween（防抖）
	CancelDoorTweens(doorData)

	-- 设置状态
	doorData.State = DoorState.OPENING

	-- 完成计数器（需要两个门都完成才触发回调）
	local completedCount = 0
	local function onOneDoorCompleted()
		completedCount = completedCount + 1
		if completedCount >= 2 then
			doorData.State = DoorState.OPEN
			Log("门已打开: PlayerHome" .. homeId)

			-- 清理引用
			doorData.LeftTween = nil
			doorData.RightTween = nil
			doorData.LeftConnection = nil
			doorData.RightConnection = nil

			-- 触发回调
			if onCompleted then
				task.spawn(onCompleted)
			end
		end
	end

	-- 根据门类型选择旋转方式
	if doorData.DoorLeft:IsA("Model") then
		-- Model 使用手动插值 + PivotTo
		doorData.LeftConnection = TweenModelRotation(
			doorData.DoorLeft,
			DOOR_CONFIG.LeftOpenAngle,
			DOOR_CONFIG.TweenDuration,
			onOneDoorCompleted
		)
	else
		-- BasePart 使用 TweenService
		local leftTarget = CreateTargetCFrame(doorData.DoorLeft, DOOR_CONFIG.LeftOpenAngle)
		if not leftTarget then
			WarnLog("创建左门目标CFrame失败")
			return false
		end

		local tweenInfo = TweenInfo.new(
			DOOR_CONFIG.TweenDuration,
			DOOR_CONFIG.EasingStyle,
			DOOR_CONFIG.EasingDirection
		)

		doorData.LeftTween = TweenService:Create(
			doorData.DoorLeft,
			tweenInfo,
			{ CFrame = leftTarget }
		)

		doorData.LeftTween.Completed:Connect(onOneDoorCompleted)
		doorData.LeftTween:Play()
	end

	if doorData.DoorRight:IsA("Model") then
		-- Model 使用手动插值 + PivotTo
		doorData.RightConnection = TweenModelRotation(
			doorData.DoorRight,
			DOOR_CONFIG.RightOpenAngle,
			DOOR_CONFIG.TweenDuration,
			onOneDoorCompleted
		)
	else
		-- BasePart 使用 TweenService
		local rightTarget = CreateTargetCFrame(doorData.DoorRight, DOOR_CONFIG.RightOpenAngle)
		if not rightTarget then
			WarnLog("创建右门目标CFrame失败")
			return false
		end

		local tweenInfo = TweenInfo.new(
			DOOR_CONFIG.TweenDuration,
			DOOR_CONFIG.EasingStyle,
			DOOR_CONFIG.EasingDirection
		)

		doorData.RightTween = TweenService:Create(
			doorData.DoorRight,
			tweenInfo,
			{ CFrame = rightTarget }
		)

		doorData.RightTween.Completed:Connect(onOneDoorCompleted)
		doorData.RightTween:Play()
	end

	return true
end

--[[
	关闭指定基地的门
	@param homeId number - 基地ID (1-6)
	@param onCompleted function|nil - 动画完成后的回调（可选）
	@return boolean - 是否成功开始关闭
]]
function DoorControlService.CloseDoor(homeId, onCompleted)
	if not Initialized then
		WarnLog("DoorControlService未初始化，无法关闭门")
		return false
	end

	local doorData = DoorCache[homeId]
	if not doorData then
		WarnLog("PlayerHome" .. homeId .. " 门数据不存在")
		return false
	end

	-- 检查当前状态
	if doorData.State == DoorState.CLOSED then
		Log("门已经是关闭状态: PlayerHome" .. homeId)
		if onCompleted then
			task.spawn(onCompleted)
		end
		return true
	end

	if doorData.State == DoorState.CLOSING then
		Log("门正在关闭中: PlayerHome" .. homeId .. "，跳过重复调用")
		return true
	end

	Log("开始关闭门: PlayerHome" .. homeId)


	-- 取消旧的Tween（防抖）
	CancelDoorTweens(doorData)

	-- 设置状态
	doorData.State = DoorState.CLOSING

	-- 完成计数器（需要两个门都完成才触发回调）
	local completedCount = 0
	local function onOneDoorCompleted()
		completedCount = completedCount + 1
		if completedCount >= 2 then
			doorData.State = DoorState.CLOSED
			Log("门已关闭: PlayerHome" .. homeId)

			-- 清理引用
			doorData.LeftTween = nil
			doorData.RightTween = nil
			doorData.LeftConnection = nil
			doorData.RightConnection = nil

			-- 触发回调
			if onCompleted then
				task.spawn(onCompleted)
			end
		end
	end

	-- 根据门类型选择旋转方式
	if doorData.DoorLeft:IsA("Model") then
		-- Model 使用手动插值 + PivotTo
		doorData.LeftConnection = TweenModelRotation(
			doorData.DoorLeft,
			DOOR_CONFIG.ClosedAngle,
			DOOR_CONFIG.TweenDuration,
			onOneDoorCompleted
		)
	else
		-- BasePart 使用 TweenService
		local leftTarget = CreateTargetCFrame(doorData.DoorLeft, DOOR_CONFIG.ClosedAngle)
		if not leftTarget then
			WarnLog("创建左门目标CFrame失败")
			return false
		end

		local tweenInfo = TweenInfo.new(
			DOOR_CONFIG.TweenDuration,
			DOOR_CONFIG.EasingStyle,
			DOOR_CONFIG.EasingDirection
		)

		doorData.LeftTween = TweenService:Create(
			doorData.DoorLeft,
			tweenInfo,
			{ CFrame = leftTarget }
		)

		doorData.LeftTween.Completed:Connect(onOneDoorCompleted)
		doorData.LeftTween:Play()
	end

	if doorData.DoorRight:IsA("Model") then
		-- Model 使用手动插值 + PivotTo
		doorData.RightConnection = TweenModelRotation(
			doorData.DoorRight,
			DOOR_CONFIG.ClosedAngle,
			DOOR_CONFIG.TweenDuration,
			onOneDoorCompleted
		)
	else
		-- BasePart 使用 TweenService
		local rightTarget = CreateTargetCFrame(doorData.DoorRight, DOOR_CONFIG.ClosedAngle)
		if not rightTarget then
			WarnLog("创建右门目标CFrame失败")
			return false
		end

		local tweenInfo = TweenInfo.new(
			DOOR_CONFIG.TweenDuration,
			DOOR_CONFIG.EasingStyle,
			DOOR_CONFIG.EasingDirection
		)

		doorData.RightTween = TweenService:Create(
			doorData.DoorRight,
			tweenInfo,
			{ CFrame = rightTarget }
		)

		doorData.RightTween.Completed:Connect(onOneDoorCompleted)
		doorData.RightTween:Play()
	end

	return true
end
--[[
	直接设置门状态（无动画，用于重连恢复）
	@param homeId number - 基地ID (1-6)
	@param state string - 目标状态 ("Open" 或 "Closed")
	@return boolean - 是否成功设置
]]
function DoorControlService.SetDoorState(homeId, state)
	if not Initialized then
		WarnLog("DoorControlService未初始化")
		return false
	end

	local doorData = DoorCache[homeId]
	if not doorData then
		WarnLog("PlayerHome" .. homeId .. " 门数据不存在")
		return false
	end

	-- 取消所有动画
	CancelDoorTweens(doorData)

	if state == "Open" or state == DoorState.OPEN then
		-- 直接设置为打开状态
		if doorData.DoorLeft then
			local targetCFrame = CreateTargetCFrame(doorData.DoorLeft, DOOR_CONFIG.LeftOpenAngle)
			if targetCFrame then
				if doorData.DoorLeft:IsA("Model") then
					doorData.DoorLeft:PivotTo(targetCFrame)
				else
					doorData.DoorLeft.CFrame = targetCFrame
				end
			end
		end

		if doorData.DoorRight then
			local targetCFrame = CreateTargetCFrame(doorData.DoorRight, DOOR_CONFIG.RightOpenAngle)
			if targetCFrame then
				if doorData.DoorRight:IsA("Model") then
					doorData.DoorRight:PivotTo(targetCFrame)
				else
					doorData.DoorRight.CFrame = targetCFrame
				end
			end
		end

		doorData.State = DoorState.OPEN
		Log("门已设置为打开状态: PlayerHome" .. homeId)

	elseif state == "Closed" or state == DoorState.CLOSED then
		-- 直接设置为关闭状态
		EnsureDoorClosed(homeId)

	else
		WarnLog("未知的门状态: " .. tostring(state))
		return false
	end

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

	local doorData = DoorCache[homeId]
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
	for homeId, doorData in pairs(DoorCache) do
		states[homeId] = doorData.State
	end
	return states
end

-- ==================== 模块导出 ====================
return DoorControlService