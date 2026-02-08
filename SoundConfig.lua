--[[
脚本名称: SoundConfig
脚本类型: ModuleScript (共享配置)
脚本位置: ReplicatedStorage/Config/SoundConfig
版本: V3.8
]]

--[[
音效配置模块
职责:
1. 定义所有BGM和音效的资源ID
2. 配置音效的播放参数（音量、循环等）
3. 提供统一的音效资源访问接口
]]

local SoundConfig = {}

-- ==================== BGM配置 ====================
SoundConfig.BGM = {
	-- 通用BGM（非战斗状态）
	Home = {
		SoundId = "rbxassetid://1842908030",
		Name = "Road To War (Underscore Version)",
		Volume = 0.5,
		Looped = true,
		-- SoundService路径: SoundService/BGM/Home/Road To War (Underscore Version)
	},

	-- 战斗BGM
	Battle = {
		SoundId = "rbxassetid://1838627590",
		Name = "Urban Racer (Alt Vs)",
		Volume = 0.5,
		Looped = true,
		-- SoundService路径: SoundService/BGM/Battle/Urban Racer (Alt Vs)
	},
}

-- ==================== 一次性音效配置 ====================
SoundConfig.SFX = {
	-- 领取离线金币音效
	CoinsTrigger = {
		SoundId = "rbxassetid://99023919906775",
		Name = "CoinsTrigger",
		Volume = 0.8,
		Looped = false,
		-- SoundService路径: SoundService/Audio/Common/CoinsTrigger
	},

	-- 胜利结算音效
	Victory = {
		SoundId = "rbxassetid://5205229311",
		Name = "Victory royale",
		Volume = 0.8,
		Looped = false,
		-- SoundService路径: SoundService/Audio/Common/Victory royale
	},

	-- 兵种合成音效
	Merge = {
		SoundId = "rbxassetid://7393525156",
		Name = "Merge",
		Volume = 0.8,
		Looped = false,
		-- SoundService路径: SoundService/Audio/Common/Merge
	},

	-- 金币不足/错误音效
	Error = {
		SoundId = "rbxassetid://8400918001",
		Name = "Error Sound 1",
		Volume = 0.7,
		Looped = false,
		-- SoundService路径: SoundService/Audio/Common/Error Sound 1
	},
	ShopRefresh = {
		SoundId = "rbxassetid://105818371386904",
		Name = "ShopRefreshTip",
		Volume = 0.8,
		Looped = false,
		-- SoundService path: SoundService/Audio/Common/ShopRefreshTip
	},
}

-- ==================== 音效类型枚举 ====================
SoundConfig.SoundType = {
	BGM = "BGM",           -- 背景音乐
	SFX = "SFX",           -- 一次性音效
}

-- ==================== 音效事件类型 ====================
SoundConfig.SoundEvent = {
	-- BGM事件
	PLAY_HOME_BGM = "PlayHomeBGM",
	PLAY_BATTLE_BGM = "PlayBattleBGM",
	STOP_BGM = "StopBGM",

	-- SFX事件
	PLAY_COINS_TRIGGER = "PlayCoinsTrigger",
	PLAY_VICTORY = "PlayVictory",
	STOP_VICTORY = "StopVictory",
	PLAY_MERGE = "PlayMerge",
	PLAY_ERROR = "PlayError",
}

-- ==================== 配置参数 ====================
SoundConfig.Settings = {
	-- BGM切换淡入淡出时间（秒）
	BGMFadeDuration = 0.5,

	-- 默认主音量
	MasterVolume = 1.0,

	-- BGM音量
	BGMVolume = 0.5,

	-- SFX音量
	SFXVolume = 0.8,
}

-- ==================== 辅助函数 ====================

--[[
获取BGM配置
@param bgmKey string - BGM键名（"Home" 或 "Battle"）
@return table|nil - BGM配置
]]
function SoundConfig.GetBGMConfig(bgmKey)
	return SoundConfig.BGM[bgmKey]
end

--[[
获取SFX配置
@param sfxKey string - SFX键名
@return table|nil - SFX配置
]]
function SoundConfig.GetSFXConfig(sfxKey)
	return SoundConfig.SFX[sfxKey]
end

--[[
获取所有BGM键名列表
@return table - BGM键名数组
]]
function SoundConfig.GetAllBGMKeys()
	local keys = {}
	for key, _ in pairs(SoundConfig.BGM) do
		table.insert(keys, key)
	end
	return keys
end

--[[
获取所有SFX键名列表
@return table - SFX键名数组
]]
function SoundConfig.GetAllSFXKeys()
	local keys = {}
	for key, _ in pairs(SoundConfig.SFX) do
		table.insert(keys, key)
	end
	return keys
end

return SoundConfig
