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
local CombatSystem = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CombatSystem") :: ModuleScript)
local UnitAI = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("UnitAI") :: ModuleScript)
local UnitManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("UnitManager") :: ModuleScript)  -- V1.5.1新增
local PhysicsManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PhysicsManager") :: ModuleScript)  -- V2.2新增
local HitboxService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("HitboxService") :: ModuleScript)  -- V1.5.1新增

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
    IsSettling = boolean,        -- V2.4新增：是否在结算中（防止重复EndBattle）
    SettlementData = table,      -- V2.4新增：结算数据（用于客户端显示）
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

        -- V2.4新增：连接胜利确认事件
        -- V2.5扩展：支持战役结算确认（battleId=0表示战役结算）
        local victoryConfirmEvent = battleEventsFolder:FindFirstChild("VictoryConfirm")
        if victoryConfirmEvent then
            victoryConfirmEvent.OnServerEvent:Connect(function(player, battleId)
                local success, err = pcall(function()
                    -- 验证玩家合法性
                    if not player then
                        return
                    end

                    -- V2.5新增：处理战役结算确认（battleId=0）
                    if battleId == 0 then
                        -- 战役结算确认
                        local CampaignManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CampaignManager") :: ModuleScript)
                        local campaignData = CampaignManager.ActiveCampaigns[player.UserId]

                        if not campaignData then
                            DebugLog(string.format("忽略VictoryConfirm: 玩家 %s 无活跃战役(battleId=0)", player.Name))
                            return
                        end

                        if not campaignData.IsWaitingForConfirm then
                            DebugLog(string.format("忽略VictoryConfirm: 玩家 %s 的战役未在等待确认状态", player.Name))
                            return
                        end

                        DebugLog(string.format("收到玩家 %s 的战役结算确认", player.Name))

                        -- 完成战役结算
                        CampaignManager.CompleteCampaignEnd(campaignData)
                        return
                    end

                    -- 战役结算(battleId==0) 已在CampaignManager处理，普通战斗需>0
                    if not battleId or battleId == 0 then
                        DebugLog(string.format("忽略VictoryConfirm: battleId无效(%s)", tostring(battleId)))
                        return
                    end

                    -- 确保battleId是数字类型
                    local battleIdNum = tonumber(battleId)
                    if not battleIdNum then
                        WarnLog("VictoryConfirm失败: battleId类型无效")
                        return
                    end

                    local battle = battles[battleIdNum]
                    if not battle then
                        DebugLog(string.format("忽略VictoryConfirm: 战斗 %d 不存在或已结算", battleIdNum))
                        return
                    end

                    if battle.PlayerId ~= player.UserId then
                        DebugLog(string.format("忽略VictoryConfirm: 玩家 %s 不是战斗 %d 的发起者", player.Name, battleIdNum))
                        return
                    end

                    if not battle.IsSettling then
                        DebugLog(string.format("忽略VictoryConfirm: 战斗 %d 未在结算中", battleIdNum))
                        return
                    end

                    DebugLog(string.format("收到玩家 %s 的胜利确认: BattleId=%d", player.Name, battleIdNum))

                    -- 完成战斗结算
                    BattleManager.CompleteBattle(battleIdNum, battle.Winner)
                end)

                if not success then
                    WarnLog("VictoryConfirm处理失败:", err)
                end
            end)
        else
            WarnLog("未找到VictoryConfirm事件，结算界面功能将不可用")
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
		-- V2.4新增字段
		IsSettling = false,              -- 是否在结算中
		SettlementData = nil,            -- 结算数据
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
        -- V2.5新增：标记阵营
        unit:SetAttribute("Team", BattleConfig.Team.ATTACK)

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
        -- V2.5新增：标记阵营
        unit:SetAttribute("Team", BattleConfig.Team.DEFENSE)

        -- V2.5新增：为敌方设置红色Highlight描边
        -- 注意：只修改描边（OutlineColor/OutlineTransparency）和深度模式，不修改填充
        local highlight = unit:FindFirstChild("Highlight")
        if not highlight then
            highlight = Instance.new("Highlight")
            highlight.Name = "Highlight"
            highlight.Parent = unit
        end
        -- 只设置描边属性和深度模式，保持填充属性不变
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.Occluded  -- 避免总在最上层
        -- 不设置 FillTransparency / FillColor，保持默认
        DebugLog(string.format("✅ 敌方高光设置完成: %s (Outline=红色, DepthMode=Occluded)", unit.Name))

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

    -- V2.3新增: 通知客户端挂载血条
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if eventsFolder then
        local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
        if battleEventsFolder then
            local attachHealthBarsEvent = battleEventsFolder:FindFirstChild("AttachHealthBars")
            if attachHealthBarsEvent then
                -- 收集所有战斗单位
                local allBattleUnits = {}
                for _, unit in ipairs(finalAttackUnits) do
                    table.insert(allBattleUnits, unit)
                end
                for _, unit in ipairs(finalDefenseUnits) do
                    table.insert(allBattleUnits, unit)
                end

                -- 通知所有客户端挂载血条
                attachHealthBarsEvent:FireAllClients(allBattleUnits)
            end

            -- V2.5新增修复：Team属性设置完成后，通知客户端重新着色血条
            -- 这解决了"血条在Team属性设置前挂载"的时序问题
            local reapplyTeamColorsEvent = battleEventsFolder:FindFirstChild("ReapplyTeamColors")
            if reapplyTeamColorsEvent then
                local allBattleUnits = {}
                for _, unit in ipairs(finalAttackUnits) do
                    table.insert(allBattleUnits, unit)
                end
                for _, unit in ipairs(finalDefenseUnits) do
                    table.insert(allBattleUnits, unit)
                end
                reapplyTeamColorsEvent:FireAllClients(allBattleUnits)
                DebugLog("✅ 通知客户端重新着色血条: " .. #allBattleUnits .. " 个单位")
            else
                DebugLog("⚠️ ReapplyTeamColors事件不存在，血条着色可能延迟")
            end
        end
    end

    return true
end

--[[
结束战斗(V2.4扩展：结算界面支持)
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

	-- V2.4新增：防止重复调用
	if battle.IsSettling then
		DebugLog("EndBattle跳过: 战斗已在结算中")
		return true
	end

	-- 更新战斗状态
	battle.State = BattleConfig.BattleState.FINISHED
	battle.Winner = winner
	battle.IsSettling = true  -- V2.4新增：标记为结算中

	-- 停止所有AI
	UnitAI.ClearBattleAIs(battleId)

	local battleType = tostring(battle.BattleType or "Test")
	local winnerStr = tostring(winner or "平局")

	if winner then
		DebugLog(string.format("战斗结束: BattleId=%d, Type=%s, 胜利方=%s",
			battleId, battleType, winnerStr))
	else
		DebugLog(string.format("战斗结束: BattleId=%d, Type=%s, 平局",
			battleId, battleType))
	end

	-- V2.4新增：准备结算数据
	local currentStage = 1  -- 默认关卡1
	local extraRewards = nil  -- 暂时无额外奖励

	-- 如果是战役战斗，尝试获取当前关卡号
	if battle.BattleType == "Campaign" then
		local playerId = battle.PlayerId
		local CampaignManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CampaignManager") :: ModuleScript)
		local campaignData = CampaignManager.ActiveCampaigns[playerId]
		if campaignData then
			currentStage = campaignData.CurrentStage or 1
		end
	end

	battle.SettlementData = {
		BattleId = battleId,
		Result = winner or "Draw",  -- "Attack", "Defense", "Draw"
		StageNum = currentStage,
		ExtraRewards = extraRewards
	}

	-- V2.4/V2.5修改：发送结算弹窗到客户端
	-- 战役模式：不弹窗，直接完成战斗，让CampaignManager决定是否继续行军
	if battle.BattleType == "Campaign" then
		DebugLog(string.format("战役战斗结束，跳过单关弹窗: BattleId=%d, Winner=%s", battleId, winner or "Draw"))
		task.defer(function()
			BattleManager.CompleteBattle(battleId, winner)
		end)
	else
		local eventsFolder = ReplicatedStorage:FindChild("Events") or ReplicatedStorage:FindFirstChild("Events")
		local battleEventsFolder = eventsFolder and eventsFolder:FindFirstChild("BattleEvents")
		local victoryPopupEvent = battleEventsFolder and battleEventsFolder:FindFirstChild("VictoryPopup")

		if victoryPopupEvent then
			local player = Players:GetPlayerByUserId(battle.PlayerId)
			if player then
				victoryPopupEvent:FireClient(player, battleId, winner or "Draw", currentStage, extraRewards)
				DebugLog(string.format("已发送结算弹窗到客户端: BattleId=%d, Result=%s, Stage=%d",
					battleId, winner or "Draw", currentStage))
			end
		else
			WarnLog("VictoryPopup事件不存在，将启动自动结算")
			task.delay(0.5, function()
				BattleManager.CompleteBattle(battleId, winner)
			end)
		end

		-- V2.4新增：设置超时自动结算（防止客户端卡死）
		task.delay(5, function()
			local currentBattle = battles[battleId]
			if currentBattle and currentBattle.IsSettling then
				WarnLog(string.format("战斗 %d 结算超时，强制完成", battleId))
				BattleManager.CompleteBattle(battleId, winner)
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

	return true
end

--[[
完成战斗结算(V2.4新增：客户端确认后调用)
@param battleId number - 战斗ID
@param winner string - 胜利方
]]
function BattleManager.CompleteBattle(battleId, winner)
	local battle = battles[battleId]

	if not battle then
		WarnLog("CompleteBattle失败: 战斗不存在")
		return false
	end

	if not battle.IsSettling then
		WarnLog("CompleteBattle失败: 战斗未在结算中")
		return false
	end

	DebugLog(string.format("完成战斗结算: BattleId=%d", battleId))

	-- 取消结算状态
	battle.IsSettling = false

	-- V2.0: 触发OnBattleEnd回调(战役系统)
	-- V2.6修复：同步调用OnBattleEnd，避免与ProcessPendingBattleResult竞态
	if battle.OnBattleEnd then
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
	end

	-- V2.4新增：如果是战役战斗，通知CampaignManager处理确认后的逻辑
	if battle.BattleType == "Campaign" then
		local CampaignManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CampaignManager") :: ModuleScript)
		local playerId = battle.PlayerId
		local campaignData = CampaignManager.ActiveCampaigns[playerId]
		if campaignData then
			DebugLog(string.format("通知CampaignManager处理确认后逻辑: BattleId=%d", battleId))
			CampaignManager.ProcessPendingBattleResult(campaignData)
		end
	end

	-- V2.3新增: 通知客户端移除血条
	-- V2.3修复: 仅非战役才移除血条（战役内关卡切换保持血条）
	if battle.BattleType ~= "Campaign" then
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
			if battleEventsFolder then
				local detachHealthBarsEvent = battleEventsFolder:FindFirstChild("DetachHealthBars")
				if detachHealthBarsEvent then
					-- 收集所有战斗单位
					local allBattleUnits = {}
					for _, unit in ipairs(battle.AttackUnits) do
						table.insert(allBattleUnits, unit)
					end
					for _, unit in ipairs(battle.DefenseUnits) do
						table.insert(allBattleUnits, unit)
					end

					-- 通知所有客户端移除血条
					detachHealthBarsEvent:FireAllClients(allBattleUnits)
					DebugLog(string.format("⚔️ 非战役战斗结束，移除血条: BattleId=%d", battleId))
				end
			end
		end
	else
		-- 战役模式下保持血条，由CampaignManager统一管理
		DebugLog(string.format("🏰 战役战斗结束，保持血条显示: BattleId=%d", battleId))
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
