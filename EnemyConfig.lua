--[[
Script: EnemyConfig
Type: ModuleScript (Config)
Path: ReplicatedStorage/Config/EnemyConfig.lua
Version: V3.11

Defines enemy composition per chapter and per stage.
Format: Chapters[chapterId].Stages[stageNum] = { enemy list }
Enemy: {UnitId = "ID", Level = number, GridPos = {X = row, Y = column}}
]]


local EnemyConfig = {}

-- ==================== Chapter Enemy Config ====================
EnemyConfig.Chapters = {} :: { [number]: any }

-- ==================== Chapter 1 ====================
EnemyConfig.Chapters[1] = {
	ChapterId = 1,
	ChapterName = "Chapter 1",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10001", Level = 1, GridPos = {X = 7, Y = 7}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10001", Level = 1, GridPos = {X = 6, Y = 7}},
			{UnitId = "10002", Level = 1, GridPos = {X = 8, Y = 7}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10001", Level = 1, GridPos = {X = 5, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 6}},
			{UnitId = "10003", Level = 1, GridPos = {X = 9, Y = 6}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10001", Level = 1, GridPos = {X = 5, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 6}},
			{UnitId = "10003", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10001", Level = 1, GridPos = {X = 8, Y = 8}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10001", Level = 1, GridPos = {X = 4, Y = 6}},
			{UnitId = "10001", Level = 1, GridPos = {X = 6, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 8, Y = 6}},
			{UnitId = "10003", Level = 1, GridPos = {X = 10, Y = 6}},
			{UnitId = "10001", Level = 1, GridPos = {X = 5, Y = 8}},
			{UnitId = "10004", Level = 1, GridPos = {X = 7, Y = 8}},
			{UnitId = "10001", Level = 1, GridPos = {X = 9, Y = 8}},
		},

	}
}

-- ==================== Chapter 2 ====================
EnemyConfig.Chapters[2] = {
	ChapterId = 2,
	ChapterName = "Chapter 2",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10002", Level = 1, GridPos = {X = 8, Y = 4}},
			{UnitId = "10002", Level = 1, GridPos = {X = 10, Y = 4}},
			{UnitId = "10001", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10002", Level = 2, GridPos = {X = 1, Y = 6}},
			{UnitId = "10004", Level = 1, GridPos = {X = 3, Y = 6}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10004", Level = 1, GridPos = {X = 12, Y = 4}},
			{UnitId = "10004", Level = 1, GridPos = {X = 1, Y = 6}},
			{UnitId = "10001", Level = 1, GridPos = {X = 3, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 5, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 6}},
			{UnitId = "10002", Level = 2, GridPos = {X = 9, Y = 6}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10005", Level = 1, GridPos = {X = 3, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 5, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10003", Level = 1, GridPos = {X = 11, Y = 6}},
			{UnitId = "10002", Level = 2, GridPos = {X = 13, Y = 6}},
			{UnitId = "10005", Level = 1, GridPos = {X = 2, Y = 8}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10004", Level = 1, GridPos = {X = 11, Y = 6}},
			{UnitId = "10005", Level = 1, GridPos = {X = 13, Y = 6}},
			{UnitId = "10002", Level = 1, GridPos = {X = 2, Y = 8}},
			{UnitId = "10002", Level = 1, GridPos = {X = 4, Y = 8}},
			{UnitId = "10005", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10002", Level = 2, GridPos = {X = 8, Y = 8}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10006", Level = 1, GridPos = {X = 11, Y = 6}},
			{UnitId = "10004", Level = 1, GridPos = {X = 13, Y = 6}},
			{UnitId = "10003", Level = 1, GridPos = {X = 2, Y = 8}},
			{UnitId = "10001", Level = 2, GridPos = {X = 4, Y = 8}},
			{UnitId = "10004", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10004", Level = 1, GridPos = {X = 8, Y = 8}},
			{UnitId = "10004", Level = 1, GridPos = {X = 10, Y = 8}},
			{UnitId = "10004", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10008", Level = 1, GridPos = {X = 3, Y = 10}},
		},

		-- Stage 6
		[6] = {
			{UnitId = "10003", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10006", Level = 1, GridPos = {X = 4, Y = 8}},
			{UnitId = "10003", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10003", Level = 1, GridPos = {X = 8, Y = 8}},
			{UnitId = "10006", Level = 1, GridPos = {X = 10, Y = 8}},
			{UnitId = "10002", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10003", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10005", Level = 1, GridPos = {X = 5, Y = 10}},
			{UnitId = "10003", Level = 1, GridPos = {X = 7, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 9, Y = 10}},
		},

		-- Stage 7
		[7] = {
			{UnitId = "10002", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10004", Level = 1, GridPos = {X = 8, Y = 8}},
			{UnitId = "10002", Level = 1, GridPos = {X = 10, Y = 8}},
			{UnitId = "10006", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10003", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10003", Level = 1, GridPos = {X = 5, Y = 10}},
			{UnitId = "10003", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10006", Level = 1, GridPos = {X = 9, Y = 10}},
			{UnitId = "10002", Level = 1, GridPos = {X = 11, Y = 10}},
			{UnitId = "10009", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10006", Level = 2, GridPos = {X = 3, Y = 2}},
		},

		-- Stage 8
		[8] = {
			{UnitId = "10001", Level = 2, GridPos = {X = 10, Y = 8}},
			{UnitId = "10006", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10001", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10006", Level = 1, GridPos = {X = 5, Y = 10}},
			{UnitId = "10003", Level = 1, GridPos = {X = 7, Y = 10}},
			{UnitId = "10001", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10006", Level = 1, GridPos = {X = 11, Y = 10}},
			{UnitId = "10002", Level = 1, GridPos = {X = 7, Y = 12}},
			{UnitId = "10006", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10004", Level = 1, GridPos = {X = 5, Y = 2}},
			{UnitId = "10006", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10002", Level = 2, GridPos = {X = 9, Y = 2}},
		},

	}
}

-- ==================== Chapter 3 ====================
EnemyConfig.Chapters[3] = {
	ChapterId = 3,
	ChapterName = "Chapter 3",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10006", Level = 1, GridPos = {X = 1, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 3, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 5, Y = 6}},
			{UnitId = "10004", Level = 2, GridPos = {X = 7, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 11, Y = 6}},
			{UnitId = "10006", Level = 2, GridPos = {X = 13, Y = 6}},
			{UnitId = "10006", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 4, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 6, Y = 8}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10006", Level = 1, GridPos = {X = 5, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 7, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 11, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 13, Y = 6}},
			{UnitId = "10006", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10001", Level = 1, GridPos = {X = 4, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 6, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 8, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 10, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 12, Y = 8}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10006", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 11, Y = 6}},
			{UnitId = "10001", Level = 1, GridPos = {X = 13, Y = 6}},
			{UnitId = "10006", Level = 1, GridPos = {X = 2, Y = 8}},
			{UnitId = "10006", Level = 1, GridPos = {X = 4, Y = 8}},
			{UnitId = "10001", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10006", Level = 1, GridPos = {X = 8, Y = 8}},
			{UnitId = "10006", Level = 1, GridPos = {X = 10, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 9, Y = 10}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10003", Level = 2, GridPos = {X = 13, Y = 6}},
			{UnitId = "10005", Level = 1, GridPos = {X = 2, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 4, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10005", Level = 1, GridPos = {X = 8, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 10, Y = 8}},
			{UnitId = "10007", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10001", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10012", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10012", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10006", Level = 1, GridPos = {X = 9, Y = 10}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10012", Level = 1, GridPos = {X = 4, Y = 8}},
			{UnitId = "10003", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10004", Level = 1, GridPos = {X = 8, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 10, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10012", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10012", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10003", Level = 1, GridPos = {X = 7, Y = 10}},
			{UnitId = "10007", Level = 1, GridPos = {X = 9, Y = 10}},
			{UnitId = "10012", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10003", Level = 1, GridPos = {X = 7, Y = 12}},
			{UnitId = "10006", Level = 1, GridPos = {X = 3, Y = 2}},
		},

		-- Stage 6
		[6] = {
			{UnitId = "10006", Level = 1, GridPos = {X = 8, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 10, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10012", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10003", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10004", Level = 1, GridPos = {X = 7, Y = 10}},
			{UnitId = "10012", Level = 1, GridPos = {X = 9, Y = 10}},
			{UnitId = "10007", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10012", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10012", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10012", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10004", Level = 1, GridPos = {X = 7, Y = 2}},
		},

		-- Stage 7
		[7] = {
			{UnitId = "10007", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10006", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10003", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10006", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10009", Level = 1, GridPos = {X = 3, Y = 2}},
			{UnitId = "10006", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10004", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10006", Level = 3, GridPos = {X = 9, Y = 2}},
			{UnitId = "10002", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10009", Level = 1, GridPos = {X = 2, Y = 4}},
		},

		-- Stage 8
		[8] = {
			{UnitId = "10003", Level = 1, GridPos = {X = 5, Y = 10}},
			{UnitId = "10001", Level = 1, GridPos = {X = 7, Y = 10}},
			{UnitId = "10003", Level = 1, GridPos = {X = 9, Y = 10}},
			{UnitId = "10011", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10001", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10011", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10011", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10011", Level = 3, GridPos = {X = 9, Y = 2}},
			{UnitId = "10003", Level = 1, GridPos = {X = 11, Y = 2}},
			{UnitId = "10010", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10003", Level = 1, GridPos = {X = 4, Y = 4}},
			{UnitId = "10009", Level = 1, GridPos = {X = 6, Y = 4}},
		},

		-- Stage 9
		[9] = {
			{UnitId = "10004", Level = 1, GridPos = {X = 9, Y = 10}},
			{UnitId = "10011", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10003", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10004", Level = 1, GridPos = {X = 3, Y = 2}},
			{UnitId = "10004", Level = 1, GridPos = {X = 5, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10008", Level = 1, GridPos = {X = 11, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 2, Y = 4}},
			{UnitId = "10011", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10011", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10008", Level = 1, GridPos = {X = 8, Y = 4}},
			{UnitId = "10011", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10013", Level = 1, GridPos = {X = 12, Y = 4}},
		},

		-- Stage 10
		[10] = {
			{UnitId = "10011", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10009", Level = 1, GridPos = {X = 3, Y = 2}},
			{UnitId = "10002", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10004", Level = 1, GridPos = {X = 11, Y = 2}},
			{UnitId = "10009", Level = 1, GridPos = {X = 2, Y = 4}},
			{UnitId = "10011", Level = 2, GridPos = {X = 4, Y = 4}},
			{UnitId = "10003", Level = 2, GridPos = {X = 6, Y = 4}},
			{UnitId = "10011", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10011", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10011", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10011", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10006", Level = 3, GridPos = {X = 3, Y = 6}},
		},

	}
}

-- ==================== Chapter 4 ====================
EnemyConfig.Chapters[4] = {
	ChapterId = 4,
	ChapterName = "Chapter 4",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10015", Level = 2, GridPos = {X = 7, Y = 6}},
			{UnitId = "10017", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10014", Level = 1, GridPos = {X = 11, Y = 6}},
			{UnitId = "10009", Level = 2, GridPos = {X = 13, Y = 6}},
			{UnitId = "10008", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10009", Level = 2, GridPos = {X = 4, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 6, Y = 8}},
			{UnitId = "10015", Level = 3, GridPos = {X = 8, Y = 8}},
			{UnitId = "10015", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10013", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10014", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 5, Y = 10}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10010", Level = 2, GridPos = {X = 11, Y = 6}},
			{UnitId = "10015", Level = 2, GridPos = {X = 13, Y = 6}},
			{UnitId = "10017", Level = 1, GridPos = {X = 2, Y = 8}},
			{UnitId = "10013", Level = 1, GridPos = {X = 4, Y = 8}},
			{UnitId = "10017", Level = 2, GridPos = {X = 6, Y = 8}},
			{UnitId = "10005", Level = 3, GridPos = {X = 8, Y = 8}},
			{UnitId = "10011", Level = 2, GridPos = {X = 10, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10014", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 7, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 9, Y = 10}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10005", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 4, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 6, Y = 8}},
			{UnitId = "10009", Level = 2, GridPos = {X = 8, Y = 8}},
			{UnitId = "10009", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10010", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10017", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10013", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10016", Level = 1, GridPos = {X = 3, Y = 2}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10010", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 8, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 10, Y = 8}},
			{UnitId = "10013", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10011", Level = 1, GridPos = {X = 5, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 7, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10006", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10011", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10015", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10015", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10015", Level = 1, GridPos = {X = 7, Y = 2}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10019", Level = 2, GridPos = {X = 10, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10011", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10019", Level = 1, GridPos = {X = 9, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10008", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10015", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10009", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10009", Level = 3, GridPos = {X = 9, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 1, GridPos = {X = 2, Y = 4}},
		},

		-- Stage 6
		[6] = {
			{UnitId = "10015", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10014", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10014", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10014", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10014", Level = 2, GridPos = {X = 2, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10013", Level = 1, GridPos = {X = 6, Y = 4}},
		},

		-- Stage 7
		[7] = {
			{UnitId = "10015", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10015", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10017", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10008", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 1, GridPos = {X = 2, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 1, GridPos = {X = 6, Y = 4}},
			{UnitId = "10008", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 12, Y = 4}},
		},

		-- Stage 8
		[8] = {
			{UnitId = "10015", Level = 1, GridPos = {X = 11, Y = 10}},
			{UnitId = "10016", Level = 1, GridPos = {X = 7, Y = 12}},
			{UnitId = "10010", Level = 1, GridPos = {X = 3, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10010", Level = 1, GridPos = {X = 7, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10010", Level = 1, GridPos = {X = 11, Y = 2}},
			{UnitId = "10020", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10012", Level = 2, GridPos = {X = 4, Y = 4}},
			{UnitId = "10020", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10020", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10008", Level = 1, GridPos = {X = 10, Y = 4}},
			{UnitId = "10010", Level = 1, GridPos = {X = 12, Y = 4}},
			{UnitId = "10008", Level = 2, GridPos = {X = 1, Y = 6}},
			{UnitId = "10017", Level = 1, GridPos = {X = 3, Y = 6}},
		},

		-- Stage 9
		[9] = {
			{UnitId = "10020", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10014", Level = 1, GridPos = {X = 5, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10015", Level = 1, GridPos = {X = 9, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10010", Level = 1, GridPos = {X = 2, Y = 4}},
			{UnitId = "10009", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10014", Level = 2, GridPos = {X = 6, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10020", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10016", Level = 1, GridPos = {X = 12, Y = 4}},
			{UnitId = "10007", Level = 2, GridPos = {X = 1, Y = 6}},
			{UnitId = "10006", Level = 2, GridPos = {X = 3, Y = 6}},
			{UnitId = "10017", Level = 1, GridPos = {X = 5, Y = 6}},
			{UnitId = "10020", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10015", Level = 1, GridPos = {X = 9, Y = 6}},
		},

		-- Stage 10
		[10] = {
			{UnitId = "10020", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10007", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10014", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 2, Y = 4}},
			{UnitId = "10013", Level = 2, GridPos = {X = 4, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 6, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10008", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10011", Level = 2, GridPos = {X = 1, Y = 6}},
			{UnitId = "10020", Level = 3, GridPos = {X = 3, Y = 6}},
			{UnitId = "10011", Level = 2, GridPos = {X = 5, Y = 6}},
			{UnitId = "10020", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10015", Level = 1, GridPos = {X = 9, Y = 6}},
			{UnitId = "10013", Level = 2, GridPos = {X = 11, Y = 6}},
			{UnitId = "10012", Level = 1, GridPos = {X = 13, Y = 6}},
		},

	}
}

-- ==================== Chapter 5 ====================
EnemyConfig.Chapters[5] = {
	ChapterId = 5,
	ChapterName = "Chapter 5",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10019", Level = 1, GridPos = {X = 13, Y = 6}},
			{UnitId = "10022", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10019", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10014", Level = 3, GridPos = {X = 6, Y = 8}},
			{UnitId = "10017", Level = 3, GridPos = {X = 8, Y = 8}},
			{UnitId = "10015", Level = 2, GridPos = {X = 10, Y = 8}},
			{UnitId = "10020", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10019", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10019", Level = 1, GridPos = {X = 5, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 7, Y = 10}},
			{UnitId = "10021", Level = 1, GridPos = {X = 9, Y = 10}},
			{UnitId = "10020", Level = 4, GridPos = {X = 11, Y = 10}},
			{UnitId = "10019", Level = 1, GridPos = {X = 7, Y = 12}},
			{UnitId = "10015", Level = 3, GridPos = {X = 3, Y = 2}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10012", Level = 2, GridPos = {X = 4, Y = 8}},
			{UnitId = "10019", Level = 1, GridPos = {X = 6, Y = 8}},
			{UnitId = "10013", Level = 3, GridPos = {X = 8, Y = 8}},
			{UnitId = "10020", Level = 4, GridPos = {X = 10, Y = 8}},
			{UnitId = "10021", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10021", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10011", Level = 3, GridPos = {X = 5, Y = 10}},
			{UnitId = "10021", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10019", Level = 1, GridPos = {X = 11, Y = 10}},
			{UnitId = "10021", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10022", Level = 1, GridPos = {X = 3, Y = 2}},
			{UnitId = "10018", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 7, Y = 2}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10012", Level = 2, GridPos = {X = 8, Y = 8}},
			{UnitId = "10023", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10021", Level = 1, GridPos = {X = 12, Y = 8}},
			{UnitId = "10019", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10014", Level = 3, GridPos = {X = 5, Y = 10}},
			{UnitId = "10015", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10020", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10022", Level = 1, GridPos = {X = 11, Y = 10}},
			{UnitId = "10017", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10011", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10010", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10020", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10012", Level = 3, GridPos = {X = 9, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10011", Level = 2, GridPos = {X = 2, Y = 4}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10016", Level = 3, GridPos = {X = 12, Y = 8}},
			{UnitId = "10022", Level = 1, GridPos = {X = 3, Y = 10}},
			{UnitId = "10011", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10019", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10011", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10019", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10013", Level = 4, GridPos = {X = 7, Y = 12}},
			{UnitId = "10020", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10013", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10022", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10021", Level = 1, GridPos = {X = 9, Y = 2}},
			{UnitId = "10019", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10021", Level = 1, GridPos = {X = 2, Y = 4}},
			{UnitId = "10020", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10014", Level = 3, GridPos = {X = 6, Y = 4}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10017", Level = 3, GridPos = {X = 5, Y = 10}},
			{UnitId = "10017", Level = 3, GridPos = {X = 7, Y = 10}},
			{UnitId = "10021", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10013", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10020", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10020", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10012", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10018", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10019", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10020", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 4, Y = 4}},
			{UnitId = "10022", Level = 1, GridPos = {X = 6, Y = 4}},
			{UnitId = "10017", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 10, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 12, Y = 4}},
		},

		-- Stage 6
		[6] = {
			{UnitId = "10020", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10017", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10020", Level = 4, GridPos = {X = 7, Y = 12}},
			{UnitId = "10022", Level = 1, GridPos = {X = 3, Y = 2}},
			{UnitId = "10021", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10022", Level = 1, GridPos = {X = 7, Y = 2}},
			{UnitId = "10012", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10020", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 2, Y = 4}},
			{UnitId = "10012", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10022", Level = 1, GridPos = {X = 6, Y = 4}},
			{UnitId = "10022", Level = 1, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10010", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10016", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10010", Level = 3, GridPos = {X = 3, Y = 6}},
		},

		-- Stage 7
		[7] = {
			{UnitId = "10023", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10015", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10016", Level = 2, GridPos = {X = 5, Y = 2}},
			{UnitId = "10018", Level = 1, GridPos = {X = 7, Y = 2}},
			{UnitId = "10011", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10014", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10018", Level = 2, GridPos = {X = 2, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 2, GridPos = {X = 6, Y = 4}},
			{UnitId = "10011", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10010", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10018", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10016", Level = 3, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 2, GridPos = {X = 5, Y = 6}},
			{UnitId = "10013", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 9, Y = 6}},
		},

		-- Stage 8
		[8] = {
			{UnitId = "10021", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10012", Level = 2, GridPos = {X = 7, Y = 2}},
			{UnitId = "10018", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10020", Level = 2, GridPos = {X = 2, Y = 4}},
			{UnitId = "10010", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 2, GridPos = {X = 6, Y = 4}},
			{UnitId = "10019", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 10, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 3, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 5, Y = 6}},
			{UnitId = "10018", Level = 2, GridPos = {X = 7, Y = 6}},
			{UnitId = "10015", Level = 3, GridPos = {X = 9, Y = 6}},
			{UnitId = "10015", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10013", Level = 4, GridPos = {X = 13, Y = 6}},
		},

		-- Stage 9
		[9] = {
			{UnitId = "10010", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10023", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10023", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10013", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10012", Level = 2, GridPos = {X = 10, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10012", Level = 2, GridPos = {X = 3, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10017", Level = 2, GridPos = {X = 7, Y = 6}},
			{UnitId = "10013", Level = 3, GridPos = {X = 9, Y = 6}},
			{UnitId = "10015", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10013", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10016", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10019", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10017", Level = 2, GridPos = {X = 6, Y = 8}},
		},

		-- Stage 10
		[10] = {
			{UnitId = "10015", Level = 2, GridPos = {X = 2, Y = 4}},
			{UnitId = "10010", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10020", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10015", Level = 2, GridPos = {X = 3, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10012", Level = 2, GridPos = {X = 7, Y = 6}},
			{UnitId = "10020", Level = 2, GridPos = {X = 9, Y = 6}},
			{UnitId = "10012", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10010", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10017", Level = 3, GridPos = {X = 2, Y = 8}},
			{UnitId = "10023", Level = 4, GridPos = {X = 4, Y = 8}},
			{UnitId = "10019", Level = 2, GridPos = {X = 6, Y = 8}},
			{UnitId = "10010", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10015", Level = 3, GridPos = {X = 10, Y = 8}},
		},

	}
}

-- ==================== Chapter 6 ====================
EnemyConfig.Chapters[6] = {
	ChapterId = 6,
	ChapterName = "Chapter 6",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10019", Level = 3, GridPos = {X = 6, Y = 8}},
			{UnitId = "10023", Level = 2, GridPos = {X = 8, Y = 8}},
			{UnitId = "10018", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10016", Level = 4, GridPos = {X = 12, Y = 8}},
			{UnitId = "10016", Level = 5, GridPos = {X = 3, Y = 10}},
			{UnitId = "10022", Level = 2, GridPos = {X = 5, Y = 10}},
			{UnitId = "10018", Level = 3, GridPos = {X = 7, Y = 10}},
			{UnitId = "10023", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10017", Level = 4, GridPos = {X = 11, Y = 10}},
			{UnitId = "10019", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10017", Level = 5, GridPos = {X = 3, Y = 2}},
			{UnitId = "10016", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10017", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10022", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 4}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10016", Level = 4, GridPos = {X = 10, Y = 8}},
			{UnitId = "10019", Level = 3, GridPos = {X = 12, Y = 8}},
			{UnitId = "10023", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10017", Level = 4, GridPos = {X = 5, Y = 10}},
			{UnitId = "10017", Level = 5, GridPos = {X = 7, Y = 10}},
			{UnitId = "10021", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10022", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10016", Level = 4, GridPos = {X = 7, Y = 12}},
			{UnitId = "10023", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10017", Level = 5, GridPos = {X = 5, Y = 2}},
			{UnitId = "10016", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10018", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10016", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10018", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 6, Y = 4}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10016", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 5, Y = 10}},
			{UnitId = "10019", Level = 3, GridPos = {X = 7, Y = 10}},
			{UnitId = "10019", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10023", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10017", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10018", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10016", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10017", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10015", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10018", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10018", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10017", Level = 5, GridPos = {X = 6, Y = 4}},
			{UnitId = "10023", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10016", Level = 5, GridPos = {X = 10, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 12, Y = 4}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10023", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10022", Level = 2, GridPos = {X = 9, Y = 10}},
			{UnitId = "10016", Level = 4, GridPos = {X = 11, Y = 10}},
			{UnitId = "10018", Level = 4, GridPos = {X = 7, Y = 12}},
			{UnitId = "10023", Level = 2, GridPos = {X = 3, Y = 2}},
			{UnitId = "10017", Level = 5, GridPos = {X = 5, Y = 2}},
			{UnitId = "10021", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10017", Level = 5, GridPos = {X = 9, Y = 2}},
			{UnitId = "10023", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10021", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10023", Level = 2, GridPos = {X = 4, Y = 4}},
			{UnitId = "10016", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10021", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10016", Level = 4, GridPos = {X = 12, Y = 4}},
			{UnitId = "10018", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 3, Y = 6}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10016", Level = 5, GridPos = {X = 11, Y = 10}},
			{UnitId = "10019", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10015", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10016", Level = 5, GridPos = {X = 5, Y = 2}},
			{UnitId = "10015", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10017", Level = 5, GridPos = {X = 9, Y = 2}},
			{UnitId = "10016", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10018", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10023", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10017", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10022", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10016", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10017", Level = 3, GridPos = {X = 5, Y = 6}},
			{UnitId = "10016", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10016", Level = 5, GridPos = {X = 9, Y = 6}},
		},

		-- Stage 6
		[6] = {
			{UnitId = "10017", Level = 4, GridPos = {X = 3, Y = 2}},
			{UnitId = "10019", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10021", Level = 5, GridPos = {X = 7, Y = 2}},
			{UnitId = "10023", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10021", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10015", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10017", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10023", Level = 2, GridPos = {X = 10, Y = 4}},
			{UnitId = "10016", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 3, Y = 6}},
			{UnitId = "10015", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10016", Level = 3, GridPos = {X = 9, Y = 6}},
			{UnitId = "10017", Level = 5, GridPos = {X = 11, Y = 6}},
			{UnitId = "10017", Level = 5, GridPos = {X = 13, Y = 6}},
		},

		-- Stage 7
		[7] = {
			{UnitId = "10016", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 3, GridPos = {X = 9, Y = 2}},
			{UnitId = "10021", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10017", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10015", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10016", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10016", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10016", Level = 4, GridPos = {X = 12, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10015", Level = 3, GridPos = {X = 3, Y = 6}},
			{UnitId = "10017", Level = 3, GridPos = {X = 5, Y = 6}},
			{UnitId = "10016", Level = 5, GridPos = {X = 7, Y = 6}},
			{UnitId = "10016", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10018", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10023", Level = 5, GridPos = {X = 2, Y = 8}},
			{UnitId = "10019", Level = 4, GridPos = {X = 4, Y = 8}},
			{UnitId = "10015", Level = 4, GridPos = {X = 6, Y = 8}},
		},

		-- Stage 8
		[8] = {
			{UnitId = "10016", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10023", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10025", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10016", Level = 4, GridPos = {X = 12, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10016", Level = 5, GridPos = {X = 5, Y = 6}},
			{UnitId = "10023", Level = 2, GridPos = {X = 7, Y = 6}},
			{UnitId = "10015", Level = 3, GridPos = {X = 9, Y = 6}},
			{UnitId = "10015", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10017", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10023", Level = 2, GridPos = {X = 2, Y = 8}},
			{UnitId = "10016", Level = 5, GridPos = {X = 4, Y = 8}},
			{UnitId = "10023", Level = 3, GridPos = {X = 6, Y = 8}},
			{UnitId = "10017", Level = 5, GridPos = {X = 8, Y = 8}},
			{UnitId = "10018", Level = 3, GridPos = {X = 10, Y = 8}},
		},

		-- Stage 9
		[9] = {
			{UnitId = "10015", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10021", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10016", Level = 5, GridPos = {X = 12, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10015", Level = 3, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 3, GridPos = {X = 5, Y = 6}},
			{UnitId = "10021", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10022", Level = 2, GridPos = {X = 9, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10016", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10018", Level = 3, GridPos = {X = 2, Y = 8}},
			{UnitId = "10023", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10022", Level = 3, GridPos = {X = 6, Y = 8}},
			{UnitId = "10017", Level = 3, GridPos = {X = 8, Y = 8}},
			{UnitId = "10023", Level = 5, GridPos = {X = 10, Y = 8}},
			{UnitId = "10022", Level = 3, GridPos = {X = 12, Y = 8}},
			{UnitId = "10025", Level = 3, GridPos = {X = 3, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 10}},
		},

		-- Stage 10
		[10] = {
			{UnitId = "10015", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10021", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10016", Level = 5, GridPos = {X = 1, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10021", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10023", Level = 2, GridPos = {X = 9, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10021", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 2, Y = 8}},
			{UnitId = "10022", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10023", Level = 4, GridPos = {X = 6, Y = 8}},
			{UnitId = "10017", Level = 5, GridPos = {X = 8, Y = 8}},
			{UnitId = "10019", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10016", Level = 5, GridPos = {X = 12, Y = 8}},
			{UnitId = "10023", Level = 3, GridPos = {X = 3, Y = 10}},
			{UnitId = "10015", Level = 3, GridPos = {X = 5, Y = 10}},
			{UnitId = "10023", Level = 4, GridPos = {X = 7, Y = 10}},
			{UnitId = "10021", Level = 3, GridPos = {X = 9, Y = 10}},
		},

	}
}

-- ==================== Chapter 7 ====================
EnemyConfig.Chapters[7] = {
	ChapterId = 7,
	ChapterName = "Chapter 7",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10024", Level = 2, GridPos = {X = 12, Y = 8}},
			{UnitId = "10024", Level = 2, GridPos = {X = 3, Y = 10}},
			{UnitId = "10021", Level = 3, GridPos = {X = 5, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 10}},
			{UnitId = "10023", Level = 4, GridPos = {X = 9, Y = 10}},
			{UnitId = "10025", Level = 2, GridPos = {X = 11, Y = 10}},
			{UnitId = "10023", Level = 4, GridPos = {X = 7, Y = 12}},
			{UnitId = "10025", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10025", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10021", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10024", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10023", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10022", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10025", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10022", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10024", Level = 2, GridPos = {X = 12, Y = 4}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 10}},
			{UnitId = "10025", Level = 2, GridPos = {X = 7, Y = 10}},
			{UnitId = "10023", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10021", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10025", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10025", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10021", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10023", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10023", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10024", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10021", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10025", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10024", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10025", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 1, Y = 6}},
			{UnitId = "10024", Level = 2, GridPos = {X = 3, Y = 6}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10024", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10024", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10024", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10024", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10023", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10022", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10025", Level = 2, GridPos = {X = 9, Y = 2}},
			{UnitId = "10023", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10022", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 6, Y = 4}},
			{UnitId = "10025", Level = 2, GridPos = {X = 8, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10025", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10021", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 6}},
			{UnitId = "10025", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 9, Y = 6}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10024", Level = 2, GridPos = {X = 7, Y = 12}},
			{UnitId = "10021", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10022", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10019", Level = 5, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 2}},
			{UnitId = "10022", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10023", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10025", Level = 2, GridPos = {X = 6, Y = 4}},
			{UnitId = "10022", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10022", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10025", Level = 2, GridPos = {X = 12, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10025", Level = 2, GridPos = {X = 5, Y = 6}},
			{UnitId = "10021", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10025", Level = 2, GridPos = {X = 11, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 13, Y = 6}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10023", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10022", Level = 3, GridPos = {X = 9, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10022", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10022", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10024", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10024", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10025", Level = 3, GridPos = {X = 5, Y = 6}},
			{UnitId = "10021", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 2, Y = 8}},
			{UnitId = "10021", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10021", Level = 4, GridPos = {X = 6, Y = 8}},
		},

		-- Stage 6
		[6] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10024", Level = 2, GridPos = {X = 11, Y = 2}},
			{UnitId = "10023", Level = 3, GridPos = {X = 2, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10025", Level = 2, GridPos = {X = 10, Y = 4}},
			{UnitId = "10025", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 9, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 2, Y = 8}},
			{UnitId = "10022", Level = 5, GridPos = {X = 4, Y = 8}},
			{UnitId = "10019", Level = 4, GridPos = {X = 6, Y = 8}},
			{UnitId = "10022", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10023", Level = 4, GridPos = {X = 10, Y = 8}},
		},

		-- Stage 7
		[7] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 4, Y = 4}},
			{UnitId = "10023", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 10, Y = 4}},
			{UnitId = "10023", Level = 4, GridPos = {X = 12, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 3, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 5, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 9, Y = 6}},
			{UnitId = "10018", Level = 5, GridPos = {X = 11, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 2, Y = 8}},
			{UnitId = "10022", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10021", Level = 3, GridPos = {X = 6, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 8, Y = 8}},
			{UnitId = "10018", Level = 5, GridPos = {X = 10, Y = 8}},
			{UnitId = "10018", Level = 5, GridPos = {X = 12, Y = 8}},
			{UnitId = "10022", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10023", Level = 4, GridPos = {X = 5, Y = 10}},
		},

		-- Stage 8
		[8] = {
			{UnitId = "10023", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 8, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10021", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 2, Y = 8}},
			{UnitId = "10023", Level = 4, GridPos = {X = 4, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 6, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10022", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10021", Level = 3, GridPos = {X = 12, Y = 8}},
			{UnitId = "10021", Level = 3, GridPos = {X = 3, Y = 10}},
			{UnitId = "10021", Level = 4, GridPos = {X = 5, Y = 10}},
			{UnitId = "10023", Level = 4, GridPos = {X = 7, Y = 10}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 10}},
		},

		-- Stage 9
		[9] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10022", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10018", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10022", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10018", Level = 5, GridPos = {X = 11, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10023", Level = 3, GridPos = {X = 2, Y = 8}},
			{UnitId = "10021", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10023", Level = 3, GridPos = {X = 6, Y = 8}},
			{UnitId = "10022", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10021", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10019", Level = 4, GridPos = {X = 12, Y = 8}},
			{UnitId = "10022", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10023", Level = 4, GridPos = {X = 5, Y = 10}},
			{UnitId = "10022", Level = 4, GridPos = {X = 7, Y = 10}},
			{UnitId = "10021", Level = 3, GridPos = {X = 9, Y = 10}},
			{UnitId = "10018", Level = 5, GridPos = {X = 11, Y = 10}},
			{UnitId = "10018", Level = 5, GridPos = {X = 7, Y = 12}},
			{UnitId = "10022", Level = 4, GridPos = {X = 3, Y = 2}},
		},

		-- Stage 10
		[10] = {
			{UnitId = "10023", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10022", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10018", Level = 5, GridPos = {X = 13, Y = 6}},
			{UnitId = "10023", Level = 4, GridPos = {X = 2, Y = 8}},
			{UnitId = "10022", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10018", Level = 5, GridPos = {X = 6, Y = 8}},
			{UnitId = "10021", Level = 3, GridPos = {X = 8, Y = 8}},
			{UnitId = "10023", Level = 4, GridPos = {X = 10, Y = 8}},
			{UnitId = "10019", Level = 4, GridPos = {X = 12, Y = 8}},
			{UnitId = "10018", Level = 5, GridPos = {X = 3, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 10}},
			{UnitId = "10022", Level = 4, GridPos = {X = 7, Y = 10}},
			{UnitId = "10021", Level = 4, GridPos = {X = 9, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 12}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10022", Level = 4, GridPos = {X = 7, Y = 2}},
		},

	}
}

-- ==================== Chapter 8 ====================
EnemyConfig.Chapters[8] = {
	ChapterId = 8,
	ChapterName = "Chapter 8",
	Stages = {
		-- Stage 1
		[1] = {
			{UnitId = "10018", Level = 5, GridPos = {X = 7, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 9, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 12}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 10, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 12, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 7, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 6}},
		},

		-- Stage 2
		[2] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 10}},
			{UnitId = "10020", Level = 5, GridPos = {X = 7, Y = 12}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 2}},
			{UnitId = "10025", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 12, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 7, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 6}},
			{UnitId = "10020", Level = 5, GridPos = {X = 11, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 13, Y = 6}},
		},

		-- Stage 3
		[3] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10018", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 12, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 7, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 6}},
			{UnitId = "10020", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 13, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 2, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 4, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 6, Y = 8}},
		},

		-- Stage 4
		[4] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 9, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10018", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10018", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 12, Y = 4}},
			{UnitId = "10025", Level = 3, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 7, Y = 6}},
			{UnitId = "10025", Level = 3, GridPos = {X = 9, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 11, Y = 6}},
			{UnitId = "10025", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 2, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 4, Y = 8}},
			{UnitId = "10018", Level = 5, GridPos = {X = 6, Y = 8}},
			{UnitId = "10024", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 10, Y = 8}},
		},

		-- Stage 5
		[5] = {
			{UnitId = "10024", Level = 3, GridPos = {X = 11, Y = 2}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10018", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10024", Level = 4, GridPos = {X = 6, Y = 4}},
			{UnitId = "10024", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10020", Level = 5, GridPos = {X = 12, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10018", Level = 5, GridPos = {X = 9, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 8}},
			{UnitId = "10019", Level = 4, GridPos = {X = 4, Y = 8}},
			{UnitId = "10018", Level = 5, GridPos = {X = 6, Y = 8}},
			{UnitId = "10019", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 10, Y = 8}},
			{UnitId = "10024", Level = 4, GridPos = {X = 12, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 3, Y = 10}},
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 10}},
		},

		-- Stage 6
		[6] = {
			{UnitId = "10020", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10025", Level = 3, GridPos = {X = 6, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 8, Y = 4}},
			{UnitId = "10019", Level = 4, GridPos = {X = 10, Y = 4}},
			{UnitId = "10024", Level = 4, GridPos = {X = 12, Y = 4}},
			{UnitId = "10024", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10020", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10024", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10024", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 8}},
			{UnitId = "10020", Level = 4, GridPos = {X = 4, Y = 8}},
			{UnitId = "10020", Level = 4, GridPos = {X = 6, Y = 8}},
			{UnitId = "10019", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10018", Level = 5, GridPos = {X = 10, Y = 8}},
			{UnitId = "10020", Level = 5, GridPos = {X = 12, Y = 8}},
			{UnitId = "10025", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 10}},
			{UnitId = "10018", Level = 5, GridPos = {X = 7, Y = 10}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 10}},
		},

		-- Stage 7
		[7] = {
			{UnitId = "10019", Level = 5, GridPos = {X = 8, Y = 4}},
			{UnitId = "10025", Level = 3, GridPos = {X = 10, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 12, Y = 4}},
			{UnitId = "10020", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 3, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10024", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10024", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10025", Level = 3, GridPos = {X = 2, Y = 8}},
			{UnitId = "10020", Level = 4, GridPos = {X = 4, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 6, Y = 8}},
			{UnitId = "10025", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 10, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 12, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10019", Level = 5, GridPos = {X = 5, Y = 10}},
			{UnitId = "10018", Level = 4, GridPos = {X = 7, Y = 10}},
			{UnitId = "10018", Level = 4, GridPos = {X = 9, Y = 10}},
			{UnitId = "10020", Level = 4, GridPos = {X = 11, Y = 10}},
			{UnitId = "10019", Level = 5, GridPos = {X = 7, Y = 12}},
			{UnitId = "10025", Level = 4, GridPos = {X = 3, Y = 2}},
		},

		-- Stage 8
		[8] = {
			{UnitId = "10025", Level = 3, GridPos = {X = 12, Y = 4}},
			{UnitId = "10020", Level = 4, GridPos = {X = 1, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 5, Y = 6}},
			{UnitId = "10025", Level = 3, GridPos = {X = 7, Y = 6}},
			{UnitId = "10020", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10020", Level = 4, GridPos = {X = 11, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10025", Level = 4, GridPos = {X = 2, Y = 8}},
			{UnitId = "10024", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 6, Y = 8}},
			{UnitId = "10022", Level = 5, GridPos = {X = 8, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 10, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 12, Y = 8}},
			{UnitId = "10020", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10018", Level = 4, GridPos = {X = 5, Y = 10}},
			{UnitId = "10025", Level = 4, GridPos = {X = 7, Y = 10}},
			{UnitId = "10024", Level = 4, GridPos = {X = 9, Y = 10}},
			{UnitId = "10019", Level = 5, GridPos = {X = 11, Y = 10}},
			{UnitId = "10020", Level = 5, GridPos = {X = 7, Y = 12}},
			{UnitId = "10020", Level = 5, GridPos = {X = 3, Y = 2}},
			{UnitId = "10018", Level = 5, GridPos = {X = 5, Y = 2}},
			{UnitId = "10019", Level = 5, GridPos = {X = 7, Y = 2}},
		},

		-- Stage 9
		[9] = {
			{UnitId = "10020", Level = 4, GridPos = {X = 3, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 5, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 9, Y = 6}},
			{UnitId = "10020", Level = 5, GridPos = {X = 11, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 13, Y = 6}},
			{UnitId = "10019", Level = 4, GridPos = {X = 2, Y = 8}},
			{UnitId = "10020", Level = 5, GridPos = {X = 4, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 6, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10024", Level = 3, GridPos = {X = 10, Y = 8}},
			{UnitId = "10019", Level = 5, GridPos = {X = 12, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10020", Level = 5, GridPos = {X = 5, Y = 10}},
			{UnitId = "10020", Level = 5, GridPos = {X = 7, Y = 10}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 10}},
			{UnitId = "10020", Level = 5, GridPos = {X = 11, Y = 10}},
			{UnitId = "10018", Level = 5, GridPos = {X = 7, Y = 12}},
			{UnitId = "10019", Level = 5, GridPos = {X = 3, Y = 2}},
			{UnitId = "10024", Level = 3, GridPos = {X = 5, Y = 2}},
			{UnitId = "10024", Level = 3, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 2}},
			{UnitId = "10024", Level = 4, GridPos = {X = 11, Y = 2}},
			{UnitId = "10025", Level = 4, GridPos = {X = 2, Y = 4}},
		},

		-- Stage 10
		[10] = {
			{UnitId = "10019", Level = 4, GridPos = {X = 7, Y = 6}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 6}},
			{UnitId = "10024", Level = 3, GridPos = {X = 11, Y = 6}},
			{UnitId = "10018", Level = 4, GridPos = {X = 13, Y = 6}},
			{UnitId = "10025", Level = 5, GridPos = {X = 2, Y = 8}},
			{UnitId = "10025", Level = 3, GridPos = {X = 4, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 6, Y = 8}},
			{UnitId = "10018", Level = 4, GridPos = {X = 8, Y = 8}},
			{UnitId = "10025", Level = 4, GridPos = {X = 10, Y = 8}},
			{UnitId = "10020", Level = 4, GridPos = {X = 12, Y = 8}},
			{UnitId = "10020", Level = 4, GridPos = {X = 3, Y = 10}},
			{UnitId = "10020", Level = 5, GridPos = {X = 5, Y = 10}},
			{UnitId = "10024", Level = 3, GridPos = {X = 7, Y = 10}},
			{UnitId = "10018", Level = 4, GridPos = {X = 9, Y = 10}},
			{UnitId = "10024", Level = 3, GridPos = {X = 11, Y = 10}},
			{UnitId = "10024", Level = 3, GridPos = {X = 7, Y = 12}},
			{UnitId = "10024", Level = 3, GridPos = {X = 3, Y = 2}},
			{UnitId = "10025", Level = 4, GridPos = {X = 5, Y = 2}},
			{UnitId = "10024", Level = 4, GridPos = {X = 7, Y = 2}},
			{UnitId = "10019", Level = 5, GridPos = {X = 9, Y = 2}},
			{UnitId = "10018", Level = 5, GridPos = {X = 11, Y = 2}},
			{UnitId = "10023", Level = 4, GridPos = {X = 2, Y = 4}},
			{UnitId = "10024", Level = 4, GridPos = {X = 4, Y = 4}},
			{UnitId = "10019", Level = 5, GridPos = {X = 6, Y = 4}},
		},

	}
}

-- ==================== Helpers ====================

function EnemyConfig.GetChapter(chapterId)
	return EnemyConfig.Chapters[chapterId]
end

function EnemyConfig.GetStageConfig(chapterId, stageNum)
	local chapter = EnemyConfig.Chapters[chapterId]
	if not chapter then
		return nil
	end

	return chapter.Stages[stageNum]
end

function EnemyConfig.GetStageCount(chapterId)
	local chapter = EnemyConfig.Chapters[chapterId]
	if not chapter or not chapter.Stages then
		return 0
	end

	local count = 0
	for _ in pairs(chapter.Stages) do
		count += 1
	end
	return count
end

-- ==================== Backward Compatibility ====================
-- Keep compatibility for legacy Stage001 / Stage010 lookups
setmetatable(EnemyConfig, {
	__index = function(_, key)
		if type(key) == "string" and key:match("^Stage%d+$") then
			local globalStage = tonumber(key:match("%d+"))
			if not globalStage then
				return nil
			end

			local cursor = globalStage
			for chapterId = 1, 8 do
				local stageCount = EnemyConfig.GetStageCount(chapterId)
				if cursor <= stageCount then
					local chapter = EnemyConfig.Chapters[chapterId]
					return chapter and chapter.Stages[cursor] or nil
				end
				cursor -= stageCount
			end
		end
		return nil
	end
})

return EnemyConfig
