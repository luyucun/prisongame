--[[
脚本名称: UnitAI (重构版 - 使用PathService)
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/UnitAI
版本: V2.0 - 寻路逻辑重构，职责分离

重构要点：
1. 移除所有PathfindingService直接操作
2. 使用PathService统一管理路径
3. UnitAI只负责AI状态机和动画控制
4. 代码更清晰、更易维护
]]

--[[
兵种AI系统 - 重构版
职责:
1. 清晰的AI状态机: SEEKING → MOVING → ATTACKING
2. 独立的动画控制器: 统一管理所有动画切换
3. 正确的动画流程: 移动 → idle → attack → idle(冷却) → attack → ...
4. 攻击周期明确: attack结束 → idle开始 → 冷却结束 → 下次attack

核心改进:
- 显式动画状态(MOVE/IDLE/ATTACK)，杜绝互相踩踏
- 动画Track自动清理，攻击结束回调触发idle
- HandleAttacking只负责判断是否可以攻击，不直接操作动画
- 冷却期idle稳定播放，覆盖整个CD阶段
- 路径管理完全委托给PathService
]]

local UnitAI = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- 引用系统
local CombatSystem = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CombatSystem")) :: any
local UnitManager = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("UnitManager")) :: any
local PathService = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("PathService")) :: any  -- ⭐新增

-- ==================== 调试日志 ====================

local function DebugLog(...)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[UnitAI]", ...)
end

local function LogStateChange(unitId, fromState, toState, reason)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, string.format("[UnitAI] %s: %s → %s (%s)",
			unitId, fromState or "nil", toState, reason or ""))
	end
end

local function LogAnimationChange(unitId, fromAnim, toAnim, reason)
	if BattleConfig.DEBUG_AI_LOGS then
		print(GameConfig.LOG_PREFIX, string.format("[UnitAI] %s 动画: %s → %s (%s)",
			unitId, fromAnim or "None", toAnim, reason or ""))
	end
end

-- ==================== 尸体冻结辅助函数 ====================

--[[
禁用模型中所有Animate脚本（递归查找）
兼容：NPC的Script、玩家的LocalScript、任何子文件夹中的Animate

@param unitModel - 兵种模型
@param unitName - 单位名称（用于日志）
]]
local function DisableAllAnimateScripts(unitModel, unitName)
	if not unitModel then
		return
	end

	-- 方法1: 直接查找（支持递归搜索，true参数表示遍历后代）
	local animateScript = unitModel:FindFirstChild("Animate", true)
	if animateScript and animateScript:IsA("BaseScript") then
		animateScript.Enabled = false
		DebugLog(string.format("[%s] 已禁用Animate脚本(直接查找)", unitName))
		return
	end

	-- 方法2: 遍历所有后代，查找所有名为Animate的脚本
	-- 处理可能有多个Animate脚本的情况
	for _, descendant in ipairs(unitModel:GetDescendants()) do
		if descendant.Name == "Animate" and descendant:IsA("BaseScript") then
			descendant.Enabled = false
			DebugLog(string.format("[%s] 已禁用Animate脚本(遍历查找): %s", unitName, descendant:GetFullName()))
		end
	end
end

--[[
冻结尸体：归零速度、锚定、禁用碰撞
防止死亡动画播完后尸体被物理引擎"抛飞"

@param unitModel - 兵种模型
@param humanoid - Humanoid对象
@param rootPart - HumanoidRootPart
]]
local function FreezeCorpse(unitModel, humanoid, rootPart, unitName)
	if not unitModel or not unitModel.Parent then
		return
	end

	-- 步骤1: 禁用自动死亡导致的关节破碎 (关键修复)
	humanoid.BreakJointsOnDeath = false
	-- 防止血量归零导致强制进入Dead状态
	if humanoid.Health <= 0 then
		humanoid.Health = 1 -- 保持一点点血量防止系统判定真死
	end

	-- 步骤2: 禁用控制并设置物理状态 (修复：使用Physics代替Dead)
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	-- 使用Physics状态，这样Humanoid不会被系统判定为"死亡"，可以被复活
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	-- 步骤3: 归零速度（消除任何剩余的移动或旋转动量）
	pcall(function()
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end)

	-- 步骤4: 锚定根部件（完全阻止物理模拟）
	pcall(function()
		rootPart.Anchored = true
	end)

	DebugLog(string.format("[%s] 尸体已冻结 (Physics状态、锚定)", unitName))
end

--[[
战役单位软冻结（保持死亡姿态但可恢复）
与FreezeCorpse不同，此函数专门为战役单位设计，保持姿态但不锚定，
以便复活时能正确恢复状态
]]
local function SoftFreezeForCampaign(unitModel, humanoid, rootPart, unitName)
	if not unitModel or not unitModel.Parent then
		return
	end

	DebugLog(string.format("[%s] 战役单位开始软冻结", unitName))

	-- 步骤1: 防止关节破碎，但保留死亡姿态
	pcall(function()
		humanoid.BreakJointsOnDeath = false
	end)

	-- 步骤2: 设置物理状态但不使用Dead状态
	pcall(function()
		humanoid.PlatformStand = true    -- 保持倒地状态
		humanoid.AutoRotate = false     -- 禁用自动旋转
		humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- 使用物理状态，可恢复
	end)

	-- 步骤3: 清零速度但不锚定（让复活时能正确传送）
	pcall(function()
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end)

	-- 步骤4: 立即锚定防止Parent=nil时姿态塌陷
	pcall(function()
		rootPart.Anchored = true
	end)

	DebugLog(string.format("[%s] 软冻结完成 (PlatformStand=true, Physics状态, 已锚定)", unitName))
end

-- ==================== 动画基础函数 ====================

--[[
预加载单个动画（不播放，仅加载到缓存）
@param animator - Animator对象
@param animationId - 动画ID（string或number）
@return AnimationTrack|nil - 返回已加载的Track（但未播放）
]]
local function PreloadAnimation(animator: Animator, animationId: string | number): AnimationTrack?
	if not animator or not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	local animIdStr = tostring(animationId)
	if not tonumber(animIdStr) then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animIdStr

	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	animation:Destroy()

	if success and animationTrack then
		return animationTrack
	end

	return nil
end

--[[
预加载所有战斗动画（在StartAI时调用）
目的：在服务器端预缓存AnimationTrack，加速LoadAnimation调用
注意：客户端动画渲染由AnimationPreloader.lua（客户端脚本）负责预加载

@param unitModel - 兵种模型
@param humanoid - Humanoid对象
@param unitId - 兵种ID
]]
local function PreloadAllAnimations(unitModel, humanoid, unitId)
	-- V2.6修复：添加humanoid空值检查
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid.Parent and humanoid.Parent:FindFirstChildOfClass("Animator")
	end

	-- V2.6修复：静默失败，不要WarnLog刷屏
	-- 原因：某些情况下Animator尚未创建，这是正常的，不应该刷屏
	if not animator then
		return  -- 静默返回，不打印警告
	end

	-- 获取所有动画ID
	local idleAnimId = UnitConfig.GetIdleAnimationId(unitId)
	local moveAnimId = UnitConfig.GetMoveAnimationId(unitId)
	local attackAnimId = UnitConfig.GetAttackAnimationId(unitId)
	local deathAnimId = UnitConfig.GetDeathAnimationId(unitId)

	-- 服务器端预加载：使用Animator:LoadAnimation预缓存Track
	-- 这样后续CreateAndPlayAnimation调用会更快
	local animIds = {
		{id = idleAnimId, name = "Idle"},
		{id = moveAnimId, name = "Move"},
		{id = attackAnimId, name = "Attack"},
		{id = deathAnimId, name = "Death"},
	}

	for _, data in ipairs(animIds) do
		if data.id and data.id ~= "" then
			local track = PreloadAnimation(animator, data.id)
			if track then
				-- 立即停止，不播放，仅为了让Animator缓存这个Track
				pcall(function()
					track:Stop(0)
				end)
				DebugLog(string.format("[%s] 预缓存%s动画Track成功", unitId, data.name))
			end
		end
	end

	DebugLog(string.format("[%s] ✅服务器端动画预缓存完成", unitId))
end

--[[
创建并播放动画（V2.8增强：支持明确指定动画优先级）
@param humanoid - Humanoid对象
@param animationId - 动画ID（string或number）
@param looped - 是否循环
@param priority - 动画优先级（Enum.AnimationPriority，可选）
@return AnimationTrack|nil
]]
local function CreateAndPlayAnimation(humanoid: Humanoid, animationId: string | number, looped: boolean, priority: Enum.AnimationPriority?): AnimationTrack?
	if not humanoid or not animationId or animationId == "" or animationId == "0" then
		return nil
	end

	local animIdStr = tostring(animationId)
	if not tonumber(animIdStr) then
		WarnLog(string.format("无效的动画ID格式: %s", animIdStr))
		return nil
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid.Parent and humanoid.Parent:FindFirstChildOfClass("Animator")
	end
	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animIdStr

	local success, animationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not animationTrack then
		animation:Destroy()
		return nil
	end

	-- V2.8新增：设置动画优先级，确保攻击覆盖一切
	if priority then
		animationTrack.Priority = priority
	end

	animationTrack.Looped = looped or false

	local playSuccess = pcall(function()
		animationTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return nil
	end

	-- 清理Animation对象
	if looped then
		-- 循环动画：在停止时清理
		animationTrack.Stopped:Connect(function()
			if animation and animation.Parent then
				animation:Destroy()
			end
		end)
	else
		-- 单次动画：延迟清理（服务器上无法获取Length，使用固定延迟）
		task.delay(5, function()
			if animation and animation.Parent then
				animation:Destroy()
			end
		end)
	end

	return animationTrack
end

--[[
V2.4新增：从缓存或创建并播放动画（V2.8增强：支持优先级）
优化：优先从aiData.Tracks缓存中查找已加载的Track，避免重复LoadAnimation
@param unitModel - 单位模型
@param aiData - AI数据
@param animationId - 动画ID（string或number）
@param trackType - 轨道类型标识（如"Idle", "Move", "Attack"）
@param looped - 是否循环
@param priority - 动画优先级（Enum.AnimationPriority，可选）
@return AnimationTrack|nil - 动画轨道
]]
local function PlayAnimationFromCache(unitModel: Model, aiData: any, animationId: string | number, trackType: string, looped: boolean, priority: Enum.AnimationPriority?): AnimationTrack?
	if not aiData or not aiData.Tracks then
		-- V2.8修复：容错处理，避免aiData=nil时崩溃
		local humanoid = aiData and aiData.Humanoid or (unitModel and unitModel:FindFirstChildOfClass("Humanoid"))
		return CreateAndPlayAnimation(humanoid, animationId, looped, priority)
	end

	-- 检查缓存中是否已有此Track
	local cachedTrack = aiData.Tracks[trackType]
	if cachedTrack and cachedTrack.Parent then
		-- 缓存的Track仍有效，直接复用
		pcall(function()
			-- V2.8新增：如果指定了优先级，更新Track的优先级
			if priority then
				cachedTrack.Priority = priority
			end
			cachedTrack:Stop()
			cachedTrack:Play()
		end)
		return cachedTrack
	end

	-- 缓存无效，使用CreateAndPlayAnimation（会自动创建新的）
	local newTrack = CreateAndPlayAnimation(aiData.Humanoid, animationId, looped, priority)
	if newTrack then
		-- 缓存新Track供后续使用
		aiData.Tracks[trackType] = newTrack
	end

	return newTrack
end

--[[
安全停止动画
@param animationTrack - 动画轨道
]]
local function SafeStopAnimation(animationTrack)
	if animationTrack and animationTrack.IsPlaying then
		pcall(function()
			animationTrack:Stop()
		end)
	end
end

-- ==================== 统一动画状态机 ====================

local AnimationState = {
	MOVE = "MOVE",
	IDLE = "IDLE",
	ATTACK = "ATTACK",
}

--[[
动画控制器 - 统一管理所有动画切换
职责：
1. 维护 Tracks 表存储所有动画轨道
2. 确保状态切换时精确停止需要的轨道
3. 攻击动画结束自动回到Idle
]]
local AnimationController = {}

--[[
切换到移动状态
@param unitModel - 兵种模型
@param aiData - AI数据
@param state - 单位状态
]]
function AnimationController.SwitchToMove(unitModel, aiData, state)
	-- 如果已经在播放移动动画，跳过
	if aiData.CurrentState == AnimationState.MOVE and
	   aiData.Tracks.Move and
	   aiData.Tracks.Move.IsPlaying then
		return
	end

	-- 停止 Idle 和 Attack
	if aiData.Tracks.Idle then
		SafeStopAnimation(aiData.Tracks.Idle)
		aiData.Tracks.Idle = nil
	end
	if aiData.Tracks.Attack then
		SafeStopAnimation(aiData.Tracks.Attack)
		aiData.Tracks.Attack = nil
	end

	-- 播放移动动画（V2.8：设置Movement优先级）
	local animId = UnitConfig.GetMoveAnimationId(state.UnitId)
	if animId and animId ~= "" then
		-- V2.4优化：使用缓存Track，V2.8：设置Movement优先级
		local track = PlayAnimationFromCache(unitModel, aiData, animId, "Move", true, Enum.AnimationPriority.Movement)
		if track then
			aiData.Tracks.Move = track
			aiData.CurrentState = AnimationState.MOVE
			LogAnimationChange(state.UnitId, aiData.LastState, AnimationState.MOVE, "开始移动")
			aiData.LastState = AnimationState.MOVE
		end
	else
		aiData.CurrentState = AnimationState.MOVE
	end
end

--[[
切换到待机状态
@param unitModel - 兵种模型
@param aiData - AI数据
@param state - 单位状态
]]
function AnimationController.SwitchToIdle(unitModel, aiData, state)
	-- 严格检查1：如果已经在播放Idle动画，直接返回（避免重复播放）
	if aiData.CurrentState == AnimationState.IDLE then
		if aiData.Tracks.Idle and aiData.Tracks.Idle.IsPlaying then
			-- 已经在播放Idle，无需重复切换
			return
		end
	end

	-- 严格检查2：如果Attack正在播放，不要打断它
	if aiData.Tracks.Attack and aiData.Tracks.Attack.IsPlaying then
		-- Attack还在播放，不要打断，等它自然结束
		return
	end

	-- 停止 Move（但不停止 Attack，上面已经检查过了）
	if aiData.Tracks.Move then
		SafeStopAnimation(aiData.Tracks.Move)
		aiData.Tracks.Move = nil
	end

	-- 播放待机动画（V2.8：设置Idle优先级）
	local animId = UnitConfig.GetIdleAnimationId(state.UnitId)
	if animId and animId ~= "" then
		-- 只有在Idle动画不存在或已停止时才重新播放
		if not aiData.Tracks.Idle or not aiData.Tracks.Idle.IsPlaying then
			local track = PlayAnimationFromCache(unitModel, aiData, animId, "Idle", true, Enum.AnimationPriority.Idle)
			if track then
				aiData.Tracks.Idle = track
				aiData.CurrentState = AnimationState.IDLE
				LogAnimationChange(state.UnitId, aiData.LastState, AnimationState.IDLE, "进入待机")
				aiData.LastState = AnimationState.IDLE
			end
		else
			-- Idle动画已经在播放，只更新状态
			aiData.CurrentState = AnimationState.IDLE
		end
	else
		-- 无配置，只更新状态
		aiData.CurrentState = AnimationState.IDLE
	end
end

--[[
播放攻击动画
@param unitModel - 兵种模型
@param aiData - AI数据
@param state - 单位状态
@param target - 攻击目标
@param onDamageCallback - 伤害回调
]]
function AnimationController.PlayAttack(unitModel, aiData, state, target, onDamageCallback)
	-- 清理之前的攻击动画连接
	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}

	-- 获取配置
	local animationId = UnitConfig.GetAttackAnimationId(state.UnitId)
	local combatProfile = UnitConfig.GetCombatProfile(state.UnitId)
	local isRangedUnit = UnitConfig.IsRangedUnit(state.UnitId)

	-- 全局防重复标志（基于单位模型）
	local damageEventFired = false

	-- 保存旧轨道的引用，但先不停止
	local prevMove = aiData.Tracks.Move
	local prevIdle = aiData.Tracks.Idle

	-- 播放攻击动画（V2.8：设置Action优先级）
	if animationId and animationId ~= "" and combatProfile.UseAnimationEvent then
		local animTrack = PlayAnimationFromCache(unitModel, aiData, animationId, "Attack", false, Enum.AnimationPriority.Action)

		if animTrack then
			-- 攻击动画成功加载并播放后，再停止旧动画
			aiData.Tracks.Attack = animTrack
			aiData.CurrentState = AnimationState.ATTACK
			LogAnimationChange(state.UnitId, aiData.LastState, AnimationState.ATTACK, "开始攻击")
			aiData.LastState = AnimationState.ATTACK

			-- 关键修复：此时再停止旧轨道，保证无缝切换
			if prevMove then
				SafeStopAnimation(prevMove)
				aiData.Tracks.Move = nil
			end
			if prevIdle then
				SafeStopAnimation(prevIdle)
				aiData.Tracks.Idle = nil
			end

			-- 监听动画的 "Damage" 事件
			local eventName = combatProfile.AnimationEventName or "Damage"

			local damageConnection = animTrack:GetMarkerReachedSignal(eventName):Connect(function()
				-- 双重检查防止重复触发
				if damageEventFired then
					DebugLog(string.format("%s Damage事件重复触发，忽略", state.UnitId))
					return
				end
				damageEventFired = true

				DebugLog(string.format("%s 动画事件[%s]触发", state.UnitId, eventName))

				-- 调用伤害回调（这会触发 OnDamageEvent，进入 Recovery）
				if onDamageCallback then
					onDamageCallback(unitModel, target, isRangedUnit)
				end
			end)

			table.insert(aiData.AnimationConnections, damageConnection)

			-- V2.8新增：兜底伤害定时器（防止动画标记未触发或触发太晚）
			local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
			task.delay(fallbackDelay, function()
				if damageEventFired then return end
				if not aiData.IsActive or not unitModel.Parent or not CombatSystem.IsUnitAlive(unitModel) then return end
				if CombatSystem.GetAttackPhase(unitModel) ~= BattleConfig.AttackPhase.ATTACKING then return end

				damageEventFired = true
				DebugLog(string.format("%s 动画标记超时，兜底伤害触发", state.UnitId))

				if onDamageCallback then
					onDamageCallback(unitModel, target, isRangedUnit)
				end

				-- 兜底伤害触发后立即切换到Idle
				local latestState = CombatSystem.GetUnitState(unitModel)
				if latestState then
					AnimationController.SwitchToIdle(unitModel, aiData, latestState)
				end
			end)

			-- 关键修复：攻击动画结束时立即切换到Idle，不等下一帧
			local stoppedConnection = animTrack.Stopped:Connect(function()
				-- 断开所有连接
				for _, conn in ipairs(aiData.AnimationConnections) do
					if conn and conn.Connected then
						conn:Disconnect()
					end
				end
				aiData.AnimationConnections = {}

				-- 清空攻击动画引用
				aiData.Tracks.Attack = nil

				DebugLog(string.format("%s 攻击动画已停止", state.UnitId))

				-- 立即切换到Idle，不等下一帧
				if aiData.IsActive and unitModel.Parent and CombatSystem.IsUnitAlive(unitModel) then
					local latestState = CombatSystem.GetUnitState(unitModel)
					if latestState then
						DebugLog(string.format("%s 攻击结束，立即切换到Idle", state.UnitId))
						AnimationController.SwitchToIdle(unitModel, aiData, latestState)
					end
				end
			end)

			table.insert(aiData.AnimationConnections, stoppedConnection)

			return true
		else
			-- 动画加载失败，使用回退机制
			local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
			task.delay(fallbackDelay, function()
				if unitModel and unitModel.Parent and not damageEventFired then
					if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
						damageEventFired = true
						if onDamageCallback then
							onDamageCallback(unitModel, target, isRangedUnit)
						end

						-- 回退机制：触发伤害后立即切换到 Idle
						if aiData.IsActive and unitModel.Parent and CombatSystem.IsUnitAlive(unitModel) then
							local latestState = CombatSystem.GetUnitState(unitModel)
							if latestState then
								DebugLog(string.format("%s (回退)立即切换到Idle", state.UnitId))
								AnimationController.SwitchToIdle(unitModel, aiData, latestState)
							end
						end
					end
				end
			end)

			return true
		end
	else
		-- 没有配置动画，使用回退机制
		local fallbackDelay = state.AttackSpeed * BattleConfig.ANIMATION_FALLBACK_RATIO
		task.delay(fallbackDelay, function()
			if unitModel and unitModel.Parent and not damageEventFired then
				if CombatSystem.GetAttackPhase(unitModel) == BattleConfig.AttackPhase.ATTACKING then
					damageEventFired = true
					if onDamageCallback then
						onDamageCallback(unitModel, target, isRangedUnit)
					end

					-- 回退机制：触发伤害后立即切换到 Idle
					if aiData.IsActive and unitModel.Parent and CombatSystem.IsUnitAlive(unitModel) then
						local latestState = CombatSystem.GetUnitState(unitModel)
						if latestState then
							DebugLog(string.format("%s (回退)立即切换到Idle", state.UnitId))
							AnimationController.SwitchToIdle(unitModel, aiData, latestState)
						end
					end
				end
			end
		end)

		return true
	end
end

--[[
停止所有动画
@param aiData - AI数据
@param fadeTime - 淡出时间（秒）。0表示瞬停，默认0.1秒淡出
]]
function AnimationController.StopAllAnimations(aiData, fadeTime)
	fadeTime = fadeTime or 0.1  -- 默认0.1秒淡出

	-- 停止所有轨道
	for animName, track in pairs(aiData.Tracks) do
		if track and track.IsPlaying then
			pcall(function()
				track:Stop(fadeTime)
			end)
		end
	end
	aiData.Tracks = {}

	-- 断开所有动画事件连接
	for _, connection in ipairs(aiData.AnimationConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	aiData.AnimationConnections = {}

	aiData.CurrentState = nil
end

-- ==================== 私有变量 ====================

local activeAIs = {}
local updateConnection = nil
local deathEventConnection = nil
local accumulatedTime = 0
local isInitialized = false

-- V2.0新增：存储战役行军动画轨道 [unitModel] = AnimationTrack
local marchAnimationTracks = {}

-- ==================== AIData数据结构 ====================

--[[
AIData = {
    UnitModel = Model,
    Humanoid = Humanoid,
    HumanoidRootPart = Part,
    IsActive = boolean,
    LastUpdateTime = number,

    -- V2.0新增：模式切换
    Mode = string,                       -- AI模式: "MarchMode"（行军）/"CombatMode"（战斗）

    -- V2.0.5性能优化：事件驱动寻路
    PathRequested = boolean,             -- 是否已在队列中请求路径（战斗）
    MoveConnection = RBXScriptConnection, -- 当前的 MoveToFinished 连接

    -- V2.4性能优化：MoveTo节流
    LastMoveToPos = Vector3|nil,         -- 上次MoveTo的目标位置
    LastMoveToTick = number,             -- 上次MoveTo的时间戳

    -- V2.4性能优化：Raycast节流与缓存
    LastLoSResult = boolean|nil,         -- 上次直线可达检测结果
    LastLoSCheckTick = number,           -- 上次检测时间戳
    LastLoSDistance = number,            -- 上次检测时的距离

    -- 动画状态
    CurrentState = string,               -- 当前动画状态: "MOVE"/"IDLE"/"ATTACK"
    LastState = string,                  -- 上次动画状态
    Tracks = {                           -- 动画轨道表
        Move = AnimationTrack|nil,
        Idle = AnimationTrack|nil,
        Attack = AnimationTrack|nil,
    },
    AnimationConnections = {},           -- 动画事件连接

    -- 其他
    LastDesiredDirection = Vector3|nil,
}
]]

-- ==================== AI模式枚举 ====================

local AIMode = {
	MARCH = "MarchMode",      -- 行军模式（战役行军）
	COMBAT = "CombatMode",    -- 战斗模式（正常战斗）
}

-- ==================== 距离策略模块 ====================

local UnitAIRangePolicy = {}

function UnitAIRangePolicy.GetDockingDistance(unitState, targetState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		return unitState.AttackRange * BattleConfig.RANGED_DOCKING_RATIO
	else
		local attackerRoot = unitState.UnitInstance:FindFirstChild("HumanoidRootPart")
		if not attackerRoot then
			return unitState.AttackRange
		end

		local attackerDepth = attackerRoot.Size.Z
		local targetDepth = 5

		if targetState and targetState.UnitInstance then
			local targetRoot = targetState.UnitInstance:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				targetDepth = targetRoot.Size.Z
			end
		end

		local contactDistance = (attackerDepth + targetDepth) * 0.5
		local desiredDistance = math.max(contactDistance - BattleConfig.CONTACT_BUFFER, 0)

		local combatProfile = UnitConfig.GetCombatProfile(unitState.UnitId)
		local contactOffset = (combatProfile and combatProfile.ContactOffset) or 0

		return math.max(
			math.min(unitState.AttackRange - BattleConfig.ATTACK_RANGE_TOLERANCE, desiredDistance),
			BattleConfig.MIN_DOCKING_DISTANCE
		) + contactOffset
	end
end

function UnitAIRangePolicy.ShouldEnterAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		local threshold = unitState.AttackRange * BattleConfig.RANGED_ENTER_ATTACK_RATIO
		return distance <= threshold
	else
		local threshold = unitState.AttackRange + BattleConfig.ATTACK_RANGE_TOLERANCE
		return distance <= threshold
	end
end

function UnitAIRangePolicy.ShouldExitAttack(distance, unitState)
	local isRanged = UnitConfig.IsRangedUnit(unitState.UnitId)

	if isRanged then
		local threshold = unitState.AttackRange * BattleConfig.RANGED_EXIT_ATTACK_RATIO
		return distance > threshold
	else
		local threshold = unitState.AttackRange + BattleConfig.ATTACK_RANGE_TOLERANCE + BattleConfig.MOVE_STOP_TOLERANCE
		return distance > threshold
	end
end

-- ==================== 工具函数 ====================

--[[
V2.8新增：攻击状态专用停止函数
只在进入攻击时调用一次，避免每帧重复MoveTo导致前后倾
@param aiData AIData - AI数据
]]
local function StopMovementForAttack(aiData)
	if not aiData or not aiData.Humanoid or not aiData.HumanoidRootPart then
		return
	end

	local h = aiData.Humanoid
	local root = aiData.HumanoidRootPart

	-- 清零移动向量
	h:Move(Vector3.zero, true)

	-- 设置WalkToPoint为当前位置
	h.WalkToPoint = root.Position

	-- 清零速度
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
end

local function GetDistance(model1, model2)
	local part1 = model1:FindFirstChild("HumanoidRootPart") or model1.PrimaryPart
	local part2 = model2:FindFirstChild("HumanoidRootPart") or model2.PrimaryPart

	if not part1 or not part2 then
		return math.huge
	end

	return (part1.Position - part2.Position).Magnitude
end

local function EnsureStopped(unitModel, aiData)
	if not aiData or not aiData.Humanoid or not aiData.HumanoidRootPart then
		return
	end

	aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
end

--[[
软停止函数（V2.8新增）- 避免攻击/停靠阶段重复MoveTo导致前后倾
只在真正需要停止时执行一次，不会每帧重复MoveTo当前位置

@param aiData AIData - AI数据
@return boolean - 是否执行了停止操作
]]
local function SoftStop(aiData)
	if not aiData or not aiData.Humanoid or not aiData.HumanoidRootPart then
		return false
	end

	local humanoid = aiData.Humanoid
	local rootPart = aiData.HumanoidRootPart

	-- 检查是否已经静止：MoveDirection接近0且WalkToPoint离当前位置很近
	local moveDirection = humanoid.MoveDirection
	local walkToPoint = humanoid.WalkToPoint
	local currentPos = rootPart.Position

	local isAlreadyStopped = moveDirection.Magnitude < 0.05 and (walkToPoint - currentPos).Magnitude < 0.5

	if isAlreadyStopped then
		-- 已经静止，无需操作
		return false
	end

	-- 节流检查：避免频繁停止命令
	local now = tick()
	if aiData.LastStopTick and (now - aiData.LastStopTick) < 0.25 then
		return false
	end

	-- 执行停止：优先使用Move(Vector3.zero)，如果WalkToPoint距离太远才用MoveTo
	local distanceToWalkPoint = (walkToPoint - currentPos).Magnitude
	if distanceToWalkPoint > 1.0 then
		-- WalkToPoint距离太远，用MoveTo当前位置停止
		humanoid:MoveTo(currentPos)
	else
		-- 使用Move(Vector3.zero)软停止
		humanoid:Move(Vector3.zero, true)
	end

	aiData.LastStopTick = now
	return true
end

--[[
朝向目标（修复版：增加角度容差，避免每帧微调导致抖动）
只有当角度偏差超过5度时才旋转，且只看水平面防止模型歪斜
@param aiData AIData - AI数据
@param target Model - 目标
@return boolean - 是否成功旋转
]]
local function OrientTowardsTarget(aiData, target)
	if not aiData or not aiData.HumanoidRootPart then
		return false
	end

	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if not targetPart then
		return false
	end

	local myPos = aiData.HumanoidRootPart.Position
	local targetPos = targetPart.Position

	-- 修复：忽略高度差，只看水平面，防止模型歪斜
	local lookVector = (Vector3.new(targetPos.X, myPos.Y, targetPos.Z) - myPos)

	if lookVector.Magnitude > 0.1 then
		-- 计算当前朝向和目标朝向的角度差
		local currentLook = aiData.HumanoidRootPart.CFrame.LookVector
		local dot = currentLook:Dot(lookVector.Unit)

		-- 修复：只有当角度偏差超过 5度 (dot < 0.996) 时才旋转
		-- 避免每帧微调导致的抖动
		if dot < 0.996 then
			local newCFrame = CFrame.lookAt(myPos, myPos + lookVector)
			-- 使用 CFrame 设置 (服务端瞬移旋转是RTS常态，但加上阈值后就不会抖了)
			aiData.HumanoidRootPart.CFrame = newCFrame
			aiData.LastDesiredDirection = lookVector.Unit
			return true
		end
	end

	return false
end

local function ValidateTarget(unitModel)
	local target = CombatSystem.GetTarget(unitModel)

	if not target or not target.Parent then
		return nil
	end

	if not CombatSystem.IsUnitAlive(target) then
		return nil
	end

	return target
end

--[[
节流的MoveTo：避免重复下发相同位置的移动命令
修复方案：增强节流机制，根据目标位置变化量和时间间隔决定是否执行MoveTo
核心原理：如果目标位置变化很小（<0.5 studs）且时间间隔很短（<1秒），则跳过
@param aiData AIData - AI数据
@param targetPos Vector3 - 目标位置
@return boolean - 是否执行了MoveTo
]]
local function ThrottledMoveTo(aiData, targetPos)
	if not aiData or not aiData.Humanoid or not targetPos then
		return false
	end

	local now = tick()

	-- 修复：检查上次目标与当前目标的距离
	if aiData.LastMoveToPos then
		local distDiff = (targetPos - aiData.LastMoveToPos).Magnitude
		local timeDiff = now - (aiData.LastMoveToTick or 0)

		-- 修复逻辑：
		-- 1. 如果目标位置变化很小 (< 0.5 studs)，且上次命令在 1秒内，则完全忽略（让Humanoid继续走原来的指令）
		-- 2. 除非目标发生了显著位移，否则不要打断当前的 MoveTo
		if distDiff < 0.5 and timeDiff < 1.0 then
			return false
		end
	end

	-- 执行MoveTo
	aiData.Humanoid:MoveTo(targetPos)
	aiData.LastMoveToPos = targetPos
	aiData.LastMoveToTick = now

	return true
end

--[[
直线可达检测（V2.4优化：增加缓存，减少射线检测频率）
修正问题：不能仅凭距离判断，必须检测障碍物
@param unitModel Model - 攻击方单位
@param targetModel Model - 目标单位
@param aiData AIData - AI数据（用于缓存）
@return boolean - 是否直线可达
]]
local function HasLineOfSight(unitModel, targetModel, aiData)
	local root = unitModel:FindFirstChild("HumanoidRootPart")
	-- 目标可能是 Model 也可能是 Part
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart or targetModel

	if not root or not targetRoot then
		return false
	end

	local origin = root.Position
	local destination = targetRoot.Position
	local direction = destination - origin
	local distance = direction.Magnitude

	-- 极短距离直接返回 true
	if distance < 2 then
		return true
	end

	-- V2.4 优化：缓存逻辑保持不变
	-- 仅当距离变化>3 studs 或超过 0.25 秒未检查时才重新射线
	if aiData and aiData.LastLoSCheckTick then
		local timeDiff = tick() - aiData.LastLoSCheckTick
		local distanceDiff = aiData.LastLoSDistance and math.abs(distance - aiData.LastLoSDistance) or math.huge

		if timeDiff < 0.25 and distanceDiff < 3 then
			-- 使用缓存结果
			return aiData.LastLoSResult or false
		end
	end

	-- V2.5寻路优化：关键修改 - 过滤器排除所有兵种
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- 🔥 关键修改：过滤器不仅要排除自己，还要排除所有兵种和目标 🔥
	local filterList = { unitModel, targetModel }

	-- 如果workspace下有Units文件夹存放所有兵种，直接排除
	local unitsFolder = workspace:FindFirstChild("Units")
	if unitsFolder then
		table.insert(filterList, unitsFolder)
	end

	-- V2.5优化：使用PhysicsService碰撞组（如果已实施CollisionSystem）
	-- 尝试使用Units碰撞组，让射线忽略所有兵种
	local success, _ = pcall(function()
		rayParams.CollisionGroup = "Units"
	end)
	if not success then
		-- 如果碰撞组未设置，回退到FilterDescendantsInstances
		rayParams.CollisionGroup = "Default"
	end

	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(origin, direction, rayParams)

	-- 如果结果为 nil，说明直线无障碍
	local losResult = (result == nil)

	-- V2.4 优化：更新缓存
	if aiData then
		aiData.LastLoSResult = losResult
		aiData.LastLoSCheckTick = tick()
		aiData.LastLoSDistance = distance
	end

	return losResult
end

-- ==================== 状态处理函数（重构版） ====================

--[[
处理SEEKING状态：寻找目标 (V2.4新增：目标黏滞机制)
目标黏滞逻辑：
1. 仅当新目标比当前目标近5+ studs时才切换
2. 防止目标抖动和频繁切换
3. 添加目标超时机制
]]
local function HandleSeeking(unitModel, aiData, state)
	local newTarget = UnitAI.FindNearestEnemy(unitModel)
	local currentTarget = CombatSystem.GetTarget(unitModel)

	-- V2.4新增：目标黏滞检查
	if newTarget then
		-- 如果已有目标，检查是否应该切换
		if currentTarget and currentTarget.Parent then
			-- 计算距离差
			local newTargetDistance = GetDistance(unitModel, newTarget)
			local currentTargetDistance = GetDistance(unitModel, currentTarget)
			local distanceDifference = currentTargetDistance - newTargetDistance

			-- V2.4：只有当新目标至少近5 studs时才切换
			-- 防止单位频繁切换目标造成抖动
			if distanceDifference >= 5 then
				-- 新目标足够接近，切换
				CombatSystem.SetTarget(unitModel, newTarget)
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
				LogStateChange(state.UnitId, "SEEKING", "MOVING",
					string.format("切换目标 (节省%.1f studs)", distanceDifference))

				-- V2.4新增：重置目标超时计数
				if not aiData.TargetLockTick then
					aiData.TargetLockTick = {}
				end
				aiData.TargetLockTick[newTarget] = tick()
			else
				-- 新目标不够接近，保持当前目标
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
				LogStateChange(state.UnitId, "SEEKING", "MOVING",
					string.format("保持目标 (新目标仅近%.1f studs)", distanceDifference))
			end
		else
			-- 没有当前目标，直接采用新目标
			CombatSystem.SetTarget(unitModel, newTarget)
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
			LogStateChange(state.UnitId, "SEEKING", "MOVING", "找到目标")

			-- V2.4新增：记录目标锁定时间
			if not aiData.TargetLockTick then
				aiData.TargetLockTick = {}
			end
			aiData.TargetLockTick[newTarget] = tick()
		end
	else
		-- 没有找到新目标
		if currentTarget and currentTarget.Parent then
			-- 还有当前目标，检查超时
			-- V2.4新增：如果追踪当前目标超过30秒，强制放弃
			local targetLockTime = aiData.TargetLockTick and aiData.TargetLockTick[currentTarget] or tick()
			local lockDuration = tick() - targetLockTime

			if lockDuration > 30 then
				-- 目标超时，放弃
				DebugLog(string.format("%s 目标超时(%.1f秒)，放弃并寻找新目标",
					state.UnitId, lockDuration))
				CombatSystem.SetTarget(unitModel, nil)
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
				AnimationController.SwitchToIdle(unitModel, aiData, state)
			else
				-- 保持当前目标，继续移动
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
			end
		else
			-- 无任何目标，切换到IDLE
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
			AnimationController.SwitchToIdle(unitModel, aiData, state)
		end
	end
end

--[[
处理MOVING状态：移动到目标（V2.1.2修正 - 恢复MoveToFinished事件）
核心修正：
1. 恢复MoveToFinished事件注册（V2.1.1错误删除）
2. 简化移动逻辑，优先直线移动
3. 被阻挡时正确触发重新寻路
]]
local function HandleMoving(unitModel, aiData, state)
	-- 验证目标
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		LogStateChange(state.UnitId, "MOVING", "SEEKING", "目标失效")
		-- 目标失效，清理路径并切换到Idle
		PathService.ClearPath(unitModel)
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		-- V2.1.3修正：不断开MoveConnection，保持事件连接
		aiData.PathRequested = false
		return
	end

	-- 确保播放移动动画
	AnimationController.SwitchToMove(unitModel, aiData, state)

	-- 检查距离
	local distance = GetDistance(unitModel, target)

	-- 远程单位提前停止策略
	local isRanged = UnitConfig.IsRangedUnit(state.UnitId)
	if isRanged then
		local targetState = CombatSystem.GetUnitState(target)
		local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

		if distance <= dockingDistance + 4 then
			DebugLog(string.format("%s (远程) 接近停靠距离(%.1f <= %.1f+4)，提前停止",
				state.UnitId, distance, dockingDistance))
			-- V2.8修复：使用StopMovementForAttack替代SoftStop
			StopMovementForAttack(aiData)
			PathService.ClearPath(unitModel)

			if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
				LogStateChange(state.UnitId, "MOVING", "ATTACKING", string.format("提前停止后距离符合攻击条件(%.1f)", distance))

				-- 停止移动动画并立刻播放Idle
				if aiData.Tracks.Move then
					SafeStopAnimation(aiData.Tracks.Move)
					aiData.Tracks.Move = nil
				end

				-- 立刻播放Idle，准备攻击
				AnimationController.SwitchToIdle(unitModel, aiData, state)
				-- V2.1.3修正：不断开MoveConnection，保持事件连接
				aiData.PathRequested = false

				-- V2.8新增：标记已经停止
				aiData.StoppedForAttack = tick()
				return
			end
		end
	end

	-- 判断是否应该进入攻击
	if UnitAIRangePolicy.ShouldEnterAttack(distance, state) then
		-- V2.8修复：使用StopMovementForAttack替代SoftStop，只停一次
		StopMovementForAttack(aiData)
		PathService.ClearPath(unitModel)

		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.ATTACKING)
		LogStateChange(state.UnitId, "MOVING", "ATTACKING", string.format("距离%.1f <= 阈值", distance))

		-- 停止移动动画，并立刻播放Idle
		if aiData.Tracks.Move then
			SafeStopAnimation(aiData.Tracks.Move)
			aiData.Tracks.Move = nil
		end

		-- 立刻播放Idle，准备攻击
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		-- V2.1.3修正：不断开MoveConnection，保持事件连接
		aiData.PathRequested = false

		-- V2.8新增：标记已经停止，防止HandleAttacking重复停止
		aiData.StoppedForAttack = tick()
		return
	end

	-- ==================== V2.1.2核心修正：MoveToFinished事件驱动已在StartAI中注册 ====================
	-- V2.1.3优化：MoveConnection现在在StartAI中注册，只在StopAI中断开，避免因状态切换导致延迟

	-- 检查是否有可用路径
	local pathState = PathService.GetPathState(unitModel)
	local hasValidPath = pathState and pathState.Status == "Success" and pathState.Waypoints and #pathState.Waypoints > 0

	-- 策略1：如果有路径，使用路径移动
	if hasValidPath then
		if PathService.HasReachedWaypoint(unitModel) then
			local hasMore = PathService.AdvancePath(unitModel)
			if not hasMore then
				-- 路径走完，清理
				PathService.ClearPath(unitModel)
				hasValidPath = false
			end
		end

		if hasValidPath then
			local nextWaypoint = PathService.GetNextWaypoint(unitModel)
			if nextWaypoint then
				ThrottledMoveTo(aiData, nextWaypoint)
				return
			end
		end
	end

	-- 策略2：优先直线移动（简单场景，无寻路开销）
	if HasLineOfSight(unitModel, target, aiData) then
		-- 直线可达，但要计算停靠距离避免转圈
		local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
		if targetPart then
			-- 🔥修复原地转圈：计算停靠位置而不是直接移动到目标
			local targetState = CombatSystem.GetUnitState(target)
			local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

			-- 计算方向和停靠位置
			local myPos = aiData.HumanoidRootPart.Position
			local targetPos = targetPart.Position
			local direction = (targetPos - myPos).Unit
			local moveTarget = targetPos - direction * dockingDistance

			-- 检查是否已足够接近停靠点
			-- 修复：增加容差，不要在临界值处急停
			-- 只有当距离非常近（< 0.5）才强制停止，否则让 Humanoid 自己走到终点
			local distanceToMoveTarget = (moveTarget - myPos).Magnitude
			if distanceToMoveTarget > 0.5 then
				-- 还需要移动，移动到停靠位置
				ThrottledMoveTo(aiData, moveTarget)
				DebugLog(string.format("%s 直线移动到停靠点，距离=%.1f", state.UnitId, distanceToMoveTarget))
			else
				-- 已经很接近了，只有真的到了才停止
				SoftStop(aiData)
				DebugLog(string.format("%s 已接近停靠点，停止移动", state.UnitId))
			end
		end

		-- 清理旧路径
		if pathState then
			PathService.ClearPath(unitModel)
		end

		return
	end

	-- 策略3：直线不可达，且无路径时，异步请求寻路（仅首次）
	if not aiData.PathRequested then
		aiData.PathRequested = true
		DebugLog(string.format("%s 直线阻挡，异步请求寻路", state.UnitId))

		PathService.RequestPathAsync(unitModel, target, state.UnitId, function(success, newPathState)
			aiData.PathRequested = false
			if not aiData.IsActive or not CombatSystem.IsUnitAlive(unitModel) then
				return
			end

			if success and newPathState and newPathState.Waypoints and #newPathState.Waypoints > 0 then
				DebugLog(string.format("%s 寻路成功，路径点数: %d", state.UnitId, #newPathState.Waypoints))
				-- 🔥修复：寻路成功后立即开始移动第一个路径点
				local nextWaypoint = PathService.GetNextWaypoint(unitModel)
				if nextWaypoint then
					ThrottledMoveTo(aiData, nextWaypoint)
				end
			else
				DebugLog(string.format("%s 寻路失败，继续直线移动", state.UnitId))
			end
		end)

		-- 🔥修复原地转圈：等待寻路期间原地待命，不要MoveTo目标
		-- 避免触发Humanoid的默认寻路导致原地转圈
		DebugLog(string.format("%s 路径计算中，原地等待", state.UnitId))
		SoftStop(aiData)
	else
		-- 🔥修复：已经在排队中，检查路径状态
		local pathStatus = PathService.GetPathStatus(unitModel)
		if pathStatus == "Computing" or pathStatus == "Queued" then
			-- 路径还在计算中，原地等待
			DebugLog(string.format("%s 路径计算中(%s)，原地等待", state.UnitId, pathStatus))
			SoftStop(aiData)
		else
			-- 路径计算失败或已完成，可以尝试直线移动（但保持停靠距离）
			local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
			if targetPart then
				local targetState = CombatSystem.GetUnitState(target)
				local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

				local myPos = aiData.HumanoidRootPart.Position
				local targetPos = targetPart.Position
				local direction = (targetPos - myPos).Unit
				local moveTarget = targetPos - direction * dockingDistance

				ThrottledMoveTo(aiData, moveTarget)
			end
		end
	end
end

--[[
处理ATTACKING状态：攻击目标（V2.8优化 - 减少重复停止命令）
]]
local function HandleAttacking(unitModel, aiData, state)
	-- 验证目标
	local target = ValidateTarget(unitModel)
	if not target then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
		LogStateChange(state.UnitId, "ATTACKING", "SEEKING", "目标失效")
		-- 切换到Idle并清理路径
		PathService.ClearPath(unitModel)  -- ⭐使用PathService
		AnimationController.SwitchToIdle(unitModel, aiData, state)
		-- 清除停止标记
		aiData.StoppedForAttack = nil
		return
	end

	-- 检查距离
	local distance = GetDistance(unitModel, target)

	-- 判断是否应该退出攻击
	if UnitAIRangePolicy.ShouldExitAttack(distance, state) then
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
		LogStateChange(state.UnitId, "ATTACKING", "MOVING", string.format("距离%.1f > 脱离阈值", distance))

		-- 关键修复：脱离攻击状态，清理路径后切换到Move
		PathService.ClearPath(unitModel)  -- ⭐使用PathService
		AnimationController.SwitchToMove(unitModel, aiData, state)
		-- 清除停止标记
		aiData.StoppedForAttack = nil
		return
	end

	-- V2.8修复：智能停止策略，避免每帧重复MoveTo
	-- 只在以下情况补充停止：
	-- 1. 超过0.5秒未停止过
	-- 2. 且Humanoid的MoveDirection有速度（说明在移动）
	local now = tick()
	local lastStopTime = aiData.StoppedForAttack or 0
	local timeSinceLastStop = now - lastStopTime

	if timeSinceLastStop > 0.5 then
		local humanoid = aiData.Humanoid
		if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
			-- Humanoid还在移动，需要停止
			StopMovementForAttack(aiData)
			aiData.StoppedForAttack = now
		end
	end

	-- 朝向目标
	OrientTowardsTarget(aiData, target)

	-- 核心修复：攻击逻辑
	-- 情况1：正在播放攻击动画 → 什么都不做，等待动画结束回调
	if aiData.Tracks.Attack and aiData.Tracks.Attack.IsPlaying then
		-- 攻击动画播放中，保持等待
		return
	end

	-- 情况2：冷却中（CanAttack()为false） → 维持Idle动画
	if not CombatSystem.CanAttack(unitModel) then
		-- 确保Idle动画在播放
		-- 使用直接检查而非CurrentState，因为CurrentState可能未初始化
		if not aiData.Tracks.Idle or not aiData.Tracks.Idle.IsPlaying then
			AnimationController.SwitchToIdle(unitModel, aiData, state)
		end
		return
	end

	-- 情况3：可以攻击（CanAttack()为true 且 没有攻击动画在播） → 触发新一轮攻击
	UnitAI.TriggerAttack(unitModel, target, state, aiData)
end

-- ==================== AI更新 ====================

-- V2.1性能优化：不同AI状态使用不同更新间隔
local AI_UPDATE_INTERVALS = {
	[BattleConfig.AIState.SEEKING] = 0.6,    -- 从0.5→0.6: 寻找目标频率降低
	[BattleConfig.AIState.MOVING] = 0.2,     -- 保持: 移动状态需要较频繁检查
	[BattleConfig.AIState.ATTACKING] = 0.1,  -- 保持: 攻击状态需要实时判断
	[BattleConfig.AIState.IDLE] = 1.0,       -- 从0.5→1.0: 待机状态频率可以大幅降低
}

-- V2.3性能优化：Round-robin分帧调度
-- 将100个单位分成4批，每帧只处理1/4，降低单帧CPU峰值
local AI_BATCH_COUNT = 4  -- 从3增加到4批，更平滑
local currentBatch = 0    -- 当前批次（0, 1, 2, 3循环）
local nextBatchIndex = 0  -- 下一个单位应分配的批次（round-robin计数器）

local function UpdateAllAIs()
	local currentTime = tick()

	-- V2.3：轮询下一个批次
	currentBatch = (currentBatch + 1) % AI_BATCH_COUNT

	-- 临时调试：确认AI更新循环运行
	if currentBatch == 0 then
		local activeCount = 0
		for _, aiData in pairs(activeAIs) do
			if aiData.IsActive then
				activeCount = activeCount + 1
			end
		end
	end

	for unitModel, aiData in pairs(activeAIs) do
		if not CombatSystem.IsUnitAlive(unitModel) then
			continue
		end

		if not aiData.IsActive then
			continue
		end

		-- V2.3优化：Round-robin分批处理
		-- 每个单位分配到一个固定批次，只在对应帧处理
		local unitBatch = aiData.BatchIndex or 0
		if unitBatch ~= currentBatch then
			continue  -- 跳过不属于当前批次的单位
		end

		-- V2.1优化：状态节流
		local state = CombatSystem.GetUnitState(unitModel)
		if state then
			local updateInterval = AI_UPDATE_INTERVALS[state.State] or 0.2

			-- 检查是否达到更新间隔
			if currentTime - (aiData.LastUpdateTime or 0) < updateInterval then
				continue
			end
		end

		local success, err = pcall(function()
			UnitAI.UpdateAI(unitModel, aiData)
		end)

		if not success then
			WarnLog("AI更新失败:", err)
		end

		aiData.LastUpdateTime = currentTime
	end
end

-- ==================== 公共接口 ====================

function UnitAI.Initialize()
	if isInitialized then
		WarnLog("AI系统已经初始化过了")
		return true
	end

	DebugLog("正在初始化AI系统...")

	updateConnection = RunService.Heartbeat:Connect(function(dt)
		accumulatedTime = accumulatedTime + dt
		if accumulatedTime >= BattleConfig.AI_BATCH_UPDATE_INTERVAL then
			UpdateAllAIs()
			accumulatedTime = 0
		end
	end)

	local eventsFolder = ReplicatedStorage:WaitForChild("Events")
	local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")

	if battleEventsFolder then
		local unitDeathEvent = battleEventsFolder:FindFirstChild("UnitDeath")

		if unitDeathEvent then
			deathEventConnection = unitDeathEvent.Event:Connect(function(deadUnit, killer, battleId)
				UnitAI.OnTargetDeath(deadUnit, battleId)
			end)
		end
	end

	isInitialized = true

	DebugLog(string.format("AI系统初始化完成 (节流间隔: %.2f秒)", BattleConfig.AI_BATCH_UPDATE_INTERVAL))
	return true
end

function UnitAI.Shutdown()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	if deathEventConnection then
		deathEventConnection:Disconnect()
		deathEventConnection = nil
	end

	activeAIs = {}
	isInitialized = false

	DebugLog("AI系统已关闭")
end

function UnitAI.StartAI(unitModel)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("StartAI失败: unitModel无效")
		return false
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		WarnLog("StartAI失败: 找不到Humanoid或HumanoidRootPart")
		return false
	end

	local aiData = {
		UnitModel = unitModel,
		Humanoid = humanoid,
		HumanoidRootPart = rootPart,
		IsActive = true,
		LastUpdateTime = 0,

		-- V2.0新增：默认为战斗模式
		Mode = AIMode.COMBAT,

		-- V2.0.5性能优化：事件驱动寻路
		PathRequested = false,     -- 是否已在队列中请求路径（战斗）
		MoveConnection = nil,      -- 当前的 MoveToFinished 连接

		-- V2.4性能优化：MoveTo节流
		LastMoveToPos = nil,       -- 上次MoveTo的目标位置
		LastMoveToTick = 0,        -- 上次MoveTo的时间戳

		-- V2.4性能优化：Raycast节流与缓存
		LastLoSResult = nil,       -- 上次直线可达检测结果
		LastLoSCheckTick = 0,      -- 上次检测时间戳
		LastLoSDistance = 0,       -- 上次检测时的距离

		-- 动画状态
		CurrentState = nil,
		LastState = nil,
		Tracks = {},
		AnimationConnections = {},

		LastDesiredDirection = nil,

		-- V2.0.4新增：路径命令安全容错
		LastPathCommandTime = 0,  -- 上次成功发送MoveTo命令的时间

		-- V2.3新增：Round-robin批次索引（分帧调度）
		BatchIndex = nextBatchIndex,

		-- V2.4新增：目标黏滞机制
		TargetLockTick = {},       -- [target] = tick() 记录每个目标的锁定时间，防止频繁切换
	}

	-- V2.3: 推进批次计数器（round-robin）
	nextBatchIndex = (nextBatchIndex + 1) % AI_BATCH_COUNT

	activeAIs[unitModel] = aiData

	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		humanoid.WalkSpeed = state.MoveSpeed
	else
		-- V2.0 Sanity Check: 如果CombatSystem没有状态，说明InitializeUnit未被调用
		WarnLog("⚠️ StartAI: 单位没有CombatSystem状态! 请确保已调用CombatSystem.InitializeUnit")
		WarnLog("   单位名称:", unitModel.Name)
		WarnLog("   UnitId属性:", unitModel:GetAttribute("UnitId") or "nil")
		WarnLog("   Level属性:", unitModel:GetAttribute("Level") or "nil")
		return false
	end

	local unitId = state and state.UnitId or "Unknown"
	DebugLog(string.format("启动AI: %s", unitId))

	-- ⭐⭐⭐ 预加载所有战斗动画,避免首次战斗时动画资源未缓存导致卡顿 ⭐⭐⭐
	PreloadAllAnimations(unitModel, humanoid, unitId)

	-- ⭐⭐⭐ V2.8修复：彻底停掉默认Animate，避免和自定义动画混播 ⭐⭐⭐
	DisableAllAnimateScripts(unitModel, unitId)

	-- ⭐⭐⭐ 设置网络所有权为服务器，防止客户端物理干扰导致抖动 ⭐⭐⭐
	if rootPart then
		pcall(function()
			rootPart:SetNetworkOwner(nil)  -- 强制服务器拥有物理权，防止客户端干扰
		end)
	end

	-- V2.1.3优化：在StartAI时就注册MoveToFinished事件，只在StopAI时断开
	-- 这样避免因状态切换导致的连接断开，配合节流机制不会有延迟
	aiData.MoveConnection = humanoid.MoveToFinished:Connect(function(reached)
		-- 事件触发时检查单位状态
		if not aiData.IsActive or not CombatSystem.IsUnitAlive(unitModel) then
			return
		end

		local currentState = CombatSystem.GetUnitState(unitModel)
		if not currentState or currentState.State ~= BattleConfig.AIState.MOVING then
			-- 不在MOVING状态，忽略此事件
			return
		end

		local currentTarget = ValidateTarget(unitModel)
		if not currentTarget then
			return
		end

		-- 检查是否到达攻击范围
		local currentDistance = GetDistance(unitModel, currentTarget)
		if UnitAIRangePolicy.ShouldEnterAttack(currentDistance, currentState) then
			-- 已到达攻击范围，无需继续移动
			return
		end

		-- V2.1.2修正：正确处理MoveToFinished
		if reached then
			-- reached = true：成功到达MoveTo目标点
			-- 如果有路径，推进到下一个waypoint
			local pathState = PathService.GetPathState(unitModel)
			if pathState and pathState.Status == "Success" then
				if PathService.AdvancePath(unitModel) then
					local nextWaypoint = PathService.GetNextWaypoint(unitModel)
					if nextWaypoint then
						ThrottledMoveTo(aiData, nextWaypoint)
					else
						-- 🔥修复：路径走完，检查是否可以直线到达
						local targetPos = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
						if targetPos then
							if HasLineOfSight(unitModel, currentTarget, aiData) then
								-- 可以直线到达，移动到停靠位置
								local targetState = CombatSystem.GetUnitState(currentTarget)
								local dockingDistance = UnitAIRangePolicy.GetDockingDistance(currentState, targetState)

								local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
								if rootPart then
									local myPos = rootPart.Position
									local direction = (targetPos.Position - myPos).Unit
									local moveTarget = targetPos.Position - direction * dockingDistance

									ThrottledMoveTo(aiData, moveTarget)
								end
							else
								-- 不可直线到达，请求新路径
								DebugLog(string.format("%s 路径走完但无直线视野，请求新路径", currentState.UnitId))
								PathService.ForceRepath(unitModel)
								aiData.PathRequested = false  -- 允许重新请求
							end
						end
					end
				else
					-- 🔥修复：路径走完，检查是否可以直线到达
					local targetPos = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
					if targetPos then
						if HasLineOfSight(unitModel, currentTarget, aiData) then
							-- 可以直线到达，移动到停靠位置
							local targetState = CombatSystem.GetUnitState(currentTarget)
							local dockingDistance = UnitAIRangePolicy.GetDockingDistance(currentState, targetState)

							local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
							if rootPart then
								local myPos = rootPart.Position
								local direction = (targetPos.Position - myPos).Unit
								local moveTarget = targetPos.Position - direction * dockingDistance

								ThrottledMoveTo(aiData, moveTarget)
							end
						else
							-- 不可直线到达，请求新路径
							DebugLog(string.format("%s 路径走完但无直线视野，请求新路径", currentState.UnitId))
							PathService.ForceRepath(unitModel)
							aiData.PathRequested = false  -- 允许重新请求
						end
					end
				end
			else
				-- 🔥修复：没有路径时检查是否真的可以直线到达
				-- 这种情况发生在：直线可达、寻路失败、或寻路未完成
				local pathStatus = PathService.GetPathStatus(unitModel)

				-- 如果路径正在计算，原地等待
				if pathStatus == "Computing" or pathStatus == "Queued" then
					DebugLog(string.format("%s 路径计算中(%s)，原地等待", currentState.UnitId, pathStatus))
					SoftStop(aiData)
					return
				end

				-- 检查是否可以直线到达
				local targetPos = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
				if targetPos then
					if HasLineOfSight(unitModel, currentTarget, aiData) then
						-- 可以直线到达，移动到停靠位置
						local targetState = CombatSystem.GetUnitState(currentTarget)
						local dockingDistance = UnitAIRangePolicy.GetDockingDistance(currentState, targetState)

						local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
						if rootPart then
							local myPos = rootPart.Position
							local direction = (targetPos.Position - myPos).Unit
							local moveTarget = targetPos.Position - direction * dockingDistance

							local distanceToMoveTarget = (moveTarget - myPos).Magnitude
							if distanceToMoveTarget > 1.5 then
								ThrottledMoveTo(aiData, moveTarget)
							else
								SoftStop(aiData)
							end
						end
					else
						-- 不可直线到达且没有路径，请求寻路
						if not aiData.PathRequested then
							DebugLog(string.format("%s 无路径且无直线视野，请求寻路", currentState.UnitId))
							PathService.ForceRepath(unitModel)
							aiData.PathRequested = false  -- 允许重新请求
						else
							-- 路径请求中，原地等待
							SoftStop(aiData)
						end
					end
				end
			end
		else
			-- V2.5寻路优化：reached = false，MoveTo被打断或无法到达（被阻挡/拥挤）
			-- 🔥 优化：不要立即请求完整寻路 🔥

			-- 1. 检查距离：如果距离目标非常近，可能是挤到了，直接算到达或忽略
			local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
			local targetRootPart = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
			if rootPart and targetRootPart then
				local dist = (targetRootPart.Position - rootPart.Position).Magnitude
				if dist < 5 then
					-- 🔥修复：距离很近被挡住，检查是否可以直线到达
					if HasLineOfSight(unitModel, currentTarget, aiData) then
						-- 可以直线到达，计算停靠位置移动
						local targetState = CombatSystem.GetUnitState(currentTarget)
						local dockingDistance = UnitAIRangePolicy.GetDockingDistance(currentState, targetState)

						local myPos = rootPart.Position
						local targetPos = targetRootPart.Position
						local direction = (targetPos - myPos).Unit
						local moveTarget = targetPos - direction * dockingDistance

						local distanceToMoveTarget = (moveTarget - myPos).Magnitude
						if distanceToMoveTarget > 1.5 then
							ThrottledMoveTo(aiData, moveTarget)
							DebugLog(string.format("%s 距离很近(%.1f)被阻挡，直线移动到停靠点", currentState.UnitId, dist))
						else
							SoftStop(aiData)
						end
					else
						-- 不可直线到达，不要MoveTo，等待路径
						DebugLog(string.format("%s 距离很近(%.1f)被阻挡但无直线视野，原地等待", currentState.UnitId, dist))
						SoftStop(aiData)
					end
					return
				end
			end

			-- 2. 随机延迟重试：防止30个兵同一帧请求寻路
			if not aiData.PathRequested then
				aiData.PathRequested = true

				-- V2.5优化：延迟 0.1 到 0.5 秒，分散计算压力
				local delayTime = math.random() * 0.4 + 0.1
				DebugLog(string.format("%s MoveTo被阻挡，将在%.2f秒后检查是否需要寻路", currentState.UnitId, delayTime))

				task.delay(delayTime, function()
					if not aiData.IsActive or not CombatSystem.IsUnitAlive(unitModel) then
						aiData.PathRequested = false
						return
					end

					-- 再次检查目标是否仍然有效
					local delayedTarget = ValidateTarget(unitModel)
					if not delayedTarget then
						aiData.PathRequested = false
						return
					end

					-- V2.5关键优化：再次检查是否真的需要寻路（可能延迟期间已经直线走过去了）
					if HasLineOfSight(unitModel, delayedTarget, aiData) then
						aiData.PathRequested = false
						-- 直线能到就别寻路了
						DebugLog(string.format("%s 延迟后发现直线可达，取消寻路请求", currentState.UnitId))

						-- 🔥修复倾倒卡顿：直线可达时使用停靠点而非目标原点
						local tPos = delayedTarget:FindFirstChild("HumanoidRootPart") or delayedTarget.PrimaryPart
						if tPos then
							local delayedTargetState = CombatSystem.GetUnitState(delayedTarget)
							local dockingDistance = UnitAIRangePolicy.GetDockingDistance(currentState, delayedTargetState)

							local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
							if rootPart then
								local myPos = rootPart.Position
								local targetPos = tPos.Position
								local direction = (targetPos - myPos).Unit
								local moveTarget = targetPos - direction * dockingDistance

								local distanceToMoveTarget = (moveTarget - myPos).Magnitude
								if distanceToMoveTarget > 1.5 then
									ThrottledMoveTo(aiData, moveTarget)
									DebugLog(string.format("%s 延迟后直线移动到停靠点，距离=%.1f", currentState.UnitId, distanceToMoveTarget))
								else
									SoftStop(aiData)
								end
							end
						end
						return
					end

					-- 确实需要寻路，再请求
					DebugLog(string.format("%s 延迟后确认需要寻路，发起请求", currentState.UnitId))
					PathService.RequestPathAsync(unitModel, delayedTarget, currentState.UnitId, function(success, pathState)
						aiData.PathRequested = false
						if not aiData.IsActive or not CombatSystem.IsUnitAlive(unitModel) then
							return
						end

						if success and pathState and pathState.Waypoints and #pathState.Waypoints > 0 then
							DebugLog(string.format("%s 重新寻路成功，路径点数: %d", currentState.UnitId, #pathState.Waypoints))
							-- 下一次Update会使用这个路径
						else
							DebugLog(string.format("%s 重新寻路失败，继续直线移动", currentState.UnitId))
						end
					end)
				end)
			end
		end
	end)

	task.defer(function()
		if not aiData.IsActive then
			return
		end

		local target = UnitAI.FindNearestEnemy(unitModel)

		if target then
			CombatSystem.SetTarget(unitModel, target)
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.MOVING)
			LogStateChange(unitId, "IDLE", "MOVING", "AI启动，发现目标")
			-- AI启动时播放移动动画
			if state then
				AnimationController.SwitchToMove(unitModel, aiData, state)
			end
		else
			CombatSystem.SetAIState(unitModel, BattleConfig.AIState.IDLE)
			-- 无目标时播放Idle
			if state then
				AnimationController.SwitchToIdle(unitModel, aiData, state)
			end
		end
	end)

	return true
end

--[[
停止AI系统 - 重构版（使用PathService）
@param unitModel - 兵种模型
@param options - 可选参数表
    skipMoveTo (bool): 是否跳过MoveTo（死亡时用true）
    disableAnimate (bool): 是否禁用Animate脚本（死亡时用true）
    stopFadeTime (number): 停止动画的淡出时间（死亡时用0表示瞬停）
]]
function UnitAI.StopAI(unitModel, options)
	local aiData = activeAIs[unitModel]

	if aiData then
		aiData.IsActive = false

		-- 处理options参数（支持向后兼容的布尔值）
		local opts = {}
		if type(options) == "boolean" then
			-- 向后兼容：UnitAI.StopAI(unitModel, true) → skipMoveTo=true
			opts.skipMoveTo = options
		elseif type(options) == "table" then
			opts = options
		end

		-- V2.0.5性能优化：断开MoveToFinished连接
		if aiData.MoveConnection then
			aiData.MoveConnection:Disconnect()
			aiData.MoveConnection = nil
		end

		-- 步骤1: 禁用Animate脚本（如果需要）
		-- 使用递归查找，兼容任何位置的Animate脚本
		if opts.disableAnimate then
			local unitId = aiData.UnitModel and aiData.UnitModel.Name or "Unknown"
			DisableAllAnimateScripts(unitModel, unitId)
		end

		-- 步骤2: 停止所有动画（带可配置的淡出时间）
		local fadeTime = opts.stopFadeTime or 0.1  -- 默认0.1秒淡出，死亡时为0
		AnimationController.StopAllAnimations(aiData, fadeTime)

		-- 步骤3: 清理路径数据
		PathService.ClearPath(unitModel)  -- ⭐使用PathService

		-- 步骤4: 停止移动 - 明确尊重 skipMoveTo 参数
		if not opts.skipMoveTo and aiData.Humanoid and aiData.HumanoidRootPart then
			aiData.Humanoid:MoveTo(aiData.HumanoidRootPart.Position)
		end

		activeAIs[unitModel] = nil

		DebugLog("停止AI")
	end
end

function UnitAI.UpdateAI(unitModel, aiData)
	local state = CombatSystem.GetUnitState(unitModel)

	if not state or not state.IsAlive then
		UnitAI.StopAI(unitModel)
		return
	end

	-- V2.0新增：检查AI模式，行军模式下不执行战斗AI
	if aiData.Mode == AIMode.MARCH then
		return
	end

	local aiState = state.State

	if aiState == BattleConfig.AIState.IDLE or aiState == BattleConfig.AIState.SEEKING then
		HandleSeeking(unitModel, aiData, state)

	elseif aiState == BattleConfig.AIState.MOVING then
		HandleMoving(unitModel, aiData, state)

	elseif aiState == BattleConfig.AIState.ATTACKING then
		HandleAttacking(unitModel, aiData, state)
	end
end

function UnitAI.FindNearestEnemy(unitModel)
	-- V2.4优化：快速范围检查，避免不必要的寻敌
	local state = CombatSystem.GetUnitState(unitModel)
	if not state then
		return nil
	end

	local unitConfig = UnitConfig.Units[state.UnitId]
	if not unitConfig then
		return nil
	end

	-- 获取攻击范围（带1.5倍安全系数）
	local baseRange = unitConfig.AttackRange or 20
	local extendedRange = baseRange * 1.5

	-- 快速距离预检查：如果单位距离敌人太远，可能不值得寻敌
	local enemy, distance = UnitManager.GetClosestEnemy(unitModel, BattleConfig.TARGET_SEARCH_RANGE)

	if not enemy then
		return nil
	end

	-- 距离过远直接返回nil，节省后续复杂计算
	if distance > extendedRange and distance > BattleConfig.TARGET_SEARCH_RANGE * 0.7 then
		return nil
	end

	return enemy
end

function UnitAI.MoveToTarget(unitModel, target, aiData, state)
	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart

	if not targetPart then
		return
	end

	local myPos = aiData.HumanoidRootPart.Position
	local targetPos = targetPart.Position

	local offset = targetPos - myPos
	local currentDistance = offset.Magnitude

	if currentDistance < 0.1 then
		DebugLog(string.format("%s 距离过近(%.3f)，停止移动避免零向量", state.UnitId, currentDistance))
		SoftStop(aiData)

		if aiData.LastDesiredDirection then
			aiData.HumanoidRootPart.CFrame = CFrame.new(
				aiData.HumanoidRootPart.Position,
				aiData.HumanoidRootPart.Position + aiData.LastDesiredDirection
			)
		end
		return
	end

	local targetState = CombatSystem.GetUnitState(target)
	local dockingDistance = UnitAIRangePolicy.GetDockingDistance(state, targetState)

	local moveDistance = currentDistance - dockingDistance

	if moveDistance <= 0.5 then
		DebugLog(string.format("%s 已到达停靠范围，当前距离=%.1f，停靠距离=%.1f",
			state.UnitId, currentDistance, dockingDistance))
		SoftStop(aiData)
		return
	end

	local direction = offset.Unit

	aiData.LastDesiredDirection = direction

	local moveTarget = targetPos - direction * dockingDistance

	local distanceToMoveTarget = (moveTarget - myPos).Magnitude
	if distanceToMoveTarget < 0.5 then
		DebugLog(string.format("%s 移动距离过小(%.2f)，停止避免抖动", state.UnitId, distanceToMoveTarget))
		SoftStop(aiData)
		return
	end

	ThrottledMoveTo(aiData, moveTarget)

	local unitType = UnitConfig.IsRangedUnit(state.UnitId) and "远程" or "近战"
	DebugLog(string.format("%s (%s) 移动中，当前距离=%.1f，停靠距离=%.1f，需移动=%.1f",
		state.UnitId, unitType, currentDistance, dockingDistance, moveDistance))
end

--[[
触发攻击（新函数，取代原AttackTarget）
职责：
1. 检查是否可以攻击
2. 调用BeginAttack进入攻击阶段
3. 调用AnimationController.PlayAttackAnimation播放攻击动画
4. 动画结束后由回调自动切换到Idle
]]
function UnitAI.TriggerAttack(unitModel, target, state, aiData)
	-- 检查攻击冷却
	if not CombatSystem.CanAttack(unitModel) then
		return
	end

	-- 面向目标
	OrientTowardsTarget(aiData, target)

	-- 开始攻击（进入Attacking阶段）
	local success = CombatSystem.BeginAttack(unitModel, target)
	if not success then
		return
	end

	-- 定义伤害回调
	local function onDamageCallback(unitModel, target, isRangedUnit)
		if isRangedUnit then
			CombatSystem.OnRangedDamageEvent(unitModel, target)
		else
			CombatSystem.OnDamageEvent(unitModel)
		end
	end

	-- 播放攻击动画
	-- 动画结束后会自动切换到Idle（在AnimationController.PlayAttack的回调中处理）
	AnimationController.PlayAttack(unitModel, aiData, state, target, onDamageCallback)
end

function UnitAI.OnTargetDeath(deadUnit, battleId)
	for unitModel, aiData in pairs(activeAIs) do
		if not aiData.IsActive then
			continue
		end

		local state = CombatSystem.GetUnitState(unitModel)

		if state and state.BattleId == battleId then
			local currentTarget = CombatSystem.GetTarget(unitModel)

			if currentTarget == deadUnit then
				CombatSystem.SetTarget(unitModel, nil)
				CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)

				LogStateChange(state.UnitId, state.State, "SEEKING", "目标死亡")

				-- 目标死亡，停止攻击动画并清理路径
				if aiData.Tracks.Attack then
					SafeStopAnimation(aiData.Tracks.Attack)
					aiData.Tracks.Attack = nil
				end

				-- 清理路径
				PathService.ClearPath(unitModel)  -- ⭐使用PathService
			end
		end
	end
end

function UnitAI.ClearBattleAIs(battleId)
	for unitModel, aiData in pairs(activeAIs) do
		local state = CombatSystem.GetUnitState(unitModel)

		if not state or (state and state.BattleId == battleId) then
			UnitAI.StopAI(unitModel)
		end
	end

	-- 清理指定战斗的路径
	PathService.ClearBattlePaths(battleId, CombatSystem.GetUnitState)  -- ⭐使用PathService

	DebugLog("已清理战斗", battleId, "的所有AI")
end

function UnitAI.GetActiveAICount()
	local count = 0

	for _, aiData in pairs(activeAIs) do
		if aiData.IsActive then
			count = count + 1
		end
	end

	return count
end

--[[
播放死亡动画（供CombatSystem调用）- 兼容旧版接口
]]
function UnitAI.PlayDeathAnimation(unitModel: Model, animationId: string | number): AnimationTrack?
	if not unitModel or not unitModel:IsA("Model") then
		return nil
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	return CreateAndPlayAnimation(humanoid, animationId, false)
end

--[[
开始死亡动画流程 - 无缝过渡版
职责：
1. 缓存当前播放的动画轨道
2. 立刻禁用Animate脚本（防止默认待机抢占）
3. 创建死亡动画轨道并立刻播放（Priority=Action4，Fade=0）
4. 等死亡轨道开始后再停止旧轨道（无缝覆盖）
5. 动画结束时冻结尸体
]]
function UnitAI.BeginDeathAnimation(unitModel: Model, animationId: string | number, unitId: string?)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("BeginDeathAnimation失败: unitModel无效")
		return
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		WarnLog("BeginDeathAnimation失败: 找不到Humanoid或HumanoidRootPart")
		return
	end

	local unitName = unitId or unitModel.Name or "Unknown"

	DebugLog(string.format("[%s] 开始死亡动画流程, 动画ID: %s", unitName, animationId or "nil"))

	-- ============ 步骤1: 缓存当前播放的动画轨道 ============
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = unitModel:FindFirstChildOfClass("Animator")
	end

	local playingTracks = {}
	if animator then
		playingTracks = animator:GetPlayingAnimationTracks()
		DebugLog(string.format("[%s] 缓存 %d 个正在播放的动画", unitName, #playingTracks))
	end

	-- ============ 步骤2: 立刻禁用Animate脚本 ============
	DisableAllAnimateScripts(unitModel, unitName)

	-- ============ 步骤3: 设置AutoRotate=false ============
	pcall(function()
		humanoid.AutoRotate = false
	end)

	-- ============ 步骤4: 创建并立刻播放死亡动画 ============
	if animationId and animationId ~= "" and animationId ~= "0" then
		local animIdStr = tostring(animationId)
		DebugLog(string.format("[%s] 正在加载死亡动画... (ID: %s)", unitName, animIdStr))

		-- 手动创建动画轨道
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. animIdStr

			local success, animTrack = pcall(function()
				return animator:LoadAnimation(animation)
			end)

			if success and animTrack then
				-- 设置高优先级和零淡出，确保立即生效
				animTrack.Priority = Enum.AnimationPriority.Action4
				animTrack.Looped = false

				-- 先停止所有旧轨道
				for _, track in ipairs(playingTracks) do
					if track and track.IsPlaying then
						pcall(function()
							track:Stop(0)
						end)
					end
				end
				DebugLog(string.format("[%s] 已停止 %d 个旧动画轨道", unitName, #playingTracks))

				-- 立刻播放死亡动画
				pcall(function()
					animTrack:Play(0)
				end)

				DebugLog(string.format("[%s] ✅ 死亡动画播放成功 (Priority=Action4, Fade=0)", unitName))

				-- 动画结束时冻结尸体（V2.0.1修复：战役单位使用软冻结）
				animTrack.Stopped:Connect(function()
					if unitModel and unitModel.Parent then
						-- V2.0.1修复：检查是否是战役单位
						local isCampaignUnit = unitModel:GetAttribute("CampaignKeepInstance")
						if not isCampaignUnit then
							-- 非战役单位：完全冻结
							FreezeCorpse(unitModel, humanoid, rootPart, unitName)
						else
							-- 战役单位：软冻结（保持姿态但可恢复）
							SoftFreezeForCampaign(unitModel, humanoid, rootPart, unitName)
						end
					end
				end)

				-- 延迟清理Animation对象
				task.delay(5, function()
					if animation and animation.Parent then
						animation:Destroy()
					end
				end)
			else
				WarnLog(string.format("[%s] ❌ 死亡动画加载失败! 动画ID可能无效: %s", unitName, animIdStr))
				animation:Destroy()
				-- 动画加载失败，直接冻结尸体（V2.0.1修复：战役单位使用软冻结）
				local isCampaignUnit = unitModel:GetAttribute("CampaignKeepInstance")
				if not isCampaignUnit then
					-- 非战役单位：完全冻结
					FreezeCorpse(unitModel, humanoid, rootPart, unitName)
				else
					-- 战役单位：软冻结（保持姿态但可恢复）
					SoftFreezeForCampaign(unitModel, humanoid, rootPart, unitName)
				end
			end
		else
			WarnLog(string.format("[%s] ❌ 找不到Animator", unitName))
			-- V2.0.1修复：战役单位使用软冻结
			local isCampaignUnit = unitModel:GetAttribute("CampaignKeepInstance")
			if not isCampaignUnit then
				-- 非战役单位：完全冻结
				FreezeCorpse(unitModel, humanoid, rootPart, unitName)
			else
				-- 战役单位：软冻结（保持姿态但可恢复）
				SoftFreezeForCampaign(unitModel, humanoid, rootPart, unitName)
			end
		end
	else
		DebugLog(string.format("[%s] 无死亡动画配置，直接冻结尸体", unitName))
		-- 无动画配置时，直接冻结尸体（V2.0.1修复：战役单位使用软冻结）
		local isCampaignUnit = unitModel:GetAttribute("CampaignKeepInstance")
		if not isCampaignUnit then
			-- 非战役单位：完全冻结
			FreezeCorpse(unitModel, humanoid, rootPart, unitName)
		else
			-- 战役单位：软冻结（保持姿态但可恢复）
			SoftFreezeForCampaign(unitModel, humanoid, rootPart, unitName)
		end
	end
end

--[[
===============================================
V2.0 新增: 手动控制动画API (用于战役行军)
===============================================
]]

--[[
手动播放移动动画 (用于战役行军阶段)
@param unitModel Model - 兵种模型
]]
function UnitAI.PlayMoveAnimation(unitModel)
	if not unitModel or not unitModel:IsA("Model") then
		return
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- 获取配置
	local unitId = unitModel:GetAttribute("UnitId") or unitModel.Name
	-- V2.0修复：使用UnitConfig辅助函数获取动画ID，兼容现有字段
	local moveAnimId = UnitConfig.GetMoveAnimationId(unitId)
	if not moveAnimId or moveAnimId == "" or moveAnimId == "0" then
		return
	end

	if not tonumber(moveAnimId) then
		return
	end

	-- 停止所有动画
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = unitModel:FindFirstChildOfClass("Animator")
	end
	if not animator then
		return
	end

	local tracks = animator:GetPlayingAnimationTracks()
	for _, track in ipairs(tracks) do
		pcall(function()
			track:Stop(0.2)
		end)
	end

	-- 创建并播放移动动画
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. moveAnimId

	local success, animTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and animTrack then
		animTrack.Looped = true
		pcall(function()
			animTrack:Play()
		end)
		-- V2.0修复：使用模块级表存储AnimationTrack，而不是Attribute（Attribute不支持Instance类型）
		marchAnimationTracks[unitModel] = animTrack
	end

	animation:Destroy()
end

--[[
停止移动动画并切换到Idle (用于战役行军到达后)
@param unitModel Model - 兵种模型
]]
function UnitAI.StopMoveAnimation(unitModel)
	if not unitModel or not unitModel:IsA("Model") then
		return
	end

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- V2.0修复：先清理存储的行军动画轨道
	if marchAnimationTracks[unitModel] then
		pcall(function()
			marchAnimationTracks[unitModel]:Stop(0.2)
		end)
		marchAnimationTracks[unitModel] = nil
	end

	-- 停止所有动画
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = unitModel:FindFirstChildOfClass("Animator")
	end
	if animator then
		local tracks = animator:GetPlayingAnimationTracks()
		for _, track in ipairs(tracks) do
			pcall(function()
				track:Stop(0.2)
			end)
		end
	end

	-- 获取配置
	local unitId = unitModel:GetAttribute("UnitId") or unitModel.Name
	-- V2.0修复：使用UnitConfig辅助函数获取动画ID，兼容现有字段
	local idleAnimId = UnitConfig.GetIdleAnimationId(unitId)
	if not idleAnimId or idleAnimId == "" or idleAnimId == "0" then
		return
	end

	if not tonumber(idleAnimId) then
		return
	end

	if not animator then
		return
	end

	-- 播放Idle动画
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. idleAnimId

	local success, animTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and animTrack then
		animTrack.Looped = true
		pcall(function()
			animTrack:Play()
		end)
	end

	animation:Destroy()
end

--[[
===============================================
V2.0 新增: AI模式切换API
===============================================
]]

--[[
设置AI模式
@param unitModel Model - 兵种模型
@param mode string - AI模式（"MarchMode"/"CombatMode"）
@return boolean - 是否成功
]]
function UnitAI.SetMode(unitModel, mode)
	local aiData = activeAIs[unitModel]
	if not aiData then
		-- 修改：AI未启动时不再警告，这在战役流程中是正常状态
		-- WarnLog("SetMode失败：AI未启动")
		return false
	end

	if mode ~= AIMode.MARCH and mode ~= AIMode.COMBAT then
		WarnLog("SetMode失败：无效的模式:", mode)
		return false
	end

	aiData.Mode = mode
	DebugLog(string.format("AI模式切换: %s → %s", unitModel.Name, mode))
	return true
end

--[[
准备单位进入战斗
清理PathService状态、重置目标、将AIState切回SEEKING
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function UnitAI.PrepareForCombat(unitModel)
	local aiData = activeAIs[unitModel]
	if not aiData then
		WarnLog("PrepareForCombat失败：AI未启动")
		return false
	end

	local unitId = unitModel and unitModel.Name or "Unknown"
	DebugLog(string.format("准备单位进入战斗: %s", unitId))

	-- 1. 切换到战斗模式
	aiData.Mode = AIMode.COMBAT

	-- 2. 清理PathService状态
	PathService.ClearPath(unitModel)

	-- 3. 重置目标和AI状态
	local state = CombatSystem.GetUnitState(unitModel)
	if state then
		CombatSystem.SetTarget(unitModel, nil)
		CombatSystem.SetAIState(unitModel, BattleConfig.AIState.SEEKING)
	end

	-- 4. 清空LastDesiredDirection
	aiData.LastDesiredDirection = nil

	-- 5. 切换到Idle动画
	if state then
		AnimationController.SwitchToIdle(unitModel, aiData, state)
	end

	DebugLog(string.format("✅单位准备完成: %s", unitId))
	return true
end

return UnitAI
