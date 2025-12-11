--[[
脚本名称: SoundController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayerScripts/SoundController
版本: V3.8
]]

--[[
客户端音效控制器
职责:
1. 实际播放BGM和SFX音效
2. 处理BGM的淡入淡出切换
3. 管理音效实例的生命周期
4. 响应服务端的音效播放指令
]]

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- 本地玩家
local LocalPlayer = Players.LocalPlayer

-- 等待配置加载
local SoundConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SoundConfig"))

-- 调试配置
local DEBUG_MODE = false
local LOG_PREFIX = "[SoundController]"

-- ==================== 状态变量 ====================

local currentBGM = nil              -- 当前正在播放的BGM Sound实例
local currentBGMKey = nil           -- 当前BGM的键名
local sfxInstances = {}             -- SFX音效实例表 {[sfxKey] = Sound}
local isInitialized = false         -- 是否已初始化

-- 事件引用
local SoundEvents = nil

-- ==================== 私有函数 ====================

local function DebugLog(...)
	if DEBUG_MODE then
		print(LOG_PREFIX, ...)
	end
end

--[[
获取或创建BGM Sound实例
@param bgmKey string - BGM键名
@return Sound|nil - Sound实例
]]
local function GetOrCreateBGMSound(bgmKey)
	local config = SoundConfig.GetBGMConfig(bgmKey)
	if not config then
		warn(LOG_PREFIX, "BGM配置不存在:", bgmKey)
		return nil
	end

	-- 查找SoundService中的BGM文件夹
	local bgmFolder = SoundService:FindFirstChild("BGM")
	if not bgmFolder then
		bgmFolder = Instance.new("Folder")
		bgmFolder.Name = "BGM"
		bgmFolder.Parent = SoundService
	end

	-- 查找对应的子文件夹
	local subFolder = bgmFolder:FindFirstChild(bgmKey)
	if not subFolder then
		subFolder = Instance.new("Folder")
		subFolder.Name = bgmKey
		subFolder.Parent = bgmFolder
	end

	-- 查找或创建Sound实例
	local sound = subFolder:FindFirstChild(config.Name)
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = config.Name
		sound.SoundId = config.SoundId
		sound.Volume = config.Volume or SoundConfig.Settings.BGMVolume
		sound.Looped = config.Looped ~= false  -- 默认循环
		sound.Parent = subFolder
	end

	return sound
end

--[[
获取或创建SFX Sound实例
@param sfxKey string - SFX键名
@return Sound|nil - Sound实例
]]
local function GetOrCreateSFXSound(sfxKey)
	local config = SoundConfig.GetSFXConfig(sfxKey)
	if not config then
		warn(LOG_PREFIX, "SFX配置不存在:", sfxKey)
		return nil
	end

	-- 查找SoundService中的Audio/Common文件夹
	local audioFolder = SoundService:FindFirstChild("Audio")
	if not audioFolder then
		audioFolder = Instance.new("Folder")
		audioFolder.Name = "Audio"
		audioFolder.Parent = SoundService
	end

	local commonFolder = audioFolder:FindFirstChild("Common")
	if not commonFolder then
		commonFolder = Instance.new("Folder")
		commonFolder.Name = "Common"
		commonFolder.Parent = audioFolder
	end

	-- 查找或创建Sound实例
	local sound = commonFolder:FindFirstChild(config.Name)
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = config.Name
		sound.SoundId = config.SoundId
		sound.Volume = config.Volume or SoundConfig.Settings.SFXVolume
		sound.Looped = config.Looped or false
		sound.Parent = commonFolder
	end

	return sound
end

--[[
淡出音效
@param sound Sound - Sound实例
@param duration number - 淡出时长
@param callback function - 完成后回调
]]
local function FadeOut(sound, duration, callback)
	if not sound then
		if callback then callback() end
		return
	end

	local tween = TweenService:Create(
		sound,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{Volume = 0}
	)

	tween.Completed:Connect(function()
		sound:Stop()
		if callback then callback() end
	end)

	tween:Play()
end

--[[
淡入音效
@param sound Sound - Sound实例
@param targetVolume number - 目标音量
@param duration number - 淡入时长
]]
local function FadeIn(sound, targetVolume, duration)
	if not sound then return end

	sound.Volume = 0
	sound:Play()

	local tween = TweenService:Create(
		sound,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{Volume = targetVolume}
	)

	tween:Play()
end

--[[
播放BGM（带淡入淡出）
@param bgmKey string - BGM键名（"Home" 或 "Battle"）
]]
local function PlayBGM(bgmKey)
	-- 如果已经在播放相同的BGM，不重复操作
	if currentBGMKey == bgmKey and currentBGM and currentBGM.IsPlaying then
		DebugLog("BGM已在播放中:", bgmKey)
		return
	end

	local newSound = GetOrCreateBGMSound(bgmKey)
	if not newSound then
		return
	end

	local config = SoundConfig.GetBGMConfig(bgmKey)
	local targetVolume = config.Volume or SoundConfig.Settings.BGMVolume
	local fadeDuration = SoundConfig.Settings.BGMFadeDuration

	-- 如果有正在播放的BGM，先淡出
	if currentBGM and currentBGM.IsPlaying then
		DebugLog("淡出当前BGM:", currentBGMKey)
		FadeOut(currentBGM, fadeDuration, function()
			-- 淡出完成后，淡入新BGM
			DebugLog("淡入新BGM:", bgmKey)
			FadeIn(newSound, targetVolume, fadeDuration)
		end)
	else
		-- 直接淡入新BGM
		DebugLog("直接播放BGM:", bgmKey)
		FadeIn(newSound, targetVolume, fadeDuration)
	end

	currentBGM = newSound
	currentBGMKey = bgmKey

	DebugLog("BGM切换:", bgmKey)
end

--[[
停止BGM
]]
local function StopBGM()
	if currentBGM and currentBGM.IsPlaying then
		local fadeDuration = SoundConfig.Settings.BGMFadeDuration
		FadeOut(currentBGM, fadeDuration, nil)
		DebugLog("停止BGM:", currentBGMKey)
	end

	currentBGM = nil
	currentBGMKey = nil
end

--[[
播放一次性音效
@param sfxKey string - 音效键名
]]
local function PlaySFX(sfxKey)
	local sound = GetOrCreateSFXSound(sfxKey)
	if not sound then
		return
	end

	local config = SoundConfig.GetSFXConfig(sfxKey)
	sound.Volume = config.Volume or SoundConfig.Settings.SFXVolume

	-- 如果音效正在播放，先停止再播放（确保从头开始）
	if sound.IsPlaying then
		sound:Stop()
	end

	sound:Play()
	sfxInstances[sfxKey] = sound

	DebugLog("播放SFX:", sfxKey)
end

--[[
停止一次性音效
@param sfxKey string - 音效键名
]]
local function StopSFX(sfxKey)
	local sound = sfxInstances[sfxKey]
	if sound and sound.IsPlaying then
		sound:Stop()
		DebugLog("停止SFX:", sfxKey)
	end
end

--[[
连接服务端事件
@return boolean - 是否成功
]]
local function ConnectServerEvents()
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if not Events then
		Events = ReplicatedStorage:WaitForChild("Events", 10)
	end
	if not Events then
		warn(LOG_PREFIX, "找不到Events文件夹")
		return false
	end

	SoundEvents = Events:FindFirstChild("SoundEvents")
	if not SoundEvents then
		SoundEvents = Events:WaitForChild("SoundEvents", 10)
	end
	if not SoundEvents then
		warn(LOG_PREFIX, "找不到SoundEvents文件夹")
		return false
	end

	-- 连接PlayBGM事件
	local playBGMEvent = SoundEvents:FindFirstChild("PlayBGM")
	if playBGMEvent then
		playBGMEvent.OnClientEvent:Connect(function(bgmKey)
			PlayBGM(bgmKey)
		end)
		DebugLog("已连接PlayBGM事件")
	end

	-- 连接StopBGM事件
	local stopBGMEvent = SoundEvents:FindFirstChild("StopBGM")
	if stopBGMEvent then
		stopBGMEvent.OnClientEvent:Connect(function()
			StopBGM()
		end)
		DebugLog("已连接StopBGM事件")
	end

	-- 连接PlaySFX事件
	local playSFXEvent = SoundEvents:FindFirstChild("PlaySFX")
	if playSFXEvent then
		playSFXEvent.OnClientEvent:Connect(function(sfxKey)
			PlaySFX(sfxKey)
		end)
		DebugLog("已连接PlaySFX事件")
	end

	-- 连接StopSFX事件
	local stopSFXEvent = SoundEvents:FindFirstChild("StopSFX")
	if stopSFXEvent then
		stopSFXEvent.OnClientEvent:Connect(function(sfxKey)
			StopSFX(sfxKey)
		end)
		DebugLog("已连接StopSFX事件")
	end

	return true
end

--[[
预加载所有音效资源
]]
local function PreloadSounds()
	local ContentProvider = game:GetService("ContentProvider")
	local assetsToPreload = {}

	-- 收集BGM资源
	for _, config in pairs(SoundConfig.BGM) do
		if config.SoundId then
			table.insert(assetsToPreload, config.SoundId)
		end
	end

	-- 收集SFX资源
	for _, config in pairs(SoundConfig.SFX) do
		if config.SoundId then
			table.insert(assetsToPreload, config.SoundId)
		end
	end

	-- 异步预加载
	if #assetsToPreload > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(assetsToPreload)
			end)
			DebugLog("音效资源预加载完成，共", #assetsToPreload, "个")
		end)
	end
end

-- ==================== 初始化 ====================

local function Initialize()
	-- 预加载音效
	PreloadSounds()

	-- 连接服务端事件
	if not ConnectServerEvents() then
		warn(LOG_PREFIX, "服务端事件连接失败，将在稍后重试")
		-- 延迟重试
		task.delay(3, function()
			ConnectServerEvents()
		end)
	end

	isInitialized = true
end

-- ==================== 公共接口（供其他客户端脚本调用） ====================

local SoundController = {}

--[[
手动播放BGM（客户端直接调用）
@param bgmKey string - BGM键名
]]
function SoundController.PlayBGM(bgmKey)
	PlayBGM(bgmKey)
end

--[[
手动停止BGM
]]
function SoundController.StopBGM()
	StopBGM()
end

--[[
手动播放SFX（客户端直接调用）
@param sfxKey string - SFX键名
]]
function SoundController.PlaySFX(sfxKey)
	PlaySFX(sfxKey)
end

--[[
手动停止SFX
@param sfxKey string - SFX键名
]]
function SoundController.StopSFX(sfxKey)
	StopSFX(sfxKey)
end

--[[
检查是否已初始化
@return boolean
]]
function SoundController.IsInitialized()
	return isInitialized
end

--[[
获取当前BGM键名
@return string|nil
]]
function SoundController.GetCurrentBGMKey()
	return currentBGMKey
end

-- 导出到全局（方便其他脚本访问）
_G.SoundController = SoundController

-- ==================== 启动 ====================

Initialize()
