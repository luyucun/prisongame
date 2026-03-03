--[[
Script: RebirthDisplay
Type: LocalScript (Client)
Location: StarterPlayer/StarterPlayerScripts/RebirthDisplay
Version: V7.0
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BLUR_LOCK_ID = "Rebirth"
local BLUR_LOCKS_KEY = "__PopupBlurLocks"
local BACKPACK_HIDE_KEY = "Rebirth"

local POPUP_OPEN_START_SCALE = 0.86
local POPUP_OPEN_OVERSHOOT_SCALE = 1.10
local POPUP_OPEN_DURATION_A = 0.18
local POPUP_OPEN_DURATION_B = 0.10
local POPUP_CLOSE_OVERSHOOT_SCALE = 1.12
local POPUP_CLOSE_END_SCALE = 0.78
local POPUP_CLOSE_DURATION_A = 0.08
local POPUP_CLOSE_DURATION_B = 0.12

local mainGui = nil
local mainButton = nil
local mainTimeLabel = nil
local mainRedPoint = nil

local rebirthGui = nil
local rebirthBg = nil
local rebirthCloseButton = nil
local rebirthButton = nil

local rewardBg = nil
local rewardTemplate = nil
local spendBg = nil
local spendTemplate = nil
local progressBar = nil
local progressNum = nil

local eventsFolder = nil
local rebirthEvents = nil
local requestRebirthDataEvent = nil
local rebirthDataEvent = nil
local attemptRebirthEvent = nil
local rebirthResultEvent = nil
local rebirthPanelClosedEvent = nil
local rebirthStateChangedEvent = nil
local currencyUpdateEvent = nil
local inventoryRefreshEvent = nil
local unitUpdatedEvent = nil
local campaignStateUpdateEvent = nil

local buttonEffectHelper = nil
local popupScale = nil
local popupScaleHost = nil
local popupOpenTweenA = nil
local popupOpenTweenB = nil
local popupCloseTweenA = nil
local popupCloseTweenB = nil

local popupAnimating = false
local currentPayload = nil
local isAttemptingRebirth = false
local isBattleBlocked = false
local initialized = false
local redPointShakeToken = 0
local redPointTweenA = nil
local redPointTweenB = nil
local redPointTweenC = nil

local COIN_CURRENCY_TYPE = tostring(GameConfig.CurrencyType and GameConfig.CurrencyType.COINS or "Coins")
local BATTLE_BLOCK_TIP_TEXT = "Finish the battle first."

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

local function RequestBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.PushHideLock then
		trigger.PushHideLock(BACKPACK_HIDE_KEY)
	elseif _G.BackpackDisplay and _G.BackpackDisplay.HideBackpack then
		_G.BackpackDisplay.HideBackpack()
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

local function PlayErrorSound()
	local soundController = _G.SoundController
	if soundController and soundController.PlaySFX then
		soundController.PlaySFX("Error")
	end
end

local function ShowBattleBlockedFeedback()
	PlayErrorSound()
	local tipsSystem = _G.TipsSystem
	if tipsSystem and tipsSystem.ShowError then
		tipsSystem.ShowError(BATTLE_BLOCK_TIP_TEXT)
	end
end

local function LoadButtonEffectHelper()
	if buttonEffectHelper then
		return true
	end

	local success, result = pcall(function()
		return require(game:GetService("StarterPlayer").StarterPlayerScripts.Utils.ButtonEffectHelper)
	end)

	if success then
		buttonEffectHelper = result
		return true
	end

	return false
end

local function EnsurePopupScale()
	if not rebirthBg then
		return nil
	end
	-- Rebirth popup scale must be applied on Rebirth.Bg (not Rebirthinfo).
	local scaleHost = rebirthBg

	if popupScale and not popupScale:IsA("UIScale") then
		popupScale = nil
	end

	if not popupScale or popupScaleHost ~= scaleHost or popupScale.Parent ~= scaleHost then
		popupScaleHost = scaleHost
		local existingScale = scaleHost:FindFirstChild("PopupScale")
		if existingScale and not existingScale:IsA("UIScale") then
			existingScale:Destroy()
			existingScale = nil
		end

		popupScale = existingScale
		if not popupScale then
			popupScale = Instance.new("UIScale")
			popupScale.Name = "PopupScale"
			popupScale.Scale = 1
			popupScale.Parent = scaleHost
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

local function PlayPanelOpen()
	if not rebirthBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		rebirthBg.Visible = true
		SetBlurLock(true)
		return true
	end

	if rebirthBg.Visible and not popupAnimating then
		SetBlurLock(true)
		return true
	end

	CancelPopupTweens()
	popupAnimating = true
	rebirthBg.Visible = true
	scale.Scale = POPUP_OPEN_START_SCALE
	SetBlurLock(true)

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
		if state == Enum.PlaybackState.Completed and popupOpenTweenB then
			popupOpenTweenB:Play()
		end
	end)

	local connB
	connB = popupOpenTweenB.Completed:Connect(function()
		connB:Disconnect()
		popupAnimating = false
		scale.Scale = 1
		SetBlurLock(true)
	end)

	popupOpenTweenA:Play()
	return true
end

local function PlayPanelClose()
	if not rebirthBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		rebirthBg.Visible = false
		SetBlurLock(false)
		return true
	end

	if not rebirthBg.Visible and not popupAnimating then
		SetBlurLock(false)
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
		if state == Enum.PlaybackState.Completed and popupCloseTweenB then
			popupCloseTweenB:Play()
		end
	end)

	local connB
	connB = popupCloseTweenB.Completed:Connect(function()
		connB:Disconnect()
		rebirthBg.Visible = false
		scale.Scale = 1
		popupAnimating = false
		SetBlurLock(false)
	end)

	popupCloseTweenA:Play()
	return true
end

local function StopRedPointShake()
	redPointShakeToken = redPointShakeToken + 1
	for _, tween in ipairs({redPointTweenA, redPointTweenB, redPointTweenC}) do
		if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
			tween:Cancel()
		end
	end

	if mainRedPoint then
		mainRedPoint.Rotation = 0
	end
end

local function StartRedPointShake()
	if not mainRedPoint or not mainRedPoint.Visible then
		return
	end

	local token = redPointShakeToken + 1
	redPointShakeToken = token

	task.spawn(function()
		while mainRedPoint and mainRedPoint.Visible and redPointShakeToken == token do
			redPointTweenA = TweenService:Create(
				mainRedPoint,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Rotation = 12}
			)
			redPointTweenB = TweenService:Create(
				mainRedPoint,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Rotation = -12}
			)
			redPointTweenC = TweenService:Create(
				mainRedPoint,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Rotation = 0}
			)

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
			if redPointShakeToken ~= token then
				break
			end

			task.wait(1.2)
		end
	end)
end

local function UpdateMainButton(payload)
	local rebirthCount = math.max(0, math.floor(tonumber((payload and payload.CurrentCount) or player:GetAttribute("RebirthCount")) or 0))
	if mainTimeLabel and mainTimeLabel:IsA("TextLabel") then
		mainTimeLabel.Text = string.format("[%d]", rebirthCount)
	end

	if mainRedPoint then
		local showRedPoint = payload and payload.CanRebirth == true and payload.IsMaxLevel ~= true
		mainRedPoint.Visible = showRedPoint == true
		if showRedPoint then
			StartRedPointShake()
		else
			StopRedPointShake()
		end
	end
end

local function FormatNumberWithCommas(value)
	local amount = math.max(0, math.floor(tonumber(value) or 0))
	local raw = tostring(amount)
	local formatted = raw:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

local function RecomputePayloadState(payload)
	if type(payload) ~= "table" then
		return
	end

	local requiredCoins = math.max(0, tonumber(payload.RequiredCoins) or 0)
	local currentCoins = math.max(0, tonumber(payload.CurrentCoins) or 0)
	local requiredUnits = math.max(0, tonumber(payload.RequiredUnitCount) or 0)
	local currentUnits = math.max(0, tonumber(payload.CurrentUnitCount) or 0)

	local enoughCoins = currentCoins >= requiredCoins
	local enoughUnits = currentUnits >= requiredUnits
	local isMaxLevel = payload.IsMaxLevel == true

	payload.CanRebirth = (not isMaxLevel) and enoughCoins and enoughUnits
	if isMaxLevel then
		payload.FailCode = "MAX_LEVEL"
	elseif payload.CanRebirth then
		payload.FailCode = "OK"
	elseif not enoughCoins then
		payload.FailCode = "NOT_ENOUGH_COINS"
	else
		payload.FailCode = "NOT_ENOUGH_UNITS"
	end

	local progressScale = 0
	if requiredCoins > 0 then
		progressScale = math.clamp(currentCoins / requiredCoins, 0, 1) * 0.998
	end

	payload.ProgressScale = progressScale
	payload.ProgressText = string.format(
		"$%s/$%s",
		FormatNumberWithCommas(currentCoins),
		FormatNumberWithCommas(requiredCoins)
	)

	if type(payload.Costs) == "table" then
		for _, cost in ipairs(payload.Costs) do
			if type(cost) == "table" then
				if cost.Type == "Coins" then
					cost.Current = currentCoins
					cost.Required = requiredCoins
					cost.Text = payload.ProgressText
					cost.IsEnough = enoughCoins
				elseif cost.Type == "Unit" then
					cost.Current = currentUnits
					cost.Required = requiredUnits
					cost.Text = string.format("%d/%d", currentUnits, requiredUnits)
					cost.IsEnough = enoughUnits
				end
			end
		end
	end
end

local function ClearTemplateItems(container, template)
	if not container or not template then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child ~= template and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function FillItem(itemFrame, icon, numText, showNum, nameText, showName, numColor)
	if not itemFrame then
		return
	end

	local iconObj = itemFrame:FindFirstChild("ItemIcon")
	if iconObj and iconObj:IsA("ImageLabel") then
		iconObj.Image = tostring(icon or "")
	end

	local numObj = itemFrame:FindFirstChild("Num")
	if numObj and numObj:IsA("TextLabel") then
		numObj.Text = tostring(numText or "")
		numObj.Visible = showNum == true
		if numColor then
			numObj.TextColor3 = numColor
		end
	end

	local nameObj = itemFrame:FindFirstChild("Name")
	if nameObj and nameObj:IsA("TextLabel") then
		nameObj.Text = tostring(nameText or "")
		nameObj.Visible = showName == true
	end
end

local function BuildUnitCostText(currentCount, requiredCount, isEnough)
	local current = math.max(0, math.floor(tonumber(currentCount) or 0))
	local required = math.max(0, math.floor(tonumber(requiredCount) or 0))
	if isEnough == true then
		return string.format("%d/%d", current, required), false
	end

	local richText = string.format(
		"<font color=\"#FF5050\">%d</font><font color=\"#FFFFFF\">/%d</font>",
		current,
		required
	)
	return richText, true
end

local function RenderRewards(payload)
	if not rewardBg or not rewardTemplate then
		return
	end

	ClearTemplateItems(rewardBg, rewardTemplate)
	local rewards = (payload and payload.Rewards) or {}

	for _, reward in ipairs(rewards) do
		local item = rewardTemplate:Clone()
		item.Visible = true
		item.Parent = rewardBg
		FillItem(
			item,
			reward.Icon,
			reward.Num,
			reward.ShowNum == true,
			reward.Name,
			reward.ShowName == true
		)
	end
end

local function RenderCosts(payload)
	if not spendBg or not spendTemplate then
		return
	end

	ClearTemplateItems(spendBg, spendTemplate)
	local costs = (payload and payload.Costs) or {}

	for _, cost in ipairs(costs) do
		if cost.Type == "Unit" then
			local item = spendTemplate:Clone()
			item.Visible = true
			item.Parent = spendBg
			local unitCostText, useRichText = BuildUnitCostText(cost.Current, cost.Required, cost.IsEnough == true)
			FillItem(item, cost.Icon, unitCostText, true, "", false, Color3.fromRGB(255, 255, 255))
			local numObj = item:FindFirstChild("Num")
			if numObj and numObj:IsA("TextLabel") then
				numObj.RichText = useRichText
				numObj.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end

local function RenderProgress(payload)
	if not progressBar then
		return
	end

	local progressScale = tonumber(payload and payload.ProgressScale) or 0
	progressScale = math.clamp(progressScale, 0, 0.998)
	progressBar.Size = UDim2.new(progressScale, 0, progressBar.Size.Y.Scale, progressBar.Size.Y.Offset)

	if progressNum and progressNum:IsA("TextLabel") then
		progressNum.Text = tostring((payload and payload.ProgressText) or "$0/$0")
	end
end

local function RenderPanel(payload)
	if not payload then
		return
	end

	RenderRewards(payload)
	RenderCosts(payload)
	RenderProgress(payload)
end

local function ApplyPayload(payload)
	if type(payload) ~= "table" then
		return
	end

	RecomputePayloadState(payload)
	currentPayload = payload
	UpdateMainButton(payload)
	RenderPanel(payload)
end

local function ApplyLiveCoinUpdate(newAmount)
	if type(currentPayload) ~= "table" or currentPayload.IsMaxLevel == true then
		return
	end

	local parsedAmount = tonumber(newAmount)
	if parsedAmount == nil then
		return
	end

	currentPayload.CurrentCoins = math.max(0, math.floor(parsedAmount))
	RecomputePayloadState(currentPayload)
	UpdateMainButton(currentPayload)
	if rebirthBg and rebirthBg.Visible then
		RenderProgress(currentPayload)
	end
end

local function ApplyLiveUnitCountUpdate(unitId, count)
	if type(currentPayload) ~= "table" or currentPayload.IsMaxLevel == true then
		return
	end

	local requiredUnitId = tostring(currentPayload.RequiredUnitId or "")
	if requiredUnitId == "" or tostring(unitId or "") ~= requiredUnitId then
		return
	end

	currentPayload.CurrentUnitCount = math.max(0, math.floor(tonumber(count) or 0))
	RecomputePayloadState(currentPayload)
	UpdateMainButton(currentPayload)
	if rebirthBg and rebirthBg.Visible then
		RenderCosts(currentPayload)
	end
end

local function InitializeEvents()
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		return false
	end

	rebirthEvents = eventsFolder:FindFirstChild("RebirthEvents")
	if not rebirthEvents then
		return false
	end

	requestRebirthDataEvent = rebirthEvents:FindFirstChild("RequestRebirthData")
	rebirthDataEvent = rebirthEvents:FindFirstChild("RebirthData")
	attemptRebirthEvent = rebirthEvents:FindFirstChild("AttemptRebirth")
	rebirthResultEvent = rebirthEvents:FindFirstChild("RebirthResult")
	rebirthPanelClosedEvent = rebirthEvents:FindFirstChild("RebirthPanelClosed")
	rebirthStateChangedEvent = rebirthEvents:FindFirstChild("RebirthStateChanged")

	return requestRebirthDataEvent
		and rebirthDataEvent
		and attemptRebirthEvent
		and rebirthResultEvent
		and rebirthPanelClosedEvent
		and rebirthStateChangedEvent
end

local function InitializeUI()
	if mainGui and rebirthGui and rebirthBg then
		return true
	end

	mainGui = playerGui:FindFirstChild("MainGui") or playerGui:WaitForChild("MainGui", 5)
	if mainGui then
		mainButton = mainGui:FindFirstChild("Rebirth")
		if mainButton and not (mainButton:IsA("GuiButton")) then
			mainButton = mainButton:FindFirstChildWhichIsA("GuiButton") or mainButton
		end

		local buttonRoot = mainGui:FindFirstChild("Rebirth")
		if buttonRoot then
			mainTimeLabel = buttonRoot:FindFirstChild("Time")
			mainRedPoint = buttonRoot:FindFirstChild("RedPoint")
		end
	end

	rebirthGui = playerGui:FindFirstChild("Rebirth") or playerGui:WaitForChild("Rebirth", 5)
	if not rebirthGui then
		return false
	end

	rebirthBg = rebirthGui:FindFirstChild("Bg")
	if not rebirthBg then
		return false
	end

	local title = rebirthBg:FindFirstChild("Title")
	if title then
		rebirthCloseButton = title:FindFirstChild("CloseButton")
	end

	local rebirthInfo = rebirthBg:FindFirstChild("Rebirthinfo")
	if rebirthInfo then
		rewardBg = rebirthInfo:FindFirstChild("RewardBg")
		spendBg = rebirthInfo:FindFirstChild("SpendBg")
		local progressBg = rebirthInfo:FindFirstChild("ProgressBg")
		if progressBg then
			progressBar = progressBg:FindFirstChild("Progress")
			progressNum = progressBg:FindFirstChild("Num")
			if not progressNum and progressBar then
				progressNum = progressBar:FindFirstChild("Num")
			end
		end
		rebirthButton = rebirthInfo:FindFirstChild("RebirthBtn")
	end

	rewardTemplate = rewardBg and rewardBg:FindFirstChild("ItemTemplate") or nil
	spendTemplate = spendBg and spendBg:FindFirstChild("ItemTemplate") or nil
	if rewardTemplate then
		rewardTemplate.Visible = false
	end
	if spendTemplate then
		spendTemplate.Visible = false
	end

	rebirthBg.Visible = false
	SetBlurLock(false)
	ReleaseBackpackHide()
	return true
end

local function RequestLatestData()
	if requestRebirthDataEvent then
		requestRebirthDataEvent:FireServer()
	end
end

local function OpenPanel()
	if not InitializeUI() then
		return
	end
	if isBattleBlocked then
		ShowBattleBlockedFeedback()
		return
	end
	if currentPayload and currentPayload.IsMaxLevel == true then
		return
	end

	RequestBackpackHide()
	if not PlayPanelOpen() then
		ReleaseBackpackHide()
		return
	end

	RenderPanel(currentPayload)
	RequestLatestData()
end

local function ClosePanel(notifyServer)
	if not InitializeUI() then
		return
	end

	PlayPanelClose()
	ReleaseBackpackHide()
	if notifyServer and rebirthPanelClosedEvent then
		rebirthPanelClosedEvent:FireServer()
	end
end

local function OnAttemptRebirth()
	if isBattleBlocked then
		ShowBattleBlockedFeedback()
		return
	end
	if isAttemptingRebirth then
		return
	end
	if not currentPayload then
		RequestLatestData()
		return
	end
	if currentPayload.IsMaxLevel == true then
		return
	end
	if currentPayload.CanRebirth ~= true then
		PlayErrorSound()
		return
	end

	isAttemptingRebirth = true
	attemptRebirthEvent:FireServer()
end

local function BindButtons()
	LoadButtonEffectHelper()

	if mainButton and (mainButton:IsA("TextButton") or mainButton:IsA("ImageButton")) then
		if buttonEffectHelper then
			buttonEffectHelper.AddClickEffect(mainButton, { OnClick = OpenPanel })
		else
			mainButton.MouseButton1Click:Connect(OpenPanel)
		end
	end

	if rebirthCloseButton and (rebirthCloseButton:IsA("TextButton") or rebirthCloseButton:IsA("ImageButton")) then
		if buttonEffectHelper then
			buttonEffectHelper.AddClickEffect(rebirthCloseButton, {
				OnClick = function()
					ClosePanel(true)
				end,
			})
		else
			rebirthCloseButton.MouseButton1Click:Connect(function()
				ClosePanel(true)
			end)
		end
	end

	if rebirthButton and (rebirthButton:IsA("TextButton") or rebirthButton:IsA("ImageButton")) then
		if buttonEffectHelper then
			buttonEffectHelper.AddClickEffect(rebirthButton, { OnClick = OnAttemptRebirth })
		else
			rebirthButton.MouseButton1Click:Connect(OnAttemptRebirth)
		end
	end
end

local function OnRebirthResult(success, code, payload)
	isAttemptingRebirth = false

	if not success then
		if type(payload) == "table" then
			ApplyPayload(payload)
		end
		PlayErrorSound()
		return
	end

	local isMaxLevelAfter = type(payload) == "table" and payload.IsMaxLevelAfter == true
	PlayPanelClose()

	if not isMaxLevelAfter then
		task.delay(0.08, function()
			if not rebirthBg or rebirthBg.Visible then
				if not rebirthBg then
					ReleaseBackpackHide()
				end
				return
			end
			if not PlayPanelOpen() then
				ReleaseBackpackHide()
				return
			end
			RequestBackpackHide()
			RequestLatestData()
		end)
	else
		ReleaseBackpackHide()
		RequestLatestData()
	end
end

local function BindEvents()
	if rebirthDataEvent then
		rebirthDataEvent.OnClientEvent:Connect(function(payload)
			ApplyPayload(payload)
		end)
	end

	if rebirthStateChangedEvent then
		rebirthStateChangedEvent.OnClientEvent:Connect(function(payload)
			ApplyPayload(payload)
		end)
	end

	if rebirthResultEvent then
		rebirthResultEvent.OnClientEvent:Connect(OnRebirthResult)
	end

	if eventsFolder then
		local campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
		if not campaignEvents then
			campaignEvents = eventsFolder:WaitForChild("CampaignEvents", 5)
		end
		if campaignEvents then
			campaignStateUpdateEvent = campaignEvents:FindFirstChild("CampaignStateUpdate")
			if not campaignStateUpdateEvent then
				campaignStateUpdateEvent = campaignEvents:WaitForChild("CampaignStateUpdate", 5)
			end
			if campaignStateUpdateEvent and campaignStateUpdateEvent:IsA("RemoteEvent") then
				campaignStateUpdateEvent.OnClientEvent:Connect(function(state)
					local battle = state ~= "Idle"
					if isBattleBlocked == battle then
						return
					end

					isBattleBlocked = battle
					if isBattleBlocked and rebirthBg and rebirthBg.Visible then
						PlayPanelClose()
						ReleaseBackpackHide()
					end
				end)
			end
		end
	end

	if eventsFolder then
		currencyUpdateEvent = eventsFolder:FindFirstChild("CurrencyEvents")
		if currencyUpdateEvent and currencyUpdateEvent:IsA("RemoteEvent") then
			currencyUpdateEvent.OnClientEvent:Connect(function(currencyType, newAmount)
				if tostring(currencyType or "") ~= COIN_CURRENCY_TYPE then
					return
				end
				ApplyLiveCoinUpdate(newAmount)
			end)
		end

		local inventoryEvents = eventsFolder:FindFirstChild("InventoryEvents")
		if inventoryEvents then
			unitUpdatedEvent = inventoryEvents:FindFirstChild("UnitUpdated")
			if unitUpdatedEvent and unitUpdatedEvent:IsA("RemoteEvent") then
				unitUpdatedEvent.OnClientEvent:Connect(function(unitId, _, count)
					ApplyLiveUnitCountUpdate(unitId, count)
				end)
			end

			inventoryRefreshEvent = inventoryEvents:FindFirstChild("InventoryRefresh")
			if inventoryRefreshEvent and inventoryRefreshEvent:IsA("RemoteEvent") then
				inventoryRefreshEvent.OnClientEvent:Connect(function(inventoryData)
					if type(currentPayload) ~= "table" then
						return
					end

					local requiredUnitId = tostring(currentPayload.RequiredUnitId or "")
					if requiredUnitId == "" then
						return
					end

					local unitData = type(inventoryData) == "table" and inventoryData[requiredUnitId] or nil
					local count = 0
					if type(unitData) == "table" then
						count = tonumber(unitData.Count) or 0
					end
					ApplyLiveUnitCountUpdate(requiredUnitId, count)
				end)
			end
		end
	end
end

local function Initialize()
	if initialized then
		return
	end

	if not InitializeUI() then
		task.delay(2, Initialize)
		return
	end
	if not InitializeEvents() then
		task.delay(2, Initialize)
		return
	end

	initialized = true
	BindButtons()
	BindEvents()
	UpdateMainButton(nil)
	RequestLatestData()

	player:GetAttributeChangedSignal("RebirthCount"):Connect(function()
		UpdateMainButton(currentPayload)
	end)
end

Initialize()


