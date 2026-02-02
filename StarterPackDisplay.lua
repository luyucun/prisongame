--[[
Script Name: StarterPackDisplay
Script Type: LocalScript (Client UI)
Script Location: StarterPlayer/StarterPlayerScripts/UI/StarterPackDisplay
Version: V5.4
Responsibility: Starter pack UI, purchase flow, reward popup
]]

local StarterPackDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))

local ButtonEffectHelper = nil

-- Events
local starterPackEvents = nil
local requestDataEvent = nil
local dataEvent = nil
local purchaseEvent = nil
local purchaseResultEvent = nil

-- UI references
local mainGui = nil
local starterPackContainer = nil
local starterPackButton = nil
local starterPackLight = nil

local shopGui = nil
local shopBg = nil
local shopCloseButton = nil
local newPlayerFrame = nil
local buyButton = nil
local tabList = nil
local tabNewPlayerButton = nil

local claimTipsGui = nil
local claimSuccess = nil
local claimBg = nil
local itemListFrame = nil
local itemTemplate = nil
local lightBg = nil
local lightImage = nil
local titleLabel = nil
local defaultTitleText = nil

-- State
local cachedPurchased = nil
local purchaseLock = false
local dataBound = false
local boundButtons = {}
local shopVisibleConn = nil
local campaignEventsBound = false
local isBattleBlocked = false
local CloseShop = nil

-- Popup state
local lightRotateConnection = nil
local popupToken = 0
local popupVisible = false
local popupAllowClose = false
local popupInputConnection = nil

local POPUP_BG_OFFSET = 0.08
local POPUP_TWEEN_DURATION = 0.3
local POPUP_ALLOW_CLOSE_SECONDS = 1
local LIGHT_ROTATE_SPEED = 60
local ENTRY_LIGHT_ROTATE_SPEED = 60
local COIN_ICON = "rbxassetid://92295649647469"

-- Shop面板弹框动画配置（ShopBg）
local SHOP_OPEN_START_SCALE = 0.86
local SHOP_OPEN_OVERSHOOT_SCALE = 1.10
local SHOP_OPEN_DURATION_A = 0.18
local SHOP_OPEN_DURATION_B = 0.10
local SHOP_CLOSE_OVERSHOOT_SCALE = 1.12
local SHOP_CLOSE_END_SCALE = 0.78
local SHOP_CLOSE_DURATION_A = 0.08
local SHOP_CLOSE_DURATION_B = 0.12

local shopScale = nil
local shopOpenTweenA = nil
local shopOpenTweenB = nil
local shopCloseTweenA = nil
local shopCloseTweenB = nil
local shopAnimating = false

local starterPackLightRotateConnection = nil

-- ==================== Helpers ====================

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

	warn("[StarterPackDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function IsDescendantOfPlayerGui(instance)
	return instance ~= nil and instance:IsDescendantOf(playerGui)
end

local function EnsureShopScale()
	if not shopBg then
		return nil
	end

	if not shopScale or shopScale.Parent ~= shopBg then
		shopScale = shopBg:FindFirstChild("PopupScale")
		if not shopScale then
			shopScale = Instance.new("UIScale")
			shopScale.Name = "PopupScale"
			shopScale.Scale = 1
			shopScale.Parent = shopBg
		end
	end

	return shopScale
end

local function CancelShopTweens()
	local tweens = {shopOpenTweenA, shopOpenTweenB, shopCloseTweenA, shopCloseTweenB}
	for _, tween in ipairs(tweens) do
		if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
			tween:Cancel()
		end
	end
end

local function PlayShopOpen()
	if not shopBg then
		return false
	end

	local scale = EnsureShopScale()
	if not scale then
		shopBg.Visible = true
		return true
	end

	if shopBg.Visible and not shopAnimating then
		return true
	end

	CancelShopTweens()
	shopAnimating = true

	shopBg.Visible = true
	scale.Scale = SHOP_OPEN_START_SCALE

	shopOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = SHOP_OPEN_OVERSHOOT_SCALE}
	)
	shopOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1}
	)

	local connA
	connA = shopOpenTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			shopOpenTweenB:Play()
		end
	end)

	local connB
	connB = shopOpenTweenB.Completed:Connect(function()
		connB:Disconnect()
		shopAnimating = false
		scale.Scale = 1
	end)

	shopOpenTweenA:Play()
	return true
end

local function PlayShopClose()
	if not shopBg then
		return false
	end

	local scale = EnsureShopScale()
	if not scale then
		shopBg.Visible = false
		return true
	end

	if not shopBg.Visible and not shopAnimating then
		return true
	end

	CancelShopTweens()
	shopAnimating = true

	shopCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = SHOP_CLOSE_OVERSHOOT_SCALE}
	)
	shopCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = SHOP_CLOSE_END_SCALE}
	)

	local connA
	connA = shopCloseTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			shopCloseTweenB:Play()
		end
	end)

	local connB
	connB = shopCloseTweenB.Completed:Connect(function()
		connB:Disconnect()
		shopBg.Visible = false
		scale.Scale = 1
		shopAnimating = false
	end)

	shopCloseTweenA:Play()
	return true
end

local function GetCompletedChapters()
	local completed = player:GetAttribute("CompletedChapters")
	if type(completed) == "number" then
		return completed
	end
	return 0
end

local function IsShopUnlocked()
	return true
end

-- ==================== Initialization ====================

local function InitializeEvents()
	if starterPackEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[StarterPackDisplay] Events folder not found")
		return false
	end

	starterPackEvents = eventsFolder:WaitForChild("StarterPackEvents", 10)
	if not starterPackEvents then
		warn("[StarterPackDisplay] StarterPackEvents not found")
		return false
	end

	requestDataEvent = starterPackEvents:WaitForChild("RequestStarterPackData", 5)
	dataEvent = starterPackEvents:WaitForChild("StarterPackData", 5)
	purchaseEvent = starterPackEvents:WaitForChild("PurchaseStarterPack", 5)
	purchaseResultEvent = starterPackEvents:WaitForChild("PurchaseStarterPackResult", 5)

	if not (requestDataEvent and dataEvent and purchaseEvent and purchaseResultEvent) then
		warn("[StarterPackDisplay] StarterPack events missing")
		return false
	end

	return true
end

local function InitializeUI()
	local mainGuiValid = IsDescendantOfPlayerGui(starterPackContainer)
	local shopValid = IsDescendantOfPlayerGui(shopBg)
	local popupValid = IsDescendantOfPlayerGui(claimSuccess)

	if mainGuiValid and shopValid and popupValid then
		return true
	end

	mainGui = SafeWaitForChild(playerGui, "MainGui", 5)
	starterPackContainer = mainGui and mainGui:FindFirstChild("StarterPack")
	starterPackButton = starterPackContainer
	if starterPackButton and not (starterPackButton:IsA("TextButton") or starterPackButton:IsA("ImageButton")) then
		local innerButton = starterPackButton:FindFirstChild("Button")
		if innerButton and (innerButton:IsA("TextButton") or innerButton:IsA("ImageButton")) then
			starterPackButton = innerButton
		end
	end
	starterPackLight = starterPackContainer and starterPackContainer:FindFirstChild("Light", true)

	shopGui = SafeWaitForChild(playerGui, "Shop", 5)
	shopBg = shopGui and shopGui:FindFirstChild("ShopBg")
	if shopBg then
		local title = shopBg:FindFirstChild("Title")
		shopCloseButton = title and title:FindFirstChild("CloseButton")
		local scale = EnsureShopScale()
		if scale then
			scale.Scale = 1
		end
	end

	newPlayerFrame = nil
	buyButton = nil
	tabList = nil
	tabNewPlayerButton = nil

	if shopBg then
		newPlayerFrame = shopBg:FindFirstChild("NewPlayer")
		local scrollingFrame = shopBg:FindFirstChild("ScrollingFrame")
		if not newPlayerFrame and scrollingFrame then
			newPlayerFrame = scrollingFrame:FindFirstChild("NewPlayer")
		end
		buyButton = newPlayerFrame and newPlayerFrame:FindFirstChild("BuyButton")
		if buyButton and not (buyButton:IsA("TextButton") or buyButton:IsA("ImageButton")) then
			local innerBuy = buyButton:FindFirstChild("Button")
				or buyButton:FindFirstChildWhichIsA("TextButton")
				or buyButton:FindFirstChildWhichIsA("ImageButton")
			if innerBuy then
				buyButton = innerBuy
			end
		end

		tabList = shopBg:FindFirstChild("TabList")
		tabNewPlayerButton = tabList and tabList:FindFirstChild("NewPlayer")
	end

	claimTipsGui = SafeWaitForChild(playerGui, "ClaimTipsGui", 5)
	claimSuccess = claimTipsGui and claimTipsGui:FindFirstChild("ClaimSuccessful")
	claimBg = claimSuccess and claimSuccess:FindFirstChild("Bg")
	itemListFrame = claimBg and claimBg:FindFirstChild("ItemListFrame")
	itemTemplate = itemListFrame and itemListFrame:FindFirstChild("ItemTemplate")
	lightBg = claimTipsGui and claimTipsGui:FindFirstChild("LightBg")
	lightImage = lightBg and lightBg:FindFirstChild("Light")
	titleLabel = claimSuccess and claimSuccess:FindFirstChild("Title")
	if titleLabel and not titleLabel:IsA("TextLabel") then
		local innerTitle = titleLabel:FindFirstChild("Text") or titleLabel:FindFirstChildWhichIsA("TextLabel")
		if innerTitle then
			titleLabel = innerTitle
		end
	end
	if titleLabel and titleLabel:IsA("TextLabel") then
		defaultTitleText = defaultTitleText or titleLabel.Text
	end

	if itemTemplate then
		itemTemplate.Visible = false
	end
	if claimSuccess then
		claimSuccess.Visible = false
	end
	if lightBg then
		lightBg.Visible = false
	end

	return mainGui ~= nil and shopBg ~= nil
end

-- ==================== UI State ====================

local function UpdateVisibility()
	local purchased = player:GetAttribute("StarterPackPurchased") == true
	if cachedPurchased ~= nil then
		purchased = cachedPurchased
	end
	local entryVisible = (not purchased) and IsShopUnlocked() and (not isBattleBlocked)

	if starterPackContainer then
		starterPackContainer.Visible = entryVisible
	end
	if starterPackButton and starterPackButton ~= starterPackContainer then
		starterPackButton.Visible = entryVisible
	end

	if newPlayerFrame then
		newPlayerFrame.Visible = not purchased
	end

	if tabNewPlayerButton then
		tabNewPlayerButton.Visible = not purchased
	end

	if purchased and shopBg and shopBg.Visible then
		if newPlayerFrame then
			newPlayerFrame.Visible = false
		end
		if tabNewPlayerButton then
			tabNewPlayerButton.Visible = false
		end
	end

	if entryVisible then
		if starterPackLight and not starterPackLightRotateConnection then
			starterPackLight.Rotation = 0
			starterPackLightRotateConnection = RunService.RenderStepped:Connect(function(deltaTime)
				if starterPackLight then
					starterPackLight.Rotation = (starterPackLight.Rotation + (ENTRY_LIGHT_ROTATE_SPEED * deltaTime)) % 360
				end
			end)
		end
	else
		if starterPackLightRotateConnection then
			starterPackLightRotateConnection:Disconnect()
			starterPackLightRotateConnection = nil
		end
		if starterPackLight then
			starterPackLight.Rotation = 0
		end
	end
end

-- ==================== Popup ====================

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
		if child:IsA("GuiObject") and child ~= itemTemplate then
			child:Destroy()
		end
	end
end

local function AnimatePopup()
	if not claimBg or not claimBg:IsA("GuiObject") then
		return
	end

	local originalPos = claimBg.Position
	claimBg.Position = UDim2.new(
		originalPos.X.Scale,
		originalPos.X.Offset,
		originalPos.Y.Scale + POPUP_BG_OFFSET,
		originalPos.Y.Offset
	)

	TweenService:Create(
		claimBg,
		TweenInfo.new(POPUP_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = originalPos }
	):Play()
end

local function RestoreTitle()
	if titleLabel and titleLabel:IsA("TextLabel") and defaultTitleText then
		titleLabel.Text = defaultTitleText
	end
end

local function ClosePopup()
	if not popupVisible then
		return
	end

	popupVisible = false
	popupAllowClose = false

	if claimSuccess then
		claimSuccess.Visible = false
	end
	if lightBg then
		lightBg.Visible = false
	end

	if popupInputConnection then
		popupInputConnection:Disconnect()
		popupInputConnection = nil
	end

	StopLightRotation()
	ClearPopupItems()
	RestoreTitle()
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
			ClosePopup()
		end
	end)
end

local function ApplyTitle(text)
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = text or defaultTitleText or titleLabel.Text
	end
end

local function ResolveIcon(item)
	if item.Type == "Unit" then
		return UnitConfig.GetIcon(item.UnitId)
	end
	if item.Type == "Skill" then
		return SkillConfig.GetSkillIcon(item.SkillId)
	end
	if item.Type == "Coins" then
		return item.Icon or COIN_ICON
	end
	return ""
end

local function ShowPopup(items, titleText)
	if not claimTipsGui or not claimSuccess or not claimBg then
		return
	end

	if popupVisible then
		ClosePopup()
	end

	ClearPopupItems()

	if itemTemplate and type(items) == "table" then
		for _, reward in ipairs(items) do
			local item = itemTemplate:Clone()
			item.Visible = true
			item.Name = "ItemReward"

			local icon = item:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				icon.Image = ResolveIcon(reward)
			end

			local numberLabel = item:FindFirstChild("Number")
			if numberLabel and numberLabel:IsA("TextLabel") then
				numberLabel.Text = tostring(reward.Count or 1)
			end

			item.Parent = itemListFrame
		end
	end

	ApplyTitle(titleText)
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

-- ==================== Event Handlers ====================

local function OnStarterPackData(data)
	local purchased = false
	if type(data) == "table" then
		purchased = data.Purchased == true
	elseif type(data) == "boolean" then
		purchased = data == true
	end

	cachedPurchased = purchased
	UpdateVisibility()
end

local function OnPurchaseResult(success, message, rewards)
	purchaseLock = false

	if success then
		local tipsSystem = _G.TipsSystem
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Purchase Successful!")
		end
		ShowPopup(rewards, "Purchase Successful!")
	else
		local tipsSystem = _G.TipsSystem
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Purchase failed")
		end
	end

	if requestDataEvent then
		requestDataEvent:FireServer()
	end
end

local function OnCampaignStateUpdate(state)
	local battle = state ~= "Idle"
	if isBattleBlocked == battle then
		return
	end

	isBattleBlocked = battle
	if isBattleBlocked then
		CloseShop()
	end
	UpdateVisibility()
end

local function BindCampaignEvents()
	if campaignEventsBound then
		return
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
	if not eventsFolder then
		return
	end

	local campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
	if not campaignEvents then
		campaignEvents = eventsFolder:WaitForChild("CampaignEvents", 5)
	end
	if not campaignEvents then
		return
	end

	local stateUpdate = campaignEvents:FindFirstChild("CampaignStateUpdate")
	if stateUpdate then
		stateUpdate.OnClientEvent:Connect(OnCampaignStateUpdate)
		campaignEventsBound = true
	end
end

-- ==================== Button Actions ====================

local function OpenShop()
	if not IsShopUnlocked() or isBattleBlocked then
		return
	end
	if cachedPurchased == true or player:GetAttribute("StarterPackPurchased") == true then
		return
	end
	if not PlayShopOpen() then
		return
	end
	if requestDataEvent then
		requestDataEvent:FireServer()
	end
	UpdateVisibility()
end

CloseShop = function()
	PlayShopClose()
end

local function OnBuyButtonClicked()
	if purchaseLock then
		return
	end

	if cachedPurchased == true or player:GetAttribute("StarterPackPurchased") == true then
		return
	end

	if purchaseEvent then
		purchaseLock = true
		purchaseEvent:FireServer()
		task.delay(2, function()
			if purchaseLock then
				purchaseLock = false
			end
		end)
	end
end

-- ==================== Bindings ====================

local function BindButtons()
	LoadButtonEffectHelper()

	if starterPackButton and (starterPackButton:IsA("TextButton") or starterPackButton:IsA("ImageButton")) then
		if not boundButtons[starterPackButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(starterPackButton, { OnClick = OpenShop })
			else
				starterPackButton.MouseButton1Click:Connect(OpenShop)
			end
			boundButtons[starterPackButton] = true
		end
	end

	if shopCloseButton and (shopCloseButton:IsA("TextButton") or shopCloseButton:IsA("ImageButton")) then
		if not boundButtons[shopCloseButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(shopCloseButton, { OnClick = CloseShop })
			else
				shopCloseButton.MouseButton1Click:Connect(CloseShop)
			end
			boundButtons[shopCloseButton] = true
		end
	end

	if buyButton and (buyButton:IsA("TextButton") or buyButton:IsA("ImageButton")) then
		if not boundButtons[buyButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(buyButton, { OnClick = OnBuyButtonClicked })
			else
				buyButton.MouseButton1Click:Connect(OnBuyButtonClicked)
			end
			boundButtons[buyButton] = true
		end
	end
end

local function BindData()
	if dataBound or not dataEvent then
		return
	end

	dataEvent.OnClientEvent:Connect(OnStarterPackData)
	purchaseResultEvent.OnClientEvent:Connect(OnPurchaseResult)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if uiReady then
		BindButtons()
		UpdateVisibility()
		if shopBg then
			if shopVisibleConn then
				shopVisibleConn:Disconnect()
				shopVisibleConn = nil
			end
			shopVisibleConn = shopBg:GetPropertyChangedSignal("Visible"):Connect(function()
				if shopBg.Visible then
					UpdateVisibility()
				end
			end)
			if shopBg.Visible then
				UpdateVisibility()
			end
		end
	end

	if eventsReady then
		BindCampaignEvents()
		BindData()
		if requestDataEvent then
			requestDataEvent:FireServer()
		end
	end

	return eventsReady and uiReady
end

function StarterPackDisplay.Initialize()
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

	player:GetAttributeChangedSignal("StarterPackPurchased"):Connect(UpdateVisibility)
	player:GetAttributeChangedSignal("CompletedChapters"):Connect(UpdateVisibility)

	playerGui.ChildAdded:Connect(function(child)
		if not child then
			return
		end
		if child.Name ~= "MainGui" and child.Name ~= "Shop" and child.Name ~= "ClaimTipsGui" then
			return
		end

		task.spawn(function()
			task.wait()
			TryInitialize()
			UpdateVisibility()
		end)
	end)
end

StarterPackDisplay.Initialize()

return StarterPackDisplay
