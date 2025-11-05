--[[
    脚本名称: MergeEffectController (独立粒子控制版)
    脚本类型: Script (服务端脚本)
    脚本位置: ReplicatedStorage/Effect/Merge01、Merge02、Merge03 各自的Part下

    功能说明:
    - 独立控制每个粒子的发射时长
    - 支持不同粒子有不同的播放时间
    - 自动查找并匹配粒子名字
    - 每个粒子独立计时和停止
--]]

-- ======================== 配置区域 ========================

--[[
粒子播放时长配置表
格式: [粒子名字] = 播放时长(秒)

使用说明:
1. 列出你的Part下所有粒子的名字
2. 为每个粒子设置独立的播放时长
3. 如果粒子名字不在配置表中，会跳过该粒子
4. 如果配置了但找不到粒子，会输出警告
]]
local PARTICLE_CONFIG = {
    -- 示例配置（请根据实际情况修改）
    ["ParticleEmitter01"] = 3.0,   -- ParticleEmitter01 播放 3 秒
    ["ParticleEmitter02"] = 2.5,   -- ParticleEmitter02 播放 2.5 秒
    ["ParticleEmitter03"] = 2.0,   -- ParticleEmitter03 播放 2 秒
    ["Glow"] = 1.5,                -- 名为 Glow 的粒子播放 1.5 秒
    ["Sparkle"] = 2.0,             -- 名为 Sparkle 的粒子播放 2 秒

    -- 继续添加你的粒子配置...
    -- ["你的粒子名字"] = 播放时长,
}

-- 默认播放时长（如果粒子名字不在配置表中，使用此值）
local DEFAULT_DURATION = 3.0

-- 是否启用默认时长模式（true = 配置表中没有的粒子也会播放默认时长）
local ENABLE_DEFAULT_MODE = false

-- ======================== 核心逻辑 ========================

-- 获取当前特效Part
local effectPart = script.Parent

-- 等待确保特效完全加载到场景中
task.wait(0.05)

-- 构建粒子索引表 {粒子名字 -> ParticleEmitter实例}
local particleIndex = {}

-- 遍历所有子级对象，建立粒子索引
for _, descendant in ipairs(effectPart:GetDescendants()) do
    if descendant:IsA("ParticleEmitter") then
        local particleName = descendant.Name

        -- 检查是否有重名粒子
        if particleIndex[particleName] then
            warn(string.format("[MergeEffect] 发现重名粒子: %s (将使用第一个找到的)", particleName))
        else
            particleIndex[particleName] = descendant
        end
    end
end

-- 遍历配置表，启动每个粒子
for particleName, duration in pairs(PARTICLE_CONFIG) do
    local emitter = particleIndex[particleName]

    if emitter then
        -- 找到匹配的粒子，启动独立控制
        task.spawn(function()
            -- 启动粒子发射
            emitter.Enabled = true

            -- 等待指定时长
            task.wait(duration)

            -- 停止粒子发射
            emitter.Enabled = false
        end)
    else
        -- 配置了但找不到粒子
        warn(string.format("[MergeEffect] 警告: 配置的粒子 '%s' 未找到!", particleName))
    end
end

-- 如果启用了默认模式，处理未配置的粒子
if ENABLE_DEFAULT_MODE then
    for particleName, emitter in pairs(particleIndex) do
        -- 如果粒子没有在配置表中，使用默认时长
        if not PARTICLE_CONFIG[particleName] then
            task.spawn(function()
                emitter.Enabled = true

                task.wait(DEFAULT_DURATION)

                emitter.Enabled = false
            end)
        end
    end
end

-- 注意事项:
-- 1. 每个粒子独立控制，互不干扰
-- 2. 粒子名字必须唯一，否则只会控制第一个找到的
-- 3. 配置表中的粒子名字必须与实际粒子名字完全匹配（区分大小写）
-- 4. 特效Part的移除由合成系统负责（3秒后移除）
-- 5. 已发射的粒子会继续存活直到生命周期结束，即使Enabled=false
