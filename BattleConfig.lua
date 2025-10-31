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
BattleConfig.MOVE_STOP_TOLERANCE = 1

return BattleConfig
