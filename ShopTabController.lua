--[[
Script Name: ShopTabController
Script Type: LocalScript (Client UI)
Script Location: StarterPlayer/StarterPlayerScripts/Controllers/ShopTabController.lua
Version: V5.7
Responsibility: Handle shop tab clicks and align scroll position based on starter pack purchase.
]]

local ShopTabController = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ButtonEffectHelper = nil

-- UI references
local shopGui = nil
local shopBg = nil
local scrollingFrame = nil
local tabList = nil

local tabNewPlayer = nil
local tabDailyGift = nil
local tabVip = nil
local tabHeroPack = nil
local tabLukcy = nil

-- State
local boundButtons = {}
local lastSelectedTab = nil

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

	warn("[ShopTabController] ButtonEffectHelper load failed:", result)
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

	local button = container:FindFirstChild("Button")
	if button and (button:IsA("TextButton") or button:IsA("ImageButton")) then
		return button
	end

	return container:FindFirstChildWhichIsA("TextButton")
		or container:FindFirstChildWhichIsA("ImageButton")
end

local function GetDeviceType()
	-- Desktop: keyboard+mouse
	if UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		return "Desktop"
	end

	-- Touch devices: split phone/tablet by viewport size
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local camera = workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			local minAxis = math.min(size.X, size.Y)
			if minAxis >= 700 then
				return "Tablet"
			end
		end
		return "Mobile"
	end

	return "Desktop"
end

local function GetCanvasPosition(tabName)
	if tabName == "NewPlayer" then
		return Vector2.new(0, 0)
	end
	if tabName == "DailyGift" then
		return Vector2.new(0, 100)
	end
	if tabName == "Vip" then
		local device = GetDeviceType()
		if device == "Mobile" then
			return Vector2.new(0, 200)
		end
		if device == "Tablet" then
			return Vector2.new(0, 300)
		end
		return Vector2.new(0, 400)
	end
	if tabName == "HeroPack" then
		local device = GetDeviceType()
		if device == "Mobile" then
			return Vector2.new(0, 400)
		end
		if device == "Tablet" then
			return Vector2.new(0, 600)
		end
		return Vector2.new(0, 700)
	end
	if tabName == "Lukcy" then
		return Vector2.new(0, 0)
	end

	return Vector2.new(0, 0)
end

local function ApplyTabScroll(tabName)
	lastSelectedTab = tabName
	if not scrollingFrame then
		return
	end

	scrollingFrame.CanvasPosition = GetCanvasPosition(tabName)
end

-- ==================== Initialization ====================

local function InitializeUI()
	local shopValid = IsDescendantOfPlayerGui(shopBg)
	local listValid = IsDescendantOfPlayerGui(tabList)
	local scrollValid = IsDescendantOfPlayerGui(scrollingFrame)
	if shopValid and listValid and scrollValid then
		return true
	end

	shopGui = SafeWaitForChild(playerGui, "Shop", 5)
	shopBg = shopGui and shopGui:FindFirstChild("ShopBg")
	if not shopBg then
		return false
	end

	scrollingFrame = shopBg:FindFirstChild("ScrollingFrame")
	tabList = shopBg:FindFirstChild("TabList")

	tabNewPlayer = tabList and tabList:FindFirstChild("NewPlayer")
	tabDailyGift = tabList and tabList:FindFirstChild("DailyGift")
	tabVip = tabList and tabList:FindFirstChild("Vip")
	tabHeroPack = tabList and tabList:FindFirstChild("HeroPack")
	tabLukcy = tabList and tabList:FindFirstChild("Lukcy")

	return scrollingFrame ~= nil and tabList ~= nil
end

local function BindTabButton(container, tabName)
	local button = ResolveButton(container)
	if not button then
		return
	end
	if boundButtons[button] then
		return
	end

	if ButtonEffectHelper then
		ButtonEffectHelper.AddClickEffect(button, { OnClick = function()
			ApplyTabScroll(tabName)
		end })
	else
		button.MouseButton1Click:Connect(function()
			ApplyTabScroll(tabName)
		end)
	end

	boundButtons[button] = true
end

local function BindButtons()
	LoadButtonEffectHelper()

	BindTabButton(tabNewPlayer, "NewPlayer")
	BindTabButton(tabDailyGift, "DailyGift")
	BindTabButton(tabVip, "Vip")
	BindTabButton(tabHeroPack, "HeroPack")
	BindTabButton(tabLukcy, "Lukcy")
end

local function TryInitialize()
	local uiReady = InitializeUI()
	if uiReady then
		BindButtons()
		if lastSelectedTab then
			ApplyTabScroll(lastSelectedTab)
		end
	end

	return uiReady
end

function ShopTabController.Initialize()
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

	player:GetAttributeChangedSignal("StarterPackPurchased"):Connect(function()
		if lastSelectedTab then
			ApplyTabScroll(lastSelectedTab)
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
end

ShopTabController.Initialize()

return ShopTabController
