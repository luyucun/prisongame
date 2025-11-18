--[[
脚本名称: PhysicsManager
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/PhysicsManager
]]

--[[
物理管理系统
职责:
1. 管理玩家和兵种之间的碰撞关系
2. 禁用玩家与兵种之间的碰撞
3. 处理玩家和兵种的物理交互
4. V2.2新增：管理友军/敌军碰撞组，友军之间不碰撞
版本: V2.2
]]

local PhysicsManager = {}

-- 引用服务
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- 引用模块
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 跟踪已创建的碰撞组
local groupsCreated = false

-- ==================== 初始化 ====================

--[[
初始化物理管理系统
]]
function PhysicsManager.Initialize()
	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "初始化PhysicsManager...")
	end

	-- 创建碰撞组
	CreateCollisionGroups()

	-- 为现有玩家设置碰撞
	for _, player in ipairs(Players:GetPlayers()) do
		OnPlayerAdded(player)
	end

	-- 监听新玩家加入
	Players.PlayerAdded:Connect(OnPlayerAdded)

	return true
end

-- ==================== 碰撞组创建 ====================

--[[
创建必要的碰撞组（V2.2重构：Allies/Enemies分组）
]]
function CreateCollisionGroups()
	if groupsCreated then
		return
	end

	-- 创建玩家碰撞组
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Players")
	end)

	-- V2.2新增：创建友军碰撞组
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Allies")
	end)

	-- V2.2新增：创建敌军碰撞组
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Enemies")
	end)

	-- 设置碰撞矩阵
	pcall(function()
		-- 禁用玩家与友军碰撞
		PhysicsService:CollisionGroupSetCollidable("Players", "Allies", false)
		-- 禁用玩家与敌军碰撞
		PhysicsService:CollisionGroupSetCollidable("Players", "Enemies", false)

		-- ✅ 核心修复：禁用友军之间碰撞（解决100单位拥堵）
		PhysicsService:CollisionGroupSetCollidable("Allies", "Allies", false)

		-- V2.3策略选择：敌军之间碰撞
		-- 选项A(当前)：禁用碰撞 → 寻路稳定，但战斗时多敌可能重叠
		-- 选项B：启用碰撞 → 战斗更真实，但敌军行军可能拥堵（敌军战前是锚定的，问题不大）
		-- 建议：保持禁用（当前设置），除非战斗表现需要更多"挤压感"
		PhysicsService:CollisionGroupSetCollidable("Enemies", "Enemies", false)

		-- 启用友军与敌军碰撞（战斗时需要）
		PhysicsService:CollisionGroupSetCollidable("Allies", "Enemies", true)
	end)

	groupsCreated = true

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "✅ 碰撞组已创建：Players/Allies/Enemies")
		print(GameConfig.LOG_PREFIX, "   - 友军↔友军: 不碰撞 (解决拥堵)")
		print(GameConfig.LOG_PREFIX, "   - 敌军↔敌军: 不碰撞")
		print(GameConfig.LOG_PREFIX, "   - 友军↔敌军: 碰撞")
	end
end

-- ==================== 玩家处理 ====================

--[[
处理玩家加入事件
@param player Player
]]
function OnPlayerAdded(player)
	-- 等待玩家角色加载
	local character = player.Character or player.CharacterAdded:Wait()
	task.wait(0.1)

	-- 为玩家角色设置无碰撞组
	DisablePlayerCollisions(player, character)

	-- 监听角色重生
	local characterAddedConnection
	characterAddedConnection = player.CharacterAdded:Connect(function(newCharacter)
		task.wait(0.1)
		DisablePlayerCollisions(player, newCharacter)
	end)

	-- 监听玩家离开
	local playerRemovingConnection
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(removingPlayer)
		if removingPlayer == player then
			characterAddedConnection:Disconnect()
			playerRemovingConnection:Disconnect()
		end
	end)
end

--[[
为玩家禁用碰撞
@param player Player
@param character Model - 玩家角色
]]
function DisablePlayerCollisions(player, character)
	if not character then
		return
	end

	-- 获取玩家的所有Part
	local playerParts = character:GetDescendants()
	local addedCount = 0

	for _, part in ipairs(playerParts) do
		if part:IsA("BasePart") then
			local success, err = pcall(function()
				part.CollisionGroup = "Players"
				addedCount = addedCount + 1
			end)

			if not success and GameConfig.DEBUG_MODE then
				warn(GameConfig.LOG_PREFIX, "设置玩家Part碰撞组失败:", part:GetFullName(), err)
			end
		end
	end

	-- 监听后续动态添加的Part（如饰品、特效等）
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			pcall(function()
				descendant.CollisionGroup = "Players"
			end)
		end
	end)
end

-- ==================== 兵种处理 ====================

--[[
为已放置的兵种模型设置碰撞组（V2.2重构：根据team设置Allies/Enemies）
@param model Model - 兵种模型
@param team string - 阵营标识（可选）："ally"或"enemy"，默认"ally"
]]
function PhysicsManager.ConfigureUnitPhysics(model, team)
	if not model then
		return
	end

	-- V2.2修复：根据team参数决定碰撞组
	team = team or "ally"  -- 默认友军
	local collisionGroup = (team == "enemy") and "Enemies" or "Allies"

	-- 获取兵种模型的所有Part
	local unitParts = model:GetDescendants()
	local addedCount = 0

	for _, part in ipairs(unitParts) do
		if part:IsA("BasePart") then
			local success, err = pcall(function()
				part.CollisionGroup = collisionGroup
				addedCount = addedCount + 1
			end)

			if not success and GameConfig.DEBUG_MODE then
				warn(GameConfig.LOG_PREFIX, "设置兵种Part碰撞组失败:", part:GetFullName(), err)
			end
		end
	end

	-- 监听后续动态添加的Part（如特效、装备等）
	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			pcall(function()
				descendant.CollisionGroup = collisionGroup
			end)
		end
	end)

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, string.format("设置单位碰撞组: %s → %s (%d Parts)",
			model.Name, collisionGroup, addedCount))
	end
end

return PhysicsManager
