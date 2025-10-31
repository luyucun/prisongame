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
    -- V1.5新增战斗属性
    BaseAttackRange = number,  -- 基础攻击距离(studs)
    BaseMoveSpeed = number,    -- 基础移动速度(studs/秒)
    ProjectileSpeed = number,  -- 弹道速度(studs/秒) 近战填0
    MoveAnimationId = string,  -- 移动动画ID (如果为空则不播放)
    AttackAnimationId = string,-- 普通攻击动画ID
    WeaponName = string,       -- 武器名称(模型中的Tool或Part名称)
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
		-- V1.5新增战斗属性
		BaseAttackRange = 5,    -- 近战攻击距离5 studs
		BaseMoveSpeed = 16,     -- 移动速度16 studs/秒
		ProjectileSpeed = 0,    -- 近战无弹道
		MoveAnimationId = 180426354,   -- 移动动画ID (从角色Animate脚本的run中获取, 为空则不播放)
		AttackAnimationId = 109394128574270, -- 攻击动画ID (如果为空则使用Humanoid默认动作, 格式: "12345678")
		WeaponName = "Sword",   -- 武器名称
		-- V1.5.1新增战斗配置
		CombatProfile = {
			HitboxRadius = 5,          -- 碰撞半径(studs)
			HitboxAngle = 90,          -- 扇形角度(度,90表示前方90度扇形)
			HitboxHeight = 8,          -- 碰撞高度(studs)
			HitboxMaxTargets = 1,      -- 最大命中数(单体攻击)
			UseAnimationEvent = true,  -- 使用动画事件驱动伤害
			AnimationEventName = "Damage", -- 动画事件名称
			ContactOffset = 0,         -- 武器长度补偿(studs) - 长武器正值,拳头0
		},
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
		-- V1.5新增战斗属性
		BaseAttackRange = 5,    -- 近战攻击距离5 studs
		BaseMoveSpeed = 16,     -- 移动速度16 studs/秒
		ProjectileSpeed = 0,    -- 近战无弹道
		MoveAnimationId = "",   -- 移动动画ID (从角色Animate脚本的run中获取, 为空则不播放)
		AttackAnimationId = "", -- 攻击动画ID (如果为空则使用Humanoid默认动作, 格式: "12345678")
		WeaponName = "Sword",   -- 武器名称
		-- V1.5.1新增战斗配置
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,         -- 武器长度补偿(studs)
		},
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

-- ==================== V1.5新增: 战斗属性获取接口 ====================

--[[
获取兵种攻击距离(不受等级影响)
@param unitId string - 兵种ID
@return number - 攻击距离
]]
function UnitConfig.GetAttackRange(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.BaseAttackRange then
		return 5  -- 默认5 studs
	end
	return unitData.BaseAttackRange
end

--[[
获取兵种移动速度(不受等级影响)
@param unitId string - 兵种ID
@return number - 移动速度
]]
function UnitConfig.GetMoveSpeed(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.BaseMoveSpeed then
		return 16  -- 默认16 studs/秒
	end
	return unitData.BaseMoveSpeed
end

--[[
获取弹道速度(不受等级影响)
@param unitId string - 兵种ID
@return number - 弹道速度 (0表示近战)
]]
function UnitConfig.GetProjectileSpeed(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.ProjectileSpeed then
		return 0  -- 默认近战
	end
	return unitData.ProjectileSpeed
end

--[[
获取攻击动画ID
@param unitId string - 兵种ID
@return string - 动画ID
]]
function UnitConfig.GetAttackAnimationId(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.AttackAnimationId then
		return ""
	end
	return unitData.AttackAnimationId
end

--[[
获取移动动画ID
@param unitId string - 兵种ID
@return string - 动画ID
]]
function UnitConfig.GetMoveAnimationId(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.MoveAnimationId then
		return ""
	end
	return unitData.MoveAnimationId
end

--[[
获取武器名称
@param unitId string - 兵种ID
@return string - 武器名称
]]
function UnitConfig.GetWeaponName(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.WeaponName then
		return "Sword"  -- 默认为Sword
	end
	return unitData.WeaponName
end

--[[
检查是否为远程单位
@param unitId string - 兵种ID
@return boolean - 是否为远程单位
]]
function UnitConfig.IsRangedUnit(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData then
		return false
	end
	return unitData.Type == UnitConfig.UnitType.RANGED
end

--[[
检查是否为近战单位
@param unitId string - 兵种ID
@return boolean - 是否为近战单位
]]
function UnitConfig.IsMeleeUnit(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData then
		return false
	end
	return unitData.Type == UnitConfig.UnitType.MELEE
end

-- ==================== V1.5.1新增: 战斗配置接口 ====================

--[[
获取兵种的战斗配置
@param unitId string - 兵种ID
@return table - 战斗配置 {HitboxRadius, HitboxAngle, HitboxHeight, HitboxMaxTargets, UseAnimationEvent, AnimationEventName}
]]
function UnitConfig.GetCombatProfile(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)

	-- 默认配置
	local defaultProfile = {
		HitboxRadius = 5,
		HitboxAngle = 90,
		HitboxHeight = 8,
		HitboxMaxTargets = 1,
		UseAnimationEvent = true,
		AnimationEventName = "Damage",
		ContactOffset = 0,         -- 默认无武器补偿
	}

	if not unitData then
		return defaultProfile
	end

	-- 如果没有配置CombatProfile,返回默认值
	if not unitData.CombatProfile then
		return defaultProfile
	end

	-- 合并配置(使用配置的值,未配置的使用默认值)
	local profile = {}
	for key, defaultValue in pairs(defaultProfile) do
		profile[key] = unitData.CombatProfile[key] or defaultValue
	end

	return profile
end

--[[
获取碰撞半径
@param unitId string - 兵种ID
@return number - 碰撞半径
]]
function UnitConfig.GetHitboxRadius(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxRadius
end

--[[
获取扇形角度
@param unitId string - 兵种ID
@return number - 扇形角度(度数)
]]
function UnitConfig.GetHitboxAngle(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxAngle
end

--[[
获取碰撞高度
@param unitId string - 兵种ID
@return number - 碰撞高度
]]
function UnitConfig.GetHitboxHeight(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxHeight
end

--[[
获取最大命中目标数
@param unitId string - 兵种ID
@return number - 最大命中数
]]
function UnitConfig.GetHitboxMaxTargets(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxMaxTargets
end

--[[
检查是否使用动画事件
@param unitId string - 兵种ID
@return boolean - 是否使用动画事件
]]
function UnitConfig.UseAnimationEvent(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.UseAnimationEvent
end

--[[
获取动画事件名称
@param unitId string - 兵种ID
@return string - 动画事件名称
]]
function UnitConfig.GetAnimationEventName(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.AnimationEventName
end

return UnitConfig
