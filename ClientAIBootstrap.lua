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

-- ==================== RemoteEvent引用 ====================

local ClientAIEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ClientAIEvents")
local InitializeBattle = ClientAIEvents:WaitForChild("InitializeBattle")
local TerminateBattle = ClientAIEvents:WaitForChild("TerminateBattle")
local ServerUnitDeath = ClientAIEvents:WaitForChild("ServerUnitDeath")
local SyncUnitPosition = ClientAIEvents:WaitForChild("SyncUnitPosition")
local ClientBattleReady = ClientAIEvents:WaitForChild("ClientBattleReady")

-- ==================== 私有变量 ====================

local activeBattles = {}  -- [battleId] = {attackUnits = {...}, defenseUnits = {...}}

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, "[ClientAIBootstrap]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[ClientAIBootstrap]", ...)
end

-- ==================== 战斗初始化处理 ====================

--[[
处理服务端发来的战斗初始化事件
@param battleId number - 战斗ID
@param attackUnits table - 攻击方单位列表 [{UnitModel=Model, UnitId=string, Level=number, Team="Attack"}, ...]
@param defenseUnits table - 防守方单位列表 [{UnitModel=Model, UnitId=string, Level=number, Team="Defense"}, ...]
@param battleField Folder - 战场文件夹
]]
local function OnInitializeBattle(battleId, attackUnits, defenseUnits, battleField)
	DebugLog(string.format("收到战斗初始化: BattleId=%d, Attack=%d, Defense=%d",
		battleId, #attackUnits, #defenseUnits))

	-- 检查BattleConfig是否启用客户端AI
	if not BattleConfig.ENABLE_CLIENT_AI then
		WarnLog("客户端AI未启用，跳过初始化")
		return
	end

	-- 清理旧战斗数据（如果存在）
	if activeBattles[battleId] then
		WarnLog("战斗", battleId, "已存在，先清理旧数据")

		-- 直接执行清理逻辑，不调用OnTerminateBattle避免递归
		local oldBattleData = activeBattles[battleId]

		-- 停止所有单位AI
		if oldBattleData.attackUnits then
			for _, unitData in ipairs(oldBattleData.attackUnits) do
				ClientUnitAI.StopAI(unitData.UnitModel)
				ClientUnitManager.UnregisterUnit(unitData.UnitModel)
			end
		end

		if oldBattleData.defenseUnits then
			for _, unitData in ipairs(oldBattleData.defenseUnits) do
				ClientUnitAI.StopAI(unitData.UnitModel)
				ClientUnitManager.UnregisterUnit(unitData.UnitModel)
			end
		end

		-- 清理战斗数据
		ClientUnitManager.ClearBattle(battleId)
		ClientPathService.ClearAll()

		-- 移除战斗记录
		activeBattles[battleId] = nil
	end

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

	print(GameConfig.LOG_PREFIX, string.format("[ClientAIBootstrap] 战斗 %d 初始化完成", battleId))
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

	print(GameConfig.LOG_PREFIX, string.format("[ClientAIBootstrap] 战斗 %d 已终止", battleId))
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
		local unitInfo = ClientUnitManager.GetUnitBattleInfo(unitModel)
		if unitInfo then
			local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
			local deathAnimId = UnitConfig.GetDeathAnimationId(unitInfo.UnitId)
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
					DebugLog(string.format("播放死亡动画: %s", unitModel.Name))
				end
				anim:Destroy()
			end
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

-- ==================== 初始化系统 ====================

local function Initialize()
	print(GameConfig.LOG_PREFIX, "[ClientAIBootstrap] 开始初始化客户端AI系统...")

	-- 初始化三大模块
	ClientUnitManager.Initialize()
	-- ClientPathService不需要Initialize，它是无状态服务
	ClientUnitAI.Initialize(ClientUnitManager, ClientPathService)

	-- 绑定服务端事件
	InitializeBattle.OnClientEvent:Connect(OnInitializeBattle)
	TerminateBattle.OnClientEvent:Connect(OnTerminateBattle)
	ServerUnitDeath.OnClientEvent:Connect(OnServerUnitDeath)
	SyncUnitPosition.OnClientEvent:Connect(OnSyncUnitPosition)

	print(GameConfig.LOG_PREFIX, "[ClientAIBootstrap] 客户端AI系统初始化完成！")
end

-- ==================== 脚本入口 ====================

-- 等待本地玩家完全加载后再初始化
if LocalPlayer then
	Initialize()
else
	Players.PlayerAdded:Wait()
	Initialize()
end
