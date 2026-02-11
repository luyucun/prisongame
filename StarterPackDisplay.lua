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
local RobuxPriceHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RobuxPriceHelper"))

local ButtonEffectHelper = nil

local STARTER_PACK_GAMEPASS_ID = 1658798778

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
local starterPackIcon = nil
local starterPackNameLabel = nil
local starterPackNameGradient = nil
local starterPackEntryPriceLabel = nil

local starterPackGui = nil
local starterPackBg = nil
local starterPackCloseButton = nil
local starterPackBuyButtonContainer = nil
local starterPackBuyButton = nil
local starterPackBuyRightPriceLabel = nil

local shopGui = nil
local shopBg = nil
local BACKPACK_HIDE_KEY = "StarterPackBg"
local newPlayerFrame = nil
local shopBuyButton = nil
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
local starterPackVisibleConn = nil
local campaignEventsBound = false
local isBattleBlocked = false
local CloseStarterPack = nil

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

local starterPackScale = nil
local starterPackOpenTweenA = nil
local starterPackOpenTweenB = nil
local starterPackCloseTweenA = nil
local starterPackCloseTweenB = nil
local starterPackAnimating = false

local starterPackLightRotateConnection = nil
local starterPackNameGradientTween = nil
local starterPackIconShakeToken = nil

-- ==================== Helpers ====================

local function RequestBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.IsOnIdleFloor and trigger.IsOnIdleFloor() then
		if trigger.PushHideLock then
			trigger.PushHideLock(BACKPACK_HIDE_KEY)
		elseif _G.BackpackDisplay and _G.BackpackDisplay.HideBackpack then
			_G.BackpackDisplay.HideBackpack()
		end
	end
end

local function ReleaseBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.PopHideLock then
		trigger.PopHideLock(BACKPACK_HIDE_KEY)
	elseif trigger and trigger.RefreshVisibility then
		trigger.RefreshVisibility()
	end
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

local function EnsureStarterPackScale()
	if not starterPackBg then
		return nil
	end

	if not starterPackScale or starterPackScale.Parent ~= starterPackBg then
		starterPackScale = starterPackBg:FindFirstChild("PopupScale")
		if not starterPackScale then
			starterPackScale = Instance.new("UIScale")
			starterPackScale.Name = "PopupScale"
			starterPackScale.Scale = 1
			starterPackScale.Parent = starterPackBg
		end
	end

	return starterPackScale
end

local function CancelStarterPackTweens()
	local tweens = {starterPackOpenTweenA, starterPackOpenTweenB, starterPackCloseTweenA, starterPackCloseTweenB}
	for _, tween in ipairs(tweens) do
		if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
			tween:Cancel()
		end
	end
end

local function PlayStarterPackOpen()
	if not starterPackBg then
		return false
	end

	local scale = EnsureStarterPackScale()
	if not scale then
		starterPackBg.Visible = true
		return true
	end

	if starterPackBg.Visible and not starterPackAnimating then
		return true
	end

	CancelStarterPackTweens()
	starterPackAnimating = true

	starterPackBg.Visible = true
	scale.Scale = SHOP_OPEN_START_SCALE

	starterPackOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = SHOP_OPEN_OVERSHOOT_SCALE}
	)
	starterPackOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1}
	)

	local connA
	connA = starterPackOpenTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			starterPackOpenTweenB:Play()
		end
	end)

	local connB
	connB = starterPackOpenTweenB.Completed:Connect(function()
		connB:Disconnect()
		starterPackAnimating = false
		scale.Scale = 1
	end)

	starterPackOpenTweenA:Play()
	return true
end

local function PlayStarterPackClose()
	if not starterPackBg then
		return false
	end

	local scale = EnsureStarterPackScale()
	if not scale then
		starterPackBg.Visible = false
		return true
	end

	if not starterPackBg.Visible and not starterPackAnimating then
		return true
	end

	CancelStarterPackTweens()
	starterPackAnimating = true

	starterPackCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = SHOP_CLOSE_OVERSHOOT_SCALE}
	)
	starterPackCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(SHOP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = SHOP_CLOSE_END_SCALE}
	)

	local connA
	connA = starterPackCloseTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			starterPackCloseTweenB:Play()
		end
	end)

	local connB
	connB = starterPackCloseTweenB.Completed:Connect(function()
		connB:Disconnect()
		starterPackBg.Visible = false
		scale.Scale = 1
		starterPackAnimating = false
	end)

	starterPackCloseTweenA:Play()
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

local function StartStarterPackIconShake()
	if starterPackIconShakeToken or not starterPackIcon or not starterPackIcon:IsA("GuiObject") then
		return
	end

	local token = {}
	starterPackIconShakeToken = token
	local baseRotation = starterPackIcon.Rotation

	task.spawn(function()
		while starterPackIconShakeToken == token do
			local tween1 = TweenService:Create(starterPackIcon, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = baseRotation + 10})
			local tween2 = TweenService:Create(starterPackIcon, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = baseRotation - 10})
			local tween3 = TweenService:Create(starterPackIcon, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = baseRotation + 6})
			local tween4 = TweenService:Create(starterPackIcon, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = baseRotation - 6})
			local tween5 = TweenService:Create(starterPackIcon, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = baseRotation})

			tween1:Play()
			tween1.Completed:Wait()
			if starterPackIconShakeToken ~= token then
				break
			end
			tween2:Play()
			tween2.Completed:Wait()
			if starterPackIconShakeToken ~= token then
				break
			end
			tween3:Play()
			tween3.Completed:Wait()
			if starterPackIconShakeToken ~= token then
				break
			end
			tween4:Play()
			tween4.Completed:Wait()
			if starterPackIconShakeToken ~= token then
				break
			end
			tween5:Play()
			tween5.Completed:Wait()
			if starterPackIconShakeToken ~= token then
				break
			end
			task.wait(4)
		end

		if starterPackIcon then
			starterPackIcon.Rotation = baseRotation
		end
	end)
end

local function StopStarterPackIconShake()
	if starterPackIconShakeToken then
		starterPackIconShakeToken = nil
	end
	if starterPackIcon then
		starterPackIcon.Rotation = 0
	end
end

local function EnsureStarterPackNameGradient()
	if not starterPackNameLabel or not starterPackNameLabel:IsA("GuiObject") then
		return nil
	end

	local gradient = starterPackNameLabel:FindFirstChildWhichIsA("UIGradient", true)
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "NameGradient"
		gradient.Parent = starterPackNameLabel
	end

	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 98, 0)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 230, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(85, 255, 0)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(0, 209, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 98, 0)),
	})

	if starterPackNameLabel:IsA("TextLabel") or starterPackNameLabel:IsA("TextButton") then
		starterPackNameLabel.TextColor3 = Color3.new(1, 1, 1)
	end

	starterPackNameGradient = gradient
	return gradient
end

local function StartStarterPackNameGradient()
	if starterPackNameGradientTween then
		return
	end
	local gradient = EnsureStarterPackNameGradient()
	if not gradient then
		return
	end

	gradient.Rotation = 0
	starterPackNameGradientTween = TweenService:Create(
		gradient,
		TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{ Rotation = 360 }
	)
	starterPackNameGradientTween:Play()
end

local function StopStarterPackNameGradient()
	if starterPackNameGradientTween then
		starterPackNameGradientTween:Cancel()
		starterPackNameGradientTween = nil
	end
	if starterPackNameGradient then
		starterPackNameGradient.Rotation = 0
	end
end

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
	local starterPackValid = IsDescendantOfPlayerGui(starterPackBg)
	local popupValid = IsDescendantOfPlayerGui(claimSuccess)

	if mainGuiValid and starterPackValid and popupValid then
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
	starterPackIcon = starterPackContainer and starterPackContainer:FindFirstChild("Icon", true)
	starterPackNameLabel = starterPackContainer and starterPackContainer:FindFirstChild("Name", true)
	if starterPackNameLabel and not starterPackNameLabel:IsA("TextLabel") then
		local innerName = starterPackNameLabel:FindFirstChild("Text") or starterPackNameLabel:FindFirstChildWhichIsA("TextLabel")
		if innerName then
			starterPackNameLabel = innerName
		end
	end
	starterPackNameGradient = starterPackNameLabel and starterPackNameLabel:FindFirstChildWhichIsA("UIGradient", true)
	starterPackEntryPriceLabel = starterPackContainer and starterPackContainer:FindFirstChild("Price", true) or nil
	if starterPackEntryPriceLabel then
		RobuxPriceHelper.UpdateGamePassLabel(starterPackEntryPriceLabel, STARTER_PACK_GAMEPASS_ID, "prefix")
	end

	starterPackGui = SafeWaitForChild(playerGui, "StarterPack", 5)
	starterPackBg = starterPackGui and starterPackGui:FindFirstChild("Bg")
	if starterPackBg then
		local title = starterPackBg:FindFirstChild("Title")
		starterPackCloseButton = title and title:FindFirstChild("CloseButton")

		starterPackBuyButtonContainer = starterPackBg:FindFirstChild("BuyButton", true)
		starterPackBuyButton = starterPackBuyButtonContainer
		if starterPackBuyButton and not (starterPackBuyButton:IsA("TextButton") or starterPackBuyButton:IsA("ImageButton")) then
			local innerBuy = starterPackBuyButton:FindFirstChild("Button")
				or starterPackBuyButton:FindFirstChildWhichIsA("TextButton")
				or starterPackBuyButton:FindFirstChildWhichIsA("ImageButton")
			if innerBuy then
				starterPackBuyButton = innerBuy
			end
		end
		starterPackBuyRightPriceLabel = starterPackBuyButtonContainer and starterPackBuyButtonContainer:FindFirstChild("RightPrice", true) or nil
		if starterPackBuyRightPriceLabel then
			RobuxPriceHelper.UpdateGamePassLabel(starterPackBuyRightPriceLabel, STARTER_PACK_GAMEPASS_ID, nil)
		end

		local scale = EnsureStarterPackScale()
		if scale then
			scale.Scale = 1
		end

		starterPackBg.Visible = false
	end

	-- Shop内的NewPlayer区域（用于隐藏，不再作为购买入口）
	shopGui = SafeWaitForChild(playerGui, "Shop", 5)
	shopBg = shopGui and shopGui:FindFirstChild("ShopBg")

	newPlayerFrame = nil
	shopBuyButton = nil
	tabList = nil
	tabNewPlayerButton = nil

	if shopBg then
		newPlayerFrame = shopBg:FindFirstChild("NewPlayer")
		local scrollingFrame = shopBg:FindFirstChild("ScrollingFrame")
		if not newPlayerFrame and scrollingFrame then
			newPlayerFrame = scrollingFrame:FindFirstChild("NewPlayer")
		end
		shopBuyButton = newPlayerFrame and newPlayerFrame:FindFirstChild("BuyButton")
		if shopBuyButton and not (shopBuyButton:IsA("TextButton") or shopBuyButton:IsA("ImageButton")) then
			local innerBuy = shopBuyButton:FindFirstChild("Button")
				or shopBuyButton:FindFirstChildWhichIsA("TextButton")
				or shopBuyButton:FindFirstChildWhichIsA("ImageButton")
			if innerBuy then
				shopBuyButton = innerBuy
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

	return mainGui ~= nil and starterPackBg ~= nil
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

	if purchased and starterPackBg and starterPackBg.Visible then
		if CloseStarterPack then
			CloseStarterPack()
		end
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
		StartStarterPackIconShake()
		StartStarterPackNameGradient()
	else
		if starterPackLightRotateConnection then
			starterPackLightRotateConnection:Disconnect()
			starterPackLightRotateConnection = nil
		end
		if starterPackLight then
			starterPackLight.Rotation = 0
		end
		StopStarterPackIconShake()
		StopStarterPackNameGradient()
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
		if CloseStarterPack then
			CloseStarterPack()
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
	UpdateVisibility()
end

local function OnCampaignStateUpdate(state)
	local battle = state ~= "Idle"
	if isBattleBlocked == battle then
		return
	end

	isBattleBlocked = battle
	if isBattleBlocked then
		if CloseStarterPack then
			CloseStarterPack()
		end
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

local function OpenStarterPack()
	if not IsShopUnlocked() or isBattleBlocked then
		return
	end
	if cachedPurchased == true or player:GetAttribute("StarterPackPurchased") == true then
		return
	end
	if not PlayStarterPackOpen() then
		return
	end
	RequestBackpackHide()
	if requestDataEvent then
		requestDataEvent:FireServer()
	end
	UpdateVisibility()
end

CloseStarterPack = function()
	PlayStarterPackClose()
	ReleaseBackpackHide()
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
				ButtonEffectHelper.AddClickEffect(starterPackButton, { OnClick = OpenStarterPack })
			else
				starterPackButton.MouseButton1Click:Connect(OpenStarterPack)
			end
			boundButtons[starterPackButton] = true
		end
	end

	if starterPackCloseButton and (starterPackCloseButton:IsA("TextButton") or starterPackCloseButton:IsA("ImageButton")) then
		if not boundButtons[starterPackCloseButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(starterPackCloseButton, { OnClick = CloseStarterPack })
			else
				starterPackCloseButton.MouseButton1Click:Connect(CloseStarterPack)
			end
			boundButtons[starterPackCloseButton] = true
		end
	end

	if starterPackBuyButton and (starterPackBuyButton:IsA("TextButton") or starterPackBuyButton:IsA("ImageButton")) then
		if not boundButtons[starterPackBuyButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(starterPackBuyButton, { OnClick = OnBuyButtonClicked })
			else
				starterPackBuyButton.MouseButton1Click:Connect(OnBuyButtonClicked)
			end
			boundButtons[starterPackBuyButton] = true
		end
	end

	if shopBuyButton and (shopBuyButton:IsA("TextButton") or shopBuyButton:IsA("ImageButton")) then
		if not boundButtons[shopBuyButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(shopBuyButton, { OnClick = OnBuyButtonClicked })
			else
				shopBuyButton.MouseButton1Click:Connect(OnBuyButtonClicked)
			end
			boundButtons[shopBuyButton] = true
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
		if starterPackBg then
			if starterPackVisibleConn then
				starterPackVisibleConn:Disconnect()
				starterPackVisibleConn = nil
			end
			starterPackVisibleConn = starterPackBg:GetPropertyChangedSignal("Visible"):Connect(function()
				if starterPackBg.Visible then
					UpdateVisibility()
				end
			end)
			if starterPackBg.Visible then
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
		if child.Name ~= "MainGui" and child.Name ~= "Shop" and child.Name ~= "StarterPack" and child.Name ~= "ClaimTipsGui" then
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
