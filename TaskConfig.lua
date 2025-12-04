--[[
脚本名称: TaskConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/TaskConfig
版本: V3.3 (任务系统)
职责: 任务系统配置表，定义所有任务类型、任务列表和奖励
]]

local TaskConfig = {}

-- ==================== 任务类型枚举 ====================
TaskConfig.TaskType = {
    PURCHASE_UNIT = 1,       -- 类型1：购买N次兵种
    PLACE_UNIT = 2,          -- 类型2：将N个兵布置到战场
    PURCHASE_SKILL = 3,      -- 类型3：购买N次技能
    COMPLETE_BATTLE = 4,     -- 类型4：完成一场战斗
    COLLECT_IDLE_COIN = 5,   -- 类型5：领取一次挂机金币奖励
    MERGE_LEVEL2_UNIT = 6,   -- 类型6：合成一个2级的指定兵种（需要TargetUnitId参数）
}

-- 任务类型名称映射（用于描述生成）
TaskConfig.TaskTypeName = {
    [1] = "购买兵种",
    [2] = "布置兵种",
    [3] = "购买技能",
    [4] = "完成战斗",
    [5] = "领取挂机奖励",
    [6] = "合成2级兵种",
}

-- ==================== 任务列表配置 ====================
-- 任务是线性的，按顺序完成
-- 每个任务配置包含:
--   TaskId: 任务唯一ID
--   TaskType: 任务类型（对应TaskType枚举）
--   RequiredCount: 完成所需数量（参数N）
--   Description: 任务描述文本
--   RewardCoins: 奖励金币数量
--   Sort: 排序（对应任务顺序，越小越靠前）
--   TargetUnitId: [仅类型6需要] 目标兵种ID，用于指定需要合成的兵种

TaskConfig.Tasks = {
    -- 任务1001: 购买任意一个囚犯
    {
        TaskId = 1001,
        TaskType = TaskConfig.TaskType.PURCHASE_UNIT,
        RequiredCount = 1,
        Description = "购买任意一个囚犯",
        RewardCoins = 100,
        Sort = 1,
    },
    -- 任务1002: 完成一场战斗
    {
        TaskId = 1002,
        TaskType = TaskConfig.TaskType.COMPLETE_BATTLE,
        RequiredCount = 1,
        Description = "完成一场战斗",
        RewardCoins = 100,
        Sort = 2,
    },
    -- 任务1003: 购买任意一个囚犯
    {
        TaskId = 1003,
        TaskType = TaskConfig.TaskType.PURCHASE_UNIT,
        RequiredCount = 1,
        Description = "购买任意一个囚犯",
        RewardCoins = 100,
        Sort = 3,
    },
    -- 任务1004: 完成一场战斗
    {
        TaskId = 1004,
        TaskType = TaskConfig.TaskType.COMPLETE_BATTLE,
        RequiredCount = 1,
        Description = "完成一场战斗",
        RewardCoins = 100,
        Sort = 4,
    },
    -- 任务1005: 将3个囚犯布置到战场中
    {
        TaskId = 1005,
        TaskType = TaskConfig.TaskType.PLACE_UNIT,
        RequiredCount = 3,
        Description = "将3个囚犯布置到战场中",
        RewardCoins = 100,
        Sort = 5,
    },
    -- 任务1006: 完成一场战斗
    {
        TaskId = 1006,
        TaskType = TaskConfig.TaskType.COMPLETE_BATTLE,
        RequiredCount = 1,
        Description = "完成一场战斗",
        RewardCoins = 100,
        Sort = 6,
    },
    -- 任务1007: 购买一次技能
    {
        TaskId = 1007,
        TaskType = TaskConfig.TaskType.PURCHASE_SKILL,
        RequiredCount = 1,
        Description = "购买一次技能",
        RewardCoins = 100,
        Sort = 7,
    },
    -- 任务1008: 购买任意一个囚犯
    {
        TaskId = 1008,
        TaskType = TaskConfig.TaskType.PURCHASE_UNIT,
        RequiredCount = 1,
        Description = "购买任意一个囚犯",
        RewardCoins = 100,
        Sort = 8,
    },
    -- 任务1009: 完成一场战斗
    {
        TaskId = 1009,
        TaskType = TaskConfig.TaskType.COMPLETE_BATTLE,
        RequiredCount = 1,
        Description = "完成一场战斗",
        RewardCoins = 100,
        Sort = 9,
    },
    -- 任务1010: 领取一次挂机奖励
    {
        TaskId = 1010,
        TaskType = TaskConfig.TaskType.COLLECT_IDLE_COIN,
        RequiredCount = 1,
        Description = "领取一次挂机奖励",
        RewardCoins = 100,
        Sort = 10,
    },
    -- 任务1011: 合成一个2级菜鸟
    {
        TaskId = 1011,
        TaskType = TaskConfig.TaskType.MERGE_LEVEL2_UNIT,
        RequiredCount = 1,
        Description = "合成一个2级菜鸟",
        RewardCoins = 100,
        Sort = 11,
        TargetUnitId = "10001",  -- Noob的UnitId（字符串格式）
    },
}

-- ==================== 公共接口 ====================

--[[
根据TaskId获取任务配置
@param taskId number - 任务ID
@return table|nil - 任务配置，不存在返回nil
]]
function TaskConfig.GetTaskById(taskId)
    for _, task in ipairs(TaskConfig.Tasks) do
        if task.TaskId == taskId then
            return task
        end
    end
    return nil
end

--[[
获取第一个任务的ID
@return number - 第一个任务的ID
]]
function TaskConfig.GetFirstTaskId()
    if #TaskConfig.Tasks > 0 then
        -- 按Sort排序，返回最小Sort的TaskId
        local sortedTasks = {}
        for _, task in ipairs(TaskConfig.Tasks) do
            table.insert(sortedTasks, task)
        end
        table.sort(sortedTasks, function(a, b)
            return a.Sort < b.Sort
        end)
        return sortedTasks[1].TaskId
    end
    return nil
end

--[[
获取下一个任务的ID
@param currentTaskId number - 当前任务ID
@return number|nil - 下一个任务ID，如果没有返回nil
]]
function TaskConfig.GetNextTaskId(currentTaskId)
    local currentTask = TaskConfig.GetTaskById(currentTaskId)
    if not currentTask then
        return nil
    end

    -- 查找Sort比当前大的最小的任务
    local nextTask = nil
    local nextSort = math.huge

    for _, task in ipairs(TaskConfig.Tasks) do
        if task.Sort > currentTask.Sort and task.Sort < nextSort then
            nextSort = task.Sort
            nextTask = task
        end
    end

    return nextTask and nextTask.TaskId or nil
end

--[[
检查任务ID是否有效
@param taskId number - 任务ID
@return boolean - 是否有效
]]
function TaskConfig.IsValidTask(taskId)
    return TaskConfig.GetTaskById(taskId) ~= nil
end

--[[
获取所有任务ID列表（按Sort排序）
@return table - 任务ID数组
]]
function TaskConfig.GetAllTaskIds()
    local sortedTasks = {}
    for _, task in ipairs(TaskConfig.Tasks) do
        table.insert(sortedTasks, task)
    end
    table.sort(sortedTasks, function(a, b)
        return a.Sort < b.Sort
    end)

    local taskIds = {}
    for _, task in ipairs(sortedTasks) do
        table.insert(taskIds, task.TaskId)
    end
    return taskIds
end

--[[
获取任务总数
@return number - 任务总数
]]
function TaskConfig.GetTaskCount()
    return #TaskConfig.Tasks
end

--[[
检查是否是最后一个任务
@param taskId number - 任务ID
@return boolean - 是否是最后一个任务
]]
function TaskConfig.IsLastTask(taskId)
    return TaskConfig.GetNextTaskId(taskId) == nil
end

--[[
获取任务类型描述
@param taskType number - 任务类型
@return string - 类型描述
]]
function TaskConfig.GetTaskTypeName(taskType)
    return TaskConfig.TaskTypeName[taskType] or "未知类型"
end

return TaskConfig
