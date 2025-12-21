--[[
=====================================================
脚本名称: SkillConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/SkillConfig.lua
版本: V3.1
=====================================================

功能描述:
- 定义所有技能的基础配置
- 提供技能数据查询接口
- 支持技能类型分类
- V3.1新增: DevProductId字段支持Robux购买
- 可扩展设计，便于添加新技能

=====================================================
]]

local SkillConfig = {}

-- ==================== 技能类型枚举 ====================
SkillConfig.SkillType = {
	DAMAGE = "Damage",      -- 伤害型
	HEALING = "Healing",    -- 治疗型
	BUFF = "Buff",          -- 增益型
}

-- ==================== 效果类型枚举 ====================
SkillConfig.EffectType = {
	INSTANT = "Instant",    -- 即时效果(一次性伤害/治疗)
	DOT = "DamageOverTime", -- 持续伤害
	HOT = "HealOverTime",   -- 持续治疗
	BUFF = "Buff",          -- 增益效果
	DEBUFF = "Debuff",      -- 减益效果
}

-- ==================== 目标类型枚举 ====================
SkillConfig.TargetType = {
	ENEMY = "Enemy",        -- 敌方单位
	ALLY = "Ally",          -- 友方单位
	SELF = "Self",          -- 自身
	ALL = "All",            -- 所有单位
}

-- ==================== 技能配置表 ====================
--[[
技能配置结构说明:
{
	SkillId = number,           -- 技能唯一ID
	Name = string,              -- 技能名称
	ResourceName = string,      -- 资源名(对应ReplicatedStorage/Skills/下的资源)
	Icon = string,              -- 技能图标资源ID
	SkillType = string,         -- 技能类型(使用SkillType枚举)
	EffectType = string,        -- 效果类型(使用EffectType枚举)
	TargetType = string,        -- 目标类型(使用TargetType枚举)
	Range = number,             -- 技能范围(studs直径)

	-- 伤害/治疗相关
	Damage = number?,           -- 即时伤害值(INSTANT类型)
	Healing = number?,          -- 即时治疗值(INSTANT类型)

	-- 持续效果相关(DOT/HOT)
	TickDamage = number?,       -- 每tick伤害值
	TickHealing = number?,      -- 每tick治疗值
	TickInterval = number?,     -- tick间隔(秒)
	Duration = number?,         -- 持续时间(秒)

	-- 增益/减益相关
	BuffType = string?,         -- 增益类型
	BuffValue = number?,        -- 增益数值
	BuffDuration = number?,     -- 增益持续时间(秒)

	-- 特效相关
	EffectDuration = number,    -- 特效显示时长(秒)

	-- V3.1新增: 商店购买相关
	DevProductId = number?,     -- 开发者商品ID（用于Robux购买，0或nil表示未配置）

	-- 扩展字段(便于未来扩展)
	Extra = table?,             -- 额外配置数据
}
]]

SkillConfig.Skills = {
	-- ==================== 技能1：喷水枪 ====================
	[1001] = {
		SkillId = 1001,
		Name = "WaterGun",
		ResourceName = "WaterGun",
		Icon = "rbxassetid://120383806488759",
		SkillType = SkillConfig.SkillType.DAMAGE,
		EffectType = SkillConfig.EffectType.INSTANT,
		TargetType = SkillConfig.TargetType.ENEMY,
		Range = 20,                    -- 直径100studs的圆形范围
		Damage = 400,                   -- 造成100点真实伤害
		EffectDuration = 3,             -- 特效显示3秒
		DevProductId = 3476850130,               -- V3.1: 开发者商品ID（0表示未配置）
		Extra = {
			Description = "对范围内所有敌人造成100点真实伤害",
		},
	},

	-- ==================== 技能2：毒气炸弹 ====================
	[1002] = {
		SkillId = 1002,
		Name = "PoisonGas",
		ResourceName = "PoisonGas",
		Icon = "rbxassetid://108132069408183",
		SkillType = SkillConfig.SkillType.DAMAGE,
		EffectType = SkillConfig.EffectType.INSTANT,
		TargetType = SkillConfig.TargetType.ENEMY,
		Range = 20,                    -- 直径100studs的圆形范围
		Damage = 500,                   -- 造成100点真实伤害
		EffectDuration = 3,             -- 特效显示3秒
		DevProductId = 3476850326,               -- V3.1: 开发者商品ID（0表示未配置）
		Extra = {
			Description = "对范围内所有敌人造成100点真实伤害",
		},
	},

	-- ==================== 技能3：大火 ====================
	[1003] = {
		SkillId = 1003,
		Name = "Molotov",
		ResourceName = "Molotov",
		Icon = "rbxassetid://119660478028982",
		SkillType = SkillConfig.SkillType.DAMAGE,
		EffectType = SkillConfig.EffectType.DOT,
		TargetType = SkillConfig.TargetType.ENEMY,
		Range = 30,                    -- 直径100studs的圆形范围
		TickDamage = 50,                -- 每tick造成20点伤害
		TickInterval = 0.3,             -- 每0.5秒触发一次
		Duration = 4,                   -- 持续4秒
		EffectDuration = 4,             -- 特效显示4秒(与持续时间一致)
		DevProductId = 3476850400,               -- V3.1: 开发者商品ID（0表示未配置）
		Extra = {
			Description = "对范围内所有敌人造成持续伤害，每0.5秒造成20点伤害，持续4秒",
		},
	},
}

-- ==================== 公共接口函数 ====================

--[[
根据技能ID获取技能配置
@param skillId number - 技能ID
@return table|nil - 技能配置表，未找到返回nil
]]
function SkillConfig.GetSkillById(skillId)
	if type(skillId) == "string" then
		skillId = tonumber(skillId)
	end
	return SkillConfig.Skills[skillId]
end

--[[
检查技能ID是否有效
@param skillId number - 技能ID
@return boolean - 是否有效
]]
function SkillConfig.IsValidSkill(skillId)
	if type(skillId) == "string" then
		skillId = tonumber(skillId)
	end
	return SkillConfig.Skills[skillId] ~= nil
end

--[[
获取所有技能ID列表
@return table - 技能ID数组
]]
function SkillConfig.GetAllSkillIds()
	local ids = {}
	for skillId, _ in pairs(SkillConfig.Skills) do
		table.insert(ids, skillId)
	end
	table.sort(ids)
	return ids
end

--[[
根据技能类型获取技能列表
@param skillType string - 技能类型(使用SkillType枚举)
@return table - 符合条件的技能ID数组
]]
function SkillConfig.GetSkillsByType(skillType)
	local result = {}
	for skillId, skillData in pairs(SkillConfig.Skills) do
		if skillData.SkillType == skillType then
			table.insert(result, skillId)
		end
	end
	table.sort(result)
	return result
end

--[[
获取技能名称
@param skillId number - 技能ID
@return string - 技能名称，未找到返回"Unknown"
]]
function SkillConfig.GetSkillName(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.Name or "Unknown"
end

--[[
获取技能图标
@param skillId number - 技能ID
@return string - 图标资源ID，未找到返回空字符串
]]
function SkillConfig.GetSkillIcon(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.Icon or ""
end

--[[
获取技能范围
@param skillId number - 技能ID
@return number - 范围(studs)，未找到返回0
]]
function SkillConfig.GetSkillRange(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.Range or 0
end

--[[
获取技能资源名
@param skillId number - 技能ID
@return string - 资源名，未找到返回空字符串
]]
function SkillConfig.GetSkillResourceName(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.ResourceName or ""
end

--[[
获取技能特效时长
@param skillId number - 技能ID
@return number - 特效时长(秒)，未找到返回3(默认值)
]]
function SkillConfig.GetEffectDuration(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.EffectDuration or 3
end

--[[
检查技能是否为持续伤害类型
@param skillId number - 技能ID
@return boolean - 是否为DOT类型
]]
function SkillConfig.IsDOTSkill(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.EffectType == SkillConfig.EffectType.DOT
end

--[[
检查技能是否为即时伤害类型
@param skillId number - 技能ID
@return boolean - 是否为即时伤害类型
]]
function SkillConfig.IsInstantDamageSkill(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.EffectType == SkillConfig.EffectType.INSTANT and skill.Damage ~= nil
end

--[[
计算DOT技能的总伤害
@param skillId number - 技能ID
@return number - 总伤害值，非DOT技能返回0
]]
function SkillConfig.CalculateDOTTotalDamage(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	if not skill or skill.EffectType ~= SkillConfig.EffectType.DOT then
		return 0
	end

	local tickCount = math.floor(skill.Duration / skill.TickInterval)
	return tickCount * skill.TickDamage
end

--[[
获取技能伤害值(即时伤害技能)
@param skillId number - 技能ID
@return number - 伤害值，未找到或非伤害技能返回0
]]
function SkillConfig.GetSkillDamage(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.Damage or 0
end

--[[
获取DOT技能的tick伤害
@param skillId number - 技能ID
@return number - tick伤害值，非DOT返回0
]]
function SkillConfig.GetTickDamage(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.TickDamage or 0
end

--[[
获取DOT技能的tick间隔
@param skillId number - 技能ID
@return number - tick间隔(秒)，非DOT返回0
]]
function SkillConfig.GetTickInterval(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.TickInterval or 0
end

--[[
获取DOT技能的持续时间
@param skillId number - 技能ID
@return number - 持续时间(秒)，非DOT返回0
]]
function SkillConfig.GetDuration(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.Duration or 0
end

--[[
V3.1新增：获取技能的开发者商品ID
@param skillId number - 技能ID
@return number - DevProductId，未配置返回0
]]
function SkillConfig.GetDevProductId(skillId)
	local skill = SkillConfig.GetSkillById(skillId)
	return skill and skill.DevProductId or 0
end

--[[
V3.1新增：检查技能是否支持Robux购买
@param skillId number - 技能ID
@return boolean - 是否支持Robux购买
]]
function SkillConfig.HasRobuxPurchase(skillId)
	local devProductId = SkillConfig.GetDevProductId(skillId)
	return devProductId and devProductId > 0
end

return SkillConfig
