--[[
脚本名称: StageConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/StageConfig
版本: V3.10
]]

--[[
关卡配置模块
职责: 存储关卡相关的配置参数
V2.8新增: 章节概念，每个章节包含多个小关
V3.7新增: 章节关卡地图替换功能，每个章节可配置不同的StageTemplateStyle
V3.10重构: 引用EnemyConfig的章节配置，实现配置统一管理
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("EnemyConfig"))

local StageConfig = {}

-- ==================== 章节配置 (V2.8新增, V3.7增强, V3.10重构) ====================
-- 章节列表配置
-- ChapterId: 章节ID (从1开始)
-- EnemyChapterRef: 引用EnemyConfig中的章节ID (V3.10新增)
-- StagesPerChapter: 该章节的关卡数量 (V3.10: 自动从EnemyConfig读取)
-- StageTemplateStyle: 该章节使用的关卡模板风格 (如 "Style01", "Style02" 等)
-- Rewards: 该章节每关的奖励

StageConfig.Chapters = {
	-- 第一章
	[1] = {
		ChapterId = 1,
		ChapterName = "Chapter 1",
		EnemyChapterRef = 1,  -- V3.10: 引用EnemyConfig.Chapters[1]
		StagesPerChapter = 4,  -- 🔥修复：显式指定关卡数，防止读取失败时回退到默认值3
		StageTemplateStyle = "Style01",  -- V3.7: 使用Style01风格的关卡模板
		Rewards = {
			[1] = {Coins = 10},
			[2] = {Coins = 10},
			[3] = {Coins = 10},
			[4] = {Coins = 10},
		}
	},
	-- 第二章
	[2] = {
		ChapterId = 2,
		ChapterName = "Chapter 2",
		EnemyChapterRef = 2,  -- V3.10: 引用EnemyConfig.Chapters[2]
		StagesPerChapter = 10,  -- 🔥修复：显式指定关卡数，防止读取失败时回退到默认值3
		StageTemplateStyle = "Style02",  -- V3.7: 使用Style02风格
		Rewards = {
			[1] = {Coins = 10},
			[2] = {Coins = 10},
			[3] = {Coins = 10},
			[4] = {Coins = 10},
			[5] = {Coins = 10},
			[6] = {Coins = 10},
			[7] = {Coins = 10},
			[8] = {Coins = 10},
			[9] = {Coins = 10},
			[10] = {Coins = 10},
		}
	},

	-- 第三章
	[3] = {
		ChapterId = 3,
		ChapterName = "Chapter 3",
		EnemyChapterRef = 3,  -- V3.10: 引用EnemyConfig.Chapters[3]
		StagesPerChapter = 20,  -- 🔥修复：显式指定关卡数，防止读取失败时回退到默认值3
		StageTemplateStyle = "Style03",  -- V3.7: 使用Style02风格
		Rewards = {
			[1] = {Coins = 10},
			[2] = {Coins = 10},
			[3] = {Coins = 10},
			[4] = {Coins = 10},
			[5] = {Coins = 10},
			[6] = {Coins = 10},
			[7] = {Coins = 10},
			[8] = {Coins = 10},
			[9] = {Coins = 10},
			[10] = {Coins = 10},
			[11] = {Coins = 10},
			[12] = {Coins = 10},
			[13] = {Coins = 10},
			[14] = {Coins = 10},
			[15] = {Coins = 10},
			[16] = {Coins = 10},
			[17] = {Coins = 10},
			[18] = {Coins = 10},
			[19] = {Coins = 10},
			[20] = {Coins = 10},
		}
	},
}

-- 总章节数
StageConfig.TotalChapters = 3

-- ==================== Style01关卡配置 (保留兼容) ====================
StageConfig.Style01 = {
	TotalStages = 20,  -- 总关卡数（兼容旧配置）

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
获取章节的关卡数量 (V3.10增强: 从EnemyConfig读取)
@param chapterId number - 章节ID
@return number - 关卡数量
]]
function StageConfig.GetStagesPerChapter(chapterId)
	local chapter = StageConfig.Chapters[chapterId]
	if chapter then
		-- V3.10: 优先从配置的StagesPerChapter读取
		if chapter.StagesPerChapter then
			return chapter.StagesPerChapter
		end

		-- V3.10: 如果没有配置，从EnemyConfig自动读取
		if chapter.EnemyChapterRef then
			local enemyStageCount = EnemyConfig.GetStageCount(chapter.EnemyChapterRef)
			if enemyStageCount > 0 then
				return enemyStageCount
			end
		end
	end
	return 3  -- 默认3关
end

--[[
获取章节的模板风格 (V3.7增强)
@param chapterId number - 章节ID
@return string - 模板风格名称 (如 "Style01", "Style02")
说明: 优先读取StageTemplateStyle字段，兼容旧版Style字段
]]
function StageConfig.GetChapterStyle(chapterId)
	local chapter = StageConfig.Chapters[chapterId]
	if chapter then
		-- V3.7: 优先使用新字段名StageTemplateStyle，兼容旧字段Style
		return chapter.StageTemplateStyle or chapter.Style or "Style01"
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
