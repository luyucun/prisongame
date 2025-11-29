--[[
脚本名称: HealthBarEventHandler
脚本类型: LocalScript (客户端事件处理器)
脚本位置: StarterPlayer/StarterPlayerScripts/Utils/HealthBarEventHandler

功能描述: V2.3血条系统 - 客户端事件处理器
- 监听服务器发送的血条相关RemoteEvent
- 调用HealthBarController的相应函数
- 处理血量更新、血条挂载/移除事件
]]

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 玩家引用
local player = Players.LocalPlayer

-- 等待HealthBarController模块加载
local HealthBarController = require(player.PlayerScripts:WaitForChild("Utils"):WaitForChild("HealthBarController"))

-- 等待事件文件夹
local events = ReplicatedStorage:WaitForChild("Events")
local battleEvents = events:WaitForChild("BattleEvents")

-- 调试日志（已禁用）
local function debugLog(message)
    -- print("[HealthBarEventHandler] " .. message)
end

--[[
初始化事件监听器
]]
local function initializeEventListeners()
    -- 1. 监听血量更新事件
    local unitHealthUpdateEvent = battleEvents:WaitForChild("UnitHealthUpdate")
    unitHealthUpdateEvent.OnClientEvent:Connect(function(unitModel, currentHP, maxHP)
        if not unitModel or not unitModel.Parent then
            return
        end

        -- 调用HealthBarController更新血量
        HealthBarController.UpdateHealth(unitModel, currentHP, maxHP)

        -- 调试信息（只在血量变化显著时输出，避免刷屏）
        if currentHP <= 0 or currentHP == maxHP then
            debugLog(string.format("血量更新 - %s: %d/%d", unitModel.Name, currentHP, maxHP))
        end
    end)

    -- 2. 监听血条挂载事件（战斗开始）
    local attachHealthBarsEvent = battleEvents:WaitForChild("AttachHealthBars")
    attachHealthBarsEvent.OnClientEvent:Connect(function(unitModels)
        if not unitModels or type(unitModels) ~= "table" then
            warn("[HealthBarEventHandler] AttachHealthBars: 无效的单位列表")
            return
        end

        debugLog(string.format("批量挂载血条，单位数量: %d", #unitModels))

        -- 为每个单位挂载血条
        for _, unitModel in ipairs(unitModels) do
            if unitModel and unitModel.Parent then
                HealthBarController.AttachHealthBar(unitModel)
            end
        end

        debugLog(string.format("血条挂载完成，当前活跃血条数: %d",
            HealthBarController.GetActiveHealthBarCount()))
    end)

    -- 3. 监听血条移除事件（战斗结束）
    local detachHealthBarsEvent = battleEvents:WaitForChild("DetachHealthBars")
    detachHealthBarsEvent.OnClientEvent:Connect(function(unitModels)
        if not unitModels or type(unitModels) ~= "table" then
            warn("[HealthBarEventHandler] DetachHealthBars: 无效的单位列表")
            return
        end

        debugLog(string.format("批量移除血条，单位数量: %d", #unitModels))

        -- 为每个单位移除血条
        for _, unitModel in ipairs(unitModels) do
            if unitModel then -- 不检查Parent，因为单位可能已经移动或隐藏
                HealthBarController.DetachHealthBar(unitModel)
            end
        end

        debugLog(string.format("血条移除完成，当前活跃血条数: %d",
            HealthBarController.GetActiveHealthBarCount()))
    end)

    debugLog("✅ 所有血条事件监听器已初始化")
end

--[[
玩家离开游戏时的清理
]]
local function onPlayerLeaving()
    debugLog("玩家离开，清理所有血条")
    HealthBarController.ClearAllHealthBars()
end

-- 监听玩家离开事件
Players.PlayerRemoving:Connect(function(leavingPlayer)
    if leavingPlayer == player then
        onPlayerLeaving()
    end
end)

-- 初始化
task.spawn(function()
    -- 等待一帧确保所有模块都已加载
    task.wait()

    initializeEventListeners()

    debugLog("HealthBarEventHandler初始化完成")
end)

-- 导出一些调试函数（可选）
local HealthBarEventHandler = {}

function HealthBarEventHandler.GetActiveHealthBarCount()
    return HealthBarController.GetActiveHealthBarCount()
end

function HealthBarEventHandler.ClearAllHealthBars()
    HealthBarController.ClearAllHealthBars()
end

-- 手动测试函数（开发阶段使用）
function HealthBarEventHandler.TestAttachHealthBar(unitModel)
    if unitModel then
        HealthBarController.AttachHealthBar(unitModel)
        debugLog("手动测试 - 挂载血条: " .. unitModel.Name)
    end
end

function HealthBarEventHandler.TestDetachHealthBar(unitModel)
    if unitModel then
        HealthBarController.DetachHealthBar(unitModel)
        debugLog("手动测试 - 移除血条: " .. unitModel.Name)
    end
end

debugLog("HealthBarEventHandler脚本已加载")

return HealthBarEventHandler