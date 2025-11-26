--[[
脚本名称: DragSystem
脚本类型: LocalScript (客户端系统)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/DragSystem
]]

--[[
已放置兵种拖动系统 (V2.0重构: 支持任意矩形占地)
职责:
1. 检测玩家点击已放置的兵种
2. 处理拖动逻辑，移动兵种位置
3. 实现拖动合成功能
4. 与服务端通信，更新兵种位置/合成
版本: V2.0

占地尺寸约定:
- GridWidth: X轴方向占用的格子数
- GridDepth: Z轴方向占用的格子数
- 支持任意矩形: 1x1, 1x2, 2x2, 2x3, 3x3, 4x7 等
]]

local DragSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用工具模块
local PlacementHelper = require(script.Parent.Parent.Utils.PlacementHelper)
local GridHelper = require(script.Parent.Parent.Utils.GridHelper)
local HighlightHelper = require(script.Parent.Parent.Utils.HighlightHelper)

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

-- V2.0重构: 拖动状态使用GridWidth和GridDepth
local dragState = {
	isDragging = false,
	draggedModel = nil,
	draggedInstanceId = nil,
	draggedUnitId = nil,
	draggedLevel = nil,
	-- V2.0: 使用GridWidth和GridDepth替代GridSize
	draggedGridWidth = nil,
	draggedGridDepth = nil,
	dragStartPos = nil,
	idleFloor = nil,
	originalCanCollide = nil,
	placedUnits = {},
	targetModel = nil,
	canMerge = false,
	isRelocating = false,
	isMobile = false,
	currentTouch = nil,
}

-- 远程事件
local mergeEvents = nil
local placementEvents = nil

-- ==================== 初始化 ====================

--[[
初始化拖动系统
]]
function DragSystem.Initialize()
	print("[DragSystem] 正在初始化...")

	-- 初始化GridHelper (V1.4)
	GridHelper.Initialize()

	-- V1.4: 检测设备类型
	dragState.isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	print("[DragSystem] 设备类型:", dragState.isMobile and "移动端" or "PC端")

	-- 等待玩家角色加载
	local character = player.Character or player.CharacterAdded:Wait()
	print("[DragSystem] 玩家角色已加载")

	-- 等待基地分配完成
	task.wait(2)

	-- 查找IdleFloor
	dragState.idleFloor = FindPlayerIdleFloor()
	if dragState.idleFloor then
		print("[DragSystem] 找到IdleFloor:", dragState.idleFloor:GetFullName())
	else
		warn("[DragSystem] 找不到IdleFloor")
		return false
	end

	-- V1.4: 获取合成事件
	local maxRetries = 10
	local retryCount = 0
	while not mergeEvents and retryCount < maxRetries do
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			mergeEvents = eventsFolder:FindFirstChild("MergeEvents")
		end
		if not mergeEvents then
			task.wait(0.5)
			retryCount = retryCount + 1
		end
	end

	if not mergeEvents then
		warn("[DragSystem] MergeEvents未找到，合成功能将不可用!")
	else
		-- 连接合成响应事件
		local responseEvent = mergeEvents:FindFirstChild("MergeResponse")
		if responseEvent then
			responseEvent.OnClientEvent:Connect(OnMergeResponse)
		end
	end

	-- V1.4.1: 获取放置事件（用于换位功能）
	retryCount = 0
	while not placementEvents and retryCount < maxRetries do
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			placementEvents = eventsFolder:FindFirstChild("PlacementEvents")
		end
		if not placementEvents then
			task.wait(0.5)
			retryCount = retryCount + 1
		end
	end

	if not placementEvents then
		warn("[DragSystem] PlacementEvents未找到，换位功能将不可用!")
	else
		-- 连接位置更新响应事件
		local updateResponseEvent = placementEvents:FindFirstChild("UpdateResponse")
		if updateResponseEvent then
			updateResponseEvent.OnClientEvent:Connect(OnUpdateResponse)
		end
	end

	-- 连接输入事件
	if dragState.isMobile then
		print("[DragSystem] 连接移动端触摸事件")
		ConnectMobileEvents()
	else
		print("[DragSystem] 连接PC端鼠标事件")
		ConnectMouseEvents()
	end

	print("[DragSystem] 初始化完成")
	return true
end

-- ==================== IdleFloor查找 ====================

--[[
查找玩家的IdleFloor
优先使用玩家实际所在的基地，而不是就近原则
@return Part|nil
]]
function FindPlayerIdleFloor()
	local character = player.Character
	if not character then
		return nil
	end

	if not character.PrimaryPart then
		return nil
	end

	local playerPos = character.PrimaryPart.Position

	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	-- 策略1: 先尝试找到玩家当前实际所在的基地（距离阈值内）
	local currentFloor = nil
	local minDistance = math.huge

	for i = 1, 6 do
		local playerHome = homeFolder:FindFirstChild("PlayerHome" .. i)
		if playerHome then
			local idleFloor = playerHome:FindFirstChild("IdleFloor")
			if idleFloor then
				local distance = (idleFloor.Position - playerPos).Magnitude
				-- 如果玩家在这个基地的合理范围内（比如100studs），认为这是他的基地
				if distance < 100 and distance < minDistance then
					minDistance = distance
					currentFloor = idleFloor
				end
			end
		end
	end

	-- 如果在合理范围内找到了基地，优先使用
	if currentFloor then
		print("[DragSystem] 找到玩家当前基地，距离:", minDistance)
		return currentFloor
	end

	-- 策略2: 如果没有在合理范围内找到，则使用最近的基地（兼容性）
	local nearestFloor = nil
	local nearestDistance = math.huge

	for i = 1, 6 do
		local playerHome = homeFolder:FindFirstChild("PlayerHome" .. i)
		if playerHome then
			local idleFloor = playerHome:FindFirstChild("IdleFloor")
			if idleFloor then
				local distance = (idleFloor.Position - playerPos).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearestFloor = idleFloor
				end
			end
		end
	end

	if nearestFloor then
		warn("[DragSystem] 未在合理范围内找到基地，使用最近基地，距离:", nearestDistance)
	end

	return nearestFloor
end

-- ==================== PC端鼠标事件处理 ====================

--[[
连接PC端鼠标事件
]]
function ConnectMouseEvents()
	-- 鼠标按下 - 检测是否点击到已放置的兵种
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- 创建射线检测
			local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
			local rayOrigin = mouseRay.Origin
			local rayDirection = mouseRay.Direction * 1000

			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = {player.Character}

			local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

			if raycastResult then
				local hitPart = raycastResult.Instance
				if hitPart then
					-- 查找父模型
					local model = hitPart.Parent
					while model and model ~= Workspace do
						if model:FindFirstChild("Humanoid") and model:GetAttribute("InstanceId") then
							-- 这是一个已放置的NPC模型
							print("[DragSystem] 检测到点击模型:", model.Name)
							StartDragging(model)
							return
						end
						model = model.Parent
					end
				end
			end
		end
	end)

	-- 鼠标移动 - 拖动已选中的模型
	RunService.RenderStepped:Connect(function()
		if dragState.isDragging and dragState.draggedModel then
			UpdateDragPosition()
		end
	end)

	-- 鼠标释放 - 结束拖动
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if dragState.isDragging then
				StopDragging()
			end
		end
	end)
end

-- ==================== 移动端触摸事件处理 ====================

--[[
连接移动端触摸事件
]]
function ConnectMobileEvents()
	-- 触摸开始 - 检测是否触摸到已放置的兵种
	UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
		if gameProcessed then
			return
		end

		-- 如果已经在拖动，忽略新的触摸
		if dragState.isDragging then
			return
		end

		-- 创建射线检测
		local touchPos = touch.Position
		local touchRay = camera:ScreenPointToRay(touchPos.X, touchPos.Y)
		local rayOrigin = touchRay.Origin
		local rayDirection = touchRay.Direction * 1000

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {player.Character}

		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

		if raycastResult then
			local hitPart = raycastResult.Instance
			if hitPart then
				-- 查找父模型
				local model = hitPart.Parent
				while model and model ~= Workspace do
					if model:FindFirstChild("Humanoid") and model:GetAttribute("InstanceId") then
						-- 这是一个已放置的NPC模型，开始拖动
						print("[DragSystem] 移动端检测到触摸模型:", model.Name)
						dragState.currentTouch = touch
						StartDragging(model)
						return
					end
					model = model.Parent
				end
			end
		end
	end)

	-- 触摸移动 - 更新拖动位置
	UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
		-- 不检查gameProcessed，允许拖动时穿过UI

		if not dragState.isDragging or not dragState.draggedModel then
			return
		end

		-- 只响应当前拖动的触摸
		if dragState.currentTouch and touch ~= dragState.currentTouch then
			return
		end

		-- 更新拖动位置
		UpdateDragPositionTouch(touch.Position)
	end)

	-- 触摸结束 - 停止拖动
	UserInputService.TouchEnded:Connect(function(touch, gameProcessed)
		if not dragState.isDragging then
			return
		end

		-- 只响应当前拖动的触摸
		if dragState.currentTouch and touch == dragState.currentTouch then
			dragState.currentTouch = nil
			StopDragging()
		end
	end)
end

-- ==================== 拖动逻辑 ====================

--[[
开始拖动模型
@param model Model - 要拖动的模型
]]
function StartDragging(model)
	if not model or dragState.isDragging then
		return
	end

	-- 检查模型是否在IdleFloor上
	if not IsModelOnIdleFloor(model) then
		return
	end

	-- 获取兵种信息
	local instanceId = model:GetAttribute("InstanceId")
	if not instanceId then
		warn("[DragSystem] 模型没有InstanceId属性")
		return
	end

	local unitId = model:GetAttribute("UnitId")
	local level = model:GetAttribute("Level") or 1
	-- V2.0: 使用GridWidth和GridDepth (向后兼容GridSize)
	local gridWidth = model:GetAttribute("GridWidth") or model:GetAttribute("GridSize") or 1
	local gridDepth = model:GetAttribute("GridDepth") or gridWidth

	print("[DragSystem] 开始拖动:", model:GetFullName(), "Level:", level)

	dragState.isDragging = true
	dragState.draggedModel = model
	dragState.draggedInstanceId = instanceId
	dragState.draggedUnitId = unitId
	dragState.draggedLevel = level
	dragState.draggedGridWidth = gridWidth
	dragState.draggedGridDepth = gridDepth

	-- 保存原始位置
	local originalPos = GetModelPosition(model)
	dragState.dragStartPos = originalPos

	-- 保存原始CanCollide状态
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		dragState.originalCanCollide = hrp.CanCollide
	end

	-- 彻底禁用Humanoid的自动行为（防止自动切回Running状态导致下沉）
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local tracks = animator:GetPlayingAnimationTracks()
			for _, track in ipairs(tracks) do
				track:Stop()
			end
		end
	end

	-- 拖动时取消碰撞，保持锚定，防止物理影响
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Anchored = true
		end
	end

	-- 对齐到网格中心，避免累计偏移
	if dragState.idleFloor and originalPos then
		local snapped = PlacementHelper.GetNearestGridPosition(originalPos, dragState.idleFloor.Position, gridWidth, gridDepth)
		PlacementHelper.SetModelPosition(model, snapped)
		GridHelper.ShowGrid(gridWidth, snapped, true, gridDepth)
	else
		-- V2.0: 显示绿色Grid（默认状态，保持原高度）
		GridHelper.ShowGrid(gridWidth, originalPos, true, gridDepth)
	end

	-- 设置绿色描边（默认拖动状态）
	HighlightHelper.SetDraggingHighlight(model, true)
end

--[[
更新拖动位置（PC端鼠标）
]]
function UpdateDragPosition()
	if not dragState.draggedModel or not dragState.idleFloor then
		return
	end

	-- 获取鼠标在IdleFloor上的位置
	local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local rayOrigin = mouseRay.Origin
	local rayDirection = mouseRay.Direction * 1000

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {player.Character, dragState.draggedModel}

	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if raycastResult then
		ProcessDragUpdate(raycastResult)
	else
		-- 没有击中任何东西
		dragState.targetModel = nil
		dragState.canMerge = false
		GridHelper.HideGrid()
	end
end

--[[
更新拖动位置（移动端触摸）
@param touchPosition Vector2 - 触摸屏幕位置
]]
function UpdateDragPositionTouch(touchPosition)
	if not dragState.draggedModel or not dragState.idleFloor then
		return
	end

	-- 获取触摸点在世界中的位置
	local touchRay = camera:ScreenPointToRay(touchPosition.X, touchPosition.Y)
	local rayOrigin = touchRay.Origin
	local rayDirection = touchRay.Direction * 1000

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {player.Character, dragState.draggedModel}

	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if raycastResult then
		ProcessDragUpdate(raycastResult)
	else
		-- 没有击中任何东西
		dragState.targetModel = nil
		dragState.canMerge = false
		GridHelper.HideGrid()
	end
end

--[[
处理拖动更新（统一处理PC和移动端）(V2.0重构: 支持矩形占地)
@param raycastResult RaycastResult
]]
function ProcessDragUpdate(raycastResult)
	local hitPart = raycastResult.Instance
	local hitModel = nil

	-- 优先查找被射线击中的兵种模型（避免先判断地板导致闪烁）
	if hitPart then
		local parent = hitPart.Parent
		while parent and parent ~= Workspace do
			if parent:FindFirstChild("Humanoid") and parent:GetAttribute("InstanceId") then
				hitModel = parent
				break
			end
			parent = parent.Parent
		end
	end

	-- V2.0.3: 计算正确的Y坐标（防止兵种下沉）
	local correctY = dragState.dragStartPos and dragState.dragStartPos.Y or nil
	if not correctY and dragState.idleFloor then
		-- 使用PlacementHelper计算正确的Y坐标
		local floorCenter = dragState.idleFloor.Position
		local tempPos = PlacementHelper.GridToWorld(0, 0, floorCenter, 1, 1)
		correctY = tempPos.Y
	end

	-- 判断拖动模式 - 优先判断合成模式
	if hitModel and hitModel ~= dragState.draggedModel then
		-- ==================== 合成模式（优先） ====================
		local targetInstanceId = hitModel:GetAttribute("InstanceId")
		local targetUnitId = hitModel:GetAttribute("UnitId")
		local targetLevel = hitModel:GetAttribute("Level") or 1
		-- V2.0: 获取目标的GridWidth和GridDepth
		local targetGridWidth = hitModel:GetAttribute("GridWidth") or hitModel:GetAttribute("GridSize") or 1
		local targetGridDepth = hitModel:GetAttribute("GridDepth") or targetGridWidth

		-- 检查是否可以合成
		local canMerge = (targetUnitId == dragState.draggedUnitId) and
			(targetLevel == dragState.draggedLevel) and
			(dragState.draggedLevel < 3)  -- 最高等级3

		-- 检测模式切换（从换位模式切换到合成模式）
		local modeChanged = dragState.isRelocating or (dragState.targetModel ~= hitModel)

		dragState.targetModel = hitModel
		dragState.canMerge = canMerge
		dragState.isRelocating = false  -- 不是换位模式

		-- 如果模式切换或目标改变，强制刷新Grid（清除缓存）
		if modeChanged then
			GridHelper.HideGrid()
		end

		-- V2.0: 显示Grid提示（在目标脚底）
		local targetPos = GetModelPosition(hitModel)
		GridHelper.ShowGrid(targetGridWidth, targetPos, canMerge, targetGridDepth)

		-- 设置拖动模型的描边颜色
		HighlightHelper.SetDraggingHighlight(dragState.draggedModel, canMerge)

		-- V2.0.3: 移动拖动的模型到目标位置（使用正确的Y坐标）
		local newPos = Vector3.new(targetPos.X, correctY or targetPos.Y, targetPos.Z)
		SetModelPosition(dragState.draggedModel, newPos)

	elseif raycastResult.Instance == dragState.idleFloor then
		-- ==================== IdleFloor上的拖动逻辑 ====================
		-- V2.0: 使用PlacementHelper进行网格吸附
		local snappedPos = PlacementHelper.GetNearestGridPosition(
			raycastResult.Position,
			dragState.idleFloor.Position,
			dragState.draggedGridWidth,
			dragState.draggedGridDepth
		)

		-- V2.0.3: 强制使用正确的Y坐标（防止下沉）
		if correctY then
			snappedPos = Vector3.new(snappedPos.X, correctY, snappedPos.Z)
		end

		-- 检测该位置是否有冲突并获取占用的模型
		local isValid, occupyingModel = IsPositionValidForRelocate(snappedPos)

		-- 如果位置无效且有占用模型，检查是否可以合成
		local canMerge = false
		if not isValid and occupyingModel then
			local targetUnitId = occupyingModel:GetAttribute("UnitId")
			local targetLevel = occupyingModel:GetAttribute("Level") or 1

			-- 检查合成条件
			canMerge = (targetUnitId == dragState.draggedUnitId) and
				(targetLevel == dragState.draggedLevel) and
				(dragState.draggedLevel < 3)  -- 最高等级3

			if canMerge then
				-- 满足合成条件：切换到合成模式
				dragState.targetModel = occupyingModel
				dragState.canMerge = true
				dragState.isRelocating = false  -- 不是换位模式，是合成模式
				isValid = true  -- 标记为绿色
			end
		else
			-- 位置有效（空位）或其他情况：使用换位模式
			dragState.targetModel = nil
			dragState.canMerge = false
			dragState.isRelocating = true  -- 换位模式
		end

		-- 检测模式切换，强制刷新Grid
		local modeChanged = false
		if canMerge and dragState.isRelocating == false then
			modeChanged = (not dragState.canMerge or dragState.targetModel == nil)
		elseif not canMerge and dragState.isRelocating == true then
			modeChanged = (dragState.canMerge or dragState.targetModel ~= nil)
		end

		if modeChanged then
			GridHelper.HideGrid()
		end

		local model = dragState.draggedModel

		-- V2.0: 显示Grid提示
		GridHelper.ShowGrid(dragState.draggedGridWidth, snappedPos, isValid, dragState.draggedGridDepth)

		-- V1.4.1: 设置拖动模型的描边颜色
		HighlightHelper.SetDraggingHighlight(model, isValid)

		-- V2.0.3: 移动模型（使用正确的Y坐标）
		SetModelPosition(model, snappedPos)

	else
		-- ==================== 其他情况（不在IdleFloor上或其他未识别情况）====================
		dragState.targetModel = nil
		dragState.canMerge = false
		dragState.isRelocating = false
		GridHelper.HideGrid()
		HighlightHelper.SetDraggingHighlight(dragState.draggedModel, false)
	end
end

--[[
停止拖动 V1.4.1重写
]]
function StopDragging()
	if not dragState.isDragging or not dragState.draggedModel then
		return
	end

	print("[DragSystem] 停止拖动:", dragState.draggedModel:GetFullName())

	local model = dragState.draggedModel

	-- V1.4.1: 判断拖动模式并处理
	if dragState.canMerge and dragState.targetModel and mergeEvents then
		-- ==================== 合成模式 ====================
		local targetInstanceId = dragState.targetModel:GetAttribute("InstanceId")

		print("[DragSystem] 请求合成:", dragState.draggedInstanceId, "->", targetInstanceId)

		-- 发送合成请求到服务端
		local requestEvent = mergeEvents:FindFirstChild("RequestMerge")
		if requestEvent then
			requestEvent:FireServer(dragState.draggedInstanceId, targetInstanceId)
		end

		-- 隐藏Grid，等待服务端响应
		GridHelper.HideGrid()
		-- 注意：不在这里恢复模型状态，等待服务端合成响应

	elseif dragState.isRelocating and placementEvents then
		-- ==================== 换位模式 ====================
		local currentPos = GetModelPosition(model)
		if currentPos then
			-- 检查该位置是否有效
			local isValid, _ = IsPositionValidForRelocate(currentPos)  -- V1.5.1: 接收第二个返回值
			if isValid then
				print("[DragSystem] 请求换位:", dragState.draggedInstanceId, "新位置:", currentPos)

				-- 发送位置更新请求到服务端（使用对齐后的网格中心）
				local snappedPos = PlacementHelper.GetNearestGridPosition(currentPos, dragState.idleFloor.Position, dragState.draggedGridWidth, dragState.draggedGridDepth)
				local updateEvent = placementEvents:FindFirstChild("UpdatePosition")
				if updateEvent then
					updateEvent:FireServer(dragState.draggedInstanceId, snappedPos)
				end

				-- 恢复模型状态（在服务端确认前）
				RestoreModelAfterDrag(model)
				GridHelper.HideGrid()
			else
				-- 位置无效，回到原位
				print("[DragSystem] 换位位置无效，回到原位")
				ReturnToOriginalPosition(model)
			end
		else
			ReturnToOriginalPosition(model)
		end

	else
		-- ==================== 取消拖动（回到原位） ====================
		print("[DragSystem] 取消拖动，回到原位")
		ReturnToOriginalPosition(model)
	end

	-- V2.0: 重置拖动状态
	dragState.isDragging = false
	dragState.draggedModel = nil
	dragState.draggedInstanceId = nil
	dragState.draggedUnitId = nil
	dragState.draggedLevel = nil
	dragState.draggedGridWidth = nil
	dragState.draggedGridDepth = nil
	dragState.dragStartPos = nil
	dragState.targetModel = nil
	dragState.canMerge = false
	dragState.isRelocating = false
	dragState.currentTouch = nil
end

-- ==================== 工具函数 ====================

--[[
恢复模型拖动后的状态（V1.4.1）
@param model Model
]]
function RestoreModelAfterDrag(model)
	if not model then
		return
	end

	-- V1.4.1: 恢复Humanoid的正常行为
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false  -- 恢复Humanoid控制
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)  -- 切换回正常状态
	end

	-- 恢复锚固和碰撞
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true  -- 恢复锚固
			if descendant.Name == "HumanoidRootPart" then
				descendant.CanCollide = dragState.originalCanCollide or false
			else
				descendant.CanCollide = false
			end
		end
	end

	-- V1.4.1: 设置默认描边（透明）
	HighlightHelper.SetDefaultHighlight(model)
end

--[[
返回到原始位置（V1.4.1）
@param model Model
]]
function ReturnToOriginalPosition(model)
	if not model or not dragState.dragStartPos then
		return
	end

	-- 移动回原位
	SetModelPosition(model, dragState.dragStartPos)

	-- 恢复模型状态
	RestoreModelAfterDrag(model)

	-- 隐藏Grid
	GridHelper.HideGrid()
end

--[[
检查模型是否在IdleFloor上
@param model Model
@return boolean
]]
function IsModelOnIdleFloor(model)
	if not model or not dragState.idleFloor then
		return false
	end

	local modelPos = GetModelPosition(model)
	if not modelPos then
		return false
	end

	local floorPos = dragState.idleFloor.Position
	local floorSize = dragState.idleFloor.Size

	-- 检查模型是否在地板范围内
	local distX = math.abs(modelPos.X - floorPos.X)
	local distZ = math.abs(modelPos.Z - floorPos.Z)

	return distX <= floorSize.X / 2 and distZ <= floorSize.Z / 2
end

--[[
检查换位时的位置是否有效 (V2.0重构: 支持矩形占地)
@param worldPos Vector3 - 世界坐标
@return boolean, Model|nil - 第一个返回值表示是否有效，第二个返回值是占用的模型（如果有冲突）
]]
function IsPositionValidForRelocate(worldPos)
	if not dragState.idleFloor then
		return false, nil
	end

	local floorCenter = dragState.idleFloor.Position

	-- 转换为网格坐标
	local gridX, gridZ = PlacementHelper.WorldToGrid(worldPos, floorCenter)

	-- V2.0: 获取当前兵种占地尺寸
	local currentGridWidth = dragState.draggedGridWidth or 1
	local currentGridDepth = dragState.draggedGridDepth or currentGridWidth

	-- 检查与已放置的模型是否重叠（需要排除自己）
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj ~= dragState.draggedModel then
			local objInstanceId = obj:GetAttribute("InstanceId")
			if objInstanceId and objInstanceId ~= dragState.draggedInstanceId then
				-- 这是另一个已放置的兵种
				local objPos = GetModelPosition(obj)
				if objPos then
					local objGridX, objGridZ = PlacementHelper.WorldToGrid(objPos, floorCenter)
					-- V2.0: 获取对象的GridWidth和GridDepth (向后兼容GridSize)
					local objGridWidth = obj:GetAttribute("GridWidth") or obj:GetAttribute("GridSize") or 1
					local objGridDepth = obj:GetAttribute("GridDepth") or objGridWidth

					-- 检查矩形网格是否重叠
					local overlapX = not (gridX + currentGridWidth <= objGridX or gridX >= objGridX + objGridWidth)
					local overlapZ = not (gridZ + currentGridDepth <= objGridZ or gridZ >= objGridZ + objGridDepth)

					if overlapX and overlapZ then
						return false, obj  -- 位置冲突，返回占用的模型
					end
				end
			end
		end
	end

	return true, nil  -- 位置有效
end

--[[
获取模型位置
@param model Model
@return Vector3|nil
]]
function GetModelPosition(model)
	if not model then
		return nil
	end

	if model.PrimaryPart then
		return model.PrimaryPart.Position
	elseif model:FindFirstChild("HumanoidRootPart") then
		return model.HumanoidRootPart.Position
	end

	return nil
end

--[[
设置模型位置
@param model Model
@param position Vector3
]]
function SetModelPosition(model, position)
	if not model or not position then
		return
	end

	if model.PrimaryPart then
		model:SetPrimaryPartCFrame(CFrame.new(position))
	elseif model:FindFirstChild("HumanoidRootPart") then
		model.HumanoidRootPart.CFrame = CFrame.new(position)
	end
end

-- ==================== V1.4: 合成响应处理 ====================

--[[
处理服务端合成响应
@param success boolean - 是否成功
@param message string - 消息
@param newUnitData table|nil - 新兵种数据
]]
function OnMergeResponse(success, message, newUnitData)
	print("[DragSystem] 收到合成响应:", success, message)

	if success then
		print("[DragSystem] 合成成功! 新等级:", newUnitData and newUnitData.Level or "?")
		-- 服务端已经处理了模型的移除和新建，客户端不需要额外操作
		-- 等待新模型自动同步
	else
		warn("[DragSystem] 合成失败:", message)
		-- 可以在这里添加UI提示
	end
end

-- ==================== V1.4.1: 换位响应处理 ====================

--[[
处理服务端位置更新响应
@param success boolean - 是否成功
@param message string - 消息
@param instanceId string - 兵种实例ID
]]
function OnUpdateResponse(success, message, instanceId)
	print("[DragSystem] 收到位置更新响应:", success, message, instanceId)

	if success then
		print("[DragSystem] 换位成功!")
		-- 服务端已经更新了位置，客户端已经在StopDragging中做了处理
	else
		warn("[DragSystem] 换位失败:", message)
		-- 可以在这里添加UI提示
		-- 如果失败，可能需要将模型恢复到原位（但通常服务端会拒绝前客户端已经检查了）
	end
end

-- ==================== 全局访问 ====================

_G.DragSystem = DragSystem

-- 自动初始化
task.spawn(function()
	task.wait(1)
	DragSystem.Initialize()
end)

return DragSystem
