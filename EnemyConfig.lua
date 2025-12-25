--[[
脚本名称: EnemyConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/EnemyConfig.lua
版本: V3.10

功能说明:
定义每个章节的关卡敌人配置
格式: Chapters[chapterId].Stages[stageNum] = {敌人列表}
每个敌人: {UnitId = "兵种ID", Level = 等级, GridPos = {X=行, Y=列}}
]]

local EnemyConfig = {}

-- ==================== 章节化敌人配置 (V3.10重构) ====================
-- 按章节组织关卡配置，每个章节包含多个关卡

EnemyConfig.Chapters = {} :: { [number]: any }

-- ==================== 第1章 ====================
EnemyConfig.Chapters[1] = {
	ChapterId = 1,
	ChapterName = "Chapter 1",
	Stages = {
		-- 第1关: 简单测试
		[1] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 7, Y = 7}},
		},

		-- 第2关: 增加难度
		[2] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 8, Y = 7}},
		},

		-- 第3关: 更强的敌人
		[3] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 8, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 6, Y = 7}},
		},

		-- 第3关: 更强的敌人
		[4] = {
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 7}},
		},

		
	}
}

-- ==================== 第2章 ====================
EnemyConfig.Chapters[2] = {
	ChapterId = 2,
	ChapterName = "Chapter 2",
	Stages = {
		-- 第3关: 更强的敌人
		[1] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 8, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 6, Y = 7}},
		},

		-- 第3关: 更强的敌人
		[2] = {
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 7}},
		},
		
		-- 第3关: 更强的敌人
		[3] = {
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 7}},
		},
		
		-- 第3关: 更强的敌人
		[4] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10005", Level = 1, GridPos = {X = 9, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 7, Y = 7}},
		},
		
		-- 第3关: 更强的敌人
		[5] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10005", Level = 1, GridPos = {X = 9, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 5, Y = 7}},
		},

		-- 第3关: 更强的敌人
		[6] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10005", Level = 1, GridPos = {X = 9, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "10008", Level = 1, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 1, GridPos = {X = 9, Y = 1}},
		},

		-- 第3关: 更强的敌人
		[7] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "10005", Level = 1, GridPos = {X = 9, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "10008", Level = 1, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 1, GridPos = {X = 9, Y = 1}},
			{UnitId = "10009", Level = 1, GridPos = {X = 7, Y = 5}},
		},

		-- 第3关: 更强的敌人
		[8] = {
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "10005", Level = 1, GridPos = {X = 9, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "10005", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "10008", Level = 1, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 1, GridPos = {X = 9, Y = 1}},
			{UnitId = "10009", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10010", Level = 1, GridPos = {X = 7, Y = 2}},
			{UnitId = "10010", Level = 1, GridPos = {X = 10, Y = 5}},
			{UnitId = "10010", Level = 1, GridPos = {X = 4, Y = 5}},
		},

		-- 第3关: 更强的敌人
		[9] = {
			{UnitId = "10010", Level = 1, GridPos = {X = 5, Y = 2}},
			{UnitId = "10010", Level = 1, GridPos = {X = 10, Y = 2}},
			{UnitId = "10008", Level = 1, GridPos = {X = 7, Y = 3}},
			{UnitId = "10008", Level = 1, GridPos = {X = 8, Y = 3}},
			{UnitId = "10004", Level = 1, GridPos = {X = 5, Y = 5}},
			{UnitId = "10004", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10004", Level = 1, GridPos = {X = 9, Y = 5}},
			{UnitId = "10004", Level = 1, GridPos = {X = 11, Y = 5}},
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 1}},
			{UnitId = "90001", Level = 1, GridPos = {X = 6, Y = 1}},
			{UnitId = "90001", Level = 1, GridPos = {X = 8, Y = 1}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 1}},
		},
		
		
		-- 第3关: 第2章最终关
		[10] = {
			{UnitId = "10010", Level = 1, GridPos = {X = 5, Y = 2}},
			{UnitId = "10010", Level = 1, GridPos = {X = 10, Y = 2}},
			{UnitId = "10008", Level = 1, GridPos = {X = 7, Y = 3}},
			{UnitId = "10008", Level = 1, GridPos = {X = 8, Y = 3}},
			{UnitId = "10004", Level = 1, GridPos = {X = 5, Y = 5}},
			{UnitId = "10004", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10004", Level = 1, GridPos = {X = 9, Y = 5}},
			{UnitId = "10004", Level = 1, GridPos = {X = 11, Y = 5}},
			{UnitId = "90001", Level = 1, GridPos = {X = 5, Y = 1}},
			{UnitId = "90001", Level = 1, GridPos = {X = 6, Y = 1}},
			{UnitId = "90001", Level = 1, GridPos = {X = 8, Y = 1}},
			{UnitId = "90001", Level = 1, GridPos = {X = 9, Y = 1}},
		},
		
		
	}
}

-- ==================== 第2章 ====================
EnemyConfig.Chapters[3] = {
	ChapterId = 3,
	ChapterName = "Chapter 3",
	Stages = {
		-- 第1关: 第2章开始
		[1] = {
			{UnitId = "10001", Level = 1, GridPos = {X = 7, Y = 1}},
			{UnitId = "10001", Level = 1, GridPos = {X = 5, Y = 1}},
			{UnitId = "10001", Level = 1, GridPos = {X = 9, Y = 1}},
			{UnitId = "10002", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 11, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 3, Y = 3}},
			{UnitId = "10003", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10003", Level = 1, GridPos = {X = 9, Y = 5}},
		},

		-- 第2关: 更多敌人
		[2] = {
			{UnitId = "10001", Level = 1, GridPos = {X = 7, Y = 1}},
			{UnitId = "10001", Level = 1, GridPos = {X = 5, Y = 1}},
			{UnitId = "10001", Level = 1, GridPos = {X = 9, Y = 1}},
			{UnitId = "10002", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 11, Y = 3}},
			{UnitId = "10002", Level = 1, GridPos = {X = 3, Y = 3}},
			{UnitId = "10003", Level = 1, GridPos = {X = 7, Y = 5}},
			{UnitId = "10003", Level = 1, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[3] = {
			{UnitId = "10001", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10001", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10003", Level = 3, GridPos = {X = 8, Y = 1}},
			{UnitId = "10004", Level = 2, GridPos = {X = 8, Y = 5}},
			{UnitId = "10004", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10004", Level = 2, GridPos = {X = 9, Y = 5}},
		},
		-- 第3关: 第2章最终关
		[4] = {
			{UnitId = "10001", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10001", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10003", Level = 3, GridPos = {X = 8, Y = 1}},
			{UnitId = "10004", Level = 2, GridPos = {X = 8, Y = 5}},
			{UnitId = "10004", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10004", Level = 2, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[5] = {
			{UnitId = "10003", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10003", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10003", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10004", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "10004", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "10004", Level = 1, GridPos = {X = 9, Y = 7}},
			{UnitId = "10006", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 8, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 7, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 6, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "10012", Level = 1, GridPos = {X = 7, Y = 4}},
		},

		-- 第3关: 第2章最终关
		[6] = {
			{UnitId = "10003", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10003", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10003", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10004", Level = 1, GridPos = {X = 5, Y = 7}},
			{UnitId = "10004", Level = 1, GridPos = {X = 7, Y = 7}},
			{UnitId = "10004", Level = 1, GridPos = {X = 9, Y = 7}},
			{UnitId = "10006", Level = 1, GridPos = {X = 9, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 8, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 7, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 6, Y = 3}},
			{UnitId = "10006", Level = 1, GridPos = {X = 5, Y = 3}},
			{UnitId = "10012", Level = 1, GridPos = {X = 7, Y = 4}},
		},

		-- 第3关: 第2章最终关
		[7] = {
			{UnitId = "10008", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 3}},
		},

		-- 第3关: 第2章最终关
		[8] = {
			{UnitId = "10008", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10009", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10009", Level = 2, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[9] = {
			{UnitId = "10005", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10005", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10005", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10005", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 8, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 6, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 10, Y = 3}},
			{UnitId = "10014", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10014", Level = 2, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[10] = {
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10007", Level = 2, GridPos = {X = 11, Y = 3}},
			{UnitId = "10007", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10007", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10007", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10013", Level = 2, GridPos = {X = 5, Y = 5}},
			{UnitId = "10013", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10013", Level = 2, GridPos = {X = 9, Y = 5}},
			{UnitId = "10013", Level = 2, GridPos = {X = 11, Y = 5}},
		},

		-- 第1关: 第2章开始
		[11] = {
			{UnitId = "10001", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10001", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10001", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10002", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 11, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 3, Y = 3}},
			{UnitId = "10003", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10003", Level = 2, GridPos = {X = 9, Y = 5}},
		},

		-- 第2关: 更多敌人
		[12] = {
			{UnitId = "10001", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10001", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10001", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10002", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 11, Y = 3}},
			{UnitId = "10002", Level = 2, GridPos = {X = 3, Y = 3}},
			{UnitId = "10003", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10003", Level = 2, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[13] = {
			{UnitId = "10001", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10001", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10003", Level = 3, GridPos = {X = 8, Y = 1}},
			{UnitId = "10004", Level = 2, GridPos = {X = 8, Y = 5}},
			{UnitId = "10004", Level = 3, GridPos = {X = 7, Y = 5}},
			{UnitId = "10004", Level = 3, GridPos = {X = 9, Y = 5}},
		},
		-- 第3关: 第2章最终关
		[14] = {
			{UnitId = "10012", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10012", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10003", Level = 3, GridPos = {X = 8, Y = 1}},
			{UnitId = "10004", Level = 2, GridPos = {X = 8, Y = 5}},
			{UnitId = "10004", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10004", Level = 2, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[15] = {
			{UnitId = "10008", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10004", Level = 2, GridPos = {X = 5, Y = 7}},
			{UnitId = "10004", Level = 2, GridPos = {X = 7, Y = 7}},
			{UnitId = "10004", Level = 2, GridPos = {X = 9, Y = 7}},
			{UnitId = "10006", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 8, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 6, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10012", Level = 2, GridPos = {X = 7, Y = 4}},
		},

		-- 第3关: 第2章最终关
		[16] = {
			{UnitId = "10003", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10003", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10003", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10004", Level = 2, GridPos = {X = 5, Y = 7}},
			{UnitId = "10004", Level = 2, GridPos = {X = 7, Y = 7}},
			{UnitId = "10004", Level = 2, GridPos = {X = 9, Y = 7}},
			{UnitId = "10006", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 8, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 6, Y = 3}},
			{UnitId = "10006", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10012", Level = 2, GridPos = {X = 7, Y = 4}},
		},

		-- 第3关: 第2章最终关
		[17] = {
			{UnitId = "10008", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 3, GridPos = {X = 9, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10008", Level = 3, GridPos = {X = 11, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10008", Level = 3, GridPos = {X = 7, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 3}},
		},

		-- 第3关: 第2章最终关
		[18] = {
			{UnitId = "10008", Level = 3, GridPos = {X = 7, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 3, GridPos = {X = 9, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10008", Level = 3, GridPos = {X = 11, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10009", Level = 3, GridPos = {X = 7, Y = 5}},
			{UnitId = "10009", Level = 3, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[19] = {
			{UnitId = "10005", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10005", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10005", Level = 3, GridPos = {X = 7, Y = 1}},
			{UnitId = "10005", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 3, GridPos = {X = 8, Y = 3}},
			{UnitId = "10008", Level = 2, GridPos = {X = 6, Y = 3}},
			{UnitId = "10008", Level = 3, GridPos = {X = 10, Y = 3}},
			{UnitId = "10014", Level = 2, GridPos = {X = 7, Y = 5}},
			{UnitId = "10014", Level = 3, GridPos = {X = 9, Y = 5}},
		},

		-- 第3关: 第2章最终关
		[20] = {
			{UnitId = "10008", Level = 2, GridPos = {X = 5, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 7, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 1}},
			{UnitId = "10008", Level = 2, GridPos = {X = 11, Y = 1}},
			{UnitId = "10007", Level = 2, GridPos = {X = 11, Y = 3}},
			{UnitId = "10007", Level = 2, GridPos = {X = 9, Y = 3}},
			{UnitId = "10007", Level = 2, GridPos = {X = 7, Y = 3}},
			{UnitId = "10007", Level = 2, GridPos = {X = 5, Y = 3}},
			{UnitId = "10013", Level = 3, GridPos = {X = 5, Y = 5}},
			{UnitId = "10013", Level = 3, GridPos = {X = 7, Y = 5}},
			{UnitId = "10013", Level = 3, GridPos = {X = 9, Y = 5}},
			{UnitId = "10013", Level = 3, GridPos = {X = 11, Y = 5}},
		},

	}
}

-- ==================== 工具函数 (V3.10新增) ====================

--[[
获取章节配置
@param chapterId number - 章节ID
@return table|nil - 章节配置
]]
function EnemyConfig.GetChapter(chapterId)
	return EnemyConfig.Chapters[chapterId]
end

--[[
获取指定章节的指定关卡配置
@param chapterId number - 章节ID
@param stageNum number - 章节内关卡编号（1, 2, 3...）
@return table|nil - 关卡敌人配置列表
]]
function EnemyConfig.GetStageConfig(chapterId, stageNum)
	local chapter = EnemyConfig.Chapters[chapterId]
	if not chapter then
		return nil
	end

	return chapter.Stages[stageNum]
end

--[[
获取章节的关卡数量
@param chapterId number - 章节ID
@return number - 关卡数量
]]
function EnemyConfig.GetStageCount(chapterId)
	local chapter = EnemyConfig.Chapters[chapterId]
	if not chapter or not chapter.Stages then
		return 0
	end

	local count = 0
	for _ in pairs(chapter.Stages) do
		count = count + 1
	end
	return count
end

-- ==================== 向后兼容 (V3.10保留) ====================
-- 保留旧的访问方式，用于兼容旧代码
-- 自动映射 EnemyConfig["Stage001"] → EnemyConfig.Chapters[1].Stages[1]

setmetatable(EnemyConfig, {
	__index = function(t, key)
		-- 如果是 "Stage001" 格式的旧键名
		if type(key) == "string" and key:match("^Stage%d+$") then
			-- 提取关卡编号
			local stageNum = tonumber(key:match("%d+"))
			if stageNum then
				-- 简单映射：前3关属于第1章，后3关属于第2章（根据实际情况调整）
				local chapterId = math.ceil(stageNum / 3)
				local stageInChapter = ((stageNum - 1) % 3) + 1

				local chapter = EnemyConfig.Chapters[chapterId]
				if chapter and chapter.Stages then
					return chapter.Stages[stageInChapter]
				end
			end
		end
		return nil
	end
})

return EnemyConfig
