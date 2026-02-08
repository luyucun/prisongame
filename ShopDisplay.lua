--[[
脚本名称: ShopDisplay
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayerScripts/UI/ShopDisplay
版本: V2.1
职责: 管理商店UI显示、商品列表展示和购买交互
]]

--[[
商店显示控制器
职责:
1. 从服务端获取商店商品列表
2. 动态生成商品卡片UI
3. 处理购买按钮点击和确认流程
4. 显示购买结果和动画反馈
5. 管理商店UI的打开/关闭状态
]]

local ShopDisplay = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")  -- V2.1修复：用于实时更新倒计时
local Lighting = game:GetService("Lighting")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))  -- V2.1修复：用于读取兵种属性
local PowerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PowerConfig"))

-- 引用格式化工具
local FormatHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FormatHelper"))

-- 本地玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 调试和日志
local DEBUG_MODE = false  -- 默认关闭，需要排查时再手动开启
local LOG_PREFIX = "[ShopDisplay]"

-- 状态变量
local shopData = {}              -- 商店商品数据
local shopUI = nil               -- 商店UI引用
local shopFrame = nil            -- 商店主框架
local itemContainer = nil        -- 商品容器
local closeButton = nil          -- 关闭按钮
local titleLabel = nil           -- 标题标签
local coinDisplay = nil          -- 金币显示
local shopBg = nil               -- 商店背景遮罩
local infoFrame = nil            -- 兵种详情面板
local infoCloseButton = nil      -- 详情关闭按钮
local blurEffect = nil           -- Lighting下的Blur

-- 购买状态管理
local isPurchasing = false       -- V2.1修复：防止重复购买
local purchaseConnections = {}   -- V2.1修复：存储事件连接，避免重复绑定
local currentSelectedItem = nil  -- V2.1修复：当前选中的商品数据
local globalBuyConnections = {}  -- V2.1修复：全局购买按钮连接

-- UI组件引用
local ButtonEffectHelper = nil
local CoinAnimationHelper = nil

-- 事件引用
local RequestShopList = nil
local ShopListEvent = nil
local PurchaseUnit = nil
local PurchaseUnitRobux = nil    -- Robux购买事件
local PurchaseResult = nil
local StockUpdate = nil          -- 库存更新事件 (V2.1库存功能)
local RefreshTimeUpdate = nil    -- 刷新倒计时事件 (V2.1库存功能)

-- 库存系统变量 (V2.1库存功能)
local currentStockData = {}      -- 当前库存数据 {[unitId] = stock}
local refreshTimeRemaining = 0   -- 刷新剩余时间（秒）
local lastSyncTick = 0           -- V2.1修复：最后一次服务器同步时间
local titleUpdateConn = nil      -- V2.1修复：标题更新连接
local currentShopName = "兵种商店"  -- 当前商店名称（默认值）

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

-- 详情弹框动画状态（Information）
local infoPopupScale = nil
local infoOpenTweenA = nil
local infoOpenTweenB = nil
local infoCloseTweenA = nil
local infoCloseTweenB = nil
local infoPopupAnimating = false

-- ==================== 私有函数 ====================

--[[
延迟加载UI助手模块
@return boolean - 是否成功加载
]]
local function LoadUIHelpers()
    if ButtonEffectHelper and CoinAnimationHelper then
        return true -- 已加载
    end

    -- 尝试加载按钮特效助手
    if not ButtonEffectHelper then
        local success, result = pcall(function()
            return require(game:GetService("StarterPlayer").StarterPlayerScripts.Utils.ButtonEffectHelper)
        end)
        if success then
            ButtonEffectHelper = result
        else
            warn(LOG_PREFIX, "按钮特效助手加载失败:", result)
        end
    end

    -- 尝试加载金币动画助手
    if not CoinAnimationHelper then
        local success, result = pcall(function()
            return require(game:GetService("StarterPlayer").StarterPlayerScripts.Utils.CoinAnimationHelper)
        end)
        if success then
            CoinAnimationHelper = result
        else
            warn(LOG_PREFIX, "金币动画助手加载失败:", result)
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

--[[
初始化UI引用
@return boolean - 是否成功
]]
local function InitializeUI()
    if shopUI and shopFrame then
        -- 补充可能尚未缓存的引用
        if not itemContainer then
            itemContainer = shopFrame:FindFirstChild("ItemContainer") or shopFrame:FindFirstChild("ScrollingFrame")
        end
        if not closeButton then
            closeButton = shopFrame:FindFirstChild("CloseButton")
        end
        if not titleLabel then
            titleLabel = shopFrame:FindFirstChild("TitleLabel") or shopFrame:FindFirstChild("Title")
        end
        if not coinDisplay then
            coinDisplay = shopFrame:FindFirstChild("CoinDisplay")
        end
        if not shopBg then
            shopBg = shopUI:FindFirstChild("Bg")
        end
        if not infoFrame then
            infoFrame = shopUI:FindFirstChild("Information")
        end
        if infoFrame and not infoCloseButton then
            infoCloseButton = infoFrame:FindFirstChild("CloseButton")
        end
        if not blurEffect then
            blurEffect = Lighting:FindFirstChild("Blur")
        end
        return true -- 已初始化
    end

    -- V2.1修复：等待ArmyStore从StarterGui复制到PlayerGui（最多等待5秒）
    shopUI = playerGui:WaitForChild("ArmyStore", 5)
    if not shopUI then
        warn(LOG_PREFIX, "找不到 ArmyStore ScreenGui（等待超时）")
        return false
    end

    shopFrame = shopUI:WaitForChild("StoreBg", 2)
    if not shopFrame then
        warn(LOG_PREFIX, "找不到 StoreBg Frame")
        return false
    end

    -- 获取子组件引用（V2.1修复：容错查找ItemContainer或ScrollingFrame）
    itemContainer = shopFrame:FindFirstChild("ItemContainer") or shopFrame:FindFirstChild("ScrollingFrame")
    closeButton = shopFrame:FindFirstChild("CloseButton")
    titleLabel = shopFrame:FindFirstChild("TitleLabel") or shopFrame:FindFirstChild("Title")
    coinDisplay = shopFrame:FindFirstChild("CoinDisplay")
    shopBg = shopUI:FindFirstChild("Bg")
    infoFrame = shopUI:FindFirstChild("Information")
    infoCloseButton = infoFrame and infoFrame:FindFirstChild("CloseButton") or nil
    blurEffect = Lighting:FindFirstChild("Blur")

    if not itemContainer then
        warn(LOG_PREFIX, "找不到 ItemContainer 或 ScrollingFrame")
        return false
    end

    if not shopBg then
        warn(LOG_PREFIX, "找不到 ArmyStore/Bg")
    end

    if not infoFrame then
        warn(LOG_PREFIX, "找不到 ArmyStore/Information")
    else
        infoFrame.Visible = false
    end

    if not blurEffect then
        warn(LOG_PREFIX, "找不到 Lighting/Blur")
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

local function SetShopBackdropVisible(visible)
    if not shopBg and shopUI then
        shopBg = shopUI:FindFirstChild("Bg")
    end
    if not blurEffect then
        blurEffect = Lighting:FindFirstChild("Blur")
    end

    if shopBg then
        shopBg.Visible = visible
    end
    if blurEffect then
        blurEffect.Enabled = visible
    end
end

local function EnsureInfoPopupScale()
    if not infoFrame then
        return nil
    end

    if not infoPopupScale or infoPopupScale.Parent ~= infoFrame then
        infoPopupScale = infoFrame:FindFirstChild("PopupScale")
        if not infoPopupScale then
            infoPopupScale = Instance.new("UIScale")
            infoPopupScale.Name = "PopupScale"
            infoPopupScale.Scale = 1
            infoPopupScale.Parent = infoFrame
        end
    end

    return infoPopupScale
end

local function CancelInfoPopupTweens()
    local tweens = {infoOpenTweenA, infoOpenTweenB, infoCloseTweenA, infoCloseTweenB}
    for _, tween in ipairs(tweens) do
        if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
            tween:Cancel()
        end
    end
end

local function HideInformationImmediate()
    if not infoFrame then
        return
    end

    CancelInfoPopupTweens()
    if infoPopupScale then
        infoPopupScale.Scale = 1
    end
    infoFrame.Visible = false
    infoPopupAnimating = false
end

local function PlayInfoOpen()
    if not InitializeUI() then
        return
    end
    if not infoFrame then
        return
    end

    local scale = EnsureInfoPopupScale()
    if not scale then
        return
    end

    if infoFrame.Visible and not infoPopupAnimating then
        return
    end

    CancelInfoPopupTweens()
    infoPopupAnimating = true

    infoFrame.Visible = true
    scale.Scale = POPUP_OPEN_START_SCALE

    infoOpenTweenA = TweenService:Create(scale,
        TweenInfo.new(POPUP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Scale = POPUP_OPEN_OVERSHOOT_SCALE}
    )
    infoOpenTweenB = TweenService:Create(scale,
        TweenInfo.new(POPUP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Scale = 1}
    )

    local connA
    connA = infoOpenTweenA.Completed:Connect(function(state)
        connA:Disconnect()
        if state == Enum.PlaybackState.Completed then
            infoOpenTweenB:Play()
        end
    end)

    local connB
    connB = infoOpenTweenB.Completed:Connect(function()
        connB:Disconnect()
        infoPopupAnimating = false
        scale.Scale = 1
    end)

    infoOpenTweenA:Play()
end

local function PlayInfoClose()
    if not InitializeUI() then
        return
    end
    if not infoFrame then
        return
    end

    local scale = EnsureInfoPopupScale()
    if not scale then
        return
    end

    if not infoFrame.Visible and not infoPopupAnimating then
        return
    end

    CancelInfoPopupTweens()
    infoPopupAnimating = true

    infoCloseTweenA = TweenService:Create(scale,
        TweenInfo.new(POPUP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Scale = POPUP_CLOSE_OVERSHOOT_SCALE}
    )
    infoCloseTweenB = TweenService:Create(scale,
        TweenInfo.new(POPUP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Scale = POPUP_CLOSE_END_SCALE}
    )

    local connA
    connA = infoCloseTweenA.Completed:Connect(function(state)
        connA:Disconnect()
        if state == Enum.PlaybackState.Completed then
            infoCloseTweenB:Play()
        end
    end)

    local connB
    connB = infoCloseTweenB.Completed:Connect(function()
        connB:Disconnect()
        infoFrame.Visible = false
        scale.Scale = 1
        infoPopupAnimating = false
    end)

    infoCloseTweenA:Play()
end

--[[
初始化事件引用
@return boolean - 是否成功
]]
local function InitializeEvents()
    if RequestShopList and ShopListEvent and PurchaseUnit and PurchaseResult then
        return true -- 已初始化
    end

    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then
        warn(LOG_PREFIX, "Events文件夹未找到")
        return false
    end

    local shopEvents = events:FindFirstChild("ShopEvents")
    if not shopEvents then
        warn(LOG_PREFIX, "ShopEvents文件夹未找到")
        return false
    end

    RequestShopList = shopEvents:FindFirstChild("RequestShopList")
    ShopListEvent = shopEvents:FindFirstChild("ShopList")
    PurchaseUnit = shopEvents:FindFirstChild("PurchaseUnit")
    PurchaseUnitRobux = shopEvents:FindFirstChild("PurchaseUnitRobux")  -- Robux购买事件
    PurchaseResult = shopEvents:FindFirstChild("PurchaseResult")
    StockUpdate = shopEvents:FindFirstChild("StockUpdate")              -- V2.1库存功能
    RefreshTimeUpdate = shopEvents:FindFirstChild("RefreshTimeUpdate")  -- V2.1库存功能

    if not (RequestShopList and ShopListEvent and PurchaseUnit and PurchaseResult) then
        warn(LOG_PREFIX, "商店事件不完整")
        return false
    end

    -- 库存事件是可选的
    if not StockUpdate then
        warn(LOG_PREFIX, "⚠️ StockUpdate事件未找到，库存显示将不可用")
    end
    if not RefreshTimeUpdate then
        warn(LOG_PREFIX, "⚠️ RefreshTimeUpdate事件未找到，刷新倒计时将不可用")
    end

    return true
end

function ShopDisplay.PlayOpen()
    if not InitializeUI() then
        return
    end

    local scale = EnsurePopupScale()
    if not scale then
        return
    end

    SetShopBackdropVisible(true)

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

function ShopDisplay.PlayClose()
    if not InitializeUI() then
        return
    end

    local scale = EnsurePopupScale()
    if not scale then
        return
    end

    if not shopFrame.Visible and not popupAnimating then
        SetShopBackdropVisible(false)
        HideInformationImmediate()
        return
    end

    if infoFrame and infoFrame.Visible then
        PlayInfoClose()
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
        SetShopBackdropVisible(false)
        HideInformationImmediate()
        scale.Scale = 1
        popupAnimating = false
    end)

    popupCloseTweenA:Play()
end

--[[
获取品质对应的颜色
@param quality string - 品质名称
@return Color3 - 对应颜色
]]
local function GetQualityColor(quality)
    local colors = (GameConfig.UI and GameConfig.UI.QualityColors) or {}
    return colors[quality] or colors.Common or Color3.fromRGB(225, 225, 225)
end

--[[
格式化金币显示（使用大数值缩写）
@param amount number - 金币数量
@return string - 格式化文本
]]
local function FormatCoins(amount)
    return FormatHelper.FormatCoinsShort(amount, true)  -- 带$符号
end

local function FormatStatNumber(value)
    if value == nil then
        return "0"
    end
    if type(value) ~= "number" then
        return tostring(value)
    end

    local intValue = math.floor(value + 1e-6)
    if math.abs(value - intValue) < 0.001 then
        return tostring(intValue)
    end

    local text = string.format("%.2f", value)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

local function UpdateInformationPanel(itemData)
    if not itemData or not itemData.UnitId then
        return
    end
    if not InitializeUI() then
        return
    end
    if not infoFrame then
        return
    end

    local unitId = itemData.UnitId
    local unitData = UnitConfig.GetUnitById(unitId)
    local level = 1

    local infoCard = infoFrame:FindFirstChild("ItemCardTemplate")
    if not infoCard then
        warn(LOG_PREFIX, "找不到 Information/ItemCardTemplate")
        return
    end
    infoCard.Visible = true

    local iconBg = infoCard:FindFirstChild("IconBg")
    local icon = iconBg and iconBg:FindFirstChild("Icon")
    if icon and icon:IsA("ImageLabel") then
        icon.Image = itemData.Icon or (unitData and unitData.Icon) or "rbxassetid://0"
    end

    local powerLabel = infoCard:FindFirstChild("Power")
    if powerLabel and powerLabel:IsA("TextLabel") then
        local powerValue = PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, level)
        powerLabel.RichText = true
        powerLabel.Text = string.format(
            "Power:<font color=\"rgb(255,255,0)\">%s</font>",
            FormatStatNumber(powerValue)
        )
    end

    local qualityLabel = infoCard:FindFirstChild("Quality")
    if qualityLabel and qualityLabel:IsA("TextLabel") then
        local qualityName = itemData.Quality or (unitData and unitData.Quality) or "Common"
        qualityLabel.Text = qualityName
        qualityLabel.TextColor3 = GetQualityColor(qualityName)
    end

    local atkVal = UnitConfig.CalculateAttack(unitId, level)
    local hpVal = UnitConfig.CalculateHealth(unitId, level)
    local asVal = UnitConfig.GetAttackSpeed(unitId)
    local rngVal = UnitConfig.GetAttackRange(unitId)

    local function SetStat(containerName, value)
        local container = infoFrame:FindFirstChild(containerName)
        local numLabel = container and container:FindFirstChild("Num")
        if numLabel and numLabel:IsA("TextLabel") then
            numLabel.Text = FormatStatNumber(value)
        end
    end

    SetStat("HP", hpVal)
    SetStat("ATK", atkVal)
    SetStat("AS", asVal)
    SetStat("RNG", rngVal)
end

local function OpenInformationPanel(itemData)
    if not itemData or not itemData.UnitId then
        return
    end
    if not InitializeUI() then
        return
    end
    if not infoFrame then
        return
    end

    UpdateInformationPanel(itemData)
    if not infoFrame.Visible then
        PlayInfoOpen()
    end
end

--[[
创建商品卡片UI（V2.1修复：使用UI模板而非代码生成）
@param itemData table - 商品数据
@param index number - 索引位置
@return Frame - 创建的卡片Frame
]]
local function CreateItemCard(itemData, index)
    -- 查找ItemCardTemplate模板
    local template = itemContainer:FindFirstChild("ItemCardTemplate")
    if not template then
        warn(LOG_PREFIX, "找不到 ItemCardTemplate 模板")
        return nil
    end

    -- 克隆模板
    local cardFrame = template:Clone()
    cardFrame.Name = "ItemCard_" .. itemData.UnitId
    cardFrame.Visible = true  -- 模板默认是隐藏的，克隆后显示
    cardFrame.LayoutOrder = itemData.Sort or index

    -- V2.1修复：从UnitConfig读取兵种数据并计算属性
    local unitId = itemData.UnitId
    local unitData = UnitConfig.GetUnitById(unitId)
    local level = (unitData and unitData.BaseLevel) or 1

    -- V2.1修复：使用升级公式计算攻击力和生命值
    local atkVal = UnitConfig.CalculateAttack(unitId, level)
    local hpVal = UnitConfig.CalculateHealth(unitId, level)

    -- V2.3优化: 填充卡片图标 - 预加载系统应该已经缓存了这些图片
    local iconBg = cardFrame:FindFirstChild("IconBg")
    if iconBg then
        local icon = iconBg:FindFirstChild("Icon")
        if icon and icon:IsA("ImageLabel") then
            icon.Image = itemData.Icon or "rbxassetid://0"

            -- 可选: 调试图标设置
            if DEBUG_MODE and itemData.Icon and itemData.Icon ~= "rbxassetid://0" then
                print(LOG_PREFIX, "设置商店图标:", unitId, "→", itemData.Icon)
            end
        end
    end

    -- 设置属性文本
    local atk = cardFrame:FindFirstChild("ATK")
    if atk and atk:IsA("TextLabel") then
        atk.Text = tostring(atkVal)
    end

    -- V2.1修复：Range显示类型（英文枚举值：Melee/Ranged）【注意：字段名是Range不是RANGE】
    local range = cardFrame:FindFirstChild("Range")
    if range and range:IsA("TextLabel") then
        -- 强制使用UnitConfig.IsRangedUnit判定，获取标准枚举值
        local isRanged = UnitConfig.IsRangedUnit(unitId)
        local unitTypeText = isRanged and UnitConfig.UnitType.RANGED or UnitConfig.UnitType.MELEE
        range.Text = unitTypeText

        -- 颜色：近战黄(255,255,127) vs 远程蓝(170,170,255)
        range.TextColor3 = isRanged and Color3.fromRGB(170, 170, 255)
                                      or Color3.fromRGB(255, 255, 127)
    end

    local hp = cardFrame:FindFirstChild("HP")
    if hp and hp:IsA("TextLabel") then
        hp.Text = tostring(hpVal)
    end

    local levelLabel = cardFrame:FindFirstChild("Level")
    if levelLabel and levelLabel:IsA("TextLabel") then
        levelLabel.Text = "Lv." .. tostring(level)
    end

    local name = cardFrame:FindFirstChild("Name")
    if name and name:IsA("TextLabel") then
        name.Text = itemData.Name or itemData.UnitId
    end

    -- V2.1库存功能：设置库存数量
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

    local price = cardFrame:FindFirstChild("Price")
    if price and price:IsA("TextLabel") then
        local priceValue = tonumber(itemData.Price) or 0
        price.Text = FormatCoins(priceValue)

        -- V2.1调试：验证UI显示价格与ShopConfig一致性
        if DEBUG_MODE and itemData.Price then
            print(string.format(
                "%s UI显示价格 - UnitId:%s 价格:%d 显示:%s",
                LOG_PREFIX,
                itemData.UnitId,
                priceValue,
                price.Text
            ))
        end
    end

    local quality = cardFrame:FindFirstChild("Quality")
    if quality and quality:IsA("TextLabel") then
        quality.Text = itemData.Quality or "Common"
        quality.TextColor3 = GetQualityColor(itemData.Quality)
    end

    -- 存储商品数据到卡片（用于点击事件）
    cardFrame:SetAttribute("UnitId", itemData.UnitId)
    cardFrame:SetAttribute("Price", itemData.Price)
    cardFrame:SetAttribute("Stock", itemData.Stock or 999)

    if DEBUG_MODE then
        print(LOG_PREFIX, "创建商品卡片:", itemData.UnitId, itemData.Name)
    end

    return cardFrame
end

--[[
处理购买按钮点击
@param itemData table - 商品数据
]]
function OnPurchaseButtonClick(itemData)
    -- V2.1修复：防重复购买和空数据检查
    if isPurchasing then
        if DEBUG_MODE then
            print(LOG_PREFIX, "购买处理中，请稍候")
        end
        return
    end

    -- V2.1修复：验证传入的商品数据
    if not itemData or not itemData.UnitId then
        if DEBUG_MODE then
            print(LOG_PREFIX, "商品数据无效:", itemData)
        end
        return
    end

    if not InitializeEvents() then
        warn(LOG_PREFIX, "事件未初始化，无法购买")
        return
    end

    -- V2.1修复：检查库存
    if itemData.Stock and itemData.Stock <= 0 then
        if DEBUG_MODE then
            print(LOG_PREFIX, "库存不足，无法购买:", itemData.UnitId)
        end
        ShowSystemError("Out of stock")
        PlayPurchaseErrorSound()
        return
    end

    if DEBUG_MODE then
        print(LOG_PREFIX, "尝试购买:", itemData.UnitId, "价格:", itemData.Price)
    end

    -- 设置购买状态
    isPurchasing = true

    -- 发送购买请求到服务端
    PurchaseUnit:FireServer(itemData.UnitId)

    -- V2.1修复：0.5秒后重置购买状态（防止服务器响应丢失导致永久锁定）
    task.delay(0.5, function()
        isPurchasing = false
    end)
end

--[[
全局购买按钮点击处理（V2.1修复：统一处理）
]]
local function OnGlobalBuyButtonClick()
    -- 使用当前选中的商品数据
    if currentSelectedItem then
        OnPurchaseButtonClick(currentSelectedItem)
    else
        if DEBUG_MODE then
            print(LOG_PREFIX, "没有选中的商品")
        end
    end
end

--[[
设置卡片点击展开逻辑（下拉展开购买按钮）
@param cardFrame Frame - 卡片Frame
@param itemData table - 商品数据
]]
local function SetupCardClickLogic(cardFrame, itemData)
    -- 查找BuyButtonFrame
    local buyButtonFrame = itemContainer:FindFirstChild("BuyButtonFrame")
    if not buyButtonFrame then
        warn(LOG_PREFIX, "找不到 BuyButtonFrame")
        return
    end

    -- 查找购买按钮
    local goldBuy = buyButtonFrame:FindFirstChild("GoldBuy")
    local robuxBuy = buyButtonFrame:FindFirstChild("RobuxBuy")

    -- V2.1修复：清理旧的事件连接（如果存在）
    local cardId = itemData.UnitId
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
        -- 如果当前卡片已展开，则收起
        if buyButtonFrame.Visible and buyButtonFrame:GetAttribute("CurrentCardId") == itemData.UnitId then
            -- 收起
            buyButtonFrame.Visible = false
            buyButtonFrame:SetAttribute("CurrentCardId", nil)
            currentSelectedItem = nil  -- V2.1修复：清空选中项
            if DEBUG_MODE then
                print(LOG_PREFIX, "收起购买按钮")
            end
        else
            -- 展开：移动到当前卡片下方
            local cardIndex = cardFrame.LayoutOrder
            buyButtonFrame.LayoutOrder = cardIndex + 1

            -- V2.1修复：设置当前选中商品（关键修复）
            currentSelectedItem = itemData

            -- 更新按钮价格
            if goldBuy then
                local goldPrice = goldBuy:FindFirstChild("Price")
                if goldPrice and goldPrice:IsA("TextLabel") then
                    goldPrice.Text = FormatCoins(itemData.Price or 0)
                end
            end

            if robuxBuy then
                local robuxPrice = robuxBuy:FindFirstChild("Price")
                if robuxPrice and robuxPrice:IsA("TextLabel") then
                    robuxPrice.Text = "R$ " .. tostring(itemData.RobuxPrice or 0)
                end
                -- 如果没有Robux价格，隐藏Robux按钮
                robuxBuy.Visible = (itemData.RobuxPrice and itemData.RobuxPrice > 0)
            end

            buyButtonFrame.Visible = true
            buyButtonFrame:SetAttribute("CurrentCardId", itemData.UnitId)

            if DEBUG_MODE then
                print(LOG_PREFIX, "展开购买按钮:", itemData.UnitId, "价格:", itemData.Price)
            end
        end

        -- V6.6：点击卡片时同步打开详情面板
        OpenInformationPanel(itemData)
    end)
    table.insert(purchaseConnections[cardId], clickConnection)

    -- V6.6：详情按钮点击
    local iconBg = cardFrame:FindFirstChild("IconBg")
    local infoButton = iconBg and iconBg:FindFirstChild("Information")
    if infoButton and infoButton:IsA("GuiButton") then
        if infoButton.ZIndex <= clickButton.ZIndex then
            infoButton.ZIndex = clickButton.ZIndex + 1
        end

        local infoConn = infoButton.MouseButton1Click:Connect(function()
            OpenInformationPanel(itemData)
        end)
        table.insert(purchaseConnections[cardId], infoConn)

        if LoadUIHelpers() and ButtonEffectHelper then
            ButtonEffectHelper.AddClickEffect(infoButton)
        end
    end

    -- V2.1修复：添加按钮特效（仅为卡片点击添加，购买按钮特效在初始化时统一处理）
    if LoadUIHelpers() and ButtonEffectHelper then
        ButtonEffectHelper.AddClickEffect(clickButton)
    end
end

--[[
初始化全局购买按钮事件（V2.1修复：统一管理）
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

    -- V2.1修复：清理旧的全局连接
    for _, connection in ipairs(globalBuyConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    globalBuyConnections = {}

    -- V2.1修复：只绑定一次全局购买按钮事件
    if goldBuy then
        local goldConnection = goldBuy.MouseButton1Click:Connect(OnGlobalBuyButtonClick)
        table.insert(globalBuyConnections, goldConnection)

        -- 添加按钮特效
        if LoadUIHelpers() and ButtonEffectHelper then
            ButtonEffectHelper.AddClickEffect(goldBuy)
        end

        if DEBUG_MODE then
            print(LOG_PREFIX, "已绑定全局金币购买按钮")
        end
    end

    if robuxBuy then
        local robuxConnection = robuxBuy.MouseButton1Click:Connect(function()
            -- Robux购买逻辑
            if currentSelectedItem then
                if not PurchaseUnitRobux then
                    warn(LOG_PREFIX, "PurchaseUnitRobux事件未找到，无法进行Robux购买")
                    return
                end

                -- 检查是否有Robux价格
                if not currentSelectedItem.RobuxPrice or currentSelectedItem.RobuxPrice <= 0 then
                    warn(LOG_PREFIX, "该商品不支持Robux购买:", currentSelectedItem.UnitId)
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
                    print(LOG_PREFIX, "尝试Robux购买:", currentSelectedItem.UnitId, "价格: R$", currentSelectedItem.RobuxPrice)
                end

                -- 设置购买状态
                isPurchasing = true

                -- 发送Robux购买请求到服务端
                PurchaseUnitRobux:FireServer(currentSelectedItem.UnitId)

                -- 0.5秒后重置购买状态
                task.delay(0.5, function()
                    isPurchasing = false
                end)
            else
                warn(LOG_PREFIX, "没有选中的商品，无法进行Robux购买")
            end
        end)
        table.insert(globalBuyConnections, robuxConnection)

        -- 添加按钮特效
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
        if child:IsA("Frame") and string.find(child.Name, "ItemCard_") then
            child:Destroy()
        end
    end

    -- V6.6：刷新列表时关闭详情面板，避免数据错位
    HideInformationImmediate()

    -- Reset selection and hide buy buttons when list refreshes.
    currentSelectedItem = nil
    local buyButtonFrame = itemContainer:FindFirstChild("BuyButtonFrame")
    if buyButtonFrame then
        buyButtonFrame.Visible = false
        buyButtonFrame:SetAttribute("CurrentCardId", nil)
    end

    -- 加载UI助手
    LoadUIHelpers()

    -- V2.1修复：初始化全局购买按钮（只执行一次）
    InitializeGlobalBuyButtons()

    -- 创建商品卡片
    for index, itemData in ipairs(shopData) do
        local cardFrame = CreateItemCard(itemData, index)
        if cardFrame then
            cardFrame.Parent = itemContainer

            -- 绑定卡片点击展开逻辑
            SetupCardClickLogic(cardFrame, itemData)
        end
    end

    -- V2.1修复：UIGridLayout会自动布局，无需手动调用ApplyLayout

    if DEBUG_MODE then
        print(LOG_PREFIX, "商店显示已更新，商品数量:", #shopData)
    end
end

--[[
处理商店列表事件
@param shopList table - 商店商品列表
]]
local function OnShopListReceived(shopList)
    if DEBUG_MODE then
        print(LOG_PREFIX, "收到商店列表，商品数量:", shopList and #shopList or 0)

        -- V2.1调试：详细打印每个商品的价格信息
        if shopList then
            for i, item in ipairs(shopList) do
                if i <= 5 then -- 只打印前5个，避免日志过多
                    print(string.format(
                        "%s 商品[%d] UnitId:%s 名称:%s 价格:%s",
                        LOG_PREFIX,
                        i,
                        item.UnitId or "nil",
                        item.Name or "nil",
                        tostring(item.Price or "nil")
                    ))
                end
            end
            if #shopList > 5 then
                print(LOG_PREFIX, "... 还有", #shopList - 5, "个商品")
            end
        end
    end

    if not shopList or type(shopList) ~= "table" then
        warn(LOG_PREFIX, "商店列表数据无效:", shopList)
        return
    end

    shopData = shopList
    UpdateShopDisplay()
end

--[[
处理购买结果事件
@param success boolean - 是否购买成功
@param message string - 结果消息
@param unitId string - 单位ID（如果成功）
@param newCoinAmount number - 新的金币数量（如果成功）
]]
local function OnPurchaseResultReceived(success, message, unitId, newCoinAmount)
    -- V2.1修复：重置购买状态
    isPurchasing = false

    if DEBUG_MODE then
        print(LOG_PREFIX, "购买结果:", success, message, unitId, newCoinAmount)
    end

    if success then
        -- 购买成功
        if LoadUIHelpers() and CoinAnimationHelper then
            -- 根据unitId找到对应商品的价格
            local actualPrice = 0
            for _, itemData in ipairs(shopData) do
                if itemData.UnitId == unitId then
                    actualPrice = itemData.Price
                    break
                end
            end

            -- 播放金币变化特效
            local startPos = UDim2.new(0.5, 0, 0.5, 0) -- 屏幕中心
            CoinAnimationHelper.CreateCoinChangeEffect(
                playerGui,
                -actualPrice, -- 显示实际购买商品的价格
                startPos,
                {
                    Duration = 1.2,
                    TextColor = Color3.fromRGB(255, 100, 100), -- 红色表示消费
                }
            )
        end

        -- 显示成功消息（简单的通知）
        local successNotification = Instance.new("TextLabel")
        successNotification.Name = "SuccessNotification"
        successNotification.Size = UDim2.new(0, 300, 0, 60)
        successNotification.Position = UDim2.new(0.5, -150, 0.1, 0)
        successNotification.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
        successNotification.BorderSizePixel = 0
        successNotification.Text = "购买成功！"
        successNotification.TextColor3 = Color3.fromRGB(255, 255, 255)
        successNotification.TextScaled = true
        successNotification.Font = Enum.Font.GothamBold
        successNotification.Parent = playerGui

        local notificationCorner = Instance.new("UICorner")
        notificationCorner.CornerRadius = UDim.new(0, 8)
        notificationCorner.Parent = successNotification

        -- 自动消失
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

        -- 显示失败消息
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

        -- 自动消失
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

-- ==================== V2.1库存系统处理函数 ====================

--[[
处理库存更新事件
@param shopId string - 商店ID
@param stockData table - 库存数据 {[unitId] = stock}
]]
local function OnStockUpdate(shopId, stockData)
    if DEBUG_MODE then
        print(LOG_PREFIX, "收到库存更新:", shopId)
    end

    -- 更新当前库存数据
    currentStockData = stockData or {}

    -- 尝试从ShopConfig获取商店显示名称（如果可用）
    local success, shopConfig = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ShopConfig"))
    end)
    if success and shopConfig then
        currentShopName = shopConfig.GetShopDisplayName(shopId) or "兵种商店"
    end

    -- 更新所有商品卡片的库存显示
    if itemContainer then
        for _, card in ipairs(itemContainer:GetChildren()) do
            if card:IsA("Frame") and string.find(card.Name, "ItemCard_") then
                local unitId = string.gsub(card.Name, "ItemCard_", "")
                local stock = currentStockData[unitId] or 0

                -- 更新Number标签（库存数量）
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

                -- 更新卡片的Attribute
                card:SetAttribute("Stock", stock)
            end
        end
    end
end

--[[
更新标题文本（V2.1修复：严格格式"Stock refreshes in XX:YY"）
]]
local function UpdateTitleText()
    if not titleLabel then return end
    local minutes = math.floor(math.max(0, refreshTimeRemaining) / 60)
    local seconds = math.max(0, refreshTimeRemaining) % 60
    titleLabel.Text = string.format("Stock refreshes in %02d:%02d", minutes, seconds)
end

--[[
处理刷新倒计时更新事件（V2.1修复：严格按照"Stock refreshes in XX:YY"格式）
@param remainingTime number - 剩余时间（秒）
]]
local function OnRefreshTimeUpdate(remainingTime)
    refreshTimeRemaining = remainingTime or 0
    lastSyncTick = tick()
    UpdateTitleText()
end

-- ==================== 公共接口 ====================

--[[
初始化商店显示系统
]]
function ShopDisplay.Initialize()
    if DEBUG_MODE then
        print(LOG_PREFIX, "初始化商店显示系统...")
    end

    -- 初始化UI
    if not InitializeUI() then
        warn(LOG_PREFIX, "UI初始化失败")
        return false
    end

    -- 初始化事件
    if not InitializeEvents() then
        warn(LOG_PREFIX, "事件初始化失败")
        return false
    end

    -- 连接事件监听
    ShopListEvent.OnClientEvent:Connect(OnShopListReceived)
    PurchaseResult.OnClientEvent:Connect(OnPurchaseResultReceived)

    -- V2.1库存功能：连接库存事件监听
    if StockUpdate then
        StockUpdate.OnClientEvent:Connect(OnStockUpdate)
    end
    if RefreshTimeUpdate then
        RefreshTimeUpdate.OnClientEvent:Connect(OnRefreshTimeUpdate)
    end

    -- 设置关闭按钮（如果存在）
    if closeButton then
        closeButton.MouseButton1Click:Connect(function()
            ShopDisplay.PlayClose()
        end)

        -- 添加按钮特效
        if LoadUIHelpers() and ButtonEffectHelper then
            ButtonEffectHelper.AddClickEffect(closeButton)
        end
    end

    -- 设置详情关闭按钮（V6.6）
    if infoCloseButton and infoCloseButton:IsA("GuiButton") then
        infoCloseButton.MouseButton1Click:Connect(function()
            PlayInfoClose()
        end)

        if LoadUIHelpers() and ButtonEffectHelper then
            ButtonEffectHelper.AddClickEffect(infoCloseButton)
        end
    end

    -- V2.1修复：监听shopFrame可见性变化，实现界面打开时实时更新倒计时
    if shopFrame then
        shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
            SetShopBackdropVisible(shopFrame.Visible)
            if shopFrame.Visible then
                -- 开始本地每秒更新标题
                if titleUpdateConn then
                    titleUpdateConn:Disconnect()
                    titleUpdateConn = nil
                end

                titleUpdateConn = RunService.Heartbeat:Connect(function()
                    if lastSyncTick > 0 then
                        local now = tick()
                        local passed = now - lastSyncTick
                        if passed >= 1.0 then  -- 每秒更新一次
                            refreshTimeRemaining = math.max(0, refreshTimeRemaining - 1)
                            lastSyncTick = now
                            UpdateTitleText()
                        end
                    end
                end)

                -- 打开瞬间先用当前缓存值刷新一次
                UpdateTitleText()
            else
                -- 隐藏时断开连接
                if titleUpdateConn then
                    titleUpdateConn:Disconnect()
                    titleUpdateConn = nil
                end
                HideInformationImmediate()
            end
        end)
    end

    if DEBUG_MODE then
        print(LOG_PREFIX, "商店显示系统初始化完成")
    end

    return true
end

--[[
请求商店列表（通常由ShopTrigger调用）
]]
function ShopDisplay.RequestShopList()
    if not InitializeEvents() then
        warn(LOG_PREFIX, "事件未初始化，无法请求商店列表")
        return
    end

    RequestShopList:FireServer()

    if DEBUG_MODE then
        print(LOG_PREFIX, "已请求商店列表")
    end
end

--[[
获取当前商店数据
@return table - 商店数据
]]
function ShopDisplay.GetShopData()
    return shopData
end

--[[
清理商店显示
]]
function ShopDisplay.Cleanup()
    shopData = {}
    HideInformationImmediate()
    SetShopBackdropVisible(false)

    -- V2.1修复：清理选中状态和全局连接
    currentSelectedItem = nil
    for _, connection in ipairs(globalBuyConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    globalBuyConnections = {}

    -- 清理所有购买连接
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
            if child:IsA("Frame") and string.find(child.Name, "ItemCard_") then
                child:Destroy()
            end
        end
    end

    if DEBUG_MODE then
        print(LOG_PREFIX, "商店显示已清理")
    end
end

-- ==================== 自动初始化 ====================

_G.ShopDisplay = ShopDisplay

-- V2.1修复：使用协程异步初始化，既不阻塞脚本加载，又确保UI准备好后才绑定事件
task.spawn(function()
    local success, result = pcall(ShopDisplay.Initialize)
    if not success then
        warn(LOG_PREFIX, "初始化失败:", result)
    end
end)

return ShopDisplay
