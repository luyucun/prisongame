--[[
脚本名称: LevelColorConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/LevelColorConfig
]]

--[[
等级颜色配置模块 (V2.2)
职责: 存储不同等级的字体颜色和描边颜色配置
]]

local LevelColorConfig = {}

-- ==================== 等级颜色映射 V2.2 ====================

--[[
等级颜色配置表
Font: 字体颜色 (TextLabel.TextColor3)
Stroke: 描边颜色 (UIStroke.Color 或 TextLabel.TextStrokeColor3)
]]
LevelColorConfig.LevelColors = {
    [1] = { Font = Color3.fromRGB(255, 255, 255), Stroke = Color3.fromRGB(0, 170, 0) },   -- LV.1: 白字绿边
    [2] = { Font = Color3.fromRGB(255, 255, 255), Stroke = Color3.fromRGB(0, 80, 255) },  -- LV.2: 白字蓝边
    [3] = { Font = Color3.fromRGB(255, 255, 255), Stroke = Color3.fromRGB(170, 0, 255) }, -- LV.3: 白字紫边
    [4] = { Font = Color3.fromRGB(255, 255, 255), Stroke = Color3.fromRGB(255, 100, 0) }, -- LV.4: 白字橙边
    [5] = { Font = Color3.fromRGB(255, 255, 255), Stroke = Color3.fromRGB(255, 0, 0) },   -- LV.5: 白字红边

    -- 最高等级特殊颜色 (当等级达到UnitConfig.MAX_LEVEL时使用)
    Max = { Font = Color3.fromRGB(0, 0, 0), Stroke = Color3.fromRGB(255, 0, 0) },         -- Lv.Max: 黑字红边
}

-- ==================== 辅助函数 ====================

--[[
获取指定等级的颜色配置
@param level number - 等级数值
@param maxLevel number - 最高等级 (可选，默认从UnitConfig获取)
@return table - {Font = Color3, Stroke = Color3}
]]
function LevelColorConfig.GetLevelColors(level, maxLevel)
    -- 获取最高等级
    if not maxLevel then
        local UnitConfig = require(game.ReplicatedStorage.Config.UnitConfig)
        maxLevel = UnitConfig.MAX_LEVEL or 5
    end

    -- 如果已达最高等级，使用Max配置
    if level >= maxLevel then
        return LevelColorConfig.LevelColors.Max
    end

    -- 查找对应等级的颜色，找不到则使用1级颜色兜底
    local colors = LevelColorConfig.LevelColors[level]
    if colors then
        return colors
    else
        warn("[LevelColorConfig] 找不到等级 " .. tostring(level) .. " 的颜色配置，使用1级颜色兜底")
        return LevelColorConfig.LevelColors[1]
    end
end

--[[
获取等级显示文本
@param level number - 等级数值
@param maxLevel number - 最高等级 (可选，默认从UnitConfig获取)
@return string - 显示文本 ("Lv.1" 或 "Lv.Max")
]]
function LevelColorConfig.GetLevelText(level, maxLevel)
    -- 获取最高等级
    if not maxLevel then
        local UnitConfig = require(game.ReplicatedStorage.Config.UnitConfig)
        maxLevel = UnitConfig.MAX_LEVEL or 5
    end

    -- 如果已达最高等级，显示Max
    if level >= maxLevel then
        return "Lv.Max"
    else
        return "Lv." .. tostring(level)
    end
end

return LevelColorConfig
