--[[
=====================================================
Script: BadgeSystem.lua
Type: ModuleScript
Location: ServerScriptService/Systems/BadgeSystem
Version: V4.4
Description: Server-side badge award system
=====================================================
--]]

local BadgeSystem = {}

-- ==================== Services ====================
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- ==================== Modules ====================
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local BadgeConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BadgeConfig"))
local DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager"))

-- ==================== Debug ====================
local _print = print
local function DebugPrint(...)
	if GameConfig.DEBUG_MODE then
		_print(...)
	end
end
local print = DebugPrint

-- ==================== Cache ====================
local badgeCache = {}    -- [userId] = { [badgeId] = true }
local pendingAwards = {} -- [userId] = { [badgeId] = {attempts, nextAttempt, reason} }

local PENDING_POLL_INTERVAL = 5
local RETRY_INTERVAL = 30
local MAX_RETRY_ATTEMPTS = 10
local FULL_SCAN_INTERVAL = 300

local function GetBadgeCache(userId)
	local cache = badgeCache[userId]
	if not cache then
		cache = {}
		badgeCache[userId] = cache
	end
	return cache
end

local function HasBadgeCached(userId, badgeId)
	local cache = badgeCache[userId]
	return cache and cache[badgeId] == true
end

local function MarkBadgeCached(userId, badgeId, hasBadge)
	if not hasBadge then
		return
	end
	local cache = GetBadgeCache(userId)
	cache[badgeId] = true
end

local function GetPendingTable(userId)
	local userPending = pendingAwards[userId]
	if not userPending then
		userPending = {}
		pendingAwards[userId] = userPending
	end
	return userPending
end

local function GetPendingEntry(userId, badgeId)
	local userPending = pendingAwards[userId]
	return userPending and userPending[badgeId] or nil
end

local function IsPendingBadge(userId, badgeId)
	return GetPendingEntry(userId, badgeId) ~= nil
end

local function ClearPendingBadge(userId, badgeId)
	local userPending = pendingAwards[userId]
	if not userPending then
		return
	end
	userPending[badgeId] = nil
	if next(userPending) == nil then
		pendingAwards[userId] = nil
	end
end

local function SchedulePendingBadge(userId, badgeId, reason)
	local now = os.clock()
	local userPending = GetPendingTable(userId)
	local entry = userPending[badgeId]
	if not entry then
		entry = {
			attempts = 0,
			nextAttempt = 0,
			reason = "",
		}
		userPending[badgeId] = entry
	end

	entry.attempts = (entry.attempts or 0) + 1
	entry.reason = reason or entry.reason

	local nextAttempt = now + RETRY_INTERVAL
	if entry.nextAttempt and entry.nextAttempt > 0 then
		entry.nextAttempt = math.min(entry.nextAttempt, nextAttempt)
	else
		entry.nextAttempt = nextAttempt
	end

	if entry.attempts > MAX_RETRY_ATTEMPTS then
		userPending[badgeId] = nil
		if next(userPending) == nil then
			pendingAwards[userId] = nil
		end
		warn(GameConfig.LOG_PREFIX, "[BadgeSystem] retry limit reached:", userId, badgeId)
		return false
	end

	return true
end

local function ShouldAttemptBadgeNow(userId, badgeId)
	local entry = GetPendingEntry(userId, badgeId)
	if not entry then
		return true
	end
	return os.clock() >= (entry.nextAttempt or 0)
end

local function GetPlayerPower(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return 0
	end
	local powerValue = leaderstats:FindFirstChild("Power")
	if not powerValue then
		return 0
	end
	if powerValue:IsA("IntValue") or powerValue:IsA("NumberValue") then
		return tonumber(powerValue.Value) or 0
	end
	return 0
end

local function GetCompletedChapters(player)
	if not player or not player:IsDescendantOf(Players) then
		return 0
	end
	local completed = DataManager.GetCompletedChapters(player)
	return tonumber(completed) or 0
end

local function SafeUserHasBadge(userId, badgeId)
	local userIdNum = tonumber(userId)
	local badgeIdNum = tonumber(badgeId)
	if not userIdNum or not badgeIdNum then
		return nil
	end
	userIdNum = userIdNum :: number
	badgeIdNum = badgeIdNum :: number

	local success, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(userIdNum, badgeIdNum)
	end)
	if not success then
		warn(GameConfig.LOG_PREFIX, "[BadgeSystem] UserHasBadgeAsync failed:", userIdNum, badgeIdNum, hasBadge)
		return nil
	end

	if hasBadge then
		MarkBadgeCached(userIdNum, badgeIdNum, true)
	end

	return hasBadge
end

local function SafeAwardBadge(userId, badgeId)
	if not RunService:IsServer() then
		return false
	end

	local userIdNum = tonumber(userId)
	local badgeIdNum = tonumber(badgeId)
	if not userIdNum or not badgeIdNum then
		return false
	end
	userIdNum = userIdNum :: number
	badgeIdNum = badgeIdNum :: number

	local awardFn = BadgeService["AwardBadgeAsync"] or BadgeService["AwardBadge"]
	if not awardFn then
		warn(GameConfig.LOG_PREFIX, "[BadgeSystem] AwardBadge method missing:", userIdNum, badgeIdNum)
		return false
	end

	local success, awarded = pcall(function()
		return awardFn(BadgeService, userIdNum, badgeIdNum)
	end)
	if not success then
		warn(GameConfig.LOG_PREFIX, "[BadgeSystem] AwardBadge failed:", userId, badgeId, awarded)
		return false
	end
	return awarded == true
end

local function AwardBadgeIfNeeded(player, badgeId)
	if not player or not player:IsDescendantOf(Players) then
		return false
	end

	local userId = player.UserId
	local badgeIdNum = tonumber(badgeId)
	if not badgeIdNum then
		return false
	end

	if HasBadgeCached(userId, badgeIdNum) then
		ClearPendingBadge(userId, badgeIdNum)
		return true
	end

	if not ShouldAttemptBadgeNow(userId, badgeIdNum) then
		return false
	end

	local hasBadge = SafeUserHasBadge(userId, badgeIdNum)
	if hasBadge == nil then
		SchedulePendingBadge(userId, badgeIdNum, "UserHasBadgeFailed")
		return false
	end
	if hasBadge then
		ClearPendingBadge(userId, badgeIdNum)
		return true
	end

	local awarded = SafeAwardBadge(userId, badgeIdNum)
	if awarded then
		MarkBadgeCached(userId, badgeIdNum, true)
		ClearPendingBadge(userId, badgeIdNum)
		print(GameConfig.LOG_PREFIX, "[BadgeSystem] Awarded badge:", userId, badgeIdNum)
		return true
	end

	local confirm = SafeUserHasBadge(userId, badgeIdNum)
	if confirm == nil then
		SchedulePendingBadge(userId, badgeIdNum, "AwardConfirmFailed")
		return false
	end
	if confirm then
		ClearPendingBadge(userId, badgeIdNum)
		return true
	end

	SchedulePendingBadge(userId, badgeIdNum, "AwardFailed")
	return false
end

local JOIN_BADGES = BadgeConfig.GetBadgesByTrigger(BadgeConfig.TriggerType.PLAYER_JOIN)
local CHAPTER_BADGES = BadgeConfig.GetChapterBadges()
local POWER_BADGES = BadgeConfig.GetPowerBadges()

local function CheckJoinBadges(player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local userId = player.UserId
	for _, badge in ipairs(JOIN_BADGES) do
		if badge and badge.Id then
			local badgeIdNum = tonumber(badge.Id)
			if badgeIdNum and not HasBadgeCached(userId, badgeIdNum) then
				if not IsPendingBadge(userId, badgeIdNum) or ShouldAttemptBadgeNow(userId, badgeIdNum) then
					AwardBadgeIfNeeded(player, badgeIdNum)
				end
			end
		end
	end
end

local function CheckPowerBadges(player, powerValue)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local userId = player.UserId
	local currentPower = tonumber(powerValue) or 0
	if currentPower <= 0 then
		return
	end

	for _, badge in ipairs(POWER_BADGES) do
		local required = tonumber(badge.RequiredPower) or 0
		if required > 0 and currentPower >= required then
			local badgeIdNum = tonumber(badge.Id)
			if badgeIdNum and not HasBadgeCached(userId, badgeIdNum) then
				if not IsPendingBadge(userId, badgeIdNum) or ShouldAttemptBadgeNow(userId, badgeIdNum) then
					AwardBadgeIfNeeded(player, badgeIdNum)
				end
			end
		end
	end
end

local function CheckChapterBadges(player, completedChapters)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local userId = player.UserId
	local completed = tonumber(completedChapters) or 0
	if completed <= 0 then
		return
	end

	for _, badge in ipairs(CHAPTER_BADGES) do
		local required = tonumber(badge.RequiredChapter) or 0
		if required > 0 and completed >= required then
			local badgeIdNum = tonumber(badge.Id)
			if badgeIdNum and not HasBadgeCached(userId, badgeIdNum) then
				if not IsPendingBadge(userId, badgeIdNum) or ShouldAttemptBadgeNow(userId, badgeIdNum) then
					AwardBadgeIfNeeded(player, badgeIdNum)
				end
			end
		end
	end
end

function BadgeSystem.CheckAllBadges(player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end
	CheckJoinBadges(player)
	local completedChapters = GetCompletedChapters(player)
	if completedChapters > 0 then
		CheckChapterBadges(player, completedChapters)
	end
	local powerValue = GetPlayerPower(player)
	if powerValue > 0 then
		CheckPowerBadges(player, powerValue)
	end
end

function BadgeSystem.OnPlayerJoin(player)
	task.spawn(function()
		if not player or not player:IsDescendantOf(Players) then
			return
		end

		CheckJoinBadges(player)

		task.delay(5, function()
			if not player or not player:IsDescendantOf(Players) then
				return
			end
			local completedChapters = GetCompletedChapters(player)
			if completedChapters > 0 then
				CheckChapterBadges(player, completedChapters)
			end
			local powerValue = GetPlayerPower(player)
			if powerValue > 0 then
				CheckPowerBadges(player, powerValue)
			end
		end)
	end)
end

function BadgeSystem.OnChapterCompleted(player, chapterId, completedChapters)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local chapterNum = tonumber(chapterId) or 0
	if chapterNum <= 0 then
		return
	end

	local completed = tonumber(completedChapters)
	if not completed then
		completed = GetCompletedChapters(player)
	end
	if completed <= 0 then
		return
	end

	task.spawn(function()
		if not player or not player:IsDescendantOf(Players) then
			return
		end
		CheckChapterBadges(player, completed)
	end)
end

function BadgeSystem.OnPowerUpdated(player, totalPower)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local powerValue = tonumber(totalPower) or 0
	if powerValue <= 0 then
		return
	end

	task.spawn(function()
		if not player or not player:IsDescendantOf(Players) then
			return
		end

		CheckPowerBadges(player, powerValue)
	end)
end

local function StartPendingProcessor()
	task.spawn(function()
		while true do
			local now = os.clock()
			for userId, badgeMap in pairs(pendingAwards) do
				local player = Players:GetPlayerByUserId(userId)
				if not player then
					pendingAwards[userId] = nil
				else
					local dueList = {}
					for badgeId, entry in pairs(badgeMap) do
						if now >= (entry.nextAttempt or 0) then
							table.insert(dueList, badgeId)
						end
					end
					for _, badgeId in ipairs(dueList) do
						AwardBadgeIfNeeded(player, badgeId)
					end
				end
			end
			task.wait(PENDING_POLL_INTERVAL)
		end
	end)
end

local function StartFullScan()
	task.spawn(function()
		while true do
			task.wait(FULL_SCAN_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				BadgeSystem.CheckAllBadges(player)
			end
		end
	end)
end

function BadgeSystem.OnPlayerLeave(player)
	if not player then
		return
	end
	badgeCache[player.UserId] = nil
	pendingAwards[player.UserId] = nil
end

function BadgeSystem.Initialize()
	Players.PlayerAdded:Connect(BadgeSystem.OnPlayerJoin)
	Players.PlayerRemoving:Connect(BadgeSystem.OnPlayerLeave)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			BadgeSystem.OnPlayerJoin(player)
		end)
	end

	StartPendingProcessor()
	StartFullScan()

	return true
end

return BadgeSystem
