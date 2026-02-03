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
local character = player.Character
local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart") or nil

-- 关键修复：不要在脚本顶部等待Character/HRP
-- 否则会阻塞 _G.BackpackTrigger 接口注册，导致RemovalController等模块偶现找不到接口
task.spawn(function()
	local currentCharacter = player.Character or player.CharacterAdded:Wait()
	character = currentCharacter

	local hrp = currentCharacter:WaitForChild("HumanoidRootPart")
	if character == currentCharacter then
		humanoidRootPart = hrp
	end
end)

-- 配置参数
local CHECK_INTERVAL = 0.2  -- 检测间隔（秒）
local RAYCAST_DISTANCE = 8  -- studs downward to detect IdleFloor contact

-- 状态变量
local isOnIdleFloor = false  -- 当前是否在IdleFloor上
local isBackpackVisible = false  -- 当前背包是否已显示
local idleFloor = nil  -- 玩家的IdleFloor引用
local lastCheckTime = 0  -- 上次检测时间
local idleFloorListeners = {}
local hideLocks = {} -- 临时隐藏背包的锁（多界面叠加）
local heartbeatConnection = nil
local idleFloorResolveInProgress = false
local IDLE_FLOOR_RETRY_INTERVAL = 0.5
local IDLE_FLOOR_WARN_INTERVAL = 10
local lastIdleFloorWarnTime = 0

-- 调试模式
local DEBUG_MODE = false

local function WarnIdleFloorIssue(message)
	local now = tick()
	if now - lastIdleFloorWarnTime < IDLE_FLOOR_WARN_INTERVAL then
		return
	end
	lastIdleFloorWarnTime = now
	warn(message)
end

local function HasHideLock()
	for _ in pairs(hideLocks) do
		return true
	end
	return false
end

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
		WarnIdleFloorIssue("[BackpackTrigger] Home文件夹不存在")
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		WarnIdleFloorIssue("[BackpackTrigger] 找不到基地: PlayerHome" .. homeSlot)
		return nil
	end

	local floor = playerHome:FindFirstChild("IdleFloor")
	if not floor then
		WarnIdleFloorIssue("[BackpackTrigger] 找不到IdleFloor")
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

	local origin = humanoidRootPart.Position
	local direction = Vector3.new(0, -RAYCAST_DISTANCE, 0)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { idleFloor }
	rayParams.IgnoreWater = true

	local hit = workspace:Raycast(origin, direction, rayParams)

	if DEBUG_MODE and hit then
		print(string.format("[BackpackTrigger] IdleFloor contact - hitY:%.2f", hit.Position.Y))
	end

	return hit ~= nil
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
	local forceHide = HasHideLock()
	local shouldShow = onFloor and not forceHide

	if shouldShow ~= isBackpackVisible then
		isBackpackVisible = shouldShow

		if shouldShow then
			ShowBackpack()
		else
			HideBackpack()
		end
	end

	if onFloor ~= isOnIdleFloor then
		isOnIdleFloor = onFloor
		-- 通知监听者 IdleFloor 状态变化
		for _, cb in ipairs(idleFloorListeners) do
			task.spawn(cb, isOnIdleFloor)
		end
	end
end

--[[
初始化
]]
local function StartHeartbeat()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - lastCheckTime >= CHECK_INTERVAL then
			lastCheckTime = currentTime
			UpdateBackpackVisibility()
		end
	end)
end

local function ResolveIdleFloor()
	if idleFloorResolveInProgress then
		return
	end
	if idleFloor then
		StartHeartbeat()
		return
	end
	idleFloorResolveInProgress = true

	task.spawn(function()
		while not idleFloor do
			idleFloor = FindPlayerIdleFloor()
			if idleFloor then
				StartHeartbeat()
				break
			end
			task.wait(IDLE_FLOOR_RETRY_INTERVAL)
		end
		idleFloorResolveInProgress = false
	end)
end

local function Initialize()
	-- 等待角色完全加载
	task.wait(1)
	ResolveIdleFloor()
end
-- 监听角色重生
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	isOnIdleFloor = false
	isBackpackVisible = false

	-- 重新查找IdleFloor
	task.wait(1)
	idleFloor = nil
	ResolveIdleFloor()

	if DEBUG_MODE then
		print("[BackpackTrigger] 角色重生，IdleFloor已重新定位")
	end
end)

-- ==================== 全局接口注册（提前注册，确保其他模块能立即访问） ====================
-- 修复：将接口注册移到初始化之前，避免RemovalController等模块找不到接口
player:GetAttributeChangedSignal("HomeSlot"):Connect(function()
	local homeSlot = player:GetAttribute("HomeSlot")
	if homeSlot and homeSlot > 0 then
		ResolveIdleFloor()
	end
end)

_G.BackpackTrigger = _G.BackpackTrigger or {}
_G.BackpackTrigger.RefreshVisibility = UpdateBackpackVisibility
_G.BackpackTrigger.PushHideLock = function(key)
	if not key then
		return
	end
	hideLocks[key] = true
	UpdateBackpackVisibility()
end
_G.BackpackTrigger.PopHideLock = function(key)
	if not key then
		return
	end
	hideLocks[key] = nil
	UpdateBackpackVisibility()
end
_G.BackpackTrigger.IsOnIdleFloor = function()
	return isOnIdleFloor
end
_G.BackpackTrigger.SubscribeIdleFloorChanged = function(callback)
	if typeof(callback) == "function" then
		table.insert(idleFloorListeners, callback)
	end
end

-- 启动初始化（异步执行，但接口已经可用）
task.spawn(Initialize)
