--[[
脚本名称: BattleConfig
脚本类型: ModuleScript (服务端配置)
脚本位置: ServerScriptService/Config/BattleConfig
]]

--[[
战斗配置模块
职责: 存储战斗系统的所有常量和配置参数
版本: V1.5
]]

local BattleConfig = {}

-- ==================== 测试区域配置 ====================
-- 战斗测试文件夹路径
BattleConfig.BATTLE_TEST_FOLDER = "BattleTest"

-- 攻击方文件夹名称
BattleConfig.ATTACK_FOLDER = "Attack"

-- 防守方文件夹名称
BattleConfig.DEFENSE_FOLDER = "Defense"

-- 每方生成点数量
BattleConfig.SPAWN_POSITION_COUNT = 5

-- 生成点名称前缀
BattleConfig.POSITION_PREFIX = "Position"

-- ==================== 战斗设置 ====================
-- 最大同时战斗数(对应最多8个玩家)
BattleConfig.MAX_CONCURRENT_BATTLES = 8

-- 战斗结束后清理延迟(秒)
BattleConfig.CLEANUP_DELAY = 3

-- ==================== AI设置 ====================
-- AI更新间隔(秒) 每0.1秒更新一次
BattleConfig.AI_UPDATE_INTERVAL = 0.1

-- AI批量更新间隔(秒) V1.5.1新增 - 用于节流
BattleConfig.AI_BATCH_UPDATE_INTERVAL = 0.2

-- 目标搜索范围(studs)
BattleConfig.TARGET_SEARCH_RANGE = 200

-- 寻路超时时间(秒)
BattleConfig.PATHFINDING_TIMEOUT = 5

-- AI循环检测间隔(秒) 用于主循环
BattleConfig.AI_LOOP_INTERVAL = 0.05

-- ==================== 弹道设置 ====================
-- 弹道更新间隔(秒) 每0.05秒更新一次
BattleConfig.PROJECTILE_UPDATE_INTERVAL = 0.05

-- 弹道最大存活时间(秒)
BattleConfig.PROJECTILE_LIFETIME = 10

-- 弹道大小
BattleConfig.PROJECTILE_SIZE = Vector3.new(0.5, 0.5, 0.5)

-- 弹道颜色
BattleConfig.PROJECTILE_COLOR = Color3.fromRGB(255, 100, 0)  -- 橙色

-- 弹道碰撞检测距离(studs) 当弹道与目标距离小于此值时视为命中
BattleConfig.PROJECTILE_HIT_DISTANCE = 2

-- ==================== 碰撞设置 ====================
-- 兵种碰撞组名称
BattleConfig.UNIT_COLLISION_GROUP = "Units"

-- 弹道碰撞组名称
BattleConfig.PROJECTILE_COLLISION_GROUP = "Projectiles"

-- ==================== 战斗状态枚举 ====================
BattleConfig.BattleState = {
    PREPARING = "Preparing",    -- 准备中
    FIGHTING = "Fighting",      -- 战斗中
    FINISHED = "Finished",      -- 已结束
}

-- 战斗队伍枚举
BattleConfig.Team = {
    ATTACK = "Attack",         -- 攻击方
    DEFENSE = "Defense",       -- 防守方
}

-- ==================== AI状态枚举 ====================
BattleConfig.AIState = {
    IDLE = "Idle",             -- 待机
    SEEKING = "Seeking",       -- 寻找目标
    MOVING = "Moving",         -- 移动到目标
    ATTACKING = "Attacking",   -- 攻击中
    DEAD = "Dead",             -- 死亡
}

-- ==================== 调试设置 ====================
-- 是否显示目标连线(调试用)
BattleConfig.DEBUG_SHOW_TARGET_LINE = false

-- 是否显示攻击范围(调试用)
BattleConfig.DEBUG_SHOW_ATTACK_RANGE = false

-- 是否输出AI详细日志
BattleConfig.DEBUG_AI_LOGS = true

-- 是否输出战斗详细日志
BattleConfig.DEBUG_COMBAT_LOGS = true

-- ==================== 动画设置 ====================
-- 默认移动动画速度
BattleConfig.DEFAULT_MOVE_ANIMATION_SPEED = 1

-- 默认攻击动画速度
BattleConfig.DEFAULT_ATTACK_ANIMATION_SPEED = 1

-- ==================== 战斗机制设置 ====================
-- 近战武器触碰伤害触发延迟(秒) 防止连续触发
BattleConfig.MELEE_DAMAGE_COOLDOWN = 0.1

-- 是否启用兵种之间的碰撞
BattleConfig.ENABLE_UNIT_COLLISION = true

-- 移动到目标时的停止距离容差(studs)
-- V1.5.1优化: 增加容差防止边界摇摆
BattleConfig.MOVE_STOP_TOLERANCE = 2

-- 攻击距离宽容值(studs) - 额外的宽容范围,防止攻击距离边界摇摆
BattleConfig.ATTACK_RANGE_TOLERANCE = 0.5

-- ==================== V1.5.1新增配置 ====================

-- 碰撞判定默认值
BattleConfig.HITBOX_DEFAULT_RADIUS = 5       -- 默认碰撞半径
BattleConfig.HITBOX_DEFAULT_ANGLE = 90       -- 默认扇形角度
BattleConfig.HITBOX_DEFAULT_HEIGHT = 8       -- 默认碰撞高度
BattleConfig.HITBOX_DEFAULT_MAX_TARGETS = 1  -- 默认最大命中数

-- 性能优化配置
BattleConfig.UNIT_POSITION_UPDATE_THRESHOLD = 3  -- 单位位置更新阈值(studs)
BattleConfig.HITBOX_SAME_FRAME_COOLDOWN = 0.05   -- 同帧命中冷却(秒)

-- 攻击超时配置
BattleConfig.ATTACK_TIMEOUT = 5              -- 攻击阶段超时时间(秒,防止动画失败卡死)
BattleConfig.ANIMATION_FALLBACK_RATIO = 0.5  -- 动画回退延迟系数(BaseAttackSpeed * 此值)

-- 动画事件配置
BattleConfig.DEFAULT_ANIMATION_EVENT_NAME = "Damage"  -- 默认动画事件名称

-- 攻击阶段枚举
BattleConfig.AttackPhase = {
	IDLE = "Idle",           -- 空闲,可以开始攻击
	ATTACKING = "Attacking", -- 攻击中(等待Damage事件)
	RECOVERY = "Recovery",   -- 收招阶段(攻击冷却)
}

-- ==================== 近战停靠配置 ====================
-- 避免隔空挥拳,让单位保持合适的战斗距离

-- 接触缓冲距离(studs) - 让单位之间保持合适间距，既不隔空也不贴太紧
-- 建议值: 1.0-1.5 (可根据实际效果调整)
BattleConfig.CONTACT_BUFFER = -1.2

-- 最小停靠距离(studs) - 防止计算结果为负
BattleConfig.MIN_DOCKING_DISTANCE = 0.5

-- ==================== 伤害冒字配置 ====================
-- 伤害数字显示相关配置

-- 是否启用伤害冒字
BattleConfig.ENABLE_DAMAGE_NUMBERS = true

-- 冒字移动距离(studs)
BattleConfig.DAMAGE_NUMBER_RISE_DISTANCE = 3

-- 冒字持续时间(秒)
BattleConfig.DAMAGE_NUMBER_DURATION = 1.5

-- 冒字字体大小
BattleConfig.DAMAGE_NUMBER_TEXT_SIZE = 24

-- 冒字颜色(正常伤害)
BattleConfig.DAMAGE_NUMBER_COLOR = Color3.fromRGB(255, 50, 50)  -- 红色

-- 冒字描边颜色
BattleConfig.DAMAGE_NUMBER_STROKE_COLOR = Color3.fromRGB(0, 0, 0)  -- 黑色

-- 冒字描边粗细
BattleConfig.DAMAGE_NUMBER_STROKE_THICKNESS = 2

-- 冒字随机水平偏移范围(studs)
BattleConfig.DAMAGE_NUMBER_RANDOM_OFFSET_X = 1

-- 冒字随机水平偏移范围(studs)
BattleConfig.DAMAGE_NUMBER_RANDOM_OFFSET_Z = 1

return BattleConfig
