--[[
脚本名称: TaskDisplay
脚本类型: LocalScript (客户端UI)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/TaskDisplay
版本: V3.3 (任务系统)
职责: 客户端任务UI显示，监听任务进度更新，处理领取奖励
]]

local TaskDisplay = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 玩家引用
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- 引用格式化工具
local FormatHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FormatHelper"))

-- 事件引用
local TaskEvents = nil
local TaskProgressEvent = nil      -- 服务器→客户端：任务进度更新
local TaskCompleteEvent = nil      -- 服务器→客户端：任务完成通知
local ClaimTaskRewardEvent = nil   -- 客户端→服务器：领取任务奖励
local ClaimRewardResultEvent = nil -- 服务器→客户端：领取结果
local CampaignStateUpdateEvent = nil -- 服务器→客户端：战役状态更新

-- UI引用
local TaskGui = nil
local TaskBg = nil           -- StarterGui - Task - Bg
local TaskText = nil         -- Bg - TaskText (任务描述+进度)
local RewardNumber = nil     -- Bg - RewardIconBg - Number (奖励数值)
local RedPoint = nil         -- Bg - RedPoint (红点)
local ClaimButton = nil      -- Bg (点击Bg领取奖励)

-- 状态
local CurrentTaskData = nil
local IsClaimCooldown = false
local IsInBattle = false     -- 是否在战斗中（用于控制UI显示）

-- ==================== 私有函数 ====================

--[[
初始化事件引用
@return boolean - 是否成功
]]
local function InitializeEvents()
    if TaskEvents then
        return true
    end

    local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
    if not eventsFolder then
        warn("[TaskDisplay] Events文件夹未找到")
        return false
    end

    TaskEvents = eventsFolder:WaitForChild("TaskEvents", 10)
    if not TaskEvents then
        warn("[TaskDisplay] TaskEvents文件夹未找到")
        return false
    end

    TaskProgressEvent = TaskEvents:WaitForChild("TaskProgress", 5)
    TaskCompleteEvent = TaskEvents:WaitForChild("TaskComplete", 5)
    ClaimTaskRewardEvent = TaskEvents:WaitForChild("ClaimTaskReward", 5)
    ClaimRewardResultEvent = TaskEvents:WaitForChild("ClaimRewardResult", 5)

    if not (TaskProgressEvent and TaskCompleteEvent and ClaimTaskRewardEvent and ClaimRewardResultEvent) then
        warn("[TaskDisplay] 部分任务事件未找到")
        return false
    end

    return true
end

--[[
初始化UI引用
@return boolean - 是否成功
]]
local function InitializeUI()
    -- 等待Task GUI加载 (根据需求文档V3.3: StarterGui - Task - Bg)
    TaskGui = PlayerGui:WaitForChild("Task", 10)
    if not TaskGui then
        warn("[TaskDisplay] Task ScreenGui未找到")
        return false
    end

    -- 查找任务面板Bg
    TaskBg = TaskGui:FindFirstChild("Bg")
    if not TaskBg then
        warn("[TaskDisplay] Task - Bg未找到，请确保UI已创建")
        return false
    end

    -- 获取UI元素 (根据需求文档V3.3)
    -- TaskText: 任务详情描述，格式为：XXXXX（M/N）
    TaskText = TaskBg:FindFirstChild("TaskText")

    -- RewardIconBg - Number: 金币奖励数值
    local rewardIconBg = TaskBg:FindFirstChild("RewardIconBg")
    if rewardIconBg then
        RewardNumber = rewardIconBg:FindFirstChild("Number")
    end

    -- RedPoint: 红点，任务完成但未领取时显示
    RedPoint = TaskBg:FindFirstChild("RedPoint")

    -- Bg本身作为点击领取区域
    ClaimButton = TaskBg

    -- 验证关键元素
    if not TaskText then
        warn("[TaskDisplay] TaskText未找到")
    end
    if not RewardNumber then
        warn("[TaskDisplay] RewardIconBg/Number未找到")
    end
    if not RedPoint then
        warn("[TaskDisplay] RedPoint未找到")
    end

    return true
end

--[[
更新UI显示
@param taskData table - 任务数据
]]
local function UpdateUI(taskData)
    CurrentTaskData = taskData

    if not TaskBg then
        return
    end

    -- 检查是否全部完成
    if taskData.AllTasksCompleted then
        -- 全部任务完成，隐藏任务界面 (根据需求文档V3.3)
        TaskBg.Visible = false
        return
    end

    -- V3.3.1 Bug修复：即使在战斗中也要更新UI内容（只是不显示）
    -- 这样当战斗结束后，UI会显示最新的进度
    -- 显示任务描述 (格式: XXXXX（M/N）)
    local progress = taskData.CurrentProgress or 0
    local required = taskData.RequiredCount or 1
    local description = taskData.Description or "加载中..."

    if TaskText then
        TaskText.Text = string.format("%s（%d/%d）", description, progress, required)
    end

    -- 显示奖励金币数值（使用大数值格式化）
    if RewardNumber then
        RewardNumber.Text = FormatHelper.FormatCoinsShort(taskData.RewardCoins or 0)
    end

    -- 更新红点状态 (任务完成但未领取时显示)
    if RedPoint then
        if taskData.IsCompleted then
            RedPoint.Visible = true
        else
            RedPoint.Visible = false
        end
    end

    -- 战斗中隐藏任务界面 (根据需求文档V3.3)
    -- 注意：这个判断移到最后，这样UI内容已经更新，只是不显示而已
    if IsInBattle then
        TaskBg.Visible = false
        return
    end

    -- 显示任务界面
    TaskBg.Visible = true
end

--[[
处理任务进度更新
@param taskData table - 任务数据
]]
local function OnTaskProgress(taskData)
    print(string.format(
        "[TaskDisplay] 收到任务进度更新 - 任务ID:%s 进度:%d/%d 完成:%s",
        tostring(taskData.CurrentTaskId),
        taskData.CurrentProgress or 0,
        taskData.RequiredCount or 0,
        tostring(taskData.IsCompleted)
    ))

    UpdateUI(taskData)
end

--[[
处理任务完成通知
@param taskInfo table - 完成的任务信息
]]
local function OnTaskComplete(taskInfo)
    print(string.format(
        "[TaskDisplay] 任务完成！任务ID:%d 奖励:%d金币",
        taskInfo.TaskId,
        taskInfo.RewardCoins
    ))

    -- 显示红点提示玩家领取
    if RedPoint then
        RedPoint.Visible = true
    end
end

--[[
处理领取按钮点击
]]
local function OnClaimButtonClicked()
    -- 检查是否可以领取
    if not CurrentTaskData or not CurrentTaskData.IsCompleted then
        warn("[TaskDisplay] 任务未完成，无法领取")
        return
    end

    -- 防止重复点击
    if IsClaimCooldown then
        return
    end
    IsClaimCooldown = true

    -- 发送领取请求
    if ClaimTaskRewardEvent then
        print("[TaskDisplay] 发送领取奖励请求...")
        ClaimTaskRewardEvent:FireServer()
    end

    -- 冷却时间
    task.delay(1, function()
        IsClaimCooldown = false
    end)
end

--[[
处理领取结果
@param success boolean - 是否成功
@param message string - 结果消息
@param rewardCoins number - 奖励金币（可选）
]]
local function OnClaimRewardResult(success, message, rewardCoins)
    if success then
        print(string.format(
            "[TaskDisplay] 领取成功！%s 获得%d金币",
            message or "",
            rewardCoins or 0
        ))

        -- 可以在这里添加领取成功的动画或音效
    else
        warn(string.format("[TaskDisplay] 领取失败：%s", message or "未知错误"))
    end
end

--[[
处理战役状态更新
@param state string - 战役状态
@param stageNum number - 关卡编号
]]
local function OnCampaignStateUpdate(state, stageNum)
    -- 战斗状态列表（进入这些状态时隐藏任务UI）
    local battleStates = {
        ["Preparing"] = true,
        ["Marching"] = true,
        ["PrepareBattle"] = true,
        ["Fighting"] = true,
        ["StageClear"] = true,
        ["Victory"] = true,
        ["Defeat"] = true,
        ["Cleanup"] = true,
    }

    -- 检查是否进入战斗状态
    local wasInBattle = IsInBattle
    IsInBattle = battleStates[state] == true

    -- 状态变化时更新UI
    if wasInBattle ~= IsInBattle then
        if IsInBattle then
            -- 进入战斗，隐藏任务UI
            if TaskBg then
                TaskBg.Visible = false
            end
            print("[TaskDisplay] 进入战斗，隐藏任务界面")
        else
            -- 退出战斗（回到Idle），如果有未完成任务则显示UI
            if CurrentTaskData and not CurrentTaskData.AllTasksCompleted then
                if TaskBg then
                    TaskBg.Visible = true
                end
                print("[TaskDisplay] 退出战斗，显示任务界面")
            end
        end
    end
end

-- ==================== 公共接口 ====================

--[[
初始化任务显示模块
]]
function TaskDisplay.Initialize()
    print("[TaskDisplay] 开始初始化任务显示模块...")

    -- 初始化事件
    if not InitializeEvents() then
        warn("[TaskDisplay] 事件初始化失败，将在稍后重试")
        task.delay(3, function()
            InitializeEvents()
        end)
    end

    -- 初始化战役状态事件监听
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if eventsFolder then
        local campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
        if campaignEvents then
            CampaignStateUpdateEvent = campaignEvents:FindFirstChild("CampaignStateUpdate")
            if CampaignStateUpdateEvent then
                CampaignStateUpdateEvent.OnClientEvent:Connect(OnCampaignStateUpdate)
                print("[TaskDisplay] ✅ 已绑定CampaignStateUpdate事件")
            end
        end
    end

    -- 初始化UI（稍后执行，等待UI加载）
    task.delay(1, function()
        if not InitializeUI() then
            warn("[TaskDisplay] UI初始化失败")
            return
        end

        -- 绑定事件监听
        if TaskProgressEvent then
            TaskProgressEvent.OnClientEvent:Connect(OnTaskProgress)
        end

        if TaskCompleteEvent then
            TaskCompleteEvent.OnClientEvent:Connect(OnTaskComplete)
        end

        if ClaimRewardResultEvent then
            ClaimRewardResultEvent.OnClientEvent:Connect(OnClaimRewardResult)
        end

        -- 绑定领取按钮点击 (Bg可以是Frame/TextButton/ImageButton)
        if ClaimButton then
            if ClaimButton:IsA("TextButton") or ClaimButton:IsA("ImageButton") then
                ClaimButton.MouseButton1Click:Connect(OnClaimButtonClicked)
            elseif ClaimButton:IsA("Frame") then
                -- Frame不能直接点击，需要查找内部的按钮
                -- 或者创建一个透明按钮覆盖在上面
                local clickDetector = ClaimButton:FindFirstChildOfClass("TextButton") or ClaimButton:FindFirstChildOfClass("ImageButton")
                if clickDetector then
                    clickDetector.MouseButton1Click:Connect(OnClaimButtonClicked)
                else
                    -- 尝试让Frame通过InputBegan响应点击
                    ClaimButton.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            OnClaimButtonClicked()
                        end
                    end)
                end
            end
        end

        print("[TaskDisplay] ✅ 任务显示模块初始化完成")
    end)
end

-- 自动初始化
TaskDisplay.Initialize()

return TaskDisplay
