--[[
脚本名称: UnitConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/UnitConfig
]]

--[[
兵种配置模块
职责: 存储所有兵种的配置信息,提供兵种数据查询接口
]]

local UnitConfig = {}

-- 内部缓存：从模型推导出的占地尺寸
UnitConfig._DerivedGridCache = {}

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
    -- V2.0占地尺寸配置 (支持任意矩形):
    -- 方式1: GridWidth + GridDepth (推荐,支持非正方形如1x2, 2x3, 4x7)
    -- 方式2: GridSize (向后兼容,表示正方形边长,如GridSize=2表示2x2)
    --
    -- 坐标轴说明 (俯视IdleFloor):
    --   GridWidth = X轴方向(水平)占用格子数
    --   GridDepth = Z轴方向(垂直)占用格子数
    --
    -- 示例配置:
    --   GridWidth=2, GridDepth=1 → 横向2格,纵向1格 (水平长条)
    --   GridWidth=1, GridDepth=2 → 横向1格,纵向2格 (垂直长条)
    --   GridWidth=2, GridDepth=3 → 横向2格,纵向3格 (2x3矩形)
    --
    GridWidth = number,        -- X轴方向(水平)占用格子数 (可选,默认1)
    GridDepth = number,        -- Z轴方向(垂直)占用格子数 (可选,默认GridWidth)
    GridSize = number,         -- [向后兼容] 正方形边长 (如果没有GridWidth/GridDepth则使用此值)
    Description = string,      -- 描述
    -- V2.0.2新增UI配置
    Icon = string,             -- 兵种图标资源ID (格式: "rbxassetid://数字" 或留空使用默认图标)
    -- V2.1新增商店配置
    Quality = string,          -- 品质 (Common/Rare/Epic/Legendary)
    -- V1.4新增属性
    BaseHealth = number,       -- 基础生命值
    BaseAttack = number,       -- 基础攻击力
    BaseAttackSpeed = number,  -- 基础攻击速度(每次攻击间隔秒数)
    -- V1.5新增战斗属性
    BaseAttackRange = number,  -- 基础攻击距离(studs)
    BaseMoveSpeed = number,    -- 基础移动速度(studs/秒)
    ProjectileSpeed = number,  -- 弹道速度(studs/秒) 近战填0
    -- V1.5.2新增: 完整动作系统
    ShowAnimationId = string,  -- 展示动画ID (放置在IdleFloor上时循环播放)
    IdleAnimationId = string,  -- 待机动画ID (战斗中两次攻击之间播放)
    MoveAnimationId = string,  -- 移动动画ID (如果为空则不播放)
    AttackAnimationId = string,-- 普通攻击动画ID
    DeathAnimationId = string, -- 死亡动画ID (V1.5.2新增, 如果为空则不播放)
    WeaponName = string,       -- 武器名称(模型中的Tool或Part名称)
    -- V1.5远程子弹配置
    ProjectileModelPath = string,  -- 子弹模型路径(可选,相对于ReplicatedStorage)
                                   -- 例如: "Projectiles/Arrow" 会从 ReplicatedStorage/Projectiles/Arrow Clone模型
                                   -- 如果不填，则使用CombatProfile.ProjectileConfig配置生成
    -- V1.6寻路配置
    PathfindingAgentRadius = number,  -- 寻路代理半径(studs) - 决定单位是否能穿过狭窄通道
    PathfindingAgentHeight = number,  -- 寻路代理高度(studs) - 决定单位是否能穿过低矮空间
    PathfindingAgentCanJump = boolean, -- 是否允许跳跃寻路
}

-- V1.5.1 CombatProfile结构
CombatProfile = {
    -- 近战碰撞配置
    HitboxRadius = number,         -- 碰撞半径(studs)
    HitboxAngle = number,          -- 扇形角度(度)
    HitboxHeight = number,         -- 碰撞高度(studs)
    HitboxMaxTargets = number,     -- 最大命中数
    UseAnimationEvent = boolean,   -- 是否使用动画事件
    AnimationEventName = string,   -- 动画事件名称
    ContactOffset = number,        -- 武器长度补偿(studs) - 影响AI停靠距离
    HitboxShape = string,          -- 命中体积形状: "Sphere"|"Box"|"Capsule"(默认Sphere)
    HitboxPartName = string,       -- 体积绑定的部件名(如Weapon/RightHand), 优先Attachment
    HitboxAttachmentName = string, -- 部件下的Attachment名，用其世界CFrame做命中源
    HitboxOffset = Vector3,        -- 命中源的局部偏移(右、上、前)
    HitboxLength = number,         -- 命中体积前向长度(用于Capsule/Box)
    HitboxBoxSize = Vector3,       -- 直接指定盒子尺寸(可选)

    -- V1.5远程子弹属性配置(当ProjectileModelPath为空时使用)
    ProjectileConfig = {
        Shape = string,            -- 形状: "Ball"(球体), "Block"(方块), "Cylinder"(圆柱)
        Size = Vector3,            -- 大小
        Color = Color3,            -- 颜色
        Material = string,         -- 材质: "Neon", "Plastic", "Wood", "Slate"等
        EnableTrail = boolean,     -- 是否启用拖尾特效(可选)
        TrailColor = Color3,       -- 拖尾颜色(可选)
        TrailLifetime = number,    -- 拖尾持续时间(可选,默认0.5秒)
    }
}
]]

-- ==================== 兵种配置表 ====================
-- 所有兵种的配置数据
UnitConfig.Units = {
	-- 10001: Rookie
	["10001"] = {
		UnitId = "10001",
		Name = "Rookie",
		ModelPath = "Role/Basic/Noob",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 100,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "基础近战",
		Icon = "rbxassetid://98616255072587",
		Quality = "Common",
		BaseHealth = 100,
		BaseAttack = 20,
		BaseAttackSpeed = 1,
		BaseAttackRange = 4,
		BaseMoveSpeed = 16,
		ProjectileSpeed = 0,
		ShowAnimationId = "77493219283554",
		IdleAnimationId = "83868414255967",
		MoveAnimationId = "138827448254225",
		AttackAnimationId = "109394128574270",
		DeathAnimationId = "106491337612930",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10002: Bat Thug
	["10002"] = {
		UnitId = "10002",
		Name = "Bat Thug",
		ModelPath = "Role/Stick/Baseball",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 120,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "突击手",
		Icon = "rbxassetid://133527593486392",
		Quality = "Common",
		BaseHealth = 80,
		BaseAttack = 25,
		BaseAttackSpeed = 0.8,
		BaseAttackRange = 5,
		BaseMoveSpeed = 18,
		ProjectileSpeed = 0,
		ShowAnimationId = "126093915205268",
		IdleAnimationId = "81785478265966",
		MoveAnimationId = "116782623852733",
		AttackAnimationId = "94774180560893",
		DeathAnimationId = "138976818120142",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10003: Pot Lid
	["10003"] = {
		UnitId = "10003",
		Name = "Pot Lid",
		ModelPath = "Role/Shield/CarThief",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 250,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "主坦克",
		Icon = "rbxassetid://114892183819195",
		Quality = "Common",
		BaseHealth = 350,
		BaseAttack = 10,
		BaseAttackSpeed = 1.5,
		BaseAttackRange = 4,
		BaseMoveSpeed = 12,
		ProjectileSpeed = 0,
		ShowAnimationId = "99124852185123",
		IdleAnimationId = "93833104502127",
		MoveAnimationId = "100464525349954",
		AttackAnimationId = "129070884392025",
		DeathAnimationId = "83615027736898",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10004: Pistol Boy
	["10004"] = {
		UnitId = "10004",
		Name = "Pistol Boy",
		ModelPath = "Role/Handgun/Mafia",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 150,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "中程游侠",
		Icon = "rbxassetid://80744151898936",
		Quality = "Common",
		BaseHealth = 70,
		BaseAttack = 15,
		BaseAttackSpeed = 0.5,
		BaseAttackRange = 25,
		BaseMoveSpeed = 16,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "123569664244954",
		MoveAnimationId = "89625134198433",
		AttackAnimationId = "71584419812250",
		DeathAnimationId = "89589936667002",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10005: Patrol Cop
	["10005"] = {
		UnitId = "10005",
		Name = "Patrol Cop",
		ModelPath = "Role/Basic/Rookie",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 280,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "基础近战",
		Icon = "rbxassetid://80710637196540",
		Quality = "Rare",
		BaseHealth = 200,
		BaseAttack = 35,
		BaseAttackSpeed = 0.9,
		BaseAttackRange = 4,
		BaseMoveSpeed = 16,
		ProjectileSpeed = 0,
		ShowAnimationId = "77493219283554",
		IdleAnimationId = "83868414255967",
		MoveAnimationId = "138827448254225",
		AttackAnimationId = "109394128574270",
		DeathAnimationId = "106491337612930",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10006: Pipe Girl
	["10006"] = {
		UnitId = "10006",
		Name = "Pipe Girl",
		ModelPath = "Role/Stick/Mama",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 300,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "突击手",
		Icon = "rbxassetid://123524507681699",
		Quality = "Rare",
		BaseHealth = 150,
		BaseAttack = 45,
		BaseAttackSpeed = 0.7,
		BaseAttackRange = 5,
		BaseMoveSpeed = 20,
		ProjectileSpeed = 0,
		ShowAnimationId = "126093915205268",
		IdleAnimationId = "81785478265966",
		MoveAnimationId = "116782623852733",
		AttackAnimationId = "94774180560893",
		DeathAnimationId = "138976818120142",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10007: Baton Cop
	["10007"] = {
		UnitId = "10007",
		Name = "Baton Cop",
		ModelPath = "Role/Stick/Batons",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 320,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "突击手",
		Icon = "rbxassetid://96910755166910",
		Quality = "Rare",
		BaseHealth = 180,
		BaseAttack = 40,
		BaseAttackSpeed = 0.8,
		BaseAttackRange = 5,
		BaseMoveSpeed = 18,
		ProjectileSpeed = 0,
		ShowAnimationId = "126093915205268",
		IdleAnimationId = "81785478265966",
		MoveAnimationId = "116782623852733",
		AttackAnimationId = "94774180560893",
		DeathAnimationId = "138976818120142",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10008: Mechanic
	["10008"] = {
		UnitId = "10008",
		Name = "Mechanic",
		ModelPath = "Role/Shield/Worker",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 400,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "主坦克",
		Icon = "rbxassetid://87038735300763",
		Quality = "Rare",
		BaseHealth = 600,
		BaseAttack = 20,
		BaseAttackSpeed = 1.5,
		BaseAttackRange = 4,
		BaseMoveSpeed = 11,
		ProjectileSpeed = 0,
		ShowAnimationId = "99124852185123",
		IdleAnimationId = "93833104502127",
		MoveAnimationId = "100464525349954",
		AttackAnimationId = "129070884392025",
		DeathAnimationId = "83615027736898",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10009: Girl Recruit
	["10009"] = {
		UnitId = "10009",
		Name = "Girl Recruit",
		ModelPath = "Role/Rifle/MP5",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 350,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "远程狙击",
		Icon = "rbxassetid://123162348831885",
		Quality = "Rare",
		BaseHealth = 100,
		BaseAttack = 60,
		BaseAttackSpeed = 1.5,
		BaseAttackRange = 40,
		BaseMoveSpeed = 14,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "117596019027541",
		MoveAnimationId = "100229633875328",
		AttackAnimationId = "101758639653079",
		DeathAnimationId = "110134141960466",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10010: Muscle Prisoner
	["10010"] = {
		UnitId = "10010",
		Name = "Muscle Prisoner",
		ModelPath = "Role/Tank/Beast",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 500,
		GridSize = 2,
		GridWidth = 2,
		GridDepth = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "重装战士",
		Icon = "rbxassetid://74819350235405",
		Quality = "Elite",
		BaseHealth = 800,
		BaseAttack = 50,
		BaseAttackSpeed = 1.2,
		BaseAttackRange = 6,
		BaseMoveSpeed = 14,
		ProjectileSpeed = 0,
		ShowAnimationId = "102006932904665",
		IdleAnimationId = "78740129238259",
		MoveAnimationId = "78458547323575",
		AttackAnimationId = "115842197325390",
		DeathAnimationId = "116288968318130",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10011: Heavy Cop
	["10011"] = {
		UnitId = "10011",
		Name = "Heavy Cop",
		ModelPath = "Role/Tank/Enforcer",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 600,
		GridSize = 2,
		GridWidth = 2,
		GridDepth = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "重装战士",
		Icon = "rbxassetid://75652304417710",
		Quality = "Elite",
		BaseHealth = 900,
		BaseAttack = 55,
		BaseAttackSpeed = 1.1,
		BaseAttackRange = 6,
		BaseMoveSpeed = 14,
		ProjectileSpeed = 0,
		ShowAnimationId = "102006932904665",
		IdleAnimationId = "78740129238259",
		MoveAnimationId = "78458547323575",
		AttackAnimationId = "115842197325390",
		DeathAnimationId = "116288968318130",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10012: Sailor Girl
	["10012"] = {
		UnitId = "10012",
		Name = "Sailor Girl",
		ModelPath = "Role/Stick/Athlete",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 550,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "突击手",
		Icon = "rbxassetid://130658905780133",
		Quality = "Elite",
		BaseHealth = 300,
		BaseAttack = 80,
		BaseAttackSpeed = 0.6,
		BaseAttackRange = 6,
		BaseMoveSpeed = 20,
		ProjectileSpeed = 0,
		ShowAnimationId = "126093915205268",
		IdleAnimationId = "81785478265966",
		MoveAnimationId = "116782623852733",
		AttackAnimationId = "94774180560893",
		DeathAnimationId = "138976818120142",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10013: Florida
	["10013"] = {
		UnitId = "10013",
		Name = "Florida",
		ModelPath = "Role/Handgun/Florida",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 550,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "中程游侠",
		Icon = "rbxassetid://140057693756084",
		Quality = "Elite",
		BaseHealth = 200,
		BaseAttack = 25,
		BaseAttackSpeed = 0.3,
		BaseAttackRange = 28,
		BaseMoveSpeed = 16,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "123569664244954",
		MoveAnimationId = "89625134198433",
		AttackAnimationId = "71584419812250",
		DeathAnimationId = "89589936667002",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10014: Shotgun Cop
	["10014"] = {
		UnitId = "10014",
		Name = "Shotgun Cop",
		ModelPath = "Role/Rifle/Shotgun",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 600,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "中程游侠",
		Icon = "rbxassetid://109694053639716",
		Quality = "Elite",
		BaseHealth = 250,
		BaseAttack = 100,
		BaseAttackSpeed = 1.5,
		BaseAttackRange = 20,
		BaseMoveSpeed = 15,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "117596019027541",
		MoveAnimationId = "100229633875328",
		AttackAnimationId = "101758639653079",
		DeathAnimationId = "110134141960466",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10015: Boxer
	["10015"] = {
		UnitId = "10015",
		Name = "Boxer",
		ModelPath = "Role/Basic/Hitter",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 900,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "基础近战",
		Icon = "rbxassetid://129425310745524",
		Quality = "Epic",
		BaseHealth = 600,
		BaseAttack = 70,
		BaseAttackSpeed = 0.5,
		BaseAttackRange = 4,
		BaseMoveSpeed = 18,
		ProjectileSpeed = 0,
		ShowAnimationId = "77493219283554",
		IdleAnimationId = "83868414255967",
		MoveAnimationId = "138827448254225",
		AttackAnimationId = "109394128574270",
		DeathAnimationId = "106491337612930",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10016: Riot FBI
	["10016"] = {
		UnitId = "10016",
		Name = "Riot FBI",
		ModelPath = "Role/Shield/FBI",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 1200,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "主坦克",
		Icon = "rbxassetid://88477019377142",
		Quality = "Epic",
		BaseHealth = 2000,
		BaseAttack = 40,
		BaseAttackSpeed = 1.4,
		BaseAttackRange = 4,
		BaseMoveSpeed = 10,
		ProjectileSpeed = 0,
		ShowAnimationId = "99124852185123",
		IdleAnimationId = "93833104502127",
		MoveAnimationId = "100464525349954",
		AttackAnimationId = "129070884392025",
		DeathAnimationId = "83615027736898",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10017: Gangster
	["10017"] = {
		UnitId = "10017",
		Name = "Gangster",
		ModelPath = "Role/Rifle/AK47",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 1000,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "远程狙击",
		Icon = "rbxassetid://96684518109328",
		Quality = "Epic",
		BaseHealth = 150,
		BaseAttack = 300,
		BaseAttackSpeed = 2.5,
		BaseAttackRange = 55,
		BaseMoveSpeed = 13,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "117596019027541",
		MoveAnimationId = "100229633875328",
		AttackAnimationId = "101758639653079",
		DeathAnimationId = "110134141960466",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10018: Tattoo Heavy
	["10018"] = {
		UnitId = "10018",
		Name = "Tattoo Heavy",
		ModelPath = "Role/Tank/Tank",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 2200,
		GridSize = 2,
		GridWidth = 2,
		GridDepth = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "重装战士",
		Icon = "rbxassetid://107612488818992",
		Quality = "Legendary",
		BaseHealth = 3000,
		BaseAttack = 150,
		BaseAttackSpeed = 1.1,
		BaseAttackRange = 7,
		BaseMoveSpeed = 13,
		ProjectileSpeed = 0,
		ShowAnimationId = "102006932904665",
		IdleAnimationId = "78740129238259",
		MoveAnimationId = "78458547323575",
		AttackAnimationId = "115842197325390",
		DeathAnimationId = "116288968318130",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10019: Yakuza
	["10019"] = {
		UnitId = "10019",
		Name = "Yakuza",
		ModelPath = "Role/Stick/Samurai",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 2000,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "突击手",
		Icon = "rbxassetid://127241024884061",
		Quality = "Legendary",
		BaseHealth = 800,
		BaseAttack = 200,
		BaseAttackSpeed = 0.7,
		BaseAttackRange = 6,
		BaseMoveSpeed = 22,
		ProjectileSpeed = 0,
		ShowAnimationId = "126093915205268",
		IdleAnimationId = "81785478265966",
		MoveAnimationId = "116782623852733",
		AttackAnimationId = "94774180560893",
		DeathAnimationId = "138976818120142",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10020: Cowboy
	["10020"] = {
		UnitId = "10020",
		Name = "Cowboy",
		ModelPath = "Role/Handgun/Cowboy",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 2500,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "中程游侠",
		Icon = "rbxassetid://78069816818003",
		Quality = "Legendary",
		BaseHealth = 500,
		BaseAttack = 120,
		BaseAttackSpeed = 0.4,
		BaseAttackRange = 30,
		BaseMoveSpeed = 18,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "123569664244954",
		MoveAnimationId = "89625134198433",
		AttackAnimationId = "71584419812250",
		DeathAnimationId = "89589936667002",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10021: Psycho
	["10021"] = {
		UnitId = "10021",
		Name = "Psycho",
		ModelPath = "Role/Basic/OG",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 4000,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "基础近战",
		Icon = "rbxassetid://102001177844916",
		Quality = "Mythic",
		BaseHealth = 1500,
		BaseAttack = 300,
		BaseAttackSpeed = 0.8,
		BaseAttackRange = 5,
		BaseMoveSpeed = 20,
		ProjectileSpeed = 0,
		ShowAnimationId = "77493219283554",
		IdleAnimationId = "83868414255967",
		MoveAnimationId = "138827448254225",
		AttackAnimationId = "109394128574270",
		DeathAnimationId = "106491337612930",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10022: SWAT
	["10022"] = {
		UnitId = "10022",
		Name = "SWAT",
		ModelPath = "Role/Rifle/S.W.A.T",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 4500,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "远程狙击",
		Icon = "rbxassetid://86449419798698",
		Quality = "Mythic",
		BaseHealth = 1000,
		BaseAttack = 100,
		BaseAttackSpeed = 0.1,
		BaseAttackRange = 50,
		BaseMoveSpeed = 10,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "117596019027541",
		MoveAnimationId = "100229633875328",
		AttackAnimationId = "101758639653079",
		DeathAnimationId = "110134141960466",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10023: Robocop
	["10023"] = {
		UnitId = "10023",
		Name = "Robocop",
		ModelPath = "Role/Handgun/Robocop",
		Type = UnitConfig.UnitType.RANGED,
		BaseLevel = 1,
		Price = 4800,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "中程游侠",
		Icon = "rbxassetid://96284212262078",
		Quality = "Mythic",
		BaseHealth = 2500,
		BaseAttack = 200,
		BaseAttackSpeed = 0.3,
		BaseAttackRange = 32,
		BaseMoveSpeed = 14,
		ProjectileSpeed = 200,
		ShowAnimationId = "101776339545224",
		IdleAnimationId = "123569664244954",
		MoveAnimationId = "89625134198433",
		AttackAnimationId = "71584419812250",
		DeathAnimationId = "89589936667002",
		WeaponName = "Weapon",
		ProjectileModelPath = "Bullet/BaseBullet",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10024: Juggernaut
	["10024"] = {
		UnitId = "10024",
		Name = "Juggernaut",
		ModelPath = "Role/Shield/Sapper",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 8000,
		GridSize = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "主坦克",
		Icon = "rbxassetid://102620601082371",
		Quality = "Godly",
		BaseHealth = 12000,
		BaseAttack = 300,
		BaseAttackSpeed = 1.5,
		BaseAttackRange = 5,
		BaseMoveSpeed = 9,
		ProjectileSpeed = 0,
		ShowAnimationId = "99124852185123",
		IdleAnimationId = "93833104502127",
		MoveAnimationId = "100464525349954",
		AttackAnimationId = "129070884392025",
		DeathAnimationId = "83615027736898",
		WeaponName = "Weapon",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 5,
			HitboxAngle = 90,
			HitboxHeight = 8,
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

	-- 10025: Titan Police
	["10025"] = {
		UnitId = "10025",
		Name = "Titan Police",
		ModelPath = "Role/Tank/Muscular",
		Type = UnitConfig.UnitType.MELEE,
		BaseLevel = 1,
		Price = 8800,
		GridSize = 2,
		GridWidth = 2,
		GridDepth = 1,
		KillReward = 5,  -- V3.4: 基础击杀金币奖励
		Description = "重装战士",
		Icon = "rbxassetid://105156254180465",
		Quality = "Godly",
		BaseHealth = 8000,
		BaseAttack = 600,
		BaseAttackSpeed = 1,
		BaseAttackRange = 8,
		BaseMoveSpeed = 15,
		ProjectileSpeed = 0,
		ShowAnimationId = "102006932904665",
		IdleAnimationId = "78740129238259",
		MoveAnimationId = "78458547323575",
		AttackAnimationId = "115842197325390",
		DeathAnimationId = "116288968318130",
		WeaponName = "",
		ProjectileModelPath = "",
		CombatProfile = {
			HitboxRadius = 3.2,           -- 拳头命中球半径(稍大容错)
			HitboxAngle = 120,            -- 挥拳扇区
			HitboxHeight = 6,             -- 身体中部高度覆盖
			HitboxMaxTargets = 1,
			UseAnimationEvent = true,
			AnimationEventName = "Damage",
			ContactOffset = 0.8,          -- 拳头前伸补偿
			HitboxShape = "Sphere",
			HitboxPartName = "RightHand", -- 没有武器，用右手为命中源
			HitboxAttachmentName = "",
			HitboxOffset = Vector3.new(0, 0, 0),
			HitboxLength = 0,
			HitboxBoxSize = nil,
		},
		PathfindingAgentRadius = 2,
		PathfindingAgentHeight = 5,
		PathfindingAgentCanJump = true,
	},

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

-- ==================== V2.0新增: 占地尺寸接口 ====================

--[[
获取兵种的占地宽度(X轴方向格子数)
V2.0新增: 支持任意矩形占地
@param unitId string - 兵种ID
@return number - 占地宽度(格子数),默认1
]]
function UnitConfig.GetGridWidth(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData then
		return 1
	end
	-- 新规则：显式配置优先；未配置宽度时默认1（单列），仅在宽/深/GridSize都缺失时尝试模型推导
	if unitData.GridWidth then
		return unitData.GridWidth
	end

	local derivedW = nil
	if not unitData.GridSize and not unitData.GridDepth then
		derivedW = UnitConfig._GetDerivedGrid(unitData, "Width")
	end

	return derivedW or 1
end

--[[
获取兵种的占地深度(Z轴方向格子数)
V2.0新增: 支持任意矩形占地
@param unitId string - 兵种ID
@return number - 占地深度(格子数),默认等于宽度
]]
function UnitConfig.GetGridDepth(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData then
		return 1
	end
	-- 新规则：显式配置优先；否则使用GridSize作为深度(默认1xN竖排)；否则尝试模型推导；最后默认1
	if unitData.GridDepth then
		return unitData.GridDepth
	end

	local derivedD = nil
	if not unitData.GridWidth and not unitData.GridSize then
		derivedD = UnitConfig._GetDerivedGrid(unitData, "Depth")
	end

	return unitData.GridSize or derivedD or 1
end

--[[
获取兵种的占地尺寸(宽度和深度)
V2.0新增: 返回两个值,支持任意矩形
@param unitId string - 兵种ID
@return number, number - GridWidth, GridDepth
]]
function UnitConfig.GetGridDimensions(unitId)
	return UnitConfig.GetGridWidth(unitId), UnitConfig.GetGridDepth(unitId)
end

--[[
获取兵种的占地总格子数(用于显示/排序等)
V2.0新增
@param unitId string - 兵种ID
@return number - 总格子数 (GridWidth * GridDepth)
]]
function UnitConfig.GetGridArea(unitId)
	local w, d = UnitConfig.GetGridDimensions(unitId)
	return w * d
end

--[[
检查兵种是否为正方形占地
V2.0新增
@param unitId string - 兵种ID
@return boolean - 是否为正方形
]]
function UnitConfig.IsSquareGrid(unitId)
	local w, d = UnitConfig.GetGridDimensions(unitId)
	return w == d
end

--[[
内部工具: 从模型推导占地尺寸(仅在未配置宽/深时使用)
@param unitData table
@param key string "Width"|"Depth"
@return number|nil
]]
function UnitConfig._GetDerivedGrid(unitData, key)
	if not unitData or not unitData.ModelPath then
		return nil
	end

	if UnitConfig._DerivedGridCache[unitData.UnitId] then
		return UnitConfig._DerivedGridCache[unitData.UnitId][key]
	end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local PlacementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PlacementConfig"))

	local pathParts = string.split(tostring(unitData.ModelPath), "/")
	local current = ReplicatedStorage
	for i = 1, #pathParts - 1 do
		current = current:FindFirstChild(pathParts[i])
		if not current then
			return nil
		end
	end

	local model = current and current:FindFirstChild(pathParts[#pathParts])
	if not model or not model:IsA("Model") then
		return nil
	end

	local _, size = model:GetBoundingBox()
	local cell = PlacementConfig.GRID_UNIT_SIZE or 4
	local width = math.max(1, math.ceil(size.X / cell))
	local depth = math.max(1, math.ceil(size.Z / cell))

	UnitConfig._DerivedGridCache[unitData.UnitId] = {Width = width, Depth = depth}
	return UnitConfig._DerivedGridCache[unitData.UnitId][key]
end

-- ==================== 基础信息接口 ====================

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
获取死亡动画ID (V1.5.2新增)
@param unitId string - 兵种ID
@return string - 动画ID
]]
function UnitConfig.GetDeathAnimationId(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.DeathAnimationId then
		return ""
	end
	return unitData.DeathAnimationId
end

--[[
获取展示动画ID (V1.5.2新增)
@param unitId string - 兵种ID
@return string - 动画ID
]]
function UnitConfig.GetShowAnimationId(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.ShowAnimationId then
		return ""
	end
	return unitData.ShowAnimationId
end

--[[
获取待机动画ID (V1.5.2新增)
@param unitId string - 兵种ID
@return string - 动画ID
]]
function UnitConfig.GetIdleAnimationId(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.IdleAnimationId then
		return ""
	end
	return unitData.IdleAnimationId
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
		HitboxShape = "Sphere",
		HitboxPartName = "",
		HitboxAttachmentName = "",
		HitboxOffset = Vector3.new(0, 0, 0),
		HitboxLength = 0,
		HitboxBoxSize = nil,
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

-- 获取命中形状
function UnitConfig.GetHitboxShape(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxShape
end

-- 获取命中体积绑定的部件名
function UnitConfig.GetHitboxPartName(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxPartName
end

-- 获取命中体积绑定的Attachment名
function UnitConfig.GetHitboxAttachmentName(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxAttachmentName
end

-- 获取命中体积偏移
function UnitConfig.GetHitboxOffset(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxOffset
end

-- 获取命中体积长度
function UnitConfig.GetHitboxLength(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxLength
end

-- 获取命中体积盒子尺寸
function UnitConfig.GetHitboxBoxSize(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.HitboxBoxSize
end

-- 获取接触补偿
function UnitConfig.GetContactOffset(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)
	return profile.ContactOffset
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

--[[
获取子弹模型路径(远程单位专用)
@param unitId string - 兵种ID
@return string|nil - 子弹模型路径，如果没有配置则返回nil
]]
function UnitConfig.GetProjectileModelPath(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData then
		return nil
	end
	return unitData.ProjectileModelPath
end

--[[
获取子弹配置(远程单位专用)
@param unitId string - 兵种ID
@return table - 子弹配置，如果没有配置则返回默认配置
]]
function UnitConfig.GetProjectileConfig(unitId)
	local profile = UnitConfig.GetCombatProfile(unitId)

	-- 默认子弹配置
	local defaultConfig = {
		Shape = "Ball",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Color = Color3.fromRGB(255, 255, 0),  -- 黄色
		Material = "Neon",
		EnableTrail = false,
		TrailColor = Color3.fromRGB(255, 255, 255),
		TrailLifetime = 0.5,
	}

	-- 如果有配置ProjectileConfig，合并配置
	if profile.ProjectileConfig then
		-- 合并用户配置和默认配置
		for key, value in pairs(profile.ProjectileConfig) do
			defaultConfig[key] = value
		end
	end

	return defaultConfig
end

-- ==================== V2.0.2新增: UI配置接口 ====================

--[[
获取兵种图标资源ID
@param unitId string - 兵种ID
@return string - 图标资源ID (格式: "rbxassetid://数字")
]]
function UnitConfig.GetIcon(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.Icon or unitData.Icon == "" then
		return "rbxassetid://0"  -- 返回默认图标
	end
	return unitData.Icon
end

-- ==================== V2.1新增: 商店配置接口 ====================

--[[
获取兵种品质
@param unitId string - 兵种ID
@return string - 品质（Common/Rare/Epic/Legendary）
]]
function UnitConfig.GetQuality(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.Quality then
		return "Common"  -- 默认品质
	end
	return unitData.Quality
end

-- ==================== V3.4新增: 击杀金币奖励接口 ====================

--[[
获取兵种的基础击杀金币奖励
V3.4新增: 杀死敌方兵种时获得的金币
@param unitId string - 兵种ID
@return number - 基础击杀金币奖励,默认5
]]
function UnitConfig.GetKillReward(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or not unitData.KillReward then
		return 5  -- 默认击杀金币
	end
	return unitData.KillReward
end

--[[
获取兵种的击杀金币奖励(根据等级计算)
V3.4新增: 1级兵就是基础值,2级兵就是金币基础数*2,3级兵就是金币基础数*3
@param unitId string - 兵种ID
@param level number - 兵种等级
@return number - 实际击杀金币奖励
]]
function UnitConfig.GetKillRewardByLevel(unitId, level)
	local baseReward = UnitConfig.GetKillReward(unitId)
	local unitLevel = level or 1
	return baseReward * unitLevel
end

-- ==================== V1.6新增: 寻路配置接口 ====================

--[[
获取寻路代理半径
V1.6.3修复：没有配置时返回nil，让UnitAI使用自动计算的值
@param unitId string - 兵种ID
@return number|nil - 寻路代理半径，nil表示使用自动计算
]]
function UnitConfig.GetPathfindingAgentRadius(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or unitData.PathfindingAgentRadius == nil then
		return nil  -- 返回nil，让UnitAI自动计算
	end
	return unitData.PathfindingAgentRadius
end

--[[
获取寻路代理高度
V1.6.3修复：没有配置时返回nil，让UnitAI使用自动计算的值
@param unitId string - 兵种ID
@return number|nil - 寻路代理高度，nil表示使用自动计算
]]
function UnitConfig.GetPathfindingAgentHeight(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or unitData.PathfindingAgentHeight == nil then
		return nil  -- 返回nil，让UnitAI自动计算
	end
	return unitData.PathfindingAgentHeight
end

--[[
获取是否允许跳跃寻路
V1.6.3修复：没有配置时返回nil，让UnitAI使用自动判断
@param unitId string - 兵种ID
@return boolean|nil - 是否允许跳跃，nil表示使用Humanoid的Jump状态
]]
function UnitConfig.GetPathfindingAgentCanJump(unitId)
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData or unitData.PathfindingAgentCanJump == nil then
		return nil  -- 返回nil，让UnitAI自动判断
	end
	return unitData.PathfindingAgentCanJump
end

return UnitConfig
