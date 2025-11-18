--[[
脚本名称: BattleManager
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/BattleManager
]]

--[[
战斗管理器
职责:
1. 管理所有战斗实例(支持多个玩家同时战斗)
2. 创建和销毁战斗实例
3. 分配战斗ID
4. 监控战斗状态
5. 处理战斗结束逻辑
版本: V1.5
]]

local BattleManager = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- 引用系统
local CombatSystem = require(ServerScriptService.Systems.CombatSystem)
local UnitAI = require(ServerScriptService.Systems.UnitAI)
local UnitManager = require(ServerScriptService.Systems.UnitManager)  -- V1.5.1新增
local PhysicsManager = require(ServerScriptService.Systems.PhysicsManager)  -- V2.2新增
local HitboxService = require(ServerScriptService.Systems.HitboxService)  -- V1.5.1新增

-- ==================== 私有变量 ====================

-- 存储所有战斗实例 [battleId] = BattleInstance
local battles = {}

-- 下一个战斗ID
local nextBattleId = 1

-- 死亡事件连接
local deathEventConnection = nil

-- 战斗状态更新事件
local battleStateUpdateEvent = nil

-- 是否已初始化
local isInitialized = false

-- ==================== 数据结构 ====================

--[[
BattleInstance = {
    BattleId = number,           -- 战斗实例ID
    PlayerId = number,           -- 发起战斗的玩家UserId
    AttackUnits = {},            -- 攻击方兵种列表 {unitModel1, unitModel2...}
    DefenseUnits = {},           -- 防守方兵种列表
    State = string,              -- 战斗状态: "Preparing", "Fighting", "Finished"
    StartTime = number,          -- 战斗开始时间
    Winner = string,             -- 胜利方: "Attack", "Defense", nil
}
]]

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
    if BattleConfig.DEBUG_COMBAT_LOGS then
        print(GameConfig.LOG_PREFIX, "[BattleManager]", ...)
    end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
    warn(GameConfig.LOG_PREFIX, "[BattleManager]", ...)
end

--[[
检查战斗是否结束
@param battleId number - 战斗ID
@return boolean, string - 是否结束, 胜利方
]]
local function CheckBattleEnd(battleId)
    local battle = battles[battleId]

    if not battle then
        return false, nil
    end

    -- 统计存活单位
    local attackAliveCount = 0
    local defenseAliveCount = 0

    for _, unit in ipairs(battle.AttackUnits) do
        if CombatSystem.IsUnitAlive(unit) then
            attackAliveCount = attackAliveCount + 1
        end
    end

    for _, unit in ipairs(battle.DefenseUnits) do
        if CombatSystem.IsUnitAlive(unit) then
            defenseAliveCount = defenseAliveCount + 1
        end
    end

    -- 判断胜负
    if attackAliveCount == 0 and defenseAliveCount > 0 then
        return true, BattleConfig.Team.DEFENSE
    elseif defenseAliveCount == 0 and attackAliveCount > 0 then
        return true, BattleConfig.Team.ATTACK
    elseif attackAliveCount == 0 and defenseAliveCount == 0 then
        return true, nil  -- 平局(双方同归于尽)
    end

    return false, nil
end

-- ==================== 公共接口 ====================

--[[
初始化战斗管理器
@return boolean - 是否初始化成功
]]
function BattleManager.Initialize()
    if isInitialized then
        WarnLog("战斗管理器已经初始化过了")
        return true
    end

    DebugLog("正在初始化战斗管理器...")

    -- 获取战斗状态更新事件
    local eventsFolder = ReplicatedStorage:WaitForChild("Events")
    local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")

    if battleEventsFolder then
        battleStateUpdateEvent = battleEventsFolder:FindFirstChild("BattleStateUpdate")

        if not battleStateUpdateEvent then
            WarnLog("未找到BattleStateUpdate事件,客户端将无法收到战斗状态更新通知")
        end

        -- 连接死亡事件,用于检查战斗结束
        local unitDeathEvent = battleEventsFolder:FindFirstChild("UnitDeath")

        if unitDeathEvent then
            deathEventConnection = unitDeathEvent.Event:Connect(function(deadUnit, killer, battleId)
                -- 检查战斗是否结束
                local isEnd, winner = CheckBattleEnd(battleId)

                if isEnd then
                    BattleManager.EndBattle(battleId, winner)
                end
            end)
        end
    end

    isInitialized = true

    DebugLog("战斗管理器初始化完成")
    return true
end

--[[
关闭战斗管理器
]]
function BattleManager.Shutdown()
    if deathEventConnection then
        deathEventConnection:Disconnect()
        deathEventConnection = nil
    end

    -- 清理所有战斗
    for battleId, _ in pairs(battles) do
        BattleManager.CleanupBattle(battleId)
    end

    battles = {}
    isInitialized = false

    DebugLog("战斗管理器已关闭")
end

--[[
创建战斗实例(V2.0扩展：支持战役模式)
@param playerId number|table - 玩家UserId 或 配置表{PlayerId, BattleType, AttackTeam, DefenseTeam, OnBattleEnd}
@param attackUnits table - 攻击方兵种列表(可选,如果第一个参数是配置表则忽略)
@param defenseUnits table - 防守方兵种列表(可选)
@return number|nil - 战斗ID,失败返回nil
]]
function BattleManager.CreateBattle(playerId, attackUnits, defenseUnits)
	-- V2.0: 支持配置表方式调用(用于战役系统)
	local config = nil
	if type(playerId) == "table" then
		config = playerId
		playerId = config.PlayerId
		attackUnits = config.AttackTeam or config.AttackUnits or {}
		defenseUnits = config.DefenseTeam or config.DefenseUnits or {}
	end

	-- 检查是否超过最大战斗数(遍历计数,因为battles是字典)
	local battleCount = 0
	for _ in pairs(battles) do
		battleCount = battleCount + 1
	end

	if battleCount >= BattleConfig.MAX_CONCURRENT_BATTLES then
		WarnLog("达到最大并发战斗数限制")
		return nil
	end

	-- 分配战斗ID
	local battleId = nextBattleId
	nextBattleId = nextBattleId + 1

	-- 创建战斗实例
	local battle = {
		BattleId = battleId,
		PlayerId = playerId,
		AttackUnits = attackUnits or {},
		DefenseUnits = defenseUnits or {},
		State = BattleConfig.BattleState.PREPARING,
		StartTime = 0,
		Winner = nil,
		-- V2.0新增字段
		BattleType = config and config.BattleType or "Test",  -- "Test"或"Campaign"
		OnBattleEnd = config and config.OnBattleEnd or nil,    -- 战斗结束回调
	}

	battles[battleId] = battle

	DebugLog(string.format("创建战斗实例: BattleId=%d, Type=%s, 攻击方%d单位, 防守方%d单位",
		battleId, battle.BattleType, #battle.AttackUnits, #battle.DefenseUnits))

	return battleId
end

--[[
开始战斗
@param battleId number - 战斗ID
@return boolean - 是否成功
]]
function BattleManager.StartBattle(battleId)
    local battle = battles[battleId]

    if not battle then
        WarnLog("StartBattle失败: 战斗不存在")
        return false
    end

    if battle.State ~= BattleConfig.BattleState.PREPARING then
        WarnLog("StartBattle失败: 战斗状态不正确")
        return false
    end

    -- 更新战斗状态
    battle.State = BattleConfig.BattleState.FIGHTING
    battle.StartTime = tick()

    -- V2.0新增：二次校验，移除无效单位
    local validAttackUnits = {}
    local validDefenseUnits = {}

    for _, unit in ipairs(battle.AttackUnits) do
        if unit and unit.Parent then
            local humanoid = unit:FindFirstChild("Humanoid")
            local rootPart = unit:FindFirstChild("HumanoidRootPart")
            if humanoid and rootPart then
                -- 检查是否锚定（战斗中不应该锚定）
                if rootPart.Anchored then
                    WarnLog(string.format("警告：攻击单位 %s 仍处于锚定状态，尝试解锚", unit.Name))
                    rootPart.Anchored = false
                end
                table.insert(validAttackUnits, unit)
            else
                WarnLog(string.format("移除无效攻击单位：%s（缺少Humanoid或RootPart）", unit.Name))
            end
        else
            WarnLog("移除无效攻击单位：实例无效或已销毁")
        end
    end

    for _, unit in ipairs(battle.DefenseUnits) do
        if unit and unit.Parent then
            local humanoid = unit:FindFirstChild("Humanoid")
            local rootPart = unit:FindFirstChild("HumanoidRootPart")
            if humanoid and rootPart then
                -- 检查是否锚定
                if rootPart.Anchored then
                    WarnLog(string.format("警告：防守单位 %s 仍处于锚定状态，尝试解锚", unit.Name))
                    rootPart.Anchored = false
                end
                table.insert(validDefenseUnits, unit)
            else
                WarnLog(string.format("移除无效防守单位：%s（缺少Humanoid或RootPart）", unit.Name))
            end
        else
            WarnLog("移除无效防守单位：实例无效或已销毁")
        end
    end

    -- 检查是否还有有效单位
    if #validAttackUnits == 0 or #validDefenseUnits == 0 then
        WarnLog(string.format("StartBattle失败：有效单位不足（攻击%d，防守%d）",
            #validAttackUnits, #validDefenseUnits))
        battle.State = BattleConfig.BattleState.FINISHED
        return false
    end

    -- 更新单位列表
    battle.AttackUnits = validAttackUnits
    battle.DefenseUnits = validDefenseUnits

    -- V2.0新增：初始化CombatSystem状态并启动AI
    -- 如果CombatSystem初始化失败，不启动AI
    local finalAttackUnits = {}
    local finalDefenseUnits = {}

    -- 处理攻击方
    for i, unit in ipairs(battle.AttackUnits) do
        UnitManager.RegisterUnit(battleId, BattleConfig.Team.ATTACK, unit)

        -- 2. 初始化CombatSystem状态
        local unitId = unit:GetAttribute("UnitId") or unit.Name
        local level = unit:GetAttribute("Level") or 1
        local success = CombatSystem.InitializeUnit(unit, unitId, level, BattleConfig.Team.ATTACK, battleId)

        if success then
            PhysicsManager.ConfigureUnitPhysics(unit, "ally")

            -- 4. 启动AI
            local aiStartResult = UnitAI.StartAI(unit)

            table.insert(finalAttackUnits, unit)
        end
    end

    -- 处理防守方
    for i, unit in ipairs(battle.DefenseUnits) do
        UnitManager.RegisterUnit(battleId, BattleConfig.Team.DEFENSE, unit)

        -- 2. 初始化CombatSystem状态
        local unitId = unit:GetAttribute("UnitId") or unit.Name
        local level = unit:GetAttribute("Level") or 1
        local success = CombatSystem.InitializeUnit(unit, unitId, level, BattleConfig.Team.DEFENSE, battleId)

        if success then
            PhysicsManager.ConfigureUnitPhysics(unit, "enemy")

            -- 4. 启动AI
            local aiStartResult = UnitAI.StartAI(unit)

            table.insert(finalDefenseUnits, unit)
        end
    end

    -- 再次检查：如果有单位初始化失败，更新战斗列表
    if #finalAttackUnits < #battle.AttackUnits or #finalDefenseUnits < #battle.DefenseUnits then
        WarnLog(string.format("部分单位初始化失败 - 攻击方: %d/%d, 防守方: %d/%d",
            #finalAttackUnits, #battle.AttackUnits,
            #finalDefenseUnits, #battle.DefenseUnits))

        battle.AttackUnits = finalAttackUnits
        battle.DefenseUnits = finalDefenseUnits

        -- 如果任一方单位为0，无法开战
        if #finalAttackUnits == 0 or #finalDefenseUnits == 0 then
            WarnLog("初始化后有效单位不足，无法开战")
            battle.State = BattleConfig.BattleState.FINISHED
            return false
        end
    end

    -- 通知客户端战斗状态更新
    if battleStateUpdateEvent then
        local player = Players:GetPlayerByUserId(battle.PlayerId)
        if player then
            battleStateUpdateEvent:FireClient(player, battleId, BattleConfig.BattleState.FIGHTING, nil)
        end
    end

    return true
end

--[[
结束战斗(V2.0扩展：触发OnBattleEnd回调)
@param battleId number - 战斗ID
@param winner string - 胜利方 ("Attack", "Defense", nil)
@return boolean - 是否成功
]]
function BattleManager.EndBattle(battleId, winner)
	local battle = battles[battleId]

	if not battle then
		WarnLog("EndBattle失败: 战斗不存在")
		return false
	end

	if battle.State == BattleConfig.BattleState.FINISHED then
		return true  -- 已经结束了
	end

	-- 更新战斗状态
	battle.State = BattleConfig.BattleState.FINISHED
	battle.Winner = winner

	-- 停止所有AI
	UnitAI.ClearBattleAIs(battleId)

	if winner then
		DebugLog(string.format("战斗结束: BattleId=%d, Type=%s, 胜利方=%s",
			battleId, battle.BattleType or "Test", winner))
	else
		DebugLog(string.format("战斗结束: BattleId=%d, Type=%s, 平局",
			battleId, battle.BattleType or "Test"))
	end

	-- V2.0: 触发OnBattleEnd回调(战役系统)
	if battle.OnBattleEnd then
		task.spawn(function()
			local success, err = pcall(function()
				battle.OnBattleEnd({
					BattleId = battleId,
					Winner = winner,
					BattleType = battle.BattleType,
				})
			end)
			if not success then
				WarnLog("OnBattleEnd回调执行失败:", err)
			end
		end)
	end

	-- 通知客户端战斗状态更新
	if battleStateUpdateEvent then
		local player = Players:GetPlayerByUserId(battle.PlayerId)
		if player then
			battleStateUpdateEvent:FireClient(player, battleId, BattleConfig.BattleState.FINISHED, winner)
			DebugLog(string.format("已通知客户端战斗结束: BattleId=%d, 胜利方=%s", battleId, winner or "平局"))
		end
	end

	-- 延迟清理战场
	task.delay(BattleConfig.CLEANUP_DELAY, function()
		BattleManager.CleanupBattle(battleId)
	end)

	return true
end

--[[
清理战场(V2.0扩展：战役模式下不销毁攻击方单位)
@param battleId number - 战斗ID
]]
function BattleManager.CleanupBattle(battleId)
	local battle = battles[battleId]

	if not battle then
		return
	end

	DebugLog(string.format("清理战场: BattleId=%d, Type=%s", battleId, battle.BattleType or "Test"))

	-- V2.0: 战役模式下不销毁攻击方单位(需要返回基地)
	local isCampaign = battle.BattleType == "Campaign"

	-- 移除兵种模型(战役模式下跳过攻击方)
	if not isCampaign then
		for _, unit in ipairs(battle.AttackUnits) do
			if unit and unit.Parent then
				unit:Destroy()
			end
		end
	else
		DebugLog("战役模式：保留攻击方单位，跳过销毁")
	end

	-- 防守方始终销毁
	for _, unit in ipairs(battle.DefenseUnits) do
		if unit and unit.Parent then
			unit:Destroy()
		end
	end

	-- V1.5.1 Bug修复: 清理HitboxService的命中记录,防止污染下一个战斗
	for _, unit in ipairs(battle.AttackUnits) do
		if unit then
			HitboxService.ClearAttackerHitRecords(unit)
		end
	end

	for _, unit in ipairs(battle.DefenseUnits) do
		if unit then
			HitboxService.ClearAttackerHitRecords(unit)
		end
	end

	-- 清理战斗状态
	CombatSystem.ClearBattleUnits(battleId)

	-- V1.5.1: 清理UnitManager中的单位索引
	UnitManager.ClearBattle(battleId)

	-- 移除战斗实例
	battles[battleId] = nil

	DebugLog(string.format("战场清理完成: BattleId=%d", battleId))
end

--[[
获取战斗实例
@param battleId number - 战斗ID
@return table|nil - 战斗实例
]]
function BattleManager.GetBattle(battleId)
    return battles[battleId]
end

--[[
获取玩家当前的战斗实例
@param playerId number - 玩家UserId
@return table|nil - 战斗实例
]]
function BattleManager.GetPlayerBattle(playerId)
    for _, battle in pairs(battles) do
        if battle.PlayerId == playerId and battle.State ~= BattleConfig.BattleState.FINISHED then
            return battle
        end
    end

    return nil
end

--[[
添加攻击方兵种
@param battleId number - 战斗ID
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function BattleManager.AddAttackUnit(battleId, unitModel)
    local battle = battles[battleId]

    if not battle then
        return false
    end

    table.insert(battle.AttackUnits, unitModel)

    return true
end

--[[
添加防守方兵种
@param battleId number - 战斗ID
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function BattleManager.AddDefenseUnit(battleId, unitModel)
    local battle = battles[battleId]

    if not battle then
        return false
    end

    table.insert(battle.DefenseUnits, unitModel)

    return true
end

--[[
获取活跃战斗数量
@return number - 活跃战斗数量
]]
function BattleManager.GetActiveBattleCount()
    local count = 0

    for _, battle in pairs(battles) do
        if battle.State == BattleConfig.BattleState.FIGHTING then
            count = count + 1
        end
    end

    return count
end

--[[
获取所有战斗
@return table - 所有战斗实例
]]
function BattleManager.GetAllBattles()
    return battles
end

return BattleManager
