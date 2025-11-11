--[[
脚本名称: CombatSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/CombatSystem
版本: V1.5.1 - 重构为动画事件驱动
]]

--[[
战斗系统
职责:
1. 管理兵种的战斗状态(血量、攻击阶段、是否存活)
2. 处理伤害计算
3. 处理死亡流程
4. 动画事件驱动的攻击系统(Idle→Attacking→Recovery)
5. 发送死亡通知给攻击者

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

-- 引用配置（从ReplicatedStorage获取共享配置）
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 私有变量 ====================

-- 存储所有兵种的战斗状态 [unitModel] = UnitCombatState
local unitStates = {}

-- 死亡事件
local unitDeathEvent = nil

-- Update连接
local updateConnection = nil

-- HitboxService 和 UnitManager 引用
local HitboxService = nil
local UnitManager = nil
local ProjectileSystem = nil  -- V1.5远程攻击支持
local WeaponEffectSystem = nil  -- V1.5.4远程武器特效支持

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

	-- 获取HitboxService和UnitManager引用
	HitboxService = require(ServerScriptService.Systems.HitboxService)
	UnitManager = require(ServerScriptService.Systems.UnitManager)

	-- 启动Update循环(处理攻击阶段切换)
	updateConnection = RunService.Heartbeat:Connect(UpdateAttackPhases)

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
@return boolean - 是否初始化成功
]]
function CombatSystem.InitializeUnit(unitModel, unitId, level, team, battleId)
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

	-- 创建战斗状态
	local combatState = {
		UnitInstance = unitModel,
		UnitId = unitId,
		Level = level,
		Team = team,
		BattleId = battleId,

		MaxHealth = maxHealth,
		CurrentHealth = maxHealth,
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

	DebugLog(string.format("初始化兵种战斗状态: %s Lv.%d [%s] HP:%d ATK:%d",
		unitId, level, team, maxHealth, attack))

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

	-- 获取敌方队伍
	local enemyTeam = UnitManager.GetEnemyTeam(state.Team)
	if not enemyTeam then
		WarnLog("OnDamageEvent失败: 无法获取敌方队伍")
		return 0
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

	-- 引用ProjectileSystem（延迟加载）
	if not ProjectileSystem then
		ProjectileSystem = require(ServerScriptService.Systems.ProjectileSystem)
	end

	-- ⭐⭐⭐ V1.5.4 播放远程武器特效 ⭐⭐⭐
	-- 在发射子弹前播放枪口特效（Beam、PointLight、ParticleEmitter）
	if not WeaponEffectSystem then
		WeaponEffectSystem = require(ServerScriptService.Systems.WeaponEffectSystem)
	end

	local weaponName = UnitConfig.GetWeaponName(state.UnitId)
	if weaponName and weaponName ~= "" then
		-- 播放武器特效（内部有容错处理，失败不影响战斗）
		WeaponEffectSystem.PlayWeaponEffect(unitModel, weaponName)
	end

	-- ⭐⭐⭐ 发射子弹 ⭐⭐⭐
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
					-- 发送给所有客户端: 单位模型, 伤害值
					showDamageNumberEvent:FireAllClients(unitModel, damage)
				end
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

	return true
end

--[[
杀死兵种 - V1.5.10无缝死亡动画版
@param unitModel Model - 兵种模型
@param killer Model - 击杀者模型(可选)

流程（关键：先播死亡动画再停AI，确保无缝过渡）：
1. 标记死亡状态
2. 从系统中注销 → 触发死亡事件
3. 播放死亡动画（立刻禁用Animate，高优先级Fade=0）
4. 停止AI（瞬停Fade=0，禁用Animate，无MoveTo）
5. 2.9秒后销毁

无缝过渡效果：
当前动作（攻击/移动/待机）→ 立刻播放死亡动画（无"傻站"间隙）
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

	DebugLog(string.format("%s [%s] 已死亡", state.UnitId, state.Team))

	-- 保存unitId用于后续日志
	local unitId = state.UnitId
	local battleId = state.BattleId

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

	-- ===== V1.5.10 无缝死亡动画版本 =====
	local UnitAI = require(ServerScriptService.Systems.UnitAI)
	local deathAnimationId = UnitConfig.GetDeathAnimationId(unitId)

	-- 关键步骤顺序：先播死亡动画再停AI
	-- 这样死亡动画会立刻播放，避免被StopAI的动画清理杀死

	-- 步骤1: 播放死亡动画（立刻禁用Animate，高优先级Fade=0确保立即生效）
	UnitAI.BeginDeathAnimation(unitModel, deathAnimationId, unitId)

	-- 步骤2: 停止AI（参数：瞬停Fade=0，禁用Animate，无MoveTo）
	-- 此时死亡动画已在播放，StopAI只会清理AI的轨道，不会干扰死亡动画
	UnitAI.StopAI(unitModel, {
		skipMoveTo = true,        -- 防止MoveTo把尸体"拉起"
		disableAnimate = true,    -- 再次确认禁用Animate
		stopFadeTime = 0          -- 瞬停AI轨道，无淡出延迟
	})

	-- 步骤3: 固定2.9秒后销毁或隐藏模型
	-- V2.0.1修复：战役单位死亡时保留实例用于重生
	task.delay(2.9, function()
		if unitModel and unitModel.Parent then
			-- 检查是否是战役单位
			local isCampaignUnit = unitModel:GetAttribute("CampaignKeepInstance")

			if isCampaignUnit then
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

return CombatSystem
