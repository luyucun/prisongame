--[[
脚本名称: AutoBattleController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/AutoBattleController.lua
版本: V5.5
职责: VIP自动挑战控制（Auto按钮、自动确认、自动开战）
]]

local AutoBattleController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ButtonEffectHelper = nil

-- UI引用
local mainGui = nil
local battleControl = nil
local playButton = nil
local retreatButton = nil
local autoButton = nil
local autoIcon = nil
local autoTips = nil

local returnToHomeButton = nil
local unlockMoveButton = nil
local restartButton = nil

-- 事件
local campaignEvents = nil
local requestStartEvent = nil

-- 状态
local autoEnabled = false
local rotationConn = nil
local tipsToken = 0
local autoStartToken = 0
local autoConfirmToken = 0
local confirmButtonConn = nil
local autoIconBaseRotation = 0
local initialized = false
local initInProgress = false
local boundButtons = {}
local stateUpdateConn = nil
local playVisibleConn = nil
local battleVisibleConn = nil
local vipAttrConn = nil
local victoryAddedConn = nil

local ROTATE_SPEED = 180
local AUTO_TIPS_TEXT = "Auto-Rioting"

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

	warn("[AutoBattleController] ButtonEffectHelper加载失败:", result)
	return false
end

local function IsVip()
	return player:GetAttribute("VipPurchased") == true
end

-- ==================== UI初始化 ====================

local function InitializeUI()
	mainGui = SafeWaitForChild(playerGui, "MainGui", 5)
	if not mainGui then
		return false
	end

	battleControl = mainGui:FindFirstChild("BattleControl")
	if not battleControl then
		return false
	end

	playButton = battleControl:FindFirstChild("Play")
	retreatButton = battleControl:FindFirstChild("Retreat")
	autoButton = battleControl:FindFirstChild("Auto")
	autoIcon = autoButton and autoButton:FindFirstChild("Icon")
	autoTips = mainGui:FindFirstChild("AutoBattleTips")

	returnToHomeButton = mainGui:FindFirstChild("ReturnToHome", true)
	unlockMoveButton = mainGui:FindFirstChild("UnlockMove", true)
	restartButton = mainGui:FindFirstChild("Restart", true)

	return playButton ~= nil and autoButton ~= nil
end

local function InitializeEvents()
	if campaignEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		return false
	end

	campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
	if not campaignEvents then
		return false
	end

	requestStartEvent = campaignEvents:FindFirstChild("RequestStartCampaign")
	return true
end

-- ==================== 自动挑战逻辑 ====================

local function StopAutoRotation()
	if rotationConn then
		rotationConn:Disconnect()
		rotationConn = nil
	end
	if autoIcon then
		autoIcon.Rotation = autoIconBaseRotation
	end
end

local function StartAutoRotation()
	StopAutoRotation()
	if not autoIcon then
		return
	end

	autoIconBaseRotation = autoIcon.Rotation or 0
	rotationConn = RunService.RenderStepped:Connect(function(dt)
		if autoIcon then
			autoIcon.Rotation = (autoIcon.Rotation + ROTATE_SPEED * dt) % 360
		end
	end)
end

local function StopAutoTips()
	tipsToken += 1
	if autoTips then
		autoTips.Visible = false
	end
end

local function StartAutoTips()
	StopAutoTips()
	if not autoTips then
		return
	end

	autoTips.Visible = true
	local token = tipsToken

	task.spawn(function()
		local dotCount = 0
		while autoEnabled and token == tipsToken and autoTips do
			dotCount = (dotCount % 3) + 1
			autoTips.Text = AUTO_TIPS_TEXT .. string.rep(".", dotCount)
			task.wait(0.5)
		end
	end)
end

local function UpdateAutoVisibility()
	if not autoButton then
		return
	end

	local shouldShow = IsVip() and playButton and playButton.Visible
	if battleControl and battleControl.Visible == false then
		shouldShow = false
	end

	autoButton.Visible = shouldShow
	if not shouldShow and autoEnabled then
		autoButton.Visible = false
	end
end

local function ScheduleAutoStart(delaySeconds)
	autoStartToken += 1
	local token = autoStartToken

	task.delay(delaySeconds or 0, function()
		if token ~= autoStartToken then
			return
		end
		if not autoEnabled then
			return
		end
		if not IsVip() then
			return
		end
		if not playButton or not playButton.Visible then
			return
		end
		if battleControl and not battleControl.Visible then
			return
		end
		if requestStartEvent then
			requestStartEvent:FireServer()
		end
	end)
end

local function ConfirmVictoryIfNeeded()
	if not autoEnabled then
		return
	end

	local victoryController = _G.VictoryUIController
	if victoryController and victoryController.ConfirmCurrent then
		victoryController.ConfirmCurrent()
		return
	end

	local victoryGui = playerGui:FindFirstChild("Victory")
	local infoFrame = victoryGui and victoryGui:FindFirstChild("Information")
	local confirmButton = infoFrame and infoFrame:FindFirstChild("Confirm")
	if confirmButton and confirmButton.Visible then
		pcall(function()
			if confirmButton.Activate then
				confirmButton:Activate()
			end
		end)
	end
end

local function ScheduleAutoConfirm()
	autoConfirmToken += 1
	local token = autoConfirmToken

	task.delay(3, function()
		if token ~= autoConfirmToken then
			return
		end
		if not autoEnabled then
			return
		end
		ConfirmVictoryIfNeeded()
	end)
end

local function BindConfirmButton()
	if confirmButtonConn then
		confirmButtonConn:Disconnect()
		confirmButtonConn = nil
	end

	local victoryGui = playerGui:FindFirstChild("Victory")
	local infoFrame = victoryGui and victoryGui:FindFirstChild("Information")
	local confirmButton = infoFrame and infoFrame:FindFirstChild("Confirm")
	if not confirmButton then
		return
	end

	confirmButtonConn = confirmButton:GetPropertyChangedSignal("Visible"):Connect(function()
		if confirmButton.Visible and autoEnabled then
			ScheduleAutoConfirm()
		end
	end)
end

local function SetAutoEnabled(enabled)
	if autoEnabled == enabled then
		return
	end

	autoEnabled = enabled

	if autoEnabled then
		StartAutoRotation()
		StartAutoTips()
		ScheduleAutoStart(0)
	else
		StopAutoRotation()
		StopAutoTips()
	end
end

-- ==================== 事件绑定 ====================

local function BindButtons()
	LoadButtonEffectHelper()

	if autoButton and (autoButton:IsA("TextButton") or autoButton:IsA("ImageButton")) then
		if not boundButtons[autoButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(autoButton, {
					OnClick = function()
						if not IsVip() then
							return
						end
						SetAutoEnabled(not autoEnabled)
					end
				})
			else
				autoButton.MouseButton1Click:Connect(function()
					if not IsVip() then
						return
					end
					SetAutoEnabled(not autoEnabled)
				end)
			end
			boundButtons[autoButton] = true
		end
	end

	local function BindCancelButton(button)
		if not button or not (button:IsA("TextButton") or button:IsA("ImageButton")) then
			return
		end
		if boundButtons[button] then
			return
		end
		button.MouseButton1Click:Connect(function()
			if autoEnabled then
				SetAutoEnabled(false)
			end
		end)
		boundButtons[button] = true
	end

	BindCancelButton(returnToHomeButton)
	BindCancelButton(unlockMoveButton)
	BindCancelButton(restartButton)
end

local function BindEvents()
	if not campaignEvents then
		return
	end

	local stateUpdate = campaignEvents:FindFirstChild("CampaignStateUpdate")
	if stateUpdate and not stateUpdateConn then
		stateUpdateConn = stateUpdate.OnClientEvent:Connect(function(state)
			if state == "Idle" and autoEnabled then
				ScheduleAutoStart(2)
			end
		end)
	end
end

-- ==================== 初始化 ====================

local function TryInitialize()
	if initialized then
		return true
	end
	if not InitializeUI() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	BindButtons()
	BindEvents()
	BindConfirmButton()

	if playButton and not playVisibleConn then
		playVisibleConn = playButton:GetPropertyChangedSignal("Visible"):Connect(UpdateAutoVisibility)
	end
	if battleControl and not battleVisibleConn then
		battleVisibleConn = battleControl:GetPropertyChangedSignal("Visible"):Connect(UpdateAutoVisibility)
	end

	if not vipAttrConn then
		vipAttrConn = player:GetAttributeChangedSignal("VipPurchased"):Connect(function()
			if not IsVip() and autoEnabled then
				SetAutoEnabled(false)
			end
			UpdateAutoVisibility()
		end)
	end

	if not victoryAddedConn then
		victoryAddedConn = playerGui.ChildAdded:Connect(function(child)
			if child and child.Name == "Victory" then
				task.wait()
				BindConfirmButton()
			end
		end)
	end

	UpdateAutoVisibility()
	initialized = true
	return true
end

function AutoBattleController.Initialize()
	if TryInitialize() then
		return true
	end

	if initInProgress then
		return false
	end
	initInProgress = true

	task.spawn(function()
		local attempts = 0
		while attempts < 10 and not TryInitialize() do
			attempts += 1
			task.wait(1.5)
		end
		initInProgress = false
	end)

	return false
end

task.spawn(function()
	local ok, err = pcall(AutoBattleController.Initialize)
	if not ok then
		warn("[AutoBattleController] 初始化失败:", err)
	end
end)

return AutoBattleController
