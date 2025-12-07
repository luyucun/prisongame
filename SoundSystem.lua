--[[
脚本名称: SoundSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/SoundSystem
版本: V3.8
]]

--[[
服务端音效系统模块
职责:
1. 创建音效相关的RemoteEvent
2. 处理服务端触发的音效播放请求
3. 通知客户端播放指定音效
4. 管理音效事件的分发
]]

local SoundSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- 引用模块（延迟加载避免循环依赖）
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SoundConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SoundConfig"))

-- 远程事件引用
local SoundEvents = nil

-- ==================== 私有函数 ====================

--[[
初始化音效事件
@return boolean - 是否成功
]]
local function InitializeEvents()
	if SoundEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		warn(GameConfig.LOG_PREFIX, "[SoundSystem] Events文件夹未找到")
		return false
	end

	SoundEvents = eventsFolder:FindFirstChild("SoundEvents")
	if not SoundEvents then
		-- 创建事件文件夹
		SoundEvents = Instance.new("Folder")
		SoundEvents.Name = "SoundEvents"
		SoundEvents.Parent = eventsFolder

		-- 创建BGM控制事件（服务端→客户端）
		local playBGMEvent = Instance.new("RemoteEvent")
		playBGMEvent.Name = "PlayBGM"
		playBGMEvent.Parent = SoundEvents

		local stopBGMEvent = Instance.new("RemoteEvent")
		stopBGMEvent.Name = "StopBGM"
		stopBGMEvent.Parent = SoundEvents

		-- 创建SFX播放事件（服务端→客户端）
		local playSFXEvent = Instance.new("RemoteEvent")
		playSFXEvent.Name = "PlaySFX"
		playSFXEvent.Parent = SoundEvents

		local stopSFXEvent = Instance.new("RemoteEvent")
		stopSFXEvent.Name = "StopSFX"
		stopSFXEvent.Parent = SoundEvents

		print(GameConfig.LOG_PREFIX, "[SoundSystem] 已创建SoundEvents事件")
	end

	return true
end

-- ==================== 公共接口 ====================

--[[
初始化音效系统
@return boolean - 是否初始化成功
]]
function SoundSystem.Initialize()
	print(GameConfig.LOG_PREFIX, "[SoundSystem] 开始初始化音效系统...")

	-- 初始化事件
	if not InitializeEvents() then
		warn(GameConfig.LOG_PREFIX, "[SoundSystem] 事件初始化失败")
		return false
	end

	print(GameConfig.LOG_PREFIX, "[SoundSystem] 音效系统初始化完成")
	return true
end

--[[
通知玩家播放BGM
@param player Player - 玩家对象
@param bgmKey string - BGM键名（"Home" 或 "Battle"）
]]
function SoundSystem.PlayBGM(player, bgmKey)
	if not InitializeEvents() then
		return
	end

	local playBGMEvent = SoundEvents:FindFirstChild("PlayBGM")
	if playBGMEvent then
		playBGMEvent:FireClient(player, bgmKey)
	end
end

--[[
通知所有玩家播放BGM
@param bgmKey string - BGM键名
]]
function SoundSystem.PlayBGMToAll(bgmKey)
	if not InitializeEvents() then
		return
	end

	local playBGMEvent = SoundEvents:FindFirstChild("PlayBGM")
	if playBGMEvent then
		playBGMEvent:FireAllClients(bgmKey)
	end
end

--[[
通知玩家停止BGM
@param player Player - 玩家对象
]]
function SoundSystem.StopBGM(player)
	if not InitializeEvents() then
		return
	end

	local stopBGMEvent = SoundEvents:FindFirstChild("StopBGM")
	if stopBGMEvent then
		stopBGMEvent:FireClient(player)
	end
end

--[[
通知玩家播放一次性音效
@param player Player - 玩家对象
@param sfxKey string - 音效键名（如"CoinsTrigger", "Victory", "Merge", "Error"）
]]
function SoundSystem.PlaySFX(player, sfxKey)
	if not InitializeEvents() then
		return
	end

	local playSFXEvent = SoundEvents:FindFirstChild("PlaySFX")
	if playSFXEvent then
		playSFXEvent:FireClient(player, sfxKey)
	end
end

--[[
通知玩家停止一次性音效
@param player Player - 玩家对象
@param sfxKey string - 音效键名
]]
function SoundSystem.StopSFX(player, sfxKey)
	if not InitializeEvents() then
		return
	end

	local stopSFXEvent = SoundEvents:FindFirstChild("StopSFX")
	if stopSFXEvent then
		stopSFXEvent:FireClient(player, sfxKey)
	end
end

-- ==================== 便捷接口（根据游戏事件触发音效） ====================

--[[
玩家进入战斗时调用 - 切换到战斗BGM
@param player Player - 玩家对象
]]
function SoundSystem.OnBattleStart(player)
	SoundSystem.PlayBGM(player, "Battle")
	print(GameConfig.LOG_PREFIX, "[SoundSystem] 玩家 " .. player.Name .. " 进入战斗，切换战斗BGM")
end

--[[
玩家结束战斗时调用 - 切换回通用BGM
@param player Player - 玩家对象
]]
function SoundSystem.OnBattleEnd(player)
	SoundSystem.PlayBGM(player, "Home")
	print(GameConfig.LOG_PREFIX, "[SoundSystem] 玩家 " .. player.Name .. " 结束战斗，切换通用BGM")
end

--[[
玩家领取离线金币时调用
@param player Player - 玩家对象
]]
function SoundSystem.OnCollectIdleCoins(player)
	SoundSystem.PlaySFX(player, "CoinsTrigger")
end

--[[
显示胜利结算界面时调用
@param player Player - 玩家对象
]]
function SoundSystem.OnVictoryShow(player)
	SoundSystem.PlaySFX(player, "Victory")
end

--[[
玩家点击确认按钮时调用 - 停止胜利音效
@param player Player - 玩家对象
]]
function SoundSystem.OnVictoryConfirm(player)
	SoundSystem.StopSFX(player, "Victory")
end

--[[
兵种合成时调用
@param player Player - 玩家对象
]]
function SoundSystem.OnMerge(player)
	SoundSystem.PlaySFX(player, "Merge")
end

--[[
购买失败（金币不足）时调用
@param player Player - 玩家对象
]]
function SoundSystem.OnPurchaseError(player)
	SoundSystem.PlaySFX(player, "Error")
end

--[[
玩家加入游戏时调用 - 开始播放通用BGM
@param player Player - 玩家对象
]]
function SoundSystem.OnPlayerJoin(player)
	-- 延迟一小段时间确保客户端已准备好
	task.delay(1, function()
		if player and player.Parent then
			SoundSystem.PlayBGM(player, "Home")
			print(GameConfig.LOG_PREFIX, "[SoundSystem] 玩家 " .. player.Name .. " 加入游戏，开始播放通用BGM")
		end
	end)
end

return SoundSystem
