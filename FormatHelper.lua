--[[
脚本名称: FormatHelper
脚本类型: ModuleScript (共享模块)
脚本位置: ReplicatedStorage/Modules/FormatHelper
]]

--[[
格式化辅助工具模块
职责:
1. 提供各种数据格式化功能
2. 金币显示格式化
3. 数字缩写格式化(后续版本)
]]

local FormatHelper = {}

-- ==================== 金币格式化 ====================

--[[
格式化金币显示
@param amount number - 金币数量
@return string - 格式化后的字符串,如 "$100"
]]
function FormatHelper.FormatCoins(amount)
    if type(amount) ~= "number" then
        warn("[FormatHelper] FormatCoins: 参数必须是数字")
        return "$0"
    end

    -- 确保金币不为负数
    if amount < 0 then
        amount = 0
    end

    -- 格式化为 $XXXXX
    return string.format("$%d", math.floor(amount))
end

-- ==================== 数字格式化 ====================

--[[
添加千分位分隔符
@param number number - 数字
@return string - 格式化后的字符串,如 "1,000,000"
]]
function FormatHelper.FormatNumberWithCommas(number)
    if type(number) ~= "number" then
        return "0"
    end

    local formatted = tostring(math.floor(number))
    local k

    -- 从右向左每三位添加逗号
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end

    return formatted
end

--[[
数字缩写格式化(K, M, B, T)
@param number number - 数字
@return string - 缩写后的字符串,如 "1.5K", "2.3M"
]]
function FormatHelper.FormatNumberShort(number)
    if type(number) ~= "number" then
        return "0"
    end

    if number < 0 then
        number = 0
    end

    -- 定义缩写单位
    local abbreviations = {
        {value = 1e12, suffix = "T"},  -- Trillion 万亿
        {value = 1e9,  suffix = "B"},  -- Billion 十亿
        {value = 1e6,  suffix = "M"},  -- Million 百万
        {value = 1e3,  suffix = "K"},  -- Thousand 千
    }

    -- 查找合适的缩写
    for _, abbr in ipairs(abbreviations) do
        if number >= abbr.value then
            local shortened = number / abbr.value
            -- 保留一位小数
            return string.format("%.1f%s", shortened, abbr.suffix)
        end
    end

    -- 小于1000直接显示
    return tostring(math.floor(number))
end

-- ==================== 时间格式化 ====================

--[[
格式化秒数为时分秒
@param seconds number - 秒数
@return string - 格式化后的时间字符串,如 "1:30:45" 或 "30:45"
]]
function FormatHelper.FormatTime(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        return "0:00"
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    else
        return string.format("%d:%02d", minutes, secs)
    end
end

--[[
格式化秒数为友好的时间描述
@param seconds number - 秒数
@return string - 友好的时间描述,如 "2小时30分" 或 "45秒"
]]
function FormatHelper.FormatTimeFriendly(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        return "0秒"
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        if minutes > 0 then
            return string.format("%d小时%d分", hours, minutes)
        else
            return string.format("%d小时", hours)
        end
    elseif minutes > 0 then
        if secs > 0 then
            return string.format("%d分%d秒", minutes, secs)
        else
            return string.format("%d分", minutes)
        end
    else
        return string.format("%d秒", secs)
    end
end

-- ==================== 百分比格式化 ====================

--[[
格式化百分比
@param value number - 数值(0-1)
@param decimals number - 小数位数(默认0)
@return string - 百分比字符串,如 "75%"
]]
function FormatHelper.FormatPercent(value, decimals)
    if type(value) ~= "number" then
        return "0%"
    end

    decimals = decimals or 0

    local percent = value * 100

    if decimals == 0 then
        return string.format("%d%%", math.floor(percent))
    else
        return string.format("%." .. decimals .. "f%%", percent)
    end
end

-- ==================== 测试函数 ====================

--[[
测试格式化功能(调试用)
]]
function FormatHelper.Test()
    print("=== FormatHelper 测试 ===")

    -- 测试金币格式化
    print("金币格式化测试:")
    print("  100 ->", FormatHelper.FormatCoins(100))
    print("  1500 ->", FormatHelper.FormatCoins(1500))
    print("  999999 ->", FormatHelper.FormatCoins(999999))

    -- 测试数字缩写
    print("数字缩写测试:")
    print("  500 ->", FormatHelper.FormatNumberShort(500))
    print("  1500 ->", FormatHelper.FormatNumberShort(1500))
    print("  1500000 ->", FormatHelper.FormatNumberShort(1500000))
    print("  2300000000 ->", FormatHelper.FormatNumberShort(2300000000))

    -- 测试千分位
    print("千分位测试:")
    print("  1000000 ->", FormatHelper.FormatNumberWithCommas(1000000))

    -- 测试时间格式化
    print("时间格式化测试:")
    print("  65秒 ->", FormatHelper.FormatTime(65))
    print("  3665秒 ->", FormatHelper.FormatTime(3665))
    print("  65秒(友好) ->", FormatHelper.FormatTimeFriendly(65))
    print("  3665秒(友好) ->", FormatHelper.FormatTimeFriendly(3665))

    -- 测试百分比
    print("百分比测试:")
    print("  0.75 ->", FormatHelper.FormatPercent(0.75))
    print("  0.5678 (2位小数) ->", FormatHelper.FormatPercent(0.5678, 2))

    print("=== 测试完成 ===")
end

return FormatHelper
