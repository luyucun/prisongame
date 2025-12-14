--[[
脚本名称: ClientUnitManager
脚本类型: ModuleScript (客户端系统)
脚本位置: StarterPlayer/StarterPlayerScripts/ClientAI/ClientUnitManager
版本: V4.0 - 客户端AI迁移
]]

--[[
客户端单位管理器
职责:
1. 管理客户端所有战斗单位的索引（按 battleId 和 team 分组）
2. 提供高效的寻敌接口
3. 维护单位位置缓存
4. 支持单位注册、注销和查询

V4.0新增:
- 客户端AI专用，与服务端UnitManager功能对齐
- 轻量化设计，减少客户端负载
- 移除不必要的空间网格，使用简单列表遍历
]]

local ClientUnitManager = {}

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 私有变量 ====================

-- 战斗单位索引 [battleId][team] = {unitModel1, unitModel2, ...}
local battleUnits = {}

-- 单位位置缓存 [unitModel] = {Position = Vector3, LastUpdateTime = number}
local unitPositionCache = {}

-- 单位所属信息 [unitModel] = {BattleId = number, Team = string, UnitId = string, Level = number}
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
		print(GameConfig.LOG_PREFIX, "[ClientUnitManager]", ...)
	end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[ClientUnitManager]", ...)
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
function ClientUnitManager.Initialize()
	if isInitialized then
		return true
	end

	-- 初始化数据结构
	battleUnits = {}
	unitPositionCache = {}
	unitBattleInfo = {}

	isInitialized = true
	DebugLog("客户端单位管理器初始化完成")
	return true
end

--[[
注册单位
@param battleId number - 战斗ID
@param team string - 队伍("Attack"或"Defense")
@param unitModel Model - 单位模型
@param unitId string - 单位配置ID
@param level number - 单位等级
@return boolean - 是否注册成功
]]
function ClientUnitManager.RegisterUnit(battleId, team, unitModel, unitId, level)
	-- 参数验证
	if not battleId or not team or not unitModel or not unitId or not level then
		WarnLog("注册单位失败：参数缺失")
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
			WarnLog("单位已注册:", unitModel.Name)
			return false
		end
	end

	-- 注册单位
	table.insert(battleUnits[battleId][team], unitModel)

	-- 记录单位所属信息
	unitBattleInfo[unitModel] = {
		BattleId = battleId,
		Team = team,
		UnitId = unitId,
		Level = level,
	}

	-- 初始化位置缓存
	GetUnitPosition(unitModel, true)

	DebugLog(string.format("注册单位: BattleId=%s, Team=%s, Unit=%s, UnitId=%s, Level=%s",
		tostring(battleId), tostring(team), tostring(unitModel.Name), tostring(unitId), tostring(level)))

	return true
end

--[[
注销单位
@param unitModel Model - 单位模型
@return boolean - 是否注销成功
]]
function ClientUnitManager.UnregisterUnit(unitModel)
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

	DebugLog(string.format("注销单位: BattleId=%s, Team=%s, Unit=%s",
		tostring(battleId), tostring(team), tostring(unitModel.Name)))

	return true
end

--[[
获取指定战斗和队伍的所有单位
@param battleId number - 战斗ID
@param team string - 队伍
@return table - 单位列表
]]
function ClientUnitManager.GetBattleUnits(battleId, team)
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
function ClientUnitManager.GetEnemyTeam(team)
	if team == BattleConfig.Team.ATTACK then
		return BattleConfig.Team.DEFENSE
	elseif team == BattleConfig.Team.DEFENSE then
		return BattleConfig.Team.ATTACK
	end
	return nil
end

--[[
获取最近的敌人（客户端版本）
@param unitModel Model - 当前单位
@param maxDistance number - 最大搜索距离
@return Model|nil - 最近的敌人
@return number|nil - 距离
]]
function ClientUnitManager.GetClosestEnemy(unitModel, maxDistance, forceUpdatePositions)
	-- 1. 获取自身信息
	local info = unitBattleInfo[unitModel]
	if not info then
		return nil, nil
	end

	local battleId = info.BattleId
	local myTeam = info.Team
	local enemyTeam = ClientUnitManager.GetEnemyTeam(myTeam)
	if not enemyTeam then
		return nil, nil
	end

	local forceUpdate = forceUpdatePositions == true

	-- 2. 获取自身位置
	local myPos = GetUnitPosition(unitModel, forceUpdate)
	if not myPos then
		return nil, nil
	end

	-- 3. 获取所有敌人列表
	local enemies = ClientUnitManager.GetBattleUnits(battleId, enemyTeam)
	if not enemies or #enemies == 0 then
		return nil, nil
	end

	local closestUnit = nil
	local closestDist = maxDistance or math.huge

	-- 4. 简单直接的循环遍历 (O(N))，这在N<200时极快
	for _, enemy in ipairs(enemies) do
		if enemy and enemy.Parent then -- 基础有效性检查
			-- V4.1修复：客户端寻敌时，可能存在Humanoid尚未复制完成的短窗口
			-- 仅在明确死亡时跳过（IsDead 或 Humanoid.Health<=0）
			local isDead = enemy:GetAttribute("IsDead")
			if not isDead then
				local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid") or enemy:FindFirstChild("Humanoid")
				if not enemyHumanoid or enemyHumanoid.Health > 0 then
					local enemyPos = GetUnitPosition(enemy, forceUpdate)
					if enemyPos then
						local dist = (myPos - enemyPos).Magnitude
						if dist < closestDist then
							closestDist = dist
							closestUnit = enemy
						end
					end
				end
			end
		end
	end

	return closestUnit, closestDist
end

--[[
更新单位位置缓存（供ClientAI调用）
@param unitModel Model - 单位模型
@param position Vector3 - 新位置
]]
function ClientUnitManager.UpdateUnitPosition(unitModel, position)
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
function ClientUnitManager.GetUnitCount(battleId, team)
	local units = ClientUnitManager.GetBattleUnits(battleId, team)
	-- 只统计活着的单位
	local aliveCount = 0
	for _, unit in ipairs(units) do
		local humanoid = unit:FindFirstChild("Humanoid")
		if humanoid and humanoid.Health > 0 then
			aliveCount = aliveCount + 1
		end
	end
	return aliveCount
end

--[[
清理战斗的所有单位
@param battleId number - 战斗ID
]]
function ClientUnitManager.ClearBattle(battleId)
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
@return table|nil - {BattleId = number, Team = string, UnitId = string, Level = number}
]]
function ClientUnitManager.GetUnitBattleInfo(unitModel)
	return unitBattleInfo[unitModel]
end

--[[
检查单位是否已注册
@param unitModel Model - 单位模型
@return boolean - 是否已注册
]]
function ClientUnitManager.IsUnitRegistered(unitModel)
	return unitBattleInfo[unitModel] ~= nil
end

--[[
获取所有战斗ID列表
@return table - 战斗ID数组
]]
function ClientUnitManager.GetAllBattleIds()
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
function ClientUnitManager.DebugPrintBattleStats(battleId)
	if not battleUnits[battleId] then
		print(string.format("[ClientUnitManager Debug] BattleId=%s 不存在", tostring(battleId)))
		return
	end

	print(string.format("=== ClientUnitManager Battle Stats: BattleId=%s ===", tostring(battleId)))
	for team, units in pairs(battleUnits[battleId]) do
		print(string.format("  Team=%s: %s units", tostring(team), tostring(#units)))
		for i, unit in ipairs(units) do
			local info = unitBattleInfo[unit]
			print(string.format("    [%d] %s (UnitId=%s, Level=%d)",
				i, unit.Name, info.UnitId or "?", info.Level or 0))
		end
	end
	print("==========================================")
end

return ClientUnitManager
