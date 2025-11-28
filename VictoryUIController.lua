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

-- 调试日志
local function DebugLog(...)
    print("[VictoryUIController]", ...)
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
播放UI显示动画
@param frame Frame - 要显示的UI框架
@param duration number - 动画时长（可选，默认0.3秒）
]]
local function ShowFrameWithAnimation(frame, duration)
    duration = duration or 0.3

    -- 初始状态：透明且缩小
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(0.8, 0, 0.8, 0) -- 稍小一些
    frame.Position = UDim2.new(0.1, 0, 0.1, 0) -- 居中
    frame.Visible = true

    -- 创建淡入和放大动画
    local fadeIn = TweenService:Create(
        frame,
        TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {
            BackgroundTransparency = 0,
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0)
        }
    )

    fadeIn:Play()
    return fadeIn
end

--[[
播放UI隐藏动画
@param frame Frame - 要隐藏的UI框架
@param duration number - 动画时长（可选，默认0.2秒）
]]
local function HideFrameWithAnimation(frame, duration)
    duration = duration or 0.2

    local fadeOut = TweenService:Create(
        frame,
        TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
        {
            BackgroundTransparency = 1,
            Size = UDim2.new(0.8, 0, 0.8, 0),
            Position = UDim2.new(0.1, 0, 0.1, 0)
        }
    )

    fadeOut:Play()

    fadeOut.Completed:Connect(function()
        frame.Visible = false
    end)

    return fadeOut
end

--[[
播放按钮点击效果
@param button GuiButton - 按钮对象
]]
local function PlayButtonClickEffect(button)
    local originalSize = button.Size

    -- 缩小效果
    local shrink = TweenService:Create(
        button,
        TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Size = UDim2.new(originalSize.X.Scale * 0.95, 0, originalSize.Y.Scale * 0.95, 0)}
    )

    -- 恢复效果
    local expand = TweenService:Create(
        button,
        TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Size = originalSize}
    )

    shrink:Play()
    shrink.Completed:Connect(function()
        expand:Play()
    end)
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

    -- 按顺序显示UI元素，创建层次感（移除Back Frame）
    ShowFrameWithAnimation(effectFrame, 0.3)

    task.wait(0.2)
    ShowFrameWithAnimation(informationFrame, 0.4)

    DebugLog("胜利界面显示完成")
end

--[[
隐藏胜利结算界面
]]
local function HideVictoryUI()
    if not isVictoryShowing then
        return
    end

    DebugLog("开始隐藏胜利界面")

    -- 按相反顺序隐藏UI元素（移除Back Frame）
    HideFrameWithAnimation(informationFrame, 0.2)

    task.wait(0.1)
    HideFrameWithAnimation(effectFrame, 0.2)

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

    -- 播放按钮点击效果
    PlayButtonClickEffect(confirmButton)

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

        -- 短暂延迟后隐藏UI
        task.delay(0.3, function()
            HideVictoryUI()
        end)
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

        -- 初始状态：隐藏所有UI（移除Back Frame）
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

