--[[
脚本名称: TaskSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/TaskSystem
版本: V3.3 (任务系统)
职责: 服务端任务系统核心逻辑，管理任务进度、完成判定和奖励发放
]]

local TaskSystem = {}

-- 调试配置
local DEBUG_MODE = true

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local TaskConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("TaskConfig"))

-- 延迟加载系统模块（避免循环依赖）
local CurrencySystem = nil
local DataManager = nil
local SoundSystem = nil

-- 事件引用
local TaskEvents = nil
local TaskProgressEvent = nil      -- 服务器→客户端：任务进度更新
local TaskCompleteEvent = nil      -- 服务器→客户端：任务完成通知
local ClaimTaskRewardEvent = nil   -- 客户端→服务器：领取任务奖励
local ClaimRewardResultEvent = nil -- 服务器→客户端：领取结果

-- ==================== 私有辅助函数 ====================

--[[
初始化依赖模块（延迟加载）
@return boolean - 是否成功
]]
local function InitializeDependencies()
    if not CurrencySystem then
        local currencyModule = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
        if currencyModule then
            CurrencySystem = require(currencyModule)
        else
            warn("[TaskSystem] CurrencySystem模块未找到")
            return false
        end
    end

    if not DataManager then
        local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
        if dataModule then
            DataManager = require(dataModule)
        else
            warn("[TaskSystem] DataManager模块未找到")
            return false
        end
    end

    if not SoundSystem then
        local soundModule = ServerScriptService.Systems:FindFirstChild("SoundSystem")
        if soundModule then
            SoundSystem = require(soundModule)
        end
        -- SoundSystem是可选的，不影响任务系统核心功能
    end

    return true
end

--[[
初始化TaskEvents事件（如果不存在则创建）
@return boolean - 是否成功
]]
local function InitializeEvents()
    if TaskEvents then
        return true -- 已初始化
    end

    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if not eventsFolder then
        eventsFolder = Instance.new("Folder")
        eventsFolder.Name = "Events"
        eventsFolder.Parent = ReplicatedStorage
    end

    TaskEvents = eventsFolder:FindFirstChild("TaskEvents")
    if not TaskEvents then
        -- 自动创建TaskEvents文件夹
        TaskEvents = Instance.new("Folder")
        TaskEvents.Name = "TaskEvents"
        TaskEvents.Parent = eventsFolder
        print(string.format("%s [TaskSystem] 自动创建TaskEvents文件夹", GameConfig.LOG_PREFIX))
    end

    -- 创建或获取各个事件
    local function GetOrCreateEvent(name)
        local event = TaskEvents:FindFirstChild(name)
        if not event then
            event = Instance.new("RemoteEvent")
            event.Name = name
            event.Parent = TaskEvents
            print(string.format("%s [TaskSystem] 自动创建事件: %s", GameConfig.LOG_PREFIX, name))
        end
        return event
    end

    TaskProgressEvent = GetOrCreateEvent("TaskProgress")
    TaskCompleteEvent = GetOrCreateEvent("TaskComplete")
    ClaimTaskRewardEvent = GetOrCreateEvent("ClaimTaskReward")
    ClaimRewardResultEvent = GetOrCreateEvent("ClaimRewardResult")

    return true
end

--[[
获取玩家任务数据
@param player Player - 玩家对象
@return table - 任务数据 {CurrentTaskId, CurrentProgress, CompletedTaskIds}
]]
local function GetPlayerTaskData(player)
    -- 确保DataManager已初始化
    if not DataManager then
        if not InitializeDependencies() then
            warn("[TaskSystem] GetPlayerTaskData: DataManager未初始化")
            return nil
        end
    end

    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    -- 确保TaskData字段存在
    if not playerData.TaskData then
        playerData.TaskData = {
            CurrentTaskId = TaskConfig.GetFirstTaskId(),  -- 当前任务ID
            CurrentProgress = 0,                           -- 当前任务进度
            CompletedTaskIds = {},                         -- 已完成的任务ID列表
            AllTasksCompleted = false,                     -- 是否全部任务完成
        }
    end

    -- V3.3修复：确保所有字段存在（向后兼容）
    if playerData.TaskData.CurrentTaskId == nil then
        playerData.TaskData.CurrentTaskId = TaskConfig.GetFirstTaskId()
    end
    if playerData.TaskData.CurrentProgress == nil then
        playerData.TaskData.CurrentProgress = 0
    end
    if playerData.TaskData.CompletedTaskIds == nil then
        playerData.TaskData.CompletedTaskIds = {}
    end
    if playerData.TaskData.AllTasksCompleted == nil then
        playerData.TaskData.AllTasksCompleted = false
    end

    return playerData.TaskData
end

--[[
检查任务是否已完成（达到目标进度）
@param taskData table - 任务数据
@return boolean - 是否完成
]]
local function IsTaskCompleted(taskData)
    if not taskData.CurrentTaskId then
        return false
    end

    local taskConfig = TaskConfig.GetTaskById(taskData.CurrentTaskId)
    if not taskConfig then
        return false
    end

    return taskData.CurrentProgress >= taskConfig.RequiredCount
end

--[[
同步任务数据到客户端
@param player Player - 玩家对象
]]
local function SyncTaskToClient(player)
    if not TaskProgressEvent then
        return
    end

    local taskData = GetPlayerTaskData(player)
    if not taskData then
        return
    end

    local taskConfig = nil
    if taskData.CurrentTaskId then
        taskConfig = TaskConfig.GetTaskById(taskData.CurrentTaskId)
    end

    -- 发送任务数据到客户端
    pcall(function()
        TaskProgressEvent:FireClient(player, {
            CurrentTaskId = taskData.CurrentTaskId,
            CurrentProgress = taskData.CurrentProgress,
            RequiredCount = taskConfig and taskConfig.RequiredCount or 0,
            Description = taskConfig and taskConfig.Description or "",
            RewardCoins = taskConfig and taskConfig.RewardCoins or 0,
            IsCompleted = IsTaskCompleted(taskData),
            AllTasksCompleted = taskData.AllTasksCompleted,
        })
    end)

    if DEBUG_MODE then
        print(string.format(
            "%s [TaskSystem] 同步任务数据 - 玩家:%s 任务ID:%s 进度:%d/%d 完成:%s",
            GameConfig.LOG_PREFIX,
            player.Name,
            tostring(taskData.CurrentTaskId),
            taskData.CurrentProgress,
            taskConfig and taskConfig.RequiredCount or 0,
            tostring(IsTaskCompleted(taskData))
        ))
    end
end

--[[
增加任务进度
@param player Player - 玩家对象
@param taskType number - 任务类型
@param amount number - 增加数量（默认1）
@param extraParams table|nil - 额外参数（用于特定任务类型验证，如 {unitId = "10001", level = 2}）
@return boolean - 是否成功增加（任务类型匹配）
]]
local function AddTaskProgress(player, taskType, amount, extraParams)
    amount = amount or 1

    local taskData = GetPlayerTaskData(player)
    if not taskData then
        return false
    end

    -- 如果所有任务已完成，不处理
    if taskData.AllTasksCompleted then
        return false
    end

    -- 检查当前任务ID是否存在
    local currentTaskId = taskData.CurrentTaskId
    if not currentTaskId then
        return false
    end
    currentTaskId = currentTaskId :: number  -- 类型断言，消除Luau警告

    -- 获取当前任务配置
    local taskConfig = TaskConfig.GetTaskById(currentTaskId)
    if not taskConfig then
        return false
    end

    -- 检查任务类型是否匹配
    if taskConfig.TaskType ~= taskType then
        return false
    end

    -- 对于类型6（合成2级兵种），需要额外验证目标兵种ID
    if taskType == TaskConfig.TaskType.MERGE_LEVEL2_UNIT then
        if not extraParams or not extraParams.unitId or not extraParams.level then
            return false
        end
        -- 检查合成的兵种ID是否匹配任务配置的目标兵种
        if taskConfig.TargetUnitId and tostring(extraParams.unitId) ~= tostring(taskConfig.TargetUnitId) then
            return false
        end
        -- 检查合成后的等级是否为2级
        if extraParams.level ~= 2 then
            return false
        end
    end

    -- 检查任务是否已完成但未领取奖励（此时不应继续增加进度）
    if taskData.CurrentProgress >= taskConfig.RequiredCount then
        return false
    end

    -- 增加进度
    taskData.CurrentProgress = taskData.CurrentProgress + amount

    -- 限制进度不超过目标值
    if taskData.CurrentProgress > taskConfig.RequiredCount then
        taskData.CurrentProgress = taskConfig.RequiredCount
    end

    if DEBUG_MODE then
        print(string.format(
            "%s [TaskSystem] 任务进度增加 - 玩家:%s 任务ID:%d 类型:%s 进度:%d/%d",
            GameConfig.LOG_PREFIX,
            player.Name,
            currentTaskId,
            TaskConfig.GetTaskTypeName(taskType),
            taskData.CurrentProgress,
            taskConfig.RequiredCount
        ))
    end

    -- 检查是否完成
    if taskData.CurrentProgress >= taskConfig.RequiredCount then
        -- 发送任务完成通知
        if TaskCompleteEvent then
            pcall(function()
                TaskCompleteEvent:FireClient(player, {
                    TaskId = currentTaskId,
                    Description = taskConfig.Description,
                    RewardCoins = taskConfig.RewardCoins,
                })
            end)
        end

        if DEBUG_MODE then
            print(string.format(
                "%s [TaskSystem] 任务完成 - 玩家:%s 任务ID:%d 奖励:%d金币",
                GameConfig.LOG_PREFIX,
                player.Name,
                currentTaskId,
                taskConfig.RewardCoins
            ))
        end
    end

    -- 同步到客户端
    SyncTaskToClient(player)

    -- 保存数据
    DataManager.SavePlayerDataThrottled(player)

    return true
end

--[[
处理领取任务奖励请求
@param player Player - 玩家对象
]]
local function OnClaimTaskReward(player)
    local success, errorMsg = pcall(function()
        local taskData = GetPlayerTaskData(player)
        if not taskData then
            if ClaimRewardResultEvent then
                ClaimRewardResultEvent:FireClient(player, false, "无法获取任务数据")
            end
            return
        end

        -- 检查是否有当前任务
        local currentTaskId = taskData.CurrentTaskId
        if not currentTaskId then
            if ClaimRewardResultEvent then
                ClaimRewardResultEvent:FireClient(player, false, "没有进行中的任务")
            end
            return
        end
        currentTaskId = currentTaskId :: number  -- 类型断言，消除Luau警告

        -- 获取任务配置
        local taskConfig = TaskConfig.GetTaskById(currentTaskId)
        if not taskConfig then
            if ClaimRewardResultEvent then
                ClaimRewardResultEvent:FireClient(player, false, "任务配置不存在")
            end
            return
        end

        -- 检查任务是否完成
        if taskData.CurrentProgress < taskConfig.RequiredCount then
            if ClaimRewardResultEvent then
                ClaimRewardResultEvent:FireClient(player, false, "任务尚未完成")
            end
            return
        end

        -- 发放奖励（金币）
        local rewardCoins = taskConfig.RewardCoins
        if CurrencySystem then
            CurrencySystem.AddCoins(player, rewardCoins, "任务奖励: " .. taskConfig.Description)
        end

        -- 播放领取奖励音效
        if SoundSystem then
            SoundSystem.OnClaimTaskReward(player)
        end

        -- 记录已完成的任务
        table.insert(taskData.CompletedTaskIds, currentTaskId)

        if DEBUG_MODE then
            print(string.format(
                "%s [TaskSystem] 领取任务奖励 - 玩家:%s 任务ID:%d 奖励:%d金币",
                GameConfig.LOG_PREFIX,
                player.Name,
                currentTaskId,
                rewardCoins
            ))
        end

        -- 切换到下一个任务
        local nextTaskId = TaskConfig.GetNextTaskId(currentTaskId)
        if nextTaskId then
            -- 有下一个任务
            taskData.CurrentTaskId = nextTaskId
            taskData.CurrentProgress = 0  -- 重置进度
        else
            -- 没有下一个任务，全部完成
            taskData.CurrentTaskId = nil
            taskData.CurrentProgress = 0
            taskData.AllTasksCompleted = true

            if DEBUG_MODE then
                print(string.format(
                    "%s [TaskSystem] 全部任务完成 - 玩家:%s",
                    GameConfig.LOG_PREFIX,
                    player.Name
                ))
            end
        end

        -- 发送领取成功结果
        if ClaimRewardResultEvent then
            ClaimRewardResultEvent:FireClient(player, true, "奖励领取成功", rewardCoins)
        end

        -- 同步新任务到客户端
        SyncTaskToClient(player)

        -- 保存数据
        DataManager.SavePlayerDataThrottled(player, true)  -- 强制立即保存
    end)

    if not success then
        warn("[TaskSystem] OnClaimTaskReward 错误: " .. tostring(errorMsg))
        if ClaimRewardResultEvent then
            pcall(function()
                ClaimRewardResultEvent:FireClient(player, false, "系统错误")
            end)
        end
    end
end

-- ==================== 公共接口 ====================

--[[
初始化任务系统
@return boolean - 是否成功
]]
function TaskSystem.Initialize()
    print(string.format("%s [TaskSystem] 开始初始化任务系统...", GameConfig.LOG_PREFIX))

    -- 1. 初始化依赖模块
    if not InitializeDependencies() then
        warn("[TaskSystem] 依赖模块初始化失败")
        return false
    end

    -- 2. 初始化事件
    if not InitializeEvents() then
        warn("[TaskSystem] 事件初始化失败")
        return false
    end

    -- 3. 绑定事件处理
    local bindSuccess, bindError = pcall(function()
        ClaimTaskRewardEvent.OnServerEvent:Connect(OnClaimTaskReward)
    end)

    if not bindSuccess then
        warn("[TaskSystem] 事件绑定失败: " .. tostring(bindError))
        return false
    end

    print(string.format("%s [TaskSystem] ✅ 任务系统初始化完成", GameConfig.LOG_PREFIX))
    return true
end

--[[
初始化玩家任务数据（在玩家进入游戏时调用）
@param player Player - 玩家对象
]]
function TaskSystem.InitializePlayerTask(player)
    local success, err = pcall(function()
        local taskData = GetPlayerTaskData(player)
        if not taskData then
            warn(string.format("[TaskSystem] 初始化玩家任务失败: %s", player.Name))
            return
        end

        -- V3.3: 检查是否有新任务（运营更新后可能添加新任务）
        -- 条件：全部任务已完成 或 当前任务ID为nil
        if taskData.AllTasksCompleted or taskData.CurrentTaskId == nil then
            -- 检查是否有未完成的新任务
            local allTaskIds = TaskConfig.GetAllTaskIds()
            local foundNewTask = false

            for _, taskId in ipairs(allTaskIds) do
                local isCompleted = false
                for _, completedId in ipairs(taskData.CompletedTaskIds or {}) do
                    if completedId == taskId then
                        isCompleted = true
                        break
                    end
                end

                if not isCompleted then
                    -- 找到未完成的任务，重新激活任务系统
                    taskData.CurrentTaskId = taskId
                    taskData.CurrentProgress = 0
                    taskData.AllTasksCompleted = false
                    foundNewTask = true

                    if DEBUG_MODE then
                        print(string.format(
                            "%s [TaskSystem] 发现新任务 - 玩家:%s 任务ID:%d",
                            GameConfig.LOG_PREFIX,
                            player.Name,
                            taskId
                        ))
                    end
                    break
                end
            end

            -- 如果没有找到新任务，确保状态正确
            if not foundNewTask then
                taskData.AllTasksCompleted = true
                taskData.CurrentTaskId = nil
            end
        end

        -- 同步到客户端
        SyncTaskToClient(player)

        if DEBUG_MODE then
            print(string.format(
                "%s [TaskSystem] 玩家任务初始化完成 - 玩家:%s 当前任务:%s 进度:%d 全部完成:%s",
                GameConfig.LOG_PREFIX,
                player.Name,
                tostring(taskData.CurrentTaskId),
                taskData.CurrentProgress,
                tostring(taskData.AllTasksCompleted)
            ))
        end
    end)

    if not success then
        warn("[TaskSystem] InitializePlayerTask 错误: " .. tostring(err))
    end
end

--[[
玩家购买兵种时调用（任务类型1）
@param player Player - 玩家对象
@param unitId string - 购买的兵种ID（可选，用于日志）
]]
function TaskSystem.OnPurchaseUnit(player, unitId)
    local success, err = pcall(function()
        AddTaskProgress(player, TaskConfig.TaskType.PURCHASE_UNIT, 1)
    end)
    if not success then
        warn("[TaskSystem] OnPurchaseUnit 错误: " .. tostring(err))
    end
end

--[[
玩家布置兵种到战场时调用（任务类型2）
@param player Player - 玩家对象
@param unitId string - 布置的兵种ID（可选，用于日志）
]]
function TaskSystem.OnPlaceUnit(player, unitId)
    local success, err = pcall(function()
        AddTaskProgress(player, TaskConfig.TaskType.PLACE_UNIT, 1)
    end)
    if not success then
        warn("[TaskSystem] OnPlaceUnit 错误: " .. tostring(err))
    end
end

--[[
玩家购买技能时调用（任务类型3）
@param player Player - 玩家对象
@param skillId number - 购买的技能ID（可选，用于日志）
]]
function TaskSystem.OnPurchaseSkill(player, skillId)
    local success, err = pcall(function()
        AddTaskProgress(player, TaskConfig.TaskType.PURCHASE_SKILL, 1)
    end)
    if not success then
        warn("[TaskSystem] OnPurchaseSkill 错误: " .. tostring(err))
    end
end

--[[
玩家完成战斗时调用（任务类型4）
点击attack后到弹出结算界面回到基地算完成一场战斗
@param player Player - 玩家对象
]]
function TaskSystem.OnCompleteBattle(player)
    local success, err = pcall(function()
        AddTaskProgress(player, TaskConfig.TaskType.COMPLETE_BATTLE, 1)
    end)
    if not success then
        warn("[TaskSystem] OnCompleteBattle 错误: " .. tostring(err))
    end
end

--[[
玩家领取挂机金币时调用（任务类型5）
@param player Player - 玩家对象
]]
function TaskSystem.OnCollectIdleCoin(player)
    local success, err = pcall(function()
        AddTaskProgress(player, TaskConfig.TaskType.COLLECT_IDLE_COIN, 1)
    end)
    if not success then
        warn("[TaskSystem] OnCollectIdleCoin 错误: " .. tostring(err))
    end
end

--[[
玩家合成兵种时调用（任务类型6）
当玩家合成出一个2级的指定兵种时触发
@param player Player - 玩家对象
@param unitId string - 合成后的兵种ID
@param newLevel number - 合成后的等级
]]
function TaskSystem.OnMergeLevel2Unit(player, unitId, newLevel)
    local success, err = pcall(function()
        -- 传递额外参数用于验证
        AddTaskProgress(player, TaskConfig.TaskType.MERGE_LEVEL2_UNIT, 1, {
            unitId = unitId,
            level = newLevel,
        })
    end)
    if not success then
        warn("[TaskSystem] OnMergeLevel2Unit 错误: " .. tostring(err))
    end
end

--[[
同步玩家任务数据到客户端（供其他系统调用）
@param player Player - 玩家对象
]]
function TaskSystem.SyncTaskToClient(player)
    SyncTaskToClient(player)
end

--[[
获取玩家当前任务信息（供其他系统查询）
@param player Player - 玩家对象
@return table|nil - 任务信息 {CurrentTaskId, CurrentProgress, RequiredCount, IsCompleted, AllTasksCompleted}
]]
function TaskSystem.GetPlayerTaskInfo(player)
    local taskData = GetPlayerTaskData(player)
    if not taskData then
        return nil
    end

    local taskConfig = nil
    if taskData.CurrentTaskId then
        taskConfig = TaskConfig.GetTaskById(taskData.CurrentTaskId)
    end

    return {
        CurrentTaskId = taskData.CurrentTaskId,
        CurrentProgress = taskData.CurrentProgress,
        RequiredCount = taskConfig and taskConfig.RequiredCount or 0,
        Description = taskConfig and taskConfig.Description or "",
        RewardCoins = taskConfig and taskConfig.RewardCoins or 0,
        IsCompleted = IsTaskCompleted(taskData),
        AllTasksCompleted = taskData.AllTasksCompleted,
    }
end

--[[
检查玩家是否有未完成的任务（用于UI显示控制）
@param player Player - 玩家对象
@return boolean - 是否有未完成任务
]]
function TaskSystem.HasPendingTask(player)
    local taskData = GetPlayerTaskData(player)
    if not taskData then
        return false
    end

    return not taskData.AllTasksCompleted and taskData.CurrentTaskId ~= nil
end

return TaskSystem
