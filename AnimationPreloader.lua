--[[
脚本名称: AnimationPreloader
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/AnimationPreloader

职责:
1. 在客户端启动时预加载所有战斗动画资源
2. 避免首场战斗时动画从CDN下载导致的卡顿
3. 确保死亡/攻击/移动动画无缝衔接
]]

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer

-- 调试日志
local DEBUG_MODE = true
local LOG_PREFIX = "[AnimationPreloader]"

local function DebugLog(...)
	if DEBUG_MODE then
		print(LOG_PREFIX, ...)
	end
end

local function WarnLog(...)
	warn(LOG_PREFIX, ...)
end

-- 等待配置加载
local Config = ReplicatedStorage:WaitForChild("Config", 10)
if not Config then
	WarnLog("严重错误: 找不到Config文件夹!")
	return
end

local UnitConfig = require(Config:WaitForChild("UnitConfig", 10))
if not UnitConfig then
	WarnLog("严重错误: 无法加载UnitConfig!")
	return
end

DebugLog("✅ 动画预加载器启动")

--[[
预加载所有兵种的战斗动画
]]
local function PreloadAllUnitAnimations()
	local startTime = tick()
	local animationsToPreload = {}
	local unitCount = 0

	-- 遍历所有兵种配置
	for unitId, unitData in pairs(UnitConfig.Units) do
		unitCount = unitCount + 1

		-- 收集该兵种的所有动画ID
		local animIds = {
			{id = unitData.IdleAnimationId, name = "Idle"},
			{id = unitData.MoveAnimationId, name = "Move"},
			{id = unitData.AttackAnimationId, name = "Attack"},
			{id = unitData.DeathAnimationId, name = "Death"},
		}

		for _, animData in ipairs(animIds) do
			local animId = animData.id
			if animId and animId ~= "" and animId ~= "0" then
				-- 创建Animation实例
				local animation = Instance.new("Animation")
				animation.AnimationId = "rbxassetid://" .. animId
				animation.Name = string.format("%s_%s", unitId, animData.name)

				table.insert(animationsToPreload, animation)
				DebugLog(string.format("收集动画: %s - %s (ID: %s)", unitId, animData.name, animId))
			end
		end
	end

	DebugLog(string.format("开始预加载 %d 个动画资源（来自 %d 个兵种）...", #animationsToPreload, unitCount))

	-- 使用ContentProvider批量预加载
	if #animationsToPreload > 0 then
		local success, err = pcall(function()
			ContentProvider:PreloadAsync(animationsToPreload)
		end)

		if success then
			local elapsed = tick() - startTime
			DebugLog(string.format("✅ 预加载完成! 耗时: %.2f秒, 动画数量: %d", elapsed, #animationsToPreload))
		else
			WarnLog(string.format("⚠️ 预加载失败: %s", tostring(err)))
		end

		-- 清理Animation实例
		for _, anim in ipairs(animationsToPreload) do
			anim:Destroy()
		end
	else
		WarnLog("没有找到需要预加载的动画")
	end
end

-- 等待玩家角色加载完成后再预加载（确保游戏环境就绪）
local function WaitForCharacterAndPreload()
	-- 等待角色加载
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	DebugLog("玩家角色已加载，开始预加载动画资源...")

	-- 延迟0.5秒，确保其他系统初始化完成
	task.wait(0.5)

	-- 执行预加载
	PreloadAllUnitAnimations()
end

-- 启动预加载流程
task.spawn(WaitForCharacterAndPreload)

DebugLog("动画预加载器初始化完成")
