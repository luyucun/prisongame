--[[
=====================================================
脚本名称: CampaignManager
脚本类型: ModuleScript (服务端核心)
脚本位置: ServerScriptService/Systems/CampaignManager.lua
版本: V2.0
=====================================================

功能描述:
- 管理玩家的战役流程
- 协调兵种行军、战斗、推进关卡
- 处理胜利/失败/撤退逻辑
- 兵种重生和血量继承

状态机:
IDLE → PREPARING → MARCHING → FIGHTING → STAGE_CLEAR/DEFEAT → CLEANUP → IDLE

]]

local CampaignManager = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- 引用模块
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local StageConfig = require(ReplicatedStorage.Config.StageConfig)
local PlayerManager = require(ServerScriptService.Core.PlayerManager)
local GridPositionSystem = require(ServerScriptService.Systems.GridPositionSystem)
local StageService = require(ServerScriptService.Systems.StageService)
local PathService = require(ServerScriptService.Systems.PathService)
local BattleManager = require(ServerScriptService.Systems.BattleManager)
local CurrencySystem = require(ServerScriptService.Systems.CurrencySystem)
local UnitAI = require(ServerScriptService.Systems.UnitAI)  -- V2.0新增：用于控制行军动画
local CampaignUnitHelper = require(ServerScriptService.Systems.CampaignUnitHelper)  -- V2.0新增：单位激活/复位

-- 远程事件
local CampaignEvents = nil

-- 战役状态枚举
local CampaignState = {
	IDLE = "Idle",
	PREPARING = "Preparing",
	MARCHING = "Marching",
	PREPARE_BATTLE = "PrepareBattle",  -- V2.0新增：准备战斗（激活单位）
	FIGHTING = "Fighting",
	STAGE_CLEAR = "StageClear",
	VICTORY = "Victory",
	DEFEAT = "Defeat",
	CLEANUP = "Cleanup"
}

-- 活跃战役数据: [playerId] = CampaignData
CampaignManager.ActiveCampaigns = {}

-- ==================== 私有函数 ====================

--[[
设置兵种的锚定状态（内部使用）
@param unitModel Model - 兵种模型
@param anchored boolean - 是否锚定
]]
local function SetUnitAnchored(unitModel, anchored)
	if not unitModel then
		return
	end

	-- 遍历所有 BasePart 设置锚定和碰撞
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
			-- V2.0修复：战役中也需要让HumanoidRootPart保持碰撞，否则无法正常移动
			if descendant.Name == "HumanoidRootPart" then
				descendant.CanCollide = true  -- 根部件始终有碰撞
			else
				descendant.CanCollide = false  -- 其他部件关闭碰撞，避免卡住
			end
		end
	end

	-- 设置 Humanoid 状态
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		if not anchored then
			-- 解除锚定：准备移动
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		else
			-- 锚定：站立不动
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	print("[CampaignManager] SetUnitAnchored:", unitModel.Name, "Anchored=", anchored)
end

--[[
初始化远程事件
]]
local function InitializeEvents()
	if not CampaignEvents then
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			CampaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
		end

		if not CampaignEvents then
			warn("[CampaignManager] CampaignEvents未找到!")
		end
	end
	return CampaignEvents ~= nil
end

--[[
获取玩家基地的IdleFloor
@param homeId number - 基地ID
@return Part|nil - IdleFloor
]]
local function GetHomeIdleFloor(homeId)
	local homeFolder = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
	if not homeFolder then
		return nil
	end

	-- V2.0修复：使用递归搜索，支持IdleFloor在子文件夹中
	return homeFolder:FindFirstChild("IdleFloor", true)
end

--[[
锁定/解锁基地操作
@param player Player - 玩家
@param locked boolean - 是否锁定
]]
local function LockHomeOperations(player, locked)
	-- 通过RemoteEvent通知客户端锁定/解锁基地操作
	if InitializeEvents() then
		local lockEvent = CampaignEvents:FindFirstChild("LockHomeOperations")
		if lockEvent then
			lockEvent:FireClient(player, locked)
		end
	end
end

--[[
播放重生特效
@param unitInstance Model - 兵种实例
@param gridSize number - 占地大小(1/2/3)
]]
local function PlayRespawnEffect(unitInstance, gridSize)
	local effectName = "Merge0" .. gridSize  -- Merge01/Merge02/Merge03
	local effectFolder = ReplicatedStorage:FindFirstChild("Effect")

	if not effectFolder then
		return
	end

	local effect = effectFolder:FindFirstChild(effectName)
	if effect and unitInstance.PrimaryPart then
		local clone = effect:Clone()
		clone.CFrame = unitInstance.PrimaryPart.CFrame
		clone.Parent = Workspace

		task.delay(GameConfig.Campaign.RespawnEffectDuration, function()
			if clone and clone.Parent then
				clone:Destroy()
			end
		end)
	end
end

-- ==================== 公共方法 ====================

--[[
开始战役
@param player Player - 玩家
@return boolean - 是否成功开始
]]
function CampaignManager.StartCampaign(player)
	local playerId = player.UserId

	-- 检查是否已在战役中
	if CampaignManager.ActiveCampaigns[playerId] then
		warn("[CampaignManager] 玩家已在战役中:", player.Name)
		return false
	end

	-- 获取HomeId
	local homeId = PlayerManager.GetPlayerHomeId(player)
	if not homeId then
		warn("[CampaignManager] 玩家未分配基地:", player.Name)
		return false
	end

	-- 收集兵种（从PlacementSystem获取）
	local PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)
	local placedUnits = PlacementSystem.GetPlacedUnitModels(player)

	if not placedUnits or #placedUnits == 0 then
		warn("[CampaignManager] 没有可用兵种:", player.Name)
		return false
	end

	print("[CampaignManager] 开始战役:", player.Name, "兵种数量:", #placedUnits)

	-- 创建CampaignData
	local campaignData = {
		PlayerId = playerId,
		Player = player,
		HomeId = homeId,
		CurrentStage = 1,
		TotalStages = GameConfig.Campaign.MaxStages,
		State = CampaignState.PREPARING,
		Units = {},
		StageInstances = {},
		CurrentBattleId = nil
	}

	-- 保存兵种数据
	local homeIdleFloor = GetHomeIdleFloor(homeId)
	if not homeIdleFloor then
		warn("[CampaignManager] 找不到基地IdleFloor:", homeId)
		return false
	end

	for _, unitModel in ipairs(placedUnits) do
		-- 获取GridPos（兼容历史数据）
		local gridPos = GridPositionSystem.LoadUnitGridPosition(unitModel, homeIdleFloor)

		-- 获取兵种配置
		local UnitConfig = require(ReplicatedStorage.Config.UnitConfig)
		local unitId = unitModel.Name
		local unitConfig = UnitConfig.Units[unitId]

		if unitConfig and unitModel:FindFirstChild("Humanoid") then
			local level = unitModel:GetAttribute("Level") or 1
			local gridSize = unitConfig.GridSize or 1

			-- V2.0修复：设置UnitId属性（确保CombatSystem能正确识别）
			unitModel:SetAttribute("UnitId", unitId)

			-- V2.0修复：解除所有部件的锚定，允许兵种移动
			SetUnitAnchored(unitModel, false)

			campaignData.Units[unitModel] = {
				Instance = unitModel,
				UnitId = unitId,
				Level = level,
				GridPos = gridPos,
				GridSize = gridSize,
				CurrentHP = unitModel.Humanoid.Health,
				MaxHP = unitModel.Humanoid.MaxHealth,
				IsDead = false,
				WasAnchored = true,  -- 记录需要重新锚定

				-- V2.0新增字段
				IsActivated = false,         -- 是否已激活
				LastKnownPosition = nil,     -- 最后已知位置（用于断线恢复）
				LastBattleId = nil,          -- 最后参与的战斗ID
			}

			print("[CampaignManager] 注册兵种:", unitId, "GridPos:", gridPos.X, gridPos.Y)
		end
	end

	-- 锁定基地操作
	LockHomeOperations(player, true)

	-- 生成Stage002
	StageService.GetOrCreateStage(playerId, 2)

	-- 注册战役
	CampaignManager.ActiveCampaigns[playerId] = campaignData

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(player, CampaignState.PREPARING, 1)
		end
	end

	-- 开始行军
	task.spawn(function()
		CampaignManager.MarchToStage(campaignData, 1)
	end)

	return true
end

--[[
行军到关卡
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
]]
function CampaignManager.MarchToStage(campaignData, stageNum)
	campaignData.State = CampaignState.MARCHING

	print("[CampaignManager] 行军到关卡:", stageNum)

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.MARCHING, stageNum)
		end
	end

	-- 获取目标关卡
	local stageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, stageNum)
	if not stageFolder then
		warn("[CampaignManager] 关卡未找到:", stageNum)
		return CampaignManager.OnCampaignEnd(campaignData, false)
	end

	-- V2.0修复：使用递归搜索，支持IdleFloor在子文件夹中（如Stage001/StageNodes/IdleFloor）
	local targetIdleFloor = stageFolder:FindFirstChild("IdleFloor", true)
	if not targetIdleFloor then
		warn("[CampaignManager] 关卡IdleFloor未找到（已递归搜索）:", stageNum, "关卡路径:", stageFolder:GetFullName())
		return CampaignManager.OnCampaignEnd(campaignData, false)
	end

	-- V2.0修复：提前生成敌人（在行军开始前），让玩家立即看到目标
	-- 但敌人处于锚定+无碰撞状态，不会阻挡行军
	print("[CampaignManager] 提前生成关卡敌人（锚定状态）:", stageNum)
	local enemies = StageService.LoadEnemyData(stageFolder, stageNum)
	print("[CampaignManager] 敌人生成完成，数量:", #enemies)

	-- 批量计算目标位置
	local moveTargets = {}
	local moveCount = 0
	for unitInstance, unitData in pairs(campaignData.Units) do
		if not unitData.IsDead and unitInstance and unitInstance.Parent then
			local targetCFrame = GridPositionSystem.MapToTargetFloor(
				unitData.GridPos,
				targetIdleFloor
			)
			moveTargets[unitInstance] = targetCFrame
			moveCount = moveCount + 1

			-- V2.0修复：开始行军前，确保停止Show动画
			local humanoid = unitInstance:FindFirstChild("Humanoid")
			if humanoid then
				local animator = humanoid:FindFirstChild("Animator")
				if animator then
					-- 停止所有正在播放的动画（包括Show动画）
					local tracks = animator:GetPlayingAnimationTracks()
					for _, track in ipairs(tracks) do
						pcall(function()
							track:Stop(0.1)
						end)
					end
					print("[CampaignManager] 停止了", #tracks, "个动画，准备播放移动动画:", unitData.UnitId)
				end
			end

			-- V2.0修复：开始行军时播放移动动画
			UnitAI.PlayMoveAnimation(unitInstance)

			-- V2.0调试：输出兵种当前位置和目标位置
			if unitInstance:FindFirstChild("HumanoidRootPart") then
				local currentPos = unitInstance.HumanoidRootPart.Position
				print(string.format("[CampaignManager] 兵种 %s: 当前位置(%.1f, %.1f, %.1f) → 目标位置(%.1f, %.1f, %.1f)",
					unitData.UnitId,
					currentPos.X, currentPos.Y, currentPos.Z,
					targetCFrame.Position.X, targetCFrame.Position.Y, targetCFrame.Position.Z))
			end
		end
	end

	print("[CampaignManager] 开始批量寻路，目标数量:", moveCount)

	-- 调用PathService批量寻路（使用新的回调API）
	local moveId = PathService.MoveUnitsToPositions(moveTargets, {
		onUnitArrived = function(unitInstance, status)
			-- 单位到达时的回调（可选，这里暂时不处理）
			print("[CampaignManager] 单位到达:", unitInstance.Name, "状态:", status)
		end,

		onAllSettled = function(arrivedList, timedOutList, failedList)
			-- 所有单位完成移动后的回调
			print("[CampaignManager] 所有兵种到达关卡:", stageNum)
			print(string.format("  - 正常到达: %d", #arrivedList))
			print(string.format("  - 超时传送: %d", #timedOutList))
			print(string.format("  - 失败: %d", #failedList))

			-- V2.0修复：到达后停止移动动画，切换到Idle
			for _, unitInstance in ipairs(arrivedList) do
				if unitInstance and unitInstance.Parent then
					UnitAI.StopMoveAnimation(unitInstance)
				end
			end

			for _, unitInstance in ipairs(timedOutList) do
				if unitInstance and unitInstance.Parent then
					UnitAI.StopMoveAnimation(unitInstance)
				end
			end

			-- V2.0重构：进入准备战斗阶段
			task.wait(0.1)  -- 给客户端缓冲
			CampaignManager.BeginBattlePrep(campaignData, stageNum, arrivedList, timedOutList, failedList)
		end
	})

	-- 存储moveId以便后续可以取消
	if moveId then
		campaignData.CurrentMoveId = moveId
	end
end

--[[
准备战斗（V2.0新增）
接收PathService回调后的核心准备流程
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
@param arrivedList table - 正常到达的单位列表
@param timedOutList table - 超时传送的单位列表
@param failedList table - 失败的单位列表
]]
function CampaignManager.BeginBattlePrep(campaignData, stageNum, arrivedList, timedOutList, failedList)
	campaignData.State = CampaignState.PREPARE_BATTLE

	print("[CampaignManager] 开始准备战斗，关卡:", stageNum)

	-- 通知客户端进入准备阶段
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.PREPARE_BATTLE, stageNum)
		end
	end

	-- 标记失败的单位为已死亡
	for _, unitInstance in ipairs(failedList) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			unitData.IsDead = true
			warn("[CampaignManager] 单位失败，标记为死亡:", unitData.UnitId)
		end
	end

	-- 合并所有到达的单位（包括正常和超时）
	local allArrivedUnits = {}
	for _, unit in ipairs(arrivedList) do
		table.insert(allArrivedUnits, unit)
	end
	for _, unit in ipairs(timedOutList) do
		table.insert(allArrivedUnits, unit)
	end

	print(string.format("[CampaignManager] 到达统计 - 正常:%d, 超时:%d, 失败:%d",
		#arrivedList, #timedOutList, #failedList))

	-- 记录到达的单位，更新 campaignData
	for _, unitInstance in ipairs(allArrivedUnits) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			local rootPart = unitInstance:FindFirstChild("HumanoidRootPart")
			if rootPart then
				unitData.LastKnownPosition = rootPart.Position
			end
		end
	end

	-- 准备友军：激活单位并准备进入战斗
	print("[CampaignManager] 准备友军...")
	local preparedAllies = {}

	for _, unitInstance in ipairs(allArrivedUnits) do
		local unitData = campaignData.Units[unitInstance]
		if unitData and not unitData.IsDead then
			-- 1. 激活单位（解除锚定等）
			local activated = CampaignUnitHelper.ActivateUnit(unitInstance)
			if activated then
				unitData.IsActivated = true
			end

			-- 2. 准备进入战斗（清理PathService残留、重置AI状态）
			local prepared = CampaignUnitHelper.PrepareForBattle(unitInstance)

			if activated and prepared then
				table.insert(preparedAllies, unitInstance)
				print(string.format("  ✅ 友军准备完成: %s", unitData.UnitId))
			else
				warn(string.format("  ❌ 友军准备失败: %s", unitData.UnitId))
			end
		end
	end

	print(string.format("[CampaignManager] 友军准备完成: %d / %d", #preparedAllies, #allArrivedUnits))

	-- 获取并激活敌军
	print("[CampaignManager] 准备敌军...")
	local stageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, stageNum)
	if not stageFolder then
		warn("[CampaignManager] 关卡未找到，战斗准备失败")
		return CampaignManager.OnDefeat(campaignData)
	end

	-- 敌军激活
	local idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
	local preparedEnemies = {}

	if idleFloorEnemy then
		for _, child in ipairs(idleFloorEnemy:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChild("Humanoid") then
				local activated = CampaignUnitHelper.ActivateUnit(child)
				if activated then
					table.insert(preparedEnemies, child)
				end
			end
		end
		print(string.format("[CampaignManager] 敌军激活完成: %d", #preparedEnemies))
	else
		warn("[CampaignManager] IdleFloorEnemy未找到")
	end

	-- 检查是否可以开战
	if #preparedAllies == 0 or #preparedEnemies == 0 then
		warn(string.format("[CampaignManager] 无法开战：友军%d，敌军%d", #preparedAllies, #preparedEnemies))
		return CampaignManager.OnDefeat(campaignData)
	end

	print("[CampaignManager] ✅ 战斗准备完成，开始战斗")

	-- 进入战斗阶段
	task.wait(0.2)  -- 给激活操作一点缓冲时间
	CampaignManager.StartStageBattle(campaignData, stageNum, preparedAllies, preparedEnemies)
end

--[[
开始关卡战斗（V2.0重构）
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
@param preparedAllies table - 已准备好的友军列表
@param preparedEnemies table - 已准备好的敌军列表
]]
function CampaignManager.StartStageBattle(campaignData, stageNum, preparedAllies, preparedEnemies)
	campaignData.State = CampaignState.FIGHTING

	print("[CampaignManager] 开始关卡战斗:", stageNum)

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.FIGHTING, stageNum)
		end
	end

	print(string.format("[CampaignManager] 友军数量: %d, 敌军数量: %d", #preparedAllies, #preparedEnemies))

	-- V2.0重构：直接使用已准备好的列表，无需再次激活
	-- 创建战斗实例
	local battleId = BattleManager.CreateBattle({
		PlayerId = campaignData.PlayerId,
		BattleType = "Campaign",
		AttackTeam = preparedAllies,
		DefenseTeam = preparedEnemies,
		OnBattleEnd = function(result)
			CampaignManager.OnBattleEnd(campaignData, stageNum, result)
		end
	})

	campaignData.CurrentBattleId = battleId

	-- 更新 LastBattleId
	for _, unitInstance in ipairs(preparedAllies) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			unitData.LastBattleId = battleId
		end
	end

	-- 开始战斗
	BattleManager.StartBattle(battleId)
end

--[[
战斗结束回调
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
@param result table - 战斗结果
]]
function CampaignManager.OnBattleEnd(campaignData, stageNum, result)
	print("[CampaignManager] 关卡", stageNum, "战斗结束，胜者:", result.Winner)

	-- 保存兵种HP
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent and unitInstance:FindFirstChild("Humanoid") then
			unitData.CurrentHP = unitInstance.Humanoid.Health
			if unitData.CurrentHP <= 0 then
				unitData.IsDead = true
			end
		else
			unitData.IsDead = true
		end
	end

	-- 判定结果
	if result.Winner == "Attack" then
		-- 我方胜利
		CampaignManager.OnStageClear(campaignData, stageNum)
	else
		-- 我方失败
		CampaignManager.OnDefeat(campaignData)
	end
end

--[[
关卡完成
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
]]
function CampaignManager.OnStageClear(campaignData, stageNum)
	campaignData.State = CampaignState.STAGE_CLEAR

	print("[CampaignManager] 关卡", stageNum, "完成!")

	-- 通知客户端
	if InitializeEvents() then
		local progressEvent = CampaignEvents:FindFirstChild("StageProgress")
		if progressEvent then
			progressEvent:FireClient(campaignData.Player, stageNum, "Clear")
		end
	end

	-- 检查是否最后一关
	if stageNum >= campaignData.TotalStages then
		return CampaignManager.OnVictory(campaignData)
	end

	-- 提前生成下下关
	local nextStage = stageNum + 1
	if nextStage + 1 <= campaignData.TotalStages then
		task.spawn(function()
			StageService.GetOrCreateStage(campaignData.PlayerId, nextStage + 1)
		end)
	end

	-- 前往下一关
	campaignData.CurrentStage = nextStage
	task.wait(2)  -- 等待2秒
	CampaignManager.MarchToStage(campaignData, nextStage)
end

--[[
战役胜利
@param campaignData table - 战役数据
]]
function CampaignManager.OnVictory(campaignData)
	campaignData.State = CampaignState.VICTORY

	print("[CampaignManager] 战役胜利!", campaignData.Player.Name)

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.VICTORY, campaignData.TotalStages)
		end
	end

	-- 计算奖励
	local totalReward = 0
	for i = 1, campaignData.TotalStages do
		local reward = StageConfig.Style01.Rewards[i]
		if reward then
			totalReward = totalReward + (reward.Coins or 0)
		end
	end

	-- 发放奖励 (V2.0修复：使用AddCoins而不是AddCurrency)
	if totalReward > 0 then
		CurrencySystem.AddCoins(campaignData.Player, totalReward, "战役胜利奖励")
		print("[CampaignManager] 发放奖励:", totalReward, "金币")
	else
		print("[CampaignManager] 无奖励发放")
	end

	-- 结束战役
	task.wait(3)
	CampaignManager.OnCampaignEnd(campaignData, true)
end

--[[
战役失败
@param campaignData table - 战役数据
]]
function CampaignManager.OnDefeat(campaignData)
	campaignData.State = CampaignState.DEFEAT

	print("[CampaignManager] 战役失败:", campaignData.Player.Name)

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.DEFEAT, campaignData.CurrentStage)
		end
	end

	-- 结束战役
	task.wait(3)
	CampaignManager.OnCampaignEnd(campaignData, false)
end

--[[
战役结束清理
@param campaignData table - 战役数据
@param isVictory boolean - 是否胜利
]]
function CampaignManager.OnCampaignEnd(campaignData, isVictory)
	campaignData.State = CampaignState.CLEANUP

	print("[CampaignManager] 战役结束，开始清理...")

	-- 重生兵种
	CampaignManager.RespawnUnits(campaignData)

	-- 清理关卡
	StageService.CleanupStages(campaignData.PlayerId)

	-- 解锁基地操作
	LockHomeOperations(campaignData.Player, false)

	-- 清除战役数据
	CampaignManager.ActiveCampaigns[campaignData.PlayerId] = nil

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.IDLE, 0)
		end
	end

	campaignData.State = CampaignState.IDLE

	print("[CampaignManager] 战役清理完成")
end

--[[
重生兵种到基地
@param campaignData table - 战役数据
]]
function CampaignManager.RespawnUnits(campaignData)
	local homeIdleFloor = GetHomeIdleFloor(campaignData.HomeId)
	if not homeIdleFloor then
		warn("[CampaignManager] 找不到基地IdleFloor")
		return
	end

	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent then
			-- 计算原位置
			local targetCFrame = GridPositionSystem.GridToWorld(
				homeIdleFloor,
				unitData.GridPos
			)

			-- 传送回去
			if unitInstance.PrimaryPart then
				unitInstance:SetPrimaryPartCFrame(targetCFrame)
			elseif unitInstance:FindFirstChild("HumanoidRootPart") then
				unitInstance.HumanoidRootPart.CFrame = targetCFrame
			end

			-- V2.0修复：重新锚定所有部件，恢复基地静止状态
			if unitData.WasAnchored then
				SetUnitAnchored(unitInstance, true)
			end

			-- 恢复满血
			if unitInstance:FindFirstChild("Humanoid") then
				unitInstance.Humanoid.Health = unitData.MaxHP
			end

			-- 复活标记
			unitData.IsDead = false
			unitData.CurrentHP = unitData.MaxHP

			-- 播放特效
			PlayRespawnEffect(unitInstance, unitData.GridSize)

			print("[CampaignManager] 重生兵种:", unitData.UnitId, "位置:", unitData.GridPos.X, unitData.GridPos.Y)
		end
	end

	print("[CampaignManager] 兵种重生完成")
end

--[[
玩家请求撤退
@param player Player - 玩家
]]
function CampaignManager.RequestRetreat(player)
	local playerId = player.UserId
	local campaignData = CampaignManager.ActiveCampaigns[playerId]

	if not campaignData then
		return
	end

	print("[CampaignManager] 玩家撤退:", player.Name)
	CampaignManager.OnDefeat(campaignData)
end

--[[
初始化CampaignManager
]]
function CampaignManager.Initialize()
	print("[CampaignManager] 初始化...")

	-- 初始化远程事件
	if not InitializeEvents() then
		warn("[CampaignManager] CampaignEvents未找到，战役系统将不可用!")
		return false
	end

	-- 连接事件
	local requestStart = CampaignEvents:FindFirstChild("RequestStartCampaign")
	if requestStart then
		requestStart.OnServerEvent:Connect(function(player)
			local success, err = pcall(function()
				CampaignManager.StartCampaign(player)
			end)

			if not success then
				warn("[CampaignManager] 开始战役失败:", err)
			end
		end)
	end

	local requestRetreat = CampaignEvents:FindFirstChild("RequestRetreat")
	if requestRetreat then
		requestRetreat.OnServerEvent:Connect(function(player)
			local success, err = pcall(function()
				CampaignManager.RequestRetreat(player)
			end)

			if not success then
				warn("[CampaignManager] 撤退失败:", err)
			end
		end)
	end

	-- 玩家离开处理
	Players.PlayerRemoving:Connect(function(player)
		local playerId = player.UserId
		local campaignData = CampaignManager.ActiveCampaigns[playerId]

		if campaignData then
			print("[CampaignManager] 玩家离开，清理战役:", player.Name)
			CampaignManager.OnCampaignEnd(campaignData, false)
		end
	end)

	print("[CampaignManager] 初始化完成")
	return true
end

return CampaignManager
