--[[
脚本名称: ClientAIBootstrap
脚本类型: LocalScript
脚本位置: StarterPlayer/StarterPlayerScripts/ClientAI/ClientAIBootstrap
版本: V4.0 - 客户端AI迁移专用
]]

--[[
客户端AI启动脚本
职责:
1. 初始化客户端AI三大模块（ClientUnitManager, ClientPathService, ClientUnitAI）
2. 监听服务端战斗初始化事件（InitializeBattle）
3. 监听服务端战斗终止事件（TerminateBattle）
4. 监听服务端单位死亡事件（ServerUnitDeath）
5. 监听服务端位置同步事件（SyncUnitPosition）
6. 向服务端报告客户端准备就绪（ClientBattleReady）

V4.0设计要点:
- 客户端AI的入口脚本
- 负责模块加载和事件绑定
- 管理战斗生命周期
]]

-- ==================== 依赖服务 ====================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ==================== 获取本地玩家 ====================

local LocalPlayer = Players.LocalPlayer

-- ==================== 引用配置 ====================

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 加载客户端AI模块 ====================

-- 获取ClientAI文件夹路径（需要与此脚本在同一目录）
local ClientAIFolder = script.Parent
local ClientUnitManager = require(ClientAIFolder:WaitForChild("ClientUnitManager"))
local ClientPathService = require(ClientAIFolder:WaitForChild("ClientPathService"))
local ClientUnitAI = require(ClientAIFolder:WaitForChild("ClientUnitAI"))
local ClientMarchService = require(ClientAIFolder:WaitForChild("ClientMarchService"))  -- V5.0新增：客户端行军服务

-- ==================== RemoteEvent引用 ====================

local ClientAIEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ClientAIEvents")
local InitializeBattle = ClientAIEvents:WaitForChild("InitializeBattle")
local TerminateBattle = ClientAIEvents:WaitForChild("TerminateBattle")
local ServerUnitDeath = ClientAIEvents:WaitForChild("ServerUnitDeath")
local SyncUnitPosition = ClientAIEvents:WaitForChild("SyncUnitPosition")
local ClientBattleReady = ClientAIEvents:WaitForChild("ClientBattleReady")

-- V5.0新增：行军相关RemoteEvent
local StartMarch = ClientAIEvents:WaitForChild("StartMarch")
local MarchComplete = ClientAIEvents:WaitForChild("MarchComplete")

-- ==================== 私有变量 ====================

local activeBattles = {}  -- [battleId] = {attackUnits = {...}, defenseUnits = {...}}
local currentCampaignState = nil
local currentCampaignStage = nil

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, "[ClientAIBootstrap]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[ClientAIBootstrap]", ...)
end

-- ==================== 工具函数 ====================

--[[
计算表中元素数量
@param t table - 表
@return number - 元素数量
]]
local function CountTable(t)
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	return count
end

-- ==================== 战斗初始化处理 ====================

--[[
处理服务端发来的战斗初始化事件
@param battleId number - 战斗ID
@param attackUnits table - 攻击方单位列表 [{UnitModel=Model, UnitId=string, Level=number, Team="Attack"}, ...]
@param defenseUnits table - 防守方单位列表 [{UnitModel=Model, UnitId=string, Level=number, Team="Defense"}, ...]
@param battleField Folder - 战场文件夹
]]
-- ==================== CampaignState清理 ====================

local function IsIdleLikeCampaignState(state)
	return state == "Idle" or state == "Victory" or state == "Defeat" or state == "Cleanup"
end

local function ResetAllClientAIState(reason)
	DebugLog("ResetAllClientAIState:", reason or "unknown")

	pcall(function()
		if ClientMarchService and ClientMarchService.StopAllMarches then
			ClientMarchService.StopAllMarches()
		end
	end)

	pcall(function()
		if ClientUnitAI and ClientUnitAI.ClearAll then
			ClientUnitAI.ClearAll()
		end
	end)

	pcall(function()
		if ClientPathService and ClientPathService.ClearAll then
			ClientPathService.ClearAll()
		end
	end)

	pcall(function()
		if ClientUnitManager and ClientUnitManager.GetAllBattleIds and ClientUnitManager.ClearBattle then
			for _, battleId in ipairs(ClientUnitManager.GetAllBattleIds()) do
				ClientUnitManager.ClearBattle(battleId)
			end
		else
			for battleId, _ in pairs(activeBattles) do
				ClientUnitManager.ClearBattle(battleId)
			end
		end
	end)

	activeBattles = {}
end

local function OnCampaignStateUpdate(state, stageNum)
	currentCampaignState = state or "Idle"
	if type(stageNum) == "number" then
		currentCampaignStage = stageNum
	else
		local parsed = tonumber(stageNum)
		if parsed then
			currentCampaignStage = parsed
		end
	end

	-- 离开Marching后立刻停掉残留行军任务，防止多局重开后兵被旧目标点瞬移走
	if currentCampaignState ~= "Marching" then
		pcall(function()
			if ClientMarchService and ClientMarchService.StopAllMarches then
				ClientMarchService.StopAllMarches()
			end
		end)
	end

	if IsIdleLikeCampaignState(currentCampaignState) then
		ResetAllClientAIState("CampaignStateUpdate=" .. tostring(currentCampaignState))
	end
end

local function OnInitializeBattle(battleId, attackUnits, defenseUnits, battleField)
	DebugLog(string.format("收到战斗初始化: BattleId=%d, Attack=%d, Defense=%d",
		battleId, #attackUnits, #defenseUnits))

	-- 检查BattleConfig是否启用客户端AI
	if not BattleConfig.ENABLE_CLIENT_AI then
		WarnLog("客户端AI未启用，跳过初始化")
		return
	end

	-- ==================== V4.8修复：彻底清理所有客户端AI状态 ====================
	-- 关键修复：不论是否是同一个battleId，都先全局清理所有AI状态，防止状态残留导致卡死
	-- 这解决了以下问题：
	-- 1. Restart时旧的activeAIs和pathStates没有被清理
	-- 2. 旧的Humanoid.MoveToFinished连接仍然存在，导致MoveTo竞态
	-- 3. 单位复生后实例引用相同，但状态没有重置

	-- 先清理所有模块的全局状态（最彻底的方式）
	DebugLog("彻底清理所有客户端AI状态...")

	-- 0. V5.0新增：停止所有行军任务
	ClientMarchService.StopAllMarches()

	-- 1. 清理ClientUnitAI的所有activeAIs
	ClientUnitAI.ClearAll()

	-- 2. 清理ClientPathService的所有pathStates
	ClientPathService.ClearAll()

	-- 3. 清理ClientUnitManager的所有单位索引
	-- （遍历所有已记录的战斗ID并清理）
	for existingBattleId, _ in pairs(activeBattles) do
		ClientUnitManager.ClearBattle(existingBattleId)
	end

	-- 4. 清空本地战斗记录
	activeBattles = {}

	DebugLog("客户端AI状态清理完成，准备初始化新战斗")
	-- ==================== 修复结束 ====================

	-- 注册所有攻击方单位
	for _, unitData in ipairs(attackUnits) do
		local unitModel = unitData.UnitModel
		local unitId = unitData.UnitId
		local level = unitData.Level
		local team = unitData.Team

		-- 注册到ClientUnitManager
		local success = ClientUnitManager.RegisterUnit(battleId, team, unitModel, unitId, level)
		if not success then
			WarnLog("注册攻击方单位失败:", unitModel.Name)
			continue
		end

		-- 启动ClientUnitAI
		success = ClientUnitAI.StartAI(battleId, unitModel, unitId, level, team)
		if not success then
			WarnLog("启动攻击方AI失败:", unitModel.Name)
		end
	end

	-- V4.0修复：防守方也由客户端AI控制，服务端仅做伤害/死亡校验
	for _, unitData in ipairs(defenseUnits) do
		local unitModel = unitData.UnitModel
		local unitId = unitData.UnitId
		local level = unitData.Level
		local team = unitData.Team

		-- 注册到ClientUnitManager
		local success = ClientUnitManager.RegisterUnit(battleId, team, unitModel, unitId, level)
		if not success then
			WarnLog("注册防守方单位失败:", unitModel.Name)
			continue
		end

		-- V4.0修复：为防守方也启动ClientUnitAI
		success = ClientUnitAI.StartAI(battleId, unitModel, unitId, level, team)
		if not success then
			WarnLog("启动防守方AI失败:", unitModel.Name)
		end
	end

	-- 记录战斗数据
	activeBattles[battleId] = {
		attackUnits = attackUnits,
		defenseUnits = defenseUnits,
		battleField = battleField,
	}

	-- 向服务端报告客户端准备就绪
	ClientBattleReady:FireServer(battleId)

	DebugLog(string.format("战斗 %d 初始化完成", battleId))
end

-- ==================== 战斗终止处理 ====================

--[[
处理服务端发来的战斗终止事件
@param battleId number - 战斗ID
@param result string - 战斗结果
]]
local function OnTerminateBattle(battleId, result)
	DebugLog(string.format("收到战斗终止: BattleId=%d, Result=%s", battleId, result))

	local battleData = activeBattles[battleId]
	if not battleData then
		WarnLog("战斗", battleId, "不存在，无法终止")
		return
	end

	-- V5.0新增：停止所有行军任务
	ClientMarchService.StopAllMarches()

	-- 停止所有单位AI
	for _, unitData in ipairs(battleData.attackUnits) do
		ClientUnitAI.StopAI(unitData.UnitModel)
		ClientUnitManager.UnregisterUnit(unitData.UnitModel)
	end

	for _, unitData in ipairs(battleData.defenseUnits) do
		ClientUnitAI.StopAI(unitData.UnitModel)
		ClientUnitManager.UnregisterUnit(unitData.UnitModel)
	end

	-- 清理战斗数据
	ClientUnitManager.ClearBattle(battleId)
	ClientPathService.ClearAll()

	-- 移除战斗记录
	activeBattles[battleId] = nil

	DebugLog(string.format("战斗 %d 已终止", battleId))
end

-- ==================== 单位死亡处理 ====================

--[[
处理服务端发来的单位死亡事件
@param battleId number - 战斗ID
@param unitModel Model - 死亡的单位模型
@param killerModel Model|nil - 击杀者模型（可能为nil）
V4.2修复：先冻结物理和停止动画，再播放死亡动画
]]
local function OnServerUnitDeath(battleId, unitModel, killerModel)
	if not unitModel then
		WarnLog("收到无效的单位死亡事件")
		return
	end

	DebugLog(string.format("单位死亡: %s (BattleId=%d)", unitModel.Name, battleId))

	-- V4.2修复：首先标记AI为死亡状态（这会停止所有移动和动画）
	ClientUnitAI.MarkDead(unitModel)

	-- V4.2修复：获取Humanoid和RootPart引用
	local humanoid = unitModel:FindFirstChild("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	local animator = humanoid and humanoid:FindFirstChild("Animator")

	-- V4.7修复：如果没有Animator，自动创建一个（敌方单位可能没有预创建）
	if humanoid and not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
		DebugLog(string.format("%s 死亡时自动创建Animator", unitModel.Name))
	end

	-- V4.2修复：再次确保物理状态被冻结（双重保险）
	if humanoid then
		pcall(function()
			humanoid:Move(Vector3.zero)
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.AutoRotate = false
		end)
	end

	-- V4.6修复：清除速度（服务端已收回NetworkOwner，这里做兜底）
	if rootPart then
		pcall(function()
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	-- V4.2修复：停止所有正在播放的动画，为死亡动画让路
	if animator then
		pcall(function()
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end)
	end

	-- 播放死亡动画（如果有）
	if animator then
		-- V4.7修复：优先从ClientUnitManager获取，如果失败则从模型属性获取UnitId
		local unitInfo = ClientUnitManager.GetUnitBattleInfo(unitModel)
		local unitId = nil

		if unitInfo then
			unitId = unitInfo.UnitId
		else
			-- 备用方案：从模型属性获取UnitId
			unitId = unitModel:GetAttribute("UnitId")
			if not unitId then
				-- 尝试从模型名解析 (格式如 "10001_Lv1_1")
				unitId = unitModel.Name:match("^(%d+)_")
			end
			DebugLog(string.format("从属性获取UnitId: %s -> %s", unitModel.Name, tostring(unitId)))
		end

		if unitId then
			local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
			local deathAnimId = UnitConfig.GetDeathAnimationId(unitId)
			if deathAnimId and deathAnimId ~= "" then
				local anim = Instance.new("Animation")
				anim.AnimationId = "rbxassetid://" .. deathAnimId
				local success, animTrack = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if success and animTrack then
					-- V4.2修复：设置最高优先级，确保死亡动画不被其他动画覆盖
					animTrack.Priority = Enum.AnimationPriority.Action4
					animTrack.Looped = false
					animTrack:Play(0)  -- 立即播放，无淡入
					DebugLog(string.format("播放死亡动画: %s (UnitId=%s)", unitModel.Name, unitId))
				else
					WarnLog(string.format("加载死亡动画失败: %s", unitModel.Name))
				end
				anim:Destroy()
			else
				WarnLog(string.format("没有死亡动画配置: %s (UnitId=%s)", unitModel.Name, tostring(unitId)))
			end
		else
			WarnLog(string.format("无法获取UnitId，跳过死亡动画: %s", unitModel.Name))
		end
	end

	-- 延迟一段时间后注销单位（让死亡动画播放完）
	task.delay(BattleConfig.DEATH_ANIMATION_DURATION or 3, function()
		if unitModel and unitModel.Parent then
			ClientUnitAI.StopAI(unitModel)
			ClientUnitManager.UnregisterUnit(unitModel)
		end
	end)
end

-- ==================== 位置同步处理 ====================

--[[
处理服务端发来的位置同步事件（防作弊）
@param battleId number - 战斗ID
@param unitModel Model - 单位模型
@param position Vector3 - 服务端同步的位置
]]
local function OnSyncUnitPosition(battleId, unitModel, position)
	if not unitModel or not unitModel.Parent then
		return
	end

	-- 检查位置偏差是否超过容差
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local currentPos = rootPart.Position
	local distance = (currentPos - position).Magnitude

	-- 如果偏差超过容差，强制同步位置
	if distance > (BattleConfig.POSITION_VALIDATION_TOLERANCE or 10) then
		WarnLog(string.format("位置偏差过大 (%s: %.2f studs)，强制同步", unitModel.Name, distance))
		rootPart.CFrame = CFrame.new(position)

		-- 更新ClientUnitManager的位置缓存
		ClientUnitManager.UpdateUnitPosition(unitModel, position)
	end
end

-- ==================== V5.0新增：行军处理 ====================

--[[
处理服务端发来的行军指令
@param battleId number - 战斗ID
@param serializableMoveTargets table - 数组格式: {{unitName=string, targetCFrame=CFrame}, ...}
@param stageIndex number - 关卡索引
]]
local function OnStartMarch(battleId, serializableMoveTargets, stageIndex)
	local stageNum = tonumber(stageIndex)

	-- Ignore late StartMarch from previous rounds (e.g. after Restart/Respawn back to base)
	-- StartMarch/CampaignStateUpdate are different RemoteEvents and can arrive out-of-order; don't require state==Marching here.
	if currentCampaignState and IsIdleLikeCampaignState(currentCampaignState) then
		WarnLog(string.format("Ignore StartMarch because CampaignState=%s (BattleId=%s, Stage=%s)",
			tostring(currentCampaignState), tostring(battleId), tostring(stageIndex)))
		return
	end

	-- Defensive: ignore obviously stale StartMarch that jumps too far ahead of our last known stage
	if stageNum and currentCampaignStage and stageNum > (currentCampaignStage + 1) then
		WarnLog(string.format("Ignore StartMarch because StageJump (CurrentStage=%s, IncomingStage=%s, CampaignState=%s)",
			tostring(currentCampaignStage), tostring(stageNum), tostring(currentCampaignState)))
		return
	end

	-- Treat StartMarch as authoritative for entering Marching (handles RemoteEvent reordering)
	currentCampaignState = "Marching"
	if stageNum then
		currentCampaignStage = stageNum
	end

	-- Defensive: never allow overlapping march tasks
	pcall(function()
		ClientMarchService.StopAllMarches()
	end)
	DebugLog(string.format("收到行军指令: BattleId=%d, Units=%d, Stage=%d",
		battleId, #serializableMoveTargets, stageIndex))

	-- V5.0修复：将数组格式转换为 {[unitModel] = CFrame} 格式
	local moveTargets = {}
	local workspace = game:GetService("Workspace")

	local instanceIdIndex = nil
	local function BuildInstanceIdIndex()
		if instanceIdIndex then
			return
		end
		instanceIdIndex = {}
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("Model") then
				local id = nil
				pcall(function()
					id = obj:GetAttribute("InstanceId")
				end)
				if id and instanceIdIndex[id] == nil then
					instanceIdIndex[id] = obj
				end
			end
		end
	end

	local function ResolveMarchUnitModel(entry)
		local unitModel = entry.unitModel
		if typeof(unitModel) == "Instance" and unitModel:IsA("Model") then
			return unitModel
		end

		local instanceId = entry.instanceId
		if type(instanceId) == "string" and instanceId ~= "" then
			BuildInstanceIdIndex()
			local byId = instanceIdIndex and instanceIdIndex[instanceId]
			if typeof(byId) == "Instance" and byId:IsA("Model") then
				return byId
			end
		end

		local unitName = entry.unitName
		if type(unitName) == "string" and unitName ~= "" then
			local byName = workspace:FindFirstChild(unitName, true)
			if byName and byName:IsA("Model") then
				return byName
			end
		end

		return nil
	end

	for _, entry in ipairs(serializableMoveTargets) do
		local targetCFrame = entry.targetCFrame
		if typeof(targetCFrame) ~= "CFrame" then
			local fallback = entry.unitName or entry.instanceId or "unknown"
			warn(string.format("  [March] Invalid targetCFrame for %s", tostring(fallback)))
		else
			local unitModel = ResolveMarchUnitModel(entry)
			if unitModel then
				moveTargets[unitModel] = targetCFrame
				DebugLog(string.format("  [March] Resolved unit: %s", unitModel.Name))
			else
				local fallback = entry.unitName or entry.instanceId or "unknown"
				warn(string.format("  [March] Could not resolve unit: %s", tostring(fallback)))
			end
		end
	end
	DebugLog(string.format("成功解析 %d 个单位进行行军", CountTable(moveTargets)))

	-- 调用ClientMarchService开始行军
	-- Ensure march-mode flag is set locally so ClientMarchService's teleport fallback isn't blocked by stale CombatMode
	for unitModel, _ in pairs(moveTargets) do
		pcall(function()
			unitModel:SetAttribute("UnitAIMode", "MarchMode")
		end)
	end

	ClientMarchService.MoveUnitsToPositions(moveTargets, {
		onUnitArrived = function(unitModel, status)
			DebugLog(unitModel.Name, "到达:", status)
		end,
		onAllSettled = function(arrivedList, timedOutList, failedList)
			-- 向服务端报告行军完成
			MarchComplete:FireServer(battleId, arrivedList, failedList)
			DebugLog(string.format("行军完成: 到达=%d, 超时=%d, 失败=%d",
				#arrivedList, #timedOutList, #failedList))
		end
	})
end

-- ==================== 初始化系统 ====================

local function Initialize()
	DebugLog("开始初始化客户端AI系统...")

	-- 初始化三大模块
	ClientUnitManager.Initialize()
	-- ClientPathService不需要Initialize，它是无状态服务
	ClientUnitAI.Initialize(ClientUnitManager, ClientPathService, ClientMarchService)

	-- V5.0新增：初始化ClientMarchService
	ClientMarchService.Initialize(ClientUnitManager, ClientPathService)

	-- 绑定服务端事件
	InitializeBattle.OnClientEvent:Connect(OnInitializeBattle)
	TerminateBattle.OnClientEvent:Connect(OnTerminateBattle)
	ServerUnitDeath.OnClientEvent:Connect(OnServerUnitDeath)
	SyncUnitPosition.OnClientEvent:Connect(OnSyncUnitPosition)

	-- V5.0新增：绑定行军事件
	StartMarch.OnClientEvent:Connect(OnStartMarch)

	-- Bind CampaignStateUpdate: clean up leftover marches/AIs when returning to base
	task.spawn(function()
		local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
		if not eventsFolder then
			WarnLog("Events folder not found; leftover client AI state may persist across rounds")
			return
		end

		local campaignEvents = eventsFolder:WaitForChild("CampaignEvents", 10)
		if not campaignEvents then
			WarnLog("CampaignEvents not found; leftover client AI state may persist across rounds")
			return
		end

		local stateUpdateEvent = campaignEvents:WaitForChild("CampaignStateUpdate", 10)
		if not stateUpdateEvent then
			WarnLog("CampaignStateUpdate not found; leftover client AI state may persist across rounds")
			return
		end

		stateUpdateEvent.OnClientEvent:Connect(OnCampaignStateUpdate)
	end)

	DebugLog("客户端AI系统初始化完成！")
end

-- ==================== 脚本入口 ====================

-- 等待本地玩家完全加载后再初始化
if LocalPlayer then
	Initialize()
else
	Players.PlayerAdded:Wait()
	Initialize()
end
