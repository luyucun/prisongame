--[[
脚本名称: StageConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/StageConfig
版本: V7.1
]]

--[[
关卡配置模块
职责:
1. 存储章节战斗配置（关卡数、模板风格、敌人引用、金币奖励）
2. 存储V7.1地图系统配置（地图名、icon、解锁勋章、通关勋章奖励）
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("EnemyConfig"))

local StageConfig = {}

local DEFAULT_CHAPTER_STYLE = "Style01"
local DEFAULT_REWARD_COINS = 10

local function BuildCoinRewards(stageCount, coinAmount)
	local rewards = {}
	local total = math.max(0, math.floor(tonumber(stageCount) or 0))
	local coins = math.max(0, math.floor(tonumber(coinAmount) or 0))
	for i = 1, total do
		rewards[i] = { Coins = coins }
	end
	return rewards
end

-- 章节地图配置（V7.1）
-- 注意：Chapter 6~8 当前复用第5章敌人配置；地图模板风格已切换为Style06~Style08。
StageConfig.Chapters = {
	[1] = {
		ChapterId = 1,
		ChapterName = "Wasteland Perimeter",
		MapIcon = "rbxassetid://136889564745361",
		UnlockMedals = 0,
		RewardMedals = 2,
		EnemyChapterRef = 1,
		StagesPerChapter = 5,
		StageTemplateStyle = "Style01",
	},
	[2] = {
		ChapterId = 2,
		ChapterName = "Desert Ironhold",
		MapIcon = "rbxassetid://107529700261477",
		UnlockMedals = 2,
		RewardMedals = 5,
		EnemyChapterRef = 2,
		StagesPerChapter = 8,
		StageTemplateStyle = "Style02",
	},
	[3] = {
		ChapterId = 3,
		ChapterName = "Lockdown Riot Campus",
		MapIcon = "rbxassetid://99918795164776",
		UnlockMedals = 25,
		RewardMedals = 10,
		EnemyChapterRef = 3,
		StagesPerChapter = 10,
		StageTemplateStyle = "Style03",
	},
	[4] = {
		ChapterId = 4,
		ChapterName = "The Prison Mess",
		MapIcon = "rbxassetid://77586065205533",
		UnlockMedals = 100,
		RewardMedals = 20,
		EnemyChapterRef = 4,
		StagesPerChapter = 10,
		StageTemplateStyle = "Style04",
	},
	[5] = {
		ChapterId = 5,
		ChapterName = "Terminal Lock",
		MapIcon = "rbxassetid://74616087643793",
		UnlockMedals = 400,
		RewardMedals = 40,
		EnemyChapterRef = 5,
		StagesPerChapter = 10,
		StageTemplateStyle = "Style05",
	},
	[6] = {
		ChapterId = 6,
		ChapterName = "Urban Lockdown",
		MapIcon = "rbxassetid://99114216606110",
		UnlockMedals = 1200,
		RewardMedals = 60,
		EnemyChapterRef = 6,
		StagesPerChapter = 10,
		StageTemplateStyle = "Style06",
	},
	[7] = {
		ChapterId = 7,
		ChapterName = "Darkbay Prison",
		MapIcon = "rbxassetid://86616141514937",
		UnlockMedals = 2400,
		RewardMedals = 100,
		EnemyChapterRef = 7,
		StagesPerChapter = 10,
		StageTemplateStyle = "Style07",
	},
	[8] = {
		ChapterId = 8,
		ChapterName = "Galactic Prison Transit",
		MapIcon = "rbxassetid://133384519931604",
		UnlockMedals = 5000,
		RewardMedals = 150,
		EnemyChapterRef = 8,
		StagesPerChapter = 10,
		StageTemplateStyle = "Style08",
	},
}

for chapterId, chapter in pairs(StageConfig.Chapters) do
	if not chapter.Rewards then
		chapter.Rewards = BuildCoinRewards(chapter.StagesPerChapter, DEFAULT_REWARD_COINS)
	end
	chapter.ChapterId = chapterId
end

StageConfig.TotalChapters = 8

-- 兼容旧逻辑保留
StageConfig.Style01 = {
	TotalStages = 20,
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
		[10] = {Coins = 1000},
	}
}

function StageConfig.GetChapterConfig(chapterId)
	local id = tonumber(chapterId)
	if not id then
		return nil
	end
	return StageConfig.Chapters[id]
end

function StageConfig.GetStagesPerChapter(chapterId)
	local chapter = StageConfig.GetChapterConfig(chapterId)
	if chapter then
		local configuredStages = tonumber(chapter.StagesPerChapter)
		if configuredStages and configuredStages > 0 then
			return configuredStages
		end

		local enemyRef = tonumber(chapter.EnemyChapterRef)
		if enemyRef and EnemyConfig.GetStageCount then
			local enemyStageCount = tonumber(EnemyConfig.GetStageCount(enemyRef)) or 0
			if enemyStageCount > 0 then
				return enemyStageCount
			end
		end
	end
	return 3
end

function StageConfig.GetChapterStyle(chapterId)
	local chapter = StageConfig.GetChapterConfig(chapterId)
	if chapter then
		return chapter.StageTemplateStyle or chapter.Style or DEFAULT_CHAPTER_STYLE
	end
	return DEFAULT_CHAPTER_STYLE
end

function StageConfig.GetStageReward(chapterId, stageNum)
	local chapter = StageConfig.GetChapterConfig(chapterId)
	local stageId = tonumber(stageNum)
	if chapter and chapter.Rewards and stageId then
		return chapter.Rewards[stageId]
	end
	return nil
end

function StageConfig.GetChapterUnlockMedals(chapterId)
	local chapter = StageConfig.GetChapterConfig(chapterId)
	if not chapter then
		return math.huge
	end
	return math.max(0, math.floor(tonumber(chapter.UnlockMedals) or 0))
end

function StageConfig.GetChapterRewardMedals(chapterId)
	local chapter = StageConfig.GetChapterConfig(chapterId)
	if not chapter then
		return 0
	end
	return math.max(0, math.floor(tonumber(chapter.RewardMedals) or 0))
end

function StageConfig.GetChapterDisplayName(chapterId)
	local chapter = StageConfig.GetChapterConfig(chapterId)
	if not chapter then
		return ""
	end
	return tostring(chapter.ChapterName or ("Chapter " .. tostring(chapter.ChapterId or chapterId)))
end

function StageConfig.GetChapterIcon(chapterId)
	local chapter = StageConfig.GetChapterConfig(chapterId)
	if not chapter then
		return ""
	end
	return tostring(chapter.MapIcon or "")
end

function StageConfig.GetChapterList()
	local chapters = {}
	for chapterId = 1, StageConfig.TotalChapters do
		local chapter = StageConfig.Chapters[chapterId]
		if chapter then
			table.insert(chapters, {
				ChapterId = chapterId,
				ChapterName = StageConfig.GetChapterDisplayName(chapterId),
				MapIcon = StageConfig.GetChapterIcon(chapterId),
				UnlockMedals = StageConfig.GetChapterUnlockMedals(chapterId),
				RewardMedals = StageConfig.GetChapterRewardMedals(chapterId),
				StagesPerChapter = StageConfig.GetStagesPerChapter(chapterId),
			})
		end
	end
	return chapters
end

function StageConfig.GetTotalChapters()
	return StageConfig.TotalChapters
end

function StageConfig.IsLastChapter(chapterId)
	local id = tonumber(chapterId) or 0
	return id >= StageConfig.TotalChapters
end

function StageConfig.IsValidChapter(chapterId)
	local id = tonumber(chapterId)
	if not id then
		return false
	end
	return StageConfig.Chapters[id] ~= nil
end

return StageConfig
