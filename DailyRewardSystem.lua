--[[
脚本名称: DailyRewardSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/DailyRewardSystem
版本: V5.3
职责: 每日免费奖励发放与状态同步
]]

local DailyRewardSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyRewardConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("DailyRewardConfig"))

local DataManager = nil
local InventorySystem = nil

local DailyRewardEvents = nil
local RequestDataEvent = nil
local DailyRewardDataEvent = nil
local ClaimRewardEvent = nil
local ClaimResultEvent = nil

local refreshTimers = {}

-- ==================== 工具函数 ====================

local function GetUtcDayIndex(timestamp)
	local ts = tonumber(timestamp) or os.time()
	return math.floor(ts / 86400)
end

local function GetNextUtcMidnight(timestamp)
	local now = tonumber(timestamp) or os.time()
	local dayIndex = GetUtcDayIndex(now)
	return (dayIndex + 1) * 86400
end

local function InitializeModules()
	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if dataModule then
			DataManager = require(dataModule)
		else
			warn("[DailyRewardSystem] DataManager模块未找到")
			return false
		end
	end

	if not InventorySystem then
		local invModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if invModule then
			InventorySystem = require(invModule)
		else
			warn("[DailyRewardSystem] InventorySystem模块未找到")
			return false
		end
	end

	return true
end

local function InitializeEvents()
	if DailyRewardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	DailyRewardEvents = eventsFolder:FindFirstChild("DailyRewardEvents")
	if not DailyRewardEvents then
		DailyRewardEvents = Instance.new("Folder")
		DailyRewardEvents.Name = "DailyRewardEvents"
		DailyRewardEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = DailyRewardEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = DailyRewardEvents
		end
		return event
	end

	RequestDataEvent = GetOrCreateEvent("RequestDailyRewardData")
	DailyRewardDataEvent = GetOrCreateEvent("DailyRewardData")
	ClaimRewardEvent = GetOrCreateEvent("ClaimDailyReward")
	ClaimResultEvent = GetOrCreateEvent("ClaimDailyRewardResult")

	return true
end

local function EnsureDailyRewardData(player)
	if not InitializeModules() then
		return nil
	end

	local rewardData = DataManager.GetDailyRewardData(player)
	if not rewardData then
		DataManager.WaitForPlayerData(player, 10)
		rewardData = DataManager.GetDailyRewardData(player)
	end

	return rewardData
end

local function CanClaimReward(rewardData, now)
	local currentDay = GetUtcDayIndex(now)
	local lastClaimDay = tonumber(rewardData and rewardData.LastClaimDay) or 0
	return lastClaimDay < currentDay
end

local function BuildPayload(rewardData, now)
	local canClaim = CanClaimReward(rewardData, now)
	return {
		CanClaim = canClaim,
		LastClaimDay = rewardData and rewardData.LastClaimDay or 0,
		LastClaimTime = rewardData and rewardData.LastClaimTime or 0,
		NextRefreshTime = GetNextUtcMidnight(now),
		ServerTime = now,
	}
end

local function SendData(player, rewardData)
	if not DailyRewardDataEvent then
		return
	end

	local now = os.time()
	local payload = BuildPayload(rewardData, now)
	DailyRewardDataEvent:FireClient(player, payload)
	player:SetAttribute("DailyRewardAvailable", payload.CanClaim == true)
end

local function GrantReward(player, reward)
	local unitId = tostring(reward.UnitId or "")
	local count = tonumber(reward.Count) or 1
	if unitId == "" or count <= 0 then
		return false, "奖励配置错误"
	end

	local grantedInstances = {}
	for i = 1, count do
		local success, result = InventorySystem.AddUnit(player, unitId)
		if not success then
			for _, instance in ipairs(grantedInstances) do
				if instance and instance.InstanceId then
					InventorySystem.RemoveUnit(player, instance.InstanceId)
				end
			end
			return false, tostring(result or "发放失败")
		end
		if type(result) == "table" and result.InstanceId then
			table.insert(grantedInstances, result)
		end
	end

	return true, {
		Type = "Unit",
		UnitId = unitId,
		Count = count,
	}
end

-- ==================== 公共接口 ====================

function DailyRewardSystem.SyncPlayer(player)
	local rewardData = EnsureDailyRewardData(player)
	if not rewardData then
		return false
	end

	SendData(player, rewardData)
	return true
end

function DailyRewardSystem.ClaimReward(player)
	local rewardData = EnsureDailyRewardData(player)
	if not rewardData then
		return false, "数据加载失败"
	end

	local now = os.time()
	if not CanClaimReward(rewardData, now) then
		return false, "今日奖励已领取"
	end

	local reward = DailyRewardConfig.RollReward()
	if not reward then
		return false, "奖励配置缺失"
	end

	local success, result = GrantReward(player, reward)
	if not success then
		return false, result
	end

	rewardData.LastClaimDay = GetUtcDayIndex(now)
	rewardData.LastClaimTime = now

	DataManager.SavePlayerDataThrottled(player)
	SendData(player, rewardData)

	return true, "Reward Claimed!", result
end

function DailyRewardSystem.GMResetDailyReward(player)
	local rewardData = EnsureDailyRewardData(player)
	if not rewardData then
		return false, "数据加载失败"
	end

	local now = os.time()
	rewardData.LastClaimDay = math.max(0, GetUtcDayIndex(now) - 1)
	rewardData.LastClaimTime = 0

	DataManager.SavePlayerDataThrottled(player)
	SendData(player, rewardData)

	return true, "已重置今日免费奖励"
end

-- ==================== 事件处理 ====================

local function HandleRequestData(player)
	if not player or not player.Parent then
		return
	end
	DailyRewardSystem.SyncPlayer(player)
end

local function HandleClaimReward(player)
	if not player or not player.Parent then
		return
	end

	local success, message, rewardInfo = DailyRewardSystem.ClaimReward(player)
	if ClaimResultEvent then
		ClaimResultEvent:FireClient(player, success, message or "", rewardInfo)
	end
end

local function ScheduleDailyRefresh(player)
	if not player or not player.Parent then
		return
	end

	if refreshTimers[player] then
		task.cancel(refreshTimers[player])
		refreshTimers[player] = nil
	end

	local now = os.time()
	local nextTime = GetNextUtcMidnight(now)
	local delaySeconds = math.max(1, nextTime - now + 1)

	refreshTimers[player] = task.delay(delaySeconds, function()
		refreshTimers[player] = nil
		if not player or not player.Parent then
			return
		end

		DailyRewardSystem.SyncPlayer(player)
		ScheduleDailyRefresh(player)
	end)
end

local function CleanupPlayer(player)
	if refreshTimers[player] then
		task.cancel(refreshTimers[player])
		refreshTimers[player] = nil
	end
end

function DailyRewardSystem.Initialize()
	if not InitializeModules() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	if RequestDataEvent then
		RequestDataEvent.OnServerEvent:Connect(HandleRequestData)
	end
	if ClaimRewardEvent then
		ClaimRewardEvent.OnServerEvent:Connect(HandleClaimReward)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			DailyRewardSystem.SyncPlayer(player)
			ScheduleDailyRefresh(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		CleanupPlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			DailyRewardSystem.SyncPlayer(player)
			ScheduleDailyRefresh(player)
		end)
	end

	return true
end

return DailyRewardSystem
