--[[
脚本名称: LoadingSystem
脚本类型: ModuleScript (服务端)
脚本位置: ServerScriptService/Systems/LoadingSystem
版本: V3.2.4

职责:
1. 管理玩家加载流程
2. 协调各系统初始化顺序
3. 通知客户端加载进度
4. 确保所有数据和资源准备就绪后才允许游戏

V3.2.4更新:
- 【修复】处理竞态条件：缓存提前到达的ClientPreloadComplete消息
- 【修复】StartPlayerLoading时检查是否有缓存的预加载完成消息
- 【修复】CleanupPlayer时同时清理缓存
]]

local LoadingSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- 配置
local DEBUG_MODE = false
local LOG_PREFIX = "[LoadingSystem]"

-- 加载阶段定义
LoadingSystem.LoadingStage = {
	INIT = "INIT",                       -- 初始化
	DATA_LOADING = "DATA_LOADING",       -- 数据加载
	HOME_SETUP = "HOME_SETUP",           -- 基地设置
	SCENE_SETUP = "SCENE_SETUP",         -- 场景设置
	SYNC_DATA = "SYNC_DATA",             -- 数据同步
	COMPLETE = "COMPLETE"                -- 完成
}

-- 加载阶段权重（用于计算进度）
local STAGE_WEIGHTS = {
	[LoadingSystem.LoadingStage.INIT] = 0,
	[LoadingSystem.LoadingStage.DATA_LOADING] = 20,
	[LoadingSystem.LoadingStage.HOME_SETUP] = 40,
	[LoadingSystem.LoadingStage.SCENE_SETUP] = 60,
	[LoadingSystem.LoadingStage.SYNC_DATA] = 80,
	[LoadingSystem.LoadingStage.COMPLETE] = 100
}

-- 玩家加载状态 [UserId] = {Stage, Progress, StartTime, ...}
local playerLoadingStates = {}

-- V3.2.4新增：缓存提前到达的客户端预加载完成消息
-- 用于处理客户端比服务端StartPlayerLoading更快完成预加载的情况
local pendingClientPreloadComplete = {}  -- [UserId] = true

-- RemoteEvent引用
local LoadingEvents = nil

-- ==================== 私有函数 ====================

local function DebugLog(...)
	if DEBUG_MODE then
		print(LOG_PREFIX, ...)
	end
end

--[[
获取或创建LoadingEvents文件夹
]]
local function GetOrCreateLoadingEvents()
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if not Events then
		Events = Instance.new("Folder")
		Events.Name = "Events"
		Events.Parent = ReplicatedStorage
	end

	local loadingFolder = Events:FindFirstChild("LoadingEvents")
	if not loadingFolder then
		loadingFolder = Instance.new("Folder")
		loadingFolder.Name = "LoadingEvents"
		loadingFolder.Parent = Events
	end

	-- 创建所需的RemoteEvent
	local eventNames = {
		"LoadingProgress",       -- S→C: 加载进度更新
		"LoadingStageUpdate",    -- S→C: 加载阶段更新
		"LoadingComplete",       -- S→C: 加载完成
		"ClientPreloadComplete", -- C→S: 客户端预加载完成
	}

	for _, eventName in ipairs(eventNames) do
		if not loadingFolder:FindFirstChild(eventName) then
			local event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = loadingFolder
		end
	end

	return loadingFolder
end

--[[
发送进度更新到客户端
@param player Player - 玩家对象
@param progress number - 进度值 (0-100)
@param stageName string - 当前阶段名称
]]
local function SendProgressUpdate(player, progress, stageName)
	if not LoadingEvents then return end

	local progressEvent = LoadingEvents:FindFirstChild("LoadingProgress")
	if progressEvent then
		progressEvent:FireClient(player, progress, stageName)
		DebugLog("发送进度更新:", player.Name, progress, stageName)
	end
end

--[[
发送阶段更新到客户端
@param player Player - 玩家对象
@param stage string - 阶段名称
]]
local function SendStageUpdate(player, stage)
	if not LoadingEvents then return end

	local stageEvent = LoadingEvents:FindFirstChild("LoadingStageUpdate")
	if stageEvent then
		stageEvent:FireClient(player, stage)
		DebugLog("发送阶段更新:", player.Name, stage)
	end
end

--[[
发送加载完成通知到客户端
@param player Player - 玩家对象
]]
local function SendLoadingComplete(player)
	if not LoadingEvents then return end

	local completeEvent = LoadingEvents:FindFirstChild("LoadingComplete")
	if completeEvent then
		completeEvent:FireClient(player)
		DebugLog("发送加载完成通知:", player.Name)
	end
end

--[[
更新玩家加载状态
@param player Player - 玩家对象
@param stage string - 阶段
@param subProgress number - 阶段内子进度 (0-1)
]]
local function UpdatePlayerLoadingState(player, stage, subProgress)
	local userId = player.UserId
	if not playerLoadingStates[userId] then
		playerLoadingStates[userId] = {
			Stage = LoadingSystem.LoadingStage.INIT,
			Progress = 0,
			StartTime = tick(),
			ClientPreloadComplete = false,
		}
	end

	local state = playerLoadingStates[userId]
	state.Stage = stage

	-- 计算总进度
	local baseProgress = STAGE_WEIGHTS[stage] or 0
	local nextStageProgress = 100

	-- 查找下一个阶段的权重
	local stageOrder = {
		LoadingSystem.LoadingStage.INIT,
		LoadingSystem.LoadingStage.DATA_LOADING,
		LoadingSystem.LoadingStage.HOME_SETUP,
		LoadingSystem.LoadingStage.SCENE_SETUP,
		LoadingSystem.LoadingStage.SYNC_DATA,
		LoadingSystem.LoadingStage.COMPLETE,
	}

	for i, s in ipairs(stageOrder) do
		if s == stage and i < #stageOrder then
			nextStageProgress = STAGE_WEIGHTS[stageOrder[i + 1]] or 100
			break
		end
	end

	-- 计算当前阶段内的进度
	subProgress = subProgress or 0
	local stageRange = nextStageProgress - baseProgress
	state.Progress = math.floor(baseProgress + stageRange * subProgress)
	state.Progress = math.clamp(state.Progress, 0, 100)

	-- 发送进度更新
	SendProgressUpdate(player, state.Progress, stage)
	SendStageUpdate(player, stage)
end

-- ==================== 公共接口 ====================

--[[
初始化Loading系统
@return boolean - 是否初始化成功
]]
function LoadingSystem.Initialize()
	DebugLog("初始化LoadingSystem...")

	-- 获取或创建事件
	LoadingEvents = GetOrCreateLoadingEvents()

	-- 监听客户端预加载完成事件
	-- V3.2.4修复：处理竞态条件，如果客户端消息比StartPlayerLoading先到达，缓存该状态
	local clientCompleteEvent = LoadingEvents:FindFirstChild("ClientPreloadComplete")
	if clientCompleteEvent then
		clientCompleteEvent.OnServerEvent:Connect(function(player)
			local userId = player.UserId
			if playerLoadingStates[userId] then
				-- 正常情况：加载状态已存在，直接标记完成
				playerLoadingStates[userId].ClientPreloadComplete = true
				DebugLog("客户端预加载完成:", player.Name)

				-- 检查是否可以完成加载
				LoadingSystem.TryCompleteLoading(player)
			else
				-- V3.2.4修复：加载状态尚不存在（客户端先于服务端StartPlayerLoading完成）
				-- 缓存此消息，等StartPlayerLoading时检查
				pendingClientPreloadComplete[userId] = true
				DebugLog("客户端预加载完成(缓存，等待StartPlayerLoading):", player.Name)
			end
		end)
	end

	DebugLog("LoadingSystem初始化完成")
	return true
end

--[[
开始玩家加载流程
@param player Player - 玩家对象
]]
function LoadingSystem.StartPlayerLoading(player)
	local userId = player.UserId

	-- V3.2.4修复：检查是否有提前到达的客户端预加载完成消息
	local hasPendingPreload = pendingClientPreloadComplete[userId] == true
	if hasPendingPreload then
		pendingClientPreloadComplete[userId] = nil  -- 清除缓存
		DebugLog("检测到缓存的客户端预加载完成消息:", player.Name)
	end

	-- 初始化加载状态
	playerLoadingStates[userId] = {
		Stage = LoadingSystem.LoadingStage.INIT,
		Progress = 0,
		StartTime = tick(),
		ClientPreloadComplete = hasPendingPreload,  -- V3.2.4：如果有缓存，直接标记为true
		DataLoaded = false,
		HomeSetup = false,
		SceneSetup = false,
		DataSynced = false,
	}

	DebugLog("开始玩家加载流程:", player.Name, "ClientPreloadComplete:", hasPendingPreload)
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.INIT, 0)
end

--[[
通知数据加载阶段
@param player Player - 玩家对象
@param subProgress number - 子进度 (0-1)
]]
function LoadingSystem.NotifyDataLoading(player, subProgress)
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.DATA_LOADING, subProgress or 0)
end

--[[
通知数据加载完成
@param player Player - 玩家对象
]]
function LoadingSystem.NotifyDataLoadComplete(player)
	local userId = player.UserId
	if playerLoadingStates[userId] then
		playerLoadingStates[userId].DataLoaded = true
	end
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.DATA_LOADING, 1)
	DebugLog("数据加载完成:", player.Name)
end

--[[
通知基地设置阶段
@param player Player - 玩家对象
@param subProgress number - 子进度 (0-1)
]]
function LoadingSystem.NotifyHomeSetup(player, subProgress)
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.HOME_SETUP, subProgress or 0)
end

--[[
通知基地设置完成
@param player Player - 玩家对象
]]
function LoadingSystem.NotifyHomeSetupComplete(player)
	local userId = player.UserId
	if playerLoadingStates[userId] then
		playerLoadingStates[userId].HomeSetup = true
	end
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.HOME_SETUP, 1)
	DebugLog("基地设置完成:", player.Name)
end

--[[
通知场景设置阶段
@param player Player - 玩家对象
@param subProgress number - 子进度 (0-1)
]]
function LoadingSystem.NotifySceneSetup(player, subProgress)
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.SCENE_SETUP, subProgress or 0)
end

--[[
通知场景设置完成
@param player Player - 玩家对象
]]
function LoadingSystem.NotifySceneSetupComplete(player)
	local userId = player.UserId
	if playerLoadingStates[userId] then
		playerLoadingStates[userId].SceneSetup = true
	end
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.SCENE_SETUP, 1)
	DebugLog("场景设置完成:", player.Name)
end

--[[
通知数据同步阶段
@param player Player - 玩家对象
@param subProgress number - 子进度 (0-1)
]]
function LoadingSystem.NotifyDataSync(player, subProgress)
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.SYNC_DATA, subProgress or 0)
end

--[[
通知数据同步完成
@param player Player - 玩家对象
]]
function LoadingSystem.NotifyDataSyncComplete(player)
	local userId = player.UserId
	if playerLoadingStates[userId] then
		playerLoadingStates[userId].DataSynced = true
	end
	UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.SYNC_DATA, 1)
	DebugLog("数据同步完成:", player.Name)

	-- 尝试完成加载
	LoadingSystem.TryCompleteLoading(player)
end

--[[
尝试完成加载流程
@param player Player - 玩家对象
]]
function LoadingSystem.TryCompleteLoading(player)
	local userId = player.UserId
	local state = playerLoadingStates[userId]

	if not state then
		DebugLog("无加载状态，无法完成:", player.Name)
		return
	end

	-- 检查所有条件是否满足
	local allConditionsMet = state.DataLoaded
		and state.HomeSetup
		and state.SceneSetup
		and state.DataSynced
		and state.ClientPreloadComplete

	if allConditionsMet then
		-- 标记加载完成
		state.Stage = LoadingSystem.LoadingStage.COMPLETE
		state.Progress = 100

		-- 发送完成通知
		UpdatePlayerLoadingState(player, LoadingSystem.LoadingStage.COMPLETE, 1)
		SendLoadingComplete(player)

		local duration = tick() - state.StartTime
		-- print(string.format("%s 玩家 %s 加载完成，耗时: %.2f秒", LOG_PREFIX, player.Name, duration))
	else
		-- 打印等待条件
		if DEBUG_MODE then
			DebugLog("等待条件:", player.Name)
			DebugLog("  DataLoaded:", state.DataLoaded)
			DebugLog("  HomeSetup:", state.HomeSetup)
			DebugLog("  SceneSetup:", state.SceneSetup)
			DebugLog("  DataSynced:", state.DataSynced)
			DebugLog("  ClientPreloadComplete:", state.ClientPreloadComplete)
		end
	end
end

--[[
获取玩家加载状态
@param player Player - 玩家对象
@return table|nil - 加载状态
]]
function LoadingSystem.GetPlayerLoadingState(player)
	return playerLoadingStates[player.UserId]
end

--[[
检查玩家是否加载完成
@param player Player - 玩家对象
@return boolean - 是否加载完成
]]
function LoadingSystem.IsPlayerLoaded(player)
	local state = playerLoadingStates[player.UserId]
	return state and state.Stage == LoadingSystem.LoadingStage.COMPLETE
end

--[[
清理玩家加载状态
@param player Player - 玩家对象
]]
function LoadingSystem.CleanupPlayer(player)
	local userId = player.UserId
	playerLoadingStates[userId] = nil
	pendingClientPreloadComplete[userId] = nil  -- V3.2.4：同时清理缓存
	DebugLog("清理玩家加载状态:", player.Name)
end

--[[
强制完成加载（超时兜底）
@param player Player - 玩家对象
]]
function LoadingSystem.ForceCompleteLoading(player)
	local userId = player.UserId
	local state = playerLoadingStates[userId]

	if state and state.Stage ~= LoadingSystem.LoadingStage.COMPLETE then
		warn(LOG_PREFIX, "强制完成加载:", player.Name)

		state.Stage = LoadingSystem.LoadingStage.COMPLETE
		state.Progress = 100
		state.DataLoaded = true
		state.HomeSetup = true
		state.SceneSetup = true
		state.DataSynced = true
		state.ClientPreloadComplete = true

		SendLoadingComplete(player)
	end
end

return LoadingSystem
