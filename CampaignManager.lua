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
local DoorControlService = require(ServerScriptService.Systems.DoorControlService)  -- V2.0.1新增：门控制

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

-- V2.3性能优化：Campaign路径缓存
-- 缓存基地到关卡的路径，避免N个单位重复ComputeAsync相同路径
-- pathCache[homeId][stageNum] = {waypoints = {Vector3}, expiryTime = number}
local pathCache = {}

-- V2.3配置：路径缓存时间（秒）
local PATH_CACHE_EXPIRY = 300  -- 5分钟过期（关卡地形变化时自动失效）

-- ==================== 私有函数 ====================

--[[
V2.3新增：获取缓存的路径
@param homeId number - 基地ID
@param stageNum number - 关卡编号
@return {Vector3}|nil - 缓存的路径点列表，如果不存在或已过期则返回nil
]]
local function GetCachedPath(homeId, stageNum)
	if not pathCache[homeId] then
		return nil
	end

	local cacheEntry = pathCache[homeId][stageNum]
	if not cacheEntry then
		return nil
	end

	-- 检查是否过期
	local now = tick()
	if now > cacheEntry.expiryTime then
		-- 已过期，清除缓存
		pathCache[homeId][stageNum] = nil
		return nil
	end

	return cacheEntry.waypoints
end

--[[
V2.3新增：存储路径到缓存
@param homeId number - 基地ID
@param stageNum number - 关卡编号
@param waypoints {Vector3} - 路径点列表
]]
local function CachePath(homeId, stageNum, waypoints)
	if not pathCache[homeId] then
		pathCache[homeId] = {}
	end

	pathCache[homeId][stageNum] = {
		waypoints = waypoints,
		expiryTime = tick() + PATH_CACHE_EXPIRY
	}
end

--[[
V2.3新增：清除指定基地的所有路径缓存
@param homeId number - 基地ID
]]
local function ClearPathCache(homeId)
	if pathCache[homeId] then
		pathCache[homeId] = nil
	end
end

--[[
设置兵种的锚定状态（内部使用）
@param unitModel Model - 兵种模型
@param anchored boolean - 是否锚定
]]
local function SetUnitAnchored(unitModel, anchored)
	if not unitModel then
		return
	end

	-- V2.0修复：保留下半身部件的碰撞，防止解锚后"插入地面"
	-- 原因：只保留HRP碰撞时，解锚瞬间脚部失去支撑，整个模型会沉到HRP碰到地面为止
	-- 解决：保留腿部和脚部的碰撞，让兵种正常站在地面上
	local lowerBodyParts = {
		"LeftFoot", "RightFoot",           -- 脚部（R15）
		"LeftLowerLeg", "RightLowerLeg",   -- 小腿（R15）
		"LowerTorso",                       -- 下半身躯干（R15）
		"Left Leg", "Right Leg",            -- 腿部（R6）
	}

	-- 创建快速查找表
	local lowerBodySet = {}
	for _, name in ipairs(lowerBodyParts) do
		lowerBodySet[name] = true
	end

	-- 遍历所有 BasePart 设置锚定和碰撞
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored

			-- HumanoidRootPart 和下半身部件保持碰撞
			if descendant.Name == "HumanoidRootPart" or lowerBodySet[descendant.Name] then
				descendant.CanCollide = true
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
关键修复：优先查找直接子节点IdleFloor，避免误返回Stage目录下的IdleFloor
]]
local function GetHomeIdleFloor(homeId)
	local homeFolder = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
	if not homeFolder then
		return nil
	end

	-- V2.0.2修复：先在直接子节点中查找IdleFloor（不递归）
	-- 这样可以获取基地根目录下的IdleFloor，而不是Stage文件夹中的
	local homeIdleFloor = homeFolder:FindFirstChild("IdleFloor", false)
	if homeIdleFloor then
		return homeIdleFloor
	end

	-- 回退方案：如果直接子节点中没有IdleFloor，才进行递归搜索
	-- 但此时要跳过所有Stage*文件夹，防止误返回关卡内的IdleFloor
	for _, child in ipairs(homeFolder:GetChildren()) do
		-- 跳过Stage文件夹
		if child:IsA("Folder") and child.Name:match("^Stage") then
			continue
		end

		-- 在非Stage子文件夹中递归搜索IdleFloor
		local found = child:FindFirstChild("IdleFloor", true)
		if found then
			return found
		end
	end

	-- 最后的回退：直接返回nil，不再盲目递归
	return nil
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

			-- V2.0.1新增：标记为战役单位，死亡时保留实例用于重生
			unitModel:SetAttribute("CampaignKeepInstance", true)

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
		end
	end

	-- V2.0.1新增：打开基地大门（兵种有效后再开门）
	pcall(function()
		DoorControlService.OpenDoor(homeId)
	end)

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

	-- V2.0.3：解锁当前关的空气墙（允许玩家进入）
	StageService.SetAirWallState(stageFolder, true)

	-- V2.0.3：确保下一关的空气墙保持锁定（如果已生成）
	local nextStageNum = stageNum + 1
	if nextStageNum <= campaignData.TotalStages then
		local nextStageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, nextStageNum)
		if nextStageFolder then
			StageService.SetAirWallState(nextStageFolder, false)
		end
	end

	-- V2.0修复：使用递归搜索，支持IdleFloor在子文件夹中（如Stage001/StageNodes/IdleFloor）
	local targetIdleFloor = stageFolder:FindFirstChild("IdleFloor", true)
	if not targetIdleFloor then
		warn("[CampaignManager] 关卡IdleFloor未找到（已递归搜索）:", stageNum, "关卡路径:", stageFolder:GetFullName())
		return CampaignManager.OnCampaignEnd(campaignData, false)
	end

	-- V2.3.1性能优化回退：移除路径缓存机制
	-- 原因：共享路径导致以下问题：
	-- 1. 所有单位挤向同一waypoint，部分兵被堵在原地
	-- 2. Stage间切换时路径起点错误，兵往基地方向走
	-- 现有的限流机制（20次/帧+队列分配）足以支撑100单位per-unit寻路
	local cachedWaypoints = nil  -- 不再使用缓存

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
				end
			end

			-- V2.0修复：开始行军时播放移动动画
			UnitAI.PlayMoveAnimation(unitInstance)
		end
	end

	-- 调用PathService批量寻路（使用新的回调API）
	-- V2.3.1：移除缓存路径传入，让每个单位使用真实起点寻路
	local moveId = PathService.MoveUnitsToPositions(moveTargets, {
		onUnitArrived = function(unitInstance, status)
			-- 单位到达时的回调（可选，这里暂时不处理）
		end,

		onAllSettled = function(arrivedList, timedOutList, failedList)
			-- 所有单位完成移动后的回调

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
	})  -- V2.3.1：移除第三个参数cachedWaypoints

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
			else
				warn(string.format("  ❌ 友军准备失败: %s", unitData.UnitId))
			end
		end
	end

	-- 获取并激活敌军
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
	else
		warn("[CampaignManager] IdleFloorEnemy未找到")
	end

	-- 检查是否可以开战
	if #preparedAllies == 0 or #preparedEnemies == 0 then
		warn(string.format("[CampaignManager] 无法开战：友军%d，敌军%d", #preparedAllies, #preparedEnemies))
		return CampaignManager.OnDefeat(campaignData)
	end

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

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.FIGHTING, stageNum)
		end
	end

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

	-- 前往下一关
	local nextStage = stageNum + 1

	-- V2.0.3：立刻解锁下一关的空气墙
	local nextStageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, nextStage)
	if nextStageFolder then
		StageService.SetAirWallState(nextStageFolder, true)
	end

	-- 提前生成下下关（并保持其空气墙锁定）
	if nextStage + 1 <= campaignData.TotalStages then
		task.spawn(function()
			local nextNextStageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, nextStage + 1)
			if nextNextStageFolder then
				-- V2.0.3：确保新预加载的下下关空气墙保持锁定
				StageService.SetAirWallState(nextNextStageFolder, false)
			end
		end)
	end

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

	-- 计算奖励（V2.0修复：使用配置的模板风格，而非硬编码Style01）
	local totalReward = 0
	local templateStyle = GameConfig.Campaign.StageTemplateStyle or "Style01"
	local styleRewards = StageConfig[templateStyle] and StageConfig[templateStyle].Rewards

	if styleRewards then
		for i = 1, campaignData.TotalStages do
			local reward = styleRewards[i]
			if reward then
				totalReward = totalReward + (reward.Coins or 0)
			end
		end
	else
		warn("[CampaignManager] 未找到风格奖励配置:", templateStyle)
	end

	-- 发放奖励 (V2.0修复：使用AddCoins而不是AddCurrency)
	if totalReward > 0 then
		CurrencySystem.AddCoins(campaignData.Player, totalReward, "战役胜利奖励")
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

	-- V2.0.1新增：关闭基地大门（确保门总是被关闭）
	pcall(function()
		DoorControlService.CloseDoor(campaignData.HomeId)
	end)

	-- V2.3性能优化：清理路径缓存
	ClearPathCache(campaignData.HomeId)

	-- 重生兵种
	CampaignManager.RespawnUnits(campaignData)

	-- V2.0.3修复：战役彻底结束后，清除所有单位的CampaignKeepInstance标记
	-- 这样下次战役开始前，单位恢复正常状态
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent then
			pcall(function()
				unitInstance:SetAttribute("CampaignKeepInstance", false)
			end)
		end
	end

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
end

--[[
恢复单位的动画和Humanoid状态（V2.0.1新增）
用于战役重生后清理死亡状态，恢复正常基地状态
@param unitModel Model - 单位模型
@param unitId string - 单位ID（用于日志）
]]
local function RestoreUnitAnimationState(unitModel, unitId)
	if not unitModel then
		return
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[CampaignManager] RestoreUnitAnimationState失败：找不到Humanoid", unitId)
		return
	end

	-- 1. 恢复Humanoid状态
	pcall(function()
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)

	-- 2. 重新启用所有Animate脚本
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			if descendant.Name == "Animate" then
				descendant.Disabled = false
			end
		end
	end

	-- 3. 清理残留的死亡动画Track
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = unitModel:FindFirstChildOfClass("Animator")
	end

	if animator then
		local playingTracks = animator:GetPlayingAnimationTracks()
		for _, track in ipairs(playingTracks) do
			pcall(function()
				track:Stop(0)
			end)
		end
	end

	-- 4. 短暂延迟后，Animate脚本会自动播放show/idle动画
	-- 无需手动启动，Animate脚本会根据Humanoid状态自动处理
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

	-- V2.0.1修复：支持重生死亡隐藏的单位
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance then
			-- V2.0.3修复：检查单位是否已被销毁（避免Parent locked错误）
			-- 如果实例已经被Destroy()，跳过该单位
			if not unitInstance:IsDescendantOf(game) and unitInstance.Parent == nil then
				-- 检查是否真的被销毁了（Parent locked状态）
				local success = pcall(function()
					local _ = unitInstance.Name  -- 尝试访问属性
				end)
				if not success then
					warn("[CampaignManager] 单位已被销毁，跳过重生:", unitData.UnitId)
					continue
				end
			end

			-- V2.0.3修复：如果单位被隐藏（Parent = nil），重新挂回基地根节点（PlayerHome）
			-- 使用pcall包裹，防止Parent locked错误
			if not unitInstance.Parent then
				local homeFolder = homeIdleFloor.Parent
				local success, err = pcall(function()
					if homeFolder then
						unitInstance.Parent = homeFolder
					else
						warn("[CampaignManager] 找不到基地根节点（IdleFloor.Parent）")
						unitInstance.Parent = homeIdleFloor  -- 回退方案
					end
				end)

				if not success then
					warn("[CampaignManager] 设置Parent失败（单位可能已被销毁）:", unitData.UnitId, err)
					continue
				end
			end

			-- 计算原位置（使用基地IdleFloor进行坐标换算）
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

			-- V2.0.1新增：恢复动画和Humanoid状态（必须在播放特效后）
			RestoreUnitAnimationState(unitInstance, unitData.UnitId)

			-- V2.0.3修复：不要在这里清除CampaignKeepInstance
			-- 保持该标记直到战役彻底结束（在OnCampaignEnd中统一清除）
			-- 这样多关卡战斗中单位死亡后不会被Destroy()
		end
	end
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

	CampaignManager.OnDefeat(campaignData)
end

--[[
初始化CampaignManager
]]
function CampaignManager.Initialize()
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
			CampaignManager.OnCampaignEnd(campaignData, false)
		end
	end)

	return true
end

return CampaignManager
