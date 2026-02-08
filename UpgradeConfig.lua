--[[
脚本名称: UpgradeConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/UpgradeConfig
]]

local UpgradeConfig = {}

UpgradeConfig.TYPE = {
    MOVE_SPEED = 1,
    ATTACK_SPEED = 2,
    ATTACK = 3,
    HEALTH = 4,
}

UpgradeConfig.TYPE_ORDER = {1, 2, 3, 4}

UpgradeConfig.TYPE_NAME = {
    [1] = "移动速度",
    [2] = "攻击速度",
    [3] = "攻击力",
    [4] = "生命值",
}

UpgradeConfig.DEV_PRODUCT_IDS = {
    [1] = 3531774125,
    [2] = 3531774364,
    [3] = 3531774660,
    [4] = 3531774899,
}

local LEVEL_CONFIG = {
    [1] = {
        [0] = { BonusRatio = 0, Price = 0 },
        [1] = { BonusRatio = 0.05, Price = 1000 },
        [2] = { BonusRatio = 0.1, Price = 3000 },
        [3] = { BonusRatio = 0.15, Price = 9000 },
        [4] = { BonusRatio = 0.2, Price = 27000 },
        [5] = { BonusRatio = 0.25, Price = 81000 },
        [6] = { BonusRatio = 0.3, Price = 243000 },
        [7] = { BonusRatio = 0.35, Price = 729000 },
        [8] = { BonusRatio = 0.4, Price = 2187000 },
        [9] = { BonusRatio = 0.45, Price = 6561000 },
        [10] = { BonusRatio = 0.5, Price = 19683000 },
        [11] = { BonusRatio = 0.55, Price = 59049000 },
        [12] = { BonusRatio = 0.6, Price = 177147000 },
        [13] = { BonusRatio = 0.65, Price = 531441000 },
        [14] = { BonusRatio = 0.7, Price = 1594323000 },
        [15] = { BonusRatio = 0.75, Price = 4782969000 },
        [16] = { BonusRatio = 0.8, Price = 14348907000 },
        [17] = { BonusRatio = 0.85, Price = 43046721000 },
        [18] = { BonusRatio = 0.9, Price = 129140163000 },
        [19] = { BonusRatio = 0.95, Price = 387420489000 },
        [20] = { BonusRatio = 1, Price = 1162261467000 },
    },
    [2] = {
        [0] = { BonusRatio = 0, Price = 0 },
        [1] = { BonusRatio = 0.02, Price = 1000 },
        [2] = { BonusRatio = 0.04, Price = 2500 },
        [3] = { BonusRatio = 0.06, Price = 6250 },
        [4] = { BonusRatio = 0.08, Price = 15625 },
        [5] = { BonusRatio = 0.1, Price = 39063 },
        [6] = { BonusRatio = 0.12, Price = 97656 },
        [7] = { BonusRatio = 0.14, Price = 244141 },
        [8] = { BonusRatio = 0.16, Price = 610352 },
        [9] = { BonusRatio = 0.18, Price = 1525879 },
        [10] = { BonusRatio = 0.2, Price = 3814697 },
        [11] = { BonusRatio = 0.22, Price = 9536743 },
        [12] = { BonusRatio = 0.24, Price = 23841858 },
        [13] = { BonusRatio = 0.26, Price = 59604645 },
        [14] = { BonusRatio = 0.28, Price = 149011612 },
        [15] = { BonusRatio = 0.3, Price = 372529030 },
        [16] = { BonusRatio = 0.32, Price = 931322575 },
        [17] = { BonusRatio = 0.34, Price = 2328306437 },
        [18] = { BonusRatio = 0.36, Price = 5820766091 },
        [19] = { BonusRatio = 0.38, Price = 14551915228 },
        [20] = { BonusRatio = 0.4, Price = 36379788071 },
        [21] = { BonusRatio = 0.42, Price = 90949470177 },
        [22] = { BonusRatio = 0.44, Price = 227373675443 },
        [23] = { BonusRatio = 0.46, Price = 568434188608 },
        [24] = { BonusRatio = 0.48, Price = 1421085471520 },
        [25] = { BonusRatio = 0.5, Price = 3552713678801 },
        [26] = { BonusRatio = 0.52, Price = 8881784197001 },
        [27] = { BonusRatio = 0.54, Price = 22204460492503 },
        [28] = { BonusRatio = 0.56, Price = 55511151231258 },
        [29] = { BonusRatio = 0.58, Price = 138777878078145 },
        [30] = { BonusRatio = 0.6, Price = 346944695195361 },
    },
    [3] = {
        [0] = { BonusRatio = 0, Price = 0 },
        [1] = { BonusRatio = 0.015, Price = 1000 },
        [2] = { BonusRatio = 0.03, Price = 2000 },
        [3] = { BonusRatio = 0.045, Price = 4000 },
        [4] = { BonusRatio = 0.06, Price = 8000 },
        [5] = { BonusRatio = 0.075, Price = 16000 },
        [6] = { BonusRatio = 0.09, Price = 32000 },
        [7] = { BonusRatio = 0.105, Price = 64000 },
        [8] = { BonusRatio = 0.12, Price = 128000 },
        [9] = { BonusRatio = 0.135, Price = 256000 },
        [10] = { BonusRatio = 0.15, Price = 512000 },
        [11] = { BonusRatio = 0.165, Price = 1024000 },
        [12] = { BonusRatio = 0.18, Price = 2048000 },
        [13] = { BonusRatio = 0.195, Price = 4096000 },
        [14] = { BonusRatio = 0.21, Price = 8192000 },
        [15] = { BonusRatio = 0.225, Price = 16384000 },
        [16] = { BonusRatio = 0.24, Price = 32768000 },
        [17] = { BonusRatio = 0.255, Price = 65536000 },
        [18] = { BonusRatio = 0.27, Price = 131072000 },
        [19] = { BonusRatio = 0.285, Price = 262144000 },
        [20] = { BonusRatio = 0.3, Price = 524288000 },
        [21] = { BonusRatio = 0.315, Price = 1048576000 },
        [22] = { BonusRatio = 0.33, Price = 2097152000 },
        [23] = { BonusRatio = 0.345, Price = 4194304000 },
        [24] = { BonusRatio = 0.36, Price = 8388608000 },
        [25] = { BonusRatio = 0.375, Price = 16777216000 },
        [26] = { BonusRatio = 0.39, Price = 33554432000 },
        [27] = { BonusRatio = 0.405, Price = 67108864000 },
        [28] = { BonusRatio = 0.42, Price = 134217728000 },
        [29] = { BonusRatio = 0.435, Price = 268435456000 },
        [30] = { BonusRatio = 0.45, Price = 536870912000 },
        [31] = { BonusRatio = 0.465, Price = 1073741824000 },
        [32] = { BonusRatio = 0.48, Price = 2147483648000 },
        [33] = { BonusRatio = 0.495, Price = 4294967296000 },
        [34] = { BonusRatio = 0.51, Price = 8589934592000 },
        [35] = { BonusRatio = 0.525, Price = 17179869184000 },
        [36] = { BonusRatio = 0.54, Price = 34359738368000 },
        [37] = { BonusRatio = 0.555, Price = 68719476736000 },
        [38] = { BonusRatio = 0.57, Price = 137438953472000 },
        [39] = { BonusRatio = 0.585, Price = 274877906944000 },
        [40] = { BonusRatio = 0.6, Price = 549755813888000 },
        [41] = { BonusRatio = 0.615, Price = 1099511627776000 },
        [42] = { BonusRatio = 0.63, Price = 2199023255552000 },
        [43] = { BonusRatio = 0.645, Price = 4398046511104000 },
        [44] = { BonusRatio = 0.66, Price = 8796093022208000 },
        [45] = { BonusRatio = 0.675, Price = 17592186044416000 },
        [46] = { BonusRatio = 0.69, Price = 35184372088832000 },
        [47] = { BonusRatio = 0.705, Price = 70368744177664000 },
        [48] = { BonusRatio = 0.72, Price = 140737488355328000 },
        [49] = { BonusRatio = 0.735, Price = 281474976710656000 },
        [50] = { BonusRatio = 0.75, Price = 562949953421312000 },
    },
    [4] = {
        [0] = { BonusRatio = 0, Price = 0 },
        [1] = { BonusRatio = 0.015, Price = 1000 },
        [2] = { BonusRatio = 0.03, Price = 2000 },
        [3] = { BonusRatio = 0.045, Price = 4000 },
        [4] = { BonusRatio = 0.06, Price = 8000 },
        [5] = { BonusRatio = 0.075, Price = 16000 },
        [6] = { BonusRatio = 0.09, Price = 32000 },
        [7] = { BonusRatio = 0.105, Price = 64000 },
        [8] = { BonusRatio = 0.12, Price = 128000 },
        [9] = { BonusRatio = 0.135, Price = 256000 },
        [10] = { BonusRatio = 0.15, Price = 512000 },
        [11] = { BonusRatio = 0.165, Price = 1024000 },
        [12] = { BonusRatio = 0.18, Price = 2048000 },
        [13] = { BonusRatio = 0.195, Price = 4096000 },
        [14] = { BonusRatio = 0.21, Price = 8192000 },
        [15] = { BonusRatio = 0.225, Price = 16384000 },
        [16] = { BonusRatio = 0.24, Price = 32768000 },
        [17] = { BonusRatio = 0.255, Price = 65536000 },
        [18] = { BonusRatio = 0.27, Price = 131072000 },
        [19] = { BonusRatio = 0.285, Price = 262144000 },
        [20] = { BonusRatio = 0.3, Price = 524288000 },
        [21] = { BonusRatio = 0.315, Price = 1048576000 },
        [22] = { BonusRatio = 0.33, Price = 2097152000 },
        [23] = { BonusRatio = 0.345, Price = 4194304000 },
        [24] = { BonusRatio = 0.36, Price = 8388608000 },
        [25] = { BonusRatio = 0.375, Price = 16777216000 },
        [26] = { BonusRatio = 0.39, Price = 33554432000 },
        [27] = { BonusRatio = 0.405, Price = 67108864000 },
        [28] = { BonusRatio = 0.42, Price = 134217728000 },
        [29] = { BonusRatio = 0.435, Price = 268435456000 },
        [30] = { BonusRatio = 0.45, Price = 536870912000 },
        [31] = { BonusRatio = 0.465, Price = 1073741824000 },
        [32] = { BonusRatio = 0.48, Price = 2147483648000 },
        [33] = { BonusRatio = 0.495, Price = 4294967296000 },
        [34] = { BonusRatio = 0.51, Price = 8589934592000 },
        [35] = { BonusRatio = 0.525, Price = 17179869184000 },
        [36] = { BonusRatio = 0.54, Price = 34359738368000 },
        [37] = { BonusRatio = 0.555, Price = 68719476736000 },
        [38] = { BonusRatio = 0.57, Price = 137438953472000 },
        [39] = { BonusRatio = 0.585, Price = 274877906944000 },
        [40] = { BonusRatio = 0.6, Price = 549755813888000 },
        [41] = { BonusRatio = 0.615, Price = 1099511627776000 },
        [42] = { BonusRatio = 0.63, Price = 2199023255552000 },
        [43] = { BonusRatio = 0.645, Price = 4398046511104000 },
        [44] = { BonusRatio = 0.66, Price = 8796093022208000 },
        [45] = { BonusRatio = 0.675, Price = 17592186044416000 },
        [46] = { BonusRatio = 0.69, Price = 35184372088832000 },
        [47] = { BonusRatio = 0.705, Price = 70368744177664000 },
        [48] = { BonusRatio = 0.72, Price = 140737488355328000 },
        [49] = { BonusRatio = 0.735, Price = 281474976710656000 },
        [50] = { BonusRatio = 0.75, Price = 562949953421312000 },
    },
}

local MAX_LEVEL = {
    [1] = 20,
    [2] = 30,
    [3] = 50,
    [4] = 50,
}

function UpgradeConfig.GetTypeIds()
    return UpgradeConfig.TYPE_ORDER
end

function UpgradeConfig.GetTypeName(typeId)
    return UpgradeConfig.TYPE_NAME[tonumber(typeId)] or ""
end

function UpgradeConfig.GetDevProductId(typeId)
    return UpgradeConfig.DEV_PRODUCT_IDS[tonumber(typeId)]
end

function UpgradeConfig.GetTypeByDevProductId(productId)
    local target = tonumber(productId)
    if not target then
        return nil
    end
    for typeId, id in pairs(UpgradeConfig.DEV_PRODUCT_IDS) do
        if tonumber(id) == target then
            return typeId
        end
    end
    return nil
end

function UpgradeConfig.GetMaxLevel(typeId)
    return MAX_LEVEL[tonumber(typeId)] or 0
end

function UpgradeConfig.GetLevelConfig(typeId, level)
    local t = tonumber(typeId)
    local lv = tonumber(level)
    if not t or not lv then
        return nil
    end
    local cfgByType = LEVEL_CONFIG[t]
    if not cfgByType then
        return nil
    end
    return cfgByType[lv]
end

function UpgradeConfig.GetInitialLevel(typeId)
    local t = tonumber(typeId)
    if not t or not LEVEL_CONFIG[t] then
        return 0
    end
    if LEVEL_CONFIG[t][0] then
        return 0
    end
    return 1
end

function UpgradeConfig.FormatBonusPercent(ratio)
    local value = (tonumber(ratio) or 0) * 100
    if math.abs(value - math.floor(value + 0.5)) < 0.001 then
        return string.format("+%d%%", math.floor(value + 0.5))
    end
    local text = string.format("%.1f", value)
    text = string.gsub(text, "%.0$", "")
    return "+" .. text .. "%"
end

return UpgradeConfig
