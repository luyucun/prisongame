--[[
=====================================================
脚本名称: SkillShopDisplay
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayerScripts/UI/SkillShopDisplay.lua
版本: V3.1
=====================================================

功能描述:
- 管理技能商店UI显示
- 动态生成技能商品卡片
- 处理购买按钮点击和确认流程
- 显示库存和刷新倒计时
- 与SkillShopSystem服务端交互

=====================================================
]]

local SkillShopDisplay = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))
local RobuxPriceHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RobuxPriceHelper"))

-- 本地玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 调试和日志
local DEBUG_MODE = false
local LOG_PREFIX = "[SkillShopDisplay]"

-- 状态变量
local shopData = {}              -- 技能商店商品数据
local shopUI = nil               -- 商店UI引用
local shopFrame = nil            -- 商店主框架
local itemContainer = nil        -- 商品容器
local closeButton = nil          -- 关闭按钮
local titleLabel = nil           -- 标题标签

-- 购买状态管理
local isPurchasing = false
local purchaseConnections = {}
local currentSelectedItem = nil
local globalBuyConnections = {}

-- UI组件引用
local ButtonEffectHelper = nil
local CoinAnimationHelper = nil

-- 事件引用
local RequestSkillShopList = nil
local SkillShopListEvent = nil
local PurchaseSkill = nil
local PurchaseSkillRobux = nil       -- Robux购买事件
local SkillPurchaseResult = nil
local SkillStockUpdate = nil
local SkillRefreshTimeUpdate = nil

-- 库存系统变量
local currentStockData = {}
local refreshTimeRemaining = 0
local lastSyncTick = 0
local titleUpdateConn = nil
local currentShopName = "技能商店"

-- 弹框动画配置（仅StoreBg）
local POPUP_OPEN_START_SCALE = 0.86
local POPUP_OPEN_OVERSHOOT_SCALE = 1.10
local POPUP_OPEN_DURATION_A = 0.18
local POPUP_OPEN_DURATION_B = 0.10
local POPUP_CLOSE_OVERSHOOT_SCALE = 1.12
local POPUP_CLOSE_END_SCALE = 0.78
local POPUP_CLOSE_DURATION_A = 0.08
local POPUP_CLOSE_DURATION_B = 0.12

local popupScale = nil
local popupOpenTweenA = nil
local popupOpenTweenB = nil
local popupCloseTweenA = nil
local popupCloseTweenB = nil
local popupAnimating = false

-- ==================== 私有函数 ====================

--[[
延迟加载UI助手模块
@return boolean - 是否成功加载
]]
local function LoadUIHelpers()
	if ButtonEffectHelper and CoinAnimationHelper then
		return true
	end

	if not ButtonEffectHelper then
		local success, result = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("Utils"):WaitForChild("ButtonEffectHelper"))
		end)
		if success then
			ButtonEffectHelper = result
		end
	end

	if not CoinAnimationHelper then
		local success, result = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("Utils"):WaitForChild("CoinAnimationHelper"))
		end)
		if success then
			CoinAnimationHelper = result
		end
	end

	return ButtonEffectHelper ~= nil and CoinAnimationHelper ~= nil
end

local function ShowSystemError(text)
	local tipsSystem = _G.TipsSystem
	if tipsSystem and tipsSystem.ShowError then
		tipsSystem.ShowError(text)
		return true
	end
	return false
end

local function PlayPurchaseErrorSound()
	local soundController = _G.SoundController
	if soundController and soundController.PlaySFX then
		soundController.PlaySFX("Error")
	end
end

local function IsOutOfStockMessage(message)
	return message and string.find(message, "库存不足")
end

local function IsNotEnoughCashMessage(message)
	return message and string.find(message, "金币不足")
end

local function UpdateRobuxBuyPriceLabel(priceLabel, devProductId)
	if not priceLabel then
		return
	end
	RobuxPriceHelper.UpdateProductLabel(priceLabel, devProductId, "suffix")
end

local function PrimeRobuxPricesFromShopData()
	if type(shopData) ~= "table" then
		return
	end
	local seen = {}
	for _, itemData in ipairs(shopData) do
		local devProductId = tonumber(itemData and itemData.DevProductId) or 0
		if devProductId > 0 and not seen[devProductId] then
			seen[devProductId] = true
			RobuxPriceHelper.GetProductPrice(devProductId)
		end
	end
end

local function MergeStockData(stockData)
	if type(stockData) ~= "table" then
		return
	end

	for key, value in pairs(stockData) do
		if type(value) == "number" then
			currentStockData[tostring(key)] = value
		end
	end
end

--[[
初始化UI引用
@return boolean - 是否成功
]]
local function InitializeUI()
	if shopUI and shopFrame then
		return true
	end

	-- 等待SkillStore ScreenGui
	shopUI = playerGui:WaitForChild("SkillStore", 5)
	if not shopUI then
		warn(LOG_PREFIX, "找不到 SkillStore ScreenGui")
		return false
	end

	shopFrame = shopUI:WaitForChild("StoreBg", 2)
	if not shopFrame then
		warn(LOG_PREFIX, "找不到 StoreBg Frame")
		return false
	end

	-- 获取子组件引用
	itemContainer = shopFrame:FindFirstChild("ItemContainer") or shopFrame:FindFirstChild("ScrollingFrame")
	closeButton = shopFrame:FindFirstChild("CloseButton")
	titleLabel = shopFrame:FindFirstChild("TitleLabel") or shopFrame:FindFirstChild("Title")

	if not itemContainer then
		warn(LOG_PREFIX, "找不到 ItemContainer 或 ScrollingFrame")
		return false
	end

	if DEBUG_MODE then
		print(LOG_PREFIX, "UI引用初始化成功")
	end

	return true
end

local function EnsurePopupScale()
	if not shopFrame then
		return nil
	end

	if not popupScale or popupScale.Parent ~= shopFrame then
		popupScale = shopFrame:FindFirstChild("PopupScale")
		if not popupScale then
			popupScale = Instance.new("UIScale")
			popupScale.Name = "PopupScale"
			popupScale.Scale = 1
			popupScale.Parent = shopFrame
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

--[[
初始化事件引用
@return boolean - 是否成功
]]
local function InitializeEvents()
	if RequestSkillShopList and SkillShopListEvent and PurchaseSkill and SkillPurchaseResult then
		return true
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		warn(LOG_PREFIX, "Events文件夹未找到")
		return false
	end

	local skillShopEvents = events:FindFirstChild("SkillShopEvents")
	if not skillShopEvents then
		warn(LOG_PREFIX, "SkillShopEvents文件夹未找到")
		return false
	end

	RequestSkillShopList = skillShopEvents:FindFirstChild("RequestSkillShopList")
	SkillShopListEvent = skillShopEvents:FindFirstChild("SkillShopList")
	PurchaseSkill = skillShopEvents:FindFirstChild("PurchaseSkill")
	PurchaseSkillRobux = skillShopEvents:FindFirstChild("PurchaseSkillRobux")  -- Robux购买事件
	SkillPurchaseResult = skillShopEvents:FindFirstChild("SkillPurchaseResult")
	SkillStockUpdate = skillShopEvents:FindFirstChild("SkillStockUpdate")
	SkillRefreshTimeUpdate = skillShopEvents:FindFirstChild("SkillRefreshTimeUpdate")

	if not (RequestSkillShopList and SkillShopListEvent and PurchaseSkill and SkillPurchaseResult) then
		warn(LOG_PREFIX, "技能商店事件不完整")
		return false
	end

	return true
end

function SkillShopDisplay.PlayOpen()
	if not InitializeUI() then
		return
	end

	local scale = EnsurePopupScale()
	if not scale then
		return
	end

	if shopFrame.Visible and not popupAnimating then
		return
	end

	CancelPopupTweens()
	popupAnimating = true

	shopFrame.Visible = true
	scale.Scale = POPUP_OPEN_START_SCALE

	popupOpenTweenA = TweenService:Create(scale,
		TweenInfo.new(POPUP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_OPEN_OVERSHOOT_SCALE}
	)
	popupOpenTweenB = TweenService:Create(scale,
		TweenInfo.new(POPUP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1}
	)

	local connA
	connA = popupOpenTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			popupOpenTweenB:Play()
		end
	end)

	local connB
	connB = popupOpenTweenB.Completed:Connect(function()
		connB:Disconnect()
		popupAnimating = false
		scale.Scale = 1
	end)

	popupOpenTweenA:Play()
end

function SkillShopDisplay.PlayClose()
	if not InitializeUI() then
		return
	end

	local scale = EnsurePopupScale()
	if not scale then
		return
	end

	if not shopFrame.Visible and not popupAnimating then
		return
	end

	CancelPopupTweens()
	popupAnimating = true

	popupCloseTweenA = TweenService:Create(scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_CLOSE_OVERSHOOT_SCALE}
	)
	popupCloseTweenB = TweenService:Create(scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = POPUP_CLOSE_END_SCALE}
	)

	local connA
	connA = popupCloseTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			popupCloseTweenB:Play()
		end
	end)

	local connB
	connB = popupCloseTweenB.Completed:Connect(function()
		connB:Disconnect()
		shopFrame.Visible = false
		scale.Scale = 1
		popupAnimating = false
	end)

	popupCloseTweenA:Play()
end

--[[
格式化金币显示
@param amount number - 金币数量
@return string - 格式化文本
]]
local function FormatCoins(amount)
	local formatted = tostring(math.floor(amount))
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if k == 0 then break end
	end
	return "$" .. formatted
end

--[[
获取技能类型颜色
@param skillType string - 技能类型
@return Color3 - 对应颜色
]]
local function GetSkillTypeColor(skillType)
	local colors = {
		["Damage"] = Color3.fromRGB(255, 80, 80),      -- 红色
		["Healing"] = Color3.fromRGB(80, 255, 80),     -- 绿色
		["Buff"] = Color3.fromRGB(80, 180, 255),       -- 蓝色
	}
	return colors[skillType] or Color3.fromRGB(200, 200, 200)
end

--[[
创建技能商品卡片UI
@param itemData table - 商品数据
@param index number - 索引位置
@return Frame - 创建的卡片Frame
]]
local function CreateSkillItemCard(itemData, index)
	-- 查找ItemCardTemplate模板
	local template = itemContainer:FindFirstChild("ItemCardTemplate")
	if not template then
		warn(LOG_PREFIX, "找不到 ItemCardTemplate 模板")
		return nil
	end

	-- 克隆模板
	local cardFrame = template:Clone()
	cardFrame.Name = "SkillCard_" .. itemData.SkillId
	cardFrame.Visible = true
	cardFrame.LayoutOrder = itemData.Sort or index

	-- 获取技能数据
	local skillId = itemData.SkillId
	local skillData = SkillConfig.GetSkillById(skillId)

	-- 填充卡片图标
	local iconBg = cardFrame:FindFirstChild("IconBg")
	if iconBg then
		local icon = iconBg:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = itemData.Icon or (skillData and skillData.Icon) or "rbxassetid://0"
		end
	end

	-- 设置技能名称
	local name = cardFrame:FindFirstChild("Name")
	if name and name:IsA("TextLabel") then
		name.Text = itemData.Name or "Unknown"
	end

	-- 设置技能类型
	local typeLabel = cardFrame:FindFirstChild("Type") or cardFrame:FindFirstChild("SkillType")
	if typeLabel and typeLabel:IsA("TextLabel") then
		typeLabel.Text = itemData.SkillType or "Damage"
		typeLabel.TextColor3 = GetSkillTypeColor(itemData.SkillType)
	end

	-- 设置效果类型
	local effectLabel = cardFrame:FindFirstChild("Effect") or cardFrame:FindFirstChild("EffectType")
	if effectLabel and effectLabel:IsA("TextLabel") then
		effectLabel.Text = itemData.EffectType or "Instant"
	end

	-- 设置范围
	local rangeLabel = cardFrame:FindFirstChild("Range")
	if rangeLabel and rangeLabel:IsA("TextLabel") then
		rangeLabel.Text = tostring(itemData.Range or 0) .. " studs"
	end

	-- 设置描述
	local descLabel = cardFrame:FindFirstChild("Description")
	if descLabel and descLabel:IsA("TextLabel") then
		descLabel.Text = itemData.Description or ""
	end

	-- 设置库存数量
	local number = cardFrame:FindFirstChild("Number")
	if number and number:IsA("TextLabel") then
		if itemData.Stock and itemData.Stock <= 0 then
			number.Text = "Sold out"
			number.TextColor3 = Color3.fromRGB(255, 50, 50)
		else
			number.Text = "x" .. tostring(itemData.Stock or 999)
			number.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end

	-- 设置价格
	local price = cardFrame:FindFirstChild("Price")
	if price and price:IsA("TextLabel") then
		local priceValue = tonumber(itemData.Price) or 0
		price.Text = FormatCoins(priceValue)
	end

	-- 存储商品数据到卡片
	cardFrame:SetAttribute("SkillId", itemData.SkillId)
	cardFrame:SetAttribute("Price", itemData.Price)
	cardFrame:SetAttribute("Stock", itemData.Stock or 999)

	if DEBUG_MODE then
		print(LOG_PREFIX, "创建技能商品卡片:", itemData.SkillId, itemData.Name)
	end

	return cardFrame
end

--[[
处理购买按钮点击
@param itemData table - 商品数据
]]
local function OnPurchaseButtonClick(itemData)
	if isPurchasing then
		return
	end

	if not itemData or not itemData.SkillId then
		return
	end

	if not InitializeEvents() then
		warn(LOG_PREFIX, "事件未初始化，无法购买")
		return
	end

	if itemData.Stock and itemData.Stock <= 0 then
		ShowSystemError("Out of stock")
		PlayPurchaseErrorSound()
		return
	end

	if DEBUG_MODE then
		print(LOG_PREFIX, "尝试购买技能:", itemData.SkillId, "价格:", itemData.Price)
	end

	isPurchasing = true
	PurchaseSkill:FireServer(itemData.SkillId)

	task.delay(0.5, function()
		isPurchasing = false
	end)
end

--[[
全局购买按钮点击处理
]]
local function OnGlobalBuyButtonClick()
	if currentSelectedItem then
		OnPurchaseButtonClick(currentSelectedItem)
	end
end

--[[
设置卡片点击展开逻辑
@param cardFrame Frame - 卡片Frame
@param itemData table - 商品数据
]]
local function SetupCardClickLogic(cardFrame, itemData)
	local buyButtonFrame = itemContainer:FindFirstChild("BuyButtonFrame")
	if not buyButtonFrame then
		warn(LOG_PREFIX, "找不到 BuyButtonFrame")
		return
	end

	local goldBuy = buyButtonFrame:FindFirstChild("GoldBuy")
	local robuxBuy = buyButtonFrame:FindFirstChild("RobuxBuy")

	-- 清理旧的事件连接
	local cardId = tostring(itemData.SkillId)
	if purchaseConnections[cardId] then
		for _, connection in ipairs(purchaseConnections[cardId]) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
	end
	purchaseConnections[cardId] = {}

	-- 创建点击检测按钮
	local clickButton = cardFrame:FindFirstChild("ClickButton")
	if not clickButton then
		clickButton = Instance.new("TextButton")
		clickButton.Name = "ClickButton"
		clickButton.Size = UDim2.new(1, 0, 1, 0)
		clickButton.Position = UDim2.new(0, 0, 0, 0)
		clickButton.BackgroundTransparency = 1
		clickButton.Text = ""
		clickButton.ZIndex = 5
		clickButton.Parent = cardFrame
	end

	-- 点击卡片展开/收起
	local clickConnection = clickButton.MouseButton1Click:Connect(function()
		if buyButtonFrame.Visible and buyButtonFrame:GetAttribute("CurrentCardId") == itemData.SkillId then
			-- 收起
			buyButtonFrame.Visible = false
			buyButtonFrame:SetAttribute("CurrentCardId", nil)
			currentSelectedItem = nil
		else
			-- 展开
			local cardIndex = cardFrame.LayoutOrder
			buyButtonFrame.LayoutOrder = cardIndex + 1
			currentSelectedItem = itemData

			-- 更新按钮价格
			if goldBuy then
				local goldPrice = goldBuy:FindFirstChild("Price")
				if goldPrice and goldPrice:IsA("TextLabel") then
					goldPrice.Text = FormatCoins(itemData.Price or 0)
				end
			end

			if robuxBuy then
				local devProductId = tonumber(itemData.DevProductId) or 0
				local robuxPrice = robuxBuy:FindFirstChild("Price")
				if robuxPrice and (robuxPrice:IsA("TextLabel") or robuxPrice:IsA("TextButton")) then
					UpdateRobuxBuyPriceLabel(robuxPrice, devProductId)
				end
				robuxBuy.Visible = devProductId > 0
			end

			buyButtonFrame.Visible = true
			buyButtonFrame:SetAttribute("CurrentCardId", itemData.SkillId)
		end
	end)
	table.insert(purchaseConnections[cardId], clickConnection)

	if LoadUIHelpers() and ButtonEffectHelper then
		ButtonEffectHelper.AddClickEffect(clickButton)
	end
end

--[[
初始化全局购买按钮事件
]]
local function InitializeGlobalBuyButtons()
	if not itemContainer then
		return false
	end

	local buyButtonFrame = itemContainer:FindFirstChild("BuyButtonFrame")
	if not buyButtonFrame then
		warn(LOG_PREFIX, "找不到 BuyButtonFrame")
		return false
	end

	local goldBuy = buyButtonFrame:FindFirstChild("GoldBuy")
	local robuxBuy = buyButtonFrame:FindFirstChild("RobuxBuy")

	-- 清理旧的全局连接
	for _, connection in ipairs(globalBuyConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	globalBuyConnections = {}

	if goldBuy then
		local goldConnection = goldBuy.MouseButton1Click:Connect(OnGlobalBuyButtonClick)
		table.insert(globalBuyConnections, goldConnection)

		if LoadUIHelpers() and ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(goldBuy)
		end
	end

	if robuxBuy then
		local robuxConnection = robuxBuy.MouseButton1Click:Connect(function()
			-- Robux购买逻辑
			if currentSelectedItem then
				if not PurchaseSkillRobux then
					warn(LOG_PREFIX, "PurchaseSkillRobux事件未找到，无法进行Robux购买")
					return
				end

				local devProductId = tonumber(currentSelectedItem.DevProductId) or 0
				-- 检查是否有DevProductId
				if devProductId <= 0 then
					warn(LOG_PREFIX, "该技能不支持Robux购买:", currentSelectedItem.SkillId)
					return
				end

				-- 防重复购买检查
				if isPurchasing then
					if DEBUG_MODE then
						print(LOG_PREFIX, "Robux购买处理中，请稍候")
					end
					return
				end

				if DEBUG_MODE then
					print(LOG_PREFIX, "尝试Robux购买技能:", currentSelectedItem.SkillId, "DevProductId:", devProductId)
				end

				-- 设置购买状态
				isPurchasing = true

				-- 发送Robux购买请求到服务端
				PurchaseSkillRobux:FireServer(currentSelectedItem.SkillId)

				-- 0.5秒后重置购买状态
				task.delay(0.5, function()
					isPurchasing = false
				end)
			else
				warn(LOG_PREFIX, "没有选中的技能，无法进行Robux购买")
			end
		end)
		table.insert(globalBuyConnections, robuxConnection)

		if LoadUIHelpers() and ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(robuxBuy)
		end
	end

	return true
end

--[[
更新商店商品列表显示
]]
local function UpdateShopDisplay()
	if not InitializeUI() then
		warn(LOG_PREFIX, "UI未初始化，无法更新显示")
		return
	end

	-- 清空现有商品（保留模板和BuyButtonFrame）
	for _, child in ipairs(itemContainer:GetChildren()) do
		if child:IsA("Frame") and string.find(child.Name, "SkillCard_") then
			child:Destroy()
		end
	end

	LoadUIHelpers()
	InitializeGlobalBuyButtons()

	-- 创建商品卡片
	for index, itemData in ipairs(shopData) do
		local cardFrame = CreateSkillItemCard(itemData, index)
		if cardFrame then
			cardFrame.Parent = itemContainer
			SetupCardClickLogic(cardFrame, itemData)
		end
	end

	if DEBUG_MODE then
		print(LOG_PREFIX, "技能商店显示已更新，商品数量:", #shopData)
	end
end

--[[
处理商店列表事件
@param shopList table - 商店商品列表
]]
local function OnShopListReceived(shopList)
	if DEBUG_MODE then
		print(LOG_PREFIX, "收到技能商店列表，商品数量:", shopList and #shopList or 0)
	end

	if not shopList or type(shopList) ~= "table" then
		warn(LOG_PREFIX, "技能商店列表数据无效")
		return
	end

	currentStockData = {}
	for _, itemData in ipairs(shopList) do
		if itemData and itemData.SkillId then
			local stockKey = tostring(itemData.SkillId)
			local stockValue = tonumber(itemData.Stock) or 0
			currentStockData[stockKey] = stockValue
			itemData.Stock = stockValue
		end
	end

	shopData = shopList
	PrimeRobuxPricesFromShopData()
	UpdateShopDisplay()
end

--[[
处理购买结果事件
@param success boolean - 是否购买成功
@param message string - 结果消息
@param skillId number - 技能ID
@param newCoinAmount number - 新的金币数量
]]
local function OnPurchaseResultReceived(success, message, skillId, newCoinAmount)
	isPurchasing = false

	if DEBUG_MODE then
		print(LOG_PREFIX, "购买结果:", success, message, skillId, newCoinAmount)
	end

	if success then
		-- 购买成功
		if LoadUIHelpers() and CoinAnimationHelper then
			local actualPrice = 0
			for _, itemData in ipairs(shopData) do
				if itemData.SkillId == skillId then
					actualPrice = itemData.Price
					break
				end
			end

			local startPos = UDim2.new(0.5, 0, 0.5, 0)
			CoinAnimationHelper.CreateCoinChangeEffect(
				playerGui,
				-actualPrice,
				startPos,
				{
					Duration = 1.2,
					TextColor = Color3.fromRGB(255, 100, 100),
				}
			)
		end

		-- 显示成功消息
		local successNotification = Instance.new("TextLabel")
		successNotification.Name = "SuccessNotification"
		successNotification.Size = UDim2.new(0, 300, 0, 60)
		successNotification.Position = UDim2.new(0.5, -150, 0.1, 0)
		successNotification.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
		successNotification.BorderSizePixel = 0
		successNotification.Text = "技能购买成功！"
		successNotification.TextColor3 = Color3.fromRGB(255, 255, 255)
		successNotification.TextScaled = true
		successNotification.Font = Enum.Font.GothamBold
		successNotification.Parent = playerGui

		local notificationCorner = Instance.new("UICorner")
		notificationCorner.CornerRadius = UDim.new(0, 8)
		notificationCorner.Parent = successNotification

		task.delay(2, function()
			if successNotification and successNotification.Parent then
				local fadeTween = TweenService:Create(successNotification,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{BackgroundTransparency = 1, TextTransparency = 1}
				)
				fadeTween:Play()
				fadeTween.Completed:Connect(function()
					successNotification:Destroy()
				end)
			end
		end)
	else
		-- 购买失败
		if DEBUG_MODE then
			warn(LOG_PREFIX, "购买失败:", message)
		end

		if IsOutOfStockMessage(message) then
			if ShowSystemError("Out of stock") then
				return
			end
		elseif IsNotEnoughCashMessage(message) then
			if ShowSystemError("Not enough cash") then
				return
			end
		end

		local failNotification = Instance.new("TextLabel")
		failNotification.Name = "FailNotification"
		failNotification.Size = UDim2.new(0, 300, 0, 60)
		failNotification.Position = UDim2.new(0.5, -150, 0.1, 0)
		failNotification.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
		failNotification.BorderSizePixel = 0
		failNotification.Text = message or "购买失败"
		failNotification.TextColor3 = Color3.fromRGB(255, 255, 255)
		failNotification.TextScaled = true
		failNotification.Font = Enum.Font.GothamBold
		failNotification.Parent = playerGui

		local notificationCorner = Instance.new("UICorner")
		notificationCorner.CornerRadius = UDim.new(0, 8)
		notificationCorner.Parent = failNotification

		task.delay(3, function()
			if failNotification and failNotification.Parent then
				local fadeTween = TweenService:Create(failNotification,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{BackgroundTransparency = 1, TextTransparency = 1}
				)
				fadeTween:Play()
				fadeTween.Completed:Connect(function()
					failNotification:Destroy()
				end)
			end
		end)
	end
end

-- ==================== 库存系统处理函数 ====================

--[[
处理库存更新事件
@param shopId string - 商店ID
@param stockData table - 库存数据
]]
local function OnSkillStockUpdate(shopId, stockData)
	if DEBUG_MODE then
		print(LOG_PREFIX, "收到技能库存更新:", shopId)
	end

	MergeStockData(stockData)

	for _, itemData in ipairs(shopData) do
		if itemData and itemData.SkillId then
			local stockKey = tostring(itemData.SkillId)
			local stockValue = currentStockData[stockKey]
			if stockValue ~= nil then
				itemData.Stock = stockValue
			end
		end
	end

	-- 更新所有商品卡片的库存显示
	if itemContainer then
		for _, card in ipairs(itemContainer:GetChildren()) do
			if card:IsA("Frame") and string.find(card.Name, "SkillCard_") then
				local skillIdStr = string.gsub(card.Name, "SkillCard_", "")
				local stock = currentStockData[skillIdStr] or 0

				local numberLabel = card:FindFirstChild("Number")
				if numberLabel and numberLabel:IsA("TextLabel") then
					if stock <= 0 then
						numberLabel.Text = "Sold out"
						numberLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
					else
						numberLabel.Text = "x" .. stock
						numberLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					end
				end

				card:SetAttribute("Stock", stock)
			end
		end
	end
end

--[[
更新标题文本
]]
local function UpdateTitleText()
	if not titleLabel then return end
	local minutes = math.floor(math.max(0, refreshTimeRemaining) / 60)
	local seconds = math.max(0, refreshTimeRemaining) % 60
	titleLabel.Text = string.format("Stock refreshes in %02d:%02d", minutes, seconds)
end

--[[
处理刷新倒计时更新事件
@param remainingTime number - 剩余时间（秒）
]]
local function OnSkillRefreshTimeUpdate(remainingTime)
	refreshTimeRemaining = remainingTime or 0
	lastSyncTick = tick()
	UpdateTitleText()
end

-- ==================== 公共接口 ====================

--[[
初始化技能商店显示系统
]]
function SkillShopDisplay.Initialize()
	if DEBUG_MODE then
		print(LOG_PREFIX, "初始化技能商店显示系统...")
	end

	if not InitializeUI() then
		warn(LOG_PREFIX, "UI初始化失败")
		return false
	end

	if not InitializeEvents() then
		warn(LOG_PREFIX, "事件初始化失败")
		return false
	end

	-- 连接事件监听
	SkillShopListEvent.OnClientEvent:Connect(OnShopListReceived)
	SkillPurchaseResult.OnClientEvent:Connect(OnPurchaseResultReceived)

	if SkillStockUpdate then
		SkillStockUpdate.OnClientEvent:Connect(OnSkillStockUpdate)
	end
	if SkillRefreshTimeUpdate then
		SkillRefreshTimeUpdate.OnClientEvent:Connect(OnSkillRefreshTimeUpdate)
	end

	-- 设置关闭按钮
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			SkillShopDisplay.PlayClose()
		end)

		if LoadUIHelpers() and ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(closeButton)
		end
	end

	-- 监听shopFrame可见性变化
	if shopFrame then
		shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if shopFrame.Visible then
				if titleUpdateConn then
					titleUpdateConn:Disconnect()
					titleUpdateConn = nil
				end

				titleUpdateConn = RunService.Heartbeat:Connect(function()
					if lastSyncTick > 0 then
						local now = tick()
						local passed = now - lastSyncTick
						if passed >= 1.0 then
							refreshTimeRemaining = math.max(0, refreshTimeRemaining - 1)
							lastSyncTick = now
							UpdateTitleText()
						end
					end
				end)

				UpdateTitleText()
			else
				if titleUpdateConn then
					titleUpdateConn:Disconnect()
					titleUpdateConn = nil
				end
			end
		end)
	end

	if DEBUG_MODE then
		print(LOG_PREFIX, "技能商店显示系统初始化完成")
	end

	return true
end

--[[
请求技能商店列表
]]
function SkillShopDisplay.RequestShopList()
	if not InitializeEvents() then
		warn(LOG_PREFIX, "事件未初始化，无法请求商店列表")
		return
	end

	RequestSkillShopList:FireServer()

	if DEBUG_MODE then
		print(LOG_PREFIX, "已请求技能商店列表")
	end
end

--[[
获取当前商店数据
@return table - 商店数据
]]
function SkillShopDisplay.GetShopData()
	return shopData
end

--[[
清理商店显示
]]
function SkillShopDisplay.Cleanup()
	shopData = {}
	currentStockData = {}
	currentSelectedItem = nil

	for _, connection in ipairs(globalBuyConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	globalBuyConnections = {}

	for cardId, connections in pairs(purchaseConnections) do
		for _, connection in ipairs(connections) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
	end
	purchaseConnections = {}

	if itemContainer then
		for _, child in ipairs(itemContainer:GetChildren()) do
			if child:IsA("Frame") and string.find(child.Name, "SkillCard_") then
				child:Destroy()
			end
		end
	end

	if DEBUG_MODE then
		print(LOG_PREFIX, "技能商店显示已清理")
	end
end

-- ==================== 自动初始化 ====================

_G.SkillShopDisplay = SkillShopDisplay

task.spawn(function()
	local success, result = pcall(SkillShopDisplay.Initialize)
	if not success then
		warn(LOG_PREFIX, "初始化失败:", result)
	end
end)

return SkillShopDisplay
