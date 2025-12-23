--[[
脚本名称: TalkConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/TalkConfig
版本: V4.5
]]

local TalkConfig = {}

-- 对话动作类型
TalkConfig.OptionType = {
	DIALOG = "DIALOG",         -- 显示对话内容
	OPEN_SHOP = "OPEN_SHOP",   -- 打开兵种商店
	CLOSE_LIST = "CLOSE_LIST", -- 关闭对话列表
}

-- 对话出现条件类型
TalkConfig.ConditionType = {
	DEFAULT = "DEFAULT",                -- 默认出现
	TALK_COMPLETED = "TALK_COMPLETED",  -- 完成指定对话后出现
	CHAPTER_COMPLETED = "CHAPTER_COMPLETED", -- 通关指定章节后出现
}

-- 对话配置列表
TalkConfig.Options = {
	[1001] = {
		Id = 1001,
		Sort = 1,
		OneTime = true,
		Condition = { Type = TalkConfig.ConditionType.DEFAULT },
		OptionText = "What is this place?",
		Action = TalkConfig.OptionType.DIALOG,
		Dialogues = {
			"You're locked up. I can help you bust out.",
			"Here's some CASH. Go hire two INMATES to help you escape.",
		},
		RewardCoins = 200,
	},
	[1002] = {
		Id = 1002,
		Sort = 2,
		OneTime = true,
		Condition = { Type = TalkConfig.ConditionType.CHAPTER_COMPLETED, Chapter = 1 },
		OptionText = "Why am I still in prison?",
		Action = TalkConfig.OptionType.DIALOG,
		Dialogues = {
			"You're marked as the MOST DANGEROUS inmate, so there are multiple layers of security outside.",
		},
	},
	[1003] = {
		Id = 1003,
		Sort = 3,
		OneTime = false,
		Condition = { Type = TalkConfig.ConditionType.TALK_COMPLETED, TalkId = 1001 },
		OptionText = "Hire INMATES",
		Action = TalkConfig.OptionType.OPEN_SHOP,
	},
	[1004] = {
		Id = 1004,
		Sort = 4,
		OneTime = false,
		Condition = { Type = TalkConfig.ConditionType.TALK_COMPLETED, TalkId = 1001 },
		OptionText = "Expand Army?",
		Action = TalkConfig.OptionType.DIALOG,
		Dialogues = {
			"1.Get more CASH from challenges or AFK to buy powerful INMATES and expand your ARMY.",
			"2.Drag and MERGE two inmates of the same level to get a HIGHER level inmate with much more POWER!",
		},
	},
	[10005] = {
		Id = 10005,
		Sort = 5,
		OneTime = false,
		Condition = { Type = TalkConfig.ConditionType.TALK_COMPLETED, TalkId = 1001 },
		OptionText = "Exit",
		Action = TalkConfig.OptionType.CLOSE_LIST,
	},
}

function TalkConfig.GetOption(talkId)
	return TalkConfig.Options[tonumber(talkId)]
end

function TalkConfig.GetAllOptions()
	local list = {}
	for _, option in pairs(TalkConfig.Options) do
		table.insert(list, option)
	end
	table.sort(list, function(a, b)
		local sortA = a.Sort or a.Id or 0
		local sortB = b.Sort or b.Id or 0
		if sortA == sortB then
			return (a.Id or 0) < (b.Id or 0)
		end
		return sortA < sortB
	end)
	return list
end

return TalkConfig
