--[[
脚本名称: UnitManager
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitManager
版本: V2.6 修复版 - 移除导致卡死的空间网格，回归高效列表遍历
]]

--[[
单位索引管理器 (性能优化版)
职责:
1. 管理所有战斗中的单位,按 battleId 和 team 分组
2. 提供高效的寻敌接口
3. 维护单位位置缓存,减少重复计算

V2.6修复说明:
- 移除了V2.4引入的空间网格系统（SpatialGrid）
- 原因：当searchRange很大时，三重循环会导致Script Timeout
- 改用简单的列表遍历（O(N)），对于<200个单位极快且稳定
- 保留了位置缓存机制，保持高效
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
		-- 缓存未过期(0.1秒缓存时间)
		if tick() - cache.LastUpdateTime < 0.1 then
			return cache.Position
		end
	end

	-- 更新缓存
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart") or unitModel.PrimaryPart
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

-- ==================== 公共接口 ====================

--[[
初始化单位管理器
@return boolean - 是否初始化成功
]]
function UnitManager.Initialize()
	if isInitialized then
		return true
	end

	-- 初始化数据结构
	battleUnits = {}
	unitPositionCache = {}
	unitBattleInfo = {}

	isInitialized = true
	print(GameConfig.LOG_PREFIX, "[UnitManager] 初始化完成 (高效列表模式)")
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
		return false
	end

	-- 初始化战斗索引
	if not battleUnits[battleId] then
		battleUnits[battleId] = {}
	end

	if not battleUnits[battleId][team] then
		battleUnits[battleId][team] = {}
	end

	-- 检查是否已注册(避免重复)
	for _, unit in ipairs(battleUnits[battleId][team]) do
		if unit == unitModel then
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
🔥 V2.6关键修复：GetClosestEnemy
移除空间网格搜索，改用直接遍历敌方列表。
对于 Roblox Lua，直接遍历 50-100 个单位比维护复杂的 3D 网格要快得多，且绝对稳定。
@param unitModel Model - 当前单位
@param maxDistance number - 最大搜索距离
@return Model|nil - 最近的敌人
@return number|nil - 距离
]]
function UnitManager.GetClosestEnemy(unitModel, maxDistance)
	-- 1. 获取自身信息
	local info = unitBattleInfo[unitModel]
	if not info then
		return nil, nil
	end

	local battleId = info.BattleId
	local myTeam = info.Team
	local enemyTeam = UnitManager.GetEnemyTeam(myTeam)
	if not enemyTeam then
		return nil, nil
	end

	-- 2. 获取自身位置
	local myPos = GetUnitPosition(unitModel, false)
	if not myPos then
		return nil, nil
	end

	-- 3. 获取所有敌人列表
	local enemies = UnitManager.GetBattleUnits(battleId, enemyTeam)
	if not enemies or #enemies == 0 then
		return nil, nil
	end

	local closestUnit = nil
	local closestDist = maxDistance or math.huge

	-- 4. 简单直接的循环遍历 (O(N))，这在N<200时极快
	for _, enemy in ipairs(enemies) do
		if enemy and enemy.Parent then -- 基础有效性检查
			local enemyPos = GetUnitPosition(enemy, false)
			if enemyPos then
				local dist = (myPos - enemyPos).Magnitude
				if dist < closestDist then
					closestDist = dist
					closestUnit = enemy
				end
			end
		end
	end

	return closestUnit, closestDist
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
		end
	end

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
	return PlacementSystem.GetPlacedUnitModels(player)
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
	unitInstance:SetAttribute("SavedHP", currentHP)
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
		return savedHP
	end

	return nil
end

return UnitManager
