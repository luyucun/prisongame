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
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript)
local StageConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StageConfig") :: ModuleScript)

-- 引用核心服务（使用类型断言避免类型检查警告）
local PlayerManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("PlayerManager") :: ModuleScript)

-- 引用系统模块
local SystemsFolder = ServerScriptService:WaitForChild("Systems")
local GridPositionSystem = require(SystemsFolder:WaitForChild("GridPositionSystem") :: ModuleScript)
local StageService = require(SystemsFolder:WaitForChild("StageService") :: ModuleScript)
local PathService = require(SystemsFolder:WaitForChild("PathService") :: ModuleScript)
local BattleManager = require(SystemsFolder:WaitForChild("BattleManager") :: ModuleScript)
local CurrencySystem = require(SystemsFolder:WaitForChild("CurrencySystem") :: ModuleScript)
local UnitAI = require(SystemsFolder:WaitForChild("UnitAI") :: ModuleScript)  -- V2.0新增：用于控制行军动画
local CampaignUnitHelper = require(SystemsFolder:WaitForChild("CampaignUnitHelper") :: ModuleScript)  -- V2.0新增：单位激活/复位
local DoorControlService = require(SystemsFolder:WaitForChild("DoorControlService") :: ModuleScript)  -- V2.0.1新增：门控制

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

-- ==================== 调试日志 ====================

local function DebugLog(...)
	if GameConfig.Campaign.EnablePathDebugLogs or GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "[CampaignManager]", ...)
	end
end

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
🔥 修复1: 安全设置 Parent，防止 Locked 报错
V2.6增强: 增加多重重试机制
]]
local function SafeSetParent(instance, newParent)
	if not instance or not newParent then
		return false
	end

	-- 检查实例是否已被销毁
	local validInstance = pcall(function() return instance.Name end)
	if not validInstance then
		return false
	end

	-- 如果已经在正确的Parent下，直接返回成功
	if instance.Parent == newParent then
		return true
	end

	-- 尝试直接设置
	local success = pcall(function()
		instance.Parent = newParent
	end)
	if success then
		return true
	end

	-- 如果失败，等待一帧后重试
	task.wait()
	success = pcall(function()
		instance.Parent = newParent
	end)
	if success then
		return true
	end

	-- 最后用defer重试
	task.defer(function()
		pcall(function()
			instance.Parent = newParent
		end)
	end)

	-- 等待一下看看是否成功
	task.wait(0.1)
	return instance.Parent == newParent
end

--[[
🔥 修复2: 强制设置网络所有权为服务器，解决顿卡/鬼畜问题
]]
local function SetNetworkOwnerToServer(model)
	if not model then return end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part:CanSetNetworkOwnership() then
			-- 只有服务器脚本可以调用此函数
			-- 参数 nil 表示将所有权交给服务器，禁止客户端接管物理计算
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end
end

--[[
设置兵种的锚定状态（内部使用）
@param unitModel Model - 兵种模型
@param anchored boolean - 是否锚定
@param displayMode boolean - 展示模式（可选）：true=只锚定HRP，false/nil=全部锚定（默认）
]]
local function SetUnitAnchored(unitModel, anchored, displayMode)
	if not unitModel then
		return
	end

	-- V2.1修复：展示模式下只锚定HRP，让Motor6D能正常驱动动画
	if displayMode and anchored then
		-- 展示模式：只锚定HumanoidRootPart，其他部件不锚定但关闭碰撞
		local humanoidRootPart = unitModel:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			humanoidRootPart.Anchored = true
			humanoidRootPart.CanCollide = true
		end

		-- 其他部件：不锚定，关闭碰撞
		for _, descendant in ipairs(unitModel:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
				descendant.Anchored = false      -- 不锚定，允许动画播放
				descendant.CanCollide = false    -- 禁用碰撞，避免肢体碰撞干扰
			end
		end

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

	-- V2.5寻路优化：设置兵种碰撞组，关闭兵种间碰撞
	if not anchored then
		-- V2.6修复：统一使用PhysicsManager的Allies/Enemies系统
		-- 移除CollisionSystem调用，避免与PhysicsManager冲突
		local PhysicsManager = ServerScriptService.Systems:FindFirstChild("PhysicsManager")
		if PhysicsManager then
			local PhysicsModule = require(PhysicsManager)
			pcall(function()
				-- 友军使用"ally"参数，会设置为Allies碰撞组
				PhysicsModule.ConfigureUnitPhysics(unitModel, "ally")
			end)
		end

		-- 🔥 关键修复：强制服务器拥有物理权，防止客户端干扰导致的卡顿
		SetNetworkOwnerToServer(unitModel)
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
		end
	end
	return CampaignEvents ~= nil
end

--[[
V2.3新增：血条事件工具函数
用于在战役各阶段管理血条显示
]]
local function fireAttachHealthBars(units)
	local events = ReplicatedStorage:FindFirstChild("Events")
	local battleEvents = events and events:FindFirstChild("BattleEvents")
	local attach = battleEvents and battleEvents:FindFirstChild("AttachHealthBars")
	if not attach then return end

	local send = {}
	for _, u in ipairs(units) do
		if u and u.Parent then table.insert(send, u) end
	end
	if #send > 0 then
		attach:FireAllClients(send)
		DebugLog(string.format("🏷️ 广播挂载血条，单位数量: %d", #send))
	end
end

local function fireDetachHealthBars(units) -- 可选，用于失败/清理兜底
	local events = ReplicatedStorage:FindFirstChild("Events")
	local battleEvents = events and events:FindFirstChild("BattleEvents")
	local detach = battleEvents and battleEvents:FindFirstChild("DetachHealthBars")
	if not detach then return end

	local send = {}
	for _, u in ipairs(units) do
		if u then table.insert(send, u) end
	end
	if #send > 0 then
		detach:FireAllClients(send)
		DebugLog(string.format("🏷️ 广播移除血条，单位数量: %d", #send))
	end
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
设置基地战斗状态视觉效果
@param homeId number - 基地ID
@param isFighting boolean - 是否处于战斗中
功能说明：
- 控制IdleFloor下Fighting Part的视觉效果
- isFighting=true时：启用ParticleEmitter和BillboardGui，复制RedLine覆盖IdleFloor
- isFighting=false时：禁用这些效果，移除RedLine
]]
local function SetHomeFightingEffect(homeId, isFighting)
	local idleFloor = GetHomeIdleFloor(homeId)
	if not idleFloor then
		DebugLog(string.format("SetHomeFightingEffect: 未找到HomeId=%d的IdleFloor", homeId))
		return
	end

	-- 查找Fighting Part
	local fightingPart = idleFloor:FindFirstChild("Fighting")
	if not fightingPart then
		DebugLog(string.format("SetHomeFightingEffect: IdleFloor下未找到Fighting Part, HomeId=%d", homeId))
		return
	end

	-- 设置ParticleEmitter的Enabled属性
	local particleEmitter = fightingPart:FindFirstChild("ParticleEmitter")
	if particleEmitter and particleEmitter:IsA("ParticleEmitter") then
		particleEmitter.Enabled = isFighting
		DebugLog(string.format("  ✨ ParticleEmitter.Enabled = %s", tostring(isFighting)))
	else
		DebugLog(string.format("  ⚠️ 未找到ParticleEmitter, HomeId=%d", homeId))
	end

	-- 设置BillboardGui的Enabled属性
	local billboardGui = fightingPart:FindFirstChild("Fighting")
	if billboardGui and billboardGui:IsA("BillboardGui") then
		billboardGui.Enabled = isFighting
		DebugLog(string.format("  🏷️ BillboardGui.Enabled = %s", tostring(isFighting)))
	else
		DebugLog(string.format("  ⚠️ 未找到Fighting BillboardGui, HomeId=%d", homeId))
	end

	-- V2.6新增：RedLine覆盖层控制
	local redLineName = "RedLine_Home" .. homeId  -- 唯一命名，便于查找和移除

	if isFighting then
		-- 战斗开始：复制RedLine并覆盖到IdleFloor上
		local redLineTemplate = ReplicatedStorage:FindFirstChild("RedLine")
		if redLineTemplate and redLineTemplate:IsA("BasePart") then
			-- 检查是否已存在（防止重复创建）
			local existingRedLine = idleFloor:FindFirstChild(redLineName)
			if not existingRedLine then
				local redLineClone = redLineTemplate:Clone()
				redLineClone.Name = redLineName

				-- 设置位置：覆盖在IdleFloor上方
				-- RedLine的Size与IdleFloor相同，位置略高于IdleFloor表面
				redLineClone.Size = Vector3.new(idleFloor.Size.X, redLineTemplate.Size.Y, idleFloor.Size.Z)
				redLineClone.CFrame = CFrame.new(
					idleFloor.Position.X,
					idleFloor.Position.Y + (idleFloor.Size.Y / 2) + (redLineClone.Size.Y / 2) + 0.01,  -- 略高于IdleFloor表面
					idleFloor.Position.Z
				)

				-- 确保不影响物理碰撞
				redLineClone.CanCollide = false
				redLineClone.Anchored = true

				redLineClone.Parent = idleFloor
				DebugLog(string.format("  🔴 RedLine已创建并覆盖到IdleFloor, HomeId=%d", homeId))
			else
				DebugLog(string.format("  🔴 RedLine已存在，跳过创建, HomeId=%d", homeId))
			end
		else
			DebugLog(string.format("  ⚠️ ReplicatedStorage中未找到RedLine模板, HomeId=%d", homeId))
		end
	else
		-- 战斗结束：移除RedLine
		local existingRedLine = idleFloor:FindFirstChild(redLineName)
		if existingRedLine then
			existingRedLine:Destroy()
			DebugLog(string.format("  🔴 RedLine已移除, HomeId=%d", homeId))
		end
	end

	DebugLog(string.format("🎮 SetHomeFightingEffect完成: HomeId=%d, isFighting=%s", homeId, tostring(isFighting)))
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
		return false
	end

	-- 获取HomeId
	local homeId = PlayerManager.GetPlayerHomeId(player)
	if not homeId then
		return false
	end

	-- 收集兵种（从PlacementSystem获取）
	local placementModule = SystemsFolder:FindFirstChild("PlacementSystem")
	if not placementModule then
		warn("[CampaignManager] 无法找到PlacementSystem模块")
		return false
	end
	-- 修复：添加类型断言避免类型检查警告
	local PlacementSystem = require(placementModule :: ModuleScript)
	local placedUnits = PlacementSystem.GetPlacedUnitModels(player)

	if not placedUnits or #placedUnits == 0 then
		return false
	end

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
		return false
	end

	for _, unitModel in ipairs(placedUnits) do
		-- 获取GridPos（兼容历史数据）
		local gridPos = GridPositionSystem.LoadUnitGridPosition(unitModel, homeIdleFloor)

		-- 获取兵种配置
		local UnitConfig = require(ReplicatedStorage.Config.UnitConfig)
		-- V2.0.5修复：从Attribute获取UnitId，而不是Name
		-- Name是显示名称(如"Noob")，UnitId是配置key(如"10001")
		local unitId = unitModel:GetAttribute("UnitId") or unitModel.Name
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

	-- V2.6新增：启用战斗状态视觉效果（粒子特效和战斗中提示）
	SetHomeFightingEffect(homeId, true)

	-- V2.0.4修复：预生成Stage002，但不重置空气墙(稍后会统一设置)
	StageService.GetOrCreateStage(playerId, 2, false)

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
	-- 检查玩家是否仍在线
	local playerId = campaignData.PlayerId
	local player = game.Players:GetPlayerByUserId(playerId)
	if not player then
		DebugLog("玩家已离线，跳过行军:", playerId, "关卡:", stageNum)
		return  -- 直接返回，不处理离线玩家的任务
	end

	campaignData.State = CampaignState.MARCHING

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.MARCHING, stageNum)
		end
	end

	-- V2.7修复：行军前禁用默认Animate脚本，避免与自定义MoveAnimation冲突
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent then
			for _, descendant in ipairs(unitInstance:GetDescendants()) do
				if descendant:IsA("BaseScript") and descendant.Name == "Animate" then
					descendant.Enabled = false
					DebugLog(string.format("🔇 %s 禁用默认Animate脚本", unitData.UnitId))
				end
			end
		end
	end

	-- V2.4新增：行军前禁用所有单位的AI（避免100个单位的AI轮询开销）
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent and unitInstance:FindFirstChild("Humanoid") then
			-- 关键优化：设置MarchMode，禁用AI战斗决策
			-- 行军只需要纯寻路，不需要寻敌、换目标等复杂AI逻辑
			if UnitAI.SetMode then
				local success = UnitAI.SetMode(unitInstance, "MarchMode")
				if success then
					DebugLog(string.format("  🚀 %s 进入行军模式（AI已禁用）", unitData.UnitId))
				else
					-- AI未启动，这在行军阶段是正常的，不需要警告
					-- DebugLog(string.format("  ⚠️ %s AI未启动，跳过行军模式设置", unitData.UnitId))
				end
			end

			-- V2.6修复：统一使用PhysicsManager，防止与CollisionSystem冲突
			local PhysicsManager = ServerScriptService.Systems:FindFirstChild("PhysicsManager")
			if PhysicsManager then
				local PhysicsModule = require(PhysicsManager)
				pcall(function()
					-- 友军使用"ally"参数，会设置为Allies碰撞组
					PhysicsModule.ConfigureUnitPhysics(unitInstance, "ally")
					DebugLog(string.format("  ✅ %s 碰撞组已设置为Allies", unitData.UnitId))
				end)
			end
		end
	end

	-- 获取目标关卡
	-- V2.0.4修复：不重置空气墙状态,后面会显式控制
	local stageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, stageNum, false)
	if not stageFolder then
		return CampaignManager.OnCampaignEnd(campaignData, false)
	end

	-- V2.0.3：解锁当前关的空气墙（允许玩家进入）
	StageService.SetAirWallState(stageFolder, true)

	-- V2.0.3修复：确保下一关的空气墙保持锁定（如果已生成）
	-- 注意：只处理还未到达的关卡，避免锁定当前正在挑战的关卡
	local nextStageNum = stageNum + 1
	if nextStageNum <= campaignData.TotalStages then
		-- 检查下一关是否已存在但还未解锁
		local nextStageFolder = nil
		if StageService.StageCache[campaignData.PlayerId] and
			StageService.StageCache[campaignData.PlayerId][nextStageNum] then
			nextStageFolder = StageService.StageCache[campaignData.PlayerId][nextStageNum]
		end

		-- 只有当下一关已经预加载但我们还没到达时，才锁定它的空气墙
		if nextStageFolder then
			StageService.SetAirWallState(nextStageFolder, false)
		end
		-- 如果下一关还不存在，等OnStageClear时会正确设置
	end

	-- V2.0修复：使用递归搜索，支持IdleFloor在子文件夹中（如Stage001/StageNodes/IdleFloor）
	local targetIdleFloor = stageFolder:FindFirstChild("IdleFloor", true)
	if not targetIdleFloor then
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

			-- V2.7修复：行军前设置WalkSpeed为配置速度，避免速度与动画不匹配导致抖动
			local unitId = unitInstance:GetAttribute("UnitId") or unitData.UnitId or unitInstance.Name
			-- V2.7修复：确保unitId为字符串类型，避免Luau类型警告
			if unitId and type(unitId) ~= "string" then
				unitId = tostring(unitId)
			end
			local humanoid = unitInstance:FindFirstChild("Humanoid")
			if humanoid and unitId then
				-- V2.7修复：使用pcall保护GetMoveSpeed调用，避免Luau类型警告
				local UnitConfigModule = require(ReplicatedStorage.Config.UnitConfig)
				local success, configSpeed = pcall(function()
					return UnitConfigModule.GetMoveSpeed(unitId)
				end)
				if success and configSpeed and type(configSpeed) == "number" and configSpeed > 0 then
					humanoid.WalkSpeed = configSpeed
					DebugLog(string.format("⚡ %s 设置移动速度: %.1f", tostring(unitInstance.Name), configSpeed))
				else
					-- 如果无法获取配置速度，使用默认值
					local defaultSpeed = humanoid.WalkSpeed
					if defaultSpeed <= 0 then
						defaultSpeed = 16
					end
					humanoid.WalkSpeed = defaultSpeed
					DebugLog(string.format("⚡ %s 使用默认速度: %.1f", tostring(unitInstance.Name), defaultSpeed))
				end
			end

			-- V2.0修复：开始行军前，确保停止Show动画
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
		end
	end

	-- V2.3新增：行军阶段立即显示血条
	-- 收集要行军的单位并立即挂载血条，确保点击Attack后立刻切换显示
	local marchingUnits = {}
	for unitInstance, unitData in pairs(campaignData.Units) do
		if not unitData.IsDead and unitInstance and unitInstance.Parent then
			table.insert(marchingUnits, unitInstance)
		end
	end
	fireAttachHealthBars(marchingUnits)  -- 立即为行军单位挂载血条
	DebugLog(string.format("🎯 行军开始，已为 %d 个单位挂载血条", #marchingUnits))

	-- 调用PathService批量寻路（使用新的回调API）
	-- V2.3.1：移除缓存路径传入，让每个单位使用真实起点寻路
	DebugLog(string.format("[MarchToStage] 开始PathService寻路，共 %d 个目标", #moveTargets))
	local moveId = PathService.MoveUnitsToPositions(moveTargets, {
		onUnitArrived = function(unitInstance, status)
			-- 单位到达时的回调（可选，这里暂时不处理）
		end,

		onAllSettled = function(arrivedList, timedOutList, failedList)
			-- 所有单位完成移动后的回调
			DebugLog(string.format("[MarchToStage] PathService回调触发 - 到达:%d, 超时:%d, 失败:%d",
				#arrivedList, #timedOutList, #failedList))

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
			DebugLog("[MarchToStage] 即将调用BeginBattlePrep...")
			task.wait(0.1)  -- 给客户端缓冲
			CampaignManager.BeginBattlePrep(campaignData, stageNum, arrivedList, timedOutList, failedList)
		end
	})  -- V2.3.1：移除第三个参数cachedWaypoints

	-- V2.7修复：PathService启动后播放移动动画，避免循环依赖
	-- 延迟0.1秒确保路径请求已入队，避免动画先于路径计算播放导致卡顿
	task.delay(0.1, function()
		for unitInstance, unitData in pairs(campaignData.Units) do
			if not unitData.IsDead and unitInstance and unitInstance.Parent then
				UnitAI.PlayMoveAnimation(unitInstance)
			end
		end
		DebugLog(string.format("🎬 已为 %d 个单位播放移动动画", moveCount))
	end)

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
		end
	end

	-- V2.7修复：超时单位也视为失败，不应进入战斗（避免位置异常）
	for _, unitInstance in ipairs(timedOutList) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			unitData.IsDead = true
			DebugLog(string.format("⏰ %s 超时未到达，标记为失败不参与战斗", unitData.UnitId or unitInstance.Name))
		end
	end

	-- 只使用正常到达的单位
	local allArrivedUnits = {}
	for _, unit in ipairs(arrivedList) do
		table.insert(allArrivedUnits, unit)
	end
	-- V2.7修复：不再添加超时单位到战斗列表
	-- 原代码：
	-- for _, unit in ipairs(timedOutList) do
	--     table.insert(allArrivedUnits, unit)
	-- end

	-- 记录到达的单位，更新 campaignData
	for _, unitInstance in ipairs(allArrivedUnits) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
			if rootPart then
				unitData.LastKnownPosition = rootPart.Position
			end
		end
	end

	-- 准备友军：激活单位并准备进入战斗
	DebugLog(string.format("[BeginBattlePrep] 开始准备友军，共有 %d 个到达单位", #allArrivedUnits))
	local preparedAllies = {}

	for i, unitInstance in ipairs(allArrivedUnits) do
		local unitData = campaignData.Units[unitInstance]
		if unitData and not unitData.IsDead then
			DebugLog(string.format("  准备友军 %d/%d: %s", i, #allArrivedUnits, unitData.UnitId))

			-- V2.4新增：从MarchMode恢复到CombatMode（重新启用AI）
			if UnitAI.SetMode then
				local success = UnitAI.SetMode(unitInstance, "CombatMode")
				if success then
					DebugLog(string.format("    ⚔️  %s 进入战斗模式（AI已启用）", unitData.UnitId))
				else
					-- AI未启动，在战斗准备时是正常的，稍后会由UnitAI启动
					DebugLog(string.format("    ⚠️ %s AI未启动，稍后将在战斗中自动启动", unitData.UnitId))
				end
			end

			-- 1. 激活单位（解除锚定等）
			DebugLog(string.format("    正在激活单位 %s...", unitData.UnitId))
			local activated = CampaignUnitHelper.ActivateUnit(unitInstance)
			DebugLog(string.format("    激活结果: %s", activated and "成功" or "失败"))
			if activated then
				unitData.IsActivated = true
			end

			-- 2. 准备进入战斗（清理PathService残留、重置AI状态）
			DebugLog(string.format("    正在准备战斗 %s...", unitData.UnitId))
			local prepared = CampaignUnitHelper.PrepareForBattle(unitInstance)
			DebugLog(string.format("    战斗准备结果: %s", prepared and "成功" or "失败"))

			if activated and prepared then
				table.insert(preparedAllies, unitInstance)
				DebugLog(string.format("    ✅ %s 准备完成，加入友军列表", unitData.UnitId))
			end
		else
			if unitData then
				DebugLog(string.format("  跳过已死亡单位: %s", unitData.UnitId))
			end
		end
	end

	DebugLog(string.format("[BeginBattlePrep] 友军准备完成，成功准备 %d/%d 个单位", #preparedAllies, #allArrivedUnits))

	-- 获取并激活敌军
	-- V2.0.4修复：不重置空气墙状态,只读取关卡信息
	local stageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, stageNum, false)
	if not stageFolder then
		return CampaignManager.OnDefeat(campaignData)
	end

	-- 敌军激活
	local idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
	local preparedEnemies = {}

	if idleFloorEnemy then
		for _, child in ipairs(idleFloorEnemy:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChild("Humanoid") then
				-- V2.6修复：敌军使用"enemy"参数，设置为Enemies碰撞组
				local activated = CampaignUnitHelper.ActivateUnit(child, "enemy")
				if activated then
					table.insert(preparedEnemies, child)
				end
			end
		end
	end

	-- V2.3.2新增：敌军为0时的容错重试机制
	-- 如果初次激活敌军为空，尝试重新加载一次敌人配置
	if #preparedEnemies == 0 then
		-- 重新调用LoadEnemyData强制重新生成敌人
		StageService.LoadEnemyData(stageFolder, stageNum)
		task.wait(0.2)  -- 给生成一点时间

		-- 再次扫描IdleFloorEnemy并尝试激活
		idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
		preparedEnemies = {}
		if idleFloorEnemy then
			for _, child in ipairs(idleFloorEnemy:GetChildren()) do
				if child:IsA("Model") and child:FindFirstChild("Humanoid") then
					-- V2.6修复：敌军使用"enemy"参数
					local activated = CampaignUnitHelper.ActivateUnit(child, "enemy")
					if activated then
						table.insert(preparedEnemies, child)
					end
				end
			end
		end

		if #preparedEnemies > 0 then
		end
	end

	-- 检查是否可以开战
	DebugLog(string.format("[BeginBattlePrep] 战斗准备完成 - 友军:%d，敌军:%d", #preparedAllies, #preparedEnemies))

	-- 详细列出友军信息
	if #preparedAllies > 0 then
		DebugLog("[BeginBattlePrep] 友军列表:")
		for i, ally in ipairs(preparedAllies) do
			DebugLog(string.format("    %d. %s (Humanoid: %s)", i, ally.Name, ally:FindFirstChild("Humanoid") and "✓" or "✗"))
		end
	end

	-- 详细列出敌军信息
	if #preparedEnemies > 0 then
		DebugLog("[BeginBattlePrep] 敌军列表:")
		for i, enemy in ipairs(preparedEnemies) do
			DebugLog(string.format("    %d. %s (Humanoid: %s)", i, enemy.Name, enemy:FindFirstChild("Humanoid") and "✓" or "✗"))
		end
	end

	if #preparedAllies == 0 or #preparedEnemies == 0 then
		return CampaignManager.OnDefeat(campaignData)
	end

	-- V2.3新增：战斗准备阶段补齐敌我血条
	-- 确保友军血条（即使行军时已挂载，客户端有去重缓存）
	fireAttachHealthBars(preparedAllies)
	-- 为敌军也挂载血条（敌军之前未行军，需要在这里挂载）
	fireAttachHealthBars(preparedEnemies)
	DebugLog(string.format("🎯 战斗准备阶段，已补齐友军(%d)和敌军(%d)血条", #preparedAllies, #preparedEnemies))

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
	DebugLog(string.format("[StartStageBattle] 开始关卡 %d 战斗 - 友军:%d，敌军:%d", stageNum, #preparedAllies, #preparedEnemies))

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
	DebugLog("[StartStageBattle] 正在创建战斗实例...")
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

	if not battleId then
		return CampaignManager.OnDefeat(campaignData)
	end

	DebugLog(string.format("[StartStageBattle] 战斗实例创建成功，BattleId: %s", tostring(battleId)))

	-- 更新 LastBattleId
	for _, unitInstance in ipairs(preparedAllies) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			unitData.LastBattleId = battleId
		end
	end

	-- 开始战斗
	DebugLog("[StartStageBattle] 正在启动战斗...")
	local startResult = BattleManager.StartBattle(battleId)
	DebugLog(string.format("[StartStageBattle] 战斗启动结果: %s", tostring(startResult)))
end

--[[
战斗结束回调(V2.4扩展：支持结算界面)
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
@param result table - 战斗结果
]]
function CampaignManager.OnBattleEnd(campaignData, stageNum, result)
	DebugLog(string.format("🏁 OnBattleEnd被调用: stageNum=%d, Winner=%s",
		stageNum, tostring(result.Winner)))

	-- 保存兵种HP
	local aliveCount = 0
	local deadCount = 0
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent and unitInstance:FindFirstChild("Humanoid") then
			unitData.CurrentHP = unitInstance.Humanoid.Health
			if unitData.CurrentHP <= 0 then
				unitData.IsDead = true
				deadCount = deadCount + 1
			else
				aliveCount = aliveCount + 1
			end
		else
			unitData.IsDead = true
			deadCount = deadCount + 1
		end
	end

	DebugLog(string.format("📊 兵种状态统计: 存活=%d, 死亡=%d", aliveCount, deadCount))

	-- V2.4关键修改：暂存战斗结果，不立即处理，等待客户端确认
	campaignData.PendingBattleResult = {
		StageNum = stageNum,
		Winner = result.Winner,
		AliveCount = aliveCount,
		DeadCount = deadCount
	}

	DebugLog(string.format("⏳ OnBattleEnd暂存结果，等待客户端结算确认: Winner=%s", tostring(result.Winner)))
end

--[[
处理结算确认后的逻辑(V2.4新增)
@param campaignData table - 战役数据
]]
function CampaignManager.ProcessPendingBattleResult(campaignData)
	local pendingResult = campaignData.PendingBattleResult
	if not pendingResult then
		DebugLog("❌ ProcessPendingBattleResult: 没有待处理的战斗结果")
		return
	end

	DebugLog(string.format("🔄 ProcessPendingBattleResult: 开始处理结算确认后的逻辑, Winner=%s", tostring(pendingResult.Winner)))

	local stageNum = pendingResult.StageNum
	local winner = pendingResult.Winner

	-- 清除待处理结果
	campaignData.PendingBattleResult = nil

	-- V2.5修复：单关结束时不传送玩家，等整个战役结束后再传送
	-- 传送逻辑已移至 CompleteCampaignEnd

	-- 判定结果并继续原有逻辑
	if winner == "Attack" then
		-- 我方胜利
		DebugLog("🎉 我方胜利，推进下一关")
		CampaignManager.OnStageClear(campaignData, stageNum)
	else
		-- 我方失败
		DebugLog(string.format("💀 我方失败，战役结束 (Winner=%s)", tostring(winner)))
		-- 失败应立即弹出结算弹窗，不等待
		CampaignManager.OnDefeat(campaignData, { skipDelay = true })
	end
end

--[[
关卡完成
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
]]
function CampaignManager.OnStageClear(campaignData, stageNum)
	-- 检查玩家是否仍在线
	local playerId = campaignData.PlayerId
	local player = game.Players:GetPlayerByUserId(playerId)
	if not player then
		DebugLog("玩家已离线，跳过关卡清理:", playerId, "关卡:", stageNum)
		return  -- 直接返回，不处理离线玩家的任务
	end

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

	-- V2.0.4修复：获取下一关并解锁空气墙,不重置状态避免已解锁的被再次锁定
	local nextStageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, nextStage, false)
	if nextStageFolder then
		StageService.SetAirWallState(nextStageFolder, true)
	end

	-- 提前生成下下关（并保持其空气墙锁定）
	if nextStage + 1 <= campaignData.TotalStages then
		task.spawn(function()
			-- V2.0.4修复：生成新关卡时显式锁定空气墙
			local nextNextStageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, nextStage + 1, false)
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
@param options table? - 可选参数 {skipDelay=true} 跳过结算前等待（用于Restart/Retreat）
]]
function CampaignManager.OnDefeat(campaignData, options)
	options = options or {}
	DebugLog("💀 OnDefeat被调用 - 战役失败")
	campaignData.State = CampaignState.DEFEAT

	-- 通知客户端
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.DEFEAT, campaignData.CurrentStage)
		end
	end

	-- 结束战役
	local delaySeconds = options.skipDelay and 0 or 3
	DebugLog(string.format("⏰ OnDefeat等待%.1f秒后调用OnCampaignEnd", delaySeconds))
	if delaySeconds > 0 then
		task.wait(delaySeconds)
	end
	DebugLog("🔚 OnDefeat调用OnCampaignEnd(false)")
	CampaignManager.OnCampaignEnd(campaignData, false)
end

--[[
战役结束清理
@param campaignData table - 战役数据
@param isVictory boolean - 是否胜利
]]
function CampaignManager.OnCampaignEnd(campaignData, isVictory)
	DebugLog(string.format("🔚 OnCampaignEnd被调用: isVictory=%s", tostring(isVictory)))
	campaignData.State = CampaignState.CLEANUP

	-- V2.5新增：战役结束时发送结算弹窗
	-- 标记战役为待确认状态
	campaignData.IsWaitingForConfirm = true
	campaignData.IsVictory = isVictory

	-- 获取当前关卡信息
	local currentStage = campaignData.CurrentStage or 1
	local result = isVictory and "Attack" or "Defense"

	-- 发送VictoryPopup事件
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
		if battleEventsFolder then
			local victoryPopupEvent = battleEventsFolder:FindFirstChild("VictoryPopup")
			if victoryPopupEvent then
				-- 使用0作为battleId表示这是战役结算
				victoryPopupEvent:FireClient(campaignData.Player, 0, result, currentStage, nil)
				DebugLog(string.format("✅ 战役结算弹窗已发送: PlayerId=%d, Result=%s, Stage=%d",
					campaignData.PlayerId, result, currentStage))
			else
				warn(GameConfig.LOG_PREFIX, "[CampaignManager] VictoryPopup事件不存在，将在超时后自动完成战役结算")
				-- V2.5修复：不立即完成，依赖超时机制（10秒后自动完成）
			end
		end
	end

	-- V2.5新增：设置超时自动完成（防止客户端卡死）
	-- V2.5修复：延长超时时间到15秒，避免玩家看动画时被提前清理
	task.delay(15, function()
		if campaignData.IsWaitingForConfirm then
			warn(GameConfig.LOG_PREFIX, string.format("[CampaignManager] 战役结算超时（15秒），强制完成: PlayerId=%d", campaignData.PlayerId))
			CampaignManager.CompleteCampaignEnd(campaignData)
		end
	end)
end

--[[
完成战役结算（玩家确认后调用）
@param campaignData table - 战役数据
]]
function CampaignManager.CompleteCampaignEnd(campaignData)
	if not campaignData then
		warn(GameConfig.LOG_PREFIX, "[CampaignManager] CompleteCampaignEnd失败: campaignData无效")
		return
	end

	-- 防止重复调用
	if not campaignData.IsWaitingForConfirm then
		DebugLog("CompleteCampaignEnd跳过: 已完成或未在等待确认状态")
		return
	end

	campaignData.IsWaitingForConfirm = false
	DebugLog(string.format("🔚 CompleteCampaignEnd开始执行: PlayerId=%d", campaignData.PlayerId))

	-- V2.5新增：战役结束后传送玩家回出生点（从ProcessPendingBattleResult移动到此处）
	local player = campaignData.Player
	if player and player.Character then
		local homeId = campaignData.HomeId
		local homeFolder = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
		if homeFolder then
			local spawnLocation = homeFolder:FindFirstChild("SpawnLocation")
			if spawnLocation and player.Character:FindFirstChild("HumanoidRootPart") then
				DebugLog(string.format("📍 战役结束，传送玩家 %s 回出生点", player.Name))
				player.Character.HumanoidRootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
			end
		end
	end

	-- V2.0.1新增：关闭基地大门（确保门总是被关闭）
	pcall(function()
		DoorControlService.CloseDoor(campaignData.HomeId)
	end)

	-- V2.3性能优化：清理路径缓存
	ClearPathCache(campaignData.HomeId)

	-- V2.3新增：兜底血条清理，防止残留血条/隐藏的等级牌
	-- 如果战斗没创建就失败（OnDefeat/OnCampaignEnd 直接走复活），确保血条被移除
	local campaignUnits = {}
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance then -- 不检查Parent，因为单位可能已经移动或隐藏
			table.insert(campaignUnits, unitInstance)
		end
	end
	if #campaignUnits > 0 then
		fireDetachHealthBars(campaignUnits)
		DebugLog(string.format("🧹 战役结束兜底清理，已移除 %d 个单位的血条", #campaignUnits))
	end

	-- 重生兵种
	DebugLog("🔄 CompleteCampaignEnd调用RespawnUnits")
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

	-- V2.6新增：禁用战斗状态视觉效果（粒子特效和战斗中提示）
	SetHomeFightingEffect(campaignData.HomeId, false)

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

	DebugLog(string.format("✅ 战役结算完成: PlayerId=%d", campaignData.PlayerId))
end

--[[
恢复单位的动画和Humanoid状态（V2.0.2 完全重制版）
专门用于战役重生后立即重置状态，确保单位能正确站立
@param unitModel Model - 单位模型
@param unitId string - 单位ID（用于日志）
]]
local function RestoreUnitAnimationState(unitModel, unitId)
	if not unitModel then
		return
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		DebugLog(string.format("    ❌ %s 没有找到Humanoid", unitId))
		return
	end

	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		DebugLog(string.format("    ❌ %s 没有找到HumanoidRootPart", unitId))
		return
	end

	DebugLog(string.format("    🔧 开始重置 %s 状态", unitId))

	-- 1. 重建Animator（关键修复：删除失效的旧Animator）
	local oldAnimator = humanoid:FindFirstChild("Animator")
	if oldAnimator then
		oldAnimator:Destroy()
		DebugLog(string.format("    🔧 %s 删除旧Animator", unitId))
	end

	-- 创建全新的Animator
	local newAnimator = Instance.new("Animator")
	newAnimator.Parent = humanoid
	DebugLog(string.format("    🔧 %s 创建新Animator", unitId))

	-- 2. 立即重置Humanoid核心状态
	pcall(function()
		-- 防止关节破碎
		humanoid.BreakJointsOnDeath = false
		-- 退出死亡/倒地状态
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid.AutoRotate = true

		-- 清零速度
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		DebugLog(string.format("    🔧 %s Humanoid属性已重置", unitId))
	end)

	-- 3. 强制状态切换：Physics → Running
	pcall(function()
		-- 先切换到Physics确保干净过渡
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		task.wait() -- 等待一帧确保状态更新
		-- 再切换到Running，单位会立即站起
		humanoid:ChangeState(Enum.HumanoidStateType.Running)

		DebugLog(string.format("    🔧 %s 状态已切换到Running", unitId))
	end)

	-- 4. 重启Animate脚本
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if (descendant:IsA("Script") or descendant:IsA("LocalScript")) and descendant.Name == "Animate" then
			pcall(function()
				descendant.Disabled = true
				task.wait() -- 短暂等待确保脚本停止
				descendant.Disabled = false
				DebugLog(string.format("    🔧 %s Animate脚本已重启", unitId))
			end)
		end
	end

	-- 5. 重置骨骼位置（新Animator不需要清理残留动画）
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			pcall(function()
				descendant.Transform = CFrame.new()
			end)
		end
	end

	DebugLog(string.format("    ✅ %s 状态重置完成（新Animator已创建）", unitId))
end

--[[
播放展示动画 (修复复生后没有动画的问题)
@param unitModel Model - 兵种模型
@param unitId string - 兵种ID
]]
local function PlayShowAnimation(unitModel, unitId)
	if not unitModel or not unitId then
		return
	end
	-- 1. 确保Humanoid处于正确状态
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	-- 2. 强制确保Humanoid状态正确
	pcall(function()
		-- 确保不是Physics状态，否则动画可能不更新
		if humanoid:GetState() == Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end)
	-- 3. 获取动画ID
	local UnitConfig = require(ReplicatedStorage.Config.UnitConfig)
	local animId = UnitConfig.GetShowAnimationId(unitId)
	if not animId or animId == "" or animId == "0" then
		animId = UnitConfig.GetIdleAnimationId(unitId)
	end
	if not animId or animId == "" or animId == "0" then
		return
	end
	-- 4. 获取Animator
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	-- 5. 加载并播放动画
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animId
	local success, track = pcall(function()
		-- 清理当前正在播放的轨道，避免混杂
		for _, oldTrack in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function()
				oldTrack:Stop(0.1) -- 给一点点淡出时间
			end)
		end
		return animator:LoadAnimation(animation)
	end)
	if success and track then
		--  关键修复1：使用Idle优先级，行军/战斗时可被覆盖
		track.Priority = Enum.AnimationPriority.Idle
		track.Looped = true

		--  关键修复2：不要立即销毁Animation对象，而是绑定到Stopped事件
		-- 如果立即Destroy，循环动画会失效或卡住
		track.Stopped:Connect(function()
			if animation then
				animation:Destroy()
			end
		end)

		track:Play(0.1) -- 0.1秒淡入

		-- 修复：确保unitId不为nil
		DebugLog(string.format("   [CampaignManager] 已为 %s 重新播放展示动画 (Priority=Action4, Looped=true)", tostring(unitId)))
	else
		warn("复生动画加载失败:", unitId)
		if animation then
			animation:Destroy()
		end
	end
end

--[[
重生兵种到基地
@param campaignData table - 战役数据
]]
function CampaignManager.RespawnUnits(campaignData)
	local homeIdleFloor = GetHomeIdleFloor(campaignData.HomeId)
	if not homeIdleFloor then
		DebugLog("❌ RespawnUnits失败: 未找到基地IdleFloor，HomeId =", campaignData.HomeId)
		return
	end

	local totalUnits = 0
	for _ in pairs(campaignData.Units) do
		totalUnits = totalUnits + 1
	end

	DebugLog(string.format("🔄 开始复生单位，HomeId = %d，共 %d 个单位",
		campaignData.HomeId,
		totalUnits))

	local respawnCount = 0
	local failCount = 0

	-- V2.0.1修复：支持重生死亡隐藏的单位
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance then
			DebugLog(string.format("  🔍 检查单位: %s (IsDead=%s, Parent=%s)",
				unitData.UnitId,
				tostring(unitData.IsDead),
				tostring(unitInstance.Parent ~= nil)))

			-- V2.0.3修复：检查单位是否已被销毁（避免Parent locked错误）
			-- 如果实例已经被Destroy()，跳过该单位
			if not unitInstance:IsDescendantOf(game) and unitInstance.Parent == nil then
				-- 检查是否真的被销毁了（Parent locked状态）
				local success = pcall(function()
					local _ = unitInstance.Name  -- 尝试访问属性
				end)
				if not success then
					DebugLog(string.format("    ⚠️  %s 已被彻底销毁，跳过", unitData.UnitId))
					failCount = failCount + 1
					continue
				end
			end

			-- V2.0.3修复：如果单位被隐藏（Parent = nil），重新挂回基地根节点（PlayerHome）
			-- 🔥 使用SafeSetParent防止Parent locked错误
			if not unitInstance.Parent then
				DebugLog(string.format("    📌 %s 当前被隐藏，尝试重新挂载...", unitData.UnitId))
				local homeFolder = homeIdleFloor.Parent
				local targetParent = homeFolder or Workspace

				-- V2.6修复：使用增强的SafeSetParent
				local mountSuccess = SafeSetParent(unitInstance, targetParent)

				if homeFolder then
					DebugLog(string.format("      ✅ 正在挂载到 %s", homeFolder.Name))
				else
					DebugLog(string.format("      ⚠️  HomeFolder不存在，挂载到Workspace"))
				end

				-- 再次验证是否成功挂载
				if not mountSuccess or not unitInstance.Parent then
					DebugLog(string.format("    ❌ %s 挂载失败: Parent仍为nil", unitData.UnitId))
					failCount = failCount + 1
					continue
				end

				DebugLog(string.format("      ✅ %s 挂载成功", unitData.UnitId))
			end

			-- 计算原位置（使用基地IdleFloor进行坐标换算）
			local targetCFrame = GridPositionSystem.GridToWorld(
				homeIdleFloor,
				unitData.GridPos
			)

			if not targetCFrame then
				DebugLog(string.format("    ❌ %s GridPos无效，无法计算目标坐标", unitData.UnitId))
				failCount = failCount + 1
				continue
			end

			-- 修复Y坐标：使用与GridPositionSystem相同的算法
			-- 参考GridPositionSystem.lua:100行的Y坐标计算
			local Y_OFFSET = 3  -- 与GridPositionSystem保持一致
			local correctedY = homeIdleFloor.Position.Y + (homeIdleFloor.Size.Y / 2) + Y_OFFSET
			local correctedCFrame = CFrame.new(
				targetCFrame.Position.X,
				correctedY,  -- 使用与放置系统相同的Y计算方式
				targetCFrame.Position.Z
			) * targetCFrame.Rotation

			DebugLog(string.format("    📍 传送 %s 到坐标 (%.1f, %.3f, %.1f) [Y修正: %.3f→%.3f]",
				unitData.UnitId,
				correctedCFrame.Position.X,
				correctedCFrame.Position.Y,
				correctedCFrame.Position.Z,
				targetCFrame.Position.Y,
				correctedCFrame.Position.Y))

			-- 根据单位整体包围盒修正Y：使用模型extents高度的一半放置在地板之上，避免大体型插地
			local extentsY = unitInstance:GetExtentsSize().Y
			local halfHeight = extentsY * 0.5
			local floorTopY = homeIdleFloor.Position.Y + (homeIdleFloor.Size.Y / 2)
			local yLift = math.max(halfHeight, floorTopY + Y_OFFSET - floorTopY)

			-- 将目标Y设置为地板顶面 + yLift
			local groundedPos = Vector3.new(
				correctedCFrame.Position.X,
				floorTopY + yLift,
				correctedCFrame.Position.Z
			)
			local groundedCFrame = CFrame.new(groundedPos) * correctedCFrame.Rotation

			-- 传送回去（使用体型修正后的坐标，优先PivotTo避免PrimaryPart尺度误差）
			local teleportSuccess = false
			pcall(function()
				if unitInstance.PivotTo then
					unitInstance:PivotTo(groundedCFrame)
					teleportSuccess = true
				elseif unitInstance.PrimaryPart then
					unitInstance:SetPrimaryPartCFrame(groundedCFrame)
					teleportSuccess = true
				elseif unitInstance:FindFirstChild("HumanoidRootPart") then
					unitInstance.HumanoidRootPart.CFrame = groundedCFrame
					teleportSuccess = true
				end
			end)

			if not teleportSuccess then
				DebugLog(string.format("    ❌ %s 没有PrimaryPart或HumanoidRootPart，无法传送", unitData.UnitId))
				failCount = failCount + 1
				continue
			end

			-- 验证传送结果
			local actualPos = nil
			if unitInstance.PrimaryPart then
				actualPos = unitInstance.PrimaryPart.Position
			elseif unitInstance:FindFirstChild("HumanoidRootPart") then
				actualPos = unitInstance.HumanoidRootPart.Position
			end

			if actualPos then
				DebugLog(string.format("    ✅ 传送完成，实际位置: (%.1f, %.1f, %.1f)",
					actualPos.X, actualPos.Y, actualPos.Z))
			end

			-- 验证Parent和可见性
			DebugLog(string.format("    🔍 传送后状态: Parent=%s, PrimaryPart=%s",
				tostring(unitInstance.Parent and unitInstance.Parent.Name),
				tostring(unitInstance.PrimaryPart ~= nil)))

			-- 关键顺序调整：先解锚，让 Humanoid/Motor6D 能拉起姿态，再重置状态和动画
			SetUnitAnchored(unitInstance, false)
			DebugLog(string.format("    🔓 %s 先解锚，允许动画拉回站姿", unitData.UnitId))

			-- V2.0.2修复：立即重置状态，防止在未锚定状态下摔倒
			-- 先重置Humanoid状态，再处理其他
			DebugLog(string.format("    🎭 立即重置 %s 的动画状态", unitData.UnitId))
			RestoreUnitAnimationState(unitInstance, unitData.UnitId)

			-- 恢复满血
			if unitInstance:FindFirstChild("Humanoid") then
				unitInstance.Humanoid.Health = unitData.MaxHP
				DebugLog(string.format("    ❤️  %s 血量恢复至 %d", unitData.UnitId, unitData.MaxHP))
			end

			-- V2.3新增: 复活后移除血条，恢复等级显示
			-- 通知客户端移除该单位的血条
			local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
			if eventsFolder then
				local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
				if battleEventsFolder then
					local detachHealthBarsEvent = battleEventsFolder:FindFirstChild("DetachHealthBars")
					if detachHealthBarsEvent then
						detachHealthBarsEvent:FireAllClients({unitInstance})
						DebugLog(string.format("    🏷️  %s 移除血条，恢复等级显示", unitData.UnitId))
					end
				end
			end

			-- 复活标记
			unitData.IsDead = false
			unitData.CurrentHP = unitData.MaxHP

			-- 播放特效
			DebugLog(string.format("    ✨ 为 %s 播放复生特效", unitData.UnitId))
			PlayRespawnEffect(unitInstance, unitData.GridSize)

			-- ==========================================
			-- ⭐⭐【新增代码】复活后立即播放展示动画 ⭐⭐
			-- ==========================================
			-- 立即播放展示动画，因为状态已经正确重置
			PlayShowAnimation(unitInstance, unitData.UnitId)
			DebugLog(string.format("    🎭 %s 开始播放展示动画", unitData.UnitId))
			-- ==========================================

			-- 延迟锚定：给动画一帧时间拉直姿态，避免躺倒被锁定
			if unitData.WasAnchored then
				task.delay(0.1, function()
					if unitInstance and unitInstance.Parent then
						-- V2.1修复：使用展示模式锚定，只锚定HRP让动画能正常播放
						SetUnitAnchored(unitInstance, true, true)  -- 第三个参数true=展示模式
						DebugLog(string.format("    🔒 %s 延迟锚定完成（展示模式）", unitData.UnitId))
						-- 锚定后再确保展示动画处于播放状态（防止状态切换/锚定打断播放）
						PlayShowAnimation(unitInstance, unitData.UnitId)
					end
				end)
			end

			-- V2.0.3修复：不要在这里清除CampaignKeepInstance
			-- 保持该标记直到战役彻底结束（在OnCampaignEnd中统一清除）
			-- 这样多关卡战斗中单位死亡后不会被Destroy()

			respawnCount = respawnCount + 1
			DebugLog(string.format("    ✅ %s 复生成功", unitData.UnitId))
		end
	end

	DebugLog(string.format("🎉 单位复生完成: 成功 %d，失败 %d", respawnCount, failCount))
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

	-- Restart/Retreat：立刻弹出结算框，不等待
	CampaignManager.OnDefeat(campaignData, { skipDelay = true })
end

--[[
初始化CampaignManager
]]
function CampaignManager.Initialize()
	-- 初始化远程事件
	if not InitializeEvents() then
		return false
	end

	-- 连接事件
	local requestStart = CampaignEvents:FindFirstChild("RequestStartCampaign")
	if requestStart then
		requestStart.OnServerEvent:Connect(function(player)
			local success, err = pcall(function()
				CampaignManager.StartCampaign(player)
			end)

		end)
	end

	local requestRetreat = CampaignEvents:FindFirstChild("RequestRetreat")
	if requestRetreat then
		requestRetreat.OnServerEvent:Connect(function(player)
			local success, err = pcall(function()
				CampaignManager.RequestRetreat(player)
			end)

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
