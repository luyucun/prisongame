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

-- 引用配置
local GameConfig = require(ServerScriptService.Config.GameConfig)
local BattleConfig = require(ServerScriptService.Config.BattleConfig)

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
获取最近的敌人(优化版)
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

	-- 获取敌方单位列表
	local enemies = UnitManager.GetBattleUnits(battleId, enemyTeam)
	if not enemies or #enemies == 0 then
		return nil, nil
	end

	-- 获取自己的位置
	local myPos = GetUnitPosition(unitModel, false)
	if not myPos then
		return nil, nil
	end

	-- 查找最近的敌人
	local closestEnemy = nil
	local closestDistance = maxDistance or math.huge

	for _, enemy in ipairs(enemies) do
		-- 跳过自己
		if enemy == unitModel then
			continue
		end

		-- 获取敌人位置
		local enemyPos = GetUnitPosition(enemy, false)
		if not enemyPos then
			continue
		end

		-- 计算距离
		local distance = (enemyPos - myPos).Magnitude

		-- 更新最近的敌人
		if distance < closestDistance then
			closestDistance = distance
			closestEnemy = enemy
		end
	end

	return closestEnemy, closestDistance
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

return UnitManager
