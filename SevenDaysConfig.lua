--[[
脚本名称: SevenDaysConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/SevenDaysConfig
版本: V4.8
]]

local SevenDaysConfig = {}

SevenDaysConfig.MaxDays = 7
SevenDaysConfig.UnlockAllProductId = 3489888670

SevenDaysConfig.RewardType = {
	Unit = "Unit",
	Skill = "Skill",
	Coins = "Coins",
}

SevenDaysConfig.Rewards = {
	[1] = { Type = SevenDaysConfig.RewardType.Unit, UnitId = "10014", Count = 1 },
	[2] = { Type = SevenDaysConfig.RewardType.Coins, Amount = 10000 },
	[3] = { Type = SevenDaysConfig.RewardType.Unit, UnitId = "10014", Count = 2 },
	[4] = { Type = SevenDaysConfig.RewardType.Skill, SkillId = 1002, Count = 10 },
	[5] = { Type = SevenDaysConfig.RewardType.Unit, UnitId = "10014", Count = 3 },
	[6] = { Type = SevenDaysConfig.RewardType.Coins, Amount = 30000 },
	[7] = { Type = SevenDaysConfig.RewardType.Unit, UnitId = "10024", Count = 2 },
}

function SevenDaysConfig.GetReward(dayIndex)
	return SevenDaysConfig.Rewards[dayIndex]
end

return SevenDaysConfig
