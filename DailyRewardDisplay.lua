--[[
脚本名称: DailyRewardDisplay
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/DailyRewardDisplay
版本: V5.3
职责: 每日免费奖励UI显示与领取交互
]]

local DailyRewardDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

local ButtonEffectHelper = nil

-- 事件引用
local dailyRewardEvents = nil
local requestDataEvent = nil
local dataEvent = nil
local claimEvent = nil
local claimResultEvent = nil

-- UI引用
local mainGui = nil
local shopContainer = nil
local shopButton = nil
local freeIcon = nil

local shopGui = nil
local shopBg = nil
local shopCloseButton = nil
local dailyGiftFrame = nil
local claimButton = nil
local claimText = nil
local claimButtonBg = nil
local claimButtonGradient = nil
local claimButtonBgOriginalColor = nil
local refreshLabel = nil

local claimTipsGui = nil
local claimSuccess = nil
local claimBg = nil
local itemListFrame = nil
local itemTemplate = nil
local lightBg = nil
local lightImage = nil
local BACKPACK_HIDE_KEY = "ShopBg"
local BLUR_LOCK_ID = "Shop"
local BLUR_LOCKS_KEY = "__PopupBlurLocks"

-- 状态缓存
local cachedData = nil
local claimLock = false
local nextRefreshTime = 0
local serverTimeOffset = 0
local refreshRequested = false
local countdownConnection = nil
local countdownAccumulator = 0

local freeIconShakeToken = nil
local freeIconOriginalPos = nil

local lightRotateConnection = nil
local popupToken = 0
local shopVisibleConn = nil
local popupVisible = false
local popupAllowClose = false
local popupInputConnection = nil
local campaignEventsBound = false
local isBattleBlocked = false
local CloseShop = nil
local shopOpenSource = nil
local reopenArmyStoreOnClose = false

local POPUP_BG_OFFSET = 0.08
local POPUP_TWEEN_DURATION = 0.3
local POPUP_ALLOW_CLOSE_SECONDS = 1
local LIGHT_ROTATE_SPEED = 60

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

local function SetBlurLock(enabled)
	local locks = _G[BLUR_LOCKS_KEY]
	if type(locks) ~= "table" then
		locks = {}
		_G[BLUR_LOCKS_KEY] = locks
	end

	if enabled then
		locks[BLUR_LOCK_ID] = true
	else
		locks[BLUR_LOCK_ID] = nil
	end

	local blur = Lighting:FindFirstChild("Blur")
	if blur and blur:IsA("BlurEffect") then
		blur.Enabled = next(locks) ~= nil
	end
end

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

	warn("[DailyRewardDisplay] ButtonEffectHelper加载失败:", result)
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
		SetBlurLock(true)
		return true
	end

	if shopBg.Visible and not shopAnimating then
		SetBlurLock(true)
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
		SetBlurLock(true)
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
		SetBlurLock(false)
		return true
	end

	if not shopBg.Visible and not shopAnimating then
		SetBlurLock(false)
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
		SetBlurLock(false)
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

local function IsShopEntryVisible()
	return IsShopUnlocked() and (not isBattleBlocked)
end

-- ==================== UI初始化 ====================

local function InitializeEvents()
	if dailyRewardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[DailyRewardDisplay] Events文件夹未找到")
		return false
	end

	dailyRewardEvents = eventsFolder:WaitForChild("DailyRewardEvents", 10)
	if not dailyRewardEvents then
		warn("[DailyRewardDisplay] DailyRewardEvents未找到")
		return false
	end

	requestDataEvent = dailyRewardEvents:WaitForChild("RequestDailyRewardData", 5)
	dataEvent = dailyRewardEvents:WaitForChild("DailyRewardData", 5)
	claimEvent = dailyRewardEvents:WaitForChild("ClaimDailyReward", 5)
	claimResultEvent = dailyRewardEvents:WaitForChild("ClaimDailyRewardResult", 5)

	if not (requestDataEvent and dataEvent and claimEvent and claimResultEvent) then
		warn("[DailyRewardDisplay] DailyReward事件不完整")
		return false
	end

	return true
end

local function InitializeUI()
	local mainGuiValid = IsDescendantOfPlayerGui(mainGui)
	local shopBgValid = IsDescendantOfPlayerGui(shopBg)
	local claimTipsValid = IsDescendantOfPlayerGui(claimSuccess)

	if mainGuiValid and shopBgValid and claimTipsValid then
		return true
	end

	mainGui = SafeWaitForChild(playerGui, "MainGui", 5)
	shopContainer = mainGui and mainGui:FindFirstChild("Shop")
	freeIcon = shopContainer and shopContainer:FindFirstChild("FreeIcon")
	shopButton = shopContainer
	if shopButton and not (shopButton:IsA("TextButton") or shopButton:IsA("ImageButton")) then
		local innerButton = shopButton:FindFirstChild("Button")
		if innerButton and (innerButton:IsA("TextButton") or innerButton:IsA("ImageButton")) then
			shopButton = innerButton
		end
	end

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

	local scrollingFrame = shopBg and shopBg:FindFirstChild("ScrollingFrame")
	dailyGiftFrame = scrollingFrame and scrollingFrame:FindFirstChild("DailyGift")
	claimButton = dailyGiftFrame and dailyGiftFrame:FindFirstChild("Claim")
	if claimButton then
		claimText = claimButton:FindFirstChild("Text") or claimButton:FindFirstChildWhichIsA("TextLabel")
		claimButtonBg = claimButton:FindFirstChild("bg") or claimButton:FindFirstChild("Bg")
		if claimButtonBg and claimButtonBg:IsA("GuiObject") then
			if not claimButtonBgOriginalColor then
				claimButtonBgOriginalColor = claimButtonBg.BackgroundColor3
			end
			claimButtonGradient = claimButtonBg:FindFirstChildOfClass("UIGradient")
		end
	end
	refreshLabel = dailyGiftFrame and dailyGiftFrame:FindFirstChild("Refresh")
	if refreshLabel and refreshLabel:IsA("TextLabel") then
		refreshLabel.RichText = true
	end

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

	return mainGui ~= nil and shopBg ~= nil
end

-- ==================== FreeIcon抖动 ====================

local function StartFreeIconShake()
	if not freeIcon or not freeIcon.Visible then
		return
	end
	if freeIconShakeToken then
		return
	end

	freeIconOriginalPos = freeIconOriginalPos or freeIcon.Position
	local token = {}
	freeIconShakeToken = token

	task.spawn(function()
		while freeIcon and freeIcon.Visible and freeIconShakeToken == token do
			local offsetRight = UDim2.new(0, 4, 0, 0)
			local offsetLeft = UDim2.new(0, -4, 0, 0)
			local tweenRight = TweenService:Create(
				freeIcon,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = freeIconOriginalPos + offsetRight }
			)
			local tweenLeft = TweenService:Create(
				freeIcon,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = freeIconOriginalPos + offsetLeft }
			)
			local tweenCenter = TweenService:Create(
				freeIcon,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = freeIconOriginalPos }
			)

			tweenRight:Play()
			tweenRight.Completed:Wait()
			if freeIconShakeToken ~= token then
				break
			end
			tweenLeft:Play()
			tweenLeft.Completed:Wait()
			if freeIconShakeToken ~= token then
				break
			end
			tweenCenter:Play()
			tweenCenter.Completed:Wait()
			if freeIconShakeToken ~= token then
				break
			end
			task.wait(2)
		end

		if freeIcon and freeIconOriginalPos then
			freeIcon.Position = freeIconOriginalPos
		end
	end)
end

local function StopFreeIconShake()
	if freeIconShakeToken then
		freeIconShakeToken = nil
	end
	if freeIcon and freeIconOriginalPos then
		freeIcon.Position = freeIconOriginalPos
	end
end

local function UpdateFreeIcon(canClaim)
	if not freeIcon then
		return
	end

	local entryVisible = IsShopEntryVisible()
	freeIcon.Visible = entryVisible and (canClaim == true)
	if freeIcon.Visible then
		StartFreeIconShake()
	else
		StopFreeIconShake()
	end
end

local function UpdateEntryVisibility()
	local entryVisible = IsShopEntryVisible()

	if shopContainer then
		shopContainer.Visible = entryVisible
	end
	if shopButton and shopButton ~= shopContainer then
		shopButton.Visible = entryVisible
	end

	if not entryVisible then
		UpdateFreeIcon(false)
		if shopBg and shopBg.Visible then
			CloseShop("Auto")
		end
		return
	end

	if cachedData then
		UpdateFreeIcon(cachedData.CanClaim == true)
	end
end

-- ==================== 倒计时 ====================

local function UpdateRefreshLabel()
	if not refreshLabel or not refreshLabel:IsA("TextLabel") then
		return
	end

	local now = os.time() + serverTimeOffset
	local remaining = math.max(0, (tonumber(nextRefreshTime) or 0) - now)
	local hours = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)
	refreshLabel.Text = string.format(
		"<font color=\"#FFFFFF\">Refreshes in </font><font color=\"#00FF00\">%02d:%02d</font>",
		hours,
		minutes
	)

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
	UpdateRefreshLabel()
	countdownConnection = RunService.Heartbeat:Connect(function(dt)
		countdownAccumulator = countdownAccumulator + dt
		if countdownAccumulator >= 1 then
			countdownAccumulator = 0
			UpdateRefreshLabel()
		end
	end)
end

local function StopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

-- ==================== 领取按钮状态 ====================

local function SetClaimButtonState(canClaim)
	if not claimButton then
		return
	end

	if claimButton:IsA("TextButton") or claimButton:IsA("ImageButton") then
		claimButton.Active = canClaim == true
		claimButton.AutoButtonColor = canClaim == true
	end

	if claimText and claimText:IsA("TextLabel") then
		claimText.Text = canClaim and "Claim" or "Claimed"
		claimText.TextColor3 = canClaim and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 180)
	elseif claimButton:IsA("TextButton") then
		claimButton.Text = canClaim and "Claim" or "Claimed"
		claimButton.TextColor3 = canClaim and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 180)
	end

	if claimButtonBg and claimButtonBg:IsA("GuiObject") then
		if claimButtonGradient and claimButtonGradient:IsA("UIGradient") then
			claimButtonGradient.Enabled = canClaim == true
		end
		if canClaim then
			if claimButtonBgOriginalColor then
				claimButtonBg.BackgroundColor3 = claimButtonBgOriginalColor
			end
		else
			claimButtonBg.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		end
	end

	if claimButton:IsA("ImageButton") then
		claimButton.ImageColor3 = canClaim and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 160, 160)
	elseif claimButton:IsA("GuiObject") then
		if canClaim then
			claimButton.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
		else
			claimButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		end
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

local function ClearClaimItems()
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

local function CloseClaimPopup()
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
	ClearClaimItems()
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
		CloseClaimPopup()
	end

	ClearClaimItems()

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

local function OnDailyRewardData(data)
	if type(data) ~= "table" then
		return
	end

	cachedData = data
	nextRefreshTime = tonumber(data.NextRefreshTime) or 0
	if type(data.ServerTime) == "number" then
		serverTimeOffset = data.ServerTime - os.time()
	end

	local canClaim = data.CanClaim == true
	SetClaimButtonState(canClaim)
	UpdateFreeIcon(canClaim)
	UpdateRefreshLabel()
end

local function OnClaimResult(success, message, rewardInfo)
	claimLock = false

	local tipsSystem = _G.TipsSystem
	if success then
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Reward Claimed!")
		end
		ShowClaimPopup(rewardInfo)
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Claim failed")
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
		CloseShop("Auto")
	end
	UpdateEntryVisibility()
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

-- ==================== 按钮交互 ====================

local function OpenShop(source)
	if not IsShopUnlocked() or isBattleBlocked then
		return false
	end
	if not PlayShopOpen() then
		return false
	end

	shopOpenSource = source or "Main"
	reopenArmyStoreOnClose = (shopOpenSource == "ArmyStore")
	RequestBackpackHide()
	if requestDataEvent then
		requestDataEvent:FireServer()
	end
	if cachedData then
		SetClaimButtonState(cachedData.CanClaim == true)
		UpdateFreeIcon(cachedData.CanClaim == true)
	end
	StartCountdown()
	return true
end

CloseShop = function(reason)
	PlayShopClose()
	ReleaseBackpackHide()
	StopCountdown()

	local shouldReopen = (reason == "User") and reopenArmyStoreOnClose
	reopenArmyStoreOnClose = false
	shopOpenSource = nil

	if shouldReopen then
		task.delay(0.25, function()
			local shopDisplay = _G.ShopDisplay
			if shopDisplay and shopDisplay.PlayOpen then
				shopDisplay.PlayOpen()
			end
		end)
	end
end

local function OnClaimButtonClicked()
	if claimLock then
		return
	end

	if cachedData and cachedData.CanClaim ~= true then
		return
	end

	if claimEvent then
		claimLock = true
		claimEvent:FireServer()
		task.delay(2, function()
			claimLock = false
		end)
	end
end

-- ==================== 初始化 ====================

local boundButtons = {}
local dataBound = false

local function BindButtons()
	LoadButtonEffectHelper()

	if shopButton and (shopButton:IsA("TextButton") or shopButton:IsA("ImageButton")) then
		if not boundButtons[shopButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(shopButton, { OnClick = OpenShop })
			else
				shopButton.MouseButton1Click:Connect(OpenShop)
			end
			boundButtons[shopButton] = true
		end
	end

	if shopCloseButton and (shopCloseButton:IsA("TextButton") or shopCloseButton:IsA("ImageButton")) then
		if not boundButtons[shopCloseButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(shopCloseButton, { OnClick = function()
					CloseShop("User")
				end })
			else
				shopCloseButton.MouseButton1Click:Connect(function()
					CloseShop("User")
				end)
			end
			boundButtons[shopCloseButton] = true
		end
	end

	if claimButton and (claimButton:IsA("TextButton") or claimButton:IsA("ImageButton")) then
		if not boundButtons[claimButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(claimButton, { OnClick = OnClaimButtonClicked })
			else
				claimButton.MouseButton1Click:Connect(OnClaimButtonClicked)
			end
			boundButtons[claimButton] = true
		end
	end
end

local function BindData()
	if dataBound or not dataEvent then
		return
	end

	dataEvent.OnClientEvent:Connect(OnDailyRewardData)
	claimResultEvent.OnClientEvent:Connect(OnClaimResult)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if uiReady then
		BindButtons()
		if cachedData then
			SetClaimButtonState(cachedData.CanClaim == true)
			UpdateFreeIcon(cachedData.CanClaim == true)
			UpdateRefreshLabel()
		end
		UpdateEntryVisibility()
		if shopBg then
			if shopVisibleConn then
				shopVisibleConn:Disconnect()
				shopVisibleConn = nil
			end
			shopVisibleConn = shopBg:GetPropertyChangedSignal("Visible"):Connect(function()
				if shopBg.Visible then
					SetBlurLock(true)
					StartCountdown()
				else
					SetBlurLock(false)
					StopCountdown()
				end
			end)
			if shopBg.Visible then
				SetBlurLock(true)
				StartCountdown()
			else
				SetBlurLock(false)
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

DailyRewardDisplay.OpenShop = OpenShop
DailyRewardDisplay.CloseShop = CloseShop
DailyRewardDisplay.IsShopOpen = function()
	return shopBg and shopBg.Visible or false
end
_G.DailyRewardDisplay = DailyRewardDisplay

function DailyRewardDisplay.Initialize()
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

	player:GetAttributeChangedSignal("CompletedChapters"):Connect(UpdateEntryVisibility)

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
			UpdateEntryVisibility()
			if cachedData then
				SetClaimButtonState(cachedData.CanClaim == true)
				UpdateFreeIcon(cachedData.CanClaim == true)
			end
		end)
	end)
end

DailyRewardDisplay.Initialize()

return DailyRewardDisplay
