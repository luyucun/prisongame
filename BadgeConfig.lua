--[[
=====================================================
Script: BadgeConfig.lua
Type: ModuleScript
Location: ReplicatedStorage/Config/BadgeConfig
Version: V4.4
Description: Badge configuration (Roblox BadgeService)
=====================================================
--]]

local BadgeConfig = {}

BadgeConfig.TriggerType = {
	PLAYER_JOIN = "PLAYER_JOIN",
	POWER = "POWER",
	CHAPTER_CLEAR = "CHAPTER_CLEAR",
}

BadgeConfig.Badges = {
	{
		Key = "WELCOME",
		Id = 1068309156030736,
		Trigger = BadgeConfig.TriggerType.PLAYER_JOIN,
	},
	{
		Key = "CHAPTER_1_CLEAR",
		Id = 2832522491747257,
		Trigger = BadgeConfig.TriggerType.CHAPTER_CLEAR,
		RequiredChapter = 1,
	},
	{
		Key = "POWER_3000",
		Id = 1363005461717615,
		Trigger = BadgeConfig.TriggerType.POWER,
		RequiredPower = 3000,
	},
	{
		Key = "POWER_50000",
		Id = 4053364769846356,
		Trigger = BadgeConfig.TriggerType.POWER,
		RequiredPower = 50000,
	},
}

function BadgeConfig.GetBadgesByTrigger(triggerType)
	local result = {}
	for _, badge in ipairs(BadgeConfig.Badges) do
		if badge.Trigger == triggerType then
			table.insert(result, badge)
		end
	end
	return result
end

function BadgeConfig.GetChapterBadges()
	local result = BadgeConfig.GetBadgesByTrigger(BadgeConfig.TriggerType.CHAPTER_CLEAR)
	table.sort(result, function(a, b)
		return (a.RequiredChapter or 0) < (b.RequiredChapter or 0)
	end)
	return result
end

function BadgeConfig.GetPowerBadges()
	local result = BadgeConfig.GetBadgesByTrigger(BadgeConfig.TriggerType.POWER)
	table.sort(result, function(a, b)
		return (a.RequiredPower or 0) < (b.RequiredPower or 0)
	end)
	return result
end

return BadgeConfig
