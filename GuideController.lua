--[[
脚本名称: GuideController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/GuideController
]]

--[[
新手引导控制器 V3.9.1
职责:
1. 接收服务端引导事件
2. 显示引导箭头（Guide01 + Guide02 + Beam）
3. 检测玩家是否到达目标位置
4. 通知服务端引导完成
5. V3.9.1新增: UI聚焦引导（半透明Frame包围目标UI，带滑入动画）
]]

local GuideController = {}

-- 调试配置
local DEBUG_MODE = false
local function DebugLog(...)
	if DEBUG_MODE then
		print("[GuideController]", ...)
	end
end

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

-- 本地玩家
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- 引用配置
local GuideConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GuideConfig"))

-- 事件缓存
local guideEvents = nil

-- 当前引导状态
local currentGuideId = nil
local currentTargetPosition = nil
local guideStartPart = nil   -- 绑定到玩家的Guide01副本
local guideEndPart = nil     -- 放在目标位置的Guide02副本
local updateConnection = nil -- RenderStepped连接

-- UI聚焦引导状态
local uiFocusFrames = {}     -- 存储ScreenGui和4个半透明Frame
local uiFocusConnections = {} -- 存储所有UI点击监听连接
local currentUIPath = nil    -- 当前聚焦的UI路径

-- ==================== 私有函数（前向声明） ====================

-- 前向声明，解决函数互相调用的问题
local CheckArrival
local OnArriveAtTarget
local ClearGuideDisplay
local ClearUIFocusGuide
local CreateUIFocusGuide

--[[
获取事件引用
]]
local function GetGuideEvents()
	if guideEvents then
		return guideEvents
	end

	local events = ReplicatedStorage:WaitForChild("Events", 10)
	if not events then
		return nil
	end

	local guideEventsFolder = events:WaitForChild("GuideEvents", 10)
	if not guideEventsFolder then
		return nil
	end

	guideEvents = {
		StartGuide = guideEventsFolder:WaitForChild("StartGuide", 5),
		CompleteGuide = guideEventsFolder:WaitForChild("CompleteGuide", 5),
		GuideArrived = guideEventsFolder:WaitForChild("GuideArrived", 5),
		SyncGuideData = guideEventsFolder:WaitForChild("SyncGuideData", 5),
		RequestGuideSync = guideEventsFolder:WaitForChild("RequestGuideSync", 5),
		StartUIFocusGuide = guideEventsFolder:WaitForChild("StartUIFocusGuide", 5),
		UIFocusCompleted = guideEventsFolder:WaitForChild("UIFocusCompleted", 5),
	}

	return guideEvents
end

--[[
从ReplicatedStorage获取引导模板
@param templateName string - 模板名称
@return Instance|nil - 模板对象
]]
local function GetGuideTemplate(templateName)
	-- 从ReplicatedStorage/Effect获取模板
	local effectFolder = ReplicatedStorage:FindFirstChild("Effect")
	if not effectFolder then
		warn("[GuideController] 找不到ReplicatedStorage/Effect文件夹")
		return nil
	end

	local template = effectFolder:FindFirstChild(templateName)
	if not template then
		warn("[GuideController] 找不到引导模板:", templateName)
		return nil
	end

	return template
end

--[[
获取玩家的躯干Part
]]
local function GetPlayerTorso()
	local char = player.Character
	if not char then
		return nil
	end

	-- 优先查找UpperTorso（R15）或Torso（R6）
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	return torso
end

--[[
清除当前引导显示
]]
ClearGuideDisplay = function()
	-- 断开更新连接
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	-- 移除引导部件
	if guideStartPart then
		guideStartPart:Destroy()
		guideStartPart = nil
	end

	if guideEndPart then
		guideEndPart:Destroy()
		guideEndPart = nil
	end

	currentGuideId = nil
	currentTargetPosition = nil
end

--[[
到达目标时调用
]]
OnArriveAtTarget = function()
	if not currentGuideId then
		return
	end

	local guideId = currentGuideId

	-- 通知服务端
	local events = GetGuideEvents()
	if events and events.GuideArrived then
		events.GuideArrived:FireServer(guideId)
	end

	-- 清除引导显示
	ClearGuideDisplay()
end

--[[
检查玩家是否到达目标位置
]]
CheckArrival = function()
	if not currentGuideId or not currentTargetPosition then
		return
	end

	local char = player.Character
	if not char then
		return
	end

	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- 获取引导配置
	local guideConfig = GuideConfig.GetGuideById(currentGuideId)
	local arrivalDistance = guideConfig and guideConfig.ArrivalDistance or 10

	-- 计算距离
	local distance = (rootPart.Position - currentTargetPosition).Magnitude

	if distance <= arrivalDistance then
		-- 到达目标
		OnArriveAtTarget()
	end
end

--[[
更新引导显示（每帧调用）
]]
local function UpdateGuideDisplay()
	if not currentGuideId or not guideStartPart then
		return
	end

	-- 获取玩家躯干
	local torso = GetPlayerTorso()
	if not torso then
		return
	end

	-- 更新起始点位置（绑定到玩家躯干）
	if guideStartPart:IsA("BasePart") then
		local offset = GuideConfig.Display.AttachmentOffset or Vector3.new(0, 1, 0)
		guideStartPart.Position = torso.Position + offset
		guideStartPart.Anchored = true
		guideStartPart.CanCollide = false
	end

	-- 检查是否到达目标
	CheckArrival()
end

--[[
创建引导显示
@param guideId number - 引导ID
@param targetPosition Vector3 - 目标位置
]]
local function CreateGuideDisplay(guideId, targetPosition)
	-- 清除旧的引导
	ClearGuideDisplay()

	-- 获取引导模板
	local guide01Template = GetGuideTemplate(GuideConfig.Display.GuideStartPartName)
	local guide02Template = GetGuideTemplate(GuideConfig.Display.GuideEndPartName)

	if not guide01Template or not guide02Template then
		warn("[GuideController] 无法获取引导模板")
		return false
	end

	-- 复制Guide01（起始点，绑定到玩家）
	guideStartPart = guide01Template:Clone()
	guideStartPart.Name = "GuideStart_" .. guideId
	guideStartPart.Parent = Workspace

	-- 复制Guide02（终点，放在目标位置）
	guideEndPart = guide02Template:Clone()
	guideEndPart.Name = "GuideEnd_" .. guideId
	guideEndPart.Parent = Workspace

	-- 设置终点位置
	if guideEndPart:IsA("BasePart") then
		guideEndPart.Position = targetPosition + Vector3.new(0, 2, 0)  -- 稍微抬高一点
		guideEndPart.Anchored = true
		guideEndPart.CanCollide = false
	end

	-- 连接Beam的Attachment
	-- Beam在GuideStart下，Attachment0连接GuideEnd的Attachment0，Attachment1连接GuideStart的Attachment1
	local beam = guideStartPart:FindFirstChild("Beam", true)
	if beam then
		local endAttachment = guideEndPart:FindFirstChild("Attachment0", true)
		local startAttachment = guideStartPart:FindFirstChild("Attachment1", true)
		if endAttachment then
			beam.Attachment0 = endAttachment
		end
		if startAttachment then
			beam.Attachment1 = startAttachment
		end
	end

	-- 保存状态
	currentGuideId = guideId
	currentTargetPosition = targetPosition

	-- 启动更新循环
	updateConnection = RunService.RenderStepped:Connect(function()
		UpdateGuideDisplay()
	end)

	return true
end

--[[
处理开始引导事件
@param guideId number - 引导ID
@param targetPosition Vector3 - 目标位置
]]
local function OnStartGuide(guideId, targetPosition)
	CreateGuideDisplay(guideId, targetPosition)
end

--[[
处理完成引导事件
@param guideId number - 引导ID (0表示清除所有)
]]
local function OnCompleteGuide(guideId)
	if guideId == 0 or guideId == currentGuideId then
		ClearGuideDisplay()
		ClearUIFocusGuide()
	end
end

--[[
处理同步引导数据事件
@param guideData table - 引导数据
]]
local function OnSyncGuideData(guideData)
	-- 可以在这里处理引导数据的客户端缓存
end

--[[
清除UI聚焦引导
]]
ClearUIFocusGuide = function()
	-- 断开所有监听连接
	for _, connection in pairs(uiFocusConnections) do
		if connection then
			pcall(function()
				connection:Disconnect()
			end)
		end
	end
	uiFocusConnections = {}

	-- 移除所有半透明Frame（包括ScreenGui）
	for _, frame in pairs(uiFocusFrames) do
		if frame and frame.Parent then
			pcall(function()
				frame:Destroy()
			end)
		end
	end
	uiFocusFrames = {}
	currentUIPath = nil
end

--[[
获取UI对象
@param uiPath string - UI路径（例如："BackpackGui/BackpackFrame/ItemListFrame"）
@return GuiObject|nil - UI对象
]]
local function GetUIObject(uiPath)
	local playerGui = player:WaitForChild("PlayerGui", 5)
	if not playerGui then
		return nil
	end

	local parts = string.split(uiPath, "/")
	local current = playerGui

	for _, partName in ipairs(parts) do
		current = current:FindFirstChild(partName)
		if not current then
			return nil
		end
	end

	return current
end

--[[
创建UI聚焦引导
@param guideId number - 引导ID
@param uiPath string - UI路径
]]
CreateUIFocusGuide = function(guideId, uiPath)
	-- 清除旧的引导
	ClearUIFocusGuide()

	-- 获取目标UI
	local targetUI = GetUIObject(uiPath)
	if not targetUI then
		warn("[GuideController] 找不到目标UI:", uiPath)
		return false
	end

	-- 获取PlayerGui
	local playerGui = player:WaitForChild("PlayerGui")
	if not playerGui then
		return false
	end

	-- 获取配置
	local focusConfig = GuideConfig.Display.UIFocus

	-- 本次UI聚焦是否已完成（防止多次触发）
	local hasCompleted = false
	local function CompleteUIFocus()
		if hasCompleted then
			return
		end
		hasCompleted = true

		local events = GetGuideEvents()
		if events and events.UIFocusCompleted then
			events.UIFocusCompleted:FireServer(guideId)
		end

		ClearUIFocusGuide()
	end

	-- 获取目标UI的绝对位置和大小
	local targetAbsPos = targetUI.AbsolutePosition
	local targetAbsSize = targetUI.AbsoluteSize

	-- 获取GuiInset偏移量（顶部状态栏高度，通常36像素）
	local GuiService = game:GetService("GuiService")
	local guiInset = GuiService:GetGuiInset()

	-- AbsolutePosition是相对于GuiInset之后的坐标，需要补偿
	local adjustedPosX = targetAbsPos.X
	local adjustedPosY = targetAbsPos.Y + guiInset.Y

	-- 获取屏幕大小
	local viewportSize = workspace.CurrentCamera.ViewportSize

	-- 创建一个ScreenGui来容纳聚焦Frame
	local focusScreenGui = Instance.new("ScreenGui")
	focusScreenGui.Name = "GuideFocusGui"
	focusScreenGui.DisplayOrder = focusConfig.ZIndex
	-- 使用IgnoreGuiInset=true覆盖整个屏幕，但需要补偿AbsolutePosition的偏移
	focusScreenGui.IgnoreGuiInset = true
	focusScreenGui.ResetOnSpawn = false
	focusScreenGui.Parent = playerGui

	-- 创建4个半透明Frame（上、下、左、右）
	local frames = {focusScreenGui}  -- 把ScreenGui也加入，方便清理

	-- 上方Frame
	local topFrame = Instance.new("Frame")
	topFrame.Name = "GuideFocusTop"
	topFrame.BackgroundColor3 = focusConfig.FrameColor
	topFrame.BackgroundTransparency = focusConfig.FrameTransparency
	topFrame.BorderSizePixel = 0
	topFrame.Size = UDim2.new(1, 0, 0, adjustedPosY)
	topFrame.Position = UDim2.new(0, 0, 0, 0)
	topFrame.Parent = focusScreenGui
	table.insert(frames, topFrame)

	-- 下方Frame
	local bottomFrame = Instance.new("Frame")
	bottomFrame.Name = "GuideFocusBottom"
	bottomFrame.BackgroundColor3 = focusConfig.FrameColor
	bottomFrame.BackgroundTransparency = focusConfig.FrameTransparency
	bottomFrame.BorderSizePixel = 0
	local bottomY = adjustedPosY + targetAbsSize.Y
	bottomFrame.Size = UDim2.new(1, 0, 0, viewportSize.Y - bottomY)
	bottomFrame.Position = UDim2.new(0, 0, 0, bottomY)
	bottomFrame.Parent = focusScreenGui
	table.insert(frames, bottomFrame)

	-- 左侧Frame
	local leftFrame = Instance.new("Frame")
	leftFrame.Name = "GuideFocusLeft"
	leftFrame.BackgroundColor3 = focusConfig.FrameColor
	leftFrame.BackgroundTransparency = focusConfig.FrameTransparency
	leftFrame.BorderSizePixel = 0
	leftFrame.Size = UDim2.new(0, adjustedPosX, 0, targetAbsSize.Y)
	leftFrame.Position = UDim2.new(0, 0, 0, adjustedPosY)
	leftFrame.Parent = focusScreenGui
	table.insert(frames, leftFrame)

	-- 右侧Frame
	local rightFrame = Instance.new("Frame")
	rightFrame.Name = "GuideFocusRight"
	rightFrame.BackgroundColor3 = focusConfig.FrameColor
	rightFrame.BackgroundTransparency = focusConfig.FrameTransparency
	rightFrame.BorderSizePixel = 0
	local rightX = adjustedPosX + targetAbsSize.X
	rightFrame.Size = UDim2.new(0, viewportSize.X - rightX, 0, targetAbsSize.Y)
	rightFrame.Position = UDim2.new(0, rightX, 0, adjustedPosY)
	rightFrame.Parent = focusScreenGui
	table.insert(frames, rightFrame)

	-- 保存Frame引用
	uiFocusFrames = frames
	currentUIPath = uiPath
	currentGuideId = guideId

	-- 添加滑入动画
	local TweenService = game:GetService("TweenService")
	local tweenInfo = TweenInfo.new(focusConfig.AnimationDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- 上方Frame从上往下滑入
	topFrame.Position = UDim2.new(0, 0, 0, -adjustedPosY)
	local topTween = TweenService:Create(topFrame, tweenInfo, {Position = UDim2.new(0, 0, 0, 0)})
	topTween:Play()

	-- 下方Frame从下往上滑入
	bottomFrame.Position = UDim2.new(0, 0, 1, 0)
	local bottomTween = TweenService:Create(bottomFrame, tweenInfo, {Position = UDim2.new(0, 0, 0, bottomY)})
	bottomTween:Play()

	-- 左侧Frame从左往右滑入
	leftFrame.Position = UDim2.new(0, -adjustedPosX, 0, adjustedPosY)
	local leftTween = TweenService:Create(leftFrame, tweenInfo, {Position = UDim2.new(0, 0, 0, adjustedPosY)})
	leftTween:Play()

	-- 右侧Frame从右往左滑入
	rightFrame.Position = UDim2.new(1, 0, 0, adjustedPosY)
	local rightTween = TweenService:Create(rightFrame, tweenInfo, {Position = UDim2.new(0, rightX, 0, adjustedPosY)})
	rightTween:Play()

	-- 监听目标UI的点击事件
	local function CheckUIClick(descendant)
		if descendant:IsA("GuiButton") or descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
			local connection
			connection = descendant.MouseButton1Click:Connect(function()
				CompleteUIFocus()
			end)
			-- 保存连接以便清理时断开
			table.insert(uiFocusConnections, connection)
		end
	end

	-- 任意点击/触摸屏幕任意区域都视为完成（不必点目标UI）
	local anyClickConn
	anyClickConn = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			CompleteUIFocus()
		end
	end)
	table.insert(uiFocusConnections, anyClickConn)

	-- 检查目标UI及其所有子对象
	CheckUIClick(targetUI)
	for _, descendant in ipairs(targetUI:GetDescendants()) do
		CheckUIClick(descendant)
	end

	return true
end

--[[
处理开始UI聚焦引导事件
@param guideId number - 引导ID
@param uiPath string - UI路径
]]
local function OnStartUIFocusGuide(guideId, uiPath)
	CreateUIFocusGuide(guideId, uiPath)
end

-- ==================== 公共接口 ====================

--[[
初始化引导控制器
]]
function GuideController.Initialize()
	-- 等待事件就绪
	local events = GetGuideEvents()
	if not events then
		warn("[GuideController] 无法获取引导事件，引导功能禁用")
		return
	end

	-- 监听服务端事件
	if events.StartGuide then
		events.StartGuide.OnClientEvent:Connect(OnStartGuide)
	end

	if events.CompleteGuide then
		events.CompleteGuide.OnClientEvent:Connect(OnCompleteGuide)
	end

	if events.SyncGuideData then
		events.SyncGuideData.OnClientEvent:Connect(OnSyncGuideData)
	end

	if events.StartUIFocusGuide then
		events.StartUIFocusGuide.OnClientEvent:Connect(OnStartUIFocusGuide)
	end

	-- 监听角色重生
	player.CharacterAdded:Connect(function(newCharacter)
		character = newCharacter
		-- 角色重生后重新请求引导数据
		task.wait(1)
		if events.RequestGuideSync then
			events.RequestGuideSync:FireServer()
		end
	end)

	-- 请求同步引导数据
	task.delay(2, function()
		if events.RequestGuideSync then
			events.RequestGuideSync:FireServer()
		end
	end)
end

--[[
获取当前激活的引导ID
@return number|nil - 引导ID
]]
function GuideController.GetCurrentGuideId()
	return currentGuideId
end

--[[
检查是否有激活的引导
@return boolean - 是否有激活的引导
]]
function GuideController.HasActiveGuide()
	return currentGuideId ~= nil
end

--[[
手动清除引导（用于调试）
]]
function GuideController.ClearGuide()
	ClearGuideDisplay()
	ClearUIFocusGuide()
end

-- 初始化
GuideController.Initialize()

-- 暴露到全局（可选，用于调试）
_G.GuideController = GuideController

return GuideController
