--[[
脚本名称: VipDisplay
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/VipDisplay
版本: V5.5
职责: VIP礼包UI购买与状态显示
]]

local VipDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local VipConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("VipConfig"))
local RobuxPriceHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RobuxPriceHelper"))

local ButtonEffectHelper = nil

-- Events
local vipEvents = nil
local requestDataEvent = nil
local vipDataEvent = nil
local purchaseEvent = nil
local purchaseResultEvent = nil

-- UI
local shopGui = nil
local shopBg = nil
local vipFrame = nil
local buyButton = nil
local buyButtonContainer = nil
local buyButtonText = nil
local rightPriceLabel = nil
local purchasedLabel = nil
local defaultBuyButtonText = nil
local defaultButtonText = nil
local defaultButtonTextColor = nil
local defaultImageButtonColor = nil

local cachedPurchased = nil
local purchaseLock = false
local dataBound = false
local boundButtons = {}

-- ==================== Helpers ====================

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

	warn("[VipDisplay] ButtonEffectHelper加载失败:", result)
	return false
end

local function InitializeEvents()
	if vipEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[VipDisplay] Events文件夹未找到")
		return false
	end

	vipEvents = eventsFolder:WaitForChild("VipEvents", 10)
	if not vipEvents then
		warn("[VipDisplay] VipEvents未找到")
		return false
	end

	requestDataEvent = vipEvents:WaitForChild("RequestVipData", 5)
	vipDataEvent = vipEvents:WaitForChild("VipData", 5)
	purchaseEvent = vipEvents:WaitForChild("PurchaseVip", 5)
	purchaseResultEvent = vipEvents:WaitForChild("VipPurchaseResult", 5)

	if not (requestDataEvent and vipDataEvent and purchaseEvent and purchaseResultEvent) then
		warn("[VipDisplay] VipEvents事件不完整")
		return false
	end

	return true
end

local function InitializeUI()
	shopGui = SafeWaitForChild(playerGui, "Shop", 5)
	shopBg = shopGui and shopGui:FindFirstChild("ShopBg")
	if not shopBg then
		return false
	end

	local scrollingFrame = shopBg:FindFirstChild("ScrollingFrame")
	vipFrame = scrollingFrame and scrollingFrame:FindFirstChild("Vip") or shopBg:FindFirstChild("Vip")
	if not vipFrame then
		return false
	end

	buyButtonContainer = vipFrame:FindFirstChild("BuyButton")
	buyButton = buyButtonContainer
	if buyButton and not (buyButton:IsA("TextButton") or buyButton:IsA("ImageButton")) then
		local inner = buyButton:FindFirstChild("Button")
			or buyButton:FindFirstChildWhichIsA("TextButton")
			or buyButton:FindFirstChildWhichIsA("ImageButton")
		if inner then
			buyButton = inner
		end
	end

	if buyButton then
		buyButtonText = buyButton:FindFirstChild("Text") or buyButton:FindFirstChildWhichIsA("TextLabel")
	end

	rightPriceLabel = buyButtonContainer and buyButtonContainer:FindFirstChild("RightPrice", true) or nil
	if rightPriceLabel then
		RobuxPriceHelper.UpdateGamePassLabel(rightPriceLabel, VipConfig.GAMEPASS_ID, nil)
	end

	purchasedLabel = vipFrame:FindFirstChild("Purchased")

	if buyButtonText and defaultBuyButtonText == nil then
		defaultBuyButtonText = buyButtonText.Text
	end
	if buyButton and buyButton:IsA("TextButton") then
		if defaultButtonText == nil then
			defaultButtonText = buyButton.Text
		end
		if defaultButtonTextColor == nil then
			defaultButtonTextColor = buyButton.TextColor3
		end
	elseif buyButton and buyButton:IsA("ImageButton") then
		if defaultImageButtonColor == nil then
			defaultImageButtonColor = buyButton.ImageColor3
		end
	end

	return buyButton ~= nil
end

local function UpdateButtonState()
	local attrValue = player:GetAttribute("VipPurchased")
	local attrPurchased = attrValue == true
	local purchased = attrPurchased
	if cachedPurchased ~= nil then
		purchased = cachedPurchased
		if attrValue ~= nil and cachedPurchased ~= attrPurchased then
			cachedPurchased = attrPurchased
			purchased = attrPurchased
		end
	end

	if buyButton and (buyButton:IsA("TextButton") or buyButton:IsA("ImageButton")) then
		buyButton.Active = purchased ~= true
		buyButton.AutoButtonColor = purchased ~= true
	end

	if buyButtonContainer and buyButtonContainer ~= buyButton then
		buyButtonContainer.Visible = purchased ~= true
	end
	if buyButton then
		buyButton.Visible = purchased ~= true
	end
	if purchasedLabel then
		purchasedLabel.Visible = purchased == true
	end

	if buyButtonText and buyButtonText:IsA("TextLabel") then
		if purchased then
			buyButtonText.Text = "Purchased"
		elseif defaultBuyButtonText ~= nil then
			buyButtonText.Text = defaultBuyButtonText
		end
	end

	if buyButton and buyButton:IsA("TextButton") then
		if purchased then
			buyButton.Text = "Purchased"
			buyButton.TextColor3 = Color3.fromRGB(180, 180, 180)
		else
			if defaultButtonText ~= nil then
				buyButton.Text = defaultButtonText
			end
			if defaultButtonTextColor ~= nil then
				buyButton.TextColor3 = defaultButtonTextColor
			end
		end
	elseif buyButton and buyButton:IsA("ImageButton") then
		if purchased then
			buyButton.ImageColor3 = Color3.fromRGB(180, 180, 180)
		elseif defaultImageButtonColor ~= nil then
			buyButton.ImageColor3 = defaultImageButtonColor
		end
	end
end

local function OnVipData(data)
	local purchased = false
	if type(data) == "table" then
		purchased = data.Purchased == true
	elseif type(data) == "boolean" then
		purchased = data == true
	end

	cachedPurchased = purchased
	UpdateButtonState()
end

local function OnPurchaseResult(success, message)
	purchaseLock = false

	local tipsSystem = _G.TipsSystem
	if success then
		if tipsSystem and tipsSystem.ShowSuccess then
			tipsSystem.ShowSuccess(message or "Purchase Successful!")
		end
	else
		if tipsSystem and tipsSystem.ShowError then
			tipsSystem.ShowError(message or "Purchase failed")
		end
	end

	if requestDataEvent then
		requestDataEvent:FireServer()
	end
end

local function OnBuyButtonClicked()
	if purchaseLock then
		return
	end

	if cachedPurchased == true or player:GetAttribute("VipPurchased") == true then
		return
	end

	if purchaseEvent then
		purchaseLock = true
		purchaseEvent:FireServer()
		task.delay(2, function()
			purchaseLock = false
		end)
	end
end

local function BindButtons()
	LoadButtonEffectHelper()

	if buyButton and (buyButton:IsA("TextButton") or buyButton:IsA("ImageButton")) then
		if not boundButtons[buyButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(buyButton, { OnClick = OnBuyButtonClicked })
			else
				buyButton.MouseButton1Click:Connect(OnBuyButtonClicked)
			end
			boundButtons[buyButton] = true
		end
	end
end

local function BindData()
	if dataBound or not vipDataEvent then
		return
	end

	vipDataEvent.OnClientEvent:Connect(OnVipData)
	purchaseResultEvent.OnClientEvent:Connect(OnPurchaseResult)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if uiReady then
		BindButtons()
		UpdateButtonState()
	end

	if eventsReady then
		BindData()
		if requestDataEvent then
			requestDataEvent:FireServer()
		end
	end

	return eventsReady and uiReady
end

function VipDisplay.Initialize()
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

	player:GetAttributeChangedSignal("VipPurchased"):Connect(function()
		cachedPurchased = player:GetAttribute("VipPurchased") == true
		UpdateButtonState()
	end)
end

VipDisplay.Initialize()

return VipDisplay
