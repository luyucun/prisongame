--[[
脚本名称: HouseUpgradeCameraController
脚本类型: LocalScript
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/HouseUpgradeCameraController
版本: V3.9.1
]]

--[[
房屋升级镜头控制�?
职责:
1. 接收服务端房屋升级通知
2. 控制镜头拉高看向房屋
3. 等待房屋替换完成
4. 恢复镜头控制

流程:
1. 玩家通关章节后点击胜利弹窗确�?
2. 玩家重生在基�?
3. 服务端通知客户端开始房屋升级表�?
4. 客户端镜头拉高看向房�?
5. 等待1�?
6. 旧房屋消失，新房屋出现（服务端处理）
7. 等待1�?
8. 恢复镜头控制
]]

local HouseUpgradeCameraController = {}

-- 服务引用
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- 本地玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))

-- 状态标�?
local isUpgrading = false
local originalCameraType = nil
local originalCameraSubject = nil

-- ���ò���
local CAMERA_HEIGHT = 30  -- ��ͷ�߶�
local CAMERA_DISTANCE = 40  -- ��ͷ���뷿�ݵľ���
local CAMERA_ANGLE = math.rad(30)  -- ��ͷ���ӽǶ�(30��)
local TWEEN_DURATION = 1.0  -- ��ͷ�ƶ�ʱ��
local WAIT_BEFORE_REPLACE = 0.8  -- �����滻ǰ�ȴ�ʱ��
local WAIT_AFTER_REPLACE = 1.8  -- �����滻��ȴ�ʱ��(ԭV3.9����)

local POPUP_MIN_DURATION = 1.0
local POPUP_BG_TWEEN_DURATION = 0.25
local POPUP_ITEM_TWEEN_DURATION = 0.12
local POPUP_ITEM_DELAY = 0.05
local POPUP_ITEM_OFFSET_X = -30
local POPUP_BG_OFFSET_SCALE = -1
local LIGHT_ROTATE_SPEED = 60
local POPUP_FORCE_CLOSE_SECONDS = 12

-- RemoteEvent����
local HouseUpgradeEvents = nil

local houseUpgradeGui = nil
local upgradeBg = nil
local upgradeLightBg = nil
local upgradeLight = nil
local upgradeOldPrison = nil
local upgradeNewPrison = nil
local upgradeOldSpeed = nil
local upgradeOldTime = nil
local upgradeNewSpeed = nil
local upgradeNewTime = nil
local upgradeArrow = nil
local upgradeTitle = nil

local popupVisible = false
local popupAllowClose = false
popupClosedFired = false
local popupToken = 0
local popupCloseSignal = nil
local popupInputConnection = nil
local lightRotateConnection = nil
local popupOriginalPositions = {}
local popupElements = {}
local function InitializeEvents()
	if HouseUpgradeEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
	if not eventsFolder then
		warn("[HouseUpgradeCameraController] Events文件夹不存在")
		return false
	end

	local houseUpgradeFolder = eventsFolder:FindFirstChild("HouseUpgradeEvents")
	if not houseUpgradeFolder then
		warn("[HouseUpgradeCameraController] HouseUpgradeEvents文件夹不存在")
		return false
	end

	HouseUpgradeEvents = houseUpgradeFolder
	return true
end

local function SafeWaitForChild(parent, childName, timeout)
	timeout = timeout or 3
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(childName)
	if child then
		return child
	end

	local startTime = tick()
	while tick() - startTime < timeout do
		child = parent:FindFirstChild(childName)
		if child then
			return child
		end
		task.wait(0.1)
	end

	return nil
end

local function OffsetPosition(position, xOffset, yOffset)
	return UDim2.new(
		position.X.Scale,
		position.X.Offset + xOffset,
		position.Y.Scale,
		position.Y.Offset + yOffset
	)
end

local function InitializePopupUI()
	if houseUpgradeGui and houseUpgradeGui.Parent == playerGui and upgradeBg then
		return true
	end

	houseUpgradeGui = playerGui:FindFirstChild("HouseUpgradeGui") or playerGui:WaitForChild("HouseUpgradeGui", 5)
	if not houseUpgradeGui then
		warn("[HouseUpgradeCameraController] HouseUpgradeGui not found")
		return false
	end

	upgradeBg = SafeWaitForChild(houseUpgradeGui, "Bg", 3)
	upgradeLightBg = SafeWaitForChild(houseUpgradeGui, "LightBg", 3)
	upgradeLight = upgradeLightBg and upgradeLightBg:FindFirstChild("Light")

	upgradeOldPrison = upgradeBg and upgradeBg:FindFirstChild("OldPrison")
	upgradeNewPrison = upgradeBg and upgradeBg:FindFirstChild("NewPrison")
	upgradeOldSpeed = upgradeBg and upgradeBg:FindFirstChild("OldSpeed")
	upgradeOldTime = upgradeBg and upgradeBg:FindFirstChild("OldTimeLimit")
	upgradeNewSpeed = upgradeBg and upgradeBg:FindFirstChild("NewSpeed")
	upgradeNewTime = upgradeBg and upgradeBg:FindFirstChild("NewTimeLimit")
	upgradeArrow = upgradeBg and upgradeBg:FindFirstChild("Arrow")
	upgradeTitle = upgradeBg and upgradeBg:FindFirstChild("Title")

	popupElements = {
		upgradeOldPrison,
		upgradeNewPrison,
		upgradeOldSpeed,
		upgradeOldTime,
		upgradeNewSpeed,
		upgradeNewTime,
		upgradeArrow,
		upgradeTitle,
	}

	popupOriginalPositions = {}
	if upgradeBg and upgradeBg:IsA("GuiObject") then
		popupOriginalPositions[upgradeBg] = upgradeBg.Position
	end
	for _, element in ipairs(popupElements) do
		if element and element:IsA("GuiObject") then
			popupOriginalPositions[element] = element.Position
		end
	end

	return upgradeBg ~= nil
end

local function GetCompletedChapters()
	local completed = player:GetAttribute("CompletedChapters")
	if type(completed) == "number" then
		return completed
	end
	return 0
end

local function ResolvePopupData(oldModelName, newModelName)
	local currentModel = oldModelName
	if type(currentModel) ~= "string" or currentModel == "" then
		currentModel = player:GetAttribute("CurrentHouseModel")
	end

	local completedChapters = GetCompletedChapters()
	if type(currentModel) ~= "string" or currentModel == "" then
		local fallback = HouseConfig.GetHouseByChapter(completedChapters)
		currentModel = fallback and fallback.ModelName or nil
	end

	local shouldUpgrade, targetModel = HouseConfig.ShouldUpgradeHouse(currentModel or "PrisonLv1", completedChapters)
	local resolvedNew = newModelName
	if type(resolvedNew) ~= "string" or resolvedNew == "" then
		resolvedNew = shouldUpgrade and targetModel or currentModel
	end

	local oldHouse = HouseConfig.GetHouseByModel(currentModel or "") or HouseConfig.GetHouseByChapter(completedChapters)
	local newHouse = HouseConfig.GetHouseByModel(resolvedNew or "")
	return oldHouse, newHouse
end

local function ApplyPopupContent(oldModelName, newModelName)
	local oldHouse, newHouse = ResolvePopupData(oldModelName, newModelName)

	if upgradeOldPrison and upgradeOldPrison:IsA("ImageLabel") then
		upgradeOldPrison.Image = oldHouse and tostring(oldHouse.Icon or "") or ""
	end
	if upgradeNewPrison and upgradeNewPrison:IsA("ImageLabel") then
		upgradeNewPrison.Image = newHouse and tostring(newHouse.Icon or "") or ""
	end

	if upgradeOldSpeed and upgradeOldSpeed:IsA("TextLabel") then
		local speed = oldHouse and tonumber(oldHouse.IdleCoinsPerMinute) or 0
		upgradeOldSpeed.Text = string.format("$%d/min", speed)
	end
	if upgradeOldTime and upgradeOldTime:IsA("TextLabel") then
		local hours = oldHouse and tonumber(oldHouse.IdleMaxHours) or 0
		upgradeOldTime.Text = string.format("%dH", hours)
	end
	if upgradeNewSpeed and upgradeNewSpeed:IsA("TextLabel") then
		local speed = newHouse and tonumber(newHouse.IdleCoinsPerMinute) or 0
		upgradeNewSpeed.Text = string.format("$%d/min", speed)
	end
	if upgradeNewTime and upgradeNewTime:IsA("TextLabel") then
		local hours = newHouse and tonumber(newHouse.IdleMaxHours) or 0
		upgradeNewTime.Text = string.format("%dH", hours)
	end
end

local function ResetPopupPositions()
	for element, position in pairs(popupOriginalPositions) do
		if element and element.Parent then
			element.Position = position
		end
	end
end

local function AnimatePopup()
	if not upgradeBg or not popupOriginalPositions[upgradeBg] then
		return
	end

	ResetPopupPositions()

	local bgOriginal = popupOriginalPositions[upgradeBg]
	upgradeBg.Position = UDim2.new(
		bgOriginal.X.Scale + POPUP_BG_OFFSET_SCALE,
		bgOriginal.X.Offset,
		bgOriginal.Y.Scale,
		bgOriginal.Y.Offset
	)

	local bgTween = TweenService:Create(
		upgradeBg,
		TweenInfo.new(POPUP_BG_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = bgOriginal }
	)
	bgTween:Play()

	for index, element in ipairs(popupElements) do
		local original = popupOriginalPositions[element]
		if element and original and element:IsA("GuiObject") then
			element.Position = OffsetPosition(original, POPUP_ITEM_OFFSET_X, 0)
			task.delay((index - 1) * POPUP_ITEM_DELAY, function()
				if element and element.Parent then
					TweenService:Create(
						element,
						TweenInfo.new(POPUP_ITEM_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Position = original }
					):Play()
				end
			end)
		end
	end
end

local function StartLightRotation()
	if lightRotateConnection then
		lightRotateConnection:Disconnect()
		lightRotateConnection = nil
	end

	if not upgradeLight then
		return
	end

	upgradeLight.Rotation = 0
	lightRotateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if upgradeLight then
			upgradeLight.Rotation = (upgradeLight.Rotation + (LIGHT_ROTATE_SPEED * deltaTime)) % 360
		end
	end)
end

local function StopLightRotation()
	if lightRotateConnection then
		lightRotateConnection:Disconnect()
		lightRotateConnection = nil
	end
end

local function NotifyPopupClosed()
	if popupClosedFired then
		return
	end
	popupClosedFired = true

	if InitializeEvents() then
		local popupClosedEvent = HouseUpgradeEvents:FindFirstChild("HouseUpgradePopupClosed")
		if popupClosedEvent then
			popupClosedEvent:FireServer()
		end

		local readyEvent = HouseUpgradeEvents:FindFirstChild("ClientCameraReady")
		if readyEvent then
			readyEvent:FireServer()
		end
	end
end

local function CloseUpgradePopup(force)
	if not popupVisible then
		return
	end
	if not force and not popupAllowClose then
		return
	end

	popupVisible = false
	popupAllowClose = false

	if upgradeBg then
		upgradeBg.Visible = false
	end
	if upgradeLightBg then
		upgradeLightBg.Visible = false
	end
	if houseUpgradeGui and houseUpgradeGui:IsA("ScreenGui") then
		houseUpgradeGui.Enabled = false
	end

	if popupInputConnection then
		popupInputConnection:Disconnect()
		popupInputConnection = nil
	end

	StopLightRotation()
	ResetPopupPositions()
	NotifyPopupClosed()

	if popupCloseSignal then
		popupCloseSignal:Fire()
		popupCloseSignal:Destroy()
		popupCloseSignal = nil
	end
end

local function BindPopupInput()
	if popupInputConnection then
		popupInputConnection:Disconnect()
		popupInputConnection = nil
	end

	popupInputConnection = UserInputService.InputBegan:Connect(function(input)
		if not popupVisible or not popupAllowClose then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			CloseUpgradePopup()
		end
	end)
end

local function ShowUpgradePopup(oldModelName, newModelName)
	if not InitializePopupUI() then
		return nil
	end

	popupToken = popupToken + 1
	local token = popupToken
	popupVisible = true
	popupAllowClose = false
	popupClosedFired = false

	if houseUpgradeGui and houseUpgradeGui:IsA("ScreenGui") then
		houseUpgradeGui.Enabled = true
	end
	if upgradeBg then
		upgradeBg.Visible = true
	end
	if upgradeLightBg then
		upgradeLightBg.Visible = true
	end

	ApplyPopupContent(oldModelName, newModelName)
	AnimatePopup()
	StartLightRotation()
	BindPopupInput()

	if popupCloseSignal then
		popupCloseSignal:Destroy()
	end
	popupCloseSignal = Instance.new("BindableEvent")

	task.delay(POPUP_MIN_DURATION, function()
		if popupToken == token then
			popupAllowClose = true
		end
	end)

	task.delay(POPUP_FORCE_CLOSE_SECONDS, function()
		if popupToken == token and popupVisible then
			CloseUpgradePopup(true)
		end
	end)

	return popupCloseSignal
end

--[[
获取玩家的House文件�?
@param homeSlot number - 玩家基地编号(1-6)
@return Folder|nil - House文件�?
]]
local function GetPlayerHouseFolder(homeSlot)
	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		warn("[HouseUpgradeCameraController] Home文件夹不存在")
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		warn("[HouseUpgradeCameraController] PlayerHome" .. homeSlot .. " not found")
		return nil
	end

	local houseFolder = playerHome:FindFirstChild("House")
	return houseFolder
end

--[[
获取House文件夹下的当前房屋模�?
@param houseFolder Folder - House文件�?
@return Model|nil - 当前房屋模型
]]
local function GetCurrentHouseModel(houseFolder)
	if not houseFolder then return nil end

	for _, child in ipairs(houseFolder:GetChildren()) do
		if child:IsA("Model") then
			return child
		end
	end

	return nil
end

--[[
计算房屋的中心位�?
@param houseModel Model - 房屋模型
@return Vector3 - 房屋中心位置
]]
local function GetHouseCenter(houseModel)
	if not houseModel then
		return Vector3.new(0, 0, 0)
	end

	local bboxCF, bboxSize = houseModel:GetBoundingBox()
	return bboxCF.Position
end

--[[
保存当前镜头状�?
]]
local function SaveCameraState()
	originalCameraType = camera.CameraType
	originalCameraSubject = camera.CameraSubject
end

--[[
恢复镜头状�?
]]
local function RestoreCameraState()
	if originalCameraType then
		camera.CameraType = originalCameraType
		originalCameraType = nil
	end

	if originalCameraSubject then
		camera.CameraSubject = originalCameraSubject
		originalCameraSubject = nil
	end
end

--[[
将镜头移动到房屋上方
@param houseCenter Vector3 - 房屋中心位置
@param duration number - 移动时长
@return Promise - 返回一个Promise，完成时resolve
]]
local function MoveCameraToHouse(houseCenter, duration)
	return Promise.new(function(resolve, reject)
		-- 计算镜头目标位置（房屋后方上方）
		-- 注意：战场在房屋前方�?Z），所以镜头应该在房屋后方�?Z）才能看到房�?
		local cameraPosition = houseCenter + Vector3.new(0, CAMERA_HEIGHT, -CAMERA_DISTANCE)

		-- 计算镜头朝向（看向房屋中心）
		local lookAtPosition = houseCenter + Vector3.new(0, 5, 0)  -- 稍微往上看一�?
		local targetCFrame = CFrame.new(cameraPosition, lookAtPosition)

		-- 使用Tween平滑移动镜头
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)

		local tween = TweenService:Create(camera, tweenInfo, {
			CFrame = targetCFrame
		})

		tween.Completed:Connect(function()
			resolve()
		end)

		tween:Play()
	end)
end

--[[
开始房屋升级镜头表�?
@param homeSlot number - 玩家基地编号
]]
function HouseUpgradeCameraController.StartUpgradeSequence(homeSlot, oldModelName, newModelName)
	if isUpgrading then
		warn("[HouseUpgradeCameraController] Upgrade sequence already running")
		return
	end

	isUpgrading = true

	-- 保存当前镜头状�?
	SaveCameraState()

	-- 设置镜头为Scriptable模式
	camera.CameraType = Enum.CameraType.Scriptable

	-- 获取房屋文件�?
	local houseFolder = GetPlayerHouseFolder(homeSlot)
	if not houseFolder then
		warn("[HouseUpgradeCameraController] House folder not found")
		RestoreCameraState()
		isUpgrading = false
		return
	end

	-- 获取当前房屋模型
	local currentHouse = GetCurrentHouseModel(houseFolder)
	if not currentHouse then
		warn("[HouseUpgradeCameraController] Current house model not found")
		RestoreCameraState()
		isUpgrading = false
		return
	end

	-- 获取房屋中心位置
	local houseCenter = GetHouseCenter(currentHouse)

	-- 执行镜头移动序列
	task.spawn(function()
		-- 1. 立即切换镜头到房屋上方（不使用Tween，直接切换）
		local success, err = pcall(function()
			-- 计算镜头目标位置（房屋后方上方）
			local cameraPosition = houseCenter + Vector3.new(0, CAMERA_HEIGHT, -CAMERA_DISTANCE)
			-- 计算镜头朝向（看向房屋中心）
			local lookAtPosition = houseCenter + Vector3.new(0, 5, 0)
			local targetCFrame = CFrame.new(cameraPosition, lookAtPosition)

			-- 立即设置镜头位置（不使用Tween�?
			camera.CFrame = targetCFrame
		end)

		if not success then
			warn("[HouseUpgradeCameraController] 镜头切换失败:", err)
			RestoreCameraState()
			isUpgrading = false
			return
		end

		-- 2. Show upgrade popup (min 1s, click to close)
		popupClosedFired = false
		local closeSignal = ShowUpgradePopup(oldModelName, newModelName)
		if closeSignal then
			closeSignal.Event:Wait()
		else
			task.wait(POPUP_MIN_DURATION)
			NotifyPopupClosed()
		end

		task.wait(WAIT_AFTER_REPLACE)

		-- 6. 恢复镜头控制
		RestoreCameraState()
		isUpgrading = false

		-- Notify server sequence complete
		if InitializeEvents() then
			local completeEvent = HouseUpgradeEvents:FindFirstChild("UpgradeSequenceComplete")
			if completeEvent then
				completeEvent:FireServer()
			end
		end
	end)
end

--[[
初始化控制器
]]
function HouseUpgradeCameraController.Initialize()

	-- 等待RemoteEvent
	if not InitializeEvents() then
		warn("[HouseUpgradeCameraController] 初始化失败：找不到HouseUpgradeEvents")
		return
	end

	-- 监听服务端的房屋升级开始事�?
	local startUpgradeEvent = HouseUpgradeEvents:FindFirstChild("StartUpgradeSequence")
	if startUpgradeEvent then
		startUpgradeEvent.OnClientEvent:Connect(function(homeSlot, oldModelName, newModelName)
			HouseUpgradeCameraController.StartUpgradeSequence(homeSlot, oldModelName, newModelName)
		end)
	else
		warn("[HouseUpgradeCameraController] 找不到StartUpgradeSequence事件")
	end
end

-- 简单的Promise实现（如果游戏中没有Promise库）
Promise = {}
Promise.__index = Promise

function Promise.new(executor)
	local self = setmetatable({}, Promise)
	self._state = "pending"
	self._value = nil
	self._handlers = {}

	local function resolve(value)
		if self._state ~= "pending" then return end
		self._state = "resolved"
		self._value = value
		for _, handler in ipairs(self._handlers) do
			handler(value)
		end
	end

	local function reject(reason)
		if self._state ~= "pending" then return end
		self._state = "rejected"
		self._value = reason
	end

	task.spawn(function()
		local success, err = pcall(executor, resolve, reject)
		if not success then
			reject(err)
		end
	end)

	return self
end

function Promise:await()
	if self._state == "resolved" then
		return self._value
	elseif self._state == "rejected" then
		error(self._value)
	end

	-- 等待完成
	local completed = false
	local result = nil
	table.insert(self._handlers, function(value)
		result = value
		completed = true
	end)

	while not completed do
		task.wait()
	end

	return result
end

-- 自动初始�?
task.defer(function()
	HouseUpgradeCameraController.Initialize()
end)

return HouseUpgradeCameraController
