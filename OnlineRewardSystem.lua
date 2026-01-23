--[[
脚本名称: OnlineRewardSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/OnlineRewardSystem
版本: V6.1
职责: 在线奖励计时、领取、重置与事件同步
]]

local OnlineRewardSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local OnlineRewardConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("OnlineRewardConfig"))

local DataManager = nil
local InventorySystem = nil
local CurrencySystem = nil
local SkillSystem = nil

local OnlineRewardEvents = nil
local RequestDataEvent = nil
local DataEvent = nil
local ClaimEvent = nil
local ClaimResultEvent = nil

local onlineTimers = {}
local onlineSessions = {}
local refreshTimers = {}

local ONLINE_ACCUMULATE_INTERVAL = 1

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
			warn("[OnlineRewardSystem] DataManager not found")
			return false
		end
	end

	if not InventorySystem then
		local invModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if invModule then
			InventorySystem = require(invModule)
		else
			warn("[OnlineRewardSystem] InventorySystem not found")
			return false
		end
	end

	if not CurrencySystem then
		local currencyModule = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
		if currencyModule then
			CurrencySystem = require(currencyModule)
		else
			warn("[OnlineRewardSystem] CurrencySystem not found")
			return false
		end
	end

	if not SkillSystem then
		local skillModule = ServerScriptService.Systems:FindFirstChild("SkillSystem")
		if skillModule then
			SkillSystem = require(skillModule)
		else
			warn("[OnlineRewardSystem] SkillSystem not found")
			return false
		end
	end

	return true
end

local function InitializeEvents()
	if OnlineRewardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	OnlineRewardEvents = eventsFolder:FindFirstChild("OnlineRewardEvents")
	if not OnlineRewardEvents then
		OnlineRewardEvents = Instance.new("Folder")
		OnlineRewardEvents.Name = "OnlineRewardEvents"
		OnlineRewardEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = OnlineRewardEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = OnlineRewardEvents
		end
		return event
	end

	RequestDataEvent = GetOrCreateEvent("RequestOnlineRewardData")
	DataEvent = GetOrCreateEvent("OnlineRewardData")
	ClaimEvent = GetOrCreateEvent("ClaimOnlineReward")
	ClaimResultEvent = GetOrCreateEvent("ClaimOnlineRewardResult")

	return true
end

local function EnsureOnlineRewardData(player)
	if not InitializeModules() then
		return nil
	end

	local rewardData = DataManager.GetOnlineRewardData(player)
	if not rewardData then
		DataManager.WaitForPlayerData(player, 10)
		rewardData = DataManager.GetOnlineRewardData(player)
	end

	return rewardData
end

local function ResetRewardDataIfNeeded(player, rewardData, now)
	local currentDay = GetUtcDayIndex(now)
	local lastDay = tonumber(rewardData and rewardData.LastRefreshDay) or -1

	if lastDay ~= currentDay then
		rewardData.LastRefreshDay = currentDay
		rewardData.TotalOnlineSeconds = 0
		rewardData.ClaimedRewards = {}
		DataManager.SavePlayerDataThrottled(player)
		return true
	end

	return false
end

local function UpdateOnlineTime(player, rewardData, now)
	if not rewardData then
		return
	end

	ResetRewardDataIfNeeded(player, rewardData, now)

	local session = onlineSessions[player]
	if not session then
		onlineSessions[player] = { LastTick = now }
		return
	end

	local lastTick = tonumber(session.LastTick) or now
	if now < lastTick then
		session.LastTick = now
		return
	end

	local currentDay = GetUtcDayIndex(now)
	local lastTickDay = GetUtcDayIndex(lastTick)
	local delta = 0

	if currentDay == lastTickDay then
		delta = now - lastTick
	else
		local midnight = currentDay * 86400
		if now > midnight then
			delta = now - midnight
		end
	end

	if delta > 0 then
		local total = tonumber(rewardData.TotalOnlineSeconds) or 0
		rewardData.TotalOnlineSeconds = total + delta
	end

	session.LastTick = now
end

local function GetNextUnclaimedReward(rewardData)
	local claimed = rewardData and rewardData.ClaimedRewards or {}
	for _, reward in ipairs(OnlineRewardConfig.GetRewards()) do
		local rewardId = tonumber(reward.Id)
		if rewardId and not claimed[rewardId] then
			return rewardId, reward
		end
	end
	return nil, nil
end

local function BuildRewardInfo(reward)
	if type(reward) ~= "table" then
		return nil
	end

	return {
		Type = reward.Type,
		UnitId = reward.UnitId,
		SkillId = reward.SkillId,
		Count = reward.Count,
	}
end

local function GrantReward(player, reward)
	local rewardType = tostring(reward.Type or "")
	local count = tonumber(reward.Count) or 0

	if rewardType == "Unit" then
		local unitId = tostring(reward.UnitId or "")
		if unitId == "" or count <= 0 then
			return false, "Reward config invalid."
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
				return false, tostring(result or "Failed to grant unit.")
			end
			if type(result) == "table" and result.InstanceId then
				table.insert(grantedInstances, result)
			end
		end
		return true
	elseif rewardType == "Skill" then
		local skillId = tonumber(reward.SkillId)
		if not skillId or count <= 0 then
			return false, "Reward config invalid."
		end
		local success = SkillSystem.AddSkill(player, skillId, count)
		if not success then
			return false, "Failed to grant skill."
		end
		return true
	elseif rewardType == "Coins" then
		if count <= 0 then
			return false, "Reward config invalid."
		end
		local success = CurrencySystem.AddCoins(player, count, "Online reward")
		if not success then
			return false, "Failed to grant coins."
		end
		return true
	elseif rewardType == "Handcuff" then
		if count <= 0 then
			return false, "Reward config invalid."
		end
		local success = DataManager.AddHandcuffs(player, count)
		if not success then
			return false, "Failed to grant handcuffs."
		end
		return true
	end

	return false, "Unknown reward type."
end

local function SendData(player, rewardData, now)
	if not DataEvent then
		return
	end

	DataEvent:FireClient(player, {
		TotalOnlineSeconds = tonumber(rewardData and rewardData.TotalOnlineSeconds) or 0,
		ClaimedRewards = rewardData and rewardData.ClaimedRewards or {},
		LastRefreshDay = tonumber(rewardData and rewardData.LastRefreshDay) or GetUtcDayIndex(now),
		ServerTime = now,
	})
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

		OnlineRewardSystem.SyncPlayer(player)
		ScheduleDailyRefresh(player)
	end)
end

local function CleanupPlayer(player)
	if refreshTimers[player] then
		task.cancel(refreshTimers[player])
		refreshTimers[player] = nil
	end
	onlineTimers[player] = nil
	onlineSessions[player] = nil
end

-- ==================== 公共接口 ====================

function OnlineRewardSystem.SyncPlayer(player)
	local rewardData = EnsureOnlineRewardData(player)
	if not rewardData then
		return
	end

	local now = os.time()
	UpdateOnlineTime(player, rewardData, now)
	SendData(player, rewardData, now)
end

function OnlineRewardSystem.StartTracking(player)
	if not player or not player.Parent then
		return
	end

	if onlineTimers[player] then
		OnlineRewardSystem.StopTracking(player)
	end

	local rewardData = EnsureOnlineRewardData(player)
	if not rewardData then
		return
	end

	local now = os.time()
	ResetRewardDataIfNeeded(player, rewardData, now)
	onlineSessions[player] = { LastTick = now }

	local token = {}
	onlineTimers[player] = token

	task.spawn(function()
		while onlineTimers[player] == token and player and player:IsDescendantOf(Players) do
			task.wait(ONLINE_ACCUMULATE_INTERVAL)

			if onlineTimers[player] ~= token or not player or not player:IsDescendantOf(Players) then
				break
			end

			UpdateOnlineTime(player, rewardData, os.time())
		end

		if onlineTimers[player] == token then
			onlineTimers[player] = nil
		end
	end)
end

function OnlineRewardSystem.StopTracking(player)
	if not player then
		return
	end

	local rewardData = EnsureOnlineRewardData(player)
	if rewardData then
		UpdateOnlineTime(player, rewardData, os.time())
	end

	onlineTimers[player] = nil
	onlineSessions[player] = nil
end

function OnlineRewardSystem.ClaimReward(player, rewardId)
	if not InitializeModules() then
		return false, "System not ready."
	end

	local rewardData = EnsureOnlineRewardData(player)
	if not rewardData then
		return false, "Player data not ready."
	end

	local now = os.time()
	UpdateOnlineTime(player, rewardData, now)

	local reward = OnlineRewardConfig.GetRewardById(rewardId)
	if not reward then
		return false, "Reward not found."
	end

	local targetId = tonumber(rewardId)
	if not targetId then
		return false, "Invalid reward id."
	end

	local requiredSeconds = tonumber(reward.Seconds) or 0
	local totalSeconds = tonumber(rewardData.TotalOnlineSeconds) or 0
	if totalSeconds < requiredSeconds then
		return false, "Not enough online time."
	end

	rewardData.ClaimedRewards = rewardData.ClaimedRewards or {}
	if rewardData.ClaimedRewards[targetId] == true then
		return false, "Reward already claimed."
	end

	local success, message = GrantReward(player, reward)
	if not success then
		return false, message or "Failed to grant reward."
	end

	rewardData.ClaimedRewards[targetId] = true
	DataManager.SavePlayerDataThrottled(player)

	return true, "Reward Claimed!", BuildRewardInfo(reward)
end

-- ==================== 事件处理 ====================

local function HandleRequestData(player)
	if not player or not player.Parent then
		return
	end
	OnlineRewardSystem.SyncPlayer(player)
end

local function HandleClaimReward(player, rewardId)
	if not player or not player.Parent then
		return
	end

	local success, message, rewardInfo = OnlineRewardSystem.ClaimReward(player, rewardId)
	if ClaimResultEvent then
		ClaimResultEvent:FireClient(player, success, message or "", rewardInfo, tonumber(rewardId))
	end
end

function OnlineRewardSystem.Initialize()
	if not InitializeModules() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	if RequestDataEvent then
		RequestDataEvent.OnServerEvent:Connect(HandleRequestData)
	end
	if ClaimEvent then
		ClaimEvent.OnServerEvent:Connect(HandleClaimReward)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			OnlineRewardSystem.SyncPlayer(player)
			OnlineRewardSystem.StartTracking(player)
			ScheduleDailyRefresh(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		OnlineRewardSystem.StopTracking(player)
		CleanupPlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			OnlineRewardSystem.SyncPlayer(player)
			OnlineRewardSystem.StartTracking(player)
			ScheduleDailyRefresh(player)
		end)
	end

	return true
end

return OnlineRewardSystem
