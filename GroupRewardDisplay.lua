--[[
Script Name: GroupRewardDisplay
Script Type: LocalScript (Client UI)
Script Location: StarterPlayer/StarterPlayerScripts/UI/GroupRewardDisplay
Version: V4.9
]]

local GroupRewardDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local groupRewardEvents = nil
local requestDataEvent = nil
local groupRewardDataEvent = nil
local claimRewardEvent = nil
local claimResultEvent = nil

local topRightGui = nil
local groupRewardButtonContainer = nil
local openButton = nil

local groupRewardGui = nil
local groupRewardBg = nil
local closeButton = nil
local claimButton = nil
local claimedLabel = nil

local cachedClaimed = nil
local claimLock = false

local ButtonEffectHelper = nil
local boundButtons = {}
local dataBound = false
local BindButtons = nil
local UpdateClaimState = nil
local UpdateFeatureVisibility = nil

-- 弹框动画配置（仅Bg）
local POPUP_OPEN_START_SCALE = 0.86
local POPUP_OPEN_OVERSHOOT_SCALE = 1.10
local POPUP_OPEN_DURATION_A = 0.18
local POPUP_OPEN_DURATION_B = 0.10
local POPUP_CLOSE_OVERSHOOT_SCALE = 1.12
local POPUP_CLOSE_END_SCALE = 0.78
local POPUP_CLOSE_DURATION_A = 0.08
local POPUP_CLOSE_DURATION_B = 0.12

local popupScale = nil
local popupOpenTweenA = nil
local popupOpenTweenB = nil
local popupCloseTweenA = nil
local popupCloseTweenB = nil
local popupAnimating = false

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

	warn("[GroupRewardDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function EnsurePopupScale()
	if not groupRewardBg then
		return nil
	end

	if not popupScale or popupScale.Parent ~= groupRewardBg then
		popupScale = groupRewardBg:FindFirstChild("PopupScale")
		if not popupScale then
			popupScale = Instance.new("UIScale")
			popupScale.Name = "PopupScale"
			popupScale.Scale = 1
			popupScale.Parent = groupRewardBg
		end
	end

	return popupScale
end

local function CancelPopupTweens()
	local tweens = {popupOpenTweenA, popupOpenTweenB, popupCloseTweenA, popupCloseTweenB}
	for _, tween in ipairs(tweens) do
		if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
			tween:Cancel()
		end
	end
end

local function PlayPopupOpen()
	if not groupRewardBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		groupRewardBg.Visible = true
		return true
	end

	if groupRewardBg.Visible and not popupAnimating then
		return true
	end

	CancelPopupTweens()
	popupAnimating = true

	groupRewardBg.Visible = true
	scale.Scale = POPUP_OPEN_START_SCALE

	popupOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_OPEN_OVERSHOOT_SCALE}
	)
	popupOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1}
	)

	local connA
	connA = popupOpenTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			popupOpenTweenB:Play()
		end
	end)

	local connB
	connB = popupOpenTweenB.Completed:Connect(function()
		connB:Disconnect()
		popupAnimating = false
		scale.Scale = 1
	end)

	popupOpenTweenA:Play()
	return true
end

local function PlayPopupClose()
	if not groupRewardBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		groupRewardBg.Visible = false
		return true
	end

	if not groupRewardBg.Visible and not popupAnimating then
		return true
	end

	CancelPopupTweens()
	popupAnimating = true

	popupCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_CLOSE_OVERSHOOT_SCALE}
	)
	popupCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = POPUP_CLOSE_END_SCALE}
	)

	local connA
	connA = popupCloseTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			popupCloseTweenB:Play()
		end
	end)

	local connB
	connB = popupCloseTweenB.Completed:Connect(function()
		connB:Disconnect()
		groupRewardBg.Visible = false
		scale.Scale = 1
		popupAnimating = false
	end)

	popupCloseTweenA:Play()
	return true
end

local function InitializeEvents()
	if groupRewardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[GroupRewardDisplay] Events folder not found")
		return false
	end

	groupRewardEvents = eventsFolder:WaitForChild("GroupRewardEvents", 10)
	if not groupRewardEvents then
		warn("[GroupRewardDisplay] GroupRewardEvents not found")
		return false
	end

	requestDataEvent = groupRewardEvents:WaitForChild("RequestGroupRewardData", 5)
	groupRewardDataEvent = groupRewardEvents:WaitForChild("GroupRewardData", 5)
	claimRewardEvent = groupRewardEvents:WaitForChild("ClaimGroupReward", 5)
	claimResultEvent = groupRewardEvents:WaitForChild("ClaimGroupRewardResult", 5)

	if not (requestDataEvent and groupRewardDataEvent and claimRewardEvent and claimResultEvent) then
		warn("[GroupRewardDisplay] GroupReward events missing")
		return false
	end

	return true
end

local function InitializeUI()
	local topRightValid = IsDescendantOfPlayerGui(groupRewardButtonContainer)
	local rewardValid = IsDescendantOfPlayerGui(groupRewardBg)
	if topRightValid and rewardValid then
		return true
	end

	if not topRightValid then
		topRightGui = nil
		groupRewardButtonContainer = nil
		openButton = nil
	end

	if not rewardValid then
		groupRewardGui = nil
		groupRewardBg = nil
		closeButton = nil
		claimButton = nil
		claimedLabel = nil
	end

	topRightGui = SafeWaitForChild(playerGui, "TopRightGui", 5)
	if topRightGui then
		local topRightBg = topRightGui:FindFirstChild("Bg")
		groupRewardButtonContainer = topRightBg and topRightBg:FindFirstChild("GroupReward")
		openButton = groupRewardButtonContainer and groupRewardButtonContainer:FindFirstChild("Button")
	end

	groupRewardGui = SafeWaitForChild(playerGui, "GroupReward", 5)
	if not groupRewardGui then
		warn("[GroupRewardDisplay] GroupReward GUI not found")
		return false
	end

	groupRewardBg = groupRewardGui:FindFirstChild("Bg")
	if not groupRewardBg then
		warn("[GroupRewardDisplay] GroupReward Bg not found")
		return false
	end

	local title = groupRewardBg:FindFirstChild("Title")
	closeButton = title and title:FindFirstChild("CloseButton")
	claimButton = groupRewardBg:FindFirstChild("Claim")
	claimedLabel = groupRewardBg:FindFirstChild("Claimed")

	if groupRewardBg then
		groupRewardBg.Visible = false
	end

	return true
end

UpdateClaimState = function(claimed)
	if claimButton then
		claimButton.Visible = not claimed
	end
	if claimedLabel then
		claimedLabel.Visible = claimed
	end
end

UpdateFeatureVisibility = function()
	if not IsDescendantOfPlayerGui(groupRewardButtonContainer) or not IsDescendantOfPlayerGui(groupRewardBg) then
		InitializeUI()
		BindButtons()
	end

	local claimed = player:GetAttribute("GroupRewardClaimed") == true
	if groupRewardButtonContainer then
		groupRewardButtonContainer.Visible = not claimed
	end
	if claimed and groupRewardBg then
		CancelPopupTweens()
		local scale = EnsurePopupScale()
		if scale then
			scale.Scale = 1
		end
		groupRewardBg.Visible = false
	end

	if cachedClaimed ~= nil then
		UpdateClaimState(cachedClaimed)
	end
end

local function OpenGroupReward()
	if player:GetAttribute("GroupRewardClaimed") == true then
		return
	end

	if not PlayPopupOpen() then
		return
	end

	if requestDataEvent then
		requestDataEvent:FireServer()
	end

	if cachedClaimed ~= nil then
		UpdateClaimState(cachedClaimed)
	end
end

local function CloseGroupReward()
	PlayPopupClose()
end

local function OnClaimButtonClicked()
	if claimLock or cachedClaimed == true then
		return
	end

	if claimRewardEvent then
		claimLock = true
		claimRewardEvent:FireServer()
		task.delay(2, function()
			if claimLock then
				claimLock = false
			end
		end)
	end
end

BindButtons = function()
	LoadButtonEffectHelper()

	if openButton and (openButton:IsA("TextButton") or openButton:IsA("ImageButton")) then
		if not boundButtons[openButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(openButton, { OnClick = OpenGroupReward })
			else
				openButton.MouseButton1Click:Connect(OpenGroupReward)
			end
			boundButtons[openButton] = true
		end
	end

	if closeButton and (closeButton:IsA("TextButton") or closeButton:IsA("ImageButton")) then
		if not boundButtons[closeButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(closeButton, { OnClick = CloseGroupReward })
			else
				closeButton.MouseButton1Click:Connect(CloseGroupReward)
			end
			boundButtons[closeButton] = true
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

local function OnGroupRewardData(data)
	local claimed = false
	if type(data) == "table" then
		claimed = data.Claimed == true
	elseif type(data) == "boolean" then
		claimed = data == true
	end

	cachedClaimed = claimed
	UpdateClaimState(claimed)
	UpdateFeatureVisibility()
end

local function OnClaimResult(success, message, claimed)
	claimLock = false

	if type(claimed) == "boolean" then
		cachedClaimed = claimed
		UpdateClaimState(claimed)
		UpdateFeatureVisibility()
	end

	local tipsSystem = _G.TipsSystem
	if success then
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Claim Successful!")
		end
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Join the group for rewards!")
		end
	end
end

local function BindData()
	if dataBound or not groupRewardDataEvent then
		return
	end

	groupRewardDataEvent.OnClientEvent:Connect(OnGroupRewardData)
	claimResultEvent.OnClientEvent:Connect(OnClaimResult)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if uiReady then
		BindButtons()
		UpdateFeatureVisibility()
	end
	if eventsReady then
		BindData()
		if requestDataEvent then
			requestDataEvent:FireServer()
		end
	end

	return eventsReady and uiReady
end

function GroupRewardDisplay.Initialize()
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

	player:GetAttributeChangedSignal("GroupRewardClaimed"):Connect(UpdateFeatureVisibility)

	playerGui.ChildAdded:Connect(function(child)
		if not child then
			return
		end
		if child.Name ~= "TopRightGui" and child.Name ~= "GroupReward" then
			return
		end

		task.spawn(function()
			task.wait()
			TryInitialize()
			UpdateFeatureVisibility()
			if cachedClaimed ~= nil then
				UpdateClaimState(cachedClaimed)
			end
		end)
	end)
end

GroupRewardDisplay.Initialize()

return GroupRewardDisplay
