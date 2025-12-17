--[[
脚本名称: CollisionSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/CollisionSystem
版本: V2.5 寻路性能优化
职责: 管理兵种间的物理碰撞，防止拥堵导致寻路死循环
]]

local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local CollisionSystem = {}

-- 定义碰撞组名称
local UNIT_GROUP = "Units"
local PLAYER_GROUP = "Players" -- 可选

-- 调试开关
local DEBUG_MODE = false
local LOG_PREFIX = "[CollisionSystem]"

--[[
初始化碰撞系统
职责：
1. 创建Units碰撞组
2. 设置Units组内不发生碰撞（兵种间可穿模）
3. 监听新兵种生成并自动应用碰撞设置
]]
function CollisionSystem.Initialize()
	-- 1. 创建碰撞组（如果不存在）
	local success, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(UNIT_GROUP)
	end)

	if not success then
		-- 碰撞组可能已存在，这是正常的
		if DEBUG_MODE then
			print(LOG_PREFIX, "碰撞组已存在或创建失败:", err)
		end
	else
		if DEBUG_MODE then
			print(LOG_PREFIX, "✅ 创建碰撞组:", UNIT_GROUP)
		end
	end

	-- 2. 设置规则：Unit组 不与 Unit组 发生碰撞
	-- 这样兵种之间可以穿模，不会互相卡住
	local setSuccess, setErr = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(UNIT_GROUP, UNIT_GROUP, false)
	end)

	if setSuccess then
		-- print(LOG_PREFIX, "✅ 兵种间碰撞已关闭 - Units组内不碰撞")
	else
		warn(LOG_PREFIX, "❌ 设置碰撞规则失败:", setErr)
	end

	-- V5.2修复：Units组不应与Players组碰撞（玩家隔离墙/玩家角色均使用Players组）
	-- 否则会出现单位直冲“玩家隔离墙”(PlayerAirWall)后原地踏步卡住的问题
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(UNIT_GROUP, PLAYER_GROUP, false)
	end)

	-- 3. 监听新兵种生成（通过CollectionService的"Unit"标签）
	-- 如果兵种模型有"Unit"标签，会自动应用碰撞设置
	CollectionService:GetInstanceAddedSignal("Unit"):Connect(function(unit)
		if DEBUG_MODE then
			print(LOG_PREFIX, "检测到带Unit标签的模型:", unit.Name)
		end
		CollisionSystem.SetUnitCollision(unit)
	end)

	-- 4. 对已存在的带"Unit"标签的模型应用碰撞设置
	for _, unit in ipairs(CollectionService:GetTagged("Unit")) do
		CollisionSystem.SetUnitCollision(unit)
	end

	-- print(LOG_PREFIX, "✅ 碰撞系统初始化完成")
end

--[[
对单个兵种应用碰撞组
@param model Model - 兵种模型实例
]]
function CollisionSystem.SetUnitCollision(model)
	if not model then
		warn(LOG_PREFIX, "SetUnitCollision: model为空")
		return
	end

	local partCount = 0
	local rootPart = model:FindFirstChild("HumanoidRootPart")

	-- 遍历所有子部件，设置碰撞组
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = UNIT_GROUP
			partCount = partCount + 1

			-- V2.5性能优化：设置所有非根部件为无质量，减少惯性计算
			if part ~= rootPart then
				part.Massless = true
			end
		end
	end

	-- 监听后续添加的部件（动态生成的部件也会被设置）
	model.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = UNIT_GROUP
			-- 同样设置为无质量（排除根部件）
			if part ~= rootPart then
				part.Massless = true
			end
			if DEBUG_MODE then
				print(LOG_PREFIX, "新增部件已设置碰撞组:", part.Name)
			end
		end
	end)

	if DEBUG_MODE then
		print(string.format(
			"%s ✅ 设置兵种碰撞 - %s (%d个部件)",
			LOG_PREFIX,
			model.Name,
			partCount
		))
	end
end

--[[
批量设置多个兵种的碰撞
@param models table - 兵种模型数组
]]
function CollisionSystem.SetBatchUnitCollision(models)
	if not models or type(models) ~= "table" then
		warn(LOG_PREFIX, "SetBatchUnitCollision: 参数无效")
		return
	end

	local count = 0
	for _, model in ipairs(models) do
		if model and model:IsA("Model") then
			CollisionSystem.SetUnitCollision(model)
			count = count + 1
		end
	end

	if DEBUG_MODE then
		print(string.format(
			"%s ✅ 批量设置碰撞完成 - 共%d个兵种",
			LOG_PREFIX,
			count
		))
	end
end

--[[
获取碰撞组名称（供其他系统使用）
@return string - Units碰撞组名称
]]
function CollisionSystem.GetUnitCollisionGroup()
	return UNIT_GROUP
end

--[[
优化 Humanoid 性能（方案4：降低物理开销）
关闭不需要的 Humanoid 状态，极大节省物理开销
@param humanoid Humanoid - Humanoid实例
]]
function CollisionSystem.OptimizeHumanoid(humanoid)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn(LOG_PREFIX, "OptimizeHumanoid: humanoid无效")
		return
	end

	-- 关闭不需要的状态，极大节省物理开销
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	-- 战斗中如果不需要跳跃，也可以关掉
	-- humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	if DEBUG_MODE then
		print(string.format(
			"%s ✅ Humanoid性能优化完成 - %s",
			LOG_PREFIX,
			humanoid.Parent and humanoid.Parent.Name or "Unknown"
		))
	end
end

--[[
批量优化多个兵种的 Humanoid
@param models table - 兵种模型数组
]]
function CollisionSystem.OptimizeBatchHumanoids(models)
	if not models or type(models) ~= "table" then
		warn(LOG_PREFIX, "OptimizeBatchHumanoids: 参数无效")
		return
	end

	local count = 0
	for _, model in ipairs(models) do
		if model and model:IsA("Model") then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				CollisionSystem.OptimizeHumanoid(humanoid)
				count = count + 1
			end
		end
	end

	if DEBUG_MODE then
		print(string.format(
			"%s ✅ 批量优化Humanoid完成 - 共%d个兵种",
			LOG_PREFIX,
			count
		))
	end
end

return CollisionSystem
