--[[
Script Name: GroupRewardSystem
Script Type: ModuleScript (Server System)
Script Location: ServerScriptService/Systems/GroupRewardSystem
Version: V4.9
]]

local GroupRewardSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local AnalyticsService = game:GetService("AnalyticsService")
local GroupService = game:GetService("GroupService")

local GroupRewardConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GroupRewardConfig"))

local DataManager = nil
local InventorySystem = nil
local SoundSystem = nil

local groupRewardEvents = nil
local requestDataEvent = nil
local groupRewardDataEvent = nil
local claimRewardEvent = nil
local claimResultEvent = nil

local function InitializeModules()
	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if dataModule then
			DataManager = require(dataModule)
		else
			warn("[GroupRewardSystem] DataManager not found")
			return false
		end
	end

	if not InventorySystem then
		local invModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if invModule then
			InventorySystem = require(invModule)
		else
			warn("[GroupRewardSystem] InventorySystem not found")
			return false
		end
	end

	if not SoundSystem then
		local soundModule = ServerScriptService.Systems:FindFirstChild("SoundSystem")
		if soundModule then
			SoundSystem = require(soundModule)
		else
			warn("[GroupRewardSystem] SoundSystem not found")
			return false
		end
	end

	return true
end

local function InitializeEvents()
	if groupRewardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	groupRewardEvents = eventsFolder:FindFirstChild("GroupRewardEvents")
	if not groupRewardEvents then
		groupRewardEvents = Instance.new("Folder")
		groupRewardEvents.Name = "GroupRewardEvents"
		groupRewardEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = groupRewardEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = groupRewardEvents
		end
		return event
	end

	requestDataEvent = GetOrCreateEvent("RequestGroupRewardData")
	groupRewardDataEvent = GetOrCreateEvent("GroupRewardData")
	claimRewardEvent = GetOrCreateEvent("ClaimGroupReward")
	claimResultEvent = GetOrCreateEvent("ClaimGroupRewardResult")

	return true
end

local function EnsureGroupRewardData(player)
	if not InitializeModules() then
		return nil
	end

	local rewardData = DataManager.GetGroupRewardData(player)
	if not rewardData then
		DataManager.WaitForPlayerData(player, 10)
		rewardData = DataManager.GetGroupRewardData(player)
	end

	return rewardData
end

local function SendData(player, rewardData)
	if groupRewardDataEvent then
		groupRewardDataEvent:FireClient(player, {
			Claimed = rewardData and rewardData.Claimed == true,
		})
	end
end

local function IsInGroup(player)
	local groupId = tonumber(GroupRewardConfig.GroupId) or 0
	if groupId <= 0 then
		warn("[GroupRewardSystem] GroupId not set in GroupRewardConfig")
		return false
	end

	local success, result = pcall(function()
		return player:IsInGroup(groupId)
	end)
	if success and result == true then
		return true
	end
	if not success then
		warn("[GroupRewardSystem] Group check failed:", result)
	end

	local fallbackSuccess, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if not fallbackSuccess then
		warn("[GroupRewardSystem] GroupService check failed:", groups)
		return false
	end

	for _, groupInfo in ipairs(groups) do
		if groupInfo and tonumber(groupInfo.Id) == groupId then
			return true
		end
	end

	return false
end

local function GrantReward(player)
	local reward = GroupRewardConfig.Reward
	if type(reward) ~= "table" then
		return false, "Reward config missing"
	end

	local unitId = tostring(reward.UnitId or "")
	local count = tonumber(reward.Count) or 0
	if unitId == "" or count <= 0 then
		return false, "Reward config invalid"
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
			return false, tostring(result or "Grant failed")
		end
		if type(result) == "table" and result.InstanceId then
			table.insert(grantedInstances, result)
		end
	end

	return true, "OK"
end

local function LogGroupRewardClaim(player)
	if not player then
		return
	end

	local reward = GroupRewardConfig.Reward or {}
	local unitId = tostring(reward.UnitId or "")
	local count = tonumber(reward.Count) or 0
	local groupId = tonumber(GroupRewardConfig.GroupId) or 0

	local success, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, "GroupReward", 1, {
			action = "Claim",
			groupId = groupId,
			unitId = unitId,
			count = count,
		})
	end)
	if not success then
		warn("[GroupRewardSystem] Analytics log failed:", err)
	end
end

function GroupRewardSystem.SyncPlayer(player)
	local rewardData = EnsureGroupRewardData(player)
	if not rewardData then
		return false
	end

	player:SetAttribute("GroupRewardClaimed", rewardData.Claimed == true)
	SendData(player, rewardData)
	return true
end

function GroupRewardSystem.ClaimReward(player)
	local rewardData = EnsureGroupRewardData(player)
	if not rewardData then
		return false, "Data load failed"
	end

	if rewardData.Claimed == true then
		return false, "Reward already claimed"
	end

	if not IsInGroup(player) then
		if SoundSystem and SoundSystem.OnPurchaseError then
			SoundSystem.OnPurchaseError(player)
		end
		return false, "Join the group for rewards!"
	end

	local success, message = GrantReward(player)
	if not success then
		return false, message
	end

	DataManager.SetGroupRewardClaimed(player, true)
	rewardData.Claimed = true
	DataManager.SavePlayerDataThrottled(player)
	player:SetAttribute("GroupRewardClaimed", true)
	SendData(player, rewardData)
	LogGroupRewardClaim(player)

	return true, "Claim Successful!"
end

local function HandleRequestData(player)
	if not player or not player.Parent then
		return
	end
	GroupRewardSystem.SyncPlayer(player)
end

local function HandleClaimReward(player)
	if not player or not player.Parent then
		return
	end

	local success, message = GroupRewardSystem.ClaimReward(player)
	if claimResultEvent then
		local claimed = player:GetAttribute("GroupRewardClaimed") == true
		claimResultEvent:FireClient(player, success, message or "", claimed)
	end
end

function GroupRewardSystem.Initialize()
	if not InitializeModules() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	if requestDataEvent then
		requestDataEvent.OnServerEvent:Connect(HandleRequestData)
	end
	if claimRewardEvent then
		claimRewardEvent.OnServerEvent:Connect(HandleClaimReward)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			GroupRewardSystem.SyncPlayer(player)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			GroupRewardSystem.SyncPlayer(player)
		end)
	end

	return true
end

return GroupRewardSystem
