--[[
脚本名称: UnitManager
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitManager
版本: V1.5.1
]]

--[[
单位索引管理器
职责:
1. 管理所有战斗中的单位,按 battleId 和 team 分组
2. 提供高效的寻敌接口
3. 维护单位位置缓存,减少重复计算
4. 广播单位死亡/位置变化事件

优势:
- 分组索引,避免全局遍历
- 位置缓存,减少实例访问
- 高效寻敌,只遍历敌方队伍
- 死亡单位立即清理
]]

local UnitManager = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 私有变量 ====================

-- 战斗单位索引 [battleId][team] = {unitModel1, unitModel2, ...}
local battleUnits = {}

-- 单位位置缓存 [unitModel] = {Position = Vector3, LastUpdateTime = number}
local unitPositionCache = {}

-- 单位所属信息 [unitModel] = {BattleId = number, Team = string}
local unitBattleInfo = {}

-- 是否已初始化
local isInitialized = false

-- V2.4新增：空间分桶系统（SpatialGrid）
-- 将战场划分为网格，加速敌人查询从O(m)→O(1)
local GRID_SIZE = 4  -- 网格大小（studs）
local spatialGrids = {}  -- [battleId] = {gridKey = {unitModel1, unitModel2, ...}}
local unitGridMapping = {}  -- [unitModel] = {battleId = xx, gridKey = "x,y,z"}

--[[
V2.4新增：计算位置对应的网格key
@param position Vector3 - 位置
@return string - 网格key (格式: "x,y,z")
]]
local function GetGridKey(position)
	local gridX = math.floor(position.X / GRID_SIZE)
	local gridY = math.floor(position.Y / GRID_SIZE)
	local gridZ = math.floor(position.Z / GRID_SIZE)
	return string.format("%d,%d,%d", gridX, gridY, gridZ)
end

--[[
V2.4新增：获取相邻的网格keys（包括中心）
@param gridKey string - 中心网格key
@param searchRange number - 搜索范围（studs）
@return table - 相邻网格key列表
]]
local function GetAdjacentGridKeys(gridKey, searchRange)
	local x, y, z = gridKey:match("(-?%d+),(-?%d+),(-?%d+)")
	x, y, z = tonumber(x), tonumber(y), tonumber(z)

	-- 根据搜索范围动态计算网格半径
	-- 例如：searchRange=200 studs, GRID_SIZE=4 studs → radius=50格
	local radius = math.ceil(searchRange / GRID_SIZE)

	-- 限制最大半径，避免性能问题（最多检查100x100x100的立方体）
	radius = math.min(radius, 50)

	local adjacent = {}
	-- 检查中心及周围的网格立方体
	for dx = -radius, radius do
		for dy = -radius, radius do
			for dz = -radius, radius do
				table.insert(adjacent, string.format("%d,%d,%d", x + dx, y + dy, z + dz))
			end
		end
	end

	return adjacent
end

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
	if BattleConfig.DEBUG_COMBAT_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitManager]", ...)
	end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[UnitManager]", ...)
end

--[[
获取单位的位置(带缓存)
@param unitModel Model - 单位模型
@param forceUpdate boolean - 是否强制更新缓存
@return Vector3|nil - 单位位置
]]
local function GetUnitPosition(unitModel, forceUpdate)
	-- 检查缓存
	if not forceUpdate and unitPositionCache[unitModel] then
		local cache = unitPositionCache[unitModel]
		-- 缓存未过期
		if tick() - cache.LastUpdateTime < 0.1 then
			return cache.Position
		end
	end

	-- 更新缓存
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local position = rootPart.Position
	unitPositionCache[unitModel] = {
		Position = position,
		LastUpdateTime = tick(),
	}

	return position
end

--[[
V2.4新增：更新单位的网格位置
@param unitModel Model - 单位模型
@param battleId number - 战斗ID
]]
local function UpdateUnitGridPosition(unitModel, battleId)
	local position = GetUnitPosition(unitModel)
	if not position then
		return
	end

	local newGridKey = GetGridKey(position)

	-- 获取或初始化战斗网格
	if not spatialGrids[battleId] then
		spatialGrids[battleId] = {}
	end

	-- 检查单位是否需要更新网格位置
	local currentMapping = unitGridMapping[unitModel]
	if currentMapping and currentMapping.battleId == battleId and currentMapping.gridKey == newGridKey then
		return  -- 单位仍在同一网格，无需更新
	end

	-- 从旧网格中移除单位（如果存在）
	if currentMapping then
		local oldGrid = spatialGrids[currentMapping.battleId]
		if oldGrid and oldGrid[currentMapping.gridKey] then
			local oldGridList = oldGrid[currentMapping.gridKey]
			for i, unit in ipairs(oldGridList) do
				if unit == unitModel then
					table.remove(oldGridList, i)
					break
				end
			end
		end
	end

	-- 添加单位到新网格
	if not spatialGrids[battleId][newGridKey] then
		spatialGrids[battleId][newGridKey] = {}
	end
	table.insert(spatialGrids[battleId][newGridKey], unitModel)

	-- 更新映射
	unitGridMapping[unitModel] = {
		battleId = battleId,
		gridKey = newGridKey,
	}
end

--[[
V2.4新增：从空间网格中查询范围内的敌人
@param unitModel Model - 查询单位
@param battleId number - 战斗ID
@param enemyTeam string - 敌方队伍
@param searchRange number - 搜索范围
@return table - 范围内的敌人列表
]]
local function GetNearbyEnemiesFromGrid(unitModel, battleId, enemyTeam, searchRange)
	local position = GetUnitPosition(unitModel)
	if not position then
		return {}
	end

	local battleGrid = spatialGrids[battleId]
	if not battleGrid then
		return {}
	end

	local gridKey = GetGridKey(position)
	local adjacentKeys = GetAdjacentGridKeys(gridKey, searchRange)

	local nearbyEnemies = {}
	for _, key in ipairs(adjacentKeys) do
		local gridUnits = battleGrid[key]
		if gridUnits then
			for _, otherUnit in ipairs(gridUnits) do
				-- 检查是否属于敌方队伍
				local otherInfo = unitBattleInfo[otherUnit]
				if otherInfo and otherInfo.BattleId == battleId and otherInfo.Team == enemyTeam then
					-- 进行最终距离检查
					local otherPos = GetUnitPosition(otherUnit)
					if otherPos then
						local distance = (position - otherPos).Magnitude
						if distance <= searchRange then
							table.insert(nearbyEnemies, {Unit = otherUnit, Distance = distance})
						end
					end
				end
			end
		end
	end

	-- 按距离排序
	table.sort(nearbyEnemies, function(a, b) return a.Distance < b.Distance end)
	return nearbyEnemies
end

-- ==================== 公共接口 ====================

--[[
初始化单位管理器
@return boolean - 是否初始化成功
]]
function UnitManager.Initialize()
	if isInitialized then
		WarnLog("UnitManager已经初始化过了")
		return true
	end

	DebugLog("正在初始化UnitManager...")

	-- 初始化数据结构
	battleUnits = {}
	unitPositionCache = {}
	unitBattleInfo = {}

	isInitialized = true
	DebugLog("UnitManager初始化完成")
	return true
end

--[[
注册单位
@param battleId number - 战斗ID
@param team string - 队伍("Attack"或"Defense")
@param unitModel Model - 单位模型
@return boolean - 是否注册成功
]]
function UnitManager.RegisterUnit(battleId, team, unitModel)
	-- 参数验证
	if not battleId or not team or not unitModel then
		WarnLog("RegisterUnit失败: 参数无效")
		return false
	end

	if not unitModel:IsA("Model") then
		WarnLog("RegisterUnit失败: unitModel不是Model类型")
		return false
	end

	-- 初始化战斗索引
	if not battleUnits[battleId] then
		battleUnits[battleId] = {}
	end

	if not battleUnits[battleId][team] then
		battleUnits[battleId][team] = {}
	end

	-- 检查是否已注册
	for _, unit in ipairs(battleUnits[battleId][team]) do
		if unit == unitModel then
			WarnLog("RegisterUnit警告: 单位已经注册过了")
			return false
		end
	end

	-- 注册单位
	table.insert(battleUnits[battleId][team], unitModel)

	-- 记录单位所属信息
	unitBattleInfo[unitModel] = {
		BattleId = battleId,
		Team = team,
	}

	-- 初始化位置缓存
	GetUnitPosition(unitModel, true)

	-- V2.4新增：初始化网格位置（SpatialGrid）
	UpdateUnitGridPosition(unitModel, battleId)

	DebugLog(string.format("注册单位: BattleId=%d, Team=%s, Unit=%s",
		battleId, team, unitModel.Name))

	return true
end

--[[
注销单位
@param unitModel Model - 单位模型
@return boolean - 是否注销成功
]]
function UnitManager.UnregisterUnit(unitModel)
	if not unitModel then
		return false
	end

	-- 获取单位信息
	local info = unitBattleInfo[unitModel]
	if not info then
		return false
	end

	local battleId = info.BattleId
	local team = info.Team

	-- 从战斗索引中移除
	if battleUnits[battleId] and battleUnits[battleId][team] then
		local units = battleUnits[battleId][team]
		for i, unit in ipairs(units) do
			if unit == unitModel then
				table.remove(units, i)
				break
			end
		end
	end

	-- 清理缓存
	unitBattleInfo[unitModel] = nil
	unitPositionCache[unitModel] = nil

	-- V2.4新增：清理网格映射
	local mapping = unitGridMapping[unitModel]
	if mapping then
		local grid = spatialGrids[mapping.battleId]
		if grid and grid[mapping.gridKey] then
			local gridList = grid[mapping.gridKey]
			for i, unit in ipairs(gridList) do
				if unit == unitModel then
					table.remove(gridList, i)
					break
				end
			end
		end
		unitGridMapping[unitModel] = nil
	end

	DebugLog(string.format("注销单位: BattleId=%d, Team=%s, Unit=%s",
		battleId, team, unitModel.Name))

	return true
end

--[[
获取指定战斗和队伍的所有单位
@param battleId number - 战斗ID
@param team string - 队伍
@return table - 单位列表
]]
function UnitManager.GetBattleUnits(battleId, team)
	if not battleUnits[battleId] then
		return {}
	end

	if not battleUnits[battleId][team] then
		return {}
	end

	return battleUnits[battleId][team]
end

--[[
获取单位的敌方队伍名称
@param team string - 当前队伍
@return string - 敌方队伍名称
]]
function UnitManager.GetEnemyTeam(team)
	if team == BattleConfig.Team.ATTACK then
		return BattleConfig.Team.DEFENSE
	elseif team == BattleConfig.Team.DEFENSE then
		return BattleConfig.Team.ATTACK
	end
	return nil
end

--[[
获取最近的敌人(优化版 - V2.4使用SpatialGrid)
@param unitModel Model - 当前单位
@param maxDistance number - 最大搜索距离
@return Model|nil - 最近的敌人
@return number|nil - 距离
]]
function UnitManager.GetClosestEnemy(unitModel, maxDistance)
	-- 获取单位信息
	local info = unitBattleInfo[unitModel]
	if not info then
		return nil, nil
	end

	local battleId = info.BattleId
	local myTeam = info.Team

	-- 获取敌方队伍名称
	local enemyTeam = UnitManager.GetEnemyTeam(myTeam)
	if not enemyTeam then
		return nil, nil
	end

	-- 获取自己的位置
	local myPos = GetUnitPosition(unitModel, false)
	if not myPos then
		return nil, nil
	end

	-- V2.4优化：使用SpatialGrid查询（O(1)而非O(m)）
	-- 注意：GetNearbyEnemiesFromGrid已按距离排序，直接返回第一个即可
	local nearbyEnemies = GetNearbyEnemiesFromGrid(unitModel, battleId, enemyTeam, maxDistance or math.huge)

	if nearbyEnemies and #nearbyEnemies > 0 then
		-- 列表已按距离排序，第一个就是最近的
		local closestResult = nearbyEnemies[1]
		return closestResult.Unit, closestResult.Distance
	end

	return nil, nil
end

--[[
遍历敌方单位(使用迭代器)
@param battleId number - 战斗ID
@param team string - 当前队伍
@return function - 迭代器函数
]]
function UnitManager.IterEnemies(battleId, team)
	local enemyTeam = UnitManager.GetEnemyTeam(team)
	if not enemyTeam then
		return function() return nil end
	end

	local enemies = UnitManager.GetBattleUnits(battleId, enemyTeam)
	local index = 0

	return function()
		index = index + 1
		if index <= #enemies then
			return enemies[index]
		end
		return nil
	end
end

--[[
更新单位位置缓存
@param unitModel Model - 单位模型
@param position Vector3 - 新位置
]]
function UnitManager.UpdateUnitPosition(unitModel, position)
	unitPositionCache[unitModel] = {
		Position = position,
		LastUpdateTime = tick(),
	}
end

--[[
获取队伍单位数量
@param battleId number - 战斗ID
@param team string - 队伍
@return number - 单位数量
]]
function UnitManager.GetUnitCount(battleId, team)
	local units = UnitManager.GetBattleUnits(battleId, team)
	return #units
end

--[[
获取战斗中所有单位数量
@param battleId number - 战斗ID
@return number - 总单位数量
]]
function UnitManager.GetBattleTotalUnitCount(battleId)
	if not battleUnits[battleId] then
		return 0
	end

	local count = 0
	for team, units in pairs(battleUnits[battleId]) do
		count = count + #units
	end

	return count
end

--[[
清理战斗的所有单位
@param battleId number - 战斗ID
]]
function UnitManager.ClearBattle(battleId)
	if not battleUnits[battleId] then
		return
	end

	-- 遍历所有队伍
	for team, units in pairs(battleUnits[battleId]) do
		-- 清理每个单位的缓存
		for _, unit in ipairs(units) do
			unitBattleInfo[unit] = nil
			unitPositionCache[unit] = nil

			-- V2.4新增：清理网格映射
			local mapping = unitGridMapping[unit]
			if mapping then
				local grid = spatialGrids[mapping.battleId]
				if grid and grid[mapping.gridKey] then
					local gridList = grid[mapping.gridKey]
					for i, gridUnit in ipairs(gridList) do
						if gridUnit == unit then
							table.remove(gridList, i)
							break
						end
					end
				end
				unitGridMapping[unit] = nil
			end
		end
	end

	-- 清理网格数据
	spatialGrids[battleId] = nil

	-- 清理战斗索引
	battleUnits[battleId] = nil

	DebugLog(string.format("清理战斗: BattleId=%d", battleId))
end

--[[
获取单位的战斗信息
@param unitModel Model - 单位模型
@return table|nil - {BattleId = number, Team = string}
]]
function UnitManager.GetUnitBattleInfo(unitModel)
	return unitBattleInfo[unitModel]
end

--[[
检查单位是否已注册
@param unitModel Model - 单位模型
@return boolean - 是否已注册
]]
function UnitManager.IsUnitRegistered(unitModel)
	return unitBattleInfo[unitModel] ~= nil
end

--[[
获取所有战斗ID列表
@return table - 战斗ID数组
]]
function UnitManager.GetAllBattleIds()
	local battleIds = {}
	for battleId, _ in pairs(battleUnits) do
		table.insert(battleIds, battleId)
	end
	return battleIds
end

--[[
调试:打印战斗单位统计
@param battleId number - 战斗ID
]]
function UnitManager.DebugPrintBattleStats(battleId)
	if not battleUnits[battleId] then
		print(string.format("[UnitManager Debug] BattleId=%d 不存在", battleId))
		return
	end

	print(string.format("=== UnitManager Battle Stats: BattleId=%d ===", battleId))
	for team, units in pairs(battleUnits[battleId]) do
		print(string.format("  Team=%s: %d units", team, #units))
		for i, unit in ipairs(units) do
			print(string.format("    [%d] %s", i, unit.Name))
		end
	end
	print("==========================================")
end

-- ==================== V2.0新增: 战役系统支持 ====================

--[[
获取玩家基地的所有兵种（用于战役系统）
@param player Player - 玩家实例
@return table - 兵种Model实例列表
]]
function UnitManager.GetHomeUnits(player)
	-- V2.0实现: 使用PlacementSystem获取玩家基地已放置的兵种
	local PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)

	local homeUnits = PlacementSystem.GetPlacedUnitModels(player)

	if BattleConfig.DEBUG_COMBAT_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitManager] GetHomeUnits:", player.Name, "兵种数量:", #homeUnits)
	end

	return homeUnits
end

--[[
保存单位的当前血量（用于血量继承）
@param unitInstance Model - 兵种实例
@param currentHP number - 当前血量
]]
function UnitManager.SaveUnitHP(unitInstance, currentHP)
	if not unitInstance or not currentHP then
		return
	end

	-- 保存到Attribute
	unitInstance:SetAttribute("SavedHP", currentHP)

	if BattleConfig.DEBUG_COMBAT_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitManager] 保存单位血量:", unitInstance.Name, currentHP)
	end
end

--[[
恢复单位的血量（用于血量继承）
@param unitInstance Model - 兵种实例
@return number|nil - 保存的血量，如果没有则返回nil
]]
function UnitManager.RestoreUnitHP(unitInstance)
	if not unitInstance then
		return nil
	end

	local savedHP = unitInstance:GetAttribute("SavedHP")

	if savedHP and unitInstance:FindFirstChild("Humanoid") then
		unitInstance.Humanoid.Health = savedHP

		if BattleConfig.DEBUG_COMBAT_LOGS then
			print(GameConfig.LOG_PREFIX, "[UnitManager] 恢复单位血量:", unitInstance.Name, savedHP)
		end

		return savedHP
	end

	return nil
end

return UnitManager
