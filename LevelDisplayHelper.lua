--[[
脚本名称: LevelDisplayHelper
脚本类型: ModuleScript (通用工具类)
脚本位置: ReplicatedStorage/Modules/LevelDisplayHelper
]]

--[[
等级显示辅助工具模块 (V2.2)
职责:
1. 统一管理兵种等级的显示逻辑
2. 根据等级设置正确的文本、字体颜色和描边颜色
3. 提供通用接口供各系统调用
]]

local LevelDisplayHelper = {}

-- 引用配置模块
local LevelColorConfig = require(script.Parent.Parent.Config.LevelColorConfig)

-- ==================== 核心功能 ====================

--[[
更新兵种等级显示 (V2.2)
统一处理等级文本、字体颜色和描边颜色
@param unitModel Model - 兵种模型
@param level number - 等级数值
@param maxLevel number - 最高等级 (可选，默认从UnitConfig获取)
@return boolean - 是否更新成功
]]
function LevelDisplayHelper.UpdateLevelDisplay(unitModel, level, maxLevel)
    -- 容错：参数检查
    if not unitModel or not level then
        warn("[LevelDisplayHelper] UpdateLevelDisplay: 参数无效，unitModel=" .. tostring(unitModel) .. ", level=" .. tostring(level))
        return false
    end

    -- 查找等级显示UI结构: Head - BillboardGui - Bg - TextLabel
    local head = unitModel:FindFirstChild("Head")
    if not head then
        -- 容错：没有Head则安全返回
        warn("[LevelDisplayHelper] UpdateLevelDisplay: 找不到Head，model=" .. tostring(unitModel.Name))
        return false
    end

    local billboardGui = head:FindFirstChild("BillboardGui")
    if not billboardGui then
        -- 容错：没有BillboardGui则安全返回
        warn("[LevelDisplayHelper] UpdateLevelDisplay: 找不到BillboardGui，model=" .. tostring(unitModel.Name))
        return false
    end

    local bg = billboardGui:FindFirstChild("Bg")
    if not bg then
        -- 容错：没有Bg则安全返回
        warn("[LevelDisplayHelper] UpdateLevelDisplay: 找不到Bg，model=" .. tostring(unitModel.Name))
        return false
    end

    local textLabel = bg:FindFirstChild("TextLabel")
    if not textLabel then
        -- 容错：没有TextLabel则安全返回
        warn("[LevelDisplayHelper] UpdateLevelDisplay: 找不到TextLabel，model=" .. tostring(unitModel.Name))
        return false
    end

    -- 获取等级显示配置
    local success, errorMsg = pcall(function()
        -- 获取等级文本和颜色
        local levelText = LevelColorConfig.GetLevelText(level, maxLevel)
        local levelColors = LevelColorConfig.GetLevelColors(level, maxLevel)

        -- V2.8.1调试：打印更新信息
        print("[LevelDisplayHelper] 更新等级显示: model=" .. unitModel.Name .. ", level=" .. tostring(level) .. ", text=" .. levelText)

        -- 设置等级文本
        textLabel.Text = levelText

        -- 设置字体颜色
        textLabel.TextColor3 = levelColors.Font

        -- 设置描边颜色 (优先使用UIStroke，兜底使用TextStroke)
        local uiStroke = textLabel:FindFirstChild("UIStroke") or textLabel:FindFirstChild("Stroke")
        if uiStroke and uiStroke:IsA("UIStroke") then
            -- 使用UIStroke方案
            uiStroke.Color = levelColors.Stroke
            uiStroke.Enabled = true
            uiStroke.Transparency = 0
        else
            -- 兜底使用TextStroke方案
            textLabel.TextStrokeColor3 = levelColors.Stroke
            textLabel.TextStrokeTransparency = 0
        end
    end)

    if not success then
        warn("[LevelDisplayHelper] UpdateLevelDisplay: 更新等级显示时发生错误，unitModel=" .. tostring(unitModel.Name) .. ", level=" .. tostring(level) .. ", error=" .. tostring(errorMsg))
        return false
    end

    return true
end

--[[
批量更新多个兵种的等级显示
@param unitDataList table - 兵种数据列表，格式: {{model=Model, level=number}, ...}
@param maxLevel number - 最高等级 (可选)
@return number - 成功更新的数量
]]
function LevelDisplayHelper.BatchUpdateLevelDisplay(unitDataList, maxLevel)
    if not unitDataList or type(unitDataList) ~= "table" then
        warn("[LevelDisplayHelper] BatchUpdateLevelDisplay: unitDataList无效")
        return 0
    end

    local successCount = 0
    for i, unitData in ipairs(unitDataList) do
        if unitData.model and unitData.level then
            local success = LevelDisplayHelper.UpdateLevelDisplay(unitData.model, unitData.level, maxLevel)
            if success then
                successCount = successCount + 1
            end
        else
            warn("[LevelDisplayHelper] BatchUpdateLevelDisplay: 第" .. i .. "个单位数据无效")
        end
    end

    return successCount
end

--[[
获取兵种当前显示的等级 (从UI读取)
@param unitModel Model - 兵种模型
@return number|nil - 当前等级，如果获取失败则返回nil
]]
function LevelDisplayHelper.GetCurrentDisplayLevel(unitModel)
    if not unitModel then
        return nil
    end

    local head = unitModel:FindFirstChild("Head")
    if not head then
        return nil
    end

    local billboardGui = head:FindFirstChild("BillboardGui")
    if not billboardGui then
        return nil
    end

    local bg = billboardGui:FindFirstChild("Bg")
    if not bg then
        return nil
    end

    local textLabel = bg:FindFirstChild("TextLabel")
    if not textLabel then
        return nil
    end

    local text = textLabel.Text
    if text == "Lv.Max" then
        -- 返回最高等级
        local UnitConfig = require(game.ReplicatedStorage.Config.UnitConfig)
        return UnitConfig.MAX_LEVEL or 3
    else
        -- 解析数字等级
        local level = tonumber(text:match("Lv%.(%d+)"))
        return level
    end
end

-- ==================== 调试与工具函数 ====================

--[[
检查兵种模型是否具备等级显示UI结构
@param unitModel Model - 兵种模型
@return boolean - 是否具备完整结构
@return string - 检查结果描述
]]
function LevelDisplayHelper.CheckLevelDisplayStructure(unitModel)
    if not unitModel then
        return false, "模型为空"
    end

    local head = unitModel:FindFirstChild("Head")
    if not head then
        return false, "缺少Head"
    end

    local billboardGui = head:FindFirstChild("BillboardGui")
    if not billboardGui then
        return false, "缺少BillboardGui"
    end

    local bg = billboardGui:FindFirstChild("Bg")
    if not bg then
        return false, "缺少Bg"
    end

    local textLabel = bg:FindFirstChild("TextLabel")
    if not textLabel then
        return false, "缺少TextLabel"
    end

    return true, "结构完整"
end

--[[
为兵种模型创建等级显示UI结构 (如果缺失)
@param unitModel Model - 兵种模型
@param level number - 初始等级
@return boolean - 是否创建成功
]]
function LevelDisplayHelper.CreateLevelDisplayIfMissing(unitModel, level)
    if not unitModel or not level then
        return false
    end

    local hasStructure, message = LevelDisplayHelper.CheckLevelDisplayStructure(unitModel)
    if hasStructure then
        -- 结构已存在，直接更新
        return LevelDisplayHelper.UpdateLevelDisplay(unitModel, level)
    end

    -- TODO: 如果需要，可以在这里实现自动创建UI结构的逻辑
    -- 当前只返回false，让调用者知道结构不完整
    warn("[LevelDisplayHelper] CreateLevelDisplayIfMissing: 兵种模型缺少等级显示结构 - " .. message)
    return false
end

return LevelDisplayHelper