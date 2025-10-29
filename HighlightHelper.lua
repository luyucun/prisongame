--[[
脚本名称: HighlightHelper
脚本类型: ModuleScript (客户端工具类)
脚本位置: StarterPlayer/StarterPlayerScripts/Utils/HighlightHelper
]]

--[[
高光辅助工具模块
职责:
1. 为模型添加/移除高光效果
2. 设置高光颜色和透明度
3. 管理放置预览的视觉效果
版本: V1.2
]]

local HighlightHelper = {}

-- 高光配置
local HIGHLIGHT_COLOR_VALID = Color3.fromRGB(0, 255, 0)      -- 绿色 - 有效位置
local HIGHLIGHT_COLOR_INVALID = Color3.fromRGB(255, 0, 0)    -- 红色 - 无效位置
local HIGHLIGHT_FILL_TRANSPARENCY = 0.4

-- ==================== 高光管理 ====================

--[[
为模型添加高光效果
@param model Model - 目标模型
@param isValid boolean - 是否为有效位置 (true=绿色, false=红色)
@return Highlight|nil - 创建的Highlight对象
]]
function HighlightHelper.AddHighlight(model, isValid)
    if not model then
        warn("[HighlightHelper] 模型为空，无法添加高光")
        return nil
    end

    -- 检查模型是否已有Highlight
    local existingFolder = model:FindFirstChild("HighlightContainer")
    if existingFolder then
        -- 更新现有高光
        HighlightHelper.SetHighlightColor(model, isValid)
        return existingFolder:FindFirstChildOfClass("Highlight")
    end

    -- 为模型的所有Part添加Highlight
    local highlight = Instance.new("Highlight")
    highlight.Name = "Highlight"
    highlight.Adornee = model
    highlight.FillColor = isValid and HIGHLIGHT_COLOR_VALID or HIGHLIGHT_COLOR_INVALID
    highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
    highlight.OutlineTransparency = 1  -- 完全隐藏描边

    -- 创建容器存储Highlight（用于追踪）
    local container = Instance.new("Folder")
    container.Name = "HighlightContainer"
    highlight.Parent = container
    container.Parent = model

    print(string.format("[HighlightHelper] 添加高光 - 颜色:(%.0f, %.0f, %.0f) 透明度:%.1f",
        highlight.FillColor.R * 255,
        highlight.FillColor.G * 255,
        highlight.FillColor.B * 255,
        highlight.FillTransparency
    ))

    return highlight
end

--[[
移除模型的高光效果
@param model Model - 目标模型
]]
function HighlightHelper.RemoveHighlight(model)
    if not model then
        return
    end

    local container = model:FindFirstChild("HighlightContainer")
    if container then
        container:Destroy()
    end
end

--[[
设置高光颜色
@param model Model - 目标模型
@param isValid boolean - 是否为有效位置
]]
function HighlightHelper.SetHighlightColor(model, isValid)
    if not model then
        return
    end

    local container = model:FindFirstChild("HighlightContainer")
    if not container then
        HighlightHelper.AddHighlight(model, isValid)
        return
    end

    local highlight = container:FindFirstChildOfClass("Highlight")
    if highlight then
        local color = isValid and HIGHLIGHT_COLOR_VALID or HIGHLIGHT_COLOR_INVALID
        highlight.FillColor = color
        print(string.format("[HighlightHelper] 更新高光颜色 - (%.0f, %.0f, %.0f)",
            highlight.FillColor.R * 255,
            highlight.FillColor.G * 255,
            highlight.FillColor.B * 255
        ))
    end
end

--[[
为预览模型启用高光
@param model Model
]]
function HighlightHelper.EnablePreviewHighlight(model)
    return HighlightHelper.AddHighlight(model, true)
end

--[[
更新预览高光状态
@param model Model
@param isValidPosition boolean - 当前位置是否有效
]]
function HighlightHelper.UpdatePreviewHighlight(model, isValidPosition)
    if not model then
        return
    end

    HighlightHelper.SetHighlightColor(model, isValidPosition)
end

-- ==================== 模型透明度控制 ====================

--[[
设置模型半透明(用于预览)
@param model Model
@param transparency number - 透明度 0-1
]]
function HighlightHelper.SetModelTransparency(model, transparency)
    if not model then
        return
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Transparency = transparency
        end
    end
end

--[[
设置模型为预览状态
@param model Model
]]
function HighlightHelper.SetPreviewMode(model)
    if not model then
        return
    end

    -- 禁用碰撞
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.Anchored = true
        end
    end

    -- 添加高光
    HighlightHelper.EnablePreviewHighlight(model)
end

--[[
恢复模型正常状态
@param model Model
]]
function HighlightHelper.RestoreNormalMode(model)
    if not model then
        return
    end

    -- 启用碰撞
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = true
            descendant.Anchored = true  -- 放置后保持锚定
        end
    end

    -- 移除高光
    HighlightHelper.RemoveHighlight(model)
end

-- ==================== 放置动画 ====================

--[[
播放放置缩放动画
@param model Model
@param duration number - 动画时长(秒)
@param callback function - 动画完成回调
]]
function HighlightHelper.PlayPlacementAnimation(model, duration, callback)
    if not model or not model.PrimaryPart then
        if callback then
            callback()
        end
        return
    end

    duration = duration or 0.2
    local startScale = 0.5
    local endScale = 1.0
    local startTime = tick()

    -- 保存每个部件的原始大小
    local originalSizes = {}
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            originalSizes[part] = part.Size
        end
    end

    local originalCFrame = model.PrimaryPart.CFrame

    -- 创建动画循环
    local connection
    connection = game:GetService("RunService").RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        local progress = math.min(elapsed / duration, 1)

        -- 使用缓动函数
        local eased = 1 - math.pow(1 - progress, 3)  -- EaseOut Cubic
        local currentScale = startScale + (endScale - startScale) * eased

        -- 应用缩放到所有部件
        if model and model.PrimaryPart then
            for part, originalSize in pairs(originalSizes) do
                if part and part.Parent then
                    part.Size = originalSize * currentScale
                end
            end
            -- 保持位置不变
            model:SetPrimaryPartCFrame(originalCFrame)
        end

        -- 动画完成
        if progress >= 1 then
            connection:Disconnect()
            if callback then
                callback()
            end
        end
    end)
end

-- ==================== 工具函数 ====================

--[[
检查模型是否有Highlight组件
@param model Model
@return boolean
]]
function HighlightHelper.HasHighlight(model)
    if not model then
        return false
    end

    return model:FindFirstChild("HighlightContainer") ~= nil
end

--[[
获取模型的Highlight组件
@param model Model
@return Highlight|nil
]]
function HighlightHelper.GetHighlight(model)
    if not model then
        return nil
    end

    local container = model:FindFirstChild("HighlightContainer")
    if container then
        return container:FindFirstChildOfClass("Highlight")
    end

    return nil
end

-- ==================== 调试函数 ====================

--[[
打印高光信息
@param model Model
]]
function HighlightHelper.DebugPrintHighlight(model)
    if not model then
        print("[HighlightHelper] 模型为空")
        return
    end

    local highlight = HighlightHelper.GetHighlight(model)
    if highlight then
        print(string.format("[HighlightHelper] 高光存在 - 颜色:(%.0f, %.0f, %.0f) FillTransparency:%.2f OutlineTransparency:%.2f",
            highlight.FillColor.R * 255,
            highlight.FillColor.G * 255,
            highlight.FillColor.B * 255,
            highlight.FillTransparency,
            highlight.OutlineTransparency
        ))
    else
        print("[HighlightHelper] 模型没有高光")
    end
end

return HighlightHelper

