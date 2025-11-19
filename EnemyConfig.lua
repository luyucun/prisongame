--[[
脚本名称: EnemyConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/EnemyConfig.lua
版本: V2.0

功能说明:
定义每个关卡的敌人配置
格式: {UnitId = "兵种ID", Level = 等级, GridPos = {X=行, Y=列}}
]]

local EnemyConfig = {}

-- ==================== Style01关卡敌人配置 ====================
-- V2.3修复: 使用兵种ID而非名称(与UnitConfig.Units的key保持一致)
-- 10001 = Noob, 10005 = Rookie

-- 第1关: 简单测试
EnemyConfig["Stage001"] = {
	{UnitId = "10001", Level = 1, GridPos = {X = 7, Y = 7}},
	{UnitId = "10001", Level = 1, GridPos = {X = 7, Y = 8}},
	{UnitId = "10001", Level = 1, GridPos = {X = 8, Y = 7}},
}

-- 第2关: 增加难度
EnemyConfig["Stage002"] = {
	{UnitId = "10005", Level = 1, GridPos = {X = 6, Y = 7}},
	{UnitId = "10005", Level = 1, GridPos = {X = 7, Y = 6}},
	{UnitId = "10001", Level = 2, GridPos = {X = 7, Y = 7}},
	{UnitId = "10005", Level = 1, GridPos = {X = 7, Y = 8}},
	{UnitId = "10005", Level = 1, GridPos = {X = 8, Y = 7}},
}

-- 第3关: 更强的敌人
EnemyConfig["Stage003"] = {
	{UnitId = "10005", Level = 2, GridPos = {X = 5, Y = 7}},
	{UnitId = "10005", Level = 2, GridPos = {X = 7, Y = 5}},
	{UnitId = "10005", Level = 2, GridPos = {X = 7, Y = 7}},
	{UnitId = "10005", Level = 2, GridPos = {X = 7, Y = 9}},
	{UnitId = "10005", Level = 2, GridPos = {X = 9, Y = 7}},
	{UnitId = "10001", Level = 3, GridPos = {X = 7, Y = 8}},
}

-- 第4关: 多样化敌人
EnemyConfig["Stage004"] = {
	{UnitId = "10005", Level = 2, GridPos = {X = 5, Y = 5}},
	{UnitId = "10005", Level = 2, GridPos = {X = 5, Y = 9}},
	{UnitId = "10001", Level = 3, GridPos = {X = 7, Y = 7}},
	{UnitId = "10005", Level = 2, GridPos = {X = 9, Y = 5}},
	{UnitId = "10005", Level = 2, GridPos = {X = 9, Y = 9}},
	{UnitId = "10005", Level = 3, GridPos = {X = 7, Y = 6}},
	{UnitId = "10005", Level = 3, GridPos = {X = 7, Y = 8}},
}

-- 第5关: 精英敌人
EnemyConfig["Stage005"] = {
	{UnitId = "10005", Level = 3, GridPos = {X = 5, Y = 6}},
	{UnitId = "10005", Level = 3, GridPos = {X = 5, Y = 8}},
	{UnitId = "10005", Level = 3, GridPos = {X = 6, Y = 7}},
	{UnitId = "10001", Level = 3, GridPos = {X = 7, Y = 7}},
	{UnitId = "10005", Level = 3, GridPos = {X = 8, Y = 7}},
	{UnitId = "10005", Level = 3, GridPos = {X = 9, Y = 6}},
	{UnitId = "10005", Level = 3, GridPos = {X = 9, Y = 8}},
	{UnitId = "10001", Level = 3, GridPos = {X = 7, Y = 9}},
}

-- 第6-10关: 使用默认配置(逐渐增加难度)
for i = 6, 10 do
	local stageName = string.format("Stage%03d", i)
	local level = math.min(3, i - 3)  -- 等级上限为3
	local enemyCount = math.min(10, 3 + i)  -- 敌人数量逐渐增加

	EnemyConfig[stageName] = {}

	-- 在网格中心区域生成敌人
	local centerX, centerY = 7, 7
	local spawnRadius = math.min(3, 1 + math.floor(i / 3))

	for j = 1, enemyCount do
		local offsetX = math.random(-spawnRadius, spawnRadius)
		local offsetY = math.random(-spawnRadius, spawnRadius)
		local gridX = math.max(1, math.min(14, centerX + offsetX))
		local gridY = math.max(1, math.min(14, centerY + offsetY))

		-- V2.3修复: 使用兵种ID (10001=Noob, 10005=Rookie)
		local unitId = (j % 2 == 0) and "10005" or "10001"

		table.insert(EnemyConfig[stageName], {
			UnitId = unitId,
			Level = level,
			GridPos = {X = gridX, Y = gridY}
		})
	end
end

return EnemyConfig
