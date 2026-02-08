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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local tipsGui = playerGui:WaitForChild("TipsSystem", 10)
if not tipsGui then
	warn("[TipsSystemController] 未找到 TipsSystem 界面")
	return
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

function TipsSystemController.ShowRefreshTip()
	ShowRefreshTip()
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

BindRefreshTipEvent()

_G.TipsSystem = TipsSystemController

return TipsSystemController
