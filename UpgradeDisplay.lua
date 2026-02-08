--[[
脚本名称: UpgradeDisplay
脚本类型: LocalScript (客户端UI)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/UpgradeDisplay
版本: V6.7
职责: 养成界面展示、开关动效与购买交互
]]

local UpgradeDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UpgradeConfig"))
local FormatHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FormatHelper"))

local ButtonEffectHelper = nil
local boundButtons = {}
local dataBound = false

local upgradeEvents = nil
local requestUpgradeDataEvent = nil
local upgradeDataEvent = nil
local purchaseUpgradeByCoinEvent = nil
local purchaseUpgradeByRobuxEvent = nil
local upgradePurchaseResultEvent = nil

local mainGui = nil
local openButton = nil
local upgradeGui = nil
local levelUpBg = nil
local dimBg = nil
local closeButton = nil
local scrollingFrame = nil

local optionByType = {}
local entryByType = {}
local pendingByType = {}

local panelScale = nil
local panelAnimating = false
local panelOpenTweenA = nil
local panelOpenTweenB = nil
local panelCloseTweenA = nil
local panelCloseTweenB = nil

local PANEL_OPEN_START_SCALE = 0.86
local PANEL_OPEN_OVERSHOOT_SCALE = 1.10
local PANEL_OPEN_DURATION_A = 0.18
local PANEL_OPEN_DURATION_B = 0.10
local PANEL_CLOSE_OVERSHOOT_SCALE = 1.12
local PANEL_CLOSE_END_SCALE = 0.78
local PANEL_CLOSE_DURATION_A = 0.08
local PANEL_CLOSE_DURATION_B = 0.12

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

	warn("[UpgradeDisplay] ButtonEffectHelper加载失败:", result)
	return false
end

local function ShowError(text)
	local tipsSystem = _G.TipsSystem
	if tipsSystem and tipsSystem.ShowError then
		tipsSystem.ShowError(text or "Upgrade failed")
		return
	end
	warn("[UpgradeDisplay]", text)
end

local function InitializeEvents()
	if upgradeEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[UpgradeDisplay] Events folder missing")
		return false
	end

	upgradeEvents = eventsFolder:WaitForChild("UpgradeEvents", 10)
	if not upgradeEvents then
		warn("[UpgradeDisplay] UpgradeEvents missing")
		return false
	end

	requestUpgradeDataEvent = upgradeEvents:WaitForChild("RequestUpgradeData", 5)
	upgradeDataEvent = upgradeEvents:WaitForChild("UpgradeData", 5)
	purchaseUpgradeByCoinEvent = upgradeEvents:WaitForChild("PurchaseUpgradeByCoin", 5)
	purchaseUpgradeByRobuxEvent = upgradeEvents:WaitForChild("PurchaseUpgradeByRobux", 5)
	upgradePurchaseResultEvent = upgradeEvents:WaitForChild("UpgradePurchaseResult", 5)

	if not (requestUpgradeDataEvent and upgradeDataEvent and purchaseUpgradeByCoinEvent and purchaseUpgradeByRobuxEvent and upgradePurchaseResultEvent) then
		warn("[UpgradeDisplay] UpgradeEvents incomplete")
		return false
	end

	return true
end

local function ResolveOptionByType(typeId)
	if not scrollingFrame then
		return nil
	end

	if optionByType[typeId] and optionByType[typeId].Parent then
		return optionByType[typeId]
	end

	for index, orderedTypeId in ipairs(UpgradeConfig.GetTypeIds()) do
		if orderedTypeId == typeId then
			local optionName = string.format("Option%02d", index)
			optionByType[typeId] = scrollingFrame:FindFirstChild(optionName)
			break
		end
	end

	return optionByType[typeId]
end

local function InitializeUI()
	if levelUpBg and levelUpBg.Parent and dimBg and dimBg.Parent and openButton and openButton.Parent then
		return true
	end

	mainGui = playerGui:FindFirstChild("MainGui") or playerGui:WaitForChild("MainGui", 5)
	upgradeGui = playerGui:FindFirstChild("Upgrade") or playerGui:WaitForChild("Upgrade", 5)

	if not mainGui or not upgradeGui then
		return false
	end

	openButton = mainGui:FindFirstChild("Upgrade", true)
	levelUpBg = upgradeGui:FindFirstChild("LevelUpBg", true)
	dimBg = upgradeGui:FindFirstChild("Bg", true)

	if not openButton or not levelUpBg or not dimBg then
		return false
	end

	local title = levelUpBg:FindFirstChild("Title", true)
	closeButton = (title and title:FindFirstChild("CloseButton")) or levelUpBg:FindFirstChild("CloseButton", true)
	scrollingFrame = levelUpBg:FindFirstChild("ScrollingFrame", true)

	optionByType = {}
	for _, typeId in ipairs(UpgradeConfig.GetTypeIds()) do
		ResolveOptionByType(typeId)
	end

	levelUpBg.Visible = false
	dimBg.Visible = false

	return true
end

local function EnsurePanelScale()
	if not levelUpBg then
		return nil
	end

	if panelScale and panelScale.Parent == levelUpBg then
		return panelScale
	end

	panelScale = levelUpBg:FindFirstChild("OpenScale")
	if not panelScale then
		panelScale = Instance.new("UIScale")
		panelScale.Name = "OpenScale"
		panelScale.Scale = 1
		panelScale.Parent = levelUpBg
	end

	return panelScale
end

local function StopPanelTweens()
	local tweens = { panelOpenTweenA, panelOpenTweenB, panelCloseTweenA, panelCloseTweenB }
	for _, tween in ipairs(tweens) do
		if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
			tween:Cancel()
		end
	end
end

local function PlayPanelOpen()
	if not InitializeUI() then
		return
	end

	local scale = EnsurePanelScale()
	if not scale then
		levelUpBg.Visible = true
		dimBg.Visible = true
		return
	end

	StopPanelTweens()
	panelAnimating = true

	dimBg.Visible = true
	levelUpBg.Visible = true
	scale.Scale = PANEL_OPEN_START_SCALE

	panelOpenTweenA = TweenService:Create(scale, TweenInfo.new(PANEL_OPEN_DURATION_A, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = PANEL_OPEN_OVERSHOOT_SCALE,
	})
	panelOpenTweenB = TweenService:Create(scale, TweenInfo.new(PANEL_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	})

	local connA
	local connB
	connA = panelOpenTweenA.Completed:Connect(function(state)
		if connA then connA:Disconnect() end
		if state == Enum.PlaybackState.Completed and panelOpenTweenB then
			panelOpenTweenB:Play()
		end
	end)
	connB = panelOpenTweenB.Completed:Connect(function()
		if connB then connB:Disconnect() end
		panelAnimating = false
	end)

	panelOpenTweenA:Play()
end

local function PlayPanelClose()
	if not InitializeUI() then
		return
	end

	local scale = EnsurePanelScale()
	if not scale then
		levelUpBg.Visible = false
		dimBg.Visible = false
		return
	end

	StopPanelTweens()
	panelAnimating = true

	panelCloseTweenA = TweenService:Create(scale, TweenInfo.new(PANEL_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = PANEL_CLOSE_OVERSHOOT_SCALE,
	})
	panelCloseTweenB = TweenService:Create(scale, TweenInfo.new(PANEL_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = PANEL_CLOSE_END_SCALE,
	})

	local connA
	local connB
	connA = panelCloseTweenA.Completed:Connect(function(state)
		if connA then connA:Disconnect() end
		if state == Enum.PlaybackState.Completed and panelCloseTweenB then
			panelCloseTweenB:Play()
		end
	end)
	connB = panelCloseTweenB.Completed:Connect(function()
		if connB then connB:Disconnect() end
		panelAnimating = false
		levelUpBg.Visible = false
		dimBg.Visible = false
		scale.Scale = 1
	end)

	panelCloseTweenA:Play()
end

local function OpenPanel()
	PlayPanelOpen()
	if requestUpgradeDataEvent then
		requestUpgradeDataEvent:FireServer()
	end
end

local function ClosePanel()
	PlayPanelClose()
end

local function RenderOption(option, entry)
	if not option or not entry then
		return
	end

	local levelLabel = option:FindFirstChild("Level")
	local bonusLabel = option:FindFirstChild("Num")
	local coinBuy = option:FindFirstChild("CoinBuy")
	local rbxBuy = option:FindFirstChild("RbxBuy")
	local priceLabel = coinBuy and coinBuy:FindFirstChild("Price")

	if levelLabel then
		if entry.IsMax then
			levelLabel.Text = "Lv.Max"
		else
			levelLabel.Text = string.format("Lv.%d", tonumber(entry.CurrentLevel) or 0)
		end
	end

	if bonusLabel then
		bonusLabel.Text = UpgradeConfig.FormatBonusPercent(entry.CurrentBonusRatio)
	end

	if priceLabel and not entry.IsMax then
		local nextPrice = tonumber(entry.NextPrice) or 0
		priceLabel.Text = FormatHelper.FormatCoinsShort(nextPrice, true)
	end

	if coinBuy then
		coinBuy.Visible = not entry.IsMax
	end
	if rbxBuy then
		rbxBuy.Visible = not entry.IsMax
	end
end

local function RenderAll()
	for _, typeId in ipairs(UpgradeConfig.GetTypeIds()) do
		local option = ResolveOptionByType(typeId)
		local entry = entryByType[typeId]
		RenderOption(option, entry)
	end
end

local function OnUpgradeData(payload)
	entryByType = {}
	if type(payload) == "table" and type(payload.Entries) == "table" then
		for _, entry in ipairs(payload.Entries) do
			local typeId = tonumber(entry.TypeId)
			if typeId then
				entryByType[typeId] = entry
				pendingByType[typeId] = nil
			end
		end
	end

	RenderAll()
end

local function OnUpgradePurchaseResult(payload)
	if type(payload) ~= "table" then
		return
	end

	local typeId = tonumber(payload.TypeId)
	if typeId then
		pendingByType[typeId] = nil
	end

	if payload.Success ~= true then
		ShowError(payload.Message or "Upgrade failed")
		return
	end

	if requestUpgradeDataEvent then
		requestUpgradeDataEvent:FireServer()
	end
end

local function BindButtonOnce(button, callback)
	if not button or boundButtons[button] then
		return
	end

	boundButtons[button] = true
	if ButtonEffectHelper then
		ButtonEffectHelper.AddClickEffect(button, { OnClick = callback })
	else
		button.MouseButton1Click:Connect(callback)
	end
end

local function BindOptionButtons(typeId)
	local option = ResolveOptionByType(typeId)
	if not option then
		return
	end

	local coinBuy = option:FindFirstChild("CoinBuy")
	local rbxBuy = option:FindFirstChild("RbxBuy")

	if coinBuy and (coinBuy:IsA("TextButton") or coinBuy:IsA("ImageButton")) then
		BindButtonOnce(coinBuy, function()
			local entry = entryByType[typeId]
			if not entry or entry.IsMax then
				return
			end
			if pendingByType[typeId] then
				return
			end
			pendingByType[typeId] = true
			if purchaseUpgradeByCoinEvent then
				purchaseUpgradeByCoinEvent:FireServer(typeId)
			end
		end)
	end

	if rbxBuy and (rbxBuy:IsA("TextButton") or rbxBuy:IsA("ImageButton")) then
		BindButtonOnce(rbxBuy, function()
			local entry = entryByType[typeId]
			if not entry or entry.IsMax then
				return
			end
			if pendingByType[typeId] then
				return
			end
			pendingByType[typeId] = true
			if purchaseUpgradeByRobuxEvent then
				purchaseUpgradeByRobuxEvent:FireServer(typeId)
				-- Prompt cancellation has no receipt callback; auto-unlock stale state
				task.delay(0.8, function()
					if pendingByType[typeId] then
						pendingByType[typeId] = nil
					end
				end)
			else
				pendingByType[typeId] = nil
			end
		end)
	end
end

local function BindButtons()
	LoadButtonEffectHelper()

	if openButton and (openButton:IsA("TextButton") or openButton:IsA("ImageButton")) then
		BindButtonOnce(openButton, OpenPanel)
	end

	if closeButton and (closeButton:IsA("TextButton") or closeButton:IsA("ImageButton")) then
		BindButtonOnce(closeButton, ClosePanel)
	end

	for _, typeId in ipairs(UpgradeConfig.GetTypeIds()) do
		BindOptionButtons(typeId)
	end
end

local function BindDataEvents()
	if dataBound then
		return
	end

	upgradeDataEvent.OnClientEvent:Connect(OnUpgradeData)
	upgradePurchaseResultEvent.OnClientEvent:Connect(OnUpgradePurchaseResult)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if uiReady then
		BindButtons()
		RenderAll()
	end

	if eventsReady then
		BindDataEvents()
		requestUpgradeDataEvent:FireServer()
	end

	return eventsReady and uiReady
end

function UpgradeDisplay.Initialize()
	if TryInitialize() then
		return
	end

	task.spawn(function()
		local attempts = 0
		while attempts < 6 and not TryInitialize() do
			attempts += 1
			task.wait(2)
		end
	end)

	playerGui.ChildAdded:Connect(function(child)
		if not child then
			return
		end
		if child.Name ~= "MainGui" and child.Name ~= "Upgrade" then
			return
		end
		task.defer(TryInitialize)
	end)
end

UpgradeDisplay.Initialize()

return UpgradeDisplay
