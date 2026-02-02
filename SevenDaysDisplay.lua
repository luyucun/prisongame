--[[
=====================================================
脚本名称: SevenDaysDisplay
脚本类型: LocalScript (客户端UI)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/SevenDaysDisplay
版本: V4.8
=====================================================
]]

local SevenDaysDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SevenDaysConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SevenDaysConfig"))

local sevenDaysEvents = nil
local requestDataEvent = nil
local sevenDaysDataEvent = nil
local claimRewardEvent = nil
local claimResultEvent = nil

local topRightGui = nil
local sevenDaysButtonContainer = nil
local openButton = nil
local redPoint = nil
local redPointOriginalPos = nil
local redPointShakeToken = nil
local StopRedPointShake = nil

local sevenDaysGui = nil
local sevenDaysBg = nil
local blackBg = nil
local closeButton = nil
local nextRewardLabel = nil
local unlockAllButton = nil

local rewardFrames = {}
local boundRewardButtons = {}

local cachedData = nil
local nextRefreshTime = 0
local serverTimeOffset = 0
local countdownConnection = nil
local countdownAccumulator = 0
local refreshRequested = false

local claimLocks = {}
local unlockAllInProgress = false

local ButtonEffectHelper = nil
local boundButtons = {}
local dataBound = false
local BindButtons = nil
local BindRewardButtons = nil
local UpdateRedPoint = nil
local campaignEventsBound = false
local lastCampaignTotalStages = nil

-- 弹框动画配置（仅Bg）
local POPUP_OPEN_START_SCALE = 0.86
local POPUP_OPEN_OVERSHOOT_SCALE = 1.10
local POPUP_OPEN_DURATION_A = 0.18
local POPUP_OPEN_DURATION_B = 0.10
local POPUP_CLOSE_OVERSHOOT_SCALE = 1.12
local POPUP_CLOSE_END_SCALE = 0.78
local POPUP_CLOSE_DURATION_A = 0.08
local POPUP_CLOSE_DURATION_B = 0.12

local panelScale = nil
local panelOpenTweenA = nil
local panelOpenTweenB = nil
local panelCloseTweenA = nil
local panelCloseTweenB = nil
local panelAnimating = false

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

local function NormalizeClaimedDaysTable(raw)
	local normalized = {}
	if type(raw) ~= "table" then
		return normalized
	end

	for key, value in pairs(raw) do
		local index = tonumber(key)
		if index and value == true then
			normalized[index] = true
		end
	end

	return normalized
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

	warn("[SevenDaysDisplay] ButtonEffectHelper加载失败:", result)
	return false
end

local function EnsurePanelScale()
	if not sevenDaysBg then
		return nil
	end

	if not panelScale or panelScale.Parent ~= sevenDaysBg then
		panelScale = sevenDaysBg:FindFirstChild("PopupScale")
		if not panelScale then
			panelScale = Instance.new("UIScale")
			panelScale.Name = "PopupScale"
			panelScale.Scale = 1
			panelScale.Parent = sevenDaysBg
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

local function PlayPanelOpen()
	if not sevenDaysBg then
		return false
	end

	local scale = EnsurePanelScale()
	if not scale then
		sevenDaysBg.Visible = true
		if blackBg then
			blackBg.Visible = true
		end
		return true
	end

	if sevenDaysBg.Visible and not panelAnimating then
		return true
	end

	CancelPanelTweens()
	panelAnimating = true

	sevenDaysBg.Visible = true
	if blackBg then
		blackBg.Visible = true
	end
	scale.Scale = POPUP_OPEN_START_SCALE

	panelOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_OPEN_OVERSHOOT_SCALE}
	)
	panelOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
	if not sevenDaysBg then
		return false
	end

	local scale = EnsurePanelScale()
	if not scale then
		sevenDaysBg.Visible = false
		if blackBg then
			blackBg.Visible = false
		end
		return true
	end

	if not sevenDaysBg.Visible and not panelAnimating then
		return true
	end

	CancelPanelTweens()
	panelAnimating = true

	panelCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_CLOSE_OVERSHOOT_SCALE}
	)
	panelCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = POPUP_CLOSE_END_SCALE}
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
		sevenDaysBg.Visible = false
		if blackBg then
			blackBg.Visible = false
		end
		scale.Scale = 1
		panelAnimating = false
	end)

	panelCloseTweenA:Play()
	return true
end

local function InitializeEvents()
	if sevenDaysEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[SevenDaysDisplay] Events文件夹未找到")
		return false
	end

	sevenDaysEvents = eventsFolder:WaitForChild("SevenDaysEvents", 10)
	if not sevenDaysEvents then
		warn("[SevenDaysDisplay] SevenDaysEvents未找到")
		return false
	end

	requestDataEvent = sevenDaysEvents:WaitForChild("RequestSevenDaysData", 5)
	sevenDaysDataEvent = sevenDaysEvents:WaitForChild("SevenDaysData", 5)
	claimRewardEvent = sevenDaysEvents:WaitForChild("ClaimSevenDayReward", 5)
	claimResultEvent = sevenDaysEvents:WaitForChild("ClaimSevenDayResult", 5)

	if not (requestDataEvent and sevenDaysDataEvent and claimRewardEvent and claimResultEvent) then
		warn("[SevenDaysDisplay] SevenDaysEvents事件不完整")
		return false
	end

	return true
end

local function InitializeUI()
	local topRightValid = IsDescendantOfPlayerGui(sevenDaysButtonContainer)
	local sevenDaysValid = IsDescendantOfPlayerGui(sevenDaysBg)
	if topRightValid and sevenDaysValid then
		return true
	end

	local previousSevenDaysBg = sevenDaysBg
	local previousRedPoint = redPoint

	if not topRightValid then
		StopRedPointShake()
		topRightGui = nil
		sevenDaysButtonContainer = nil
		openButton = nil
		redPoint = nil
		redPointOriginalPos = nil
	end

	if not sevenDaysValid then
		sevenDaysGui = nil
		sevenDaysBg = nil
		blackBg = nil
		closeButton = nil
		nextRewardLabel = nil
		unlockAllButton = nil
		rewardFrames = {}
	end

	topRightGui = SafeWaitForChild(playerGui, "TopRightGui", 5)
	if topRightGui then
		local topRightBg = topRightGui:FindFirstChild("Bg")
		sevenDaysButtonContainer = topRightBg and topRightBg:FindFirstChild("SevenDays")
		openButton = sevenDaysButtonContainer and sevenDaysButtonContainer:FindFirstChild("Button")
		redPoint = sevenDaysButtonContainer and sevenDaysButtonContainer:FindFirstChild("RedPoint")
		if redPoint and redPoint ~= previousRedPoint then
			redPointOriginalPos = redPoint.Position
			redPoint.Visible = false
		elseif redPoint and not redPointOriginalPos then
			redPointOriginalPos = redPoint.Position
		end
	end

	sevenDaysGui = SafeWaitForChild(playerGui, "SevenDays", 5)
	if not sevenDaysGui then
		warn("[SevenDaysDisplay] SevenDays GUI未找到")
		return false
	end

	sevenDaysBg = sevenDaysGui:FindFirstChild("Bg")
	blackBg = sevenDaysGui:FindFirstChild("BlackBg")
	if not sevenDaysBg then
		warn("[SevenDaysDisplay] SevenDays Bg未找到")
		return false
	end

	local title = sevenDaysBg:FindFirstChild("Title")
	closeButton = title and title:FindFirstChild("CloseButton")
	nextRewardLabel = sevenDaysBg:FindFirstChild("NextReward")
	unlockAllButton = sevenDaysBg:FindFirstChild("UnlockAll")

	rewardFrames = {}
	for day = 1, SevenDaysConfig.MaxDays do
		local frameName = string.format("Reward%02d", day)
		local rewardFrame = sevenDaysBg:FindFirstChild(frameName)
		if rewardFrame then
			rewardFrames[day] = {
				Frame = rewardFrame,
				DayNum = rewardFrame:FindFirstChild("DayNum"),
				ClaimButton = rewardFrame:FindFirstChild("Claim"),
				Claimed = rewardFrame:FindFirstChild("Claimed"),
				Bg = rewardFrame:FindFirstChild("Bg"),
			}
		end
	end

	if sevenDaysBg and sevenDaysBg ~= previousSevenDaysBg then
		local scale = EnsurePanelScale()
		if scale then
			scale.Scale = 1
		end
		sevenDaysBg.Visible = false
		if blackBg then
			blackBg.Visible = false
		end
	end

	return true
end

local function UpdateFeatureVisibility()
	if not IsDescendantOfPlayerGui(sevenDaysButtonContainer) or not IsDescendantOfPlayerGui(sevenDaysBg) then
		InitializeUI()
		BindButtons()
		BindRewardButtons()
	end

	local unlocked = player:GetAttribute("SevenDaysUnlocked")
	if unlocked == nil then
		unlocked = true
	end
	unlocked = unlocked == true
	if sevenDaysButtonContainer then
		sevenDaysButtonContainer.Visible = unlocked
	end
	if not unlocked and sevenDaysBg then
		CancelPanelTweens()
		local scale = EnsurePanelScale()
		if scale then
			scale.Scale = 1
		end
		sevenDaysBg.Visible = false
		if blackBg then
			blackBg.Visible = false
		end
	end
	if not unlocked and blackBg then
		blackBg.Visible = false
	end
	if not unlocked and redPoint then
		redPoint.Visible = false
		StopRedPointShake()
	elseif unlocked and cachedData then
		UpdateRedPoint(cachedData)
	end
end

local function BindCampaignEvents()
	if campaignEventsBound then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
	if not eventsFolder then
		return false
	end

	local campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
	if not campaignEvents then
		campaignEvents = eventsFolder:WaitForChild("CampaignEvents", 5)
	end
	if not campaignEvents then
		return false
	end

	local stateUpdateEvent = campaignEvents:FindFirstChild("CampaignStateUpdate")
	local progressEvent = campaignEvents:FindFirstChild("StageProgress")

	if stateUpdateEvent then
		stateUpdateEvent.OnClientEvent:Connect(function(state, stageNum, _chapter, totalStagesInChapter)
			if type(totalStagesInChapter) == "number" then
				lastCampaignTotalStages = totalStagesInChapter
			elseif state == "Victory" and type(stageNum) == "number" then
				lastCampaignTotalStages = stageNum
			end
		end)
	end

	if progressEvent then
		progressEvent.OnClientEvent:Connect(function(stageNum, result)
			if result ~= "Clear" then
				return
			end

			if type(stageNum) ~= "number" then
				stageNum = tonumber(stageNum)
			end

			local totalStages = tonumber(lastCampaignTotalStages)
			if totalStages and stageNum and stageNum >= totalStages then
				if player:GetAttribute("SevenDaysUnlocked") ~= true then
					player:SetAttribute("SevenDaysUnlocked", true)
				end
				UpdateFeatureVisibility()
			end
		end)
	end

	campaignEventsBound = true
	return true
end

local function UpdateCountdownLabel()
	if not nextRewardLabel or not nextRewardLabel:IsA("TextLabel") then
		return
	end

	local now = os.time() + serverTimeOffset
	local remaining = math.max(0, (tonumber(nextRefreshTime) or 0) - now)
	local hours = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)
	nextRewardLabel.Text = string.format("Refresh In:%02d:%02d", hours, minutes)

	if remaining <= 0 and not refreshRequested then
		refreshRequested = true
		if requestDataEvent then
			requestDataEvent:FireServer(false)
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

local function UpdateRewardStates(data)
	if not data then
		return
	end

	local unlockedDays = tonumber(data.UnlockedDays) or 0
	local claimedDays = type(data.ClaimedDays) == "table" and data.ClaimedDays or {}
	local claimedCount = 0

	for day = 1, SevenDaysConfig.MaxDays do
		if claimedDays[day] == true then
			claimedCount += 1
		end
	end

	for day = 1, SevenDaysConfig.MaxDays do
		local info = rewardFrames[day]
		if info then
			local claimed = claimedDays[day] == true
			local unlocked = day <= unlockedDays

			if info.DayNum then
				info.DayNum.Visible = (not claimed) and (not unlocked)
			end
			if info.ClaimButton then
				info.ClaimButton.Visible = (not claimed) and unlocked
			end
			if info.Claimed then
				info.Claimed.Visible = claimed
			end
			if info.Bg then
				info.Bg.Visible = claimed
			end
		end
	end

	if unlockAllButton then
		local unlockedAll = unlockedDays >= SevenDaysConfig.MaxDays
		local hasUnclaimed = claimedCount < SevenDaysConfig.MaxDays
		local shouldHide = (data.PendingReset == true) or (unlockedAll and hasUnclaimed)
		unlockAllButton.Visible = not shouldHide
	end
end

local function StartRedPointShake()
	if not redPoint or not redPoint.Visible then
		return
	end
	if redPointShakeToken then
		return
	end

	redPointOriginalPos = redPointOriginalPos or redPoint.Position
	local token = {}
	redPointShakeToken = token

	task.spawn(function()
		while redPoint and redPoint.Visible and redPointShakeToken == token do
			local offsetRight = UDim2.new(0, 4, 0, 0)
			local offsetLeft = UDim2.new(0, -4, 0, 0)
			local tweenRight = TweenService:Create(
				redPoint,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = redPointOriginalPos + offsetRight }
			)
			local tweenLeft = TweenService:Create(
				redPoint,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = redPointOriginalPos + offsetLeft }
			)
			local tweenCenter = TweenService:Create(
				redPoint,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = redPointOriginalPos }
			)

			tweenRight:Play()
			tweenRight.Completed:Wait()
			if redPointShakeToken ~= token then
				break
			end
			tweenLeft:Play()
			tweenLeft.Completed:Wait()
			if redPointShakeToken ~= token then
				break
			end
			tweenCenter:Play()
			tweenCenter.Completed:Wait()
			if redPointShakeToken ~= token then
				break
			end
			task.wait(2)
		end

		if redPoint and redPointOriginalPos then
			redPoint.Position = redPointOriginalPos
		end
	end)
end

StopRedPointShake = function()
	if redPointShakeToken then
		redPointShakeToken = nil
	end
	if redPoint and redPointOriginalPos then
		redPoint.Position = redPointOriginalPos
	end
end

UpdateRedPoint = function(data)
	if not redPoint then
		return
	end

	local unlocked = player:GetAttribute("SevenDaysUnlocked") == true
	local show = false

	if unlocked and data then
		local unlockedDays = tonumber(data.UnlockedDays) or 0
		local claimedDays = type(data.ClaimedDays) == "table" and data.ClaimedDays or {}

		for day = 1, unlockedDays do
			if not claimedDays[day] then
				show = true
				break
			end
		end
	end

	redPoint.Visible = show
	if show then
		StartRedPointShake()
	else
		StopRedPointShake()
	end
end

local function OpenSevenDays()
	if not sevenDaysBg then
		return
	end
	if player:GetAttribute("SevenDaysUnlocked") ~= true then
		return
	end

	sevenDaysBg.Visible = true
	if blackBg then
		blackBg.Visible = true
	end

	if requestDataEvent then
		requestDataEvent:FireServer(true)
	end

	StartCountdown()
	if cachedData then
		UpdateRewardStates(cachedData)
		UpdateRedPoint(cachedData)
		UpdateCountdownLabel()
	end
end

local function CloseSevenDays()
	PlayPanelClose()
	StopCountdown()
end

local function OnClaimButtonClicked(day)
	if claimLocks[day] then
		return
	end

	local data = cachedData
	local unlockedDays = data and tonumber(data.UnlockedDays) or 0
	local claimedDays = data and data.ClaimedDays or {}

	if day > unlockedDays or claimedDays[day] == true then
		return
	end

	if claimRewardEvent then
		claimLocks[day] = true
		claimRewardEvent:FireServer(day)
		task.delay(2, function()
			if claimLocks[day] then
				claimLocks[day] = nil
			end
		end)
	end
end

BindRewardButtons = function()
	LoadButtonEffectHelper()

	for day = 1, SevenDaysConfig.MaxDays do
		local info = rewardFrames[day]
		if info and info.ClaimButton and (info.ClaimButton:IsA("TextButton") or info.ClaimButton:IsA("ImageButton")) then
			local button = info.ClaimButton
			if not boundRewardButtons[button] then
				if ButtonEffectHelper then
					ButtonEffectHelper.AddClickEffect(button, {
						OnClick = function()
							OnClaimButtonClicked(day)
						end
					})
				else
					button.MouseButton1Click:Connect(function()
						OnClaimButtonClicked(day)
					end)
				end
				boundRewardButtons[button] = true
			end
		end
	end
end

local function PromptUnlockAll()
	if unlockAllInProgress then
		return
	end

	local productId = SevenDaysConfig.UnlockAllProductId
	if not productId then
		return
	end

	unlockAllInProgress = true
	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not success then
		unlockAllInProgress = false
		warn("[SevenDaysDisplay] PromptProductPurchase失败:", err)
	end
end

BindButtons = function()
	LoadButtonEffectHelper()

	if openButton and (openButton:IsA("TextButton") or openButton:IsA("ImageButton")) then
		if not boundButtons[openButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(openButton, { OnClick = OpenSevenDays })
			else
				openButton.MouseButton1Click:Connect(OpenSevenDays)
			end
			boundButtons[openButton] = true
		end
	end

	if closeButton and (closeButton:IsA("TextButton") or closeButton:IsA("ImageButton")) then
		if not boundButtons[closeButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(closeButton, { OnClick = CloseSevenDays })
			else
				closeButton.MouseButton1Click:Connect(CloseSevenDays)
			end
			boundButtons[closeButton] = true
		end
	end

	if unlockAllButton and (unlockAllButton:IsA("TextButton") or unlockAllButton:IsA("ImageButton")) then
		if not boundButtons[unlockAllButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(unlockAllButton, { OnClick = PromptUnlockAll })
			else
				unlockAllButton.MouseButton1Click:Connect(PromptUnlockAll)
			end
			boundButtons[unlockAllButton] = true
		end
	end
end

local function OnSevenDaysData(data)
	if type(data) ~= "table" then
		return
	end

	local normalizedClaimed = NormalizeClaimedDaysTable(data.ClaimedDays)
	local dataRound = tonumber(data.Round)
	local cachedRound = cachedData and tonumber(cachedData.Round)
	if cachedRound and dataRound and cachedRound == dataRound then
		local previousClaimed = NormalizeClaimedDaysTable(cachedData.ClaimedDays)
		for day, claimed in pairs(previousClaimed) do
			if claimed == true then
				normalizedClaimed[day] = true
			end
		end
	end
	data.ClaimedDays = normalizedClaimed

	local previousRound = cachedData and tonumber(cachedData.Round)
	local newRound = tonumber(data.Round)
	if previousRound and newRound and previousRound ~= newRound then
		unlockAllInProgress = false
	end

	local unlockedDaysNow = tonumber(data.UnlockedDays)
	if unlockedDaysNow and unlockedDaysNow >= SevenDaysConfig.MaxDays then
		unlockAllInProgress = false
	end

	cachedData = data
	nextRefreshTime = tonumber(data.NextRefreshTime) or 0
	if type(data.ServerTime) == "number" then
		serverTimeOffset = data.ServerTime - os.time()
	end

	UpdateRewardStates(data)
	UpdateRedPoint(data)
	if sevenDaysBg and sevenDaysBg.Visible then
		UpdateCountdownLabel()
	end
end

local function OnClaimResult(success, message, dayIndex)
	if dayIndex then
		claimLocks[dayIndex] = nil
	else
		claimLocks = {}
	end

	local tipsSystem = _G.TipsSystem
	if success then
		local day = dayIndex
		if type(day) ~= "number" then
			day = tonumber(day)
		end
		if day and cachedData then
			cachedData.ClaimedDays = NormalizeClaimedDaysTable(cachedData.ClaimedDays)
			cachedData.ClaimedDays[day] = true
			if not cachedData.UnlockedDays or day > cachedData.UnlockedDays then
				cachedData.UnlockedDays = day
			end

			local claimedCount = 0
			for index = 1, SevenDaysConfig.MaxDays do
				if cachedData.ClaimedDays[index] == true then
					claimedCount += 1
				end
			end
			if claimedCount >= SevenDaysConfig.MaxDays then
				cachedData.PendingReset = true
			end

			UpdateRewardStates(cachedData)
			UpdateRedPoint(cachedData)
		end

		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Reward Claimed!")
		elseif tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Reward Claimed!")
		end
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "领取失败")
		end
	end
end

local function BindData()
	if dataBound or not sevenDaysDataEvent then
		return
	end

	sevenDaysDataEvent.OnClientEvent:Connect(OnSevenDaysData)
	claimResultEvent.OnClientEvent:Connect(OnClaimResult)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()
	BindCampaignEvents()

	if uiReady then
		BindButtons()
		BindRewardButtons()
		UpdateFeatureVisibility()
	end
	if eventsReady then
		BindData()
		if requestDataEvent then
			requestDataEvent:FireServer(false)
		end
	end

	return eventsReady and uiReady
end

function SevenDaysDisplay.Initialize()
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

	player:GetAttributeChangedSignal("SevenDaysUnlocked"):Connect(UpdateFeatureVisibility)

	playerGui.ChildAdded:Connect(function(child)
		if not child then
			return
		end
		if child.Name ~= "TopRightGui" and child.Name ~= "SevenDays" then
			return
		end

		task.spawn(function()
			task.wait()
			TryInitialize()
			UpdateFeatureVisibility()
			if cachedData then
				UpdateRewardStates(cachedData)
				UpdateRedPoint(cachedData)
				if sevenDaysBg and sevenDaysBg.Visible then
					UpdateCountdownLabel()
				end
			end
		end)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
		if userId == player.UserId and productId == SevenDaysConfig.UnlockAllProductId then
			unlockAllInProgress = false
		end
	end)
end

SevenDaysDisplay.Initialize()

return SevenDaysDisplay
