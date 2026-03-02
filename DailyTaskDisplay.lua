--[[
脚本名称: DailyTaskDisplay
脚本类型: LocalScript
脚本位置: StarterPlayer/StarterPlayerScripts/UI/DailyTaskDisplay.lua
版本: V7.3
]]

local DailyTaskDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ButtonEffectHelper = nil
local function TryLoadButtonEffectHelper()
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

	warn("[DailyTaskDisplay] ButtonEffectHelper加载失败:", result)
	return false
end

local BLUR_LOCKS_KEY = "__PopupBlurLocks"
local BLUR_LOCK_ID = "DailyTaskDisplay"

local PANEL_OPEN_START_SCALE = 0.88
local PANEL_OPEN_OVERSHOOT_SCALE = 1.04
local PANEL_CLOSE_OVERSHOOT_SCALE = 1.06
local PANEL_CLOSE_END_SCALE = 0.92

local CLAIM_DISABLED_BG = Color3.fromRGB(162, 162, 162)
local CLAIM_ENABLED_BG = Color3.fromRGB(255, 255, 255)
local PROGRESS_INCOMPLETE_COLOR = "#FF3B30"
local PROGRESS_COMPLETE_COLOR = "#00FF00"
local HANDCUFF_ICON = "rbxassetid://118659064631130"
local BACKPACK_HIDE_KEY = "DailyTask"

local mainGui = nil
local dailyButtonRoot = nil
local dailyButton = nil
local dailyRedPoint = nil

local dailyTaskGui = nil
local panelBg = nil
local panelCloseButton = nil
local taskBg = nil

local panelScale = nil
local panelOpenTweenA = nil
local panelOpenTweenB = nil
local panelCloseTweenA = nil
local panelCloseTweenB = nil

local isPanelOpen = false
local initDone = false

local redPointShakeToken = 0
local redPointTweenA = nil
local redPointTweenB = nil
local redPointTweenC = nil

local eventsFolder = nil
local dailyTaskEvents = nil
local requestDataEvent = nil
local dataEvent = nil
local claimEvent = nil
local claimResultEvent = nil

local dataEventConn = nil
local claimResultEventConn = nil

local cachedPayload = nil
local taskEntries = {}
local claimPending = {}
local boundButtons = {}

local claimTipsGui = nil
local claimSuccess = nil
local claimLightBg = nil
local claimPopupBg = nil
local popupItemListFrame = nil
local popupItemTemplate = nil
local popupTitleLabel = nil
local popupDefaultTitle = nil
local popupVisible = false
local popupAllowClose = false
local popupToken = 0
local popupInputConn = nil
local popupRestorePanel = false

local function ParseBlurLocks()
	local lockStr = Lighting:GetAttribute(BLUR_LOCKS_KEY)
	local lockMap = {}
	if type(lockStr) == "string" and lockStr ~= "" then
		for token in string.gmatch(lockStr, "[^|]+") do
			lockMap[token] = true
		end
	end
	return lockMap
end

local function SetBlurLock(enabled)
	local lockMap = ParseBlurLocks()
	if enabled then
		lockMap[BLUR_LOCK_ID] = true
	else
		lockMap[BLUR_LOCK_ID] = nil
	end

	local tokens = {}
	for token in pairs(lockMap) do
		table.insert(tokens, token)
	end
	table.sort(tokens)

	if #tokens > 0 then
		Lighting:SetAttribute(BLUR_LOCKS_KEY, table.concat(tokens, "|"))
	else
		Lighting:SetAttribute(BLUR_LOCKS_KEY, nil)
	end

	local blur = Lighting:FindFirstChild("Blur")
	if blur and blur:IsA("BlurEffect") then
		blur.Enabled = #tokens > 0
	end
end

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

local function EnsurePanelScale()
	if not panelBg then
		return nil
	end

	if panelScale and panelScale.Parent == panelBg then
		return panelScale
	end

	local existing = panelBg:FindFirstChild("PopupScale")
	if existing and existing:IsA("UIScale") then
		panelScale = existing
		return panelScale
	end

	panelScale = Instance.new("UIScale")
	panelScale.Name = "PopupScale"
	panelScale.Scale = 1
	panelScale.Parent = panelBg
	return panelScale
end

local function StopPanelTweens()
	for _, tween in ipairs({ panelOpenTweenA, panelOpenTweenB, panelCloseTweenA, panelCloseTweenB }) do
		if tween then
			tween:Cancel()
		end
	end
	panelOpenTweenA = nil
	panelOpenTweenB = nil
	panelCloseTweenA = nil
	panelCloseTweenB = nil
end

local function PlayPanelOpen()
	if not panelBg then
		return false
	end

	local scale = EnsurePanelScale()
	if not scale then
		panelBg.Visible = true
		SetBlurLock(true)
		return true
	end

	StopPanelTweens()
	panelBg.Visible = true
	scale.Scale = PANEL_OPEN_START_SCALE
	SetBlurLock(true)

	panelOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = PANEL_OPEN_OVERSHOOT_SCALE }
	)
	panelOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)

	local connA, connB
	connA = panelOpenTweenA.Completed:Connect(function(state)
		if connA then
			connA:Disconnect()
			connA = nil
		end
		if state == Enum.PlaybackState.Completed and panelOpenTweenB then
			panelOpenTweenB:Play()
		end
	end)

	connB = panelOpenTweenB.Completed:Connect(function()
		if connB then
			connB:Disconnect()
			connB = nil
		end
		scale.Scale = 1
		SetBlurLock(true)
	end)

	panelOpenTweenA:Play()
	return true
end

local function PlayPanelClose()
	if not panelBg then
		return false
	end

	local scale = EnsurePanelScale()
	if not scale then
		panelBg.Visible = false
		SetBlurLock(false)
		return true
	end

	StopPanelTweens()

	panelCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = PANEL_CLOSE_OVERSHOOT_SCALE }
	)
	panelCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = PANEL_CLOSE_END_SCALE }
	)

	local connA, connB
	connA = panelCloseTweenA.Completed:Connect(function(state)
		if connA then
			connA:Disconnect()
			connA = nil
		end
		if state == Enum.PlaybackState.Completed and panelCloseTweenB then
			panelCloseTweenB:Play()
		end
	end)

	connB = panelCloseTweenB.Completed:Connect(function()
		if connB then
			connB:Disconnect()
			connB = nil
		end
		scale.Scale = 1
		panelBg.Visible = false
		SetBlurLock(false)
	end)

	panelCloseTweenA:Play()
	return true
end

local function StopRedPointShake()
	redPointShakeToken = redPointShakeToken + 1
	for _, tween in ipairs({ redPointTweenA, redPointTweenB, redPointTweenC }) do
		if tween then
			tween:Cancel()
		end
	end
	redPointTweenA = nil
	redPointTweenB = nil
	redPointTweenC = nil
	if dailyRedPoint then
		dailyRedPoint.Rotation = 0
	end
end

local function StartRedPointShake()
	if not dailyRedPoint or not dailyRedPoint.Visible then
		return
	end

	StopRedPointShake()
	local token = redPointShakeToken

	task.spawn(function()
		while dailyRedPoint and dailyRedPoint.Visible and redPointShakeToken == token do
			redPointTweenA = TweenService:Create(dailyRedPoint, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Rotation = 12 })
			redPointTweenB = TweenService:Create(dailyRedPoint, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = -12 })
			redPointTweenC = TweenService:Create(dailyRedPoint, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Rotation = 0 })
			redPointTweenA:Play()
			redPointTweenA.Completed:Wait()
			if redPointShakeToken ~= token then
				break
			end
			redPointTweenB:Play()
			redPointTweenB.Completed:Wait()
			if redPointShakeToken ~= token then
				break
			end
			redPointTweenC:Play()
			redPointTweenC.Completed:Wait()

			task.wait(2)
		end
	end)
end

local function PlayErrorSfx()
	local soundController = _G.SoundController
	if soundController and soundController.PlaySFX then
		soundController.PlaySFX("Error")
	end
end

local function Color3ToHex(color)
	local r = math.clamp(math.floor((color.R * 255) + 0.5), 0, 255)
	local g = math.clamp(math.floor((color.G * 255) + 0.5), 0, 255)
	local b = math.clamp(math.floor((color.B * 255) + 0.5), 0, 255)
	return string.format("#%02X%02X%02X", r, g, b)
end

local function ResolveTaskPayload(taskId)
	if type(cachedPayload) ~= "table" then
		return nil
	end
	local tasks = cachedPayload.Tasks
	if type(tasks) ~= "table" then
		return nil
	end
	return tasks[taskId]
end

local function UpdateTaskEntry(taskId)
	local entry = taskEntries[taskId]
	if not entry then
		return
	end

	local payload = ResolveTaskPayload(taskId)
	if type(payload) ~= "table" then
		return
	end

	local progress = math.max(0, math.floor(tonumber(payload.Progress) or 0))
	local target = math.max(1, math.floor(tonumber(payload.Target) or 1))
	local completed = payload.Completed == true
	local claimed = payload.Claimed == true

	if entry.ProgressLabel and entry.ProgressLabel:IsA("TextLabel") then
		entry.ProgressLabel.RichText = true
		local defaultHex = Color3ToHex(entry.ProgressDefaultColor or entry.ProgressLabel.TextColor3)
		if completed then
			entry.ProgressLabel.Text = string.format(
				"(<font color=\"%s\">%d/%d</font>)",
				PROGRESS_COMPLETE_COLOR,
				progress,
				target
			)
		else
			entry.ProgressLabel.Text = string.format(
				"(<font color=\"%s\">%d</font>/<font color=\"%s\">%d</font>)",
				PROGRESS_INCOMPLETE_COLOR,
				progress,
				defaultHex,
				target
			)
		end
	end

	local canClaim = completed and not claimed
	if entry.ClaimButton then
		entry.ClaimButton.Visible = not claimed
		entry.ClaimButton.BackgroundColor3 = canClaim and CLAIM_ENABLED_BG or CLAIM_DISABLED_BG
		if entry.ClaimButton:IsA("TextButton") or entry.ClaimButton:IsA("ImageButton") then
			entry.ClaimButton.Active = true
			entry.ClaimButton.AutoButtonColor = canClaim
		end
	end

	if entry.ClaimGradient then
		entry.ClaimGradient.Enabled = canClaim
	end

	if entry.ClaimedLabel then
		entry.ClaimedLabel.Visible = claimed
	end
end

local function UpdateAllTaskEntries()
	for taskId in pairs(taskEntries) do
		UpdateTaskEntry(taskId)
	end
end

local function UpdateRedPoint()
	if not dailyRedPoint then
		return
	end

	local show = type(cachedPayload) == "table" and cachedPayload.HasClaimable == true
	dailyRedPoint.Visible = show
	if show then
		StartRedPointShake()
	else
		StopRedPointShake()
	end
end

local function ApplyPayload(payload)
	if type(payload) ~= "table" then
		return
	end
	cachedPayload = payload
	UpdateAllTaskEntries()
	UpdateRedPoint()
end

local function RequestData()
	if requestDataEvent then
		requestDataEvent:FireServer()
	end
end

local function OpenPanel(skipRequest)
	if not panelBg then
		return
	end
	isPanelOpen = true
	RequestBackpackHide()
	PlayPanelOpen()
	if not skipRequest then
		RequestData()
	end
end

local function ClosePanel()
	if not panelBg then
		return
	end
	isPanelOpen = false
	ReleaseBackpackHide()
	PlayPanelClose()
end

local function ForceHidePanel(keepBlur)
	if not panelBg then
		return
	end

	StopPanelTweens()
	panelBg.Visible = false
	isPanelOpen = false

	local scale = EnsurePanelScale()
	if scale then
		scale.Scale = 1
	end

	if not keepBlur then
		SetBlurLock(false)
		ReleaseBackpackHide()
	end
end

local function ClearPopupItems()
	if not popupItemListFrame then
		return
	end

	for _, child in ipairs(popupItemListFrame:GetChildren()) do
		if child ~= popupItemTemplate and child.Name == "DailyTaskItem" then
			child:Destroy()
		end
	end
end

local function UnbindPopupInput()
	if popupInputConn then
		popupInputConn:Disconnect()
		popupInputConn = nil
	end
end

local function CloseClaimPopup()
	if not popupVisible then
		return
	end

	popupVisible = false
	popupAllowClose = false
	popupToken = popupToken + 1
	UnbindPopupInput()

	if claimSuccess then
		claimSuccess.Visible = false
	end
	if claimLightBg then
		claimLightBg.Visible = false
	end

	ClearPopupItems()

	if popupRestorePanel then
		popupRestorePanel = false
		OpenPanel(true)
	else
		SetBlurLock(false)
		ReleaseBackpackHide()
	end
end

local function BindPopupInput(token)
	UnbindPopupInput()
	popupInputConn = UserInputService.InputBegan:Connect(function(input)
		if popupToken ~= token or not popupVisible or not popupAllowClose then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			CloseClaimPopup()
		end
	end)
end

local function ShowClaimPopup(rewardInfo)
	if not claimSuccess or not claimPopupBg then
		return false
	end

	if popupVisible then
		CloseClaimPopup()
	end

	popupRestorePanel = isPanelOpen
	if popupRestorePanel then
		ForceHidePanel(true)
	end

	ClearPopupItems()

	if popupItemTemplate and popupItemListFrame then
		local item = popupItemTemplate:Clone()
		item.Name = "DailyTaskItem"
		item.Visible = true

		local icon = item:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = HANDCUFF_ICON
		end

		local numberLabel = item:FindFirstChild("Number")
		if numberLabel and numberLabel:IsA("TextLabel") then
			numberLabel.Text = tostring(math.max(1, math.floor(tonumber(rewardInfo and rewardInfo.Count) or 1)))
		end

		item.Parent = popupItemListFrame
	end

	if popupTitleLabel and popupTitleLabel:IsA("TextLabel") then
		popupTitleLabel.Text = popupDefaultTitle or "Reward Claimed!"
	end

	claimSuccess.Visible = true
	if claimLightBg then
		claimLightBg.Visible = true
	end
	SetBlurLock(true)

	local originalPos = claimPopupBg.Position
	local startPos = UDim2.new(
		originalPos.X.Scale,
		originalPos.X.Offset,
		originalPos.Y.Scale + 0.04,
		originalPos.Y.Offset
	)
	claimPopupBg.Position = startPos
	TweenService:Create(
		claimPopupBg,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = originalPos }
	):Play()

	popupToken = popupToken + 1
	local token = popupToken
	popupVisible = true
	popupAllowClose = false
	BindPopupInput(token)

	task.delay(0.4, function()
		if popupToken ~= token then
			return
		end
		popupAllowClose = true
	end)

	task.delay(4, function()
		if popupToken ~= token then
			return
		end
		CloseClaimPopup()
	end)

	return true
end

local function OnClaimButtonClicked(taskId)
	local payload = ResolveTaskPayload(taskId)
	if type(payload) ~= "table" then
		PlayErrorSfx()
		return
	end

	if claimPending[taskId] then
		return
	end

	if payload.Claimed == true or payload.Completed ~= true then
		PlayErrorSfx()
		return
	end

	if not claimEvent then
		PlayErrorSfx()
		return
	end

	claimPending[taskId] = true
	claimEvent:FireServer(taskId)
end

local function BindButton(button, callback)
	if not button or boundButtons[button] then
		return
	end

	local isButton = button:IsA("TextButton") or button:IsA("ImageButton")
	if not isButton then
		return
	end

	if TryLoadButtonEffectHelper() and ButtonEffectHelper and ButtonEffectHelper.AddClickEffect then
		ButtonEffectHelper.AddClickEffect(button, { OnClick = callback })
	else
		button.MouseButton1Click:Connect(callback)
	end

	boundButtons[button] = true
end

local function BindTaskEntries()
	taskEntries = {}
	for taskId = 1, 3 do
		local taskFrame = taskBg and taskBg:FindFirstChild(string.format("Task%02d", taskId))
		if taskFrame then
			local progressLabel = taskFrame:FindFirstChild("TaskProgress")
			local claimButton = taskFrame:FindFirstChild("Claim")
			local claimedLabel = taskFrame:FindFirstChild("Claimed")
			local claimGradient = claimButton and claimButton:FindFirstChildOfClass("UIGradient")

			taskEntries[taskId] = {
				Root = taskFrame,
				ProgressLabel = progressLabel,
				ProgressDefaultColor = progressLabel and progressLabel:IsA("TextLabel") and progressLabel.TextColor3 or Color3.fromRGB(255, 255, 255),
				ClaimButton = claimButton,
				ClaimGradient = claimGradient,
				ClaimedLabel = claimedLabel,
			}

			if claimButton then
				BindButton(claimButton, function()
					OnClaimButtonClicked(taskId)
				end)
			end
		end
	end
end

local function BindEvents()
	if dataEventConn and claimResultEventConn then
		return true
	end

	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	end
	if not eventsFolder then
		warn("[DailyTaskDisplay] Events folder missing")
		return false
	end

	dailyTaskEvents = eventsFolder:FindFirstChild("DailyTaskEvents")
	if not dailyTaskEvents then
		dailyTaskEvents = eventsFolder:WaitForChild("DailyTaskEvents", 10)
	end
	if not dailyTaskEvents then
		warn("[DailyTaskDisplay] DailyTaskEvents folder missing")
		return false
	end

	requestDataEvent = dailyTaskEvents:FindFirstChild("RequestDailyTaskData") or dailyTaskEvents:WaitForChild("RequestDailyTaskData", 10)
	dataEvent = dailyTaskEvents:FindFirstChild("DailyTaskData") or dailyTaskEvents:WaitForChild("DailyTaskData", 10)
	claimEvent = dailyTaskEvents:FindFirstChild("ClaimDailyTaskReward") or dailyTaskEvents:WaitForChild("ClaimDailyTaskReward", 10)
	claimResultEvent = dailyTaskEvents:FindFirstChild("ClaimDailyTaskResult") or dailyTaskEvents:WaitForChild("ClaimDailyTaskResult", 10)

	if not requestDataEvent or not dataEvent or not claimEvent or not claimResultEvent then
		warn("[DailyTaskDisplay] DailyTask events incomplete")
		return false
	end

	if not dataEventConn then
		dataEventConn = dataEvent.OnClientEvent:Connect(function(payload)
			ApplyPayload(payload)
		end)
	end

	if not claimResultEventConn then
		claimResultEventConn = claimResultEvent.OnClientEvent:Connect(function(success, message, rewardInfo, taskId)
			local resolvedTaskId = math.floor(tonumber(taskId) or 0)
			if resolvedTaskId > 0 then
				claimPending[resolvedTaskId] = nil
			else
				claimPending = {}
			end

			if success == true then
				local tipsSystem = _G.TipsSystem
				if tipsSystem and tipsSystem.ShowSuccess then
					tipsSystem.ShowSuccess(message or "Reward Claimed!")
				end
				if not ShowClaimPopup(rewardInfo) then
					RequestData()
				end
			else
				PlayErrorSfx()
				local tipsSystem = _G.TipsSystem
				if tipsSystem and tipsSystem.ShowError then
					tipsSystem.ShowError(message or "Claim failed")
				end
			end
		end)
	end

	return true
end

local function BindPopupRefs()
	claimTipsGui = playerGui:FindFirstChild("ClaimTipsGui")
	claimSuccess = claimTipsGui and claimTipsGui:FindFirstChild("ClaimSuccessful")
	claimLightBg = claimTipsGui and claimTipsGui:FindFirstChild("LightBg")
	claimPopupBg = claimSuccess and claimSuccess:FindFirstChild("Bg")
	popupItemListFrame = claimPopupBg and claimPopupBg:FindFirstChild("ItemListFrame")
	popupItemTemplate = popupItemListFrame and popupItemListFrame:FindFirstChild("ItemTemplate")
	popupTitleLabel = claimSuccess and claimSuccess:FindFirstChild("Title")

	if popupTitleLabel and popupTitleLabel:IsA("TextLabel") then
		popupDefaultTitle = popupTitleLabel.Text
	end
end

local function FindDailyButton(root)
	if not root then
		return nil, nil
	end

	local direct = root:FindFirstChild("Daily")
	local buttonRoot = direct
	if not buttonRoot then
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant.Name == "Daily" then
				buttonRoot = descendant
				break
			end
		end
	end

	if not buttonRoot then
		return nil, nil
	end

	if buttonRoot:IsA("ImageButton") or buttonRoot:IsA("TextButton") then
		return buttonRoot, buttonRoot
	end

	local nestedButton = buttonRoot:FindFirstChildWhichIsA("GuiButton", true)
	if nestedButton then
		return buttonRoot, nestedButton
	end

	return buttonRoot, nil
end

local function TryInitialize()
	mainGui = playerGui:FindFirstChild("MainGui")
	dailyButtonRoot, dailyButton = FindDailyButton(mainGui)
	dailyRedPoint = (dailyButtonRoot and dailyButtonRoot:FindFirstChild("RedPoint")) or (dailyButton and dailyButton:FindFirstChild("RedPoint"))

	dailyTaskGui = playerGui:FindFirstChild("DailyTask")
	panelBg = dailyTaskGui and dailyTaskGui:FindFirstChild("Bg")
	local panelTitle = panelBg and panelBg:FindFirstChild("Title")
	panelCloseButton = panelTitle and panelTitle:FindFirstChild("CloseButton")
	taskBg = panelBg and panelBg:FindFirstChild("TaskBg")

	if not panelBg or not panelCloseButton or not taskBg or not dailyButton then
		return false
	end

	panelBg.Visible = false
	isPanelOpen = false
	ReleaseBackpackHide()
	local scale = EnsurePanelScale()
	if scale then
		scale.Scale = 1
	end
	SetBlurLock(false)

	if dailyRedPoint then
		dailyRedPoint.Visible = false
	end

	BindTaskEntries()
	BindPopupRefs()

	if not BindEvents() then
		return false
	end

	BindButton(dailyButton, function()
		OpenPanel(false)
	end)
	BindButton(panelCloseButton, function()
		ClosePanel()
	end)

	RequestData()
	if cachedPayload then
		UpdateAllTaskEntries()
		UpdateRedPoint()
	end

	return true
end

function DailyTaskDisplay.Initialize()
	if initDone then
		return
	end

	if TryInitialize() then
		initDone = true
		return
	end

	task.spawn(function()
		local attempts = 0
		while attempts < 8 and not initDone do
			attempts += 1
			if TryInitialize() then
				initDone = true
				return
			end
			task.wait(2)
		end
	end)

	playerGui.ChildAdded:Connect(function(child)
		if not child then
			return
		end
		if child.Name ~= "MainGui" and child.Name ~= "DailyTask" and child.Name ~= "ClaimTipsGui" then
			return
		end

		task.spawn(function()
			task.wait()
			if TryInitialize() then
				initDone = true
			end
		end)
	end)
end

DailyTaskDisplay.Initialize()

return DailyTaskDisplay
