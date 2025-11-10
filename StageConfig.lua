--[[
脚本名称: StageConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/StageConfig
版本: V2.0
]]

--[[
关卡配置模块
职责: 存储关卡相关的配置参数
]]

local StageConfig = {}

-- ==================== Style01关卡配置 ====================
StageConfig.Style01 = {
	TotalStages = 10,  -- 总关卡数

	-- 关卡奖励（预留，后续完善）
	Rewards = {
		[1] = {Coins = 100},
		[2] = {Coins = 150},
		[3] = {Coins = 200},
		[4] = {Coins = 250},
		[5] = {Coins = 300},
		[6] = {Coins = 350},
		[7] = {Coins = 400},
		[8] = {Coins = 450},
		[9] = {Coins = 500},
		[10] = {Coins = 1000},  -- 最后一关额外奖励
	}
}

return StageConfig
