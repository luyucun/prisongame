--[[
脚本名称: IdleCoinController
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/IdleCoinController
版本: V2.6
]]

--[[
挂机金币客户端控制器
职责:
1. 显示ProximityPrompt交互提示（靠近Mail模型时）
2. 处理玩家长按E键领取金币
3. 更新Mail模型上的金币数量显示
]]

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 获取本地玩家
local player = Players.LocalPlayer

-- 状态变量
local currentPrompt = nil
local pendingIdleCoins = 0
local cachedHomeId = nil  -- 缓存HomeId，避免重复查询

-- 事件引用
local IdleCoinEvents = nil

-- ==================== 私有函数 ====================

--[[
初始化事件
@return boolean - 是否成功
]]
local function InitializeEvents()
	if IdleCoinEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[IdleCoinController] Events文件夹未找到")
		return false
	end

	IdleCoinEvents = eventsFolder:WaitForChild("IdleCoinEvents", 10)
	if not IdleCoinEvents then
		warn("[IdleCoinController] IdleCoinEvents未找到")
		return false
	end

	return true
end

--[[
获取玩家基地ID（带等待机制）
@param waitForAttribute boolean - 是否等待属性被设置
@return number|nil - 基地ID
]]
local function GetPlayerHomeId(waitForAttribute)
	-- 如果已有缓存，直接返回
	if cachedHomeId and cachedHomeId > 0 then
		return cachedHomeId
	end

	-- 首选方案：从服务端同步的HomeSlot属性获取（PlayerManager在分配基地时会设置这个属性）
	local homeSlot = player:GetAttribute("HomeSlot")
	if homeSlot and type(homeSlot) == "number" and homeSlot > 0 then
		cachedHomeId = homeSlot
		return homeSlot
	end

	-- 如果需要等待，则使用GetAttributeChangedSignal监听属性变化
	if waitForAttribute then
		local maxWaitTime = 15  -- 最大等待15秒
		local startTime = tick()

		-- 先检查一次
		homeSlot = player:GetAttribute("HomeSlot")
		if homeSlot and type(homeSlot) == "number" and homeSlot > 0 then
			cachedHomeId = homeSlot
			return homeSlot
		end

		-- 等待属性变化
		while tick() - startTime < maxWaitTime do
			homeSlot = player:GetAttribute("HomeSlot")
			if homeSlot and type(homeSlot) == "number" and homeSlot > 0 then
				cachedHomeId = homeSlot
				print("[IdleCoinController] HomeSlot已获取: " .. homeSlot)
				return homeSlot
			end
			task.wait(0.2)
		end

		warn("[IdleCoinController] 等待HomeSlot超时")
	end

	-- 备用方案：从IntValue获取
	local homeIdValue = player:FindFirstChild("HomeId")
	if homeIdValue and homeIdValue:IsA("IntValue") and homeIdValue.Value > 0 then
		cachedHomeId = homeIdValue.Value
		return homeIdValue.Value
	end

	return nil
end

--[[
获取玩家基地的Mail模型
@param waitForHomeId boolean - 是否等待HomeId被设置
@return Model|nil - Mail模型
]]
local function GetMailModel(waitForHomeId)
	local homeId = GetPlayerHomeId(waitForHomeId)
	if not homeId then
		-- 只有在等待后仍找不到才打印警告
		if waitForHomeId then
			warn("[IdleCoinController] 未找到HomeSlot/HomeId，无法定位玩家基地Mail")
		end
		return nil
	end

	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end
	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeId)
	if not playerHome then
		return nil
	end

	return playerHome:FindFirstChild("Mail")
end

--[[
获取Mail模型的有效PrimaryPart（带多级回退机制）
@param mailModel Model - Mail模型
@return BasePart|nil - PrimaryPart
]]
local function GetMailPrimaryPart(mailModel)
	-- 首选：使用Model的PrimaryPart属性
	local primaryPart = mailModel.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	-- 回退1：查找名为"PrimaryPart"的子Part（解决克隆时PrimaryPart引用丢失的问题）
	local namedPart = mailModel:FindFirstChild("PrimaryPart")
	if namedPart and namedPart:IsA("BasePart") then
		mailModel.PrimaryPart = namedPart
		print("[IdleCoinController] 已通过名称'PrimaryPart'找到并设置PrimaryPart")
		return namedPart
	end

	-- 回退2：递归查找名为"PrimaryPart"的Part（可能在更深层级）
	local function FindPartRecursive(parent, name)
		for _, child in ipairs(parent:GetDescendants()) do
			if child.Name == name and child:IsA("BasePart") then
				return child
			end
		end
		return nil
	end

	local deepPart = FindPartRecursive(mailModel, "PrimaryPart")
	if deepPart then
		mailModel.PrimaryPart = deepPart
		print("[IdleCoinController] 已在子层级找到并设置PrimaryPart: " .. deepPart:GetFullName())
		return deepPart
	end

	-- 回退3：使用Mail下的第一个BasePart（如IdleEarnings）
	for _, child in ipairs(mailModel:GetChildren()) do
		if child:IsA("BasePart") then
			mailModel.PrimaryPart = child
			print("[IdleCoinController] 使用备用Part作为PrimaryPart: " .. child.Name)
			return child
		end
	end

	return nil
end

--[[
创建ProximityPrompt
@param parent Instance - 父节点
@return ProximityPrompt - 创建的ProximityPrompt
]]
local function CreateProximityPrompt(parent)
	-- 检查是否已存在
	local existingPrompt = parent:FindFirstChild("IdleCoinPrompt")
	if existingPrompt then
		return existingPrompt
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IdleCoinPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Idle Coins"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = GameConfig.IdleCoin.ProximityHoldDuration
	prompt.MaxActivationDistance = GameConfig.IdleCoin.ProximityTriggerDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent

	return prompt
end

--[[
处理领取金币
]]
local function OnCollectCoins()
	if not InitializeEvents() then
		return
	end

	local collectEvent = IdleCoinEvents:FindFirstChild("CollectIdleCoins")
	if collectEvent then
		collectEvent:FireServer()
		print("[IdleCoinController] 发送领取挂机金币请求")
	end
end

--[[
更新金币显示（仅缓存本地状态，实际显示由服务端负责）
@param coins number - 待领取金币数量
]]
local function UpdateCoinDisplay(coins)
	-- 仅缓存待领取金币数量，用于本地逻辑判断
	-- 实际的Mail上TextLabel显示由服务端的UpdateMailDisplay负责更新
	-- 服务端修改Workspace中的对象会自动同步到所有客户端
	pendingIdleCoins = coins
	print("[IdleCoinController] 收到挂机金币同步: " .. coins)
end

--[[
初始化Mail模型的ProximityPrompt
@param waitForHomeId boolean - 是否等待HomeId被设置（首次初始化时为true，重生时为false）
]]
local function SetupMailPrompt(waitForHomeId)
	-- 根据参数决定是否等待HomeSlot属性被设置
	local mailModel = GetMailModel(waitForHomeId)
	if not mailModel then
		warn("[IdleCoinController] 未找到Mail模型")
		return
	end

	-- 使用Mail模型的PrimaryPart作为交互点（带回退机制）
	local primaryPart = GetMailPrimaryPart(mailModel)
	if not primaryPart then
		warn("[IdleCoinController] Mail模型未设置PrimaryPart，且未找到名为'PrimaryPart'的子Part")
		-- 列出Mail子节点便于排查
		for _, child in ipairs(mailModel:GetChildren()) do
			print("[IdleCoinController] Mail子节点: " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return
	end

	local prompt = CreateProximityPrompt(primaryPart)
	currentPrompt = prompt

	-- 连接领取事件
	prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer == player then
			OnCollectCoins()
		end
	end)

	print("[IdleCoinController] Mail ProximityPrompt已创建，挂载在PrimaryPart: " .. primaryPart.Name)
end

-- ==================== 初始化 ====================

local function Initialize()
	print("[IdleCoinController] 开始初始化...")

	-- 初始化事件
	if not InitializeEvents() then
		-- 重试
		task.delay(3, function()
			if InitializeEvents() then
				-- 连接同步事件
				local syncEvent = IdleCoinEvents:FindFirstChild("SyncIdleCoins")
				if syncEvent then
					syncEvent.OnClientEvent:Connect(function(coins)
						UpdateCoinDisplay(coins)
					end)
				end
			end
		end)
	else
		-- 连接同步事件
		local syncEvent = IdleCoinEvents:FindFirstChild("SyncIdleCoins")
		if syncEvent then
			syncEvent.OnClientEvent:Connect(function(coins)
				UpdateCoinDisplay(coins)
			end)
		end
	end

	-- 设置Mail的ProximityPrompt（首次初始化，需要等待HomeId）
	task.spawn(function()
		SetupMailPrompt(true)
	end)

	-- 监听角色加载（重生后重新设置，不需要等待HomeId）
	player.CharacterAdded:Connect(function()
		task.wait(1)
		SetupMailPrompt(false)
	end)

	print("[IdleCoinController] 初始化完成")
end

-- 启动初始化
Initialize()
