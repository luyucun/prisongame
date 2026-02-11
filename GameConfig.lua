--[[
脚本名称: GameConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/GameConfig
]]

--[[
游戏配置模块
职责: 存储游戏的所有常量和配置参数
]]

local GameConfig = {}

-- ==================== 数据存储配置 ====================
-- Studio与线上数据隔离开关
-- 当为true时，Studio环境会使用独立的DataStore（名称追加_Studio后缀）
-- 发布到线上前可以设置为false来使用相同的DataStore（不推荐）
GameConfig.USE_STUDIO_DATASTORE_SUFFIX = true

-- ==================== 玩家相关配置 ====================
-- 服务器最大玩家数量
GameConfig.MAX_PLAYERS = 6

-- 玩家初始货币配置
GameConfig.INITIAL_COINS = 0

-- ==================== 基地相关配置 ====================
-- 基地数量(对应玩家数量)
GameConfig.HOME_COUNT = 6

-- 基地编号范围
GameConfig.MIN_HOME_SLOT = 1
GameConfig.MAX_HOME_SLOT = 6

-- 基地父级文件夹名称
GameConfig.HOME_FOLDER_NAME = "Home"

-- 基地名称前缀
GameConfig.HOME_PREFIX = "PlayerHome"

-- 出生点名称
GameConfig.SPAWN_LOCATION_NAME = "SpawnLocation"

-- ==================== 货币相关配置 ====================
-- 货币类型
GameConfig.CurrencyType = {
	COINS = "Coins"  -- 金币
}

-- 货币显示格式
GameConfig.COIN_DISPLAY_FORMAT = "$%d"  -- $XXXXX格式

-- ==================== 好友金币加成配置 (V5.8) ====================
GameConfig.FriendCoinBonusRates = {
	[1] = 0.2,
	[2] = 0.4,
	[3] = 0.6,
	[4] = 0.8,
	[5] = 1.0,
}
GameConfig.FriendCoinBonusMaxCount = 5

-- ==================== 复活配置 (V5.9) ====================
GameConfig.Revive = {
	MaxChapter = 3,
	ProductIdsByChapter = {
		[1] = 3517019111,
		[2] = 3517019352,
		[3] = 3517019548,
	},
	PricesByChapter = {
		[1] = 9,
		[2] = 29,
		[3] = 79,
	},
}

-- ==================== UI相关配置 ====================
-- 主界面GUI名称
GameConfig.MAIN_GUI_NAME = "MainGui"

-- 金币显示TextLabel名称
GameConfig.COIN_DISPLAY_NAME = "CoinNum"

-- ==================== 放置系统配置 (V1.2) ====================
-- IdleFloor名称
GameConfig.IDLE_FLOOR_NAME = "IdleFloor"

-- 放置确认UI名称
GameConfig.PUT_CONFIRM_GUI_NAME = "PutConfirm"

-- ==================== 战役系统配置 (V2.0) ====================
-- 战役关卡配置
GameConfig.Campaign = {
	MaxStages = 30,                       -- 最大关卡数
	StageGenerateOffset = 170,           -- 关卡Z轴间距(studs)
	MoveTimeout = 30,                    -- 移动超时(秒)
	ArrivalThreshold = 8,                -- 到达阈值(studs) - V2.0修复：放宽到8，避免因敌人存在导致无法到达
	RespawnEffectDuration = 0.3,         -- 重生特效时长(秒)
	StageTemplateStyle = "Style01",      -- 模板风格
	MarchWaitTime = 1,                   -- 到达关卡后等待时间(秒)
	StageClearWaitTime = 2,              -- 关卡完成后等待时间(秒)
	VictoryWaitTime = 3,                 -- 胜利后等待时间(秒)
	DefeatWaitTime = 3,                  -- 失败后等待时间(秒)

	-- V2.0.1新增：Stage001初始坐标配置（Base的Position）
	-- 默认坐标（保留向后兼容），当Style未配置时使用
	Stage001Positions = {
		[1] = Vector3.new(0, 0.5, -184),
		[2] = Vector3.new(-120, 0.5, -184),
		[3] = Vector3.new(-240, 0.5, -184),
		[4] = Vector3.new(-360, 0.5, -184),
		[5] = Vector3.new(-480, 0.5, -184),
		[6] = Vector3.new(-600, 0.5, -184),
	},

	-- V3.7扩展：每个Style风格独立的Stage001坐标配置
	-- 键名为Style名称（如"Style01", "Style02"），值为与Stage001Positions相同格式的坐标表
	-- 如果某个Style未配置，则回退使用默认的Stage001Positions
	Stage001PositionsByStyle = {
		-- Style01的坐标（与默认坐标相同）
		["Style01"] = {
			[1] = Vector3.new(0, 0.5, -184),
			[2] = Vector3.new(-120, 0.5, -184),
			[3] = Vector3.new(-240, 0.5, -184),
			[4] = Vector3.new(-360, 0.5, -184),
			[5] = Vector3.new(-480, 0.5, -184),
			[6] = Vector3.new(-600, 0.5, -184),
		},

		-- Style02的坐标（请根据实际模板调整）
		["Style02"] = {
			[1] = Vector3.new(-0.316, 0.992, -158.269),
			[2] = Vector3.new(-120.316, 0.992, -158.269),
			[3] = Vector3.new(-240.316, 0.992, -158.269),
			[4] = Vector3.new(-360.316, 0.992, -158.269),
			[5] = Vector3.new(-480.316, 0.992, -158.269),
			[6] = Vector3.new(-600.316, 0.992, -158.269),
		},
		
		-- Style03的坐标（请根据实际模板调整）
		["Style03"] = {
			[1] = Vector3.new(-0.316, 0.992, -158.269),
			[2] = Vector3.new(-120.316, 0.992, -158.269),
			[3] = Vector3.new(-240.316, 0.992, -158.269),
			[4] = Vector3.new(-360.316, 0.992, -158.269),
			[5] = Vector3.new(-480.316, 0.992, -158.269),
			[6] = Vector3.new(-600.316, 0.992, -158.269),
		},
		
		-- Style04的坐标（请根据实际模板调整）
		["Style04"] = {
			[1] = Vector3.new(-0.316, 0.992, -158.269),
			[2] = Vector3.new(-120.316, 0.992, -158.269),
			[3] = Vector3.new(-240.316, 0.992, -158.269),
			[4] = Vector3.new(-360.316, 0.992, -158.269),
			[5] = Vector3.new(-480.316, 0.992, -158.269),
			[6] = Vector3.new(-600.316, 0.992, -158.269),
		},

		-- Style05的坐标（请根据实际模板调整）
		["Style05"] = {
			[1] = Vector3.new(-0.316, 0.992, -158.269),
			[2] = Vector3.new(-120.316, 0.992, -158.269),
			[3] = Vector3.new(-240.316, 0.992, -158.269),
			[4] = Vector3.new(-360.316, 0.992, -158.269),
			[5] = Vector3.new(-480.316, 0.992, -158.269),
			[6] = Vector3.new(-600.316, 0.992, -158.269),
		},
	},

	-- V2.4新增：寻路卡住检测参数（Watchdog机制）
	StuckDetectionThreshold = 0.2,   -- studs（单位移动距离少于这个）
	StuckDetectionWindow = 0.8,      -- seconds（时间窗口）
	StuckDetectionMinDistance = 5,   -- studs（距离目标大于这个才认定卡住）

	-- V2.4新增：调试开关
	EnablePathDebugLogs = false,     -- 详细寻路日志
	EnableAIDebugLogs = false,       -- 详细AI日志
}

-- ==================== 门控系统配置 (V2.0.1) ====================
GameConfig.Door = {
	TweenDuration = 1,                       -- 动画时长(秒)
	LeftOpenAngle = 90,                      -- 左门打开角度(度)
	RightOpenAngle = -90,                    -- 右门打开角度(度)
	ClosedAngle = 0,                         -- 关闭角度(度)
	EasingStyle = Enum.EasingStyle.Quad,     -- 缓动样式
	EasingDirection = Enum.EasingDirection.InOut  -- 缓动方向
}

-- ==================== 商店系统配置 (V2.1) ====================
GameConfig.Shop = {
	NPCName = "KeepShoper01",            -- 默认商店NPC名称
	OpenDistance = 11,                   -- 触发距离(studs) - V2.1修复：从15缩短约25%到11
	CheckInterval = 0.2,                 -- 距离检测间隔(秒)
	PurchaseCooldown = 0.3,              -- 购买冷却(秒)
	EnableDistanceCheck = true,          -- 是否启用服务端距离校验
	FallbackToUnitConfig = true,         -- ShopConfig缺失时是否回退到UnitConfig

	-- 库存系统配置 (V2.1库存功能)
	DefaultRefreshInterval = 300,        -- 默认库存刷新间隔(秒) 5分钟
	RefreshTimerUpdateInterval = 1,      -- 刷新倒计时更新间隔(秒)
	EnableStockSystem = true,            -- 是否启用库存系统

	-- V6.8 快速补货配置（囚犯商店）
	FastRestock = {
		ProductId = 3530358099,           -- 开发者商品ID
		ReducedInterval = 180,            -- 加速后刷新间隔(秒) 3分钟
		DurationSeconds = 900,            -- 持续时长(秒) 15分钟
		AdjustSeconds = 120,              -- 购买/到期时对倒计时的加减秒数(2分钟)
	},
}

-- ==================== UI配置 (V2.1) ====================
GameConfig.UI = GameConfig.UI or {}
GameConfig.UI.CoinRollDuration = 0.8     -- 金币滚动动画时长(秒)
GameConfig.UI.ButtonScaleDown = 0.9      -- 按钮按下缩放比例
GameConfig.UI.ButtonScaleDuration = 0.1  -- 按钮缩放动画时长(秒)
GameConfig.UI.QualityColors = {
	Common = Color3.fromRGB(0, 255, 0),      -- 灰色
	Rare = Color3.fromRGB(0, 255, 255),          -- 青色
	Elite = Color3.fromRGB(170, 0, 255),           -- 绿色
	Epic = Color3.fromRGB(255, 80, 0),          -- 紫色
	Legendary = Color3.fromRGB(255, 0, 0),      -- 橙色
	Mythic = Color3.fromRGB(255, 255, 255),          -- 红色
	Godly = Color3.fromRGB(255, 255, 255),       -- 白色
}

-- ==================== 挂机金币配置 (V2.6) ====================
GameConfig.IdleCoin = {
	CoinsPerMinute = 8,                  -- 每分钟产出金币数 🔥V3.9.3修改：从20改为10
	MaxOfflineHours = 24,                 -- 最大离线产出小时数
	MaxOfflineMinutes = 24 * 60,          -- 最大离线产出分钟数(6小时=360分钟)
	ProximityTriggerDistance = 8,         -- 触发交互的距离(studs)
	ProximityHoldDuration = 0.6,          -- 长按确认时长(秒)
	ParticleEffectDuration = 1,           -- 粒子特效持续时长(秒)
	-- 🔥V3.9.3新增：在线挂机金币配置
	OnlineAccumulateInterval = 60,        -- 在线累计间隔(秒)，每60秒累计一次
}

-- ==================== 战斗金币配置 (V3.4) ====================
GameConfig.BattleCoin = {
	-- 前进金币配置
	AdvanceDistance = 10,                -- 战场中心每前进多少studs获得一次金币
	AdvanceReward = 3,                   -- 每次前进获得的金币数

	-- 击杀金币说明(实际在UnitConfig中配置每个兵种的KillReward)
-- 1级兵就是配置的基础值
-- 2级兵就是金币基础数*2
-- 3级兵就是金币基础数*3
-- 4级兵就是金币基础数*4
-- 5级兵就是金币基础数*5
	DefaultKillReward = 5,               -- 默认击杀金币(如果兵种未配置KillReward)
}

-- ==================== 调试配置 ====================
-- 是否启用调试模式
GameConfig.DEBUG_MODE = false

-- 调试日志前缀
GameConfig.LOG_PREFIX = "[PrisonGame]"

return GameConfig
