--[[
=====================================================
脚本名称: SkillSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/SkillSystem.lua
版本: V3.0
=====================================================

功能描述:
- 管理玩家技能背包数据
- 处理技能释放请求
- 计算技能伤害并应用效果
- 支持即时伤害和持续伤害(DOT)
- 与战斗系统集成

=====================================================
]]

local SkillSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- 引用配置
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 延迟加载的模块引用(避免循环依赖)
local DataManager = nil
local CombatSystem = nil
local UnitManager = nil

-- 远程事件引用
local SkillEvents = nil

-- 活跃DOT效果: [effectId] = {SkillId, Position, RemainingTicks, ...}
local ActiveDOTEffects = {}
local DOTEffectIdCounter = 0

-- 玩家技能冷却: [playerId] = timestamp
local PlayerSkillCooldowns = {}

-- 配置常量
local SKILL_COOLDOWN = 0.5  -- 技能释放冷却(秒)

-- ==================== 私有函数 ====================

--[[
初始化延迟加载的模块
]]
local function InitializeModules()
	if not DataManager then
		local coreFolder = ServerScriptService:FindFirstChild("Core")
		if coreFolder then
			local dm = coreFolder:FindFirstChild("DataManager")
			if dm then
				DataManager = require(dm)
			end
		end
	end

	if not CombatSystem then
		local systemsFolder = ServerScriptService:FindFirstChild("Systems")
		if systemsFolder then
			local cs = systemsFolder:FindFirstChild("CombatSystem")
			if cs then
				CombatSystem = require(cs)
			end
		end
	end

	if not UnitManager then
		local systemsFolder = ServerScriptService:FindFirstChild("Systems")
		if systemsFolder then
			local um = systemsFolder:FindFirstChild("UnitManager")
			if um then
				UnitManager = require(um)
			end
		end
	end
end

--[[
初始化远程事件
]]
local function InitializeEvents()
	if SkillEvents then return true end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	SkillEvents = eventsFolder:FindFirstChild("SkillEvents")
	if not SkillEvents then
		SkillEvents = Instance.new("Folder")
		SkillEvents.Name = "SkillEvents"
		SkillEvents.Parent = eventsFolder
	end

	-- 创建所需的RemoteEvent
	local eventNames = {
		"RequestCastSkill",     -- 客户端→服务器：请求释放技能
		"CastSkillResponse",    -- 服务器→客户端：释放结果
		"SkillInventoryUpdate", -- 服务器→客户端：技能背包更新
		"SpawnSkillEffect",     -- 服务器→客户端：生成技能特效
		"RequestSkillSync",     -- 客户端→服务器：请求同步技能背包
	}

	for _, eventName in ipairs(eventNames) do
		if not SkillEvents:FindFirstChild(eventName) then
			local event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = SkillEvents
		end
	end

	return true
end

--[[
获取日志前缀
]]
local function GetLogPrefix()
	return GameConfig.LOG_PREFIX or "[PrisonGame]"
end

--[[
调试日志
]]
local function DebugLog(...)
	if GameConfig.DEBUG_MODE then
		print(GetLogPrefix(), "[SkillSystem]", ...)
	end
end

--[[
获取范围内的敌方单位
@param position Vector3 - 中心位置
@param radius number - 半径(studs)
@param casterTeam string - 释放者阵营("ally"或"enemy")
@return table - 敌方单位列表
]]
local function GetEnemiesInRange(position, radius, casterTeam)
	InitializeModules()

	local enemies = {}
	local targetTeam = casterTeam == "ally" and "enemy" or "ally"

	-- 方案1: 使用UnitManager获取单位(如果可用)
	if UnitManager and UnitManager.GetAllUnits then
		local allUnits = UnitManager.GetAllUnits()
		for _, unitModel in ipairs(allUnits) do
			local team = unitModel:GetAttribute("Team")
			if team == targetTeam then
				local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local distance = (rootPart.Position - position).Magnitude
					if distance <= radius then
						table.insert(enemies, unitModel)
					end
				end
			end
		end
	else
		-- 方案2: 遍历Workspace查找带有Humanoid的模型
		for _, child in ipairs(Workspace:GetDescendants()) do
			if child:IsA("Model") and child:FindFirstChild("Humanoid") then
				local team = child:GetAttribute("Team")
				if team == targetTeam then
					local rootPart = child:FindFirstChild("HumanoidRootPart")
					if rootPart then
						local distance = (rootPart.Position - position).Magnitude
						if distance <= radius then
							table.insert(enemies, child)
						end
					end
				end
			end
		end
	end

	return enemies
end

--[[
对单位造成伤害
@param unitModel Model - 目标单位
@param damage number - 伤害值
@param skillId number - 技能ID(用于日志)
]]
local function DealDamageToUnit(unitModel, damage, skillId)
	InitializeModules()

	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- 使用CombatSystem造成伤害(如果可用)
	if CombatSystem and CombatSystem.TakeDamage then
		-- CombatSystem.TakeDamage(unitModel, damage, attacker, attackerTeam)
		-- 技能伤害没有具体攻击者,传nil
		CombatSystem.TakeDamage(unitModel, damage, nil, "ally")
	else
		-- 直接扣血
		humanoid.Health = humanoid.Health - damage

		-- 尝试发送伤害数字事件
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			local battleEvents = eventsFolder:FindFirstChild("BattleEvents")
			if battleEvents then
				local showDamageEvent = battleEvents:FindFirstChild("ShowDamageNumber")
				if showDamageEvent then
					-- 白色字体(我方对敌方)
					showDamageEvent:FireAllClients(unitModel, damage, "ally")
				end
			end
		end
	end

	DebugLog(string.format("技能 %d 对 %s 造成 %d 点伤害", skillId, unitModel.Name, damage))
end

--[[
执行即时伤害技能效果
@param skillData table - 技能配置
@param position Vector3 - 释放位置
]]
local function ExecuteInstantDamage(skillData, position)
	local radius = skillData.Range / 2  -- Range是直径,转换为半径
	local enemies = GetEnemiesInRange(position, radius, "ally")

	for _, enemyUnit in ipairs(enemies) do
		DealDamageToUnit(enemyUnit, skillData.Damage, skillData.SkillId)
	end

	DebugLog(string.format("即时伤害技能 %s 命中 %d 个敌人", skillData.Name, #enemies))
end

--[[
创建DOT效果
@param skillData table - 技能配置
@param position Vector3 - 释放位置
@return string - DOT效果ID
]]
local function CreateDOTEffect(skillData, position)
	DOTEffectIdCounter = DOTEffectIdCounter + 1
	local effectId = "DOT_" .. DOTEffectIdCounter

	local totalTicks = math.floor(skillData.Duration / skillData.TickInterval)

	ActiveDOTEffects[effectId] = {
		SkillId = skillData.SkillId,
		SkillData = skillData,
		Position = position,
		Radius = skillData.Range / 2,  -- 直径转半径
		TickDamage = skillData.TickDamage,
		TickInterval = skillData.TickInterval,
		RemainingTicks = totalTicks - 1,  -- 修复：减1因为下面立即执行了第一次伤害
		NextTickTime = tick() + skillData.TickInterval,
		StartTime = tick(),
	}

	-- 立即执行第一次伤害（释放瞬间）
	local enemies = GetEnemiesInRange(position, skillData.Range / 2, "ally")
	for _, enemyUnit in ipairs(enemies) do
		DealDamageToUnit(enemyUnit, skillData.TickDamage, skillData.SkillId)
	end

	DebugLog(string.format("DOT效果 %s 创建成功, 总tick数: %d, 首次命中: %d 个敌人",
		effectId, totalTicks, #enemies))

	return effectId
end

--[[
处理DOT效果tick(由Heartbeat驱动)
]]
local function ProcessDOTEffects()
	local currentTime = tick()
	local toRemove = {}

	for effectId, effectData in pairs(ActiveDOTEffects) do
		if currentTime >= effectData.NextTickTime then
			if effectData.RemainingTicks > 0 then
				-- 执行伤害
				local enemies = GetEnemiesInRange(effectData.Position, effectData.Radius, "ally")
				for _, enemyUnit in ipairs(enemies) do
					DealDamageToUnit(enemyUnit, effectData.TickDamage, effectData.SkillId)
				end

				effectData.RemainingTicks = effectData.RemainingTicks - 1
				effectData.NextTickTime = currentTime + effectData.TickInterval
			else
				-- DOT效果结束
				table.insert(toRemove, effectId)
			end
		end
	end

	-- 移除结束的DOT效果
	for _, effectId in ipairs(toRemove) do
		DebugLog(string.format("DOT效果 %s 结束", effectId))
		ActiveDOTEffects[effectId] = nil
	end
end

--[[
生成技能特效
@param player Player - 释放技能的玩家
@param skillData table - 技能配置
@param position Vector3 - 释放位置
]]
local function SpawnSkillEffect(player, skillData, position)
	-- 从ReplicatedStorage/Skills/获取特效模板
	local skillsFolder = ReplicatedStorage:FindFirstChild("Skills")
	if not skillsFolder then
		DebugLog("Skills文件夹不存在")
		return
	end

	local effectTemplate = skillsFolder:FindFirstChild(skillData.ResourceName)
	if not effectTemplate then
		DebugLog(string.format("技能特效 %s 不存在", skillData.ResourceName))
		return
	end

	-- 克隆特效到Workspace
	local effectClone = effectTemplate:Clone()
	effectClone.Name = skillData.ResourceName .. "_Effect_" .. tick()

	-- 辅助函数：放置特效并自动抬高，避免埋入地面
	local function placeEffect(effect, pos)
		local targetCf = CFrame.new(pos)
		local sizeY = nil

		if effect:IsA("BasePart") then
			sizeY = effect.Size.Y
		else
			local _, extentsSize = effect:GetBoundingBox()
			sizeY = extentsSize.Y
		end

		-- 向上抬高半个高度，使底部贴地
		if sizeY then
			targetCf = targetCf + Vector3.new(0, sizeY * 0.5, 0)
		end

		if effect:IsA("Model") then
			effect:PivotTo(targetCf)
		else
			effect.CFrame = targetCf
		end
	end

	-- 设置位置（使用placeEffect自动处理高度偏移）
	if effectClone:IsA("BasePart") then
		placeEffect(effectClone, position)
		effectClone.Anchored = true
		effectClone.CanCollide = false
	elseif effectClone:IsA("Model") then
		placeEffect(effectClone, position)
	end

	effectClone.Parent = Workspace

	-- 定时移除特效
	task.delay(skillData.EffectDuration, function()
		if effectClone and effectClone.Parent then
			effectClone:Destroy()
		end
	end)

	-- 通知客户端(用于额外的客户端特效)
	if SkillEvents then
		local spawnEvent = SkillEvents:FindFirstChild("SpawnSkillEffect")
		if spawnEvent then
			spawnEvent:FireAllClients(skillData.SkillId, position, skillData.EffectDuration)
		end
	end

	DebugLog(string.format("技能特效 %s 已生成于 (%.1f, %.1f, %.1f)",
		skillData.ResourceName, position.X, position.Y, position.Z))
end

-- ==================== 公共接口 ====================

--[[
初始化技能系统
]]
function SkillSystem.Initialize()
	InitializeModules()
	InitializeEvents()

	-- 监听技能释放请求
	if SkillEvents then
		local requestCast = SkillEvents:FindFirstChild("RequestCastSkill")
		if requestCast then
			requestCast.OnServerEvent:Connect(function(player, skillId, position)
				SkillSystem.HandleCastSkillRequest(player, skillId, position)
			end)
		end

		-- 监听客户端请求同步技能背包
		local requestSync = SkillEvents:FindFirstChild("RequestSkillSync")
		if requestSync then
			requestSync.OnServerEvent:Connect(function(player)
				SkillSystem.SyncSkillInventory(player)
			end)
		end
	end

	-- 启动DOT效果处理循环
	game:GetService("RunService").Heartbeat:Connect(function()
		ProcessDOTEffects()
	end)

	print(GetLogPrefix(), "[SkillSystem] 技能系统初始化完成")
	return true
end

--[[
处理技能释放请求
@param player Player - 玩家
@param skillId number - 技能ID
@param position Vector3 - 释放位置
]]
function SkillSystem.HandleCastSkillRequest(player, skillId, position)
	local playerId = player.UserId

	-- 验证技能ID
	if not SkillConfig.IsValidSkill(skillId) then
		DebugLog(string.format("无效的技能ID: %s", tostring(skillId)))
		return SkillSystem.SendCastResponse(player, false, "无效的技能")
	end

	-- 检查冷却
	local lastCast = PlayerSkillCooldowns[playerId]
	if lastCast and (tick() - lastCast) < SKILL_COOLDOWN then
		return SkillSystem.SendCastResponse(player, false, "技能冷却中")
	end

	-- 检查玩家是否拥有该技能
	InitializeModules()
	local skillCount = 0
	if DataManager then
		skillCount = DataManager.GetSkillCount(player, skillId)
	end

	if skillCount <= 0 then
		return SkillSystem.SendCastResponse(player, false, "技能数量不足")
	end

	-- 扣除技能数量
	if DataManager then
		DataManager.RemoveSkill(player, skillId, 1)
		-- V3.0修复：保存数据到DataStore（使用节流保存避免频繁写入）
		DataManager.SavePlayerDataThrottled(player)
	end

	-- 更新冷却
	PlayerSkillCooldowns[playerId] = tick()

	-- 获取技能配置
	local skillData = SkillConfig.GetSkillById(skillId)

	-- 生成特效
	SpawnSkillEffect(player, skillData, position)

	-- 执行技能效果
	if skillData.EffectType == SkillConfig.EffectType.INSTANT then
		ExecuteInstantDamage(skillData, position)
	elseif skillData.EffectType == SkillConfig.EffectType.DOT then
		CreateDOTEffect(skillData, position)
	end

	-- 发送成功响应
	SkillSystem.SendCastResponse(player, true, "技能释放成功")

	-- 通知客户端更新技能背包
	SkillSystem.SyncSkillInventory(player)

	DebugLog(string.format("玩家 %s 释放技能 %s 于 (%.1f, %.1f, %.1f)",
		player.Name, skillData.Name, position.X, position.Y, position.Z))
end

--[[
发送技能释放响应
@param player Player - 玩家
@param success boolean - 是否成功
@param message string - 消息
]]
function SkillSystem.SendCastResponse(player, success, message)
	if SkillEvents then
		local responseEvent = SkillEvents:FindFirstChild("CastSkillResponse")
		if responseEvent then
			responseEvent:FireClient(player, success, message)
		end
	end
end

--[[
同步玩家技能背包
@param player Player - 玩家
]]
function SkillSystem.SyncSkillInventory(player)
	InitializeModules()

	local inventory = {}
	if DataManager then
		inventory = DataManager.GetSkillInventory(player)
	end

	if SkillEvents then
		local updateEvent = SkillEvents:FindFirstChild("SkillInventoryUpdate")
		if updateEvent then
			updateEvent:FireClient(player, inventory)
		end
	end
end

--[[
添加技能到玩家背包
@param player Player - 玩家
@param skillId number - 技能ID
@param count number - 数量
@return boolean - 是否成功
]]
function SkillSystem.AddSkill(player, skillId, count)
	if not SkillConfig.IsValidSkill(skillId) then
		return false
	end

	InitializeModules()
	if DataManager then
		DataManager.AddSkill(player, skillId, count)
		SkillSystem.SyncSkillInventory(player)
		return true
	end

	return false
end

--[[
获取玩家技能数量
@param player Player - 玩家
@param skillId number - 技能ID
@return number - 数量
]]
function SkillSystem.GetSkillCount(player, skillId)
	InitializeModules()
	if DataManager then
		return DataManager.GetSkillCount(player, skillId)
	end
	return 0
end

--[[
获取玩家所有技能
@param player Player - 玩家
@return table - 技能背包 {[skillId] = count}
]]
function SkillSystem.GetPlayerSkills(player)
	InitializeModules()
	if DataManager then
		return DataManager.GetSkillInventory(player)
	end
	return {}
end

return SkillSystem
