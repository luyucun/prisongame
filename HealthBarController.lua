--[[
脚本名称: HealthBarController
脚本类型: ModuleScript (客户端工具类)
脚本位置: StarterPlayer/StarterPlayerScripts/Utils/HealthBarController

功能描述: V2.3血条系统 - 客户端血条显示管理
- 战斗时隐藏等级显示，挂载血条
- 根据血量实时更新血条
- 战斗结束/复活时恢复等级显示，移除血条
]]

local HealthBarController = {}

-- 服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 玩家引用
local player = Players.LocalPlayer

-- 血条缓存：unitModel -> healthBar BillboardGui
local healthBarCache = {}
-- Humanoid连接缓存：unitModel -> connection
local healthConnections = {}

-- 配置
local HEALTH_BAR_TEMPLATE_PATH = "HpTemplate"
local MAX_HEALTH_SCALE = 0.998 -- 满血时的Scale值

-- 调试日志（已禁用）
local function debugLog(message)
    -- print("[HealthBarController] " .. message)
end

--[[
根据Team属性为血条应用颜色
@param unitModel: Model - 单位模型
@param healthBar: BillboardGui - 血条实例
@return boolean - 是否成功应用颜色
]]
local function ApplyTeamColor(unitModel, healthBar)
    if not healthBar or not healthBar.Parent then
        return false
    end

    local team = unitModel:GetAttribute("Team")
    if not team then
        -- 还没有设置Team属性，跳过
        return false
    end

    -- 查找血条结构
    local bg = healthBar:FindFirstChild("Bg")
    if not bg then
        warn("[HealthBarController] ApplyTeamColor: 血条缺少Bg组件 - " .. unitModel.Name)
        return false
    end

    local progressBar = bg:FindFirstChild("Hpprogressbar")
    if not progressBar then
        warn("[HealthBarController] ApplyTeamColor: 血条缺少Hpprogressbar组件 - " .. unitModel.Name)
        return false
    end

    -- V2.5新增：根据Team属性设置血条颜色
    if team == "Defense" then
        -- 敌方血条为红色
        progressBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        debugLog("应用敌方血条颜色为红色 - " .. unitModel.Name)
    else
        -- 我方保持默认色（可选：显式设置为其他颜色）
        debugLog("应用我方血条颜色（默认） - " .. unitModel.Name)
    end

    return true
end

--[[
为指定单位模型挂载血条
@param unitModel: Model - 需要挂载血条的单位模型
]]
function HealthBarController.AttachHealthBar(unitModel)
    if not unitModel or not unitModel.Parent then
        warn("[HealthBarController] AttachHealthBar: unitModel无效或已被销毁")
        return
    end

    -- 检查Head部件
    local head = unitModel:FindFirstChild("Head")
    if not head then
        warn("[HealthBarController] AttachHealthBar: 未找到Head部件 - " .. unitModel.Name)
        return
    end

    -- 检查是否已有血条，避免重复挂载
    if healthBarCache[unitModel] then
        debugLog("血条已存在，尝试重新着色 - " .. unitModel.Name)
        -- V2.5修复：已存在血条时，尝试重新应用Team颜色（可能Team属性刚设置）
        local healthBar = healthBarCache[unitModel]
        if ApplyTeamColor(unitModel, healthBar) then
            debugLog("血条重着色成功 - " .. unitModel.Name)
        else
            debugLog("血条重着色跳过（Team属性未设置） - " .. unitModel.Name)
        end
        return
    end

    -- 获取血条模板
    local hpTemplate = ReplicatedStorage:FindFirstChild(HEALTH_BAR_TEMPLATE_PATH)
    if not hpTemplate then
        warn("[HealthBarController] AttachHealthBar: 未找到HpTemplate模板")
        return
    end

    -- 复制血条模板
    local healthBar = hpTemplate:Clone()
    healthBar.Name = "HealthBar"
    healthBar.Parent = head
    healthBar.Enabled = true

    -- 缓存血条
    healthBarCache[unitModel] = healthBar

    -- V2.5新增：应用Team颜色（如果Team属性已设置）
    if not ApplyTeamColor(unitModel, healthBar) then
        -- Team属性还未设置，这是正常的（会在StartBattle前后设置）
        debugLog("血条已挂载，等待Team属性设置 - " .. unitModel.Name)
    end

    -- 隐藏原等级显示
    local levelGui = head:FindFirstChild("BillboardGui")
    if levelGui then
        levelGui.Enabled = false
        debugLog("隐藏等级显示 - " .. unitModel.Name)
    end

    -- 获取Humanoid，设置本地血量监听
    local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
    if humanoid then
        -- 监听血量变化（方案B：本地监听）
        local connection = humanoid.HealthChanged:Connect(function(health)
            HealthBarController.UpdateHealth(unitModel, health, humanoid.MaxHealth)
        end)
        healthConnections[unitModel] = connection

        -- 初始化血量显示
        HealthBarController.UpdateHealth(unitModel, humanoid.Health, humanoid.MaxHealth)
    end

    -- 监听模型销毁，自动清理
    local ancestryConnection
    ancestryConnection = unitModel.AncestryChanged:Connect(function()
        if not unitModel.Parent then
            debugLog("模型被销毁，自动清理血条 - " .. unitModel.Name)
            HealthBarController.DetachHealthBar(unitModel)
            if ancestryConnection then
                ancestryConnection:Disconnect()
            end
        end
    end)

    debugLog("成功挂载血条 - " .. unitModel.Name)
end

--[[
更新指定单位的血量显示
@param unitModel: Model - 单位模型
@param currentHP: number - 当前血量
@param maxHP: number - 最大血量
]]
function HealthBarController.UpdateHealth(unitModel, currentHP, maxHP)
    if not unitModel or not unitModel.Parent then
        return
    end

    -- 获取已挂载的血条
    local healthBar = healthBarCache[unitModel]
    if not healthBar or not healthBar.Parent then
        -- 血条不存在，可能已被清理
        return
    end

    -- V2.9.3新增：血量归零时立即隐藏血条（死亡时）
    if currentHP <= 0 then
        healthBar.Enabled = false
        debugLog(string.format("单位死亡，隐藏血条 - %s", unitModel.Name))
        return
    end

    -- 检查血条结构：Bg/Hpprogressbar
    local bg = healthBar:FindFirstChild("Bg")
    if not bg then
        warn("[HealthBarController] UpdateHealth: 血条缺少Bg组件 - " .. unitModel.Name)
        return
    end

    local progressBar = bg:FindFirstChild("Hpprogressbar")
    if not progressBar then
        warn("[HealthBarController] UpdateHealth: 血条缺少Hpprogressbar组件 - " .. unitModel.Name)
        return
    end

    -- 计算血量比例
    local ratio = 0
    if maxHP > 0 then
        ratio = currentHP / maxHP
    end

    -- 更新血条宽度：0到0.998之间
    local clampedRatio = math.clamp(ratio * MAX_HEALTH_SCALE, 0, MAX_HEALTH_SCALE)
    progressBar.Size = UDim2.new(clampedRatio, 0, 1, 0)
end

--[[
移除指定单位的血条，恢复等级显示
@param unitModel: Model - 单位模型
]]
function HealthBarController.DetachHealthBar(unitModel)
    if not unitModel then
        return
    end

    -- 清理血条
    local healthBar = healthBarCache[unitModel]
    if healthBar then
        healthBar:Destroy()
        healthBarCache[unitModel] = nil
        debugLog("移除血条 - " .. unitModel.Name)
    end

    -- 清理血量监听连接
    local connection = healthConnections[unitModel]
    if connection then
        connection:Disconnect()
        healthConnections[unitModel] = nil
    end

    -- 恢复等级显示
    local head = unitModel:FindFirstChild("Head")
    if head then
        local levelGui = head:FindFirstChild("BillboardGui")
        if levelGui then
            levelGui.Enabled = true
            debugLog("恢复等级显示 - " .. unitModel.Name)
        end
    end
end

--[[
批量为多个单位挂载血条（战斗开始时使用）
@param unitModels: table - 单位模型数组
]]
function HealthBarController.AttachHealthBarsForBattle(unitModels)
    debugLog("批量挂载血条，单位数量: " .. #unitModels)
    for _, unitModel in ipairs(unitModels) do
        HealthBarController.AttachHealthBar(unitModel)
    end
end

--[[
批量移除血条（战斗结束时使用）
@param unitModels: table - 单位模型数组
]]
function HealthBarController.DetachHealthBarsAfterBattle(unitModels)
    debugLog("批量移除血条，单位数量: " .. #unitModels)
    for _, unitModel in ipairs(unitModels) do
        HealthBarController.DetachHealthBar(unitModel)
    end
end

--[[
清理所有血条缓存（用于清理或重置）
]]
function HealthBarController.ClearAllHealthBars()
    debugLog("清理所有血条缓存")
    for unitModel, _ in pairs(healthBarCache) do
        HealthBarController.DetachHealthBar(unitModel)
    end
end

--[[
重新为血条应用Team颜色（战斗开始后Team属性设置完成时调用）
@param unitModel: Model - 单位模型
@return boolean - 是否成功应用颜色
]]
function HealthBarController.ReapplyTeamColor(unitModel)
    local healthBar = healthBarCache[unitModel]
    if not healthBar then
        debugLog("重新着色失败：血条不存在 - " .. unitModel.Name)
        return false
    end

    local success = ApplyTeamColor(unitModel, healthBar)
    if success then
        debugLog("✅ V2.5修复：血条重新着色成功 - " .. unitModel.Name)
    else
        debugLog("血条重新着色失败（可能Team属性未设置） - " .. unitModel.Name)
    end
    return success
end

--[[
批量重新着色血条（战斗开始时Team属性设置后调用）
@param unitModels: table - 单位模型数组
]]
function HealthBarController.ReapplyTeamColorsForBattle(unitModels)
    debugLog("批量重新着色血条，单位数量: " .. #unitModels)
    for _, unitModel in ipairs(unitModels) do
        HealthBarController.ReapplyTeamColor(unitModel)
    end
end

--[[
获取当前血条数量（调试用）
]]
function HealthBarController.GetActiveHealthBarCount()
    local count = 0
    for _ in pairs(healthBarCache) do
        count = count + 1
    end
    return count
end

debugLog("HealthBarController模块已加载")

-- V2.5修复：初始化ReapplyTeamColors事件监听
local function InitializeTeamColorEvent()
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if eventsFolder then
        local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
        if battleEventsFolder then
            local reapplyTeamColorsEvent = battleEventsFolder:FindFirstChild("ReapplyTeamColors")
            if reapplyTeamColorsEvent then
                reapplyTeamColorsEvent.OnClientEvent:Connect(function(unitModels)
                    debugLog("✅ 收到重新着色请求，单位数量: " .. #unitModels)
                    HealthBarController.ReapplyTeamColorsForBattle(unitModels)
                end)
                debugLog("✅ ReapplyTeamColors事件监听已初始化")
            else
                debugLog("⚠️ ReapplyTeamColors事件不存在，客户端将依赖AttachHealthBar自动着色")
            end
        end
    end
end

-- 在模块加载时初始化事件监听
InitializeTeamColorEvent()

return HealthBarController