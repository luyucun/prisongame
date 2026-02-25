--[[
脚本名称: ShopTrigger
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayerScripts/UI/ShopTrigger
版本: V6.10
职责: 通过玩家触碰自家 PrisonerTouch 来打开/关闭兵种商店
]]

local ShopTrigger = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 收敛调试 print，避免刷屏（仅在 DEBUG_MODE 开启时输出）
local DEBUG_MODE = GameConfig.DEBUG_MODE
local _print = print
local function DebugPrint(...)
	if DEBUG_MODE then
		_print(...)
	end
end
local print = DebugPrint

-- 本地玩家
local player = Players.LocalPlayer

-- 状态变量
local isNearShop = false
local isShopOpen = false
local blockReopenUntilLeave = false
local checkConnection = nil
local closeButtonConnection = nil
local lastResolveTime = 0

-- PrisonerTouch 触发
local prisonerTouchPart = nil
local prisonerTouchConn = nil
local prisonerTouchEndedConn = nil
local prisonerTouchingParts = {}
local prisonerTouchActive = false

-- UI引用（延迟加载）
local shopUI = nil
local shopFrame = nil
local BACKPACK_HIDE_KEY = "Shop"
local TOUCH_RESOLVE_INTERVAL = 0.5

-- 事件引用
local RequestShopList = nil

-- ==================== 私有函数 ====================

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

local function InitializeUI()
	if shopUI and shopFrame then
		return true
	end

	local playerGui = player:WaitForChild("PlayerGui")
	shopUI = playerGui:WaitForChild("ArmyStore", 10)
	if not shopUI then
		warn("[ShopTrigger] 找不到 ArmyStore ScreenGui")
		return false
	end

	shopFrame = shopUI:WaitForChild("StoreBg", 5)
	if not shopFrame then
		warn("[ShopTrigger] 找不到 StoreBg Frame")
		return false
	end

	return true
end

local function InitializeEvents()
	if RequestShopList then
		return true
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		warn("[ShopTrigger] Events 文件夹未找到")
		return false
	end

	local shopEvents = events:FindFirstChild("ShopEvents")
	if not shopEvents then
		warn("[ShopTrigger] ShopEvents 文件夹未找到")
		return false
	end

	RequestShopList = shopEvents:FindFirstChild("RequestShopList")
	if not RequestShopList then
		warn("[ShopTrigger] 找不到 RequestShopList 事件")
		return false
	end

	return true
end

local function IsLocalCharacterPart(part)
	local character = player.Character
	return character and part and part:IsDescendantOf(character)
end

local function IsCharacterTouchingPart(part)
	local character = player.Character
	if not character or not part or not part.Parent then
		return false
	end

	local ok, touching = pcall(function()
		return part:GetTouchingParts()
	end)
	if not ok or type(touching) ~= "table" then
		return false
	end

	for _, hit in ipairs(touching) do
		if hit and hit:IsDescendantOf(character) then
			return true
		end
	end

	return false
end

local function FindPrisonerTouchPart()
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local home = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME or "Home")
	if not home then
		return nil
	end

	local playerHome = home:FindFirstChild((GameConfig.HOME_PREFIX or "PlayerHome") .. homeSlot)
	if not playerHome then
		return nil
	end

	local touchPart = playerHome:FindFirstChild("PrisonerTouch")
	if touchPart and touchPart:IsA("BasePart") then
		return touchPart
	end
	return nil
end

local function OpenShop()
	if isShopOpen or blockReopenUntilLeave then
		return
	end

	if not InitializeUI() or not InitializeEvents() then
		return
	end

	if _G.ShopDisplay and _G.ShopDisplay.PlayOpen then
		_G.ShopDisplay.PlayOpen()
	else
		shopFrame.Visible = true
	end

	RequestBackpackHide()
	isShopOpen = true
	isNearShop = true

	RequestShopList:FireServer()
	print("[ShopTrigger] 触碰 PrisonerTouch，已请求商店列表")

	-- 兜底重试机制，防止竞态丢消息
	task.delay(0.5, function()
		if not shopFrame or not shopFrame.Visible then
			return
		end

		local scrollingFrame = shopFrame:FindFirstChild("ItemContainer") or shopFrame:FindFirstChild("ScrollingFrame")
		if not scrollingFrame then
			return
		end

		local hasCards = false
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child:IsA("Frame") and string.find(child.Name, "ItemCard_") then
				hasCards = true
				break
			end
		end

		if not hasCards then
			print("[ShopTrigger] 未检测到商品卡片，重试请求商店列表")
			RequestShopList:FireServer()
		end
	end)
end

local function CloseShop(manual)
	if not isShopOpen then
		return
	end

	if not InitializeUI() then
		return
	end

	if _G.ShopDisplay and _G.ShopDisplay.PlayClose then
		_G.ShopDisplay.PlayClose()
	else
		shopFrame.Visible = false
	end

	ReleaseBackpackHide()
	isShopOpen = false

	if manual then
		blockReopenUntilLeave = true
		print("[ShopTrigger] 手动关闭商店，离开 PrisonerTouch 前不再自动打开")
	else
		print("[ShopTrigger] 离开 PrisonerTouch，自动关闭商店")
	end
end

local function ClearPrisonerTouchConnections()
	if prisonerTouchConn then
		prisonerTouchConn:Disconnect()
		prisonerTouchConn = nil
	end

	if prisonerTouchEndedConn then
		prisonerTouchEndedConn:Disconnect()
		prisonerTouchEndedConn = nil
	end

	prisonerTouchingParts = {}
	prisonerTouchActive = false
end

local function OnLeavePrisonerTouch()
	prisonerTouchActive = false
	isNearShop = false
	blockReopenUntilLeave = false
	CloseShop(false)
end

local function BindPrisonerTouch(part)
	if prisonerTouchPart == part then
		return
	end

	ClearPrisonerTouchConnections()
	prisonerTouchPart = part
	if not part then
		return
	end

	prisonerTouchConn = part.Touched:Connect(function(hit)
		if not IsLocalCharacterPart(hit) then
			return
		end

		prisonerTouchingParts[hit] = true
		if prisonerTouchActive then
			return
		end

		prisonerTouchActive = true
		if not blockReopenUntilLeave then
			OpenShop()
		end
	end)

	prisonerTouchEndedConn = part.TouchEnded:Connect(function(hit)
		if not prisonerTouchingParts[hit] then
			return
		end

		prisonerTouchingParts[hit] = nil
		if next(prisonerTouchingParts) == nil then
			OnLeavePrisonerTouch()
		end
	end)
end

local function ResolvePrisonerTouch(force)
	local now = tick()
	if not force and (now - lastResolveTime) < TOUCH_RESOLVE_INTERVAL then
		return
	end
	lastResolveTime = now

	local part = FindPrisonerTouchPart()
	if part ~= prisonerTouchPart then
		BindPrisonerTouch(part)
	end
end

local function UpdatePrisonerTouchState()
	if not prisonerTouchPart or not prisonerTouchPart.Parent then
		if prisonerTouchActive or isShopOpen then
			OnLeavePrisonerTouch()
		end
		return
	end

	local touching = IsCharacterTouchingPart(prisonerTouchPart)

	if touching and not prisonerTouchActive then
		prisonerTouchActive = true
		if not blockReopenUntilLeave then
			OpenShop()
		end
	elseif (not touching) and prisonerTouchActive and next(prisonerTouchingParts) == nil then
		OnLeavePrisonerTouch()
	elseif (not touching) and (not prisonerTouchActive) and next(prisonerTouchingParts) == nil then
		-- 防止手动关闭后永久锁死，离开触碰面后恢复可自动开启状态
		blockReopenUntilLeave = false
	end
end

local function BindCloseButton()
	if closeButtonConnection then
		closeButtonConnection:Disconnect()
		closeButtonConnection = nil
	end

	if not shopFrame then
		return
	end

	local closeButton = shopFrame:FindFirstChild("CloseButton")
	if not closeButton then
		warn("[ShopTrigger] 找不到 CloseButton")
		return
	end

	closeButtonConnection = closeButton.MouseButton1Click:Connect(function()
		CloseShop(true)
	end)

	print("[ShopTrigger] 关闭按钮已绑定")
end

-- ==================== 公共接口 ====================

function ShopTrigger.Initialize()
	print("[ShopTrigger] 初始化触碰商店触发器...")

	if not InitializeUI() then
		warn("[ShopTrigger] UI 初始化失败")
		return
	end

	if not InitializeEvents() then
		warn("[ShopTrigger] 事件初始化失败")
		return
	end

	BindCloseButton()
	ResolvePrisonerTouch(true)

	if checkConnection then
		checkConnection:Disconnect()
	end

	checkConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if not ShopTrigger._lastCheckTime or (now - ShopTrigger._lastCheckTime) >= GameConfig.Shop.CheckInterval then
			ShopTrigger._lastCheckTime = now
			ResolvePrisonerTouch(false)
			UpdatePrisonerTouchState()
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait(0.3)
		prisonerTouchingParts = {}
		prisonerTouchActive = false
		isNearShop = false
		blockReopenUntilLeave = false
		CloseShop(false)
		ResolvePrisonerTouch(true)
	end)

	player:GetAttributeChangedSignal("HomeSlot"):Connect(function()
		prisonerTouchingParts = {}
		prisonerTouchActive = false
		isNearShop = false
		blockReopenUntilLeave = false
		CloseShop(false)
		ResolvePrisonerTouch(true)
	end)

	print("[ShopTrigger] ✅ 触碰商店触发器已就绪")
end

function ShopTrigger.Cleanup()
	if checkConnection then
		checkConnection:Disconnect()
		checkConnection = nil
	end

	if closeButtonConnection then
		closeButtonConnection:Disconnect()
		closeButtonConnection = nil
	end

	ClearPrisonerTouchConnections()
	print("[ShopTrigger] 已清理")
end

-- ==================== 自动初始化 ====================
ShopTrigger.Initialize()

return ShopTrigger
