--[[
脚本名称: HouseUpgradeCameraController
脚本类型: LocalScript
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/HouseUpgradeCameraController
版本: V3.9
]]

--[[
房屋升级镜头控制器
职责:
1. 接收服务端房屋升级通知
2. 控制镜头拉高看向房屋
3. 等待房屋替换完成
4. 恢复镜头控制

流程:
1. 玩家通关章节后点击胜利弹窗确认
2. 玩家重生在基地
3. 服务端通知客户端开始房屋升级表现
4. 客户端镜头拉高看向房屋
5. 等待1秒
6. 旧房屋消失，新房屋出现（服务端处理）
7. 等待1秒
8. 恢复镜头控制
]]

local HouseUpgradeCameraController = {}

-- 服务引用
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- 本地玩家
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- 状态标记
local isUpgrading = false
local originalCameraType = nil
local originalCameraSubject = nil

-- 配置参数
local CAMERA_HEIGHT = 30  -- 镜头高度
local CAMERA_DISTANCE = 40  -- 镜头距离房屋的距离
local CAMERA_ANGLE = math.rad(30)  -- 镜头俯视角度（30度）
local TWEEN_DURATION = 1.0  -- 镜头移动时长
local WAIT_BEFORE_REPLACE = 1.0  -- 房屋替换前等待时间
local WAIT_AFTER_REPLACE = 1.0  -- 房屋替换后等待时间

-- RemoteEvent引用
local HouseUpgradeEvents = nil

--[[
初始化RemoteEvent
]]
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

--[[
获取玩家的House文件夹
@param homeSlot number - 玩家基地编号(1-6)
@return Folder|nil - House文件夹
]]
local function GetPlayerHouseFolder(homeSlot)
	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		warn("[HouseUpgradeCameraController] Home文件夹不存在")
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		warn("[HouseUpgradeCameraController] PlayerHome" .. homeSlot .. " 不存在")
		return nil
	end

	local houseFolder = playerHome:FindFirstChild("House")
	return houseFolder
end

--[[
获取House文件夹下的当前房屋模型
@param houseFolder Folder - House文件夹
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
计算房屋的中心位置
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
保存当前镜头状态
]]
local function SaveCameraState()
	originalCameraType = camera.CameraType
	originalCameraSubject = camera.CameraSubject
end

--[[
恢复镜头状态
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
		-- 注意：战场在房屋前方（+Z），所以镜头应该在房屋后方（-Z）才能看到房屋
		local cameraPosition = houseCenter + Vector3.new(0, CAMERA_HEIGHT, -CAMERA_DISTANCE)

		-- 计算镜头朝向（看向房屋中心）
		local lookAtPosition = houseCenter + Vector3.new(0, 5, 0)  -- 稍微往上看一点
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
开始房屋升级镜头表现
@param homeSlot number - 玩家基地编号
]]
function HouseUpgradeCameraController.StartUpgradeSequence(homeSlot)
	if isUpgrading then
		warn("[HouseUpgradeCameraController] 已经在升级中，跳过")
		return
	end

	isUpgrading = true
	print(string.format("[HouseUpgradeCameraController] 开始房屋升级镜头表现，HomeSlot=%d", homeSlot))

	-- 保存当前镜头状态
	SaveCameraState()

	-- 设置镜头为Scriptable模式
	camera.CameraType = Enum.CameraType.Scriptable

	-- 获取房屋文件夹
	local houseFolder = GetPlayerHouseFolder(homeSlot)
	if not houseFolder then
		warn("[HouseUpgradeCameraController] 找不到House文件夹")
		RestoreCameraState()
		isUpgrading = false
		return
	end

	-- 获取当前房屋模型
	local currentHouse = GetCurrentHouseModel(houseFolder)
	if not currentHouse then
		warn("[HouseUpgradeCameraController] 找不到房屋模型")
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

			-- 立即设置镜头位置（不使用Tween）
			camera.CFrame = targetCFrame
			print("[HouseUpgradeCameraController] 镜头已立即切换到房屋上方")
		end)

		if not success then
			warn("[HouseUpgradeCameraController] 镜头切换失败:", err)
			RestoreCameraState()
			isUpgrading = false
			return
		end

		print("[HouseUpgradeCameraController] 镜头已到位，等待房屋替换...")

		-- 2. 等待1秒（让玩家看清楚房屋）
		task.wait(WAIT_BEFORE_REPLACE)

		-- 3. 通知服务端可以替换房屋了
		if InitializeEvents() then
			local readyEvent = HouseUpgradeEvents:FindFirstChild("ClientCameraReady")
			if readyEvent then
				readyEvent:FireServer()
				print("[HouseUpgradeCameraController] 已通知服务端镜头就位")
			end
		end

		-- 4. 等待房屋替换完成（服务端会发送ReplaceComplete事件）
		-- 这里我们等待一个信号或者固定时间
		task.wait(WAIT_AFTER_REPLACE + 0.5)  -- 等待房屋替换 + 额外0.5秒

		print("[HouseUpgradeCameraController] 房屋替换完成，等待后恢复镜头...")

		-- 5. 再等待1秒（让玩家看清楚新房屋）
		task.wait(WAIT_AFTER_REPLACE)

		-- 6. 恢复镜头控制
		RestoreCameraState()
		isUpgrading = false
		print("[HouseUpgradeCameraController] 房屋升级镜头表现完成")
	end)
end

--[[
初始化控制器
]]
function HouseUpgradeCameraController.Initialize()
	print("[HouseUpgradeCameraController] 初始化中...")

	-- 等待RemoteEvent
	if not InitializeEvents() then
		warn("[HouseUpgradeCameraController] 初始化失败：找不到HouseUpgradeEvents")
		return
	end

	-- 监听服务端的房屋升级开始事件
	local startUpgradeEvent = HouseUpgradeEvents:FindFirstChild("StartUpgradeSequence")
	if startUpgradeEvent then
		startUpgradeEvent.OnClientEvent:Connect(function(homeSlot)
			print(string.format("[HouseUpgradeCameraController] 收到房屋升级通知，HomeSlot=%d", homeSlot))
			HouseUpgradeCameraController.StartUpgradeSequence(homeSlot)
		end)
		print("[HouseUpgradeCameraController] 已监听StartUpgradeSequence事件")
	else
		warn("[HouseUpgradeCameraController] 找不到StartUpgradeSequence事件")
	end

	print("[HouseUpgradeCameraController] 初始化完成")
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

-- 自动初始化
task.defer(function()
	HouseUpgradeCameraController.Initialize()
end)

return HouseUpgradeCameraController
