--[[
=====================================================
脚本名称：TipsSystemController
脚本类型：本地脚本（客户端）
脚本位置：StarterPlayer/StarterPlayerScripts/Controllers/TipsSystemController.lua
=====================================================
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

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

local targetPosition = frame.Position
local startPosition = UDim2.new(0.5, 0, 0.5, 0)
local showDuration = 1
local tweenDuration = 0.25

local showToken = 0
local activeTween = nil

frame.Visible = false

local function StopCurrentTip()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	frame.Visible = false
end

local TipsSystemController = {}

function TipsSystemController.ShowError(text)
	if not text or text == "" then
		return
	end

	showToken = showToken + 1
	local token = showToken

	StopCurrentTip()

	errorText.Text = text
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

_G.TipsSystem = TipsSystemController

return TipsSystemController