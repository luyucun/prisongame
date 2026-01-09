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
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
local FormatHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FormatHelper"))

-- 获取本地玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local IDLE_COIN_PRODUCT_ID = 3487946200

-- 状态变量
local currentPrompt = nil
local promptConnections = {}
local mailPromptResolveInProgress = false
local mailPromptReady = false
local pendingIdleCoins = 0
local cachedHomeId = nil  -- 缓存HomeId，避免重复查询
local autoPopupShown = false
local hasReceivedInitialSync = false
local promptOpensPopup = true
local claim10InProgress = false

-- 事件引用
local IdleCoinEvents = nil
local OnCollectCoins = nil

-- UI引用
local idleEarningGui = nil
local idleEarningBg = nil
local idleCloseButton = nil
local idleTimeLabel = nil
local idleTimeTitle = nil
local idleClaimButton = nil
local idleClaimCash = nil
local idleClaim10Button = nil
local idleClaim10Cash = nil
local idleScale = nil

-- UI状态
local idleUiTween = nil
local idleUiToken = 0
local idleUiBound = false
local gradientTween = nil

local ButtonEffectHelper = nil

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

local function LoadButtonEffectHelper()
	if ButtonEffectHelper then
		return true
	end

	local success, result = pcall(function()
		return require(game:GetService("StarterPlayer").StarterPlayerScripts.Utils.ButtonEffectHelper)
	end)

	if success then
		ButtonEffectHelper = result
		return true
	end

	warn("[IdleCoinController] ButtonEffectHelper加载失败:", result)
	return false
end

local function FormatIdleTime(totalMinutes)
	local minutes = math.max(0, math.floor(tonumber(totalMinutes) or 0))
	local hours = math.floor(minutes / 60)
	local mins = minutes % 60
	return string.format("%02d:%02d", hours, mins)
end

local function GetCompletedChapters()
	local completed = player:GetAttribute("CompletedChapters")
	if type(completed) == "number" then
		return completed
	end
	return 0
end

local function GetIdleConfigForPlayer()
	local completedChapters = GetCompletedChapters()
	local houseConfig = HouseConfig.GetIdleConfigByCompletedChapters(completedChapters)

	local coinsPerMinute = houseConfig and tonumber(houseConfig.CoinsPerMinute) or 0
	local maxMinutes = houseConfig and tonumber(houseConfig.MaxMinutes) or 0
	local maxHours = houseConfig and tonumber(houseConfig.MaxHours) or 0

	if coinsPerMinute <= 0 then
		coinsPerMinute = tonumber(GameConfig.IdleCoin.CoinsPerMinute) or 0
	end

	if maxMinutes <= 0 then
		maxMinutes = tonumber(GameConfig.IdleCoin.MaxOfflineMinutes) or 0
	end

	if maxHours <= 0 then
		maxHours = math.floor(maxMinutes / 60)
	end

	return {
		CoinsPerMinute = coinsPerMinute,
		MaxMinutes = maxMinutes,
		MaxHours = maxHours,
	}
end

local function GetPendingIdleMinutes()
	local idleConfig = GetIdleConfigForPlayer()
	local coinsPerMinute = idleConfig.CoinsPerMinute or 0
	if coinsPerMinute <= 0 then
		return 0
	end

	local minutes = math.floor((pendingIdleCoins or 0) / coinsPerMinute)
	local maxMinutes = tonumber(idleConfig.MaxMinutes)
	if maxMinutes and maxMinutes > 0 and minutes > maxMinutes then
		minutes = maxMinutes
	end

	return minutes
end

local function GetVipDisplayAmount(baseCoins)
	local baseAmount = math.max(0, math.floor(tonumber(baseCoins) or 0))
	if player:GetAttribute("VipPurchased") == true then
		local total = math.ceil(baseAmount * 1.5)
		return total, true
	end
	return baseAmount, false
end

local function UpdateIdleEarningUI()
	if not idleEarningBg then
		return
	end

	local minutes = GetPendingIdleMinutes()
	if idleTimeLabel and idleTimeLabel:IsA("TextLabel") then
		idleTimeLabel.Text = FormatIdleTime(minutes)
	end
	if idleTimeTitle and idleTimeTitle:IsA("TextLabel") then
		local idleConfig = GetIdleConfigForPlayer()
		local maxHours = tonumber(idleConfig.MaxHours) or 0
		idleTimeTitle.Text = string.format("MAX %dH", maxHours)
	end

	local baseCoins = math.max(0, math.floor(pendingIdleCoins or 0))
	if idleClaimCash and idleClaimCash:IsA("TextLabel") then
		local displayAmount, isVip = GetVipDisplayAmount(baseCoins)
		if isVip then
			idleClaimCash.Text = FormatHelper.FormatCoins(displayAmount) .. "(Vip+50%)"
		else
			idleClaimCash.Text = FormatHelper.FormatCoins(baseCoins)
		end
	end
	if idleClaim10Cash and idleClaim10Cash:IsA("TextLabel") then
		idleClaim10Cash.Text = FormatHelper.FormatCoins(baseCoins * 10)
	end
end

local function InitializeIdleEarningUI()
	if idleEarningGui and idleEarningBg then
		return true
	end

	idleEarningGui = playerGui:FindFirstChild("IdleEarningGui") or playerGui:WaitForChild("IdleEarningGui", 5)
	if not idleEarningGui then
		return false
	end

	idleEarningBg = idleEarningGui:FindFirstChild("Bg")
	if not idleEarningBg then
		warn("[IdleCoinController] 未找到 IdleEarningGui.Bg")
		return false
	end

	local title = idleEarningBg:FindFirstChild("Title")
	if title then
		idleCloseButton = title:FindFirstChild("CloseButton")
	end

	local currentTime = idleEarningBg:FindFirstChild("CurrentTime")
	if currentTime then
		idleTimeLabel = currentTime:FindFirstChild("Time")
		idleTimeTitle = currentTime:FindFirstChild("Title")
	end

	idleClaimButton = idleEarningBg:FindFirstChild("Claim")
	if idleClaimButton then
		idleClaimCash = idleClaimButton:FindFirstChild("CashNum")
	end

	idleClaim10Button = idleEarningBg:FindFirstChild("Claim10")
	if idleClaim10Button then
		idleClaim10Cash = idleClaim10Button:FindFirstChild("CashNum")
	end

	idleScale = idleEarningBg:FindFirstChildOfClass("UIScale")
	if not idleScale then
		idleScale = Instance.new("UIScale")
		idleScale.Parent = idleEarningBg
	end
	idleScale.Scale = 1

	return true
end

local function ShowIdleEarningUI()
	if not InitializeIdleEarningUI() then
		return
	end

	UpdateIdleEarningUI()

	if idleEarningBg.Visible then
		return
	end

	idleUiToken = idleUiToken + 1
	local token = idleUiToken

	if idleUiTween then
		idleUiTween:Cancel()
	end

	idleScale.Scale = 0.8
	idleEarningBg.Visible = true
	idleUiTween = TweenService:Create(
		idleScale,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1}
	)
	idleUiTween:Play()

	idleUiTween.Completed:Connect(function()
		if token ~= idleUiToken then
			return
		end
		idleUiTween = nil
	end)
end

local function HideIdleEarningUI()
	if not idleEarningBg or not idleEarningBg.Visible then
		return
	end

	if idleUiTween then
		idleUiTween:Cancel()
		idleUiTween = nil
	end

	if idleScale then
		idleScale.Scale = 1
	end
	idleEarningBg.Visible = false
end

local function StartClaim10Gradient()
	if not idleClaim10Button then
		return
	end

	local gradient = idleClaim10Button:FindFirstChildOfClass("UIGradient")
	if not gradient then
		return
	end

	if gradientTween then
		gradientTween:Cancel()
	end

	gradient.Offset = Vector2.new(-1, 0)
	gradientTween = TweenService:Create(
		gradient,
		TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 0),
		{Offset = Vector2.new(1, 0)}
	)
	gradientTween:Play()
end

local function ApplyPromptMode(prompt)
	if not prompt then
		return
	end

	prompt.ActionText = "Click"
	if promptOpensPopup then
		prompt.HoldDuration = 0
	else
		prompt.HoldDuration = GameConfig.IdleCoin.ProximityHoldDuration
	end
end

local function BindIdleEarningUI()
	if idleUiBound then
		return
	end

	if not InitializeIdleEarningUI() then
		return
	end

	idleUiBound = true

	if LoadButtonEffectHelper() and ButtonEffectHelper then
		if idleCloseButton then
			ButtonEffectHelper.AddClickEffect(idleCloseButton)
		end
		if idleClaimButton then
			ButtonEffectHelper.AddClickEffect(idleClaimButton)
		end
		if idleClaim10Button then
			ButtonEffectHelper.AddClickEffect(idleClaim10Button)
		end
	end

	if idleCloseButton then
		idleCloseButton.MouseButton1Click:Connect(function()
			promptOpensPopup = true
			ApplyPromptMode(currentPrompt)
			HideIdleEarningUI()
		end)
	end

	if idleClaimButton then
		idleClaimButton.MouseButton1Click:Connect(function()
			if pendingIdleCoins > 0 then
				OnCollectCoins()
			end
			HideIdleEarningUI()
		end)
	end

	if idleClaim10Button then
		idleClaim10Button.MouseButton1Click:Connect(function()
			if pendingIdleCoins <= 0 then
				return
			end
			if claim10InProgress then
				return
			end

			claim10InProgress = true
			local success, err = pcall(function()
				MarketplaceService:PromptProductPurchase(player, IDLE_COIN_PRODUCT_ID)
			end)
			if not success then
				claim10InProgress = false
				warn("[IdleCoinController] PromptProductPurchase失败:", err)
			end
		end)
	end

	StartClaim10Gradient()
end

local function BindPrompt(prompt)
	if not prompt or prompt.Name ~= "IdleCoinPrompt" then
		return
	end

	currentPrompt = prompt
	ApplyPromptMode(prompt)

	if promptConnections[prompt] then
		return
	end

	promptConnections[prompt] = prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer ~= player then
			return
		end

		if promptOpensPopup then
			BindIdleEarningUI()
			ShowIdleEarningUI()
			return
		end

		OnCollectCoins()
	end)
end

--[[
获取玩家基地ID（带等待机制）
@param waitForAttribute boolean - 是否等待属性被设置
@return number|nil - 基地ID
]]
local function HasValidPrompt()
	return currentPrompt and currentPrompt.Parent ~= nil
end

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
		return deepPart
	end

	-- 回退3：使用Mail下的第一个BasePart（如IdleEarnings）
	for _, child in ipairs(mailModel:GetChildren()) do
		if child:IsA("BasePart") then
			mailModel.PrimaryPart = child
			return child
		end
	end

	return nil
end

--[[
🔥V2.6.1修复：ProximityPrompt已改为由服务端创建，客户端不再创建
此函数保留用于调试，但不再被调用
]]
local function CreateProximityPrompt_DEPRECATED(parent)
	-- 检查是否已存在
	local existingPrompt = parent:FindFirstChild("IdleCoinPrompt")
	if existingPrompt then
		return existingPrompt
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IdleCoinPrompt"
	prompt.ActionText = "Click"
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
OnCollectCoins = function()
	if not InitializeEvents() then
		return
	end

	local collectEvent = IdleCoinEvents:FindFirstChild("CollectIdleCoins")
	if collectEvent then
		collectEvent:FireServer()
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
	pendingIdleCoins = math.max(0, tonumber(coins) or 0)

	if InitializeIdleEarningUI() then
		UpdateIdleEarningUI()
		BindIdleEarningUI()

		if pendingIdleCoins <= 0 and idleEarningBg and idleEarningBg.Visible then
			HideIdleEarningUI()
		end
	end

	if not hasReceivedInitialSync then
		hasReceivedInitialSync = true
		if not autoPopupShown and pendingIdleCoins >= 1 then
			autoPopupShown = true
			BindIdleEarningUI()
			ShowIdleEarningUI()
		end
	end
end

--[[
🔥V2.6.1修复：连接服务端创建的ProximityPrompt事件
不再由客户端创建ProximityPrompt，而是等待服务端创建后连接事件
@param waitForHomeId boolean - 是否等待HomeId被设置（首次初始化时为true，重生时为false）
]]
local function SetupMailPromptConnection(waitForHomeId)
	if mailPromptResolveInProgress then
		return
	end
	if HasValidPrompt() then
		mailPromptReady = true
		return
	end
	mailPromptResolveInProgress = true
	-- 根据参数决定是否等待HomeSlot属性被设置
	local mailModel = GetMailModel(waitForHomeId)
	if not mailModel then
		warn("[IdleCoinController] 未找到Mail模型")
		mailPromptResolveInProgress = false
		return
	end

	-- 使用Mail模型的PrimaryPart作为交互点（带回退机制）
	local primaryPart = GetMailPrimaryPart(mailModel)
	if not primaryPart then
		warn("[IdleCoinController] Mail模型未设置PrimaryPart，且未找到名为'PrimaryPart'的子Part")
		mailPromptResolveInProgress = false
		return
	end

	-- 🔥等待服务端创建的ProximityPrompt（最多等待10秒）
	local prompt = primaryPart:WaitForChild("IdleCoinPrompt", 10)
	if not prompt then
		warn("[IdleCoinController] 服务端未创建ProximityPrompt，等待超时")
		mailPromptResolveInProgress = false
		return
	end

	currentPrompt = prompt

	BindPrompt(prompt)
	mailPromptReady = true
	mailPromptResolveInProgress = false
end

-- ==================== 初始化 ====================

local function Initialize()

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

	-- 🔥V2.6.1修复：连接服务端创建的ProximityPrompt事件（首次初始化，需要等待HomeId）
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt and prompt.Name == "IdleCoinPrompt" then
			BindPrompt(prompt)
		end
	end)

	-- 监听购买弹窗关闭（成功或取消都重置状态）
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
		if userId == player.UserId and productId == IDLE_COIN_PRODUCT_ID then
			claim10InProgress = false
		end
	end)

	-- 尝试初始化挂机金币弹框UI
	task.spawn(function()
		if InitializeIdleEarningUI() then
			BindIdleEarningUI()
			UpdateIdleEarningUI()
		end
	end)

	task.spawn(function()
		SetupMailPromptConnection(true)
	end)

	-- HomeSlot就绪后尝试绑定Mail Prompt
	player:GetAttributeChangedSignal("HomeSlot"):Connect(function()
		local homeSlot = player:GetAttribute("HomeSlot")
		if homeSlot and type(homeSlot) == "number" and homeSlot > 0 then
			cachedHomeId = homeSlot
			task.spawn(function()
				SetupMailPromptConnection(false)
			end)
		end
	end)

	-- 🔥V2.6.1修复：角色重生时重新连接事件（不需要等待HomeId，因为已经分配过了）

	player.CharacterAdded:Connect(function()
		task.wait(1)
		SetupMailPromptConnection(false)
	end)

	player:GetAttributeChangedSignal("VipPurchased"):Connect(function()
		if InitializeIdleEarningUI() then
			UpdateIdleEarningUI()
		end
	end)
end

-- 启动初始化
Initialize()
