--[[
Script Name: FastRestockDisplay
Script Type: LocalScript (Client UI)
Script Location: StarterPlayer/StarterPlayerScripts/UI/FastRestockDisplay
Version: V6.8
Responsibility: Fast restock dev product purchase and countdown display
]]

local FastRestockDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local RobuxPriceHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RobuxPriceHelper"))

local ButtonEffectHelper = nil

local FAST_RESTOCK_PRODUCT_ID = 0
local fastConfig = GameConfig.Shop and GameConfig.Shop.FastRestock
if fastConfig and fastConfig.ProductId then
	FAST_RESTOCK_PRODUCT_ID = tonumber(fastConfig.ProductId) or 0
end

local LAST_TIME_ATTR = "UnitShopFastRestockEndTime"
local TIP_TEXT = "Prisoner Shop restock time reduced: 5 → 3 min"

-- UI references
local shopGui = nil
local shopBg = nil
local scrollingFrame = nil
local lukcyFrame = nil
local buyButtonContainer = nil
local buyButton = nil
local buyButtonPriceLabel = nil
local lastTimeLabel = nil

-- State
local boundBuyButton = nil
local countdownConn = nil
local countdownAccumulator = 0
local lastEndTime = 0
local initialized = false
local attributeBound = false

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

	warn("[FastRestockDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function ResolveButton(container)
	if not container then
		return nil
	end
	if container:IsA("TextButton") or container:IsA("ImageButton") then
		return container
	end

	local button = container:FindFirstChild("Button")
	if button and (button:IsA("TextButton") or button:IsA("ImageButton")) then
		return button
	end

	return container:FindFirstChildWhichIsA("TextButton")
		or container:FindFirstChildWhichIsA("ImageButton")
end

local function FormatRemaining(seconds)
	local remaining = math.max(0, math.floor(tonumber(seconds) or 0))
	local minutes = math.floor(remaining / 60)
	local secs = remaining % 60
	return string.format("%d:%02d", minutes, secs)
end

local function GetServerNow()
	local ok, serverNow = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(serverNow) == "number" and serverNow > 0 then
		return serverNow
	end
	return os.time()
end

local function StopCountdown()
	if countdownConn then
		countdownConn:Disconnect()
		countdownConn = nil
	end
	countdownAccumulator = 0
end

local function UpdateCountdown()
	if not lastTimeLabel then
		return
	end

	local remaining = math.max(0, (tonumber(lastEndTime) or 0) - GetServerNow())
	if remaining <= 0 then
		lastTimeLabel.Visible = false
		StopCountdown()
		return
	end

	lastTimeLabel.Visible = true
	lastTimeLabel.Text = FormatRemaining(remaining)
end

local function StartCountdown()
	if countdownConn then
		return
	end

	countdownAccumulator = 0
	UpdateCountdown()

	countdownConn = RunService.Heartbeat:Connect(function(dt)
		countdownAccumulator += dt
		if countdownAccumulator < 1 then
			return
		end
		countdownAccumulator = 0
		UpdateCountdown()
	end)
end

local function ShowPurchaseTip()
	local tips = _G.TipsSystem
	if tips and tips.ShowBuyTip then
		tips.ShowBuyTip(TIP_TEXT)
		return
	end
	if tips and tips.ShowSuccess then
		tips.ShowSuccess(TIP_TEXT)
	end
end

local function RefreshFromAttribute(showTip)
	local endTime = tonumber(player:GetAttribute(LAST_TIME_ATTR)) or 0
	if endTime < 0 then
		endTime = 0
	end

	local now = GetServerNow()
	if showTip and initialized and endTime > now and endTime > lastEndTime then
		ShowPurchaseTip()
	end

	lastEndTime = endTime

	if endTime > now then
		UpdateCountdown()
		StartCountdown()
	else
		if lastTimeLabel then
			lastTimeLabel.Visible = false
		end
		StopCountdown()
	end
end

local function WaitForFastRestockSync(prevEndTime)
	local startTime = tick()
	local maxWait = 6
	while tick() - startTime < maxWait do
		local current = tonumber(player:GetAttribute(LAST_TIME_ATTR)) or 0
		if current > (prevEndTime or 0) then
			RefreshFromAttribute(true)
			return
		end
		task.wait(0.2)
	end
	-- 兜底刷新一次，避免属性同步延迟导致不更新
	RefreshFromAttribute(true)
end

local function PromptPurchase()
	if FAST_RESTOCK_PRODUCT_ID <= 0 then
		warn("[FastRestockDisplay] Invalid product id")
		return
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, FAST_RESTOCK_PRODUCT_ID)
	end)
	if not ok then
		warn("[FastRestockDisplay] PromptProductPurchase failed:", err)
		local tips = _G.TipsSystem
		if tips and tips.ShowError then
			tips.ShowError("Purchase failed")
		end
	end
end

local function BindBuyButton()
	if not buyButton or buyButton == boundBuyButton then
		return
	end

	boundBuyButton = buyButton
	if LoadButtonEffectHelper() and ButtonEffectHelper then
		ButtonEffectHelper.AddClickEffect(buyButton, { OnClick = PromptPurchase })
	else
		buyButton.MouseButton1Click:Connect(PromptPurchase)
	end
end

local function InitializeUI()
	local shopValid = shopBg and shopBg:IsDescendantOf(playerGui)
	local lukcyValid = lukcyFrame and lukcyFrame:IsDescendantOf(playerGui)
	if shopValid and lukcyValid then
		return true
	end

	shopGui = SafeWaitForChild(playerGui, "Shop", 5)
	shopBg = shopGui and shopGui:FindFirstChild("ShopBg")
	scrollingFrame = shopBg and shopBg:FindFirstChild("ScrollingFrame")
	lukcyFrame = scrollingFrame and scrollingFrame:FindFirstChild("Lukcy", true)

	buyButtonContainer = lukcyFrame and lukcyFrame:FindFirstChild("BuyButton")
	buyButton = ResolveButton(buyButtonContainer)
	buyButtonPriceLabel = buyButtonContainer and buyButtonContainer:FindFirstChild("RightPrice", true) or nil
	lastTimeLabel = lukcyFrame and lukcyFrame:FindFirstChild("LastTime", true)

	if buyButtonPriceLabel and FAST_RESTOCK_PRODUCT_ID > 0 then
		RobuxPriceHelper.UpdateProductLabel(buyButtonPriceLabel, FAST_RESTOCK_PRODUCT_ID, nil)
	end

	if lastTimeLabel then
		lastTimeLabel.Visible = false
	end

	return shopBg ~= nil and lukcyFrame ~= nil
end

local function TryInitialize()
	local uiReady = InitializeUI()
	if uiReady then
		BindBuyButton()
		RefreshFromAttribute(false)
		initialized = true
	end

	if not attributeBound then
		attributeBound = true
		player:GetAttributeChangedSignal(LAST_TIME_ATTR):Connect(function()
			RefreshFromAttribute(true)
		end)
	end

	return uiReady
end

function FastRestockDisplay.Initialize()
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
		if not child or child.Name ~= "Shop" then
			return
		end

		task.spawn(function()
			task.wait()
			TryInitialize()
		end)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
		if userId ~= player.UserId then
			return
		end
		if not wasPurchased then
			return
		end
		if tonumber(productId) ~= tonumber(FAST_RESTOCK_PRODUCT_ID) then
			return
		end

		local prevEndTime = lastEndTime
		task.spawn(function()
			WaitForFastRestockSync(prevEndTime)
		end)
	end)
end

FastRestockDisplay.Initialize()

return FastRestockDisplay


