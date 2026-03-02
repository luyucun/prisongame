--[[
脚本名称: DailyTaskSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/DailyTaskSystem
版本: V7.3
职责:
1. 每日任务数据同步（UTC0重置）
2. 在线时长任务（离线重置）
3. 勋章/击败任务领奖发放（手铐）
]]

local DailyTaskSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = nil

local DailyTaskEvents = nil
local RequestDataEvent = nil
local DataEvent = nil
local ClaimEvent = nil
local ClaimResultEvent = nil

local sessionTimers = {}
local sessionOnlineSeconds = {}
local lastPayloadSignature = {}

local initialized = false

local TASK_DEFINITIONS = {
	{ Id = 1, Type = "Online", Target = 15 * 60, RewardType = "Handcuff", RewardCount = 1 },
	{ Id = 2, Type = "Medal", Target = 20, RewardType = "Handcuff", RewardCount = 1 },
	{ Id = 3, Type = "EnemyDefeat", Target = 100, RewardType = "Handcuff", RewardCount = 1 },
}

local function GetDisplayProgress(taskDef, progress)
	if not taskDef then
		return progress
	end
	if taskDef.Type == "Online" then
		return math.max(0, math.floor(progress / 60))
	end
	return progress
end

local function GetDisplayTarget(taskDef, target)
	if not taskDef then
		return target
	end
	if taskDef.Type == "Online" then
		return math.max(1, math.ceil(target / 60))
	end
	return target
end

local function GetTaskDefinition(taskId)
	local targetTaskId = math.floor(tonumber(taskId) or 0)
	for _, taskDef in ipairs(TASK_DEFINITIONS) do
		if taskDef.Id == targetTaskId then
			return taskDef
		end
	end
	return nil
end

local function EnsureModules()
	if DataManager then
		return true
	end

	local module = ServerScriptService:WaitForChild("Core"):FindFirstChild("DataManager")
	if not module then
		warn("[DailyTaskSystem] DataManager module missing")
		return false
	end

	DataManager = require(module)
	return true
end

local function EnsureEvents()
	if DailyTaskEvents and RequestDataEvent and DataEvent and ClaimEvent and ClaimResultEvent then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	DailyTaskEvents = eventsFolder:FindFirstChild("DailyTaskEvents")
	if not DailyTaskEvents then
		DailyTaskEvents = Instance.new("Folder")
		DailyTaskEvents.Name = "DailyTaskEvents"
		DailyTaskEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = DailyTaskEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = DailyTaskEvents
		end
		return event
	end

	RequestDataEvent = GetOrCreateEvent("RequestDailyTaskData")
	DataEvent = GetOrCreateEvent("DailyTaskData")
	ClaimEvent = GetOrCreateEvent("ClaimDailyTaskReward")
	ClaimResultEvent = GetOrCreateEvent("ClaimDailyTaskResult")
	return true
end

local function RefreshTaskData(player, now)
	if not DataManager or not DataManager.RefreshDailyTaskData then
		return nil, false
	end

	local ok, refreshed, data = DataManager.RefreshDailyTaskData(player, now)
	if not ok then
		return nil, false
	end

	if refreshed then
		sessionOnlineSeconds[player] = 0
	end

	return data, refreshed
end

local function GetTaskProgress(player, taskData, taskId)
	if taskId == 1 then
		return math.max(0, math.floor(tonumber(sessionOnlineSeconds[player]) or 0))
	end
	if taskId == 2 then
		return math.max(0, math.floor(tonumber(taskData and taskData.MedalProgress) or 0))
	end
	if taskId == 3 then
		return math.max(0, math.floor(tonumber(taskData and taskData.EnemyDefeatProgress) or 0))
	end
	return 0
end

local function BuildPayload(player, taskData, now)
	local payload = {
		ServerTime = tonumber(now) or os.time(),
		Tasks = {},
		HasClaimable = false,
	}

	for _, taskDef in ipairs(TASK_DEFINITIONS) do
		local progress = GetTaskProgress(player, taskData, taskDef.Id)
		local target = math.max(1, math.floor(tonumber(taskDef.Target) or 1))
		local claimed = taskData and taskData.ClaimedTaskIds and taskData.ClaimedTaskIds[taskDef.Id] == true
		local completed = progress >= target
		if completed and not claimed then
			payload.HasClaimable = true
		end

		local displayProgress = GetDisplayProgress(taskDef, progress)
		local displayTarget = GetDisplayTarget(taskDef, target)

		payload.Tasks[taskDef.Id] = {
			Id = taskDef.Id,
			Type = taskDef.Type,
			Progress = displayProgress,
			Target = displayTarget,
			Completed = completed,
			Claimed = claimed == true,
			RewardType = taskDef.RewardType,
			RewardCount = taskDef.RewardCount,
		}
	end

	return payload
end

local function BuildPayloadSignature(payload)
	if type(payload) ~= "table" or type(payload.Tasks) ~= "table" then
		return ""
	end

	local t1 = payload.Tasks[1] or {}
	local t2 = payload.Tasks[2] or {}
	local t3 = payload.Tasks[3] or {}
	return table.concat({
		tostring(payload.HasClaimable == true),
		tostring(t1.Progress or 0), tostring(t1.Claimed == true),
		tostring(t2.Progress or 0), tostring(t2.Claimed == true),
		tostring(t3.Progress or 0), tostring(t3.Claimed == true),
	}, "|")
end

local function SendTaskData(player, force)
	if not player or not player:IsDescendantOf(Players) then
		return false
	end
	if not DataEvent then
		return false
	end

	local now = os.time()
	local taskData = RefreshTaskData(player, now)
	if not taskData then
		return false
	end

	local payload = BuildPayload(player, taskData, now)
	local signature = BuildPayloadSignature(payload)
	if not force and lastPayloadSignature[player] == signature then
		return false
	end

	lastPayloadSignature[player] = signature
	DataEvent:FireClient(player, payload)
	player:SetAttribute("DailyTaskClaimable", payload.HasClaimable == true)
	return true
end

local function GrantTaskReward(player, taskDef)
	if not DataManager then
		return false, "System not ready.", nil
	end

	if taskDef.RewardType == "Handcuff" then
		local rewardCount = math.max(1, math.floor(tonumber(taskDef.RewardCount) or 1))
		local success = DataManager.AddHandcuffs(player, rewardCount)
		if not success then
			return false, "Failed to grant reward.", nil
		end
		return true, "Reward Claimed!", {
			Type = "Handcuff",
			Count = rewardCount,
		}
	end

	return false, "Unknown reward type.", nil
end

local function HandleRequestData(player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end
	SendTaskData(player, true)
end

local function HandleClaimReward(player, taskId)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local success, message, rewardInfo = DailyTaskSystem.ClaimTaskReward(player, taskId)
	if ClaimResultEvent then
		ClaimResultEvent:FireClient(player, success, message or "", rewardInfo, math.floor(tonumber(taskId) or 0))
	end
end

local function CleanupPlayer(player)
	sessionTimers[player] = nil
	sessionOnlineSeconds[player] = nil
	lastPayloadSignature[player] = nil
end

function DailyTaskSystem.SyncPlayer(player)
	return SendTaskData(player, true)
end

function DailyTaskSystem.StartTracking(player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	if sessionTimers[player] then
		sessionTimers[player] = nil
	end

	sessionOnlineSeconds[player] = 0
	lastPayloadSignature[player] = nil

	local token = {}
	sessionTimers[player] = token

	task.spawn(function()
		while sessionTimers[player] == token and player and player:IsDescendantOf(Players) do
			task.wait(1)
			if sessionTimers[player] ~= token or not player or not player:IsDescendantOf(Players) then
				break
			end

			local taskData = RefreshTaskData(player, os.time())
			if not taskData then
				continue
			end

			local isTaskOneClaimed = taskData.ClaimedTaskIds and taskData.ClaimedTaskIds[1] == true
			if not isTaskOneClaimed then
				sessionOnlineSeconds[player] = math.max(0, math.floor(tonumber(sessionOnlineSeconds[player]) or 0) + 1)
			end

			SendTaskData(player, false)
		end

		if sessionTimers[player] == token then
			sessionTimers[player] = nil
		end
	end)
end

function DailyTaskSystem.StopTracking(player)
	if not player then
		return
	end
	CleanupPlayer(player)
end

function DailyTaskSystem.RecordEnemyDefeat(player, amount)
	if not EnsureModules() then
		return false
	end
	if not player or not player:IsDescendantOf(Players) then
		return false
	end

	local delta = math.max(0, math.floor(tonumber(amount) or 0))
	if delta <= 0 then
		return false
	end

	if not DataManager.AddDailyTaskEnemyDefeats then
		return false
	end

	DataManager.AddDailyTaskEnemyDefeats(player, delta, os.time())
	SendTaskData(player, false)
	return true
end

function DailyTaskSystem.RecordMedalGain(player, amount)
	if not EnsureModules() then
		return false
	end
	if not player or not player:IsDescendantOf(Players) then
		return false
	end

	local delta = math.max(0, math.floor(tonumber(amount) or 0))
	if delta <= 0 then
		return false
	end

	if not DataManager.AddDailyTaskMedals then
		return false
	end

	DataManager.AddDailyTaskMedals(player, delta, os.time())
	SendTaskData(player, false)
	return true
end

function DailyTaskSystem.ClaimTaskReward(player, taskId)
	if not EnsureModules() then
		return false, "System not ready.", nil
	end

	local targetTaskId = math.floor(tonumber(taskId) or 0)
	local taskDef = GetTaskDefinition(targetTaskId)
	if not taskDef then
		return false, "Invalid task.", nil
	end

	local taskData = RefreshTaskData(player, os.time())
	if not taskData then
		return false, "Player data not ready.", nil
	end

	local claimedTaskIds = taskData.ClaimedTaskIds or {}
	if claimedTaskIds[targetTaskId] == true then
		return false, "Reward already claimed.", nil
	end

	local progress = GetTaskProgress(player, taskData, targetTaskId)
	local target = math.max(1, math.floor(tonumber(taskDef.Target) or 1))
	if progress < target then
		return false, "Task not completed.", nil
	end

	local success, message, rewardInfo = GrantTaskReward(player, taskDef)
	if not success then
		return false, message or "Claim failed.", nil
	end

	if DataManager.SetDailyTaskClaimed then
		DataManager.SetDailyTaskClaimed(player, targetTaskId, true)
	else
		taskData.ClaimedTaskIds = taskData.ClaimedTaskIds or {}
		taskData.ClaimedTaskIds[targetTaskId] = true
	end

	if DataManager.SavePlayerDataThrottled then
		DataManager.SavePlayerDataThrottled(player)
	end

	SendTaskData(player, true)
	return true, message or "Reward Claimed!", rewardInfo
end

function DailyTaskSystem.Initialize()
	if initialized then
		return true
	end

	if not EnsureModules() then
		return false
	end
	if not EnsureEvents() then
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
			if DataManager and DataManager.WaitForPlayerData then
				DataManager.WaitForPlayerData(player, 10)
			end
			SendTaskData(player, true)
			DailyTaskSystem.StartTracking(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		DailyTaskSystem.StopTracking(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			SendTaskData(player, true)
			DailyTaskSystem.StartTracking(player)
		end)
	end

	initialized = true
	return true
end

return DailyTaskSystem
