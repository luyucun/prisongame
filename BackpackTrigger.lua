--[[
脚本名称: BackpackTrigger
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/BackpackTrigger
]]

--[[
背包触发器
职责:
1. 检测玩家角色与IdleFloor的接触
2. 自动显示/隐藏背包UI
3. 防抖处理，避免频繁切换
版本: V2.0.2
]]

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- 配置参数
local CHECK_INTERVAL = 0.2  -- 检测间隔（秒）
local DISTANCE_THRESHOLD = 5  -- 距离阈值（studs）- 角色与IdleFloor中心的距离

-- 状态变量
local isOnIdleFloor = false  -- 当前是否在IdleFloor上
local isBackpackVisible = false  -- 当前背包是否已显示
local idleFloor = nil  -- 玩家的IdleFloor引用
local lastCheckTime = 0  -- 上次检测时间

-- 调试模式
local DEBUG_MODE = false

--[[
查找玩家的IdleFloor
@return Part|nil
]]
local function FindPlayerIdleFloor()
	-- 从玩家属性中读取HomeSlot
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot or homeSlot <= 0 then
		if DEBUG_MODE then
			warn("[BackpackTrigger] 玩家HomeSlot未设置，等待服务端分配...")
		end
		return nil
	end

	local homeFolder = workspace:FindFirstChild("Home")
	if not homeFolder then
		warn("[BackpackTrigger] Home文件夹不存在")
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		warn("[BackpackTrigger] 找不到基地: PlayerHome" .. homeSlot)
		return nil
	end

	local floor = playerHome:FindFirstChild("IdleFloor")
	if not floor then
		warn("[BackpackTrigger] 找不到IdleFloor")
		return nil
	end

	if DEBUG_MODE then
		print("[BackpackTrigger] 找到IdleFloor:", playerHome.Name)
	end

	return floor
end

--[[
检查角色是否在IdleFloor范围内
@return boolean
]]
local function IsCharacterOnIdleFloor()
	if not idleFloor or not idleFloor.Parent then
		return false
	end

	if not humanoidRootPart or not humanoidRootPart.Parent then
		return false
	end

	-- 计算角色与IdleFloor中心的距离
	local characterPos = humanoidRootPart.Position
	local floorPos = idleFloor.Position
	local floorSize = idleFloor.Size

	-- 检查X和Z轴是否在IdleFloor范围内（加上阈值）
	local halfSizeX = floorSize.X / 2 + DISTANCE_THRESHOLD
	local halfSizeZ = floorSize.Z / 2 + DISTANCE_THRESHOLD

	local deltaX = math.abs(characterPos.X - floorPos.X)
	local deltaZ = math.abs(characterPos.Z - floorPos.Z)

	-- Y轴检查（角色在IdleFloor上方或稍微下方）
	local deltaY = characterPos.Y - floorPos.Y
	local isOnY = deltaY > -5 and deltaY < 20  -- 允许在IdleFloor下方5studs到上方20studs

	local isInBounds = deltaX <= halfSizeX and deltaZ <= halfSizeZ and isOnY

	if DEBUG_MODE and isInBounds then
		print(string.format("[BackpackTrigger] 角色在IdleFloor上 - deltaX:%.2f, deltaZ:%.2f, deltaY:%.2f",
			deltaX, deltaZ, deltaY))
	end

	return isInBounds
end

local function HasAvailableUnits()
	if _G.BackpackDisplay and _G.BackpackDisplay.HasAvailableUnits then
		return _G.BackpackDisplay.HasAvailableUnits()
	end
	-- ✅ V2.0.2修复：默认返回false而不是true
	-- 原因：BackpackDisplay未加载时不应该显示背包
	return false
end

--[[
显示背包
]]
local function ShowBackpack()
	if _G.BackpackDisplay and _G.BackpackDisplay.ShowBackpack then
		_G.BackpackDisplay.ShowBackpack()
		if DEBUG_MODE then
			print("[BackpackTrigger] 背包已显示")
		end
	else
		-- 回退方案：直接控制BackpackGui
		local playerGui = player:WaitForChild("PlayerGui")
		local backpackGui = playerGui:FindFirstChild("BackpackGui")
		if backpackGui then
			backpackGui.Enabled = true
		end
	end
end

--[[
隐藏背包
]]
local function HideBackpack()
	if _G.BackpackDisplay and _G.BackpackDisplay.HideBackpack then
		_G.BackpackDisplay.HideBackpack()
		if DEBUG_MODE then
			print("[BackpackTrigger] 背包已隐藏")
		end
	else
		-- 回退方案：直接控制BackpackGui
		local playerGui = player:WaitForChild("PlayerGui")
		local backpackGui = playerGui:FindFirstChild("BackpackGui")
		if backpackGui then
			backpackGui.Enabled = false
		end
	end
end

--[[
更新背包显示状态
]]
local function UpdateBackpackVisibility()
	local onFloor = IsCharacterOnIdleFloor()
	local hasUnits = HasAvailableUnits()
	local shouldShow = onFloor and hasUnits

	if shouldShow ~= isBackpackVisible then
		isBackpackVisible = shouldShow

		if shouldShow then
			ShowBackpack()
		else
			HideBackpack()
		end
	end

	isOnIdleFloor = onFloor
end

--[[
初始化
]]
local function Initialize()
	print("[BackpackTrigger] 正在初始化...")

	-- 等待角色完全加载
	task.wait(1)

	-- 查找IdleFloor（带重试）
	local maxRetries = 10
	local retryCount = 0
	while not idleFloor and retryCount < maxRetries do
		idleFloor = FindPlayerIdleFloor()
		if not idleFloor then
			task.wait(0.5)
			retryCount = retryCount + 1
		end
	end

	if not idleFloor then
		warn("[BackpackTrigger] 无法找到IdleFloor，背包触发器将不可用")
		return
	end

	print("[BackpackTrigger] IdleFloor已找到，开始监听...")

	-- 启动定时检测
	RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - lastCheckTime >= CHECK_INTERVAL then
			lastCheckTime = currentTime
			UpdateBackpackVisibility()
		end
	end)

	print("[BackpackTrigger] 初始化完成")
end

-- 监听角色重生
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	isOnIdleFloor = false
	isBackpackVisible = false

	-- 重新查找IdleFloor
	task.wait(1)
	idleFloor = FindPlayerIdleFloor()

	if DEBUG_MODE then
		print("[BackpackTrigger] 角色重生，IdleFloor已重新定位")
	end
end)

_G.BackpackTrigger = _G.BackpackTrigger or {}
_G.BackpackTrigger.RefreshVisibility = UpdateBackpackVisibility

-- 启动初始化
task.spawn(Initialize)

print("[BackpackTrigger] 模块已加载")
