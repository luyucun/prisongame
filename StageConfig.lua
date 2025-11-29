--[[
脚本名称: StageConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/StageConfig
版本: V2.8
]]

--[[
关卡配置模块
职责: 存储关卡相关的配置参数
V2.8新增: 章节概念，每个章节包含多个小关
]]

local StageConfig = {}

-- ==================== 章节配置 (V2.8新增) ====================
-- 章节列表配置
-- ChapterId: 章节ID (从1开始)
-- StagesPerChapter: 该章节的关卡数量
-- Style: 该章节使用的模板风格
-- Rewards: 该章节每关的奖励

StageConfig.Chapters = {
	-- 第一章
	[1] = {
		ChapterId = 1,
		ChapterName = "Chapter 1",
		StagesPerChapter = 3,  -- 3个小关
		Style = "Style01",
		Rewards = {
			[1] = {Coins = 100},
			[2] = {Coins = 150},
			[3] = {Coins = 200},
		}
	},
	-- 第二章
	[2] = {
		ChapterId = 2,
		ChapterName = "Chapter 2",
		StagesPerChapter = 3,  -- 3个小关
		Style = "Style01",
		Rewards = {
			[1] = {Coins = 250},
			[2] = {Coins = 300},
			[3] = {Coins = 400},
		}
	},
}

-- 总章节数
StageConfig.TotalChapters = 2

-- ==================== Style01关卡配置 (保留兼容) ====================
StageConfig.Style01 = {
	TotalStages = 10,  -- 总关卡数（兼容旧配置）

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

-- ==================== 工具函数 (V2.8新增) ====================

--[[
获取章节配置
@param chapterId number - 章节ID
@return table|nil - 章节配置数据
]]
function StageConfig.GetChapterConfig(chapterId)
	return StageConfig.Chapters[chapterId]
end

--[[
获取章节的关卡数量
@param chapterId number - 章节ID
@return number - 关卡数量
]]
function StageConfig.GetStagesPerChapter(chapterId)
	local chapter = StageConfig.Chapters[chapterId]
	if chapter then
		return chapter.StagesPerChapter
	end
	return 3  -- 默认3关
end

--[[
获取章节的模板风格
@param chapterId number - 章节ID
@return string - 模板风格名称
]]
function StageConfig.GetChapterStyle(chapterId)
	local chapter = StageConfig.Chapters[chapterId]
	if chapter then
		return chapter.Style
	end
	return "Style01"  -- 默认Style01
end

--[[
获取章节某关的奖励
@param chapterId number - 章节ID
@param stageNum number - 章节内关卡编号
@return table|nil - 奖励配置
]]
function StageConfig.GetStageReward(chapterId, stageNum)
	local chapter = StageConfig.Chapters[chapterId]
	if chapter and chapter.Rewards then
		return chapter.Rewards[stageNum]
	end
	return nil
end

--[[
获取总章节数
@return number - 总章节数
]]
function StageConfig.GetTotalChapters()
	return StageConfig.TotalChapters
end

--[[
判断是否是最后一章
@param chapterId number - 章节ID
@return boolean - 是否是最后一章
]]
function StageConfig.IsLastChapter(chapterId)
	return chapterId >= StageConfig.TotalChapters
end

return StageConfig
