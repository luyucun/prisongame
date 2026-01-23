--[[
脚本名称: LimitPrisonerDisplay
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/LimitPrisonerDisplay
版本: V6.0
职责: 限时囚犯界面显示、交互与倒计时
]]

local LimitPrisonerDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local FormatHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FormatHelper"))

local ButtonEffectHelper = nil

-- 事件引用
local limitEvents = nil
local requestDataEvent = nil
local dataEvent = nil
local purchaseGoldEvent = nil
local purchaseRobuxEvent = nil
local redeemEvent = nil
local purchaseResultEvent = nil
local redeemResultEvent = nil

-- UI引用
local limitGui = nil
local storeBg = nil
local closeButton = nil
local titleLabel = nil
local itemCardTemplate = nil
local itemContainer = nil
local buyButtonFrame = nil
local goldBuy = nil
local robuxBuy = nil
local freeButton = nil
local progressNum = nil
local redeemButton = nil
local claimedLabel = nil

-- 弹框UI
local claimTipsGui = nil
local claimSuccess = nil
local claimBg = nil
local itemListFrame = nil
local itemTemplate = nil
local lightBg = nil
local lightImage = nil

-- 状态缓存
local cachedData = nil
local currentCard = nil
local currentUnitId = ""
local defaultRobuxPos = nil
local countdownConnection = nil
local countdownAccumulator = 0
local nextRefreshTime = 0
local serverTimeOffset = 0
local refreshRequested = false
local purchaseLock = false

local lightRotateConnection = nil
local popupToken = 0
local popupVisible = false
local popupAllowClose = false
local popupInputConnection = nil
local restorePanelAfterPopup = false

local POPUP_BG_OFFSET = 0.08
local POPUP_TWEEN_DURATION = 0.3
local POPUP_ALLOW_CLOSE_SECONDS = 1
local LIGHT_ROTATE_SPEED = 60

local buttonsBound = false
local dataBound = false
local promptBound = false
local visibleBound = false

-- ==================== 工具函数 ====================

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

	warn("[LimitPrisonerDisplay] ButtonEffectHelper加载失败:", result)
	return false
end

local function FormatCoins(amount)
	return FormatHelper.FormatCoinsShort(amount or 0, true)
end

local function GetQualityColor(quality)
	local colors = (GameConfig.UI and GameConfig.UI.QualityColors) or {}
	return colors[quality] or colors.Common or Color3.fromRGB(225, 225, 225)
end

local function FormatRefreshText(remainingSeconds)
	local remaining = math.max(0, math.floor(tonumber(remainingSeconds) or 0))
	if remaining < 60 then
		local minutes = math.floor(remaining / 60)
		local seconds = remaining % 60
		return string.format(
			"<font color=\"#FFFFFF\">Refreshes In:</font><font color=\"#00FF00\">%02d:%02d</font>",
			minutes,
			seconds
		)
	end

	local hours = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)
	return string.format(
		"<font color=\"#FFFFFF\">Refreshes In:</font><font color=\"#00FF00\">%02d:%02d</font>",
		hours,
		minutes
	)
end

local function GetPlayerHomeModel()
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local homeFolder = workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	return homeFolder:FindFirstChild("PlayerHome" .. tostring(homeSlot))
end

local function IsPromptFromPlayerHome(prompt)
	if not prompt then
		return false
	end

	local homeModel = GetPlayerHomeModel()
	if not homeModel then
		return true
	end

	return prompt:IsDescendantOf(homeModel)
end

-- ==================== UI初始化 ====================

local function InitializeEvents()
	if limitEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[LimitPrisonerDisplay] Events文件夹未找到")
		return false
	end

	limitEvents = eventsFolder:WaitForChild("LimitPrisonerEvents", 10)
	if not limitEvents then
		warn("[LimitPrisonerDisplay] LimitPrisonerEvents未找到")
		return false
	end

	requestDataEvent = limitEvents:WaitForChild("RequestLimitPrisonerData", 5)
	dataEvent = limitEvents:WaitForChild("LimitPrisonerData", 5)
	purchaseGoldEvent = limitEvents:WaitForChild("PurchaseLimitPrisonerGold", 5)
	purchaseRobuxEvent = limitEvents:WaitForChild("PurchaseLimitPrisonerRobux", 5)
	redeemEvent = limitEvents:WaitForChild("RedeemLimitPrisoner", 5)
	purchaseResultEvent = limitEvents:WaitForChild("LimitPrisonerPurchaseResult", 5)
	redeemResultEvent = limitEvents:WaitForChild("LimitPrisonerRedeemResult", 5)

	return true
end

local function InitializeClaimPopup()
	claimTipsGui = SafeWaitForChild(playerGui, "ClaimTipsGui", 5)
	claimSuccess = claimTipsGui and claimTipsGui:FindFirstChild("ClaimSuccessful")
	claimBg = claimSuccess and claimSuccess:FindFirstChild("Bg")
	itemListFrame = claimBg and claimBg:FindFirstChild("ItemListFrame")
	itemTemplate = itemListFrame and itemListFrame:FindFirstChild("ItemTemplate")
	lightBg = claimTipsGui and claimTipsGui:FindFirstChild("LightBg")
	lightImage = lightBg and lightBg:FindFirstChild("Light")

	if itemTemplate then
		itemTemplate.Visible = false
	end
	if claimSuccess then
		claimSuccess.Visible = false
	end
	if lightBg then
		lightBg.Visible = false
	end
end

local function InitializeUI()
	local storeValid = storeBg and storeBg:IsDescendantOf(playerGui)
	if storeValid then
		return true
	end

	limitGui = SafeWaitForChild(playerGui, "LimitPrisoner", 5)
	storeBg = limitGui and limitGui:FindFirstChild("StoreBg")
	if not storeBg then
		return false
	end

	titleLabel = storeBg:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.RichText = true
	end

	closeButton = (titleLabel and titleLabel:FindFirstChild("CloseButton")) or storeBg:FindFirstChild("CloseButton")

	itemCardTemplate = storeBg:FindFirstChild("ItemCardTemplate", true)
	itemContainer = itemCardTemplate and itemCardTemplate.Parent or storeBg

	if itemCardTemplate then
		itemCardTemplate.Visible = false
	end

	buyButtonFrame = storeBg:FindFirstChild("BuyButtonFrame", true)
	goldBuy = buyButtonFrame and buyButtonFrame:FindFirstChild("GoldBuy")
	robuxBuy = buyButtonFrame and buyButtonFrame:FindFirstChild("RobuxBuy")
	if robuxBuy and not defaultRobuxPos then
		defaultRobuxPos = robuxBuy.Position
	end

	freeButton = storeBg:FindFirstChild("FreeButton", true)
	progressNum = freeButton and freeButton:FindFirstChild("ProgressNum")
	redeemButton = freeButton and freeButton:FindFirstChild("Redeem")
	claimedLabel = freeButton and freeButton:FindFirstChild("Claimed")

	if claimedLabel then
		claimedLabel.Visible = false
	end

	InitializeClaimPopup()
	return true
end

-- ==================== 卡片渲染 ====================

local function CreateOrGetCard(unitId)
	if currentCard and currentCard.Parent then
		return currentCard
	end

	if not itemCardTemplate or not itemContainer then
		return nil
	end

	local card = itemCardTemplate:Clone()
	card.Name = "ItemCard_" .. unitId
	card.Visible = true
	card.Parent = itemContainer
	currentCard = card
	return card
end

local function UpdateCardData(data)
	if not data or not data.UnitId or data.UnitId == "" then
		if currentCard then
			currentCard.Visible = false
		end
		if buyButtonFrame then
			buyButtonFrame.Visible = false
		end
		return
	end

	local card = CreateOrGetCard(data.UnitId)
	if not card then
		return
	end

	currentUnitId = data.UnitId
	card.Visible = true

	if buyButtonFrame then
		buyButtonFrame.Visible = true
		if buyButtonFrame:IsA("GuiObject") and card:IsA("GuiObject") then
			buyButtonFrame.LayoutOrder = card.LayoutOrder + 1
		end
	end

	local unitData = UnitConfig.GetUnitById(data.UnitId)
	local level = (unitData and unitData.BaseLevel) or 1
	local atkVal = UnitConfig.CalculateAttack(data.UnitId, level)
	local hpVal = UnitConfig.CalculateHealth(data.UnitId, level)

	local iconBg = card:FindFirstChild("IconBg")
	if iconBg then
		local icon = iconBg:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = UnitConfig.GetIcon(data.UnitId)
		end
	end

	local atk = card:FindFirstChild("ATK")
	if atk and atk:IsA("TextLabel") then
		atk.Text = tostring(atkVal)
	end

	local hp = card:FindFirstChild("HP")
	if hp and hp:IsA("TextLabel") then
		hp.Text = tostring(hpVal)
	end

	local levelLabel = card:FindFirstChild("Level")
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = "Lv." .. tostring(level)
	end

	local nameLabel = card:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = unitData and unitData.Name or data.UnitId
	end

	local numberLabel = card:FindFirstChild("Number")
	if numberLabel and numberLabel:IsA("TextLabel") then
		numberLabel.Text = "x1"
		numberLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	local priceLabel = card:FindFirstChild("Price")
	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = FormatCoins(data.GoldPrice or 0)
	end

	local qualityLabel = card:FindFirstChild("Quality")
	if qualityLabel and qualityLabel:IsA("TextLabel") then
		local quality = UnitConfig.GetQuality(data.UnitId) or "Common"
		qualityLabel.Text = quality
		qualityLabel.TextColor3 = GetQualityColor(quality)
	end

	local rangeLabel = card:FindFirstChild("Range")
	if rangeLabel and rangeLabel:IsA("TextLabel") then
		local isRanged = UnitConfig.IsRangedUnit(data.UnitId)
		rangeLabel.Text = isRanged and UnitConfig.UnitType.RANGED or UnitConfig.UnitType.MELEE
		rangeLabel.TextColor3 = isRanged and Color3.fromRGB(170, 170, 255) or Color3.fromRGB(255, 255, 127)
	end
end

local function UpdateBuyButtons(data)
	if not buyButtonFrame then
		return
	end

	if not data or not data.UnitId or data.UnitId == "" then
		buyButtonFrame.Visible = false
		return
	end

	if goldBuy then
		local priceLabel = goldBuy:FindFirstChild("Price")
		if priceLabel and priceLabel:IsA("TextLabel") then
			priceLabel.Text = FormatCoins(data.GoldPrice or 0)
		end
	end

	if robuxBuy then
		local priceLabel = robuxBuy:FindFirstChild("Price")
		if priceLabel and priceLabel:IsA("TextLabel") then
			priceLabel.Text = "R$ " .. tostring(data.RobuxPrice or 0)
		end
		robuxBuy.Visible = (tonumber(data.RobuxPrice) or 0) > 0
	end

	if data.GoldPurchased then
		if goldBuy then
			goldBuy.Visible = false
		end
		if robuxBuy then
			robuxBuy.Position = UDim2.new(0.5, 0, robuxBuy.Position.Y.Scale, robuxBuy.Position.Y.Offset)
		end
	else
		if goldBuy then
			goldBuy.Visible = true
		end
		if robuxBuy and defaultRobuxPos then
			robuxBuy.Position = defaultRobuxPos
		end
	end
end

local function UpdateRedeemState(data)
	if not freeButton then
		return
	end

	local redeemed = data and data.Redeemed == true
	if redeemed then
		if redeemButton then
			redeemButton.Visible = false
		end
		if claimedLabel then
			claimedLabel.Visible = true
		end
	else
		if redeemButton then
			redeemButton.Visible = true
		end
		if claimedLabel then
			claimedLabel.Visible = false
		end
	end

	local current = tonumber(data and data.HandcuffCount) or 0
	local required = tonumber(data and data.HandcuffCost) or 0
	if progressNum and progressNum:IsA("TextLabel") then
		progressNum.RichText = true
		local color = current < required and "#FF3333" or "#FFFFFF"
		progressNum.Text = string.format("<font color=\"%s\">%d</font>/<font color=\"#FFFFFF\">%d</font>", color, current, required)
	end
end

local function UpdateCountdownLabel()
	if not titleLabel or not titleLabel:IsA("TextLabel") then
		return
	end

	local now = os.time() + serverTimeOffset
	local remaining = math.max(0, (tonumber(nextRefreshTime) or 0) - now)
	titleLabel.Text = FormatRefreshText(remaining)

	if remaining <= 0 and not refreshRequested then
		refreshRequested = true
		if requestDataEvent then
			requestDataEvent:FireServer()
		end
	elseif remaining > 0 then
		refreshRequested = false
	end
end

local function StartCountdown()
	if countdownConnection then
		return
	end

	countdownAccumulator = 0
	UpdateCountdownLabel()
	countdownConnection = RunService.Heartbeat:Connect(function(dt)
		countdownAccumulator = countdownAccumulator + dt
		if countdownAccumulator >= 1 then
			countdownAccumulator = 0
			UpdateCountdownLabel()
		end
	end)
end

local function StopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

-- ==================== 弹框表现 ====================

local function StopLightRotation()
	if lightRotateConnection then
		lightRotateConnection:Disconnect()
		lightRotateConnection = nil
	end
end

local function StartLightRotation()
	StopLightRotation()
	if not lightImage then
		return
	end

	lightImage.Rotation = 0
	lightRotateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if lightImage then
			lightImage.Rotation = (lightImage.Rotation + (LIGHT_ROTATE_SPEED * deltaTime)) % 360
		end
	end)
end

local function ClearPopupItems()
	if not itemListFrame then
		return
	end

	for _, child in ipairs(itemListFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name == "ItemReward" then
			child:Destroy()
		end
	end
end

local function AnimatePopup()
	if not claimBg then
		return
	end

	local startPos = claimBg.Position + UDim2.new(0, 0, POPUP_BG_OFFSET, 0)
	claimBg.Position = startPos
	claimBg.Visible = true

	local tween = TweenService:Create(
		claimBg,
		TweenInfo.new(POPUP_TWEEN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = startPos - UDim2.new(0, 0, POPUP_BG_OFFSET, 0)}
	)
	tween:Play()
end

local function CloseClaimPopup()
	popupVisible = false
	popupAllowClose = false

	if claimSuccess then
		claimSuccess.Visible = false
	end
	if lightBg then
		lightBg.Visible = false
	end
	if restorePanelAfterPopup and storeBg then
		storeBg.Visible = true
	end
	restorePanelAfterPopup = false

	if popupInputConnection then
		popupInputConnection:Disconnect()
		popupInputConnection = nil
	end

	StopLightRotation()
	ClearPopupItems()
end

local function BindPopupInput(token)
	if popupInputConnection then
		popupInputConnection:Disconnect()
		popupInputConnection = nil
	end

	popupInputConnection = UserInputService.InputBegan:Connect(function(input)
		if not popupVisible or not popupAllowClose or popupToken ~= token then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			CloseClaimPopup()
		end
	end)
end

local function ShowClaimPopup(rewardInfo)
	if not claimTipsGui or not claimSuccess or not claimBg then
		return
	end

	if popupVisible then
		restorePanelAfterPopup = false
		CloseClaimPopup()
	end

	restorePanelAfterPopup = storeBg and storeBg.Visible == true
	if restorePanelAfterPopup and storeBg then
		storeBg.Visible = false
	end

	ClearPopupItems()

	if itemTemplate and rewardInfo then
		local item = itemTemplate:Clone()
		item.Visible = true
		item.Name = "ItemReward"

		local icon = item:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			if rewardInfo.Type == "Unit" then
				icon.Image = UnitConfig.GetIcon(rewardInfo.UnitId)
			end
		end

		local numberLabel = item:FindFirstChild("Number")
		if numberLabel and numberLabel:IsA("TextLabel") then
			numberLabel.Text = tostring(rewardInfo.Count or 1)
		end

		item.Parent = itemListFrame
	end

	claimSuccess.Visible = true
	if lightBg then
		lightBg.Visible = true
	end

	StartLightRotation()
	AnimatePopup()

	popupToken = popupToken + 1
	local token = popupToken
	popupVisible = true
	popupAllowClose = false
	BindPopupInput(token)

	task.delay(POPUP_ALLOW_CLOSE_SECONDS, function()
		if popupToken ~= token then
			return
		end
		popupAllowClose = true
	end)
end

-- ==================== 事件处理 ====================

local function OnLimitPrisonerData(data)
	if type(data) ~= "table" then
		return
	end

	cachedData = data
	currentUnitId = data.UnitId or ""
	nextRefreshTime = tonumber(data.NextRefreshTime) or 0
	if type(data.ServerTime) == "number" then
		serverTimeOffset = data.ServerTime - os.time()
	end

	UpdateCardData(data)
	UpdateBuyButtons(data)
	UpdateRedeemState(data)

	if storeBg and storeBg.Visible then
		UpdateCountdownLabel()
	end
end

local function OnPurchaseResult(success, message, purchaseType, unitId)
	purchaseLock = false
	local tipsSystem = _G.TipsSystem
	if success then
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Purchase Successful!")
		end
		if unitId and unitId ~= "" then
			ShowClaimPopup({
				Type = "Unit",
				UnitId = unitId,
				Count = 1,
			})
		end
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Purchase failed")
		end
	end
end

local function OnRedeemResult(success, message, rewardInfo)
	purchaseLock = false
	local tipsSystem = _G.TipsSystem
	if success then
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Redeem Successful!")
		end
		ShowClaimPopup(rewardInfo)
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Redeem failed")
		end
	end
end

local function BindButtons()
	if buttonsBound then
		return
	end

	LoadButtonEffectHelper()

	if closeButton and (closeButton:IsA("TextButton") or closeButton:IsA("ImageButton")) then
		if ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(closeButton)
		end
		closeButton.MouseButton1Click:Connect(function()
			if storeBg then
				storeBg.Visible = false
			end
		end)
	end

	if goldBuy and (goldBuy:IsA("TextButton") or goldBuy:IsA("ImageButton")) then
		if ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(goldBuy)
		end
		goldBuy.MouseButton1Click:Connect(function()
			if purchaseLock or not purchaseGoldEvent then
				return
			end
			if not cachedData or cachedData.UnitId == "" then
				return
			end
			purchaseLock = true
			purchaseGoldEvent:FireServer()
		end)
	end

	if robuxBuy and (robuxBuy:IsA("TextButton") or robuxBuy:IsA("ImageButton")) then
		if ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(robuxBuy)
		end
		robuxBuy.MouseButton1Click:Connect(function()
			if purchaseLock or not purchaseRobuxEvent then
				return
			end
			if not cachedData or cachedData.UnitId == "" then
				return
			end
			purchaseLock = true
			purchaseRobuxEvent:FireServer()
			task.delay(0.5, function()
				purchaseLock = false
			end)
		end)
	end

	if redeemButton and (redeemButton:IsA("TextButton") or redeemButton:IsA("ImageButton")) then
		if ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(redeemButton)
		end
		redeemButton.MouseButton1Click:Connect(function()
			if purchaseLock or not redeemEvent then
				return
			end
			if not cachedData or cachedData.UnitId == "" then
				return
			end
			purchaseLock = true
			redeemEvent:FireServer()
		end)
	end

	buttonsBound = true
end

local function BindData()
	if dataBound then
		return
	end

	if dataEvent then
		dataEvent.OnClientEvent:Connect(OnLimitPrisonerData)
	end
	if purchaseResultEvent then
		purchaseResultEvent.OnClientEvent:Connect(OnPurchaseResult)
	end
	if redeemResultEvent then
		redeemResultEvent.OnClientEvent:Connect(OnRedeemResult)
	end

	dataBound = true
end

local function BindPrompt()
	if promptBound then
		return
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if not prompt or prompt.Name ~= "LimitPrisonerPrompt" then
			return
		end
		if not IsPromptFromPlayerHome(prompt) then
			return
		end

		if storeBg then
			storeBg.Visible = true
		end

		if requestDataEvent then
			requestDataEvent:FireServer()
		end
	end)

	promptBound = true
end

local function SetupStoreVisibleListener()
	if visibleBound then
		return
	end

	if not storeBg then
		return
	end

	storeBg:GetPropertyChangedSignal("Visible"):Connect(function()
		if storeBg.Visible then
			StartCountdown()
			UpdateCountdownLabel()
		else
			StopCountdown()
		end
	end)

	if storeBg.Visible then
		StartCountdown()
	end

	visibleBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if uiReady then
		BindButtons()
		SetupStoreVisibleListener()
		if cachedData then
			UpdateCardData(cachedData)
			UpdateBuyButtons(cachedData)
			UpdateRedeemState(cachedData)
		end
	end

	if eventsReady then
		BindData()
		if requestDataEvent then
			requestDataEvent:FireServer()
		end
	end

	if eventsReady and uiReady then
		BindPrompt()
	end

	return eventsReady and uiReady
end

function LimitPrisonerDisplay.Initialize()
	if TryInitialize() then
		return
	end

	task.spawn(function()
		local attempts = 0
		while attempts < 5 and not TryInitialize() do
			attempts += 1
			task.wait(2)
		end
	end)

	playerGui.ChildAdded:Connect(function(child)
		if not child then
			return
		end
		if child.Name ~= "LimitPrisoner" and child.Name ~= "ClaimTipsGui" then
			return
		end

		task.spawn(function()
			task.wait()
			TryInitialize()
		end)
	end)
end

LimitPrisonerDisplay.Initialize()

return LimitPrisonerDisplay
