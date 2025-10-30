--[[
脚本名称: UnitConfig
脚本类型: ModuleScript (服务端配置)
脚本位置: ServerScriptService/Config/UnitConfig
]]

--[[
兵种配置模块
职责: 存储所有兵种的配置信息,提供兵种数据查询接口
]]

local UnitConfig = {}

-- ==================== 兵种类型枚举 ====================
UnitConfig.UnitType = {
    MELEE = "Melee",      -- 近战单位
    RANGED = "Ranged",    -- 远程单位
}

-- ==================== 等级配置 V1.4 ====================
UnitConfig.MAX_LEVEL = 3  -- 最高等级

-- 等级系数配置
UnitConfig.LevelCoefficients = {
    [1] = 1,      -- 1级系数: 1.0
    [2] = 1.2,    -- 2级系数: 1.2
    [3] = 1.5,    -- 3级系数: 1.5
}

-- ==================== 兵种数据结构 ====================
--[[
UnitData = {
    UnitId = string,           -- 兵种唯一ID
    Name = string,             -- 兵种名称
    ModelPath = string,        -- 模型路径(相对于ReplicatedStorage)
    Type = string,             -- 兵种类型(Melee/Ranged)
    BaseLevel = number,        -- 基础等级(1-6)
    Price = number,            -- 购买价格(金币)
    GridSize = number,         -- 占地面积(格子数:1或4)
    Description = string,      -- 描述
    -- V1.4新增属性
    BaseHealth = number,       -- 基础生命值
    BaseAttack = number,       -- 基础攻击力
    BaseAttackSpeed = number,  -- 基础攻击速度(每次攻击间隔秒数)
}
]]

-- ==================== 兵种配置表 ====================
-- 所有兵种的配置数据
UnitConfig.Units = {
    -- 兵种1: Noob
    ["Noob"] = {
        UnitId = "Noob",
        Name = "Noob",
        ModelPath = "Role/Basic/Noob",  -- 相对于ReplicatedStorage
        Type = UnitConfig.UnitType.MELEE,
        BaseLevel = 1,
        Price = 100,
        GridSize = 1,
        Description = "最基础的近战单位,适合新手使用",
        -- V1.4新增属性
        BaseHealth = 100,       -- 基础生命值
        BaseAttack = 10,        -- 基础攻击力
        BaseAttackSpeed = 1,    -- 基础攻击速度(1秒/次)
    },

    -- 兵种2: Rookie
    ["Rookie"] = {
        UnitId = "Rookie",
        Name = "Rookie",
        ModelPath = "Role/Basic/Rookie",
        Type = UnitConfig.UnitType.MELEE,
        BaseLevel = 1,
        Price = 200,
        GridSize = 1,
        Description = "进阶的近战单位,比Noob更强力",
        -- V1.4新增属性
        BaseHealth = 100,       -- 基础生命值
        BaseAttack = 10,        -- 基础攻击力
        BaseAttackSpeed = 1,    -- 基础攻击速度(1秒/次)
    },

    -- 后续可以继续添加更多兵种...
    -- ["UnitId"] = { ... },
}

-- ==================== 公共接口 ====================

--[[
根据UnitId获取兵种配置
@param unitId string - 兵种ID
@return table|nil - 兵种配置数据,不存在返回nil
]]
function UnitConfig.GetUnitById(unitId)
    return UnitConfig.Units[unitId]
end

--[[
检查兵种是否存在
@param unitId string - 兵种ID
@return boolean - 是否存在
]]
function UnitConfig.IsValidUnit(unitId)
    return UnitConfig.Units[unitId] ~= nil
end

--[[
获取所有兵种ID列表
@return table - 所有兵种ID数组
]]
function UnitConfig.GetAllUnitIds()
    local unitIds = {}
    for unitId, _ in pairs(UnitConfig.Units) do
        table.insert(unitIds, unitId)
    end
    return unitIds
end

--[[
根据等级获取所有兵种
@param level number - 等级
@return table - 该等级的所有兵种数组
]]
function UnitConfig.GetUnitsByLevel(level)
    local units = {}
    for _, unitData in pairs(UnitConfig.Units) do
        if unitData.BaseLevel == level then
            table.insert(units, unitData)
        end
    end
    return units
end

--[[
根据类型获取所有兵种
@param unitType string - 兵种类型(Melee/Ranged)
@return table - 该类型的所有兵种数组
]]
function UnitConfig.GetUnitsByType(unitType)
    local units = {}
    for _, unitData in pairs(UnitConfig.Units) do
        if unitData.Type == unitType then
            table.insert(units, unitData)
        end
    end
    return units
end

--[[
获取所有兵种配置
@return table - 所有兵种配置表
]]
function UnitConfig.GetAllUnits()
    return UnitConfig.Units
end

--[[
验证兵种价格是否足够
@param unitId string - 兵种ID
@param playerCoins number - 玩家金币数量
@return boolean - 是否足够购买
]]
function UnitConfig.CanAfford(unitId, playerCoins)
    local unitData = UnitConfig.GetUnitById(unitId)
    if not unitData then
        return false
    end
    return playerCoins >= unitData.Price
end

-- ==================== V1.4新增: 属性计算接口 ====================

--[[
计算兵种实际生命值
@param unitId string - 兵种ID
@param level number - 等级
@return number - 实际生命值
]]
function UnitConfig.CalculateHealth(unitId, level)
    local unitData = UnitConfig.GetUnitById(unitId)
    if not unitData or not unitData.BaseHealth then
        return 0
    end

    local coefficient = UnitConfig.LevelCoefficients[level] or 1
    return unitData.BaseHealth * level * coefficient
end

--[[
计算兵种实际攻击力
@param unitId string - 兵种ID
@param level number - 等级
@return number - 实际攻击力
]]
function UnitConfig.CalculateAttack(unitId, level)
    local unitData = UnitConfig.GetUnitById(unitId)
    if not unitData or not unitData.BaseAttack then
        return 0
    end

    local coefficient = UnitConfig.LevelCoefficients[level] or 1
    return unitData.BaseAttack * level * coefficient
end

--[[
获取兵种攻击速度(不受等级影响)
@param unitId string - 兵种ID
@return number - 攻击速度
]]
function UnitConfig.GetAttackSpeed(unitId)
    local unitData = UnitConfig.GetUnitById(unitId)
    if not unitData or not unitData.BaseAttackSpeed then
        return 1
    end
    return unitData.BaseAttackSpeed
end

--[[
检查是否可以升级
@param level number - 当前等级
@return boolean - 是否可以升级
]]
function UnitConfig.CanLevelUp(level)
    return level < UnitConfig.MAX_LEVEL
end

--[[
获取等级系数
@param level number - 等级
@return number - 系数
]]
function UnitConfig.GetLevelCoefficient(level)
    return UnitConfig.LevelCoefficients[level] or 1
end

return UnitConfig
