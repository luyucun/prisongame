--[[
脚本名称: CoinNumShowController
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/CoinNumShowController.lua
版本: V3.4.1

功能描述:
- 监听战斗中金币获取事件
- 在屏幕中央区域显示金币获取的抛洒烟花效果
- 金币数字从中心抛出，做抛物线运动后消失
- 每次获取金币都会触发一次烟花效果

依赖:
- ReplicatedStorage/CoinNumShow/CoinNumShow (TextLabel模板)
- ReplicatedStorage/Events/BattleEvents/CoinEarnedEffect (RemoteEvent)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- 调试模式
local DEBUG_MODE = false
local LOG_PREFIX = "[CoinNumShowController]"

-- ==================== 配置参数 ====================
local Config = {
    -- 抛洒区域配置（屏幕中央区域）
    SpawnAreaCenter = UDim2.new(0.5, 0, 0.4, 0),  -- 屏幕中心偏上
    SpawnAreaSize = Vector2.new(300, 150),         -- 随机生成范围（像素）- 扩大范围

    -- 抛物线运动配置
    InitialVelocityX = {Min = -200, Max = 200},    -- 初始X方向速度范围（像素/秒）- 扩大
    InitialVelocityY = {Min = -250, Max = -120},   -- 初始Y方向速度范围（负值=向上）
    Gravity = 400,                                   -- 重力加速度（像素/秒^2）

    -- 动画配置
    Duration = 1.5,                                 -- 总动画时长（秒）
    FadeStartTime = 1.0,                            -- 开始淡出的时间点（秒）
    ScaleStart = 1.0,                               -- 初始缩放
    ScaleMax = 1.5,                                 -- 最大缩放
    ScalePeakTime = 0.2,                            -- 达到最大缩放的时间点（秒）

    -- 视觉配置
    TextColor = Color3.fromRGB(255, 215, 0),       -- 金色
    StrokeColor = Color3.fromRGB(0, 0, 0),         -- 黑色描边
    StrokeTransparency = 0,                         -- 描边透明度
    FontSize = 32,                                  -- 字体大小
    Font = Enum.Font.GothamBold,                   -- 字体
}

-- ==================== 私有变量 ====================
local screenGui = nil
local coinNumShowTemplate = nil
local activeLabels = {}  -- 存储活跃的金币标签 {label, startTime, velX, velY, startPos}

-- ==================== 私有函数 ====================

--[[
输出调试日志
]]
local function DebugLog(...)
    if DEBUG_MODE then
        print(LOG_PREFIX, ...)
    end
end

--[[
获取或创建ScreenGui
@return ScreenGui
]]
local function GetOrCreateScreenGui()
    if screenGui and screenGui.Parent then
        return screenGui
    end

    -- 检查是否已存在
    screenGui = PlayerGui:FindFirstChild("CoinNumShowGui")
    if screenGui then
        return screenGui
    end

    -- 创建新的ScreenGui
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CoinNumShowGui"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100  -- 确保在最上层
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = PlayerGui

    DebugLog("创建ScreenGui成功")
    return screenGui
end

--[[
获取金币显示模板
@return TextLabel|nil
]]
local function GetCoinNumShowTemplate()
    if coinNumShowTemplate then
        return coinNumShowTemplate
    end

    -- 从ReplicatedStorage获取模板
    local coinNumShowFolder = ReplicatedStorage:FindFirstChild("CoinNumShow")
    if coinNumShowFolder then
        coinNumShowTemplate = coinNumShowFolder:FindFirstChild("CoinNumShow")
        if coinNumShowTemplate then
            DebugLog("找到金币显示模板")
            return coinNumShowTemplate
        end
    end

    -- 如果找不到模板，创建一个默认的
    DebugLog("未找到模板，创建默认金币显示模板")
    coinNumShowTemplate = Instance.new("TextLabel")
    coinNumShowTemplate.Name = "CoinNumShowDefault"
    coinNumShowTemplate.BackgroundTransparency = 1
    coinNumShowTemplate.Size = UDim2.new(0, 100, 0, 40)
    coinNumShowTemplate.Font = Config.Font
    coinNumShowTemplate.TextSize = Config.FontSize
    coinNumShowTemplate.TextColor3 = Config.TextColor
    coinNumShowTemplate.TextStrokeColor3 = Config.StrokeColor
    coinNumShowTemplate.TextStrokeTransparency = Config.StrokeTransparency
    coinNumShowTemplate.TextXAlignment = Enum.TextXAlignment.Center
    coinNumShowTemplate.TextYAlignment = Enum.TextYAlignment.Center
    coinNumShowTemplate.Visible = false

    return coinNumShowTemplate
end

--[[
创建一个金币显示标签
@param amount number - 金币数量
@return TextLabel
]]
local function CreateCoinLabel(amount)
    local template = GetCoinNumShowTemplate()
    if not template then
        return nil
    end

    local gui = GetOrCreateScreenGui()
    if not gui then
        return nil
    end

    -- 克隆模板
    local label = template:Clone()
    label.Name = "CoinEarned_" .. tostring(os.clock())
    label.Text = "+" .. tostring(amount) .. "$"
    label.Visible = true
    label.TextTransparency = 0

    -- 强制设置所有视觉属性，确保可见
    label.BackgroundTransparency = 1
    label.TextColor3 = Config.TextColor
    label.TextStrokeColor3 = Config.StrokeColor
    label.TextStrokeTransparency = 0
    label.Font = Config.Font
    label.TextScaled = false
    label.TextSize = Config.FontSize
    label.ZIndex = 100

    -- 如果模板没有描边，添加UIStroke
    local stroke = label:FindFirstChildOfClass("UIStroke")
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Color = Config.StrokeColor
        stroke.Thickness = 2
        stroke.Transparency = 0
        stroke.Parent = label
    else
        stroke.Transparency = 0
        stroke.Thickness = 2
    end

    -- 设置初始位置（屏幕中央区域随机位置）
    local screenSize = gui.AbsoluteSize
    local centerX = screenSize.X * Config.SpawnAreaCenter.X.Scale + Config.SpawnAreaCenter.X.Offset
    local centerY = screenSize.Y * Config.SpawnAreaCenter.Y.Scale + Config.SpawnAreaCenter.Y.Offset

    -- 使用math.floor确保random参数为整数
    local halfWidth = math.floor(Config.SpawnAreaSize.X / 2)
    local halfHeight = math.floor(Config.SpawnAreaSize.Y / 2)
    local randomX = centerX + math.random(-halfWidth, halfWidth)
    local randomY = centerY + math.random(-halfHeight, halfHeight)

    label.Position = UDim2.new(0, randomX, 0, randomY)
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Size = UDim2.new(0, 150, 0, 60)
    label.TextSize = Config.FontSize

    label.Parent = gui

    return label, Vector2.new(randomX, randomY)
end

--[[
开始金币抛洒动画
@param amount number - 金币数量
]]
local function PlayCoinEffect(amount)
    local label, startPos = CreateCoinLabel(amount)
    if not label or not startPos then
        return
    end

    -- 随机初始速度
    local velX = math.random(Config.InitialVelocityX.Min, Config.InitialVelocityX.Max)
    local velY = math.random(Config.InitialVelocityY.Min, Config.InitialVelocityY.Max)

    -- 存储到活跃列表
    table.insert(activeLabels, {
        label = label,
        startTime = os.clock(),
        velX = velX,
        velY = velY,
        startPos = startPos,
    })

    DebugLog(string.format("开始金币动画: velX=%.1f, velY=%.1f", velX, velY))
end

--[[
更新所有活跃的金币标签
]]
local function UpdateActiveLabels()
    local currentTime = os.clock()
    local toRemove = {}

    for i, data in ipairs(activeLabels) do
        local elapsed = currentTime - data.startTime

        -- 检查是否超时
        if elapsed >= Config.Duration then
            table.insert(toRemove, i)
            if data.label and data.label.Parent then
                data.label:Destroy()
            end
        else
            -- 计算抛物线位置
            -- x = x0 + vx * t
            -- y = y0 + vy * t + 0.5 * g * t^2
            local newX = data.startPos.X + data.velX * elapsed
            local newY = data.startPos.Y + data.velY * elapsed + 0.5 * Config.Gravity * elapsed * elapsed

            if data.label and data.label.Parent then
                data.label.Position = UDim2.new(0, newX, 0, newY)

                -- 计算缩放
                local scale = Config.ScaleStart
                if elapsed < Config.ScalePeakTime then
                    -- 放大阶段
                    local t = elapsed / Config.ScalePeakTime
                    scale = Config.ScaleStart + (Config.ScaleMax - Config.ScaleStart) * t
                else
                    -- 缩小阶段
                    local t = (elapsed - Config.ScalePeakTime) / (Config.Duration - Config.ScalePeakTime)
                    scale = Config.ScaleMax - (Config.ScaleMax - Config.ScaleStart) * t
                end
                data.label.Size = UDim2.new(0, 150 * scale, 0, 60 * scale)
                data.label.TextSize = Config.FontSize * scale

                -- 计算透明度（淡出）
                if elapsed > Config.FadeStartTime then
                    local fadeProgress = (elapsed - Config.FadeStartTime) / (Config.Duration - Config.FadeStartTime)
                    data.label.TextTransparency = fadeProgress
                    local stroke = data.label:FindFirstChildOfClass("UIStroke")
                    if stroke then
                        stroke.Transparency = fadeProgress
                    end
                end
            end
        end
    end

    -- 从后往前删除（避免索引错乱）
    for i = #toRemove, 1, -1 do
        table.remove(activeLabels, toRemove[i])
    end
end

-- ==================== 事件监听 ====================

--[[
监听金币获取事件
@param amount number - 获取的金币数量
]]
local function OnCoinEarned(amount)
    if not amount or type(amount) ~= "number" or amount <= 0 then
        return
    end
    PlayCoinEffect(amount)
end

-- ==================== 初始化 ====================

local function Initialize()
    -- 获取事件
    local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
    if not eventsFolder then
        return false
    end

    local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
    if not battleEventsFolder then
        battleEventsFolder = eventsFolder:WaitForChild("BattleEvents", 10)
    end

    if not battleEventsFolder then
        return false
    end

    -- 获取或等待CoinEarnedEffect事件
    local coinEarnedEvent = battleEventsFolder:FindFirstChild("CoinEarnedEffect")
    if not coinEarnedEvent then
        coinEarnedEvent = battleEventsFolder:WaitForChild("CoinEarnedEffect", 10)
    end

    if coinEarnedEvent then
        coinEarnedEvent.OnClientEvent:Connect(OnCoinEarned)
    else
        -- 如果仍然找不到，监听文件夹的ChildAdded事件
        battleEventsFolder.ChildAdded:Connect(function(child)
            if child.Name == "CoinEarnedEffect" and child:IsA("RemoteEvent") then
                child.OnClientEvent:Connect(OnCoinEarned)
            end
        end)
    end

    -- 启动更新循环
    RunService.RenderStepped:Connect(UpdateActiveLabels)

    return true
end

-- 启动初始化
pcall(Initialize)

return true
