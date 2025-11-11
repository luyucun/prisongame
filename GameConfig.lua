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

-- ==================== 玩家相关配置 ====================
-- 服务器最大玩家数量
GameConfig.MAX_PLAYERS = 6

-- 玩家初始货币配置
GameConfig.INITIAL_COINS = 100

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
	MaxStages = 10,                      -- 最大关卡数
	StageGenerateOffset = 169,           -- 关卡Z轴间距(studs)
	MoveTimeout = 30,                    -- 移动超时(秒)
	ArrivalThreshold = 8,                -- 到达阈值(studs) - V2.0修复：放宽到8，避免因敌人存在导致无法到达
	RespawnEffectDuration = 0.3,         -- 重生特效时长(秒)
	StageTemplateStyle = "Style01",      -- 模板风格
	MarchWaitTime = 1,                   -- 到达关卡后等待时间(秒)
	StageClearWaitTime = 2,              -- 关卡完成后等待时间(秒)
	VictoryWaitTime = 3,                 -- 胜利后等待时间(秒)
	DefeatWaitTime = 3,                  -- 失败后等待时间(秒)

	-- V2.0.1新增：Stage001初始坐标配置（Base的Position）
	Stage001Positions = {
		[1] = Vector3.new(0, 0.5, -185.999),
		[2] = Vector3.new(-120, 0.5, -184),
		[3] = Vector3.new(-240, 0.5, -184),
		[4] = Vector3.new(-360, 0.5, -184),
		[5] = Vector3.new(-480, 0.5, -184),
		[6] = Vector3.new(-600, 0.5, -184),
	}
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

-- ==================== 调试配置 ====================
-- 是否启用调试模式
GameConfig.DEBUG_MODE = true

-- 调试日志前缀
GameConfig.LOG_PREFIX = "[PrisonGame]"

return GameConfig
