--[[
=====================================================
脚本名称: VictoryUIController
脚本类型: LocalScript (客户端UI控制器)
脚本位置: StarterPlayerScripts/Utils/VictoryUIController.lua
版本: V2.4
=====================================================

功能描述:
- 处理战斗结算界面的显示和交互
- 响应服务器发送的VictoryPopup事件
- 处理玩家确认按钮点击并通知服务器
- 管理Victory UI的显示状态

V2.4新功能:
- 战斗结束后显示结算弹窗而非立即复生
- 玩家必须点击确认按钮才能完成战斗结算
- 支持不同的战斗结果显示（胜利/失败/平局）

UI路径说明:
- Victory UI应该存在于 StarterGui 中，运行时会自动复制到 PlayerGui
- 实际访问路径：PlayerGui > Victory > Effect/Information
- 确认按钮路径：PlayerGui > Victory > Information > Confirm
- 注意：无需创建Back Frame，只需Effect和Information两个Frame

]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local FormatHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FormatHelper"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local StageConfig = nil
pcall(function()
    StageConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StageConfig"))
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 尝试获取UI元素（不使用WaitForChild，避免无限等待）
local victoryGui = playerGui:FindFirstChild("Victory")
local effectFrame = nil
local informationFrame = nil
local confirmButton = nil
local reviveFrame = nil
local reviveButton = nil
local revivePriceLabel = nil
local bgFrame = nil
local progressBg = nil
local progressPlayerIcon = nil
local cashNumLabel = nil
local distanceTextLabel = nil

-- 获取远程事件
local events = ReplicatedStorage:WaitForChild("Events")
local battleEvents = events:WaitForChild("BattleEvents")
local victoryPopupEvent = battleEvents:WaitForChild("VictoryPopup")
local victoryConfirmEvent = battleEvents:WaitForChild("VictoryConfirm")
local battleStateUpdateEvent = battleEvents:WaitForChild("BattleStateUpdate", 5)
local reviveResultEvent = battleEvents:FindFirstChild("ReviveResult")

-- 本地变量
local currentBattleId = nil
local isVictoryShowing = false
local uiInitialized = false
local campaignCoinTotal = 0
local battleCoinTotal = 0
local campaignVipBonusTotal = 0
local battleVipBonusTotal = 0
local isCampaignActive = false
local isBattleActive = false
local lastCampaignChapter = nil
local lastCampaignTotalStages = nil
local lastCampaignStage = nil
local currentReviveProductId = nil
local currentRevivePrice = nil
local reviveAvailable = false
local revivePromptInProgress = false
local reviveResultConnected = false
local REVIVE_BUTTON_ENABLED = false

-- 调试日志（已禁用）
local function DebugLog(...)
    -- print("[VictoryUIController]", ...)
end

--[[
安全获取UI元素
@param parent Instance - 父对象
@param childName string - 子对象名称
@param timeout number - 超时时间（秒），可选，默认3秒
@return Instance|nil - 找到的对象或nil
]]
local function SafeWaitForChild(parent, childName, timeout)
    timeout = timeout or 3

    local child = parent:FindFirstChild(childName)
    if child then
        return child
    end

    DebugLog(string.format("正在等待 %s 中的 %s...", parent.Name, childName))

    local startTime = tick()
    while tick() - startTime < timeout do
        child = parent:FindFirstChild(childName)
        if child then
            DebugLog(string.format("找到 %s", childName))
            return child
        end
        task.wait(0.1)
    end

    DebugLog(string.format("超时：未找到 %s 中的 %s", parent.Name, childName))
    return nil
end

local function ScaleUDim2(value, scale)
    return UDim2.new(value.X.Scale * scale, value.X.Offset * scale, value.Y.Scale * scale, value.Y.Offset * scale)
end

local function GetPercentColor(percent)
    if percent <= 20 then
        return Color3.fromRGB(0, 255, 0)
    elseif percent <= 50 then
        return Color3.fromRGB(255, 255, 0)
    end
    return Color3.fromRGB(255, 0, 0)
end

local function FormatCashAmount(amount, vipBonus)
    local numberAmount = tonumber(amount) or 0
    local baseText = "+$" .. FormatHelper.FormatNumberWithCommas(numberAmount)

    local bonusAmount = tonumber(vipBonus) or 0
    if bonusAmount > 0 and player:GetAttribute("VipPurchased") == true then
        return string.format("%s(Vip+%s)", baseText, FormatHelper.FormatNumberWithCommas(bonusAmount))
    end

    return baseText
end

local function GetReviveConfig()
    local reviveConfig = GameConfig.Revive
    if not reviveConfig then
        return nil
    end

    local chapter = tonumber(lastCampaignChapter) or tonumber(player:GetAttribute("CurrentChapter")) or 0
    local maxChapter = tonumber(reviveConfig.MaxChapter) or 0

    if chapter <= 0 then
        return nil
    end

    if maxChapter > 0 and chapter > maxChapter then
        return nil
    end

    local productId = reviveConfig.ProductIdsByChapter and reviveConfig.ProductIdsByChapter[chapter]
    local price = reviveConfig.PricesByChapter and reviveConfig.PricesByChapter[chapter]
    if not productId or not price then
        return nil
    end

    return chapter, productId, price
end

local function SetPlayerIconImage(imageLabel)
    if not imageLabel then
        return
    end

    local success, result = pcall(function()
        return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    end)

    if success and result then
        imageLabel.Image = result
    end
end

local function GetDistanceProgress(stageNum, preferStageProgress)
    local progressValue = nil
    local distanceGui = playerGui:FindFirstChild("Distance")
    if distanceGui then
        local distanceBg = distanceGui:FindFirstChild("Bg")
        local distanceProgressBg = distanceBg and distanceBg:FindFirstChild("ProgressBg")
        local distancePlayerIcon = distanceProgressBg and distanceProgressBg:FindFirstChild("PlayerIcon")
        if distancePlayerIcon and distancePlayerIcon.Position then
            progressValue = distancePlayerIcon.Position.X.Scale
        end
    end

    local stageToUse = tonumber(stageNum) or tonumber(lastCampaignStage) or 0
    local totalStages = tonumber(lastCampaignTotalStages)

    if (not totalStages or totalStages <= 0) and StageConfig then
        local chapterToUse = tonumber(lastCampaignChapter) or tonumber(player:GetAttribute("CurrentChapter")) or 1
        totalStages = StageConfig.GetStagesPerChapter(chapterToUse)
    end

    if preferStageProgress and stageToUse > 0 and totalStages and totalStages > 0 then
        return math.clamp(stageToUse / totalStages, 0, 1)
    end

    if type(progressValue) == "number" then
        return math.clamp(progressValue, 0, 1)
    end

    if stageToUse > 0 and totalStages and totalStages > 0 then
        return math.clamp(stageToUse / totalStages, 0, 1)
    end

    return 0
end

local function UpdateDistanceText(progress)
    if not distanceTextLabel then
        return
    end

    local remaining = math.clamp(1 - progress, 0, 1)
    local remainingPercent = math.floor(remaining * 100 + 0.5)
    local color = GetPercentColor(remainingPercent)

    distanceTextLabel.RichText = true
    distanceTextLabel.Text = string.format(
        '<font color="rgb(255,255,255)">Distance to Escape:</font> <font color="rgb(%d,%d,%d)">%d%%</font>',
        math.floor(color.R * 255),
        math.floor(color.G * 255),
        math.floor(color.B * 255),
        remainingPercent
    )
end

local function AddBattleCoins(amount, vipBonus)
    if type(amount) ~= "number" or amount <= 0 then
        return
    end

    local bonus = tonumber(vipBonus) or 0

    if isCampaignActive then
        campaignCoinTotal = campaignCoinTotal + amount
        campaignVipBonusTotal = campaignVipBonusTotal + bonus
    elseif isBattleActive then
        battleCoinTotal = battleCoinTotal + amount
        battleVipBonusTotal = battleVipBonusTotal + bonus
    end
end

local function GetCurrentCoinTotal(isCampaignBattle)
    if isCampaignBattle then
        return campaignCoinTotal, campaignVipBonusTotal
    end
    return battleCoinTotal, battleVipBonusTotal
end

--[[
初始化UI元素
@return boolean - 是否初始化成功
]]
local function InitializeUI()
    DebugLog("开始初始化UI元素...")

    -- 首先检查Victory GUI是否存在
    if not victoryGui then
        DebugLog("正在等待Victory UI...")
        victoryGui = SafeWaitForChild(playerGui, "Victory", 5)

        if not victoryGui then
            DebugLog("❌ 错误：Victory UI不存在")
            DebugLog("请确保在StarterGui中创建Victory ScreenGui")
            return false
        end
    end

    DebugLog("✅ Victory UI已找到")

    -- 获取子元素（移除Back Frame）
    effectFrame = SafeWaitForChild(victoryGui, "Effect", 2)
    informationFrame = SafeWaitForChild(victoryGui, "Information", 2)
    bgFrame = SafeWaitForChild(victoryGui, "Bg", 2)

    -- 检查必需的UI元素
    local missingElements = {}
    if not effectFrame then table.insert(missingElements, "Effect") end
    if not informationFrame then table.insert(missingElements, "Information") end

    if #missingElements > 0 then
        DebugLog("❌ 缺少以下UI元素:", table.concat(missingElements, ", "))
        DebugLog("请在Victory UI中创建这些Frame")
        return false
    end

    DebugLog("✅ 基本UI元素已找到")

    -- 获取确认按钮
    if informationFrame then
        confirmButton = SafeWaitForChild(informationFrame, "Confirm", 2)

        if not confirmButton then
            DebugLog("❌ 错误：确认按钮不存在")
            DebugLog("请在Information Frame中创建Confirm按钮")
            return false
        end

        DebugLog("✅ 确认按钮已找到")

        cashNumLabel = SafeWaitForChild(informationFrame, "CashNum", 2)
        distanceTextLabel = SafeWaitForChild(informationFrame, "DistanceText", 2)
        if distanceTextLabel then
            distanceTextLabel.RichText = true
        end

        reviveFrame = SafeWaitForChild(informationFrame, "Revive", 2)
        if reviveFrame then
            if reviveFrame:IsA("GuiButton") then
                reviveButton = reviveFrame
                revivePriceLabel = reviveFrame:FindFirstChild("Price", true)
            else
                reviveButton = SafeWaitForChild(reviveFrame, "Confirm", 2)
                if reviveButton then
                    revivePriceLabel = SafeWaitForChild(reviveButton, "Price", 2)
                end
            end
        end
    end

    if bgFrame then
        progressBg = SafeWaitForChild(bgFrame, "ProgressBg", 2)
        if progressBg then
            progressPlayerIcon = SafeWaitForChild(progressBg, "PlayerIcon", 2)
        end
    end

    return true
end

--[[
显示UI框架（无动画）
@param frame Frame - 要显示的UI框架
]]
local function ShowFrame(frame)
    if frame then
        frame.Visible = true
    end
end

--[[
隐藏UI框架（无动画）
@param frame Frame - 要隐藏的UI框架
]]
local function HideFrame(frame)
    if frame then
        frame.Visible = false
    end
end

--[[
播放棒球棍敲击动画
@param imageLabel ImageLabel - 棒球棍图片
@param fromLeft boolean - 是否从左边飞入
@param duration number - 动画时长
]]
local function PlayBatAnimation(imageLabel, fromLeft, duration)
    if not imageLabel then return end

    duration = duration or 0.4

    -- 保存原始位置和旋转
    local originalPosition = imageLabel.Position
    local originalRotation = imageLabel.Rotation
    local originalSize = imageLabel.Size

    -- 设置初始状态：从屏幕外飞入
    if fromLeft then
        -- 左边棒球棍：从左上方飞入，顺时针旋转
        imageLabel.Position = UDim2.new(-0.3, 0, -0.3, 0)
        imageLabel.Rotation = -45
    else
        -- 右边棒球棍：从右上方飞入，逆时针旋转
        imageLabel.Position = UDim2.new(1.3, 0, -0.3, 0)
        imageLabel.Rotation = 45
    end

    imageLabel.Size = UDim2.new(originalSize.X.Scale * 0.8, 0, originalSize.Y.Scale * 0.8, 0)
    imageLabel.Visible = true

    -- 创建飞入动画（快速）
    local flyIn = TweenService:Create(
        imageLabel,
        TweenInfo.new(duration * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Position = originalPosition,
            Rotation = originalRotation,
            Size = originalSize
        }
    )

    -- 创建轻微回弹效果
    local bounce = TweenService:Create(
        imageLabel,
        TweenInfo.new(duration * 0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
        {
            Rotation = originalRotation
        }
    )

    flyIn:Play()

    -- 飞入完成后播放回弹
    flyIn.Completed:Connect(function()
        bounce:Play()
    end)

    return flyIn
end

--[[
播放文本弹出动画
@param textLabel TextLabel - 文本标签
@param duration number - 动画时长
]]
local function PlayTextPopAnimation(textLabel, duration)
    if not textLabel then return end

    duration = duration or 0.5

    -- 保存原始状态
    local originalSize = textLabel.Size
    local originalPosition = textLabel.Position

    -- 设置初始状态：缩小且透明
    textLabel.Size = UDim2.new(0, 0, 0, 0)
    textLabel.Position = UDim2.new(0.5, 0, 0.5, 0) -- 从中心开始
    textLabel.TextTransparency = 1
    textLabel.TextStrokeTransparency = 1
    textLabel.Visible = true

    -- 创建弹出动画
    local popOut = TweenService:Create(
        textLabel,
        TweenInfo.new(duration, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
        {
            Size = originalSize,
            Position = originalPosition,
            TextTransparency = 0,
            TextStrokeTransparency = 0
        }
    )

    popOut:Play()
    return popOut
end

local function PlayGuiScaleIn(guiObject, duration)
    if not guiObject then return end

    duration = duration or 0.4

    local originalSize = guiObject.Size
    local originalBackgroundTransparency = guiObject.BackgroundTransparency
    local originalTextTransparency = nil
    local originalStrokeTransparency = nil
    local originalImageTransparency = nil

    if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") then
        originalTextTransparency = guiObject.TextTransparency
        originalStrokeTransparency = guiObject.TextStrokeTransparency
        guiObject.TextTransparency = 1
        guiObject.TextStrokeTransparency = 1
    end

    if guiObject:IsA("ImageLabel") or guiObject:IsA("ImageButton") then
        originalImageTransparency = guiObject.ImageTransparency
        guiObject.ImageTransparency = 1
    end

    guiObject.BackgroundTransparency = 1
    guiObject.Size = ScaleUDim2(originalSize, 0.85)
    guiObject.Visible = true

    local goals = {
        Size = originalSize,
        BackgroundTransparency = originalBackgroundTransparency
    }

    if originalTextTransparency ~= nil then
        goals.TextTransparency = originalTextTransparency
        goals.TextStrokeTransparency = originalStrokeTransparency
    end

    if originalImageTransparency ~= nil then
        goals.ImageTransparency = originalImageTransparency
    end

    local tween = TweenService:Create(
        guiObject,
        TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        goals
    )
    tween:Play()

    return tween
end

--[[
播放按钮淡入动画
@param button GuiButton - 按钮对象
@param duration number - 动画时长
]]
local function PlayButtonFadeIn(button, duration)
    if not button then return end

    duration = duration or 0.3

    -- 保存原始状态
    local originalSize = button.Size

    -- 设置初始状态
    button.Size = UDim2.new(originalSize.X.Scale * 0.8, 0, originalSize.Y.Scale * 0.8, 0)
    button.BackgroundTransparency = 1

    -- 如果按钮有文本
    if button:IsA("TextButton") then
        button.TextTransparency = 1
    end

    button.Visible = true

    -- 创建淡入和放大动画
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local goals = {
        Size = originalSize,
        BackgroundTransparency = 0
    }

    if button:IsA("TextButton") then
        goals.TextTransparency = 0
    end

    local fadeIn = TweenService:Create(button, tweenInfo, goals)
    fadeIn:Play()

    return fadeIn
end

--[[
显示胜利结算界面
@param battleId number - 战斗ID
@param result string - 战斗结果 ("Attack", "Defense", "Draw")
@param stageNum number - 关卡编号
@param extraRewards table - 额外奖励（可选）
]]
local function ShowVictoryUI(battleId, result, stageNum, extraRewards)
	if isVictoryShowing then
		DebugLog("胜利界面已在显示中，忽略重复请求")
		return
	end

	-- 确保battleId有效（客户端防呆）
	-- V2.5修复：battleId=0 表示战役结算，也是有效的
	local isCampaign = (battleId == 0)
	if type(battleId) ~= "number" or (battleId < 0) or (not isCampaign and battleId <= 0) then
		DebugLog(string.format("收到无效的BattleId(%s)，忽略结算界面", tostring(battleId)))
		return
	end

	-- 检查UI是否已初始化
	if not uiInitialized then
		DebugLog("UI未初始化，尝试重新初始化...")
		if not InitializeUI() then
            DebugLog("❌ UI初始化失败，无法显示结算界面")
            return
        end
        uiInitialized = true
    end

    -- 再次检查必需的UI元素是否存在
    if not effectFrame or not informationFrame then
        DebugLog("❌ 关键UI元素缺失，无法显示结算界面")
        return
    end

    isVictoryShowing = true
    currentBattleId = battleId
    reviveAvailable = false
    revivePromptInProgress = false
    currentReviveProductId = nil
    currentRevivePrice = nil

    DebugLog(string.format("显示结算界面 - BattleId: %d, Result: %s, Stage: %d",
        battleId, tostring(result), stageNum))

    if REVIVE_BUTTON_ENABLED and battleId == 0 and tostring(result) == "Defense" then
        local _, productId, price = GetReviveConfig()
        if productId and price and (reviveButton or reviveFrame) then
            reviveAvailable = true
            currentReviveProductId = productId
            currentRevivePrice = price
        end
    end

    if revivePriceLabel and currentRevivePrice then
        revivePriceLabel.Text = tostring(currentRevivePrice)
    end

    -- 更新信息显示（如果有相关UI元素）
    -- 这里可以根据实际UI结构来设置结果文本、关卡信息等

    -- 播放结算音效（如果有的话）
    pcall(function()
        if result == "Attack" then
            -- 播放胜利音效
            -- SoundService:PlayLocalSound(victorySound)
        else
            -- 播放失败音效
            -- SoundService:PlayLocalSound(defeatSound)
        end
    end)

    -- 显示Information Frame（作为容器）
    informationFrame.Visible = true
    if bgFrame then
        bgFrame.Visible = true
    end

    local progressValue = GetDistanceProgress(stageNum, isCampaign)
    if progressPlayerIcon then
        SetPlayerIconImage(progressPlayerIcon)
        progressPlayerIcon.Position = UDim2.new(progressValue, 0, 0.5, 0)
    end

    if cashNumLabel then
        local totalAmount, vipBonus = GetCurrentCoinTotal(isCampaign)
        cashNumLabel.Text = FormatCashAmount(totalAmount, vipBonus)
    end

    if distanceTextLabel then
        UpdateDistanceText(progressValue)
    end

    -- 获取UI元素
    local leftBat = informationFrame:FindFirstChild("ImageLabel") -- 左边棒球棍
    local rightBat = nil
    local victoryText = informationFrame:FindFirstChild("TextLabel")

    -- 查找右边的ImageLabel（第二个ImageLabel）
    for _, child in ipairs(informationFrame:GetChildren()) do
        if child:IsA("ImageLabel") and child ~= leftBat then
            rightBat = child
            break
        end
    end

    -- 确保所有元素初始状态为隐藏
    if leftBat then leftBat.Visible = false end
    if rightBat then rightBat.Visible = false end
    if victoryText then victoryText.Visible = false end
    if confirmButton then confirmButton.Visible = false end
    if reviveFrame then reviveFrame.Visible = false end
    if reviveButton and reviveButton ~= reviveFrame then
        reviveButton.Visible = false
    end
    if cashNumLabel then cashNumLabel.Visible = false end
    if distanceTextLabel then distanceTextLabel.Visible = false end
    if progressBg then progressBg.Visible = false end

    -- 播放动画序列
    task.spawn(function()
        -- 1. 左边棒球棍飞入（0.4秒）
        if leftBat then
            PlayBatAnimation(leftBat, true, 0.4)
        end

        task.wait(0.15) -- 短暂延迟

        -- 2. 右边棒球棍飞入（0.4秒）
        if rightBat then
            PlayBatAnimation(rightBat, false, 0.4)
        end

        task.wait(0.3) -- 等待棒球棍动画接近完成

        -- 3. VICTORY文本弹出（0.5秒）
        if victoryText then
            PlayTextPopAnimation(victoryText, 0.5)
        end

        task.wait(0.6) -- 等待文本动画完成

        -- 4. CashNum弹出（0.4秒）
        if cashNumLabel then
            PlayGuiScaleIn(cashNumLabel, 0.4)
            task.wait(0.5)
        end

        -- 5. DistanceText + ProgressBg 同时动画
        local hasDistanceAnimation = false
        if distanceTextLabel then
            PlayGuiScaleIn(distanceTextLabel, 0.4)
            hasDistanceAnimation = true
        end

        if progressBg then
            PlayGuiScaleIn(progressBg, 0.4)
            hasDistanceAnimation = true
        end

        if hasDistanceAnimation then
            task.wait(0.5)
        end

        -- 6. Confirm按钮淡入（0.3秒）
        if confirmButton then
            PlayButtonFadeIn(confirmButton, 0.3)
        end

        if reviveAvailable then
            if reviveFrame then
                reviveFrame.Visible = true
            end
            if reviveButton then
                PlayButtonFadeIn(reviveButton, 0.3)
            elseif reviveFrame then
                PlayButtonFadeIn(reviveFrame, 0.3)
            end
        end
    end)

    DebugLog("胜利界面动画开始播放")
end

--[[
隐藏胜利结算界面
]]
local function HideVictoryUI()
    if not isVictoryShowing then
        return
    end

    DebugLog("开始隐藏胜利界面")

    -- 隐藏所有子元素
    if informationFrame then
        -- 隐藏所有子元素
        for _, child in ipairs(informationFrame:GetChildren()) do
            if child:IsA("GuiObject") then
                child.Visible = false
            end
        end
        -- 隐藏容器
        informationFrame.Visible = false
    end

    if effectFrame then
        effectFrame.Visible = false
    end

    if bgFrame then
        bgFrame.Visible = false
    end

    isVictoryShowing = false
    currentBattleId = nil
    reviveAvailable = false
    revivePromptInProgress = false
    currentReviveProductId = nil
    currentRevivePrice = nil

    DebugLog("胜利界面隐藏完成")
end

--[[
处理确认按钮点击
]]
local function OnConfirmButtonClick()
	-- V2.5修复：battleId=0 表示战役结算，也是有效的，需要发送确认事件
	local isCampaign = (currentBattleId == 0)
	if currentBattleId == nil or (not isCampaign and currentBattleId <= 0) then
		DebugLog(string.format("确认按钮点击失败：BattleId无效(%s)，直接隐藏UI", tostring(currentBattleId)))
		HideVictoryUI()
		return
	end

    DebugLog(string.format("玩家点击确认按钮，BattleId: %d (isCampaign: %s)", currentBattleId, tostring(isCampaign)))

    -- 发送确认事件到服务器
    local success, err = pcall(function()
        victoryConfirmEvent:FireServer(currentBattleId)
    end)

    if success then
        DebugLog("已发送VictoryConfirm事件到服务器")
        -- Unlock camera/movement after confirm
        if _G.BattleCameraController and _G.BattleCameraController.Stop then
            _G.BattleCameraController.Stop()
        end

        if isCampaign then
            campaignCoinTotal = 0
            campaignVipBonusTotal = 0
        else
            battleCoinTotal = 0
            battleVipBonusTotal = 0
        end

        -- 立即隐藏UI（无延迟）
        HideVictoryUI()
    else
        DebugLog("发送VictoryConfirm事件失败:", err)
    end
end

--[[
处理复活按钮点击
]]
local function OnReviveButtonClick()
    if revivePromptInProgress then
        return
    end

    if not currentReviveProductId then
        local tipsSystem = _G.TipsSystem
        if tipsSystem and tipsSystem.ShowError then
            tipsSystem.ShowError("复活商品未配置")
        end
        return
    end

    revivePromptInProgress = true
    local success, err = pcall(function()
        MarketplaceService:PromptProductPurchase(player, currentReviveProductId)
    end)

    if not success then
        revivePromptInProgress = false
        local tipsSystem = _G.TipsSystem
        if tipsSystem and tipsSystem.ShowError then
            tipsSystem.ShowError("复活购买失败")
        end
        DebugLog("Revive Prompt失败:", err)
    end
end

--[[
初始化事件连接
]]
local function Initialize()
    DebugLog("初始化VictoryUIController")

    -- 初始化UI元素
    if not InitializeUI() then
        DebugLog("❌ UI初始化失败，将在首次使用时重试")
        -- 不直接返回false，允许事件连接，稍后重试UI初始化
    else
        uiInitialized = true

        -- 初始状态：隐藏所有UI
        if effectFrame then effectFrame.Visible = false end
        if informationFrame then informationFrame.Visible = false end
        if bgFrame then bgFrame.Visible = false end

        DebugLog("✅ UI元素初始化完成")
    end

    -- 连接战役状态更新
    local campaignEvents = events:FindFirstChild("CampaignEvents")
    if campaignEvents then
        local campaignStateUpdate = campaignEvents:FindFirstChild("CampaignStateUpdate")
        if not campaignStateUpdate then
            campaignStateUpdate = campaignEvents:WaitForChild("CampaignStateUpdate", 5)
        end

        if campaignStateUpdate then
            campaignStateUpdate.OnClientEvent:Connect(function(state, stageNum, chapter, totalStagesInChapter)
                if chapter then
                    lastCampaignChapter = chapter
                end

                if totalStagesInChapter then
                    lastCampaignTotalStages = totalStagesInChapter
                end

                if stageNum then
                    lastCampaignStage = stageNum
                end

                if state == "Preparing" then
                    campaignCoinTotal = 0
                    campaignVipBonusTotal = 0
                    isCampaignActive = true
                elseif state == "Idle" or state == "Cleanup" then
                    isCampaignActive = false
                    campaignCoinTotal = 0
                    campaignVipBonusTotal = 0
                else
                    isCampaignActive = true
                end
            end)
        end
    end

    -- 连接战斗状态更新（非战役）
    if battleStateUpdateEvent then
        battleStateUpdateEvent.OnClientEvent:Connect(function(battleId, state)
            if isCampaignActive then
                return
            end

            if state == "Fighting" then
                battleCoinTotal = 0
                battleVipBonusTotal = 0
                isBattleActive = true
            elseif state == "Finished" then
                isBattleActive = false
            end
        end)
    end

    -- 监听战斗金币收益
    local function ConnectCoinEarnedEvent(event)
        if not event then
            return
        end

        event.OnClientEvent:Connect(function(amount, vipBonus)
            AddBattleCoins(amount, vipBonus)
        end)
    end

    local coinEarnedEvent = battleEvents:FindFirstChild("CoinEarnedEffect")
    if coinEarnedEvent then
        ConnectCoinEarnedEvent(coinEarnedEvent)
    else
        battleEvents.ChildAdded:Connect(function(child)
            if child.Name == "CoinEarnedEffect" and child:IsA("RemoteEvent") then
                ConnectCoinEarnedEvent(child)
            end
        end)
    end

    -- 连接服务器VictoryPopup事件
    victoryPopupEvent.OnClientEvent:Connect(function(battleId, result, stageNum, extraRewards)
        local success, err = pcall(function()
            -- 战役结算用 battleId=0，允许显示；普通战斗需>0
            local isCampaign = (battleId == 0)
            DebugLog(string.format("收到VictoryPopup事件: BattleId=%s, Result=%s, Stage=%s (isCampaign=%s)",
                tostring(battleId), tostring(result), tostring(stageNum), tostring(isCampaign)))

            if not isCampaign and (type(battleId) ~= "number" or battleId <= 0) then
                DebugLog(string.format("无效的BattleId(%s)，忽略结算界面", tostring(battleId)))
                return
            end

            ShowVictoryUI(battleId, result, stageNum, extraRewards)
        end)

        if not success then
            DebugLog("处理VictoryPopup事件失败:", err)
        end
    end)

    local function ConnectReviveResultEvent(event)
        if reviveResultConnected then
            return
        end

        reviveResultConnected = true
        event.OnClientEvent:Connect(function(success, message)
            revivePromptInProgress = false
            if success then
                HideVictoryUI()
            else
                local tipsSystem = _G.TipsSystem
                if tipsSystem and tipsSystem.ShowError then
                    tipsSystem.ShowError(message or "复活失败")
                end
            end
        end)
    end

    if reviveResultEvent then
        ConnectReviveResultEvent(reviveResultEvent)
    else
        battleEvents.ChildAdded:Connect(function(child)
            if child.Name == "ReviveResult" and child:IsA("RemoteEvent") then
                reviveResultEvent = child
                ConnectReviveResultEvent(child)
            end
        end)
    end

    -- 连接确认按钮点击事件（延迟连接，直到按钮存在）
    local function ConnectConfirmButton()
        if confirmButton then
            confirmButton.MouseButton1Click:Connect(function()
                local success, err = pcall(function()
                    OnConfirmButtonClick()
                end)

                if not success then
                    DebugLog("处理确认按钮点击失败:", err)
                end
            end)
            DebugLog("✅ 确认按钮事件已连接")
            return true
        end
        return false
    end

    local function ConnectReviveButton()
        if reviveButton then
            reviveButton.MouseButton1Click:Connect(function()
                local success, err = pcall(function()
                    OnReviveButtonClick()
                end)

                if not success then
                    DebugLog("处理复活按钮点击失败:", err)
                end
            end)
            DebugLog("✅ 复活按钮事件已连接")
            return true
        end
        return false
    end

    -- 尝试立即连接，如果失败则稍后重试
    if not ConnectConfirmButton() then
        DebugLog("确认按钮暂时不可用，将在UI初始化时重新连接")

        -- 当UI初始化成功时，重新连接按钮事件
        task.spawn(function()
            while not confirmButton do
                task.wait(1)
                if uiInitialized and confirmButton then
                    ConnectConfirmButton()
                    break
                end
            end
        end)
    end

    if not ConnectReviveButton() then
        task.spawn(function()
            while not reviveButton do
                task.wait(1)
                if uiInitialized and reviveButton then
                    ConnectReviveButton()
                    break
                end
            end
        end)
    end

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId)
        if userId ~= player.UserId then
            return
        end
        if currentReviveProductId and productId == currentReviveProductId then
            revivePromptInProgress = false
        end
    end)

    DebugLog("VictoryUIController事件连接完成")
    return true
end

-- 启动初始化
task.spawn(function()
    local success, err = pcall(function()
        local initResult = Initialize()
        if not initResult then
            DebugLog("VictoryUIController初始化失败")
        end
    end)

    if not success then
        DebugLog("VictoryUIController初始化出现异常:", err)
    end
end)

_G.VictoryUIController = _G.VictoryUIController or {}
_G.VictoryUIController.ConfirmCurrent = function()
    if reviveAvailable then
        return
    end
    if currentBattleId == 0 then
        return
    end
    local ok, err = pcall(function()
        OnConfirmButtonClick()
    end)
    if not ok then
        DebugLog("VictoryUIController自动确认失败:", err)
    end
end

DebugLog("VictoryUIController脚本加载完成")

