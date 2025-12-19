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

-- 缓存每个SurfaceGui的默认文本（用于玩家离线后恢复显示）
local defaultDisplayCache = {} -- [SurfaceGui] = { NameText = string, PowerText = string }

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
	获取/缓存SurfaceGui的默认文本（Name/Num）
	@param surfaceGui SurfaceGui
	@return table
]]
local function GetOrCacheDefaultDisplay(surfaceGui)
	if not surfaceGui then
		return { NameText = "", PowerText = "0" }
	end

	local cached = defaultDisplayCache[surfaceGui]
	if cached then
		return cached
	end

	local defaults = {
		NameText = "",
		PowerText = "0",
	}

	local frame = surfaceGui:FindFirstChild("Frame")
	if frame then
		local playerNameContainer = frame:FindFirstChild("PlayerName")
		local nameLabel = playerNameContainer and playerNameContainer:FindFirstChild("Name")
		if nameLabel and nameLabel:IsA("TextLabel") then
			defaults.NameText = nameLabel.Text
		end

		local playerPowerContainer = frame:FindFirstChild("PlayerPower")
		local numLabel = playerPowerContainer and playerPowerContainer:FindFirstChild("Num")
		if numLabel and numLabel:IsA("TextLabel") then
			defaults.PowerText = numLabel.Text
		end
	end

	defaultDisplayCache[surfaceGui] = defaults
	return defaults
end

local function ResetSurfaceGuiToDefault(surfaceGui)
	if not surfaceGui then
		return
	end

	local defaults = defaultDisplayCache[surfaceGui]
	if not defaults then
		-- 如果没缓存过，尝试读取当前作为默认（兜底，不阻断）
		defaults = GetOrCacheDefaultDisplay(surfaceGui)
	end

	local frame = surfaceGui:FindFirstChild("Frame")
	if not frame then
		return
	end

	local playerNameContainer = frame:FindFirstChild("PlayerName")
	local nameLabel = playerNameContainer and playerNameContainer:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = defaults.NameText or ""
	end

	local playerPowerContainer = frame:FindFirstChild("PlayerPower")
	local numLabel = playerPowerContainer and playerPowerContainer:FindFirstChild("Num")
	if numLabel and numLabel:IsA("TextLabel") then
		numLabel.Text = defaults.PowerText or "0"
	end
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

	-- 先缓存默认文本（只缓存一次）
	GetOrCacheDefaultDisplay(surfaceGui)

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
local function OnPowerUpdate(playerNameOrTotalPower, homeIdOrNil, totalPowerOrNil)
	-- 🔥V3.9.2修复：兼容新旧两种参数格式
	local playerName, homeId, totalPower

	if type(playerNameOrTotalPower) == "number" and homeIdOrNil == nil and totalPowerOrNil == nil then
		-- 旧版格式：OnPowerUpdate(totalPower)
		-- 这是给自己的战力更新
		if not isInitialized then
			return
		end

		totalPower = playerNameOrTotalPower
		playerName = player.Name
		homeId = GetPlayerHomeId(false)

		if not homeId then
			return
		end

		UpdateAllDisplays(totalPower)
		return
	elseif type(playerNameOrTotalPower) == "string" and type(homeIdOrNil) == "number" and type(totalPowerOrNil) == "number" then
		-- 新版格式：OnPowerUpdate(playerName, homeId, totalPower)
		-- 这是广播给所有客户端的更新
		playerName = playerNameOrTotalPower
		homeId = homeIdOrNil
		totalPower = totalPowerOrNil
	else
		-- 参数格式不正确
		warn("[PowerDisplayController] OnPowerUpdate 参数格式不正确:", playerNameOrTotalPower, homeIdOrNil, totalPowerOrNil)
		return
	end

	-- 查找对应基地的Information模型
	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeId)
	if not playerHome then
		return
	end

	local information = playerHome:FindFirstChild("Information")
	if not information then
		return
	end

	local part = information:FindFirstChild("Part")
	if not part then
		return
	end

	-- 更新所有SurfaceGui
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceGui") and (child.Name == "SurfaceGui01" or child.Name == "SurfaceGui02") then
			-- ⚠️说明：Information面板现在由服务端写入（世界状态复制），客户端在“清空”事件时不应再本地写文本，
			-- 否则在网络乱序/缓存默认文本不准时，可能把旧玩家信息写回去导致看起来“没清理”。
			if playerName ~= "" then
				UpdateSurfaceGui(child, playerName, totalPower)
			end
		end
	end

	-- 如果是自己的战力更新，也更新本地缓存的显示
	if homeId == GetPlayerHomeId(false) and isInitialized then
		UpdateAllDisplays(totalPower)
	end
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
