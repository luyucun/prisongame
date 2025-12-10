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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 尝试获取UI元素（不使用WaitForChild，避免无限等待）
local victoryGui = playerGui:FindFirstChild("Victory")
local effectFrame = nil
local informationFrame = nil
local confirmButton = nil

-- 获取远程事件
local events = ReplicatedStorage:WaitForChild("Events")
local battleEvents = events:WaitForChild("BattleEvents")
local victoryPopupEvent = battleEvents:WaitForChild("VictoryPopup")
local victoryConfirmEvent = battleEvents:WaitForChild("VictoryConfirm")

-- 本地变量
local currentBattleId = nil
local isVictoryShowing = false
local uiInitialized = false

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

    DebugLog(string.format("显示结算界面 - BattleId: %d, Result: %s, Stage: %d",
        battleId, tostring(result), stageNum))

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

        task.wait(0.9) -- 等待文本动画完成后再延迟0.5秒

        -- 4. Confirm按钮淡入（0.3秒）
        if confirmButton then
            PlayButtonFadeIn(confirmButton, 0.3)
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

    isVictoryShowing = false
    currentBattleId = nil

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

        -- 立即隐藏UI（无延迟）
        HideVictoryUI()
    else
        DebugLog("发送VictoryConfirm事件失败:", err)
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

        DebugLog("✅ UI元素初始化完成")
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

DebugLog("VictoryUIController脚本加载完成")

