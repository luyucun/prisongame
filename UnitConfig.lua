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

return UnitConfig
