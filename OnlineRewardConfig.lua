--[[
脚本名称: OnlineRewardConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/OnlineRewardConfig
版本: V6.1
]]

local OnlineRewardConfig = {}

OnlineRewardConfig.Rewards = {
	{ Id = 1, Seconds = 180, Type = "Skill", SkillId = 1001, Count = 1 },
	{ Id = 2, Seconds = 360, Type = "Unit", UnitId = "10002", Count = 2 },
	{ Id = 3, Seconds = 600, Type = "Coins", Count = 2000 },
	{ Id = 4, Seconds = 900, Type = "Coins", Count = 2000 },
	{ Id = 5, Seconds = 1500, Type = "Handcuff", Count = 1 },
	{ Id = 6, Seconds = 2400, Type = "Skill", SkillId = 1002, Count = 5 },
	{ Id = 7, Seconds = 3000, Type = "Unit", UnitId = "10008", Count = 2 },
	{ Id = 8, Seconds = 3600, Type = "Coins", Count = 5000 },
	{ Id = 9, Seconds = 4500, Type = "Unit", UnitId = "10010", Count = 3 },
	{ Id = 10, Seconds = 5400, Type = "Handcuff", Count = 1 },
}

function OnlineRewardConfig.GetRewards()
	return OnlineRewardConfig.Rewards
end

function OnlineRewardConfig.GetRewardById(id)
	local target = tonumber(id)
	if not target then
		return nil
	end
	for _, reward in ipairs(OnlineRewardConfig.Rewards) do
		if tonumber(reward.Id) == target then
			return reward
		end
	end
	return nil
end

return OnlineRewardConfig
