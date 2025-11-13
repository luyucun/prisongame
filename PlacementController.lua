--[[
脚本名称: PlacementController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/PlacementController
]]

--[[
兵种放置控制器
职责:
1. 处理PC端和移动端的放置交互
2. 管理放置预览模型
3. 实现网格吸附和边界限制
4. 与服务端通信完成放置
版本: V1.2
]]

local PlacementController = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- 引用工具模块
local PlacementHelper = require(script.Parent.Parent.Utils.PlacementHelper)
local HighlightHelper = require(script.Parent.Parent.Utils.HighlightHelper)
local GridHelper = require(script.Parent.Parent.Utils.GridHelper)  -- V1.2.1: 新增Grid管理

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

-- 远程事件
local placementEvents = nil

-- 调试模式（客户端无法访问ServerScriptService中的GameConfig）
local DEBUG_MODE = true

-- ==================== 放置状态 ====================
local placementState = {
	isPlacing = false,           -- 是否正在放置
	previewModel = nil,          -- 预览模型
	currentInstanceId = nil,     -- 当前放置的实例ID
	currentUnitId = nil,         -- 当前兵种ID
	currentGridSize = 1,         -- 当前兵种占地大小
	idleFloor = nil,             -- 玩家的IdleFloor
	lastGridX = nil,             -- 上次的网格X
	lastGridZ = nil,             -- 上次的网格Z
	isMobile = false,            -- 是否为移动设备
	placedModels = {},           -- V1.2.1: 客户端跟踪已放置的模型 {model = {gridX, gridZ, gridSize}}
}

-- ==================== 初始化 ====================

--[[
初始化放置控制器
]]
function PlacementController.Initialize()
	-- 初始化GridHelper (V1.2.1)
	GridHelper.Initialize()

	-- 检测设备类型
	placementState.isMobile = PlacementHelper.IsMobileDevice()

	-- 多次尝试获取远程事件（避免时序问题）
	local maxRetries = 10
	local retryCount = 0
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
		warn("[PlacementController] PlacementEvents未找到，放置功能将不可用!")
		return false
	end

	-- 连接服务端响应事件
	local responseEvent = placementEvents:FindFirstChild("PlacementResponse")
	if responseEvent then
		responseEvent.OnClientEvent:Connect(OnPlacementResponse)
	end

	-- V1.3: 监听回收事件，清理placedModels（Bug修复）
	local removeResponseEvent = placementEvents:FindFirstChild("RemoveResponse")
	if removeResponseEvent then
		removeResponseEvent.OnClientEvent:Connect(function(success, message, instanceId)
			if success then
				-- 回收成功，清理placedModels中对应的模型
				for model, data in pairs(placementState.placedModels) do
					if model:GetAttribute("InstanceId") == instanceId then
						placementState.placedModels[model] = nil
						break
					end
				end
			end
		end)
	end

	-- 等待IdleFloor加载
	task.spawn(function()
		-- 等待玩家角色加载
		local character = player.Character or player.CharacterAdded:Wait()

		-- 再等待一段时间确保基地分配完成
		task.wait(2)

		placementState.idleFloor = FindPlayerIdleFloor()
		if not placementState.idleFloor then
			warn("[PlacementController] 找不到IdleFloor!")
		end
	end)

	-- 连接输入事件
	if placementState.isMobile then
		ConnectMobileInput()
	else
		ConnectPCInput()
	end

	return true
end

-- ==================== 查找IdleFloor ====================

--[[
查找玩家的IdleFloor
优先使用玩家属性中的 HomeSlot（来自服务端），否则使用距离判断
@return Part|nil
]]
function FindPlayerIdleFloor()
	local homeSlot = nil

	-- 策略1: 优先从玩家属性中读取权威的HomeSlot（由服务端下发）
	local homeSlotAttr = player:GetAttribute("HomeSlot")
	if homeSlotAttr and homeSlotAttr > 0 then
		homeSlot = homeSlotAttr
		if DEBUG_MODE then
			print("[PlacementController] 从玩家属性获取权威 HomeSlot:", homeSlot)
		end
	end

	-- 如果属性缺失，回退到距离判断
	if not homeSlot then
		if DEBUG_MODE then
			print("[PlacementController] 玩家属性中没有 HomeSlot，进行距离判断")
		end

		-- 等待玩家角色加载
		local character = player.Character
		if not character then
			character = player.CharacterAdded:Wait()
		end

		if not character.PrimaryPart then
			task.wait(0.5)
			if not character.PrimaryPart then
				warn("[PlacementController] PrimaryPart加载失败")
				return nil
			end
		end

		local playerPos = character.PrimaryPart.Position
		local homeFolder = Workspace:FindFirstChild("Home")
		if not homeFolder then
			warn("[PlacementController] Home文件夹不存在")
			return nil
		end

		-- 策略2: 先尝试找到玩家当前实际所在的基地（距离阈值内）
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
			if DEBUG_MODE then
				print("[PlacementController] 找到玩家当前基地，距离:", minDistance)
			end
			return currentFloor
		end

		-- 策略3: 如果没有在合理范围内找到，则使用最近的基地（兼容性）
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
			warn("[PlacementController] 未在合理范围内找到基地，使用最近基地，距离:", nearestDistance)
		end

		return nearestFloor
	end

	-- 如果有 HomeSlot，直接通过它查找 IdleFloor
	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		warn("[PlacementController] Home文件夹不存在")
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		warn("[PlacementController] 找不到基地:", "PlayerHome" .. homeSlot)
		return nil
	end

	local idleFloor = playerHome:FindFirstChild("IdleFloor")
	if not idleFloor then
		warn("[PlacementController] 找不到IdleFloor")
		return nil
	end

	if DEBUG_MODE then
		print("[PlacementController] 通过 HomeSlot 找到 IdleFloor:", playerHome.Name)
	end

	return idleFloor
end

-- ==================== 公共接口 ====================

--[[
开始放置兵种
@param instanceId string - 兵种实例ID
@param unitId string - 兵种配置ID
@param gridSize number - 占地大小
]]
function PlacementController.StartPlacement(instanceId, unitId, gridSize)
	-- V1.3: 检查是否处于回收模式
	if _G.RemovalController and _G.RemovalController.IsRemovalMode() then
		warn("[PlacementController] 回收模式下无法放置兵种")
		return
	end

	if placementState.isPlacing then
		PlacementController.CancelPlacement()
	end

	-- 每次开始放置时重新获取IdleFloor（确保使用最新的权威HomeSlot）
	placementState.idleFloor = FindPlayerIdleFloor()

	if not placementState.idleFloor then
		warn("[PlacementController] IdleFloor不存在，无法放置")
		return
	end

	-- 更新状态
	placementState.isPlacing = true
	placementState.currentInstanceId = instanceId
	placementState.currentUnitId = unitId
	placementState.currentGridSize = gridSize or 1

	-- 克隆预览模型
	local previewModel = PlacementHelper.CloneUnitModel(unitId)
	if not previewModel then
		warn("[PlacementController] 无法创建预览模型")
		PlacementController.CancelPlacement()
		return
	end

	placementState.previewModel = previewModel
	previewModel.Parent = Workspace

	-- 设置预览模式
	HighlightHelper.SetPreviewMode(previewModel)

	-- 初始位置（PC端用鼠标，移动端用角色前方）
	if placementState.isMobile then
		-- 移动端：放在角色前方，但要限制在IdleFloor范围内
		local character = player.Character
		if character and character.PrimaryPart then
			local forwardPos = character.PrimaryPart.Position + character.PrimaryPart.CFrame.LookVector * 3
			-- 将位置投影到IdleFloor的Y轴上
			local floorY = placementState.idleFloor.Position.Y
			local initialPos = Vector3.new(forwardPos.X, floorY, forwardPos.Z)
			-- 通过吸附函数确保在范围内
			local floorCenter = placementState.idleFloor.Position
			local snappedPos = PlacementHelper.GetNearestGridPosition(initialPos, floorCenter, placementState.currentGridSize)
			UpdatePreviewPosition(snappedPos)
		else
			-- 如果没有角色，放在IdleFloor中心
			UpdatePreviewPosition(placementState.idleFloor.Position)
		end

		-- 显示确认UI
		ShowMobileConfirmUI(true)
	else
		-- PC端：跟随鼠标
		-- 位置会在RenderStepped中更新
	end

	-- ✅ V2.0.2新增：通知BackpackDisplay进入放置模式
	if _G.BackpackDisplay then
		_G.BackpackDisplay.SetPlacingMode(true)
	end
end

--[[
确认放置
]]
function PlacementController.ConfirmPlacement()
	if not placementState.isPlacing or not placementState.previewModel then
		return
	end

	-- 防御性检查：确保IdleFloor仍然有效
	if not placementState.idleFloor or not placementState.idleFloor.Parent then
		warn("[PlacementController] IdleFloor已失效或被删除，无法放置")
		PlacementController.CancelPlacement()
		return
	end

	-- 获取最终位置
	local finalPosition = PlacementHelper.GetModelPosition(placementState.previewModel)
	if not finalPosition then
		warn("[PlacementController] 无法获取模型位置")
		PlacementController.CancelPlacement()
		return
	end

	if DEBUG_MODE then
		print(string.format(
			"[PlacementController] 确认放置 - IdleFloor: %s, Position: (%.2f, %.2f, %.2f)",
			placementState.idleFloor.Name,
			finalPosition.X, finalPosition.Y, finalPosition.Z
			))
	end

	-- 发送确认请求到服务端
	if placementEvents then
		local confirmEvent = placementEvents:FindFirstChild("ConfirmPlacement")
		if confirmEvent then
			confirmEvent:FireServer(placementState.currentInstanceId, finalPosition)
		end
	end

	-- 暂时不清理，等待服务端响应
end

--[[
取消放置
]]
function PlacementController.CancelPlacement()
	if not placementState.isPlacing then
		return
	end

	-- V1.2.1: 移除Grid提示块
	GridHelper.HideGrid()

	-- V1.2.1: 移除Highlight效果
	if placementState.previewModel then
		HighlightHelper.RemoveHighlight(placementState.previewModel)
	end

	-- 移除预览模型
	if placementState.previewModel then
		placementState.previewModel:Destroy()
		placementState.previewModel = nil
	end

	-- 隐藏移动端UI
	if placementState.isMobile then
		ShowMobileConfirmUI(false)
	end

	-- 通知服务端取消
	if placementEvents then
		local cancelEvent = placementEvents:FindFirstChild("CancelPlacement")
		if cancelEvent then
			cancelEvent:FireServer(placementState.currentInstanceId)
		end
	end

	-- 重置状态
	placementState.isPlacing = false
	placementState.currentInstanceId = nil
	placementState.currentUnitId = nil
	placementState.currentGridSize = 1
	placementState.lastGridX = nil
	placementState.lastGridZ = nil

	-- ✅ V2.0.2新增：通知BackpackDisplay退出放置模式
	if _G.BackpackDisplay then
		_G.BackpackDisplay.SetPlacingMode(false)
	end
end

-- ==================== 预览位置更新 ====================

--[[
检查当前位置是否有效（客户端预检测）
@param gridX number
@param gridZ number
@return boolean - true表示有效（绿色），false表示冲突（红色）
]]
local function IsPositionValid(gridX, gridZ)
	-- V1.2.1: 基于网格坐标的碰撞检测
	if not placementState.idleFloor then
		return true
	end

	-- 获取当前兵种占据的网格宽度
	local currentGridWidth = math.sqrt(placementState.currentGridSize)  -- 1, 2, 3

	-- 检查当前位置是否与已放置的模型重叠
	for model, data in pairs(placementState.placedModels) do
		-- 确保模型还存在
		if model and model.Parent then
			local placedGridX = data.gridX
			local placedGridZ = data.gridZ
			local placedGridWidth = math.sqrt(data.gridSize)

			-- 检查网格是否重叠
			-- 当前模型占据的网格范围: [gridX, gridX + currentGridWidth)
			-- 已放置模型占据的网格范围: [placedGridX, placedGridX + placedGridWidth)
			local overlapX = not (gridX + currentGridWidth <= placedGridX or gridX >= placedGridX + placedGridWidth)
			local overlapZ = not (gridZ + currentGridWidth <= placedGridZ or gridZ >= placedGridZ + placedGridWidth)

			if overlapX and overlapZ then
				return false  -- 位置冲突
			end
		else
			-- 模型已被移除，清理缓存
			placementState.placedModels[model] = nil
		end
	end

	return true  -- 位置有效
end

--[[
更新预览模型位置
@param worldPos Vector3 - 原始世界坐标
]]
function UpdatePreviewPosition(worldPos)
	if not placementState.previewModel or not placementState.idleFloor then
		return
	end

	local floorCenter = placementState.idleFloor.Position

	-- 转换为网格索引
	local gridX, gridZ = PlacementHelper.WorldToGrid(worldPos, floorCenter)

	-- 检查是否需要更新 (只有网格变化时才更新，实现吸附效果)
	if gridX == placementState.lastGridX and gridZ == placementState.lastGridZ then
		return
	end

	-- 限制在边界内
	gridX, gridZ = PlacementHelper.ClampGridToBounds(gridX, gridZ, placementState.currentGridSize)

	-- 转换回世界坐标（传入gridSize以正确计算中心偏移）
	local snappedPos = PlacementHelper.GridToWorld(gridX, gridZ, floorCenter, placementState.currentGridSize)

	-- 更新模型位置
	PlacementHelper.SetModelPosition(placementState.previewModel, snappedPos)

	-- V1.2.1: 检测位置是否有效（用于切换Grid颜色）
	local isValid = IsPositionValid(gridX, gridZ)

	-- V1.2.1: 更新Grid提示块（绿色或红色）
	GridHelper.ShowGrid(placementState.currentGridSize, snappedPos, isValid)

	-- 记录当前网格
	placementState.lastGridX = gridX
	placementState.lastGridZ = gridZ
end

-- ==================== PC端输入处理 ====================

--[[
连接PC端输入事件
]]
function ConnectPCInput()
	-- 鼠标移动 - 使用RenderStepped实时更新
	RunService.RenderStepped:Connect(function()
		if not placementState.isPlacing or not placementState.previewModel then
			return
		end

		if not placementState.idleFloor then
			return
		end

		-- 获取鼠标在地板上的位置
		local mouseWorldPos = PlacementHelper.GetMouseWorldPosition(camera, mouse, placementState.idleFloor)
		if mouseWorldPos then
			UpdatePreviewPosition(mouseWorldPos)
		end
	end)

	-- 鼠标点击
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- ✅ V2.0.2关键修复：放置状态下允许穿透UI，解决背包遮挡地面无法放置的问题
		if gameProcessed and not placementState.isPlacing then
			return
		end

		-- ✅ 额外安全检查：避免在文本输入时误触发
		if gameProcessed and UserInputService:GetFocusedTextBox() then
			return
		end

		if not placementState.isPlacing then
			return
		end

		-- 左键确认
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			PlacementController.ConfirmPlacement()
		end

		-- 右键取消
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			PlacementController.CancelPlacement()
		end
	end)
end

-- ==================== 移动端输入处理 ====================

--[[
连接移动端输入事件
]]
function ConnectMobileInput()
	-- 触摸开始 - 用于初始拖动
	UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
		-- ✅ V2.0.2关键修复：放置状态下允许穿透UI，解决背包遮挡地面无法放置的问题
		if gameProcessed and not placementState.isPlacing then
			return
		end

		-- ✅ 额外安全检查：避免在文本输入时误触发
		if gameProcessed and UserInputService:GetFocusedTextBox() then
			return
		end

		if not placementState.isPlacing or not placementState.previewModel then
			return
		end

		if not placementState.idleFloor then
			return
		end

		-- 获取触摸点在地板上的位置
		local touchWorldPos = PlacementHelper.GetTouchWorldPosition(camera, touch.Position, placementState.idleFloor)
		if touchWorldPos then
			UpdatePreviewPosition(touchWorldPos)
		end
	end)

	-- 触摸拖动
	UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
		-- ✅ V2.0.2关键修复：放置状态下允许穿透UI
		if gameProcessed and not placementState.isPlacing then
			return
		end

		-- ✅ 额外安全检查：避免在文本输入时误触发
		if gameProcessed and UserInputService:GetFocusedTextBox() then
			return
		end

		if not placementState.isPlacing or not placementState.previewModel then
			return
		end

		if not placementState.idleFloor then
			return
		end

		-- 获取触摸点在地板上的位置
		local touchWorldPos = PlacementHelper.GetTouchWorldPosition(camera, touch.Position, placementState.idleFloor)
		if touchWorldPos then
			UpdatePreviewPosition(touchWorldPos)
		end
	end)

	-- 连接移动端确认/取消按钮
	ConnectMobileUI()
end

--[[
连接移动端UI按钮
]]
function ConnectMobileUI()
	local playerGui = player:WaitForChild("PlayerGui")
	local putConfirmGui = playerGui:WaitForChild("PutConfirm", 10)

	if not putConfirmGui then
		warn("[PlacementController] 找不到PutConfirm UI")
		return
	end

	local buttonBg = putConfirmGui:WaitForChild("ButtonBg", 5)
	if not buttonBg then
		return
	end

	local confirmButton = buttonBg:FindFirstChild("Confirm")
	local cancelButton = buttonBg:FindFirstChild("Cancel")

	if confirmButton then
		confirmButton.MouseButton1Click:Connect(function()
			PlacementController.ConfirmPlacement()
		end)
	end

	if cancelButton then
		cancelButton.MouseButton1Click:Connect(function()
			PlacementController.CancelPlacement()
		end)
	end
end

--[[
显示/隐藏移动端确认UI
@param show boolean
]]
function ShowMobileConfirmUI(show)
	local playerGui = player:WaitForChild("PlayerGui")
	local putConfirmGui = playerGui:FindFirstChild("PutConfirm")

	if putConfirmGui then
		putConfirmGui.Enabled = show
	end
end

-- ==================== 服务端响应处理 ====================

--[[
检查该兵种是否还有可用实例（未放置）
@param unitId string - 兵种ID
@return boolean - 是否还有可用实例
@return string|nil - 下一个可用实例ID（如果有）
]]
local function CheckUnitAvailability(unitId)
	-- 从BackpackDisplay获取缓存数据
	if not _G.BackpackDisplay or not _G.BackpackDisplay.GetInventoryCache then
		return false, nil
	end

	local inventoryCache = _G.BackpackDisplay.GetInventoryCache()
	local unitData = inventoryCache[unitId]

	if not unitData or not unitData.Instances then
		return false, nil
	end

	-- 查找第一个未放置的实例
	for _, instanceInfo in ipairs(unitData.Instances) do
		if not instanceInfo.IsPlaced then
			return true, instanceInfo.InstanceId
		end
	end

	return false, nil
end

--[[
处理服务端放置响应
@param success boolean
@param message string
@param data table|nil
]]
function OnPlacementResponse(success, message, data)
	if success then
		-- V1.2.1: 记录放置的位置，用于后续碰撞检测
		if placementState.lastGridX and placementState.lastGridZ and placementState.currentGridSize and placementState.idleFloor then
			-- ⚠️ V2.0.2修复：缓存变量避免异步任务中访问被修改的state
			local cachedGridX = placementState.lastGridX
			local cachedGridZ = placementState.lastGridZ
			local cachedGridSize = placementState.currentGridSize
			local cachedIdleFloor = placementState.idleFloor

			-- 延迟一帧后查找服务端创建的模型
			task.spawn(function()
				task.wait(0.1)  -- 等待服务端模型同步到客户端

				-- 检查IdleFloor是否仍然有效
				if not cachedIdleFloor or not cachedIdleFloor.Parent then
					warn("[PlacementController] IdleFloor已失效，跳过模型记录")
					return
				end

				-- 查找IdleFloor上新增的模型
				local floorCenter = cachedIdleFloor.Position
				local placedPos = PlacementHelper.GridToWorld(cachedGridX, cachedGridZ, floorCenter, cachedGridSize)

				-- 在该位置附近查找模型
				local nearbyModels = {}
				for _, obj in ipairs(Workspace:GetChildren()) do
					if obj:IsA("Model") and obj.PrimaryPart then
						local distance = (obj.PrimaryPart.Position - placedPos).Magnitude
						if distance < 5 then  -- 5 studs范围内
							table.insert(nearbyModels, obj)
						end
					end
				end

				-- 找到最近的模型
				local closestModel = nil
				local closestDistance = math.huge
				for _, model in ipairs(nearbyModels) do
					if not placementState.placedModels[model] then  -- 排除已记录的
						local distance = (model.PrimaryPart.Position - placedPos).Magnitude
						if distance < closestDistance then
							closestDistance = distance
							closestModel = model
						end
					end
				end

				if closestModel then
					placementState.placedModels[closestModel] = {
						gridX = cachedGridX,
						gridZ = cachedGridZ,
						gridSize = cachedGridSize
					}
				else
					warn("[PlacementController] 未找到放置的模型!")
				end
			end)
		end

		-- V1.2.1: 移除Grid提示块
		GridHelper.HideGrid()

		-- V1.2.1: 移除Highlight效果
		if placementState.previewModel then
			HighlightHelper.RemoveHighlight(placementState.previewModel)
		end

		-- 放置成功，清理预览模型
		if placementState.previewModel then
			placementState.previewModel:Destroy()
			placementState.previewModel = nil
		end

		-- 隐藏移动端UI
		if placementState.isMobile then
			ShowMobileConfirmUI(false)
		end

		-- ⭐ V2.0.2核心修改: 检查是否还有库存，实现连续放置
		local currentUnitId = placementState.currentUnitId
		local currentGridSize = placementState.currentGridSize

		-- 先重置部分状态
		placementState.isPlacing = false
		placementState.currentInstanceId = nil
		placementState.lastGridX = nil
		placementState.lastGridZ = nil

		-- 延迟0.15秒等待背包刷新
		task.spawn(function()
			task.wait(0.15)

			-- 检查是否还有可用库存
			local hasMore, nextInstanceId = CheckUnitAvailability(currentUnitId)

			if hasMore and nextInstanceId then
				-- 还有库存，自动开始下一次放置
				if DEBUG_MODE then
					print("[PlacementController] 检测到库存，自动开始下一次放置:", nextInstanceId)
				end

				PlacementController.StartPlacement(nextInstanceId, currentUnitId, currentGridSize)
			else
				-- 库存耗尽，完全重置状态
				placementState.currentUnitId = nil
				placementState.currentGridSize = 1

				-- ✅ V2.0.2新增：通知BackpackDisplay退出放置模式
				if _G.BackpackDisplay then
					_G.BackpackDisplay.SetPlacingMode(false)
				end

				if DEBUG_MODE then
					print("[PlacementController] 库存耗尽，放置流程结束")
				end
			end
		end)
	else
		-- 放置失败，显示错误信息
		warn("[PlacementController] 放置失败:", message)
		-- 可以在这里添加UI提示
	end
end

-- ==================== 全局访问 ====================

-- 提供全局访问接口（供BackpackDisplay调用）
_G.PlacementController = PlacementController

-- 自动初始化
task.spawn(function()
	task.wait(1)  -- 等待其他系统加载
	PlacementController.Initialize()
end)

return PlacementController
