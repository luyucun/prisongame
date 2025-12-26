--[[
=====================================================
Script Name: LeaderboardSystem.lua
Script Type: ModuleScript (Server System)
Script Location: ServerScriptService/Systems/LeaderboardSystem
Version: V4.7
=====================================================
--]]

local LeaderboardSystem = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager"))

local REFRESH_INTERVAL = 180
local MAX_ENTRIES = 20
local TIME_SCALE = 100000000
local UPDATE_COOLDOWN = 10
local REQUEST_REFRESH_COOLDOWN = 10

local leaderboardStore = nil
local isInitialized = false
local refreshInProgress = false

local cachedEntries = {}
local lastRefreshTime = 0
local nextRefreshTime = 0

local nameCache = {}
local lastWriteTimes = {}
local pendingWrites = {}
local pendingTimers = {}

local leaderboardEvents = nil
local requestLeaderboardEvent = nil
local leaderboardDataEvent = nil

local function GetLeaderboardStore()
	if leaderboardStore then
		return leaderboardStore
	end

	local suffix = (RunService:IsStudio() and GameConfig.USE_STUDIO_DATASTORE_SUFFIX) and "_Studio" or ""
	local storeName = "GlobalPowerLeaderboard_V4_7" .. suffix
	leaderboardStore = DataStoreService:GetOrderedDataStore(storeName)
	return leaderboardStore
end

local function EnsureEvents()
	if leaderboardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events") or ReplicatedStorage:WaitForChild("Events", 5)
	if not eventsFolder then
		warn(GameConfig.LOG_PREFIX, "[LeaderboardSystem] Events folder not found")
		return false
	end

	leaderboardEvents = eventsFolder:FindFirstChild("LeaderboardEvents")
	if not leaderboardEvents then
		leaderboardEvents = Instance.new("Folder")
		leaderboardEvents.Name = "LeaderboardEvents"
		leaderboardEvents.Parent = eventsFolder
	end

	requestLeaderboardEvent = leaderboardEvents:FindFirstChild("RequestLeaderboard")
	if not requestLeaderboardEvent then
		requestLeaderboardEvent = Instance.new("RemoteEvent")
		requestLeaderboardEvent.Name = "RequestLeaderboard"
		requestLeaderboardEvent.Parent = leaderboardEvents
	end

	leaderboardDataEvent = leaderboardEvents:FindFirstChild("LeaderboardData")
	if not leaderboardDataEvent then
		leaderboardDataEvent = Instance.new("RemoteEvent")
		leaderboardDataEvent.Name = "LeaderboardData"
		leaderboardDataEvent.Parent = leaderboardEvents
	end

	return true
end

local function EncodeScore(power, reachTime)
	local p = math.max(0, math.floor(tonumber(power) or 0))
	local t = math.max(0, math.floor(tonumber(reachTime) or 0))
	local timeMod = t % TIME_SCALE
	return p * TIME_SCALE + (TIME_SCALE - timeMod)
end

local function DecodePower(score)
	local value = tonumber(score) or 0
	if value <= 0 then
		return 0
	end
	return math.floor(value / TIME_SCALE)
end

local function GetPlayerNameByUserId(userId)
	if not userId then
		return "Unknown"
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		return onlinePlayer.Name
	end

	local cached = nameCache[userId]
	if cached then
		return cached
	end

	local success, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	if success and result then
		nameCache[userId] = result
		return result
	end

	return "User_" .. tostring(userId)
end

local function WriteScore(userId, score)
	local store = GetLeaderboardStore()
	if not store then
		return
	end

	local success, result = pcall(function()
		store:SetAsync(tostring(userId), score)
	end)

	if success then
		lastWriteTimes[userId] = os.time()
	else
		warn(GameConfig.LOG_PREFIX, "[LeaderboardSystem] Failed to save score:", result)
	end
end

local function ScheduleWrite(userId, score)
	if UPDATE_COOLDOWN <= 0 then
		WriteScore(userId, score)
		return
	end

	local now = os.time()
	local lastWrite = lastWriteTimes[userId] or 0
	if now - lastWrite >= UPDATE_COOLDOWN then
		WriteScore(userId, score)
		return
	end

	pendingWrites[userId] = score
	if pendingTimers[userId] then
		return
	end

	local delaySeconds = math.max(0.1, UPDATE_COOLDOWN - (now - lastWrite))
	pendingTimers[userId] = true
	task.delay(delaySeconds, function()
		pendingTimers[userId] = nil
		local pending = pendingWrites[userId]
		if not pending then
			return
		end
		pendingWrites[userId] = nil
		WriteScore(userId, pending)
	end)
end

local function BuildEntries()
	local store = GetLeaderboardStore()
	if not store then
		return false
	end

	local success, pages = pcall(function()
		return store:GetSortedAsync(false, MAX_ENTRIES)
	end)

	if not success or not pages then
		warn(GameConfig.LOG_PREFIX, "[LeaderboardSystem] Failed to get sorted data")
		return false
	end

	local page = pages:GetCurrentPage()
	local entries = {}
	local rank = 1

	for _, item in ipairs(page) do
		local userId = tonumber(item.key)
		if userId then
			local power = DecodePower(item.value)
			local name = GetPlayerNameByUserId(userId)
			table.insert(entries, {
				UserId = userId,
				Name = name,
				Power = power,
				Rank = rank,
			})
			rank = rank + 1
		end
	end

	cachedEntries = entries
	lastRefreshTime = os.time()
	nextRefreshTime = lastRefreshTime + REFRESH_INTERVAL
	return true
end

function LeaderboardSystem.BroadcastLeaderboard()
	if not leaderboardDataEvent then
		return
	end

	local serverTime = os.time()
	leaderboardDataEvent:FireAllClients(cachedEntries, nextRefreshTime, serverTime)
end

function LeaderboardSystem.SendLeaderboardToPlayer(player)
	if not player or not leaderboardDataEvent then
		return
	end

	local now = os.time()
	local shouldRefresh = false
	if nextRefreshTime == 0 or now >= nextRefreshTime then
		shouldRefresh = true
	elseif #cachedEntries == 0 and (now - lastRefreshTime) >= REQUEST_REFRESH_COOLDOWN then
		shouldRefresh = true
	end

	if shouldRefresh then
		LeaderboardSystem.RefreshLeaderboard()
	end

	local serverTime = os.time()
	leaderboardDataEvent:FireClient(player, cachedEntries, nextRefreshTime, serverTime)
end

function LeaderboardSystem.RefreshLeaderboard()
	if refreshInProgress then
		return false
	end

	refreshInProgress = true
	local success = BuildEntries()
	if success then
		LeaderboardSystem.BroadcastLeaderboard()
	else
		lastRefreshTime = os.time()
		nextRefreshTime = lastRefreshTime + REFRESH_INTERVAL
	end
	refreshInProgress = false
	return success
end

function LeaderboardSystem.UpdatePlayerPower(player, totalPower)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		return
	end

	local power = math.max(0, math.floor(tonumber(totalPower) or 0))
	local now = os.time()

	local record = playerData.PowerRankData
	if not record then
		record = {
			Power = power,
			Time = now,
		}
		playerData.PowerRankData = record
	else
		local cachedPower = tonumber(record.Power) or 0
		if cachedPower ~= power then
			record.Power = power
			record.Time = now
		end
	end

	local score = EncodeScore(record.Power, record.Time)
	ScheduleWrite(player.UserId, score)
end

function LeaderboardSystem.Initialize()
	if isInitialized then
		return true
	end

	if not EnsureEvents() then
		return false
	end

	if requestLeaderboardEvent then
		requestLeaderboardEvent.OnServerEvent:Connect(function(player)
			LeaderboardSystem.SendLeaderboardToPlayer(player)
		end)
	end

	isInitialized = true
	task.spawn(function()
		LeaderboardSystem.RefreshLeaderboard()
		while true do
			task.wait(REFRESH_INTERVAL)
			LeaderboardSystem.RefreshLeaderboard()
		end
	end)

	return true
end

return LeaderboardSystem
