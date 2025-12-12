--[[
=====================================================
脚本名称: PowerConfig.lua
脚本类型: ModuleScript
脚本位置: ReplicatedStorage/Config/PowerConfig
版本: V3.9.2
功能描述: 战斗力系统配置
=====================================================
--]]

local PowerConfig = {}

-- ==================== 战斗力计算公式 ====================
-- 战斗力 (CP/Combat Power) = (HP * 0.15) + (DPS * 2) + (射程 * 2)
-- 其中 DPS = 攻击力 / 攻击速度

-- 战斗力计算权重
PowerConfig.Weights = {
	HP = 0.15,           -- 生命值权重
	DPS = 2,             -- DPS权重
	Range = 2,           -- 射程权重
}

-- ==================== 公共接口 ====================

--[[
	计算单个兵种的战斗力
	@param unitData table - 兵种数据，包含HP/Attack/AttackSpeed/AttackRange
	@return number - 战斗力值
--]]
function PowerConfig.CalculateUnitPower(unitData)
	if not unitData then
		return 0
	end

	local hp = unitData.HP or unitData.Health or 0
	local attack = unitData.Attack or 0
	local attackSpeed = unitData.AttackSpeed or 1
	local attackRange = unitData.AttackRange or 0

	if attackSpeed <= 0 then
		attackSpeed = 1
	end

	local dps = attack / attackSpeed
	local power = (hp * PowerConfig.Weights.HP) +
	              (dps * PowerConfig.Weights.DPS) +
	              (attackRange * PowerConfig.Weights.Range)

	return math.floor(power)
end

--[[
	根据UnitId和Level计算战斗力
	需要从UnitConfig获取基础属性
	@param unitId string - 兵种ID
	@param level number - 兵种等级
	@return number - 战斗力值
--]]
function PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, level)
	if not unitId then
		return 0
	end

	level = level or 1

	local UnitConfig = require(game:GetService("ReplicatedStorage").Config.UnitConfig)

	local baseConfig = UnitConfig.Units[unitId]
	if not baseConfig then
		return 0
	end

	local hp = UnitConfig.CalculateHealth(unitId, level)
	local attack = UnitConfig.CalculateAttack(unitId, level)
	local attackSpeed = baseConfig.BaseAttackSpeed or 1
	local attackRange = baseConfig.BaseAttackRange or 0

	local unitData = {
		HP = hp,
		Attack = attack,
		AttackSpeed = attackSpeed,
		AttackRange = attackRange,
	}

	return PowerConfig.CalculateUnitPower(unitData)
end

--[[
	格式化战斗力数值显示
	@param power number - 战斗力值
	@return string - 格式化后的战斗力字符串
--]]
function PowerConfig.FormatPower(power)
	if not power or power <= 0 then
		return "0"
	end

	if power >= 1000000 then
		return string.format("%.1fM", power / 1000000)
	end

	if power >= 10000 then
		return string.format("%.1fK", power / 1000)
	end

	return tostring(math.floor(power))
end

-- ==================== 导出模块 ====================

return PowerConfig
