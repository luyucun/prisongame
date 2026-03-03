--[[
=====================================================
脚本名称：TipsSystemController
脚本类型：本地脚本（客户端）
脚本位置：StarterPlayer/StarterPlayerScripts/Controllers/TipsSystemController.lua
=====================================================
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MIN_TIPS_DISPLAY_ORDER = 120

local tipsGui = playerGui:WaitForChild("TipsSystem", 10)
if not tipsGui then
	warn("[TipsSystemController] 未找到 TipsSystem 界面")
	return
end

if tipsGui:IsA("ScreenGui") and tipsGui.DisplayOrder < MIN_TIPS_DISPLAY_ORDER then
	tipsGui.DisplayOrder = MIN_TIPS_DISPLAY_ORDER
end

local frame = tipsGui:WaitForChild("Frame", 5)
if not frame then
	warn("[TipsSystemController] 未找到 Frame 节点")
	return
end

local errorText = frame:WaitForChild("ErrorText", 5)
if not errorText then
	warn("[TipsSystemController] 未找到 ErrorText 节点")
	return
end

local defaultTextColor = errorText.TextColor3

local powerFrame = tipsGui:FindFirstChild("Power")
local powerText = nil
if powerFrame then
	powerText = powerFrame:FindFirstChild("PowerText")
	if not powerText then
		warn("[TipsSystemController] 未找到 PowerText 节点")
	end
	powerFrame.Visible = false
else
	warn("[TipsSystemController] 未找到 Power 节点")
end

local refreshTips = tipsGui:FindFirstChild("RefreshTips")
if not refreshTips then
	warn("[TipsSystemController] RefreshTips node missing")
end

local refreshTargetPosition = refreshTips and refreshTips.Position or nil
local refreshStartOffset = 24
local refreshOvershootOffset = 8
local refreshShowDuration = 6
local refreshTweenDurationA = 0.32
local refreshTweenDurationB = 0.18

local refreshToken = 0
local refreshTweenA = nil
local refreshTweenB = nil

if refreshTips then
	refreshTips.Visible = false
end

local buyTips = tipsGui:FindFirstChild("BuyTips")
if not buyTips then
	warn("[TipsSystemController] BuyTips node missing")
end

local buyTargetPosition = buyTips and buyTips.Position or nil
local buyShowDuration = 2.5
local buyTweenDurationA = refreshTweenDurationA
local buyTweenDurationB = refreshTweenDurationB
local buyToken = 0
local buyTweenA = nil
local buyTweenB = nil
local buyTipLabel = buyTips and (
	buyTips:FindFirstChild("TipText", true)
	or buyTips:FindFirstChild("Text", true)
	or buyTips:FindFirstChild("ErrorText", true)
	or buyTips:FindFirstChildWhichIsA("TextLabel", true)
) or nil

if buyTips then
	buyTips.Visible = false
end

local rebirthTips = tipsGui:FindFirstChild("RebirthTips")
if not rebirthTips then
	warn("[TipsSystemController] RebirthTips node missing")
end

local rebirthTargetPosition = rebirthTips and rebirthTips.Position or nil
local rebirthShowDuration = 2
local rebirthTweenDurationA = refreshTweenDurationA
local rebirthTweenDurationB = refreshTweenDurationB
local rebirthToken = 0
local rebirthTweenA = nil
local rebirthTweenB = nil
local rebirthTipLabel = rebirthTips and (
	rebirthTips:FindFirstChild("TipText", true)
	or rebirthTips:FindFirstChild("Text", true)
	or rebirthTips:FindFirstChild("ErrorText", true)
	or rebirthTips:FindFirstChildWhichIsA("TextLabel", true)
) or nil
local rebirthTipDefaultText = (rebirthTipLabel and rebirthTipLabel:IsA("TextLabel")) and rebirthTipLabel.Text or nil

if rebirthTips then
	rebirthTips.Visible = false
end

local function EnsureTipsAboveRebirthPopup()
	if not tipsGui or not tipsGui:IsA("ScreenGui") then
		return
	end

	local rebirthGui = playerGui:FindFirstChild("Rebirth")
	if rebirthGui and rebirthGui:IsA("ScreenGui") then
		local requiredDisplayOrder = (rebirthGui.DisplayOrder or 0) + 1
		if tipsGui.DisplayOrder < requiredDisplayOrder then
			tipsGui.DisplayOrder = requiredDisplayOrder
		end
	end
end

local targetPosition = frame.Position
local startPosition = UDim2.new(0.5, 0, 0.5, 0)
local showDuration = 1
local tweenDuration = 0.25

local showToken = 0
local activeTween = nil

local powerToken = 0
local powerTween = nil
local powerValue = nil
local powerConnection = nil
local powerAnimDuration = 0.8

frame.Visible = false

local LIKE_HOME_ID_ATTR = "LikeHomeId"
local LIKE_OWNER_ATTR = "LikeOwnerUserId"

local function IsValidLikeOwnerUserId(userId)
	return type(userId) == "number" and userId ~= 0 and userId == math.floor(userId)
end

local watchedLikePrompts = {}
local likedOwnerUserIdSet = {}

local function NormalizeLikeOwnerUserId(userId)
	if not IsValidLikeOwnerUserId(userId) then
		return nil
	end
	return math.floor(userId)
end

local function HasLikedOwner(userId)
	local normalizedUserId = NormalizeLikeOwnerUserId(userId)
	if not normalizedUserId then
		return false
	end

	return likedOwnerUserIdSet[normalizedUserId] == true
end

local function AddLikedOwner(userId)
	local normalizedUserId = NormalizeLikeOwnerUserId(userId)
	if not normalizedUserId then
		return false
	end
	if likedOwnerUserIdSet[normalizedUserId] then
		return false
	end

	likedOwnerUserIdSet[normalizedUserId] = true
	return true
end

local function ReplaceLikedOwners(payload)
	for key in pairs(likedOwnerUserIdSet) do
		likedOwnerUserIdSet[key] = nil
	end

	if type(payload) ~= "table" then
		return
	end

	for _, rawUserId in ipairs(payload) do
		AddLikedOwner(rawUserId)
	end

	if #payload == 0 then
		for rawUserId, state in pairs(payload) do
			if state == true then
				AddLikedOwner(rawUserId)
			end
		end
	end
end

local function StopCurrentTip()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	frame.Visible = false
end

local function StopPowerTip()
	if powerTween then
		powerTween:Cancel()
		powerTween = nil
	end
	if powerConnection then
		powerConnection:Disconnect()
		powerConnection = nil
	end
	if powerValue then
		powerValue:Destroy()
		powerValue = nil
	end
	if powerFrame then
		powerFrame.Visible = false
	end
end

local function StopRefreshTip()
	if refreshTweenA then
		refreshTweenA:Cancel()
		refreshTweenA = nil
	end
	if refreshTweenB then
		refreshTweenB:Cancel()
		refreshTweenB = nil
	end
	if refreshTips then
		refreshTips.Visible = false
		if refreshTargetPosition then
			refreshTips.Position = refreshTargetPosition
		end
	end
end

local function StopBuyTip()
	if buyTweenA then
		buyTweenA:Cancel()
		buyTweenA = nil
	end
	if buyTweenB then
		buyTweenB:Cancel()
		buyTweenB = nil
	end
	if buyTips then
		buyTips.Visible = false
		if buyTargetPosition then
			buyTips.Position = buyTargetPosition
		end
	end
end

local function StopRebirthTip()
	if rebirthTweenA then
		rebirthTweenA:Cancel()
		rebirthTweenA = nil
	end
	if rebirthTweenB then
		rebirthTweenB:Cancel()
		rebirthTweenB = nil
	end
	if rebirthTips then
		rebirthTips.Visible = false
		if rebirthTargetPosition then
			rebirthTips.Position = rebirthTargetPosition
		end
	end
end

local function PlayRefreshTipSound()
	local soundController = _G.SoundController
	if soundController and soundController.PlaySFX then
		soundController.PlaySFX("ShopRefresh")
	end
end

local function ShowRefreshTip()
	if not refreshTips or not refreshTargetPosition then
		return
	end

	refreshToken = refreshToken + 1
	local token = refreshToken

	StopRefreshTip()

	local startPos = UDim2.new(
		refreshTargetPosition.X.Scale, refreshTargetPosition.X.Offset,
		refreshTargetPosition.Y.Scale, refreshTargetPosition.Y.Offset + refreshStartOffset
	)
	local overshootPos = UDim2.new(
		refreshTargetPosition.X.Scale, refreshTargetPosition.X.Offset,
		refreshTargetPosition.Y.Scale, refreshTargetPosition.Y.Offset - refreshOvershootOffset
	)

	refreshTips.Position = startPos
	refreshTips.Visible = true

	refreshTweenA = TweenService:Create(
		refreshTips,
		TweenInfo.new(refreshTweenDurationA, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = overshootPos }
	)
	refreshTweenB = TweenService:Create(
		refreshTips,
		TweenInfo.new(refreshTweenDurationB, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = refreshTargetPosition }
	)

	refreshTweenA.Completed:Connect(function(state)
		if token ~= refreshToken then
			return
		end
		if state == Enum.PlaybackState.Completed and refreshTweenB then
			refreshTweenB:Play()
		end
	end)

	refreshTweenA:Play()
	PlayRefreshTipSound()

	task.delay(refreshShowDuration, function()
		if token ~= refreshToken then
			return
		end
		if refreshTips then
			refreshTips.Visible = false
			refreshTips.Position = refreshTargetPosition
		end
	end)
end

local function ShowTip(text, color)
	if not text or text == "" then
		return
	end

	showToken = showToken + 1
	local token = showToken

	StopCurrentTip()

	errorText.Text = text
	errorText.TextColor3 = color or defaultTextColor
	frame.Position = startPosition
	frame.Visible = true

	activeTween = TweenService:Create(
		frame,
		TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = targetPosition }
	)
	activeTween:Play()

	task.delay(showDuration, function()
		if token ~= showToken then
			return
		end
		frame.Visible = false
	end)
end

local function ShowBuyTip(text)
	if not text or text == "" then
		return
	end

	if not buyTips or not buyTargetPosition then
		ShowTip(text, Color3.fromRGB(0, 255, 0))
		return
	end

	buyToken = buyToken + 1
	local token = buyToken

	StopBuyTip()

	if buyTipLabel and buyTipLabel:IsA("TextLabel") then
		buyTipLabel.Text = text
	end

	local startPos = UDim2.new(
		buyTargetPosition.X.Scale, buyTargetPosition.X.Offset,
		buyTargetPosition.Y.Scale, buyTargetPosition.Y.Offset + refreshStartOffset
	)
	local overshootPos = UDim2.new(
		buyTargetPosition.X.Scale, buyTargetPosition.X.Offset,
		buyTargetPosition.Y.Scale, buyTargetPosition.Y.Offset - refreshOvershootOffset
	)

	buyTips.Position = startPos
	buyTips.Visible = true

	buyTweenA = TweenService:Create(
		buyTips,
		TweenInfo.new(buyTweenDurationA, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = overshootPos }
	)
	buyTweenB = TweenService:Create(
		buyTips,
		TweenInfo.new(buyTweenDurationB, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = buyTargetPosition }
	)

	buyTweenA.Completed:Connect(function(state)
		if token ~= buyToken then
			return
		end
		if state == Enum.PlaybackState.Completed and buyTweenB then
			buyTweenB:Play()
		end
	end)

	buyTweenA:Play()

	task.delay(buyShowDuration, function()
		if token ~= buyToken then
			return
		end
		if buyTips then
			buyTips.Visible = false
			buyTips.Position = buyTargetPosition
		end
	end)
end

local function ShowRebirthTip(customText)
	if not rebirthTips or not rebirthTargetPosition then
		return
	end

	EnsureTipsAboveRebirthPopup()

	rebirthToken = rebirthToken + 1
	local token = rebirthToken

	StopRebirthTip()

	if rebirthTipLabel and rebirthTipLabel:IsA("TextLabel") then
		if type(customText) == "string" and customText ~= "" then
			rebirthTipLabel.Text = customText
		elseif type(rebirthTipDefaultText) == "string" then
			rebirthTipLabel.Text = rebirthTipDefaultText
		end
	end

	local startPos = UDim2.new(
		rebirthTargetPosition.X.Scale, rebirthTargetPosition.X.Offset,
		rebirthTargetPosition.Y.Scale, rebirthTargetPosition.Y.Offset + refreshStartOffset
	)
	local overshootPos = UDim2.new(
		rebirthTargetPosition.X.Scale, rebirthTargetPosition.X.Offset,
		rebirthTargetPosition.Y.Scale, rebirthTargetPosition.Y.Offset - refreshOvershootOffset
	)

	rebirthTips.Position = startPos
	rebirthTips.Visible = true

	rebirthTweenA = TweenService:Create(
		rebirthTips,
		TweenInfo.new(rebirthTweenDurationA, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = overshootPos }
	)
	rebirthTweenB = TweenService:Create(
		rebirthTips,
		TweenInfo.new(rebirthTweenDurationB, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = rebirthTargetPosition }
	)

	rebirthTweenA.Completed:Connect(function(state)
		if token ~= rebirthToken then
			return
		end
		if state == Enum.PlaybackState.Completed and rebirthTweenB then
			rebirthTweenB:Play()
		end
	end)

	rebirthTweenA:Play()

	task.delay(rebirthShowDuration, function()
		if token ~= rebirthToken then
			return
		end
		if rebirthTips then
			rebirthTips.Visible = false
			rebirthTips.Position = rebirthTargetPosition
		end
		end)
end

local function ShowLikeTip(likerName)
	local safeName = tostring(likerName or "")
	if safeName == "" then
		safeName = "Someone"
	end
	local text = string.format("%s gave you a like!", safeName)
	if rebirthTips and rebirthTargetPosition then
		ShowRebirthTip(text)
	else
		ShowBuyTip(text)
	end
end

local function ApplyLikePromptVisibility(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end

	local homeId = tonumber(prompt:GetAttribute(LIKE_HOME_ID_ATTR))
	if not homeId then
		return
	end

	local ownerUserId = prompt:GetAttribute(LIKE_OWNER_ATTR)
	local shouldEnable = IsValidLikeOwnerUserId(ownerUserId)
		and ownerUserId ~= player.UserId
		and not HasLikedOwner(ownerUserId)
	if prompt.Enabled ~= shouldEnable then
		prompt.Enabled = shouldEnable
	end
end

local function RefreshAllLikePromptVisibility()
	for prompt in pairs(watchedLikePrompts) do
		ApplyLikePromptVisibility(prompt)
	end
end

local function WatchLikePrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	if watchedLikePrompts[prompt] then
		return
	end

	local ownerConn = prompt:GetAttributeChangedSignal(LIKE_OWNER_ATTR):Connect(function()
		ApplyLikePromptVisibility(prompt)
	end)
	local homeConn = prompt:GetAttributeChangedSignal(LIKE_HOME_ID_ATTR):Connect(function()
		ApplyLikePromptVisibility(prompt)
	end)
	local ancestryConn = prompt.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			local state = watchedLikePrompts[prompt]
			watchedLikePrompts[prompt] = nil
			if state then
				if state.ownerConn then
					state.ownerConn:Disconnect()
				end
				if state.homeConn then
					state.homeConn:Disconnect()
				end
				if state.ancestryConn then
					state.ancestryConn:Disconnect()
				end
			end
		end
	end)

	watchedLikePrompts[prompt] = {
		ownerConn = ownerConn,
		homeConn = homeConn,
		ancestryConn = ancestryConn,
	}

	ApplyLikePromptVisibility(prompt)
end

local function StartLikePromptVisibilitySync()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			WatchLikePrompt(descendant)
		end
	end

	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			WatchLikePrompt(descendant)
		end
	end)
end

local function ShouldShowLikePrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return true
	end

	local homeId = tonumber(prompt:GetAttribute(LIKE_HOME_ID_ATTR))
	if not homeId then
		return true
	end

	local ownerUserId = prompt:GetAttribute(LIKE_OWNER_ATTR)
	if not IsValidLikeOwnerUserId(ownerUserId) then
		return false
	end

	return ownerUserId ~= player.UserId and not HasLikedOwner(ownerUserId)
end

local function BindLikePromptShownGuard()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if not ShouldShowLikePrompt(prompt) then
			prompt.Enabled = false
		end
	end)
end

local function BuildPowerText(basePower, deltaValue, isIncrease)
	local sign = isIncrease and "+" or "-"
	local arrow = isIncrease and "↑" or "↓"
	local color = isIncrease and "#00FF00" or "#FF3B30"
	return string.format(
		"<font color=\"#FFFFFF\">%d</font><font color=\"%s\">%s%d%s</font>",
		basePower,
		color,
		sign,
		deltaValue,
		arrow
	)
end

local TipsSystemController = {}

function TipsSystemController.ShowError(text)
	ShowTip(text, defaultTextColor)
end

function TipsSystemController.ShowSuccess(text)
	ShowTip(text, Color3.fromRGB(0, 255, 0))
end

function TipsSystemController.ShowPowerChange(oldPower, newPower)
	if not powerFrame or not powerText then
		return
	end

	oldPower = math.floor(tonumber(oldPower) or 0)
	newPower = math.floor(tonumber(newPower) or 0)
	local delta = newPower - oldPower
	if delta == 0 then
		return
	end

	powerToken = powerToken + 1
	local token = powerToken

	StopPowerTip()

	powerFrame.Visible = true
	powerText.RichText = true

	local isIncrease = delta > 0
	local targetValue = math.abs(delta)

	local function UpdateText(value)
		powerText.Text = BuildPowerText(oldPower, value, isIncrease)
	end

	UpdateText(0)

	powerValue = Instance.new("NumberValue")
	powerValue.Value = 0

	powerTween = TweenService:Create(
		powerValue,
		TweenInfo.new(powerAnimDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = targetValue }
	)

	powerConnection = powerValue.Changed:Connect(function(current)
		if token ~= powerToken then
			return
		end
		UpdateText(math.floor(current + 0.5))
	end)

	powerTween.Completed:Connect(function()
		if token ~= powerToken then
			return
		end
		UpdateText(targetValue)
		StopPowerTip()
	end)

	powerTween:Play()
end

function TipsSystemController.ShowBuyTip(text)
	ShowBuyTip(text)
end

function TipsSystemController.ShowRefreshTip()
	ShowRefreshTip()
end

function TipsSystemController.ShowRebirthTip()
	ShowRebirthTip()
end

function TipsSystemController.ShowLikeTip(likerName)
	ShowLikeTip(likerName)
end

local function BindRefreshTipEvent()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[TipsSystemController] Events folder missing")
		return
	end

	local shopEvents = eventsFolder:WaitForChild("ShopEvents", 10)
	if not shopEvents then
		warn("[TipsSystemController] ShopEvents folder missing")
		return
	end

	local refreshEvent = shopEvents:FindFirstChild("ShopRefreshTip")
	if not refreshEvent then
		refreshEvent = shopEvents:WaitForChild("ShopRefreshTip", 10)
	end

	if refreshEvent and refreshEvent:IsA("RemoteEvent") then
		refreshEvent.OnClientEvent:Connect(function(shopId)
			if shopId == nil or shopId == "UnitShop" then
				ShowRefreshTip()
			end
		end)
	else
		warn("[TipsSystemController] ShopRefreshTip event missing")
	end
end

local function BindRebirthTipEvent()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[TipsSystemController] Events folder missing for rebirth tip")
		return
	end

	local rebirthEvents = eventsFolder:WaitForChild("RebirthEvents", 10)
	if not rebirthEvents then
		warn("[TipsSystemController] RebirthEvents folder missing")
		return
	end

	local rebirthResultEvent = rebirthEvents:FindFirstChild("RebirthResult")
	if not rebirthResultEvent then
		rebirthResultEvent = rebirthEvents:WaitForChild("RebirthResult", 10)
	end

	if rebirthResultEvent and rebirthResultEvent:IsA("RemoteEvent") then
		rebirthResultEvent.OnClientEvent:Connect(function(success)
			if success == true then
				ShowRebirthTip()
			end
		end)
	else
		warn("[TipsSystemController] RebirthResult event missing")
	end
end

local function BindLikeTipEvent()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[TipsSystemController] Events folder missing for like tip")
		return
	end

	local likeEvents = eventsFolder:WaitForChild("LikeEvents", 10)
	if not likeEvents then
		warn("[TipsSystemController] LikeEvents folder missing")
		return
	end

	local likeToastEvent = likeEvents:FindFirstChild("LikeToast")
	if not likeToastEvent then
		likeToastEvent = likeEvents:WaitForChild("LikeToast", 10)
	end

	if likeToastEvent and likeToastEvent:IsA("RemoteEvent") then
		likeToastEvent.OnClientEvent:Connect(function(likerName)
			ShowLikeTip(likerName)
		end)
	else
		warn("[TipsSystemController] LikeToast event missing")
	end
end

local function BindLikeStateEvent()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[TipsSystemController] Events folder missing for like state")
		return
	end

	local likeEvents = eventsFolder:WaitForChild("LikeEvents", 10)
	if not likeEvents then
		warn("[TipsSystemController] LikeEvents folder missing for like state")
		return
	end

	local likeStateEvent = likeEvents:FindFirstChild("LikeStateSync")
	if not likeStateEvent then
		likeStateEvent = likeEvents:WaitForChild("LikeStateSync", 10)
	end

	if likeStateEvent and likeStateEvent:IsA("RemoteEvent") then
		likeStateEvent.OnClientEvent:Connect(function(mode, payload)
			if mode == "full" then
				ReplaceLikedOwners(payload)
				RefreshAllLikePromptVisibility()
			elseif mode == "add" then
				if AddLikedOwner(payload) then
					RefreshAllLikePromptVisibility()
				end
			end
		end)
	else
		warn("[TipsSystemController] LikeStateSync event missing")
	end
end

BindRefreshTipEvent()
BindRebirthTipEvent()
BindLikeTipEvent()
BindLikeStateEvent()
StartLikePromptVisibilitySync()
BindLikePromptShownGuard()

_G.TipsSystem = TipsSystemController

return TipsSystemController

