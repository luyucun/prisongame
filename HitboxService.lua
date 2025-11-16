--[[
脚本名称: HitboxService
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/HitboxService
版本: V1.5.1
]]

--[[
碰撞判定服务
职责:
1. 提供服务端权威的近战命中判定
2. 使用 OverlapParams 替代 Touched 事件
3. 支持扇形角度过滤、距离过滤
4. 多段命中控制(同帧去重)
5. 友军碰撞忽略

优势:
- 服务端权威,防止客户端篡改
- 稳定可靠,不依赖物理引擎的Touched事件
- 支持精确的扇形判定
- 性能优化,使用空间查询而非全局遍历
]]

local HitboxService = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 私有变量 ====================

-- 存储上次命中帧记录 [attackerModel][targetModel] = frameNumber
local lastHitFrames = {}

-- 当前帧号
local currentFrame = 0

-- 是否已初始化
local isInitialized = false

-- ==================== 数据结构 ====================

--[[
HitboxConfig = {
    Radius = number,           -- 碰撞半径(studs)
    Angle = number,            -- 扇形角度(度数,0-180,180为全方位)
    Height = number,           -- 碰撞高度(studs)
    MaxTargets = number,       -- 最大命中目标数
}

HitResult = {
    Targets = {Model},         -- 命中的目标列表
    HitCount = number,         -- 命中数量
}
]]

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
	if BattleConfig.DEBUG_COMBAT_LOGS then
		print(GameConfig.LOG_PREFIX, "[HitboxService]", ...)
	end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[HitboxService]", ...)
end

--[[
计算两个向量之间的夹角(度数)
@param v1 Vector3 - 向量1
@param v2 Vector3 - 向量2
@return number - 夹角(0-180度)
]]
local function GetAngleBetweenVectors(v1, v2)
	-- 单位化向量
	local unit1 = v1.Unit
	local unit2 = v2.Unit

	-- 计算点积
	local dotProduct = unit1:Dot(unit2)

	-- 限制范围到[-1, 1]防止数值误差
	dotProduct = math.clamp(dotProduct, -1, 1)

	-- 计算角度(弧度转度数)
	local angleRadians = math.acos(dotProduct)
	local angleDegrees = math.deg(angleRadians)

	return angleDegrees
end

--[[
检查目标是否在攻击者的扇形范围内
@param attackerPos Vector3 - 攻击者位置
@param attackerLook Vector3 - 攻击者朝向
@param targetPos Vector3 - 目标位置
@param maxAngle number - 最大角度(度数)
@return boolean - 是否在扇形范围内
]]
local function IsInAttackAngle(attackerPos, attackerLook, targetPos, maxAngle)
	-- 计算攻击者到目标的向量
	local toTarget = (targetPos - attackerPos)

	-- 只考虑水平方向(忽略Y轴)
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	local lookDirection = Vector3.new(attackerLook.X, 0, attackerLook.Z)

	-- 检查是否为零向量
	if toTarget.Magnitude < 0.001 or lookDirection.Magnitude < 0.001 then
		return false
	end

	-- 计算夹角
	local angle = GetAngleBetweenVectors(lookDirection, toTarget)

	-- 判断是否在扇形范围内
	return angle <= maxAngle
end

--[[
检查是否为有效的可攻击目标
@param targetPart BasePart - 目标部件
@return Model|nil - 如果是有效目标返回模型,否则返回nil
]]
local function GetValidTargetModel(targetPart)
	if not targetPart or not targetPart:IsA("BasePart") then
		return nil
	end

	-- 向上查找父级模型
	local model = targetPart:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	-- 检查模型是否有Humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	-- 检查是否有HumanoidRootPart
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	return model
end

--[[
检查同帧是否已命中
@param attackerModel Model - 攻击者
@param targetModel Model - 目标
@return boolean - 是否已命中
]]
local function IsAlreadyHitThisFrame(attackerModel, targetModel)
	if not lastHitFrames[attackerModel] then
		return false
	end

	local lastFrame = lastHitFrames[attackerModel][targetModel]
	if not lastFrame then
		return false
	end

	-- 检查是否为同一帧
	return lastFrame == currentFrame
end

--[[
记录本次命中
@param attackerModel Model - 攻击者
@param targetModel Model - 目标
]]
local function RecordHit(attackerModel, targetModel)
	if not lastHitFrames[attackerModel] then
		lastHitFrames[attackerModel] = {}
	end

	lastHitFrames[attackerModel][targetModel] = currentFrame
end

-- ==================== 公共接口 ====================

--[[
初始化碰撞服务
@return boolean - 是否初始化成功
]]
function HitboxService.Initialize()
	if isInitialized then
		WarnLog("HitboxService已经初始化过了")
		return true
	end

	DebugLog("正在初始化HitboxService...")

	-- 连接帧更新,用于同帧去重
	RunService.Heartbeat:Connect(function()
		currentFrame = currentFrame + 1

		-- 每1000帧清理一次旧数据,防止内存泄漏
		if currentFrame % 1000 == 0 then
			for attacker, targets in pairs(lastHitFrames) do
				-- 检查攻击者是否还存在
				if not attacker or not attacker.Parent then
					lastHitFrames[attacker] = nil
				else
					-- 清理目标表中不存在的目标
					for target, _ in pairs(targets) do
						if not target or not target.Parent then
							targets[target] = nil
						end
					end
				end
			end
		end
	end)

	isInitialized = true
	DebugLog("HitboxService初始化完成")
	return true
end

--[[
创建碰撞配置
@param radius number - 碰撞半径
@param angle number - 扇形角度
@param height number - 碰撞高度
@param maxTargets number - 最大命中数
@return table - 碰撞配置
]]
function HitboxService.CreateHitboxConfig(radius, angle, height, maxTargets)
	return {
		Radius = radius or BattleConfig.HITBOX_DEFAULT_RADIUS,
		Angle = angle or BattleConfig.HITBOX_DEFAULT_ANGLE,
		Height = height or BattleConfig.HITBOX_DEFAULT_HEIGHT,
		MaxTargets = maxTargets or BattleConfig.HITBOX_DEFAULT_MAX_TARGETS,
	}
end

--[[
执行近战命中判定(核心接口) - V2.4优化版
改进：使用物理空间查询(GetPartBoundsInRadius)初选候选目标，再进行精确过滤
性能：从O(N)降至O(K)，K为半径内单位数，通常远小于N

@param attackerModel Model - 攻击者模型
@param targetTeam string - 目标队伍("Attack"或"Defense")
@param battleId number - 战斗ID
@param hitboxConfig table - 碰撞配置
@param unitManager table - 单位管理器引用(用于获取敌方单位列表)
@return table - 命中结果 {Targets = {Model}, HitCount = number}
]]
function HitboxService.ResolveMeleeHit(attackerModel, targetTeam, battleId, hitboxConfig, unitManager)
	-- 参数验证
	if not attackerModel or not attackerModel:IsA("Model") then
		WarnLog("ResolveMeleeHit失败: attackerModel无效")
		return {Targets = {}, HitCount = 0}
	end

	if not hitboxConfig then
		WarnLog("ResolveMeleeHit失败: hitboxConfig为空")
		return {Targets = {}, HitCount = 0}
	end

	-- 获取攻击者位置和朝向
	local attackerRoot = attackerModel:FindFirstChild("HumanoidRootPart")
	if not attackerRoot then
		WarnLog("ResolveMeleeHit失败: 攻击者没有HumanoidRootPart")
		return {Targets = {}, HitCount = 0}
	end

	local attackerPos = attackerRoot.Position
	local attackerLook = attackerRoot.CFrame.LookVector

	-- 结果列表
	local hitTargets = {}
	local hitCount = 0

	-- V2.4优化：使用物理空间查询代替全量遍历
	-- 步骤1: 使用GetPartBoundsInRadius获取半径内的候选Part
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {attackerModel}  -- 忽略自己

	-- 使用半径初选
	local candidateParts = Workspace:GetPartBoundsInRadius(attackerPos, hitboxConfig.Radius, overlapParams)

	-- 步骤2: 将Part映射到Model，并进行精确过滤
	local processedModels = {}  -- 防止重复处理同一个Model

	for _, part in ipairs(candidateParts) do
		-- 获取Part对应的Model
		local candidateModel = GetValidTargetModel(part)
		if not candidateModel then
			continue
		end

		-- 跳过已处理的Model
		if processedModels[candidateModel] then
			continue
		end
		processedModels[candidateModel] = true

		-- 跳过自己
		if candidateModel == attackerModel then
			continue
		end

		-- V2.4关键修复：使用GetUnitBattleInfo验证是否属于敌方阵营
		-- 必须验证battleId匹配且Team是敌方，否则会误伤友军
		if unitManager and unitManager.GetUnitBattleInfo then
			local candidateInfo = unitManager.GetUnitBattleInfo(candidateModel)

			-- 如果单位未注册或不在同一战斗中，跳过
			if not candidateInfo or candidateInfo.BattleId ~= battleId then
				continue
			end

			-- 如果不是目标队伍(敌方)，跳过(避免友军误伤)
			if candidateInfo.Team ~= targetTeam then
				continue
			end
		else
			-- 如果没有UnitManager接口，降级到不安全模式并警告
			WarnLog("ResolveMeleeHit警告: unitManager缺少GetUnitBattleInfo接口，无法过滤友军")
		end

		-- 跳过已经命中的目标(同帧去重)
		if IsAlreadyHitThisFrame(attackerModel, candidateModel) then
			continue
		end

		-- 获取目标位置
		local enemyRoot = candidateModel:FindFirstChild("HumanoidRootPart")
		if not enemyRoot then
			continue
		end

		local enemyPos = enemyRoot.Position

		-- 精确过滤1: 距离验证（冗余检查，确保精度）
		local distance = (enemyPos - attackerPos).Magnitude
		if distance > hitboxConfig.Radius then
			continue
		end

		-- 精确过滤2: 扇形角度过滤
		if hitboxConfig.Angle < 180 then
			if not IsInAttackAngle(attackerPos, attackerLook, enemyPos, hitboxConfig.Angle) then
				continue
			end
		end

		-- 精确过滤3: 高度过滤
		local heightDiff = math.abs(enemyPos.Y - attackerPos.Y)
		if heightDiff > hitboxConfig.Height then
			continue
		end

		-- 通过所有过滤,记录命中
		table.insert(hitTargets, candidateModel)
		RecordHit(attackerModel, candidateModel)
		hitCount = hitCount + 1

		-- 检查是否达到最大命中数
		if hitCount >= hitboxConfig.MaxTargets then
			break
		end
	end

	-- 调试输出
	if hitCount > 0 then
		DebugLog(string.format("命中判定: 攻击者=%s, 命中%d个目标",
			attackerModel.Name, hitCount))
	end

	return {
		Targets = hitTargets,
		HitCount = hitCount,
	}
end

--[[
过滤:按距离
@param attackerPos Vector3 - 攻击者位置
@param targetPos Vector3 - 目标位置
@param maxDistance number - 最大距离
@return boolean - 是否在范围内
]]
function HitboxService.FilterByDistance(attackerPos, targetPos, maxDistance)
	local distance = (targetPos - attackerPos).Magnitude
	return distance <= maxDistance
end

--[[
过滤:按扇形角度
@param attackerPos Vector3 - 攻击者位置
@param attackerLook Vector3 - 攻击者朝向
@param targetPos Vector3 - 目标位置
@param maxAngle number - 最大角度(度数)
@return boolean - 是否在扇形范围内
]]
function HitboxService.FilterByAngle(attackerPos, attackerLook, targetPos, maxAngle)
	return IsInAttackAngle(attackerPos, attackerLook, targetPos, maxAngle)
end

--[[
清理攻击者的命中记录
@param attackerModel Model - 攻击者模型
]]
function HitboxService.ClearAttackerHitRecords(attackerModel)
	if lastHitFrames[attackerModel] then
		lastHitFrames[attackerModel] = nil
	end
end

--[[
获取当前帧号(调试用)
@return number - 当前帧号
]]
function HitboxService.GetCurrentFrame()
	return currentFrame
end

return HitboxService
