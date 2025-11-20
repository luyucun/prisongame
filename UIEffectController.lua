--[[
    脚本名称: UIEffectController (UI特效粒子控制器)
    脚本类型: LocalScript (客户端脚本)
    脚本位置: PlayerGui/ScreenGui/Frame 或 Configuration 下

    功能说明:
    - 专门用于屏幕UI特效的粒子控制
    - 独立控制每个粒子的发射时长
    - 支持不同粒子有不同的播放时间
    - 自动查找并匹配粒子名字
    - 每个粒子独立计时和停止
    - 与外部ScreenGui.Enabled控制兼容

    使用说明:
    1. 将此脚本作为LocalScript放在ScreenGui、Frame或Configuration下
    2. 外部通过控制父级ScreenGui.Enabled = true/false来显示/隐藏整个特效
    3. 脚本会自动控制内部粒子的播放时长
    4. 每个粒子可以设置独立的播放时间
--]]

-- ======================== 配置区域 ========================

--[[
粒子播放时长配置表
格式: [粒子名字] = 播放时长(秒)

使用说明:
1. 列出你的UI容器下所有粒子的名字
2. 为每个粒子设置独立的播放时长
3. 如果粒子名字不在配置表中，会跳过该粒子
4. 如果配置了但找不到粒子，会输出警告

常见UI特效粒子配置示例:
]]
local PARTICLE_CONFIG = {
    -- 合成特效粒子
    ["MergeSparkle"] = 2.5,        -- 合成闪光效果 2.5秒
    ["MergeGlow"] = 3.0,           -- 合成发光效果 3秒
    ["MergeBurst"] = 1.5,          -- 合成爆发效果 1.5秒

    -- 升级特效粒子
    ["UpgradeStars"] = 2.0,        -- 升级星星效果 2秒
    ["UpgradeRays"] = 2.8,         -- 升级射线效果 2.8秒

    -- 通用特效粒子
    ["ParticleEmitter01"] = 3.0,   -- 通用粒子1
    ["ParticleEmitter02"] = 2.5,   -- 通用粒子2
    ["ParticleEmitter03"] = 2.0,   -- 通用粒子3
    ["Glow"] = 1.5,                -- 发光效果
    ["Sparkle"] = 2.0,             -- 闪烁效果
    ["Trail"] = 2.2,               -- 拖尾效果
    ["Burst"] = 1.8,               -- 爆发效果

    -- 继续添加你的粒子配置...
    -- ["你的粒子名字"] = 播放时长,
}

-- 默认播放时长（如果粒子名字不在配置表中，使用此值）
local DEFAULT_DURATION = 3.0

-- 是否启用默认时长模式（true = 配置表中没有的粒子也会播放默认时长）
local ENABLE_DEFAULT_MODE = false

-- 调试模式开关
local DEBUG_MODE = true

-- ======================== 核心逻辑 ========================

-- 获取当前UI特效容器（支持ScreenGui、Frame、Configuration等）
local effectContainer = script.Parent

-- 日志前缀
local LOG_PREFIX = "[UIEffectController]"

-- 等待确保UI特效完全加载到场景中
task.wait(0.05)

if DEBUG_MODE then
    print(LOG_PREFIX, "开始初始化UI特效控制器")
    print(LOG_PREFIX, "特效容器:", effectContainer:GetFullName())
    print(LOG_PREFIX, "容器类型:", effectContainer.ClassName)
end

-- 构建粒子索引表 {粒子名字 -> ParticleEmitter实例}
local particleIndex = {}

-- 遍历所有子级对象，建立粒子索引
for _, descendant in ipairs(effectContainer:GetDescendants()) do
    if descendant:IsA("ParticleEmitter") then
        local particleName = descendant.Name

        -- 检查是否有重名粒子
        if particleIndex[particleName] then
            warn(string.format("%s 发现重名粒子: %s (将使用第一个找到的)", LOG_PREFIX, particleName))
        else
            particleIndex[particleName] = descendant
            if DEBUG_MODE then
                print(LOG_PREFIX, "找到粒子:", particleName, "→", descendant:GetFullName())
            end
        end
    end
end

-- 统计找到的粒子数量
local totalParticles = 0
for _ in pairs(particleIndex) do
    totalParticles = totalParticles + 1
end

if DEBUG_MODE then
    print(LOG_PREFIX, string.format("共找到 %d 个粒子发射器", totalParticles))
end

if totalParticles == 0 then
    warn(LOG_PREFIX, "警告: 未找到任何粒子发射器！请检查容器结构")
    return
end

-- 遍历配置表，启动每个粒子
local activeParticleCount = 0

for particleName, duration in pairs(PARTICLE_CONFIG) do
    local emitter = particleIndex[particleName]

    if emitter then
        activeParticleCount = activeParticleCount + 1

        -- 找到匹配的粒子，启动独立控制
        task.spawn(function()
            if DEBUG_MODE then
                print(LOG_PREFIX, string.format("启动粒子: %s (播放时长: %.1f秒)", particleName, duration))
            end

            -- 启动粒子发射
            emitter.Enabled = true

            -- 等待指定时长
            task.wait(duration)

            -- 停止粒子发射
            emitter.Enabled = false

            if DEBUG_MODE then
                print(LOG_PREFIX, string.format("停止粒子: %s", particleName))
            end
        end)
    else
        -- 配置了但找不到粒子
        warn(string.format("%s 警告: 配置的粒子 '%s' 未找到!", LOG_PREFIX, particleName))
    end
end

-- 如果启用了默认模式，处理未配置的粒子
if ENABLE_DEFAULT_MODE then
    for particleName, emitter in pairs(particleIndex) do
        -- 如果粒子没有在配置表中，使用默认时长
        if not PARTICLE_CONFIG[particleName] then
            activeParticleCount = activeParticleCount + 1

            task.spawn(function()
                if DEBUG_MODE then
                    print(LOG_PREFIX, string.format("启动未配置粒子: %s (默认时长: %.1f秒)", particleName, DEFAULT_DURATION))
                end

                emitter.Enabled = true

                task.wait(DEFAULT_DURATION)

                emitter.Enabled = false

                if DEBUG_MODE then
                    print(LOG_PREFIX, string.format("停止未配置粒子: %s", particleName))
                end
            end)
        end
    end
end

if DEBUG_MODE then
    print(LOG_PREFIX, string.format("✅ UI特效控制器初始化完成，共激活 %d 个粒子", activeParticleCount))
end

--[[
======================== 使用说明 ========================

### 在合成系统中的使用示例：

```lua
-- 服务端: MergeSystem.lua
local function NotifyClientMergeEffect(player, mergePosition)
    local remoteEvent = ReplicatedStorage.Events.MergeEvents:FindFirstChild("ShowMergeEffect")
    if remoteEvent then
        remoteEvent:FireClient(player, mergePosition)
    end
end

-- 客户端: MergeEffectHandler.lua (LocalScript)
local remoteEvent = ReplicatedStorage.Events.MergeEvents:FindFirstChild("ShowMergeEffect")

remoteEvent.OnClientEvent:Connect(function(mergePosition)
    local screenGui = player.PlayerGui:FindFirstChild("MergeEffectGui")

    if screenGui then
        -- 可选: 设置特效位置（如果需要）
        -- screenGui.Frame.Position = UDim2.new(0, mergePosition.X, 0, mergePosition.Y)

        -- 显示特效（UIEffectController会自动控制粒子播放）
        screenGui.Enabled = true

        -- 3秒后隐藏（或根据最长粒子时长调整）
        task.delay(3.0, function()
            screenGui.Enabled = false
        end)
    end
end)
```

### ScreenGui结构示例：

```
PlayerGui
└── MergeEffectGui (ScreenGui)
    ├── UIEffectController (LocalScript) ← 此脚本
    └── EffectFrame (Frame)
        └── Configuration
            ├── MergeSparkle (ParticleEmitter)
            ├── MergeGlow (ParticleEmitter)
            ├── MergeBurst (ParticleEmitter)
            └── 其他粒子...
```

======================== 注意事项 ========================

1. 每个粒子独立控制，互不干扰
2. 粒子名字必须唯一，否则只会控制第一个找到的
3. 配置表中的粒子名字必须与实际粒子名字完全匹配（区分大小写）
4. 外部通过 ScreenGui.Enabled 控制整体显示/隐藏，脚本只负责粒子播放时长
5. 已发射的粒子会继续存活直到生命周期结束，即使Enabled=false
6. 建议将DEBUG_MODE设为false以减少控制台输出
7. 如果需要重复播放，每次都需要重新设置ScreenGui.Enabled=true
8. 此脚本专用于UI特效，不要用于3D场景特效

--]]