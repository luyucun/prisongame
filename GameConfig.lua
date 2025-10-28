--[[
脚本名称: GameConfig
脚本类型: ModuleScript (服务端配置)
脚本位置: ServerScriptService/Config/GameConfig
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

-- ==================== 调试配置 ====================
-- 是否启用调试模式
GameConfig.DEBUG_MODE = true

-- 调试日志前缀
GameConfig.LOG_PREFIX = "[PrisonGame]"

return GameConfig
