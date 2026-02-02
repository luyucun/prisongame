--[[
脚本名称: OnlineRewardDisplay
脚本类型: LocalScript (客户端UI)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/OnlineRewardDisplay
版本: V6.1
职责: 在线奖励界面展示、倒计时与领取交互
]]

local OnlineRewardDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local OnlineRewardConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("OnlineRewardConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))

local COIN_ICON = "rbxassetid://92295649647469"

local onlineRewardEvents = nil
local requestDataEvent = nil
local dataEvent = nil
local claimEvent = nil
local claimResultEvent = nil

local topRightGui = nil
local onlineButtonContainer = nil
local openButton = nil
local redPoint = nil
local onlineTimeLabel = nil

local onlineRewardGui = nil
local onlineRewardBg = nil
local closeButton = nil
local nextRewardLabel = nil

local rewardFrames = {}
local boundRewardButtons = {}

local cachedData = nil
local serverTimeOffset = 0
local countdownConnection = nil
local countdownAccumulator = 0
local refreshRequested = false

local claimLocks = {}
local ButtonEffectHelper = nil
local boundButtons = {}
local dataBound = false

local claimTipsGui = nil
local claimSuccess = nil
local claimBg = nil
local itemListFrame = nil
local itemTemplate = nil
local lightBg = nil
local lightImage = nil
local titleLabel = nil
local defaultTitleText = nil

local popupVisible = false
local popupAllowClose = false
local popupInputConnection = nil
local popupToken = 0
local lightRotateConnection = nil
local restorePanelAfterPopup = false

local POPUP_BG_OFFSET = 0.08
local POPUP_TWEEN_DURATION = 0.3
local POPUP_ALLOW_CLOSE_SECONDS = 1
local LIGHT_ROTATE_SPEED = 60

-- 面板弹框动画配置（OnlineReward Bg）
local PANEL_OPEN_START_SCALE = 0.86
local PANEL_OPEN_OVERSHOOT_SCALE = 1.10
local PANEL_OPEN_DURATION_A = 0.18
local PANEL_OPEN_DURATION_B = 0.10
local PANEL_CLOSE_OVERSHOOT_SCALE = 1.12
local PANEL_CLOSE_END_SCALE = 0.78
local PANEL_CLOSE_DURATION_A = 0.08
local PANEL_CLOSE_DURATION_B = 0.12

local panelScale = nil
local panelOpenTweenA = nil
local panelOpenTweenB = nil
local panelCloseTweenA = nil
local panelCloseTweenB = nil
local panelAnimating = false

local RewardPathCandidates = {
	[1] = { { "Bg01", "Reward01" } },
	[2] = { { "Bg01", "Reward02" } },
	[3] = { { "Bg01", "Reward03" } },
	[4] = { { "Bg01", "Reward04" } },
	[5] = { { "Bg01", "Reward05" } },
	[6] = { { "Bg02", "Reward01" } },
	[7] = { { "Bg02", "Reward02" } },
	[8] = { { "Bg02", "Reward03" }, { "Bg03", "Reward03" } },
	[9] = { { "Bg02", "Reward04" }, { "Bg04", "Reward04" } },
	[10] = { { "Bg02", "Reward05" }, { "Bg05", "Reward05" } },
}

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

local function IsDescendantOfPlayerGui(instance)
	return instance ~= nil and instance:IsDescendantOf(playerGui)
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

	warn("[OnlineRewardDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function NormalizeClaimedRewards(raw)
	local normalized = {}
	if type(raw) ~= "table" then
		return normalized
	end

	for key, value in pairs(raw) do
		local id = tonumber(key)
		if id and value == true then
			normalized[id] = true
		end
	end

	return normalized
end

local function FormatDuration(seconds)
	local total = math.max(0, math.floor(tonumber(seconds) or 0))
	local minutes = math.floor(total / 60)
	local secs = total % 60
	return string.format("%02d:%02d", minutes, secs)
end

local function FormatHourMinute(seconds)
	local total = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	return string.format("%02d:%02d", hours, minutes)
end

local function GetServerTimeNow()
	return os.time() + serverTimeOffset
end

local function GetCurrentOnlineSeconds()
	if type(cachedData) ~= "table" then
		return 0
	end

	local baseSeconds = tonumber(cachedData.TotalOnlineSeconds) or 0
	local baseServerTime = tonumber(cachedData.ServerTime) or GetServerTimeNow()
	local nowServerTime = GetServerTimeNow()
	local delta = nowServerTime - baseServerTime
	if delta < 0 then
		delta = 0
	end
	return baseSeconds + delta
end

-- ==================== 初始化 ====================

local function InitializeEvents()
	if onlineRewardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[OnlineRewardDisplay] Events folder not found")
		return false
	end

	onlineRewardEvents = eventsFolder:WaitForChild("OnlineRewardEvents", 10)
	if not onlineRewardEvents then
		warn("[OnlineRewardDisplay] OnlineRewardEvents not found")
		return false
	end

	requestDataEvent = onlineRewardEvents:WaitForChild("RequestOnlineRewardData", 5)
	dataEvent = onlineRewardEvents:WaitForChild("OnlineRewardData", 5)
	claimEvent = onlineRewardEvents:WaitForChild("ClaimOnlineReward", 5)
	claimResultEvent = onlineRewardEvents:WaitForChild("ClaimOnlineRewardResult", 5)

	if not (requestDataEvent and dataEvent and claimEvent and claimResultEvent) then
		warn("[OnlineRewardDisplay] OnlineReward events missing")
		return false
	end

	return true
end

local function InitializeUI()
	local topRightValid = IsDescendantOfPlayerGui(onlineButtonContainer)
	local rewardValid = IsDescendantOfPlayerGui(onlineRewardBg)
	local popupValid = IsDescendantOfPlayerGui(claimSuccess)

	if topRightValid and rewardValid and popupValid then
		return true
	end

	if not topRightValid then
		topRightGui = nil
		onlineButtonContainer = nil
		openButton = nil
		redPoint = nil
		onlineTimeLabel = nil
	end

	if not rewardValid then
		onlineRewardGui = nil
		onlineRewardBg = nil
		closeButton = nil
		nextRewardLabel = nil
		rewardFrames = {}
		boundRewardButtons = {}
	end

	topRightGui = SafeWaitForChild(playerGui, "TopRightGui", 5)
	if topRightGui then
		local topRightBg = topRightGui:FindFirstChild("Bg")
		onlineButtonContainer = topRightBg and topRightBg:FindFirstChild("Online")
		openButton = onlineButtonContainer
		if openButton and not (openButton:IsA("TextButton") or openButton:IsA("ImageButton")) then
			local innerButton = openButton:FindFirstChild("Button")
			if innerButton and (innerButton:IsA("TextButton") or innerButton:IsA("ImageButton")) then
				openButton = innerButton
			end
		end
		redPoint = onlineButtonContainer and onlineButtonContainer:FindFirstChild("RedPoint")
		if redPoint then
			redPoint.Visible = false
		end
		onlineTimeLabel = onlineButtonContainer and onlineButtonContainer:FindFirstChild("Time")
		if (not onlineTimeLabel or not onlineTimeLabel:IsA("TextLabel")) and openButton then
			local fallback = openButton:FindFirstChild("Time")
			if fallback and fallback:IsA("TextLabel") then
				onlineTimeLabel = fallback
			end
		end
	end

	onlineRewardGui = SafeWaitForChild(playerGui, "OnlineReward", 5)
	if not onlineRewardGui then
		warn("[OnlineRewardDisplay] OnlineReward GUI not found")
		return false
	end

	onlineRewardBg = onlineRewardGui:FindFirstChild("Bg")
	if not onlineRewardBg then
		warn("[OnlineRewardDisplay] OnlineReward Bg not found")
		return false
	end

	local title = onlineRewardBg:FindFirstChild("Title")
	closeButton = title and title:FindFirstChild("CloseButton")
	nextRewardLabel = onlineRewardBg:FindFirstChild("NextReward")

	rewardFrames = {}
	for _, reward in ipairs(OnlineRewardConfig.GetRewards()) do
		local rewardId = tonumber(reward.Id)
		local candidates = rewardId and RewardPathCandidates[rewardId]
		if rewardId and candidates then
			local rewardFrame = nil
			for _, path in ipairs(candidates) do
				local bgContainer = onlineRewardBg:FindFirstChild(path[1])
				local candidate = bgContainer and bgContainer:FindFirstChild(path[2])
				if candidate then
					rewardFrame = candidate
					break
				end
			end

			if rewardFrame then
				local timeLabel = rewardFrame:FindFirstChild("Time")
				local claimButton = rewardFrame:FindFirstChild("Claim")
				local claimedLabel = rewardFrame:FindFirstChild("Claimed")
				local defaultTimeText = FormatDuration(reward.Seconds)
				if timeLabel and timeLabel:IsA("TextLabel") then
					timeLabel.Text = defaultTimeText
				end
				rewardFrames[rewardId] = {
					Frame = rewardFrame,
					Time = timeLabel,
					Claim = claimButton,
					Claimed = claimedLabel,
					DefaultTimeText = defaultTimeText,
				}
			end
		end
	end

	if onlineRewardBg then
		onlineRewardBg.Visible = false
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

	return true
end

local function EnsurePanelScale()
	if not onlineRewardBg then
		return nil
	end

	if not panelScale or panelScale.Parent ~= onlineRewardBg then
		panelScale = onlineRewardBg:FindFirstChild("PopupScale")
		if not panelScale then
			panelScale = Instance.new("UIScale")
			panelScale.Name = "PopupScale"
			panelScale.Scale = 1
			panelScale.Parent = onlineRewardBg
		end
	end

	return panelScale
end

local function CancelPanelTweens()
	local tweens = {panelOpenTweenA, panelOpenTweenB, panelCloseTweenA, panelCloseTweenB}
	for _, tween in ipairs(tweens) do
		if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
			tween:Cancel()
		end
	end
end

local function ForceHidePanel()
	if not onlineRewardBg then
		return
	end

	CancelPanelTweens()
	local scale = EnsurePanelScale()
	if scale then
		scale.Scale = 1
	end
	onlineRewardBg.Visible = false
	panelAnimating = false
end

local function PlayPanelOpen()
	if not onlineRewardBg then
		return false
	end

	local scale = EnsurePanelScale()
	if not scale then
		onlineRewardBg.Visible = true
		return true
	end

	if onlineRewardBg.Visible and not panelAnimating then
		return true
	end

	CancelPanelTweens()
	panelAnimating = true

	onlineRewardBg.Visible = true
	scale.Scale = PANEL_OPEN_START_SCALE

	panelOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(PANEL_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = PANEL_OPEN_OVERSHOOT_SCALE}
	)
	panelOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(PANEL_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1}
	)

	local connA
	connA = panelOpenTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			panelOpenTweenB:Play()
		end
	end)

	local connB
	connB = panelOpenTweenB.Completed:Connect(function()
		connB:Disconnect()
		panelAnimating = false
		scale.Scale = 1
	end)

	panelOpenTweenA:Play()
	return true
end

local function PlayPanelClose()
	if not onlineRewardBg then
		return false
	end

	local scale = EnsurePanelScale()
	if not scale then
		onlineRewardBg.Visible = false
		return true
	end

	if not onlineRewardBg.Visible and not panelAnimating then
		return true
	end

	CancelPanelTweens()
	panelAnimating = true

	panelCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(PANEL_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = PANEL_CLOSE_OVERSHOOT_SCALE}
	)
	panelCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(PANEL_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = PANEL_CLOSE_END_SCALE}
	)

	local connA
	connA = panelCloseTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			panelCloseTweenB:Play()
		end
	end)

	local connB
	connB = panelCloseTweenB.Completed:Connect(function()
		connB:Disconnect()
		onlineRewardBg.Visible = false
		scale.Scale = 1
		panelAnimating = false
	end)

	panelCloseTweenA:Play()
	return true
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
	if restorePanelAfterPopup and onlineRewardBg then
		CancelPanelTweens()
		local scale = EnsurePanelScale()
		if scale then
			scale.Scale = 1
		end
		onlineRewardBg.Visible = true
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
	if item.Type == "Handcuff" then
		return item.Icon or ""
	end
	return ""
end

local function ShowPopup(rewardInfo, titleText)
	if not claimTipsGui or not claimSuccess or not claimBg then
		return
	end

	if popupVisible then
		ClosePopup()
	end

	restorePanelAfterPopup = onlineRewardBg and onlineRewardBg.Visible == true
	if restorePanelAfterPopup and onlineRewardBg then
		ForceHidePanel()
	end

	ClearPopupItems()

	if itemTemplate and rewardInfo then
		local item = itemTemplate:Clone()
		item.Visible = true
		item.Name = "ItemReward"

		local icon = item:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = ResolveIcon(rewardInfo)
		end

		local numberLabel = item:FindFirstChild("Number")
		if numberLabel and numberLabel:IsA("TextLabel") then
			numberLabel.Text = tostring(rewardInfo.Count or 1)
		end

		item.Parent = itemListFrame
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

-- ==================== UI更新 ====================

local function GetNextUnclaimedReward(claimed)
	for _, reward in ipairs(OnlineRewardConfig.GetRewards()) do
		local rewardId = tonumber(reward.Id)
		if rewardId and not claimed[rewardId] then
			return rewardId, reward
		end
	end
	return nil, nil
end

local function GetNextCountdownReward(claimed, currentSeconds)
	for _, reward in ipairs(OnlineRewardConfig.GetRewards()) do
		local rewardId = tonumber(reward.Id)
		if rewardId and not claimed[rewardId] then
			local required = tonumber(reward.Seconds) or 0
			if currentSeconds < required then
				return rewardId, reward, math.max(0, required - currentSeconds)
			end
		end
	end
	return nil, nil, 0
end

local function UpdateNextRewardLabel(currentSeconds, nextReward)
	if not nextRewardLabel or not nextRewardLabel:IsA("TextLabel") then
		return
	end

	if not nextReward then
		nextRewardLabel.Text = "Next Reward:00:00"
		return
	end

	local remaining = math.max(0, (tonumber(nextReward.Seconds) or 0) - currentSeconds)
	nextRewardLabel.Text = "Next Reward:" .. FormatDuration(remaining)
end

local function UpdateTopRightTimeLabel(remainingSeconds)
	if onlineTimeLabel and onlineTimeLabel:IsA("TextLabel") then
		onlineTimeLabel.Text = FormatHourMinute(remainingSeconds)
	end
end

local function SetRewardState(rewardId, state, countdownText)
	local frame = rewardFrames[rewardId]
	if not frame then
		return
	end

	if frame.Time then
		if state == "countdown" then
			frame.Time.Visible = true
			frame.Time.Text = countdownText or frame.DefaultTimeText
		elseif state == "default" then
			frame.Time.Visible = true
			frame.Time.Text = frame.DefaultTimeText
		else
			frame.Time.Visible = false
		end
	end

	if frame.Claim then
		frame.Claim.Visible = state == "claim"
		frame.Claim.Active = state == "claim"
	end

	if frame.Claimed then
		frame.Claimed.Visible = state == "claimed"
	end
end

local function UpdateRedPoint(claimable)
	if redPoint then
		redPoint.Visible = claimable == true
	end
end

local function UpdateRewardStates()
	if type(cachedData) ~= "table" then
		return
	end

	local claimed = NormalizeClaimedRewards(cachedData.ClaimedRewards)
	local currentSeconds = GetCurrentOnlineSeconds()
	local nextCountdownId, nextCountdownReward, nextRemaining = GetNextCountdownReward(claimed, currentSeconds)
	local hasClaimable = false

	for _, reward in ipairs(OnlineRewardConfig.GetRewards()) do
		local rewardId = tonumber(reward.Id)
		if rewardId and rewardFrames[rewardId] then
			if claimed[rewardId] then
				SetRewardState(rewardId, "claimed")
			else
				local required = tonumber(reward.Seconds) or 0
				if currentSeconds >= required then
					SetRewardState(rewardId, "claim")
					hasClaimable = true
				elseif nextCountdownId and rewardId == nextCountdownId then
					SetRewardState(rewardId, "countdown", FormatDuration(nextRemaining))
				else
					SetRewardState(rewardId, "default")
				end
			end
		end
	end

	UpdateNextRewardLabel(currentSeconds, nextCountdownReward)
	UpdateTopRightTimeLabel(nextRemaining)
	UpdateRedPoint(hasClaimable)
end

local function StartCountdown()
	if countdownConnection then
		return
	end

	countdownAccumulator = 0
	countdownConnection = RunService.RenderStepped:Connect(function(deltaTime)
		countdownAccumulator += deltaTime
		if countdownAccumulator < 0.3 then
			return
		end
		countdownAccumulator = 0
		UpdateRewardStates()
	end)
end

-- ==================== 交互处理 ====================

local function OpenPanel()
	if not PlayPanelOpen() then
		return
	end
	if requestDataEvent and not refreshRequested then
		refreshRequested = true
		requestDataEvent:FireServer()
		task.delay(0.5, function()
			refreshRequested = false
		end)
	end
end

local function ClosePanel()
	PlayPanelClose()
end

local function OnClaimButtonClicked(rewardId)
	if claimLocks[rewardId] then
		return
	end

	if not claimEvent then
		return
	end

	claimLocks[rewardId] = true
	claimEvent:FireServer(rewardId)
end

local function BindButtons()
	if not LoadButtonEffectHelper() then
		ButtonEffectHelper = nil
	end

	local function BindButton(button, callback)
		if not button or boundButtons[button] then
			return
		end
		boundButtons[button] = true
		if ButtonEffectHelper and ButtonEffectHelper.AddClickEffect then
			ButtonEffectHelper.AddClickEffect(button, { OnClick = callback })
		else
			button.MouseButton1Click:Connect(callback)
		end
	end

	BindButton(openButton, OpenPanel)
	BindButton(closeButton, ClosePanel)

	for rewardId, frame in pairs(rewardFrames) do
		local claimButton = frame.Claim
		if claimButton and not boundRewardButtons[rewardId] then
			boundRewardButtons[rewardId] = true
			if ButtonEffectHelper and ButtonEffectHelper.AddClickEffect then
				ButtonEffectHelper.AddClickEffect(claimButton, {
					OnClick = function()
						OnClaimButtonClicked(rewardId)
					end,
				})
			else
				claimButton.MouseButton1Click:Connect(function()
					OnClaimButtonClicked(rewardId)
				end)
			end
		end
	end
end

-- ==================== 事件处理 ====================

local function OnOnlineRewardData(data)
	if type(data) ~= "table" then
		return
	end

	cachedData = data
	if type(data.ServerTime) == "number" then
		serverTimeOffset = data.ServerTime - os.time()
	end

	UpdateRewardStates()
	StartCountdown()
end

local function OnClaimResult(success, message, rewardInfo, rewardId)
	if rewardId then
		claimLocks[rewardId] = nil
	else
		claimLocks = {}
	end

	local tipsSystem = _G.TipsSystem
	if success then
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Reward Claimed!")
		end
		ShowPopup(rewardInfo, "Reward Claimed!")
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Claim failed.")
		end
	end

	if requestDataEvent then
		requestDataEvent:FireServer()
	end
end

local function BindData()
	if dataBound or not dataEvent then
		return
	end

	dataEvent.OnClientEvent:Connect(OnOnlineRewardData)
	claimResultEvent.OnClientEvent:Connect(OnClaimResult)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if uiReady then
		BindButtons()
	end
	if eventsReady then
		BindData()
		if requestDataEvent then
			requestDataEvent:FireServer()
		end
	end

	return eventsReady and uiReady
end

function OnlineRewardDisplay.Initialize()
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
		if child.Name ~= "TopRightGui" and child.Name ~= "OnlineReward" and child.Name ~= "ClaimTipsGui" then
			return
		end

		task.spawn(function()
			task.wait()
			TryInitialize()
			UpdateRewardStates()
		end)
	end)
end

OnlineRewardDisplay.Initialize()

return OnlineRewardDisplay
