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
local ContextActionService = game:GetService("ContextActionService")

-- 引用工具模块
local PlacementHelper = require(script.Parent.Parent.Utils.PlacementHelper)
local GridHelper = require(script.Parent.Parent.Utils.GridHelper)
local HighlightHelper = require(script.Parent.Parent.Utils.HighlightHelper)

-- V2.0.4: 引入UnitConfig用于获取占地尺寸（当模型属性缺失时）
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

-- 触发拖动的最小位移（像素）
local DRAG_START_MOVE_PX_MOUSE = 8
local DRAG_START_MOVE_PX_TOUCH = 18

-- 前向声明：供相机输入拦截函数访问
local dragState

-- 移动端拖动时屏蔽相机触摸旋转（方案一：ContextActionService吃掉触摸）
local BLOCK_CAMERA_ACTION = "DragSystem_BlockCameraTouch"
local CAMERA_BLOCK_PRIORITY = Enum.ContextActionPriority.High.Value + 200
local cameraBlockBound = false

local function BindCameraTouchBlock()
	if cameraBlockBound then
		return
	end
	-- 仅在支持触摸的设备上启用
	if not UserInputService.TouchEnabled then
		return
	end

	cameraBlockBound = true
	ContextActionService:BindActionAtPriority(
		BLOCK_CAMERA_ACTION,
		function(_, _, inputObject)
			-- 仅在拖动期间吃掉输入，平时不影响相机
			if not (dragState and dragState.isDragging) then
				return Enum.ContextActionResult.Pass
			end

			-- 只拦截当前拖动用的那根手指（避免影响移动摇杆/按钮等第二指操作）
			if inputObject
				and inputObject.UserInputType == Enum.UserInputType.Touch
				and dragState.currentTouch
				and inputObject ~= dragState.currentTouch
			then
				return Enum.ContextActionResult.Pass
			end

			return Enum.ContextActionResult.Sink
		end,
		false,
		CAMERA_BLOCK_PRIORITY,
		Enum.UserInputType.Touch,
		Enum.UserInputType.MouseMovement
	)
end

local function UnbindCameraTouchBlock()
	if not cameraBlockBound then
		return
	end
	cameraBlockBound = false
	ContextActionService:UnbindAction(BLOCK_CAMERA_ACTION)
end

-- 移动端拖动期间屏蔽镜头旋转（方案二：临时切到Scriptable，彻底屏蔽默认镜头拖拽旋转）
local dragCameraLock = {
	active = false,
	cameraType = nil,
	cameraSubject = nil,
}

local function LockCameraDuringDrag()
	if dragCameraLock.active then
		return
	end
	if not UserInputService.TouchEnabled then
		return
	end
	if not camera then
		return
	end

	-- 如果其他系统已经接管了Scriptable镜头（战斗/房屋升级等），这里不重复接管，避免互相覆盖
	if camera.CameraType == Enum.CameraType.Scriptable then
		return
	end

	dragCameraLock.active = true
	dragCameraLock.cameraType = camera.CameraType
	dragCameraLock.cameraSubject = camera.CameraSubject

	camera.CameraType = Enum.CameraType.Scriptable
end

local function UnlockCameraDuringDrag()
	if not dragCameraLock.active then
		return
	end
	dragCameraLock.active = false

	if camera then
		camera.CameraType = dragCameraLock.cameraType or Enum.CameraType.Custom
		if dragCameraLock.cameraSubject then
			camera.CameraSubject = dragCameraLock.cameraSubject
		end
	end

	dragCameraLock.cameraType = nil
	dragCameraLock.cameraSubject = nil
end

local function BeginPowerTipSuppression()
	local powerController = _G.PowerDisplayController
	if powerController and powerController.BeginPowerTipSuppression then
		powerController.BeginPowerTipSuppression()
	end
end

local function EndPowerTipSuppression()
	local powerController = _G.PowerDisplayController
	if powerController and powerController.EndPowerTipSuppression then
		powerController.EndPowerTipSuppression()
	end
end

-- V2.0重构: 拖动状态使用GridWidth和GridDepth
dragState = {
	isDragging = false,
	isMouseDown = false,
	pendingModel = nil,
	pendingStartPos = nil,
	pendingTouch = nil,
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

-- 最近一次拖动用于失败回退
local lastDragRestore = {
	model = nil,
	origin = nil,
}

local function ClearPendingDrag()
	dragState.pendingModel = nil
	dragState.pendingStartPos = nil
	dragState.pendingTouch = nil
end

-- 远程事件
local mergeEvents = nil
local placementEvents = nil

-- ==================== 初始化 ====================

--[[
初始化拖动系统
]]
function DragSystem.Initialize()
	-- print("[DragSystem] 正在初始化...")

	-- 初始化GridHelper (V1.4)
	GridHelper.Initialize()

	-- V1.4: 检测设备类型
	-- 只要支持触摸就按移动端处理（避免部分设备 MouseEnabled=true 导致误判，从而不触发镜头锁定）
	dragState.isMobile = PlacementHelper.IsMobileDevice()
	-- print("[DragSystem] 设备类型:", dragState.isMobile and "移动端" or "PC端")

	-- 移动端：提前绑定相机输入拦截，确保能作用于同一次触摸（避免拖动时镜头跟着转）
	BindCameraTouchBlock()

	-- 等待玩家角色加载
	local character = player.Character or player.CharacterAdded:Wait()
	-- print("[DragSystem] 玩家角色已加载")

	-- 等待基地分配完成
	task.wait(2)

	-- 查找IdleFloor
	dragState.idleFloor = FindPlayerIdleFloor()
	if dragState.idleFloor then
		-- print("[DragSystem] 找到IdleFloor:", dragState.idleFloor:GetFullName())
		-- V2.0.4: 设置GridHelper的IdleFloor引用，用于精确计算Grid的Y坐标
		GridHelper.SetIdleFloor(dragState.idleFloor)
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
		-- print("[DragSystem] 连接移动端触摸事件")
		ConnectMobileEvents()
	else
		-- print("[DragSystem] 连接PC端鼠标事件")
		ConnectMouseEvents()
	end

	-- print("[DragSystem] 初始化完成")
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
		-- print("[DragSystem] 找到玩家当前基地，距离:", minDistance)
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
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		dragState.isMouseDown = true

		if gameProcessed or dragState.isDragging then
			return
		end

		ClearPendingDrag()

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
						-- print("[DragSystem] 检测到点击模型:", model.Name)
						dragState.pendingModel = model
						dragState.pendingStartPos = UserInputService:GetMouseLocation()
						return
					end
					model = model.Parent
				end
			end
		end
	end)

	-- 鼠标移动 - 拖动已选中的模型
	RunService.RenderStepped:Connect(function()
		if dragState.isDragging and dragState.draggedModel then
			UpdateDragPosition()
			return
		end

		if dragState.pendingModel and dragState.isMouseDown and dragState.pendingStartPos then
			local currentPos = UserInputService:GetMouseLocation()
			if (currentPos - dragState.pendingStartPos).Magnitude >= DRAG_START_MOVE_PX_MOUSE then
				local model = dragState.pendingModel
				ClearPendingDrag()
				StartDragging(model)
			end
		end
	end)

	-- 鼠标释放 - 结束拖动
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragState.isMouseDown = false
			if dragState.isDragging then
				StopDragging()
			else
				ClearPendingDrag()
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

		ClearPendingDrag()

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
							-- 这是一个已放置的NPC模型，准备拖动
							-- print("[DragSystem] 移动端检测到触摸模型:", model.Name)
							dragState.pendingTouch = touch
							dragState.pendingStartPos = Vector2.new(touchPos.X, touchPos.Y)
							dragState.pendingModel = model
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

		if dragState.pendingModel and dragState.pendingTouch == touch and not dragState.isDragging then
			local startPos = dragState.pendingStartPos
			if startPos then
				local currentPos = Vector2.new(touch.Position.X, touch.Position.Y)
				if (currentPos - startPos).Magnitude >= DRAG_START_MOVE_PX_TOUCH then
					local model = dragState.pendingModel
					ClearPendingDrag()
					StartDragging(model)
					if dragState.isDragging then
						dragState.currentTouch = touch
					end
				end
			end
		end

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
		if dragState.pendingTouch and touch == dragState.pendingTouch and not dragState.isDragging then
			ClearPendingDrag()
			return
		end

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

	-- V2.0.4修复: 优先从模型属性读取，如果没有则从UnitConfig获取
	local gridWidth = model:GetAttribute("GridWidth")
	local gridDepth = model:GetAttribute("GridDepth")

	-- 如果模型属性缺失，从UnitConfig获取（兼容旧数据）
	if not gridWidth or not gridDepth then
		if unitId then
			gridWidth = gridWidth or UnitConfig.GetGridWidth(unitId)
			gridDepth = gridDepth or UnitConfig.GetGridDepth(unitId)
		else
			-- 回退到GridSize属性或默认值1
			local gridSize = model:GetAttribute("GridSize") or 1
			gridWidth = gridWidth or gridSize
			gridDepth = gridDepth or gridSize
		end
	end

	-- V2.0.4调试：打印占地尺寸，确认属性是否正确读取
	-- print(string.format("[DragSystem] 开始拖动: %s Level: %d GridSize: %dx%d", model:GetFullName(), level, gridWidth, gridDepth))

	dragState.isDragging = true
	-- 移动端：拖动期间锁定镜头，避免手指拖动导致相机旋转
	if dragState.isMobile then
		LockCameraDuringDrag()
	end
	dragState.draggedModel = model
	dragState.draggedInstanceId = instanceId
	dragState.draggedUnitId = unitId
	dragState.draggedLevel = level
	dragState.draggedGridWidth = gridWidth
	dragState.draggedGridDepth = gridDepth
	-- 清理上一次的回退缓存，防止旧数据干扰
	lastDragRestore.model = nil
	lastDragRestore.origin = nil

	-- 保存原始位置
	local originalPos = GetModelPosition(model)
	dragState.dragStartPos = originalPos

	-- 保存原始CanCollide状态
	local hrp = model:FindFirstChild("HumanoidRootPart")
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

		-- V2.0.4修复: 获取目标的GridWidth和GridDepth（从属性或UnitConfig）
		local targetGridWidth = hitModel:GetAttribute("GridWidth")
		local targetGridDepth = hitModel:GetAttribute("GridDepth")
		if not targetGridWidth or not targetGridDepth then
			if targetUnitId then
				targetGridWidth = targetGridWidth or UnitConfig.GetGridWidth(targetUnitId)
				targetGridDepth = targetGridDepth or UnitConfig.GetGridDepth(targetUnitId)
			else
				local targetGridSize = hitModel:GetAttribute("GridSize") or 1
				targetGridWidth = targetGridWidth or targetGridSize
				targetGridDepth = targetGridDepth or targetGridSize
			end
		end

		-- 检查是否可以合成
		local canMerge = (targetUnitId == dragState.draggedUnitId) and
			(targetLevel == dragState.draggedLevel) and
			(dragState.draggedLevel < UnitConfig.MAX_LEVEL)  -- 最高等级限制

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
				(dragState.draggedLevel < UnitConfig.MAX_LEVEL)  -- 最高等级限制

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

	-- print("[DragSystem] 停止拖动:", dragState.draggedModel:GetFullName())

	local model = dragState.draggedModel

	-- V1.4.1: 判断拖动模式并处理
	if dragState.canMerge and dragState.targetModel and mergeEvents then
		-- ==================== 合成模式 ====================
		local targetInstanceId = dragState.targetModel:GetAttribute("InstanceId")

		-- print("[DragSystem] 请求合成:", dragState.draggedInstanceId, "->", targetInstanceId)

		-- 发送合成请求到服务端
		local requestEvent = mergeEvents:FindFirstChild("RequestMerge")
		if requestEvent then
			BeginPowerTipSuppression()
			requestEvent:FireServer(dragState.draggedInstanceId, targetInstanceId)
		end

		-- 记录回退信息，防止合成失败后悬空
		lastDragRestore.model = model
		lastDragRestore.origin = dragState.dragStartPos

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
				-- print("[DragSystem] 请求换位:", dragState.draggedInstanceId, "新位置:", currentPos)

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
				-- print("[DragSystem] 换位位置无效，回到原位")
				ReturnToOriginalPosition(model)
			end
		else
			ReturnToOriginalPosition(model)
		end

	else
		-- ==================== 取消拖动（回到原位） ====================
		-- print("[DragSystem] 取消拖动，回到原位")
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

	-- 移动端：拖动结束后恢复镜头控制
	if dragState.isMobile then
		UnlockCameraDuringDrag()
	end
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

	-- 恢复锚固和碰撞（只锚定根部件，其他部件保持可动画状态）
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant == rootPart then
				descendant.Anchored = true
				descendant.CanCollide = dragState.originalCanCollide or false
			else
				descendant.Anchored = false
				descendant.CanCollide = false
			end
		end
	end

	-- V1.4.1: 设置默认描边（透明）
	HighlightHelper.SetDefaultHighlight(model)

	-- 恢复展示动画（拖动时停止了动画，这里重新播）
	-- 注意：基地上的兵种应该播放展示动画（ShowAnimationId），不是战斗待机动画
	if humanoid then
		-- V2.8.1修复：不要重新启用Animate脚本，战斗时UnitAI会禁用它们
		-- 如果这里启用，会与UnitAI的自定义动画冲突

		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		-- 停掉已有轨道，防止动画冲突
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function()
				track:Stop()
			end)
		end

		-- 播放展示动画（ShowAnimationId），不是Idle动画
		-- ShowAnimationId是基地上的展示动画，IdleAnimationId是战斗中的待机动画
		local unitId = model:GetAttribute("UnitId")
		local showId = unitId and UnitConfig.GetShowAnimationId(unitId)
		if showId and showId ~= "" and showId ~= "0" then
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. tostring(showId)
			local track = nil
			local ok = pcall(function()
				track = animator:LoadAnimation(anim)
			end)
			if ok and track then
				-- 使用较低优先级，便于战斗时被移动/攻击动画覆盖
				track.Priority = Enum.AnimationPriority.Idle
				track.Looped = true
				pcall(function() track:Play() end)
				track.Stopped:Connect(function()
					if anim and anim.Parent then
						anim:Destroy()
					end
				end)
			else
				anim:Destroy()
			end
		end
	end
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
检查换位时的位置是否有效 (V2.0.4修复: WorldToGrid传入占地尺寸)
@param worldPos Vector3 - 世界坐标
@return boolean, Model|nil - 第一个返回值表示是否有效，第二个返回值是占用的模型（如果有冲突）
]]
function IsPositionValidForRelocate(worldPos)
	if not dragState.idleFloor then
		return false, nil
	end

	local floorCenter = dragState.idleFloor.Position

	-- V2.0: 获取当前兵种占地尺寸
	local currentGridWidth = dragState.draggedGridWidth or 1
	local currentGridDepth = dragState.draggedGridDepth or currentGridWidth

	-- V2.0.4修复: WorldToGrid需要传入占地尺寸，才能正确计算左下角格子索引
	local gridX, gridZ = PlacementHelper.WorldToGrid(worldPos, floorCenter, currentGridWidth, currentGridDepth)

	-- 检查与已放置的模型是否重叠（需要排除自己）
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and obj ~= dragState.draggedModel then
			local objInstanceId = obj:GetAttribute("InstanceId")
			if objInstanceId and objInstanceId ~= dragState.draggedInstanceId then
				-- 这是另一个已放置的兵种
				local objPos = GetModelPosition(obj)
				if objPos then
					-- V2.0.4修复: 获取对象的GridWidth和GridDepth（从属性或UnitConfig）
					local objUnitId = obj:GetAttribute("UnitId")
					local objGridWidth = obj:GetAttribute("GridWidth")
					local objGridDepth = obj:GetAttribute("GridDepth")
					if not objGridWidth or not objGridDepth then
						if objUnitId then
							objGridWidth = objGridWidth or UnitConfig.GetGridWidth(objUnitId)
							objGridDepth = objGridDepth or UnitConfig.GetGridDepth(objUnitId)
						else
							local objGridSize = obj:GetAttribute("GridSize") or 1
							objGridWidth = objGridWidth or objGridSize
							objGridDepth = objGridDepth or objGridSize
						end
					end
					-- V2.0.4修复: WorldToGrid需要传入该对象的占地尺寸
					local objGridX, objGridZ = PlacementHelper.WorldToGrid(objPos, floorCenter, objGridWidth, objGridDepth)

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
获取模型位置 (V2.0.4修复: 统一使用GetPivot避免偏移累积)
@param model Model
@return Vector3|nil
]]
function GetModelPosition(model)
	if not model then
		return nil
	end

	-- V2.0.4: 统一使用PlacementHelper.GetModelPosition，确保读写一致
	return PlacementHelper.GetModelPosition(model)
end

--[[
设置模型位置 (V2.0.4修复: 统一使用PivotTo避免偏移累积)
@param model Model
@param position Vector3
]]
function SetModelPosition(model, position)
	if not model or not position then
		return
	end

	-- V2.0.4: 统一使用PlacementHelper.SetModelPosition，确保读写一致
	-- 这样可以避免因PrimaryPart和Pivot不一致导致的偏移累积问题
	PlacementHelper.SetModelPosition(model, position)
end

-- ==================== V1.4: 合成响应处理 ====================

--[[
处理服务端合成响应
@param success boolean - 是否成功
@param message string - 消息
@param newUnitData table|nil - 新兵种数据
]]
function OnMergeResponse(success, message, newUnitData)
	-- print("[DragSystem] 收到合成响应:", success, message)
	EndPowerTipSuppression()

	if success then
		-- print("[DragSystem] 合成成功! 新等级:", newUnitData and newUnitData.Level or "?")
		-- 服务端已经处理了模型的移除和新建，客户端不需要额外操作
		-- 等待新模型自动同步
		lastDragRestore.model = nil
		lastDragRestore.origin = nil
	else
		warn("[DragSystem] 合成失败:", message)
		-- 合成失败：将拖动的模型复位到原始位置
		local modelToRestore = lastDragRestore.model
		local origin = lastDragRestore.origin
		if modelToRestore and origin then
			SetModelPosition(modelToRestore, origin)
			-- RestoreModelAfterDrag已经会调用SetDefaultHighlight移除描边
			RestoreModelAfterDrag(modelToRestore)
		end
		lastDragRestore.model = nil
		lastDragRestore.origin = nil
		GridHelper.HideGrid()
		-- 不需要再调用SetDraggingHighlight，RestoreModelAfterDrag已处理
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
	-- print("[DragSystem] 收到位置更新响应:", success, message, instanceId)

	if success then
		-- print("[DragSystem] 换位成功!")
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
