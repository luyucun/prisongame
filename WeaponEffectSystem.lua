--[[
脚本名称: WeaponEffectSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/WeaponEffectSystem
版本: V1.5.4

职责:
1. 管理远程武器的发射特效播放
2. 支持 Beam、PointLight、ParticleEmitter 的时序控制
3. 处理快速攻击时的特效强制重置
4. 统一管理所有特效实例的生命周期

武器模型结构规范:
Weapon (Model/Part)
└── Effect (Part)
    ├── Beam (Beam)
    ├── PointLight (PointLight)
    ├── ParticleEmitter01 (ParticleEmitter)
    ├── ParticleEmitter02 (ParticleEmitter)
    └── ...
]]

local WeaponEffectSystem = {}

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))

-- ==================== 私有变量 ====================

-- 存储所有活跃的特效实例，key为unitModel的tostring()
local activeEffects = {}

-- 是否已初始化
local isInitialized = false

-- ==================== 数据结构 ====================

--[[
EffectInstance = {
    UnitModel = Model,           -- 兵种模型
    WeaponPart = Part/Model,     -- 武器Part
    EffectPart = Part,           -- Effect Part

    -- 特效组件引用
    Beam = Beam,
    PointLight = PointLight,
    ParticleEmitters = {ParticleEmitter, ...},

    -- 时序控制
    BeamTimer = nil,             -- Beam定时器（0.1秒）
    LightTimer = nil,            -- PointLight定时器（0.1秒）
    ParticleTimer = nil,         -- Particle定时器（0.5秒）
    IsPlaying = boolean,         -- 是否正在播放
}
]]

-- ==================== 调试日志 ====================

local function DebugLog(...)
	if BattleConfig.DEBUG_WEAPON_EFFECTS then
		print(GameConfig.LOG_PREFIX, "[WeaponEffectSystem]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[WeaponEffectSystem]", ...)
end

-- ==================== 私有函数 ====================

--[[
查找武器的Effect Part
@param unitModel Model - 兵种模型
@param weaponName string - 武器名称
@return Part|nil - Effect Part，未找到返回nil
]]
local function FindWeaponEffectPart(unitModel, weaponName)
	if not unitModel or not weaponName or weaponName == "" then
		return nil
	end

	-- 1. 查找武器Part
	local weaponPart = unitModel:FindFirstChild(weaponName)
	if not weaponPart then
		DebugLog(string.format("[%s] 武器未找到: %s", unitModel.Name, weaponName))
		return nil
	end

	-- 2. 查找Effect Part
	local effectPart = weaponPart:FindFirstChild("Effect")
	if not effectPart or not effectPart:IsA("BasePart") then
		DebugLog(string.format("[%s] Effect Part未找到: %s.Effect", unitModel.Name, weaponName))
		return nil
	end

	return effectPart
end

--[[
收集特效组件
@param effectPart Part - Effect Part
@return table - 特效组件表 {Beam, PointLight, ParticleEmitters}
]]
local function CollectEffectComponents(effectPart)
	local components = {
		Beam = nil,
		PointLight = nil,
		ParticleEmitters = {}
	}

	if not effectPart then
		return components
	end

	-- 查找 Beam
	local beam = effectPart:FindFirstChild("Beam")
	if beam and beam:IsA("Beam") then
		components.Beam = beam
	end

	-- 查找 PointLight
	local pointLight = effectPart:FindFirstChild("PointLight")
	if pointLight and pointLight:IsA("PointLight") then
		components.PointLight = pointLight
	end

	-- 遍历查找所有 ParticleEmitter
	-- 命名可能是 ParticleEmitter、ParticleEmitter01、ParticleEmitter02 等
	for _, child in ipairs(effectPart:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			table.insert(components.ParticleEmitters, child)
		end
	end

	DebugLog(string.format("收集特效组件: Beam=%s, PointLight=%s, Particles=%d",
		tostring(components.Beam ~= nil),
		tostring(components.PointLight ~= nil),
		#components.ParticleEmitters))

	return components
end

--[[
播放 Beam 特效
@param beam Beam - Beam组件
@param duration number - 持续时间（秒）
@param effectKey any - 特效实例key（用于验证）
@return thread|nil - 定时器thread
]]
local function PlayBeam(beam, duration, effectKey)
	if not beam then
		return nil
	end

	local success, err = pcall(function()
		beam.Enabled = true
	end)

	if not success then
		WarnLog("播放Beam失败:", err)
		return nil
	end

	DebugLog(string.format("Beam开启，将在%.1f秒后关闭", duration))

	local timer = task.delay(duration, function()
		pcall(function()
			-- ⭐ 关键验证：确保特效实例还存在且是当前正在播放的
			if beam and beam.Parent and activeEffects[effectKey] and activeEffects[effectKey].Beam == beam then
				beam.Enabled = false
				DebugLog("Beam已关闭")
			else
				DebugLog("Beam关闭跳过（实例已更新或不存在）")
			end
		end)
	end)

	return timer
end

--[[
播放 PointLight 特效
@param light PointLight - PointLight组件
@param duration number - 持续时间（秒）
@param effectKey any - 特效实例key（用于验证）
@return thread|nil - 定时器thread
]]
local function PlayPointLight(light, duration, effectKey)
	if not light then
		return nil
	end

	local success, err = pcall(function()
		light.Enabled = true
	end)

	if not success then
		WarnLog("播放PointLight失败:", err)
		return nil
	end

	DebugLog(string.format("PointLight开启，将在%.1f秒后关闭", duration))

	local timer = task.delay(duration, function()
		pcall(function()
			-- ⭐ 关键验证：确保特效实例还存在且是当前正在播放的
			if light and light.Parent and activeEffects[effectKey] and activeEffects[effectKey].PointLight == light then
				light.Enabled = false
				DebugLog("PointLight已关闭")
			else
				DebugLog("PointLight关闭跳过（实例已更新或不存在）")
			end
		end)
	end)

	return timer
end

--[[
播放 ParticleEmitter 特效
@param emitters table - ParticleEmitter数组
@param duration number - 持续时间（秒）
@param effectKey any - 特效实例key（用于验证）
@return thread|nil - 定时器thread
]]
local function PlayParticleEmitters(emitters, duration, effectKey)
	if not emitters or #emitters == 0 then
		return nil
	end

	-- 开启所有粒子
	local enabledCount = 0
	for _, emitter in ipairs(emitters) do
		local success, err = pcall(function()
			if emitter and emitter.Parent then
				emitter.Enabled = true
				enabledCount = enabledCount + 1
			end
		end)

		if not success then
			WarnLog("开启ParticleEmitter失败:", err)
		end
	end

	DebugLog(string.format("ParticleEmitters开启 (%d个)，将在%.1f秒后关闭", enabledCount, duration))

	-- 定时关闭所有粒子
	local timer = task.delay(duration, function()
		-- ⭐ 关键验证：确保特效实例还存在
		if not activeEffects[effectKey] then
			DebugLog("ParticleEmitters关闭跳过（实例已不存在）")
			return
		end

		for _, emitter in ipairs(emitters) do
			pcall(function()
				if emitter and emitter.Parent then
					emitter.Enabled = false
				end
			end)
		end
		DebugLog("ParticleEmitters已关闭")
	end)

	return timer
end

--[[
强制停止粒子特效（用于快速攻击时重置）
@param emitters table - ParticleEmitter数组
]]
local function ForceStopParticles(emitters)
	if not emitters or #emitters == 0 then
		return
	end

	for _, emitter in ipairs(emitters) do
		pcall(function()
			if emitter and emitter.Parent then
				emitter.Enabled = false
			end
		end)
	end

	DebugLog("强制关闭所有粒子特效")
end

--[[
清理特效实例的所有定时器
@param effectInstance table - 特效实例
]]
local function ClearEffectTimers(effectInstance)
	if not effectInstance then
		return
	end

	-- 取消所有定时器
	if effectInstance.BeamTimer then
		pcall(function()
			task.cancel(effectInstance.BeamTimer)
		end)
		effectInstance.BeamTimer = nil
	end

	if effectInstance.LightTimer then
		pcall(function()
			task.cancel(effectInstance.LightTimer)
		end)
		effectInstance.LightTimer = nil
	end

	if effectInstance.ParticleTimer then
		pcall(function()
			task.cancel(effectInstance.ParticleTimer)
		end)
		effectInstance.ParticleTimer = nil
	end
end

-- ==================== 公共接口 ====================

--[[
初始化武器特效系统
@return boolean - 是否初始化成功
]]
function WeaponEffectSystem.Initialize()
	if isInitialized then
		WarnLog("武器特效系统已经初始化过了")
		return true
	end

	DebugLog("正在初始化武器特效系统...")

	isInitialized = true

	DebugLog("武器特效系统初始化完成")
	return true
end

--[[
关闭武器特效系统
]]
function WeaponEffectSystem.Shutdown()
	DebugLog("正在关闭武器特效系统...")

	-- 清理所有活跃的特效
	WeaponEffectSystem.CancelAllEffects()

	activeEffects = {}
	isInitialized = false

	DebugLog("武器特效系统已关闭")
end

--[[
播放武器特效
@param unitModel Model - 兵种模型
@param weaponName string - 武器名称
@return boolean - 是否成功播放
]]
function WeaponEffectSystem.PlayWeaponEffect(unitModel, weaponName)
	if not unitModel or not weaponName or weaponName == "" then
		return false
	end

	-- 查找Effect Part
	local effectPart = FindWeaponEffectPart(unitModel, weaponName)
	if not effectPart then
		-- 静默跳过，不影响战斗
		return false
	end

	-- 收集特效组件
	local components = CollectEffectComponents(effectPart)

	-- 如果没有任何特效组件，直接返回
	if not components.Beam and not components.PointLight and #components.ParticleEmitters == 0 then
		DebugLog(string.format("[%s] 没有找到任何特效组件", unitModel.Name))
		return false
	end

	-- 生成特效实例的key（使用模型本身作为key，更可靠）
	local effectKey = unitModel

	-- ⭐⭐⭐ 关键修复：检查是否已经有特效在播放 ⭐⭐⭐
	if activeEffects[effectKey] then
		local existingEffect = activeEffects[effectKey]

		DebugLog(string.format("[%s] 检测到旧特效正在播放，强制关闭所有旧特效", unitModel.Name))

		-- 1. 取消所有定时器
		ClearEffectTimers(existingEffect)

		-- 2. ⭐ 强制关闭Beam（防止一直亮着）
		if existingEffect.Beam then
			pcall(function()
				existingEffect.Beam.Enabled = false
			end)
			DebugLog(string.format("[%s] 强制关闭旧Beam", unitModel.Name))
		end

		-- 3. ⭐ 强制关闭PointLight（防止一直亮着）
		if existingEffect.PointLight then
			pcall(function()
				existingEffect.PointLight.Enabled = false
			end)
			DebugLog(string.format("[%s] 强制关闭旧PointLight", unitModel.Name))
		end

		-- 4. 强制关闭所有粒子
		ForceStopParticles(existingEffect.ParticleEmitters)
	end

	-- 创建新的特效实例
	local newEffect = {
		UnitModel = unitModel,
		EffectPart = effectPart,
		Beam = components.Beam,
		PointLight = components.PointLight,
		ParticleEmitters = components.ParticleEmitters,
		BeamTimer = nil,
		LightTimer = nil,
		ParticleTimer = nil,
		IsPlaying = true,
	}

	-- 保存到活跃特效表
	activeEffects[effectKey] = newEffect

	-- 播放特效序列
	DebugLog(string.format("[%s] 开始播放武器特效", unitModel.Name))

	-- 1. 播放 Beam (0.1秒) ⭐ 传入effectKey进行验证
	if components.Beam then
		newEffect.BeamTimer = PlayBeam(components.Beam, BattleConfig.WEAPON_EFFECT_BEAM_DURATION, effectKey)
	end

	-- 2. 播放 PointLight (0.1秒) ⭐ 传入effectKey进行验证
	if components.PointLight then
		newEffect.LightTimer = PlayPointLight(components.PointLight, BattleConfig.WEAPON_EFFECT_LIGHT_DURATION, effectKey)
	end

	-- 3. 播放 ParticleEmitters (0.5秒) ⭐ 传入effectKey进行验证
	if #components.ParticleEmitters > 0 then
		newEffect.ParticleTimer = PlayParticleEmitters(components.ParticleEmitters, BattleConfig.WEAPON_EFFECT_PARTICLE_DURATION, effectKey)
	end

	-- 设置清理任务：在最长的特效结束后清理实例
	-- 粒子特效最长(0.5秒)，所以在0.5秒后清理
	task.delay(BattleConfig.WEAPON_EFFECT_PARTICLE_DURATION + 0.1, function()
		-- 检查是否还是同一个特效实例
		if activeEffects[effectKey] == newEffect then
			activeEffects[effectKey] = nil
			DebugLog(string.format("[%s] 特效播放完成，清理实例", unitModel.Name))
		end
	end)

	return true
end

--[[
强制停止指定单位的武器特效
@param unitModel Model - 兵种模型
]]
function WeaponEffectSystem.StopWeaponEffect(unitModel)
	if not unitModel then
		return
	end

	local effectKey = tostring(unitModel)
	local effectInstance = activeEffects[effectKey]

	if not effectInstance then
		return
	end

	DebugLog(string.format("[%s] 强制停止武器特效", unitModel.Name))

	-- 清理定时器
	ClearEffectTimers(effectInstance)

	-- 强制关闭所有特效
	if effectInstance.Beam then
		pcall(function()
			effectInstance.Beam.Enabled = false
		end)
	end

	if effectInstance.PointLight then
		pcall(function()
			effectInstance.PointLight.Enabled = false
		end)
	end

	ForceStopParticles(effectInstance.ParticleEmitters)

	-- 从活跃表中移除
	activeEffects[effectKey] = nil
end

--[[
清理所有活跃的特效
用于系统关闭或战斗结束时
]]
function WeaponEffectSystem.CancelAllEffects()
	DebugLog(string.format("清理所有活跃特效，共%d个", #activeEffects))

	for effectKey, effectInstance in pairs(activeEffects) do
		ClearEffectTimers(effectInstance)

		-- 强制关闭所有特效
		if effectInstance.Beam then
			pcall(function()
				effectInstance.Beam.Enabled = false
			end)
		end

		if effectInstance.PointLight then
			pcall(function()
				effectInstance.PointLight.Enabled = false
			end)
		end

		ForceStopParticles(effectInstance.ParticleEmitters)
	end

	activeEffects = {}
end

--[[
获取当前活跃的特效数量（调试用）
@return number - 活跃特效数量
]]
function WeaponEffectSystem.GetActiveEffectCount()
	local count = 0
	for _ in pairs(activeEffects) do
		count = count + 1
	end
	return count
end

return WeaponEffectSystem
