--[[
脚本名称: BattleConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/BattleConfig
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
BattleConfig.AI_BATCH_UPDATE_INTERVAL = 0.1  -- 从0.2降低到0.1，提升响应性

-- 目标搜索范围(studs)
BattleConfig.TARGET_SEARCH_RANGE = 200

-- ==================== 寻路系统配置 V1.6 ====================
-- 寻路超时时间(秒)
BattleConfig.PATHFINDING_TIMEOUT = 5

-- 路径重算冷却时间(秒) - 避免频繁重建路径
BattleConfig.PATH_RECALC_COOLDOWN = 0.6  -- 从0.5提高到0.6，减少重算频率

-- V2.3性能优化：大幅提高目标移动阈值，减少频繁重算
-- 从6提高到35，与PathService的TARGET_MOVE_THRESHOLD对齐
BattleConfig.PATH_TARGET_MOVE_THRESHOLD = 35

-- Waypoint到达阈值(studs) - 距离waypoint小于此值视为到达
BattleConfig.WAYPOINT_REACH_THRESHOLD = 2

-- 路径失败最大重试次数
BattleConfig.PATH_MAX_RETRY_COUNT = 3

-- 路径重试延迟(秒)
BattleConfig.PATH_RETRY_DELAY = 1

-- MoveToFinished超时时间(秒)
BattleConfig.MOVE_TO_TIMEOUT = 3

-- 是否显示路径调试可视化
BattleConfig.DEBUG_SHOW_PATH = false

-- 路径点可视化颜色
BattleConfig.PATH_WAYPOINT_COLOR = Color3.fromRGB(0, 255, 255)  -- 青色

-- 路径线可视化颜色
BattleConfig.PATH_LINE_COLOR = Color3.fromRGB(255, 255, 0)  -- 黄色

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

-- 是否显示近战命中体积(调试用)
BattleConfig.DEBUG_SHOW_MELEE_HITBOX = false
BattleConfig.DEBUG_HITBOX_DURATION = 0.15
BattleConfig.DEBUG_HITBOX_COLOR_GOOD = Color3.fromRGB(0, 255, 0)
BattleConfig.DEBUG_HITBOX_COLOR_BAD = Color3.fromRGB(255, 0, 0)

-- 是否输出AI详细日志
BattleConfig.DEBUG_AI_LOGS = false

-- 是否输出战斗详细日志
BattleConfig.DEBUG_COMBAT_LOGS = false

-- ==================== 动画设置 ====================
-- 默认移动动画速度
BattleConfig.DEFAULT_MOVE_ANIMATION_SPEED = 1

-- 默认攻击动画速度
BattleConfig.DEFAULT_ATTACK_ANIMATION_SPEED = 1

-- V1.5.2新增: 死亡动画配置
BattleConfig.DEATH_ANIMATION_DURATION = 3.0  -- 死亡动画播放时长(秒)，用于延迟移除模型（最小等待时间）
BattleConfig.DEFAULT_DEATH_ANIMATION_SPEED = 1  -- 默认死亡动画速度

-- V1.5.6新增: 死亡后保持终帧时间
BattleConfig.DEATH_POST_HOLD = 0.5  -- 死亡动画播完后额外保持的时间(秒)，让玩家看清倒地姿势
BattleConfig.MIN_DEATH_DISPLAY_TIME = 3.0  -- 死亡后最少显示时间(秒)，确保尸体至少停留3秒

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
BattleConfig.HITBOX_DEFAULT_RADIUS = 3       -- 默认碰撞半径(更贴近手/武器厚度)
BattleConfig.HITBOX_DEFAULT_ANGLE = 90       -- 默认扇形角度
BattleConfig.HITBOX_DEFAULT_HEIGHT = 6       -- 默认碰撞高度(身高一半偏下)
BattleConfig.HITBOX_DEFAULT_MAX_TARGETS = 1  -- 默认最大命中数

-- 性能优化配置
BattleConfig.UNIT_POSITION_UPDATE_THRESHOLD = 3  -- 单位位置更新阈值(studs)
BattleConfig.HITBOX_SAME_FRAME_COOLDOWN = 0.05   -- 同帧命中冷却(秒)

-- 攻击超时配置
BattleConfig.ATTACK_TIMEOUT = 8              -- 攻击阶段超时时间(秒,防止动画失败卡死,从5调至8秒以适应较长的攻击动画或网络波动)
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
-- 建议值: 0.3-0.8 (越大越远)
BattleConfig.CONTACT_BUFFER = 0.5

-- 最小停靠距离(studs) - 防止计算结果为负
BattleConfig.MIN_DOCKING_DISTANCE = 0.5

-- 进入/退出攻击的距离容差(近战专用)
BattleConfig.ATTACK_ENTER_TOLERANCE = 0.75
BattleConfig.ATTACK_EXIT_TOLERANCE = 1.25

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

-- ==================== 远程单位距离阈值配置（V1.5.2重构优化） ====================
-- 核心原则：三层阈值形成梯度，避免AI状态机抖动
--
-- 🔧 V1.5.2 关键修复：增大停靠距离，避免双方互相穿越导致绕圈
--
-- 问题根源：当双方都朝对方移动时，停靠距离15太小，双方会互相穿越
-- 解决方案：增大停靠距离到0.85（17 studs），给予足够的"刹车距离"
--
-- 阈值设计逻辑（攻击距离20为例）：
-- 1. 停靠距离：17 studs (0.85) - 足够远，避免双方互相穿越
-- 2. 进入阈值：19 studs (0.95) - 接近停靠距离就进入攻击
-- 3. 脱离阈值：22 studs (1.1) - 给予一定滞后空间

-- 远程单位的停靠距离(相对于攻击距离)
-- 🔧 V1.5.3 从0.85降低到0.65，让远程单位停得更远
-- 攻击距离20时，停靠距离=13 studs，给予足够的"安全距离"避免互相穿越
BattleConfig.RANGED_DOCKING_RATIO = 0.65

-- 远程单位进入ATTACKING状态的阈值(相对于攻击距离)
-- 🔧 V1.5.3 从0.95降低到0.75，与新的停靠距离(0.65)拉开差距，形成缓冲区
-- 攻击距离20时，进入阈值=15 studs，停靠距离=13 studs，有2 studs缓冲
BattleConfig.RANGED_ENTER_ATTACK_RATIO = 0.75

-- 远程单位脱离ATTACKING状态的阈值(相对于攻击距离)
-- 保持1.1不变
BattleConfig.RANGED_EXIT_ATTACK_RATIO = 1.1

-- 射程优势阈值(studs) - 当射程差大于此值时认为有显著优势
BattleConfig.RANGE_ADVANTAGE_THRESHOLD = 3

-- 射程劣势阈值(studs) - 当射程差小于此负值时认为有显著劣势
BattleConfig.RANGE_DISADVANTAGE_THRESHOLD = -3

-- 优势单位保持距离缓冲(studs) - 优势单位在攻击距离前保持的距离
BattleConfig.RANGE_ADVANTAGE_BUFFER = 2

-- 劣势单位积极接近距离(studs) - 劣势单位开始积极接近的阈值
BattleConfig.RANGE_DISADVANTAGE_APPROACH_DISTANCE = 5

-- ==================== V1.5.4 武器特效配置 ====================
-- Beam特效持续时间(秒)
BattleConfig.WEAPON_EFFECT_BEAM_DURATION = 0.1

-- PointLight特效持续时间(秒)
BattleConfig.WEAPON_EFFECT_LIGHT_DURATION = 0.1

-- ParticleEmitter特效持续时间(秒)
BattleConfig.WEAPON_EFFECT_PARTICLE_DURATION = 0.5

-- 是否显示武器特效调试日志
BattleConfig.DEBUG_WEAPON_EFFECTS = false

return BattleConfig
