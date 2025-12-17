--[[
脚本名称: CombatSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/CombatSystem
版本: V4.0 - 客户端AI迁移支持
]]

--[[
战斗系统
职责:
1. 管理兵种的战斗状态(血量、攻击阶段、是否存活)
2. 处理伤害计算
3. 处理死亡流程
4. 动画事件驱动的攻击系统(Idle→Attacking→Recovery)
5. 发送死亡通知给攻击者

V4.0 客户端AI迁移:
- 新增客户端攻击请求处理（RequestAttack事件）
- 新增位置校验逻辑（防作弊）
- 保留完整的伤害计算和死亡流程
- 支持服务端AI和客户端AI双模式运行

V1.5.1 重要改动:
- 攻击阶段从四阶段简化为三阶段(移除Windup和Release)
- 伤害判定完全由动画"Damage"事件触发
- 移除基于时间的伤害窗口计算
]]

local CombatSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService") -- 显式引用TweenService

-- 引用配置（从ReplicatedStorage获取共享配置）
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 私有变量 ====================

-- 存储所有兵种的战斗状态 [unitModel] = UnitCombatState
local unitStates = {}

-- 死亡事件
local unitDeathEvent = nil
-- V4.0新增：客户端死亡通知事件
local serverUnitDeathEvent = nil

-- Update连接
local updateConnection = nil

-- HitboxService 和 UnitManager 引用
local HitboxService = nil
local UnitManager = nil
local ProjectileSystem = nil  -- V1.5远程攻击支持
local WeaponEffectSystem = nil  -- V1.5.4远程武器特效支持

-- V1.5.12新增：集中管理死亡渐隐Tween，用于战役复活时一键取消
-- [unitModel] = { tweens = {Tween...}, connections = {RBXScriptConnection...} }
local activeDeathFades = {}

-- ==================== 数据结构 ====================

--[[
UnitCombatState = {
    UnitInstance = Model,        -- 兵种模型实例
    UnitId = string,             -- 兵种ID (如"Noob")
    Level = number,              -- 等级 (1-3)
    Team = string,               -- 阵营: "Attack" 或 "Defense"
    BattleId = number,           -- 所属战斗ID

    -- 战斗属性
    MaxHealth = number,          -- 最大生命值
    CurrentHealth = number,      -- 当前生命值
    Attack = number,             -- 攻击力
    AttackSpeed = number,        -- 攻击速度(秒/次)
    AttackRange = number,        -- 攻击距离
    MoveSpeed = number,          -- 移动速度

    -- 战斗状态
    IsAlive = boolean,           -- 是否存活
    CurrentTarget = Model,       -- 当前攻击目标
    State = string,              -- AI状态: "Idle", "Moving", "Attacking", "Dead"

    -- V1.5.1 新增攻击阶段相关
    AttackPhase = string,        -- 攻击阶段: "Idle", "Attacking", "Recovery"
    AttackStartTime = number,    -- 攻击开始时间(用于超时检测)
    RecoveryEndTime = number,    -- 冷却结束时间
    LastHitFrame = {},           -- 上次命中帧记录 [target] = frame (已移至HitboxService)
}
]]

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
	if BattleConfig.DEBUG_COMBAT_LOGS then
		print(GameConfig.LOG_PREFIX, "[CombatSystem]", ...)
	end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[CombatSystem]", ...)
end

--[[
驱动攻击阶段更新
]]
local function UpdateAttackPhases()
	local currentTime = tick()

	for unitModel, state in pairs(unitStates) do
		if not state.IsAlive then
			continue
		end

		-- 处理 Recovery 阶段
		if state.AttackPhase == BattleConfig.AttackPhase.RECOVERY then
			if currentTime >= state.RecoveryEndTime then
				-- 冷却结束,切换到 Idle
				state.AttackPhase = BattleConfig.AttackPhase.IDLE
				DebugLog(string.format("%s 冷却结束,进入Idle", state.UnitId))
			end
		end

		-- 处理 Attacking 阶段超时(防止动画失败导致卡死)
		if state.AttackPhase == BattleConfig.AttackPhase.ATTACKING then
			if currentTime - state.AttackStartTime > BattleConfig.ATTACK_TIMEOUT then
				WarnLog(string.format("%s 攻击超时,强制进入Recovery", state.UnitId))
				state.AttackPhase = BattleConfig.AttackPhase.RECOVERY
				state.RecoveryEndTime = currentTime + state.AttackSpeed
			end
		end
	end
end

-- ==================== 公共接口 ====================

--[[
初始化战斗系统
@return boolean - 是否初始化成功
]]
function CombatSystem.Initialize()
	DebugLog("正在初始化战斗系统...")

	-- 获取或创建死亡事件
	local eventsFolder = ReplicatedStorage:WaitForChild("Events")
	local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")

	if not battleEventsFolder then
		WarnLog("未找到BattleEvents文件夹,死亡通知将无法工作")
		return false
	end

	unitDeathEvent = battleEventsFolder:FindFirstChild("UnitDeath")

	if not unitDeathEvent then
		WarnLog("未找到UnitDeath事件,死亡通知将无法工作")
		return false
	end

	-- V4.0新增：获取客户端死亡通知事件
	local clientAIEvents = eventsFolder:FindFirstChild("ClientAIEvents")
	if clientAIEvents then
		serverUnitDeathEvent = clientAIEvents:FindFirstChild("ServerUnitDeath")
		if not serverUnitDeathEvent then
			WarnLog("未找到ServerUnitDeath事件,客户端AI死亡通知将无法工作")
		end
	end

	-- 获取HitboxService和UnitManager引用（使用类型断言）
	local SystemsFolder = ServerScriptService:WaitForChild("Systems")
	HitboxService = require(SystemsFolder:WaitForChild("HitboxService") :: ModuleScript)
	UnitManager = require(SystemsFolder:WaitForChild("UnitManager") :: ModuleScript)

	-- 启动Update循环(处理攻击阶段切换)
	updateConnection = RunService.Heartbeat:Connect(UpdateAttackPhases)

	-- V4.0新增：初始化客户端AI事件监听
	if BattleConfig.ENABLE_CLIENT_AI then
		CombatSystem.InitializeClientAIEvents()
		DebugLog("客户端AI事件监听已启动")
	end

	DebugLog("战斗系统初始化完成")
	return true
end

--[[
关闭战斗系统
]]
function CombatSystem.Shutdown()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	unitStates = {}

	DebugLog("战斗系统已关闭")
end

--[[
初始化兵种战斗状态
@param unitModel Model - 兵种模型实例
@param unitId string - 兵种ID
@param level number - 等级
@param team string - 阵营("Attack"或"Defense")
@param battleId number - 所属战斗ID
@param currentHealth number? - 可选，当前血量（用于战役中血量继承，不传则满血）
@return boolean - 是否初始化成功
]]
function CombatSystem.InitializeUnit(unitModel, unitId, level, team, battleId, currentHealth)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("InitializeUnit失败: unitModel无效")
		return false
	end

	if not UnitConfig.IsValidUnit(unitId) then
		WarnLog("InitializeUnit失败: 无效的unitId:", unitId)
		return false
	end

	-- 计算战斗属性
	local maxHealth = UnitConfig.CalculateHealth(unitId, level)
	local attack = UnitConfig.CalculateAttack(unitId, level)
	local attackSpeed = UnitConfig.GetAttackSpeed(unitId)
	local attackRange = UnitConfig.GetAttackRange(unitId)
	local moveSpeed = UnitConfig.GetMoveSpeed(unitId)

	-- V2.8.9修复：支持血量继承
	-- 如果传入了currentHealth，使用它（战役跨关卡血量继承）
	-- 否则使用maxHealth（新单位/复生/测试）
	local actualHealth = maxHealth
	if currentHealth ~= nil and type(currentHealth) == "number" then
		-- 确保血量在有效范围内：大于0且不超过最大值
		actualHealth = math.clamp(currentHealth, 1, maxHealth)
		DebugLog(string.format("血量继承: %s 传入血量=%d, 实际血量=%d/%d",
			unitId, currentHealth, actualHealth, maxHealth))
	end

	-- 创建战斗状态
	local combatState = {
		UnitInstance = unitModel,
		UnitId = unitId,
		Level = level,
		Team = team,
		BattleId = battleId,

		MaxHealth = maxHealth,
		CurrentHealth = actualHealth,  -- V2.8.9: 使用实际血量（可能是继承的残血）
		Attack = attack,
		AttackSpeed = attackSpeed,
		AttackRange = attackRange,
		MoveSpeed = moveSpeed,

		IsAlive = true,
		CurrentTarget = nil,
		State = BattleConfig.AIState.IDLE,

		-- V1.5.1 新增攻击阶段
		AttackPhase = BattleConfig.AttackPhase.IDLE,
		AttackStartTime = 0,
		RecoveryEndTime = 0,
	}

	-- 存储状态
	unitStates[unitModel] = combatState

	-- ✅ 关键修复：清除死亡标记！
	-- 当单位被重新初始化时，必须确保IsDead属性被清除
	-- 否则客户端AI会认为该单位已死亡，不会攻击
	unitModel:SetAttribute("IsDead", false)

	-- ✅ 关键修复：同步Humanoid.Health到CombatSystem状态
	-- 确保Humanoid.Health和CombatSystem.CurrentHealth一致
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Health = actualHealth    -- V2.8.9: 同步实际血量
		humanoid.MaxHealth = maxHealth
	end

	DebugLog(string.format("初始化兵种战斗状态: %s Lv.%d [%s] HP:%d/%d ATK:%d",
		unitId, level, team, actualHealth, maxHealth, attack))

	return true
end

--[[
获取兵种战斗状态
@param unitModel Model - 兵种模型实例
@return table|nil - 战斗状态,不存在返回nil
]]
function CombatSystem.GetUnitState(unitModel)
	return unitStates[unitModel]
end

--[[
检查兵种是否存活
@param unitModel Model - 兵种模型实例
@return boolean - 是否存活
]]
function CombatSystem.IsUnitAlive(unitModel)
	local state = unitStates[unitModel]
	if not state then
		return false
	end
	return state.IsAlive and state.CurrentHealth > 0
end

-- ==================== V1.5.1 新增: 攻击阶段管理 ====================

--[[
开始攻击(进入Attacking阶段)
@param unitModel Model - 兵种模型
@param target Model - 目标模型(可选,用于记录)
@return boolean - 是否成功开始攻击
]]
function CombatSystem.BeginAttack(unitModel, target)
	local state = unitStates[unitModel]

	if not state then
		WarnLog("BeginAttack失败: 兵种未初始化")
		return false
	end

	if not state.IsAlive then
		return false
	end

	-- 检查是否可以攻击(必须是Idle阶段)
	if state.AttackPhase ~= BattleConfig.AttackPhase.IDLE then
		return false
	end

	-- 进入 Attacking 阶段
	state.AttackPhase = BattleConfig.AttackPhase.ATTACKING
	state.AttackStartTime = tick()

	DebugLog(string.format("%s 开始攻击,进入Attacking阶段", state.UnitId))

	return true
end

--[[
动画"Damage"事件触发时调用(核心伤害判定接口)
@param unitModel Model - 攻击者模型
@return number - 命中目标数量
]]
function CombatSystem.OnDamageEvent(unitModel)
	local state = unitStates[unitModel]

	if not state then
		WarnLog("OnDamageEvent失败: 兵种未初始化")
		return 0
	end

	if not state.IsAlive then
		WarnLog(string.format("%s OnDamageEvent被调用,但单位已死亡", state.UnitId))
		return 0
	end

	-- 验证攻击阶段(必须是Attacking)
	if state.AttackPhase ~= BattleConfig.AttackPhase.ATTACKING then
		WarnLog(string.format("%s OnDamageEvent被调用,但不在Attacking阶段(当前:%s)",
			state.UnitId, state.AttackPhase))
		return 0
	end

	-- 获取战斗配置
	local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)

	-- 创建碰撞配置
	local hitboxConfig = HitboxService.CreateHitboxConfig(
		combatProfile.HitboxRadius,
		combatProfile.HitboxAngle,
		combatProfile.HitboxHeight,
		combatProfile.HitboxMaxTargets
	)

	-- 近战命中源定位：优先Attachment，再部件，再HRP
	local attackerRoot = unitModel:FindFirstChild("HumanoidRootPart")
	local sourcePart = nil

	if combatProfile.HitboxPartName and combatProfile.HitboxPartName ~= "" then
		sourcePart = unitModel:FindFirstChild(combatProfile.HitboxPartName, true)
	end

	if not sourcePart then
		local weaponName = UnitConfig.GetWeaponName(state.UnitId)
		if weaponName and weaponName ~= "" then
			sourcePart = unitModel:FindFirstChild(weaponName, true)
		end
	end

	if not sourcePart then
		sourcePart = unitModel:FindFirstChild("RightHand") or attackerRoot
	end

	local originCFrame = attackerRoot and attackerRoot.CFrame or unitModel:GetPivot()
	local sourceCFrame = originCFrame

	-- 如果当前有目标，记录目标根部信息用于前向偏移
	local currentTarget = state.CurrentTarget
	local targetRoot = nil
	if currentTarget and currentTarget.Parent then
		targetRoot = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
	end

	if sourcePart and sourcePart:IsA("BasePart") then
		sourceCFrame = sourcePart.CFrame
	end

	if combatProfile.HitboxAttachmentName and combatProfile.HitboxAttachmentName ~= "" and sourcePart then
		local attach = sourcePart:FindFirstChild(combatProfile.HitboxAttachmentName)
		if attach and attach:IsA("Attachment") then
			sourceCFrame = attach.WorldCFrame
		end
	end

	-- 稳定命中源：位置扎根于HRP前方，保持源部件的高度差，朝向用HRP
	if attackerRoot then
		local heightDiff = sourceCFrame.Position.Y - attackerRoot.Position.Y
		local forwardOffset = (combatProfile.ContactOffset or 0.5) + 1.0 -- 基础前伸1 + 补偿

		-- 如果有目标且在身前，使用到目标的距离来限定前伸，避免站停过远
		if targetRoot then
			local flatDir = targetRoot.Position - attackerRoot.Position
			flatDir = Vector3.new(flatDir.X, 0, flatDir.Z)
			local planarDist = flatDir.Magnitude
			if planarDist > 0 then
				flatDir = flatDir.Unit
				-- 让命中中心落在两者之间（靠近敌人一点），并预留半个半径
				-- V3.0修复：确保clamp的max >= min，避免planarDist过小时报错
				local clampMin = 0.5
				local clampMax = math.max(planarDist, clampMin)  -- 确保max >= min
				local desired = math.clamp(planarDist - math.min((combatProfile.HitboxRadius or 3), 1.5), clampMin, clampMax)
				forwardOffset = desired
				attackerRoot.CFrame = CFrame.lookAt(attackerRoot.Position, attackerRoot.Position + flatDir) -- 再次确保朝向
			end
		end

		local basePos = attackerRoot.Position + attackerRoot.CFrame.LookVector * forwardOffset + Vector3.new(0, heightDiff, 0)
		originCFrame = CFrame.new(basePos, basePos + attackerRoot.CFrame.LookVector)
	else
		originCFrame = sourceCFrame
	end

	if combatProfile.HitboxOffset then
		local offset = combatProfile.HitboxOffset
		originCFrame = originCFrame * CFrame.new(offset.X, offset.Y, offset.Z)
	end

	hitboxConfig.Shape = combatProfile.HitboxShape or "Sphere"
	hitboxConfig.SourceCFrame = originCFrame
	-- 角度过滤用角色朝向，避免手部局部朝向导致误过滤
	hitboxConfig.ForwardVector = attackerRoot and attackerRoot.CFrame.LookVector or originCFrame.LookVector
	hitboxConfig.Length = combatProfile.HitboxLength
	hitboxConfig.BoxSize = combatProfile.HitboxBoxSize
	hitboxConfig.DebugEnabled = BattleConfig.DEBUG_SHOW_MELEE_HITBOX
	hitboxConfig.DebugDuration = BattleConfig.DEBUG_HITBOX_DURATION
	hitboxConfig.DebugColor = BattleConfig.DEBUG_HITBOX_COLOR_GOOD

	-- 🔍 调试: 输出Hitbox配置
	DebugLog(string.format("%s Hitbox配置: Radius=%.1f, Angle=%.1f, Height=%.1f, MaxTargets=%d",
		state.UnitId, hitboxConfig.Radius, hitboxConfig.Angle, hitboxConfig.Height, hitboxConfig.MaxTargets))

	-- 获取敌方队伍
	local enemyTeam = UnitManager.GetEnemyTeam(state.Team)
	if not enemyTeam then
		WarnLog("OnDamageEvent失败: 无法获取敌方队伍")
		return 0
	end

	-- 🔍 调试: 输出敌方队伍信息
	if BattleConfig.DEBUG_COMBAT_LOGS then
		local enemyUnits = UnitManager.GetBattleUnits(state.BattleId, enemyTeam)
		local enemyCount = enemyUnits and #enemyUnits or 0
		print(GameConfig.LOG_PREFIX, "[CombatSystem]", string.format("%s 敌方队伍[%s]共有%d个单位", state.UnitId, tostring(enemyTeam), enemyCount))
	end

	-- 执行命中判定
	local hitResult = HitboxService.ResolveMeleeHit(
		unitModel,
		enemyTeam,
		state.BattleId,
		hitboxConfig,
		UnitManager
	)

	-- 对命中的目标造成伤害
	local hitCount = 0
	for _, target in ipairs(hitResult.Targets) do
		-- V1.5.1 Bug修复: 检查目标是否还活着,避免对尸体造成伤害
		if CombatSystem.IsUnitAlive(target) then
			if CombatSystem.TakeDamage(target, state.Attack, unitModel) then
				hitCount = hitCount + 1
			end
		end
	end

	-- 进入 Recovery 阶段
	state.AttackPhase = BattleConfig.AttackPhase.RECOVERY
	state.RecoveryEndTime = tick() + state.AttackSpeed

	DebugLog(string.format("%s Damage事件触发,命中%d个目标,进入Recovery(%.1f秒)",
		state.UnitId, hitCount, state.AttackSpeed))

	return hitCount
end

--[[
远程单位动画"Damage"事件触发时调用(发射子弹)
@param unitModel Model - 攻击者模型
@param target Model - 目标模型
@return boolean - 是否成功发射子弹
]]
function CombatSystem.OnRangedDamageEvent(unitModel, target)
	local state = unitStates[unitModel]

	if not state then
		WarnLog("OnRangedDamageEvent失败: 兵种未初始化")
		return false
	end

	if not state.IsAlive then
		return false
	end

	-- 验证攻击阶段(必须是Attacking)
	if state.AttackPhase ~= BattleConfig.AttackPhase.ATTACKING then
		WarnLog(string.format("%s OnRangedDamageEvent被调用,但不在Attacking阶段(当前:%s)",
			state.UnitId, state.AttackPhase))
		return false
	end

	-- 检查目标是否还存活
	if not target or not target.Parent or not CombatSystem.IsUnitAlive(target) then
		DebugLog(string.format("%s 目标已死亡或不存在,取消发射子弹", state.UnitId))
		-- 即使目标死亡，也进入Recovery阶段（不让攻击卡住）
		state.AttackPhase = BattleConfig.AttackPhase.RECOVERY
		state.RecoveryEndTime = tick() + state.AttackSpeed
		return false
	end

	-- 修复4: 检查目标距离是否在射程内
	-- 🔧 V1.5.2优化：使用攻击距离+容差作为有效射程，而非脱离阈值
	-- 理由：只要在攻击状态就应该能发射，距离检查不应过于严格
	local unitRoot = unitModel:FindFirstChild("HumanoidRootPart")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if unitRoot and targetRoot then
		local distance = (targetRoot.Position - unitRoot.Position).Magnitude
		-- 使用攻击距离 * 1.15 作为最大有效射程（稍微宽松一些）
		local maxRange = state.AttackRange * 1.15

		if distance > maxRange then
			DebugLog(string.format("%s 目标距离%.1f超出最大有效射程%.1f，取消发射",
				state.UnitId, distance, maxRange))
			-- 进入Recovery阶段，让AI继续判断是否脱离
			state.AttackPhase = BattleConfig.AttackPhase.RECOVERY
			state.RecoveryEndTime = tick() + state.AttackSpeed
			return false
		end
	end

	-- 获取ProjectileSpeed
	local projectileSpeed = UnitConfig.GetProjectileSpeed(state.UnitId)
	if not projectileSpeed or projectileSpeed <= 0 then
		WarnLog(string.format("%s ProjectileSpeed无效: %s, 无法发射子弹",
			state.UnitId, tostring(projectileSpeed)))
		-- 进入Recovery阶段
		state.AttackPhase = BattleConfig.AttackPhase.RECOVERY
		state.RecoveryEndTime = tick() + state.AttackSpeed
		return false
	end

	-- 引用ProjectileSystem（延迟加载，使用类型断言）
	if not ProjectileSystem then
		local projectileModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("ProjectileSystem")
		if projectileModule then
			ProjectileSystem = require(projectileModule :: ModuleScript)
		end
	end

	-- ⭐⭐ V1.5.4 播放远程武器特效 ⭐⭐
	-- 在发射子弹前播放枪口特效（Beam、PointLight、ParticleEmitter）
	if not WeaponEffectSystem then
		local effectModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("WeaponEffectSystem")
		if effectModule then
			WeaponEffectSystem = require(effectModule :: ModuleScript)
		end
	end

	local weaponName = UnitConfig.GetWeaponName(state.UnitId)
	if weaponName and weaponName ~= "" then
		-- 播放武器特效（内部有容错处理，失败不影响战斗）
		WeaponEffectSystem.PlayWeaponEffect(unitModel, weaponName)
	end

	-- ⭐⭐ 发射子弹 ⭐⭐
	local projectile = ProjectileSystem.CreateProjectile(
		unitModel,     -- 攻击者
		target,        -- 目标
		state.Attack,  -- 伤害值
		projectileSpeed -- 子弹速度
	)

	if projectile then
		DebugLog(string.format("%s 成功发射子弹, 目标:%s, 伤害:%d, 速度:%d",
			state.UnitId,
			CombatSystem.GetUnitState(target) and CombatSystem.GetUnitState(target).UnitId or "Unknown",
			state.Attack,
			projectileSpeed))
	else
		WarnLog(string.format("%s 发射子弹失败", state.UnitId))
	end

	-- 进入 Recovery 阶段
	state.AttackPhase = BattleConfig.AttackPhase.RECOVERY
	state.RecoveryEndTime = tick() + state.AttackSpeed

	DebugLog(string.format("%s 远程攻击完成,进入Recovery(%.1f秒)",
		state.UnitId, state.AttackSpeed))

	return projectile ~= nil
end

--[[
检查是否可以攻击
@param unitModel Model - 兵种模型
@return boolean - 是否可以攻击
]]
function CombatSystem.CanAttack(unitModel)
	local state = unitStates[unitModel]

	if not state then
		return false
	end

	if not state.IsAlive then
		return false
	end

	-- 必须在Idle阶段才能攻击
	return state.AttackPhase == BattleConfig.AttackPhase.IDLE
end

--[[
获取攻击阶段
@param unitModel Model - 兵种模型
@return string|nil - 攻击阶段
]]
function CombatSystem.GetAttackPhase(unitModel)
	local state = unitStates[unitModel]
	if not state then
		return nil
	end
	return state.AttackPhase
end

--[[
重置攻击阶段到Idle（用于目标死亡等情况）
@param unitModel Model - 兵种模型
@return boolean - 是否成功重置
]]
function CombatSystem.ResetAttackPhase(unitModel)
	local state = unitStates[unitModel]
	if not state then
		return false
	end

	if not state.IsAlive then
		return false
	end

	-- 重置攻击阶段到Idle，允许立即开始新的攻击
	local previousPhase = state.AttackPhase
	state.AttackPhase = BattleConfig.AttackPhase.IDLE
	state.AttackStartTime = 0
	state.RecoveryEndTime = 0

	DebugLog(string.format("%s 攻击阶段重置: %s → Idle", state.UnitId, previousPhase or "nil"))

	return true
end

-- ==================== 伤害与死亡 ====================

--[[
兵种受到伤害
@param unitModel Model - 受伤的兵种模型
@param damage number - 伤害值
@param attacker Model - 攻击者模型(可选)
@return boolean - 是否造成了伤害
]]
function CombatSystem.TakeDamage(unitModel, damage, attacker)
	local state = unitStates[unitModel]

	if not state then
		-- V1.5.1 优化: 改为DebugLog而非WarnLog(已死单位重复伤害是预期行为)
		DebugLog("TakeDamage: 兵种已死亡或未初始化")
		return false
	end

	if not state.IsAlive then
		return false
	end

	-- 扣除血量
	state.CurrentHealth = state.CurrentHealth - damage

	-- V4.1修复：同步血量到Humanoid.Health，让客户端AI能正确判断目标死亡
	local humanoid = unitModel:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Health = math.max(0, state.CurrentHealth)
	end

	DebugLog(string.format("%s受到%d伤害, 剩余HP:%d/%d",
		state.UnitId, damage, state.CurrentHealth, state.MaxHealth))

	-- V1.5.1新增: 通知所有客户端显示伤害数字
	if BattleConfig.ENABLE_DAMAGE_NUMBERS then
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
			if battleEventsFolder then
				local showDamageNumberEvent = battleEventsFolder:FindFirstChild("ShowDamageNumber")
				if showDamageNumberEvent then
					-- V2.5新增：扩展事件参数，加入阵营信息
					-- 获取攻击者的Team属性
					local attackerTeam = attacker and attacker:GetAttribute("Team") or nil
					local targetTeam = state.Team
					-- 发送给所有客户端: 单位模型, 伤害值, 攻击者阵营, 被击中者阵营
					showDamageNumberEvent:FireAllClients(unitModel, damage, attackerTeam, targetTeam)
				end
			end
		end
	end

	-- V2.3新增: 通知所有客户端血量更新
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
		if battleEventsFolder then
			local unitHealthUpdateEvent = battleEventsFolder:FindFirstChild("UnitHealthUpdate")
			if unitHealthUpdateEvent then
				-- 发送给所有客户端: 单位模型, 当前血量, 最大血量
				unitHealthUpdateEvent:FireAllClients(unitModel, state.CurrentHealth, state.MaxHealth)
			end
		end
	end

	-- 检查是否死亡
	if state.CurrentHealth <= 0 then
		state.CurrentHealth = 0
		CombatSystem.KillUnit(unitModel, attacker)
	end

	return true
end

--[[
治疗兵种(预留接口)
@param unitModel Model - 兵种模型
@param amount number - 治疗量
@return boolean - 是否治疗成功
]]
function CombatSystem.Heal(unitModel, amount)
	local state = unitStates[unitModel]

	if not state then
		return false
	end

	if not state.IsAlive then
		return false
	end

	state.CurrentHealth = math.min(state.CurrentHealth + amount, state.MaxHealth)

	DebugLog(string.format("%s恢复%d生命值, 当前HP:%d/%d",
		state.UnitId, amount, state.CurrentHealth, state.MaxHealth))

	-- V2.3新增: 通知所有客户端血量更新
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
		if battleEventsFolder then
			local unitHealthUpdateEvent = battleEventsFolder:FindFirstChild("UnitHealthUpdate")
			if unitHealthUpdateEvent then
				-- 发送给所有客户端: 单位模型, 当前血量, 最大血量
				unitHealthUpdateEvent:FireAllClients(unitModel, state.CurrentHealth, state.MaxHealth)
			end
		end
	end

	return true
end

--[[
杀死兵种 - V1.5.11 修复复生透明度竞态版本
@param unitModel Model - 兵种模型
@param killer Model - 击杀者模型(可选)

流程（关键：先播死亡动画再停AI，确保无缝过渡）：
1. 标记死亡状态
2. 从系统中注销 → 触发死亡事件
3. 播放死亡动画
4. 停止AI
5. 2.9秒后销毁/隐藏
]]
function CombatSystem.KillUnit(unitModel, killer)
	local state = unitStates[unitModel]

	if not state then
		WarnLog("KillUnit失败: 兵种未初始化")
		return
	end

	if not state.IsAlive then
		return  -- 已经死亡,不重复处理
	end

	-- 标记为死亡
	state.IsAlive = false
	state.State = BattleConfig.AIState.DEAD
	state.CurrentHealth = 0
	state.AttackPhase = BattleConfig.AttackPhase.IDLE

	-- V4.6修复：死亡瞬间收回网络所有权 + 清理物理
	local humanoid = unitModel:FindFirstChild("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	-- 步骤1：立即收回网络所有权，确保死亡过程由服务端接管
	if rootPart then
		pcall(function()
			rootPart:SetNetworkOwner(nil)
		end)
	end

	-- 步骤2：清理所有BodyMover/Constraint推力，防止残余推力抬尸
	for _, child in ipairs(unitModel:GetDescendants()) do
		if child:IsA("BodyForce") or child:IsA("BodyVelocity") or child:IsA("BodyGyro")
			or child:IsA("BodyPosition") or child:IsA("BodyAngularVelocity")
			or child:IsA("VectorForce") or child:IsA("AlignPosition") or child:IsA("AlignOrientation")
			or child:IsA("LinearVelocity") or child:IsA("AngularVelocity") then
			pcall(function() child:Destroy() end)
		end
	end

	-- 步骤3：设置Humanoid状态
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid.Health = 0
		humanoid:Move(Vector3.zero)
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		-- 强制设置为Physics状态，让角色像布娃娃一样倒下，防止飞天
		humanoid.PlatformStand = true
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end

	-- 步骤4：禁用碰撞 + 清零速度（在SetNetworkOwner之后再做一遍兜底）
	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	-- 禁用除HumanoidRootPart外的所有部件碰撞，保留HRP碰撞让角色能倒在地上
	for _, part in ipairs(unitModel:GetDescendants()) do
		if part:IsA("BasePart") and part ~= rootPart then
			part.CanCollide = false
		end
	end

	-- HumanoidRootPart保持碰撞开启，让角色能正常倒在地面上
	if rootPart then
		rootPart.CanCollide = true
	end

	-- 步骤5：清零速度，让角色自然倒地
	if rootPart then
		-- 清零速度，防止残余推力
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		-- 不锚定，让死亡动画能正常播放（角色倒地）
		-- 死亡动画会让角色自然倒在地上
		rootPart.Anchored = false

		-- 步骤6：持续监控速度，防止死亡动画或其他因素导致飞天
		-- 在死亡后的前1秒内，每0.1秒检查一次速度，如果向上速度过大就清零
		local velocityCheckCount = 0
		local maxChecks = 10  -- 检查10次（1秒）
		local checkInterval = 0.1

		local function checkVelocity()
			velocityCheckCount = velocityCheckCount + 1
			if velocityCheckCount > maxChecks then
				return  -- 停止检查
			end

			if not unitModel or not unitModel.Parent or not rootPart or not rootPart.Parent then
				return  -- 单位已被移除
			end

			-- 检查向上速度，如果Y轴速度大于5就清零（防止飞天）
			local velocity = rootPart.AssemblyLinearVelocity
			if velocity.Y > 5 or velocity.Y < -20 then
				rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.5, 0, velocity.Z * 0.5)
				rootPart.AssemblyAngularVelocity = Vector3.zero
			end

			-- 继续下一次检查
			task.delay(checkInterval, checkVelocity)
		end

		-- 开始第一次检查
		task.delay(checkInterval, checkVelocity)
	end

	unitModel:SetAttribute("IsDead", true)

	DebugLog(string.format("%s [%s] 已死亡", state.UnitId, state.Team))

	-- 保存unitId用于后续日志
	local unitId = state.UnitId
	local battleId = state.BattleId
	local unitLevel = state.Level or 1

	-- V3.4新增: 发放击杀金币奖励
	-- 只有敌方单位(Defense队)被击杀时才发放奖励给玩家
	if state.Team == "Defense" and battleId then
		-- 计算击杀金币（基础值 * 等级）
		local killReward = UnitConfig.GetKillRewardByLevel(unitId, unitLevel)

		-- 通过BattleManager获取战斗实例和玩家ID
		local BattleManager = nil
		local bmModule = ServerScriptService:FindFirstChild("Systems") and ServerScriptService.Systems:FindFirstChild("BattleManager")
		if bmModule then
			BattleManager = require(bmModule :: ModuleScript)
		end

		if BattleManager and BattleManager.GetBattle then
			local battle = BattleManager.GetBattle(battleId)
			if battle and battle.PlayerId then
				-- 获取玩家实例
				local Players = game:GetService("Players")
				local player = Players:GetPlayerByUserId(battle.PlayerId)
				if player then
					-- 加载CurrencySystem发放金币
					local CurrencySystem = nil
					local csModule = ServerScriptService:FindFirstChild("Systems") and ServerScriptService.Systems:FindFirstChild("CurrencySystem")
					if csModule then
						CurrencySystem = require(csModule :: ModuleScript)
					end

					if CurrencySystem then
						-- V3.4.1修改：使用AddCoinsFromBattle触发金币表现效果
						CurrencySystem.AddCoinsFromBattle(player, killReward, battleId)
						DebugLog(string.format("[V3.4] 击杀金币: 玩家 %s 击杀 %s(Lv.%d) 获得 %d 金币",
							player.Name, unitId, unitLevel, killReward))
					end
				end
			end
		end
	end

	-- V2.9.3新增：立即隐藏死亡单位头顶的所有UI（血条、等级等）
	local head = unitModel:FindFirstChild("Head")
	if head then
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("BillboardGui") then
				child.Enabled = false
			end
		end
		DebugLog(string.format("%s 头顶UI已隐藏", unitId))
	end

	-- V1.5.1 Bug修复: 从UnitManager中注销单位(必须在清除unitStates之前)
	if UnitManager then
		UnitManager.UnregisterUnit(unitModel)
		DebugLog(string.format("%s 已从UnitManager注销", unitId))
	end

	-- 立即从状态表中移除，避免其他系统访问死亡单位
	unitStates[unitModel] = nil

	-- 触发死亡事件(通知攻击者)
	if unitDeathEvent then
		unitDeathEvent:Fire(unitModel, killer, battleId)
	end

	-- V4.0新增：通知客户端单位死亡（客户端AI模式下）
	if BattleConfig.ENABLE_CLIENT_AI and serverUnitDeathEvent then
		-- 获取战斗对应的玩家
		local BattleManager = nil
		local bmModule = ServerScriptService:FindFirstChild("Systems") and ServerScriptService.Systems:FindFirstChild("BattleManager")
		if bmModule then
			BattleManager = require(bmModule :: ModuleScript)
		end

		if BattleManager and BattleManager.GetBattle then
			local battle = BattleManager.GetBattle(battleId)
			if battle and battle.PlayerId then
				local Players = game:GetService("Players")
				local player = Players:GetPlayerByUserId(battle.PlayerId)
				if player then
					serverUnitDeathEvent:FireClient(player, battleId, unitModel, killer)
					DebugLog(string.format("[V4.0] 已通知客户端单位死亡: %s (BattleId=%d)", unitId, battleId))
				end
			end
		end
	end

	-- V4.6修复：客户端AI模式下，死亡动画由客户端播放，服务端不处理
	-- 只有服务端AI模式才需要服务端播放死亡动画
	if not BattleConfig.ENABLE_CLIENT_AI then
		-- ===== 服务端AI模式：播放死亡动画 =====
		local unitAIModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("UnitAI")
		if not unitAIModule then
			WarnLog("无法加载UnitAI模块，跳过死亡动画")
			return
		end
		local UnitAI = require(unitAIModule :: ModuleScript)
		local deathAnimationId = UnitConfig.GetDeathAnimationId(unitId)

		-- 步骤1: 播放死亡动画（立刻禁用Animate，高优先级Fade=0确保立即生效）
		UnitAI.BeginDeathAnimation(unitModel, deathAnimationId, unitId)

		-- 步骤2: 停止AI（参数：瞬停Fade=0，禁用Animate，无MoveTo）
		-- 此时死亡动画已在播放，StopAI只会清理AI的轨道，不会干扰死亡动画
		UnitAI.StopAI(unitModel, {
			skipMoveTo = true,        -- 防止MoveTo把尸体"拉起"
			disableAnimate = true,    -- 再次确认禁用Animate
			stopFadeTime = 0          -- 瞬停AI轨道，无淡出延迟
		})
	end

	-- 步骤3: 固定2.9秒后销毁或隐藏模型
	-- 记录预定移除时间供渐隐使用
	local removalTime = os.clock() + 2.9
	unitModel:SetAttribute("DeathRemovalTime", removalTime)

	-- V3.8新增：死亡后渐隐效果（倒地后逐渐变透明）
	-- 渐隐开始延迟1.5秒（让死亡动画先播放完大部分），渐隐持续1.4秒
	local fadeStartDelay = 1.5
	local fadeDuration = 1.4

	-- V2.0.1修复：战役单位死亡时保留实例用于重生
	-- V3.8修复：使用属性标记来防止复生后被错误隐藏（竞态条件）
	-- V1.5.12修复：必须在task.delay之前设置标记，防止竞态
	unitModel:SetAttribute("PendingDeathHide", true)

	-- V1.5.12 [修复核心]: 使用任务延迟执行渐隐，并添加事件监听以支持中途取消
	-- 同时将Tween注册到集中管理表，支持CancelDeathFade一键取消
	task.delay(fadeStartDelay, function()
		if not unitModel or not unitModel.Parent then return end

		-- 1. 检查是否已经被复生（如果复生，PendingDeathHide 会被 CampaignManager 置为 nil）
		local pendingHide = unitModel:GetAttribute("PendingDeathHide")
		if not pendingHide then
			DebugLog(string.format("%s 跳过渐隐：单位已被复生", unitId))
			return
		end

		-- 2. 收集所有需要渐隐的对象，并保存原始透明度
		local fadeTargets = {}
		for _, inst in ipairs(unitModel:GetDescendants()) do
			if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
				-- 只记录一次原始透明度，避免重复覆盖
				if inst:GetAttribute("_OrigTrans") == nil then
					inst:SetAttribute("_OrigTrans", inst.Transparency)
				end
				table.insert(fadeTargets, inst)
			end
		end

		-- 3. 创建 Tweens
		local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		local tweens = {}
		local connections = {}

		for _, inst in ipairs(fadeTargets) do
			local success, tween = pcall(function()
				return TweenService:Create(inst, tweenInfo, {Transparency = 1})
			end)
			if success and tween then
				table.insert(tweens, tween)
				tween:Play()
			end
		end

		DebugLog(string.format("%s 开始渐隐效果，共%d个对象", unitId, #fadeTargets))

		-- 4. [关键修复] 使用 GetAttributeChangedSignal 监听取消信号
		-- 这样当 CampaignManager 执行 SetAttribute("PendingDeathHide", nil) 时，渐隐会立即停止
		local connection
		connection = unitModel:GetAttributeChangedSignal("PendingDeathHide"):Connect(function()
			local stillPending = unitModel:GetAttribute("PendingDeathHide")
			if not stillPending then
				-- 复生发生了！立即停止所有 Tween
				for _, tween in ipairs(tweens) do
					pcall(function()
						tween:Cancel()
						-- Cancel后Transparency会停留在当前值，由CampaignManager负责设回0
					end)
				end

				-- 断开连接，防止内存泄漏
				if connection then
					connection:Disconnect()
					connection = nil
				end
				-- 从集中管理表移除
				CombatSystem.UnregisterDeathFade(unitModel)
				DebugLog(string.format("%s 渐隐Tween已立即取消：单位已被复生", unitId))
			end
		end)
		table.insert(connections, connection)

		-- 5. 如果模型被销毁，也要断开连接
		local destroyConnection
		destroyConnection = unitModel.AncestryChanged:Connect(function()
			if not unitModel.Parent then
				if connection then connection:Disconnect() connection = nil end
				if destroyConnection then destroyConnection:Disconnect() destroyConnection = nil end
				-- 停止Tweens
				for _, tween in ipairs(tweens) do pcall(function() tween:Cancel() end) end
				-- 从集中管理表移除
				CombatSystem.UnregisterDeathFade(unitModel)
			end
		end)
		table.insert(connections, destroyConnection)

		-- V1.5.12新增：将Tween和连接注册到集中管理表
		CombatSystem.RegisterDeathFade(unitModel, tweens, connections)

		-- 6. 双重保险：如果在连接事件之前标记就已经没了（极少数并发情况）
		-- V1.5.12关键修复：不仅要取消Tween，还要立即重置透明度！
		-- 因为Tween.Play()可能已经让透明度开始变化了
		if not unitModel:GetAttribute("PendingDeathHide") then
			-- 取消所有Tween
			for _, tween in ipairs(tweens) do pcall(function() tween:Cancel() end) end

			-- 立即重置透明度到原始值
			for _, inst in ipairs(fadeTargets) do
				pcall(function()
					local origTrans = inst:GetAttribute("_OrigTrans")
					if origTrans ~= nil then
						inst.Transparency = origTrans
					elseif inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart" then
						inst.Transparency = 0
					elseif inst:IsA("Decal") or inst:IsA("Texture") then
						inst.Transparency = 0
					end
					-- 清除临时属性
					inst:SetAttribute("_OrigTrans", nil)
				end)
			end

			-- 断开连接
			if connection then connection:Disconnect() connection = nil end
			if destroyConnection then destroyConnection:Disconnect() destroyConnection = nil end
			CombatSystem.UnregisterDeathFade(unitModel)
			DebugLog(string.format("%s 双重保险触发：Tween已取消，透明度已重置", unitId))
		end
	end)

	task.delay(2.9, function()
		if unitModel and unitModel.Parent then
			-- V3.8修复：检查是否已被复生（复生时会清除PendingDeathHide标记）
			local pendingHide = unitModel:GetAttribute("PendingDeathHide")
			if not pendingHide then
				DebugLog(string.format("%s 跳过隐藏：单位已被复生", unitId))
				return
			end

			-- V1.5.12新增：正常死亡流程结束，清理集中管理表
			CombatSystem.UnregisterDeathFade(unitModel)

			-- 检查是否是战役单位
			local isCampaignUnit = unitModel:GetAttribute("CampaignKeepInstance")

			if isCampaignUnit then
				-- V2.0.2修复：战役单位隐藏前确保已软冻结
				-- 调用UnitAI的软冻结确保状态稳定
				local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
				local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
				if humanoid and rootPart then
					-- 确保状态已冻结
					pcall(function()
						humanoid.BreakJointsOnDeath = false
						humanoid.PlatformStand = true
						humanoid.AutoRotate = false
						humanoid:ChangeState(Enum.HumanoidStateType.Physics)
						rootPart.AssemblyLinearVelocity = Vector3.zero
						rootPart.AssemblyAngularVelocity = Vector3.zero
						rootPart.Anchored = true
					end)
					DebugLog(string.format("%s 战役单位隐藏前已确保软冻结状态", unitId))
				end

				-- 战役单位：隐藏但不销毁，用于后续重生
				unitModel.Parent = nil
				DebugLog(string.format("%s 战役单位已隐藏（保留实例用于重生）", unitId))
			else
				-- 非战役单位：直接销毁
				unitModel:Destroy()
				DebugLog(string.format("%s 模型已销毁", unitId))
			end
		end
	end)
end

-- ==================== AI状态管理 (保持兼容V1.5) ====================

--[[
设置兵种当前目标
@param unitModel Model - 兵种模型
@param target Model - 目标模型
]]
function CombatSystem.SetTarget(unitModel, target)
	local state = unitStates[unitModel]

	if not state then
		return
	end

	state.CurrentTarget = target
end

--[[
获取兵种当前目标
@param unitModel Model - 兵种模型
@return Model|nil - 目标模型
]]
function CombatSystem.GetTarget(unitModel)
	local state = unitStates[unitModel]

	if not state then
		return nil
	end

	return state.CurrentTarget
end

--[[
设置兵种AI状态
@param unitModel Model - 兵种模型
@param aiState string - AI状态
]]
function CombatSystem.SetAIState(unitModel, aiState)
	local state = unitStates[unitModel]

	if not state then
		return
	end

	state.State = aiState
end

--[[
获取兵种AI状态
@param unitModel Model - 兵种模型
@return string|nil - AI状态
]]
function CombatSystem.GetAIState(unitModel)
	local state = unitStates[unitModel]

	if not state then
		return nil
	end

	return state.State
end

-- ==================== 清理与工具 ====================

--[[
清理兵种战斗状态
@param unitModel Model - 兵种模型
]]
function CombatSystem.ClearUnitState(unitModel)
	unitStates[unitModel] = nil
end

--[[
清理战斗的所有兵种状态
@param battleId number - 战斗ID
]]
function CombatSystem.ClearBattleUnits(battleId)
	for unitModel, state in pairs(unitStates) do
		if state.BattleId == battleId then
			unitStates[unitModel] = nil
		end
	end

	DebugLog("已清理战斗", battleId, "的所有兵种状态")
end

--[[
获取所有战斗状态
@return table - 所有兵种状态
]]
function CombatSystem.GetAllUnitStates()
	return unitStates
end

-- ==================== V1.5.12新增：死亡渐隐集中管理 ====================

--[[
取消单位的死亡渐隐效果，并立即重置透明度
在战役复活时调用，一键终止所有渐隐Tween并恢复可见性
@param unitModel Model - 单位模型
]]
function CombatSystem.CancelDeathFade(unitModel)
	if not unitModel then return end

	-- 1. 清除PendingDeathHide标记（触发已存在的监听器取消Tween）
	pcall(function()
		unitModel:SetAttribute("PendingDeathHide", nil)
	end)

	-- 2. 从集中管理表中取出并清理
	local fadeData = activeDeathFades[unitModel]
	if fadeData then
		-- 取消所有Tween
		if fadeData.tweens then
			for _, tween in ipairs(fadeData.tweens) do
				pcall(function()
					tween:Cancel()
				end)
			end
		end

		-- 断开所有连接
		if fadeData.connections then
			for _, conn in ipairs(fadeData.connections) do
				pcall(function()
					conn:Disconnect()
				end)
			end
		end

		activeDeathFades[unitModel] = nil
		DebugLog(string.format("[CancelDeathFade] 已取消 %s 的渐隐效果", unitModel.Name or "Unknown"))
	end

	-- 3. 加载UnitAI并重置透明度（兜底清理）
	local unitAIModule = ServerScriptService:FindFirstChild("Systems") and ServerScriptService.Systems:FindFirstChild("UnitAI")
	if unitAIModule then
		local UnitAI = require(unitAIModule :: ModuleScript)
		if UnitAI.ResetModelTransparency then
			UnitAI.ResetModelTransparency(unitModel)
		end
	end

	-- 4. 双重保险：强制遍历所有部件重置透明度
	-- V1.5.13修复：优先使用_OriginalTransparency恢复原始值，保持武器结构不变
	-- V1.5.14修复：如果没有保存原始透明度，尝试从模板获取
	local hasSavedTransparency = unitModel:GetAttribute("_TransparencySaved")
	local templateTransparencyMap = nil

	if not hasSavedTransparency then
		-- 尝试从模板获取原始透明度
		local unitId = unitModel:GetAttribute("UnitId")
		if unitId then
			local unitConfig = UnitConfig.Units[unitId]
			local modelPath = unitConfig and unitConfig.ModelPath

			if modelPath and modelPath ~= "" then
				-- 解析路径找到模板
				local pathParts = string.split(tostring(modelPath), "/")
				local currentFolder = ReplicatedStorage
				for i = 1, #pathParts - 1 do
					local nextFolder = currentFolder:FindFirstChild(pathParts[i])
					if nextFolder then
						currentFolder = nextFolder
					else
						currentFolder = nil
						break
					end
				end

				if currentFolder then
					local modelName = pathParts[#pathParts]
					local template = currentFolder:FindFirstChild(modelName)
					if template then
						-- 构建模板透明度映射表
						templateTransparencyMap = {}
						for _, part in ipairs(template:GetDescendants()) do
							if part:IsA("BasePart") or part:IsA("Decal") or part:IsA("Texture") then
								local relativePath = part:GetFullName():sub(#template:GetFullName() + 2)
								templateTransparencyMap[relativePath] = part.Transparency
							end
						end
					end
				end
			end
		end
	end

	for _, part in ipairs(unitModel:GetDescendants()) do
		if part:IsA("BasePart") then
			-- HumanoidRootPart通常是透明的，保持不变
			if part.Name ~= "HumanoidRootPart" then
				-- 优先使用保存的原始透明度
				local origTrans = part:GetAttribute("_OriginalTransparency")
				if origTrans ~= nil then
					part.Transparency = origTrans
				elseif templateTransparencyMap then
					-- 从模板映射中获取
					local relativePath = part:GetFullName():sub(#unitModel:GetFullName() + 2)
					local templateTrans = templateTransparencyMap[relativePath]
					if templateTrans ~= nil then
						part.Transparency = templateTrans
						pcall(function()
							part:SetAttribute("_OriginalTransparency", templateTrans)
						end)
					else
						part.Transparency = 0
					end
				else
					part.Transparency = 0
				end
			end
			-- 清除临时保存的死亡渐隐透明度属性
			pcall(function()
				part:SetAttribute("_OrigTrans", nil)
			end)
		elseif part:IsA("Decal") or part:IsA("Texture") then
			-- 优先使用保存的原始透明度
			local origTrans = part:GetAttribute("_OriginalTransparency")
			if origTrans ~= nil then
				part.Transparency = origTrans
			elseif templateTransparencyMap then
				local relativePath = part:GetFullName():sub(#unitModel:GetFullName() + 2)
				local templateTrans = templateTransparencyMap[relativePath]
				if templateTrans ~= nil then
					part.Transparency = templateTrans
					pcall(function()
						part:SetAttribute("_OriginalTransparency", templateTrans)
					end)
				else
					part.Transparency = 0
				end
			else
				part.Transparency = 0
			end
			pcall(function()
				part:SetAttribute("_OrigTrans", nil)
			end)
		end
	end

	-- 如果从模板获取了透明度，标记已保存
	if templateTransparencyMap then
		unitModel:SetAttribute("_TransparencySaved", true)
	end

	DebugLog(string.format("[CancelDeathFade] %s 透明度已完全重置", unitModel.Name or "Unknown"))
end

--[[
注册死亡渐隐数据到集中管理表
@param unitModel Model - 单位模型
@param tweens table - Tween数组
@param connections table - 连接数组
]]
function CombatSystem.RegisterDeathFade(unitModel, tweens, connections)
	if not unitModel then return end

	-- 先清理可能存在的旧数据
	local oldData = activeDeathFades[unitModel]
	if oldData then
		if oldData.tweens then
			for _, tween in ipairs(oldData.tweens) do
				pcall(function() tween:Cancel() end)
			end
		end
		if oldData.connections then
			for _, conn in ipairs(oldData.connections) do
				pcall(function() conn:Disconnect() end)
			end
		end
	end

	activeDeathFades[unitModel] = {
		tweens = tweens or {},
		connections = connections or {}
	}
end

--[[
从集中管理表中移除死亡渐隐数据（渐隐正常完成时调用）
@param unitModel Model - 单位模型
]]
function CombatSystem.UnregisterDeathFade(unitModel)
	if not unitModel then return end
	activeDeathFades[unitModel] = nil
end

-- ==================== V4.0 客户端AI支持 ====================

--[[
初始化客户端AI事件监听
]]
function CombatSystem.InitializeClientAIEvents()
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		WarnLog("[V4.0] 未找到Events文件夹")
		return
	end

	local clientAIEvents = eventsFolder:FindFirstChild("ClientAIEvents")
	if not clientAIEvents then
		WarnLog("[V4.0] 未找到ClientAIEvents文件夹，客户端AI将无法工作")
		return
	end

	-- 监听客户端攻击请求
	local requestAttackEvent = clientAIEvents:FindFirstChild("RequestAttack")
	if requestAttackEvent then
		requestAttackEvent.OnServerEvent:Connect(function(player, battleId, attackerModel, targetModel, attackType)
			CombatSystem.OnClientAttackRequest(player, battleId, attackerModel, targetModel, attackType)
		end)
		DebugLog("[V4.0] RequestAttack事件监听已绑定")
	else
		WarnLog("[V4.0] 未找到RequestAttack事件")
	end

	-- 监听客户端位置上报（用于防作弊校验）
	local reportPositionEvent = clientAIEvents:FindFirstChild("ReportUnitPosition")
	if reportPositionEvent then
		reportPositionEvent.OnServerEvent:Connect(function(player, battleId, unitModel, position, state)
			CombatSystem.OnClientPositionReport(player, battleId, unitModel, position, state)
		end)
		DebugLog("[V4.0] ReportUnitPosition事件监听已绑定")
	else
		WarnLog("[V4.0] 未找到ReportUnitPosition事件")
	end
end

-- ==================== V4.0 客户端AI校验辅助（服务端权威） ====================

-- BattleManager懒加载缓存（避免循环依赖）
local cachedBattleManager = nil

local function GetBattleManager()
	-- nil=未加载，false=加载失败，table=模块
	if cachedBattleManager ~= nil then
		return cachedBattleManager or nil
	end

	local bmModule = ServerScriptService:FindFirstChild("Systems") and ServerScriptService.Systems:FindFirstChild("BattleManager")
	if not bmModule then
		cachedBattleManager = false
		return nil
	end

	local ok, mod = pcall(function()
		return require(bmModule :: ModuleScript)
	end)

	if ok and mod then
		cachedBattleManager = mod
		return mod
	end

	cachedBattleManager = false
	return nil
end

local function GetSyncUnitPositionEvent()
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		return nil
	end

	local clientAIEvents = eventsFolder:FindFirstChild("ClientAIEvents")
	if not clientAIEvents then
		return nil
	end

	return clientAIEvents:FindFirstChild("SyncUnitPosition")
end

local function IsBattleOwnedByPlayer(player, battleId)
	local BattleManager = GetBattleManager()
	if not BattleManager or not BattleManager.GetBattle then
		return false
	end

	local battle = BattleManager.GetBattle(battleId)
	if not battle or not battle.PlayerId then
		return false
	end

	return battle.PlayerId == player.UserId
end

local function ResolveUnitStateForBattle(battleId, unitModel)
	-- 先尝试直接引用（正常情况下客户端传入的Instance与服务端一致）
	local state = unitStates[unitModel]
	if state and state.BattleId == battleId then
		return state, unitModel
	end

	-- 备用：使用InstanceId匹配（更稳定，避免同名模型误匹配）
	local instanceId = nil
	pcall(function()
		instanceId = unitModel:GetAttribute("InstanceId")
	end)

	if instanceId then
		for model, s in pairs(unitStates) do
			if s.BattleId == battleId then
				local mid = nil
				pcall(function()
					mid = model:GetAttribute("InstanceId")
				end)
				if mid == instanceId then
					return s, model
				end
			end
		end
	end

	-- 最后兜底：按Name匹配（不推荐，仅兼容旧逻辑）
	for model, s in pairs(unitStates) do
		if s.BattleId == battleId and model.Name == unitModel.Name then
			return s, model
		end
	end

	return nil, nil
end

--[[
处理客户端攻击请求（V4.0核心接口）
@param player Player - 发起请求的玩家
@param battleId number - 战斗ID
@param attackerModel Model - 攻击者模型
@param targetModel Model - 目标模型
@param attackType string - 攻击类型（"Melee"或"Ranged"）
]]
function CombatSystem.OnClientAttackRequest(player, battleId, attackerModel, targetModel, attackType)
	-- 参数验证（类型+存在性）
	if not player or typeof(battleId) ~= "number" then
		WarnLog("[V4.0] 客户端攻击请求参数无效")
		return
	end
	if typeof(attackerModel) ~= "Instance" or not attackerModel:IsA("Model") then
		WarnLog("[V4.0] 客户端攻击请求攻击者模型无效")
		return
	end
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then
		WarnLog("[V4.0] 客户端攻击请求目标模型无效")
		return
	end
	if typeof(attackType) ~= "string" then
		WarnLog("[V4.0] 客户端攻击请求攻击类型无效")
		return
	end

	-- 关键校验：只能由战斗拥有者驱动该战斗的AI（客户端驱动，服务端校验）
	if not IsBattleOwnedByPlayer(player, battleId) then
		WarnLog(string.format("[V4.0] 非法攻击请求：玩家%s无权控制BattleId=%s", player.Name, tostring(battleId)))
		return
	end

	-- 解析并强制绑定到该battleId下的单位状态（禁止跨战斗控制）
	local attackerState, attackerServerModel = ResolveUnitStateForBattle(battleId, attackerModel)
	if not attackerState then
		return
	end
	attackerModel = attackerServerModel

	if not attackerState.IsAlive then
		DebugLog("[V4.0] 攻击者已死亡，拒绝攻击请求")
		return
	end

	local targetState, targetServerModel = ResolveUnitStateForBattle(battleId, targetModel)
	if not targetState then
		return
	end
	targetModel = targetServerModel

	-- 验证目标状态
	if not targetState.IsAlive then
		return
	end

	-- 验证攻击阶段（必须是Idle才能攻击）
	if attackerState.AttackPhase ~= BattleConfig.AttackPhase.IDLE then
		return
	end

	-- 验证队伍（不能攻击友军）
	if targetState.Team == attackerState.Team then
		WarnLog("[V4.0] 不能攻击友军")
		return
	end

	-- 由服务端根据配置决定真实攻击类型（不信任客户端传入的attackType）
	local expectedAttackType = nil
	if UnitConfig.IsMeleeUnit(attackerState.UnitId) then
		expectedAttackType = "Melee"
	elseif UnitConfig.IsRangedUnit(attackerState.UnitId) then
		expectedAttackType = "Ranged"
	end

	if not expectedAttackType then
		WarnLog(string.format("[V4.0] 未知单位类型，拒绝攻击请求: %s (%s)", tostring(attackerState.UnitId), attackerModel.Name))
		return
	end

	if attackType ~= expectedAttackType then
		DebugLog(string.format("[V4.0] 客户端攻击类型与配置不一致，已按服务端配置覆盖: %s -> %s (%s)",
			tostring(attackType), tostring(expectedAttackType), tostring(attackerState.UnitId)))
	end
	attackType = expectedAttackType

	-- 验证距离（防作弊）
	local attackerRoot = attackerModel:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")
	if not attackerRoot or not targetRoot then
		WarnLog("[V4.0] 攻击者或目标缺少HumanoidRootPart")
		return
	end

	local distance = (attackerRoot.Position - targetRoot.Position).Magnitude
	local maxValidDistance = attackerState.AttackRange * 1.5 -- 允许1.5倍容差
	if distance > maxValidDistance then
		return
	end

	-- 校验通过，执行攻击
	if not CombatSystem.BeginAttack(attackerModel, targetModel) then
		WarnLog("[V4.0] BeginAttack失败")
		return
	end

	-- 设置当前目标（服务端维护）
	CombatSystem.SetTarget(attackerModel, targetModel)

	-- 根据单位真实类型执行伤害判定
	if attackType == "Melee" then
		CombatSystem.OnDamageEvent(attackerModel)
	elseif attackType == "Ranged" then
		CombatSystem.OnRangedDamageEvent(attackerModel, targetModel)
	end
end

--[[
处理客户端位置上报（V4.0防作弊）
@param player Player - 发起请求的玩家
@param battleId number - 战斗ID
@param unitModel Model - 单位模型
@param position Vector3 - 客户端报告的位置
@param state string - 客户端报告的AI状态
]]
function CombatSystem.OnClientPositionReport(player, battleId, unitModel, position, state)
	-- 参数验证
	if not player or typeof(battleId) ~= "number" then
		return
	end
	if typeof(unitModel) ~= "Instance" or not unitModel:IsA("Model") then
		return
	end
	if typeof(position) ~= "Vector3" then
		return
	end

	-- 关键校验：只能由战斗拥有者上报本战斗单位位置
	if not IsBattleOwnedByPlayer(player, battleId) then
		return
	end

	-- 绑定到本战斗的单位状态（禁止跨战斗）
	local unitState, unitServerModel = ResolveUnitStateForBattle(battleId, unitModel)
	if not unitState then
		return
	end
	unitModel = unitServerModel

	if not unitModel.Parent or not unitState.IsAlive then
		return
	end

	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- 服务器观测到的当前位置（服务端权威参考）
	local serverPos = rootPart.Position
	local now = tick()

	-- 首次上报：建立基准，不做判定（避免初始化/复制阶段误判）
	if not unitState.LastServerPosTime then
		unitState.LastServerPosTime = now
		unitState.LastServerPos = serverPos
		return
	end

	-- 速度/位移校验：限制异常瞬移（客户端驱动，服务端校验）
	local dt = math.max(now - (unitState.LastServerPosTime or now), 0.01)
	local lastPos = unitState.LastServerPos or serverPos
	local moved = (serverPos - lastPos).Magnitude

	-- 服务器侧“卡住样本”统计：用于允许一次解卡瞬移（不需要服务端运行AI，仅做校验/放行）
	local prevStuckSamples = unitState.StuckSamples or 0
	local stuckMoveThreshold = BattleConfig.UNSTUCK_TELEPORT_STUCK_MOVE_THRESHOLD or 0.5

	-- 允许一定的容差，避免网络抖动误判
	local moveSpeed = unitState.MoveSpeed or 16
	local tolerance = BattleConfig.POSITION_VALIDATION_TOLERANCE or 10
	local maxAllowed = (moveSpeed * dt * 3) + tolerance

	if moved > maxAllowed then
		-- 允许客户端“解卡瞬移”：当服务端连续观测到单位几乎没动（卡住），且客户端处于Moving状态时，放行一次较大位移
		-- 目的：配合ClientUnitAI的瞬移解卡，避免被位置校验回滚导致单位永久发呆/少兵
		local allowUnstuckTeleport = (BattleConfig.ALLOW_UNSTUCK_TELEPORT ~= false)
		local maxTeleportDist = BattleConfig.UNSTUCK_TELEPORT_MAX_DISTANCE or 150
		local requiredSamples = BattleConfig.UNSTUCK_TELEPORT_STUCK_SAMPLES or 3
		local teleportCooldown = BattleConfig.UNSTUCK_TELEPORT_COOLDOWN or 2.0
		local lastTeleportTime = unitState.LastUnstuckTeleportTime or 0

		if allowUnstuckTeleport
			and state == "Moving"
			and prevStuckSamples >= requiredSamples
			and moved <= maxTeleportDist
			and (now - lastTeleportTime) >= teleportCooldown then
			DebugLog(string.format("[V4.11] 允许解卡瞬移: %s moved=%.1f, stuckSamples=%d",
				unitModel.Name, moved, prevStuckSamples))
			unitState.LastUnstuckTeleportTime = now
			unitState.StuckSamples = 0

			-- V4.12修复：不使用MoveTo到当前位置，避免单位原地站住
			local humanoid = unitModel:FindFirstChildOfClass("Humanoid") or unitModel:FindFirstChild("Humanoid")
			if humanoid then
				pcall(function()
					humanoid:Move(Vector3.zero)
				end)
			end

			pcall(function()
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
			end)

			-- 接受该次位置变化，并更新基准
			unitState.LastServerPosTime = now
			unitState.LastServerPos = serverPos
			return
		end

		unitState.PositionViolationCount = (unitState.PositionViolationCount or 0) + 1

		WarnLog(string.format("[V4.0] 位置校验失败: %s 移动%.1f > 允许%.1f (dt=%.2f, speed=%.1f, 玩家:%s)",
			unitModel.Name, moved, maxAllowed, dt, moveSpeed, player.Name))

		-- 强制回滚到上一次合法位置，并同步给客户端
		local rollbackPos = lastPos

		pcall(function()
			if rootPart:CanSetNetworkOwnership() then
				rootPart:SetNetworkOwner(nil) -- 临时收回所有权，确保回滚生效
			end
		end)

		rootPart.CFrame = CFrame.new(rollbackPos)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		-- V4.12修复：回滚后清理移动状态，但不使用MoveTo到当前位置
		local humanoid = unitModel:FindFirstChildOfClass("Humanoid") or unitModel:FindFirstChild("Humanoid")
		if humanoid then
			pcall(function()
				humanoid:Move(Vector3.zero)
			end)
		end

		-- 通知客户端矫正
		local syncEvent = GetSyncUnitPositionEvent()
		if syncEvent then
			syncEvent:FireClient(player, battleId, unitModel, rollbackPos)
		end

		-- 轻量恢复NetworkOwner（避免持续抢夺导致抖动）
		task.delay(0.2, function()
			if rootPart and rootPart.Parent then
				pcall(function()
					if rootPart:CanSetNetworkOwnership() then
						rootPart:SetNetworkOwner(player)
					end
				end)
			end
		end)

		-- 回滚后更新基准，避免下一次继续按异常位移计算
		unitState.LastServerPosTime = now
		unitState.LastServerPos = rollbackPos
		return
	end

	-- 位置偏差（客户端上报 vs 服务端观测）过大时，通知客户端矫正到服务端观测值
	-- 该逻辑用于修正网络抖动/丢包导致的可见不同步，不用于信任客户端位置
	local reportDiff = (serverPos - position).Magnitude
	if reportDiff > (BattleConfig.POSITION_VALIDATION_TOLERANCE or 10) then
		local syncEvent = GetSyncUnitPositionEvent()
		if syncEvent then
			syncEvent:FireClient(player, battleId, unitModel, serverPos)
		end
	end

	-- 更新“卡住样本”
	if state == "Moving" and moved < stuckMoveThreshold then
		unitState.StuckSamples = prevStuckSamples + 1
	else
		unitState.StuckSamples = 0
	end

	-- 更新基准
	unitState.LastServerPosTime = now
	unitState.LastServerPos = serverPos
end

return CombatSystem
