--[[
=====================================================
脚本名称: PowerDisplayController.lua
脚本类型: LocalScript
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/PowerDisplayController
版本: V3.9.2
功能描述: 客户端战斗力显示控制器
=====================================================
--]]

local PowerDisplayController = {}

-- ==================== 服务引用 ====================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ==================== 本地引用 ====================
local player = Players.LocalPlayer
local Workspace = game:GetService("Workspace")

-- ==================== RemoteEvent ====================
local PowerEvents
local PowerUpdateEvent

-- ==================== 本地变量 ====================
local informationModel = nil
local surfaceGuis = {}
local isInitialized = false
local cachedHomeId = nil

-- ==================== 工具函数 ====================

--[[
	获取玩家基地ID（带等待机制）
	@param waitForAttribute boolean - 是否等待属性被设置
	@return number|nil - 基地ID
]]
local function GetPlayerHomeId(waitForAttribute)
	if cachedHomeId and cachedHomeId > 0 then
		return cachedHomeId
	end

	local homeSlot = player:GetAttribute("HomeSlot")
	if homeSlot and type(homeSlot) == "number" and homeSlot > 0 then
		cachedHomeId = homeSlot
		return homeSlot
	end

	if waitForAttribute then
		local maxWaitTime = 15
		local startTime = tick()

		while tick() - startTime < maxWaitTime do
			homeSlot = player:GetAttribute("HomeSlot")
			if homeSlot and type(homeSlot) == "number" and homeSlot > 0 then
				cachedHomeId = homeSlot
				return homeSlot
			end
			task.wait(0.2)
		end
	end

	local homeIdValue = player:FindFirstChild("HomeId")
	if homeIdValue and homeIdValue:IsA("IntValue") and homeIdValue.Value > 0 then
		cachedHomeId = homeIdValue.Value
		return homeIdValue.Value
	end

	return nil
end

--[[
	查找玩家的Information模型
	@param waitForHomeId boolean - 是否等待HomeId被设置
]]
local function FindPlayerInformation(waitForHomeId)
	-- 优先从LoadingController获取预加载的Information
	if _G.LoadingController and _G.LoadingController.GetPreloadedInformation then
		local preloaded = _G.LoadingController.GetPreloadedInformation()
		if preloaded then
			return preloaded
		end
	end

	if not Workspace:FindFirstChild("Home") then
		return nil
	end

	local homeId = GetPlayerHomeId(waitForHomeId)
	if not homeId then
		return nil
	end

	local playerHome = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
	if not playerHome then
		return nil
	end

	local info = playerHome:FindFirstChild("Information")
	return info
end

--[[
	初始化SurfaceGui引用
]]
local function InitializeSurfaceGuis()
	if not informationModel then
		return false
	end

	local part = informationModel:WaitForChild("Part", 5)
	if not part then
		return false
	end

	local surfaceGui01 = part:WaitForChild("SurfaceGui01", 3)
	local surfaceGui02 = part:WaitForChild("SurfaceGui02", 3)

	if not surfaceGui01 then
		return false
	end

	if not surfaceGui02 then
		surfaceGuis = {surfaceGui01}
	else
		surfaceGuis = {surfaceGui01, surfaceGui02}
	end

	return true
end

--[[
	更新单个SurfaceGui的显示
	@param surfaceGui SurfaceGui - 要更新的SurfaceGui
	@param playerName string - 玩家名字
	@param power number - 战斗力数值
]]
local function UpdateSurfaceGui(surfaceGui, playerName, power)
	if not surfaceGui then
		return
	end

	local frame = surfaceGui:FindFirstChild("Frame")
	if not frame then
		return
	end

	local playerNameContainer = frame:FindFirstChild("PlayerName")
	if playerNameContainer then
		local nameLabel = playerNameContainer:FindFirstChild("Name")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = playerName
		end
	end

	local playerPowerContainer = frame:FindFirstChild("PlayerPower")
	if playerPowerContainer then
		local numLabel = playerPowerContainer:FindFirstChild("Num")
		if numLabel and numLabel:IsA("TextLabel") then
			numLabel.Text = tostring(power)
		end
	end
end

--[[
	更新所有SurfaceGui的显示
	@param power number - 战斗力数值
]]
local function UpdateAllDisplays(power)
	local playerName = player.Name

	for _, surfaceGui in ipairs(surfaceGuis) do
		UpdateSurfaceGui(surfaceGui, playerName, power)
	end
end

-- ==================== RemoteEvent处理 ====================

--[[
	处理服务端发来的战斗力更新
	@param totalPower number - 总战斗力
]]
local function OnPowerUpdate(totalPower)
	if not isInitialized then
		return
	end

	if not totalPower or type(totalPower) ~= "number" then
		return
	end

	UpdateAllDisplays(totalPower)
end

-- ==================== 初始化 ====================

--[[
	初始化控制器
]]
function PowerDisplayController.Initialize()
	-- 等待Loading完成后再初始化
	if _G.LoadingController then
		local maxWait = 30
		local startTime = tick()
		while not _G.LoadingController.IsLoadingComplete() do
			if tick() - startTime > maxWait then
				break
			end
			task.wait(0.5)
		end
	end

	-- 获取PowerEvents
	PowerEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PowerEvents", 10)
	if not PowerEvents then
		return
	end

	-- 获取PowerUpdateEvent
	PowerUpdateEvent = PowerEvents:WaitForChild("PowerUpdate", 10)
	if not PowerUpdateEvent then
		return
	end

	-- 连接RemoteEvent
	PowerUpdateEvent.OnClientEvent:Connect(OnPowerUpdate)

	-- 等待角色加载
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	-- 查找Information模型
	informationModel = FindPlayerInformation(true)
	if not informationModel then
		task.wait(3)
		informationModel = FindPlayerInformation(false)

		if not informationModel then
			return
		end
	end

	-- 初始化SurfaceGui引用
	if not InitializeSurfaceGuis() then
		return
	end

	-- 初始化完成
	isInitialized = true

	-- 初始化显示
	UpdateAllDisplays(0)

	-- 主动请求服务端发送当前战斗力
	if PowerEvents then
		local requestEvent = PowerEvents:WaitForChild("RequestPower", 5)
		if requestEvent then
			requestEvent:FireServer()
		end
	end
end

--[[
	处理角色重生
]]
local function OnCharacterAdded(character)
	if not isInitialized then
		return
	end

	task.wait(1)
	informationModel = FindPlayerInformation(false)

	if informationModel then
		InitializeSurfaceGuis()
	end
end

-- ==================== 启动 ====================

player.CharacterAdded:Connect(OnCharacterAdded)

task.spawn(function()
	local success, err = pcall(PowerDisplayController.Initialize)
	if not success then
		warn("[PowerDisplayController] 初始化出错:", err)
	end
end)

-- ==================== 导出 ====================

return PowerDisplayController
