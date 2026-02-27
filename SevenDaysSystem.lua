--[[
脚本名称: SevenDaysSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/SevenDaysSystem
版本: V4.8
]]

local SevenDaysSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SevenDaysConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SevenDaysConfig"))

local DataManager = nil
local InventorySystem = nil
local CurrencySystem = nil
local SkillSystem = nil

local SevenDaysEvents = nil
local RequestDataEvent = nil
local SevenDaysDataEvent = nil
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
			warn("[SevenDaysSystem] DataManager模块未找到")
			return false
		end
	end

	if not InventorySystem then
		local invModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if invModule then
			InventorySystem = require(invModule)
		else
			warn("[SevenDaysSystem] InventorySystem模块未找到")
			return false
		end
	end

	if not CurrencySystem then
		local currencyModule = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
		if currencyModule then
			CurrencySystem = require(currencyModule)
		else
			warn("[SevenDaysSystem] CurrencySystem模块未找到")
			return false
		end
	end

	if not SkillSystem then
		local skillModule = ServerScriptService.Systems:FindFirstChild("SkillSystem")
		if skillModule then
			SkillSystem = require(skillModule)
		else
			warn("[SevenDaysSystem] SkillSystem模块未找到")
			return false
		end
	end

	return true
end

local function InitializeEvents()
	if SevenDaysEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	SevenDaysEvents = eventsFolder:FindFirstChild("SevenDaysEvents")
	if not SevenDaysEvents then
		SevenDaysEvents = Instance.new("Folder")
		SevenDaysEvents.Name = "SevenDaysEvents"
		SevenDaysEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = SevenDaysEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = SevenDaysEvents
		end
		return event
	end

	RequestDataEvent = GetOrCreateEvent("RequestSevenDaysData")
	SevenDaysDataEvent = GetOrCreateEvent("SevenDaysData")
	ClaimRewardEvent = GetOrCreateEvent("ClaimSevenDayReward")
	ClaimResultEvent = GetOrCreateEvent("ClaimSevenDayResult")

	return true
end

local function NormalizeData(data)
	if type(data) ~= "table" then
		data = {}
	end

	data.Round = tonumber(data.Round) or 1

	if type(data.ClaimedDays) ~= "table" then
		data.ClaimedDays = {}
	end

	local unlocked = tonumber(data.UnlockedDays)
	if unlocked == nil then
		unlocked = 1
	end
	if unlocked < 0 then
		unlocked = 0
	elseif unlocked > SevenDaysConfig.MaxDays then
		unlocked = SevenDaysConfig.MaxDays
	end
	data.UnlockedDays = unlocked

	data.LastClaimTime = tonumber(data.LastClaimTime) or 0
	data.LastUnlockDay = tonumber(data.LastUnlockDay) or GetUtcDayIndex(os.time())
	data.PendingReset = data.PendingReset == true

	local claimedCount = 0
	for day, claimed in pairs(data.ClaimedDays) do
		if tonumber(day) and claimed == true then
			claimedCount = claimedCount + 1
		end
	end
	if data.UnlockedDays < claimedCount then
		data.UnlockedDays = claimedCount
	end

	return data
end

local function EnsureSevenDayData(player)
	if not InitializeModules() then
		return nil
	end

	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		playerData = DataManager.WaitForPlayerData(player, 10)
	end
	if not playerData then
		return nil
	end

	if not playerData.SevenDayData then
		playerData.SevenDayData = {
			Round = 1,
			ClaimedDays = {},
			UnlockedDays = 1,
			LastClaimTime = 0,
			LastUnlockDay = GetUtcDayIndex(os.time()),
			PendingReset = false,
		}
	end

	playerData.SevenDayData = NormalizeData(playerData.SevenDayData)
	return playerData.SevenDayData
end

local function CountClaimedDays(data)
	local count = 0
	for day = 1, SevenDaysConfig.MaxDays do
		if data.ClaimedDays and data.ClaimedDays[day] == true then
			count = count + 1
		end
	end
	return count
end

local function ApplyDailyUnlock(data, now)
	local currentDay = GetUtcDayIndex(now)
	local lastDay = tonumber(data.LastUnlockDay) or currentDay
	if currentDay <= lastDay then
		return false
	end

	data.LastUnlockDay = currentDay

	if data.PendingReset then
		return true
	end

	local claimedCount = CountClaimedDays(data)
	if data.UnlockedDays < SevenDaysConfig.MaxDays and claimedCount >= data.UnlockedDays then
		data.UnlockedDays = math.min(data.UnlockedDays + 1, SevenDaysConfig.MaxDays)
	end

	return true
end

local function ResetRoundIfNeeded(data, now, allowReset)
	if not data.PendingReset or not allowReset then
		return false
	end

	local lastClaimTime = tonumber(data.LastClaimTime) or now
	local lastClaimDay = GetUtcDayIndex(lastClaimTime)
	local currentDay = GetUtcDayIndex(now)
	local canUnlockFirst = currentDay > lastClaimDay

	data.Round = (tonumber(data.Round) or 1) + 1
	data.ClaimedDays = {}
	data.UnlockedDays = canUnlockFirst and 1 or 0
	data.LastClaimTime = now
	data.LastUnlockDay = currentDay
	data.PendingReset = false
	return true
end

local function BuildPayload(data, now)
	return {
		UnlockedDays = data.UnlockedDays or 0,
		ClaimedDays = data.ClaimedDays or {},
		PendingReset = data.PendingReset == true,
		NextRefreshTime = GetNextUtcMidnight(now),
		ServerTime = now,
		Round = data.Round or 1,
	}
end

local function SendData(player, data)
	if SevenDaysDataEvent then
		local now = os.time()
		SevenDaysDataEvent:FireClient(player, BuildPayload(data, now))
	end
end

local function GrantReward(player, reward)
	if reward.Type == SevenDaysConfig.RewardType.Unit then
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
		return true, "OK"
	end

	if reward.Type == SevenDaysConfig.RewardType.Skill then
		local skillId = tonumber(reward.SkillId)
		local count = tonumber(reward.Count) or 1
		if not skillId or count <= 0 then
			return false, "奖励配置错误"
		end
		local addSuccess = DataManager.AddSkill(player, skillId, count)
		if not addSuccess then
			return false, "技能发放失败"
		end
		if SkillSystem and SkillSystem.SyncSkillInventory then
			SkillSystem.SyncSkillInventory(player)
		end
		return true, "OK"
	end

	if reward.Type == SevenDaysConfig.RewardType.Coins then
		local amount = tonumber(reward.Amount) or 0
		if amount <= 0 then
			return false, "奖励配置错误"
		end
		local success = CurrencySystem.AddCoins(player, amount, "七日登录奖励", { ApplyRebirthBonus = false })
		if not success then
			return false, "金币发放失败"
		end
		return true, "OK"
	end

	return false, "奖励类型未知"
end

-- ==================== 公共接口 ====================

function SevenDaysSystem.SyncPlayer(player, allowReset)
	local data = EnsureSevenDayData(player)
	if not data then
		return false
	end

	local now = os.time()
	local changed = false

	if ResetRoundIfNeeded(data, now, allowReset == true) then
		changed = true
	end

	if ApplyDailyUnlock(data, now) then
		changed = true
	end

	if changed then
		DataManager.SavePlayerDataThrottled(player)
	end

	SendData(player, data)
	return true
end

function SevenDaysSystem.ClaimReward(player, dayIndex)
	if type(dayIndex) ~= "number" then
		dayIndex = tonumber(dayIndex)
	end
	if not dayIndex or dayIndex < 1 or dayIndex > SevenDaysConfig.MaxDays then
		return false, "无效奖励"
	end

	local data = EnsureSevenDayData(player)
	if not data then
		return false, "数据加载失败"
	end

	local now = os.time()
	ApplyDailyUnlock(data, now)

	if data.PendingReset then
		return false, "本轮奖励已领取完"
	end

	if data.ClaimedDays and data.ClaimedDays[dayIndex] then
		return false, "奖励已领取"
	end

	if dayIndex > (data.UnlockedDays or 0) then
		return false, "奖励未解锁"
	end

	local reward = SevenDaysConfig.GetReward(dayIndex)
	if not reward then
		return false, "奖励配置缺失"
	end

	local success, message = GrantReward(player, reward)
	if not success then
		return false, message
	end

	data.ClaimedDays[dayIndex] = true
	data.LastClaimTime = now

	if CountClaimedDays(data) >= SevenDaysConfig.MaxDays then
		data.PendingReset = true
	end

	DataManager.SavePlayerDataThrottled(player)
	SendData(player, data)

	return true, "Reward Claimed!"
end

function SevenDaysSystem.UnlockAll(player)
	local data = EnsureSevenDayData(player)
	if not data then
		return false, "数据加载失败"
	end

	local now = os.time()
	ApplyDailyUnlock(data, now)

	if data.PendingReset then
		SendData(player, data)
		return true, "本轮奖励已完成"
	end

	data.UnlockedDays = SevenDaysConfig.MaxDays
	data.LastUnlockDay = GetUtcDayIndex(now)

	DataManager.SavePlayerDataThrottled(player)
	SendData(player, data)

	return true, "OK"
end

function SevenDaysSystem.GMUnlockNextDay(player)
	local data = EnsureSevenDayData(player)
	if not data then
		return false, "数据加载失败"
	end

	local now = os.time()
	ApplyDailyUnlock(data, now)

	if data.PendingReset then
		SendData(player, data)
		return false, "本轮奖励已完成"
	end

	local unlocked = tonumber(data.UnlockedDays) or 0
	local claimedCount = CountClaimedDays(data)
	if unlocked < claimedCount then
		unlocked = claimedCount
	end

	if unlocked >= SevenDaysConfig.MaxDays then
		SendData(player, data)
		return false, "奖励已全部解锁"
	end

	data.UnlockedDays = math.min(unlocked + 1, SevenDaysConfig.MaxDays)
	data.LastUnlockDay = GetUtcDayIndex(now)

	DataManager.SavePlayerDataThrottled(player)
	SendData(player, data)

	return true, string.format("已解锁到第 %d 天", data.UnlockedDays)
end

-- ==================== 事件处理 ====================

local function HandleRequestData(player, allowReset)
	if not player or not player.Parent then
		return
	end
	SevenDaysSystem.SyncPlayer(player, allowReset == true)
end

local function HandleClaimReward(player, dayIndex)
	if not player or not player.Parent then
		return
	end

	local success, message = SevenDaysSystem.ClaimReward(player, dayIndex)
	if ClaimResultEvent then
		ClaimResultEvent:FireClient(player, success, message or "", dayIndex)
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

		local data = EnsureSevenDayData(player)
		if not data then
			return
		end

		local changed = ApplyDailyUnlock(data, os.time())
		if changed then
			DataManager.SavePlayerDataThrottled(player)
		end
		SendData(player, data)

		ScheduleDailyRefresh(player)
	end)
end

local function CleanupPlayer(player)
	if refreshTimers[player] then
		task.cancel(refreshTimers[player])
		refreshTimers[player] = nil
	end
end

function SevenDaysSystem.Initialize()
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
			SevenDaysSystem.SyncPlayer(player, false)
			ScheduleDailyRefresh(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		CleanupPlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			SevenDaysSystem.SyncPlayer(player, false)
			ScheduleDailyRefresh(player)
		end)
	end

	return true
end

return SevenDaysSystem
