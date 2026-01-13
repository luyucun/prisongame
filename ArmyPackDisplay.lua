--[[
Script Name: ArmyPackDisplay
Script Type: LocalScript (Client UI)
Script Location: StarterPlayer/StarterPlayerScripts/UI/ArmyPackDisplay
Version: V5.6
Responsibility: Army pack dev product purchase and reward popup
]]

local ArmyPackDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

local ButtonEffectHelper = nil

local PACK_CONFIGS = {
	{ FrameName = "ArmyPack01", ProductId = 3511148249 },
	{ FrameName = "ArmyPack02", ProductId = 3511148622 },
}

local productIdSet = {}
local function GetProductKey(productId)
	return tostring(productId or "")
end
for _, config in ipairs(PACK_CONFIGS) do
	productIdSet[GetProductKey(config.ProductId)] = true
end

local armyPackEvents = nil
local purchaseResultEvent = nil

local shopGui = nil
local shopBg = nil
local scrollingFrame = nil
local buyButtons = {}
local boundButtons = {}
local dataBound = false

local claimTipsGui = nil
local purchaseSuccess = nil
local purchaseBg = nil
local itemListFrame = nil
local itemTemplate = nil
local lightBg = nil
local lightImage = nil

local promptLocks = {}

local popupVisible = false
local popupAllowClose = false
local popupToken = 0
local popupInputConnection = nil
local lightRotateConnection = nil

local POPUP_BG_OFFSET = 0.08
local POPUP_TWEEN_DURATION = 0.3
local POPUP_ALLOW_CLOSE_SECONDS = 1
local LIGHT_ROTATE_SPEED = 60

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

	warn("[ArmyPackDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function IsDescendantOfPlayerGui(instance)
	return instance ~= nil and instance:IsDescendantOf(playerGui)
end

local function ResolveButton(container)
	if not container then
		return nil
	end
	if container:IsA("TextButton") or container:IsA("ImageButton") then
		return container
	end
	return container:FindFirstChild("Button")
		or container:FindFirstChildWhichIsA("TextButton")
		or container:FindFirstChildWhichIsA("ImageButton")
end

local function InitializeEvents()
	if armyPackEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[ArmyPackDisplay] Events folder not found")
		return false
	end

	armyPackEvents = eventsFolder:WaitForChild("ArmyPackEvents", 10)
	if not armyPackEvents then
		warn("[ArmyPackDisplay] ArmyPackEvents not found")
		return false
	end

	purchaseResultEvent = armyPackEvents:WaitForChild("ArmyPackPurchaseResult", 5)
	if not purchaseResultEvent then
		warn("[ArmyPackDisplay] ArmyPackPurchaseResult not found")
		return false
	end

	return true
end

local function InitializeUI()
	local shopValid = IsDescendantOfPlayerGui(shopBg)
	local popupValid = IsDescendantOfPlayerGui(purchaseSuccess)

	if shopValid and popupValid then
		return true
	end

	shopGui = SafeWaitForChild(playerGui, "Shop", 5)
	shopBg = shopGui and shopGui:FindFirstChild("ShopBg")
	scrollingFrame = shopBg and shopBg:FindFirstChild("ScrollingFrame")

	buyButtons = {}
	if scrollingFrame then
		for _, config in ipairs(PACK_CONFIGS) do
			local packFrame = scrollingFrame:FindFirstChild(config.FrameName)
			local buyButton = ResolveButton(packFrame and packFrame:FindFirstChild("BuyButton"))
			if buyButton then
				buyButtons[config.ProductId] = buyButton
			end
		end
	end

	claimTipsGui = SafeWaitForChild(playerGui, "ClaimTipsGui", 5)
	purchaseSuccess = claimTipsGui and claimTipsGui:FindFirstChild("PurchaseSuccessful")
	purchaseBg = purchaseSuccess and purchaseSuccess:FindFirstChild("Bg")
	itemListFrame = purchaseBg and purchaseBg:FindFirstChild("ItemListFrame")
	itemTemplate = itemListFrame and itemListFrame:FindFirstChild("ItemTemplate")
	lightBg = claimTipsGui and claimTipsGui:FindFirstChild("LightBg")
	lightImage = lightBg and lightBg:FindFirstChild("Light")

	if itemTemplate then
		itemTemplate.Visible = false
	end
	if purchaseSuccess then
		purchaseSuccess.Visible = false
	end
	if lightBg then
		lightBg.Visible = false
	end

	return shopBg ~= nil
end

local function PromptPurchase(productId)
	local key = GetProductKey(productId)
	if key == "" then
		return
	end
	if promptLocks[key] then
		return
	end

	promptLocks[key] = true
	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not success then
		promptLocks[key] = nil
		warn("[ArmyPackDisplay] PromptProductPurchase failed:", err)
		local tipsSystem = _G.TipsSystem
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError("Purchase failed")
		end
		return
	end

	task.delay(5, function()
		if promptLocks[key] then
			promptLocks[key] = nil
		end
	end)
end

local function BindButtons()
	LoadButtonEffectHelper()

	for productId, button in pairs(buyButtons) do
		if button and (button:IsA("TextButton") or button:IsA("ImageButton")) then
			if not boundButtons[button] then
				if ButtonEffectHelper then
					ButtonEffectHelper.AddClickEffect(button, { OnClick = function()
						PromptPurchase(productId)
					end })
				else
					button.MouseButton1Click:Connect(function()
						PromptPurchase(productId)
					end)
				end
				boundButtons[button] = true
			end
		end
	end
end

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
	if not purchaseBg or not purchaseBg:IsA("GuiObject") then
		return
	end

	local originalPos = purchaseBg.Position
	purchaseBg.Position = UDim2.new(
		originalPos.X.Scale,
		originalPos.X.Offset,
		originalPos.Y.Scale + POPUP_BG_OFFSET,
		originalPos.Y.Offset
	)

	TweenService:Create(
		purchaseBg,
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

	if purchaseSuccess then
		purchaseSuccess.Visible = false
	end
	if lightBg then
		lightBg.Visible = false
	end

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

	popupInputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if not popupVisible or not popupAllowClose or popupToken ~= token then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ClosePopup()
		end
	end)
end

local function ResolveIcon(item)
	if item.Type == "Unit" then
		return UnitConfig.GetIcon(item.UnitId)
	end
	return ""
end

local function ShowPopup(items)
	if not claimTipsGui or not purchaseSuccess or not purchaseBg then
		return
	end

	if popupVisible then
		ClosePopup()
	end

	ClearPopupItems()

	if itemTemplate and type(items) == "table" then
		for _, reward in ipairs(items) do
			local item = itemTemplate:Clone()
			item.Visible = true
			item.Name = "ItemReward"

			local icon = item:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				icon.Image = ResolveIcon(reward)
			end

			local numberLabel = item:FindFirstChild("Number")
			if numberLabel and numberLabel:IsA("TextLabel") then
				numberLabel.Text = tostring(reward.Count or 1)
			end

			item.Parent = itemListFrame
		end
	end

	purchaseSuccess.Visible = true
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

local function OnPurchaseResult(success, message, productId, rewards)
	local key = GetProductKey(productId)
	if key ~= "" and promptLocks[key] then
		promptLocks[key] = nil
	end

	local tipsSystem = _G.TipsSystem
	if success then
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Purchase Successful!")
		end
		ShowPopup(rewards)
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Purchase failed")
		end
	end
end

local function BindData()
	if dataBound or not purchaseResultEvent then
		return
	end

	purchaseResultEvent.OnClientEvent:Connect(OnPurchaseResult)
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
	end

	return eventsReady and uiReady
end

function ArmyPackDisplay.Initialize()
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
		if child.Name ~= "Shop" and child.Name ~= "ClaimTipsGui" then
			return
		end

		task.spawn(function()
			task.wait()
			TryInitialize()
		end)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId)
		if userId ~= player.UserId then
			return
		end
		local key = GetProductKey(productId)
		if productIdSet[key] then
			promptLocks[key] = nil
		end
	end)
end

ArmyPackDisplay.Initialize()

return ArmyPackDisplay
