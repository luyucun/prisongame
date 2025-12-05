--[[
=====================================================
脚本名称: CampaignManager
脚本类型: ModuleScript (服务端核心)
脚本位置: ServerScriptService/Systems/CampaignManager.lua
版本: V2.8.4 (修复复生半透明问题)
=====================================================

功能描述:
- 管理玩家的战役流程
- 协调单位行军、战斗、胜利和关卡切换
- 处理胜利/失败/清理逻辑
- 管理单位血条继承
- V2.8新增: 章节系统支持

状态机:
IDLE → PREPARING → MARCHING → FIGHTING → STAGE_CLEAR/DEFEAT → CLEANUP → IDLE

]]

local CampaignManager = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- 引用配置模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript)
local StageConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StageConfig") :: ModuleScript)
local PlacementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PlacementConfig") :: ModuleScript)
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig") :: ModuleScript)

-- 引用核心管理器
local PlayerManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("PlayerManager") :: ModuleScript)
local DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager") :: ModuleScript)  -- V2.8新增

-- 引用系统模块
local SystemsFolder = ServerScriptService:WaitForChild("Systems")
local GridPositionSystem = require(SystemsFolder:WaitForChild("GridPositionSystem") :: ModuleScript)
local StageService = require(SystemsFolder:WaitForChild("StageService") :: ModuleScript)
local PathService = require(SystemsFolder:WaitForChild("PathService") :: ModuleScript)
local BattleManager = require(SystemsFolder:WaitForChild("BattleManager") :: ModuleScript)
local CurrencySystem = require(SystemsFolder:WaitForChild("CurrencySystem") :: ModuleScript)
local UnitAI = require(SystemsFolder:WaitForChild("UnitAI") :: ModuleScript)
local CampaignUnitHelper = require(SystemsFolder:WaitForChild("CampaignUnitHelper") :: ModuleScript)
local DoorControlService = require(SystemsFolder:WaitForChild("DoorControlService") :: ModuleScript)

-- 远程事件引用
local CampaignEvents = nil

-- 战役状态枚举
local CampaignState = {
	IDLE = "Idle",
	PREPARING = "Preparing",
	MARCHING = "Marching",
	PREPARE_BATTLE = "PrepareBattle",
	FIGHTING = "Fighting",
	STAGE_CLEAR = "StageClear",
	VICTORY = "Victory",
	DEFEAT = "Defeat",
	CLEANUP = "Cleanup"
}

-- 活跃战役数据: [playerId] = CampaignData
CampaignManager.ActiveCampaigns = {}

-- 路径缓存优化: [homeId][stageNum] = {waypoints = {Vector3}, expiryTime = number}
local pathCache = {}

-- 路径缓存过期时间(秒)
local PATH_CACHE_EXPIRY = 300

-- ==================== 日志函数 ====================

local function DebugLog(...)
	if GameConfig.Campaign.EnablePathDebugLogs or GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "[CampaignManager]", ...)
	end
end

-- ==================== 私有函数 ====================

--[[
获取缓存的路径
@param homeId number - 家园ID
@param stageNum number - 关卡编号
@return {Vector3}|nil - 缓存的路径点列表，未缓存或已过期则返回nil
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
		pathCache[homeId][stageNum] = nil
		return nil
	end

	return cacheEntry.waypoints
end

--[[
存储路径到缓存
@param homeId number - 家园ID
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
清除指定家园的路径缓存
@param homeId number - 家园ID
]]
local function ClearPathCache(homeId)
	if pathCache[homeId] then
		pathCache[homeId] = nil
	end
end

--[[
安全设置Parent,处理Locked情况
@param instance Instance - 要设置的实例
@param newParent Instance - 新的父级
@return boolean - 是否设置成功
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

	-- 如果已经在正确的Parent下,直接返回成功
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

	-- 失败后等待一帧重试
	task.wait()
	success = pcall(function()
		instance.Parent = newParent
	end)
	if success then
		return true
	end

	-- 使用defer延迟设置
	task.defer(function()
		pcall(function()
			instance.Parent = newParent
		end)
	end)

	-- 等待一下看是否成功
	task.wait(0.1)
	return instance.Parent == newParent
end

--[[
强制将物理权限设置给服务器
@param model Model - 单位模型
]]
local function SetNetworkOwnerToServer(model)
	if not model then return end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part:CanSetNetworkOwnership() then
			-- 设置网络所有权为nil表示由服务器控制
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end
end

--[[
设置单位的锚定状态
@param unitModel Model - 单位模型
@param anchored boolean - 是否锚定
@param displayMode boolean - 展示模式(true=仅锚定HRP, false/nil=全身锚定)
]]
local function SetUnitAnchored(unitModel, anchored, displayMode)
	if not unitModel then
		return
	end

	-- 展示模式:仅锚定HumanoidRootPart,其他部位不锚定以保持Motor6D动画
	if displayMode and anchored then
		local humanoidRootPart = unitModel:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			humanoidRootPart.Anchored = true
			humanoidRootPart.CanCollide = true
		end

		-- 其他部位取消锚定
		for _, descendant in ipairs(unitModel:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
				descendant.Anchored = false
				descendant.CanCollide = false
			end
		end

		return
	end

	-- 下半身部位定义(需要启用碰撞以支持行走)
	local lowerBodyParts = {
		"LeftFoot", "RightFoot",
		"LeftLowerLeg", "RightLowerLeg",
		"LowerTorso",
		"Left Leg", "Right Leg",
	}

	-- 构建下半身部位集合
	local lowerBodySet = {}
	for _, name in ipairs(lowerBodyParts) do
		lowerBodySet[name] = true
	end

	-- 遍历所有BasePart设置锚定和碰撞
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored

			-- HumanoidRootPart和下半身启用碰撞
			if descendant.Name == "HumanoidRootPart" or lowerBodySet[descendant.Name] then
				descendant.CanCollide = true
			else
				descendant.CanCollide = false
			end
		end
	end

	-- 解除锚定时配置物理碰撞组
	if not anchored then
		local PhysicsManager = ServerScriptService.Systems:FindFirstChild("PhysicsManager")
		if PhysicsManager then
			local PhysicsModule = require(PhysicsManager)
			pcall(function()
				PhysicsModule.ConfigureUnitPhysics(unitModel, "ally")
			end)
		end

		-- 强制设置网络所有权为服务器
		SetNetworkOwnerToServer(unitModel)
	end

	-- 设置Humanoid状态
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		if not anchored then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		else
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

--[[
初始化远程事件
@return boolean - 是否初始化成功
]]
local function InitializeEvents()
	if not CampaignEvents then
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			CampaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
		end

		if not CampaignEvents then
			-- 未找到CampaignEvents
		end
	end
	return CampaignEvents ~= nil
end

--[[
发送附加血条事件到客户端
@param units table - 单位模型列表
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
		DebugLog(string.format("✅ 广播附加血条，单位数量: %d", #send))
	end
end

--[[
发送移除血条事件到客户端
@param units table - 单位模型列表
]]
local function fireDetachHealthBars(units)
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
		DebugLog(string.format("✅ 广播移除血条，单位数量: %d", #send))
	end
end

--[[
获取家园的IdleFloor
@param homeId number - 家园ID
@return Part|nil - IdleFloor部件
说明: 优先查找根目录下的IdleFloor,如果找不到则在Stage文件夹下递归查找
]]
local function GetHomeIdleFloor(homeId)
	local homeFolder = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
	if not homeFolder then
		return nil
	end

	-- 优先查找根目录下的IdleFloor
	local homeIdleFloor = homeFolder:FindFirstChild("IdleFloor", false)
	if homeIdleFloor then
		return homeIdleFloor
	end

	-- 如果根目录没找到,则在非Stage子文件夹中递归查找
	for _, child in ipairs(homeFolder:GetChildren()) do
		-- 跳过Stage文件夹
		if child:IsA("Folder") and child.Name:match("^Stage") then
			continue
		end

		-- 在其他子文件夹中递归查找IdleFloor
		local found = child:FindFirstChild("IdleFloor", true)
		if found then
			return found
		end
	end

	return nil
end

--[[
锁定/解锁家园操作
@param player Player - 玩家
@param locked boolean - 是否锁定
]]
local function LockHomeOperations(player, locked)
	-- 通过RemoteEvent通知客户端锁定/解锁家园操作
	if InitializeEvents() then
		local lockEvent = CampaignEvents:FindFirstChild("LockHomeOperations")
		if lockEvent then
			lockEvent:FireClient(player, locked)
		end
	end
end

--[[
获取指挥点位置
@param homeId number - 家园ID
@return Part|nil - CommandPart部件
]]
local function GetCommandPart(homeId)
	local homeFolder = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
	if not homeFolder then
		return nil
	end

	local commandPart = homeFolder:FindFirstChild("CommandPart") or homeFolder:FindFirstChild("CommandPart", true)
	if commandPart and commandPart:IsA("BasePart") then
		return commandPart
	end
	return nil
end

--[[
锁定玩家移动能力
@param campaignData table - 战役数据
]]
local function LockPlayerMovement(campaignData)
	if not campaignData or campaignData.PlayerMoveBackup then
		return
	end

	local player = campaignData.Player
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- 备份玩家原始移动设置
	campaignData.PlayerMoveBackup = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
	}

	-- 限制玩家跳跃
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = true

	-- 设置指挥模式标记
	if player then
		player:SetAttribute("CommandMode", true)
	end
end

--[[
恢复玩家移动能力
@param campaignData table - 战役数据
]]
local function RestorePlayerMovement(campaignData)
	local backup = campaignData and campaignData.PlayerMoveBackup
	if not backup then
		return
	end

	local player = campaignData.Player
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		if backup.WalkSpeed then humanoid.WalkSpeed = backup.WalkSpeed end
		if backup.JumpPower then humanoid.JumpPower = backup.JumpPower end
		if backup.JumpHeight then humanoid.JumpHeight = backup.JumpHeight end
		if backup.AutoRotate ~= nil then humanoid.AutoRotate = backup.AutoRotate end
	end

	-- 清除指挥模式标记
	if player then
		player:SetAttribute("CommandMode", false)
	end

	campaignData.PlayerMoveBackup = nil
end

--[[
传送玩家到指挥点
@param campaignData table - 战役数据
]]
local function TeleportPlayerToCommandPart(campaignData)
	if not campaignData then
		return
	end

	local player = campaignData.Player
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return
	end

	local commandPart = GetCommandPart(campaignData.HomeId)
	if not commandPart then
		return
	end

	-- 计算传送位置(考虑角色高度)
	local yOffset = (commandPart.Size.Y * 0.5) + (humanoid.HipHeight or 2)
	hrp.CFrame = commandPart.CFrame + Vector3.new(0, yOffset, 0)
end

--[[
设置家园战斗特效
@param homeId number - 家园ID
@param isFighting boolean - 是否处于战斗中
说明:
- 控制家园IdleFloor上Fighting Part的特效显示
- isFighting=true时显示ParticleEmitter和BillboardGui,并生成RedLine边界
- isFighting=false时隐藏特效并移除RedLine
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

	-- 控制ParticleEmitter的Enabled属性
	local particleEmitter = fightingPart:FindFirstChild("ParticleEmitter")
	if particleEmitter and particleEmitter:IsA("ParticleEmitter") then
		particleEmitter.Enabled = isFighting
		DebugLog(string.format("  ✅ ParticleEmitter.Enabled = %s", tostring(isFighting)))
	else
		DebugLog(string.format("  ⚠ 未找到ParticleEmitter, HomeId=%d", homeId))
	end

	-- 控制BillboardGui的Enabled属性
	local billboardGui = fightingPart:FindFirstChild("Fighting")
	if billboardGui and billboardGui:IsA("BillboardGui") then
		billboardGui.Enabled = isFighting
		DebugLog(string.format("  ✅ BillboardGui.Enabled = %s", tostring(isFighting)))
	else
		DebugLog(string.format("  ⚠ 未找到Fighting BillboardGui, HomeId=%d", homeId))
	end

	-- 处理RedLine边界显示
	local redLineName = "RedLine_Home" .. homeId

	if isFighting then
		-- 战斗开始时生成RedLine覆盖到IdleFloor上
		local redLineTemplate = ReplicatedStorage:FindFirstChild("RedLine")
		if redLineTemplate and redLineTemplate:IsA("BasePart") then
			-- 检查是否已经存在RedLine
			local existingRedLine = idleFloor:FindFirstChild(redLineName)
			if not existingRedLine then
				local redLineClone = redLineTemplate:Clone()
				redLineClone.Name = redLineName

				-- 设置大小和位置与IdleFloor对齐
				redLineClone.Size = Vector3.new(idleFloor.Size.X, redLineTemplate.Size.Y, idleFloor.Size.Z)
				redLineClone.CFrame = CFrame.new(
					idleFloor.Position.X,
					idleFloor.Position.Y + (idleFloor.Size.Y / 2) + (redLineClone.Size.Y / 2) + 0.01,
					idleFloor.Position.Z
				)

				-- 设置物理属性
				redLineClone.CanCollide = false
				redLineClone.Anchored = true

				redLineClone.Parent = idleFloor
				DebugLog(string.format("  ✅ RedLine已生成并挂载到IdleFloor, HomeId=%d", homeId))
			else
				DebugLog(string.format("  ℹ RedLine已经存在，跳过生成, HomeId=%d", homeId))
			end
		else
			DebugLog(string.format("  ⚠ ReplicatedStorage中未找到RedLine模板, HomeId=%d", homeId))
		end
	else
		-- 战斗结束时移除RedLine
		local existingRedLine = idleFloor:FindFirstChild(redLineName)
		if existingRedLine then
			existingRedLine:Destroy()
			DebugLog(string.format("  ✅ RedLine已移除, HomeId=%d", homeId))
		end
	end

	DebugLog(string.format("✅ SetHomeFightingEffect完成: HomeId=%d, isFighting=%s", homeId, tostring(isFighting)))
end

--[[
播放重生特效
@param unitInstance Model - 单位实例
@param gridSize number - 格子大小(1/2/3)
]]
local function PlayRespawnEffect(unitInstance, gridSize)
	local effectName = "Merge0" .. gridSize -- Merge01/Merge02/Merge03
	local effectFolder = ReplicatedStorage:FindFirstChild("Effect")

	if not effectFolder then
		return
	end

	local effect = effectFolder:FindFirstChild(effectName)
	if effect and unitInstance.PrimaryPart then
		local clone = effect:Clone()
		clone.CFrame = unitInstance.PrimaryPart.CFrame
		clone.Parent = Workspace

		-- 定时清理特效
		task.delay(GameConfig.Campaign.RespawnEffectDuration, function()
			if clone and clone.Parent then
				clone:Destroy()
			end
		end)
	end
end

-- ==================== V3.4新增: 前进金币计算函数 ====================

--[[
计算战场中心位置(所有存活友军单位的质心)
@param campaignData table - 战役数据
@return Vector3|nil - 战场中心位置，无存活单位返回nil
]]
local function CalculateBattleCenter(campaignData)
	if not campaignData or not campaignData.Units then
		return nil
	end

	local totalPosition = Vector3.zero
	local aliveCount = 0

	for unitInstance, unitData in pairs(campaignData.Units) do
		if not unitData.IsDead and unitInstance and unitInstance.Parent then
			local rootPart = unitInstance:FindFirstChild("HumanoidRootPart")
			if rootPart then
				totalPosition = totalPosition + rootPart.Position
				aliveCount = aliveCount + 1
			end
		end
	end

	if aliveCount == 0 then
		return nil
	end

	return totalPosition / aliveCount
end

--[[
检查并发放前进金币
V3.4新增: 战场中心每前进AdvanceDistance studs获得AdvanceReward金币
只计算前进(Z轴负方向)，不计算后退
@param campaignData table - 战役数据
]]
local function CheckAndRewardAdvanceCoins(campaignData)
	if not campaignData or not campaignData.Player then
		return
	end

	-- 计算当前战场中心
	local battleCenter = CalculateBattleCenter(campaignData)
	if not battleCenter then
		return
	end

	local currentZ = battleCenter.Z
	local startZ = campaignData.StartZPosition

	-- 注意: 在Roblox中，前进通常是Z轴负方向
	-- 所以前进距离 = startZ - currentZ (当currentZ比startZ更小时表示前进了)
	local advancedDistance = startZ - currentZ

	-- 只有前进才计算，后退不计算
	if advancedDistance <= 0 then
		return
	end

	-- 检查是否创造了新的最远前进距离
	local previousMaxZ = campaignData.MaxAdvancedZ
	local previousAdvancedDistance = startZ - previousMaxZ

	-- 如果没有超过之前的最远距离，不发放金币
	if currentZ >= previousMaxZ then
		return
	end

	-- 更新最远前进距离
	campaignData.MaxAdvancedZ = currentZ

	-- 计算应该获得的金币奖励次数
	local advanceDistanceConfig = GameConfig.BattleCoin.AdvanceDistance
	local advanceRewardConfig = GameConfig.BattleCoin.AdvanceReward

	-- 计算从起点开始的累计前进距离
	local currentTotalAdvance = startZ - currentZ
	local lastRewardedDistance = campaignData.LastRewardedDistance or 0

	-- 计算新获得奖励的次数
	local currentRewardCount = math.floor(currentTotalAdvance / advanceDistanceConfig)
	local lastRewardCount = math.floor(lastRewardedDistance / advanceDistanceConfig)
	local newRewardCount = currentRewardCount - lastRewardCount

	if newRewardCount > 0 then
		local totalReward = newRewardCount * advanceRewardConfig

		-- V3.4.1修改：使用AddCoinsFromBattle触发金币表现效果
		CurrencySystem.AddCoinsFromBattle(campaignData.Player, totalReward, campaignData.CurrentStage)

		-- 更新上次获得奖励时的距离
		campaignData.LastRewardedDistance = currentRewardCount * advanceDistanceConfig

		DebugLog(string.format("[V3.4] 前进金币: 玩家 %s 前进了 %.1f studs，获得 %d 金币 (累计前进: %.1f)",
			campaignData.Player.Name, currentTotalAdvance - lastRewardedDistance, totalReward, currentTotalAdvance))
	end
end

-- ==================== 公共接口 ====================

--[[
开始战役
@param player Player - 玩家
@return boolean - 是否成功启动
]]
function CampaignManager.StartCampaign(player)
	local playerId = player.UserId

	-- 检查是否已有战役
	if CampaignManager.ActiveCampaigns[playerId] then
		return false
	end

	-- 获取玩家HomeId
	local homeId = PlayerManager.GetPlayerHomeId(player)
	if not homeId then
		return false
	end

	-- 重启/重新开战前，彻底清理旧的关卡缓存与路径缓存，避免复用上一次关卡的空气墙/敌人状态
	StageService.CleanupStages(playerId)
	ClearPathCache(homeId)

	-- [修复步骤 1]：清理后等待一帧，确保物理引擎处理完 Destroy
	task.wait()

	-- 获取PlacementSystem中已放置的单位
	local placementModule = SystemsFolder:FindFirstChild("PlacementSystem")
	if not placementModule then
		warn("[CampaignManager] 未找到PlacementSystem模块")
		return false
	end
	local PlacementSystem = require(placementModule :: ModuleScript)
	local placedUnits = PlacementSystem.GetPlacedUnitModels(player)

	if not placedUnits or #placedUnits == 0 then
		return false
	end

	-- V2.8新增: 获取玩家当前章节信息
	local currentChapter = DataManager.GetCurrentChapter(player)
	local chapterConfig = StageConfig.GetChapterConfig(currentChapter)
	local totalStagesInChapter = chapterConfig and chapterConfig.StagesPerChapter or GameConfig.Campaign.MaxStages

	DebugLog(string.format("[StartCampaign] 玩家 %s 开始章节 %d，关卡数: %d",
		player.Name, currentChapter, totalStagesInChapter))

	-- V3.4新增: 获取CommandPart作为前进金币计算的起点
	local commandPart = GetCommandPart(homeId)
	local startZPosition = commandPart and commandPart.Position.Z or 0

	-- 初始化战役数据
	local campaignData = {
		PlayerId = playerId,
		Player = player,
		HomeId = homeId,
		CurrentStage = 1,
		TotalStages = totalStagesInChapter,  -- V2.8: 使用章节的关卡数
		CurrentChapter = currentChapter,      -- V2.8新增: 当前章节
		State = CampaignState.PREPARING,
		Units = {},
		StageInstances = {},
		CurrentBattleId = nil,
		-- V3.4新增: 前进金币追踪数据
		StartZPosition = startZPosition,           -- 战斗开始时的起点Z坐标(CommandPart位置)
		MaxAdvancedZ = startZPosition,             -- 已经前进过的最远Z坐标
		LastRewardedDistance = 0,                  -- 上次获得奖励时的累计前进距离
	}

	-- 获取家园IdleFloor
	local homeIdleFloor = GetHomeIdleFloor(homeId)
	if not homeIdleFloor then
		return false
	end

	-- 遍历已放置单位,构建战役单位数据
	-- V2.8修复: 从PlacementSystem获取完整的放置数据(包含GridX/GridZ/GridWidth/GridDepth)
	local PlacementSystem = require(placementModule :: ModuleScript)
	local placedUnitsData = PlacementSystem.GetPlacedUnits(player) -- 获取完整数据而非仅Model

	-- 构建instanceId到placedData的映射
	local placedDataMap = {}
	for _, placedData in ipairs(placedUnitsData) do
		if placedData.InstanceId then
			placedDataMap[placedData.InstanceId] = placedData
		end
	end

	for _, unitModel in ipairs(placedUnits) do
		-- 加载单位格子坐标(兼容旧数据)
		local gridPos = GridPositionSystem.LoadUnitGridPosition(unitModel, homeIdleFloor)

		-- 获取单位配置
		local unitId = unitModel:GetAttribute("UnitId") or unitModel.Name
		local unitConfigData = UnitConfig.Units[unitId]

		if unitConfigData and unitModel:FindFirstChild("Humanoid") then
			local level = unitModel:GetAttribute("Level") or 1
			local gridSize = unitConfigData.GridSize or 1

			-- V2.8修复: 从模型Attribute或PlacementSystem获取完整占地信息
			local instanceId = unitModel:GetAttribute("InstanceId")
			local placedData = instanceId and placedDataMap[instanceId]

			-- 优先从PlacementSystem获取,其次从模型Attribute,最后从配置表
			local gridWidth = placedData and placedData.GridWidth or unitModel:GetAttribute("GridWidth") or UnitConfig.GetGridWidth(unitId)
			local gridDepth = placedData and placedData.GridDepth or unitModel:GetAttribute("GridDepth") or UnitConfig.GetGridDepth(unitId)

			local gridX: number = 0
			local gridZ: number = 0

			-- 优先从PlacementSystem或模型Attribute获取
			local tempGridX = placedData and placedData.GridX or unitModel:GetAttribute("GridX")
			local tempGridZ = placedData and placedData.GridZ or unitModel:GetAttribute("GridZ")

			if tempGridX and type(tempGridX) == "number" and tempGridZ and type(tempGridZ) == "number" then
				gridX = tempGridX
				gridZ = tempGridZ
			-- 兼容旧数据: 如果没有GridX/GridZ,从GridPos中心坐标推算左下角
			elseif gridPos and gridPos.X and gridPos.Y then
				-- 保存 gridPos 值到局部变量
				local gridPosX = gridPos.X
				local gridPosY = gridPos.Y

				-- GridPos是1-based的格子中心坐标,需要转换为0-based的左下角坐标
				-- 中心格子 -> 左下角格子: gridX = centerX - 1 - floor((width-1)/2)
				gridX = math.max(0, gridPosX - 1 - math.floor((gridWidth - 1) / 2))
				gridZ = math.max(0, gridPosY - 1 - math.floor((gridDepth - 1) / 2))

				-- 确保不超出边界
				gridX = math.min(gridX, PlacementConfig.GRID_COUNT_X - gridWidth)
				gridZ = math.min(gridZ, PlacementConfig.GRID_COUNT_Z - gridDepth)

				-- 确保所有变量都是非nil类型(消除Luau类型警告)
				local safeUnitId = tostring(unitId or "Unknown")
				local safeGridPosX = gridPosX or 0
				local safeGridPosY = gridPosY or 0
				local safeGridWidth = gridWidth or 1
				local safeGridDepth = gridDepth or 1

				DebugLog(string.format("  ℹ %s 从GridPos(%d,%d)推算GridX/Z: (%d,%d) 占地: %dx%d",
					safeUnitId, safeGridPosX, safeGridPosY, gridX, gridZ, safeGridWidth, safeGridDepth))
			else
				-- 最后兜底: 使用0,0
				warn(string.format("[CampaignManager] %s 无法获取格子坐标,使用默认值(0,0)", unitId))
			end

			-- 设置UnitId属性供CombatSystem使用
			unitModel:SetAttribute("UnitId", unitId)

			-- 设置战役保持标记,防止被误删除
			unitModel:SetAttribute("CampaignKeepInstance", true)

			-- 解除单位锚定,允许移动
			SetUnitAnchored(unitModel, false)

			-- 构建单位数据(V2.8.1: 包含完整占地信息和InstanceId)
			campaignData.Units[unitModel] = {
				Instance = unitModel,
				InstanceId = instanceId, -- V2.8.1: 保存InstanceId用于恢复
				UnitId = unitId,
				Level = level,
				GridPos = gridPos, -- 兼容旧代码,保留中心格子坐标
				GridSize = gridSize,
				-- V2.8新增: 完整占地信息
				GridX = gridX,
				GridZ = gridZ,
				GridWidth = gridWidth,
				GridDepth = gridDepth,
				CurrentHP = unitModel.Humanoid.Health,
				MaxHP = unitModel.Humanoid.MaxHealth,
				IsDead = false,
				WasAnchored = true,

				-- 战役专用字段
				IsActivated = false,
				LastKnownPosition = nil,
				LastBattleId = nil,
			}

			DebugLog(string.format("  ✅ 单位 %s 加入战役: GridX=%d, GridZ=%d, GridWidth=%d, GridDepth=%d",
				unitId, gridX, gridZ, gridWidth, gridDepth))
		end
	end

	-- 打开家园大门
	pcall(function()
		DoorControlService.OpenDoor(homeId)
	end)

	-- 锁定家园操作
	LockHomeOperations(player, true)

	-- [修复步骤 2]：显式预加载第一关，并强制等待 NavMesh 更新
	local stage1 = StageService.GetOrCreateStage(playerId, 1, false)

	-- ⭐⭐ V4.0修复：增加等待时间到 0.6 秒 ⭐⭐
	-- NavMesh需要足够时间更新，避免首轮请求NoPath导致恶性循环
	task.wait(0.6)

	-- V2.8优化：延迟4秒显示战斗特效（RedLine）
	task.delay(4, function()
		SetHomeFightingEffect(homeId, true)
	end)

	-- 预加载Stage002关卡(不阻塞主流程)
	StageService.GetOrCreateStage(playerId, 2, false)

	-- 保存战役数据
	CampaignManager.ActiveCampaigns[playerId] = campaignData

	-- V2.8修复：先传送玩家到指挥点，再通知客户端状态更新
	-- 避免主角在传送前就开始向战场移动
	TeleportPlayerToCommandPart(campaignData)
	LockPlayerMovement(campaignData)

	-- 通知客户端战役状态更新（传送完成后再触发相机锁定）
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(player, CampaignState.PREPARING, 1)
		end
	end

	-- V2.8修复：立即启动行军流程，跟随延迟由客户端CameraController根据状态控制
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
	-- 验证玩家是否在线
	local playerId = campaignData.PlayerId
	local player = game.Players:GetPlayerByUserId(playerId)
	if not player then
		DebugLog("玩家已离线，终止行军流程:", playerId, "关卡:", stageNum)
		return
	end

	campaignData.State = CampaignState.MARCHING

	-- 通知客户端状态更新
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.MARCHING, stageNum)
		end
	end

	-- 禁用单位默认Animate脚本,使用自定义MoveAnimation
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent then
			for _, descendant in ipairs(unitInstance:GetDescendants()) do
				if descendant:IsA("BaseScript") and descendant.Name == "Animate" then
					descendant.Enabled = false
					DebugLog(string.format("✅ %s 已禁用默认Animate脚本", unitData.UnitId))
				end
			end
		end
	end

	-- 设置单位为行军模式(不执行战斗AI)
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance and unitInstance.Parent and unitInstance:FindFirstChild("Humanoid") then
			-- 设置MarchMode后AI将不会执行战斗逻辑
			if UnitAI.SetMode then
				local success = UnitAI.SetMode(unitInstance, "MarchMode")
				if success then
					DebugLog(string.format("  ✅ %s 已切换到行军AI模式", unitData.UnitId))
				else
					-- AI模块不支持SetMode则跳过
				end
			end

			-- 配置单位物理碰撞组为友军
			local PhysicsManager = ServerScriptService.Systems:FindFirstChild("PhysicsManager")
			if PhysicsManager then
				local PhysicsModule = require(PhysicsManager)
				pcall(function()
					PhysicsModule.ConfigureUnitPhysics(unitInstance, "ally")
					DebugLog(string.format("  ✅ %s 已配置为友军碰撞组Allies", unitData.UnitId))
				end)
			end
		end
	end

	-- 获取目标关卡
	local stageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, stageNum, false)
	if not stageFolder then
		return CampaignManager.OnCampaignEnd(campaignData, false)
	end

	-- 启用当前关卡空气墙
	StageService.SetAirWallState(stageFolder, true)

	-- 预加载下一关并禁用其空气墙
	local nextStageNum = stageNum + 1
	if nextStageNum <= campaignData.TotalStages then
		local nextStageFolder = nil
		if StageService.StageCache[campaignData.PlayerId] and
			StageService.StageCache[campaignData.PlayerId][nextStageNum] then
			nextStageFolder = StageService.StageCache[campaignData.PlayerId][nextStageNum]
		end

		-- 禁用下一关空气墙允许通行
		if nextStageFolder then
			StageService.SetAirWallState(nextStageFolder, false)
		end
	end

	-- ⭐⭐ V4.0关键修复：修改空气墙后等待NavMesh稳定 ⭐⭐
	-- AirWall 的 CanCollide 属性改变会触发 NavMesh 更新
	-- 不等待的话首轮请求容易NoPath，导致部队卡死或直线冲刺
	-- V4.0修复：增加等待时间到 0.6 秒，确保复杂地图的NavMesh也能更新完成
	task.wait(0.6)

	-- 获取目标IdleFloor
	local targetIdleFloor = stageFolder:FindFirstChild("IdleFloor", true)
	if not targetIdleFloor then
		return CampaignManager.OnCampaignEnd(campaignData, false)
	end

	-- 构建单位移动目标列表
	-- V2.8修复: 使用PlacementConfig.GridToWorld计算正确的行军目标位置
	-- V2.9修复: 添加随机偏移避免多个单位目标位置重叠导致寻路混乱
	-- V3.0修复: 增大偏移量(0.5→2.0)，并使用确定性排序确保行为一致
	local moveTargets = {}
	local moveCount = 0
	local targetFloorCenter = targetIdleFloor.Position

	-- V3.0修复：将units转为数组并按InstanceId排序，确保遍历顺序一致
	-- 避免pairs()的不确定性导致每次Restart行为不同
	local sortedUnits = {}
	for unitInstance, unitData in pairs(campaignData.Units) do
		if not unitData.IsDead and unitInstance and unitInstance.Parent then
			table.insert(sortedUnits, {
				instance = unitInstance,
				data = unitData,
				sortKey = unitData.InstanceId or unitInstance.Name or tostring(unitInstance)
			})
		end
	end
	table.sort(sortedUnits, function(a, b)
		return a.sortKey < b.sortKey
	end)

	for unitIndex, entry in ipairs(sortedUnits) do
		local unitInstance = entry.instance
		local unitData = entry.data

		-- V2.8修复: 使用完整的GridX/GridZ/GridWidth/GridDepth计算目标位置
		local gridX = unitData.GridX
		local gridZ = unitData.GridZ
		local gridWidth = unitData.GridWidth or 1
		local gridDepth = unitData.GridDepth or gridWidth

		-- 使用PlacementConfig.GridToWorld计算目标IdleFloor上的中心位置
		local targetPosition = PlacementConfig.GridToWorld(gridX, gridZ, targetFloorCenter, gridWidth, gridDepth)

		-- V3.0修复：增大偏移量从0.5到2.0 studs，更有效地分散单位避免拥挤
		-- 使用单位索引和网格位置作为种子，确保同一单位每次偏移一致
		local offsetSeed = unitIndex * 1000 + (gridX or 0) * 100 + (gridZ or 0)
		local randomX = (math.sin(offsetSeed) * 2.0)  -- -2.0 到 2.0
		local randomZ = (math.cos(offsetSeed) * 2.0)  -- -2.0 到 2.0
		targetPosition = targetPosition + Vector3.new(randomX, 0, randomZ)

		-- ✅ V3.2新增：使用 Raycast 向下检测目标点是否在地板上
		-- 如果偏移后的点悬空（说明出界了）或者下面不是 Floor，就回退到原始中心点
		do
			local rayOrigin = targetPosition + Vector3.new(0, 5, 0)
			local rayDir = Vector3.new(0, -10, 0)
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Include
			rayParams.FilterDescendantsInstances = {targetIdleFloor} -- 只检测目标地板

			local hit = workspace:Raycast(rayOrigin, rayDir, rayParams)

			if not hit then
				-- 射线没打中地板，说明偏移出界了，回退到原始位置（不带随机偏移）
				targetPosition = targetPosition - Vector3.new(randomX, 0, randomZ)
				DebugLog(string.format("  ⚠ %s 目标点偏移出界，已回退", unitData.UnitId))
			end
		end

		-- 额外安全夹紧：确保目标点落在当前关卡IdleFloor可达范围内，避免贴在下一关空气墙后无法到达
		do
			local halfX = (targetIdleFloor.Size.X or 0) / 2
			local halfZ = (targetIdleFloor.Size.Z or 0) / 2
			-- 预留安全边距，防止贴边/贴空气墙
			local margin = 3
			targetPosition = Vector3.new(
				math.clamp(targetPosition.X, targetFloorCenter.X - halfX + margin, targetFloorCenter.X + halfX - margin),
				targetPosition.Y,
				math.clamp(targetPosition.Z, targetFloorCenter.Z - halfZ + margin, targetFloorCenter.Z + halfZ - margin)
			)
		end
		local targetCFrame = CFrame.new(targetPosition)

		moveTargets[unitInstance] = targetCFrame
		moveCount = moveCount + 1

		DebugLog(string.format("  行军目标 %s: GridX=%d, GridZ=%d, 占地=%dx%d, 目标=(%.1f, %.1f, %.1f)",
			unitData.UnitId, gridX, gridZ, gridWidth, gridDepth,
			targetPosition.X, targetPosition.Y, targetPosition.Z))

		-- 设置单位移动速度
		local unitId = unitInstance:GetAttribute("UnitId") or unitData.UnitId or unitInstance.Name
		if unitId and type(unitId) ~= "string" then
			unitId = tostring(unitId)
		end
		local humanoid = unitInstance:FindFirstChild("Humanoid")
		if humanoid and unitId then
			local UnitConfigModule = require(ReplicatedStorage.Config.UnitConfig)
			local success, configSpeed = pcall(function()
				return UnitConfigModule.GetMoveSpeed(unitId)
			end)
			if success and configSpeed and type(configSpeed) == "number" and configSpeed > 0 then
				humanoid.WalkSpeed = configSpeed
				DebugLog(string.format("  ✅ %s 设置移动速度: %.1f", tostring(unitInstance.Name), configSpeed))
			else
				-- 使用默认速度
				local defaultSpeed = humanoid.WalkSpeed
				if defaultSpeed <= 0 then
					defaultSpeed = 16
				end
				humanoid.WalkSpeed = defaultSpeed
				DebugLog(string.format("  ℹ %s 使用默认速度: %.1f", tostring(unitInstance.Name), defaultSpeed))
			end
		end

		-- 停止所有正在播放的动画
		if humanoid then
			local animator = humanoid:FindFirstChild("Animator")
			if animator then
				local tracks = animator:GetPlayingAnimationTracks()
				for _, track in ipairs(tracks) do
					pcall(function()
						track:Stop(0.1)
					end)
				end
			end
		end
	end

	-- 为行军单位附加血条
	local marchingUnits = {}
	for unitInstance, unitData in pairs(campaignData.Units) do
		if not unitData.IsDead and unitInstance and unitInstance.Parent then
			table.insert(marchingUnits, unitInstance)
		end
	end
	fireAttachHealthBars(marchingUnits)
	DebugLog(string.format("✅ 行军开始，已为 %d 个单位附加血条", #marchingUnits))

	-- V2.7新增：计算战场中心（敌方IdleFloorEnemy的中心）
	local battleCenter = nil
	local idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
	if idleFloorEnemy then
		battleCenter = idleFloorEnemy.Position
		DebugLog(string.format("🎯 战场中心位置: (%.1f, %.1f, %.1f)", battleCenter.X, battleCenter.Y, battleCenter.Z))
	end

	-- 使用PathService进行批量寻路移动
	-- V4.1修复：使用moveCount而非#moveTargets（字典取长度总是0）
	DebugLog(string.format("[MarchToStage] 开始PathService寻路，目标数量: %d", moveCount))
	local moveId = PathService.MoveUnitsToPositions(moveTargets, {
		battleCenter = battleCenter,  -- V2.7新增：传递战场中心位置
		onUnitArrived = function(unitInstance, status)
			-- 单位到达时的回调(当前为空实现)
		end,

		onAllSettled = function(arrivedList, timedOutList, failedList)
			-- 所有单位移动完成的回调
			DebugLog(string.format("[MarchToStage] PathService移动完成 - 到达:%d, 超时:%d, 失败:%d",
				#arrivedList, #timedOutList, #failedList))

			-- 停止到达单位的移动动画
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

			-- 进入战斗准备阶段
			DebugLog("[MarchToStage] 行军完成，开始BeginBattlePrep...")
			task.wait(0.1)
			CampaignManager.BeginBattlePrep(campaignData, stageNum, arrivedList, timedOutList, failedList)
		end
	})

	-- PathService启动后延迟播放移动动画(等待寻路系统初始化)
	task.delay(0.1, function()
		for unitInstance, unitData in pairs(campaignData.Units) do
			if not unitData.IsDead and unitInstance and unitInstance.Parent then
				UnitAI.PlayMoveAnimation(unitInstance)
			end
		end
		DebugLog(string.format("✅ 已为 %d 个单位播放移动动画", moveCount))
	end)

	-- 保存移动任务ID用于可能的取消操作
	if moveId then
		campaignData.CurrentMoveId = moveId
	end

	-- V3.4新增：启动前进金币检查循环
	-- 在行军和战斗过程中持续检查战场中心位置变化
	task.spawn(function()
		while campaignData.State ~= CampaignState.IDLE
			and campaignData.State ~= CampaignState.CLEANUP
			and campaignData.State ~= CampaignState.VICTORY
			and campaignData.State ~= CampaignState.DEFEAT do

			-- 检查并发放前进金币
			CheckAndRewardAdvanceCoins(campaignData)

			-- 每0.5秒检查一次
			task.wait(0.5)
		end
		DebugLog("[V3.4] 前进金币检查循环已结束")
	end)
end

--[[
战斗准备阶段(V2.0新增)
处理PathService移动完成后的单位激活和战斗准备
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
@param arrivedList table - 成功到达的单位列表
@param timedOutList table - 超时的单位列表
@param failedList table - 失败的单位列表
]]
function CampaignManager.BeginBattlePrep(campaignData, stageNum, arrivedList, timedOutList, failedList)
	campaignData.State = CampaignState.PREPARE_BATTLE

	-- 通知客户端状态更新
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.PREPARE_BATTLE, stageNum)
		end
	end

	-- 标记失败单位为已死亡
	for _, unitInstance in ipairs(failedList) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			unitData.IsDead = true
		end
	end

	-- 标记超时单位为已死亡(V2.7变更)
	for _, unitInstance in ipairs(timedOutList) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			unitData.IsDead = true
			DebugLog(string.format("  ⚠ %s 移动超时，标记为死亡，不参与战斗", unitData.UnitId or unitInstance.Name))
		end
	end

	-- 收集所有成功到达的单位
	local allArrivedUnits = {}
	for _, unit in ipairs(arrivedList) do
		table.insert(allArrivedUnits, unit)
	end
	-- V2.7不再将超时单位加入战斗
	-- for _, unit in ipairs(timedOutList) do
	--   table.insert(allArrivedUnits, unit)
	-- end

	-- 保存单位最后已知位置
	for _, unitInstance in ipairs(allArrivedUnits) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			local rootPart = unitInstance:FindFirstChild("HumanoidRootPart") or unitInstance.PrimaryPart
			if rootPart then
				unitData.LastKnownPosition = rootPart.Position
			end
		end
	end

	-- 激活并准备友军单位
	DebugLog(string.format("[BeginBattlePrep] 开始准备友军单位，总数: %d 个", #allArrivedUnits))
	local preparedAllies = {}

	for i, unitInstance in ipairs(allArrivedUnits) do
		local unitData = campaignData.Units[unitInstance]
		if unitData and not unitData.IsDead then
			DebugLog(string.format("  准备单位 %d/%d: %s", i, #allArrivedUnits, unitData.UnitId))

			-- 切换AI模式为战斗模式
			if UnitAI.SetMode then
				local success = UnitAI.SetMode(unitInstance, "CombatMode")
				if success then
					DebugLog(string.format("    ✅ %s 已切换到战斗AI模式", unitData.UnitId))
				else
					-- AI模块不支持SetMode则跳过
					DebugLog(string.format("    ℹ %s AI模块不支持模式切换", unitData.UnitId))
				end
			end

			-- 激活单位(解除锚定等)
			DebugLog(string.format("    正在激活单位 %s...", unitData.UnitId))
			local activated = CampaignUnitHelper.ActivateUnit(unitInstance)
			DebugLog(string.format("    激活结果: %s", activated and "成功" or "失败"))
			if activated then
				unitData.IsActivated = true
			end

			-- 准备进入战斗(清理PathService状态)
			DebugLog(string.format("    准备战斗状态 %s...", unitData.UnitId))
			local prepared = CampaignUnitHelper.PrepareForBattle(unitInstance)
			DebugLog(string.format("    准备战斗: %s", prepared and "成功" or "失败"))

			if activated and prepared then
				table.insert(preparedAllies, unitInstance)
				DebugLog(string.format("    ✅ %s 准备完成，加入列表", unitData.UnitId))
			end
		else
			if unitData then
				DebugLog(string.format("  跳过已死亡单位: %s", unitData.UnitId))
			end
		end
	end

	DebugLog(string.format("[BeginBattlePrep] 友军准备完成，成功准备 %d/%d 个单位", #preparedAllies, #allArrivedUnits))

	-- 获取关卡并准备敌军
	local stageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, stageNum, false)
	if not stageFolder then
		return CampaignManager.OnDefeat(campaignData)
	end

	-- 激活敌军单位
	local idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
	local preparedEnemies = {}

	if idleFloorEnemy then
		for _, child in ipairs(idleFloorEnemy:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChild("Humanoid") then
				-- V2.9修复：强制重置激活状态，确保Restart后敌人能被正确激活
				child:SetAttribute("IsActivated", false)

				-- 激活敌军单位,指定类型为"enemy"
				local activated = CampaignUnitHelper.ActivateUnit(child, "enemy")
				if activated then
					table.insert(preparedEnemies, child)
					DebugLog(string.format("  ✅ 敌军 %s 激活成功", child.Name))
				else
					DebugLog(string.format("  ⚠ 敌军 %s 激活失败", child.Name))
				end
			end
		end
	end

	-- 如果敌军数量为0,尝试重新加载敌人数据
	if #preparedEnemies == 0 then
		StageService.LoadEnemyData(stageFolder, stageNum)
		task.wait(0.2)

		-- 重新查找并激活敌军
		idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
		preparedEnemies = {}
		if idleFloorEnemy then
			for _, child in ipairs(idleFloorEnemy:GetChildren()) do
				if child:IsA("Model") and child:FindFirstChild("Humanoid") then
					local activated = CampaignUnitHelper.ActivateUnit(child, "enemy")
					if activated then
						table.insert(preparedEnemies, child)
					end
				end
			end
		end

		if #preparedEnemies > 0 then
			-- 敌军加载成功
		end
	end

	-- 输出战斗准备结果
	DebugLog(string.format("[BeginBattlePrep] 战斗准备完成 - 友军:%d，敌军: %d", #preparedAllies, #preparedEnemies))

	-- 输出友军列表
	if #preparedAllies > 0 then
		DebugLog("[BeginBattlePrep] 友军列表:")
		for i, ally in ipairs(preparedAllies) do
			DebugLog(string.format("  %d. %s (Humanoid: %s)", i, ally.Name, ally:FindFirstChild("Humanoid") and "有" or "无"))
		end
	end

	-- 输出敌军列表
	if #preparedEnemies > 0 then
		DebugLog("[BeginBattlePrep] 敌军列表:")
		for i, enemy in ipairs(preparedEnemies) do
			DebugLog(string.format("  %d. %s (Humanoid: %s)", i, enemy.Name, enemy:FindFirstChild("Humanoid") and "有" or "无"))
		end
	end

	-- 验证是否有足够单位进行战斗
	if #preparedAllies == 0 or #preparedEnemies == 0 then
		return CampaignManager.OnDefeat(campaignData)
	end

	-- 为友军和敌军附加血条
	fireAttachHealthBars(preparedAllies)
	fireAttachHealthBars(preparedEnemies)
	DebugLog(string.format("✅ 战斗准备阶段，已附加友军(%d)和敌军(%d)血条", #preparedAllies, #preparedEnemies))

	-- 短暂延迟后开始战斗
	task.wait(0.2)
	CampaignManager.StartStageBattle(campaignData, stageNum, preparedAllies, preparedEnemies)
end

--[[
开始关卡战斗(V2.0重构)
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
@param preparedAllies table - 准备好的友军列表
@param preparedEnemies table - 准备好的敌军列表
]]
function CampaignManager.StartStageBattle(campaignData, stageNum, preparedAllies, preparedEnemies)
	DebugLog(string.format("[StartStageBattle] 开始关卡 %d 战斗 - 友军:%d，敌军: %d", stageNum, #preparedAllies, #preparedEnemies))

	campaignData.State = CampaignState.FIGHTING

	-- 通知客户端状态更新
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.FIGHTING, stageNum)
		end
	end

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

	-- 记录友军单位的战斗ID
	for _, unitInstance in ipairs(preparedAllies) do
		local unitData = campaignData.Units[unitInstance]
		if unitData then
			unitData.LastBattleId = battleId
		end
	end

	-- 启动战斗
	DebugLog("[StartStageBattle] 正在启动战斗...")
	local startResult = BattleManager.StartBattle(battleId)
	DebugLog(string.format("[StartStageBattle] 战斗启动结果: %s", tostring(startResult)))
end

--[[
战斗结束回调(V2.4增加待处理机制)
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
@param result table - 战斗结果
]]
function CampaignManager.OnBattleEnd(campaignData, stageNum, result)
	DebugLog(string.format("✅ OnBattleEnd触发，stageNum=%d, Winner=%s",
		stageNum, tostring(result.Winner)))

	-- V3.3新增：通知任务系统完成战斗（战斗真正结束才算完成，中途退出不算）
	local TaskSystem = nil
	pcall(function()
		TaskSystem = require(SystemsFolder:WaitForChild("TaskSystem"))
	end)
	if TaskSystem and campaignData.Player then
		pcall(function()
			TaskSystem.OnCompleteBattle(campaignData.Player)
			DebugLog(string.format("✅ 已通知TaskSystem完成战斗，玩家: %s", campaignData.Player.Name))
		end)
	end

	-- 更新所有单位血量
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

	DebugLog(string.format("✅ 友军单位统计：存活=%d, 死亡=%d", aliveCount, deadCount))

	-- 保存待处理的战斗结果(等待玩家确认后才继续流程)
	campaignData.PendingBattleResult = {
		StageNum = stageNum,
		Winner = result.Winner,
		AliveCount = aliveCount,
		DeadCount = deadCount
	}

	DebugLog(string.format("  OnBattleEnd已保存待处理战斗结果: Winner=%s", tostring(result.Winner)))
end

--[[
处理待确认的战斗结果(V2.4新增)
@param campaignData table - 战役数据
]]
function CampaignManager.ProcessPendingBattleResult(campaignData)
	local pendingResult = campaignData.PendingBattleResult
	if not pendingResult then
		DebugLog("  ProcessPendingBattleResult: 没有待处理的战斗结果")
		return
	end

	DebugLog(string.format("✅ ProcessPendingBattleResult: 开始处理战斗结果, Winner=%s", tostring(pendingResult.Winner)))

	local stageNum = pendingResult.StageNum
	local winner = pendingResult.Winner

	-- 清除待处理标记
	campaignData.PendingBattleResult = nil

	-- 根据胜负执行对应逻辑
	if winner == "Attack" then
		-- 友军胜利
		DebugLog("✅ 我方胜利，移动下一关")
		CampaignManager.OnStageClear(campaignData, stageNum)
	else
		-- 友军失败
		DebugLog(string.format("⚠ 友军战败，进入失败流程(Winner=%s)", tostring(winner)))
		-- 跳过延迟直接进入失败流程
		CampaignManager.OnDefeat(campaignData, { skipDelay = true })
	end
end

--[[
关卡通关
@param campaignData table - 战役数据
@param stageNum number - 关卡编号
]]
function CampaignManager.OnStageClear(campaignData, stageNum)
	-- 验证玩家是否在线
	local playerId = campaignData.PlayerId
	local player = game.Players:GetPlayerByUserId(playerId)
	if not player then
		DebugLog("玩家已离线，终止关卡通关流程:", playerId, "关卡:", stageNum)
		return
	end

	campaignData.State = CampaignState.STAGE_CLEAR

	-- 通知客户端关卡进度
	if InitializeEvents() then
		local progressEvent = CampaignEvents:FindFirstChild("StageProgress")
		if progressEvent then
			progressEvent:FireClient(campaignData.Player, stageNum, "Clear")
		end
	end

	-- 检查是否完成所有关卡
	if stageNum >= campaignData.TotalStages then
		return CampaignManager.OnVictory(campaignData)
	end

	-- 准备进入下一关
	local nextStage = stageNum + 1

	-- 预加载下一关并启用其空气墙
	local nextStageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, nextStage, false)
	if nextStageFolder then
		StageService.SetAirWallState(nextStageFolder, true)
	end

	-- 预加载下下一关并禁用其空气墙
	if nextStage + 1 <= campaignData.TotalStages then
		task.spawn(function()
			local nextNextStageFolder = StageService.GetOrCreateStage(campaignData.PlayerId, nextStage + 1, false)
			if nextNextStageFolder then
				StageService.SetAirWallState(nextNextStageFolder, false)
			end
		end)
	end

	-- 更新当前关卡并继续行军
	campaignData.CurrentStage = nextStage
	task.wait(2)
	CampaignManager.MarchToStage(campaignData, nextStage)
end

--[[
战役胜利
@param campaignData table - 战役数据
]]
function CampaignManager.OnVictory(campaignData)
	campaignData.State = CampaignState.VICTORY

	-- 通知客户端状态更新
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.VICTORY, campaignData.TotalStages)
		end
	end

	-- V2.8新增: 获取当前章节信息
	local currentChapter = campaignData.CurrentChapter or 1

	-- V2.8: 计算章节奖励
	local totalReward = 0
	local chapterConfig = StageConfig.GetChapterConfig(currentChapter)

	if chapterConfig and chapterConfig.Rewards then
		-- 使用章节配置的奖励
		for i = 1, campaignData.TotalStages do
			local reward = chapterConfig.Rewards[i]
			if reward then
				totalReward = totalReward + (reward.Coins or 0)
			end
		end
		DebugLog(string.format("[OnVictory] 章节 %d 奖励计算完成，总奖励: %d 金币", currentChapter, totalReward))
	else
		-- 兼容旧版本: 使用Style01奖励
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
	end

	-- V3.4.1修改：使用AddCoinsFromBattle触发金币表现效果
	if totalReward > 0 then
		CurrencySystem.AddCoinsFromBattle(campaignData.Player, totalReward, campaignData.CurrentStage)
	end

	-- V2.8新增: 更新章节进度
	local player = campaignData.Player
	if player then
		local success, newCompletedChapters = DataManager.CompleteChapter(player, currentChapter)
		if success then
			DebugLog(string.format("[OnVictory] 玩家 %s 通关章节 %d，已通关章节数: %d",
				player.Name, currentChapter, newCompletedChapters))

			-- 保存数据
			DataManager.SavePlayerDataThrottled(player, true)  -- 强制保存

			-- V2.8: 触发房屋升级检查
			local HouseUpgradeSystem = nil
			pcall(function()
				HouseUpgradeSystem = require(SystemsFolder:WaitForChild("HouseUpgradeSystem"))
			end)

			if HouseUpgradeSystem then
				HouseUpgradeSystem.OnChapterCompleted(player, currentChapter)
			end
		end
	end

	-- 延迟后进入结束流程
	task.wait(3)
	CampaignManager.OnCampaignEnd(campaignData, true)
end

--[[
战役失败
@param campaignData table - 战役数据
@param options table? - 可选参数 {skipDelay=true} 跳过延迟(用于Restart/Retreat)
]]
function CampaignManager.OnDefeat(campaignData, options)
	options = options or {}
	DebugLog("⚠ OnDefeat触发 - 友军战败")
	campaignData.State = CampaignState.DEFEAT

	-- 通知客户端状态更新
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.DEFEAT, campaignData.CurrentStage)
		end
	end

	-- 延迟后进入结束流程
	local delaySeconds = options.skipDelay and 0 or 3
	DebugLog(string.format("  OnDefeat将在%.1f秒后调用OnCampaignEnd", delaySeconds))
	if delaySeconds > 0 then
		task.wait(delaySeconds)
	end
	DebugLog("✅ OnDefeat调用OnCampaignEnd(false)")
	CampaignManager.OnCampaignEnd(campaignData, false)
end

--[[
战役结束流程
@param campaignData table - 战役数据
@param isVictory boolean - 是否胜利
]]
function CampaignManager.OnCampaignEnd(campaignData, isVictory)
	DebugLog(string.format("✅ OnCampaignEnd触发，isVictory=%s", tostring(isVictory)))
	campaignData.State = CampaignState.CLEANUP

	-- 设置等待玩家确认标记
	campaignData.IsWaitingForConfirm = true
	campaignData.IsVictory = isVictory

	-- 构建结算数据
	local currentStage = campaignData.CurrentStage or 1
	local result = isVictory and "Attack" or "Defense"

	-- 发送战斗结算弹窗事件到客户端
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
		if battleEventsFolder then
			local victoryPopupEvent = battleEventsFolder:FindFirstChild("VictoryPopup")
			if victoryPopupEvent then
				-- 发送结算弹窗(battleId设为0表示战役结算)
				victoryPopupEvent:FireClient(campaignData.Player, 0, result, currentStage, nil)
				DebugLog(string.format("  ✅ 已发送结算弹窗，PlayerId=%d, Result=%s, Stage=%d",
					campaignData.PlayerId, result, currentStage))
			else
				warn(GameConfig.LOG_PREFIX, "[CampaignManager] VictoryPopup事件不存在(请检查RemoteEvent创建)")
				-- 事件不存在则10秒后自动完成清理
			end
		end
	end

	-- 设置超时自动完成机制(15秒后自动清理)
	task.delay(15, function()
		if campaignData.IsWaitingForConfirm then
			warn(GameConfig.LOG_PREFIX, string.format("[CampaignManager] 玩家超过 15秒未确认结算，PlayerId=%d", campaignData.PlayerId))
			CampaignManager.CompleteCampaignEnd(campaignData)
		end
	end)
end

--[[
完成战役结束清理流程
@param campaignData table - 战役数据
]]
function CampaignManager.CompleteCampaignEnd(campaignData)
	if not campaignData then
		warn(GameConfig.LOG_PREFIX, "[CampaignManager] CompleteCampaignEnd错误: campaignData为空")
		return
	end

	-- 检查是否已完成
	if not campaignData.IsWaitingForConfirm then
		DebugLog("CompleteCampaignEnd跳过: 已经完成清理流程")
		return
	end

	campaignData.IsWaitingForConfirm = false
	RestorePlayerMovement(campaignData)
	DebugLog(string.format("✅ CompleteCampaignEnd开始，PlayerId=%d", campaignData.PlayerId))

	-- ==================== 修复核心：强制清理移动和AI ====================

	-- 1. 强制取消当前的批量行军任务（解决原地转圈和奔向第二关的问题）
	if campaignData.CurrentMoveId then
		DebugLog(string.format("🛑 强制取消行军任务: %s", tostring(campaignData.CurrentMoveId)))
		PathService.CancelGroupMove(campaignData.CurrentMoveId)
		campaignData.CurrentMoveId = nil
	end

	-- 2. 强制停止所有单位的AI和路径（解决实例复用导致的状态残留）
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance then
			-- 停止AI逻辑
			UnitAI.StopAI(unitInstance)
			-- 清理PathService中的单体路径状态
			PathService.ClearPath(unitInstance)
			-- 停止所有动画
			local humanoid = unitInstance:FindFirstChild("Humanoid")
			if humanoid then
				humanoid:Move(Vector3.zero) -- 物理刹车
			end
		end
	end

	-- =================================================================

	-- 传送玩家回出生点
	local player = campaignData.Player
	if player and player.Character then
		local homeId = campaignData.HomeId
		local homeFolder = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
		if homeFolder then
			local spawnLocation = homeFolder:FindFirstChild("SpawnLocation")
			if spawnLocation and player.Character:FindFirstChild("HumanoidRootPart") then
				DebugLog(string.format("✅ 正在传送玩家 %s 回出生点", player.Name))
				player.Character.HumanoidRootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
			end
		end
	end

	-- 关闭家园大门
	pcall(function()
		DoorControlService.CloseDoor(campaignData.HomeId)
	end)

	-- 清除路径缓存
	ClearPathCache(campaignData.HomeId)

	-- 移除所有战役单位的血条
	local campaignUnits = {}
	for unitInstance, unitData in pairs(campaignData.Units) do
		if unitInstance then
			table.insert(campaignUnits, unitInstance)
		end
	end
	if #campaignUnits > 0 then
		fireDetachHealthBars(campaignUnits)
		DebugLog(string.format("✅ 战役结束，已移除 %d 个单位的血条", #campaignUnits))
	end

	-- 执行单位重生（现在是安全的，因为AI和移动都已停止）
	DebugLog("✅ CompleteCampaignEnd调用RespawnUnits")
	CampaignManager.RespawnUnits(campaignData)

	-- V2.8.2: CampaignKeepInstance标记已在RespawnUnits中清除,这里不再重复处理

	-- 清理关卡场景
	StageService.CleanupStages(campaignData.PlayerId)

	-- 关闭家园战斗特效
	SetHomeFightingEffect(campaignData.HomeId, false)

	-- 解锁家园操作
	LockHomeOperations(campaignData.Player, false)

	-- 移除战役数据
	CampaignManager.ActiveCampaigns[campaignData.PlayerId] = nil

	-- 通知客户端战役结束
	if InitializeEvents() then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate:FireClient(campaignData.Player, CampaignState.IDLE, 0)
		end
	end

	DebugLog(string.format("  战役完全结束: PlayerId=%d", campaignData.PlayerId))
end

--[[
恢复单位动画状态(V2.0.2 重构优化)
重新创建Animator并重置Humanoid状态以修复动画卡死问题
@param unitModel Model - 单位模型
@param unitId string - 单位ID(用于日志)
]]
local function RestoreUnitAnimationState(unitModel, unitId)
	if not unitModel then
		return
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		DebugLog(string.format("    ⚠ %s 未找到Humanoid", unitId))
		return
	end

	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		DebugLog(string.format("    ⚠ %s 未找到HumanoidRootPart", unitId))
		return
	end

	DebugLog(string.format("    ✅ 正在恢复 %s 的动画", unitId))

	-- 1. 销毁旧Animator并创建新的
	local oldAnimator = humanoid:FindFirstChild("Animator")
	if oldAnimator then
		oldAnimator:Destroy()
		DebugLog(string.format("    ✅ %s 已销毁旧Animator", unitId))
	end

	-- 创建新Animator
	local newAnimator = Instance.new("Animator")
	newAnimator.Parent = humanoid
	DebugLog(string.format("    ✅ %s 已创建新Animator", unitId))

	-- 2. 重置Humanoid属性
	pcall(function()
		-- 重置物理状态
		humanoid.BreakJointsOnDeath = false
		-- 重置姿态状态
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid.AutoRotate = true

		-- 清零速度
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		DebugLog(string.format("    ✅ %s Humanoid属性已重置", unitId))
	end)

	-- 3. 强制切换状态到Running
	pcall(function()
		-- 先切换到Physics状态清理
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		task.wait()
		-- 再切换到Running状态
		humanoid:ChangeState(Enum.HumanoidStateType.Running)

		DebugLog(string.format("    ✅ %s 已切换状态到Running", unitId))
	end)

	-- 4. 重启Animate脚本
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if (descendant:IsA("Script") or descendant:IsA("LocalScript")) and descendant.Name == "Animate" then
			pcall(function()
				descendant.Disabled = true
				task.wait()
				descendant.Disabled = false
				DebugLog(string.format("    ✅ %s Animate脚本已重启", unitId))
			end)
		end
	end

	-- 5. 重置所有Motor6D变换
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			pcall(function()
				descendant.Transform = CFrame.new()
			end)
		end
	end

	DebugLog(string.format("    ✅ %s 动画恢复完成(Animator已重建)", unitId))
end

--[[
播放展示动画(单位在基地待机时的循环动画)
@param unitModel Model - 单位模型
@param unitId string - 单位ID
]]
local function PlayShowAnimation(unitModel, unitId)
	if not unitModel or not unitId then
		return
	end
	-- 1. 获取Humanoid并验证
	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	-- 2. 重置Humanoid状态
	pcall(function()
		-- 如果处于Physics状态则切换回Running
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
		-- 停止所有正在播放的动画
		for _, oldTrack in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function()
				oldTrack:Stop(0.1)
			end)
		end
		return animator:LoadAnimation(animation)
	end)
	if success and track then
		-- 设置动画优先级为Idle
		track.Priority = Enum.AnimationPriority.Idle
		track.Looped = true

		-- 连接Stopped事件以清理Animation实例
		track.Stopped:Connect(function()
			if animation then
				animation:Destroy()
			end
		end)

		track:Play(0.1)

		DebugLog(string.format("    [CampaignManager] 单位 %s 开始播放展示动画 (Priority=Idle, Looped=true)", tostring(unitId)))
	else
		warn("播放展示动画失败:", unitId)
		if animation then
			animation:Destroy()
		end
	end
end

--[[
重生所有单位
V2.8.2修复: 处理单位被隐藏(Parent=nil)的情况,重新挂载并同步PlacementSystem
@param campaignData table - 战役数据
]]
function CampaignManager.RespawnUnits(campaignData)
	local homeIdleFloor = GetHomeIdleFloor(campaignData.HomeId)
	if not homeIdleFloor then
		warn("[CampaignManager] RespawnUnits失败: 未找到家园IdleFloor，HomeId =", campaignData.HomeId)
		return
	end

	-- 获取PlacementSystem用于重新创建被销毁的单位
	local placementModule = SystemsFolder:FindFirstChild("PlacementSystem")
	local PlacementSystem = placementModule and require(placementModule :: ModuleScript)

	local totalUnits = 0
	for _ in pairs(campaignData.Units) do
		totalUnits = totalUnits + 1
	end

	DebugLog(string.format("✅ 开始重生单位，HomeId = %d，总计 %d 个单位",
		campaignData.HomeId,
		totalUnits))

	local respawnCount = 0
	local failCount = 0
	local recreateCount = 0

	-- 获取家园文件夹作为Parent
	local homeFolder = homeIdleFloor.Parent
	local targetParent = homeFolder or Workspace

	-- 遍历所有战役单位执行重生
	for unitInstance, unitData in pairs(campaignData.Units) do
		local safeUnitId = tostring(unitData.UnitId or "Unknown")

		DebugLog(string.format("  处理单位 %s (IsDead=%s)",
			safeUnitId,
			tostring(unitData.IsDead)))

		-- V2.8.1: 确保 gridX/gridZ 不是 nil
		local gridX = unitData.GridX or 0
		local gridZ = unitData.GridZ or 0
		local gridWidth = unitData.GridWidth or 1
		local gridDepth = unitData.GridDepth or gridWidth

		-- 计算复生位置
		local floorCenter = homeIdleFloor.Position
		local targetPosition = PlacementConfig.GridToWorld(gridX, gridZ, floorCenter, gridWidth, gridDepth)

		-- 越界检测和修正
		local floorHalfX = homeIdleFloor.Size.X / 2
		local floorHalfZ = homeIdleFloor.Size.Z / 2
		local floorMinX = floorCenter.X - floorHalfX
		local floorMaxX = floorCenter.X + floorHalfX
		local floorMinZ = floorCenter.Z - floorHalfZ
		local floorMaxZ = floorCenter.Z + floorHalfZ

		local unitHalfSpanX = (gridWidth * PlacementConfig.GRID_UNIT_SIZE) / 2
		local unitHalfSpanZ = (gridDepth * PlacementConfig.GRID_UNIT_SIZE) / 2

		local clampedX = math.clamp(targetPosition.X, floorMinX + unitHalfSpanX, floorMaxX - unitHalfSpanX)
		local clampedZ = math.clamp(targetPosition.Z, floorMinZ + unitHalfSpanZ, floorMaxZ - unitHalfSpanZ)

		if clampedX ~= targetPosition.X or clampedZ ~= targetPosition.Z then
			warn(string.format("[CampaignManager] ⚠ %s 复生位置超出边界! 原始:(%.1f,%.1f) 修正后:(%.1f,%.1f)",
				safeUnitId, targetPosition.X, targetPosition.Z, clampedX, clampedZ))
			targetPosition = Vector3.new(clampedX, targetPosition.Y, clampedZ)
		end

		DebugLog(string.format("    复生位置: GridX=%d, GridZ=%d, 占地=%dx%d, 世界坐标=(%.1f, %.1f, %.1f)",
			gridX, gridZ, gridWidth, gridDepth,
			targetPosition.X, targetPosition.Y, targetPosition.Z))

		-- V2.8.1: 检查单位实例是否有效
		local instanceValid = false
		local currentInstance = unitInstance

		if unitInstance then
			local checkSuccess = pcall(function()
				local _ = unitInstance.Name
				local _ = unitInstance.Parent
			end)

			if checkSuccess then
				-- 实例存在,检查是否在场景中
				if unitInstance.Parent or unitInstance:IsDescendantOf(game) then
					instanceValid = true
				else
					-- 尝试重新挂载
					local mountSuccess = SafeSetParent(unitInstance, targetParent)
					if mountSuccess and unitInstance.Parent then
						instanceValid = true
						DebugLog(string.format("    ✅ %s 重新挂载成功", safeUnitId))
					end
				end
			end
		end

		-- V2.8.2: 如果实例无效或被隐藏(Parent=nil),需要恢复
		if not instanceValid then
			DebugLog(string.format("  ⚠ %s 实例无效或被隐藏,尝试恢复...", safeUnitId))

			-- 方案1: 原始unitInstance可能只是被隐藏(Parent=nil),尝试重新挂载
			if unitInstance then
				local canAccess = pcall(function() return unitInstance.Name end)
				if canAccess then
					-- 实例存在但被隐藏,尝试重新挂载
					local mountSuccess = SafeSetParent(unitInstance, targetParent)
					if mountSuccess and unitInstance.Parent then
						currentInstance = unitInstance
						instanceValid = true
						DebugLog(string.format("    ✅ %s 原始实例重新挂载成功", safeUnitId))

						-- V3.8修复：挂载后立即重置透明度和UI
						if UnitAI.ResetModelTransparency then
							UnitAI.ResetModelTransparency(currentInstance)
						end
						local head = currentInstance:FindFirstChild("Head")
						if head then
							for _, child in ipairs(head:GetChildren()) do
								if child:IsA("BillboardGui") then
									child.Enabled = true
								end
							end
						end
					end
				end
			end

			-- 方案2: 从PlacementSystem获取Model引用
			if not instanceValid and PlacementSystem then
				local instanceId = unitData.InstanceId or (unitInstance and pcall(function() return unitInstance:GetAttribute("InstanceId") end) and unitInstance:GetAttribute("InstanceId"))

				if instanceId then
					local placedUnitsData = PlacementSystem.GetPlacedUnits(campaignData.Player)
					local foundPlacedData = nil

					for _, pData in ipairs(placedUnitsData) do
						if pData.InstanceId == instanceId then
							foundPlacedData = pData
							break
						end
					end

					if foundPlacedData and foundPlacedData.Model then
						local pModel = foundPlacedData.Model
						local canAccessP = pcall(function() return pModel.Name end)
						if canAccessP then
							-- PlacementSystem的Model可能也被隐藏,尝试重新挂载
							local mountSuccess = SafeSetParent(pModel, targetParent)
							if mountSuccess and pModel.Parent then
								currentInstance = pModel
								instanceValid = true
								DebugLog(string.format("    ✅ %s 从PlacementSystem恢复并重新挂载成功", safeUnitId))

								-- V3.8修复：挂载后立即重置透明度和UI
								if UnitAI.ResetModelTransparency then
									UnitAI.ResetModelTransparency(currentInstance)
								end
								local head = currentInstance:FindFirstChild("Head")
								if head then
									for _, child in ipairs(head:GetChildren()) do
										if child:IsA("BillboardGui") then
											child.Enabled = true
										end
									end
								end
							end
						end
					end
				end
			end

			-- 如果仍然无效,标记为失败但不阻止其他单位
			if not instanceValid then
				warn(string.format("[CampaignManager] ❌ %s 无法恢复,需要玩家重新进入游戏", safeUnitId))
				failCount = failCount + 1
				continue
			end

			recreateCount = recreateCount + 1
		end

		-- 执行复生流程
		local teleportSuccess = false

		-- V3.8修复：重置透明度（确保模型可见）
		if currentInstance then
			-- 立即重置一次
			if UnitAI.ResetModelTransparency then
				UnitAI.ResetModelTransparency(currentInstance)
			end
		end

		-- 创建目标CFrame
		local groundedCFrame = CFrame.new(targetPosition.X, targetPosition.Y, targetPosition.Z)

		-- 执行传送
		pcall(function()
			if currentInstance.PivotTo then
				currentInstance:PivotTo(groundedCFrame)
				teleportSuccess = true
			elseif currentInstance.PrimaryPart then
				currentInstance:SetPrimaryPartCFrame(groundedCFrame)
				teleportSuccess = true
			elseif currentInstance:FindFirstChild("HumanoidRootPart") then
				currentInstance.HumanoidRootPart.CFrame = groundedCFrame
				teleportSuccess = true
			end
		end)

		if not teleportSuccess then
			warn(string.format("[CampaignManager] ⚠ %s 传送失败", safeUnitId))
			failCount = failCount + 1
			continue
		end

		-- 验证传送后位置
		local actualPos = nil
		pcall(function()
			if currentInstance.PrimaryPart then
				actualPos = currentInstance.PrimaryPart.Position
			elseif currentInstance:FindFirstChild("HumanoidRootPart") then
				actualPos = currentInstance.HumanoidRootPart.Position
			end
		end)

		if actualPos then
			DebugLog(string.format("    传送后位置: (%.1f, %.1f, %.1f)", actualPos.X, actualPos.Y, actualPos.Z))

			-- 检查Y坐标是否合理(防止掉出世界)
			local floorTopY = floorCenter.Y + (homeIdleFloor.Size.Y / 2)
			if actualPos.Y < floorTopY - 10 then
				warn(string.format("[CampaignManager] ⚠ %s Y坐标异常(%.1f),修正到地板上方", safeUnitId, actualPos.Y))
				local fixedCFrame = CFrame.new(actualPos.X, floorTopY + 3, actualPos.Z)
				pcall(function()
					if currentInstance.PivotTo then
						currentInstance:PivotTo(fixedCFrame)
					end
				end)
			end
		end

		-- 解除锚定
		SetUnitAnchored(currentInstance, false)

		-- 恢复动画状态
		pcall(function()
			RestoreUnitAnimationState(currentInstance, safeUnitId)
		end)

		-- 恢复血量
		local humanoid = currentInstance:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.Health = unitData.MaxHP or humanoid.MaxHealth
			DebugLog(string.format("    %s 血量恢复到 %d", safeUnitId, humanoid.Health))
		end

		-- 移除血条
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
			if battleEventsFolder then
				local detachHealthBarsEvent = battleEventsFolder:FindFirstChild("DetachHealthBars")
				if detachHealthBarsEvent then
					detachHealthBarsEvent:FireAllClients({currentInstance})
				end
			end
		end

		-- 重置死亡标记
		unitData.IsDead = false
		unitData.CurrentHP = unitData.MaxHP

		-- V2.8.2: 清除CampaignKeepInstance标记(在这里清除确保使用正确的实例)
		pcall(function()
			currentInstance:SetAttribute("CampaignKeepInstance", false)
		end)

		-- V3.8修复：清除PendingDeathHide标记，防止延迟隐藏任务把复生后的单位又隐藏掉
		pcall(function()
			currentInstance:SetAttribute("PendingDeathHide", nil)
		end)

		-- V2.8.2: 如果使用了不同的实例(currentInstance != unitInstance),更新PlacementSystem
		if currentInstance ~= unitInstance and PlacementSystem then
			local instanceId = unitData.InstanceId
			if instanceId then
				-- 更新PlacementSystem中的Model引用
				local placedUnitsData = PlacementSystem.GetPlacedUnits(campaignData.Player)
				for _, pData in ipairs(placedUnitsData) do
					if pData.InstanceId == instanceId then
						pData.Model = currentInstance
						DebugLog(string.format("    ✅ %s PlacementSystem Model引用已更新", safeUnitId))
						break
					end
				end
			end
		end

		-- 播放重生特效
		PlayRespawnEffect(currentInstance, unitData.GridSize or 1)

		-- 播放展示动画
		PlayShowAnimation(currentInstance, safeUnitId)

		-- V3.8修复：最终确保透明度已重置（防止死亡渐隐效果残留）
		if UnitAI.ResetModelTransparency then
			UnitAI.ResetModelTransparency(currentInstance)

			-- [关键修复 V2.8.4] 双重保险：强制遍历所有部件重置透明度
			-- 防止CombatSystem的Tween延迟取消导致的半透明残留
			-- 配合CombatSystem.lua的事件监听修复效果最佳
			for _, part in ipairs(currentInstance:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					part.Transparency = 0
				elseif part:IsA("Decal") or part:IsA("Texture") then
					part.Transparency = 0
				end
			end
		end

		-- V3.8修复：恢复头顶UI（死亡时被隐藏的BillboardGui）
		local head = currentInstance:FindFirstChild("Head")
		if head then
			for _, child in ipairs(head:GetChildren()) do
				if child:IsA("BillboardGui") then
					child.Enabled = true
				end
			end
			DebugLog(string.format("    %s 头顶UI已恢复", safeUnitId))
		end

		-- 延迟后重新锚定(展示模式)
		if unitData.WasAnchored then
			task.delay(0.1, function()
				if currentInstance and currentInstance.Parent then
					SetUnitAnchored(currentInstance, true, true)
					PlayShowAnimation(currentInstance, safeUnitId)
				end
			end)
		end

		respawnCount = respawnCount + 1
		DebugLog(string.format("    ✅ %s 重生完成", safeUnitId))
	end

	DebugLog(string.format("✅ 单位重生完成: 成功=%d, 失败=%d, 重新创建=%d",
		respawnCount, failCount, recreateCount))

	-- 如果有失败的单位,给玩家提示
	if failCount > 0 then
		warn(string.format("[CampaignManager] ⚠ %d 个单位复生失败,玩家可能需要重新进入游戏恢复", failCount))
	end
end

--[[
请求撤退
@param player Player - 玩家
]]
function CampaignManager.RequestRetreat(player)
	local playerId = player.UserId
	local campaignData = CampaignManager.ActiveCampaigns[playerId]

	if not campaignData then
		return
	end

	-- Restart/Retreat时跳过延迟直接进入失败流程
	CampaignManager.OnDefeat(campaignData, { skipDelay = true })
end

--[[
V2.11新增：传送玩家回家园出生点
在战斗期间允许玩家返回家园
@param player Player - 玩家
@return boolean - 是否传送成功
]]
function CampaignManager.ReturnToHome(player)
	if not player then
		return false
	end

	local playerId = player.UserId
	local campaignData = CampaignManager.ActiveCampaigns[playerId]

	-- 获取玩家HomeId
	local homeId = nil
	if campaignData then
		homeId = campaignData.HomeId
	else
		-- 如果没有战役数据，从PlayerManager获取
		homeId = PlayerManager.GetPlayerHomeId(player)
	end

	if not homeId then
		DebugLog(string.format("ReturnToHome失败: 玩家 %s 没有分配家园", player.Name))
		return false
	end

	-- 获取家园出生点
	local homeFolder = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
	if not homeFolder then
		DebugLog(string.format("ReturnToHome失败: 未找到PlayerHome%s", tostring(homeId)))
		return false
	end

	local spawnLocation = homeFolder:FindFirstChild("SpawnLocation")
	if not spawnLocation then
		DebugLog(string.format("ReturnToHome失败: PlayerHome%s中未找到SpawnLocation", tostring(homeId)))
		return false
	end

	-- 传送玩家
	local character = player.Character
	if not character then
		DebugLog(string.format("ReturnToHome失败: 玩家 %s 没有角色", player.Name))
		return false
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		DebugLog(string.format("ReturnToHome失败: 玩家 %s 角色没有HumanoidRootPart", player.Name))
		return false
	end

	-- 执行传送（在出生点上方一定高度）
	local teleportPosition = spawnLocation.CFrame + Vector3.new(0, 5, 0)
	humanoidRootPart.CFrame = teleportPosition

	DebugLog(string.format("✅ 玩家 %s 已传送回家园出生点", player.Name))
	return true
end

--[[
初始化CampaignManager
@return boolean - 是否初始化成功
]]
function CampaignManager.Initialize()
	-- 初始化远程事件
	if not InitializeEvents() then
		return false
	end

	-- 监听开始战役请求
	local requestStart = CampaignEvents:FindFirstChild("RequestStartCampaign")
	if requestStart then
		requestStart.OnServerEvent:Connect(function(player)
			local success, err = pcall(function()
				CampaignManager.StartCampaign(player)
			end)

		end)
	end

	-- 监听撤退请求
	local requestRetreat = CampaignEvents:FindFirstChild("RequestRetreat")
	if requestRetreat then
		requestRetreat.OnServerEvent:Connect(function(player)
			local success, err = pcall(function()
				CampaignManager.RequestRetreat(player)
			end)

		end)
	end

	-- V2.11新增：监听返回家园请求
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local battleControlEvents = eventsFolder:FindFirstChild("BattleControlEvents")
		if battleControlEvents then
			local returnToHomeEvent = battleControlEvents:FindFirstChild("ReturnToHome")
			if returnToHomeEvent then
				returnToHomeEvent.OnServerEvent:Connect(function(player)
					local success, err = pcall(function()
						CampaignManager.ReturnToHome(player)
					end)
					if not success then
						warn("[CampaignManager] ReturnToHome处理失败:", err)
					end
				end)
				DebugLog("✅ 已监听ReturnToHome远程事件")
			else
				DebugLog("⚠ BattleControlEvents中未找到ReturnToHome事件")
			end
		else
			DebugLog("⚠ Events中未找到BattleControlEvents文件夹")
		end
	end

	-- 监听玩家离开事件
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